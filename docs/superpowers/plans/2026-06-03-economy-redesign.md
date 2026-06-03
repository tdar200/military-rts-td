# Economy & Pacing Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the passive-trickle economy with a Civ-style multi-resource economy mined from finite map deposits, give every building a real role, and re-pace the game with a ~3-minute peaceful build-up before gentle alien waves.

**Architecture:** All gameplay stays in the deterministic `crates/core` (fixed-point, `no_std`, no I/O). Map tiles gain optional finite **deposits**; per-player resources become **Minerals / Energy / Research / Alloys**; **Extractors** mine the deposit they stand on; **Labs** produce Research that funds tech; the survival **wave director** gets a long first delay + gentler escalation. The shell renders the new resources + deposits. Every core change is hashed into `Sim::state_hash`, the golden hash is re-pinned, and `cargo run -p rts-server` must report zero client/server drift.

**Tech Stack:** Rust (workspace: `rts-core` no_std sim, `rts-data` RON balance loader, `rts-render-shell` Macroquad client, `rts-server` headless verifier). Fixed-point math via `rts_core::fixed::Fixed`. RON for balance data.

**Spec:** `docs/superpowers/specs/2026-06-03-economy-redesign-design.md`

**Resolved open questions (from spec):**
- **Alloy mining:** ONE Extractor (the Refinery building) mines whatever deposit kind it sits on — Ore→Minerals, Alloy→Alloys. No separate Alloy Refinery. (The existing `antimatter_plant` building is repurposed as a second placeable Extractor with no special behavior, or left as-is; mining is driven by the deposit, not the building variant.)
- **Research:** a one-time Research **cost** paid from an accumulated **pool** (Labs add to the pool each tick).

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `crates/core/src/game/map.rs` | grid + tiles + **deposits** | add `Deposit`, `DepositKind`, parallel deposit storage, `deposit`/`set_deposit`/`mine` |
| `crates/core/src/game/sim.rs` | sim state, economy, hashing, commands, accessors | rename resources → 4-resource model; add `research` pool; add mining; reroute tech cost to research; hash deposits + research; re-pin golden |
| `crates/core/src/game/stats.rs` | `BuildingStats` | add `research_income`, `mine_rate`; drop reliance on `credit_income` for refinery |
| `crates/data/src/lib.rs` + `crates/data/balance.ron` | RON balance | add `research_income`/`mine_rate` fields; retune costs as Minerals; lab Research |
| `crates/core/src/game/tech.rs` | tech defs | (no structural change; cost is reinterpreted as Research) |
| `crates/core/src/game/procgen.rs` | survival map gen | scatter ore + alloy deposits; guarantee near-base ore |
| `crates/core/src/game/scenario.rs` | scenarios + survival builder | place deposits; re-pace survival waves |
| `crates/render-shell/src/ui.rs` | HUD | show Minerals/Energy/Research/Alloys |
| `crates/render-shell/src/main.rs` | board render + build ghost | draw deposits; highlight deposit tiles for Extractor |

**Determinism rule for every core task:** if you add/rename a field that influences the sim, update `Sim::state_hash` (`sim.rs`) in the same task, then run the golden test, read the new hash, and re-pin the `assert_eq!(s.state_hash(), …)` constant. Finish each core task with `cargo run -p rts-server` and confirm `re-simulation … MATCH ✓`.

**Build note:** native shell builds with audio need the ALSA link shim in this sandbox: `LIBRARY_PATH=/tmp/alsa-shim` (create once: `mkdir -p /tmp/alsa-shim && ln -sf /lib/x86_64-linux-gnu/libasound.so.2 /tmp/alsa-shim/libasound.so`). CI / core / server builds do **not** need it.

---

## Phase 1 — Deposits as map state

### Task 1: Deposit types + storage on the Map

**Files:**
- Modify: `crates/core/src/game/map.rs`

- [ ] **Step 1: Write the failing test** (append to `map.rs` `mod tests`)

