//! Input-abstraction layer.
//!
//! Maps raw device input (mouse + keyboard today; touch and gamepad later) into
//! platform-agnostic [`rts_core`] [`Command`]s for the human player. Keeping this
//! layer separate is what lets the same simulation accept input from any device.

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2 as SimVec;

const HUMAN: PlayerId = PlayerId(0);
/// Max squared distance (in tiles) for a left-click to grab a unit.
const SELECT_RADIUS_SQ: f32 = 2.25;

#[must_use]
fn f32_to_fixed(v: f32) -> Fixed {
    Fixed::from_bits((v * 65536.0) as i64)
}

#[must_use]
fn fixed_to_tiles(v: Fixed) -> f32 {
    v.to_bits() as f32 / 65536.0
}

/// Reads this frame's input and returns commands for the human player.
/// `selected` tracks the currently selected unit and is updated by clicks.
#[must_use]
pub fn gather_commands(sim: &Sim, selected: &mut Option<EntityId>, cell: f32) -> Vec<Command> {
    let mut cmds = Vec::new();
    let (mx, my) = mouse_position();
    let (wx, wy) = (mx / cell, my / cell);

    if is_mouse_button_pressed(MouseButton::Left) {
        *selected = nearest_friendly_unit(sim, wx, wy);
    }
    if is_mouse_button_pressed(MouseButton::Right) {
        if let Some(unit) = *selected {
            cmds.push(Command::Move {
                owner: HUMAN,
                unit,
                target: SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
            });
        }
    }

    // Touch (mobile): a tap on a friendly unit selects it; a tap on empty ground
    // moves the selected unit. Same command set as mouse/keyboard — the sim never
    // knows which device produced the input.
    for touch in touches() {
        if touch.phase != TouchPhase::Started {
            continue;
        }
        let tx = touch.position.x / cell;
        let ty = touch.position.y / cell;
        if let Some(unit) = nearest_friendly_unit(sim, tx, ty) {
            *selected = Some(unit);
        } else if let Some(unit) = *selected {
            cmds.push(Command::Move {
                owner: HUMAN,
                unit,
                target: SimVec::new(f32_to_fixed(tx), f32_to_fixed(ty)),
            });
        }
    }

    let tile = (wx as u16, wy as u16);
    if is_key_pressed(KeyCode::P) {
        cmds.push(build(BuildingKind::PowerPlant, tile));
    }
    if is_key_pressed(KeyCode::R) {
        cmds.push(build(BuildingKind::Refinery, tile));
    }
    if is_key_pressed(KeyCode::B) {
        cmds.push(build(BuildingKind::Barracks, tile));
    }
    if is_key_pressed(KeyCode::G) {
        cmds.push(build(BuildingKind::GunTurret, tile));
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
    cmds
}

#[must_use]
const fn build(kind: BuildingKind, tile: (u16, u16)) -> Command {
    Command::Build {
        owner: HUMAN,
        kind,
        x: tile.0,
        y: tile.1,
    }
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
