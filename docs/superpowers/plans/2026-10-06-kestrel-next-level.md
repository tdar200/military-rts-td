# Kestrel Next Level Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Kestrel Reach feel like a finished game: truthful HUD icons, a real opening with objectives, generated combat and UI sound, presentation-only fog of war with a useful minimap, and less placeholder-looking building art.

**Architecture:** Five phases on branch `kestrel-next-level` (cut from `gameplay-hud-kestrel-reach` @ caf3920). Rust changes are limited to `crates/core/src/game/scenario.rs` (P2) and `crates/server/src/bin/godot-bridge.rs` (P4). Everything else is Godot client and `tools/` scripts, all gated on Kestrel / `world_art_on` so Survival stays byte-identical. Audio logic is a pure module behind a thin player pool; fog is a bridge-computed mask the client renders and obeys.

**Tech Stack:** Rust (scenario, bridge), Godot 4.7.2 Compatibility (GDScript), numpy/PIL deterministic generator scripts in `tools/`.

**Spec:** `docs/superpowers/specs/2026-10-06-kestrel-next-level-design.md` (approved by the user 2026-10-06: "go", after "do all"). Predecessor plans: `2026-10-05-kestrel-sprite-entities.md`, `2026-10-05-kestrel-combat-motion-fx.md`.

## Global Constraints

