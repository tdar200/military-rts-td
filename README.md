# Ascension: Real-Time Science RTS

A continuous real-time strategy game inspired by the direct battlefield control
of *Age of Empires* and *Red Alert*, with civilization-scale technological
progression. Defend Earth against an alien invasion: build a base and economy,
command armies, hold the lanes with static defences, and counterattack to destroy
the alien Core Node. The playable campaign currently covers **Contemporary Humanity and Advanced Industrial Civilization**. The ten-era cosmic campaign is a design and implementation roadmap, not completed gameplay.

Earthfront has finite ore extraction, powered refining, dedicated unit factories, ammunition supply, adaptive alien waves, and twelve infrastructure-dependent research projects. Survival shows the whole battlefield; Kestrel Reach, the default map, hides unscouted ground behind a presentation-only fog of war (details below). Destroy the alien Core Node to win. Two defended relay outposts are optional targets: disabling them reduces alien reinforcements and local supply. Electricity is generation versus demand; batteries store limited reserves. Research and weapons production compete for industrial capacity.

- [Implemented gameplay, controls, validation and limitations](docs/ascension/IMPLEMENTED.md)
- [Complete game blueprint and 200-technology catalogue](docs/ascension/README.md)
- [Playable development milestones](docs/ascension/ROADMAP.md)
- [Mobile build notes](MOBILE.md)

The deterministic Rust simulation drives the Godot client, the legacy native/web Macroquad shell and the headless server.

The Godot client (`godot3d/`, started with `./run-3d.sh`) is the product: it is where the campaign, map picker, settings and all current gameplay work land. The Macroquad shell (`crates/render-shell/`, `cargo run -p rts-render-shell --bin rts`, the web build and the mobile notes) is a legacy shell kept compiling and tested, and it does not receive the Godot client's features.

## Architecture

```
crates/core/         # pure Rust deterministic sim, no floats, no I/O, no time
crates/data/         # validated data-driven balance loading
crates/render-shell/ # Macroquad render/input shell -> desktop, web, mobile
crates/server/       # headless build of `core`: input-log re-simulation
```

The simulation is fixed-point and `no_std`-clean. Determinism is **compiler-enforced**:
`crates/core` denies `clippy::float_arithmetic`, so floating-point math (which differs
across CPUs/wasm) cannot sneak in. Given the same seed and input log, the sim produces a
bit-identical state hash on every target.

## 3D presentation build

The Godot frontend displays the authoritative Rust battlefield with a restrained military palette, terrain lighting, compact industrial structures and infantry squad models. Buildings fit their simulation tiles. Ore appears as mineral beds; construction reveals the placement grid. The opening camera frames the real command centre. Decorative cities and painted billboard forests have been removed so playable entities remain identifiable. Existing vehicle and alien models remain prototype assets.

```bash
./run-3d.sh
```

3D controls: the arrow keys pan (the cursor at a screen edge and a middle-button drag pan too), `Z/E` rotate, mouse wheel zoom, `F` focus selection, `Home` recall the Earthfront, left-click or drag-select, right-click context order, `A` then right-click attack-move, `F2` select the whole army, `.` select an idle crew, `Ctrl+1` to `Ctrl+9` save a control group and `1` to `9` recall it, `T/K/V/H/X` train the combined-arms roster, `P/R/B/N/I/O/L/,/G/J/C` place a Reactor, Refinery, Barracks, Vehicle factory, Airfield, Supply depot, Research lab, Battery, Gun turret, AA battery or Field wall (the Build panel does the same with the mouse), `Y` research, `Q` tactical ability, `U` repair, and `Delete` sell. `Esc` with nothing armed opens the pause menu (a real pause: the simulation stops; Resume, Controls, Terrain guide on Kestrel Reach, Settings, Restart mission, Quit game), `F1` opens the controls reference (the top bar shows an `F1 Controls` hint) and `M` opens the strategic map (the simulation keeps running; Esc or `M` closes it). A contextual Build / Units / Orders / Science command deck shows costs, roles, prerequisites, construction and production progress. On Earthfront maps a Logistics tab (mouse only, no key) draws one map overlay at a time: Power lines, Supply routes (once a stocked depot has a building in reach), Borders, turret Coverage or Yield bonuses.

The title screen's New operation opens a map picker (Kestrel Reach or Earthfront Survival; Kestrel Reach is preselected on a normal launch) and its Settings entry, also in the pause menu, sets the Master, Effects, Interface, Ambience and Music volumes, fog of war on or off (Kestrel Reach, applied at the next match) and windowed or fullscreen. Settings are saved to `user://settings.cfg` (Godot's per-user data directory, never inside the repository). The debrief offers Review battlefield, Restart (the same map and seed), Main menu and Quit.

Wave timing differs by map. On Kestrel Reach the briefing and objectives name the first wave at 2:30 (4500 ticks), and an alien probe may strike sooner. On Survival the objective chain (Operation Dawnshield) guides the real opening dependency chain and the first wave arrives 90 seconds after founding. Both announce unit, research and combat events and end with match statistics and instant redeployment. Survival shows the whole battlefield. Kestrel Reach has a presentation-only fog of war (since 2026-10-06): unseen ground is shrouded, explored ground is dimmed, enemies appear only in sight and enemy structures stay as dimmed memories once seen; the simulation and the AI still see everything. Start the bridge with `EARTHFRONT_FOG=0` to turn it off.

