//! Input-abstraction layer.
//!
//! Maps raw device input (mouse + keyboard + touch; gamepad later) into
//! platform-agnostic [`rts_core`] [`Command`]s for the human player. Keeping this
//! layer separate is what lets the same simulation accept input from any device.

use crate::Selection;
use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::hex;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2 as SimVec;

const HUMAN: PlayerId = PlayerId(0);
/// Max squared distance (in tiles) for a left-click to grab a unit.
const SELECT_RADIUS_SQ: f32 = 2.25;
/// Below this screen-space drag distance (px) a left release counts as a click,
/// not a box-select.
const CLICK_SLOP_PX: f32 = 6.0;
/// Spacing between destinations in a multi-unit formation, in world tiles.
const FORMATION_SPACING: f32 = 1.35;

#[must_use]
fn f32_to_fixed(v: f32) -> Fixed {
    Fixed::from_bits((v * 65536.0) as i64)
}

#[must_use]
fn fixed_to_tiles(v: Fixed) -> f32 {
    v.to_bits() as f32 / 65536.0
}

/// Reads this frame's input and returns commands for the human player.
///
/// `selected` is the live group selection (units + an optional planet);
/// `drag_start` holds the screen-space anchor of an in-progress box-select (set on
/// left-press, consumed on release); `build_mode` tracks a pending building
/// placement (the shell draws a ghost for it until a click places or cancels it);
/// `attack_move_armed` tracks attack-move mode — pressing `A` arms it, and the
/// next left- or right-click issues [`Command::AttackMove`] for the whole group
/// instead of a plain move, then disarms (`StarCraft` convention).
///
/// Selection: a left *click* on a friendly unit selects just it; on open planet
/// ground selects the planet; on nothing clears. A left *drag* box-selects every
/// friendly unit inside the rectangle. A right click moves the selected group, or
/// assaults an enemy/neutral planet under the cursor.
#[must_use]
#[allow(
    clippy::too_many_arguments,
    reason = "the per-frame input state (selection, drag, build_mode, attack_move, camera) is threaded explicitly rather than bundled into a struct, matching the shell's existing style"
)]
pub fn gather_commands(
    sim: &Sim,
    selected: &mut Selection,
    drag_start: &mut Option<(f32, f32)>,
    build_mode: &mut Option<BuildingKind>,
    attack_move_armed: &mut bool,
    pointer_over_ui: bool,
    cell: f32,
    origin: (f32, f32),
) -> Vec<Command> {
    let mut cmds = Vec::new();
    let (ox, wtop) = origin;
    let (mx, my) = mouse_position();
    // `ox`/`wtop` come from the shared camera transform (zoom + pan), so this
    // screen→world conversion is identical to what `draw` used this frame.
    let (wx, wy) = ((mx - ox) / cell, (my - wtop) / cell);
    let shift = is_key_down(KeyCode::LeftShift) || is_key_down(KeyCode::RightShift);

    // Drop dead/recycled ids so stale selections never command a reused slot.
    if !selected.units.is_empty() {
        let views = sim.views();
        selected
            .units
            .retain(|&id| sim.entity_alive(id) && views.iter().any(|v| v.id == id));
    }

    // Build hotkeys arm a placement; the shell shows a ghost until you click.
    if is_key_pressed(KeyCode::P) {
        *build_mode = Some(BuildingKind::PowerPlant);
    }
    if is_key_pressed(KeyCode::R) {
        *build_mode = Some(BuildingKind::Refinery);
    }
    if is_key_pressed(KeyCode::B) {
        *build_mode = Some(BuildingKind::Barracks);
    }
    if is_key_pressed(KeyCode::G) {
        *build_mode = Some(BuildingKind::GunTurret);
    }
    // J arms Flak (AaTurret) placement. (`A` was reassigned to attack-move.)
    if is_key_pressed(KeyCode::J) {
        *build_mode = Some(BuildingKind::AaTurret);
    }
    if is_key_pressed(KeyCode::L) {
        *build_mode = Some(BuildingKind::ResearchLab);
    }
    if is_key_pressed(KeyCode::N) {
        *build_mode = Some(if sim.is_earthfront() {
            BuildingKind::SupplyDepot
        } else {
            BuildingKind::AntimatterPlant
        });
    }
    if sim.is_earthfront() {
        for (key, kind) in [
            (KeyCode::F, BuildingKind::VehicleFactory),
            (KeyCode::O, BuildingKind::Airfield),
            (KeyCode::I, BuildingKind::Battery),
        ] {
            if is_key_pressed(key) {
                *build_mode = Some(kind);
            }
        }
    }
    if is_key_pressed(KeyCode::W) {
        *build_mode = Some(BuildingKind::Wall);
    }
    // A arms ATTACK-MOVE (StarCraft convention): the next left/right click issues
    // an AttackMove for the whole group. Arming a build placement cancels it, and
    // vice versa, so the two modes never fight.
    if is_key_pressed(KeyCode::A) {
        *attack_move_armed = true;
        *build_mode = None;
    }
    if build_mode.is_some() {
        *attack_move_armed = false;
    }
    if is_key_pressed(KeyCode::Escape) {
        *build_mode = None;
        *attack_move_armed = false;
    }

    // F2 selects the whole living army, matching the quick army-selection
    // convention of classic base-building RTS games.
    if is_key_pressed(KeyCode::F2) {
        selected.units = sim
            .views()
            .into_iter()
            .filter(|v| {
                v.owner == HUMAN
                    && matches!(v.kind, EntityKindView::Unit(k) if k != UnitKind::Harvester)
            })
            .map(|v| v.id)
            .collect();
        selected.planet = None;
    }

    // Stop immediately cancels movement and attack-move stances. A Move to the
    // unit's current deterministic position uses the core's normal validated
    // command path and clears the old order on the next simulation tick.
    if is_key_pressed(KeyCode::S) && !selected.units.is_empty() {
        let views = sim.views();
        for &unit in &selected.units {
            if let Some(v) = views.iter().find(|v| v.id == unit && v.owner == HUMAN) {
                cmds.push(Command::Move {
                    owner: HUMAN,
                    unit,
                    target: v.pos,
                });
            }
        }
    }

    // Left press: arm a box-select (the anchor) unless a build is being placed —
    // placement happens on press to match the existing feel.
    // Selection resolves on PRESS for immediate feedback (and so it works even
    // where button-release edges are unreliable): place a building, else select
    // the friendly unit > planet > clear under the cursor. A subsequent drag
    // upgrades to a box-select when the button is released.
    // Attack-move armed: a left-click on the map issues AttackMove to the whole
    // group (instead of selecting), then disarms. Handled before the normal
    // press logic so it takes precedence; does not start a box-select.
    if *attack_move_armed
        && is_mouse_button_pressed(MouseButton::Left)
        && !pointer_over_ui
        && !selected.units.is_empty()
    {
        let target = SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy));
        cmds.extend(group_orders(sim, &selected.units, target, true));
        *attack_move_armed = false;
        return cmds;
    }
    if is_mouse_button_pressed(MouseButton::Left) && !pointer_over_ui {
        *drag_start = Some((mx, my));
        if let Some(kind) = build_mode.take() {
            let (col, row) = hex::from_world(
                SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
                sim.map().width(),
                sim.map().height(),
            );
            cmds.push(Command::Build {
                owner: HUMAN,
                kind,
                x: col,
                y: row,
            });
        } else if let Some(unit) = nearest_friendly_entity(sim, wx, wy) {
            if shift {
                if let Some(i) = selected.units.iter().position(|&id| id == unit) {
                    selected.units.remove(i);
                } else {
                    selected.units.push(unit);
                }
            } else {
                selected.units = vec![unit];
            }
            selected.planet = None;
        } else if let Some(pid) = planet_at_world(sim, wx, wy) {
            selected.planet = Some(pid);
            selected.units.clear();
        } else if !shift {
            selected.units.clear();
            selected.planet = None;
        }
    }
    // On release, if the press became a drag, select every friendly unit in the box.
    if is_mouse_button_released(MouseButton::Left) && !pointer_over_ui {
        if let Some((sxp, syp)) = drag_start.take() {
            if (mx - sxp).hypot(my - syp) >= CLICK_SLOP_PX {
                let (w0x, w0y) = ((sxp - ox) / cell, (syp - wtop) / cell);
                let (lo_x, hi_x) = (w0x.min(wx), w0x.max(wx));
                let (lo_y, hi_y) = (w0y.min(wy), w0y.max(wy));
                let boxed: Vec<_> = sim
                    .views()
                    .into_iter()
                    .filter(|v| v.owner == HUMAN && matches!(v.kind, EntityKindView::Unit(_)))
                    .filter(|v| {
                        let (ux, uy) = (fixed_to_tiles(v.pos.x), fixed_to_tiles(v.pos.y));
                        ux >= lo_x && ux <= hi_x && uy >= lo_y && uy <= hi_y
                    })
                    .map(|v| v.id)
                    .collect();
                if shift {
                    for id in boxed {
                        if !selected.units.contains(&id) {
                            selected.units.push(id);
                        }
                    }
                } else {
                    selected.units = boxed;
                }
                selected.planet = None;
            }
        }
    }
    if is_mouse_button_pressed(MouseButton::Right) && !pointer_over_ui {
        *build_mode = None; // right-click cancels a pending placement
                            // A right-click while attack-move is armed also issues the attack-move
                            // (and disarms), matching the left-click path.
        let attack_move = *attack_move_armed;
        *attack_move_armed = false;
        if !selected.units.is_empty() {
            let selected_producer = (selected.units.len() == 1)
                .then(|| selected.units[0])
                .filter(|&id| {
                    sim.views().into_iter().any(|view| {
                        view.id == id
                            && view.owner == HUMAN
                            && matches!(
                                view.kind,
                                EntityKindView::Building(
                                    BuildingKind::Barracks
                                        | BuildingKind::Refinery
                                        | BuildingKind::VehicleFactory
                                        | BuildingKind::Airfield
                                )
                            )
                    })
                });
            if let Some(producer) = selected_producer {
                cmds.push(Command::SetRally {
                    owner: HUMAN,
                    producer,
                    target: SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
                });
            } else {
                // Contextual classic-RTS order: right-clicking an enemy attacks it;
                // right-clicking hostile territory assaults its seat; empty ground is
                // a move. A explicitly forces attack-move even on empty ground.
                let assault = planet_at_world(sim, wx, wy)
                    .and_then(|pid| (sim.planet_owner(pid) != Some(HUMAN)).then_some(pid));
                let cursor = SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy));
                let enemy = nearest_enemy_position(sim, wx, wy);
                let target = enemy.or_else(|| {
                    assault.map(|pid| {
                        seat_pos(sim, pid)
                            .or_else(|| sim.planet_center(pid))
                            .unwrap_or(cursor)
                    })
                });
                let hostile = target.is_some();
                cmds.extend(group_orders(
                    sim,
                    &selected.units,
                    target.unwrap_or(cursor),
                    attack_move || hostile,
                ));
            }
        }
    }
    // U repairs selected structures in paid 20% chunks. Delete sells selected
    // non-HQ structures for a 50% refund; both are validated by the core.
    if is_key_pressed(KeyCode::U) {
        for &building in &selected.units {
            cmds.push(Command::Repair {
                owner: HUMAN,
                building,
            });
        }
    }
    if is_key_pressed(KeyCode::Delete) {
        for &building in &selected.units {
            cmds.push(Command::Sell {
                owner: HUMAN,
                building,
            });
        }
        selected.units.clear();
    }
    if is_key_pressed(KeyCode::T) {
        if let Some(barracks) = first_friendly_producer(sim, UnitKind::Infantry) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Infantry,
            });
        }
    }
    if is_key_pressed(KeyCode::V) {
        if let Some(barracks) = first_friendly_producer(sim, UnitKind::AntiArmor) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::AntiArmor,
            });
        }
    }
    if is_key_pressed(KeyCode::K) {
        if let Some(barracks) = first_friendly_producer(sim, UnitKind::Tank) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Tank,
            });
        }
    }
    if is_key_pressed(KeyCode::H) {
        if let Some(barracks) = first_friendly_producer(sim, UnitKind::Helicopter) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Helicopter,
            });
        }
    }
    if is_key_pressed(KeyCode::C) {
        if let Some(barracks) = first_friendly_producer(sim, UnitKind::Capital) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Capital,
            });
        }
    }
    if is_key_pressed(KeyCode::D) {
        if let Some(refinery) = first_friendly_refinery(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks: refinery,
                kind: UnitKind::Harvester,
            });
        }
    }
    // F settles the selected NEUTRAL planet: found a colony on it. The target tile
    // is the planet's center, converted world -> tile. The core re-validates
    // affordability + that the planet is unowned, so a bad press is a harmless
    // no-op. Only fires when a planet is selected and currently unclaimed.
    if is_key_pressed(KeyCode::F) {
        if let Some(pid) = selected.planet {
            if sim.planet_owner(pid).is_none() {
                if let Some(c) = sim.planet_center(pid) {
                    let (col, row) = hex::from_world(c, sim.map().width(), sim.map().height());
                    cmds.push(Command::FoundColony {
                        owner: HUMAN,
                        parent: rts_core::game::civ::ColonyId(0),
                        x: col,
                        y: row,
                    });
                }
            }
        }
    }
    // Q casts the first selected unit's ability at the cursor. The core validates
    // ownership, cooldown, and range, so a bad cast is simply a no-op.
    if is_key_pressed(KeyCode::Q) {
        if let Some(&unit) = selected.units.first() {
            cmds.push(Command::UseAbility {
                owner: HUMAN,
                unit,
                target: SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
            });
        }
    }

    // Touch (mobile): a tap on a friendly unit selects just it; a tap on empty
    // ground moves the selected group. Same command set as mouse/keyboard.
    for touch in touches() {
        if touch.phase != TouchPhase::Started {
            continue;
        }
        let tx = (touch.position.x - ox) / cell;
        let ty = (touch.position.y - wtop) / cell;
        if let Some(unit) = nearest_friendly_entity(sim, tx, ty) {
            selected.units = vec![unit];
            selected.planet = None;
        } else if !selected.units.is_empty() {
            let target = SimVec::new(f32_to_fixed(tx), f32_to_fixed(ty));
            let hostile = nearest_enemy_position(sim, tx, ty).is_some();
            cmds.extend(group_orders(sim, &selected.units, target, hostile));
        }
    }
    cmds
}

