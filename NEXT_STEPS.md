# Roadmap / next steps

The deterministic core, AI, a three-map scenario roster (Lane Defense, Open Clash,
Crossroads) with an in-game map-select screen, shells (desktop + web + touch),
server re-sim, deterministic lockstep PvP core, data-driven balance, spatial-grid
combat, recycling, save/replay, and shell polish (build ghost, wave countdown,
tracers) are all implemented, tested, and committed (run `cargo test --workspace` and the
Godot suite to see the current counts).

The items below are scoped and ready, but deliberately left for focused follow-up
rather than rushed in at the end of a long session - each is a self-contained piece
of work the engine already supports cleanly.

## Tier 3 - content

### Map roster + map-select - ✅ DONE
Three distinct scenarios, each a `Scenario` enum variant with `name`/`tagline`/
`build` and a shared `Scenario::ALL` the shell iterates:
- **Lane Defense** - funnelled lanes + escalating waves (the original). ~947-tick
  AI-vs-AI pace.
- **Open Clash** - wall-free open-field skirmish, no waves, two full bases. The
  fast brawl (~668 ticks).
- **Crossroads** - a central impassable fortress forcing flank pushes, with a
  distinct *siege* wave cadence (fewer/larger/slower waves). The grind (~962 ticks).
The title screen is now a map picker (hover/click, number keys `1` to `3`, or Enter);
the game-over overlay offers `M` to return to it. Generic tests assert every
scenario builds with two live bases, keeps the battlefield path-connected (no base
walled off), resolves decisively (no soft-lock), and replays deterministically;
further maps just add an enum variant + a builder.

### Balance polish - ✅ DONE
- **Playtest harness:** `cargo run -p rts-server -- playtest` runs AI-vs-AI across
  many seeds per map and reports win split, match length (min/med/max), stalemate
  rate, and peak army size - the data that drives tuning.
- **Side-relative AI expansion:** `find_buildable_near` now expands *away from the
  enemy* (defensive, symmetric) instead of toward a fixed world direction, so the
  AI plays a corner base the same on either side.
- **Unit roster** verified via `-- balance`: a clean ground RPS triangle
  (Infantry → AntiArmor → Tank → Infantry) with tight margins; Helicopter dominant
  over all ground but countered by AA turrets (the AI builds them on detecting air).
- Note: the AI is a deterministic pure function of state (no RNG) - this is what
  keeps lockstep replays bit-identical, so AI-vs-AI on a symmetric map is a fixed
  outcome by design, not a balance bug. The human plays P0 with full control.

### Air units + AA - ✅ DONE
Helicopter (flies straight over terrain, only killable by anti-air) + AA turret,
with `is_air`/`targets_ground`/`targets_air` driving combat targeting. The AI
builds AA when it detects enemy aircraft. Golden hash unchanged; covered by tests.
Adversarial review confirmed it determinism-safe. Two low-priority polish notes
from that review remain open:
- Air units can overlap in flight (no separation) - cosmetic; add light
  repulsion or document as intentional.
- `balance.ron` has no schema version; hand-edited *old* files missing the new
  per-attack flags would default to ground-only. New entries are required fields
  (so they fail loudly), but a version tag / validation would be tidier.

### Full battlefield intelligence - locked direction
Ascension deliberately has **no fog of war**. Full visibility is a defining rule:
strategy comes from economy, force composition, positioning, wave pressure, and
real-time science choices rather than hidden information. Do not add a
per-player visibility system.

**Reversed 2026-10-06 for Kestrel Reach only (plan
`docs/superpowers/plans/2026-10-06-kestrel-next-level.md`, Tasks 6 and 7; the
user approved the spec that flagged this reversal).** Kestrel Reach now has a
fog of war that is presentation only: the bridge computes the human side's
sight per snapshot write and sends a per-cell mask plus only the enemies in
sight (structures seen once stay as dimmed memories); the client shades the
ground and props by the mask and gates effects and sounds by it. The sim, its
combat and the AI stay omniscient and deterministic; nothing in `crates/core`
reads the fog, and replays and hashes are unchanged. Survival keeps full
visibility. Kill switch: `EARTHFRONT_FOG=0` (also `off` or `false`) when
starting the bridge gives Kestrel an all-visible mask and the client draws
exactly as before fog.