### Scenarios and bridge flags

`./run-3d.sh` starts the bridge with the default scenario, **Kestrel Reach**. **Survival** is the original generated map. Kestrel Reach is a
hand-authored 44x26 coastal basin: a river that only the Wyllow Ford crosses (vehicles move at half pace on the
ford, infantry at 70%), highland that adds weapon range, forest cover, dry flats, a bay and a named region map. It adds the tile inspector,
territory card, Logistics lenses, the strategic map (`M`), the terrain guide (pause menu) and the briefing card. Survival
shows none of those. Start Survival with the `SCENARIO` pass-through, which keeps the launcher's GPU setup
(`SCENARIO=kestrel` is accepted too; the title's map picker also switches maps between matches):

```bash
SCENARIO=survival ./run-3d.sh
```

Or run the bridge yourself, then the client, which reads `godot3d/runtime/snapshot.json`:

```bash
cargo build --release -p rts-server --bin godot-bridge
target/release/godot-bridge godot3d/runtime/snapshot.json &
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path godot3d
```

`godot-bridge [--scenario kestrel|survival] [--dump-snapshot <path>] <snapshot path> [frame limit]`: `--scenario` defaults to
`kestrel` and an unknown value exits with status 2; `--dump-snapshot` writes the scenario's first snapshot to that path and exits (used for test fixtures). QA runs never touch your
display or speakers: `python3 tools/qa/launch_ui.py <dir> [--software] [--scenario kestrel|survival]` starts an isolated
bridge and client (Godot always gets `--audio-driver Dummy`), prints the owned PIDs and writes them to `<dir>/pids.json`;
drive it with `tools/qa/ui_client.py` and stop it by those PIDs.

## Run it

```bash
# Headless AI-vs-AI match + server re-simulation proving zero drift:
cargo run --release -p rts-server

# Desktop client (needs a display):
cargo run --release -p rts-render-shell --bin rts

# Web client (builds wasm, copies it next to index.html, serves on :8000):
./web/build.sh --release

# Package the self-contained web release without starting a local server:
./web/build.sh --release --no-serve
```

Controls: left-click or drag to select, Shift to add/toggle units, right-click to
move or contextually attack, `A` then click to attack-move, `S` to stop, `F2` to
select the entire army, and `1-9` for control groups. Use `B/P/R/G/W` to build
(Barracks/Reactor/Refinery/Laser Turret/Wall), and `T/V/K/H` to train riflemen,
rocket teams, battle tanks, and gunships. Refineries deploy vulnerable ore
harvesters automatically; `D` rebuilds one if it is destroyed. Harvesters travel
to exposed finite ore fields and must return their cargo before it becomes usable
credits. Construction,
production, movement, research, and combat all continue in real time. Touch uses
the same command system through tap-to-select and tap-to-move.
Select a Barracks or Refinery and right-click to set its rally point (or press the Set rally button in the structure panel, then left-click a tile; Esc cancels). Select an
owned structure and press `U` to repair it or `Delete` to sell it for a partial
refund. Unit production pauses at zero Energy and resumes automatically when
power generation restores the stockpile.

## Develop

```bash
cargo test  --workspace                         # run it (and the Godot suite below) to see the current counts
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt    --all -- --check
cargo build  -p rts-core -p rts-render-shell --target wasm32-unknown-unknown
```

The Godot client has its own headless suite, and the Python tooling has unit tests (run from the repository root):

```bash
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --audio-driver Dummy --path godot3d --script res://tests/run_tests.gd
(cd tools/ui && python3 -m unittest test_world_diff test_build_prop_atlas test_build_building_variants test_build_fx_atlas)
(cd tools/audio && python3 -m unittest test_build_sfx test_quiet_launchers)
```

CI (`.github/workflows/ci.yml`) has four jobs: `check` (fmt, strict Clippy with pedantic + nursery, the Rust test
suite, a wasm build), `deny` (`cargo-deny`), `godot` (downloads and caches Godot 4.7.2, imports the project, runs the headless suite
and fails on any `SCRIPT ERROR`, `SHADER ERROR` or `ERROR` line in its log) and `python-tools` (the `tools/ui`, `tools/audio` and `tools/ci`
unit tests). This repository has no GitHub remote, so the `godot` and `python-tools` jobs have been validated
locally only (`tools/ci/check_ci_yaml.py`) and have not yet run on GitHub.

## Guarantees, verified by tests

- **Determinism**: same seed + inputs ⇒ identical state hash; a pinned golden hash
  catches any cross-target (native/wasm/mobile) divergence.
- **Zero client/server drift**: the server re-simulates a match from its input log
  alone and the hash matches; a tampered log is detected.
- **AI-vs-AI** runs reproducibly.

## Platform reach

One codebase covers Windows, macOS, Linux, Web (wasm), Android, and iOS for the game
logic and shell. Consoles are not supported by the open Rust toolchain. Each platform
still needs its own packaging (signing, store accounts, ratings); see `MOBILE.md`.
