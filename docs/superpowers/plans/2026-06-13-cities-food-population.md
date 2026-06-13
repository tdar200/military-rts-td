# Cities, Food & Population Growth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each colony a Population that grows from a per-tile-terrain Food yield, where population scales output/supply/build-capacity/autonomy, while keeping the deterministic closed-form (D3) exact.

**Architecture:** Growth (non-linear) runs only on the Active per-tick path; a colony goes Dormant only once *mature* (population at cap), where every population-derived rate is constant, so the existing closed-form `materialize_colony` extends with one constant-rate treasury term. All new hashed state is per-`Colony`; the golden replay has zero colonies, so the migration is expected **golden-neutral** (verify each task).

**Tech Stack:** Rust (no_std + alloc), fixed-point `Fixed`, FNV `state_hash`, RON balance. Verify per task: `cargo test --workspace`, strict clippy (`--all-targets -- -D warnings`, pedantic+nursery), `cargo fmt --all -- --check`, `cargo run --release -p rts-server` (MATCH).

**Spec:** `docs/superpowers/specs/2026-06-13-cities-food-population-design.md`

---

## Determinism gates (read first)

- **Golden hash is `17_495_389_389_365_438_884`.** All new hashed state is on `Colony`; the golden replay (`golden_hash_pins_cross_target_determinism`, sim.rs ~:4044) creates **zero colonies**, so it should stay unchanged. **Every task must re-run the golden and confirm it's unchanged.** If a task changes it, STOP and report — the only legitimate cause is a pinned-constant test that instantiates colonies (none is expected); a real re-pin is a confirmation gate.
- **The cardinal new test (Task 6):** `lod_skip` on vs off must produce identical hashes every tick on a multi-colony scenario, and treasury-at-wake must equal the never-skipped treasury.
- Rules: **D1** no rng; **D2/D6** i128-saturating closed form; **D3** skip==full; static map layers (terrain) are **not** hashed (like `deposits`/`planet_of`).

## File structure

| File | Responsibility |
|---|---|
| `crates/core/src/game/map.rs` | `TerrainKind` + static `terrain` layer + `terrain_at`/`set_terrain`. |
| `crates/core/src/game/balance.rs` + `crates/data/balance.ron` | terrain yields, `pop_factor`, food `threshold`, `housing_base`, `supply_per_pop`, `buildings_per_pop`. |
| `crates/core/src/game/civ/mod.rs` | `Colony`: `population`/`food`/`treasury`. |
| `crates/core/src/game/sim.rs` | `planet_yield` cache; `colony_cap`/`mature`/`colony_output_rate`/`colony_food_rate`; `colony_lod` maturity rule; `run_colony_accrual` growth + pool feed; `materialize_colony` treasury; `supply_cap`/build-cap/autonomy read population; `state_hash` append + treasury reconstruction. |
| `crates/render-shell/src/*` | colony HUD: population + food-to-next-pop (non-hashed). |

---

## Task 1: Terrain map layer + per-planet yield cache

**Files:** Modify `crates/core/src/game/map.rs`, `crates/core/src/game/balance.rs`, `crates/data/balance.ron`, `crates/core/src/game/sim.rs`.

- [ ] **Step 1: Add `TerrainKind` + per-tile yields.**

In `map.rs`:
```rust
/// Terrain class of a tile. Carries static per-tile yields (food/money/energy/
/// labour). A new, static map layer — NOT part of `state_hash` (like `deposits`).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, Default)]
pub enum TerrainKind {
    #[default]
    Barren,   // (0,0,0,0)
    Plains,   // food-leaning
    Fertile,  // high food
    Rich,     // high money/energy
}
```

- [ ] **Step 2: Add the static layer to `Map`.**

In `map.rs`, add field `terrain: Vec<TerrainKind>,` to `struct Map`; init `terrain: alloc::vec![TerrainKind::Barren; count],` in `Map::new` (same `count` as `tiles`). Add:
```rust
/// Terrain class at `(x, y)` (`Barren` out of bounds). Static; not hashed.
#[must_use]
pub fn terrain_at(&self, x: i32, y: i32) -> TerrainKind {
    if self.in_bounds(x, y) {
        let idx = (y as usize) * usize::from(self.width) + (x as usize);
        self.terrain[idx]
    } else {
        TerrainKind::Barren
    }
}

/// Sets terrain at `(x, y)` (procgen only; static thereafter).
pub fn set_terrain(&mut self, x: u16, y: u16, kind: TerrainKind) {
    if x < self.width && y < self.height {
        let idx = usize::from(y) * usize::from(self.width) + usize::from(x);
        self.terrain[idx] = kind;
    }
}
```
Copy the existing `#[allow(clippy::cast_sign_loss, reason = ...)]` from `tile()` for the `as usize` casts.

