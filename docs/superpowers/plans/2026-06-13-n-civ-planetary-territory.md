# N-Civ + Planetary Territory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the hardcoded two-player engine to up to ~6 civilizations and add planetary territory with seat-capture conquest, keeping the deterministic real-time core intact.

**Architecture:** Two layered changes landed as two separate re-pin commits. **Migration 1** is a pure structural rewrite (`Player` → `Civ`, `[Player; 2]` → `civs: Vec<Civ>`) designed to be **hash-neutral** — the 2-civ golden replay must hash identically. **Migration 2** adds a `planets: Vec<Planet>` arena, a static tile→planet map layer, build-gating, seat-capture conquest, and per-civ elimination; it re-pins the golden hash. Planet ownership is discrete and event-driven, so it never touches the LOD/closed-form determinism machinery.

**Tech Stack:** Rust (no_std core, `alloc`), fixed-point math (`Fixed`), FNV state hashing, RON balance data. Verification per milestone: `cargo test --workspace`, strict clippy (`--all-targets -- -D warnings`, pedantic+nursery), `cargo fmt --all -- --check`, `cargo run --release -p rts-server` (MATCH), wasm build.

**Spec:** `docs/superpowers/specs/2026-06-13-n-civ-planetary-territory-design.md`

---

## Determinism gates (read before starting)

Per the project's blast-radius rule, **every `state_hash` change is a confirmation gate**: show the before/after hash and re-pin the golden constant in the *same* commit, and **STOP for user confirmation before committing a re-pin**. Two re-pin points exist:

- **Migration 1** — expected **hash-NEUTRAL** (golden stays `4_245_124_049_375_366_020`). If it changes, STOP: a neutral migration that isn't neutral is a hidden ordering bug.
- **Migration 2** — **re-pins** (new `alive` byte + planets section). Capture the new hash and pin it under user confirmation.

Determinism rules in force: **D1** no `rng` in conquest (use combat order); **D2/D3** N/A (event-driven, no accrual); **D5** civs/planets are fixed at setup (no free-list); **D6** capture HP uses `Fixed`; **D8** one hash rewrite per commit.

---

## File structure

| File | Responsibility | Migration |
|---|---|---|
| `crates/core/src/game/civ/mod.rs` | Home of `Civ` (renamed from `Player`); gains `alive`. | 1 (move) + 2 (alive) |
| `crates/core/src/game/sim.rs` | `civs: Vec<Civ>`, `planets: Vec<Planet>`, all per-civ logic, conquest, build-gating, hash. | 1 + 2 |
| `crates/core/src/game/planet.rs` | **New.** `PlanetId`, `Planet`, helpers. | 2 |
| `crates/core/src/game/map.rs` | Static `planet_of` layer + `planet_at()`. | 2 |
| `crates/core/src/game/balance.rs` + `crates/data/balance.ron` | `capture_hp_fraction`. | 2 |
| `crates/core/src/game/scenario.rs`, `procgen.rs` | N-civ + planet setup; conquest scenario. | 2 |
| `crates/render-shell/src/*` | Owner tinting + N-civ HUD (non-hashed). | 2 |

---

# MIGRATION 1 — `Vec<Civ>` (hash-neutral)

## Task 1: Widen `PlayerId` to `u16` and rename `Player` → `Civ`

**Files:**
- Modify: `crates/core/src/game/sim.rs:41` (`PlayerId`), `:222-244` (`Player` struct), and `crates/core/src/game/civ/mod.rs` (new home for `Civ`).

This is a nominal change only: a wider id and a renamed struct. The fixed `[_; 2]` array stays for now (split from the Vec change so each step compiles and the golden stays provably neutral).

- [ ] **Step 1: Move the `Player` struct to `civ/mod.rs`, renamed `Civ`.**

Cut the `Player` struct (`sim.rs:222-244`) and paste into `crates/core/src/game/civ/mod.rs`, renamed and made public:

```rust
/// One civilization's empire-wide state (formerly `Player`).
#[derive(Clone, Debug)]
pub struct Civ {
    pub money: crate::fixed::Fixed,
    pub researched_techs: crate::game::tech_grid::TechBitset,
    pub active_research: Option<(u32, u32)>,
    pub era: u8,
    pub energy: crate::fixed::Fixed,
    pub labour: crate::fixed::Fixed,
    pub active_perks: u32,
    pub doctrine_levels: [u16; crate::game::sim::DOCTRINE_TRACKS],
    pub unlocked_buildings: u16,
    pub unlocked_units: u16,
}
```

