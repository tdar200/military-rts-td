//! The 500-slot Kardashev capability grid — Ascension's tech system.
//!
//! The grid is a fixed `10 eras × 10 branches × 5 steps = 500` lattice. Every
//! node has a **stable, computable id** `era*50 + branch*5 + step`, so ids never
//! need to be stored as magic numbers and the layout is trivially reasoned about.
//! A node is *what civilization can now do* — detect, mine, build, automate,
//! defend, colonize, attack, survive, or understand — reached only through its
//! real precursor chain (theory → lab control → engineering → deployment →
//! application → civilization-scale).
//!
//! The grid is live in the deterministic simulation: players research directly
//! into [`TechBitset`], era keys advance civilization, and concrete unlocks feed
//! the RTS build and production rosters. The fixed coordinate system and honesty
//! labels are also consumed by both presentation clients.

use crate::game::stats::{BuildingKind, UnitKind};
use crate::hash::Fnv;

/// Number of eras (Kardashev/theme columns), 0..=9.
pub const ERA_COUNT: usize = 10;
/// Number of branches (capability lanes), 0..=9.
pub const BRANCH_COUNT: usize = 10;
/// Steps per (era, branch) cell — the theory→civ-scale progression.
pub const STEPS_PER_CELL: usize = 5;
/// Total grid slots: `10 * 10 * 5 == 500`.
pub const TECH_MAX: usize = ERA_COUNT * BRANCH_COUNT * STEPS_PER_CELL;
/// 64-bit words needed to hold one bit per slot: `512` bits, `12` spare.
pub const TECH_WORDS: usize = TECH_MAX.div_ceil(64);

/// Era boundary after which everything is speculative/lore (the visible
/// "Frontier of Known Physics"): no Achieved/Emerging node exists past era 4.
pub const FRONTIER_AFTER_ERA: u8 = 4;

/// The nine era-key node ids (one per era 0..=8).
///
/// Researching an era key advances the empire to the next era. Each is the
/// Energy-branch civ-scale capstone (`era*50 + 9`) — fitting, because the
/// Kardashev scale is energy-defined.
pub const ERA_KEYS: [u32; ERA_COUNT - 1] = [9, 59, 109, 159, 209, 259, 309, 359, 409];

/// The stable grid id of the node at `(era, branch, step)`.
#[inline]
#[must_use]
pub const fn tech_id(era: u8, branch: u8, step: u8) -> u32 {
    era as u32 * 50 + branch as u32 * 5 + step as u32
}

/// The era (0..=9) of grid id `id`.
#[inline]
#[must_use]
#[allow(
    clippy::cast_possible_truncation,
    reason = "id < TECH_MAX (500) ⇒ id/50 < 10, fits u8"
)]
pub const fn era_of(id: u32) -> u8 {
    (id / 50) as u8
}

/// The branch (0..=9) of grid id `id`.
#[inline]
#[must_use]
#[allow(
    clippy::cast_possible_truncation,
    reason = "(id % 50) / 5 < 10, fits u8"
)]
pub const fn branch_of(id: u32) -> u8 {
    ((id % 50) / 5) as u8
}

/// The step (0..=4) of grid id `id`.
#[inline]
#[must_use]
#[allow(clippy::cast_possible_truncation, reason = "id % 5 < 5, fits u8")]
pub const fn step_of(id: u32) -> u8 {
    (id % 5) as u8
}

/// A deterministic, no-heap set of researched grid nodes (512 bits, `Copy`).
///
/// This replaces the legacy `u32` researched-tech bitmask; 500 nodes need more
/// than 64 bits, so it is a fixed `[u64; 8]`. Bit `id` lives in word `id / 64`,
/// bit `id % 64`. Hashing folds the words in index order — see [`Self::hash_into`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct TechBitset {
    /// Raw 64-bit words; word `w` covers ids `64*w ..= 64*w + 63`.
    pub words: [u64; TECH_WORDS],
}

impl TechBitset {
    /// An empty set (nothing researched).
    #[must_use]
    pub const fn empty() -> Self {
        Self {
            words: [0; TECH_WORDS],
        }
    }