```rust
#[test]
fn deposits_default_empty_and_round_trip() {
    let mut m = Map::new(6, 4);
    assert_eq!(m.deposit(2, 1), None);
    m.set_deposit(2, 1, Deposit { kind: DepositKind::Ore, remaining: 500 });
    assert_eq!(m.deposit(2, 1), Some(Deposit { kind: DepositKind::Ore, remaining: 500 }));
    // mine() removes up to `amount`, returns the amount actually mined, depletes.
    assert_eq!(m.mine(2, 1, 200), 200);
    assert_eq!(m.deposit(2, 1).unwrap().remaining, 300);
    assert_eq!(m.mine(2, 1, 999), 300); // clamps to remaining
    assert_eq!(m.deposit(2, 1), None);  // exhausted → cleared
    assert_eq!(m.mine(5, 5, 10), 0);    // out of bounds / no deposit
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core deposits_default_empty_and_round_trip`
Expected: FAIL — `Deposit`/`DepositKind`/`deposit`/`set_deposit`/`mine` not found.

- [ ] **Step 3: Implement** (in `map.rs`, after the `Tile` impl)

```rust
/// What a map deposit yields when mined by an Extractor standing on it.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum DepositKind {
    /// Mines into the owner's Minerals (common).
    Ore,
    /// Mines into the owner's Alloys (rare).
    Alloy,
}

/// A finite resource deposit on a tile.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct Deposit {
    /// Which resource it yields.
    pub kind: DepositKind,
    /// Units of resource left; the deposit is removed when this reaches 0.
    pub remaining: u32,
}
```

Add a field to `Map` (parallel to `tiles`): in `struct Map { … deposits: Vec<Option<Deposit>>, }`, and in `Map::new`, after building `tiles`:

```rust
let deposits = alloc::vec![None; count];
Self { width, height, tiles, deposits }
```

Add methods to `impl Map`:

```rust
/// The deposit at `(x, y)`, if any (and in bounds).
#[must_use]
pub fn deposit(&self, x: u16, y: u16) -> Option<Deposit> {
    if x < self.width && y < self.height {
        self.deposits[usize::from(y) * usize::from(self.width) + usize::from(x)]
    } else {
        None
    }
}

/// Places (or clears, with `None`) a deposit. Out-of-bounds is ignored.
pub fn set_deposit(&mut self, x: u16, y: u16, deposit: Deposit) {
    if x < self.width && y < self.height {
        self.deposits[usize::from(y) * usize::from(self.width) + usize::from(x)] = Some(deposit);
    }
}

/// Mines up to `amount` from the deposit at `(x, y)`; returns the amount actually
/// mined and decrements `remaining` (clearing the deposit when exhausted).
pub fn mine(&mut self, x: u16, y: u16, amount: u32) -> u32 {
    if x >= self.width || y >= self.height {
        return 0;
    }
    let i = usize::from(y) * usize::from(self.width) + usize::from(x);
    let Some(dep) = self.deposits[i].as_mut() else {
        return 0;
    };
    let mined = amount.min(dep.remaining);
    dep.remaining -= mined;
    if dep.remaining == 0 {
        self.deposits[i] = None;
    }
    mined
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `cargo test -p rts-core deposits_default_empty_and_round_trip`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add crates/core/src/game/map.rs
git commit -m "feat(core): finite resource deposits on the map"
```

### Task 2: Hash deposits into the sim fingerprint + iterator for the shell

**Files:**
- Modify: `crates/core/src/game/map.rs` (add a `deposits()` iterator)
- Modify: `crates/core/src/game/sim.rs` (`state_hash`, re-pin golden)

- [ ] **Step 1: Write the failing test** (in `map.rs` tests)

```rust
#[test]
fn deposits_iter_lists_placed_deposits() {
    let mut m = Map::new(4, 4);
    m.set_deposit(1, 1, Deposit { kind: DepositKind::Ore, remaining: 100 });
    m.set_deposit(3, 0, Deposit { kind: DepositKind::Alloy, remaining: 50 });
    let mut got: alloc::vec::Vec<(u16, u16, DepositKind, u32)> =
        m.deposits().map(|(x, y, d)| (x, y, d.kind, d.remaining)).collect();
    got.sort_unstable();
    assert_eq!(
        got,
        alloc::vec![(1, 1, DepositKind::Ore, 100), (3, 0, DepositKind::Alloy, 50)]
    );
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core deposits_iter_lists_placed_deposits`
Expected: FAIL — `deposits()` not found.

- [ ] **Step 3: Implement** the iterator in `impl Map`:

```rust
/// Iterates `(x, y, Deposit)` for every tile that has a deposit, in row-major
/// order (deterministic).
pub fn deposits(&self) -> impl Iterator<Item = (u16, u16, Deposit)> + '_ {
    let w = self.width;
    self.deposits.iter().enumerate().filter_map(move |(i, d)| {
        d.map(|dep| {
            let idx = u16::try_from(i).unwrap_or(0);
            (idx % w, idx / w, dep)
        })
    })
}
```