(Adjust visibility of `DOCTRINE_TRACKS` to `pub` in `sim.rs` if not already. Fields become `pub` so `sim.rs` can construct/read them across the module boundary.)

- [ ] **Step 2: Add `CivId` and widen the id.**

In `sim.rs:41`, change `pub struct PlayerId(pub u8);` to:

```rust
pub struct PlayerId(pub u16);

/// The identity of a civilization. Same newtype as [`PlayerId`]; the alias
/// documents that an id now denotes a civ, not a 1-of-2 player slot.
pub type CivId = PlayerId;
```

- [ ] **Step 3: Fix the fallout (compiler-driven).**

Re-export `Civ` from `civ/mod.rs` in the existing `use crate::game::civ::{...}` block at `sim.rs:14`. Replace the local `Player` type with `Civ` (the field `players: [Player; PLAYER_COUNT]` becomes `players: [Civ; PLAYER_COUNT]` for now). Fix any `as u8`/`u8::try_from` on `PlayerId.0` that the widen breaks (e.g. `winner()`'s `PlayerId(i as u8)` → `PlayerId(i as u16)`; `run_combat`'s `PlayerId(u8::try_from(p).unwrap())` → `PlayerId(u16::try_from(p).unwrap())`).

- [ ] **Step 4: Verify it compiles and the golden is unchanged.**

Run: `cargo test -p rts-core golden_hash_pins_cross_target_determinism -- --nocapture`
Expected: PASS, hash still `4_245_124_049_375_366_020`. (`u16` hashes identically to `u8` for values 0/1 — `state_hash` casts owner to `u64`.)

- [ ] **Step 5: Full check + commit.**

Run: `cargo test --workspace && cargo clippy --all-targets -- -D warnings && cargo fmt --all -- --check`
Expected: all green.

```bash
git add -A
git commit -m "refactor(core): widen PlayerId to u16, rename Player -> Civ (no behavior change)"
```

## Task 2: Convert `[Civ; 2]` → `civs: Vec<Civ>`

**Files:**
- Modify: `crates/core/src/game/sim.rs` — `:29` (`PLAYER_COUNT`), `:530` (field), `:667-700` (`new`), `:1320-1344` (`winner`), `:2663-2684` + `:2332-2368` + `:2583` (per-player `[_; PLAYER_COUNT]` arrays), and every `self.players[..]` access.
- Test: `crates/core/src/game/sim.rs` (tests module).

This is a compiler-driven mechanical sweep. The contract: a 2-civ game hashes byte-identically (a `Vec` of 2 serializes like an array of 2).

- [ ] **Step 1: Write the failing N-civ determinism test.**

Add to the tests module in `sim.rs`:

```rust
#[test]
fn six_civ_game_is_deterministic() {
    fn run() -> u64 {
        let mut s = Sim::with_civ_count(Map::new(40, 40), 999, f(1500), 6);
        for id in 0..6u16 {
            s.add_building(PlayerId(id), BuildingKind::CommandCenter, 3 + id * 5, 20);
        }
        for _ in 0..60 {
            let cmds: Vec<Command> =
                (1..6u16).flat_map(|id| s.ai_commands(PlayerId(id))).collect();
            s.step(&cmds);
        }
        s.state_hash()
    }
    assert_eq!(run(), run(), "six-civ run must be bit-identical across runs");
}
```

- [ ] **Step 2: Run it to confirm it fails to compile.**

Run: `cargo test -p rts-core six_civ_game_is_deterministic`
Expected: FAIL — `Sim::with_civ_count` does not exist.

- [ ] **Step 3: Convert the field and constructors.**

In `sim.rs`:
- `:530` `players: [Civ; PLAYER_COUNT]` → `civs: Vec<Civ>`.
- Delete `PLAYER_COUNT` (`:29`); rename `human_civ` concept by adding a field `human_civ: CivId` (default `PlayerId(0)`).
- Replace the `const fn new` body's array init (`:672-683`). Drop `const` (a `Vec` init isn't const). Factor the per-civ default into a helper and add `with_civ_count`:

