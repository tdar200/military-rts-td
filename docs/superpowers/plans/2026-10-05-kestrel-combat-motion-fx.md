# Kestrel Combat and Motion Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Kestrel, units animate while they move, firing shows muzzle flashes and tracers from the real shooter to the real target, and hits, deaths and building collapses are layered fire, smoke and spark effects instead of single coloured spheres.

**Architecture:** The sim already records the shots of each combat tick (`Sim::recent_attacks`, positions only, unhashed), but `godot-bridge` never sends them and the client polls at 8 Hz against a 30 Hz sim. Task 1 adds a rolling window of recent shots to the bridge snapshot (additive key, Kestrel only, `crates/core` untouched). Tasks 2-4 are Godot client work behind `world_art_on`: an effect atlas plus pooled effect cards, shot-driven firing effects, and procedural movement animation of the sprite cards. Survival stays byte-identical.

**Tech Stack:** Rust (godot-bridge only), Godot 4.7.2 Compatibility renderer (GDScript), PIL for a deterministic committed effect atlas script (same pattern as `tools/ui/build_prop_atlas.py`).

**Spec:** the chat design of 2026-10-05 (user answers: "what about animations for any movement and the explosions are just blobs as well when firing"; firing source = "Add target to the snapshot"). Branch `gameplay-hud-kestrel-reach`, builds on `docs/superpowers/plans/2026-10-05-kestrel-sprite-entities.md`.

## Global Constraints