    /// Whether grid node `id` is in the set. Ids `>= TECH_MAX` are never present.
    #[inline]
    #[must_use]
    pub const fn get(&self, id: u32) -> bool {
        if id as usize >= TECH_MAX {
            return false;
        }
        self.words[(id / 64) as usize] & (1u64 << (id % 64)) != 0
    }

    /// Adds grid node `id` to the set. Out-of-range ids are ignored.
    #[inline]
    pub const fn set(&mut self, id: u32) {
        if (id as usize) < TECH_MAX {
            self.words[(id / 64) as usize] |= 1u64 << (id % 64);
        }
    }

    /// Removes grid node `id` from the set. Out-of-range ids are ignored.
    #[inline]
    pub const fn clear(&mut self, id: u32) {
        if (id as usize) < TECH_MAX {
            self.words[(id / 64) as usize] &= !(1u64 << (id % 64));
        }
    }

    /// How many nodes are in the set.
    #[must_use]
    pub const fn count(&self) -> u32 {
        let mut total = 0u32;
        let mut w = 0;
        while w < TECH_WORDS {
            total += self.words[w].count_ones();
            w += 1;
        }
        total
    }

    /// Whether the set is empty.
    #[must_use]
    pub const fn is_empty(&self) -> bool {
        let mut w = 0;
        while w < TECH_WORDS {
            if self.words[w] != 0 {
                return false;
            }
            w += 1;
        }
        true
    }

    /// Folds the set into a state hash, words in index order (stable forever).
    pub fn hash_into(&self, h: &mut Fnv) {
        for w in self.words {
            h.write_u64(w);
        }
    }
}

impl Default for TechBitset {
    fn default() -> Self {
        Self::empty()
    }
}

/// The ten eras (Kardashev/theme columns). `#[repr(u8)]` so the discriminant is
/// the era index used by [`tech_id`].
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub enum Era {
    /// 0 — Foundation / Digital Age (1990s–2020s, K≈0.70).
    Foundation = 0,
    /// 1 — Quantum-Nano Age (quantum computing, nanotech, AI).
    QuantumNano = 1,
    /// 2 — Planetary Renewable Age (renewables, storage, smart grid).
    Renewable = 2,
    /// 3 — Fusion Age (plasma, superconductors, commercial fusion).
    Fusion = 3,
    /// 4 — Space Industrial Age (launch, ISRU, habitats, orbital industry).
    SpaceIndustrial = 4,
    /// 5 — Stellar Type I–II Age (Dyson swarm, antimatter, star lifting).
    Stellar = 5,
    /// 6 — Galactic Type III Age (interstellar empire, matrioshka brains).
    Galactic = 6,
    /// 7 — Dark Sector Age (dark matter, dark energy, hidden sector).
    DarkSector = 7,
    /// 8 — Higher-Dimensional Age (string theory, branes, quantum gravity).
    HigherDimensional = 8,
    /// 9 — Cosmic Type IV–VII Age (universe fate, vacuum engineering).
    Cosmic = 9,
}

/// The ten capability branches (lanes). `#[repr(u8)]` so the discriminant is the
/// branch index used by [`tech_id`].
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub enum Branch {
    /// 0 — Computation / AI / Information.
    Compute = 0,
    /// 1 — Energy / Power (carries the era keys).
    Energy = 1,
    /// 2 — Materials / Manufacturing.
    Materials = 2,
    /// 3 — Propulsion / Mobility.
    Propulsion = 3,
    /// 4 — Weapons / Force Projection.
    Weapons = 4,
    /// 5 — Defense / Shields / Survivability.
    Defense = 5,
    /// 6 — Biology / Labour / Population / Civilization.
    Biology = 6,
    /// 7 — Space Infrastructure / Megastructures.
    SpaceInfra = 7,
    /// 8 — Dark Sector (dark matter + dark energy).
    DarkSector = 8,
    /// 9 — Quantum Gravity / Dimensions / Universe Fate.
    Gravity = 9,
}

