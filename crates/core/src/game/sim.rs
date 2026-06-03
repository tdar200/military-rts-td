//! The integrated RTS simulation: two players, an economy, buildings, units,
//! combat, and a win condition — all deterministic and fixed-point.
//!
//! [`Sim::step`] advances one fixed tick by, in order: applying the ordered
//! command batch, running the economy, advancing production, moving units,
//! resolving combat, and clearing the dead. [`Sim::state_hash`] fingerprints the
//! whole thing so two runs (or two platforms, or client and server) can be proven
//! identical.

use crate::fixed::Fixed;
use crate::game::balance::Balance;
use crate::game::hex;
use crate::game::map::{Map, Tile};
use crate::game::path::find_path;
use crate::game::stats::{
    damage_multiplier, ArmorType, AttackProfile, BuildingKind, DamageType, UnitKind,
};
use crate::hash::Fnv;
use crate::rng::Rng;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Number of players (single-player vs one AI for now; `PvP` later).
pub const PLAYER_COUNT: usize = 2;

/// How often (in ticks) the AI re-issues move orders to idle units, throttling
/// pathfinding work.
const MOVE_REISSUE_PERIOD: u64 = 20;

/// Combat spatial-grid cell size in tiles. Must be >= the largest attack range so
/// a 3x3 cell query around an attacker contains every in-range enemy.
const COMBAT_CELL: i32 = 8;

/// Identifies a player (`0` or `1`).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct PlayerId(pub u8);

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
    /// Remaining tile waypoints toward `move_target` (from A*), nearest first.
    path: Vec<(u16, u16)>,
    tile: Option<(u16, u16)>,
    build_queue: Vec<UnitKind>,
    build_progress: u32,
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
}

/// Ticks of EMP immunity granted when a stun wears off — twice the stun length,
/// capping worst-case stun uptime at one third even against massed casters.
const STUN_IMMUNITY: u32 = 90;

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

/// Antimatter cost to train a Capital Ship.
const CAPITAL_ANTIMATTER_COST: Fixed = Fixed::from_int(100);

/// Base population allowance before any production buildings.
const SUPPLY_BASE: u32 = 10;
/// Extra population headroom per Command Center.
const SUPPLY_PER_CC: u32 = 6;
/// Extra population headroom per Barracks.
const SUPPLY_PER_BARRACKS: u32 = 5;
/// Extra population headroom per Reactor — so surplus Minerals convert into a
/// bigger army (build reactors → raise the cap → field more units vs the waves).
const SUPPLY_PER_REACTOR: u32 = 4;
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

// === Ascendancy Doctrines ===
// Endless, escalating-cost upgrade tracks that turn a late-game resource surplus
// into army QUALITY (not quantity) under the hard supply cap. Four tracks, not
// mutually exclusive, no prereq. The next level's cost rises linearly with the
// level already bought, so it keeps pace with — then outgrows — income, draining
// the surplus forever instead of letting it bank. Effects fold into the existing
// per-player weapon/armor/shield accessors, so the combat code is untouched.
/// Number of doctrine tracks.
const DOCTRINE_TRACKS: usize = 4;
/// Hard ceiling on a track's level (keeps Fixed bits + hash width bounded).
const DOCTRINE_LEVEL_CAP: u16 = 9999;
/// Track index: army-wide flat weapon damage (research-heavy).
const DOC_WEAPONS: usize = 0;
/// Track index: army-wide flat armor mitigation (research-heavy).
const DOC_ARMOR: usize = 1;
/// Track index: army-wide shield-max (research-heavy survivability).
const DOC_VITALITY: usize = 2;
/// Track index: the minerals-only bank-drainer (steep escalating lump cost).
const DOC_FORGE: usize = 3;
/// Per-track cost ramp: cost(level L→L+1) = base + step * L. Minerals component.
const DOCTRINE_MIN_BASE: [i32; DOCTRINE_TRACKS] = [300, 300, 300, 2000];
const DOCTRINE_MIN_STEP: [i32; DOCTRINE_TRACKS] = [120, 120, 120, 900];
/// Research component of the cost ramp (FORGE is minerals-only ⇒ 0).
const DOCTRINE_RES_BASE: [i32; DOCTRINE_TRACKS] = [500, 500, 400, 0];
const DOCTRINE_RES_STEP: [i32; DOCTRINE_TRACKS] = [180, 180, 150, 0];
/// Per-level effect of the WEAPONS track: +1 flat damage. The effect is endless
/// by design (capped only at `DOCTRINE_LEVEL_CAP`); the steeply escalating
/// per-level research+minerals cost (see `ascend_cost`) is the sole brake — by the
/// time a level is cheap relative to income, the wave curve has long outgrown it.
const WEAPON_STEP: Fixed = Fixed::from_int(1);
/// Per-level effect of the ARMOR track: +0.5 flat mitigation (half-steps blunt
/// swarms without granting immunity — the ≥1-damage clamp still applies).
const ARMOR_STEP: Fixed = Fixed::from_ratio(1, 2);
/// Per-level effect of the VITALITY track: +8 shield-max.
const VITALITY_STEP: Fixed = Fixed::from_int(8);
/// Per-level FORGE bonuses: a small flat weapon AND armor buff, so a FORGE level
/// is a real purchase — and its steep, escalating minerals-only lump cost is the
/// bank-drainer. The AI keeps `ASCEND_MIN_RESERVE` in hand, so the surplus churns
/// down to a low equilibrium (continually buying levels) instead of sitting idle,
/// while never starving unit retraining.
const FORGE_WEAPON_STEP: Fixed = Fixed::from_ratio(1, 4);
const FORGE_ARMOR_STEP: Fixed = Fixed::from_ratio(1, 4);
/// Minerals granted for founding the Command Center adjacent to an Ore deposit —
/// the survey phase's premium-site payoff.
const FOUNDING_ORE_BONUS: Fixed = Fixed::from_int(200);
/// The AI only ascends with at least this much minerals in reserve (and era ≥ 1),
/// so the 120-tick golden run — which never reaches era 1 — never emits an Ascend
/// and the golden hash stays stable across future balance tuning of the sink.
const ASCEND_MIN_RESERVE: Fixed = Fixed::from_int(2000);

/// Per-player resources.
#[derive(Clone, Copy, Debug)]
struct Player {
    minerals: Fixed,
    /// Bitmask of researched tech ids (bit i = tech i complete).
    researched_techs: u32,
    /// In-progress research: (tech id, ticks remaining). One at a time.
    active_research: Option<(u32, u32)>,
    /// Current era index (0=Modern..3=Interstellar).
    era: u8,
    /// Accumulated alloys (third resource).
    alloys: Fixed,
    /// Accumulated Research pool (funds the tech tree).
    research: Fixed,
    /// Bitmask of chosen survival perks (bit i = perk i active).
    active_perks: u32,
    /// Level bought on each endless Ascendancy Doctrine track (see `DOC_*`).
    doctrine_levels: [u16; DOCTRINE_TRACKS],
    /// Bitmask of buildable building kinds (bit = `BuildingKind::index`). Tech
    /// research flips these on; the human starts with a tiny founding kit.
    unlocked_buildings: u16,
    /// Bitmask of trainable unit kinds (bit = `UnitKind::index`).
    unlocked_units: u16,
}

