# Phase 3 — Era Advancement + Per-Era Roster — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** Players advance through 4 eras (Modern→Orbital→Interplanetary→Interstellar) by researching **era-key techs**; each era multiplies attack damage ×1.4, so combat escalates. Add the **Capital Ship** (Era-4 unit), and surface eras in the AI and UI.

**Architecture:** Per-player `era: u8` in `Sim` (hashed), starting Modern, advanced when an era-key tech completes in `run_research`. **Per-era damage is applied at combat time**, not in the data: `run_combat` multiplies an attacker's base (type-multiplied) damage by a per-player `(7/5)^era` factor (a runtime `Fixed` multiply, mirroring the existing weapon-bonus precompute) — so no `Balance`/`const_default` changes and no const-multiply problem. The `(era,faction)`-keyed `Balance` from Phase 0 is left intact (reserved for richer per-era data later). Capital Ship is a new `UnitKind`, gated to Era 4 at train time. Golden hash re-pinned twice (era enters the hash; AI advances eras).

**Tech Stack:** `rts-core` (no_std, fixed-point, `deny(clippy::float_arithmetic)`, golden-hash determinism), `rts-data`, `rts-render-shell`.

**Spec:** [`../specs/2026-06-02-space-rts-era-pivot-design.md`](../specs/2026-06-02-space-rts-era-pivot-design.md) — Phase 3. (Phases 0–2 merged.)

**Before you start:**
- Branch: `git checkout -b feat/phase3-eras` (from `feat/core-foundation`). Tree is clean.
- Stage only each task's files; never `git add -A`. Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Determinism:** era math is fixed-point/integer; era enters `state_hash`. The golden hash (currently `18_112_695_847_899_389_504`) is re-pinned in **T1** (era added to hash, zero-valued in the golden run) and **T4** (AI advances eras). Re-pin = run the test, read the actual hash from the failure, paste it in, re-run. NEVER re-pin in a task not marked for it.
- **Locked decisions:** only attack DAMAGE scales per era; factor `(7/5)^era`; applied at combat time using the attacker's CURRENT era (retroactive); aliens stat-mirrored; Capital Ship trainable only at Era 4.

---

## Task 1: Per-player era + era-key techs + advance + hash (re-pin #1)

**Files:** `crates/core/src/game/tech.rs`, `crates/core/src/game/sim.rs`.

- [ ] **Step 1 (tech.rs): era-key techs.** Add `Era` to `TechBranch` (`/// Advances the player to the next era. Era,`). Bump `TECH_COUNT` 10→13. Append to `TECHS`:
```rust
    TechDef { id: 10, name: "Reach Orbital", branch: TechBranch::Era, cost: Fixed::from_int(500), duration: 600, prereq: None, bonus: Fixed::ZERO },
    TechDef { id: 11, name: "Reach Interplanetary", branch: TechBranch::Era, cost: Fixed::from_int(800), duration: 800, prereq: Some(10), bonus: Fixed::ZERO },
    TechDef { id: 12, name: "Reach Interstellar", branch: TechBranch::Era, cost: Fixed::from_int(1200), duration: 1000, prereq: Some(11), bonus: Fixed::ZERO },
```
Add:
```rust
/// Whether a tech id is an era-key (researching it advances the player's era).
#[must_use]
pub const fn is_era_key(id: u32) -> bool {
    matches!(tech(id), Some(t) if matches!(t.branch, TechBranch::Era))
}
```
The existing `const _: () = assert!(TECHS[TECH_COUNT - 1].id as usize == TECH_COUNT - 1);` stays valid. Add a test: `is_era_key(10) && is_era_key(12) && !is_era_key(0)`, and the three Era techs chain by prereq (11→10, 12→11).

- [ ] **Step 2 (sim.rs): failing test.**
```rust
    #[test]
    fn researching_an_era_key_tech_advances_the_era() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(10_000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P0, BuildingKind::PowerPlant, 6, 20);
        s.add_building(P0, BuildingKind::ResearchLab, 7, 20);
        assert_eq!(s.player_era(P0), 0);
        s.step(&[Command::Research { owner: P0, tech_id: 10 }]);
        let dur = crate::game::tech::tech(10).unwrap().duration;
        for _ in 0..dur { s.step(&[]); }
        assert_eq!(s.player_era(P0), 1, "advanced to Orbital");
    }
```

