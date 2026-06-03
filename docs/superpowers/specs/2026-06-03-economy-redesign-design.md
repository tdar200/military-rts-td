# Stellar Front — Economy & Pacing Redesign ("Hold the Line")

**Date:** 2026-06-03
**Status:** Design approved (pending spec review)

## Context

The overhaul (M1–M7: holographic theme, juice, audio, fog of war, veterancy,
supply cap, tech forks, survival mode, perks) made the game *look and feel* great
but left the **core gameplay** unchanged, and the user identified that it plays
wrong:

1. **No time to build** — waves arrive almost immediately; you never get to
   establish a base.
2. **No resources to mine** — the economy is a passive Refinery trickle; there is
   nothing on the map to gather, claim, or fight over.
3. **Most buildings do nothing** — buildings lack distinct, meaningful roles.

The user wants the game **closer to Civilization**: a real *civilization-building*
feel — expand, gather map resources, grow an economy, then weather conflict —
rather than a frantic wave rush.

**Decided direction (via brainstorming):**

- **Structure:** Real-time, **economy-first** (keep the RTS engine + all the new
  visuals/juice; re-pace it).
- **Resource model:** **Claim deposits with Extractors** (build an Extractor *on*
  a map deposit to mine it).
- **Opposition & pace:** **Slow-escalating alien waves** with a long peaceful
  build-up (keeps the alien-invasion lore; tower-defense-style economy builder).
- **Resources:** **Multi-resource (Civ-style)** — Minerals, Energy, Research,
  Alloys.
- **Deposits:** **Finite (deplete)** — forces continual expansion to fresh
  deposits.
- **Grace period:** **~3 minutes** of peace before the first wave.

**Cardinal constraint (unchanged):** all gameplay logic stays in the deterministic
`crates/core` — fixed-point, `no_std`, no I/O. Every new sim field is hashed into
`Sim::state_hash`, the golden hash is re-pinned, and the `rts-server` re-simulation
+ lockstep checks must pass (zero client/server drift).

## Core loop

```
Scout → expand to ore deposits → build Extractors to mine (finite) →
grow base & economy → research up (Research-funded) → build defenses →
survive escalating alien waves → push out for new deposits + alloys →
tech to the endgame.
```

The opening **~3 minutes are peaceful** — no enemies — so the player establishes
a civilization before the invasion tests it. Because deposits deplete, the
economy keeps the player *moving outward* across the match.

## Economy — four resources

| Resource | Source | Spent on | Notes |
|---|---|---|---|
| **Minerals** | Extractor on an **ore deposit** (mines a finite amount, then the deposit is exhausted) | buildings, units, walls | the main build currency (replaces "credits") |
| **Energy** | Reactor | building **upkeep** | over-budget throttles output via the existing power gradient (replaces "power") |
| **Research** | Research Lab (per tick, while powered) | the tech tree (tech now costs Research, not credits) | finally makes Labs worth building |
| **Alloys** | Extractor on a rare **alloy deposit** (also finite) | advanced/Era-4 units (Capital ships) + top-tier tech | replaces "antimatter" |

**Deposits** are a new map concept: a tile carries a deposit with a `kind` (Ore or
Alloy) and a finite `remaining` amount. An Extractor placed on a deposit tile
mines `rate`/tick from it into the owner's resource pool until `remaining` hits 0,
at which point the deposit is exhausted (the Extractor still stands but yields
nothing — a prompt to relocate/expand). Deposits are claim-and-defend: only an
Extractor *standing on* the tile mines it.

## Buildings — each gets a real job

| Building | Role |
|---|---|
| Command Nexus (CommandCenter) | base; lose it = lose; provides supply + a small Energy trickle |
| **Extractor** | mines the **deposit it is built on** (Ore → Minerals, Alloy → Alloys); useless off a deposit |
| **Reactor** (PowerPlant) | produces Energy (the upkeep budget) |
| **Research Lab** | produces Research (funds/advances tech) |
| **Hangar/Barracks** | trains units (Minerals + Energy upkeep; advanced units also cost Alloys) |
| **Laser / Flak Turret** | defense; Energy upkeep |
| **Barrier (Wall)** | cheap blocker for shaping lanes |
| **Alloy Refinery** (was Antimatter Plant) | an Extractor variant for alloy deposits (or fold into Extractor keyed by deposit kind — see open question) |

This resolves "buildings do nothing": Extractors require deposits, Reactors gate
upkeep, Labs drive tech, production costs are multi-resource.

## Pacing

- **Peaceful grace period:** ~3 minutes (≈ 5400 ticks at 30 Hz) before wave 1.
- **Gentle escalation:** smaller starting waves and slower growth than the current
  survival numbers; keep the Capital-ship "boss" cadence (every 5th wave) for late
  drama. The existing wave director + countdown HUD + incoming alarm telegraph it.
- Applies to **survival** (the primary re-paced mode). Skirmish maps keep their
  existing wave configs but adopt the deposit economy.

## Map

Procgen (`procgen.rs`) and the three hand-built scenarios scatter, alongside the
wreck obstacles:
- **Ore deposits** — common; some near the base frontier, more out in the field.
- **Alloy deposits** — rare; placed in contested/farther tiles so expanding for
  them carries risk.

Procgen guarantees the player's start area has ≥1 reachable ore deposit so the
opening is never stillborn, and keeps the connectivity guarantee.

## Tech

Tech costs **Research** (a pool accumulated from Labs) instead of credits. The
existing tech tree, eras, doctrine fork, and research modal stay; only the cost
currency changes. (Era/Alloy-gated advanced techs may also cost Alloys.)

## What carries over unchanged

Holographic theme, juice (interpolation/particles/shake/hit-stop/popups), audio,
fog of war, supply cap, power gradient, veterancy, focus-fire targeting, tech
doctrine fork, survival perks, and meta best-score — all unaffected; they layer on
top of the new economy.

## Deterministic-core impact (and how it's verified)

New/changed **hashed** sim state:
- Per-tile (or per-deposit-entity) `deposit { kind, remaining }` → must be added to
  `state_hash` (the `Map` is not currently hashed; deposits will be hashed
  explicitly, plus a direct map/deposit-equality test).
- Per-player resources expand from credits/power/antimatter to
  Minerals/Energy/Research/Alloys (rename + add Research as a stored pool).
- Wave director timing constants change (re-paced).

Every implementation phase ends with: `cargo fmt`/strict clippy, `cargo test
--workspace`, **golden hash re-pin**, `cargo run -p rts-server` zero-drift MATCH,
and native + wasm builds.

## Decisions captured

- Real-time, economy-first · claim-deposits-with-Extractors · slow alien waves ·
  4 resources (Minerals/Energy/Research/Alloys) · **finite depleting** deposits ·
  **~3 min** grace period.

## Open questions (to resolve during planning)

1. **Alloy extraction:** a separate "Alloy Refinery" building, or one Extractor
   whose output is keyed by the deposit kind it sits on? (Leaning: one Extractor,
   simpler.)
2. **Research as upkeep vs pool:** tech pays a one-time Research cost from a pool
   (simpler) vs research progresses only while Lab Research income flows. (Leaning:
   pool + one-time cost.)
3. **Starting resources / first build order:** exact starting Minerals and the
   minimum guaranteed near-base ore so the 3-minute opening is smooth.
4. **Skirmish vs survival:** how much the AI-vs-AI skirmish adopts deposit mining
   (the AI must be taught to claim deposits) vs survival being the showcase mode.
