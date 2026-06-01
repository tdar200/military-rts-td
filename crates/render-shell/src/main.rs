//! Thin Macroquad render/input shell over the deterministic [`rts_core`].
//!
//! The shell reads core state and draws it (with inter-tick interpolation) and
//! translates input into platform-agnostic simulation commands. It owns nothing
//! authoritative. Macroquad + egui wiring lands in the desktop-shell milestone;
//! this is the crate scaffold that proves the core links into a binary target.

fn main() {
    println!(
        "rts shell — deterministic core runs at {} ticks/sec",
        rts_core::TICKS_PER_SECOND
    );
}
