//! Kestrel Reach: a hand-authored 44x26 Earthfront map. Glyphs: see `Ground::glyph`.
//!
//! The home colony sits in Sunfield (west). The Calder River runs north-west to
//! south-east into Kestrel Bay and can only be crossed at the two-hex Wyllow Ford.
//! East of the river lie The Dry Flats (alien holdfast) under Ironback Ridge (alloy).

use crate::game::map::{Deposit, DepositKind, Ground, Map};

pub const MAP_NAME: &str = "Kestrel Reach";
/// Home Command Centre tile and alien holdfast tile (both authored on passable ground).
///
/// `HOLDFAST` is the holdfast's muster hex, where alien waves spawn; the alien Core
/// Node stands one hex east of it at [`CORE_NODE`] (the same spawn-beside-core
/// relation `survival` uses), so the hex itself stays open ground.
pub const HOME_CC: (u16, u16) = (7, 9);
pub const HOLDFAST: (u16, u16) = (36, 8);
/// The alien Core Node (enemy Command Centre): destroying it wins the mission.
pub const CORE_NODE: (u16, u16) = (37, 8);

pub struct Region {
    pub name: &'static str,
    pub kind: &'static str,
    pub x0: u16,
    pub y0: u16,
    pub x1: u16,
    pub y1: u16,
}

pub const REGIONS: [Region; 8] = [
    Region {
        name: "Sunfield",
        kind: "grassland",
        x0: 2,
        y0: 4,
        x1: 13,
        y1: 14,
    },
    Region {
        name: "Hollow Wood",
        kind: "forest",
        x0: 4,
        y0: 16,
        x1: 13,
        y1: 23,
    },
    Region {
        name: "Calder River",
        kind: "river",
        x0: 13,
        y0: 0,
        x1: 37,
        y1: 25,
    },
    Region {
        name: "Wyllow Ford",
        kind: "ford",
        x0: 21,
        y0: 10,
        x1: 24,
        y1: 12,
    },
    Region {
        name: "The Dry Flats",
        kind: "flats",
        x0: 24,
        y0: 6,
        x1: 38,
        y1: 16,
    },
    Region {
        name: "Ironback Ridge",
        kind: "highland",
        x0: 24,
        y0: 0,
        x1: 43,
        y1: 5,
    },
    Region {
        name: "Kestrel Bay",
        kind: "sea",
        x0: 32,
        y0: 18,
        x1: 43,
        y1: 25,
    },
    Region {
        name: "Colony",
        kind: "colony",
        x0: 5,
        y0: 7,
        x1: 10,
        y1: 11,
    },
];

/// Row-major text map, one glyph per hex (flat-top odd-q).
///
/// The river is a two-hex band, six-connected from the north edge into the bay,
/// so the ford (`w`, row 10) is the only crossing; scenario tests verify this by
/// flood fill.
pub const ROWS: [&str; 26] = [
    "ggggggggggggggrrgggggggghhhhhhhhhhhhhhhhhhhh",
    "gggggggggggggggrrggggggghhhhhhhhhhhhhhhhhhhh",
    "ggttggggggggggggrrgggggghhhhhhhhhhhhhhhhhhhh",
    "ggtggggggggtggggrrgggggghhhhhhhhhhhhhhhhhhhh",
    "ggggggggggmgggggggrrgggghhhhhhhhhhhhhhhhhhhh",
    "gggmmggggmmgggggggrrgggggghhhhhhhhhhhhhhhhhh",
    "gggmgggggggmmggggggrrfffffffffffffffffffffff",
    "ggggggggggggmgggggggrrffffffffffffffffffffff",
    "gggggggggggggggggggggrrfffffffffffffffffffff",
    "ggggggggggggggggggggggrrffffffffffffffffffff",
    "ggggggggggggggggggggggwwffffffffffffffffffff",
    "ggggggggggggggggggggggggrrffffffffffffffffff",
    "gggmmggggggmmgggttggggggrrfffffffcffffffffff",
    "ggggmgggggggmggggggggggggrrfffffffffffffffff",
    "ggggggggggggggggggggggggggrrffffffffffffffff",
    "gggggggggggggggggggggggggggrrffffffcffffffff",
    "gggggtttttttggggggggggggggggrrffffffffffffff",
    "gggggttttttttgggggggggggggggrrfffffffffsssss",
    "gggggttttttttgggggggggggggggggrrfffffssooooo",
    "gggggttttttttgggggggggggggggggrrfffssooooooo",
    "gggggttttttttggggggggggggggggggrrssooooooooo",
    "gggggttttttttggggggggggggggggggsrooooooooooo",
    "gggggttttttttggggggggggggggggggsoooooooooooo",
    "ggggggtttttggggggggggggggggggggsoooooooooooo",
    "gggggggggggggggggggggggggggggggsoooooooooooo",
    "gggggggggggggggggggggggggggggggsoooooooooooo",
];

const HOME_ORE: Deposit = Deposit {
    kind: DepositKind::Ore,
    remaining: 30_000,
};
const ORE: Deposit = Deposit {
    kind: DepositKind::Ore,
    remaining: 24_000,
};
const ALLOY: Deposit = Deposit {
    kind: DepositKind::Alloy,
    remaining: 15_000,
};

/// Authored deposits.
///
/// Home ore in Sunfield two hexes from the CC (mirroring
/// `survival`'s home deposit two rows from its founding site), three west-bank
/// ores toward the river (`(18, 7)` touches the water, with river-side plant
/// and refinery sites at `(18, 6)` / `(19, 7)`), two east-bank ores on the flats
/// and three alloy seams on the Ironback Ridge crest.
pub const DEPOSITS: [(u16, u16, Deposit); 9] = [
    (7, 11, HOME_ORE),
    (18, 7, ORE),
    (19, 10, ORE),
    (19, 13, ORE),
    (27, 8, ORE),
    (31, 17, ORE),
    (31, 2, ALLOY),
    (35, 1, ALLOY),
    (39, 3, ALLOY),
];

/// The authored battlefield: ground from [`ROWS`] (which also sets each tile's
/// passable/buildable flags) plus [`DEPOSITS`].
#[must_use]
pub fn build_map() -> Map {
    let mut map = Map::new(44, 26);
    for (y, row) in (0u16..).zip(ROWS) {
        for (x, c) in (0u16..).zip(row.chars()) {
            if let Some(g) = Ground::from_glyph(c) {
                map.set_ground(x, y, g);
            }
        }
    }
    for (x, y, d) in DEPOSITS {
        map.set_deposit(x, y, d);
    }
    map
}

/// Tiles of the Ford, derived from `ROWS` ('w').
pub fn ford_tiles() -> impl Iterator<Item = (u16, u16)> {
    (0u16..).zip(ROWS).flat_map(|(y, row)| {
        (0u16..)
            .zip(row.chars())
            .filter(|&(_, c)| c == 'w')
            .map(move |(x, _)| (x, y))
    })
}
