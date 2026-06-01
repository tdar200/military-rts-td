//! Deterministic state hashing.
//!
//! The determinism guarantee is checked by hashing the whole world each tick and
//! comparing: same seed + same inputs must yield the same hash on every target.
//! We hand-roll [`FNV-1a`] (64-bit) rather than use `std`'s hasher so the result
//! is stable across Rust versions, platforms, and endianness (we always feed
//! little-endian bytes).
//!
//! [`FNV-1a`]: https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function

/// A 64-bit `FNV-1a` hash accumulator.
#[derive(Clone, Debug)]
pub struct Fnv(u64);

impl Fnv {
    const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01b3;

    /// Creates a fresh accumulator.
    #[must_use]
    pub const fn new() -> Self {
        Self(Self::OFFSET_BASIS)
    }

    /// Folds a `u64` into the hash (little-endian, byte by byte).
    pub fn write_u64(&mut self, value: u64) {
        for byte in value.to_le_bytes() {
            self.0 ^= u64::from(byte);
            self.0 = self.0.wrapping_mul(Self::PRIME);
        }
    }

    /// Folds an `i64` into the hash by reinterpreting its bits.
    #[allow(
        clippy::cast_sign_loss,
        reason = "reinterpreting the bit pattern for hashing; sign is irrelevant"
    )]
    pub fn write_i64(&mut self, value: i64) {
        self.write_u64(value as u64);
    }

    /// Returns the accumulated hash.
    #[must_use]
    pub const fn finish(&self) -> u64 {
        self.0
    }
}

impl Default for Fnv {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::Fnv;

    const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;

    #[test]
    fn empty_hash_is_offset_basis() {
        assert_eq!(Fnv::new().finish(), OFFSET_BASIS);
    }

    #[test]
    fn deterministic_for_same_input() {
        let mut a = Fnv::new();
        let mut b = Fnv::new();
        a.write_u64(42);
        a.write_i64(-7);
        b.write_u64(42);
        b.write_i64(-7);
        assert_eq!(a.finish(), b.finish());
    }

    #[test]
    fn distinguishes_values() {
        let mut a = Fnv::new();
        let mut b = Fnv::new();
        a.write_u64(1);
        b.write_u64(2);
        assert_ne!(a.finish(), b.finish());
    }

    #[test]
    fn order_sensitive() {
        let mut a = Fnv::new();
        let mut b = Fnv::new();
        a.write_u64(1);
        a.write_u64(2);
        b.write_u64(2);
        b.write_u64(1);
        assert_ne!(a.finish(), b.finish());
    }
}
