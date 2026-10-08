//! Deterministic hex-grid pathfinding (A*).
//!
//! Movement around walls and buildings uses A* over the **hexagonal** tile grid
//! (six neighbors per cell, see [`hex`](super::hex)). To stay bit-identical across
//! platforms it uses an integer per-step cost (the ground cost of the tile entered) and an open set ordered by
//! `(f_score, tile_index)` — the tile index tie-breaker gives a total order, so the
//! search expands nodes in the same sequence everywhere. No floats.

use crate::game::hex;
use crate::game::map::{Ground, Map};
use alloc::collections::BinaryHeap;
use alloc::vec::Vec;
use core::cmp::Reverse;

/// Cost of stepping onto tile `(x, y)`: the [`Ground`] `path_cost` of the tile being
/// entered (`Grass` is 10, so all-grass maps cost what the old uniform step did).
fn step_cost(map: &Map, x: u16, y: u16) -> i64 {
    i64::from(map.ground_at(i32::from(x), i32::from(y)).props().path_cost)
}

/// Cheapest step cost of any passable tile on `map`: the heuristic's per-hex factor.
///
/// Scaling by the map's own cheapest tile keeps the heuristic admissible while leaving
/// all-grass maps at the legacy factor of 10, so their expansion order and tie-breaking,
/// hence their paths, are unchanged. [`Ground::MIN_PASSABLE_COST`] is the lower bound
/// every passable ground must respect, so the scan stops as soon as it is reached.
/// Callers guarantee a passable tile exists (the goal), so the result is a real cost.
fn min_step_cost(map: &Map) -> i64 {
    let floor = i64::from(Ground::MIN_PASSABLE_COST);
    let mut min = i64::MAX;
    for y in 0..map.height() {
        for x in 0..map.width() {
            if passable(map, i32::from(x), i32::from(y)) {
                let cost = step_cost(map, x, y);
                debug_assert!(
                    cost >= floor,
                    "passable ground cheaper than MIN_PASSABLE_COST"
                );
                min = min.min(cost);
                if min <= floor {
                    return min;
                }
            }
        }
    }
    min
}

/// Hex-distance heuristic in the same integer units as the step cost (admissible, so A*
/// stays optimal): `per_hex` is the map's cheapest step, see [`min_step_cost`].
fn heuristic(from: (u16, u16), to: (u16, u16), per_hex: i64) -> i64 {
    i64::from(hex::distance(from, to)) * per_hex
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

    let per_hex = min_step_cost(map);
    let mut g_score = alloc::vec![i64::MAX; count];
    let mut came_from = alloc::vec![usize::MAX; count];
    let start_i = index(start.0, start.1);
    let goal_i = index(goal.0, goal.1);
    g_score[start_i] = 0;

    // Min-heap on (f_score, tile_index); the index breaks ties for determinism.
    let mut open = BinaryHeap::new();
    open.push(Reverse((heuristic(start, goal, per_hex), start_i)));

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
            let tentative = here + step_cost(map, nx as u16, ny as u16);
            if tentative < g_score[neighbor] {
                g_score[neighbor] = tentative;
                came_from[neighbor] = current;
                let f = tentative + heuristic((nx as u16, ny as u16), goal, per_hex);
                open.push(Reverse((f, neighbor)));
            }
        }
    }
    None
}