- [ ] **Step 3: Add a per-`TerrainKind` yield table to `Balance`.**

In `balance.rs`, add a method (no new struct field needed — keep it a `const fn` lookup so it threads through neither `const_default` nor `from_tables`):
```rust
/// Static per-tile yields for a terrain class: (food, money, energy, labour).
#[must_use]
pub const fn terrain_yield(kind: TerrainKind) -> (Fixed, Fixed, Fixed, Fixed) {
    use crate::game::map::TerrainKind as T;
    let z = Fixed::ZERO;
    match kind {
        T::Barren => (z, z, z, z),
        T::Plains => (Fixed::from_ratio(1, 4), Fixed::from_ratio(1, 8), z, z),
        T::Fertile => (Fixed::from_ratio(1, 2), Fixed::from_ratio(1, 8), z, z),
        T::Rich => (Fixed::from_ratio(1, 4), Fixed::from_ratio(1, 2), Fixed::from_ratio(1, 4), z),
    }
}
```
(These ratios are starting balance values — tunable later. `terrain_yield` is a free `const fn`, so it needs no `balance.ron` entry. Skip balance.ron for terrain values in this slice; they live in code. Note this in the commit.)

- [ ] **Step 4: Add the `planet_yield` cache to `Sim`.**

In `sim.rs`, add a non-hashed field `planet_yield: Vec<[Fixed; 4]>,` (indexed by `PlanetId`; `[food, money, energy, labour]`). Init `planet_yield: Vec::new(),` in `with_civ_count`. Add a rebuild method called by scenario setup after planets + terrain are assigned:
```rust
/// Recompute each planet's summed tile yields from the static terrain layer.
/// Pure function of static map data — NOT hashed. Call once after procgen.
pub fn rebuild_planet_yield(&mut self) {
    let mut out = alloc::vec![[Fixed::ZERO; 4]; self.planets.len()];
    for y in 0..self.map.height() {
        for x in 0..self.map.width() {
            if let Some(pid) = self.map.planet_at(i32::from(x), i32::from(y)) {
                let (f, m, e, l) = Balance::terrain_yield(self.map.terrain_at(i32::from(x), i32::from(y)));
                if let Some(slot) = out.get_mut(pid.0 as usize) {
                    slot[0] = slot[0] + f;
                    slot[1] = slot[1] + m;
                    slot[2] = slot[2] + e;
                    slot[3] = slot[3] + l;
                }
            }
        }
    }
    self.planet_yield = out;
}

/// The cached summed yields for a planet (`[0;4]` if unknown). Not hashed.
#[must_use]
pub fn planet_yield_of(&self, pid: PlanetId) -> [Fixed; 4] {
    self.planet_yield.get(pid.0 as usize).copied().unwrap_or([Fixed::ZERO; 4])
}
```

- [ ] **Step 5: Test the layer + cache.**

```rust
#[test]
fn terrain_layer_and_planet_yield_cache() {
    let mut s = Sim::new(Map::new(10, 10), 1, f(0));
    let pid = PlanetId(0);
    s.push_planet(Planet { owner: None, seat: None, center: tile_center(1, 1), radius: f(2) });
    // Mark a 2x2 block as this planet, set two Fertile tiles.
    for y in 0..2 { for x in 0..2 { s.map_mut().set_planet(x, y, pid); } }
    s.map_mut().set_terrain(0, 0, TerrainKind::Fertile);
    s.map_mut().set_terrain(1, 0, TerrainKind::Fertile);
    s.rebuild_planet_yield();
    // food = 2 * Fertile.food (1/2) = 1.0
    assert_eq!(s.planet_yield_of(pid)[0], f(1));
    // terrain layer is round-trippable and defaults Barren
    assert_eq!(s.map().terrain_at(5, 5), TerrainKind::Barren);
}
```

- [ ] **Step 6: Run + golden + commit.**

Run: `cargo test -p rts-core terrain_layer_and_planet_yield_cache golden_hash_pins_cross_target_determinism` (both pass; golden `17_495_389_389_365_438_884`). Then `cargo clippy --all-targets -- -D warnings && cargo fmt --all -- --check`.
```bash
git add -A
git commit -m "feat(core): static terrain map layer + per-planet yield cache"
```

---

## Task 2: Colony population/food/treasury fields + hash

