# Kestrel Depth Design

Date: 2026-10-07. Branch: `kestrel-depth`, cut from `kestrel-next-level` @ 67e6355 (unmerged, 164 commits ahead of `master`; there is no git
remote).

## Intent (what the user asked for)

The user asked "how to improve the game further, look at all aspects including gameplay". Two read-only audits (gameplay depth, and
everything outside the sim) produced ranked findings; the user answered "all of them". This spec turns those findings into one program of
seven phases. Success = a stranger launches the game, lands on Kestrel, is taught the controls, hears every important event, commands units
that defend themselves and spread out, cannot solve the map with 80 credits of walls, plays a 15 to 25 minute match with a real late game
and a score, can replay a seeded run, and can download an exported build.

Sources: `.superpowers/sdd/2026-10-06-kestrel-next-level/gameplay-audit.md` and `experience-audit.md` (gitignored scratch). Every code claim
below was re-checked against the branch HEAD unless marked "audit-measured" (numbers from the audit's scratch harness, not re-run for this
spec) or "unverified".

## Facts the design rests on

Sim and determinism
- The only pinned hash is `golden_hash_pins_cross_target_determinism` (`sim.rs:6683`, value at `:6732`). It builds its own legacy two-CC sim
  with `Balance::default()`; it never enables Earthfront. `crates/data` has `default_ron_matches_the_code_default`, so a `balance.ron` stat
  change must also change the code default and therefore re-pins the golden. Changing unit stats globally is not an option.
- Precedent for Earthfront-only state: per-entity hash fields appended only `if self.earthfront` (`sim.rs:2179`) and a global block
  (`sim.rs:2198`). `sim.rs` has 64 `self.earthfront` checks.
- CORRECTION to the brief: gating on `self.earthfront` alone does NOT protect Survival. The Godot Survival map also calls
  `enable_earthfront()` (`scenario.rs:232-233`, Kestrel at `:387-388`). This spec therefore adds a narrower flag, `depth` (set only by the
  Kestrel builder), and every P2 to P4 behaviour checks `self.earthfront && self.depth`. Survival, legacy maps and the golden stay
  byte-identical.
- `step` returns early once an Earthfront survival operation has a winner (`sim.rs:2417-2421`); the tick freezes.
- Seed: the bridge always builds `scenario.build(2026)` (`godot-bridge.rs:1354`, again at restart `:1393`). The sim RNG is only hashed
  (`sim.rs:2108`), never drawn.
- `Command` (`sim.rs:385`) has no Stop, Hold, Stance, AttackTarget or waypoint queue. It derives only `Clone, Debug` (no serde); the client
  protocol is text lines parsed by `take_commands` (`godot-bridge.rs:1121`).

Combat, movement, AI
- `run_combat` (`sim.rs:4186`) fires only at the nearest valid enemy inside the unit's own weapon range (`:4330-4360`); air/ground targeting
  via `targets_air`/`targets_ground`. No acquisition radius, no under-attack response, no stance.
- Attack-move halt (`run_movement`, `sim.rs:4080-4177`): the scan snapshot holds `(alive, owner, pos)` only, so any enemy in range halts the
  advance, including a helicopter the unit cannot shoot. Verified. `ATTACK_MOVE_LEASH` (`:162`) is only the engagement range for unarmed
  units, not a return leash.
- No unit separation in `run_movement`. Audit-measured: 10 infantry stack on one point.
- Only the AaTurret targets air (`balance.ron:65`); no unit does. Audit-measured: 4 helicopters beat any ground army with 0 losses.
- `order_unit_to` (`sim.rs:2554`) does nothing when `find_path` fails (`:2589`), so a wave unit with no path keeps no order. Waves:
  `run_earthfront_waves` (`earthfront.rs:918-1003`), size `min(6 + 2w, 24) + 2 x operational relays` (`:902`), doctrine locked 1350 ticks
  early, siege only when walls > 5 (`:941`). Audit-measured (not re-run): 4 walls (80 credits) on the ford neighbours seal the only crossing
  (`kestrel.rs` row 10, hexes (22,10)/(23,10), verified) and the base survives to 11:48 with zero army.