- [ ] **Step 4: Hash deposits in `Sim::state_hash`** — in `sim.rs`, at the end of `state_hash` (after the free-list loop, before `h.finish()`), add:

```rust
// Deposits are world state that drives the economy → must be hashed.
for (x, y, dep) in self.map.deposits() {
    h.write_u64(u64::from(x));
    h.write_u64(u64::from(y));
    h.write_u64(match dep.kind {
        crate::game::map::DepositKind::Ore => 0,
        crate::game::map::DepositKind::Alloy => 1,
    });
    h.write_u64(u64::from(dep.remaining));
}
```

- [ ] **Step 5: Run the iterator test + golden test**

Run: `cargo test -p rts-core deposits_iter_lists_placed_deposits golden_hash`
Expected: iterator test PASS; `golden_hash` PASS (the golden scenario places no deposits, so the new loop adds nothing → hash unchanged). If it unexpectedly fails, read the `left:` value and re-pin the constant in `golden_hash_pins_cross_target_determinism`.

- [ ] **Step 6: Commit**

```bash
git add crates/core/src/game/map.rs crates/core/src/game/sim.rs
git commit -m "feat(core): hash map deposits; expose deposits() iterator"
```

---

## Phase 2 — Four-resource model (Minerals / Energy / Research / Alloys)

This phase renames `credits→minerals`, `antimatter→alloys`, and adds a `research` pool. Energy stays computed (the existing power balance). It is mostly a mechanical rename plus one new field.

### Task 3: Rename Player resource fields + add `research`

**Files:**
- Modify: `crates/core/src/game/sim.rs`

- [ ] **Step 1: Find every reference** so nothing is missed:

```bash
cd crates/core && grep -n "credits\|antimatter" src/game/sim.rs
```

- [ ] **Step 2: Rename + add the field.** In `struct Player`, change `credits: Fixed` → `minerals: Fixed`, `antimatter: Fixed` → `alloys: Fixed`, and add `research: Fixed`. In the `Player { … }` initializer in `Sim::new`, set `minerals: starting_credits`, `alloys: Fixed::ZERO`, `research: Fixed::ZERO`.

- [ ] **Step 3: Update accessors.** Rename `pub fn credits(...)` → `pub fn minerals(...)`, `pub fn antimatter(...)` → `pub fn alloys(...)`, and add:

```rust
/// The player's accumulated Research pool (funds the tech tree).
#[must_use]
pub fn research(&self, player: PlayerId) -> Fixed {
    self.players[usize::from(player.0)].research
}
```

- [ ] **Step 4: Update internal uses.** Replace `self.players[p].credits` → `.minerals` and `.antimatter` → `.alloys` at every site found in Step 1 (economy, `apply_command` Build/Train, etc.). Leave behavior identical for now (mining + research income come in later tasks).

- [ ] **Step 5: Update `state_hash`.** Change the player loop fields: `h.write_i64(p.minerals.to_bits());`, `h.write_i64(p.alloys.to_bits());`, and add `h.write_i64(p.research.to_bits());` (keep a stable, documented field order).

- [ ] **Step 6: Build + fix the rest of the workspace.** Renamed public accessors break the shell/server/tests.

```bash
cargo build --workspace 2>&1 | tail -30
```

Fix every error by renaming `sim.credits(` → `sim.minerals(`, `sim.antimatter(` → `sim.alloys(` in `crates/render-shell/src/ui.rs`, `crates/render-shell/src/main.rs`, `crates/server/src/main.rs`, and any tests. (Use `grep -rn "\.credits(\|\.antimatter(" crates` to find them.)

- [ ] **Step 7: Run core tests + re-pin golden.**

