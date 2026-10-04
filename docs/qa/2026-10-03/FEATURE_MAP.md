# Runtime feature map

- `crates/core/src/game/sim.rs`: fixed-point 30 Hz simulation, entity slots, commands, construction, harvesters, movement, combat, repair/sell, victory, state hashing. Tick order: commands → services → construction → economy → colony/LOD → research → production → waves → harvesting → movement → shields → combat → status → death cleanup → conquest.
- `earthfront.rs`: two-era ruleset, 12 live technologies, power priorities/batteries, ore processing, ammunition paths, prototype allocation, relay reinforcement and economy/combat AI.
- `map.rs`, `hex.rs`, `path.rs`, `procgen.rs`, `scenario.rs`: tiles, hex/world conversions, A*, finite deposits, generation, founding and mission configuration.
- `stats.rs`, `balance.rs`, `crates/data/balance.ron`: units/buildings/weapon profiles, costs, damage multipliers and configurable balance. Actual Godot runtime loads the data crate's default balance; test fixtures must distinguish this from `Sim::new` defaults.
- `tech_grid*.rs`, `ability.rs`, `perk.rs`, `civ/`, `planet.rs`: legacy sandbox systems; most are deliberately disabled in Earthfront. The 200 JSON catalogue entries under docs are design examples, not runtime unlocks.
- `lockstep.rs`, `crates/server/src/main.rs`: deterministic input replay and in-process lockstep demonstration. Neither proves persisted campaign saves or a deployed network service.
- `godot-bridge.rs`: authoritative process, snapshot schema 5, file command transport, fixed seed 2026, realtime pacing, deploy/restart flags. No serialization/load path found in this runtime.
- `godot3d/scripts/earthfront_3d.gd`: main scene, actual UI/input/selection/groups/camera, bridge sync, scene rendering and notifications. `continuous_terrain.gd` and `tactical_models.gd`: presentation only. GLB assets, fonts, audio and UI textures load through Godot resources. No database or external gameplay service.
- `crates/render-shell/`: alternate Macroquad native/wasm client, pause/speed, legacy meta progression. Must not assume control parity with Godot.
- `tools/ascension_catalog.py`: design graph validation; `earthfront-playtest.rs`: accelerated AI matches, not player-interface validation.

Confirmed scope: Earth tactical game, 2 eras, 12 live projects. Solar/galactic/cosmic layers, megastructures, demographic evolution, physical fuel logistics and a campaign save/load interface are not implemented in the primary client. Report as coverage limitations/product gaps.