```rust
fn default_civ(starting_credits: Fixed) -> Civ {
    Civ {
        money: starting_credits,
        researched_techs: TechBitset::empty(),
        active_research: None,
        era: 0,
        energy: Fixed::ZERO,
        labour: Fixed::ZERO,
        active_perks: 0,
        doctrine_levels: [0; DOCTRINE_TRACKS],
        unlocked_buildings: u16::MAX,
        unlocked_units: u16::MAX,
    }
}

pub fn new(map: Map, seed: u64, starting_credits: Fixed) -> Self {
    Self::with_civ_count(map, seed, starting_credits, 2)
}

pub fn with_civ_count(map: Map, seed: u64, starting_credits: Fixed, civ_count: usize) -> Self {
    let civs = (0..civ_count).map(|_| default_civ(starting_credits)).collect();
    Self {
        tick: 0,
        rng: Rng::from_seed(seed),
        map,
        civs,
        human_civ: PlayerId(0),
        entities: Vec::new(),
        free: Vec::new(),
        waves: None,
        wave_count: 0,
        phase: GamePhase::Active,
        phase_started: 0,
        survival: false,
        balance: Balance::const_default(),
        attacks: Vec::new(),
        colonies: Vec::new(),
        colony_free: Vec::new(),
        sectors: Vec::new(),
        sector_free: Vec::new(),
        field_seed: seed,
        lod_skip: true,
    }
}
```

- [ ] **Step 4: Sweep `self.players[..]` → `self.civs[..]`.**

Mechanical rename. Run `grep -n "self.players" crates/core/src/game/sim.rs` and replace each `self.players` with `self.civs`. Bounds are unchanged (`usize::from(owner.0)` still indexes). For the per-civ `[_; PLAYER_COUNT]` arrays in `run_combat` (`:2663-2684`), `run_economy` (`:2355-2356`), `:2332`, and `:2583`, replace `core::array::from_fn::<_, PLAYER_COUNT, _>(|p| …)` with a `Vec`:

```rust
// before: let weapon: [Fixed; PLAYER_COUNT] = core::array::from_fn(|p| …);
let weapon: Vec<Fixed> = (0..self.civs.len())
    .map(|p| self.player_weapon_bonus(PlayerId(u16::try_from(p).unwrap())))
    .collect();
```

Do the same for `armor`, `era_dmg`, `perk_dmg`, `perk_mit`, and the `run_economy` `energy_out`/`labour_out`/`max` arrays. Indexing stays `arr[usize::from(owner.0)]`.

- [ ] **Step 5: Generalize `winner()` (`:1320-1344`).**

```rust
pub fn winner(&self) -> Option<PlayerId> {
    if matches!(self.phase, GamePhase::Survey) {
        return None;
    }
    let mut has_cc = alloc::vec![false; self.civs.len()];
    for e in &self.entities {
        if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
            let i = usize::from(e.owner.0);
            if i < has_cc.len() {
                has_cc[i] = true;
            }
        }
    }
    if self.survival {
        return if has_cc[usize::from(self.human_civ.0)] { None } else { Some(PlayerId(1)) };
    }
    let alive: usize = has_cc.iter().filter(|&&b| b).count();
    if alive == 1 {
        has_cc.iter().position(|&b| b).map(|i| PlayerId(i as u16))
    } else {
        None
    }
}
```

- [ ] **Step 6: Update `state_hash` (`:1365`) to iterate the Vec — no field changes.**

Change `for p in &self.players {` to `for c in &self.civs {` and rename the loop binding (`p.money` → `c.money`, etc.). **Write exactly the same fields in the same order. Add nothing.**

- [ ] **Step 7: Run the new test + the golden.**

Run: `cargo test -p rts-core six_civ_game_is_deterministic golden_hash_pins_cross_target_determinism`
Expected: both PASS; golden still `4_245_124_049_375_366_020`.

- [ ] **Step 8: Full verification.**

Run: `cargo test --workspace && cargo clippy --all-targets -- -D warnings && cargo fmt --all -- --check && cargo run --release -p rts-server`
Expected: all green; server prints MATCH.

- [ ] **Step 9: CONFIRM NEUTRALITY, then commit.**

If the golden hash is unchanged, the migration is neutral — commit. **If it changed, STOP and report** (ordering bug).

```bash
git add -A
git commit -m "refactor(core)!: [Player;2] -> Vec<Civ> (N-civ support, hash-neutral)"
```

---

# MIGRATION 2 — Planets + conquest (re-pins)

## Task 3: `Planet` arena, static tile→planet map, `Civ.alive`, hash re-pin

**Files:**
- Create: `crates/core/src/game/planet.rs`
- Modify: `crates/core/src/game/mod.rs` (add `pub mod planet;`), `map.rs`, `sim.rs`, `civ/mod.rs`.

- [ ] **Step 1: Create `planet.rs`.**

