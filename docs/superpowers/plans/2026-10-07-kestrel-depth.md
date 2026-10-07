# Kestrel Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Kestrel Reach into a complete, replayable 15 to 25 minute RTS match: Kestrel first with a map picker and settings, audible feedback for every important event, units that defend themselves, spread out and take Stop/Hold/stance/target orders, walls that delay instead of win, a real late game with difficulty, score and a seeded roguelite run with verifiable replays, and an exportable build.

**Architecture:** Seven phases (P0 to P6) on branch `kestrel-depth` (cut from `kestrel-next-level` @ 67e6355). P0, P1, P5 and P6 are Godot client, bridge and tooling work. P2 to P4 add gameplay to the deterministic Rust core behind a new `depth` flag that only `kestrel_reach` sets, so every new behaviour checks `self.earthfront && self.depth` and Survival, the legacy maps and the golden hash stay byte-identical. New core code lives in `crates/core/src/game/depth.rs`, an `impl Sim` module declared from `sim.rs` with `#[path]` exactly like `earthfront.rs`; its per-entity and global state is hashed only when `depth` is on.

**Tech Stack:** Rust (core sim, `godot-bridge`, new `verify-run` bin), Godot 4.7.2 Compatibility (GDScript), Python 3 (numpy generator and tool tests), GitHub Actions YAML (validated locally only).

**Spec:** `docs/superpowers/specs/2026-10-07-kestrel-depth-design.md` (approved by the user 2026-10-07 with all nine open-decision defaults: "go"). Predecessor plan: `docs/superpowers/plans/2026-10-06-kestrel-next-level.md`.

## Global Constraints

Copied from the spec's Constraints section (verbatim values), then the tooling rules this repo's plans have always carried.

- `crates/core` and `crates/data` rule, relaxed deliberately and narrowly: only P2, P3 and P4 may touch them, only the files listed per phase, and every new behaviour sits behind `self.earthfront && self.depth` (or the P4 `run` flag on top). P0, P1, P5 and P6 touch no file under `crates/core` or `crates/data`. Check `git diff --stat 67e6355..HEAD -- crates/` at every phase end against the phase's list.
- Allowed `crates/` paths per phase (cumulative), the list the phase-end check compares against:
  - P0, P1: `crates/server/src/bin/godot-bridge.rs` only.
  - P2: plus `crates/core/src/game/sim.rs`, `crates/core/src/game/depth.rs` (new), `crates/core/src/game/path.rs`, `crates/core/src/game/earthfront.rs`, `crates/core/src/game/scenario.rs`, and `crates/core/src/game/civ/mod.rs` (deviation D1 below: one match arm only).
  - P3: the same core files as P2 (no new ones). `crates/data` stays untouched (depth tuning lives as consts in `depth.rs`).
  - P4: plus `crates/core/src/game/perk.rs`, `crates/server/src/bridge_protocol.rs` (new), `crates/server/src/lib.rs` (new, deviation D2), `crates/server/src/bin/verify-run.rs` (new).
  - P5: plus `crates/server/Cargo.toml` (version only, deviation D4). P6: nothing new.
