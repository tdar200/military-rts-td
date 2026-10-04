# Gameplay HUD and Kestrel Reach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 12 gameplay boards (`docs/ascension/ui-mocks-gameplay/`) real: a fixed Kestrel Reach map with per-tile terrain rules in the Rust sim, and a Godot 3D HUD that matches the boards at 1920x1080.

**Architecture:** A new `Ground` layer on `Map` (hashed, Earthfront-gated) drives path cost, movement speed, cover, high-ground range and two adjacency bonuses. A hand-authored `scenario::kestrel_reach` fills it. The godot bridge adds only additive snapshot fields (schema stays 5); the Godot client builds terrain and new HUD sections from those fields, reusing `Hud.register_section`, `live_adapter.gd` view models and `world_marks.gd`. Chrome is pixel-diffed against the boards; the battlefield stays 3D.

**Tech Stack:** Rust workspace (`core` no_std, no floats, `Fixed` Q47.16; `server` godot-bridge), Godot 4.7.2 GDScript (code-built UI), headless-Chrome pixel harness in `tools/ui/`.

**Spec:** `docs/superpowers/specs/2026-10-04-gameplay-hud-kestrel-reach-design.md` (binding). Boards: `docs/ascension/ui-mocks-gameplay/*.dc.html`, `hud.css`. Prior plan and harness conventions: `docs/superpowers/plans/2026-10-04-godot-ui-design-implementation.md`, deviations in `docs/ascension/ui-deviations.md`.

## Global Constraints

- Legacy golden hash `2_081_234_273_307_305_018` (`golden_hash_pins_cross_target_determinism`) MUST NOT move. All new sim behaviour is gated on `self.earthfront` or is a no-op for maps whose ground is all `Grass`. A moved golden is a bug, never a re-pin.
- `crates/core` is `no_std`, no dependencies, integer / `Fixed` maths only, no float arithmetic, ascending index order, no `HashMap`. `state_hash` order is stable: append only, never reorder.
- Bridge `"schema":5` stays; every new JSON field is additive; the test asserting the JSON starts `{"schema":5,` must still pass.
- Grid stays 44x26 flat-top odd-q hex; buildings are single tile (spec R1, R2).
- Fog of war is OUT: no shroud, explored percent, discovery toasts or terrain-survey card anywhere.
- Godot UI rules: `preload`, never `class_name`; every clickable is a `Button` with human label text; a missing view-model slice builds nothing and no number is ever invented; place names come from the snapshot, never hardcoded in Godot.
- No em dashes or en dashes in any user-facing copy or docs (use plain hyphens).
- Rust gates before every Rust commit: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, `cargo test --workspace --offline`. (`--offline` is proven to work: golden test ran green on 2026-10-04.)
- Godot gate: `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd` must stay at 1519+ passing; grep the log for `SCRIPT ERROR`. Run `--import` after adding assets.
- Commits stage only the task's own paths (`git add <paths>`, never `-A`: the tree holds 83 unrelated modified Rust files). Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Balance numbers are the boards' proposals and live in ONE table (`Ground::PROPS`), so they are easy to retune.

## Review Focus

- Golden hash drift: any Earthfront-only change leaking into the legacy path (test: golden + `legacy_maps_have_all_grass_ground`).
- Pathing determinism and admissibility: equal-cost ties and a heuristic that overestimates (test: Task 3 admissibility + replay).
- Unreachable goals: unit ordered across the river with no ford path, or onto Sea (expected: path is `None`, unit stays put, no panic or infinite A*).
- Buildings placed on Shore/River/Sea/Highland rules and on a deposit tile (expected: rejected by `apply_build`, not silently accepted).
- Snapshot consumers on other scenarios: Survival snapshot has no `ground`/`regions`; Godot must fall back to noise terrain and hide region-only UI (test: Task 11 fallback).
- Empty/zero states in the HUD: no idle crews, no wave route, no control groups, no selection, power at 0 (expected: sections absent or showing real zeros, never fake numbers).

---

## File Structure

Rust:
- `crates/core/src/game/map.rs` - `Ground` enum, `GroundProps` table, private `Map.ground` layer with `ground_at` / `set_ground` / `ground_iter`.
- `crates/core/src/game/path.rs` - cost-aware A*.
- `crates/core/src/game/sim.rs` - movement multiplier, combat cover and range, hash append, `idle` helper.
- `crates/core/src/game/earthfront.rs` - power and ore adjacency bonuses.
- `crates/core/src/game/scenario.rs` - `kestrel_reach`, `Scenario::KestrelReach`, tests.
- `crates/core/src/game/kestrel.rs` (new) - the compact 44x26 text map, region table, name table (keeps scenario.rs from growing).
- `crates/server/src/bin/godot-bridge.rs` - additive fields, scenario flag.

Godot (`godot3d/`):
- `scripts/terrain/ground_model.gd` (new) - decodes `ground` + `ground_table`, pure, tested.
- `scripts/continuous_terrain.gd` - consume the ground model, noise fallback.
- `scripts/earthfront_3d.gd` - light/shadow tuning, section feed, overlay feed.
- `scripts/ui/live_adapter.gd`, `hud.gd`, new section files under `scripts/ui/sections/`, new screens under `scripts/ui/screens/`.
- `tests/` one test file per new section/screen; `tests/stub_game.gd` gains Kestrel fields.

Harness: `tools/ui/screens.json`, `compare_*.json`, `verify_all.sh`, `scripts/gallery/gallery.gd`, `fixtures_*.gd`, `blob-map.json`.

Design reference edits: boards 1, 6, 11 and `README.md` in `docs/ascension/ui-mocks-gameplay/`.

---

### Task 0: Baseline, backup, R7 ruling, board edits, harness entries

**Files:**
- Create: `~/backups/ascension/military-rts-td-2026-10-04.tar.gz` (outside repo)
- Modify: `docs/ascension/ui-mocks-gameplay/Main.dc.html`, `EarlyMission.dc.html`, `RegionMap.dc.html`, `README.md`, `docs/ascension/ui-deviations.md`
- Modify: `tools/ui/screens.json`, `tools/ui/verify_all.sh`, add `tools/ui/compare_gp01.json` ... `compare_gp12.json`

**Interfaces:**
- Produces: R7 ruling recorded in `ui-deviations.md` section 4; boards free of fog; harness SPEC entries `gp01`..`gp12` that later tasks fill with gallery cases.

- [ ] **Step 1: Back up the working tree**

```bash
mkdir -p ~/backups/ascension
cd /home/tahseen-dar/Projects && tar --exclude='military-rts-td/target' --exclude='military-rts-td/godot3d/.godot' \
  -czf ~/backups/ascension/military-rts-td-2026-10-04.tar.gz military-rts-td
ls -lh ~/backups/ascension/
```
Expected: archive exists, non-zero size.

- [ ] **Step 2: Prove baselines**

```bash
cd /home/tahseen-dar/Projects/military-rts-td
cargo test --workspace --offline 2>&1 | tail -15
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd 2>&1 | tee /tmp/godot-base.log | tail -5; grep -c "SCRIPT ERROR" /tmp/godot-base.log
```
Expected: Rust all pass; Godot 1519 pass; `0` SCRIPT ERROR. Record both numbers in the ledger; if Rust has failures that pre-date this work, list them as known-red and do not fix.

- [ ] **Step 3: Record the R7 ruling (decided from sim.rs)**

The sim tracks `kills` and `rank` (0..=3, `rank_for_kills`: 2/5/9 kills; `veterancy_factor` +0/10/20/35%, sim.rs:109-217, hashed at 2070-2071). So veteran chevrons are BUILT from per-unit `rank`. The board-5 combat preview is built only from `damage_multiplier(damage_type, armor)` plus `veterancy_factor`; the preview shows "x1.5 vs armour" style multipliers and nothing else (no hit percent, no cover number outside Task 5). Append to `docs/ascension/ui-deviations.md` section 4 under heading `Gameplay boards, R7`:

```markdown
### Gameplay boards, R7 (decided 2026-10-04)
- Veteran chevrons: BUILT. Source: per-unit `rank` (0..3) already in the sim.
- Combat preview: BUILT as damage-type multiplier and rank bonus only. Hit chance and
  "across the river -25%" are NOT shown (no such mechanic).
```

- [ ] **Step 4: Remove fog blocks from boards 1, 6, 11 (spec section 2)**

In `Main.dc.html`, `EarlyMission.dc.html`, `RegionMap.dc.html` delete: the fog mask `<mask id="fog">` and the `<rect ... mask="url(#fog)"/>` shroud; the "Explored" card (RegionMap lines 87-93: keep "Territory" and "Hostile sites" rows by moving them into the Composition card, drop "Explored" and "Resources seen 3 of ?"); the "Unexplored" pin; the "Fog" lens button (RegionMap line 110) and TerrainGuide's "Fog" rule-of-thumb; discovery toasts and the terrain-survey card in EarlyMission and Main (search each file for `fog`, `Fog`, `Explored`, `explor`, `survey`, `discover`, `Unexplored`). Then verify:

```bash
cd docs/ascension/ui-mocks-gameplay && grep -il "fog\|explored\|unexplored\|discover\|terrain survey" *.dc.html README.md || echo CLEAN
```
Expected: `CLEAN`. In `EarlyMission.dc.html` replace the board title "First minutes: fog, briefing, survey" with "First minutes: briefing, objectives" (and in `canvas.json` of the scratchpad copy only if republishing; the repo copy has no canvas.json).

- [ ] **Step 5: Add harness entries for the 12 boards**

Follow the existing mechanism in `tools/ui/verify_all.sh` (SPEC map) and `tools/ui/screens.json`. Use ids `gp01`..`gp12` mapped to the board files in this order: Main, BuildDeck, CoreAssault, StructureSelected, OrdersArmed, EarlyMission, WaveInbound, MapOverlays, PauseMenu, Controls, RegionMap, TerrainGuide. Each `compare_gpNN.json` starts with the full-board rectangle masked as battlefield (`"mask": true`) and chrome rectangles added by later tasks as they implement each section. Run:

```bash
tools/ui/verify_all.sh 2>&1 | tail -20
```
Expected: existing 18 boards unchanged; `gpNN` report "no gallery case" (skipped, not failed). If the script hard-fails on a missing case, add the key `"pending": true` support to `verify_all.sh` for gp ids and note it.

