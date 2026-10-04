//! Live, dependency-free JSON snapshot bridge for the Godot presentation client.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rts_core::fixed::Fixed;
use rts_core::game::scenario::Scenario;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;

#[allow(
    clippy::too_many_lines,
    reason = "one explicit JSON frame keeps the dependency-free bridge schema easy to audit"
)]
fn snapshot_json(sim: &rts_core::game::sim::Sim) -> String {
    let views = sim.views();
    let mut out = String::with_capacity(512 + views.len() * 240);
    let human = PlayerId(0);
    let winner = sim.winner().map_or(-1, |PlayerId(id)| i32::from(id));
    let (researched, active) = sim.research_state(human);
    let active_id = active.map_or(-1_i64, |(id, _)| i64::from(id));
    let active_ticks = active.map_or(0, |(_, ticks)| ticks);
    let active_name = active
        .and_then(|(id, _)| sim.technology(id))
        .map_or_else(String::new, |node| node.name.to_owned());
    let suggested_id = sim.suggested_research(human);
    let suggested_name = suggested_id
        .and_then(|id| sim.technology(id))
        .map_or_else(String::new, |node| node.name.to_owned());
    let waves_survived = sim.waves_survived();
    let next_wave_ticks = sim
        .ticks_until_next_wave()
        .map_or(-1_i64, |ticks| i64::try_from(ticks).unwrap_or(i64::MAX));
    write!(
        out,
        "{{\"schema\":5,\"tick\":{},\"hash\":{},\"winner\":{},\"money_bits\":{},\"energy_bits\":{},\"labour_bits\":{},\"supply_used\":{},\"supply_cap\":{},\"era\":{},\"research_count\":{},\"active_research_id\":{},\"active_research_ticks\":{},\"active_research_name\":{:?},\"suggested_research_id\":{},\"suggested_research_name\":{:?},\"waves_survived\":{},\"next_wave_ticks\":{},\"map_width\":{},\"map_height\":{},\"surveying\":{},\"unlocked_buildings\":[",
        sim.tick(),
        sim.state_hash(),
        winner,
        sim.money(human).to_bits(),
        sim.energy(human).to_bits(),
        sim.labour(human).to_bits(),
        sim.supply_used(human),
        sim.supply_cap(human),
        sim.player_era(human),
        researched.count(),
        active_id,
        active_ticks,
        active_name,
        suggested_id.map_or(-1_i64, i64::from),
        suggested_name,
        waves_survived,
        next_wave_ticks,
        sim.map().width(),
        sim.map().height(),
        sim.surveying(),
    )
    .expect("writing to String cannot fail");

    let building_roster = [
        BuildingKind::PowerPlant,
        BuildingKind::Refinery,
        BuildingKind::Barracks,
        BuildingKind::GunTurret,
        BuildingKind::AaTurret,
        BuildingKind::Wall,
        BuildingKind::ResearchLab,
        BuildingKind::AntimatterPlant,
        BuildingKind::VehicleFactory,
        BuildingKind::Airfield,
        BuildingKind::SupplyDepot,
        BuildingKind::Battery,
    ];
    for (index, kind) in building_roster
        .into_iter()
        .filter(|kind| sim.building_unlocked(human, *kind))
        .enumerate()
    {
        if index != 0 {
            out.push(',');
        }
        write!(out, "{:?}", format!("{kind:?}")).expect("writing to String cannot fail");
    }
    out.push_str("],\"unlocked_units\":[");
    let unit_roster = [
        UnitKind::Infantry,
        UnitKind::AntiArmor,
        UnitKind::Tank,
        UnitKind::Helicopter,
        UnitKind::Capital,
        UnitKind::Harvester,
    ];
    for (index, kind) in unit_roster
        .into_iter()
        .filter(|kind| sim.unit_unlocked(human, *kind))
        .enumerate()
    {
        if index != 0 {
            out.push(',');
        }
        write!(out, "{:?}", format!("{kind:?}")).expect("writing to String cannot fail");
    }
    out.push_str("],\"blocked\":[");

    let mut blocked_index = 0_usize;
    for y in 0..sim.map().height() {
        for x in 0..sim.map().width() {
            if sim
                .map()
                .tile(i32::from(x), i32::from(y))
                .is_some_and(|tile| !tile.buildable)
            {
                if blocked_index != 0 {
                    out.push(',');
                }
                write!(out, "[{x},{y}]").expect("writing to String cannot fail");
                blocked_index += 1;
            }
        }
    }
    out.push_str("],\"deposits\":[");
    for (index, (x, y, deposit)) in sim.map().deposits().enumerate() {
        if index != 0 {
            out.push(',');
        }
        write!(
            out,
            "{{\"x\":{x},\"y\":{y},\"kind\":{:?},\"remaining\":{}}}",
            format!("{:?}", deposit.kind),
            deposit.remaining,
        )
        .expect("writing to String cannot fail");
    }
    out.push_str("],\"research_options\":[");
    let available = sim.available_research(human);
    let visible: Vec<u32> = if sim.is_earthfront() {
        (0..u32::try_from(sim.technology_count()).unwrap_or(0)).collect()
    } else {
        available.clone()
    };
    for (index, id) in visible.into_iter().enumerate() {
        if index != 0 {
            out.push(',');
        }
        let node = sim
            .technology(id)
            .expect("available research id is a grid node");
        let unlocks = node
            .unlocks
            .iter()
            .map(|unlock| format!("{:?}: {}", unlock.family, unlock.name))
            .collect::<Vec<_>>()
            .join("  •  ");
        write!(
            out,
            "{{\"id\":{},\"name\":{:?},\"era\":{},\"branch\":{},\"step\":{},\"reality\":\"{:?}\",\"money\":{},\"energy\":{},\"labour\":{},\"duration\":{},\"unlocks\":{:?},\"recommended\":{},\"available\":{},\"researched\":{},\"prerequisites\":{:?}}}",
            node.id,
            node.name,
            node.era,
            node.branch,
            node.step,
            node.reality,
            node.money,
            node.energy,
            node.labour,
            node.duration,
            unlocks,
            suggested_id == Some(node.id),
            available.contains(&id),
            researched.get(id),
            node.prereqs.iter().filter_map(|&required| sim.technology(required)).map(|n| n.name).collect::<Vec<_>>().join(" + "),
        )
        .expect("writing to String cannot fail");
    }
    out.push_str("],\"entities\":[");

    for (index, entity) in views.iter().enumerate() {
        if index != 0 {
            out.push(',');
        }
        let (category, kind) = match entity.kind {
            EntityKindView::Building(kind) => ("building", format!("{kind:?}")),
            EntityKindView::Unit(kind) => ("unit", format!("{kind:?}")),
        };
        let production = sim.production_status(entity.id);
        let production_name =
            production.map_or_else(String::new, |status| format!("{:?}", status.unit));
        write!(
            out,
            "{{\"id\":{},\"owner\":{},\"category\":\"{}\",\"kind\":\"{}\",\"x_bits\":{},\"z_bits\":{},\"hp_bits\":{},\"max_hp_bits\":{},\"shield_bits\":{},\"max_shield_bits\":{},\"ability_cd\":{},\"stun_ticks\":{},\"cargo\":{},\"rally_x_bits\":{},\"rally_z_bits\":{},\"construction\":{},\"construction_total\":{},\"production_name\":{:?},\"production_queued\":{},\"production_progress\":{},\"production_duration\":{}}}",
            entity.id.0,
            entity.owner.0,
            category,
            kind,
            entity.pos.x.to_bits(),
            entity.pos.y.to_bits(),
            entity.hp.to_bits(),
            entity.max_hp.to_bits(),
            entity.shield.to_bits(),
            entity.max_shield.to_bits(),
            entity.ability_cd,
            entity.stun_ticks,
            entity.cargo,
            entity.rally.map_or(-1, |point| point.x.to_bits()),
            entity.rally.map_or(-1, |point| point.y.to_bits()),
            entity.construction_remaining,
            entity.construction_total,
            production_name,
            production.map_or(0, |status| status.queued),
            production.map_or(0, |status| status.progress),
            production.map_or(0, |status| status.duration),
        )
        .expect("writing to String cannot fail");
    }
    let economy = sim.economy_view(human);
    write!(out, "],\"earthfront\":{},\"technology_total\":{},\"power_generation\":{},\"power_demand\":{},\"stored_energy\":{},\"storage_capacity\":{},\"ore_buffer\":{},\"depot_ammunition\":{},\"active_factories\":{},\"research_status\":{:?},\"incoming_doctrine\":{:?},\"services\":[",
        sim.is_earthfront(), sim.technology_count(), economy.generation, economy.demand,
        economy.stored_energy, economy.storage_capacity, economy.ore, economy.ammunition,
        economy.active_factories, economy.research_status, sim.incoming_doctrine()).expect("string write");
    for (i, entity) in views.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let (power, ammo, stock, ore) = sim.earthfront_entity_status(entity.id);
        write!(
            out,
            "{{\"id\":{},\"power\":{},\"ammo\":{},\"stock\":{},\"ore\":{},\"ore_capacity\":{},\"prototype\":{},\"alien_relay\":{}}}",
            entity.id.0, power, ammo, stock, ore, sim.refinery_capacity(),
            sim.prototype_factory(entity.owner) == Some(entity.id), sim.is_alien_relay(entity.id)
        )
        .expect("string write");
    }
    write!(out, "],\"alien_relays\":{},\"active_alien_relays\":{},\"next_expedition_size\":{},\"construction_zone\":[",
        sim.alien_relay_count(PlayerId(1), false), sim.alien_relay_count(PlayerId(1), true), sim.next_expedition_size()).expect("string write");
    let mut first_tile = true;
    for y in 0..sim.map().height() {
        for x in 0..sim.map().width() {
            if sim.construction_allowed_at(human, x, y) {
                if !first_tile {
                    out.push(',');
                }
                first_tile = false;
                write!(out, "[{x},{y}]").expect("string write");
            }
        }
    }
    out.push_str("]}");
    out
}

