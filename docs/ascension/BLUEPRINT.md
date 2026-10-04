# Ascension: game and systems blueprint

Proposal v1. Read alongside [the roadmap](ROADMAP.md), [200 technology records](TECHNOLOGIES.md) and [science boundaries](SCIENCE.md). All new numerical values below are initial balance hypotheses, not measured results.

## 1. Game vision

**Build the civilization that can survive the next war.** The battlefield asks what you need now; science shows what might become possible; industry determines what you can actually field. A tank saved through careful positioning matters because it represents production time, trained personnel and an exposed supply chain.

Earthfront opens as a legible combined-arms RTS. The wider campaign evolves into real-time management of industrial regions, worlds, systems and eventually stellar societies. The enduring strategic verbs are establish, supply, defend, discover, deploy and expand. Scale changes what those verbs act on.

Original identity: **capability transitions under military pressure**. Breakthroughs replace constraints instead of merely raising numbers. Fusion changes which operations can be powered. Automation changes labour allocation. Orbital industry changes where mass is cheap. Gates change network topology. Each transition creates new exposed infrastructure and a new dependency.

Target audience: players who enjoy army control and production planning, with optional depth panels for simulation enthusiasts. Default campaign offers pause and speed control; competitive operations run continuously with agreed speed. No turn-based mode, mandatory clicker loops, offline idle progression or purchasable power.

## 2. Core loop and player experience

Gather finite deposits → convert materials → deliver electricity → allocate industrial capacity → deploy units → defend and seize territory → obtain resources and evidence → research and prototype → retool industry → open the next strategic frontier.

Three decision horizons coexist:

- Seconds: withdraw damaged armour, intercept aircraft, protect a convoy, prioritize an incoming siege unit.
- Minutes: expand toward copper, divert a factory to ammunition, reserve power for research, sacrifice a forward depot to finish a breakthrough.
- Campaign chapters: electrify transport, specialize colonies, distribute political authority, build a new launch route or begin a megaproject.

The first ten minutes should teach: “ore in the ground is not usable inventory,” “a lab needs a functioning economy,” and “a mixed army plus a supply route outperforms an expensive unsupported army.” Do not teach twenty commodity icons before the first fight. An optional opening starts with a staffed command centre, generator, refinery, two haulers and four squads; advanced players can choose a founding site.

First operation target: 25–40 minutes, several viable openings, approximately six to nine major waves, and a player-chosen counterattack timing. Late chapters target 45–90-minute operations linked by persistent campaign development. Dates are narrative scale indicators, not a demand that the player wait literal centuries.

## 3. Resource economy

Separate four kinds of quantity:

| Kind | Examples | Rule |
|---|---|---|
| Stock | ore, steel, fuel, ammunition, food, isotopes | Finite inventory at a location; moved, consumed, recovered or destroyed. |
| Flow | electricity, industrial work, compute service, transport throughput | Delivered per simulation interval; unused capacity is lost unless a specific store exists. |
| Capacity | warehouse volume, workforce, radiator area, lab slots | Limits concurrent operation; cannot be spent like coins. |
| Knowledge | research, validated designs, evidence | Persistent and usually shareable; transmission still takes time at stellar scale. |

Credits are a procurement and maintenance budget for civilian services, not a substitute for physical materials. Owned factories do not conjure metal by spending credits. Outside procurement is a visible shipment with price, delay and finite supplier capacity; enemy blockades affect it.

Full terrestrial chains:

- Iron ore + fuel/electric heat → steel; steel + copper + electronics → vehicle components.
- Bauxite + electricity → aluminium; titanium ore + specialized refining → aerospace alloys.
- Silica + high-purity chemicals + energy → silicon wafers → electronics; rare-earth inputs improve selected motors and magnets, not every recipe indiscriminately.
- Crude hydrocarbons or synthetic fuel plants → fuel and chemical feedstocks; fuel drives mobile operations and early peak generation.
- Uranium extraction → enrichment/fuel fabrication → fission power, with waste handling represented as maintenance and storage capacity.
- Water + food production + housing + healthcare → supported population; education shifts available specialists rather than converting food instantly into scientists.

Milestone 1 intentionally compresses this into ore, refined material and delivered power, plus local ammunition/parts packages. Credits are the legacy-facing representation during migration. Iron/copper/etc. appear when geology offers meaningful choices in Milestone 2. Resource tiers are recipes and substitution permissions, never automatic renaming of yesterday's stockpile.

A deposit has quantity, grade, extraction limit, terrain and ownership. Extraction removes raw mass; processing loses an explicit fraction to tailings. Recycling returns some compatible material, never all energy or work. Destruction splits inventory into recoverable wreckage, inaccessible residue and lost mass categories. Low-grade deposits remain usable at higher energy cost.

Resource UI shows available / reserved / inbound / capacity and net flow. The first screen pins at most six bottlenecks; the detailed ledger exposes every commodity. Forecast depletion at current and planned extraction rates. Never sell an exhausted-mine surprise as difficulty.

## 4. Industrial capacity and manufacturing

A factory has specialized work capacity, tool compatibility, staff, electrical demand, material buffers and output bays. Jobs require a bill of materials and work units. Construction, ammunition, unit production, upgrades and research prototypes compete for the same scarce services.

For a one-second economy interval, expressed using fixed-point integer arithmetic:

```text
potential_work = nominal_work * staffing_fraction * condition_fraction
actual_work = min(potential_work, powered_work, material_supported_work,
                  logistics_supported_work, remaining_job_work)
input_consumed[r] = actual_work * recipe_input[r] / recipe_work
```

Retain fractional remainders in the job, so splitting work into many ticks cannot create materials. Reserve inputs at order acceptance; consume incrementally; cancellation returns only unconsumed inventory. Produced units occupy a delivery bay until released. Population is assigned, not deducted into oblivion.

