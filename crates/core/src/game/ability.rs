//! Active unit abilities — the tactical "buttons" of combat.
//!
//! A flat data table in the style of [`crate::game::tech`]: each heavy unit kind
//! carries one ability, cast with [`crate::game::sim::Command::UseAbility`] at a
//! world position within range. Effects resolve instantly and deterministically
//! (fixed magnitudes, no RNG); the per-entity cooldown is tick-based, hashed, and
//! the rate limiter. Stuns are a per-entity tick counter, also hashed.

use crate::fixed::Fixed;
use crate::game::stats::UnitKind;

/// Every ability, for exhaustive table checks (tests iterate this so a future
/// variant cannot ship without sane tuning numbers).
pub const ALL_ABILITIES: [AbilityKind; 3] = [
    AbilityKind::Barrage,
    AbilityKind::EmpBurst,
    AbilityKind::NaniteField,
];

/// Which ability a unit casts.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AbilityKind {
    /// Tank: a shell volley — area damage at the target point. Anti-swarm siege.
    Barrage,
    /// Helicopter: an electromagnetic pulse — stuns enemy units around the target
    /// (no move, no fire) for the duration. Crowd control.
    EmpBurst,
    /// Capital: a nanite repair field — heals friendly units around the target.
    NaniteField,
}

/// The tuning numbers for one ability. All times are 30 Hz ticks.
#[derive(Clone, Copy, Debug)]
pub struct AbilityDef {
    /// Ticks between casts (per casting unit).
    pub cooldown: u32,
    /// Maximum cast distance from the casting unit to the target point.
    pub range: Fixed,
    /// Effect radius around the target point.
    pub radius: Fixed,
    /// Damage (`Barrage`) or healing (`NaniteField`); unused for `EmpBurst`.
    pub magnitude: Fixed,
    /// Stun length in ticks (`EmpBurst`); 0 for instant effects.
    pub duration: u32,
}

/// The ability each unit kind carries, if any. Light units have none — their
/// strength is numbers; the heavies each get one tactical tool.
#[must_use]
pub const fn ability_for(unit: UnitKind) -> Option<AbilityKind> {
    match unit {
        UnitKind::Tank => Some(AbilityKind::Barrage),
        UnitKind::Helicopter => Some(AbilityKind::EmpBurst),
        UnitKind::Capital => Some(AbilityKind::NaniteField),
        UnitKind::Infantry | UnitKind::AntiArmor => None,
    }
}

/// The tuning table for `kind`.
#[must_use]
pub const fn def(kind: AbilityKind) -> AbilityDef {
    match kind {
        // Half a shell's damage, but applied to EVERYTHING in the blast — pays off
        // against clumps (a survival wave) where the single-target gun does not.
        // Tuned tactical, not nuclear: an early cut (30 dmg / radius 2) let five
        // wave-tanks delete a packed 68-unit army inside one wave interval.
        AbilityKind::Barrage => AbilityDef {
            cooldown: 360, // 12 s
            range: Fixed::from_int(6),
            radius: Fixed::from_ratio(3, 2),
            magnitude: Fixed::from_int(16),
            duration: 0,
        },
        // 1.5 s of silence from a knot of attackers; the long cooldown keeps it a
        // decision, not a rotation (3 s stuns chain-locked whole armies).
        AbilityKind::EmpBurst => AbilityDef {
            cooldown: 600, // 20 s
            range: Fixed::from_int(5),
            radius: Fixed::from_ratio(3, 2),
            magnitude: Fixed::ZERO,
            duration: 45, // 1.5 s
        },
        // A meaningful chunk of HP across the front line (full heal for infantry,
        // ~a quarter of a Tank).
        AbilityKind::NaniteField => AbilityDef {
            cooldown: 300, // 10 s
            range: Fixed::from_int(5),
            radius: Fixed::from_int(3),
            magnitude: Fixed::from_int(60),
            duration: 0,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{ability_for, def, AbilityKind};
    use crate::game::stats::UnitKind;

    #[test]
    fn heavies_have_abilities_and_lights_do_not() {
        assert_eq!(ability_for(UnitKind::Tank), Some(AbilityKind::Barrage));
        assert_eq!(
            ability_for(UnitKind::Helicopter),
            Some(AbilityKind::EmpBurst)
        );
        assert_eq!(
            ability_for(UnitKind::Capital),
            Some(AbilityKind::NaniteField)
        );
        assert_eq!(ability_for(UnitKind::Infantry), None);
        assert_eq!(ability_for(UnitKind::AntiArmor), None);
    }

    #[test]
    fn defs_are_sane() {
        for kind in super::ALL_ABILITIES {
            let d = def(kind);
            assert!(d.cooldown > 0, "{kind:?}: cooldown must rate-limit");
            assert!(d.range.to_bits() > 0, "{kind:?}: needs a cast range");
            assert!(d.radius.to_bits() > 0, "{kind:?}: needs an effect radius");
        }
        // Only the stun has a duration; only damage/heal have a magnitude.
        assert!(def(AbilityKind::EmpBurst).duration > 0);
        assert!(def(AbilityKind::Barrage).magnitude.to_bits() > 0);
        assert!(def(AbilityKind::NaniteField).magnitude.to_bits() > 0);
    }
}