fn write_atomic(path: &Path, contents: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension("json.next");
    std::fs::write(&temporary, contents)?;
    std::fs::rename(temporary, path)
}

#[allow(
    clippy::too_many_lines,
    reason = "one protocol parser keeps every line-oriented Godot command auditable in one match"
)]
fn take_commands(path: &Path) -> Vec<Command> {
    // Legacy single-file input remains readable for older tools. The player client
    // publishes immutable packets with atomic rename, so polling cannot unlink an
    // open append stream or consume half an order.
    let mut contents = std::fs::read_to_string(path).unwrap_or_default();
    let _ = std::fs::remove_file(path);
    let directory = path.with_file_name("commands");
    let mut packets: Vec<_> = std::fs::read_dir(directory)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|packet| packet.extension().is_some_and(|ext| ext == "cmd"))
        .collect();
    packets.sort();
    for packet in packets {
        if let Ok(text) = std::fs::read_to_string(&packet) {
            contents.push_str(&text);
            contents.push('\n');
            let _ = std::fs::remove_file(packet);
        }
    }
    contents
        .lines()
        .filter_map(|line| {
            let mut fields = line.split(',');
            match fields.next()? {
                "move" | "attack" => {
                    let mode = line.starts_with("attack,");
                    let unit = fields.next()?.parse::<u32>().ok()?;
                    let x_bits = fields.next()?.parse::<i64>().ok()?;
                    let z_bits = fields.next()?.parse::<i64>().ok()?;
                    let target = Vec2::new(Fixed::from_bits(x_bits), Fixed::from_bits(z_bits));
                    Some(if mode {
                        Command::AttackMove {
                            owner: PlayerId(0),
                            unit: EntityId(unit),
                            target,
                        }
                    } else {
                        Command::Move {
                            owner: PlayerId(0),
                            unit: EntityId(unit),
                            target,
                        }
                    })
                }
                "train" => {
                    let barracks = fields.next()?.parse::<u32>().ok()?;
                    let kind = match fields.next()? {
                        "Harvester" => UnitKind::Harvester,
                        "Infantry" => UnitKind::Infantry,
                        "Tank" => UnitKind::Tank,
                        "AntiArmor" => UnitKind::AntiArmor,
                        "Helicopter" => UnitKind::Helicopter,
                        "Capital" => UnitKind::Capital,
                        _ => return None,
                    };
                    Some(Command::Train {
                        owner: PlayerId(0),
                        barracks: EntityId(barracks),
                        kind,
                    })
                }
                "build" => {
                    let kind = match fields.next()? {
                        "PowerPlant" => BuildingKind::PowerPlant,
                        "Refinery" => BuildingKind::Refinery,
                        "Barracks" => BuildingKind::Barracks,
                        "GunTurret" => BuildingKind::GunTurret,
                        "AaTurret" => BuildingKind::AaTurret,
                        "Wall" => BuildingKind::Wall,
                        "ResearchLab" => BuildingKind::ResearchLab,
                        "AntimatterPlant" => BuildingKind::AntimatterPlant,
                        "VehicleFactory" => BuildingKind::VehicleFactory,
                        "Airfield" => BuildingKind::Airfield,
                        "SupplyDepot" => BuildingKind::SupplyDepot,
                        "Battery" => BuildingKind::Battery,
                        _ => return None,
                    };
                    let x = fields.next()?.parse::<u16>().ok()?;
                    let y = fields.next()?.parse::<u16>().ok()?;
                    Some(Command::Build {
                        owner: PlayerId(0),
                        kind,
                        x,
                        y,
                    })
                }
                "research" => {
                    let tech_id = fields.next()?.parse::<u32>().ok()?;
                    Some(Command::Research {
                        owner: PlayerId(0),
                        tech_id,
                    })
                }
                "rally" | "ability" => {
                    let ability = line.starts_with("ability,");
                    let entity = fields.next()?.parse::<u32>().ok()?;
                    let x_bits = fields.next()?.parse::<i64>().ok()?;
                    let z_bits = fields.next()?.parse::<i64>().ok()?;
                    let target = Vec2::new(Fixed::from_bits(x_bits), Fixed::from_bits(z_bits));
                    Some(if ability {
                        Command::UseAbility {
                            owner: PlayerId(0),
                            unit: EntityId(entity),
                            target,
                        }
                    } else {
                        Command::SetRally {
                            owner: PlayerId(0),
                            producer: EntityId(entity),
                            target,
                        }
                    })
                }
                "repair" | "sell" => {
                    let repair = line.starts_with("repair,");
                    let building = EntityId(fields.next()?.parse::<u32>().ok()?);
                    Some(if repair {
                        Command::Repair {
                            owner: PlayerId(0),
                            building,
                        }
                    } else {
                        Command::Sell {
                            owner: PlayerId(0),
                            building,
                        }
                    })
                }
                _ => None,
            }
        })
        .collect()
}

