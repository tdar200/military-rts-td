//! Balance-data loading.
//!
//! Loads the game's tunable stats from RON into a [`rts_core`]
//! [`Balance`](rts_core::game::balance::Balance). This is the `std` side that lets
//! you tune the game by editing `balance.ron` instead of recompiling the core.
//! Whole-number fields are literal; `speed_milli` is tiles-per-tick × 1000.

use rts_core::fixed::Fixed;
use rts_core::game::balance::Balance;
use rts_core::game::stats::{ArmorType, AttackProfile, BuildingStats, DamageType, UnitStats};
use serde::Deserialize;

/// The default balance table, embedded at build time.
pub const DEFAULT_RON: &str = include_str!("../balance.ron");

#[derive(Deserialize, Clone, Copy)]
enum ArmorKind {
    Flesh,
    Plated,
    Structure,
}

#[derive(Deserialize, Clone, Copy)]
enum DamageKind {
    Ballistic,
    AntiArmor,
    Explosive,
}

#[must_use]
const fn default_true() -> bool {
    true
}

#[derive(Deserialize)]
struct AttackData {
    damage: i32,
    damage_type: DamageKind,
    range: i32,
    period: u32,
    #[serde(default = "default_true")]
    targets_ground: bool,
    #[serde(default)]
    targets_air: bool,
    /// Area-of-effect blast radius in whole tiles. `0` (the default, so older
    /// RON without the key still parses) means a single-target weapon.
    #[serde(default)]
    splash_radius: i32,
    /// Splash damage fraction in milli (`500` = 0.5). Ignored when
    /// `splash_radius == 0`. Defaults to `0`.
    #[serde(default)]
    splash_falloff_milli: i64,
}

#[derive(Deserialize)]
struct UnitData {
    max_hp: i32,
    armor: ArmorKind,
    attack: AttackData,
    speed_milli: i32,
    /// Money cost to train (the RON field stays `cost`).
    cost: i32,
    #[serde(default)]
    energy_cost: i32,
    #[serde(default)]
    labour_cost: i32,
    build_time: u32,
    #[serde(default)]
    is_air: bool,
}

#[derive(Deserialize)]
struct BuildingData {
    max_hp: i32,
    #[serde(default)]
    energy_output: i32,
    #[serde(default)]
    labour_output: i32,
    produces_units: bool,
    attack: Option<AttackData>,
    /// Money cost to construct (the RON field stays `cost`).
    cost: i32,
    #[serde(default)]
    energy_cost: i32,
    #[serde(default)]
    labour_cost: i32,
    #[serde(default)]
    mine_rate: i32,
}

#[derive(Deserialize)]
struct BalanceData {
    infantry: UnitData,
    tank: UnitData,
    anti_armor: UnitData,
    helicopter: UnitData,
    capital: UnitData,
    command_center: BuildingData,
    power_plant: BuildingData,
    refinery: BuildingData,
    barracks: BuildingData,
    gun_turret: BuildingData,
    aa_turret: BuildingData,
    wall: BuildingData,
    research_lab: BuildingData,
    antimatter_plant: BuildingData,
    /// Fraction (× 1000) of a `CommandCenter`'s max HP a captured seat is left at.
    /// `250` = 0.25. Config only; not part of `state_hash`. Defaults to 250 so
    /// older RON without the key still parses.
    #[serde(default = "default_capture_hp_milli")]
    capture_hp_fraction: i64,
}

#[must_use]
const fn default_capture_hp_milli() -> i64 {
    250
}

const fn to_armor(a: ArmorKind) -> ArmorType {
    match a {
        ArmorKind::Flesh => ArmorType::Flesh,
        ArmorKind::Plated => ArmorType::Plated,
        ArmorKind::Structure => ArmorType::Structure,
    }
}