- Golden hash `2_081_234_273_307_305_018` never changes (`golden_hash_pins_cross_target_determinism`, `crates/core/src/game/sim.rs:6683`, value at `:6732`). Survival and legacy maps stay byte-identical (their Rust determinism and playtest tests untouched); Survival does not get the combat changes (open decision 6). The bridge test `survival_snapshots_are_byte_identical_to_the_pre_fog_bridge` (`godot-bridge.rs:2711`) is never edited.
- Gates per task (and in full at each phase end): `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, `cargo test --workspace --offline` (the golden test inside it unchanged), Godot headless suite `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --audio-driver Dummy --path godot3d --script res://tests/run_tests.gd` (0 SCRIPT ERROR, 0 SHADER ERROR, 0 ERROR lines, leak line stays "141 ObjectDB instances were leaked" unless the task explains a deliberate change), `cd tools/ui && python3 -m unittest test_world_diff test_build_prop_atlas test_build_building_variants test_build_fx_atlas -v`, `cd tools/audio && python3 -m unittest test_build_sfx test_quiet_launchers -v` (plus any new module a task adds), `bash tools/ui/verify_all.sh` exit 0 with no limits loosened. TDD: show the failing test first in the task report.
- Idle scoreboard: fog-off software captures (`EARTHFRONT_FOG=0 python3 tools/qa/world_capture.py $SCRATCH/world/kdN --scenario kestrel --display :94`) scored with `python3 tools/ui/world_diff.py run --mocks <mock dir> --live $SCRATCH/world/kdN --out $SCRATCH/world/kdN_out --check tools/ui/world_scores.json` (the reference re-baselined from `t10k2` at the end of the previous program). No board drops more than 2.0 except where a phase intends it: P0 title, P1 damage states, P2 stance chip; an intended change is shown before/after and only then re-baselined with `--write tools/ui/world_scores.json`. Survival pair at least 97 against `$SCRATCH/world/surv/survival_home.png` (capture with `--scenario survival --only home`; timing swings it 97 to 99.8, judge borderline cases against a same-tick run). `SCRATCH=/tmp/claude-1000/-home-tahseen-dar-Projects/6192d82f-7996-46e2-a728-f193248e89d9/scratchpad`.
- Perf: at most +120 draw calls and +150k primitives vs `tools/ui/world_baseline.json`; separation and acquisition must keep a 30 Hz tick under budget in the bridge (measure ms per tick with 80 units; Task 12 owns the measurement).
- QA never plays real audio, opens windows on the user's display or moves the cursor: `--headless` or `--audio-driver Dummy`, private Xvfb only (`world_capture.py` / `launch_ui.py --software --display :94`, never `--gpu` without `--allow-user-display`, never `--help`). Nothing under `tools/audio/listen_pass.py` or `tools/perf/gpu_frametime.sh` is ever executed by an agent except their refusal and dry-run tests.
- Godot tests that touch `user://` files use their own temporary paths (`user://test_<name>/...`) and delete them; no test writes `user://settings.cfg`, `user://records.cfg` or `user://replays/` for real. Nothing is ever written under `res://` except `res://runtime` by the dev bridge.
- No pushing, merging or remote creation without the user (there is no remote; creating one is the user's decision).
- Commit trailer exactly `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` on every commit (re-check after each subagent task; subagents may stamp another model name from a harness notice and the controller rewrites it); no em or en dashes anywhere (grep `\x{2013}|\x{2014}` on added lines; GDScript strings that need a dash use the existing `\u2014` escape convention only where the file already does); stage only a task's own paths, never `git add -A`, never `__pycache__`.
- Kestrel outcome test (`kestrel_reach_overruns_an_undefended_base_and_holds_with_the_playtest_defence`, `scenario.rs:2163`) keeps its invariants (undefended falls; defended never overrun before wave 3 or wins). Every core task that moves it records old and new ticks in the test's doc comment (above `KESTREL_DEFENDED_WAVES`, `scenario.rs:2148-2160`), in the commit message and in the task report. Starting numbers: undefended falls at t=4959, playtest AI wins at t=13622 after 2 waves. Read the curve with `cargo test -p rts-core --offline kestrel_opening_playtest -- --ignored --nocapture`.
- Every core task that changes balance includes a measured duel or scenario test in the task itself and prints its table in the report.
- Fixtures: when the Kestrel snapshot shape changes, regenerate both Godot fixtures and explain every changed expectation: `cargo build --release -p rts-server --bin godot-bridge --offline && target/release/godot-bridge --scenario kestrel --dump-snapshot godot3d/tests/fixtures/kestrel_snapshot.json && EARTHFRONT_FOG=0 target/release/godot-bridge --scenario kestrel --dump-snapshot godot3d/tests/fixtures/kestrel_snapshot_fog_off.json`.
- SDD ledger: `.superpowers/sdd/2026-10-07-kestrel-depth/progress.md` (one paragraph per task: commits, trailer check, gates, rulings, carries), `plan-path` (this file's path), `task-N-brief.md`, `task-N-report.md` and evidence images in the same folder (gitignored scratch). Scoreboard captures go to `$SCRATCH/world/kdN*`.

### Spec deviations found while planning (controller acknowledges before the owning task starts)

- D1 (Task 13, Task 14): `Command` is matched exhaustively in `crates/core/src/game/civ/mod.rs:455-479` (`command_autonomy_level` style match ending in `| Command::GovernColony { .. } => u8::MAX`). Adding variants cannot compile without one edit there. Ruling: the new variants join the `u8::MAX` arm ("never colony-emitted"); that arm is the only permitted edit in `civ/mod.rs`, behaviour-neutral, no hash effect.
- D2 (Task 24): the shared parser needs a library target so both bins use it without dead-code warnings under `warnings = "deny"`. Ruling: new `crates/server/src/lib.rs` containing only `pub mod bridge_protocol;`.
- D3 (Task 23): the spec's meta pool "8 to 16" cannot reach 16 because only 12 perks are defined (4 existing + 8 depth). Ruling: pool starts at 8 and grows by one per run reaching wave 6, capped at 12; the report says so.
- D4 (Task 28): the version must live in the workspace without touching `crates/core` or `crates/data` (P5 forbids it). Ruling: `[workspace.package] version = "0.2.0"` in the root `Cargo.toml`, `version.workspace = true` in `crates/server/Cargo.toml` only; core, data and render-shell keep `0.1.0`.
- Fact verified during planning (the spec marked it unverified): Logistics and Conscription do NOT reach Earthfront. `run_economy` returns early when `self.earthfront` (`sim.rs:3448`) before the Logistics hook at `:3478`, and `supply_cap` returns 60/90 early (`sim.rs:1796-1802`) before the Conscription hook at `:1815`. Overcharge and Bulwark do apply (their vectors in `run_combat` are not gated). Task 23 adds depth-gated hooks for the two missing perks.

## Review Focus

- Depth leaking into Survival or legacy maps: a Survival match (which also calls `enable_earthfront`, `scenario.rs:233`) must keep today's combat, waves, hash and snapshot bytes; nothing in P2 to P4 may run on `self.earthfront` alone. Owned by Task 10 (`survival_and_classic_kestrel_hashes_are_pinned_across_depth`, re-run unchanged by every later core task) and Task 13 (Survival snapshot carries no `stance` key).
- Replay and determinism divergence between the bridge and headless runs: the bridge, the core tests and `verify-run` must build the same per-tick command list (host AI, scripted probe, player lines), apply the same balance and seed, and treat pause and restart identically; a replay recorded live must verify headless, at any playback speed. Owned by Task 10 (`Scenario::host_commands` is the only host-command builder), Task 24 (bridge loop test records and the header carries balance hash), Task 25 (`recorded_bridge_run_verifies_headless`, `playback_at_8x_equals_1x`, `tampered_replay_fails`).
- Units that never return from a leash or get stuck: an idle unit pulled off by acquisition or an under-attack response must come back to its anchor when the target dies, flees past 6 or a player order supersedes it; a forced target whose entity slot is freed and reused (`alloc_slot` pops `free`, `sim.rs:1352`) must not be chased; Hold units never move. Owned by Task 11 (`unit_returns_to_anchor_after_target_flees_past_leash`), Task 13 (`forced_target_is_dropped_when_its_slot_is_reused`, `hold_never_moves`).
- Difficulty and combat changes making the opening unwinnable or trivially won: AI from tick 0, era-0 raids, Hard's 2:00 first wave, the AntiArmor air counter and the breach must still give a do-nothing player a loss and the playtest AI at least three waves on Normal and Easy (two on Hard), with first contact not before 3000 ticks on Normal. Owned by Task 19 (`first_contact_is_not_earlier_than_tick_3000_on_normal`), Task 20 (`each_difficulty_resolves_and_the_playtest_ai_survives_its_floor`).
- Persistent files and seeds: settings, records, replays and run meta live under `user://` (never `res://`, never the runtime dir), tests use temp paths, the exported smoke run redirects `user://`; a new operation never silently reuses the previous match's seed (random by default, Restart is the only same-seed path), the daily seed is the UTC date, and a replay always verifies with the seed and perk pool from its own header, never local meta. Owned by Task 4 (`settings_never_write_under_res`), Task 20 (`new_operation_draws_a_fresh_seed_and_restart_reuses_it`), Task 26 (`daily_seed_is_the_utc_date`), Task 25 (`verify_reads_pool_from_header_only`), Task 28 (smoke run with `XDG_DATA_HOME` redirected).

## Pre-flight conflict scan

Task pairs that share files or interfaces, and the ruling for each. Implementers follow the ruling; reviewers reject a task that breaks one.

| Tasks | Shared surface | Ruling |
|---|---|---|
| 1 / 20 / 23 / 24 / 25 / 27 | `godot-bridge.rs` `main` loop, runtime paths, `match.json` fields | Task 1 introduces `RuntimePaths::from_output(&Path)` and `MatchConfig` + `parse_match_config(text, fallback)`. Later tasks only ADD fields with defaults that reproduce the earlier behaviour (seed 2026, difficulty Normal, run false, no replay dir, no replay) and add their own malformed-input test. Task 27 only changes where the runtime directory comes from; every path is still derived through `RuntimePaths`. Task 24 moves `MatchConfig` verbatim into `bridge_protocol.rs`. |
| 2 / 9 / 13 / 14 / 26 | `keybinds.gd`, `project.godot` input map, `test_keybinds.gd` | Task 2 owns the camera move to arrows and frees W/A/S/D; S, D and Z become Kestrel-only order keys in Task 13 (added to `KESTREL_ONLY`, Z rotates on Survival as before because Kestrel yaw is locked). Task 9 changes F from tap-to-focus to tap-focus/hold-follow without a new key. Task 14 uses Shift as a modifier only. Task 26's replay viewer reads no keys except Esc (pause menu). `test_keybinds.gd` must stay green with a no-clash assertion after each. |
| 3 / 4 / 9 / 22 / 26 | `user://` persistence | Task 4's `Settings` module is the only code that opens `user://settings.cfg` (sections `audio`, `video`, `game`, `coach`, `run`); Task 9 and Task 26 call `Settings.get_value/set_value`. Task 22's `Records` module is the only code that opens `user://records.cfg`. Both take an injectable path for tests. |
| 3 / 22 / 23 / 26 | `live_screens.gd` `title_vm` and `debrief_vm` | Task 3 owns the button list and the picker; Task 22 adds score rows to `debrief_vm` additively; Task 26 adds run rows and the Replays entry additively. `footer_right` stays "" until Task 28 fills it with the version. |
| 7 / 18 | client affordability check vs dynamic refinery price | Task 7's `FeedbackEvents.funds_short(cost, money)` reads card cost from `LiveAdapter.BUILD_CARDS`; Task 18 adds `"depth":{"refinery_cost":N}` to the Kestrel snapshot and changes the cost lookup to prefer it. Survival never sees the key. |
| 10 / 11 to 23 | `DepthUnit`, `DepthGlobal`, their `hash_into`, `sim.rs` hash insertion points | Task 10 creates both structs (empty) and the two hash call sites. Every later task appends its fields at the END of the struct and its hash writes at the END of `hash_into`, in task order, never reordering. Each task re-runs Task 10's pins unchanged. |
| 10 / 19 / 25 | non-player command list | `Scenario::host_commands(self, &Sim)` (Task 10) is the only builder. Task 19 changes its depth branch (alien AI from tick 0); the bridge, `kestrel_shell_commands` and `verify-run` all call it. |
| 13 / 14 / 23 / 24 | `Command` enum, `take_commands` text protocol | New variants are appended at the end of `Command` (Task 13: Stop, HoldPosition, SetStance, AttackTarget; Task 14: QueueMove). New text lines are added as match arms in `take_commands` (Task 13: `stop`, `hold`, `stance`, `target`; Task 14: `qmove`, `qattack`; Task 17: `upgrade`; Task 23: `perk`). Task 24 moves the parser unchanged (same tests) into `bridge_protocol::parse_command_line`. Task 23 lands before Task 24 so the move is complete. |
| 15 / 16 / 17 / 19 / 21 | Kestrel outcome test numbers | Each re-baselines in its own commit with old and new ticks; Task 21 replaces the open window with the 27,000 to 45,000 match-length assertion. No task loosens the undefended-falls or never-overrun-before-wave-3 invariants. |
| 16 / 19 / 20 / 23 | `run_earthfront_waves` (`earthfront.rs:918`) | Task 16 changes only the siege threshold and the siege lead (inline, depth-gated). Task 19 moves depth composition into `depth.rs` (`depth_wave_kind`, `depth_expedition_size`) and calls them from `run_earthfront_waves` under depth. Task 20 sets timing through `WaveConfig` in `kestrel_reach_with` and size through `Difficulty::wave_size_pct`. Task 23's perks never change wave config; run length uses `waves_cleared`. |
| 17 / 23 | Upgrades and ability cooldowns | Task 23's "free upgrade level" and "ability cooldown -25%" perks call Task 17's `apply_depth_upgrade` and `depth_ability_cooldown`; no second cost or cooldown path. |
| 18 / 23 | `depth_building_cost`, depth repair | One source each (Task 18); Task 23's refinery-discount and cheaper-repair perks modify inside them. |
| 21 / 22 / 23 / 25 | score | `Sim::depth_score()` (Task 22) is the only score; Task 23 adds the run bonus inside it; `verify-run` prints it. |
| 24 / 27 / 4 | where replays and settings live | Replays go to `MatchConfig.replay_dir`, which the client fills with `ProjectSettings.globalize_path("user://replays")`; the bridge never defaults to the runtime dir or `res://`. Task 27's `user://runtime` holds only flags, packets, `match.json` and the snapshot. |
| 1 / 27 | `run-3d.sh` | Task 1 drops the `SCENARIO` requirement; Task 27 adds `--runtime-dir` to the bridge call; both keep `SCENARIO=survival ./run-3d.sh` working. |
| 5 / later docs | README test counts | Task 5 removes hardcoded test counts in favour of the command that prints them, so no later task edits counts. |

---

## P0. Hygiene and front door

### Task 1: Bridge freeze fix, Kestrel default and runtime match switching

Size M.

**Files:**
- Modify: `crates/server/src/bin/godot-bridge.rs` (`ShotWindow` `:541-605`, `parse_args` `:1296-1335` default `:1298`, `main` `:1337-1490`, tests from `:1491`), `run-3d.sh` (`:23-28`), `.gitignore`
- Test: tests in `godot-bridge.rs` (`mod tests`)

**Interfaces:**
- Consumes: `Scenario::build(seed)`, `FogState::new(bool)`, `fog_enabled_from`, `write_atomic`.
- Produces:
  - `ShotWindow::record(&mut self, tick: u64, attacks: &[(Vec2, Vec2)], finished: bool)` with a new field `last_tick: Option<u64>`; skips when `finished` or `Some(tick) == last_tick`.
  - `struct RuntimePaths { snapshot: PathBuf, commands: PathBuf, start: PathBuf, restart: PathBuf, pause: PathBuf, match_config: PathBuf }` and `RuntimePaths::from_output(output: &Path) -> Self` (same file names as today, plus `match.json`).
  - `struct MatchConfig { scenario: Scenario, fog: Option<bool> }`, `fn parse_match_config(text: &str, fallback: Scenario) -> MatchConfig` (flat JSON object; unknown keys ignored; any malformed value falls back to the default for that key; malformed object returns `MatchConfig { scenario: fallback, fog: None }`), `fn read_match_config(path: &Path, fallback: Scenario) -> MatchConfig` (missing file = fallback).
  - Bridge default scenario `Scenario::KestrelReach`; on restart the bridge reads `match.json` (if present), rebuilds `cfg.scenario` with seed 2026 and resets the fog with `FogState::new(env_fog && cfg.fog.unwrap_or(true))`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test]
fn shot_window_does_not_grow_after_a_win() {
    let mut window = ShotWindow::new();
    let a = (Vec2::new(Fixed::ONE, Fixed::ONE), Vec2::new(Fixed::from_int(2), Fixed::ONE));
    window.record(100, &[a], false);
    let len = window.len();
    for _ in 0..100 {
        window.record(100, &[a], false); // tick did not advance
        window.record(100, &[a], true); // finished sim
    }
    assert_eq!(window.len(), len);
}

#[test]
fn won_sim_stepped_for_100_frames_keeps_the_window_length() {
    let mut sim = Scenario::KestrelReach.build(2026);
    let mut window = ShotWindow::new();
    // drive to a winner the cheap way: the undefended run
    while sim.winner().is_none() {
        let cmds = sim.ai_commands(PlayerId(1));
        sim.step(&cmds);
        window.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
    }
    let len = window.len();
    for _ in 0..100 {
        sim.step(&[]);
        window.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
    }
    assert_eq!(window.len(), len);
}

#[test]
fn match_config_parses_and_falls_back() {
    let c = parse_match_config(r#"{"scenario":"survival","seed":7,"difficulty":"hard","fog":false}"#, Scenario::KestrelReach);
    assert_eq!(c.scenario, Scenario::Survival);
    assert_eq!(c.fog, Some(false));
    let c = parse_match_config("not json", Scenario::KestrelReach);
    assert_eq!((c.scenario, c.fog), (Scenario::KestrelReach, None));
    let c = parse_match_config(r#"{"scenario":"mars","fog":"maybe"}"#, Scenario::KestrelReach);
    assert_eq!((c.scenario, c.fog), (Scenario::KestrelReach, None));
    let c = read_match_config(std::path::Path::new("/nonexistent/match.json"), Scenario::Survival);
    assert_eq!(c.scenario, Scenario::Survival);
}

#[test]
fn runtime_paths_sit_beside_the_snapshot() {
    let p = RuntimePaths::from_output(std::path::Path::new("/r/snapshot.json"));
    assert_eq!(p.restart, std::path::PathBuf::from("/r/restart.flag"));
    assert_eq!(p.match_config, std::path::PathBuf::from("/r/match.json"));
    assert_eq!(p.commands, std::path::PathBuf::from("/r/commands.txt"));
}
```

Also edit the existing `parse_args` test (`:1927-1946`): with no `--scenario` the default is now `Scenario::KestrelReach`; `--scenario=survival` still yields Survival.

- [ ] **Step 2: Run to verify they fail**

Run: `cargo test -p rts-server --bin godot-bridge --offline shot_window match_config runtime_paths parses`
Expected: compile errors (`record` takes 2 args, `parse_match_config` and `RuntimePaths` not defined) and the default-scenario assertion failing.

- [ ] **Step 3: Implement**

```rust
fn record(&mut self, tick: u64, attacks: &[(Vec2, Vec2)], finished: bool) {
    if finished || self.last_tick == Some(tick) {
        return;
    }
    self.last_tick = Some(tick);
    // existing extend + retain unchanged
}
// clear() also resets last_tick = None.
```

`parse_match_config` is a hand parser (the server crate has no serde): find `"key":` and read either a quoted string or a bare token up to `,` or `}`; `scenario` maps through `parse_scenario`; `fog` accepts `true`/`false` only. In `main`: replace the `with_file_name` calls with `RuntimePaths::from_output(&output)`; make `scenario` mutable; in the restart branch call `read_match_config(&paths.match_config, scenario)`, set `scenario = cfg.scenario`, rebuild, `fog = FogState::new(fog_enabled && cfg.fog.unwrap_or(true))`. The record call becomes `shots.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some())`. `run-3d.sh`: comment says Kestrel is the default and `SCENARIO=survival` selects Survival; the existing `if [[ -n "${SCENARIO:-}" ]]` block stays. `.gitignore`: add `/godot3d/runtime/*.flag` and `/godot3d/runtime/commands/` (`match.json` is already covered by `/godot3d/runtime/*.json`).

- [ ] **Step 4: Run tests and gates**

Run: `cargo test -p rts-server --bin godot-bridge --offline` then the full gate list. Expected: PASS, Survival byte-identical test untouched and green. Then `git check-ignore godot3d/runtime/restart.flag godot3d/runtime/commands/x.cmd godot3d/runtime/match.json` prints all three.

- [ ] **Step 5: Commit**

```bash
git add crates/server/src/bin/godot-bridge.rs run-3d.sh .gitignore
git commit -m "Bridge: freeze the shot window after a win, Kestrel by default, match.json on restart"
```

---

### Task 2: Controls: arrow-key pan, middle-drag, nine groups, four build hotkeys, F1 hint

Size M.

**Files:**
- Modify: `godot3d/project.godot` (`[input]` `:17-23`), `godot3d/scripts/ui/keybinds.gd` (`:15-36` constants, `groups()` camera rows), `godot3d/scripts/earthfront_3d.gd` (`_update_camera_controls` `:1531-1549`, `_unhandled_input` `:1592`, group handling), `godot3d/scripts/ui/live_adapter.gd` (`BUILD_CARDS` hotkey column `:52-64`), `godot3d/scripts/ui/hud.gd` (F1 hint), `godot3d/tests/test_keybinds.gd`, `godot3d/tests/test_section_control_groups.gd`, `godot3d/tests/test_screen_controls_reference.gd`
- Create: `godot3d/tests/test_camera_pan.gd`

**Interfaces:**
- Consumes: `Keybinds.CAMERA_ACTIONS`, `_camera_step(delta, motion, aspect, rotate_axis)`.
- Produces: `Keybinds.CAMERA_ACTIONS` = `{"camera_up": KEY_UP, "camera_left": KEY_LEFT, "camera_down": KEY_DOWN, "camera_right": KEY_RIGHT, "camera_rotate_left": KEY_Z, "camera_rotate_right": KEY_E}`; `Keybinds.GROUPS` = `KEY_1..KEY_9`; `Keybinds.BUILD` gains `KEY_N: "VehicleFactory", KEY_I: "Airfield", KEY_O: "SupplyDepot", KEY_COMMA: "Battery"`; `Keybinds.CONTROLS_HINT := "F1 Controls"`; `earthfront_3d.gd` `func _drag_pan(relative: Vector2) -> Vector3` (pure, returns the focus delta for a middle-mouse drag).

- [ ] **Step 1: Failing tests**

```gdscript
# test_keybinds.gd additions
func test_wasd_no_longer_pan(t) -> void:
	for action in ["camera_up", "camera_left", "camera_down", "camera_right"]:
		for ev in InputMap.action_get_events(action):
			t.ok(not (ev is InputEventKey and ev.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]), action)

func test_nine_groups_and_new_build_keys_do_not_clash(t) -> void:
	t.eq(Keybinds.GROUPS.size(), 9)
	var seen := {}
	var all: Array = Keybinds.GROUPS + Keybinds.TRAIN.keys() + Keybinds.BUILD.keys() + [Keybinds.ATTACK_MOVE, Keybinds.ABILITY, Keybinds.REPAIR, Keybinds.SELL, Keybinds.SCIENCE, Keybinds.REGION_MAP, Keybinds.FOCUS, Keybinds.HOME, Keybinds.JUMP_ALERT, Keybinds.SELECT_IDLE]
	for k in all:
		t.ok(not seen.has(k), "clash on %s" % Keybinds.cap(k))
		seen[k] = true
	for kind in ["VehicleFactory", "Airfield", "SupplyDepot", "Battery"]:
		t.ok(Keybinds.BUILD.values().has(kind), kind)

# test_camera_pan.gd
func test_middle_drag_moves_focus_against_the_drag(t) -> void:
	var g = load("res://scripts/earthfront_3d.gd").new()
	var d: Vector3 = g._drag_pan(Vector2(100, 0))
	t.ok(d.x < 0.0, "dragging right pans the world left")
	g.free()
```

Every `BUILD_CARDS` row must show its hotkey letter (assert no empty hotkey column in `test_live_adapter.gd`), and the HUD shows "F1 Controls" (assert in `test_hud.gd`).

- [ ] **Step 2: Run to verify failure**

Run: `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --audio-driver Dummy --path godot3d --script res://tests/run_tests.gd -- test_keybinds`
Expected: FAIL on the W/A/S/D and group-count assertions.

- [ ] **Step 3: Implement** the input map change (physical keycodes 4194320 UP, 4194319 LEFT, 4194322 DOWN, 4194321 RIGHT), the constants, the controls-reference rows ("Pan" shows the arrows, new "Drag pan" mouse row with proof needle `"_drag_pan("`), groups 1-9 in the group handler and the control-groups section, the four hotkeys in `BUILD_CARDS`, middle-button drag in `_unhandled_input` calling `_drag_pan`, and the F1 hint label on the HUD (Kestrel and Survival).

- [ ] **Step 4: Gates, capture, score.** The controls board and HUD change; show before/after captures; no idle board may drop more than 2.0 (the hint is small).

- [ ] **Step 5: Commit**

```bash
git add godot3d/project.godot godot3d/scripts/ui/keybinds.gd godot3d/scripts/earthfront_3d.gd godot3d/scripts/ui/live_adapter.gd godot3d/scripts/ui/hud.gd godot3d/tests/test_keybinds.gd godot3d/tests/test_section_control_groups.gd godot3d/tests/test_screen_controls_reference.gd godot3d/tests/test_camera_pan.gd godot3d/tests/test_live_adapter.gd godot3d/tests/test_hud.gd
git commit -m "Controls: pan on arrows and middle drag, A only attack-moves, groups 1-9, build hotkeys N I O comma, F1 hint"
```

---

### Task 3: Map picker on the title and the new debrief buttons

Size M.

**Files:**
- Create: `godot3d/scripts/match_config.gd`, `godot3d/scripts/ui/sections/map_picker.gd`, `godot3d/tests/test_map_picker.gd`
- Modify: `godot3d/scripts/ui/live_screens.gd` (`title_vm` `:20-48`, `debrief_vm` `:66-80`), `godot3d/scripts/ui/game_ui.gd` (`_on_title_action` `:439-445`, `_on_debrief_action` `:465-472`), `godot3d/scripts/earthfront_3d.gd` (`_restart_mission` `:3908-3914`, `_deploy_mission` `:3967`), `godot3d/scripts/gallery/fixtures_title.gd`, `godot3d/tests/test_title.gd`, `godot3d/tests/test_debrief.gd`, `godot3d/tests/test_live_screens.gd`, `tools/ui/world_scores.json` / title compare baseline only if the board intentionally changes

**Interfaces:**
- Consumes: Task 1's `match.json` contract and restart flag; `_restart_mission()`; `runtime_directory`.
- Produces:
  - `MatchConfig` (preload, static): `const SCENARIOS := ["kestrel", "survival"]`, `static func defaults() -> Dictionary` (`{"scenario": "kestrel", "seed": 2026, "difficulty": "normal", "fog": true}`), `static func to_json(cfg: Dictionary) -> String`, `static func write(runtime_dir: String, cfg: Dictionary) -> bool` (atomic: write `match.json.next`, rename), `static func display_name(scenario: String) -> String` ("Kestrel Reach" / "Earthfront Survival"), `static var current: Dictionary` (the config of the running match, kept across the scene reload via `Engine.set_meta("match_config", cfg)`), `static func pending_auto_deploy() -> bool` / `static func set_auto_deploy(on: bool)` (via `Engine.set_meta("auto_deploy", on)`).
  - `title_vm(...)`: the "New operation" item opens the picker (`action: "pick_map"`); campaign card `name` = `MatchConfig.display_name(current.scenario)`.
  - Picker confirm: `MatchConfig.write(runtime_dir, cfg)`, write `restart.flag`, wait until `restart.flag` is gone plus 0.1 s, then `_deploy_mission()` (no scene reload; the title scene is fresh).
  - `debrief_vm` buttons: `[{"label":"Review battlefield","action":"review","primary":true}, {"label":"Restart","action":"restart"}, {"label":"Main menu","action":"menu"}, {"label":"Quit","action":"quit"}]`. Restart = same config (same seed) + `set_auto_deploy(true)` + `_restart_mission()`; after the reload the title sees `pending_auto_deploy()` and deploys once the bridge snapshot shows tick 0. Main menu = `_restart_mission()` without auto-deploy (today's Redeploy). Quit = `get_tree().quit()`.

- [ ] **Step 1: Failing tests** (`test_map_picker.gd`, `test_debrief.gd`, `test_title.gd`)

```gdscript
const MatchConfig := preload("res://scripts/match_config.gd")
const DIR := "user://test_map_picker"

func test_write_produces_the_bridge_contract(t) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cfg := MatchConfig.defaults()
	cfg.scenario = "survival"
	t.ok(MatchConfig.write(DIR, cfg))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("match.json")))
	t.eq(parsed.scenario, "survival")
	t.eq(parsed.fog, true)
	t.ok(not FileAccess.file_exists(DIR.path_join("match.json.next")))
	DirAccess.remove_absolute(DIR.path_join("match.json"))
	DirAccess.remove_absolute(DIR)

func test_debrief_offers_restart_menu_and_quit(t) -> void:
	var g := StubGame.new()  # tests/stub_game.gd
	g.bridge_winner = 1
	var vm := LiveScreens.debrief_vm(g, null)
	var actions := []
	for b in vm.buttons:
		actions.append(b.action)
	t.eq(actions, ["review", "restart", "menu", "quit"])

func test_title_new_operation_opens_the_picker_and_names_the_map(t) -> void:
	var vm := LiveScreens.title_vm(true, 0)
	var deploy = vm.menu.filter(func(i): return i.id == "deploy")[0]
	t.eq(deploy.get("action", "pick_map"), "pick_map")
	t.eq(vm.campaign.featured.name, "Kestrel Reach")
```

Add a picker test with a fake runtime dir: confirming Survival writes `match.json` and `restart.flag`, and deploy waits until the flag is removed (simulate the bridge by deleting it).

- [ ] **Step 2: Run to verify failure** (`-- test_map_picker`, `-- test_debrief`, `-- test_title`). Expected: FAIL (missing script, old buttons, old name "Operation Dawnshield").
- [ ] **Step 3: Implement** the module, the picker section (two cards, Kestrel default, built with the kit used by the pause menu), the title and debrief wiring, and the auto-deploy hook in the title flow. Keep Survival's debrief text otherwise unchanged.
- [ ] **Step 4: Gates, capture, score.** The title board changes by intent (picker entry, campaign card name): show before/after title captures and re-baseline only the title comparison after showing it. Debrief board: show it.
- [ ] **Step 5: Commit** (stage only the files above), message "Title map picker and debrief Restart, Main menu, Quit".

---

### Task 4: Settings screen with persisted volumes, fog and window mode

Size M.

**Files:**
- Create: `godot3d/scripts/ui/settings.gd`, `godot3d/scripts/ui/sections/settings_screen.gd`, `godot3d/tests/test_settings.gd`
- Modify: `godot3d/scripts/ui/live_screens.gd` (`settings` menu item enabled), `godot3d/scripts/ui/game_ui.gd` (title action `settings`, pause menu `open_settings`, `_on_pause_action` `:748`), `godot3d/scripts/ui/sections/pause_menu.gd` (one entry), `godot3d/scripts/earthfront_3d.gd` (`_setup_audio` `:377` applies saved volumes), `godot3d/scripts/match_config.gd` (fog from settings), `godot3d/tests/test_game_ui_pause.gd`, `godot3d/tests/test_screen_pause_menu.gd`

**Interfaces:**
- Consumes: bus names Master, SFX, UI, Ambient, Music (`default_bus_layout.tres`), `Keybinds.vm(...)` for the read-only keybind list, `MatchConfig.write`.
- Produces: `Settings` (static): `const PATH := "user://settings.cfg"`, `static func defaults() -> Dictionary` (`{"audio/master": 1.0, "audio/sfx": 1.0, "audio/ui": 1.0, "audio/ambient": 1.0, "audio/music": 1.0, "game/fog": true, "video/window_mode": "windowed"}`), `static func load_from(path: String) -> Dictionary` (missing or corrupt file = defaults; out-of-range values clamped), `static func save_to(path: String, values: Dictionary) -> int` (refuses any path starting with `res://`, returns `ERR_FILE_NO_PERMISSION`), `static func get_value(key: String, path := PATH) -> Variant`, `static func set_value(key: String, value: Variant, path := PATH) -> int`, `static func apply_audio(values: Dictionary) -> void` (linear to dB on each bus, 0 mutes), `static func apply_window(values: Dictionary) -> void`.

- [ ] **Step 1: Failing tests**

```gdscript
const Settings := preload("res://scripts/ui/settings.gd")
const P := "user://test_settings/settings.cfg"

func test_round_trip_and_clamp(t) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	var v := Settings.defaults()
	v["audio/sfx"] = 0.25
	v["game/fog"] = false
	t.eq(Settings.save_to(P, v), OK)
	var back := Settings.load_from(P)
	t.near(back["audio/sfx"], 0.25, 0.001)
	t.eq(back["game/fog"], false)
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", 7.0)
	cf.save(P)
	t.near(Settings.load_from(P)["audio/master"], 1.0, 0.001)
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")

func test_settings_never_write_under_res(t) -> void:
	t.eq(Settings.save_to("res://settings.cfg", Settings.defaults()), ERR_FILE_NO_PERMISSION)
	t.ok(not FileAccess.file_exists("res://settings.cfg"))

func test_corrupt_file_gives_defaults(t) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[[[ not a config")
	f.close()
	t.eq(Settings.load_from(P), Settings.defaults())
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")
```

Plus: `apply_audio` with `audio/music = 0` sets the Music bus mute; the title's Settings item is enabled and opens the screen; the pause menu lists Settings; the fog toggle value lands in the next `match.json`.

- [ ] **Step 2: Run to verify failure** (`-- test_settings`).
- [ ] **Step 3: Implement** module, screen (five sliders, fog toggle "applies next match", window mode option, read-only keybind list reusing the controls reference rows), title and pause entries, apply on startup.
- [ ] **Step 4: Gates, capture** of the settings screen (open the image), score (title board moves only by the now-enabled item; show it).
- [ ] **Step 5: Commit**, message "Settings screen: bus volumes, fog for the next match, window mode, saved in user://settings.cfg".

---

### Task 5: Docs drift and CI jobs

Size S.

**Files:**
- Modify: `README.md` (`:9`, `:40`, `:102`, plus one paragraph: the Godot client is the product, the Macroquad shell is legacy), `godot3d/README.md` (`:5-7`), `NEXT_STEPS.md` (`:7`), `.github/workflows/ci.yml`
- Create: `tools/ci/check_ci_yaml.py` (structure check used when `actionlint` is absent), `tools/ci/test_check_ci_yaml.py`

**Interfaces:**
- Produces: CI jobs `godot` (cache `tools/godot/Godot_v4.7.2-stable_linux.x86_64` keyed on version, download `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` on miss, run the headless suite with `--audio-driver Dummy`, fail when the log contains `SCRIPT ERROR`, `SHADER ERROR` or a line starting `ERROR`) and `python-tools` (install numpy, pillow, scipy; run the `tools/ui` and `tools/audio` unittest modules from the Global Constraints). `check_ci_yaml.py <file>` exits 0 when the YAML parses, every job has `runs-on` and `steps`, and every step has `run` or `uses`.

- [ ] **Step 1: Failing test**

```python
import subprocess, sys, pathlib, unittest
HERE = pathlib.Path(__file__).parent
CI = HERE.parent.parent / ".github/workflows/ci.yml"

class CiYaml(unittest.TestCase):
    def test_workflow_has_the_three_jobs(self):
        import yaml
        jobs = yaml.safe_load(CI.read_text())["jobs"]
        self.assertTrue({"check", "godot", "python-tools"} <= set(jobs))
    def test_checker_accepts_the_workflow(self):
        r = subprocess.run([sys.executable, str(HERE / "check_ci_yaml.py"), str(CI)])
        self.assertEqual(r.returncode, 0)
    def test_checker_rejects_a_step_without_run_or_uses(self):
        bad = HERE / "_bad.yml"
        bad.write_text("jobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - name: nothing\n")
        try:
            self.assertNotEqual(subprocess.run([sys.executable, str(HERE / "check_ci_yaml.py"), str(bad)]).returncode, 0)
        finally:
            bad.unlink()
```

- [ ] **Step 2: Run** `cd tools/ci && python3 -m unittest test_check_ci_yaml -v`. Expected: FAIL (no checker, no jobs).
- [ ] **Step 3: Implement** the checker and the two jobs; fix each doc drift item (README:9 fog of war now exists on Kestrel; README:40 first wave 2:30; README:102 and NEXT_STEPS:7 replace the counts with "run `cargo test --workspace` and the Godot suite to see the current counts"; `godot3d/README.md:5-7` describes what is really shipped).
- [ ] **Step 4: Validate** `which actionlint && actionlint .github/workflows/ci.yml || python3 tools/ci/check_ci_yaml.py .github/workflows/ci.yml`; run the unittest again (PASS); full gates.
- [ ] **Step 5: Commit**, message "Docs drift fixed; CI gains Godot headless and Python tool jobs (validated locally; no remote, never run)".
- [ ] **Step 6: Phase P0 end check:** `git diff --stat 67e6355..HEAD -- crates/` lists only `crates/server/src/bin/godot-bridge.rs`; full gates; append the phase line to the ledger.

---

## P1. Feedback

### Task 6: Eight new procedural sound ids

Size S.

**Files:**
- Modify: `tools/audio/build_sfx.py` (`SOUNDS` table `:444`), `tools/audio/test_build_sfx.py`, `godot3d/assets/audio/sfx/sfx_manifest.json`, `godot3d/assets/audio/sfx/README.md`
- Create: `godot3d/assets/audio/sfx/{denied,place_thunk,power_down,power_up,wave_cleared,research_complete,victory_sting,defeat_sting}.wav` (+ `.import` from a `--headless --import` run)

**Interfaces:**
- Produces: manifest ids `denied` (ui), `place_thunk` (ui), `power_down` (alert), `power_up` (alert), `wave_cleared` (alert), `research_complete` (alert), `victory_sting` (alert), `defeat_sting` (alert); 26 ids total.

- [ ] **Step 1: Failing tests**: extend `test_build_sfx.py` so the expected id set is the 26 ids, and the existing per-id checks (deterministic bytes over two runs, duration range, peak below 0 dBFS, loudness within 6 dB per category, committed file equals generator output) run for the new ids. Add stings: duration 1.5 to 3.0 s.
- [ ] **Step 2: Run** `cd tools/audio && python3 -m unittest test_build_sfx -v`. Expected: FAIL on the id set.
- [ ] **Step 3: Implement** eight builders in the same numpy style (`env`, `tone_note`, `band`, `finish`), add them to `SOUNDS`, regenerate, import. Print the loudness/peak table. Total sfx folder stays under 3 MB.
- [ ] **Step 4: Gates.** No listening; the table is the check.
- [ ] **Step 5: Commit**, message "Audio: eight new procedural cues (denied, place, power down/up, wave cleared, research, victory and defeat stings)".

---

### Task 7: Every important event gets a cue and a toast

Size M.

**Files:**
- Create: `godot3d/scripts/ui/feedback_events.gd`, `godot3d/tests/test_feedback_events.gd`
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_write_bridge_train` `:2319`, `_write_bridge_build` `:2376`, `_write_bridge_rally` `:2333`, snapshot poll near `:2450`, `_sfx` `:3402`, victory/defeat call sites), `godot3d/scripts/audio/audio_director.gd` (`COOLDOWN` `:26`: `unit_attacked` 10 s), `godot3d/tests/test_audio_hooks.gd`

**Interfaces:**
- Consumes: Task 6 ids; `bridge_money` (`money_bits / 65536`, `:2450`); `LiveAdapter.BUILD_CARDS` costs; unit costs from the same command table the deck uses; snapshot `power_generation`, `power_demand`, `waves_survived`, `next_wave_ticks`, entities with `hp`, `owner`, `kind`.
- Produces: `FeedbackEvents` (static, pure): `static func funds_short(cost: int, money: int) -> int` (0 when affordable), `static func derive(prev: Dictionary, snap: Dictionary, state: Dictionary) -> Array` returning dictionaries `{"id": String, "toast": String, "at": Vector3 or null}` for: `power_down` (demand crosses above generation), `power_up` (back at or below), `wave_warning` (next wave crosses 45 s; id `alert` played at -6 dB via the director's `volume_db` override), `wave_cleared` (a wave has spawned and no unit with owner 1 that arrived with it remains: tracked in `state` as the set of alien unit ids present at the spawn tick), `unit_attacked` (a human unit lost HP; one per 10 s), `production_complete` (one per batch: units of one kind appearing in the same poll give one toast "3 Riflemen ready"). `state` is the caller-owned memo dictionary.
- Insufficient funds: `_write_bridge_train` / `_write_bridge_build` check `funds_short`; when short they do not send, play `denied` and toast "N materials short".

- [ ] **Step 1: Failing tests** (pure, crafted snapshots; recording stub for audio as `test_audio_director.gd` already does)

```gdscript
const FE := preload("res://scripts/ui/feedback_events.gd")

func _snap(gen, dem, waves, next_ticks, ents := []) -> Dictionary:
	return {"power_generation": gen, "power_demand": dem, "waves_survived": waves, "next_wave_ticks": next_ticks, "entities": ents}

func test_power_down_then_up_fire_once_each(t) -> void:
	var st := {}
	var a := FE.derive(_snap(100, 80, 0, 4000), _snap(100, 120, 0, 3990), st)
	t.eq(a.map(func(e): return e.id), ["power_down"])
	t.eq(FE.derive(_snap(100, 120, 0, 3990), _snap(100, 130, 0, 3980), st).size(), 0)
	var b := FE.derive(_snap(100, 130, 0, 3980), _snap(150, 130, 0, 3970), st)
	t.eq(b.map(func(e): return e.id), ["power_up"])

func test_funds_short(t) -> void:
	t.eq(FE.funds_short(150, 100), 50)
	t.eq(FE.funds_short(100, 100), 0)

func test_batch_of_three_riflemen_is_one_toast(t) -> void:
	var st := {}
	var before := _snap(100, 50, 0, 4000, [])
	var ents := []
	for i in 3:
		ents.append({"id": 40 + i, "owner": 0, "kind": "Infantry", "hp": 100})
	var ev := FE.derive(before, _snap(100, 50, 0, 3990, ents), st)
	t.eq(ev.filter(func(e): return e.id == "production_complete").size(), 1)
```

Plus `wave_cleared` after the spawned wave's alien ids are all gone, `unit_attacked` cooldown 10 s, and a hook test: a short train request sends no command packet (fake runtime dir) and requests `denied`; victory requests `victory_sting`, defeat `defeat_sting`; rally plays `ui_click`. Survival keeps its tones (assert the director path is not called when `world_art_on` is false).

- [ ] **Step 2: Run** `-- test_feedback_events` and `-- test_audio_hooks`. Expected: FAIL.
- [ ] **Step 3: Implement** the pure module and the Kestrel-only wiring.
- [ ] **Step 4: Gates**, one Xvfb software session with `--audio-driver Dummy` and `EARTHFRONT_AUDIO_LOG=1` (via `launch_ui.py`) confirming the new ids appear in the play log; state that nothing was listened to.
- [ ] **Step 5: Commit**, message "Kestrel feedback: denied orders, power, wave warning and cleared, under attack, production batches, stings".

---

### Task 8: Building damage and working states

Size M.

**Files:**
- Create: `godot3d/scripts/world/building_states.gd`, `godot3d/tests/test_building_states.gd`
- Modify: `godot3d/scripts/world/world_fx.gd` (new `smoke`/`fire` on the existing pooled cards; `dust` `:396`, `flash` `:305`), `godot3d/scripts/earthfront_3d.gd` (`_sync_bridge_entities`), `godot3d/tests/test_world_fx.gd`, `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: entity `hp`, `max_hp`, `construction`, services `power` and the producing/researching state the HUD already reads; `FogView.is_visible(pos)`.
- Produces: `BuildingStates.state_for(hp: int, max_hp: int, working: bool) -> String` (`"fire"` below 25%, `"smoke"` below 50%, `"working"` when working, else `"ok"`); `BuildingStates.next_emit(state: String, last_emit: float, now: float) -> bool` (smoke every 0.6 s, fire every 0.35 s with a flicker flash, working puff every 2.5 s); `WorldFx.smoke(pos: Vector3, size: float) -> int` and `WorldFx.fire(pos: Vector3, size: float) -> int` returning a pooled slot or -1 when culled/out of view.

- [ ] **Step 1: Failing tests**: thresholds (49% smoke, 24% fire, 100% working when producing), emit cadence, pool bound (40 burning buildings never exceed the existing pool), a fogged building emits nothing, Survival never calls it.
- [ ] **Step 2: Run** `-- test_building_states`, `-- test_world_fx`. Expected: FAIL.
- [ ] **Step 3: Implement** (Kestrel only, fog-gated, pooled; no new art).
- [ ] **Step 4: Gates, capture, score.** Idle boards with a damaged building may change (intended for P1 damage states): show before/after; perf within budget (draw calls and primitives from the capture's perf table).
- [ ] **Step 5: Commit**, message "Kestrel buildings smoke, burn and puff while working (pooled WorldFx, fog-gated)".

---

### Task 9: Camera group centring and follow, onboarding coach

Size M.

**Files:**
- Create: `godot3d/scripts/ui/kestrel_coach.gd`, `godot3d/tests/test_kestrel_coach.gd`, `godot3d/tests/test_camera_follow.gd`
- Modify: `godot3d/scripts/earthfront_3d.gd` (group recall, FOCUS handling, coach wiring), `godot3d/scripts/ui/hud.gd` (coach hint card, dismiss and "never show again"), `godot3d/scripts/ui/keybinds.gd` (row text only)

**Interfaces:**
- Consumes: `KestrelObjectives.evaluate(snapshot)` stages; `Settings.get_value/set_value("coach/never_show")`.
- Produces: `KestrelCoach` (pure): `const STEPS := ["select_squad", "move", "place_building", "train", "attack_move", "done"]`, `static func advance(step: String, event: String) -> String` (events `"selected_units"`, `"move_sent"`, `"build_sent"`, `"train_sent"`, `"attack_move_sent"`), `static func hint(step: String) -> Dictionary` (`{"title", "body", "keys"}`), `static func visible(step: String, never_show: bool, kestrel: bool) -> bool`. Camera: `func _group_tap(index: int, now: float) -> bool` (true = centre on the group: same index within 0.35 s), F tap focuses (today), F held over 0.25 s follows the selection centroid until released.

- [ ] **Step 1: Failing tests**: coach advances only on the matching event, skips nothing, `visible` false when `never_show` or Survival, dismissal persists through a temp settings path; double tap within 0.35 s centres, a slow second tap does not; hold-F follow keeps the focus on a moving centroid across 30 frames of `_camera_step`.
- [ ] **Step 2: Run** `-- test_kestrel_coach`, `-- test_camera_follow`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates, capture** of the first hint over the start (open it), score.
- [ ] **Step 5: Commit**, message "Kestrel coach hints and camera group centring, hold F to follow".
- [ ] **Step 6: Phase P1 end check:** `git diff --stat 67e6355..HEAD -- crates/` still lists only `godot-bridge.rs`; full gates; ledger line.

---

## P2. Combat that feels like an RTS

### Task 10: The depth flag, depth.rs, hash plumbing, one host-command builder, determinism pins

Size M.

**Files:**
- Create: `crates/core/src/game/depth.rs`
- Modify: `crates/core/src/game/sim.rs` (module declaration beside `:10-12`; `Entity` `:90-148` gains `dp`; entity constructors at `:2347` and `:2390` region; `Sim` `:721-787` gains `depth` and `dg`; `Sim::new` `:956-990`; `state_hash` after the per-entity Earthfront block `:2179-2186` and after the global block `:2198-2201`), `crates/core/src/game/scenario.rs` (`kestrel_reach` `:369-475` calls `enable_depth`; `Scenario::host_commands`; test helper `kestrel_shell_commands` `:1928`), `crates/server/src/bin/godot-bridge.rs` (`main` loop builds non-player commands with `scenario.host_commands(&sim)`)

**Interfaces:**
- Consumes: `Sim::enable_earthfront`, `Scenario::scripted_commands`, `Sim::ai_commands`, `Fnv`.
- Produces:
  - In `sim.rs`: `#[path = "depth.rs"] mod depth;` and fields `depth: bool`, `dg: depth::DepthGlobal`; `Entity.dp: depth::DepthUnit` (constructors use `depth::DepthUnit::default()`).
  - In `depth.rs`: `#[derive(Clone, Debug, Default)] pub(super) struct DepthUnit {}` with `pub(super) fn hash_into(&self, h: &mut Fnv)`; `#[derive(Clone, Debug, Default)] pub(super) struct DepthGlobal {}` with the same; `impl Sim { pub fn enable_depth(&mut self); #[must_use] pub const fn is_depth(&self) -> bool /* self.earthfront && self.depth */ }`.
  - Hash: in the entity loop, right after the `if self.earthfront { ... }` block, `if self.earthfront && self.depth { e.dp.hash_into(&mut h); }`; after the global Earthfront block, `if self.earthfront && self.depth { h.write_u64(0x4445_5054_48); self.dg.hash_into(&mut h); }`.
  - In `scenario.rs`: `impl Scenario { #[must_use] pub fn host_commands(self, sim: &Sim) -> Vec<Command> }` producing exactly what the bridge builds today: human AI while `sim.surveying()`, alien AI once `sim.waves_survived() > 0`, then `self.scripted_commands(sim)`. `#[cfg(test)] pub(crate) fn kestrel_reach_classic(seed: u64) -> Sim` (Kestrel without `enable_depth`, for the pin).
  - Bridge: `let mut commands = scenario.host_commands(&sim); commands.extend(player_commands);` (same order as today).

- [ ] **Step 1: Measure the pre-change pins at HEAD before editing.** Add this temporary test to `scenario.rs` tests, run it, copy the two printed numbers, then delete the temporary test:

```rust
#[test]
fn print_pins() {
    let mut s = survival(7);
    for _ in 0..3000 { let c = Scenario::Survival.host_commands_today(&s); s.step(&c); }
    std::eprintln!("SURVIVAL_PIN {}", s.state_hash());
    let mut k = kestrel_reach(3);
    for _ in 0..6000 { let c = kestrel_shell_commands(&k); k.step(&c); }
    std::eprintln!("KESTREL_CLASSIC_PIN {}", k.state_hash());
}
```

(`host_commands_today` is the inline equivalent: `if s.surveying() { s.ai_commands(PlayerId(0)) } else { Vec::new() }` plus the alien and scripted commands exactly as `godot-bridge.rs:1410-1424` builds them.) Run: `cargo test -p rts-core --offline print_pins -- --nocapture`.

- [ ] **Step 2: Write the failing tests** (in `depth.rs` `#[cfg(test)] mod tests`)

```rust
const SURVIVAL_PIN: u64 = /* value printed in Step 1 */;
const KESTREL_CLASSIC_PIN: u64 = /* value printed in Step 1 */;

#[test]
fn depth_is_only_enabled_by_kestrel() {
    assert!(kestrel_reach(3).is_depth());
    assert!(!survival(3).is_depth());
    assert!(!lane_defense(3).is_depth());
    assert!(!kestrel_reach_classic(3).is_depth());
}

#[test]
fn survival_and_classic_kestrel_hashes_are_pinned_across_depth() {
    let mut s = survival(7);
    for _ in 0..3000 { let c = Scenario::Survival.host_commands(&s); s.step(&c); }
    assert_eq!(s.state_hash(), SURVIVAL_PIN);
    let mut k = kestrel_reach_classic(3);
    for _ in 0..6000 { let c = Scenario::KestrelReach.host_commands(&k); k.step(&c); }
    assert_eq!(k.state_hash(), KESTREL_CLASSIC_PIN);
}

/// Fixed player script exercising every depth command (later tasks append theirs).
pub(super) fn scripted_player(s: &Sim) -> Vec<Command> {
    let mut out = Vec::new();
    if s.tick() == 600 {
        for v in s.views().into_iter().filter(|v| v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(UnitKind::Infantry))) {
            out.push(Command::AttackMove { owner: PlayerId(0), unit: v.id, target: hex::center(20, 10) });
        }
    }
    out
}

#[test]
fn same_inputs_twice_give_the_same_depth_hash_and_replay() {
    let run = || {
        let mut s = kestrel_reach(11);
        let mut log = Vec::new();
        for _ in 0..5000 {
            let mut c = Scenario::KestrelReach.host_commands(&s);
            c.extend(scripted_player(&s));
            s.step(&c);
            log.push(c);
        }
        (s.state_hash(), log)
    };
    let (a, log) = run();
    let (b, _) = run();
    assert_eq!(a, b);
    let mut r = kestrel_reach(11);
    for c in &log { r.step(c); }
    assert_eq!(r.state_hash(), a);
}
```

Also a bridge test: `host_commands` for Survival at tick 0 equals the inline list the loop used to build (`sim.ai_commands(PlayerId(0))` while surveying).

- [ ] **Step 3: Run to verify failure** `cargo test -p rts-core --offline depth`. Expected: compile errors (`is_depth`, `host_commands`, `kestrel_reach_classic` missing).
- [ ] **Step 4: Implement** as in Interfaces. `kestrel_shell_commands` becomes `Scenario::KestrelReach.host_commands(s)`.
- [ ] **Step 5: Run all gates.** Expected: golden unchanged, both pins green, Kestrel outcome test unchanged in behaviour (depth has no behaviour yet; only Kestrel's hash differs, by the depth marker). Re-derive any bridge test that pins a Kestrel hash or snapshot fingerprint and explain it; regenerate the Godot fixtures (the snapshot `hash` changes) and explain.
- [ ] **Step 6: Commit**, message "Depth flag (Kestrel only), depth.rs, hash plumbing, Scenario::host_commands, Survival and classic Kestrel pins".

---

### Task 11: Auto-acquire, leash and under-attack response

Size L.

**Files:**
- Modify: `crates/core/src/game/depth.rs`, `crates/core/src/game/sim.rs` (`step` `:2417-2445`: call `run_depth_acquire()` before `run_movement` when depth; `run_combat` damage loop `:4441-4495`: collect `(victim, attacker)` and call `depth_respond_to_hits` at the end when depth; `Command::Move`/`AttackMove` arms `:2833-2860` clear the anchor and engagement under depth; `clear_dead` `:4511` drops dangling `engaged` ids), `crates/core/src/game/scenario.rs` (outcome test comment and numbers)

**Interfaces:**
- Consumes: `attack_of(&self.balance, kind)`, `is_air_of`, `COMBAT_CELL`, `order_unit_to(idx, target, attack_move)`, `DepthUnit::hash_into`.
- Produces:
  - Consts in `depth.rs`: `ACQUIRE_BONUS: Fixed = Fixed::from_int(3)`, `LEASH: Fixed = Fixed::from_int(6)`, `ASSIST_RADIUS: Fixed = Fixed::from_int(6)`, `REPATH_PERIOD: u64 = 20`.
  - `DepthUnit` fields appended: `anchor: Option<Vec2>`, `engaged: Option<EntityId>` (hashed in that order: tag 0/1 then bits).
  - `fn run_depth_acquire(&mut self)`: ascending index; for each alive, constructed, unstunned, armed, non-Harvester unit with ammunition: an idle unit (no `move_target`) records `anchor = pos` if none; if `engaged` is dead, untargetable or its distance from `anchor` exceeds `LEASH`, clear it and `order_unit_to(anchor, false)`; otherwise, with no engagement, find the nearest targetable enemy within `range + ACQUIRE_BONUS` (same targetability test as `run_combat`) and engage it (`order_unit_to(target_pos, true)`, re-issued every `REPATH_PERIOD` ticks while the target moves). An attack-moving unit with an enemy inside the acquisition ring but outside weapon range steps straight toward it when the straight step lands on a passable tile, otherwise keeps its path.
  - `fn depth_respond_to_hits(&mut self, hits: &[(usize, usize)])`: for each hit (victim, attacker) in order, idle friendly units within `ASSIST_RADIUS` of the victim whose weapon can hit the attacker engage it (same leash). Applies to every owner, so the alien base and waves respond too.

- [ ] **Step 1: Failing tests** (in `depth.rs`; helper `depth_arena()` builds `Sim::new(Map::new(40, 40), 1, Fixed::ZERO)`, `enable_earthfront()`, `enable_depth()`)

```rust
#[test]
fn idle_rifle_engages_an_enemy_inside_its_acquisition_ring() {
    let mut s = depth_arena();
    let r = UnitKind::Infantry.stats().attack.range;
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    let b = s.add_unit(P1, UnitKind::Infantry, v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO));
    let hp0 = s.views().iter().find(|x| x.id == b).unwrap().hp;
    for _ in 0..120 { s.step(&[]); }
    let hp1 = s.views().iter().find(|x| x.id == b).map_or(Fixed::ZERO, |x| x.hp);
    assert!(hp1 < hp0, "the idle unit never engaged");
    let _ = a;
}

#[test]
fn idle_rifle_ignores_an_enemy_outside_the_ring() {
    let mut s = depth_arena();
    let r = UnitKind::Infantry.stats().attack.range;
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    s.add_unit(P1, UnitKind::Harvester, v(10, 20) + Vec2::new(r + Fixed::from_int(4), Fixed::ZERO));
    for _ in 0..120 { s.step(&[]); }
    assert_eq!(s.position(a), Some(v(10, 20)));
}

#[test]
fn unit_returns_to_anchor_after_target_flees_past_leash() {
    let mut s = depth_arena();
    let r = UnitKind::Infantry.stats().attack.range;
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    let b = s.add_unit(P1, UnitKind::Tank, v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO));
    for _ in 0..30 { s.step(&[]); }
    s.step(&[Command::Move { owner: P1, unit: b, target: v(38, 20) }]);
    for _ in 0..900 { s.step(&[]); }
    let home = s.position(a).unwrap();
    assert!((home - v(10, 20)).length_squared() < Fixed::ONE, "never came back: {home:?}");
}

#[test]
fn idle_units_defend_a_building_under_attack() {
    let mut s = depth_arena();
    s.add_building(P0, BuildingKind::Barracks, 20, 20);
    let bpos = s.views().iter().find(|x| x.owner == P0).unwrap().pos;
    let r = UnitKind::Infantry.stats().attack.range;
    // attacker hits the barracks from the east; the riflemen stand 5 west of the
    // barracks, beyond their own acquisition ring of the attacker
    s.add_unit(P1, UnitKind::Infantry, bpos + Vec2::new(r, Fixed::ZERO));
    let guards: Vec<_> = (0..3).map(|i| s.add_unit(P0, UnitKind::Infantry, bpos + Vec2::new(Fixed::from_int(-5), Fixed::from_int(i)))).collect();
    for _ in 0..300 { s.step(&[]); }
    assert_eq!(s.unit_count(P1), 0, "guards never answered the attack");
    let _ = guards;
}

#[test]
fn a_player_move_clears_the_anchor() {
    let mut s = depth_arena();
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    s.step(&[]);
    s.step(&[Command::Move { owner: P0, unit: a, target: v(14, 20) }]);
    for _ in 0..200 { s.step(&[]); }
    for _ in 0..200 { s.step(&[]); }
    assert!((s.position(a).unwrap() - v(14, 20)).length_squared() < Fixed::ONE, "snapped back to the old anchor");
}
```

Add `scripted_player` lines: none needed (behaviour runs every tick); the determinism test from Task 10 must stay green.

- [ ] **Step 2: Run** `cargo test -p rts-core --offline depth::tests`. Expected: the acquisition, leash and defence tests FAIL.
- [ ] **Step 3: Implement** as in Interfaces (fixed point, ascending index, combat grid for the scan, no rng).
- [ ] **Step 4: Run all gates**; Task 10 pins and golden unchanged. Re-run the Kestrel outcome test and the ignored opening playtest; record old/new ticks (start: 4959 / 13622) in the test comment.
- [ ] **Step 5: Commit**, message "Depth: units acquire within range+3, leash to 6 from their anchor, and defend allies under attack (Kestrel outcome: undefended <old>-><new>, AI <old>-><new>)".

---

### Task 12: Separation and the attack-move halt fix

Size M.

**Files:**
- Modify: `crates/core/src/game/depth.rs`, `crates/core/src/game/sim.rs` (`run_movement` `:4080-4177`: snapshot tuple gains `is_air`; the halt scan `:4115-4130` skips untargetable enemies when depth; `step` calls `run_depth_separation()` after `run_movement` when depth), `crates/core/src/game/scenario.rs` (outcome numbers)

**Interfaces:**
- Consumes: `is_air_of`, `attack_of`, `is_passable_tile`, `hex::from_world`, `COMBAT_CELL`.
- Produces: `SEPARATION: Fixed = Fixed::from_ratio(45, 100)`; `fn run_depth_separation(&mut self)`: bucket living units by the combat grid; for each same-owner pair `i < j` in ascending index with the same layer (ground with ground, air with air) and distance below `SEPARATION`, push each half the overlap apart along their axis (coincident units use the hex direction `j % 6`); a push that would land a ground unit on an impassable tile is skipped for that unit. `#[ignore] fn depth_tick_budget()` bench.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn ten_riflemen_on_one_point_spread_out() {
    let mut s = depth_arena();
    for _ in 0..10 { s.add_unit(P0, UnitKind::Infantry, v(20, 20)); }
    for _ in 0..90 { s.step(&[]); }
    let pos: Vec<Vec2> = s.views().iter().map(|x| x.pos).collect();
    let min_sq = Fixed::from_ratio(40, 100) * Fixed::from_ratio(40, 100);
    for i in 0..pos.len() { for j in i + 1..pos.len() {
        assert!((pos[i] - pos[j]).length_squared() >= min_sq, "{i} {j} still stacked");
    }}
}

#[test]
fn separation_never_pushes_onto_water() {
    let mut s = kestrel_reach(3);
    let ford = hex::center(22, 10);
    for _ in 0..8 { s.add_unit(PlayerId(0), UnitKind::Infantry, ford); }
    for _ in 0..90 { s.step(&[]); }
    for v in s.views() { if matches!(v.kind, EntityKindView::Unit(_)) {
        let (x, y) = hex::from_world(v.pos, 44, 26);
        assert!(s.map().tile(i32::from(x), i32::from(y)).is_some_and(|t| t.passable), "unit on impassable tile at {x},{y}");
    }}
}

#[test]
fn attack_move_does_not_halt_under_an_untargetable_helicopter() {
    let mut s = depth_arena();
    let inf = s.add_unit(P0, UnitKind::Infantry, v(5, 20));
    s.add_unit(P1, UnitKind::Helicopter, v(8, 20));
    s.step(&[Command::AttackMove { owner: P0, unit: inf, target: v(30, 20) }]);
    for _ in 0..600 { s.step(&[]); }
    assert!(s.position(inf).map_or(true, |p| p.x > Fixed::from_int(20)), "halted under the gunship");
}

#[test]
#[ignore = "bench: cargo test --release -p rts-core --offline depth_tick_budget -- --ignored --nocapture"]
fn depth_tick_budget() {
    let mut s = kestrel_reach(3);
    for i in 0..40 { s.add_unit(PlayerId(0), UnitKind::Infantry, hex::center(10, 5 + (i % 15) as u16)); }
    for i in 0..40 { s.add_unit(PlayerId(1), UnitKind::Infantry, hex::center(30, 5 + (i % 15) as u16)); }
    let t = std::time::Instant::now();
    let mut worst = std::time::Duration::ZERO;
    for _ in 0..900 { let c = Scenario::KestrelReach.host_commands(&s); let t0 = std::time::Instant::now(); s.step(&c); worst = worst.max(t0.elapsed()); }
    let mean = t.elapsed() / 900;
    std::eprintln!("depth tick mean {mean:?} worst {worst:?}");
    assert!(mean < std::time::Duration::from_millis(5) && worst < std::time::Duration::from_millis(15));
}
```

(`s.map()` is the existing accessor at `sim.rs:1381`; `Map::tile(x: i32, y: i32) -> Option<Tile>` is at `map.rs:276`.)

- [ ] **Step 2: Run** `cargo test -p rts-core --offline depth::tests`. Expected: the three behaviour tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates; bench** `cargo test --release -p rts-core --offline depth_tick_budget -- --ignored --nocapture` with the printed mean and worst in the report (80 units). Outcome re-baseline with old/new ticks.
- [ ] **Step 5: Commit**, message "Depth: same-owner units spread to 0.45, attack-move only halts for enemies it can shoot (bench: mean <x> ms, worst <y> ms at 80 units)".

---

### Task 13: Stop, Hold, stances and attack-target, end to end

Size L.

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`Command` `:385-580` append four variants; `apply_command` `:2818-2950` arms; `run_combat` target choice `:4337-4357` prefers the forced target; `run_movement` keeps Hold units still; `clear_dead` drops dangling `forced`/`engaged`; re-export `pub use depth::Stance;` beside `:12`), `crates/core/src/game/depth.rs`, `crates/core/src/game/civ/mod.rs` (D1: the four variants join the `u8::MAX` arm only), `crates/core/src/game/scenario.rs` (outcome numbers if moved), `crates/server/src/bin/godot-bridge.rs` (`take_commands` `:1121-1256` four arms; entity objects gain `"stance":"<name>"` only when `sim.is_depth()`), `godot3d/scripts/ui/keybinds.gd` (`STOP := KEY_S`, `HOLD := KEY_D`, `STANCE := KEY_Z` in `KESTREL_ONLY`), `godot3d/scripts/earthfront_3d.gd` (key handling, right-click on an enemy sends `target`), `godot3d/scripts/ui/sections/army_orders.gd` (Stop, Hold, Stance buttons), `godot3d/scripts/ui/live_adapter.gd` (stance chip text), `godot3d/tests/test_keybinds.gd`, `godot3d/tests/test_section_army_orders.gd`, new `godot3d/tests/test_orders_protocol.gd`, Godot fixtures (regenerate)

**Interfaces:**
- Consumes: Task 11 `anchor`, `engaged`, `run_depth_acquire`.
- Produces:
  - `#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)] pub enum Stance { #[default] Aggressive, Defensive, Hold }` with `pub const fn name(self) -> &'static str` ("aggressive", "defensive", "hold"), `pub fn from_name(s: &str) -> Option<Self>`, `pub const fn tag(self) -> u64`.
  - `Command::Stop { owner: PlayerId, unit: EntityId }`, `Command::HoldPosition { owner: PlayerId, unit: EntityId }`, `Command::SetStance { owner: PlayerId, unit: EntityId, stance: Stance }`, `Command::AttackTarget { owner: PlayerId, unit: EntityId, target: EntityId }`, appended in this order; every arm returns immediately unless `self.is_depth()`.
  - `DepthUnit` appended fields: `stance: Stance`, `forced: Option<EntityId>`.
  - Semantics: Stop clears `move_target`, `path`, `attack_move`, `engaged`, `forced` and sets `anchor = pos`. HoldPosition = Stop + `stance = Hold`. Defensive: no acquisition move; responds only through `depth_respond_to_hits` when it or an ally within 6 is hit, leash 3 instead of 6. Hold: never moves on its own (acquire and respond only pick targets already in weapon range), still obeys player Move/AttackMove and holds where it arrives. AttackTarget: valid when the target is alive, hostile and targetable by the unit's weapon; the unit paths toward it until in range and `run_combat` fires only at it while it lives; cleared when it dies.
  - `pub fn stance_of(&self, id: EntityId) -> Option<Stance>` (None when depth off).
  - Bridge lines: `stop,<id>`, `hold,<id>`, `stance,<id>,<name>`, `target,<id>,<eid>`.

- [ ] **Step 1: Failing tests** (core, bridge, Godot)

```rust
#[test]
fn stop_clears_orders_and_hold_never_moves() {
    let mut s = depth_arena();
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    s.step(&[Command::Move { owner: P0, unit: a, target: v(30, 20) }]);
    for _ in 0..20 { s.step(&[]); }
    s.step(&[Command::Stop { owner: P0, unit: a }]);
    let here = s.position(a).unwrap();
    for _ in 0..60 { s.step(&[]); }
    assert_eq!(s.position(a), Some(here));
    s.step(&[Command::HoldPosition { owner: P0, unit: a }]);
    let r = UnitKind::Infantry.stats().attack.range;
    s.add_unit(P1, UnitKind::Infantry, here + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO));
    for _ in 0..200 { s.step(&[]); }
    assert_eq!(s.position(a), Some(here), "hold moved");
    assert_eq!(s.stance_of(a), Some(Stance::Hold));
}

#[test]
fn attack_target_focuses_the_chosen_enemy() {
    let mut s = depth_arena();
    let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
    let near = s.add_unit(P1, UnitKind::Infantry, v(12, 20));
    let far = s.add_unit(P1, UnitKind::Infantry, v(13, 21));
    s.step(&[Command::AttackTarget { owner: P0, unit: a, target: far }]);
    for _ in 0..300 { if s.position(far).is_none() { break; } s.step(&[]); }
    assert!(s.position(far).is_none(), "forced target survived");
    assert!(s.position(near).is_some(), "fired at the nearer enemy first");
}

#[test]
fn forced_target_is_dropped_when_its_slot_is_reused() {
    let mut s = depth_arena();
    let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
    let t = s.add_unit(P1, UnitKind::Infantry, v(12, 20));
    s.step(&[Command::AttackTarget { owner: P0, unit: a, target: t }]);
    while s.position(t).is_some() { s.step(&[]); }
    let ally = s.add_unit(P0, UnitKind::Infantry, v(25, 25)); // reuses the freed slot
    assert_eq!(ally, t);
    let hp = s.views().iter().find(|x| x.id == ally).unwrap().hp;
    for _ in 0..200 { s.step(&[]); }
    assert_eq!(s.views().iter().find(|x| x.id == ally).unwrap().hp, hp);
    assert!((s.position(a).unwrap() - v(25, 25)).length_squared() > Fixed::from_int(4), "chased the recycled slot");
}

#[test]
fn defensive_ignores_a_passer_by_but_answers_a_hit() { /* passer-by outside range: no move; then attacked: responds, stays within 3 of anchor */ }

#[test]
fn depth_commands_are_ignored_without_depth() {
    let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
    s.enable_earthfront();
    let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
    s.step(&[Command::Move { owner: P0, unit: a, target: v(30, 20) }]);
    s.step(&[Command::Stop { owner: P0, unit: a }]);
    for _ in 0..60 { s.step(&[]); }
    assert!(s.position(a).unwrap().x > Fixed::from_int(11));
}
```

(Write `defensive_ignores_a_passer_by_but_answers_a_hit` fully: P1 Infantry walks past at range + 2 with a Move order, P0 Defensive must not leave its tile; then a P1 Infantry attacks it, P0 must damage it and end within 3 of its anchor.)

Bridge tests: the four lines parse to the four commands; a malformed id is dropped; Kestrel entity objects carry `"stance":"aggressive"`; `snapshot_json(&Scenario::Survival.build(2026))` contains no `"stance"` (the byte-identical test stays green unedited). Godot tests: S, D, Z write `stop`, `hold`, `stance` packets for the selection on Kestrel and do nothing on Survival; right-clicking an enemy entity writes `target,<id>,<eid>`; the army orders section shows Stop, Hold and a stance chip. Append `Stop`, `SetStance` and `AttackTarget` uses to `scripted_player` at ticks 900 to 1200.

- [ ] **Step 2: Run** core, bridge and Godot filters. Expected: FAIL (missing variants, missing lines, missing keys).
- [ ] **Step 3: Implement** core, then bridge, then client.
- [ ] **Step 4: Gates**; regenerate fixtures; capture the HUD with a stance chip (intended board change, shown before/after); pins and golden green; outcome numbers re-recorded if they moved.
- [ ] **Step 5: Commit** in up to three commits (core, bridge, client), messages "Depth commands: Stop, HoldPosition, SetStance, AttackTarget", "Bridge: stop/hold/stance/target lines and the Kestrel stance key", "Kestrel orders: S stop, D hold, Z stance, right-click attacks a target, stance chip".

---

### Task 14: Shift-queued waypoints

Size M. (The spec's named deferral candidate: if it cannot land within its budget, it becomes a follow-up and the spec's P2 section records the deferral; nothing else depends on it.)

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`Command` append `QueueMove`; `run_movement` arrival `:4160-4166` pops the next leg under depth; Move/AttackMove/Stop clear the queue), `crates/core/src/game/depth.rs`, `crates/core/src/game/civ/mod.rs` (D1 arm), `crates/server/src/bin/godot-bridge.rs` (`qmove`, `qattack` lines; entity `"queue":N` only when depth), `godot3d/scripts/earthfront_3d.gd` (shift+right-click and shift+A-click append; waypoint markers), `godot3d/tests/test_orders_protocol.gd`

**Interfaces:**
- Consumes: Task 13 commands and `DepthUnit`.
- Produces: `Command::QueueMove { owner: PlayerId, unit: EntityId, target: Vec2, attack_move: bool }` (appended after `AttackTarget`); `DepthUnit.queue: Vec<(Vec2, bool)>` appended (hashed as length then each leg), cap `QUEUE_CAP: usize = 8` (a ninth leg is dropped); a QueueMove on an idle unit starts immediately; `pub fn queue_len(&self, id: EntityId) -> u32`.

- [ ] **Step 1: Failing tests**: three legs visited in order (positions sampled when each arrival happens); the ninth leg is ignored; a plain Move clears the queue; an attack-move leg halts for an enemy and resumes the queue after the fight; bridge lines parse; client shift+right-click writes `qmove`; append a QueueMove to `scripted_player`.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates** (fixtures regenerated for the `queue` key, pins, golden).
- [ ] **Step 5: Commit**, message "Depth: shift-queued waypoints, up to 8 legs".

---

### Task 15: Helicopter counter, decided by measured duels

Size M.

**Files:**
- Modify: `crates/core/src/game/depth.rs` (profile override and the duel harness), `crates/core/src/game/sim.rs` (`run_combat` reads `self.depth_attack_profile(e.kind, profile)` and scales damage against air by `depth_air_damage_pct` when depth; the same override feeds the halt scan from Task 12), `crates/core/src/game/scenario.rs` (outcome numbers)

**Interfaces:**
- Consumes: `attack_of`, `damage_multiplier`, the attack-move duel method of the audit (both sides attack-move through each other, `Map::new(40, 40)`, 2400-tick cap).
- Produces: `pub(super) fn depth_attack_profile(&self, kind: Kind, base: AttackProfile) -> AttackProfile` (under depth, `Kind::Unit(UnitKind::AntiArmor)` gains `targets_air = true`; fallback variant: `Infantry` instead); `pub(super) const fn depth_air_damage_pct(kind: Kind) -> i64` (AntiArmor 50, fallback Infantry 25, else 100); test helper `struct Duel { a_left: usize, b_left: usize, a_value_lost: i64, b_value_lost: i64, ticks: u64 }` and `fn duel(a: &[(UnitKind, usize)], b: &[(UnitKind, usize)], depth: bool) -> Duel`.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn anti_armour_teams_now_trade_with_gunships() {
    let d = duel(&[(UnitKind::Helicopter, 4)], &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)], true);
    assert!(d.a_left < 4, "no helicopter losses: {d:?}");
    let s = kestrel_reach(1);
    let at_cost = 5 * s.unit_cost(UnitKind::AntiArmor).to_int_floor() + s.unit_cost(UnitKind::Infantry).to_int_floor();
    assert!(d.b_left > 0 || d.a_value_lost * 100 >= at_cost * 60, "{d:?}");
}

