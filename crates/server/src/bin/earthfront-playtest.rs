//! Reproducible, accelerated Earthfront economy/warfare playtest.
use rts_core::game::scenario;
use rts_core::game::sim::PlayerId;

fn main() {
    let seed = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(3);
    let verbose = std::env::args().any(|s| s == "--verbose");
    let mut sim = scenario::survival(seed);
    sim.set_balance(rts_data::load_default());
    let mut wave = 0;
    let mut relays = sim.alien_relay_count(PlayerId(1), false);
    for tick in 0..72_000 {
        let mut commands = sim.ai_commands(PlayerId(0));
        if sim.waves_survived() > 0 {
            commands.extend(sim.ai_commands(PlayerId(1)));
        }
        sim.step(&commands);
        if sim.waves_survived() != wave
            || tick == 2400
            || sim.alien_relay_count(PlayerId(1), false) != relays
        {
            relays = sim.alien_relay_count(PlayerId(1), false);
            wave = sim.waves_survived();
            println!(
                "t={}s wave={} material={} era={} science={} units={} relays={relays} economy={:?}",
                tick / 30,
                wave,
                sim.money(PlayerId(0)).to_int_floor(),
                sim.player_era(PlayerId(0)),
                sim.research_state(PlayerId(0)).0.count(),
                sim.unit_count(PlayerId(0)),
                sim.economy_view(PlayerId(0))
            );
            if verbose {
                for e in sim.views().iter().filter(|e| e.owner == PlayerId(0)) {
                    println!(
                        "  {:?} id={} pos=({}, {}) hp={} cargo={} services={:?}",
                        e.kind,
                        e.id.0,
                        e.pos.x.to_int_floor(),
                        e.pos.y.to_int_floor(),
                        e.hp.to_int_floor(),
                        e.cargo,
                        sim.earthfront_entity_status(e.id)
                    );
                }
            }
        }
        if sim.winner().is_some() {
            println!(
                "RESULT seed={seed} winner={:?} time={}s waves={wave} hash={}",
                sim.winner(),
                tick / 30,
                sim.state_hash()
            );
            return;
        }
    }
    println!("UNRESOLVED seed={seed} hash={}", sim.state_hash());
}
