//! The battlefield grid.
//!
//! The map is a rectangular grid of [`Tile`]s. Each tile records whether units
//! can walk it (`passable`) and whether structures can be placed on it
//! (`buildable`). World positions are [`Fixed`](crate::fixed::Fixed) `Vec2`s; the
//! map works in integer tile coordinates and is queried with signed `i32` so that
//! out-of-bounds lookups (negative or past the edge) are well-defined.

use alloc::vec::Vec;

use crate::game::planet::PlanetId;

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

/// Terrain class of a tile. Carries static per-tile yields (food/money/energy/
/// labour). A new, static map layer — NOT part of `state_hash` (like `deposits`).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, Default)]
pub enum TerrainKind {
    #[default]
    Barren,
    Plains,
    Fertile,
    Rich,
}

/// A finite resource deposit on a map tile.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct Deposit {
    /// What kind of resource this deposit contains.
    pub kind: DepositKind,
    /// How many units of resource remain.
    pub remaining: u32,
}

/// Ground type of one tile. Hashed (Earthfront only) because it changes behaviour.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Ground {
    Grass,
    Meadow,
    Flats,
    Highland,
    Forest,
    River,
    Ford,
    Shore,
    Sea,
    Crater,
}

/// Per-ground rules. Integer percents; `cover_pct` removes that share of incoming damage,
/// `range_pct` extends the shooter's range. One table, easy to retune.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct GroundProps {
    pub path_cost: u32,
    pub infantry_pct: u32,
    pub vehicle_pct: u32,
    pub cover_pct: u32,
    pub range_pct: u32,
    pub buildable: bool,
    pub passable: bool,
}

const fn gp(
    path_cost: u32,
    infantry_pct: u32,
    vehicle_pct: u32,
    cover_pct: u32,
    range_pct: u32,
    buildable: bool,
    passable: bool,
) -> GroundProps {
    GroundProps {
        path_cost,
        infantry_pct,
        vehicle_pct,
        cover_pct,
        range_pct,
        buildable,
        passable,
    }
}

impl Ground {
    pub const ALL: [Self; 10] = [
        Self::Grass,
        Self::Meadow,
        Self::Flats,
        Self::Highland,
        Self::Forest,
        Self::River,
        Self::Ford,
        Self::Shore,
        Self::Sea,
        Self::Crater,
    ];
    /// Lowest `path_cost` among passable grounds: the A* heuristic factor.
    pub const MIN_PASSABLE_COST: u32 = 9;

    #[must_use]
    pub const fn props(self) -> GroundProps {
        match self {
            Self::Grass => gp(10, 100, 100, 0, 0, true, true),
            Self::Meadow => gp(10, 100, 100, 5, 0, true, true),
            Self::Flats => gp(9, 110, 110, 0, 0, true, true),
            Self::Highland => gp(14, 70, 70, 25, 25, true, true),
            Self::Forest => gp(12, 80, 80, 20, 0, true, true),
            Self::River | Self::Sea => gp(0, 0, 0, 0, 0, false, false),
            Self::Ford => gp(20, 70, 50, 0, 0, false, true),
            Self::Shore => gp(12, 80, 80, 0, 0, false, true),
            Self::Crater => gp(12, 80, 80, 15, 0, false, true),
        }
    }

    #[must_use]
    pub const fn tag(self) -> u8 {
        self as u8
    }

    #[must_use]
    pub const fn from_tag(t: u8) -> Option<Self> {
        match t {
            0 => Some(Self::Grass),
            1 => Some(Self::Meadow),
            2 => Some(Self::Flats),
            3 => Some(Self::Highland),
            4 => Some(Self::Forest),
            5 => Some(Self::River),
            6 => Some(Self::Ford),
            7 => Some(Self::Shore),
            8 => Some(Self::Sea),
            9 => Some(Self::Crater),
            _ => None,
        }
    }

    /// One ASCII char per ground, used by the scenario text map and the snapshot.
    #[must_use]
    pub const fn glyph(self) -> char {
        match self {
            Self::Grass => 'g',
            Self::Meadow => 'm',
            Self::Flats => 'f',
            Self::Highland => 'h',
            Self::Forest => 't',
            Self::River => 'r',
            Self::Ford => 'w',
            Self::Shore => 's',
            Self::Sea => 'o',
            Self::Crater => 'c',
        }
    }

    #[must_use]
    pub const fn from_glyph(c: char) -> Option<Self> {
        match c {
            'g' => Some(Self::Grass),
            'm' => Some(Self::Meadow),
            'f' => Some(Self::Flats),
            'h' => Some(Self::Highland),
            't' => Some(Self::Forest),
            'r' => Some(Self::River),
            'w' => Some(Self::Ford),
            's' => Some(Self::Shore),
            'o' => Some(Self::Sea),
            'c' => Some(Self::Crater),
            _ => None,
        }
    }

    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Grass => "Grassland",
            Self::Meadow => "Meadow",
            Self::Flats => "Dry flats",
            Self::Highland => "Highland",
            Self::Forest => "Forest",
            Self::River => "River",
            Self::Ford => "Ford",
            Self::Shore => "Shore",
            Self::Sea => "Sea",
            Self::Crater => "Crater",
        }
    }
}

