//! Deterministic 2D vector built on [`Fixed`].
//!
//! Positions, velocities, and offsets in the simulation are all `Vec2`. Like
//! every sim quantity it is fixed-point — no floats — so vector math is
//! bit-identical across platforms.

use crate::fixed::Fixed;
use core::ops::{Add, Sub};

/// A 2D vector of [`Fixed`] components.
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug, Hash)]
pub struct Vec2 {
    /// Horizontal component.
    pub x: Fixed,
    /// Vertical component.
    pub y: Fixed,
}

impl Vec2 {
    /// The origin `(0, 0)`.
    pub const ZERO: Self = Self {
        x: Fixed::ZERO,
        y: Fixed::ZERO,
    };

    /// Creates a vector from its components.
    #[must_use]
    pub const fn new(x: Fixed, y: Fixed) -> Self {
        Self { x, y }
    }

    /// Multiplies both components by a scalar.
    #[must_use]
    pub fn scale(self, s: Fixed) -> Self {
        Self::new(self.x * s, self.y * s)
    }

    /// Dot product `self · other`.
    #[must_use]
    pub fn dot(self, other: Self) -> Fixed {
        self.x * other.x + self.y * other.y
    }

    /// Squared length `|self|^2` (avoids a square root; use for range checks by
    /// comparing against a squared radius).
    #[must_use]
    pub fn length_squared(self) -> Fixed {
        self.dot(self)
    }

    /// Euclidean length `|self|`.
    #[must_use]
    pub fn length(self) -> Fixed {
        self.length_squared().sqrt()
    }
}

impl Add for Vec2 {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y)
    }
}

impl Sub for Vec2 {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y)
    }
}

#[cfg(test)]
mod tests {
    use super::Vec2;
    use crate::fixed::Fixed;

    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(Fixed::from_int(x), Fixed::from_int(y))
    }

    #[test]
    fn new_sets_components() {
        let p = v(2, 3);
        assert_eq!(p.x, Fixed::from_int(2));
        assert_eq!(p.y, Fixed::from_int(3));
    }

    #[test]
    fn zero_is_origin() {
        assert_eq!(Vec2::ZERO, v(0, 0));
    }

    #[test]
    fn addition_and_subtraction() {
        assert_eq!(v(1, 2) + v(3, 4), v(4, 6));
        assert_eq!(v(5, 5) - v(2, 8), v(3, -3));
    }

    #[test]
    fn scale_multiplies_components() {
        assert_eq!(v(2, 3).scale(Fixed::from_int(2)), v(4, 6));
        assert_eq!(v(4, 6).scale(Fixed::from_ratio(1, 2)), v(2, 3));
    }

    #[test]
    fn dot_product() {
        // 1*3 + 2*4 = 11
        assert_eq!(v(1, 2).dot(v(3, 4)), Fixed::from_int(11));
    }

    #[test]
    fn length_squared_is_dot_with_self() {
        // 3^2 + 4^2 = 25
        assert_eq!(v(3, 4).length_squared(), Fixed::from_int(25));
    }

    #[test]
    fn length_is_euclidean_distance() {
        // 3-4-5 right triangle
        assert_eq!(v(3, 4).length(), Fixed::from_int(5));
        assert_eq!(Vec2::ZERO.length(), Fixed::ZERO);
    }
}
