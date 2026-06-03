//! Game-feel helpers: easing/tween curves, frame-rate-independent damping, and a
//! trauma-based screen-shake camera. Cosmetic only — used by the shell's view
//! layer to smooth motion and add impact, never by the sim.

use macroquad::prelude::get_time;

/// Linear interpolation between `a` and `b` by `t`.
#[must_use]
#[inline]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Ease-out "back": overshoots past the target then settles. Starts at 0 for
/// `t = 0` and returns to 1 at `t = 1` — ideal for spawn/pop scale-ins.
#[must_use]
#[inline]
pub fn ease_out_back(t: f32) -> f32 {
    const C1: f32 = 1.701_58;
    const C3: f32 = C1 + 1.0;
    let t = t.clamp(0.0, 1.0);
    let inv = t - 1.0;
    1.0 + C3 * inv * inv * inv + C1 * inv * inv
}

/// Frame-rate-independent exponential approach of `current` toward `target`.
/// `rate` is the approach speed (higher = snappier); stable for any `dt`.
#[must_use]
#[inline]
pub fn damp(current: f32, target: f32, rate: f32, dt: f32) -> f32 {
    let blend = 1.0 - (-rate * dt).exp();
    current + (target - current) * blend
}

/// Smooth scalar pseudo-noise in roughly [-1, 1] from a seed and time — a cheap
/// stand-in for Perlin, sufficient for screen shake.
fn noise(seed: f32, t: f32) -> f32 {
    (t * 23.0 + seed * 5.0).sin() * 0.6 + (t * 37.0 + seed * 2.3).sin() * 0.4
}

/// Trauma-based screen shake. Callers add trauma on impacts; the shake magnitude
/// is `trauma²`, so big hits feel huge while small ones fade fast.
#[derive(Default)]
pub struct Camera {
    trauma: f32,
}

impl Camera {
    /// Adds trauma (clamped to 1.0).
    pub fn add_trauma(&mut self, amount: f32) {
        self.trauma = (self.trauma + amount).clamp(0.0, 1.0);
    }

    /// Decays trauma toward zero.
    pub fn update(&mut self, dt: f32) {
        const DECAY: f32 = 1.5;
        self.trauma = (self.trauma - DECAY * dt).max(0.0);
    }

    /// Pixel offset `(dx, dy)` to translate the shaking world layer by this frame.
    #[must_use]
    pub fn offset(&self, max_px: f32) -> (f32, f32) {
        if self.trauma <= 0.0 {
            return (0.0, 0.0);
        }
        let shake = self.trauma * self.trauma;
        let t = get_time() as f32;
        (
            max_px * shake * noise(1.3, t),
            max_px * shake * noise(7.7, t),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::{damp, ease_out_back, lerp};

    #[test]
    fn lerp_endpoints_and_midpoint() {
        assert!((lerp(0.0, 10.0, 0.0) - 0.0).abs() < 1e-6);
        assert!((lerp(0.0, 10.0, 1.0) - 10.0).abs() < 1e-6);
        assert!((lerp(0.0, 10.0, 0.5) - 5.0).abs() < 1e-6);
    }

    #[test]
    fn ease_out_back_endpoints_and_overshoot() {
        assert!(ease_out_back(0.0).abs() < 1e-4);
        assert!((ease_out_back(1.0) - 1.0).abs() < 1e-4);
        // Overshoots above 1.0 somewhere in the back half before settling.
        assert!(ease_out_back(0.7) > 1.0);
    }

    #[test]
    fn damp_converges_toward_target() {
        let mut v = 0.0;
        for _ in 0..240 {
            v = damp(v, 100.0, 12.0, 1.0 / 60.0);
        }
        assert!((v - 100.0).abs() < 0.5);
    }
}