A discovery authorizes a prototype recipe. A successful prototype authorizes production tooling. A commissioned factory may then manufacture units. Existing tanks remain their existing model until an explicit depot retrofit consumes parts and time. Knowledge is not an automatic empire-wide stat buff.

Shared industrial policy sliders allocate a **budget of work and material reservations** to military / infrastructure / science / civilian upkeep. They never multiply capacity. Local overrides have a visible expiry. Wartime overclocking increases wear and repair demand; do not use random catastrophic failure for routine optimization.

Example: a 12-work/s vehicle plant needs 360 work and 180 material for a tank. Full supply yields 30 seconds; half delivered power yields 60 seconds; absent electronics halts it. A second factory does not help if the shared refinery or grid is the bottleneck. Retooling to drones consumes 15 seconds plus 20 parts in the initial balance model; surviving tooling persists.

## 5. Electricity, storage and energy progression

Generation is power; batteries store energy. Use watts/joules or internally documented scaled units, never one undifferentiated “Energy” counter for both.

```text
requested_power = sum(enabled device demands)
served_power <= generation + storage_discharge_limit
stored_energy_next = clamp(stored_energy + charge_efficiency*charge_power*dt
                           - discharge_power*dt/discharge_efficiency, 0, capacity)
```

Allocate deterministically by player priority, then entity ID. Within a priority group share proportionally, retaining rounding residues. Devices expose minimum operating fraction: command and depot systems can operate at reduced throughput; a collider has a minimum stable power threshold and pauses below it. Batteries have finite capacity and power limits. Grid segments have throughput and losses; adjacency is simplified in the first slice, physical lines arrive later. Separate local grids do not pool electricity globally.

Early default priorities: life support and command → defensive supply → extraction → active manufacturing → research → discretionary export. Players can override this, with an explicit forecast of the result. Loss of power must be recoverable: command backup can build a slow emergency generator using a reserved starter kit; its finite reserve is visible.

| Era | Power source or carrier | New constraint and decision |
|---|---|---|
| 1 | Chemical generators, solar/storage, fission | Fuel deliveries, peak load, grid vulnerability. |
| 2 | Advanced fission, better storage, smart dispatch | Specialized parts and electrical transmission. |
| 3 | D–T fusion; optional later fuel cycles | Tritium breeding, maintenance, heat rejection; electrify industry or military first. |
| 4 | Orbital solar and fusion | Launch mass, radiator area, beamed-power receivers. |
| 5 | Fusion plus manufactured antimatter carrier | Production losses versus portable energy density. |
| 6 | Dyson swarms and stellar harvesting | Collector manufacture, transmission geometry and dissipation. |
| 7 | Efficient computing and recovered waste heat | Useful computation per watt, latency and cooling location. |
| 8 | Accretion/spin extraction; optional fictional gate support | Feedstock, finite spin, stable infrastructure and cooling. |
| 9 | Distributed stellar grids | Routing, resilience, communication latency and correlated failures. |
| 10 | Long-lived stellar/remnant infrastructure | Accessible free energy, heat sinks, survival horizons; fictional vacuum projects optional. |

A Kardashev-inspired dashboard displays usable power, captured fraction, resilience and waste heat. It is diagnostic, not an era-unlock button. Scale never makes energy conservation disappear. See [science corrections](SCIENCE.md).

## 6. Base building and territorial control

Structures occupy terrain, take delivered materials and construction work, and have maintenance, power, staffing and network needs. Construction sites can be interrupted and salvaged. Blueprints preview collision, supply reach, power deficit and expected completion. Free camera movement is not construction permission: build in an owned supply zone or send an engineer with cargo.

Territory means holding an anchor and a viable supply corridor; colouring a tile does not teleport its resources home. Mines can operate in a contested region while convoys are at risk. Capture requires a ground presence, suppression of defenders and a timed handover; changing a flag does not grant safe access to sabotaged machinery. Walls have gates and cannot trap friendly harvesters without a warning. No placement inside hostile footprints or instant walls under moving units.

| Era | Major structures | Economic consequence |
|---|---|---|
| 1 | Command centre, generator, refinery, warehouse/depot, barracks, vehicle works, air pad, lab, hospital, repair yard, radar, bunker, wall, gun/AA battery | Staff, fuel and material throughput compete with unit output. |
| 2 | Advanced fission station, robotic works, battery farm, university, AI cluster, composite foundry, precision lab, drone hangar, directed-energy test range | Automation trades labour for power, electronics and technicians. |
| 3 | Fusion station, breeding blanket works, superconductor mill, thermal reservoir, desalination plant, vertical farm, fusion test campus, railgun battery | High fixed investment; fuel independence only after breeding and maintenance chains. |
| 4 | Launch complex, orbital yard, mass driver, asteroid refinery, rotating habitat, orbital lab, lunar elevator, orbital ring project, planetary defence array | Location of mass matters; launch and radiator bottlenecks. |
| 5 | Beam sail array, cryogenic ark yard, antimatter plant, precision atom works, interstellar observatory, seed-factory dock | Long delivery lead times; expensive autonomy and stores. |
| 6 | Dyson collector foundry, star-lifting array, stellar separator, planet-disassembly yard, world-foundry project, stellar-engine anchorage | Commits huge fractions of regional construction capacity. |
| 7 | Cold compute habitat, mind archive, reversible logic foundry, biological sanctuary, programmable-material works, Matrioshka project | Population support depends on chosen substrate and cooling. |
| 8 | Accretion plant, relativistic test range, black-hole observatory, gravity-wave relay; optional gate anchor, metric laboratory | Concentrated energy assets become high-value network dependencies. |
| 9 | Sector governance hub, distributed fleet foundry, interstellar cache, deep-space radiator field, galaxy relay spine | Local autonomy and standards prevent central-command paralysis. |
| 10 | Refuge cluster, stellar-lifetime works, horizon observatory, intergalactic ark port, deep-time archive; optional cosmogenesis chamber | Preserve reachable assets instead of infinite expansion. |

