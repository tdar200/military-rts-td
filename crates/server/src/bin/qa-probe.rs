//! Repeatable QA measurements. Fixtures deliberately bypass progression for stress tests.
use rts_core::fixed::Fixed;
use rts_core::game::map::{Deposit, DepositKind, Map};
use rts_core::game::sim::{Command, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;
use std::time::Instant;

const fn point(x: i32, y: i32) -> Vec2 {
    Vec2::new(Fixed::from_int(x), Fixed::from_int(y))
}
fn memory_kb() -> u64 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|text| {
            text.lines()
                .find(|s| s.starts_with("VmRSS:"))
                .and_then(|s| s.split_whitespace().nth(1))
                .and_then(|s| s.parse().ok())
        })
        .unwrap_or(0)
}
fn fixture() -> Sim {
    let mut sim = Sim::new(Map::new(160, 80), 2026, Fixed::from_int(100_000));
    sim.enable_earthfront();
    sim.set_survival_mode(true);
    sim.set_balance(rts_data::load_default());
    sim.add_building(PlayerId(0), BuildingKind::CommandCenter, 3, 40);
    sim.add_building(PlayerId(1), BuildingKind::CommandCenter, 154, 40);
    sim
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let mode = args.get(1).map_or("stress", String::as_str);
    if mode == "movement" {
        let mut sim = fixture();
        let mut ids = Vec::new();
        let mut orders = Vec::new();
        for i in 0..100 {
            let unit = sim.add_unit(
                PlayerId(0),
                UnitKind::Infantry,
                point(10 + i % 10, 10 + i / 10),
            );
            ids.push(unit);
            orders.push(Command::Move {
                owner: PlayerId(0),
                unit,
                target: point(35, 35),
            });
        }
        for tick in 0..1800 {
            sim.step(if tick == 0 { &orders } else { &[] });
        }
        let unique: std::collections::BTreeSet<_> = ids
            .iter()
            .filter_map(|id| sim.position(*id))
            .map(|p| (p.x.to_bits(), p.y.to_bits()))
            .collect();
        println!(
            "movement: 100 units, {} distinct final positions",
            unique.len()
        );
        return;
    }
    if mode == "soak" {
        soak();
        return;
    }
    let count: u32 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1000);
    let ticks: u32 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(120);
    let mut sim = fixture();
    let mut orders = Vec::new();
    for i in 0..count {
        let side = u16::try_from(if mode == "sustained" { 0 } else { i % 2 }).unwrap_or(0);
        let x = 40 + i32::try_from((i / 2) % 60).unwrap_or(0);
        let y = 10 + i32::try_from((i / 120) % 60).unwrap_or(0);
        let unit = sim.add_unit(
            PlayerId(side),
            if i % 7 == 0 {
                UnitKind::Tank
            } else {
                UnitKind::Infantry
            },
            point(x, y),
        );
        if i < 100 {
            orders.push(Command::AttackMove {
                owner: PlayerId(side),
                unit,
                target: point(100 - x / 2, 50 - y / 2),
            });
        }
    }
    let before = memory_kb();
    let total = Instant::now();
    let mut samples = Vec::new();
    for t in 0..ticks {
        let start = Instant::now();
        sim.step(if t == 0 { &orders } else { &[] });
        samples.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    samples.sort_by(f64::total_cmp);
    let n = samples.len();
    println!("{{\"mode\":\"{mode}\",\"spawned\":{count},\"ticks\":{ticks},\"seconds\":{},\"p50_ms\":{},\"p95_ms\":{},\"max_ms\":{},\"rss_before_kb\":{before},\"rss_after_kb\":{},\"survivors\":{},\"hash\":{}}}",total.elapsed().as_secs_f64(),samples[n/2],samples[(n*95/100).min(n-1)],samples[n-1],memory_kb(),sim.unit_count(PlayerId(0))+sim.unit_count(PlayerId(1)),sim.state_hash());
}
fn soak() {
    let mut sim = fixture();
    for i in 0..12_u16 {
        let x = 5 + i * 3;
        sim.map_mut().set_deposit(
            x,
            43,
            Deposit {
                kind: DepositKind::Ore,
                remaining: 20_000,
            },
        );
        sim.add_building(PlayerId(0), BuildingKind::PowerPlant, x, 38);
        sim.add_building(PlayerId(0), BuildingKind::Refinery, x, 40);
        sim.add_building(PlayerId(0), BuildingKind::SupplyDepot, x, 42);
        sim.add_building(PlayerId(0), BuildingKind::Battery, x, 45);
        sim.add_unit(PlayerId(0), UnitKind::Harvester, point(i32::from(x), 44));
    }
    sim.add_building(PlayerId(0), BuildingKind::ResearchLab, 5, 36);
    sim.add_building(PlayerId(0), BuildingKind::VehicleFactory, 8, 36);
    let mut moving = Vec::new();
    for i in 0..100 {
        moving.push(sim.add_unit(
            PlayerId(0),
            UnitKind::Infantry,
            point(10 + i % 20, 10 + i / 20),
        ));
    }
    let started = Instant::now();
    for t in 0..864_000_u64 {
        let mut orders = Vec::new();
        if t % 900 == 0 {
            if let Some(tech_id) = sim.suggested_research(PlayerId(0)) {
                orders.push(Command::Research {
                    owner: PlayerId(0),
                    tech_id,
                });
            }
            for (i, &unit) in moving.iter().enumerate().take(10) {
                orders.push(Command::Move {
                    owner: PlayerId(0),
                    unit,
                    target: point(
                        10 + i32::try_from(i).unwrap_or(0),
                        if t % 1800 == 0 { 20 } else { 10 },
                    ),
                });
            }
        }
        sim.step(&orders);
        assert!(sim.money(PlayerId(0)) >= Fixed::ZERO && sim.energy(PlayerId(0)) >= Fixed::ZERO);
        let view = sim.economy_view(PlayerId(0));
        assert!(view.ore <= 3600 && view.stored_energy <= view.storage_capacity);
        if [53_999, 215_999, 863_999].contains(&t) {
            let remaining: u64 = sim
                .map()
                .deposits()
                .map(|(_, _, d)| u64::from(d.remaining))
                .sum();
            println!("{{\"mode\":\"soak\",\"simulated_seconds\":{},\"wall_seconds\":{},\"rss_kb\":{},\"ore_remaining\":{remaining},\"ore_buffer\":{},\"material_bits\":{},\"stored_energy\":{},\"entities\":{},\"era\":{},\"techs\":{},\"hash\":{}}}",(t+1)/30,started.elapsed().as_secs_f64(),memory_kb(),view.ore,sim.money(PlayerId(0)).to_bits(),view.stored_energy,sim.entity_count(),sim.player_era(PlayerId(0)),sim.research_state(PlayerId(0)).0.count(),sim.state_hash());
        }
    }
}
