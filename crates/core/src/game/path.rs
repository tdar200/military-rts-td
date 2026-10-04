//! Deterministic hex-grid pathfinding (A*).
//!
//! Movement around walls and buildings uses A* over the **hexagonal** tile grid
//! (six neighbors per cell, see [`hex`](super::hex)). To stay bit-identical across
//! platforms it uses an integer per-step cost and an open set ordered by
//! `(f_score, tile_index)` — the tile index tie-breaker gives a total order, so the
//! search expands nodes in the same sequence everywhere. No floats.

use crate::game::hex;
use crate::game::map::Map;
use alloc::collections::BinaryHeap;
use alloc::vec::Vec;
use core::cmp::Reverse;

/// Uniform cost of stepping to any of the six hex neighbors.
const STEP: i64 = 10;

/// Hex-distance heuristic, in the same integer units as the step cost
/// (admissible, so A* stays optimal).
fn heuristic(from: (u16, u16), to: (u16, u16)) -> i64 {
    i64::from(hex::distance(from, to)) * STEP
}

fn passable(map: &Map, x: i32, y: i32) -> bool {
    map.tile(x, y).is_some_and(|t| t.passable)
}

/// Finds the shortest hex path from `start` to `goal`.
///
/// Returns the waypoints *after* `start` up to and including `goal`, an empty
/// path if `start == goal`, or `None` if no route exists.
#[must_use]
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "tile coords are bounds-checked non-negative and < the u16 grid"
)]
pub fn find_path(map: &Map, start: (u16, u16), goal: (u16, u16)) -> Option<Vec<(u16, u16)>> {
    if start.0 >= map.width()
        || start.1 >= map.height()
        || goal.0 >= map.width()
        || goal.1 >= map.height()
    {
        return None;
    }
    if start == goal {
        return Some(Vec::new());
    }
    if !passable(map, i32::from(goal.0), i32::from(goal.1)) {
        return None;
    }
    let width = usize::from(map.width());
    let height = usize::from(map.height());
    let count = width * height;
    let index = |x: u16, y: u16| usize::from(y) * width + usize::from(x);

    let mut g_score = alloc::vec![i64::MAX; count];
    let mut came_from = alloc::vec![usize::MAX; count];
    let start_i = index(start.0, start.1);
    let goal_i = index(goal.0, goal.1);
    g_score[start_i] = 0;

    // Min-heap on (f_score, tile_index); the index breaks ties for determinism.
    let mut open = BinaryHeap::new();
    open.push(Reverse((heuristic(start, goal), start_i)));

    while let Some(Reverse((_, current))) = open.pop() {
        if current == goal_i {
            return Some(reconstruct(&came_from, current, width));
        }
        let cx = (current % width) as u16;
        let cy = (current / width) as u16;
        let here = g_score[current];
        for (nx, ny) in hex::neighbors(cx, cy) {
            if nx < 0 || ny < 0 || nx >= i32::from(map.width()) || ny >= i32::from(map.height()) {
                continue;
            }
            if !passable(map, nx, ny) {
                continue;
            }
            let neighbor = index(nx as u16, ny as u16);
            let tentative = here + STEP;
            if tentative < g_score[neighbor] {
                g_score[neighbor] = tentative;
                came_from[neighbor] = current;
                let f = tentative + heuristic((nx as u16, ny as u16), goal);
                open.push(Reverse((f, neighbor)));
            }
        }
    }
    None
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "tile indices are < width*height which fits the u16 grid"
)]
fn reconstruct(came_from: &[usize], goal: usize, width: usize) -> Vec<(u16, u16)> {
    let mut path = Vec::new();
    let mut node = goal;
    while came_from[node] != usize::MAX {
        path.push(((node % width) as u16, (node / width) as u16));
        node = came_from[node];
    }
    path.reverse();
    path
}

#[cfg(test)]
mod tests {
    use super::find_path;
    use crate::game::map::{Map, Tile};

    #[test]
    fn start_equals_goal_is_empty_path() {
        let m = Map::new(5, 5);
        assert_eq!(find_path(&m, (2, 2), (2, 2)), Some(Vec::new()));
    }

    #[test]
    fn straight_path_on_open_map_reaches_goal() {
        let m = Map::new(5, 5);
        let path = find_path(&m, (0, 0), (4, 0)).expect("path exists");
        assert_eq!(path.last(), Some(&(4, 0)));
        assert!(!path.is_empty());
    }

    #[test]
    fn path_routes_around_a_wall() {
        let mut m = Map::new(5, 5);
        // Wall along column x=2 for rows 0..=3, leaving (2,4) open as the gap.
        for y in 0..4 {
            m.set_tile(2, y, Tile::BLOCKED);
        }
        let path = find_path(&m, (0, 0), (4, 0)).expect("path exists via the gap");
        assert_eq!(path.last(), Some(&(4, 0)));
        // never steps on a blocked tile
        for &(x, y) in &path {
            assert!(m.tile(i32::from(x), i32::from(y)).unwrap().passable);
        }
    }

    #[test]
    fn no_path_when_fully_walled_off() {
        let mut m = Map::new(5, 5);
        for y in 0..5 {
            m.set_tile(2, y, Tile::BLOCKED);
        }
        assert_eq!(find_path(&m, (0, 0), (4, 0)), None);
    }

    #[test]
    fn deterministic_same_path_each_call() {
        let mut m = Map::new(8, 8);
        m.set_tile(3, 0, Tile::BLOCKED);
        m.set_tile(3, 1, Tile::BLOCKED);
        m.set_tile(3, 2, Tile::BLOCKED);
        let a = find_path(&m, (0, 0), (7, 7));
        let b = find_path(&m, (0, 0), (7, 7));
        assert_eq!(a, b);
        assert!(a.is_some());
    }
}

#[cfg(test)]
mod qa_bounds {
    use super::*;
    #[test]
    fn invalid_endpoints_are_rejected_without_panicking() {
        let map = Map::new(8, 8);
        assert_eq!(find_path(&map, (u16::MAX, u16::MAX), (1, 1)), None);
        assert_eq!(find_path(&map, (9, 9), (9, 9)), None);
    }
}
