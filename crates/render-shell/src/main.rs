//! Thin Macroquad render/input shell over the deterministic [`rts_core`] sim.
//!
//! It owns nothing authoritative: every frame it feeds the human's input commands
//! plus the AI's commands into [`Sim::step`] on a fixed 30 Hz timestep, then draws
//! the resulting state. The exact same shell compiles to desktop, the browser
//! (wasm32), and mobile (via miniquad). All game logic lives in `rts_core`.
#![allow(
    clippy::wildcard_imports,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_possible_wrap,
    clippy::while_float,
    clippy::suboptimal_flops,
    reason = "the render/input shell converts fixed-point sim values and grid sizes to/from f32 screen space and runs a float accumulator game loop; the determinism-critical math stays in rts_core"
)]

mod input;
mod sprites;
mod ui;

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::scenario::lane_defense;
use rts_core::game::sim::{EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use sprites::Sprites;

/// Fixed simulation timestep (30 Hz), decoupled from the render frame rate.
const TICK_DT: f32 = 1.0 / 30.0;
const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);
/// The battlefield is drawn below the top bar.
const WORLD_TOP: f32 = ui::TOP_BAR_H;

fn window_conf() -> Conf {
    Conf {
        window_title: "Military RTS".to_owned(),
        window_width: 1024,
        window_height: 768,
        high_dpi: true,
        ..Conf::default()
    }
}

fn new_match() -> Sim {
    lane_defense(2026)
}

/// Pixels per tile, sized to fit the window between the top and command bars.
fn cell_size(sim: &Sim) -> f32 {
    let w = f32::from(sim.map().width());
    let h = f32::from(sim.map().height());
    (screen_width() / w).min((screen_height() - ui::TOP_BAR_H - ui::CMD_BAR_H) / h)
}

fn tile_to_px(v: Fixed, cell: f32) -> f32 {
    v.to_bits() as f32 / 65536.0 * cell
}

#[macroquad::main(window_conf)]
async fn main() {
    let sprites = Sprites::load().await;
    let mut sim = new_match();
    let mut selected: Option<EntityId> = None;
    let mut build_mode: Option<BuildingKind> = None;
    let mut pending = Vec::new();
    let mut accumulator = 0.0_f32;
    let mut paused = false;

    loop {
        let cell = cell_size(&sim);
        let over = sim.winner().is_some();

        // Input: UI command bar first, then map (suppressed while over the UI).
        pending.extend(ui::handle_click(&sim, &mut build_mode));
        pending.extend(input::gather_commands(
            &sim,
            &mut selected,
            &mut build_mode,
            ui::pointer_over_ui(),
            cell,
        ));
        if is_key_pressed(KeyCode::Space) {
            paused = !paused;
        }
        if over && is_key_pressed(KeyCode::R) {
            sim = new_match();
            selected = None;
            build_mode = None;
            pending.clear();
            accumulator = 0.0;
        }

        // Advance the fixed-timestep sim unless paused or the match is over.
        accumulator += get_frame_time();
        if paused || over {
            accumulator = 0.0;
            pending.clear();
        }
        while accumulator >= TICK_DT {
            let mut commands = std::mem::take(&mut pending);
            commands.extend(sim.ai_commands(ENEMY));
            sim.step(&commands);
            accumulator -= TICK_DT;
        }

        draw(&sim, selected, build_mode, cell, &sprites);
        ui::draw(&sim, build_mode, paused, &sprites);
        if let Some(winner) = sim.winner() {
            draw_game_over(winner);
        }
        next_frame().await;
    }
}

fn draw_game_over(winner: PlayerId) {
    let w = screen_width();
    let h = screen_height();
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 150));
    let (msg, color) = if winner == HUMAN {
        ("VICTORY", GREEN)
    } else {
        ("DEFEAT", RED)
    };
    let size = 64.0;
    let dims = measure_text(msg, None, size as u16, 1.0);
    draw_text(msg, (w - dims.width) / 2.0, h / 2.0, size, color);
    let hint = "press R to restart";
    let hd = measure_text(hint, None, 24, 1.0);
    draw_text(hint, (w - hd.width) / 2.0, h / 2.0 + 40.0, 24.0, WHITE);
}

