# Military RTS + Tower Defense — Design Spec

**Date:** 2026-06-01
**Status:** Approved (brainstorming complete) — ready for implementation planning
**Working title:** *(TBD — placeholder project name: `military-rts-td`)*

## One-line pitch

A military real-time strategy game fused with tower defense and DOTA-style lane
pressure: build a base and economy, defend it with units and static towers, and
push the lanes to destroy the enemy base. Single-player vs AI first, architected
so PvP can be added later.

## Goals & constraints

- **Goal:** A polished, shippable/sellable game. Long road accepted.
- **Audience hook ("the game that doesn't quit"):** replayability from the
  attack/defend tension and varied skirmish matches.
- **Engine:** Godot 4 with C#. Free (no royalties), strong 2D tooling. Unity (C#)
  is an acceptable alternative; the architecture is engine-agnostic by design.
- **Perspective:** 2D / 2.5D top-down (Path A). 3D explicitly deferred — the sim
  core could drive a 3D renderer later if the game succeeds.
- **Mode:** Single-player & co-op *vs AI* is the target; **single-player ships
  first**, co-op deferred, PvP deferred (but architecturally enabled).

## Core decisions (locked during brainstorming)

| Decision | Choice | Notes |
|---|---|---|
| Genre | Pure RTS + tower defense + lane pressure | No hero/commander unit |
| Win condition | Destroy enemy Command Center | Lose if yours falls |
| Match loop | Attack & defend hybrid (two-way pressure) | Split resources/attention |
| Setting | Modern / near-future military | Infantry, armor, anti-armor, air |
| Opponent | AI first; PvP later | AI is just another input source |
| Replayability | Skirmish + AI core first, campaign later | Engine is the valuable part |
| Resource gathering | Passive trickle (no harvester micro) in v1 | Simpler, still strategic |
| Co-op | Deferred until after single-player MVP | Sim supports it; networking is real work |

## Architecture — the simulation / render split

The single most important architectural decision. The game is two layers:

### Simulation layer (deterministic, headless)

- Pure C#, **no Godot/engine dependencies**, **no rendering**.
- Advances the world in discrete **fixed-timestep ticks**.
- Holds all game state: units, buildings, towers, resources, projectiles, AI.
- **Determinism rules (hard requirements):**
  - No floating-point from engine physics; use fixed-point or carefully
    controlled integer/deterministic math for all sim quantities.
  - No `System.Random` — only a **seeded, deterministic RNG** owned by the sim.
  - No reading wall-clock time or frame time inside the sim.
  - Same starting state + same ordered input stream ⇒ **identical** end state.
- Player and AI both feed the sim via **queued, ordered commands** (build here,
  move these units, set rally, etc.).

### Render layer (Godot)

- Godot scenes/sprites read sim state each frame and draw it, with
  **interpolation** between ticks for visual smoothness.
- Captures player input and translates it into sim commands.
- Owns nothing authoritative — purely a view + input shell.

### Why this split

- The sim is **fully headless-testable** (thousands of battles in unit tests, no
  window).
- AI, balance, tower/lane logic live in clean, isolated, testable code.
- **Lockstep PvP later** becomes "synchronize input streams across clients"
  rather than "rewrite the game."

## The match

- **Map:** a tile grid. Player base on one side, enemy base on the other,
  connected by **2–3 lanes** (chokepoints/paths) plus open flanking terrain —
  giving both DOTA-style lane pressure and AoE-style maneuver.
- **Win condition:** destroy the enemy **Command Center**. Lose if yours falls.
- **The loop (both directions simultaneously):**
  1. Grow economy.
  2. Build defenses (towers + walls) on your lanes.
  3. Produce an army.
  4. Push a lane to pressure the enemy base.
  5. Defend against their counter-pushes/waves.
- The core tension — and the replayability hook — is **splitting resources and
  attention between offense and defense.**

## Economy & base building

Two resources only (legibility over complexity):

- **Credits** — main currency. **Passive trickle** scaled by number of
  **Refineries** working a large resource node. (No harvester micro in v1.)
- **Power** — produced by **Power Plants**, consumed by buildings/towers.
  Running a **power deficit slows towers/production** (a *Red Alert* staple and a
  key pressure lever).
- **Build flow:** Command Center → Power Plant → Refinery → Barracks/Factory →
  defenses.
- **Placement:** buildings placed freely on buildable terrain ("build anywhere"
  RTS feel); towers/walls restricted to defensible spots near lanes.

## Units & combat

Rock-paper-scissors so balance is legible and the AI is teachable:

- **Infantry** — cheap, fast, swarms.
- **Armor / tanks** — tough, strong vs structures & infantry; weak vs anti-armor.
- **Anti-armor** — strong vs tanks; weak vs infantry swarm.
- **Air** (helicopters) — hits anything, fragile; weak vs dedicated AA.
- **Total vision: ~5–6 unit types. MVP: 3.**
- Combat is **auto-resolved by the sim**: attack range, cooldown, and a
  **damage-type vs armor-type table**.
- **All unit/building/tower stats live in data files (JSON / Godot resources),
  not code** — balancing is editing a table, not recompiling.

## Towers / static defense (the TD half)

- **Wall segments** — cheap; redirect/slow.
- **Gun turret** — anti-infantry/armor.
- **AA turret** — anti-air.
- **Splash/artillery tower** — later.
- Towers **cost Power to stay online**, so "turtle harder" trades against "fund my
  army." This Power coupling is what *fuses* TD and RTS rather than bolting them
  together.

## AI opponent

- Because everything is in the deterministic sim, the AI is **just another input
  source** — no special engine hooks.
- **MVP AI:** rule-based / behavior-tree with build orders and simple lane
  pressure logic: maintain economy ratio → mass army to a threshold → push the
  weakest lane → retreat if losing.
- **Difficulty:** resource handicaps + aggression tuning.
- **Testable:** AI-vs-AI matches run headlessly in CI to catch balance breaks and
  crashes.
- **No machine learning** — overkill and non-deterministic.

## MVP scope (Milestone 1 — must be *fun* before expanding)

**Includes:**

- 1 map, 1 faction.
- Two-resource economy (Credits trickle + Power).
- **3 buildings:** Command Center, Power Plant, Barracks.
- **3 unit types:** infantry, tank, anti-armor.
- **2 towers** (gun, AA) + walls.
- **1 rule-based AI** with difficulty tuning.
- Full attack/defend → destroy-base loop.
- Win/lose screens.

**Deferred (all slot onto the same sim core later):**

- Air units, multiple factions, campaign, co-op, PvP, polished art.

## Testing strategy

The sim/render split makes this straightforward:

- **TDD on the sim layer.** Unit tests for: resource ticks, damage resolution,
  building placement rules, win/lose detection.
- **Determinism tests:** same seed + same inputs ⇒ identical end state.
- **AI-vs-AI smoke matches** as integration tests.
- **Render layer:** light manual testing — all *logic* is covered headlessly.

## Out of scope (explicitly, for now)

- 3D rendering.
- Networked play (co-op and PvP) — architecturally enabled, not implemented.
- Campaign/story content authoring.
- Machine-learning AI.
- More than two resources; harvester micro.

## Open questions / future decisions

- Final game name / faction identities / art direction.
- Exact map dimensions, lane count (2 vs 3), and flanking-terrain ratio.
- Fixed-point math library choice vs hand-rolled deterministic math in C#.
- Whether Godot 4 C# or Unity C# is the final engine (low-stakes, reversible).
