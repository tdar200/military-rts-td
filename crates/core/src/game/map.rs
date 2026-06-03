//! The battlefield grid.
//!
//! The map is a rectangular grid of [`Tile`]s. Each tile records whether units
//! can walk it (`passable`) and whether structures can be placed on it
//! (`buildable`). World positions are [`Fixed`](crate::fixed::Fixed) `Vec2`s; the
//! map works in integer tile coordinates and is queried with signed `i32` so that
//! out-of-bounds lookups (negative or past the edge) are well-defined.

use alloc::vec::Vec;

/// A single map cell.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct Tile {
    /// Units may walk across this tile.
    pub passable: bool,
    /// Structures may be placed on this tile.
    pub buildable: bool,
}

impl Tile {
    /// Open ground: walkable and buildable.
    pub const OPEN: Self = Self {
        passable: true,
        buildable: true,
    };

    /// Impassable, unbuildable terrain (e.g. cliffs, water).
    pub const BLOCKED: Self = Self {
        passable: false,
        buildable: false,
    };
}

/// The type of a resource deposit.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub enum DepositKind {
    /// Standard ore used for credit income.
    Ore,
    /// Rare alloy used for advanced production.
    Alloy,
}

/// A finite resource deposit on a map tile.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct Deposit {
    /// What kind of resource this deposit contains.
    pub kind: DepositKind,
    /// How many units of resource remain.
    pub remaining: u32,
}

/// A rectangular grid of [`Tile`]s.
#[derive(Clone, Debug)]
pub struct Map {
    width: u16,
    height: u16,
    tiles: Vec<Tile>,
    deposits: Vec<Option<Deposit>>,
}

impl Map {
    /// Creates a `width × height` map of open ground.
    #[must_use]
    pub fn new(width: u16, height: u16) -> Self {
        let count = usize::from(width) * usize::from(height);
        let mut tiles = Vec::with_capacity(count);
        tiles.resize(count, Tile::OPEN);
        Self {
            width,
            height,
            tiles,
            deposits: alloc::vec![None; count],
        }
    }

    /// Map width in tiles.
    #[must_use]
    pub const fn width(&self) -> u16 {
        self.width
    }

    /// Map height in tiles.
    #[must_use]
    pub const fn height(&self) -> u16 {
        self.height
    }

    /// Whether `(x, y)` is a valid tile coordinate.
    #[must_use]
    pub const fn in_bounds(&self, x: i32, y: i32) -> bool {
        x >= 0 && y >= 0 && (x as i64) < self.width as i64 && (y as i64) < self.height as i64
    }

    /// The tile at `(x, y)`, or `None` if out of bounds.
    #[must_use]
    #[allow(
        clippy::cast_sign_loss,
        reason = "coordinates are bounds-checked non-negative before the cast"
    )]
    pub fn tile(&self, x: i32, y: i32) -> Option<Tile> {
        if self.in_bounds(x, y) {
            let index = (y as usize) * usize::from(self.width) + (x as usize);
            Some(self.tiles[index])
        } else {
            None
        }
    }

    /// Replaces the tile at `(x, y)`. Out-of-bounds coordinates are ignored.
    pub fn set_tile(&mut self, x: u16, y: u16, tile: Tile) {
        if x < self.width && y < self.height {
            let index = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.tiles[index] = tile;
        }
    }

    /// The deposit at `(x, y)`, or `None` if there is none or `(x, y)` is out of bounds.
    #[must_use]
    pub fn deposit(&self, x: u16, y: u16) -> Option<Deposit> {
        if x < self.width && y < self.height {
            let index = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.deposits[index]
        } else {
            None
        }
    }

    /// Places or replaces a deposit at `(x, y)`. Out-of-bounds coordinates are ignored.
    pub fn set_deposit(&mut self, x: u16, y: u16, deposit: Deposit) {
        if x < self.width && y < self.height {
            let index = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.deposits[index] = Some(deposit);
        }
    }

    /// Iterates over all placed deposits as `(x, y, deposit)` in row-major order.
    pub fn deposits(&self) -> impl Iterator<Item = (u16, u16, Deposit)> + '_ {
        let width = usize::from(self.width);
        self.deposits
            .iter()
            .enumerate()
            .filter_map(move |(i, slot)| {
                let dep = (*slot)?;
                let x = u16::try_from(i % width).unwrap_or(0);
                let y = u16::try_from(i / width).unwrap_or(0);
                Some((x, y, dep))
            })
    }

    /// Mines up to `amount` units from the deposit at `(x, y)`.
    ///
    /// Returns the actual amount mined (clamped to what remains). Clears the
    /// deposit when exhausted. Returns `0` for out-of-bounds or missing deposits.
    pub fn mine(&mut self, x: u16, y: u16, amount: u32) -> u32 {
        if x >= self.width || y >= self.height {
            return 0;
        }
        let index = usize::from(y) * usize::from(self.width) + usize::from(x);
        let Some(dep) = &mut self.deposits[index] else {
            return 0;
        };
        let mined = amount.min(dep.remaining);
        dep.remaining -= mined;
        if dep.remaining == 0 {
            self.deposits[index] = None;
        }
        mined
    }
}

