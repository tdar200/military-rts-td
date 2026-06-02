# Phase 6 — Anti-Grav / Flight Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** A researched **Anti-Grav Drives** upgrade that lets a player's units ignore terrain for movement (fly straight to their target), while remaining normal **ground targets**. The final phase of the 7-phase program.

**Architecture:** Anti-grav is a single research tech (`TechBranch::AntiGrav`). A unit moves terrain-ignoring iff it is `is_air` OR its owner has researched an anti-grav tech — checked in `order_unit_to`, which already routes `is_air` units to straight-line movement (reused verbatim, so determinism + the existing run_movement path are untouched). **No new hashed state** (anti-grav derives from the already-hashed `researched_techs`), **no map-passability change**, and the AI won't research it inside the 120-tick golden run — so **the golden hash does NOT change (no re-pin)**.

**Tech Stack:** `rts-core` (no_std, fixed-point, golden-hash determinism).

**Spec:** [`../specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 6. (Phases 0–5 merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase6-antigrav` (from `feat/core-foundation`). Tree clean.
- Stage only each task's files; never `git add -A`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism:** the golden hash (currently `13_355_596_211_711_344_768`) must stay **UNCHANGED** in every task (no new hashed state; the routing change only triggers when the anti-grav tech is researched, which never happens in the golden run). If any task changes the hash, STOP and report blocked — do NOT re-pin.
- **Locked (first-pass, tunable):** one Anti-Grav Drives tech, `TechBranch::AntiGrav`, cost 500, duration 600, `prereq: None`, bonus ZERO.

---

## Task 1: Anti-Grav Drives tech + terrain-ignoring movement

**Files:** `crates/core/src/game/tech.rs`, `crates/core/src/game/sim.rs`.

- [ ] **Step 1 (tech.rs): failing test.** In the tech tests, update the existing `assert_eq!(TECH_COUNT, 16)` to `17`, and add: there is exactly one `TechBranch::AntiGrav` tech (id 16, "Anti-Grav Drives"), its prereq is `None`, and `tech(16).unwrap().branch == TechBranch::AntiGrav`.

- [ ] **Step 2: run → FAIL** (no AntiGrav variant / TECH_COUNT is 16).

- [ ] **Step 3 (tech.rs): implement.** Add `AntiGrav` to `TechBranch` (`/// Lets the player's units ignore terrain for movement. AntiGrav,`). Bump `TECH_COUNT` 16→17. Append to `TECHS`:
```rust
    TechDef { id: 16, name: "Anti-Grav Drives", branch: TechBranch::AntiGrav, cost: Fixed::from_int(500), duration: 600, prereq: None, bonus: Fixed::ZERO },
```
The density assert `const _: () = assert!(TECHS[TECH_COUNT - 1].id as usize == TECH_COUNT - 1);` stays valid (last id 16 == 17-1). `TechBranch` is matched only via `==`/`matches!` (no exhaustive `match TechBranch` to break) — verify with `cargo build --workspace`.

- [ ] **Step 4 (sim.rs): failing test.** The anti-grav tech has `prereq: None`, so it researches directly:
```rust
    #[test]
    fn antigrav_research_makes_owner_units_ignore_terrain() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(50_000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 2);
        s.add_building(P0, BuildingKind::ResearchLab, 4, 2);
        let agid = (0..crate::game::tech::TECH_COUNT)
            .find(|&i| matches!(crate::game::tech::TECHS[i].branch, crate::game::tech::TechBranch::AntiGrav))
            .map(|i| u32::try_from(i).unwrap()).unwrap();
        assert!(!s.has_antigrav(P0));
        s.step(&[Command::Research { owner: P0, tech_id: agid }]);
        for _ in 0..crate::game::tech::tech(agid).unwrap().duration { s.step(&[]); }
        assert!(s.has_antigrav(P0), "anti-grav researched");
        assert!(!s.has_antigrav(P1), "opponent unaffected");
    }
```
**So revise Step 3 to use `prereq: None`** for the Anti-Grav Drives tech (and update Step 1's test to assert `prereq` is `None`).

- [ ] **Step 5 (sim.rs): helper + accessor.** After `player_shield_max`:
```rust
    fn player_has_antigrav(&self, p: PlayerId) -> bool {
        let mask = self.players[usize::from(p.0)].researched_techs;
        (0..crate::game::tech::TECH_COUNT).any(|i| {
            mask & (1u32 << i) != 0
                && matches!(crate::game::tech::TECHS[i].branch, crate::game::tech::TechBranch::AntiGrav)
        })
    }
```
And a public accessor: `pub fn has_antigrav(&self, p: PlayerId) -> bool { self.player_has_antigrav(p) }`.

- [ ] **Step 6 (sim.rs): route anti-grav units straight-line.** In `order_unit_to`, change the opening guard:
```rust
    fn order_unit_to(&mut self, idx: usize, target: Vec2) {
        if is_air_of(&self.balance, self.entities[idx].kind) {
```
to:
```rust
    fn order_unit_to(&mut self, idx: usize, target: Vec2) {
        let owner = self.entities[idx].owner;
        if is_air_of(&self.balance, self.entities[idx].kind) || self.player_has_antigrav(owner) {
```
(Read `owner` and call the helpers before the `let e = &mut self.entities[idx];` borrow inside the branch. The rest of the straight-line branch and the A* fallback are unchanged.)

- [ ] **Step 7: verify.** `cargo test -p rts-core antigrav_research_makes_owner` and the tech test → PASS. `golden_hash_pins_cross_target_determinism` → **PASS, UNCHANGED `13_355_596_211_711_344_768`** (no new hashed state; no player has anti-grav in the golden run). `cargo test --workspace`; clippy; fmt. Commit (tech.rs, sim.rs): `feat(core): Anti-Grav Drives tech — researched units ignore terrain (hash-preserving)`.

---

## Task 2: AI researches anti-grav

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.** Over a long match (≈9000 ticks, seed 7), assert the AI eventually has `s.has_antigrav(P0)` true.
- [ ] **Step 2: run → FAIL** (anti-grav not in the AI priority).
- [ ] **Step 3: implement.** Extend the AI `RESEARCH_PRIORITY` (currently `[u32; 16]`) to `[u32; 17]`, appending the anti-grav tech id (16) near the end (it's a late, optional upgrade). The existing eligibility loop handles prereq (none now)/affordability/anti-stall.
- [ ] **Step 4: verify.** New test PASS. `golden_hash_pins_cross_target_determinism` → **PASS, UNCHANGED** (the AI's first researched tech is still Economy I; anti-grav is last in priority and never reached within the 120-tick golden run; confirm). `cargo test --workspace`; clippy; fmt. Commit (sim.rs): `feat(core): AI researches Anti-Grav Drives`.

---

## Task 3: Verify + finish

- [ ] `cargo test --workspace`; `golden_hash_pins_cross_target_determinism` (PASS, unchanged); `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`; `cargo run --release -p rts-server -- playtest` (report).
- [ ] Final holistic review; fast-forward merge into `feat/core-foundation`.

## Definition of done
- A researched Anti-Grav Drives upgrade makes the owner's units ignore terrain for movement (reusing the `is_air` straight-line path) while keeping them ground-targetable; the tech appears in the research modal automatically; the AI researches it; the golden hash is UNCHANGED throughout (no new hashed state); full workspace test/clippy/fmt/wasm green.

## Notes / deferred
- Anti-grav is all-or-nothing per player (research → all your units ignore terrain). A per-unit `is_antigrav` flag (only *some* units fly) is a possible refinement; the current research-gated approach is simpler and determinism-safe.
- Cost/duration are first-pass; tune via playtest.
- The research modal already lists all techs, so Anti-Grav Drives shows up with no UI change. A "flight" visual cue for anti-grav units is deferred polish.
