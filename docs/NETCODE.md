# Netcode — deterministic lockstep PvP

PvP runs on **deterministic lockstep**: every peer runs the *same* simulation core
([`rts_core`]) and only **inputs** cross the wire, never world state. Because the
sim is bit-deterministic (fixed-point math, seeded RNG, fixed-timestep ticks — see
the design spec), two peers fed the same inputs in the same order stay
bit-identical forever. A tiny per-turn **checksum** (the existing `state_hash`)
makes any divergence detectable the instant it happens.

This is the same property the single-player server already proves by re-simulating
an input log; PvP just exchanges those inputs live between peers instead of
recording them.

## What's built (in this repo, tested)

The **protocol/correctness layer** is complete and lives in the deterministic core
so it compiles to every target (native, WASM, mobile) and is covered by tests:

- `crates/core/src/game/lockstep.rs` — the `Lockstep` session and `InputFrame`:
  - `submit_local(commands) -> InputFrame` — schedule the local player's commands
    `input_delay` turns ahead and produce the frame to broadcast.
  - `receive(frame)` — record a peer's frame.
  - `try_advance() -> Option<u64>` — advance one turn **only** when every player's
    input for it is present, applying all players' commands in player order;
    returns the new checksum, or `None` while stalled waiting on input.
  - `checksum()` — the current `state_hash`, for desync detection.
- `crates/server/src/main.rs` — a `lockstep` subcommand that runs **two in-process
  peers** to a full match (`cargo run -p rts-server -- lockstep`). Each peer owns
  its own sim and computes only *its own* player's AI input; they swap frames every
  turn under a 3-turn input delay and stay bit-identical the whole match. Tests
  also assert the P2P outcome matches the authoritative single-player replay
  bit-for-bit at zero delay.

### Input delay

Local inputs are scheduled `input_delay` turns into the future so frames have time
to arrive over the network before the turn that needs them. The first
`input_delay` turns are bootstrap turns that advance with no input. This is the
standard lockstep latency-hiding trick — a delay of 2–4 turns (≈66–133 ms at
30 Hz) covers typical RTT while staying imperceptible.

### Desync detection

After each turn, peers can exchange `checksum()` values (cheaply, e.g. every N
turns). A mismatch means a desync — a determinism bug or tampering — and the match
is halted rather than allowed to silently diverge. The two-peer demo asserts the
checksums match on every single turn.

## What remains (transport + service — environment-bound)

The pieces below are deployment infrastructure, not game logic. They wrap the
finished core; none of them touch determinism.

### Transport

`InputFrame` is the only thing that needs to be sent. It is small (a turn number, a
player id, and that turn's commands) and serializes trivially. Two backends, same
core:

- **Browser (WASM):** `WebSocket` only — browsers can't open raw TCP/UDP. Frames
  relay through a lightweight server (which can double as the matchmaker). Our
  single-threaded core needs no `SharedArrayBuffer`/COOP-COEP, so this is
  unobstructed.
- **Native (desktop):** TCP (or QUIC/UDP later) directly peer-to-peer or via the
  same relay.

Recommended shape: a thin `Transport` trait (`send(frame)`, `poll() -> Vec<frame>`)
with a `WebSocketTransport` and a `TcpTransport` impl, kept in the **shell**, not
the core. The render loop already calls `sim.step`; the lockstep loop replaces that
with `submit_local` → `transport.send` → drain `transport.poll` into `receive` →
`try_advance`.

### Matchmaking / lobby

A small stateless service: players connect, are paired, agree on a **seed** and the
**starting scenario**, then the relay forwards `InputFrame`s between them and
optionally collects periodic checksums to flag desyncs server-side. Because the
server can re-simulate from the input stream (the existing replay path), it can
also act as the authoritative judge of the result — no separate, drift-prone
server-side game logic.

### Reconnect / lag handling (later)

- **Stall on missing input** is already the behavior (`try_advance` returns `None`).
  A real client shows a "waiting for opponent" indicator during a stall.
- Adaptive input delay (grow/shrink with measured RTT) and drop/forfeit on timeout
  are straightforward additions on top of the existing stall semantics.

## Why lockstep (vs. state replication)

- **Bandwidth:** only inputs cross the wire — a handful of commands per turn —
  regardless of how many units are on the field. State replication would scale with
  entity count.
- **Zero drift by construction:** there is no separate server world to keep in sync
  with the client; there is one core, run identically everywhere. This is the same
  zero-drift guarantee the project was built around, extended to PvP.
- **Cheat resistance:** the server can validate any reported outcome by
  re-simulating the inputs.

The cost — every peer must be perfectly deterministic — is exactly the constraint
the core was designed around from day one (`clippy::float_arithmetic` is denied in
`core`, so non-determinism can't even compile).