/// How real a node is — the honesty label shown in-game. Distinct from the
/// empire's Kardashev tier (progress); this is the *scientific status* of the
/// technology itself.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub enum RealityClass {
    /// Real, datable, deployed today.
    Achieved = 0,
    /// Under active development; credible near-term.
    Emerging = 1,
    /// Sound physics, no device built.
    Theoretical = 2,
    /// Beyond current physics.
    Speculative = 3,
    /// Pure futurism / lore — no scientific basis.
    Lore = 4,
}

/// Which kind of concrete thing a node makes available.
///
/// The 500-grid's unlocks are mostly capabilities/automation, not new buildings,
/// so the family is a first-class tag. In M1 the unlocked item is carried as a
/// name string (see [`Unlock`]); typed per-family enums arrive when unlocks are
/// wired to gameplay.
#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub enum UnlockFamily {
    /// A placeable structure.
    Building = 0,
    /// A trainable unit.
    Unit = 1,
    /// A one-shot upgrade to existing things.
    Upgrade = 2,
    /// An activated ability.
    Ability = 3,
    /// A standing system/automation behaviour.
    System = 4,
    /// A production recipe / resource conversion.
    Recipe = 5,
    /// A named passive modifier (a stat rider tied to a real technology).
    Modifier = 6,
}

/// One concrete thing a node unlocks: a [`UnlockFamily`] and the item's name.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Unlock {
    /// The kind of unlock.
    pub family: UnlockFamily,
    /// The item's name (a typed enum variant once unlocks are wired).
    pub name: &'static str,
}

/// One node of the capability grid (static, generated; see
/// [`crate::game::tech_grid_table::GRID`]).
#[derive(Clone, Copy, Debug)]
pub struct GridNode {
    /// Stable grid id (`era*50 + branch*5 + step`); equals the array index.
    pub id: u32,
    /// The real-science milestone name.
    pub name: &'static str,
    /// Era 0..=9.
    pub era: u8,
    /// Branch 0..=9 (see [`Branch`]).
    pub branch: u8,
    /// Step 0..=4 within the cell (theory → civ-scale).
    pub step: u8,
    /// Scientific-honesty class.
    pub reality: RealityClass,
    /// Money cost to research.
    pub money: u32,
    /// Energy cost to research.
    pub energy: u32,
    /// Labour cost to research.
    pub labour: u32,
    /// Research duration in ticks.
    pub duration: u32,
    /// Grid ids that must be researched first (all strictly lower than `id`).
    pub prereqs: &'static [u32],
    /// What completing this node makes available (always non-empty).
    pub unlocks: &'static [Unlock],
}

/// The grid node with id `id`, or `None` if out of range.
#[must_use]
pub fn node(id: u32) -> Option<&'static GridNode> {
    crate::game::tech_grid_table::GRID.get(id as usize)
}

/// Whether `id` is one of the era-key nodes (completing it advances the era).
#[must_use]
pub fn is_era_key(id: u32) -> bool {
    ERA_KEYS.contains(&id)
}

/// Bridge: the real, implemented [`BuildingKind`] a grid node unlocks.
///
/// The grid is mostly aspirational — only a handful of nodes map to entities that
/// exist today; the rest unlock flavour/“coming soon” capabilities (`None` here).
/// These mappings are what keep a Survival run winnable (the human researches
/// these to get an economy, an army, and defenses).
#[must_use]
pub const fn real_building(id: u32) -> Option<BuildingKind> {
    match id {
        0 => Some(BuildingKind::ResearchLab), // Compute e0s0 (root)
        20 => Some(BuildingKind::Barracks),   // Weapons e0s0 (root)
        25 => Some(BuildingKind::GunTurret),  // Defense e0s0 (root)
        75 => Some(BuildingKind::AaTurret),   // Defense e1s0
        105 => Some(BuildingKind::AntimatterPlant), // Energy e2s0
        _ => None,
    }
}