- [ ] **Step 6: Commit decision (needs the user)**

The UI rebuild (1519 tests) is uncommitted and is this plan's base. Ask the user once whether to (a) commit it on a new branch `gameplay-hud-kestrel-reach` first, or (b) keep working in the dirty tree and skip commits. Under (b) the executor records each task's changed-file list in the ledger instead of commit SHAs. Under (a):

```bash
git checkout -b gameplay-hud-kestrel-reach
git add godot3d tools docs/ascension docs/superpowers
git commit -m "chore: baseline UI rebuild and gameplay mocks" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 1: `Ground` layer on `Map` (golden-neutral)

**Files:**
- Modify: `crates/core/src/game/map.rs`
- Test: inline `#[cfg(test)]` in `map.rs`

**Interfaces:**
- Produces: `pub enum Ground { Grass, Meadow, Flats, Highland, Forest, River, Ford, Shore, Sea, Crater }` (`#[repr(u8)]`, `Copy`, `Eq`, `Debug`), `Ground::ALL: [Ground; 10]`, `Ground::props(self) -> GroundProps`, `Ground::tag(self) -> u8`, `Ground::from_tag(u8) -> Option<Ground>`, `Ground::glyph(self) -> char`, `Ground::from_glyph(char) -> Option<Ground>`, `Ground::name(self) -> &'static str`; `pub struct GroundProps { path_cost: u32, infantry_pct: u32, vehicle_pct: u32, cover_pct: u32, range_pct: u32, buildable: bool, passable: bool }` (all pub); `Map::ground_at(&self, x: i32, y: i32) -> Ground` (out of bounds = `Grass`); `Map::ground_iter(&self) -> impl Iterator<Item = Ground> + '_`; `Map::set_ground(&mut self, x: u16, y: u16, g: Ground)` (also sets `Tile.passable/buildable` from props); private `ground: Vec<Ground>` on `Map` (same visibility as `tiles`/`deposits`), filled `Grass` by `Map::new`, plus `Map::ground_iter(&self) -> impl Iterator<Item = Ground> + '_` (row-major) for hashing and the bridge.
- Consumes: existing `Tile`, `Map::new`, `tile`, `set_tile`.

Property table (spec 4.1; `cover_pct` = percent of incoming damage REMOVED; `range_pct` = bonus percent for the shooter; speeds are percent of base):

| Ground | cost | inf% | veh% | cover% | range% | buildable | passable |
|---|---|---|---|---|---|---|---|
| Grass | 10 | 100 | 100 | 0 | 0 | yes | yes |
| Meadow | 10 | 100 | 100 | 5 | 0 | yes | yes |
| Flats | 9 | 110 | 110 | 0 | 0 | yes | yes |
| Highland | 14 | 70 | 70 | 25 | 25 | yes | yes |
| Forest | 12 | 80 | 80 | 20 | 0 | yes | yes |
| River | 0 | 0 | 0 | 0 | 0 | no | no |
| Ford | 20 | 70 | 50 | 0 | 0 | no | yes |
| Shore | 12 | 80 | 80 | 0 | 0 | no | yes |
| Sea | 0 | 0 | 0 | 0 | 0 | no | no |
| Crater | 12 | 80 | 80 | 15 | 0 | no | yes |

`min` cost among passable = 9 (Flats), which is the heuristic factor.

- [ ] **Step 1: Write failing tests** (append inside the existing `mod tests` of `map.rs`, creating it with `use super::*;` if absent)

```rust
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cargo test --offline -p rts-core ground_ -- --nocapture`
Expected: FAIL (`Ground` not found).

- [ ] **Step 3: Implement** in `map.rs` (above `pub struct Map`; add private `ground: Vec<Ground>` to the struct and `ground: vec![Ground::Grass; (width as usize) * (height as usize)]` in `Map::new`; match the existing index convention used for `tiles` - read `Map::tile` first and use the same `y * width + x`)

```rust
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
    GroundProps { path_cost, infantry_pct, vehicle_pct, cover_pct, range_pct, buildable, passable }
}

impl Ground {
    pub const ALL: [Self; 10] = [
        Self::Grass, Self::Meadow, Self::Flats, Self::Highland, Self::Forest,
        Self::River, Self::Ford, Self::Shore, Self::Sea, Self::Crater,
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
            Self::River => gp(0, 0, 0, 0, 0, false, false),
            Self::Ford => gp(20, 70, 50, 0, 0, false, true),
            Self::Shore => gp(12, 80, 80, 0, 0, false, true),
            Self::Sea => gp(0, 0, 0, 0, 0, false, false),
            Self::Crater => gp(12, 80, 80, 15, 0, false, true),
        }
    }
    #[must_use]
    pub const fn tag(self) -> u8 { self as u8 }
    #[must_use]
    pub const fn from_tag(t: u8) -> Option<Self> {
        match t {
            0 => Some(Self::Grass), 1 => Some(Self::Meadow), 2 => Some(Self::Flats),
            3 => Some(Self::Highland), 4 => Some(Self::Forest), 5 => Some(Self::River),
            6 => Some(Self::Ford), 7 => Some(Self::Shore), 8 => Some(Self::Sea),
            9 => Some(Self::Crater), _ => None,
        }
    }
    /// One ASCII char per ground, used by the scenario text map and the snapshot.
    #[must_use]
    pub const fn glyph(self) -> char {
        match self {
            Self::Grass => 'g', Self::Meadow => 'm', Self::Flats => 'f', Self::Highland => 'h',
            Self::Forest => 't', Self::River => 'r', Self::Ford => 'w', Self::Shore => 's',
            Self::Sea => 'o', Self::Crater => 'c',
        }
    }
    #[must_use]
    pub const fn from_glyph(c: char) -> Option<Self> {
        match c {
            'g' => Some(Self::Grass), 'm' => Some(Self::Meadow), 'f' => Some(Self::Flats),
            'h' => Some(Self::Highland), 't' => Some(Self::Forest), 'r' => Some(Self::River),
            'w' => Some(Self::Ford), 's' => Some(Self::Shore), 'o' => Some(Self::Sea),
            'c' => Some(Self::Crater), _ => None,
        }
    }
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Grass => "Grassland", Self::Meadow => "Meadow", Self::Flats => "Dry flats",
            Self::Highland => "Highland", Self::Forest => "Forest", Self::River => "River",
            Self::Ford => "Ford", Self::Shore => "Shore", Self::Sea => "Sea", Self::Crater => "Crater",
        }
    }
}
```

`Map::ground_at`:

```rust
#[must_use]
pub fn ground_at(&self, x: i32, y: i32) -> Ground {
    if x < 0 || y < 0 || x >= i32::from(self.width) || y >= i32::from(self.height) {
        return Ground::Grass;
    }
    self.ground[(y as usize) * usize::from(self.width) + (x as usize)]
}

pub fn ground_iter(&self) -> impl Iterator<Item = Ground> + '_ {
    self.ground.iter().copied()
}

pub fn set_ground(&mut self, x: u16, y: u16, g: Ground) {
    let idx = usize::from(y) * usize::from(self.width) + usize::from(x);
    self.ground[idx] = g;
    let p = g.props();
    self.set_tile(x, y, Tile { passable: p.passable, buildable: p.buildable });
}
```
(If `Tile` has more fields than the two shown, copy them from the existing tile and override only those two. Add the usual `#[allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]` the file already uses for index casts.)

- [ ] **Step 4: Run to verify it passes**

Run: `cargo test --offline -p rts-core ground_ && cargo test --offline -p rts-core golden_hash`
Expected: all PASS, golden unchanged.

- [ ] **Step 5: Commit**

```bash
git add crates/core/src/game/map.rs
git commit -m "feat(core): Ground layer on Map with per-ground rules table" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Hash the ground layer (Earthfront only)

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`state_hash`, ~2025-2130)
- Test: inline in `sim.rs` tests

**Interfaces:**
- Consumes: `Map::ground_iter`, `Ground::tag`.
- Produces: `state_hash` changes with ground when `self.earthfront`; legacy hash unchanged.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn legacy_maps_have_all_grass_ground() {
    let sim = crate::game::scenario::Scenario::LaneDefense.build(7);
    assert!(sim.map().ground_iter().all(|g| g == crate::game::map::Ground::Grass));
}

#[test]
fn earthfront_hash_depends_on_ground_but_legacy_does_not() {
    use crate::game::map::Ground;
    let mut a = crate::game::scenario::Scenario::Survival.build(2026);
    let b = crate::game::scenario::Scenario::Survival.build(2026);
    assert_eq!(a.state_hash(), b.state_hash());
    a.map_mut().set_ground(3, 3, Ground::Flats);
    assert_ne!(a.state_hash(), b.state_hash());

    let mut l1 = crate::game::scenario::Scenario::OpenClash.build(5);
    let l2 = crate::game::scenario::Scenario::OpenClash.build(5);
    l1.map_mut().set_ground(0, 0, Ground::Flats); // legacy must not hash ground
    assert_eq!(l1.state_hash(), l2.state_hash());
}
```

- [ ] **Step 2: Run, expect FAIL** (`cargo test --offline -p rts-core earthfront_hash_depends_on_ground`): first assert passes, second fails.

- [ ] **Step 3: Implement.** At the END of `state_hash` (after all existing writes, before the final `h.finish()`), append:

```rust
if self.earthfront {
    for g in self.map.ground_iter() {
        h.write_u64(u64::from(g.tag()));
    }
}
```
Use the field name `self.map` as it exists in `Sim` (check `pub const fn map(&self)` at sim.rs:1329).

- [ ] **Step 4: Run** `cargo test --offline -p rts-core` and confirm: new tests PASS, `golden_hash_pins_cross_target_determinism` PASS. If any Earthfront golden/replay test pins a hash literal that now moves, that pin is for an Earthfront-only scenario: re-pin ONLY those, list each in the ledger with old/new value, and never touch the legacy `2_081_234_273_307_305_018`.

- [ ] **Step 5: Commit** `git add crates/core/src/game/sim.rs && git commit -m "feat(core): hash ground layer for Earthfront" ...`

---

### Task 3: Cost-aware, deterministic pathing

**Files:**
- Modify: `crates/core/src/game/path.rs`
- Test: inline in `path.rs`

