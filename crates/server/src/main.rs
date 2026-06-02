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
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;

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

/// An army of `kind` units fitting roughly within `budget` credits.
#[must_use]
fn balance_army(kind: UnitKind, budget: i64) -> Vec<UnitKind> {
    let cost = (kind.stats().cost.to_bits() / 65536).max(1);
    let n = (budget / cost).max(1);
    (0..n).map(|_| kind).collect()
}

/// Fights two small armies placed in mutual weapon range (no movement, so they
/// resolve cleanly), returning `(surviving P0, surviving P1)`.
#[must_use]
fn balance_duel(a: &[UnitKind], b: &[UnitKind]) -> (usize, usize) {
    let mut s = Sim::new(Map::new(40, 40), 1, Fixed::from_int(0));
    for (i, &k) in a.iter().enumerate() {
        let y = 18 + i32::try_from(i).unwrap_or(0);
        s.add_unit(
            PlayerId(0),
            k,
            Vec2::new(Fixed::from_int(18), Fixed::from_int(y)),
        );
    }
    for (i, &k) in b.iter().enumerate() {
        let y = 18 + i32::try_from(i).unwrap_or(0);
        s.add_unit(
            PlayerId(1),
            k,
            Vec2::new(Fixed::from_int(20), Fixed::from_int(y)),
        );
    }
    for _ in 0..1200 {
        s.step(&[]);
    }
    (s.unit_count(PlayerId(0)), s.unit_count(PlayerId(1)))
}

/// Prints an equal-cost duel matrix to eyeball unit balance.
fn run_balance_report() {
    let kinds = [
        UnitKind::Infantry,
        UnitKind::Tank,
        UnitKind::AntiArmor,
        UnitKind::Helicopter,
    ];
    let budget = 240;
    println!("== Equal-cost duel matrix (~{budget} cr/side; row = P0 vs col = P1) ==");
    print!("{:>11}", "");
    for k in kinds {
        print!("{:>14}", format!("{k:?}"));
    }
    println!();
    for &a in &kinds {
        print!("{:>11}", format!("{a:?}"));
        for &b in &kinds {
            let (pa, pb) = balance_duel(&balance_army(a, budget), &balance_army(b, budget));
            let tag = if pa > 0 && pb == 0 {
                "WIN"
            } else if pb > 0 && pa == 0 {
                "lose"
            } else {
                "draw"
            };
            print!("{:>14}", format!("{tag} {pa}/{pb}"));
        }
        println!();
    }
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("balance") {
        run_balance_report();
        return;
    }

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