#[test]
fn infantry_still_cannot_touch_gunships() {
    let with = duel(&[(UnitKind::Helicopter, 4)], &[(UnitKind::Infantry, 12)], true);
    let without = duel(&[(UnitKind::Helicopter, 4)], &[(UnitKind::Infantry, 12)], false);
    assert_eq!((with.a_left, with.b_left), (without.a_left, without.b_left));
}

#[test]
fn the_ground_triangle_holds_within_one_survivor_of_the_audit() {
    // audit table (gameplay-audit.md section 2): winner side and survivors
    let cases: [(&[(UnitKind, usize)], &[(UnitKind, usize)], bool, usize); 4] = [
        (&[(UnitKind::Tank, 3)], &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)], false, 4),
        (&[(UnitKind::Infantry, 12)], &[(UnitKind::AntiArmor, 5), (UnitKind::Infantry, 1)], true, 12),
        (&[(UnitKind::Tank, 6)], &[(UnitKind::AntiArmor, 11)], false, 7),
        (&[(UnitKind::Infantry, 24)], &[(UnitKind::AntiArmor, 11)], true, 21),
    ];
    for (a, b, a_wins, left) in cases {
        let d = duel(a, b, true);
        let (won, n) = if a_wins { (d.b_left == 0, d.a_left) } else { (d.a_left == 0, d.b_left) };
        assert!(won && n.abs_diff(left) <= 1, "{a:?} vs {b:?}: {d:?}");
    }
}
```

(Costs come from `Sim::unit_cost` at `sim.rs:1616`, which reads `self.balance.unit(kind).money_cost`; `duel` loads the same default balance.)

- [ ] **Step 2: Run** to verify the first test FAILS (0 helicopter losses today).
- [ ] **Step 3: Implement** AntiArmor at 50% vs air. If `the_ground_triangle_holds...` or the first test cannot both pass, switch to the fallback (Infantry at 25%, AntiArmor unchanged), change the first test to the infantry form, and record both measured tables.
- [ ] **Step 4: Gates**; print the full duel table (all ten audit fights, depth on) in the report; outcome re-baseline with old/new ticks.
- [ ] **Step 5: Commit**, message "Depth: AntiArmor hits air at 50% (duel table in the message), outcome <old>-><new>".

---

### Task 16: Walls delay instead of win: breach pathing and the siege threshold

Size L.

**Files:**
- Modify: `crates/core/src/game/path.rs` (new `find_path_weighted`; `find_path` untouched), `crates/core/src/game/sim.rs` (`order_unit_to` `:2554-2595`: under depth, when `find_path` fails for a unit owned by the waves' attacker, try the breach path), `crates/core/src/game/depth.rs`, `crates/core/src/game/earthfront.rs` (`run_earthfront_waves` `:937-952` threshold `> 5` becomes `>= 3` under depth; composition `:977-990` leads siege waves with tanks under depth), `crates/core/src/game/scenario.rs` (outcome test comment and numbers, final for P2)

**Interfaces:**
- Consumes: `find_path`'s A* (`path.rs:69-127`), `Tile::BLOCKED` occupancy (`add_building` `:2335`), Task 13 `forced`.
- Produces:
  - `pub fn find_path_weighted(map: &Map, start: (u16, u16), goal: (u16, u16), extra: &dyn Fn(u16, u16) -> Option<i64>) -> Option<Vec<(u16, u16)>>`: same A* and tie-break as `find_path`, except an impassable tile is enterable at the cost `extra(x, y)` returns (None = blocked).
  - `BREACH_WALL_COST: i64 = 60`, `BREACH_BUILDING_COST: i64 = 120`; `DepthUnit.breach_tried: bool` appended (reset whenever the unit gets a new order target).
  - Breach: walls owned by the defender cost `BREACH_WALL_COST`, other defender buildings `BREACH_BUILDING_COST`; the unit walks the path up to the first blocked tile and `forced` = the building on it; when it dies the unit re-paths normally. One breach search per unit per order target.
  - Siege lead: under depth and doctrine 2, the first `ceil(budget / 4)` units of the wave are Tanks (Capital at `i == 0` when `w >= 3` is kept).

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn weighted_path_crosses_a_wall_only_when_needed() {
    let mut m = Map::new(10, 3);
    for y in 0..3 { m.set_tile(5, y, Tile::BLOCKED); }
    assert!(find_path(&m, (1, 1), (8, 1)).is_none());
    let p = find_path_weighted(&m, (1, 1), (8, 1), &|x, _| (x == 5).then_some(60)).unwrap();
    assert!(p.iter().any(|&(x, _)| x == 5));
    let open = Map::new(10, 3);
    assert_eq!(find_path_weighted(&open, (1, 1), (8, 1), &|_, _| None), find_path(&open, (1, 1), (8, 1)));
}

#[test]
fn four_wall_ford_seal_is_breached_by_wave_two() {
    let seal = [(21u16, 9u16), (21, 10), (22, 11), (23, 11)];
    let run = |mut s: Sim| {
        for (x, y) in seal { s.add_building(PlayerId(0), BuildingKind::Wall, x, y); }
        assert!(find_path(s.map(), kestrel::HOLDFAST, kestrel::HOME_CC).is_none(), "seal is not a seal");
        let mut breached_at = None;
        while s.winner().is_none() && s.waves_survived() < 2 || s.tick() < 4500 + 5400 + 1800 {
            let c = Scenario::KestrelReach.host_commands(&s);
            s.step(&c);
            let walls = s.views().iter().filter(|v| v.owner == PlayerId(0) && v.kind == EntityKindView::Building(BuildingKind::Wall)).count();
            if walls < seal.len() && breached_at.is_none() { breached_at = Some(s.tick()); }
            if s.winner().is_some() { break; }
        }
        (breached_at, s)
    };
    let (breach, s) = run(kestrel_reach(3));
    assert!(breach.is_some(), "no wall fell by wave two");
    let base_hit = s.winner() == Some(PlayerId(1)) || s.views().iter().any(|v| v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Building(k) if k != BuildingKind::Wall) && v.hp < v.max_hp);
    assert!(base_hit, "the base was never attacked");
    let (classic, _) = run(kestrel_reach_classic(3));
    assert!(classic.is_none(), "classic Kestrel documents the old exploit");
}

#[test]
fn three_walls_call_a_siege_led_by_tanks() { /* 3 human walls before the doctrine lock (tick first_delay - 1350): next wave is doctrine 2 and its first ceil(budget/4) spawned units are Tanks */ }
```