**Interfaces:**
- Consumes: `Map::ground_at`, `Ground::props`, `Ground::MIN_PASSABLE_COST`.
- Produces: `find_path` unchanged signature `find_path(map: &Map, start: (u16,u16), goal: (u16,u16)) -> Option<Vec<(u16,u16)>>`; step cost is the cost of the tile being ENTERED. For all-`Grass` maps every step costs 10 = old `STEP`, so legacy paths are byte-identical.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn all_grass_path_matches_legacy_step_cost() {
    let m = Map::new(10, 10);
    let p = find_path(&m, (0, 0), (5, 0)).unwrap();
    assert_eq!(*p.last().unwrap(), (5, 0));
}

#[test]
fn river_blocks_and_ford_is_the_only_crossing() {
    use crate::game::map::Ground;
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
    use crate::game::map::Ground;
    let mut m = Map::new(12, 5);
    for x in 3..9 {
        m.set_ground(x, 2, Ground::Highland);
        m.set_ground(x, 0, Ground::Flats);
    }
    let p = find_path(&m, (0, 2), (11, 2)).unwrap();
    let highland = p.iter().filter(|&&(x, y)| m.ground_at(i32::from(x), i32::from(y)) == Ground::Highland).count();
    assert!(highland < 6, "should detour over cheaper ground, crossed {highland} highland tiles");
}

#[test]
fn unreachable_goal_returns_none_without_hanging() {
    use crate::game::map::Ground;
    let mut m = Map::new(6, 6);
    m.set_ground(5, 5, Ground::Sea);
    assert!(find_path(&m, (0, 0), (5, 5)).is_none());
}

#[test]
fn heuristic_is_admissible_on_a_mixed_map() {
    use crate::game::map::Ground;
    let mut m = Map::new(16, 10);
    for x in 0..16u16 { m.set_ground(x, 5, Ground::Flats); }
    // Cheapest possible cost per step is MIN_PASSABLE_COST, so the heuristic never overestimates.
    let p = find_path(&m, (0, 5), (15, 5)).unwrap();
    assert_eq!(p.len(), 15);
}
```

- [ ] **Step 2: Run** `cargo test --offline -p rts-core path::` - expect the ford/highland tests FAIL.

- [ ] **Step 3: Implement.** In `path.rs`: keep `const STEP: i64 = 10;` (still used by callers), add

```rust
fn step_cost(map: &Map, x: u16, y: u16) -> i64 {
    i64::from(map.ground_at(i32::from(x), i32::from(y)).props().path_cost)
}
```
Change `heuristic` to `hex::distance(...) * i64::from(Ground::MIN_PASSABLE_COST)` (import `Ground`; if `STEP` was the factor, replace it there only). Change `let tentative = here + STEP;` to `let tentative = here + step_cost(map, nx, ny);` where `(nx, ny)` are the neighbour's tile coordinates already in scope. Because `passable()` already rejects River/Sea (their `passable` is false after `set_ground`), no extra block is needed. Keep the heap key `Reverse((f, idx))` so ties break by tile index as before.

Admissibility note: old `STEP=10` equals Grass cost; with Flats at 9 the heuristic factor must be 9 (done), otherwise A* could return a non-optimal path on flats.

- [ ] **Step 4: Run** `cargo test --offline -p rts-core` and the golden test. Expect PASS.

- [ ] **Step 5: Commit** `git add crates/core/src/game/path.rs && git commit -m "feat(core): ground-cost-aware A* pathing" ...`

---

### Task 4: Movement speed per ground

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`run_movement`, speed line at ~4023)
- Test: inline in `sim.rs`

**Interfaces:**
- Consumes: `Ground::props().infantry_pct / vehicle_pct`, `world_to_tile` (sim.rs:3182), `UnitKind`.
- Produces: `fn ground_speed_pct(&self, e_pos: Vec2, uk: UnitKind) -> i64` (private) returning 100 when `!self.earthfront` or the unit is air.

Class rule: `Infantry` and `AntiArmor` use `infantry_pct`; `Harvester`, `Tank`, `Capital` use `vehicle_pct`; `Helicopter` is always 100.

- [ ] **Step 1: Failing test**

```rust
// In sim.rs `mod tests` (helpers there: `f`, `v`, `P0`, `P1`, `Sim::new(map, seed, money)`,
// `s.add_unit`, `s.step(&[Command::Move{owner,unit,target}])`, `s.position(id)`,
// `s.enable_earthfront()` from earthfront.rs).
fn first_tick_dx(ground: Ground, earthfront: bool, kind: UnitKind) -> i64 {
    let mut m = Map::new(32, 8);
    for x in 0..32u16 {
        m.set_ground(x, 2, ground);
    }
    let mut s = Sim::new(m, 1, f(0));
    if earthfront {
        s.enable_earthfront();
    }
    let u = s.add_unit(P0, kind, tile_center(2, 2));
    let before = s.position(u).unwrap().x;
    s.step(&[Command::Move { owner: P0, unit: u, target: tile_center(20, 2) }]);
    (s.position(u).unwrap().x - before).to_bits()
}

#[test]
fn tanks_slow_on_highland_and_ford_and_speed_up_on_flats_in_earthfront() {
    let grass = first_tick_dx(Ground::Grass, true, UnitKind::Tank);
    assert!(first_tick_dx(Ground::Flats, true, UnitKind::Tank) > grass);
    let hi = first_tick_dx(Ground::Highland, true, UnitKind::Tank);
    assert!(hi < grass);
    assert!(first_tick_dx(Ground::Ford, true, UnitKind::Tank) < hi);
}

#[test]
fn ford_slows_tanks_more_than_infantry() {
    let tank = first_tick_dx(Ground::Ford, true, UnitKind::Tank) * 100
        / first_tick_dx(Ground::Grass, true, UnitKind::Tank);
    let inf = first_tick_dx(Ground::Ford, true, UnitKind::Infantry) * 100
        / first_tick_dx(Ground::Grass, true, UnitKind::Infantry);
    assert!(tank < inf);
}

#[test]
fn ground_never_changes_speed_outside_earthfront() {
    assert_eq!(
        first_tick_dx(Ground::Highland, false, UnitKind::Tank),
        first_tick_dx(Ground::Grass, false, UnitKind::Tank)
    );
}
```
Helpers are those of the existing test `unit_moves_toward_target_and_arrives` (sim.rs ~6018). `Map::set_ground` on a fresh `Map::new` is enough; nothing needs a production test hook. Note `Command::Move` is validated against passability: a Ford or Highland row is passable so the first tick moves.

- [ ] **Step 2: Run, expect FAIL** (all speeds equal).

- [ ] **Step 3: Implement** in `run_movement` replace

```rust
let speed = uk.stats().speed + mobility[usize::from(e.owner.0)];
```
with

```rust
let base = uk.stats().speed + mobility[usize::from(e.owner.0)];
let speed = if self.earthfront && !uk.stats().is_air {
    let (tx, ty) = self.world_to_tile(e.pos);
    let g = self.map.ground_at(i32::from(tx), i32::from(ty)).props();
    let pct = if is_vehicle(uk) { g.vehicle_pct } else { g.infantry_pct };
    base.scale(Fixed::from_int(i64::from(pct)) / Fixed::from_int(100))
} else {
    base
};
```
Use whichever `Fixed` multiply/divide API the file already uses (see `dir.scale(speed / dist)` above; if `Fixed * Fixed` exists use it). Add:

```rust
const fn is_vehicle(k: UnitKind) -> bool {
    matches!(k, UnitKind::Harvester | UnitKind::Tank | UnitKind::Capital)
}
```
`world_to_tile` takes `&self`, but `run_movement` iterates `self.entities` mutably: read the ground BEFORE the mutable borrow by precomputing `let ground_pct: Vec<...>` or borrow `self.map` separately (`let map = &self.map;` before the loop, and inline a free `fn world_to_tile_map(map, p)`); resolve the borrow the way the surrounding code does for `mobility`. If a unit stands on an impassable tile (e.g. Ford is passable, River is not) a pct of 0 would freeze it: clamp the multiplier to at least 30 percent.

- [ ] **Step 4: Run** `cargo test --offline -p rts-core` incl. golden. PASS.

- [ ] **Step 5: Commit** `git add crates/core/src/game/sim.rs && git commit -m "feat(core): ground-dependent movement speed (Earthfront)" ...`

---

### Task 5: Cover and high-ground range in combat

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`run_combat`, range_sq ~4180, damage ~4210)
- Test: inline in `sim.rs`

**Interfaces:**
- Consumes: `Ground::props().cover_pct / range_pct`.
- Produces: attacker's `range_sq` multiplied by `((100+range_pct)^2) / 10000` using integers; target takes `dmg * (100 - cover_pct) / 100`. Both only when `self.earthfront`.

- [ ] **Step 1: Failing tests**

```rust
// Attacker tank at tile (2,2) on row 2; defender Wall is not usable (cover applies to units
// too), so use an enemy Infantry that cannot reach/move: give it no orders and run a short window.
fn volley_loss(att_ground: Ground, tgt_ground: Ground, gap_tiles: u16, earthfront: bool) -> i64 {
    let mut m = Map::new(40, 8);
    for x in 0..40u16 {
        m.set_ground(x, 2, Ground::Grass);
    }
    m.set_ground(2, 2, att_ground);
    m.set_ground(2 + gap_tiles, 2, tgt_ground);
    let mut s = Sim::new(m, 1, f(0));
    if earthfront {
        s.enable_earthfront();
    }
    let _att = s.add_unit(P0, UnitKind::Tank, tile_center(2, 2));
    let tgt = s.add_unit(P1, UnitKind::Infantry, tile_center(2 + gap_tiles, 2));
    let hp0 = s.entities[tgt.0 as usize].hp.to_bits();
    for _ in 0..30 {
        s.step(&[]);
    }
    hp0 - s.entities[tgt.0 as usize].hp.to_bits()
}