/// [`find_path`] with enterable obstacles.
///
/// The same A*, heuristic and `(f_score, tile_index)` tie-break, except that
/// an impassable tile `(x, y)`
/// may be entered at the cost `extra(x, y)` returns (`None` keeps it blocked).
///
/// With `extra` always `None` it returns exactly what [`find_path`] returns.
/// Kestrel depth breaching (Task 16) uses it to route a blocked wave through
/// the defender's structures. Costs below the map's cheapest passable step
/// make the heuristic inadmissible (the path is then still deterministic, just
/// not always the cheapest); breach costs are many times a grass step.
#[must_use]
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "tile coords are bounds-checked non-negative and < the u16 grid"
)]
pub fn find_path_weighted(
    map: &Map,
    start: (u16, u16),
    goal: (u16, u16),
    extra: &dyn Fn(u16, u16) -> Option<i64>,
) -> Option<Vec<(u16, u16)>> {
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
    // Cost of entering a tile: its ground cost when passable, else `extra`.
    let enter = |x: u16, y: u16| {
        if passable(map, i32::from(x), i32::from(y)) {
            Some(step_cost(map, x, y))
        } else {
            extra(x, y)
        }
    };
    enter(goal.0, goal.1)?;
    let width = usize::from(map.width());
    let height = usize::from(map.height());
    let count = width * height;
    let index = |x: u16, y: u16| usize::from(y) * width + usize::from(x);

    // A map whose only enterable tiles are obstacles has no passable floor:
    // fall back to the floor every passable ground respects.
    let per_hex = match min_step_cost(map) {
        i64::MAX => i64::from(Ground::MIN_PASSABLE_COST),
        cost => cost,
    };
    let mut g_score = alloc::vec![i64::MAX; count];
    let mut came_from = alloc::vec![usize::MAX; count];
    let start_i = index(start.0, start.1);
    let goal_i = index(goal.0, goal.1);
    g_score[start_i] = 0;

    // Min-heap on (f_score, tile_index); the index breaks ties for determinism.
    let mut open = BinaryHeap::new();
    open.push(Reverse((heuristic(start, goal, per_hex), start_i)));

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
            let Some(step) = enter(nx as u16, ny as u16) else {
                continue;
            };
            let neighbor = index(nx as u16, ny as u16);
            let tentative = here + step;
            if tentative < g_score[neighbor] {
                g_score[neighbor] = tentative;
                came_from[neighbor] = current;
                let f = tentative + heuristic((nx as u16, ny as u16), goal, per_hex);
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
mod ground_cost_tests {
    use super::find_path;
    use crate::game::map::{Ground, Map, Tile};

    #[test]
    fn all_grass_path_matches_legacy_step_cost() {
        let m = Map::new(10, 10);
        let p = find_path(&m, (0, 0), (5, 0)).unwrap();
        assert_eq!(*p.last().unwrap(), (5, 0));
    }

    #[test]
    fn river_blocks_and_ford_is_the_only_crossing() {
        let mut m = Map::new(9, 5);
        for y in 0..5 {
            m.set_ground(4, y, Ground::River);
        }
        assert!(find_path(&m, (0, 2), (8, 2)).is_none());
        m.set_ground(4, 4, Ground::Ford);
        let p = find_path(&m, (0, 2), (8, 2)).unwrap();
        assert!(p.contains(&(4, 4)));
    }

    #[test]
    fn path_prefers_cheap_flats_over_a_short_highland_cut() {
        let mut m = Map::new(12, 5);
        for x in 3..9 {
            m.set_ground(x, 2, Ground::Highland);
            m.set_ground(x, 0, Ground::Flats);
        }
        let p = find_path(&m, (0, 2), (11, 2)).unwrap();
        let highland = p
            .iter()
            .filter(|&&(x, y)| m.ground_at(i32::from(x), i32::from(y)) == Ground::Highland)
            .count();
        assert!(
            highland < 6,
            "should detour over cheaper ground, crossed {highland} highland tiles"
        );
    }

    #[test]
    fn unreachable_goal_returns_none_without_hanging() {
        // A passable goal enclosed by a ring of River/Sea: the search must exhaust the
        // reachable region and report None, not stop early on an impassable goal.
        let mut m = Map::new(9, 9);
        let goal = (4u16, 4u16);
        for (nx, ny) in crate::game::hex::neighbors(goal.0, goal.1) {
            let (x, y) = (u16::try_from(nx).unwrap(), u16::try_from(ny).unwrap());
            m.set_ground(
                x,
                y,
                if (x + y) % 2 == 0 {
                    Ground::River
                } else {
                    Ground::Sea
                },
            );
        }
        assert!(m.tile(4, 4).unwrap().passable, "goal itself is passable");
        assert!(find_path(&m, (0, 0), goal).is_none());
    }

    /// Dijkstra oracle: cheapest total entered-tile cost from `start` to `goal`, or None.
    /// Same rules as `find_path` (hex neighbours, passable tiles, cost of the tile entered).
    fn oracle(map: &Map, start: (u16, u16), goal: (u16, u16)) -> Option<i64> {
        let (w, h) = (usize::from(map.width()), usize::from(map.height()));
        let mut dist = vec![i64::MAX; w * h];
        let mut done = vec![false; w * h];
        dist[usize::from(start.1) * w + usize::from(start.0)] = 0;
        loop {
            let mut best = None;
            for i in 0..w * h {
                if !done[i] && dist[i] != i64::MAX && best.is_none_or(|b: usize| dist[i] < dist[b])
                {
                    best = Some(i);
                }
            }
            let cur = best?;
            done[cur] = true;
            let (cx, cy) = (
                u16::try_from(cur % w).unwrap(),
                u16::try_from(cur / w).unwrap(),
            );
            if (cx, cy) == goal {
                return Some(dist[cur]);
            }
            for (nx, ny) in crate::game::hex::neighbors(cx, cy) {
                if nx < 0 || ny < 0 || nx >= i32::from(map.width()) || ny >= i32::from(map.height())
                {
                    continue;
                }
                if !map.tile(nx, ny).is_some_and(|t| t.passable) {
                    continue;
                }
                let ni = usize::try_from(ny).unwrap() * w + usize::try_from(nx).unwrap();
                let step = i64::from(map.ground_at(nx, ny).props().path_cost);
                dist[ni] = dist[ni].min(dist[cur] + step);
            }
        }
    }

    #[test]
    fn find_path_is_optimal_against_a_dijkstra_oracle_on_mixed_ground() {
        const MIX: [Ground; 13] = [
            Ground::Grass,
            Ground::Grass,
            Ground::Grass,
            Ground::Flats,
            Ground::Flats,
            Ground::Flats,
            Ground::Highland,
            Ground::Highland,
            Ground::Forest,
            Ground::Forest,
            Ground::Ford,
            Ground::River,
            Ground::Sea,
        ];
        let mut seed: u64 = 0x5EED_0003;
        let mut roll = |bound: usize| {
            seed = seed
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            usize::try_from((seed >> 33) % bound as u64).unwrap()
        };
        let (mut reachable, mut unreachable) = (0, 0);
        for _ in 0..200 {
            let width = u16::try_from(8 + roll(9)).unwrap();
            let height = u16::try_from(8 + roll(9)).unwrap();
            let mut map = Map::new(width, height);
            for y in 0..height {
                for x in 0..width {
                    map.set_ground(x, y, MIX[roll(MIX.len())]);
                }
            }
            for _ in 0..6 {
                let start = (
                    u16::try_from(roll(usize::from(width))).unwrap(),
                    u16::try_from(roll(usize::from(height))).unwrap(),
                );
                let goal = (
                    u16::try_from(roll(usize::from(width))).unwrap(),
                    u16::try_from(roll(usize::from(height))).unwrap(),
                );
                let found = find_path(&map, start, goal);
                let goal_ok = map
                    .tile(i32::from(goal.0), i32::from(goal.1))
                    .unwrap()
                    .passable;
                // find_path never checks the start tile, so the oracle matches it by
                // searching from `start` regardless of its own ground.
                let want = if goal_ok {
                    oracle(&map, start, goal)
                } else {
                    None
                };
                assert_eq!(found.is_some(), want.is_some(), "{start:?}->{goal:?}");
                if let (Some(path), Some(best)) = (found, want) {
                    reachable += 1;
                    assert_eq!(cost(&map, &path), best, "suboptimal {start:?}->{goal:?}");
                    let mut prev = start;
                    for &step in &path {
                        let adjacent = crate::game::hex::neighbors(prev.0, prev.1)
                            .contains(&(i32::from(step.0), i32::from(step.1)));
                        assert!(adjacent, "non-adjacent step {prev:?}->{step:?}");
                        prev = step;
                    }
                } else {
                    unreachable += 1;
                }
            }
        }
        assert!(
            reachable > 300 && unreachable > 50,
            "{reachable}/{unreachable}"
        );
    }

    /// Legacy (uniform step 10, heuristic 10/hex) path pinned from before ground costs
    /// existed: with h=9 on grass the equal-cost tie-break would pick a different route.
    #[test]
    fn all_grass_obstacle_map_keeps_the_legacy_tie_break() {
        let mut seed: u64 = 12_345;
        // `n % bound` is below `bound`, which fits u16, so the narrowing never fails.
        let mut roll = |bound: u16| {
            seed = seed
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            u16::try_from(((seed >> 33) as u32) % u32::from(bound)).unwrap()
        };
        let width = 12 + roll(10);
        let height = 12 + roll(10);
        let mut map = Map::new(width, height);
        for _ in 0..(u32::from(width) * u32::from(height) / 4) {
            let (tx, ty) = (roll(width), roll(height));
            map.set_tile(tx, ty, Tile::BLOCKED);
        }
        let start = (roll(width), roll(height));
        let goal = (roll(width), roll(height));
        let path = find_path(&map, start, goal).unwrap();
        let want = [
            (12, 13),
            (12, 12),
            (12, 11),
            (12, 10),
            (12, 9),
            (12, 8),
            (12, 7),
            (12, 6),
            (12, 5),
            (12, 4),
            (11, 3),
            (11, 2),
            (10, 2),
            (9, 1),
            (8, 1),
            (7, 0),
        ];
        assert_eq!(path, want);
    }

    /// Cost of a path (sum of entered-tile costs) on `m`.
    fn cost(m: &Map, p: &[(u16, u16)]) -> i64 {
        p.iter()
            .map(|&(x, y)| i64::from(m.ground_at(i32::from(x), i32::from(y)).props().path_cost))
            .sum()
    }

    #[test]
    fn flats_corridor_is_cheaper_than_equal_length_grass() {
        let mut m = Map::new(16, 10);
        for x in 0..16u16 {
            m.set_ground(x, 5, Ground::Flats);
        }
        let p = find_path(&m, (0, 5), (15, 5)).unwrap();
        assert_eq!(cost(&m, &p), 15 * 9);
    }

    #[test]
    fn blocked_tiles_still_block_on_mixed_maps() {
        let mut m = Map::new(5, 5);
        for y in 0..5 {
            m.set_tile(2, y, Tile::BLOCKED);
        }
        m.set_ground(1, 1, Ground::Flats);
        assert_eq!(find_path(&m, (0, 0), (4, 0)), None);
    }
}

#[cfg(test)]
mod weighted_tests {
    use super::{find_path, find_path_weighted};
    use crate::game::map::{Ground, Map, Tile};

    #[test]
    fn weighted_path_crosses_a_wall_only_when_needed() {
        let mut m = Map::new(10, 3);
        for y in 0..3 {
            m.set_tile(5, y, Tile::BLOCKED);
        }
        assert!(find_path(&m, (1, 1), (8, 1)).is_none());
        let p = find_path_weighted(&m, (1, 1), (8, 1), &|x, _| (x == 5).then_some(60)).unwrap();
        assert!(p.iter().any(|&(x, _)| x == 5));
        let open = Map::new(10, 3);
        assert_eq!(
            find_path_weighted(&open, (1, 1), (8, 1), &|_, _| None),
            find_path(&open, (1, 1), (8, 1))
        );
    }

    #[test]
    fn weighted_path_prefers_a_detour_cheaper_than_the_wall() {
        // A wall with a gap at the bottom: a 60-cost wall hex is dearer than the
        // few extra grass steps around, so the weighted path takes the gap.
        let mut m = Map::new(10, 6);
        for y in 0..5 {
            m.set_tile(5, y, Tile::BLOCKED);
        }
        let p = find_path_weighted(&m, (1, 3), (8, 3), &|_, _| Some(60)).unwrap();
        assert!(p
            .iter()
            .all(|&(x, y)| m.tile(x.into(), y.into()).unwrap().passable));
        assert_eq!(p, find_path(&m, (1, 3), (8, 3)).unwrap());
        // A dearer detour (the gap is far away) goes through the wall instead.
        let mut long = Map::new(10, 30);
        for y in 0..29 {
            long.set_tile(5, y, Tile::BLOCKED);
        }
        let p = find_path_weighted(&long, (1, 1), (8, 1), &|_, _| Some(60)).unwrap();
        assert!(p.iter().any(|&(x, _)| x == 5));
    }

    #[test]
    fn weighted_path_matches_find_path_on_mixed_ground_without_extras() {
        // Same A*, same tie-break: with no enterable impassable tile the two
        // searches agree on every route of a mixed map, found or not.
        let mut m = Map::new(16, 12);
        let mix = [
            Ground::Grass,
            Ground::Flats,
            Ground::Highland,
            Ground::Forest,
            Ground::River,
        ];
        for y in 0..12u16 {
            for x in 0..16u16 {
                m.set_ground(x, y, mix[usize::from((x * 7 + y * 3) % 5)]);
            }
        }
        for (s, g) in [((0, 0), (15, 11)), ((3, 4), (12, 2)), ((15, 0), (0, 11))] {
            assert_eq!(
                find_path_weighted(&m, s, g, &|_, _| None),
                find_path(&m, s, g)
            );
        }
    }

    #[test]
    fn weighted_path_never_enters_an_impassable_tile_without_a_cost() {
        let mut m = Map::new(10, 3);
        for y in 0..3 {
            m.set_tile(5, y, Tile::BLOCKED);
        }
        assert!(find_path_weighted(&m, (1, 1), (8, 1), &|_, y| (y == 9).then_some(60)).is_none());
        assert_eq!(
            find_path_weighted(&m, (9, 9), (1, 1), &|_, _| Some(1)),
            None
        );
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