(Write `three_walls_call_a_siege_led_by_tanks` fully: place 3 walls at tick 0 on authored grass near the CC, step `kestrel_reach(3)` with host commands to tick 4500, read `incoming_doctrine()` = "Siege against fortifications" and count the first spawned alien units by kind.)

- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.** Keep `find_path` byte-identical (the golden and every legacy path test guard it).
- [ ] **Step 4: Gates**; outcome re-baseline (P2 final): undefended falls at <new>, AI <result> at <new>, old values 4959 / 13622 recorded.
- [ ] **Step 5: Commit**, message "Depth: blocked waves breach walls, siege at 3 walls led by tanks; Kestrel outcome <old>-><new>".
- [ ] **Step 6: Phase P2 end check:** `git diff --stat 67e6355..HEAD -- crates/` lists only the P2 allow-list; golden, pins, Survival snapshot test green; full gates; ledger line with the P2 outcome table.

---

## P3. Shape of a match

### Task 17: Enable abilities, Capital at era 1 and Upgrades under depth

Size L.

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`apply_use_ability` early return `:3090`; `apply_train` Capital era check `:2688`; `apply_ascend` early return `:3264`; extract the legacy AI ability block `:4663-4745` into `fn ai_ability_casts(&self, player: PlayerId, cmds: &mut Vec<Command>)` called at the same place), `crates/core/src/game/earthfront.rs` (tech unlock match `:510-525`: tech 7 unlocks Capital under depth; `earthfront_ai` calls `ai_ability_casts` and buys upgrades under depth), `crates/core/src/game/depth.rs`, `crates/core/src/game/scenario.rs` (outcome numbers), `crates/server/src/bin/godot-bridge.rs` (`upgrade,<track>` line; Kestrel-only `"depth":{"upgrades":[w,a,v],"upgrade_costs":[...]}` block), `godot3d/scripts/earthfront_3d.gd` (Q works on Kestrel; Upgrades buttons), `godot3d/scripts/ui/live_research.gd` (Upgrades panel), tests