- Rust: the ONLY crates change allowed is `crates/server/src/bin/godot-bridge.rs`. `git diff --stat d81deab..HEAD -- crates/` may list that one file and nothing else (core, data, render-shell untouched). `golden_hash_pins_cross_target_determinism` must not move. The Survival snapshot must keep its exact shape (no `shots` key).
- Kestrel only: every Godot change gated on `world_art_on`; Survival SHA tests in `godot3d/tests/test_world_art_survival.gd` never weakened; Survival keeps `_fire`, `_tracer`, `_impact_effect`, `_death_effect` as they are.
- Perf: at most +120 draw calls and +150k primitives vs `tools/ui/world_baseline.json` `_perf` in the idle home and max frames (current software: home 25 dc / 156,776 prim, max about 78-132 dc / 214k). Effects must be pooled (cap live effect cards, for example 64) and share materials per effect type; per-instance duplicated materials are not allowed for effects. A big firefight (30 shots in one second) must stay within 10 ms p50 on the GPU baseline method.
- Never open windows on the user's display, move the real cursor, or play audio through the speakers during QA: software capture on private Xvfb (`world_capture.py --software`, display :94). Never run `world_capture.py --help`.
- Commit trailer exactly `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Stage only a task's own paths. No em or en dashes anywhere.
- Gates after every task: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, `cargo test --workspace --offline`, Godot suite `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd` (0 SCRIPT ERROR, 0 SHADER ERROR, 0 ERROR lines, ObjectDB leak line stays 141), `cd tools/ui && python3 -m unittest test_world_diff test_build_prop_atlas test_build_building_variants -v` (plus any new test module), `bash tools/ui/verify_all.sh` exit 0. TDD: show the failing test first.
- The idle scoreboard (`world_diff.py run` vs `$SCRATCH/world/tff_scores.json`) must not drop any board by more than 2.0: effects only appear during combat, so idle frames should not change.
  `SCRATCH=/tmp/claude-1000/-home-tahseen-dar-Projects/6192d82f-7996-46e2-a728-f193248e89d9/scratchpad`

## Review Focus

- Shots are cosmetic: a missed or duplicated shot must never change gameplay state, selection or HUD; the client dedups by (tick, attacker position, target position) and never draws the same shot twice across polls.
- Paused game and scenario restart: no shots replayed after resume or restart; the bridge window resets with the sim.
- A shot whose attacker or target entity has already left the snapshot (killed this tick) still draws from and to its position, with no null access.
- An attacker out of the camera view or under hidden fog draws nothing expensive (cull by distance to the camera focus), and the pool cap drops the oldest effect, never errors.
- Destroyed building: the finished sprite must not linger under the collapse effect, and an alien and a human kind use their own colours.

---

### Task 1: Bridge shots window (Rust)

**Files:**
- Modify: `crates/server/src/bin/godot-bridge.rs`

**Interfaces:**
- Consumes: `Sim::recent_attacks() -> &[(Vec2, Vec2)]`, `Sim::tick()`, the snapshot writer `snapshot_json_with(sim, supply_links)`, the main loop that calls `sim.step(&commands)` once per 1/30 s.
- Produces: an additive snapshot key `"shots":[[tick,ax_bits,az_bits,tx_bits,tz_bits],...]` (positions as `Fixed::to_bits()` like `x_bits`/`z_bits`), holding the shots of the last 18 ticks (0.6 s), oldest first, emitted ONLY when the scenario has a ground layer (Kestrel), appended after the existing keys. A small `ShotWindow` struct (push per tick, prune, clear on scenario restart).

- [ ] **Step 1: Failing tests** in the bridge test module: (a) after stepping a Kestrel sim into combat (two armed units of opposing owners in range, the way `combat_destroys_an_enemy_structure`-style fixtures do) the snapshot contains a `shots` array whose entries have the tick and four integers and the attacker/target bits match the two units; (b) shots older than 18 ticks are pruned; (c) the Survival snapshot has no `shots` key and is byte-identical to before (reuse `survival_snapshot_is_unchanged_in_shape_and_has_all_grass_ground`); (d) the window clears when the scenario restarts; (e) the snapshot stays valid JSON (reuse `kestrel_snapshot_is_valid_json_shape`).
- [ ] **Step 2: Implement** `ShotWindow`, push `sim.recent_attacks()` after every `sim.step` in the main loop (not while paused, not before the mission starts), prune to `tick - 18`, clear on restart, thread it into the snapshot writer, emit the key only for a ground-layer scenario.
- [ ] **Step 3: Gates.** Run `cargo test --workspace --offline` and confirm `golden_hash_pins_cross_target_determinism` passes untouched, `git diff --stat d81deab..HEAD -- crates/` lists only `crates/server/src/bin/godot-bridge.rs`, and the Godot suite and `verify_all.sh` still pass (the new key must not break the client parser).
- [ ] **Step 4: Commit** (one commit), append to the task report.

---

### Task 2: Effect atlas, pooled effect cards, hit, death and collapse effects

**Files:**
- Create: `tools/ui/build_fx_atlas.py`, `tools/ui/test_build_fx_atlas.py`, `godot3d/assets/world/fx/fx_atlas.png` (+ `.import`), `godot3d/scripts/world/world_fx.gd`, `godot3d/tests/test_world_fx.gd`
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_impact_effect`, `_death_effect` call sites on the Kestrel path, building destruction), `godot3d/tests/run_tests.gd` registration if tests are listed there, `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: the sprite entities' node contract (`visual_tiles`, `crown_y`), `WorldSprites` (kind sizes), `world_art_on`, the existing `_impact_effect(position, human_hit)` and `_death_effect(position, owner)` call sites (bridge diff, lines near 2608 and 2688).
- Produces: `WorldFx` with `flash(pos, weight, owner)`, `hit(pos, weight, owner)`, `explode(pos, size, owner)`, `collapse(pos, tiles, owner)` and `pool_count() -> int` (live effect cards, capped at 64, oldest recycled). `weight` is 0 (infantry), 1 (anti-armour, gun), 2 (tank), 3 (gunship, capital, buildings). A deterministic atlas script writes flipbook frames: muzzle flash, fireball (8 frames), smoke puff (8 frames), sparks, debris, ember and a burning-rubble decal; amber/orange for humans, teal/magenta plasma for aliens (two atlas rows).

- [ ] **Step 1: Failing tests** for the atlas script (deterministic: two runs identical; the committed PNG matches the script output within the same tolerance as `test_committed_sprites_are_the_script_output`; alpha present; frame grid size) and for `WorldFx` (a hit spawns at most the documented number of cards; pool cap holds under 200 spawns and the oldest is recycled; effects free themselves after their duration; materials are shared, no per-card duplicate material; headless-safe).
- [ ] **Step 2: Implement** the atlas script (noise-based, no randomness without a fixed seed) and `world_fx.gd`: billboard flipbook cards (additive for fire and flash, alpha for smoke), one shared material per effect type, no shadow casting, camera-facing for the orthographic Kestrel camera, ground-contact smoke that drifts up and fades. Replace the sphere flash and shard ring on the Kestrel path only: a hit = flash + small fireball + sparks scaled by weight, unit death = fireball + smoke plume + debris, building death = staged collapse (dust ring, rolling fireball, smoke column, burning-rubble decal fading over about 6 s) while the finished sprite is removed immediately. Camera shake and the human-hit tone stay as they are.
- [ ] **Step 3: Gates, capture and score** (an idle scoreboard must not move; take one in-combat software capture to a scratch path and open it to check the effects read as fire and smoke, not blobs).
- [ ] **Step 4: Commit** incrementally (atlas, WorldFx, wiring), append to the task report.

---

### Task 3: Firing effects from the shots window

**Files:**
- Modify: `godot3d/scripts/earthfront_3d.gd` (snapshot ingestion, a shot dispatcher), `godot3d/scripts/world/world_fx.gd`, `godot3d/scripts/world/world_sprites.gd` (recoil hook), `godot3d/tests/test_world_fx.gd`, `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: Task 1's `shots` key (tick, attacker bits, target bits) and Task 2's `WorldFx`; the bridge entity table `bridge_nodes` and `bridge_frame_entities` for kind lookup by nearest position.
- Produces: `WorldFx.shot(from, to, attacker_kind, owner)` drawing a muzzle flash at the attacker, a tracer or projectile to the target (short bright streak for infantry and gun turrets, slow glowing shell for tanks and anti-armour, beam streak for aliens) and an impact flash at the target; a card recoil (small backward kick over about 0.1 s) on the attacker; a client dedup set keyed by (tick, attacker bits, target bits) pruned to the 18-tick window; resolved attacker kind = nearest entity to the attacker position within 0.6 tiles (unknown kind falls back to the infantry look).