**Files:** Modify `crates/core/src/game/civ/mod.rs`, `crates/core/src/game/sim.rs` (`add_colony` ~:715, `hash_colony_layer` :1577).

- [ ] **Step 1: Add the fields.**

In `civ/mod.rs` `struct Colony`, add:
```rust
/// City size. Starts at 1; grows from food while Active; capped at colony_cap.
pub population: u32,
/// Food box: accumulates the colony's food rate; on crossing the population
/// threshold, increments `population` and subtracts the threshold.
pub food: crate::fixed::Fixed,
/// Banked Money/Energy/Labour for a *mature* (self-funding) colony. Accrues at a
/// constant rate (closed-form, D2). Index 0=Money, 1=Energy, 2=Labour.
pub treasury: [crate::fixed::Fixed; 3],
```
In `add_colony` (sim.rs ~:716), set `population: 1, food: Fixed::ZERO, treasury: [Fixed::ZERO; 3],` in the `Colony { .. }` literal.

- [ ] **Step 2: Write the golden-neutrality + determinism test FIRST.**

```rust
#[test]
fn colony_growth_fields_hash_is_stable_and_golden_neutral() {
    // Two identical constructions with a colony hash equal (determinism).
    fn build() -> Sim {
        let mut s = Sim::new(Map::new(12, 12), 4, f(100));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 3, 3);
        s.add_colony(P0, cc, 0);
        s
    }
    assert_eq!(build().state_hash(), build().state_hash());
}
```
(The golden test itself — run in Step 5 — is the golden-neutrality check, since it has no colonies.)

- [ ] **Step 3: Run — expect compile failure** (fields not yet hashed is fine; the test compiles once fields exist). Run `cargo test -p rts-core colony_growth_fields_hash_is_stable_and_golden_neutral`.

- [ ] **Step 4: Append the fields to the colony hash + reconstruct treasury.**

In `hash_colony_layer` (sim.rs:1577), inside the per-colony loop, AFTER the `knowledge_of` loop (after :1619) and BEFORE the loop closes, append:
```rust
// City state. population/food are frozen while mature (a mature colony is the
// only kind that goes Dormant), so they hash as stored. The treasury accrues at
// a constant rate while Dormant, so fold in the closed-form caught-up value
// (rule D3) exactly like the Field stockpiles above. For an immature colony
// `elapsed` is 0 (it is always Active, never skipped), so the reconstruction is
// a no-op and the treasury (which stays zero for immature colonies) is unchanged.
h.write_u64(u64::from(c.population));
h.write_i64(c.food.to_bits());
for k in 0..3 {
    let rate = self.colony_output_rate(ci, k);
    let bits = saturate_i64(
        i128::from(c.treasury[k].to_bits()) + i128::from(rate.to_bits()) * i128::from(elapsed),
    );
    h.write_i64(bits);
}
```
NOTE: `colony_output_rate(ci, k) -> Fixed` is defined in Task 3. For THIS task, add a temporary stub returning `Fixed::ZERO` so the code compiles and the hash is well-defined; Task 3 replaces the stub. (Stub: `fn colony_output_rate(&self, _ci: usize, _k: usize) -> Fixed { Fixed::ZERO }`.)

- [ ] **Step 5: Run the test + the golden.**

Run: `cargo test -p rts-core colony_growth_fields_hash_is_stable_and_golden_neutral golden_hash_pins_cross_target_determinism`
Expected: both PASS; golden **unchanged** at `17_495_389_389_365_438_884` (no colonies in the golden run ⇒ no new bytes). If the golden changed, STOP and report BLOCKED.

- [ ] **Step 6: Full check + commit.**

Run: `cargo test --workspace && cargo clippy --all-targets -- -D warnings && cargo fmt --all -- --check`.
```bash
git add -A
git commit -m "feat(core): colony population/food/treasury fields + hash (golden-neutral)"
```

---

## Task 3: Derived helpers + balance constants

**Files:** Modify `crates/core/src/game/sim.rs` (replace the Task-2 stub), `crates/core/src/game/balance.rs`.

- [ ] **Step 1: Add balance constants.**

