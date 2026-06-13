# Design: Cities, Food & Population Growth

**Date:** 2026-06-13
**Status:** Approved (brainstorm complete; pending implementation plan)
**Project:** `military-rts-td` ("Ascension")
**Predecessor:** `2026-06-13-n-civ-planetary-territory-design.md` (N-civ + planetary
territory — DONE). This is the next "Civ-7 breadth" slice: the **Cities & tile
yields** priority.

## 1. Goal & context

Ascension is a deterministic, real-time, autonomous Kardashev civilization
engine. Direction "B" (real-time + Civ breadth) is in progress. Planetary
territory (own whole planets, conquer by seat capture) shipped. This slice adds
the **city layer**: per-colony **Population** that **grows** from a **Food** yield
sourced from **per-tile terrain**, where population is the central colony stat
(it scales output, supply, build capacity, and autonomy speed).

The cardinal constraint is **determinism**, specifically rule **D3**: a `Dormant`
colony skips its per-tick work and is caught up in exact closed form, and the
skip-path state hash must equal the full-path hash every tick. The entire design
is shaped to keep growth (the non-linear part) off the closed-form path.

### 1.1 Settled decisions (from brainstorm)

- **Add Food (per-colony) + Population (per-colony `u32`)**, leaving the empire
  Money/Energy/Labour triad in place.
- **Yield source:** per-tile **terrain** (a new static, non-hashed `Map` layer,
  like `deposits`/`planet_of`), summed over the colony's owned planet + buildings.
- **Population drives all four:** resource output scaling, military supply, a
  building-count capacity cap, and autonomy-earning speed.
- **Population cap** = `base(planet tile count) + housing buildings`.
  **Maturity** = `population == cap`.
- **Growth** = a Civ-style food box with a rising threshold; runs **only while a
  colony is Active** (never on the closed-form path).
- **Output channel:** a **per-colony treasury**. Developing (immature) colonies
  feed the empire pool each tick; mature colonies self-fund (bank output in their
  treasury, closed-form). Mode is keyed on **maturity**, not the LOD class.

## 2. Architecture overview

- **New per-colony state** (`Colony`): `population: u32`, `food: Fixed`,
  `treasury: [Fixed; 3]`.
- **New static terrain layer** (`Map`): `terrain: Vec<TerrainKind>`, set at
  procgen, **not hashed** (same treatment as `deposits`/`planet_of`).
- **Non-hashed per-planet yield cache** (`Sim.planet_yield`): each planet's tile
  yields summed once at setup, so per-tick rate lookups are O(1).
- **The maturity rule** (one change to `colony_lod`): a colony is `Dormant` only
  when **mature** (`population >= cap && earned_autonomy >= AUTONOMY_FULL`) and
  not threatened. Therefore immature colonies are always `Active` and never
  skipped → growth always runs full-fidelity.
- **Closed-form treasury**: `materialize_colony` gains one constant-rate term
  (`treasury[k] += rate(k) × elapsed`) for mature colonies, mirroring the
  existing Field-stockpile line. Mature output rate is **purely
  `pop_factor(population) × planet_yield`** (terrain × population), independent of
  live building count, so it is provably constant during a Dormant window.

### 2.1 Why this respects D3 (the key argument)

The closed form is exact only when a Dormant colony's per-tick deltas are
constant over the skipped window. This design guarantees that:

1. **Growth is non-linear, so it must never be skipped.** The maturity rule
   ensures immature (growing) colonies are always `Active` (full per-tick path).
   Growth uses any formula with zero closed-form concern.
2. **Mature colonies have constant deltas.** Population is frozen at `cap`; the
   output rate is `pop_factor(cap) × planet_yield`, both constant; the terrain
   yield is static map data. Buildings are deliberately excluded from the mature
   rate, so a building change can never perturb a skipped window.
3. **Threat forces full fidelity.** A threatened colony is `Tactical` (processed
   every tick), never `Dormant`, so any combat-driven change happens on the full
   path.
4. **Frozen fields need no reconstruction.** Food/population don't change while
   mature, so the hash reads them as stored; only the treasury accrues and is
   reconstructed (read-only) in the hash, exactly like the Field stockpiles.

## 3. Data model

### 3.1 `Colony` additions (`civ/mod.rs`)

```rust
/// City size. Starts at 1; grows from food while Active; capped at colony_cap.
pub population: u32,
/// Food box: accumulates the colony's food rate; on reaching the population
/// threshold, increments population and subtracts the threshold.
pub food: Fixed,
/// Banked Money/Energy/Labour output for a *mature* (self-funding) colony.
/// Accrues at a constant rate (closed-form, D2). Indexed Money/Energy/Labour.
pub treasury: [Fixed; 3],
```

