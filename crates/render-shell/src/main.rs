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

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::map::Map;
use rts_core::game::sim::{EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};

/// Fixed simulation timestep (30 Hz), decoupled from the render frame rate.
const TICK_DT: f32 = 1.0 / 30.0;
/// Map size in tiles (square).
const MAP_TILES: u16 = 40;
const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);
/// Pixels reserved at the bottom for the HUD.
const HUD_HEIGHT: f32 = 40.0;

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
    let mut sim = Sim::new(Map::new(MAP_TILES, MAP_TILES), 2026, Fixed::from_int(2000));
    sim.add_building(HUMAN, BuildingKind::CommandCenter, 4, 20);
    sim.add_building(HUMAN, BuildingKind::PowerPlant, 6, 20);
    sim.add_building(HUMAN, BuildingKind::Refinery, 6, 22);
    sim.add_building(HUMAN, BuildingKind::Barracks, 6, 18);
    sim.add_building(ENEMY, BuildingKind::CommandCenter, 35, 20);
    sim
}

/// Pixels per tile, sized to fit the window above the HUD.
fn cell_size() -> f32 {
    let tiles = f32::from(MAP_TILES);
    (screen_width() / tiles).min((screen_height() - HUD_HEIGHT) / tiles)
}

fn tile_to_px(v: Fixed, cell: f32) -> f32 {
    v.to_bits() as f32 / 65536.0 * cell
}

#[macroquad::main(window_conf)]
async fn main() {
    let mut sim = new_match();
    let mut selected: Option<EntityId> = None;
    let mut pending = Vec::new();
    let mut accumulator = 0.0_f32;

    loop {
        let cell = cell_size();
        pending.extend(input::gather_commands(&sim, &mut selected, cell));

        accumulator += get_frame_time();
        while accumulator >= TICK_DT {
            let mut commands = std::mem::take(&mut pending);
            commands.extend(sim.ai_commands(ENEMY));
            sim.step(&commands);
            accumulator -= TICK_DT;
        }

        draw(&sim, selected, cell);
        next_frame().await;
    }
}

fn draw(sim: &Sim, selected: Option<EntityId>, cell: f32) {
    clear_background(Color::from_rgba(18, 22, 18, 255));
    for v in sim.views() {
        let x = tile_to_px(v.pos.x, cell);
        let y = tile_to_px(v.pos.y, cell);
        let color = if v.owner == HUMAN { SKYBLUE } else { RED };
        match v.kind {
            EntityKindView::Building(b) => {
                let size = if matches!(b, BuildingKind::CommandCenter) {
                    cell * 1.6
                } else {
                    cell * 1.1
                };
                draw_rectangle(x - size / 2.0, y - size / 2.0, size, size, color);
            }
            EntityKindView::Unit(u) => {
                let radius = if matches!(u, UnitKind::Tank) {
                    cell * 0.5
                } else {
                    cell * 0.35
                };
                draw_circle(x, y, radius, color);
            }
        }
        draw_health_bar(x, y, cell, v.hp, v.max_hp);
        if Some(v.id) == selected {
            draw_circle_lines(x, y, cell * 0.7, 2.0, YELLOW);
        }
    }
    draw_hud(sim);
}

fn draw_health_bar(x: f32, y: f32, cell: f32, hp: Fixed, max_hp: Fixed) {
    let frac = (hp.to_bits() as f32 / max_hp.to_bits() as f32).clamp(0.0, 1.0);
    let width = cell * 1.2;
    let left = x - width / 2.0;
    let top = y - cell;
    draw_rectangle(left, top, width, 3.0, DARKGRAY);
    draw_rectangle(left, top, width * frac, 3.0, GREEN);
}

fn draw_hud(sim: &Sim) {
    let line = screen_height() - 22.0;
    let status = match sim.winner() {
        Some(PlayerId(0)) => "YOU WIN".to_owned(),
        Some(PlayerId(p)) => format!("PLAYER {p} WINS"),
        _ => format!(
            "credits {}   tick {}   units {}",
            sim.credits(HUMAN).to_bits() / 65536,
            sim.tick(),
            sim.unit_count(HUMAN),
        ),
    };
    draw_text(&status, 8.0, line, 24.0, WHITE);
    draw_text(
        "L-click: select unit   R-click: move   keys B/P/R/G: build   T: train infantry",
        8.0,
        screen_height() - 4.0,
        16.0,
        LIGHTGRAY,
    );
}