Run: `cargo test -p rts-core 2>&1 | grep -E "test result|left:|right:"`
Expected: `golden_hash` FAILS (adding `research` to the hash changes the fingerprint even though it's 0). Read the `left:` value and update the constant in `golden_hash_pins_cross_target_determinism` to it. Re-run: all pass.

- [ ] **Step 8: Zero-drift check + commit**

```bash
cargo run -p rts-server 2>&1 | grep re-simulation   # expect MATCH ✓
git add -A
git commit -m "refactor(core): rename resources to minerals/alloys, add research pool"
```

---

## Phase 3 — Extractors mine deposits

### Task 4: Add `mine_rate` + `research_income` to building stats and balance

**Files:**
- Modify: `crates/core/src/game/stats.rs` (`BuildingStats`)
- Modify: `crates/data/src/lib.rs` (`BuildingData`, `to_building`)
- Modify: `crates/data/balance.ron`

- [ ] **Step 1: Extend `BuildingStats`** in `stats.rs` — add fields:

```rust
/// Resource/tick this building mines from a deposit it stands on (Extractors).
pub mine_rate: i32,
/// Research/tick this building produces while powered (Research Labs).
pub research_income: Fixed,
```

Update every `BuildingStats { … }` constructor in `stats.rs` (and `Balance::from_tables`/defaults) to set `mine_rate: 0, research_income: Fixed::ZERO` unless noted.

- [ ] **Step 2: Extend the RON loader** in `crates/data/src/lib.rs` — in `struct BuildingData` add:

```rust
#[serde(default)]
mine_rate: i32,
#[serde(default)]
research_income: i32,
```

and in `to_building`:

```rust
mine_rate: b.mine_rate,
research_income: Fixed::from_int(b.research_income),
```

- [ ] **Step 3: Retune `balance.ron`.** Set `refinery` (the Extractor): `credit_income: 0, mine_rate: 5, power_consumed: 20`. Set `antimatter_plant` (second Extractor): `antimatter_income: 0, mine_rate: 5`. Set `research_lab`: add `research_income: 4`. Leave unit/turret costs as-is for now (they are Minerals).

- [ ] **Step 4: Build the data crate**

Run: `cargo build -p rts-data 2>&1 | tail -10`
Expected: builds (RON `#[serde(default)]` keeps old fields optional).

- [ ] **Step 5: Commit**

```bash
git add crates/core/src/game/stats.rs crates/data/src/lib.rs crates/data/balance.ron
git commit -m "feat(core): building stats for deposit mining + research income"
```

### Task 5: Mining + research income in the economy step

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`run_economy`)

- [ ] **Step 1: Write the failing test** (in `sim.rs` tests)

```rust
#[test]
fn extractor_on_ore_mines_minerals_and_depletes() {
    let mut map = Map::new(20, 20);
    map.set_deposit(6, 2, crate::game::map::Deposit {
        kind: crate::game::map::DepositKind::Ore,
        remaining: 12,
    });
    let mut s = Sim::new(map, 1, f(0)); // start with 0 minerals
    s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
    s.add_building(P0, BuildingKind::PowerPlant, 4, 2);   // power the extractor
    s.add_building(P0, BuildingKind::Refinery, 6, 2);     // ON the ore deposit
    let before = s.minerals(P0).to_bits();
    s.step(&[]);
    assert!(s.minerals(P0).to_bits() > before, "extractor should mine minerals");
    // Deposit depletes; after enough ticks it is exhausted and yields stop.
    for _ in 0..10 { s.step(&[]); }
    assert_eq!(s.map().deposit(6, 2), None, "deposit should be exhausted");
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core extractor_on_ore_mines_minerals_and_depletes`
Expected: FAIL (no mining yet; minerals unchanged).

- [ ] **Step 3: Implement mining** in `run_economy`. After the building income loop and before/with the per-player credit application, add a mining pass. Because mining mutates `self.map` while reading entities, collect `(tile, owner, kind, rate)` first, then apply:

```rust
// Extractors mine the deposit they stand on (powered only). Collect first to
// avoid borrowing self.map while iterating entities.
let mut to_mine: alloc::vec::Vec<(u16, u16, u8, i32)> = alloc::vec::Vec::new();
for e in &self.entities {
    if !e.alive {
        continue;
    }
    if let Kind::Building(b) = e.kind {
        let rate = self.balance.building(b).mine_rate;
        if rate > 0 {
            if let Some((tx, ty)) = e.tile {
                to_mine.push((tx, ty, e.owner.0, rate));
            }
        }
    }
}
for (tx, ty, owner, rate) in to_mine {
    let Some(dep) = self.map.deposit(tx, ty) else { continue };
    // Power-deficient players mine at the same throttled `factor` as income.
    let p = usize::from(owner);
    let throttle = if powered[p] { rate } else { rate / 2 };
    let mined = self.map.mine(tx, ty, throttle.max(0) as u32);
    let amount = Fixed::from_int(mined as i32);
    match dep.kind {
        crate::game::map::DepositKind::Ore => {
            self.players[p].minerals = self.players[p].minerals + amount;
        }
        crate::game::map::DepositKind::Alloy => {
            self.players[p].alloys = self.players[p].alloys + amount;
        }
    }
}
```

