//! The research tech tree — global, per-player upgrades.
//!
//! Techs are code constants (ids are array indices). Each tech adds a flat
//! `bonus` to its `branch`; a player's total branch bonus is the sum of the
//! bonuses of the techs they've researched. Effects are applied live at
//! combat/economy/movement resolution, never by mutating unit stats.

use crate::fixed::Fixed;

/// Number of techs in the tree.
pub const TECH_COUNT: usize = 10;

/// Which global stat a tech improves.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum TechBranch {
    /// Adds flat damage to all of the player's attacks.
    Weapons,
    /// Subtracts flat damage from all incoming hits (clamped above zero).
    Armor,
    /// Adds flat credit income per tick.
    Economy,
    /// Adds flat move speed (tiles/tick) to the player's units.
    Mobility,
}

/// One research upgrade.
///
/// `PartialEq`/`Eq` are intentionally absent: [`Fixed`] does not implement them.
/// Use [`TechDef::id`] for identity comparisons.
#[derive(Clone, Copy, Debug)]
pub struct TechDef {
    /// Stable id; equals the index into [`TECHS`].
    pub id: u32,
    /// Display name.
    pub name: &'static str,
    /// Which branch this improves.
    pub branch: TechBranch,
    /// Credit cost to research.
    pub cost: Fixed,
    /// Research duration in ticks.
    pub duration: u32,
    /// Tech that must be researched first (always an earlier index, same branch).
    pub prereq: Option<u32>,
    /// Flat bonus added to the branch total when researched.
    pub bonus: Fixed,
}

/// The full tech tree. Balance numbers are first-pass; tune via the playtest harness.
pub const TECHS: [TechDef; TECH_COUNT] = [
    TechDef {
        id: 0,
        name: "Weapons I",
        branch: TechBranch::Weapons,
        cost: Fixed::from_int(200),
        duration: 300,
        prereq: None,
        bonus: Fixed::from_int(2),
    },
    TechDef {
        id: 1,
        name: "Weapons II",
        branch: TechBranch::Weapons,
        cost: Fixed::from_int(350),
        duration: 450,
        prereq: Some(0),
        bonus: Fixed::from_int(2),
    },
    TechDef {
        id: 2,
        name: "Weapons III",
        branch: TechBranch::Weapons,
        cost: Fixed::from_int(500),
        duration: 600,
        prereq: Some(1),
        bonus: Fixed::from_int(3),
    },
    TechDef {
        id: 3,
        name: "Armor I",
        branch: TechBranch::Armor,
        cost: Fixed::from_int(200),
        duration: 300,
        prereq: None,
        bonus: Fixed::from_int(1),
    },
    TechDef {
        id: 4,
        name: "Armor II",
        branch: TechBranch::Armor,
        cost: Fixed::from_int(350),
        duration: 450,
        prereq: Some(3),
        bonus: Fixed::from_int(1),
    },
    TechDef {
        id: 5,
        name: "Armor III",
        branch: TechBranch::Armor,
        cost: Fixed::from_int(500),
        duration: 600,
        prereq: Some(4),
        bonus: Fixed::from_int(2),
    },
    TechDef {
        id: 6,
        name: "Economy I",
        branch: TechBranch::Economy,
        cost: Fixed::from_int(250),
        duration: 450,
        prereq: None,
        bonus: Fixed::from_int(1),
    },
    TechDef {
        id: 7,
        name: "Economy II",
        branch: TechBranch::Economy,
        cost: Fixed::from_int(400),
        duration: 600,
        prereq: Some(6),
        bonus: Fixed::from_int(1),
    },
    TechDef {
        id: 8,
        name: "Mobility I",
        branch: TechBranch::Mobility,
        cost: Fixed::from_int(200),
        duration: 360,
        prereq: None,
        bonus: Fixed::from_ratio(2, 100), // 0.02 tiles/tick
    },
    TechDef {
        id: 9,
        name: "Mobility II",
        branch: TechBranch::Mobility,
        cost: Fixed::from_int(350),
        duration: 480,
        prereq: Some(8),
        bonus: Fixed::from_ratio(2, 100), // 0.02 tiles/tick
    },
];

// Keep TECH_COUNT in sync with the table: the last tech's id must be the last
// index. A forgotten count bump or a mis-numbered id is then a compile error.
const _: () = assert!(TECHS[TECH_COUNT - 1].id as usize == TECH_COUNT - 1);

/// Look up a tech by id.
#[must_use]
pub const fn tech(id: u32) -> Option<&'static TechDef> {
    if (id as usize) < TECH_COUNT {
        Some(&TECHS[id as usize])
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::{tech, TechBranch, TECHS, TECH_COUNT};

    #[test]
    fn tree_is_well_formed() {
        assert_eq!(TECHS.len(), TECH_COUNT);
        for (i, t) in TECHS.iter().enumerate() {
            assert_eq!(t.id as usize, i, "tech id must equal its index");
            if let Some(p) = t.prereq {
                assert!((p as usize) < i, "prereq must come earlier in the array");
                assert_eq!(
                    TECHS[p as usize].branch, t.branch,
                    "prereq must be in the same branch"
                );
            }
        }
        assert!(tech(0).is_some());
        assert!(tech(u32::try_from(TECH_COUNT).unwrap()).is_none());
        assert_eq!(tech(0).unwrap().branch, TechBranch::Weapons);
    }
}
