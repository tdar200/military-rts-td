# Industrial Earthfront: implemented vertical slice

Launch from the repository with `./run-3d.sh`. The script builds the authoritative Rust bridge and launches the Godot client. This is the playable two-era foundation; the other eight eras remain future milestones.

## What changed

- A fully visible Earth battlefield with finite ore, harvesters and refinery delivery buffers. Refineries consume ore to manufacture construction material; depleted deposits force expansion. Each refinery holds 300 ore. Loaded harvesters choose a processor with free storage, deliver only what fits and keep any excess cargo until processing frees space.
- Electricity is a service budget, with generation, demand, priority allocation and brownouts. Batteries provide finite storage with charging losses. Defences and construction receive priority over industry and research.
- Construction requires territory within ten tiles of a completed command centre, refinery or supply depot. The placement preview reads authoritative construction tiles.
- Barracks train infantry and anti-armour teams. Vehicle factories produce tanks; refineries produce replacement harvesters. Airfields produce aircraft. Production needs electricity, material and available crew capacity. Queues are limited to eight entries.
- Units carry finite ammunition. Command centres and supply depots manufacture replacement rounds from material and distribute them over short traversable routes. Walls and terrain can sever these routes. Empty units must retreat or receive a forward depot.
- Twelve projects cover guided anti-armour, vehicle tooling, aircraft, air defence, batteries, field supply, precision manufacturing, robotics, AI-assisted science, smart grids, autonomous supply and industrial resilience. Projects require prerequisites, funded experiments and powered laboratories. Advanced prototype work reserves exactly one completed vehicle factory (the oldest surviving works), leaving other factories available for military production. Destroying it transfers the reservation to the next works; without a powered works, progress pauses. AI compute accelerates theory, while prototype validation is limited by factory and laboratory power. Parallel laboratories cannot skip the prototype stage.
- Robotic workcells mark the second era. Technology unlocks specialised infrastructure and changes throughput, storage or supply rather than granting universal era damage bonuses.
- Alien waves announce and commit their doctrine 45 seconds before arrival. Observed walls, armour and aircraft influence siege, anti-armour and interdiction choices. Supply raids threaten the economy. First arrival is 90 seconds after founding; subsequent waves are three minutes apart.
- Two defended invasion relay outposts screen the Core district. Each powered relay adds two units to every expedition and supplies nearby alien forces. Destroying a relay permanently removes that contribution; cutting power temporarily disables it. Ordinary replacement depots cannot restore expedition capacity. Both targets are optional: a direct Core assault can still win. The AI prioritises relays before the Core, and the Godot HUD labels them and reports their operational count.
- Core Node destruction wins; losing your headquarters loses. The AI builds an economy, researches, fields mixed forces and retreats for ammunition using ordinary commands and budgets.
- Both clients understand the new buildings and research. The Godot interface displays power balance, stored energy, ore buffers, ammunition, crew, production and infrastructure-dependent research progress. Science shows all twelve projects and their dependencies.

## Controls

Godot: WASD pans, Z/E rotates, wheel zooms, F focuses selection, Home returns to base. Left-click or drag selects; right-click issues contextual orders; A issues attack-move. Use Build, Units, Orders and Science panels for the full roster. U repairs and Delete sells. Traditional fog of war is absent.

## Technical boundaries

The ruleset lives in `crates/core/src/game/earthfront.rs`, integrated with the deterministic simulation. The Earthfront project registry is separate from the legacy sandbox technology grid. Snapshot schema 5 carries economy services and construction geometry. The native shell and Godot remain presentation/input clients. Both show prototype queue reservations; Godot also shows local ore capacity and depot ammunition. The native tank hotkey no longer opens planetary governance in Earthfront.

Implemented electricity uses a shared faction grid, not simulated cables. Supply uses local path connectivity and abstract distribution, not individually routed trucks, fuel or spare-part inventories. Crew is support capacity rather than a demographic simulation. Research deployment is represented by factory prerequisites and prototype reservations; individual industrial retrofits are future work. Some new buildings reuse existing artwork.

Planetary governance, interstellar travel, cosmic warfare, the full 200-technology catalogue and population evolution are design content, not accessible campaign systems. The legacy sandbox remains available separately. Current balance is a prototype: automated victory is possible within minutes; a polished 25–40 minute human mission requires further playtesting.

## Reproducible verification

- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo check -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`
- `cargo run -p rts-server --bin earthfront-playtest -- 2026`
- `python3 -m unittest discover -s tools -p 'test_ascension_catalog.py'`

Core tests exercise conservation, power loss, research infrastructure, production roles, ammunition, severed supply, prototype competition and deterministic replay. The automated playtest reports seed, progression, waves, outcome and state hash. These checks do not replace human balance and usability testing.

## Industrial follow-up validation

The bounded-storage and single-factory prototype pass passed 272 workspace tests (one existing balance test remains ignored), strict Clippy, wasm compilation and Godot editor parsing. Three accelerated AI matches—seeds 2026, 3 and 42—reached human Core Node victories in 397, 412 and 414 seconds respectively. These are automated outcomes, not evidence of target mission pacing or human difficulty balance.

New regression cases cover partial unloading without loss, a destroyed receiving refinery, one reserved factory alongside continuing tank production, reassignment after factory destruction, and the boundary between parallel theory and serial physical validation.

## Relay assault follow-up

The Earth operation now includes two relay outposts, each guarded by a gun turret, anti-air battery and anti-armour team. The original 90-second grace period and three-minute wave interval remain. The first wave contains up to ten units with both relays operating, or six without them; later base escalation is capped at 24 plus relay support, with the existing active-force ceiling still applied. Wave strength is support capacity, not a damage multiplier.

Initial automated results: seed 2026 won at 427 seconds after destroying both relays; seed 42 won at 445 seconds; seed 3 destroyed both relays but lost its headquarters at 482 seconds. These results add an assault sequence and a meaningful defeat case, but do not meet the intended 25–40-minute mission pacing. Economy expansion and campaign balance remain unfinished.

Relay tests cover actual wave counts with and without power, destruction, reuse of an entity slot by an ordinary depot, deterministic role hashing, and Core victory while a relay survives. Relay identity is a scenario role on the authoritative entity, never inferred from its name or model.

Validation for the relay pass: 274 workspace tests passed (one existing balance test ignored), strict Clippy and wasm checks passed, and the Godot visual smoke test exited successfully after battlefield and science captures. The optional-objective HUD was inspected at 1440×900.