#[cfg(test)]
mod tests {
    use super::{Deposit, DepositKind, Map, Tile};

    #[test]
    fn new_map_has_dimensions_and_is_open() {
        let m = Map::new(8, 5);
        assert_eq!(m.width(), 8);
        assert_eq!(m.height(), 5);
        assert_eq!(m.tile(0, 0), Some(Tile::OPEN));
        assert_eq!(m.tile(7, 4), Some(Tile::OPEN));
    }

    #[test]
    fn in_bounds_rejects_outside_and_negative() {
        let m = Map::new(4, 4);
        assert!(m.in_bounds(0, 0));
        assert!(m.in_bounds(3, 3));
        assert!(!m.in_bounds(4, 0));
        assert!(!m.in_bounds(0, 4));
        assert!(!m.in_bounds(-1, 0));
        assert!(!m.in_bounds(0, -1));
    }

    #[test]
    fn tile_is_none_out_of_bounds() {
        let m = Map::new(4, 4);
        assert_eq!(m.tile(-1, 0), None);
        assert_eq!(m.tile(4, 4), None);
    }

    #[test]
    fn set_tile_changes_the_cell() {
        let mut m = Map::new(4, 4);
        m.set_tile(2, 1, Tile::BLOCKED);
        assert_eq!(m.tile(2, 1), Some(Tile::BLOCKED));
        // neighbours untouched
        assert_eq!(m.tile(2, 2), Some(Tile::OPEN));
    }

    #[test]
    fn deposits_iter_lists_placed_deposits() {
        let mut m = Map::new(4, 4);
        m.set_deposit(
            1,
            1,
            Deposit {
                kind: DepositKind::Ore,
                remaining: 100,
            },
        );
        m.set_deposit(
            3,
            0,
            Deposit {
                kind: DepositKind::Alloy,
                remaining: 50,
            },
        );
        let mut got: alloc::vec::Vec<(u16, u16, DepositKind, u32)> = m
            .deposits()
            .map(|(x, y, d)| (x, y, d.kind, d.remaining))
            .collect();
        got.sort_unstable();
        assert_eq!(
            got,
            alloc::vec![
                (1, 1, DepositKind::Ore, 100),
                (3, 0, DepositKind::Alloy, 50)
            ]
        );
    }

    #[test]
    fn deposits_default_empty_and_round_trip() {
        let mut m = Map::new(6, 4);
        assert_eq!(m.deposit(2, 1), None);
        m.set_deposit(
            2,
            1,
            Deposit {
                kind: DepositKind::Ore,
                remaining: 500,
            },
        );
        assert_eq!(
            m.deposit(2, 1),
            Some(Deposit {
                kind: DepositKind::Ore,
                remaining: 500
            })
        );
        assert_eq!(m.mine(2, 1, 200), 200);
        assert_eq!(m.deposit(2, 1).unwrap().remaining, 300);
        assert_eq!(m.mine(2, 1, 999), 300); // clamps to remaining
        assert_eq!(m.deposit(2, 1), None); // exhausted -> cleared
        assert_eq!(m.mine(5, 5, 10), 0); // out of bounds / no deposit
    }
}
