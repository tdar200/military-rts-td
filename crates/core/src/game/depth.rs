//! Kestrel depth rules: RTS combat, match shape and run mode, isolated behind
//! the narrow `depth` flag that only [`crate::game::scenario::kestrel_reach`]
//! sets. Every behaviour here checks [`Sim::is_depth`] (`earthfront && depth`),
//! never `earthfront` alone: the Survival map also enables Earthfront and must
//! stay byte-identical.
//!
//! State lives in [`DepthUnit`] (one per entity, `Entity::dp`) and
//! [`DepthGlobal`] (`Sim::dg`). Both are folded into [`Sim::state_hash`] only
//! when depth is on. Later tasks append fields at the END of each struct and
//! their hash writes at the END of its `hash_into`, in task order, never
//! reordering.

use super::{
    attack_of, is_air_of, tile_center, EntityId, Kind, PlayerId, Sim, COMBAT_CELL, DOC_ARMOR,
    DOC_VITALITY, DOC_WEAPONS,
};
use crate::fixed::Fixed;
use crate::game::ability::AbilityKind;
use crate::game::balance::Balance;
use crate::game::hex;
use crate::game::map::Map;
use crate::game::path::find_path_weighted;
use crate::game::stats::{AttackProfile, BuildingKind, UnitKind};
use crate::hash::Fnv;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Extra reach of the acquisition ring beyond a unit's weapon range: an idle
/// unit engages the nearest targetable enemy within `range + ACQUIRE_BONUS`.
pub(super) const ACQUIRE_BONUS: Fixed = Fixed::from_int(3);
/// How far a unit pulled off by acquisition or a call for help may stray from
/// its anchor before it drops the fight and walks home.
pub(super) const LEASH: Fixed = Fixed::from_int(6);
/// Idle friendly units within this distance of a damaged unit or building
/// answer the hit by engaging the attacker.
pub(super) const ASSIST_RADIUS: Fixed = Fixed::from_int(6);
/// Ticks between re-paths of a chase while the engaged target keeps moving.
pub(super) const REPATH_PERIOD: u64 = 20;
/// Task 12: same-owner units on the same layer closer than this are pushed
/// apart after movement (half the overlap each).
pub(super) const SEPARATION: Fixed = Fixed::from_ratio(45, 100);
/// Task 13: the leash of a Defensive unit (an Aggressive one uses [`LEASH`]).
pub(super) const DEFENSIVE_LEASH: Fixed = Fixed::from_int(3);
/// Task 13: a forced target (`AttackTarget`) stays tracked while the chaser or
/// any other entity of its side is within this distance of it (the widest
/// unit sight the client's fog uses, a Gunship's 10); past that the target is
/// lost and the order ends where the chaser stands.
pub(super) const FORCED_TRACK: Fixed = Fixed::from_int(10);
/// Task 14: the most waypoint legs a unit carries, counting the player order
/// under way (a ninth leg is dropped).
pub const QUEUE_CAP: usize = 8;
/// Task 15: percent of its normal hit an `AntiArmor` missile lands on an air
/// target under depth (the team gains `targets_air`). A missile does 38.5 to
/// a Plated gunship (22 x 1.75) and a gunship has 90 HP, so only the hits to
/// kill matter: 47 to 58 percent is 5 hits, 59 to 77 is 4 and 78 to 100 is
/// 3. The spec's 50 (and every value up to 77) leaves 4 gunships beating
/// 5 teams + 1 rifle for 320 of its 600 credits, short of the 60 percent
/// trade target (`audit_duel_table`, `anti_armour_teams_now_trade_with_gunships`);
/// 80 is the first round value in the 3-hit band with a margin (3 x 30.8 =
/// 92.4), and one gunship still beats one team.
pub(super) const AT_AIR_PCT: i64 = 80;
/// Task 16: path cost of breaking through one of the defender's walls when a
/// wave unit has no open route (six grass steps: a short detour still wins).
pub const BREACH_WALL_COST: i64 = 60;
/// Task 16: path cost of breaking through any other defender structure, so a
/// breach goes through a wall wherever one is about as close.
pub const BREACH_BUILDING_COST: i64 = 120;

/// Task 17: money price of the first level of an Upgrades track (weapons,
/// armour, vitality); each level bought adds [`UPGRADE_STEP`].
pub const UPGRADE_BASE: i32 = 150;
/// Task 17: price rise per level already bought on that track.
pub const UPGRADE_STEP: i32 = 100;
/// Task 17: levels per track a player may hold at era 0.
pub const UPGRADE_CAP_ERA0: u16 = 3;
/// Task 17: levels per track at era 1 (Robotic Workcells, tech 7) and later.
pub const UPGRADE_CAP_ERA1: u16 = 6;
/// Task 17: the Upgrades tracks offered under depth, in `Ascend` track order
/// (weapons, armour, vitality). The forge (track 3) is never offered.
pub const UPGRADE_TRACKS: u8 = 3;
/// Task 17: the Earthfront technology a `Barrage` needs under depth
/// (Precision Manufacturing).
pub(super) const BARRAGE_TECH: u32 = 6;

/// Task 18: the money a Refinery costs on top of its base price for each
/// refinery its owner already has (alive or under construction).
pub const REFINERY_STEP: i32 = 50;
/// Task 18: ticks a depth repair job spreads its `max_hp / 5` over.
pub const REPAIR_TICKS: u32 = 150;
/// Task 18: ticks after a repair order before the same building may be
/// repaired again (counted from the order, so it covers the job).
pub const REPAIR_COOLDOWN: u32 = 450;
/// Task 18: the least a depth repair costs (the Command Center, priced 0,
/// pays this); dearer buildings pay a tenth of their price.
pub const REPAIR_MIN_COST: i32 = 25;
/// Task 18: the money line above which the depth AI spends its surplus on
/// extra refineries once science, training and Upgrades have had their turn.
pub(super) const AI_SURPLUS: i32 = 1500;
/// Task 18: the most refineries the depth AI owns through surplus spending
/// (its own build list stops at two, so at most two extra). Without a cap the
/// playtest AI fills its base with 18 refineries and wins after 2 waves; see
/// the Task 18 note on `KESTREL_DEFENDED_WAVES` in scenario.rs.
pub(super) const AI_SURPLUS_REFINERIES: usize = 4;

/// Task 19: the most units an expedition's wave table supplies before the
/// relays add theirs (`6 + 2w`, capped here; reached at wave 10).
pub const WAVE_SIZE_CAP: u32 = 24;
/// Task 19: the zero-based index of the elite wave (wave 6), which opens with
/// a Capital and [`ELITE_ESCORT_TANKS`] Tanks before its doctrine's mix.
pub const ELITE_WAVE: u32 = 5;
/// Task 19: the Tanks escorting the elite wave's Capital.
pub const ELITE_ESCORT_TANKS: u32 = 2;
/// Task 19: the last table row (wave 10); later waves repeat it.
pub(super) const LAST_TABLE_WAVE: u32 = 9;
/// Task 19: the first zero-based wave whose mix follows its doctrine (wave 5).
/// Before it the seeded doctrines pick only the target; the defender
/// overrides (siege, anti-armour) still shape the mix.
pub(super) const DOCTRINE_WAVE: u32 = 4;
/// Task 21: the waves that must have spawned (the elite wave 6 among them)
/// before the Core Node can take damage, with every relay down as well.
pub const CORE_EXPOSED_WAVES: u32 = ELITE_WAVE + 1;
/// Task 21: the supply the waves' attacker keeps as its home army in every
/// era under depth (the classic target, 10 at era 0, grows to 24 at era 1).
/// Its offence is the waves and the raids; the base army garrisons the Core
/// Node. Measured in the Task 21 report: 8 to 12 hold the match window, 14
/// and 24 do not.
pub const ALIEN_ARMY_TARGET: u32 = 10;
/// Task 21: the Upgrades levels per track the waves' attacker may own for
/// each spawned wave (none before wave one, Task 20's gate). Unpaced it
/// bought [6, 6, 6] the moment it reached era 1, after wave 2.
pub const ALIEN_UPGRADES_PER_WAVE: u32 = 1;
/// Task 19: ticks between the alien's era-0 raids (90 s).
pub const RAID_PERIOD: u64 = 2700;
/// Task 19: the supply the alien must have in use before it raids at era 0.
pub const RAID_SUPPLY: u32 = 12;

/// Task 19: the kind of unit `i` (of `budget`) in zero-based wave `w` under
/// doctrine `doctrine` (0 mixed, 1 anti-armour, 2 siege, 3 air interdiction,
/// 4 supply raid). Wave 1 is rifles; wave 2 adds a Tank every 4th; wave 3 an
/// `AntiArmor` team every 5th; wave 4 brings the first flyers (a Helicopter
/// every 7th). From wave 5 the doctrine shapes the mix: 1 puts an `AntiArmor`
/// team every 3rd, 2 leads with a Capital and Tanks (the Task 16 siege lead,
/// the first quarter rounded up), 3 a Helicopter every 4th, 4 is a fast raid
/// of rifles with a Tank every 3rd, 0 is wave 4's mix. Wave 6 is the elite
/// wave: a Capital, then [`ELITE_ESCORT_TANKS`] Tanks, then its doctrine's
/// mix. Waves after 10 repeat wave 10's mix. The siege lead and the
/// anti-armour mix also answer the defender's walls and tanks before wave 5
/// (the Capital only from wave 5), because [`Sim::depth_wave_doctrine`] lets
/// doctrines 1 and 2 reach waves 1 to 4 only as those overrides.
#[must_use]
pub(super) const fn depth_wave_kind(w: u32, i: u32, budget: u32, doctrine: u8) -> UnitKind {
    let w = if w > LAST_TABLE_WAVE {
        LAST_TABLE_WAVE
    } else {
        w
    };
    if w == ELITE_WAVE {
        if i == 0 {
            return UnitKind::Capital;
        }
        if i <= ELITE_ESCORT_TANKS {
            return UnitKind::Tank;
        }
    }
    let shaped = w >= DOCTRINE_WAVE;
    match doctrine {
        2 if shaped && i == 0 => return UnitKind::Capital,
        2 if i < budget.div_ceil(4) => return UnitKind::Tank,
        1 if i.is_multiple_of(3) => return UnitKind::AntiArmor,
        3 if shaped && i.is_multiple_of(4) => return UnitKind::Helicopter,
        4 if shaped => {
            return if i.is_multiple_of(3) {
                UnitKind::Tank
            } else {
                UnitKind::Infantry
            }
        }
        _ => {}
    }
    if w >= 3 && i.is_multiple_of(7) {
        UnitKind::Helicopter
    } else if w >= 2 && i.is_multiple_of(5) {
        UnitKind::AntiArmor
    } else if w >= 1 && i.is_multiple_of(4) {
        UnitKind::Tank
    } else {
        UnitKind::Infantry
    }
}

/// Task 15: the depth weapon of an entity of `kind` whose balance weapon is
/// `base`. `AntiArmor` teams also engage air (at [`depth_air_damage_pct`]);
/// every other weapon is unchanged. Callers apply it under depth only (see
/// [`Sim::depth_attack_profile`]); `run_combat` and `run_movement` call this
/// directly because they hold `entities` mutably.
pub(super) const fn depth_profile(kind: Kind, base: AttackProfile) -> AttackProfile {
    let mut p = base;
    if matches!(kind, Kind::Unit(UnitKind::AntiArmor)) {
        p.targets_air = true;
    }
    p
}

/// Task 15: the weapon `run_combat` and the attack-move halt scan use for an
/// entity of `kind`: [`attack_of`] with [`depth_profile`] applied when
/// `depth`. Those passes hold `entities` mutably, so they cannot call
/// [`Sim::depth_attack_profile`].
pub(super) const fn weapon_of(balance: &Balance, kind: Kind, depth: bool) -> Option<AttackProfile> {
    match attack_of(balance, kind) {
        Some(p) if depth => Some(depth_profile(kind, p)),
        other => other,
    }
}

/// Task 15: percent of a hit that lands when an entity of `kind` fires at an
/// air target under depth: [`AT_AIR_PCT`] for `AntiArmor`, 100 for the rest
/// (the AA battery and anything else that always could).
pub(super) const fn depth_air_damage_pct(kind: Kind) -> i64 {
    match kind {
        Kind::Unit(UnitKind::AntiArmor) => AT_AIR_PCT,
        _ => 100,
    }
}

/// How a Kestrel depth unit fights when nobody is ordering it (Task 13).
/// Set by [`super::Command::SetStance`] (and `HoldPosition`); kept by `Stop`
/// and by every move order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Stance {
    /// Acquires anything in its ring, chases on a leash of 6, answers hits on
    /// itself and on allies within 6. The default.
    #[default]
    Aggressive,
    /// Never goes looking: fires at what walks into weapon range, answers a hit
    /// on itself or an ally within 6, and stays within 3 of its anchor.
    Defensive,
    /// Never moves on its own: fires at targets in weapon range only. Player
    /// move orders still move it, and it holds where they end.
    Hold,
}

impl Stance {
    /// The protocol and HUD name: "aggressive", "defensive" or "hold".
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Aggressive => "aggressive",
            Self::Defensive => "defensive",
            Self::Hold => "hold",
        }
    }

    /// The stance with this exact (lower case) name, if any.
    #[must_use]
    pub fn from_name(s: &str) -> Option<Self> {
        [Self::Aggressive, Self::Defensive, Self::Hold]
            .into_iter()
            .find(|st| st.name() == s)
    }

    /// Stable hash tag. Never renumber.
    #[must_use]
    pub const fn tag(self) -> u64 {
        match self {
            Self::Aggressive => 0,
            Self::Defensive => 1,
            Self::Hold => 2,
        }
    }
}

/// Task 20: the Kestrel difficulty preset, chosen on the title and carried by
/// `match.json`. Normal is the match as it was before presets existed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Difficulty {
    /// More money, a later first wave, longer gaps and smaller waves.
    Easy,
    /// The reference match (Kestrel's constants before Task 20).
    #[default]
    Normal,
    /// Less money, an earlier first wave, shorter gaps and bigger waves.
    Hard,
}

impl Difficulty {
    /// The human player's starting money.
    #[must_use]
    pub const fn start_credits(self) -> i32 {
        match self {
            Self::Easy => 1500,
            Self::Normal => 1200,
            Self::Hard => 1000,
        }
    }

    /// Ticks before the first wave (3:00, 2:30, 2:00 at 30 ticks a second).
    #[must_use]
    pub const fn first_wave_ticks(self) -> u64 {
        match self {
            Self::Easy => 5400,
            Self::Normal => 4500,
            Self::Hard => 3600,
        }
    }

    /// Ticks between waves (3:30, 3:00, 2:30).
    #[must_use]
    pub const fn wave_interval_ticks(self) -> u64 {
        match self {
            Self::Easy => 6300,
            Self::Normal => 5400,
            Self::Hard => 4500,
        }
    }

    /// The percent of the wave table's size a wave brings (rounded down),
    /// before the relays add theirs.
    #[must_use]
    pub const fn wave_size_pct(self) -> u32 {
        match self {
            Self::Easy => 75,
            Self::Normal => 100,
            Self::Hard => 125,
        }
    }

    /// Task 22: the percent of the base score a match on this preset earns
    /// ([`Sim::depth_score`]).
    #[must_use]
    pub const fn score_pct(self) -> i64 {
        match self {
            Self::Easy => 75,
            Self::Normal => 100,
            Self::Hard => 150,
        }
    }

    /// The protocol name: "easy", "normal" or "hard".
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Easy => "easy",
            Self::Normal => "normal",
            Self::Hard => "hard",
        }
    }

    /// The preset with this exact (lower case) name, if any.
    #[must_use]
    pub fn from_name(s: &str) -> Option<Self> {
        [Self::Easy, Self::Normal, Self::Hard]
            .into_iter()
            .find(|d| d.name() == s)
    }

    /// Stable hash tag. Never renumber.
    #[must_use]
    pub const fn tag(self) -> u64 {
        match self {
            Self::Easy => 0,
            Self::Normal => 1,
            Self::Hard => 2,
        }
    }
}

/// Unit push axes for coincident units, one per hex direction (60 degrees
/// apart, starting at 30 degrees), picked by the higher index `j % 6`.
const HEX_AXES: [(i64, i64); 6] = [
    (866, 500),
    (0, 1000),
    (-866, 500),
    (-866, -500),
    (0, -1000),
    (866, -500),
];

/// Per-entity depth state. Fields are appended at the END in task order.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthUnit {
    /// Task 11: where this unit stood when it last fell idle. Auto-acquisition
    /// and calls for help pull it off this point by at most [`LEASH`]; it walks
    /// back once the fight is over. Cleared by a player (or AI) `Move` or
    /// `AttackMove`, re-recorded where that order ends.
    pub(super) anchor: Option<Vec2>,
    /// Task 11: the enemy this unit chose to fight on its own (acquisition or a
    /// call for help). Dropped by `clear_dead` the tick its target dies, so a
    /// freed and reused entity slot is never chased.
    pub(super) engaged: Option<EntityId>,
    /// Task 13: how this unit fights on its own (Aggressive by default).
    pub(super) stance: Stance,
    /// Task 13: the enemy a player `AttackTarget` order focuses. While it is set
    /// the unit walks into weapon range of it and `run_combat` fires at nothing
    /// else; it is cleared (and the unit stops where it stands) when the target
    /// dies, is lost from track, turns untargetable or cannot be reached, and
    /// by any new order.
    pub(super) forced: Option<EntityId>,
    /// Task 14: shift-queued waypoint legs `(point, attack_move)`, nearest
    /// first, walked after the current player order. Never holds more than
    /// `QUEUE_CAP - 1` legs (the one under way is the eighth). Cleared by any
    /// new direct order (`Move`, `AttackMove`, `Stop`, `HoldPosition`,
    /// `AttackTarget`). Invariant after every tick: a non-empty queue means
    /// the unit is on a player order or a forced target, so it is never
    /// anchored, acquired or called for help while legs remain.
    pub(super) queue: Vec<(Vec2, bool)>,
    /// Task 16: this unit already ran its breach search for the order it is
    /// on (one search per order target, found or not). Reset whenever it gets
    /// a new order target: a `Move` or `AttackMove`, the start of a queued
    /// leg (including the order a breach resumes once its structure falls),
    /// and any halt (`Stop`, `Hold`, `AttackTarget`, the end of a forced
    /// target). While it is set a forced target on a building is a breach.
    pub(super) breach_tried: bool,
    /// P2 review M6: the goal tile of this unit's last breach search when it
    /// found no route. A later order to the same tile (the alien AI re-issues
    /// its wave target on every pass) skips the search; another tile, a
    /// successful search or any halt clears it.
    pub(super) breach_failed: Option<(u16, u16)>,
    /// Task 18: ticks left of this building's repair job (0 when none). Each
    /// tick heals its share of `max_hp / 5`; cleared when the building dies or
    /// is sold, and never inherited by a reused slot.
    pub(super) repair_ticks: u32,
    /// Task 18: ticks until this building may be repaired again (0 when it
    /// may). Set to [`REPAIR_COOLDOWN`] by an accepted repair order.
    pub(super) repair_cd: u32,
    /// Task 19: the one-based wave this unit spawned with (0 when it is not a
    /// wave unit). [`Sim::waves_cleared`] counts a wave once none of its
    /// living units remain.
    pub(super) wave: u16,
}

impl DepthUnit {
    /// Folds this entity's depth state into the world hash (depth on only).
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        match self.anchor {
            Some(a) => {
                h.write_u64(1);
                h.write_i64(a.x.to_bits());
                h.write_i64(a.y.to_bits());
            }
            None => h.write_u64(0),
        }
        match self.engaged {
            Some(id) => {
                h.write_u64(1);
                h.write_u64(u64::from(id.0));
            }
            None => h.write_u64(0),
        }
        // Task 13 (appended).
        h.write_u64(self.stance.tag());
        match self.forced {
            Some(id) => {
                h.write_u64(1);
                h.write_u64(u64::from(id.0));
            }
            None => h.write_u64(0),
        }
        // Task 14 (appended): the queue length, then each leg.
        h.write_u64(self.queue.len() as u64);
        for &(p, attack_move) in &self.queue {
            h.write_i64(p.x.to_bits());
            h.write_i64(p.y.to_bits());
            h.write_u64(u64::from(attack_move));
        }
        // Task 16 (appended).
        h.write_u64(u64::from(self.breach_tried));
        // P2 review M6 (appended).
        match self.breach_failed {
            Some((x, y)) => {
                h.write_u64(1);
                h.write_u64(u64::from(x));
                h.write_u64(u64::from(y));
            }
            None => h.write_u64(0),
        }
        // Task 18 (appended).
        h.write_u64(u64::from(self.repair_ticks));
        h.write_u64(u64::from(self.repair_cd));
        // Task 19 (appended).
        h.write_u64(u64::from(self.wave));
    }
}

/// World-wide depth state. Fields are appended at the END in task order.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthGlobal {
    /// Task 19: the seeded doctrine cycle; wave `w` (zero-based) follows
    /// `doctrine_order[w % 5]` unless the defender's walls or tanks override
    /// it ([`Sim::depth_wave_doctrine`]). Drawn once by [`Sim::enable_depth`].
    pub(super) doctrine_order: [u8; 5],
    /// Task 19: spawned waves none of whose units are alive any more,
    /// recounted at the end of every depth tick ([`Sim::waves_cleared`]).
    pub(super) waves_cleared: u32,
    /// Task 20: the match's difficulty preset (Normal unless
    /// [`crate::game::scenario::kestrel_reach_with`] chose another). It scales
    /// the wave size here; the purse and the wave clock are set at build time.
    pub(super) difficulty: Difficulty,
    /// Task 22: the money value (balance price) of the enemy units and
    /// structures that died, by the player credited with them (the other side
    /// of the two-player match: the sim records no killer). Credited by
    /// `clear_dead`; a sold structure is never credited.
    pub(super) destroyed: [i64; 2],
    /// Task 22: the money value of each player's own units and structures that
    /// died (never a sale), by owner.
    pub(super) lost: [i64; 2],
    /// Task 22: entity slots sold by this tick's commands, so the `clear_dead`
    /// right after the commands treats them as sales, not losses. Transient:
    /// filled by `apply_sell` and emptied by that same tick's first
    /// `clear_dead`, so it is always empty between ticks and is not hashed.
    pub(super) sold: Vec<u32>,
}

impl DepthGlobal {
    /// Folds the global depth state into the world hash (depth on only).
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        // Task 19.
        for &d in &self.doctrine_order {
            h.write_u64(u64::from(d));
        }
        h.write_u64(u64::from(self.waves_cleared));
        // Task 20 (appended).
        h.write_u64(self.difficulty.tag());
        // Task 22 (appended): the destroyed and lost ledgers.
        for v in self.destroyed.iter().chain(&self.lost) {
            h.write_i64(*v);
        }
    }
}

/// Task 22: points per cleared wave.
pub const SCORE_PER_WAVE: i64 = 500;
/// Task 22: a human win earns a tenth of the ticks left before this one (25
/// minutes, the end of the match window).
pub const SCORE_VICTORY_TICKS: i64 = 45_000;
/// Task 22: the least total for each grade, S first; below the last is D.
pub const GRADE_THRESHOLDS: [(i64, char); 4] =
    [(12_000, 'S'), (8_000, 'A'), (5_000, 'B'), (2_500, 'C')];

/// Task 22: the score of a Kestrel depth match so far, from the human's side.
/// Derived from hashed sim state only ([`Sim::depth_score`]), so a replay that
/// reaches the same state reaches the same score.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DepthScore {
    /// Spawned waves none of whose units are left ([`Sim::waves_cleared`]).
    pub waves_held: u32,
    /// Money value of the alien units and structures destroyed.
    pub destroyed: i64,
    /// Money value of the human's own units and structures lost.
    pub lost: i64,
    /// A tenth of the ticks left before [`SCORE_VICTORY_TICKS`] on a human
    /// win, else 0.
    pub victory_bonus: i64,
    /// `max(0, waves_held * 500 + destroyed - lost / 2 + victory_bonus)`
    /// times the preset's [`Difficulty::score_pct`] / 100.
    pub total: i64,
    /// S, A, B, C or D ([`depth_grade`]).
    pub grade: char,
}

/// Task 22: the grade a score total earns: S at 12,000, A at 8,000, B at
/// 5,000, C at 2,500, else D.
#[must_use]
pub const fn depth_grade(total: i64) -> char {
    let mut i = 0;
    while i < GRADE_THRESHOLDS.len() {
        if total >= GRADE_THRESHOLDS[i].0 {
            return GRADE_THRESHOLDS[i].1;
        }
        i += 1;
    }
    'D'
}

impl Sim {
    /// Turns on the Kestrel depth rules. Called only by
    /// [`crate::game::scenario::kestrel_reach`], after `enable_earthfront`;
    /// depth means nothing without Earthfront (see [`Sim::is_depth`]).
    ///
    /// Task 19: draws the doctrine order, a Fisher-Yates shuffle of
    /// `[0, 1, 2, 3, 4]` with five `next_below` draws (the sim's first real
    /// draws; nothing else in the core uses the rng, and no other scenario
    /// calls this, so their rng state stays the seed).
    pub fn enable_depth(&mut self) {
        self.depth = true;
        let mut order = [0, 1, 2, 3, 4];
        for i in (0..order.len()).rev() {
            let bound = u32::try_from(i + 1).unwrap_or(1);
            let j = usize::try_from(self.rng.next_below(bound)).unwrap_or(0);
            order.swap(i, j);
        }
        self.dg.doctrine_order = order;
    }

    /// Task 19: the doctrine zero-based wave `w` is locked to, 45 seconds
    /// before it lands: 2 (siege) when the defender has at least 3 walls, else
    /// 1 (anti-armour) when it has more than 3 tanks, else the seeded
    /// `doctrine_order[w % 5]`. Before wave 5 a seeded 1 or 2 reads as 0
    /// (mixed): the early table rows keep their shape, so those two doctrines
    /// reach waves 1 to 4 only as answers to the defender.
    #[must_use]
    pub(super) fn depth_wave_doctrine(&self, w: u32, walls: usize, tanks: usize) -> u8 {
        if walls >= 3 {
            return 2;
        }
        if tanks > 3 {
            return 1;
        }
        let seeded = self.dg.doctrine_order[usize::try_from(w % 5).unwrap_or(0)];
        if w < DOCTRINE_WAVE && matches!(seeded, 1 | 2) {
            0
        } else {
            seeded
        }
    }

    /// Task 19: the force zero-based wave `w` brings before the supply
    /// ceiling: `min(6 + 2w, 24)` at the difficulty's percent (Task 20,
    /// [`Difficulty::wave_size_pct`], rounded down) plus 2 per operational
    /// relay of the waves' attacker.
    #[must_use]
    pub(super) fn depth_expedition_size(&self, w: u32) -> u32 {
        let Some(cfg) = self.waves else {
            return 0;
        };
        let table = 6_u32.saturating_add(w.saturating_mul(2)).min(WAVE_SIZE_CAP);
        table * self.dg.difficulty.wave_size_pct() / 100
            + 2 * self.alien_relay_count(cfg.attacker, true)
    }

    /// Task 20: the seed the match was built with (the bridge reports it, so
    /// the debrief can show it and Restart can replay it).
    #[must_use]
    pub const fn seed(&self) -> u64 {
        self.field_seed
    }

    /// Task 20: the match's difficulty preset (Normal without depth).
    #[must_use]
    pub const fn difficulty(&self) -> Difficulty {
        if self.is_depth() {
            self.dg.difficulty
        } else {
            Difficulty::Normal
        }
    }

    /// Task 20: records the difficulty preset the match was built with (the
    /// purse and the wave clock are the builder's; this scales the waves and
    /// joins the hash). Only [`crate::game::scenario::kestrel_reach_with`]
    /// calls it, after [`Sim::enable_depth`].
    pub(crate) const fn set_difficulty(&mut self, difficulty: Difficulty) {
        self.dg.difficulty = difficulty;
    }

    /// Task 20 (the Task 19 carry-over): whether `player` may buy Upgrades
    /// now. The waves' attacker waits until wave one has spawned, so its
    /// pre-wave probe stays a probe (bought from tick 0, Upgrades let the
    /// probe alone take an undefended base at t=4121); every other player
    /// always may. Its raids wait for wave one too ([`Sim::depth_raid`]).
    ///
    /// Task 21: the attacker is paced, one level per track for each spawned
    /// wave ([`ALIEN_UPGRADES_PER_WAVE`]), so wave one's rule above is the
    /// first step of this one.
    #[must_use]
    pub(super) fn depth_ai_may_upgrade(&self, player: PlayerId, track: u8) -> bool {
        self.waves.is_none_or(|cfg| {
            let level = self.upgrade_levels(player)[usize::from(track).min(2)];
            cfg.attacker != player
                || u32::from(level) < self.wave_count.saturating_mul(ALIEN_UPGRADES_PER_WAVE)
        })
    }

    /// Task 21: the supply the Earthfront AI fills with its home army: 10 at
    /// era 0 and 24 from era 1 (the classic targets), except that under
    /// depth the waves' attacker stays at [`ALIEN_ARMY_TARGET`].
    #[must_use]
    pub(super) fn earthfront_army_target(&self, player: PlayerId) -> u32 {
        let classic = if self.player_era(player) == 0 { 10 } else { 24 };
        if self.is_depth() && self.waves.is_some_and(|cfg| cfg.attacker == player) {
            classic.min(ALIEN_ARMY_TARGET)
        } else {
            classic
        }
    }

    /// Task 22: the match's score from the human's (the waves' defender's)
    /// side; `None` without depth. It reads only hashed state (the cleared
    /// waves, the destroyed and lost ledgers, the tick, the winner and the
    /// preset), so it is deterministic and replay-safe. A decided match stops
    /// its tick, so the score holds once the match is over.
    #[must_use]
    pub fn depth_score(&self) -> Option<DepthScore> {
        if !self.is_depth() {
            return None;
        }
        let human = usize::from(self.waves.map_or(self.human_civ, |c| c.defender).0).min(1);
        let waves_held = self.dg.waves_cleared;
        let destroyed = self.dg.destroyed[human];
        let lost = self.dg.lost[human];
        let won = self.winner().is_some_and(|w| usize::from(w.0) == human);
        let tick = i64::try_from(self.tick).unwrap_or(i64::MAX);
        let victory_bonus = if won {
            (SCORE_VICTORY_TICKS - tick).max(0) / 10
        } else {
            0
        };
        let base = i64::from(waves_held) * SCORE_PER_WAVE + destroyed - lost / 2 + victory_bonus;
        let total = base.max(0) * self.dg.difficulty.score_pct() / 100;
        Some(DepthScore {
            waves_held,
            destroyed,
            lost,
            victory_bonus,
            total,
            grade: depth_grade(total),
        })
    }

    /// Task 22: credits the entities in `dead` (slots `clear_dead` just
    /// reaped) to the destroyed and lost ledgers at their balance price: the
    /// owner loses it and the other player destroyed it. Slots sold this tick
    /// ([`DepthGlobal::sold`]) are skipped; the sold list is emptied. Depth
    /// only; owners outside the two players are not counted.
    pub(super) fn depth_credit_deaths(&mut self, dead: &[u32]) {
        for &slot in dead {
            if self.dg.sold.contains(&slot) {
                continue;
            }
            let e = &self.entities[slot as usize];
            let owner = usize::from(e.owner.0);
            if owner > 1 {
                continue;
            }
            let value = match e.kind {
                Kind::Unit(u) => self.balance.unit(u).money_cost,
                Kind::Building(b) => self.balance.building(b).money_cost,
            }
            .to_int_floor();
            self.dg.lost[owner] += value;
            self.dg.destroyed[1 - owner] += value;
        }
        self.dg.sold.clear();
    }

    /// Task 19: spawned waves with no living unit left (0 without depth).
    #[must_use]
    pub const fn waves_cleared(&self) -> u32 {
        if self.is_depth() {
            self.dg.waves_cleared
        } else {
            0
        }
    }

    /// Task 21: whether the Core Node (the waves' attacker's Command Center)
    /// ignores damage: under depth, while any of the attacker's relays is
    /// operational or fewer than [`CORE_EXPOSED_WAVES`] waves have spawned.
    /// Always false without depth (Survival and classic Kestrel). Derived
    /// from hashed state only, so it adds nothing to the hash.
    #[must_use]
    pub fn core_node_shielded(&self) -> bool {
        let Some(cfg) = self.waves else {
            return false;
        };
        self.is_depth()
            && (self.alien_relay_count(cfg.attacker, true) > 0
                || self.wave_count < CORE_EXPOSED_WAVES)
    }

