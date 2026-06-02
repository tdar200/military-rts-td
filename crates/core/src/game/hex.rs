//! Flat-top **offset-hex** geometry (odd-q layout: odd columns shoved down half a
//! row), matching the Field Command design's hex campaign map.
//!
//! Tiles keep their `(col, row)` integer addressing — storage and indexing in
//! [`Map`](super::map::Map) are unchanged — but adjacency, distance, and the
//! world position of a cell are hex-aware. Adjacency/distance route through cube
//! (axial) coordinates so they are provably correct; world↔cell conversions stay
//! in fixed-point so the simulation remains deterministic and float-free.
//!
//! World spacing is in tile units: columns are `3/4` apart in x, rows `1` apart in
//! y, and odd columns are offset `+1/2` in y. This keeps cell spacing near one
//! unit so unit speeds stay calibrated to the old square grid.

use crate::fixed::Fixed;
use crate::vec::Vec2;

/// The six axial neighbor directions, in a fixed order (determinism).
const AXIAL_DIRS: [(i32, i32); 6] = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

const fn offset_to_axial(col: i32, row: i32) -> (i32, i32) {
    (col, row - (col - (col & 1)) / 2)
}

const fn axial_to_offset(q: i32, r: i32) -> (i32, i32) {
    (q, r + (q - (q & 1)) / 2)
}

/// The six neighbor cells of `(col, row)` in offset coordinates, in a fixed order.
/// Entries may be out of bounds (negative or past an edge); callers bounds-check.
#[must_use]
pub fn neighbors(col: u16, row: u16) -> [(i32, i32); 6] {
    let (q, r) = offset_to_axial(i32::from(col), i32::from(row));
    let mut out = [(0, 0); 6];
    let mut i = 0;
    while i < 6 {
        let (dq, dr) = AXIAL_DIRS[i];
        out[i] = axial_to_offset(q + dq, r + dr);
        i += 1;
    }
    out
}

/// Hex (grid) distance between two cells — the minimum number of steps.
#[must_use]
pub fn distance(a: (u16, u16), b: (u16, u16)) -> i32 {
    let (aq, ar) = offset_to_axial(i32::from(a.0), i32::from(a.1));
    let (bq, br) = offset_to_axial(i32::from(b.0), i32::from(b.1));
    let dq = aq - bq;
    let dr = ar - br;
    let ds = -dq - dr;
    (dq.abs() + dr.abs() + ds.abs()) / 2
}

/// World-space center of cell `(col, row)`.
#[must_use]
pub fn center(col: u16, row: u16) -> Vec2 {
    let half = Fixed::from_ratio(1, 2);
    let x = Fixed::from_int(i32::from(col)) * Fixed::from_ratio(3, 4) + half;
    let mut y = Fixed::from_int(i32::from(row)) + half;
    if col & 1 == 1 {
        y = y + half;
    }
    Vec2::new(x, y)
}

fn clamp_round(f: Fixed, max: u16) -> u16 {
    let v = f.round_to_int().clamp(0, i64::from(max) - 1);
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "clamped into 0..max-1 which fits u16"
    )]
    {
        v as u16
    }
}

/// The cell nearest a world position, clamped into the `width × height` grid.
/// Deterministic fixed-point rounding (no floats) so client and server agree.
#[must_use]
pub fn from_world(p: Vec2, width: u16, height: u16) -> (u16, u16) {
    let half = Fixed::from_ratio(1, 2);
    // col = round((x - 0.5) / 0.75)
    let col = clamp_round((p.x - half) * Fixed::from_ratio(4, 3), width);
    // row = round(y - 0.5 - (col odd ? 0.5 : 0))
    let mut yy = p.y - half;
    if col & 1 == 1 {
        yy = yy - half;
    }
    let row = clamp_round(yy, height);
    (col, row)
}

#[cfg(test)]
mod tests {
    use super::{center, distance, from_world, neighbors};

    #[test]
    fn neighbors_are_six_and_distance_one() {
        // A cell well inside the grid has six neighbors, each at hex distance 1.
        let nb = neighbors(4, 4);
        let mut count = 0;
        for &(c, r) in &nb {
            assert!(c >= 0 && r >= 0);
            #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
            let d = distance((4, 4), (c as u16, r as u16));
            assert_eq!(d, 1, "neighbor ({c},{r}) should be distance 1");
            count += 1;
        }
        assert_eq!(count, 6);
    }

    #[test]
    fn distance_is_symmetric_and_zero_to_self() {
        assert_eq!(distance((3, 3), (3, 3)), 0);
        assert_eq!(distance((0, 0), (5, 2)), distance((5, 2), (0, 0)));
    }

    #[test]
    fn from_world_round_trips_cell_centers() {
        // The center of a cell maps back to that cell.
        for col in 0..8u16 {
            for row in 0..8u16 {
                assert_eq!(from_world(center(col, row), 8, 8), (col, row));
            }
        }
    }
}