/// Bridge: the real, implemented [`UnitKind`] a grid node unlocks (see
/// [`real_building`]).
#[must_use]
pub const fn real_unit(id: u32) -> Option<UnitKind> {
    match id {
        20 => Some(UnitKind::Infantry),    // Weapons e0s0 (with Barracks)
        70 => Some(UnitKind::AntiArmor),   // Weapons e1s0
        71 => Some(UnitKind::Tank),        // Weapons e1s1
        115 => Some(UnitKind::Helicopter), // Propulsion e2s0
        270 => Some(UnitKind::Capital),    // Weapons e5s0
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        branch_of, era_of, step_of, tech_id, TechBitset, BRANCH_COUNT, ERA_COUNT, ERA_KEYS,
        STEPS_PER_CELL, TECH_MAX, TECH_WORDS,
    };
    use crate::hash::Fnv;

    #[test]
    fn grid_dimensions_are_500_in_8_words() {
        const _: () = assert!(TECH_WORDS * 64 >= TECH_MAX);
        assert_eq!(TECH_MAX, 500);
        assert_eq!(TECH_WORDS, 8);
    }

    #[test]
    fn coordinate_system_covers_every_slot_exactly_once() {
        // Every (era, branch, step) maps to a distinct id, and the ids are exactly
        // 0..500 with no gaps — the structural guarantee of the grid.
        let mut seen = [false; TECH_MAX];
        let mut count = 0;
        for era in 0..ERA_COUNT {
            for branch in 0..BRANCH_COUNT {
                for step in 0..STEPS_PER_CELL {
                    let (era, branch, step) = (
                        u8::try_from(era).unwrap(),
                        u8::try_from(branch).unwrap(),
                        u8::try_from(step).unwrap(),
                    );
                    let id = tech_id(era, branch, step);
                    assert!((id as usize) < TECH_MAX);
                    assert!(!seen[id as usize], "duplicate id {id}");
                    seen[id as usize] = true;
                    count += 1;
                    assert_eq!(era_of(id), era);
                    assert_eq!(branch_of(id), branch);
                    assert_eq!(step_of(id), step);
                }
            }
        }
        assert_eq!(count, 500);
        assert!(seen.iter().all(|&s| s));
    }

    #[test]
    fn era_keys_are_the_energy_capstones() {
        // One per era 0..=8, all on branch 1 (Energy), step 4 — the era spine.
        assert_eq!(ERA_KEYS.len(), ERA_COUNT - 1);
        for (era, &key) in ERA_KEYS.iter().enumerate() {
            let era = u8::try_from(era).unwrap();
            assert_eq!(key, tech_id(era, 1, 4));
            assert_eq!(era_of(key), era);
            assert_eq!(branch_of(key), 1);
            assert_eq!(step_of(key), 4);
        }
    }

    #[test]
    fn bitset_set_get_clear_count() {
        let mut b = TechBitset::empty();
        assert!(b.is_empty());
        assert_eq!(b.count(), 0);
        // touch a node in every word, including the last live slot.
        for &id in &[0u32, 63, 64, 200, 333, 499] {
            assert!(!b.get(id));
            b.set(id);
            assert!(b.get(id));
        }
        assert_eq!(b.count(), 6);
        b.clear(333);
        assert!(!b.get(333));
        assert_eq!(b.count(), 5);
    }

    #[test]
    fn bitset_ignores_out_of_range_ids() {
        let mut b = TechBitset::empty();
        b.set(500);
        b.set(10_000);
        assert!(b.is_empty());
        assert!(!b.get(500));
    }

    #[test]
    fn bitset_hash_is_order_stable_and_value_sensitive() {
        let mut a = TechBitset::empty();
        a.set(5);
        a.set(300);
        let mut b = TechBitset::empty();
        b.set(300);
        b.set(5);
        let mut ha = Fnv::new();
        let mut hb = Fnv::new();
        a.hash_into(&mut ha);
        b.hash_into(&mut hb);
        assert_eq!(ha.finish(), hb.finish());
        let mut c = TechBitset::empty();
        c.set(6);
        let mut hc = Fnv::new();
        c.hash_into(&mut hc);
        assert_ne!(ha.finish(), hc.finish());
    }
}
