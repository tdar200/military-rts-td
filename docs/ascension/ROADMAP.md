# Implementation roadmap

The delivery goal is an excellent Earth RTS before the larger civilization game. This roadmap defines implementation work; the accompanying blueprint/catalogue does not itself implement these systems. Existing gameplay changes in the working tree predate this package and must be preserved.

## Repository audit: reuse, repair, extend

Inspection on 3 October 2026; observations come from source, not a new playtest or benchmark.

| Area | Existing source evidence | Implication |
|---|---|---|
| Authoritative simulation | `crates/core/src/game/sim.rs`, `fixed.rs`, `hash.rs`, `rng.rs` | Retain deterministic Rust core and command validation. Do not replace it with Godot-side rules. |
| Earth operation | `scenario.rs::survival`: founding, finite starting ore, defended alien base, waves at 2700/5400 ticks | Much of the requested vertical slice is scaffolded. Improve this operation instead of starting another prototype. |
| Victory | `sim.rs`: Earthfront Core Node victory and human command-centre defeat checks | Retain decisive base destruction; persist a campaign milestone separately later. |
| Tactical roles | `stats.rs`, `sim.rs`: infantry, anti-armour, tanks, helicopters, harvesters, capital units, turrets and walls | Reuse selection/combat/pathing; separate production roles and later add artillery. |
| Resource delivery | `sim.rs`: harvest cargo, refinery return, finite deposits | Extend the local cargo model into stock accounting; preserve the exposed-hauler decision. |
| Electricity | `BuildingStats.energy_output` and simulation energy stockpile | Currently not a complete delivered-power network. Add power flow and bounded storage; do not relabel a stockpile as a grid. |
| Industry | Timed build/production jobs and costs in simulation/balance | Add work rates, material reservation and retooling incrementally. |
| Research | `apply_research` deducts money/energy/labour then sets `(tech_id, duration)` | Replace timer-dominated progress with allocated services and prototype work in the new ruleset. Existing powered progress is not enough to model scientific infrastructure. |
| Technology content | `tech_grid.rs`, `tech_grid_table.rs`: fixed 500 slots; `real_building`/`real_unit` explicitly map only a subset | Large graph is not proof of complete content. Ship only bound effects in the playable deck. |
| Era mismatch | Ten eras in `tech_grid::Era`, four in `stats::Era` | Separate campaign maturity from equipment tier before extending either; preserve old save meaning. |
| Theme mismatch | Early runtime mapping includes AntimatterPlant at grid ID 105; shields/antigravity and era damage bonuses exist | Ground the first two eras. Do not expose antimatter or blanket antigravity as near-present technology. |
| Strategic experiment | `planet.rs`: territory regions and controlling command-centre seats; colony automation in simulation | Useful ownership/automation precedent, not a full orbital/interstellar map or scale transition. |
| Godot | `godot3d/scripts/earthfront_3d.gd`, `continuous_terrain.gd`; bridge in `crates/server/src/bin/godot-bridge.rs` | Keep presentation investment. Extend bridge with flow/job/reason-code fields rather than creating a competing simulation. |
| Other client | `crates/render-shell/` | Keep compatibility tests and basic operation; Godot is the primary polished slice client. |
| Networking | `lockstep.rs`, server replay; `docs/NETCODE.md` | Deterministic session core exists; production transport/matchmaking is separate, unfinished deployment scope. |

The existing grid's numbers encode era/branch/step and unlock logic. Do not overwrite it with this catalogue. New IDs require a registry and explicit scenario binding. Legacy campaign state should stay in its original ruleset until a reviewed migration exists.

## Milestone 0 — Instrument and stabilize the current Earthfront

Deliverable: reproducible baseline operation and a content/status audit.

1. Record current build instructions, toolchain, content hash and working-tree baseline. Do not revert existing work.
2. Run current workspace tests, formatting and strict Clippy before changing simulation behavior. Record failures as baseline findings rather than silently fixing unrelated code.
3. Capture three full seeded matches: normal combined arms, defence-heavy and mobile counterattack. Collect tick time, orders rejected, stuck units, research timing and decisive outcome.
4. Enumerate every visible research unlock and whether it maps to a live effect. Mark previews explicitly or remove from playable command menus.
5. Add replay metadata and event counters needed for future balance comparisons. Establish a named baseline machine for performance targets.

