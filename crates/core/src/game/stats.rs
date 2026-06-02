//! Combat stat tables and the kinds of units and buildings.
//!
//! These are the balance numbers, expressed in deterministic [`Fixed`] /
//! integer-tick terms. They live in code for now; the `rts-data` crate will load
//! them from `RON` later so balancing is editing a table, not recompiling. The
//! rock-paper-scissors damage matrix is what makes unit composition matter.

use crate::fixed::Fixed;

/// How an attack damages things.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum DamageType {
    /// Small-arms fire: strong vs flesh, weak vs armour.
    Ballistic,
    /// Dedicated anti-armour: strong vs vehicles, weak vs flesh.
    AntiArmor,
    /// High explosive: strong vs structures.
    Explosive,
}

/// How a target resists damage.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum ArmorType {
    /// Infantry.
    Flesh,
    /// Vehicles.
    Plated,
    /// Buildings and walls.
    Structure,
}

/// Number of technology eras (Modern → Interstellar).
pub const ERA_COUNT: usize = 4;

/// Number of factions (Human, Alien).
pub const FACTION_COUNT: usize = 2;

/// The technology era a roster tier belongs to. Later eras upgrade the roster in
/// place; Era 1 (`Modern`) is the game's starting tier.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Era {
    /// 21st-century conventional military (the starting era).
    Modern,
    /// Moon / Mars orbital tier.
    Orbital,
    /// Solar-system / interplanetary tier.
    Interplanetary,
    /// Interstellar tier — the alien-war endgame.
    Interstellar,
}

/// Which side a roster tier belongs to. Aliens mirror human stats in v1 (cosmetic
/// only); the faction axis exists so the rosters can diverge later.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Faction {
    /// Humanity (the player's default side).
    Human,
    /// The alien invaders.
    Alien,
}

impl Era {
    /// Dense index into era-keyed tables, in `0..ERA_COUNT`.
    #[must_use]
    pub const fn index(self) -> usize {
        match self {
            Self::Modern => 0,
            Self::Orbital => 1,
            Self::Interplanetary => 2,
            Self::Interstellar => 3,
        }
    }
}

impl Faction {
    /// Dense index into faction-keyed tables, in `0..FACTION_COUNT`.
    #[must_use]
    pub const fn index(self) -> usize {
        match self {
            Self::Human => 0,
            Self::Alien => 1,
        }
    }
}

// Keep the `*_COUNT` constants in sync with the enums: `index()` is dense and
// the last variant's index must be exactly `COUNT - 1`. A forgotten count bump
// after adding a variant is then a compile error, not a silent table-size bug.
const _: () = assert!(Era::Interstellar.index() + 1 == ERA_COUNT);
const _: () = assert!(Faction::Alien.index() + 1 == FACTION_COUNT);

/// A repeating attack: how hard, what type, how far, how often.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct AttackProfile {
    /// Base damage per shot, before the armour multiplier.
    pub damage: Fixed,
    /// Damage type, matched against the target's [`ArmorType`].
    pub damage_type: DamageType,
    /// Maximum range (world units).
    pub range: Fixed,
    /// Ticks between shots.
    pub period: u32,
    /// Whether this attack can hit ground targets.
    pub targets_ground: bool,
    /// Whether this attack can hit air targets.
    pub targets_air: bool,
}

impl AttackProfile {
    /// A ground-only attack (the common case).
    #[must_use]
    pub const fn ground(damage: Fixed, damage_type: DamageType, range: Fixed, period: u32) -> Self {
        Self {
            damage,
            damage_type,
            range,
            period,
            targets_ground: true,
            targets_air: false,
        }
    }

    /// An air-only attack (anti-air weapons).
    #[must_use]
    pub const fn anti_air(
        damage: Fixed,
        damage_type: DamageType,
        range: Fixed,
        period: u32,
    ) -> Self {
        Self {
            damage,
            damage_type,
            range,
            period,
            targets_ground: false,
            targets_air: true,
        }
    }
}

/// Stats for a mobile unit.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct UnitStats {
    /// Maximum health.
    pub max_hp: Fixed,
    /// Armour class.
    pub armor: ArmorType,
    /// Attack profile (all units can attack).
    pub attack: AttackProfile,
    /// Movement speed in world units per tick.
    pub speed: Fixed,
    /// Credit cost to train.
    pub cost: Fixed,
    /// Ticks to train.
    pub build_time: u32,
    /// Whether this unit flies — only attackable by anti-air, and ignores terrain.
    pub is_air: bool,
}

