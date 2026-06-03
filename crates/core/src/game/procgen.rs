//! Deterministic procedural map generation for the survival mode.
//!
//! Same seed → a bit-identical map on every target. It uses its own tiny seeded
//! LCG (separate from the simulation RNG, so it never perturbs sim determinism).
//! The left and right margins are kept clear for the player base and the alien
//! beachhead, and a [`find_path`] connectivity check guarantees the two sides are
//! never bisected (which would soft-lock the run).
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_possible_wrap,
    reason = "procgen converts between bounded tile indices and the LCG's integer \
              output; every value is range-checked before the cast"
)]

use crate::game::map::{Deposit, DepositKind, Map, Tile};
use crate::game::path::find_path;

/// Survival battlefield width in tiles.
pub const WIDTH: u16 = 44;
/// Survival battlefield height in tiles.
pub const HEIGHT: u16 = 26;
/// Columns kept clear at each edge for the base / beachhead.
pub const MARGIN: u16 = 7;

/// A tiny deterministic PRNG (separate from the sim's), for map layout only.
struct Lcg(u64);

impl Lcg {
    const fn next(&mut self) -> u32 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (self.0 >> 33) as u32
    }

    /// A value in `lo..hi` (hi exclusive; requires `lo < hi`).
    fn range(&mut self, lo: u16, hi: u16) -> u16 {
        lo + (self.next() % u32::from(hi - lo)) as u16
    }
}

/// Generates a survival battlefield for `seed`: scattered wreck clusters with the
/// base margins clear and guaranteed left↔right connectivity.
#[must_use]
pub fn generate(seed: u64) -> Map {
    let mut map = Map::new(WIDTH, HEIGHT);
    // Mix the seed so adjacent seeds give visibly different maps.
    let mut rng = Lcg(seed ^ 0x9E37_79B9_7F4A_7C15);
    let clusters = 7 + (rng.next() % 6) as u16; // 7..=12 wreckfields
    for _ in 0..clusters {
        let cx = rng.range(MARGIN, WIDTH - MARGIN);
        let cy = rng.range(1, HEIGHT - 1);
        let radius = 1 + (rng.next() % 2) as i32; // 1..=2
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                if dx * dx + dy * dy > radius * radius {
                    continue;
                }
                let x = i32::from(cx) + dx;
                let y = i32::from(cy) + dy;
                // Keep both base margins clear; stay in bounds.
                if x >= i32::from(MARGIN)
                    && x < i32::from(WIDTH - MARGIN)
                    && y >= 0
                    && y < i32::from(HEIGHT)
                {
                    map.set_tile(x as u16, y as u16, Tile::BLOCKED);
                }
            }
        }
    }
    // Connectivity repair: if the wrecks bisect the field, carve a clear lane down
    // the middle row so attackers can always reach the player's base.
    let mid = HEIGHT / 2;
    let left = (MARGIN - 1, mid);
    let right = (WIDTH - MARGIN, mid);
    if find_path(&map, left, right).is_none() {
        for x in 0..WIDTH {
            map.set_tile(x, mid, Tile::OPEN);
        }
    }

    // Deposit placement: scatter ore + alloy on passable tiles using the same
    // seeded RNG so the layout stays deterministic. A guaranteed near-base ore is
    // placed at (MARGIN, mid) first; extra ore and alloys are then scattered.
    map.set_deposit(
        MARGIN,
        mid,
        Deposit {
            kind: DepositKind::Ore,
            // ~1.5 min of mining at 5/tick (30 Hz) — a deposit you settle and hold,
            // not one that vanishes in seconds. Finite, so you still expand later.
            remaining: 14_000,
        },
    );
    let extra_ore = 4 + (rng.next() % 4) as u16; // 4..=7
    let alloys = 1 + (rng.next() % 2) as u16; // 1..=2
    let mut placed = 0u16;
    let mut tries = 0u16;
    while placed < extra_ore + alloys && tries < 400 {
        tries += 1;
        let x = rng.range(1, WIDTH - 1);
        let y = rng.range(0, HEIGHT);
        let passable = map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.passable);
        if passable && map.deposit(x, y).is_none() {
            let kind = if placed < extra_ore {
                DepositKind::Ore
            } else {
                DepositKind::Alloy
            };
            let remaining = if matches!(kind, DepositKind::Ore) {
                11_000
            } else {
                6_000
            };
            map.set_deposit(x, y, Deposit { kind, remaining });
            placed += 1;
        }
    }

    map
}

#[cfg(test)]
mod tests {
    use super::{generate, HEIGHT, MARGIN, WIDTH};
    use crate::game::path::find_path;

    fn blocked_cells(seed: u64) -> alloc::vec::Vec<(u16, u16)> {
        let m = generate(seed);
        let mut out = alloc::vec::Vec::new();
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                if !m.tile(i32::from(x), i32::from(y)).unwrap().passable {
                    out.push((x, y));
                }
            }
        }
        out
    }

    #[test]
    fn same_seed_is_identical_different_seed_differs() {
        assert_eq!(
            blocked_cells(42),
            blocked_cells(42),
            "procgen not deterministic"
        );
        assert_ne!(
            blocked_cells(1),
            blocked_cells(2),
            "different seeds produced the same map"
        );
    }

    #[test]
    fn procgen_places_ore_and_a_near_base_deposit() {
        use crate::game::map::DepositKind;
        for seed in 0..30_u64 {
            let m = generate(seed);
            let mut ore = 0;
            let mut alloy = 0;
            let mut near_base = false;
            for (x, _y, d) in m.deposits() {
                match d.kind {
                    DepositKind::Ore => ore += 1,
                    DepositKind::Alloy => alloy += 1,
                }
                if x < 12 {
                    near_base = true;
                }
            }
            assert!(ore >= 3, "seed {seed}: too few ore deposits ({ore})");
            assert!(alloy >= 1, "seed {seed}: no alloy deposit");
            assert!(near_base, "seed {seed}: no deposit near the player's base");
        }
    }

    #[test]
    fn margins_are_clear_and_field_is_connected() {
        for seed in 0..40_u64 {
            let m = generate(seed);
            // Base margins must be fully open for building placement.
            for y in 0..HEIGHT {
                for x in 0..MARGIN {
                    assert!(m.tile(i32::from(x), i32::from(y)).unwrap().passable);
                    let rx = WIDTH - 1 - x;
                    assert!(m.tile(i32::from(rx), i32::from(y)).unwrap().passable);
                }
            }
            // The two sides are always reachable from each other.
            let mid = HEIGHT / 2;
            assert!(
                find_path(&m, (MARGIN - 1, mid), (WIDTH - MARGIN, mid)).is_some(),
                "seed {seed}: battlefield bisected"
            );
        }
    }
}
