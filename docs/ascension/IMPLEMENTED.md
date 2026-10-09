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

Godot: the arrow keys pan (so do the cursor at a screen edge and a middle-button drag), Z/E rotates, wheel zooms, F focuses selection, Home returns to base. Left-click or drag selects; right-click issues contextual orders; A issues attack-move (an on-screen banner shows it is armed; right-click the destination, Esc or the roster's Cancel button disarms); the structure panel's Set rally button arms the next left click as the rally point (no new key); F2 selects the whole army; Ctrl with 1 to 9 saves a control group and 1 to 9 recalls it; Esc (with nothing armed) opens the pause menu, which really stops the simulation (the client writes `pause.flag`, the bridge skips stepping while it exists) and offers Resume, Controls, Terrain guide (the ground table as cards), Settings (volumes, fog of war, window mode), Restart mission (returns to the title with a fresh mission) and Quit game, the last two after a confirmation; M opens the strategic map (the real ground layer, regions, borders and the expected wave route; the simulation keeps running; Esc or M closes it); F1 opens the controls reference, which lists exactly the keys in `godot3d/scripts/ui/keybinds.gd`; . selects the next idle crew and centres the camera on it. Use Build, Units, Orders and Science panels for the full roster. U repairs and Delete sells. Survival has no fog of war; Kestrel Reach has a presentation-only one (2026-10-06), off with `EARTHFRONT_FOG=0`.

Kestrel Reach adds (0.2.0): `S` stops the selection, `D` holds position, `Z` cycles the stance (aggressive, defensive,
hold; the yaw is locked there, so Z does not rotate), a right click on an enemy in sight focuses fire on it, `Shift` +
right-click (after `A` too) queues up to eight waypoint legs drawn as a thin path, `Q` casts the first ready ability in the
selection at the cursor (Barrage, EMP burst, Nanite field), the Science screen sells Upgrades (weapons, armour, vitality),
a double tap on a control group number centres on it and holding `F` follows the selection. During a run's perk draft
`1` to `3` pick a perk. The README's Kestrel section lists the same.

## Kestrel Reach depth (0.2.0, branch kestrel-depth, 2026-10-07)

Kestrel Reach is the default map. A core `depth` flag, on only for the hosted Kestrel match, gates every rule below, so
Survival, the lane maps and classic Kestrel keep their pinned hashes (golden 2081234273307305018, Survival(7)
1622883436588820810, classic Kestrel 2849524003663712283).

- **Combat orders.** Units auto-acquire inside range + 3 and leash 6 tiles; units at rest spread apart; Stop, Hold
  position, stances and focus fire; Shift-queued waypoints (eight legs a unit); waves breach walls through a weighted path
  and lay siege behind Tanks once three or more walls block them; Anti-armour teams hit aircraft (80%).
- **Abilities and Upgrades.** Battle tank Barrage (after Precision Manufacturing), Gunship EMP burst, Capital unit
  Nanite field (the Capital trains at a Vehicle factory from era 2). Upgrades cost 150 + 100 a level in money, three
  levels a track in era 1 and six from era 2.
- **Economy.** Each Refinery costs 50 more than the last; repair heals over time (150 ticks, a tenth of the price, at
  least 25) with a 450-tick cooldown.
- **Waves and the Core Node.** A ten-row wave table (6 + 2 units a wave, capped at 24, plus 2 per working relay), a
  seeded doctrine order from wave 5, an elite wave 6 led by a Capital, alien raids, and an alien AI that plays from tick 0
  but buys no Upgrades and makes no raid before wave one. The Core Node takes no damage until both relays have fallen and
  wave 6 has spawned.
- **Difficulty and seed.** Easy / Normal / Hard: 1,500 / 1,200 / 1,000 credits, first wave at 5,400 / 4,500 / 3,600
  ticks, then every 6,300 / 5,400 / 4,500, waves 75% / 100% / 125%. The seed is shown, typed or set to the UTC date (Daily
  seed); Restart reuses both.
- **Score.** 500 a cleared wave + the value of enemy losses - half the value of your own + on a win a tenth of the ticks
  left before 45,000 (+1,000 for a run), times 0.75 / 1 / 1.5 by difficulty, floored at 0. Grades S 24,000, A 16,000,
  B 10,000, C 5,000, else D. Bests per map and difficulty in `user://records.cfg`.
- **Run mode.** Twelve waves to hold; a seeded three-perk draft after each cleared wave (the bridge pauses meanwhile);
  8 of 12 perks at first, one more unlocked by reaching wave 6 in a run.
- **Replays.** RPL1 files in `user://replays` (header, accepted orders by tick, a final END line with tick, hash and
  score). The Replays list shows the newest eight; the viewer plays at 0.5x to 8x and sends no orders. `verify-run`
  re-simulates a file: MATCH (exit 0), MISMATCH (exit 1), unverifiable (exit 2). It certifies consistency and score, not
  fog legality; the file is unsigned.
- **Client.** It starts its own bridge when run without `--runtime-dir=` (the exported game's path), shows building
  damage (smoke under half HP, fire under a quarter) and working puffs, an onboarding coach (five lessons), a stance chip,
  path markers and the Core Node's shield ring. Music hooks pick menu, calm, combat (8 s hold), victory or defeat, but no
  track exists, so nothing plays.
- **Release.** Version 0.2.0; Linux and Windows x86_64 export presets and `tools/release/package.sh`. No export template
  build, Windows build or itch upload has been done (see `docs/release/itch-checklist.md`).

Automated outcomes (the hosted playtest AI on seed 3, Normal unless noted; not human balance): Normal win at tick 32,857
after 6 waves (about 18 minutes), Easy win 39,366, Hard overrun 17,738 after 4 waves; an undefended base falls at 4,951
(Normal). Run mode: seeds 3, 1, 2, 7 and 11 win all twelve waves at about 64,300 ticks; seeds 5 and 2026 are overrun
after 10. In the Task 30 scripted playthrough (the real client and its own bridge, Normal, seed 1851371552) a simple
scripted defence holding the home approach west of the ford cleared five waves and lost at tick 32,196 (17:53), score
6,220, grade C; `verify-run` on its replay printed MATCH. All of it is software-rendered and unheard; no person has
played the 0.2.0 build.

## Technical boundaries

The ruleset lives in `crates/core/src/game/earthfront.rs`, integrated with the deterministic simulation. The Earthfront project registry is separate from the legacy sandbox technology grid. Snapshot schema 5 carries economy services and construction geometry. The native shell and Godot remain presentation/input clients. Both show prototype queue reservations; Godot also shows local ore capacity and depot ammunition. The native tank hotkey no longer opens planetary governance in Earthfront.

Implemented electricity uses a shared faction grid, not simulated cables. Supply uses local path connectivity and abstract distribution, not individually routed trucks, fuel or spare-part inventories. Crew is support capacity rather than a demographic simulation. Research deployment is represented by factory prerequisites and prototype reservations; individual industrial retrofits are future work. Some new buildings reuse existing artwork.

Planetary governance, interstellar travel, cosmic warfare, the full 200-technology catalogue and population evolution are design content, not accessible campaign systems. The legacy sandbox remains available separately. Current balance is a prototype: automated victory is possible within minutes; a polished 25-40 minute human mission requires further playtesting.

## Reproducible verification

- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo check -p rts-core -p rts-render-shell --target wasm32-unknown-unknown`
- `cargo run -p rts-server --bin earthfront-playtest -- 2026`
- `python3 -m unittest discover -s tools -p 'test_ascension_catalog.py'`

Core tests exercise conservation, power loss, research infrastructure, production roles, ammunition, severed supply, prototype competition and deterministic replay. The automated playtest reports seed, progression, waves, outcome and state hash. These checks do not replace human balance and usability testing.

## Industrial follow-up validation

The bounded-storage and single-factory prototype pass passed 272 workspace tests (one existing balance test remains ignored), strict Clippy, wasm compilation and Godot editor parsing. Three accelerated AI matches (seeds 2026, 3 and 42) reached human Core Node victories in 397, 412 and 414 seconds respectively. These are automated outcomes, not evidence of target mission pacing or human difficulty balance.

New regression cases cover partial unloading without loss, a destroyed receiving refinery, one reserved factory alongside continuing tank production, reassignment after factory destruction, and the boundary between parallel theory and serial physical validation.

## Relay assault follow-up

The Earth operation now includes two relay outposts, each guarded by a gun turret, anti-air battery and anti-armour team. The original 90-second grace period and three-minute wave interval remain. The first wave contains up to ten units with both relays operating, or six without them; later base escalation is capped at 24 plus relay support, with the existing active-force ceiling still applied. Wave strength is support capacity, not a damage multiplier.

Initial automated results: seed 2026 won at 427 seconds after destroying both relays; seed 42 won at 445 seconds; seed 3 destroyed both relays but lost its headquarters at 482 seconds. These results add an assault sequence and a meaningful defeat case, but do not meet the intended 25-40-minute mission pacing. Economy expansion and campaign balance remain unfinished.

Relay tests cover actual wave counts with and without power, destruction, reuse of an entity slot by an ordinary depot, deterministic role hashing, and Core victory while a relay survives. Relay identity is a scenario role on the authoritative entity, never inferred from its name or model.

Validation for the relay pass: 274 workspace tests passed (one existing balance test ignored), strict Clippy and wasm checks passed, and the Godot visual smoke test exited successfully after battlefield and science captures. The optional-objective HUD was inspected at 1440×900.
