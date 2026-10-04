//! Adversarial contracts from the end-to-end QA investigation.
use super::*;
fn arena() -> Sim {
    let mut sim = Sim::new(Map::new(48, 32), 2026, Fixed::from_int(4000));
    sim.enable_earthfront();
    sim.set_survival_mode(true);
    sim.add_building(PlayerId(0), BuildingKind::CommandCenter, 2, 16);
    sim.add_building(PlayerId(1), BuildingKind::CommandCenter, 44, 16);
    sim
}
#[test]
fn qa_repeated_sell_is_not_an_infinite_material_faucet() {
    let mut sim = arena();
    let id = sim.add_building(PlayerId(0), BuildingKind::PowerPlant, 4, 16);
    let before = sim.money(PlayerId(0));
    let batch = alloc::vec![Command::Sell { owner: PlayerId(0), building: id }; 100];
    for command in &batch {
        sim.apply_command(command);
    }
    assert_eq!(sim.money(PlayerId(0)) - before, Fixed::from_int(50));
}
#[test]
fn qa_sold_building_cannot_be_resurrected_by_repair_in_same_tick() {
    let mut sim = arena();
    let id = sim.add_building(PlayerId(0), BuildingKind::PowerPlant, 4, 16);
    sim.apply_sell(PlayerId(0), id);
    let before = sim.money(PlayerId(0));
    sim.apply_repair(PlayerId(0), id);
    assert_eq!(sim.entities[id.0 as usize].hp, Fixed::ZERO);
    assert_eq!(sim.money(PlayerId(0)), before);
}
#[test]
fn qa_victory_is_terminal_even_with_hostile_survivors_and_commands() {
    let mut sim = arena();
    sim.entities[1].hp = Fixed::ZERO;
    sim.clear_dead();
    assert_eq!(sim.winner(), Some(PlayerId(0)));
    let hash = sim.state_hash();
    for _ in 0..100 {
        sim.step(&[Command::Build {
            owner: PlayerId(0),
            kind: BuildingKind::PowerPlant,
            x: 4,
            y: 16,
        }]);
    }
    assert_eq!(
        sim.state_hash(),
        hash,
        "finished campaign continued mutating"
    );
}
#[test]
fn qa_exact_build_price_and_invalid_placement_do_not_create_material() {
    for funds in [99, 100, 101] {
        let mut sim = arena();
        sim.civs[0].money = Fixed::from_int(funds);
        sim.apply_build(PlayerId(0), BuildingKind::PowerPlant, 4, 16);
        assert_eq!(
            sim.money(PlayerId(0)),
            Fixed::from_int(if funds >= 100 { funds - 100 } else { funds })
        );
        let before = sim.money(PlayerId(0));
        sim.apply_build(PlayerId(0), BuildingKind::PowerPlant, u16::MAX, u16::MAX);
        sim.apply_build(PlayerId(0), BuildingKind::PowerPlant, 2, 16);
        assert_eq!(sim.money(PlayerId(0)), before);
    }
}
#[test]
fn qa_queue_cost_crew_limit_and_unauthorised_producer() {
    let mut sim = arena();
    let producer = sim.add_building(PlayerId(0), BuildingKind::Barracks, 4, 16);
    let before = sim.money(PlayerId(0));
    for _ in 0..100 {
        sim.apply_train(PlayerId(0), producer, UnitKind::Infantry);
    }
    assert_eq!(sim.entities[producer.0 as usize].build_queue.len(), 8);
    assert_eq!(before - sim.money(PlayerId(0)), Fixed::from_int(400));
    let enemy_before = sim.money(PlayerId(1));
    sim.apply_train(PlayerId(1), producer, UnitKind::Infantry);
    assert_eq!(sim.money(PlayerId(1)), enemy_before);
}
#[test]
fn qa_duplicate_research_spends_once_and_invalid_ids_do_nothing() {
    let mut sim = arena();
    sim.add_building(PlayerId(0), BuildingKind::ResearchLab, 4, 16);
    let before = sim.money(PlayerId(0));
    for _ in 0..100 {
        sim.apply_research(PlayerId(0), 0);
    }
    sim.apply_research(PlayerId(0), u32::MAX);
    assert_eq!(before - sim.money(PlayerId(0)), Fixed::from_int(100));
    assert_eq!(sim.research_state(PlayerId(0)).1, Some((0, 900)));
}
#[test]
fn qa_damage_range_and_time_to_kill_are_measured_independently() {
    let mut sim = arena();
    let shooter = sim.add_unit(
        PlayerId(0),
        UnitKind::Infantry,
        Vec2::new(Fixed::from_int(15), Fixed::from_int(15)),
    );
    let target = sim.add_unit(
        PlayerId(1),
        UnitKind::Infantry,
        Vec2::new(Fixed::from_int(18), Fixed::from_int(15)),
    );
    sim.entities[target.0 as usize].ammunition = 0;
    // 6 ballistic × 3/2 against flesh = 9 HP/shot. First shot at tick zero,
    // then every authored period = 8 ticks. Six shots kill 50 HP at tick 40.
    let mut kill_tick = None;
    for tick in 0..60 {
        sim.run_combat();
        if tick == 0 {
            assert_eq!(sim.entities[target.0 as usize].hp, Fixed::from_int(41));
        }
        if sim.entities[target.0 as usize].hp <= Fixed::ZERO {
            kill_tick = Some(tick);
            break;
        }
    }
    assert_eq!(kill_tick, Some(40));
    assert_eq!(sim.entities[shooter.0 as usize].ammunition, 84);
    let mut out = arena();
    let a = out.add_unit(
        PlayerId(0),
        UnitKind::Infantry,
        Vec2::new(Fixed::from_int(15), Fixed::from_int(15)),
    );
    let b = out.add_unit(
        PlayerId(1),
        UnitKind::Infantry,
        Vec2::new(
            Fixed::from_int(18) + Fixed::from_ratio(1, 100),
            Fixed::from_int(15),
        ),
    );
    out.entities[b.0 as usize].ammunition = 0;
    out.run_combat();
    assert_eq!(out.entities[b.0 as usize].hp, Fixed::from_int(50));
    assert_eq!(out.entities[a.0 as usize].ammunition, 90);
}

