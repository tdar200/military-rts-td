//! Live, dependency-free JSON snapshot bridge for the Godot presentation client.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rts_core::fixed::Fixed;
use rts_core::game::kestrel;
use rts_core::game::map::Ground;
use rts_core::game::scenario::Scenario;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, SupplyState};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;

fn snapshot_json(sim: &rts_core::game::sim::Sim) -> String {
    snapshot_json_with(sim, &supply_links_json(sim), &ShotWindow::new())
}

/// How many ticks of shots the snapshot carries (0.6 s at 30 Hz). The sim steps at
/// 30 Hz but the Godot client polls about every 0.12 s, so the latest tick alone would
/// miss most shots; the client dedups the overlapping windows by (tick, attacker, target).
const SHOT_WINDOW_TICKS: u64 = 18;

/// One shot: the tick it was fired on and the attacker and target positions.
type Shot = (u64, Vec2, Vec2);

/// Rolling window of the most recent shots, oldest first. Cosmetic only: it is never
/// part of the sim state and never read back by it.
struct ShotWindow {
    shots: Vec<Shot>,
}

impl ShotWindow {
    const fn new() -> Self {
        Self { shots: Vec::new() }
    }

    /// Adds the shots the sim fired on `tick` (its tick counter right after the step),
    /// then drops everything `SHOT_WINDOW_TICKS` or more ticks old.
    fn record(&mut self, tick: u64, attacks: &[(Vec2, Vec2)]) {
        self.shots.extend(
            attacks
                .iter()
                .map(|&(attacker, target)| (tick, attacker, target)),
        );
        self.shots
            .retain(|&(fired, _, _)| tick.saturating_sub(fired) < SHOT_WINDOW_TICKS);
    }

    /// Forgets every shot (scenario restart).
    fn clear(&mut self) {
        self.shots.clear();
    }

    #[cfg(test)]
    const fn len(&self) -> usize {
        self.shots.len()
    }

    #[cfg(test)]
    const fn is_empty(&self) -> bool {
        self.shots.is_empty()
    }

    /// `[[tick,ax_bits,az_bits,tx_bits,tz_bits],...]`, oldest first.
    fn json_array(&self) -> String {
        let mut out = String::from("[");
        for (i, (tick, attacker, target)) in self.shots.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(
                out,
                "[{tick},{},{},{},{}]",
                attacker.x.to_bits(),
                attacker.y.to_bits(),
                target.x.to_bits(),
                target.y.to_bits()
            )
            .expect("string write");
        }
        out.push(']');
        out
    }
}

/// The human's depot-to-building supply links as a JSON array (see `SupplyLinkCache`).
fn supply_links_json(sim: &rts_core::game::sim::Sim) -> String {
    let mut out = String::from("[");
    for (i, link) in sim
        .earthfront_supply_links(PlayerId(0))
        .into_iter()
        .enumerate()
    {
        if i > 0 {
            out.push(',');
        }
        let state = match link.state {
            SupplyState::Supplied => "ok",
            SupplyState::Severed => "severed",
        };
        write!(
            out,
            "{{\"depot\":{},\"target\":{},\"state\":\"{state}\"}}",
            link.depot.0, link.target.0
        )
        .expect("string write");
    }
    out.push(']');
    out
}

/// Throttle for `supply_links_json`: each link costs path searches, so the live loop
/// recomputes only on the supply beat (the sim feeds ammunition every 30 ticks) and
/// serves the cached array in between. The loop writes one snapshot per tick, so the
/// array shown at tick T is always the sim's links at the last multiple of 30 at or
/// below T (or at the first snapshot after a start or restart): deterministic per tick.
struct SupplyLinkCache {
    tick: Option<u64>,
    json: String,
}

impl SupplyLinkCache {
    const BEAT: u64 = 30;

    const fn new() -> Self {
        Self {
            tick: None,
            json: String::new(),
        }
    }