`last_sync_tick` (existing) continues to anchor the closed form.

### 3.2 Terrain (`map.rs`)

```rust
pub enum TerrainKind { /* e.g. Barren, Fertile, Rich, ... */ }
// each carries (food, money, energy, labour) base per-tile yields (from balance)

// on Map (static, NOT hashed):
terrain: Vec<TerrainKind>,            // parallel to tiles, set at procgen
// + terrain_at(i32,i32) -> TerrainKind, set_terrain(u16,u16,TerrainKind)
```

### 3.3 Per-planet yield cache (`sim.rs`, non-hashed)

```rust
// derived once from the static terrain + planet_of layers at setup:
planet_yield: Vec<TileYield>,   // indexed by PlanetId; (food, money, energy, labour) sums
```

Not hashed (pure function of static map data).

## 4. Mechanics

### 4.1 Derived quantities (pure functions of hashed state + static map)

- `colony_cap(ci)` = `housing_base(planet tile count) + Σ housing buildings on the
  colony's planet`.
- `mature(ci)` = `population >= colony_cap(ci) && earned_autonomy >= AUTONOMY_FULL`.
- `colony_food_rate(ci)` = `planet_yield[planet].food` (+ food buildings, Active
  only).
- `colony_output_rate(ci, k)` (mature steady state) =
  `pop_factor(population) × planet_yield[planet][k]`. **No live-building term** —
  this is what makes it constant during Dormancy.

`pop_factor`, the food `threshold(population)`, `housing_base`, per-`TerrainKind`
yields, `supply_per_pop`, and `buildings_per_pop` are all `Balance` constants
(also mirrored in `balance.ron`).

### 4.2 Growth (Active-phase only)

In `run_colony_accrual`, for each processed (non-skipped) colony, **after**
`materialize_colony`, if the colony is **immature**:

```
food += colony_food_rate(ci)              // per-tick (elapsed is always 1 here)
while food >= threshold(population) {
    food -= threshold(population);
    population += 1;
}
// feed this colony's gross output to the empire pool (real-time income):
civ.money/energy/labour += colony_output_rate(ci, k)   // immature → empire pool
```

Immature colonies are always `Active` (maturity rule), so this is always an
elapsed-1 path; no closed form is involved.

**The existing `run_economy` income is unchanged** (deposit mining → Money,
building energy/labour output). The colony terrain output added here is an
**additional, terrain-based** income source, not a replacement — and because the
mature/immature output rate is `pop_factor × planet_yield` (terrain only, no
building term), it never double-counts the building income that `run_economy`
already provides. Crucially, the golden replay has zero colonies, so this entire
pass is a no-op there (preserving golden-neutrality, §5).

### 4.3 Mature colonies (closed-form treasury)

`materialize_colony(ci, next)` (existing) gains, for **mature** colonies only:

```
let rate = colony_output_rate(ci, k);     // constant (pop=cap, terrain static)
treasury[k] = saturate(treasury[k] + rate × elapsed)   // i128, D2/D6
```

Mature colonies bank into `treasury`; they do **not** feed the empire pool. (The
empire pool is fed only by immature colonies, §4.2.) Autonomous *spending* of the
treasury is deferred (§7).

### 4.4 The four population effects

| Effect | Mechanism | Determinism |
|---|---|---|
| Output scaling | rate = `pop_factor(population) × planet_yield` | constant once mature → closed-form exact |
| Military supply | `supply_cap += supply_per_pop × population` summed over a civ's colonies | derived on demand from hashed pop; constant when mature |
| Building capacity | a colony holds ≤ `buildings_per_pop × population` buildings — gates Build/auto-build | build-time gate (like the planet build-gate); no accrual |
| Autonomy speed | the `materialize` `autonomy_progress += 1` term becomes `+= pop-scaled rate` | mature ⇒ pop constant ⇒ constant rate; already in the closed form |

### 4.5 `colony_lod` change (the maturity rule)

```rust
// threatened → Tactical (unchanged)
// else if mature(ci) → Dormant      (was: earned_autonomy >= AUTONOMY_FULL)
// else → Active
```

## 5. Determinism & migration

- **D1:** no `rng` — all rates/thresholds are pure functions of hashed state +
  static map.
- **D2 / D6:** treasury closed form widens to `i128` and saturates, bit-identical
  to `elapsed` sequential adds (mirrors the Field-stockpile line).
