# Design: N-Civ + Planetary Territory ("Stellar Conquest")

**Date:** 2026-06-13
**Status:** Approved (brainstorm complete; pending implementation plan)
**Project:** `military-rts-td` ("Ascension")

## 1. Goal & context

Ascension is a deterministic, real-time, autonomous Kardashev civilization
engine. The user wants to grow it toward **Civilization VII breadth while
keeping the real-time autonomous core** (direction "B": real-time + Civ breadth,
*not* a turn-based clone). The first slice toward that goal is the two
foundational systems that everything else (diplomacy, yields, ages) depends on:

1. **N civilizations** — replace the hardcoded two-player model with up to ~6
   civs.
2. **Planetary territory** — territory is quantized to whole **planets**, not
   gradient tile borders. Controlling a planet makes its entire area usable;
   civs contest planets through interplanetary war (Civ-style conquest).

This spec covers **only** those two systems plus the conquest mechanic that
links them. Per-tile yields/growth, diplomacy relations/UI, and Ages are
explicitly deferred to later specs (see §10).

### 1.1 Settled design decisions (from brainstorm)

- **Civ count:** up to ~6 (1 human + up to 5 AI). `Vec<Civ>` types, no hard cap
  baked into the type; tuned/tested at 6.
- **Territory unit:** the **planet**, with discrete per-planet ownership (one
  owner per planet — *not* per-tile gradient state).
- **Planet model:** "regions on one space map." The existing single hex map is a
  star-system; planets are large regions of tiles with open space between them.
  Units fly between planets across the same map, reusing A* pathfinding and
  real-time combat as-is.
- **Conquest rule:** **seat capture** — each planet has a capital seat (a
  CommandCenter). Capturing it transfers the whole planet (tiles + surviving
  buildings) to the attacker. Losing your last planet = elimination.
- **Territory enforcement:** build/expansion is gated to planets you control.

## 2. Architecture overview

Two changes, layered onto existing systems with maximal reuse:

- **Civs:** today's `Player` struct becomes `Civ`, and the fixed
  `players: [Player; 2]` array becomes a dense `civs: Vec<Civ>` indexed by civ
  id. Eliminated civs persist as `alive: false` slots (no free-list, stable
  hash order). One human civ; all other live civs run the existing
  `ai_commands` each tick.
- **Planets:** a new `planets: Vec<Planet>` arena on `Sim` holds mutable
  ownership. A *static* `planet_of` layer on `Map` maps each tile to its planet
  and is set once at procgen. Ownership lives on the `Planet` (one field);
  capture flips that one field and re-owners the planet's surviving buildings.

Both touch `state_hash` and therefore are **re-pin confirmation gates**, landed
as two separate commits (rule D8). The ordering is deliberate: the
high-blast-radius structural change (Migration 1) is designed to be
**hash-neutral**, isolating risk from the behavioral change (Migration 2).

### 2.1 Why this is low-risk relative to the deferred yields work

Planet ownership is **discrete and event-driven** — it mutates only on settle or
capture, never accrues per-tick. It therefore does **not** interact with the
`last_sync_tick` / closed-form / LOD machinery (rules D2/D3) that makes the
deferred growth/yields model a hard determinism gate. A Dormant colony skipping
ticks cannot desync a field that only changes on explicit events.

## 3. Data model

### 3.1 Civ identity

- `PlayerId` is **kept as the id type name** (every `owner: PlayerId` on entities
  and command variants is untouched — minimal churn) but its inner integer
  widens `u8` → `u16` to allow more than 2 ids. A `CivId` documents intent
  (alias or re-export of the same newtype).
- `PLAYER_COUNT` is deleted; civ count is dynamic (`civs.len()`).

### 3.2 `Civ` (renamed from `Player`, moved to `civ/mod.rs`)

Keeps all existing fields: `money`, `researched_techs`, `active_research`,
`era`, `energy`, `labour`, `active_perks`, `doctrine_levels`,
`unlocked_buildings`, `unlocked_units`. Adds (in Migration 2):

```rust
/// `false` once the civ owns no planets; the slot stays for stable hash order.
pub alive: bool,
```

`Sim` gains:

```rust
civs: Vec<Civ>,     // index = civ id; created at setup, never removed
human_civ: CivId,   // the local player (default 0); all other alive civs are AI
```

### 3.3 `Planet` (new module `game/planet.rs`)

```rust
pub struct PlanetId(pub u16);

pub struct Planet {
    /// Owning civ, or `None` for a neutral/unsettled planet.
    pub owner: Option<CivId>,
    /// The controlling CommandCenter (the capital). `None` when unsettled.
    pub seat: Option<EntityId>,
    /// Fixed-point world-space centre, used for AI distance reasoning.
    pub center: Vec2,
    /// Claim radius in world units; a tile belongs to this planet if its
    /// planet id (set statically at procgen) equals this planet's id.
    pub radius: Fixed,
}
```

`Sim` gains `planets: Vec<Planet>` (arena, created at procgen, not recycled).

### 3.4 Static tile → planet layer (on `Map`)

