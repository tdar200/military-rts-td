# Phase 0 — Era/Faction Data Model Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the runtime `Balance` table era- and faction-aware (the structural prerequisite for the 4-era roster and the mirrored alien faction) **without changing any game behavior** — every existing test, including the cross-target golden state hash, stays green.

**Architecture:** Introduce `Era` and `Faction` enums and store unit/building stats in `Balance` keyed by `[era][faction]`, filled by replicating today's canonical Modern/Human numbers across all tiers. Keep the existing `Balance::unit(kind)` / `building(kind)` accessors as thin Modern/Human wrappers so every current call site in `sim.rs` is untouched and `state_hash()` (which never reads `balance`) produces the identical hash. Per-era/faction *divergence*, per-player era/faction tracking, and nested RON come in later phases.

**Tech Stack:** Rust (workspace), `rts-core` (`no_std`, `#![deny(clippy::float_arithmetic)]`, zero deps, fixed-point `Fixed`), `rts-data` (RON loader). Strict lints: deny warnings, Clippy `pedantic` + `nursery`.

**Spec:** [`docs/superpowers/specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — this plan implements **Phase 0** of that 7-phase program.

**Before you start:**
- Work on a dedicated branch: `git checkout -b feat/era-faction-data-model` (current branch is `feat/core-foundation`).
- Ensure the wasm target is installed: `rustup target add wasm32-unknown-unknown`.
- All commit messages should follow repo convention and end with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Determinism rule for this whole phase: **the golden hash constant must not change.** If `golden_hash_pins_cross_target_determinism` ever fails, you changed behavior — stop and fix the refactor, do not re-pin the constant.

### Scope notes (deliberate deltas from the spec's Phase 0)

The spec's Phase 0 also listed "single source of truth for stats," "load-time
validation," and "golden hashes regenerated & committed." This plan scopes those
differently on purpose, because the lowest-risk first step is a *behavior-
preserving* refactor:

- **Source-of-truth consolidation is deferred to Phase 3.** Today `stats.rs`
  `const fn`s are canonical and `balance.ron` mirrors them (the existing
  `default_ron_matches_the_code_default` test enforces equality). Collapsing to
  one source *now* would either drop the compile-time `const` stats (a real cost
  the code review flagged) or force nested per-era RON before any divergent era
  data exists (premature). It becomes genuinely necessary — and is done — in
  Phase 3, when era stats first diverge.
- **Load-time validation is N/A here:** fixed-size `[era][faction]` arrays make
  missing entries structurally impossible. Validation arrives alongside nested
  RON in Phase 3.
- **Golden-hash regeneration is NOT needed:** this phase is hash-preserving by
  design (a strict improvement over what the spec assumed). Hash re-pinning
  starts in Phase 2, when the first new hashed state is added.

---

## File Structure

Phase 0 modifies exactly two source files. No new files, no `sim.rs` changes, no `balance.ron` changes, no `rts-data` changes.

- **Modify `crates/core/src/game/stats.rs`** — add the `Era` and `Faction` classification enums + `ERA_COUNT` / `FACTION_COUNT` constants and their `index()` methods. (Responsibility: defines unit/building/era/faction *kinds* and canonical stats.)
- **Modify `crates/core/src/game/balance.rs`** — change `Balance` storage to `[era][faction]`-keyed arrays; add `unit_in` / `building_in` accessors; keep `unit` / `building` as Modern/Human wrappers; make `from_tables` / `const_default` replicate one tier across all eras/factions. (Responsibility: the runtime stat table the `Sim` reads.)

Tests live inline in each file's existing `#[cfg(test)] mod tests`.

---

## Task 1: Add `Era` and `Faction` enums to `stats.rs`

**Files:**
- Modify: `crates/core/src/game/stats.rs` (add enums after the `ArmorType` enum, ~line 30; add a test to the existing `mod tests` at the bottom)
- Test: `crates/core/src/game/stats.rs` (inline `mod tests`)

- [ ] **Step 1: Write the failing test**

Add this test function inside the existing `#[cfg(test)] mod tests { ... }` block at the bottom of `crates/core/src/game/stats.rs`:

```rust
    #[test]
    fn era_and_faction_indices_are_dense_and_in_bounds() {
        use super::{Era, Faction, ERA_COUNT, FACTION_COUNT};
        assert_eq!(ERA_COUNT, 4);
        assert_eq!(FACTION_COUNT, 2);
        assert_eq!(Era::Modern.index(), 0);
        assert_eq!(Era::Interstellar.index(), 3);
        assert_eq!(Faction::Human.index(), 0);
        assert_eq!(Faction::Alien.index(), 1);
        assert!(Era::Interstellar.index() < ERA_COUNT);
        assert!(Faction::Alien.index() < FACTION_COUNT);
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p rts-core era_and_faction_indices`
Expected: **compile error** — `cannot find type 'Era' in this scope` / unresolved import `Era`, `Faction`, `ERA_COUNT`, `FACTION_COUNT`.

- [ ] **Step 3: Write minimal implementation**

In `crates/core/src/game/stats.rs`, immediately after the `ArmorType` enum definition (after its closing `}` near line 30), add:

```rust
/// Number of technology eras (Modern → Interstellar).
pub const ERA_COUNT: usize = 4;

/// Number of factions (Human, Alien).
pub const FACTION_COUNT: usize = 2;

/// The technology era a roster tier belongs to. Later eras upgrade the roster in
/// place; Era 1 (`Modern`) is the game's starting tier.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Era {
    /// 21st-century conventional military (the starting era).
    Modern,
    /// Moon / Mars orbital tier.
    Orbital,
    /// Solar-system / interplanetary tier.
    Interplanetary,
    /// Interstellar tier — the alien-war endgame.
    Interstellar,
}

/// Which side a roster tier belongs to. Aliens mirror human stats in v1 (cosmetic
/// only); the faction axis exists so the rosters can diverge later.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Faction {
    /// Humanity (the player's default side).
    Human,
    /// The alien invaders.
    Alien,
}

impl Era {
    /// Dense index into era-keyed tables, in `0..ERA_COUNT`.
    #[must_use]
    pub const fn index(self) -> usize {
        match self {
            Self::Modern => 0,
            Self::Orbital => 1,
            Self::Interplanetary => 2,
            Self::Interstellar => 3,
        }
    }
}

impl Faction {
    /// Dense index into faction-keyed tables, in `0..FACTION_COUNT`.
    #[must_use]
    pub const fn index(self) -> usize {
        match self {
            Self::Human => 0,
            Self::Alien => 1,
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p rts-core era_and_faction_indices`
Expected: **PASS** (`test ... era_and_faction_indices_are_dense_and_in_bounds ... ok`).

- [ ] **Step 5: Verify lints are clean**

Run: `cargo clippy -p rts-core --all-targets -- -D warnings`
Expected: no warnings/errors (the new `pub` items are reachable API, so no `dead_code`).

- [ ] **Step 6: Commit**

```bash
git add crates/core/src/game/stats.rs
git commit -m "feat(core): add Era and Faction enums + dense indices"
```

---

## Task 2: Make `Balance` era/faction-keyed (behavior-preserving)

**Files:**
- Modify: `crates/core/src/game/balance.rs` (replace the struct, constructors, and accessors; extend the `mod tests`)
- Test: `crates/core/src/game/balance.rs` (inline `mod tests`)

- [ ] **Step 1: Write the failing tests**

Replace the entire `#[cfg(test)] mod tests { ... }` block at the bottom of `crates/core/src/game/balance.rs` with:

```rust
#[cfg(test)]
mod tests {
    use super::Balance;
    use crate::game::stats::{BuildingKind, Era, Faction, UnitKind};

    const ERAS: [Era; 4] = [
        Era::Modern,
        Era::Orbital,
        Era::Interplanetary,
        Era::Interstellar,
    ];
    const FACTIONS: [Faction; 2] = [Faction::Human, Faction::Alien];

    #[test]
    fn default_balance_matches_canonical_stats() {
        let b = Balance::default();
        assert_eq!(b.unit(UnitKind::Tank), UnitKind::Tank.stats());
        assert_eq!(
            b.building(BuildingKind::Refinery),
            BuildingKind::Refinery.stats()
        );
    }

    #[test]
    fn every_era_and_faction_returns_canonical_stats_for_now() {
        let b = Balance::default();
        for era in ERAS {
            for faction in FACTIONS {
                assert_eq!(
                    b.unit_in(era, faction, UnitKind::Infantry),
                    UnitKind::Infantry.stats()
                );
                assert_eq!(
                    b.building_in(era, faction, BuildingKind::GunTurret),
                    BuildingKind::GunTurret.stats()
                );
            }
        }
    }

    #[test]
    fn alien_mirrors_human_in_every_era() {
        // v1 invariant: aliens are a cosmetic mirror — identical stats to humans.
        let b = Balance::default();
        for era in ERAS {
            assert_eq!(
                b.unit_in(era, Faction::Human, UnitKind::Tank),
                b.unit_in(era, Faction::Alien, UnitKind::Tank)
            );
            assert_eq!(
                b.building_in(era, Faction::Human, BuildingKind::CommandCenter),
                b.building_in(era, Faction::Alien, BuildingKind::CommandCenter)
            );
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p rts-core every_era_and_faction`
Expected: **compile error** — `no method named 'unit_in' found for struct 'Balance'` (and `building_in`).

- [ ] **Step 3: Write the implementation**

Replace the `use` line and everything from `pub struct Balance` through the `impl Default for Balance` block (i.e. lines 9–77, everything **above** the `#[cfg(test)]`) in `crates/core/src/game/balance.rs` with:

```rust
use crate::game::stats::{
    BuildingKind, BuildingStats, Era, Faction, UnitKind, UnitStats, ERA_COUNT, FACTION_COUNT,
};

/// A complete set of unit and building stats, keyed by `[era][faction]`.
///
/// Every era/faction tier is currently a copy of the canonical Modern/Human
/// numbers in [`stats`](crate::game::stats); per-era and per-faction divergence
/// is introduced in a later phase. The plain [`unit`](Balance::unit) /
/// [`building`](Balance::building) accessors read the Modern/Human tier so the
/// `Sim`'s existing call sites are unaffected.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Balance {
    units: [[[UnitStats; 4]; FACTION_COUNT]; ERA_COUNT],
    buildings: [[[BuildingStats; 7]; FACTION_COUNT]; ERA_COUNT],
}

impl Balance {
    /// The default balance — the canonical numbers from [`stats`](crate::game::stats),
    /// replicated across every era and faction.
    #[must_use]
    pub const fn const_default() -> Self {
        Self::from_tables(
            [
                UnitKind::Infantry.stats(),
                UnitKind::Tank.stats(),
                UnitKind::AntiArmor.stats(),
                UnitKind::Helicopter.stats(),
            ],
            [
                BuildingKind::CommandCenter.stats(),
                BuildingKind::PowerPlant.stats(),
                BuildingKind::Refinery.stats(),
                BuildingKind::Barracks.stats(),
                BuildingKind::GunTurret.stats(),
                BuildingKind::AaTurret.stats(),
                BuildingKind::Wall.stats(),
            ],
        )
    }

    /// Builds a balance from one canonical (Modern/Human) tier, replicated across
    /// every era and faction. Used by data loaders; per-era/faction divergence is
    /// introduced in a later phase.
    #[must_use]
    pub const fn from_tables(units: [UnitStats; 4], buildings: [BuildingStats; 7]) -> Self {
        let unit_tier = [units, units];
        let bld_tier = [buildings, buildings];
        Self {
            units: [unit_tier, unit_tier, unit_tier, unit_tier],
            buildings: [bld_tier, bld_tier, bld_tier, bld_tier],
        }
    }

    /// Stats for a unit kind in a given era and faction.
    #[must_use]
    pub const fn unit_in(&self, era: Era, faction: Faction, kind: UnitKind) -> UnitStats {
        let tier = self.units[era.index()][faction.index()];
        match kind {
            UnitKind::Infantry => tier[0],
            UnitKind::Tank => tier[1],
            UnitKind::AntiArmor => tier[2],
            UnitKind::Helicopter => tier[3],
        }
    }

    /// Stats for a building kind in a given era and faction.
    #[must_use]
    pub const fn building_in(
        &self,
        era: Era,
        faction: Faction,
        kind: BuildingKind,
    ) -> BuildingStats {
        let tier = self.buildings[era.index()][faction.index()];
        match kind {
            BuildingKind::CommandCenter => tier[0],
            BuildingKind::PowerPlant => tier[1],
            BuildingKind::Refinery => tier[2],
            BuildingKind::Barracks => tier[3],
            BuildingKind::GunTurret => tier[4],
            BuildingKind::AaTurret => tier[5],
            BuildingKind::Wall => tier[6],
        }
    }

    /// Stats for a unit kind in the default (Modern era, Human faction) tier.
    #[must_use]
    pub const fn unit(&self, kind: UnitKind) -> UnitStats {
        self.unit_in(Era::Modern, Faction::Human, kind)
    }

    /// Stats for a building kind in the default (Modern era, Human faction) tier.
    #[must_use]
    pub const fn building(&self, kind: BuildingKind) -> BuildingStats {
        self.building_in(Era::Modern, Faction::Human, kind)
    }
}

impl Default for Balance {
    fn default() -> Self {
        Self::const_default()
    }
}
```

Note: the doc-comment at the top of the file (lines 1–7) can stay; only the code below `use ...` is replaced. The `#[cfg(test)] mod tests` you wrote in Step 1 stays.

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cargo test -p rts-core every_era_and_faction alien_mirrors_human default_balance_matches`
Expected: **PASS** for `every_era_and_faction_returns_canonical_stats_for_now`, `alien_mirrors_human_in_every_era`, and `default_balance_matches_canonical_stats`.

- [ ] **Step 5: Confirm `rts-data` still builds against the unchanged `from_tables` signature**

Run: `cargo test -p rts-data`
Expected: **PASS** — `default_ron_matches_the_code_default`, `tweaking_a_value_takes_effect_without_recompiling_core`, `malformed_ron_is_an_error` all still pass (the `from_tables(units, buildings)` signature is unchanged; it now replicates the tier internally).

- [ ] **Step 6: Commit**

```bash
git add crates/core/src/game/balance.rs
git commit -m "feat(core): key Balance by era+faction (Modern/Human tier replicated); behavior-preserving"
```

---

## Task 3: Verify determinism is preserved across the whole workspace

This task adds no production code — it is the gate that proves the refactor changed nothing observable. The key assertion is that the **golden hash constant is unchanged**.

**Files:** none modified (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `cargo test --workspace`
Expected: **all tests pass**, including `golden_hash_pins_cross_target_determinism` (the constant `3_409_360_777_067_811_056` is unchanged). If that specific test fails, the refactor altered behavior — revert and find the discrepancy; do **not** edit the constant.

- [ ] **Step 2: Run strict Clippy**

Run: `cargo clippy --workspace --all-targets -- -D warnings`
Expected: no warnings or errors.

- [ ] **Step 3: Check formatting**

Run: `cargo fmt --all -- --check`
Expected: no diff. (If it reports changes, run `cargo fmt --all` and re-check.)

- [ ] **Step 4: Build the wasm target (proves `no_std` core still compiles cross-target)**

Run: `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`
Expected: builds successfully.

- [ ] **Step 5: Commit (if formatting produced changes; otherwise skip)**

```bash
git add -A
git commit -m "chore(core): fmt after era/faction Balance refactor"
```

(If Steps 1–4 all passed with no file changes, there is nothing to commit here — Phase 0 is already committed via Tasks 1 and 2.)

---

## Phase 0 done — definition of done

- `Era` and `Faction` enums exist with dense `index()` and `ERA_COUNT`/`FACTION_COUNT` constants.
- `Balance` stores stats keyed by `[era][faction]`; `unit_in`/`building_in` resolve any tier; `unit`/`building` resolve the Modern/Human tier.
- Every era/faction tier currently returns the canonical Modern/Human stats (tests assert this and the alien-mirror invariant).
- `sim.rs`, `balance.ron`, and `rts-data` are untouched; **the golden hash is unchanged**; full workspace test/clippy/fmt/wasm all green.

---

## Downstream phases (each gets its own plan when we reach it)

These are scoped in the spec and will be turned into their own bite-sized plans in order — do **not** start them from this plan:

- **Phase 1 — Space reskin, Era-1 slice (shippable):** retheme strings/scenarios/README/story; thread per-player `Faction`; alien palette tint + data-driven names in `render-shell`; placeholder-first game-icons art. (Touches `render-shell`: `sprites.rs`, `theme.rs`, `ui.rs`, plus `scenario.rs`.)
- **Phase 2 — Tech-tree research:** `ResearchLab`, `Command::Research`, `run_research()` `u32`-tick phase, validated tech-tree data, AI research (deterministic, symmetric, anti-stall), placeholder research modal. (Re-pins the golden hash — new hashed state.)
- **Phase 3 — Era advancement + per-era roster:** per-player `era` (hashed), era-gating key techs, per-era stat tiers + new unit incarnations via `era_acquired`, `Capital` unit kind, nested per-era RON, migrate `sim.rs` call sites to `unit_in`/`building_in`, era badge + command-bar tabs + `(Kind,Era,Faction)` sprites.
- **Phase 4 — Energy shields:** per-entity `shield`/`last_combat_tick` (hashed), `run_shields()` regen (stored `Fixed`/tick), shield-piercing `AttackProfile` flag, research-gated, cyan shield bars, cross-platform regen tests.
- **Phase 5 — Antimatter (3rd resource):** per-player `antimatter` (hashed), producer building (passive trickle), top-tier/Capital-Ship costs, economy + AI + top-bar UI.
- **Phase 6 — Anti-grav / flight:** per-unit `is_antigrav` flag reusing `is_air` straight-line movement (never alters map passability), late-era ground units, path determinism tests.
