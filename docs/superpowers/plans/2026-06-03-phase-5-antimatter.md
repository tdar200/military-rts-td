# Phase 5 — Antimatter (Third Resource) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** A third resource, **Antimatter**, produced by a new **Antimatter Plant** building (passive trickle while powered) and required (with credits) to train the **Capital Ship** — a top-tier economic gate. Shown in the HUD; the AI builds plants and fields Capitals.

**Architecture:** A new `antimatter_income: Fixed` field on `BuildingStats` (default `ZERO`, >0 only for the new `AntimatterPlant`). Per-player `antimatter: Fixed` in `Sim` (hashed). `run_economy` accrues antimatter from powered Antimatter Plants (same power-factor as credits). The Capital Ship Train command now also requires/deducts `CAPITAL_ANTIMATTER_COST`. Golden hash re-pinned once (per-player antimatter enters the hash, zero-valued in the golden run since no plant is built there).

**Tech Stack:** `rts-core` (no_std, fixed-point, golden-hash determinism), `rts-data`, `rts-render-shell`.

**Spec:** [`../specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 5. (Phases 0–4 merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase5-antimatter` (from `feat/core-foundation`). Tree clean.
- Stage only each task's files; never `git add -A`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism:** golden hash (currently `14_227_407_528_270_883_136`) re-pinned in **T2** only. Re-pin = run test, read actual hash, paste, re-run. Never elsewhere.
- **Locked (first-pass, tunable):** Antimatter Plant: 300 HP, power_consumed 20, antimatter_income 5/tick, cost 200. `CAPITAL_ANTIMATTER_COST = 100`. AI builds a plant only at Era 1+.

---

## Task 1: `antimatter_income` field + Antimatter Plant building (hash-preserving)

**Files:** `stats.rs`, `balance.rs`, `crates/data/src/lib.rs`, `crates/data/balance.ron`, `sim.rs` (kind_tag), render-shell `ui.rs` + `sprites.rs`.

- [ ] **Step 1: failing test (balance.rs).**
```rust
    #[test]
    fn antimatter_plant_produces_antimatter_and_draws_power() {
        use crate::game::stats::BuildingKind;
        let st = BuildingKind::AntimatterPlant.stats();
        assert!(st.antimatter_income > crate::fixed::Fixed::ZERO);
        assert!(st.power_consumed > 0);
        assert!(!st.produces_units && st.attack.is_none());
        // Existing buildings produce no antimatter.
        assert_eq!(BuildingKind::Refinery.stats().antimatter_income, crate::fixed::Fixed::ZERO);
    }
```
Extend the test `BUILDING_KINDS` const to `[BuildingKind; 9]` adding `BuildingKind::AntimatterPlant`.

- [ ] **Step 2: run → compile failure** (no `antimatter_income`, no `AntimatterPlant`).

- [ ] **Step 3 (stats.rs):** add `pub antimatter_income: Fixed,` to `BuildingStats` (after `credit_income`, doc `/// Antimatter generated per tick while powered (Antimatter Plant only).`). Add `antimatter_income: Fixed::ZERO,` to the `base()` helper in `BuildingKind::stats()`. Add `AntimatterPlant` to the `BuildingKind` enum (after `ResearchLab`). Add the stats arm:
```rust
            Self::AntimatterPlant => BuildingStats {
                power_consumed: 20,
                antimatter_income: Fixed::from_int(5),
                ..base(300, 200)
            },
```

- [ ] **Step 4 (balance.rs):** buildings inner array `[BuildingStats; 8]` → `9` (struct field, `from_tables` param); `const_default` buildings list adds `BuildingKind::AntimatterPlant.stats()` (9th); `building_in` adds `BuildingKind::AntimatterPlant => tier[8]`; the test `BUILDING_KINDS` const → `[BuildingKind; 9]` (done in Step 1).

- [ ] **Step 5 (rts-data):** `BuildingData` add `#[serde(default)] antimatter_income: i32,` (serde default so existing RON entries need no change). `to_building` maps `antimatter_income: Fixed::from_int(b.antimatter_income),`. `load()` buildings array adds `to_building(&data.antimatter_plant)` (9th). `BalanceData` add `antimatter_plant: BuildingData`. `balance.ron`: add an `antimatter_plant` entry: `(max_hp: 300, power_produced: 0, power_consumed: 20, credit_income: 0, antimatter_income: 5, produces_units: false, attack: None, cost: 200)`. (Confirm `default_ron_matches_the_code_default` still passes — code & RON both yield antimatter_income 0 for old buildings, 5 for the plant.)

- [ ] **Step 6 (sim.rs):** `kind_tag` building match add `BuildingKind::AntimatterPlant => 9` (unique; existing tags 1-8 used).

- [ ] **Step 7 (render-shell exhaustive matches):** `ui.rs` `human_name_role`: `EntityKindView::Building(BuildingKind::AntimatterPlant) => ("Antimatter Plant", "Produces antimatter"),`; `alien_name_role`: `EntityKindView::Building(BuildingKind::AntimatterPlant) => ("Singularity", "Produces antimatter"),`. `sprites.rs`: add an `AntimatterPlant` arm reusing the refinery sprite (merge-arm if clippy `match_same_arms` requires). `cargo build --workspace`; fix any other flagged `BuildingKind` match.

- [ ] **Step 8: verify + commit.** `cargo test -p rts-core antimatter_plant_produces` → PASS; `cargo test -p rts-data` → PASS; `golden_hash_pins_cross_target_determinism` → **UNCHANGED** (BuildingStats isn't hashed; no plant in the golden run); `cargo test --workspace`; clippy; fmt. Commit (the files): `feat(core): add Antimatter Plant building + antimatter_income stat (hash-preserving)`.

---

## Task 2: Per-player antimatter — state, economy, Capital cost, hash (re-pin)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.**
```rust
    #[test]
    fn antimatter_accrues_and_gates_capital() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(20_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::AntimatterPlant, 4, 2);
        assert_eq!(s.antimatter(P0), crate::fixed::Fixed::ZERO);
        for _ in 0..50 { s.step(&[]); }
        assert!(s.antimatter(P0) > crate::fixed::Fixed::ZERO, "antimatter accrues from a powered plant");
    }
```

- [ ] **Step 2: run → compile failure** (`antimatter` accessor missing).

- [ ] **Step 3 (sim.rs):** add `antimatter: Fixed,` to `Player` (after `era`, doc `/// Accumulated antimatter (third resource).`); init `antimatter: Fixed::ZERO` in `Sim::new`. Add a const near the top: `/// Antimatter cost to train a Capital Ship. const CAPITAL_ANTIMATTER_COST: Fixed = Fixed::from_int(100);`. Add accessor `pub fn antimatter(&self, player: PlayerId) -> Fixed { self.players[usize::from(player.0)].antimatter }`.

- [ ] **Step 4 (sim.rs): economy.** In `run_economy`, alongside the `income` accumulation, add an `am_income: [Fixed; PLAYER_COUNT]` accumulator: in the building loop add `am_income[p] = am_income[p] + st.antimatter_income;`. In the powered loop, after updating credits, add `self.players[p].antimatter = self.players[p].antimatter + am_income[p] * factor;` (antimatter is subject to the same power `factor` as credits).

- [ ] **Step 5 (sim.rs): Capital antimatter cost.** In `apply_command`'s `Command::Train` arm, the Capital era gate exists (`if matches!(kind, UnitKind::Capital) && era < 3 { return; }`). Change the affordability so Capital also needs antimatter:
```rust
                let cost = self.balance.unit(kind).cost;
                let am_cost = if matches!(kind, UnitKind::Capital) { CAPITAL_ANTIMATTER_COST } else { Fixed::ZERO };
                // ... existing `ok` barracks check ...
                if ok && self.players[p].credits >= cost && self.players[p].antimatter >= am_cost {
                    self.players[p].credits = self.players[p].credits - cost;
                    self.players[p].antimatter = self.players[p].antimatter - am_cost;
                    if let Some(e) = self.entities.get_mut(barracks.0 as usize) { e.build_queue.push(kind); }
                }
```
(Preserve the existing `ok` check and structure; only add the `am_cost` computation, the `antimatter >= am_cost` condition, and the antimatter deduction.)

- [ ] **Step 6 (sim.rs): hash.** In `state_hash`'s per-player loop, after `h.write_u64(u64::from(p.era));`, add `h.write_i64(p.antimatter.to_bits());`.

- [ ] **Step 7: verify + RE-PIN.** `cargo test -p rts-core antimatter_accrues` → PASS. `golden_hash_pins_cross_target_determinism` → **FAILS** (antimatter now hashed); re-pin to the actual new value (run twice for stability). `cargo test --workspace`; clippy; fmt. Commit (sim.rs): `feat(core): per-player antimatter — economy + Capital cost + hash (re-pin golden)`.

---

## Task 3: UI — third resource readout + Antimatter Plant button (shell-only)

**Files:** `crates/render-shell/src/{ui,input}.rs`.

- [ ] **Step 1: antimatter readout.** In `ui.rs`'s top resource-bar draw fn (shows credits/power/units + era), add an "Antimatter" readout calling `sim.antimatter(HUMAN)` (format like credits; place at discretion following the bar layout). If the bar gets crowded, abbreviate (e.g. "AM").
- [ ] **Step 2: build button.** In `ui.rs` `layout()`, add `mk(9, "Antimatter", 'N', Action::Build(BuildingKind::AntimatterPlant))` (`[Button; 9]` → `[Button; 10]`; keep the build group before the unit group — adjust the group-gap index so units still start after all buildings). In `input.rs` add `KeyCode::N` → `build_mode = Some(BuildingKind::AntimatterPlant)` mirroring the other build hotkeys.
- [ ] **Step 3: build + lint.** `cargo build -p rts-render-shell`; `cargo clippy --workspace --all-targets -- -D warnings`; fmt; `golden_hash_pins_cross_target_determinism` PASS (no core change). Commit: `feat(shell): antimatter resource readout + Antimatter Plant build button`.

---

## Task 4: AI builds Antimatter Plants + fields Capitals (hash-preserving)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.** Over a long match (≈8000 ticks, seed 7), assert the AI eventually builds an Antimatter Plant (`s.has_building(P0, BuildingKind::AntimatterPlant)` becomes true at some point).
- [ ] **Step 2: run → FAIL.**
- [ ] **Step 3 (sim.rs):** in `ai_commands`, after the essential build-order loop (and its `building_this_tick` guard), add a conditional build: if `!building_this_tick && self.player_era(player) >= 1 && !self.has_building(player, BuildingKind::AntimatterPlant) && credits >= self.building_cost(BuildingKind::AntimatterPlant)`, build an Antimatter Plant near the base (use the same `find_buildable_near(cc_tile, enemy_cc)` the other builds use) and set `building_this_tick = true`. Era≥1 gating keeps the 120-tick golden run (AI stays Era 0) unaffected. Also: in the AI Capital-training choice (Phase 3), add the antimatter affordability check — only choose `UnitKind::Capital` when `self.antimatter(player) >= CAPITAL_ANTIMATTER_COST` (so it doesn't issue rejected Capital trains).
- [ ] **Step 4: verify.** New test PASS. `golden_hash_pins_cross_target_determinism` → **PASS, UNCHANGED** (AI is Era 0 for the whole 120-tick golden run, so it never builds a plant or trains a Capital there; confirm — if it unexpectedly changes, investigate before re-pinning). `cargo test --workspace`; clippy; fmt; `cargo run --release -p rts-server -- playtest` (report). Commit (sim.rs): `feat(core): AI builds Antimatter Plants (Era 1+) and funds Capital Ships`.

---

## Task 5: Verify + finish

- [ ] `cargo test --workspace`; `golden_hash_pins_cross_target_determinism`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`; `cargo run --release -p rts-server -- playtest`.
- [ ] Final holistic review; fast-forward merge into `feat/core-foundation`.

## Definition of done
- Antimatter Plant produces antimatter while powered; per-player antimatter (hashed) accrues in the economy; Capital Ships require credits + antimatter; HUD shows antimatter + has a plant build button; AI builds plants (Era 1+) and funds Capitals; AI-vs-AI deterministic (golden re-pinned once); full workspace test/clippy/fmt/wasm green.

## Notes / deferred
- Antimatter numbers (plant income/cost, `CAPITAL_ANTIMATTER_COST`) are first-pass; tune via playtest. Contested antimatter map *nodes* (vs passive production) remain a deferred option per the spec.
- Antimatter Plant reuses the refinery sprite placeholder.