    /// Task 21: whether a hit on entity `j` is ignored by the Core Node
    /// shield, given `shielded` = [`Sim::core_node_shielded`] read once per
    /// pass: `j` is a Command Center of the waves' attacker.
    #[must_use]
    pub(super) fn depth_core_immune(&self, shielded: bool, j: usize) -> bool {
        shielded
            && self.waves.is_some_and(|cfg| {
                let e = &self.entities[j];
                e.owner == cfg.attacker && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
    }

    /// Task 19: recounts [`DepthGlobal::waves_cleared`] after the tick's
    /// deaths (depth only; called at the end of `step`).
    pub(super) fn run_depth_wave_ledger(&mut self) {
        let spawned = usize::try_from(self.wave_count).unwrap_or(usize::MAX);
        if spawned == 0 {
            return;
        }
        let mut alive = alloc::vec![false; spawned + 1];
        for e in self.entities.iter().filter(|e| e.alive && e.dp.wave > 0) {
            if let Some(slot) = alive.get_mut(usize::from(e.dp.wave)) {
                *slot = true;
            }
        }
        let cleared = alive[1..].iter().filter(|&&a| !a).count();
        self.dg.waves_cleared = u32::try_from(cleared).unwrap_or(u32::MAX);
    }

    /// Task 19: whether unit `i` of `player` is idle enough to join a raid: a
    /// built, armed, unstunned combat unit with no order, forced target,
    /// engagement or queued leg, and ammunition to fight with.
    #[must_use]
    pub(super) fn depth_raider(&self, i: usize, player: PlayerId) -> bool {
        let e = &self.entities[i];
        e.owner == player
            && self.depth_fighter(i).is_some()
            && e.move_target.is_none()
            && e.dp.forced.is_none()
            && e.dp.engaged.is_none()
            && e.dp.queue.is_empty()
            && e.ammunition >= 15
    }

    /// Task 19: the alien's era-0 raid on this AI pass, if one is due: every
    /// [`RAID_PERIOD`] ticks, once its supply in use is at least
    /// [`RAID_SUPPLY`], the lowest-index half of its idle combat units
    /// ([`Sim::depth_raider`]) and the defender's structure nearest `base`
    /// (ties to the lowest index) that they attack-move at. Only the waves'
    /// attacker raids, and only under depth. Task 20: never before wave one
    /// has spawned (the probe is the only pre-wave contact; without its
    /// pre-wave Upgrades the alien reached 12 supply by tick 2700 and its raid
    /// made first contact at t=2908).
    #[must_use]
    pub(super) fn depth_raid(&self, player: PlayerId, base: Vec2) -> Option<(Vec<usize>, Vec2)> {
        let cfg = self.waves?;
        if !self.is_depth()
            || player != cfg.attacker
            || self.wave_count == 0
            || !self.tick.is_multiple_of(RAID_PERIOD)
            || self.player_era(player) != 0
            || self.supply_used(player) < RAID_SUPPLY
        {
            return None;
        }
        let idle: Vec<usize> = (0..self.entities.len())
            .filter(|&i| self.depth_raider(i, player))
            .collect();
        let party = idle.len() / 2;
        if party == 0 {
            return None;
        }
        let target = self
            .entities
            .iter()
            .filter(|e| {
                e.alive
                    && e.hp > Fixed::ZERO
                    && e.owner == cfg.defender
                    && matches!(e.kind, Kind::Building(_))
            })
            .min_by_key(|e| (e.pos - base).length_squared())?
            .pos;
        Some((idle[..party].to_vec(), target))
    }

    /// Whether the Kestrel depth rules are active: Earthfront AND depth. Every
    /// depth behaviour and every depth hash write checks this, never
    /// `earthfront` alone.
    #[must_use]
    pub const fn is_depth(&self) -> bool {
        self.earthfront && self.depth
    }

    /// Task 15: the weapon an entity of `kind` fights with, given its balance
    /// weapon `base`: under depth an `AntiArmor` team also targets air
    /// ([`depth_profile`]); with depth off `base` unchanged.
    pub(super) const fn depth_attack_profile(
        &self,
        kind: Kind,
        base: AttackProfile,
    ) -> AttackProfile {
        if self.is_depth() {
            depth_profile(kind, base)
        } else {
            base
        }
    }

    /// The weapon of entity `i` when it is a unit that may fight on its own:
    /// alive, built, not stunned, armed and not a Harvester. Ammunition is
    /// checked by the callers (a dry unit still walks home). Includes the
    /// Task 15 air override, so acquisition, calls for help, attack-move
    /// steering and forced targets all see the weapon `run_combat` fires.
    fn depth_fighter(&self, i: usize) -> Option<AttackProfile> {
        let e = &self.entities[i];
        if !e.alive || e.construction_remaining > 0 || e.stun_ticks > 0 {
            return None;
        }
        if !matches!(e.kind, Kind::Unit(k) if k != UnitKind::Harvester) {
            return None;
        }
        attack_of(&self.balance, e.kind).map(|p| self.depth_attack_profile(e.kind, p))
    }

    /// Whether a unit with weapon `profile` owned by `owner` may shoot entity
    /// `j`: the same test `run_combat` applies (alive, another owner, and the
    /// weapon reaches the target's layer).
    fn depth_can_hit(&self, profile: AttackProfile, owner: PlayerId, j: usize) -> bool {
        let Some(t) = self.entities.get(j) else {
            return false;
        };
        if !t.alive || t.hp <= Fixed::ZERO || t.owner == owner {
            return false;
        }
        if is_air_of(&self.balance, t.kind) {
            profile.targets_air
        } else {
            profile.targets_ground
        }
    }

    /// The nearest enemy of unit `i` (weapon `profile`) within `radius` of the
    /// unit and within `reach` of `anchor`; ties go to the lowest index.
    fn depth_nearest_enemy(
        &self,
        grid: &DepthGrid,
        scratch: &mut Vec<usize>,
        i: usize,
        profile: AttackProfile,
        radius: Fixed,
        (anchor, reach): (Vec2, Fixed),
    ) -> Option<usize> {
        let e = &self.entities[i];
        let radius_sq = radius * radius;
        let reach_sq = reach * reach;
        grid.gather(e.pos, radius, scratch);
        let mut best: Option<(usize, Fixed)> = None;
        for &j in scratch.iter() {
            if !self.depth_can_hit(profile, e.owner, j) {
                continue;
            }
            let tpos = self.entities[j].pos;
            let d = (tpos - e.pos).length_squared();
            if d > radius_sq || (tpos - anchor).length_squared() > reach_sq {
                continue;
            }
            if best.is_none_or(|(_, bd)| d < bd) {
                best = Some((j, d));
            }
        }
        best.map(|(j, _)| j)
    }

    /// Sends unit `i` back to its anchor. A return that cannot be pathed (or is
    /// redirected to a substitute tile) re-anchors the unit where the order
    /// really ends, so it never retries a hopeless walk every tick.
    fn depth_return(&mut self, i: usize, anchor: Vec2) {
        let e = &mut self.entities[i];
        e.dp.engaged = None;
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, anchor, false);
        let e = &mut self.entities[i];
        match e.move_target {
            None => e.dp.anchor = Some(e.pos),
            Some(t) if t != anchor => e.dp.anchor = Some(t),
            Some(_) => {}
        }
    }

    /// Orders unit `i` after its engaged target at `tpos`. Returns false when
    /// the chase cannot stay on the leash: no path, or a path that leaves the
    /// leash before the target is in weapon range (a detour around water). The
    /// failed move is cancelled so the unit never wanders off on it.
    fn depth_chase(&mut self, i: usize, tpos: Vec2, anchor: Vec2, range: Fixed) -> bool {
        let e = &mut self.entities[i];
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, tpos, true);
        let leash = leash_of(&self.entities[i].dp);
        let leash_sq = leash * leash;
        let range_sq = range * range;
        let e = &mut self.entities[i];
        let fits = e.move_target.is_some()
            && e.path.iter().all(|&(x, y)| {
                let c = tile_center(x, y);
                (c - anchor).length_squared() <= leash_sq || (c - tpos).length_squared() <= range_sq
            });
        if !fits {
            e.move_target = None;
            e.path.clear();
            e.attack_move = false;
        }
        fits
    }

    /// Engages enemy `j` with unit `i`: records it, and chases it when it is out
    /// of weapon range. A chase that cannot stay on the leash leaves a unit at
    /// home engaged and waiting (it re-tries every [`REPATH_PERIOD`] ticks while
    /// the target moves); a unit away from home drops the fight and walks back.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn depth_engage(&mut self, i: usize, j: usize, anchor: Vec2, range: Fixed) {
        self.entities[i].dp.engaged = Some(EntityId(j as u32));
        let pos = self.entities[i].pos;
        let tpos = self.entities[j].pos;
        if (tpos - pos).length_squared() <= range * range {
            return;
        }
        if !self.depth_chase(i, tpos, anchor, range)
            && (pos - anchor).length_squared() > HOME_SLACK * HOME_SLACK
        {
            self.depth_return(i, anchor);
        }
    }

    /// Task 11 auto-acquire and leash, run every depth tick before movement in
    /// ascending entity index. For every unit that may fight on its own:
    /// - an idle unit (no move order) records its anchor if it has none; a unit
    ///   moving on someone else's order (no anchor) is left alone;
    /// - an engagement is dropped when its target is dead, untargetable, or
    ///   further than `LEASH + range` from the anchor, when the unit has strayed
    ///   more than [`LEASH`] from the anchor, or when it is out of ammunition;
    /// - a unit with no engagement takes the nearest targetable enemy within
    ///   `range + ACQUIRE_BONUS` of itself (and `LEASH + range` of its anchor),
    ///   chasing it with an attack-move when it is out of weapon range and
    ///   re-pathing every [`REPATH_PERIOD`] ticks while the target moves;
    /// - with nothing to fight it walks back to its anchor. A unit walking home
    ///   does not acquire on the way (no ping-pong at the leash edge), though
    ///   `run_combat` still fires at anything in range as it passes.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 and u64 for any real game"
    )]
    pub(super) fn run_depth_acquire(&mut self) {
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        for i in 0..self.entities.len() {
            let Some(profile) = self.depth_fighter(i) else {
                continue;
            };
            if self.entities[i].dp.forced.is_some() {
                // Task 13: a player-chosen target overrides everything below.
                self.depth_pursue_forced(i, profile, &grid, &mut scratch);
                continue;
            }
            let e = &self.entities[i];
            let (pos, owner, idle) = (e.pos, e.owner, e.move_target.is_none());
            let anchor = match e.dp.anchor {
                Some(a) => a,
                None if idle => {
                    self.entities[i].dp.anchor = Some(pos);
                    pos
                }
                // Moving on a player or AI order: not ours to steer here.
                None => continue,
            };
            if self.entities[i].dp.stance == Stance::Hold {
                // Task 13: Hold never moves on its own (no acquisition, no
                // chase, no walk home); `run_combat` fires at anything in range.
                self.entities[i].dp.engaged = None;
                continue;
            }
            let e = &self.entities[i];
            let armed = e.ammunition > 0;
            let range = profile.range;
            let leash = leash_of(&e.dp);
            let leash_sq = leash * leash;
            let reach = leash + range;
            let home_sq = (pos - anchor).length_squared();
            let returning = !idle && e.move_target == Some(anchor) && e.dp.engaged.is_none();
            // Validate the current engagement.
            let mut engaged = e.dp.engaged.map(|t| t.0 as usize).filter(|&j| {
                armed
                    && home_sq <= leash_sq
                    && self.depth_can_hit(profile, owner, j)
                    && (self.entities[j].pos - anchor).length_squared() <= reach * reach
            });
            if engaged.is_none() {
                self.entities[i].dp.engaged = None;
            }
            if home_sq > leash_sq || !armed {
                // Off the leash (or dry): drop everything and walk home.
                if !returning && home_sq > HOME_SLACK * HOME_SLACK {
                    self.depth_return(i, anchor);
                }
                continue;
            }
            // Look for a (nearer) enemy when standing still, or when a chase has
            // lost its target; never while walking home.
            if may_acquire(&self.entities[i].dp) && (idle || (engaged.is_none() && !returning)) {
                let ring = range + ACQUIRE_BONUS;
                if let Some(j) =
                    self.depth_nearest_enemy(&grid, &mut scratch, i, profile, ring, (anchor, reach))
                {
                    let nearer = engaged.is_none_or(|k| {
                        let d = |x: usize| (self.entities[x].pos - pos).length_squared();
                        k != j && d(j) < d(k)
                    });
                    if nearer {
                        self.depth_engage(i, j, anchor, range);
                        continue;
                    }
                }
            }
            if let Some(j) = engaged.take() {
                // Keep after a target that has stepped out of weapon range.
                let tpos = self.entities[j].pos;
                let e = &self.entities[i];
                let out_of_range = (tpos - pos).length_squared() > range * range;
                let due = (self.tick + i as u64).is_multiple_of(REPATH_PERIOD);
                if out_of_range && due && e.order_goal != Some(tpos) && may_chase(&e.dp) {
                    let ok = self.depth_chase(i, tpos, anchor, range);
                    if !ok && home_sq > HOME_SLACK * HOME_SLACK {
                        self.depth_return(i, anchor);
                    }
                }
                continue;
            }
            if !returning && home_sq > HOME_SLACK * HOME_SLACK {
                self.depth_return(i, anchor);
            }
        }
    }

    /// Task 11 under-attack response, run at the end of `run_combat` with this
    /// tick's hits as (victim, attacker) in damage order: idle friendly units
    /// within [`ASSIST_RADIUS`] of the victim that are not already fighting and
    /// whose weapon can hit the attacker engage it, on the same leash (the
    /// attacker must lie within `LEASH + range` of the responder's anchor).
    /// Applies to every owner, so the alien base and its waves answer too.
    pub(super) fn depth_respond_to_hits(&mut self, hits: &[(usize, usize)]) {
        if hits.is_empty() {
            return;
        }
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        let assist_sq = ASSIST_RADIUS * ASSIST_RADIUS;
        for &(victim, attacker) in hits {
            let vpos = self.entities[victim].pos;
            let side = self.entities[victim].owner;
            if !self.entities[attacker].alive || self.entities[attacker].hp <= Fixed::ZERO {
                continue;
            }
            grid.gather(vpos, ASSIST_RADIUS, &mut scratch);
            for &k in &scratch {
                let Some(profile) = self.depth_fighter(k) else {
                    continue;
                };
                let e = &self.entities[k];
                if e.owner != side
                    || e.move_target.is_some()
                    || e.dp.engaged.is_some()
                    || e.ammunition == 0
                    || !may_respond(&e.dp)
                    || (e.pos - vpos).length_squared() > assist_sq
                    || !self.depth_can_hit(profile, e.owner, attacker)
                {
                    continue;
                }
                let anchor = e.dp.anchor.unwrap_or(e.pos);
                let reach = leash_of(&e.dp) + profile.range;
                if (self.entities[attacker].pos - anchor).length_squared() > reach * reach {
                    continue;
                }
                self.entities[k].dp.anchor = Some(anchor);
                self.depth_engage(k, attacker, anchor, profile.range);
            }
        }
    }

    /// `clear_dead` hook: forget engagements and forced targets whose target
    /// slot was just freed, before production or waves can hand the slot to a
    /// new entity. A living unit whose forced target died stops where it
    /// stands (and walks any queued legs). A unit that is dead itself (dying
    /// on the same tick) only drops that forced target and its queued legs:
    /// it is never re-ordered (P2 review M3).
    pub(super) fn depth_drop_dangling(&mut self, freed: &[u32]) {
        for i in 0..self.entities.len() {
            let e = &mut self.entities[i];
            if e.dp.engaged.is_some_and(|t| freed.contains(&t.0)) {
                e.dp.engaged = None;
            }
            if e.dp.forced.is_some_and(|t| freed.contains(&t.0)) {
                if e.alive {
                    self.depth_forced_over(i);
                } else {
                    e.dp.forced = None;
                    e.dp.queue.clear();
                }
            }
        }
        // Task 18: a dead or sold building's repair job ends with it.
        for &slot in freed {
            if let Some(e) = self.entities.get_mut(slot as usize) {
                e.dp.repair_ticks = 0;
                e.dp.repair_cd = 0;
            }
        }
    }

    /// The stance of living unit `id` under Kestrel depth; `None` when depth is
    /// off, for buildings and for unknown or dead ids. Read-only.
    #[must_use]
    pub fn stance_of(&self, id: EntityId) -> Option<Stance> {
        if !self.is_depth() {
            return None;
        }
        self.entities
            .get(id.0 as usize)
            .filter(|e| e.alive && matches!(e.kind, Kind::Unit(_)))
            .map(|e| e.dp.stance)
    }

    /// Index of `unit` when it is a living unit owned by `owner` that depth
    /// orders may command: never a Harvester, whose economy loop owns its
    /// moves (P2 review M4: Stop, Hold and stances used to reach them too).
    fn depth_own_unit(&self, owner: PlayerId, unit: EntityId) -> Option<usize> {
        let i = unit.0 as usize;
        self.entities
            .get(i)
            .is_some_and(|e| {
                e.alive
                    && e.owner == owner
                    && matches!(e.kind, Kind::Unit(k) if k != UnitKind::Harvester)
            })
            .then_some(i)
    }

    /// Unit `i` drops every order, engagement and queued leg and stands where
    /// it is, its anchor here (its stance is kept). Used by `Stop`, `Hold`,
    /// the start of an `AttackTarget` and a stance switch to Hold.
    fn depth_halt(&mut self, i: usize) {
        let e = &mut self.entities[i];
        e.move_target = None;
        e.order_goal = None;
        e.path.clear();
        e.attack_move = false;
        e.dp.engaged = None;
        e.dp.forced = None;
        e.dp.anchor = Some(e.pos);
        e.dp.queue.clear();
        e.dp.breach_tried = false;
        e.dp.breach_failed = None;
    }

    /// The end of unit `i`'s forced target (the target died, was lost or
    /// cannot be reached): it halts where it stands, then walks any legs
    /// queued behind the target (Task 14).
    fn depth_forced_over(&mut self, i: usize) {
        let queue = core::mem::take(&mut self.entities[i].dp.queue);
        self.depth_halt(i);
        self.entities[i].dp.queue = queue;
        self.depth_next_leg(i);
    }

    /// [`super::Command::Stop`]: depth only; the owner's living unit (not a
    /// Harvester) drops its orders and holds its current spot as the new
    /// anchor.
    pub(super) fn apply_depth_stop(&mut self, owner: PlayerId, unit: EntityId) {
        if !self.is_depth() {
            return;
        }
        if let Some(i) = self.depth_own_unit(owner, unit) {
            self.depth_halt(i);
        }
    }

    /// [`super::Command::HoldPosition`]: `Stop`, then the Hold stance.
    pub(super) fn apply_depth_hold(&mut self, owner: PlayerId, unit: EntityId) {
        if !self.is_depth() {
            return;
        }
        if let Some(i) = self.depth_own_unit(owner, unit) {
            self.depth_halt(i);
            self.entities[i].dp.stance = Stance::Hold;
        }
    }

    /// [`super::Command::SetStance`]: depth only. Switching to Hold while the
    /// unit is out on its own business (an acquisition chase or a walk home)
    /// stops it on the spot; a player order or a forced target keeps going and
    /// the unit holds where it ends.
    pub(super) fn apply_depth_stance(&mut self, owner: PlayerId, unit: EntityId, stance: Stance) {
        if !self.is_depth() {
            return;
        }
        let Some(i) = self.depth_own_unit(owner, unit) else {
            return;
        };
        let dp = &self.entities[i].dp;
        if stance == Stance::Hold && dp.anchor.is_some() && dp.forced.is_none() {
            self.depth_halt(i);
        }
        self.entities[i].dp.stance = stance;
    }

    /// [`super::Command::AttackTarget`]: depth only. Valid when the unit is the
    /// owner's living armed unit (not a Harvester) with ammunition and the
    /// target is alive, owned by someone else, on a layer the unit's weapon
    /// reaches and tracked by the owner's side (the same [`FORCED_TRACK`] rule
    /// that ends the order every tick). The unit forgets its other orders and
    /// walks toward the target at once. An invalid order is a true no-op (P2
    /// review M1: it used to halt the unit before the track test dropped it,
    /// telling a hand-written line whether a hidden enemy id was alive); the
    /// bridge also drops a target its fogged snapshot did not show.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub(super) fn apply_depth_attack_target(
        &mut self,
        owner: PlayerId,
        unit: EntityId,
        target: EntityId,
    ) {
        if !self.is_depth() {
            return;
        }
        let Some(i) = self.depth_own_unit(owner, unit) else {
            return;
        };
        let e = &self.entities[i];
        let Some(profile) = attack_of(&self.balance, e.kind) else {
            return;
        };
        if e.ammunition == 0 {
            return;
        }
        let profile = self.depth_attack_profile(e.kind, profile);
        let j = target.0 as usize;
        if !self.depth_can_hit(profile, owner, j) {
            return;
        }
        let (tpos, track_sq) = (self.entities[j].pos, FORCED_TRACK * FORCED_TRACK);
        let tracked = self
            .entities
            .iter()
            .any(|o| o.alive && o.owner == owner && (o.pos - tpos).length_squared() <= track_sq);
        if !tracked {
            return;
        }
        self.depth_halt(i);
        let e = &mut self.entities[i];
        e.dp.anchor = None;
        e.dp.forced = Some(EntityId(j as u32));
        self.depth_close_on(i, j, profile.range, true);
    }

    /// [`super::Command::QueueMove`]: depth only, the owner's living unit, not
    /// a Harvester (its economy loop owns its moves). A unit on a player order
    /// (a move or attack-move it was given, or a forced target) appends the
    /// leg, unless it already carries [`QUEUE_CAP`] legs counting the one
    /// under way; any other unit (idle, fighting or walking home on its own)
    /// starts the leg at once, exactly as a `Move` or `AttackMove` would.
    pub(super) fn apply_depth_queue_move(
        &mut self,
        owner: PlayerId,
        unit: EntityId,
        target: Vec2,
        attack_move: bool,
    ) {
        if !self.is_depth() {
            return;
        }
        let Some(i) = self.depth_own_unit(owner, unit) else {
            return;
        };
        let e = &mut self.entities[i];
        let ordered = e.dp.forced.is_some() || (e.move_target.is_some() && e.dp.anchor.is_none());
        if ordered {
            if e.dp.queue.len() + 1 < QUEUE_CAP {
                e.dp.queue.push((target, attack_move));
            }
            return;
        }
        e.dp.queue.clear();
        e.dp.queue.push((target, attack_move));
        self.depth_next_leg(i);
    }

    /// Starts unit `i`'s next queued leg as a player order (no anchor, no
    /// engagement). A leg that cannot be pathed is skipped, so at most
    /// [`QUEUE_CAP`] path searches run and the unit never retries a hopeless
    /// leg; with every leg gone it simply falls idle.
    fn depth_next_leg(&mut self, i: usize) {
        while !self.entities[i].dp.queue.is_empty() {
            let (target, attack_move) = self.entities[i].dp.queue.remove(0);
            let e = &mut self.entities[i];
            e.dp.anchor = None;
            e.dp.engaged = None;
            e.dp.breach_tried = false;
            e.move_target = None;
            e.path.clear();
            e.attack_move = false;
            self.order_unit_to(i, target, attack_move);
            // Task 16: a leg that breaches stands on its forced structure.
            let e = &self.entities[i];
            if e.move_target.is_some() || e.dp.forced.is_some() {
                return;
            }
        }
    }

    /// Task 14, run at the end of every depth `run_movement` in ascending
    /// index: a living unit whose leg ended this tick (arrived, ran out of
    /// path, or could not re-path) and that is not on a forced target starts
    /// its next queued leg, so it is never left idle with legs to walk.
    pub(super) fn depth_advance_queues(&mut self) {
        for i in 0..self.entities.len() {
            let e = &self.entities[i];
            if e.alive && e.move_target.is_none() && e.dp.forced.is_none() && !e.dp.queue.is_empty()
            {
                self.depth_next_leg(i);
            }
        }
    }

    /// The number of waypoint legs living unit `id` has queued behind its
    /// current order (0 when depth is off, for buildings and for unknown or
    /// dead ids). Read-only.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the queue never holds more than QUEUE_CAP legs"
    )]
    pub fn queue_len(&self, id: EntityId) -> u32 {
        if !self.is_depth() {
            return 0;
        }
        self.entities
            .get(id.0 as usize)
            .filter(|e| e.alive && matches!(e.kind, Kind::Unit(_)))
            .map_or(0, |e| e.dp.queue.len() as u32)
    }

    /// The route a living unit with queued legs still has to walk, as
    /// `(point, attack_move)`: the destination of the move under way (the
    /// point it was given), then every queued leg in order. Empty when depth is
    /// off, when the queue is empty, and for unknown or dead ids. A forced
    /// target is never listed (its position is the enemy's). Read-only.
    #[must_use]
    pub fn queue_route(&self, id: EntityId) -> Vec<(Vec2, bool)> {
        let Some(e) = self
            .entities
            .get(id.0 as usize)
            .filter(|e| self.is_depth() && e.alive && !e.dp.queue.is_empty())
        else {
            return Vec::new();
        };
        let mut out = Vec::with_capacity(e.dp.queue.len() + 1);
        if e.dp.forced.is_none() {
            if let Some(goal) = e.order_goal.or(e.move_target) {
                out.push((goal, e.attack_move));
            }
        }
        out.extend_from_slice(&e.dp.queue);
        out
    }

    /// Whether the side `owner` still tracks a forced target at `tpos`: the
    /// chaser `i` itself or any other entity of that side within
    /// [`FORCED_TRACK`] of it.
    fn depth_tracked(
        &self,
        grid: &DepthGrid,
        scratch: &mut Vec<usize>,
        i: usize,
        tpos: Vec2,
    ) -> bool {
        let track_sq = FORCED_TRACK * FORCED_TRACK;
        let e = &self.entities[i];
        if (e.pos - tpos).length_squared() <= track_sq {
            return true;
        }
        grid.gather(tpos, FORCED_TRACK, scratch);
        scratch.iter().any(|&k| {
            let o = &self.entities[k];
            o.alive && o.owner == e.owner && (o.pos - tpos).length_squared() <= track_sq
        })
    }

    /// Unit `i` with forced target `j` (weapon `range`): it stands still while
    /// the target is in weapon range and otherwise walks toward it, re-pathing
    /// every [`REPATH_PERIOD`] ticks while the target moves (`now` re-paths at
    /// once). A target that cannot be reached ends the order, and so does a
    /// fresh walk that would end on the unit's own tile still out of range of
    /// the target (P2 review M2: the nearest reachable tile is no closer, e.g.
    /// a gunship over the sea), so every re-order either gains ground or
    /// releases the unit, never repeats every tick.
    fn depth_close_on(&mut self, i: usize, j: usize, range: Fixed, now: bool) {
        let tpos = self.entities[j].pos;
        let e = &mut self.entities[i];
        if (tpos - e.pos).length_squared() <= range * range {
            e.move_target = None;
            e.order_goal = None;
            e.path.clear();
            e.attack_move = false;
            return;
        }
        let due = now || (self.tick + i as u64).is_multiple_of(REPATH_PERIOD);
        if e.move_target.is_some() && !(due && e.order_goal != Some(tpos)) {
            return;
        }
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, tpos, false);
        let e = &self.entities[i];
        let stuck = match e.move_target {
            None => !self.depth_approach(i, j),
            Some(dest) => {
                self.world_to_tile(dest) == self.world_to_tile(e.pos)
                    && (tpos - dest).length_squared() > range * range
            }
        };
        if stuck {
            self.depth_forced_over(i);
        }
    }

    /// Task 13 per-tick step for a unit on a forced target (called from
    /// [`Sim::run_depth_acquire`] in ascending index): the order ends where the
    /// unit stands when the unit has run dry (P2 review M2, Task 11 ruling 6:
    /// it never stands in front of an enemy it cannot shoot), or when the
    /// target is no longer a living, targetable enemy or is lost from track;
    /// otherwise the unit closes on it.
    fn depth_pursue_forced(
        &mut self,
        i: usize,
        profile: AttackProfile,
        grid: &DepthGrid,
        scratch: &mut Vec<usize>,
    ) {
        let Some(t) = self.entities[i].dp.forced else {
            return;
        };
        let j = t.0 as usize;
        let owner = self.entities[i].owner;
        // Task 16: a breach target is a structure, which never slips away.
        let breach = self.entities[i].dp.breach_tried
            && matches!(
                self.entities.get(j).map(|b| b.kind),
                Some(Kind::Building(_))
            );
        if self.entities[i].ammunition == 0
            || !self.depth_can_hit(profile, owner, j)
            || !(breach || self.depth_tracked(grid, scratch, i, self.entities[j].pos))
        {
            self.depth_forced_over(i);
            return;
        }
        self.depth_close_on(i, j, profile.range, false);
    }

    /// Task 16 breach, from `order_unit_to` under depth when `find_path` found
    /// no route `(start, goal)` for unit `i` ordered to `given`. Only a unit of
    /// the waves' attacker on an order (no anchor: a chase or a walk home never
    /// breaches) that may fight, has ammunition (P2 review M2), has no forced
    /// target and has not yet searched for this order runs one weighted
    /// search, and (P2 review M6) not when its last search for this same goal
    /// tile found no route. The search runs with the defender's walls
    /// enterable at [`BREACH_WALL_COST`] and its other structures at
    /// [`BREACH_BUILDING_COST`]. On a route it walks up to the first structure
    /// on it, forces that structure (Task 13) and puts its order back at the
    /// head of its queue (Task 14), so it resumes the order once the structure
    /// falls (and may breach again for it).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub(super) fn depth_breach(
        &mut self,
        i: usize,
        (start, goal): ((u16, u16), (u16, u16)),
        given: Vec2,
        attack_move: bool,
    ) {
        let Some(cfg) = self.waves else {
            return;
        };
        let e = &self.entities[i];
        if e.owner != cfg.attacker
            || e.dp.breach_tried
            || e.dp.anchor.is_some()
            || e.dp.forced.is_some()
            || e.ammunition == 0
            || self.depth_fighter(i).is_none()
        {
            return;
        }
        self.entities[i].dp.breach_tried = true;
        if self.entities[i].dp.breach_failed == Some(goal) {
            return;
        }
        // Set for every way the search can fail; cleared on a route below.
        self.entities[i].dp.breach_failed = Some(goal);
        #[cfg(test)]
        {
            self.breach_searches += 1;
        }
        let width = usize::from(self.map.width());
        let mut cost = alloc::vec![None; width * usize::from(self.map.height())];
        for b in &self.entities {
            if let (true, Some((x, y)), Kind::Building(kind)) =
                (b.alive && b.owner == cfg.defender, b.tile, b.kind)
            {
                cost[usize::from(y) * width + usize::from(x)] =
                    Some(if kind == BuildingKind::Wall {
                        BREACH_WALL_COST
                    } else {
                        BREACH_BUILDING_COST
                    });
            }
        }
        let extra = |x: u16, y: u16| cost[usize::from(y) * width + usize::from(x)];
        let Some(mut path) = find_path_weighted(&self.map, start, goal, &extra) else {
            return;
        };
        let Some(k) = path.iter().position(|&(x, y)| {
            !self
                .map
                .tile(i32::from(x), i32::from(y))
                .is_some_and(|t| t.passable)
        }) else {
            return;
        };
        let blocked = path[k];
        let Some(j) = self.entities.iter().position(|b| {
            b.alive
                && b.owner == cfg.defender
                && b.tile == Some(blocked)
                && matches!(b.kind, Kind::Building(_))
        }) else {
            return;
        };
        path.truncate(k);
        let wall = self.entities[j].pos;
        let e = &mut self.entities[i];
        e.dp.breach_failed = None;
        e.dp.engaged = None;
        e.dp.forced = Some(EntityId(j as u32));
        e.dp.queue.insert(0, (given, attack_move));
        e.dp.queue.truncate(QUEUE_CAP - 1);
        e.order_goal = Some(wall);
        e.move_target = path.last().map(|&(x, y)| tile_center(x, y));
        e.attack_move = false;
        e.path = path;
    }

    /// Task 16: walks unit `i` toward forced structure `j` when no plain route
    /// to a tile beside it exists (its nearest open tile lies on the far side
    /// of a wall line): a search with only that structure's hex enterable,
    /// stopping one hex short. False when `j` is not a building or no such
    /// route exists.
    fn depth_approach(&mut self, i: usize, j: usize) -> bool {
        let Some(goal) = self.entities[j]
            .tile
            .filter(|_| matches!(self.entities[j].kind, Kind::Building(_)))
        else {
            return false;
        };
        let start = self.world_to_tile(self.entities[i].pos);
        let extra = |x: u16, y: u16| ((x, y) == goal).then_some(BREACH_WALL_COST);
        let Some(mut path) = find_path_weighted(&self.map, start, goal, &extra) else {
            return false;
        };
        path.pop();
        let wall = self.entities[j].pos;
        let e = &mut self.entities[i];
        e.order_goal = Some(wall);
        e.move_target = Some(path.last().map_or_else(
            || hex::center(start.0, start.1),
            |&(x, y)| tile_center(x, y),
        ));
        e.attack_move = false;
        e.path = path;
        true
    }

    /// Re-issues unit `i`'s current order from where it stands (its path no
    /// longer starts beside its tile). An order that can no longer be pathed
    /// is dropped, so the unit idles instead of retrying every tick.
    pub(super) fn depth_repath(&mut self, i: usize) {
        let e = &mut self.entities[i];
        let Some(goal) = e.order_goal.or(e.move_target) else {
            return;
        };
        let attack_move = e.attack_move;
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, goal, attack_move);
    }

    /// Every entity's position, taken just before `run_movement` so
    /// [`Sim::run_depth_separation`] can tell which units advanced this tick.
    pub(super) fn depth_positions(&self) -> Vec<Vec2> {
        self.entities.iter().map(|e| e.pos).collect()
    }

    /// Task 12 separation, run every depth tick right after `run_movement`
    /// (`before` holds the positions from just before it). Living units are
    /// bucketed by the combat grid; every same-owner pair `i < j` (ascending
    /// index, positions updated in place) on the same layer (ground with
    /// ground, air with air) closer than [`SEPARATION`] is pushed apart along
    /// its axis by half the overlap each. Coincident units use the hex axis
    /// `j % 6`. A unit that advanced this tick is never pushed: the unit at
    /// rest steps aside by the whole overlap instead, and two advancing units
    /// pass, so separation never alters a marching unit's route and can never
    /// jam a ford, a corridor or a waypoint (a crowd converging on one point
    /// spreads once it stops). A push that would put a ground unit on an
    /// impassable tile (water, a building footprint) or any unit off the map
    /// is skipped for that unit only. An idle unit's anchor moves with its
    /// push, so the leash never walks it back into the crowd.
    pub(super) fn run_depth_separation(&mut self, before: &[Vec2]) {
        let layer: Vec<Option<bool>> = self
            .entities
            .iter()
            .map(|e| {
                (e.alive && e.hp > Fixed::ZERO && matches!(e.kind, Kind::Unit(_)))
                    .then(|| is_air_of(&self.balance, e.kind))
            })
            .collect();
        // A unit that advanced this tick, or (Task 13) one holding position,
        // keeps its ground: the other unit of the pair steps aside.
        let moved: Vec<bool> = self
            .entities
            .iter()
            .enumerate()
            .map(|(i, e)| before.get(i).is_some_and(|&p| p != e.pos) || e.dp.stance == Stance::Hold)
            .collect();
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        let sep_sq = SEPARATION * SEPARATION;
        for i in 0..self.entities.len() {
            let Some(air) = layer[i] else {
                continue;
            };
            grid.gather(self.entities[i].pos, SEPARATION, &mut scratch);
            for &j in &scratch {
                if j <= i
                    || layer[j] != Some(air)
                    || self.entities[j].owner != self.entities[i].owner
                {
                    continue;
                }
                let d = self.entities[j].pos - self.entities[i].pos;
                let dsq = d.length_squared();
                if dsq >= sep_sq {
                    continue;
                }
                let dist = if dsq > Fixed::ZERO {
                    d.length()
                } else {
                    Fixed::ZERO
                };
                let overlap = SEPARATION - dist;
                let axis = if dist > Fixed::ZERO {
                    d.scale(Fixed::ONE / dist)
                } else {
                    let (ax, ay) = HEX_AXES[j % 6];
                    Vec2::new(Fixed::from_ratio(ax, 1000), Fixed::from_ratio(ay, 1000))
                };
                // Half the overlap each between units at rest; a unit that
                // advanced this tick holds its ground and the one at rest steps
                // aside by the whole overlap; two advancing units pass.
                let (pi, pj) = match (moved[i], moved[j]) {
                    (false, false) => {
                        let half = overlap / Fixed::from_int(2);
                        (half, half)
                    }
                    (true, false) => (Fixed::ZERO, overlap),
                    (false, true) => (overlap, Fixed::ZERO),
                    (true, true) => continue,
                };
                if pi > Fixed::ZERO {
                    self.depth_push(i, axis.scale(-pi), air);
                }
                if pj > Fixed::ZERO {
                    self.depth_push(j, axis.scale(pj), air);
                }
            }
        }
    }

    /// Moves unit `k` by `delta` unless that lands a ground unit on an
    /// impassable tile or any unit off the map; an idle unit's anchor follows.
    fn depth_push(&mut self, unit: usize, delta: Vec2, air: bool) {
        let next = self.entities[unit].pos + delta;
        let (width, height) = (self.map.width(), self.map.height());
        let max_x = Fixed::from_int(i32::from(width) - 1) * Fixed::from_ratio(3, 4) + Fixed::ONE;
        let max_y = Fixed::from_int(i32::from(height)) + Fixed::from_ratio(1, 2);
        if next.x < Fixed::ZERO || next.y < Fixed::ZERO || next.x > max_x || next.y > max_y {
            return;
        }
        if !air {
            let (tx, ty) = hex::from_world(next, width, height);
            if !self
                .map
                .tile(i32::from(tx), i32::from(ty))
                .is_some_and(|t| t.passable)
            {
                return;
            }
        }
        let e = &mut self.entities[unit];
        e.pos = next;
        if e.move_target.is_none() {
            if let Some(a) = e.dp.anchor {
                e.dp.anchor = Some(a + delta);
            }
        }
    }

    /// For each attack-mover, the nearest targetable enemy inside its
    /// acquisition ring (`range + ACQUIRE_BONUS`), measured before anyone moves
    /// this tick. `run_movement` steps the unit straight at it when nothing is
    /// in weapon range yet and the step lands on passable ground.
    pub(super) fn depth_steer_points(&self) -> Vec<Option<Vec2>> {
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        (0..self.entities.len())
            .map(|i| {
                let e = &self.entities[i];
                if !e.attack_move || e.move_target.is_none() || e.ammunition == 0 {
                    return None;
                }
                let profile = self.depth_fighter(i)?;
                let ring = profile.range + ACQUIRE_BONUS;
                // No anchor bound for an order-driven attack-move: the ring is
                // the only limit (`reach` = `ring` keeps the anchor test inert).
                self.depth_nearest_enemy(&grid, &mut scratch, i, profile, ring, (e.pos, ring))
                    .map(|j| self.entities[j].pos)
            })
            .collect()
    }
}

