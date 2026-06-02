//! Headless authoritative server / replay harness.
//!
//! This links the *same* [`rts_core`] simulation the clients use and demonstrates
//! the zero-drift guarantee end to end: it runs an AI-vs-AI match while recording
//! only the per-tick **input log**, then re-simulates the match from that log in a
//! fresh world and checks the final state hash matches. Because the simulation is
//! deterministic, the server can validate any client's claimed outcome from inputs
//! alone — no separate, drift-prone server logic.

use rts_core::fixed::Fixed;
use rts_core::game::lockstep::Lockstep;
use rts_core::game::map::Map;
use rts_core::game::scenario::Scenario;
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

/// The result of a two-peer lockstep match: how many turns ran, who won, whether
/// the two peers' simulations stayed bit-identical every turn, and the agreed
/// final checksum.
struct LockstepReport {
    turns: u64,
    winner: Option<PlayerId>,
    in_sync: bool,
    final_checksum: u64,
}

/// Runs a full `PvP` match between two in-process [`Lockstep`] peers — each owning
/// its own simulation and computing only *its own* player's AI commands — to prove
/// the netcode end to end. Every turn each peer broadcasts an [`InputFrame`]
/// (delayed by `input_delay` turns, as a real network needs), receives the other's,
/// and advances; the two per-turn checksums are compared. In a correct lockstep
/// they are always equal, so `in_sync` stays true — that is the zero-drift `PvP`
/// guarantee, the same property the replay harness proves for single-player.
#[must_use]
fn run_lockstep_match(seed: u64, input_delay: u64, max_turns: u64) -> LockstepReport {
    let mut a = Lockstep::new(new_match(seed), PlayerId(0), input_delay);
    let mut b = Lockstep::new(new_match(seed), PlayerId(1), input_delay);
    let mut in_sync = true;
    let mut turns = 0;
    while turns < max_turns {
        // Each peer computes only its own player's input, then they swap frames —
        // exactly what crosses the wire in a real match.
        let frame_a = a.submit_local(a.sim().ai_commands(PlayerId(0)));
        let frame_b = b.submit_local(b.sim().ai_commands(PlayerId(1)));
        a.receive(frame_b);
        b.receive(frame_a);

        let mut advanced = false;
        while let (Some(hash_a), Some(hash_b)) = (a.try_advance(), b.try_advance()) {
            advanced = true;
            turns += 1;
            if hash_a != hash_b {
                in_sync = false;
            }
            if a.sim().winner().is_some() || turns >= max_turns {
                break;
            }
        }
        if !advanced {
            break;
        }
        if a.sim().winner().is_some() {
            break;
        }
    }
    LockstepReport {
        turns,
        winner: a.sim().winner(),
        in_sync,
        final_checksum: a.checksum(),
    }
}

/// Prints the two-peer lockstep `PvP` proof.
fn run_lockstep_report() {
    let seed = 2026;
    let report = run_lockstep_match(seed, 3, 8_000);
    println!("== Military RTS — two-peer lockstep PvP match ==");
    println!("seed:        {seed}");
    println!("input delay: 3 turns");
    println!("turns:       {}", report.turns);
    match report.winner {
        Some(PlayerId(p)) => println!("winner:      player {p}"),
        None => println!("winner:      none (stalemate at turn cap)"),
    }
    println!("checksum:    {:#018x}", report.final_checksum);
    print!("peer-to-peer lockstep: ");
    if report.in_sync {
        println!("IN SYNC ✓ (both peers bit-identical every turn)");
    } else {
        println!("DESYNC ✗ (checksums diverged)");
        std::process::exit(1);
    }
}

/// Aggregate AI-vs-AI results for one scenario across many seeds — the data that
/// drives balancing: who wins, how decisive, how long, and whether matches stall.
struct ScenarioStats {
    scenario: Scenario,
    p0_wins: u32,
    p1_wins: u32,
    stalemates: u32,
    lengths: Vec<u64>,
    peak_units: usize,
}

impl ScenarioStats {
    const fn matches(&self) -> u32 {
        self.p0_wins + self.p1_wins + self.stalemates
    }

