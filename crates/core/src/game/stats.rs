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
    /// Area-of-effect blast radius (world units) around the primary target.
    /// `Fixed::ZERO` means a single-target weapon (no splash) — the default for
    /// every profile except the Capital ship's main gun.
    pub splash_radius: Fixed,
    /// Fraction (`0..=1`) of the primary hit's damage that each enemy within
    /// `splash_radius` of the primary target takes. Ignored when
    /// `splash_radius == ZERO`.
    pub splash_falloff: Fixed,
}

impl AttackProfile {
    /// A ground-only attack (the common case). Single-target by default
    /// (`splash_radius == ZERO`); use [`Self::with_splash`] to add area damage.
    #[must_use]
    pub const fn ground(damage: Fixed, damage_type: DamageType, range: Fixed, period: u32) -> Self {
        Self {
            damage,
            damage_type,
            range,
            period,
            targets_ground: true,
            targets_air: false,
            splash_radius: Fixed::ZERO,
            splash_falloff: Fixed::ZERO,
        }
    }

    /// An air-only attack (anti-air weapons). Single-target by default.
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
            splash_radius: Fixed::ZERO,
            splash_falloff: Fixed::ZERO,
        }
    }

    /// Returns this profile with an area-of-effect blast: enemies within
    /// `splash_radius` of the primary target take `splash_falloff` of the hit.
    #[must_use]
    pub const fn with_splash(mut self, splash_radius: Fixed, splash_falloff: Fixed) -> Self {
        self.splash_radius = splash_radius;
        self.splash_falloff = splash_falloff;
        self
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
    /// Money cost to train.
    pub money_cost: Fixed,
    /// Energy cost to train (first-pass 0 for legacy units; priced with grid content).
    pub energy_cost: Fixed,
    /// Labour (population) cost to train.
    pub labour_cost: Fixed,
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
    /// Energy added to the owner's stockpile per tick (power buildings).
    pub energy_output: i32,
    /// Labour (population) produced per tick (housing / civic buildings).
    pub labour_output: i32,
    /// Whether this building can train units (barracks).
    pub produces_units: bool,
    /// Attack profile, if this building is a defensive tower.
    pub attack: Option<AttackProfile>,
    /// Money cost to construct.
    pub money_cost: Fixed,
    /// Energy cost to construct (first-pass 0 for legacy buildings).
    pub energy_cost: Fixed,
    /// Labour cost to construct (first-pass 0 for legacy buildings).
    pub labour_cost: Fixed,
    /// Money/tick this building mines from a deposit it stands on (Extractors).
    pub mine_rate: i32,
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
    /// The base; destroying the enemy's wins the game. Produces base Labour.
    CommandCenter,
    /// Feeds the spendable Energy stockpile.
    PowerPlant,
    /// Mines Money from a deposit it stands on.
    Refinery,
    /// Trains units; also produces a little Labour.
    Barracks,
    /// Defensive anti-ground tower.
    GunTurret,
    /// Defensive anti-air tower.
    AaTurret,
    /// Cheap blocker.
    Wall,
    /// Enables research (gates tier-1+ tech; no attack, no production).
    ResearchLab,
    /// A second Money extractor (repurposed; mines deposits).
    AntimatterPlant,
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
    /// Stable 0-based index, for unlock bitmasks and tech wiring. Never reorder.
    #[must_use]
    pub const fn index(self) -> u32 {
        match self {
            Self::Infantry => 0,
            Self::Tank => 1,
            Self::AntiArmor => 2,
            Self::Helicopter => 3,
            Self::Capital => 4,
        }
    }

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
                speed: Fixed::from_ratio(15, 200),
                money_cost: Fixed::from_int(50),
                energy_cost: Fixed::ZERO,
                labour_cost: Fixed::from_int(1),
                build_time: 90,
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
                speed: Fixed::from_ratio(10, 200),
                money_cost: Fixed::from_int(200),
                energy_cost: Fixed::from_int(12),
                labour_cost: Fixed::from_int(2),
                build_time: 270,
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
                speed: Fixed::from_ratio(12, 200),
                money_cost: Fixed::from_int(110),
                energy_cost: Fixed::from_int(4),
                labour_cost: Fixed::from_int(1),
                build_time: 150,
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
                speed: Fixed::from_ratio(20, 200),
                money_cost: Fixed::from_int(160),
                energy_cost: Fixed::from_int(16),
                labour_cost: Fixed::from_int(2),
                build_time: 210,
                is_air: true,
            },
            Self::Capital => UnitStats {
                max_hp: Fixed::from_int(600),
                armor: ArmorType::Plated,
                // The capital's main gun is the only weapon with area splash:
                // a 2-tile blast where neighbours of the primary target take
                // 50% damage. This punishes clumped armies — every other unit /
                // building stays single-target (splash radius ZERO), so the
                // golden run (no Capital) is behaviour-identical.
                attack: AttackProfile::ground(
                    Fixed::from_int(40),
                    DamageType::Explosive,
                    Fixed::from_int(6),
                    18,
                )
                .with_splash(Fixed::from_int(2), Fixed::from_ratio(1, 2)),
                speed: Fixed::from_ratio(8, 200),
                money_cost: Fixed::from_int(500),
                energy_cost: Fixed::from_int(40),
                labour_cost: Fixed::from_int(5),
                build_time: 600,
                is_air: false,
            },
        }
    }
}