Exit: current operation runs from launch to Core Node victory and to player defeat; replay matches state hashes; known issues have reproducible steps. This milestone is a short foundation task, not a reason to delay gameplay work for a generalized engine rewrite.

## Milestone 1 — Operation Dawnshield, two-era vertical slice

**A single polished Earth map, approximately 25–40 minutes, with a complete gather/build/defend/research/counterattack loop.** No Solar map, galactic simulation, digital minds, gates or megastructures. All buildable units and technology effects must work.

### Map and opening

Use a curated version of the existing approximately 44×26 Earthfront battlefield. Human industrial district in the west; defended alien Core Node in the east. A central bridge offers a short dangerous route, a northern ridge rewards infantry/AT positions, and a southern industrial road supports mobile flanks. Ensure passable routes for every required ground role; aircraft can cross terrain but must return for sustainment.

Initial base footprint can be chosen inside a small safe zone. Starter package: command centre, generator kit, refinery kit, two harvesters, four infantry squads and enough refined material to recover from one early mistake. The first attack timer starts on confirmed founding, with a visible setup countdown rather than unlimited pre-wave simulation.

Deposits: safe home ore, smaller protected reserve, two contested expansion sites, and rich exposed industrial ruins near enemy supply. Start with at least 24,000 ore design units across the map, then tune against actual consumption; 1 ore → 0.8 usable material in the baseline recipe. Late-wave wreck salvage offers a limited recovery path, not a perpetual-motion economy. Each expansion has a distinct defence geometry.

### Resource and power contract

Player-facing primary resources: **ore, refined material, delivered electricity**. Auxiliary bars: crew capacity and local military supply. Existing money is a compatibility adapter for refined material during the first migration; it does not become a second interchangeable physical stock. Separate displayed material from a future civilian procurement budget.

Illustrative initial production values, to tune in playtests:

| Item | Input | Output / capacity | Operating demand |
|---|---|---|---|
| Harvester | Deposit ore; 20-unit cargo | One round trip around 20–40 s depending on distance | Transport upkeep bundled for this slice. |
| Refinery | 1 ore/s per active processing lane | 0.8 refined material/s; buffer 80 | 20 power units. |
| Field generator | Maintained starter fuel allocation | 80 power units | Fuel procurement bundled for this slice. |
| Battery | Surplus electricity | 2400 energy units, max 40 power charge/discharge | Round-trip efficiency represented explicitly. |
| Barracks | Material + 1 crew slot per squad | 6 industrial work/s | 10 power units. |
| Vehicle works | Material + crew slots | 12 work/s | 30 power units. |
| Laboratory | Staff + compute + experimental kits | 3 theory work/s at full service | 25 power units. |
| Supply depot | 1 refined material per package | 1 ammunition/parts package per 5 s; store 30 | 5 power units. |

Power units here are tactical balance units; define one power unit = 1 catalogue kW for the slice. Battery energy is power-unit seconds. Physical conversion applies only within the slice; later real-world labels remain balance approximations. A single starting generator cannot run unrestricted extraction, vehicle production and a full laboratory simultaneously. Refineries can gain lanes through an upgrade rather than multiplying arbitrary income modifiers.

Costs must fit income: a tank at 180 material with a single 0.8/s refinery takes 225 seconds of material accumulation before other spending. Therefore opening stock, extra processing lanes and contested expansions are necessary, not optional decoration. Measure the actual opening before locking these numbers. Do not use an impressive-looking 30-second factory timer to hide a four-minute income bottleneck.

**Target funding example:** begin with 900 refined material; a new refinery costs 100, a generator 80, barracks 100, vehicle works 180, laboratory 120, depot 60, a gun turret 70, an infantry squad 20 and a tank 180. Starting kits do not also deduct those structures' prices. Two refineries produce 1.6 material/s when adequately fed; this can sustain mixed spending but not unlimited tank spam. Catalogue prototype budgets are separately normalized and must be tuned to this ledger before runtime binding.

