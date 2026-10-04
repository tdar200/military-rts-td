# Gameplay HUD and the Kestrel Reach map: design

Status: DRAFT for review, 2026-10-04. Nothing in this spec is implemented.
Designs: `docs/ascension/ui-mocks-gameplay/` (12 boards; canvas https://claude.ai/artifact/5CjjisvQHfZf8CatMDu8Am).
Builds on: `2026-10-04-godot-ui-design-implementation-design.md` (the 18-board UI rebuild, installed, uncommitted).

## 1. Goal

Make the 12 gameplay boards real: the player sees and plays on a fixed map (Kestrel Reach: river, ford, coast, plains,
ridge, forest, ore, alloy), the sim enforces the terrain rules the boards show, and the Godot HUD matches the boards at
1920x1080. Chrome is pixel-matched as before; the battlefield stays 3D (the boards' painted sprites are a stand-in).

## 2. Decisions already made (by the user)

- Scope: chrome AND sim mechanics, so every number on a board is real or the block is dropped.
- Fog of war: skipped. `NEXT_STEPS.md` and the README keep "no per-player visibility system". Fog shroud, explored
  percent, discovery toasts and the terrain-survey card are dropped from boards 1, 6 and 11 before implementation.
- Map: a new fixed Kestrel Reach scenario with real per-tile terrain. Other scenarios keep procgen.

## 3. Rulings made while writing this spec (reversible, flagged)

R1. Grid stays 44x26 flat-top odd-q hex. The boards' square 48 px tile grid and 4x3 building footprints become single hex
    tiles; the placement panel says "1 hex". Cost if wrong: footprints are a sim rewrite, so this is the line I hold.
R2. Buildings stay single-tile. "Shore sand cannot be built on" becomes `buildable = false` on Shore tiles.
R3. Movement speed multipliers are per (ground, unit class); path cost is per ground only. This keeps A* admissible and
    deterministic.
R4. The boards' "attack across the river -25%" line is dropped from the terrain guide (needs line-of-sight work).
R5. Power lines on board 8 are drawn as links from each PowerPlant or Battery to its consumers by priority tier, with
    load = the real `power_fraction`; a building under 500/1000 draws a broken link. No new cable mechanic. Supply routes
    use the real `supply_route`. The Logistics tab is shown (it was hidden before because no data existed).
R6. Enemy territory border = union of hexes within 3 of known alien structures, computed in Godot and labelled
    "Enemy territory". Player border = the real `construction_zone`.
R7. Veteran chevrons and the combat preview are built only if the sim already tracks the inputs (rank, damage, armour).
    If it does not, they are dropped and listed in `ui-deviations.md` section 4. Decided in plan Task 0 by reading sim.rs.
R8. Place names (Kestrel Reach, Calder River, Wyllow Ford, The Dry Flats, Ironback Ridge, Hollow Wood, Kestrel Bay,
    Sunfield) live in scenario data and ride the snapshot, so Godot never hardcodes them.

## 4. Sim changes (crates/core, crates/server; Earthfront only, golden-neutral)

All new behaviour is gated on `self.earthfront` or defaults to a no-op, so the legacy golden hash
`2_081_234_273_307_305_018` must NOT move. Any change that moves it is a bug, not a re-pin. Integer and `Fixed` maths
only; no floats in core; ascending index order; no HashMap.

4.1 Ground layer. New `Ground` enum in `game/map.rs`: Grass, Meadow, Flats, Highland, Forest, River, Ford, Shore, Sea,
Crater. Stored as a `Vec<Ground>` beside `terrain` with `ground_at` / `set_ground`. A constant table gives, per ground:
path cost, speed multiplier for infantry and for vehicles, cover (incoming damage percent), range bonus (percent),
buildable, passable. The existing `TerrainKind` yield layer is untouched. The ground layer is hashed (appended to
`state_hash`, Earthfront section) because it changes behaviour.

4.2 Pathing. `find_path` uses per-tile `path_cost` for `g` and `hex_dist * min_cost` for the heuristic. River and Sea are
impassable; Ford is passable at a higher cost. Tie-breaking stays `(f_score, tile_index)`. `supply_route` and procgen
connectivity checks follow.

4.3 Movement. `run_movement` multiplies speed by the (ground, class) factor of the tile the unit stands on.

4.4 Combat. `run_combat` applies cover to damage taken by the target's tile and the range bonus to the attacker's tile
(Highland +25 percent range, via integer ratio on `range_sq`). Both read the ground table; nothing else changes.

4.5 Power and ore adjacency. `generation_for` adds +12 kW to a PowerPlant with a River or Ford neighbour. A Refinery with
a deposit within 1 hex yields +20 percent ore. Both are exposed per entity so the HUD can show "river +12" truthfully.

4.6 Kestrel Reach scenario. `scenario::kestrel_reach(seed)` hand-authors the 44x26 grid from a compact text map, sets
passable/buildable from the ground table, places the home Command Centre, ore on both banks, alloy on the ridge, the alien
holdfast on the east flats, and reuses the survival wave, relay and Earthfront rules. New `Scenario::KestrelReach`, excluded
from `Scenario::ALL` like Survival. Replay, connectivity and decisive-outcome tests are extended to it.

4.7 Bridge (`godot-bridge.rs`). Additive fields, schema stays 5 (Godot rejects other values; nothing existing changes
meaning): `map_name`, `regions` (name, hex bounds), `ground` (one char per tile), `ground_table` (all constants from 4.1,
so Godot hardcodes none), per-service `bonus` (river / ore), per-entity `idle`, `wave_route` (spawn to target hexes) and, if
R7 allows, per-unit `veteran` and a `unit_stats` table. The bridge gets a flag to pick the scenario; Survival stays the
default. The snapshot-shape test is extended.

## 5. Godot changes (godot3d/)

5.1 Terrain. `continuous_terrain.gd` is driven by the snapshot `ground` layer: height and vertex colour per ground class,
the river carved along River/Ford hexes, the coast from Sea hexes, textures from the game's own painterly set and v4
ground detail. The cosmetic noise terrain is the fallback when no `ground` field is present (other scenarios).

5.2 Cast shadows. Directional light and shadow settings tuned so buildings and tanks sit on the ground (the user's main
complaint about the mocks). Verified by live capture, not by the diff harness.

5.3 HUD sections (view-model slices, `live_adapter.gd`, `hud.gd`), each a pure screen with a test:
top bar yields with per-minute deltas, research and era chips, territory card (composition counted from `ground` inside
`construction_zone`), tile-under-cursor inspector, resource pins, minimap lenses (Land, Res, Bdr, Thr), idle-crews and
next-alert chips, control-group panel, ATTACK-MOVE ARMED banner, rally path and flag, structure panel (Set rally, Repair,
Cancel last, Focus building, Demolish), selection roster with HP bars, wave-inbound panel with approach arrows and turret
fields of fire, and the Logistics deck tab with the board-8 overlays.

5.4 New screens: pause menu with the mission snapshot and restart confirmation, controls reference (F1), strategic region
map (M), terrain guide (Codex). Region map and guide read `regions` and `ground_table`.

5.5 World marks. `world_marks.gd` already supports ring, link, arrow, beam, badge and callout kinds that nothing feeds live.
The new world overlays (borders, power lines, supply routes, coverage and yield circles) reuse it.

## 6. Verification

- Rust: `cargo test --workspace`, strict clippy, `cargo fmt --check`, wasm check, golden hash unchanged, plus new tests per
  4.1 to 4.6 and a Kestrel Reach full-match replay.
- Godot: `run_tests.gd` (1519 pass today, must stay green, grep for SCRIPT ERROR), one test file per new section.
- Pixel diff: boards 1 to 12 added to `tools/ui/` (`screens.json`, `compare_*.json`, gallery cases). Battlefield rectangles
  are masked as before; chrome limits are achieved percent plus 3.
- Live: `launch_ui.py` against Kestrel Reach, `hud_states.py` captures, compared by eye with the boards for the shadow and
  ground goal.

## 7. Risks

- The working tree has 83 modified Rust files that are not mine. A tarball backup precedes any edit (plan Task 0).
- `sim.rs` is 9,115 lines; pathing and combat edits are the deterministic-hash risk. Golden-neutral gating is the mitigation
  and the first thing the Rust reviewer checks.
- Cargo works offline from the registry cache but has not been run in this session; plan Task 0 proves it before relying
  on it.
- Rust changes add real game balance effects (cover, high ground, ford slow). The numbers are the boards' proposals and
  live in one table so they are easy to retune.

## 8. Out of scope

Fog of war, footprints and rotation, new unit or building types, multiplayer, audio, the legacy Rust shell UI.