/// Stats for a building.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct BuildingStats {
    /// Maximum health.
    pub max_hp: Fixed,
    /// Armour class (always [`ArmorType::Structure`]).
    pub armor: ArmorType,
    /// Power produced per tick.
    pub power_produced: i32,
    /// Power consumed per tick.
    pub power_consumed: i32,
    /// Credits generated per tick while powered (refineries).
    pub credit_income: Fixed,
    /// Whether this building can train units (barracks).
    pub produces_units: bool,
    /// Attack profile, if this building is a defensive tower.
    pub attack: Option<AttackProfile>,
    /// Credit cost to construct.
    pub cost: Fixed,
}

/// The kinds of mobile unit.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum UnitKind {
    /// Cheap, fast, anti-flesh swarm.
    Infantry,
    /// Tough, slow, anti-everything via explosives.
    Tank,
    /// Anti-armour specialist.
    AntiArmor,
    /// Flying gunship: strong vs ground, only killable by anti-air.
    Helicopter,
    /// Era-4 capital ship: massive HP and damage.
    Capital,
}

/// The kinds of building.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum BuildingKind {
    /// The base; destroying the enemy's wins the game.
    CommandCenter,
    /// Produces power.
    PowerPlant,
    /// Generates credit income while powered.
    Refinery,
    /// Trains units.
    Barracks,
    /// Defensive anti-ground tower.
    GunTurret,
    /// Defensive anti-air tower.
    AaTurret,
    /// Cheap blocker.
    Wall,
    /// Enables research (consumes power; no attack, no production).
    ResearchLab,
}

/// The rock-paper-scissors damage matrix: how `damage_type` fares against
/// `armor`. `1.0` is neutral; above favours the attacker, below the defender.
#[must_use]
pub const fn damage_multiplier(damage_type: DamageType, armor: ArmorType) -> Fixed {
    match (damage_type, armor) {
        (DamageType::Ballistic, ArmorType::Flesh)
        | (DamageType::Explosive, ArmorType::Structure) => Fixed::from_ratio(3, 2),
        (DamageType::Ballistic, ArmorType::Plated) | (DamageType::AntiArmor, ArmorType::Flesh) => {
            Fixed::from_ratio(1, 2)
        }
        (DamageType::AntiArmor, ArmorType::Plated) => Fixed::from_ratio(7, 4),
        _ => Fixed::ONE,
    }
}

impl UnitKind {
    /// The balance stats for this unit kind.
    #[must_use]
    pub const fn stats(self) -> UnitStats {
        match self {
            Self::Infantry => UnitStats {
                max_hp: Fixed::from_int(50),
                armor: ArmorType::Flesh,
                attack: AttackProfile::ground(
                    Fixed::from_int(6),
                    DamageType::Ballistic,
                    Fixed::from_int(3),
                    8,
                ),
                speed: Fixed::from_ratio(15, 100),
                cost: Fixed::from_int(50),
                build_time: 30,
                is_air: false,
            },
            Self::Tank => UnitStats {
                max_hp: Fixed::from_int(220),
                armor: ArmorType::Plated,
                attack: AttackProfile::ground(
                    Fixed::from_int(30),
                    DamageType::Explosive,
                    Fixed::from_int(4),
                    20,
                ),
                speed: Fixed::from_ratio(10, 100),
                cost: Fixed::from_int(200),
                build_time: 90,
                is_air: false,
            },
            Self::AntiArmor => UnitStats {
                max_hp: Fixed::from_int(70),
                armor: ArmorType::Flesh,
                attack: AttackProfile::ground(
                    Fixed::from_int(22),
                    DamageType::AntiArmor,
                    Fixed::from_int(4),
                    16,
                ),
                speed: Fixed::from_ratio(12, 100),
                cost: Fixed::from_int(110),
                build_time: 50,
                is_air: false,
            },
            Self::Helicopter => UnitStats {
                max_hp: Fixed::from_int(90),
                armor: ArmorType::Plated,
                attack: AttackProfile::ground(
                    Fixed::from_int(16),
                    DamageType::Ballistic,
                    Fixed::from_int(4),
                    9,
                ),
                speed: Fixed::from_ratio(20, 100),
                cost: Fixed::from_int(160),
                build_time: 70,
                is_air: true,
            },
            Self::Capital => UnitStats {
                max_hp: Fixed::from_int(600),
                armor: ArmorType::Plated,
                attack: AttackProfile::ground(
                    Fixed::from_int(40),
                    DamageType::Explosive,
                    Fixed::from_int(6),
                    18,
                ),
                speed: Fixed::from_ratio(8, 100),
                cost: Fixed::from_int(500),
                build_time: 200,
                is_air: false,
            },
        }
    }
}