### Buildings and military roster

Essential buildings: command centre, generator, refinery, barracks, vehicle works, air pad, laboratory, depot/warehouse, gun turret, AA battery, walls/gates and repair facility. A battery, fission generator and robotic production upgrade support the second era. Upgrade existing buildings where a separate footprint adds no decision.

Required human roles: infantry, tank, anti-armour team, helicopter and harvester; add supply truck and engineer as logistics/control roles. Artillery and observation drone are the two stretch roles needed if their research cards ship; otherwise their cards remain outside the live deck. Human aircraft are visibly attackable by AA and need rearm opportunities. Enemy roster: cheap drone infantry, durable walker, anti-armour spitter, airborne raider and slow siege carrier. Give each a resource cost, counter and recognizable silhouette.

First-pass relative balance targets, normalized at equal material investment:

| Encounter | Desired behavior |
|---|---|
| Tanks vs exposed infantry | Tanks win decisively; infantry retreat/cover still matters. |
| Prepared AT + infantry screen vs unsupported tanks | Defenders win with meaningful survivors. |
| Infantry flank vs unsupported AT | Infantry win if they reach effective range. |
| Helicopters vs unsupported armour | Aircraft win over repeated sorties, bounded by rearm. |
| Aircraft vs covered AA | Aircraft lose unless they isolate/saturate coverage. |
| Turrets vs equal mobile spending in a frontal attack | Static defence wins locally but cannot secure distant ore. |
| Supplied force vs same force with exhausted ammo | Supply advantage is decisive; empty units can retreat. |

Avoid specifying universal damage ratios before measuring pathing, targeting and focus-fire behavior. The existing counter tests are a foundation, not proof that the revised economy produces balanced matches.

### Research and era boundaries

Use a 24-node **scenario binding set**: T001–T019 plus T021, T022, T024, T028 and T039 from the catalogue. It is prerequisite-closed. Not all are presented as buttons: basic doctrine, power distribution, ore/refining, scheduling, logistics, armour production, computing, experimental practice, medicine and accounting can be starting knowledge or scenario-provided capabilities. Each granted node must have its own prerequisites granted as well.

A concrete default grant set is T001–T007, T009, T014–T017 (12 nodes). The remaining 12 are wartime deployments/research opportunities: T008, T010, T011, T012, T013, T018, T019, T021, T022, T024, T028, T039. If artillery/drone roles are deferred, remove T018/T019 from the live scenario binding and ship a 22-node set; never expose a nonfunctional unlock to meet a numeric target. This remains a curated subset of the 200 examples, not a claim of complete catalogue integration.

Research examples to implement first:

- Guided anti-armour: experiment kits + staffed lab → portable AT production at barracks.
- Air defence: radar/fire-control prerequisite + powered experiment → AA battery blueprint.
- Battery buffering: lab and materials → construction recipe for bounded power storage.
- Robotic workcells: commissioned factory + compute service → local retrofit using power in place of some crew demand.
- AI-assisted science: powered compute allocation → faster eligible theory tasks but no free experimental throughput.
- Distributed factory control: local store targets and outage policy → automatic fallback orders with visible limits.

Era 2 recognition requires commissioned robotic workcells, AI-assisted research support, and sustained power reserve for 60 simulation seconds while maintaining minimum defence supply. Era 2 is not necessary to make the first tank, AA or aircraft. Winning with excellent Era 1 play remains possible; research is an advantage with opportunity cost, not a mandatory checklist before damaging the Core Node.

Milestone research economy uses a lab/compute capability provided by the command campus at low output, allowing construction of a stronger lab without a circular prerequisite. Personnel are allocated capacity, not permanently consumed whenever a project begins. Give every research pause a visible reason code.

### Waves and objective

Wave 1 infantry/drone pressure; wave 2 mixed armour/AT; wave 3 raiders against harvest routes; wave 4 introduces air or siege according to doctrine; wave 5 combines a slow siege carrier with escorts. Subsequent waves use bounded adaptive compositions and survivors rather than unbounded stat growth. Exact staging and timings are tuned after observing openings.

