# Roadmap / next steps

The deterministic core, AI, a three-map scenario roster (Lane Defense, Open Clash,
Crossroads) with an in-game map-select screen, shells (desktop + web + touch),
server re-sim, deterministic lockstep PvP core, data-driven balance, spatial-grid
combat, recycling, save/replay, and shell polish (build ghost, wave countdown,
tracers) are all implemented, tested (101 tests), and committed.

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
- Missing sim mechanics the mocks assumed, deliberately not faked: fog, "across the river -25%", multi-hex footprints,
  Cancel last, Resupply, Focus fire, per-minute yields, a wave composition list, a campaign or checkpoint.
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