/// Which planet (if any) the world point `(wx, wy)` in tile units falls on. Maps
/// the world point to a tile, then asks the map which planet owns that tile.
#[must_use]
fn planet_at_world(sim: &Sim, wx: f32, wy: f32) -> Option<rts_core::game::planet::PlanetId> {
    let (col, row) = hex::from_world(
        SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
        sim.map().width(),
        sim.map().height(),
    );
    sim.map().planet_at(i32::from(col), i32::from(row))
}

/// The world position of a planet's seat entity (its capital), if it has a living
/// one — used as the muster point for an assault order.
#[must_use]
fn seat_pos(sim: &Sim, pid: rts_core::game::planet::PlanetId) -> Option<SimVec> {
    let seat = sim.planet_seat(pid)?;
    sim.views()
        .into_iter()
        .find(|v| v.id == seat)
        .map(|v| v.pos)
}

/// The map tile under the mouse cursor (for survey-phase founding).
#[must_use]
pub fn cursor_tile(sim: &Sim, cell: f32, origin: (f32, f32)) -> (u16, u16) {
    let (ox, wtop) = origin;
    let (mx, my) = mouse_position();
    let wx = (mx - ox) / cell;
    let wy = (my - wtop) / cell;
    hex::from_world(
        SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
        sim.map().width(),
        sim.map().height(),
    )
}