In `balance.rs`, add `const fn` helpers (free functions or `Balance` methods; no `balance.ron` plumbing needed — keep in code for this slice, note in commit):
```rust
/// Output multiplier for a colony of the given population (linear for now).
#[must_use]
pub const fn pop_factor(population: u32) -> Fixed { Fixed::from_int(population as i32) }

/// Food required to grow from `population` to `population + 1` (rises with size).
#[must_use]
pub const fn food_threshold(population: u32) -> Fixed {
    Fixed::from_int(10 + 5 * population as i32)
}

/// Base population cap contributed by a planet of `tile_count` tiles.
#[must_use]
pub const fn housing_base(tile_count: u32) -> u32 { 2 + tile_count / 4 }
```
Also add plain `const`s near the other supply consts in `sim.rs`: `const SUPPLY_PER_POP: u32 = 1;` and `const BUILDINGS_PER_POP: u32 = 2;` and `const HOUSING_PER_BUILDING: u32 = 2;` (starting values, tunable).

- [ ] **Step 2: Implement the derived helpers in `sim.rs`** (replace the Task-2 `colony_output_rate` stub):

```rust
/// The planet a colony sits on (its seat's tile resolves to a planet id).
fn colony_planet(&self, ci: usize) -> Option<PlanetId> {
    let seat = self.colonies[ci].seat;
    let (x, y) = self.entities.get(seat.0 as usize)?.tile?;
    self.map.planet_at(i32::from(x), i32::from(y))
}

/// Number of tiles belonging to the colony's planet (for the housing base).
fn colony_planet_tiles(&self, ci: usize) -> u32 {
    let Some(pid) = self.colony_planet(ci) else { return 0; };
    let mut n = 0u32;
    for y in 0..self.map.height() {
        for x in 0..self.map.width() {
            if self.map.planet_at(i32::from(x), i32::from(y)) == Some(pid) { n += 1; }
        }
    }
    n
}

/// Population cap = housing_base(planet tiles) + housing buildings on the planet.
fn colony_cap(&self, ci: usize) -> u32 {
    let base = Balance::housing_base(self.colony_planet_tiles(ci));
    let Some(pid) = self.colony_planet(ci) else { return base; };
    let mut housing = 0u32;
    for e in &self.entities {
        if e.alive && matches!(e.kind, Kind::Building(BuildingKind::CommandCenter)) {
            if let Some((x, y)) = e.tile {
                if self.map.planet_at(i32::from(x), i32::from(y)) == Some(pid) {
                    housing += HOUSING_PER_BUILDING;
                }
            }
        }
    }
    base + housing
}

/// Whether a colony is mature: at population cap AND has earned full autonomy.
fn colony_mature(&self, ci: usize) -> bool {
    let c = &self.colonies[ci];
    c.population >= self.colony_cap(ci) && c.earned_autonomy() >= AUTONOMY_FULL
}

/// Per-tick food rate (terrain only).
fn colony_food_rate(&self, ci: usize) -> Fixed {
    let Some(pid) = self.colony_planet(ci) else { return Fixed::ZERO; };
    self.planet_yield_of(pid)[0]
}

/// Per-tick output rate for resource `k` (0=Money,1=Energy,2=Labour):
/// pop_factor(population) x the planet's terrain yield for that resource.
/// Deliberately independent of live building count, so it is constant during a
/// Dormant (mature) window (rule D3). Resource index maps to planet_yield[k+1]
/// (slot 0 is food).
fn colony_output_rate(&self, ci: usize, k: usize) -> Fixed {
    let Some(pid) = self.colony_planet(ci) else { return Fixed::ZERO; };
    let yield_k = self.planet_yield_of(pid)[k + 1];
    Balance::pop_factor(self.colonies[ci].population) * yield_k
}
```
(`HOUSING_PER_BUILDING` here uses the CommandCenter as the only "housing" building in this slice; extend to a dedicated housing building kind later. Note this simplification in the commit.)

- [ ] **Step 3: Test the helpers.**

```rust
#[test]
fn colony_cap_and_rates_derive_from_planet() {
    let mut s = Sim::new(Map::new(10, 10), 1, f(0));
    let pid = PlanetId(0);
    for y in 0..2 { for x in 0..2 { s.map_mut().set_planet(x, y, pid); } }
    s.map_mut().set_terrain(0, 0, TerrainKind::Fertile); // food 1/2, money 1/8
    let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
    s.push_planet(Planet { owner: Some(P0), seat: Some(cc), center: tile_center(0, 0), radius: f(2) });
    let id = s.add_colony(P0, cc, 0);
    s.rebuild_planet_yield();
    let ci = id.0 as usize;
    // food rate = planet food sum = 1/2
    assert_eq!(s.colony_food_rate(ci), f_ratio(1, 2));
    // output money rate at population 1 = pop_factor(1)=1 * money yield 1/8
    assert_eq!(s.colony_output_rate(ci, 0), f_ratio(1, 8));
    // cap = housing_base(4 tiles)= 2+1=3, + 1 CC * HOUSING_PER_BUILDING(2) = 5
    assert_eq!(s.colony_cap(ci), 5);
    assert!(!s.colony_mature(ci)); // population 1 < cap 5
}
```
(Add an `f_ratio(n, d)` test helper if not present: `fn f_ratio(n: i64, d: i64) -> Fixed { Fixed::from_ratio(n, d) }`.)