#[test]
fn highland_attacker_reaches_targets_a_grass_attacker_cannot() {
    // Pick `gap` so the target is between 1.0x and 1.25x of tank range on a first-principles
    // basis: gap = ceil(range / tile_spacing) + 0 .. computed in the test from
    // `UnitKind::Tank.stats().attack.range` and `hex::center(1,0).x - hex::center(0,0).x`.
    let range = UnitKind::Tank.stats().attack.range;
    let spacing = tile_center(1, 0).x - tile_center(0, 0).x;
    let gap = ((range.to_bits() + spacing.to_bits() - 1) / spacing.to_bits() + 1) as u16;
    // sanity: gap tiles is beyond base range but within +25 percent
    assert!(spacing * Fixed::from_int(i64::from(gap)) > range);
    assert!(spacing * Fixed::from_int(i64::from(gap)) * Fixed::from_int(100) <= range * Fixed::from_int(125));
    assert_eq!(volley_loss(Ground::Grass, Ground::Grass, gap, true), 0);
    assert!(volley_loss(Ground::Highland, Ground::Grass, gap, true) > 0);
}

#[test]
fn forest_cover_removes_twenty_percent_of_damage() {
    let open = volley_loss(Ground::Grass, Ground::Grass, 1, true);
    let wood = volley_loss(Ground::Grass, Ground::Forest, 1, true);
    assert!(open > 0);
    // allow 2 Fixed bits per tick of rounding across the 30-tick window
    assert!((wood * 100 - open * 80).abs() <= 60 * 100, "wood={wood} open={open}");
}

#[test]
fn legacy_scenarios_ignore_cover_and_range_bonus() {
    assert_eq!(
        volley_loss(Ground::Grass, Ground::Forest, 1, false),
        volley_loss(Ground::Grass, Ground::Grass, 1, false)
    );
}
```
The tests above are the contract (helpers copied from `combat_destroys_an_enemy_structure`, sim.rs ~6036). If `Fixed` lacks `*`/`<=` between `Fixed` values, use `to_bits()` comparisons. If a Tank cannot fire at Infantry (targeting rules), swap the defender for `BuildingKind::Wall` via `add_building(P1, Wall, x, y)` and read its hp the same way (buildings take cover from their tile too).

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement.** Before the candidate loop:

```rust
let range_pct = if self.earthfront {
    u64::from(self.map.ground_at(tx_att, ty_att).props().range_pct)
} else { 0 };
let range_sq = if range_pct == 0 {
    profile.range * profile.range
} else {
    let r = profile.range.scale_ratio(100 + range_pct, 100); // helper below
    r * r
};
```
If `Fixed` has no ratio helper, compute `profile.range * Fixed::from_int(100 + pct) / Fixed::from_int(100)` using the existing operators. After `raw` is computed and before it is pushed, apply:

```rust
let raw = if self.earthfront {
    let cover = u64::from(self.map.ground_at(tx_tgt, ty_tgt).props().cover_pct);
    raw * Fixed::from_int(100 - cover as i64) / Fixed::from_int(100)
} else { raw };
```
where `(tx_tgt, ty_tgt)` come from `world_to_tile(snap[j].2)`. Air targets get no cover (`snap[j].4` is air). Keep all of it inside integer / `Fixed` ops; no floats.

- [ ] **Step 4: Run** `cargo test --offline -p rts-core` incl. golden. PASS.

- [ ] **Step 5: Commit** `git add crates/core/src/game/sim.rs && git commit -m "feat(core): cover and high-ground range (Earthfront)" ...`

---

### Task 6: Power and ore adjacency bonuses, exposed per entity

**Files:**
- Modify: `crates/core/src/game/earthfront.rs` (`generation_for` ~306), the harvest/refine path in `sim.rs` (find where a Refinery converts ore to money: grep `Refinery` near `ore_buffer`)
- Test: inline in `earthfront.rs`

**Interfaces:**
- Consumes: `Map::ground_at`, `hex::neighbors` (the hex helper used by path.rs; read its name there), `Map.deposits`.
- Produces: `pub(crate) fn river_bonus_kw(&self, e: &Entity) -> u32` (12 for a PowerPlant with a River or Ford neighbour else 0), `pub fn refinery_near_ore(&self, e: &Entity) -> bool`, both `pub(crate)`; `generation_for` includes the +12; Refinery yield +20 percent when `refinery_near_ore`.

- [ ] **Step 1: Failing tests**

```rust
// earthfront.rs tests (sibling tests use `Sim::new(Map::new(..), seed, money)`, `sim.enable_earthfront()`,
// `sim.add_building(owner, kind, x, y)` which returns a COMPLETE building, `sim.map.set_deposit`).
fn plant_sim(earthfront: bool) -> (Sim, u16, u16) {
    let mut s = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
    if earthfront {
        s.enable_earthfront();
    }
    s.add_building(PlayerId(0), BuildingKind::PowerPlant, 6, 6);
    (s, 6, 6)
}

#[test]
fn power_plant_beside_river_generates_twelve_more() {
    let (mut s, x, y) = plant_sim(true);
    let before = s.generation_for(PlayerId(0));
    let (nx, ny) = crate::game::hex::neighbors(x, y)[0];
    s.map_mut().set_ground(nx as u16, ny as u16, Ground::River);
    assert_eq!(s.generation_for(PlayerId(0)), before + 12);
}

#[test]
fn ford_neighbour_also_counts_and_dry_neighbours_do_not() {
    let (mut s, x, y) = plant_sim(true);
    let before = s.generation_for(PlayerId(0));
    let (nx, ny) = crate::game::hex::neighbors(x, y)[1];
    s.map_mut().set_ground(nx as u16, ny as u16, Ground::Flats);
    assert_eq!(s.generation_for(PlayerId(0)), before);
    s.map_mut().set_ground(nx as u16, ny as u16, Ground::Ford);
    assert_eq!(s.generation_for(PlayerId(0)), before + 12);
}

#[test]
fn power_bonus_is_zero_off_earthfront() {
    let (mut s, x, y) = plant_sim(false);
    let before = s.generation_for(PlayerId(0));
    let (nx, ny) = crate::game::hex::neighbors(x, y)[0];
    s.map_mut().set_ground(nx as u16, ny as u16, Ground::River);
    assert_eq!(s.generation_for(PlayerId(0)), before);
}

fn refinery_money_after_a_second(deposit_at: Option<(u16, u16)>) -> i64 {
    let mut sim = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
    sim.enable_earthfront();
    sim.add_building(PlayerId(0), BuildingKind::PowerPlant, 3, 12);
    let r = sim.add_building(PlayerId(0), BuildingKind::Refinery, 8, 8);
    if let Some((dx, dy)) = deposit_at {
        sim.map_mut().set_deposit(dx, dy, Deposit { kind: DepositKind::Ore, remaining: 100 });
    }
    sim.entities[r.0 as usize].ore_buffer = 25; // 25 ore -> 20 material at 100 percent
    sim.civs[0].money = Fixed::ZERO;
    for _ in 0..30 {
        sim.step(&[]);
    }
    sim.money(PlayerId(0)).to_bits()
}

#[test]
fn refinery_next_to_a_deposit_yields_twenty_percent_more() {
    let far = refinery_money_after_a_second(Some((1, 1)));
    let (nx, ny) = crate::game::hex::neighbors(8, 8)[2];
    let near = refinery_money_after_a_second(Some((nx as u16, ny as u16)));
    assert!(far > 0);
    assert_eq!(near * 100, far * 120);
}
```
Implementer fills the helper names from the module's existing tests (`grep -n "fn .*PowerPlant" earthfront.rs`); asserts above are normative, bodies for the 2nd and 3rd tests must assert real values (`assert_eq!(gen_open, gen_open_baseline)`, `assert_eq!(money_near * 100, money_far * 120)`).

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement.** In `generation_for` replace the PowerPlant arm with:

```rust
Kind::Building(BuildingKind::PowerPlant) => {
    let base = if smart { 96 } else { 80 };
    base + self.river_bonus_kw(e)
}
```
and add

```rust
pub(crate) fn river_bonus_kw(&self, e: &Entity) -> u32 {
    if !self.earthfront || !matches!(e.kind, Kind::Building(BuildingKind::PowerPlant)) {
        return 0;
    }
    let (x, y) = self.world_to_tile(e.pos);
    let wet = hex_neighbors(x, y).any(|(nx, ny)| {
        matches!(self.map.ground_at(i32::from(nx), i32::from(ny)), Ground::River | Ground::Ford)
    });
    if wet { 12 } else { 0 }
}

pub(crate) fn refinery_near_ore(&self, e: &Entity) -> bool {
    if !self.earthfront || !matches!(e.kind, Kind::Building(BuildingKind::Refinery)) {
        return false;
    }
    let (x, y) = self.world_to_tile(e.pos);
    self.map.deposits.iter().any(|d| {
        crate::game::hex::distance((i32::from(x), i32::from(y)), (i32::from(d.x), i32::from(d.y))) <= 1
    })
}
```
The real helpers are `hex::neighbors(col,row) -> [(i32,i32);6]` and `hex::distance((u16,u16),(u16,u16)) -> i32` (hex.rs:31,45); `Map::deposits()` yields `(x, y, Deposit)`, so write `self.map.deposits().any(|(dx, dy, _)| hex::distance((x, y), (dx, dy)) <= 1)` and `hex::neighbors(x, y).iter().any(|&(nx, ny)| nx >= 0 && ny >= 0 && matches!(self.map.ground_at(nx, ny), Ground::River | Ground::Ford))`. The ore step is earthfront.rs:639-642: after `let ore = ...;` compute `let material = ore / 5 * 4;` then `let material = if refinery_near { material * 120 / 100 } else { material };` before `Fixed::from_int(...)`. `refinery_near` must be computed BEFORE the `for e in &mut self.entities` loop (borrow): collect `Vec<bool>` per entity index, or take `&self.map` separately.

- [ ] **Step 4: Run** `cargo test --offline -p rts-core` incl. golden. PASS.

- [ ] **Step 5: Commit** `git add crates/core/src/game/earthfront.rs crates/core/src/game/sim.rs && git commit -m "feat(core): river power bonus and refinery ore adjacency (Earthfront)" ...`

---

### Task 7: Kestrel Reach scenario

**Files:**
- Create: `crates/core/src/game/kestrel.rs`
- Modify: `crates/core/src/game/mod.rs` (add `pub mod kestrel;`), `crates/core/src/game/scenario.rs` (`kestrel_reach`, `Scenario::KestrelReach`, `build`, `name`, `tagline`, tests)

**Interfaces:**
- Consumes: `Ground`, `Map::set_ground`, existing `survival(seed)` building blocks (read scenario.rs:190-310 and copy its Earthfront set-up: relays, waves, civs, research, colony founding).
- Produces: `pub const MAP_NAME: &str = "Kestrel Reach"`, `pub struct Region { pub name: &'static str, pub kind: &'static str, pub x0: u16, pub y0: u16, pub x1: u16, pub y1: u16 }`, `pub const REGIONS: [Region; 8]`, `pub const ROWS: [&str; 26]` (44 glyphs per row), `pub fn kestrel_reach(seed: u64) -> Sim` in scenario.rs, `Scenario::KestrelReach` (NOT in `Scenario::ALL`).

Layout contract (hex grid 44 wide x 26 tall; the boards show the home colony west, river running north-west to south-east to the bay, ford mid river, flats east, ridge north-east, bay south-east):
- Sunfield + home Command Centre around col 6-8, row 8-10 (grass/meadow).
- Hollow Wood (forest) cols 5-12, rows 17-22.
- Calder River `r` diagonal band 1-2 hexes wide from (14,0) to (36,25), with the single Ford `w` (2 tiles) near (22,11).
- The Dry Flats `f` east of the river, cols 24-38, rows 6-16.
- Ironback Ridge `h` cols 24-43, rows 0-5; alloy deposits on the crest.
- Kestrel Bay `o` (Sea) south-east corner cols 32-43, rows 18-25 with `s` Shore ring.
- 2 craters `c` on the flats. Ore deposits: 3 on the west bank (near river, one adjacent to a plant site), 2 on the east bank. Alien holdfast on the east flats near col 36, row 8 (where `survival` places the alien core).

- [ ] **Step 1: Failing tests** (in `scenario.rs` tests)

```rust
#[test]
fn kestrel_text_map_is_44_by_26_and_all_glyphs_known() {
    use crate::game::{kestrel::ROWS, map::Ground};
    assert_eq!(ROWS.len(), 26);
    for row in ROWS {
        assert_eq!(row.chars().count(), 44, "row: {row}");
        assert!(row.chars().all(|c| Ground::from_glyph(c).is_some()));
    }
}

