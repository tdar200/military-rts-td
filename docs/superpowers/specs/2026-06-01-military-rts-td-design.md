# Military RTS + Tower Defense — Design Spec

**Date:** 2026-06-01 (revised 2026-06-02: shared Rust core / multi-device pivot)
**Status:** Approved (brainstorming complete) — ready for implementation planning
**Working title:** *(TBD — placeholder project name: `military-rts-td`)*

## One-line pitch

A military real-time strategy game fused with tower defense and DOTA-style lane
pressure: build a base and economy, defend it with units and static towers, and
push the lanes to destroy the enemy base. Single-player vs AI first, architected
so PvP can be added later. Built on a **single deterministic Rust core** shared
across desktop, web, mobile, **and the backend server** — so client and server
can never diverge.

## Goals & constraints

- **Goal:** A polished, shippable/sellable game. Long road accepted.
- **Audience hook ("the game that doesn't quit"):** replayability from the
  attack/defend tension and varied skirmish matches.
- **Zero backend↔frontend drift (hard requirement):** frontend and backend run
  the *exact same* deterministic simulation core. They must never disagree. This
  is what enables authoritative server validation and lockstep PvP.
- **Strictest possible compiler:** Rust, with maximal lint strictness (deny
  warnings, Clippy pedantic, forbid `unsafe` in the core, and **forbid float
  arithmetic in the deterministic core** so determinism is compiler-enforced).
- **Performance:** native-fast core; no GC pauses; tight fixed-timestep sim.
- **Multi-device bundling (first-class):** one core crate compiles to Windows,
  macOS, Linux (native), the browser (WASM), and mobile (iOS/Android), plus a
  headless server build.
- **Perspective:** 2D / 2.5D top-down. 3D explicitly deferred — the core could
  drive a 3D renderer later if the game succeeds.
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
| Core language | **Rust** | Strict, fast, multi-target, no GC |
| Backend↔frontend | **Shared deterministic core, zero drift** | Same crate on client + server |
| Render shell | **Macroquad** (decided) | Pure-Rust immediate-mode shell; tiny WASM, all 5 targets (Android first-class). Godot+gdext / Bevy evaluated & rejected |
| Determinism | **Fixed-point math** (`fixed` crate), no floats in core | Float math diverges across targets |

## Architecture — one shared core, many shells

The defining decision: a single **deterministic simulation core** crate that
every target shares. Nothing platform-specific, no rendering, no I/O, no floats.

```
core/        # pure Rust sim crate — deterministic, fixed-point, no_std-friendly
data/        # unit/building/tower stats as data files (RON/JSON), not code
render-shell # thin per-platform view+input layer (Macroquad) -> desktop/web/mobile
server/      # headless build of `core` for authoritative validation / lockstep
```

### Simulation core (deterministic, headless, portable)

- **Pure Rust, no engine/OS dependencies, no rendering.** `no_std`-friendly to
  mechanically prevent accidental use of system time, threads, or I/O.
- Advances the world in discrete **fixed-timestep ticks**.
- Holds all game state: units, buildings, towers, resources, projectiles, AI.
- **Determinism rules (hard requirements):**
  - **No floating point.** All sim quantities (positions, velocities, health,
    timers) use a **fixed-point type** (`fixed` crate). Trig/roots via `cordic`
    or lookup tables — never `std` transcendental functions (they diverge across
    libm/WASM). This rule is **enforced by a Clippy lint denying float
    arithmetic in the core crate**, not just by convention.
  - **Seeded, deterministic RNG only** (e.g. a small PRNG owned by the sim). No
    OS entropy, no thread-local RNG.
  - **No wall-clock / frame-time reads** inside the core.
  - Same starting state + same ordered input stream ⇒ **bit-identical** end
    state on every target (desktop, WASM, mobile, server).
- Player and AI both feed the core via **queued, ordered commands** (build here,
  move these units, set rally, etc.).
