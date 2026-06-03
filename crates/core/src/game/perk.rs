//! Survival-mode roguelite perks.
//!
//! One-time, permanent run upgrades the player drafts via
//! [`Command::ChoosePerk`](crate::game::sim::Command). They are stored as a
//! per-player bitmask in the sim and hashed into the state, so a run stays fully
//! deterministic given its `(seed, perk choices)`.

/// Number of perks in the pool.
pub const PERK_COUNT: u32 = 4;

/// +25% outgoing unit/tower damage.
pub const OVERCHARGE: u32 = 0;
/// +50% credit income.
pub const LOGISTICS: u32 = 1;
/// +8 population (supply) cap.
pub const CONSCRIPTION: u32 = 2;
/// +2 flat incoming-damage mitigation.
pub const BULWARK: u32 = 3;

/// Display name for a perk id.
#[must_use]
pub const fn name(id: u32) -> &'static str {
    match id {
        OVERCHARGE => "Overcharge",
        LOGISTICS => "Logistics",
        CONSCRIPTION => "Conscription",
        _ => "Bulwark",
    }
}

/// One-line description for a perk id.
#[must_use]
pub const fn description(id: u32) -> &'static str {
    match id {
        OVERCHARGE => "+25% weapon damage",
        LOGISTICS => "+50% credit income",
        CONSCRIPTION => "+8 supply cap",
        _ => "+2 armor mitigation",
    }
}