- [ ] **Step 3: run → compile failure** (`player_era` missing). `cargo test -p rts-core researching_an_era_key`.

- [ ] **Step 4 (sim.rs):** add `era: u8` to `Player` (after `active_research`, doc `/// Current era index (0=Modern..3=Interstellar).`); init `era: 0` in `Sim::new`.

- [ ] **Step 5 (sim.rs): hash it.** In `state_hash`'s per-player loop, after the `active_research` match, add `h.write_u64(u64::from(p.era));`.

- [ ] **Step 6 (sim.rs): advance on completion.** In `run_research`, immediately after `player.researched_techs |= 1u32 << id;` (and `player.active_research = None;`), add:
```rust
                    if crate::game::tech::is_era_key(id) {
                        player.era = (player.era + 1).min(3);
                    }
```

- [ ] **Step 7 (sim.rs): accessor.** `pub fn player_era(&self, player: PlayerId) -> u8 { self.players[usize::from(player.0)].era }`.

- [ ] **Step 8: verify + RE-PIN #1.** `cargo test -p rts-core researching_an_era_key is_era_key research_completes` → PASS. `golden_hash_pins_cross_target_determinism` → **FAILS** (era now hashed); re-pin to the new value. `cargo test --workspace`; clippy; fmt. Commit (tech.rs, sim.rs):
```
feat(core): per-player era + era-key techs + advance on research (re-pin golden #1)
```

---

## Task 2: Per-era attack damage applied at combat time (hash-preserving)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.**
```rust
    #[test]
    fn era_damage_factor_scales_up() {
        assert_eq!(super::era_damage_factor(0), Fixed::ONE);
        assert!(super::era_damage_factor(1) > Fixed::ONE);
        assert!(super::era_damage_factor(3) > super::era_damage_factor(2));
        assert!(super::era_damage_factor(2) > super::era_damage_factor(1));
    }
```

- [ ] **Step 2: run → compile failure** (`era_damage_factor` missing).

- [ ] **Step 3 (sim.rs): the factor fn.** Add a module-level fn near the other combat helpers:
```rust
/// Per-era attack-damage multiplier: (7/5)^era. Era 0 (Modern) is neutral.
fn era_damage_factor(era: u8) -> Fixed {
    match era {
        0 => Fixed::ONE,
        1 => Fixed::from_ratio(7, 5),
        2 => Fixed::from_ratio(49, 25),
        _ => Fixed::from_ratio(343, 125),
    }
}
```

- [ ] **Step 4 (sim.rs): apply it in `run_combat`.** `run_combat` already precomputes per-player `weapon` and `armor` `[Fixed; PLAYER_COUNT]` arrays before the attack loop. Add a third:
```rust
        let era_dmg: [Fixed; PLAYER_COUNT] =
            core::array::from_fn(|p| era_damage_factor(self.players[p].era));
```
Where damage is pushed (currently `damage.push((j, profile.damage * mult + weapon[usize::from(e.owner.0)]));`), scale the base by the attacker's era factor (weapon bonus stays a flat add on top):
```rust
                let base = profile.damage * mult * era_dmg[usize::from(e.owner.0)];
                damage.push((j, base + weapon[usize::from(e.owner.0)]));
```

- [ ] **Step 5: verify.** `cargo test -p rts-core era_damage_factor_scales_up` → PASS. `golden_hash_pins_cross_target_determinism` → **PASS, UNCHANGED** (every player is era 0 in the golden run until T4, so factor == 1 → bit-identical). `cargo test --workspace`; clippy; fmt. Commit (sim.rs):
```
feat(core): scale attack damage by attacker era (7/5)^era at combat time (hash-preserving)
```

---

## Task 3: Capital Ship `UnitKind` (Era-4 unit)