```rust
//! Planetary territory. A planet is a region of map tiles; a civ owns a planet
//! by holding its capital seat (a CommandCenter). Ownership is discrete and
//! event-driven (settle / capture), so it never accrues per-tick — it is
//! invisible to the LOD/closed-form machinery (determinism rules D2/D3 N/A).

use crate::fixed::Fixed;
use crate::game::sim::{CivId, EntityId};
use crate::vec::Vec2;

/// Stable index into `Sim::planets`.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Hash)]
pub struct PlanetId(pub u16);

/// One planet's mutable control state. Tile membership is stored statically on
/// the `Map`; only ownership lives here (and is hashed).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Planet {
    /// Owning civ, or `None` for a neutral/unsettled planet.
    pub owner: Option<CivId>,
    /// The controlling CommandCenter (capital). `None` when unsettled.
    pub seat: Option<EntityId>,
    /// Fixed-point world-space centre (AI distance reasoning).
    pub center: Vec2,
    /// Claim radius in world units (auxiliary; exact membership is the Map layer).
    pub radius: Fixed,
}
```

Add `pub mod planet;` to `crates/core/src/game/mod.rs`.

- [ ] **Step 2: Add the static tile→planet layer to `Map`.**

In `map.rs`, add to `struct Map` (`:54`): `planet_of: Vec<Option<PlanetId>>,`. In `Map::new` (`:64`), init `planet_of: alloc::vec![None; count],`. Add (import `use crate::game::planet::PlanetId;`):

```rust
/// The planet owning tile `(x, y)`, or `None` for open space / out of bounds.
#[must_use]
pub fn planet_at(&self, x: i32, y: i32) -> Option<PlanetId> {
    if self.in_bounds(x, y) {
        let idx = (y as usize) * usize::from(self.width) + (x as usize);
        self.planet_of[idx]
    } else {
        None
    }
}

/// Assigns tile `(x, y)` to a planet (procgen only; static thereafter).
pub fn set_planet(&mut self, x: u16, y: u16, planet: PlanetId) {
    if x < self.width && y < self.height {
        let idx = usize::from(y) * usize::from(self.width) + usize::from(x);
        self.planet_of[idx] = Some(planet);
    }
}
```

This layer is static terrain and is **not** hashed (same as `deposits`).

- [ ] **Step 3: Add `planets` to `Sim` and `alive` to `Civ`.**

In `sim.rs`: add field `planets: Vec<Planet>,` to `struct Sim` (`:555` area, near `colonies`); init `planets: Vec::new(),` in `with_civ_count`. Import `use crate::game::planet::{Planet, PlanetId};`. In `civ/mod.rs`, add `pub alive: bool,` to `Civ`; set `alive: true` in `default_civ`.

- [ ] **Step 4: Append to `state_hash` (the re-pin).**

After the entities loop in `state_hash` (after `:1411` block ends), and after the existing colonies/sectors hashing, append:

```rust
// Planetary control (event-driven; safe to hash directly — no LOD accrual).
h.write_u64(self.planets.len() as u64);
for pl in &self.planets {
    h.write_u64(match pl.owner {
        Some(c) => u64::from(c.0) + 1, // 0 reserved for neutral
        None => 0,
    });
    match pl.seat {
        Some(e) => { h.write_u64(1); h.write_u64(u64::from(e.0)); }
        None => h.write_u64(0),
    }
    h.write_i64(pl.center.x.to_bits());
    h.write_i64(pl.center.y.to_bits());
    h.write_i64(pl.radius.to_bits());
}
```

And in the per-civ loop (`:1365`), append after `unlocked_units`:

```rust
h.write_u64(u64::from(c.alive));
```

- [ ] **Step 5: Run the golden to capture the NEW hash.**

Run: `cargo test -p rts-core golden_hash_pins_cross_target_determinism -- --nocapture`
Expected: FAIL with a left/right mismatch; copy the actual (left) value.

- [ ] **Step 6: Re-pin the golden constant + document.**

Replace `4_245_124_049_375_366_020` at `sim.rs:3660` with the captured value, and add a comment line:

```rust
// Re-pinned for planetary territory: state hash now appends each civ's `alive`
// byte and the planets arena (this run has no planets -> one zero-length marker).
assert_eq!(s.state_hash(), <NEW_HASH>);
```

- [ ] **Step 7: Verify determinism + server MATCH.**

Run: `cargo test --workspace && cargo run --release -p rts-server`
Expected: PASS; server prints MATCH at the new hash. (If the server binary embeds the expected hash, update it there too.)

- [ ] **Step 8: STOP — confirmation gate, then commit.**

This is a re-pin migration. **Show the before/after hash to the user and get confirmation before committing.**

```bash
git add -A
git commit -m "feat(core)!: M-planets — Planet arena + tile->planet map + Civ.alive (re-pin)"
```

## Task 4: Build-gating to owned planets