- Kestrel outcome test `kestrel_reach_overruns_an_undefended_base_and_holds_with_the_playtest_defence` (`scenario.rs:~2133-2200`):
  undefended base falls at t=4959; the playtest AI wins at t=13622 after 2 waves (`KESTREL_DEFENDED_WAVES = 3`, "never overrun before wave
  3").

Dormant content
- `UseAbility` returns early in Earthfront (`sim.rs:3090`); abilities are Barrage (Tank), EmpBurst (Helicopter), NaniteField (Capital)
  (`ability.rs:50-57`). `ChoosePerk` ignored (`sim.rs:2862`); 4 perks exist (`perk.rs`: Overcharge, Logistics, Conscription, Bulwark).
  `apply_ascend` returns early (`sim.rs:3264`); it is a paid upgrade sink with 4 tracks (weapons, armour, vitality, forge) and a linear cost
  ramp (`ascend_cost`, `:698`). Shields are zero in Earthfront (`:3374`). Capital needs era 3 (`:2688`); Earthfront tops out at era 1.
  Unverified: whether Logistics and Conscription reach the Earthfront refinery income and supply cap paths (their hooks at `sim.rs:3478` and
  `:1815` sit in shared code; P3 must check).

Client and bridge
- Shot window bug: `ShotWindow::record` (`godot-bridge.rs:552-560`) appends then age-filters by `tick - fired`; the loop calls it every
  frame (`:1442`) even after `step` stopped advancing, so rows accumulate forever after a win. Verified in code; audit-measured 4,384 rows
  in a 219 KB snapshot 9 s after a win.
- `run-3d.sh:24-28` starts Survival unless `SCENARIO=kestrel`; the bridge default is `Scenario::Survival` (`godot-bridge.rs:1298`). The
  title has 6 entries, 4 disabled (`live_screens.gd:29-33`), and always shows "Operation Dawnshield".
- `A` is attack-move (`keybinds.gd:15`) and the `camera_left` physical key (`project.godot:18`), read every frame by
  `_update_camera_controls` (`earthfront_3d.gd:1535`). Control groups are 1-4 (`keybinds.gd:27`). Factory, airfield, depot and battery cards
  have no hotkey (`live_adapter.gd:57-64`). Nothing on screen mentions F1.
- `_write_bridge_train` (`earthfront_3d.gd:2319`) sends the order without checking money.
- Debrief buttons are only "Review battlefield" and "Redeploy" (`live_screens.gd:69`). No settings screen; buses Master, SFX (+4 pan buses),
  UI, Ambient, Music exist (`default_bus_layout.tres`). Fog is read once from `EARTHFRONT_FOG` at bridge start.
- Audio: 18 sound ids in `sfx_manifest.json` from `tools/audio/build_sfx.py`; no music file. Nothing has ever been heard on real speakers.
- The client reads `res://runtime` (`earthfront_3d.gd:164`), never spawns the bridge, and there is no `export_presets.cfg`, version string
  or LICENSE (Cargo says `Proprietary`).
- Docs drift (verified): README:9 "fully visible battlefield", README:40 "90-second first wave" (now 2:30), README:102 "259 passing"
  (audit-measured 377), NEXT_STEPS:7 "101 tests", `godot3d/README.md:5-7` advertises modeled cities, illustrated districts and ten-era
  science. `.gitignore` does not cover `godot3d/runtime/*.flag`.
- CI (`.github/workflows/ci.yml`) covers Rust only and has never run (no remote). The Godot suite takes about 13.5 min under load
  (audit-measured).

## Phases (each independently shippable, gated, committed, unmerged)

### P0. Hygiene and front door (size M)
Files: `crates/server/src/bin/godot-bridge.rs` (only Rust file), `run-3d.sh`, `godot3d/project.godot` (input map),
`godot3d/scripts/ui/{keybinds,live_screens,live_adapter,game_ui}.gd`, `godot3d/scripts/earthfront_3d.gd`, a new
`godot3d/scripts/ui/settings.gd` (+ section), `README.md`, `godot3d/README.md`, `NEXT_STEPS.md`, `.gitignore`, `.github/workflows/ci.yml`,
tests and fixtures.
- Shot window: `record` skips when the tick did not advance (keep `last_tick`; also skip when the sim has a winner). Bridge test: step a won
  sim 100 frames, window length unchanged. Replay-safe (presentation only).
- Kestrel default with a map picker: the bridge default becomes Kestrel and `run-3d.sh` stops requiring `SCENARIO` (it still accepts
  `SCENARIO=survival`). Runtime map switching: the client writes `runtime/match.json` (`{scenario, seed, difficulty, fog}`; P0 uses only
  `scenario` and `fog`) then touches `restart.flag`; the bridge reads it on restart and rebuilds that scenario. The title's "New operation"
  opens a small picker (Kestrel Reach default, Survival selectable); the campaign card names the chosen map.
- Docs: fix every drift item listed in Facts; one paragraph in README saying the Godot client is the product and the Macroquad shell is
  legacy.
- Controls: camera pan moves to the arrow keys (plus edge pan and new middle-mouse drag); W/A/S/D no longer pan, so `A` only arms
  attack-move (open decision 7). Control groups 1-9. Build hotkeys for the four missing cards (proposed: N factory, I airfield, O depot,
  comma battery; `test_keybinds.gd` enforces no clash). An "F1 Controls" hint on the HUD.
- Debrief: Main menu, Restart (same map and seed), Quit.
- Settings screen (title entry enabled, pause menu entry added): Master/SFX/UI/Ambient/Music volume sliders on the existing buses, fog
  toggle (applies next match through `match.json`), keybind display (reuses the controls reference, not remappable yet), window mode.
  Persisted with `ConfigFile` at `user://settings.cfg`, never under `res://runtime`.
- Hygiene: ignore `godot3d/runtime/*.flag` and `match.json`.
- CI: add jobs for the Godot headless suite (download and cache Godot 4.7.2, `--headless --audio-driver Dummy`, fail on any SCRIPT ERROR
  line) and the Python tool tests (`tools/ui`, `tools/audio`). Workflow file only: there is no remote, so it cannot run; validate the YAML
  locally (actionlint if present, else a parser) and say so in the commit.
- Player sees: Kestrel first, a choice of map, settings, a working A key, nine groups, a way back to the menu.
- Testing: bridge unit tests (shot window, `match.json` parsing incl. malformed file falls back to defaults), Godot tests for picker,
  settings persistence (temp `user://` path), keybinds, debrief buttons. Title board re-baselined deliberately (shown).

### P1. Feedback (size M)
Files: Godot client scripts (`earthfront_3d.gd`, `scripts/audio/audio_director.gd`, `scripts/world/world_fx.gd`, HUD/toast scripts, a new
`kestrel_coach.gd`), `tools/audio/build_sfx.py` + its test, `godot3d/assets/audio/sfx/*`, bridge only for an additive per-building power key
if `services` lacks one (verify first). No `crates/core`.
- Silent events get a cue. From the existing manifest: rally set (`ui_click`), 45 s wave warning (`alert`, quieter), unit under attack
  (`alert`, own 10 s cooldown), production complete (`ack_*`, one toast per batch not per unit). New procedural ids via `build_sfx.py` (same
  CC0-by-construction pipeline and tests): `denied`, `place_thunk`, `power_down`, `power_up`, `wave_cleared`, `research_complete`,
  `victory_sting`, `defeat_sting` (18 to 26 ids).
- Insufficient funds: the client checks cost against `money_bits` before sending train/build, does not send the doomed order, plays `denied`
  and toasts "N materials short". Low power: toast + `power_down` on the transition demand > generation, `power_up` on recovery. Wave
  cleared: derived from the snapshot (wave spawned, no wave units left). Victory/defeat stings replace the reused cues.
- Building states with existing WorldFx cards: below 50% HP light smoke, below 25% fire and a flicker; working state (producing or
  researching) a small periodic puff; all fog-gated and pooled.
- Camera: double-tap a group key centres on it; hold F follows the selection; Space jump keeps its behaviour.
- Onboarding coach (Kestrel only): first-run hints keyed to the existing objectives (select the squad, right-click to move, place a
  building, train, attack-move), dismissible, "never show again" stored in `user://settings.cfg`; F1 hint stays visible.
- Testing: AudioDirector recording stub asserts event to id, cooldown and bus; sfx tests (duration, peak, loudness, deterministic hash) for
  the new ids; coach state machine tests; WorldFx slot tests for damage states. No real audio device ever.

### P2. Combat that feels like an RTS (size L)
Files (exact): `crates/core/src/game/sim.rs`, new `crates/core/src/game/depth.rs` (an `impl Sim` block plus tests, declared from `sim.rs`
with `#[path]` exactly like `earthfront.rs` at `sim.rs:10-11`), `crates/core/src/game/path.rs`, `crates/core/src/game/earthfront.rs`,
`crates/core/src/game/scenario.rs`, `crates/server/src/bin/godot-bridge.rs`, Godot client scripts. Every behaviour behind `self.earthfront && self.depth`; new
per-entity state hashed only when `depth` is on, appended after the `:2179` block.
- `depth` flag: `Sim::enable_depth()` called only by `kestrel_reach`.
- Auto-acquire and leash: idle and attack-moving units scan an acquisition radius of weapon range + 3; they move to engage, and an idle unit
  records an anchor and returns once it is more than 6 from it or its target dies. Under attack: when a unit or building takes damage,
  friendly idle units within 6 that can hit the attacker engage it (bounded by the same leash). Applies to the alien AI's units too, so the
  base AI and waves fight back properly.
- Separation: after movement, same-owner ground units closer than 0.45 are pushed apart in ascending index order over the combat spatial
  grid, fixed point, never onto an impassable tile; air units separate among themselves.
- Attack-move halt fix: the halt scan uses the same targetability test as `run_combat` (add the air flag to the snapshot tuple).
- New commands `Stop`, `HoldPosition`, `SetStance { unit, stance }` (Aggressive default, Defensive: respond only when it or an ally within 6
  is hit, and stays within 3 of its anchor, Hold: never moves, fires in range) and `AttackTarget { unit, target }` (internal forced target, also
  used by breaching). Appended at the end of `Command`; ignored when `depth` is off. Bridge text lines `stop,id`, `hold,id`,
  `stance,id,name`, `target,id,eid`. Client (Kestrel only): S stop, D hold, Z cycles stance (yaw is locked on Kestrel), right-click an enemy
  attacks it, HUD order buttons and a stance chip.
- Shift-queued waypoints: a per-unit queue of up to 8 `(point, attack_move)` legs consumed on arrival; shift+right-click appends. Tractable
  because `order_goal`/`move_target` already exist; if hashing and snapshot plumbing push P2 past its task budget, it moves to a P2
  follow-up task and the spec records the deferral.
- Helicopter counter, pick one: AntiArmor can hit air at 50% damage (missile teams), chosen over infantry because it keeps the
  infantry/AntiArmor/tank triangle intact and the Helicopter (Ballistic, x1.5 vs Flesh) still beats AT one for one. Override in `depth.rs`,
  not `balance.ron` (golden). Gates with headless duels: 4 Heli vs 5 AT + 1 Inf no longer ends with 0 heli losses (target: AT side wins or
  trades at least 60% of its cost); 4 Heli vs 12 Inf unchanged; AT vs Tank and Inf vs AT outcomes within 1 survivor of the audit table. If
  AT-vs-air breaks the triangle, fall back to infantry at 25% and record the measured table.
- Ford exploit, siege behaviour: when a wave unit's `find_path` fails, path again with player walls (then other player buildings) passable
  at high cost, walk it, and `AttackTarget` the first blocking structure; re-path when it dies. Siege doctrine threshold drops from walls >
  5 to walls >= 3, and a siege wave leads with tanks (Explosive x1.5 vs Structure). Test: the audit's 4-wall seal is breached by wave 2 and
  the base is attacked.
- Re-baseline: the Kestrel outcome test keeps its invariants (undefended falls, defended never overrun before wave 3 or wins); the commit
  message and test comment show old vs new ticks (old: falls 4959, AI wins 13622).
- Player sees: squads that shoot back, spread out, stop and hold on command, a reason to build AT against gunships, and walls that delay
  rather than win.
- Testing: one headless duel/scenario test per change in `depth.rs` (acquire, leash return, under-attack response, separation spacing, halt
  fix vs heli, each command, queue, heli duels, wall breach), plus a determinism test (same inputs twice, equal hash) and a test that
  Survival with identical inputs hashes the same as before the phase.

### P3. Shape of a match (size L)
Files: `crates/core/src/game/{sim.rs, depth.rs, earthfront.rs, scenario.rs}`, `crates/server/src/bin/godot-bridge.rs`, Godot client.
`crates/data` stays untouched by default (depth tuning lives as consts in `depth.rs`); if a table must be data-driven it is a new depth-only
field whose default changes nothing outside `depth`.
- Enable list (justified): abilities YES (code, AI usage and tests exist; Barrage with tech 6, EMP with Helicopter, NaniteField with
  Capital; the dead Q key comes alive); Capital YES at era 1 (tech 7) as the late unit, built at the VehicleFactory; Ascend tracks YES,
  renamed "Upgrades" in the UI (weapons, armour, vitality; forge excluded), as the money sink, era 1 raises the level cap; perks deferred to
  P4 drafting. NO: shields (needs presentation work, overlaps Bulwark), AntimatterPlant (worst recolour art, power is not a constraint),
  alloy seams (needs a new extraction loop and art; they stay decoration), branch riders and antigrav (Survival grid tech without UI).
- Economy: each additional refinery costs +50 (150, 200, 250 ...); repair becomes heal over time with a cooldown and a minimum cost (CC no
  longer free); measured target: banked credits at 10:00 under 2,500 for the playtest AI (audit-measured today: 8,924 with walls).
- Waves and doctrines: per-wave composition table (wave 3 first flyers, siege waves with tanks + Capital against walls, wave 6 elite wave
  with a Capital escort, escalation to wave 10); doctrine order seeded from the sim RNG (first real draws, depth only); the alien base AI
  activates at tick 0 and raids at era 0 once supply >= 12.
- Difficulty Easy/Normal/Hard as scenario inputs in `match.json`: start credits 1500/1200/1000, first wave 3:00/2:30/2:00, interval
  3:30/3:00/2:30, wave size x0.75/1/1.25. Seed chosen on the title (random by default, editable, shown on the debrief).
- Victory: the Core Node takes no damage while any relay is operational, and the wave-6 elite wave must have spawned; destroy it afterwards.
  Target: the playtest AI match ends between 15 and 25 minutes (27,000 to 45,000 ticks) on Normal; the outcome test is re-baselined to that
  window.
- Score and stats: score = waves held, enemy value destroyed, time bonus on victory, losses, x difficulty; debrief shows score, grade and
  personal best per map and difficulty (`user://records.cfg`).
- Testing: unit tests per mechanic, difficulty presets build and resolve, seeded doctrine order differs across seeds and repeats per seed,
  match length window test, balance table of measured duels and AI runs in the commit message.

### P4. Roguelite run mode, Direction B (size L)
Files: `crates/core/src/game/{depth.rs, perk.rs, sim.rs, scenario.rs}`, `crates/server/src/bin/godot-bridge.rs`, the command parser moved to
a shared `crates/server/src/bridge_protocol.rs`, a new `crates/server/src/bin/verify-run.rs`, Godot client.
- A run is Kestrel with depth rules plus `run` mode: 12 waves or until the CC falls. When a wave is cleared the sim draws 3 distinct perks
  from the seeded RNG out of the run's pool; the client pauses (existing `pause.flag`), shows the draft, and sends `ChoosePerk` (gate
  relaxed for `run`). Pool: the 4 existing perks (after P3 confirms they reach Earthfront income and supply) plus depth perks over P3
  features (free upgrade level, ability cooldown -25%, refinery discount, turret range +1, early tank tooling, wall HP, cheaper repair,
  Capital discount).