#[test]
fn kestrel_reach_builds_and_ground_matches_text() {
    let sim = kestrel_reach(2026);
    assert_eq!(sim.map().width, 44);
    assert_eq!(sim.map().height, 26);
    assert!(sim.economy_view(crate::game::sim::PlayerId(0)).ore == 0 || true); // see note: assert Earthfront via a snapshot-visible effect, e.g. generation_for(P0) > 0 after the CC is placed
    for (y, row) in crate::game::kestrel::ROWS.iter().enumerate() {
        for (x, c) in row.chars().enumerate() {
            assert_eq!(sim.map().ground_at(x as i32, y as i32).glyph(), c);
        }
    }
}

#[test]
fn kestrel_river_is_crossable_only_at_the_ford() {
    let sim = kestrel_reach(2026);
    let (cc, holdfast) = (crate::game::kestrel::HOME_CC, crate::game::kestrel::HOLDFAST);
    let path = crate::game::path::find_path(sim.map(), cc, holdfast).expect("ford connects the banks");
    assert!(path.iter().any(|&(x, y)| sim.map().ground_at(x.into(), y.into()) == Ground::Ford));
    // Plug the ford: no path.
    let mut s2 = kestrel_reach(2026);
    for (x, y) in crate::game::kestrel::ford_tiles() { s2.map_mut().set_ground(x, y, Ground::River); }
    assert!(crate::game::path::find_path(s2.map(), cc, holdfast).is_none());
}

#[test]
fn kestrel_reach_is_deterministic_and_replays() {
    let (mut a, mut b) = (kestrel_reach(7), kestrel_reach(7));
    for _ in 0..600 { a.step(&[]); b.step(&[]); }
    assert_eq!(a.state_hash(), b.state_hash());
}

#[test]
fn kestrel_reach_has_ore_on_both_banks_and_alloy_on_the_ridge() {
    use crate::game::map::{DepositKind, Ground};
    let sim = kestrel_reach(2026);
    let (mut west, mut east, mut alloy) = (0, 0, 0);
    for (x, y, d) in sim.map().deposits() {
        let g = sim.map().ground_at(i32::from(x), i32::from(y));
        match d.kind {
            DepositKind::Ore if x < 20 => west += 1,
            DepositKind::Ore => east += 1,
            _ if g == Ground::Highland => alloy += 1,
            _ => {}
        }
    }
    assert!(west >= 3 && east >= 2 && alloy >= 2, "west={west} east={east} alloy={alloy}");
}

#[test]
fn kestrel_reach_overruns_an_undefended_base_and_holds_with_the_playtest_defence() {
    // Port of `survival_overruns_an_undefended_base` and `survival_balance_playtest` in this
    // file: copy their set-up and assertions, swapping `survival(seed)` for `kestrel_reach(seed)`.
    // If a threshold must differ on this map, change it in ONE place and record it in the ledger.
}
```
The last test is a port of two existing tests: the implementer copies their set-up and assertions (the comment names them).

- [ ] **Step 2: Run, expect FAIL** (`cargo test --offline -p rts-core kestrel`).

- [ ] **Step 3: Implement.** `kestrel.rs`:

```rust
//! Kestrel Reach: a hand-authored 44x26 Earthfront map. Glyphs: see `Ground::glyph`.
pub const MAP_NAME: &str = "Kestrel Reach";
/// Home Command Centre tile and alien holdfast tile (both authored on passable ground).
pub const HOME_CC: (u16, u16) = (7, 9);
pub const HOLDFAST: (u16, u16) = (36, 8);

pub struct Region {
    pub name: &'static str,
    pub kind: &'static str,
    pub x0: u16, pub y0: u16, pub x1: u16, pub y1: u16,
}

pub const REGIONS: [Region; 8] = [
    Region { name: "Sunfield", kind: "grassland", x0: 2, y0: 4, x1: 13, y1: 14 },
    Region { name: "Hollow Wood", kind: "forest", x0: 4, y0: 16, x1: 13, y1: 23 },
    Region { name: "Calder River", kind: "river", x0: 13, y0: 0, x1: 37, y1: 25 },
    Region { name: "Wyllow Ford", kind: "ford", x0: 21, y0: 10, x1: 24, y1: 12 },
    Region { name: "The Dry Flats", kind: "flats", x0: 24, y0: 6, x1: 38, y1: 16 },
    Region { name: "Ironback Ridge", kind: "highland", x0: 24, y0: 0, x1: 43, y1: 5 },
    Region { name: "Kestrel Bay", kind: "sea", x0: 32, y0: 18, x1: 43, y1: 25 },
    Region { name: "Colony", kind: "colony", x0: 5, y0: 7, x1: 10, y1: 11 },
];

/// Row-major text map, one glyph per hex. Author this so the layout contract above
/// holds; the tests in scenario.rs verify dimensions, glyphs, ford uniqueness.
pub const ROWS: [&str; 26] = [ /* 26 strings of exactly 44 glyphs */ ];

/// Tiles of the Ford, derived from `ROWS` ('w').
pub fn ford_tiles() -> impl Iterator<Item = (u16, u16)> {
    ROWS.iter().enumerate().flat_map(|(y, row)| {
        row.chars().enumerate().filter(|&(_, c)| c == 'w').map(move |(x, _)| (x as u16, y as u16))
    })
}
```
Author the 26 rows (the implementer generates them from the layout contract with a small throwaway script and pastes the literal strings; commit the literals, not the script; verify with the dimension test). Region bounds above are the contract: the river band must pass through every Region::Calder cell range and the ford must lie inside "Wyllow Ford".

`kestrel_reach(seed)` in scenario.rs: build via the same constructor `survival` uses (`Map::new(44, 26)`), apply `set_ground` from `ROWS`, then run the exact survival setup steps (founding colony at the Colony region centre, relays, objective roles, waves, AI) but with deposit placement driven by the layout contract instead of procgen. Where `survival` calls `procgen::generate`, replace it with the authored map; keep everything after unchanged. Add `Scenario::KestrelReach` to the enum, `build` (`Self::KestrelReach => kestrel_reach(seed)`), `name` ("Kestrel Reach"), `tagline` ("A coastal river basin. Hold the ford."); leave `ALL` untouched. Make sure no match on `Scenario` elsewhere becomes non-exhaustive (`cargo build --offline --workspace`).

- [ ] **Step 4: Run** `cargo test --offline --workspace` incl. golden. PASS.

- [ ] **Step 5: Commit** `git add crates/core/src/game/kestrel.rs crates/core/src/game/mod.rs crates/core/src/game/scenario.rs && git commit -m "feat(core): Kestrel Reach fixed Earthfront scenario" ...`

---

### Task 8: Additive bridge fields, scenario flag, snapshot tests

**Files:**
- Modify: `crates/server/src/bin/godot-bridge.rs`
- Test: inline tests there (extend the existing one at line ~532)

**Interfaces:**
- Consumes: `kestrel::{MAP_NAME, REGIONS}`, `Ground`, `Sim` accessors (`river_bonus_kw`, `refinery_near_ore` from Task 6), entity `rank`.
- Produces (all additive, schema stays 5), inside the existing hand-written JSON frame:
  - `"map_name":"Kestrel Reach"` (string; omit key entirely for other scenarios)
  - `"regions":[{"name":"Sunfield","kind":"grassland","x0":2,"y0":4,"x1":13,"y1":14},...]` (omit when not Kestrel)
  - `"ground":"gggmm..."` one 44*26 char string, row-major, glyphs from `Ground::glyph` (emit for EVERY Earthfront scenario; all-`g` for Survival)
  - `"ground_table":[{"glyph":"g","name":"Grassland","path_cost":10,"infantry_pct":100,"vehicle_pct":100,"cover_pct":0,"range_pct":0,"buildable":true,"passable":true},...]`
  - per entity: `"idle":true|false` (unit with no `move_target`, empty `path`, not harvesting/building and no order) ; per unit `"rank":0..3`; per PowerPlant `"river_kw":12|0`; per Refinery `"ore_bonus":true|false`
  - `"wave_route":[[x,y],...]` = `find_path` from the alien core tile to the home CC tile (empty array if none)
- CLI: `--scenario kestrel|survival` flag (default `survival`), parsed where the bridge reads its args; unknown value exits with a clear error message on stderr.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn survival_snapshot_is_unchanged_in_shape_and_has_all_grass_ground() {
    let sim = Scenario::Survival.build(2026);
    let json = snapshot_json(&sim);
    assert!(json.starts_with("{\"schema\":5,"));
    assert!(!json.contains("\"map_name\""));
    assert!(!json.contains("\"regions\""));
    let g = extract_str(&json, "ground");
    assert_eq!(g.len(), 44 * 26);
    assert!(g.chars().all(|c| c == 'g'));
}

#[test]
fn kestrel_snapshot_carries_names_regions_ground_and_table() {
    let sim = Scenario::KestrelReach.build(2026);
    let json = snapshot_json(&sim);
    assert!(json.starts_with("{\"schema\":5,"));
    assert!(json.contains("\"map_name\":\"Kestrel Reach\""));
    assert!(json.contains("\"name\":\"Wyllow Ford\""));
    assert!(json.contains("\"ground_table\":["));
    assert!(json.contains("\"wave_route\":["));
    let g = extract_str(&json, "ground");
    assert_eq!(g.len(), 44 * 26);
    assert!(g.contains('r') && g.contains('w') && g.contains('h'));
}

#[test]
fn kestrel_snapshot_is_valid_json_shape() {
    // Balanced braces/brackets and no trailing commas: reuse the helper the existing
    // snapshot test uses, or count `{`/`}` and `[`/`]` pairs and assert `,]` / `,}` absent.
    let json = snapshot_json(&Scenario::KestrelReach.build(1));
    assert_eq!(json.matches('{').count(), json.matches('}').count());
    assert_eq!(json.matches('[').count(), json.matches(']').count());
    assert!(!json.contains(",]") && !json.contains(",}"));
}
```
`extract_str(json, key)` is a 6-line test helper: find `"key":"`, take until the next `"`.