#[must_use]
fn nearest_friendly_entity(sim: &Sim, wx: f32, wy: f32) -> Option<EntityId> {
    let mut best: Option<(EntityId, f32)> = None;
    for v in sim.views() {
        if v.owner != HUMAN {
            continue;
        }
        let dx = fixed_to_tiles(v.pos.x) - wx;
        let dy = fixed_to_tiles(v.pos.y) - wy;
        let dist_sq = dx * dx + dy * dy;
        if best.is_none_or(|(_, bd)| dist_sq < bd) {
            best = Some((v.id, dist_sq));
        }
    }
    best.filter(|&(_, d)| d <= SELECT_RADIUS_SQ)
        .map(|(id, _)| id)
}

/// The clicked enemy's exact world position. Units and buildings are both valid
/// contextual attack targets; the deterministic core still chooses what each
/// attacker can actually damage.
#[must_use]
fn nearest_enemy_position(sim: &Sim, wx: f32, wy: f32) -> Option<SimVec> {
    let mut best: Option<(SimVec, f32)> = None;
    for v in sim.views() {
        if v.owner == HUMAN {
            continue;
        }
        let dx = fixed_to_tiles(v.pos.x) - wx;
        let dy = fixed_to_tiles(v.pos.y) - wy;
        let dist_sq = dx * dx + dy * dy;
        if best.is_none_or(|(_, bd)| dist_sq < bd) {
            best = Some((v.pos, dist_sq));
        }
    }
    best.filter(|&(_, d)| d <= SELECT_RADIUS_SQ)
        .map(|(pos, _)| pos)
}

