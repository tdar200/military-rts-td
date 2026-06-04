//! Special (strategic) resources — discovered through science, not mined by
//! default.
//!
//! Money/Energy/Labour are the universal economy; *special* resources are the
//! exotic inputs a colony can only see and harvest once it has the capability.
//! Five flavours across three deterministic classes:
//!
//! - **Field** (Solar Flux, Gravitational Gradient): a static, immutable
//!   intensity sampled from the map by position — seeded once at world-gen, never
//!   depleting. Hashed as a single [`field intensity`](field_intensity) seed, not
//!   per-tile, so it costs one `u64` in the state hash.
//! - **Hazard** (Radiation, Anomaly): same static-field nature, but a danger
//!   rather than a resource.
//! - **Finite** (Antimatter, Rare Elements): a depletable stock (reuses the
//!   map-deposit path in later wiring).
//!
//! Determinism rule **D1**: field/hazard intensity is a *non-stream-advancing*
//! hash of `(seed, x, y, kind)` — it never touches `Sim::rng`, so it can be
//! sampled any number of times, in any order, without coupling the RNG draw-count
//! to colony state.

use crate::fixed::Fixed;

/// Number of special-resource kinds.
pub const SPECIAL_COUNT: usize = 6;

/// The strategic special resources.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub enum SpecialKind {
    /// Field: incident stellar energy (drives orbital solar).
    SolarFlux = 0,
    /// Field: spacetime curvature gradient (gravitational engineering).
    GravGradient = 1,
    /// Hazard: ambient radiation (degrades unshielded operations).
    RadiationBelt = 2,
    /// Hazard: an unexplained anomaly (dark-sector science hook).
    Anomaly = 3,
    /// Finite: trapped antimatter (densest fuel).
    Antimatter = 4,
    /// Finite: rare elements (advanced manufacturing).
    RareElement = 5,
}

/// The deterministic behaviour class of a [`SpecialKind`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SpecialClass {
    /// Static, immutable, non-depleting positive resource.
    Field,
    /// Static, immutable danger.
    Hazard,
    /// Depletable stock.
    Finite,
}

/// A colony's awareness of a special resource (capability gate).
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
pub enum Knowledge {
    /// Not yet detected — invisible and unharvestable.
    #[default]
    Unknown = 0,
    /// Detected (visible) but not yet extractable.
    Detected = 1,
    /// Detected and extractable — accrues into the colony stockpile.
    Extractable = 2,
}

impl SpecialKind {
    /// All kinds in index order.
    pub const ALL: [Self; SPECIAL_COUNT] = [
        Self::SolarFlux,
        Self::GravGradient,
        Self::RadiationBelt,
        Self::Anomaly,
        Self::Antimatter,
        Self::RareElement,
    ];

    /// Stable 0-based index (== discriminant). Never reorder.
    #[must_use]
    pub const fn index(self) -> usize {
        self as usize
    }

    /// The deterministic class this kind behaves as.
    #[must_use]
    pub const fn class(self) -> SpecialClass {
        match self {
            Self::SolarFlux | Self::GravGradient => SpecialClass::Field,
            Self::RadiationBelt | Self::Anomaly => SpecialClass::Hazard,
            Self::Antimatter | Self::RareElement => SpecialClass::Finite,
        }
    }
}

/// Static field/hazard intensity (0..=8) at tile `(x, y)`.
///
/// A pure, non-stream-advancing `SplitMix64` hash of `(seed, x, y, kind)`
/// (determinism rule D1): the same tile always yields the same intensity,
/// sampled without touching the RNG stream. Finite kinds return `0` here (they
/// live in map deposits).
#[must_use]
#[allow(
    clippy::cast_possible_truncation,
    reason = "z % 9 is 0..=8 and fits i32 (checked via the modulus)"
)]
pub const fn field_intensity(seed: u64, x: u16, y: u16, kind: SpecialKind) -> Fixed {
    if matches!(kind.class(), SpecialClass::Finite) {
        return Fixed::ZERO;
    }
    let mut z = seed
        ^ (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F)
        ^ (kind as u64).wrapping_mul(0x1656_67B1_9E37_79F9);
    // SplitMix64 finalizer — pure, advances nothing.
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    Fixed::from_int((z % 9) as i32)
}