All reinforcements spawn at a defined Core Node gate or enter visibly from an orbital landing corridor. No surprise materialization inside the human base. Local enemy factories spend resources; off-map assistance is a separately exposed support allowance. Damaging alien power or manufacturing reduces local support. A strong player can counterattack before every wave has appeared.

Victory: destroy the Core Node. Defeat: lose the human command centre. Victory panel reports economy, losses, supply interruptions, research utilization and time, then reveals Solar relay coordinates as narrative continuation only. Do not imply the next map exists until it ships.

### Implementation sequence within Milestone 1

| Increment | Concrete engineering work | Playable exit |
|---|---|---|
| 1A Grounded content binding | Add scenario-specific runtime IDs for initial units and effects; hide unimplemented grid nodes; remove early antimatter/antigravity from this operation; retain legacy mode separately | Earthfront remains completable with infantry, AT, tanks, aircraft and defenses. |
| 1B Flowing power | Add generation, demand, bounded storage and priority allocation; extend bridge and resource HUD | Player can overload a base, identify cause, shed load and recover. |
| 1C Local industry | Add material inventory/reservations, work-based queues and factory roles; preserve harvester delivery | A second factory only helps when resources and power can support it. |
| 1D Supplied combat | Add depot stock, local resupply and ammunition; dispatch minimal truck service | Cutting the exposed route changes battle outcome; restoring it restores combat capability. |
| 1E Economic science | Add research work/services/prototype requirements; bind the curated deck and Era 2 upgrades | Destroying or depowering research infrastructure pauses correctly; knowledge survives. |
| 1F Tactical pressure | Add wave budgets, staging, doctrine observations and basic route choice; tune alien asymmetry | Player can recognize and counter adaptation without chasing cheating spawns. |
| 1G Player-facing polish | Stalled-job explanations, supply overlays, queue cancellation/refunds, command feedback, onboarding and results | New players understand costs and complete the loop without developer assistance. |

Each increment keeps a runnable operation. Do not merge six half-integrated systems and call the combined build a slice.

### Acceptance gates

Automated correctness:

- Same seed/commands produces identical hashes across repeated runs and supported native/wasm builds.
- Conservation: material removed from deposits equals material in transit, stored, consumed or recorded loss; cancelled orders cannot create stock.
- Power: delivered demand cannot exceed generation plus bounded discharge; an empty battery cannot power a job; priority changes are deterministic.
- Industry: zero input/power produces no work; cancellation cannot refund consumed components; simultaneous factories cannot claim the same reservation.
- Research: facility destruction pauses new work, retained work survives, completed science remains known; speculative or unbound tech cannot enter the slice.
- Logistics: cargo has exactly one owner/location; destroyed convoy cargo cannot arrive; resupply consumes depot inventory; out-of-ammo guns stop firing.
- Campaign: Core Node destruction always wins once; player command-centre destruction loses consistently; no later wave can revive the node or revoke victory.
- AI: budget accounting and declared observation access hold; reaction delays and staging are reproducible.

Playtest acceptance (targets, not claims of achieved results):

- Five unfamiliar RTS players can train units, resolve a power deficit and issue a counterattack without developer help after onboarding.
- At least three openings complete Normal: mobile pressure, fortified economy, research-first with limited defence.
- Experienced players can win consistently without exploiting blocked pathing, indefinite kiting or unlimited refunds; hard mode requires tighter choices rather than perfect clicks.
- Median first combat near 90–150 seconds; successful full operation commonly 25–40 minutes; investigate outliers rather than force every run into a timer.
- At least one battle is won through a flank and one through logistics denial in observed sessions.
- UI explains the binding bottleneck within two interactions; no research card promises an unimplemented unit.
- Performance meets the measured baseline budget; an hour-long stress run has no growing orphan queues, invalid cargo or stuck match objective.

Record actual outcomes and retune. Do not declare the slice excellent based only on passing deterministic tests.

## Milestone 2 — Industrial Earth and Fusion

Playable deliverable: a small Earth campaign with regional expansion and a genuinely transformative fusion conversion.

