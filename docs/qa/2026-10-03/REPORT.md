# Earthfront end-to-end QA — 3 October 2026

## Executive Summary

**Release assessment: not ready for a claim of complete RTS/civilization-scale functionality.** This investigation ran the rendered game, drove real viewport input, reproduced simulation and UI defects, fixed confirmed localized defects, and measured long-run correctness and scaling. The implemented product is an Earth tactical slice with **two eras and 12 runtime technologies**. The 200-entry future technology catalogue is design data, not 200 playable unlocks.

A fresh UI campaign completed successfully; the final restart regression and second fresh campaign are tracked below. Passing automated tests does not close the remaining formation, performance, persistence and UI gaps. No claim is made that every possible defect has been found.

## Test Environment

- Ubuntu 24.04, Linux 7.0.0-38; Intel i5-11260H (6 cores / 12 threads); approximately 62 GiB RAM.
- Godot 4.7.2 stable, OpenGL Compatibility renderer; Rust release bridge; 30 Hz fixed-point simulation; snapshot schema 5; seed 2026 for player campaigns.
- Initial rendered test: Intel UHD TGL GT1, Mesa 25.2.8. NVIDIA selection initially failed through the default GL path.
- Corrected rendered test: NVIDIA RTX 3050 Laptop GPU, 4 GiB VRAM, driver 580.178.04, PRIME offload. `nvidia-smi` confirmed the Godot graphics process using 174 MiB in one sample.
- Primary interactive viewport 1440×900. Separate software-rendered layout captures at 1920×1080, 2560×1440, 3840×2160 and 3440×1440. Software layout results are not NVIDIA performance measurements.
- Build base: `b0757db50737ea3ba7f7b44cde6b61ff32780335` plus a pre-existing, heavily modified working tree. [Baseline status](evidence/baseline-status.txt) preserves that distinction. No commit or release was created.
- Other applications were active on the workstation; timings are observations, not isolated laboratory guarantees. CPU hardware sampling was denied by `perf_event_paranoid=4`; see [profiler restriction](evidence/perf-run.log).

## Test Coverage

The [feature map](FEATURE_MAP.md) and [test matrix](MATRIX.md) were created before the main suite. [Machine-readable matrix](matrix.json) records coverage and limitations.

Executed: real deploy/build/research/production controls; selection and control groups; terrain picking; modal input; material costs; finite extraction and full buffers; power prioritization and battery rounding; ammunition depletion and replenishment; research interruption/prototypes; factory queues and blocked exits; combat counters, range and time-to-kill; relay/wave tests; victory/loss fixtures; deterministic command storms; long-run economy; sustained and casualty-heavy scale measurements; rendered layout and GPU comparisons.

Not equivalent to full coverage: all strategic AI exploits, every map geometry, every possible build order, every simultaneous command permutation, 8 hours of continuous combat, and physical GPU utilization/VRAM under a 10,000-model battle. Missing features are not marked passed.

## Player Journey Result

Exploratory UI play verified that losing a research laboratory pauses work, rebuilding restores the route to progress, and unattended/light defenses can lose infrastructure. A later run retained the same simulation while its renderer was switched to NVIDIA; that run is exploratory, not the final untouched campaign.

The final fresh run uses `tools/qa/campaign_player.py` and `ui_driver.gd`: snapshots are read only, while actions enter through viewport mouse/key events. It does not call simulation commands, create units, change resources, skip timers, or enable human AI. Synthetic fixtures used elsewhere are explicitly separate.

**Completed fresh campaign:** tick **21,642** (721.4 simulated seconds), winner human, **12/12 technologies**, second era, four waves encountered. All eleven human buildable types were placed over the run, and infantry, anti-armour, tanks and aircraft participated in the final 50-unit attack-move. Final state hash **11859179164159499449** remained unchanged after post-victory build/train/research input. See [victory screenshot](evidence/final-campaign/victory.png), [player actions](evidence/final-campaign/journey.jsonl) and [terminal comparison](evidence/final-campaign/terminal-verification.json).

An additional fresh run is in progress after the localized restart-marker fix. UI automation was refined during testing; those changes issue normal mouse/keyboard input and do not alter simulation state.

## Critical Bugs

### QA-001 — Repeated sale creates unlimited material — FIXED

- **Severity/System:** Critical / economy and commands.
- **Reproduce:** Submit 100 `Sell` orders for one live generator before death cleanup.
- **Expected/Actual:** One 50-material refund; observed 5,000 material.
- **Frequency/State:** Deterministic, same-tick command batch; fresh controlled fixture.
- **Evidence:** [Failing reproduction](evidence/adversarial-before.log), [passing regression](evidence/adversarial-after.log).
- **Cause/Fix:** Sold entities retained `alive` until cleanup. Sales now reject zero-HP entities; Earthfront removes dead structures before services run.