- [ ] **Step 4: Run + golden + commit.**

Run: `cargo test -p rts-core colony_cap_and_rates_derive_from_planet golden_hash_pins_cross_target_determinism` (pass; golden unchanged). Then clippy + fmt.
```bash
git add -A
git commit -m "feat(core): colony cap/maturity/food-rate/output-rate helpers + balance consts"
```

---

## Task 4: Growth pass (Active-phase) + empire-pool feed

**Files:** Modify `crates/core/src/game/sim.rs` (`run_colony_accrual` :2659).

- [ ] **Step 1: Write the failing test.**

```rust
#[test]
fn active_colony_grows_population_and_halts_at_cap() {
    let mut s = Sim::new(Map::new(8, 8), 1, f(0));
    let pid = PlanetId(0);
    for y in 0..2 { for x in 0..2 { s.map_mut().set_planet(x, y, pid); }
                    s.map_mut().set_terrain(0, y, TerrainKind::Fertile); }
    let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
    s.push_planet(Planet { owner: Some(P0), seat: Some(cc), center: tile_center(0, 0), radius: f(2) });
    let id = s.add_colony(P0, cc, 0);
    s.rebuild_planet_yield();
    let ci = id.0 as usize;
    let cap = s.colony_cap(ci);
    for _ in 0..4000 { s.step(&[]); }
    assert_eq!(s.colony(id).unwrap().population, cap, "growth halts exactly at cap");
}
```
(`s.colony(id)` is the existing read accessor.)

- [ ] **Step 2: Run — expect FAIL** (`cargo test -p rts-core active_colony_grows_population_and_halts_at_cap`): population stays 1.

- [ ] **Step 3: Add growth + pool-feed to `run_colony_accrual`.**

In `run_colony_accrual` (sim.rs:2659), inside the per-colony loop, AFTER `self.materialize_colony(ci, next);` add:
```rust
// Growth + real-time income for DEVELOPING (immature) colonies. Immature
// colonies are always Active (never skipped — see colony_lod's maturity rule),
// so this is always an elapsed-1 path: no closed form needed (rule D3). Mature
// colonies bank their output in `treasury` inside materialize_colony instead.
if !self.colony_mature(ci) {
    let owner = usize::from(self.colonies[ci].owner.0);
    // Food box growth.
    let food_rate = self.colony_food_rate(ci);
    self.colonies[ci].food = self.colonies[ci].food + food_rate;
    let cap = self.colony_cap(ci);
    while self.colonies[ci].population < cap {
        let threshold = Balance::food_threshold(self.colonies[ci].population);
        if self.colonies[ci].food < threshold { break; }
        self.colonies[ci].food = self.colonies[ci].food - threshold;
        self.colonies[ci].population += 1;
    }
    // Real-time income to the empire pool (additional to run_economy).
    self.civs[owner].money = self.civs[owner].money + self.colony_output_rate(ci, 0);
    self.civs[owner].energy = cap_energy(self.civs[owner].energy + self.colony_output_rate(ci, 1));
    self.civs[owner].labour = cap_labour(self.civs[owner].labour + self.colony_output_rate(ci, 2));
}
```
Use the existing energy/labour cap helpers (search for `ENERGY_CAP`/`cap_at`/how `run_economy` clamps energy/labour, and mirror it — replace `cap_energy`/`cap_labour` with the real clamp calls used in `run_economy`). If `run_economy` clamps inline, copy that idiom.

- [ ] **Step 4: Run the test.**

Run: `cargo test -p rts-core active_colony_grows_population_and_halts_at_cap` → PASS.

- [ ] **Step 5: Golden + full + commit.**

Run: `cargo test --workspace && cargo run --release -p rts-server`. Golden unchanged (`17_495_389_389_365_438_884`); server MATCH (golden/legacy survival paths: survival HAS colonies, but its tests are run-to-run, so they stay green; verify). clippy + fmt.
```bash
git add -A
git commit -m "feat(core): Active-phase population growth + colony income to empire pool"
```

---

## Task 5: The maturity rule in `colony_lod`

**Files:** Modify `crates/core/src/game/sim.rs` (`colony_lod` :2678).