**Files:** `stats.rs`, `balance.rs`, `crates/data/src/lib.rs`, `crates/data/balance.ron`, `sim.rs`, render-shell `ui.rs` + `sprites.rs`.

- [ ] **Step 1: failing test (balance.rs).**
```rust
    #[test]
    fn capital_ship_is_a_heavy_unit() {
        use crate::game::stats::UnitKind;
        let cap = UnitKind::Capital.stats();
        let tank = UnitKind::Tank.stats();
        assert!(cap.max_hp > tank.max_hp);
        assert!(cap.attack.damage > tank.attack.damage);
    }
```
Extend the test `UNIT_KINDS` const to `[UnitKind; 5]` adding `UnitKind::Capital`.

- [ ] **Step 2: run → compile failure** (no variant `Capital`).

- [ ] **Step 3 (stats.rs):** add `Capital` to `UnitKind` (after `Helicopter`, doc `/// Era-4 capital ship: massive HP and damage.`). Add to `UnitKind::stats()`:
```rust
            Self::Capital => UnitStats {
                max_hp: Fixed::from_int(600),
                armor: ArmorType::Plated,
                attack: AttackProfile::ground(
                    Fixed::from_int(40), DamageType::Explosive, Fixed::from_int(6), 18,
                ),
                speed: Fixed::from_ratio(8, 100),
                cost: Fixed::from_int(500),
                build_time: 200,
                is_air: false,
            },
```

- [ ] **Step 4 (balance.rs):** the units inner array `[UnitStats; 4]` → `5` everywhere (struct field `units: [[[UnitStats; 4]; FACTION_COUNT]; ERA_COUNT]` → `5`; `from_tables(units: [UnitStats; 4], ...)` → `5`; `const_default()` units list adds `UnitKind::Capital.stats()` as the 5th; `unit_in()` adds `UnitKind::Capital => tier[4]`).

- [ ] **Step 5 (rts-data):** `BalanceData` add `capital: UnitData` (after `helicopter`); `load()` units array add `to_unit(&data.capital)` 5th. `balance.ron`: add `capital` entry (max_hp 600, armor Plated, attack (damage 40, damage_type Explosive, range 6, period 18), speed_milli 80, cost 500, build_time 200).

- [ ] **Step 6 (sim.rs):** `unit_tag` match add `UnitKind::Capital => 5`. Era-4 gate in `apply_command`'s `Command::Train` arm — at the top of that arm add: `if matches!(kind, UnitKind::Capital) && self.players[usize::from(owner.0)].era < 3 { return; }`.

- [ ] **Step 7 (render-shell exhaustive matches):** `ui.rs` `human_name_role`: `EntityKindView::Unit(UnitKind::Capital) => ("Capital Ship", "Era-4 heavy warship"),`; `alien_name_role`: `EntityKindView::Unit(UnitKind::Capital) => ("Leviathan", "Era-4 alien warship"),`. `sprites.rs`: add a `UnitKind::Capital` arm reusing the tank sprite (merge-arm if clippy `match_same_arms` requires). `cargo build --workspace` and fix any other flagged `UnitKind` match.

- [ ] **Step 8: verify + commit.** `cargo test -p rts-core capital_ship_is_a_heavy_unit` → PASS; `golden_hash_pins_cross_target_determinism` → **UNCHANGED** (no Capital in the golden run); `cargo test --workspace`; `cargo test -p rts-data`; clippy; fmt. Commit (the 7 files):
```
feat(core): add Capital Ship unit (Era-4-gated; behavior-preserving)
```

---

## Task 4: AI advances eras + builds Capital Ships (re-pin #2)

**Files:** `crates/core/src/game/sim.rs`.

- [ ] **Step 1: failing test.**
```rust
    #[test]
    fn ai_advances_at_least_one_era() {
        let mut s = Sim::new(Map::new(40, 40), 7, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        let mut max_era = 0u8;
        for _ in 0..6000 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            max_era = max_era.max(s.player_era(P0));
        }
        assert!(max_era >= 1, "AI advanced at least one era");
    }
```

- [ ] **Step 2: run → FAIL** (AI never researches era-key techs).

