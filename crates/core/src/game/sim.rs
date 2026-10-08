//! The integrated RTS simulation: two players, an economy, buildings, units,
//! combat, and a win condition — all deterministic and fixed-point.
//!
//! [`Sim::step`] advances one fixed tick by, in order: applying the ordered
//! command batch, running the economy, advancing production, moving units,
//! resolving combat, and clearing the dead. [`Sim::state_hash`] fingerprints the
//! whole thing so two runs (or two platforms, or client and server) can be proven
//! identical.

#[path = "earthfront.rs"]
mod earthfront;
pub use earthfront::{EconomyView, SupplyLink, SupplyState};
#[path = "depth.rs"]
mod depth;
pub use depth::Stance;

use crate::fixed::Fixed;
use crate::game::balance::Balance;
use crate::game::civ::{
    Civ, Colony, ColonyId, ColonyIntent, ColonyPolicy, ExpansionIntent, KardashevTier, Sector,
    SectorDoctrine, SectorId, SimDetail, Species, AUTONOMY_FULL,
};
use crate::game::hex;
use crate::game::map::{Map, Tile};
use crate::game::path::find_path;
use crate::game::planet::{Planet, PlanetId};
use crate::game::stats::{
    damage_multiplier, ArmorType, AttackProfile, BuildingKind, DamageType, UnitKind,
};
use crate::game::tech_grid::{self, TechBitset};
use crate::hash::Fnv;
use crate::rng::Rng;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// How often (in ticks) the AI re-issues move orders to idle units, throttling
/// pathfinding work.
const MOVE_REISSUE_PERIOD: u64 = 20;

/// Conquest only: how many of a civ's combat units must have gathered at the
/// staging rally before the AI COMMITS them as one focused assault on the chosen
/// enemy planet. Below this, units keep massing at a safe rally (out of the
/// target's defensive range) instead of trickling in to die one-by-one against a
/// turret ring. Tuned via the `playtest_measure_contest` harness: real combat
/// captures (held seats taken, not neutrals settled) peak around 14 — big enough
/// that a committed wave can break a turret-defended colony seat, small enough that
/// the upkeep-capped economy reaches it often. (Far larger stacks commit too rarely;
/// far smaller ones dribble in and bleed.) NOTE: the four turret-RINGED starting
/// homeworlds resist any stack the economy can field once distance-decay and the
/// defenders' standing army are counted — a balance ceiling, see the commit/report.
const ASSAULT_STACK: usize = 14;

/// Conquest only: the staging rally sits this fraction of the way from the
/// attacker's Command Center toward the assault target, kept OUT of the target's
/// defensive range so the massing stack is not bled while it gathers. Expressed
/// as a numerator over 16 (`Fixed`-friendly, no float).
const RALLY_NUM: i64 = 9;
const RALLY_DEN: i64 = 16;

/// Conquest only: a unit counts as "at the rally" (ready to commit) when within
/// this world-space radius of the rally point. Generous enough that units which
/// arrive from slightly different paths still pool, small enough that it does not
/// count units still marching across the map.
const RALLY_GATHER_RADIUS: i32 = 6;

/// Combat spatial-grid cell size in tiles. Must be >= the largest attack range
/// INCLUDING the Highland range bonus (1.25x, `Ground::Highland`), so a 3x3 cell
/// query around an attacker contains every in-range enemy. Guarded by the test
/// `combat_cell_covers_highland_extended_range`.
const COMBAT_CELL: i32 = 8;

/// Identifies a player (`0` or `1`).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct PlayerId(pub u16);

/// The identity of a civilization. Same newtype as [`PlayerId`]; the alias
/// documents that an id now denotes a civ, not a 1-of-2 player slot.
pub type CivId = PlayerId;

/// Stable handle to an entity (index into the entity list).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct EntityId(pub u32);

/// What an entity is.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum Kind {
    Building(BuildingKind),
    Unit(UnitKind),
}

/// A simulated entity — a building or a unit.
#[derive(Clone, Debug)]
struct Entity {
    owner: PlayerId,
    kind: Kind,
    alive: bool,
    pos: Vec2,
    hp: Fixed,
    /// Current energy shield (absorbs damage before HP).
    shield: Fixed,
    /// Tick the entity was last hit (drives out-of-combat shield regen).
    last_combat_tick: u32,
    cooldown: u32,
    move_target: Option<Vec2>,
    /// The point the last order was GIVEN, before earthfront substituted a passable tile
    /// for an impassable goal (`move_target` then holds the substitute). Harvesters compare
    /// against this so a returning truck is not re-pathed every tick. Derived from the
    /// order, never read by combat or hashing.
    order_goal: Option<Vec2>,
    /// Remaining tile waypoints toward `move_target` (from A*), nearest first.
    path: Vec<(u16, u16)>,
    tile: Option<(u16, u16)>,
    build_queue: Vec<UnitKind>,
    build_progress: u32,
    /// Ticks until a placed structure becomes operational.
    construction_remaining: u32,
    /// Original construction duration, retained for UI progress.
    construction_total: u32,
    /// Confirmed kills, accumulated for veterancy.
    kills: u32,
    /// Veterancy rank (0..=3), derived from `kills`; boosts outgoing damage.
    rank: u8,
    /// Ticks until this unit's ability is ready again (0 = ready).
    ability_cd: u32,
    /// Remaining EMP-stun ticks: while > 0 the entity neither moves nor fires.
    stun_ticks: u32,
    /// Post-stun hardening: while > 0 a fresh EMP cannot re-stun this entity, so
    /// massed casters can never chain-stun a clump into a permanent lock (max
    /// stun uptime = duration / (duration + `STUN_IMMUNITY`)).
    stun_immunity: u32,
    /// Attack-move flag: when `true`, the unit halts its advance toward
    /// `move_target` whenever an enemy is within its weapon range (standing to
    /// fight via the existing auto-fire), and resumes once the area is clear.
    /// Set by [`Command::AttackMove`], cleared by a plain [`Command::Move`] and
    /// on arrival. Genuine mutable per-entity state, so it is folded into
    /// [`Sim::state_hash`].
    attack_move: bool,
    /// Ore currently carried by an economy vehicle.
    cargo: u32,
    /// A loaded harvester is returning to the nearest friendly Refinery.
    harvest_returning: bool,
    /// Producer destination inherited by newly completed units.
    rally: Option<Vec2>,
    // Earthfront-only authoritative per-entity service state.
    power_fraction: u32,
    work_fraction: u32,
    ammunition: u32,
    supply_stock: u32,
    ore_buffer: u32,
    objective_role: earthfront::ObjectiveRole,
    /// Kestrel depth per-entity state; hashed only when depth is on.
    dp: depth::DepthUnit,
}

const HARVEST_CAPACITY: u32 = 100;
const HARVEST_CHUNK: u32 = 10;
const HARVEST_PERIOD: u64 = 10;
const HARVEST_RANGE_SQ: Fixed = Fixed::from_int(2);

/// Ticks of EMP immunity granted when a stun wears off — twice the stun length,
/// capping worst-case stun uptime at one third even against massed casters.
const STUN_IMMUNITY: u32 = 90;

/// Engagement leash (world units) for an attack-moving unit that has NO weapon:
/// it halts its advance when an enemy comes this close, letting armed escorts
/// catch up and fight. Armed units use their own weapon range instead.
const ATTACK_MOVE_LEASH: Fixed = Fixed::from_int(4);

/// Supply-decay full-strength radius (tiles). A UNIT firing within this distance
/// of its owner's nearest Command Center deals 100% damage — fighting at or near
/// a base/owned planet is unpenalised.
const SUPPLY_FULL_RADIUS: Fixed = Fixed::from_int(6);
/// Supply-decay outer radius (tiles). Beyond this distance from any friendly
/// Command Center, a unit's outgoing damage bottoms out at [`SUPPLY_DECAY_FLOOR`]
/// (overextension penalty). Between [`SUPPLY_FULL_RADIUS`] and here the factor
/// ramps down linearly (in squared distance — monotonic, no sqrt needed).
const SUPPLY_DECAY_RADIUS: Fixed = Fixed::from_int(20);
/// Minimum outgoing-damage multiplier for a fully-overextended unit (0.6 = 40%
/// penalty). Gentle by design: this nudges forward-basing, it doesn't gut deep
/// strikes.
const SUPPLY_DECAY_FLOOR: Fixed = Fixed::from_ratio(3, 5);

/// Outgoing-damage multiplier for a unit firing at squared distance `dist_sq`
/// (world units²) from its owner's NEAREST friendly Command Center.
///
/// Returns a [`Fixed`] in `[SUPPLY_DECAY_FLOOR, 1]`:
/// - `<= SUPPLY_FULL_RADIUS²`  → `1` (full strength plateau).
/// - `>= SUPPLY_DECAY_RADIUS²` → `SUPPLY_DECAY_FLOOR`.
/// - between                  → linear ramp **in squared distance** (monotonically
///   decreasing; cheaper and exact in `Fixed` since it avoids a square root).
///
/// Pass `None` for `dist_sq` when the owner has NO Command Center (just lost their
/// last seat) — they get a `1` factor so a losing player isn't double-punished.
/// Deterministic: `Fixed`/integer only, no rng, no float, no sqrt.
fn supply_decay_factor(dist_sq: Option<Fixed>) -> Fixed {
    let Some(d_sq) = dist_sq else {
        return Fixed::ONE;
    };
    let full_sq = SUPPLY_FULL_RADIUS * SUPPLY_FULL_RADIUS;
    if d_sq <= full_sq {
        return Fixed::ONE;
    }
    let decay_sq = SUPPLY_DECAY_RADIUS * SUPPLY_DECAY_RADIUS;
    if d_sq >= decay_sq {
        return SUPPLY_DECAY_FLOOR;
    }
    // Linear interpolation on squared distance: t in (0,1) maps the band
    // (full_sq, decay_sq) onto a 1 → FLOOR descent. `decay_sq > full_sq` here, so
    // the divisor is strictly positive.
    let t = (d_sq - full_sq) / (decay_sq - full_sq);
    Fixed::ONE - t * (Fixed::ONE - SUPPLY_DECAY_FLOOR)
}

/// Veterancy rank for a given kill count (0 → 3, capped).
const fn rank_for_kills(kills: u32) -> u8 {
    if kills >= 9 {
        3
    } else if kills >= 5 {
        2
    } else if kills >= 2 {
        1
    } else {
        0
    }
}

/// Outgoing-damage multiplier for a veterancy rank: +0%, +10%, +20%, +35%.
const fn veterancy_factor(rank: u8) -> Fixed {
    match rank {
        0 => Fixed::ONE,
        1 => Fixed::from_ratio(11, 10),
        2 => Fixed::from_ratio(6, 5),
        _ => Fixed::from_ratio(27, 20),
    }
}

/// Base population allowance before any production buildings.
const SUPPLY_BASE: u32 = 10;
/// Extra population headroom per Command Center.
const SUPPLY_PER_CC: u32 = 6;
/// Extra population headroom per Barracks.
const SUPPLY_PER_BARRACKS: u32 = 5;
/// Extra population headroom per Reactor — so surplus Minerals convert into a
/// bigger army (build reactors → raise the cap → field more units vs the waves).
const SUPPLY_PER_REACTOR: u32 = 4;
/// Advancing command technology grants headroom for newly unlocked heavy units.
const SUPPLY_PER_ERA: u32 = 4;
/// Army supply each colony population point contributes (city → army coupling).
const SUPPLY_PER_POP: u32 = 1;
/// Extra production-building slots each colony population point unlocks.
const BUILDINGS_PER_POP: u32 = 2;
/// Population headroom each housing building (the Command Center, in this slice)
/// adds to a colony's cap.
const HOUSING_PER_BUILDING: u32 = 2;
/// Population needed per +1 to a colony's autonomy-earning rate: a colony earns
/// `1 + population / AUTONOMY_POP_DIVISOR` autonomy progress per qualifying tick.
const AUTONOMY_POP_DIVISOR: u32 = 4;
/// How many live Ore Extractors the AI expands to before it stops claiming new
/// Ore deposits. Bounds map-wide refinery sprawl while still letting the AI
/// re-claim a fresh deposit when an old one depletes.
const MAX_AI_EXTRACTORS: usize = 4;
/// How many live Alloy Extractors the AI secures. Alloy is the scarce second
/// resource that fuels Capital ships, so the AI deliberately claims a couple of
/// Alloy deposits rather than spending its whole extractor budget on Ore.
const MAX_AI_ALLOY_EXTRACTORS: usize = 2;
/// Production buildings the AI will field. Bounds Barracks/Reactor expansion so
/// surplus Minerals raise the supply ceiling to a healthy army — not an absurd
/// map-carpeting one that wrecks its own defensive footprint.
const MAX_AI_BARRACKS: usize = 4;
const MAX_AI_REACTORS: usize = 8;
/// Once advanced research starts, leave room for the first heavy flagship
/// instead of allowing cheap infantry to consume every new supply slot.
const AI_CAPITAL_SUPPLY_RESERVE: u32 = 2;
/// Money an autonomous colony spends to found a new colony.
const FOUND_COLONY_COST: Fixed = Fixed::from_int(800);
/// Hard safety ceiling on auto-founded colonies per owner (the per-species
/// [`Species::colony_cap`](crate::game::civ::Species::colony_cap) is the soft
/// limit; this just bounds the worst case).
const MAX_COLONIES_PER_OWNER: usize = 8;
/// Minimum tile spacing between a new colony and every existing Command Center.
const MIN_COLONY_SPACING: u16 = 6;
/// Extra attackers per wave for each colony the defender holds — the coupling
/// that makes a bigger empire face proportionally harder sieges (scale forces
/// the strategic layer). Zero colonies ⇒ legacy waves are unchanged.
const EMPIRE_WAVE_PRESSURE: u32 = 2;
/// Per-colony step of the super-linear empire-administration upkeep, charged in
/// Money every economy tick. Total upkeep for an `n`-colony empire is
/// `UPKEEP_STEP × n·(n−1)/2` (triangular): colony `k` costs `UPKEEP_STEP·(k−1)`,
/// so the FIRST colony is free and each extra colony costs more than the last
/// (1→0, 2→1·step, 3→3·step, 4→6·step, 8→28·step). This is the "wide empires
/// cost more to administer" 4X brake: a runaway leader pays disproportionately
/// more upkeep per colony than a trailing 2–3 colony follower, so expansion is
/// self-limiting and trailing civs get room to contest. Keyed off owned-COLONY
/// count (administrative empire size), which is ZERO in the colony-free golden
/// survival run, so this is golden-neutral. Tuning magnitude is deliberately
/// modest pending playtest.
const UPKEEP_STEP: Fixed = Fixed::from_int(1);
/// Ceiling on the Energy stockpile — a bounded, spend-it-or-cap-it resource
/// rather than a runaway counter. Must be ≥ the most expensive grid node's
/// Energy cost (currently 14000) or that node — and any era it gates — becomes
/// permanently unresearchable; see `every_grid_node_is_affordable`.
const ENERGY_CAP: Fixed = Fixed::from_int(15000);
/// Ceiling on the Labour (population) stockpile. Must be ≥ the most expensive
/// grid node's Labour cost (currently 14000); the old 800 cap made 283 nodes —
/// including the Era-3 key and the Capital ship — unaccumulable and so dead
/// content. Guarded by `every_grid_node_is_affordable`.
const LABOUR_CAP: Fixed = Fixed::from_int(15000);

/// Hard resolution cap for a CONQUEST game, in ticks (~20 min @ 30 Hz). A fully
/// fortified 4-civ standoff can outlast a single-survivor decision indefinitely, so
/// once `self.tick` reaches this cap [`Sim::winner`] resolves to the deterministic
/// leader rather than running forever. SURVIVAL is unaffected — it ends only when
/// the human's base falls. Read-only in `winner()` from the already-hashed `self.tick`
/// (no new hashed state), so it is golden-neutral and lockstep-safe.
const CONQUEST_TICK_CAP: u64 = 36_000;
/// Domination threshold: an alive civ owning a STRICT majority — more than this
/// percent — of all planets wins a conquest game immediately. Read from current
/// ownership (no per-civ counter is added to the hashed state), so it is
/// instantaneous and golden-neutral.
const DOMINATION_PERCENT: usize = 60;

/// Clamps `v` to at most `max` (non-const: `Fixed`'s `Ord` isn't usable in const).
fn cap_at(v: Fixed, max: Fixed) -> Fixed {
    if v > max {
        max
    } else {
        v
    }
}

// === Ascendancy Doctrines ===
// Endless, escalating-cost upgrade tracks that turn a late-game resource surplus
// into army QUALITY (not quantity) under the hard supply cap. Four tracks, not
// mutually exclusive, no prereq. The next level's cost rises linearly with the
// level already bought, so it keeps pace with — then outgrows — income, draining
// the surplus forever instead of letting it bank. Effects fold into the existing
// per-player weapon/armor/shield accessors, so the combat code is untouched.
/// Number of doctrine tracks.
pub const DOCTRINE_TRACKS: usize = 4;
/// Hard ceiling on a track's level (keeps Fixed bits + hash width bounded).
const DOCTRINE_LEVEL_CAP: u16 = 9999;
/// Track index: army-wide flat weapon damage (research-heavy).
const DOC_WEAPONS: usize = 0;
/// Track index: army-wide flat armor mitigation (research-heavy).
const DOC_ARMOR: usize = 1;
/// Track index: army-wide shield-max (research-heavy survivability).
const DOC_VITALITY: usize = 2;
/// Track index: the money-only bank-drainer (steep escalating lump cost).
const DOC_FORGE: usize = 3;
/// Per-track cost ramp: cost(level L→L+1) = base + step * L. Minerals component.
const DOCTRINE_MIN_BASE: [i32; DOCTRINE_TRACKS] = [300, 300, 300, 2000];
const DOCTRINE_MIN_STEP: [i32; DOCTRINE_TRACKS] = [120, 120, 120, 900];
/// Research component of the cost ramp (FORGE is money-only ⇒ 0).
const DOCTRINE_RES_BASE: [i32; DOCTRINE_TRACKS] = [500, 500, 400, 0];
const DOCTRINE_RES_STEP: [i32; DOCTRINE_TRACKS] = [180, 180, 150, 0];
/// Per-level effect of the WEAPONS track: +1 flat damage. The effect is endless
/// by design (capped only at `DOCTRINE_LEVEL_CAP`); the steeply escalating
/// per-level research+money cost (see `ascend_cost`) is the sole brake — by the
/// time a level is cheap relative to income, the wave curve has long outgrown it.
const WEAPON_STEP: Fixed = Fixed::from_int(1);
/// Per researched grid node, the flat rider to its branch's combat/economy effect
/// (Weapons→dmg, Defense→armor+shield, Energy→income, Propulsion→speed).
const GRID_WEAPON_PER_NODE: Fixed = Fixed::from_ratio(1, 2);
const GRID_ARMOR_PER_NODE: Fixed = Fixed::from_ratio(1, 4);
const GRID_SHIELD_PER_NODE: Fixed = Fixed::from_int(4);
const GRID_ECON_PER_NODE: Fixed = Fixed::from_ratio(1, 2);
const GRID_MOB_PER_NODE: Fixed = Fixed::from_ratio(1, 100);
/// Per-level effect of the ARMOR track: +0.5 flat mitigation (half-steps blunt
/// swarms without granting immunity — the ≥1-damage clamp still applies).
const ARMOR_STEP: Fixed = Fixed::from_ratio(1, 2);
/// Per-level effect of the VITALITY track: +8 shield-max.
const VITALITY_STEP: Fixed = Fixed::from_int(8);
/// Per-level FORGE bonuses: a small flat weapon AND armor buff, so a FORGE level
/// is a real purchase — and its steep, escalating money-only lump cost is the
/// bank-drainer. The AI keeps `ASCEND_MIN_RESERVE` in hand, so the surplus churns
/// down to a low equilibrium (continually buying levels) instead of sitting idle,
/// while never starving unit retraining.
const FORGE_WEAPON_STEP: Fixed = Fixed::from_ratio(1, 4);
const FORGE_ARMOR_STEP: Fixed = Fixed::from_ratio(1, 4);
/// Minerals granted for founding the Command Center adjacent to an Ore deposit —
/// the survey phase's premium-site payoff.
const FOUNDING_ORE_BONUS: Fixed = Fixed::from_int(200);
/// The AI only ascends with at least this much money in reserve (and era ≥ 1),
/// so the 120-tick golden run — which never reaches era 1 — never emits an Ascend
/// and the golden hash stays stable across future balance tuning of the sink.
const ASCEND_MIN_RESERVE: Fixed = Fixed::from_int(2000);

/// A player or AI input, applied at a tick boundary.
#[derive(Clone, Debug)]
pub enum Command {
    /// Construct a building on a tile (costs money; tile must be buildable).
    Build {
        /// Owning player.
        owner: PlayerId,
        /// What to build.
        kind: BuildingKind,
        /// Tile column.
        x: u16,
        /// Tile row.
        y: u16,
    },
    /// Queue a unit for training at a barracks (costs money).
    Train {
        /// Owning player.
        owner: PlayerId,
        /// The barracks entity.
        barracks: EntityId,
        /// What to train.
        kind: UnitKind,
    },
    /// Set a Barracks or Refinery rally point for newly completed units.
    SetRally {
        /// Owning player.
        owner: PlayerId,
        /// Producer whose rally point changes.
        producer: EntityId,
        /// Destination assigned to new units.
        target: Vec2,
    },
    /// Repair one owned building by a fixed health chunk, paying credits.
    Repair {
        /// Owning player.
        owner: PlayerId,
        /// Structure to repair.
        building: EntityId,
    },
    /// Sell one owned non-HQ building for half of its construction price.
    Sell {
        /// Owning player.
        owner: PlayerId,
        /// Structure to sell.
        building: EntityId,
    },
    /// Order a unit to move to a world position.
    Move {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
        /// Destination.
        target: Vec2,
    },
    /// Order a unit to ATTACK-MOVE to a world position: it advances toward the
    /// point but STOPS to fight any enemy that comes within its weapon range
    /// en route (the existing auto-fire deals the damage), resuming once the
    /// area is clear. Clears itself on arrival. Contrast with [`Command::Move`],
    /// which marches straight to the point and never stops for a fight.
    AttackMove {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
        /// Destination.
        target: Vec2,
    },
    /// Begin researching a tech (costs money; needs a research lab; powered to progress).
    Research {
        /// Owning player.
        owner: PlayerId,
        /// Tech id to research.
        tech_id: u32,
    },
    /// Draft a survival perk (a one-time permanent run upgrade).
    ChoosePerk {
        /// Owning player.
        owner: PlayerId,
        /// Perk id (see [`crate::game::perk`]).
        perk: u32,
    },
    /// Buy the next level of an endless Ascendancy Doctrine track (spends Minerals
    /// and Research; rising cost is the rate limiter). See `DOC_*` track indices.
    Ascend {
        /// Owning player.
        owner: PlayerId,
        /// Track index (0..`DOCTRINE_TRACKS`).
        track: u8,
    },
    /// Found the Command Center on a surveyed tile — the act that starts the
    /// game. Only valid in the Survey phase; resolves instantly.
    FoundBase {
        /// Owning player.
        owner: PlayerId,
        /// Tile column.
        x: u16,
        /// Tile row.
        y: u16,
    },
    /// Cast a unit's active ability at a world position (see [`crate::game::ability`]).
    /// Validated and resolved instantly; the per-unit cooldown is the rate limiter.
    UseAbility {
        /// Owning player.
        owner: PlayerId,
        /// The casting unit.
        unit: EntityId,
        /// Target point — must be within the ability's range of the caster.
        target: Vec2,
    },
    /// Set a colony's requested autonomy level (the *effective* level is still
    /// capped by what the colony has earned). Player → colony configuration.
    SetColonyAutonomy {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// Requested autonomy `0..=9`.
        level: u8,
    },
    /// Replace a colony's standing policy (the stances it executes autonomously).
    SetColonyPolicy {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// The new policy.
        policy: ColonyPolicy,
    },
    /// Issue a one-shot directive overriding a colony's standing policy.
    DirectColony {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// The override intent (`Auto` clears it).
        intent: ColonyIntent,
    },
    /// Survey a special resource at a colony — marks it Extractable so it starts
    /// accruing into the colony's stockpile. (Tech adoption drives this later.)
    SurveySpecial {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// Which special resource to survey.
        kind: crate::game::civ::special::SpecialKind,
    },
    /// Found a new colony for `owner` on a surveyed buildable tile — places a
    /// Command Center and registers a [`Colony`] on it. Costs Money; the engine
    /// of empire growth. (`parent` is informational: who initiated it.)
    FoundColony {
        /// Owning player.
        owner: PlayerId,
        /// The colony that initiated the expansion (informational).
        parent: ColonyId,
        /// Tile column for the new Command Center.
        x: u16,
        /// Tile row for the new Command Center.
        y: u16,
    },
    /// Create a new governance sector for `owner` with the given doctrine. The
    /// new sector takes the lowest free slot; the UI finds it by scanning.
    FoundSector {
        /// Owning player.
        owner: PlayerId,
        /// The doctrine the new sector starts with.
        doctrine: SectorDoctrine,
    },
    /// Place `colony` under `sector`'s governance (both must belong to `owner`).
    /// The sector's doctrine then supplies the colony's standing policy.
    AssignColonyToSector {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// The sector to join.
        sector: SectorId,
    },
    /// Change a sector's governance doctrine; its member colonies re-sync their
    /// policy to it on the following ticks.
    SetSectorDoctrine {
        /// Owning player.
        owner: PlayerId,
        /// Target sector.
        sector: SectorId,
        /// The doctrine to apply.
        doctrine: SectorDoctrine,
    },
    /// One-shot governance: place `colony` under one of `owner`'s sectors with the
    /// given doctrine, reusing an existing such sector or founding one. A
    /// convenience composite of [`FoundSector`](Self::FoundSector) +
    /// [`AssignColonyToSector`](Self::AssignColonyToSector) for one-press UI.
    GovernColony {
        /// Owning player.
        owner: PlayerId,
        /// Target colony.
        colony: ColonyId,
        /// The doctrine to govern it with.
        doctrine: SectorDoctrine,
    },
    /// Kestrel depth only (a no-op elsewhere): the unit drops its orders,
    /// engagement and forced target and stands where it is (its new anchor).
    /// Its stance is kept.
    Stop {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
    },
    /// Kestrel depth only: [`Command::Stop`] plus the [`Stance::Hold`] stance.
    HoldPosition {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
    },
    /// Kestrel depth only: sets how the unit fights on its own.
    SetStance {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
        /// The new stance.
        stance: Stance,
    },
    /// Kestrel depth only: the unit walks into weapon range of `target` and
    /// fires at nothing else while it lives. Ignored unless the target is a
    /// living enemy on a layer the unit's weapon reaches.
    AttackTarget {
        /// Owning player.
        owner: PlayerId,
        /// The attacking unit.
        unit: EntityId,
        /// The enemy entity to focus.
        target: EntityId,
    },
    /// Kestrel depth only (a shift-click): appends a waypoint leg to the
    /// unit's queue, walked after its current player order (a move, an
    /// attack-move or a forced target). A unit with no player order starts the
    /// leg at once. At most [`QUEUE_CAP`](depth::QUEUE_CAP) legs in all,
    /// counting the one under way; more are dropped. Harvesters never queue.
    QueueMove {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
        /// The leg's destination.
        target: Vec2,
        /// Whether the leg is an attack-move (halts for enemies in range).
        attack_move: bool,
    },
}

/// Building or unit, for the render/UI layer (public projection of the internal
/// entity kind).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum EntityKindView {
    /// A building of the given kind.
    Building(BuildingKind),
    /// A unit of the given kind.
    Unit(UnitKind),
}

/// A read-only snapshot of one living entity, for rendering and UI.
#[derive(Clone, Copy, Debug)]
pub struct EntityView {
    /// Stable handle, for issuing commands back to the sim.
    pub id: EntityId,
    /// Owning player.
    pub owner: PlayerId,
    /// Building or unit (and which kind).
    pub kind: EntityKindView,
    /// World position.
    pub pos: Vec2,
    /// Current health.
    pub hp: Fixed,
    /// Maximum health (for health bars).
    pub max_hp: Fixed,
    /// Current energy shield.
    pub shield: Fixed,
    /// Maximum energy shield (owner's researched shield max).
    pub max_shield: Fixed,
    /// Ticks until this unit's ability is ready (0 = ready; see [`crate::game::ability`]).
    pub ability_cd: u32,
    /// Remaining EMP-stun ticks (> 0 ⇒ the entity can't move or fire).
    pub stun_ticks: u32,
    /// Ore carried by a Harvester (zero for every other entity).
    pub cargo: u32,
    /// Rally destination for a producer, if one is set.
    pub rally: Option<Vec2>,
    /// Ticks until this structure becomes operational (zero for units/completed buildings).
    pub construction_remaining: u32,
    /// Total authoritative construction duration.
    pub construction_total: u32,
}

/// Read-only status of a structure's active production queue.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProductionView {
    /// Unit currently at the front of the queue.
    pub unit: UnitKind,
    /// Total entries in this producer's queue, including the active entry.
    pub queued: u32,
    /// Ticks already invested in the active entry.
    pub progress: u32,
    /// Total ticks required to complete the active entry.
    pub duration: u32,
}

/// Configures periodic enemy waves — the attack/defend loop.
///
/// Every `interval` ticks (after `first_delay`) a growing group of `unit`s
/// spawns at `spawn` for `attacker` and attack-moves toward `defender`'s base.
#[derive(Clone, Copy, Debug)]
pub struct WaveConfig {
    /// Ticks before the first wave.
    pub first_delay: u64,
    /// Ticks between waves.
    pub interval: u64,
    /// Units in the first wave.
    pub base_size: u32,
    /// Extra units added per subsequent wave.
    pub growth: u32,
    /// World position units spawn at.
    pub spawn: Vec2,
    /// What to spawn (the base unit; ignored per-unit when `escalate` is set).
    pub unit: UnitKind,
    /// Player the wave belongs to.
    pub attacker: PlayerId,
    /// Player the wave marches against.
    pub defender: PlayerId,
    /// Survival escalation: when set, later waves broaden their composition
    /// (anti-armor, tanks, then air) and a Capital "boss" joins every 5th wave.
    pub escalate: bool,
}

/// Survival wave composition: which unit a given index in wave `wave` spawns as.
/// Broadens deterministically over time so the player must diversify defenses.
const fn escalating_unit(wave: u32, i: u32) -> UnitKind {
    match wave {
        0..=1 => UnitKind::Infantry,
        2..=3 => {
            if i.is_multiple_of(3) {
                UnitKind::AntiArmor
            } else {
                UnitKind::Infantry
            }
        }
        4..=6 => match i % 3 {
            0 => UnitKind::Tank,
            1 => UnitKind::AntiArmor,
            _ => UnitKind::Infantry,
        },
        _ => match i % 4 {
            0 => UnitKind::Tank,
            1 => UnitKind::Helicopter,
            2 => UnitKind::AntiArmor,
            _ => UnitKind::Infantry,
        },
    }
}

/// Cost in `(money, research)` to buy the next level of doctrine `track` when
/// the current level is `level`. Linear ramp `base + step * level` — exact in
/// fixed-point, no float, so it stays clippy-clean and bit-identical everywhere.
fn ascend_cost(track: usize, level: u16) -> (Fixed, Fixed) {
    let l = Fixed::from_int(i32::from(level));
    let money =
        Fixed::from_int(DOCTRINE_MIN_BASE[track]) + Fixed::from_int(DOCTRINE_MIN_STEP[track]) * l;
    let research =
        Fixed::from_int(DOCTRINE_RES_BASE[track]) + Fixed::from_int(DOCTRINE_RES_STEP[track]) * l;
    (money, research)
}

/// The high-level game phase: surveying (choosing where to found the base)
/// or active play. Survival starts in Survey; skirmish starts Active.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum GamePhase {
    /// No human base yet — the player is choosing a founding site. The wave
    /// clock is frozen and an absent Command Center is not a loss.
    Survey,
    /// Normal play; the wave clock measures from `phase_started`.
    Active,
}

/// The deterministic RTS world.
#[derive(Clone, Debug)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent mode switches (survival, lod_skip, earthfront, depth), not one state machine"
)]
pub struct Sim {
    /// Test-only count of `order_unit_to` calls (pins that harvesters do not re-path every tick).
    #[cfg(test)]
    order_calls: u64,
    /// Test-only count of Kestrel depth breach searches (Task 16: at most one
    /// per unit per order target).
    #[cfg(test)]
    breach_searches: u64,
    tick: u64,
    rng: Rng,
    map: Map,
    civs: Vec<Civ>,
    /// The human-controlled civ (P0 by convention). Used by [`Sim::winner`] in
    /// survival mode to decide whose Command Center loss ends the run.
    human_civ: CivId,
    entities: Vec<Entity>,
    /// Indices of dead entity slots available for reuse, so long matches don't
    /// grow the entity list without bound.
    free: Vec<u32>,
    waves: Option<WaveConfig>,
    wave_count: u32,
    /// Survey (pre-founding) vs Active play. Hashed.
    phase: GamePhase,
    /// Tick at which Active play began (0 unless founded mid-run). The wave
    /// clock measures from here, so survey time never eats the peace window.
    phase_started: u64,
    /// Earthfront mission mode: the human loses when their Command Center falls
    /// and wins by destroying every hostile Command Center. Set at construction;
    /// it only changes [`Sim::winner`] (a query), not hashed state.
    survival: bool,
    balance: Balance,
    /// Transient render hint: (attacker, target) world positions of shots fired
    /// on the most recent combat tick. Deterministically derived, so it is not
    /// part of the state hash.
    attacks: Vec<(Vec2, Vec2)>,
    /// The autonomous-civilization layer: colonies that drive themselves through
    /// the command channel (see [`crate::game::civ`]). Hashed. Empty in the
    /// legacy single-base scenarios, so they behave exactly as before.
    colonies: Vec<Colony>,
    /// Recycled colony slots (LIFO), mirroring [`Sim::free`] for entities.
    colony_free: Vec<u32>,
    /// The governance layer: sectors grouping colonies under a doctrine (see
    /// [`crate::game::civ::Sector`]). Hashed; empty in the legacy scenarios.
    sectors: Vec<Sector>,
    /// Recycled sector slots (LIFO), mirroring [`Sim::colony_free`].
    sector_free: Vec<u32>,
    /// Planetary territory: discrete, event-driven ownership (settle / capture).
    /// Hashed. Empty in legacy scenarios, so the only delta is a zero-length
    /// marker. Tile membership is static on the [`Map`]; only control lives here.
    planets: Vec<Planet>,
    /// World seed for sampling static special-resource fields (see
    /// [`crate::game::civ::special`]). Immutable; sampled without touching `rng`.
    field_seed: u64,
    /// Whether [`Dormant`](crate::game::civ::SimDetail::Dormant) colonies skip
    /// their per-tick scalar passes and catch up in closed form. Always `true` in
    /// real play; tests flip it off to assert the skip path is bit-identical to a
    /// full-fidelity run every tick (determinism rule D3). Not hashed — it changes
    /// *how* the same hashed state is produced, never the state itself.
    lod_skip: bool,
    /// Per-planet aggregate terrain yield (`[food, money, energy, labour]`),
    /// indexed by [`PlanetId`]. A derived cache over the static terrain layer;
    /// rebuilt via [`Sim::rebuild_planet_yield`] and never folded into
    /// `state_hash` (like the terrain layer it summarizes).
    planet_yield: Vec<[Fixed; 4]>,
    /// Per-planet tile count, indexed by [`PlanetId`]. A derived cache over the
    /// static planet-membership layer; rebuilt via [`Sim::rebuild_planet_yield`]
    /// in the same tile scan and never folded into `state_hash` (like
    /// `planet_yield`).
    planet_tiles: Vec<u32>,
    earthfront: bool,
    earthfront_wave_doctrine: u8,
    /// Kestrel depth rules (see `depth.rs`): set only by `kestrel_reach` via
    /// [`Sim::enable_depth`] and always read through [`Sim::is_depth`]
    /// (`earthfront && depth`). Its state below is hashed only when on.
    depth: bool,
    /// Kestrel depth world-wide state; hashed only when depth is on.
    dg: depth::DepthGlobal,
}

/// Narrows an `i128` accumulator to `i64`, saturating at the bounds rather than
/// wrapping (determinism rule D6: identical in debug and release).
#[allow(
    clippy::cast_possible_truncation,
    reason = "the else branch only casts when v is within i64 range"
)]
const fn saturate_i64(v: i128) -> i64 {
    if v > i64::MAX as i128 {
        i64::MAX
    } else if v < i64::MIN as i128 {
        i64::MIN
    } else {
        v as i64
    }
}

/// The D3 closed form: `stored + rate * elapsed`, widened to i128 and saturated
/// back to a Fixed's i64 bits. This is the SINGLE definition of the per-tick
/// accumulator catch-up — it MUST be the only place this math lives, because the
/// hash reconstruction (`hash_colony_layer`) and the banking (`materialize_colony`)
/// have to be bit-identical or Dormant-skip diverges from full simulation
/// (determinism rule D3).
#[inline]
fn closed_form_bits(stored: Fixed, rate: Fixed, elapsed: u64) -> i64 {
    saturate_i64(i128::from(stored.to_bits()) + i128::from(rate.to_bits()) * i128::from(elapsed))
}

const fn armor_of(balance: &Balance, kind: Kind) -> ArmorType {
    match kind {
        Kind::Unit(u) => balance.unit(u).armor,
        Kind::Building(b) => balance.building(b).armor,
    }
}

const fn attack_of(balance: &Balance, kind: Kind) -> Option<AttackProfile> {
    match kind {
        Kind::Unit(UnitKind::Harvester) => None,
        Kind::Unit(u) => Some(balance.unit(u).attack),
        Kind::Building(b) => balance.building(b).attack,
    }
}

const fn max_hp(balance: &Balance, kind: Kind) -> Fixed {
    match kind {
        Kind::Unit(u) => balance.unit(u).max_hp,
        Kind::Building(b) => balance.building(b).max_hp,
    }
}

/// Vehicles (wheeled/tracked) follow `vehicle_pct`; foot units follow `infantry_pct`.
const fn is_vehicle(k: UnitKind) -> bool {
    matches!(k, UnitKind::Harvester | UnitKind::Tank | UnitKind::Capital)
}

/// Floor on the ground speed multiplier so no unit ever freezes in place.
const MIN_GROUND_SPEED_PCT: u32 = 30;

/// Speed percent (Earthfront) for a unit of kind `uk` standing at `pos`: 100 for air units,
/// else the standing tile's infantry/vehicle percent, clamped to `MIN_GROUND_SPEED_PCT`.
fn ground_speed_pct(map: &Map, pos: Vec2, uk: UnitKind) -> u32 {
    if uk.stats().is_air {
        return 100;
    }
    let (tx, ty) = crate::game::hex::from_world(pos, map.width(), map.height());
    let g = map.ground_at(i32::from(tx), i32::from(ty)).props();
    let pct = if is_vehicle(uk) {
        g.vehicle_pct
    } else {
        g.infantry_pct
    };
    pct.max(MIN_GROUND_SPEED_PCT)
}

/// Rules (cover / range bonus) of the ground under world position `pos` (Earthfront).
fn ground_props_at(map: &Map, pos: Vec2) -> crate::game::map::GroundProps {
    let (tx, ty) = crate::game::hex::from_world(pos, map.width(), map.height());
    map.ground_at(i32::from(tx), i32::from(ty)).props()
}

/// A small percent as `i32` for `Fixed::from_int` (ground percents are tiny; saturates).
fn pct_i32(p: u32) -> i32 {
    i32::try_from(p).unwrap_or(i32::MAX)
}

/// Percent of damage that gets through `cover_pct` of cover (never underflows).
const fn through_cover_pct(cover_pct: u32) -> u32 {
    100u32.saturating_sub(cover_pct)
}

/// World-space center of hex cell `(x, y)`.
fn tile_center(x: u16, y: u16) -> Vec2 {
    crate::game::hex::center(x, y)
}

const fn unit_tag(u: UnitKind) -> u64 {
    match u {
        UnitKind::Infantry => 1,
        UnitKind::Tank => 2,
        UnitKind::AntiArmor => 3,
        UnitKind::Helicopter => 4,
        UnitKind::Capital => 5,
        UnitKind::Harvester => 6,
    }
}

/// Per-era attack-damage multiplier: (7/5)^era. Era 0 (Modern) is neutral.
const fn era_damage_factor(era: u8) -> Fixed {
    match era {
        0 => Fixed::ONE,
        1 => Fixed::from_ratio(7, 5),
        2 => Fixed::from_ratio(49, 25),
        _ => Fixed::from_ratio(343, 125),
    }
}

/// The attack-move halt scan: whether any living enemy in `snap` (the
/// pre-tick `(alive, owner, pos, is_air)` snapshot) stands within the
/// engagement range of entity `i` (`e`): its weapon range, or
/// [`ATTACK_MOVE_LEASH`] when unarmed. Ascending index, first hit wins. Under
/// Kestrel depth an enemy the weapon cannot reach (a gunship over a rifle,
/// the `run_combat` layer test) never halts the advance, and the weapon is
/// the depth one (Task 15: an `AntiArmor` team reaches air).
fn attack_move_halts(
    snap: &[(bool, u16, Vec2, bool)],
    i: usize,
    e: &Entity,
    balance: &Balance,
    depth: bool,
) -> bool {
    let profile = depth::weapon_of(balance, e.kind, depth);
    let leash = profile.map_or(ATTACK_MOVE_LEASH, |p| p.range);
    let leash_sq = leash * leash;
    snap.iter().enumerate().any(|(j, t)| {
        t.0 && j != i
            && t.1 != e.owner.0
            && (!depth
                || profile.is_some_and(|p| if t.3 { p.targets_air } else { p.targets_ground }))
            && (t.2 - e.pos).length_squared() <= leash_sq
    })
}

const fn is_air_of(balance: &Balance, kind: Kind) -> bool {
    match kind {
        Kind::Unit(u) => balance.unit(u).is_air,
        Kind::Building(_) => false,
    }
}

const fn kind_tag(kind: Kind) -> u64 {
    match kind {
        Kind::Unit(u) => 0x100 | unit_tag(u),
        Kind::Building(b) => {
            let t = match b {
                BuildingKind::CommandCenter => 1,
                BuildingKind::PowerPlant => 2,
                BuildingKind::Refinery => 3,
                BuildingKind::Barracks => 4,
                BuildingKind::GunTurret => 5,
                BuildingKind::AaTurret => 7,
                BuildingKind::Wall => 6,
                BuildingKind::ResearchLab => 8,
                BuildingKind::AntimatterPlant => 9,
                BuildingKind::VehicleFactory => 10,
                BuildingKind::Airfield => 11,
                BuildingKind::SupplyDepot => 12,
                BuildingKind::Battery => 13,
            };
            0x200 | t
        }
    }
}

/// A pristine civ holding `starting_credits` and nothing researched yet.
const fn default_civ(starting_credits: Fixed) -> Civ {
    Civ {
        alive: true,
        money: starting_credits,
        researched_techs: TechBitset::empty(),
        active_research: None,
        era: 0,
        energy: Fixed::ZERO,
        labour: Fixed::ZERO,
        active_perks: 0,
        doctrine_levels: [0; DOCTRINE_TRACKS],
        unlocked_buildings: u16::MAX,
        unlocked_units: u16::MAX,
    }
}

impl Sim {
    /// Creates a fresh world on `map`, with each player holding
    /// `starting_credits`, seeded for deterministic randomness.
    #[must_use]
    pub fn new(map: Map, seed: u64, starting_credits: Fixed) -> Self {
        Self::with_civ_count(map, seed, starting_credits, 2)
    }

    /// Creates a fresh world with `civ_count` civilizations, each holding
    /// `starting_credits`. The two-civ case ([`Sim::new`]) is the legacy default.
    #[must_use]
    pub fn with_civ_count(map: Map, seed: u64, starting_credits: Fixed, civ_count: usize) -> Self {
        let civs = (0..civ_count)
            .map(|_| default_civ(starting_credits))
            .collect();
        Self {
            #[cfg(test)]
            order_calls: 0,
            #[cfg(test)]
            breach_searches: 0,
            tick: 0,
            rng: Rng::from_seed(seed),
            map,
            civs,
            human_civ: PlayerId(0),
            entities: Vec::new(),
            free: Vec::new(),
            waves: None,
            wave_count: 0,
            phase: GamePhase::Active,
            phase_started: 0,
            survival: false,
            balance: Balance::const_default(),
            attacks: Vec::new(),
            colonies: Vec::new(),
            colony_free: Vec::new(),
            sectors: Vec::new(),
            sector_free: Vec::new(),
            planets: Vec::new(),
            field_seed: seed,
            lod_skip: true,
            planet_yield: Vec::new(),
            planet_tiles: Vec::new(),
            earthfront: false,
            earthfront_wave_doctrine: 0,
            depth: false,
            dg: depth::DepthGlobal::default(),
        }
    }

    /// Starts the run in the Survey phase: no human base exists until a
    /// [`Command::FoundBase`] resolves; waves and defeat are held until then.
    pub const fn begin_survey(&mut self) {
        self.phase = GamePhase::Survey;
    }

    /// Registers an autonomous [`Colony`] seated on `seat`, owned by `owner`, at
    /// the given autonomy level, and returns its stable [`ColonyId`]. Recycles a
    /// freed slot (LIFO) when one is available, mirroring the entity arena.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "colony index fits u32 for any real game (mirrors alloc_slot)"
    )]
    pub fn add_colony(&mut self, owner: PlayerId, seat: EntityId, autonomy_level: u8) -> ColonyId {
        let colony = Colony {
            alive: true,
            owner,
            seat,
            autonomy_level,
            autonomy_progress: 0,
            policy: ColonyPolicy::default(),
            directive: ColonyIntent::Auto,
            stockpile: [Fixed::ZERO; crate::game::civ::special::SPECIAL_COUNT],
            knowledge_of: [crate::game::civ::special::Knowledge::Unknown;
                crate::game::civ::special::SPECIAL_COUNT],
            species: Species::Standard,
            detail: SimDetail::Active,
            sector: None,
            // Synced as of its birth tick: its first per-tick pass materializes it.
            last_sync_tick: self.tick,
            population: 1,
            food: Fixed::ZERO,
            treasury: [Fixed::ZERO; 3],
        };
        if let Some(index) = self.colony_free.pop() {
            self.colonies[index as usize] = colony;
            ColonyId(index)
        } else {
            let index = self.colonies.len() as u32;
            self.colonies.push(colony);
            ColonyId(index)
        }
    }

    /// Sets a colony's species (scenario setup; biases its autonomous behaviour).
    pub fn set_colony_species(&mut self, colony: ColonyId, species: Species) {
        if let Some(c) = self.colonies.get_mut(colony.0 as usize) {
            c.species = species;
        }
    }

    /// Read access to a living colony by id (for the UI and tests).
    #[must_use]
    pub fn colony(&self, id: ColonyId) -> Option<&Colony> {
        self.colonies.get(id.0 as usize).filter(|c| c.alive)
    }

    /// A colony's current population (city size). Read-only; not hash-affecting.
    #[must_use]
    pub fn colony_population(&self, id: ColonyId) -> u32 {
        self.colony(id).map_or(0, |c| c.population)
    }

    /// `(current food, food needed for the next population point)` for a UI
    /// readout. Read-only; not hash-affecting.
    #[must_use]
    pub fn colony_food_progress(&self, id: ColonyId) -> (Fixed, Fixed) {
        self.colony(id).map_or((Fixed::ZERO, Fixed::ZERO), |c| {
            (c.food, Balance::food_threshold(c.population))
        })
    }

    /// How many living colonies `owner` holds (for the UI and tests).
    #[must_use]
    pub fn colony_count_for(&self, owner: PlayerId) -> usize {
        self.count_owner_colonies(owner)
    }

    /// Super-linear empire-administration upkeep (in Money) for `owner` this tick.
    ///
    /// For `n` owned colonies the cost is the triangular sum
    /// `UPKEEP_STEP × n·(n−1)/2`, so colony `k` adds `UPKEEP_STEP·(k−1)`: the first
    /// colony is free and every extra colony costs more than the last
    /// (n=1→0, 2→1·step, 3→3·step, 4→6·step, 8→28·step). A runaway leader therefore
    /// pays disproportionately more upkeep PER colony than a small follower — the
    /// "wide empires cost more to administer" brake on the conquest snowball.
    ///
    /// Fully integer/`Fixed`: `n·(n−1)` is always even, so the `/2` is exact with no
    /// float and no rounding (determinism rule D1). Deducted in [`run_economy`].
    #[must_use]
    pub fn empire_upkeep(&self, owner: PlayerId) -> Fixed {
        let n = i32::try_from(self.count_owner_colonies(owner)).unwrap_or(i32::MAX);
        // n·(n−1) is the product of consecutive integers ⇒ even ⇒ /2 is exact.
        let triangular = n.saturating_mul(n.saturating_sub(1)) / 2;
        UPKEEP_STEP * Fixed::from_int(triangular)
    }

    /// `owner`'s current Kardashev tier, derived from its empire size.
    #[must_use]
    pub fn kardashev_tier(&self, owner: PlayerId) -> KardashevTier {
        KardashevTier::from_colony_count(self.count_owner_colonies(owner))
    }

    /// Razes a colony, freeing its slot for reuse. Idempotent: freeing an already
    /// dead (or out-of-range) colony is a no-op, and a slot is never pushed twice.
    pub fn free_colony(&mut self, colony: ColonyId) {
        let index = colony.0 as usize;
        if self.colonies.get(index).is_some_and(|c| c.alive) {
            // Settle any skipped accrual so the dead colony's stored accumulators
            // match a full-fidelity run (the hash stops reconstructing once dead).
            self.materialize_colony(index, self.tick);
            self.colonies[index].alive = false;
            self.colony_free.push(colony.0);
        }
    }

    /// Creates a governance [`Sector`] for `owner`, reusing the lowest free slot
    /// (LIFO) exactly like [`add_colony`](Self::add_colony) (determinism rule D5).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "sector index fits u32 for any real game (mirrors add_colony)"
    )]
    pub fn add_sector(&mut self, owner: PlayerId, doctrine: SectorDoctrine) -> SectorId {
        let sector = Sector {
            alive: true,
            owner,
            doctrine,
        };
        if let Some(index) = self.sector_free.pop() {
            self.sectors[index as usize] = sector;
            SectorId(index)
        } else {
            let index = self.sectors.len() as u32;
            self.sectors.push(sector);
            SectorId(index)
        }
    }

    /// Disbands a sector, freeing its slot and unassigning its member colonies.
    /// Idempotent; a slot is never pushed twice.
    pub fn free_sector(&mut self, sector: SectorId) {
        let index = sector.0 as usize;
        if self.sectors.get(index).is_some_and(|s| s.alive) {
            self.sectors[index].alive = false;
            self.sector_free.push(sector.0);
            for c in &mut self.colonies {
                if c.sector == Some(sector) {
                    c.sector = None;
                }
            }
        }
    }

    /// Read access to a living sector by id (for the UI and tests).
    #[must_use]
    pub fn sector(&self, id: SectorId) -> Option<&Sector> {
        self.sectors.get(id.0 as usize).filter(|s| s.alive)
    }

    /// Length of the colony arena, including dead slots (for UI enumeration:
    /// scan `0..colonies_len()` and filter via [`colony`](Self::colony)).
    #[must_use]
    pub const fn colonies_len(&self) -> usize {
        self.colonies.len()
    }

    /// Length of the sector arena, including dead slots (for UI enumeration:
    /// scan `0..sectors_len()` and filter via [`sector`](Self::sector)).
    #[must_use]
    pub const fn sectors_len(&self) -> usize {
        self.sectors.len()
    }

    /// The effective governance doctrine of a colony: its sector's doctrine, or
    /// [`Balanced`](SectorDoctrine::Balanced) when ungoverned.
    #[must_use]
    pub fn colony_doctrine(&self, colony: ColonyId) -> SectorDoctrine {
        self.colonies
            .get(colony.0 as usize)
            .filter(|c| c.alive)
            .and_then(|c| c.sector)
            .and_then(|s| self.sector(s))
            .map_or(SectorDoctrine::Balanced, |s| s.doctrine)
    }

    /// The governance commands every living sector emits this tick, in ascending
    /// sector-id order. A **pure function of hashed state** (no RNG, no floats) —
    /// the same lockstep-safe contract as [`colony_commands`](Self::colony_commands).
    ///
    /// A sector governs by pushing its doctrine's [`policy`](SectorDoctrine::policy)
    /// onto each member colony whose policy does not already match — so it is
    /// **idempotent**: once the colonies are in sync the sector emits nothing.
    #[must_use]
    pub fn sector_commands(&self) -> Vec<Command> {
        let mut cmds = Vec::new();
        for (si, s) in self.sectors.iter().enumerate() {
            if !s.alive {
                continue;
            }
            let sid = SectorId(u32::try_from(si).unwrap_or(0));
            let target = s.doctrine.policy();
            for (ci, c) in self.colonies.iter().enumerate() {
                if c.alive && c.sector == Some(sid) && c.owner == s.owner && c.policy != target {
                    cmds.push(Command::SetColonyPolicy {
                        owner: s.owner,
                        colony: ColonyId(u32::try_from(ci).unwrap_or(0)),
                        policy: target,
                    });
                }
            }
        }
        cmds
    }

    /// The autonomous commands of every living colony this tick, gathered in
    /// ascending colony-id order. A **pure function of hashed state** (no RNG,
    /// no floats) — the same lockstep-safe contract as [`Sim::ai_commands`], so a
    /// driver may log/replay the batch (or regenerate it) without drift.
    ///
    /// Each colony generates its owner's AI commands, then keeps only the
    /// categories its *effective* autonomy permits (see
    /// [`command_min_autonomy`](crate::game::civ::command_min_autonomy)). At
    /// autonomy 0 it stays silent (manual); at the cap, nothing is filtered, so a
    /// fully-autonomous colony delegates wholesale to the proven AI brain.
    #[must_use]
    pub fn colony_commands(&self) -> Vec<Command> {
        let mut cmds = Vec::new();
        // Sites already planned this tick, so two colonies don't target one tile.
        let mut planned: Vec<(u16, u16)> = Vec::new();
        for (idx, c) in self.colonies.iter().enumerate() {
            if !c.alive {
                continue;
            }
            let level = c.effective_autonomy();
            if level == 0 {
                continue;
            }
            for cmd in self.ai_commands(c.owner) {
                if crate::game::civ::command_min_autonomy(&cmd) <= level {
                    cmds.push(cmd);
                }
            }
            // Auto-expansion: a sufficiently-autonomous colony with an active
            // expansion stance founds a new colony toward the first viable site,
            // throttled and bounded so growth never runs away. Deterministic.
            let expanding = !matches!(
                c.policy.expansion,
                ExpansionIntent::None | ExpansionIntent::SuggestOnly
            );
            if level >= 6
                && expanding
                && self.tick.is_multiple_of(c.species.expand_period())
                && self.count_owner_colonies(c.owner) < c.species.colony_cap()
                && self.money(c.owner) >= FOUND_COLONY_COST
            {
                if let Some(site) = self.first_colony_site(&planned) {
                    planned.push(site);
                    cmds.push(Command::FoundColony {
                        owner: c.owner,
                        parent: ColonyId(u32::try_from(idx).unwrap_or(0)),
                        x: site.0,
                        y: site.1,
                    });
                }
            }
        }
        cmds
    }

    /// Restricts `player` to a starting founding kit — only `buildings` and
    /// `units` are buildable until tech research unlocks the rest. Used for the
    /// survival human (the AI sides stay fully unlocked).
    pub fn set_starting_unlocks(
        &mut self,
        player: PlayerId,
        buildings: &[BuildingKind],
        units: &[UnitKind],
    ) {
        let p = usize::from(player.0);
        self.civs[p].unlocked_buildings = 0;
        self.civs[p].unlocked_units = 0;
        for &b in buildings {
            self.civs[p].unlocked_buildings |= 1 << b.index();
        }
        for &u in units {
            self.civs[p].unlocked_units |= 1 << u.index();
        }
    }

    /// Whether `player` may build `kind` yet (for the shell command bar).
    #[must_use]
    pub fn building_unlocked(&self, player: PlayerId, kind: BuildingKind) -> bool {
        self.civs[usize::from(player.0)].unlocked_buildings & (1 << kind.index()) != 0
    }

    /// Whether `player` may train `kind` yet (for the shell command bar).
    #[must_use]
    pub fn unit_unlocked(&self, player: PlayerId, kind: UnitKind) -> bool {
        self.civs[usize::from(player.0)].unlocked_units & (1 << kind.index()) != 0
    }

    /// Test-only: instantly grant `id` (set the bit, advance era, apply unlocks),
    /// mirroring research completion. Lets tests satisfy DAG prereqs without
    /// stepping the whole chain.
    #[cfg(test)]
    fn grant_tech(&mut self, player: PlayerId, id: u32) {
        let p = usize::from(player.0);
        self.civs[p].researched_techs.set(id);
        self.apply_grid_unlocks(p, id);
    }

    /// Applies a completed grid node's effects for player slot `p`: an era bump if
    /// it is an era key, plus any real building/unit it makes buildable. (The
    /// researched bit itself is set by the caller.)
    fn apply_grid_unlocks(&mut self, p: usize, id: u32) {
        if self.earthfront {
            self.unlock_earthfront_tech(p, id);
            return;
        }
        if tech_grid::is_era_key(id) {
            self.civs[p].era = (self.civs[p].era + 1).min(9);
        }
        if let Some(b) = tech_grid::real_building(id) {
            self.civs[p].unlocked_buildings |= 1 << b.index();
        }
        if let Some(u) = tech_grid::real_unit(id) {
            self.civs[p].unlocked_units |= 1 << u.index();
        }
    }

    /// Whether the run is still in the pre-founding Survey phase.
    #[must_use]
    pub const fn surveying(&self) -> bool {
        matches!(self.phase, GamePhase::Survey)
    }

    /// Enables Earthfront mission rules: defend the human Command Center and
    /// counterattack to destroy every hostile Command Center.
    pub const fn set_survival_mode(&mut self, on: bool) {
        self.survival = on;
    }

    /// Shots fired on the most recent combat tick, as (attacker, target) world
    /// positions — for drawing tracers. Transient; not part of the state.
    #[must_use]
    pub fn recent_attacks(&self) -> &[(Vec2, Vec2)] {
        &self.attacks
    }

    /// Stores an entity in a recycled dead slot if one is free, else appends.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn alloc_slot(&mut self, entity: Entity) -> EntityId {
        if let Some(index) = self.free.pop() {
            self.entities[index as usize] = entity;
            EntityId(index)
        } else {
            let index = self.entities.len() as u32;
            self.entities.push(entity);
            EntityId(index)
        }
    }

    /// Replaces the balance table (e.g. one loaded from data).
    pub const fn set_balance(&mut self, balance: Balance) {
        self.balance = balance;
    }

    /// Enables periodic enemy waves (the attack/defend loop).
    pub const fn set_waves(&mut self, config: WaveConfig) {
        self.waves = Some(config);
    }

    /// The current tick count.
    #[must_use]
    pub const fn tick(&self) -> u64 {
        self.tick
    }

    /// The battlefield map.
    #[must_use]
    pub const fn map(&self) -> &Map {
        &self.map
    }

    /// Mutable access to the map (scenario setup and tests: e.g. painting the
    /// tile→planet membership layer via [`Map::set_planet`]).
    pub const fn map_mut(&mut self) -> &mut Map {
        &mut self.map
    }

    /// Recomputes the per-planet terrain-yield cache from the static terrain and
    /// planet-membership map layers. Pure derived data: not hashed, no `rng`, no
    /// floats. Call after painting terrain / planet tiles.
    pub fn rebuild_planet_yield(&mut self) {
        let mut out = alloc::vec![[Fixed::ZERO; 4]; self.planets.len()];
        let mut tiles = alloc::vec![0u32; self.planets.len()];
        for y in 0..self.map.height() {
            for x in 0..self.map.width() {
                if let Some(pid) = self.map.planet_at(i32::from(x), i32::from(y)) {
                    let (f, m, e, l) =
                        Balance::terrain_yield(self.map.terrain_at(i32::from(x), i32::from(y)));
                    if let Some(slot) = out.get_mut(usize::from(pid.0)) {
                        slot[0] = slot[0] + f;
                        slot[1] = slot[1] + m;
                        slot[2] = slot[2] + e;
                        slot[3] = slot[3] + l;
                    }
                    if let Some(n) = tiles.get_mut(usize::from(pid.0)) {
                        *n += 1;
                    }
                }
            }
        }
        self.planet_yield = out;
        self.planet_tiles = tiles;
    }

    /// The cached aggregate terrain yield (`[food, money, energy, labour]`) for a
    /// planet, or all-zero if `pid` is out of range or the cache is unbuilt.
    #[must_use]
    pub fn planet_yield_of(&self, pid: PlanetId) -> [Fixed; 4] {
        self.planet_yield
            .get(usize::from(pid.0))
            .copied()
            .unwrap_or([Fixed::ZERO; 4])
    }

    /// Registers a [`Planet`] in the control arena and returns its stable
    /// [`PlanetId`] (its index). Scenario setup and tests.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "planet index fits u16 for any real game"
    )]
    pub fn push_planet(&mut self, p: Planet) -> PlanetId {
        let id = PlanetId(self.planets.len() as u16);
        self.planets.push(p);
        id
    }

    /// Sets a planet's owning civ (scenario setup and tests). No-op if the id is
    /// out of range.
    pub fn set_planet_owner(&mut self, id: PlanetId, owner: Option<CivId>) {
        if let Some(pl) = self.planets.get_mut(id.0 as usize) {
            pl.owner = owner;
        }
    }

    /// A planet's current owning civ, if the planet exists (tests and UI).
    #[must_use]
    pub fn planet_owner(&self, id: PlanetId) -> Option<CivId> {
        self.planets.get(id.0 as usize).and_then(|pl| pl.owner)
    }

    /// A planet's world-space centre (for drawing its city + anchoring its panel).
    /// Read-only accessor; does not affect the deterministic state hash.
    #[must_use]
    pub fn planet_center(&self, id: PlanetId) -> Option<Vec2> {
        self.planets.get(usize::from(id.0)).map(|p| p.center)
    }

    /// A planet's claim radius (world units).
    /// Read-only accessor; does not affect the deterministic state hash.
    #[must_use]
    pub fn planet_radius(&self, id: PlanetId) -> Option<Fixed> {
        self.planets.get(usize::from(id.0)).map(|p| p.radius)
    }

    /// A planet's controlling seat (`CommandCenter` entity), if settled.
    /// Read-only accessor; does not affect the deterministic state hash.
    #[must_use]
    pub fn planet_seat(&self, id: PlanetId) -> Option<EntityId> {
        self.planets.get(usize::from(id.0)).and_then(|p| p.seat)
    }

    /// The living colony seated on a planet (its city), if any.
    /// Read-only accessor; does not affect the deterministic state hash.
    #[must_use]
    pub fn planet_colony(&self, id: PlanetId) -> Option<ColonyId> {
        let seat = self.planets.get(usize::from(id.0)).and_then(|p| p.seat)?;
        self.colonies
            .iter()
            .position(|c| c.alive && c.seat == seat)
            .map(|i| ColonyId(u32::try_from(i).unwrap_or(0)))
    }

    /// The number of planets registered in the control arena (tests and UI).
    #[must_use]
    pub const fn planets_len(&self) -> usize {
        self.planets.len()
    }

    /// The number of civilizations in this game (UI iterates `0..civ_count()`).
    /// Read-only accessor; does not affect the deterministic state hash.
    #[must_use]
    pub const fn civ_count(&self) -> usize {
        self.civs.len()
    }

    /// Sets an entity's current HP (scenario setup / tests; e.g. to bring a seat
    /// near death). No-op if the id is out of range.
    pub fn debug_set_hp(&mut self, e: EntityId, hp: Fixed) {
        if let Some(ent) = self.entities.get_mut(e.0 as usize) {
            ent.hp = hp;
        }
    }

    /// Whether the entity with this id is currently alive (tests/UI).
    #[must_use]
    pub fn entity_alive(&self, e: EntityId) -> bool {
        self.entities.get(e.0 as usize).is_some_and(|ent| ent.alive)
    }

    /// The owning civ of a living entity, if it exists (tests/UI).
    #[must_use]
    pub fn entity_owner(&self, e: EntityId) -> Option<CivId> {
        self.entities
            .get(e.0 as usize)
            .filter(|ent| ent.alive)
            .map(|ent| ent.owner)
    }

    /// The owner of the living colony seated on `seat`, if any (tests/UI).
    #[must_use]
    pub fn colony_owner_of_seat(&self, seat: EntityId) -> Option<CivId> {
        self.colonies
            .iter()
            .find(|c| c.alive && c.seat == seat)
            .map(|c| c.owner)
    }

    /// How many living [`Building`](Kind::Building) entities `civ` owns (tests/UI).
    #[must_use]
    pub fn buildings_owned_by(&self, civ: CivId) -> usize {
        self.entities
            .iter()
            .filter(|e| e.alive && e.owner == civ && matches!(e.kind, Kind::Building(_)))
            .count()
    }

    /// Whether `civ` may build on tile `(x, y)`: the tile must belong to a planet
    /// this civ owns. Open space (no planet) is never buildable — EXCEPT that when
    /// the map has zero planets assigned anywhere, building is ungated (legacy /
    /// planet-free scenarios behave exactly as before).
    #[must_use]
    pub fn can_build_on(&self, civ: CivId, x: u16, y: u16) -> bool {
        if self.planets.is_empty() {
            return true; // legacy / planet-free scenarios are ungated
        }
        self.map
            .planet_at(i32::from(x), i32::from(y))
            .is_some_and(|pid| {
                self.planets
                    .get(pid.0 as usize)
                    .is_some_and(|pl| pl.owner == Some(civ))
            })
    }

    /// A player's current money balance.
    #[must_use]
    pub fn money(&self, player: PlayerId) -> Fixed {
        self.civs[usize::from(player.0)].money
    }

    /// Adds `amount` to a player's money stockpile (scenario setup only). Used by
    /// `conquest` to grant a small, seeded, FAIR starting edge to one civ so a
    /// symmetric stand-off can tip rather than deadlock. Money is part of the hashed
    /// state, but this runs at BUILD time and is deterministic in `(seed)`, so the
    /// per-seed setup stays bit-identical across runs.
    pub fn grant_money(&mut self, player: PlayerId, amount: Fixed) {
        let c = &mut self.civs[usize::from(player.0)];
        c.money = c.money + amount;
    }

    /// A player's current Energy stockpile.
    #[must_use]
    pub fn energy(&self, player: PlayerId) -> Fixed {
        self.civs[usize::from(player.0)].energy
    }

    /// A player's current Labour (population) stockpile.
    #[must_use]
    pub fn labour(&self, player: PlayerId) -> Fixed {
        self.civs[usize::from(player.0)].labour
    }

    /// A player's current level on Ascendancy Doctrine `track` (for the UI).
    /// Out-of-range tracks read as 0.
    #[must_use]
    pub fn doctrine_level(&self, player: PlayerId, track: u8) -> u16 {
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return 0;
        }
        self.civs[usize::from(player.0)].doctrine_levels[t]
    }

    /// The `(money, research)` cost for `player` to buy the next level of
    /// doctrine `track` (for UI affordability hints). Out-of-range ⇒ zero.
    #[must_use]
    pub fn doctrine_cost(&self, player: PlayerId, track: u8) -> (Fixed, Fixed) {
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return (Fixed::ZERO, Fixed::ZERO);
        }
        ascend_cost(t, self.doctrine_level(player, track))
    }

    /// Money cost to construct a building (for UI affordability hints).
    #[must_use]
    pub const fn building_cost(&self, kind: BuildingKind) -> Fixed {
        self.balance.building(kind).money_cost
    }

    /// Money cost to train a unit (for UI affordability hints).
    #[must_use]
    pub const fn unit_cost(&self, kind: UnitKind) -> Fixed {
        self.balance.unit(kind).money_cost
    }

    /// Whether `player` can afford `kind` in all three resources (Money, Energy,
    /// Labour). The AI uses this so it paces production instead of queueing
    /// commands `apply_build` would reject.
    fn can_afford_building(&self, player: PlayerId, kind: BuildingKind) -> bool {
        let p = usize::from(player.0);
        let st = self.balance.building(kind);
        self.civs[p].money >= st.money_cost
            && (self.earthfront || self.civs[p].energy >= st.energy_cost)
            && (self.earthfront || self.civs[p].labour >= st.labour_cost)
    }

    /// Whether `player` can afford `kind` in all three resources (see
    /// [`Sim::can_afford_building`]).
    fn can_afford_unit(&self, player: PlayerId, kind: UnitKind) -> bool {
        let p = usize::from(player.0);
        let st = self.balance.unit(kind);
        self.civs[p].money >= st.money_cost
            && (self.earthfront || self.civs[p].energy >= st.energy_cost)
            && (self.earthfront || self.civs[p].labour >= st.labour_cost)
    }

    /// Per-player research state: (researched grid set, optional (node id, ticks left)).
    #[must_use]
    pub fn research_state(&self, player: PlayerId) -> (TechBitset, Option<(u32, u32)>) {
        let p = &self.civs[usize::from(player.0)];
        (p.researched_techs, p.active_research)
    }

    /// Current science-era index for `player` (`0..=9`; see `tech_grid::Era`).
    #[must_use]
    pub fn player_era(&self, player: PlayerId) -> u8 {
        self.civs[usize::from(player.0)].era
    }
    /// The next currently affordable technology recommended by the deterministic
    /// AI research policy. Presentation clients use this as a one-click research
    /// affordance; issuing the returned id still goes through normal validation.
    #[must_use]
    pub fn suggested_research(&self, player: PlayerId) -> Option<u32> {
        if self.research_state(player).1.is_some() {
            None
        } else {
            self.ai_next_research(player)
        }
    }

    /// All currently affordable research choices in stable grid-id order.
    ///
    /// Presentation clients use this to offer a real player choice while command
    /// application remains the final authority. Busy and pre-founding players
    /// intentionally receive no options.
    #[must_use]
    pub fn available_research(&self, player: PlayerId) -> Vec<u32> {
        if self.earthfront {
            return self.earthfront_available_research(player);
        }
        if self.surveying() || self.research_state(player).1.is_some() {
            return Vec::new();
        }
        let p = usize::from(player.0);
        let set = self.civs[p].researched_techs;
        crate::game::tech_grid_table::GRID
            .iter()
            .filter(|node| {
                if set.get(node.id) || !node.prereqs.iter().all(|&required| set.get(required)) {
                    return false;
                }
                let lab_ok = node.era == 0 || self.has_research_lab(player);
                let money = Fixed::from_int(i32::try_from(node.money).unwrap_or(i32::MAX));
                let energy = Fixed::from_int(i32::try_from(node.energy).unwrap_or(i32::MAX));
                let labour = Fixed::from_int(i32::try_from(node.labour).unwrap_or(i32::MAX));
                lab_ok
                    && self.civs[p].money >= money
                    && self.civs[p].energy >= energy
                    && self.civs[p].labour >= labour
            })
            .map(|node| node.id)
            .collect()
    }

    /// Whether the player has at least one alive research lab.
    #[must_use]
    pub fn has_research_lab(&self, player: PlayerId) -> bool {
        self.entities.iter().any(|e| {
            e.alive
                && e.owner == player
                && e.construction_remaining == 0
                && matches!(e.kind, Kind::Building(BuildingKind::ResearchLab))
        })
    }

    /// How many living buildings of `kind` a player owns. Used by the AI to bound
    /// its own expansion (it never reads this for combat, so determinism is unaffected).
    #[must_use]
    fn count_alive_buildings(&self, player: PlayerId, kind: BuildingKind) -> usize {
        self.entities
            .iter()
            .filter(|e| {
                e.alive && e.owner == player && matches!(e.kind, Kind::Building(b) if b == kind)
            })
            .count()
    }

    /// The first buildable tile (row-major) holding an active deposit of `kind`,
    /// if any — the AI's expansion target for that resource. Deterministic, no RNG.
    #[must_use]
    fn first_buildable_deposit(&self, kind: crate::game::map::DepositKind) -> Option<(u16, u16)> {
        self.map.deposits().find_map(|(x, y, d)| {
            (d.kind == kind
                && self
                    .map
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.buildable))
            .then_some((x, y))
        })
    }

    /// How many of a player's living Extractors stand on a still-active deposit of
    /// `kind`. Lets the AI bound expansion per resource (Ore → Minerals, Alloy →
    /// Capital ships). AI-only; never read for combat, so determinism is unaffected.
    #[must_use]
    fn active_extractors_on(&self, player: PlayerId, kind: crate::game::map::DepositKind) -> usize {
        self.entities
            .iter()
            .filter(|e| {
                e.alive
                    && e.owner == player
                    && e.construction_remaining == 0
                    && matches!(e.kind, Kind::Building(BuildingKind::Refinery))
                    && e.tile.is_some_and(|(tx, ty)| {
                        self.map.deposit(tx, ty).is_some_and(|d| d.kind == kind)
                    })
            })
            .count()
    }

    /// Ticks until the next enemy wave, or `None` if waves are disabled.
    #[must_use]
    pub fn ticks_until_next_wave(&self) -> Option<u64> {
        let cfg = self.waves?;
        if matches!(self.phase, GamePhase::Survey) {
            return None; // the clock starts at founding
        }
        let t = self.tick - self.phase_started;
        if t < cfg.first_delay {
            return Some(cfg.first_delay - t);
        }
        let into = (t - cfg.first_delay) % cfg.interval;
        Some(if into == 0 { 0 } else { cfg.interval - into })
    }

    /// Number of waves that have already spawned — the survival-mode score.
    #[must_use]
    pub const fn waves_survived(&self) -> u32 {
        self.wave_count
    }

    /// Number of living entities.
    #[must_use]
    pub fn entity_count(&self) -> usize {
        self.entities.iter().filter(|e| e.alive).count()
    }

    /// Number of living units owned by `player`.
    #[must_use]
    pub fn unit_count(&self, player: PlayerId) -> usize {
        self.entities
            .iter()
            .filter(|e| e.alive && e.owner == player && matches!(e.kind, Kind::Unit(_)))
            .count()
    }

    /// Population cap for `player`: a base allowance plus headroom from the
    /// Command Center and each Barracks, so expanding production also lifts the
    /// supply ceiling (the build-economy-vs-army decision).
    #[must_use]
    pub fn supply_cap(&self, player: PlayerId) -> u32 {
        if self.earthfront {
            return if self.civs[usize::from(player.0)].researched_techs.get(11) {
                90
            } else {
                60
            };
        }
        let mut cap =
            SUPPLY_BASE + SUPPLY_PER_ERA * u32::from(self.civs[usize::from(player.0)].era);
        for e in &self.entities {
            if e.alive && e.owner == player && e.construction_remaining == 0 {
                cap += match e.kind {
                    Kind::Building(BuildingKind::CommandCenter) => SUPPLY_PER_CC,
                    Kind::Building(BuildingKind::Barracks) => SUPPLY_PER_BARRACKS,
                    Kind::Building(BuildingKind::PowerPlant) => SUPPLY_PER_REACTOR,
                    _ => 0,
                };
            }
        }
        if self.civs[usize::from(player.0)].active_perks & (1 << crate::game::perk::CONSCRIPTION)
            != 0
        {
            cap += 8;
        }
        // Each colony's population contributes army supply (city → army coupling).
        for c in &self.colonies {
            if c.alive && c.owner == player {
                cap += SUPPLY_PER_POP * c.population;
            }
        }
        cap
    }

    /// The player's active survival perks (bitmask).
    #[must_use]
    pub fn perks(&self, player: PlayerId) -> u32 {
        self.civs[player.0 as usize].active_perks
    }

    /// Supply in use: living units plus units still queued for training, so the
    /// cap can't be bypassed by over-queueing.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "unit/queue counts fit u32 for any real game"
    )]
    pub fn supply_used(&self, player: PlayerId) -> u32 {
        let mut used = 0;
        for e in &self.entities {
            if e.alive && e.owner == player {
                match e.kind {
                    Kind::Unit(kind) => {
                        used += if self.earthfront {
                            u32::try_from(self.balance.unit(kind).labour_cost.to_int_floor())
                                .unwrap_or(1)
                                .max(1)
                        } else {
                            1
                        }
                    }
                    Kind::Building(_) => {
                        used += if self.earthfront {
                            e.build_queue
                                .iter()
                                .map(|&kind| {
                                    u32::try_from(
                                        self.balance.unit(kind).labour_cost.to_int_floor(),
                                    )
                                    .unwrap_or(1)
                                    .max(1)
                                })
                                .sum()
                        } else {
                            e.build_queue.len() as u32
                        }
                    }
                }
            }
        }
        used
    }

    /// Whether the entity exists and is alive.
    #[must_use]
    pub fn is_alive(&self, id: EntityId) -> bool {
        self.entity(id).is_some_and(|e| e.alive)
    }

    /// The position of a living entity.
    #[must_use]
    pub fn position(&self, id: EntityId) -> Option<Vec2> {
        self.entity(id).filter(|e| e.alive).map(|e| e.pos)
    }

    /// A snapshot of every living entity, for the render/UI layer.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn views(&self) -> Vec<EntityView> {
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, e)| e.alive)
            .map(|(i, e)| EntityView {
                id: EntityId(i as u32),
                owner: e.owner,
                kind: match e.kind {
                    Kind::Building(b) => EntityKindView::Building(b),
                    Kind::Unit(u) => EntityKindView::Unit(u),
                },
                pos: e.pos,
                hp: e.hp,
                max_hp: max_hp(&self.balance, e.kind),
                shield: e.shield,
                max_shield: self.player_shield_max(e.owner),
                ability_cd: e.ability_cd,
                stun_ticks: e.stun_ticks,
                cargo: e.cargo,
                rally: e.rally,
                construction_remaining: e.construction_remaining,
                construction_total: e.construction_total,
            })
            .collect()
    }

    /// Veterancy rank (0..=3) of the living unit `id`; 0 for buildings and
    /// unknown or dead entities. Read-only, not hashed.
    #[must_use]
    pub fn rank_of(&self, id: EntityId) -> u8 {
        self.entity(id)
            .filter(|e| e.alive && matches!(e.kind, Kind::Unit(_)))
            .map_or(0, |e| e.rank)
    }

    /// Whether the living unit `id` has nothing to do: no move target, no
    /// remaining path, no queued work. Conservative: Harvesters (which work
    /// autonomously), buildings and stunned units are never reported idle.
    /// Read-only, not hashed.
    #[must_use]
    pub fn is_idle_unit(&self, id: EntityId) -> bool {
        self.entity(id).is_some_and(|e| {
            e.alive
                && matches!(e.kind, Kind::Unit(u) if u != UnitKind::Harvester)
                && e.move_target.is_none()
                && e.dp.forced.is_none()
                && e.path.is_empty()
                && !e.harvest_returning
                && e.cargo == 0
                && e.build_queue.is_empty()
                && e.construction_remaining == 0
                && e.stun_ticks == 0
        })
    }

    /// Production status for a living producer, or `None` when it is idle or
    /// `id` does not identify a living entity.
    #[must_use]
    pub fn production_status(&self, id: EntityId) -> Option<ProductionView> {
        let e = self.entity(id).filter(|e| e.alive)?;
        let unit = *e.build_queue.first()?;
        Some(ProductionView {
            unit,
            queued: u32::try_from(e.build_queue.len()).unwrap_or(u32::MAX),
            progress: e.build_progress,
            duration: self.balance.unit(unit).build_time.max(1),
        })
    }

    /// The winner of the game, or `None` while it is still undecided.
    ///
    /// EARTHFRONT resolves when the human Command Center falls or every hostile
    /// Command Center has been destroyed.
    ///
    /// CONQUEST resolves by THREE deterministic rules, in order:
    /// 1. **Last civ standing** — exactly one civ still holds a `CommandCenter`.
    /// 2. **Domination** — an alive civ owns a strict majority (> [`DOMINATION_PERCENT`]%)
    ///    of all planets; it wins immediately (a clear leader needn't grind out the
    ///    last fortified seat). Skipped in planet-free scenarios.
    /// 3. **Timeout** — at [`CONQUEST_TICK_CAP`] a fortified multi-civ standoff would
    ///    otherwise never resolve, so the LEADING alive civ wins on a deterministic
    ///    score (most planets → most total `CommandCenter` HP → most entities → lowest
    ///    `PlayerId`), broken to a single civ.
    ///
    /// READ-ONLY query: it is NOT part of [`state_hash`](Self::state_hash). It reads
    /// only already-hashed/derived state (`self.tick`, planet ownership, entity HP),
    /// adds no new hashed counter, and never mutates — so the new rules are
    /// golden-neutral and lockstep-safe (the hash is identical; only the *reported*
    /// winner/end-time changes).
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the index is a civ slot < civs.len() (<= ~6), so it fits u16"
    )]
    pub fn winner(&self) -> Option<PlayerId> {
        // Before founding, an absent base is a pending decision, not a defeat.
        if matches!(self.phase, GamePhase::Survey) {
            return None;
        }
        let mut has_cc = alloc::vec![false; self.civs.len()];
        for e in &self.entities {
            if e.alive
                && e.construction_remaining == 0
                && e.kind == Kind::Building(BuildingKind::CommandCenter)
            {
                let i = usize::from(e.owner.0);
                // An owner id could in principle exceed the current civ count, so skip it defensively rather than panic.
                if i < has_cc.len() {
                    has_cc[i] = true;
                }
            }
        }
        // Earthfront mission: losing the human base is defeat; destroying every
        // hostile base is victory. The wave army can still eliminate exposed
        // forces, but its Core Node is now the decisive counterattack objective.
        if self.survival {
            if !has_cc[usize::from(self.human_civ.0)] {
                return Some(PlayerId(1));
            }
            let hostile_base_alive = has_cc
                .iter()
                .enumerate()
                .any(|(i, &has)| i != usize::from(self.human_civ.0) && has);
            return (!hostile_base_alive).then_some(self.human_civ);
        }
        // Conquest rule 1 — last civ standing.
        let alive: usize = has_cc.iter().filter(|&&b| b).count();
        if alive == 1 {
            return has_cc.iter().position(|&b| b).map(|i| PlayerId(i as u16));
        }
        if alive == 0 {
            // Everyone's base is gone (e.g. mutual destruction); no winner to name.
            return None;
        }

        // Conquest rule 2 — domination: a strict majority of all planets wins now.
        // Only an alive civ (still holds a CC) can claim victory this way. Skipped
        // when there are no planets (nothing to dominate).
        if !self.planets.is_empty() {
            let total = self.planets.len();
            for (i, &has) in has_cc.iter().enumerate() {
                if !has {
                    continue;
                }
                let civ = PlayerId(i as u16);
                let held = self
                    .planets
                    .iter()
                    .filter(|pl| pl.owner == Some(civ))
                    .count();
                // Strict majority by integer comparison: held·100 > total·PERCENT.
                if held * 100 > total * DOMINATION_PERCENT {
                    return Some(civ);
                }
            }
        }

        // Conquest rule 3 — timeout: a fortified standoff resolves to the leader.
        if self.tick >= CONQUEST_TICK_CAP {
            // Deterministic score, descending priority: planets owned, then total
            // CommandCenter HP (in Fixed bits), then entity count, then lowest
            // PlayerId. Scanned in ascending civ order with strict `>`, so the first
            // civ to set a tuple keeps it on ties ⇒ lowest PlayerId wins the tie.
            let mut best: Option<(PlayerId, (usize, i64, usize))> = None;
            for (i, &has) in has_cc.iter().enumerate() {
                if !has {
                    continue;
                }
                let owner = PlayerId(i as u16);
                let planets = self
                    .planets
                    .iter()
                    .filter(|pl| pl.owner == Some(owner))
                    .count();
                let mut cc_hp: i64 = 0;
                let mut entities = 0usize;
                for e in &self.entities {
                    if !e.alive || e.owner != owner {
                        continue;
                    }
                    entities += 1;
                    if e.kind == Kind::Building(BuildingKind::CommandCenter) {
                        cc_hp = cc_hp.saturating_add(e.hp.to_bits());
                    }
                }
                let score = (planets, cc_hp, entities);
                if best.is_none_or(|(_, b)| score > b) {
                    best = Some((owner, score));
                }
            }
            return best.map(|(owner, _)| owner);
        }

        None
    }

    /// Whether `civ` is still in the game (holds at least one `CommandCenter`).
    #[must_use]
    pub fn civ_alive(&self, civ: CivId) -> bool {
        self.civs.get(usize::from(civ.0)).is_some_and(|c| c.alive)
    }

    /// A deterministic fingerprint of the entire world.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        clippy::too_many_lines,
        reason = "the exhaustive, order-sensitive state serializer is clearer kept in one function; queue length comfortably fits u64 for any real game"
    )]
    pub fn state_hash(&self) -> u64 {
        let mut h = Fnv::new();
        h.write_u64(self.tick);
        h.write_u64(self.rng.current_state());
        h.write_u64(u64::from(self.wave_count));
        h.write_u64(match self.phase {
            GamePhase::Survey => 0,
            GamePhase::Active => 1,
        });
        h.write_u64(self.phase_started);
        // Per-player fields: money, researched_techs, active_research,
        // era, alloys, research, active_perks, doctrine_levels — in this stable
        // order. Never reorder; appending is fine (and re-pins the golden hash).
        for c in &self.civs {
            h.write_i64(c.money.to_bits());
            c.researched_techs.hash_into(&mut h);
            match c.active_research {
                Some((id, ticks)) => {
                    h.write_u64(1);
                    h.write_u64(u64::from(id));
                    h.write_u64(u64::from(ticks));
                }
                None => h.write_u64(0),
            }
            h.write_u64(u64::from(c.era));
            h.write_i64(c.energy.to_bits());
            h.write_i64(c.labour.to_bits());
            h.write_u64(u64::from(c.active_perks));
            for t in 0..DOCTRINE_TRACKS {
                h.write_u64(u64::from(c.doctrine_levels[t]));
            }
            h.write_u64(u64::from(c.unlocked_buildings));
            h.write_u64(u64::from(c.unlocked_units));
            h.write_u64(u64::from(c.alive));
        }
        for e in &self.entities {
            h.write_u64(u64::from(e.alive));
            h.write_u64(u64::from(e.owner.0));
            h.write_u64(kind_tag(e.kind));
            h.write_i64(e.pos.x.to_bits());
            h.write_i64(e.pos.y.to_bits());
            h.write_i64(e.hp.to_bits());
            h.write_i64(e.shield.to_bits());
            h.write_u64(u64::from(e.last_combat_tick));
            h.write_u64(u64::from(e.cooldown));
            h.write_u64(u64::from(e.kills));
            h.write_u64(u64::from(e.rank));
            h.write_u64(u64::from(e.ability_cd));
            h.write_u64(u64::from(e.stun_ticks));
            h.write_u64(u64::from(e.stun_immunity));
            match e.move_target {
                Some(t) => {
                    h.write_u64(1);
                    h.write_i64(t.x.to_bits());
                    h.write_i64(t.y.to_bits());
                }
                None => h.write_u64(0),
            }
            h.write_u64(u64::from(e.build_progress));
            h.write_u64(u64::from(e.construction_remaining));
            h.write_u64(u64::from(e.construction_total));
            h.write_u64(e.build_queue.len() as u64);
            for q in &e.build_queue {
                h.write_u64(unit_tag(*q));
            }
            h.write_u64(e.path.len() as u64);
            for &(wx, wy) in &e.path {
                h.write_u64(u64::from(wx));
                h.write_u64(u64::from(wy));
            }
            // Attack-move stance — genuine mutable per-entity state (set by an
            // AttackMove order, cleared by a plain Move and on arrival), so it is
            // folded into the hash. Appended last per the stable-order rule above
            // (this is what re-pinned the golden).
            if self.earthfront {
                h.write_u64(u64::from(e.power_fraction));
                h.write_u64(u64::from(e.work_fraction));
                h.write_u64(u64::from(e.ammunition));
                h.write_u64(u64::from(e.supply_stock));
                h.write_u64(u64::from(e.ore_buffer));
                h.write_u64(e.objective_role as u64);
            }
            // Kestrel depth per-entity state, depth on only (Survival and the
            // classic paths never write it, so their hashes are unchanged).
            if self.earthfront && self.depth {
                e.dp.hash_into(&mut h);
            }
            h.write_u64(u64::from(e.attack_move));
            h.write_u64(u64::from(e.cargo));
            h.write_u64(u64::from(e.harvest_returning));
            if let Some(rally) = e.rally {
                h.write_u64(1);
                h.write_i64(rally.x.to_bits());
                h.write_i64(rally.y.to_bits());
            } else {
                h.write_u64(0);
            }
        }
        if self.earthfront {
            h.write_u64(0x4541_5254_4832);
            h.write_u64(u64::from(self.earthfront_wave_doctrine));
        }
        // Kestrel depth global state behind its own marker ("DEPTH"), depth on only.
        if self.earthfront && self.depth {
            h.write_u64(0x44_4550_5448);
            self.dg.hash_into(&mut h);
        }
        h.write_u64(self.free.len() as u64);
        for &slot in &self.free {
            h.write_u64(u64::from(slot));
        }
        for (x, y, dep) in self.map.deposits() {
            h.write_u64(u64::from(x));
            h.write_u64(u64::from(y));
            h.write_u64(match dep.kind {
                crate::game::map::DepositKind::Ore => 0,
                crate::game::map::DepositKind::Alloy => 1,
            });
            h.write_u64(u64::from(dep.remaining));
        }
        // Colony layer — appended last (per the stable-order rule above). Empty in
        // legacy scenarios, so the only effect there is field_seed + zero markers.
        self.hash_colony_layer(&mut h);
        // Planetary control (event-driven; safe to hash directly — no LOD accrual).
        h.write_u64(self.planets.len() as u64);
        for pl in &self.planets {
            // 0 reserved for neutral; an owned planet writes its civ id + 1.
            h.write_u64(pl.owner.map_or(0, |c| u64::from(c.0) + 1));
            match pl.seat {
                Some(e) => {
                    h.write_u64(1);
                    h.write_u64(u64::from(e.0));
                }
                None => h.write_u64(0),
            }
            h.write_i64(pl.center.x.to_bits());
            h.write_i64(pl.center.y.to_bits());
            h.write_i64(pl.radius.to_bits());
        }
        // Ground layer — Earthfront only, appended last so the legacy hash is
        // untouched (legacy maps are all-Grass and never fold this in).
        if self.earthfront {
            for g in self.map.ground_iter() {
                h.write_u64(u64::from(g.tag()));
            }
        }
        h.finish()
    }

    /// Folds the autonomous-civilization layer into the state hash, in a stable
    /// append-only order (see [`Sim::state_hash`]).
    fn hash_colony_layer(&self, h: &mut Fnv) {
        h.write_u64(self.field_seed);
        h.write_u64(self.colonies.len() as u64);
        for (ci, c) in self.colonies.iter().enumerate() {
            // A Dormant colony skips its per-tick passes, so its stored
            // accumulators lag by `elapsed` ticks. Fold in the closed-form
            // caught-up values, never the lazy stored ones, so the hash is a pure
            // function of the *logical* state — independent of whether the colony
            // was simulated tick-by-tick or skipped (determinism rule D3). A dead
            // colony was settled at `free_colony`, so it never reconstructs.
            let elapsed = if c.alive {
                self.tick.saturating_sub(c.last_sync_tick)
            } else {
                0
            };
            // Population-scaled autonomy accrual mirror. Identical formula to
            // materialize_colony's accrual (rule D3): population is frozen while
            // Dormant, so this reconstructs the exact caught-up progress whether
            // the colony was stepped tick-by-tick or skipped. Same population-scaled
            // rate materialize_colony banks (single source: colony_autonomy_rate).
            let auto_rate = self.colony_autonomy_rate(ci);
            let steps_h = u32::try_from(elapsed).unwrap_or(u32::MAX);
            let progress = c
                .autonomy_progress
                .saturating_add(steps_h.saturating_mul(auto_rate));
            h.write_u64(u64::from(c.alive));
            h.write_u64(u64::from(c.owner.0));
            h.write_u64(u64::from(c.seat.0));
            h.write_u64(u64::from(c.autonomy_level));
            h.write_u64(u64::from(progress));
            for d in c.policy.discriminants() {
                h.write_u64(u64::from(d));
            }
            h.write_u64(c.directive as u64);
            h.write_u64(c.species as u64);
            h.write_u64(c.detail as u64);
            // Sector membership: 0 = ungoverned, else sector id + 1.
            h.write_u64(c.sector.map_or(0, |s| u64::from(s.0) + 1));
            for kind in crate::game::civ::special::SpecialKind::ALL {
                let k = kind.index();
                let rate = self.colony_special_rate(ci, kind);
                h.write_i64(closed_form_bits(c.stockpile[k], rate, elapsed));
            }
            for k in c.knowledge_of {
                h.write_u64(k as u64);
            }
            // City state. population/food are frozen while mature (only mature
            // colonies go Dormant), so they hash as stored. The treasury accrues at
            // a constant rate while Dormant, so fold in the closed-form caught-up
            // value (rule D3) exactly like the Field stockpiles above. For an
            // immature colony `elapsed` is 0 (always Active, never skipped) and the
            // treasury stays zero, so this is a no-op there.
            h.write_u64(u64::from(c.population));
            h.write_i64(c.food.to_bits());
            for k in 0..c.treasury.len() {
                let rate = self.colony_output_rate(ci, k);
                h.write_i64(closed_form_bits(c.treasury[k], rate, elapsed));
            }
        }
        h.write_u64(self.colony_free.len() as u64);
        for &slot in &self.colony_free {
            h.write_u64(u64::from(slot));
        }
        // The sector (governance) arena, appended in stable order.
        h.write_u64(self.sectors.len() as u64);
        for s in &self.sectors {
            h.write_u64(u64::from(s.alive));
            h.write_u64(u64::from(s.owner.0));
            h.write_u64(s.doctrine as u64);
        }
        h.write_u64(self.sector_free.len() as u64);
        for &slot in &self.sector_free {
            h.write_u64(u64::from(slot));
        }
    }

    /// Places a building for free (scenario setup), blocking its tile.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn add_building(
        &mut self,
        owner: PlayerId,
        kind: BuildingKind,
        x: u16,
        y: u16,
    ) -> EntityId {
        let pos = tile_center(x, y);
        self.map.set_tile(x, y, Tile::BLOCKED);
        let hp = max_hp(&self.balance, Kind::Building(kind));
        let shield = self.player_shield_max(owner);
        self.alloc_slot(Entity {
            owner,
            kind: Kind::Building(kind),
            alive: true,
            pos,
            hp,
            shield,
            last_combat_tick: 0,
            cooldown: 0,
            move_target: None,
            order_goal: None,
            path: Vec::new(),
            tile: Some((x, y)),
            build_queue: Vec::new(),
            build_progress: 0,
            construction_remaining: 0,
            construction_total: 0,
            kills: 0,
            rank: 0,
            ability_cd: 0,
            stun_ticks: 0,
            stun_immunity: 0,
            attack_move: false,
            cargo: 0,
            harvest_returning: false,
            rally: None,
            power_fraction: 1000,
            work_fraction: 0,
            ammunition: 90,
            supply_stock: 0,
            ore_buffer: 0,
            objective_role: earthfront::ObjectiveRole::None,
            dp: depth::DepthUnit::default(),
        })
    }

    /// Places a unit for free (scenario setup / production).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn add_unit(&mut self, owner: PlayerId, kind: UnitKind, pos: Vec2) -> EntityId {
        let hp = max_hp(&self.balance, Kind::Unit(kind));
        let shield = self.player_shield_max(owner);
        self.alloc_slot(Entity {
            owner,
            kind: Kind::Unit(kind),
            alive: true,
            pos,
            hp,
            shield,
            last_combat_tick: 0,
            cooldown: 0,
            move_target: None,
            order_goal: None,
            path: Vec::new(),
            tile: None,
            build_queue: Vec::new(),
            build_progress: 0,
            construction_remaining: 0,
            construction_total: 0,
            kills: 0,
            rank: 0,
            ability_cd: 0,
            stun_ticks: 0,
            stun_immunity: 0,
            attack_move: false,
            cargo: 0,
            harvest_returning: false,
            rally: None,
            power_fraction: 1000,
            work_fraction: 0,
            ammunition: 90,
            supply_stock: 0,
            ore_buffer: 0,
            objective_role: earthfront::ObjectiveRole::None,
            dp: depth::DepthUnit::default(),
        })
    }

    /// Advances the simulation one fixed tick.
    pub fn step(&mut self, commands: &[Command]) {
        // A completed Earthfront operation is immutable until a new Sim is created.
        if self.earthfront && self.survival && self.winner().is_some() {
            return;
        }
        for command in commands {
            self.apply_command(command);
        }
        if self.earthfront {
            // Sold structures must not generate power, finish queues or process ore.
            self.clear_dead();
            self.run_earthfront_services();
        }
        self.run_construction();
        self.run_economy();
        self.run_colony_accrual();
        self.run_lod();
        self.run_research();
        self.run_production();
        self.run_waves();
        self.run_harvesters();
        if self.is_depth() {
            // Kestrel depth: idle units acquire, leash and walk home (depth.rs).
            self.run_depth_acquire();
        }
        if self.is_depth() {
            // Kestrel depth: same-owner units at rest spread apart (depth.rs).
            let before = self.depth_positions();
            self.run_movement();
            self.run_depth_separation(&before);
        } else {
            self.run_movement();
        }
        self.run_shields();
        self.run_combat();
        self.run_status();
        self.clear_dead();
        self.run_conquest();
        self.tick += 1;
    }

    /// Recompute each civ's `alive` flag from `CommandCenter` possession. A civ is
    /// alive iff it holds >= 1 `CommandCenter` (the concrete form of "owns >= 1
    /// planet": equivalent in planet scenarios since every planet seat is a CC, and
    /// the only definition that also works in planet-free scenarios such as the
    /// golden/survival replays). Runs after `clear_dead` so destroyed/transferred
    /// seats are reflected. No `rng` (D1); no per-tick accrual (D2/D3 N/A).
    fn run_conquest(&mut self) {
        let mut holds_cc = alloc::vec![false; self.civs.len()];
        for e in &self.entities {
            if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
                let i = usize::from(e.owner.0);
                if i < holds_cc.len() {
                    holds_cc[i] = true;
                }
            }
        }
        for (i, c) in self.civs.iter_mut().enumerate() {
            c.alive = holds_cc[i];
        }
    }

    /// Ticks down per-entity ability cooldowns and EMP stuns. Runs at the end of
    /// the tick, so an effect applied this tick is felt this tick and a
    /// `duration`-tick stun suppresses exactly `duration` ticks of action.
    fn run_status(&mut self) {
        for e in &mut self.entities {
            if !e.alive || e.construction_remaining > 0 {
                continue;
            }
            e.ability_cd = e.ability_cd.saturating_sub(1);
            if e.stun_ticks > 0 {
                e.stun_ticks -= 1;
                if e.stun_ticks == 0 {
                    // The moment a stun wears off, harden against the next one.
                    e.stun_immunity = STUN_IMMUNITY;
                }
            } else {
                e.stun_immunity = e.stun_immunity.saturating_sub(1);
            }
        }
    }

    /// Spawns a scheduled enemy wave, if one is due this tick, and points it at
    /// the defender's base.
    fn run_waves(&mut self) {
        if self.earthfront {
            self.run_earthfront_waves();
            return;
        }
        let Some(cfg) = self.waves else { return };
        // The wave clock is frozen until the base is founded, then measures from
        // the founding tick — survey time never eats the first peace window.
        if matches!(self.phase, GamePhase::Survey) {
            return;
        }
        let t = self.tick - self.phase_started;
        if t < cfg.first_delay {
            return;
        }
        if !(t - cfg.first_delay).is_multiple_of(cfg.interval) {
            return;
        }
        let w = self.wave_count;
        // Wave pressure scales with the defender's empire size (Kardashev climb):
        // bigger empires draw proportionally larger sieges. Legacy scenarios have
        // no colonies, so this term is 0 and waves are unchanged.
        let empire = u32::try_from(self.count_owner_colonies(cfg.defender)).unwrap_or(0);
        let size = cfg.base_size + cfg.growth * w + EMPIRE_WAVE_PRESSURE * empire;
        let target = self.command_center_pos(cfg.defender);
        for i in 0..size {
            let offset = Vec2::new(Fixed::ZERO, Fixed::from_ratio(i64::from(i), 3));
            let kind = if cfg.escalate {
                escalating_unit(w, i)
            } else {
                cfg.unit
            };
            let spawned = self.add_unit(cfg.attacker, kind, cfg.spawn + offset);
            if let Some(t) = target {
                self.order_unit_to(spawned.0 as usize, t, false);
            }
        }
        // Boss: a Capital ship joins every 5th wave once escalation is underway.
        if cfg.escalate && (w + 1).is_multiple_of(5) {
            let spawned = self.add_unit(cfg.attacker, UnitKind::Capital, cfg.spawn);
            if let Some(t) = target {
                self.order_unit_to(spawned.0 as usize, t, false);
            }
        }
        // The swarm ADAPTS: each escalating wave also hardens the attacker itself —
        // a free doctrine level on a fixed rotation. This is the counterweight to
        // the defender's endless Ascendancy stacking: a fully-retrained,
        // doctrine-stacked army out-compounds any linear growth in wave COUNT, so
        // the waves must climb the same quality curve to ever overwhelm it.
        if cfg.escalate {
            let p = usize::from(cfg.attacker.0);
            let track = [DOC_WEAPONS, DOC_ARMOR, DOC_VITALITY][(w % 3) as usize];
            let lv = self.civs[p].doctrine_levels[track];
            self.civs[p].doctrine_levels[track] = (lv + 1).min(DOCTRINE_LEVEL_CAP);
        }
        self.wave_count += 1;
    }

    /// Sets a unit's move target and computes its A* path. Shared by the Move
    /// command and wave spawning. If the target tile is blocked (e.g. it *is* a
    /// building like the enemy Command Center), the unit paths to the nearest
    /// passable tile beside it and then closes the last step directly — so
    /// "attack the base" actually routes there.
    fn order_unit_to(&mut self, idx: usize, target: Vec2, attack_move: bool) {
        #[cfg(test)]
        {
            self.order_calls += 1;
        }
        let owner = self.entities[idx].owner;
        let given = target;
        if is_air_of(&self.balance, self.entities[idx].kind) || self.player_has_antigrav(owner) {
            // Air units and anti-grav units fly straight to the target, ignoring terrain.
            let e = &mut self.entities[idx];
            e.order_goal = Some(given);
            e.move_target = Some(target);
            e.attack_move = attack_move;
            e.path = Vec::new();
            return;
        }
        let start = self.world_to_tile(self.entities[idx].pos);
        let goal_tile = self.world_to_tile(target);
        let goal_passable = self.is_passable_tile(goal_tile);
        let goal = if goal_passable {
            goal_tile
        } else {
            match self.nearest_passable_tile(goal_tile) {
                Some(tile) => tile,
                None => return,
            }
        };
        // Earthfront: a substituted goal (water, a building) must not leave the
        // raw impassable point as the final straight leg, or the unit would walk
        // onto River/Sea once its path runs out. Aim at the passable tile instead.
        let target = if self.earthfront && !goal_passable {
            tile_center(goal.0, goal.1)
        } else {
            target
        };
        if let Some(path) = find_path(&self.map, start, goal) {
            let e = &mut self.entities[idx];
            e.order_goal = Some(given);
            e.move_target = Some(target);
            e.attack_move = attack_move;
            e.path = path;
        } else if self.is_depth() {
            // Kestrel depth (Task 16): a walled-off wave unit breaks through
            // the defender's structures instead of standing still (depth.rs).
            self.depth_breach(idx, (start, goal), given, attack_move);
        }
    }

    fn is_passable_tile(&self, tile: (u16, u16)) -> bool {
        self.map
            .tile(i32::from(tile.0), i32::from(tile.1))
            .is_some_and(|t| t.passable)
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "ring scan stays within the bounds-checked, non-negative u16 grid"
    )]
    fn nearest_passable_tile(&self, center: (u16, u16)) -> Option<(u16, u16)> {
        let cx = i32::from(center.0);
        let cy = i32::from(center.1);
        let mut best: Option<((u16, u16), i32, usize)> = None;
        for dy in -24..=24i32 {
            for dx in -24..=24i32 {
                let (x, y) = (cx + dx, cy + dy);
                if x < 0 || y < 0 || !self.map.tile(x, y).is_some_and(|t| t.passable) {
                    continue;
                }
                let cell = (x as u16, y as u16);
                let dist = hex::distance(center, cell);
                if dist == 0 {
                    continue;
                }
                let idx = y as usize * usize::from(self.map.width()) + x as usize;
                if best.is_none_or(|(_, bd, bi)| dist < bd || (dist == bd && idx < bi)) {
                    best = Some((cell, dist, idx));
                }
            }
        }
        best.map(|(cell, _, _)| cell)
    }

    fn command_center_pos(&self, player: PlayerId) -> Option<Vec2> {
        self.entities
            .iter()
            .find(|e| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .map(|e| e.pos)
    }

    fn entity(&self, id: EntityId) -> Option<&Entity> {
        self.entities.get(id.0 as usize)
    }

    /// Constructs `kind` at `(x, y)` for `owner` if the tile is buildable, the
    /// kind is unlocked, and all three resource costs are affordable.
    fn apply_build(&mut self, owner: PlayerId, kind: BuildingKind, x: u16, y: u16) {
        if self.earthfront
            && (kind == BuildingKind::CommandCenter
                || !self.earthfront_build_reachable(owner, x, y))
        {
            return;
        }
        let buildable = self
            .map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.buildable);
        let st = self.balance.building(kind);
        let p = usize::from(owner.0);
        let unlocked = self.civs[p].unlocked_buildings & (1 << kind.index()) != 0;
        if unlocked
            && buildable
            && self.can_build_on(owner, x, y)
            && self.under_building_cap(x, y)
            && self.civs[p].money >= st.money_cost
            && (self.earthfront || self.civs[p].energy >= st.energy_cost)
            && (self.earthfront || self.civs[p].labour >= st.labour_cost)
        {
            self.civs[p].money = self.civs[p].money - st.money_cost;
            if !self.earthfront {
                self.civs[p].energy = self.civs[p].energy - st.energy_cost;
                self.civs[p].labour = self.civs[p].labour - st.labour_cost;
            }
            let id = self.add_building(owner, kind, x, y);
            if let Some(building) = self.entities.get_mut(id.0 as usize) {
                building.construction_remaining = st.build_time;
                building.construction_total = st.build_time;
            }
        }
    }

    /// Queues a combat unit at a Barracks, or a Harvester at a Refinery, if the
    /// producer is owned and the resource, supply, unlock, and era checks pass.
    fn apply_train(&mut self, owner: PlayerId, barracks: EntityId, kind: UnitKind) {
        if matches!(kind, UnitKind::Capital) && self.civs[usize::from(owner.0)].era < 3 {
            return;
        }
        let st = self.balance.unit(kind);
        let p = usize::from(owner.0);
        let ok = self.entity(barracks).is_some_and(|e| {
            let correct_producer = if self.earthfront {
                e.kind == Kind::Building(Self::earthfront_producer(kind))
            } else if kind == UnitKind::Harvester {
                e.kind == Kind::Building(BuildingKind::Refinery)
            } else {
                e.kind == Kind::Building(BuildingKind::Barracks)
            };
            e.alive
                && e.owner == owner
                && e.construction_remaining == 0
                && correct_producer
                && (!self.earthfront || e.build_queue.len() < 8)
        });
        let needed = if self.earthfront {
            u32::try_from(st.labour_cost.to_int_floor())
                .unwrap_or(1)
                .max(1)
        } else {
            1
        };
        let has_supply = self.supply_used(owner).saturating_add(needed) <= self.supply_cap(owner);
        let unlocked = self.civs[p].unlocked_units & (1 << kind.index()) != 0;
        if ok
            && unlocked
            && has_supply
            && self.civs[p].money >= st.money_cost
            && (self.earthfront || self.civs[p].energy >= st.energy_cost)
            && (self.earthfront || self.civs[p].labour >= st.labour_cost)
        {
            self.civs[p].money = self.civs[p].money - st.money_cost;
            if !self.earthfront {
                self.civs[p].energy = self.civs[p].energy - st.energy_cost;
                self.civs[p].labour = self.civs[p].labour - st.labour_cost;
            }
            if let Some(e) = self.entities.get_mut(barracks.0 as usize) {
                e.build_queue.push(kind);
            }
        }
    }

    fn apply_set_rally(&mut self, owner: PlayerId, producer: EntityId, target: Vec2) {
        let requested = hex::from_world(target, self.map.width(), self.map.height());
        let valid_target = if self.is_passable_tile(requested) {
            Some(requested)
        } else {
            self.nearest_passable_tile(requested)
        }
        .map(|(x, y)| tile_center(x, y));
        let Some(target) = valid_target else {
            return;
        };
        if let Some(e) = self.entities.get_mut(producer.0 as usize) {
            if e.alive
                && e.owner == owner
                && matches!(
                    e.kind,
                    Kind::Building(
                        BuildingKind::Barracks
                            | BuildingKind::Refinery
                            | BuildingKind::VehicleFactory
                            | BuildingKind::Airfield
                    )
                )
            {
                e.rally = Some(target);
            }
        }
    }

    fn apply_repair(&mut self, owner: PlayerId, building: EntityId) {
        let idx = building.0 as usize;
        let Some((kind, hp)) = self.entities.get(idx).and_then(|e| match e.kind {
            Kind::Building(kind) if e.alive && e.hp > Fixed::ZERO && e.owner == owner => {
                Some((kind, e.hp))
            }
            _ => None,
        }) else {
            return;
        };
        let max = self.balance.building(kind).max_hp;
        if hp >= max {
            return;
        }
        let minimum = Fixed::from_int(5);
        let proportional = self.balance.building(kind).money_cost / Fixed::from_int(10);
        let cost = if proportional > minimum {
            proportional
        } else {
            minimum
        };
        let p = usize::from(owner.0);
        if self.civs[p].money < cost {
            return;
        }
        self.civs[p].money = self.civs[p].money - cost;
        let chunk = max / Fixed::from_int(5);
        let repaired = hp + chunk;
        self.entities[idx].hp = if repaired < max { repaired } else { max };
    }

    fn apply_sell(&mut self, owner: PlayerId, building: EntityId) {
        let idx = building.0 as usize;
        let Some(kind) = self.entities.get(idx).and_then(|e| match e.kind {
            Kind::Building(kind)
                if e.alive
                    && e.hp > Fixed::ZERO
                    && e.owner == owner
                    && kind != BuildingKind::CommandCenter =>
            {
                Some(kind)
            }
            _ => None,
        }) else {
            return;
        };
        let refund = self.balance.building(kind).money_cost / Fixed::from_int(2);
        self.civs[usize::from(owner.0)].money = self.civs[usize::from(owner.0)].money + refund;
        self.entities[idx].hp = Fixed::ZERO;
    }

    #[allow(
        clippy::too_many_lines,
        reason = "a flat one-arm-per-Command dispatch match; splitting it would hurt clarity"
    )]
    fn apply_command(&mut self, command: &Command) {
        match *command {
            Command::Build { owner, kind, x, y } => self.apply_build(owner, kind, x, y),
            Command::Train {
                owner,
                barracks,
                kind,
            } => self.apply_train(owner, barracks, kind),
            Command::SetRally {
                owner,
                producer,
                target,
            } => self.apply_set_rally(owner, producer, target),
            Command::Repair { owner, building } => self.apply_repair(owner, building),
            Command::Sell { owner, building } => self.apply_sell(owner, building),
            Command::Move {
                owner,
                unit,
                target,
            } => {
                let idx = unit.0 as usize;
                let valid = self.entities.get(idx).is_some_and(|e| {
                    e.alive && e.owner == owner && matches!(e.kind, Kind::Unit(_))
                });
                if valid {
                    if self.is_depth() {
                        // A direct order supersedes any auto-engagement and its
                        // anchor, and (Task 13) any forced target, and (Task 14)
                        // any queued waypoints; (Task 16) its new target may be
                        // breached once.
                        self.entities[idx].dp.anchor = None;
                        self.entities[idx].dp.engaged = None;
                        self.entities[idx].dp.forced = None;
                        self.entities[idx].dp.queue.clear();
                        self.entities[idx].dp.breach_tried = false;
                    }
                    // Plain move clears any standing attack-move stance.
                    self.order_unit_to(idx, target, false);
                }
            }
            Command::AttackMove {
                owner,
                unit,
                target,
            } => {
                let idx = unit.0 as usize;
                let valid = self.entities.get(idx).is_some_and(|e| {
                    e.alive && e.owner == owner && matches!(e.kind, Kind::Unit(_))
                });
                if valid {
                    if self.is_depth() {
                        // A direct order supersedes any auto-engagement and its
                        // anchor, and (Task 13) any forced target, and (Task 14)
                        // any queued waypoints; (Task 16) its new target may be
                        // breached once.
                        self.entities[idx].dp.anchor = None;
                        self.entities[idx].dp.engaged = None;
                        self.entities[idx].dp.forced = None;
                        self.entities[idx].dp.queue.clear();
                        self.entities[idx].dp.breach_tried = false;
                    }
                    self.order_unit_to(idx, target, true);
                }
            }
            Command::Research { owner, tech_id } => self.apply_research(owner, tech_id),
            Command::ChoosePerk { owner, perk } => {
                if self.earthfront {
                    return;
                }
                if perk < crate::game::perk::PERK_COUNT {
                    self.civs[usize::from(owner.0)].active_perks |= 1u32 << perk;
                }
            }
            Command::Ascend { owner, track } => self.apply_ascend(owner, track),
            Command::FoundBase { owner, x, y } => self.apply_found_base(owner, x, y),
            Command::UseAbility {
                owner,
                unit,
                target,
            } => self.apply_use_ability(owner, unit, target),
            Command::SetColonyAutonomy {
                owner,
                colony,
                level,
            } => {
                if let Some(c) = self.colonies.get_mut(colony.0 as usize) {
                    if c.alive && c.owner == owner {
                        c.autonomy_level = level.min(AUTONOMY_FULL);
                    }
                }
            }
            Command::SetColonyPolicy {
                owner,
                colony,
                policy,
            } => {
                if let Some(c) = self.colonies.get_mut(colony.0 as usize) {
                    if c.alive && c.owner == owner {
                        c.policy = policy;
                    }
                }
            }
            Command::DirectColony {
                owner,
                colony,
                intent,
            } => {
                if let Some(c) = self.colonies.get_mut(colony.0 as usize) {
                    if c.alive && c.owner == owner {
                        c.directive = intent;
                    }
                }
            }
            Command::SurveySpecial {
                owner,
                colony,
                kind,
            } => {
                let ci = colony.0 as usize;
                if self
                    .colonies
                    .get(ci)
                    .is_some_and(|c| c.alive && c.owner == owner)
                {
                    // Settle any skipped accrual at the OLD rate (through last tick)
                    // before the survey changes this kind's rate, so the new rate
                    // only applies from the current tick forward.
                    self.materialize_colony(ci, self.tick);
                    self.colonies[ci].knowledge_of[kind.index()] =
                        crate::game::civ::special::Knowledge::Extractable;
                }
            }
            Command::FoundColony { owner, x, y, .. } => self.apply_found_colony(owner, x, y),
            Command::FoundSector { owner, doctrine } => {
                self.add_sector(owner, doctrine);
            }
            Command::AssignColonyToSector {
                owner,
                colony,
                sector,
            } => self.apply_assign_sector(owner, colony, sector),
            Command::SetSectorDoctrine {
                owner,
                sector,
                doctrine,
            } => self.apply_set_sector_doctrine(owner, sector, doctrine),
            Command::GovernColony {
                owner,
                colony,
                doctrine,
            } => self.apply_govern_colony(owner, colony, doctrine),
            Command::Stop { owner, unit } => self.apply_depth_stop(owner, unit),
            Command::HoldPosition { owner, unit } => self.apply_depth_hold(owner, unit),
            Command::SetStance {
                owner,
                unit,
                stance,
            } => self.apply_depth_stance(owner, unit, stance),
            Command::AttackTarget {
                owner,
                unit,
                target,
            } => self.apply_depth_attack_target(owner, unit, target),
            Command::QueueMove {
                owner,
                unit,
                target,
                attack_move,
            } => self.apply_depth_queue_move(owner, unit, target, attack_move),
        }
    }

    /// Resolves [`Command::GovernColony`]: assigns `colony` to `owner`'s sector of
    /// `doctrine`, reusing the lowest-id matching sector or founding a new one.
    fn apply_govern_colony(&mut self, owner: PlayerId, colony: ColonyId, doctrine: SectorDoctrine) {
        let valid_target = self
            .colonies
            .get(colony.0 as usize)
            .is_some_and(|c| c.alive && c.owner == owner);
        if !valid_target {
            return;
        }
        let existing = self.sectors.iter().enumerate().find_map(|(si, s)| {
            (s.alive && s.owner == owner && s.doctrine == doctrine)
                .then(|| SectorId(u32::try_from(si).unwrap_or(0)))
        });
        let sector = existing.unwrap_or_else(|| self.add_sector(owner, doctrine));
        self.colonies[colony.0 as usize].sector = Some(sector);
    }

    /// Places `colony` under `sector` when both belong to `owner` (the
    /// `AssignColonyToSector` resolution). Factored out, with the doctrine setter
    /// below, to keep `apply_command` within its line budget.
    fn apply_assign_sector(&mut self, owner: PlayerId, colony: ColonyId, sector: SectorId) {
        let sector_ok = self.sector(sector).is_some_and(|s| s.owner == owner);
        if let Some(c) = self.colonies.get_mut(colony.0 as usize) {
            if c.alive && c.owner == owner && sector_ok {
                c.sector = Some(sector);
            }
        }
    }

    /// Re-doctrines `sector` when it belongs to `owner` (the `SetSectorDoctrine`
    /// resolution).
    fn apply_set_sector_doctrine(
        &mut self,
        owner: PlayerId,
        sector: SectorId,
        doctrine: SectorDoctrine,
    ) {
        if let Some(s) = self.sectors.get_mut(sector.0 as usize) {
            if s.alive && s.owner == owner {
                s.doctrine = doctrine;
            }
        }
    }

    /// Founds a new colony for `owner` at `(x, y)`: validate (buildable tile,
    /// affordable, under the per-owner cap), spend [`FOUND_COLONY_COST`], place a
    /// Command Center, and register a [`Colony`] on it (requested full autonomy,
    /// earned from zero). The new colony's spacing is enforced by the caller.
    fn apply_found_colony(&mut self, owner: PlayerId, x: u16, y: u16) {
        let p = usize::from(owner.0);
        let buildable = self
            .map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.buildable);
        // Planet gate: settling requires an UNOWNED planet and claims it. When the
        // map has zero planets assigned anywhere, founding is ungated (legacy /
        // planet-free scenarios behave exactly as before) and claims nothing.
        let target = if self.planets.is_empty() {
            None
        } else {
            match self.map.planet_at(i32::from(x), i32::from(y)) {
                Some(pid)
                    if self
                        .planets
                        .get(pid.0 as usize)
                        .is_some_and(|pl| pl.owner.is_none()) =>
                {
                    Some(pid)
                }
                // A planet that is missing or already owned blocks the founding.
                _ => return,
            }
        };
        if !buildable
            || self.civs[p].money < FOUND_COLONY_COST
            || self.count_owner_colonies(owner) >= MAX_COLONIES_PER_OWNER
        {
            return;
        }
        self.civs[p].money = self.civs[p].money - FOUND_COLONY_COST;
        let cc = self.add_building(owner, BuildingKind::CommandCenter, x, y);
        if let Some(pid) = target {
            if let Some(pl) = self.planets.get_mut(pid.0 as usize) {
                pl.owner = Some(owner);
                pl.seat = Some(cc);
            }
        }
        self.add_colony(owner, cc, AUTONOMY_FULL);
    }

    /// How many living colonies `owner` holds.
    fn count_owner_colonies(&self, owner: PlayerId) -> usize {
        self.colonies
            .iter()
            .filter(|c| c.alive && c.owner == owner)
            .count()
    }

    /// The first row-major buildable tile at least [`MIN_COLONY_SPACING`] from
    /// every existing Command Center and from every `exclude` tile (sites already
    /// planned this tick). Deterministic; `None` if the map is too crowded.
    fn first_colony_site(&self, exclude: &[(u16, u16)]) -> Option<(u16, u16)> {
        let ccs: Vec<(u16, u16)> = self
            .entities
            .iter()
            .filter(|e| e.alive && matches!(e.kind, Kind::Building(BuildingKind::CommandCenter)))
            .filter_map(|e| e.tile)
            .collect();
        let spacing = i32::from(MIN_COLONY_SPACING);
        for y in 0..self.map.height() {
            for x in 0..self.map.width() {
                if !self
                    .map
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.buildable)
                {
                    continue;
                }
                if exclude.contains(&(x, y)) {
                    continue;
                }
                let clear = ccs.iter().all(|&(cx, cy)| {
                    (i32::from(cx) - i32::from(x)).abs() + (i32::from(cy) - i32::from(y)).abs()
                        >= spacing
                });
                if clear {
                    return Some((x, y));
                }
            }
        }
        None
    }

    /// Casts `unit`'s ability at `target`: validate (alive, owned, carries an
    /// ability, off cooldown, not stunned, target in range), resolve the effect
    /// instantly over the entity list in index order, then start the cooldown.
    /// Deterministic — fixed magnitudes, no RNG, order-independent per cast.
    fn apply_use_ability(&mut self, owner: PlayerId, unit: EntityId, target: Vec2) {
        use crate::game::ability::{ability_for, def, AbilityKind};
        if self.earthfront {
            return;
        }
        let idx = unit.0 as usize;
        let Some(caster) = self.entities.get(idx) else {
            return;
        };
        if !caster.alive || caster.owner != owner || caster.ability_cd > 0 || caster.stun_ticks > 0
        {
            return;
        }
        let Kind::Unit(uk) = caster.kind else { return };
        let Some(kind) = ability_for(uk) else { return };
        let d = def(kind);
        if (target - caster.pos).length_squared() > d.range * d.range {
            return;
        }
        let radius_sq = d.radius * d.radius;
        #[allow(
            clippy::cast_possible_truncation,
            reason = "tick fits u32 for any real game"
        )]
        let tick = self.tick as u32;
        match kind {
            AbilityKind::Barrage => {
                // Shell volley: shield-absorbing damage to every enemy in the
                // blast (buildings included — it is a siege tool). Kills credit
                // the caster's veterancy, mirroring run_combat.
                let mut kills = 0u32;
                for e in &mut self.entities {
                    if !e.alive || e.owner == owner {
                        continue;
                    }
                    if (e.pos - target).length_squared() > radius_sq {
                        continue;
                    }
                    e.last_combat_tick = tick;
                    let was_alive = e.hp > Fixed::ZERO;
                    let absorbed = if e.shield < d.magnitude {
                        e.shield
                    } else {
                        d.magnitude
                    };
                    e.shield = e.shield - absorbed;
                    e.hp = e.hp - (d.magnitude - absorbed);
                    if was_alive && e.hp <= Fixed::ZERO {
                        kills += 1;
                    }
                }
                let caster = &mut self.entities[idx];
                caster.kills += kills;
                caster.rank = rank_for_kills(caster.kills);
            }
            AbilityKind::EmpBurst => {
                // Stun enemy UNITS in the blast (structures shrug it off). Already
                // stunned or freshly-released (immune) units are unaffected, so
                // massed EMPs cannot chain a clump into a permanent lock.
                for e in &mut self.entities {
                    if !e.alive || e.owner == owner || !matches!(e.kind, Kind::Unit(_)) {
                        continue;
                    }
                    if e.stun_ticks > 0 || e.stun_immunity > 0 {
                        continue;
                    }
                    if (e.pos - target).length_squared() > radius_sq {
                        continue;
                    }
                    e.stun_ticks = d.duration;
                }
            }
            AbilityKind::NaniteField => {
                // Heal friendly UNITS in the field, capped at their max HP.
                for e in &mut self.entities {
                    if !e.alive || e.owner != owner || !matches!(e.kind, Kind::Unit(_)) {
                        continue;
                    }
                    if (e.pos - target).length_squared() > radius_sq {
                        continue;
                    }
                    let cap = max_hp(&self.balance, e.kind);
                    let healed = e.hp + d.magnitude;
                    e.hp = if healed > cap { cap } else { healed };
                }
            }
        }
        self.entities[idx].ability_cd = d.cooldown;
    }

    /// Begins researching `tech_id`: validate prereqs (full DAG), the doctrine
    /// fork lock, and affordability, then deduct + start the timer. Foundation
    /// (tier 0) techs are Minerals-paid and need no lab (so research bootstraps
    /// before the Lab is unlocked); later tiers are Research-pool-paid and need a
    /// lab. Mirrors the validate-then-resolve pattern.
    fn apply_research(&mut self, owner: PlayerId, tech_id: u32) {
        if self.earthfront {
            self.start_earthfront_research(owner, tech_id);
            return;
        }
        if matches!(self.phase, GamePhase::Survey) {
            return; // can't research before founding a base
        }
        let p = usize::from(owner.0);
        let Some(node) = tech_grid::node(tech_id) else {
            return;
        };
        let set = self.civs[p].researched_techs;
        let already = set.get(tech_id);
        let busy = self.civs[p].active_research.is_some();
        let prereq_ok = node.prereqs.iter().all(|&r| set.get(r));
        // Era 0 is the bootstrap (researchable with no lab); every later era needs
        // a Research Lab. Paid in all three resources from the node's costs.
        let lab_ok = node.era == 0 || self.has_research_lab(owner);
        let (mc, ec, lc) = (
            Fixed::from_int(i32::try_from(node.money).unwrap_or(i32::MAX)),
            Fixed::from_int(i32::try_from(node.energy).unwrap_or(i32::MAX)),
            Fixed::from_int(i32::try_from(node.labour).unwrap_or(i32::MAX)),
        );
        let affordable = lab_ok
            && self.civs[p].money >= mc
            && self.civs[p].energy >= ec
            && self.civs[p].labour >= lc;
        if !already && !busy && prereq_ok && affordable {
            self.civs[p].money = self.civs[p].money - mc;
            self.civs[p].energy = self.civs[p].energy - ec;
            self.civs[p].labour = self.civs[p].labour - lc;
            self.civs[p].active_research = Some((tech_id, node.duration));
        }
    }

    /// Founds the Command Center: the Survey-ending act. Validate-then-resolve —
    /// Survey phase only, on a buildable tile. Founding beside an Ore deposit
    /// grants the colony bonus (the "green tile" payoff the survey overlay shows).
    fn apply_found_base(&mut self, owner: PlayerId, x: u16, y: u16) {
        if matches!(self.phase, GamePhase::Active) {
            return;
        }
        let buildable = self
            .map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.buildable);
        if !buildable || (self.earthfront && x > self.map.width() / 3) {
            return;
        }
        let cc = self.add_building(owner, BuildingKind::CommandCenter, x, y);
        self.phase = GamePhase::Active;
        self.phase_started = self.tick;
        // Register the founded base as the owner's first colony. It starts fully
        // MANUAL (autonomy 0) — the player drives it directly and opts into
        // delegation by raising its autonomy; this makes the autonomous-colony
        // layer reachable in a normal Survival run.
        self.add_colony(owner, cc, 0);
        if self.earthfront {
            for i in 0..4 {
                self.add_unit(
                    owner,
                    UnitKind::Infantry,
                    tile_center(x, y) + Vec2::new(Fixed::ONE, Fixed::from_int(i)),
                );
            }
        }
        let near_ore = self.map.deposits().any(|(dx, dy, d)| {
            d.kind == crate::game::map::DepositKind::Ore
                && crate::game::hex::distance((x, y), (dx, dy)) <= 1
        });
        if near_ore {
            let p = usize::from(owner.0);
            self.civs[p].money = self.civs[p].money + FOUNDING_ORE_BONUS;
        }
    }

    /// Buys the next level of doctrine `track` for `owner`, if unlocked and
    /// affordable. FORGE (the money-only track) needs no lab; the research
    /// tracks require a Research Lab. Validate-then-spend, mirroring `Research`.
    fn apply_ascend(&mut self, owner: PlayerId, track: u8) {
        if self.earthfront {
            return;
        }
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return;
        }
        let p = usize::from(owner.0);
        let level = self.civs[p].doctrine_levels[t];
        if level >= DOCTRINE_LEVEL_CAP {
            return;
        }
        // Doctrines are now paid entirely from Money (the old research portion is
        // folded into the Money cost). FORGE needs no lab; the rest do.
        let (min_cost, res_cost) = ascend_cost(t, level);
        let total = min_cost + res_cost;
        let lab_ok = t == DOC_FORGE || self.has_research_lab(owner);
        if lab_ok && self.civs[p].money >= total {
            self.civs[p].money = self.civs[p].money - total;
            self.civs[p].doctrine_levels[t] = (level + 1).min(DOCTRINE_LEVEL_CAP);
        }
    }

    fn world_to_tile(&self, p: Vec2) -> (u16, u16) {
        crate::game::hex::from_world(p, self.map.width(), self.map.height())
    }

    /// The next grid node the AI should research.
    ///
    /// Scans every eligible (prereqs met, lab available past era 0) + affordable
    /// (all three resources) node and picks the best by priority: era keys first
    /// (they advance the era), then nodes that unlock a real building/unit (the
    /// lab, army, and defenses that give the AI breadth), then the Energy spine
    /// that leads to the next key, then everything else, with the lowest id
    /// breaking ties. `&self`, RNG-free, row-major — fully replayable.
    fn ai_next_research(&self, player: PlayerId) -> Option<u32> {
        if self.earthfront {
            return self.earthfront_available_research(player).first().copied();
        }
        let p = usize::from(player.0);
        let set = self.civs[p].researched_techs;
        let mut best: Option<(u8, u32)> = None; // (priority, id); lower wins
        for node in &crate::game::tech_grid_table::GRID {
            if set.get(node.id) || !node.prereqs.iter().all(|&r| set.get(r)) {
                continue;
            }
            let lab_ok = node.era == 0 || self.has_research_lab(player);
            if !lab_ok {
                continue;
            }
            let (mc, ec, lc) = (
                Fixed::from_int(i32::try_from(node.money).unwrap_or(i32::MAX)),
                Fixed::from_int(i32::try_from(node.energy).unwrap_or(i32::MAX)),
                Fixed::from_int(i32::try_from(node.labour).unwrap_or(i32::MAX)),
            );
            if self.civs[p].money < mc || self.civs[p].energy < ec || self.civs[p].labour < lc {
                continue;
            }
            let priority = if tech_grid::is_era_key(node.id) {
                0
            } else if tech_grid::real_building(node.id).is_some()
                || tech_grid::real_unit(node.id).is_some()
            {
                1
            } else if node.branch == 1 {
                2
            } else {
                3
            };
            let cand = (priority, node.id);
            match best {
                Some(b) if b <= cand => {}
                _ => best = Some(cand),
            }
        }
        best.map(|(_, id)| id)
    }

    /// How many researched grid nodes `player` holds in branch index `branch`
    /// (C=0,E=1,M=2,P=3,W=4,D=5,B=6,S=7,X=8,G=9). Each researched node grants a
    /// small flat rider to its branch's effect — research strengthens the army.
    fn grid_branch_count(&self, player: PlayerId, branch: u8) -> u32 {
        let set = &self.civs[usize::from(player.0)].researched_techs;
        let mut n = 0u32;
        for node in &crate::game::tech_grid_table::GRID {
            if node.branch == branch && set.get(node.id) {
                n += 1;
            }
        }
        n
    }
    fn branch_rider(&self, p: PlayerId, branch: u8, per_node: Fixed) -> Fixed {
        if self.earthfront {
            return Fixed::ZERO;
        }
        per_node * Fixed::from_int(i32::try_from(self.grid_branch_count(p, branch)).unwrap_or(0))
    }
    fn player_weapon_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_rider(p, 4, GRID_WEAPON_PER_NODE) + self.doctrine_weapon_bonus(p)
    }
    fn player_armor_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_rider(p, 5, GRID_ARMOR_PER_NODE) + self.doctrine_armor_bonus(p)
    }
    fn player_economy_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_rider(p, 1, GRID_ECON_PER_NODE)
    }
    fn player_mobility_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_rider(p, 3, GRID_MOB_PER_NODE)
    }
    fn player_shield_max(&self, p: PlayerId) -> Fixed {
        if self.earthfront {
            return Fixed::ZERO;
        }
        self.branch_rider(p, 5, GRID_SHIELD_PER_NODE) + self.doctrine_shield_bonus(p)
    }
    /// Flat weapon-damage bonus from the doctrine tracks (Weapons + Forge).
    fn doctrine_weapon_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.civs[usize::from(p.0)].doctrine_levels;
        WEAPON_STEP * Fixed::from_int(i32::from(lv[DOC_WEAPONS]))
            + FORGE_WEAPON_STEP * Fixed::from_int(i32::from(lv[DOC_FORGE]))
    }
    /// Flat armor-mitigation bonus from the doctrine tracks (Armor + Forge).
    fn doctrine_armor_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.civs[usize::from(p.0)].doctrine_levels;
        ARMOR_STEP * Fixed::from_int(i32::from(lv[DOC_ARMOR]))
            + FORGE_ARMOR_STEP * Fixed::from_int(i32::from(lv[DOC_FORGE]))
    }
    /// Shield-max bonus from the Vitality doctrine track.
    fn doctrine_shield_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.civs[usize::from(p.0)].doctrine_levels;
        VITALITY_STEP * Fixed::from_int(i32::from(lv[DOC_VITALITY]))
    }
    /// Public accessor for the UI and tests outside the module.
    #[must_use]
    pub fn shield_max(&self, player: PlayerId) -> Fixed {
        self.player_shield_max(player)
    }
    fn player_has_antigrav(&self, p: PlayerId) -> bool {
        if self.earthfront {
            return false;
        }
        // Any researched Gravity-branch (9) node grants terrain-ignoring movement.
        self.grid_branch_count(p, 9) > 0
    }
    /// Returns `true` if the player has researched an Anti-Grav Drives tech.
    #[must_use]
    pub fn has_antigrav(&self, p: PlayerId) -> bool {
        self.player_has_antigrav(p)
    }

    /// Regenerates each entity's shield toward its owner's current max while out
    /// of combat (no hit for `REGEN_DELAY` ticks). Also clamps to the current max.
    fn run_shields(&mut self) {
        const REGEN_DELAY: u32 = 90;
        let regen = Fixed::ONE;
        #[allow(
            clippy::cast_possible_truncation,
            reason = "tick fits u32 for any real game"
        )]
        let tick = self.tick as u32;
        let max: Vec<Fixed> = (0..self.civs.len())
            .map(|p| self.player_shield_max(PlayerId(u16::try_from(p).unwrap())))
            .collect();
        for e in &mut self.entities {
            if !e.alive {
                continue;
            }
            let m = max[usize::from(e.owner.0)];
            if e.shield > m {
                e.shield = m;
            }
            if tick.saturating_sub(e.last_combat_tick) >= REGEN_DELAY && e.shield < m {
                let r = e.shield + regen;
                e.shield = if r > m { m } else { r };
            }
        }
    }

    /// Produces the three resources for every player: Energy and Labour
    /// stockpiles from buildings' per-tick output, and Money from extractor
    /// mining plus the Economy tech bonus and the Logistics perk. The old
    /// power-balance gradient is gone — Energy is a spendable stockpile. Unit
    /// factories pause at zero Energy, while completed buildings keep producing.
    fn run_economy(&mut self) {
        if self.earthfront {
            return;
        }
        let mut energy_out = alloc::vec![0i32; self.civs.len()];
        let mut labour_out = alloc::vec![0i32; self.civs.len()];
        for e in &self.entities {
            if !e.alive || e.construction_remaining > 0 {
                continue;
            }
            if let Kind::Building(b) = e.kind {
                let st = self.balance.building(b);
                let p = usize::from(e.owner.0);
                energy_out[p] += st.energy_output;
                labour_out[p] += st.labour_output;
            }
        }
        for p in 0..self.civs.len() {
            // Energy and Labour are bounded stockpiles: they fill toward a ceiling
            // (use-it-or-bank-it tempo) rather than running away to millions.
            self.civs[p].energy = cap_at(
                self.civs[p].energy + Fixed::from_int(energy_out[p]),
                ENERGY_CAP,
            );
            self.civs[p].labour = cap_at(
                self.civs[p].labour + Fixed::from_int(labour_out[p]),
                LABOUR_CAP,
            );
            // Money income: the Economy tech rider, scaled by the Logistics perk.
            let econ = self.player_economy_bonus(PlayerId(u16::try_from(p).unwrap()));
            let mut money_income = econ;
            if self.civs[p].active_perks & (1 << crate::game::perk::LOGISTICS) != 0 {
                money_income = money_income * Fixed::from_ratio(3, 2);
            }
            self.civs[p].money = self.civs[p].money + money_income;
            // Escalating empire-administration upkeep: the more colonies this player
            // holds, the more Money it bleeds per tick, scaling super-linearly so a
            // wide runaway empire pays disproportionately more per colony than a small
            // one (the conquest-snowball brake). Clamp at zero so the stockpile never
            // runs negative on upkeep alone — a broke empire simply can't fund growth.
            // ZERO in the colony-free survival run, so the golden hash is unaffected.
            let upkeep = self.empire_upkeep(PlayerId(u16::try_from(p).unwrap()));
            let after = self.civs[p].money - upkeep;
            self.civs[p].money = if after > Fixed::ZERO {
                after
            } else {
                Fixed::ZERO
            };
        }
        // Extractors mine the deposit they stand on — all deposits yield Money.
        let mut to_mine: alloc::vec::Vec<(u16, u16, u16, i32)> = alloc::vec::Vec::new();
        for e in &self.entities {
            if !e.alive || e.construction_remaining > 0 {
                continue;
            }
            if let Kind::Building(b) = e.kind {
                let rate = self.balance.building(b).mine_rate;
                if rate > 0 {
                    if let Some((tx, ty)) = e.tile {
                        to_mine.push((tx, ty, e.owner.0, rate));
                    }
                }
            }
        }
        for (tx, ty, owner, rate) in to_mine {
            if self.map.deposit(tx, ty).is_none() {
                continue;
            }
            let p = usize::from(owner);
            let want = u32::try_from(rate.max(0)).unwrap_or(0);
            let mined = self.map.mine(tx, ty, want);
            let amount = Fixed::from_int(i32::try_from(mined).unwrap_or(0));
            self.civs[p].money = self.civs[p].money + amount;
        }
    }

    /// The per-tick accrual rate of special `kind` for colony `ci`: its static
    /// **Field** intensity once the colony has surveyed it Extractable, otherwise
    /// zero. A pure, `rng`-free sample of the static field at the seat tile
    /// (determinism rule D1) — Hazard/Finite kinds never accrue here.
    fn colony_special_rate(
        &self,
        ci: usize,
        kind: crate::game::civ::special::SpecialKind,
    ) -> Fixed {
        use crate::game::civ::special::{field_intensity, Knowledge, SpecialClass};
        let c = &self.colonies[ci];
        if c.knowledge_of[kind.index()] != Knowledge::Extractable
            || !matches!(kind.class(), SpecialClass::Field)
        {
            return Fixed::ZERO;
        }
        match self
            .entities
            .get(c.seat.0 as usize)
            .filter(|e| e.alive)
            .and_then(|e| e.tile)
        {
            Some((tx, ty)) => field_intensity(self.field_seed, tx, ty, kind),
            None => Fixed::ZERO,
        }
    }

    /// The planet a colony sits on (its seat tile → planet id).
    fn colony_planet(&self, ci: usize) -> Option<PlanetId> {
        self.colony_planet_for_seat(self.colonies[ci].seat)
    }

    /// The planet a colony seat entity sits on (its tile → planet id).
    fn colony_planet_for_seat(&self, seat: EntityId) -> Option<PlanetId> {
        let (x, y) = self.entities.get(seat.0 as usize)?.tile?;
        self.map.planet_at(i32::from(x), i32::from(y))
    }

    /// Whether the colony on planet `(x,y)` can hold another building
    /// (count of buildings on the planet < `BUILDINGS_PER_POP` × colony
    /// population). Open space (no planet) is ungated and returns true.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "building count on a single planet fits u32 for any real game"
    )]
    fn under_building_cap(&self, x: u16, y: u16) -> bool {
        let Some(pid) = self.map.planet_at(i32::from(x), i32::from(y)) else {
            return true;
        };
        // Population of the colony seated on this planet (0 if none).
        let pop = self
            .colonies
            .iter()
            .find(|c| c.alive && self.colony_planet_for_seat(c.seat) == Some(pid))
            .map_or(0, |c| c.population);
        let count = self
            .entities
            .iter()
            .filter(|e| {
                e.alive
                    && matches!(e.kind, Kind::Building(_))
                    && e.tile.is_some_and(|(tx, ty)| {
                        self.map.planet_at(i32::from(tx), i32::from(ty)) == Some(pid)
                    })
            })
            .count();
        // pop.max(1) so a colony always holds at least BUILDINGS_PER_POP
        // buildings (avoids a 0-pop deadlock; population starts at 1 anyway).
        (count as u32) < BUILDINGS_PER_POP * pop.max(1)
    }

    /// Tiles belonging to the colony's planet (for the housing base). O(1): reads
    /// the [`Sim::planet_tiles`] cache built in `rebuild_planet_yield`.
    fn colony_planet_tiles(&self, ci: usize) -> u32 {
        let Some(pid) = self.colony_planet(ci) else {
            return 0;
        };
        self.planet_tiles
            .get(usize::from(pid.0))
            .copied()
            .unwrap_or(0)
    }

    /// Population cap = `housing_base(planet tiles)` + housing buildings on the
    /// planet. The Command Center is the only "housing" building in this slice.
    fn colony_pop_cap(&self, ci: usize) -> u32 {
        let base = Balance::housing_base(self.colony_planet_tiles(ci));
        let Some(pid) = self.colony_planet(ci) else {
            return base;
        };
        let mut housing = 0u32;
        for e in &self.entities {
            if e.alive && matches!(e.kind, Kind::Building(BuildingKind::CommandCenter)) {
                if let Some((x, y)) = e.tile {
                    if self.map.planet_at(i32::from(x), i32::from(y)) == Some(pid) {
                        housing += HOUSING_PER_BUILDING;
                    }
                }
            }
        }
        base + housing
    }

    /// Mature: at population cap AND earned full autonomy.
    fn colony_mature(&self, ci: usize) -> bool {
        let c = &self.colonies[ci];
        c.population >= self.colony_pop_cap(ci) && c.earned_autonomy() >= AUTONOMY_FULL
    }

    /// Per-tick food rate (terrain only) — the planet's aggregate food yield.
    fn colony_food_rate(&self, ci: usize) -> Fixed {
        let Some(pid) = self.colony_planet(ci) else {
            return Fixed::ZERO;
        };
        self.planet_yield_of(pid)[0]
    }

    /// Per-tick output rate for resource `k` (0=Money, 1=Energy, 2=Labour):
    /// `pop_factor(population)` × the planet's terrain yield for that resource.
    /// Independent of live building count, so it is constant during a Dormant
    /// (mature) window (rule D3). Resource index `k` maps to `planet_yield[k+1]`
    /// (slot 0 is food).
    fn colony_output_rate(&self, ci: usize, k: usize) -> Fixed {
        let Some(pid) = self.colony_planet(ci) else {
            return Fixed::ZERO;
        };
        Balance::pop_factor(self.colonies[ci].population) * self.planet_yield_of(pid)[k + 1]
    }

    /// Autonomy-earning rate per qualifying tick, scaled by population (bigger
    /// cities earn autonomy faster). Constant while mature (population frozen),
    /// so the closed-form hash reconstruction stays exact (rule D3).
    fn colony_autonomy_rate(&self, ci: usize) -> u32 {
        1 + self.colonies[ci].population / AUTONOMY_POP_DIVISOR
    }

    /// Brings colony `ci`'s skipped scalar accumulators up to tick `next` (i.e.
    /// through tick `next - 1`) with the exact closed form `stored + rate ×
    /// elapsed` — autonomy progress accrues one qualifying tick per elapsed tick,
    /// Field stockpiles accrue `rate × elapsed`. The stockpile math widens to
    /// `i128` and saturates (determinism rules D2/D6), so the single multiply is
    /// bit-identical to `elapsed` sequential adds. A no-op when already current,
    /// which keeps non-skipped colonies (materialized every tick) on the same path
    /// they always took.
    fn materialize_colony(&mut self, ci: usize, next: u64) {
        use crate::game::civ::special::SpecialKind;
        let elapsed = next.saturating_sub(self.colonies[ci].last_sync_tick);
        if elapsed == 0 {
            return;
        }
        let steps = u32::try_from(elapsed).unwrap_or(u32::MAX);
        // Population-scaled autonomy accrual. The rate is frozen while the colony
        // is Dormant (population is frozen at cap), so the hash reconstruction in
        // hash_colony_layer uses the identical formula over the same elapsed span
        // (rule D3) — skip == full.
        let auto_rate = self.colony_autonomy_rate(ci);
        self.colonies[ci].autonomy_progress = self.colonies[ci]
            .autonomy_progress
            .saturating_add(steps.saturating_mul(auto_rate));
        for kind in SpecialKind::ALL {
            let rate = self.colony_special_rate(ci, kind);
            if rate.to_bits() != 0 {
                let k = kind.index();
                self.colonies[ci].stockpile[k] = Fixed::from_bits(closed_form_bits(
                    self.colonies[ci].stockpile[k],
                    rate,
                    elapsed,
                ));
            }
        }
        // A mature colony banks its per-resource output into its own treasury at the
        // constant Dormant rate (its population is frozen at cap, so the rate is
        // fixed over the whole window). This mirrors, byte-for-byte, the closed-form
        // term folded into the state hash (rule D3): stored + rate·elapsed, i128
        // saturating. An immature (Active, growing) colony never reaches this line
        // with elapsed>0 — it is materialized every tick (elapsed==1, returns above
        // only when 0) and feeds the empire pool instead, never its treasury — so
        // gating on maturity keeps the two banking paths disjoint and exact.
        if self.colony_mature(ci) {
            for k in 0..self.colonies[ci].treasury.len() {
                let rate = self.colony_output_rate(ci, k);
                if rate.to_bits() != 0 {
                    self.colonies[ci].treasury[k] = Fixed::from_bits(closed_form_bits(
                        self.colonies[ci].treasury[k],
                        rate,
                        elapsed,
                    ));
                }
            }
        }
        self.colonies[ci].last_sync_tick = next;
    }

    /// Advances every colony's per-tick scalar accumulators (earned-autonomy
    /// progress + extractable Field stockpiles) for this tick. A
    /// [`Dormant`](crate::game::civ::SimDetail::Dormant) colony skips the work and
    /// is caught up in closed form when it wakes (or read closed-form by the state
    /// hash) — so its hashed state is identical to a full-fidelity run every tick
    /// (rule D3), it just costs less to produce. The detail class read here is the
    /// previous tick's (set by [`run_lod`](Self::run_lod) after this pass).
    fn run_colony_accrual(&mut self) {
        if self.earthfront {
            return;
        }
        let next = self.tick.saturating_add(1);
        for ci in 0..self.colonies.len() {
            if !self.colonies[ci].alive {
                continue;
            }
            // The work-skip: a Dormant colony is left frozen and caught up later in
            // closed form. Its hashed state is unchanged (rule D3) — see the hash
            // reconstruction and the determinism tests in this module.
            if self.lod_skip && self.colonies[ci].detail == SimDetail::Dormant {
                continue;
            }
            self.materialize_colony(ci, next);
            // Growth + real-time income for DEVELOPING (immature) colonies. Immature
            // colonies will be kept Active by colony_lod's maturity rule (C5); the
            // inlined `population < cap || autonomy < full` gate here is self-sufficient
            // regardless, so this is always an elapsed-1 path: no closed form needed
            // (rule D3). Mature colonies bank their output in `treasury` inside
            // materialize_colony instead.
            let cap = self.colony_pop_cap(ci);
            let mature = self.colonies[ci].population >= cap
                && self.colonies[ci].earned_autonomy() >= AUTONOMY_FULL;
            if !mature {
                let owner = usize::from(self.colonies[ci].owner.0);
                // Fix 2: only accrue/spend food while there is room to grow (a pop-capped
                // but not-yet-mature colony must not accumulate food forever -> Fixed
                // overflow).
                if self.colonies[ci].population < cap {
                    self.colonies[ci].food = self.colonies[ci].food + self.colony_food_rate(ci);
                    while self.colonies[ci].population < cap {
                        let threshold = Balance::food_threshold(self.colonies[ci].population);
                        if self.colonies[ci].food < threshold {
                            break;
                        }
                        self.colonies[ci].food = self.colonies[ci].food - threshold;
                        self.colonies[ci].population += 1;
                    }
                }
                // Real-time income to the empire pool (additional to run_economy).
                let dm = self.colony_output_rate(ci, 0);
                let de = self.colony_output_rate(ci, 1);
                let dl = self.colony_output_rate(ci, 2);
                self.civs[owner].money = self.civs[owner].money + dm;
                self.civs[owner].energy = cap_at(self.civs[owner].energy + de, ENERGY_CAP);
                self.civs[owner].labour = cap_at(self.civs[owner].labour + dl, LABOUR_CAP);
            }
        }
    }

    /// The determinism-safe LOD class for colony `ci`: a pure function of hashed
    /// state — Tactical when an enemy unit is within range of the seat, Dormant
    /// once the colony is mature and quiet, else Active. Never reads view state.
    fn colony_lod(&self, ci: usize) -> SimDetail {
        // 8 tiles, squared.
        const TACTICAL_RANGE_SQ: Fixed = Fixed::from_int(64);
        // Maturity (population at cap AND full autonomy) is the Dormant precondition;
        // compute it up front (a plain &self read, coexists with the `c` borrow below).
        let mature = self.colony_mature(ci);
        let c = &self.colonies[ci];
        if let Some(seat) = self.entities.get(c.seat.0 as usize).filter(|e| e.alive) {
            let pos = seat.pos;
            let threatened = self.entities.iter().any(|e| {
                if !e.alive || e.owner == c.owner || !matches!(e.kind, Kind::Unit(_)) {
                    return false;
                }
                let dx = e.pos.x - pos.x;
                let dy = e.pos.y - pos.y;
                dx * dx + dy * dy <= TACTICAL_RANGE_SQ
            });
            if threatened {
                return SimDetail::Tactical;
            }
        }
        // Dormant ONLY when mature. An immature colony stays Active so its non-linear
        // growth always runs full-fidelity and is never caught up by the closed form
        // (rule D3).
        if mature {
            SimDetail::Dormant
        } else {
            SimDetail::Active
        }
    }

    /// Recomputes every living colony's LOD class (deterministic; see
    /// [`Sim::colony_lod`]). The sim runs full fidelity regardless — the class is
    /// a render/CPU hint, so it cannot perturb results.
    fn run_lod(&mut self) {
        for ci in 0..self.colonies.len() {
            if self.colonies[ci].alive {
                self.colonies[ci].detail = self.colony_lod(ci);
            }
        }
    }

    /// Advances each player's in-progress research one tick.
    ///
    /// Runs every tick after `run_economy`, so the tick on which a research is
    /// started also counts as its first tick of progress: a `duration`-tick tech
    /// completes after `duration` ticks counting the start tick.
    fn run_research(&mut self) {
        if self.earthfront {
            self.run_earthfront_research();
            return;
        }
        // No research before a base is founded.
        if matches!(self.phase, GamePhase::Survey) {
            return;
        }
        // Tick each player's research; collect completions, then apply their grid
        // unlocks (era bump + real building/unit) through the shared helper so the
        // live completion path and the test-only `grant_tech` stay in lockstep.
        let mut completed: Vec<(usize, u32)> = Vec::new();
        for (p, player) in self.civs.iter_mut().enumerate() {
            if let Some((id, ticks)) = player.active_research {
                if ticks <= 1 {
                    player.researched_techs.set(id);
                    player.active_research = None;
                    completed.push((p, id));
                } else {
                    player.active_research = Some((id, ticks - 1));
                }
            }
        }
        for (p, id) in completed {
            self.apply_grid_unlocks(p, id);
        }
    }

    /// Advances placed structures toward becoming operational. A Refinery
    /// deploys its included ore truck exactly once, on the completion tick.
    fn run_construction(&mut self) {
        let mut completed_refineries: Vec<(PlayerId, Vec2)> = Vec::new();
        for e in &mut self.entities {
            if !e.alive || e.construction_remaining == 0 {
                continue;
            }
            if self.earthfront && e.kind != Kind::Building(BuildingKind::PowerPlant) {
                e.work_fraction += e.power_fraction;
                if e.work_fraction < 1000 {
                    continue;
                }
                e.work_fraction -= 1000;
            }
            e.construction_remaining -= 1;
            if e.construction_remaining == 0 && e.kind == Kind::Building(BuildingKind::Refinery) {
                completed_refineries.push((e.owner, e.pos));
            }
        }
        for (owner, pos) in completed_refineries {
            if self.earthfront && self.supply_used(owner) >= self.supply_cap(owner) {
                continue;
            }
            self.add_unit(
                owner,
                UnitKind::Harvester,
                pos + Vec2::new(Fixed::ONE, Fixed::ZERO),
            );
        }
    }

    fn run_production(&mut self) {
        let prototype_reserved: Vec<Option<EntityId>> = (0..self.civs.len())
            .map(|p| self.prototype_factory(PlayerId(u16::try_from(p).unwrap_or(0))))
            .collect();
        let spawn_positions: Vec<Option<Vec2>> = self
            .entities
            .iter()
            .map(|e| {
                if !self.earthfront {
                    return Some(e.pos + Vec2::new(Fixed::ONE, Fixed::ZERO));
                }
                if e.build_queue.is_empty() {
                    return None;
                }
                let (x, y) = e.tile?;
                hex::neighbors(x, y).into_iter().find_map(|(nx, ny)| {
                    if !self.map.tile(nx, ny).is_some_and(|t| t.passable) {
                        return None;
                    }
                    Some(hex::center(
                        u16::try_from(nx).ok()?,
                        u16::try_from(ny).ok()?,
                    ))
                })
            })
            .collect();
        let mut spawns: Vec<(PlayerId, UnitKind, Vec2, Option<Vec2>)> = Vec::new();
        for (idx, e) in self.entities.iter_mut().enumerate() {
            if !e.alive
                || e.construction_remaining > 0
                || !matches!(
                    e.kind,
                    Kind::Building(
                        BuildingKind::Barracks
                            | BuildingKind::Refinery
                            | BuildingKind::VehicleFactory
                            | BuildingKind::Airfield
                    )
                )
            {
                continue;
            }
            if !self.earthfront && self.civs[usize::from(e.owner.0)].energy <= Fixed::ZERO {
                continue;
            }
            if e.kind == Kind::Building(BuildingKind::VehicleFactory)
                && prototype_reserved[usize::from(e.owner.0)].map(|id| id.0 as usize) == Some(idx)
            {
                continue;
            }
            if let Some(&front) = e.build_queue.first() {
                if self.earthfront {
                    let speed = if self.civs[usize::from(e.owner.0)].researched_techs.get(7) {
                        1500
                    } else if self.civs[usize::from(e.owner.0)].researched_techs.get(6) {
                        1250
                    } else {
                        1000
                    };
                    e.work_fraction += e.power_fraction * speed / 1000;
                    e.build_progress += e.work_fraction / 1000;
                    e.work_fraction %= 1000;
                } else {
                    e.build_progress += 1;
                }
                if e.build_progress >= self.balance.unit(front).build_time {
                    let Some(pos) = spawn_positions[idx] else {
                        e.build_progress = self.balance.unit(front).build_time;
                        continue;
                    };
                    e.build_progress = 0;
                    e.build_queue.remove(0);
                    spawns.push((e.owner, front, pos, e.rally));
                }
            }
        }
        for (owner, kind, pos, rally) in spawns {
            let unit = self.add_unit(owner, kind, pos);
            if let Some(target) = rally {
                self.order_unit_to(unit.0 as usize, target, false);
            }
        }
    }

    /// Drives vulnerable ore trucks through the same deterministic movement
    /// system as combat units. They seek the nearest active deposit, load finite
    /// ore in chunks, and deliver it to the nearest friendly Refinery. Destroying
    /// the truck loses its cargo, making economic raids strategically meaningful.
    fn run_harvesters(&mut self) {
        let covered_deposits: Vec<(u16, u16)> = self
            .entities
            .iter()
            .filter(|e| {
                e.alive
                    && e.construction_remaining == 0
                    && e.kind == Kind::Building(BuildingKind::Refinery)
            })
            .filter_map(|e| e.tile)
            .collect();
        let harvesters: Vec<usize> = self
            .entities
            .iter()
            .enumerate()
            .filter(|(_, e)| e.alive && e.kind == Kind::Unit(UnitKind::Harvester))
            .map(|(i, _)| i)
            .collect();

        for idx in harvesters {
            let owner = self.entities[idx].owner;
            let pos = self.entities[idx].pos;
            let returning = self.entities[idx].harvest_returning;
            let moving = self.entities[idx].move_target.is_some();

            if returning {
                let refinery = self
                    .entities
                    .iter()
                    .enumerate()
                    .filter(|(_, e)| {
                        e.alive
                            && e.owner == owner
                            && e.construction_remaining == 0
                            && e.kind == Kind::Building(BuildingKind::Refinery)
                            && (!self.earthfront || e.ore_buffer < earthfront::REFINERY_CAPACITY)
                    })
                    .min_by_key(|(_, e)| (e.pos - pos).length_squared().to_bits())
                    .map(|(i, e)| (i, e.pos));
                let Some((refinery_id, target)) = refinery else {
                    // Retain cargo when the receiving network is full or destroyed.
                    continue;
                };
                if (target - pos).length_squared() <= HARVEST_RANGE_SQ {
                    let cargo = self.entities[idx].cargo;
                    let delivered = if self.earthfront {
                        let processor = &mut self.entities[refinery_id];
                        let amount =
                            cargo.min(earthfront::REFINERY_CAPACITY - processor.ore_buffer);
                        processor.ore_buffer += amount;
                        amount
                    } else {
                        self.civs[usize::from(owner.0)].money = self.civs[usize::from(owner.0)]
                            .money
                            + Fixed::from_int(i32::try_from(cargo).unwrap_or(0));
                        cargo
                    };
                    let e = &mut self.entities[idx];
                    e.cargo -= delivered;
                    e.harvest_returning = e.cargo > 0;
                    e.move_target = None;
                    e.path.clear();
                } else if !moving
                    || (self.earthfront && self.entities[idx].order_goal != Some(target))
                {
                    self.order_unit_to(idx, target, false);
                }
                continue;
            }

            let deposit = self
                .map
                .deposits()
                .filter(|(_, _, d)| d.kind == crate::game::map::DepositKind::Ore)
                // A Refinery directly on a deposit keeps its legacy baseline
                // income; trucks seek exposed fields so they visibly leave the
                // base and create raidable economic traffic.
                .filter(|(x, y, _)| self.earthfront || !covered_deposits.contains(&(*x, *y)))
                .min_by_key(|&(x, y, _)| (tile_center(x, y) - pos).length_squared().to_bits())
                .map(|(x, y, _)| (x, y, tile_center(x, y)));
            let Some((dx, dy, target)) = deposit else {
                if self.entities[idx].cargo > 0 {
                    self.entities[idx].harvest_returning = true;
                    self.entities[idx].move_target = None;
                }
                continue;
            };
            if (target - pos).length_squared() <= HARVEST_RANGE_SQ {
                self.entities[idx].move_target = None;
                self.entities[idx].path.clear();
                if self.tick.is_multiple_of(HARVEST_PERIOD) {
                    let space = HARVEST_CAPACITY.saturating_sub(self.entities[idx].cargo);
                    let mined = self.map.mine(dx, dy, HARVEST_CHUNK.min(space));
                    self.entities[idx].cargo += mined;
                    if self.entities[idx].cargo >= HARVEST_CAPACITY
                        || self.map.deposit(dx, dy).is_none()
                    {
                        self.entities[idx].harvest_returning = true;
                    }
                }
            } else if !moving {
                self.order_unit_to(idx, target, false);
            }
        }
    }

    fn run_movement(&mut self) {
        let mobility: Vec<Fixed> = (0..self.civs.len())
            .map(|p| self.player_mobility_bonus(PlayerId(u16::try_from(p).unwrap())))
            .collect();
        // Pre-tick snapshot of every living entity's (owner, position), so an
        // attack-mover can scan for a nearby enemy without borrowing `entities`
        // mutably during the move loop. Ascending index, no rng/float — the same
        // deterministic order the combat pass relies on.
        // The last field is the air flag: under Kestrel depth only an enemy the
        // attack-mover's weapon can reach (the `run_combat` layer test) halts it.
        let snap: Vec<(bool, u16, Vec2, bool)> = self
            .entities
            .iter()
            .map(|e| (e.alive, e.owner.0, e.pos, is_air_of(&self.balance, e.kind)))
            .collect();
        let depth = self.is_depth();
        let antigrav: Vec<bool> = (0..self.civs.len())
            .map(|p| self.player_has_antigrav(PlayerId(u16::try_from(p).unwrap())))
            .collect();
        // Kestrel depth: where each attack-mover would step to engage (empty, so
        // never consulted, when depth is off).
        let steer = if self.is_depth() {
            self.depth_steer_points()
        } else {
            Vec::new()
        };
        // Kestrel depth: ground units that must re-path from their own tile
        // (always empty when depth is off).
        let mut repath: Vec<usize> = Vec::new();
        for (i, e) in self.entities.iter_mut().enumerate() {
            if !e.alive || e.construction_remaining > 0 {
                continue;
            }
            // EMP-stunned units hold position.
            if e.stun_ticks > 0 {
                continue;
            }
            let Kind::Unit(uk) = e.kind else { continue };
            let Some(target) = e.move_target else {
                continue;
            };
            // Attack-move: stand and fight if any enemy is within engagement
            // range — the existing combat auto-fire does the damage; here we
            // only SUPPRESS the advance this tick. Engagement range is the
            // unit's own weapon range (`attack_of`), or a small fixed leash if
            // it is unarmed. Scan in ascending index order over the frozen
            // snapshot (deterministic; no rng/float). Plain Move never enters
            // this branch, so it marches through unchanged.
            if e.attack_move
                && (!self.earthfront || e.ammunition > 0)
                && attack_move_halts(&snap, i, e, &self.balance, depth)
            {
                continue;
            }
            let base = uk.stats().speed + mobility[usize::from(e.owner.0)];
            let speed = if self.earthfront {
                base * Fixed::from_ratio(i64::from(ground_speed_pct(&self.map, e.pos, uk)), 100)
            } else {
                base
            };
            // Kestrel depth: an attack-mover with an enemy inside its acquisition
            // ring (none in weapon range, or it would have halted above) steps
            // straight at it when that step lands on passable ground.
            if let Some(&Some(goal)) = steer.get(i) {
                let flies = is_air_of(&self.balance, e.kind) || antigrav[usize::from(e.owner.0)];
                if let Some(next) = depth::steer_step(&self.map, e.pos, goal, speed, flies) {
                    e.pos = next;
                    continue;
                }
            }
            // Earthfront: the straight final leg must never carry a ground unit
            // onto an impassable tile. Once the path is exhausted, a target that
            // sits on one (terrain changed under the order, a building raised on
            // it) ends the order where the unit stands, on its last passable tile.
            if self.earthfront && e.path.is_empty() && !antigrav[usize::from(e.owner.0)] {
                let (tx, ty) = hex::from_world(target, self.map.width(), self.map.height());
                let air = is_air_of(&self.balance, e.kind);
                if !air
                    && !self
                        .map
                        .tile(i32::from(tx), i32::from(ty))
                        .is_some_and(|t| t.passable)
                {
                    e.move_target = None;
                    e.attack_move = false;
                    continue;
                }
            }
            // Head to the next waypoint, or straight to the target once the path
            // is exhausted.
            let subgoal = e
                .path
                .first()
                .map_or(target, |&(wx, wy)| tile_center(wx, wy));
            let dir = subgoal - e.pos;
            let dist = dir.length();
            // Kestrel depth: a ground unit standing off its tile centre (pushed
            // aside by separation) must not cut a corner into the river on its
            // way to the next waypoint; it re-centres first, or re-paths.
            if depth && !is_air_of(&self.balance, e.kind) && !antigrav[usize::from(e.owner.0)] {
                match depth::ground_step(&self.map, e.pos, subgoal, speed) {
                    depth::GroundStep::Clear => {}
                    depth::GroundStep::Recentre(p) => {
                        e.pos = p;
                        continue;
                    }
                    depth::GroundStep::Repath => {
                        repath.push(i);
                        continue;
                    }
                }
            }
            if dist <= speed {
                e.pos = subgoal;
                if e.path.is_empty() {
                    e.move_target = None;
                    // Arrived: drop the attack-move stance with the waypoint.
                    e.attack_move = false;
                } else {
                    e.path.remove(0);
                }
            } else {
                e.pos = e.pos + dir.scale(speed / dist);
            }
        }
        for i in repath {
            self.depth_repath(i);
        }
        if depth {
            // Kestrel depth (Task 14): a unit whose leg ended this tick starts
            // its next queued waypoint at once.
            self.depth_advance_queues();
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::cast_possible_wrap,
        clippy::too_many_lines,
        reason = "grid cell coordinates are clamped into the map bounds before use; combat loop is long by necessity"
    )]
    fn run_combat(&mut self) {
        // Pre-tick snapshot (all attackers this tick target the same frozen
        // state, so combat is order-independent and bit-deterministic). The last
        // field is current HP, used for focus-fire targeting.
        let snap: Vec<(bool, u16, Vec2, ArmorType, bool, Fixed)> = self
            .entities
            .iter()
            .map(|e| {
                (
                    e.alive,
                    e.owner.0,
                    e.pos,
                    armor_of(&self.balance, e.kind),
                    is_air_of(&self.balance, e.kind),
                    e.hp,
                )
            })
            .collect();

        // Spatial grid over living entities so target lookup is ~O(neighbours)
        // rather than O(n^2). The cell size is >= 1.25x the largest attack range
        // (the Highland-extended reach), so a 3x3 cell query around an attacker
        // contains every in-range enemy.
        let cols = (i32::from(self.map.width()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let rows = (i32::from(self.map.height()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let mut grid = alloc::vec![Vec::<usize>::new(); (cols * rows).max(1) as usize];
        for (i, t) in snap.iter().enumerate() {
            if t.0 {
                let cx = (t.2.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, cols - 1);
                let cy = (t.2.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, rows - 1);
                grid[(cy * cols + cx) as usize].push(i);
            }
        }

        // Research bonuses apply to ALL of a player's entities, buildings included:
        // armor mitigates damage to structures, and weapon buffs the attacks of
        // armed buildings (turrets / command center). This is intentional.
        let weapon: Vec<Fixed> = (0..self.civs.len())
            .map(|p| self.player_weapon_bonus(PlayerId(u16::try_from(p).unwrap())))
            .collect();
        let armor: Vec<Fixed> = (0..self.civs.len())
            .map(|p| self.player_armor_bonus(PlayerId(u16::try_from(p).unwrap())))
            .collect();
        let era_dmg: Vec<Fixed> = (0..self.civs.len())
            .map(|p| {
                if self.earthfront {
                    Fixed::ONE
                } else {
                    era_damage_factor(self.civs[p].era)
                }
            })
            .collect();
        // Survival perks: Overcharge scales outgoing damage; Bulwark adds flat
        // mitigation. No perks chosen ⇒ ONE / ZERO ⇒ base combat is unchanged.
        let perk_dmg: Vec<Fixed> = (0..self.civs.len())
            .map(|p| {
                if self.civs[p].active_perks & (1 << crate::game::perk::OVERCHARGE) != 0 {
                    Fixed::from_ratio(5, 4)
                } else {
                    Fixed::ONE
                }
            })
            .collect();
        let perk_mit: Vec<Fixed> = (0..self.civs.len())
            .map(|p| {
                if self.civs[p].active_perks & (1 << crate::game::perk::BULWARK) != 0 {
                    Fixed::from_int(2)
                } else {
                    Fixed::ZERO
                }
            })
            .collect();

        // Supply anchors: every living Command Center position, bucketed by owner.
        // Gathered ONCE per tick (ascending entity index) so the per-firer
        // nearest-anchor scan below stays deterministic and order-independent —
        // and reuses the same frozen geometry every attacker fires against. A unit
        // far from all of its owner's anchors fires at reduced strength
        // (`supply_decay_factor`), making overextension costly and forward bases
        // worth holding. Static defenders (turrets / CC) are intentionally exempt
        // (see the firing loop), so homeworld defence is never weakened.
        let mut cc_positions: Vec<Vec<Vec2>> = alloc::vec![Vec::new(); self.civs.len()];
        for e in &self.entities {
            if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
                cc_positions[usize::from(e.owner.0)].push(e.pos);
            }
        }

        // Kestrel depth (also gates the forced-target filter below).
        let depth = self.is_depth();
        // (target index, attacker index, damage, pierces-shields).
        let mut damage: Vec<(usize, usize, Fixed, bool)> = Vec::new();
        // Seats whose lethal blow this tick captures (not destroys) them:
        // (seat entity index, capturing player). Applied after the damage loop.
        let mut captures: Vec<(usize, PlayerId)> = Vec::new();
        let mut lines: Vec<(Vec2, Vec2)> = Vec::new();
        let mut candidates: Vec<usize> = Vec::new();
        for (i, e) in self.entities.iter_mut().enumerate() {
            if !e.alive || e.construction_remaining > 0 {
                continue;
            }
            // EMP-stunned entities can't fire (their weapon stays frozen too).
            if e.stun_ticks > 0 {
                continue;
            }
            if self.earthfront
                && (e.ammunition == 0
                    || (matches!(e.kind, Kind::Building(_)) && e.power_fraction < 500))
            {
                continue;
            }
            // Kestrel depth (Task 15): AntiArmor teams also target air.
            let Some(profile) = depth::weapon_of(&self.balance, e.kind, depth) else {
                continue;
            };
            if e.cooldown > 0 {
                e.cooldown -= 1;
                continue;
            }
            // Gather candidates from the 3x3 neighbourhood in ascending index
            // order so distance ties resolve to the lowest index — identical to a
            // full linear scan (keeps the simulation bit-for-bit deterministic).
            candidates.clear();
            let cx = (e.pos.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, cols - 1);
            let cy = (e.pos.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, rows - 1);
            for ny in (cy - 1)..=(cy + 1) {
                for nx in (cx - 1)..=(cx + 1) {
                    if nx >= 0 && ny >= 0 && nx < cols && ny < rows {
                        candidates.extend_from_slice(&grid[(ny * cols + nx) as usize]);
                    }
                }
            }
            candidates.sort_unstable();

            // Earthfront: the attacker's tile extends its range (Highland +25 percent).
            let range_sq = if self.earthfront {
                let range_pct = ground_props_at(&self.map, e.pos).range_pct;
                if range_pct == 0 {
                    profile.range * profile.range
                } else {
                    let r = profile.range * Fixed::from_int(pct_i32(100 + range_pct))
                        / Fixed::from_int(100);
                    r * r
                }
            } else {
                profile.range * profile.range
            };
            // Target the NEAREST valid enemy (preserves lane/base pressure so
            // matches resolve), breaking distance ties by LOWEST HP — a focus-fire
            // tie-break that secures kills when several foes are equidistant. Ties
            // resolve to the lowest index (candidates are scanned in ascending
            // index order and we only replace on a strict improvement), keeping
            // the simulation bit-for-bit deterministic.
            let mut best: Option<(usize, Fixed, Fixed)> = None;
            // Kestrel depth (Task 13): a unit on a forced target fires at it
            // alone (never set when depth is off).
            let forced = if depth {
                e.dp.forced.map(|t| t.0 as usize)
            } else {
                None
            };
            for &j in &candidates {
                let t = snap[j];
                if t.1 == e.owner.0 || forced.is_some_and(|f| f != j) {
                    continue;
                }
                // Respect air/ground targeting: AA hits only air, most weapons
                // hit only ground.
                let target_is_air = t.4;
                if (target_is_air && !profile.targets_air)
                    || (!target_is_air && !profile.targets_ground)
                {
                    continue;
                }
                let dist_sq = (t.2 - e.pos).length_squared();
                if dist_sq > range_sq {
                    continue;
                }
                let thp = t.5;
                let better =
                    best.is_none_or(|(_, bd, bhp)| dist_sq < bd || (dist_sq == bd && thp < bhp));
                if better {
                    best = Some((j, dist_sq, thp));
                }
            }
            if let Some((j, _, _)) = best {
                if self.earthfront {
                    e.ammunition = e.ammunition.saturating_sub(1);
                }
                let mult = damage_multiplier(profile.damage_type, snap[j].3);
                let raw = profile.damage * mult * era_dmg[usize::from(e.owner.0)]
                    + weapon[usize::from(e.owner.0)];
                // Kestrel depth (Task 15): a weapon that only gained air
                // targeting under depth lands a fraction of its hit on air.
                let air_pct = depth::depth_air_damage_pct(e.kind);
                let raw = if depth && snap[j].4 && air_pct != 100 {
                    raw * Fixed::from_ratio(air_pct, 100)
                } else {
                    raw
                };
                // Earthfront cover: the target's tile removes `cover_pct` of the hit. Air
                // targets take none. Applied before the push so splash inherits it.
                let raw = if self.earthfront && !snap[j].4 {
                    let cover = ground_props_at(&self.map, snap[j].2).cover_pct;
                    raw * Fixed::from_int(pct_i32(through_cover_pct(cover))) / Fixed::from_int(100)
                } else {
                    raw
                };
                // Supply-line decay: a UNIT firing far from its owner's nearest
                // Command Center deals less damage (overextension penalty), ramping
                // from full strength within `SUPPLY_FULL_RADIUS` down to
                // `SUPPLY_DECAY_FLOOR` past `SUPPLY_DECAY_RADIUS`. Static defenders
                // (turrets / CC) are EXEMPT — they sit on an anchor anyway and we
                // want homeworld defence at full strength. The nearest-anchor scan
                // is ascending-index, squared-distance, `Fixed`-only (deterministic);
                // an owner with no anchors gets factor 1 (don't punish a player who
                // just lost their last CC). This factor folds into `dmg` BEFORE the
                // push, so splash inherits it too.
                let supply = if !self.earthfront && matches!(e.kind, Kind::Unit(_)) {
                    let anchors = &cc_positions[usize::from(e.owner.0)];
                    let nearest_sq = anchors.iter().map(|&a| (a - e.pos).length_squared()).min();
                    supply_decay_factor(nearest_sq)
                } else {
                    Fixed::ONE
                };
                let dmg =
                    raw * veterancy_factor(e.rank) * perk_dmg[usize::from(e.owner.0)] * supply;
                let pierces = matches!(profile.damage_type, DamageType::AntiArmor);
                damage.push((j, i, dmg, pierces));
                lines.push((e.pos, snap[j].2));
                e.cooldown = if self.earthfront {
                    profile.period.saturating_sub(1)
                } else {
                    profile.period
                };

                // Area splash: a weapon with a non-zero blast radius also damages
                // every OTHER enemy within `splash_radius` of the PRIMARY TARGET
                // (not the firer) for a `splash_falloff` fraction of the hit. We
                // reuse the already-sorted `candidates` (ascending index), so the
                // extra entries are pushed in deterministic, order-independent
                // index order and land in the same post-loop apply pass — shields,
                // mitigation, and kill-credit all flow through uniformly. Every
                // weapon but the Capital has `splash_radius == ZERO`, so this scan
                // is skipped entirely and base combat (the golden run) is identical.
                if profile.splash_radius > Fixed::ZERO {
                    let splash_dmg = dmg * profile.splash_falloff;
                    let splash_sq = profile.splash_radius * profile.splash_radius;
                    let primary_pos = snap[j].2;
                    for &k in &candidates {
                        if k == j {
                            continue;
                        }
                        let t = snap[k];
                        // Living enemies only (owner != firer); the primary `j` is
                        // excluded above. Air/ground gating already held for `j`;
                        // neighbours inherit the same blast regardless of layer.
                        if !t.0 || t.1 == e.owner.0 {
                            continue;
                        }
                        if (t.2 - primary_pos).length_squared() > splash_sq {
                            continue;
                        }
                        damage.push((k, i, splash_dmg, pierces));
                    }
                }
            }
        }
        #[allow(
            clippy::cast_possible_truncation,
            reason = "tick fits u32 for any real game"
        )]
        let tick = self.tick as u32;
        // Kestrel depth: (victim, attacker) in damage order, for the
        // under-attack response once every hit has landed.
        let mut hits: Vec<(usize, usize)> = Vec::new();
        for (j, attacker, dmg, pierces) in damage {
            if depth {
                hits.push((j, attacker));
            }
            let owner = self.entities[j].owner;
            let mit = armor[usize::from(owner.0)] + perk_mit[usize::from(owner.0)];
            // Armor research subtracts flat mitigation, but a mitigated hit still
            // deals at least 1 (no immunity). With no armor research (mit == 0),
            // damage is unchanged, keeping base combat identical.
            let net = if mit > Fixed::ZERO {
                let reduced = dmg - mit;
                if reduced < Fixed::ONE {
                    Fixed::ONE
                } else {
                    reduced
                }
            } else {
                dmg
            };
            let killed = {
                let e = &mut self.entities[j];
                e.last_combat_tick = tick;
                let was_alive = e.hp > Fixed::ZERO;
                if pierces {
                    e.hp = e.hp - net;
                } else {
                    let absorbed = if e.shield < net { e.shield } else { net };
                    e.shield = e.shield - absorbed;
                    e.hp = e.hp - (net - absorbed);
                }
                // Only the blow that crosses 0 counts, so a target killed by an
                // earlier hit this tick can't be double-credited.
                was_alive && e.hp <= Fixed::ZERO
            };
            if killed {
                #[allow(
                    clippy::cast_possible_truncation,
                    reason = "entity index fits u32 for any real game"
                )]
                let is_seat = self.entities[j].kind == Kind::Building(BuildingKind::CommandCenter)
                    && self
                        .planets
                        .iter()
                        .any(|pl| pl.seat == Some(EntityId(j as u32)));
                if is_seat {
                    // Capturing a planet seat is INTENTIONALLY not a kill: no kill
                    // credit and no veterancy rank bump for the attacker. It's a
                    // capture, not a destruction — the missing credit is by design,
                    // not a bug to "fix".
                    let capturing_owner = self.entities[attacker].owner;
                    captures.push((j, capturing_owner));
                } else {
                    let a = &mut self.entities[attacker];
                    a.kills += 1;
                    a.rank = rank_for_kills(a.kills);
                }
            }
        }
        self.attacks = lines;
        // Captures are applied here, at the end of `run_combat`, BEFORE `clear_dead`
        // runs in `step()`. `apply_seat_capture` restores the seat's HP to a positive
        // fraction of max, so the captured seat is no longer at hp <= 0 and is NOT
        // reaped by `clear_dead`. Do not reorder this relative to `clear_dead` — doing
        // so would silently destroy captured seats instead of transferring them.
        for (seat_idx, capturing_owner) in captures {
            self.apply_seat_capture(seat_idx, capturing_owner);
        }
        if depth {
            self.depth_respond_to_hits(&hits);
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn clear_dead(&mut self) {
        let mut freed_tiles: Vec<(u16, u16)> = Vec::new();
        let mut freed_slots: Vec<u32> = Vec::new();
        for (i, e) in self.entities.iter_mut().enumerate() {
            if e.alive && e.hp <= Fixed::ZERO {
                e.alive = false;
                if let Some(tile) = e.tile {
                    freed_tiles.push(tile);
                }
                freed_slots.push(i as u32);
            }
        }
        for (x, y) in freed_tiles {
            self.map.set_tile(x, y, Tile::OPEN);
        }
        if self.is_depth() && !freed_slots.is_empty() {
            // Before the slots can be reused: nobody keeps chasing a dead target.
            self.depth_drop_dangling(&freed_slots);
        }
        self.free.extend(freed_slots);

        // Reap orphaned colonies: a colony whose seat CommandCenter has just been
        // reaped (or is otherwise no longer a live entity) must be freed too, or it
        // would keep accruing income/upkeep forever, keep inflating its dead owner's
        // `count_owner_colonies` / `empire_upkeep` / Kardashev tier / wave pressure,
        // and — worst — alias a recycled entity slot so its LOD/rates would later
        // flip to whatever entity reuses that index (logically corrupt; a latent
        // panic vector). `free_colony` already settles accrual exactly and recycles
        // the slot (LIFO), so freeing on seat-death is the correct, exact action and
        // keeps the Dormant-LOD skip==full invariant intact.
        //
        // Note a captured (not destroyed) planet seat is NOT reaped — `run_combat`
        // restored its HP to a positive fraction before `clear_dead`, so its entity
        // stays alive and its (now re-ownered) colony is untouched here.
        //
        // Borrow-safe: collect the orphaned colony ids first (immutable scan), then
        // free them. Ascending colony order, no rng ⇒ deterministic.
        let orphaned: Vec<ColonyId> = self
            .colonies
            .iter()
            .enumerate()
            .filter(|(_, c)| {
                // Orphaned iff the seat entity is gone or no longer alive.
                c.alive
                    && self
                        .entities
                        .get(c.seat.0 as usize)
                        .is_none_or(|e| !e.alive)
            })
            .map(|(i, _)| ColonyId(i as u32))
            .collect();
        for id in orphaned {
            self.free_colony(id);
        }
    }

    /// Capture (not destroy) a planet seat: flip the seat + planet to `attacker`,
    /// restore the seat to a fraction of max HP, re-owner the planet's surviving
    /// buildings, and transfer the seated colony (autonomy/policy reset). The
    /// capturer is the owner of the lethal blow (deterministic combat order; no rng).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity/colony indices fit u32 for any real game"
    )]
    fn apply_seat_capture(&mut self, seat_idx: usize, capturing_owner: PlayerId) {
        let seat_id = EntityId(seat_idx as u32);
        let Some(pidx) = self.planets.iter().position(|pl| pl.seat == Some(seat_id)) else {
            return;
        };
        let pid = PlanetId(u16::try_from(pidx).unwrap_or(u16::MAX));

        let cc_max = self.balance.building(BuildingKind::CommandCenter).max_hp;
        let frac = self.balance.capture_hp_fraction;
        self.entities[seat_idx].hp = cc_max * frac;
        self.entities[seat_idx].owner = capturing_owner;
        self.planets[pidx].owner = Some(capturing_owner);

        // Re-owner surviving buildings whose tile belongs to this planet.
        let Self { entities, map, .. } = self;
        for e in entities.iter_mut() {
            if e.alive && matches!(e.kind, Kind::Building(_)) {
                if let Some((tx, ty)) = e.tile {
                    if map.planet_at(i32::from(tx), i32::from(ty)) == Some(pid) {
                        e.owner = capturing_owner;
                    }
                }
            }
        }

        // Transfer the seated colony; reset earned autonomy/policy under the new owner.
        for c in &mut self.colonies {
            if c.alive && c.seat == seat_id {
                c.owner = capturing_owner;
                c.autonomy_level = 0;
                c.autonomy_progress = 0;
                c.policy = ColonyPolicy::default();
                c.sector = None;
            }
        }
    }
}

impl Sim {
    /// Rule-based commands for `player` this tick: follow a build order, train
    /// infantry from an idle barracks, and attack-move idle units toward the
    /// enemy base. Pure function of state (no RNG), so AI-vs-AI replays bit-for-bit.
    #[must_use]
    #[allow(
        clippy::too_many_lines,
        reason = "AI command function covers build, train, research, and move logic; splitting adds indirection without clarity gain"
    )]
    pub fn ai_commands(&self, player: PlayerId) -> Vec<Command> {
        if self.earthfront {
            return self.earthfront_ai(player);
        }
        let mut cmds = Vec::new();

        // Survey phase: the only move is founding. Pick the first buildable tile
        // hex-adjacent to an Ore deposit (the colony-bonus site), falling back to
        // the first buildable Ore tile. Everyone else holds until play begins.
        if matches!(self.phase, GamePhase::Survey) {
            if self.command_center_tile(player).is_none() {
                let mut site: Option<(u16, u16)> = None;
                'scan: for (dx, dy, d) in self.map.deposits() {
                    if d.kind != crate::game::map::DepositKind::Ore {
                        continue;
                    }
                    for ny in -1..=1i32 {
                        for nx in -1..=1i32 {
                            let tx = i32::from(dx) + nx;
                            let ty = i32::from(dy) + ny;
                            let (Ok(txu), Ok(tyu)) = (u16::try_from(tx), u16::try_from(ty)) else {
                                continue;
                            };
                            if self.map.tile(tx, ty).is_some_and(|t| t.buildable)
                                && crate::game::hex::distance((dx, dy), (txu, tyu)) == 1
                            {
                                site = Some((txu, tyu));
                                break 'scan;
                            }
                        }
                    }
                }
                let site = site
                    .or_else(|| self.first_buildable_deposit(crate::game::map::DepositKind::Ore));
                if let Some((x, y)) = site {
                    cmds.push(Command::FoundBase {
                        owner: player,
                        x,
                        y,
                    });
                }
            }
            return cmds;
        }

        // Abilities: cast the first ready tactical ability with a worthwhile
        // target — Barrage/EMP at the first enemy with ≥ 3 foes packed inside the
        // blast, Nanite Field when ≥ 2 nearby allies run below half HP. Index
        // order, fixed thresholds, no RNG; at most one cast per tick keeps the
        // command volume flat. Costs nothing, so it never fights the build budget.
        'ability: for (i, e) in self.entities.iter().enumerate() {
            // Re-scan only every 5th tick: the clump scan is O(n²) against packed
            // fields, and a ≤166 ms casting-reaction delay is imperceptible.
            if !self.tick.is_multiple_of(5) {
                break 'ability;
            }
            if !e.alive || e.owner != player || e.ability_cd > 0 || e.stun_ticks > 0 {
                continue;
            }
            let Kind::Unit(uk) = e.kind else { continue };
            let Some(kind) = crate::game::ability::ability_for(uk) else {
                continue;
            };
            let d = crate::game::ability::def(kind);
            let radius_sq = d.radius * d.radius;
            let range_sq = d.range * d.range;
            let unit_id = EntityId(u32::try_from(i).unwrap_or(u32::MAX));
            // EMP only affects stunnable units (not buildings / already-stunned /
            // immune targets), so its clump count and epicenter must match what
            // the resolve would actually hit — otherwise casts are wasted.
            let stunnable = |o: &Entity| {
                matches!(o.kind, Kind::Unit(_)) && o.stun_ticks == 0 && o.stun_immunity == 0
            };
            let emp = matches!(kind, crate::game::ability::AbilityKind::EmpBurst);
            match kind {
                crate::game::ability::AbilityKind::Barrage
                | crate::game::ability::AbilityKind::EmpBurst => {
                    for t in &self.entities {
                        if !t.alive || t.owner == player || (emp && !stunnable(t)) {
                            continue;
                        }
                        if (t.pos - e.pos).length_squared() > range_sq {
                            continue;
                        }
                        let packed = self
                            .entities
                            .iter()
                            .filter(|o| {
                                o.alive
                                    && o.owner != player
                                    && (!emp || stunnable(o))
                                    && (o.pos - t.pos).length_squared() <= radius_sq
                            })
                            .count();
                        if packed >= 3 {
                            cmds.push(Command::UseAbility {
                                owner: player,
                                unit: unit_id,
                                target: t.pos,
                            });
                            break 'ability;
                        }
                    }
                }
                crate::game::ability::AbilityKind::NaniteField => {
                    let wounded = self
                        .entities
                        .iter()
                        .filter(|o| {
                            o.alive
                                && o.owner == player
                                && matches!(o.kind, Kind::Unit(_))
                                && (o.pos - e.pos).length_squared() <= radius_sq
                                && o.hp + o.hp < max_hp(&self.balance, o.kind)
                        })
                        .count();
                    if wounded >= 2 {
                        cmds.push(Command::UseAbility {
                            owner: player,
                            unit: unit_id,
                            target: e.pos,
                        });
                        break 'ability;
                    }
                }
            }
        }

        let Some(cc_tile) = self.command_center_tile(player) else {
            // No base left: no building/training — but the army above still casts
            // its abilities, so a razed-beachhead wave keeps fighting smart.
            return cmds;
        };
        let money = self.money(player);
        let enemy_cc = self.nearest_enemy_cc(player).and_then(|e| e.tile);

        // Build order: act on the first missing essential, then build no more
        // this tick (keeps spending paced and deterministic).
        let mut building_this_tick = false;
        for kind in [
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
            BuildingKind::ResearchLab,
        ] {
            // Skip kinds not yet unlocked by research — otherwise the loop would
            // spin forever on a locked essential and never build/train anything.
            if self.building_unlocked(player, kind) && !self.has_building(player, kind) {
                if kind == BuildingKind::Refinery {
                    // Refineries only earn income when built ON a deposit tile.
                    // Scan deposits in row-major order; pick the first whose tile
                    // is still buildable. If no buildable deposit exists, skip the
                    // Refinery and continue to the next building in the order — a
                    // Refinery built off-deposit is useless, but it should not
                    // block Barracks or ResearchLab from being built.
                    let deposit_tile = self.map.deposits().find(|&(x, y, _)| {
                        self.map
                            .tile(i32::from(x), i32::from(y))
                            .is_some_and(|t| t.buildable)
                    });
                    if let Some((dx, dy, _)) = deposit_tile {
                        if self.can_afford_building(player, kind) {
                            cmds.push(Command::Build {
                                owner: player,
                                kind,
                                x: dx,
                                y: dy,
                            });
                        }
                        building_this_tick = true;
                        break;
                    }
                    // No buildable deposit: skip Refinery, continue the build order.
                } else {
                    if self.can_afford_building(player, kind) {
                        if let Some((x, y)) = self.find_buildable_near(cc_tile, enemy_cc) {
                            cmds.push(Command::Build {
                                owner: player,
                                kind,
                                x,
                                y,
                            });
                        }
                    }
                    building_this_tick = true;
                    break;
                }
            }
        }

        // Anti-air response: if the enemy fields aircraft and we have no AA yet,
        // build a turret to counter it.
        if !building_this_tick
            && self.building_unlocked(player, BuildingKind::AaTurret)
            && self.enemy_has_air(player)
            && !self.has_building(player, BuildingKind::AaTurret)
            && self.can_afford_building(player, BuildingKind::AaTurret)
        {
            if let Some((x, y)) = self.find_buildable_near(cc_tile, enemy_cc) {
                cmds.push(Command::Build {
                    owner: player,
                    kind: BuildingKind::AaTurret,
                    x,
                    y,
                });
            }
            building_this_tick = true;
        }

        // Antimatter infrastructure: once it is unlocked (Interstellar / era 3),
        // build an Antimatter Plant if we don't have one yet. Gating on the unlock
        // keeps the 120-tick golden run (AI stays Era 0, plant locked) unaffected
        // and stops the loop stalling on a not-yet-unlocked plant.
        if !building_this_tick
            && self.building_unlocked(player, BuildingKind::AntimatterPlant)
            && !self.has_building(player, BuildingKind::AntimatterPlant)
            && self.can_afford_building(player, BuildingKind::AntimatterPlant)
        {
            if let Some((x, y)) = self.find_buildable_near(cc_tile, enemy_cc) {
                cmds.push(Command::Build {
                    owner: player,
                    kind: BuildingKind::AntimatterPlant,
                    x,
                    y,
                });
            }
            building_this_tick = true;
        }

        // Expand when Minerals pile up instead of banking them. A single priority
        // list — first affordable+placeable action wins — so a "wanted but
        // unplaceable" step never blocks a lower one (the classic else-if-chain
        // trap). Power-aware: a deficit stalls research/mining (see `run_research` /
        // the `run_economy` throttle), so a Reactor comes first. Then sustain
        // Minerals income (Ore extractors), then secure scarce Alloy (fuels Capital
        // ships), then — once at the supply ceiling — raise the army cap with a
        // Barracks, then Reactors as a pure supply sink. Every type is bounded, so
        // the AI fields a healthy army without carpeting the map. Deterministic
        // (row-major scans, no RNG); the flag is set only when a build is queued.
        if !building_this_tick && money >= Fixed::from_int(500) {
            use crate::game::map::DepositKind;
            let reactors = self.count_alive_buildings(player, BuildingKind::PowerPlant);
            let barracks = self.count_alive_buildings(player, BuildingKind::Barracks);
            let ore_extractors = self.active_extractors_on(player, DepositKind::Ore);
            let alloy_extractors = self.active_extractors_on(player, DepositKind::Alloy);
            let at_cap = self.supply_used(player) + 2 >= self.supply_cap(player);
            let near = self.find_buildable_near(cc_tile, enemy_cc);
            let afford = |k| self.can_afford_building(player, k);

            let action: Option<(BuildingKind, u16, u16)> = (reactors == 0
                && afford(BuildingKind::PowerPlant))
            .then(|| near.map(|(x, y)| (BuildingKind::PowerPlant, x, y)))
            .flatten()
            .or_else(|| {
                (ore_extractors < MAX_AI_EXTRACTORS && afford(BuildingKind::Refinery))
                    .then(|| self.first_buildable_deposit(DepositKind::Ore))
                    .flatten()
                    .map(|(x, y)| (BuildingKind::Refinery, x, y))
            })
            .or_else(|| {
                (alloy_extractors < MAX_AI_ALLOY_EXTRACTORS && afford(BuildingKind::Refinery))
                    .then(|| self.first_buildable_deposit(DepositKind::Alloy))
                    .flatten()
                    .map(|(x, y)| (BuildingKind::Refinery, x, y))
            })
            .or_else(|| {
                (at_cap
                    && barracks < MAX_AI_BARRACKS
                    && self.building_unlocked(player, BuildingKind::Barracks)
                    && afford(BuildingKind::Barracks))
                .then_some(near)
                .flatten()
                .map(|(x, y)| (BuildingKind::Barracks, x, y))
            })
            .or_else(|| {
                (at_cap && reactors < MAX_AI_REACTORS && afford(BuildingKind::PowerPlant))
                    .then_some(near)
                    .flatten()
                    .map(|(x, y)| (BuildingKind::PowerPlant, x, y))
            });

            if let Some((kind, x, y)) = action {
                cmds.push(Command::Build {
                    owner: player,
                    kind,
                    x,
                    y,
                });
                building_this_tick = true;
            }
        }

        // Economy is up: train from an idle barracks. At Era 3+, prefer Capital Ships
        // (also needs sufficient antimatter).
        if !building_this_tick {
            if let Some(barracks) = self.idle_barracks(player) {
                let kind = if self.player_era(player) >= 3
                    && self.can_afford_unit(player, UnitKind::Capital)
                {
                    UnitKind::Capital
                } else {
                    UnitKind::Infantry
                };
                let reserving_for_capital = self.player_era(player) >= 1
                    && kind != UnitKind::Capital
                    && self.supply_used(player) + AI_CAPITAL_SUPPLY_RESERVE
                        >= self.supply_cap(player);
                if !reserving_for_capital && self.can_afford_unit(player, kind) {
                    cmds.push(Command::Train {
                        owner: player,
                        barracks,
                        kind,
                    });
                }
            }
        }

        // Ascendancy Doctrines: once established (era ≥ 1) and holding a Minerals
        // reserve, convert the surplus into army QUALITY. The money-only Forge
        // track always runs (it bleeds the standing Minerals bank); the research-
        // costed quality tracks only run once the finite tech tree is exhausted —
        // era keys and Anti-Grav are worth more than incremental doctrine levels,
        // so research is reserved for them while any finite tech is still pending.
        // The AI may also Build/Train this tick, so gate on the money that would
        // be LEFT after those commits (`avail`) — never queueing an Ascend the
        // apply step would drop, while still ascending every tick the surplus
        // allows. The era ≥ 1 gate keeps the era-0 golden run from ever emitting an
        // Ascend. Pure, row-major, no RNG.
        let spent_this_tick = cmds.iter().fold(Fixed::ZERO, |acc, c| match *c {
            Command::Build { kind, .. } => acc + self.building_cost(kind),
            Command::Train { kind, .. } => acc + self.balance.unit(kind).money_cost,
            _ => acc,
        });
        let avail = money - spent_this_tick;
        if self.player_era(player) >= 1 && avail >= ASCEND_MIN_RESERVE {
            let active = self.research_state(player).1;
            // Research stays reserved for still-useful grid nodes (those that
            // unlock a real building/unit or advance the era); once they're
            // exhausted, the surplus also funds the endless doctrine tracks.
            let set = self.civs[usize::from(player.0)].researched_techs;
            let tree_open = active.is_some()
                || crate::game::tech_grid_table::GRID.iter().any(|node| {
                    !set.get(node.id)
                        && node.prereqs.iter().all(|&r| set.get(r))
                        && (tech_grid::real_building(node.id).is_some()
                            || tech_grid::real_unit(node.id).is_some()
                            || tech_grid::is_era_key(node.id))
                });
            // Track order: Forge (3) first to drain Minerals, then the research
            // tracks Weapons(0)/Armor(1)/Vitality(2). u8 ids avoid a fallible cast.
            let tracks: &[u8] = if tree_open { &[3] } else { &[3, 0, 1, 2] };
            for &track_id in tracks {
                if self.doctrine_level(player, track_id) >= DOCTRINE_LEVEL_CAP {
                    continue;
                }
                let (min_cost, res_cost) = self.doctrine_cost(player, track_id);
                let total = min_cost + res_cost;
                let is_forge = usize::from(track_id) == DOC_FORGE;
                let lab_ok = is_forge || self.has_research_lab(player);
                if lab_ok && avail >= total {
                    cmds.push(Command::Ascend {
                        owner: player,
                        track: track_id,
                    });
                    break;
                }
            }
        }

        // Research: with no active research, start the next grid node the AI wants
        // (see `ai_next_research`) — eligible + affordable, preferring nodes that
        // unlock a real building/unit or advance the era, falling back to the
        // lowest-id eligible node. Deterministic, prereq-gated, no RNG.
        let active_research = self.research_state(player).1;
        if active_research.is_none() {
            if let Some(tech_id) = self.ai_next_research(player) {
                cmds.push(Command::Research {
                    owner: player,
                    tech_id,
                });
            }
        }

        // PLANET-FREE RTS MAPS: periodically push idle units toward the enemy base.
        // Re-issuing an AttackMove (and thus running A*) for every idle unit every tick
        // is the classic RTS perf trap; throttling by tick keeps pathfinding cheap
        // and is still fully deterministic.
        //
        // Gated to planet-free maps. Survival and the direct RTS skirmishes use
        // this branch; planetary conquest uses its separate massing logic.
        // AttackMove is essential here: a plain Move ignores enemies and can leave
        // mirrored skirmish armies repeatedly walking through one another into a
        // permanent stalemate. Units now engage threats en route, which is also the
        // order a player expects an RTS opponent to issue.
        //
        // In CONQUEST this trickle would be the bleed: idle units dribble one-by-one into
        // a defended homeworld and die. There the massing path in
        // `ai_conquest_commands` takes over instead (it pools a stack at a SAFE
        // rally, then commits it as one focused assault).
        if self.planets.is_empty() && self.tick.is_multiple_of(MOVE_REISSUE_PERIOD) {
            if let Some(target) = self.enemy_command_center_pos(player) {
                for unit in self.idle_units(player) {
                    cmds.push(Command::AttackMove {
                        owner: player,
                        unit,
                        target,
                    });
                }
            }
        }

        // Conquest expansion: settle the nearest neutral planet when affordable.
        // A TOTAL NO-OP on planet-free maps (golden / survival / skirmish), so the
        // existing AI path is byte-identical there.
        cmds.extend(self.ai_conquest_commands(player));
        // Conquest offence: mass a stack at a safe rally, then commit it as one
        // focused assault on the weakest enemy homeworld. Also a NO-OP without
        // planets, so survival/golden are unaffected.
        cmds.extend(self.ai_conquest_military(player));
        cmds
    }

    /// Conquest-only expansion: if any planet is neutral, the civ has spare money
    /// and headroom under the colony cap, emit a single `FoundColony` toward the
    /// **nearest** unowned planet's centre tile. Returns empty (a no-op) whenever
    /// no planets exist or none are neutral, so the planet-free golden/survival
    /// AI is unchanged. Deterministic: nearest by `center` distance to the civ's
    /// seat, lowest-index tiebreak; Fixed math, no RNG, no floats.
    fn ai_conquest_commands(&self, player: PlayerId) -> Vec<Command> {
        // Hard gate: nothing to do without planets, or without a neutral target.
        if self.planets.is_empty() || !self.planets.iter().any(|pl| pl.owner.is_none()) {
            return Vec::new();
        }
        // Mirror `apply_found_colony`'s own guards so we don't spam unappliable
        // commands (the apply step re-validates anyway). NOTE: this caps at the
        // global `MAX_COLONIES_PER_OWNER` (matching `apply_found_colony`), which can
        // exceed a species' `colony_cap()` used by the auto-expansion path —
        // intentional, since the apply-time guard is the global cap.
        if self.money(player) < FOUND_COLONY_COST
            || self.count_owner_colonies(player) >= MAX_COLONIES_PER_OWNER
        {
            return Vec::new();
        }
        // Distance reference: the civ's CommandCenter (its seat). No base → no expand.
        let Some(from) = self.command_center_pos(player) else {
            return Vec::new();
        };
        // Nearest neutral planet by squared distance; ties broken by lowest index.
        let mut best: Option<(usize, Fixed)> = None;
        for (i, pl) in self.planets.iter().enumerate() {
            if pl.owner.is_some() {
                continue;
            }
            let dx = pl.center.x - from.x;
            let dy = pl.center.y - from.y;
            let d2 = dx * dx + dy * dy;
            if best.is_none_or(|(_, bd)| d2 < bd) {
                best = Some((i, d2));
            }
        }
        let Some((idx, _)) = best else {
            return Vec::new();
        };
        // Settle a buildable tile of that neutral planet. Map membership (not the
        // Vec2 centre) is the source of truth, so scan row-major for the first
        // buildable tile assigned to this planet id — deterministic, lowest-index.
        let target = PlanetId(u16::try_from(idx).unwrap_or(u16::MAX));
        let mut site: Option<(u16, u16)> = None;
        'scan: for ty in 0..self.map.height() {
            for tx in 0..self.map.width() {
                if self.map.planet_at(i32::from(tx), i32::from(ty)) == Some(target)
                    && self
                        .map
                        .tile(i32::from(tx), i32::from(ty))
                        .is_some_and(|t| t.buildable)
                {
                    site = Some((tx, ty));
                    break 'scan;
                }
            }
        }
        let Some((x, y)) = site else {
            return Vec::new();
        };
        alloc::vec![Command::FoundColony {
            owner: player,
            // `parent` is informational/unread by the handler; the civ's own first
            // colony id is a sensible value.
            parent: ColonyId(u32::from(player.0)),
            x,
            y,
        }]
    }

    /// Conquest-only OFFENCE: mass a stack at a safe rally, then commit it as one
    /// focused assault on the nearest enemy planet. This replaces the survival
    /// trickle (now gated to planet-free maps) which bled units one-by-one into a
    /// defended seat. The flow each call:
    ///
    /// 1. Pick the assault target — the NEAREST enemy-owned planet to our base
    ///    (lowest-index tiebreak), so the fight stays inside the supply ramp and the
    ///    assault fires near full strength. No enemy planets ⇒ fall back to the
    ///    nearest enemy CC position.
    /// 2. Pick a launch anchor — our `CommandCenter` (home or any colony) NEAREST the
    ///    target — and compute a rally partway from it toward the target, kept OUT of
    ///    the target's defensive range so the massing stack is not shot while it
    ///    gathers.
    /// 3. While under-massed, rally all idle combat units there (plain `Move` — they
    ///    pool, no bleed, no en-route attrition).
    /// 4. Once `ASSAULT_STACK` of our combat units have gathered at the rally,
    ///    `AttackMove` the WHOLE army (gathered + stragglers + fresh trainees) at the
    ///    target seat: attack-move clears defenders en route and engages the seat, so
    ///    the existing capture detection in `run_combat` flips the planet. Committed
    ///    units carry a `move_target` so they are no longer "idle" and won't be
    ///    re-rallied until that order clears.
    ///
    /// A NO-OP without planets (survival/golden untouched). Throttled by
    /// `MOVE_REISSUE_PERIOD` for pathing cost. Deterministic: ascending-index
    /// scans, `Fixed`/squared-distance math, no rng, no float.
    #[allow(
        clippy::too_many_lines,
        reason = "one cohesive assault pipeline — target select, forward launch, safe rally, commit — splitting it would scatter the shared geometry across helpers and obscure the flow"
    )]
    fn ai_conquest_military(&self, player: PlayerId) -> Vec<Command> {
        // Hard gate: planet-free maps (survival/golden) never enter here.
        if self.planets.is_empty() {
            return Vec::new();
        }
        // Throttle: re-pathing every idle unit every tick is the RTS perf trap.
        if !self.tick.is_multiple_of(MOVE_REISSUE_PERIOD) {
            return Vec::new();
        }
        // No base ⇒ nowhere to rally from, nothing to do.
        let Some(from) = self.command_center_pos(player) else {
            return Vec::new();
        };

        // --- 1. Choose the assault target. ---
        // Pick the assault target = the NEAREST enemy-owned planet to this civ's
        // base, tie-broken by lowest planet index. Proximity is the dominant lever
        // for one decisive reason: outgoing damage decays with a unit's distance
        // from its NEAREST friendly Command Center (`supply_decay_factor`), bottoming
        // out at 0.6 beyond 20 tiles. A turret-defended seat that a ~14-unit stack
        // breaks at full strength needs far more at the 0.6 floor. Assaulting the
        // CLOSEST enemy world keeps the fight inside the supply ramp (near full
        // strength), so a stack the economy can actually field is enough to crack a
        // soft colony; hitting the softest far-flung colony instead would forever
        // fire at the decay floor and bounce. Distance and index are both STATIC per
        // planet, so the target — and the rally derived from it — does not jitter; it
        // holds until the world falls or changes hands. Ascending index scan; Fixed
        // math, no rng, no float.
        let mut best: Option<(Fixed, usize)> = None;
        for (i, pl) in self.planets.iter().enumerate() {
            // Enemy-owned only (owner is Some and != us).
            let Some(owner) = pl.owner else { continue };
            if owner == player {
                continue;
            }
            let dx = pl.center.x - from.x;
            let dy = pl.center.y - from.y;
            let cc_d2 = dx * dx + dy * dy;
            let cand = (cc_d2, i);
            if best.is_none_or(|b| cand < b) {
                best = Some(cand);
            }
        }

        // Resolve the target world-position (the seat we must reach to capture) and
        // the defensive radius to stay clear of while massing.
        let (target_pos, defense_radius) = if let Some((_, idx)) = best {
            let pid = PlanetId(u16::try_from(idx).unwrap_or(u16::MAX));
            // Aim at the seat entity's position when settled (that's the CC whose
            // destruction triggers capture); else the planet centre.
            let seat_pos = self
                .planet_seat(pid)
                .and_then(|s| self.entity(s))
                .filter(|e| e.alive)
                .map(|e| e.pos);
            let center = self.planet_center(pid).unwrap_or(from);
            let radius = self.planet_radius(pid).unwrap_or(Fixed::ZERO);
            (seat_pos.unwrap_or(center), radius)
        } else {
            // No enemy planet ⇒ assault the nearest enemy CC directly. A CC has no
            // planet claim radius here, so treat it as a point target.
            let Some(cc) = self.enemy_command_center_pos(player) else {
                return Vec::new();
            };
            (cc, Fixed::ZERO)
        };

        // Launch anchor: rally from the friendly CommandCenter (home seat or any
        // settled colony — each colony is a CC) NEAREST the target, not necessarily
        // the main homeworld. Distance-decay is measured from a unit's NEAREST
        // friendly CC, so staging the assault off the closest forward base keeps the
        // committed stack as near full strength as the empire's footprint allows —
        // the difference between bouncing off a turret ring at the 0.6 decay floor
        // and breaking it. Ascending index scan, lowest-index tiebreak; no rng.
        let launch = {
            let mut best_cc: Option<(Vec2, Fixed)> = None;
            for e in &self.entities {
                if !e.alive
                    || e.owner != player
                    || e.kind != Kind::Building(BuildingKind::CommandCenter)
                {
                    continue;
                }
                let d2 = (e.pos - target_pos).length_squared();
                if best_cc.is_none_or(|(_, bd)| d2 < bd) {
                    best_cc = Some((e.pos, d2));
                }
            }
            best_cc.map_or(from, |(p, _)| p)
        };

        // --- 2. Compute a SAFE rally on our side of the front. ---
        // Start partway from the launch anchor toward the target, then if that point
        // falls inside the target's defensive range, pull it back along the
        // launch->target line until it clears (keep_clear). Massing in the open, not
        // under fire.
        let dir = target_pos - launch;
        let total = dir.length();
        // Degenerate (target on top of us): rally at the launch anchor.
        let rally = if total <= Fixed::ZERO {
            launch
        } else {
            // Partway point: launch + dir * (RALLY_NUM / RALLY_DEN).
            let r = launch + dir.scale(Fixed::from_ratio(RALLY_NUM, RALLY_DEN));
            // Keep the rally OUT of the defensive ring (plus a small buffer) so the
            // massing stack is not under fire. `keep_clear` is the minimum allowed
            // distance from the target along the CC->target line.
            let keep_clear = defense_radius + Fixed::from_int(RALLY_GATHER_RADIUS);
            let rdist = (target_pos - r).length();
            if rdist < keep_clear {
                // The partway point is too close: pull it back along the same line
                // so it sits exactly `keep_clear` out from the target. If that would
                // land behind the launch anchor, just rally at the anchor.
                let back = total - keep_clear;
                if back <= Fixed::ZERO {
                    launch
                } else {
                    launch + dir.scale(back / total)
                }
            } else {
                r
            }
        };

        let mut cmds = Vec::new();
        let gather_sq = {
            let g = Fixed::from_int(RALLY_GATHER_RADIUS);
            g * g
        };

        // --- 3/4. Count our combat units already AT the rally (decides commit). ---
        // Ascending index scan; alive `Kind::Unit` within the gather radius.
        let gathered = self
            .entities
            .iter()
            .filter(|e| {
                e.alive
                    && e.owner == player
                    && matches!(e.kind, Kind::Unit(_))
                    && (e.pos - rally).length_squared() <= gather_sq
            })
            .count();

        if gathered >= ASSAULT_STACK {
            // COMMIT: throw the ENTIRE army at the target seat, not just the units
            // inside the gather circle. Once the rally has pooled a critical mass,
            // every combat unit (gathered, stragglers, fresh trainees) attack-moves
            // in — maximising the mass that lands on the seat. Attack-move clears
            // defenders en route and engages the seat, so the existing capture
            // detection in `run_combat` flips the planet. A half-stack trickling in
            // dies to the turret ring; the whole army arriving together overwhelms a
            // soft (lightly-held) seat. (A heavily-fortified homeworld — its 3-gun
            // ring plus its owner's standing army, all firing while the assault wades
            // in at distance-decayed damage — can out-attrit the ~16-20 stack the
            // upkeep-capped economy fields; cracking those is a balance question, not
            // an AI-massing one. See the report.)
            for (i, e) in self.entities.iter().enumerate() {
                if e.alive && e.owner == player && matches!(e.kind, Kind::Unit(_)) {
                    cmds.push(Command::AttackMove {
                        owner: player,
                        unit: EntityId(u32::try_from(i).unwrap_or(u32::MAX)),
                        target: target_pos,
                    });
                }
            }
        } else {
            // MASS: rally every idle combat unit to the safe staging point. Plain
            // Move so they pool (no attack-move stance, no en-route bleed). Idle =
            // no current move_target, so committed/already-rallying units are left
            // alone. Units already inside the gather radius with no order will be
            // (harmlessly) re-issued the same rally Move.
            for unit in self.idle_units(player) {
                cmds.push(Command::Move {
                    owner: player,
                    unit,
                    target: rally,
                });
            }
        }
        cmds
    }

    fn command_center_tile(&self, player: PlayerId) -> Option<(u16, u16)> {
        self.entities
            .iter()
            .find(|e| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .and_then(|e| e.tile)
    }

    /// The living enemy (any owner != `player`) Command Center nearest to
    /// `player`'s own base, as `(entity, distance_squared)`. With two civs the
    /// only candidate is the other civ, so this is identical to the old
    /// `PlayerId(1 - player.0)` lookup; with N civs it picks the closest threat,
    /// ties broken by entity order (deterministic).
    fn nearest_enemy_cc(&self, player: PlayerId) -> Option<&Entity> {
        let from = self.command_center_pos(player);
        let mut best: Option<(&Entity, Fixed)> = None;
        for e in &self.entities {
            if !e.alive
                || e.owner == player
                || e.kind != Kind::Building(BuildingKind::CommandCenter)
            {
                continue;
            }
            // Distance is only a tie-key; with one enemy (two-civ) it is unused.
            let d2 = from.map_or(Fixed::ZERO, |f| {
                let dx = e.pos.x - f.x;
                let dy = e.pos.y - f.y;
                dx * dx + dy * dy
            });
            if best.is_none_or(|(_, bd)| d2 < bd) {
                best = Some((e, d2));
            }
        }
        best.map(|(e, _)| e)
    }

    fn enemy_command_center_pos(&self, player: PlayerId) -> Option<Vec2> {
        self.nearest_enemy_cc(player).map(|e| e.pos)
    }

    fn has_building(&self, player: PlayerId, kind: BuildingKind) -> bool {
        self.entities
            .iter()
            .any(|e| e.alive && e.owner == player && e.kind == Kind::Building(kind))
    }

    fn enemy_has_air(&self, player: PlayerId) -> bool {
        self.entities
            .iter()
            .any(|e| e.alive && e.owner != player && is_air_of(&self.balance, e.kind))
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn idle_barracks(&self, player: PlayerId) -> Option<EntityId> {
        self.entities
            .iter()
            .enumerate()
            .find(|(_, e)| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::Barracks)
                    && e.build_queue.is_empty()
            })
            .map(|(i, _)| EntityId(i as u32))
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn idle_units(&self, player: PlayerId) -> Vec<EntityId> {
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, e)| {
                e.alive
                    && e.owner == player
                    && matches!(e.kind, Kind::Unit(u) if u != UnitKind::Harvester)
                    && e.move_target.is_none()
            })
            .map(|(i, _)| EntityId(i as u32))
            .collect()
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "scan stays within the bounds-checked, non-negative u16 grid"
    )]
    /// Finds a buildable tile in the nearest ring around `center`. When `away_from`
    /// is given (the enemy base), it prefers the tile in that ring *farthest* from
    /// it — so each player expands defensively behind its own base. This keeps
    /// expansion **side-relative** rather than biased toward a fixed world
    /// direction, which a symmetric map needs to play fairly for both sides.
    fn find_buildable_near(
        &self,
        center: (u16, u16),
        away_from: Option<(u16, u16)>,
    ) -> Option<(u16, u16)> {
        let cx = i32::from(center.0);
        let cy = i32::from(center.1);
        // Nearest buildable cell by hex distance; among equidistant cells prefer
        // the one farthest from `away_from` (defensive expansion), then lowest
        // index for a deterministic tie-break.
        let mut best: Option<((u16, u16), i32, i64, usize)> = None;
        for dy in -24..=24i32 {
            for dx in -24..=24i32 {
                let x = cx + dx;
                let y = cy + dy;
                if x < 0 || y < 0 || !self.map.tile(x, y).is_some_and(|t| t.buildable) {
                    continue;
                }
                let cell = (x as u16, y as u16);
                let dist = hex::distance(center, cell);
                if dist == 0 {
                    continue;
                }
                let score = away_from.map_or(0, |(ex, ey)| {
                    let ddx = i64::from(x) - i64::from(ex);
                    let ddy = i64::from(y) - i64::from(ey);
                    ddx * ddx + ddy * ddy
                });
                let idx = y as usize * usize::from(self.map.width()) + x as usize;
                let better = best.is_none_or(|(_, bd, bs, bi)| {
                    dist < bd || (dist == bd && (score > bs || (score == bs && idx < bi)))
                });
                if better {
                    best = Some((cell, dist, score, idx));
                }
            }
        }
        best.map(|(cell, _, _, _)| cell)
    }
}

#[cfg(test)]
impl Sim {
    /// Test-only: force a colony's population (drives supply/build-cap/autonomy
    /// effects without running the growth loop).
    fn set_population_for_test(&mut self, id: ColonyId, pop: u32) {
        self.colonies[id.0 as usize].population = pop;
    }

    /// Test-only: count alive `Building` entities whose tile sits on planet `pid`.
    fn buildings_on_planet_test(&self, pid: PlanetId) -> usize {
        self.entities
            .iter()
            .filter(|e| {
                e.alive
                    && matches!(e.kind, Kind::Building(_))
                    && e.tile.is_some_and(|(tx, ty)| {
                        self.map.planet_at(i32::from(tx), i32::from(ty)) == Some(pid)
                    })
            })
            .count()
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn legacy_maps_have_all_grass_ground() {
        let sim = crate::game::scenario::Scenario::LaneDefense.build(7);
        assert!(sim
            .map()
            .ground_iter()
            .all(|g| g == crate::game::map::Ground::Grass));
    }

    #[test]
    fn earthfront_hash_depends_on_ground_but_legacy_does_not() {
        use crate::game::map::Ground;
        let mut a = crate::game::scenario::Scenario::Survival.build(2026);
        let b = crate::game::scenario::Scenario::Survival.build(2026);
        assert_eq!(a.state_hash(), b.state_hash());
        a.map_mut().set_ground(3, 3, Ground::Flats);
        assert_ne!(a.state_hash(), b.state_hash());

        let mut l1 = crate::game::scenario::Scenario::OpenClash.build(5);
        let l2 = crate::game::scenario::Scenario::OpenClash.build(5);
        l1.map_mut().set_ground(0, 0, Ground::Flats); // legacy must not hash ground
        assert_eq!(l1.state_hash(), l2.state_hash());
    }

    use super::{
        ascend_cost, tile_center, BuildingKind, Command, EntityId, EntityKindView, Kind, PlayerId,
        Sim, UnitKind, WaveConfig, SUPPLY_DECAY_FLOOR, UPKEEP_STEP,
    };
    use crate::fixed::Fixed;
    use crate::game::civ::ColonyId;
    use crate::game::map::{Ground, Map, TerrainKind};
    use crate::game::planet::{Planet, PlanetId};
    use crate::vec::Vec2;

    fn f(n: i32) -> Fixed {
        Fixed::from_int(n)
    }
    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(f(x), f(y))
    }
    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    /// Empire-administration upkeep scales SUPER-LINEARLY with colony count: each
    /// extra colony costs strictly more than the last, so a wide empire pays
    /// disproportionately more upkeep per colony than a small one. Verified two ways:
    /// the exact closed-form curve for n = 1,2,4,8, and a stepped-economy run where
    /// the many-colony player bleeds MORE-THAN-PROPORTIONALLY more Money than a
    /// one-colony player. Fully deterministic (integer/`Fixed`, no rng, no float).
    #[test]
    fn empire_upkeep_scales_superlinearly() {
        const TICKS: i32 = 10;
        const CREDITS: i32 = 100_000; // ample headroom so upkeep never clamps at zero

        // A bare, planet-free map: colonies here have no planet yield (Money output
        // is ZERO) and no tech, so the ONLY money movement in `run_economy` is the
        // upkeep deduction — letting us read it off exactly from stockpile deltas.
        // `seat` validity is irrelevant: upkeep keys purely off owned-colony COUNT.
        fn sim_with_colonies(n: usize, credits: i32) -> Sim {
            let mut s = Sim::with_civ_count(Map::new(8, 8), 1, f(credits), 2);
            // One real CC seat to anchor the colonies (count is what upkeep reads).
            let seat = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
            for _ in 0..n {
                s.add_colony(P0, seat, 0);
            }
            s
        }

        // --- Exact closed-form curve: triangular UPKEEP_STEP·n·(n−1)/2 ---
        // n=1→0, 2→1·step, 3→3·step, 4→6·step, 8→28·step.
        let upkeep_for = |n: usize| sim_with_colonies(n, 100_000).empire_upkeep(P0);
        assert_eq!(upkeep_for(1), Fixed::ZERO, "the first colony is free");
        assert_eq!(upkeep_for(2), UPKEEP_STEP * f(1));
        assert_eq!(upkeep_for(4), UPKEEP_STEP * f(6));
        assert_eq!(upkeep_for(8), UPKEEP_STEP * f(28));

        // PER-COLONY upkeep strictly rises with empire size (the super-linearity):
        // doubling colonies more-than-doubles total upkeep, so cost/colony climbs.
        // 4 colonies cost 6·step total (1.5·step each) vs 2 colonies' 1·step total
        // (0.5·step each); 8 cost 28·step (3.5·step each). Compare with integer
        // cross-multiplication to stay float-free: upkeep(8)/8 > upkeep(4)/4 ⇔
        // upkeep(8)·4 > upkeep(4)·8.
        let per4_x = upkeep_for(4) * f(8); // upkeep(4) scaled by 8
        let per8_x = upkeep_for(8) * f(4); // upkeep(8) scaled by 4
        assert!(
            per8_x > per4_x,
            "per-colony upkeep must rise with empire size (super-linear)"
        );

        // --- Stepped-economy run: the deduction actually happens, and the wide
        // empire loses MORE-THAN-PROPORTIONALLY more Money over the same ticks. ---
        let run = |n: usize| -> Fixed {
            let mut s = sim_with_colonies(n, CREDITS);
            let before = s.money(P0);
            for _ in 0..TICKS {
                s.run_economy();
            }
            before - s.money(P0) // total Money paid in upkeep over TICKS
        };
        let paid_2 = run(2);
        let paid_8 = run(8);
        // Exact: TICKS · UPKEEP_STEP · n·(n−1)/2.
        assert_eq!(paid_2, f(TICKS) * UPKEEP_STEP * f(1));
        assert_eq!(paid_8, f(TICKS) * UPKEEP_STEP * f(28));
        // The 8-colony leader holds 4× the colonies of the 2-colony follower but
        // pays 28× the upkeep — far more than the 4× a flat per-colony tax would
        // give. Assert strictly more than proportional: paid_8 > 4 · paid_2.
        assert!(
            paid_8 > paid_2 * f(4),
            "wide empire must pay MORE than proportionally more upkeep \
             (paid_8={paid_8:?} should exceed 4·paid_2={:?})",
            paid_2 * f(4)
        );
    }

    #[test]
    #[allow(
        clippy::identity_op,
        reason = "the explicit * 1 spells out SUPPLY_PER_POP for clarity"
    )]
    fn population_scales_supply_cap() {
        let mut s = Sim::new(Map::new(8, 8), 1, f(0));
        let pid = PlanetId(0);
        s.map_mut().set_planet(0, 0, pid);
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
        s.push_planet(Planet {
            owner: Some(P0),
            seat: Some(cc),
            center: tile_center(0, 0),
            radius: f(1),
        });
        // Capture the cap before the colony exists, so the full population term
        // (not just the delta over the birth population of 1) is the measured rise.
        let before = s.supply_cap(P0);
        let id = s.add_colony(P0, cc, 0);
        s.set_population_for_test(id, 5);
        assert_eq!(
            s.supply_cap(P0),
            before + 5 * 1,
            "supply rises by SUPPLY_PER_POP * population"
        );
    }

    #[test]
    fn population_gates_building_count() {
        let mut s = Sim::new(Map::new(10, 10), 1, f(100_000));
        let pid = PlanetId(0);
        for y in 0..3 {
            for x in 0..3 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
        s.push_planet(Planet {
            owner: Some(P0),
            seat: Some(cc),
            center: tile_center(1, 1),
            radius: f(2),
        });
        let id = s.add_colony(P0, cc, 0);
        // population 1, BUILDINGS_PER_POP 2 -> cap 2 buildings on this planet (CC
        // counts as 1). A second build succeeds (total 2); a third is rejected
        // until population rises.
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 1,
            y: 0,
        }]);
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 0,
            y: 1,
        }]); // would be 3rd building
        assert_eq!(
            s.buildings_on_planet_test(pid),
            2,
            "building count capped at BUILDINGS_PER_POP*pop"
        );
        s.set_population_for_test(id, 3); // cap now 6
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 0,
            y: 1,
        }]);
        assert_eq!(
            s.buildings_on_planet_test(pid),
            3,
            "raising population lifts the cap"
        );
    }

    #[test]
    fn terrain_layer_and_planet_yield_cache() {
        let mut s = Sim::new(Map::new(10, 10), 1, f(0));
        let pid = PlanetId(0);
        s.push_planet(Planet {
            owner: None,
            seat: None,
            center: tile_center(1, 1),
            radius: f(2),
        });
        for y in 0..2 {
            for x in 0..2 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        s.map_mut().set_terrain(0, 0, TerrainKind::Fertile);
        s.map_mut().set_terrain(1, 0, TerrainKind::Fertile);
        s.rebuild_planet_yield();
        // 2 * Fertile.food(1/2) = 1.0
        assert_eq!(s.planet_yield_of(pid)[0], Fixed::from_int(1));
        assert_eq!(s.map().terrain_at(5, 5), TerrainKind::Barren);
    }

    #[test]
    fn colony_cap_and_rates_derive_from_planet() {
        let mut s = Sim::new(Map::new(10, 10), 1, f(0));
        let pid = PlanetId(0);
        for y in 0..2 {
            for x in 0..2 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        s.map_mut().set_terrain(0, 0, TerrainKind::Fertile); // food 1/2, money 1/8
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
        s.push_planet(Planet {
            owner: Some(P0),
            seat: Some(cc),
            center: tile_center(0, 0),
            radius: f(2),
        });
        let id = s.add_colony(P0, cc, 0);
        s.rebuild_planet_yield();
        let ci = id.0 as usize;
        assert_eq!(s.colony_food_rate(ci), Fixed::from_ratio(1, 2));
        assert_eq!(s.colony_output_rate(ci, 0), Fixed::from_ratio(1, 8)); // money at pop 1
        assert_eq!(s.colony_pop_cap(ci), 5); // housing_base(4 tiles)=2+1=3 + 1 CC*2 = 5
        assert!(!s.colony_mature(ci)); // pop 1 < cap 5
    }

    #[test]
    fn active_colony_grows_population_and_halts_at_cap() {
        let mut s = Sim::new(Map::new(8, 8), 1, f(0));
        let pid = PlanetId(0);
        for y in 0..2 {
            for x in 0..2 {
                s.map_mut().set_planet(x, y, pid);
            }
            s.map_mut().set_terrain(0, y, TerrainKind::Fertile);
        }
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
        s.push_planet(Planet {
            owner: Some(P0),
            seat: Some(cc),
            center: tile_center(0, 0),
            radius: f(2),
        });
        let id = s.add_colony(P0, cc, 0);
        s.rebuild_planet_yield();
        let cap = s.colony_pop_cap(id.0 as usize);
        for _ in 0..6000 {
            s.step(&[]);
        }
        assert_eq!(
            s.colony(id).unwrap().population,
            cap,
            "growth halts exactly at cap"
        );
        assert!(cap > 1, "test planet must allow growth beyond 1");
    }

    #[test]
    fn new_sim_has_starting_credits_and_no_winner() {
        let s = Sim::new(Map::new(16, 16), 1, f(500));
        assert_eq!(s.money(P0), f(500));
        assert_eq!(s.money(P1), f(500));
        assert_eq!(s.winner(), None);
        assert_eq!(s.tick(), 0);
    }

    #[test]
    fn losing_last_command_center_eliminates_and_decides_winner() {
        let mut s = Sim::new(Map::new(16, 16), 3, f(2000));
        let a = s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let _b = s.add_building(P1, BuildingKind::CommandCenter, 13, 13);
        // Kill P0's only CC outright (no planet -> normal death, not capture).
        s.debug_set_hp(a, f(0));
        s.step(&[]);
        assert!(!s.civ_alive(P0), "civ with no CC is eliminated");
        assert!(s.civ_alive(P1));
        assert_eq!(s.winner(), Some(P1), "sole survivor wins");
    }

    /// The aggressive conquest AI must actually RESOLVE assaults — not just trickle
    /// units to their death. With every civ driven by `ai_commands`, require that
    /// within the run a real COMBAT CAPTURE happens: a planet that was already OWNED
    /// changes to a DIFFERENT owner (an owner→other-owner flip, which the engine only
    /// produces by driving a held seat's HP to zero — see `apply_seat_capture`). That
    /// is categorically different from a neutral being settled for the first time
    /// (None→owner), and it cannot occur unless the AI masses a stack and breaks a
    /// DEFENDED seat. A civ elimination also counts. Either proves the old frozen
    /// stalemate (zero captures, armies stuck at 1-6) is gone.
    ///
    /// NB: this asserts a captured *defended seat*, not specifically one of the four
    /// turret-ringed starting HOMEWORLDS. Measurement showed those fortified cores
    /// are NOT broken by the ~16-20-unit army the upkeep-capped economy fields once
    /// distance-decay and the defenders' standing army are accounted for; that is a
    /// balance ceiling (turret ring / decay / upkeep), deliberately left to a human
    /// tuning pass rather than worked around in the AI. See the report.
    ///
    /// Deterministic by construction (`ai_commands` is a pure function of state, no
    /// rng), so this is a stable regression guard against the AI ever regressing to a
    /// no-capture trickle.
    #[test]
    fn conquest_ai_breaks_a_defended_homeworld() {
        use crate::game::scenario::conquest;
        const CIVS: u16 = 4;
        let mut s = conquest(12_345, usize::from(CIVS));
        let pn = u16::try_from(s.planets_len()).unwrap();

        // Per-planet last-seen owner, and the set of civs alive at the start.
        let mut last_owner: Vec<Option<PlayerId>> =
            (0..pn).map(|p| s.planet_owner(PlanetId(p))).collect();
        let start_alive: Vec<bool> = (0..CIVS).map(|c| s.civ_alive(PlayerId(c))).collect();

        let mut captured = false;
        let mut eliminated = false;
        for _ in 0..12_000u32 {
            let cmds: Vec<Command> = (0..CIVS)
                .filter(|&c| s.civ_alive(PlayerId(c)))
                .flat_map(|c| s.ai_commands(PlayerId(c)))
                .collect();
            s.step(&cmds);

            for p in 0..pn {
                let now = s.planet_owner(PlanetId(p));
                let prev = last_owner[p as usize];
                // A combat capture is an owned→DIFFERENT-owned transition. A
                // None→owner change (first settlement) and owner→None (never happens
                // for seats) are excluded, so this fires only on a real seat capture.
                if let (Some(a), Some(b)) = (prev, now) {
                    if a != b {
                        captured = true;
                    }
                }
                last_owner[p as usize] = now;
            }
            for c in 0..CIVS {
                if start_alive[c as usize] && !s.civ_alive(PlayerId(c)) {
                    eliminated = true;
                }
            }
            if captured || eliminated {
                break;
            }
        }

        assert!(
            captured || eliminated,
            "aggressive conquest AI must resolve assaults: a held, defended planet \
             seat should be captured (or a civ eliminated) within 12000 ticks — \
             proving the AI masses a stack and breaks a defended seat rather than \
             trickling units to their death"
        );
    }

    /// Conquest with all civs AI-driven must be bit-for-bit reproducible: the
    /// massing/assault logic is a pure function of state (ascending-index scans,
    /// `Fixed` math, no rng), so two independent runs land on the same state hash.
    #[test]
    fn conquest_ai_offence_is_deterministic() {
        use crate::game::scenario::conquest;
        fn run() -> u64 {
            let mut s = conquest(12_345, 4);
            for _ in 0..4_000u32 {
                let cmds: Vec<Command> = (0..4u16)
                    .filter(|&c| s.civ_alive(PlayerId(c)))
                    .flat_map(|c| s.ai_commands(PlayerId(c)))
                    .collect();
                s.step(&cmds);
            }
            s.state_hash()
        }
        assert_eq!(run(), run(), "AI-driven conquest must replay identically");
    }

    /// A conquest game must ALWAYS resolve to a winner: a fully fortified multi-civ
    /// standoff that never collapses to a single survivor is decided by the tick cap
    /// (or earlier by domination). Drives all four civs with `ai_commands` and asserts
    /// `winner()` is `Some` by `CONQUEST_TICK_CAP` — the flagship mode is winnable.
    #[test]
    fn conquest_resolves_by_timeout_or_domination() {
        use super::CONQUEST_TICK_CAP;
        use crate::game::scenario::conquest;
        let mut s = conquest(12_345, 4);
        // While unresolved, winner() is None (the game is genuinely ongoing).
        assert!(
            s.winner().is_none(),
            "a fresh conquest game has no winner yet"
        );

        let mut resolved_at: Option<u64> = None;
        // Run AT MOST up to the cap. The +1 lets the cap tick itself be evaluated.
        for _ in 0..=CONQUEST_TICK_CAP {
            if s.winner().is_some() {
                resolved_at = Some(s.tick);
                break;
            }
            let cmds: Vec<Command> = (0..4u16)
                .filter(|&c| s.civ_alive(PlayerId(c)))
                .flat_map(|c| s.ai_commands(PlayerId(c)))
                .collect();
            s.step(&cmds);
        }
        // If the loop fell through without an early winner, the cap tick must decide.
        let winner = s.winner();
        assert!(
            winner.is_some(),
            "conquest must resolve to a winner by the tick cap (tick={}, cap={})",
            s.tick,
            CONQUEST_TICK_CAP
        );
        // Whoever it resolved to must be an alive civ (last-standing, dominator, or
        // the timeout leader) — never a civ that already lost its base.
        let w = winner.unwrap();
        assert!(
            s.civ_alive(w),
            "the resolved winner must still hold a base (winner={w:?}, resolved_at={resolved_at:?})"
        );
    }

    /// Domination victory: an alive civ owning a strict majority (> 60%) of all
    /// planets wins a conquest game IMMEDIATELY, without grinding out the last seat.
    /// Read straight from current planet ownership (no hashed counter), so it is
    /// instantaneous and deterministic.
    #[test]
    fn conquest_majority_planet_owner_wins_immediately() {
        let mut s = Sim::new(Map::new(24, 24), 1, f(0));
        // Five planets; both civs keep a CommandCenter (so neither is eliminated and
        // the single-survivor rule does NOT fire — domination must be what resolves).
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P1, BuildingKind::CommandCenter, 20, 20);
        for i in 0..5u16 {
            s.push_planet(Planet {
                owner: None,
                seat: None,
                center: tile_center(i, 0),
                radius: f(2),
            });
        }
        // Two of five owned (40%) is not a strict majority of > 60% ⇒ no winner yet
        // (both civs still hold a CC, so it's a genuine ongoing game).
        s.set_planet_owner(PlanetId(0), Some(P0));
        s.set_planet_owner(PlanetId(1), Some(P0));
        assert_eq!(
            s.winner(),
            None,
            "40% of planets is below the >60% domination threshold"
        );
        // A fourth planet (4/5 = 80% > 60%) flips P0 to an immediate domination win,
        // even though P1 still holds its base.
        s.set_planet_owner(PlanetId(2), Some(P0));
        s.set_planet_owner(PlanetId(3), Some(P0));
        assert_eq!(
            s.winner(),
            Some(P0),
            "a civ owning a strict majority (>60%) of planets wins immediately"
        );
    }

    #[test]
    fn refinery_on_deposit_mines_money_when_powered() {
        let mut map = Map::new(16, 16);
        map.set_deposit(
            5,
            1,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 100,
            },
        );
        let mut s = Sim::new(map, 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        s.add_building(P0, BuildingKind::Refinery, 5, 1); // ON the ore deposit
        let before = s.money(P0).to_bits();
        s.step(&[]);
        // Refinery mine_rate is 5/tick while powered.
        assert!(
            s.money(P0).to_bits() > before,
            "refinery should mine money from ore deposit"
        );
    }

    #[test]
    fn refinery_deploys_a_harvester_that_hauls_ore_home() {
        let mut map = Map::new(16, 8);
        map.set_deposit(
            9,
            3,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 1_000,
            },
        );
        let mut s = Sim::new(map, 11, f(500));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 1, 4);
        s.step(&[]); // accrue the Refinery's Energy/Labour construction costs
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Refinery,
            x: 3,
            y: 3,
        }]);
        let after_build = s.money(P0);
        assert!(s
            .entities
            .iter()
            .all(|e| { !(e.alive && e.owner == P0 && e.kind == Kind::Unit(UnitKind::Harvester)) }));
        let duration = s.balance.building(BuildingKind::Refinery).build_time;
        for _ in 1..duration {
            s.step(&[]);
        }
        assert!(s
            .entities
            .iter()
            .any(|e| { e.alive && e.owner == P0 && e.kind == Kind::Unit(UnitKind::Harvester) }));

        for _ in 0..700 {
            s.step(&[]);
        }
        assert!(
            s.money(P0) > after_build,
            "the ore truck must deliver credits back to its Refinery"
        );
        assert!(
            s.map.deposit(9, 3).unwrap().remaining < 1_000,
            "the visible truck must mine the finite map deposit"
        );
    }

    #[test]
    fn extractor_mines_at_full_rate() {
        let mut map = Map::new(16, 16);
        map.set_deposit(
            5,
            1,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 100,
            },
        );
        let mut s = Sim::new(map, 1, f(0));
        // No power gradient anymore: an extractor mines its full rate.
        s.add_building(P0, BuildingKind::Refinery, 5, 1);
        s.step(&[]);
        // mine_rate 2 → 2 Money/tick.
        assert_eq!(s.money(P0), f(2));
    }

    #[test]
    fn build_command_places_building_and_charges() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(1000));
        let before = s.entity_count();
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::PowerPlant,
            x: 5,
            y: 5,
        }]);
        assert_eq!(s.entity_count(), before + 1);
        assert_eq!(s.money(P0), f(900)); // 1000 - 100
        assert!(!s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn build_fails_when_unaffordable() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(50));
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::PowerPlant,
            x: 5,
            y: 5,
        }]);
        assert_eq!(s.entity_count(), 0);
        assert_eq!(s.money(P0), f(50));
        assert!(s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn training_spawns_a_unit_after_build_time() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 1);
        let units_before = s.unit_count(P0);
        // Let the HQ accrue a little Labour first (Infantry now costs 1 Labour).
        for _ in 0..2 {
            s.step(&[]);
        }
        s.step(&[Command::Train {
            owner: P0,
            barracks,
            kind: UnitKind::Infantry,
        }]);
        assert_eq!(s.money(P0), f(950)); // charged immediately
        let status = s.production_status(barracks).unwrap();
        assert_eq!(status.unit, UnitKind::Infantry);
        assert_eq!(status.queued, 1);
        assert!(status.progress < status.duration);
        // Infantry build time is 90 ticks; not yet spawned at 89.
        for _ in 0..88 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P0), units_before);
        s.step(&[]); // 90th tick
        assert_eq!(s.unit_count(P0), units_before + 1);
        assert_eq!(s.production_status(barracks), None);
    }

    #[test]
    fn producer_rally_is_inherited_by_completed_units() {
        let mut s = Sim::new(Map::new(20, 20), 5, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 1);
        for _ in 0..2 {
            s.step(&[]);
        }
        let rally = v(12, 12);
        s.step(&[
            Command::SetRally {
                owner: P0,
                producer: barracks,
                target: rally,
            },
            Command::Train {
                owner: P0,
                barracks,
                kind: UnitKind::Infantry,
            },
        ]);
        let expected_rally = s.entities[barracks.0 as usize].rally.unwrap();
        for _ in 0..90 {
            s.step(&[]);
        }
        assert!(s.entities.iter().any(|e| {
            e.alive
                && e.owner == P0
                && e.kind == Kind::Unit(UnitKind::Infantry)
                && e.move_target == Some(expected_rally)
        }));
    }

    #[test]
    fn production_pauses_without_power_and_resumes_when_power_returns() {
        let mut s = Sim::new(Map::new(20, 20), 5, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 1);
        for _ in 0..2 {
            s.step(&[]);
        }
        s.step(&[Command::Train {
            owner: P0,
            barracks,
            kind: UnitKind::Infantry,
        }]);
        for _ in 0..100 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P0), 0);
        assert_eq!(s.production_status(barracks).unwrap().progress, 0);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        for _ in 0..90 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P0), 1);
    }

    #[test]
    fn repair_costs_money_and_sell_refunds_and_frees_tile() {
        let mut s = Sim::new(Map::new(16, 16), 2, f(1000));
        let wall = s.add_building(P0, BuildingKind::Wall, 5, 5);
        s.entities[wall.0 as usize].hp = f(20);
        let before_repair = s.money(P0);
        s.step(&[Command::Repair {
            owner: P0,
            building: wall,
        }]);
        assert!(s.entities[wall.0 as usize].hp > f(20));
        assert!(s.money(P0) < before_repair);
        let before_sell = s.money(P0);
        s.step(&[Command::Sell {
            owner: P0,
            building: wall,
        }]);
        assert!(!s.entity_alive(wall));
        assert!(s.money(P0) > before_sell);
        assert!(s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn unit_moves_toward_target_and_arrives() {
        let mut s = Sim::new(Map::new(64, 64), 1, f(0));
        let u = s.add_unit(P0, UnitKind::Infantry, v(0, 0));
        s.step(&[Command::Move {
            owner: P0,
            unit: u,
            target: v(10, 0),
        }]);
        // moved at least a little on the first tick
        assert!(s.position(u).unwrap().x > Fixed::ZERO);
        for _ in 0..200 {
            s.step(&[]);
        }
        assert_eq!(s.position(u), Some(v(10, 0)));
    }

    fn first_tick_dx(ground: Ground, earthfront: bool, kind: UnitKind) -> i64 {
        let mut m = Map::new(32, 8);
        for x in 0..32u16 {
            m.set_ground(x, 2, ground);
        }
        let mut s = Sim::new(m, 1, f(0));
        if earthfront {
            s.enable_earthfront();
        }
        let u = s.add_unit(P0, kind, tile_center(2, 2));
        let before = s.position(u).unwrap().x;
        s.step(&[Command::Move {
            owner: P0,
            unit: u,
            target: tile_center(20, 2),
        }]);
        (s.position(u).unwrap().x - before).to_bits()
    }

    #[test]
    fn tanks_slow_on_highland_and_ford_and_speed_up_on_flats_in_earthfront() {
        let grass = first_tick_dx(Ground::Grass, true, UnitKind::Tank);
        assert!(first_tick_dx(Ground::Flats, true, UnitKind::Tank) > grass);
        let hi = first_tick_dx(Ground::Highland, true, UnitKind::Tank);
        assert!(hi < grass);
        assert!(first_tick_dx(Ground::Ford, true, UnitKind::Tank) < hi);
    }

    #[test]
    fn ford_slows_tanks_more_than_infantry() {
        let tank = first_tick_dx(Ground::Ford, true, UnitKind::Tank) * 100
            / first_tick_dx(Ground::Grass, true, UnitKind::Tank);
        let inf = first_tick_dx(Ground::Ford, true, UnitKind::Infantry) * 100
            / first_tick_dx(Ground::Grass, true, UnitKind::Infantry);
        assert!(tank < inf);
    }

    #[test]
    fn ground_never_changes_speed_outside_earthfront() {
        assert_eq!(
            first_tick_dx(Ground::Highland, false, UnitKind::Tank),
            first_tick_dx(Ground::Grass, false, UnitKind::Tank)
        );
    }

    /// HP the lone P1 wall loses over a 30-tick volley from a P0 tank, with the given ground
    /// under each and `gap_tiles` of separation along row 2. A wall (200 HP) is the target
    /// because infantry (50 HP) dies inside the window, which would cap the measured loss.
    fn volley_loss(
        att_ground: Ground,
        tgt_ground: Ground,
        gap_tiles: u16,
        earthfront: bool,
    ) -> i64 {
        let mut m = Map::new(40, 8);
        for x in 0..40u16 {
            m.set_ground(x, 2, Ground::Grass);
        }
        m.set_ground(2, 2, att_ground);
        m.set_ground(2 + gap_tiles, 2, tgt_ground);
        let mut s = Sim::new(m, 1, f(0));
        if earthfront {
            s.enable_earthfront();
        }
        let _att = s.add_unit(P0, UnitKind::Tank, tile_center(2, 2));
        let tgt = s.add_building(P1, BuildingKind::Wall, 2 + gap_tiles, 2);
        let hp0 = s.entities[tgt.0 as usize].hp.to_bits();
        for _ in 0..30 {
            s.step(&[]);
        }
        hp0 - s.entities[tgt.0 as usize].hp.to_bits()
    }

    /// Smallest column gap (from the attacker at column 2, row 2) whose true hex-grid
    /// distance exceeds the tank's base range; asserts it still sits within +25 percent.
    fn gap_beyond_base_range_within_highland_reach() -> u16 {
        let range = UnitKind::Tank.stats().attack.range;
        let range_sq = range * range;
        let from = tile_center(2, 2);
        let gap = (1..30u16)
            .find(|&g| (tile_center(2 + g, 2) - from).length_squared() > range_sq)
            .unwrap();
        let dist_sq = (tile_center(2 + gap, 2) - from).length_squared();
        // (1.25 * range)^2 == range^2 * 15625 / 10000
        assert!(dist_sq * Fixed::from_int(10_000) <= range_sq * Fixed::from_int(15_625));
        gap
    }

    #[test]
    fn highland_attacker_reaches_targets_a_grass_attacker_cannot() {
        let gap = gap_beyond_base_range_within_highland_reach();
        assert_eq!(volley_loss(Ground::Grass, Ground::Grass, gap, true), 0);
        assert!(volley_loss(Ground::Highland, Ground::Grass, gap, true) > 0);
    }

    #[test]
    fn forest_cover_removes_twenty_percent_of_damage() {
        let open = volley_loss(Ground::Grass, Ground::Grass, 1, true);
        let wood = volley_loss(Ground::Grass, Ground::Forest, 1, true);
        assert!(open > 0);
        // allow 2 Fixed bits per tick of rounding across the 30-tick window
        assert!(
            (wood * 100 - open * 80).abs() <= 60 * 100,
            "wood={wood} open={open}"
        );
    }

    #[test]
    fn combat_cell_covers_highland_extended_range() {
        let mut ranges: Vec<Fixed> = Vec::new();
        for u in [
            UnitKind::Harvester,
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::AntiArmor,
            UnitKind::Helicopter,
            UnitKind::Capital,
        ] {
            ranges.push(u.stats().attack.range);
        }
        for b in [
            BuildingKind::CommandCenter,
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
            BuildingKind::GunTurret,
            BuildingKind::AaTurret,
            BuildingKind::Wall,
            BuildingKind::ResearchLab,
            BuildingKind::AntimatterPlant,
            BuildingKind::VehicleFactory,
            BuildingKind::Airfield,
            BuildingKind::SupplyDepot,
            BuildingKind::Battery,
        ] {
            if let Some(a) = b.stats().attack {
                ranges.push(a.range);
            }
        }
        let max = ranges.into_iter().max().unwrap();
        let highland = max * Fixed::from_int(125) / Fixed::from_int(100);
        assert!(
            highland <= Fixed::from_int(super::COMBAT_CELL),
            "highland-extended max range {highland:?} exceeds COMBAT_CELL {}",
            super::COMBAT_CELL
        );
    }

    #[test]
    fn legacy_scenarios_ignore_cover_and_range_bonus() {
        assert_eq!(
            volley_loss(Ground::Grass, Ground::Forest, 1, false),
            volley_loss(Ground::Grass, Ground::Grass, 1, false)
        );
        let gap = gap_beyond_base_range_within_highland_reach();
        assert_eq!(volley_loss(Ground::Highland, Ground::Grass, gap, false), 0);
    }

    #[test]
    fn combat_destroys_an_enemy_structure() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let tank = s.add_unit(P0, UnitKind::Tank, v(0, 0));
        let wall = s.add_building(P1, BuildingKind::Wall, 1, 1);
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(!s.is_alive(wall));
        assert!(s.is_alive(tank));
    }

    #[test]
    fn unit_does_not_move_to_a_walled_off_target() {
        let mut s = Sim::new(Map::new(8, 8), 1, f(0));
        // A full wall on column x=4 splits the map in two.
        for y in 0..8 {
            s.add_building(P1, BuildingKind::Wall, 4, y);
        }
        let u = s.add_unit(P0, UnitKind::Infantry, v(0, 0));
        let before = s.position(u);
        s.step(&[Command::Move {
            owner: P0,
            unit: u,
            target: Vec2::new(f(7), f(7)),
        }]);
        for _ in 0..50 {
            s.step(&[]);
        }
        // No route across the wall, so the unit never accepted a move target.
        assert_eq!(s.position(u), before);
    }

    #[test]
    fn winner_is_the_last_player_with_a_command_center() {
        let mut only_p0 = Sim::new(Map::new(16, 16), 1, f(0));
        only_p0.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        assert_eq!(only_p0.winner(), Some(P0));

        let mut both = Sim::new(Map::new(16, 16), 1, f(0));
        both.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        both.add_building(P1, BuildingKind::CommandCenter, 10, 10);
        assert_eq!(both.winner(), None);
    }

    #[test]
    fn views_report_living_entities_for_rendering() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        let tank = s.add_unit(P1, UnitKind::Tank, v(3, 3));
        let views = s.views();
        assert_eq!(views.len(), 2);
        let cc_view = views.iter().find(|w| w.id == cc).unwrap();
        assert_eq!(cc_view.owner, P0);
        assert!(matches!(
            cc_view.kind,
            EntityKindView::Building(BuildingKind::CommandCenter)
        ));
        let tank_view = views.iter().find(|w| w.id == tank).unwrap();
        assert_eq!(tank_view.pos, v(3, 3));
        assert!(matches!(
            tank_view.kind,
            EntityKindView::Unit(UnitKind::Tank)
        ));
    }

    fn scenario(seed: u64) -> Sim {
        let mut s = Sim::new(Map::new(48, 48), seed, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
        s.add_building(P1, BuildingKind::CommandCenter, 40, 40);
        s.add_unit(P0, UnitKind::Tank, v(5, 5));
        s.add_unit(P1, UnitKind::Infantry, v(7, 5));
        s
    }

    /// Distance-decayed combat: one Infantry (P0) shoots one stationary Tank (P1)
    /// for exactly one combat tick. The attacker–target geometry is identical in
    /// both runs; only the attacker's distance from its OWN Command Center differs.
    /// `at` is the bottom-left anchor of the (CC, attacker, target) cluster, so the
    /// far run is a pure translation of the near run.
    ///
    /// Returns the damage dealt = (target `max_hp` − target hp after one tick).
    fn one_shot_damage(cc_at: (u16, u16), atk: Vec2, tgt: Vec2) -> Fixed {
        let mut s = Sim::new(Map::new(60, 60), 1, f(0));
        // P0's only anchor.
        s.add_building(P0, BuildingKind::CommandCenter, cc_at.0, cc_at.1);
        // Attacker (P0) and a fat target (P1). Tank has 220 hp, so a single 6-dmg
        // Infantry shot (after the Ballistic-vs-Plated matrix, constant across both
        // runs) leaves it comfortably alive — a clean hp delta to read.
        let attacker = s.add_unit(P0, UnitKind::Infantry, atk);
        let target = s.add_unit(P1, UnitKind::Tank, tgt);
        let max = s.entities[target.0 as usize].hp;
        // One step: movement (nobody has a move order), then combat fires once.
        s.step(&[]);
        // Sanity: the attacker actually fired (went on cooldown) and the target
        // took a hit. Without this the test could pass vacuously on zero damage.
        assert!(
            s.entities[attacker.0 as usize].cooldown > 0,
            "attacker must have fired this tick"
        );
        max - s.entities[target.0 as usize].hp
    }

    #[test]
    fn combat_decays_with_distance_from_command_center() {
        // Identical attacker/target geometry (attacker 1 tile from target, well
        // within Infantry's range 3). Run #1: the attacker sits ON its CC (full
        // supply). Run #2: the whole cluster is translated to the far corner, so
        // the attacker is > SUPPLY_DECAY_RADIUS (20) from its only CC.
        let near = one_shot_damage((2, 2), v(2, 2), v(3, 2));
        // Far cluster: CC at (50,50), attacker at (50,50) would be adjacent — we
        // want the ATTACKER far from the CC, so put the CC back near the origin
        // and march the attacker+target to the opposite corner (distance ~67 >> 20).
        let far = one_shot_damage((2, 2), v(50, 50), v(51, 50));

        // The overextended attacker deals strictly LESS damage...
        assert!(
            far < near,
            "an attacker far from its Command Center must deal less damage \
             (near={} far={})",
            near.to_bits(),
            far.to_bits()
        );
        // ...and the near attacker deals FULL strength: exactly the factor-1
        // baseline (what it would deal touching the CC). This is the pre-feature
        // damage, proving the plateau is unpenalised.
        let baseline = one_shot_damage((2, 2), v(2, 2), v(3, 2));
        assert_eq!(
            near, baseline,
            "an attacker on its CC must deal full (factor-1) damage"
        );
        // And the floor is respected: far damage is at least FLOOR (0.6) of full,
        // never zero — the penalty nudges, it doesn't erase the attack.
        assert!(
            far >= near * SUPPLY_DECAY_FLOOR,
            "decayed damage must not drop below the FLOOR (near={} far={} floor=0.6)",
            near.to_bits(),
            far.to_bits()
        );
    }

    #[test]
    fn combat_full_strength_within_full_radius() {
        // An attacker anywhere inside SUPPLY_FULL_RADIUS (6 tiles) of its CC deals
        // the SAME damage as one touching the CC: the factor==1 plateau is flat.
        // CC at (2,2). Touching: attacker at (2,2). Inside the plateau: attacker at
        // (7,2) — 5 tiles away, still <= FULL_RADIUS=6.
        let touching = one_shot_damage((2, 2), v(2, 2), v(3, 2));
        let inside_plateau = one_shot_damage((2, 2), v(7, 2), v(8, 2));
        assert_eq!(
            inside_plateau,
            touching,
            "within FULL_RADIUS the supply factor is a flat 1 — damage must match \
             touching the CC (touching={} inside={})",
            touching.to_bits(),
            inside_plateau.to_bits()
        );
    }

    #[test]
    fn same_setup_and_commands_produce_same_hash() {
        let mut a = scenario(99);
        let mut b = scenario(99);
        let script: [&[Command]; 5] = [
            &[Command::Build {
                owner: P0,
                kind: BuildingKind::Barracks,
                x: 6,
                y: 2,
            }],
            &[Command::Move {
                owner: P0,
                unit: EntityId(3),
                target: Vec2::new(f(7), f(5)),
            }],
            &[],
            &[Command::Build {
                owner: P0,
                kind: BuildingKind::Refinery,
                x: 8,
                y: 2,
            }],
            &[],
        ];
        for cmds in script {
            a.step(cmds);
            b.step(cmds);
            assert_eq!(a.state_hash(), b.state_hash());
        }
        // and they keep agreeing for a while
        for _ in 0..50 {
            a.step(&[]);
            b.step(&[]);
            assert_eq!(a.state_hash(), b.state_hash());
        }
    }

    #[test]
    fn ai_builds_up_its_economy_and_army() {
        let mut s = Sim::new(Map::new(32, 32), 1, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        for _ in 0..400 {
            let cmds = s.ai_commands(P0);
            s.step(&cmds);
        }
        // It should have expanded its base and trained at least one unit.
        assert!(s.unit_count(P0) >= 1);
        assert!(s.entity_count() >= 4); // CC + power + refinery + barracks (+ units)
    }

    fn run_ai_vs_ai(seed: u64) -> Vec<u64> {
        let mut s = Sim::new(Map::new(40, 40), seed, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        s.add_building(P1, BuildingKind::CommandCenter, 35, 35);
        let mut hashes = Vec::new();
        for _ in 0..300 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            hashes.push(s.state_hash());
        }
        hashes
    }

    #[test]
    fn ai_vs_ai_is_deterministic() {
        assert_eq!(run_ai_vs_ai(7), run_ai_vs_ai(7));
    }

    /// Builds a 1-D corridor: a P0 Infantry at x=5, a P1 Infantry "ambush" at
    /// x=10, both on row 5, with a far destination at x=20. Both combatants get a
    /// huge HP pool so neither dies inside the test window — the assertions key on
    /// POSITION (did the attacker stop?) and on the enemy taking *some* damage.
    fn corridor() -> (Sim, EntityId, EntityId, Vec2) {
        let mut s = Sim::new(Map::new(30, 12), 1, f(0));
        let atk = s.add_unit(P0, UnitKind::Infantry, v(5, 5));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(10, 5));
        // Survive the whole window so the test measures behavior, not lethality.
        s.entities[atk.0 as usize].hp = f(100_000);
        s.entities[foe.0 as usize].hp = f(100_000);
        (s, atk, foe, v(20, 5))
    }

    #[test]
    fn attack_move_units_stop_to_fight() {
        // An AttackMove order PAST an enemy must make the unit halt at the enemy
        // (engagement range) and damage it — NOT walk on to the far destination.
        let (mut s, atk, foe, dest) = corridor();
        let foe_full = s.entities[foe.0 as usize].hp;
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: atk,
            target: dest,
        }]);
        for _ in 0..200 {
            s.step(&[]);
        }
        let atk_x = s.entities[atk.0 as usize].pos.x;
        // Halted well short of the destination (x=20): it stopped to fight, so it
        // never crossed the enemy at x=10.
        assert!(
            atk_x < f(11),
            "attack-mover should halt near the enemy (~x<=10), got x-bits={}",
            atk_x.to_bits()
        );
        // Still carrying the unreached order (move_target set, stance still armed).
        assert!(
            s.entities[atk.0 as usize].move_target.is_some(),
            "the unmet move order must persist while standing to fight"
        );
        assert!(
            s.entities[atk.0 as usize].attack_move,
            "the attack-move stance must stay armed until the destination is reached"
        );
        // And it actually fought: the enemy bled.
        assert!(
            s.entities[foe.0 as usize].hp < foe_full,
            "the halted attack-mover must deal damage to the enemy it stopped for"
        );
    }

    #[test]
    fn plain_move_ignores_enemies() {
        // The control: a plain Move with the SAME geometry marches straight to the
        // far destination, never stopping for the enemy on the way.
        let (mut s, atk, _foe, dest) = corridor();
        s.step(&[Command::Move {
            owner: P0,
            unit: atk,
            target: dest,
        }]);
        // A plain move never sets the attack-move stance.
        assert!(
            !s.entities[atk.0 as usize].attack_move,
            "plain Move must not arm the attack-move stance"
        );
        for _ in 0..400 {
            s.step(&[]);
        }
        // Reached the destination: move_target cleared (arrival) and x is at x=20.
        assert!(
            s.entities[atk.0 as usize].move_target.is_none(),
            "a plain Move must reach the destination and clear its order"
        );
        let atk_x = s.entities[atk.0 as usize].pos.x;
        assert!(
            atk_x > f(19),
            "a plain Move must reach the far destination (~x=20), got x-bits={}",
            atk_x.to_bits()
        );
    }

    #[test]
    fn golden_hash_pins_cross_target_determinism() {
        // A fixed scripted AI-vs-AI run. This constant must be byte-identical on
        // every target — native, wasm, mobile, server. A mismatch when this test
        // is run on another platform is a determinism regression, full stop.
        let mut s = Sim::new(Map::new(40, 40), 12_345, f(1500));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        for _ in 0..120 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
        }
        // Re-pinned for F5 (Migration J): `researched_techs` is now a 500-slot
        // `TechBitset` hashed as eight u64 words, and the AI researches the live
        // grid (era keys + real unlocks first), so its golden-run research cadence
        // and hashed state both shift.
        //
        // Re-pinned again for M7 (sector arena): the state hash now appends the
        // sector (governance) arena. This run has no sectors, so the only delta is
        // two appended zero-length markers (`sectors.len()` + `sector_free.len()`);
        // the simulation itself is unchanged.
        //
        // Re-pinned for planetary territory: state hash now appends each civ's `alive`
        // byte and the planets arena (this run has no planets -> one zero-length marker).
        //
        // Re-pinned for decisive planet-free RTS AI: idle armies now issue
        // AttackMove rather than plain Move. This changes both the stance byte and
        // the scripted battle outcome while remaining bit-identical across runs and
        // targets; it fixes symmetric Open Front matches stalling indefinitely.
        //
        // Re-pinned for the ore economy: each entity now appends cargo and
        // return-trip state. This short run creates no Harvester, so the two
        // zero-valued fields are the only simulation-state delta.
        // Re-pinned again when producer rally destinations were appended to the
        // entity hash; this script sets no rally point, so only the explicit
        // absent marker changes the fingerprint.
        // Re-pinned for authoritative structure construction. Entity hashes now
        // include remaining/total build ticks, and the scripted AI opening has
        // real build delays before new economy and production structures activate.
        //
        // GOLDEN-NEUTRAL for distance-decayed combat (supply-line damage falloff):
        // a unit's outgoing damage now decays with its distance from the owner's
        // nearest Command Center. This 120-tick scripted run never fields a unit
        // that fires while > SUPPLY_FULL_RADIUS (6 tiles) from its CC — the CCs sit
        // 25 tiles apart and the economy/research opening hasn't pushed armies into
        // each other's deep field yet — so the supply factor is a flat 1 throughout
        // and the hash is unchanged (verified: zero decayed-fire events in this run).
        // The feature is exercised by `combat_decays_with_distance_from_command_center`
        // and `combat_full_strength_within_full_radius`.
        assert_eq!(s.state_hash(), 2_081_234_273_307_305_018);
    }

    /// Reachability invariant: every grid node's per-resource cost must fit under
    /// its stockpile cap, or that node can NEVER be accumulated and is dead
    /// content. Research charges Money (uncapped), Energy (`ENERGY_CAP`) and
    /// Labour (`LABOUR_CAP`) from the SAME `node.energy`/`node.labour` fields the
    /// charging path reads (see `apply_research`). This guards the cap-vs-cost
    /// invariant forever — if a future cost edit (or a cap cut) breaks it, this
    /// fails instead of silently bricking the back half of the tech grid.
    #[test]
    fn every_grid_node_is_affordable() {
        use super::{ENERGY_CAP, LABOUR_CAP};
        for node in &crate::game::tech_grid_table::GRID {
            let energy = Fixed::from_int(i32::try_from(node.energy).unwrap());
            let labour = Fixed::from_int(i32::try_from(node.labour).unwrap());
            assert!(
                energy <= ENERGY_CAP,
                "node {} ({}) energy cost {} exceeds ENERGY_CAP — unresearchable",
                node.id,
                node.name,
                node.energy,
            );
            assert!(
                labour <= LABOUR_CAP,
                "node {} ({}) labour cost {} exceeds LABOUR_CAP — unresearchable",
                node.id,
                node.name,
                node.labour,
            );
        }
    }

    /// Era-key nodes gate era advancement: if a key is unaffordable, that era and
    /// everything past it (including the Capital ship) is permanently unreachable.
    /// Pin the strongest version of the invariant on exactly the gating nodes.
    #[test]
    fn era_key_nodes_are_affordable() {
        use super::{ENERGY_CAP, LABOUR_CAP};
        for &key in &crate::game::tech_grid::ERA_KEYS {
            let node = crate::game::tech_grid::node(key).expect("era key in range");
            let energy = Fixed::from_int(i32::try_from(node.energy).unwrap());
            let labour = Fixed::from_int(i32::try_from(node.labour).unwrap());
            assert!(
                energy <= ENERGY_CAP && labour <= LABOUR_CAP,
                "era-key node {} ({}) unaffordable: energy {} (cap {ENERGY_CAP:?}), labour {} (cap {LABOUR_CAP:?})",
                node.id,
                node.name,
                node.energy,
                node.labour,
            );
        }
    }

    #[test]
    fn colony_growth_fields_hash_is_stable_and_golden_neutral() {
        fn build() -> Sim {
            let mut s = Sim::new(Map::new(12, 12), 4, f(100));
            let cc = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
            s.add_colony(P0, cc, 0);
            s
        }
        assert_eq!(build().state_hash(), build().state_hash());
    }

    #[test]
    fn planets_and_alive_hash_is_stable() {
        fn run() -> u64 {
            // Exercise the new hashed state without behavior wiring (Task 3 is
            // data-only): two identical constructions must hash-equal.
            let s = Sim::with_civ_count(Map::new(20, 20), 5, f(1500), 2);
            s.state_hash()
        }
        assert_eq!(run(), run());
    }

    #[test]
    fn six_civ_game_is_deterministic() {
        fn run() -> u64 {
            let mut s = Sim::with_civ_count(Map::new(40, 40), 999, f(1500), 6);
            for id in 0..6u16 {
                s.add_building(PlayerId(id), BuildingKind::CommandCenter, 3 + id * 5, 20);
            }
            for _ in 0..60 {
                let cmds: Vec<Command> = (1..6u16)
                    .flat_map(|id| s.ai_commands(PlayerId(id)))
                    .collect();
                s.step(&cmds);
            }
            s.state_hash()
        }
        assert_eq!(
            run(),
            run(),
            "six-civ run must be bit-identical across runs"
        );
    }

    // ---- M0: autonomous colony prototype ----

    #[test]
    fn full_autonomy_colony_drives_its_owner_like_the_ai() {
        // "Automated at maturity": a colony at full autonomy must emit exactly the
        // commands the proven pure AI brain would emit for its owner.
        let mut s = Sim::new(Map::new(40, 40), 12_345, f(1500));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        // The colony must first EARN full autonomy (one level per 120 ticks); run
        // well past 9*120 so its effective level reaches the cap, at which point no
        // command category is filtered and it delegates wholesale to the AI brain.
        for _ in 0..1100 {
            let mut cmds = s.colony_commands();
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
        }
        let via_colony = format!("{:?}", s.colony_commands());
        let via_ai = format!("{:?}", s.ai_commands(P0));
        assert_eq!(via_colony, via_ai);
    }

    #[test]
    fn manual_colony_emits_no_commands() {
        // "Manual at birth": an autonomy-0 colony never acts on its own.
        let mut s = Sim::new(Map::new(40, 40), 7, f(1500));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_colony(P0, cc, 0);
        // Even after the economy has banked plenty, it stays silent.
        for _ in 0..50 {
            assert!(s.colony_commands().is_empty());
            s.step(&[]);
        }
    }

    #[test]
    fn autonomous_colony_run_is_deterministic() {
        // The colony layer is a pure function of hashed state: two identical runs
        // produce a bit-identical hash (the lockstep/replay guarantee).
        fn run() -> u64 {
            let mut s = Sim::new(Map::new(40, 40), 99, f(1500));
            let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
            s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
            s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
            for _ in 0..200 {
                let mut cmds = s.colony_commands();
                cmds.extend(s.ai_commands(P1));
                s.step(&cmds);
            }
            s.state_hash()
        }
        assert_eq!(run(), run());
    }

    // ---- M3: policy + earned-autonomy gradient ----

    #[test]
    fn autonomy_is_earned_over_time() {
        use crate::game::civ::AUTONOMY_HOLD_TICKS;
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 10);
        let col = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        // Freshly founded: requested 9 but earned 0 ⇒ acts at 0 (silent).
        assert!(s.colony_commands().is_empty());
        // After two hold windows it has earned level 2 (Build unlocked).
        for _ in 0..=(AUTONOMY_HOLD_TICKS * 2) {
            s.step(&[]);
        }
        assert_eq!(s.colony(col).unwrap().earned_autonomy(), 2);
    }

    #[test]
    fn requested_autonomy_caps_the_effective_level() {
        use crate::game::civ::AUTONOMY_HOLD_TICKS;
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 10);
        let col = s.add_colony(P0, cc, 1); // request only level 1
        for _ in 0..(AUTONOMY_HOLD_TICKS * 5) {
            s.step(&[]);
        }
        // Earned 5, but requested 1 ⇒ effective is capped at 1.
        assert_eq!(s.colony(col).unwrap().earned_autonomy(), 5);
        assert_eq!(s.colony(col).unwrap().effective_autonomy(), 1);
    }

    #[test]
    fn hold_directive_freezes_a_colony() {
        use crate::game::civ::{ColonyIntent, AUTONOMY_HOLD_TICKS};
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 10);
        let col = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        for _ in 0..(AUTONOMY_HOLD_TICKS * 10) {
            s.step(&[]);
        }
        assert!(!s.colony_commands().is_empty(), "earned colony acts");
        s.step(&[Command::DirectColony {
            owner: P0,
            colony: col,
            intent: ColonyIntent::Hold,
        }]);
        assert!(
            s.colony_commands().is_empty(),
            "a Hold directive freezes autonomous action"
        );
    }

    #[test]
    fn set_policy_and_autonomy_commands_apply() {
        use crate::game::civ::{ColonyPolicy, MilitaryIntent};
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 10);
        let col = s.add_colony(P0, cc, 0);
        s.step(&[Command::SetColonyAutonomy {
            owner: P0,
            colony: col,
            level: 4,
        }]);
        assert_eq!(s.colony(col).unwrap().autonomy_level, 4);
        let policy = ColonyPolicy {
            military: MilitaryIntent::Conquest,
            ..ColonyPolicy::default()
        };
        s.step(&[Command::SetColonyPolicy {
            owner: P0,
            colony: col,
            policy,
        }]);
        assert_eq!(
            s.colony(col).unwrap().policy.military,
            MilitaryIntent::Conquest
        );
        // A non-owner cannot reconfigure it.
        s.step(&[Command::SetColonyAutonomy {
            owner: P1,
            colony: col,
            level: 9,
        }]);
        assert_eq!(s.colony(col).unwrap().autonomy_level, 4);
    }

    // ---- M9: Kardashev tier + empire-scaled wave pressure ----

    #[test]
    fn kardashev_tier_climbs_with_empire_size() {
        use crate::game::civ::KardashevTier;
        let mut s = Sim::new(Map::new(64, 24), 1, f(50_000));
        // No colonies yet ⇒ Planetary.
        assert_eq!(s.kardashev_tier(P0), KardashevTier::Planetary);
        // Found colonies and watch the tier rise.
        let mut x = 4;
        for _ in 0..6 {
            let cc = s.add_building(P0, BuildingKind::CommandCenter, x, 12);
            s.add_colony(P0, cc, 0);
            x += 8;
        }
        // 6 colonies ⇒ Galactic.
        assert_eq!(s.kardashev_tier(P0), KardashevTier::Galactic);
    }

    #[test]
    fn waves_scale_with_the_defenders_empire() {
        // A wave's size grows with how many colonies the defender holds.
        fn first_wave_attackers(colonies: usize) -> usize {
            let mut s = Sim::new(Map::new(40, 20), 1, f(50_000));
            s.add_building(P0, BuildingKind::CommandCenter, 3, 10);
            // Give P0 (the defender) some colonies seated on extra CommandCenters.
            let mut x = 8;
            for _ in 0..colonies {
                let cc = s.add_building(P0, BuildingKind::CommandCenter, x, 10);
                s.add_colony(P0, cc, 0);
                x += 4;
            }
            s.set_waves(WaveConfig {
                first_delay: 0,
                interval: 100,
                base_size: 3,
                growth: 0,
                spawn: v(36, 10),
                unit: UnitKind::Infantry,
                attacker: P1,
                defender: P0,
                escalate: false,
            });
            s.step(&[]); // first wave fires at t=0
            s.unit_count(P1)
        }
        let small = first_wave_attackers(0);
        let big = first_wave_attackers(3);
        assert_eq!(small, 3, "0 colonies ⇒ base wave size");
        assert!(big > small, "a larger empire draws a larger siege");
    }

    // ---- M7: sector governance + LOD ----

    #[test]
    fn colony_lod_is_state_driven_and_deterministic() {
        use crate::game::civ::{SimDetail, AUTONOMY_HOLD_TICKS};
        // A young colony is Active; a mature, unthreatened one goes Dormant. Mature
        // now means population at cap AND full autonomy (rule D3), so seat the colony
        // on a fertile planet that lets its population grow to cap.
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        fertile_planet_around(&mut s, 5, 5);
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
        let col = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        s.step(&[]);
        assert_eq!(s.colony(col).unwrap().detail, SimDetail::Active);
        for _ in 0..(AUTONOMY_HOLD_TICKS * 10) {
            s.step(&[]);
        }
        assert_eq!(
            s.colony(col).unwrap().detail,
            SimDetail::Dormant,
            "a mature, quiet colony drops to Dormant"
        );
    }

    #[test]
    fn dormant_requires_maturity_not_just_autonomy() {
        use crate::game::civ::{SimDetail, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS};
        let mut s = Sim::new(Map::new(8, 8), 1, f(0));
        let pid = PlanetId(0);
        for y in 0..2 {
            for x in 0..2 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
        s.push_planet(Planet {
            owner: Some(P0),
            seat: Some(cc),
            center: tile_center(0, 0),
            radius: f(2),
        });
        let id = s.add_colony(P0, cc, AUTONOMY_FULL); // requested full autonomy, but population 1 < cap
        s.rebuild_planet_yield();
        // Step long enough for earned_autonomy to reach AUTONOMY_FULL (it rises one
        // step per Active tick; full needs AUTONOMY_HOLD_TICKS·(FULL+1) ticks). The
        // planet is all-Barren so food rate is 0 and population stays at 1 < cap, i.e.
        // the colony is immature. Under the OLD rule it would now be Dormant
        // (earned autonomy full); under the new D3 rule it must stay Active — so this
        // loop count makes the test fail pre-fix and pass post-fix.
        for _ in 0..(AUTONOMY_HOLD_TICKS * (u32::from(AUTONOMY_FULL) + 1)) {
            s.step(&[]); // run_lod recomputes detail
        }
        assert_eq!(
            s.colony(id).unwrap().detail,
            SimDetail::Active,
            "an autonomy-full but immature colony must stay Active, not Dormant"
        );
    }

    #[test]
    fn colony_goes_tactical_under_threat() {
        use crate::game::civ::SimDetail;
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
        let col = s.add_colony(P0, cc, 0);
        // Drop an enemy unit right next to the colony seat.
        s.add_unit(P1, UnitKind::Infantry, v(5, 6));
        s.step(&[]);
        assert_eq!(
            s.colony(col).unwrap().detail,
            SimDetail::Tactical,
            "an enemy beside the seat forces Tactical detail"
        );
    }

    #[test]
    fn lod_classification_does_not_perturb_results() {
        // Detail is a hint: a colonied run is bit-identical across two passes,
        // proving LOD classification is deterministic and side-effect-free.
        fn run() -> u64 {
            let mut s = Sim::new(Map::new(30, 30), 9, f(5000));
            let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
            s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
            s.add_building(P1, BuildingKind::CommandCenter, 24, 24);
            for _ in 0..400 {
                let mut cmds = s.colony_commands();
                cmds.extend(s.ai_commands(P1));
                s.step(&cmds);
            }
            s.state_hash()
        }
        assert_eq!(run(), run());
    }

    #[test]
    fn assigning_a_colony_to_a_sector_sets_its_doctrine() {
        use crate::game::civ::{SectorDoctrine, SectorId};
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
        let col = s.add_colony(P0, cc, 0);
        // Ungoverned colonies report the Balanced default.
        assert_eq!(s.colony_doctrine(col), SectorDoctrine::Balanced);
        s.step(&[Command::FoundSector {
            owner: P0,
            doctrine: SectorDoctrine::Fortress,
        }]);
        s.step(&[Command::AssignColonyToSector {
            owner: P0,
            colony: col,
            sector: SectorId(0),
        }]);
        assert_eq!(s.colony_doctrine(col), SectorDoctrine::Fortress);
        // A foreign owner cannot poach the colony into its sector.
        s.step(&[Command::AssignColonyToSector {
            owner: P1,
            colony: col,
            sector: SectorId(0),
        }]);
        assert_eq!(s.colony(col).unwrap().sector, Some(SectorId(0)));
    }

    #[test]
    fn a_sector_governs_its_member_colonies_policy() {
        use crate::game::civ::{SectorDoctrine, SectorId};
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        let cc1 = s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        let cc2 = s.add_building(P0, BuildingKind::CommandCenter, 20, 20);
        let c1 = s.add_colony(P0, cc1, 0);
        let c2 = s.add_colony(P0, cc2, 0);
        s.step(&[Command::FoundSector {
            owner: P0,
            doctrine: SectorDoctrine::Fortress,
        }]);
        s.step(&[
            Command::AssignColonyToSector {
                owner: P0,
                colony: c1,
                sector: SectorId(0),
            },
            Command::AssignColonyToSector {
                owner: P0,
                colony: c2,
                sector: SectorId(0),
            },
        ]);
        // The sector pushes its doctrine policy onto both members.
        let target = SectorDoctrine::Fortress.policy();
        for _ in 0..3 {
            let cmds = s.sector_commands();
            s.step(&cmds);
        }
        assert_eq!(s.colony(c1).unwrap().policy, target);
        assert_eq!(s.colony(c2).unwrap().policy, target);
        // Idempotent: once synced, the sector emits nothing further.
        assert!(
            s.sector_commands().is_empty(),
            "a synced sector issues no governance commands"
        );
    }

    #[test]
    fn changing_a_sectors_doctrine_repropagates_to_members() {
        use crate::game::civ::{SectorDoctrine, SectorId};
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        let col = s.add_colony(P0, cc, 0);
        s.step(&[Command::FoundSector {
            owner: P0,
            doctrine: SectorDoctrine::Fortress,
        }]);
        s.step(&[Command::AssignColonyToSector {
            owner: P0,
            colony: col,
            sector: SectorId(0),
        }]);
        for _ in 0..2 {
            let cmds = s.sector_commands();
            s.step(&cmds);
        }
        assert_eq!(
            s.colony(col).unwrap().policy,
            SectorDoctrine::Fortress.policy()
        );
        // Re-doctrine the sector: the member converges on the new policy.
        s.step(&[Command::SetSectorDoctrine {
            owner: P0,
            sector: SectorId(0),
            doctrine: SectorDoctrine::Research,
        }]);
        for _ in 0..2 {
            let cmds = s.sector_commands();
            s.step(&cmds);
        }
        assert_eq!(
            s.colony(col).unwrap().policy,
            SectorDoctrine::Research.policy()
        );
    }

    #[test]
    fn sector_slots_are_recycled_lifo() {
        use crate::game::civ::{SectorDoctrine, SectorId};
        let mut s = Sim::new(Map::new(10, 10), 1, f(5000));
        let a = s.add_sector(P0, SectorDoctrine::Mining);
        let b = s.add_sector(P0, SectorDoctrine::Fortress);
        assert_eq!((a, b), (SectorId(0), SectorId(1)));
        s.free_sector(a);
        // The freed slot is reused before the vector grows (LIFO, rule D5).
        let c = s.add_sector(P0, SectorDoctrine::Research);
        assert_eq!(c, SectorId(0));
        assert_eq!(
            s.sector(SectorId(0)).unwrap().doctrine,
            SectorDoctrine::Research
        );
        assert!(s.sector(b).is_some());
    }

    #[test]
    fn govern_colony_reuses_or_founds_a_sector() {
        use crate::game::civ::SectorDoctrine;
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        let cc1 = s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        let cc2 = s.add_building(P0, BuildingKind::CommandCenter, 20, 20);
        let c1 = s.add_colony(P0, cc1, 0);
        let c2 = s.add_colony(P0, cc2, 0);
        // Governing two colonies with the same doctrine groups them in ONE sector.
        s.step(&[
            Command::GovernColony {
                owner: P0,
                colony: c1,
                doctrine: SectorDoctrine::Fortress,
            },
            Command::GovernColony {
                owner: P0,
                colony: c2,
                doctrine: SectorDoctrine::Fortress,
            },
        ]);
        assert_eq!(s.colony_doctrine(c1), SectorDoctrine::Fortress);
        assert_eq!(s.colony_doctrine(c2), SectorDoctrine::Fortress);
        assert_eq!(s.colony(c1).unwrap().sector, s.colony(c2).unwrap().sector);
        assert_eq!(
            s.sectors_len(),
            1,
            "the second govern reused the first sector"
        );
        // A different doctrine founds a second sector and moves the colony into it.
        s.step(&[Command::GovernColony {
            owner: P0,
            colony: c1,
            doctrine: SectorDoctrine::Research,
        }]);
        assert_eq!(s.colony_doctrine(c1), SectorDoctrine::Research);
        assert_eq!(s.colony_doctrine(c2), SectorDoctrine::Fortress);
        assert_eq!(s.sectors_len(), 2);
    }

    #[test]
    fn disbanding_a_sector_unassigns_its_colonies() {
        use crate::game::civ::{SectorDoctrine, SectorId};
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
        let col = s.add_colony(P0, cc, 0);
        let sec = s.add_sector(P0, SectorDoctrine::Fortress);
        s.step(&[Command::AssignColonyToSector {
            owner: P0,
            colony: col,
            sector: sec,
        }]);
        assert_eq!(s.colony(col).unwrap().sector, Some(SectorId(0)));
        s.free_sector(sec);
        assert_eq!(s.colony(col).unwrap().sector, None);
        assert_eq!(s.colony_doctrine(col), SectorDoctrine::Balanced);
    }

    /// Registers a small fertile planet covering the 3×3 block around (cx, cy) and
    /// returns its id. A colony seated on it accrues food and grows to its
    /// population cap, so it can become *mature* — the precondition for Dormant
    /// under rule D3. Rebuilds the planet-yield cache before returning, so the
    /// colony's food/output rates are live from its first `step`.
    fn fertile_planet_around(s: &mut Sim, cx: u16, cy: u16) -> PlanetId {
        let pid = s.push_planet(Planet {
            owner: Some(P0),
            seat: None,
            center: tile_center(cx, cy),
            radius: f(2),
        });
        for x in cx.saturating_sub(1)..=cx.saturating_add(1) {
            for y in cy.saturating_sub(1)..=cy.saturating_add(1) {
                s.map_mut().set_planet(x, y, pid);
                s.map_mut().set_terrain(x, y, TerrainKind::Fertile);
            }
        }
        s.rebuild_planet_yield();
        pid
    }

    // ---- M7 (cont.): Dormant closed-form work-skip ----

    /// Scans a small region for a tile whose static `SolarFlux` field is non-zero,
    /// so a colony seated there actually accrues a stockpile (exercising the
    /// stockpile closed-form, not just autonomy progress).
    fn nonzero_flux_tile(seed: u64) -> (u16, u16) {
        use crate::game::civ::special::{field_intensity, SpecialKind};
        for y in 0..20u16 {
            for x in 0..20u16 {
                if field_intensity(seed, x, y, SpecialKind::SolarFlux).to_bits() > 0 {
                    return (x, y);
                }
            }
        }
        panic!("no non-zero SolarFlux tile found for seed {seed}");
    }

    #[test]
    fn dormant_colonies_skip_their_per_tick_work() {
        use crate::game::civ::{SimDetail, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS};
        let mut s = Sim::new(Map::new(30, 30), 1, f(5000));
        fertile_planet_around(&mut s, 5, 5);
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 5);
        let col = s.add_colony(P0, cc, AUTONOMY_FULL);
        // Run until the mature, unthreatened colony drops to Dormant, then keep
        // stepping so several ticks pass without it being materialized.
        for _ in 0..(AUTONOMY_HOLD_TICKS * 10 + 50) {
            s.step(&[]);
        }
        let c = s.colony(col).unwrap();
        assert_eq!(c.detail, SimDetail::Dormant);
        // The skip leaves the colony's sync clock behind the world clock by
        // exactly the number of ticks its per-tick passes were skipped.
        assert!(
            c.last_sync_tick < s.tick,
            "a Dormant colony's sync clock must lag the world clock (sync={}, tick={})",
            c.last_sync_tick,
            s.tick
        );
    }

    #[test]
    fn dormant_closed_form_matches_full_simulation_every_tick() {
        use crate::game::civ::special::SpecialKind;
        use crate::game::civ::{SimDetail, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS};
        // Two identical worlds: one skips Dormant colonies' per-tick passes and
        // catches them up in closed form; the other runs every colony at full
        // fidelity every tick. Their state hashes must agree on EVERY tick
        // (determinism rule D3) — the closed-form accumulation is exact.
        let seed = 7;
        let (sx, sy) = nonzero_flux_tile(seed);
        let build = || {
            let mut s = Sim::new(Map::new(30, 30), seed, f(5000));
            fertile_planet_around(&mut s, sx, sy);
            let cc = s.add_building(P0, BuildingKind::CommandCenter, sx, sy);
            let col = s.add_colony(P0, cc, AUTONOMY_FULL);
            // Make the Field special extractable so the stockpile keeps accruing
            // while the colony is Dormant.
            s.step(&[Command::SurveySpecial {
                owner: P0,
                colony: col,
                kind: SpecialKind::SolarFlux,
            }]);
            s
        };
        let mut skip = build();
        let mut full = build();
        full.lod_skip = false;
        for _ in 0..(AUTONOMY_HOLD_TICKS * 10 + 200) {
            skip.step(&[]);
            full.step(&[]);
            assert_eq!(
                skip.state_hash(),
                full.state_hash(),
                "closed-form Dormant skip diverged from full simulation at tick {}",
                skip.tick
            );
        }
        // Confirm the test actually drove the colony Dormant and accrued a stock.
        let c = skip.colony(ColonyId(0)).unwrap();
        assert_eq!(c.detail, SimDetail::Dormant, "the colony should be Dormant");
        assert!(
            c.stockpile[SpecialKind::SolarFlux.index()].to_bits() > 0,
            "the Dormant colony should have accrued a SolarFlux stockpile"
        );
    }

    #[test]
    fn waking_a_dormant_colony_recovers_the_full_active_value() {
        use crate::game::civ::special::SpecialKind;
        use crate::game::civ::{SimDetail, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS};
        // Demote(skip)∘promote(wake) == identity (determinism rule D2): a colony
        // that skipped work while Dormant, then woke, holds the exact same
        // accumulators as one that never skipped.
        let seed = 11;
        let (sx, sy) = nonzero_flux_tile(seed);
        let build = |skip: bool| {
            let mut s = Sim::new(Map::new(30, 30), seed, f(5000));
            s.lod_skip = skip;
            fertile_planet_around(&mut s, sx, sy);
            let cc = s.add_building(P0, BuildingKind::CommandCenter, sx, sy);
            let col = s.add_colony(P0, cc, AUTONOMY_FULL);
            s.step(&[Command::SurveySpecial {
                owner: P0,
                colony: col,
                kind: SpecialKind::SolarFlux,
            }]);
            (s, col)
        };
        let (mut skip, c1) = build(true);
        let (mut full, c2) = build(false);
        for _ in 0..(AUTONOMY_HOLD_TICKS * 10 + 100) {
            skip.step(&[]);
            full.step(&[]);
        }
        assert_eq!(skip.colony(c1).unwrap().detail, SimDetail::Dormant);
        // Park an enemy beside each seat to force the colony awake, then let the
        // wake tick land (detail flips this step; the catch-up runs next step).
        skip.add_unit(P1, UnitKind::Infantry, v(i32::from(sx), i32::from(sy) + 1));
        full.add_unit(P1, UnitKind::Infantry, v(i32::from(sx), i32::from(sy) + 1));
        skip.step(&[]);
        full.step(&[]);
        skip.step(&[]);
        full.step(&[]);
        let a = skip.colony(c1).unwrap();
        let b = full.colony(c2).unwrap();
        assert_eq!(
            a.autonomy_progress, b.autonomy_progress,
            "woken colony's autonomy progress must equal the never-skipped value"
        );
        assert_eq!(
            a.stockpile, b.stockpile,
            "woken colony's stockpile must equal the never-skipped value"
        );
        assert_eq!(
            a.last_sync_tick, b.last_sync_tick,
            "waking fully materializes the colony's sync clock"
        );
    }

    /// Paints every planet tile in a [`scenario::conquest`] world Fertile so the
    /// seated colonies actually grow to their population cap, mature, and go
    /// Dormant during a long run — the precondition for the skip path to engage.
    /// (The default conquest planets are Barren ⇒ zero food ⇒ population pinned at
    /// 1 ⇒ never mature ⇒ the skip path would never fire, making the oracle below
    /// vacuous.) Rebuilds the planet-yield cache so the new rates are live.
    fn fertilize_all_planets(s: &mut Sim) {
        let (w, h) = (s.map().width(), s.map().height());
        for y in 0..h {
            for x in 0..w {
                if s.map().planet_at(i32::from(x), i32::from(y)).is_some() {
                    s.map_mut().set_terrain(x, y, TerrainKind::Fertile);
                }
            }
        }
        s.rebuild_planet_yield();
    }

    #[test]
    fn lod_skip_matches_full_with_growing_and_mature_colonies() {
        use crate::game::civ::SimDetail;
        use crate::game::scenario;
        // Strongest D3 oracle: a real multi-civ conquest world (planets + colonies)
        // run for 1500 ticks with the Dormant-skip path ON vs OFF must produce the
        // SAME state hash on every tick. This proves treasury + population growth +
        // autonomy + stockpile all reconstruct exactly whether or not Dormant
        // colonies skip their per-tick passes.
        let run = |lod_skip: bool| {
            let mut s = scenario::conquest(2024, 3);
            // Make the colonies maturable so the skip path actually engages.
            fertilize_all_planets(&mut s);
            s.lod_skip = lod_skip;
            let mut hashes = alloc::vec::Vec::new();
            let mut ever_dormant = false;
            for _ in 0..1500 {
                let cmds: alloc::vec::Vec<Command> = (0..3u16)
                    .filter(|&i| s.civ_alive(PlayerId(i)))
                    .flat_map(|i| s.ai_commands(PlayerId(i)))
                    .collect();
                s.step(&cmds);
                for ci in 0..s.colonies_len() {
                    let id = ColonyId(u32::try_from(ci).unwrap_or(u32::MAX));
                    if s.colony(id).map(|c| c.detail) == Some(SimDetail::Dormant) {
                        ever_dormant = true;
                    }
                }
                hashes.push(s.state_hash());
            }
            (hashes, ever_dormant)
        };
        let (skip_hashes, skip_dormant) = run(true);
        let (full_hashes, _) = run(false);
        // Guard against a vacuous pass: at least one colony must have gone Dormant
        // on the skip run, otherwise the skip path was never exercised.
        assert!(
            skip_dormant,
            "no colony reached Dormant — the skip path was never exercised, oracle is vacuous"
        );
        // Pinpoint the first diverging tick if they disagree (a real D3 bug).
        if let Some(tick) = skip_hashes
            .iter()
            .zip(full_hashes.iter())
            .position(|(a, b)| a != b)
        {
            panic!(
                "skip path diverged from full path at tick index {tick}: skip={} full={}",
                skip_hashes[tick], full_hashes[tick]
            );
        }
        assert_eq!(
            skip_hashes, full_hashes,
            "skip path must match full path every tick"
        );
    }

    #[test]
    fn mature_colony_treasury_wakes_to_exact_value() {
        use crate::game::civ::{SimDetail, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS};
        // A single colony forced to maturity on Fertile terrain: after it has gone
        // Dormant for thousands of ticks and is then WOKEN, its banked treasury must
        // be byte-equal to one that was simulated at full fidelity the whole time.
        // This proves the closed-form wake (materialize_colony's `stored + rate·elapsed`)
        // recovers exactly the value the never-skipped accrual produces — the treasury
        // analogue of the C5 `waking_a_dormant_colony_recovers_the_full_active_value`
        // test (mirroring its enemy-park wake protocol below).
        //
        // NB: a Dormant colony's STORED `treasury` field deliberately lags by design
        // (the per-tick banking is skipped; the logical value is reconstructed in the
        // hash and only materialized on wake). So we must wake the skip colony before
        // reading the field — reading it mid-Dormancy would compare the lazy lagging
        // value against the eager one, which is expected to differ.
        let seed = 7;
        let (sx, sy) = nonzero_flux_tile(seed);
        let treasury_after = |lod_skip: bool, ticks: usize| -> [Fixed; 3] {
            let mut s = Sim::new(Map::new(30, 30), seed, f(5000));
            fertile_planet_around(&mut s, sx, sy);
            let cc = s.add_building(P0, BuildingKind::CommandCenter, sx, sy);
            let col = s.add_colony(P0, cc, AUTONOMY_FULL);
            s.lod_skip = lod_skip;
            for _ in 0..ticks {
                s.step(&[]);
            }
            // The colony must actually have matured and gone Dormant for this to test
            // the closed-form wake rather than the always-Active path.
            assert_eq!(
                s.colony(col).unwrap().detail,
                SimDetail::Dormant,
                "colony should be mature/Dormant after {ticks} ticks"
            );
            // Wake it: park an enemy beside the seat (flips detail to Tactical), let the
            // wake tick land, then a second step runs the catch-up that banks treasury.
            s.add_unit(P1, UnitKind::Infantry, v(i32::from(sx), i32::from(sy) + 1));
            s.step(&[]);
            s.step(&[]);
            s.colony(col).unwrap().treasury
        };
        // Long enough that the colony is mature and has banked treasury for a while.
        let n = AUTONOMY_HOLD_TICKS as usize * 10 + 3000;
        let banked = treasury_after(true, n);
        assert!(
            banked.iter().any(|t| t.to_bits() != 0),
            "test must actually bank nonzero treasury to be meaningful"
        );
        assert_eq!(
            banked,
            treasury_after(false, n),
            "mature colony treasury must be identical whether Dormant-skipped or fully simulated"
        );
    }

    // ---- M6: species biases + emergent conflict ----

    #[test]
    fn species_bias_expansion_drive() {
        use crate::game::civ::Species;
        // Swarm is pushier and sprawls wider than the Ancients.
        assert!(Species::Swarm.expand_period() < Species::Ancient.expand_period());
        assert!(Species::Swarm.colony_cap() > Species::Ancient.colony_cap());
        assert_eq!(Species::Standard.colony_cap(), 4);
    }

    #[test]
    fn species_caps_expansion_per_archetype() {
        use crate::game::civ::{ColonyPolicy, ExpansionIntent, Species};
        // An Ancient colony stops at its low colony cap even with room + money.
        let mut s = Sim::new(Map::new(48, 48), 1, f(1_000_000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
        let col = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        s.set_colony_species(col, Species::Ancient);
        s.step(&[Command::SetColonyPolicy {
            owner: P0,
            colony: col,
            policy: ColonyPolicy {
                expansion: ExpansionIntent::Aggressive,
                ..ColonyPolicy::default()
            },
        }]);
        // Run well past an expansion window that lands after level 6 is earned
        // (Ancient's expand period is long).
        for _ in 0..2000 {
            let cmds = s.colony_commands();
            s.step(&cmds);
        }
        assert_eq!(
            s.colony_count_for(P0),
            Species::Ancient.colony_cap(),
            "Ancient expansion is capped at its archetype ceiling"
        );
    }

    #[test]
    fn conflict_emerges_over_a_shared_deposit() {
        // Two AI empires sharing one contested deposit-rich map fight without any
        // scripting — scarcity drives the war. Deterministic.
        let mut map = Map::new(28, 12);
        map.set_deposit(
            14,
            6,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 50_000,
            },
        );
        let mut s = Sim::new(map, 5, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 3, 6);
        s.add_building(P1, BuildingKind::CommandCenter, 24, 6);
        let mut peak_units = 0;
        let mut prev_units = 0;
        let mut saw_casualty = false;
        for _ in 0..4000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            let units = s.unit_count(P0) + s.unit_count(P1);
            peak_units = peak_units.max(units);
            // A drop in total living units between ticks is a battlefield death.
            if units < prev_units {
                saw_casualty = true;
            }
            prev_units = units;
        }
        assert!(peak_units > 0, "both empires fielded forces");
        assert!(
            saw_casualty,
            "casualties were taken — conflict emerged without scripting"
        );
    }

    // ---- M5: planetary expansion ----

    #[test]
    fn found_colony_places_a_base_and_registers_a_colony() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
        let parent = s.add_colony(P0, cc, 0);
        let entities_before = s.entity_count();
        s.step(&[Command::FoundColony {
            owner: P0,
            parent,
            x: 12,
            y: 12,
        }]);
        // A second Command Center exists and a second colony is registered.
        assert_eq!(s.entity_count(), entities_before + 1);
        assert_eq!(s.colony(ColonyId(1)).unwrap().owner, P0);
        assert!(s.money(P0) < f(5000), "founding spent Money");
    }

    #[test]
    fn found_colony_respects_the_per_owner_cap() {
        let mut s = Sim::new(Map::new(64, 40), 1, f(100_000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_colony(P0, cc, 0);
        // Try to found many at distinct in-bounds tiles; only up to the cap take.
        let mut x = 10;
        for _ in 0..10 {
            s.step(&[Command::FoundColony {
                owner: P0,
                parent: ColonyId(0),
                x,
                y: 20,
            }]);
            x += 7;
        }
        assert_eq!(
            s.colony_count_for(P0),
            super::MAX_COLONIES_PER_OWNER,
            "expansion is bounded by the per-owner cap"
        );
    }

    #[test]
    fn build_requires_owning_the_planet() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
        let pid = PlanetId(0);
        for y in 0..4 {
            for x in 0..4 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        s.push_planet(Planet {
            owner: None,
            seat: None,
            center: tile_center(2, 2),
            radius: f(3),
        });

        // Build on the unowned planet is rejected (no building appears). Wall is
        // a money-only building (no energy/labour cost), so the only thing that
        // can block it here is the planet-ownership gate.
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 1,
            y: 1,
        }]);
        assert_eq!(s.buildings_owned_by(P0), 0);

        // After P0 owns the planet, the same build succeeds.
        s.set_planet_owner(pid, Some(P0));
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 1,
            y: 1,
        }]);
        assert_eq!(s.buildings_owned_by(P0), 1);

        // Open space (no planet id) stays unbuildable.
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Wall,
            x: 10,
            y: 10,
        }]);
        assert_eq!(s.buildings_owned_by(P0), 1);
    }

    #[test]
    fn found_colony_claims_only_unowned_planets() {
        let mut s = Sim::new(Map::new(20, 20), 2, f(5000));
        let pid = PlanetId(0);
        for y in 0..4 {
            for x in 0..4 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        s.push_planet(Planet {
            owner: None,
            seat: None,
            center: tile_center(2, 2),
            radius: f(3),
        });
        // (FOUND_COLONY_COST is paid from money; 5000 is plenty.)
        s.step(&[Command::FoundColony {
            owner: P0,
            parent: ColonyId(0),
            x: 1,
            y: 1,
        }]);
        assert_eq!(s.planet_owner(pid), Some(P0));
        // founding again on the now-owned planet does nothing new
        let before = s.buildings_owned_by(P0);
        s.step(&[Command::FoundColony {
            owner: P1,
            parent: ColonyId(0),
            x: 2,
            y: 2,
        }]);
        assert_eq!(s.planet_owner(pid), Some(P0)); // still P0's
        assert_eq!(s.buildings_owned_by(P0), before);
        assert_eq!(
            s.buildings_owned_by(P1),
            0,
            "P1 cannot found on a planet P0 already owns"
        );
    }

    #[test]
    fn autonomous_colony_expands_when_policy_allows() {
        use crate::game::civ::{ColonyPolicy, ExpansionIntent, AUTONOMY_HOLD_TICKS};
        let mut s = Sim::new(Map::new(40, 40), 1, f(100_000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
        let col = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        s.step(&[Command::SetColonyPolicy {
            owner: P0,
            colony: col,
            policy: ColonyPolicy {
                expansion: ExpansionIntent::AutoSafe,
                ..ColonyPolicy::default()
            },
        }]);
        // Earn past level 6 and cross an expansion window.
        for _ in 0..(AUTONOMY_HOLD_TICKS * 7) {
            let cmds = s.colony_commands();
            s.step(&cmds);
        }
        assert!(
            s.colony_count_for(P0) > 1,
            "an autonomous colony with AutoSafe expansion founds new colonies"
        );
    }

    // ---- M4: special-resource discovery ----

    #[test]
    fn field_intensity_is_deterministic_and_finite_is_zero() {
        use crate::game::civ::special::{field_intensity, SpecialKind};
        let a = field_intensity(12_345, 5, 10, SpecialKind::SolarFlux);
        let b = field_intensity(12_345, 5, 10, SpecialKind::SolarFlux);
        assert_eq!(a, b, "same inputs ⇒ same intensity");
        // Finite kinds have no field intensity (they live in deposits).
        assert_eq!(
            field_intensity(12_345, 5, 10, SpecialKind::Antimatter),
            Fixed::ZERO
        );
    }

    #[test]
    fn surveyed_field_special_accrues_into_the_stockpile() {
        use crate::game::civ::special::{field_intensity, Knowledge, SpecialKind};
        let mut s = Sim::new(Map::new(20, 20), 12_345, f(5000));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 10);
        let col = s.add_colony(P0, cc, 0);
        let solar = SpecialKind::SolarFlux.index();
        let grav = SpecialKind::GravGradient.index();
        // Unsurveyed: nothing accrues.
        s.step(&[]);
        assert_eq!(s.colony(col).unwrap().stockpile[solar], Fixed::ZERO);
        // Survey Solar Flux, then accrue over ten ticks total (the survey tick
        // itself extracts once, after the knowledge flips Extractable).
        s.step(&[Command::SurveySpecial {
            owner: P0,
            colony: col,
            kind: SpecialKind::SolarFlux,
        }]);
        for _ in 0..9 {
            s.step(&[]);
        }
        let intensity = field_intensity(12_345, 5, 10, SpecialKind::SolarFlux);
        assert_eq!(
            s.colony(col).unwrap().stockpile[solar].to_bits(),
            intensity.to_bits() * 10,
            "ten ticks of extraction accrue 10× the field intensity"
        );
        assert_eq!(
            s.colony(col).unwrap().knowledge_of[solar],
            Knowledge::Extractable
        );
        // An unsurveyed special stays at zero.
        assert_eq!(s.colony(col).unwrap().stockpile[grav], Fixed::ZERO);
    }

    #[test]
    fn colony_slots_are_recycled() {
        // The colony arena mirrors the entity recycler: a fresh colony reuses a
        // freed slot (LIFO) rather than growing the vec unbounded.
        let mut s = Sim::new(Map::new(16, 16), 1, f(500));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 5, 8);
        let first = s.add_colony(P0, cc, 0);
        s.free_colony(first);
        let reused = s.add_colony(P0, cc, crate::game::civ::AUTONOMY_FULL);
        assert_eq!(first, reused);
    }

    #[test]
    fn research_rejects_already_researched_and_unmet_prereqs() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        // Granting the Weapons root (20) then re-researching it is a no-op.
        s.grant_tech(P0, 20);
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 20,
        }]);
        assert!(
            s.research_state(P0).1.is_none(),
            "an already-researched node is rejected"
        );
        // Electromagnetic Railgun (71) needs prereq 70 (and a lab past era 0):
        // with neither, the request is rejected and nothing starts.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 71,
        }]);
        assert!(
            s.research_state(P0).1.is_none(),
            "a node with unmet prereqs is rejected"
        );
        assert!(!s.research_state(P0).0.get(71));
    }

    #[test]
    fn supply_cap_limits_trained_units() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let b = s.add_building(P0, BuildingKind::Barracks, 4, 2);
        let cap = s.supply_cap(P0); // 10 base + 6 CC + 5 barracks
        assert_eq!(cap, 21);
        // Accrue enough Labour (CC+Barracks ~3/tick) that supply, not Labour, is
        // the binding limit when we over-queue.
        for _ in 0..16 {
            s.step(&[]);
        }
        // Queue far more than the cap in a single tick; the cap must hold.
        let mut cmds = alloc::vec::Vec::new();
        for _ in 0..(cap + 8) {
            cmds.push(Command::Train {
                owner: P0,
                barracks: b,
                kind: UnitKind::Infantry,
            });
        }
        s.step(&cmds);
        assert_eq!(s.supply_used(P0), cap, "training exceeded the supply cap");
    }

    #[test]
    fn perk_choice_sets_bit_and_applies_effect() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let base_cap = s.supply_cap(P0);
        s.step(&[Command::ChoosePerk {
            owner: P0,
            perk: crate::game::perk::CONSCRIPTION,
        }]);
        assert!(s.perks(P0) & (1 << crate::game::perk::CONSCRIPTION) != 0);
        assert_eq!(
            s.supply_cap(P0),
            base_cap + 8,
            "conscription should lift the cap"
        );
        // An out-of-range perk id is ignored.
        s.step(&[Command::ChoosePerk {
            owner: P0,
            perk: 99,
        }]);
        assert_eq!(s.perks(P0), 1 << crate::game::perk::CONSCRIPTION);
    }

    #[test]
    fn ascend_cost_ramp_is_linear_and_exact() {
        // Track 0 (Weapons): money 300 + 120*L, research 500 + 180*L.
        let (m0, r0) = ascend_cost(0, 0);
        assert_eq!(
            (m0.to_bits(), r0.to_bits()),
            (f(300).to_bits(), f(500).to_bits())
        );
        let (m1, r1) = ascend_cost(0, 1);
        assert_eq!(
            (m1.to_bits(), r1.to_bits()),
            (f(420).to_bits(), f(680).to_bits())
        );
        // Track 3 (Forge): money-only — 2000 + 900*L, research always 0.
        let (m3, r3) = ascend_cost(3, 2);
        assert_eq!(
            (m3.to_bits(), r3.to_bits()),
            (f(3800).to_bits(), f(0).to_bits())
        );
    }

    #[test]
    fn ascend_charges_money_and_increments_level() {
        // Doctrines are paid entirely from Money now (money + research folded).
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        // No deposits ⇒ Money only changes by the Ascend cost.
        let (mc0, rc0) = s.doctrine_cost(P0, 0);
        let m_before = s.money(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(s.doctrine_level(P0, 0), 1);
        assert_eq!(
            (m_before - s.money(P0)).to_bits(),
            (mc0 + rc0).to_bits(),
            "first Weapons level costs money + folded research"
        );
        let (mc1, rc1) = s.doctrine_cost(P0, 0);
        assert!(mc1 + rc1 > mc0 + rc0, "cost ramps with level");
        let m_before2 = s.money(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(s.doctrine_level(P0, 0), 2);
        assert_eq!(
            (m_before2 - s.money(P0)).to_bits(),
            (mc1 + rc1).to_bits(),
            "second Weapons level costs the ramped amount"
        );
    }

    #[test]
    fn ascend_research_track_is_gated_by_lab() {
        // No lab ⇒ a research track (Weapons) is a no-op, but Forge still works.
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(s.doctrine_level(P0, 0), 0, "no lab ⇒ Weapons track blocked");
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(
            s.doctrine_level(P0, 3),
            1,
            "Forge (money-only) needs no lab"
        );
        // With a lab and money, the Weapons track proceeds.
        let mut rich = Sim::new(Map::new(20, 20), 1, f(100_000));
        rich.add_building(P0, BuildingKind::ResearchLab, 2, 2);
        rich.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(
            rich.doctrine_level(P0, 0),
            1,
            "lab + money ⇒ Weapons proceeds"
        );
        // An out-of-range track id is ignored.
        rich.step(&[Command::Ascend {
            owner: P0,
            track: 99,
        }]);
        assert_eq!(rich.doctrine_level(P0, 99), 0);
    }

    #[test]
    fn doctrine_effects_fold_into_combat_factors() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(1_000_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        for _ in 0..1000 {
            s.step(&[]); // warm a large research pool (no Research cmds ⇒ no tech bonuses)
        }
        let w0 = s.player_weapon_bonus(P0);
        let a0 = s.player_armor_bonus(P0);
        let sh0 = s.shield_max(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(
            (s.player_weapon_bonus(P0) - w0).to_bits(),
            super::WEAPON_STEP.to_bits(),
            "Weapons doctrine adds flat damage"
        );
        s.step(&[Command::Ascend {
            owner: P0,
            track: 1,
        }]);
        assert_eq!(
            (s.player_armor_bonus(P0) - a0).to_bits(),
            super::ARMOR_STEP.to_bits(),
            "Armor doctrine adds flat mitigation"
        );
        s.step(&[Command::Ascend {
            owner: P0,
            track: 2,
        }]);
        assert_eq!(
            (s.shield_max(P0) - sh0).to_bits(),
            super::VITALITY_STEP.to_bits(),
            "Vitality doctrine raises shield max"
        );
        let wpre = s.player_weapon_bonus(P0);
        let apre = s.player_armor_bonus(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(
            (s.player_weapon_bonus(P0) - wpre).to_bits(),
            super::FORGE_WEAPON_STEP.to_bits(),
            "Forge adds flat damage"
        );
        assert_eq!(
            (s.player_armor_bonus(P0) - apre).to_bits(),
            super::FORGE_ARMOR_STEP.to_bits(),
            "Forge adds flat mitigation"
        );
    }

    #[test]
    fn forge_track_is_money_only_and_ramps() {
        // Forge needs no lab; its steep money lump cost (2000, then 2900) is the
        // bank-drainer.
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let m0 = s.money(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(s.doctrine_level(P0, 3), 1, "Forge needs no lab");
        assert_eq!(
            (m0 - s.money(P0)).to_bits(),
            f(2000).to_bits(),
            "first Forge level costs 2000 money"
        );
        let m1 = s.money(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(s.doctrine_level(P0, 3), 2);
        assert_eq!(
            (m1 - s.money(P0)).to_bits(),
            f(2900).to_bits(),
            "second Forge level costs 2900 money (ramp)"
        );
    }

    #[test]
    fn doctrine_levels_are_hashed() {
        let a = Sim::new(Map::new(8, 8), 1, f(0));
        let mut b = Sim::new(Map::new(8, 8), 1, f(0));
        b.civs[0].doctrine_levels[2] = 1;
        assert_ne!(
            a.state_hash(),
            b.state_hash(),
            "doctrine_levels must participate in the determinism hash"
        );
    }

    #[test]
    fn ai_emits_no_ascend_in_the_golden_run() {
        // Mirrors the golden setup: the era ≥ 1 AI gate must keep the 120-tick run
        // from ever ascending, so the golden re-pin is one-time and stays stable
        // across future balance tuning of the sink.
        let mut s = Sim::new(Map::new(40, 40), 12_345, f(1500));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        for _ in 0..120 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
        }
        for pl in [P0, P1] {
            assert_eq!(s.player_era(pl), 0, "golden run must stay era 0");
            for track in 0..4u8 {
                assert_eq!(
                    s.doctrine_level(pl, track),
                    0,
                    "the AI must not ascend in the golden run"
                );
            }
        }
    }

    #[test]
    fn ai_queues_no_unaffordable_money_spend() {
        // Across a full survival run (where the AI reaches era ≥ 1 and ascends), the
        // AI may queue a Build/Train AND an Ascend in one tick, but their combined
        // money cost must never exceed the balance — otherwise the apply step
        // silently drops the later command. The post-build `avail` gate enforces it.
        let mut s = crate::game::scenario::survival(3);
        let mut saw_research = false;
        for _ in 0..12_000u32 {
            let cmds = s.ai_commands(P0);
            let total: i64 = cmds
                .iter()
                .map(|c| match *c {
                    Command::Build { kind, .. } => s.building_cost(kind).to_bits(),
                    Command::Train { kind, .. } => s.unit_cost(kind).to_bits(),
                    Command::Ascend { track, .. } => s.doctrine_cost(P0, track).0.to_bits(),
                    Command::Research { tech_id, .. } => s
                        .technology(tech_id)
                        .map_or(0, |node| i64::from(node.money) * 65536),
                    _ => 0,
                })
                .sum();
            assert!(
                total <= s.money(P0).to_bits(),
                "AI queued money-spends ({total} bits) exceeding its balance"
            );
            saw_research |= cmds.iter().any(|c| matches!(c, Command::Research { .. }));
            s.step(&cmds);
            // Keep advancing after the mission becomes decisive: this regression
            // validates long-horizon AI budgeting, not match termination.
        }
        assert!(
            saw_research,
            "the AI should fund real research during Earthfront"
        );
    }

    #[test]
    fn ai_secures_alloy_and_fields_a_capital() {
        // A map rich in Ore (Minerals) with a cluster of Alloy deposits. Over a long
        // run the AI should tech to era 3, deliberately claim an Alloy deposit, and
        // train at least one Capital ship — instead of staying infantry-only because
        // it spent its whole extractor budget on Ore.
        let mut map = Map::new(40, 40);
        for x in 0..40u16 {
            for y in 0..40u16 {
                map.set_deposit(
                    x,
                    y,
                    crate::game::map::Deposit {
                        kind: crate::game::map::DepositKind::Ore,
                        remaining: 10_000_000,
                    },
                );
            }
        }
        for &(ax, ay) in &[(20u16, 20u16), (21, 20), (20, 21)] {
            map.set_deposit(
                ax,
                ay,
                crate::game::map::Deposit {
                    kind: crate::game::map::DepositKind::Alloy,
                    remaining: 10_000_000,
                },
            );
        }
        let mut s = Sim::new(map, 7, f(5000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut saw_capital = false;
        for _ in 0..30_000 {
            // P1 remains a static strategic target; simulating its full economy
            // only adds an unrelated army to this P0 alloy/capital milestone.
            let cmds = s.ai_commands(P0);
            s.step(&cmds);
            if s.views()
                .iter()
                .any(|v| v.owner == P0 && matches!(v.kind, EntityKindView::Unit(UnitKind::Capital)))
            {
                saw_capital = true;
                break;
            }
        }
        assert!(
            saw_capital,
            "AI should mine alloy and field a Capital ship by era 3: era={}, alive={}, money={}, energy={}, labour={}, entities={}",
            s.player_era(P0),
            s.civ_alive(P0),
            s.money(P0).to_bits(),
            s.energy(P0).to_bits(),
            s.labour(P0).to_bits(),
            s.entity_count(),
        );
    }

    #[test]
    fn barrage_damages_clustered_enemies_and_starts_cooldown() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        // Tank at gun-safe distance (5 > gun range 4) but inside Barrage range (6).
        let tank = s.add_unit(P0, UnitKind::Tank, v(2, 3));
        let foes = [
            s.add_unit(P1, UnitKind::Infantry, v(7, 3)),
            s.add_unit(P1, UnitKind::Infantry, v(7, 4)),
            s.add_unit(P1, UnitKind::Infantry, v(8, 3)),
        ];
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: tank,
            target: v(7, 3),
        }]);
        // 16 blast damage each (no shields researched): 50 → 34.
        for id in foes {
            assert_eq!(
                s.entities[id.0 as usize].hp.to_bits(),
                f(34).to_bits(),
                "every unit in the blast takes the full volley"
            );
        }
        assert!(
            s.entities[tank.0 as usize].ability_cd > 0,
            "the cast must start the cooldown"
        );
        // An immediate recast is rejected: the clump takes no further damage.
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: tank,
            target: v(7, 3),
        }]);
        assert_eq!(
            s.entities[foes[0].0 as usize].hp.to_bits(),
            f(34).to_bits(),
            "cooldown must block a recast"
        );
    }

    #[test]
    fn emp_stuns_units_for_its_duration_then_releases() {
        let mut s = Sim::new(Map::new(30, 20), 1, f(0));
        // Distance 5: inside EMP range (5) but outside the heli's gun (4), so the
        // target is stunned, not shot.
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(3, 3));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(8, 3));
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: heli,
            target: v(8, 3),
        }]);
        assert!(s.entities[foe.0 as usize].stun_ticks > 0, "EMP must stun");
        let start_x = s.entities[foe.0 as usize].pos.x.to_bits();
        // Orders are accepted but held while stunned.
        s.step(&[Command::Move {
            owner: P1,
            unit: foe,
            target: v(14, 3),
        }]);
        assert_eq!(
            s.entities[foe.0 as usize].pos.x.to_bits(),
            start_x,
            "stunned units hold position"
        );
        // Once the stun expires the held order resumes.
        for _ in 0..120 {
            s.step(&[]);
        }
        assert_eq!(s.entities[foe.0 as usize].stun_ticks, 0);
        assert_ne!(
            s.entities[foe.0 as usize].pos.x.to_bits(),
            start_x,
            "the unit must resume moving after the stun"
        );
    }

    #[test]
    fn nanite_field_heals_wounded_allies_capped_at_max() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        let capital = s.add_unit(P0, UnitKind::Capital, v(5, 5));
        let infantry = s.add_unit(P0, UnitKind::Infantry, v(6, 5));
        let tank = s.add_unit(P0, UnitKind::Tank, v(5, 6));
        s.entities[infantry.0 as usize].hp = f(10); // max 50: 10 + 60 caps at 50
        s.entities[tank.0 as usize].hp = f(200); // max 220: 200 + 60 caps at 220
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: capital,
            target: v(5, 5),
        }]);
        assert_eq!(
            s.entities[infantry.0 as usize].hp.to_bits(),
            f(50).to_bits(),
            "healing must cap at max HP"
        );
        assert_eq!(
            s.entities[tank.0 as usize].hp.to_bits(),
            f(220).to_bits(),
            "partial heal also caps at max HP"
        );
    }

    #[test]
    fn capital_splash_hits_clustered_neighbors() {
        // The Capital's main gun is the one weapon with area splash: a 2-tile
        // blast where neighbours of the primary target take 50% damage. A clumped
        // pair both bleed; a pair spread beyond the blast radius does not.
        //
        // Capital damage 40, Explosive vs Flesh is neutral (×1), era-0 / no
        // research / no perks ⇒ no other factors. Fresh sim ⇒ zero shields, so
        // damage lands straight on HP: primary -40, splash -20 (50% of 40).
        let mut clustered = Sim::new(Map::new(30, 30), 1, f(0));
        let cap = clustered.add_unit(P0, UnitKind::Capital, v(10, 10));
        // Primary (nearest, 4 away) and a neighbour 1 tile from it (inside the
        // 2-tile blast, 5 away from the Capital — still inside its range 6).
        let primary = clustered.add_unit(P1, UnitKind::Infantry, v(14, 10));
        let neighbour = clustered.add_unit(P1, UnitKind::Infantry, v(15, 10));
        // First tick: cooldown starts at 0, so the Capital fires immediately.
        clustered.step(&[]);
        assert!(
            clustered.entities[cap.0 as usize].cooldown > 0,
            "the Capital must have fired this tick"
        );
        assert_eq!(
            clustered.entities[primary.0 as usize].hp.to_bits(),
            f(10).to_bits(),
            "the primary target takes the full 40 (50 -> 10)"
        );
        assert_eq!(
            clustered.entities[neighbour.0 as usize].hp.to_bits(),
            f(30).to_bits(),
            "the clustered neighbour takes half the blast, 20 (50 -> 30)"
        );

        // Control: the same fight, but the second enemy is well beyond the 2-tile
        // blast (far side of the map, out of splash but a clean primary pick is
        // still the near one). Only the primary takes damage.
        let mut spread = Sim::new(Map::new(30, 30), 1, f(0));
        let cap2 = spread.add_unit(P0, UnitKind::Capital, v(10, 10));
        let near = spread.add_unit(P1, UnitKind::Infantry, v(14, 10));
        // 6 tiles from `near` (>> splash radius 2) and out of the Capital's
        // range-6 reach, so it is neither splashed nor targeted this tick.
        let far = spread.add_unit(P1, UnitKind::Infantry, v(20, 10));
        spread.step(&[]);
        assert!(
            spread.entities[cap2.0 as usize].cooldown > 0,
            "the Capital must have fired this tick"
        );
        assert_eq!(
            spread.entities[near.0 as usize].hp.to_bits(),
            f(10).to_bits(),
            "the primary target still takes the full 40"
        );
        assert_eq!(
            spread.entities[far.0 as usize].hp.to_bits(),
            f(50).to_bits(),
            "a foe beyond the splash radius is untouched"
        );
    }

    #[test]
    fn use_ability_is_validated() {
        let mut s = Sim::new(Map::new(30, 20), 1, f(0));
        let tank = s.add_unit(P0, UnitKind::Tank, v(2, 3));
        let grunt = s.add_unit(P0, UnitKind::Infantry, v(2, 5));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(8, 3));
        // Wrong owner: P1 cannot cast P0's tank.
        s.step(&[Command::UseAbility {
            owner: P1,
            unit: tank,
            target: v(8, 3),
        }]);
        // Out of range: Barrage range is 6, target at distance 12.
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: tank,
            target: v(14, 3),
        }]);
        // No ability: infantry carries none.
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: grunt,
            target: v(8, 3),
        }]);
        assert_eq!(
            s.entities[foe.0 as usize].hp.to_bits(),
            f(50).to_bits(),
            "no invalid cast may deal damage"
        );
        assert_eq!(
            s.entities[tank.0 as usize].ability_cd, 0,
            "rejected casts must not start the cooldown"
        );
    }

    #[test]
    fn ai_casts_an_ability_at_a_packed_clump() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 8);
        s.add_unit(P0, UnitKind::Tank, v(2, 3));
        for i in 0..3i32 {
            s.add_unit(P1, UnitKind::Infantry, v(7, 3 + i));
        }
        let cmds = s.ai_commands(P0);
        assert!(
            cmds.iter().any(|c| matches!(c, Command::UseAbility { .. })),
            "the AI should barrage a packed enemy clump"
        );
    }

    #[test]
    fn abilities_are_deterministic() {
        let build = || {
            let mut s = Sim::new(Map::new(20, 20), 9, f(0));
            let t = s.add_unit(P0, UnitKind::Tank, v(2, 3));
            for i in 0..3i32 {
                s.add_unit(P1, UnitKind::Infantry, v(7, 3 + i));
            }
            (s, t)
        };
        let (mut a, ta) = build();
        let (mut b, tb) = build();
        for _ in 0..200 {
            let cmd_a = [Command::UseAbility {
                owner: P0,
                unit: ta,
                target: v(7, 3),
            }];
            let cmd_b = [Command::UseAbility {
                owner: P0,
                unit: tb,
                target: v(7, 3),
            }];
            a.step(&cmd_a);
            b.step(&cmd_b);
        }
        assert_eq!(
            a.state_hash(),
            b.state_hash(),
            "identical ability usage must stay bit-identical"
        );
    }

    #[test]
    fn emp_immunity_prevents_chain_stun() {
        let mut s = Sim::new(Map::new(30, 20), 1, f(0));
        let heli_a = s.add_unit(P0, UnitKind::Helicopter, v(3, 3));
        let heli_b = s.add_unit(P0, UnitKind::Helicopter, v(4, 4));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(8, 3));
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: heli_a,
            target: v(8, 3),
        }]);
        assert!(s.entities[foe.0 as usize].stun_ticks > 0);
        // Let the stun wear off — the release grants a hardening window.
        for _ in 0..50 {
            s.step(&[]);
        }
        assert_eq!(s.entities[foe.0 as usize].stun_ticks, 0);
        assert!(
            s.entities[foe.0 as usize].stun_immunity > 0,
            "release must grant immunity"
        );
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: heli_b,
            target: v(8, 3),
        }]);
        assert_eq!(
            s.entities[foe.0 as usize].stun_ticks, 0,
            "an immune unit cannot be chain-stunned"
        );
        // Once the immunity lapses, EMP bites again.
        s.entities[heli_b.0 as usize].ability_cd = 0;
        for _ in 0..100 {
            s.step(&[]);
        }
        assert_eq!(s.entities[foe.0 as usize].stun_immunity, 0);
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: heli_b,
            target: v(8, 3),
        }]);
        assert!(
            s.entities[foe.0 as usize].stun_ticks > 0,
            "after the immunity window the unit is stunnable again"
        );
    }

    #[test]
    fn same_tick_double_cast_resolves_once() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        let tank = s.add_unit(P0, UnitKind::Tank, v(2, 3));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(7, 3));
        let cmd = Command::UseAbility {
            owner: P0,
            unit: tank,
            target: v(7, 3),
        };
        s.step(&[cmd.clone(), cmd]);
        assert_eq!(
            s.entities[foe.0 as usize].hp.to_bits(),
            f(34).to_bits(),
            "the first cast starts the cooldown; the same-tick duplicate must no-op"
        );
    }

    #[test]
    fn emp_freezes_a_moving_unit_then_it_resumes() {
        let mut s = Sim::new(Map::new(40, 20), 1, f(0));
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(12, 4));
        let foe = s.add_unit(P1, UnitKind::Tank, v(8, 3));
        s.step(&[Command::Move {
            owner: P1,
            unit: foe,
            target: v(20, 3),
        }]);
        for _ in 0..11 {
            s.step(&[]);
        }
        let mid = s.entities[foe.0 as usize].pos;
        assert_ne!(
            mid.x.to_bits(),
            v(8, 3).x.to_bits(),
            "the tank must be moving before the EMP"
        );
        // Freeze it mid-path.
        s.step(&[Command::UseAbility {
            owner: P0,
            unit: heli,
            target: mid,
        }]);
        let frozen = s.entities[foe.0 as usize].pos.x.to_bits();
        for _ in 0..20 {
            s.step(&[]);
        }
        assert_eq!(
            s.entities[foe.0 as usize].pos.x.to_bits(),
            frozen,
            "a stunned unit holds position mid-path"
        );
        for _ in 0..60 {
            s.step(&[]);
        }
        assert_ne!(
            s.entities[foe.0 as usize].pos.x.to_bits(),
            frozen,
            "the held path resumes once the stun expires"
        );
    }

    #[test]
    fn ai_heals_a_wounded_clump_with_nanite_field() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 8);
        let cap = s.add_unit(P0, UnitKind::Capital, v(5, 5));
        let a = s.add_unit(P0, UnitKind::Infantry, v(6, 5));
        let b = s.add_unit(P0, UnitKind::Infantry, v(5, 6));
        s.entities[a.0 as usize].hp = f(10);
        s.entities[b.0 as usize].hp = f(10);
        let cmds = s.ai_commands(P0);
        assert!(
            cmds.iter()
                .any(|c| matches!(c, Command::UseAbility { unit, .. } if *unit == cap)),
            "the AI Capital should heal a wounded clump"
        );
    }

    #[test]
    fn escalating_waves_harden_the_attacker() {
        // Each escalating wave grants the attacker a doctrine level (Weapons →
        // Armor → Vitality rotation), so late waves grow in QUALITY, not just count.
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.set_waves(WaveConfig {
            first_delay: 10,
            interval: 10,
            base_size: 1,
            growth: 0,
            spawn: Vec2::new(Fixed::from_int(15), Fixed::from_int(15)),
            unit: UnitKind::Infantry,
            attacker: P1,
            defender: P0,
            escalate: true,
        });
        for _ in 0..45 {
            s.step(&[]);
        }
        let total: u32 = (0..4u8).map(|t| u32::from(s.doctrine_level(P1, t))).sum();
        assert!(
            total >= 3,
            "after several escalating waves the attacker should hold doctrine levels (got {total})"
        );
        assert_eq!(
            (0..4u8)
                .map(|t| u32::from(s.doctrine_level(P0, t)))
                .sum::<u32>(),
            0,
            "the defender gains nothing for free"
        );
    }

    #[test]
    fn earthfront_is_won_by_destroying_the_hostile_core() {
        // In normal mode, being the only side with a Command Center is a win.
        let mut normal = Sim::new(Map::new(10, 10), 1, f(0));
        normal.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        assert_eq!(normal.winner(), Some(P0), "lone CC wins a normal match");

        // Earthfront has the same decisive base-destruction objective: once the
        // hostile Core Node is gone, the human wins the mission.
        let mut surv = Sim::new(Map::new(10, 10), 1, f(0));
        surv.set_survival_mode(true);
        surv.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let core = surv.add_building(P1, BuildingKind::CommandCenter, 7, 7);
        assert_eq!(
            surv.winner(),
            None,
            "both live bases keep the mission active"
        );
        surv.entities[core.0 as usize].alive = false;
        assert_eq!(
            surv.winner(),
            Some(P0),
            "destroying the hostile Core Node must win Earthfront"
        );
    }

    fn wave_cfg() -> WaveConfig {
        WaveConfig {
            first_delay: 0,
            interval: 50,
            base_size: 2,
            growth: 1,
            spawn: v(36, 20),
            unit: UnitKind::Infantry,
            attacker: P1,
            defender: P0,
            escalate: false,
        }
    }

    #[test]
    fn power_plant_feeds_the_energy_stockpile() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        s.add_building(P0, BuildingKind::PowerPlant, 1, 1);
        s.step(&[]);
        // PowerPlant adds 40 Energy/tick to the owner's stockpile.
        assert_eq!(s.energy(P0), f(40));
        assert_eq!(s.energy(P1), f(0));
    }

    #[test]
    fn wave_countdown_reports_time_to_next_wave() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        assert_eq!(s.ticks_until_next_wave(), None);
        s.set_waves(wave_cfg());
        assert_eq!(s.ticks_until_next_wave(), Some(0)); // first_delay is 0
        s.step(&[]);
        assert_eq!(s.ticks_until_next_wave(), Some(49)); // interval 50, 1 tick in
    }

    #[test]
    fn waves_spawn_on_schedule_and_grow() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
        s.set_waves(wave_cfg());
        s.step(&[]); // tick 0 -> wave 0 (base_size = 2)
        assert_eq!(s.unit_count(P1), 2);
        for _ in 0..50 {
            s.step(&[]);
        }
        // 51 steps total -> tick 50 fired wave 1 (size 3); none have died yet.
        assert_eq!(s.unit_count(P1), 5);
    }

    #[test]
    fn wave_units_march_toward_the_defender() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
        s.set_waves(wave_cfg());
        s.step(&[]);
        let uid = s.views().into_iter().find(|w| w.owner == P1).unwrap().id;
        let x0 = s.position(uid).unwrap().x;
        for _ in 0..20 {
            s.step(&[]);
        }
        // Spawned at x=36, base at x=3, so it should be moving left.
        assert!(s.position(uid).unwrap().x < x0);
    }

    #[test]
    fn waves_are_deterministic() {
        let run = |seed: u64| {
            let mut s = Sim::new(Map::new(40, 40), seed, f(0));
            s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
            s.set_waves(wave_cfg());
            let mut hashes = Vec::new();
            for _ in 0..120 {
                s.step(&[]);
                hashes.push(s.state_hash());
            }
            hashes
        };
        assert_eq!(run(7), run(7));
    }

    #[test]
    fn combat_scales_with_the_spatial_grid() {
        // Two interleaved blobs of infantry, in range of each other.
        let mut s = Sim::new(Map::new(48, 48), 1, f(0));
        let n: i32 = 150;
        for i in 0..n {
            let row = i % 10;
            let col = i / 10;
            s.add_unit(P0, UnitKind::Infantry, v(10 + col, 5 + row));
            s.add_unit(P1, UnitKind::Infantry, v(12 + col, 5 + row));
        }
        let start = s.entity_count();
        assert_eq!(start, 300); // 150 per side
        for _ in 0..120 {
            s.step(&[]);
        }
        // They were within range and fought, so casualties occurred.
        assert!(s.entity_count() < start);
    }

    #[test]
    fn dead_slots_are_recycled() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let _tank = s.add_unit(P0, UnitKind::Tank, v(0, 0)); // slot 0
        let wall = s.add_building(P1, BuildingKind::Wall, 1, 1); // slot 1
        for _ in 0..200 {
            s.step(&[]); // the tank destroys the wall
        }
        assert!(!s.is_alive(wall));
        // The next spawn reuses the wall's freed slot rather than growing the list.
        let reused = s.add_unit(P0, UnitKind::Infantry, v(5, 5));
        assert_eq!(reused, wall);
    }

    #[test]
    fn ai_builds_anti_air_when_threatened_by_aircraft() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(3000));
        s.add_building(P1, BuildingKind::CommandCenter, 30, 20);
        s.add_building(P1, BuildingKind::PowerPlant, 32, 20);
        // A player helicopter is on the field — the AI should counter with AA.
        s.add_unit(P0, UnitKind::Helicopter, v(20, 20));
        for _ in 0..2500 {
            let cmds = s.ai_commands(P1);
            s.step(&cmds);
        }
        let has_aa = s.views().into_iter().any(|v| {
            v.owner == P1 && matches!(v.kind, EntityKindView::Building(BuildingKind::AaTurret))
        });
        assert!(has_aa);
    }

    /// Stands two armies a few tiles apart (in weapon range) and fights to the
    /// finish, returning `(surviving P0 units, surviving P1 units)`.
    fn duel(a: &[UnitKind], b: &[UnitKind]) -> (usize, usize) {
        let mut s = Sim::new(Map::new(40, 40), 1, f(0));
        for (i, &k) in a.iter().enumerate() {
            s.add_unit(P0, k, v(15, 16 + i32::try_from(i).unwrap()));
        }
        for (i, &k) in b.iter().enumerate() {
            s.add_unit(P1, k, v(18, 16 + i32::try_from(i).unwrap()));
        }
        for _ in 0..800 {
            s.step(&[]);
        }
        (s.unit_count(P0), s.unit_count(P1))
    }

    #[test]
    fn anti_armor_hard_counters_tanks_at_equal_cost() {
        // 4 anti-armor (440cr) vs 2 tanks (400cr): the anti-armour role wins.
        let (aa, tanks) = duel(
            &[
                UnitKind::AntiArmor,
                UnitKind::AntiArmor,
                UnitKind::AntiArmor,
                UnitKind::AntiArmor,
            ],
            &[UnitKind::Tank, UnitKind::Tank],
        );
        assert!(aa > 0 && tanks == 0, "anti-armor {aa} vs tanks {tanks}");
    }

    #[test]
    fn helicopters_beat_ground_without_anti_air() {
        // 1 helicopter (160cr) vs 3 infantry (150cr): ground can't touch air.
        let (heli, inf) = duel(
            &[UnitKind::Helicopter],
            &[UnitKind::Infantry, UnitKind::Infantry, UnitKind::Infantry],
        );
        assert!(heli > 0 && inf == 0, "heli {heli} vs infantry {inf}");
    }

    #[test]
    fn research_completes_after_its_duration_and_sets_the_bit() {
        use crate::game::tech_grid::node;
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        // Node 20 (Combined-Arms Doctrine) is an era-0 root: money-paid, no lab,
        // no prereq. Warm up first so its Energy + Labour cost is covered.
        for _ in 0..120 {
            s.step(&[]);
        }
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 20,
        }]);
        let (set, active) = s.research_state(P0);
        assert!(!set.get(20));
        assert!(active.is_some());
        assert_eq!(
            s.suggested_research(P0),
            None,
            "an active project suppresses the one-click recommendation"
        );
        assert!(
            s.available_research(P0).is_empty(),
            "an active project suppresses the presentation choice list"
        );
        let dur = node(20).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        let (set, active) = s.research_state(P0);
        assert!(set.get(20), "node 20 bit set after duration");
        assert!(active.is_none());
    }

    #[test]
    fn research_bonus_helpers_start_at_zero_then_grid_nodes_raise_them() {
        let mut s = Sim::new(Map::new(10, 10), 1, f(0));
        // No research yet → every branch rider is zero.
        assert_eq!(s.player_weapon_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_armor_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_economy_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_mobility_bonus(P0), Fixed::ZERO);
        // Granting a node in each rider's branch lifts it above zero: Weapons(20),
        // Defense(25), Energy(5), Propulsion(15).
        for id in [20u32, 25, 5, 15] {
            s.grant_tech(P0, id);
        }
        assert!(s.player_weapon_bonus(P0) > Fixed::ZERO);
        assert!(s.player_armor_bonus(P0) > Fixed::ZERO);
        assert!(s.player_economy_bonus(P0) > Fixed::ZERO);
        assert!(s.player_mobility_bonus(P0) > Fixed::ZERO);
    }

    #[test]
    fn research_is_rejected_without_a_lab_or_prereq() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        // Satisfy Solid-State Laser (70)'s prereqs [24, 9] so the ONLY blocker is
        // the missing lab. Granting era key 9 advances P0 into era 1.
        for id in [5u32, 6, 7, 8, 9, 20, 21, 22, 23, 24] {
            s.grant_tech(P0, id);
        }
        assert_eq!(s.player_era(P0), 1);
        // No ResearchLab yet → an era-1 node is rejected.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 70,
        }]);
        assert!(s.research_state(P0).1.is_none());
        s.add_building(P0, BuildingKind::ResearchLab, 7, 20);
        // Railgun (71) needs prereq 70, not researched → still rejected.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 71,
        }]);
        assert!(s.research_state(P0).1.is_none());
    }

    #[test]
    fn ai_builds_a_lab_and_researches() {
        let mut s = Sim::new(Map::new(40, 40), 7, f(2000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut lab_seen = false;
        let mut research_seen = false;
        for _ in 0..2000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            if s.has_research_lab(P0) {
                lab_seen = true;
            }
            if s.research_state(P0).1.is_some() || !s.research_state(P0).0.is_empty() {
                research_seen = true;
            }
        }
        assert!(lab_seen, "AI builds a research lab");
        assert!(research_seen, "AI starts/finishes research");
    }

    #[test]
    fn researching_an_era_key_tech_advances_the_era() {
        use crate::game::tech_grid::node;
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        // Node 9 is the era-0 key (Energy spine, step 4). Grant its prereq chain.
        for id in [5u32, 6, 7, 8] {
            s.grant_tech(P0, id);
        }
        assert_eq!(s.player_era(P0), 0);
        // Warm up so the key's Energy + Labour cost is covered (era 0 needs no lab).
        for _ in 0..150 {
            s.step(&[]);
        }
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 9,
        }]);
        let dur = node(9).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        assert_eq!(s.player_era(P0), 1, "advanced an era");
    }

    #[test]
    fn era_damage_factor_scales_up() {
        assert_eq!(super::era_damage_factor(0), Fixed::ONE);
        assert!(super::era_damage_factor(1) > Fixed::ONE);
        assert!(super::era_damage_factor(3) > super::era_damage_factor(2));
        assert!(super::era_damage_factor(2) > super::era_damage_factor(1));
    }

    #[test]
    fn ai_advances_at_least_one_era() {
        let mut map = Map::new(40, 40);
        // Scatter ore deposits across the whole map so the AI's Refineries earn income
        // regardless of which buildable tile they land on.
        for x in 0..40u16 {
            for y in 0..40u16 {
                map.set_deposit(
                    x,
                    y,
                    crate::game::map::Deposit {
                        kind: crate::game::map::DepositKind::Ore,
                        remaining: 10_000_000,
                    },
                );
            }
        }
        let mut s = Sim::new(map, 7, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut max_era = 0u8;
        for _ in 0..18_000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            max_era = max_era.max(s.player_era(P0));
            if max_era >= 1 {
                break;
            }
        }
        assert!(max_era >= 1, "AI advanced at least one era");
    }

    #[test]
    fn shields_absorb_then_regen_and_antiarmor_pierces() {
        use crate::game::tech_grid::node;
        let mut s = Sim::new(Map::new(20, 20), 1, f(20_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        // Node 25 (Defense root) is era-0: money-paid, no lab, no prereq. A Defense
        // node raises the shield ceiling. Warm up so its cost is covered first.
        for _ in 0..120 {
            s.step(&[]);
        }
        // Research Spaced & Sloped Armor Theory (id 25) to completion.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 25,
        }]);
        let dur = node(25).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        assert!(s.player_shield_max(P0) > crate::fixed::Fixed::ZERO);
        // A newly spawned P0 unit has shield == max.
        let id = s.add_unit(
            P0,
            UnitKind::Infantry,
            crate::vec::Vec2::new(
                crate::fixed::Fixed::from_int(6),
                crate::fixed::Fixed::from_int(6),
            ),
        );
        let v = s.views().into_iter().find(|v| v.id == id).unwrap();
        assert_eq!(v.shield, v.max_shield);
        assert!(v.max_shield > crate::fixed::Fixed::ZERO);
    }

    #[test]
    fn air_is_immune_to_ground_fire_but_dies_to_anti_air() {
        // A helicopter shreds adjacent infantry, which cannot hit air at all.
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(5, 5));
        let inf = s.add_unit(P1, UnitKind::Infantry, v(6, 5));
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(s.is_alive(heli));
        assert!(!s.is_alive(inf));

        // An AA turret brings the helicopter down.
        let mut s2 = Sim::new(Map::new(20, 20), 1, f(0));
        let heli2 = s2.add_unit(P0, UnitKind::Helicopter, v(5, 5));
        s2.add_building(P1, BuildingKind::AaTurret, 6, 5);
        for _ in 0..400 {
            s2.step(&[]);
        }
        assert!(!s2.is_alive(heli2));
    }

    #[test]
    fn ai_researches_shields() {
        // Over a long match the AI should eventually research a Shield tech,
        // giving its units a non-zero shield max.
        let mut s = Sim::new(Map::new(40, 40), 7, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        for _ in 0..16000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
        }
        assert!(
            s.player_shield_max(P0) > crate::fixed::Fixed::ZERO,
            "AI (P0) should have researched a Shield tech"
        );
    }

    #[test]
    fn extractor_mines_money_from_a_deposit() {
        let mut map = Map::new(20, 20);
        map.set_deposit(
            4,
            2,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Alloy,
                remaining: 1000,
            },
        );
        let mut s = Sim::new(map, 1, f(20_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::AntimatterPlant, 4, 2); // ON the deposit
        let before = s.money(P0);
        for _ in 0..50 {
            s.step(&[]);
        }
        assert!(
            s.money(P0) > before,
            "money accrues from an extractor standing on a deposit"
        );
    }

    #[test]
    fn antigrav_research_makes_owner_units_ignore_terrain() {
        use crate::game::tech_grid::node;
        let mut s = Sim::new(Map::new(20, 20), 1, f(50_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        assert!(!s.has_antigrav(P0));
        // Node 45 (Gravity branch root) grants terrain-ignoring movement. Era-0
        // root: money-paid, no lab, no prereq. Warm up to cover its cost.
        for _ in 0..150 {
            s.step(&[]);
        }
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 45,
        }]);
        for _ in 0..node(45).unwrap().duration {
            s.step(&[]);
        }
        assert!(s.has_antigrav(P0), "anti-grav researched");
        assert!(!s.has_antigrav(P1), "opponent unaffected");
    }

    #[test]
    fn ai_researches_antigrav() {
        // Over a long match (seed 7), the AI should eventually research Anti-Grav
        // Drives — the LOWEST-priority node in the ladder, reached only after the
        // higher-priority work (era keys + every real building/unit unlock) is
        // exhausted.
        //
        // SOLO run (P0 only). Originally this was P0-vs-P1, but distance-decayed
        // combat (forward-base supply lines) shifted the head-to-head balance so
        // that with seed 7 the enemy now snowballs and conquers P0 before it can
        // grind to the LAST tech — P0 reaches Era 3 and dies. This test is about
        // the *research priority ladder* reaching its final node, NOT about who
        // wins a skirmish, so the enemy is irrelevant noise here. Dropping P1
        // isolates the ladder: with no one to conquer it, P0 reaches Anti-Grav at
        // tick ~185_542 (verified), comfortably inside the 200_000-tick budget.
        //
        // The reach-tick jumped from ~46_427 to ~185_542 when the Energy/Labour
        // caps were raised so every grid node is affordable (the cap-reachability
        // fix). Before, the 283 nodes whose Labour cost exceeded the old 800 cap
        // were PERMANENTLY unaffordable, so `ai_next_research` skipped them and the
        // ladder was short. Now those nodes — including every era key — are
        // affordable, so the AI climbs the full tree to Era 9 first, and only then
        // drops to the low-priority gravity node. The longer grind is the fix
        // working as intended: the back half of the game is now live content.
        //
        // The P0-vs-P1 combat balance is covered by the dedicated combat tests; the
        // earlier-milestone economy tests (e.g. antimatter-by-era-1) still run
        // head-to-head and pass because they resolve before the conquest.
        let mut map = Map::new(40, 40);
        // Scatter ore deposits across the whole map so the AI's Refineries earn income
        // regardless of which buildable tile they land on.
        for x in 0..40u16 {
            for y in 0..40u16 {
                map.set_deposit(
                    x,
                    y,
                    crate::game::map::Deposit {
                        kind: crate::game::map::DepositKind::Ore,
                        remaining: 10_000_000,
                    },
                );
            }
        }
        let mut s = Sim::new(map, 7, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        let mut antigrav_seen = false;
        for _ in 0..200_000 {
            let cmds = s.ai_commands(P0);
            s.step(&cmds);
            if s.has_antigrav(P0) {
                antigrav_seen = true;
                break;
            }
        }
        assert!(
            antigrav_seen,
            "AI (P0) should eventually research Anti-Grav Drives"
        );
    }

    #[test]
    fn ai_builds_antimatter_plant_by_era_1() {
        // Over a long match (≈8000 ticks, seed 7) the AI should eventually build
        // an Antimatter Plant once it reaches Era 1.
        let mut map = Map::new(40, 40);
        // Scatter ore deposits across the whole map so the AI's Refineries earn income
        // regardless of which buildable tile they land on.
        for x in 0..40u16 {
            for y in 0..40u16 {
                map.set_deposit(
                    x,
                    y,
                    crate::game::map::Deposit {
                        kind: crate::game::map::DepositKind::Ore,
                        remaining: 10_000_000,
                    },
                );
            }
        }
        let mut s = Sim::new(map, 7, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut plant_seen = false;
        for _ in 0..8000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            if s.has_building(P0, BuildingKind::AntimatterPlant) {
                plant_seen = true;
                break;
            }
        }
        assert!(
            plant_seen,
            "AI (P0) should build an Antimatter Plant after reaching Era 1"
        );
    }

    #[test]
    fn lab_gates_research_past_era_zero() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        // Solid-State Laser (70) is an era-1 node (prereqs [24, 9]); granting key 9
        // advances P0 to era 1, where research needs a lab.
        for id in [5u32, 6, 7, 8, 9, 20, 21, 22, 23, 24] {
            s.grant_tech(P0, id);
        }
        // Warm up so Energy + Labour are not the blocker — only the lab is.
        for _ in 0..150 {
            s.step(&[]);
        }
        // No Research Lab yet -> rejected even with resources to spare.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 70,
        }]);
        assert!(
            s.research_state(P0).1.is_none(),
            "era-1 research needs a Research Lab"
        );
        // With a lab it starts immediately.
        s.add_building(P0, BuildingKind::ResearchLab, 6, 2);
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 70,
        }]);
        assert!(
            s.research_state(P0).1.is_some(),
            "node 70 starts with a lab + resources"
        );
    }

    #[test]
    fn ai_claims_and_mines_a_nearby_deposit() {
        let mut map = Map::new(24, 12);
        map.set_deposit(
            7,
            6,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 800,
            },
        );
        let mut s = Sim::new(map, 1, f(100_000));
        s.add_building(P1, BuildingKind::CommandCenter, 4, 6);
        for _ in 0..500 {
            let cmds = s.ai_commands(P1);
            s.step(&cmds);
        }
        let mined = s.map().deposit(7, 6).is_none_or(|d| d.remaining < 800);
        assert!(mined, "AI never claimed and mined the deposit");
    }

    #[test]
    fn extractor_on_ore_mines_money_and_depletes() {
        let mut map = Map::new(20, 20);
        map.set_deposit(
            6,
            2,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 12,
            },
        );
        let mut s = Sim::new(map, 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
        s.add_building(P0, BuildingKind::Refinery, 6, 2); // ON the ore deposit
        let before = s.money(P0).to_bits();
        s.step(&[]);
        assert!(
            s.money(P0).to_bits() > before,
            "extractor should mine money"
        );
        for _ in 0..10 {
            s.step(&[]);
        }
        assert_eq!(s.map().deposit(6, 2), None, "deposit should be exhausted");
    }

    #[test]
    fn capturing_a_seat_transfers_the_planet() {
        use crate::game::civ::AUTONOMY_FULL;
        let mut s = Sim::new(Map::new(12, 12), 7, f(9000));
        let pid = PlanetId(0);
        for y in 0..3 {
            for x in 0..3 {
                s.map_mut().set_planet(x, y, pid);
            }
        }
        // P1 owns the planet; its CC seat at (1,1), a Barracks at (0,0).
        let seat = s.add_building(P1, BuildingKind::CommandCenter, 1, 1);
        let bks = s.add_building(P1, BuildingKind::Barracks, 0, 0);
        s.push_planet(Planet {
            owner: Some(P1),
            seat: Some(seat),
            center: tile_center(1, 1),
            radius: f(2),
        });
        s.add_colony(P1, seat, AUTONOMY_FULL);
        // Bring the seat to near-death, then let a P0 attacker land the lethal blow.
        s.debug_set_hp(seat, f(1));
        s.add_unit(P0, UnitKind::Tank, tile_center(1, 1)); // adjacent/overlapping attacker
        for _ in 0..30 {
            s.step(&[]);
        }

        assert_eq!(
            s.planet_owner(pid),
            Some(P0),
            "planet transfers to attacker"
        );
        assert!(
            s.entity_alive(seat),
            "seat is captured intact, not destroyed"
        );
        assert_eq!(s.entity_owner(seat), Some(P0));
        assert_eq!(
            s.entity_owner(bks),
            Some(P0),
            "surviving buildings transfer"
        );
        assert_eq!(s.colony_owner_of_seat(seat), Some(P0), "colony transfers");
    }

    /// Reaping a colony's seat `CommandCenter` must free the colony in the same tick,
    /// not leave a ghost that keeps inflating its dead owner's empire. Here a seat is
    /// DESTROYED (driven to 0 HP with no attacker to capture it), so `clear_dead`
    /// reaps the entity and the orphaned-colony pass must drop the colony.
    #[test]
    fn destroying_a_colony_seat_reaps_the_colony() {
        use crate::game::civ::AUTONOMY_FULL;
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        // P0 owns two colonies seated on two CommandCenters (no planets registered,
        // so neither seat is a capturable planet seat — a lethal blow DESTROYS them).
        let keep_seat = s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        let doomed_seat = s.add_building(P0, BuildingKind::CommandCenter, 8, 8);
        let keep = s.add_colony(P0, keep_seat, AUTONOMY_FULL);
        let doomed = s.add_colony(P0, doomed_seat, AUTONOMY_FULL);
        assert_eq!(s.colony_count_for(P0), 2, "owner starts with two colonies");

        // Destroy the doomed seat (no enemy present ⇒ no capture ⇒ reaped by
        // clear_dead), then step so clear_dead runs.
        s.debug_set_hp(doomed_seat, f(0));
        s.step(&[]);

        // (a) The owner's colony count DROPS by exactly one.
        assert_eq!(
            s.colony_count_for(P0),
            1,
            "the orphaned colony must be freed when its seat is destroyed"
        );
        // The surviving colony is the one whose seat is intact; the orphan is gone.
        assert!(s.colony(keep).is_some(), "the live-seat colony survives");
        assert!(
            s.colony(doomed).is_none(),
            "the dead-seat colony is freed, not a ghost"
        );

        // (b) No ghost accrual / slot aliasing: the freed slot is recycled (LIFO), so
        // a freshly added colony reuses the doomed colony's exact slot index — proving
        // the orphan was actually freed (its slot returned to the free list), not just
        // left dead-but-unrecycled. The new colony seats on the live CC.
        let reused = s.add_colony(P0, keep_seat, AUTONOMY_FULL);
        assert_eq!(
            reused.0, doomed.0,
            "freeing the orphan recycled its slot (LIFO), so the next add reuses it"
        );
        assert_eq!(
            s.colony_count_for(P0),
            2,
            "no orphan double-counts: count is exactly the two live colonies"
        );
        // The ghost never aliased the live colony's slot.
        assert_ne!(
            keep.0, doomed.0,
            "the live colony kept its own distinct slot"
        );
    }
}

#[cfg(test)]
#[path = "qa_adversarial.rs"]
mod qa_adversarial;
#[cfg(test)]
impl Sim {
    pub(crate) fn order_calls_for_test(&self) -> u64 {
        self.order_calls
    }
}