    /// Median match length in ticks (0 if no matches).
    fn median_len(&self) -> u64 {
        if self.lengths.is_empty() {
            return 0;
        }
        let mut sorted = self.lengths.clone();
        sorted.sort_unstable();
        sorted[sorted.len() / 2]
    }
}

/// Runs `max_ticks`-capped AI-vs-AI matches for one scenario across `seeds`,
/// recording the win split, match lengths, and peak army size.
#[must_use]
fn playtest_scenario(scenario: Scenario, seeds: &[u64], max_ticks: u64) -> ScenarioStats {
    let mut stats = ScenarioStats {
        scenario,
        p0_wins: 0,
        p1_wins: 0,
        stalemates: 0,
        lengths: Vec::new(),
        peak_units: 0,
    };
    for &seed in seeds {
        let mut sim = scenario.build(seed);
        sim.set_balance(load_balance());
        let mut ticks = 0;
        while ticks < max_ticks {
            let mut commands = sim.ai_commands(PlayerId(0));
            commands.extend(sim.ai_commands(PlayerId(1)));
            sim.step(&commands);
            ticks += 1;
            let units = sim.unit_count(PlayerId(0)) + sim.unit_count(PlayerId(1));
            stats.peak_units = stats.peak_units.max(units);
            if sim.winner().is_some() {
                break;
            }
        }
        match sim.winner() {
            Some(PlayerId(0)) => stats.p0_wins += 1,
            Some(PlayerId(_)) => stats.p1_wins += 1,
            None => stats.stalemates += 1,
        }
        if sim.winner().is_some() {
            stats.lengths.push(ticks);
        }
    }
    stats
}

/// Prints a per-scenario AI-vs-AI playtest table to guide balancing.
fn run_playtest_report() {
    let seeds: Vec<u64> = (1..=12).collect();
    let max_ticks = 12_000;
    println!(
        "== AI-vs-AI playtest ({} seeds/map, cap {max_ticks} ticks) ==",
        seeds.len()
    );
    println!(
        "{:>14}  {:>7}  {:>6}  {:>6}  {:>6}  {:>18}  {:>5}",
        "scenario", "matches", "P0", "P1", "stale", "len min/med/max", "peak"
    );
    for &sc in &Scenario::ALL {
        let stats = playtest_scenario(sc, &seeds, max_ticks);
        let (lo, med, hi) = (
            stats.lengths.iter().min().copied().unwrap_or(0),
            stats.median_len(),
            stats.lengths.iter().max().copied().unwrap_or(0),
        );
        println!(
            "{:>14}  {:>7}  {:>6}  {:>6}  {:>6}  {:>18}  {:>5}",
            stats.scenario.name(),
            stats.matches(),
            stats.p0_wins,
            stats.p1_wins,
            stats.stalemates,
            format!("{lo}/{med}/{hi}"),
            stats.peak_units,
        );
    }
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
    match std::env::args().nth(1).as_deref() {
        Some("balance") => {
            run_balance_report();
            return;
        }
        Some("lockstep") => {
            run_lockstep_report();
            return;
        }
        Some("playtest") => {
            run_playtest_report();
            return;
        }
        _ => {}
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
    use super::{replay, run_lockstep_match, simulate};

    #[test]
    fn two_peers_stay_in_lockstep_for_a_full_match() {
        let report = run_lockstep_match(2026, 3, 8_000);
        assert!(report.turns > 0);
        assert!(
            report.in_sync,
            "peers desynced after {} turns",
            report.turns
        );
    }

    #[test]
    fn lockstep_outcome_matches_the_authoritative_replay() {
        // With zero input delay, advancing turn T applies inputs computed from
        // state T — identical scheduling to the single-player loop. So the
        // peer-to-peer match must reach the same final state as the server's own
        // re-simulation: the client (P2P) and server (replay) cores agree to the
        // bit. (A non-zero delay merely shifts *when* inputs land, which both peers
        // still apply identically — proven by the in-sync test above.)
        let report = run_lockstep_match(2026, 0, 8_000);
        let outcome = simulate(2026, 8_000);
        assert_eq!(report.final_checksum, outcome.final_hash);
        assert_eq!(report.winner, outcome.winner);
    }

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
