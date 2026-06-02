//! Runtime balance table.
//!
//! All tunable stats live in a [`Balance`] instance the [`Sim`](crate::game::sim::Sim)
//! reads from, instead of hard-coded calls. The defaults mirror the canonical
//! numbers in [`stats`](crate::game::stats), but a `Balance` can also be built from
//! data (see the `rts-data` crate, which loads one from RON) so balancing is
//! editing a table, not recompiling.

use crate::game::stats::{BuildingKind, BuildingStats, UnitKind, UnitStats};

/// A complete set of unit and building stats.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Balance {
    units: [UnitStats; 4],
    buildings: [BuildingStats; 7],
}

impl Balance {
    /// The default balance — the canonical numbers from [`stats`](crate::game::stats).
    #[must_use]
    pub const fn const_default() -> Self {
        Self {
            units: [
                UnitKind::Infantry.stats(),
                UnitKind::Tank.stats(),
                UnitKind::AntiArmor.stats(),
                UnitKind::Helicopter.stats(),
            ],
            buildings: [
                BuildingKind::CommandCenter.stats(),
                BuildingKind::PowerPlant.stats(),
                BuildingKind::Refinery.stats(),
                BuildingKind::Barracks.stats(),
                BuildingKind::GunTurret.stats(),
                BuildingKind::AaTurret.stats(),
                BuildingKind::Wall.stats(),
            ],
        }
    }

    /// Builds a balance from explicit tables (used by data loaders).
    #[must_use]
    pub const fn from_tables(units: [UnitStats; 4], buildings: [BuildingStats; 7]) -> Self {
        Self { units, buildings }
    }

    /// Stats for a unit kind.
    #[must_use]
    pub const fn unit(&self, kind: UnitKind) -> UnitStats {
        match kind {
            UnitKind::Infantry => self.units[0],
            UnitKind::Tank => self.units[1],
            UnitKind::AntiArmor => self.units[2],
            UnitKind::Helicopter => self.units[3],
        }
    }

    /// Stats for a building kind.
    #[must_use]
    pub const fn building(&self, kind: BuildingKind) -> BuildingStats {
        match kind {
            BuildingKind::CommandCenter => self.buildings[0],
            BuildingKind::PowerPlant => self.buildings[1],
            BuildingKind::Refinery => self.buildings[2],
            BuildingKind::Barracks => self.buildings[3],
            BuildingKind::GunTurret => self.buildings[4],
            BuildingKind::AaTurret => self.buildings[5],
            BuildingKind::Wall => self.buildings[6],
        }
    }
}

impl Default for Balance {
    fn default() -> Self {
        Self::const_default()
    }
}

#[cfg(test)]
mod tests {
    use super::Balance;
    use crate::game::stats::{BuildingKind, UnitKind};

    #[test]
    fn default_balance_matches_canonical_stats() {
        let b = Balance::default();
        assert_eq!(b.unit(UnitKind::Tank), UnitKind::Tank.stats());
        assert_eq!(
            b.building(BuildingKind::Refinery),
            BuildingKind::Refinery.stats()
        );
    }
}