impl BuildingKind {
    /// The balance stats for this building kind.
    #[must_use]
    pub const fn stats(self) -> BuildingStats {
        // Defaults shared by most structures; overridden per kind below.
        const fn base(max_hp: i32, cost: i32) -> BuildingStats {
            BuildingStats {
                max_hp: Fixed::from_int(max_hp),
                armor: ArmorType::Structure,
                power_produced: 0,
                power_consumed: 0,
                credit_income: Fixed::ZERO,
                produces_units: false,
                attack: None,
                cost: Fixed::from_int(cost),
            }
        }
        match self {
            Self::CommandCenter => base(1000, 0),
            Self::PowerPlant => BuildingStats {
                power_produced: 100,
                ..base(300, 100)
            },
            Self::Refinery => BuildingStats {
                power_consumed: 20,
                credit_income: Fixed::from_int(5),
                ..base(300, 150)
            },
            Self::Barracks => BuildingStats {
                power_consumed: 30,
                produces_units: true,
                ..base(400, 200)
            },
            Self::GunTurret => BuildingStats {
                power_consumed: 25,
                attack: Some(AttackProfile::ground(
                    Fixed::from_int(10),
                    DamageType::Ballistic,
                    Fixed::from_int(5),
                    10,
                )),
                ..base(250, 120)
            },
            Self::AaTurret => BuildingStats {
                power_consumed: 30,
                attack: Some(AttackProfile::anti_air(
                    Fixed::from_int(20),
                    DamageType::AntiArmor,
                    Fixed::from_int(6),
                    8,
                )),
                ..base(220, 140)
            },
            Self::Wall => base(200, 20),
            Self::ResearchLab => BuildingStats {
                power_consumed: 25,
                ..base(300, 250)
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ArmorType, BuildingKind, DamageType, Era, Faction, UnitKind, ERA_COUNT, FACTION_COUNT,
    };
    use crate::fixed::Fixed;

    #[test]
    fn ballistic_is_strong_vs_flesh_weak_vs_plated() {
        assert!(super::damage_multiplier(DamageType::Ballistic, ArmorType::Flesh) > Fixed::ONE);
        assert!(super::damage_multiplier(DamageType::Ballistic, ArmorType::Plated) < Fixed::ONE);
    }

    #[test]
    fn anti_armor_is_strong_vs_plated_weak_vs_flesh() {
        assert!(super::damage_multiplier(DamageType::AntiArmor, ArmorType::Plated) > Fixed::ONE);
        assert!(super::damage_multiplier(DamageType::AntiArmor, ArmorType::Flesh) < Fixed::ONE);
    }

    #[test]
    fn explosive_is_strong_vs_structure() {
        assert!(super::damage_multiplier(DamageType::Explosive, ArmorType::Structure) > Fixed::ONE);
    }

    #[test]
    fn tank_is_tougher_and_costlier_than_infantry() {
        let inf = UnitKind::Infantry.stats();
        let tank = UnitKind::Tank.stats();
        assert!(tank.max_hp > inf.max_hp);
        assert!(tank.cost > inf.cost);
        assert!(inf.speed > tank.speed); // infantry is faster
    }

    #[test]
    fn power_plant_produces_and_refinery_earns() {
        assert!(BuildingKind::PowerPlant.stats().power_produced > 0);
        assert!(BuildingKind::Refinery.stats().credit_income > Fixed::ZERO);
        assert!(BuildingKind::CommandCenter.stats().max_hp > Fixed::from_int(500));
    }

    #[test]
    fn turret_attacks_but_command_center_does_not() {
        assert!(BuildingKind::GunTurret.stats().attack.is_some());
        assert!(BuildingKind::CommandCenter.stats().attack.is_none());
    }

    #[test]
    fn era_and_faction_indices_are_dense_and_in_bounds() {
        assert_eq!(ERA_COUNT, 4);
        assert_eq!(FACTION_COUNT, 2);
        assert_eq!(Era::Modern.index(), 0);
        assert_eq!(Era::Interstellar.index(), 3);
        assert_eq!(Faction::Human.index(), 0);
        assert_eq!(Faction::Alien.index(), 1);
        assert!(Era::Interstellar.index() < ERA_COUNT);
        assert!(Faction::Alien.index() < FACTION_COUNT);
    }
}