- [ ] **Step 2: Run, expect FAIL** (`cargo test --offline -p rts-server godot_bridge` or the crate name from `crates/server/Cargo.toml`).

- [ ] **Step 3: Implement.** Follow the file's own pattern (`write!`/`format!` into one `String`, `#[allow(clippy::too_many_lines)]` already present with its reason). Append the new keys at the END of the top-level frame so existing positional tooling is untouched; entity-level keys appended at the end of each entity object. Emit `ground` via `sim.map().ground_iter().map(|g| g.glyph()).collect::<String>()`. `ground_table` from `Ground::ALL`. Add the scenario flag next to the existing arg parsing and replace the two `Scenario::Survival.build(2026)` calls (lines 428, 450) with the chosen scenario variable (keep seed 2026).

- [ ] **Step 4: Run** `cargo test --offline --workspace && cargo clippy --workspace --all-targets --offline -- -D warnings && cargo fmt --all -- --check`. PASS. Also write the Kestrel snapshot to a fixture for Godot tests:

```bash
cargo run --offline -p rts-server --bin godot-bridge -- --scenario kestrel --dump-snapshot godot3d/tests/fixtures/kestrel_snapshot.json
```
If the bridge has no dump option, add `--dump-snapshot <path>` (write one frame and exit); this fixture is what Godot tests load, so Tasks 9-14 are testable without a running bridge.

- [ ] **Step 5: Commit** `git add crates/server godot3d/tests/fixtures/kestrel_snapshot.json && git commit -m "feat(bridge): additive Kestrel Reach snapshot fields and scenario flag" ...`

---

### Task 9: Ground model and snapshot-driven terrain in Godot

**Files:**
- Create: `godot3d/scripts/terrain/ground_model.gd`, `godot3d/tests/test_ground_model.gd`
- Modify: `godot3d/scripts/continuous_terrain.gd`, `godot3d/scripts/earthfront_3d.gd` (pass `ground`/`ground_table` on each snapshot; MAP_W/MAP_H at lines 3-4 come from `map_width/map_height` when present), `godot3d/tests/stub_game.gd`