Add distinct iron/copper/electronics/fuel supply chains, worker specialization, universities, specialized experimental facilities, artillery logistics, aircraft fuel, rail, repair parts and civilian procurement. Ship Era 3 only when fuel breeding, materials, cooling and reactor commissioning form a coherent chain. Add regional governors using the same budgets and validators.

Exit: a player can remain viable with fission or invest in fusion; fusion materially changes production possibilities without instantly replacing all plants. Finite-resource maps remain winnable through expansion/recycling/procurement. A stabilized region runs autonomously for ten minutes of normal play. Save/load preserves reservations and planned jobs exactly.

## Milestone 3 — Solar liberation

Playable deliverable: Earth, Moon and one asteroid region with transport, orbital construction and a Solar enemy base.

Add the region graph and canonical campaign clock, orbital transfer events, launch costs, local inventories, closed habitats and fleets. Integrate one tactical↔aggregate boundary using persistent manifests. Build the first major off-world project (orbital yard or lunar elevator). No interstellar travel yet.

Exit: no mass, crew, ammunition, damage or time duplication after 1,000 repeated authority transitions; source cargo cannot also remain in the source store; off-world production can sustain itself; losing a launch hub changes military options; the Solar campaign can be won with no second-by-second planetary micromanagement.

## Milestone 4 — Interstellar frontier

Playable deliverable: three to seven star systems, long-lead expeditions, alien origin discovery and two viable population-transport paths.

Ship autonomous seeds, causal communications, strategic time acceleration, caches, generation habitats and optional hibernation/antimatter branches. Allow meaningful domestic alternatives when an experimental route is unattractive. No gates needed.

Exit: the campaign cannot deadlock while every fleet is in transit; the player receives relevant decisions between arrivals; an isolated colony follows policies without home intervention; command/report timestamps remain honest; alien origin can be found along multiple seeded routes.

## Milestone 5 — Stellar works and civilization choices

Playable deliverable: a multi-system war centred on collector swarms, star lifting and vulnerable industrial megastructures, with biological/hybrid/machine/digital options.

Ship partial-output megaprojects, sector resource aggregation, population substrate accounting and distributed research. Digital minds remain optional and scientifically labelled. Separate construction-heavy machine expansion from food/habitat-heavy biological expansion.

Exit: megastructures transform energy/industry without erasing upkeep; at least two substrate paths can complete the same operation; a collector raid matters without causing an unrecoverable one-hit empire collapse; older local forces retain useful garrison roles.

## Milestone 6 — Extreme physics and galactic governance

Playable deliverable: a bounded sector campaign with compact-object energy, federated AI and two explicitly different physics rulesets.

Ship default causal routes first. Then add optional paired gates with endpoint delivery, bandwidth, reserves, cargo ownership and predictable failure handling. Stellar/system combat uses aggregate formations with optional focused tactical operations. Add alien lineage diplomacy and the wider replication crisis.

Exit: both rulesets can reach a campaign ending; gate failure reroutes or strands real cargo without duplication; no player must command millions of units; aggregate combat calibration errors are measured against detailed scenarios; a 10,000-region synthetic benchmark meets its declared budget on a named machine.

## Milestone 7 — Cosmic continuity

Playable deliverable: a finite authored endgame in a procedurally varied reachable domain, with survival, coalition and optional fictional intervention endings.

Ship horizon-aware strategic planning, refuge construction, long-term free-energy accounting and migration. Deep time is represented through operations plus explicitly simulated development intervals. Artificial universes and vacuum engineering appear only in the opt-in ruleset and disclose assumptions at unlock and victory.

Exit: default causal campaign has a satisfying complete ending without unknown physics; choices made on Earth influence institutions, industrial standards or surviving archives; the last operation is strategically legible, not a screen of exponentially growing numbers.

## Implementation contracts and migration details

### Resource and job contracts

Introduce definitions before switching existing behavior:

```rust
// Illustrative interfaces, not drop-in code for the present crate.
struct Inventory { location: RegionId, available: ResourceBundle, reserved: ResourceBundle }
struct WorkOrder { recipe: RecipeId, remaining_work: Work, reservation: ReservationId }
struct PowerConsumer { priority: u8, requested: Power, minimum: Power }
struct ResearchProject { tech: TechId, phase: ResearchPhase, completed_work: Work }
struct Transfer { cargo: CargoId, from: StoreId, to: StoreId, arrival: CampaignTick }
struct RegionAuthority { region: RegionId, mode: AuthorityMode, manifest: ManifestId }
```

