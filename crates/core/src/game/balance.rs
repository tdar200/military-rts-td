//! Runtime balance table.
//!
//! All tunable stats live in a [`Balance`] instance the [`Sim`](crate::game::sim::Sim)
//! reads from, instead of hard-coded calls. The defaults mirror the canonical
//! numbers in [`stats`](crate::game::stats), but a `Balance` can also be built from
//! data (see the `rts-data` crate, which loads one from RON) so balancing is
//! editing a table, not recompiling.

use crate::game::stats::{
    BuildingKind, BuildingStats, Era, Faction, UnitKind, UnitStats, ERA_COUNT, FACTION_COUNT,
};

/// A complete set of unit and building stats, keyed by `[era][faction]`.
///
/// Every era/faction tier is currently a copy of the canonical Modern/Human
/// numbers in [`stats`](crate::game::stats); per-era and per-faction divergence
/// is introduced in a later phase. The plain [`unit`](Balance::unit) /
/// [`building`](Balance::building) accessors read the Modern/Human tier so the
/// `Sim`'s existing call sites are unaffected.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Balance {
    units: [[[UnitStats; 5]; FACTION_COUNT]; ERA_COUNT],
    buildings: [[[BuildingStats; 9]; FACTION_COUNT]; ERA_COUNT],
}

impl Balance {
    /// The default balance — the canonical numbers from [`stats`](crate::game::stats),
    /// replicated across every era and faction.
    #[must_use]
    pub const fn const_default() -> Self {
        Self::from_tables(
            [
                UnitKind::Infantry.stats(),
                UnitKind::Tank.stats(),
                UnitKind::AntiArmor.stats(),
                UnitKind::Helicopter.stats(),
                UnitKind::Capital.stats(),
            ],
            [
                BuildingKind::CommandCenter.stats(),
                BuildingKind::PowerPlant.stats(),
                BuildingKind::Refinery.stats(),
                BuildingKind::Barracks.stats(),
                BuildingKind::GunTurret.stats(),
                BuildingKind::AaTurret.stats(),
                BuildingKind::Wall.stats(),
                BuildingKind::ResearchLab.stats(),
                BuildingKind::AntimatterPlant.stats(),
            ],
        )
    }

    /// Builds a balance from one canonical (Modern/Human) tier, replicated across
    /// every era and faction. Used by data loaders; per-era/faction divergence is
    /// introduced in a later phase.
    #[must_use]
    pub const fn from_tables(units: [UnitStats; 5], buildings: [BuildingStats; 9]) -> Self {
        Self {
            units: [[units; FACTION_COUNT]; ERA_COUNT],
            buildings: [[buildings; FACTION_COUNT]; ERA_COUNT],
        }
    }

    /// Stats for a unit kind in a given era and faction.
    #[must_use]
    pub const fn unit_in(&self, era: Era, faction: Faction, kind: UnitKind) -> UnitStats {
        let tier = self.units[era.index()][faction.index()];
        match kind {
            UnitKind::Infantry => tier[0],
            UnitKind::Tank => tier[1],
            UnitKind::AntiArmor => tier[2],
            UnitKind::Helicopter => tier[3],
            UnitKind::Capital => tier[4],
        }
    }

    /// Stats for a building kind in a given era and faction.
    #[must_use]
    pub const fn building_in(
        &self,
        era: Era,
        faction: Faction,
        kind: BuildingKind,
    ) -> BuildingStats {
        let tier = self.buildings[era.index()][faction.index()];
        match kind {
            BuildingKind::CommandCenter => tier[0],
            BuildingKind::PowerPlant => tier[1],
            BuildingKind::Refinery => tier[2],
            BuildingKind::Barracks => tier[3],
            BuildingKind::GunTurret => tier[4],
            BuildingKind::AaTurret => tier[5],
            BuildingKind::Wall => tier[6],
            BuildingKind::ResearchLab => tier[7],
            BuildingKind::AntimatterPlant => tier[8],
        }
    }