Hospitals and universities have real ongoing benefits, not merely prerequisite labels. Civilian services recover specialists, improve training throughput and reduce displacement after attacks. Population loss and evacuation are visible strategic costs rather than a happiness meter tacked onto combat.

## 7. Military structure

A unit definition contains role, size, armour profile, weapons, ammunition, fuel/energy store, crew, supply demand, movement class, detection/targeting quality, heat budget, production recipe and refit paths. Unit chassis and equipment versions are distinct from civilizational era.

| Era | Representative deployable forces | Role, vulnerability and retained older role |
|---|---|---|
| 1 | Rifle squads, mechanized squads, tanks, missile teams, artillery, drones, helicopters, fighters, bombers; patrol ships where water matters | Tanks hold open ground; infantry hold cover; AA protects from aircraft; artillery requires targeting and ammunition. Cheap infantry still guards depots. |
| 2 | Loitering drones, active-protection armour, EW vehicles, counter-drone teams, precision artillery, hypersonic strike aircraft | Jamming and saturation contest autonomy; ordinary guns remain economical against soft targets. |
| 3 | Electric armour, railgun artillery, laser AA, fusion-powered support vehicles, thermal-management ships | Energy/heat bottlenecks and weather defeat universal laser dominance; missiles retain reach. |
| 4 | Orbital interceptors, escort cutters, boarding transports, mass-driver defence, autonomous miners with escorts | Delta-v and radiator exposure matter; ground armies still hold launch infrastructure. “Fighters” are local interceptors, not atmospheric dogfighters in vacuum. |
| 5 | Relativistic probes, ark escorts, autonomous missile tenders, interstellar logistics ships | Travel commitment and destination braking; local planetary forces remain faster to deploy. |
| 6 | Collector guards, stellar tugs, megastructure siege formations, mass-stream interceptors | Very visible infrastructure supports enormous weapons; small raiders threaten delicate collectors. |
| 7 | Distributed drone hosts, cyber-defence fleets, archive evacuation ships, morphable repair swarms | Verification and communications limit remote compromise; isolated conventional systems remain resilient. |
| 8 | Accretion-powered monitors, relativistic bastions; optional gate wardens and metric interdiction craft | Anchors, fuel flow and approach geometry; conventional convoy routes remain fallback. |
| 9 | Sector fleets, autonomous fortress systems, replicator interdiction groups, relativistic defence webs | Strategic throughput and replenishment; coordinated rather than numerically inflated units. |
| 10 | Refuge guardians, stellar migration escorts, intergalactic arks, entropy-efficient sentinels; optional metric containment fleets | Preserve habitats, route access and energy reserves; no costless universe-destroying click. |

An obsolete front-line tank may become a garrison vehicle, salvage source or upgrade candidate. It need not defeat a stellar fleet. Preserve its **economic role within its operating layer**, not implausible direct combat parity across all eras.

## 8. Combat mechanics

Target resolution uses weapon domain, line of fire, range, traverse, ammunition, heat and accuracy; armour and cover modify damage. Fixed-point hit rolls use event-keyed deterministic randomness. Suppression reduces movement/aim temporarily; it does not remove player control. Cover is visible on both teams. “Concealed infantry” means lower target quality and damage exposure in cover, not hidden icons or fog of war.

Initial counter matrix:

| Attacker | Strong target | Counterplay |
|---|---|---|
| Infantry | Exposed missile teams, depots, light drones | Armour, suppression, flanking and cover denial. |
| Anti-armour | Tanks at prepared range | Infantry screens, artillery, limited missile magazines. |
| Tank | Exposed infantry, breakthrough positions | AT crossfire, rough ground, fuel denial, obstacles. |
| Artillery | Static guns, dense formations | Counterbattery, mobile flanks, targeting disruption, ammunition raids. |
| Aircraft | Unsupported armour and convoys | Integrated AA, fighters, short sortie time, airfield attacks. |
| Turret | Cost-efficient local defence | Range disadvantage, power loss, several approach lanes. |
| Laser | Drones/missiles in a defended arc | Heat saturation, weather/attenuation where applicable, multiple vectors. |
| Missile | Distant or high-value targets | Interception, decoys, electronic attack, finite reload. |

No blanket “new era doubles all damage.” Improvements alter a capability: stabilization enables firing while moving; active protection intercepts a limited number of missiles; better batteries extend sorties; new optics improve target solutions. Armour remains mass that costs mobility and production.

Damage, repair, suppression and weapon state resolve in a stable tick order. Projectiles already in flight can survive the shooter's destruction. Ground targeting and air targeting use explicit weapon capabilities. Collisions and pathing should not prevent a selected formation from completing a simple retreat.

Late warfare has explicit response windows. Relativistic weapons can be extremely destructive but require large acceleration installations, predictable approach corridors in scenario geometry, defensive depth and sacrificial interceptors; warnings are determined by detection/light travel, not magic advance knowledge. Planet-cracking or stellar-disruption attacks are strategic projects with detectable preparation, ethical/political consequences, industrial cost and irreversible loss of the prize. Do not promise an intercept window where the physical model gives none: scenario design must provide early launch observation or preventative counterforce opportunities.

## 9. Logistics

A supply network is a graph of sources, stores, transfer links and consumers. Links have throughput, delay, allowed cargo, losses and ownership. Dispatch makes a cargo reservation and a transit record; arrivals credit exactly one destination. A blocked route triggers reroute, hold or recall according to policy.

First slice: depot coverage along passable paths, with local ammunition/parts stores and visible resupply trips; one combined military-supply commodity keeps it readable. Milestone 2 separates ammunition, fuel and replacement parts and adds trucks/rail. A tank with no fuel stops; it can still fire if ammunition remains. A dry gun cannot shoot. Unsupplied units lose sustainment, not arbitrary hit points every second. Emergency towing and limited carried reserves allow recovery.