    fn get(&mut self, sim: &rts_core::game::sim::Sim) -> &str {
        let now = sim.tick();
        let stale = self
            .tick
            .is_none_or(|t| now < t || now / Self::BEAT != t / Self::BEAT);
        if stale {
            self.json = supply_links_json(sim);
            self.tick = Some(now);
        }
        &self.json
    }
}

#[allow(
    clippy::too_many_lines,
    reason = "one explicit JSON frame keeps the dependency-free bridge schema easy to audit"
)]
fn snapshot_json_with(
    sim: &rts_core::game::sim::Sim,
    supply_links: &str,
    shots: &ShotWindow,
) -> String {
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
            "{{\"id\":{},\"owner\":{},\"category\":\"{}\",\"kind\":\"{}\",\"x_bits\":{},\"z_bits\":{},\"hp_bits\":{},\"max_hp_bits\":{},\"shield_bits\":{},\"max_shield_bits\":{},\"ability_cd\":{},\"stun_ticks\":{},\"cargo\":{},\"rally_x_bits\":{},\"rally_z_bits\":{},\"construction\":{},\"construction_total\":{},\"production_name\":{:?},\"production_queued\":{},\"production_progress\":{},\"production_duration\":{}",
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
        // Additive per-entity fields, appended last so existing consumers are untouched.
        write!(
            out,
            ",\"idle\":{}",
            entity.owner == human && sim.is_idle_unit(entity.id)
        )
        .expect("writing to String cannot fail");
        match entity.kind {
            EntityKindView::Unit(_) => write!(out, ",\"rank\":{}", sim.rank_of(entity.id)),
            EntityKindView::Building(BuildingKind::PowerPlant) => {
                write!(out, ",\"river_kw\":{}", sim.river_bonus_kw_of(entity.id))
            }
            EntityKindView::Building(BuildingKind::Refinery) => {
                write!(
                    out,
                    ",\"ore_bonus\":{}",
                    sim.ore_bonus_pct_of(entity.id) > 0
                )
            }
            EntityKindView::Building(_) => Ok(()),
        }
        .expect("writing to String cannot fail");
        out.push('}');
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
    out.push(']');
    write_additive_fields(&mut out, sim);
    out.push_str(",\"supply_links\":");
    out.push_str(supply_links);
    // Kestrel only (the ground-layer scenario): Survival keeps its exact shape.
    if is_kestrel_map(sim) {
        out.push_str(",\"shots\":");
        out.push_str(&shots.json_array());
    }
    out.push('}');
    out
}

/// True when the sim's ground layer is exactly the authored Kestrel Reach text map.
/// The sim carries no scenario tag, so the bridge recognises the fixed map by content.
fn is_kestrel_map(sim: &rts_core::game::sim::Sim) -> bool {
    let ground = sim.map().ground_iter().map(Ground::glyph);
    ground.eq(kestrel::ROWS.iter().flat_map(|row| row.chars()))
}

/// The route alien waves take: holdfast tile to home Command Center tile, inclusive of
/// both ends; empty when the map offers none.
///
/// The home Command Center's own tile is blocked once the building stands, so a
/// forward search to it fails; the free-standing holdfast tile is not, so search
/// home to holdfast and reverse (the waypoints after `HOME_CC`, including `HOLDFAST`).
fn kestrel_wave_route(map: &rts_core::game::map::Map) -> Vec<(u16, u16)> {
    use rts_core::game::path::find_path;
    if let Some(forward) = find_path(map, kestrel::HOLDFAST, kestrel::HOME_CC) {
        return std::iter::once(kestrel::HOLDFAST).chain(forward).collect();
    }
    find_path(map, kestrel::HOME_CC, kestrel::HOLDFAST).map_or_else(Vec::new, |back| {
        back.into_iter()
            .rev()
            .chain(std::iter::once(kestrel::HOME_CC))
            .collect()
    })
}