- [ ] **Step 3 (sim.rs): era-keys in the AI priority.** Change `RESEARCH_PRIORITY` from `[u32; 10] = [6, 0, 3, 7, 1, 4, 8, 2, 5, 9]` to `[u32; 13] = [6, 0, 3, 10, 7, 1, 4, 11, 8, 2, 5, 12, 9]` (era-keys interleaved after the cheap early upgrades). The existing eligibility loop (prereq + affordability + anti-stall) handles the rest.

- [ ] **Step 4 (sim.rs): AI trains Capital at Era 4.** In the AI training block (trains Infantry from an idle barracks), pick Capital when in Era 4 and affordable:
```rust
                let kind = if self.player_era(player) >= 3
                    && credits >= self.balance.unit(UnitKind::Capital).cost
                { UnitKind::Capital } else { UnitKind::Infantry };
```
and use `kind` in the `Command::Train`. (The affordability check for the chosen kind should use that kind's cost.)

- [ ] **Step 5: verify + RE-PIN #2 + reconcile.** `cargo test -p rts-core ai_advances_at_least_one_era` → PASS. `golden_hash_pins_cross_target_determinism` → **FAILS** (AI research priority changed → different run). Re-pin. `cargo test --workspace`: update any AI-behavior test whose counts legitimately shifted (document why; never loosen determinism/equality assertions). `cargo run --release -p rts-server -- playtest` → report (balance tunable, not a blocker). clippy; fmt. Commit (sim.rs):
```
feat(core): AI researches era-keys + trains Capital Ships at Era 4 (re-pin golden #2)
```

---

## Task 5: UI — era indicator + Capital Ship button (shell-only)

**Files:** `crates/render-shell/src/{ui,input,main}.rs`.

- [ ] **Step 1: era indicator.** In `ui.rs`'s top resource-bar draw fn, add a small label for the human era: `const ERAS: [&str; 4] = ["Modern", "Orbital", "Interplanetary", "Interstellar"]; let era = ERAS[(sim.player_era(HUMAN) as usize).min(3)];` and draw it near the credits/power/units readout (placement at discretion, follow the bar layout).
- [ ] **Step 2: Capital train button.** In `ui.rs` `layout()`, add `mk(8, "Capital", 'C', Action::Train(UnitKind::Capital))` (`[Button; 8]` → `[Button; 9]`). In `input.rs` add a `KeyCode::C` train hotkey mirroring `T`/`H` (issues `Command::Train` for Capital, or arms it through the existing train path — match how `T`/`H` work). The core rejects Capital trains before Era 4, so leaving the button always clickable is safe (optionally dim it when `sim.player_era(HUMAN) < 3`).
- [ ] **Step 3: build + lint.** `cargo build -p rts-render-shell`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo test -p rts-core golden_hash_pins_cross_target_determinism` (PASS — no core change). Commit (shell files):
```
feat(shell): era indicator + Capital Ship train button
```

---

## Task 6: Verify + finish

- [ ] `cargo test --workspace`; `golden_hash_pins_cross_target_determinism`; `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --all -- --check`; `cargo build -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`; `cargo run --release -p rts-server -- playtest`.
- [ ] Final holistic review; fast-forward merge into `feat/core-foundation`.

## Definition of done
- Per-player era (hashed), advanced by researching era-key techs; combat damage scales ×1.4/era by the attacker's current era (retroactive, combat-time).
- Capital Ship buildable only at Era 4 (human via button, AI in Era 4).
- AI advances eras + fields Capital Ships; AI-vs-AI deterministic (golden re-pinned); era indicator in HUD; full workspace test/clippy/fmt/wasm green.

## Notes / deferred
- Per-era unit NAME/sprite variants are deferred (era surfaced via the HUD indicator; Capital reuses the tank sprite placeholder).
- Only attack damage scales per era (hp/speed/economy/cost era-invariant). The `(era,faction)` Balance infra is intact for richer per-era data later.
- Era-key tech costs/durations, Capital stats, and the `(7/5)^era` factor are first-pass; tune via playtest.
