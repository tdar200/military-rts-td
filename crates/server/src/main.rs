//! Headless authoritative server / replay harness.
//!
//! This links the *same* [`rts_core`] simulation the clients use and demonstrates
//! the zero-drift guarantee end to end: it runs an AI-vs-AI match while recording
//! only the per-tick **input log**, then re-simulates the match from that log in a
//! fresh world and checks the final state hash matches. Because the simulation is
//! deterministic, the server can validate any client's claimed outcome from inputs
//! alone — no separate, drift-prone server logic.

use rts_core::fixed::Fixed;
use rts_core::game::map::Map;
use rts_core::game::sim::{Command, PlayerId, Sim};
use rts_core::game::stats::BuildingKind;

/// The outcome of a simulated match: who won (if anyone), how long it ran, the
/// final state hash, and the full ordered input log that produced it.
struct MatchOutcome {
    ticks: u64,
    winner: Option<PlayerId>,
    final_hash: u64,
    log: Vec<Vec<Command>>,
}

/// Loads the balance table from `balance.ron` in the working directory if present
/// (tune the game with no recompile), otherwise the embedded default.
fn load_balance() -> rts_core::game::balance::Balance {
    std::fs::read_to_string("balance.ron")
        .ok()
        .and_then(|s| rts_data::load(&s).ok())
        .unwrap_or_else(rts_data::load_default)
}

/// Builds the standard two-base AI-vs-AI scenario. Identical setup is essential:
/// the input log only reproduces the match if both runs start from this world.
fn new_match(seed: u64) -> Sim {
    let mut sim = Sim::new(Map::new(40, 40), seed, Fixed::from_int(3000));
    sim.set_balance(load_balance());
    sim.add_building(PlayerId(0), BuildingKind::CommandCenter, 4, 4);
    sim.add_building(PlayerId(1), BuildingKind::CommandCenter, 35, 35);
    sim
}

/// Runs an AI-vs-AI match, recording the command batch applied each tick. Stops
/// when a player wins or `max_ticks` is reached.
#[must_use]
fn simulate(seed: u64, max_ticks: u64) -> MatchOutcome {
    let mut sim = new_match(seed);
    let mut log: Vec<Vec<Command>> = Vec::new();
    let mut ticks = 0;
    while ticks < max_ticks {
        let mut commands = sim.ai_commands(PlayerId(0));
        commands.extend(sim.ai_commands(PlayerId(1)));
        sim.step(&commands);
        log.push(commands);
        ticks += 1;
        if sim.winner().is_some() {
            break;
        }
    }
    MatchOutcome {
        ticks,
        winner: sim.winner(),
        final_hash: sim.state_hash(),
        log,
    }
}

/// Re-simulates a match from its recorded input log in a fresh world and returns
/// the resulting final state hash. This is exactly what an authoritative server
/// does to validate a client's reported result.
#[must_use]
fn replay(seed: u64, log: &[Vec<Command>]) -> u64 {
    let mut sim = new_match(seed);
    for batch in log {
        sim.step(batch);
    }
    sim.state_hash()
}

fn main() {
    let seed = 2026;
    let outcome = simulate(seed, 8_000);

    println!("== Military RTS — headless AI-vs-AI match ==");
    println!("seed:        {seed}");
    println!("ticks:       {}", outcome.ticks);
    match outcome.winner {
        Some(PlayerId(p)) => println!("winner:      player {p}"),
        None => println!("winner:      none (stalemate at tick cap)"),
    }
    println!("final hash:  {:#018x}", outcome.final_hash);

    let replay_hash = replay(seed, &outcome.log);
    print!("server re-simulation from input log: ");
    if replay_hash == outcome.final_hash {
        println!("MATCH ✓ (zero client/server drift)");
    } else {
        println!("DESYNC ✗ (expected {:#018x})", outcome.final_hash);
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::{replay, simulate};

    #[test]
    fn replay_from_input_log_reproduces_final_state() {
        let outcome = simulate(7, 1500);
        assert_eq!(replay(7, &outcome.log), outcome.final_hash);
    }

    #[test]
    fn matches_are_deterministic_across_runs() {
        let a = simulate(7, 1500);
        let b = simulate(7, 1500);
        assert_eq!(a.final_hash, b.final_hash);
        assert_eq!(a.ticks, b.ticks);
    }

    #[test]
    fn a_tampered_log_is_detected() {
        let outcome = simulate(7, 1500);
        assert!(!outcome.log.is_empty());
        // Drop the last input batch: the re-simulation must NOT match.
        let tampered = &outcome.log[..outcome.log.len() - 1];
        assert_ne!(replay(7, tampered), outcome.final_hash);
    }
}