- Run score extends P3 score; daily seed = UTC date to seed on the client.
- Replays: the bridge logs a header (version, scenario config, seed, difficulty, mode, perk pool, balance hash) and `(tick, raw command
  lines)` per tick to `user://replays/*.rpl`, closing with the final hash and score. AI and scripted commands are pure functions of state
  and are rebuilt, not logged. `--replay <file>` playback ignores client orders; a speed control (0.5x to 8x, pause) via a control file; a
  Godot replay viewer with input disabled.
- Verification: `cargo run -p rts-server --bin verify-run -- <file>` re-simulates headless and prints score and hash match. Meta progress
  kept small: unlocked perk pool in `user://settings.cfg` (one unlock per run reaching wave 6, pool 8 to 16); the replay header carries the
  pool so verification never reads local meta.
- Out: no online leaderboard server, no submission endpoint; the local verifier is the whole story.
- Testing: draft draws deterministic per seed, perk effects, record then verify round trip equals live hash, playback at 8x equals 1x,
  tampered replay fails verification.

### P5. Ship-readiness (size M)
Files: `godot3d/export_presets.cfg` (new), `godot3d/project.godot`, `earthfront_3d.gd` and a small `bridge_launcher.gd`, bridge
(`--runtime-dir` flag), `run-3d.sh`, `docs/release/itch-checklist.md` (new), `tools/release/` packaging script.
- Choice: the client launches a bundled bridge binary itself (`OS.create_process`, killed on exit and on crash detection), with the runtime
  directory under `user://runtime` (passed as a globalized path). Least risky: the protocol, tests and replay tooling stay as they are, and
  dev runs keep working (`run-3d.sh` passes the same flag). Embedding the sim with GDExtension is OUT of scope and recorded as the next step
  (30 Hz state, no JSON, save/load).
