//! Deterministic lockstep session — the core of `PvP` networking.
//!
//! Each peer runs one [`Lockstep`] wrapping its own [`Sim`]. Every turn, each
//! player submits an [`InputFrame`] (its commands for a future turn) that is
//! broadcast to the other peer; a turn only advances once *all* players' inputs
//! for it are present, and both peers apply the same inputs in the same order —
//! so their simulations stay bit-identical. Because the sim is deterministic, the
//! only thing that crosses the wire is inputs (tiny), and a per-turn state-hash
//! **checksum** lets peers detect any desync immediately.
//!
//! This module is the protocol/correctness layer. The transport (WebSocket in the
//! browser, TCP natively) and matchmaking are thin layers on top — see the
//! roadmap. Inputs are delayed by `input_delay` turns so frames have time to
//! arrive before the turn that needs them.

use crate::game::sim::{Command, PlayerId, Sim, PLAYER_COUNT};
use alloc::collections::BTreeMap;
use alloc::vec::Vec;

/// One player's commands for a specific turn, broadcast between peers.
#[derive(Clone, Debug)]
pub struct InputFrame {
    /// Turn this input executes on (every peer applies it on the same turn).
    pub tick: u64,
    /// Player the input belongs to.
    pub player: PlayerId,
    /// The player's commands for that turn.
    pub commands: Vec<Command>,
}

/// A lockstep session driving one peer's deterministic simulation.
#[derive(Debug)]
pub struct Lockstep {
    sim: Sim,
    local_player: PlayerId,
    input_delay: u64,
    turn: u64,
    next_input_tick: u64,
    inbox: BTreeMap<u64, [Option<Vec<Command>>; PLAYER_COUNT]>,
}

impl Lockstep {
    /// Creates a session for `local_player`, scheduling local inputs `input_delay`
    /// turns ahead so they arrive in time over the network.
    #[must_use]
    pub const fn new(sim: Sim, local_player: PlayerId, input_delay: u64) -> Self {
        Self {
            sim,
            local_player,
            input_delay,
            turn: 0,
            next_input_tick: input_delay,
            inbox: BTreeMap::new(),
        }
    }

    /// The underlying simulation (for rendering and computing local input).
    #[must_use]
    pub const fn sim(&self) -> &Sim {
        &self.sim
    }

    /// The next turn to execute (equals the number of turns simulated so far).
    #[must_use]
    pub const fn turn(&self) -> u64 {
        self.turn
    }

    /// The current state-hash checksum, for desync detection.
    #[must_use]
    pub fn checksum(&self) -> u64 {
        self.sim.state_hash()
    }

    fn record(&mut self, tick: u64, player: PlayerId, commands: Vec<Command>) {
        let slots = self
            .inbox
            .entry(tick)
            .or_insert_with(|| core::array::from_fn(|_| None));
        slots[usize::from(player.0)] = Some(commands);
    }

    /// Schedules the local player's commands for the next free turn and returns
    /// the frame to broadcast to the other peer(s).
    pub fn submit_local(&mut self, commands: Vec<Command>) -> InputFrame {
        let tick = self.next_input_tick;
        self.next_input_tick += 1;
        let frame = InputFrame {
            tick,
            player: self.local_player,
            commands: commands.clone(),
        };
        self.record(tick, self.local_player, commands);
        frame
    }

    /// Records a frame received from another peer.
    pub fn receive(&mut self, frame: InputFrame) {
        self.record(frame.tick, frame.player, frame.commands);
    }

    /// Whether the next turn has every player's input (turns before `input_delay`
    /// are bootstrap turns with no input and are always ready).
    #[must_use]
    pub fn ready(&self) -> bool {
        if self.turn < self.input_delay {
            return true;
        }
        self.inbox
            .get(&self.turn)
            .is_some_and(|slots| slots.iter().all(Option::is_some))
    }

    /// Advances exactly one turn if all inputs are present, applying every
    /// player's commands in player order. Returns the new state-hash checksum, or
    /// `None` if the session is stalled waiting on inputs.
    pub fn try_advance(&mut self) -> Option<u64> {
        if !self.ready() {
            return None;
        }
        let mut merged = Vec::new();
        if let Some(slots) = self.inbox.remove(&self.turn) {
            for commands in slots.into_iter().flatten() {
                merged.extend(commands);
            }
        }
        self.sim.step(&merged);
        self.turn += 1;
        Some(self.sim.state_hash())
    }
}

#[cfg(test)]
mod tests {
    use super::{InputFrame, Lockstep};
    use crate::fixed::Fixed;
    use crate::game::map::Map;
    use crate::game::sim::{Command, PlayerId, Sim};
    use crate::game::stats::BuildingKind;
    use alloc::vec;
    use alloc::vec::Vec;

    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    fn match_sim() -> Sim {
        let mut s = Sim::new(Map::new(40, 40), 7, Fixed::from_int(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        s.add_building(P1, BuildingKind::CommandCenter, 35, 35);
        s
    }

    #[test]
    fn two_peers_stay_in_sync() {
        let delay = 3;
        let mut a = Lockstep::new(match_sim(), P0, delay);
        let mut b = Lockstep::new(match_sim(), P1, delay);
        let mut hashes_a = Vec::new();
        let mut hashes_b = Vec::new();
        for _ in 0..200 {
            let fa = a.submit_local(a.sim().ai_commands(P0));
            let fb = b.submit_local(b.sim().ai_commands(P1));
            a.receive(fb);
            b.receive(fa);
            while let Some(h) = a.try_advance() {
                hashes_a.push(h);
            }
            while let Some(h) = b.try_advance() {
                hashes_b.push(h);
            }
        }
        assert!(!hashes_a.is_empty());
        assert_eq!(hashes_a, hashes_b);
    }

    #[test]
    fn stalls_until_all_inputs_arrive() {
        let mut a = Lockstep::new(match_sim(), P0, 2);
        // Two bootstrap turns advance with no input.
        assert!(a.try_advance().is_some());
        assert!(a.try_advance().is_some());
        // Turn 2 needs both players' inputs; only the local one is submitted.
        a.submit_local(Vec::new());
        assert!(a.try_advance().is_none());
        // Once the peer's input arrives, it advances.
        a.receive(InputFrame {
            tick: 2,
            player: P1,
            commands: Vec::new(),
        });
        assert!(a.try_advance().is_some());
    }

    #[test]
    fn checksums_detect_a_desync() {
        // Both peers run the same world with input delay 0 and are fed identical
        // inputs — except peer B gets an extra command on turn 5.
        let mut a = Lockstep::new(match_sim(), P0, 0);
        let mut b = Lockstep::new(match_sim(), P0, 0);
        for t in 0..12 {
            a.receive(InputFrame {
                tick: t,
                player: P0,
                commands: Vec::new(),
            });
            a.receive(InputFrame {
                tick: t,
                player: P1,
                commands: Vec::new(),
            });
            b.receive(InputFrame {
                tick: t,
                player: P0,
                commands: Vec::new(),
            });
            let b_p1 = if t == 5 {
                vec![Command::Build {
                    owner: P1,
                    kind: BuildingKind::PowerPlant,
                    x: 30,
                    y: 30,
                }]
            } else {
                Vec::new()
            };
            b.receive(InputFrame {
                tick: t,
                player: P1,
                commands: b_p1,
            });
            let ca = a.try_advance().unwrap();
            let cb = b.try_advance().unwrap();
            if t < 5 {
                assert_eq!(ca, cb, "peers must match before the divergent input");
            }
        }
        // The divergent input desynced them — the checksum makes it detectable.
        assert_ne!(a.checksum(), b.checksum());
    }
}
