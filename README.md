# Ascension — Real-Time Science RTS

A continuous real-time strategy game inspired by the direct battlefield control
of *Age of Empires* and *Red Alert*, with civilization-scale technological
progression. Defend Earth against an alien invasion: build a base and economy,
command armies, hold the lanes with static defences, and counterattack to destroy
the alien Core Node. The playable campaign currently covers **Contemporary Humanity and Advanced Industrial Civilization**. The ten-era cosmic campaign is a design and implementation roadmap, not completed gameplay.

Earthfront has a fully visible battlefield, finite ore extraction, powered refining, dedicated unit factories, ammunition supply, adaptive alien waves, and twelve infrastructure-dependent research projects. Destroy the alien Core Node to win. Two defended relay outposts are optional targets: disabling them reduces alien reinforcements and local supply. Electricity is generation versus demand; batteries store limited reserves. Research and weapons production compete for industrial capacity.

- [Implemented gameplay, controls, validation and limitations](docs/ascension/IMPLEMENTED.md)
- [Complete game blueprint and 200-technology catalogue](docs/ascension/README.md)
- [Playable development milestones](docs/ascension/ROADMAP.md)
- [Mobile build notes](MOBILE.md)

The deterministic Rust simulation drives the Godot client, native/web shell and headless server.

## Architecture

```
crates/core/         # pure Rust deterministic sim — no floats, no I/O, no time
crates/data/         # validated data-driven balance loading
crates/render-shell/ # Macroquad render/input shell -> desktop, web, mobile
crates/server/       # headless build of `core` — input-log re-simulation
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

3D controls: `WASD` pan, `Z/E` rotate, mouse wheel zoom, `F` focus selection, `Home` recall the Earthfront, left-click or drag-select, right-click context order, `A` attack-move, `F2` select the whole army, `.` select an idle crew, `T/K/V/H/X` train the combined-arms roster, the Build panel constructs the economy and defence network, `Y` research, `U` repair, and `Delete` sell. `Esc` with nothing armed opens the pause menu (a real pause: the simulation stops; Resume, Controls, Restart mission, Quit game) and `F1` opens the controls reference. A contextual Build / Units / Orders / Science command deck shows costs, roles, prerequisites, construction and production progress. On Earthfront maps a Logistics tab (mouse only, no key) draws one map overlay at a time: Power lines, Supply routes (once a stocked depot has a building in reach), Borders, turret Coverage or Yield bonuses. Operation Dawnshield guides the real opening dependency chain, telegraphs its 90-second first wave, announces unit/research/combat events, and ends with match statistics and instant redeployment. There is deliberately no fog of war.

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
select the entire army, and `1–9` for control groups. Use `B/P/R/G/W` to build
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
cargo test  --workspace                         # 259 passing + 1 ignored balance playtest
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt    --all -- --check
cargo build  -p rts-core -p rts-render-shell --target wasm32-unknown-unknown
```

CI (`.github/workflows/ci.yml`) runs fmt, strict Clippy (pedantic + nursery),
the test suite, a wasm build, and `cargo-deny`.

## Guarantees, verified by tests

- **Determinism**: same seed + inputs ⇒ identical state hash; a pinned golden hash
  catches any cross-target (native/wasm/mobile) divergence.
- **Zero client/server drift**: the server re-simulates a match from its input log
  alone and the hash matches; a tampered log is detected.
- **AI-vs-AI** runs reproducibly.

## Platform reach

One codebase covers Windows, macOS, Linux, Web (wasm), Android, and iOS for the game
logic and shell. Consoles are not supported by the open Rust toolchain. Each platform
still needs its own packaging (signing, store accounts, ratings) — see `MOBILE.md`.