## Deferred (bigger / environment-bound)

### PvP netcode (lockstep) - ✅ CORE DONE
The deterministic **lockstep session core** is implemented, tested, and proven
end-to-end (see `docs/NETCODE.md`):
- `crates/core/src/game/lockstep.rs` - `Lockstep` + `InputFrame`: per-turn input
  exchange, configurable input delay, turn gating (advance only when all players'
  inputs are present), and desync detection via the existing `state_hash` checksum.
- `cargo run -p rts-server -- lockstep` runs **two in-process peers** through a full
  match - each computing only its own player's input, exchanging frames under a
  3-turn delay - and they stay bit-identical every turn. Tests also assert the P2P
  outcome bit-matches the authoritative single-player replay at zero delay.

Remaining is **deployment infrastructure** (not game logic, and environment-bound):
a `Transport` trait in the shell with WebSocket (browser) and TCP (native) impls,
and a small matchmaking/relay service that pairs players, agrees a seed, forwards
`InputFrame`s, and collects periodic checksums. Adaptive input delay and
reconnect/forfeit layer on top of the existing stall semantics. All scoped in
`docs/NETCODE.md`.

### Mobile store submission
Touch input and `cargo-apk` config are in place (see `MOBILE.md`). Producing a
signed APK/IPA and submitting needs the Android SDK/NDK, macOS + Xcode, and
Apple/Google developer accounts - not available in a headless CI box.

## The biggest lever remains: playtest for fun
Everything above is content/feature scaffolding. The highest-value ongoing work is
running the lane-defense scenario, tuning `balance.ron` (no recompile), and
adjusting lane/wave design until the attack/defend loop is genuinely engaging.

## Kestrel Reach and the gameplay HUD (2026-10, branch gameplay-hud-kestrel-reach)

State: Kestrel Reach (`godot-bridge --scenario kestrel`) and the twelve gameplay boards are built and checked against the
mocks in `docs/ascension/ui-mocks-gameplay/`; every deviation is listed in `docs/ascension/ui-deviations.md` (section 4,
"Live QA and cleanup"). Survival shows none of the new ground UI (its ground layer is flat Grassland), but it is not unchanged: it is an Earthfront
scenario, so it gets the refinery +20% ore bonus and its state hash now includes the ground layer. Legacy non-Earthfront
scenarios are unchanged, and the golden hash is unmoved.

Open items, in rough order of value:
- Play Kestrel on a real GPU. Live QA ran at about 3 fps under software GL, so frame pacing, hover latency and shadow
  strength were never judged, and no run reached a win (every colony fell within three waves). Balance for a human player on
  this map is untested.
- Show "River +12 kW" on the selected structure's terrain card. Today it appears on the hover inspector (nothing selected),
  the Yield lens and the briefing only.
- Yield lens legend swatches render as empty boxes.
- Missing sim mechanics the mocks assumed, deliberately not faked: fog (fog added for Kestrel 2026-10-06, see above),
  "across the river -25%", multi-hex footprints, Cancel last, Resupply, Focus fire, per-minute yields, a wave composition
  list, a campaign or checkpoint.
- Make `run-3d.sh` pass a scenario to the bridge (today it passes its arguments to Godot only), so Kestrel starts with one
  command.
- Supply lens needs a stocked depot with a building in reach; with none it is hidden by design.

## Kestrel next level (2026-10-06, branch kestrel-next-level)