- Export presets Linux x86_64 and Windows x86_64; the Windows bridge is cross-built (toolchain availability unverified) and needs a Windows
  test by the user. Version string in `project.godot` and the workspace, shown on the title footer (`footer_right`). LICENSE: open decision
  5. itch.io page checklist as a doc (needs the user's account; butler upload documented, not run).
- Testing: launcher tests with a stub binary, runtime path tests, an exported Linux build smoke run on private Xvfb with `--audio-driver
  Dummy`.

### P6. Needs the user (documented, not blocking; size S)
- `tools/audio/listen_pass.py`: plays every sound id with its category label, only when the user runs it, with an interactive confirmation;
  refuses to run without a TTY. Agents never run it.
- `tools/perf/gpu_frametime.sh`: idle, combat and zoomed-out p50/p95 against the 10 ms budget, for the user's RTX 3050 session.
- Music: a `MusicDirector` with Music-bus hooks (menu, calm, combat, victory, defeat) and no tracks; the user supplies or approves tracks.
- Art direction approvals: a checklist of remaining recolours and the P1 damage states for the user to sign off.

## Out of scope

Online multiplayer, PvP and co-op (need the sim in Godot and a relay); new maps (decided: no Kestrel variant in this program; seeds and
difficulty supply the variety); voice acting; level editor; eight-direction unit art; day/night.

## Constraints (all phases)

- `crates/core` and `crates/data` rule, relaxed deliberately and narrowly: only P2, P3 and P4 may touch them, only the files listed per
  phase, and every new behaviour sits behind `self.earthfront && self.depth` (or the P4 `run` flag on top). P0, P1, P5 and P6 touch no file
  under `crates/core` or `crates/data`. Check `git diff --stat 67e6355..HEAD -- crates/` at every phase end against the phase's list.
- Golden hash `2_081_234_273_307_305_018` never changes. Survival and legacy maps stay byte-identical (their Rust determinism and playtest
  tests untouched); Survival does not get the combat changes (open decision 6).
- Gates per phase: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --workspace`, golden hash, Godot headless suite (0
  SCRIPT/SHADER/ERROR, leak line at baseline), `tools/ui` and `tools/audio` unittests, `verify_all.sh`, idle scoreboard (no board drops more
  than 2.0 except where a phase intends it: P0 title, P1 damage states, P2 stance chip), Survival pair at least 97 (no phase intends a
  Survival change).
- Perf: at most +120 draw calls and +150k primitives vs `world_baseline.json`; separation and acquisition must keep a 30 Hz tick under
  budget in the bridge (measure ms per tick with 80 units).
- QA never plays real audio, opens windows on the user's display or moves the cursor: `--headless` or `--audio-driver Dummy`, private Xvfb
  only.
- No pushing, merging or remote creation without the user (there is no remote; creating one is the user's decision).
- Commit trailer exactly `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` on every commit (re-check after each subagent task); no
  em or en dashes; stage only a task's own paths.

## Open decisions (defaults chosen; user may overrule)

1. Direction B (roguelite run mode as P4): default YES.
2. Enable list: abilities, Capital at era 1, Ascend as Upgrades YES; shields, AntimatterPlant, alloy seams NO.
3. Run length: 12 waves (about 35 min on Normal); match victory window 15 to 25 min.
4. Export targets: Linux x86_64 and Windows x86_64; macOS later.
5. License: undecided, user's call (keep Proprietary / all rights reserved, or open code with separate asset terms). Default until decided:
   no LICENSE file, Cargo stays `Proprietary`.
6. Survival gets the combat changes: default NO, Kestrel depth only.
7. Camera pan on arrows, WASD freed: default YES (S stop, D hold on Kestrel).
8. Branch strategy: `kestrel-depth` from `kestrel-next-level` @ 67e6355; the user decides merge order of `gameplay-hud-kestrel-reach`,
   `kestrel-next-level` and this branch later.
9. Heli counter: AntiArmor at 50% vs air (fallback infantry at 25%), decided by the measured duels.

## Risks

- Balance churn: every P2/P3 change moves the Kestrel outcome test; mitigated by keeping its invariants, showing old vs new numbers, and
  gating each change with its own duel test.
- Determinism regressions: new state is hashed only under `depth`, scans run in ascending index with fixed point; same-input-twice and
  Survival-unchanged tests every phase; the golden is a hard stop.
- Scope: seven phases, three of them L. Each phase ships alone; P4 to P6 can be dropped without leaving P0 to P3 half-done.
- Art budget: damage states and the replay viewer reuse WorldFx and existing cards; no new painted art is promised.
- Helicopter counter breaking the opening: AT arrives at tech 0 (100 credits, 900 ticks) and helicopters appear from wave 3; the duel gates
  and the outcome test catch an opening that becomes trivial or impossible.
- Breach pathing cost: a second path search per stuck unit is bounded to once per unit per wave target change.
- Windows build untested here; P5 needs the user's Windows machine before any public upload.
