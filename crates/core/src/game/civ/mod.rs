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

/// Stable handle for a sector — a governance grouping of colonies.
///
/// An index into `Sim`'s sector arena; slots are recycled (LIFO) through the
/// sector free-list, mirroring the colony and entity arenas (determinism rule D5).
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct SectorId(pub u32);

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

/// An empire's Kardashev tier — its civilization-scale progress.
///
/// Derived from how far it has expanded. Distinct from a tech's `RealityClass`
/// honesty label: this is *how powerful the civilization is* — the climb the
/// whole game is about.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum KardashevTier {
    /// Planetary (≈ Type I) — a single world.
    Planetary = 0,
    /// Interplanetary — a handful of colonies.
    Interplanetary = 1,
    /// Interstellar — a spreading empire.
    Interstellar = 2,
    /// Galactic (≈ Type III) — a vast dominion.
    Galactic = 3,
    /// Transcendent (Type IV+) — masters of the universe.
    Transcendent = 4,
}

impl KardashevTier {
    /// The tier an empire of `colony_count` colonies has reached.
    #[must_use]
    pub const fn from_colony_count(colony_count: usize) -> Self {
        match colony_count {
            0 | 1 => Self::Planetary,
            2 | 3 => Self::Interplanetary,
            4 | 5 => Self::Interstellar,
            6 | 7 => Self::Galactic,
            _ => Self::Transcendent,
        }
    }
}

/// The civilization archetype a colony belongs to.
///
/// Every species runs the SAME simulation; the discriminant only *biases*
/// deterministic behaviour (expansion drive, colony ceiling), so conflict still
/// emerges from competition over the same scarce resources, not from scripting.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Species {
    /// Humanity — the balanced baseline.
    #[default]
    Standard = 0,
    /// Swarm — fast, sprawling expansion; weak early economy.
    Swarm = 1,
    /// Machine — high automation, energy-hungry, strong logistics.
    Machine = 2,
    /// Trader — economy-first, expansion-shy, dangerous late.
    Trader = 3,
    /// Ancient — few colonies, very strong, slow to spread.
    Ancient = 4,
    /// Dark-sector — stealthy, hidden resources, hard to counter.
    DarkSector = 5,
}

impl Species {
    /// Ticks between this species' auto-expansion attempts (lower = pushier).
    #[must_use]
    pub const fn expand_period(self) -> u64 {
        match self {
            Self::Swarm => 120,
            Self::Standard | Self::Machine => 240,
            Self::DarkSector => 320,
            Self::Trader => 480,
            Self::Ancient => 600,
        }
    }

    /// How many colonies this species will auto-found.
    #[must_use]
    pub const fn colony_cap(self) -> usize {
        match self {
            Self::Swarm => 8,
            Self::Machine | Self::DarkSector => 5,
            Self::Standard => 4,
            Self::Trader => 3,
            Self::Ancient => 2,
        }
    }
}

/// A colony's simulation detail level — a determinism-safe LOD.
///
/// Computed every tick as a pure function of *hashed game state* (never the
/// camera or selection), so it is identical on every client. In M7 the sim runs
/// full fidelity regardless; `SimDetail` is a hint the render shell uses to
/// throttle drawing/CPU and that later milestones use to skip work via
/// provably-equal closed-form catch-up.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum SimDetail {
    /// Quiet and mature — minimum detail.
    #[default]
    Dormant = 0,
    /// Growing / active — full scalar updates.
    Active = 1,
    /// Combat imminent — full entity-level simulation.
    Tactical = 2,
}

/// A governance doctrine applied to a sector (a grouping of colonies); biases
/// what its colonies emphasize.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum SectorDoctrine {
    /// No special emphasis.
    #[default]
    Balanced = 0,
    /// Research focus.
    Research = 1,
    /// Resource extraction focus.
    Mining = 2,
    /// Defensive focus.
    Fortress = 3,
    /// Shipyard / production focus.
    Shipyard = 4,
    /// Expansion frontier.
    Frontier = 5,
}