/// A rectangular grid of [`Tile`]s.
#[derive(Clone, Debug)]
pub struct Map {
    width: u16,
    height: u16,
    tiles: Vec<Tile>,
    deposits: Vec<Option<Deposit>>,
    planet_of: Vec<Option<PlanetId>>,
    /// Static per-tile terrain class. A new map layer — NOT folded into
    /// `state_hash` (like `deposits` / `planet_of`).
    terrain: Vec<TerrainKind>,
    /// Per-tile ground type (row-major). Not hashed yet.
    ground: Vec<Ground>,
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
            planet_of: alloc::vec![None; count],
            terrain: alloc::vec![TerrainKind::Barren; count],
            ground: alloc::vec![Ground::Grass; count],
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

    /// The planet owning tile `(x, y)`, or `None` for open space / out of bounds.
    #[must_use]
    #[allow(
        clippy::cast_sign_loss,
        reason = "coordinates are bounds-checked non-negative before the cast"
    )]
    pub fn planet_at(&self, x: i32, y: i32) -> Option<PlanetId> {
        if self.in_bounds(x, y) {
            let idx = (y as usize) * usize::from(self.width) + (x as usize);
            self.planet_of[idx]
        } else {
            None
        }
    }

    /// Assigns tile `(x, y)` to a planet (procgen only; static thereafter).
    pub fn set_planet(&mut self, x: u16, y: u16, planet: PlanetId) {
        if x < self.width && y < self.height {
            let idx = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.planet_of[idx] = Some(planet);
        }
    }

    /// The terrain class at `(x, y)`, or [`TerrainKind::Barren`] if out of bounds.
    #[must_use]
    #[allow(
        clippy::cast_sign_loss,
        reason = "coordinates are bounds-checked non-negative before the cast"
    )]
    pub fn terrain_at(&self, x: i32, y: i32) -> TerrainKind {
        if self.in_bounds(x, y) {
            let index = (y as usize) * usize::from(self.width) + (x as usize);
            self.terrain[index]
        } else {
            TerrainKind::Barren
        }
    }

    /// Sets the terrain class at `(x, y)`. Out-of-bounds coordinates are ignored.
    pub fn set_terrain(&mut self, x: u16, y: u16, kind: TerrainKind) {
        if x < self.width && y < self.height {
            let index = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.terrain[index] = kind;
        }
    }

    /// The ground type at `(x, y)`, or [`Ground::Grass`] if out of bounds.
    #[must_use]
    #[allow(
        clippy::cast_sign_loss,
        reason = "coordinates are bounds-checked non-negative before the cast"
    )]
    pub fn ground_at(&self, x: i32, y: i32) -> Ground {
        if self.in_bounds(x, y) {
            let index = (y as usize) * usize::from(self.width) + (x as usize);
            self.ground[index]
        } else {
            Ground::Grass
        }
    }

    /// Iterates over every tile's ground in row-major order.
    pub fn ground_iter(&self) -> impl Iterator<Item = Ground> + '_ {
        self.ground.iter().copied()
    }

    /// Sets the ground at `(x, y)` and updates the tile's `passable`/`buildable`
    /// flags from the ground's rules. Out-of-bounds coordinates are ignored.
    pub fn set_ground(&mut self, x: u16, y: u16, g: Ground) {
        if x < self.width && y < self.height {
            let index = usize::from(y) * usize::from(self.width) + usize::from(x);
            self.ground[index] = g;
            let p = g.props();
            self.tiles[index] = Tile {
                passable: p.passable,
                buildable: p.buildable,
            };
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
    use super::{Deposit, DepositKind, Ground, Map, Tile};

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

    #[test]
    fn ground_defaults_to_grass_and_out_of_bounds_is_grass() {
        let m = Map::new(4, 4);
        assert_eq!(m.ground_at(1, 1), Ground::Grass);
        assert_eq!(m.ground_at(-1, 0), Ground::Grass);
        assert_eq!(m.ground_at(99, 99), Ground::Grass);
    }

    #[test]
    fn set_ground_updates_tile_flags_from_the_table() {
        let mut m = Map::new(4, 4);
        m.set_ground(2, 2, Ground::River);
        let t = m.tile(2, 2).unwrap();
        assert!(!t.passable && !t.buildable);
        m.set_ground(2, 2, Ground::Shore);
        let t = m.tile(2, 2).unwrap();
        assert!(t.passable && !t.buildable);
        m.set_ground(2, 2, Ground::Grass);
        assert!(m.tile(2, 2).unwrap().buildable);
    }

    #[test]
    fn ground_tags_round_trip_and_glyphs_are_unique() {
        for g in Ground::ALL {
            assert_eq!(Ground::from_tag(g.tag()), Some(g));
        }
        let mut glyphs: Vec<char> = Ground::ALL.iter().map(|g| g.glyph()).collect();
        glyphs.sort_unstable();
        glyphs.dedup();
        assert_eq!(glyphs.len(), Ground::ALL.len());
        assert_eq!(Ground::from_tag(200), None);
    }

    #[test]
    fn heuristic_floor_is_the_cheapest_passable_cost() {
        let min = Ground::ALL
            .iter()
            .filter(|g| g.props().passable)
            .map(|g| g.props().path_cost)
            .min()
            .unwrap();
        assert_eq!(min, Ground::MIN_PASSABLE_COST);
    }
}