fn draw(
    sim: &Sim,
    selected: Option<EntityId>,
    build_mode: Option<BuildingKind>,
    cell: f32,
    sprites: &Sprites,
) {
    clear_background(Color::from_rgba(18, 22, 18, 255));
    draw_terrain(sim, cell);
    for v in sim.views() {
        let x = tile_to_px(v.pos.x, cell);
        let y = WORLD_TOP + tile_to_px(v.pos.y, cell);
        let tint = if v.owner == HUMAN { SKYBLUE } else { RED };
        let (texture, size) = match v.kind {
            EntityKindView::Building(b) => (
                sprites.building(b),
                if matches!(b, BuildingKind::CommandCenter) {
                    cell * 1.9
                } else {
                    cell * 1.45
                },
            ),
            EntityKindView::Unit(u) => (
                sprites.unit(u),
                if matches!(u, UnitKind::Tank) {
                    cell * 1.2
                } else {
                    cell * 1.0
                },
            ),
        };
        if let Some(texture) = texture {
            draw_texture_ex(
                texture,
                x - size / 2.0,
                y - size / 2.0,
                tint,
                DrawTextureParams {
                    dest_size: Some(vec2(size, size)),
                    ..DrawTextureParams::default()
                },
            );
        } else if matches!(v.kind, EntityKindView::Unit(_)) {
            draw_circle(x, y, size * 0.4, tint);
        } else {
            draw_rectangle(x - size / 2.0, y - size / 2.0, size, size, tint);
        }
        draw_health_bar(x, y, cell, v.hp, v.max_hp);
        if Some(v.id) == selected {
            draw_circle_lines(x, y, cell * 0.7, 2.0, YELLOW);
        }
    }
    draw_tracers(sim, cell);
    if let Some(kind) = build_mode {
        draw_build_ghost(sim, kind, cell);
    }
}

/// Draws shot tracers for the most recent combat tick (combat juice).
fn draw_tracers(sim: &Sim, cell: f32) {
    let color = Color::from_rgba(255, 240, 150, 200);
    for &(from, to) in sim.recent_attacks() {
        draw_line(
            tile_to_px(from.x, cell),
            WORLD_TOP + tile_to_px(from.y, cell),
            tile_to_px(to.x, cell),
            WORLD_TOP + tile_to_px(to.y, cell),
            1.5,
            color,
        );
    }
}

/// Draws a translucent placement ghost at the moused tile: green if the tile is
/// buildable and affordable, red otherwise.
fn draw_build_ghost(sim: &Sim, kind: BuildingKind, cell: f32) {
    let (mx, my) = mouse_position();
    let tx = (mx / cell) as i32;
    let ty = ((my - WORLD_TOP) / cell) as i32;
    let buildable = sim.map().tile(tx, ty).is_some_and(|t| t.buildable);
    let affordable = sim.credits(HUMAN) >= sim.building_cost(kind);
    let color = if buildable && affordable {
        Color::from_rgba(80, 200, 120, 130)
    } else {
        Color::from_rgba(200, 80, 80, 130)
    };
    draw_rectangle(
        tx as f32 * cell,
        WORLD_TOP + ty as f32 * cell,
        cell,
        cell,
        color,
    );
}

/// Draws impassable terrain (the wall band) so the lanes read clearly.
fn draw_terrain(sim: &Sim, cell: f32) {
    let map = sim.map();
    let wall = Color::from_rgba(60, 60, 66, 255);
    for ty in 0..map.height() {
        for tx in 0..map.width() {
            if !map.tile(i32::from(tx), i32::from(ty)).unwrap().passable {
                draw_rectangle(
                    f32::from(tx) * cell,
                    WORLD_TOP + f32::from(ty) * cell,
                    cell,
                    cell,
                    wall,
                );
            }
        }
    }
}

fn draw_health_bar(x: f32, y: f32, cell: f32, hp: Fixed, max_hp: Fixed) {
    let frac = (hp.to_bits() as f32 / max_hp.to_bits() as f32).clamp(0.0, 1.0);
    let width = cell * 1.2;
    let left = x - width / 2.0;
    let top = y - cell;
    draw_rectangle(left, top, width, 3.0, DARKGRAY);
    draw_rectangle(left, top, width * frac, 3.0, GREEN);
}