**Files:**
- Modify: `crates/core/src/game/sim.rs` — `apply_build` (`:1749`), `apply_found_colony` (`:1960`).
- Test: `sim.rs` tests module.

- [ ] **Step 1: Write failing tests.**

```rust
#[test]
fn build_requires_owning_the_planet() {
    let mut s = Sim::new(Map::new(20, 20), 1, f(5000));
    // One planet covering a 4x4 block at the top-left, owned by nobody yet.
    let pid = PlanetId(0);
    for y in 0..4 { for x in 0..4 { s.map_mut().set_planet(x, y, pid); } }
    s.push_planet(Planet { owner: None, seat: None, center: tile_center(2, 2), radius: f(3) });

    // Build on the unowned planet is rejected (no building appears).
    s.step(&[Command::Build { owner: P0, kind: BuildingKind::Barracks, x: 1, y: 1 }]);
    assert_eq!(s.buildings_owned_by(P0), 0);

    // After P0 owns the planet, the same build succeeds.
    s.set_planet_owner(pid, Some(P0));
    s.step(&[Command::Build { owner: P0, kind: BuildingKind::Barracks, x: 1, y: 1 }]);
    assert_eq!(s.buildings_owned_by(P0), 1);

    // Open space (no planet id) stays unbuildable.
    s.step(&[Command::Build { owner: P0, kind: BuildingKind::Barracks, x: 10, y: 10 }]);
    assert_eq!(s.buildings_owned_by(P0), 1);
}
```

(Add small test/helper accessors: `map_mut(&mut self) -> &mut Map`, `push_planet(&mut self, Planet) -> PlanetId`, `set_planet_owner(&mut self, PlanetId, Option<CivId>)`, and reuse an existing building-count accessor or add `buildings_owned_by`.)

- [ ] **Step 2: Run — expect failure.**

Run: `cargo test -p rts-core build_requires_owning_the_planet`
Expected: FAIL (build currently succeeds on the unowned planet).

- [ ] **Step 3: Add the gate helper + enforce it.**

In `sim.rs`:

```rust
/// Whether `civ` may build on tile `(x, y)`: the tile must belong to a planet
/// this civ owns. Open space (no planet) is never buildable.
#[must_use]
pub fn can_build_on(&self, civ: CivId, x: u16, y: u16) -> bool {
    match self.map.planet_at(i32::from(x), i32::from(y)) {
        Some(pid) => self.planets.get(pid.0 as usize)
            .is_some_and(|pl| pl.owner == Some(civ)),
        None => false,
    }
}
```

In `apply_build` (`:1757`), add `&& self.can_build_on(owner, x, y)` to the guard. In `apply_found_colony` (`:1960`), change settling to require an **unowned** planet and claim it:

```rust
fn apply_found_colony(&mut self, owner: PlayerId, x: u16, y: u16) {
    let Some(pid) = self.map.planet_at(i32::from(x), i32::from(y)) else { return; };
    let planet_unowned = self.planets.get(pid.0 as usize).is_some_and(|pl| pl.owner.is_none());
    let p = usize::from(owner.0);
    let buildable = self.map.tile(i32::from(x), i32::from(y)).is_some_and(|t| t.buildable);
    if !buildable || !planet_unowned
        || self.civs[p].money < FOUND_COLONY_COST
        || self.count_owner_colonies(owner) >= MAX_COLONIES_PER_OWNER
    {
        return;
    }
    self.civs[p].money = self.civs[p].money - FOUND_COLONY_COST;
    let cc = self.add_building(owner, BuildingKind::CommandCenter, x, y);
    if let Some(pl) = self.planets.get_mut(pid.0 as usize) {
        pl.owner = Some(owner);
        pl.seat = Some(cc);
    }
    self.add_colony(owner, cc, AUTONOMY_FULL);
}
```

> Note: scenarios with no planets (golden/survival) call `add_building`/`add_colony` directly in setup, not through these commands, so they are unaffected.

- [ ] **Step 4: Run the test.**

