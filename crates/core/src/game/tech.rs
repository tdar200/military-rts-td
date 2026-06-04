//! The research tech TREE — a per-player prerequisite DAG where research opens doors.
//!
//! Each tech can UNLOCK buildings/units (the primary payoff) and carries a flat
//! stat `bonus` to its `branch` as a secondary rider. A player's total branch
//! bonus is the sum of researched techs' bonuses, applied live at
//! combat/economy/movement resolution.
//!
//! The tree has a single root (Mobilization), five tiers (Foundation → Expansion
//! → Industrial → Energy → Ascendancy), multi-parent convergence edges, and a
//! mutually-exclusive doctrine fork at the capstone. The Foundation tier is paid
//! from MINERALS (so research bootstraps before the Research Lab exists); every
//! later tier is paid from the Research pool.

use crate::fixed::Fixed;
use crate::game::stats::{BuildingKind, UnitKind};

/// Number of techs in the tree.
pub const TECH_COUNT: usize = 19;

/// Which global stat a tech's rider improves.
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

/// What completing a tech makes available — the door it opens.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TechUnlock {
    /// Makes a building kind placeable.
    Building(BuildingKind),
    /// Makes a unit kind trainable.
    Unit(UnitKind),
}

/// One research node.
///
/// `PartialEq`/`Eq` are intentionally absent: [`Fixed`] does not implement them.
/// Use [`TechDef::id`] for identity comparisons.
#[derive(Clone, Copy, Debug)]
pub struct TechDef {
    /// Stable id; equals the index into [`TECHS`].
    pub id: u32,
    /// Display name.
    pub name: &'static str,
    /// Tier (0..=4), the era/column this node sits in — drives the graph layout
    /// and the cost currency (tier 0 is money-paid).
    pub tier: u8,
    /// Which branch the stat rider improves.
    pub branch: TechBranch,
    /// Cost to research (in Minerals for tier 0, else Research).
    pub cost: Fixed,
    /// Research duration in ticks.
    pub duration: u32,
    /// Techs that must ALL be researched first (a DAG; ids may be in any order).
    pub prereqs: &'static [u32],
    /// What this tech makes buildable/trainable on completion.
    pub unlocks: &'static [TechUnlock],
    /// Flat bonus added to the branch total when researched (the secondary rider).
    pub bonus: Fixed,
}

#[allow(
    clippy::too_many_arguments,
    reason = "a terse positional constructor for the tech table; named struct fields would bloat the 19-row table"
)]
const fn t(
    id: u32,
    name: &'static str,
    tier: u8,
    branch: TechBranch,
    cost: i32,
    duration: u32,
    prereqs: &'static [u32],
    unlocks: &'static [TechUnlock],
    bonus: Fixed,
) -> TechDef {
    TechDef {
        id,
        name,
        tier,
        branch,
        cost: Fixed::from_int(cost),
        duration,
        prereqs,
        unlocks,
        bonus,
    }
}

use TechBranch::{AntiGrav, Armor, Economy, Era, Mobility, Shields, Weapons};
use TechUnlock::{Building as B, Unit as U};

/// The full tech tree. Ids are kept stable across the redesign (so saves/forks
/// and `excludes` ids don't shift); prereqs form the DAG independent of id order.
// Ordered by id (index == id). Tiers/eras are encoded by the `tier` field, not
// array position: Foundation(0, money-paid) → Expansion(1) → Industrial(2) →
// Energy(3) → Ascendancy(4). The single root is Mobilization (id 6).
pub const TECHS: [TechDef; TECH_COUNT] = [
    t(
        0,
        "Directed Energy",
        0,
        Weapons,
        220,
        600,
        &[6],
        &[B(BuildingKind::GunTurret)],
        Fixed::from_int(2),
    ),
    t(
        1,
        "Heavy Chassis",
        1,
        Weapons,
        320,
        1050,
        &[10],
        &[U(UnitKind::Tank)],
        Fixed::from_int(2),
    ),
    t(
        2,
        "Rotorcraft",
        2,
        Weapons,
        520,
        1350,
        &[1, 11],
        &[U(UnitKind::Helicopter)],
        Fixed::from_int(3),
    ),
    t(
        3,
        "Composite Plating",
        1,
        Armor,
        250,
        900,
        &[10],
        &[],
        Fixed::from_int(1),
    ),
    t(
        4,
        "Reactive Armor",
        2,
        Armor,
        420,
        1200,
        &[3],
        &[],
        Fixed::from_int(1),
    ),
    t(
        5,
        "Ablative Hull",
        3,
        Armor,
        650,
        1500,
        &[4, 12],
        &[],
        Fixed::from_int(2),
    ),
    // The single root: your first research builds your army (money-paid).
    t(
        6,
        "Mobilization",
        0,
        Economy,
        200,
        600,
        &[],
        &[B(BuildingKind::Barracks), U(UnitKind::Infantry)],
        Fixed::from_int(1),
    ),
    t(
        7,
        "Industrial Base",
        2,
        Economy,
        400,
        1200,
        &[3, 1],
        &[],
        Fixed::from_int(1),
    ),
    t(
        8,
        "Mechanized Corps",
        1,
        Mobility,
        280,
        900,
        &[10],
        &[U(UnitKind::AntiArmor)],
        Fixed::from_ratio(2, 100),
    ),
    t(
        9,
        "Anti-Grav Servos",
        2,
        Mobility,
        420,
        1200,
        &[8],
        &[],
        Fixed::from_ratio(2, 100),
    ),
    // Era key -> Expansion; unlocks the Research Lab, ending the money bootstrap.
    t(
        10,
        "Orbital Logistics",
        0,
        Era,
        300,
        900,
        &[0],
        &[B(BuildingKind::ResearchLab)],
        Fixed::ZERO,
    ),
    // Era key -> Industrial; unlocks anti-air as the alien air threat arrives.
    t(
        11,
        "Interplanetary Drive",
        2,
        Era,
        500,
        1500,
        &[1, 3],
        &[B(BuildingKind::AaTurret)],
        Fixed::ZERO,
    ),
    // Era key -> Energy; unlocks the Antimatter Plant + Capital ships.
    t(
        12,
        "Interstellar Drive",
        3,
        Era,
        800,
        1800,
        &[11, 14],
        &[B(BuildingKind::AntimatterPlant), U(UnitKind::Capital)],
        Fixed::ZERO,
    ),
    t(
        13,
        "Deflector Fields",
        1,
        Shields,
        300,
        900,
        &[10],
        &[],
        Fixed::from_int(30),
    ),
    t(
        14,
        "Shield Capacitors",
        2,
        Shields,
        460,
        1200,
        &[13],
        &[],
        Fixed::from_int(40),
    ),
    t(
        15,
        "Shield Matrix",
        3,
        Shields,
        700,
        1500,
        &[14, 12],
        &[],
        Fixed::from_int(50),
    ),
    t(
        16,
        "Anti-Grav Drives",
        3,
        AntiGrav,
        700,
        1500,
        &[9, 12],
        &[],
        Fixed::ZERO,
    ),
    // Ascendancy (tier 4) — a mutually-exclusive doctrine fork (see `excludes`).
    t(
        17,
        "Assault Doctrine",
        4,
        Weapons,
        900,
        1800,
        &[12],
        &[],
        Fixed::from_int(3),
    ),
    t(
        18,
        "Fortress Doctrine",
        4,
        Armor,
        900,
        1800,
        &[12],
        &[],
        Fixed::from_int(3),
    ),
];

