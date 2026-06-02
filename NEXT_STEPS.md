# Roadmap / next steps

The deterministic core, AI, lane-defense scenario, shells (desktop + web + touch),
server re-sim, data-driven balance, spatial-grid combat, recycling, save/replay,
and shell polish (build ghost, wave countdown, tracers) are all implemented, tested
(86+ tests), and committed.

The items below are scoped and ready, but deliberately left for focused follow-up
rather than rushed in at the end of a long session — each is a self-contained piece
of work the engine already supports cleanly.

## Tier 3 — content

### Air units + AA (completes the roster's rock-paper-scissors)
The design calls for air (helicopters) countered by dedicated anti-air. Path:
- `stats`: add `is_air: bool` to `UnitStats`; add `targets_ground: bool` +
  `targets_air: bool` to `AttackProfile` (existing entries: ground-only, so
  behaviour and the golden hash are unchanged).
- Add `UnitKind::Helicopter` and `BuildingKind::AaTurret`; grow the `Balance`
  arrays to `[UnitStats; 4]` / `[BuildingStats; 7]` and add the match arms in
  `balance`, `stats`, and `kind_tag`.
- `run_combat`: filter candidate targets by `is_air` vs the attacker's
  `targets_air`/`targets_ground` — air is hittable only by AA (and other air).
- `rts-data`: mirror the new fields; extend `balance.ron`.
- Recompute the golden hash only if existing units change (they shouldn't).

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