Run: `cargo test -p rts-core build_requires_owning_the_planet`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(core): gate building + colony founding to owned/unowned planets"
```

## Task 5: Seat-capture conquest

**Files:**
- Modify: `crates/core/src/game/sim.rs` — `run_combat` (`:2627`, the `if killed` block at `:2799`), plus a new `apply_seat_capture`.
- Test: `sim.rs` tests module.

- [ ] **Step 1: Write the failing test.**

```rust
#[test]
fn capturing_a_seat_transfers_the_planet() {
    let mut s = Sim::new(Map::new(12, 12), 7, f(9000));
    let pid = PlanetId(0);
    for y in 0..3 { for x in 0..3 { s.map_mut().set_planet(x, y, pid); } }
    // P1 owns the planet; its CC seat sits at (1,1) with a Barracks at (0,0).
    let seat = s.add_building(P1, BuildingKind::CommandCenter, 1, 1);
    let bks = s.add_building(P1, BuildingKind::Barracks, 0, 0);
    s.push_planet(Planet { owner: Some(P1), seat: Some(seat), center: tile_center(1, 1), radius: f(2) });
    s.add_colony(P1, seat, AUTONOMY_FULL);
    // Reduce the seat to near-death, then let a P0 unit land the lethal blow.
    s.debug_set_hp(seat, f(1));
    s.add_unit_at(P0, UnitKind::Tank, tile_center(1, 1)); // adjacent attacker
    for _ in 0..30 { s.step(&[]); }

    assert_eq!(s.planet_owner(pid), Some(P0), "planet transfers to attacker");
    assert!(s.entity_alive(seat), "seat is captured intact, not destroyed");
    assert_eq!(s.entity_owner(seat), Some(P0));
    assert_eq!(s.entity_owner(bks), Some(P0), "surviving buildings transfer");
    assert_eq!(s.colony_owner_of_seat(seat), Some(P0), "colony transfers");
}
```

(Add test helpers as needed: `debug_set_hp`, `add_unit_at`, `entity_alive`, `entity_owner`, `planet_owner`, `colony_owner_of_seat`. Keep them `#[cfg(test)]` or minimal `pub` accessors mirroring existing ones.)

- [ ] **Step 2: Run — expect failure.**

Run: `cargo test -p rts-core capturing_a_seat_transfers_the_planet`
Expected: FAIL — the seat dies and the planet stays P1.

- [ ] **Step 3: Detect captures in `run_combat`.**