/// One straight step of `speed` from `pos` toward `goal` for an attack-mover
/// closing on an enemy in its acquisition ring, or `None` when a ground unit's
/// step would land on an impassable tile (it then keeps following its path).
pub(super) fn steer_step(
    map: &Map,
    pos: Vec2,
    goal: Vec2,
    speed: Fixed,
    flies: bool,
) -> Option<Vec2> {
    let dir = goal - pos;
    let dist = dir.length();
    if dist <= Fixed::ZERO {
        return None;
    }
    let next = if dist <= speed {
        goal
    } else {
        pos + dir.scale(speed / dist)
    };
    let (x, y) = hex::from_world(next, map.width(), map.height());
    (flies
        || map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.passable))
    .then_some(next)
}

/// What a depth ground unit does with its next movement step.
pub(super) enum GroundStep {
    /// The step lands on passable ground: take it.
    Clear,
    /// The step would land in water or on a footprint: walk toward the centre
    /// of the unit's own tile instead (a segment inside one hex), from where
    /// the straight line to an adjacent waypoint never leaves the two hexes.
    Recentre(Vec2),
    /// Recentring cannot help: the waypoint itself turned impassable (a
    /// structure raised on it), or it is no tile centre next to this tile, or
    /// the unit is already centred and still blocked. Path again from here.
    Repath,
}

/// Task 12 corner guard for a ground unit at `pos` about to take one step of
/// `speed` toward `subgoal`. Units travel between adjacent tile centres, a
/// segment that stays inside those two hexes; a unit pushed off centre by
/// separation could otherwise clip a corner of a river hex beside the ford.
///
/// P2 review I1: recentring only helps when `subgoal` is the centre of a
/// passable hex next to the unit's own, since from the centre that segment
/// never leaves the two hexes. In every other case (the waypoint's hex is
/// impassable, or the waypoint is farther away or off centre) the unit would
/// walk back to the centre, step out again and be blocked again forever, so
/// it re-paths instead. A waypoint whose hex turned impassable re-paths at
/// once, without walking up to it first.
pub(super) fn ground_step(map: &Map, pos: Vec2, subgoal: Vec2, speed: Fixed) -> GroundStep {
    let dir = subgoal - pos;
    let dist = dir.length();
    let next = if dist <= speed {
        subgoal
    } else {
        pos + dir.scale(speed / dist)
    };
    let (width, height) = (map.width(), map.height());
    let passable = |p: Vec2| {
        let (x, y) = hex::from_world(p, width, height);
        map.tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.passable)
    };
    // A unit already standing somewhere impassable (a structure raised under
    // it) walks out along its path exactly as before.
    if !passable(pos) {
        return GroundStep::Clear;
    }
    if !passable(subgoal) {
        return GroundStep::Repath;
    }
    if passable(next) {
        return GroundStep::Clear;
    }
    let (hx, hy) = hex::from_world(pos, width, height);
    let centre = hex::center(hx, hy);
    let (sx, sy) = hex::from_world(subgoal, width, height);
    let beside = hex::center(sx, sy) == subgoal && hex::distance((hx, hy), (sx, sy)) == 1;
    if centre == pos || !beside {
        return GroundStep::Repath;
    }
    let d = centre - pos;
    let len = d.length();
    GroundStep::Recentre(if len <= speed {
        centre
    } else {
        pos + d.scale(speed / len)
    })
}

/// Within this distance of its anchor an idle unit counts as home (a return
/// order always ends exactly on the anchor; the slack only absorbs drift).
const HOME_SLACK: Fixed = Fixed::ONE;

/// Stance hook: how far this unit may stray from its anchor (Aggressive 6,
/// Defensive 3, Hold 0: it never leaves).
const fn leash_of(dp: &DepthUnit) -> Fixed {
    match dp.stance {
        Stance::Aggressive => LEASH,
        Stance::Defensive => DEFENSIVE_LEASH,
        Stance::Hold => Fixed::ZERO,
    }
}

/// Stance hook: whether this unit picks fights on sight. Only Aggressive does
/// (Defensive and Hold still fire at whatever enters weapon range, through
/// `run_combat`); a unit on a forced target never looks elsewhere.
const fn may_acquire(dp: &DepthUnit) -> bool {
    matches!(dp.stance, Stance::Aggressive) && dp.forced.is_none()
}

/// Stance hook: whether this unit answers a hit on itself or an ally within
/// [`ASSIST_RADIUS`]. Hold never moves for one; a forced unit keeps its target.
const fn may_respond(dp: &DepthUnit) -> bool {
    !matches!(dp.stance, Stance::Hold) && dp.forced.is_none()
}

/// Stance hook: whether this unit may leave its spot to chase (Hold never
/// moves on its own).
const fn may_chase(dp: &DepthUnit) -> bool {
    !matches!(dp.stance, Stance::Hold)
}

/// Living entities bucketed by the combat grid (`COMBAT_CELL` tiles), each
/// cell in ascending index, rebuilt from the current positions on demand.
struct DepthGrid {
    cols: i32,
    rows: i32,
    cells: Vec<Vec<usize>>,
}

impl DepthGrid {
    #[allow(
        clippy::cast_sign_loss,
        reason = "cell counts are positive for any real map"
    )]
    fn build(sim: &Sim) -> Self {
        let cols = (i32::from(sim.map.width()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let rows = (i32::from(sim.map.height()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let mut g = Self {
            cols,
            rows,
            cells: alloc::vec![Vec::new(); (cols * rows).max(1) as usize],
        };
        for (i, e) in sim.entities.iter().enumerate() {
            if e.alive {
                let c = g.cell(e.pos);
                g.cells[c].push(i);
            }
        }
        g
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "cell coordinates are clamped into the map bounds"
    )]
    fn coords(&self, p: Vec2) -> (i32, i32) {
        let cx = (p.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, self.cols - 1);
        let cy = (p.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, self.rows - 1);
        (cx, cy)
    }

    #[allow(clippy::cast_sign_loss, reason = "cell coordinates are clamped")]
    fn cell(&self, p: Vec2) -> usize {
        let (cx, cy) = self.coords(p);
        (cy * self.cols + cx) as usize
    }

    /// Every living entity in the cells that can hold a point within `radius`
    /// of `p`, in ascending index order.
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "radius is a few tiles; cell coordinates are bounds-checked"
    )]
    fn gather(&self, p: Vec2, radius: Fixed, out: &mut Vec<usize>) {
        out.clear();
        let k = radius.to_int_floor() as i32 / COMBAT_CELL + 1;
        let (cx, cy) = self.coords(p);
        for ny in (cy - k).max(0)..=(cy + k).min(self.rows - 1) {
            for nx in (cx - k).max(0)..=(cx + k).min(self.cols - 1) {
                out.extend_from_slice(&self.cells[(ny * self.cols + nx) as usize]);
            }
        }
        out.sort_unstable();
    }
}

/// Task 17: abilities and the Upgrades tracks (the legacy Ascendancy
/// doctrines, money only and capped per era) under depth. Upgrade levels live
/// in the civ's `doctrine_levels` (already hashed), so no new state is added.
impl Sim {
    /// Whether `owner` may cast `kind` under depth: a `Barrage` needs
    /// [`BARRAGE_TECH`] researched, an `EmpBurst` is always allowed (it rides
    /// the gunship), a `NaniteField` comes with the Capital (its only carrier).
    #[must_use]
    pub(super) fn depth_ability_allowed(&self, owner: PlayerId, kind: AbilityKind) -> bool {
        match kind {
            AbilityKind::Barrage => self.civs[usize::from(owner.0)]
                .researched_techs
                .get(BARRAGE_TECH),
            AbilityKind::EmpBurst | AbilityKind::NaniteField => true,
        }
    }

    /// The cooldown an ability of base cooldown `base` starts for `owner`
    /// under depth. The perk hook of Task 23; `base` for now.
    #[must_use]
    #[allow(
        clippy::unused_self,
        clippy::missing_const_for_fn,
        reason = "Task 23 reads the owner's perks here"
    )]
    pub(super) fn depth_ability_cooldown(&self, owner: PlayerId, base: u32) -> u32 {
        let _ = owner;
        base
    }

    /// `owner`'s Upgrades levels: weapons, armour, vitality.
    #[must_use]
    pub fn upgrade_levels(&self, owner: PlayerId) -> [u16; 3] {
        let lv = &self.civs[usize::from(owner.0)].doctrine_levels;
        [lv[DOC_WEAPONS], lv[DOC_ARMOR], lv[DOC_VITALITY]]
    }

    /// The level cap per Upgrades track for `owner` (its era decides).
    fn upgrade_cap(&self, owner: PlayerId) -> u16 {
        if self.civs[usize::from(owner.0)].era >= 1 {
            UPGRADE_CAP_ERA1
        } else {
            UPGRADE_CAP_ERA0
        }
    }

    /// The money price of `owner`'s next level on Upgrades `track`:
    /// `UPGRADE_BASE + UPGRADE_STEP * level`. `None` at the era cap, for the
    /// forge (track 3) or any other track, and without depth.
    #[must_use]
    pub fn upgrade_cost(&self, owner: PlayerId, track: u8) -> Option<Fixed> {
        if !self.is_depth() || track >= UPGRADE_TRACKS {
            return None;
        }
        let level = self.upgrade_levels(owner)[usize::from(track)];
        (level < self.upgrade_cap(owner)).then(|| {
            Fixed::from_int(UPGRADE_BASE) + Fixed::from_int(UPGRADE_STEP * i32::from(level))
        })
    }

    /// Buys `owner`'s next level on Upgrades `track` (validate, then spend),
    /// or grants it without charge when `free` (Task 23's perk). Refused for
    /// the forge, at the era cap, without depth and, unless free, when the
    /// owner cannot pay.
    pub(super) fn apply_depth_upgrade(&mut self, owner: PlayerId, track: u8, free: bool) {
        let Some(cost) = self.upgrade_cost(owner, track) else {
            return;
        };
        let c = &mut self.civs[usize::from(owner.0)];
        if !free {
            if c.money < cost {
                return;
            }
            c.money = c.money - cost;
        }
        let t = [DOC_WEAPONS, DOC_ARMOR, DOC_VITALITY][usize::from(track)];
        c.doctrine_levels[t] += 1;
    }
}

/// Task 18: the depth economy. Refineries cost more with each one owned, and a
/// repair is a job that heals over [`REPAIR_TICKS`] with a cooldown. Both are
/// the single source Task 23's perks adjust.
impl Sim {
    /// The money `owner` pays to build `kind`: under depth a Refinery costs its
    /// base plus [`REFINERY_STEP`] for each refinery `owner` already has (alive
    /// or under construction; a sold one stops counting at once). Every other
    /// kind, and every kind with depth off, costs [`Sim::building_cost`].
    #[must_use]
    pub fn depth_building_cost(&self, owner: PlayerId, kind: BuildingKind) -> Fixed {
        let base = self.building_cost(kind);
        if !self.is_depth() || kind != BuildingKind::Refinery {
            return base;
        }
        let refineries = self
            .entities
            .iter()
            .filter(|e| {
                e.alive
                    && e.hp > Fixed::ZERO
                    && e.owner == owner
                    && e.kind == Kind::Building(BuildingKind::Refinery)
            })
            .count();
        base + Fixed::from_int(REFINERY_STEP * i32::try_from(refineries).unwrap_or(0))
    }

    /// The money `owner` pays up front for a depth repair of a `kind`
    /// building: a tenth of its price, at least [`REPAIR_MIN_COST`].
    #[must_use]
    pub fn depth_repair_cost(&self, owner: PlayerId, kind: BuildingKind) -> Fixed {
        let _ = owner;
        let tenth = self.balance.building(kind).money_cost / Fixed::from_int(10);
        let floor = Fixed::from_int(REPAIR_MIN_COST);
        if tenth > floor {
            tenth
        } else {
            floor
        }
    }

    /// Ticks until living building `id` may be repaired again under depth (0
    /// when it may now). `None` with depth off, for units and for unknown or
    /// dead ids. Read-only.
    #[must_use]
    pub fn repair_cooldown(&self, id: EntityId) -> Option<u32> {
        if !self.is_depth() {
            return None;
        }
        self.entities
            .get(id.0 as usize)
            .filter(|e| e.alive && matches!(e.kind, Kind::Building(_)))
            .map(|e| e.dp.repair_cd)
    }

    /// Starts a repair job on `owner`'s damaged building (depth only; the
    /// classic instant repair stays in `apply_repair`). Refused while the
    /// building's cooldown runs, at full health, and when `owner` cannot pay
    /// [`Sim::depth_repair_cost`], which is charged up front.
    pub(super) fn apply_depth_repair(&mut self, owner: PlayerId, building: EntityId) {
        let idx = building.0 as usize;
        let Some(kind) = self.entities.get(idx).and_then(|e| match e.kind {
            Kind::Building(kind)
                if e.alive
                    && e.hp > Fixed::ZERO
                    && e.owner == owner
                    && e.dp.repair_cd == 0
                    && e.dp.repair_ticks == 0
                    && e.hp < self.balance.building(kind).max_hp =>
            {
                Some(kind)
            }
            _ => None,
        }) else {
            return;
        };
        let cost = self.depth_repair_cost(owner, kind);
        let p = usize::from(owner.0);
        if self.civs[p].money < cost {
            return;
        }
        self.civs[p].money = self.civs[p].money - cost;
        let dp = &mut self.entities[idx].dp;
        dp.repair_ticks = REPAIR_TICKS;
        dp.repair_cd = REPAIR_COOLDOWN;
    }

    /// Advances every depth repair job one tick and counts down the repair
    /// cooldowns. A job heals `max_hp / 5` in [`REPAIR_TICKS`] equal integer
    /// shares of the running total (so the whole chunk lands exactly), capped
    /// at full health, where it ends early. Runs after `clear_dead`, so only
    /// living buildings are touched.
    pub(super) fn run_depth_repairs(&mut self) {
        let total = i64::from(REPAIR_TICKS);
        for e in &mut self.entities {
            if !e.alive || (e.dp.repair_ticks == 0 && e.dp.repair_cd == 0) {
                continue;
            }
            e.dp.repair_cd = e.dp.repair_cd.saturating_sub(1);
            let Kind::Building(kind) = e.kind else {
                e.dp.repair_ticks = 0;
                continue;
            };
            if e.dp.repair_ticks == 0 {
                continue;
            }
            let max = self.balance.building(kind).max_hp;
            let chunk = (max / Fixed::from_int(5)).to_bits();
            let done = total - i64::from(e.dp.repair_ticks);
            let heal = Fixed::from_bits(chunk * (done + 1) / total - chunk * done / total);
            let healed = e.hp + heal;
            e.hp = if healed < max { healed } else { max };
            e.dp.repair_ticks -= 1;
            if e.hp >= max {
                e.dp.repair_ticks = 0;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        depth_air_damage_pct, is_air_of, EntityId, Kind, ACQUIRE_BONUS, AT_AIR_PCT,
        DEFENSIVE_LEASH, FORCED_TRACK, LEASH, QUEUE_CAP,
    };
    use crate::fixed::Fixed;
    use crate::game::ability::AbilityKind;
    use crate::game::hex;
    use crate::game::map::Map;
    use crate::game::scenario::{
        kestrel_reach, kestrel_reach_classic, kestrel_reach_with, lane_defense, survival,
        MatchOptions, Scenario,
    };
    use crate::game::sim::{
        Command, DepthScore, Difficulty, EntityKindView, PlayerId, Sim, Stance,
    };
    use crate::game::stats::{BuildingKind, UnitKind};
    use crate::vec::Vec2;
    use alloc::vec::Vec;

    /// `survival(7)` after 3000 host ticks, measured at 503fd7c (before the
    /// depth flag existed). Every later core task re-runs this unchanged.
    const SURVIVAL_PIN: u64 = 1_622_883_436_588_820_810;
    /// Classic Kestrel (`kestrel_reach_classic(3)`, no depth) after 6000 host
    /// ticks, measured at 503fd7c with the bridge's command list.
    const KESTREL_CLASSIC_PIN: u64 = 2_849_524_003_663_712_283;

    #[test]
    fn depth_is_only_enabled_by_kestrel() {
        assert!(kestrel_reach(3).is_depth());
        assert!(!survival(3).is_depth());
        assert!(!lane_defense(3).is_depth());
        assert!(!kestrel_reach_classic(3).is_depth());
    }

    #[test]
    fn survival_and_classic_kestrel_hashes_are_pinned_across_depth() {
        let mut s = survival(7);
        for _ in 0..3000 {
            let c = Scenario::Survival.host_commands(&s);
            s.step(&c);
        }
        assert_eq!(s.state_hash(), SURVIVAL_PIN);
        let mut k = kestrel_reach_classic(3);
        for _ in 0..6000 {
            let c = Scenario::KestrelReach.host_commands(&k);
            k.step(&c);
        }
        assert_eq!(k.state_hash(), KESTREL_CLASSIC_PIN);
    }

    /// Fixed player script exercising every depth command (later tasks append theirs).
    pub(super) fn scripted_player(s: &Sim) -> Vec<Command> {
        let mut out = Vec::new();
        if s.tick() == 600 {
            for v in s.views().into_iter().filter(|v| {
                v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(UnitKind::Infantry))
            }) {
                out.push(Command::AttackMove {
                    owner: PlayerId(0),
                    unit: v.id,
                    target: hex::center(20, 10),
                });
            }
        }
        // Task 13: stance, stop, hold and a forced target between ticks 900
        // and 1200 (on the lowest-id living rifles; the target is the
        // lowest-id living alien unit, valid or not, deterministic either way).
        let rifles: Vec<_> = s
            .views()
            .into_iter()
            .filter(|v| {
                v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(UnitKind::Infantry))
            })
            .map(|v| v.id)
            .collect();
        let alien = s
            .views()
            .into_iter()
            .find(|v| v.owner == PlayerId(1) && matches!(v.kind, EntityKindView::Unit(_)))
            .map(|v| v.id);
        match (s.tick(), rifles.first(), rifles.get(1)) {
            (900, Some(&unit), _) => out.push(Command::SetStance {
                owner: PlayerId(0),
                unit,
                stance: Stance::Defensive,
            }),
            (1000, Some(&unit), _) => out.push(Command::Stop {
                owner: PlayerId(0),
                unit,
            }),
            (1100, _, Some(&unit)) => out.push(Command::HoldPosition {
                owner: PlayerId(0),
                unit,
            }),
            (1200, Some(&unit), _) => {
                if let Some(target) = alien {
                    out.push(Command::AttackTarget {
                        owner: PlayerId(0),
                        unit,
                        target,
                    });
                }
            }
            // Task 14: a three-leg queue (the last an attack-move) on the
            // second rifle, which has been holding since tick 1100.
            (1300, _, Some(&unit)) => {
                for (target, attack_move) in [
                    (hex::center(14, 10), false),
                    (hex::center(16, 13), false),
                    (hex::center(20, 10), true),
                ] {
                    out.push(Command::QueueMove {
                        owner: PlayerId(0),
                        unit,
                        target,
                        attack_move,
                    });
                }
            }
            // Task 17: one weapons Upgrade (era 0 price 150).
            (1400, _, _) => out.push(Command::Ascend {
                owner: PlayerId(0),
                track: 0,
            }),
            _ => {}
        }
        out
    }

    #[test]
    fn same_inputs_twice_give_the_same_depth_hash_and_replay() {
        let run = || {
            let mut s = kestrel_reach(11);
            let mut log = Vec::new();
            for _ in 0..5000 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                c.extend(scripted_player(&s));
                s.step(&c);
                log.push(c);
            }
            // Task 17: the scripted weapons Upgrade was bought.
            assert_eq!(s.upgrade_levels(PlayerId(0))[0], 1);
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = kestrel_reach(11);
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// Host commands are a pure function of the world: building them never
    /// mutates the sim and asking twice gives the same list, so a replay that
    /// re-derives them per tick (the bridge, the tests, `verify-run`) and one
    /// that replays a recorded log reach the same hash, including from a save
    /// (a clone) taken mid-match. Since Task 19 the alien AI is awake from
    /// tick 0, so the replayed half carries its orders throughout.
    #[test]
    fn host_commands_are_pure_and_replay_from_a_mid_match_save() {
        // Fixed step counts, never `while tick < n`: a decided Earthfront match
        // stops advancing its tick (the undefended base can fall near t=4100).
        const STEPS: u32 = 6000;
        const SAVE_AT: u32 = 4000;
        let mut s = kestrel_reach(11);
        let mut save = None;
        let mut log = Vec::new();
        for step in 0..STEPS {
            let before = s.state_hash();
            let c = Scenario::KestrelReach.host_commands(&s);
            assert_eq!(s.state_hash(), before, "host_commands mutated the sim");
            assert_eq!(
                alloc::format!("{c:?}"),
                alloc::format!("{:?}", Scenario::KestrelReach.host_commands(&s)),
                "host_commands is not repeatable at tick {}",
                s.tick()
            );
            let mut c = c;
            c.extend(scripted_player(&s));
            if step == SAVE_AT {
                save = Some(s.clone());
            }
            if step >= SAVE_AT {
                log.push(c.clone());
            }
            s.step(&c);
        }
        // Task 19: the alien AI acts from tick 0 (it used to wake with wave
        // one, which `waves_survived() > 0` checked); its own orders must be in
        // the replayed half. The probe script orders only at ticks 1650 and
        // 3300, before the save.
        assert!(
            log.iter().flatten().any(|c| matches!(
                c,
                Command::Build { owner: P1, .. }
                    | Command::Train { owner: P1, .. }
                    | Command::Research { owner: P1, .. }
                    | Command::Ascend { owner: P1, .. }
                    | Command::AttackMove { owner: P1, .. }
            )),
            "the replayed half must carry alien AI orders"
        );
        // Continue the save by re-deriving host commands live.
        let mut live = save.clone().expect("save taken");
        for _ in SAVE_AT..STEPS {
            let mut c = Scenario::KestrelReach.host_commands(&live);
            c.extend(scripted_player(&live));
            live.step(&c);
        }
        // Continue the save from the recorded log only.
        let mut logged = save.expect("save taken");
        for c in &log {
            logged.step(c);
        }
        assert_eq!(live.state_hash(), s.state_hash());
        assert_eq!(logged.state_hash(), s.state_hash());
    }

    /// Depth changes nothing about the starting world: the depth and classic
    /// Kestrel builds show the same entities, yet only the depth one hashes the
    /// depth state (its marker), so a depth replay can never verify against a
    /// classic world.
    #[test]
    fn depth_kestrel_starts_from_the_classic_world_but_hashes_apart() {
        let depth = kestrel_reach(3);
        let classic = kestrel_reach_classic(3);
        assert_eq!(
            alloc::format!("{:?}", depth.views()),
            alloc::format!("{:?}", classic.views())
        );
        assert_ne!(depth.state_hash(), classic.state_hash());
    }

    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(Fixed::from_int(x), Fixed::from_int(y))
    }

    /// An open 40x40 Earthfront arena with the depth rules on.
    fn depth_arena() -> Sim {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        s.enable_depth();
        s
    }

