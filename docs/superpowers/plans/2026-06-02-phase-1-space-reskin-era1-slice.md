# Phase 1 — Space Reskin (Era-1 Shippable Slice) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the existing Era-1 (Modern) game into the space / alien-invasion slice — humans (P0) vs a synthetic alien faction (P1) — via **display names, one palette color, and narrative/scenario text only**. No gameplay/balance/sim-state change; the golden state hash stays identical.

**Architecture:** Faction is already a render-time concept (`v.owner == HUMAN`). So this is purely cosmetic + display strings: (1) faction-aware unit/building names in the shell, (2) human command-bar relabels, (3) recolor the alien tint to toxic green, (4) scenario names/taglines (core display strings — not hashed), (5) title-screen / game-over / README narrative. The deterministic core's sim logic and state hash are untouched.

**Tech Stack:** Rust workspace — `rts-core` (`no_std`, fixed-point, golden-hash determinism) for scenario display strings only; `rts-render-shell` (Macroquad bin) for names/palette/narrative.

**Spec:** [`docs/superpowers/specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 1 of the 7-phase program. (Phase 0 — era/faction-aware `Balance` — is already merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase1-space-reskin` (from `feat/core-foundation`).
- The working tree is **clean** (prior WIP was committed as the milestone `363375e`), so normal targeted commits apply. Still, stage only the files each task names.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism rule:** the golden hash (`3_409_360_777_067_811_056` in `crates/core/src/game/sim.rs`) must NOT change. Scenario name/tagline strings are display-only and not part of `state_hash()`; nothing in this phase touches sim logic. If `golden_hash_pins_cross_target_determinism` ever fails, you changed something you shouldn't have.

### Locked content decisions (use these exact strings)

**Human (P0) Era-1 relabels** — Infantry / Tank / Anti-Armor keep their names; Helicopter→**Gunship**, Command Center→**Command Nexus**, Power Plant→**Reactor**, Refinery→**Extractor**, Barracks→**Hangar**, Gun Turret→**Laser Turret**, AA Turret→**Flak Turret**, Wall→**Barrier**.

**Alien (P1) names (synthetic/machine)** — Infantry→**Drone**, Tank→**Crawler**, Anti-Armor→**Lancer**, Helicopter→**Wasp**, Command Center→**Core Node**, Power Plant→**Power Node**, Refinery→**Extractor**, Barracks→**Assembler**, Gun Turret→**Sentry**, AA Turret→**Interceptor**, Wall→**Barrier**.

**Alien palette** — toxic green `color_u8!(100, 200, 80, 255)`.

**Scenarios** — Lane Defense→**Orbital Siege** / "Hold the approach lanes against alien waves"; Open Clash→**Open Front** / "Open-field clash — no walls, no waves"; Crossroads→**Crater Crossroads** / "Flank a central wreck under pressure".

> **Narrative wordmarks are the user's to finalize** (title-screen game name, game-over words). This plan uses concrete placeholders flagged inline; keep the title (62px) and game-over (56px) words short enough not to overflow.

---

## File Structure

- **Modify `crates/core/src/game/scenario.rs`** — `Scenario::name()` / `tagline()` display strings (Task 1). Only display; not hashed.
- **Modify `crates/render-shell/src/ui.rs`** — faction-aware `kind_name_role` + callsites + command-bar labels (Task 2).
- **Modify `crates/render-shell/src/theme.rs`** — recolor the alien tint (Task 3).
- **Modify `crates/render-shell/src/main.rs`** — title-screen + game-over text (Task 3).
- **Modify `README.md`** — intro + controls reskin (Task 3).

No `sim.rs` change. No new files. No `balance.ron` change.

---

## Task 1: Scenario names + taglines (core, hash-safe)

**Files:**
- Modify: `crates/core/src/game/scenario.rs` (the `name()` ~lines 139-145 and `tagline()` ~lines 148-155 methods; add a test to the file's `#[cfg(test)] mod tests`)
- Test: `crates/core/src/game/scenario.rs` (inline)

- [ ] **Step 1: Check for existing string assertions, then write/Update the test.**

First run `grep -n "Lane Defense\|Open Clash\|Crossroads\|escalating waves\|central fortress" crates/core/src/game/scenario.rs` to find any existing test asserting the OLD strings; you will update those expectations in Step 3. Then add this test to the `#[cfg(test)] mod tests { ... }` block at the bottom of `scenario.rs`:

```rust
    #[test]
    fn scenarios_use_space_theme_names() {
        assert_eq!(Scenario::LaneDefense.name(), "Orbital Siege");
        assert_eq!(Scenario::OpenClash.name(), "Open Front");
        assert_eq!(Scenario::Crossroads.name(), "Crater Crossroads");
        assert_eq!(
            Scenario::LaneDefense.tagline(),
            "Hold the approach lanes against alien waves"
        );
    }
```

(If the test module's `use` doesn't already bring `Scenario` into scope, add `use super::Scenario;` inside the test fn or module as the file's pattern dictates.)

- [ ] **Step 2: Run to verify it fails.**

Run: `cargo test -p rts-core scenarios_use_space_theme_names`
Expected: FAIL — assertion mismatch (still returns "Lane Defense", etc.).

- [ ] **Step 3: Update the strings.**

In `crates/core/src/game/scenario.rs`, replace the `name()` match arms:
```rust
            Self::LaneDefense => "Lane Defense",
            Self::OpenClash => "Open Clash",
            Self::Crossroads => "Crossroads",
```
with:
```rust
            Self::LaneDefense => "Orbital Siege",
            Self::OpenClash => "Open Front",
            Self::Crossroads => "Crater Crossroads",
```
and replace the `tagline()` match arms:
```rust
            Self::LaneDefense => "Hold two lanes against escalating waves",
            Self::OpenClash => "Open-field skirmish — no walls, no waves",
            Self::Crossroads => "Flank a central fortress under pressure",
```
with:
```rust
            Self::LaneDefense => "Hold the approach lanes against alien waves",
            Self::OpenClash => "Open-field clash — no walls, no waves",
            Self::Crossroads => "Flank a central wreck under pressure",
```
If Step 1's grep found other tests asserting the old strings, update those expected values to the new strings now.

- [ ] **Step 4: Run tests.**

Run: `cargo test -p rts-core scenarios_use_space_theme_names` → PASS.
Run: `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → PASS (constant unchanged — proves the rename is display-only).
Run: `cargo test -p rts-core` → all pass.

- [ ] **Step 5: Lints + commit (targeted).**

```bash
cargo clippy -p rts-core --all-targets -- -D warnings   # clean
cargo fmt -p rts-core -- --check                          # clean (else: cargo fmt -p rts-core)
git add crates/core/src/game/scenario.rs
git commit -m "feat(core): reskin scenario names/taglines to the space theme (display-only)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Confirm `git show --stat HEAD` shows only `scenario.rs`.

---

## Task 2: Faction-aware display names + human command-bar labels (shell)

**Files:**
- Modify: `crates/render-shell/src/ui.rs` (the `kind_name_role` fn ~252-270 and its callsites ~284 and ~405; the command-bar labels ~77-85; add a `#[cfg(test)] mod tests`)
- Test: `crates/render-shell/src/ui.rs` (inline)

- [ ] **Step 1: Write the failing test.**

Add to the bottom of `crates/render-shell/src/ui.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::{kind_name_role, HUMAN};
    use rts_core::game::sim::{EntityKindView, PlayerId};
    use rts_core::game::stats::{BuildingKind, UnitKind};

    #[test]
    fn names_are_faction_aware() {
        let inf = EntityKindView::Unit(UnitKind::Infantry);
        assert_eq!(kind_name_role(inf, HUMAN).0, "Infantry");
        assert_eq!(kind_name_role(inf, PlayerId(1)).0, "Drone");

        let cc = EntityKindView::Building(BuildingKind::CommandCenter);
        assert_eq!(kind_name_role(cc, HUMAN).0, "Command Nexus");
        assert_eq!(kind_name_role(cc, PlayerId(1)).0, "Core Node");

        let heli = EntityKindView::Unit(UnitKind::Helicopter);
        assert_eq!(kind_name_role(heli, HUMAN).0, "Gunship");
        assert_eq!(kind_name_role(heli, PlayerId(1)).0, "Wasp");
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cargo test -p rts-render-shell names_are_faction_aware`
Expected: compile error — `kind_name_role` currently takes one argument (`kind`), so the two-arg calls don't type-check (and it isn't faction-aware yet).

- [ ] **Step 3: Make `kind_name_role` faction-aware.**

In `crates/render-shell/src/ui.rs`, replace the entire existing `kind_name_role` function:
```rust
const fn kind_name_role(kind: EntityKindView) -> (&'static str, &'static str) {
    match kind {
        EntityKindView::Unit(UnitKind::Infantry) => ("Infantry", "Cheap anti-infantry"),
        EntityKindView::Unit(UnitKind::Tank) => ("Tank", "Heavy armour, anti-ground"),
        EntityKindView::Unit(UnitKind::AntiArmor) => {
            ("Anti-Armor", "Beats tanks, weak vs infantry")
        }
        EntityKindView::Unit(UnitKind::Helicopter) => ("Helicopter", "Air — only AA can hit it"),
        EntityKindView::Building(BuildingKind::CommandCenter) => {
            ("Command Center", "Your base — protect it")
        }
        EntityKindView::Building(BuildingKind::PowerPlant) => ("Power Plant", "Supplies power"),
        EntityKindView::Building(BuildingKind::Refinery) => ("Refinery", "+credits while powered"),
        EntityKindView::Building(BuildingKind::Barracks) => ("Barracks", "Trains units"),
        EntityKindView::Building(BuildingKind::GunTurret) => ("Gun Turret", "Anti-ground defence"),
        EntityKindView::Building(BuildingKind::AaTurret) => ("AA Turret", "Anti-air defence"),
        EntityKindView::Building(BuildingKind::Wall) => ("Wall", "Blocks movement"),
    }
}
```
with a dispatcher + two faction tables:
```rust
/// Display name + one-line role for an entity, themed by faction (Human P0 vs the
/// Alien AI). Stats are identical across factions — only the cosmetic name and
/// blurb differ.
fn kind_name_role(kind: EntityKindView, owner: PlayerId) -> (&'static str, &'static str) {
    if owner == HUMAN {
        human_name_role(kind)
    } else {
        alien_name_role(kind)
    }
}

const fn human_name_role(kind: EntityKindView) -> (&'static str, &'static str) {
    match kind {
        EntityKindView::Unit(UnitKind::Infantry) => ("Infantry", "Cheap anti-infantry"),
        EntityKindView::Unit(UnitKind::Tank) => ("Tank", "Heavy armour, anti-ground"),
        EntityKindView::Unit(UnitKind::AntiArmor) => {
            ("Anti-Armor", "Beats tanks, weak vs infantry")
        }
        EntityKindView::Unit(UnitKind::Helicopter) => ("Gunship", "Air — only flak can hit it"),
        EntityKindView::Building(BuildingKind::CommandCenter) => {
            ("Command Nexus", "Your base — protect it")
        }
        EntityKindView::Building(BuildingKind::PowerPlant) => ("Reactor", "Supplies power"),
        EntityKindView::Building(BuildingKind::Refinery) => ("Extractor", "+credits while powered"),
        EntityKindView::Building(BuildingKind::Barracks) => ("Hangar", "Trains units"),
        EntityKindView::Building(BuildingKind::GunTurret) => ("Laser Turret", "Anti-ground defence"),
        EntityKindView::Building(BuildingKind::AaTurret) => ("Flak Turret", "Anti-air defence"),
        EntityKindView::Building(BuildingKind::Wall) => ("Barrier", "Blocks movement"),
    }
}

const fn alien_name_role(kind: EntityKindView) -> (&'static str, &'static str) {
    match kind {
        EntityKindView::Unit(UnitKind::Infantry) => ("Drone", "Cheap anti-infantry swarm"),
        EntityKindView::Unit(UnitKind::Tank) => ("Crawler", "Heavy armour, anti-ground"),
        EntityKindView::Unit(UnitKind::AntiArmor) => ("Lancer", "Beats armour, weak vs swarm"),
        EntityKindView::Unit(UnitKind::Helicopter) => ("Wasp", "Flyer — only flak can hit it"),
        EntityKindView::Building(BuildingKind::CommandCenter) => {
            ("Core Node", "Alien core — destroy it")
        }
        EntityKindView::Building(BuildingKind::PowerPlant) => ("Power Node", "Powers the alien base"),
        EntityKindView::Building(BuildingKind::Refinery) => ("Extractor", "Feeds the alien economy"),
        EntityKindView::Building(BuildingKind::Barracks) => ("Assembler", "Builds alien units"),
        EntityKindView::Building(BuildingKind::GunTurret) => ("Sentry", "Anti-ground defence"),
        EntityKindView::Building(BuildingKind::AaTurret) => ("Interceptor", "Anti-air defence"),
        EntityKindView::Building(BuildingKind::Wall) => ("Barrier", "Blocks movement"),
    }
}
```

- [ ] **Step 4: Update the two callsites to pass `owner`.**

In `draw_selection_panel` (~line 284), the selected entity's owner drives the name:
```rust
    let (name, role) = kind_name_role(view.kind);
```
→
```rust
    let (name, role) = kind_name_role(view.kind, view.owner);
```

In `draw_tooltip` (~line 405-406), the command bar is the human player's, so always pass `HUMAN`:
```rust
    let (name, role) = kind_name_role(action_kind(action));
```
→
```rust
    let (name, role) = kind_name_role(action_kind(action), HUMAN);
```

- [ ] **Step 5: Relabel the human command bar.**

In the command-bar layout (~lines 77-85), update the build/train button labels to the human names (keep the index, hotkey char, and `Action` unchanged):
```rust
        mk(0, "Power", 'P', Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Refinery", 'R', Action::Build(BuildingKind::Refinery)),
        mk(2, "Barracks", 'B', Action::Build(BuildingKind::Barracks)),
        mk(3, "Gun Turret", 'G', Action::Build(BuildingKind::GunTurret)),
        mk(4, "AA Turret", 'A', Action::Build(BuildingKind::AaTurret)),
        mk(5, "Infantry", 'T', Action::Train(UnitKind::Infantry)),
        mk(6, "Helicopter", 'H', Action::Train(UnitKind::Helicopter)),
```
→
```rust
        mk(0, "Reactor", 'P', Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Extractor", 'R', Action::Build(BuildingKind::Refinery)),
        mk(2, "Hangar", 'B', Action::Build(BuildingKind::Barracks)),
        mk(3, "Laser Turret", 'G', Action::Build(BuildingKind::GunTurret)),
        mk(4, "Flak Turret", 'A', Action::Build(BuildingKind::AaTurret)),
        mk(5, "Infantry", 'T', Action::Train(UnitKind::Infantry)),
        mk(6, "Gunship", 'H', Action::Train(UnitKind::Helicopter)),
```
(Hotkey chars stay as-is — they're key bindings, not derived from labels. The `H`/Gunship and `G`/Laser-Turret pairings are intentional carry-overs.)

- [ ] **Step 6: Run tests + lints.**

Run: `cargo test -p rts-render-shell names_are_faction_aware` → PASS.
Run: `cargo test -p rts-render-shell` → all pass.
Run: `cargo clippy -p rts-render-shell --all-targets -- -D warnings` → clean. (If clippy flags `kind_name_role` could be `const fn`: it can't — it compares `PlayerId` via `==`, which isn't const; that's expected. If clippy raises anything else, fix it.)
Run: `cargo fmt -p rts-render-shell -- --check` → clean (else `cargo fmt -p rts-render-shell`, then confirm `git status --short` shows only `ui.rs`).

- [ ] **Step 7: Commit (targeted).**

```bash
git add crates/render-shell/src/ui.rs
git commit -m "feat(shell): faction-aware unit/building names + human command-bar relabels" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Confirm `git show --stat HEAD` shows only `ui.rs`.

---

## Task 3: Alien palette + narrative reskin (theme.rs + main.rs + README)

Pure cosmetic/text. No new tests — verified by build + clippy + visual.

**Files:**
- Modify: `crates/render-shell/src/theme.rs` (the `TEAM_ENEMY` constant ~89-91)
- Modify: `crates/render-shell/src/main.rs` (title screen ~430-455, game-over ~560-564)
- Modify: `README.md`

- [ ] **Step 1: Recolor the alien tint.**

In `crates/render-shell/src/theme.rs`, replace:
```rust
/// Enemy faction tint — a warm brick-red, kept less chromatic than the gold so it
/// doesn't out-saturate the HUD accent.
pub const TEAM_ENEMY: Color = color_u8!(200, 66, 58, 255);
```
with:
```rust
/// Alien (enemy) faction tint — a sickly toxic green that reads as synthetic and
/// is hue-distinct from the steel-teal player and the red HP/threat cues.
pub const TEAM_ENEMY: Color = color_u8!(100, 200, 80, 255);
```
(Keeping the name `TEAM_ENEMY` means the draw sites in `main.rs`/`ui.rs` and their imports need no change — P1 already renders via `TEAM_ENEMY`. A rename to `TEAM_ALIEN` is optional polish, deferred to avoid churn.)

- [ ] **Step 2: Reskin the title screen.**

In `crates/render-shell/src/main.rs`, in the title block (~lines 429-460), change these four string literals (leave the surrounding `centered(...)` args untouched):
- `"FIELD COMMAND"` → `"EARTH COMMAND"`
- `"MILITARY RTS"` → `"STELLAR FRONT"`  *(working game name — user may rename; keep short, it renders at 62px)*
- `"CHOOSE YOUR BATTLEFIELD"` → `"CHOOSE YOUR FRONT"`
- `"THREE THEATRES · ONE COMMAND"` → `"THREE FRONTS · ONE WAR"`

- [ ] **Step 3: Reskin the game-over text.**

In `crates/render-shell/src/main.rs` (~lines 560-564), replace:
```rust
    let (msg, color) = if winner == HUMAN {
        ("VICTORY", GOOD)
    } else {
        ("DEFEAT", BAD)
    };
```
with:
```rust
    let (msg, color) = if winner == HUMAN {
        ("REPELLED", GOOD)
    } else {
        ("OVERRUN", BAD)
    };
```
*(Renders at 56px — keep replacements short, ≤ ~9 chars, so they don't overflow the 440px panel. "REPELLED" = you held off the invasion; "OVERRUN" = you fell. User may reword within that width.)*

- [ ] **Step 4: Reskin the README intro + controls.**

In `README.md`, replace the H1 and opening paragraph:
```markdown
# Military RTS + Tower Defense

A military real-time strategy game fused with tower defense and DOTA-style lane
pressure: build a base and economy, defend with units and static towers, and push
the lanes to destroy the enemy base. Single-player vs AI, architected so PvP can be
added later.
```
with:
```markdown
# Stellar Front — Space RTS + Tower Defense

A space real-time strategy game fused with tower defense and DOTA-style lane
pressure: defend Earth against an alien invasion — build a base and economy,
hold the lanes with units and static towers, and push to destroy the alien Core
Node. Single-player vs AI, architected so PvP can be added later. (The campaign
techs up across four eras; this is the Era-1 / modern slice.)
```
and replace the Controls line:
```markdown
Controls: left-click select unit, right-click move, `B/P/R/G` build
(Barracks/Power/Refinery/Gun turret), `T` train infantry; tap-to-select / tap-to-move
on touch screens.
```
with:
```markdown
Controls: left-click select unit, right-click move, `B/P/R/G` build
(Hangar/Reactor/Extractor/Laser Turret), `T` train infantry; tap-to-select / tap-to-move
on touch screens.
```

- [ ] **Step 5: Build + lints.**

Run: `cargo build -p rts-render-shell` → compiles.
Run: `cargo clippy -p rts-render-shell --all-targets -- -D warnings` → clean.
Run: `cargo fmt -p rts-render-shell -- --check` → clean (else `cargo fmt -p rts-render-shell`).

- [ ] **Step 6: Commit (targeted).**

```bash
git add crates/render-shell/src/theme.rs crates/render-shell/src/main.rs README.md
git commit -m "feat(shell): toxic-green alien palette + alien-invasion title/game-over/README reskin" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Confirm `git show --stat HEAD` shows only `theme.rs`, `main.rs`, `README.md`.

---

## Task 4: Phase 1 verification gate

Verification only.

- [ ] **Step 1: Full suite + determinism.**

Run: `cargo test --workspace` → all pass.
Run: `cargo test -p rts-core golden_hash_pins_cross_target_determinism` → PASS, constant **unchanged** (proves the reskin changed nothing observable to the sim).

- [ ] **Step 2: Strict clippy + fmt + wasm.**

Run: `cargo clippy --workspace --all-targets -- -D warnings` → clean.
Run: `cargo fmt --all -- --check` → clean.
Run: `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown` → builds.

- [ ] **Step 3: Manual/visual smoke (best-effort).**

If a display is available: `cargo run --release -p rts` and confirm the title reads the new wordmarks, the map picker shows Orbital Siege / Open Front / Crater Crossroads, enemy pieces render toxic green, and selecting an alien unit shows the alien name. (Headless box: skip — all logic is covered above; note that it was skipped.)

---

## Phase 1 done — definition of done

- Scenario menu shows Orbital Siege / Open Front / Crater Crossroads with the new taglines.
- Selecting an entity shows faction-aware names (human relabels for P0, synthetic names for P1); the human command bar shows Reactor/Extractor/Hangar/Laser Turret/Flak Turret/Gunship.
- Enemy (alien) pieces render toxic green; title screen + game-over + README read as the alien-invasion slice.
- `sim.rs`/`balance.ron` untouched; **golden hash unchanged**; full workspace test/clippy/fmt/wasm green.

---

## Notes for later phases

- A `TEAM_ENEMY`→`TEAM_ALIEN` rename and deeper README/Cargo-comment dethemeing ("military RTS" mentions in code comments) are deferred cosmetic cleanups.
- The faction-aware name split here is shell-side; when Phase 2-3 add the tech tree / per-era roster, names may move to a data-driven table keyed by (kind, era, faction).
- The title-screen game name ("STELLAR FRONT") is a working placeholder pending the final name decision.