impl SectorDoctrine {
    /// The standing [`ColonyPolicy`] this doctrine pushes onto its member
    /// colonies. A pure mapping — the governance verb is "a sector translates one
    /// doctrine choice into the policy its colonies execute" (coherence rule R2:
    /// policy inherits down). Returning a full policy keeps the propagation
    /// idempotent: once a colony matches, the sector emits nothing further.
    #[must_use]
    pub const fn policy(self) -> ColonyPolicy {
        let base = ColonyPolicy {
            expansion: ExpansionIntent::None,
            economic: EconomicIntent::Balanced,
            military: MilitaryIntent::DefensiveOnly,
            research: ResearchIntent::Balanced,
            resource: ResourcePolicy::LocalFirst,
            build: BuildPolicy::Balanced,
            export: ExportIntent::Hold,
        };
        match self {
            Self::Balanced => base,
            Self::Research => ColonyPolicy {
                economic: EconomicIntent::Research,
                build: BuildPolicy::EconomyFirst,
                ..base
            },
            Self::Mining => ColonyPolicy {
                economic: EconomicIntent::Money,
                resource: ResourcePolicy::ExportSurplus,
                build: BuildPolicy::EconomyFirst,
                export: ExportIntent::ExportSurplus,
                ..base
            },
            Self::Fortress => ColonyPolicy {
                military: MilitaryIntent::DefensiveOnly,
                build: BuildPolicy::MilitaryFirst,
                ..base
            },
            Self::Shipyard => ColonyPolicy {
                economic: EconomicIntent::Military,
                military: MilitaryIntent::ProtectRoutes,
                build: BuildPolicy::MilitaryFirst,
                ..base
            },
            Self::Frontier => ColonyPolicy {
                expansion: ExpansionIntent::AutoStrategic,
                build: BuildPolicy::InfrastructureFirst,
                ..base
            },
        }
    }
}

/// A governance grouping of colonies under one [`SectorDoctrine`].
///
/// The net-new strategic layer between the empire and its colonies. Lives in
/// `Sim`'s sector arena with LIFO slot recycling (determinism rule D5). Aggregate
/// readings (colony count, flows) are computed on demand from members, never
/// stored, so there is no second source of truth to drift (rule D4).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Sector {
    /// `false` once disbanded; the slot is then recycled.
    pub alive: bool,
    /// Owning player/faction (a [`PlayerId`] for now; M6 generalizes to `Vec<Civ>`).
    pub owner: PlayerId,
    /// The governance doctrine its member colonies inherit.
    pub doctrine: SectorDoctrine,
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
        Command::FoundBase { .. } | Command::FoundColony { .. } => 6,
        // movement / initiative
        Command::Move { .. } | Command::UseAbility { .. } => 7,
        // institution-level spend
        Command::Ascend { .. } | Command::ChoosePerk { .. } => 8,
        // player→colony / player→sector configuration commands are never
        // colony-emitted (the sector layer emits SetColonyPolicy on the colonies'
        // behalf, which is already covered above).
        Command::SetColonyAutonomy { .. }
        | Command::SetColonyPolicy { .. }
        | Command::DirectColony { .. }
        | Command::SurveySpecial { .. }
        | Command::FoundSector { .. }
        | Command::AssignColonyToSector { .. }
        | Command::SetSectorDoctrine { .. }
        | Command::GovernColony { .. } => u8::MAX,
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
    /// The civilization archetype, which biases autonomous behaviour.
    pub species: Species,
    /// Current simulation detail level (a determinism-safe render/CPU hint).
    pub detail: SimDetail,
    /// The sector governing this colony, if any. Its [`SectorDoctrine`] supplies
    /// the colony's standing policy (see [`SectorDoctrine::policy`]); `None` means
    /// the colony is ungoverned and keeps whatever policy it was last set.
    pub sector: Option<SectorId>,
    /// The tick through which the per-tick scalar accumulators
    /// ([`autonomy_progress`](Self::autonomy_progress) and the Field-class
    /// entries of [`stockpile`](Self::stockpile)) have been materialized into
    /// stored form. While the colony is [`Dormant`](SimDetail::Dormant) its
    /// per-tick passes are skipped, so this clock lags the world clock; the gap is
    /// the number of skipped ticks, applied in one exact closed-form step on wake
    /// (or read closed-form by the state hash). It is *not* hashed directly — the
    /// hash folds in the reconstructed (caught-up) values, so the lazy
    /// representation is invisible to determinism (rule D3).
    pub last_sync_tick: u64,
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