Transport evolution: truck routes → rail/pipeline/airlift → autonomous freight → launch/mass driver/elevator → interplanetary cargo → interstellar cache/ark → optional paired gate. Throughput and latency remain separate. A gate changes travel time but does not grant infinite bandwidth.

Combat and economic reservations share priority policy. Reserve a configurable number of minutes of ammunition; avoid infinite production whenever a depot has space. Forecast “frontline ammunition exhausted in 45 seconds” and name the broken link. A player can defend a network without manually ordering each truck.

## 10. Research system

Use a directed acyclic capability graph, not a fixed rectangle whose coordinates dictate scientific dependencies. Eras are presentation and campaign gates; fields are tags and cross-links. Completed discoveries remain known even if the last lab is destroyed.

Each node stores all fields requested in the accompanying catalogue: identity, field, description, prerequisites, work and evidence, infrastructure, material/industrial cost, power demand, effect, units, buildings, reverse dependencies and plausibility. Infrastructure requirements reference capabilities with reachable providers. Some starting facilities and knowledge are scenario grants; the validator checks that they can bootstrap the graph.

A contemporary civilization starts with electromagnetism, semiconductor physics, ordinary mathematics and nuclear physics understood. Early “research” is wartime adaptation, qualification and production deployment, not rediscovery of the transistor while a jet flies overhead. Fundamental prerequisites absent from the 200-node examples are explicitly part of starting knowledge.

Research has three phases:

1. **Theory and evidence:** specialists, field-tagged laboratory throughput, compute allocation, observations and prerequisites establish a validated model.
2. **Experiment and prototype:** consumes physical kits and specialized facility time; practical proof unlocks a reproducible design.
3. **Deployment:** factories must be tooled and infrastructure commissioned. This is construction/production, not a research countdown.

```text
research_work_per_s = base_work * specialist_fraction
                     * min(power_fraction, compute_fraction,
                           experiment_capacity_fraction, input_fraction)
```

Use fixed-point arithmetic, cap every fraction at one, and return reason codes for every missing input. A project may accelerate by parallelizing independent experiments up to its declared maximum; ten labs cannot make a serial containment experiment finish ten times faster. Education raises qualified workforce over campaign time. AI consumes compute and supports specified tasks, with diminishing returns and validation requirements; it never gives unbounded research recursion.

A project progresses only while allocated resources and facility capability are delivered. Saving energy earlier does not power a destroyed lab. Interruptions preserve completed work and evidence; wasted partial experimental batches are stated before starting. No random roll can indefinitely block a required campaign technology. Optional alien branches can require scarce evidence; mandatory progression always has a domestic route.

Scientific fields cross-link: compute + spectroscopy → materials; materials + plasma → fusion; fusion + propulsion → interplanetary industry; autonomous manufacturing + orbital materials → swarms; astrophysics + high-energy experiments → optional spacetime investigations.

Milestone 1 uses a curated subset of 24 nodes, not 200 buttons. Players can inspect the wider future map in an explicitly labelled design preview only after the relevant content exists. A visible unlock must do something implemented.

## 11. Ten eras and transformative gates

Dates below are fictional campaign horizons. A gate requires installed and **sustained delivered capacity**, a demonstrated capability and a strategic objective; it never requires waiting for a date. Gate tests run over a declared observation window and do not revoke knowledge when infrastructure is later damaged.

| Era | Horizon / transformation | Example entry or exit achievement | Binding bottleneck |
|---|---|---|---|
| 1 Contemporary Humanity | 2000–2035; survive with military industry | Establish a supplied base, research wartime adaptations, protect an expansion | Raw materials, crews, power and immediate military pressure. |
| 2 Advanced Industrial | 2035–2080; automate and coordinate | Commission robotic production and an AI-supported lab while meeting civilian and defence reserve targets | Electronics, skilled technicians, resilient grids. |
| 3 Fusion | 2080–2200; electrify heavy industry | Demonstrate net delivered fusion power, breeding chain and maintainable components | Industrial conversion rate and heat. |
| 4 Solar | 2200–3000; location becomes orbital | Establish a self-supporting off-world industry and defend transport | Launch mass, orbital logistics, life support. |
| 5 Interstellar | 3,000–20,000 CE; travel becomes commitment | Deliver an independent industrial seed to another system; recover expedition origin evidence | Propulsion, autonomy and communication delay. |
| 6 Stellar Engineering | Tens of millennia; stars become productive assets | Operational collector fraction plus a closed repair/manufacturing loop | Stellar material handling and cooling. |
| 7 Post-Biological Options | Hundreds of millennia; choose civilization substrate | Validate a durable distributed civilization: biological, hybrid or digital | Compute, resilience, population support and coordination. |
| 8 Extreme Physics / Spacetime | Hundreds of millennia to millions of years | Commission a remnant-energy network; optionally demonstrate a gate under fictional rules | High-energy infrastructure and stability. |
| 9 Galactic | Millions of years or scenario compression; federate systems | Sustain several sector economies without central micromanagement | Latency, correlated risk and defence depth. |
| 10 Cosmic | Deep time; preserve agency against cosmic limits | Build a causally viable refuge network; optional fictional cosmic intervention | Reachability, free energy, heat rejection and long-term reliability. |

Era 7 does not force mind uploading. A biological federation with AI institutions can meet the same functional gate through habitats and governance. Era 8 does not force new physics. The strategic maturity track and the speculative physics track are orthogonal.

## 12. Resources and civilization across scales