    /// Stats for a unit kind in the default (Modern era, Human faction) tier.
    #[must_use]
    pub const fn unit(&self, kind: UnitKind) -> UnitStats {
        self.unit_in(Era::Modern, Faction::Human, kind)
    }

    /// Stats for a building kind in the default (Modern era, Human faction) tier.
    #[must_use]
    pub const fn building(&self, kind: BuildingKind) -> BuildingStats {
        self.building_in(Era::Modern, Faction::Human, kind)
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
    use crate::game::stats::{BuildingKind, Era, Faction, UnitKind};

    const ERAS: [Era; 4] = [
        Era::Modern,
        Era::Orbital,
        Era::Interplanetary,
        Era::Interstellar,
    ];
    const FACTIONS: [Faction; 2] = [Faction::Human, Faction::Alien];
    const UNIT_KINDS: [UnitKind; 5] = [
        UnitKind::Infantry,
        UnitKind::Tank,
        UnitKind::AntiArmor,
        UnitKind::Helicopter,
        UnitKind::Capital,
    ];
    const BUILDING_KINDS: [BuildingKind; 9] = [
        BuildingKind::CommandCenter,
        BuildingKind::PowerPlant,
        BuildingKind::Refinery,
        BuildingKind::Barracks,
        BuildingKind::GunTurret,
        BuildingKind::AaTurret,
        BuildingKind::Wall,
        BuildingKind::ResearchLab,
        BuildingKind::AntimatterPlant,
    ];

    #[test]
    fn default_balance_matches_canonical_stats() {
        let b = Balance::default();
        assert_eq!(b.unit(UnitKind::Tank), UnitKind::Tank.stats());
        assert_eq!(
            b.building(BuildingKind::Refinery),
            BuildingKind::Refinery.stats()
        );
    }

    #[test]
    fn every_era_and_faction_returns_canonical_stats_for_now() {
        let b = Balance::default();
        for era in ERAS {
            for faction in FACTIONS {
                for kind in UNIT_KINDS {
                    assert_eq!(b.unit_in(era, faction, kind), kind.stats());
                }
                for kind in BUILDING_KINDS {
                    assert_eq!(b.building_in(era, faction, kind), kind.stats());
                }
            }
        }
    }

    #[test]
    fn research_lab_exists_and_costs_money() {
        use crate::game::stats::BuildingKind;
        let b = Balance::default();
        let st = b.building(BuildingKind::ResearchLab);
        assert!(!st.produces_units);
        assert!(st.attack.is_none());
        assert!(st.money_cost > crate::fixed::Fixed::ZERO);
    }

    #[test]
    fn antimatter_plant_is_a_money_extractor() {
        use crate::game::stats::BuildingKind;
        let st = BuildingKind::AntimatterPlant.stats();
        // Repurposed as a plain money extractor: mines deposits, no passive income.
        assert!(st.mine_rate > 0);
        assert!(!st.produces_units && st.attack.is_none());
    }

    #[test]
    fn capital_ship_is_a_heavy_unit() {
        use crate::game::stats::UnitKind;
        let cap = UnitKind::Capital.stats();
        let tank = UnitKind::Tank.stats();
        assert!(cap.max_hp > tank.max_hp);
        assert!(cap.attack.damage > tank.attack.damage);
    }

    #[test]
    fn alien_mirrors_human_in_every_era() {
        // v1 invariant: aliens are a cosmetic mirror — identical stats to humans.
        let b = Balance::default();
        for era in ERAS {
            for kind in UNIT_KINDS {
                assert_eq!(
                    b.unit_in(era, Faction::Human, kind),
                    b.unit_in(era, Faction::Alien, kind)
                );
            }
            for kind in BUILDING_KINDS {
                assert_eq!(
                    b.building_in(era, Faction::Human, kind),
                    b.building_in(era, Faction::Alien, kind)
                );
            }
        }
    }
}