Declare `let mut captures: Vec<(usize, PlayerId)> = Vec::new();` alongside `damage` (`:2687`). In the `if killed` block (`:2799-2803`), after the kill-credit lines, add (read the attacker's owner before the `&mut` borrow ends):

```rust
let attacker_owner = self.entities[attacker].owner;
if self.entities[j].kind == Kind::Building(BuildingKind::CommandCenter)
    && self.planets.iter().any(|pl| pl.seat == Some(EntityId(j as u32)))
{
    captures.push((j, attacker_owner));
}
```

After `self.attacks = lines;` (`:2805`), apply them:

```rust
for (seat_idx, attacker) in captures {
    self.apply_seat_capture(seat_idx, attacker);
}
```

- [ ] **Step 4: Implement `apply_seat_capture`.**

Add this method (use field-destructuring to borrow `entities` and `map` disjointly):

```rust
/// Capture (not destroy) a planet seat: flip the seat + planet to `attacker`,
/// restore the seat to a fraction of max HP, re-owner the planet's surviving
/// buildings, and transfer the seated colony (autonomy/policy reset).
fn apply_seat_capture(&mut self, seat_idx: usize, attacker: PlayerId) {
    let seat_id = EntityId(seat_idx as u32);
    let Some(pidx) = self.planets.iter().position(|pl| pl.seat == Some(seat_id)) else { return; };
    let pid = PlanetId(pidx as u16);

    let cc_max = self.balance.building(BuildingKind::CommandCenter).max_hp;
    let frac = self.balance.capture_hp_fraction;
    self.entities[seat_idx].hp = cc_max * frac;
    self.entities[seat_idx].owner = attacker;
    self.planets[pidx].owner = Some(attacker);

    // Re-owner surviving buildings whose tile belongs to this planet.
    let Sim { entities, map, .. } = self;
    for e in entities.iter_mut() {
        if e.alive && matches!(e.kind, Kind::Building(_)) {
            if let Some((tx, ty)) = e.tile {
                if map.planet_at(i32::from(tx), i32::from(ty)) == Some(pid) {
                    e.owner = attacker;
                }
            }
        }
    }

    // Transfer the seated colony; reset earned autonomy/policy under the new owner.
    for c in &mut self.colonies {
        if c.alive && c.seat == seat_id {
            c.owner = attacker;
            c.autonomy_level = 0;
            c.autonomy_progress = 0;
            c.policy = ColonyPolicy::default();
            c.sector = None;
        }
    }
}
```

> Determinism (D1): the capturer is the owner of the unique lethal blow (`was_alive && hp <= 0` fires once per entity per tick); damage entries process in attacker-index order, so the result is replay-stable with no `rng`.

- [ ] **Step 5: Run the test + a determinism re-run.**

Run: `cargo test -p rts-core capturing_a_seat_transfers_the_planet`
Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(core): seat-capture conquest (planet + buildings + colony transfer)"
```

## Task 6: Elimination + generalized victory (`run_conquest`)

**Files:**
- Modify: `crates/core/src/game/sim.rs` — `step` (`:1571`), new `run_conquest`, `winner` (read `civ.alive`).
- Test: `sim.rs` tests module.

- [ ] **Step 1: Write the failing test.**

```rust
#[test]
fn losing_last_command_center_eliminates_and_decides_winner() {
    let mut s = Sim::new(Map::new(16, 16), 3, f(2000));
    let a = s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
    let _b = s.add_building(P1, BuildingKind::CommandCenter, 13, 13);
    // Kill P0's only CC outright (no planet -> normal death, not capture).
    s.debug_set_hp(a, f(0));
    s.step(&[]);
    assert!(!s.civ_alive(P0), "civ with no CC is eliminated");
    assert!(s.civ_alive(P1));
    assert_eq!(s.winner(), Some(P1), "sole survivor wins");
}
```

- [ ] **Step 2: Run — expect failure.**

Run: `cargo test -p rts-core losing_last_command_center_eliminates_and_decides_winner`
Expected: FAIL — `civ_alive` missing / `alive` never updated.

- [ ] **Step 3: Implement `run_conquest` and wire it into `step`.**

A civ is alive iff it holds ≥1 CommandCenter (the concrete realization of the spec's "owns ≥1 planet": equivalent in planet scenarios, and the only definition that also works in planet-free scenarios like the golden/survival replay).

```rust
/// Recompute each civ's `alive` flag from CommandCenter possession. Runs after
/// `clear_dead` so destroyed/transferred seats are reflected. No `rng` (D1);
/// no per-tick accrual (D2/D3 N/A).
fn run_conquest(&mut self) {
    let mut holds_cc = alloc::vec![false; self.civs.len()];
    for e in &self.entities {
        if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
            let i = usize::from(e.owner.0);
            if i < holds_cc.len() {
                holds_cc[i] = true;
            }
        }
    }
    for (i, c) in self.civs.iter_mut().enumerate() {
        c.alive = holds_cc[i];
    }
}
```

Add `self.run_conquest();` to `step` immediately after `self.clear_dead();` (`:1585`). Add accessor:

```rust
#[must_use]
pub fn civ_alive(&self, civ: CivId) -> bool {
    self.civs.get(usize::from(civ.0)).is_some_and(|c| c.alive)
}
```

Optionally simplify `winner()` to read `civ.alive` instead of rescanning entities (it now mirrors `run_conquest`), keeping the Survey early-return and survival special-case.

- [ ] **Step 4: Run the test + golden (alive now actively maintained).**

Run: `cargo test -p rts-core losing_last_command_center_eliminates_and_decides_winner golden_hash_pins_cross_target_determinism`
Expected: both PASS. (Golden civs hold their CCs for all 120 ticks → `alive` stays `true` → hash matches the Task 3 re-pin.)

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(core): per-civ elimination + N-civ victory (run_conquest)"
```

## Task 7: Balance field, conquest scenario, and AI conquest behavior

**Files:**
- Modify: `crates/core/src/game/balance.rs` (`:21`/`:30`), `crates/data/balance.ron`, `crates/core/src/game/scenario.rs`, `ai_commands` (`:2840`).
- Test: `scenario.rs` tests module.

- [ ] **Step 1: Add `capture_hp_fraction` to `Balance`.**