- **Why fixed-point (research-confirmed):** cross-target float math diverges —
  32- vs 64-bit (x87 vs SSE2), compiler/opt differences, and especially
  transcendental functions across libm/WASM. Observed drift as small as
  `87` vs `87.000000002424` compounds into desyncs. Fixed-point is the proven
  cross-platform-deterministic approach (cf. rustsim's deterministic physics).

### Render shells (thin, per-platform)

- A lightweight **Macroquad** layer reads core state each frame and draws it,
  with **interpolation** between ticks for visual smoothness.
- Captures input and translates it into core commands. Owns nothing
  authoritative — purely a view + input shell.
- Same shell code compiles to desktop (native), web (WASM → canvas/WebGL via
  miniquad), and mobile (iOS/Android via miniquad). UI via `egui` if needed
  (WASM-compatible).
- **Godot+gdext / Bevy 0.18** were evaluated and rejected for v1 (Godot adds a C++
  engine + FFI boundary with experimental Rust-on-mobile/web; Bevy has heavy API
  churn and rougher mobile). The core is engine-agnostic, so the shell is swappable
  later if needs change.

### Backend server (same core, authoritative)

- The **server links the identical `core` crate**, compiled headless/native.
- Roles: authoritative validation (re-simulate from inputs to detect cheating /
  desync), matchmaking/lobby, and the lockstep relay for PvP later.
- Because client and server run the same deterministic code, "is the client
  lying?" reduces to "does the server's re-simulation match?" — no separate,
  drift-prone server logic to maintain.

### Why this split

- The core is **fully headless-testable** (thousands of battles in unit tests,
  no window, on any platform incl. CI).
- AI, balance, tower/lane logic live in clean, isolated, testable code.
- **Multi-device bundling is intrinsic:** one core, many thin shells.
- **Zero drift + lockstep PvP** become "synchronize the input streams" rather
  than "reconcile two different implementations."

## Strictness, build & multi-device bundling

- **Workspace:** Cargo workspace with `core`, `render-shell`, `server`, `data`.
- **Lints (strictest):** `#![forbid(unsafe_code)]` in `core`; deny warnings;
  Clippy `pedantic` + `nursery` denied; **deny float arithmetic in `core`**
  (`clippy::float_arithmetic`) to compiler-enforce determinism; `cargo-deny` for
  dependency/license/security gating.
- **Targets:** native desktop (Win/macOS/Linux), `wasm32-unknown-unknown`
  (browser), iOS/Android (via miniquad/macroquad), and a headless `server`
  binary. CI builds and tests all targets.
- **Performance posture:** fixed-timestep core decoupled from render frame rate;
  data-oriented state (contiguous arrays/slotmaps) for cache-friendliness;
  profile before optimizing.

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

## Pathfinding & movement (research-informed)

Performance lesson from the field: naive per-unit pathfinding tanks an RTS
(reports of `<15 fps` at ~300 units doing per-frame pathfinding). Our approach:

- **Pathfinding lives in the deterministic core** — fixed-point grid A* plus
  **flow-fields**. Do **not** use an engine navmesh/agent: float-based ones are
  non-deterministic and per-unit pathing does not scale.
- **Lanes are a performance ally:** precompute a **flow-field per lane** toward
  the enemy base once; units cheaply follow the field instead of each running
  A*. Reserve per-unit A* for off-lane maneuvering and re-routing around new
  buildings/walls.
- **Throttle path requests:** queue them and cap recomputes per tick rather than
  repathing every unit every tick.
- Keep MVP unit counts modest; treat large formations as groups where possible.

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
- Combat is **auto-resolved by the core**: attack range, cooldown, and a
  **damage-type vs armor-type table**.
- **All unit/building/tower stats live in data files (RON/JSON), not code** —
  balancing is editing a table, not recompiling. Stats parse into fixed-point.

## Towers / static defense (the TD half)

- **Wall segments** — cheap; redirect/slow.
- **Gun turret** — anti-infantry/armor.
- **AA turret** — anti-air.
- **Splash/artillery tower** — later.
- Towers **cost Power to stay online**, so "turtle harder" trades against "fund my
  army." This Power coupling is what *fuses* TD and RTS rather than bolting them
  together.

## AI opponent

- Because everything is in the deterministic core, the AI is **just another input
  source** — no special engine hooks.
- **MVP AI:** rule-based / behavior-tree with build orders and simple lane
  pressure logic: maintain economy ratio → mass army to a threshold → push the
  weakest lane → retreat if losing. (Research note: behavior trees are the
  modular, designer-friendly standard and stay predictable — a good fit for a
  deterministic core; FSMs scale poorly. Open RTS-BT reference implementations
  exist to study.)
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
- **Runs on at least desktop + web from the shared core** (proves the bundling
  promise early); server build exists headless even if PvP isn't wired yet.

**Deferred (all slot onto the same core later):**

- Air units, multiple factions, campaign, co-op, PvP matchmaking, polished art,
  mobile store packaging.

## Testing strategy

The shared-core design makes this straightforward:

- **TDD on the core.** Unit tests for: resource ticks, damage resolution,
  building placement rules, win/lose detection.
- **Determinism tests:** same seed + same inputs ⇒ identical end state —
  **including cross-target** (native vs WASM produce the same final hash).
- **AI-vs-AI smoke matches** as integration tests.
- **Render/shell layer:** light manual testing — all *logic* is covered
  headlessly.

## Out of scope (explicitly, for now)

- 3D rendering.
- Networked play (co-op and PvP) — architecturally enabled, not implemented.
- Campaign/story content authoring.
- Machine-learning AI.
- More than two resources; harvester micro.
- Mobile app-store packaging (the build targets exist; shipping to stores later).

## Open questions / future decisions

- Final game name / faction identities / art direction.
- Exact map dimensions, lane count (2 vs 3), and flanking-terrain ratio.
- Fixed-point configuration: which `fixed` type/precision; `cordic` vs lookup
  tables for trig.
- Render shell: **Macroquad — decided.** (Godot+gdext and Bevy 0.18 evaluated and
  rejected for v1; core is engine-agnostic so the shell is swappable later.)
- Mobile delivery: direct miniquad build vs a `uniffi`-exposed core behind native
  UI (only relevant if shells diverge per platform).
- Flow-field vs A* split: how much movement is lane-following vs free A*.
- Serialization format for save/replay and lockstep input logs.

## References (from research, 2026-06-01 / 2026-06-02)

- Deterministic lockstep + fixed-point: bonsai7 "Determinism and fixed point
  math"; "Deterministic Lockstep Networking Demystified" (LinkedIn, 2024);
  MonoGame forum thread on float determinism in an RTS.
- Float drift across targets: Unity Discussions "Lockstep syncing transform
  properties" (`87` vs `87.000000002424`); SO "Cross Platform Floating Point
  Consistency" (32- vs 64-bit x87/SSE2, optimization flags, transcendentals);
  gamedev.SE "How are deterministic games possible…".
- Rust determinism: rustsim "This month in rustsim #11" (cross-platform
  deterministic physics via fixed-point); r/rust discussion on WASM float
  behavior.
- Rust engines (Feb 2026): Aarambh Dev Hub "Rust Game Engines in 2026: Bevy vs
  Macroquad vs ggez vs Fyrox" (Bevy 0.18 / Macroquad 0.4.14); macroquad project
  page (miniquad → desktop/web/mobile); r/rust_gamedev "Choose game engine for
  native and wasm"; DuBlog "Making an ECS WebAssembly Game with Rust and Bevy".
- Godot RTS performance (still informs pathfinding strategy): Godot forum
  "optimize multiple pathfinding" (<15 fps at 300 units); r/godot threads on
  RTS unit-count optimization.
- AI: ScienceDirect "Survey of Behavior Trees"; Mina Pêcheux "Making an RTS game"
  (BT-driven unit/AI patterns).
