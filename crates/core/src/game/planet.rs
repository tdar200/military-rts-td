//! Planetary territory.
//!
//! A planet is a region of map tiles; a civ owns a planet by holding its capital
//! seat (a `CommandCenter`). Ownership is discrete and event-driven (settle /
//! capture), so it never accrues per-tick — it is invisible to the LOD/closed-form
//! machinery (determinism rules D2/D3 N/A).

use crate::fixed::Fixed;
use crate::game::sim::{CivId, EntityId};
use crate::vec::Vec2;

/// Stable index into `Sim::planets`.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct PlanetId(pub u16);

/// One planet's mutable control state. Tile membership is stored statically on
/// the `Map`; only ownership lives here (and is hashed).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Planet {
    /// Owning civ, or `None` for a neutral/unsettled planet.
    pub owner: Option<CivId>,
    /// The controlling `CommandCenter` (capital). `None` when unsettled.
    pub seat: Option<EntityId>,
    /// Fixed-point world-space centre (AI distance reasoning).
    pub center: Vec2,
    /// Claim radius in world units (auxiliary; exact membership is the Map layer).
    pub radius: Fixed,
}