State: plan `docs/superpowers/plans/2026-10-06-kestrel-next-level.md` is built (Tasks 1 to 10). Kestrel Reach now has
truthful HUD icons, a prebuilt opening (CC, Power Plant, Refinery, Barracks, one Harvester, 4 riflemen, 1200 credits)
with a scripted alien probe at about 1:55 and wave one at 2:30, five live objectives, a generated sound set behind an
audio director, presentation-only fog of war (reversal note above), a clickable minimap with alert rings and Space to
jump, three redrawn buildings and a short aim lean on firing units. Every change is listed in
`docs/ascension/ui-deviations.md` (section 9, one subsection per task); perf is in `docs/ascension/perf-2026-10-06.md`.
Rust changes are confined to `crates/core/src/game/scenario.rs` and `crates/server/src/bin/godot-bridge.rs`; Survival
and the golden hash are unchanged.

Still owed, in rough order of value:
- A listening pass. Nothing was ever played aloud: every run used `--headless` or `--audio-driver Dummy`. Levels, panner
  widths, the 9 dB duck, pitch variance and loop levels are reasoned numbers checked by tests and the `[audio]` log.
- GPU perf and look. All numbers and captures are software GL (llvmpipe) on a private Xvfb. The fog shader branches, the
  near-black shroud on a real gamma, the idle frame budget (10 ms p50) and the lean in motion were not checked on the RTX 3050.
