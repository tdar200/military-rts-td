//! Input-abstraction layer.
//!
//! Maps raw device input (mouse + keyboard + touch; gamepad later) into
//! platform-agnostic [`rts_core`] [`Command`]s for the human player. Keeping this
//! layer separate is what lets the same simulation accept input from any device.

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::hex;
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
/// `selected` tracks the selected unit; `build_mode` tracks a pending building
/// placement (the shell draws a ghost for it until a click places or cancels it).
#[must_use]
pub fn gather_commands(
    sim: &Sim,
    selected: &mut Option<EntityId>,
    build_mode: &mut Option<BuildingKind>,
    pointer_over_ui: bool,
    cell: f32,
) -> Vec<Command> {
    let mut cmds = Vec::new();
    let (mx, my) = mouse_position();
    // The board is centered horizontally; back out that offset to reach world x.
    let ox = crate::board_origin_x(sim, cell);
    let (wx, wy) = ((mx - ox) / cell, (my - crate::ui::TOP_BAR_H) / cell);

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
    if is_key_pressed(KeyCode::Escape) {
        *build_mode = None;
    }

    if is_mouse_button_pressed(MouseButton::Left) && !pointer_over_ui {
        if let Some(kind) = build_mode.take() {
            // Snap the click to the nearest hex cell.
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
        } else {
            *selected = nearest_friendly_unit(sim, wx, wy);
        }
    }
    if is_mouse_button_pressed(MouseButton::Right) && !pointer_over_ui {
        *build_mode = None; // right-click cancels a pending placement
        if let Some(unit) = *selected {
            cmds.push(Command::Move {
                owner: HUMAN,
                unit,
                target: SimVec::new(f32_to_fixed(wx), f32_to_fixed(wy)),
            });
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
    if is_key_pressed(KeyCode::H) {
        if let Some(barracks) = first_friendly_barracks(sim) {
            cmds.push(Command::Train {
                owner: HUMAN,
                barracks,
                kind: UnitKind::Helicopter,
            });
        }
    }

    // Touch (mobile): a tap on a friendly unit selects it; a tap on empty ground
    // moves the selected unit. Same command set as mouse/keyboard.
    for touch in touches() {
        if touch.phase != TouchPhase::Started {
            continue;
        }
        let tx = (touch.position.x - ox) / cell;
        let ty = (touch.position.y - crate::ui::TOP_BAR_H) / cell;
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
    cmds
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