```rust
planet_of: Vec<Option<PlanetId>>,   // parallel to `tiles`, set once at procgen
```

with `Map::planet_at(x, y) -> Option<PlanetId>`. This layer is **static
terrain** and is **not** included in `state_hash` (consistent with how
`deposits` are handled today). All mutable ownership lives on `Planet.owner` in
the hashed `Sim` arena.

A tile is "open space" when `planet_at` is `None`; open space is unbuildable as
it already is today.

## 4. Behavior

### 4.1 Build-gating

A new helper `Sim::can_build_on(civ, x, y) -> bool` resolves
`map.planet_at(x, y)` to a planet and returns `true` iff that planet's
`owner == Some(civ)`. `apply_build` rejects builds on tiles the civ does not own
(open space and enemy/neutral planets both fail). The AI's site-selection logic
is constrained to owned tiles via the same helper.

### 4.2 Settling a neutral planet

`FoundColony` (existing command) now:

1. Resolves the target tile's planet; validates `planet.owner == None`.
2. Sets `planet.owner = civ`, `planet.seat = <new CommandCenter entity>`.
3. Calls the existing `add_colony`.

Neutral planets start **empty** (no defenders). Founding on an already-owned
planet is rejected.

### 4.3 Conquest — seat capture (Civ-faithful, intact capture)

The planet seat (a CommandCenter) has HP. When enemy combat would reduce a seat
to `<= 0` HP, it is **captured, not destroyed**:

1. `entity.owner = attacker`; HP restored to a small fraction (capture-HP
   fraction, e.g. 25%, sourced from `balance.ron`).
2. `planet.owner = attacker`; `planet.seat` unchanged (same entity, new owner).
3. Every surviving building on tiles belonging to this planet has its
   `owner` reassigned to `attacker` (tiles + buildings transfer).
4. The colony seated here transfers: `colony.owner = attacker`,
   `autonomy_level` reset to `0` (re-earned under the new owner),
   `policy` reset to default, `sector = None`.

**Attacker attribution is deterministic (rule D1):** the attacker is the civ of
the unit that landed the lethal blow. Combat already resolves in a fixed order;
simultaneous candidates are broken by **lowest `CivId`**. No `rng` is consulted.

### 4.4 Elimination & victory

A new `run_conquest` pass (or folded into the existing clear-dead pass)
recomputes, after captures: a civ is `alive` iff it owns ≥1 planet.

This **generalizes** the current whole-game CommandCenter loss check
(`has_cc`, `sim.rs:~1322`):

- **Win:** exactly one civ alive, or the human is the sole survivor.
- **Loss:** `human_civ` is not alive.

### 4.5 AI generalization

The AI loop iterates every `alive` civ where `id != human_civ` and runs the
existing `ai_commands(owner)`. For this slice, conquest AI is intentionally
conservative and deterministic:

- Prioritize **settling neutral planets** (expansion).
- Assault an enemy seat only with a strong local force advantage.

Pre-diplomacy, there is no war/peace state — relations are implicitly hostile
(free-for-all), gated only by the AI's conservative assault heuristic. War/peace
gating arrives with the diplomacy spec (Step 3) and will refine this.

## 5. Determinism & migrations

Two migrations, separate commits (rule D8). Each is a re-pin confirmation gate:
the hash delta is shown and the golden + `balance.ron` re-pinned **before**
landing, never autonomously.

### 5.1 Migration 1 — `Vec<Civ>` (expected hash-NEUTRAL; must verify)

- `state_hash`'s `for p in &self.players` becomes `for c in &self.civs`, writing
  the **same fields in the same order**, with **no new hashed fields**
  (`alive` is deferred to Migration 2).
- A `Vec<Civ>` of length 2 serializes byte-identical to `[Player; 2]`, so the
  2-civ golden replay hash is expected **unchanged**.
- **Gate:** run the golden + `rts-server` MATCH and confirm both are untouched.
  If the hash shifts, **stop** — a neutral migration that isn't neutral signals
  a hidden ordering bug; investigate before landing.
- This isolates the high-blast-radius, zero-behavior-change structural rewrite
  in its own commit.

### 5.2 Migration 2 — Planets + conquest + build-gating (re-pins)

`state_hash` appends, after the entities block:

```
for pl in &self.planets {
    owner       // 0 = neutral, else civ_id + 1
    seat        // present-flag + entity id
    center.x bits, center.y bits
    radius bits
}
for c in &self.civs { alive byte }   // added here, where planets give it meaning
```

The golden scenario now has home planets, so the hash changes → **re-pin**.
Show the before/after hash; re-pin the golden and `balance.ron` in the same
commit.

### 5.3 Determinism checklist for this slice

- **D1** (no `rng` under `civ/`): capture attribution uses combat order +
  lowest-`CivId` tiebreak; planet generation is procgen-seeded, not per-tick rng.
- **D2 / D3** (closed-form / LOD): **N/A** — ownership is event-driven, never
  accrued per-tick; no `last_sync_tick` interaction.