| Era | New stocks/services | What stays meaningful |
|---|---|---|
| 1 | Metal ores, refined materials, fuel, food, trained people | Inventory, haulage and production opportunity cost. |
| 2 | Composites, precision components, battery packs, AI compute | Automation replaces some labour, increases maintenance and electricity. |
| 3 | Superconductors, breeding isotopes, fusion fuel, high-grade heat | Abundant gross energy does not erase fuel cycle or industrial capacity. |
| 4 | Asteroid feedstock, volatiles, habitat capacity, orbital lift | Different worlds specialize; imports have real travel time. |
| 5 | Antimatter stores, atomically precise components, seed kits, long-duration archives | Programmed matter still needs appropriate elements and heat rejection. |
| 6 | Stellar-mass feedstock allocations, collector capacity, world-building work | Stellar material has composition and extraction constraints. |
| 7 | Reliable compute, memory, cooling, biological habitat services, integrity certificates | Digital population consumes compute; machines consume factories; humans need habitats. |
| 8 | Accretion fuel, spin reserves, extreme-field experimental capacity; optional exotic stress | Black holes convert a resource or finite rotation, never provide limitless free energy. |
| 9 | Sector work allocations, fleet replenishment, relay bandwidth, systemic redundancy | Display aggregation replaces billions of resource widgets. |
| 10 | Available free-energy budgets, viable heat sinks, causally reachable mass, archive endurance | Entropy and causality constrain options; optional fictional rules are explicit. |

Population is cohorts by substrate and skills, not one expendable labour currency. Biological cohorts need food/habitat/medicine; enhanced humans trade specialized healthcare for resilience; cyborgs add parts and power; digital cohorts require memory, compute, cooling and independent backups; machine cohorts need chassis manufacturing and repair; hybrids pay multiple support costs but diversify failure modes.

No path gains every benefit. Digital systems are vulnerable to correlated software failure; biological colonies are vulnerable to habitat loss but offer independent, low-bandwidth agency. Machine population can scale with production but competes directly with military manufacturing. Cultural autonomy and consent policies affect migration and stability, represented by disclosed modifiers and events rather than compulsory ideology.

## 13. Map layers and scale transition

| Layer | Player commands | Simulated entity / resolution |
|---|---|---|
| Tactical | Squads, vehicles, individual buildings | Fixed-tick entities and pathing on local terrain. |
| Regional | Army groups, freight corridors, industrial districts | Formation cohorts, local stores and throughput graph. |
| Planetary | Theatre plans, continents, launch regions | Region ownership, population, factories and strategic transport. |
| Solar | Fleets, orbits, colonies, transfer schedules | Orbital nodes, transit events, launch windows approximated consistently. |
| Interstellar | Expeditions, system policies, supply caches | System inventories, fleet transit and time-stamped directives. |
| Galactic | Sector budgets, migration fronts, defence doctrines | Bounded sector graph with aggregate productive assets and risk. |
| Cosmic | Refuge networks, galactic groups, survival projects | Reachability graph and long-horizon event schedule. |

Camera zoom alone never changes authoritative simulation fidelity. A **registered activation transition** assigns a region either aggregate authority or tactical authority, not both. Going tactical instantiates forces from a persistent cohort manifest: exact equipment counts, damage bands, fuel, ammunition, crew and inventory. Closing it reconciles survivors, wrecks, consumed cargo and captured assets back into that same ledger. Repeated zooming cannot heal, duplicate, refill or reroll anything.

Non-active regions use deterministic aggregate rates and event-driven combat. Aggregate combat uses the same weapon-role tables and supply limits, but is not promised to reproduce a tactical battle blow-for-blow. Calibrate outcomes against a scenario suite; show confidence ranges for player forecasts, while the seeded resolver itself is reproducible. A region under manual tactical control uses the tactical outcome exclusively.

Bounded target: initially one active tactical theatre plus at most two background detailed theatres; all others aggregate. A later performance gate may increase this. Expand sectors by splitting aggregate records when strategically relevant; do not allocate an entity for every star in the galaxy. Procedural disaggregation uses persistent seeds and divides, never invents, material/population totals.

### Time model

There is one canonical campaign clock and rational layer-specific conversion factors between ticks and campaign duration. Tactical operations temporarily cap global speed; background regions progress over the **same campaign interval**. A month cannot pass in another region while a selected tank fights for ten seconds unless the campaign explicitly advances a chapter outside that combat interval.

Long transits use accelerated event-driven play between engagements. Single-player automatically pauses or slows on critical alerts according to user policy. A remote battle can be delegated; opening it earlier cannot rewind events. Multiplayer uses a voted or fixed speed schedule, with no private time acceleration. Era dates can jump in authored interludes with a summarized ledger of the simulated development that occurred.

Full battlefield visibility remains. At interstellar distances the strategic layer shows last received state plus its age, planned orders and arrival times; this is causal communication, not a hidden exploration shroud. An optional omniscient spectator layer can visualize truth, but remote commands still obey latency. Supply forecasts explicitly distinguish confirmed stock from estimates.

## 14. Automation and governance

Delegation is a contract: objective, budget, constraints, reserves, fallback and notification thresholds. Examples: “hold this pass with no more than 25% of regional ammunition” or “export surplus steel but keep two replacement tanks' materials.”

Automation ladder: repeat queue → stock targets → route auto-dispatch → district template → theatre commander → planetary governor → sector policy. Each level exposes its proposed actions and binding bottleneck. The player can override an order, lock assets, and undo a policy prospectively; no hidden auto-sell of a manually protected building.

Governors obey the same commands and resource validations as the player. Maintain bounded action queues and budget reservations so several governors cannot all spend the same stock. Reconcile policies at fixed intervals, with hysteresis to prevent oscillating build/cancel decisions. Notify exceptions, not every successful delivery. A fully stable world should run for ten minutes of normal play without requiring a click; intervention should be strategic, not janitorial.

## 15. Alien civilization and reverse engineering

Working name: **the Veyr Continuance**. Earth is targeted by an autonomous expeditionary seed tasked with securing compatible matter and containing uncontrolled replicators. Early biological troops are engineered maintenance organisms, not necessarily the alien founders. The local Core Node is an industrial command centre, repair archive and communication endpoint.

Alien asymmetry: fewer multifunctional chassis, modular adaptation, high precision but fragile specialized inputs. Humanity initially has cheap distributed labour and repairable mass production. Neither faction simply copies the other's roster with a damage bonus.

