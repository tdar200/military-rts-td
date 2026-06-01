//! Deterministic simulation core for the military RTS + tower-defense game.
//!
//! This crate is the single source of truth for game logic. It is pure, headless,
//! and deterministic: given the same seed and the same ordered command stream it
//! produces a bit-identical end state on every target — native desktop, WASM in
//! the browser, mobile, and the headless server. That property is what lets the
//! client and server never drift apart.
//!
//! The determinism guarantees are enforced mechanically, not by convention:
//!
//! * **No floating point** — `deny(clippy::float_arithmetic)` makes the compiler
//!   reject `f32`/`f64` math anywhere in this crate. All quantities are
//!   fixed-point (see the forthcoming `math` module).
//! * **No std outside tests** — `no_std` keeps system time, threads, and I/O (and
//!   the randomly-seeded `std` `HashMap`) out of the simulation.
//! * **Seeded RNG only** — the simulation owns a small deterministic PRNG; there
//!   is no access to OS entropy.
#![cfg_attr(not(test), no_std)]
#![deny(clippy::float_arithmetic)]

extern crate alloc;

pub mod fixed;
pub mod hash;
pub mod rng;
pub mod vec;
pub mod world;

/// Simulation ticks per second. The sim advances in fixed steps of
/// `1 / TICKS_PER_SECOND` seconds, decoupled from any render frame rate.
pub const TICKS_PER_SECOND: u32 = 30;
