# Stellar Front — Space RTS + Tower Defense

A space real-time strategy game fused with tower defense and DOTA-style lane
pressure: defend Earth against an alien invasion — build a base and economy,
hold the lanes with units and static towers, and push to destroy the alien base
(its Core Node). Single-player vs AI, architected so PvP can be added later. (The campaign
techs up across four eras; this is the Era-1 / modern slice.)

The defining property: a **single deterministic Rust core** is shared by every
client *and* the server, so they can never disagree.

- Design spec: [`docs/superpowers/specs/2026-06-01-military-rts-td-design.md`](docs/superpowers/specs/2026-06-01-military-rts-td-design.md)
- Mobile build notes: [`MOBILE.md`](MOBILE.md)

## Architecture

```
crates/core/         # pure Rust deterministic sim — no floats, no I/O, no time
crates/data/         # (stub) balance-data loading
crates/render-shell/ # Macroquad render/input shell -> desktop, web, mobile
crates/server/       # headless build of `core` — input-log re-simulation
```

The simulation is fixed-point and `no_std`-clean. Determinism is **compiler-enforced**:
`crates/core` denies `clippy::float_arithmetic`, so floating-point math (which differs
across CPUs/wasm) cannot sneak in. Given the same seed and input log, the sim produces a
bit-identical state hash on every target.

## Run it

```bash
# Headless AI-vs-AI match + server re-simulation proving zero drift:
cargo run --release -p rts-server

# Desktop client (needs a display):
cargo run --release -p rts            # bin name is `rts`

# Web client (builds wasm, copies it next to index.html, serves on :8000):
./web/build.sh --release
```

Controls: left-click select unit, right-click move, `B/P/R/G` build
(Hangar/Reactor/Extractor/Laser Turret), `T` train infantry; tap-to-select / tap-to-move
on touch screens.

## Develop

```bash
cargo test  --workspace                         # ~71 tests
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