impl BuildingKind {
    /// Stable 0-based index, for unlock bitmasks and tech wiring. Never reorder.
    #[must_use]
    pub const fn index(self) -> u32 {
        match self {
            Self::CommandCenter => 0,
            Self::PowerPlant => 1,
            Self::Refinery => 2,
            Self::Barracks => 3,
            Self::GunTurret => 4,
            Self::AaTurret => 5,
            Self::Wall => 6,
            Self::ResearchLab => 7,
            Self::AntimatterPlant => 8,
        }
    }

    /// The balance stats for this building kind.
    #[must_use]
    pub const fn stats(self) -> BuildingStats {
        // Defaults shared by most structures; overridden per kind below.
        const fn base(max_hp: i32, money_cost: i32) -> BuildingStats {
            BuildingStats {
                max_hp: Fixed::from_int(max_hp),
                armor: ArmorType::Structure,
                energy_output: 0,
                labour_output: 0,
                produces_units: false,
                attack: None,
                money_cost: Fixed::from_int(money_cost),
                energy_cost: Fixed::ZERO,
                labour_cost: Fixed::ZERO,
                mine_rate: 0,
            }
        }
        match self {
            // The HQ produces base population (Labour) every tick.
            Self::CommandCenter => BuildingStats {
                labour_output: 2,
                ..base(1000, 0)
            },
            // The power building feeds the spendable Energy stockpile (the bite
            // comes from a moderate flow that production/expansion can outrun).
            Self::PowerPlant => BuildingStats {
                energy_output: 40,
                ..base(300, 100)
            },
            Self::Refinery => BuildingStats {
                mine_rate: 2,
                energy_cost: Fixed::from_int(8),
                ..base(300, 150)
            },
            Self::Barracks => BuildingStats {
                produces_units: true,
                labour_output: 1,
                energy_cost: Fixed::from_int(15),
                ..base(400, 200)
            },
            Self::GunTurret => BuildingStats {
                attack: Some(AttackProfile::ground(
                    Fixed::from_int(10),
                    DamageType::Ballistic,
                    Fixed::from_int(5),
                    10,
                )),
                energy_cost: Fixed::from_int(10),
                ..base(250, 120)
            },
            Self::AaTurret => BuildingStats {
                attack: Some(AttackProfile::anti_air(
                    Fixed::from_int(20),
                    DamageType::AntiArmor,
                    Fixed::from_int(6),
                    8,
                )),
                energy_cost: Fixed::from_int(12),
                ..base(220, 140)
            },
            Self::Wall => base(200, 20),
            // The lab is now just a research prerequisite building.
            Self::ResearchLab => BuildingStats {
                energy_cost: Fixed::from_int(20),
                ..base(300, 250)
            },
            // Repurposed as a plain money extractor (mines deposits).
            Self::AntimatterPlant => BuildingStats {
                mine_rate: 2,
                energy_cost: Fixed::from_int(12),
                ..base(300, 200)
            },
        }
    }
}

// Unlock bitmasks (sim.rs) are u16, indexed by `index()`. Keep every kind under
// bit 16 so a future variant can't silently alias another's unlock bit.
const _: () = assert!(BuildingKind::AntimatterPlant.index() < 16);
const _: () = assert!(UnitKind::Capital.index() < 16);

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
        assert!(tank.money_cost > inf.money_cost);
        assert!(inf.speed > tank.speed); // infantry is faster
    }

    #[test]
    fn power_plant_outputs_energy_and_refinery_mines() {
        assert!(BuildingKind::PowerPlant.stats().energy_output > 0);
        assert!(BuildingKind::Refinery.stats().mine_rate > 0);
        // The HQ produces base population (Labour).
        assert!(BuildingKind::CommandCenter.stats().labour_output > 0);
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