## High Priority Bugs

| ID | System / title | Reproduction and expected vs actual | Evidence, cause and disposition |
|---|---|---|---|
| QA-002 | Repair resurrects a sold building | Sell then repair in the same batch. Expected rejection; actual restored HP for a small repair charge. Deterministic. | [Before/after](evidence/adversarial-before.log). **Fixed:** repair rejects zero HP; regression verifies no second charge or resurrection. |
| QA-003 | Simulation continues after victory | Remove Core, then step with economic commands and hostile survivors. Expected immutable terminal state; actual hash/state changed. Deterministic. | [Before](evidence/adversarial-before.log). **Fixed:** Earthfront survival steps return once a winner exists. Tests also cover loss, mutual destruction and four weapon types. |
| QA-004 | Command file race loses orders | Concurrent writer/reader exchange 1,000 orders. Expected 1,000; actual 950. Reproduced once before fix; timing dependent. | [950/1,000](evidence/transport-before.log), [1,000/1,000](evidence/transport-after.log). **Fixed:** primary client publishes immutable atomic command packets. Legacy append-file compatibility remains a risk for old external clients. |
| QA-005 | Authored attack period is one tick too slow | Infantry fires at stationary 50-HP flesh target. Expected sixth shot at tick 40; actual tick 45. Deterministic. | [Before](evidence/additional-before.log), [combat matrix](evidence/combat-matrix.log). **Fixed for Earthfront:** compensate for cooldown decrement convention; legacy replay behavior retained. |
| QA-006 | Refinery completion bypasses crew limit | Complete refinery at crew cap. Expected no extra crew; actual free harvester takes crew beyond cap. Deterministic. | [Before](evidence/additional-before.log). **Fixed:** included truck requires capacity; later replacements are player-orderable. No deferred free truck is promised after capacity opens. |
| QA-009 | No replacement harvester through primary UI | Lose truck; refinery remains. Expected orderable replacement; no button and parser rejects that unit type. Deterministic interface gap. | UI/bridge inspection and unit-cost tests. **Fixed:** harvester button, refinery routing and bridge parser support; actual production costs remain 140 material / 1 crew. |
| QA-010 | Factory deploys into blocked terrain | Block preferred output tile, finish infantry. Expected passable output or held queue; actual unit inside blocked tile. Deterministic. | [Failing test](evidence/spawn-before.log). **Fixed:** adjacent passable exit selection; fully enclosed factory holds paid completed order and deploys once opened, without duplicate charge. |
| QA-011 | Invalid path start crashes core API | `find_path(8×8 map, (65535,65535), (1,1))`. Expected `None`; actual index-out-of-bounds panic. Deterministic API fixture; ordinary UI reachability not established. | [Crash](evidence/path-before.log), [regression](evidence/path-after.log). **Fixed:** bounds-check both endpoints before equality/indexing. |
| QA-013 | Hybrid laptop selects slow graphics device | Launch default Godot GL client on this machine. Expected available discrete GPU selection; Intel used after NVIDIA/Mesa fallback errors, ~25 FPS in live scene. | [GPU probe](evidence/nvidia-probe.log), [comparison](evidence/gpu-comparison.json). **Fixed launcher:** PRIME offload when NVIDIA available; explicit integrated override supported. RTX run observed 42–51 FPS. |
| QA-014 | Armies collapse into one position | Order 100 infantry to one point, run 1,800 ticks. Expected useful spacing/collision; **one distinct final position**. Deterministic controlled fixture. | [Movement result](evidence/movement.log). **OPEN:** no effective unit separation/formation occupancy. Formation destinations and local avoidance need a designed solution; cosmetic path offsets are insufficient. |
| QA-015 | Large populations miss real-time tick budget | Sustain 5,000 or 10,000 live units for 900 ticks. Expected ≤33.3 ms at 30 Hz; observed p50 35.59 / 126.95 ms. | [Sustained measurements](evidence/sustained.jsonl). **OPEN:** measured scaling limitation. Do not claim 10,000-unit support from casualty-heavy tests. |
| QA-017 | Campaign save/load absent | Look for save/load UI and serialized restoration path in primary game. None exists; no recovery across process termination. | [Feature map](FEATURE_MAP.md). **OPEN product gap:** deterministic replay/in-memory clone is not campaign persistence. No save corruption claim is made because no save implementation exists. |

## Medium/Low Bugs

