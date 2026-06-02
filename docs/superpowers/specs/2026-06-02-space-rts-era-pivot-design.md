# Space RTS + Era Progression — Design Spec

**Date:** 2026-06-02
**Status:** Approved (brainstorming complete) — ready for implementation planning
**Working title:** *Stellar Dominion* *(placeholder — rename freely; supersedes `military-rts-td`)*
**Supersedes/extends:** [`2026-06-01-military-rts-td-design.md`](2026-06-01-military-rts-td-design.md)

## One-line pitch

"Age of Empires, in space." A single real-time RTS match where you command
humanity against an **alien invasion**: both sides start in the **Modern era**
and **tech up** through four eras (Modern → Orbital → Interplanetary →
Interstellar) via a **research tech tree**, escalating from defending Earth to
taking the war to the alien stars. The existing RPS combat, two-resource
economy, lane pressure, and **deterministic fixed-point core are extended, not
replaced** — Era 1 *is* today's game.

## Relationship to the existing game

This is a **theme + progression pivot**, not an engine rewrite. The existing
deterministic core (`crates/core`), Macroquad shell, headless server, lockstep,
AI, scenarios, and 101 tests are the foundation.

**Reused unchanged (the genre spine is theme-neutral):**

- Deterministic fixed-point core (`Fixed` Q47.16, no floats, golden-hash determinism).
- RPS damage matrix and the swarm/armor/anti-armor/air triangle.
- Two-resource economy (Credits trickle + Power), build/placement, walls/turrets.
- Lane pressure, flow-field + A* pathfinding, spatial-grid combat, slot recycling.
- Rule-based AI, AI-vs-AI playtest harness, save/replay, lockstep session core.

**Added by this pivot:**

- A **research tech tree** and per-player **era** progression (Modern→Interstellar).
- **Per-era roster tiers** — same RPS roles, upgraded in place each era; one new
  role (**Capital Ship**) unlocks at Era 4.
- A **mirrored alien faction** (identical stats, distinct names + art/palette).
- Three space-native mechanics: **energy shields**, a **third resource
  (Antimatter)**, and **anti-grav / flight expansion**.
- Space retheme of all art, strings, scenarios, and story.

## Locked decisions (from brainstorming)

| Decision | Choice | Notes |
|---|---|---|
| Pivot depth | Reskin **+ space-native content** | A real space game, not repaint |
| End-state | **RTS with era advancement only** | "AoE in space"; **no** 4X/strategic meta-layer |
| Eras | **4** — Modern → Orbital → Interplanetary → Interstellar | Era 1 = today's roster |
| Advance mechanic | **Tech-tree research** (StarCraft/Civ-style) | Research Lab; key techs gate eras, others are upgrades |
| Roster model | Same RPS roles, **upgraded in place** each era | RPS triangle identical every era; Capital Ship new at Era 4 |
| Enemy | **Symmetric tech race**; aliens **mirror** the player | Identical stats, distinct art/names; "aliens start ahead" deferred to a difficulty toggle |
| New mechanics | **Energy shields + Antimatter + anti-grav** | Sequenced **shields-first** |
| Art | **game-icons.net, placeholder-first** | Human vs alien palette + silhouettes; ~30-45 sprites |
| Story | Aliens invade in the modern era; humanity techs up across centuries to take the war to the alien stars | Earth → solar system → alien worlds expressed via map themes |

## Architecture — extending the deterministic core

Every addition must obey the existing determinism contract: **fixed-point only
(no floats; enforced by `clippy::float_arithmetic`), seeded RNG only, no
wall-clock reads, and everything that is game state enters `state_hash()`.**

### New simulation state (all hashed)

