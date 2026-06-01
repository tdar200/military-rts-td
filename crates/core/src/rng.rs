//! Deterministic pseudo-random number generator owned by the simulation.
//!
//! The simulation must never touch OS entropy or `std`'s randomly-seeded hashers —
//! every random decision (spawn jitter, AI choices, combat rolls) has to replay
//! identically from a seed so the client and server agree. This is a small
//! [`SplitMix64`](https://prng.di.unimi.it/splitmix64.c) generator: fast,
//! deterministic, and dependency-free.

/// A deterministic `SplitMix64` pseudo-random generator.
#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
}

impl Rng {
    /// Creates a generator from a 64-bit seed. The same seed always yields the
    /// same sequence on every platform.
    #[must_use]
    pub const fn from_seed(seed: u64) -> Self {
        Self { state: seed }
    }

    /// Returns the next 64-bit value and advances the state (`SplitMix64`).
    #[must_use]
    pub const fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Returns the next 32-bit value and advances the state.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "taking the high 32 bits of a 64-bit draw is intentional"
    )]
    pub const fn next_u32(&mut self) -> u32 {
        (self.next_u64() >> 32) as u32
    }

    /// Returns a value uniformly in `[0, bound)` and advances the state, using
    /// Lemire's multiply-shift to avoid modulo bias. `bound` must be non-zero;
    /// `next_below(1)` is always `0`.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the high 32 bits of the widened product are the mapped result, by construction in 0..bound"
    )]
    #[allow(
        clippy::cast_lossless,
        reason = "const fn cannot call the (non-const) u64::From; the u32->u64 casts are lossless"
    )]
    pub const fn next_below(&mut self, bound: u32) -> u32 {
        let product = self.next_u32() as u64 * bound as u64;
        (product >> 32) as u32
    }
}

#[cfg(test)]
mod tests {
    use super::Rng;

    #[test]
    fn same_seed_produces_same_sequence() {
        let mut a = Rng::from_seed(12_345);
        let mut b = Rng::from_seed(12_345);
        for _ in 0..100 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn different_seeds_diverge() {
        let mut a = Rng::from_seed(1);
        let mut b = Rng::from_seed(2);
        assert_ne!(a.next_u64(), b.next_u64());
    }

    #[test]
    fn sequence_advances() {
        let mut a = Rng::from_seed(7);
        assert_ne!(a.next_u64(), a.next_u64());
    }

    #[test]
    fn next_below_stays_in_range() {
        let mut a = Rng::from_seed(99);
        for _ in 0..1000 {
            assert!(a.next_below(6) < 6);
        }
    }

    #[test]
    fn next_below_one_is_always_zero() {
        let mut a = Rng::from_seed(99);
        for _ in 0..50 {
            assert_eq!(a.next_below(1), 0);
        }
    }

    #[test]
    fn next_below_covers_full_range() {
        let mut a = Rng::from_seed(2024);
        let mut seen_low = false;
        let mut seen_high = false;
        for _ in 0..1000 {
            match a.next_below(4) {
                0 => seen_low = true,
                3 => seen_high = true,
                _ => {}
            }
        }
        assert!(seen_low && seen_high);
    }
}