fn clear_command_packets(path: &Path) -> std::io::Result<()> {
    let directory = path.with_file_name("commands");
    std::fs::create_dir_all(&directory)?;
    for entry in std::fs::read_dir(directory)? {
        let packet = entry?.path();
        if packet
            .extension()
            .is_some_and(|ext| ext == "cmd" || ext == "next")
        {
            std::fs::remove_file(packet)?;
        }
    }
    Ok(())
}

fn main() -> std::io::Result<()> {
    let output = std::env::args().nth(1).map_or_else(
        || PathBuf::from("godot3d/runtime/snapshot.json"),
        PathBuf::from,
    );
    let frame_limit = std::env::args()
        .nth(2)
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(u64::MAX);

    let mut sim = Scenario::Survival.build(2026);
    sim.set_balance(rts_data::load_default());
    // Match the primary client: the deterministic simulation is authored at 30 Hz.
    // Godot renders between snapshots, but must not double the gameplay speed.
    let frame_time = Duration::from_micros(33_333);
    let command_path = output.with_file_name("commands.txt");
    let start_path = output.with_file_name("start.flag");
    let restart_path = output.with_file_name("restart.flag");
    // Never let an order left by a previous closed match disable opening AI.
    let _ = std::fs::remove_file(&command_path);
    let _ = std::fs::remove_file(&start_path);
    let _ = std::fs::remove_file(&restart_path);
    clear_command_packets(&command_path)?;
    let mut mission_started = false;

    for _ in 0..frame_limit {
        if restart_path.exists() {
            let _ = std::fs::remove_file(&restart_path);
            // A rapid second Deploy click must not auto-start the next mission.
            let _ = std::fs::remove_file(&start_path);
            let _ = std::fs::remove_file(&command_path);
            clear_command_packets(&command_path)?;
            sim = Scenario::Survival.build(2026);
            sim.set_balance(rts_data::load_default());
            mission_started = false;
        }
        if !mission_started {
            if start_path.exists() {
                let _ = std::fs::remove_file(&start_path);
                mission_started = true;
            } else {
                write_atomic(&output, &snapshot_json(&sim))?;
                std::thread::sleep(frame_time);
                continue;
            }
        }
        let started = Instant::now();
        let player_commands = take_commands(&command_path);
        // The human-side AI exists only to resolve Survival's initial survey at
        // the deterministic premium site. From the first active tick onward the
        // player owns every economy, production, science, and tactical decision.
        let mut commands = if sim.surveying() {
            sim.ai_commands(PlayerId(0))
        } else {
            Vec::new()
        };
        // Keep the beachhead garrison defensive during the authored 90-second
        // build-up. Once wave one arrives, the enemy economy and tactics activate.
        if sim.waves_survived() > 0 {
            commands.extend(sim.ai_commands(PlayerId(1)));
        }
        commands.extend(player_commands);
        sim.step(&commands);
        write_atomic(&output, &snapshot_json(&sim))?;
        std::thread::sleep(frame_time.saturating_sub(started.elapsed()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{snapshot_json, take_commands, BuildingKind, Command, EntityId, UnitKind};
    use rts_core::game::scenario::Scenario;

    #[test]
    fn qa_concurrent_command_transport_preserves_every_order() {
        use std::sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        };
        let root =
            std::env::temp_dir().join(format!("earthfront-transport-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("commands.txt");
        std::fs::create_dir_all(root.join("commands")).unwrap();
        let done = Arc::new(AtomicBool::new(false));
        let producer_done = done.clone();
        let producer_path = path.clone();
        let producer = std::thread::spawn(move || {
            for id in 0..1000 {
                let packet = producer_path
                    .with_file_name("commands")
                    .join(format!("{id:020}.cmd"));
                let temporary = packet.with_extension("next");
                std::fs::write(&temporary, format!("move,{id},0,0\n")).unwrap();
                std::fs::rename(temporary, packet).unwrap();
                std::thread::sleep(std::time::Duration::from_micros(100));
            }
            producer_done.store(true, Ordering::SeqCst);
        });
        let mut received = Vec::new();
        while !done.load(Ordering::SeqCst) {
            received.extend(take_commands(&path));
            std::thread::sleep(std::time::Duration::from_micros(100));
        }
        producer.join().unwrap();
        received.extend(take_commands(&path));
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(received.len(), 1000, "concurrent player orders were lost");
    }

    #[test]
    fn snapshot_is_parseable_shape_and_contains_entities() {
        let sim = Scenario::Survival.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(json.contains("\"era\":0"));
        assert!(json.contains("\"alien_relays\":2"));
        assert!(json.contains("\"next_expedition_size\":10"));
        assert_eq!(json.matches("\"alien_relay\":true").count(), 2);
        assert!(json.contains("\"research_count\":0"));
        assert!(json.contains("\"suggested_research_name\":"));
        assert!(json.contains("\"waves_survived\":0"));
        assert!(json.contains("\"next_wave_ticks\":"));
        assert!(json.contains("\"unlocked_buildings\":["));
        assert!(json.contains("\"unlocked_units\":["));
        assert!(json.contains("\"max_shield_bits\":"));
        assert!(json.contains("\"ability_cd\":"));
        assert!(json.contains("\"rally_x_bits\":"));
        assert!(json.contains("\"map_width\":44"));
        assert!(json.contains("\"map_height\":26"));
        assert!(json.contains("\"surveying\":true"));
        assert!(json.contains("\"blocked\":["));
        assert!(json.contains("\"deposits\":["));
        assert!(json.contains("\"research_options\":["));
        assert!(json.contains("\"construction_total\":"));
        assert!(json.contains("\"production_name\":"));
        assert!(json.contains("\"entities\":[{"));
        assert!(json.ends_with("]}"));
    }

    #[test]
    fn godot_command_file_supports_rts_orders() {
        let path =
            std::env::temp_dir().join(format!("earthfront-commands-{}.txt", std::process::id()));
        std::fs::write(
            &path,
            "move,7,65536,131072\nattack,8,196608,262144\ntrain,9,Tank\nbuild,Barracks,4,5\nresearch,20\nrally,9,327680,393216\nability,7,458752,524288\nrepair,11\nsell,12\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 9);
        assert!(matches!(
            commands[0],
            Command::Move {
                unit: EntityId(7),
                ..
            }
        ));
        assert!(matches!(
            commands[1],
            Command::AttackMove {
                unit: EntityId(8),
                ..
            }
        ));
        assert!(matches!(
            commands[2],
            Command::Train {
                barracks: EntityId(9),
                kind: UnitKind::Tank,
                ..
            }
        ));
        assert!(matches!(
            commands[3],
            Command::Build {
                kind: BuildingKind::Barracks,
                x: 4,
                y: 5,
                ..
            }
        ));
        assert!(matches!(commands[4], Command::Research { tech_id: 20, .. }));
        assert!(matches!(
            commands[5],
            Command::SetRally {
                producer: EntityId(9),
                ..
            }
        ));
        assert!(matches!(
            commands[6],
            Command::UseAbility {
                unit: EntityId(7),
                ..
            }
        ));
        assert!(matches!(
            commands[7],
            Command::Repair {
                building: EntityId(11),
                ..
            }
        ));
        assert!(matches!(
            commands[8],
            Command::Sell {
                building: EntityId(12),
                ..
            }
        ));
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }
    #[test]
    fn godot_command_file_covers_the_complete_combat_roster() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-roster-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "train,9,AntiArmor\ntrain,9,Helicopter\ntrain,9,Capital\nbuild,AaTurret,1,2\nbuild,Wall,2,3\nbuild,ResearchLab,3,4\nbuild,AntimatterPlant,4,5\n",
        )
        .expect("write complete-roster fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 7);
        assert!(matches!(
            commands[0],
            Command::Train {
                kind: UnitKind::AntiArmor,
                ..
            }
        ));
        assert!(matches!(
            commands[1],
            Command::Train {
                kind: UnitKind::Helicopter,
                ..
            }
        ));
        assert!(matches!(
            commands[2],
            Command::Train {
                kind: UnitKind::Capital,
                ..
            }
        ));
        assert!(matches!(
            commands[3],
            Command::Build {
                kind: BuildingKind::AaTurret,
                ..
            }
        ));
        assert!(matches!(
            commands[4],
            Command::Build {
                kind: BuildingKind::Wall,
                ..
            }
        ));
        assert!(matches!(
            commands[5],
            Command::Build {
                kind: BuildingKind::ResearchLab,
                ..
            }
        ));
        assert!(matches!(
            commands[6],
            Command::Build {
                kind: BuildingKind::AntimatterPlant,
                ..
            }
        ));
        assert!(!path.exists(), "bridge consumes the roster file atomically");
    }
}
