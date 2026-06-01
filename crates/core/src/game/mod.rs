//! The RTS game simulation, built on the deterministic primitives in the crate
//! root (`fixed`, `vec`, `rng`, `hash`).
//!
//! Submodules are added as the gameplay grows: the battlefield [`map`], the
//! economy, buildings, units, combat, pathfinding, and AI.

pub mod map;
pub mod path;
pub mod sim;
pub mod stats;
