//! Deterministic fixed-point number type.
//!
//! Every spatial / numeric quantity in the simulation is a [`Fixed`] rather than
//! an `f32`/`f64`, because floating-point results differ across CPUs, compilers,
//! and WASM-vs-native — which would desync the client from the server. Fixed-point
//! integer math is bit-identical everywhere.
//!
//! Representation: a signed `Q47.16` value stored in an `i64` — i.e. the stored
//! integer is the real value multiplied by `2^16`. That gives a resolution of
//! `1 / 65_536` and an integer range of roughly `±1.4e14`, which is ample for tile
//! coordinates, health, and timers.

use core::ops::{Add, Div, Mul, Neg, Sub};

/// A deterministic fixed-point number (`Q47.16`, backed by `i64`).
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default, Debug)]
pub struct Fixed(i64);

impl Fixed {
    /// Number of fractional bits in the representation.
    pub const FRAC_BITS: u32 = 16;

    /// The value `0`.
    pub const ZERO: Self = Self(0);

    /// The value `1`.
    pub const ONE: Self = Self(1 << Self::FRAC_BITS);

    /// Wraps a raw fixed-point bit pattern (real value × `2^FRAC_BITS`).
    #[must_use]
    pub const fn from_bits(raw: i64) -> Self {
        Self(raw)
    }

    /// Returns the raw fixed-point bit pattern (real value × `2^FRAC_BITS`).
    #[must_use]
    pub const fn to_bits(self) -> i64 {
        self.0
    }

    /// Creates a `Fixed` from a whole integer.
    #[must_use]
    #[allow(
        clippy::cast_lossless,
        reason = "const fn cannot call the (non-const) i64::From; the i32->i64 cast is lossless"
    )]
    pub const fn from_int(n: i32) -> Self {
        Self((n as i64) << Self::FRAC_BITS)
    }

    /// Creates a `Fixed` from the exact ratio `num / den` (rounded toward zero in
    /// the final bit). Panics if `den == 0`.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "result is in i64 range for the ratios we construct; truncation is the documented Q47.16 behavior"
    )]
    pub const fn from_ratio(num: i64, den: i64) -> Self {
        Self((((num as i128) << Self::FRAC_BITS) / (den as i128)) as i64)
    }

    /// Largest integer `<= self` (rounds toward negative infinity).
    #[must_use]
    pub const fn to_int_floor(self) -> i64 {
        self.0 >> Self::FRAC_BITS
    }

    /// Nearest integer, rounding halves toward positive infinity.
    #[must_use]
    pub const fn round_to_int(self) -> i64 {
        (self.0 + (1 << (Self::FRAC_BITS - 1))) >> Self::FRAC_BITS
    }
}

impl Add for Fixed {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self(self.0 + rhs.0)
    }
}

impl Sub for Fixed {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self(self.0 - rhs.0)
    }
}

impl Neg for Fixed {
    type Output = Self;
    fn neg(self) -> Self {
        Self(-self.0)
    }
}

impl Mul for Fixed {
    type Output = Self;
    #[allow(
        clippy::cast_possible_truncation,
        reason = "widened to i128 for the multiply; shifting back into Q47.16 i64 range is intended"
    )]
    fn mul(self, rhs: Self) -> Self {
        Self(((i128::from(self.0) * i128::from(rhs.0)) >> Self::FRAC_BITS) as i64)
    }
}

impl Div for Fixed {
    type Output = Self;
    #[allow(
        clippy::cast_possible_truncation,
        reason = "widened to i128 for the divide; result is back in Q47.16 i64 range"
    )]
    fn div(self, rhs: Self) -> Self {
        Self(((i128::from(self.0) << Self::FRAC_BITS) / i128::from(rhs.0)) as i64)
    }
}

#[cfg(test)]
mod tests {
    use super::Fixed;

    #[test]
    fn constants_have_expected_raw_values() {
        assert_eq!(Fixed::ZERO.to_bits(), 0);
        assert_eq!(Fixed::ONE.to_bits(), 1 << 16);
    }

    #[test]
    fn from_int_round_trips() {
        assert_eq!(Fixed::from_int(5).to_bits(), 5 * 65_536);
        assert_eq!(Fixed::from_int(-3).to_int_floor(), -3);
        assert_eq!(Fixed::from_int(42).to_int_floor(), 42);
    }

    #[test]
    fn from_ratio_makes_fractions() {
        assert_eq!(Fixed::from_ratio(1, 2).to_bits(), 32_768);
        assert_eq!(Fixed::from_ratio(3, 4).to_bits(), 49_152);
    }

    #[test]
    fn ordering_follows_value() {
        assert!(Fixed::from_int(1) < Fixed::from_int(2));
        assert!(Fixed::from_ratio(1, 2) < Fixed::ONE);
        assert!(Fixed::from_int(-1) < Fixed::ZERO);
    }

    #[test]
    fn addition_and_subtraction() {
        assert_eq!(Fixed::from_int(2) + Fixed::from_int(3), Fixed::from_int(5));
        assert_eq!(Fixed::from_int(5) - Fixed::from_int(8), Fixed::from_int(-3));
        assert_eq!(
            Fixed::from_ratio(1, 2) + Fixed::from_ratio(1, 2),
            Fixed::ONE
        );
    }

    #[test]
    fn negation() {
        assert_eq!(-Fixed::from_int(5), Fixed::from_int(-5));
        assert_eq!(-Fixed::ZERO, Fixed::ZERO);
    }

    #[test]
    fn multiplication() {
        assert_eq!(Fixed::from_int(3) * Fixed::from_int(4), Fixed::from_int(12));
        // 1.5 * 2 == 3
        assert_eq!(
            Fixed::from_ratio(3, 2) * Fixed::from_int(2),
            Fixed::from_int(3)
        );
        // 0.5 * 0.5 == 0.25
        assert_eq!(
            Fixed::from_ratio(1, 2) * Fixed::from_ratio(1, 2),
            Fixed::from_ratio(1, 4)
        );
    }

    #[test]
    fn division() {
        assert_eq!(Fixed::from_int(12) / Fixed::from_int(4), Fixed::from_int(3));
        // 3 / 2 == 1.5
        assert_eq!(
            Fixed::from_int(3) / Fixed::from_int(2),
            Fixed::from_ratio(3, 2)
        );
    }

    #[test]
    fn floor_rounds_toward_negative_infinity() {
        assert_eq!(Fixed::from_ratio(7, 2).to_int_floor(), 3); // 3.5 -> 3
        assert_eq!(Fixed::from_ratio(-7, 2).to_int_floor(), -4); // -3.5 -> -4
    }

    #[test]
    fn round_to_nearest() {
        assert_eq!(Fixed::from_ratio(7, 2).round_to_int(), 4); // 3.5 -> 4
        assert_eq!(Fixed::from_ratio(5, 2).round_to_int(), 3); // 2.5 -> 3
        assert_eq!(Fixed::from_ratio(4, 3).round_to_int(), 1); // 1.33 -> 1
    }
}
