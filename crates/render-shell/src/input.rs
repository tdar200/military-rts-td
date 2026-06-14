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
/// placement (the shell draws a ghost for it until a click places or cancels it).
///
/// Selection: a left *click* on a friendly unit selects just it; on open planet
/// ground selects the planet; on nothing clears. A left *drag* box-selects every
/// friendly unit inside the rectangle. A right click moves the selected group, or
/// assaults an enemy/neutral planet under the cursor.
#[must_use]
pub fn gather_commands(
    sim: &Sim,
    selected: &mut Selection,
    drag_start: &mut Option<(f32, f32)>,
    build_mode: &mut Option<BuildingKind>,
    pointer_over_ui: bool,
    cell: f32,
) -> Vec<Command> {
    let mut cmds = Vec::new();
    let (mx, my) = mouse_position();
    // The board is centered horizontally; back out that offset to reach world x.
    let ox = crate::board_origin_x(sim, cell);
    let (wx, wy) = ((mx - ox) / cell, (my - crate::ui::TOP_BAR_H) / cell);

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
    if is_key_pressed(KeyCode::A) {
        *build_mode = Some(BuildingKind::AaTurret);
    }
    if is_key_pressed(KeyCode::L) {
        *build_mode = Some(BuildingKind::ResearchLab);
    }
    if is_key_pressed(KeyCode::N) {
        *build_mode = Some(BuildingKind::AntimatterPlant);
    }
    if is_key_pressed(KeyCode::Escape) {
        *build_mode = None;
    }

    // Left press: arm a box-select (the anchor) unless a build is being placed —
    // placement happens on press to match the existing feel.
    // Selection resolves on PRESS for immediate feedback (and so it works even
    // where button-release edges are unreliable): place a building, else select
    // the friendly unit > planet > clear under the cursor. A subsequent drag
    // upgrades to a box-select when the button is released.
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
        } else if let Some(unit) = nearest_friendly_unit(sim, wx, wy) {
            selected.units = vec![unit];
            selected.planet = None;
        } else if let Some(pid) = planet_at_world(sim, wx, wy) {
            selected.planet = Some(pid);
            selected.units.clear();
        } else {
            selected.units.clear();
            selected.planet = None;
        }
    }
    // On release, if the press became a drag, select every friendly unit in the box.
    if is_mouse_button_released(MouseButton::Left) && !pointer_over_ui {
        if let Some((sxp, syp)) = drag_start.take() {
            if (mx - sxp).hypot(my - syp) >= CLICK_SLOP_PX {
                let (w0x, w0y) = ((sxp - ox) / cell, (syp - crate::ui::TOP_BAR_H) / cell);
                let (lo_x, hi_x) = (w0x.min(wx), w0x.max(wx));
                let (lo_y, hi_y) = (w0y.min(wy), w0y.max(wy));
                selected.units = sim
                    .views()
                    .into_iter()
                    .filter(|v| v.owner == HUMAN && matches!(v.kind, EntityKindView::Unit(_)))
                    .filter(|v| {
                        let (ux, uy) = (fixed_to_tiles(v.pos.x), fixed_to_tiles(v.pos.y));
                        ux >= lo_x && ux <= hi_x && uy >= lo_y && uy <= hi_y
                    })
                    .map(|v| v.id)
                    .collect();
                selected.planet = None;
            }
        }
    }
    if is_mouse_button_pressed(MouseButton::Right) && !pointer_over_ui {
        *build_mode = None; // right-click cancels a pending placement
        if !selected.units.is_empty() {
            // Assault: a right-click on an enemy/neutral planet orders the whole
            // group to that planet's seat (else its center). Otherwise it's a plain
            // group move to the cursor.
            let assault = planet_at_world(sim, wx, wy)
                .and_then(|pid| (sim.planet_owner(pid) != Some(HUMAN)).then_some(pid));
            let cursor = SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy));
            let target = assault.map_or(cursor, |pid| {
                seat_pos(sim, pid)
                    .or_else(|| sim.planet_center(pid))
                    .unwrap_or(cursor)
            });
            for &unit in &selected.units {
                if sim.entity_alive(unit) {
                    cmds.push(Command::Move {
                        owner: HUMAN,
                        unit,
                        target,
                    });
                }
            }
        }
    }
    if is_key_pressed(KeyCode::T) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Infantry,
            });
        }
    }
    if is_key_pressed(KeyCode::V) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::AntiArmor,
            });
        }
    }
    if is_key_pressed(KeyCode::K) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Tank,
            });
        }
    }
    if is_key_pressed(KeyCode::H) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Helicopter,
            });
        }
    }
    if is_key_pressed(KeyCode::C) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Capital,
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
        let ty = (touch.position.y - crate::ui::TOP_BAR_H) / cell;
        if let Some(unit) = nearest_friendly_unit(sim, tx, ty) {
            selected.units = vec![unit];
            selected.planet = None;
        } else if !selected.units.is_empty() {
            let target = SimVec::new(f32_to_fixed(tx), f32_to_fixed(ty));
            for &unit in &selected.units {
                if sim.entity_alive(unit) {
                    cmds.push(Command::Move {
                        owner: HUMAN,
                        unit,
                        target,
                    });
                }
            }
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
pub fn cursor_tile(sim: &Sim, cell: f32) -> (u16, u16) {
    let (mx, my) = mouse_position();
    let ox = crate::board_origin_x(sim, cell);
    let wx = (mx - ox) / cell;
    let wy = (my - crate::ui::TOP_BAR_H) / cell;
    hex::from_world(
        SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
        sim.map().width(),
        sim.map().height(),
    )
}

#[must_use]
fn nearest_friendly_unit(sim: &Sim, wx: f32, wy: f32) -> Option<EntityId> {
    let mut best: Option<(EntityId, f32)> = None;
    for v in sim.views() {
        if v.owner != HUMAN || !matches!(v.kind, EntityKindView::Unit(_)) {
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

#[must_use]
fn first_friendly_barracks(sim: &Sim) -> Option<EntityId> {
    sim.views()
        .into_iter()
        .find(|v| {
            v.owner == HUMAN && matches!(v.kind, EntityKindView::Building(BuildingKind::Barracks))
        })
        .map(|v| v.id)
}