- [ ] **Step 1: Write the failing test.**

```rust
#[test]
fn dormant_requires_maturity_not_just_autonomy() {
    let mut s = Sim::new(Map::new(8, 8), 1, f(0));
    let pid = PlanetId(0);
    for y in 0..2 { for x in 0..2 { s.map_mut().set_planet(x, y, pid); } }
    let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
    s.push_planet(Planet { owner: Some(P0), seat: Some(cc), center: tile_center(0, 0), radius: f(2) });
    let id = s.add_colony(P0, cc, AUTONOMY_FULL); // full autonomy, but population 1 < cap
    s.rebuild_planet_yield();
    s.step(&[]); // run_lod recomputes detail
    assert_eq!(s.colony(id).unwrap().detail, SimDetail::Active,
        "an autonomy-full but immature colony must stay Active, not Dormant");
}
```

- [ ] **Step 2: Run — expect FAIL** (it goes Dormant under the old rule).

- [ ] **Step 3: Change the Dormant condition.**

In `colony_lod` (sim.rs:2695), replace:
```rust
if c.earned_autonomy() >= AUTONOMY_FULL {
    SimDetail::Dormant
} else {
    SimDetail::Active
}
```
with:
```rust
// Dormant only when MATURE (population at cap AND full autonomy). An immature
// colony stays Active so its non-linear growth always runs full-fidelity and is
// never caught up by the closed form (rule D3).
if self.colony_mature(ci) {
    SimDetail::Dormant
} else {
    SimDetail::Active
}
```
(`colony_lod` takes `ci`; it currently binds `let c = &self.colonies[ci];` — keep that for the threat check, and call `self.colony_mature(ci)` for the maturity branch. Ensure no borrow conflict: compute `let mature = self.colony_mature(ci);` before the final `if`, then branch on the local.)

- [ ] **Step 4: Run the test + golden.**

Run: `cargo test -p rts-core dormant_requires_maturity_not_just_autonomy golden_hash_pins_cross_target_determinism` → both PASS; golden unchanged.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(core): colony goes Dormant only when mature (population at cap)"
```

---

## Task 6: Closed-form treasury + the D3 skip==full test

**Files:** Modify `crates/core/src/game/sim.rs` (`materialize_colony` :2631). Test in the tests module.

- [ ] **Step 1: Write the cardinal determinism test FIRST.**

```rust
#[test]
fn lod_skip_matches_full_with_growing_and_mature_colonies() {
    fn run(lod_skip: bool) -> Vec<u64> {
        let mut s = scenario::conquest(2024, 3); // multi-colony scenario
        s.set_lod_skip_for_test(lod_skip);        // add a #[cfg(test)] setter if absent
        let mut hashes = Vec::new();
        for _ in 0..1500 {
            let cmds: Vec<Command> = (0..3u16)
                .filter(|&i| s.civ_alive(PlayerId(i)))
                .flat_map(|i| s.ai_commands(PlayerId(i)))
                .collect();
            s.step(&cmds);
            hashes.push(s.state_hash());
        }
        hashes
    }
    assert_eq!(run(true), run(false), "skip path must match full path every tick");
}

#[test]
fn mature_colony_treasury_wakes_to_exact_value() {
    // A mature colony banks output; skipping then waking reproduces the exact
    // never-skipped treasury.
    // (Construct a colony forced mature: population at cap + full autonomy, on
    // Rich terrain; run with lod_skip true vs false for N ticks; treasury equal.)
    // See colony_cap/colony_output_rate; assert the two treasuries are equal.
}
```
For `mature_colony_treasury_wakes_to_exact_value`, build a small colony, set `population` to its cap via a `#[cfg(test)]` setter (or grow it), grant full autonomy, put it on `Rich` terrain, then compare treasury after 500 ticks with `lod_skip` true vs false — assert equal. (If a test-only `lod_skip` setter or `population` setter doesn't exist, add minimal `#[cfg(test)]` ones mirroring `debug_set_hp`.)

- [ ] **Step 2: Run — expect FAIL** (treasury never accrues; skip==full may already pass with zero treasury, so the treasury-wake test is the one that must fail first). Run both filters.

- [ ] **Step 3: Add the treasury term to `materialize_colony`.**