(Place this after `powered` is computed. Remove the old `refinery` `credit_income` contribution by virtue of Task 4 setting it to 0 — no code change needed, but verify the income loop no longer grants credits to refineries.)

- [ ] **Step 4: Run the test**

Run: `cargo test -p rts-core extractor_on_ore_mines_minerals_and_depletes`
Expected: PASS.

- [ ] **Step 5: Re-pin golden + zero-drift.** Golden scenario has no deposits/extractors mining, so it should be unchanged; if `cargo test -p rts-core golden_hash` fails, re-pin. Then:

Run: `cargo run -p rts-server 2>&1 | grep re-simulation`  → MATCH ✓

- [ ] **Step 6: Commit**

```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): extractors mine finite deposits into minerals/alloys"
```

---

## Phase 4 — Research-funded tech

### Task 6: Labs produce Research; tech is paid from the Research pool

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`run_economy` research income; `apply_command` Research arm)

- [ ] **Step 1: Write the failing test** (in `sim.rs` tests)

```rust
#[test]
fn lab_funds_tech_from_research_pool() {
    let mut s = Sim::new(Map::new(20, 20), 1, f(0));
    s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
    s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
    s.add_building(P0, BuildingKind::ResearchLab, 6, 2);
    // No research yet → research command rejected (can't afford).
    s.step(&[Command::Research { owner: P0, tech_id: 0 }]);
    assert!(s.research_state(P0).1.is_none(), "tech 0 should be unaffordable at 0 research");
    // Accumulate research from the lab, then it becomes affordable.
    for _ in 0..400 { s.step(&[]); }
    assert!(s.research(P0).to_bits() > 0, "lab should produce research");
    s.step(&[Command::Research { owner: P0, tech_id: 0 }]);
    assert!(s.research_state(P0).1.is_some(), "tech 0 should start once research is funded");
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core lab_funds_tech_from_research_pool`
Expected: FAIL (no research income; tech still checks minerals).

- [ ] **Step 3: Implement research income** in `run_economy`. In the per-player loop where `credit_income`/`econ` is applied, also accumulate research from buildings. Add to the building-income collection: a `research[p]` accumulator summing `self.balance.building(b).research_income` for powered buildings, then `self.players[p].research = self.players[p].research + research[p] * factor;` (use the same power `factor`).

- [ ] **Step 4: Reroute the Research command cost** in `apply_command`'s `Command::Research` arm: replace the affordability check `self.players[p].credits >= def.cost` with `self.players[p].research >= def.cost`, and the deduction `self.players[p].credits = … - def.cost` with `self.players[p].research = self.players[p].research - def.cost`.

- [ ] **Step 5: Run the test + the existing research tests**

Run: `cargo test -p rts-core lab_funds_tech_from_research doctrine_fork research`
Expected: PASS. (The doctrine-fork test builds a lab + powers it; it now also needs research income time — it already runs 700 ticks, enough. If it now fails on affordability, give it a few hundred extra warm-up ticks before issuing the Research command, or start it with seeded research by running ticks first.)

- [ ] **Step 6: Re-pin golden (the golden AI may research with credits today).** Run `cargo test -p rts-core golden_hash`; if it fails, re-pin. Then `cargo run -p rts-server | grep re-simulation` → MATCH ✓.

- [ ] **Step 7: Commit**

```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): research labs fund the tech tree from a research pool"
```

---

## Phase 5 — Re-pace the survival waves

### Task 7: Long grace period + gentler escalation

**Files:**
- Modify: `crates/core/src/game/scenario.rs` (`survival` builder `WaveConfig`)

- [ ] **Step 1: Write the failing test** (in `scenario.rs` tests, `use super::survival`)

```rust
#[test]
fn survival_has_a_three_minute_grace_period() {
    let mut s = survival(7);
    // 30 Hz → 3 minutes = 5400 ticks. No wave (no enemy units) before then.
    for _ in 0..5000 {
        s.step(&[]);
    }
    assert_eq!(s.unit_count(PlayerId(1)), 0, "no waves should spawn during the grace period");
    // After the grace period, waves begin.
    for _ in 0..1000 {
        s.step(&[]);
    }
    assert!(s.unit_count(PlayerId(1)) > 0, "waves should begin after the grace period");
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core survival_has_a_three_minute_grace_period`
Expected: FAIL (current `first_delay` is 240 → waves spawn far earlier).