**Interfaces:**
- Consumes: `ability_for`, `ability::def`, `DOC_WEAPONS`/`DOC_ARMOR`/`DOC_VITALITY` (`sim.rs:338-342`), `doctrine_weapon_bonus`.
- Produces: `pub(super) fn depth_ability_allowed(&self, owner: PlayerId, kind: AbilityKind) -> bool` (Barrage needs tech 6 researched, EmpBurst always, NaniteField with the Capital); `pub(super) fn depth_ability_cooldown(&self, owner: PlayerId, base: u32) -> u32` (Task 23 perk hook; base for now); `pub fn upgrade_levels(&self, owner: PlayerId) -> [u16; 3]`; `pub fn upgrade_cost(&self, owner: PlayerId, track: u8) -> Option<Fixed>` (money only: `150 + 100 * level`; None at the cap: 3 levels per track at era 0, 6 at era 1; forge (track 3) always None); `pub(super) fn apply_depth_upgrade(&mut self, owner: PlayerId, track: u8, free: bool)`.

- [ ] **Step 1: Failing tests**: under depth an EMP from a Helicopter stuns a clump and a Barrage is refused before tech 6 and accepted after; the Earthfront legacy guard still refuses abilities on Survival; Capital trains at a VehicleFactory after tech 7 at era 1 and is refused at era 1 on Survival-style Earthfront without depth; one weapons upgrade measurably raises damage (duel: 6 Infantry vs 6 Infantry, the upgraded side wins with at least 2 more survivors); forge refused; level cap per era; legacy Ascend unchanged (golden); AI under depth casts at least one ability in a 20,000-tick Kestrel playtest; bridge `upgrade,0` parses and Survival has no `depth` key.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement** core, bridge, client (Upgrades panel lists weapons, armour, vitality with level and cost; Q casts on Kestrel).
- [ ] **Step 4: Gates**, pins, outcome re-baseline, fixtures; report the ability-use count and an upgrade duel table.
- [ ] **Step 5: Commit** (core, bridge, client), messages starting "Depth enable list:".