In `materialize_colony` (sim.rs:2631), after the Field-stockpile loop and before `self.colonies[ci].last_sync_tick = next;`, add:
```rust
// Mature (self-funding) colonies bank their constant-rate output into the
// treasury, in exact closed form (rule D2/D6) — the same shape as the Field
// stockpile catch-up above. Immature colonies feed the empire pool in
// run_colony_accrual instead and keep a zero treasury, so they are skipped here.
if self.colony_mature(ci) {
    for k in 0..3 {
        let rate = self.colony_output_rate(ci, k);
        if rate.to_bits() != 0 {
            let acc = i128::from(self.colonies[ci].treasury[k].to_bits())
                + i128::from(rate.to_bits()) * i128::from(elapsed);
            self.colonies[ci].treasury[k] = Fixed::from_bits(saturate_i64(acc));
        }
    }
}
```
This exactly mirrors the hash reconstruction in Task 2 Step 4, so stored == reconstructed for every tick.

- [ ] **Step 4: Run both determinism tests.**

Run: `cargo test -p rts-core lod_skip_matches_full_with_growing_and_mature_colonies mature_colony_treasury_wakes_to_exact_value` → PASS.

- [ ] **Step 5: Golden + full + server + commit.**

Run: `cargo test --workspace && cargo run --release -p rts-server`. Golden unchanged; server MATCH. clippy + fmt.
```bash
git add -A
git commit -m "feat(core): closed-form treasury accrual for mature colonies (D3-exact)"
```

---

## Task 7: The four population effects (supply, build-cap, autonomy)

**Files:** Modify `crates/core/src/game/sim.rs` (`supply_cap` :1333, `apply_build`/auto-build gate, `materialize_colony` autonomy term).

- [ ] **Step 1: Write failing tests.**

```rust
#[test]
fn population_scales_supply_cap() {
    let mut s = Sim::new(Map::new(8, 8), 1, f(0));
    let pid = PlanetId(0);
    s.map_mut().set_planet(0, 0, pid);
    let cc = s.add_building(P0, BuildingKind::CommandCenter, 0, 0);
    s.push_planet(Planet { owner: Some(P0), seat: Some(cc), center: tile_center(0, 0), radius: f(1) });
    let id = s.add_colony(P0, cc, 0);
    let before = s.supply_cap(P0);
    s.set_population_for_test(id, 5); // #[cfg(test)] setter
    assert_eq!(s.supply_cap(P0), before + 5 * 1, "supply rises by SUPPLY_PER_POP * population");
}

#[test]
fn population_gates_building_count() {
    // A colony at population 1 with BUILDINGS_PER_POP=2 can hold <=2 buildings;
    // a third Build on its planet is rejected until population rises.
    // Build via Command::Build on owned planet tiles; assert buildings_owned_by
    // stops increasing at the cap, then rises after set_population_for_test.
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3a: Population → supply.** In `supply_cap` (sim.rs:1333), before `cap`, add:
```rust
for c in &self.colonies {
    if c.alive && c.owner == player {
        cap += SUPPLY_PER_POP * c.population;
    }
}
```

- [ ] **Step 3b: Population → building capacity.** Add a gate helper and use it in `apply_build` (and the AI/auto-build path). The cap is per-colony: a colony's planet can hold `BUILDINGS_PER_POP * population` buildings.
```rust
/// Whether the colony owning planet `(x,y)` can hold another building.
fn under_building_cap(&self, owner: CivId, x: u16, y: u16) -> bool {
    let Some(pid) = self.map.planet_at(i32::from(x), i32::from(y)) else { return true; };
    // Find the colony seated on this planet.
    let Some(ci) = self.colonies.iter().position(|c| c.alive && c.owner == owner
        && self.colony_planet_index_eq(c.seat, pid)) else { return true; };
    let count = self.entities.iter().filter(|e| e.alive && matches!(e.kind, Kind::Building(_))
        && e.tile.is_some_and(|(tx, ty)| self.map.planet_at(i32::from(tx), i32::from(ty)) == Some(pid))).count();
    (count as u32) < BUILDINGS_PER_POP * self.colonies[ci].population
}
```
(Add the small `colony_planet_index_eq(seat, pid)` helper, or inline the seat→planet resolution. Add `&& self.under_building_cap(owner, x, y)` to `apply_build`'s success guard, next to `can_build_on`.)

- [ ] **Step 3c: Population → autonomy speed.** In `materialize_colony` (sim.rs:2638), replace `autonomy_progress += steps` with a population-scaled rate. Keep it integer and deterministic:
```rust
// Bigger cities earn autonomy faster. Rate is constant while mature (pop frozen),
// so the closed form stays exact; immature colonies run this every tick (Active).
let auto_rate = 1 + self.colonies[ci].population / AUTONOMY_POP_DIVISOR; // const, e.g. 4
self.colonies[ci].autonomy_progress =
    self.colonies[ci].autonomy_progress.saturating_add(steps.saturating_mul(auto_rate));