/// Additive top-level fields (schema stays 5): appended after every pre-existing key.
/// `map_name`, `regions` and `core_node` appear only for Kestrel Reach; `ground`,
/// `ground_table` and `wave_route` appear for every scenario.
fn write_additive_fields(out: &mut String, sim: &rts_core::game::sim::Sim) {
    let kestrel_map = is_kestrel_map(sim);
    if kestrel_map {
        write!(out, ",\"map_name\":{:?},\"regions\":[", kestrel::MAP_NAME).expect("string write");
        for (i, r) in kestrel::REGIONS.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(
                out,
                "{{\"name\":{:?},\"kind\":{:?},\"x0\":{},\"y0\":{},\"x1\":{},\"y1\":{}}}",
                r.name, r.kind, r.x0, r.y0, r.x1, r.y1
            )
            .expect("string write");
        }
        out.push(']');
    }
    out.push_str(",\"ground\":\"");
    out.extend(sim.map().ground_iter().map(Ground::glyph));
    out.push_str("\",\"ground_table\":[");
    for (i, g) in Ground::ALL.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let p = g.props();
        write!(
            out,
            "{{\"glyph\":\"{}\",\"name\":{:?},\"path_cost\":{},\"infantry_pct\":{},\"vehicle_pct\":{},\"cover_pct\":{},\"range_pct\":{},\"buildable\":{},\"passable\":{}}}",
            g.glyph(), g.name(), p.path_cost, p.infantry_pct, p.vehicle_pct, p.cover_pct,
            p.range_pct, p.buildable, p.passable
        )
        .expect("string write");
    }
    out.push_str("],\"wave_route\":[");
    if kestrel_map {
        for (i, (x, y)) in kestrel_wave_route(sim.map()).into_iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(out, "[{x},{y}]").expect("string write");
        }
    }
    out.push(']');
    if kestrel_map {
        write!(
            out,
            ",\"core_node\":[{},{}]",
            kestrel::CORE_NODE.0,
            kestrel::CORE_NODE.1
        )
        .expect("string write");
    }
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

/// Parsed command line: the two historical positional arguments plus the flags.
#[derive(Debug)]
struct Options {
    output: PathBuf,
    frame_limit: u64,
    scenario: Scenario,
    dump_snapshot: Option<PathBuf>,
}

/// Maps a `--scenario` value to a scenario (Survival is the default).
fn parse_scenario(value: &str) -> Result<Scenario, String> {
    match value {
        "survival" => Ok(Scenario::Survival),
        "kestrel" => Ok(Scenario::KestrelReach),
        other => Err(format!(
            "unknown scenario '{other}' (expected 'kestrel' or 'survival')"
        )),
    }
}

/// Parses `[--scenario S] [--dump-snapshot P] [output [frame_limit]]`. Flags (also
/// as `--flag=value`) may appear anywhere; they are stripped before the positional
/// arguments (arg 1 = output path, arg 2 = frame limit) are read.
fn parse_args(args: impl IntoIterator<Item = String>) -> Result<Options, String> {
    let mut positional = Vec::new();
    let mut scenario = Scenario::Survival;
    let mut dump_snapshot = None;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let (flag, inline) = match arg.split_once('=') {
            Some((flag, value)) if flag.starts_with("--") => {
                (flag.to_owned(), Some(value.to_owned()))
            }
            _ => (arg.clone(), None),
        };
        match flag.as_str() {
            "--scenario" | "--dump-snapshot" => {
                let value = inline
                    .or_else(|| args.next())
                    .ok_or_else(|| format!("{flag} needs a value"))?;
                if flag == "--scenario" {
                    scenario = parse_scenario(&value)?;
                } else {
                    dump_snapshot = Some(PathBuf::from(value));
                }
            }
            _ if flag.starts_with("--") => return Err(format!("unknown flag '{flag}'")),
            _ => positional.push(arg),
        }
    }
    Ok(Options {
        output: positional.first().map_or_else(
            || PathBuf::from("godot3d/runtime/snapshot.json"),
            PathBuf::from,
        ),
        frame_limit: positional
            .get(1)
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(u64::MAX),
        scenario,
        dump_snapshot,
    })
}

