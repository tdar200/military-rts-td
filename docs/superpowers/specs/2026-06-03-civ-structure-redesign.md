# Civ-Structure Redesign — Founding, Progressive Unlocks, Tech Tree, Sieges

Approved by the user 2026-06-03 after three rejections of pacing-only fixes.
Research basis: Civ V/VI founding & tech-tree structure; Northgard / Against the
Storm / Frostpunk for Civ-feel in real time (full research in the session
workflow output `w8arjikyn`).

**Verdict being fixed:** techs handed out +1s instead of opening doors; the game
started with a finished base instead of a decision; combat was a stream instead
of punctuation; pure unconmmanded real-time. Slowing the clock does not make a
Civ — structure does.

**User decisions:** commanded real-time (NOT turn-based); ~10-min peace between
sieges (first ~6 min after founding); cursor-based founding (no colony-ship
unit); keep one exclusive doctrine fork at the capstone tier.

## Pillar 1 — The Founding Moment (Phase 1)
- New global sim phase `Survey | Active` (hashed). Survival starts in Survey
  with NO human base (beachhead still pre-placed, dormant). Skirmish + the
  golden run start Active with pre-placed bases (re-pin is one-time for the new
  hashed bytes only).
- Survey: wave clock frozen; `winner()` returns None for the human side (no CC
  yet ≠ loss). Shell shows "SURVEY — choose your site": foundability tint per
  hex (red illegal / grey legal / green deposit-adjacent premium), deposit
  richness always visible.
- `Command::FoundBase { owner, x, y }` (validate-then-resolve): Survey only,
  buildable tile. Resolves instantly: CC spawned, phase→Active,
  `phase_started = tick` (the wave clock measures from here), founding
  adjacent to an Ore deposit grants a +200 minerals colony bonus.
- The survival AI proxy founds deterministically (first buildable ore-adjacent
  tile) so the balance harness still runs.

## Pillar 2 — Progressive building placement (Phase 2)
- `Player.unlocked_buildings: u16` bitmask (hashed). Build rejects locked kinds.
- Human at founding: **Extractor, Reactor, Wall** only. Everything else arrives
  as tech-unlock payloads. AI players start fully unlocked (skirmish balance &
  golden unchanged).
- Command bar renders locked kinds greyed with the gating tech named; unlock
  toast on research completion.

## Pillar 3 — The unlocking tech TREE (Phase 3)
- `TechDef`: `prereqs: &[u32]` (multi-parent DAG), `unlocks: &[TechUnlock]`
  (`Building | Unit | Ability | Capability`), stat bonuses demoted to riders.
- ~24 nodes across 5 eras: Foundation → Expansion → Industrial → Energy →
  Ascendancy. Era = count of researched era-key techs (4 keys). Era-up triggers
  a telegraphed **era assault**.
- Foundation tier is **minerals-paid** (solves the lab-before-research
  bootstrap); `Computing` unlocks the Research Lab; later tiers research-paid.
- Units gated too (`unlocked_units` bitmask): Infantry via Mobilization, Tank
  via Heavy Chassis (+Barrage), AntiArmor via Munitions, Helicopter via
  Rotorcraft (+EMP), Capital via Capital Frames (+Nanite Field).
- Endless Ascendancy doctrines stay as the post-tree sink. One exclusive
  offense/defense doctrine fork is kept at the capstone via the existing
  `excludes()` machinery. NOTE (impl 2026-06-04): the endless U-panel doctrines
  are NOT hard-gated behind the capstone techs — they remain available as the
  numeric sink and the capstone fork is the *tech-side* exclusive choice. This is
  intentional; gating the panel was descoped to avoid coupling two systems.
- Shell: replace the list modal with a pannable era-column node GRAPH with
  drawn prereq edges and click-to-research; opening it pauses the sim.
- Eureka/boost discounts: deferred to a later phase (founding ore bonus ships
  in Phase 1 as minerals).

## Pillar 4 — Occasional sieges + commanded time (Phase 4)
- Survival waves: `first_delay 10_800` (6 min from founding), `interval 18_000`
  (10 min). Each siege is a discrete, named, telegraphed event; adapting-swarm
  growth retuned for few-but-large sieges. Milestone rescaled (hold N sieges).
- Telegraph: persistent countdown (exists), INCOMING alarm ≤45 s (exists),
  minimap arrow at the spawn edge (new).
- Commanded time: speed gears to 8×; AUTO-PAUSE with a banner on siege warning,
  research complete, era-up, human building destroyed, and at the founding
  prompt. Tech tree hard-pauses (already does); doctrine panel stays live.

## Determinism contract (unchanged)
Every new sim field (`phase`, `phase_started`, `unlocked_buildings`,
`unlocked_units`, any assault scheduling) goes into `state_hash`; golden
re-pinned once per core phase; `cargo run -p rts-server` MATCH; wasm build;
clippy pedantic+nursery clean; survival balance harness re-run per phase.