- **Per player:** `era` (the player's current era — players progress
  independently, it's a race), `researched_techs` (a fixed-capacity set/bitmask),
  `active_research: Option<(TechId, ticks_remaining: u32)>`, `antimatter: Fixed`.
- **Per entity:** `shield: Fixed`, `last_combat_tick: u32` (drives out-of-combat
  regen), `era_acquired: u8` (the era a unit's stats were last synced to, so
  upgrades apply deterministically).
- **Unit/building stats gain:** optional `ShieldStats { max: Fixed,
  regen_per_tick: Fixed, regen_delay_ticks: u32 }`, an `is_antigrav: bool` flag,
  and an Antimatter cost field.

**Hashing checklist (each must be added to `state_hash()` in the existing
iteration order):** per-player `era`, `researched_techs`, `active_research`,
`antimatter`; per-entity `shield`, `last_combat_tick`, `era_acquired`. The
**golden hash is deliberately re-pinned and committed once per phase** that
changes state, so cross-target (native/wasm/mobile) divergence is still caught.

### New tick phases in `Sim::step()`

- **`run_research()`** — decrement `active_research` timers as **`u32` tick
  counts** (never fractions/percentages). On completion: mark tech researched,
  apply its effect (advance era / unlock / stat delta).
- **`run_shields()`** (before `run_production`) — for each entity out of combat
  (`tick - last_combat_tick >= regen_delay_ticks`), regen using a **stored
  `Fixed` per-tick value** (never `regen_per_sec / 30.0`), clamped to `max`.

### Determinism rules for the new mechanics

- **Shields:** stored per-entity `Fixed`; regen per-tick is a precomputed `Fixed`
  constant; combat applies damage to shield first, overflow to HP. **Shield-
  piercing** is an `AttackProfile.piercing: bool`; piercing attacks multiply
  *shield* damage by a `Fixed::from_ratio(...)` bonus (e.g. 3/2). No floats anywhere.
- **Anti-grav:** a **per-unit flag only** — it reuses the *existing* `is_air`
  straight-line movement path and **must not alter `Map` passability** (changing
  the A* neighbour set would desync pathfinding). Distinct from `is_air` for
  *targeting*: anti-grav units ignore terrain for movement but are still hit by
  normal ground attacks (only `is_air` units are AA-only).
- **Era / upgrades:** stats are looked up as `base(kind, era, faction) +
  per-player upgrades`; living units carry `era_acquired` and are re-synced
  **deterministically** when an upgrade/era completes (retroactive, RTS-style).
- **Research timers:** `u32` ticks only.
- **RNG / tech tree:** the tech tree is **static, validated data** — no RNG draws
  during `step()`; RNG ordering is unchanged. AI research choices are a
  deterministic function of state (no RNG).

### Data model (the keystone — Phase 0)

Stats today are **duplicated**: hardcoded `const fn` in
`crates/core/src/game/stats.rs` *and* in `crates/data/balance.ron`, with a test
asserting equality. This duplication explodes at 4 eras × 2 factions, so it is
resolved **first**:

1. **Confirm the runtime source of truth** (code const vs RON) and **collapse to
   one.** Keep `UnitKind`/`BuildingKind` as pure **role identifiers**; stats move
   to a single `Balance` table.
2. Add enums `Era { Modern, Orbital, Interplanetary, Interstellar }` and
   `Faction { Human, Alien }`.
3. Re-key `Balance` by **`(Era, Faction, Kind)`** with getter methods; **validate
   at load** that every `(Era, Faction, Kind)` triple has a complete entry
   (fail loudly — data-driven lookups otherwise panic in production).
4. Keep the core **`no_std`-friendly**: fixed-capacity arrays / `heapless` maps
   sized to the final tech/roster count, **not** `std::HashMap`.
5. **Display names are data-driven** so aliens read as alien (e.g. swarm role:
   "Marine" vs "Swarmling") without code changes.

The tech tree itself: **`TechEffect` enum in code** (`UnlocksEra`, `UnlocksUnit`,
`UpgradeStats`, …), with **nodes/prereqs/costs in data**, validated at load (no
cycles, all prereqs exist, every era reachable).

## The four eras & roster

Era 1 is the existing game. Each later era is a stronger incarnation of the same
RPS roles; advancing **upgrades your units in place** and unlocks the new
look/stats. The **RPS triangle is identical in every era** (balance stays
legible). Names below are illustrative placeholders.

| Role (UnitKind) | E1 Modern | E2 Orbital | E3 Interplanetary | E4 Interstellar |
|---|---|---|---|---|
| Swarm (`Infantry`) | Infantry | Drone Trooper | Laser Trooper | Plasma Trooper |
| Armor (`Tank`) | Tank | Hovertank | Siege Walker | Battle Mech |
| Anti-armor (`AntiArmor`) | AT Team | Railgunner | Lance Trooper | Beam Lancer |
| Air (`Helicopter`) | Helicopter | Gunship | Interceptor | Starfighter |
| **Capital (`Capital`, new)** | — | — | — | **Capital Ship** |

> Whether the role enum variants are renamed from `Infantry/Tank/...` to neutral
> role names (`Swarm/Armor/...`) is a Phase-0 cleanup choice; identity = role,
> display name = data.

**Setting / story journey** (expressed via map themes & scenario flavor, not a
separate map layer): Era 1 defend Earth → Era 2 Moon/Mars orbit → Era 3 colonize
the solar system → Era 4 assault the alien worlds. Aliens are the headline enemy
of Era 4 and the war you tech up to win.

## Tech tree

- **Shape:** a **linear era spine** (3 "key" techs — *Reach Orbital*, *Reach
  Interplanetary*, *Reach Interstellar* — each gating the next era) **plus optional
  side branches**: Shields I/II, Antimatter Extraction, Anti-grav Drives, and
  generic weapon/armor/economy upgrades.
- **Gating policy:** era-key techs and the Capital Ship are **hard gates** (you
  truly cannot field them early); stat/shield/economy/anti-grav techs are **soft**
  — researching them never blocks army production (avoids economy soft-locks).
- **Advancement:** **automatic** — researching an era's key tech advances that
  player to the new era (no separate "declare era" action).
- **Mechanic:** build a **Research Lab** (consumes power), issue
  `Command::Research { owner, tech_id }`, pay credits (+ antimatter for late
  techs), wait `u32` ticks. One active research per player (queue is a later
  nicety).

## Energy shields (Phase 4 — first new mechanic)

- Regenerating shield layer on top of HP; **out-of-combat regen only**
  (`tick - last_combat_tick >= regen_delay_ticks`), per-tick `Fixed`, clamped to
  `max`. Unlocked/upgraded via research, kicking in ~Era 2.
- Damage hits shield first, overflow to HP. **Shield-piercing** weapons get a
  `Fixed` bonus multiplier vs shields (the counter-play).
- UI: a thin cyan bar above the existing health bar.

## Antimatter — third resource (Phase 5)

- A **passive trickle from a dedicated building** (mirrors the Refinery/Credits
  model; needs power). Stored per player as `Fixed`, hashed.
- Required (with Credits) for **top-tier units and the Capital Ship**, giving the
  late game a second economic lever.
- UI: third entry in the top resource bar (abbreviate / shrink-test at 800 /
  1024 / 1440 px so mobile doesn't overflow). Contested resource *nodes* are an
  explicit later option, not v1.

## Anti-grav / flight expansion (Phase 6 — last, highest path risk)

- A per-unit `is_antigrav` flag granted to some late-era ground units; they ignore
  terrain/obstacles for movement (reusing `is_air` straight-line movement) but
  remain normal ground targets.
- **Never modifies map passability.** Cross-platform path determinism tests
  required before ship.

## Enemy & AI model

- **Symmetric tech race:** the AI (alien faction) also starts Modern and techs up
  the same ladder. Aliens **mechanically mirror** the player's roster/stats
  (proven balance + AI carry over); only names/art/palette differ. **Aliens stats
  are identical for v1** — asymmetric "aliens start ahead" is a deferred difficulty
  toggle.
- **AI extension** (lowest-risk lens, ~L): `ai_commands()` gains deterministic
  research decisions and era-advance triggers. Rules:
  - Tech priorities are **fixed heuristics** (no RNG) — e.g. shields before
    advancing to Era 2.
  - Era-advance triggers are **symmetric conditions on state alone**, identical
    for both players.
  - **Anti-stall fallback:** if not advanced by a tunable tick threshold,
    auto-advance, so the AI never gets stuck in Era 1 and new content always gets
    exercised.
  - The **playtest harness** is extended to report per-era stats (ticks-to-Era-2,
    tech adoption, win split) and must stay ~50/50 on symmetric maps.

## Art strategy

- Keep the **game-icons.net** pipeline (CC-BY, already credited). **Placeholder-
  first:** build all gameplay against quick geometric/era-tinted placeholders so
  nothing is art-blocked, then swap in chosen icons.
- **Faction = palette + silhouette:** human palette vs alien palette (Era-1 alien
  = a desaturated purple/magenta via draw-time tint); custom alien sprite art
  deferred. `sprites.rs` is refactored to key by **`(Kind, Era, Faction)`** before
  Era 2 (Era 1 aliases to existing sprites so it isn't blocked).

## UI / shell changes

- **Command bar** → tabs or 2-row carousel (Build / Train / Tech) to fit 11+
  buttons without overflow.
- **Research panel** → Phase-2 placeholder modal (key techs as locked/unlocked
  buttons); full tech-tree graph UI is a later phase.
- **Era indicator** → badge (roman numeral I–IV + era color) near the minimap.
- **Shield bars** (cyan) above health bars; **third resource** in the top bar
  (layout-tested for mobile).
- New build buttons: Research Lab, Antimatter plant, Capital-Ship yard;
  `(Kind, Era, Faction)` sprite swapping.

## Build plan (phased; each phase independently testable)

| Phase | Delivers | Effort |
|---|---|---|
| **0 — Data foundation** | Single source of truth for stats; `Era`+`Faction` enums; `Balance` keyed by `(Era,Faction,Kind)`; load-time validation. Eras 2-4 = placeholder copies of Era 1; Alien = identical to Human. All tests green; golden hashes regenerated & committed. | Med |
| **1 — Space reskin, Era-1 slice (shippable)** | Full space retheme (strings, scenarios, README, story); human-vs-alien factions with palette tint + data-driven names; placeholder-first game-icons art. A complete, playable "humans vs alien invaders" Modern-era game. | Low |
| **2 — Tech-tree research** | `Research Lab`, `Command::Research`, `run_research()` tick phase, validated tech-tree data, AI research (deterministic, symmetric, anti-stall), placeholder research modal. | Med |
| **3 — Era advancement + per-era roster** | Era-gating key techs; per-era stat tiers + new unit incarnations (deterministic in-place upgrades via `era_acquired`); Capital Ship at Era 4; era badge, command-bar tabs, `(Kind,Era,Faction)` sprites. | High |
| **4 — Energy shields** | `shield`/`last_combat_tick`, `run_shields()` regen, piercing damage, research-gated ~Era 2, cyan shield bars, cross-platform regen tests. | Med |
| **5 — Antimatter (3rd resource)** | Antimatter + producer building (passive trickle), top-tier/Capital-Ship costs, economy + AI + top-bar UI. | Low |
| **6 — Anti-grav / flight** | Per-unit `is_antigrav` flag (reuses `is_air` movement), late-era ground units, path determinism tests. | Med |

**Critical path:** Phase 0 (data model) gates everything; Phase 1 is shippable on
its own. Rough estimate: **~8-12 weeks** for all phases.

## Risks & mitigations (from the 5-lens code review)

| Risk | Mitigation |
|---|---|
| Float temptation (shield regen, piercing %) | Store as `Fixed`/`Fixed::from_ratio`; `clippy::float_arithmetic` enforces it |
| Silent desync (new state not hashed) | Hashing checklist (shield, era, era_acquired, antimatter, research) added to `state_hash()`; re-pin golden hash per phase |
| Anti-grav breaks A* determinism | Never touches passability; per-unit straight-line flag only |
| Per-era upgrades to live units non-deterministic | `era_acquired` per entity; retroactive sync is a pure function of state |
| AI never techs up (content unexercised) | Deterministic heuristics + tick-based fallback + playtest per-era reporting (~50/50 split) |
| Economy soft-locks from hard tech gates | Era-keys + Capital Ship are hard gates; everything else is soft |
| Data duplication explodes at 4×2 | Phase 0 collapses to one source of truth, keyed by `(Era,Faction,Kind)`, validated at load |
| Command bar / top bar overflow | Tabs/carousel; abbreviate & layout-test the 3rd resource at 800/1024/1440 px |
| `no_std` lost to complex tech tree | Fixed-capacity arrays / `heapless`, not `std::HashMap` |

## Baked-in decisions (resolved defaults)

1. **Per-player era** (it's a race; players can be in different eras).
2. **Tech tree = linear era spine + optional side branches.**
3. **Upgrades apply retroactively** to living units, deterministically.
4. **Era advance is automatic** on key-tech completion.
5. **Antimatter = passive trickle from a building** (contested nodes = later option).
6. **Shields regen out-of-combat only.**
7. **Phase 1 ships as a real milestone** before eras 2-4.
8. **Alien stats are identical to human for v1** (cosmetic mirror only).

## Testing strategy

- **TDD on the core** for every new system (research timers, shield regen,
  piercing, era upgrades, antimatter economy, anti-grav movement).
- **Determinism:** re-pin and commit the golden state hash each state-changing
  phase; native-vs-wasm hash equality stays in CI.
- **AI-vs-AI playtest** each phase (win split + per-era stats); symmetric maps
  must stay ~50/50.
- **Load-time validation tests:** every `(Era, Faction, Kind)` triple complete;
  tech tree acyclic with valid prereqs.
- Shell/UI: light manual testing; all logic covered headlessly.

## Out of scope (explicitly)

- The 4X / strategic galaxy meta-layer (colonies, diplomacy, turn-based map) —
  explicitly **not** this project.
- Asymmetric "aliens start ahead" (deferred difficulty toggle).
- Contested Antimatter map nodes (v1 uses passive production).
- Custom hand-drawn alien sprite art (placeholder-first; later art pass).
- 3D rendering, networked PvP deployment infra, mobile store submission,
  campaign/story authoring beyond map flavor, ML AI.

## Open questions (minor; resolvable during planning)

- Final game name, era color palette, and alien faction identity/names.
- Exact tech costs/timers and per-era stat multipliers (tuned via playtest).
- Whether to rename `UnitKind` variants to neutral role names in Phase 0.
- Research queue (single active research v1; queue later?).
- Which specific late-era units gain anti-grav.

## References

- Original design: [`2026-06-01-military-rts-td-design.md`](2026-06-01-military-rts-td-design.md);
  netcode: [`../../NETCODE.md`](../../NETCODE.md); roadmap: [`../../../NEXT_STEPS.md`](../../../NEXT_STEPS.md).
- 5-lens adversarial code review (2026-06-02): determinism & core sim, AI
  extension, data model & content, render shell & UI, scope & sequencing — run
  against the live codebase; findings folded into the architecture, risks, and
  phase plan above.