- **D5** (arena discipline): civs and planets are fixed at setup with **no
  free-list recycling**, so no LIFO/`swap_remove` hazard.
- **D6** (i128 saturating math): capture HP-fraction uses existing `Fixed`
  arithmetic; no new i128 accumulation paths.
- **D4 / D7 / D8**: single-source scores unaffected; second-colony golden pin
  still applies; each migration lands as its own re-pin commit.

## 6. Component / file map

| File | Change |
|---|---|
| `crates/core/src/game/civ/mod.rs` | `Player` → `Civ` (moved here); gains `alive: bool` (Mig 2). |
| `crates/core/src/game/planet.rs` | **New.** `PlanetId`, `Planet`, contains/distance helpers. |
| `crates/core/src/game/map.rs` | Add static `planet_of` layer + `planet_at()`. |
| `crates/core/src/game/sim.rs` | `civs: Vec<Civ>` + `planets: Vec<Planet>`; delete `PLAYER_COUNT`; generalize every `players[..]` / `[_; PLAYER_COUNT]`; seat-capture in the combat lethal-damage path; `run_conquest` (elimination + victory); build-gating in `apply_build` / `apply_found_colony`; AI loop over all live AI civs; widen `state_hash` (both migrations). |
| `crates/core/src/game/procgen.rs`, `scenario.rs` | Generate planet regions + assign tile planet ids; place each civ's home planet + seat; seed neutral planets. |
| `crates/data` / `balance.ron` | Planet count/radius, civ count, capture-HP fraction, starting layout. |
| `crates/render-shell/*` | Tint tiles by planet owner; HUD lists all civs (not just 2). Non-hashed → low risk; lands after core. |
| `crates/server` | Verify MATCH at each migration; no logic change. |

## 7. Testing

Per the project's per-milestone bar: `cargo test --workspace` + strict clippy
(`--all-targets -- -D warnings`, pedantic + nursery) + `cargo fmt --all -- --check`
+ `cargo run --release -p rts-server` (MATCH) + wasm build.

### 7.1 Migration 1

- All existing core tests pass **unchanged**.
- Golden hash **unchanged** (the §5.1 neutrality assertion).
- New: a 6-civ game runs and produces a **stable hash across two identical
  runs**.

### 7.2 Migration 2

- **Build-gating:** build on an unowned planet is rejected; the same build
  succeeds once the civ owns the planet; open-space tiles remain unbuildable.
- **Settling:** `FoundColony` on a neutral planet sets owner + seat and creates
  the colony; on an owned planet it is rejected.
- **Conquest:** enemy reduces a seat to `<= 0` → the seat flips owner at the
  capture-HP fraction (not destroyed); `planet.owner` flips; all surviving
  buildings on the planet re-owner; the colony transfers with autonomy reset
  to 0.
- **Elimination & victory:** a civ losing its last planet flips `alive = false`;
  victory fires when one civ remains; human elimination = loss.
- **Determinism:** capture/ownership replays identically; `lod_skip` on vs off
  produce identical hashes (trivially, since ownership is event-driven).
- **Golden re-pin** test at the new hash + server MATCH.

## 8. Risks & mitigations

- **Migration 1 not actually hash-neutral.** Mitigation: the neutrality test is
  the gate; if it fails, stop and find the ordering bug rather than re-pinning.
- **High blast radius of the `players[..]` rewrite.** Mitigation: pure
  mechanical generalization in its own commit, no behavior change, full test
  suite + server MATCH before landing.
- **Conquest attribution ambiguity** (who captured when multiple civs are
  present). Mitigation: deterministic rule — lethal-blow owner, lowest-`CivId`
  tiebreak; covered by a conquest test.
- **6-civ performance** (more per-tick AI command-gen + combat). Mitigation:
  the existing Dormant-colony LOD skip already bounds per-tick work; measure at
  6 civs and only add AI throttling if a hot path appears.

## 9. Success criteria

- A game runs with up to 6 civs (1 human + 5 AI), fully deterministic
  (identical hash across runs; server MATCH; `lod_skip` on == off).
- Civs can only build on planets they control.
- Neutral planets can be settled; enemy planets can be conquered by seat
  capture, transferring tiles + buildings + the colony.
- Losing the last planet eliminates a civ; the game resolves to a single
  survivor / human win-or-loss.
- Migration 1 lands hash-neutral; Migration 2 lands with a confirmed re-pin.
- Strict clippy + fmt + wasm build all green.

## 10. Out of scope (deferred follow-ups)

- **Per-tile yields & city growth** (the separate, higher-risk D3/closed-form
  gate — the next priority spec after this).
- **Diplomacy** relations/UI: war/peace, alliances, trade, espionage,
  city-states / independent powers (Step 3).
- **Annex-vs-raze** choice on capture.
- **Defended neutral planets** (independent powers / barbarians).
- **Multiple colonies per planet** (one seat per planet for this slice).
- **Ages / Legacy paths** and additional victory conditions.
- Richer culture-pressure organic borders (a possible later replacement for
  radius/region claiming).