| Conflict scale | Alien development | Human response / discovery |
|---|---|---|
| Earth landings | Survey drones, symbiotic infantry, walkers, focused-energy weapons | Crossfire, dispersed industry, capture intact control modules. |
| Earth escalation | Siege organisms, thermal shields, airborne harvesters, logistics raids | Ammunition diversity, interceptors, deceptive power profiles. |
| Solar interdiction | Orbital suppressors, carrier foundries, autonomous boarding machines | Launch redundancy, mobile orbital industry, independent supply caches. |
| Interstellar frontier | Seed fleets, relativistic interdiction, machine ecologies | Local autonomy, long-range sensing, disruption of repair standards. |
| Stellar war | Collector sieges, stellar siphons, megastructure weapons | Distributed collectors, counterforce and protected manufacturing. |
| Galactic conflict | Competing Continuance lineages with different doctrines | Diplomacy and alliances become possible; identify a wider replication crisis. |
| Cosmic crisis | Survivors trying incompatible ways to escape isolation and free-energy decline | Coalition, refuge engineering or speculative intervention. |

Alien tech also has facilities, costs and prerequisites. Early expedition reinforcements come from a visible off-map orbital budget; they do not imply that a damaged local refinery magically produces infinite troops. Destroying relay infrastructure reduces support, with exact effects shown.

Reverse engineering pipeline: secure wreck/site → transport intact sample → quarantine/characterize → interpret with domestic scientific prerequisites → prototype a compatible adaptation → manufacture locally. Loot grants evidence, not an instant production-ready antimatter reactor.

Evidence is typed (materials, control, biological, field physics) and persistent. Destructive testing consumes a physical sample but retains recorded results. The catalogue permits an alien-material route to a domestic armour prototype; the independent test route is slower but cannot be permanently blocked by poor salvage drops. Duplicate samples give bounded throughput aid, not unlimited stacking bonuses. Captured control systems can introduce reliability liabilities that are disclosed and can be removed through validation work.

## 16. Enemy AI and wave director

Use four deterministic layers:

1. **Strategic planner:** selects goals, production doctrine and research based on resources, mission stage and observed outcomes.
2. **Operational planner:** chooses routes and targets using defence geometry, supply vulnerability and travel time; assigns formations and reserves.
3. **Tactical controllers:** range management, target priorities, retreat, escort, suppression and ability use.
4. **Wave director:** schedules expeditionary reinforcements and pressure windows, respecting mission and economic budgets.

Shared visible battlefield information is allowed; the AI cannot inspect unissued human orders, future random values or private research choices. A doctrine observation updates every 30 seconds; a selected composition locks when production begins. Adaptation must be visible and slow enough to counter-counter. Difficulty changes planning quality, coordination, explicit support budgets and reaction interval; any bonuses are listed.

Example target score: exposed_value × strategic_importance × route_survival / (travel_time + resistance + sustainment_cost). Use fixed-point bounded terms and stable ID tie-breaking. Score candidates on a schedule and cap searches per tick. An influence map estimates firepower, anti-air, supply and mobility separately; a single “army strength” number cannot choose sensible routes.

Wave schedule baseline: first warning at founding, first arrival near 90 seconds; next waves roughly every three minutes. Timing is a playtest parameter, not a sacred requirement. Provide a 45-second strategic warning and a visible staging area. Early reports reveal an honest broad category; exact units are visible once staged. Enemy future intentions can remain unknown without hiding current units.

Wave budget = stage support allowance + delivered local production + banked surviving reserves. Growth is bounded by scenario phase. Spend it through recipes; no free hard counter spawns beside the player. Keep 60% doctrine identity, allocate up to 30% response units and up to 10% seeded variation as an initial rule. Do not punish good performance by secretly adding health.

| Observation | Response | Human counter-counter |
|---|---|---|
| Dense walls and static guns | Siege formation with ammo escort | Raid escort, reposition mobile force. |
| Tank-heavy army | Missile teams and obstacles | Infantry screen and indirect fire. |
| Aircraft dominance | AA escorts and airfield raid | Ground push or split sortie timing. |
| One giant powered base | Telegraph orbital strike preparation | Interrupt relay, disperse, use hardened reserve grid. |
| Exposed harvest routes | Mobile raiding group | Escort, forward depot, alternate route. |

Prevent endless compound escalation: waves obey maximum active threat and stage budgets. A destroyed Core Node stops local wave dispatch immediately. Already launched forces can retreat or remain as a short cleanup objective, but cannot cancel the achieved campaign milestone. Accessibility difficulty permits longer intervals and explicit recovery windows; never silently invent a hidden difficulty scale.

## 17. Megastructures

Every project has survey, foundation, pilot, expansion and commissioning phases; phases consume materials and specialized work, expose useful partial output where appropriate, and cannot refund spent effort. Project UI shows percentage of regional capacity committed, missing supply chains and military exposure. Mothballing costs less upkeep but can degrade unprotected components predictably.