#[test]
fn qa_refinery_completion_cannot_bypass_crew_cap() {
    let mut sim = arena();
    for _ in 0..60 {
        sim.add_unit(
            PlayerId(0),
            UnitKind::Infantry,
            Vec2::new(Fixed::from_int(10), Fixed::from_int(10)),
        );
    }
    let refinery = sim.add_building(PlayerId(0), BuildingKind::Refinery, 4, 16);
    sim.entities[refinery.0 as usize].construction_remaining = 1;
    sim.run_construction();
    assert_eq!(sim.supply_used(PlayerId(0)), 60);
}
#[test]
fn qa_every_live_unit_requires_exact_cost_and_correct_producer() {
    for kind in [
        UnitKind::Infantry,
        UnitKind::Tank,
        UnitKind::AntiArmor,
        UnitKind::Helicopter,
        UnitKind::Harvester,
    ] {
        for missing in [false, true] {
            let mut sim = arena();
            sim.civs[0].unlocked_units |= 1 << kind.index();
            let cost = sim.balance.unit(kind).money_cost;
            sim.civs[0].money = if missing { cost - Fixed::ONE } else { cost };
            let producer = sim.add_building(PlayerId(0), Sim::earthfront_producer(kind), 4, 16);
            sim.apply_train(PlayerId(0), producer, kind);
            assert_eq!(
                sim.entities[producer.0 as usize].build_queue.len(),
                usize::from(!missing),
                "{kind:?}"
            );
            assert_eq!(
                sim.money(PlayerId(0)),
                if missing {
                    cost - Fixed::ONE
                } else {
                    Fixed::ZERO
                }
            );
        }
    }
}
#[test]
fn qa_shared_extraction_depletes_once_without_negative_inventory() {
    let mut sim = arena();
    sim.map.set_deposit(
        10,
        10,
        crate::game::map::Deposit {
            kind: crate::game::map::DepositKind::Ore,
            remaining: 15,
        },
    );
    let position = tile_center(10, 10);
    let a = sim.add_unit(PlayerId(0), UnitKind::Harvester, position);
    let b = sim.add_unit(PlayerId(0), UnitKind::Harvester, position);
    sim.run_harvesters();
    assert_eq!(
        sim.entities[a.0 as usize].cargo + sim.entities[b.0 as usize].cargo,
        15
    );
    assert!(sim.map.deposit(10, 10).is_none());
    sim.run_harvesters();
    assert_eq!(
        sim.entities[a.0 as usize].cargo + sim.entities[b.0 as usize].cargo,
        15
    );
}
#[test]
fn qa_power_priority_and_battery_charge_follow_fixed_point_ledger() {
    let mut sim = arena();
    sim.add_building(PlayerId(0), BuildingKind::PowerPlant, 4, 16);
    sim.add_building(PlayerId(0), BuildingKind::Battery, 5, 16);
    for tick in 0..30 {
        sim.tick = tick;
        sim.run_earthfront_services();
    }
    assert_eq!(
        sim.energy(PlayerId(0)).to_bits(),
        30 * ((36_i64 * 65536) / 30)
    );
    let mut brownout = arena();
    let turret = brownout.add_building(PlayerId(0), BuildingKind::GunTurret, 4, 16);
    let lab = brownout.add_building(PlayerId(0), BuildingKind::ResearchLab, 5, 16);
    brownout.civs[0].active_research = Some((0, 900));
    brownout.run_earthfront_services();
    assert_eq!(brownout.entities[turret.0 as usize].power_fraction, 1000);
    assert_eq!(brownout.entities[lab.0 as usize].power_fraction, 66); // (10-8)/30
    brownout.run_earthfront_research();
    assert_eq!(brownout.research_state(PlayerId(0)).1, Some((0, 900)));
}
#[test]
fn qa_live_technology_graph_is_unique_acyclic_and_reachable() {
    let sim = arena();
    let mut reached = alloc::vec![false;sim.technology_count()];
    for _ in 0..sim.technology_count() {
        for id in 0..u32::try_from(sim.technology_count()).unwrap() {
            let node = sim.technology(id).unwrap();
            assert_eq!(node.id, id);
            assert!(!node.unlocks.is_empty());
            if node
                .prereqs
                .iter()
                .all(|&p| reached.get(p as usize) == Some(&true))
            {
                reached[id as usize] = true;
            }
        }
    }
    assert!(reached.iter().all(|&v| v));
}