| ID | Severity / system | Reproduction, expected vs actual | Status / evidence |
|---|---|---|---|
| QA-007 | Medium / terrain picking | Project raised tile centers and convert pointer back. Expected same tile; original plane intersection yielded 22 mismatches among 234 sampled tiles, including offscreen samples. | **Fixed:** heightfield ray intersection. [Before](evidence/picking-before.json); clean UI asserts every sampled construction tile round-trips. Do not interpret all 22 as visible misclicks. |
| QA-008 | Medium / modal input | Open science; press P. Expected no battlefield build command; generator placement armed behind panel. Deterministic. | **Fixed:** science consumes game hotkeys except close. [Before](evidence/controls-before.json); clean run asserts unchanged build mode. |
| QA-012 | Medium / selection and entity visuals | Double-click requires matching unit type, but unit nodes lacked `kind_name`; renderer also trusted recycled IDs. | **Fixed:** populate metadata, replace mismatched kind/owner nodes, clear affected selection/group references; add shift-add and same-type double-click. [Metadata observation](evidence/reused-entity.json) proves missing metadata, not a captured recycled-model glitch. Clean control assertions verify selection. |
| QA-016 | Medium / science scroll | With completed cards under pointer, wheel over card region: later project remained clipped; wheel over scrollbar moved it and enabled selection. | **OPEN**, workaround: scrollbar. [Screenshot](evidence/gpu-campaign/research-click-investigation.png). Event propagation is suspected; cause not proven. |
| QA-018 | Medium / control parity | Space in primary Godot client: simulation continues; no pause/speed UI found. Native client has controls. | **OPEN product gap**, not a claim that an advertised Godot pause button malfunctions. [Control observation](evidence/controls-before.json). |
| QA-019 | Low / shutdown | Close controlled Godot probe: reports four ObjectDB instances and two resources still in use. | **OPEN:** [probe log](evidence/shadow-probe.log). No steadily growing live-session leak proven. |
| QA-020 | Medium / effects readability | Combat effect obscures much of HQ/nearby units in 4K layout capture. Expected readable battlefield; large opaque spheres cover it temporarily. | **OPEN visual issue:** [capture](evidence/resolution-3840x2160.png). Frequency/duration not quantified; do not infer a 4K-only cause. |

### QA-021 — Stale deploy starts the next mission behind its briefing — FIXED

- **Severity/System:** Medium / restart protocol.
- **Steps:** Leave a duplicate `start.flag` after deployment (rapid repeat/reconnecting client), then press Redeploy. Expected tick 0 and waiting briefing; actual new mission advanced before a fresh deploy.
- **Frequency/State:** Deterministic when the stale marker exists; observed reset tick 33 with cleared research/winner. This is a reconnect/duplicate-input edge case, not every normal restart.
- **Evidence:** [Before reset observation](evidence/restart-test/restart-verification.json), [process regression](evidence/restart-protocol.log).
- **Cause/Fix:** Restart removed command/restart markers but retained deploy marker. It now clears the marker too. Process regression proves waiting at tick zero, then accepts a genuinely fresh deployment.

## Economy Verification

All quantities are fixed point or integers; rounding is explicit, not a floating-point tolerance.

| Check | Independent expectation | Observed |
|---|---|---|
| Generator affordability | 99 rejects; 100→0; 101→1 material | Matches |
| 100 repeated generator sales | +50 exactly | +5,000 before fix; +50 after |
| Infantry queue cap | Eight × 50 = 400 paid; later requests rejected | Matches |
| Duplicate first research | 100 material once | Matches |
| Shared deposit extraction | 15 total available between two trucks; no negative remaining | Matches |
| Refining | Five ore becomes four material; bounded 300-ore refinery buffer | Tests and soak reconcile |
| Battery charge | 40 kW × 90% efficiency / 30 Hz; Q16 truncation each tick | Matches `30 × floor(36 × 65536 / 30)` bits |
| Deficit dispatch | 10 kW HQ generation: 8 to defense, 2 of 30 to lab | Turret full; lab 66 permille, research paused |
| Eight-hour material ledger | 100,000 + 240,000×0.8 − 1,870 research − 260 ammunition = **289,870** | **289,870**; deposit and buffer ore both zero |

Existing integration regressions also cover truck cargo retained on full/destroyed receivers, partial unloads, ammunition consumption/restoration and supply paths severed by walls. There is no physical fuel, food or multi-region resource transfer system to validate in this slice.

## Combat Verification

Controlled targets cannot return fire. First shot at t=0; DPS is sustained shot damage×30/period, while TTK is `(ceil(HP/damage)−1)×period/30`. These are canonical balance fixtures; full-game outcomes additionally depend on positioning, power and ammunition.