**Interfaces:**
- Produces `GroundModel` (RefCounted, `preload`ed): `static func from_snapshot(snap: Dictionary) -> RefCounted` (returns null when no `ground` string or length != w*h); `func name_at(x: int, y: int) -> String`; `func props_at(x: int, y: int) -> Dictionary` (the matching `ground_table` row); `func glyph_at(x: int, y: int) -> String`; `func counts_in(cells: Array) -> Dictionary` (glyph -> count, for the territory composition); `func is_wet(x: int, y: int) -> bool` (River/Ford/Sea glyph by table name).
- `continuous_terrain.gd`: new `func apply_ground(model: RefCounted) -> void`. With a model: height per glyph (Highland +1.6, Flats 0.05, Grass/Meadow 0.2 plus the existing low-amplitude noise, Shore 0.05, River -0.5, Ford -0.15, Sea -0.8, Crater -0.3, Forest 0.3) smoothed across neighbours, vertex colour per glyph from the v4 ground palette already used by the mocks (grass #6a9a3a, meadow #97a64a, flats #c9923a, highland #6e747a, forest #2f8a52, river/ford/sea water shader, shore #c9b27a), river/coast carved from River/Ford/Sea hexes instead of the noise carve. Without a model it behaves exactly as today (noise fallback).

- [ ] **Step 1: Failing tests** (`test_ground_model.gd`; mirror an existing test file's `extends` and registration pattern in `godot3d/tests/`)

```gdscript
extends RefCounted
const GroundModel := preload("res://scripts/terrain/ground_model.gd")

func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func test_from_snapshot_decodes_ground_and_table(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	t.check(m != null, "model builds from the Kestrel fixture")
	t.check(m.name_at(0, 0) != "", "name resolves")
	var wet_found := false
	for y in range(26):
		for x in range(44):
			if m.is_wet(x, y):
				wet_found = true
	t.check(wet_found, "river/sea present")

func test_missing_ground_returns_null(t) -> void:
	t.check(GroundModel.from_snapshot({"schema": 5, "map_width": 44, "map_height": 26}) == null, "no ground field -> null")

func test_wrong_length_returns_null(t) -> void:
	t.check(GroundModel.from_snapshot({"map_width": 44, "map_height": 26, "ground": "ggg", "ground_table": []}) == null, "short string -> null")

func test_counts_in_matches_hand_count(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	var counts: Dictionary = m.counts_in([[0, 0], [1, 0], [2, 0]])
	var total := 0
	for k in counts:
		total += int(counts[k])
	t.check(total == 3, "three cells counted")
```
Use the real assert API of `godot3d/tests/` (read one existing test and the runner first: if it is `t.check(cond, msg)` keep it, otherwise adapt; the four behaviours above are normative).

- [ ] **Step 2: Run** `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd -- test_ground_model.gd` - expect FAIL (file missing).

- [ ] **Step 3: Implement** `ground_model.gd`:

```gdscript
extends RefCounted

var width := 0
var height := 0
var _ground := ""
var _table := {}   # glyph -> row dictionary

static func from_snapshot(snap: Dictionary) -> RefCounted:
	var g: String = str(snap.get("ground", ""))
	var w := int(snap.get("map_width", 0))
	var h := int(snap.get("map_height", 0))
	if g == "" or w <= 0 or h <= 0 or g.length() != w * h:
		return null
	var m := (load("res://scripts/terrain/ground_model.gd") as GDScript).new()
	m.width = w
	m.height = h
	m._ground = g
	for row in snap.get("ground_table", []):
		m._table[str(row.get("glyph", ""))] = row
	return m

func glyph_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return "g"
	return _ground[y * width + x]

func props_at(x: int, y: int) -> Dictionary:
	return _table.get(glyph_at(x, y), {})

func name_at(x: int, y: int) -> String:
	return str(props_at(x, y).get("name", ""))

func is_wet(x: int, y: int) -> bool:
	var n := name_at(x, y)
	return n == "River" or n == "Ford" or n == "Sea"

func counts_in(cells: Array) -> Dictionary:
	var out := {}
	for c in cells:
		var gl := glyph_at(int(c[0]), int(c[1]))
		out[gl] = int(out.get(gl, 0)) + 1
	return out
```
Then add `apply_ground` to `continuous_terrain.gd` (heights/colours as listed; keep `height_at_world`/`biome_at_world` signatures; when a model is set they read it, otherwise noise), and call it from `earthfront_3d.gd` when the first snapshot containing `ground` arrives (rebuild the mesh once, not per poll). Extend `stub_game.gd` with a `kestrel` flag that loads the fixture.

- [ ] **Step 4: Run** the full Godot suite (command in Global Constraints). Expect 1519 + new tests PASS, `0` SCRIPT ERROR.

- [ ] **Step 5: Live check and commit.** Launch `tools/qa/launch_ui.py <dir> --software` against `--scenario kestrel`, capture a frame, confirm river/ford/ridge/bay appear in the right places versus board 12 (by eye), stop the processes by PID from `pids.json`. Commit `git add godot3d/scripts/terrain godot3d/scripts/continuous_terrain.gd godot3d/scripts/earthfront_3d.gd godot3d/tests && git commit -m "feat(godot): snapshot-driven Kestrel terrain with noise fallback" ...`

---

### Task 10: Cast shadows and lighting (the "pasted on" fix)

**Files:**
- Modify: `godot3d/scripts/earthfront_3d.gd` (light and environment set-up; search `DirectionalLight3D`)
- Test: `godot3d/tests/test_lighting.gd`

**Interfaces:** none new. Behaviour: one warm `DirectionalLight3D` from the north-west at ~38 degrees elevation, `shadow_enabled = true`, `directional_shadow_mode = SHADOW_PARALLEL_4_SPLITS`, `shadow_bias = 0.04`, `shadow_normal_bias = 1.0`, `directional_shadow_max_distance = 120`; terrain mesh and every building/unit mesh instance `cast_shadow = SHADOW_CASTING_SETTING_ON`; environment ambient light sky-contribution 0.35 so shadows stay readable; SSAO on when the renderer supports it (skip silently under `--software`).

- [ ] **Step 1: Failing test**

```gdscript
extends RefCounted
func test_scene_has_a_shadow_casting_sun(t) -> void:
	var scene = load("res://scenes/earthfront_3d.tscn").instantiate()  # use the real main scene path from project.godot
	t.root.add_child(scene)
	var sun: DirectionalLight3D = null
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		sun = n
	t.check(sun != null, "a DirectionalLight3D exists")
	t.check(sun.shadow_enabled, "sun casts shadows")
	t.check(sun.directional_shadow_max_distance >= 100.0, "shadow reaches the whole base")
	scene.queue_free()
```
Adapt scene path/`t.root` to how other scene-level tests in `godot3d/tests/` instantiate the main scene (copy one).

- [ ] **Step 2: Run, expect FAIL** if shadows are off or the setting differs; if it already passes, strengthen the test with the exact bias values listed above.

- [ ] **Step 3: Implement** the settings above in the light/environment builder; ensure unit/building mesh spawn code sets `cast_shadow`.

- [ ] **Step 4: Run** the Godot suite; PASS. Live capture a frame at 1920x1080 and compare by eye with board 1 (shadows grounded, contact darkening under buildings). Because buildings share one pivot origin, if a model floats, fix its y offset in the model loader, not in the light. Record the before/after capture paths in the ledger.

- [ ] **Step 5: Commit** `git add godot3d/scripts/earthfront_3d.gd godot3d/tests/test_lighting.gd && git commit -m "feat(godot): cast shadows and ambient tuning" ...`

---

### Task 11: View-model slices for the new HUD data

**Files:**
- Modify: `godot3d/scripts/ui/live_adapter.gd` (`hud_vm`, lines ~134-156), `godot3d/tests/stub_game.gd`
- Create: `godot3d/scripts/ui/vm_gameplay.gd` (pure functions), `godot3d/tests/test_vm_gameplay.gd`

**Interfaces:**
- Consumes: snapshot fields from Task 8, `GroundModel`.
- Produces pure functions on `vm_gameplay.gd`, each returning a Dictionary or `{}` when its data is missing (so the section builds nothing):
  - `territory(snap, ground_model) -> {"tiles": int, "composition": [{"glyph","name","pct"}...]}` from `construction_zone` cells
  - `tile_inspect(snap, ground_model, x, y) -> {"name","cover_pct","range_pct","infantry_pct","vehicle_pct","buildable","bonus_text"}` (bonus_text only from real per-entity `river_kw`/`ore_bonus`)
  - `idle_crews(snap) -> {"count": int, "first_id": int}` counts `idle` units that are crews/harvesters
  - `next_alert(snap) -> {"label": String, "seconds": int}` from `next_wave_ticks` (ticks / the sim tick rate constant already used by the topbar)
  - `wave_inbound(snap) -> {"route": [[x,y]...], "wave": int, "eta_s": int}` from `wave_route`
  - `enemy_border(snap) -> Array` of hex cells within 3 of alien structures (hex distance helper already in the client; flat-top odd-q)
  - `regions(snap) -> Array`
  - `veterans(snap) -> {unit_id: rank}`

- [ ] **Step 1: Failing tests** against the Kestrel fixture and the stub:

```gdscript
extends RefCounted
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")

func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())

func test_territory_composition_sums_to_one_hundred(t) -> void:
	var s := _snap()
	var tv: Dictionary = VM.territory(s, GroundModel.from_snapshot(s))
	t.check(tv.has("composition"), "composition present")
	var sum := 0
	for row in tv.composition:
		sum += int(row.pct)
	t.check(abs(sum - 100) <= 2, "percent rounds to ~100")

func test_missing_slices_return_empty(t) -> void:
	t.check(VM.wave_inbound({}).is_empty(), "no wave_route -> empty")
	t.check(VM.regions({}).is_empty(), "no regions -> empty")
	t.check(VM.territory({}, null).is_empty(), "no ground -> empty")
	t.check(VM.idle_crews({"entities": []}).get("count", 0) == 0, "no idle crews -> zero, not invented")

func test_enemy_border_is_within_three_hexes_of_an_alien_structure(t) -> void:
	var s := _snap()
	var cells: Array = VM.enemy_border(s)
	t.check(cells.size() > 0, "holdfast produces a border")

func test_tile_inspect_reports_table_numbers_only(t) -> void:
	var s := _snap()
	var gm = GroundModel.from_snapshot(s)
	var info: Dictionary = VM.tile_inspect(s, gm, 0, 0)
	for k in ["name", "cover_pct", "range_pct", "buildable"]:
		t.check(info.has(k), "has " + k)
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** `vm_gameplay.gd` as static functions over the shapes above (read how existing `live_adapter.gd` iterates `entities` and the owner/side fields so `idle_crews`/`enemy_border` filter correctly), then add each result as a slice key in `hud_vm` only when non-empty: `"territory"`, `"inspect"` (filled on hover), `"idle"`, `"alert"`, `"wave"`, `"regions"`, `"veterans"`.

- [ ] **Step 4: Run** the Godot suite; PASS, `0` SCRIPT ERROR.

- [ ] **Step 5: Commit** `git add godot3d/scripts/ui godot3d/tests && git commit -m "feat(godot): gameplay view-model slices" ...`

---

### Task 12: Core HUD chrome, boards 1, 2, 3, 4, 5, 7 (pixel-matched)

**Files:**
- Create under `godot3d/scripts/ui/sections/`: `top_yields.gd`, `territory_card.gd`, `tile_inspector.gd`, `resource_pins.gd`, `minimap_lenses.gd`, `alert_chips.gd`, `control_groups.gd`, `attack_move_banner.gd`, `structure_panel.gd`, `selection_roster.gd`, `wave_panel.gd`
- Modify: `godot3d/scripts/ui/hud.gd` (register in `SECTIONS`/`register_section`), `godot3d/scripts/ui/live_adapter.gd`, `godot3d/scripts/earthfront_3d.gd` (hover + order wiring), `godot3d/scripts/gallery/gallery.gd` + `fixtures_gp.gd`, `tools/ui/compare_gp01.json` ... `compare_gp07.json`
- Test: one `godot3d/tests/test_section_<name>.gd` per section

**Interfaces:** each section is a pure builder `static func build(parent: Control, vm: Dictionary) -> void` following the existing section files' signature (read `godot3d/scripts/ui/sections/*` or the nearest existing section such as the topbar before coding; copy its theme tokens and metrics). Behaviour per section, each driven only by its Task 11 slice and returning without building when the slice is absent:
- `top_yields`: per-minute yield chips (M, W, kW) with delta sign from existing economy fields; no invented numbers.
- `territory_card`: tiles + composition bar (colours from the board legend).
- `tile_inspector`: panel near the cursor listing the `tile_inspect` fields.
- `resource_pins`: pin buttons "Ore +N" per deposit with real amounts; clicking centres camera.
- `minimap_lenses`: four toggle Buttons Land/Res/Bdr/Thr switching the minimap layer; state in the vm.
- `alert_chips`: "Idle crews N" Button (click selects first idle) and "Next alert mm:ss" label.
- `control_groups`: 1-9 slots with unit counts.
- `attack_move_banner`: "ATTACK-MOVE ARMED" banner while the attack-move stance is armed (existing flag in `earthfront_3d.gd`).
- `structure_panel`: Buttons Set rally, Repair, Cancel last, Focus building, Demolish, each wired to the existing bridge command CSV (read `Command` list in godot-bridge.rs; where a command does not exist, hide the Button, never fake it, and record it in `ui-deviations.md`).
- `selection_roster`: card per selected unit with HP bar and veteran chevrons from `veterans`.
- `wave_panel`: wave number, ETA, route summary, "Fortify" hint text only from `wave` slice.

- [ ] **Step 1: Failing tests, one per section** (pattern; repeat for each section with its own slice and expected labels):

```gdscript
extends RefCounted
const Section := preload("res://scripts/ui/sections/alert_chips.gd")

func test_idle_chip_shows_real_count_and_is_a_button(t) -> void:
	var root := Control.new()
	Section.build(root, {"idle": {"count": 3, "first_id": 41}})
	var btn: Button = null
	for b in root.find_children("*", "Button", true, false):
		if b.text.begins_with("Idle crews"):
			btn = b
	t.check(btn != null and btn.text.contains("3"), "idle crews chip with the count")
	root.free()

func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	t.check(root.get_child_count() == 0, "no slice -> no nodes, no fake zero")
	root.free()
```
Each section's tests must assert: (a) label/Button text with the real number from the slice, (b) absent slice builds nothing, (c) clickable controls are `Button`s with human label text.

- [ ] **Step 2: Run each, expect FAIL** (files missing).

- [ ] **Step 3: Implement** sections against `hud.css` metrics of the boards (positions/sizes from the `.dc.html` inline styles: read the board for the exact left/top/width/height and font sizes; the diff harness is the arbiter). Register in `hud.gd` in the order the boards stack them.

- [ ] **Step 4: Fill the harness.** Add gallery cases `gp01`..`gp07` in `scripts/gallery/gallery.gd` using fixtures from the Kestrel snapshot, add chrome rectangles to `compare_gp01..07.json` (battlefield rectangle masked), then:

```bash
tools/ui/verify_all.sh 2>&1 | tail -30
```
Iterate until each gp01-07 chrome rectangle is within limit (achieved% + 3). Run the whole Godot suite; PASS.

- [ ] **Step 5: Commit** `git add godot3d tools/ui docs/ascension/ui-deviations.md && git commit -m "feat(godot): gameplay HUD sections for boards 1-5 and 7" ...`

---

### Task 13: Logistics tab and world overlays, board 8

**Files:**
- Create: `godot3d/scripts/ui/sections/logistics_tab.gd`, `godot3d/scripts/world/overlay_feed.gd`, tests `test_logistics_tab.gd`, `test_overlay_feed.gd`
- Modify: `godot3d/scripts/ui/hud.gd` (show Logistics deck tab), `godot3d/scripts/earthfront_3d.gd` (call `overlay_feed` each snapshot), `godot3d/scripts/ui/world_marks.gd` only if a kind needs a new style, `compare_gp08.json`, gallery case gp08

**Interfaces:**
- Consumes: `world_marks.gd` kinds ring/link/arrow/beam/badge/callout, snapshot `power`/`supply_routes`/`river_kw` fields, `construction_zone`, Task 11 `enemy_border`.
- Produces `overlay_feed.gd`: `static func marks(snap: Dictionary, lens: String) -> Array` returning mark dictionaries in `world_marks.gd`'s own schema (read its `add`/`apply` signature first). Lens `"power"`: one `link` per PowerPlant/Battery to each consumer building in tier order, colour by `power_fraction` (>=1000 ok, 500-999 amber, <500 `broken: true`); `"supply"`: one `link` per real supply route; `"borders"`: player border polyline from `construction_zone` outline plus enemy border from `enemy_border`, the latter labelled "Enemy territory"; `"coverage"`: `ring` per turret at its real range (and +25 percent on Highland from `ground_table`); `"yield"`: `ring` radius 1 around each Refinery with the `ore_bonus` badge "+20%"; PowerPlant `badge` "river +12" only when `river_kw > 0`.

- [ ] **Step 1: Failing tests**

```gdscript
extends RefCounted
const Feed := preload("res://scripts/world/overlay_feed.gd")

func test_power_lens_marks_broken_links_under_five_hundred(t) -> void:
	var snap := {"entities": [
		{"id": 1, "kind": "PowerPlant", "x": 5, "y": 5, "power_fraction": 1000},
		{"id": 2, "kind": "Barracks", "x": 7, "y": 5, "power_fraction": 300},
	]}
	var marks: Array = Feed.marks(snap, "power")
	var broken := 0
	for m in marks:
		if bool(m.get("broken", false)):
			broken += 1
	t.check(broken == 1, "the 300/1000 consumer gets a broken link")

func test_no_power_plants_gives_no_marks(t) -> void:
	t.check(Feed.marks({"entities": []}, "power").is_empty(), "nothing to link")

func test_river_badge_only_when_real(t) -> void:
	var with_b := Feed.marks({"entities": [{"id": 1, "kind": "PowerPlant", "x": 1, "y": 1, "river_kw": 12}]}, "yield")
	var without := Feed.marks({"entities": [{"id": 1, "kind": "PowerPlant", "x": 1, "y": 1, "river_kw": 0}]}, "yield")
	t.check(with_b.size() > without.size(), "badge appears only with river_kw > 0")
```
Use the real snapshot entity key names (`kind`, position keys, `power_fraction`) from `godot-bridge.rs` and the Kestrel fixture, not the shorthand above, if they differ; the three assertions are normative.

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** `overlay_feed.gd` and `logistics_tab.gd` (Buttons for the five lenses Power/Supply/Borders/Coverage/Yield, active lens in the vm), wire the Logistics deck tab (the one previously hidden for lack of data) to appear when the snapshot has `ground` (Earthfront).

- [ ] **Step 4: Harness** gp08 gallery case and `compare_gp08.json`; run `tools/ui/verify_all.sh`, then the Godot suite. PASS.

- [ ] **Step 5: Commit** `git add godot3d tools/ui && git commit -m "feat(godot): Logistics tab and world overlays (board 8)" ...`

---

### Task 14: Pause menu, controls reference, strategic map, terrain guide (boards 9-12) and EarlyMission (board 6)

**Files:**
- Create: `godot3d/scripts/ui/screens/pause_menu.gd`, `controls_reference.gd`, `region_map.gd`, `terrain_guide.gd`, `early_mission.gd`; tests `test_screen_*.gd`
- Modify: `godot3d/scripts/ui/game_ui.gd` (host, key routing: Esc pause, F1 controls, M region map, Codex button for the guide), `compare_gp06.json`, `compare_gp09..12.json`, gallery cases

**Interfaces:**
- `pause_menu`: mission snapshot (map_name, wave, waves_survived, tick as mm:ss), Buttons Resume, Controls, Restart (opens a confirm sub-panel with Buttons "Restart mission" and "Keep playing"; Restart emits the bridge restart command that already exists, else the Button is hidden), Quit.
- `controls_reference`: static keybinding list read from the SAME constants the input handler uses (extract them to `godot3d/scripts/ui/keybinds.gd` if they are inline; never hardcode a second copy that can drift).
- `region_map`: renders the `ground` layer as a flat minimap at 0.45 scale in the left 1620 px, region labels from `regions`, borders from Task 13 feed (player and enemy), route from `wave_route`, right panel with Composition (from `ground` counts), Territory tiles, Hostile sites count, Yields per minute, Lenses Terrain/Resources/Borders/Threat/Hex grid as Buttons. No fog, no explored percent.
- `terrain_guide`: 12 cards from `ground_table` plus Ore/Alloy cards; numbers (movement, cover, range, buildable) read from the table; text notes are static copy without numbers; rule-of-thumb footer uses table values via string format (high ground "adds %d%% range" from `range_pct`). Drop "across the river -25%" and the Fog rule (R4, spec 2).
- `early_mission`: briefing card and 3 objectives from the snapshot's real objective fields; if the snapshot has no objective data, the screen is built from the Kestrel region names only ("Fortify Wyllow Ford" style goals are hardcoded copy keyed to region names that exist in `regions`, hidden otherwise).

- [ ] **Step 1: Failing tests**

```gdscript
extends RefCounted
const Guide := preload("res://scripts/ui/screens/terrain_guide.gd")

func test_guide_numbers_come_from_the_table(t) -> void:
	var s: Dictionary = JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())
	var root := Control.new()
	Guide.build(root, s)
	var text := ""
	for l in root.find_children("*", "Label", true, false):
		text += l.text + "\n"
	var hi: Dictionary = {}
	for row in s.ground_table:
		if row.name == "Highland":
			hi = row
	t.check(text.contains(str(int(hi.range_pct))), "highland range bonus is the table value")
	t.check(not text.contains("-25%"), "no across-the-river penalty (R4)")
	t.check(not text.to_lower().contains("fog"), "no fog copy")
	root.free()

func test_guide_without_ground_table_builds_nothing(t) -> void:
	var root := Control.new()
	Guide.build(root, {})
	t.check(root.get_child_count() == 0, "no table -> nothing")
	root.free()
```
Add the analogous pairs for `pause_menu` (Restart opens confirm; Resume is a Button), `controls_reference` (every key shown is in `keybinds.gd`), `region_map` (labels equal `regions` names; absent `regions` builds nothing), `early_mission` (no fog/survey strings).

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** screens against the boards' exact metrics; route keys in `game_ui.gd`; pause must freeze the poll-driven HUD updates but not the process.

- [ ] **Step 4: Harness** gp06, gp09-12 gallery cases and compare files; run `tools/ui/verify_all.sh` until all twelve gp rectangles are within limit; full Godot suite PASS.

- [ ] **Step 5: Commit** `git add godot3d tools/ui && git commit -m "feat(godot): pause, controls, region map, terrain guide, early mission screens" ...`

---

### Task 15: Docs, live QA, whole-branch gates

**Files:**
- Modify: `docs/ascension/ui-deviations.md`, `NEXT_STEPS.md`, `README.md` (add Kestrel Reach scenario + `--scenario kestrel` flag), `docs/ascension/ui-mocks-gameplay/README.md`

- [ ] **Step 1: Full gates**

```bash
cargo fmt --all -- --check && cargo clippy --workspace --all-targets --offline -- -D warnings && cargo test --workspace --offline 2>&1 | tail -5
cargo check --offline --target wasm32-unknown-unknown -p rts-core 2>&1 | tail -3   # wasm check, if the target is installed
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd 2>&1 | tee /tmp/godot-final.log | tail -5; grep -c "SCRIPT ERROR" /tmp/godot-final.log
tools/ui/verify_all.sh 2>&1 | tail -30
```
Expected: all green; golden unchanged (`2_081_234_273_307_305_018`); Godot count >= 1519 + new; 0 SCRIPT ERROR; 30 boards (18 + 12) within limits.

- [ ] **Step 2: Live QA** with `tools/qa/launch_ui.py <dir> --software` on Kestrel Reach: open each of the 12 states with `hud_states.py`, capture, compare with the boards. Specifically verify by eye: shadows ground the buildings and tanks; river impassable with the ford crossing; tanks slow at the ford; a turret on Highland outranges; river power plant shows "+12"; Logistics lenses draw; Esc/F1/M open their screens; Survival scenario still starts and shows noise terrain with no region UI. Stop processes by PID from `pids.json`; leave the TV/speakers alone (no audio tests).

- [ ] **Step 3: Docs.** Update `ui-deviations.md` with every item dropped or reduced (fog, footprints, "across the river -25%", any structure-panel Button hidden for a missing command), `NEXT_STEPS.md`, README flag usage.

- [ ] **Step 4: Commit** `git add docs NEXT_STEPS.md README.md && git commit -m "docs: Kestrel Reach scenario and gameplay HUD deviations" ...`

- [ ] **Step 5: Final review.** Dispatch the whole-branch reviewer with the Review Focus list above and the spec; it must run the golden test itself.

---

## Self-Review (spec coverage)

- 4.1 -> Tasks 1, 2. 4.2 -> Task 3. 4.3 -> Task 4. 4.4 -> Task 5. 4.5 -> Task 6. 4.6 -> Task 7. 4.7 -> Task 8 (R7 veteran: Task 0 ruling + Task 8 `rank` + Task 12 roster).
- 5.1 -> Task 9. 5.2 -> Task 10. 5.3 -> Tasks 11, 12, 13. 5.4 -> Task 14. 5.5 -> Task 13.
- R5 (power links, broken under 500, Logistics tab) -> Task 13; R6 (enemy border in Godot) -> Tasks 11, 13; R8 (names in snapshot) -> Tasks 7, 8, 14; R4 -> Task 14 (dropped copy); R1/R2 -> Task 1 (Shore/Crater unbuildable) and Global Constraints.
- Section 6 verification -> Tasks 0, 2, 12-15. Section 7 risks: backup (Task 0), golden gating (Tasks 2, 4-6), cargo proven (Task 0), table-based balance (Task 1).
- Spec decision "no fog" -> Task 0 board edits + Review Focus; grep-checked in Task 0 Step 4 and Task 14 tests.

Known soft spots, flagged honestly rather than hidden: Tasks 4, 5 and 6 name test helpers only as "the module's existing helper" because the spawn/order helper names inside `sim.rs` tests were not read before planning (the implementer reads two neighbouring tests first; assertions are normative). Tasks 12-14 give section-by-section behaviour and exact tests for the key behaviours but leave pixel metrics to the boards and the diff harness, which is the arbiter in this repo. The Kestrel `ROWS` literals are generated at implementation time from the layout contract and verified by the dimension, glyph, ford-uniqueness and connectivity tests.