```
**CRITICAL:** the hash reconstruction in `hash_colony_layer` currently reconstructs `autonomy_progress` as `progress + elapsed` (rate 1). It MUST be changed to match: `progress + elapsed * auto_rate` where `auto_rate` uses the colony's (frozen, mature) population. Update the reconstruction at sim.rs:1592-1594 to compute the same `auto_rate` and multiply. (For immature colonies, elapsed is 0, so no divergence; for mature, population is frozen so `auto_rate` is constant — closed-form exact.) Verify the skip==full test (Task 6) still passes after this change.

- [ ] **Step 4: Run tests + the Task 6 determinism test.**

Run: `cargo test -p rts-core population_scales_supply_cap population_gates_building_count lod_skip_matches_full_with_growing_and_mature_colonies` → PASS.

- [ ] **Step 5: Golden + full + commit.**

Run: `cargo test --workspace && cargo run --release -p rts-server`. Golden unchanged; server MATCH. clippy + fmt.
```bash
git add -A
git commit -m "feat(core): population scales supply, building capacity, and autonomy speed"
```

---

## Task 8: Render-shell — colony population + food HUD

**Files:** Modify `crates/render-shell/src/ui.rs` (colony panel/roster). Non-hashed.

- [ ] **Step 1: Add read accessors (core).**

In `sim.rs`, add (if absent) `#[must_use] pub fn colony_population(&self, id: ColonyId) -> u32` and `pub fn colony_food_progress(&self, id: ColonyId) -> (Fixed, Fixed)` returning `(food, food_threshold(population))` for a "to next pop" readout. Confirm golden unchanged (read-only accessors).

- [ ] **Step 2: Show it in the colony panel.**

In `ui.rs`, wherever the colony/sector roster draws a colony row (the `draw_civ_roster` from the prior feature, or the existing colony panel), add a compact `pop N (food x/y)` readout per colony using the new accessors and the existing text-draw idiom. Use ASCII / `•` `–` `—` only (no arrow glyphs U+2190–2193).

- [ ] **Step 3: Build + smoke test.**

Run: `cargo build -p rts-render-shell`. Run headless under Xvfb (per the project's practice) on a conquest scenario if reachable, else the default; confirm no panic. Report honestly if it can't run headless.

- [ ] **Step 4: Golden + commit.**

Run: `cargo test -p rts-core golden_hash_pins_cross_target_determinism` (unchanged), clippy + fmt.
```bash
git add -A
git commit -m "feat(shell): show colony population + food-to-next-pop"
```

---

## Self-review notes (addressed)

- **Spec coverage:** Food/Population fields → Task 2; terrain yields → Task 1; cap/maturity/rates → Task 3; growth (Active-only) + pool feed → Task 4; the maturity rule (the D3 linchpin) → Task 5; closed-form treasury + the cardinal skip==full test → Task 6; the four pop effects → Tasks 4 (output) + 7 (supply/build-cap/autonomy); HUD → Task 8. Determinism §5 → gates in every task (golden re-run) + Task 6.
- **The autonomy-speed change (Task 7 Step 3c) is the one subtle hash coupling** — it changes the EXISTING `autonomy_progress` accrual, so the hash reconstruction at sim.rs:1592 must be updated in lockstep. This is called out explicitly. It is still golden-neutral (golden has no colonies) but DOES change survival/conquest run-to-run hashes (still deterministic → tests stay green).
- **Type consistency:** `colony_output_rate(ci: usize, k: usize) -> Fixed` (k: 0=Money/1=Energy/2=Labour, mapping to `planet_yield[k+1]`); `treasury: [Fixed; 3]`; `colony_mature(ci)`/`colony_cap(ci)`/`colony_food_rate(ci)` all take `ci: usize`; `planet_yield: Vec<[Fixed;4]>` (slot 0 = food). The Task-2 stub is replaced in Task 3 — flagged so out-of-order readers don't miss it.
- **Golden-neutrality is the recurring gate:** every task re-runs the golden; the expectation is *unchanged* because the golden replay has no colonies. A change is a STOP-and-report (only a pinned-constant test with colonies would legitimately re-pin — none is expected).
- **YAGNI:** no districts, no treasury spending, no food consumption/starvation, no balance.ron plumbing for the new code-constants (kept as `const fn` for this slice), CommandCenter doubles as the only "housing" building for now — all flagged in commits as deliberate slice scope.