/// A player or AI input, applied at a tick boundary.
#[derive(Clone, Debug)]
pub enum Command {
    /// Construct a building on a tile (costs minerals; tile must be buildable).
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
    /// Queue a unit for training at a barracks (costs minerals).
    Train {
        /// Owning player.
        owner: PlayerId,
        /// The barracks entity.
        barracks: EntityId,
        /// What to train.
        kind: UnitKind,
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
    /// Begin researching a tech (costs minerals; needs a research lab; powered to progress).
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

/// Cost in `(minerals, research)` to buy the next level of doctrine `track` when
/// the current level is `level`. Linear ramp `base + step * level` — exact in
/// fixed-point, no float, so it stays clippy-clean and bit-identical everywhere.
fn ascend_cost(track: usize, level: u16) -> (Fixed, Fixed) {
    let l = Fixed::from_int(i32::from(level));
    let minerals =
        Fixed::from_int(DOCTRINE_MIN_BASE[track]) + Fixed::from_int(DOCTRINE_MIN_STEP[track]) * l;
    let research =
        Fixed::from_int(DOCTRINE_RES_BASE[track]) + Fixed::from_int(DOCTRINE_RES_STEP[track]) * l;
    (minerals, research)
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
pub struct Sim {
    tick: u64,
    rng: Rng,
    map: Map,
    players: [Player; PLAYER_COUNT],
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
    /// Endurance mode (survival): the run is won/lost only by the human's own
    /// Command Center surviving — destroying the alien beachhead does NOT win, so
    /// the player must outlast the waves rather than rush the spawner. Set at
    /// construction; it only changes [`Sim::winner`] (a query), not hashed state.
    survival: bool,
    balance: Balance,
    /// Transient render hint: (attacker, target) world positions of shots fired
    /// on the most recent combat tick. Deterministically derived, so it is not
    /// part of the state hash.
    attacks: Vec<(Vec2, Vec2)>,
}

const fn armor_of(balance: &Balance, kind: Kind) -> ArmorType {
    match kind {
        Kind::Unit(u) => balance.unit(u).armor,
        Kind::Building(b) => balance.building(b).armor,
    }
}

const fn attack_of(balance: &Balance, kind: Kind) -> Option<AttackProfile> {
    match kind {
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
            };
            0x200 | t
        }
    }
}

impl Sim {
    /// Creates a fresh world on `map`, with each player holding
    /// `starting_credits`, seeded for deterministic randomness.
    #[must_use]
    pub const fn new(map: Map, seed: u64, starting_credits: Fixed) -> Self {
        Self {
            tick: 0,
            rng: Rng::from_seed(seed),
            map,
            players: [Player {
                minerals: starting_credits,
                researched_techs: 0,
                active_research: None,
                era: 0,
                alloys: Fixed::ZERO,
                research: Fixed::ZERO,
                active_perks: 0,
                doctrine_levels: [0; DOCTRINE_TRACKS],
                unlocked_buildings: u16::MAX,
                unlocked_units: u16::MAX,
            }; PLAYER_COUNT],
            entities: Vec::new(),
            free: Vec::new(),
            waves: None,
            wave_count: 0,
            phase: GamePhase::Active,
            phase_started: 0,
            survival: false,
            balance: Balance::const_default(),
            attacks: Vec::new(),
        }
    }

    /// Starts the run in the Survey phase: no human base exists until a
    /// [`Command::FoundBase`] resolves; waves and defeat are held until then.
    pub const fn begin_survey(&mut self) {
        self.phase = GamePhase::Survey;
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
        self.players[p].unlocked_buildings = 0;
        self.players[p].unlocked_units = 0;
        for &b in buildings {
            self.players[p].unlocked_buildings |= 1 << b.index();
        }
        for &u in units {
            self.players[p].unlocked_units |= 1 << u.index();
        }
    }

    /// Whether `player` may build `kind` yet (for the shell command bar).
    #[must_use]
    pub fn building_unlocked(&self, player: PlayerId, kind: BuildingKind) -> bool {
        self.players[usize::from(player.0)].unlocked_buildings & (1 << kind.index()) != 0
    }

    /// Whether `player` may train `kind` yet (for the shell command bar).
    #[must_use]
    pub fn unit_unlocked(&self, player: PlayerId, kind: UnitKind) -> bool {
        self.players[usize::from(player.0)].unlocked_units & (1 << kind.index()) != 0
    }

    /// Test-only: instantly grant `id` (set the bit, advance era, apply unlocks),
    /// mirroring research completion. Lets tests satisfy DAG prereqs without
    /// stepping the whole chain.
    #[cfg(test)]
    fn grant_tech(&mut self, player: PlayerId, id: u32) {
        let p = usize::from(player.0);
        self.players[p].researched_techs |= 1u32 << id;
        if crate::game::tech::is_era_key(id) {
            self.players[p].era = (self.players[p].era + 1).min(3);
        }
        if let Some(def) = crate::game::tech::tech(id) {
            for unlock in def.unlocks {
                match *unlock {
                    crate::game::tech::TechUnlock::Building(b) => {
                        self.players[p].unlocked_buildings |= 1 << b.index();
                    }
                    crate::game::tech::TechUnlock::Unit(u) => {
                        self.players[p].unlocked_units |= 1 << u.index();
                    }
                }
            }
        }
    }

    /// Whether the run is still in the pre-founding Survey phase.
    #[must_use]
    pub const fn surveying(&self) -> bool {
        matches!(self.phase, GamePhase::Survey)
    }

    /// Enables endurance (survival) mode: the run ends only when the human's
    /// Command Center falls; the alien beachhead can't be rushed for a cheap win.
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

    /// A player's current minerals balance.
    #[must_use]
    pub fn minerals(&self, player: PlayerId) -> Fixed {
        self.players[usize::from(player.0)].minerals
    }

    /// A player's current alloys balance.
    #[must_use]
    pub fn alloys(&self, player: PlayerId) -> Fixed {
        self.players[usize::from(player.0)].alloys
    }

    /// The player's accumulated Research pool (funds the tech tree).
    #[must_use]
    pub fn research(&self, player: PlayerId) -> Fixed {
        self.players[usize::from(player.0)].research
    }

    /// A player's current level on Ascendancy Doctrine `track` (for the UI).
    /// Out-of-range tracks read as 0.
    #[must_use]
    pub fn doctrine_level(&self, player: PlayerId, track: u8) -> u16 {
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return 0;
        }
        self.players[usize::from(player.0)].doctrine_levels[t]
    }