#[test]
fn qa_factory_does_not_spawn_inside_a_blocked_tile() {
    let mut sim = arena();
    let producer = sim.add_building(PlayerId(0), BuildingKind::Barracks, 4, 16);
    let pos = sim.entities[producer.0 as usize].pos + Vec2::new(Fixed::ONE, Fixed::ZERO);
    let tile = sim.world_to_tile(pos);
    sim.map
        .set_tile(tile.0, tile.1, crate::game::map::Tile::BLOCKED);
    sim.apply_train(PlayerId(0), producer, UnitKind::Infantry);
    sim.entities[producer.0 as usize].build_progress =
        sim.balance.unit(UnitKind::Infantry).build_time;
    sim.run_production();
    let unit = sim
        .entities
        .iter()
        .find(|e| e.alive && e.kind == Kind::Unit(UnitKind::Infantry))
        .unwrap();
    let tile = sim.world_to_tile(unit.pos);
    assert!(
        sim.map
            .tile(i32::from(tile.0), i32::from(tile.1))
            .unwrap()
            .passable
    );
}

#[test]
fn qa_sealed_factory_retains_paid_queue_until_an_exit_opens() {
    let mut sim = arena();
    let producer = sim.add_building(PlayerId(0), BuildingKind::Barracks, 4, 16);
    for (x, y) in hex::neighbors(4, 16) {
        sim.map.set_tile(
            u16::try_from(x).unwrap(),
            u16::try_from(y).unwrap(),
            crate::game::map::Tile::BLOCKED,
        );
    }
    sim.apply_train(PlayerId(0), producer, UnitKind::Infantry);
    let paid = sim.money(PlayerId(0));
    sim.entities[producer.0 as usize].build_progress =
        sim.balance.unit(UnitKind::Infantry).build_time;
    for _ in 0..60 {
        sim.run_production();
    }
    assert_eq!(sim.unit_count(PlayerId(0)), 0);
    assert_eq!(sim.entities[producer.0 as usize].build_queue.len(), 1);
    let (x, y) = hex::neighbors(4, 16)[0];
    sim.map.set_tile(
        u16::try_from(x).unwrap(),
        u16::try_from(y).unwrap(),
        crate::game::map::Tile::OPEN,
    );
    sim.run_production();
    assert_eq!(sim.unit_count(PlayerId(0)), 1);
    assert!(sim.entities[producer.0 as usize].build_queue.is_empty());
    assert_eq!(sim.money(PlayerId(0)), paid);
}

#[test]
fn qa_combat_counter_matrix_matches_independent_damage_and_ttk() {
    // Authored constants, independently calculated; first shot occurs at t=0.
    for (attacker, defender, damage, hp, period) in [
        (
            UnitKind::Infantry,
            UnitKind::Infantry,
            Fixed::from_int(9),
            50,
            8,
        ),
        (
            UnitKind::Infantry,
            UnitKind::Tank,
            Fixed::from_int(3),
            220,
            8,
        ),
        (
            UnitKind::AntiArmor,
            UnitKind::Tank,
            Fixed::from_ratio(77, 2),
            220,
            16,
        ),
        (
            UnitKind::AntiArmor,
            UnitKind::Infantry,
            Fixed::from_int(11),
            50,
            16,
        ),
        (UnitKind::Tank, UnitKind::Tank, Fixed::from_int(30), 220, 20),
        (
            UnitKind::Helicopter,
            UnitKind::Infantry,
            Fixed::from_int(24),
            50,
            9,
        ),
    ] {
        let mut sim = arena();
        let a = sim.add_unit(PlayerId(0), attacker, hex::center(18, 16));
        let b = sim.add_unit(PlayerId(1), defender, hex::center(20, 16));
        sim.entities[b.0 as usize].ammunition = 0;
        let shots = (Fixed::from_int(hp).to_bits() + damage.to_bits() - 1) / damage.to_bits();
        let expected = (shots - 1) * period;
        for tick in 0..=expected {
            sim.run_combat();
            if tick == 0 {
                assert_eq!(sim.entities[b.0 as usize].hp, Fixed::from_int(hp) - damage);
            }
            if tick < expected {
                assert!(sim.entities[b.0 as usize].hp > Fixed::ZERO);
            }
        }
        assert!(
            sim.entities[b.0 as usize].hp <= Fixed::ZERO,
            "{attacker:?} vs {defender:?}"
        );
        assert_eq!(i64::from(sim.entities[a.0 as usize].ammunition), 90 - shots);
    }
}

