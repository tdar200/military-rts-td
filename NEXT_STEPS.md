# Roadmap / next steps

The deterministic core, AI, a three-map scenario roster (Lane Defense, Open Clash,
Crossroads) with an in-game map-select screen, shells (desktop + web + touch),
server re-sim, deterministic lockstep PvP core, data-driven balance, spatial-grid
combat, recycling, save/replay, and shell polish (build ghost, wave countdown,
tracers) are all implemented, tested (101 tests), and committed.

The items below are scoped and ready, but deliberately left for focused follow-up
rather than rushed in at the end of a long session — each is a self-contained piece
of work the engine already supports cleanly.

## Tier 3 — content

### Map roster + map-select — ✅ DONE
Three distinct scenarios, each a `Scenario` enum variant with `name`/`tagline`/
`build` and a shared `Scenario::ALL` the shell iterates:
- **Lane Defense** — funnelled lanes + escalating waves (the original). ~947-tick
  AI-vs-AI pace.
- **Open Clash** — wall-free open-field skirmish, no waves, two full bases. The
  fast brawl (~668 ticks).
- **Crossroads** — a central impassable fortress forcing flank pushes, with a
  distinct *siege* wave cadence (fewer/larger/slower waves). The grind (~962 ticks).
The title screen is now a map picker (hover/click, number keys `1`–`3`, or Enter);
the game-over overlay offers `M` to return to it. Generic tests assert every
scenario builds with two live bases, keeps the battlefield path-connected (no base
walled off), resolves decisively (no soft-lock), and replays deterministically;
further maps just add an enum variant + a builder.

### Balance polish — ✅ DONE
- **Playtest harness:** `cargo run -p rts-server -- playtest` runs AI-vs-AI across
  many seeds per map and reports win split, match length (min/med/max), stalemate
  rate, and peak army size — the data that drives tuning.
- **Side-relative AI expansion:** `find_buildable_near` now expands *away from the
  enemy* (defensive, symmetric) instead of toward a fixed world direction, so the
  AI plays a corner base the same on either side.
- **Unit roster** verified via `-- balance`: a clean ground RPS triangle
  (Infantry → AntiArmor → Tank → Infantry) with tight margins; Helicopter dominant
  over all ground but countered by AA turrets (the AI builds them on detecting air).
- Note: the AI is a deterministic pure function of state (no RNG) — this is what
  keeps lockstep replays bit-identical, so AI-vs-AI on a symmetric map is a fixed
  outcome by design, not a balance bug. The human plays P0 with full control.

### Air units + AA — ✅ DONE
Helicopter (flies straight over terrain, only killable by anti-air) + AA turret,
with `is_air`/`targets_ground`/`targets_air` driving combat targeting. The AI
builds AA when it detects enemy aircraft. Golden hash unchanged; covered by tests.
Adversarial review confirmed it determinism-safe. Two low-priority polish notes
from that review remain open:
- Air units can overlap in flight (no separation) — cosmetic; add light
  repulsion or document as intentional.
- `balance.ron` has no schema version; hand-edited *old* files missing the new
  per-attack flags would default to ground-only. New entries are required fields
  (so they fail loudly), but a version tag / validation would be tidier.

### Full battlefield intelligence — locked direction
Ascension deliberately has **no fog of war**. Full visibility is a defining rule:
strategy comes from economy, force composition, positioning, wave pressure, and
real-time science choices rather than hidden information. Do not add a
per-player visibility system.

## Deferred (bigger / environment-bound)

### PvP netcode (lockstep) — ✅ CORE DONE
The deterministic **lockstep session core** is implemented, tested, and proven
end-to-end (see `docs/NETCODE.md`):
- `crates/core/src/game/lockstep.rs` — `Lockstep` + `InputFrame`: per-turn input
  exchange, configurable input delay, turn gating (advance only when all players'
  inputs are present), and desync detection via the existing `state_hash` checksum.
- `cargo run -p rts-server -- lockstep` runs **two in-process peers** through a full
  match — each computing only its own player's input, exchanging frames under a
  3-turn delay — and they stay bit-identical every turn. Tests also assert the P2P
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
Apple/Google developer accounts — not available in a headless CI box.

## The biggest lever remains: playtest for fun
Everything above is content/feature scaffolding. The highest-value ongoing work is
running the lane-defense scenario, tuning `balance.ron` (no recompile), and
adjusting lane/wave design until the attack/defend loop is genuinely engaging.

## Kestrel Reach and the gameplay HUD (2026-10, branch gameplay-hud-kestrel-reach)

State: Kestrel Reach (`godot-bridge --scenario kestrel`) and the twelve gameplay boards are built and checked against the
mocks in `docs/ascension/ui-mocks-gameplay/`; every deviation is listed in `docs/ascension/ui-deviations.md` (section 4,
"Live QA and cleanup"). Survival is unchanged and shows none of the new ground UI. The golden hash is unmoved.

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
