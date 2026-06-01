//! Headless authoritative server.
//!
//! Links the identical [`rts_core`] crate and (in the server milestone)
//! re-simulates recorded input logs to validate match outcomes — the end-to-end
//! proof that client and server can never drift. This is the crate scaffold.

fn main() {
    println!(
        "rts server — deterministic core @ {} ticks/sec",
        rts_core::TICKS_PER_SECOND
    );
}