- Rust: allowed crates changes are exactly `crates/core/src/game/scenario.rs` (Task 2) and `crates/server/src/bin/godot-bridge.rs` (Tasks 2 fixture regen only via the bridge binary, Task 6). `golden_hash_pins_cross_target_determinism` must not move. After every task `git diff --stat d81deab..HEAD -- crates/` may list only `godot-bridge.rs` plus `scenario.rs` once Task 2 lands.
- Survival byte-identical: SHA tests in `godot3d/tests/test_world_art_survival.gd` never weakened (adding assertions is fine); every new behaviour gated on Kestrel / `world_art_on`; Survival snapshot shape unchanged.
- Perf: at most +120 draw calls and +150k primitives vs `tools/ui/world_baseline.json` `_perf` (software: home 25 dc / 156,776 prim, max 78 / 209,766 at HEAD caf3920). Idle frame at most 10 ms p50 on the GPU baseline method when the user's display is available (otherwise state unmeasured).
- QA: private Xvfb only (`tools/qa/world_capture.py --software`, display :94, never `--help`, never `--gpu` without `--allow-user-display`). NEVER play audio, open windows or move the cursor on the user's machine: Godot only with `--headless` or `--audio-driver Dummy`. Audio is verified by a recording stub and offline file analysis, not by listening.
- Commit trailer exactly `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (subagents keep stamping Opus 5.5 from a harness notice; the controller rewrites after each task). Stage only a task's own paths, never `git add -A`, never `__pycache__`. No em or en dashes anywhere (grep `\x{2013}|\x{2014}` on added lines).
- Gates after every task: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, `cargo test --workspace --offline`, Godot suite `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd` (0 SCRIPT ERROR, 0 SHADER ERROR, 0 ERROR lines, ObjectDB leak line stays 141 unless the task explains a deliberate change), `cd tools/ui && python3 -m unittest test_world_diff test_build_prop_atlas test_build_building_variants test_build_fx_atlas -v` (plus new test modules), `bash tools/ui/verify_all.sh` exit 0 with no limits loosened. TDD: show the failing test first.
- Idle scoreboard (`world_diff.py run` vs `$SCRATCH/world/tff_scores.json`): no board drops more than 2.0 except where a task intends the change (Task 1 icons are HUD only so should not move; Task 2 changes the start so boards may move, re-baseline deliberately with `--write` after showing before/after; Task 7 fog may darken idle frames, treat unexplored shroud as intended and re-baseline with fog off for comparison). `SCRATCH=/tmp/claude-1000/-home-tahseen-dar-Projects/6192d82f-7996-46e2-a728-f193248e89d9/scratchpad`. Survival pair at least 97 against `$SCRATCH/world/surv/survival_home.png` (capture timing swings it 97-99.8; judge borderline cases against a same-tick run).

## Review Focus

- Fog must not leak: enemy positions through toasts, the enemy-intel / region / threat panels, the minimap marks, selection and picking, effects (hit, collapse, dust), the shots window, and AUDIO (a sound from an unseen fight must not play at its position). Re-sighting an enemy must not replay "unit added" toasts or deploy effects.
- Fog edge cases: pause and scenario restart (explored state resets with the sim), a unit killed this tick that was the only viewer of its killer, entities that were visible and then die out of sight, the `EARTHFRONT_FOG=0` kill switch restoring today's behaviour exactly.
- Audio safety: no test path reaches a real audio device; no `AudioStreamGenerator.push_frame` busy loops; cooldowns stop a 30-shots-per-second fight from spawning 30 players; Survival keeps its tones; sounds are paused with the sim.
- Scenario retune: the overrun/defended playtest, ford and region tests, bridge tail-key tests and the Godot Kestrel fixture still pass honestly (re-derived expectations explained, not just edited); first contact lands near 2:00 and a do-nothing player still loses.
- Objectives: stage logic derived from real entity state (power online, harvester delivering, squad size, wave survived) handles a destroyed building, loading mid-game and Survival untouched.

---

### Task 1: HUD icon truth

**Files:**
- Modify: `godot3d/scripts/ui/live_adapter.gd` (`BUILD_CARDS` lines ~46-58, the queue card ~968, `GROUP_SPRITES` ~28, the uses at ~952/985), `godot3d/scripts/gallery/fixtures_build.gd`, `godot3d/scripts/gallery/fixtures_gp.gd`, `godot3d/tests/` (new `test_hud_icons.gd`), `docs/ascension/ui-deviations.md`
- Reuse (do not duplicate): `godot3d/scripts/world/world_sprites.gd` `SPRITES` table, `godot3d/assets/world/sprites/`.

**Interfaces:**
- Consumes: `WorldSprites.SPRITES[kind]` (kind -> [human texture path, alien texture path]).
- Produces: `LiveAdapter.icon_path_for_building(kind: String) -> String` and `icon_path_for_unit(kind: String) -> String` (human art; falls back to the generic icon only when no sprite exists).

- [ ] **Step 1: Failing tests:** every `BUILD_CARDS` entry resolves to a texture that exists and equals the world sprite of its kind (factory, airfield, depot, lab, battery were stale); the queue card shows the queued building's sprite, not `foundation_v1`; all six unit kinds get a group icon; no entry still points at `barracks_v2` unless the kind is Barracks.
- [ ] **Step 2: Implement** via a single mapping function used by build deck, queue card and group icons; keep Survival fixtures and screens untouched.
- [ ] **Step 3: Gates, capture, score.** Show a before/after of the build deck; the pixel-gate UI tests may only change where an icon legitimately changed (list each).
- [ ] **Step 4: Commit,** append to the task report.

---

### Task 2: Kestrel opening (Rust scenario and pacing)

**Files:**
- Modify: `crates/core/src/game/scenario.rs` (`kestrel_reach`, lines ~309-392 and its tests ~1389-1820), `godot3d/tests/fixtures/kestrel_snapshot.json` (regenerate with `target/release/godot-bridge --scenario kestrel --dump-snapshot <path>`), `crates/server/src/bin/godot-bridge.rs` tests that pin the Kestrel start (expectations only)
- Do NOT touch `kestrel.rs` ROWS/REGIONS (bridge detects Kestrel by comparing the ground layer to ROWS).

**Interfaces:**
- Consumes: `Sim::add_building/add_unit` style helpers already used by `kestrel_reach` for the alien base, `earthfront.rs` wave logic, the bridge's `waves_survived() > 0` gate for the alien AI (`godot-bridge.rs:~821`).
- Produces: a human start of CommandCenter (7,9) + PowerPlant + Refinery (+ Barracks) placed fully built next to the CC on buildable tiles, one Harvester, the 4 infantry, resources tuned by playtest; a pre-wave alien probe (2-3 infantry AttackMove toward the nearest human relay/CC around tick 1500-1800) and the alien AI active before wave 1 so first contact is near 2:00; unchanged wave schedule afterwards unless a test forces a retune.

- [ ] **Step 1: Failing tests:** human start contains the listed buildings and a harvester, all on buildable, passable tiles with the ford and region tests unchanged; first hostile unit comes within weapon range of a human structure between ticks 3000 and 4200 in an undefended run; an AI-defended human base still holds at least 3 waves and an undefended one still falls (existing playtest, same thresholds); the probe is deterministic (replay test); the golden hash test untouched and green.
- [ ] **Step 2: Implement** in `scenario.rs` only (plus bridge test expectations); tune tick values and money against the playtest tests, not around them; document each tuned constant with its reason.
- [ ] **Step 3: Regenerate the Godot fixture** and update the ~10 Godot test files that read it; explain every changed expectation.
- [ ] **Step 4: Gates, capture and score** (boards will show the new base; show before/after and re-baseline `world_scores.json` only after the user-visible change is explained).
- [ ] **Step 5: Commit,** append report.

---

### Task 3: Kestrel objectives and briefing

**Files:**
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_advance_tutorial`/`_update_tutorial` ~3050-3107, reset ~3598), `godot3d/scripts/ui/live_adapter.gd` (`OBJECTIVE_GROUPS`, `STAGE_DETAIL`, ~30-41, 608), `godot3d/scripts/ui/vm_maps.gd` (briefing ~13, 354-385), `godot3d/scripts/ui/vm_gameplay.gd`, `godot3d/tests/` (new `test_kestrel_objectives.gd`), `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: `bridge_snapshot` entities (kinds, owners, construction, cargo), `waves_survived`, `winner`, power/economy fields already used by the HUD.
- Produces: `KestrelObjectives.evaluate(snapshot: Dictionary) -> Dictionary` (pure, in `godot3d/scripts/world/kestrel_objectives.gd`): current stage 1-5 (Power the base, Start the economy, Raise a squad, Hold the ford, Break the Core Node), per-objective done flags, title/detail strings; HUD objective card, briefing and toasts read it on Kestrel only.

- [ ] **Step 1: Failing tests** on the pure evaluator: each stage from crafted snapshots; a destroyed power plant reverts stage 1 appropriately; loading mid-game (many buildings, wave 2 survived) jumps to the right stage; `winner` set shows completion; Survival still uses the legacy tutorial (assert unchanged call path).
- [ ] **Step 2: Implement** the evaluator and wire the HUD/briefing/toasts for Kestrel; keep the Survival tutorial functions intact.
- [ ] **Step 3: Gates, capture, score,** open a capture of the objective card.
- [ ] **Step 4: Commit,** append report.

---

### Task 4: Sound set generator

**Files:**
- Create: `tools/audio/build_sfx.py`, `tools/audio/test_build_sfx.py`, `godot3d/assets/audio/sfx/*.ogg` or `.wav` (+ `.import` files via a Godot `--import` run), `godot3d/assets/audio/sfx/README.md` (CC0 by construction, generator reference)
- Modify: `tools/ui/verify_all.sh` only if it lists test modules (add the new one)

**Interfaces:**
- Produces: a deterministic generator (fixed seeds, numpy, no network) writing: `rifle`, `cannon`, `plasma_bolt`, `explosion_small`, `explosion_large`, `collapse`, `rotor_loop`, `tread_loop`, `foot_loop`, `ui_click`, `ui_hover`, `select`, `ack_infantry`, `ack_vehicle`, `ack_air`, `alert`, `build_complete`, `wave_inbound`; a manifest `sfx_manifest.json` (id, file, duration, loop flag, base volume dB, category) consumed by the director in Task 5.

- [ ] **Step 1: Failing tests:** two runs byte-identical; every manifest file exists, 22050-44100 Hz mono/stereo, duration within a stated range, peak below 0 dBFS (no clipping), loops have matching start/end amplitude (click-free), loudness within 6 dB across categories; the committed files equal the generator output within a stated tolerance.
- [ ] **Step 2: Implement** the synthesis (layered noise bursts + filtered sweeps + envelopes; simple, characterful, not painful); render and print a loudness/peak table; keep the total asset size under 3 MB.
- [ ] **Step 3: Commit,** append report. (No listening: the table and waveform stats are the check.)

---

### Task 5: AudioDirector, player pool, buses and hooks

**Files:**
- Create: `godot3d/scripts/audio/audio_director.gd` (pure), `godot3d/scripts/audio/audio_pool.gd` (thin engine layer), `godot3d/default_bus_layout.tres`, `godot3d/tests/test_audio_director.gd`
- Modify: `godot3d/project.godot` (bus layout path only), `godot3d/scripts/earthfront_3d.gd` (`_setup_audio` ~343-351, `_play_tone` call sites ~2337, 2655, 3154, 3173, 3491, 3512, 3519, 3601; shot dispatcher; WorldFx spawn sites; selection and order handlers), `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: Task 4's `sfx_manifest.json` and files; camera view rect (`view_ground_rect()`), `bridge_nodes`, `sim_paused`.
- Produces: `AudioDirector.request(id: String, world_pos: Vector3, now: float) -> Dictionary` returning `{play: bool, volume_db, pan, bus}` or `{play:false}` (pure: cooldowns per id, priority, voice cap per category, off-screen attenuation/skip, distance volume, ducking state); `AudioPool.play(result, stream)` owning 16 SFX players + 1 ambient + 1 UI on buses Master/SFX/UI/Ambient/Music; Kestrel-only hooks replacing `_play_tone` sites (Survival keeps its tones).

- [ ] **Step 1: Failing tests (recording stub, no engine audio):** cooldown blocks a repeat inside its window; 30 requests in a second yield at most the category cap; an off-screen position is skipped or heavily attenuated; pan sign follows screen x; ducking lowers Ambient under `explosion_large` and recovers; paused sim requests nothing; Survival path does not call the director; no test instantiates a real `AudioStreamPlayer` outside a Dummy driver.
- [ ] **Step 2: Implement** director, pool, bus layout, preloaded streams (no synchronous generator loops), hooks: shots (by attacker kind), hit/explode/collapse, unit-ready, build-complete, wave-inbound, under-attack alert (with cooldown), selection and move/attack order acknowledgements by unit class, UI click/hover on Kestrel HUD buttons, rotor/tread/foot loops tied to moving units with a cap.
- [ ] **Step 3: Gates.** Run the Godot suite with `--headless` only; run one software capture session with `--audio-driver Dummy` (via `launch_ui.py`) and confirm the director logged plays with no errors. State clearly that nothing was listened to.
- [ ] **Step 4: Commit,** append report.

---

### Task 6: Fog of war in the bridge

**Files:**
- Modify: `crates/server/src/bin/godot-bridge.rs` (snapshot writer ~150-420, `ShotWindow` ~28-85, tests ~949-1262)
- Do NOT touch `crates/core` or `crates/data`.

**Interfaces:**
- Consumes: `Sim::views()` entity data, `AttackProfile.range` via core stats (public `UnitKind::stats()` / building stats), `is_kestrel_map`, `ShotWindow`.
- Produces: a `FogState` (bridge-side, reset with the sim) with a sight-radius table (unit sight = max(weapon range, 6) + 1; buildings 7; Command Center 9; Harvester 5; gunship 10), a per-cell mask over the 44x26 grid (0 unseen, 1 explored, 2 visible) persisted across ticks as explored; new additive snapshot key `"fog":"<1144 chars>"` (one digit per cell, row-major) placed before `shots`; non-human entities outside the visible union are omitted, except previously seen enemy buildings, kept with `"remembered":true`; `shots` entries dropped unless attacker or target cell is visible; `core_node`, `alien_relays`, `wave_route`, `next_wave_ticks` stay (briefing intel); kill switch env `EARTHFRONT_FOG=0` (bridge emits `fog` as all-visible and omits nothing); Survival unchanged (no `fog` key).

- [ ] **Step 1: Failing tests:** a unit's sight reveals cells within its radius and explored persists after it leaves; an alien unit outside sight is absent from the snapshot and present inside; a seen alien building later out of sight appears with `remembered:true`; shots with both ends in the dark are dropped, one visible end kept; `EARTHFRONT_FOG=0` output equals today's entity list; Survival snapshot has no `fog` key and is byte-identical; JSON stays valid; mask length equals width*height; restart clears explored.
- [ ] **Step 2: Implement** (cheap: integer circle fill per viewer, recomputed per snapshot write, not per tick if the cache trick used for supply links applies).
- [ ] **Step 3: Gates;** update the tail-key asserts deliberately; regenerate the Godot fixture to include `fog`.
- [ ] **Step 4: Commit,** append report.

---

### Task 7: Fog of war in the Godot client

**Files:**
- Modify: `godot3d/scripts/continuous_terrain.gd` (ground shader ~186-269: mask sampler + uniforms), `godot3d/scripts/earthfront_3d.gd` (`_sync_bridge_entities` ~2611, `_dispatch_shots`, effect spawn sites, notification/deploy effect sites ~2640), `godot3d/scripts/world/world_fx.gd`, `godot3d/scripts/ui/vm_gameplay.gd` and the enemy-intel/region/threat sections, `godot3d/scripts/ui/live_screens.gd:36`, `godot3d/scripts/gallery/fixtures_title.gd:51`, `NEXT_STEPS.md`, `README.md`, `godot3d/README.md`, the five tests that ban fog wording (`test_screen_region_map.gd:115`, `test_screen_early_mission.gd:53`, `test_screen_terrain_guide.gd:116`, `test_section_enemy_intel.gd:21`, `test_vm_gameplay_boards23.gd:139`), new `godot3d/tests/test_fog.gd`

**Interfaces:**
- Consumes: Task 6's `fog` key and `remembered` flag; `WorldFx.set_view`.
- Produces: `FogView` (pure helper `godot3d/scripts/world/fog_view.gd`): `parse(mask_string, w, h)`, `state_at(world_pos) -> int`, `is_visible(pos)`, `texture() -> ImageTexture` (L8, linear filter, soft edges, refreshed per poll); terrain darkens unseen (near-black, slight blue) and explored-not-visible (dim); enemy nodes appear/disappear without re-firing toasts or deploy effects (a `seen_ids` set); remembered buildings drawn dimmed and not selectable/attackable via picking; shots, hit/explode/collapse/dust and (Task 5) audio gated by `is_visible`; enemy-derived panels and minimap hostile marks use only known entities; copy rewritten from "Full battlefield, no fog of war" to the new truth.

- [ ] **Step 1: Failing tests:** `FogView` parsing and sampling; entity sync hides an unseen enemy and does not re-announce it on re-sight; remembered building is dim and not pickable; a shot with neither end visible draws nothing and plays no audio request; with `EARTHFRONT_FOG=0` / mask all-visible nothing changes versus today (SHA/idle captures equal); Survival untouched; the reworked wording tests assert the new copy.
- [ ] **Step 2: Implement** the shader mask (Kestrel ground shader only; the noise-ground variant stays fog-free), node sync, gating and panels; amend the docs that recorded "no fog".
- [ ] **Step 3: Gates, capture:** a software capture with fog showing shroud, explored dim and a visible enemy; also capture with fog off and confirm the idle scoreboard equals the pre-fog scores within 2.0.
- [ ] **Step 4: Commit,** append report.

---

### Task 8: Minimap interaction

**Files:**
- Modify: `godot3d/scripts/ui/game_ui.gd` (`_mount_minimap` ~131-216, mouse filter), `godot3d/scripts/ui/components/map_marks.gd`, `godot3d/scripts/ui/live_adapter.gd` (`_marks` ~611-640, `next_alert` link in `vm_gameplay.gd:147`), `godot3d/scripts/earthfront_3d.gd` (camera jump, alert position recording), `docs/ascension/ui-deviations.md` (lines ~295, 408), new `godot3d/tests/test_minimap_interaction.gd`

**Interfaces:**
- Consumes: Task 7's fog gating (pings only for events the player can see, which are always on own units), `minimap_world_rect`.
- Produces: click or drag on the minimap converts to a world point and moves the camera focus (clamped, ignores clicks outside the map rect); `AlertPing` marks (pulsing ring, 3 s) created when a human unit or building loses HP, deduplicated per 1.5 s radius 3 tiles, also feeding `next_alert`; `Space` jumps the camera to the latest alert (cycles older ones); layer tabs remain out of scope.

- [ ] **Step 1: Failing tests:** minimap click maps to the expected world point and moves the camera; clicks outside the rect do nothing; ping lifecycle (spawn, pulse, expire at 3 s); dedup; Space jumps to the newest alert and cycles; Survival minimap unchanged.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Gates, capture** (ping visible on the minimap), **commit,** report.

---

### Task 9: Building art distinction and target lean

**Files:**
- Modify: `tools/ui/build_building_variants.py` and `test_build_building_variants.py`, `godot3d/assets/world/sprites/` (regenerated composites + `.import`), `godot3d/scripts/world/world_sprites.gd` (target lean layer only), `godot3d/tests/test_world_sprites.gd`, `docs/ascension/ui-deviations.md`

**Interfaces:**
- Consumes: the existing deterministic composite pipeline (13 kinds: 7 board sprites + 6 composites).
- Produces: clearly distinct composites for alien supply depot, alien battery and vehicle factory (own silhouette via scaling/cropping of different parts, distinct signage/accent colours, kind-specific details); a unit "lean toward target" layer (small rotation about the base toward the current shot target for 0.25 s after a shot, composed as another pose layer over the rest, never changing pick parts or the ellipse).

- [ ] **Step 1: Failing tests:** composites for the three kinds differ from their source sprite and from each other by a measured structural metric (not just hue); generator deterministic and committed files match within tolerance; lean returns exactly to rest.
- [ ] **Step 2: Implement; produce a contact sheet** of all 13 human and alien building sprites next to the board sprites and open it in the report; be honest in the report about what still reads as a recolour.
- [ ] **Step 3: Gates, capture, score,** commit, report.

---

### Task 10: Docs, regression and playthrough check

**Files:** `docs/ascension/ui-deviations.md`, `docs/ascension/perf-2026-10-05.md` (or a new perf note), `docs/ascension/ui-mocks-gameplay/README.md` (one sentence), `NEXT_STEPS.md`, `tools/ui/world_scores.json` (re-baseline with `--write` only for intended changes), memory notes by the controller.

- [ ] **Step 1: Docs** for each phase (what changed, accepted limits, how to switch fog off, how to regenerate audio and fixtures); no em or en dashes.
- [ ] **Step 2: Full gates,** scoreboard vs `tff_scores.json` with each intended change listed, software perf budgets, Survival pair, `git diff --stat d81deab..HEAD -- crates/` lists only `scenario.rs` and `godot-bridge.rs`, golden hash green.
- [ ] **Step 3: Scripted playthrough on the private Xvfb** (real bridge, Kestrel, Dummy audio): deploy, build power plant and refinery, train a squad, survive wave 1; record the objective stages reached, first-contact time, fog behaviour and the audio director's play log (counts per id). Report anything broken.
- [ ] **Step 4: Commit,** final report with every number.