---

### Task 18: Economy: escalating refineries and repair over time

Size M.

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`apply_build` cost and `can_afford_building` `:1621` use the depth cost; `apply_repair` `:2763-2792` under depth starts a job; a `run_depth_repairs()` call in `step`), `crates/core/src/game/depth.rs`, `crates/core/src/game/earthfront.rs` (`earthfront_ai` spends surplus above 1500 on upgrades and extra refineries under depth), `crates/core/src/game/scenario.rs`, `crates/server/src/bin/godot-bridge.rs` (`depth.refinery_cost`), `godot3d/scripts/ui/live_adapter.gd` and `godot3d/scripts/ui/feedback_events.gd` (cost lookup prefers `depth.refinery_cost`), tests

**Interfaces:**
- Produces: `pub fn depth_building_cost(&self, owner: PlayerId, kind: BuildingKind) -> Fixed` (Refinery: base + 50 per refinery the owner already has, alive or under construction; else base; equals `building_cost` when depth off); `DepthUnit` appended `repair_ticks: u32`, `repair_cd: u32`; consts `REPAIR_TICKS: u32 = 150`, `REPAIR_COOLDOWN: u32 = 450`, `REPAIR_MIN_COST: i32 = 25`; repair heals `max_hp / 5` spread over `REPAIR_TICKS` and costs `max(money_cost / 10, 25)` up front (the Command Center included).

- [ ] **Step 1: Failing tests**: second refinery costs base + 50, third base + 100, selling one lowers the next price; a repair heals gradually (not at once), costs at least 25 on the CC, cannot restart within 450 ticks; Survival repair unchanged (pin); measured `banked_credits_at_ten_minutes_stay_under_2500`: playtest AI on `kestrel_reach(3)` with host commands, `money(PlayerId(0)) < 2500` at tick 18,000 (print the value; audit-measured today 8,924 with walls).
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement** core, bridge key, client price.
- [ ] **Step 4: Gates**, pins, outcome re-baseline, fixtures; report the money curve every 1800 ticks.
- [ ] **Step 5: Commit**, message "Depth economy: refineries cost +50 each, repair heals over time with a cooldown; banked credits at 10:00 <x>".

---

### Task 19: Wave table, seeded doctrines and an alien AI from tick 0

Size L.

**Files:**
- Modify: `crates/core/src/game/depth.rs`, `crates/core/src/game/earthfront.rs` (`run_earthfront_waves` `:918-1003` calls the depth table under depth; `earthfront_ai` era-0 raids under depth), `crates/core/src/game/sim.rs` (`enable_depth` draws the doctrine order), `crates/core/src/game/scenario.rs` (`Scenario::host_commands` depth branch: alien AI from tick 0; outcome numbers)

**Interfaces:**
- Consumes: `Rng::next_below(bound: u32) -> u32` (`rng.rs:62`), Task 16 siege lead.
- Produces:
  - `DepthGlobal` appended `doctrine_order: [u8; 5]`, `waves_cleared: u32`; `DepthUnit` appended `wave: u16` (1-based wave index, 0 = not a wave unit).
  - `enable_depth` shuffles `[0, 1, 2, 3, 4]` with five `next_below` draws (Fisher-Yates); doctrine for wave `w` = `doctrine_order[w % 5]`, overridden by 2 when the defender has at least 3 walls and by 1 when it has more than 3 tanks.
  - `pub(super) const fn depth_wave_kind(w: u32, i: u32, budget: u32, doctrine: u8) -> UnitKind`, the table: wave 1 (w=0) Infantry; wave 2 Infantry + Tank every 4th; wave 3 adds AntiArmor every 5th; wave 4 first flyers (Helicopter every 7th); waves 5+ follow the doctrine (1 AntiArmor every 3rd, 2 tank lead + Capital at i=0, 3 Helicopter every 4th, 4 fast raid of Infantry + Tank every 3rd, 0 mixed); wave 6 (w=5) elite: Capital at i=0, Tanks at i=1 and 2, then the doctrine; waves after 10 repeat wave 10's mix at the size cap.
  - `pub(super) fn depth_expedition_size(&self, w: u32) -> u32` = `min(6 + 2w, 24) * Difficulty pct / 100 + 2 * operational relays` (pct is 100 until Task 20).
  - `pub fn waves_cleared(&self) -> u32` (a wave counts as cleared when it has spawned and no living unit carries its `wave` tag).
  - Raids: under depth the alien attacker, at era 0 once its supply used is at least 12, sends half its idle combat units (ascending index) on AttackMove at the nearest human structure every 2700 ticks.
  - `host_commands` depth branch: alien AI every tick from tick 0.