| Project | Prerequisite chain | New capability | Cost/counter |
|---|---|---|---|
| Lunar elevator / later Earth elevator | Tethers, orbital mechanics, materials; Earth tether demands a higher material assumption | Continuous lift replacing some launches | Anchor defence, cable repair, throughput limit. |
| Orbital ring | Orbital manufacturing, active stabilization, power | Massive transport and defended orbital platforms | Continuous control and maintenance; segmented failure containment. |
| O'Neill habitat | Closed ecology, rotating structures, shielding | Independent populations and industry | Volatiles, radiation mass and maintenance. |
| Dyson swarm | Autonomous orbital factories, collector logistics | Capture a growing fraction of stellar output | Collector replacement, transmission and waste heat. |
| Matrioshka computing shells | Swarm infrastructure, reversible computing, thermal cascades | Layered compute service at different temperatures | Radiator area, signal latency, redundancy. |
| Star lifter | Plasma control, collectors, stellar observation | Extract usable stellar material | Separation energy and stellar stability reserve. |
| Stellar engine / Shkadov-style array | Collector control, orbital dynamics | Slowly change routes and refuge geometry | Very long commitment, exposed infrastructure. |
| Planet disassembly | Mass drivers, autonomous industry, environmental policy | Bulk material for habitats and infrastructure | Loses the planet and existing habitability; irreversible confirmation. |
| Artificial worlds | Bulk material handling, habitat ecology, long-term stabilization | Tailored habitation and industry | Extreme work budget and continuing support. |
| Black-hole plant | Astrophysics, accretion control, high-temperature materials | High-output conversion or finite spin extraction | Feedstock, radiator fields and orbital stability. |
| Galactic relay network | Local autonomy, astronomy, reliable standards | Coordinate sectors despite delay | Relay defence, bandwidth and time-stamped state. |
| Paired wormhole gates (optional) | Exotic-stress and stable-throat postulates | Change network connectivity | Conventional endpoint delivery, finite transfer, energy and blockade. |

A rigid Dyson shell is not the default. Visually spherical distributed swarms deliver the fantasy without pretending that a solid shell is ordinary construction.

## 18. Campaign, milestones and victory

| Chapter | Play objective | Persistent gain |
|---|---|---|
| 1 Hold the Line | Found industry and survive the opening assault | Veteran crews, basic economy, captured evidence. |
| 2 Break Dawnshield | Destroy the Earth Core Node using a sustainable combined-arms push | First-stage victory, local invasion map and orbital relay coordinates. |
| 3 Reclaim the Sky | Defeat Solar staging infrastructure and keep Earth supplied | Multiple economic centres and orbital sovereignty. |
| 4 The Long Signal | Triangulate origin evidence from several sites | Choice of expedition routes and first alien political context. |
| 5 The Second Sun | Establish a self-supporting interstellar settlement | Local governance and distant industry. |
| 6 The Collector Wars | Defend stellar works and defeat or negotiate with regional lineages | Stellar engineering and faction diplomacy. |
| 7 A Thousand Frontiers | Sustain a galactic federation under replication warfare | Sector governance and discovery of the wider crisis. |
| 8 The Causal Winter | Protect civilization against isolation, hostile successors and declining accessible energy | A chosen deep-time future. |

First operation defeat: loss of the designated command centre, with a clear warning and optional campaign checkpoint restart. Later theatre loss need not end the campaign if population, archives and productive refuges survive. Research survives local base destruction; a complete civilization loss requires losing all viable continuation sites.

Campaign endings: **Continuity** (durable distributed refuges), **Concord** (a functioning negotiated human/alien defence network), **Hegemony** (control key reachable strategic regions while meeting civilian survival floors), or **Cosmic Intervention** (opt-in fictional rules and a disclosed megaproject). Victory metrics require sustained conditions, not momentary ownership on the last frame. No ending requires exterminating every entity in a procedurally enormous universe.

The cosmic threat has a physical foundation—causal isolation and available free energy—and an authored antagonist: competing survival systems whose expansion threatens others. Avoid claiming heat death occurs in a few million years; the crisis is planning and competition over deep-time survival, with later narrative timescales as needed.

## 19. Replayability and procedural design

Seed geography, deposit placement/grades, route geometry, alien doctrine, salvage opportunities and strategic site distribution. Hand-author the learning curve, scientific prerequisites, landmark missions and minimum viable openings. Procedural generation changes decisions; it never randomizes away the sole prerequisite needed to win.

Every map validator checks reachable starting deposits, room for essential structures, at least two strategically distinct approach routes, attainable research evidence and a traversable counterattack. Strategic generation checks connected feasible expansion routes under the selected physics ruleset. Expose seed and modifiers. Same seed + same inputs + same ruleset/content version must replay identically.

Challenge variants: scarce fuel, fractured power grids, early air pressure, dispersed deposits, salvage-rich ruins, independent alien lineages, biological-only civilization, no-gate causal campaign. Optional endless defence is separate from the campaign; its unbounded escalation cannot determine campaign balance.

## 20. UI/UX architecture and RTS controls

Top bar: relevant stocks, grid delivered/requested power, reserved industrial work, workforce, supply and next wave. Hovering any deficit names the responsible producers/consumers and gives a map focus action. Avoid a misleading stockpile-only electricity icon.

Bottom left: minimap, strategic-layer breadcrumb and alert queue. Bottom centre: selected formation/building, health, ammunition, fuel, supply path and current order. Bottom right: contextual Build / Units / Orders / Science / Logistics deck. Costs show materials, work, power and prerequisites together. Queues show why they are stalled. Map overlays are mutually composable but limited to three visible layers by default.

Research view is a zoomable semantic graph: close view shows nodes and facilities; medium view shows scientific domains and dependency bundles; far view shows eras and transformation milestones. A “path to capability” command highlights the shortest feasible prerequisite route **including construction and evidence**, not merely technology nodes. Filters: available, planned, blocked, implemented, physics category and strategic effect. Unknown alien functions are visibly unknown, never falsely labelled discovered.

Controls: left click/select, drag box, Shift add, right-click contextual order, Shift queue, A attack-move, S stop, H hold, Ctrl+number assign group, number select, double-tap focus, Tab cycle subgroup, F focus, Home headquarters, middle drag/WASD pan, wheel zoom, Q/E camera rotate where not bound to ability. Preserve existing key bindings through a remappable profile; do not silently reuse current H/Q/E actions. Commands bind by action IDs, with conflict detection. A separate strategic-mode profile exposes route/formation tools. Touch uses a radial order menu and explicit queued-order toggle.

Control-group membership is stable through upgrades and aggregate/tactical transitions. Context order previews its interpretation before confirmation. Destructive megaprojects, colony abandonment and population-substrate migration receive in-game impact confirmation; ordinary construction does not.