/// Produces a centered square formation around an order point. Giving every unit
/// the same destination creates an unreadable blob; stable entity-order slots
/// instead preserve army shape without changing deterministic simulation rules.
#[must_use]
fn group_orders(sim: &Sim, units: &[EntityId], center: SimVec, attack: bool) -> Vec<Command> {
    let views = sim.views();
    let living: Vec<_> = units
        .iter()
        .copied()
        .filter(|&id| {
            sim.entity_alive(id)
                && views
                    .iter()
                    .any(|view| view.id == id && matches!(view.kind, EntityKindView::Unit(_)))
        })
        .collect();
    let count = living.len();
    if count == 0 {
        return Vec::new();
    }
    let cols = (count as f32).sqrt().ceil() as usize;
    let rows = count.div_ceil(cols);
    let cx = fixed_to_tiles(center.x);
    let cy = fixed_to_tiles(center.y);
    let max_x = f32::from(sim.map().width()).max(1.0) - 0.25;
    let max_y = f32::from(sim.map().height()).max(1.0) - 0.25;
    living
        .into_iter()
        .enumerate()
        .map(|(i, unit)| {
            let col = i % cols;
            let row = i / cols;
            let x = (cx + (col as f32 - (cols - 1) as f32 / 2.0) * FORMATION_SPACING)
                .clamp(0.25, max_x);
            let y = (cy + (row as f32 - (rows - 1) as f32 / 2.0) * FORMATION_SPACING)
                .clamp(0.25, max_y);
            let target = SimVec::new(f32_to_fixed(x), f32_to_fixed(y));
            if attack {
                Command::AttackMove {
                    owner: HUMAN,
                    unit,
                    target,
                }
            } else {
                Command::Move {
                    owner: HUMAN,
                    unit,
                    target,
                }
            }
        })
        .collect()
}