- [ ] **Step 3: Re-pace** the `survival()` `WaveConfig`: `first_delay: 5400` (3 min), `interval: 540` (18 s between waves), `base_size: 2`, `growth: 1`. Keep `escalate: true`.

- [ ] **Step 4: Run the test + survival determinism/overrun tests**

Run: `cargo test -p rts-core survival`
Expected: PASS. (If `survival_overruns_an_undefended_base` now needs more ticks to resolve, raise its loop bound from 8000 to e.g. 20000.)

- [ ] **Step 5: Commit**

```bash
git add crates/core/src/game/scenario.rs
git commit -m "feat(core): re-pace survival with a 3-minute grace period + gentle escalation"
```

---

## Phase 6 — Put deposits on the maps

### Task 8: Deterministic deposit placement in procgen

**Files:**
- Modify: `crates/core/src/game/procgen.rs`

- [ ] **Step 1: Write the failing test** (in `procgen.rs` tests)

```rust
#[test]
fn procgen_places_ore_and_a_near_base_deposit() {
    use crate::game::map::DepositKind;
    for seed in 0..30_u64 {
        let m = generate(seed);
        let mut ore = 0;
        let mut alloy = 0;
        let mut near_base = false;
        for (x, _y, d) in m.deposits() {
            match d.kind {
                DepositKind::Ore => ore += 1,
                DepositKind::Alloy => alloy += 1,
            }
            if x < 12 {
                near_base = true; // a deposit within reach of the left base
            }
        }
        assert!(ore >= 3, "seed {seed}: too few ore deposits ({ore})");
        assert!(alloy >= 1, "seed {seed}: no alloy deposit");
        assert!(near_base, "seed {seed}: no deposit near the player's base");
    }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core procgen_places_ore_and_a_near_base_deposit`
Expected: FAIL (procgen places no deposits yet).

- [ ] **Step 3: Implement** in `generate()` (after wreck scatter + connectivity repair, before returning). Reuse the `Lcg`. Place a guaranteed near-base ore deposit, then scatter the rest on passable, deposit-free tiles:

```rust
// A guaranteed ore deposit just outside the player's base margin.
let mid = HEIGHT / 2;
map.set_deposit(MARGIN, mid, Deposit { kind: DepositKind::Ore, remaining: 600 });
// Scatter more ore (common) + a few alloys (rare) on open, empty tiles.
let extra_ore = 4 + (rng.next() % 4) as u16; // 4..=7
let alloys = 1 + (rng.next() % 2) as u16; // 1..=2
let mut placed = 0;
let mut tries = 0;
while placed < extra_ore + alloys && tries < 400 {
    tries += 1;
    let x = rng.range(1, WIDTH - 1);
    let y = rng.range(0, HEIGHT);
    let t = map.tile(i32::from(x), i32::from(y));
    if t.is_some_and(|t| t.passable) && map.deposit(x, y).is_none() {
        let kind = if placed < extra_ore { DepositKind::Ore } else { DepositKind::Alloy };
        let remaining = if matches!(kind, DepositKind::Ore) { 500 } else { 300 };
        map.set_deposit(x, y, Deposit { kind, remaining });
        placed += 1;
    }
}
```

Add `use crate::game::map::{Deposit, DepositKind};` (extend the existing `use crate::game::map::{Map, Tile};`).

- [ ] **Step 4: Run the test + the existing procgen tests**