| Attacker → target | Damage/shot | Period ticks | DPS | Expected/actual TTK |
|---|---:|---:|---:|---:|
| Infantry → infantry | 9 | 8 | 33.75 | 40 ticks / 1.333 s |
| Infantry → tank | 3 | 8 | 11.25 | 584 ticks / 19.467 s |
| Anti-armour → tank | 38.5 | 16 | 72.1875 | 80 ticks / 2.667 s |
| Anti-armour → infantry | 11 | 16 | 20.625 | 64 ticks / 2.133 s |
| Tank → tank | 30 | 20 | 45 | 140 ticks / 4.667 s |
| Helicopter → infantry | 24 | 9 | 80 | 18 ticks / 0.600 s |

All six after-fix results match, including shot/ammunition count. Infantry fires at range 3 and does not fire at 3.01. Broader existing tests cover air restrictions, splash, target selection and deterministic combat. Accuracy/penetration are not separate randomized runtime statistics here. Artillery is not a distinct live human unit; an artillery-vs-Core test cannot honestly be marked passed.

## Technology Graph Verification

- Runtime: 12 unique, reachable nodes; no missing prerequisite IDs or cycles; each has nonempty capability data. Era advancement and factory-reserved prototypes are integration-tested.
- Design catalogue: 200 examples, validated separately by ten Python tests. This does not establish that those capabilities exist in the game.
- Contemporary/advanced-industrial runtime labels distinguish achieved/emerging concepts. No playable wormhole, artificial universe or cosmic physics mechanic exists to test.
- Scientific dependency review is limited to the authored graph and catalogue validations; this is not independent physics peer review.

## AI Findings

Observed attacks damage economic/scientific infrastructure; an exploratory wave destroyed the laboratory and forced rebuilding. Relays materially increase wave counts; power loss and destruction change actual reinforcement counts in regression tests. Composition locks before arrival and includes counters based on army/defense composition.

Four additional accelerated AI campaigns using the actual loaded runtime balance completed: seed 1 lost at 596 s; seed 3 lost at 481 s; seed 42 won at 433 s; seed 2026 won at 447 s. See [seeded results](evidence/ai-seeds.log). These are one mixed AI policy across seeds, not eight independently authored strategies.

The UI campaign and finite deterministic fixtures do not prove robust strategic intelligence. No completed exhaustive kiting, maze, unreachable-base or eight-strategy balance tournament is claimed. Ground-unit stacking is an exploitable combat geometry weakness. Wave attackers have a bounded crew budget; intentional cap-limited zero reinforcement is different from an AI stall.

## Performance Results

Sustained same-faction fixtures maintain their initial unit count for 900 ticks. First 100 units receive movement orders. Dense positioning and service/target work remain enabled; this is headless simulation, not a 10,000-model render benchmark.

| Live units | p50 tick ms | p95 tick ms | Worst tick ms | RSS before→after KiB |
|---:|---:|---:|---:|---:|
| 100 | 0.047 | 0.066 | 3.382 | 2,624→2,936 |
| 1,000 | 2.292 | 3.217 | 5.424 | 2,824→3,136 |
| 5,000 | 35.592 | 46.248 | 55.875 | 3,740→4,008 |
| 10,000 | 126.950 | 170.722 | 324.694 | 4,736→5,280 |

Largest tested sustained population comfortably meeting the simulation budget: **1,000**. The threshold between 1,000 and 5,000 was not bisected. Separate casualty-heavy 10,000-unit combat produced a 168 ms spike and quickly dropped to 1,457 survivors; it is not evidence of sustained 10,000-unit performance.

Rendered live scene: Intel roughly 25 FPS; NVIDIA observed 42–51 FPS after device correction. Representative NVIDIA last-600-frame median 19.44 ms, p95 34.33 ms. GPU choice matters, but the frame budget is still inconsistent. Camera/state/background workload and differing frame caps prevent interpreting this as an exact controlled speedup ratio.

A fixed-scene shadow A/B/C probe measured 7,665 / 6,227 / 5,239 draw calls for four/two/single shadow splits, with median ~16.5–16.9 ms in all three. No meaningful frame-time gain justified degrading shadows. Detailed CPU sampling was unavailable. Test-only subsystem timing on a denser 5,000-unit arena measured 100 calls each: combat 14,889,445 μs, services 9,288 μs, production 1,329 μs, movement 1,559 μs and harvesting 1,978 μs. **Combat targeting dominates this dense fixture.** This is not the same spatial distribution as the sustained benchmark; timings must not be combined as one frame breakdown. See [subsystem profile](evidence/subsystem-profile.log). No GPU busy-percent or peak renderer memory guarantee is claimed.

