# Phase 4 — Energy Shields — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** A researched, regenerating shield layer on top of HP. Shields absorb damage before it reaches HP, regen out of combat, and are **pierced by AntiArmor damage** (a new RPS counter). Max shield comes from a new **Shields research branch**.

**Architecture:** Per-entity `shield: Fixed` + `last_combat_tick: u32` (both hashed). A player's shield *max* = sum of their researched **Shields**-branch tech bonuses (reuses the Phase-2 `branch_bonus` helper). Units/buildings spawn with full shield (= owner's current max). A new `run_shields()` tick phase (between `run_movement` and `run_combat`) regens shield toward max when `tick - last_combat_tick >= REGEN_DELAY`. In `run_combat`, post-armor damage hits the shield first (non-piercing) then overflows to HP; AntiArmor hits pierce straight to HP; either way the target's `last_combat_tick` is stamped. `EntityView` exposes `shield`/`max_shield` for a cyan shield bar. Golden hash re-pinned once (new fields hashed + `last_combat_tick` stamped on hits; shield is 0 in the golden run so HP outcomes are unchanged).

**Tech Stack:** `rts-core` (no_std, fixed-point, `deny(clippy::float_arithmetic)`, golden-hash determinism), `rts-render-shell`.

**Spec:** [`../specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 4. (Phases 0–3 merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase4-shields` (from `feat/core-foundation`). Tree clean.
- Stage only each task's files; never `git add -A`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism:** new state is fixed-point/integer and hashed. The golden hash (currently `9_987_500_447_761_259_648`) is re-pinned in **T2** only (new fields + last_combat_tick). Re-pin = run the test, read the actual new hash, paste it in, re-run. NEVER re-pin elsewhere.
- **Locked balance (first-pass, tunable):** Shield I/II/III bonus = 30/40/50 (cumulative max 120); `REGEN_DELAY = 90` ticks (3s out of combat); `REGEN_PER_TICK = Fixed::ONE`; AntiArmor pierces shields.

---

## Task 1: Shields research branch (tech.rs)

**Files:** `crates/core/src/game/tech.rs`.

- [ ] **Step 1: failing test.** Add a test: `is_shield_branch` of ids 13/14/15 is `TechBranch::Shields`, they chain by prereq (14→13, 15→14), and `TECH_COUNT == 16`. (Use `tech(13).unwrap().branch == TechBranch::Shields`, etc.)
- [ ] **Step 2: run → FAIL** (no Shields variant / TECH_COUNT is 13).
- [ ] **Step 3: implement.** Add `Shields` to `TechBranch` (`/// Adds to the player's max energy shield. Shields,`). Bump `TECH_COUNT` 13→16. Append to `TECHS`:
```rust
    TechDef { id: 13, name: "Shield I", branch: TechBranch::Shields, cost: Fixed::from_int(300), duration: 450, prereq: None, bonus: Fixed::from_int(30) },
    TechDef { id: 14, name: "Shield II", branch: TechBranch::Shields, cost: Fixed::from_int(450), duration: 600, prereq: Some(13), bonus: Fixed::from_int(40) },
    TechDef { id: 15, name: "Shield III", branch: TechBranch::Shields, cost: Fixed::from_int(600), duration: 750, prereq: Some(14), bonus: Fixed::from_int(50) },
```
The existing `const _: () = assert!(TECHS[TECH_COUNT - 1].id as usize == TECH_COUNT - 1);` stays valid (last id 15 == 16-1). `TechBranch` is matched only via `==` (no exhaustive `match TechBranch` to break) — verify with `cargo build --workspace`.
- [ ] **Step 4: verify + commit.** `cargo test -p rts-core` (incl the new test + golden hash UNCHANGED — nothing researches shields yet); `cargo clippy --workspace --all-targets -- -D warnings`; fmt. Commit (tech.rs): `feat(core): add Shields research branch (Shield I/II/III; hash-preserving)`.

---

## Task 2: Shield mechanic — state, regen, combat absorption, EntityView (re-pin)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.**
```rust
    #[test]
    fn shields_absorb_then_regen_and_antiarmor_pierces() {
        use crate::game::stats::Fixed; // if needed; else crate::fixed::Fixed
        let mut s = Sim::new(Map::new(20, 20), 1, f(20_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        // Research Shield I (id 13) to completion.
        s.step(&[Command::Research { owner: P0, tech_id: 13 }]);
        let dur = crate::game::tech::tech(13).unwrap().duration;
        for _ in 0..dur { s.step(&[]); }
        assert!(s.player_shield_max(P0) > crate::fixed::Fixed::ZERO);
        // A newly spawned P0 unit has shield == max.
        let id = s.add_unit(P0, UnitKind::Infantry, crate::vec::Vec2::new(crate::fixed::Fixed::from_int(6), crate::fixed::Fixed::from_int(6)));
        let v = s.views().into_iter().find(|v| v.id == id).unwrap();
        assert_eq!(v.shield, v.max_shield);
        assert!(v.max_shield > crate::fixed::Fixed::ZERO);
    }
```
(Adapt `Vec2`/`Fixed` import paths to the file's conventions; the point: after researching Shield I, `player_shield_max(P0) > 0` and a new P0 unit spawns with `shield == max_shield > 0`.)

- [ ] **Step 2: run → compile failure** (`player_shield_max`, `EntityView.shield` missing).

- [ ] **Step 3: Entity fields.** Add to `Entity` (after `hp`): `/// Current energy shield (absorbs damage before HP). shield: Fixed,` and `/// Tick the entity was last hit (drives out-of-combat shield regen). last_combat_tick: u32,`.

- [ ] **Step 4: `player_shield_max` helper.** After `player_mobility_bonus`:
```rust
    fn player_shield_max(&self, p: PlayerId) -> Fixed {
        self.branch_bonus(p, crate::game::tech::TechBranch::Shields)
    }
```
Also add a public accessor `pub fn shield_max(&self, player: PlayerId) -> Fixed { self.player_shield_max(player) }` if the UI/tests need it (the test uses `player_shield_max` from the in-file test module — private is fine; if the test is outside the module, add the pub accessor and use it).

- [ ] **Step 5: spawn init.** In `add_building` and `add_unit`, before `self.alloc_slot(Entity { ... })`, compute `let shield = self.player_shield_max(owner);` and add `shield,` and `last_combat_tick: 0,` to the `Entity { ... }` literal.

- [ ] **Step 6: `run_shields` phase + step order.** Add:
```rust
    /// Regenerates each entity's shield toward its owner's current max while out
    /// of combat (no hit for `REGEN_DELAY` ticks). Also clamps to the current max.
    fn run_shields(&mut self) {
        const REGEN_DELAY: u32 = 90;
        let regen = Fixed::ONE;
        let tick = self.tick;
        let max: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_shield_max(PlayerId(u8::try_from(p).unwrap())));
        for e in &mut self.entities {
            if !e.alive {
                continue;
            }
            let m = max[usize::from(e.owner.0)];
            if e.shield > m {
                e.shield = m;
            }
            if tick.saturating_sub(e.last_combat_tick) >= REGEN_DELAY && e.shield < m {
                let r = e.shield + regen;
                e.shield = if r > m { m } else { r };
            }
        }
    }
```
In `step`, insert `self.run_shields();` between `self.run_movement();` and `self.run_combat();`.

- [ ] **Step 7: combat absorption + piercing + last_combat_tick.** In `run_combat`: change the `damage` vec to carry a `pierces` bool. Where damage is pushed (currently `damage.push((j, base + weapon[...]));` after computing `base`), also compute `pierces` from the attack profile's damage type and push it:
```rust
                let pierces = matches!(profile.damage_type, DamageType::AntiArmor);
                damage.push((j, base + weapon[usize::from(e.owner.0)], pierces));
```
(So `damage: Vec<(usize, Fixed, bool)>` — update its declaration.) In the apply loop, after computing the post-armor `net` (the existing armor-mitigation-with-`Fixed::ONE`-floor logic), route through the shield:
```rust
        for (j, dmg, pierces) in damage {
            let owner = self.entities[j].owner;
            let mit = armor[usize::from(owner.0)];
            let net = if mit > Fixed::ZERO {
                let r = dmg - mit;
                if r < Fixed::ONE { Fixed::ONE } else { r }
            } else {
                dmg
            };
            let e = &mut self.entities[j];
            e.last_combat_tick = self.tick; // wait: borrow — read self.tick before borrowing e
            if pierces {
                e.hp = e.hp - net;
            } else {
                let absorbed = if e.shield < net { e.shield } else { net };
                e.shield = e.shield - absorbed;
                e.hp = e.hp - (net - absorbed);
            }
        }
```
> **Borrow fix:** read `let tick = self.tick;` once before the loop, then use `e.last_combat_tick = tick;` (you cannot read `self.tick` while `e = &mut self.entities[j]` is borrowed). Keep the existing armor-mitigation math exactly; only the shield/pierce/last_combat_tick handling is new. `DamageType` must be in scope (import if needed).

- [ ] **Step 8: EntityView.** Add `pub shield: Fixed,` and `pub max_shield: Fixed,` to `EntityView`. In `views()`, add `shield: e.shield,` and `max_shield: self.player_shield_max(e.owner),`.

- [ ] **Step 9: hash.** In `state_hash`'s per-entity block, after `h.write_i64(e.hp.to_bits());`, add `h.write_i64(e.shield.to_bits());` and `h.write_u64(u64::from(e.last_combat_tick));`.

- [ ] **Step 10: verify + RE-PIN.** `cargo test -p rts-core shields_absorb_then_regen` → PASS. `golden_hash_pins_cross_target_determinism` → **FAILS** (new hashed fields + last_combat_tick stamped on hits); re-pin to the actual new value, re-run (run twice to confirm stable). `cargo test --workspace`; clippy; fmt. Commit (sim.rs): `feat(core): energy shields — state, regen, combat absorption, AntiArmor piercing (re-pin golden)`.

---

## Task 3: Cyan shield bars (UI, shell-only)

**Files:** `crates/render-shell/src/{main,theme}.rs`.

- [ ] **Step 1: shield color.** In `theme.rs`, add a cyan constant if none exists: `/// Energy-shield bar tint. pub const SHIELD: Color = color_u8!(90, 200, 235, 255);`.
- [ ] **Step 2: draw the bar.** Find where the HP bar is drawn per entity in `main.rs` (uses `EntityView.hp`/`max_hp`). Draw a thin shield bar of width `shield/max_shield` directly ABOVE the HP bar, in `SHIELD` color, **only when `v.max_shield > Fixed::ZERO`**. Match the HP bar's width/position math; keep it 2–3px tall. (Convert `Fixed` to a fraction the same way the HP bar does — follow the existing `hp/max_hp` ratio code.)
- [ ] **Step 3: build + lint.** `cargo build -p rts-render-shell`; `cargo clippy --workspace --all-targets -- -D warnings`; fmt; `cargo test -p rts-core golden_hash_pins_cross_target_determinism` (PASS — no core change). Commit: `feat(shell): cyan energy-shield bars above health bars`.

> The new Shield techs already appear in the research modal automatically (it iterates `TECHS`) — no modal change needed.

---

## Task 4: AI researches shields

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.** Over a long match (e.g. 8000 ticks, seed 7), assert the AI eventually has `player_shield_max(P0) > 0` (it researched a Shield tech).
- [ ] **Step 2: run → FAIL.**
- [ ] **Step 3: implement.** Extend the AI `RESEARCH_PRIORITY` (currently `[u32; 13] = [6, 0, 3, 10, 7, 1, 4, 11, 8, 2, 5, 12, 9]`) to `[u32; 16]`, inserting the Shield techs (13/14/15) at sensible spots (e.g. after Armor I and the early upgrades): `[6, 0, 3, 13, 10, 7, 1, 4, 14, 11, 8, 2, 5, 15, 12, 9]`. The existing eligibility loop handles prereq/affordability/anti-stall.
- [ ] **Step 4: verify.** New test PASS. `golden_hash_pins_cross_target_determinism` → **PASS, UNCHANGED** (the AI's first researched tech is still Economy I (id 6, priority[0]); within the 120-tick golden run nothing shield-related completes, so the run is bit-identical — confirm by running it; if it unexpectedly changes, investigate before re-pinning). `cargo test --workspace`; clippy; fmt. Commit (sim.rs): `feat(core): AI researches energy-shield techs`.

---

## Task 5: Verify + finish

- [ ] `cargo test --workspace`; `golden_hash_pins_cross_target_determinism`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`; `cargo run --release -p rts-server -- playtest` (report).
- [ ] Final holistic review; fast-forward merge into `feat/core-foundation`.

## Definition of done
- Researched shields (Shield I/II/III) give a per-player shield max; entities spawn shielded, regen out of combat, and absorb damage before HP; AntiArmor pierces shields; cyan shield bars render; AI researches shields; AI-vs-AI deterministic (golden re-pinned once); full workspace test/clippy/fmt/wasm green.

## Notes / deferred
- Shield numbers, `REGEN_DELAY`/`REGEN_PER_TICK`, and AntiArmor-as-the-piercer are first-pass; tune via playtest.
- Shields use the owner's CURRENT max (retroactive: researching more Shield tiers raises the cap and units regen up to it).