- [ ] **Step 1: Failing tests**: `doctrine_order_differs_across_seeds_and_repeats_per_seed` (seeds 1..8 give at least 3 distinct orders; the same seed twice is equal); the table spot checks (wave 4 contains a Helicopter, wave 6 starts Capital, Tank, Tank); `waves_cleared` increments when the last unit of a wave dies; `first_contact_is_not_earlier_than_tick_3000_on_normal` (undefended `kestrel_reach(3)`, reuse `kestrel_hostile_in_range_of_a_structure`); the undefended base still falls; the defended playtest is never overrun before wave 3 or wins; Survival pin unchanged (Survival's host branch untouched).
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**, pins, outcome re-baseline; report the wave-by-wave composition actually spawned for seed 3 (counts per kind) and first contact tick.
- [ ] **Step 5: Commit**, message "Depth waves: ten-wave table with an elite wave 6, seeded doctrine order, alien AI from tick 0".

---

### Task 20: Difficulty and seed, from the title to the sim

Size M.

**Files:**
- Modify: `crates/core/src/game/depth.rs` (`Difficulty`), `crates/core/src/game/sim.rs` (re-export), `crates/core/src/game/scenario.rs` (`MatchOptions`, `kestrel_reach_with`, `Scenario::build_with`), `crates/core/src/game/earthfront.rs` (size pct), `crates/server/src/bin/godot-bridge.rs` (`MatchConfig` gains `seed: u64` default 2026 and `difficulty: Difficulty` default Normal; build with `scenario.build_with(cfg.seed, MatchOptions { difficulty })`; Kestrel `depth` block gains `"difficulty"` and `"seed"`), `godot3d/scripts/match_config.gd`, `godot3d/scripts/ui/sections/map_picker.gd` (difficulty selector, seed field), `godot3d/scripts/ui/live_screens.gd` (debrief shows seed and difficulty), tests

**Interfaces:**
- Produces:
  - `#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)] pub enum Difficulty { Easy, #[default] Normal, Hard }` with `pub const fn start_credits(self) -> i32` (1500, 1200, 1000), `pub const fn first_wave_ticks(self) -> u64` (5400, 4500, 3600), `pub const fn wave_interval_ticks(self) -> u64` (6300, 5400, 4500), `pub const fn wave_size_pct(self) -> u32` (75, 100, 125), `pub const fn name(self) -> &'static str`, `pub fn from_name(s: &str) -> Option<Self>`; `DepthGlobal` appended `difficulty: Difficulty` (hashed as a tag).
  - `#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)] pub struct MatchOptions { pub difficulty: Difficulty }`; `pub fn kestrel_reach_with(seed: u64, opts: MatchOptions) -> Sim` (`kestrel_reach(seed)` = `kestrel_reach_with(seed, MatchOptions::default())`, so Normal equals today's constants); `pub fn build_with(self, seed: u64, opts: MatchOptions) -> Sim` (non-Kestrel scenarios ignore `opts`).
  - Client: `MatchConfig.random_seed() -> int` (RandomNumberGenerator, randomized, 1..2^31-1), the picker fills it fresh on every open; Restart reuses `MatchConfig.current.seed`.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn normal_difficulty_equals_the_plain_builder() {
    assert_eq!(kestrel_reach_with(5, MatchOptions::default()).state_hash(), kestrel_reach(5).state_hash());
}

#[test]
fn each_difficulty_resolves_and_the_playtest_ai_survives_its_floor() {
    for (d, floor) in [(Difficulty::Easy, 3), (Difficulty::Normal, 3), (Difficulty::Hard, 2)] {
        let mut s = kestrel_reach_with(3, MatchOptions { difficulty: d });
        assert_eq!(s.money(PlayerId(0)).to_int_floor(), d.start_credits());
        while s.winner().is_none() && s.tick() < 60_000 { let c = Scenario::KestrelReach.host_commands(&s); s.step(&c); }
        assert_eq!(s.winner(), Some(PlayerId(1)), "{d:?}: undefended base never fell");
        let mut s = kestrel_reach_with(3, MatchOptions { difficulty: d });
        while s.winner().is_none() && s.tick() < 140_000 { let mut c = s.ai_commands(PlayerId(0)); c.extend(Scenario::KestrelReach.host_commands(&s)); s.step(&c); }
        assert!(s.waves_survived() >= floor || s.winner() == Some(PlayerId(0)), "{d:?} overrun after {}", s.waves_survived());
    }
}
```

Plus `ticks_until_next_wave` at tick 0 equals each preset's first wave; size pct applied; bridge `match_config` parses seed and difficulty, malformed seed falls back to 2026; Godot `new_operation_draws_a_fresh_seed_and_restart_reuses_it` (two picker opens give different seeds with overwhelming probability, Restart writes the same seed as the running match).

- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**, pins, fixtures, outcome numbers; report per difficulty: undefended fall tick, playtest waves and result.
- [ ] **Step 5: Commit** (core, bridge, client), messages starting "Difficulty and seed:".

---

### Task 21: Victory gate and the 15 to 25 minute match

Size M.

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`run_combat` damage apply `:4441-4460`: under depth the Core Node takes no damage while gated), `crates/core/src/game/depth.rs`, `crates/core/src/game/scenario.rs` (outcome test re-baselined to the window), `crates/server/src/bin/godot-bridge.rs` (`depth.core_shielded`), `godot3d/scripts/world/kestrel_objectives.gd` (stage 5 detail), `godot3d/scripts/earthfront_3d.gd` (shield ring on the Core Node), tests

**Interfaces:**
- Produces: `pub fn core_node_shielded(&self) -> bool` (depth: the attacker's Command Center is shielded while `alien_relay_count(attacker, true) > 0` or `wave_count < 6`; false without depth); objective text "Destroy both relays and outlast the sixth expedition to expose the Core Node".
- Tuning knobs allowed in this task only: the depth wave size cap, the elite escort counts and the raid period in `depth.rs`; each change recorded with its measured effect.

- [ ] **Step 1: Failing tests**: Core Node HP unchanged under fire while a relay stands; damageable after both relays fall and wave 6 spawned; Survival Core Node unaffected; `playtest_match_ends_inside_15_to_25_minutes` for seeds 3 and 5 on Normal (`resolved_at` in 27,000..=45,000, winner printed); the outcome test asserts the window plus the existing invariants and its comment lists the history (4959 / 13622, then each P2/P3 value, then the window result).
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement**, then tune only the listed knobs until both seeds land in the window.
- [ ] **Step 4: Gates**, fixtures, capture of the shielded Core Node (open it).
- [ ] **Step 5: Commit**, message "Depth victory: Core Node shielded until both relays fall and wave 6 has spawned; playtest matches end at <t3>/<t5> ticks".

---

### Task 22: Score, grade and personal bests

Size M.

**Files:**
- Modify: `crates/core/src/game/depth.rs`, `crates/core/src/game/sim.rs` (`clear_dead` `:4511` credits destroyed and lost value under depth; re-export `DepthScore`), `crates/server/src/bin/godot-bridge.rs` (`depth.score` object), `godot3d/scripts/ui/live_screens.gd` (`debrief_vm` score rows), `godot3d/scripts/ui/debrief.gd`
- Create: `godot3d/scripts/records.gd`, `godot3d/tests/test_records.gd`

**Interfaces:**
- Produces: `DepthGlobal` appended `destroyed: [i64; 2]`, `lost: [i64; 2]` (money value of units and buildings, by owner); `pub struct DepthScore { pub waves_held: u32, pub destroyed: i64, pub lost: i64, pub victory_bonus: i64, pub total: i64, pub grade: char }`; `pub fn depth_score(&self) -> Option<DepthScore>`: `base = waves_cleared * 500 + destroyed_by_human - lost_by_human / 2 + victory_bonus` with `victory_bonus = max(0, 45_000 - tick) / 10` on a human win; `total = max(0, base) * score_pct / 100` with `Difficulty::score_pct` (Easy 75, Normal 100, Hard 150, added here); grade S at 12,000, A 8,000, B 5,000, C 2,500, else D. Client `Records`: `const PATH := "user://records.cfg"`, `static func best(map: String, difficulty: String, path := PATH) -> int`, `static func submit(map: String, difficulty: String, total: int, path := PATH) -> bool` (true when a new best).

- [ ] **Step 1: Failing tests**: score arithmetic on a crafted sim (kill a known set of units, check `destroyed`), grade thresholds, `None` without depth, Hard multiplies by 1.5; Records round trip on a temp path, refuses `res://`, a lower score is not a new best; debrief shows score, grade and best.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**, pins, fixtures, debrief capture; report the playtest score per difficulty.
- [ ] **Step 5: Commit**, message "Depth score and grade, personal bests per map and difficulty in user://records.cfg".
- [ ] **Step 6: Phase P3 end check:** crates diff against the P3 allow-list, golden, pins, full gates, ledger.

---

## P4. Roguelite run mode and verifiable replays

### Task 23: Run mode in the core: twelve waves, seeded perk drafts, depth perks

Size L.

**Files:**
- Modify: `crates/core/src/game/perk.rs` (eight depth perks; `PERK_COUNT` stays 4), `crates/core/src/game/sim.rs` (`ChoosePerk` arm `:2861-2869`: under depth accept only a perk in the current draft; `winner()` `:1990` run victory; `supply_cap` and Earthfront refinery income hooks for Conscription and Logistics under depth), `crates/core/src/game/depth.rs`, `crates/core/src/game/earthfront.rs` (Logistics credit hook in the refinery delivery path), `crates/core/src/game/scenario.rs` (`MatchOptions` gains `run: bool`, `perk_pool: u32`), `crates/server/src/bin/godot-bridge.rs` (`perk,<id>` line; `MatchConfig` gains `run`, `perk_pool`; `depth.run` object `{wave, draft, pool}`)

**Interfaces:**
- Consumes: Task 17 `apply_depth_upgrade`, `depth_ability_cooldown`; Task 18 `depth_building_cost`, repair; Task 19 `waves_cleared`; Task 22 score.
- Produces:
  - `perk.rs`: `FIELD_UPGRADE = 4` (one free level on the lowest of the three upgrade tracks), `RAPID_CYCLE = 5` (ability cooldown x0.75), `REFINERY_DISCOUNT = 6` (refinery escalation removed), `LONG_SIGHT = 7` (turret range +1), `EARLY_TOOLING = 8` (tech 1 completes at once), `HARDENED_WALLS = 9` (walls take one third less damage), `FIELD_REPAIR = 10` (repair cost halved), `CAPITAL_DISCOUNT = 11` (Capital 25% cheaper); `pub const DEPTH_PERK_COUNT: u32 = 12`; `pub const DEFAULT_RUN_POOL: u32 = 0xFF` (perks 0..7); `name`/`description` for 4..11.
  - `MatchOptions { difficulty, run: bool, perk_pool: u32 }` (defaults false, `DEFAULT_RUN_POOL`).
  - `DepthGlobal` appended `run: bool`, `perk_pool: u32`, `draft: Option<[u8; 3]>`, `drafted: u32` (number of drafts offered).
  - On each `waves_cleared` increase in a run with no pending draft: draw 3 distinct perks from the pool not already active with `next_below` (fewer if the pool is exhausted). `pub fn depth_draft(&self) -> Option<[u8; 3]>`. ChoosePerk in depth accepts only a drafted id, applies it, clears the draft. Run victory: human wins when `waves_cleared >= 12`. Run score adds 1000 on a run victory inside `depth_score`.
  - Logistics: +50% Earthfront refinery credits (depth); Conscription: +8 Earthfront supply cap (depth).

- [ ] **Step 1: Failing tests**: draft draws are deterministic per seed and differ across seeds; three distinct ids within the pool; a ChoosePerk outside the draft is ignored; each depth perk's effect measured (one test per perk, e.g. refinery discount: third refinery costs base); Logistics and Conscription now act under depth and still do nothing on Survival (pin); run ends in victory at 12 cleared waves (drive with a `kestrel_reach_with(3, MatchOptions { run: true, .. })` playtest where the human AI drafts the first offered perk each time; assert it reaches the end state or record the wave it fell at); legacy `ChoosePerk` with id 5 on `lane_defense` is still rejected (`perks()` unchanged); bridge `perk,4` parses.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**, pins, golden; report the run playtest (waves reached, drafts, score).
- [ ] **Step 5: Commit**, message "Run mode: twelve waves, seeded three-perk drafts, eight depth perks; Logistics and Conscription reach Earthfront under depth".

---

### Task 24: Shared bridge protocol and replay recording

Size M.

**Files:**
- Create: `crates/server/src/lib.rs` (D2: `pub mod bridge_protocol;`), `crates/server/src/bridge_protocol.rs`
- Modify: `crates/server/src/bin/godot-bridge.rs` (uses `rts_server::bridge_protocol::*`; the parser, `MatchConfig` and their tests move; recording in `main`), `godot3d/scripts/match_config.gd` (writes `replay_dir`)

**Interfaces:**
- Produces in `bridge_protocol`: `pub fn parse_command_line(line: &str) -> Option<Command>` (every arm of today's `take_commands` plus the depth lines, unchanged), `pub fn read_command_lines(path: &Path) -> Vec<String>` (legacy file + sorted packets, as today), `pub struct MatchConfig { pub scenario, pub fog, pub seed, pub difficulty, pub run, pub perk_pool, pub replay_dir: Option<PathBuf> }`, `pub fn parse_match_config(text: &str, fallback: Scenario) -> MatchConfig`, `pub fn balance_hash() -> u64` (FNV over `rts_data::DEFAULT_RON` bytes), `pub struct ReplayHeader { pub version: String, pub scenario: Scenario, pub seed: u64, pub difficulty: Difficulty, pub run: bool, pub perk_pool: u32, pub fog: bool, pub balance: u64 }` with `to_text()` / `parse(text) -> Result<ReplayHeader, String>`, `pub struct ReplayWriter` (`create(dir: &Path, header: &ReplayHeader) -> std::io::Result<Self>`, `tick(&mut self, tick: u64, lines: &[String])`, `finish(&mut self, tick: u64, hash: u64, score: i64)`). File format: line 1 `RPL1`, then `key=value` header lines, a blank line, `T <tick> <raw line>` per player line, last line `END <tick> <hash> <score>`. File name `<unix seconds>_<scenario>_<seed>.rpl`.
- Bridge: opens a writer when the mission starts and `replay_dir` is set; logs the raw player lines of each stepped tick against `sim.tick()` before the step; finishes on winner, restart and exit (Drop flushes an `END` with the current hash).

- [ ] **Step 1: Failing tests**: every existing `take_commands` test passes unchanged against `parse_command_line` + `read_command_lines`; header round trip; a writer produces the exact format; `replay_dir` absent means no file; a header with a `res://` dir is refused (bridge only accepts absolute paths); `balance_hash` is stable across two calls.
- [ ] **Step 2: Run** `cargo test -p rts-server --offline`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the move verbatim, then recording.
- [ ] **Step 4: Gates.**
- [ ] **Step 5: Commit**, message "Bridge protocol shared in rts_server::bridge_protocol; replays recorded to the client's user://replays".

---

### Task 25: verify-run, playback and speed control

Size L.

**Files:**
- Create: `crates/server/src/bin/verify-run.rs`
- Modify: `crates/server/src/bridge_protocol.rs` (`verify`, `ReplayPlayer`, speed parsing), `crates/server/src/bin/godot-bridge.rs` (`--replay <file>` flag and `MatchConfig.replay`; playback ignores client packets; reads `replay_speed.txt`; snapshot `"replay":{"speed":S,"tick":T,"end":E}` only in playback)

**Interfaces:**
- Produces: `pub struct VerifyReport { pub ticks: u64, pub hash: u64, pub expected_hash: u64, pub score: i64, pub expected_score: i64 }` with `pub fn ok(&self) -> bool`; `pub fn verify(text: &str) -> Result<VerifyReport, String>` (rebuilds `header.scenario.build_with(header.seed, MatchOptions { difficulty, run, perk_pool })`, `set_balance(rts_data::load_default())`, refuses a balance hash mismatch, steps `Scenario::host_commands` + the logged lines of each tick up to the END tick); `pub struct ReplayPlayer` (`new(text) -> Result<Self, String>`, `commands_for(tick: u64) -> Vec<Command>`, `end_tick() -> u64`); `pub fn parse_speed(text: &str) -> f32` (0, 0.5, 1, 2, 4, 8; anything else 1). Speed is applied by stepping `n` ticks per 33 ms frame (8x = 8 steps, 0.5x = one step every other frame), so playback never changes the tick sequence. `verify-run <file>` prints `ticks <n> hash <h> expected <e> score <s> expected <x> MATCH|MISMATCH`, exit 0 on match, 1 on mismatch, 2 on a malformed file.

- [ ] **Step 1: Failing tests**

```rust
#[test]
fn recorded_bridge_run_verifies_headless() {
    let dir = tempdir_in_target("verify_round_trip");
    let text = record_test_match(&dir, Scenario::KestrelReach, 77, /* run */ true, 3000);
    let r = verify(&text).unwrap();
    assert!(r.ok(), "{r:?}");
}

#[test]
fn tampered_replay_fails() {
    let dir = tempdir_in_target("verify_tamper");
    let text = record_test_match(&dir, Scenario::KestrelReach, 77, false, 3000);
    let bad = text.replacen("T 600 attack,", "T 601 attack,", 1);
    assert!(!verify(&bad).unwrap().ok());
    let bad_end = text.rsplit_once("END").map(|(a, _)| format!("{a}END 3000 1 0\n")).unwrap();
    assert!(!verify(&bad_end).unwrap().ok());
}

#[test]
fn playback_at_8x_equals_1x() {
    let dir = tempdir_in_target("verify_speed");
    let text = record_test_match(&dir, Scenario::KestrelReach, 9, false, 2000);
    assert_eq!(play_back(&text, 1.0), play_back(&text, 8.0));
    assert_eq!(play_back(&text, 0.5), play_back(&text, 1.0));
}

#[test]
fn verify_reads_pool_from_header_only() {
    let dir = tempdir_in_target("verify_pool");
    let text = record_test_match(&dir, Scenario::KestrelReach, 5, true, 3000);
    // no settings or meta file is consulted: the header pool alone rebuilds the run
    assert!(text.contains("perk_pool="));
    assert!(verify(&text).unwrap().ok());
}
```

`record_test_match` and `play_back` are test helpers in `bridge_protocol` tests that drive the same loop body the bridge uses (`host_commands` + parsed lines, a scripted player that issues `attack`, `stop`, `stance`, `perk` lines), writing through `ReplayWriter`; `tempdir_in_target` creates a folder under `target/` and removes it at the end. Also: `verify-run` exits 2 on a file without `RPL1`.

- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement** and `cargo run -p rts-server --bin verify-run --offline -- <file>` on one recorded file from a real bridge session on the private Xvfb (`launch_ui.py --software --display :94`), output in the report.
- [ ] **Step 4: Gates.**
- [ ] **Step 5: Commit**, message "verify-run re-simulates a replay headless; bridge --replay playback at 0.5x to 8x".

---

### Task 26: Run mode and replays in the client

Size L.

**Files:**
- Create: `godot3d/scripts/ui/sections/perk_draft.gd`, `godot3d/scripts/ui/sections/replay_list.gd`, `godot3d/tests/test_perk_draft.gd`, `godot3d/tests/test_replay_viewer.gd`
- Modify: `godot3d/scripts/match_config.gd` (`mode`, `perk_pool`, `daily_seed()`, `replay`), `godot3d/scripts/ui/sections/map_picker.gd` (Operation / Run toggle, Daily seed button), `godot3d/scripts/ui/live_screens.gd` (Replays title entry, run rows on the debrief), `godot3d/scripts/ui/game_ui.gd`, `godot3d/scripts/earthfront_3d.gd` (draft pause via `pause.flag`, `perk,<id>` packet, replay mode input lock, speed buttons writing `replay_speed.txt`), `godot3d/scripts/ui/settings.gd` (`run/perk_pool`, unlock on reaching wave 6)

**Interfaces:**
- Consumes: snapshot `depth.run` (`wave`, `draft`, `pool`) and `replay` keys; `Settings.get_value/set_value`.
- Produces: `MatchConfig.daily_seed(unix_time: int) -> int` (UTC `YYYYMMDD`, e.g. 20261007); `PerkDraft.build(layer, vm, emit)` (three cards with name and description from a `PERK_TEXT` table that mirrors `perk.rs`); `Settings` key `run/perk_pool` (int bitmask, default 0xFF, one more depth perk bit per run reaching wave 6, capped at 0xFFF); replay viewer: when the snapshot has `replay`, world input is ignored except camera and the speed bar (0.5x, 1x, 2x, 4x, 8x, pause).

- [ ] **Step 1: Failing tests**: `daily_seed_is_the_utc_date` (a fixed unix time near midnight UTC maps to the UTC date, not local); a snapshot with a draft pauses (writes `pause.flag` in a temp runtime dir) and choosing a card writes `perk,<id>` and removes the flag; replay mode drops a right-click order (no packet) and the speed bar writes `replay_speed.txt`; the pool unlock adds exactly one bit after a run whose snapshot reached wave 6 and never exceeds 0xFFF; the Replays list reads only `user://replays` (temp override in the test).
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**, captures of the draft and the replay viewer (open them); one scripted Xvfb session: start a daily run, take one draft, quit, verify the produced replay with `verify-run` (report output).
- [ ] **Step 5: Commit**, message "Client: run mode with perk drafts and daily seed, replay list and viewer".
- [ ] **Step 6: Phase P4 end check:** crates diff against the P4 allow-list, golden, pins, full gates, ledger.

---

## P5. Ship-readiness

### Task 27: The client launches its own bridge under user://runtime

Size M.

**Files:**
- Create: `godot3d/scripts/bridge_launcher.gd`, `godot3d/tests/test_bridge_launcher.gd`, `godot3d/tests/fixtures/stub_bridge.sh`
- Modify: `crates/server/src/bin/godot-bridge.rs` (`--runtime-dir <dir>` flag: output becomes `<dir>/snapshot.json`; giving both it and a positional output is an error), `godot3d/scripts/earthfront_3d.gd` (`runtime_directory` resolution at `:164` and `:230-232`; start, stop and crash detection), `run-3d.sh` (passes `--runtime-dir "$GAME_ROOT/godot3d/runtime"` to the bridge and `-- --runtime-dir=...` to Godot)

**Interfaces:**
- Produces: `BridgeLauncher` (static helpers + small node): `static func binary_path(os_name: String, exe_dir: String) -> String` (`godot-bridge` on Linux, `godot-bridge.exe` on Windows, next to the executable), `static func runtime_dir() -> String` (`ProjectSettings.globalize_path("user://runtime")`), `static func should_spawn(user_args: PackedStringArray) -> bool` (false when `--runtime-dir=` is passed: dev and QA keep their external bridge), `func start(binary: String, dir: String) -> int` (`OS.create_process(binary, ["--runtime-dir", dir])`), `func stop() -> void` (kills on `NOTIFICATION_WM_CLOSE_REQUEST` and `_exit_tree`), `func alive() -> bool` (`OS.is_process_running(pid)`, polled once a second; a dead bridge shows "Simulation core stopped" with a Restart button).

- [ ] **Step 1: Failing tests**: bridge flag parse (`--runtime-dir /x` gives `/x/snapshot.json`, both forms together error); launcher picks the right binary name per OS; `should_spawn` false with `--runtime-dir=`; with `stub_bridge.sh` (writes a tick-0 snapshot into the given dir, then sleeps) the launcher starts it, `alive()` is true, `stop()` ends it; killing the stub flips `alive()` and raises the stopped state; the runtime dir is under `user://`, never `res://`.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Gates**; `./run-3d.sh` path checked only by reading the script and a dry Xvfb launch through `launch_ui.py` (never on the user's display).
- [ ] **Step 5: Commit**, message "Client spawns and supervises its bridge under user://runtime; bridge --runtime-dir".

---

### Task 28: Export presets, version, packaging and the itch checklist

Size M.

**Files:**
- Create: `godot3d/export_presets.cfg` (Linux/X11 x86_64, Windows Desktop x86_64), `tools/release/package.sh`, `tools/release/test_package.py`, `docs/release/itch-checklist.md`
- Modify: `godot3d/project.godot` (`config/version="0.2.0"`), `Cargo.toml` (`[workspace.package] version = "0.2.0"`), `crates/server/Cargo.toml` (D4: `version.workspace = true`), `Cargo.lock`, `crates/server/src/bin/godot-bridge.rs` (`--version` prints `env!("CARGO_PKG_VERSION")`), `godot3d/scripts/ui/live_screens.gd` (`footer_right` = "v" + version), `godot3d/tests/test_title.gd`

**Interfaces:**
- Produces: `tools/release/package.sh [linux|windows|all]`: builds `target/release/godot-bridge`, exports with `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --export-release "Linux" <out>/ascension.x86_64`, copies the bridge beside it, writes `<out>/VERSION`, tars to `build/ascension-<version>-linux-x86_64.tar.gz`; exits non-zero with a clear message when export templates for 4.7.2 are missing (`~/.local/share/godot/export_templates/4.7.2.stable/`) or, for Windows, when the `x86_64-pc-windows-gnu` target or mingw linker is missing (both absent on this machine at planning time: say so in the report, do not install system packages).

- [ ] **Step 1: Failing tests**: `test_package.py` checks the presets file has both presets with `x86_64`, the project version equals the Cargo workspace version, the script refuses to run without templates (run it with `HOME` pointed at an empty temp dir and expect the message); Godot `test_title.gd`: footer shows "v0.2.0"; bridge `--version` prints `0.2.0`.
- [ ] **Step 2: Run** to verify failure.
- [ ] **Step 3: Implement**, then the exported Linux smoke run only if templates exist: `XDG_DATA_HOME=$SCRATCH/export-smoke/xdg` (redirects `user://`), private Xvfb `:94`, `--audio-driver Dummy`, run 20 s, assert the launcher-spawned bridge wrote `$SCRATCH/export-smoke/xdg/godot/app_userdata/<name>/runtime/snapshot.json`, kill both. If templates are missing, the report states the smoke run was not possible and why.
- [ ] **Step 4: Gates.** itch checklist covers: page copy, screenshots from the capture tool, butler commands (documented, not run), the Windows test the user must do, the license decision (open decision 5: no LICENSE file until the user decides).
- [ ] **Step 5: Commit**, message "Release: export presets, v0.2.0 shown on the title, packaging script, itch checklist".
- [ ] **Step 6: Phase P5 end check:** crates diff (only `godot-bridge.rs` and `crates/server/Cargo.toml` added in P5), full gates, ledger.

---

## P6. Needs the user (documented, not blocking)

### Task 29: Listening pass and GPU frame-time tools for the user

Size S.

**Files:**
- Create: `tools/audio/listen_pass.py`, `tools/audio/test_listen_pass.py`, `tools/perf/gpu_frametime.sh`, `tools/perf/test_gpu_frametime.py`

**Interfaces:**
- Produces: `listen_pass.py` plays every manifest id with its category label only after an interactive "type yes" confirmation; `main(argv, stdin, player)` returns 2 and plays nothing when `stdin.isatty()` is false. `gpu_frametime.sh` measures idle, combat and zoomed-out p50/p95 against the 10 ms budget on the user's RTX 3050; it refuses without `--allow-user-display` and supports `--dry-run` (prints the plan, launches nothing).

- [ ] **Step 1: Failing tests**: `listen_pass.main` with a non-TTY stdin returns 2 and the injected player was never called; with a fake TTY answering "no" plays nothing; the shell script without the flag exits non-zero, and `--dry-run --allow-user-display` prints the three scenes and exits 0 without starting Godot (checked by a PATH shim that fails if `Godot_*` is executed).
- [ ] **Step 2: Run** `cd tools/audio && python3 -m unittest test_listen_pass -v` and `cd tools/perf && python3 -m unittest test_gpu_frametime -v`. Expected: FAIL.
- [ ] **Step 3: Implement.** Agents never run either tool for real.
- [ ] **Step 4: Gates.**
- [ ] **Step 5: Commit**, message "User tools: guarded listening pass and GPU frame-time script (never run by agents)".

---

### Task 30: Music hooks, art approvals checklist and the program close

Size M.

**Files:**
- Create: `godot3d/scripts/audio/music_director.gd`, `godot3d/tests/test_music_director.gd`, `docs/release/art-approvals.md`
- Modify: `godot3d/scripts/earthfront_3d.gd` (feeds the director), `NEXT_STEPS.md`, `docs/ascension/ui-deviations.md`, `tools/ui/world_scores.json` (only for changes already shown as intended)

**Interfaces:**
- Produces: `MusicDirector` (pure): `const STATES := ["menu", "calm", "combat", "victory", "defeat"]`, `func update(ctx: Dictionary, now: float) -> String` (ctx: `on_title`, `winner`, `recent_combat_s`), hysteresis of 8 s before leaving combat, `func track_for(state: String) -> String` returning "" for every state (no tracks yet), `play` is a no-op on "".

- [ ] **Step 1: Failing tests**: state transitions (title to calm on deploy, calm to combat on a shot within 3 s, combat back to calm only after 8 s quiet, victory and defeat terminal); no player is created while every track is "".
- [ ] **Step 2: Run** `-- test_music_director`. Expected: FAIL.
- [ ] **Step 3: Implement**; write `art-approvals.md` (remaining recolours named in the previous program's Task 9 report, the P1 damage states, the stance chip, the draft cards) as a sign-off checklist for the user.
- [ ] **Step 4: Program close:** full gates; `git diff --stat 67e6355..HEAD -- crates/` against the cumulative allow-list; golden and both pins; scoreboard vs `tools/ui/world_scores.json` with every intended change listed; Survival pair; perf table; one scripted Normal playthrough on private Xvfb with the real bridge and Dummy audio (deploy, follow the coach, train, hold the ford, use Stop/Hold/stance, survive wave 3, finish or lose; record match length, score, first contact, waves, audio play counts per id) and `verify-run` on its replay; `NEXT_STEPS.md` lists everything owed to the user (listening pass, GPU run, Windows test, music, art approvals, license, itch upload).
- [ ] **Step 5: Commit**, message "Music hooks without tracks, art approvals checklist, program close notes"; final report with every number.

---

## Self-review record

- Spec coverage: P0 items (shot window, Kestrel default and picker with `match.json`, docs drift, controls, debrief buttons, settings, hygiene, CI) are Tasks 1 to 5. P1 (cues and 8 ids, funds, power, wave cleared, stings, damage and working states, camera, coach) are Tasks 6 to 9. P2 (depth flag, acquire/leash/under attack, separation, halt fix, four commands and client keys, waypoints, heli counter, breach and siege, re-baseline, determinism and Survival tests) are Tasks 10 to 16. P3 (enable list, economy, waves and doctrines and AI, difficulty and seed, victory and match length, score and records) are Tasks 17 to 22. P4 (run mode and perks, replays, verify, viewer, daily seed, meta) are Tasks 23 to 26. P5 (launcher, runtime dir, exports, version, checklist, smoke) are Tasks 27 and 28. P6 (listen pass, GPU script, music hooks, art approvals) are Tasks 29 and 30. Out-of-scope items have no task.
- Placeholder scan: the only values left to fill are measurements the steps produce (Task 10 pins measured in Step 1, outcome ticks recorded by each task); each names the command that produces it.
- Type consistency: `Scenario::host_commands`, `is_depth`, `DepthUnit`/`DepthGlobal` field order, `Stance`, `Difficulty`, `MatchOptions`, `kestrel_reach_with`/`build_with`, `depth_building_cost`, `depth_score`/`DepthScore`, `depth_draft`, `waves_cleared`, `MatchConfig` (bridge, then `bridge_protocol`) and the client `MatchConfig`/`Settings`/`Records` names are used identically across tasks.