## Long-Run and Determinism

Two independent eight-hour-equivalent runs (864,000 ticks each) matched checkpoint hashes exactly:

| Simulated duration | Hash |
|---|---:|
| 30 minutes | 12093851020447167491 |
| 2 hours | 14410298251575142443 |
| 8 hours | 6469179170166933901 |

Run A wall time 158.9 s, RSS 2,924 KiB at checkpoints; run B 224.6 s, RSS 2,932 KiB. Final 164 entities, all 12 technologies, era 1 (second era), 28,800 stored kJ. These are economy/research/movement fixtures: deposits were depleted by the first checkpoint, and they are **not eight-hour continuous combat or renderer-memory tests**. A third soak against the final simulation changes also matched all three hashes exactly: 168.9 s wall time, 3,032 KiB RSS at every checkpoint. See [final soak](evidence/soak-final.jsonl).

A separate 10,000-tick command storm applies movement, production, research and invalid entity actions to identical clones, comparing state hashes and nonnegative resources/crew bounds each tick. It passes. In-memory cloning is used only as a deterministic test fixture.

## Save/Load Verification

**Unavailable in the primary game.** No user save, load, serialized campaign restore or version migration path was found. Existing replay/hash tests pass, but cannot stand in for save/load during construction, research or combat. This remains QA-017.

## UX Findings

Readable main controls were observed at the four tested layout resolutions. Larger HUD panels obscure substantial battlefield space. Pointer placement now round-trips through terrain elevation. The clean run checks shift selection, same-type double-click, group assignment/recall and science modal isolation. The minimap is an overview; click-to-navigate, production cancellation, advanced formation controls, and Godot pause/speed are not all implemented. Science scrolling has the documented workaround.

## Exploits Found

Fixed: unlimited repeat-sale refunds, sale/repair resurrection, free crew beyond capacity, post-terminal economic mutation. Corrected transport and blocked-spawn errors could also distort competitive behavior. Remaining: army stacking can concentrate forces unrealistically; old append-file clients remain exposed to the legacy transport race. No claim is made that every AI or save exploit was exhaustively tested.

## Automated Tests Added

- `crates/core/src/game/qa_adversarial.rs`: refund/repair/terminal contracts, affordability, queues, research duplication, combat math, finite ore, power rounding, crew cap, graph, sealed factories, command storm, terminal weapon/tie cases, explicit release-only profile fixture.
- `path.rs`: invalid endpoint regression.
- `godot-bridge.rs`: concurrent 1,000-command transport regression.
- `crates/server/src/bin/qa-probe.rs`: casualty-heavy stress, sustained populations, movement overlap and long-run inventory/hash/RSS checkpoints.
- `tools/qa/`: isolated client launcher, viewport input driver, reusable UI client, campaign player, fixed-scene shadow probe.

Run examples:

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
python3 -m unittest discover -s tools -p test_ascension_catalog.py
cargo run --release -p rts-server --bin qa-probe -- sustained 1000 900
cargo run --release -p rts-server --bin qa-probe -- soak
cargo test --release -p rts-core qa_profile_subsystems -- --ignored --nocapture
```

## Fixes Made

Production changes are limited to the confirmed command/economy/terminal defects, Earthfront attack cadence and crew limit, passable factory exits, path endpoint validation, primary UI selection/picking/modal/live-research display, replacement harvester routing, atomic primary command packets and hybrid-GPU launcher selection and stale-deploy clearing on restart. No balance values were changed to manufacture a victory. Test harness fixes (tab handling, uppercase labels, scrollbar targeting and HUD-safe clicks) are not represented as game fixes.

## Remaining Risks

Open issues above prevent an unconditional release signoff. Missing later eras, strategic layers, megastructures, demographic paths, physical fuel and full logistics are scope gaps relative to the larger design. Malformed network protocol authority, all alternate-client controls, browser/mobile behavior, random-map coverage, full save/load, long continuous combat, true formation collision and large-model rendering remain unproven. Startup GPU fallback and shutdown resource warnings are retained in evidence rather than hidden.

## Final Regression Result

**293 workspace tests passed, zero failed; two ignored by the standard suite** (the profiling fixture was separately executed successfully). Ten catalogue tests, strict Clippy, wasm core compilation, launcher/Python syntax and process-level restart checks pass. The first clean real-input campaign won; a second fresh run after the restart fix is still in progress. A successful Core victory, if obtained, proves the available Earth slice under that run—not the ten-era game or all possible strategies.
