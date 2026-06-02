# Roadmap / next steps

The deterministic core, AI, lane-defense scenario, shells (desktop + web + touch),
server re-sim, data-driven balance, spatial-grid combat, recycling, save/replay,
and shell polish (build ghost, wave countdown, tracers) are all implemented, tested
(86+ tests), and committed.

The items below are scoped and ready, but deliberately left for focused follow-up
rather than rushed in at the end of a long session — each is a self-contained piece
of work the engine already supports cleanly.

## Tier 3 — content

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

### Fog of war
Per-player visibility so you only see what your units/buildings reveal. Path:
- Compute a per-player visible tile set each tick from entity positions + sight
  radius (deterministic, in-core).
- Extend `views()` with a `for_player` variant that hides entities on
  non-visible tiles; the shell renders unseen areas dimmed.
- Keep it out of the state hash (visibility is derived).

## Deferred (bigger / environment-bound)

### PvP netcode (lockstep)
The hard prerequisite — a deterministic core with an input-log replay that the
server already validates — is done. Remaining: a lobby/matchmaking service, a
per-tick input exchange with a small input delay, lockstep turn synchronization,
and desync detection via the existing `state_hash`. This is a multi-week
networking effort and should follow proof that the single-player loop is fun.

### Mobile store submission
Touch input and `cargo-apk` config are in place (see `MOBILE.md`). Producing a
signed APK/IPA and submitting needs the Android SDK/NDK, macOS + Xcode, and
Apple/Google developer accounts — not available in a headless CI box.

## The biggest lever remains: playtest for fun
Everything above is content/feature scaffolding. The highest-value ongoing work is
running the lane-defense scenario, tuning `balance.ron` (no recompile), and
adjusting lane/wave design until the attack/defend loop is genuinely engaging.