In `balance.rs` `struct Balance` add `pub capture_hp_fraction: Fixed,`; in `const_default()` set `capture_hp_fraction: Fixed::from_ratio(1, 4),`. Add the matching key to `crates/data/balance.ron` (`capture_hp_fraction: (...)` in the same `Fixed` serialization form used by neighboring fields — copy an adjacent `Fixed` field's syntax).

- [ ] **Step 2: Write a failing deterministic conquest-scenario test.**

```rust
#[test]
fn conquest_scenario_is_deterministic_and_resolves() {
    fn run() -> u64 {
        let mut s = scenario::conquest(12_345, 4); // 4 civs, generated planets
        for _ in 0..400 {
            let cmds: Vec<Command> = (0..4u16)
                .filter(|&id| s.civ_alive(PlayerId(id)))
                .flat_map(|id| s.ai_commands(PlayerId(id)))
                .collect();
            s.step(&cmds);
        }
        s.state_hash()
    }
    assert_eq!(run(), run());
}
```

- [ ] **Step 3: Run — expect failure.**

Run: `cargo test -p rts-core conquest_scenario_is_deterministic_and_resolves`
Expected: FAIL — `scenario::conquest` missing.

- [ ] **Step 4: Implement `scenario::conquest`.**

Add to `scenario.rs`: build a `Sim::with_civ_count(map, seed, credits, civ_count)`, then deterministically lay out planets (e.g. evenly spaced regions on the 40×40 map). For each civ: pick a home-planet region, `map.set_planet` its tiles, `add_building` a CommandCenter at its centre, `push_planet { owner: Some(civ), seat: Some(cc), .. }`, and `add_colony`. Add 1–2 neutral planets (`owner: None, seat: None`) as expansion targets. Keep all layout choices index-driven (no `rng`) so the run is reproducible (D1).

- [ ] **Step 5: Extend `ai_commands` for conquest (conservative).**

In `ai_commands` (`:2840`), after existing build/train/move logic, add: if the civ has idle military and a **neutral** planet is reachable and affordable, emit `Command::FoundColony` at that planet's centre (expansion-first). Only emit attack-moves toward an **enemy** seat when the civ's local force near that seat outnumbers the defender (a deterministic count comparison). Keep it pure (no `rng`). This is intentionally minimal — diplomacy refines target selection later.

- [ ] **Step 6: Run the scenario test + full suite.**

Run: `cargo test --workspace && cargo clippy --all-targets -- -D warnings && cargo fmt --all -- --check`
Expected: all green.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat(core): capture_hp_fraction + N-civ conquest scenario + conquest AI"
```

## Task 8: Render-shell — owner tinting + N-civ HUD (non-hashed)

**Files:**
- Modify: `crates/render-shell/src/view.rs` (tile draw), `crates/render-shell/src/ui.rs` (HUD), `crates/render-shell/src/main.rs` (civ iteration).

No core/hash changes — purely presentational. Verify live under Xvfb per existing M8 practice.

- [ ] **Step 1: Tint tiles by planet owner.**

In the tile-draw loop in `view.rs`, query `sim.map().planet_at(x, y)` → resolve owner via a new read accessor `Sim::planet_owner(PlanetId) -> Option<CivId>` → tint the tile with that civ's colour (reuse the existing per-player colour table; extend it to 6 entries).

- [ ] **Step 2: HUD lists all live civs.**

In `ui.rs`, replace any 2-player assumption (e.g. drawing P0/P1 only) with a loop over `0..sim.civ_count()` (add a `civ_count()` accessor), showing each civ's colour + alive/eliminated state + colony count.

- [ ] **Step 3: Build + live smoke test.**

Run: `cargo build -p rts-render-shell` then run under Xvfb (per the project's M8 verification note) and confirm planets render tinted by owner and the HUD shows all civs.

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "feat(shell): planet owner tinting + N-civ HUD"
```

---

## Self-review notes (addressed)

- **Spec coverage:** civ count → Tasks 1–2; planets/ownership → Task 3; build-gating → Task 4; seat capture (transfer tiles+buildings+colony, autonomy reset) → Task 5; elimination/victory → Task 6; capture-HP balance + scenario + conquest AI → Task 7; render → Task 8. Determinism §5 → gates in Tasks 2 & 3.
- **Refinement vs spec:** aliveness is realized as "holds ≥1 CommandCenter" rather than "owns ≥1 planet" — equivalent in planet scenarios (every planet seat is a CC) and necessary so planet-free scenarios (golden/survival) keep working. Noted in Task 6. Consider a one-line spec amendment.
- **Capture attribution:** the spec's "lowest-CivId tiebreak" is effectively unreachable (only one blow crosses zero); the implementation uses lethal-blow owner in deterministic damage-processing order. Equivalent and fully deterministic.
- **`new` loses `const`:** unavoidable with `Vec` init; `with_civ_count` is the general constructor, `new` delegates with `civ_count = 2` to preserve every existing caller and the golden.
- **Type consistency:** `CivId = PlayerId` (u16) throughout; `PlanetId(u16)`; `EntityId(u32)` with `EntityId(n)` indexing `entities[n]`; `Balance::capture_hp_fraction: Fixed`; `Map::planet_at(i32,i32)`/`set_planet(u16,u16)`.
- **Test helpers:** several small `#[cfg(test)]`/`pub` accessors are introduced in Tasks 4–6 (`map_mut`, `push_planet`, `set_planet_owner`, `debug_set_hp`, `add_unit_at`, `entity_alive`/`entity_owner`, `planet_owner`, `colony_owner_of_seat`, `buildings_owned_by`, `civ_alive`, `civ_count`). Mirror existing accessor style in `sim.rs`.