fn main() -> std::io::Result<()> {
    let options = match parse_args(std::env::args().skip(1)) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("godot-bridge: {message}");
            std::process::exit(2);
        }
    };
    let Options {
        output,
        frame_limit,
        scenario,
        dump_snapshot,
    } = options;

    let mut sim = scenario.build(2026);
    sim.set_balance(rts_data::load_default());
    if let Some(path) = dump_snapshot {
        // One frame of the chosen scenario's initial snapshot, for Godot test fixtures.
        return write_atomic(&path, &snapshot_json(&sim));
    }
    // Match the primary client: the deterministic simulation is authored at 30 Hz.
    // Godot renders between snapshots, but must not double the gameplay speed.
    let frame_time = Duration::from_micros(33_333);
    let command_path = output.with_file_name("commands.txt");
    let start_path = output.with_file_name("start.flag");
    let restart_path = output.with_file_name("restart.flag");
    // Godot's pause menu holds the world still by keeping this file in place; removing it resumes the run.
    let pause_path = output.with_file_name("pause.flag");
    // Never let an order left by a previous closed match disable opening AI.
    let _ = std::fs::remove_file(&command_path);
    let _ = std::fs::remove_file(&start_path);
    let _ = std::fs::remove_file(&restart_path);
    let _ = std::fs::remove_file(&pause_path);
    clear_command_packets(&command_path)?;
    let mut mission_started = false;
    let mut supply_cache = SupplyLinkCache::new();
    let mut shots = ShotWindow::new();

    for _ in 0..frame_limit {
        if restart_path.exists() {
            let _ = std::fs::remove_file(&restart_path);
            // A rapid second Deploy click must not auto-start the next mission.
            let _ = std::fs::remove_file(&start_path);
            let _ = std::fs::remove_file(&command_path);
            let _ = std::fs::remove_file(&pause_path);
            clear_command_packets(&command_path)?;
            sim = scenario.build(2026);
            sim.set_balance(rts_data::load_default());
            mission_started = false;
            supply_cache = SupplyLinkCache::new();
            shots.clear();
        }
        if !mission_started {
            if start_path.exists() {
                let _ = std::fs::remove_file(&start_path);
                mission_started = true;
            } else {
                write_atomic(
                    &output,
                    &snapshot_json_with(&sim, supply_cache.get(&sim), &shots),
                )?;
                std::thread::sleep(frame_time);
                continue;
            }
        }
        if pause_path.exists() {
            // Paused: no step, no commands taken (they wait for the resume), the same snapshot stays current.
            write_atomic(
                &output,
                &snapshot_json_with(&sim, supply_cache.get(&sim), &shots),
            )?;
            std::thread::sleep(frame_time);
            continue;
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
        // The scenario's scripted orders (Kestrel Reach: the pre-wave probe); empty elsewhere.
        commands.extend(scenario.scripted_commands(&sim));
        commands.extend(player_commands);
        sim.step(&commands);
        shots.record(sim.tick(), sim.recent_attacks());
        write_atomic(
            &output,
            &snapshot_json_with(&sim, supply_cache.get(&sim), &shots),
        )?;
        std::thread::sleep(frame_time.saturating_sub(started.elapsed()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        parse_args, snapshot_json, snapshot_json_with, supply_links_json, take_commands,
        BuildingKind, Command, EntityId, PlayerId, ShotWindow, SupplyLinkCache, UnitKind,
        SHOT_WINDOW_TICKS,
    };
    use rts_core::game::scenario::Scenario;

    /// Value of the string field `"key":"..."` (first occurrence).
    fn extract_str(json: &str, key: &str) -> String {
        let needle = format!("\"{key}\":\"");
        let start = json.find(&needle).expect("key present") + needle.len();
        let end = json[start..].find('"').expect("closing quote") + start;
        json[start..end].to_owned()
    }

    /// The `{...}` object of the entity with this id (entity objects hold no nesting).
    fn entity_object(json: &str, id: u32) -> String {
        let needle = format!("{{\"id\":{id},\"owner\"");
        let start = json.find(&needle).expect("entity present");
        let end = json[start..].find('}').expect("entity end") + start;
        json[start..=end].to_owned()
    }

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_owned()).collect()
    }

    fn human_infantry(sim: &rts_core::game::sim::Sim) -> EntityId {
        sim.views()
            .into_iter()
            .find(|v| {
                v.owner.0 == 0
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Unit(UnitKind::Infantry)
                    )
            })
            .expect("a human infantry unit")
            .id
    }

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
        assert!(json.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn survival_snapshot_is_unchanged_in_shape_and_has_all_grass_ground() {
        let sim = Scenario::Survival.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(!json.contains("\"map_name\""));
        assert!(!json.contains("\"regions\""));
        assert!(!json.contains("\"core_node\""));
        let g = extract_str(&json, "ground");
        assert_eq!(g.len(), 44 * 26);
        assert!(g.chars().all(|c| c == 'g'));
        assert!(json.contains("\"ground_table\":["));
        assert!(json.contains("\"wave_route\":[]"));
        assert!(json.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn kestrel_snapshot_carries_names_regions_ground_and_table() {
        let sim = Scenario::KestrelReach.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(json.contains("\"map_name\":\"Kestrel Reach\""));
        assert!(json.contains("\"name\":\"Wyllow Ford\""));
        assert!(json.contains("\"ground_table\":["));
        assert!(json.contains("\"wave_route\":["));
        assert!(json.contains("\"core_node\":[37,8]"));
        let g = extract_str(&json, "ground");
        assert_eq!(g.len(), 44 * 26);
        assert!(g.contains('r') && g.contains('w') && g.contains('h'));
        // Additive and last: at tick 0 the Command Center holds no stock yet, so the
        // three prebuilt structures beside it are not served until the first supply beat.
        assert!(json.ends_with("\"core_node\":[37,8],\"supply_links\":[],\"shots\":[]}"));
        assert!(json.starts_with("{\"schema\":5,"));
    }

    /// A Kestrel sim where the home Command Center (id 0) has stock and a turret in reach.
    fn kestrel_with_a_served_turret() -> (rts_core::game::sim::Sim, EntityId) {
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let turret = sim.add_building(PlayerId(0), BuildingKind::GunTurret, 9, 10);
        while sim.tick() < 30 {
            sim.step(&[]);
        }
        (sim, turret)
    }

    #[test]
    fn supply_links_key_lists_a_supplied_building() {
        let (sim, turret) = kestrel_with_a_served_turret();
        let json = snapshot_json(&sim);
        let link = format!("{{\"depot\":0,\"target\":{},\"state\":\"ok\"}}", turret.0);
        assert!(json.contains(&link), "{link} missing");
        // The Kestrel start also has the Power Plant (1), Refinery (2) and Barracks (3)
        // standing beside the Command Center, so the CC serves them too, listed before
        // the turret in ascending entity order.
        let served: Vec<String> = [1, 2, 3, turret.0]
            .iter()
            .map(|t| format!("{{\"depot\":0,\"target\":{t},\"state\":\"ok\"}}"))
            .collect();
        assert!(
            json.ends_with(&format!(
                "\"supply_links\":[{}],\"shots\":[]}}",
                served.join(",")
            )),
            "supply_links precedes the trailing shots key"
        );
        // Pure and deterministic for a given sim state.
        assert_eq!(supply_links_json(&sim), supply_links_json(&sim));
    }

    #[test]
    fn supply_link_cache_recomputes_only_on_the_beat() {
        let (mut sim, turret) = kestrel_with_a_served_turret();
        let mut cache = SupplyLinkCache::new();
        let at_beat = cache.get(&sim).to_owned();
        assert_eq!(at_beat, supply_links_json(&sim));
        assert!(at_beat.contains(&format!("\"target\":{}", turret.0)));
        // A second building in reach appears fresh immediately but not in the cache...
        sim.step(&[]);
        let late = sim.add_building(PlayerId(0), BuildingKind::GunTurret, 9, 12);
        let fresh = supply_links_json(&sim);
        assert!(fresh.contains(&format!("\"target\":{}", late.0)));
        assert_eq!(cache.get(&sim), at_beat);
        while sim.tick() < 59 {
            sim.step(&[]);
            assert_eq!(cache.get(&sim), at_beat, "tick {}", sim.tick());
        }
        // ...until the next supply beat.
        sim.step(&[]);
        assert_eq!(sim.tick(), 60);
        assert!(cache.get(&sim).contains(&format!("\"target\":{}", late.0)));
    }

    #[test]
    fn kestrel_snapshot_is_valid_json_shape() {
        let json = snapshot_json(&Scenario::KestrelReach.build(1));
        assert_eq!(json.matches('{').count(), json.matches('}').count());
        assert_eq!(json.matches('[').count(), json.matches(']').count());
        assert!(!json.contains(",]") && !json.contains(",}"));
        let survival = snapshot_json(&Scenario::Survival.build(1));
        assert_eq!(survival.matches('{').count(), survival.matches('}').count());
        assert!(!survival.contains(",]") && !survival.contains(",}"));
    }

    /// A Kestrel sim with two opposing infantry squads in rifle range, in open ground.
    fn kestrel_firefight() -> (rts_core::game::sim::Sim, EntityId, EntityId) {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let at = |x: i32, y: i32| Vec2::new(Fixed::from_int(x), Fixed::from_int(y));
        let ours = sim.add_unit(PlayerId(0), UnitKind::Infantry, at(20, 12));
        let theirs = sim.add_unit(PlayerId(1), UnitKind::Infantry, at(21, 12));
        (sim, ours, theirs)
    }

    /// Steps once and feeds the window the way the main loop does.
    fn step_into(sim: &mut rts_core::game::sim::Sim, window: &mut ShotWindow) {
        sim.step(&[]);
        window.record(sim.tick(), sim.recent_attacks());
    }

    /// Parses the `"shots":[[...],...]` value into rows of five integers.
    fn parse_shots(json: &str) -> Vec<[i64; 5]> {
        let start = json.find("\"shots\":[").expect("shots key") + "\"shots\":[".len();
        let body = &json[start..json.len() - 2];
        if body.is_empty() {
            return Vec::new();
        }
        body.trim_start_matches('[')
            .split("],[")
            .map(|row| {
                let nums: Vec<i64> = row
                    .trim_end_matches(']')
                    .split(',')
                    .map(|n| n.parse().expect("integer"))
                    .collect();
                <[i64; 5]>::try_from(nums).expect("five integers per shot")
            })
            .collect()
    }

    #[test]
    fn kestrel_snapshot_carries_the_recent_shots_of_the_real_shooters() {
        let (mut sim, ours, theirs) = kestrel_firefight();
        let mut window = ShotWindow::new();
        let mut guard = 0;
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
            guard += 1;
            assert!(guard < 200, "the two squads never fired");
        }
        let pos = |id: EntityId| {
            sim.views()
                .into_iter()
                .find(|v| v.id == id)
                .expect("unit")
                .pos
        };
        let (a, t) = (pos(ours), pos(theirs));
        let json = snapshot_json_with(&sim, "[]", &window);
        assert!(json.ends_with("]]}"), "shots is the final key: {json}");
        let shots = parse_shots(&json);
        assert!(!shots.is_empty());
        let tick = i64::try_from(sim.tick()).unwrap();
        let last = shots.last().unwrap();
        assert_eq!(last[0], tick, "tagged with the tick it was fired on");
        let pair = |p: rts_core::vec::Vec2| (p.x.to_bits(), p.y.to_bits());
        let shot_pair = |s: &[i64; 5]| ((s[1], s[2]), (s[3], s[4]));
        assert!(
            shots
                .iter()
                .any(|s| shot_pair(s) == (pair(a), pair(t)) || shot_pair(s) == (pair(t), pair(a))),
            "an entry must run from one real unit to the other: {shots:?}"
        );
    }

    #[test]
    fn shots_older_than_the_window_are_pruned_oldest_first() {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let p = |n: i32| Vec2::new(Fixed::from_int(n), Fixed::from_int(n));
        let mut window = ShotWindow::new();
        window.record(10, &[(p(1), p(2))]);
        window.record(11, &[(p(3), p(4)), (p(5), p(6))]);
        assert_eq!(window.len(), 3);
        // Still inside: age 17 at tick 27.
        window.record(10 + SHOT_WINDOW_TICKS - 1, &[]);
        assert_eq!(window.len(), 3);
        // Tick 10 falls out at age 18, tick 11 one tick later.
        window.record(10 + SHOT_WINDOW_TICKS, &[]);
        assert_eq!(window.len(), 2);
        window.record(11 + SHOT_WINDOW_TICKS, &[]);
        assert_eq!(window.len(), 0);
        // Order is oldest first.
        window.record(100, &[(p(1), p(2))]);
        window.record(101, &[(p(3), p(4))]);
        let json = window.json_array();
        assert!(
            json.starts_with("[[100,") && json.contains("],[101,"),
            "{json}"
        );
    }

    #[test]
    fn the_snapshot_drops_a_shot_once_it_is_older_than_the_window() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        let fired = sim.tick();
        assert!(!parse_shots(&snapshot_json_with(&sim, "[]", &window)).is_empty());
        // The firefight ends (no further attacks fed in); the window runs out.
        window.record(fired + SHOT_WINDOW_TICKS - 1, &[]);
        assert!(!window.is_empty());
        window.record(fired + SHOT_WINDOW_TICKS, &[]);
        assert!(parse_shots(&snapshot_json_with(&sim, "[]", &window)).is_empty());
    }

    #[test]
    fn survival_snapshot_has_no_shots_key_even_with_a_full_window() {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let sim = Scenario::Survival.build(2026);
        let mut window = ShotWindow::new();
        let p = Vec2::new(Fixed::from_int(1), Fixed::from_int(1));
        window.record(sim.tick(), &[(p, p)]);
        let with_window = snapshot_json_with(&sim, "[]", &window);
        assert!(!with_window.contains("\"shots\""));
        assert_eq!(
            with_window,
            snapshot_json_with(&sim, "[]", &ShotWindow::new())
        );
        assert!(with_window.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn clearing_the_window_on_restart_drops_every_shot() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        assert!(!window.is_empty());
        window.clear();
        assert!(window.is_empty());
        let json = snapshot_json_with(&sim, "[]", &window);
        assert!(json.ends_with("\"shots\":[]}"));
    }

    #[test]
    fn kestrel_snapshot_with_shots_is_valid_json_shape() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        let json = snapshot_json_with(&sim, "[]", &window);
        assert_eq!(json.matches('{').count(), json.matches('}').count());
        assert_eq!(json.matches('[').count(), json.matches(']').count());
        assert!(!json.contains(",]") && !json.contains(",}"));
        assert!(json.contains("\"shots\":[["));
    }

    #[test]
    fn kestrel_wave_route_starts_at_the_holdfast_and_reaches_home() {
        use rts_core::game::kestrel::{HOLDFAST, HOME_CC};
        let json = snapshot_json(&Scenario::KestrelReach.build(2026));
        let start = json.find("\"wave_route\":[").expect("wave_route") + "\"wave_route\":".len();
        let end = json[start..].find("]]").expect("route end") + start + 2;
        let route = &json[start..end];
        assert!(route.len() > 2, "route must be non-empty");
        let first = format!("[[{},{}]", HOLDFAST.0, HOLDFAST.1);
        assert!(
            route.starts_with(&first),
            "route starts at holdfast: {route}"
        );
        let last = format!("[{},{}]]", HOME_CC.0, HOME_CC.1);
        assert!(route.ends_with(&last), "route ends at home CC: {route}");
    }

    #[test]
    fn idle_is_false_for_a_moving_unit_and_true_for_a_stationary_one() {
        use rts_core::fixed::Fixed;
        use rts_core::game::sim::PlayerId;
        use rts_core::vec::Vec2;
        // Kestrel opens with four founding rifle squads; Survival opens mid-survey.
        let mut sim = Scenario::KestrelReach.build(2026);
        let id = human_infantry(&sim);
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, id.0).contains("\"idle\":true"));
        let pos = sim
            .views()
            .into_iter()
            .find(|v| v.id == id)
            .expect("unit")
            .pos;
        sim.step(&[Command::Move {
            owner: PlayerId(0),
            unit: id,
            target: pos + Vec2::new(Fixed::from_int(5), Fixed::ZERO),
        }]);
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, id.0).contains("\"idle\":false"));
        let obj = entity_object(&json, id.0);
        assert!(obj.contains("\"rank\":0"));
        // Buildings are never idle units.
        let cc = sim
            .views()
            .into_iter()
            .find(|v| {
                v.owner.0 == 0
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Building(BuildingKind::CommandCenter)
                    )
            })
            .map(|v| v.id);
        if let Some(cc) = cc {
            assert!(entity_object(&json, cc.0).contains("\"idle\":false"));
        }
    }

    #[test]
    fn river_kw_is_twelve_for_a_riverside_plant_and_zero_elsewhere() {
        // Kestrel's river-side plant site is (18, 6); (10, 12) is dry meadow.
        let mut sim = Scenario::KestrelReach.build(2026);
        let wet = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::PowerPlant,
            18,
            6,
        );
        let dry = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::PowerPlant,
            10,
            12,
        );
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, wet.0).contains("\"river_kw\":12"));
        assert!(entity_object(&json, dry.0).contains("\"river_kw\":0"));
        let refinery = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::Refinery,
            19,
            7,
        );
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, refinery.0).contains("\"ore_bonus\":true"));
        // Non-plant entities carry no river_kw.
        assert!(!entity_object(&json, refinery.0).contains("river_kw"));
    }

    #[test]
    fn scenario_flag_parses_anywhere_without_breaking_positional_args() {
        let o = parse_args(args(&[])).unwrap();
        assert_eq!(o.scenario, Scenario::Survival);
        assert_eq!(o.frame_limit, u64::MAX);
        assert_eq!(
            o.output,
            std::path::PathBuf::from("godot3d/runtime/snapshot.json")
        );
        let o = parse_args(args(&["out.json", "5"])).unwrap();
        assert_eq!((o.output.to_str(), o.frame_limit), (Some("out.json"), 5));
        let o = parse_args(args(&["--scenario", "kestrel", "out.json", "5"])).unwrap();
        assert_eq!(o.scenario, Scenario::KestrelReach);
        assert_eq!((o.output.to_str(), o.frame_limit), (Some("out.json"), 5));
        let o = parse_args(args(&["out.json", "--scenario=survival", "7"])).unwrap();
        assert_eq!(o.scenario, Scenario::Survival);
        assert_eq!(o.frame_limit, 7);
        let o = parse_args(args(&["out.json", "9", "--scenario", "kestrel"])).unwrap();
        assert_eq!(o.scenario, Scenario::KestrelReach);
        assert_eq!(o.frame_limit, 9);
        let o = parse_args(args(&[
            "--scenario",
            "kestrel",
            "--dump-snapshot",
            "f.json",
        ]))
        .unwrap();
        assert_eq!(
            o.dump_snapshot.as_deref().and_then(|p| p.to_str()),
            Some("f.json")
        );
    }

    #[test]
    fn scenario_flag_rejects_unknown_values_and_missing_arguments() {
        let err = parse_args(args(&["--scenario", "mars"])).unwrap_err();
        assert!(err.contains("mars") && err.contains("kestrel"), "{err}");
        assert!(parse_args(args(&["--scenario"])).is_err());
        assert!(parse_args(args(&["--dump-snapshot"])).is_err());
        assert!(parse_args(args(&["--bogus"])).is_err());
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