#[must_use]
fn first_friendly_producer(sim: &Sim, unit: UnitKind) -> Option<EntityId> {
    let kind = if sim.is_earthfront() {
        Sim::earthfront_producer(unit)
    } else {
        BuildingKind::Barracks
    };
    sim.views()
        .into_iter()
        .find(|v| v.owner == HUMAN && v.kind == EntityKindView::Building(kind))
        .map(|v| v.id)
}

#[must_use]
fn first_friendly_refinery(sim: &Sim) -> Option<EntityId> {
    sim.views()
        .into_iter()
        .find(|v| {
            v.owner == HUMAN && matches!(v.kind, EntityKindView::Building(BuildingKind::Refinery))
        })
        .map(|v| v.id)
}

#[cfg(test)]
mod tests {
    use super::{
        fixed_to_tiles, group_orders, nearest_enemy_position, nearest_friendly_entity, HUMAN,
    };
    use rts_core::fixed::Fixed;
    use rts_core::game::map::Map;
    use rts_core::game::sim::{Command, PlayerId, Sim};
    use rts_core::game::stats::{BuildingKind, UnitKind};
    use rts_core::vec::Vec2;

    fn point(x: i32, y: i32) -> Vec2 {
        Vec2::new(Fixed::from_int(x), Fixed::from_int(y))
    }

    #[test]
    fn group_orders_assign_distinct_formation_slots() {
        let mut sim = Sim::new(Map::new(20, 20), 7, Fixed::from_int(500));
        let units: Vec<_> = (0..4)
            .map(|x| sim.add_unit(HUMAN, UnitKind::Infantry, point(x, 1)))
            .collect();
        let orders = group_orders(&sim, &units, point(10, 10), false);
        assert_eq!(orders.len(), units.len());
        let targets: Vec<_> = orders
            .into_iter()
            .map(|order| match order {
                Command::Move { target, .. } => target,
                _ => panic!("formation move emitted the wrong command kind"),
            })
            .collect();
        for i in 0..targets.len() {
            for j in i + 1..targets.len() {
                assert_ne!(
                    targets[i], targets[j],
                    "units were assigned one blob target"
                );
            }
        }
    }

    #[test]
    fn buildings_are_selectable_but_excluded_from_army_orders() {
        let mut sim = Sim::new(Map::new(20, 20), 7, Fixed::from_int(500));
        let barracks = sim.add_building(HUMAN, BuildingKind::Barracks, 4, 4);
        assert_eq!(nearest_friendly_entity(&sim, 4.0, 4.0), Some(barracks));
        assert!(group_orders(&sim, &[barracks], point(10, 10), false).is_empty());
    }

    #[test]
    fn contextual_targeting_finds_visible_enemy_units_and_buildings() {
        let mut sim = Sim::new(Map::new(20, 20), 7, Fixed::from_int(500));
        sim.add_unit(HUMAN, UnitKind::Infantry, point(2, 2));
        let enemy = point(8, 9);
        sim.add_unit(PlayerId(1), UnitKind::Tank, enemy);
        assert_eq!(nearest_enemy_position(&sim, 8.0, 9.0), Some(enemy));
        let turret = sim.add_building(PlayerId(1), BuildingKind::GunTurret, 14, 14);
        let turret_pos = sim
            .views()
            .into_iter()
            .find(|v| v.id == turret)
            .expect("new turret must be visible")
            .pos;
        assert_eq!(
            nearest_enemy_position(
                &sim,
                fixed_to_tiles(turret_pos.x),
                fixed_to_tiles(turret_pos.y)
            ),
            Some(turret_pos)
        );
        assert_eq!(nearest_enemy_position(&sim, 1.0, 1.0), None);
    }
}
