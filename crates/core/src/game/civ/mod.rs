//! The autonomous-civilization layer.
//!
//! "Ascension" is a real-time autonomous civilization engine: the player sets
//! policy and conditions, and **colonies execute** — gather, build, train,
//! research, expand, and fight on their own, scaling from manual at birth to fully
//! automated at maturity. Everything a colony decides is emitted as a
//! [`Command`](crate::game::sim::Command) and flows through the same validated
//! `apply_command` channel the human and the legacy AI use, so the determinism /
//! lockstep / replay contract is untouched: a colony's decision function is a
//! **pure function of hashed state** (no `self.rng`, no floats, index-ordered),
//! exactly like [`Sim::ai_commands`](crate::game::sim::Sim::ai_commands).
//!
//! Milestones so far: M0 added the colony arena + the autonomy poles; M3 adds the
//! policy / intent model and the earned 1..=8 autonomy gradient (one command
//! category unlocked per level). Later milestones grow [`Colony`] with the civ
//! scalars, scoring, adoption, and LOD, and add the sector / empire hierarchy.

pub mod special;

use crate::fixed::Fixed;
use crate::game::sim::{EntityId, PlayerId};
use special::{Knowledge, SPECIAL_COUNT};

/// Stable handle for a colony.
///
/// An index into `Sim`'s colony arena; slots are recycled (LIFO) through the
/// colony free-list, mirroring the entity arena.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct ColonyId(pub u32);

/// Full autonomy — the colony runs itself entirely.
///
/// The "automated at maturity" pole and the maximum [`Colony::autonomy_level`].
pub const AUTONOMY_FULL: u8 = 9;

/// Consecutive qualifying ticks needed to earn one more autonomy level.
pub const AUTONOMY_HOLD_TICKS: u32 = 120;

/// Expansion stance — how aggressively a colony founds new colonies.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ExpansionIntent {
    /// Never expand.
    #[default]
    None = 0,
    /// Surface suggestions only; never act.
    SuggestOnly = 1,
    /// Auto-settle safe empty sites.
    AutoSafe = 2,
    /// Expand toward needed resources.
    AutoResource = 3,
    /// Expand toward strategic positions.
    AutoStrategic = 4,
    /// Expand aggressively.
    Aggressive = 5,
}

/// Economic emphasis.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum EconomicIntent {
    /// No special emphasis.
    #[default]
    Balanced = 0,
    /// Grow population / labour.
    Population = 1,
    /// Energy independence.
    Energy = 2,
    /// Money surplus.
    Money = 3,
    /// Research throughput.
    Research = 4,
    /// Military industry.
    Military = 5,
}

/// Military posture.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum MilitaryIntent {
    /// Defend only.
    #[default]
    DefensiveOnly = 0,
    /// Protect supply routes.
    ProtectRoutes = 1,
    /// Raid enemy resource sites.
    Raid = 2,
    /// Capture marked targets.
    Capture = 3,
    /// Full conquest.
    Conquest = 4,
    /// Strike back only when attacked.
    Retaliate = 5,
}

/// Research-branch emphasis.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ResearchIntent {
    /// Spread evenly.
    #[default]
    Balanced = 0,
    /// Energy branch.
    Energy = 1,
    /// Computation branch.
    Compute = 2,
    /// Weapons / military branch.
    Military = 3,
    /// Biology / civilization branch.
    Biology = 4,
    /// Propulsion branch.
    Propulsion = 5,
    /// Dark-sector branch.
    DarkSector = 6,
    /// Cosmic / gravity branch.
    Cosmic = 7,
}

/// How resources flow between colonies.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ResourcePolicy {
    /// Keep production local.
    #[default]
    LocalFirst = 0,
    /// Export surplus to the empire.
    ExportSurplus = 1,
    /// Empire needs come first.
    EmpirePriority = 2,
    /// Military supply comes first.
    MilitaryPriority = 3,
    /// Research supply comes first.
    ResearchPriority = 4,
    /// Emergency requisition.
    Emergency = 5,
}

/// What a colony builds first.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum BuildPolicy {
    /// Balanced build order.
    #[default]
    Balanced = 0,
    /// Economy buildings first.
    EconomyFirst = 1,
    /// Military buildings first.
    MilitaryFirst = 2,
    /// Power / housing infrastructure first.
    InfrastructureFirst = 3,
}

/// Export stance.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ExportIntent {
    /// Keep everything.
    #[default]
    Hold = 0,
    /// Export surplus.
    ExportSurplus = 1,
    /// Pull imports in.
    ImportPriority = 2,
}