- **D3:** skip-path hash == full-path hash every tick. Guaranteed by §2.1: growth
  never skipped; mature deltas constant; treasury reconstructed read-only in the
  hash; food/population frozen while mature.
- **Re-pin expectation — golden NEUTRAL (verify).** All new hashed state is on
  `Colony`. The golden replay (`golden_hash_pins_cross_target_determinism`)
  creates **zero colonies**, so the per-colony additions emit no bytes and the
  golden hash should stay `17_495_389_389_365_438_884`. The implementer MUST
  verify this and confirm no other *pinned-constant* hash test instantiates
  colonies. Survival/conquest determinism tests do have colonies but compare
  run-to-run (not pinned), so they stay green. If a pinned test does have
  colonies, that constant re-pins (a confirmation gate).
- **Hash layout:** append to the per-colony hash, in stable order, `population`
  (u64), `food` (i64 bits), `treasury[0..3]` (i64 bits); extend the Dormant
  reconstruction fold to reconstruct `treasury` (food/population frozen while
  mature ⇒ stored == reconstructed).

## 6. Component / file map

| File | Responsibility |
|---|---|
| `crates/core/src/game/civ/mod.rs` | `Colony`: `population`/`food`/`treasury`; `colony_cap`/`mature` helpers if they live here. |
| `crates/core/src/game/map.rs` | static `terrain` layer + `terrain_at`/`set_terrain`; `TerrainKind`. |
| `crates/core/src/game/sim.rs` | `planet_yield` cache; `colony_cap`/`colony_output_rate`/`mature`; `colony_lod` maturity rule; `run_colony_accrual` growth + empire-pool feed; `materialize_colony` treasury term; supply-cap + build-cap read population; `state_hash` per-colony append + treasury reconstruction. |
| `crates/core/src/game/balance.rs` + `crates/data/balance.ron` | `TerrainKind` yields, `pop_factor`, `threshold`, `housing_base`, `supply_per_pop`, `buildings_per_pop`. |
| `crates/core/src/game/scenario.rs`, `procgen.rs` | assign terrain at procgen; build `planet_yield`; seed colonies at `population: 1`. |
| `crates/render-shell/src/*` | colony HUD: population + food-to-next-pop (non-hashed). |

## 7. Out of scope (deferred)

- **Districts** (a real tile-placement layer) — "building/district capacity" is
  realized as a population-gated building *count* cap for now.
- **Autonomous spending of mature treasuries** — this slice banks treasury as
  real, hashed, visible state; mature colonies spending it on upkeep/builds is a
  follow-up.
- Per-tile citizen assignment; food *consumption*/starvation/shrinkage; terrain
  improvements; the conquest-scenario menu wiring (separate task).

## 8. Risks & mitigations

- **Mature output rate must be exactly constant over a Dormant window.**
  Mitigation: the rate is `pop_factor(population) × planet_yield` — population is
  frozen at cap, terrain is static, and live buildings are deliberately excluded.
  A test asserts treasury-at-wake == never-skipped treasury.
- **Immature colony accidentally skipped** would desync growth. Mitigation: the
  maturity rule makes `Dormant` require `population >= cap`; a test asserts an
  immature autonomy-full colony stays `Active`.
- **Golden not actually neutral** (e.g. a pinned test instantiates colonies).
  Mitigation: verify first; if so, re-pin that constant under the confirmation
  gate, in its own commit.
- **Per-tick cost** of summing terrain. Mitigation: the `planet_yield` cache makes
  rate lookups O(1); growth/treasury are O(colonies) per tick like the existing
  accrual.

## 9. Success criteria

- An Active colony on fertile terrain grows population over time; growth halts at
  `cap` and resumes when housing raises the cap.
- A colony becomes `Dormant` only when `population == cap && earned_autonomy >=
  AUTONOMY_FULL`; an immature autonomy-full colony stays `Active`.
- `lod_skip` on vs off produce identical hashes every tick on a multi-colony
  scenario; treasury-at-wake == never-skipped treasury.
- Developing colonies raise the empire pool; mature colonies bank treasury and
  stop feeding the pool; supply and build-cap scale with population.
- Golden stays `17_495_389_389_365_438_884` (or a single confirmed re-pin if a
  pinned test has colonies); server MATCH; strict clippy + fmt + wasm green.

## 10. Testing

Per the project bar: `cargo test --workspace` + strict clippy
(`--all-targets -- -D warnings`, pedantic+nursery) + `cargo fmt --all -- --check`
+ `cargo run --release -p rts-server` (MATCH) + wasm build. Specific tests in §9
plus the existing skip==full and replay/survival determinism suites, which must
stay green.