Run: `cargo test -p rts-core procgen`
Expected: PASS (determinism test `same_seed_is_identical…` still passes because placement is seeded; deposits don't affect `blocked_cells` which checks `passable`).

- [ ] **Step 5: Commit**

```bash
git add crates/core/src/game/procgen.rs
git commit -m "feat(core): scatter ore + alloy deposits in procgen with a near-base guarantee"
```

### Task 9: Deposits on the hand-built scenarios + survival start economy

**Files:**
- Modify: `crates/core/src/game/scenario.rs`

- [ ] **Step 1: Write the failing test** (in `scenario.rs` tests)

```rust
#[test]
fn every_wave_map_has_minable_deposits() {
    for &sc in &[Scenario::LaneDefense, Scenario::Crossroads, Scenario::Survival] {
        let s = sc.build(7);
        let count = s.map().deposits().count();
        assert!(count >= 2, "{}: needs deposits to mine ({count})", sc.name());
    }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core every_wave_map_has_minable_deposits`
Expected: FAIL (hand maps have no deposits; survival relies on procgen which now does — survival may already pass, lane/crossroads fail).

- [ ] **Step 3: Implement.** In `lane_defense` and `crossroads`, after `Map::new(...)` and the wall band, add a handful of deposits with `map.set_deposit(...)` on open tiles near each base + contested mid-map (e.g., lane_defense: ore at `(8,5)`, `(8,15)`, `(40,5)`; an alloy at `(24,3)`). In `survival`, no change needed (procgen handles it), but verify the player start (`mid` row, col 3) has the procgen near-base ore reachable.

- [ ] **Step 4: Run the test + all scenario tests**

Run: `cargo test -p rts-core scenario`
Expected: PASS (`every_scenario_keeps_the_battlefield_connected` unaffected; deposits don't block).

- [ ] **Step 5: Re-pin golden if needed + zero-drift, then commit.** (The golden scenario is `Sim::new` + bare CommandCenters, no scenario builder, so unaffected.)

```bash
cargo run -p rts-server 2>&1 | grep re-simulation   # MATCH ✓
git add crates/core/src/game/scenario.rs
git commit -m "feat(core): place deposits on the hand-built wave scenarios"
```

---

## Phase 7 — Shell: show the new economy

### Task 10: Four-resource top bar

**Files:**
- Modify: `crates/render-shell/src/ui.rs` (`draw_top_bar`)

- [ ] **Step 1: Implement** — in `draw_top_bar`, replace the single credits readout + the `AM` antimatter readout with four labelled yields: Minerals (`sim.minerals(HUMAN)`), Energy (the existing `power_balance` produced/consumed), Research (`sim.research(HUMAN)`), Alloys (`sim.alloys(HUMAN)`). Reuse `icon_coin`/`icon_bolt` and the existing `text`/`ribbon_divider` helpers; format each as integer (`to_bits()/65536`). Keep the `holo_flicker` on the Minerals headline.

(No test — this is presentation. Verify by build + screenshot.)

- [ ] **Step 2: Build native + wasm**

```bash
cargo build -p rts-render-shell 2>&1 | tail -3
cargo build -p rts-render-shell --target wasm32-unknown-unknown 2>&1 | tail -3
```

Expected: both compile (accessors renamed in Phase 2).

- [ ] **Step 3: Commit**

```bash
git add crates/render-shell/src/ui.rs
git commit -m "feat(shell): four-resource HUD (minerals/energy/research/alloys)"
```

### Task 11: Render deposits on the board + Extractor placement hint

**Files:**
- Modify: `crates/render-shell/src/main.rs` (`draw_ground` or a new `draw_deposits`, called from `draw`; `draw_build_ghost`)

- [ ] **Step 1: Implement deposit rendering.** Add `fn draw_deposits(sim: &Sim, cell: f32, ox: f32, wtop: f32)` that iterates `sim.map().deposits()` and draws a glyph per deposit tile via `hex_center_px` — e.g., a cluster of small cyan diamonds for `Ore` and amber/gold for `Alloy`, sized `cell*0.2`, with a faint count ring. Call it in `draw()` right after `draw_ground` (under pieces, above fog). Use `theme::GOLD`/`theme::WARN` for ore/alloy tint.

- [ ] **Step 2: Highlight deposit tiles during Extractor placement.** In `draw_build_ghost`, when `kind == BuildingKind::Refinery` (or `AntimatterPlant`), outline deposit tiles in cyan so the player sees where to place; if the moused tile has a deposit, tint the ghost green.

- [ ] **Step 3: Build native + wasm, then screenshot-verify** (run `./web/build.sh` or the native binary) that deposits appear and the Extractor ghost highlights them.

- [ ] **Step 4: Commit**

```bash
git add crates/render-shell/src/main.rs
git commit -m "feat(shell): draw map deposits + Extractor placement hints"
```

---

## Phase 8 — AI claims deposits + final balance & verification

### Task 12: Teach the AI to mine

**Files:**
- Modify: `crates/core/src/game/sim.rs` (`ai_commands`)

- [ ] **Step 1: Write the failing test** (in `sim.rs` tests)

```rust
#[test]
fn ai_claims_and_mines_a_nearby_deposit() {
    let mut map = Map::new(24, 12);
    map.set_deposit(7, 6, crate::game::map::Deposit {
        kind: crate::game::map::DepositKind::Ore,
        remaining: 800,
    });
    let mut s = Sim::new(map, 1, f(100_000));
    s.add_building(P1, BuildingKind::CommandCenter, 4, 6);
    // Drive the AI; it should place a Refinery on the deposit and start mining it,
    // which decrements (or exhausts) the deposit.
    for _ in 0..500 {
        let cmds = s.ai_commands(P1);
        s.step(&cmds);
    }
    let mined = s.map().deposit(7, 6).map_or(true, |d| d.remaining < 800);
    assert!(mined, "AI never claimed and mined the deposit");
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cargo test -p rts-core ai_claims_and_mines_a_nearby_deposit`
Expected: FAIL (AI ignores deposits).

- [ ] **Step 3: Implement** in `ai_commands`: after the AI's essential build order, scan `self.map.deposits()` for the nearest unclaimed (no friendly Refinery on it) deposit reachable from the AI's base, and if the AI can afford a Refinery, emit `Command::Build { owner: player, kind: BuildingKind::Refinery, x, y }` on that tile. Keep it deterministic: iterate deposits in `deposits()` (row-major) order and pick the first unclaimed one (no RNG; `ai_commands` is pure `&self`).

- [ ] **Step 4: Run the test**

Run: `cargo test -p rts-core ai_claims_and_mines_a_nearby_deposit`
Expected: PASS.

- [ ] **Step 5: Re-pin golden + zero-drift.** The golden scenario has no deposits, so the new AI branch is a no-op there → golden unchanged. Confirm `cargo test -p rts-core golden_hash` passes; `cargo run -p rts-server | grep re-simulation` → MATCH ✓.

- [ ] **Step 6: Commit**

```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): AI claims and mines deposits"
```

### Task 13: Balance pass + full verification

**Files:**
- Modify: `crates/data/balance.ron` (tune as needed)

- [ ] **Step 1: Playtest the economy via the server.** Run `cargo run -p rts-server` and confirm a decisive/known result + MATCH. Then run a survival smoke check by adding (temporarily) or reusing `survival_overruns_an_undefended_base` to confirm the 3-minute grace + mining produce a sane curve.

- [ ] **Step 2: Tune** starting minerals (`Sim::new` `starting_credits` callers / scenario `Fixed::from_int(...)`), `mine_rate`, deposit `remaining`, and wave numbers so a player can claim 1-2 deposits and field defenses before wave 1. Adjust in `balance.ron` / `scenario.rs` only.

- [ ] **Step 3: Full gate.**

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
LIBRARY_PATH=/tmp/alsa-shim cargo clippy -p rts-render-shell --all-targets --features audio -- -D warnings
cargo test --workspace
cargo run -p rts-server 2>&1 | grep re-simulation
cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown --features audio
```

Expected: fmt clean, clippy clean (both audio configs), all tests pass, `MATCH ✓`, wasm builds.

- [ ] **Step 4: Visual check.** `./web/build.sh` (browser) or `cargo run -p rts --features audio`: confirm the 3-minute calm, deposits on the map, Extractors mining (Minerals rising only when on a deposit), the four-resource HUD, Research funding tech, and waves starting gently after the grace period.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "balance: tune deposit economy + survival pacing"
```

---

## Self-review notes (coverage map)

- Spec §"Economy — four resources" → Phase 2 (resources) + Phase 3 (mining) + Phase 4 (research).
- Spec §"Buildings — each gets a real job" → Task 4/5 (Extractor mines, Reactor=Energy already, Lab=Research) + Task 11 (placement hint).
- Spec §"Pacing" → Phase 5.
- Spec §"Map" → Phase 6.
- Spec §"Tech" → Phase 4.
- Spec §"Deterministic-core impact" → the per-task golden re-pin + zero-drift steps; deposits hashed in Task 2; resources/research hashed in Task 3.
- Spec §"What carries over unchanged" → no task touches theme/juice/audio/fog/perks/veterancy; they remain.

**Energy note:** "Energy" is the existing power system (produced/consumed, gradient throttle) — no rename needed beyond HUD labelling (Task 10); it already gates building output and now also throttles mining (Task 5 Step 3).
