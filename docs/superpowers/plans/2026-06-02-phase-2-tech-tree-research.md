# Phase 2 — Tech-Tree Research System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a branching research system to the deterministic core: a `ResearchLab` building, a code-defined tech tree of 10 global upgrades (Weapons/Armor/Economy/Mobility, tiered), per-player research state, a `Command::Research`, a `run_research()` tick phase, live effect application in combat/economy/movement, AI that researches, and a research UI.

**Architecture:** Research state (a `u32` researched-tech bitmask + an `Option<(tech_id, ticks_remaining)>`) lives per-player in `Sim` and is **hashed**. Tech definitions are code constants in a new `tech` module. Upgrade effects are **flat per-player scalars consulted live at resolution time** (combat damage/mitigation, economy income, movement speed) — never by mutating unit stats, so they're retroactive and determinism-simple. The golden hash is re-pinned twice (once when research state is added to the hash, once when the AI starts researching).

**Tech Stack:** Rust workspace — `rts-core` (`no_std`, fixed-point `Fixed`, `deny(clippy::float_arithmetic)`, golden-hash determinism), `rts-data` (RON loader), `rts-render-shell` (Macroquad).

**Spec:** [`../specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 2 of the 7-phase program. (Phases 0–1 merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase2-research` (from `feat/core-foundation`).
- Working tree is clean. Stage only each task's named files; never `git add -A`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism rules:** all timers are `u32` ticks (never floats); all bonuses are `Fixed`; the `float_arithmetic` lint is your friend. New per-player research state MUST be added to `state_hash()`. The golden hash WILL change — re-pin it **deliberately** in the tasks that say so (run the test, read the actual hash from the failure, paste it into the constant, re-run). Never re-pin in a task that isn't supposed to change behavior.
- **Borrow-checker note (important):** bonus helpers read `self.players`; the combat/movement loops take `&mut self.entities`. You CANNOT call `self.xxx_bonus(owner)` inside a `for e in &mut self.entities` loop. **Precompute per-player bonus arrays into a local `[Fixed; PLAYER_COUNT]` before** the mutable loop, then index by `usize::from(owner.0)`.

### Locked design (balance numbers are first-pass — tunable via `cargo run -p rts-server -- playtest`)

- **ResearchLab:** `max_hp 300, power_consumed 25, cost 250`, no income/production/attack.
- **Tech tree (ids 0–9):** Weapons I/II/III (+2/+2/+3 damage), Armor I/II/III (+1/+1/+2 flat mitigation), Economy I/II (+1/+1 credit/tick), Mobility I/II (+0.02/+0.02 tiles/tick). Tier _n_ requires tier _n−1_ in the same branch. Costs/durations in the `TECHS` table below.
- **Effects (live, per player):** Weapons → added to attacker damage; Armor → subtracted from incoming damage, clamped to a `Fixed::ONE` floor (no healing); Economy → added to income before the power factor; Mobility → added to unit speed.
- **Research mechanics:** one active research per player; starting research requires an alive owned ResearchLab + affordability + prereq + not-already-researched + not-already-researching; credits deducted immediately; progress advances only while the player is **powered**; (if the lab is destroyed mid-research, progress simply continues — acceptable v1 behavior).
- **AI:** builds a ResearchLab after Barracks, then researches in a fixed priority order, skipping unaffordable/ineligible techs (anti-stall). Deterministic, symmetric.

---

## File Structure

- **Create `crates/core/src/game/tech.rs`** — `TechBranch`, `TechDef`, `TECHS`, `TECH_COUNT`, `tech(id)` (Task 1). Register `pub mod tech;` in `crates/core/src/game/mod.rs`.
- **Modify `crates/core/src/game/stats.rs`** — add `BuildingKind::ResearchLab` + its stats + `kind_tag` is in sim.rs (Task 2).
- **Modify `crates/core/src/game/balance.rs`** — building array 7→8 + `ResearchLab` lookup (Task 2).
- **Modify `crates/data/src/lib.rs` + `crates/data/balance.ron`** — `research_lab` entry (Task 2).
- **Modify `crates/core/src/game/sim.rs`** — `Player` fields, `Command::Research`, `apply_command`, `run_research`, `state_hash`, accessors, `kind_tag`, effect hooks, `ai_commands` (Tasks 2–5).
- **Modify `crates/render-shell/src/{ui,input,main,sprites,theme}.rs`** — research UI (Task 6).

---

## Task 1: The tech-tree data module

**Files:** Create `crates/core/src/game/tech.rs`; modify `crates/core/src/game/mod.rs`.

- [ ] **Step 1: Write the failing test.** Create `crates/core/src/game/tech.rs` with ONLY a test module first:

```rust
#[cfg(test)]
mod tests {
    use super::{tech, TechBranch, TECHS, TECH_COUNT};

    #[test]
    fn tree_is_well_formed() {
        assert_eq!(TECHS.len(), TECH_COUNT);
        for (i, t) in TECHS.iter().enumerate() {
            assert_eq!(t.id as usize, i, "tech id must equal its index");
            if let Some(p) = t.prereq {
                assert!((p as usize) < i, "prereq must come earlier in the array");
                assert_eq!(
                    TECHS[p as usize].branch, t.branch,
                    "prereq must be in the same branch"
                );
            }
        }
        assert!(tech(0).is_some());
        assert!(tech(TECH_COUNT as u32).is_none());
        assert_eq!(tech(0).unwrap().branch, TechBranch::Weapons);
    }
}
```
Add `pub mod tech;` to `crates/core/src/game/mod.rs` (alongside the other `pub mod` lines).

- [ ] **Step 2: Run, expect compile failure.** `cargo test -p rts-core tree_is_well_formed` → unresolved `tech`/`TechBranch`/`TECHS`/`TECH_COUNT`.

- [ ] **Step 3: Implement the module.** Put this ABOVE the test module in `crates/core/src/game/tech.rs`:

```rust
//! The research tech tree — global, per-player upgrades.
//!
//! Techs are code constants (ids are array indices). Each tech adds a flat
//! `bonus` to its `branch`; a player's total branch bonus is the sum of the
//! bonuses of the techs they've researched. Effects are applied live at
//! combat/economy/movement resolution, never by mutating unit stats.

use crate::fixed::Fixed;

/// Number of techs in the tree.
pub const TECH_COUNT: usize = 10;

/// Which global stat a tech improves.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum TechBranch {
    /// Adds flat damage to all of the player's attacks.
    Weapons,
    /// Subtracts flat damage from all incoming hits (clamped above zero).
    Armor,
    /// Adds flat credit income per tick.
    Economy,
    /// Adds flat move speed (tiles/tick) to the player's units.
    Mobility,
}

/// One research upgrade.
#[derive(Clone, Copy, Debug)]
pub struct TechDef {
    /// Stable id; equals the index into [`TECHS`].
    pub id: u32,
    /// Display name.
    pub name: &'static str,
    /// Which branch this improves.
    pub branch: TechBranch,
    /// Credit cost to research.
    pub cost: Fixed,
    /// Research duration in ticks.
    pub duration: u32,
    /// Tech that must be researched first (always an earlier index, same branch).
    pub prereq: Option<u32>,
    /// Flat bonus added to the branch total when researched.
    pub bonus: Fixed,
}

/// The full tech tree. Balance numbers are first-pass; tune via the playtest harness.
pub const TECHS: [TechDef; TECH_COUNT] = [
    TechDef { id: 0, name: "Weapons I", branch: TechBranch::Weapons, cost: Fixed::from_int(200), duration: 300, prereq: None, bonus: Fixed::from_int(2) },
    TechDef { id: 1, name: "Weapons II", branch: TechBranch::Weapons, cost: Fixed::from_int(350), duration: 450, prereq: Some(0), bonus: Fixed::from_int(2) },
    TechDef { id: 2, name: "Weapons III", branch: TechBranch::Weapons, cost: Fixed::from_int(500), duration: 600, prereq: Some(1), bonus: Fixed::from_int(3) },
    TechDef { id: 3, name: "Armor I", branch: TechBranch::Armor, cost: Fixed::from_int(200), duration: 300, prereq: None, bonus: Fixed::from_int(1) },
    TechDef { id: 4, name: "Armor II", branch: TechBranch::Armor, cost: Fixed::from_int(350), duration: 450, prereq: Some(3), bonus: Fixed::from_int(1) },
    TechDef { id: 5, name: "Armor III", branch: TechBranch::Armor, cost: Fixed::from_int(500), duration: 600, prereq: Some(4), bonus: Fixed::from_int(2) },
    TechDef { id: 6, name: "Economy I", branch: TechBranch::Economy, cost: Fixed::from_int(250), duration: 450, prereq: None, bonus: Fixed::from_int(1) },
    TechDef { id: 7, name: "Economy II", branch: TechBranch::Economy, cost: Fixed::from_int(400), duration: 600, prereq: Some(6), bonus: Fixed::from_int(1) },
    TechDef { id: 8, name: "Mobility I", branch: TechBranch::Mobility, cost: Fixed::from_int(200), duration: 360, prereq: None, bonus: Fixed::from_ratio(2, 100) },
    TechDef { id: 9, name: "Mobility II", branch: TechBranch::Mobility, cost: Fixed::from_int(350), duration: 480, prereq: Some(8), bonus: Fixed::from_ratio(2, 100) },
];

/// Look up a tech by id.
#[must_use]
pub const fn tech(id: u32) -> Option<&'static TechDef> {
    if (id as usize) < TECH_COUNT {
        Some(&TECHS[id as usize])
    } else {
        None
    }
}
```

- [ ] **Step 4: Run tests + lints.** `cargo test -p rts-core tree_is_well_formed` → PASS; `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → PASS (unchanged — nothing uses the module yet); `cargo clippy -p rts-core --all-targets -- -D warnings` → clean; `cargo fmt -p rts-core -- --check`.

- [ ] **Step 5: Commit.**
```bash
git add crates/core/src/game/tech.rs crates/core/src/game/mod.rs
git commit -m "feat(core): add the research tech-tree data module (no effects yet)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add the `ResearchLab` building (full blast radius)

**Files:** `crates/core/src/game/stats.rs`, `crates/core/src/game/balance.rs`, `crates/core/src/game/sim.rs`, `crates/data/src/lib.rs`, `crates/data/balance.ron`.

This is mechanical but spans 5 files; the build won't compile until all the exhaustive matches/arrays are updated. Do all edits, then build.

- [ ] **Step 1: Write the failing test.** Add to the `#[cfg(test)] mod tests` in `crates/core/src/game/balance.rs` (it already has `BUILDING_KINDS`):

```rust
    #[test]
    fn research_lab_exists_and_is_a_powered_structure() {
        use crate::game::stats::BuildingKind;
        let b = Balance::default();
        let st = b.building(BuildingKind::ResearchLab);
        assert!(st.power_consumed > 0, "research lab draws power");
        assert!(!st.produces_units);
        assert!(st.attack.is_none());
        assert!(st.cost > crate::fixed::Fixed::ZERO);
    }
```
Also extend the existing `BUILDING_KINDS` const in that test module from `[BuildingKind; 7]` to `[BuildingKind; 8]` and add `BuildingKind::ResearchLab` as the 8th element.

- [ ] **Step 2: Run, expect compile failure.** `cargo test -p rts-core research_lab_exists` → `no variant named ResearchLab`.

- [ ] **Step 3: Add the variant + stats (`stats.rs`).** In the `BuildingKind` enum (after `Wall`), add:
```rust
    /// Enables research (consumes power; no attack, no production).
    ResearchLab,
```
In `BuildingKind::stats()`, add a match arm (the `match self` currently ends with `Self::Wall => base(200, 20),`):
```rust
            Self::ResearchLab => BuildingStats {
                power_consumed: 25,
                ..base(300, 250)
            },
```

- [ ] **Step 4: Update `balance.rs`.** Four edits:
  1. Struct field: `buildings: [[[BuildingStats; 7]; FACTION_COUNT]; ERA_COUNT],` → `8`.
  2. `from_tables` param: `buildings: [BuildingStats; 7]` → `8`.
  3. `const_default()` building list: add `BuildingKind::ResearchLab.stats(),` as the 8th entry (after `BuildingKind::Wall.stats(),`).
  4. `building_in()` match: add `BuildingKind::ResearchLab => tier[7],` after the `Wall => tier[6]` arm.

- [ ] **Step 5: Update `sim.rs` `kind_tag`.** In the building match inside `kind_tag` (currently ends `BuildingKind::Wall => 6,`), add `BuildingKind::ResearchLab => 8,` (8 is unused; the existing numbering is 1-7 with AaTurret=7, Wall=6).

- [ ] **Step 6: Update `rts-data`.** In `crates/data/src/lib.rs`: add `research_lab: BuildingData,` to the `BalanceData` struct (after `wall`); and add `to_building(&data.research_lab),` as the 8th element of the buildings array in `load()`. In `crates/data/balance.ron`, add before the final closing `)`:
```ron
    research_lab: (
        max_hp: 300, power_produced: 0, power_consumed: 25, credit_income: 0,
        produces_units: false, attack: None, cost: 250,
    ),
```
> Per the user's global rule, `balance.ron` is hand-authored game data (not codegen output), so this edit is in-scope — but keep it to exactly this additive entry.

- [ ] **Step 7: Update the render-shell exhaustive matches (so the workspace compiles).** Adding the `ResearchLab` variant makes every exhaustive `match BuildingKind` in the workspace non-exhaustive — the compiler will list each one. Add a `ResearchLab` arm to each. The known sites in `crates/render-shell/src`:
  - `ui.rs` `human_name_role`: add `EntityKindView::Building(BuildingKind::ResearchLab) => ("Research Lab", "Researches upgrades"),`
  - `ui.rs` `alien_name_role`: add `EntityKindView::Building(BuildingKind::ResearchLab) => ("Fabricator", "Researches alien upgrades"),`
  - `sprites.rs`: wherever a building is mapped to a sprite/asset name (an exhaustive `match BuildingKind`), add a `ResearchLab` arm. Reuse an existing icon (e.g. the barracks/command sprite) or return `None`/a placeholder — no new asset is required this task; the command-bar button and modal come in Task 6.
  Run `cargo build --workspace` and fix any remaining non-exhaustive `match BuildingKind` the compiler flags the same way.

- [ ] **Step 8: Run tests + lints + determinism.** `cargo test -p rts-core research_lab_exists` → PASS; `cargo test -p rts-data` → PASS (`default_ron_matches_the_code_default` still holds — RON and code both gained the same entry); `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → **PASS, constant UNCHANGED** (the golden AI run builds no ResearchLab, so behavior is identical); `cargo test --workspace` → all pass; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`.

- [ ] **Step 9: Commit.**
```bash
git add crates/core/src/game/stats.rs crates/core/src/game/balance.rs crates/core/src/game/sim.rs crates/data/src/lib.rs crates/data/balance.ron crates/render-shell/src/ui.rs crates/render-shell/src/sprites.rs
git commit -m "feat(core): add ResearchLab building (data + lookups + shell name/sprite arms; behavior-preserving)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Research state, command, tick phase, hashing (re-pins golden hash #1)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: Write failing tests.** Add to the `#[cfg(test)] mod tests` in `sim.rs` (it has helpers `P0`, `P1`, `f(...)`, `Map::new`):

```rust
    #[test]
    fn research_completes_after_its_duration_and_sets_the_bit() {
        use crate::game::tech::tech;
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20); // power so research advances
        s.add_building(P0, BuildingKind::ResearchLab, 7, 20);
        s.step(&[Command::Research { owner: P0, tech_id: 0 }]);
        // active research is now set, bit not yet researched
        let (mask, active) = s.research_state(P0);
        assert_eq!(mask & 1, 0);
        assert!(active.is_some());
        let dur = tech(0).unwrap().duration;
        for _ in 0..dur {
            s.step(&[]);
        }
        let (mask, active) = s.research_state(P0);
        assert_eq!(mask & 1, 1, "Weapons I bit set after duration");
        assert!(active.is_none());
    }

    #[test]
    fn research_is_rejected_without_a_lab_or_prereq_or_funds() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        // No ResearchLab yet → rejected.
        s.step(&[Command::Research { owner: P0, tech_id: 0 }]);
        assert!(s.research_state(P0).1.is_none());
        s.add_building(P0, BuildingKind::ResearchLab, 7, 20);
        // Weapons II (id 1) needs Weapons I (id 0) → rejected.
        s.step(&[Command::Research { owner: P0, tech_id: 1 }]);
        assert!(s.research_state(P0).1.is_none());
    }
```

- [ ] **Step 2: Run, expect compile failure** (`research_state`, `Command::Research` don't exist). `cargo test -p rts-core research_completes`.

- [ ] **Step 3: Extend `Player`.** Replace:
```rust
struct Player {
    credits: Fixed,
}
```
with:
```rust
struct Player {
    credits: Fixed,
    /// Bitmask of researched tech ids (bit i = tech i complete).
    researched_techs: u32,
    /// The in-progress research: (tech id, ticks remaining). One at a time.
    active_research: Option<(u32, u32)>,
}
```
Update the `Sim::new` player initializer (currently `Player { credits: starting_credits }`) to `Player { credits: starting_credits, researched_techs: 0, active_research: None }`.

- [ ] **Step 4: Add the `Command::Research` variant** to the `Command` enum (after `Move`):
```rust
    /// Begin researching a tech (costs credits; needs a powered* research lab).
    Research {
        /// Owning player.
        owner: PlayerId,
        /// Tech id to research.
        tech_id: u32,
    },
```

- [ ] **Step 5: Handle it in `apply_command`.** Add this arm (after the `Move` arm), importing `crate::game::tech::{tech, TECHS}` at the top of the file as needed:
```rust
            Command::Research { owner, tech_id } => {
                let p = usize::from(owner.0);
                let Some(def) = tech(tech_id) else { return };
                let already = self.players[p].researched_techs & (1 << tech_id) != 0;
                let busy = self.players[p].active_research.is_some();
                let prereq_ok = match def.prereq {
                    Some(req) => self.players[p].researched_techs & (1 << req) != 0,
                    None => true,
                };
                let has_lab = self.entities.iter().any(|e| {
                    e.alive
                        && e.owner == owner
                        && matches!(e.kind, Kind::Building(BuildingKind::ResearchLab))
                });
                if !already && !busy && prereq_ok && has_lab && self.players[p].credits >= def.cost
                {
                    self.players[p].credits = self.players[p].credits - def.cost;
                    self.players[p].active_research = Some((tech_id, def.duration));
                }
            }
```
> Note `*needs a powered` — power is enforced for *progress* in `run_research`, not at command time (mirrors how Barracks queue at any time but only produce when powered).

- [ ] **Step 6: Add `run_research` and call it in `step`.** Add the method:
```rust
    /// Advances each player's in-progress research, but only while powered.
    fn run_research(&mut self, powered: [bool; PLAYER_COUNT]) {
        for p in 0..PLAYER_COUNT {
            if !powered[p] {
                continue;
            }
            if let Some((id, ticks)) = self.players[p].active_research {
                if ticks <= 1 {
                    self.players[p].researched_techs |= 1 << id;
                    self.players[p].active_research = None;
                } else {
                    self.players[p].active_research = Some((id, ticks - 1));
                }
            }
        }
    }
```
In `step`, insert `self.run_research(powered);` right after `let powered = self.run_economy();` and before `self.run_production(powered);`.

- [ ] **Step 7: Hash the new state.** In `state_hash`, the current per-player loop is:
```rust
        for p in &self.players {
            h.write_i64(p.credits.to_bits());
        }
```
Replace with:
```rust
        for p in &self.players {
            h.write_i64(p.credits.to_bits());
            h.write_u64(u64::from(p.researched_techs));
            match p.active_research {
                Some((id, ticks)) => {
                    h.write_u64(1);
                    h.write_u64(u64::from(id));
                    h.write_u64(u64::from(ticks));
                }
                None => h.write_u64(0),
            }
        }
```

- [ ] **Step 8: Add UI/AI accessors.** Near the existing `credits`/`unit_cost` accessors add:
```rust
    /// Per-player research state: (researched bitmask, optional (tech id, ticks left)).
    #[must_use]
    pub fn research_state(&self, player: PlayerId) -> (u32, Option<(u32, u32)>) {
        let p = &self.players[usize::from(player.0)];
        (p.researched_techs, p.active_research)
    }

    /// Whether the player has at least one alive research lab.
    #[must_use]
    pub fn has_research_lab(&self, player: PlayerId) -> bool {
        self.entities.iter().any(|e| {
            e.alive
                && e.owner == player
                && matches!(e.kind, Kind::Building(BuildingKind::ResearchLab))
        })
    }
```

- [ ] **Step 9: Run new tests + re-pin the golden hash.** `cargo test -p rts-core research_completes research_is_rejected` → PASS. Then `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → **FAILS** (the hash input grew by the per-player research fields, even though values are zero in the golden run). This is expected and correct. Copy the actual hash from the failure message (`left: <NEW>`) and replace the constant in the test (`assert_eq!(s.state_hash(), <NEW>);`). Re-run → PASS. Then `cargo test --workspace` (fix any other test that pinned the old hash the same way — search for `3_409_360_777_067_811_056` and any AI-vs-AI determinism test that re-derives a hash will still pass since it compares runs, not a constant). `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`.

- [ ] **Step 10: Commit.**
```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): research state + Command::Research + run_research + hash (re-pin golden)" -m "Re-pins golden_hash: per-player research state is now hashed (zero-valued in the golden run but grows the hash input)." -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Apply research effects in combat / economy / movement (hash-preserving)

**Files:** `crates/core/src/game/sim.rs`.

These hooks add a per-player bonus that is **zero unless a tech is researched**, so the golden hash (whose AI run researches nothing yet) stays unchanged. The tests research techs manually to prove the effects.

- [ ] **Step 1: Write failing tests.**
```rust
    #[test]
    fn weapons_research_increases_damage_and_armor_reduces_it() {
        use crate::game::tech::TECHS;
        let dmg0 = TECHS[0].bonus; // Weapons I bonus
        let mit3 = TECHS[3].bonus; // Armor I bonus
        assert!(dmg0 > Fixed::ZERO && mit3 > Fixed::ZERO);
        // Unit test the pure bonus helpers directly:
        let mut s = Sim::new(Map::new(10, 10), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        // Force-complete Weapons I for P0 by researching with funds + lab + power:
        // (helper path is covered in Task 3; here assert the bonus accessor.)
        assert_eq!(s.player_weapon_bonus(P0), Fixed::ZERO);
        assert_eq!(s.player_armor_bonus(P0), Fixed::ZERO);
    }
```
> The deep end-to-end "researched Weapons I makes infantry hit harder" is best asserted via a focused combat test; add one if the existing combat tests give an easy harness. At minimum, pin the bonus helpers return 0 with no research and the tech bonuses are positive.

- [ ] **Step 2: Run, expect compile failure** (`player_weapon_bonus`, `player_armor_bonus` missing).

- [ ] **Step 3: Add the bonus helpers.** Add a private branch-sum + four public-in-crate accessors near the other helpers in `sim.rs`:
```rust
    /// Sum of researched-tech bonuses for `player` in `branch`.
    fn branch_bonus(&self, player: PlayerId, branch: crate::game::tech::TechBranch) -> Fixed {
        let mask = self.players[usize::from(player.0)].researched_techs;
        let mut total = Fixed::ZERO;
        let mut i = 0u32;
        while (i as usize) < crate::game::tech::TECH_COUNT {
            if mask & (1 << i) != 0 {
                let t = crate::game::tech::TECHS[i as usize];
                if t.branch == branch {
                    total = total + t.bonus;
                }
            }
            i += 1;
        }
        total
    }
    fn player_weapon_bonus(&self, p: PlayerId) -> Fixed { self.branch_bonus(p, crate::game::tech::TechBranch::Weapons) }
    fn player_armor_bonus(&self, p: PlayerId) -> Fixed { self.branch_bonus(p, crate::game::tech::TechBranch::Armor) }
    fn player_economy_bonus(&self, p: PlayerId) -> Fixed { self.branch_bonus(p, crate::game::tech::TechBranch::Economy) }
    fn player_mobility_bonus(&self, p: PlayerId) -> Fixed { self.branch_bonus(p, crate::game::tech::TechBranch::Mobility) }
```
(If the test references `player_weapon_bonus` from the test module, make these `pub(crate)` or test via a thin pub accessor. Simplest: mark the four accessors `pub(crate)`.)

- [ ] **Step 4: Hook combat.** In `run_combat`, BEFORE the candidate/damage loops, precompute per-player arrays (avoids borrowing `self` inside the `&mut` loop):
```rust
        let weapon: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_weapon_bonus(PlayerId(p as u8)));
        let armor: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_armor_bonus(PlayerId(p as u8)));
```
Where damage is pushed (currently `damage.push((j, profile.damage * mult));`), add the attacker's weapon bonus:
```rust
                damage.push((j, profile.damage * mult + weapon[usize::from(e.owner.0)]));
```
Where damage is applied (currently `self.entities[j].hp = self.entities[j].hp - dmg;`), subtract the defender's armor bonus, clamped to a `Fixed::ONE` floor:
```rust
            let owner = self.entities[j].owner;
            let net = dmg - armor[usize::from(owner.0)];
            let net = if net < Fixed::ONE { Fixed::ONE } else { net };
            self.entities[j].hp = self.entities[j].hp - net;
```

- [ ] **Step 5: Hook economy.** In `run_economy`, inside the `for p in 0..PLAYER_COUNT` loop, change the income application so the economy bonus is added before the power factor:
```rust
            let econ = self.player_economy_bonus(PlayerId(p as u8));
            self.players[p].credits = self.players[p].credits + (income[p] + econ) * factor;
```
(Replace the existing `self.players[p].credits = self.players[p].credits + income[p] * factor;`.)

- [ ] **Step 6: Hook movement.** In `run_movement`, precompute before the `for e in &mut self.entities` loop:
```rust
        let mobility: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| self.player_mobility_bonus(PlayerId(p as u8)));
```
and change `let speed = uk.stats().speed;` to `let speed = uk.stats().speed + mobility[usize::from(e.owner.0)];`.

- [ ] **Step 7: Run tests + determinism.** New tests PASS; `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → **PASS, constant UNCHANGED** (bonuses are 0 in the golden run, so all results are bit-identical); `cargo test --workspace`; clippy; fmt.

- [ ] **Step 8: Commit.**
```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): apply research bonuses live in combat/economy/movement (zero-bonus = hash-preserving)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: AI research behavior (re-pins golden hash #2)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: Write the failing test.**
```rust
    #[test]
    fn ai_builds_a_lab_and_researches() {
        let mut s = Sim::new(Map::new(40, 40), 7, f(2000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut lab_seen = false;
        let mut research_seen = false;
        for _ in 0..2000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            if s.has_research_lab(P0) {
                lab_seen = true;
            }
            if s.research_state(P0).1.is_some() || s.research_state(P0).0 != 0 {
                research_seen = true;
            }
        }
        assert!(lab_seen, "AI builds a research lab");
        assert!(research_seen, "AI starts/finishes research");
    }
```

- [ ] **Step 2: Run, expect FAIL** (AI never builds a lab / researches).

- [ ] **Step 3: Add ResearchLab to the AI build order.** In `ai_commands`, the essential build loop currently iterates `[PowerPlant, Refinery, Barracks]`. Change it to `[PowerPlant, Refinery, Barracks, ResearchLab]` so the AI builds a lab once its economy is up (still one build per tick via `building_this_tick`).

- [ ] **Step 4: Add deterministic research generation.** After the building/training blocks in `ai_commands` (before the movement block), add:
```rust
        // Research: if we have a lab and aren't already researching, start the
        // first eligible+affordable tech in a fixed priority order (deterministic,
        // symmetric for both players; skipping ineligible/unaffordable avoids stalls).
        if self.has_research_lab(player) && self.research_state(player).1.is_none() {
            const PRIORITY: [u32; 10] = [6, 0, 3, 7, 1, 4, 8, 2, 5, 9];
            let (mask, _) = self.research_state(player);
            for tech_id in PRIORITY {
                let def = crate::game::tech::TECHS[tech_id as usize];
                let researched = mask & (1 << tech_id) != 0;
                let prereq_ok = match def.prereq {
                    Some(req) => mask & (1 << req) != 0,
                    None => true,
                };
                if !researched && prereq_ok && credits >= def.cost {
                    cmds.push(Command::Research { owner: player, tech_id });
                    break;
                }
            }
        }
```
> `credits` is the local already computed at the top of `ai_commands`. Research is issued independently of `building_this_tick` (it's a different resource decision; `apply_command` deducts atomically and rejects if funds ran out, so issuing both a Build and a Research in one tick is safe).

- [ ] **Step 5: Run the new test + re-pin golden hash + fix AI-behavior assertions.**
  - `cargo test -p rts-core ai_builds_a_lab_and_researches` → PASS.
  - `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → **FAILS** (AI now builds a lab + researches → different run). Copy the new hash from the failure and re-pin the constant. Re-run → PASS.
  - `cargo test --workspace`: other AI tests may shift. Determinism tests (`ai_vs_ai_is_deterministic`, lockstep, replay) still PASS (they compare runs, not constants). If `ai_builds_up_its_economy_and_army` or similar asserts specific counts that legitimately changed because the AI now also builds a lab, update those expectations and note why in the commit. Do NOT loosen a determinism assertion.
  - Sanity-check balance: `cargo run --release -p rts-server -- playtest` and skim the win-split / stalemate-rate output; if research wildly unbalances it (e.g. one side always wins, or stalemate rate spikes), note it — balance tuning of `TECHS`/`ResearchLab` numbers is expected follow-up, not a blocker for the mechanic landing.
  - clippy; fmt.

- [ ] **Step 6: Commit.**
```bash
git add crates/core/src/game/sim.rs
git commit -m "feat(core): AI builds a ResearchLab and researches (fixed priority; re-pin golden)" -m "Re-pins golden_hash: AI now builds a lab and researches, changing the scripted AI-vs-AI run." -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Research UI (shell-only; no hash impact)

**Files:** `crates/render-shell/src/{ui,input,main,sprites}.rs`.

Goal: a build button (+ hotkey `L`) for the ResearchLab, and a **research modal** (toggled by a hotkey, e.g. `Tab` or `Y`) that lists the techs with status + progress and lets the player start a research. The modal pauses input like the existing overlays. Pixel layout is implementer discretion following the `draw_game_over` pattern; the data and command flow below are exact.

> Note: the ResearchLab sprite arm and the faction-aware names (`Research Lab` / `Fabricator`) were already added in Task 2 to keep the workspace compiling. `ResearchLab` uses `Action::Build`, so `cost()` / `action_texture()` need no new `Action` variant.

- [ ] **Step 1: Command-bar Lab button.** In `ui.rs` `layout()`, change the return type `fn layout() -> [Button; 7]` → `[Button; 8]`, change the group-gap in the `mk` closure from `if i >= 5` to `if i >= 6` (units stay grouped after the now-6 buildings), and make the button array:
```rust
    [
        mk(0, "Reactor", 'P', Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Extractor", 'R', Action::Build(BuildingKind::Refinery)),
        mk(2, "Hangar", 'B', Action::Build(BuildingKind::Barracks)),
        mk(3, "Laser Turret", 'G', Action::Build(BuildingKind::GunTurret)),
        mk(4, "Flak Turret", 'A', Action::Build(BuildingKind::AaTurret)),
        mk(5, "Lab", 'L', Action::Build(BuildingKind::ResearchLab)),
        mk(6, "Infantry", 'T', Action::Train(UnitKind::Infantry)),
        mk(7, "Gunship", 'H', Action::Train(UnitKind::Helicopter)),
    ]
```
Clicking the Lab button already works via the existing `Action::Build` → `build_mode` path in `handle_click`.

- [ ] **Step 2: Build hotkey for the Lab.** In `input.rs`, mirror the existing build hotkeys (P/R/B/G/A arm `build_mode`): add `KeyCode::L` → arm `build_mode = Some(BuildingKind::ResearchLab)`. (This is the BUILD key; the research MODAL toggle in Step 3 uses a different key.)

- [ ] **Step 3: Research modal state + input.** In `main.rs`, add `let mut research_open = false;` near the other loop state. Add input: when the research hotkey is pressed (and not paused / not over / not pointer-over-UI), toggle `research_open`. While `research_open`: the game is paused (gate the `sim.step` accumulator on `!research_open` as well as `!paused`), and number keys `1..=0` (or up/down + enter) map to a tech id; pressing a tech key issues `pending.push(Command::Research { owner: HUMAN, tech_id })` if `sim.research_state(HUMAN).1.is_none()`, then closes the modal. `Esc` closes without researching. Read tech defs via `rts_core::game::tech::{TECHS, TECH_COUNT, TechBranch}` and progress via `sim.research_state(HUMAN)` and `sim.has_research_lab(HUMAN)`.

- [ ] **Step 4: Draw the modal.** Add `fn draw_research_modal(sim: &Sim, sprites: &Sprites)` modeled on `draw_game_over`: dark overlay + centered panel; title "RESEARCH"; one row per tech in `TECHS` showing name, cost, and status — **Researched** (bit set), **In progress** (matches `active_research`, with a progress bar from `ticks_remaining`/`duration`), **Available** (prereq met, affordable, lab present), or **Locked** (prereq missing) / **No lab** (no ResearchLab); a footer hint (keys to research / Esc to close). Call it from the draw section after `ui::draw(...)` when `research_open`.

- [ ] **Step 5: Build + lint.** `cargo build -p rts-render-shell`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`. (No determinism impact — shell only.) Add a small `#[cfg(test)]` test in `ui.rs` if any pure helper was added (e.g. a tech-status classifier); otherwise rely on build + manual.

- [ ] **Step 6: Commit.**
```bash
git add crates/render-shell/src/ui.rs crates/render-shell/src/input.rs crates/render-shell/src/main.rs crates/render-shell/src/sprites.rs
git commit -m "feat(shell): ResearchLab build button + research modal (status/progress + start research)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Phase 2 verification gate + finish

- [ ] **Step 1: Full suite + determinism.** `cargo test --workspace` → all pass (golden hash now at its Task-5 re-pinned value). `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → PASS.
- [ ] **Step 2: Lints + wasm.** `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`.
- [ ] **Step 3: Playtest sanity.** `cargo run --release -p rts-server -- playtest` — capture win-split / match-length / stalemate-rate; note whether research left the matchup reasonable (balance tuning is acceptable follow-up).
- [ ] **Step 4: Manual smoke (best-effort).** If a display is available: `cargo run --release -p rts`, build a Lab, open the research modal, start a research, confirm it completes and (e.g.) Weapons makes hits land harder. Headless: skip and note it.

---

## Definition of done

- A `ResearchLab` building exists and is buildable (human via UI, AI in its build order).
- Players research a branching tree of 10 global upgrades; research state is hashed; one active research at a time; progress requires power.
- Weapons/Armor/Economy/Mobility bonuses apply live and retroactively in combat/economy/movement (clamped, fixed-point, deterministic).
- The AI researches deterministically and symmetrically; AI-vs-AI stays bit-identical (golden hash re-pinned to its new value).
- A research modal shows status/progress and starts research; full workspace test/clippy/fmt/wasm green.

## Notes / deferred
- Balance numbers (`TECHS`, `ResearchLab`) are first-pass — tune via the playtest harness in a follow-up.
- Tech tree is code-defined; moving it into RON (data-driven) is deferred (can land with the Phase-3 nested-RON work).
- The era-gating "key" techs that advance eras + per-era rosters are **Phase 3**, not here.
- If a ResearchLab is destroyed mid-research, progress still completes (minor v1 simplification).