    #[test]
    fn idle_rifle_engages_an_enemy_inside_its_acquisition_ring() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Infantry,
            v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
        );
        let hp0 = s.views().iter().find(|x| x.id == b).unwrap().hp;
        for _ in 0..120 {
            s.step(&[]);
        }
        let hp1 = s
            .views()
            .iter()
            .find(|x| x.id == b)
            .map_or(Fixed::ZERO, |x| x.hp);
        assert!(hp1 < hp0, "the idle unit never engaged");
        let _ = a;
    }

    #[test]
    fn idle_rifle_ignores_an_enemy_outside_the_ring() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.add_unit(
            P1,
            UnitKind::Harvester,
            v(10, 20) + Vec2::new(r + Fixed::from_int(4), Fixed::ZERO),
        );
        for _ in 0..120 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(v(10, 20)));
    }

    #[test]
    fn unit_returns_to_anchor_after_target_flees_past_leash() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Tank,
            v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
        );
        // Dry, so the tank cannot simply kill the chaser before it flees.
        s.entities[b.0 as usize].ammunition = 0;
        let mut furthest = Fixed::ZERO;
        for _ in 0..30 {
            s.step(&[]);
        }
        s.step(&[Command::Move {
            owner: P1,
            unit: b,
            target: v(38, 20),
        }]);
        for _ in 0..900 {
            s.step(&[]);
            furthest = furthest.max((s.position(a).unwrap() - v(10, 20)).length());
        }
        let home = s.position(a).unwrap();
        assert!(
            (home - v(10, 20)).length_squared() < Fixed::ONE,
            "never came back: {home:?}"
        );
        assert!(furthest > Fixed::ONE, "it never chased at all");
        assert!(
            furthest <= LEASH + Fixed::ONE,
            "chased {furthest:?} from its anchor"
        );
        // Home and idle: no order left.
        assert!(s.entities[a.0 as usize].move_target.is_none());
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
    }

    #[test]
    fn idle_units_defend_a_building_under_attack() {
        let mut s = depth_arena();
        s.add_building(P0, BuildingKind::Barracks, 20, 20);
        let bpos = s.views().iter().find(|x| x.owner == P0).unwrap().pos;
        let r = UnitKind::Infantry.stats().attack.range;
        // attacker hits the barracks from the east; the riflemen stand 5 west of the
        // barracks, beyond their own acquisition ring of the attacker
        s.add_unit(P1, UnitKind::Infantry, bpos + Vec2::new(r, Fixed::ZERO));
        let guards: Vec<_> = (0..3)
            .map(|i| {
                s.add_unit(
                    P0,
                    UnitKind::Infantry,
                    bpos + Vec2::new(Fixed::from_int(-5), Fixed::from_int(i)),
                )
            })
            .collect();
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P1), 0, "guards never answered the attack");
        let _ = guards;
    }

    #[test]
    fn a_player_move_clears_the_anchor() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[]);
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(14, 20),
        }]);
        for _ in 0..200 {
            s.step(&[]);
        }
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(
            (s.position(a).unwrap() - v(14, 20)).length_squared() < Fixed::ONE,
            "snapped back to the old anchor"
        );
    }

    /// A unit carrying a player Move walks past an enemy inside its acquisition
    /// ring along exactly the path it takes with depth off: auto-acquire never
    /// pulls it off the order.
    #[test]
    fn a_unit_with_a_player_move_is_never_acquired_away() {
        let trace = |depth: bool| {
            let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
            s.enable_earthfront();
            if depth {
                s.enable_depth();
            }
            let a = s.add_unit(P0, UnitKind::Infantry, v(4, 20));
            // Beside the route: inside the ring (6), outside weapon range (3).
            // Dry, so it never fires or moves itself.
            let b = s.add_unit(
                P1,
                UnitKind::Infantry,
                v(17, 16) + Vec2::new(Fixed::ZERO, Fixed::from_ratio(1, 2)),
            );
            s.entities[b.0 as usize].ammunition = 0;
            s.step(&[Command::Move {
                owner: P0,
                unit: a,
                target: v(30, 20),
            }]);
            let mut path = Vec::new();
            let mut closest = Fixed::from_int(100);
            for _ in 0..900 {
                s.step(&[]);
                let p = s.position(a).unwrap();
                closest = closest.min((p - s.position(b).unwrap()).length());
                path.push(p);
            }
            (path, closest, s)
        };
        let (classic, _, _) = trace(false);
        let (path, closest, s) = trace(true);
        let r = UnitKind::Infantry.stats().attack.range;
        assert!(
            closest > r && closest <= r + ACQUIRE_BONUS,
            "the route must pass through the ring only: {closest:?}"
        );
        assert_eq!(path, classic, "depth changed a player-ordered route");
        let p = *path.last().unwrap();
        assert!(
            (p - v(30, 20)).length_squared() < Fixed::ONE,
            "ended at {p:?}"
        );
        // Arrived and idle: the destination is the new anchor.
        assert_eq!(s.entities[0].dp.anchor, Some(p));
    }

    /// An engaged unit given an attack-move follows the attack-move: the
    /// engagement and the old anchor are dropped, it fights on the way, and it
    /// settles at the attack-move destination instead of snapping home.
    #[test]
    fn attack_move_wins_over_an_engagement() {
        let mut s = depth_arena();
        let range = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Infantry,
            v(10, 20) + Vec2::new(range + Fixed::from_int(2), Fixed::ZERO),
        );
        s.entities[b.0 as usize].ammunition = 0;
        for _ in 0..5 {
            s.step(&[]);
        }
        assert_eq!(s.entities[a.0 as usize].dp.engaged, Some(b), "precondition");
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: a,
            target: v(10, 34),
        }]);
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
        assert!(s.entities[a.0 as usize].dp.anchor.is_none());
        for _ in 0..900 {
            s.step(&[]);
        }
        let end = s.position(a).unwrap();
        assert!(
            (end - v(10, 34)).length_squared() < Fixed::ONE,
            "ended at {end:?}"
        );
        assert_eq!(s.entities[a.0 as usize].dp.anchor, Some(end));
    }

    /// An attack-mover that sees an enemy inside its acquisition ring but out of
    /// weapon range steps straight at it instead of marching past.
    #[test]
    fn attack_move_steps_toward_an_enemy_in_its_ring() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(4, 20));
        // Dry, so it never fires back or moves itself.
        let b = s.add_unit(P1, UnitKind::Infantry, v(16, 15));
        s.entities[b.0 as usize].ammunition = 0;
        let hp0 = s.views().iter().find(|x| x.id == b).unwrap().hp;
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: a,
            target: v(30, 20),
        }]);
        for _ in 0..900 {
            s.step(&[]);
        }
        let hp1 = s
            .views()
            .iter()
            .find(|x| x.id == b)
            .map_or(Fixed::ZERO, |x| x.hp);
        assert!(hp1 < hp0, "marched past the enemy");
        let p = s.position(a).unwrap();
        assert!(
            (p - v(30, 20)).length_squared() < Fixed::ONE,
            "never finished the attack-move: {p:?}"
        );
    }

    /// A dead engagement whose entity slot is freed (and reused by a fresh unit)
    /// is never chased: `clear_dead` drops the dangling id at once.
    #[test]
    fn a_dead_engagement_is_dropped_before_its_slot_is_reused() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(P1, UnitKind::Infantry, v(14, 20));
        for _ in 0..3 {
            s.step(&[]);
        }
        assert_eq!(s.entities[a.0 as usize].dp.engaged, Some(b), "precondition");
        s.entities[b.0 as usize].hp = Fixed::ZERO;
        s.step(&[]);
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
        // The slot comes back as an ally far away: nothing chases it.
        let c = s.add_unit(P0, UnitKind::Infantry, v(30, 30));
        assert_eq!(c, b, "slot reused");
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!((s.position(a).unwrap() - v(10, 20)).length_squared() < Fixed::ONE);
        assert_eq!(s.position(c), Some(v(30, 30)));
    }

    /// One audit scenario, in a fresh arena: a human Barracks with 4 idle rifles
    /// parked 4 west of it, and 4 alien rifles attack-moving onto it from the
    /// east. Returns (barracks alive, human rifles left, alien rifles left).
    fn barracks_raid(depth: bool) -> (bool, usize, usize) {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        let barracks = s.add_building(P0, BuildingKind::Barracks, 20, 20);
        let bpos = s.position(barracks).unwrap();
        for i in 0..4 {
            s.add_unit(
                P0,
                UnitKind::Infantry,
                bpos + Vec2::new(Fixed::from_int(-4), Fixed::from_ratio(i64::from(i) - 1, 2)),
            );
        }
        let raiders: Vec<_> = (0..4)
            .map(|i| {
                s.add_unit(
                    P1,
                    UnitKind::Infantry,
                    bpos + Vec2::new(Fixed::from_int(12), Fixed::from_ratio(i64::from(i) - 1, 2)),
                )
            })
            .collect();
        let orders: Vec<_> = raiders
            .iter()
            .map(|&unit| Command::AttackMove {
                owner: P1,
                unit,
                target: bpos,
            })
            .collect();
        s.step(&orders);
        for _ in 0..1200 {
            s.step(&[]);
        }
        (
            s.position(barracks).is_some(),
            s.unit_count(P0),
            s.unit_count(P1),
        )
    }

    /// The gameplay audit's measurement (4 rifles parked about 4 from a Barracks
    /// raided by 4 alien rifles: Barracks destroyed, all 4 aliens alive). With
    /// depth off that is still what happens; with depth on the parked rifles
    /// answer the first hit and the Barracks stands.
    #[test]
    fn parked_rifles_now_defend_their_barracks() {
        let before = barracks_raid(false);
        let after = barracks_raid(true);
        std::eprintln!(
            "barracks raid (barracks alive, human rifles, alien rifles): depth off {before:?}, depth on {after:?}"
        );
        assert!(
            !before.0,
            "depth off: the barracks should fall as the audit measured"
        );
        assert_eq!(before.2, 4, "depth off: every raider survives");
        assert!(after.0, "depth on: the barracks fell");
        assert_eq!(after.2, 0, "depth on: raiders left alive");
    }

    /// A busy depth skirmish (two rifle lines, a tank pair, a barracks) run twice
    /// gives the same hash, and replaying the recorded orders reproduces it.
    #[test]
    fn acquisition_and_response_are_deterministic_and_replay() {
        let run = || {
            let mut s = depth_arena();
            s.add_building(P0, BuildingKind::Barracks, 12, 20);
            for i in 0..8 {
                s.add_unit(P0, UnitKind::Infantry, v(8, 14 + i));
                s.add_unit(P1, UnitKind::Infantry, v(26, 14 + i));
            }
            let tanks = [
                s.add_unit(P1, UnitKind::Tank, v(30, 18)),
                s.add_unit(P1, UnitKind::Tank, v(30, 22)),
            ];
            let mut log = Vec::new();
            for t in 0..1500u32 {
                let mut c = Vec::new();
                if t == 100 {
                    for &unit in &tanks {
                        c.push(Command::AttackMove {
                            owner: P1,
                            unit,
                            target: v(10, 20),
                        });
                    }
                }
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = depth_arena();
        r.add_building(P0, BuildingKind::Barracks, 12, 20);
        for i in 0..8 {
            r.add_unit(P0, UnitKind::Infantry, v(8, 14 + i));
            r.add_unit(P1, UnitKind::Infantry, v(26, 14 + i));
        }
        r.add_unit(P1, UnitKind::Tank, v(30, 18));
        r.add_unit(P1, UnitKind::Tank, v(30, 22));
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// Ten rifles dropped on one exact point spread out to at least 0.40 apart.
    #[test]
    fn ten_riflemen_on_one_point_spread_out() {
        let mut s = depth_arena();
        for _ in 0..10 {
            s.add_unit(P0, UnitKind::Infantry, v(20, 20));
        }
        for _ in 0..90 {
            s.step(&[]);
        }
        let pos: Vec<Vec2> = s.views().iter().map(|x| x.pos).collect();
        let min_sq = Fixed::from_ratio(40, 100) * Fixed::from_ratio(40, 100);
        let mut closest = Fixed::from_int(100);
        for i in 0..pos.len() {
            for j in i + 1..pos.len() {
                closest = closest.min((pos[i] - pos[j]).length());
                assert!(
                    (pos[i] - pos[j]).length_squared() >= min_sq,
                    "{i} {j} still stacked"
                );
            }
        }
        let spread = pos
            .iter()
            .map(|&p| (p - v(20, 20)).length())
            .max()
            .unwrap_or(Fixed::ZERO);
        let milli = |f: Fixed| f.to_bits() * 1000 / Fixed::ONE.to_bits();
        std::eprintln!(
            "ten rifles after 90 ticks: closest pair {} milli-tiles, furthest from the drop point {}",
            milli(closest),
            milli(spread)
        );
    }

    /// The spread crowd settles: after the spread every rifle is idle (no walk
    /// home fighting the push), unengaged, within its anchor's home slack, and
    /// the crowd stays put from then on.
    #[test]
    fn a_spread_crowd_settles_at_home_and_stays_put() {
        let mut s = depth_arena();
        let ids: Vec<_> = (0..10)
            .map(|_| s.add_unit(P0, UnitKind::Infantry, v(20, 20)))
            .collect();
        for _ in 0..90 {
            s.step(&[]);
        }
        let settled: Vec<Vec2> = ids.iter().map(|&id| s.position(id).unwrap()).collect();
        let mut orders = 0u32;
        for _ in 0..600 {
            s.step(&[]);
            orders += u32::try_from(
                ids.iter()
                    .filter(|&&id| s.entities[id.0 as usize].move_target.is_some())
                    .count(),
            )
            .unwrap();
        }
        assert_eq!(orders, 0, "a spread unit walked home into the crowd");
        for (k, &id) in ids.iter().enumerate() {
            let e = &s.entities[id.0 as usize];
            assert_eq!(s.position(id), Some(settled[k]), "unit {k} kept drifting");
            let a = e.dp.anchor.expect("anchored");
            assert!(
                (e.pos - a).length_squared() <= Fixed::ONE,
                "unit {k} off its anchor"
            );
            assert!(
                (e.pos - v(20, 20)).length() < Fixed::from_ratio(3, 2),
                "unit {k} wandered off"
            );
        }
    }

    /// Separation is per owner and per layer: an enemy rifle or a friendly
    /// helicopter on the same point is never pushed.
    #[test]
    fn separation_ignores_enemies_and_the_other_layer() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(20, 20));
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(20, 20));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(20, 20));
        for id in [a, heli, foe] {
            s.entities[id.0 as usize].ammunition = 0;
        }
        for _ in 0..30 {
            s.step(&[]);
        }
        for id in [a, heli, foe] {
            assert_eq!(s.position(id), Some(v(20, 20)));
        }
        // Two friendly helicopters do separate among themselves.
        let h2 = s.add_unit(P0, UnitKind::Helicopter, v(20, 20));
        s.entities[h2.0 as usize].ammunition = 0;
        for _ in 0..30 {
            s.step(&[]);
        }
        let d = (s.position(h2).unwrap() - s.position(heli).unwrap()).length();
        assert!(
            d >= Fixed::from_ratio(40, 100),
            "helicopters still stacked: {d:?}"
        );
        assert_eq!(s.position(a), Some(v(20, 20)));
    }

    /// Eight rifles on one ford hex: the push never puts one in the river.
    #[test]
    fn separation_never_pushes_onto_water() {
        let mut s = kestrel_reach(3);
        let ford = hex::center(22, 10);
        for _ in 0..8 {
            s.add_unit(PlayerId(0), UnitKind::Infantry, ford);
        }
        for _ in 0..90 {
            s.step(&[]);
        }
        for v in s.views() {
            if matches!(v.kind, EntityKindView::Unit(_)) {
                let (x, y) = hex::from_world(v.pos, 44, 26);
                assert!(
                    s.map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable),
                    "unit on impassable tile at {x},{y}"
                );
            }
        }
    }

    /// A crowd dropped between three buildings is never pushed onto a footprint.
    #[test]
    fn separation_never_pushes_onto_a_building() {
        let mut s = depth_arena();
        s.add_building(P0, BuildingKind::Barracks, 20, 19);
        s.add_building(P0, BuildingKind::PowerPlant, 19, 20);
        s.add_building(P0, BuildingKind::Refinery, 21, 20);
        let spot = hex::center(20, 20);
        let ids: Vec<_> = (0..8)
            .map(|_| s.add_unit(P0, UnitKind::Infantry, spot))
            .collect();
        for _ in 0..120 {
            s.step(&[]);
            for &id in &ids {
                let (x, y) = hex::from_world(s.position(id).unwrap(), 40, 40);
                assert!(
                    s.map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable),
                    "unit on a footprint at {x},{y}"
                );
            }
        }
    }

    /// Infantry attack-moving past an enemy helicopter it cannot shoot keeps
    /// going (the halt scan used to stop it under the gunship for good). The
    /// gunship is dry so the measurement is the movement alone.
    #[test]
    fn attack_move_does_not_halt_under_an_untargetable_helicopter() {
        let mut s = depth_arena();
        let inf = s.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let heli = s.add_unit(P1, UnitKind::Helicopter, v(8, 20));
        s.entities[heli.0 as usize].ammunition = 0;
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..600 {
            s.step(&[]);
        }
        let p = s.position(inf).expect("the rifle survives a dry gunship");
        assert!(
            p.x > Fixed::from_int(20),
            "halted under the gunship at {p:?}"
        );
    }

    /// The same march with a ground enemy it can shoot still halts there (the
    /// fix only skips enemies the weapon cannot reach). Depth off, the rifle
    /// halts under the gunship exactly as before.
    #[test]
    fn attack_move_still_halts_for_a_shootable_enemy_and_classic_is_unchanged() {
        let mut s = depth_arena();
        let inf = s.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let foe = s.add_unit(P1, UnitKind::Tank, v(8, 20));
        s.entities[foe.0 as usize].ammunition = 0;
        s.debug_set_hp(foe, Fixed::from_int(1_000_000));
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..300 {
            s.step(&[]);
        }
        assert!(
            s.position(inf).unwrap().x < Fixed::from_int(9),
            "marched past a target"
        );

        let mut c = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        c.enable_earthfront();
        let inf = c.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let heli = c.add_unit(P1, UnitKind::Helicopter, v(8, 20));
        c.entities[heli.0 as usize].ammunition = 0;
        c.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..600 {
            c.step(&[]);
        }
        let p = c.position(inf).unwrap();
        assert!(
            p.x < Fixed::from_int(12),
            "classic no longer halts under the gunship: {p:?}"
        );
    }

    /// One column of a ford test: (start tile, destination tile).
    type ColumnLeg = ((u16, u16), (u16, u16));

    /// Walks a column of `n` rifles from `from` to `to` on Kestrel (the river
    /// is crossable only at the two-hex Wyllow Ford, (22,10) and (23,10)), with
    /// every unit made unkillable so the measurement is movement only. Returns
    /// (tick the last one arrived, every unit stayed on passable ground every
    /// tick, every unit crossed the ford).
    fn ford_column(
        depth: bool,
        groups: &[ColumnLeg],
        per_column: u16,
        parked: bool,
    ) -> (Option<u32>, bool, bool) {
        let mut s = if depth {
            kestrel_reach(3)
        } else {
            kestrel_reach_classic(3)
        };
        // Optionally three idle rifles parked on each ford hex, in the way.
        let mut idle = Vec::new();
        for tile in [(22, 10), (23, 10)].into_iter().filter(|_| parked) {
            for _ in 0..3 {
                let id = s.add_unit(P0, UnitKind::Infantry, hex::center(tile.0, tile.1));
                s.debug_set_hp(id, Fixed::from_int(1_000_000));
                idle.push(id);
            }
        }
        let mut units = Vec::new();
        let mut orders = Vec::new();
        for &(from, to) in groups {
            for i in 0..per_column {
                let id = s.add_unit(P0, UnitKind::Infantry, hex::center(from.0, from.1));
                s.debug_set_hp(id, Fixed::from_int(1_000_000));
                // A column: each rifle leaves a little after the one before.
                orders.push((u32::from(i) * 6, id, hex::center(to.0, to.1)));
                units.push((id, from.0 < 22));
            }
        }
        let (width, height) = (s.map().width(), s.map().height());
        let mut dry = true;
        let mut crossed = alloc::vec![false; units.len()];
        // First tick each rifle is within 1.5 of its destination (a spread crowd
        // fits; after that the depth rules may send it after an enemy).
        let mut arrived: Vec<Option<u32>> = alloc::vec![None; units.len()];
        for t in 0..1500u32 {
            let cmds: Vec<_> = orders
                .iter()
                .filter(|o| o.0 == t)
                .map(|&(_, unit, target)| Command::Move {
                    owner: P0,
                    unit,
                    target,
                })
                .collect();
            s.step(&cmds);
            for &id in &idle {
                let (x, y) = hex::from_world(s.position(id).expect("unkillable"), width, height);
                let ok = s
                    .map()
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.passable);
                dry &= ok;
            }
            for (k, &(id, west)) in units.iter().enumerate() {
                let p = s.position(id).expect("unkillable");
                let (x, y) = hex::from_world(p, width, height);
                dry &= s
                    .map()
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.passable);
                crossed[k] |= if west { x >= 24 } else { x <= 21 };
                let near = (p - orders[k].2).length_squared() <= Fixed::from_ratio(9, 4);
                if arrived[k].is_none() && t > orders[k].0 && near {
                    arrived[k] = Some(t);
                }
            }
        }
        let done = arrived.iter().try_fold(0, |m, a| a.map(|a| m.max(a)));
        (done, dry, crossed.iter().all(|&ok| ok))
    }

    /// A ten-rifle column through the two-hex ford, two columns crossing it in
    /// opposite directions at once, and a column through six rifles parked on
    /// the ford: with separation every rifle still crosses, nobody (parked or
    /// marching) ever stands in the river, and the last one arrives within 10
    /// percent of the classic (no separation) time. No corridor deadlock.
    #[test]
    fn columns_cross_the_two_hex_ford_without_wading_or_deadlock() {
        let one = [((17, 10), (28, 10))];
        let two = [((17, 10), (28, 10)), ((28, 11), (17, 11))];
        for (label, groups, parked) in [
            ("one column", &one[..], false),
            ("two columns", &two[..], false),
            ("one column past 6 parked rifles", &one[..], true),
        ] {
            let classic = ford_column(false, groups, 10, parked);
            let depth = ford_column(true, groups, 10, parked);
            std::eprintln!("ford {label}: classic {classic:?}, depth {depth:?} (last arrival tick, dry, all crossed)");
            assert!(depth.1, "{label}: a rifle waded into the river");
            assert!(depth.2, "{label}: a rifle never crossed");
            let (c, d) = (
                classic.0.expect("classic arrives"),
                depth.0.expect("depth deadlocked"),
            );
            assert!(d * 10 <= c * 11, "{label}: depth {d} vs classic {c}");
        }
    }

    /// Unit-ticks a ground unit spends on an impassable tile (river, sea, a
    /// structure) over `steps` ticks of the AI-defended Kestrel match.
    fn wading_unit_ticks(mut s: Sim, steps: u32) -> u32 {
        let (width, height) = (s.map().width(), s.map().height());
        let mut wading = 0;
        for _ in 0..steps {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(Scenario::KestrelReach.host_commands(&s));
            s.step(&cmds);
            for e in s.entities.iter().filter(|e| e.alive) {
                if matches!(e.kind, Kind::Unit(_)) && !is_air_of(&s.balance, e.kind) {
                    let (x, y) = hex::from_world(e.pos, width, height);
                    if !s
                        .map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable)
                    {
                        wading += 1;
                    }
                }
            }
        }
        wading
    }

    /// Over a whole defended match (both AIs crowding fords, bases and
    /// rally points), separation and the corner guard never leave a ground
    /// unit on an impassable tile more often than the classic rules do (the
    /// classic count is units walking off the producer that spawned them).
    #[test]
    fn a_defended_match_wades_no_more_than_classic() {
        let classic = wading_unit_ticks(kestrel_reach_classic(3), 13_000);
        let depth = wading_unit_ticks(kestrel_reach(3), 13_000);
        std::eprintln!("ground unit-ticks on impassable tiles in 13000 defended ticks: classic {classic}, depth {depth}");
        assert!(depth <= classic, "depth {depth} vs classic {classic}");
    }

    /// Mines one ore hex with four harvesters feeding one refinery for 3000
    /// ticks and returns the ore taken out of the ground.
    fn harvest_run(depth: bool) -> u32 {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        s.add_building(P0, BuildingKind::PowerPlant, 16, 16);
        s.add_building(P0, BuildingKind::Refinery, 20, 20);
        s.map.set_deposit(
            25,
            20,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 30_000,
            },
        );
        for _ in 0..4 {
            s.add_unit(P0, UnitKind::Harvester, hex::center(21, 21));
        }
        for _ in 0..3000 {
            s.step(&[]);
        }
        30_000 - s.map.deposit(25, 20).map_or(0, |d| d.remaining)
    }

    /// Harvesters crowding one refinery and one ore hex still dock and mine:
    /// with separation the four trucks take at least 95 percent of the ore
    /// they take without it.
    #[test]
    fn harvesters_still_dock_and_mine_with_separation() {
        let classic = harvest_run(false);
        let depth = harvest_run(true);
        std::eprintln!("ore mined in 3000 ticks by 4 harvesters: classic {classic}, depth {depth}");
        assert!(classic > 0);
        assert!(
            depth * 100 >= classic * 95,
            "depth {depth} vs classic {classic}"
        );
    }

    /// A crowd that separates every tick is still deterministic: two runs give
    /// the same hash and replaying the recorded orders reproduces it.
    #[test]
    fn separation_is_deterministic_and_replays() {
        let setup = || {
            let mut s = depth_arena();
            let mut ids = Vec::new();
            for i in 0..12 {
                ids.push(s.add_unit(P0, UnitKind::Infantry, v(10, 20)));
                ids.push(s.add_unit(P1, UnitKind::Infantry, v(30, 18 + i % 4)));
            }
            (s, ids)
        };
        let run = || {
            let (mut s, ids) = setup();
            let mut log = Vec::new();
            for t in 0..900u32 {
                let mut c = Vec::new();
                if t == 60 {
                    for &unit in ids.iter().step_by(2) {
                        c.push(Command::AttackMove {
                            owner: P0,
                            unit,
                            target: v(30, 20),
                        });
                    }
                }
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let (mut r, _) = setup();
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    // ---- Task 13: Stop, HoldPosition, SetStance, AttackTarget ----

    /// Hit points of a living entity (zero once it is gone).
    fn hp_of(s: &Sim, id: EntityId) -> Fixed {
        s.views()
            .iter()
            .find(|x| x.id == id)
            .map_or(Fixed::ZERO, |x| x.hp)
    }

    #[test]
    fn stop_clears_orders_and_hold_never_moves() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(30, 20),
        }]);
        for _ in 0..20 {
            s.step(&[]);
        }
        s.step(&[Command::Stop { owner: P0, unit: a }]);
        let here = s.position(a).unwrap();
        assert!(here.x > Fixed::from_int(10), "never marched");
        for _ in 0..60 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(here));
        s.step(&[Command::HoldPosition { owner: P0, unit: a }]);
        let r = UnitKind::Infantry.stats().attack.range;
        // Inside the acquisition ring, outside weapon range. Dry, so the duel
        // cannot kill the holder (which would also read as "moved").
        let passer = s.add_unit(
            P1,
            UnitKind::Infantry,
            here + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
        );
        s.entities[passer.0 as usize].ammunition = 0;
        for _ in 0..200 {
            s.step(&[]);
            assert_eq!(s.position(a), Some(here), "hold moved");
        }
        assert_eq!(s.stance_of(a), Some(Stance::Hold));
        // Hold still fires at an enemy that stands inside weapon range.
        let inside = s.add_unit(
            P1,
            UnitKind::Infantry,
            here + Vec2::new(r - Fixed::ONE, Fixed::ZERO),
        );
        s.entities[inside.0 as usize].ammunition = 0;
        for _ in 0..60 {
            s.step(&[]);
        }
        assert!(
            hp_of(&s, inside) < UnitKind::Infantry.stats().max_hp,
            "hold never fired"
        );
        assert_eq!(s.position(a), Some(here), "hold moved");
    }

    /// Hold never moves on its own: not for an enemy hitting it from outside its
    /// weapon range, not for a hit on an ally beside it, not for a same-owner
    /// crowd pressing on it; a player Move still moves it, and it holds where
    /// the order ends.
    #[test]
    fn hold_never_moves() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let ally = s.add_unit(P0, UnitKind::Infantry, v(10, 21));
        // Two more rifles dropped right on top of the holder.
        let crowd = [
            s.add_unit(P0, UnitKind::Infantry, v(10, 20)),
            s.add_unit(P0, UnitKind::Infantry, v(10, 20)),
        ];
        s.step(&[Command::HoldPosition { owner: P0, unit: a }]);
        let home = s.position(a).unwrap();
        // A tank shoots from range 4, beyond the rifle's 3.
        let tank = s.add_unit(
            P1,
            UnitKind::Tank,
            home + Vec2::new(Fixed::from_int(4), Fixed::ZERO),
        );
        s.entities[tank.0 as usize].ammunition = 1;
        for _ in 0..300 {
            s.step(&[]);
            assert_eq!(s.position(a), Some(home), "hold moved");
        }
        // The others (not holding) answered the shell and spread out.
        assert!(
            [ally, crowd[0], crowd[1]]
                .iter()
                .any(|&u| s.position(u) != Some(v(10, 20)) && s.position(u) != Some(v(10, 21))),
            "control: the aggressive rifles never moved"
        );
        // A player Move is obeyed; the unit then holds where it arrives.
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(10, 30),
        }]);
        for _ in 0..400 {
            s.step(&[]);
        }
        let there = s.position(a).unwrap();
        assert!(
            (there - v(10, 30)).length_squared() < Fixed::ONE,
            "ended at {there:?}"
        );
        assert_eq!(s.stance_of(a), Some(Stance::Hold));
        let p1 = s.add_unit(
            P1,
            UnitKind::Infantry,
            there + Vec2::new(Fixed::from_int(5), Fixed::ZERO),
        );
        s.entities[p1.0 as usize].ammunition = 0;
        s.step(&[Command::Move {
            owner: P1,
            unit: p1,
            target: there + Vec2::new(Fixed::from_int(5), Fixed::from_int(6)),
        }]);
        for _ in 0..200 {
            s.step(&[]);
            assert_eq!(s.position(a), Some(there), "hold chased a passer-by");
        }
    }

    #[test]
    fn attack_target_focuses_the_chosen_enemy() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let near = s.add_unit(P1, UnitKind::Infantry, v(12, 20));
        let far = s.add_unit(P1, UnitKind::Infantry, v(13, 21));
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: far,
        }]);
        for _ in 0..300 {
            if s.position(far).is_none() {
                break;
            }
            s.step(&[]);
        }
        assert!(s.position(far).is_none(), "forced target survived");
        assert!(
            s.position(near).is_some(),
            "fired at the nearer enemy first"
        );
        assert_eq!(
            hp_of(&s, near),
            UnitKind::Infantry.stats().max_hp,
            "a shot went to the nearer enemy"
        );
    }

    /// A forced target out of weapon range is walked to (not just waited for),
    /// past a nearer enemy that does not halt the walk, and the order ends
    /// (no chase, no forced id) once it dies.
    #[test]
    fn attack_target_walks_into_range_and_ends_when_the_target_dies() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let far = s.add_unit(P1, UnitKind::Infantry, v(20, 20));
        s.entities[far.0 as usize].ammunition = 0;
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: far,
        }]);
        for _ in 0..600 {
            if s.position(far).is_none() {
                break;
            }
            s.step(&[]);
        }
        assert!(s.position(far).is_none(), "never reached its target");
        let stood = s.position(a).unwrap();
        assert!(stood.x > Fixed::from_int(14), "fired from {stood:?}");
        assert!(s.entities[a.0 as usize].dp.forced.is_none());
        for _ in 0..120 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(stood), "kept walking after the kill");
    }

    /// A later `Move` or `AttackMove` replaces the forced target outright.
    #[test]
    fn a_move_order_replaces_a_forced_target() {
        for attack in [false, true] {
            let mut s = depth_arena();
            let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
            let t = s.add_unit(P1, UnitKind::Infantry, v(16, 20));
            s.entities[t.0 as usize].ammunition = 0;
            s.step(&[Command::AttackTarget {
                owner: P0,
                unit: a,
                target: t,
            }]);
            assert_eq!(s.entities[a.0 as usize].dp.forced, Some(t), "precondition");
            let order = if attack {
                Command::AttackMove {
                    owner: P0,
                    unit: a,
                    target: v(10, 34),
                }
            } else {
                Command::Move {
                    owner: P0,
                    unit: a,
                    target: v(10, 34),
                }
            };
            s.step(&[order]);
            assert!(s.entities[a.0 as usize].dp.forced.is_none());
            for _ in 0..600 {
                s.step(&[]);
            }
            let end = s.position(a).unwrap();
            assert!(
                (end - v(10, 34)).length_squared() < Fixed::ONE,
                "ended at {end:?}"
            );
        }
    }

    #[test]
    fn forced_target_is_dropped_when_its_slot_is_reused() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let t = s.add_unit(P1, UnitKind::Infantry, v(12, 20));
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: t,
        }]);
        // Fixed step count (never `while alive`): the kill takes a few shots.
        for _ in 0..300 {
            if s.position(t).is_none() {
                break;
            }
            s.step(&[]);
        }
        assert!(s.position(t).is_none(), "precondition: the target died");
        let ally = s.add_unit(P0, UnitKind::Infantry, v(25, 25)); // reuses the freed slot
        assert_eq!(ally, t);
        let hp = hp_of(&s, ally);
        for _ in 0..200 {
            s.step(&[]);
        }
        assert_eq!(hp_of(&s, ally), hp);
        assert!(
            (s.position(a).unwrap() - v(25, 25)).length_squared() > Fixed::from_int(4),
            "chased the recycled slot"
        );
    }

    /// A target that outruns every unit of the chaser's side (no friendly
    /// entity within [`FORCED_TRACK`]) is lost: the order ends where the chaser
    /// stands instead of hunting it across the map.
    #[test]
    fn attack_target_ends_when_the_target_slips_out_of_track() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(5, 20));
        let runner = s.add_unit(P1, UnitKind::Infantry, v(10, 20));
        s.entities[runner.0 as usize].ammunition = 0;
        // Too tough to kill: it chases but never kills. (It used to be dry,
        // but since P2 review M2 a dry unit takes no forced target.)
        s.entities[runner.0 as usize].hp = Fixed::from_int(100_000);
        s.step(&[
            Command::AttackTarget {
                owner: P0,
                unit: a,
                target: runner,
            },
            Command::Move {
                owner: P1,
                unit: runner,
                target: v(38, 20),
            },
        ]);
        let mut lost_at = None;
        for t in 0..900 {
            s.step(&[]);
            if lost_at.is_none() && s.entities[a.0 as usize].dp.forced.is_none() {
                lost_at = Some((t, s.position(a).unwrap()));
            }
        }
        let (_, at) = lost_at.expect("the chase never ended");
        let gap = (s.position(runner).unwrap() - at).length();
        assert!(
            gap >= FORCED_TRACK - Fixed::ONE,
            "dropped too early: {gap:?}"
        );
        assert!(at.x > Fixed::from_int(6), "it never chased");
        assert_eq!(
            s.position(a),
            Some(at),
            "kept moving after losing the target"
        );
    }

    #[test]
    fn attack_target_rejects_friends_untargetable_layers_and_other_owners() {
        let setup = || {
            let mut s = depth_arena();
            let ids = [
                s.add_unit(P0, UnitKind::Infantry, v(10, 20)),
                s.add_unit(P0, UnitKind::Infantry, v(14, 20)),
                s.add_unit(P1, UnitKind::Helicopter, v(16, 20)),
                // Out of everyone's ring, but within track (7.2) of `friend`.
                s.add_unit(P1, UnitKind::Infantry, v(18, 26)),
            ];
            s.entities[ids[2].0 as usize].ammunition = 0;
            s.entities[ids[3].0 as usize].ammunition = 0;
            (s, ids)
        };
        let (mut t, [a, friend, heli, rifle]) = setup();
        let (mut twin, _) = setup();
        twin.step(&[]);
        t.step(&[
            // A friend, a helicopter a rifle cannot shoot, an order in another
            // player's name and unknown ids: all no-ops.
            Command::AttackTarget {
                owner: P0,
                unit: a,
                target: friend,
            },
            Command::AttackTarget {
                owner: P0,
                unit: a,
                target: heli,
            },
            Command::AttackTarget {
                owner: P1,
                unit: a,
                target: rifle,
            },
            Command::AttackTarget {
                owner: P0,
                unit: a,
                target: EntityId(99),
            },
            Command::Stop { owner: P1, unit: a },
            Command::HoldPosition { owner: P1, unit: a },
            Command::SetStance {
                owner: P1,
                unit: a,
                stance: Stance::Hold,
            },
            Command::Stop {
                owner: P0,
                unit: EntityId(99),
            },
        ]);
        assert_eq!(
            t.state_hash(),
            twin.state_hash(),
            "an invalid order changed the world"
        );
        assert_eq!(t.stance_of(a), Some(Stance::Aggressive));
        // A valid one does.
        t.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: rifle,
        }]);
        assert_eq!(t.entities[a.0 as usize].dp.forced, Some(rifle));
    }

    #[test]
    fn stances_cycle_by_name_and_stop_keeps_the_stance() {
        assert_eq!(Stance::default(), Stance::Aggressive);
        for st in [Stance::Aggressive, Stance::Defensive, Stance::Hold] {
            assert_eq!(Stance::from_name(st.name()), Some(st));
        }
        assert_eq!(Stance::from_name("Hold"), None, "names are lower case");
        assert_eq!(Stance::from_name("charge"), None);
        assert_ne!(Stance::Aggressive.tag(), Stance::Defensive.tag());
        assert_ne!(Stance::Defensive.tag(), Stance::Hold.tag());
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_building(P0, BuildingKind::Barracks, 20, 20);
        assert_eq!(s.stance_of(a), Some(Stance::Aggressive));
        assert_eq!(s.stance_of(b), None, "buildings have no stance");
        s.step(&[Command::SetStance {
            owner: P0,
            unit: a,
            stance: Stance::Defensive,
        }]);
        s.step(&[Command::Stop { owner: P0, unit: a }]);
        assert_eq!(s.stance_of(a), Some(Stance::Defensive));
        s.step(&[Command::SetStance {
            owner: P0,
            unit: b,
            stance: Stance::Hold,
        }]);
        assert_eq!(s.stance_of(b), None);
    }

    /// One Defensive-stance run: a dry P1 rifle marches past at weapon range + 2
    /// with a Move order (inside the acquisition ring). Returns whether the P0
    /// rifle left its spot.
    fn passer_by(stance: Stance) -> bool {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[Command::SetStance {
            owner: P0,
            unit: a,
            stance,
        }]);
        let home = s.position(a).unwrap();
        let lane = home.x + r + Fixed::from_int(2);
        let p = s.add_unit(P1, UnitKind::Infantry, Vec2::new(lane, Fixed::from_int(8)));
        s.entities[p.0 as usize].ammunition = 0;
        s.step(&[Command::Move {
            owner: P1,
            unit: p,
            target: Vec2::new(lane, Fixed::from_int(36)),
        }]);
        let mut moved = false;
        for _ in 0..500 {
            s.step(&[]);
            moved |= s.position(a) != Some(home);
        }
        moved
    }

    #[test]
    fn defensive_ignores_a_passer_by_but_answers_a_hit() {
        assert!(
            passer_by(Stance::Aggressive),
            "control: aggressive gives chase"
        );
        assert!(!passer_by(Stance::Defensive), "defensive left its spot");
        // Now an enemy tank shoots it from range 4 (beyond the rifle's 3): the
        // defensive rifle answers, closes in, damages it, and never strays more
        // than 3 from its anchor.
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[Command::SetStance {
            owner: P0,
            unit: a,
            stance: Stance::Defensive,
        }]);
        let anchor = s.position(a).unwrap();
        let tank = s.add_unit(
            P1,
            UnitKind::Tank,
            anchor + Vec2::new(Fixed::from_int(4), Fixed::ZERO),
        );
        // One round: a single 30-damage shell leaves the 50 hp rifle standing.
        s.entities[tank.0 as usize].ammunition = 1;
        let tank_hp = hp_of(&s, tank);
        let mut furthest = Fixed::ZERO;
        for _ in 0..600 {
            s.step(&[]);
            let p = s.position(a).expect("the rifle died");
            furthest = furthest.max((p - anchor).length());
        }
        assert!(hp_of(&s, tank) < tank_hp, "never answered the hit");
        assert!(furthest > Fixed::ZERO, "never closed in");
        assert!(
            furthest <= DEFENSIVE_LEASH,
            "strayed {furthest:?} from its anchor"
        );
        let end = s.position(a).unwrap();
        assert!(
            (end - anchor).length() <= DEFENSIVE_LEASH,
            "ended at {end:?}"
        );
    }

    #[test]
    fn depth_commands_are_ignored_without_depth() {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let e = s.add_unit(P1, UnitKind::Infantry, v(38, 38));
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(30, 20),
        }]);
        let mut twin = s.clone();
        s.step(&[
            Command::Stop { owner: P0, unit: a },
            Command::HoldPosition { owner: P0, unit: a },
            Command::SetStance {
                owner: P0,
                unit: a,
                stance: Stance::Hold,
            },
            Command::AttackTarget {
                owner: P0,
                unit: a,
                target: e,
            },
        ]);
        twin.step(&[]);
        assert_eq!(
            s.state_hash(),
            twin.state_hash(),
            "a depth order acted without depth"
        );
        for _ in 0..60 {
            s.step(&[]);
        }
        assert!(s.position(a).unwrap().x > Fixed::from_int(11));
        assert_eq!(s.stance_of(a), None);
    }

    /// The four orders replay: a busy skirmish with every order (and the
    /// stances in play) run twice gives one hash, and the recorded log
    /// reproduces it.
    #[test]
    fn depth_orders_are_deterministic_and_replay() {
        let setup = || {
            let mut s = depth_arena();
            let mut mine = Vec::new();
            let mut theirs = Vec::new();
            for i in 0..8 {
                mine.push(s.add_unit(P0, UnitKind::Infantry, v(8, 14 + i)));
                theirs.push(s.add_unit(P1, UnitKind::Infantry, v(24, 14 + i)));
            }
            mine.push(s.add_unit(P0, UnitKind::Tank, v(6, 18)));
            (s, mine, theirs)
        };
        let orders = |t: u32, mine: &[EntityId], theirs: &[EntityId]| -> Vec<Command> {
            let mut c = Vec::new();
            match t {
                10 => {
                    for (k, &unit) in mine.iter().enumerate() {
                        let stance = [Stance::Aggressive, Stance::Defensive, Stance::Hold][k % 3];
                        c.push(Command::SetStance {
                            owner: P0,
                            unit,
                            stance,
                        });
                    }
                }
                40 => {
                    for &unit in mine {
                        c.push(Command::AttackMove {
                            owner: P0,
                            unit,
                            target: v(26, 18),
                        });
                    }
                }
                120 => c.push(Command::Stop {
                    owner: P0,
                    unit: mine[0],
                }),
                130 => c.push(Command::HoldPosition {
                    owner: P0,
                    unit: mine[1],
                }),
                140 => c.push(Command::AttackTarget {
                    owner: P0,
                    unit: mine[8],
                    target: theirs[7],
                }),
                _ => {}
            }
            c
        };
        let run = || {
            let (mut s, mine, theirs) = setup();
            let mut log = Vec::new();
            for t in 0..1200u32 {
                let c = orders(t, &mine, &theirs);
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let (mut r, _, _) = setup();
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// The bridge budget at 80 units on Kestrel: a 30 Hz tick must stay far
    /// under its 33 ms, with separation and acquisition both running.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_tick_budget -- --ignored --nocapture"]
    fn depth_tick_budget() {
        let mut s = kestrel_reach(3);
        for i in 0..40u16 {
            s.add_unit(
                PlayerId(0),
                UnitKind::Infantry,
                hex::center(10, 5 + (i % 15)),
            );
        }
        for i in 0..40u16 {
            s.add_unit(
                PlayerId(1),
                UnitKind::Infantry,
                hex::center(30, 5 + (i % 15)),
            );
        }
        let t = std::time::Instant::now();
        let mut worst = std::time::Duration::ZERO;
        for _ in 0..900 {
            let c = Scenario::KestrelReach.host_commands(&s);
            let t0 = std::time::Instant::now();
            s.step(&c);
            worst = worst.max(t0.elapsed());
        }
        let mean = t.elapsed() / 900;
        std::eprintln!("depth tick mean {mean:?} worst {worst:?}");
        assert!(
            mean < std::time::Duration::from_millis(5)
                && worst < std::time::Duration::from_millis(15)
        );
    }

    /// Headless tick cost with 80+ units on Kestrel, depth vs classic, hosted
    /// as the bridge hosts them: two 40-rifle lines either 6 apart (inside each
    /// other's acquisition ring, so the depth run acquires, chases, answers
    /// hits and walks home) or 15 apart (idle scans only), plus the
    /// scenario's own units.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_acquire_tick_cost -- --ignored --nocapture"]
    fn depth_acquire_tick_cost() {
        let bench = |mut s: Sim, cols: (u16, u16)| {
            for i in 0..40u16 {
                s.add_unit(P0, UnitKind::Infantry, hex::center(cols.0, 5 + (i % 15)));
            }
            for i in 0..40u16 {
                s.add_unit(P1, UnitKind::Infantry, hex::center(cols.1, 5 + (i % 15)));
            }
            let units = s.unit_count(P0) + s.unit_count(P1);
            let t = std::time::Instant::now();
            let mut worst = std::time::Duration::ZERO;
            for _ in 0..900 {
                let c = Scenario::KestrelReach.host_commands(&s);
                let t0 = std::time::Instant::now();
                s.step(&c);
                worst = worst.max(t0.elapsed());
            }
            let left = s.unit_count(P0) + s.unit_count(P1);
            (units, left, t.elapsed() / 900, worst)
        };
        for (label, cols) in [("lines 6 apart", (12, 20)), ("lines 15 apart", (10, 30))] {
            let (n, left, mean, worst) = bench(kestrel_reach(3), cols);
            let (cn, cleft, cmean, cworst) = bench(kestrel_reach_classic(3), cols);
            std::eprintln!(
                "{label}: depth {n} units ({left} left) mean {mean:?} worst {worst:?}; classic {cn} units ({cleft} left) mean {cmean:?} worst {cworst:?}"
            );
            assert!(n >= 80);
            assert!(mean < std::time::Duration::from_millis(5));
            assert!(worst < std::time::Duration::from_millis(15));
        }
    }

    /// Task 13 tick cost: the same two 40-rifle lines 6 apart on Kestrel, the
    /// human line split into thirds (every rifle on a forced target, a third
    /// holding, a third defensive), against the plain Task 11/12 run.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_orders_tick_cost -- --ignored --nocapture"]
    fn depth_orders_tick_cost() {
        let bench = |orders: bool| {
            let mut s = kestrel_reach(3);
            let mine: Vec<_> = (0..40u16)
                .map(|i| s.add_unit(P0, UnitKind::Infantry, hex::center(12, 5 + (i % 15))))
                .collect();
            let theirs: Vec<_> = (0..40u16)
                .map(|i| s.add_unit(P1, UnitKind::Infantry, hex::center(20, 5 + (i % 15))))
                .collect();
            let mut first = Vec::new();
            if orders {
                for (k, (&unit, &target)) in mine.iter().zip(&theirs).enumerate() {
                    let stance = [Stance::Aggressive, Stance::Hold, Stance::Defensive][k % 3];
                    first.push(Command::SetStance {
                        owner: P0,
                        unit,
                        stance,
                    });
                    first.push(Command::AttackTarget {
                        owner: P0,
                        unit,
                        target,
                    });
                }
            }
            let t = std::time::Instant::now();
            let mut worst = std::time::Duration::ZERO;
            for step in 0..900 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                if step == 0 {
                    c.extend(first.iter().cloned());
                }
                let t0 = std::time::Instant::now();
                s.step(&c);
                worst = worst.max(t0.elapsed());
            }
            (t.elapsed() / 900, worst)
        };
        let (mean, worst) = bench(true);
        let (pmean, pworst) = bench(false);
        std::eprintln!(
            "orders: mean {mean:?} worst {worst:?}; plain: mean {pmean:?} worst {pworst:?}"
        );
        assert!(mean < std::time::Duration::from_millis(5));
        assert!(worst < std::time::Duration::from_millis(15));
    }

    // ---- Task 14: shift-queued waypoints ----

    fn qmove(unit: EntityId, target: Vec2) -> Command {
        Command::QueueMove {
            owner: P0,
            unit,
            target,
            attack_move: false,
        }
    }

    fn qattack(unit: EntityId, target: Vec2) -> Command {
        Command::QueueMove {
            owner: P0,
            unit,
            target,
            attack_move: true,
        }
    }

    /// Steps `s` up to `steps` times and returns, for each point of `legs`, the
    /// first tick the unit stood exactly on it (sampled after every step).
    fn visits(s: &mut Sim, unit: EntityId, legs: &[Vec2], steps: u32) -> Vec<Option<u64>> {
        let mut seen = alloc::vec![None; legs.len()];
        for _ in 0..steps {
            s.step(&[]);
            let p = s.position(unit);
            for (k, &leg) in legs.iter().enumerate() {
                if seen[k].is_none() && p == Some(leg) {
                    seen[k] = Some(s.tick());
                }
            }
        }
        seen
    }

    #[test]
    fn queued_legs_are_visited_in_order() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let legs = [v(16, 20), v(16, 27), v(9, 27)];
        // Three legs in one tick: the first starts at once, two wait.
        s.step(&legs.iter().map(|&p| qmove(a, p)).collect::<Vec<_>>());
        assert_eq!(s.queue_len(a), 2, "the first leg is under way");
        assert!(
            s.position(a).unwrap().x > Fixed::from_int(10),
            "idle unit started at once"
        );
        let mut arrivals = Vec::new();
        let mut last = s.queue_len(a);
        for _ in 0..900 {
            s.step(&[]);
            let now = s.queue_len(a);
            if now < last {
                // The next leg is popped the tick the previous one arrives.
                arrivals.push(s.position(a).unwrap());
                last = now;
            }
        }
        assert_eq!(arrivals, alloc::vec![legs[0], legs[1]], "arrival samples");
        assert_eq!(s.position(a), Some(legs[2]), "ends on the last leg");
        assert_eq!(s.queue_len(a), 0);
        // The order of first visits is the order of the legs.
        let mut t = depth_arena();
        let b = t.add_unit(P0, UnitKind::Infantry, v(10, 20));
        t.step(&legs.iter().map(|&p| qmove(b, p)).collect::<Vec<_>>());
        let seen = visits(&mut t, b, &legs, 900);
        assert!(seen.iter().all(Option::is_some), "{seen:?}");
        assert!(seen.windows(2).all(|w| w[0] < w[1]), "{seen:?}");
        // At rest on its last leg the unit is idle again and anchors there.
        assert_eq!(t.entities[b.0 as usize].dp.anchor, Some(legs[2]));
    }

    #[test]
    fn a_queue_appends_after_a_plain_move_and_the_ninth_leg_is_dropped() {
        let waiting = u32::try_from(QUEUE_CAP - 1).unwrap();
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(4, 4));
        let legs: Vec<Vec2> = (0..9).map(|k| v(6 + 3 * k, 4 + (k % 2) * 3)).collect();
        // A plain Move is the first leg; QueueMoves append behind it.
        let mut c = alloc::vec![Command::Move {
            owner: P0,
            unit: a,
            target: legs[0],
        }];
        c.extend(legs[1..].iter().map(|&p| qmove(a, p)));
        s.step(&c);
        assert_eq!(s.queue_len(a), waiting, "eight legs in all");
        s.step(&[qmove(a, v(30, 30))]);
        assert_eq!(s.queue_len(a), waiting, "a full queue drops more");
        let seen = visits(&mut s, a, &legs, 2400);
        assert!(seen[..8].iter().all(Option::is_some), "{seen:?}");
        assert!(seen[..8].windows(2).all(|w| w[0] < w[1]), "{seen:?}");
        assert_eq!(seen[8], None, "the ninth leg was dropped");
        assert_eq!(s.position(a), Some(legs[7]));
        // The same cap holds for an idle unit given nine QueueMoves at once.
        let mut idle = depth_arena();
        let fresh = idle.add_unit(P0, UnitKind::Infantry, v(4, 4));
        idle.step(&legs.iter().map(|&p| qmove(fresh, p)).collect::<Vec<_>>());
        assert_eq!(idle.queue_len(fresh), waiting);
        let seen = visits(&mut idle, fresh, &legs, 2400);
        assert_eq!(seen[8], None, "the ninth leg was dropped");
        assert_eq!(idle.position(fresh), Some(legs[7]));
    }

    #[test]
    fn move_stop_hold_and_attack_target_clear_the_queue() {
        let queued = || {
            let mut s = depth_arena();
            let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
            // Within FORCED_TRACK of the tank when the AttackTarget below is
            // given (P2 review M1 rejects an untracked target outright).
            let foe = s.add_unit(P1, UnitKind::Infantry, v(10, 28));
            s.entities[foe.0 as usize].ammunition = 0;
            s.step(&[
                qmove(a, v(20, 20)),
                qmove(a, v(20, 10)),
                qattack(a, v(30, 10)),
            ]);
            for _ in 0..10 {
                s.step(&[]);
            }
            assert_eq!(s.queue_len(a), 2);
            (s, a, foe)
        };
        // A plain Move replaces the whole queue.
        let (mut s, a, _) = queued();
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(10, 10),
        }]);
        assert_eq!(s.queue_len(a), 0);
        for _ in 0..600 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(v(10, 10)));
        // So does an AttackMove.
        let (mut s, a, _) = queued();
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: a,
            target: v(10, 10),
        }]);
        assert_eq!(s.queue_len(a), 0);
        // Stop clears it and the unit stays put.
        let (mut s, a, _) = queued();
        s.step(&[Command::Stop { owner: P0, unit: a }]);
        assert_eq!(s.queue_len(a), 0);
        let here = s.position(a);
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), here, "a stopped unit walked its old queue");
        // Hold too.
        let (mut s, a, _) = queued();
        s.step(&[Command::HoldPosition { owner: P0, unit: a }]);
        assert_eq!(s.queue_len(a), 0);
        // An AttackTarget forgets the queue as well.
        let (mut s, a, foe) = queued();
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: foe,
        }]);
        assert_eq!(s.queue_len(a), 0);
    }

    /// An attack-move leg halts for an enemy in weapon range, the unit fights,
    /// and once the area is clear it walks the rest of its queue. A plain move
    /// leg marches on.
    #[test]
    fn an_attack_move_leg_halts_for_an_enemy_and_resumes_the_queue() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(4, 20));
        // Dry, so the tank wins without a scratch and the test stays a fight.
        let foe = s.add_unit(P1, UnitKind::Infantry, v(14, 20));
        s.entities[foe.0 as usize].ammunition = 0;
        let legs = [v(22, 20), v(22, 28)];
        s.step(&[qattack(a, legs[0]), qmove(a, legs[1])]);
        let mut halted = 0;
        let mut prev = s.position(a);
        for _ in 0..900 {
            s.step(&[]);
            if s.position(foe).is_some() && s.position(a) == prev {
                halted += 1;
            }
            prev = s.position(a);
        }
        assert!(s.position(foe).is_none(), "the enemy survived");
        assert!(halted > 0, "the attack-move leg never halted");
        assert_eq!(s.position(a), Some(legs[1]), "never resumed the queue");
        assert_eq!(s.queue_len(a), 0);
    }

    /// A unit on a forced target queues legs behind it and walks them once the
    /// target dies; Hold set mid-queue keeps the player's legs going and the
    /// unit holds where the last one ends.
    #[test]
    fn a_forced_target_and_hold_keep_the_queue() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(16, 20));
        s.entities[foe.0 as usize].ammunition = 0;
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: foe,
        }]);
        let legs = [v(16, 28), v(24, 28)];
        s.step(&[qmove(a, legs[0]), qmove(a, legs[1])]);
        assert_eq!(s.queue_len(a), 2, "both legs wait behind the target");
        for _ in 0..40 {
            s.step(&[]);
        }
        s.step(&[Command::SetStance {
            owner: P0,
            unit: a,
            stance: Stance::Hold,
        }]);
        let seen = visits(&mut s, a, &legs, 900);
        assert!(s.position(foe).is_none(), "the target survived");
        assert!(seen.iter().all(Option::is_some), "{seen:?}");
        assert!(seen[0] < seen[1]);
        assert_eq!(s.position(a), Some(legs[1]));
        assert_eq!(s.stance_of(a), Some(Stance::Hold));
        // Hold: it now stays there, a passer-by notwithstanding.
        let p1 = s.add_unit(P1, UnitKind::Infantry, legs[1] + v(5, 0));
        s.entities[p1.0 as usize].ammunition = 0;
        for _ in 0..200 {
            s.step(&[]);
            assert_eq!(s.position(a), Some(legs[1]), "hold left its last leg");
        }
    }

    /// A queued unit that dies leaves nothing behind: its slot's next owner
    /// starts with an empty queue and stays put. Harvesters never queue, and a
    /// `QueueMove` from another owner is ignored.
    #[test]
    fn death_harvesters_and_other_owners_never_inherit_a_queue() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[qmove(a, v(20, 20)), qmove(a, v(20, 30))]);
        assert_eq!(s.queue_len(a), 1);
        s.entities[a.0 as usize].hp = Fixed::ZERO;
        s.step(&[]);
        assert!(s.position(a).is_none());
        assert_eq!(s.queue_len(a), 0, "a dead unit reports no queue");
        let b = s.add_unit(P0, UnitKind::Infantry, v(5, 5));
        assert_eq!(b, a, "the slot is reused");
        assert_eq!(s.queue_len(b), 0);
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(
            s.position(b),
            Some(v(5, 5)),
            "the new unit walked a dead queue"
        );
        let h = s.add_unit(P0, UnitKind::Harvester, v(30, 30));
        let before = s.state_hash();
        let mut twin = s.clone();
        s.step(&[qmove(h, v(35, 35))]);
        twin.step(&[]);
        assert_eq!(s.state_hash(), twin.state_hash(), "a harvester queued");
        assert_eq!(s.queue_len(h), 0);
        assert_ne!(before, s.state_hash());
        let mut s2 = s.clone();
        let mut twin = s.clone();
        s2.step(&[Command::QueueMove {
            owner: P1,
            unit: b,
            target: v(30, 5),
            attack_move: false,
        }]);
        twin.step(&[]);
        assert_eq!(
            s2.state_hash(),
            twin.state_hash(),
            "another owner's order was obeyed"
        );
    }

    #[test]
    fn queue_move_is_ignored_without_depth() {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let mut twin = s.clone();
        s.step(&[qmove(a, v(30, 20)), qattack(a, v(30, 30))]);
        twin.step(&[]);
        assert_eq!(
            s.state_hash(),
            twin.state_hash(),
            "a queued leg acted without depth"
        );
        for _ in 0..60 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(v(10, 20)));
        assert_eq!(s.queue_len(a), 0);
    }

    /// Queues replay: a skirmish where every unit walks a patrol of queued
    /// legs (some attack-move), with a `Stop`, a `Move` and an `AttackTarget` cutting
    /// in, run twice gives one hash, and the recorded log reproduces it. The
    /// queue is in the hash: the same world with one leg fewer hashes apart.
    #[test]
    fn queued_waypoints_are_deterministic_and_replay() {
        let setup = || {
            let mut s = depth_arena();
            let mut mine = Vec::new();
            let mut theirs = Vec::new();
            for i in 0..8 {
                mine.push(s.add_unit(P0, UnitKind::Infantry, v(6, 12 + i)));
                theirs.push(s.add_unit(P1, UnitKind::Infantry, v(28, 12 + i)));
            }
            (s, mine, theirs)
        };
        let orders = |t: u32, mine: &[EntityId], theirs: &[EntityId]| -> Vec<Command> {
            let mut c = Vec::new();
            match t {
                5 => {
                    for (k, &unit) in mine.iter().enumerate() {
                        let y = 10 + 2 * i32::try_from(k).unwrap();
                        c.push(qmove(unit, v(12, y)));
                        c.push(qattack(unit, v(20, y)));
                        c.push(qmove(unit, v(20, y + 6)));
                        c.push(qattack(unit, v(27, y)));
                    }
                }
                60 => c.push(Command::Stop {
                    owner: P0,
                    unit: mine[0],
                }),
                70 => c.push(Command::Move {
                    owner: P0,
                    unit: mine[1],
                    target: v(6, 30),
                }),
                80 => c.push(Command::AttackTarget {
                    owner: P0,
                    unit: mine[2],
                    target: theirs[2],
                }),
                90 => c.push(qmove(mine[2], v(10, 30))),
                _ => {}
            }
            c
        };
        let run = || {
            let (mut s, mine, theirs) = setup();
            let mut log = Vec::new();
            for t in 0..1200u32 {
                let c = orders(t, &mine, &theirs);
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (first, log) = run();
        let (second, _) = run();
        assert_eq!(first, second);
        let (mut replay, _, _) = setup();
        for c in &log {
            replay.step(c);
        }
        assert_eq!(replay.state_hash(), first);
        // The queue itself is hashed.
        let (mut s, mine, _) = setup();
        let mut t = s.clone();
        s.step(&[qmove(mine[0], v(12, 12)), qmove(mine[0], v(14, 14))]);
        t.step(&[qmove(mine[0], v(12, 12))]);
        assert_ne!(s.state_hash(), t.state_hash());
    }

    /// Task 14 tick cost: the two 40-rifle lines 15 apart on Kestrel, every
    /// human rifle on an eight-leg patrol (half of it attack-move), against the
    /// same world with no orders.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_queue_tick_cost -- --ignored --nocapture"]
    fn depth_queue_tick_cost() {
        let bench = |queued: bool| {
            let mut s = kestrel_reach(3);
            let mine: Vec<_> = (0..40u16)
                .map(|i| s.add_unit(P0, UnitKind::Infantry, hex::center(10, 5 + (i % 15))))
                .collect();
            for i in 0..40u16 {
                s.add_unit(P1, UnitKind::Infantry, hex::center(30, 5 + (i % 15)));
            }
            let mut first = Vec::new();
            if queued {
                for (k, &unit) in mine.iter().enumerate() {
                    let row = 5 + u16::try_from(k % 15).unwrap();
                    for leg in 0..QUEUE_CAP {
                        let col = if leg % 2 == 0 { 14 } else { 10 };
                        let target = hex::center(col, row);
                        first.push(if leg % 4 < 2 {
                            qmove(unit, target)
                        } else {
                            qattack(unit, target)
                        });
                    }
                }
            }
            let t = std::time::Instant::now();
            let mut worst = std::time::Duration::ZERO;
            for step in 0..900 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                if step == 0 {
                    c.extend(first.iter().cloned());
                }
                let t0 = std::time::Instant::now();
                s.step(&c);
                worst = worst.max(t0.elapsed());
            }
            (t.elapsed() / 900, worst)
        };
        let (mean, worst) = bench(true);
        let (pmean, pworst) = bench(false);
        std::eprintln!(
            "queued: mean {mean:?} worst {worst:?}; plain: mean {pmean:?} worst {pworst:?}"
        );
        assert!(mean < std::time::Duration::from_millis(5));
        assert!(worst < std::time::Duration::from_millis(15));
    }

    /// Task 15 duel result: units left and money value lost per side, and the
    /// steps run (the fight ends when a side is wiped out, or at 2400).
    #[derive(Debug)]
    struct Duel {
        a_left: usize,
        b_left: usize,
        a_value_lost: i64,
        b_value_lost: i64,
        ticks: u64,
    }

    /// The gameplay audit's duel method: side `a` (P0) in rows of three at
    /// x 14 to 16 and side `b` (P1) at x 19 to 21 of an open 40x40 Earthfront
    /// map with the default balance, both attack-moving through each other
    /// (to x 30 and x 4), at most 2400 steps.
    fn duel(a: &[(UnitKind, usize)], b: &[(UnitKind, usize)], depth: bool) -> Duel {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        duel_in(s, a, b)
    }

    /// [`duel`] in a prepared arena `s` (Task 17 buys upgrades first).
    fn duel_in(mut s: Sim, a: &[(UnitKind, usize)], b: &[(UnitKind, usize)]) -> Duel {
        let side = |s: &mut Sim, owner: PlayerId, x0: i32, army: &[(UnitKind, usize)]| {
            let mut ids = Vec::new();
            let mut row = 0i32;
            for &(k, n) in army {
                for _ in 0..n {
                    let id = s.add_unit(owner, k, v(x0 + row % 3, 10 + row / 3));
                    ids.push((id, k));
                    row += 1;
                }
            }
            ids
        };
        let ours = side(&mut s, P0, 14, a);
        let theirs = side(&mut s, P1, 19, b);
        let orders: Vec<_> = ours
            .iter()
            .map(|&(id, _)| (P0, id, 30))
            .chain(theirs.iter().map(|&(id, _)| (P1, id, 4)))
            .map(|(owner, unit, x)| Command::AttackMove {
                owner,
                unit,
                target: Vec2::new(Fixed::from_int(x), s.position(unit).unwrap().y),
            })
            .collect();
        s.step(&orders);
        let mut ticks = 0u64;
        while ticks < 2400 && s.unit_count(P0) > 0 && s.unit_count(P1) > 0 {
            s.step(&[]);
            ticks += 1;
        }
        let lost = |s: &Sim, ids: &[(EntityId, UnitKind)]| -> i64 {
            ids.iter()
                .filter(|&&(id, _)| s.position(id).is_none())
                .map(|&(_, k)| s.unit_cost(k).to_int_floor())
                .sum()
        };
        Duel {
            a_left: s.unit_count(P0),
            b_left: s.unit_count(P1),
            a_value_lost: lost(&s, &ours),
            b_value_lost: lost(&s, &theirs),
            ticks,
        }
    }

    #[test]
    fn anti_armour_teams_now_trade_with_gunships() {
        let d = duel(
            &[(UnitKind::Helicopter, 4)],
            &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)],
            true,
        );
        assert!(d.a_left < 4, "no helicopter losses: {d:?}");
        let s = kestrel_reach(1);
        let at_cost = 5 * s.unit_cost(UnitKind::AntiArmor).to_int_floor()
            + s.unit_cost(UnitKind::Infantry).to_int_floor();
        assert!(
            d.b_left > 0 || d.a_value_lost * 100 >= at_cost * 60,
            "{d:?}"
        );
    }

    #[test]
    fn infantry_still_cannot_touch_gunships() {
        let with = duel(
            &[(UnitKind::Helicopter, 4)],
            &[(UnitKind::Infantry, 12)],
            true,
        );
        let without = duel(
            &[(UnitKind::Helicopter, 4)],
            &[(UnitKind::Infantry, 12)],
            false,
        );
        assert_eq!((with.a_left, with.b_left), (without.a_left, without.b_left));
    }

    /// One row of the audit's ground triangle: (side a, side b, a wins,
    /// survivors of the winner in the audit, survivors under depth before
    /// Task 15).
    type TriangleCase = (
        &'static [(UnitKind, usize)],
        &'static [(UnitKind, usize)],
        bool,
        usize,
        usize,
    );

    /// The ground triangle is untouched by the air counter. The audit column
    /// was measured on the classic rules, which still reproduce it (checked
    /// here within one survivor, as the brief asks). Under depth Tasks 11 to
    /// 14 already moved two rows by two survivors before any air change
    /// (12 Inf vs 5 AT + 1 Inf: 12 -> 10; 24 Inf vs 11 AT: 21 -> 19, both
    /// measured at 05bb34e), so the depth run is held within one survivor of
    /// that pre-Task 15 depth column, and every winner matches the audit.
    #[test]
    fn the_ground_triangle_holds_within_one_survivor_of_the_audit() {
        // audit table (gameplay-audit.md section 2): winner side and survivors
        let cases: [TriangleCase; 4] = [
            (
                &[(UnitKind::Tank, 3)],
                &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)],
                false,
                4,
                4,
            ),
            (
                &[(UnitKind::Infantry, 12)],
                &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)],
                true,
                12,
                10,
            ),
            (
                &[(UnitKind::Tank, 6)],
                &[(UnitKind::AntiArmor, 11)],
                false,
                7,
                7,
            ),
            (
                &[(UnitKind::Infantry, 24)],
                &[(UnitKind::AntiArmor, 11)],
                true,
                21,
                19,
            ),
        ];
        for (a, b, a_wins, audit, depth_before) in cases {
            for (depth, left) in [(false, audit), (true, depth_before)] {
                let d = duel(a, b, depth);
                let (won, n) = if a_wins {
                    (d.b_left == 0, d.a_left)
                } else {
                    (d.a_left == 0, d.b_left)
                };
                assert!(
                    won && n.abs_diff(left) <= 1,
                    "{a:?} vs {b:?}, depth {depth}: {d:?}"
                );
            }
        }
    }

    /// The spec's guard on the counter: a gunship still beats an `AntiArmor`
    /// team one for one under depth, and with depth off a team still never
    /// touches a gunship (the audit's 0 losses).
    #[test]
    fn one_gunship_still_beats_one_team_and_classic_gunships_stay_untouchable() {
        let one = duel(
            &[(UnitKind::Helicopter, 1)],
            &[(UnitKind::AntiArmor, 1)],
            true,
        );
        assert_eq!((one.a_left, one.b_left), (1, 0), "{one:?}");
        let classic = duel(
            &[(UnitKind::Helicopter, 4)],
            &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)],
            false,
        );
        assert_eq!(
            (classic.a_left, classic.a_value_lost),
            (4, 0),
            "{classic:?}"
        );
    }

    /// One `AntiArmor` missile on a gunship lands `AT_AIR_PCT` percent of the
    /// hit it lands on a tank (both Plated, no cover in the air); a gunship
    /// with depth off is never hit at all.
    #[test]
    fn an_anti_armour_missile_lands_its_air_percent_on_a_gunship() {
        let first_hit = |depth: bool, kind: UnitKind| {
            let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
            s.enable_earthfront();
            if depth {
                s.enable_depth();
            }
            s.add_unit(P0, UnitKind::AntiArmor, v(10, 20));
            let foe = s.add_unit(P1, kind, v(12, 20));
            s.entities[foe.0 as usize].ammunition = 0;
            let hp0 = hp_of(&s, foe);
            for _ in 0..3 {
                s.step(&[]);
            }
            hp0 - hp_of(&s, foe)
        };
        let tank = first_hit(true, UnitKind::Tank);
        assert!(tank > Fixed::ZERO, "no hit on the tank");
        assert_eq!(
            first_hit(true, UnitKind::Helicopter),
            tank * Fixed::from_ratio(AT_AIR_PCT, 100)
        );
        assert_eq!(first_hit(false, UnitKind::Helicopter), Fixed::ZERO);
        assert_eq!(depth_air_damage_pct(Kind::Unit(UnitKind::Infantry)), 100);
        assert_eq!(
            depth_air_damage_pct(Kind::Building(BuildingKind::AaTurret)),
            100
        );
    }

    /// The override feeds every depth decision that reads a weapon: an idle
    /// team acquires a gunship in its ring (Task 11), an attack-moving team
    /// halts under one (Task 12 halt scan) and may be ordered onto one (Task
    /// 13). A rifle, which still cannot shoot air, does none of these.
    #[test]
    fn anti_armour_acquires_halts_for_and_targets_gunships_and_rifles_still_ignore_them() {
        let ring = |kind: UnitKind| {
            let mut s = depth_arena();
            let r = kind.stats().attack.range;
            let me = s.add_unit(P0, kind, v(10, 20));
            let heli = s.add_unit(
                P1,
                UnitKind::Helicopter,
                v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
            );
            s.entities[heli.0 as usize].ammunition = 0;
            s.debug_set_hp(heli, Fixed::from_int(1_000_000));
            for _ in 0..120 {
                s.step(&[]);
            }
            (
                hp_of(&s, heli) < Fixed::from_int(1_000_000),
                s.position(me).unwrap() == v(10, 20),
            )
        };
        assert_eq!(
            ring(UnitKind::AntiArmor),
            (true, false),
            "team: engaged and moved"
        );
        assert_eq!(
            ring(UnitKind::Infantry),
            (false, true),
            "rifle: ignored and stayed"
        );

        let march = |kind: UnitKind| {
            let mut s = depth_arena();
            let me = s.add_unit(P0, kind, v(5, 20));
            let heli = s.add_unit(P1, UnitKind::Helicopter, v(8, 20));
            s.entities[heli.0 as usize].ammunition = 0;
            s.debug_set_hp(heli, Fixed::from_int(1_000_000));
            s.step(&[Command::AttackMove {
                owner: P0,
                unit: me,
                target: v(30, 20),
            }]);
            for _ in 0..600 {
                s.step(&[]);
            }
            s.position(me).unwrap().x
        };
        // The gunship is in weapon range from the start, so the halt scan
        // stops the team where it stands (attack-move steering alone would
        // walk it onto the gunship).
        assert_eq!(
            march(UnitKind::AntiArmor),
            Fixed::from_int(5),
            "team did not halt"
        );
        assert!(
            march(UnitKind::Infantry) > Fixed::from_int(20),
            "rifle halted"
        );

        let order = |kind: UnitKind| {
            let mut s = depth_arena();
            let me = s.add_unit(P0, kind, v(10, 20));
            let heli = s.add_unit(P1, UnitKind::Helicopter, v(20, 20));
            s.step(&[Command::AttackTarget {
                owner: P0,
                unit: me,
                target: heli,
            }]);
            s.entities[me.0 as usize].dp.forced
        };
        assert!(
            order(UnitKind::AntiArmor).is_some(),
            "team refused the gunship"
        );
        assert_eq!(order(UnitKind::Infantry), None, "rifle took the gunship");
    }

    /// A gunship strafing a rifle draws the team standing beside it (Task 11
    /// call for help); a second rifle beside it cannot answer.
    #[test]
    fn a_team_answers_a_gunship_hitting_its_ally() {
        let mut s = depth_arena();
        let victim = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.debug_set_hp(victim, Fixed::from_int(1_000_000));
        let team = s.add_unit(P0, UnitKind::AntiArmor, v(6, 20));
        let rifle = s.add_unit(P0, UnitKind::Infantry, v(6, 21));
        // In the gunship's range of the victim, past the team's ring (4 + 3).
        let heli = s.add_unit(P1, UnitKind::Helicopter, v(14, 20));
        s.debug_set_hp(heli, Fixed::from_int(1_000_000));
        let mut answered = false;
        for _ in 0..90 {
            s.step(&[]);
            answered |= s.entities[team.0 as usize].dp.engaged == Some(heli);
            assert_eq!(s.entities[rifle.0 as usize].dp.engaged, None);
        }
        assert!(answered, "the team never answered the gunship");
        assert!(hp_of(&s, heli) < Fixed::from_int(1_000_000));
    }

    /// The audit's ten fights (section 2), depth off and on, printed for the
    /// task report. Depth off reproduces the audit table exactly.
    #[test]
    #[ignore = "table: cargo test -p rts-core --offline audit_duel_table -- --ignored --nocapture"]
    fn audit_duel_table() {
        type Army = &'static [(UnitKind, usize)];
        use UnitKind::{AntiArmor, Helicopter, Infantry, Tank};
        let armies: [(&str, &[(UnitKind, usize)]); 5] = [
            ("12 Inf", &[(Infantry, 12)]),
            ("3 Tank", &[(Tank, 3)]),
            ("5 AT + 1 Inf", &[(AntiArmor, 5), (Infantry, 1)]),
            ("4 Heli", &[(Helicopter, 4)]),
            ("6 Inf + 3 AT", &[(Infantry, 6), (AntiArmor, 3)]),
        ];
        let mut fights: Vec<(String, Army, Army)> = Vec::new();
        for i in 0..armies.len() {
            for j in (i + 1)..armies.len() {
                fights.push((
                    std::format!("{} vs {}", armies[i].0, armies[j].0),
                    armies[i].1,
                    armies[j].1,
                ));
            }
        }
        fights.push(("24 Inf vs 6 Tank".into(), &[(Infantry, 24)], &[(Tank, 6)]));
        fights.push((
            "24 Inf vs 11 AT".into(),
            &[(Infantry, 24)],
            &[(AntiArmor, 11)],
        ));
        fights.push(("6 Tank vs 11 AT".into(), &[(Tank, 6)], &[(AntiArmor, 11)]));
        fights.push((
            "4 Heli vs 5 AT + 1 Inf (gate)".into(),
            &[(Helicopter, 4)],
            &[(AntiArmor, 5), (Infantry, 1)],
        ));
        fights.push((
            "4 Heli vs 11 AT".into(),
            &[(Helicopter, 4)],
            &[(AntiArmor, 11)],
        ));
        fights.push((
            "4 Heli vs 3 AT".into(),
            &[(Helicopter, 4)],
            &[(AntiArmor, 3)],
        ));
        fights.push((
            "1 Heli vs 1 AT".into(),
            &[(Helicopter, 1)],
            &[(AntiArmor, 1)],
        ));
        fights.push((
            "2 Heli vs 3 AT".into(),
            &[(Helicopter, 2)],
            &[(AntiArmor, 3)],
        ));
        fights.push((
            "4 Heli vs 6 AT + 6 Inf".into(),
            &[(Helicopter, 4)],
            &[(AntiArmor, 6), (Infantry, 6)],
        ));
        for (name, a, b) in fights {
            let off = duel(a, b, false);
            let on = duel(a, b, true);
            let cell = |d: &Duel| {
                std::format!(
                    "{} / {} left, lost {} / {}, t={}",
                    d.a_left,
                    d.b_left,
                    d.a_value_lost,
                    d.b_value_lost,
                    d.ticks
                )
            };
            std::eprintln!("| {name} | {} | {} |", cell(&off), cell(&on));
        }
    }

    // Task 16: walls delay instead of win (breach pathing, siege threshold).

    /// The audit's four-wall seal: every passable west-bank hex beside the two
    /// Wyllow Ford hexes, `(22, 10)` and `(23, 10)`.
    const FORD_SEAL: [(u16, u16); 4] = [(21, 9), (21, 10), (22, 11), (23, 11)];
    /// Open grass beside the home Command Centre. The plan's seal check pathed
    /// to `HOME_CC` itself, a building footprint no path ever ends on, so it
    /// held with or without the walls; a path to this hex only fails sealed.
    const HOME_YARD: (u16, u16) = (8, 9);

    /// A depth arena with waves configured P1 against P0 (never spawned: P1
    /// has no Command Centre), so P1 units are the waves' attacker, a P0
    /// Command Centre at (3, 20) and a line of P0 `kind` across column 20.
    fn breach_arena(line: BuildingKind) -> Sim {
        breach_arena_with(|_| line)
    }

    /// [`breach_arena`] with the building at `(20, y)` chosen by `line`.
    fn breach_arena_with(line: impl Fn(u16) -> BuildingKind) -> Sim {
        let mut s = depth_arena();
        s.set_waves(crate::game::sim::WaveConfig {
            first_delay: 1_000_000,
            interval: 1_000_000,
            base_size: 0,
            growth: 0,
            spawn: hex::center(30, 20),
            unit: UnitKind::Infantry,
            attacker: P1,
            defender: P0,
            escalate: false,
        });
        s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
        for y in 0..40 {
            s.add_building(P0, line(y), 20, y);
        }
        s
    }

    fn attack_move(owner: PlayerId, unit: EntityId, target: Vec2) -> Command {
        Command::AttackMove {
            owner,
            unit,
            target,
        }
    }

    fn p1_qmove(unit: EntityId, target: Vec2) -> Command {
        Command::QueueMove {
            owner: P1,
            unit,
            target,
            attack_move: false,
        }
    }

    fn tile_of(s: &Sim, id: EntityId) -> (u16, u16) {
        s.world_to_tile(s.entities[id.0 as usize].pos)
    }

    fn living_walls(s: &Sim, owner: PlayerId) -> usize {
        s.count_alive_buildings(owner, BuildingKind::Wall)
    }

    #[test]
    fn a_walled_off_wave_unit_breaks_the_first_wall_and_walks_on() {
        let mut s = breach_arena(BuildingKind::Wall);
        let tank = s.add_unit(P1, UnitKind::Tank, hex::center(30, 20));
        s.step(&[attack_move(P1, tank, hex::center(5, 20))]);
        let e = &s.entities[tank.0 as usize];
        let wall = e.dp.forced.expect("the blocked unit forces a wall");
        let w = &s.entities[wall.0 as usize];
        assert_eq!(w.kind, Kind::Building(BuildingKind::Wall));
        assert_eq!(w.owner, P0);
        assert!(e.dp.breach_tried);
        assert_eq!(e.dp.queue, alloc::vec![(hex::center(5, 20), true)]);
        assert!(
            e.path
                .iter()
                .all(|&(x, y)| s.map.tile(x.into(), y.into()).unwrap().passable),
            "the walk stops short of the wall"
        );
        assert_eq!(s.breach_searches, 1);
        let mut crossed = false;
        for _ in 0..4000 {
            s.step(&[]);
            if tile_of(&s, tank).0 < 20 {
                crossed = true;
                break;
            }
        }
        assert!(crossed, "the tank never got through");
        // Once the gap is open it resumes its attack-move, which (as before
        // depth) also fights the walls in reach on its way through the gap.
        assert!(living_walls(&s, P0) < 40);
        assert_eq!(s.breach_searches, 1, "one search per order target");
        assert_eq!(s.entities[tank.0 as usize].dp.forced, None);
    }

    #[test]
    fn a_breach_prefers_a_wall_to_any_other_building() {
        // Column 20 is walls except a plant straight on the line of march: the
        // wall costs half as much, so the route bends to the next wall hex.
        let mut s = breach_arena_with(|y| {
            if y == 20 {
                BuildingKind::PowerPlant
            } else {
                BuildingKind::Wall
            }
        });
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20));
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        let forced = s.entities[rifle.0 as usize].dp.forced.unwrap();
        assert_eq!(
            s.entities[forced.0 as usize].kind,
            Kind::Building(BuildingKind::Wall)
        );
        // A line of plants only: the plant on the route is forced instead.
        let mut s = breach_arena(BuildingKind::PowerPlant);
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20));
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        let forced = s.entities[rifle.0 as usize].dp.forced.unwrap();
        assert_eq!(
            s.entities[forced.0 as usize].kind,
            Kind::Building(BuildingKind::PowerPlant)
        );
    }

    #[test]
    fn only_the_waves_attacker_breaches_and_only_under_depth() {
        // The defender's own unit behind the line just gets no route.
        let mut s = breach_arena(BuildingKind::Wall);
        let ours = s.add_unit(P0, UnitKind::Infantry, hex::center(30, 20));
        s.step(&[attack_move(P0, ours, hex::center(5, 20))]);
        let e = &s.entities[ours.0 as usize];
        assert_eq!(
            (e.dp.forced, e.move_target, e.dp.breach_tried),
            (None, None, false)
        );
        assert_eq!(s.breach_searches, 0);
        // Depth off: the attacker is stuck as before.
        let mut s = breach_arena(BuildingKind::Wall);
        s.depth = false;
        let theirs = s.add_unit(P1, UnitKind::Tank, hex::center(30, 20));
        s.step(&[attack_move(P1, theirs, hex::center(5, 20))]);
        let e = &s.entities[theirs.0 as usize];
        assert_eq!((e.dp.forced, e.move_target), (None, None));
        assert_eq!(s.breach_searches, 0);
    }

    #[test]
    fn one_breach_search_per_order_target() {
        // A river column with no building in it: no breach route exists, so
        // the single search fails and is never retried until a new order.
        let mut s = breach_arena(BuildingKind::Wall);
        for y in 0..40 {
            s.map.set_ground(25, y, crate::game::map::Ground::River);
        }
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20));
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        assert_eq!(s.breach_searches, 1);
        assert!(s.entities[rifle.0 as usize].dp.breach_tried);
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(s.breach_searches, 1, "a failed breach is never retried");
        // A new order target is a new search.
        s.step(&[attack_move(P1, rifle, hex::center(5, 21))]);
        assert_eq!(s.breach_searches, 2);
        // Stop resets it; a later order searches again.
        s.step(&[Command::Stop {
            owner: P1,
            unit: rifle,
        }]);
        assert!(!s.entities[rifle.0 as usize].dp.breach_tried);
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        assert_eq!(s.breach_searches, 3);
    }

    #[test]
    fn a_new_order_or_stop_ends_a_breach() {
        let mut s = breach_arena(BuildingKind::Wall);
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20));
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        assert!(s.entities[rifle.0 as usize].dp.forced.is_some());
        s.step(&[Command::Move {
            owner: P1,
            unit: rifle,
            target: hex::center(32, 25),
        }]);
        let e = &s.entities[rifle.0 as usize];
        assert_eq!((e.dp.forced, e.dp.queue.len()), (None, 0));
        assert!(!e.dp.breach_tried, "a reachable order never searched");
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        assert!(s.entities[rifle.0 as usize].dp.forced.is_some());
        s.step(&[Command::Stop {
            owner: P1,
            unit: rifle,
        }]);
        let e = &s.entities[rifle.0 as usize];
        assert_eq!(
            (e.dp.forced, e.dp.queue.len(), e.move_target),
            (None, 0, None)
        );
    }

    #[test]
    fn a_breach_keeps_queued_legs_and_hold_still_follows_it() {
        // A Hold-stance attacker queues a reachable leg, then one across the
        // wall: the breach runs when that leg starts, and the leg after it is
        // walked once the wall is down.
        let mut s = breach_arena(BuildingKind::Wall);
        let tank = s.add_unit(P1, UnitKind::Tank, hex::center(30, 20));
        s.step(&[Command::HoldPosition {
            owner: P1,
            unit: tank,
        }]);
        s.step(&[
            Command::Move {
                owner: P1,
                unit: tank,
                target: hex::center(28, 20),
            },
            p1_qmove(tank, hex::center(5, 20)),
            p1_qmove(tank, hex::center(5, 30)),
        ]);
        let mut forced_seen = false;
        for _ in 0..5000 {
            s.step(&[]);
            forced_seen |= s.entities[tank.0 as usize].dp.forced.is_some();
            if s.entities[tank.0 as usize].dp.queue.is_empty() && tile_of(&s, tank).0 < 20 {
                break;
            }
        }
        assert!(forced_seen, "the queued leg never breached");
        assert!(tile_of(&s, tank).0 < 20, "never crossed");
        assert_eq!(s.stance_of(tank), Some(Stance::Hold));
        for _ in 0..1500 {
            s.step(&[]);
        }
        let (x, y) = tile_of(&s, tank);
        assert!(x <= 6 && y >= 28, "the last leg was not walked: at {x},{y}");
    }

    #[test]
    fn a_crowd_at_the_wall_spreads_without_jamming_and_breaks_through() {
        let mut s = breach_arena(BuildingKind::Wall);
        let rifles: Vec<EntityId> = (0..12)
            .map(|_| s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20)))
            .collect();
        let orders: Vec<Command> = rifles
            .iter()
            .map(|&r| attack_move(P1, r, hex::center(5, 20)))
            .collect();
        s.step(&orders);
        let mut targets: Vec<u32> = rifles
            .iter()
            .filter_map(|r| s.entities[r.0 as usize].dp.forced.map(|t| t.0))
            .collect();
        targets.dedup();
        assert_eq!(targets.len(), 1, "the crowd focuses one wall: {targets:?}");
        assert!(rifles
            .iter()
            .all(|r| s.entities[r.0 as usize].dp.forced.is_some()));
        for _ in 0..3000 {
            s.step(&[]);
        }
        let through = rifles.iter().filter(|&&r| tile_of(&s, r).0 < 20).count();
        assert_eq!(through, rifles.len(), "{through} of 12 got through");
    }

    #[test]
    fn the_alien_ai_leaves_a_breaching_unit_alone() {
        // P1 gets a base so its Earthfront AI runs; it re-orders every idle
        // unit every 30 ticks, which would cancel a breach at the wall.
        let mut s = breach_arena(BuildingKind::Wall);
        s.add_building(P1, BuildingKind::CommandCenter, 36, 20);
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(22, 20));
        let idle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 30));
        s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        let (mut at_wall, mut idle_ordered) = (0, false);
        for _ in 0..120 {
            let ai = s.ai_commands(P1);
            let ordered = |u: EntityId| {
                ai.iter().any(|c| {
                    matches!(c, Command::Move { unit, .. } | Command::AttackMove { unit, .. } if *unit == u)
                })
            };
            let e = &s.entities[rifle.0 as usize];
            assert!(e.dp.forced.is_some(), "the breach was cancelled");
            if e.move_target.is_none() && s.tick().is_multiple_of(30) {
                at_wall += 1;
            }
            assert!(!ordered(rifle), "the AI re-ordered the breaching rifle");
            idle_ordered |= ordered(idle);
            s.step(&ai);
        }
        assert!(
            at_wall > 0,
            "the rifle never stood at the wall on an AI tick"
        );
        assert!(idle_ordered, "the AI is not running");
    }

    #[test]
    fn breaching_is_deterministic_and_replays() {
        let run = || {
            let mut s = kestrel_reach(3);
            for (x, y) in FORD_SEAL {
                s.add_building(P0, BuildingKind::Wall, x, y);
            }
            let mut log = Vec::new();
            for _ in 0..4200 {
                let c = Scenario::KestrelReach.host_commands(&s);
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = kestrel_reach(3);
        for (x, y) in FORD_SEAL {
            r.add_building(P0, BuildingKind::Wall, x, y);
        }
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    #[test]
    fn four_wall_ford_seal_is_breached_by_wave_two() {
        use crate::game::kestrel;
        use crate::game::path::find_path;
        // Wave two spawns at 4500 + 5400 and crosses in well under 1800 ticks.
        // A fixed step count: a decided match stops advancing its tick.
        const STEPS: u32 = 4500 + 5400 + 1800;
        let run = |mut s: Sim| {
            // Clear the east bank first, as the audit's measured run did: the
            // probe on its picket and the south relay's GunTurret at (29, 12)
            // (range 5) have the seal walls in reach and shoot them down even
            // in classic Kestrel (all four gone by t=2167, base hit at 3461),
            // and under depth the relay's AntiArmor team at (30, 14) acquires
            // them on its own (all four gone by t=624, no breach needed). With
            // them gone only a breach can open the seal. Task 19: the alien AI
            // now runs from tick 0, and its home rally walks the north relay's
            // AntiArmor team at (28, 4) on an attack-move that steps toward
            // the seal and shoots a wall at t=208, so that team goes too.
            let mut cleared = crate::game::scenario::kestrel_probe_units(&s);
            cleared.extend(
                s.views()
                    .iter()
                    .filter(|v| matches!(s.world_to_tile(v.pos), (29, 12) | (30, 14) | (28, 4)))
                    .map(|v| v.id),
            );
            assert_eq!(cleared.len(), 6);
            for id in cleared {
                s.entities[id.0 as usize].hp = Fixed::ZERO;
            }
            assert!(find_path(s.map(), kestrel::HOLDFAST, HOME_YARD).is_some());
            for (x, y) in FORD_SEAL {
                s.add_building(P0, BuildingKind::Wall, x, y);
            }
            assert!(
                find_path(s.map(), kestrel::HOLDFAST, HOME_YARD).is_none(),
                "seal is not a seal"
            );
            let mut breached_at = None;
            for _ in 0..STEPS {
                // Task 19: the alien AI now runs from tick 0, so its training
                // is held off here. A Tank it trains at t=3750 rallies onto
                // the ford and shoots a seal wall at t=3885, before any wave,
                // and a rifle born in a cleared probe squad's slot would be
                // staged on the picket by the probe script. Waves still come.
                let mut c = Scenario::KestrelReach.host_commands(&s);
                c.retain(|c| !matches!(c, Command::Train { owner: P1, .. }));
                s.step(&c);
                if living_walls(&s, P0) < FORD_SEAL.len() && breached_at.is_none() {
                    breached_at = Some(s.tick());
                }
                if s.winner().is_some() {
                    break;
                }
            }
            (breached_at, s)
        };
        let (breach, s) = run(kestrel_reach(3));
        assert!(breach.is_some(), "no wall fell by wave two");
        assert!(s.breach_searches > 0, "the seal fell without a breach");
        assert!(
            breach > Some(crate::game::scenario::KESTREL_FIRST_WAVE_TICKS),
            "a wall fell before any wave: {breach:?}"
        );
        assert!(s.winner().is_some() || s.waves_survived() >= 2);
        let base_hit = s.winner() == Some(P1)
            || s.views().iter().any(|v| {
                v.owner == P0
                    && matches!(v.kind, EntityKindView::Building(k) if k != BuildingKind::Wall)
                    && v.hp < v.max_hp
            });
        assert!(base_hit, "the base was never attacked");
        let (classic, s) = run(kestrel_reach_classic(3));
        assert!(
            classic.is_none(),
            "classic Kestrel documents the old exploit"
        );
        assert_eq!(s.winner(), None, "the classic seal holds");
        assert_eq!(s.breach_searches, 0);
    }

    /// The first `n` units spawned by the next Kestrel wave with three human
    /// walls standing from tick 0, and the doctrine announced for it.
    fn wave_one_with_three_walls(mut s: Sim) -> (&'static str, u32, Vec<UnitKind>) {
        for (x, y) in [(3, 9), (3, 10), (3, 11)] {
            s.add_building(P0, BuildingKind::Wall, x, y);
        }
        // Task 19: with the alien AI buying Upgrades from tick 0 the probe
        // alone took the undefended base before wave one (t=4121 on seed 3),
        // so it is cleared. Task 20 holds those Upgrades until wave one; the
        // probe stays cleared because this test reads only the composition.
        for id in crate::game::scenario::kestrel_probe_units(&s) {
            s.entities[id.0 as usize].hp = Fixed::ZERO;
        }
        let mut before = 0;
        for _ in 0..4600 {
            if s.waves_survived() == 1 {
                break;
            }
            // No slot reuse, so the wave's units are appended in spawn order.
            s.free.clear();
            before = s.entities.len();
            let c = Scenario::KestrelReach.host_commands(&s);
            s.step(&c);
        }
        assert_eq!(s.waves_survived(), 1, "wave one never came");
        let budget = u32::try_from(
            s.entities[before..]
                .iter()
                .filter(|e| e.owner == P1 && matches!(e.kind, Kind::Unit(_)))
                .count(),
        )
        .unwrap();
        let kinds = s.entities[before..]
            .iter()
            .filter(|e| e.owner == P1)
            .filter_map(|e| match e.kind {
                Kind::Unit(k) => Some(k),
                Kind::Building(_) => None,
            })
            .collect();
        (s.incoming_doctrine(), budget, kinds)
    }

    #[test]
    fn three_walls_call_a_siege_led_by_tanks() {
        let (doctrine, budget, kinds) = wave_one_with_three_walls(kestrel_reach(3));
        assert_eq!(doctrine, "Siege against fortifications");
        assert!(budget >= 6, "wave one spawned {budget}");
        let lead = usize::try_from(budget.div_ceil(4)).unwrap();
        assert!(
            kinds[..lead].iter().all(|&k| k == UnitKind::Tank),
            "{kinds:?}"
        );
        assert!(
            kinds[lead..].iter().all(|&k| k != UnitKind::Tank),
            "{kinds:?}"
        );
        // Classic keeps the old threshold (more than five walls) and wave one
        // stays all rifles.
        let (doctrine, _, kinds) = wave_one_with_three_walls(kestrel_reach_classic(3));
        assert_ne!(doctrine, "Siege against fortifications");
        assert!(kinds.iter().all(|&k| k == UnitKind::Infantry), "{kinds:?}");
    }

    /// Breach tick cost on Kestrel with the ford sealed: 40 alien rifles
    /// attack-moved at the base from the east bank on the first tick (all
    /// blocked, so each runs its one breach search on that tick) and 40 human
    /// rifles at home, hosted as the bridge hosts them; against the same
    /// armies with the ford open, and the sealed ford in classic Kestrel
    /// (whose failed searches the breach search comes on top of).
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_breach_tick_cost -- --ignored --nocapture"]
    fn depth_breach_tick_cost() {
        let bench = |mut s: Sim, sealed: bool| {
            if sealed {
                for (x, y) in FORD_SEAL {
                    s.add_building(P0, BuildingKind::Wall, x, y);
                }
            }
            for i in 0..40u16 {
                s.add_unit(P0, UnitKind::Infantry, hex::center(10, 5 + (i % 15)));
            }
            let aliens: Vec<EntityId> = (0..40u16)
                .map(|i| s.add_unit(P1, UnitKind::Infantry, hex::center(30, 5 + (i % 15))))
                .collect();
            let units = s.unit_count(P0) + s.unit_count(P1);
            let t = std::time::Instant::now();
            let mut worst = std::time::Duration::ZERO;
            let mut first = (std::time::Duration::ZERO, 0);
            for step in 0..900 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                if step == 0 {
                    c.extend(
                        aliens
                            .iter()
                            .map(|&a| attack_move(P1, a, hex::center(8, 9))),
                    );
                }
                let t0 = std::time::Instant::now();
                s.step(&c);
                let dt = t0.elapsed();
                if step == 0 {
                    first = (dt, s.breach_searches);
                }
                worst = worst.max(dt);
            }
            (units, first, s.breach_searches, t.elapsed() / 900, worst)
        };
        let runs = [
            ("depth, sealed", bench(kestrel_reach(3), true)),
            ("depth, open", bench(kestrel_reach(3), false)),
            ("classic, sealed", bench(kestrel_reach_classic(3), true)),
        ];
        for (label, (n, (first, first_searches), searches, mean, worst)) in &runs {
            std::eprintln!(
                "{label}: {n} units; order tick {first:?} with {first_searches} breach searches ({searches} in 900 ticks); mean {mean:?}, worst {worst:?}"
            );
        }
        for (_, (n, _, _, mean, worst)) in runs {
            assert!(n >= 80);
            assert!(mean < std::time::Duration::from_millis(5));
            assert!(worst < std::time::Duration::from_millis(15));
        }
    }

    // ---- P2 review fixes ----

    /// P2 review I1: a structure raised on a waypoint still ahead of a marching
    /// ground unit (the next one, or one three legs on) makes it path around.
    /// It used to jitter between its tile centre and the hex edge forever.
    #[test]
    fn a_structure_raised_on_the_route_is_walked_around() {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::AntiArmor] {
            for ahead in [0_usize, 3] {
                let mut s = depth_arena();
                let unit = s.add_unit(P0, kind, hex::center(5, 20));
                s.step(&[Command::Move {
                    owner: P0,
                    unit,
                    target: hex::center(30, 20),
                }]);
                if ahead > 0 {
                    for _ in 0..30 {
                        s.step(&[]);
                    }
                }
                let (wx, wy) = s.entities[unit.0 as usize].path[ahead];
                s.add_building(P0, BuildingKind::Wall, wx, wy);
                for _ in 0..1500 {
                    s.step(&[]);
                }
                let e = &s.entities[unit.0 as usize];
                assert_eq!(
                    (tile_of(&s, unit), e.move_target),
                    ((30, 20), None),
                    "{kind:?} stranded by a wall on path[{ahead}]"
                );
            }
        }
    }

    /// P2 review I2: `order_goal` gates depth re-paths, so it is hashed under
    /// depth (and only there: classic and Survival hashes never see it).
    #[test]
    fn order_goal_is_hashed_under_depth_only() {
        let mut s = depth_arena();
        let u = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[]);
        let mut t = s.clone();
        t.entities[u.0 as usize].order_goal = Some(v(12, 20));
        assert_ne!(s.state_hash(), t.state_hash(), "order_goal is not hashed");
        s.depth = false;
        t.depth = false;
        assert_eq!(
            s.state_hash(),
            t.state_hash(),
            "order_goal is hashed with depth off"
        );
    }

    /// P2 review M1: an `AttackTarget` on a live enemy that nothing of ours
    /// tracks is a true no-op, exactly like one on an unknown id (it used to
    /// halt the unit, an oracle for hidden enemies).
    #[test]
    fn attack_target_on_an_untracked_enemy_changes_nothing() {
        let setup = || {
            let mut s = depth_arena();
            let a = s.add_unit(P0, UnitKind::Infantry, hex::center(5, 5));
            let far = s.add_unit(P1, UnitKind::Infantry, hex::center(35, 35));
            s.entities[far.0 as usize].ammunition = 0;
            s.step(&[Command::Move {
                owner: P0,
                unit: a,
                target: hex::center(5, 30),
            }]);
            (s, a, far)
        };
        let (mut s, a, far) = setup();
        let (mut twin, _, _) = setup();
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: far,
        }]);
        twin.step(&[]);
        assert_eq!(s.state_hash(), twin.state_hash(), "the order acted");
        assert!(s.entities[a.0 as usize].move_target.is_some());
    }

    /// P2 review M2 (Task 11 ruling 6): a unit that runs dry gives up its
    /// forced target, and a dry unit takes no forced order at all.
    #[test]
    fn a_dry_unit_gives_up_its_forced_target_and_takes_none() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let wall = s.add_building(P1, BuildingKind::Wall, 16, 20);
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: wall,
        }]);
        assert_eq!(s.entities[a.0 as usize].dp.forced, Some(wall));
        s.entities[a.0 as usize].ammunition = 0;
        for _ in 0..30 {
            s.step(&[]);
        }
        assert_eq!(
            s.entities[a.0 as usize].dp.forced, None,
            "a dry unit kept its forced target"
        );
        let mut twin = s.clone();
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: a,
            target: wall,
        }]);
        twin.step(&[]);
        assert_eq!(
            s.state_hash(),
            twin.state_hash(),
            "a dry unit took the order"
        );
    }

    /// P2 review M2: a forced target whose nearest reachable tile is still out
    /// of weapon range (a gunship hovering over the sea) ends the order once
    /// the unit stands as close as it can get, instead of re-ordering it every
    /// tick.
    #[test]
    fn an_unreachable_forced_target_is_released_not_reordered_every_tick() {
        let mut s = depth_arena();
        for x in 14..40 {
            for y in 0..40 {
                s.map.set_ground(x, y, crate::game::map::Ground::River);
            }
        }
        let team = s.add_unit(P0, UnitKind::AntiArmor, hex::center(10, 20));
        let heli = s.add_unit(P1, UnitKind::Helicopter, hex::center(22, 20));
        s.entities[heli.0 as usize].ammunition = 0;
        s.step(&[Command::AttackTarget {
            owner: P0,
            unit: team,
            target: heli,
        }]);
        assert_eq!(s.entities[team.0 as usize].dp.forced, Some(heli));
        let calls = s.order_calls;
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(
            s.entities[team.0 as usize].dp.forced, None,
            "never released"
        );
        assert!(
            s.order_calls - calls <= 3,
            "re-ordered {} times",
            s.order_calls - calls
        );
    }

    /// P2 review M3: a unit that dies on the tick its forced target dies is
    /// never re-ordered (no queued leg started on a corpse).
    #[test]
    fn a_unit_dying_with_its_forced_target_is_not_reordered() {
        let mut s = depth_arena();
        let tank = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(11, 20));
        s.entities[foe.0 as usize].ammunition = 0;
        s.entities[foe.0 as usize].hp = Fixed::from_int(100_000);
        s.step(&[
            Command::AttackTarget {
                owner: P0,
                unit: tank,
                target: foe,
            },
            qmove(tank, hex::center(10, 32)),
        ]);
        let e = &s.entities[tank.0 as usize];
        assert_eq!((e.dp.forced, e.dp.queue.len()), (Some(foe), 1));
        assert_eq!(e.move_target, None, "the foe is in range");
        s.entities[tank.0 as usize].hp = Fixed::ZERO;
        s.entities[foe.0 as usize].hp = Fixed::ZERO;
        let calls = s.order_calls;
        s.step(&[]);
        let e = &s.entities[tank.0 as usize];
        assert!(!e.alive);
        assert_eq!(
            (e.move_target, e.path.len(), e.dp.queue.len(), e.dp.forced),
            (None, 0, 0, None)
        );
        assert_eq!(s.order_calls, calls, "a corpse was ordered");
    }

    /// P2 review M4: Stop, Hold and stance orders leave Harvesters alone (a
    /// Hold Harvester was never pushed and slowed the docking crowd).
    #[test]
    fn stop_hold_and_stance_ignore_harvesters() {
        let setup = || {
            let mut s = depth_arena();
            let h = s.add_unit(P0, UnitKind::Harvester, v(10, 20));
            s.step(&[Command::Move {
                owner: P0,
                unit: h,
                target: v(20, 20),
            }]);
            (s, h)
        };
        let (mut s, h) = setup();
        let (mut twin, _) = setup();
        s.step(&[
            Command::Stop { owner: P0, unit: h },
            Command::HoldPosition { owner: P0, unit: h },
            Command::SetStance {
                owner: P0,
                unit: h,
                stance: Stance::Defensive,
            },
        ]);
        twin.step(&[]);
        assert_eq!(s.state_hash(), twin.state_hash(), "a harvester obeyed");
        assert_eq!(s.stance_of(h), Some(Stance::Aggressive));
    }

    /// P2 review M5: an order point far outside any map (raw `i64` bits from a
    /// hand-written or replayed line) is dropped, never panics, on depth,
    /// classic Earthfront and plain maps alike.
    #[test]
    fn out_of_range_order_points_are_dropped_without_panicking() {
        let huge = [i64::MIN, i64::MAX, i64::MIN / 2, -(1_i64 << 40)];
        for mode in 0..3 {
            let setup = || {
                let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
                if mode > 0 {
                    s.enable_earthfront();
                }
                if mode > 1 {
                    s.enable_depth();
                }
                let tank = s.add_unit(P0, UnitKind::Tank, v(10, 20));
                let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 5);
                (s, tank, barracks)
            };
            for &bits in &huge {
                for point in [
                    Vec2::new(Fixed::from_bits(bits), Fixed::from_int(5)),
                    Vec2::new(Fixed::from_int(5), Fixed::from_bits(bits)),
                ] {
                    let (mut s, tank, barracks) = setup();
                    let (mut twin, _, _) = setup();
                    s.step(&[
                        Command::Move {
                            owner: P0,
                            unit: tank,
                            target: point,
                        },
                        Command::AttackMove {
                            owner: P0,
                            unit: tank,
                            target: point,
                        },
                        Command::QueueMove {
                            owner: P0,
                            unit: tank,
                            target: point,
                            attack_move: true,
                        },
                        Command::SetRally {
                            owner: P0,
                            producer: barracks,
                            target: point,
                        },
                        Command::UseAbility {
                            owner: P0,
                            unit: tank,
                            target: point,
                        },
                    ]);
                    twin.step(&[]);
                    assert_eq!(
                        s.state_hash(),
                        twin.state_hash(),
                        "mode {mode}: an out-of-range point acted"
                    );
                }
            }
        }
    }

    /// P2 review M6: a hopeless alien unit (no route even through the walls)
    /// searches once per order target, however often the AI re-issues the
    /// same order; a different target, or a halt, searches again.
    #[test]
    fn a_failed_breach_is_not_searched_again_for_the_same_target() {
        let mut s = breach_arena(BuildingKind::Wall);
        for y in 0..40 {
            s.map.set_ground(25, y, crate::game::map::Ground::River);
        }
        let rifle = s.add_unit(P1, UnitKind::Infantry, hex::center(30, 20));
        for _ in 0..5 {
            s.step(&[Command::Move {
                owner: P1,
                unit: rifle,
                target: hex::center(5, 20),
            }]);
            s.step(&[attack_move(P1, rifle, hex::center(5, 20))]);
        }
        assert_eq!(s.breach_searches, 1, "re-searched a hopeless target");
        s.step(&[attack_move(P1, rifle, hex::center(5, 22))]);
        assert_eq!(s.breach_searches, 2);
    }

    // ---- Task 17: abilities, the Capital at era 1 and Upgrades under depth.

    /// Three alien rifles packed inside a 1.5 blast around `v(8, 10)`.
    fn clump(s: &mut Sim) -> [EntityId; 3] {
        [
            s.add_unit(P1, UnitKind::Infantry, v(8, 10)),
            s.add_unit(P1, UnitKind::Infantry, v(8, 11)),
            s.add_unit(P1, UnitKind::Infantry, v(9, 10)),
        ]
    }

    fn cast(owner: PlayerId, unit: EntityId, target: Vec2) -> Command {
        Command::UseAbility {
            owner,
            unit,
            target,
        }
    }

    #[test]
    fn a_depth_helicopter_emp_stuns_a_clump() {
        let mut s = depth_arena();
        // Distance 5 to the clump centre: inside EMP range (5).
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(3, 10));
        let foes = clump(&mut s);
        s.step(&[cast(P0, heli, v(8, 10))]);
        for id in foes {
            assert!(
                s.entities[id.0 as usize].stun_ticks > 0,
                "{id:?} not stunned"
            );
        }
        assert!(s.entities[heli.0 as usize].ability_cd > 0);
        assert!(s.depth_ability_allowed(P0, AbilityKind::EmpBurst));
        assert!(s.depth_ability_allowed(P0, AbilityKind::NaniteField));
        assert_eq!(s.depth_ability_cooldown(P0, 600), 600);
    }

    #[test]
    fn a_depth_barrage_needs_precision_manufacturing() {
        let mut s = depth_arena();
        let tank = s.add_unit(P0, UnitKind::Tank, v(3, 10));
        let foes = clump(&mut s);
        let full = UnitKind::Infantry.stats().max_hp;
        assert!(!s.depth_ability_allowed(P0, AbilityKind::Barrage));
        s.step(&[cast(P0, tank, v(8, 10))]);
        for id in foes {
            assert_eq!(s.entities[id.0 as usize].hp, full, "barrage before tech 6");
        }
        assert_eq!(s.entities[tank.0 as usize].ability_cd, 0);
        s.civs[0].researched_techs.set(6);
        assert!(s.depth_ability_allowed(P0, AbilityKind::Barrage));
        s.step(&[cast(P0, tank, v(8, 10))]);
        for id in foes {
            assert_eq!(
                s.entities[id.0 as usize].hp,
                full - Fixed::from_int(16),
                "the volley lands once tech 6 is researched"
            );
        }
        assert!(s.entities[tank.0 as usize].ability_cd > 0);
    }

    #[test]
    fn earthfront_without_depth_still_refuses_abilities() {
        for build in [survival, kestrel_reach_classic] {
            let mut s = build(3);
            let heli = s.add_unit(P0, UnitKind::Helicopter, v(3, 10));
            let foes = clump(&mut s);
            s.civs[0].researched_techs.set(6);
            s.step(&[cast(P0, heli, v(8, 10))]);
            for id in foes {
                assert_eq!(s.entities[id.0 as usize].stun_ticks, 0);
            }
            assert_eq!(s.entities[heli.0 as usize].ability_cd, 0);
        }
    }

    /// A finished `VehicleFactory` for `P0` with money to spare.
    fn factory_arena(depth: bool) -> (Sim, EntityId) {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        let factory = s.add_building(P0, BuildingKind::VehicleFactory, 10, 10);
        s.civs[0].money = Fixed::from_int(5000);
        (s, factory)
    }

    fn train_capital(s: &mut Sim, factory: EntityId) -> bool {
        s.step(&[Command::Train {
            owner: P0,
            barracks: factory,
            kind: UnitKind::Capital,
        }]);
        s.entities[factory.0 as usize]
            .build_queue
            .contains(&UnitKind::Capital)
    }

    #[test]
    fn the_capital_trains_at_a_vehicle_factory_after_tech_7_under_depth_only() {
        let (mut s, factory) = factory_arena(true);
        assert!(!train_capital(&mut s, factory), "era 0 trained a Capital");
        s.civs[0].researched_techs.set(7);
        s.unlock_earthfront_tech(0, 7);
        assert_eq!(s.player_era(P0), 1);
        assert!(s.unit_unlocked(P0, UnitKind::Capital));
        let before = s.money(P0);
        assert!(train_capital(&mut s, factory), "era 1 refused the Capital");
        assert_eq!(before - s.money(P0), s.unit_cost(UnitKind::Capital));
        // Survival-style Earthfront (no depth): tech 7 still gives era 1, and
        // even with the Capital unlocked by hand the era 3 rule refuses it.
        let (mut e, factory) = factory_arena(false);
        e.civs[0].researched_techs.set(7);
        e.unlock_earthfront_tech(0, 7);
        assert_eq!(e.player_era(P0), 1);
        assert!(!e.unit_unlocked(P0, UnitKind::Capital));
        e.civs[0].unlocked_units |= 1 << UnitKind::Capital.index();
        assert!(!train_capital(&mut e, factory), "the era 3 rule was lifted");
    }

    fn upgrade(owner: PlayerId, track: u8) -> Command {
        Command::Ascend { owner, track }
    }

    #[test]
    fn upgrades_cost_money_cap_per_era_and_never_sell_the_forge() {
        let mut s = depth_arena();
        s.civs[0].money = Fixed::from_int(100_000);
        assert_eq!(s.upgrade_levels(P0), [0, 0, 0]);
        assert_eq!(s.upgrade_cost(P0, 3), None, "forge on sale");
        let money = s.money(P0);
        s.step(&[upgrade(P0, 3)]);
        assert_eq!(s.money(P0), money, "forge charged");
        assert_eq!(s.doctrine_level(P0, 3), 0, "forge bought");
        // Era 0: three levels per track at 150, 250, 350.
        for (level, cost) in [(0u16, 150), (1, 250), (2, 350)] {
            assert_eq!(s.upgrade_levels(P0)[0], level);
            assert_eq!(s.upgrade_cost(P0, 0), Some(Fixed::from_int(cost)));
            let before = s.money(P0);
            s.step(&[upgrade(P0, 0)]);
            assert_eq!(before - s.money(P0), Fixed::from_int(cost));
        }
        assert_eq!(s.upgrade_cost(P0, 0), None, "era 0 cap is 3");
        let capped = s.money(P0);
        s.step(&[upgrade(P0, 0)]);
        assert_eq!(s.upgrade_levels(P0), [3, 0, 0]);
        assert_eq!(s.money(P0), capped);
        // Era 1 raises the cap to 6.
        s.civs[0].era = 1;
        for cost in [450, 550, 650] {
            assert_eq!(s.upgrade_cost(P0, 0), Some(Fixed::from_int(cost)));
            s.step(&[upgrade(P0, 0)]);
        }
        assert_eq!(s.upgrade_levels(P0), [6, 0, 0]);
        assert_eq!(s.upgrade_cost(P0, 0), None, "era 1 cap is 6");
        s.step(&[upgrade(P0, 0)]);
        assert_eq!(s.upgrade_levels(P0), [6, 0, 0]);
        // Too poor: refused, nothing spent. A free level skips the price.
        s.civs[0].money = Fixed::from_int(100);
        s.step(&[upgrade(P0, 1)]);
        assert_eq!(s.upgrade_levels(P0), [6, 0, 0]);
        assert_eq!(s.money(P0), Fixed::from_int(100));
        s.apply_depth_upgrade(P0, 1, true);
        assert_eq!(s.upgrade_levels(P0), [6, 1, 0]);
        assert_eq!(s.money(P0), Fixed::from_int(100));
        s.apply_depth_upgrade(P0, 3, true);
        assert_eq!(s.doctrine_level(P0, 3), 0, "a free forge level");
    }

    #[test]
    fn earthfront_without_depth_still_refuses_ascend() {
        for build in [survival, kestrel_reach_classic] {
            let mut s = build(3);
            s.civs[0].money = Fixed::from_int(100_000);
            s.step(&[upgrade(P0, 0), upgrade(P0, 3)]);
            assert_eq!(s.doctrine_level(P0, 0), 0);
            assert_eq!(s.doctrine_level(P0, 3), 0);
            assert_eq!(s.upgrade_cost(P0, 0), None);
        }
    }

    #[test]
    fn vitality_grants_shields_under_depth_only() {
        let mut s = depth_arena();
        s.apply_depth_upgrade(P0, 2, true);
        let rifle = s.add_unit(P0, UnitKind::Infantry, v(5, 5));
        assert_eq!(s.shield_max(P0), Fixed::from_int(8));
        assert_eq!(s.entities[rifle.0 as usize].shield, Fixed::from_int(8));
        assert_eq!(s.shield_max(P1), Fixed::ZERO);
        // Without depth the Earthfront shield stays zero whatever the level.
        let mut e = survival(3);
        e.civs[0].doctrine_levels[2] = 2;
        assert_eq!(e.shield_max(P0), Fixed::ZERO);
    }

    /// [`duel`] with `P0`'s upgrade levels (weapons, armour, vitality) and
    /// `P1`'s bought for free first.
    fn upgraded_duel(a: [u16; 3], b: [u16; 3], n: usize) -> Duel {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        s.enable_depth();
        for (owner, levels) in [(P0, a), (P1, b)] {
            s.civs[usize::from(owner.0)].era = 1;
            for (track, &n) in levels.iter().enumerate() {
                for _ in 0..n {
                    s.apply_depth_upgrade(owner, u8::try_from(track).unwrap(), true);
                }
            }
        }
        duel_in(s, &[(UnitKind::Infantry, n)], &[(UnitKind::Infantry, n)])
    }

    #[test]
    fn one_weapons_upgrade_wins_the_rifle_duel() {
        let rows: [([u16; 3], [u16; 3]); 9] = [
            ([0, 0, 0], [0, 0, 0]),
            ([1, 0, 0], [0, 0, 0]),
            ([0, 0, 0], [1, 0, 0]),
            ([2, 0, 0], [0, 0, 0]),
            ([3, 0, 0], [0, 0, 0]),
            ([0, 1, 0], [0, 0, 0]),
            ([0, 3, 0], [0, 0, 0]),
            ([0, 0, 1], [0, 0, 0]),
            ([0, 0, 3], [0, 0, 0]),
        ];
        std::eprintln!("6 rifles vs 6 rifles, levels [weapons, armour, vitality]");
        for (a, b) in rows {
            let d = upgraded_duel(a, b, 6);
            std::eprintln!(
                "P0 {a:?} vs P1 {b:?}: left {} vs {}, ticks {}",
                d.a_left,
                d.b_left,
                d.ticks
            );
        }
        let up = upgraded_duel([1, 0, 0], [0, 0, 0], 6);
        assert!(up.b_left == 0 && up.a_left >= 2, "{up:?}");
        // Mirrored, so the side (P0 or P1, x 14 or x 19) is not the cause.
        let down = upgraded_duel([0, 0, 0], [1, 0, 0], 6);
        assert!(down.a_left == 0 && down.b_left >= 2, "{down:?}");
    }

    #[test]
    fn the_depth_ai_waits_for_tech_6_before_a_barrage() {
        let mut s = depth_arena();
        s.add_building(P0, BuildingKind::CommandCenter, 2, 30);
        s.add_unit(P0, UnitKind::Tank, v(3, 10));
        clump(&mut s);
        let casts = |s: &Sim| {
            s.ai_commands(P0)
                .iter()
                .filter(|c| matches!(c, Command::UseAbility { .. }))
                .count()
        };
        assert_eq!(casts(&s), 0, "barrage cast before tech 6");
        s.civs[0].researched_techs.set(6);
        assert_eq!(casts(&s), 1);
        // Without depth the Earthfront AI casts nothing.
        let mut e = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        e.enable_earthfront();
        e.add_building(P0, BuildingKind::CommandCenter, 2, 30);
        e.add_unit(P0, UnitKind::Tank, v(3, 10));
        clump(&mut e);
        e.civs[0].researched_techs.set(6);
        assert!(!e
            .ai_commands(P0)
            .iter()
            .any(|c| matches!(c, Command::UseAbility { .. })));
    }

    /// The defended Kestrel playtest (the playtest AI on `P0`, host commands
    /// for the aliens) for 20,000 fixed steps: abilities cast and accepted
    /// per side, upgrade levels bought, and the outcome.
    fn ability_playtest(seed: u64) -> ([u32; 2], [[u16; 3]; 2], Option<PlayerId>, u64) {
        let mut s = kestrel_reach(seed);
        let mut casts = [0u32; 2];
        for _ in 0..20_000 {
            let mut c = s.ai_commands(P0);
            c.extend(Scenario::KestrelReach.host_commands(&s));
            let casters: Vec<(usize, usize)> = c
                .iter()
                .filter_map(|c| match *c {
                    Command::UseAbility { owner, unit, .. } => {
                        Some((usize::from(owner.0), unit.0 as usize))
                    }
                    _ => None,
                })
                .collect();
            s.step(&c);
            for (side, unit) in casters {
                if s.entities[unit].ability_cd > 0 {
                    casts[side] += 1;
                }
            }
        }
        (
            casts,
            [s.upgrade_levels(P0), s.upgrade_levels(P1)],
            s.winner(),
            s.tick(),
        )
    }

    #[test]
    fn the_depth_ai_casts_abilities_and_buys_upgrades_in_a_kestrel_playtest() {
        let (casts, levels, winner, tick) = ability_playtest(3);
        std::eprintln!(
            "casts P0 {} P1 {}; upgrades P0 {:?} P1 {:?}; winner {winner:?} at {tick}",
            casts[0],
            casts[1],
            levels[0],
            levels[1]
        );
        assert!(casts[0] + casts[1] >= 1, "no ability was cast");
        assert!(levels[0].iter().sum::<u16>() >= 1, "no upgrade was bought");
    }

    // ---------------------------------------------------------------- Task 18

    /// The first tile `owner` may build on (row-major), as the bridge's
    /// construction zone reports it.
    fn first_build_tile(s: &Sim, owner: PlayerId) -> (u16, u16) {
        for y in 0..s.map().height() {
            for x in 0..s.map().width() {
                if s.construction_allowed_at(owner, x, y) {
                    return (x, y);
                }
            }
        }
        panic!("no buildable tile");
    }

    fn refineries(s: &Sim, owner: PlayerId) -> Vec<EntityId> {
        s.views()
            .into_iter()
            .filter(|v| {
                v.owner == owner
                    && matches!(v.kind, EntityKindView::Building(BuildingKind::Refinery))
            })
            .map(|v| v.id)
            .collect()
    }

    #[test]
    fn each_refinery_costs_fifty_more_and_selling_one_lowers_the_next_price() {
        let mut s = kestrel_reach(3);
        let base = s.building_cost(BuildingKind::Refinery);
        let step = Fixed::from_int(50);
        // Kestrel opens with one refinery, so the next one is the second.
        assert_eq!(refineries(&s, P0).len(), 1);
        assert_eq!(
            s.depth_building_cost(P0, BuildingKind::Refinery),
            base + step
        );
        // Other kinds and the other side's count are unaffected.
        assert_eq!(
            s.depth_building_cost(P0, BuildingKind::Barracks),
            s.building_cost(BuildingKind::Barracks)
        );
        s.grant_money(P0, Fixed::from_int(2000));
        let (x, y) = first_build_tile(&s, P0);
        let build = [Command::Build {
            owner: P0,
            kind: BuildingKind::Refinery,
            x,
            y,
        }];
        assert_eq!(
            spent(&mut s, &build),
            base + step,
            "the second refinery costs base + 50"
        );
        assert_eq!(
            refineries(&s, P0).len(),
            2,
            "the second refinery was not placed"
        );
        // Under construction counts: the third is base + 100.
        assert_eq!(
            s.depth_building_cost(P0, BuildingKind::Refinery),
            base + step + step
        );
        let (x, y) = first_build_tile(&s, P0);
        let build = [Command::Build {
            owner: P0,
            kind: BuildingKind::Refinery,
            x,
            y,
        }];
        assert_eq!(
            spent(&mut s, &build),
            base + step + step,
            "the third costs base + 100"
        );
        assert_eq!(refineries(&s, P0).len(), 3);
        // Selling one lowers the next price by 50 again.
        let sold = refineries(&s, P0)[2];
        s.step(&[Command::Sell {
            owner: P0,
            building: sold,
        }]);
        assert_eq!(refineries(&s, P0).len(), 2);
        assert_eq!(
            s.depth_building_cost(P0, BuildingKind::Refinery),
            base + step + step
        );
        // A short purse is refused at the escalated price.
        s.civs[0].money = base + step;
        let (x, y) = first_build_tile(&s, P0);
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::Refinery,
            x,
            y,
        }]);
        assert_eq!(
            refineries(&s, P0).len(),
            2,
            "built below the escalated price"
        );
        // Classic Kestrel (depth off) keeps the flat price.
        let classic = kestrel_reach_classic(3);
        assert_eq!(
            classic.depth_building_cost(P0, BuildingKind::Refinery),
            classic.building_cost(BuildingKind::Refinery)
        );
    }

    /// A damaged depth Command Center with `money` in the purse, in an arena.
    fn repair_arena(money: i32) -> (Sim, EntityId) {
        let mut s = depth_arena();
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 10, 10);
        s.entities[cc.0 as usize].hp = Fixed::from_int(400);
        s.grant_money(P0, Fixed::from_int(money));
        (s, cc)
    }

    /// Steps `s` with `cmds` and a clone of it with nothing; returns what the
    /// commands cost `P0` (the arena's own economy moves both alike).
    fn spent(s: &mut Sim, cmds: &[Command]) -> Fixed {
        let mut twin = s.clone();
        twin.step(&[]);
        s.step(cmds);
        twin.money(P0) - s.money(P0)
    }

    fn repair(building: EntityId) -> [Command; 1] {
        [Command::Repair {
            owner: P0,
            building,
        }]
    }

    #[test]
    fn a_depth_repair_heals_gradually_costs_at_least_25_and_has_a_cooldown() {
        let (mut s, cc) = repair_arena(1000);
        let max = s.balance.building(BuildingKind::CommandCenter).max_hp;
        let chunk = max / Fixed::from_int(5);
        let start = Fixed::from_int(400);
        // The Command Center costs nothing to build, so the floor applies.
        assert_eq!(
            spent(&mut s, &repair(cc)),
            Fixed::from_int(super::REPAIR_MIN_COST)
        );
        let hp = hp_of(&s, cc);
        assert!(hp > start, "nothing healed on the first tick");
        assert!(
            hp < start + chunk / Fixed::from_int(10),
            "healed at once: {hp:?}"
        );
        let mut last = hp;
        for _ in 1..super::REPAIR_TICKS {
            s.step(&[]);
            let now = hp_of(&s, cc);
            assert!(now >= last, "repair lost hp");
            last = now;
        }
        assert_eq!(hp_of(&s, cc), start + chunk, "max_hp / 5 over the job");
        s.step(&[]);
        assert_eq!(hp_of(&s, cc), start + chunk, "healed past the job");
        // On cooldown until 450 ticks after the order: refused, nothing spent.
        let mut steps = super::REPAIR_TICKS + 1;
        while steps < super::REPAIR_COOLDOWN {
            assert_eq!(
                spent(&mut s, &repair(cc)),
                Fixed::ZERO,
                "restarted at step {steps}"
            );
            steps += 1;
        }
        assert_eq!(hp_of(&s, cc), start + chunk);
        assert_eq!(
            spent(&mut s, &repair(cc)),
            Fixed::from_int(super::REPAIR_MIN_COST)
        );
        assert!(
            hp_of(&s, cc) > start + chunk,
            "no restart after the cooldown"
        );
        // Dearer buildings pay a tenth of their price.
        let mut a = depth_arena();
        let field = a.add_building(P0, BuildingKind::Airfield, 10, 10);
        let price = a.building_cost(BuildingKind::Airfield);
        a.entities[field.0 as usize].hp = Fixed::from_int(100);
        a.grant_money(P0, Fixed::from_int(1000));
        let floor = Fixed::from_int(super::REPAIR_MIN_COST);
        let tenth = price / Fixed::from_int(10);
        assert!(tenth > floor, "pick a dearer building for this check");
        assert_eq!(spent(&mut a, &repair(field)), tenth);
        // A short purse starts nothing.
        let (mut p, cc) = repair_arena(super::REPAIR_MIN_COST - 2);
        assert_eq!(spent(&mut p, &repair(cc)), Fixed::ZERO);
        assert_eq!(hp_of(&p, cc), start);
        assert_eq!(p.repair_cooldown(cc), Some(0));
    }

    #[test]
    fn a_repair_job_ends_cleanly_when_its_building_dies_or_is_sold() {
        for sell in [false, true] {
            let mut s = depth_arena();
            let lab = s.add_building(P0, BuildingKind::ResearchLab, 10, 10);
            s.entities[lab.0 as usize].hp = Fixed::from_int(50);
            s.grant_money(P0, Fixed::from_int(1000));
            s.step(&[Command::Repair {
                owner: P0,
                building: lab,
            }]);
            assert!(s.entities[lab.0 as usize].dp.repair_ticks > 0);
            s.step(&[]);
            if sell {
                s.step(&[Command::Sell {
                    owner: P0,
                    building: lab,
                }]);
            } else {
                s.entities[lab.0 as usize].hp = Fixed::ZERO;
                s.step(&[]);
            }
            let e = &s.entities[lab.0 as usize];
            assert!(!e.alive);
            assert_eq!((e.dp.repair_ticks, e.dp.repair_cd), (0, 0), "job leaked");
            assert_eq!(s.repair_cooldown(lab), None);
            for _ in 0..200 {
                s.step(&[]);
            }
            // The slot is reused by a fresh building: no inherited job.
            let next = s.add_building(P0, BuildingKind::Barracks, 12, 12);
            assert_eq!(next, lab, "slot was not reused");
            let full = s.entities[next.0 as usize].hp;
            s.step(&[]);
            assert_eq!(s.entities[next.0 as usize].hp, full);
            assert_eq!(s.repair_cooldown(next), Some(0));
        }
    }

    #[test]
    fn survival_and_classic_repair_still_heal_a_fifth_at_once() {
        // Earthfront without depth (Survival's rules): cost max(price/10, 5),
        // max_hp / 5 in one tick, no cooldown.
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 10, 10);
        s.entities[cc.0 as usize].hp = Fixed::from_int(400);
        s.grant_money(P0, Fixed::from_int(100));
        let chunk = s.balance.building(BuildingKind::CommandCenter).max_hp / Fixed::from_int(5);
        assert_eq!(spent(&mut s, &repair(cc)), Fixed::from_int(5));
        assert_eq!(hp_of(&s, cc), Fixed::from_int(400) + chunk);
        assert_eq!(spent(&mut s, &repair(cc)), Fixed::from_int(5));
        assert_eq!(hp_of(&s, cc), Fixed::from_int(400) + chunk + chunk);
        assert_eq!(s.repair_cooldown(cc), None, "no depth state without depth");
        assert!(!survival(7).is_depth());
    }

    #[test]
    fn the_depth_ai_spends_surplus_on_extra_refineries_up_to_its_cap() {
        let mut s = kestrel_reach(3);
        let base = s.command_center_pos(P0).unwrap();
        let surplus = |s: &Sim, budget: i32, built: bool| {
            let mut c = Vec::new();
            s.earthfront_ai_surplus(P0, base, Fixed::from_int(budget), built, &mut c);
            c
        };
        assert!(surplus(&s, super::AI_SURPLUS - 1, false).is_empty());
        let c = surplus(&s, super::AI_SURPLUS, false);
        assert!(
            matches!(
                c.as_slice(),
                [Command::Build {
                    kind: BuildingKind::Refinery,
                    ..
                }]
            ),
            "{c:?}"
        );
        assert!(surplus(&s, 5000, true).is_empty(), "two builds in one pass");
        // A refinery under construction waits for the next pass.
        s.grant_money(P0, Fixed::from_int(5000));
        s.step(&c);
        assert_eq!(refineries(&s, P0).len(), 2);
        assert!(
            surplus(&s, 5000, false).is_empty(),
            "a second site while one builds"
        );
        // At the cap nothing more is bought, whatever the purse.
        let mut full = kestrel_reach(3);
        for _ in 0..3 {
            let (x, y) = first_build_tile(&full, P0);
            full.add_building(P0, BuildingKind::Refinery, x, y);
        }
        assert_eq!(refineries(&full, P0).len(), super::AI_SURPLUS_REFINERIES);
        let mut c = Vec::new();
        full.earthfront_ai_surplus(P0, base, Fixed::from_int(9000), false, &mut c);
        assert!(c.is_empty(), "{c:?}");
    }

    /// `(tick, money)` every 1800 steps, refineries, Upgrades levels, winner.
    type BankedCurve = (Vec<(u64, i64)>, usize, [u16; 3], Option<PlayerId>);

    /// The defended Kestrel playtest for 18,000 fixed steps (10:00 at 30 Hz):
    /// `P0`'s money every 1800 ticks, its refinery count and Upgrades levels.
    fn banked_credits_curve(seed: u64) -> BankedCurve {
        let mut s = kestrel_reach(seed);
        let mut curve = Vec::new();
        for step in 1..=18_000u64 {
            let mut c = s.ai_commands(P0);
            c.extend(Scenario::KestrelReach.host_commands(&s));
            s.step(&c);
            if step % 1800 == 0 {
                curve.push((s.tick(), s.money(P0).to_int_floor()));
            }
        }
        (
            curve,
            refineries(&s, P0).len(),
            s.upgrade_levels(P0),
            s.winner(),
        )
    }

    #[test]
    fn banked_credits_at_ten_minutes_stay_under_2500() {
        let (curve, refs, levels, winner) = banked_credits_curve(3);
        std::eprintln!(
            "banked credits curve {curve:?}; refineries {refs}; upgrades {levels:?}; winner {winner:?}"
        );
        // A match decided before 18,000 stops its tick: the last entry is then
        // the purse the playtest AI ended with.
        let &(tick, money) = curve.last().unwrap();
        std::eprintln!("money(P0) at tick {tick}: {money}");
        assert!(money < 2500, "P0 banks {money} at tick {tick}");
        assert!(refs <= super::AI_SURPLUS_REFINERIES, "{refs} refineries");
    }

    // ---------------------------------------------------------------- Task 19

    #[test]
    fn doctrine_order_differs_across_seeds_and_repeats_per_seed() {
        let orders: Vec<[u8; 5]> = (1..=8)
            .map(|seed| kestrel_reach(seed).dg.doctrine_order)
            .collect();
        for order in &orders {
            let mut sorted = *order;
            sorted.sort_unstable();
            assert_eq!(sorted, [0, 1, 2, 3, 4], "not a permutation: {order:?}");
        }
        let mut distinct = orders.clone();
        distinct.sort_unstable();
        distinct.dedup();
        assert!(distinct.len() >= 3, "seeds 1..8 gave {orders:?}");
        for seed in [1, 3, 2026] {
            assert_eq!(
                kestrel_reach(seed).dg.doctrine_order,
                kestrel_reach(seed).dg.doctrine_order
            );
        }
        // The draws are the sim's first real ones, depth only: the classic and
        // Survival worlds never draw (their rng state is the seed).
        assert_eq!(kestrel_reach_classic(3).dg.doctrine_order, [0; 5]);
        assert_eq!(kestrel_reach_classic(3).rng.current_state(), 3);
        assert_ne!(kestrel_reach(3).rng.current_state(), 3);
        assert_eq!(survival(3).rng.current_state(), 3);
    }

    #[test]
    fn the_wave_table_spot_checks() {
        use super::depth_wave_kind;
        use UnitKind::{AntiArmor, Capital, Helicopter, Infantry, Tank};
        let wave = |w: u32, budget: u32, d: u8| -> Vec<UnitKind> {
            (0..budget)
                .map(|i| depth_wave_kind(w, i, budget, d))
                .collect()
        };
        // Doctrines 0, 3 and 4 never shape waves 1 to 4 (1 and 2 do only as
        // the defender overrides, see `depth_wave_doctrine`).
        for d in [0, 3, 4] {
            assert!(wave(0, 10, d).iter().all(|&k| k == Infantry), "{d}");
            let w2 = wave(1, 12, d);
            assert!(w2.iter().all(|&k| matches!(k, Infantry | Tank)), "{w2:?}");
            assert_eq!(w2.iter().filter(|&&k| k == Tank).count(), 3, "{w2:?}");
            let w3 = wave(2, 14, d);
            assert!(
                w3.contains(&AntiArmor) && !w3.contains(&Helicopter),
                "{w3:?}"
            );
        }
        for d in 0..5 {
            assert!(wave(3, 16, d).contains(&Helicopter), "wave 4, doctrine {d}");
            assert_eq!(
                wave(5, 20, d)[..3],
                [Capital, Tank, Tank],
                "wave 6, doctrine {d}"
            );
            // Waves after 10 repeat wave 10's mix.
            assert_eq!(wave(12, 28, d), wave(9, 28, d));
            assert_eq!(wave(40, 28, d), wave(9, 28, d));
        }
        // Waves 5+ follow the doctrine.
        let w5 = |d| wave(4, 18, d);
        assert!(w5(1).iter().step_by(3).all(|&k| k == AntiArmor));
        assert_eq!(w5(2)[..5], [Capital, Tank, Tank, Tank, Tank]);
        assert!(w5(3).iter().step_by(4).all(|&k| k == Helicopter));
        assert!(w5(4).iter().all(|&k| matches!(k, Infantry | Tank)));
        assert!(w5(4).iter().step_by(3).all(|&k| k == Tank));
        assert_ne!(w5(0), w5(1));
        // The siege lead (Task 16) answers walls from wave one, without a
        // Capital before wave 5.
        let siege = wave(0, 10, 2);
        assert_eq!(siege[..3], [Tank, Tank, Tank]);
        assert!(siege[3..].iter().all(|&k| k == Infantry), "{siege:?}");
    }

    #[test]
    fn the_wave_doctrine_follows_the_seeded_order_and_the_defender_overrides() {
        let s = kestrel_reach(3);
        let order = s.dg.doctrine_order;
        for w in 4..15 {
            assert_eq!(s.depth_wave_doctrine(w, 0, 0), order[(w % 5) as usize]);
        }
        for w in 0..4 {
            let seeded = order[(w % 5) as usize];
            let want = if matches!(seeded, 1 | 2) { 0 } else { seeded };
            assert_eq!(s.depth_wave_doctrine(w, 2, 3), want, "wave {}", w + 1);
        }
        for w in 0..12 {
            assert_eq!(s.depth_wave_doctrine(w, 3, 0), 2);
            assert_eq!(s.depth_wave_doctrine(w, 3, 9), 2);
            assert_eq!(s.depth_wave_doctrine(w, 2, 4), 1);
        }
    }

    #[test]
    fn the_expedition_size_grows_to_its_cap_plus_the_relays() {
        let s = kestrel_reach(3);
        assert_eq!(s.alien_relay_count(P1, true), 2);
        assert_eq!(s.depth_expedition_size(0), 10);
        assert_eq!(s.depth_expedition_size(4), 18);
        assert_eq!(s.depth_expedition_size(9), 28);
        assert_eq!(s.depth_expedition_size(30), 28);
        assert_eq!(s.next_expedition_size(), s.depth_expedition_size(0));
    }

    /// Task 20: the preset's percent scales the table size (rounded down),
    /// before the relays add theirs (2 relays on seed 3: +4).
    #[test]
    fn the_preset_scales_the_expedition_before_the_relays() {
        for (d, first, fifth, capped) in [
            (Difficulty::Easy, 4 + 4, 10 + 4, 18 + 4),
            (Difficulty::Normal, 10, 18, 28),
            (Difficulty::Hard, 7 + 4, 17 + 4, 30 + 4),
        ] {
            let s = kestrel_reach_with(3, MatchOptions { difficulty: d });
            assert_eq!(s.depth_expedition_size(0), first, "{d:?}");
            assert_eq!(s.depth_expedition_size(4), fifth, "{d:?}");
            assert_eq!(s.depth_expedition_size(9), capped, "{d:?}");
            assert_eq!(s.depth_expedition_size(30), capped, "{d:?}");
        }
    }

    /// Task 20 (the Task 19 carry-over): the waves' attacker buys no Upgrades
    /// level before wave one has spawned (an upgraded probe alone used to
    /// take an undefended base at t=4121); it buys from wave one on, and the
    /// human-side AI is never held back.
    #[test]
    fn the_alien_ai_buys_upgrades_only_once_wave_one_has_spawned() {
        let mut s = kestrel_reach(3);
        while s.waves_survived() == 0 && s.winner().is_none() && s.tick() < 6000 {
            let c = Scenario::KestrelReach.host_commands(&s);
            assert!(
                !c.iter()
                    .any(|c| matches!(c, Command::Ascend { owner, .. } if *owner == P1)),
                "alien Upgrades order before wave one at t={}",
                s.tick()
            );
            s.step(&c);
        }
        assert_eq!(s.waves_survived(), 1, "wave one never came");
        assert_eq!(s.upgrade_levels(P1), [0, 0, 0]);
        let mut bought = false;
        for _ in 0..3000 {
            let c = Scenario::KestrelReach.host_commands(&s);
            bought |= c
                .iter()
                .any(|c| matches!(c, Command::Ascend { owner, .. } if *owner == P1));
            s.step(&c);
        }
        assert!(bought, "the alien never bought a level after wave one");
        // The human-side AI buys before any wave when it has the money.
        let mut s = kestrel_reach(3);
        let mut human = false;
        for _ in 0..4400 {
            let mut c = s.ai_commands(P0);
            human |= c
                .iter()
                .any(|c| matches!(c, Command::Ascend { owner, .. } if *owner == P0));
            c.extend(Scenario::KestrelReach.host_commands(&s));
            s.step(&c);
        }
        assert!(human, "the playtest AI bought no level before wave one");
        // Classic rules never reach this branch: no depth, no alien orders
        // before wave one at all.
        assert!(Scenario::KestrelReach
            .host_commands(&kestrel_reach_classic(3))
            .is_empty());
    }

    #[test]
    fn waves_cleared_counts_a_wave_once_its_last_unit_dies() {
        let mut s = kestrel_reach(3);
        for _ in 0..4600 {
            if s.waves_survived() == 1 {
                break;
            }
            s.step(&[]);
        }
        assert_eq!(s.waves_survived(), 1, "wave one never came");
        assert_eq!(s.waves_cleared(), 0);
        let wave: Vec<usize> = (0..s.entities.len())
            .filter(|&i| s.entities[i].alive && s.entities[i].dp.wave == 1)
            .collect();
        assert_eq!(wave.len(), 10, "wave one is 6 + 2 per relay");
        assert!(s
            .entities
            .iter()
            .all(|e| e.dp.wave <= 1 && (e.dp.wave == 0 || e.owner == P1)));
        let (last, rest) = wave.split_last().unwrap();
        for &i in rest {
            s.entities[i].hp = Fixed::ZERO;
        }
        s.step(&[]);
        assert_eq!(s.waves_cleared(), 0, "one unit of wave one still lives");
        s.entities[*last].hp = Fixed::ZERO;
        s.step(&[]);
        assert_eq!(s.waves_cleared(), 1);
        // Classic Kestrel tags nothing and clears nothing.
        let mut c = kestrel_reach_classic(3);
        for _ in 0..4600 {
            c.step(&[]);
        }
        assert_eq!(c.waves_survived(), 1);
        assert!(c.entities.iter().all(|e| e.dp.wave == 0));
        assert_eq!(c.waves_cleared(), 0);
    }

    #[test]
    fn the_alien_ai_runs_from_tick_zero_and_leaves_the_probe_to_its_script() {
        use crate::game::scenario::{kestrel_probe_units, KESTREL_PROBE_STRIKE_TICK};
        let s = kestrel_reach(3);
        let c = Scenario::KestrelReach.host_commands(&s);
        assert!(
            c.iter()
                .any(|c| matches!(c, Command::Build { owner, .. } if *owner == P1)),
            "no alien AI order at tick 0: {c:?}"
        );
        assert!(Scenario::KestrelReach
            .host_commands(&kestrel_reach_classic(3))
            .is_empty());
        // Before wave one the probe squads take only their two scripted orders.
        let probe = kestrel_probe_units(&s);
        let mut s = s;
        let mut orders = 0;
        for _ in 0..4400 {
            let c = Scenario::KestrelReach.host_commands(&s);
            orders += c
                .iter()
                .filter(|c| {
                    matches!(c, Command::Move { unit, .. } | Command::AttackMove { unit, .. }
                        if probe.contains(unit))
                })
                .count();
            s.step(&c);
        }
        assert!(s.tick() > KESTREL_PROBE_STRIKE_TICK);
        assert_eq!(orders, 2 * probe.len());
    }

    /// An alien garrison of `n` idle rifles near its Command Center, at `tick`,
    /// with wave one already spawned (Task 20: no raid before it).
    fn raid_setup(n: u16, tick: u64) -> Sim {
        let mut s = kestrel_reach(3);
        for i in 0..n {
            s.add_unit(P1, UnitKind::Infantry, hex::center(33, 4 + i % 10));
        }
        s.tick = tick;
        s.wave_count = 1;
        s
    }

    /// The structure of `owner`'s enemy nearest `owner`'s base (ties by id).
    fn nearest_enemy_structure(s: &Sim, owner: PlayerId) -> Vec2 {
        let base = s.command_center_pos(owner).unwrap();
        s.views()
            .into_iter()
            .filter(|v| v.owner != owner && matches!(v.kind, EntityKindView::Building(_)))
            .min_by_key(|v| ((v.pos - base).length_squared().to_bits(), v.id.0))
            .unwrap()
            .pos
    }

    /// The alien AI's attack-moves at the human structure nearest its base.
    fn raid_orders(s: &Sim) -> Vec<(EntityId, Vec2)> {
        let target = nearest_enemy_structure(s, P1);
        s.ai_commands(P1)
            .into_iter()
            .filter_map(|c| match c {
                Command::AttackMove { unit, target, .. } => Some((unit, target)),
                _ => None,
            })
            .filter(|&(_, t)| t == target)
            .collect()
    }

    #[test]
    fn at_era_zero_the_alien_raids_with_half_its_idle_army_every_2700_ticks() {
        let s = raid_setup(4, super::RAID_PERIOD);
        assert!(s.supply_used(P1) >= super::RAID_SUPPLY);
        let idle: Vec<EntityId> = (0..s.entities.len())
            .filter(|&i| s.depth_raider(i, P1))
            .map(|i| EntityId(u32::try_from(i).unwrap()))
            .collect();
        let raid = raid_orders(&s);
        assert_eq!(raid.len(), idle.len() / 2, "{raid:?} of {idle:?}");
        // The lowest-index half, at the human structure nearest the alien base.
        let units: Vec<EntityId> = raid.iter().map(|&(u, _)| u).collect();
        assert_eq!(units, idle[..idle.len() / 2]);
        // Off the period, under the supply line, past era 0, for the
        // defender, and without depth there is no raid.
        assert!(raid_orders(&raid_setup(4, super::RAID_PERIOD + 30)).is_empty());
        assert!(raid_orders(&raid_setup(0, super::RAID_PERIOD)).is_empty());
        // Task 20: before wave one the alien never raids.
        let mut early = raid_setup(4, super::RAID_PERIOD);
        early.wave_count = 0;
        assert!(raid_orders(&early).is_empty());
        let mut late = raid_setup(4, super::RAID_PERIOD);
        late.civs[1].era = 1;
        assert!(raid_orders(&late).is_empty());
        let mut classic = kestrel_reach_classic(3);
        for i in 0..4 {
            classic.add_unit(P1, UnitKind::Infantry, hex::center(33, 4 + i));
        }
        classic.tick = super::RAID_PERIOD;
        assert!(raid_orders(&classic).is_empty());
        // The human playtest AI never raids.
        let mut human = raid_setup(0, super::RAID_PERIOD);
        for i in 0..14 {
            human.add_unit(P0, UnitKind::Infantry, hex::center(9, 4 + i % 10));
        }
        let alien_target = nearest_enemy_structure(&human, P0);
        assert!(!human
            .ai_commands(P0)
            .iter()
            .any(|c| matches!(c, Command::AttackMove { target, .. } if *target == alien_target)));
    }

    /// Wave by wave, the doctrine and the kinds `kestrel_reach(seed)` actually
    /// spawns, hosted as the bridge hosts it, when every wave is recorded and
    /// wiped out the tick it spawns (so the supply ceiling never trims a wave
    /// and no override fires) and the human Command Center cannot fall.
    fn spawned_waves(seed: u64, waves: u32) -> Vec<(u8, Vec<(UnitKind, usize)>)> {
        let mut s = kestrel_reach(seed);
        let cc = (0..s.entities.len())
            .find(|&i| {
                s.entities[i].owner == P0
                    && s.entities[i].kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .unwrap();
        let mut out = Vec::new();
        let mut recorded = 0;
        for _ in 0..(4500 + 5400 * waves) {
            s.entities[cc].hp = Fixed::from_int(1_000_000);
            if s.waves_survived() == waves {
                break;
            }
            let c = Scenario::KestrelReach.host_commands(&s);
            s.step(&c);
            if s.waves_survived() > recorded {
                recorded = s.waves_survived();
                let mut kinds: Vec<(UnitKind, usize)> = Vec::new();
                for e in s
                    .entities
                    .iter()
                    .filter(|e| e.alive && u32::from(e.dp.wave) == recorded)
                {
                    let Kind::Unit(k) = e.kind else { continue };
                    match kinds.iter_mut().find(|(kk, _)| *kk == k) {
                        Some((_, n)) => *n += 1,
                        None => kinds.push((k, 1)),
                    }
                }
                out.push((s.earthfront_wave_doctrine, kinds));
                for e in s.entities.iter_mut().filter(|e| e.dp.wave > 0) {
                    e.hp = Fixed::ZERO;
                }
            }
        }
        out
    }

    #[test]
    #[ignore = "table: cargo test --release -p rts-core --offline depth_wave_composition -- --ignored --nocapture"]
    fn depth_wave_composition() {
        std::eprintln!("doctrine order {:?}", kestrel_reach(3).dg.doctrine_order);
        for (w, (d, kinds)) in spawned_waves(3, 12).iter().enumerate() {
            std::eprintln!("wave {} doctrine {d}: {kinds:?}", w + 1);
        }
    }

    #[test]
    fn seed_three_spawns_flyers_at_wave_four_and_an_elite_wave_six() {
        let waves = spawned_waves(3, 6);
        assert_eq!(waves.len(), 6);
        let has = |w: usize, k: UnitKind| waves[w].1.iter().any(|&(kk, _)| kk == k);
        assert!(
            waves[0].1.iter().all(|&(k, _)| k == UnitKind::Infantry),
            "{waves:?}"
        );
        assert!((0..3).all(|w| !has(w, UnitKind::Helicopter)), "{waves:?}");
        assert!(has(3, UnitKind::Helicopter), "{waves:?}");
        assert!(has(5, UnitKind::Capital), "{waves:?}");
    }

    // ---- Task 21: the Core Node shield.

    /// Task 21: the waves' attacker's Command Center (the Core Node).
    fn core_of(s: &Sim) -> usize {
        (0..s.entities.len())
            .find(|&i| {
                s.entities[i].alive
                    && s.entities[i].owner == P1
                    && s.entities[i].kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .unwrap()
    }

    /// Task 21: clears the alien's units and turrets (its plants keep the
    /// relays powered), kills its relays unless `keep_relays`, sets the
    /// spawned wave count to `waves`, parks four human Tanks beside the Core
    /// Node with it as their forced target (depth only; with depth off they
    /// fire at it as the only thing in range) and runs 300 ticks. Returns the
    /// Core Node's (HP before, HP after, shielded before).
    fn fire_on_the_core(mut s: Sim, keep_relays: bool, waves: u32) -> (Fixed, Fixed, bool) {
        use super::super::earthfront::ObjectiveRole;
        let core = core_of(&s);
        for e in &mut s.entities {
            let relay = e.objective_role == ObjectiveRole::AlienRelay;
            let doomed = matches!(e.kind, Kind::Unit(_))
                || matches!(
                    e.kind,
                    Kind::Building(BuildingKind::GunTurret | BuildingKind::AaTurret)
                )
                || (relay && !keep_relays);
            if e.alive && e.owner == P1 && doomed {
                e.hp = Fixed::ZERO;
            }
        }
        s.step(&[]);
        s.wave_count = waves;
        let at = s.entities[core].pos;
        let tanks: Vec<EntityId> = (0..4)
            .map(|k| {
                s.add_unit(
                    P0,
                    UnitKind::Tank,
                    at + Vec2::new(Fixed::from_int(-2), Fixed::from_ratio(k - 2, 2)),
                )
            })
            .collect();
        let orders: Vec<Command> = tanks
            .iter()
            .map(|&unit| Command::AttackTarget {
                owner: P0,
                unit,
                target: EntityId(u32::try_from(core).unwrap()),
            })
            .collect();
        let before = s.entities[core].hp;
        let shielded = s.core_node_shielded();
        s.step(&orders);
        for _ in 0..300 {
            s.step(&[]);
        }
        (before, s.entities[core].hp, shielded)
    }

    #[test]
    fn the_core_node_takes_no_damage_while_a_relay_stands() {
        // Both relays up, no wave yet; both relays up after wave 6; no relay
        // but only five waves: every case keeps the Core Node whole.
        for (keep, waves) in [(true, 0), (true, 6), (false, 5)] {
            let (before, after, shielded) = fire_on_the_core(kestrel_reach(3), keep, waves);
            assert!(shielded, "relays {keep} waves {waves}");
            assert_eq!(before, after, "relays {keep} waves {waves}");
        }
        assert!(kestrel_reach(3).core_node_shielded());
    }

    #[test]
    fn the_core_node_is_damageable_once_both_relays_fall_and_wave_six_spawned() {
        let (before, after, shielded) = fire_on_the_core(kestrel_reach(3), false, 6);
        assert!(!shielded);
        assert!(after < before, "{before:?} -> {after:?}");
    }

    /// Task 21: a Barrage on the Core Node (alien units and turrets cleared,
    /// relays killed unless `keep_relays`, `waves` spawned): its HP before
    /// and after.
    fn barrage_the_core(keep_relays: bool, waves: u32) -> (Fixed, Fixed) {
        use super::super::earthfront::ObjectiveRole;
        let mut s = kestrel_reach(3);
        let core = core_of(&s);
        for e in &mut s.entities {
            let relay = e.objective_role == ObjectiveRole::AlienRelay;
            if e.alive
                && e.owner == P1
                && (matches!(e.kind, Kind::Unit(_)) || (relay && !keep_relays))
            {
                e.hp = Fixed::ZERO;
            }
        }
        s.step(&[]);
        s.wave_count = waves;
        s.civs[0].researched_techs.set(6);
        let at = s.entities[core].pos;
        let tank = s.add_unit(
            P0,
            UnitKind::Tank,
            at + Vec2::new(Fixed::from_int(-4), Fixed::ZERO),
        );
        s.entities[tank.0 as usize].ammunition = 0;
        let before = s.entities[core].hp;
        s.step(&[cast(P0, tank, at)]);
        assert!(
            s.entities[tank.0 as usize].ability_cd > 0,
            "the volley was cast"
        );
        (before, s.entities[core].hp)
    }

    #[test]
    fn a_barrage_spares_the_shielded_core_node_only() {
        let (before, after) = barrage_the_core(true, 6);
        assert_eq!(before, after);
        let (before, after) = barrage_the_core(false, 6);
        assert!(after < before, "{before:?} -> {after:?}");
    }

    /// Task 21: under depth the waves' attacker keeps a ten-supply garrison
    /// in every era (the classic target grows to 24 at era 1); the human
    /// side and every non-depth match keep the classic targets.
    #[test]
    fn the_alien_garrison_stays_at_ten_supply_in_era_one() {
        let mut s = kestrel_reach(3);
        assert_eq!(s.earthfront_army_target(P1), 10);
        assert_eq!(s.earthfront_army_target(P0), 10);
        s.civs[0].era = 1;
        s.civs[1].era = 1;
        assert_eq!(s.earthfront_army_target(P1), super::ALIEN_ARMY_TARGET);
        assert_eq!(s.earthfront_army_target(P0), 24);
        for build in [kestrel_reach_classic, survival] {
            let mut other = build(3);
            other.civs[1].era = 1;
            assert_eq!(other.earthfront_army_target(P1), 24);
        }
    }

    /// Task 21: the alien buys at most one Upgrades level per track for each
    /// spawned wave (none before wave one, as in Task 20), so its waves
    /// harden with the match instead of maxing out at era 1. The human side
    /// is not paced.
    #[test]
    fn the_alien_buys_at_most_one_upgrade_level_per_track_per_wave() {
        let mut s = kestrel_reach(3);
        let cc = (0..s.entities.len())
            .find(|&i| {
                s.entities[i].owner == P0
                    && s.entities[i].kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .unwrap();
        // A rich alien, so money never limits it.
        s.grant_money(P1, Fixed::from_int(50_000));
        let mut peak = [0_u16; 3];
        while s.waves_survived() < 3 && s.tick() < 20_000 {
            s.entities[cc].hp = Fixed::from_int(1_000_000);
            let c = Scenario::KestrelReach.host_commands(&s);
            s.step(&c);
            let levels = s.upgrade_levels(P1);
            for t in 0..3 {
                assert!(
                    u32::from(levels[t]) <= s.waves_survived(),
                    "t={} levels {levels:?} after {} waves",
                    s.tick(),
                    s.waves_survived()
                );
                peak[t] = peak[t].max(levels[t]);
            }
            if s.waves_survived() == 2 {
                assert!(s.depth_ai_may_upgrade(P1, 0) == (levels[0] < 2));
            }
        }
        assert_eq!(s.waves_survived(), 3);
        assert!(
            peak.iter().all(|&l| l >= 2),
            "the paced alien still buys: {peak:?}"
        );
        assert!(
            s.depth_ai_may_upgrade(P0, 0),
            "the human side is never paced"
        );
    }

    #[test]
    fn survival_and_classic_core_nodes_are_never_shielded() {
        for (build, seed) in [(survival as fn(u64) -> Sim, 7), (kestrel_reach_classic, 3)] {
            let s = build(seed);
            assert!(!s.core_node_shielded());
            let (before, after, shielded) = fire_on_the_core(s, true, 0);
            assert!(!shielded);
            assert!(after < before, "{before:?} -> {after:?}");
        }
        let mut lane = lane_defense(3);
        lane.step(&[]);
        assert!(!lane.core_node_shielded());
    }

    /// Task 22: the money value of entity `i` (its balance price).
    fn value_of(s: &Sim, i: usize) -> i64 {
        match s.entities[i].kind {
            Kind::Unit(u) => s.unit_cost(u).to_int_floor(),
            Kind::Building(b) => s.building_cost(b).to_int_floor(),
        }
    }

    /// Task 22: the first `n` living entities of `owner` that `keep` accepts.
    fn pick(s: &Sim, owner: PlayerId, n: usize, keep: fn(Kind) -> bool) -> Vec<usize> {
        (0..s.entities.len())
            .filter(|&i| {
                let e = &s.entities[i];
                e.alive && e.owner == owner && keep(e.kind)
            })
            .take(n)
            .collect()
    }

    const fn is_unit(k: Kind) -> bool {
        matches!(k, Kind::Unit(_))
    }

    fn is_spare_building(k: Kind) -> bool {
        matches!(k, Kind::Building(b) if b != BuildingKind::CommandCenter)
    }

    #[test]
    fn deaths_credit_destroyed_and_lost_value_by_owner_and_a_sale_is_no_loss() {
        let mut s = kestrel_reach(3);
        let aliens = pick(&s, P1, 3, is_unit);
        let humans = pick(&s, P0, 2, is_unit);
        assert_eq!((aliens.len(), humans.len()), (3, 2));
        let alien_value: i64 = aliens.iter().map(|&i| value_of(&s, i)).sum();
        let human_value: i64 = humans.iter().map(|&i| value_of(&s, i)).sum();
        assert!(alien_value > 0 && human_value > 0);
        assert_eq!((s.dg.destroyed, s.dg.lost), ([0, 0], [0, 0]));
        for &i in aliens.iter().chain(&humans) {
            s.entities[i].hp = Fixed::ZERO;
        }
        s.step(&[]);
        assert_eq!(s.dg.destroyed, [alien_value, human_value]);
        assert_eq!(s.dg.lost, [human_value, alien_value]);
        // A sold structure is refunded, not lost: nothing moves.
        let spare = pick(&s, P0, 2, is_spare_building);
        assert_eq!(spare.len(), 2);
        s.step(&[Command::Sell {
            owner: P0,
            building: EntityId(u32::try_from(spare[0]).unwrap()),
        }]);
        assert!(!s.entities[spare[0]].alive, "the sale went through");
        assert_eq!(s.dg.lost, [human_value, alien_value]);
        assert_eq!(s.dg.destroyed, [alien_value, human_value]);
        // A structure that falls counts its price.
        let price = value_of(&s, spare[1]);
        assert!(price > 0);
        s.entities[spare[1]].hp = Fixed::ZERO;
        s.step(&[]);
        assert_eq!(s.dg.lost, [human_value + price, alien_value]);
        assert_eq!(s.dg.destroyed, [alien_value, human_value + price]);
        // Survival and classic Kestrel keep no ledger.
        for build in [survival as fn(u64) -> Sim, kestrel_reach_classic] {
            let mut c = build(3);
            let mut units = pick(&c, P0, 1, is_unit);
            units.extend(pick(&c, P1, 1, is_unit));
            assert!(!units.is_empty());
            for &i in &units {
                c.entities[i].hp = Fixed::ZERO;
            }
            c.step(&[]);
            assert_eq!((c.dg.destroyed, c.dg.lost), ([0, 0], [0, 0]));
            assert!(c.depth_score().is_none());
        }
    }

    #[test]
    fn grades_follow_the_score_thresholds() {
        for (total, grade) in [
            (50_000, 'S'),
            (12_000, 'S'),
            (11_999, 'A'),
            (8_000, 'A'),
            (7_999, 'B'),
            (5_000, 'B'),
            (4_999, 'C'),
            (2_500, 'C'),
            (2_499, 'D'),
            (0, 'D'),
        ] {
            assert_eq!(super::depth_grade(total), grade, "{total}");
        }
    }

    #[test]
    fn the_difficulty_scales_the_score() {
        assert_eq!(
            [Difficulty::Easy, Difficulty::Normal, Difficulty::Hard].map(Difficulty::score_pct),
            [75, 100, 150]
        );
    }

    /// Task 22: `kestrel_reach_with(3, d)` with a crafted ledger: 4 waves
    /// cleared, 3000 destroyed and 1000 lost by the human.
    fn crafted(d: Difficulty) -> Sim {
        let mut s = kestrel_reach_with(3, MatchOptions { difficulty: d });
        s.dg.waves_cleared = 4;
        s.dg.destroyed = [3000, 700];
        s.dg.lost = [1000, 3000];
        s
    }

    #[test]
    fn the_score_adds_waves_destroyed_half_the_losses_and_the_difficulty() {
        let normal = crafted(Difficulty::Normal).depth_score().unwrap();
        // 4 x 500 + 3000 - 1000 / 2 = 4500.
        assert_eq!(
            normal,
            DepthScore {
                waves_held: 4,
                destroyed: 3000,
                lost: 1000,
                victory_bonus: 0,
                total: 4500,
                grade: 'C',
            }
        );
        let hard = crafted(Difficulty::Hard).depth_score().unwrap();
        assert_eq!((hard.total, hard.grade), (6750, 'B'), "Hard is x1.5");
        let easy = crafted(Difficulty::Easy).depth_score().unwrap();
        assert_eq!((easy.total, easy.grade), (3375, 'C'), "Easy is x0.75");
        // Heavy losses never push the score below zero.
        let mut broke = crafted(Difficulty::Hard);
        broke.dg.lost[0] = 20_000;
        let broke = broke.depth_score().unwrap();
        assert_eq!((broke.lost, broke.total, broke.grade), (20_000, 0, 'D'));
        // No score without depth.
        assert!(survival(7).depth_score().is_none());
        assert!(kestrel_reach_classic(3).depth_score().is_none());
        assert!(lane_defense(3).depth_score().is_none());
    }

    #[test]
    fn a_human_win_adds_a_tenth_of_the_ticks_left_before_45000() {
        let mut s = crafted(Difficulty::Normal);
        let core = pick(&s, P1, 1, |k| {
            k == Kind::Building(BuildingKind::CommandCenter)
        })[0];
        let core_value = value_of(&s, core);
        s.entities[core].hp = Fixed::ZERO;
        s.step(&[]);
        assert_eq!(s.winner(), Some(P0));
        let t = i64::try_from(s.tick()).unwrap();
        let won = s.depth_score().unwrap();
        assert_eq!(won.victory_bonus, (45_000 - t) / 10);
        assert_eq!(won.destroyed, 3000 + core_value);
        assert_eq!(
            won.total,
            4 * 500 + 3000 + core_value - 500 + (45_000 - t) / 10
        );
        // A decided match stops: the score holds on later steps.
        for _ in 0..30 {
            s.step(&[]);
        }
        assert_eq!(s.depth_score(), Some(won));
        // A human loss earns no bonus.
        let mut lost = crafted(Difficulty::Normal);
        let home = pick(&lost, P0, 1, |k| {
            k == Kind::Building(BuildingKind::CommandCenter)
        })[0];
        lost.entities[home].hp = Fixed::ZERO;
        lost.step(&[]);
        assert_eq!(lost.winner(), Some(P1));
        assert_eq!(lost.depth_score().unwrap().victory_bonus, 0);
        // A win after 45,000 ticks earns none either.
        let mut late = crafted(Difficulty::Normal);
        late.tick = 45_500;
        late.entities[core].hp = Fixed::ZERO;
        late.step(&[]);
        assert_eq!(late.winner(), Some(P0));
        assert_eq!(late.depth_score().unwrap().victory_bonus, 0);
    }

    #[test]
    fn the_score_ledger_is_hashed_under_depth_only() {
        let depth = kestrel_reach(3);
        let mut one = depth.clone();
        one.dg.destroyed[0] = 1;
        assert_ne!(depth.state_hash(), one.state_hash());
        let mut two = depth.clone();
        two.dg.lost[1] = 1;
        assert_ne!(depth.state_hash(), two.state_hash());
        let plain = survival(7);
        let mut ledger = plain.clone();
        ledger.dg.destroyed = [5, 6];
        ledger.dg.lost = [7, 8];
        assert_eq!(plain.state_hash(), ledger.state_hash());
    }
}