const fn to_damage(d: DamageKind) -> DamageType {
    match d {
        DamageKind::Ballistic => DamageType::Ballistic,
        DamageKind::AntiArmor => DamageType::AntiArmor,
        DamageKind::Explosive => DamageType::Explosive,
    }
}

const fn to_attack(a: &AttackData) -> AttackProfile {
    AttackProfile {
        damage: Fixed::from_int(a.damage),
        damage_type: to_damage(a.damage_type),
        range: Fixed::from_int(a.range),
        period: a.period,
        targets_ground: a.targets_ground,
        targets_air: a.targets_air,
        splash_radius: Fixed::from_int(a.splash_radius),
        splash_falloff: Fixed::from_ratio(a.splash_falloff_milli, 1000),
    }
}

fn to_unit(u: &UnitData) -> UnitStats {
    UnitStats {
        max_hp: Fixed::from_int(u.max_hp),
        armor: to_armor(u.armor),
        attack: to_attack(&u.attack),
        speed: Fixed::from_ratio(i64::from(u.speed_milli), 1000),
        money_cost: Fixed::from_int(u.cost),
        energy_cost: Fixed::from_int(u.energy_cost),
        labour_cost: Fixed::from_int(u.labour_cost),
        build_time: u.build_time,
        is_air: u.is_air,
    }
}

fn to_building(b: &BuildingData) -> BuildingStats {
    BuildingStats {
        max_hp: Fixed::from_int(b.max_hp),
        armor: ArmorType::Structure,
        energy_output: b.energy_output,
        labour_output: b.labour_output,
        produces_units: b.produces_units,
        attack: b.attack.as_ref().map(to_attack),
        money_cost: Fixed::from_int(b.cost),
        energy_cost: Fixed::from_int(b.energy_cost),
        labour_cost: Fixed::from_int(b.labour_cost),
        mine_rate: b.mine_rate,
    }
}

/// Parses a balance table from a RON string.
///
/// # Errors
/// Returns the RON parse error if `ron_str` is malformed or missing fields.
pub fn load(ron_str: &str) -> Result<Balance, ron::error::SpannedError> {
    let data: BalanceData = ron::from_str(ron_str)?;
    Ok(Balance::from_tables(
        [
            to_unit(&data.infantry),
            to_unit(&data.tank),
            to_unit(&data.anti_armor),
            to_unit(&data.helicopter),
            to_unit(&data.capital),
        ],
        [
            to_building(&data.command_center),
            to_building(&data.power_plant),
            to_building(&data.refinery),
            to_building(&data.barracks),
            to_building(&data.gun_turret),
            to_building(&data.aa_turret),
            to_building(&data.wall),
            to_building(&data.research_lab),
            to_building(&data.antimatter_plant),
        ],
        Fixed::from_ratio(data.capture_hp_fraction, 1000),
    ))
}

/// Loads the embedded default balance.
///
/// # Panics
/// Panics only if the embedded `balance.ron` is malformed, which the test suite
/// guards against — so in practice this never panics.
#[must_use]
pub fn load_default() -> Balance {
    load(DEFAULT_RON).expect("embedded balance.ron must parse")
}

#[cfg(test)]
mod tests {
    use super::{load, load_default, DEFAULT_RON};
    use rts_core::fixed::Fixed;
    use rts_core::game::balance::Balance;
    use rts_core::game::stats::UnitKind;

    #[test]
    fn default_ron_matches_the_code_default() {
        assert_eq!(load_default(), Balance::default());
    }

    #[test]
    fn tweaking_a_value_takes_effect_without_recompiling_core() {
        let tweaked = DEFAULT_RON.replace("max_hp: 50,", "max_hp: 999,");
        let balance = load(&tweaked).expect("tweaked ron parses");
        assert_eq!(
            balance.unit(UnitKind::Infantry).max_hp,
            Fixed::from_int(999)
        );
        assert_ne!(balance, Balance::default());
    }

    #[test]
    fn malformed_ron_is_an_error() {
        assert!(load("(not valid").is_err());
    }
}