Accessibility: scalable text, remapping, colour plus shape for factions and supply states, screen-reader-friendly strategic summaries where practical, adjustable warning timing, reduced motion, high-contrast projectile indicators and pauseable single-player command planning. No key information depends on colour, sound or tiny icons alone.

## 21. AI shared with player automation

The human-assistance planner and enemy planner use common action validators, route evaluators and budget accounting, with different goals and observation access. Do not implement enemy success by bypassing logistics.

Planner inputs: immutable snapshot, doctrine, reserved budgets and blackboard goals. Outputs: bounded commands with desired execution tick and reason codes. Simulation validates them identically to player input. No generative model or network request belongs in the deterministic authoritative tick; optional offline narrative tools cannot control combat outcomes.

Testing scenario families: exposed convoy, tank line against prepared AT, air strike into AA, artillery ammunition starvation, generator loss during research, interrupted counterattack, multi-front reserve use and convoy reroute after gate loss. Measure decision quality against explicit objectives and budgets; a high win rate alone can conceal cheating or poor player experience.

## 22. Technical architecture

Preserve Rust as the authoritative simulation, fixed-point state, input-log replay, stable entity IDs and data-driven balance. Godot remains presentation and input. Rendering interpolates snapshots and may use floats; it never computes economic truth. See [roadmap audit](ROADMAP.md) for current mismatches.

Proposed modules, introduced incrementally:

```text
core/game/economy/       inventory, reservations, recipes, jobs, population
core/game/power/         graph, allocation, storage, heat
core/game/logistics/     routes, cargo, depots, transfer events
core/game/research/      capability graph, evidence, projects, prototypes
core/game/combat/        weapons, targeting, supply, cohorts
core/game/ai/            doctrine, director, operations, local control
core/game/campaign/      objectives, persistent knowledge, physics ruleset
core/game/strategic/     region graphs, transit, aggregation, governors
crates/data/             versioned definitions and validators
crates/server/           authoritative host, replay and headless scenarios
Godot/client            views, controls, graph UI, audio and accessibility
```

Do not rewrite `sim.rs` into all these modules in one change. Extract one tested responsibility at a time behind existing commands. Add optional scenario rules while old replays remain associated with their old simulation version.

Stable identifiers: `TechId`, `RecipeId`, `CapabilityId`, `ResourceId`, `RegionId`, `ProjectId`. Author content with immutable string IDs; compile to a sorted dense registry for runtime. Registry and content hash are part of saves and replay headers. Display era/order is metadata, never an ID encoding. Valid effects are typed operations, not arbitrary strings executed by the core.

A runtime research record references prerequisites, scenario-granted knowledge, lab capabilities, evidence clauses, typed effects and prototype recipes. The delivered JSON catalogue is an authoring prototype; prose effects require explicit bindings before runtime loading. A `ContentStatus` distinguishes design-only / implemented / deprecated so unavailable features cannot masquerade as playable unlocks.

Canonical tick sequence:

1. Validate and order commands by tick, player, sequence.
2. Apply ownership changes and scheduled arrivals.
3. Resolve power/network capacity and resource reservations.
4. Advance industrial/research jobs and consume inputs.
5. Update movement, supply transfers and weapon readiness.
6. Resolve targeting, projectiles, damage, wrecks and deaths.
7. Reconcile population, objectives, wave scheduling and AI planning budgets.
8. Publish events and hash all authoritative state.

Economy systems can update every 30 tactical ticks at the existing 30 Hz baseline; their next-update ticks and remainders are authoritative. Strategic events are scheduled on the same integer timeline. Threading may calculate immutable candidate results in parallel later, but commit order is stable. Wall-clock time never decides outcomes.

Scale-safe arithmetic: local stocks use checked integer/fixed-point units. Strategic quantities use explicit unit metadata and checked wide integers (e.g. i128 base quantities) with a documented maximum; do not silently multiply solar masses into a narrow tactical fixed-point field. Display switches units, while transfers use exact rational conversion and retained remainder. No floating logarithms determine authoritative progression. Saturation signals a content error rather than silently generating capped resources.

Saves include ruleset, simulation version, content hash, ID registry, clock, RNG stream state, all queues, reservations, route cargo, manifests and authority ownership. Support explicit migrations for released schemas; do not reinterpret a legacy 500-bit research array under new names. Replays are pinned to compatible version/content, or report incompatibility clearly.

Bridge snapshots carry schema/version, event sequence and rational units. Commands return accepted/rejected with reason and command ID. Clients never silently predict stock ownership. Extend the existing bridge first, then move transport behind a stable interface; network transport and matchmaking are separate delivery work from lockstep mathematics.

Performance targets to measure on a named baseline desktop before promising them: 30 simulation ticks/s, under 10 ms p95 simulation tick for 500 tactical units and 200 buildings; 60 fps UI where hardware permits; 10,000 aggregate regions under 100 ms per strategic update. First benchmark current code. Spatial grids, cached routes, dirty power components, bounded planner work and event-driven distant regions should carry initial optimization. Do not claim billions of continuously simulated stars.

## 23. Design acceptance and failure prevention

Success is demonstrated by playtests, not the size of the graph. A first-time player should identify a stalled factory's cause within ten seconds, execute a retreat reliably, understand why a wave won, and choose between two useful research directions before the third major wave.

Reject designs that produce: research timer races independent of infrastructure; instant global retrofits; costless matter synthesis; identical alien/human rosters; unavoidable invisible counters; automatic enemy scaling that erases player advantage; camera-driven duplication; infinite gate throughput; universal new-era stat inflation; or mandatory speculative science presented as fact.

Track opening viability, time to first combat, time to field each role, percentage of production stalled by cause, research utilization, convoy losses, defence/mobile spending, counterattack timing, player attention per region and reasons for defeat. Use results to tune; do not force an arbitrary 50% win rate for every player.