- [ ] **Step 1: Failing tests:** the dispatcher draws each (tick, attacker, target) exactly once across three consecutive polls carrying overlapping windows; a shot with no matching entity still draws; a snapshot without `shots` (Survival, or an old bridge) draws nothing and raises no error; at most N shots per frame are drawn (cap, for example 24) with the rest dropped; the recoil restores the card position.
- [ ] **Step 2: Implement** the dispatcher in the snapshot sync, gated on `world_art_on`; keep `_impact_effect` hit-on-HP-drop but suppress its duplicate flash when a shot already drew an impact at that target within 0.2 s.
- [ ] **Step 3: Gates, capture and score**, plus an in-combat capture that shows a tracer between two real units.
- [ ] **Step 4: Commit**, append to the report.

---

### Task 4: Movement animation

**Files:**
- Modify: `godot3d/scripts/world/world_sprites.gd`, `godot3d/scripts/earthfront_3d.gd` (`_glide_bridge_nodes`, `_bob_units`, dust), `godot3d/scripts/world/world_fx.gd`, `godot3d/tests/test_world_sprites.gd`, `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: the unit cards (`UnitVisual`, `lift_at`, `base_y`, `hover`, `face()`), `glide_to` motion, `current_speed` where present, `WorldFx` smoke.
- Produces: `WorldSprites.animate(card, kind, speed, t)` applying only to cards that are moving: infantry stride bob and slight lean, anti-armour and tank rumble plus a start/stop lurch, harvester heavy sway, gunship forward tilt and a rotor-wash dust ring while low, plus tread-dust trails for tanks via `WorldFx`. A stationary unit returns exactly to rest (card transform equals its rest transform within 1e-5), a moving unit's animation never changes `pick_parts` or the selection ellipse, and animation must not touch Survival models.

- [ ] **Step 1: Failing tests:** moving vs stationary transform for each unit kind 0-5; the rest transform is restored after stopping; animation off when the unit is idle; pick box unchanged while animating; Survival unit transforms byte-identical (existing SHA tests).
- [ ] **Step 2: Implement** with card rotation and non-uniform scale about the base (the bottom edge stays on the ground), amplitude small and kind-specific constants in one table; no per-unit materials; frame cost measured (animating 60 units under 0.5 ms CPU).
- [ ] **Step 3: Gates, capture and score** (idle boards must not move by more than 2.0), software perf budgets, Survival pair at least 97 (note: capture timing swings it, judge the difference against a same-tick run if borderline).
- [ ] **Step 4: Commit**, append to the report.

---

### Task 5: Docs and regression gate

**Files:** `docs/ascension/ui-deviations.md`, `docs/ascension/ui-mocks-gameplay/README.md` (one sentence), `docs/ascension/perf-2026-10-05.md` (effects cost), `tools/ui/world_scores.json` only if a board moved (refresh with `--write`).

- [ ] **Step 1:** record the effect set, the shots window (key, 18-tick window, Kestrel only), movement animation, accepted limits, and the perf numbers; verify `grep -nP "\x{2013}|\x{2014}"` on touched docs prints nothing.
- [ ] **Step 2:** full gates, scoreboard vs `tff_scores.json`, software perf, GPU idle perf with a staged firefight if the display allows (otherwise state it as unverified), Survival pair, final `git diff --stat d81deab..HEAD -- crates/` (godot-bridge.rs only), golden hash passing.
- [ ] **Step 3: Commit**, report every number.