- Deposit pins and the tile inspector still show over unseen ground (the bridge sends the briefing survey's deposits). A
  `resource_pins` filter on `FogView.state_at` would hide them until explored.
- Recolour limits: both antimatter plants, the alien vehicle factory, the human depot and battery pair, the shared
  airfield layout and the labs (CC plus a dome) still read as recolours (Task 9's measured list).
- Long-hitch death silence: after a poll gap over about 20 ticks a unit killed near the sight rim with no drawn shot may
  vanish without an explosion (the fog silence heuristic's reach caps at 2.0 world units).
- Idle riflemen do not defend a structure under attack (the alert only informs); the probe ids 9 to 11 are fixed
  constants; only the bridge calls `Scenario::scripted_commands`, so another Kestrel host must add that call.
- Accepted fog leaks from the final review, behaviour unchanged (fix round 2026-10-06):
  - M1: `wave_route` is pathed by `find_path` over the real map, so a hidden alien structure (`Tile::BLOCKED`) can bend
    the drawn route although its cell is withheld from `blocked`. Fix later by pathing over hidden cells as ground, or by
    caching the tick-0 route in `FogState`.
  - M2: an incoming tracer from an attacker in a dark cell starts at the attacker's true position, which shows its
    direction and rough range. Arguably intended (fire shows where it comes from); otherwise start it at the sight edge.
  - M4: a non-empty fog mask of the wrong length (bridge and client version skew) is read as no fog with no warning, so
    the whole alien side shows. Fix later with one latched `push_warning`, like the ground-layer check.

How to:
- Regenerate the audio: `python3 tools/audio/build_sfx.py` (writes `godot3d/assets/audio/sfx/`, byte-identical on a
  rerun), then refresh the imports silently with
  `tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --audio-driver Dummy --path godot3d --import`. The import
  creates untracked `*.gd.uid` files and can rewrite `godot3d/default_bus_layout.tres`; delete the new uid files and
  `git checkout` the bus layout before committing. Never audition the files through the speakers on a shared machine.
- Regenerate the Kestrel fixtures (release build first, `cargo build --release --offline --bin godot-bridge`):
  `target/release/godot-bridge --scenario kestrel --dump-snapshot godot3d/tests/fixtures/kestrel_snapshot.json` (fogged
  start) and its fog-off twin
  `EARTHFRONT_FOG=0 target/release/godot-bridge --scenario kestrel --dump-snapshot godot3d/tests/fixtures/kestrel_snapshot_fog_off.json`.
  Both are deterministic (rerunning them on 2026-10-06 rewrote identical bytes).
- Switch fog off: start the bridge with `EARTHFRONT_FOG=0` (also `off` or `false`). It is read once at bridge start;
  the client then draws exactly the pre-fog frame. The idle scoreboard gate is captured fog off.
- Run the Kestrel QA, always on a private Xvfb with the Dummy audio driver (the launchers pass it; a test pins that):
  `python3 tools/qa/launch_ui.py <dir> --software --display :94 --scenario kestrel` and drive it with
  `tools/qa/ui_client.py`; add `EARTHFRONT_AUDIO_LOG=1` to the environment to get one `[audio]` line per sound start in
  `<dir>/godot.log`. World frames for the scoreboard:
  `EARTHFRONT_FOG=0 python3 tools/qa/world_capture.py <dir> --software --display :94`, then
  `python3 tools/ui/world_diff.py run --mocks <mocks> --live <dir> --out <side dir> --check tools/ui/world_scores.json`.
  Never pass `--gpu` without `--allow-user-display` (it opens a window on the user's display).

## Kestrel depth (2026-10-07, branch `kestrel-depth`)

State: plan `docs/superpowers/plans/2026-10-07-kestrel-depth.md` is built (Tasks 1 to 30). Kestrel Reach is the default
map and the game is version 0.2.0. Behind a core `depth` flag (on for the hosted Kestrel match only) it adds unit stances,
Stop, Hold and focus fire, Shift-queued waypoints, breach pathing and siege, abilities and Upgrades, repair over time,
a ten-wave alien table with an elite sixth wave and a shielded Core Node, Easy / Normal / Hard with a match seed, a score
and grade with personal bests, a twelve-wave run mode with perk drafts and a daily seed, RPL1 replays with an in-game viewer
and `verify-run`, a client that starts its own bridge, export presets and a packaging script, an onboarding coach, building
damage states and music hooks with no tracks. Survival, the golden hash and the classic Kestrel hash are unchanged
(pinned by tests). The per-task record is `.superpowers/sdd/2026-10-07-kestrel-depth/` (local, not in git); UI choices
that differ from the mocks are in `docs/ascension/ui-deviations.md`.

Owed to you (an agent cannot or must not do these):
- **Listening pass.** No person has heard any of the 26 sounds; every agent run used `--headless` or the Dummy audio
  driver. Run `python3 tools/audio/listen_pass.py --notes listen-notes.txt` from a terminal (it asks for `yes`, then plays
  one sound at a time; `--list` plays nothing).
- **GPU run.** Every frame time, draw call count and capture is software GL (llvmpipe) on a private Xvfb. Run
  `tools/perf/gpu_frametime.sh --allow-user-display` on the RTX 3050 (it opens a window on your display; `--dry-run` with
  the flag only prints the plan). Its GPU launch path has never been executed, so the first run may need small fixes.
- **Export templates and the Windows test.** Install the Godot 4.7.2 export templates, then
  `tools/release/package.sh linux` and the template smoke from `docs/release/itch-checklist.md`; the Windows build also
  needs the `x86_64-pc-windows-gnu` Rust target and MinGW, and a test on a Windows machine (a hard-killed game there leaves
  the bridge running: `--exit-with-parent` is a no-op on Windows). Only `--export-pack` was tried (575 files, 32.1 MB).
- **Music tracks.** There are none. `godot3d/scripts/audio/music_director.gd` already picks menu, calm, combat (on a seen
  shot, held 8 s after the last one), victory or defeat on Kestrel; add a `res://` path per state to its `TRACKS` table and
  it plays on the Music bus (ducked by the SFX director, scaled by the Music volume). The test that pins "no player" must
  change with it.
- **Art approvals.** `docs/release/art-approvals.md`: the buildings that still read as recolours and every new visual of
  this program, each with how to see it and a Pass / Fail column.
- **License decision and notices.** There is no LICENSE file and Cargo says `Proprietary`. Before a public upload add the
  full SIL OFL 1.1 text for Rajdhani and IBM Plex and Godot's MIT notice with its third-party notices to `licenses/`
  (itch checklist section 8).
- **Asset provenance audit.** Confirm the origin and license of every shipped asset (Kenney CC0 kits, fonts, generated
  sprites and sounds) before upload.
- **itch upload.** `docs/release/itch-checklist.md`, after the items above.
- **Merge order.** The repository has no git remote, so neither branch exists anywhere but this machine. `master`
  (b0757db) is an ancestor of `kestrel-next-level` (67e6355, 164 commits ahead), which is an ancestor of `kestrel-depth`
  (56 commits ahead of it). Merge `kestrel-next-level` into `master` first, then `kestrel-depth`; both are fast-forwards.
  Add a remote and push both branches as a backup before anything else.
- **macOS export.** Later: it needs a preset, signing and notarisation, and the bridge's parent watch is untested there.

Owed from the program's task record (small, found and left on purpose):
- Run mode: the alien base is razed by waves 3 to 4 in automated runs (its Upgrades stall at [3, 3, 3]); the default
  perk pool runs out after 8 drafts, so waves 9 to 11 offer none; the AI ignores Capital Discount; Early Tooling and Field
  Upgrade can be drafted with no effect; an idle new player never sees a draft and the coach has no lesson for runs.
- The Units deck has no Capital card (the `X` key only).
- The Replays list cannot show victory or defeat (RPL1 has no result field); `verify-run` certifies consistency and score,
  not fog legality or authorship (the END line is unsigned); `match.json` keeps the picker seed beside a replay.
- Stance can show on harvesters in the selection panel; the core ignores stance commands for them.
- Repair: the client checks only the cooldown before sending, not the price or a building already at full HP (the core
  refuses those with no on-screen reason).
- Hold units stay stacked; units ordered together travel stacked until they stop; the target marker is static.
- The assault layout and the Orders deck have no Stop / Hold cards; the Controls screen has no row for Shift-queue.
- The last queued leg's path is not drawn; path lines are thin.
- The client combat preview ignores the air / ground split (AntiArmor does 80% to air under depth, not the shown figure).
- The `core_shielded` flag and the stage-5 text can reveal an unseen relay loss under fog once wave 6 has spawned, and
  the stage-5 Core Node text is wrong for runs.
- Score: a death credits the opponent even for friendly fire; the first record is always "New best" (even 0); records
  are keyed by map and difficulty, not seed; no real victory was ever captured (the screenshot is crafted).
- Hard cannot reach the 15 to 25 minute window (the playtest is overrun after 4 waves); the playtest human banks 8,000 to
  14,000 credits late; the result does not depend on the seed (the AI's anti-armour override).
- Feedback: a locked Units card has no hit area, so no "denied" cue on click; a full producer queue drops silently;
  `wave_cleared` may stay silent under fog; the HUD layout can mismatch after a debrief Restart.
- Coach: no Settings toggle to re-enable it after "Never show again"; the combat preview can float over its card; a
  group double tap posts two toasts.
- Title and picker: Quit stays focusable under the picker; no timeout if `restart.flag` is never cleared; the debrief
  says Operation Dawnshield on both maps; Tab can reach buttons under Settings.
- Building states: an HP bar can show on an unseen live building; the fog check runs per snapshot.
- Debrief (seen in the Task 30 playthrough): after "Headquarters lost" the What failed panel still reads HQ integrity
  INTACT, Power BALANCED and Depot ammo STOCKED, and the title says Operation Dawnshield on Kestrel.
- Bridge: the breach cache can go stale if a route opens on the same tile; the replay fingerprint cannot see sim changes
  that no probe run reaches; Armour and Bulwark do not stop Barrage (documented).
- Music: with tracks added, combat starts on any shot the player can see, including a lone turret plinking a probe; tune
  `COMBAT_ENTER_S` and `COMBAT_HOLD_S` by ear.

How to (kestrel-depth):
- Verify a replay: `target/release/verify-run <file.rpl>` prints MATCH (exit 0), MISMATCH (exit 1) or why the file is
  unverifiable (exit 2). Replays are in `user://replays` (on Linux `~/.local/share/godot/app_userdata/Ascension- Earthfront 3D/replays`).
- Package: `tools/release/package.sh [linux|windows|all]` (needs the export templates); `--export-pack` works without them.
