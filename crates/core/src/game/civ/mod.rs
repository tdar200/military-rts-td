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
//! This module is the **M0 prototype** — the minimal slice that proves the loop:
//! a colony at full autonomy delegates to the proven AI brain, and a colony at
//! zero autonomy stays manual. Later milestones grow [`Colony`] into the full
//! civ-scalar / policy / scoring / adoption / LOD model and add the
//! Empire→Sector→…→Colony hierarchy.

use crate::game::sim::{EntityId, PlayerId};

/// Stable handle for a colony.
///
/// An index into `Sim`'s colony arena; slots are recycled (LIFO) through the
/// colony free-list, mirroring the entity arena.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct ColonyId(pub u32);

/// Full autonomy — the colony runs itself entirely.
///
/// The "automated at maturity" pole. M0 uses only the two poles, `0` (fully
/// manual) and this one; milestone M3 fills in the earned 1..=8 gradient that
/// unlocks one command category at a time.
pub const AUTONOMY_FULL: u8 = 9;

/// One autonomous colony.
///
/// M0 keeps this intentionally small: enough to exist, be hashed deterministically,
/// and drive itself. The civ scalars (population, labour, energy/money/labour
/// flows, housing, stability, automation, …), policy, scores, adoption phases, and
/// LOD detail level land in later milestones.
#[derive(Clone, Debug)]
pub struct Colony {
    /// `false` once the colony is razed; the slot is then recycled.
    pub alive: bool,
    /// Owning civ/faction. Represented by a [`PlayerId`] for now (one civ per
    /// player); M6 generalizes ownership to `Vec<Civ>`.
    pub owner: PlayerId,
    /// The Command Center entity this colony is seated on.
    pub seat: EntityId,
    /// Earned autonomy, `0..=9`. Gates which command categories the colony may
    /// emit for itself; M0 honours only `0` (manual) and [`AUTONOMY_FULL`].
    pub autonomy_level: u8,
}

impl Colony {
    /// True when the colony runs itself fully (autonomy at [`AUTONOMY_FULL`]).
    #[must_use]
    pub const fn is_fully_autonomous(&self) -> bool {
        self.alive && self.autonomy_level >= AUTONOMY_FULL
    }
}