// Keep TECH_COUNT in sync: the array length must match.
const _: () = assert!(TECHS.len() == TECH_COUNT);

/// Look up a tech by id (id == array index).
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
    use super::{excludes, is_era_key, tech, TechUnlock, TECHS, TECH_COUNT};
    use crate::game::stats::{BuildingKind, UnitKind};

    #[test]
    fn doctrine_fork_is_mutually_exclusive() {
        assert_eq!(excludes(17), Some(18));
        assert_eq!(excludes(18), Some(17));
        assert_eq!(excludes(0), None);
        assert_eq!(excludes(16), None);
        assert_eq!(tech(17).unwrap().name, "Assault Doctrine");
        assert_eq!(tech(18).unwrap().name, "Fortress Doctrine");
    }

    #[test]
    fn tree_is_a_well_formed_dag() {
        assert_eq!(TECHS.len(), TECH_COUNT);
        for (i, t) in TECHS.iter().enumerate() {
            assert_eq!(t.id as usize, i, "tech id must equal its index");
            for &p in t.prereqs {
                assert!((p as usize) < TECH_COUNT, "prereq id in range");
                assert_ne!(p, t.id, "no self-prereq");
                // A prereq must sit in an earlier-or-equal tier (no forward edges).
                assert!(
                    TECHS[p as usize].tier <= t.tier,
                    "prereq {p} of {} must not be in a later tier",
                    t.id
                );
            }
        }
        // Exactly one root (Mobilization), so the tree has a single entry point.
        let roots: usize = TECHS.iter().filter(|t| t.prereqs.is_empty()).count();
        assert_eq!(roots, 1, "exactly one root tech");
        assert_eq!(tech(6).unwrap().name, "Mobilization");
    }

    #[test]
    fn every_buildable_and_unit_kind_is_unlocked_by_some_tech() {
        // Every kind NOT in the founding kit must be reachable via research.
        let founding_buildings = [
            BuildingKind::CommandCenter,
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Wall,
        ];
        for b in [
            BuildingKind::Barracks,
            BuildingKind::GunTurret,
            BuildingKind::AaTurret,
            BuildingKind::ResearchLab,
            BuildingKind::AntimatterPlant,
        ] {
            assert!(!founding_buildings.contains(&b));
            assert!(
                TECHS
                    .iter()
                    .any(|t| t.unlocks.contains(&TechUnlock::Building(b))),
                "{b:?} must be unlocked by a tech"
            );
        }
        for u in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::AntiArmor,
            UnitKind::Helicopter,
            UnitKind::Capital,
        ] {
            assert!(
                TECHS
                    .iter()
                    .any(|t| t.unlocks.contains(&TechUnlock::Unit(u))),
                "{u:?} must be unlocked by a tech"
            );
        }
    }

    #[test]
    fn era_keys_are_the_tier_spine() {
        // One era key advances into each of Expansion/Industrial/Energy.
        assert!(is_era_key(10) && is_era_key(11) && is_era_key(12));
        assert!(!is_era_key(0) && !is_era_key(16));
        assert!(!is_era_key(100));
        assert_eq!(TECH_COUNT, 19);
    }
}
