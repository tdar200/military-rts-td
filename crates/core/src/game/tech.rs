//! The research tech tree — global, per-player upgrades.
//!
//! Techs are code constants (ids are array indices). Each tech adds a flat
//! `bonus` to its `branch`; a player's total branch bonus is the sum of the
//! bonuses of the techs they've researched. Effects are applied live at
//! combat/economy/movement resolution, never by mutating unit stats.

use crate::fixed::Fixed;

/// Number of techs in the tree.
pub const TECH_COUNT: usize = 19;

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
    /// Advances the player to the next era.
    Era,
    /// Adds to the player's max energy shield.
    Shields,
    /// Lets the player's units ignore terrain for movement.
    AntiGrav,
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
    TechDef {
        id: 10,
        name: "Reach Orbital",
        branch: TechBranch::Era,
        cost: Fixed::from_int(500),
        duration: 600,
        prereq: None,
        bonus: Fixed::ZERO,
    },
    TechDef {
        id: 11,
        name: "Reach Interplanetary",
        branch: TechBranch::Era,
        cost: Fixed::from_int(800),
        duration: 800,
        prereq: Some(10),
        bonus: Fixed::ZERO,
    },
    TechDef {
        id: 12,
        name: "Reach Interstellar",
        branch: TechBranch::Era,
        cost: Fixed::from_int(1200),
        duration: 1000,
        prereq: Some(11),
        bonus: Fixed::ZERO,
    },
    TechDef {
        id: 13,
        name: "Shield I",
        branch: TechBranch::Shields,
        cost: Fixed::from_int(300),
        duration: 450,
        prereq: None,
        bonus: Fixed::from_int(30),
    },
    TechDef {
        id: 14,
        name: "Shield II",
        branch: TechBranch::Shields,
        cost: Fixed::from_int(450),
        duration: 600,
        prereq: Some(13),
        bonus: Fixed::from_int(40),
    },
    TechDef {
        id: 15,
        name: "Shield III",
        branch: TechBranch::Shields,
        cost: Fixed::from_int(600),
        duration: 750,
        prereq: Some(14),
        bonus: Fixed::from_int(50),
    },
    TechDef {
        id: 16,
        name: "Anti-Grav Drives",
        branch: TechBranch::AntiGrav,
        cost: Fixed::from_int(500),
        duration: 600,
        prereq: None,
        bonus: Fixed::ZERO,
    },
    // --- Doctrine fork: a one-time, mutually-exclusive specialization (see
    // `excludes`). Commit to overwhelming offense OR an entrenched defense.
    TechDef {
        id: 17,
        name: "Assault Doctrine",
        branch: TechBranch::Weapons,
        cost: Fixed::from_int(600),
        duration: 600,
        prereq: None,
        bonus: Fixed::from_int(3),
    },
    TechDef {
        id: 18,
        name: "Fortress Doctrine",
        branch: TechBranch::Armor,
        cost: Fixed::from_int(600),
        duration: 600,
        prereq: None,
        bonus: Fixed::from_int(3),
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

/// Whether a tech id is an era-key (researching it advances the player's era).
#[must_use]
pub const fn is_era_key(id: u32) -> bool {
    matches!(tech(id), Some(t) if matches!(t.branch, TechBranch::Era))
}

/// The mutually-exclusive counterpart of `id` in a doctrine fork, if any.
/// Researching a tech permanently locks out the tech this returns.
#[must_use]
pub const fn excludes(id: u32) -> Option<u32> {
    match id {
        17 => Some(18),
        18 => Some(17),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{excludes, is_era_key, tech, TechBranch, TECHS, TECH_COUNT};

    #[test]
    fn doctrine_fork_is_mutually_exclusive() {
        // The two doctrines exclude each other; nothing else is part of a fork.
        assert_eq!(excludes(17), Some(18));
        assert_eq!(excludes(18), Some(17));
        assert_eq!(excludes(0), None);
        assert_eq!(excludes(16), None);
        assert_eq!(tech(17).unwrap().name, "Assault Doctrine");
        assert_eq!(tech(18).unwrap().name, "Fortress Doctrine");
    }

    #[test]
    fn is_shield_branch() {
        assert_eq!(tech(13).unwrap().branch, TechBranch::Shields);
        assert_eq!(tech(14).unwrap().branch, TechBranch::Shields);
        assert_eq!(tech(15).unwrap().branch, TechBranch::Shields);
        // Chain by prereq: 14→13, 15→14.
        assert_eq!(tech(14).unwrap().prereq, Some(13));
        assert_eq!(tech(15).unwrap().prereq, Some(14));
        assert_eq!(TECH_COUNT, 19);
    }

    #[test]
    fn antigrav_tech_exists_at_id_16() {
        // There is exactly one AntiGrav tech, at index 16.
        let count = TECHS
            .iter()
            .filter(|t| matches!(t.branch, TechBranch::AntiGrav))
            .count();
        assert_eq!(count, 1, "exactly one AntiGrav tech");
        let t = tech(16).unwrap();
        assert_eq!(t.id, 16);
        assert_eq!(t.name, "Anti-Grav Drives");
        assert!(matches!(t.branch, TechBranch::AntiGrav));
        assert_eq!(t.prereq, None);
        assert_eq!(TECH_COUNT, 19);
    }

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

    #[test]
    fn is_era_key_identifies_era_techs() {
        assert!(is_era_key(10) && is_era_key(12) && !is_era_key(0));
        // Era techs chain by prereq: 11 requires 10, 12 requires 11.
        assert_eq!(TECHS[11].prereq, Some(10));
        assert_eq!(TECHS[12].prereq, Some(11));
        // Non-era techs are not era keys.
        assert!(!is_era_key(1));
        assert!(!is_era_key(9));
        // Out-of-range id is not an era key.
        assert!(!is_era_key(100));
    }
}