A resource reservation transaction either succeeds entirely or changes nothing. Each job/prototype uses one reservation owner. Failure reason codes flow to the HUD: `NoMaterial`, `NoPower`, `NoStaff`, `NoFacility`, `NoEvidence`, `NoRoute`, `NoOutputSpace`, `UnknownEffect`.

Develop `Power`, `Energy`, `Work`, `Mass` and `Tick` as distinct types to prevent dimensional mistakes. Serialize canonical units explicitly. Human UI formatting can scale values freely; authoritative arithmetic cannot.

### Era and ID migration

1. Name the existing four-tier unit table `EquipmentTier` conceptually without changing saved numerical meaning.
2. Add campaign `MaturityEra` and immutable authoring technology IDs; translate through a content registry, not `era*50 + branch*5 + step`.
3. Version the ruleset: legacy grid continues to load in legacy mode; new Earthfront uses the curated v2 graph.
4. Create an explicit mapping table only for legacy nodes with equivalent real effects. Unmapped knowledge is archived as legacy content, never silently reassigned to a different discovery.
5. Pin replays to the old version or provide a compatible runner; do not promise behavior-preserving replay across changed balance or physics.
6. Deprecate duplicate era APIs only after both clients and saves use the explicit distinction.

### Catalogue pipeline

`docs/ascension/technologies.json` is the authored source for this proposal. `tools/ascension_catalog.py` validates graph/facility/cost/science invariants and renders `TECHNOLOGIES.md`. Runtime integration will add typed effects and concrete `BuildingKind`/`UnitKind` bindings for the chosen slice. Never execute the current prose `gameplay_effect` as code.

Each runtime binding must declare: real effect handler, UI explanation, prerequisite/facility provider, bill of materials, simulation-unit conversion, ruleset availability, save ID and at least one meaningful scenario proving the effect. CI must reject unbound effects in shipping scenario decks. Catalogue records remain `design_only` until those bindings exist; changing the label alone is not implementation.

### Testing by phase

Run focused simulation tests for each new rule, then the existing workspace suite. Run formatting/Clippy/wasm checks required by the repository before a gameplay PR is ready. Update golden hashes only after explaining the intentional changed rule and confirming cross-target determinism. Snapshot hashes alone cannot prove economic conservation or fun.

Before strategic layers ship, test the same region aggregated for N intervals versus stepped over equivalent event boundaries for economic conservation; exact tactical battle equivalence is neither assumed nor required. Compare combat outcomes statistically across a fixed reference set and ensure no consistent benefit from manually switching representation.

## Risk register and release discipline

| Risk | Early signal | Response / scope cut |
|---|---|---|
| Too many resources | Players cannot identify why production stopped | Delay commodity split; keep physical model extensible underneath. |
| Science as timer race | Same best research sequence in every match | Add facility/location opportunity costs and useful alternate unlocks. |
| Logistics as tedious punishment | Players spend most actions rescuing trucks | Improve auto-dispatch, reserves and recovery; retain network strategy. |
| AI appears to cheat | Counters arrive before observed production could finish | Audit budgets, observation snapshots and doctrine lock timing. |
| Scale transition destroys attachment | Earlier cities/units vanish into anonymous totals | Preserve named cohorts, landmarks, institutions and ledgers. |
| Infinite scope | Late-era assets appear before the Earth loop is fun | Freeze future content production; ship the current milestone gate. |
| Giant simulation monolith | Every system change touches unrelated behavior | Extract the next responsibility behind stable contracts, not a wholesale rewrite. |
| Speculative science is misleading | Players read optional physics as prediction | Keep provenance and assumptions next to the unlock, not buried in lore. |

Milestones are dependency gates, not calendar promises. Estimate staffing and dates after the baseline audit and first power/economy increments reveal integration cost. Keep design, implementation, measured validation and playable claims distinct in every release note.