    /// The `(minerals, research)` cost for `player` to buy the next level of
    /// doctrine `track` (for UI affordability hints). Out-of-range ⇒ zero.
    #[must_use]
    pub fn doctrine_cost(&self, player: PlayerId, track: u8) -> (Fixed, Fixed) {
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return (Fixed::ZERO, Fixed::ZERO);
        }
        ascend_cost(t, self.doctrine_level(player, track))
    }

    /// Mineral cost to construct a building (for UI affordability hints).
    #[must_use]
    pub const fn building_cost(&self, kind: BuildingKind) -> Fixed {
        self.balance.building(kind).cost
    }

    /// Mineral cost to train a unit (for UI affordability hints).
    #[must_use]
    pub const fn unit_cost(&self, kind: UnitKind) -> Fixed {
        self.balance.unit(kind).cost
    }

    /// Per-player research state: (researched bitmask, optional (tech id, ticks left)).
    #[must_use]
    pub fn research_state(&self, player: PlayerId) -> (u32, Option<(u32, u32)>) {
        let p = &self.players[usize::from(player.0)];
        (p.researched_techs, p.active_research)
    }

    /// Current era index for `player` (0 = Modern, 1 = Orbital, 2 = Interplanetary, 3 = Interstellar).
    #[must_use]
    pub fn player_era(&self, player: PlayerId) -> u8 {
        self.players[usize::from(player.0)].era
    }

    /// Whether the player has at least one alive research lab.
    #[must_use]
    pub fn has_research_lab(&self, player: PlayerId) -> bool {
        self.entities.iter().any(|e| {
            e.alive
                && e.owner == player
                && matches!(e.kind, Kind::Building(BuildingKind::ResearchLab))
        })
    }

    /// A player's `(produced, consumed)` power from living buildings. The player
    /// is in deficit (slowed economy/production) when consumed exceeds produced.
    #[must_use]
    pub fn power_balance(&self, player: PlayerId) -> (i32, i32) {
        let mut produced = 0;
        let mut consumed = 0;
        for e in &self.entities {
            if e.alive && e.owner == player {
                if let Kind::Building(b) = e.kind {
                    let st = self.balance.building(b);
                    produced += st.power_produced;
                    consumed += st.power_consumed;
                }
            }
        }
        (produced, consumed)
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
        let mut cap = SUPPLY_BASE;
        for e in &self.entities {
            if e.alive && e.owner == player {
                cap += match e.kind {
                    Kind::Building(BuildingKind::CommandCenter) => SUPPLY_PER_CC,
                    Kind::Building(BuildingKind::Barracks) => SUPPLY_PER_BARRACKS,
                    Kind::Building(BuildingKind::PowerPlant) => SUPPLY_PER_REACTOR,
                    _ => 0,
                };
            }
        }
        if self.players[usize::from(player.0)].active_perks & (1 << crate::game::perk::CONSCRIPTION)
            != 0
        {
            cap += 8;
        }
        cap
    }

    /// The player's active survival perks (bitmask).
    #[must_use]
    pub const fn perks(&self, player: PlayerId) -> u32 {
        self.players[player.0 as usize].active_perks
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
                    Kind::Unit(_) => used += 1,
                    Kind::Building(_) => used += e.build_queue.len() as u32,
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
            })
            .collect()
    }

    /// The winner: the only player still holding a Command Center, if exactly
    /// one does; otherwise `None` (game ongoing or no bases left).
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the index is a player slot < PLAYER_COUNT (2), so it fits u8"
    )]
    pub fn winner(&self) -> Option<PlayerId> {
        // Before founding, an absent base is a pending decision, not a defeat.
        if matches!(self.phase, GamePhase::Survey) {
            return None;
        }
        let mut has_cc = [false; PLAYER_COUNT];
        for e in &self.entities {
            if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
                has_cc[usize::from(e.owner.0)] = true;
            }
        }
        // Endurance mode: only the human (P0) losing their base ends the run —
        // razing the alien beachhead is not a win, so the waves are the real test.
        if self.survival {
            return if has_cc[0] { None } else { Some(PlayerId(1)) };
        }
        let alive: usize = has_cc.iter().filter(|&&b| b).count();
        if alive == 1 {
            has_cc.iter().position(|&b| b).map(|i| PlayerId(i as u8))
        } else {
            None
        }
    }

    /// A deterministic fingerprint of the entire world.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "queue length comfortably fits u64 for any real game"
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
        // Per-player fields: minerals, researched_techs, active_research,
        // era, alloys, research, active_perks, doctrine_levels — in this stable
        // order. Never reorder; appending is fine (and re-pins the golden hash).
        for p in &self.players {
            h.write_i64(p.minerals.to_bits());
            h.write_u64(u64::from(p.researched_techs));
            match p.active_research {
                Some((id, ticks)) => {
                    h.write_u64(1);
                    h.write_u64(u64::from(id));
                    h.write_u64(u64::from(ticks));
                }
                None => h.write_u64(0),
            }
            h.write_u64(u64::from(p.era));
            h.write_i64(p.alloys.to_bits());
            h.write_i64(p.research.to_bits());
            h.write_u64(u64::from(p.active_perks));
            for t in 0..DOCTRINE_TRACKS {
                h.write_u64(u64::from(p.doctrine_levels[t]));
            }
            h.write_u64(u64::from(p.unlocked_buildings));
            h.write_u64(u64::from(p.unlocked_units));
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
            h.write_u64(e.build_queue.len() as u64);
            for q in &e.build_queue {
                h.write_u64(unit_tag(*q));
            }
            h.write_u64(e.path.len() as u64);
            for &(wx, wy) in &e.path {
                h.write_u64(u64::from(wx));
                h.write_u64(u64::from(wy));
            }
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
        h.finish()
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
            path: Vec::new(),
            tile: Some((x, y)),
            build_queue: Vec::new(),
            build_progress: 0,
            kills: 0,
            rank: 0,
            ability_cd: 0,
            stun_ticks: 0,
            stun_immunity: 0,
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
            path: Vec::new(),
            tile: None,
            build_queue: Vec::new(),
            build_progress: 0,
            kills: 0,
            rank: 0,
            ability_cd: 0,
            stun_ticks: 0,
            stun_immunity: 0,
        })
    }

    /// Advances the simulation one fixed tick.
    pub fn step(&mut self, commands: &[Command]) {
        for command in commands {
            self.apply_command(command);
        }
        let powered = self.run_economy();
        self.run_research(powered);
        self.run_production(powered);
        self.run_waves();
        self.run_movement();
        self.run_shields();
        self.run_combat();
        self.run_status();
        self.clear_dead();
        self.tick += 1;
    }

    /// Ticks down per-entity ability cooldowns and EMP stuns. Runs at the end of
    /// the tick, so an effect applied this tick is felt this tick and a
    /// `duration`-tick stun suppresses exactly `duration` ticks of action.
    fn run_status(&mut self) {
        for e in &mut self.entities {
            if !e.alive {
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
        let size = cfg.base_size + cfg.growth * w;
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
                self.order_unit_to(spawned.0 as usize, t);
            }
        }
        // Boss: a Capital ship joins every 5th wave once escalation is underway.
        if cfg.escalate && (w + 1).is_multiple_of(5) {
            let spawned = self.add_unit(cfg.attacker, UnitKind::Capital, cfg.spawn);
            if let Some(t) = target {
                self.order_unit_to(spawned.0 as usize, t);
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
            let lv = self.players[p].doctrine_levels[track];
            self.players[p].doctrine_levels[track] = (lv + 1).min(DOCTRINE_LEVEL_CAP);
        }
        self.wave_count += 1;
    }

    /// Sets a unit's move target and computes its A* path. Shared by the Move
    /// command and wave spawning. If the target tile is blocked (e.g. it *is* a
    /// building like the enemy Command Center), the unit paths to the nearest
    /// passable tile beside it and then closes the last step directly — so
    /// "attack the base" actually routes there.
    fn order_unit_to(&mut self, idx: usize, target: Vec2) {
        let owner = self.entities[idx].owner;
        if is_air_of(&self.balance, self.entities[idx].kind) || self.player_has_antigrav(owner) {
            // Air units and anti-grav units fly straight to the target, ignoring terrain.
            let e = &mut self.entities[idx];
            e.move_target = Some(target);
            e.path = Vec::new();
            return;
        }
        let start = self.world_to_tile(self.entities[idx].pos);
        let goal_tile = self.world_to_tile(target);
        let goal = if self.is_passable_tile(goal_tile) {
            goal_tile
        } else {
            match self.nearest_passable_tile(goal_tile) {
                Some(tile) => tile,
                None => return,
            }
        };
        if let Some(path) = find_path(&self.map, start, goal) {
            let e = &mut self.entities[idx];
            e.move_target = Some(target);
            e.path = path;
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

    fn apply_command(&mut self, command: &Command) {
        match *command {
            Command::Build { owner, kind, x, y } => {
                let buildable = self
                    .map
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.buildable);
                let cost = self.balance.building(kind).cost;
                let p = usize::from(owner.0);
                let unlocked = self.players[p].unlocked_buildings & (1 << kind.index()) != 0;
                if unlocked && buildable && self.players[p].minerals >= cost {
                    self.players[p].minerals = self.players[p].minerals - cost;
                    self.add_building(owner, kind, x, y);
                }
            }
            Command::Train {
                owner,
                barracks,
                kind,
            } => {
                if matches!(kind, UnitKind::Capital) && self.players[usize::from(owner.0)].era < 3 {
                    return;
                }
                let cost = self.balance.unit(kind).cost;
                let am_cost = if matches!(kind, UnitKind::Capital) {
                    CAPITAL_ANTIMATTER_COST
                } else {
                    Fixed::ZERO
                };
                let p = usize::from(owner.0);
                let ok = self.entity(barracks).is_some_and(|e| {
                    e.alive
                        && e.owner == owner
                        && matches!(e.kind, Kind::Building(BuildingKind::Barracks))
                });
                let has_supply = self.supply_used(owner) < self.supply_cap(owner);
                let unlocked = self.players[p].unlocked_units & (1 << kind.index()) != 0;
                if ok
                    && unlocked
                    && has_supply
                    && self.players[p].minerals >= cost
                    && self.players[p].alloys >= am_cost
                {
                    self.players[p].minerals = self.players[p].minerals - cost;
                    self.players[p].alloys = self.players[p].alloys - am_cost;
                    if let Some(e) = self.entities.get_mut(barracks.0 as usize) {
                        e.build_queue.push(kind);
                    }
                }
            }
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
                    self.order_unit_to(idx, target);
                }
            }
            Command::Research { owner, tech_id } => self.apply_research(owner, tech_id),
            Command::ChoosePerk { owner, perk } => {
                if perk < crate::game::perk::PERK_COUNT {
                    self.players[usize::from(owner.0)].active_perks |= 1u32 << perk;
                }
            }
            Command::Ascend { owner, track } => self.apply_ascend(owner, track),
            Command::FoundBase { owner, x, y } => self.apply_found_base(owner, x, y),
            Command::UseAbility {
                owner,
                unit,
                target,
            } => self.apply_use_ability(owner, unit, target),
        }
    }

    /// Casts `unit`'s ability at `target`: validate (alive, owned, carries an
    /// ability, off cooldown, not stunned, target in range), resolve the effect
    /// instantly over the entity list in index order, then start the cooldown.
    /// Deterministic — fixed magnitudes, no RNG, order-independent per cast.
    fn apply_use_ability(&mut self, owner: PlayerId, unit: EntityId, target: Vec2) {
        use crate::game::ability::{ability_for, def, AbilityKind};
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
        if matches!(self.phase, GamePhase::Survey) {
            return; // can't research before founding a base
        }
        let p = usize::from(owner.0);
        let Some(def) = crate::game::tech::tech(tech_id) else {
            return;
        };
        let mask = self.players[p].researched_techs;
        let already = mask & (1u32 << tech_id) != 0;
        let busy = self.players[p].active_research.is_some();
        let prereq_ok = def.prereqs.iter().all(|&r| mask & (1u32 << r) != 0);
        let fork_ok =
            crate::game::tech::excludes(tech_id).is_none_or(|other| mask & (1u32 << other) == 0);
        let mineral_paid = def.tier == 0;
        let affordable = if mineral_paid {
            self.players[p].minerals >= def.cost
        } else {
            self.has_research_lab(owner) && self.players[p].research >= def.cost
        };
        if !already && !busy && prereq_ok && fork_ok && affordable {
            if mineral_paid {
                self.players[p].minerals = self.players[p].minerals - def.cost;
            } else {
                self.players[p].research = self.players[p].research - def.cost;
            }
            self.players[p].active_research = Some((tech_id, def.duration));
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
        if !buildable {
            return;
        }
        self.add_building(owner, BuildingKind::CommandCenter, x, y);
        self.phase = GamePhase::Active;
        self.phase_started = self.tick;
        let near_ore = self.map.deposits().any(|(dx, dy, d)| {
            d.kind == crate::game::map::DepositKind::Ore
                && crate::game::hex::distance((x, y), (dx, dy)) <= 1
        });
        if near_ore {
            let p = usize::from(owner.0);
            self.players[p].minerals = self.players[p].minerals + FOUNDING_ORE_BONUS;
        }
    }

    /// Buys the next level of doctrine `track` for `owner`, if unlocked and
    /// affordable. FORGE (the minerals-only track) needs no lab; the research
    /// tracks require a Research Lab. Validate-then-spend, mirroring `Research`.
    fn apply_ascend(&mut self, owner: PlayerId, track: u8) {
        let t = usize::from(track);
        if t >= DOCTRINE_TRACKS {
            return;
        }
        let p = usize::from(owner.0);
        let level = self.players[p].doctrine_levels[t];
        if level >= DOCTRINE_LEVEL_CAP {
            return;
        }
        let (min_cost, res_cost) = ascend_cost(t, level);
        let lab_ok = t == DOC_FORGE || self.has_research_lab(owner);
        if lab_ok && self.players[p].minerals >= min_cost && self.players[p].research >= res_cost {
            self.players[p].minerals = self.players[p].minerals - min_cost;
            self.players[p].research = self.players[p].research - res_cost;
            self.players[p].doctrine_levels[t] = (level + 1).min(DOCTRINE_LEVEL_CAP);
        }
    }

    fn world_to_tile(&self, p: Vec2) -> (u16, u16) {
        crate::game::hex::from_world(p, self.map.width(), self.map.height())
    }

    /// Sum of researched-tech bonuses for `player` in `branch`.
    fn branch_bonus(&self, player: PlayerId, branch: crate::game::tech::TechBranch) -> Fixed {
        let mask = self.players[usize::from(player.0)].researched_techs;
        let mut total = Fixed::ZERO;
        let mut i = 0u32;
        while (i as usize) < crate::game::tech::TECH_COUNT {
            if mask & (1u32 << i) != 0 {
                let t = crate::game::tech::TECHS[i as usize];
                if t.branch == branch {
                    total = total + t.bonus;
                }
            }
            i += 1;
        }
        total
    }
    fn player_weapon_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Weapons) + self.doctrine_weapon_bonus(p)
    }
    fn player_armor_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Armor) + self.doctrine_armor_bonus(p)
    }
    fn player_economy_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Economy)
    }
    fn player_mobility_bonus(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Mobility)
    }
    fn player_shield_max(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Shields) + self.doctrine_shield_bonus(p)
    }
    /// Flat weapon-damage bonus from the doctrine tracks (Weapons + Forge).
    fn doctrine_weapon_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.players[usize::from(p.0)].doctrine_levels;
        WEAPON_STEP * Fixed::from_int(i32::from(lv[DOC_WEAPONS]))
            + FORGE_WEAPON_STEP * Fixed::from_int(i32::from(lv[DOC_FORGE]))
    }
    /// Flat armor-mitigation bonus from the doctrine tracks (Armor + Forge).
    fn doctrine_armor_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.players[usize::from(p.0)].doctrine_levels;
        ARMOR_STEP * Fixed::from_int(i32::from(lv[DOC_ARMOR]))
            + FORGE_ARMOR_STEP * Fixed::from_int(i32::from(lv[DOC_FORGE]))
    }
    /// Shield-max bonus from the Vitality doctrine track.
    fn doctrine_shield_bonus(&self, p: PlayerId) -> Fixed {
        let lv = &self.players[usize::from(p.0)].doctrine_levels;
        VITALITY_STEP * Fixed::from_int(i32::from(lv[DOC_VITALITY]))
    }
    /// Public accessor for the UI and tests outside the module.
    #[must_use]
    pub fn shield_max(&self, player: PlayerId) -> Fixed {
        self.player_shield_max(player)
    }
    fn player_has_antigrav(&self, p: PlayerId) -> bool {
        let mask = self.players[usize::from(p.0)].researched_techs;
        (0..crate::game::tech::TECH_COUNT).any(|i| {
            mask & (1u32 << i) != 0
                && matches!(
                    crate::game::tech::TECHS[i].branch,
                    crate::game::tech::TechBranch::AntiGrav
                )
        })
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
        let max: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_shield_max(PlayerId(u8::try_from(p).unwrap())));
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

    fn run_economy(&mut self) -> [bool; PLAYER_COUNT] {
        let mut produced = [0i32; PLAYER_COUNT];
        let mut consumed = [0i32; PLAYER_COUNT];
        let mut income = [Fixed::ZERO; PLAYER_COUNT];
        let mut am_income = [Fixed::ZERO; PLAYER_COUNT];
        let mut research = [Fixed::ZERO; PLAYER_COUNT];
        for e in &self.entities {
            if !e.alive {
                continue;
            }
            if let Kind::Building(b) = e.kind {
                let st = self.balance.building(b);
                let p = usize::from(e.owner.0);
                produced[p] += st.power_produced;
                consumed[p] += st.power_consumed;
                income[p] = income[p] + st.credit_income;
                am_income[p] = am_income[p] + st.antimatter_income;
                research[p] = research[p] + st.research_income;
            }
        }
        let mut powered = [false; PLAYER_COUNT];
        for p in 0..PLAYER_COUNT {
            powered[p] = produced[p] >= consumed[p];
            // Power is a gradient, not a switch: a deficit scales income by the
            // fraction of demand actually met, floored at 1/2. Meeting more of
            // your demand is rewarded smoothly instead of an all-or-nothing cliff.
            let half = Fixed::from_ratio(1, 2);
            let factor = if powered[p] || consumed[p] <= 0 {
                Fixed::ONE
            } else {
                let frac = Fixed::from_ratio(i64::from(produced[p]), i64::from(consumed[p]));
                if frac < half {
                    half
                } else {
                    frac
                }
            };
            let econ = self.player_economy_bonus(PlayerId(u8::try_from(p).unwrap()));
            // Logistics perk: +50% credit income.
            let mut credit_income = income[p] + econ;
            if self.players[p].active_perks & (1 << crate::game::perk::LOGISTICS) != 0 {
                credit_income = credit_income * Fixed::from_ratio(3, 2);
            }
            self.players[p].minerals = self.players[p].minerals + credit_income * factor;
            self.players[p].alloys = self.players[p].alloys + am_income[p] * factor;
            self.players[p].research = self.players[p].research + research[p] * factor;
        }
        // Extractors mine the deposit they stand on (throttled by power like income).
        let mut to_mine: alloc::vec::Vec<(u16, u16, u8, i32)> = alloc::vec::Vec::new();
        for e in &self.entities {
            if !e.alive {
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
            let Some(dep) = self.map.deposit(tx, ty) else {
                continue;
            };
            let p = usize::from(owner);
            let throttle = if powered[p] { rate } else { rate / 2 };
            let want = u32::try_from(throttle.max(0)).unwrap_or(0);
            let mined = self.map.mine(tx, ty, want);
            let amount = Fixed::from_int(i32::try_from(mined).unwrap_or(0));
            match dep.kind {
                crate::game::map::DepositKind::Ore => {
                    self.players[p].minerals = self.players[p].minerals + amount;
                }
                crate::game::map::DepositKind::Alloy => {
                    self.players[p].alloys = self.players[p].alloys + amount;
                }
            }
        }
        powered
    }

    /// Advances each player's in-progress research, but only while powered.
    ///
    /// Runs every tick after `run_economy`, so the tick on which a research is
    /// started also counts as its first tick of progress: a `duration`-tick tech
    /// completes after `duration` powered ticks counting the start tick.
    fn run_research(&mut self, powered: [bool; PLAYER_COUNT]) {
        // No research before a base is founded (a base-less player reads as
        // "powered" since 0 >= 0, so guard the phase explicitly).
        if matches!(self.phase, GamePhase::Survey) {
            return;
        }
        for (player, &is_powered) in self.players.iter_mut().zip(powered.iter()) {
            if !is_powered {
                continue;
            }
            if let Some((id, ticks)) = player.active_research {
                if ticks <= 1 {
                    player.researched_techs |= 1u32 << id;
                    player.active_research = None;
                    if crate::game::tech::is_era_key(id) {
                        player.era = (player.era + 1).min(3);
                    }
                    // Research opens doors: flip on the buildings/units it unlocks.
                    if let Some(def) = crate::game::tech::tech(id) {
                        for unlock in def.unlocks {
                            match *unlock {
                                crate::game::tech::TechUnlock::Building(b) => {
                                    player.unlocked_buildings |= 1 << b.index();
                                }
                                crate::game::tech::TechUnlock::Unit(u) => {
                                    player.unlocked_units |= 1 << u.index();
                                }
                            }
                        }
                    }
                } else {
                    player.active_research = Some((id, ticks - 1));
                }
            }
        }
    }

    fn run_production(&mut self, powered: [bool; PLAYER_COUNT]) {
        let mut spawns: Vec<(PlayerId, UnitKind, Vec2)> = Vec::new();
        for e in &mut self.entities {
            if !e.alive || !matches!(e.kind, Kind::Building(BuildingKind::Barracks)) {
                continue;
            }
            if !powered[usize::from(e.owner.0)] {
                continue;
            }
            if let Some(&front) = e.build_queue.first() {
                e.build_progress += 1;
                if e.build_progress >= self.balance.unit(front).build_time {
                    e.build_progress = 0;
                    e.build_queue.remove(0);
                    let pos = e.pos + Vec2::new(Fixed::ONE, Fixed::ZERO);
                    spawns.push((e.owner, front, pos));
                }
            }
        }
        for (owner, kind, pos) in spawns {
            self.add_unit(owner, kind, pos);
        }
    }

    fn run_movement(&mut self) {
        let mobility: [Fixed; PLAYER_COUNT] = core::array::from_fn(|p| {
            self.player_mobility_bonus(PlayerId(u8::try_from(p).unwrap()))
        });
        for e in &mut self.entities {
            if !e.alive {
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
            let speed = uk.stats().speed + mobility[usize::from(e.owner.0)];
            // Head to the next waypoint, or straight to the target once the path
            // is exhausted.
            let subgoal = e
                .path
                .first()
                .map_or(target, |&(wx, wy)| tile_center(wx, wy));
            let dir = subgoal - e.pos;
            let dist = dir.length();
            if dist <= speed {
                e.pos = subgoal;
                if e.path.is_empty() {
                    e.move_target = None;
                } else {
                    e.path.remove(0);
                }
            } else {
                e.pos = e.pos + dir.scale(speed / dist);
            }
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
        let snap: Vec<(bool, u8, Vec2, ArmorType, bool, Fixed)> = self
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
        // rather than O(n^2). The cell size is >= the largest attack range, so a
        // 3x3 cell query around an attacker contains every in-range enemy.
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
        let weapon: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_weapon_bonus(PlayerId(u8::try_from(p).unwrap())));
        let armor: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_armor_bonus(PlayerId(u8::try_from(p).unwrap())));
        let era_dmg: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| era_damage_factor(self.players[p].era));
        // Survival perks: Overcharge scales outgoing damage; Bulwark adds flat
        // mitigation. No perks chosen ⇒ ONE / ZERO ⇒ base combat is unchanged.
        let perk_dmg: [Fixed; PLAYER_COUNT] = core::array::from_fn(|p| {
            if self.players[p].active_perks & (1 << crate::game::perk::OVERCHARGE) != 0 {
                Fixed::from_ratio(5, 4)
            } else {
                Fixed::ONE
            }
        });
        let perk_mit: [Fixed; PLAYER_COUNT] = core::array::from_fn(|p| {
            if self.players[p].active_perks & (1 << crate::game::perk::BULWARK) != 0 {
                Fixed::from_int(2)
            } else {
                Fixed::ZERO
            }
        });

        // (target index, attacker index, damage, pierces-shields).
        let mut damage: Vec<(usize, usize, Fixed, bool)> = Vec::new();
        let mut lines: Vec<(Vec2, Vec2)> = Vec::new();
        let mut candidates: Vec<usize> = Vec::new();
        for (i, e) in self.entities.iter_mut().enumerate() {
            if !e.alive {
                continue;
            }
            // EMP-stunned entities can't fire (their weapon stays frozen too).
            if e.stun_ticks > 0 {
                continue;
            }
            let Some(profile) = attack_of(&self.balance, e.kind) else {
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

            let range_sq = profile.range * profile.range;
            // Target the NEAREST valid enemy (preserves lane/base pressure so
            // matches resolve), breaking distance ties by LOWEST HP — a focus-fire
            // tie-break that secures kills when several foes are equidistant. Ties
            // resolve to the lowest index (candidates are scanned in ascending
            // index order and we only replace on a strict improvement), keeping
            // the simulation bit-for-bit deterministic.
            let mut best: Option<(usize, Fixed, Fixed)> = None;
            for &j in &candidates {
                let t = snap[j];
                if t.1 == e.owner.0 {
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
                let mult = damage_multiplier(profile.damage_type, snap[j].3);
                let raw = profile.damage * mult * era_dmg[usize::from(e.owner.0)]
                    + weapon[usize::from(e.owner.0)];
                let dmg = raw * veterancy_factor(e.rank) * perk_dmg[usize::from(e.owner.0)];
                let pierces = matches!(profile.damage_type, DamageType::AntiArmor);
                damage.push((j, i, dmg, pierces));
                lines.push((e.pos, snap[j].2));
                e.cooldown = profile.period;
            }
        }
        #[allow(
            clippy::cast_possible_truncation,
            reason = "tick fits u32 for any real game"
        )]
        let tick = self.tick as u32;
        for (j, attacker, dmg, pierces) in damage {
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
                let a = &mut self.entities[attacker];
                a.kills += 1;
                a.rank = rank_for_kills(a.kills);
            }
        }
        self.attacks = lines;
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
        self.free.extend(freed_slots);
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
        let minerals = self.minerals(player);
        let enemy_cc = self.command_center_tile(PlayerId(1 - player.0));

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
                        if minerals >= self.building_cost(kind) {
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
                    if minerals >= self.building_cost(kind) {
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
            && minerals >= self.building_cost(BuildingKind::AaTurret)
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
            && minerals >= self.building_cost(BuildingKind::AntimatterPlant)
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
        if !building_this_tick && minerals >= Fixed::from_int(500) {
            use crate::game::map::DepositKind;
            let (produced, consumed) = self.power_balance(player);
            let reactors = self.count_alive_buildings(player, BuildingKind::PowerPlant);
            let barracks = self.count_alive_buildings(player, BuildingKind::Barracks);
            let ore_extractors = self.active_extractors_on(player, DepositKind::Ore);
            let alloy_extractors = self.active_extractors_on(player, DepositKind::Alloy);
            let at_cap = self.supply_used(player) + 2 >= self.supply_cap(player);
            let near = self.find_buildable_near(cc_tile, enemy_cc);
            let afford = |k| minerals >= self.building_cost(k);

            let action: Option<(BuildingKind, u16, u16)> = (produced <= consumed
                && reactors < MAX_AI_REACTORS
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
                    && minerals >= self.balance.unit(UnitKind::Capital).cost
                    && self.alloys(player) >= CAPITAL_ANTIMATTER_COST
                {
                    UnitKind::Capital
                } else {
                    UnitKind::Infantry
                };
                if minerals >= self.balance.unit(kind).cost {
                    cmds.push(Command::Train {
                        owner: player,
                        barracks,
                        kind,
                    });
                }
            }
        }

        // Ascendancy Doctrines: once established (era ≥ 1) and holding a Minerals
        // reserve, convert the surplus into army QUALITY. The minerals-only Forge
        // track always runs (it bleeds the standing Minerals bank); the research-
        // costed quality tracks only run once the finite tech tree is exhausted —
        // era keys and Anti-Grav are worth more than incremental doctrine levels,
        // so research is reserved for them while any finite tech is still pending.
        // The AI may also Build/Train this tick, so gate on the minerals that would
        // be LEFT after those commits (`avail`) — never queueing an Ascend the
        // apply step would drop, while still ascending every tick the surplus
        // allows. The era ≥ 1 gate keeps the era-0 golden run from ever emitting an
        // Ascend. Pure, row-major, no RNG.
        let spent_this_tick = cmds.iter().fold(Fixed::ZERO, |acc, c| match *c {
            Command::Build { kind, .. } => acc + self.building_cost(kind),
            Command::Train { kind, .. } => acc + self.balance.unit(kind).cost,
            _ => acc,
        });
        let avail = minerals - spent_this_tick;
        if self.player_era(player) >= 1 && avail >= ASCEND_MIN_RESERVE {
            let (rmask, active) = self.research_state(player);
            // The tree is "open" while any non-fork tech (tiers 0..=3) is still
            // eligible+unbought — research stays reserved for the finite tree until
            // it is exhausted, then funds the endless doctrines.
            let tree_open = active.is_some()
                || crate::game::tech::TECHS.iter().any(|def| {
                    let done = rmask & (1u32 << def.id) != 0;
                    let prereq_ok = def.prereqs.iter().all(|&r| rmask & (1u32 << r) != 0);
                    def.tier < 4 && !done && prereq_ok
                });
            // Track order: Forge (3) first to drain Minerals, then the research
            // tracks Weapons(0)/Armor(1)/Vitality(2). u8 ids avoid a fallible cast.
            let tracks: &[u8] = if tree_open { &[3] } else { &[3, 0, 1, 2] };
            for &track_id in tracks {
                if self.doctrine_level(player, track_id) >= DOCTRINE_LEVEL_CAP {
                    continue;
                }
                let (min_cost, res_cost) = self.doctrine_cost(player, track_id);
                let is_forge = usize::from(track_id) == DOC_FORGE;
                let lab_ok = is_forge || self.has_research_lab(player);
                let res_ok = is_forge || self.research(player) >= res_cost;
                if lab_ok && avail >= min_cost && res_ok {
                    cmds.push(Command::Ascend {
                        owner: player,
                        track: track_id,
                    });
                    break;
                }
            }
        }

        // Research: with no active research, start the first eligible + affordable
        // tech in a fixed priority order — the unlock spine first (Mobilization →
        // Directed Energy → era keys), so the AI opens its own kit, then the stat
        // riders. Tier-0 techs are minerals-paid (no lab); later tiers need a lab
        // and the Research pool. Deterministic, prereq-gated, no RNG.
        let (researched_mask, active_research) = self.research_state(player);
        if active_research.is_none() {
            // Spine (6,0,10 unlock army/turret/lab + era 1) → expansion unlocks
            // (1,8 = Tank/Lancer) → era 2 (11) → Heli(2) → econ/defense riders →
            // era 3 (12 = Antimatter+Capital) → late riders → Anti-Grav(16).
            const RESEARCH_PRIORITY: [u32; 17] =
                [6, 0, 10, 1, 8, 11, 2, 7, 3, 13, 4, 14, 12, 5, 15, 9, 16];
            for tech_id in RESEARCH_PRIORITY {
                let def = crate::game::tech::TECHS[tech_id as usize];
                let researched = researched_mask & (1u32 << tech_id) != 0;
                let prereq_ok = def
                    .prereqs
                    .iter()
                    .all(|&r| researched_mask & (1u32 << r) != 0);
                let affordable = if def.tier == 0 {
                    self.minerals(player) >= def.cost
                } else {
                    self.has_research_lab(player) && self.research(player) >= def.cost
                };
                if !researched && prereq_ok && affordable {
                    cmds.push(Command::Research {
                        owner: player,
                        tech_id,
                    });
                    break;
                }
            }
        }

        // Periodically push idle units toward the enemy base. Re-issuing a Move
        // (and thus running A*) for every idle unit every tick is the classic RTS
        // perf trap; throttling by tick keeps pathfinding cheap and is still fully
        // deterministic.
        if self.tick.is_multiple_of(MOVE_REISSUE_PERIOD) {
            if let Some(target) = self.enemy_command_center_pos(player) {
                for unit in self.idle_units(player) {
                    cmds.push(Command::Move {
                        owner: player,
                        unit,
                        target,
                    });
                }
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

    fn enemy_command_center_pos(&self, player: PlayerId) -> Option<Vec2> {
        self.command_center_pos(PlayerId(1 - player.0))
    }

    fn has_building(&self, player: PlayerId, kind: BuildingKind) -> bool {
        self.entities
            .iter()
            .any(|e| e.alive && e.owner == player && e.kind == Kind::Building(kind))
    }

    fn enemy_has_air(&self, player: PlayerId) -> bool {
        let enemy = PlayerId(1 - player.0);
        self.entities
            .iter()
            .any(|e| e.alive && e.owner == enemy && is_air_of(&self.balance, e.kind))
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
                    && matches!(e.kind, Kind::Unit(_))
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
mod tests {
    use super::{
        ascend_cost, BuildingKind, Command, EntityId, EntityKindView, PlayerId, Sim, UnitKind,
        WaveConfig,
    };
    use crate::fixed::Fixed;
    use crate::game::map::Map;
    use crate::vec::Vec2;

    fn f(n: i32) -> Fixed {
        Fixed::from_int(n)
    }
    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(f(x), f(y))
    }
    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    #[test]
    fn new_sim_has_starting_credits_and_no_winner() {
        let s = Sim::new(Map::new(16, 16), 1, f(500));
        assert_eq!(s.minerals(P0), f(500));
        assert_eq!(s.minerals(P1), f(500));
        assert_eq!(s.winner(), None);
        assert_eq!(s.tick(), 0);
    }

    #[test]
    fn refinery_on_deposit_mines_minerals_when_powered() {
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
        let before = s.minerals(P0).to_bits();
        s.step(&[]);
        // Refinery mine_rate is 5/tick while powered.
        assert!(
            s.minerals(P0).to_bits() > before,
            "refinery should mine minerals from ore deposit"
        );
    }

    #[test]
    fn power_deficit_halves_mining() {
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
        // Refinery consumes 20 but there is no power plant -> deficit -> mine_rate halved.
        s.add_building(P0, BuildingKind::Refinery, 5, 1);
        s.step(&[]);
        // mine_rate 2, throttled to 2/2 = 1 when unpowered.
        assert_eq!(s.minerals(P0), f(1));
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
        assert_eq!(s.minerals(P0), f(900)); // 1000 - 100
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
        assert_eq!(s.minerals(P0), f(50));
        assert!(s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn training_spawns_a_unit_after_build_time() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 1);
        let units_before = s.unit_count(P0);
        s.step(&[Command::Train {
            owner: P0,
            barracks,
            kind: UnitKind::Infantry,
        }]);
        assert_eq!(s.minerals(P0), f(950)); // charged immediately
                                            // Infantry build time is 90 ticks; not yet spawned at 89.
        for _ in 0..88 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P0), units_before);
        s.step(&[]); // 90th tick
        assert_eq!(s.unit_count(P0), units_before + 1);
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
        assert_eq!(s.state_hash(), 2_767_408_481_316_525_773);
    }

    #[test]
    fn doctrine_fork_locks_out_the_counterpart() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 6, 2);
        for id in [6u32, 0, 10, 1, 3, 13, 14, 11, 12] {
            s.grant_tech(P0, id); // satisfy Assault Doctrine (17)'s prereq [12]
        }
        // Warm up the research pool: Assault Doctrine costs 900, lab makes 2/tick => 450 ticks.
        for _ in 0..500 {
            s.step(&[]);
        }
        // Research Assault Doctrine (17) to completion.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 17,
        }]);
        for _ in 0..1900 {
            s.step(&[]);
        }
        assert!(
            s.research_state(P0).0 & (1 << 17) != 0,
            "assault doctrine should be researched"
        );
        // Fortress Doctrine (18) is now permanently locked out.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 18,
        }]);
        assert!(
            s.research_state(P0).1.is_none(),
            "fortress doctrine should be rejected (fork already chosen)"
        );
        assert!(s.research_state(P0).0 & (1 << 18) == 0);
    }

    #[test]
    fn supply_cap_limits_trained_units() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let b = s.add_building(P0, BuildingKind::Barracks, 4, 2);
        let cap = s.supply_cap(P0); // 10 base + 6 CC + 5 barracks
        assert_eq!(cap, 21);
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
        // Track 0 (Weapons): minerals 300 + 120*L, research 500 + 180*L.
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
        // Track 3 (Forge): minerals-only — 2000 + 900*L, research always 0.
        let (m3, r3) = ascend_cost(3, 2);
        assert_eq!(
            (m3.to_bits(), r3.to_bits()),
            (f(3800).to_bits(), f(0).to_bits())
        );
    }

    #[test]
    fn ascend_charges_pools_and_increments_level() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        // Warm the research pool (lab makes 2/tick while powered): two Weapons
        // levels cost 500 + 680 research, so warm well past that.
        for _ in 0..800 {
            s.step(&[]);
        }
        // No deposits + CC credit_income 0 ⇒ minerals never grow, so the minerals
        // delta is exactly the Ascend cost.
        let m_before = s.minerals(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(s.doctrine_level(P0, 0), 1);
        assert_eq!(
            (m_before - s.minerals(P0)).to_bits(),
            f(300).to_bits(),
            "first Weapons level should cost 300 minerals"
        );
        let m_before2 = s.minerals(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(s.doctrine_level(P0, 0), 2);
        assert_eq!(
            (m_before2 - s.minerals(P0)).to_bits(),
            f(420).to_bits(),
            "second Weapons level should cost 420 minerals (ramp)"
        );
    }

    #[test]
    fn ascend_is_gated_by_lab_and_pools() {
        // No lab + no research ⇒ a research track is a no-op, but Forge still works.
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
            "Forge (minerals-only) needs no lab"
        );
        // A lab but an empty research pool still blocks a research track.
        let mut poor = Sim::new(Map::new(20, 20), 1, f(100_000));
        poor.add_building(P0, BuildingKind::ResearchLab, 2, 2);
        poor.step(&[Command::Ascend {
            owner: P0,
            track: 0,
        }]);
        assert_eq!(
            poor.doctrine_level(P0, 0),
            0,
            "no research ⇒ Weapons track blocked even with a lab"
        );
        // An out-of-range track id is ignored.
        poor.step(&[Command::Ascend {
            owner: P0,
            track: 99,
        }]);
        assert_eq!(poor.doctrine_level(P0, 99), 0);
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
    fn forge_track_is_minerals_only_and_ramps() {
        // Forge needs no lab and never touches the research pool; its steep
        // minerals lump cost (2000, then 2900) is the bank-drainer.
        let mut s = Sim::new(Map::new(20, 20), 1, f(100_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        let r_before = s.research(P0);
        let m0 = s.minerals(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(s.doctrine_level(P0, 3), 1, "Forge needs no lab");
        assert_eq!(
            (m0 - s.minerals(P0)).to_bits(),
            f(2000).to_bits(),
            "first Forge level costs 2000 minerals"
        );
        assert_eq!(
            s.research(P0).to_bits(),
            r_before.to_bits(),
            "Forge must not spend research"
        );
        let m1 = s.minerals(P0);
        s.step(&[Command::Ascend {
            owner: P0,
            track: 3,
        }]);
        assert_eq!(s.doctrine_level(P0, 3), 2);
        assert_eq!(
            (m1 - s.minerals(P0)).to_bits(),
            f(2900).to_bits(),
            "second Forge level costs 2900 minerals (ramp)"
        );
    }

    #[test]
    fn doctrine_levels_are_hashed() {
        let a = Sim::new(Map::new(8, 8), 1, f(0));
        let mut b = Sim::new(Map::new(8, 8), 1, f(0));
        b.players[0].doctrine_levels[2] = 1;
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
    fn ai_queues_no_unaffordable_minerals_spend() {
        // Across a full survival run (where the AI reaches era ≥ 1 and ascends), the
        // AI may queue a Build/Train AND an Ascend in one tick, but their combined
        // minerals cost must never exceed the balance — otherwise the apply step
        // silently drops the later command. The post-build `avail` gate enforces it.
        let mut s = crate::game::scenario::survival(3);
        let mut saw_ascend = false;
        for _ in 0..12_000u32 {
            let cmds = s.ai_commands(P0);
            let total: i64 = cmds
                .iter()
                .map(|c| match *c {
                    Command::Build { kind, .. } => s.building_cost(kind).to_bits(),
                    Command::Train { kind, .. } => s.unit_cost(kind).to_bits(),
                    Command::Ascend { track, .. } => s.doctrine_cost(P0, track).0.to_bits(),
                    _ => 0,
                })
                .sum();
            assert!(
                total <= s.minerals(P0).to_bits(),
                "AI queued minerals-spends ({total} bits) exceeding its balance"
            );
            saw_ascend |= cmds.iter().any(|c| matches!(c, Command::Ascend { .. }));
            s.step(&cmds);
            if s.winner().is_some() {
                break;
            }
        }
        assert!(
            saw_ascend,
            "the AI should ascend at least once over a survival run"
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
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
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
            "AI should mine alloy and field a Capital ship by era 3"
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
    fn survival_is_endurance_not_a_rush_win() {
        // In normal mode, being the only side with a Command Center is a win.
        let mut normal = Sim::new(Map::new(10, 10), 1, f(0));
        normal.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        assert_eq!(normal.winner(), Some(P0), "lone CC wins a normal match");

        // In survival, razing/absence of the alien beachhead is NOT a win — only
        // the human losing their own base ends the run.
        let mut surv = Sim::new(Map::new(10, 10), 1, f(0));
        surv.set_survival_mode(true);
        surv.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        assert_eq!(
            surv.winner(),
            None,
            "survival must not be won by razing the beachhead"
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
    fn power_balance_sums_living_buildings() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        s.add_building(P0, BuildingKind::PowerPlant, 1, 1);
        s.add_building(P0, BuildingKind::Refinery, 3, 1);
        assert_eq!(s.power_balance(P0), (100, 20));
        assert_eq!(s.power_balance(P1), (0, 0));
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
        use crate::game::tech::tech;
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20); // CC alone is powered
        s.grant_tech(P0, 6); // Mobilization, the prereq of Directed Energy (0)
                             // Tech 0 is a Foundation tech: minerals-paid, no lab needed.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 0,
        }]);
        let (mask, active) = s.research_state(P0);
        assert_eq!(mask & 1, 0);
        assert!(active.is_some());
        let dur = tech(0).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        let (mask, active) = s.research_state(P0);
        assert_eq!(mask & 1, 1, "Weapons I bit set after duration");
        assert!(active.is_none());
    }

    #[test]
    fn research_bonus_helpers_start_at_zero_and_tech_bonuses_are_positive() {
        use crate::game::tech::TECHS;
        assert!(TECHS[0].bonus > Fixed::ZERO); // Weapons I
        assert!(TECHS[3].bonus > Fixed::ZERO); // Armor I
        let s = Sim::new(Map::new(10, 10), 1, f(0));
        // No research yet → every branch bonus is zero.
        assert_eq!(s.player_weapon_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_armor_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_economy_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_mobility_bonus(P0), Fixed::ZERO);
    }

    #[test]
    fn research_is_rejected_without_a_lab_or_prereq() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        // Satisfy Heavy Chassis (1)'s prereq so the ONLY blocker is the missing lab.
        s.grant_tech(P0, 6);
        s.grant_tech(P0, 0);
        s.grant_tech(P0, 10);
        // No ResearchLab yet → a research-paid tech is rejected.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 1,
        }]);
        assert!(s.research_state(P0).1.is_none());
        s.add_building(P0, BuildingKind::ResearchLab, 7, 20);
        // Rotorcraft (2) needs prereqs [1, 11], neither researched → rejected.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 2,
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
            if s.research_state(P0).1.is_some() || s.research_state(P0).0 != 0 {
                research_seen = true;
            }
        }
        assert!(lab_seen, "AI builds a research lab");
        assert!(research_seen, "AI starts/finishes research");
    }

    #[test]
    fn researching_an_era_key_tech_advances_the_era() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.grant_tech(P0, 6);
        s.grant_tech(P0, 0); // prereq chain for Orbital Logistics (10)
        assert_eq!(s.player_era(P0), 0);
        // Tech 10 is Foundation: minerals-paid, no lab needed.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 10,
        }]);
        let dur = crate::game::tech::tech(10).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        assert_eq!(s.player_era(P0), 1, "advanced to Orbital");
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
        }
        assert!(max_era >= 1, "AI advanced at least one era");
    }

    #[test]
    fn shields_absorb_then_regen_and_antiarmor_pierces() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(20_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        s.grant_tech(P0, 6);
        s.grant_tech(P0, 0);
        s.grant_tech(P0, 10); // prereq of Deflector Fields (13)
                              // Warm up the research pool: Shield I costs 300, lab produces 2/tick => 150 ticks.
        for _ in 0..160 {
            s.step(&[]);
        }
        // Research Deflector Fields (id 13) to completion.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 13,
        }]);
        let dur = crate::game::tech::tech(13).unwrap().duration;
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
    fn antimatter_accrues_and_gates_capital() {
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
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::AntimatterPlant, 4, 2); // ON the alloy deposit
        assert_eq!(s.alloys(P0), crate::fixed::Fixed::ZERO);
        for _ in 0..50 {
            s.step(&[]);
        }
        assert!(
            s.alloys(P0) > crate::fixed::Fixed::ZERO,
            "alloys accrue from a powered antimatter plant on an alloy deposit"
        );
    }

    #[test]
    fn antigrav_research_makes_owner_units_ignore_terrain() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(50_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        let agid = (0..crate::game::tech::TECH_COUNT)
            .find(|&i| {
                matches!(
                    crate::game::tech::TECHS[i].branch,
                    crate::game::tech::TechBranch::AntiGrav
                )
            })
            .map(|i| u32::try_from(i).unwrap())
            .unwrap();
        assert!(!s.has_antigrav(P0));
        for id in [6u32, 0, 10, 1, 3, 8, 9, 13, 14, 11, 12] {
            s.grant_tech(P0, id); // satisfy Anti-Grav Drives (16)'s prereqs [9, 12]
        }
        // Warm up the research pool: Anti-Grav Drives costs 700, lab makes 2/tick => 350 ticks.
        for _ in 0..400 {
            s.step(&[]);
        }
        s.step(&[Command::Research {
            owner: P0,
            tech_id: agid,
        }]);
        for _ in 0..crate::game::tech::tech(agid).unwrap().duration {
            s.step(&[]);
        }
        assert!(s.has_antigrav(P0), "anti-grav researched");
        assert!(!s.has_antigrav(P1), "opponent unaffected");
    }

    #[test]
    fn ai_researches_antigrav() {
        // Over a long match (≈20_000 ticks, seed 7), the AI should eventually
        // research Anti-Grav Drives (the last tech in priority, after all 16
        // earlier techs are complete — sequential research takes ~9k+ ticks).
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
        let mut antigrav_seen = false;
        for _ in 0..60_000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
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
    fn lab_funds_tech_from_research_pool() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 6, 2);
        // Heavy Chassis (1) is a research-paid tier-1 tech; satisfy its prereqs.
        s.grant_tech(P0, 6);
        s.grant_tech(P0, 0);
        s.grant_tech(P0, 10);
        // No research yet -> rejected even though minerals are plentiful.
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 1,
        }]);
        assert!(
            s.research_state(P0).1.is_none(),
            "tech 1 should be unaffordable at 0 research"
        );
        for _ in 0..400 {
            s.step(&[]);
        }
        assert!(s.research(P0).to_bits() > 0, "lab should produce research");
        s.step(&[Command::Research {
            owner: P0,
            tech_id: 1,
        }]);
        assert!(
            s.research_state(P0).1.is_some(),
            "tech 1 should start once research is funded"
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
    fn extractor_on_ore_mines_minerals_and_depletes() {
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
        let before = s.minerals(P0).to_bits();
        s.step(&[]);
        assert!(
            s.minerals(P0).to_bits() > before,
            "extractor should mine minerals"
        );
        for _ in 0..10 {
            s.step(&[]);
        }
        assert_eq!(s.map().deposit(6, 2), None, "deposit should be exhausted");
    }
}