#[test]
fn qa_command_storm_is_deterministic_and_inventory_stays_valid() {
    let mut first = arena();
    first.add_building(PlayerId(0), BuildingKind::PowerPlant, 3, 16);
    first.add_building(PlayerId(0), BuildingKind::ResearchLab, 3, 14);
    let barracks = first.add_building(PlayerId(0), BuildingKind::Barracks, 4, 14);
    let soldier = first.add_unit(PlayerId(0), UnitKind::Infantry, hex::center(5, 16));
    let mut second = first.clone();
    for tick in 0..10_000_u32 {
        let orders = alloc::vec![
            Command::Move {
                owner: PlayerId(0),
                unit: soldier,
                target: hex::center(
                    5 + u16::try_from(tick % 20).unwrap(),
                    10 + u16::try_from(tick % 10).unwrap()
                )
            },
            Command::Train {
                owner: PlayerId(0),
                barracks,
                kind: UnitKind::Infantry
            },
            Command::Research {
                owner: PlayerId(0),
                tech_id: tick % 16
            },
            Command::Sell {
                owner: PlayerId(0),
                building: EntityId(u32::MAX)
            },
            Command::Repair {
                owner: PlayerId(0),
                building: EntityId(u32::MAX)
            },
        ];
        first.step(&orders);
        second.step(&orders);
        assert_eq!(first.state_hash(), second.state_hash());
        assert!(first.money(PlayerId(0)) >= Fixed::ZERO);
        assert!(first.supply_used(PlayerId(0)) <= first.supply_cap(PlayerId(0)));
    }
}

#[test]
fn qa_core_kills_by_each_live_weapon_end_once_and_mutual_destruction_is_loss() {
    for kind in [
        UnitKind::Infantry,
        UnitKind::Tank,
        UnitKind::AntiArmor,
        UnitKind::Helicopter,
    ] {
        let mut sim = arena();
        sim.entities[1].hp = Fixed::ONE;
        let pos = sim.entities[1].pos - Vec2::new(Fixed::ONE, Fixed::ZERO);
        sim.add_unit(PlayerId(0), kind, pos);
        sim.run_combat();
        sim.clear_dead();
        assert_eq!(sim.winner(), Some(PlayerId(0)), "{kind:?}");
        let hash = sim.state_hash();
        for _ in 0..90 {
            sim.step(&[]);
        }
        assert_eq!(hash, sim.state_hash());
    }
    let mut sim = arena();
    sim.entities[0].hp = Fixed::ZERO;
    sim.entities[1].hp = Fixed::ZERO;
    sim.clear_dead();
    assert_eq!(sim.winner(), Some(PlayerId(1)));
    let hash = sim.state_hash();
    sim.step(&[]);
    assert_eq!(hash, sim.state_hash());
}

#[test]
#[ignore = "Measurement fixture; run explicitly in release mode"]
fn qa_profile_subsystems() {
    type TimedSystem = (&'static str, fn(&mut Sim));
    let mut sim = arena();
    for i in 0..5000 {
        sim.add_unit(
            PlayerId(0),
            UnitKind::Infantry,
            hex::center(8 + i % 25, 3 + (i / 25) % 25),
        );
    }
    let systems: [TimedSystem; 5] = [
        ("services", Sim::run_earthfront_services),
        ("production", Sim::run_production),
        ("movement", Sim::run_movement),
        ("combat", Sim::run_combat),
        ("harvesting", Sim::run_harvesters),
    ];
    for (name, system) in systems {
        let mut fixture = sim.clone();
        let start = std::time::Instant::now();
        for _ in 0..100 {
            system(&mut fixture);
        }
        std::println!(
            "QA_PROFILE {name} total_us={} calls=100",
            start.elapsed().as_micros()
        );
    }
}