/// A direct, one-shot override the player issues to a single colony, taking
/// precedence over its standing policy until cleared.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ColonyIntent {
    /// Follow standing policy (no override).
    #[default]
    Auto = 0,
    /// Prioritize expansion.
    Expand = 1,
    /// Prioritize defense.
    Fortify = 2,
    /// Prioritize production.
    Industrialize = 3,
    /// Prioritize research.
    Research = 4,
    /// Do nothing — freeze autonomous action.
    Hold = 5,
    /// Pull back / stop investing.
    Evacuate = 6,
}

/// One stance per policy axis. The player sets these; the colony executes them.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct ColonyPolicy {
    /// Expansion stance.
    pub expansion: ExpansionIntent,
    /// Economic emphasis.
    pub economic: EconomicIntent,
    /// Military posture.
    pub military: MilitaryIntent,
    /// Research emphasis.
    pub research: ResearchIntent,
    /// Resource-flow policy.
    pub resource: ResourcePolicy,
    /// Build-order policy.
    pub build: BuildPolicy,
    /// Export stance.
    pub export: ExportIntent,
}

impl ColonyPolicy {
    /// The seven axis discriminants, in a stable order, for state hashing.
    #[must_use]
    pub const fn discriminants(&self) -> [u8; 7] {
        [
            self.expansion as u8,
            self.economic as u8,
            self.military as u8,
            self.research as u8,
            self.resource as u8,
            self.build as u8,
            self.export as u8,
        ]
    }
}

/// The minimum autonomy level a [`Command`](crate::game::sim::Command) category
/// requires before a colony may emit it for itself. Mirrors the earn-gate ladder
/// in the module docs.
#[must_use]
pub const fn command_min_autonomy(command: &crate::game::sim::Command) -> u8 {
    use crate::game::sim::Command;
    match command {
        // maintenance/economy build
        Command::Build { .. } => 2,
        // research adoption
        Command::Research { .. } => 4,
        // training (defensive at 3, offensive folds in by 5)
        Command::Train { .. } => 5,
        // expansion
        Command::FoundBase { .. } => 6,
        // movement / initiative
        Command::Move { .. } | Command::UseAbility { .. } => 7,
        // institution-level spend
        Command::Ascend { .. } | Command::ChoosePerk { .. } => 8,
        // player→colony configuration commands are never colony-emitted.
        Command::SetColonyAutonomy { .. }
        | Command::SetColonyPolicy { .. }
        | Command::DirectColony { .. }
        | Command::SurveySpecial { .. } => u8::MAX,
    }
}

/// One autonomous colony.
#[derive(Clone, Debug)]
pub struct Colony {
    /// `false` once the colony is razed; the slot is then recycled.
    pub alive: bool,
    /// Owning civ/faction (a [`PlayerId`] for now; M6 generalizes to `Vec<Civ>`).
    pub owner: PlayerId,
    /// The Command Center entity this colony is seated on.
    pub seat: EntityId,
    /// Player-requested autonomy, `0..=9`. The *effective* level is capped by what
    /// the colony has [earned](Self::earned_autonomy).
    pub autonomy_level: u8,
    /// Consecutive qualifying ticks accumulated toward the next earned level.
    pub autonomy_progress: u32,
    /// Standing policy the colony executes.
    pub policy: ColonyPolicy,
    /// A direct player override taking precedence over `policy`.
    pub directive: ColonyIntent,
    /// Per-special accumulated stockpile (indexed by `SpecialKind::index`).
    pub stockpile: [Fixed; SPECIAL_COUNT],
    /// Per-special awareness/capability (Unknown → Detected → Extractable).
    pub knowledge_of: [Knowledge; SPECIAL_COUNT],
}

impl Colony {
    /// The autonomy the colony has *earned* so far (`0..=9`): one level per
    /// [`AUTONOMY_HOLD_TICKS`] of accumulated progress. Institutions can later
    /// discount the requirement; for now it is a straight ratio.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the else branch only casts when earned <= AUTONOMY_FULL (9)"
    )]
    pub const fn earned_autonomy(&self) -> u8 {
        let earned = self.autonomy_progress / AUTONOMY_HOLD_TICKS;
        if earned > AUTONOMY_FULL as u32 {
            AUTONOMY_FULL
        } else {
            earned as u8
        }
    }

    /// The level the colony actually acts at: the lesser of requested and earned.
    /// A `Hold` directive forces it to zero (fully manual).
    #[must_use]
    pub const fn effective_autonomy(&self) -> u8 {
        if matches!(self.directive, ColonyIntent::Hold | ColonyIntent::Evacuate) {
            return 0;
        }
        let earned = self.earned_autonomy();
        if self.autonomy_level < earned {
            self.autonomy_level
        } else {
            earned
        }
    }

    /// True when the colony runs itself fully (effective autonomy at the cap).
    #[must_use]
    pub const fn is_fully_autonomous(&self) -> bool {
        self.alive && self.effective_autonomy() >= AUTONOMY_FULL
    }
}
