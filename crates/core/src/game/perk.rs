//! Roguelite perks.
//!
//! One-time, permanent run upgrades the player drafts via
//! [`Command::ChoosePerk`](crate::game::sim::Command). They are stored as a
//! per-player bitmask in the sim and hashed into the state, so a run stays fully
//! deterministic given its `(seed, perk choices)`.
//!
//! Ids 0 to 3 are the legacy survival perks ([`PERK_COUNT`]), the only ones a
//! legacy map accepts. Task 23 adds the Kestrel depth perks, ids 4 to 11
//! ([`DEPTH_PERK_COUNT`]): a Kestrel run drafts all twelve out of its pool, and
//! every depth effect checks the depth rules (`Sim::is_depth`).

/// Number of perks in the legacy (non-depth) pool.
pub const PERK_COUNT: u32 = 4;

/// +25% outgoing unit/tower damage.
pub const OVERCHARGE: u32 = 0;
/// +50% credit income.
pub const LOGISTICS: u32 = 1;
/// +8 population (supply) cap.
pub const CONSCRIPTION: u32 = 2;
/// +2 flat incoming-damage mitigation.
pub const BULWARK: u32 = 3;
/// Task 23: one free level on the lowest of the three Upgrades tracks (ties
/// to the lowest track), granted when drafted.
pub const FIELD_UPGRADE: u32 = 4;
/// Task 23: ability cooldowns x0.75.
pub const RAPID_CYCLE: u32 = 5;
/// Task 23: the refinery escalation is removed (every refinery costs base).
pub const REFINERY_DISCOUNT: u32 = 6;
/// Task 23: turret range +1.
pub const LONG_SIGHT: u32 = 7;
/// Task 23: tech 1 (tank tooling) completes when drafted.
pub const EARLY_TOOLING: u32 = 8;
/// Task 23: walls take one third less damage.
pub const HARDENED_WALLS: u32 = 9;
/// Task 23: the repair price is halved.
pub const FIELD_REPAIR: u32 = 10;
/// Task 23: the Capital costs 25% less.
pub const CAPITAL_DISCOUNT: u32 = 11;

/// Task 23: number of perks a Kestrel run can draft (the legacy four plus the
/// eight depth perks).
pub const DEPTH_PERK_COUNT: u32 = 12;
/// Task 23: the run pool a new player starts with, perks 0 to 7 (one bit per
/// perk id).
pub const DEFAULT_RUN_POOL: u32 = 0xFF;
/// Task 23: every draftable perk (bits 0 to 11); pool bits above it are ignored.
pub const FULL_RUN_POOL: u32 = (1 << DEPTH_PERK_COUNT) - 1;
/// Task 23: an empty slot in a draft that drew fewer than three perks.
pub const NO_PERK: u8 = u8::MAX;

/// Display name for a perk id.
#[must_use]
pub const fn name(id: u32) -> &'static str {
    match id {
        OVERCHARGE => "Overcharge",
        LOGISTICS => "Logistics",
        CONSCRIPTION => "Conscription",
        FIELD_UPGRADE => "Field Upgrade",
        RAPID_CYCLE => "Rapid Cycle",
        REFINERY_DISCOUNT => "Refinery Discount",
        LONG_SIGHT => "Long Sight",
        EARLY_TOOLING => "Early Tooling",
        HARDENED_WALLS => "Hardened Walls",
        FIELD_REPAIR => "Field Repair",
        CAPITAL_DISCOUNT => "Capital Discount",
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
        FIELD_UPGRADE => "One free level on your lowest Upgrades track",
        RAPID_CYCLE => "Ability cooldowns 25% shorter",
        REFINERY_DISCOUNT => "Every refinery costs the base price",
        LONG_SIGHT => "+1 turret range",
        EARLY_TOOLING => "Tank tooling (tech 1) completes at once",
        HARDENED_WALLS => "Walls take one third less damage",
        FIELD_REPAIR => "Repairs cost half",
        CAPITAL_DISCOUNT => "The Capital costs 25% less",
        _ => "+2 armor mitigation",
    }
}
