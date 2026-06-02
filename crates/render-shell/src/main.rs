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
    clippy::too_many_lines,
    reason = "the render/input shell converts fixed-point sim values and grid sizes to/from f32 screen space and runs a float accumulator game loop; draw functions and main() are inherently long; the determinism-critical math stays in rts_core"
)]

mod input;
mod sprites;
mod theme;
mod ui;

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::hex;
use rts_core::game::scenario::Scenario;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::game::tech::TECHS;
use rts_core::vec::Vec2 as SimVec2;
use sprites::Sprites;
// Explicit theme imports (not a glob) so they take precedence over the
// like-named macroquad prelude color constants (e.g. GOLD).
use theme::{
    hp_color, BAD, BASE_CHARCOAL, BORDER_NEUTRAL, BRONZE, DECO_GOLD, DECO_GOLD_HI, GOLD, GOOD,
    GRID, GROUND, GROUND_MACRO, HP_TRACK, INK, INK_DIM, MAP_FOREST, MAP_GRASS, MAP_GRASS2,
    MAP_PLAINS, OLIVE, PANEL, PARCHMENT, PARCHMENT_EDGE, PARCHMENT_HI, PARCHMENT_LO, PIECE_SHADOW,
    REGAL_BG, REGAL_BG_HI, REGAL_BG_LO, SELECT_RING, TEAM_ENEMY, TEAM_PLAYER, TERRAIN_WALL, TEXT,
    TEXT_DIM, TRACER, VARNISH, WALL_EDGE, WALL_HI, WALL_TOP, WARN, WELL,
};

/// Fixed simulation timestep (30 Hz), decoupled from the render frame rate.
const TICK_DT: f32 = 1.0 / 30.0;
const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);
/// The battlefield is drawn below the top bar.
const WORLD_TOP: f32 = ui::TOP_BAR_H;

/// Top-level screen state.
#[derive(Clone, Copy, PartialEq)]
enum Phase {
    Title,
    Playing,
}

fn window_conf() -> Conf {
    Conf {
        window_title: "Stellar Front".to_owned(),
        window_width: 1024,
        window_height: 768,
        high_dpi: true,
        ..Conf::default()
    }
}

/// The match seed. Fixed for now (every match on a map plays from the same seed);
/// a future lobby supplies this for `PvP`.
const MATCH_SEED: u64 = 2026;

fn new_match(scenario: Scenario) -> Sim {
    scenario.build(MATCH_SEED)
}

/// Centered vertical list of selectable maps on the title screen, paired with the
/// clickable rectangle for each. Shared by the renderer and the hit-test so they
/// can't drift.
fn scenario_rows() -> [(Scenario, Rect); 3] {
    let c = cartouche();
    let rows_top = c.y + CART_HEAD_H;
    let mut out = [(Scenario::LaneDefense, Rect::new(0.0, 0.0, 0.0, 0.0)); 3];
    for (i, &sc) in Scenario::ALL.iter().enumerate() {
        out[i] = (
            sc,
            Rect::new(
                c.x + 12.0,
                rows_top + i as f32 * CART_ROW_H,
                c.w - 24.0,
                CART_ROW_H,
            ),
        );
    }
    out
}

/// The map the pointer is hovering on the title screen, if any.
fn scenario_at_pointer() -> Option<Scenario> {
    let (mx, my) = mouse_position();
    scenario_rows()
        .into_iter()
        .find(|(_, rect)| rect.contains(vec2(mx, my)))
        .map(|(sc, _)| sc)
}

/// A scenario chosen by number key (1/2/3) this frame, if any.
fn scenario_hotkey() -> Option<Scenario> {
    for (i, &sc) in Scenario::ALL.iter().enumerate() {
        let key = match i {
            0 => KeyCode::Key1,
            1 => KeyCode::Key2,
            _ => KeyCode::Key3,
        };
        if is_key_pressed(key) {
            return Some(sc);
        }
    }
    None
}

/// Pixels per world unit, sized so the whole hex board fits between the bars.
/// The hex layout spans `0.75·cols + ~1` world units wide and `rows + ~1.5` tall.
fn cell_size(sim: &Sim) -> f32 {
    let world_w = 0.75 * f32::from(sim.map().width()) + 1.0;
    let world_h = f32::from(sim.map().height()) + 1.5;
    (screen_width() / world_w).min((screen_height() - ui::TOP_BAR_H - ui::CMD_BAR_H) / world_h)
}

fn tile_to_px(v: Fixed, cell: f32) -> f32 {
    v.to_bits() as f32 / 65536.0 * cell
}

/// Horizontal offset that centers the hex board in the window.
fn board_origin_x(sim: &Sim, cell: f32) -> f32 {
    ((screen_width() - board_size(sim, cell).0) / 2.0).max(0.0)
}

/// World-space center of hex cell `(col, row)` in pixels, with the board centered
/// by `ox` (from [`board_origin_x`]).
fn hex_center_px(col: u16, row: u16, cell: f32, ox: f32) -> (f32, f32) {
    let c = hex::center(col, row);
    (
        ox + tile_to_px(c.x, cell),
        WORLD_TOP + tile_to_px(c.y, cell),
    )
}

/// Fills a flat-top hexagon (width = height = `cell`, so cells tile cleanly at the
/// 3/4-column / 1-row / half-row-stagger spacing) via a 6-triangle fan.
fn draw_hex(cx: f32, cy: f32, cell: f32, fill: Color) {
    let rx = cell * 0.5;
    let ry = cell * 0.5;
    let hx = rx * 0.5;
    let v = [
        vec2(cx + rx, cy),
        vec2(cx + hx, cy - ry),
        vec2(cx - hx, cy - ry),
        vec2(cx - rx, cy),
        vec2(cx - hx, cy + ry),
        vec2(cx + hx, cy + ry),
    ];
    let ctr = vec2(cx, cy);
    for i in 0..6 {
        draw_triangle(ctr, v[i], v[(i + 1) % 6], fill);
    }
}

/// Draws a flat-top hexagon outline.
fn draw_hex_outline(cx: f32, cy: f32, cell: f32, thick: f32, col: Color) {
    let rx = cell * 0.5;
    let ry = cell * 0.5;
    let hx = rx * 0.5;
    let v = [
        vec2(cx + rx, cy),
        vec2(cx + hx, cy - ry),
        vec2(cx - hx, cy - ry),
        vec2(cx - rx, cy),
        vec2(cx - hx, cy + ry),
        vec2(cx + hx, cy + ry),
    ];
    for i in 0..6 {
        let a = v[i];
        let b = v[(i + 1) % 6];
        draw_line(a.x, a.y, b.x, b.y, thick, col);
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    let sprites = Sprites::load().await;
    let mut scenario = Scenario::LaneDefense;
    let mut sim = new_match(scenario);
    let mut selected: Option<EntityId> = None;
    let mut build_mode: Option<BuildingKind> = None;
    let mut pending = Vec::new();
    let mut accumulator = 0.0_f32;
    let mut paused = false;
    let mut research_open = false;
    let mut phase = Phase::Title;

    loop {
        if phase == Phase::Title {
            // Hover highlights a map; click / number key / Enter chooses one.
            if let Some(hovered) = scenario_at_pointer() {
                scenario = hovered;
            }
            let clicked = is_mouse_button_pressed(MouseButton::Left);
            let chosen = scenario_hotkey()
                .or_else(|| clicked.then_some(scenario))
                .or_else(|| is_key_pressed(KeyCode::Enter).then_some(scenario));
            if let Some(sc) = chosen {
                scenario = sc;
                phase = Phase::Playing;
                sim = new_match(scenario);
                selected = None;
                build_mode = None;
                pending.clear();
                accumulator = 0.0;
                research_open = false;
            }
            draw_title(&sprites, scenario);
            next_frame().await;
            continue;
        }

        let cell = cell_size(&sim);
        let over = sim.winner().is_some();

        // Input: UI command bar first, then map (suppressed while over the UI or
        // the research modal).
        if !research_open {
            pending.extend(ui::handle_click(&sim, &mut build_mode));
            pending.extend(input::gather_commands(
                &sim,
                &mut selected,
                &mut build_mode,
                ui::pointer_over_ui(),
                cell,
            ));
        }
        if !research_open && is_key_pressed(KeyCode::Space) {
            paused = !paused;
        }
        // Toggle research modal with Y (only while playing, not paused, not on title/game-over).
        if !over && !paused && is_key_pressed(KeyCode::Y) {
            research_open = !research_open;
        }
        // While the research modal is open: number keys issue research commands;
        // Escape closes without researching.
        if research_open {
            let key_to_tech: [(KeyCode, u32); 10] = [
                (KeyCode::Key1, 0),
                (KeyCode::Key2, 1),
                (KeyCode::Key3, 2),
                (KeyCode::Key4, 3),
                (KeyCode::Key5, 4),
                (KeyCode::Key6, 5),
                (KeyCode::Key7, 6),
                (KeyCode::Key8, 7),
                (KeyCode::Key9, 8),
                (KeyCode::Key0, 9),
            ];
            for (key, tech_id) in key_to_tech {
                if is_key_pressed(key) {
                    // Core validates affordability, prereq, and lab presence.
                    if sim.research_state(HUMAN).1.is_none() {
                        pending.push(Command::Research {
                            owner: HUMAN,
                            tech_id,
                        });
                    }
                    research_open = false;
                    break;
                }
            }
            if is_key_pressed(KeyCode::Escape) {
                research_open = false;
            }
        }
        if over && is_key_pressed(KeyCode::R) {
            sim = new_match(scenario);
            selected = None;
            build_mode = None;
            pending.clear();
            accumulator = 0.0;
            research_open = false;
        }
        // Return to the map-select screen.
        if over && is_key_pressed(KeyCode::M) {
            phase = Phase::Title;
            selected = None;
            build_mode = None;
            pending.clear();
            accumulator = 0.0;
            research_open = false;
        }

        // Advance the fixed-timestep sim unless paused, the match is over, or the
        // research modal is open (the modal freezes time so the player can read it).
        // Clamp frame time so a stall / slow frame can't dump hundreds of ticks at
        // once (the "spiral of death") and fast-forward past wave spawns.
        accumulator += get_frame_time().min(0.1);
        if paused || over || research_open {
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
        ui::draw(&sim, build_mode, paused, selected, &sprites);
        if research_open {
            draw_research_modal(&sim, &sprites);
        }
        if let Some(winner) = sim.winner() {
            draw_game_over(winner, &sprites);
        }
        next_frame().await;
    }
}

/// Centered text in the bold font; returns nothing.
fn centered(s: &str, y: f32, size: f32, color: Color, font: Option<&Font>) {
    let w = measure_text(s, font, size as u16, 1.0).width;
    draw_text_ex(
        s,
        (screen_width() - w) / 2.0,
        y,
        TextParams {
            font,
            font_size: size as u16,
            color,
            ..Default::default()
        },
    );
}

/// Same RGB at a given alpha.
const fn with_alpha(c: Color, a: f32) -> Color {
    Color::new(c.r, c.g, c.b, a)
}

/// Centered text with a soft drop shadow (for the engraved wordmark).
fn centered_shadow(s: &str, y: f32, size: f32, color: Color, font: Option<&Font>) {
    let w = measure_text(s, font, size as u16, 1.0).width;
    let x = (screen_width() - w) / 2.0;
    let shadow = TextParams {
        font,
        font_size: size as u16,
        color: Color::from_rgba(0, 0, 0, 150),
        ..Default::default()
    };
    draw_text_ex(s, x, y + 2.0, shadow);
    draw_text_ex(
        s,
        x,
        y,
        TextParams {
            font,
            font_size: size as u16,
            color,
            ..Default::default()
        },
    );
}

/// A four-sided beveled border (lit top+left, shadowed bottom+right).
fn beveled_frame(r: Rect, th: f32, lit: Color, shade: Color) {
    draw_rectangle(r.x, r.y, r.w, th, lit);
    draw_rectangle(r.x, r.y, th, r.h, lit);
    draw_rectangle(r.x, r.y + r.h - th, r.w, th, shade);
    draw_rectangle(r.x + r.w - th, r.y, th, r.h, shade);
}

/// A small gold diamond (rotated square).
fn diamond(cx: f32, cy: f32, r: f32, col: Color) {
    draw_poly(cx, cy, 4, r, 0.0, col);
}

/// A deco rule: a tapered gold line either side of a centered diamond.
fn deco_rule(cx: f32, y: f32, half: f32) {
    draw_rectangle(cx - half, y - 1.0, half - 12.0, 2.0, DECO_GOLD);
    draw_rectangle(cx + 12.0, y - 1.0, half - 12.0, 2.0, DECO_GOLD);
    diamond(cx, y, 6.0, DECO_GOLD_HI);
}

/// Art-deco corner ornament drawn into a 23-unit box; the outer corner is at
/// `(ox, oy)` and `sx`/`sy` (±1) flip it toward the panel interior.
fn corner_ornament(ox: f32, oy: f32, sx: f32, sy: f32) {
    let p = |u: f32, v: f32| (ox + u * sx, oy + v * sy);
    let ln =
        |a: (f32, f32), b: (f32, f32), th: f32, col: Color| draw_line(a.0, a.1, b.0, b.1, th, col);
    ln(p(3.0, 23.0), p(3.0, 3.0), 2.0, DECO_GOLD);
    ln(p(3.0, 3.0), p(23.0, 3.0), 2.0, DECO_GOLD);
    ln(p(9.0, 22.0), p(9.0, 9.0), 2.0, DECO_GOLD);
    ln(p(9.0, 9.0), p(22.0, 9.0), 2.0, DECO_GOLD);
    ln(p(9.0, 9.0), p(20.0, 14.0), 1.3, DECO_GOLD_HI);
    ln(p(9.0, 9.0), p(14.0, 20.0), 1.3, DECO_GOLD_HI);
    let (dx, dy) = p(6.0, 6.0);
    diamond(dx, dy, 4.5, DECO_GOLD_HI);
}

/// Keystone crest cresting the top edge of the cartouche.
fn keystone_crest(cx: f32, base_y: f32) {
    for (dx, dy) in [
        (-26.0, -30.0),
        (-15.0, -35.0),
        (0.0, -39.0),
        (15.0, -35.0),
        (26.0, -30.0),
    ] {
        draw_line(cx, base_y, cx + dx, base_y + dy, 1.6, DECO_GOLD);
    }
    diamond(cx, base_y - 42.0, 7.0, DECO_GOLD_HI);
}

/// The parchment cartouche geometry — shared by the renderer and the click
/// hit-test so the visible rows and the clickable rows can't drift.
fn cartouche() -> Rect {
    let w = 560.0_f32.min(screen_width() - 60.0);
    let x = (screen_width() - w) / 2.0;
    let y = (screen_height() * 0.42).max(190.0);
    let h = CART_HEAD_H + 3.0 * CART_ROW_H + 14.0;
    Rect::new(x, y, w, h)
}
const CART_HEAD_H: f32 = 56.0;
const CART_ROW_H: f32 = 58.0;

fn draw_title(sprites: &Sprites, selected: Scenario) {
    let (w, h) = (screen_width(), screen_height());
    let cx = w / 2.0;
    let fc = h * 0.40; // field center y

    // --- antiquarian teal field, lit center, vignette ---
    clear_background(REGAL_BG_LO);
    draw_rectangle(0.0, 0.0, w, h, REGAL_BG);
    draw_ellipse(
        cx,
        fc,
        w * 0.46,
        h * 0.40,
        0.0,
        with_alpha(REGAL_BG_HI, 0.85),
    );
    // antique-map linework: contour rings + graticule (faint deco gold)
    let ring = Color::from_rgba(201, 164, 76, 16);
    for r in [150.0_f32, 280.0, 430.0] {
        draw_circle_lines(cx, fc, r, 1.0, ring);
    }
    let grat = Color::from_rgba(201, 164, 76, 11);
    let mut gx = cx % 132.0;
    while gx < w {
        draw_line(gx, 0.0, gx, h, 1.0, grat);
        gx += 132.0;
    }
    let mut gy = fc % 132.0;
    while gy < h {
        draw_line(0.0, gy, w, gy, 1.0, grat);
        gy += 132.0;
    }
    for (i, a) in [40u8, 70, 110, 150].into_iter().enumerate() {
        let inset = i as f32 * 26.0;
        draw_rectangle_lines(
            inset,
            inset,
            w - inset * 2.0,
            h - inset * 2.0,
            26.0,
            Color::from_rgba(6, 12, 9, a),
        );
    }

    let c = cartouche();
    // --- regal wordmark hero (Cinzel, engraved gold) ---
    centered(
        "EARTH COMMAND",
        c.y - 118.0,
        17.0,
        DECO_GOLD,
        sprites.font_regal(),
    );
    centered_shadow(
        "STELLAR FRONT",
        c.y - 80.0,
        62.0,
        DECO_GOLD_HI,
        sprites.font_regal(),
    );
    deco_rule(cx, c.y - 46.0, 180.0);

    // --- parchment cartouche ---
    draw_cartouche(c);
    centered(
        "CHOOSE YOUR FRONT",
        c.y + 28.0,
        21.0,
        INK,
        sprites.font_regal(),
    );
    centered(
        "THREE FRONTS · ONE WAR",
        c.y + 46.0,
        13.0,
        INK_DIM,
        sprites.font(),
    );
    for (sc, rect) in scenario_rows() {
        draw_scenario_row(sc, rect, sc == selected, sprites);
    }

    centered(
        "click a map, press 1–3, or ENTER",
        c.y + c.h + 34.0,
        17.0,
        DECO_GOLD,
        sprites.font(),
    );
}

/// Draws the ornate gold-framed parchment panel.
fn draw_cartouche(c: Rect) {
    let outer = Rect::new(c.x - 6.0, c.y - 6.0, c.w + 12.0, c.h + 12.0);
    beveled_frame(outer, 5.0, DECO_GOLD_HI, theme::GOLD_DK);
    draw_rectangle_lines(
        outer.x - 1.0,
        outer.y - 1.0,
        outer.w + 2.0,
        outer.h + 2.0,
        1.0,
        BRONZE,
    );
    // parchment fill, lit top + aged bottom
    draw_rectangle(c.x, c.y, c.w, c.h, PARCHMENT);
    draw_rectangle(c.x, c.y, c.w, c.h * 0.3, with_alpha(PARCHMENT_HI, 0.5));
    draw_rectangle(
        c.x,
        c.y + c.h * 0.72,
        c.w,
        c.h * 0.28,
        with_alpha(PARCHMENT_LO, 0.5),
    );
    draw_rectangle_lines(c.x, c.y, c.w, c.h, 1.0, PARCHMENT_EDGE);
    draw_rectangle_lines(c.x + 9.0, c.y + 9.0, c.w - 18.0, c.h - 18.0, 1.5, DECO_GOLD);
    corner_ornament(c.x - 6.0, c.y - 6.0, 1.0, 1.0);
    corner_ornament(c.x + c.w + 6.0, c.y - 6.0, -1.0, 1.0);
    corner_ornament(c.x - 6.0, c.y + c.h + 6.0, 1.0, -1.0);
    corner_ornament(c.x + c.w + 6.0, c.y + c.h + 6.0, -1.0, -1.0);
    keystone_crest(c.x + c.w / 2.0, c.y - 6.0);
}

/// Draws one selectable map row on the parchment (sepia-ink serif name + tagline,
/// gold wash + diamond marker when selected).
fn draw_scenario_row(scenario: Scenario, rect: Rect, selected: bool, sprites: &Sprites) {
    draw_line(
        rect.x,
        rect.y,
        rect.x + rect.w,
        rect.y,
        1.0,
        with_alpha(BRONZE, 0.3),
    );
    if selected {
        draw_rectangle(
            rect.x,
            rect.y,
            rect.w,
            rect.h,
            Color::from_rgba(201, 164, 76, 64),
        );
        draw_rectangle_lines(rect.x, rect.y, rect.w, rect.h, 1.5, DECO_GOLD);
        diamond(rect.x + 18.0, rect.y + rect.h / 2.0, 5.0, DECO_GOLD_HI);
    }
    let name_color = if selected { INK } else { with_alpha(INK, 0.82) };
    draw_text_ex(
        scenario.name(),
        rect.x + 38.0,
        rect.y + 27.0,
        TextParams {
            font: sprites.font_regal(),
            font_size: 24,
            color: name_color,
            ..Default::default()
        },
    );
    draw_text_ex(
        scenario.tagline(),
        rect.x + 38.0,
        rect.y + 47.0,
        TextParams {
            font: sprites.font(),
            font_size: 16,
            color: INK_DIM,
            ..Default::default()
        },
    );
}

fn draw_game_over(winner: PlayerId, sprites: &Sprites) {
    let (w, h) = (screen_width(), screen_height());
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 175));
    let (pw, ph) = (440.0, 184.0);
    let (px, py) = ((w - pw) / 2.0, (h - ph) / 2.0);
    draw_rectangle(px, py, pw, ph, PANEL);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);
    let (msg, color) = if winner == HUMAN {
        ("REPELLED", GOOD)
    } else {
        ("OVERRUN", BAD)
    };
    centered(msg, py + 92.0, 56.0, color, sprites.font_display());
    centered(
        "R to restart    •    M for map select",
        py + 132.0,
        22.0,
        TEXT,
        sprites.font(),
    );
}

/// Classifies the visible status of a single tech for the research modal.
#[derive(Clone, Copy)]
enum TechStatus {
    Researched,
    /// Ticks remaining and the tech's duration, for a progress %.
    InProgress {
        ticks_remaining: u32,
        duration: u32,
    },
    Locked,
    NoLab,
    Available,
}

/// Returns the display status of tech `t` given the player's current research
/// state, active research slot, and whether a research lab exists.
fn tech_status(
    tech_id: u32,
    prereq: Option<u32>,
    duration: u32,
    mask: u32,
    active: Option<(u32, u32)>,
    has_lab: bool,
) -> TechStatus {
    if mask & (1 << tech_id) != 0 {
        return TechStatus::Researched;
    }
    if let Some((active_id, ticks_remaining)) = active {
        if active_id == tech_id {
            return TechStatus::InProgress {
                ticks_remaining,
                duration,
            };
        }
    }
    if prereq.is_some_and(|p| mask & (1 << p) == 0) {
        return TechStatus::Locked;
    }
    if !has_lab {
        return TechStatus::NoLab;
    }
    TechStatus::Available
}

/// Full-screen overlay listing all 10 techs with their status + progress.
/// Number keys 1-0 start research; Escape closes.
fn draw_research_modal(sim: &Sim, sprites: &Sprites) {
    let (w, h) = (screen_width(), screen_height());
    // Dark full-screen overlay — time is frozen while this is up.
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 200));

    let pw = 560.0_f32.min(w - 40.0);
    // 10 rows + title bar + footer
    let row_h = 34.0;
    let head_h = 48.0;
    let foot_h = 36.0;
    let n = TECHS.len() as f32;
    let ph = head_h + n * row_h + foot_h + 16.0;
    let px = (w - pw) / 2.0;
    let py = (h - ph) / 2.0;

    // Panel background + gold top bar + border.
    draw_rectangle(px, py, pw, ph, PANEL);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);

    // Title.
    let fb = sprites.font_bold();
    let f = sprites.font();
    centered("RESEARCH", py + 32.0, 26.0, GOLD, sprites.font_bold());
    // Thin olive separator below the title.
    draw_rectangle(px + 12.0, py + head_h - 4.0, pw - 24.0, 1.0, OLIVE);

    let (mask, active) = sim.research_state(HUMAN);
    let has_lab = sim.has_research_lab(HUMAN);

    for (i, t) in TECHS.iter().enumerate() {
        let ry = py + head_h + i as f32 * row_h + 8.0;
        // Alternating subtle row tint for readability.
        if i % 2 == 0 {
            draw_rectangle(px + 8.0, ry - 4.0, pw - 16.0, row_h - 2.0, WELL);
        }

        // Number key chip (1-9, then 0 for the 10th).
        let key_char = if i < 9 {
            char::from_digit(u32::try_from(i + 1).unwrap_or(0), 10).unwrap_or('?')
        } else {
            '0'
        };
        let key_s = key_char.to_string();
        draw_rectangle(px + 14.0, ry - 2.0, 18.0, 18.0, PANEL);
        draw_rectangle_lines(px + 14.0, ry - 2.0, 18.0, 18.0, 1.0, BORDER_NEUTRAL);
        let kw = measure_text(&key_s, f, 14, 1.0).width;
        draw_text_ex(
            &key_s,
            px + 23.0 - kw / 2.0,
            ry + 12.0,
            TextParams {
                font: f,
                font_size: 14,
                color: TEXT_DIM,
                ..Default::default()
            },
        );

        // Tech name.
        draw_text_ex(
            t.name,
            px + 40.0,
            ry + 14.0,
            TextParams {
                font: fb,
                font_size: 16,
                color: TEXT,
                ..Default::default()
            },
        );

        // Cost.
        let cost_val = t.cost.to_bits() / 65536;
        let cost_s = format!("${cost_val}");
        let cost_w = measure_text(&cost_s, f, 14, 1.0).width;
        draw_text_ex(
            &cost_s,
            px + pw / 2.0 - cost_w / 2.0,
            ry + 14.0,
            TextParams {
                font: f,
                font_size: 14,
                color: TEXT_DIM,
                ..Default::default()
            },
        );

        // Status (right-aligned).
        let status = tech_status(t.id, t.prereq, t.duration, mask, active, has_lab);
        let (status_s, status_col) = match status {
            TechStatus::Researched => ("Researched".to_owned(), GOOD),
            TechStatus::InProgress {
                ticks_remaining,
                duration,
            } => {
                // Compute percent safely using checked_div (duration could be 0).
                let elapsed = duration.saturating_sub(ticks_remaining);
                let pct = (elapsed * 100).checked_div(duration).unwrap_or(100);
                (format!("In progress {pct}%"), WARN)
            }
            TechStatus::Locked => ("Locked".to_owned(), TEXT_DIM),
            TechStatus::NoLab => ("No lab".to_owned(), BAD),
            TechStatus::Available => ("Available".to_owned(), TEXT),
        };
        let sw = measure_text(&status_s, f, 14, 1.0).width;
        draw_text_ex(
            &status_s,
            px + pw - sw - 20.0,
            ry + 14.0,
            TextParams {
                font: f,
                font_size: 14,
                color: status_col,
                ..Default::default()
            },
        );
    }

    // Footer hint.
    let footer_y = py + head_h + n * row_h + foot_h;
    draw_rectangle(
        px + 12.0,
        py + head_h + n * row_h + 4.0,
        pw - 24.0,
        1.0,
        OLIVE,
    );
    centered(
        "1-0 research  \u{2022}  Esc close",
        footer_y,
        15.0,
        TEXT_DIM,
        f,
    );
}

fn draw(
    sim: &Sim,
    selected: Option<EntityId>,
    build_mode: Option<BuildingKind>,
    cell: f32,
    sprites: &Sprites,
) {
    clear_background(BASE_CHARCOAL);
    draw_ground(sim, cell);
    draw_terrain(sim, cell);
    let ox = board_origin_x(sim, cell);
    for v in sim.views() {
        let x = ox + tile_to_px(v.pos.x, cell);
        let y = WORLD_TOP + tile_to_px(v.pos.y, cell);
        let team = if v.owner == HUMAN {
            TEAM_PLAYER
        } else {
            TEAM_ENEMY
        };
        let (texture, size, is_building) = match v.kind {
            EntityKindView::Building(b) => (
                sprites.building(b),
                if matches!(b, BuildingKind::CommandCenter) {
                    cell * 1.9
                } else {
                    cell * 1.5
                },
                true,
            ),
            EntityKindView::Unit(u) => (
                sprites.unit(u),
                if matches!(u, UnitKind::Tank) {
                    cell * 1.25
                } else {
                    cell * 1.05
                },
                false,
            ),
        };
        draw_piece(x, y, size, texture, team, is_building);
        draw_health_bar(x, y, cell, v.hp, v.max_hp);
        if Some(v.id) == selected {
            draw_circle_lines(x, y, size * 0.62, 2.0, SELECT_RING);
        }
    }
    draw_tracers(sim, cell);
    if let Some(kind) = build_mode {
        draw_build_grid(sim, cell);
        draw_build_ghost(sim, kind, cell);
    }
}

/// Scales a color's RGB toward black by `factor` (keeps alpha).
fn darken(c: Color, factor: f32) -> Color {
    Color::new(c.r * factor, c.g * factor, c.b * factor, c.a)
}

/// A tight contact shadow under a piece, two stacked ellipses for a soft edge.
fn contact_shadow(x: f32, y: f32, base: f32) {
    let sy = y + base * 0.92;
    draw_ellipse(x, sy, base * 0.92, base * 0.26, 0.0, PIECE_SHADOW);
    draw_ellipse(
        x,
        sy,
        base * 0.6,
        base * 0.18,
        0.0,
        Color::new(0.0, 0.0, 0.0, 0.42),
    );
}

/// Draws the white silhouette icon (or a fallback shape) centered on a piece.
fn piece_icon(x: f32, y: f32, isz: f32, texture: Option<&Texture2D>, team: Color, building: bool) {
    if let Some(tex) = texture {
        draw_texture_ex(
            tex,
            x - isz / 2.0,
            y - isz / 2.0,
            WHITE,
            DrawTextureParams {
                dest_size: Some(vec2(isz, isz)),
                ..DrawTextureParams::default()
            },
        );
    } else if building {
        draw_rectangle(x - isz / 4.0, y - isz / 4.0, isz / 2.0, isz / 2.0, team);
    } else {
        draw_circle(x, y, isz / 4.0, team);
    }
}

/// Draws one unit/building as a grounded game piece. Units get a fake-lit team
/// dome (stacked discs + a specular dot); buildings get a fake-extruded team
/// foundation slab with a thin gold baseplate tying them to the HUD. Both sit on a
/// contact shadow, with the white silhouette framed by the team base so faction
/// reads instantly and the piece has volume rather than looking like flat clip-art.
fn draw_piece(x: f32, y: f32, size: f32, texture: Option<&Texture2D>, team: Color, building: bool) {
    let base = size * 0.5;
    contact_shadow(x, y, base);
    if building {
        let s = size * 0.86;
        // Extruded team slab, lit top face, gold-rimmed (a map "plinth").
        draw_rectangle(x - s / 2.0, y - s / 2.0, s, s, darken(team, 0.45));
        draw_rectangle(x - s / 2.0, y - s / 2.0, s, s * 0.5, darken(team, 0.66));
        draw_rectangle_lines(x - s / 2.0, y - s / 2.0, s, s, 2.0, DECO_GOLD);
        draw_line(
            x - s / 2.0,
            y - s / 2.0 + 1.0,
            x + s / 2.0,
            y - s / 2.0 + 1.0,
            1.0,
            DECO_GOLD_HI,
        );
        // Thin gold baseplate tying structures to the gold HUD.
        draw_rectangle(x - s / 2.0, y + s / 2.0 - 2.0, s, 2.0, GOLD);
        piece_icon(x, y, size * 0.6, texture, team, true);
    } else {
        let r = size * 0.58;
        draw_circle(x, y, r, darken(team, 0.5)); // base
        draw_circle(x, y - r * 0.14, r * 0.82, team); // top-lit bulge
        draw_circle_lines(x, y, r, 2.0, DECO_GOLD); // gold rim
        draw_circle_lines(x, y, r - 1.8, 1.0, with_alpha(DECO_GOLD_HI, 0.55)); // inner sheen
                                                                               // Specular highlight, upper-left.
        draw_circle(
            x - r * 0.36,
            y - r * 0.36,
            r * 0.18,
            Color::new(1.0, 1.0, 1.0, 0.32),
        );
        piece_icon(x, y, size * 0.6, texture, team, false);
    }
}

/// Picks a warm campaign-map terrain tone for a tile, deterministically by
/// position — mostly grassland with patches of plains and forest, so the board
/// reads as a painted Civ-style map rather than a flat checkerboard.
fn terrain_tone(tx: u16, ty: u16) -> Color {
    let n = (u32::from(tx) * 73 + u32::from(ty) * 151) % 100;
    if n < 50 {
        MAP_GRASS
    } else if n < 72 {
        MAP_GRASS2
    } else if n < 88 {
        MAP_PLAINS
    } else {
        MAP_FOREST
    }
}

/// Pixel bounds of the hex board (for the frame + vignette).
fn board_size(sim: &Sim, cell: f32) -> (f32, f32) {
    let cols = f32::from(sim.map().width().saturating_sub(1));
    let rows = f32::from(sim.map().height());
    ((0.75 * cols + 1.0) * cell, (rows + 0.5) * cell)
}

/// Draws the battlefield as a gilded antique **hex** campaign-map: flat-top hex
/// terrain tiles in warm painted tones, a sepia varnish + edge vignette, and an
/// ornate gold deco frame with corner ornaments — matching the regal menu.
fn draw_ground(sim: &Sim, cell: f32) {
    let cols = sim.map().width();
    let rows = sim.map().height();
    let (bw, bh) = board_size(sim, cell);
    let ox = board_origin_x(sim, cell);
    draw_rectangle(ox, WORLD_TOP, bw, bh, GROUND);
    for row in 0..rows {
        for col in 0..cols {
            let (cx, cy) = hex_center_px(col, row, cell, ox);
            draw_hex(cx, cy, cell, terrain_tone(col, row));
            if (col / 4 + row / 4).is_multiple_of(2) {
                draw_hex(cx, cy, cell, GROUND_MACRO);
            }
            draw_hex_outline(cx, cy, cell, 1.0, GRID);
        }
    }
    // Warm sepia varnish — a soft gold wash lifting the lit center.
    draw_ellipse(
        ox + bw / 2.0,
        WORLD_TOP + bh * 0.42,
        bw * 0.5,
        bh * 0.42,
        0.0,
        VARNISH,
    );
    // Edge vignette: concentric darkening frames, heaviest at the rim.
    for (i, alpha) in [80u8, 60, 45, 30].into_iter().enumerate() {
        let inset = i as f32 * cell;
        draw_rectangle_lines(
            ox + inset,
            WORLD_TOP + inset,
            bw - inset * 2.0,
            bh - inset * 2.0,
            cell,
            Color::from_rgba(16, 12, 4, alpha),
        );
    }
    // Ornate gold deco frame (brass bevel) + inner gold rule + corner ornaments.
    let board = Rect::new(ox, WORLD_TOP, bw, bh);
    beveled_frame(board, 5.0, DECO_GOLD_HI, theme::GOLD_DK);
    draw_rectangle_lines(ox, WORLD_TOP, bw, bh, 1.0, BRONZE);
    draw_rectangle_lines(
        ox + 8.0,
        WORLD_TOP + 8.0,
        bw - 16.0,
        bh - 16.0,
        1.5,
        with_alpha(DECO_GOLD, 0.7),
    );
    corner_ornament(ox, WORLD_TOP, 1.0, 1.0);
    corner_ornament(ox + bw, WORLD_TOP, -1.0, 1.0);
    corner_ornament(ox, WORLD_TOP + bh, 1.0, -1.0);
    corner_ornament(ox + bw, WORLD_TOP + bh, -1.0, -1.0);
}

/// The hovered hex during building placement (mouse → cell), board centered.
fn mouse_hex(sim: &Sim, cell: f32) -> (u16, u16) {
    let (mx, my) = mouse_position();
    let ox = board_origin_x(sim, cell);
    let wx = Fixed::from_bits((((mx - ox) / cell) * 65536.0) as i64);
    let wy = Fixed::from_bits((((my - WORLD_TOP) / cell) * 65536.0) as i64);
    hex::from_world(SimVec2::new(wx, wy), sim.map().width(), sim.map().height())
}

/// Faint hex outlines over buildable cells, shown while placing a building.
fn draw_build_grid(sim: &Sim, cell: f32) {
    let col = Color::from_rgba(255, 255, 255, 24);
    let ox = board_origin_x(sim, cell);
    for row in 0..sim.map().height() {
        for tx in 0..sim.map().width() {
            if sim
                .map()
                .tile(i32::from(tx), i32::from(row))
                .is_some_and(|t| t.buildable)
            {
                let (cx, cy) = hex_center_px(tx, row, cell, ox);
                draw_hex_outline(cx, cy, cell, 1.0, col);
            }
        }
    }
}

/// Draws shot tracers for the most recent combat tick (combat juice).
fn draw_tracers(sim: &Sim, cell: f32) {
    let color = TRACER;
    let ox = board_origin_x(sim, cell);
    for &(from, to) in sim.recent_attacks() {
        draw_line(
            ox + tile_to_px(from.x, cell),
            WORLD_TOP + tile_to_px(from.y, cell),
            ox + tile_to_px(to.x, cell),
            WORLD_TOP + tile_to_px(to.y, cell),
            1.5,
            color,
        );
    }
}

/// Draws a translucent placement ghost on the moused hex: green if buildable and
/// affordable, red otherwise.
fn draw_build_ghost(sim: &Sim, kind: BuildingKind, cell: f32) {
    let (col, row) = mouse_hex(sim, cell);
    let buildable = sim
        .map()
        .tile(i32::from(col), i32::from(row))
        .is_some_and(|t| t.buildable);
    let affordable = sim.credits(HUMAN) >= sim.building_cost(kind);
    let fill = if buildable && affordable {
        Color::from_rgba(80, 200, 120, 120)
    } else {
        Color::from_rgba(200, 80, 80, 120)
    };
    let (cx, cy) = hex_center_px(col, row, cell, board_origin_x(sim, cell));
    draw_hex(cx, cy, cell, fill);
    draw_hex_outline(
        cx,
        cy,
        cell,
        2.0,
        if buildable && affordable { GOOD } else { BAD },
    );
}

/// Draws impassable terrain as **mountain hexes** (ramparts): a dark rampart body
/// with a lighter raised peak and a dark outline, matching the design's mountain
/// tiles that block movement.
fn draw_terrain(sim: &Sim, cell: f32) {
    let map = sim.map();
    let ox = board_origin_x(sim, cell);
    for row in 0..map.height() {
        for col in 0..map.width() {
            if map.tile(i32::from(col), i32::from(row)).unwrap().passable {
                continue;
            }
            let (cx, cy) = hex_center_px(col, row, cell, ox);
            draw_hex(cx, cy, cell, TERRAIN_WALL); // rampart body
            draw_hex(cx, cy - cell * 0.12, cell * 0.6, WALL_TOP); // raised lit peak
            draw_hex(cx, cy - cell * 0.2, cell * 0.28, WALL_HI); // bright cap
            draw_hex_outline(cx, cy, cell, 1.5, WALL_EDGE);
        }
    }
}

/// Health bar over a piece. Full-health pieces are left clean; once damaged a
/// framed gauge appears so it reads as a deliberate readout, not a stray sliver.
fn draw_health_bar(x: f32, y: f32, cell: f32, hp: Fixed, max_hp: Fixed) {
    let frac = (hp.to_bits() as f32 / max_hp.to_bits() as f32).clamp(0.0, 1.0);
    if frac >= 0.999 {
        return;
    }
    let width = cell * 1.1;
    let left = x - width / 2.0;
    let top = y - cell * 0.82;
    draw_rectangle(left - 1.0, top - 1.0, width + 2.0, 6.0, WALL_EDGE); // frame plate
    draw_rectangle(left, top, width, 4.0, HP_TRACK);
    draw_rectangle(left, top, width * frac, 4.0, hp_color(frac));
}

#[cfg(test)]
mod tests {
    use super::tech_status;

    #[test]
    fn researched_bit_takes_priority() {
        // Bit 0 set => Researched regardless of active slot.
        let status = tech_status(0, None, 300, 0b0001, None, true);
        assert!(matches!(status, super::TechStatus::Researched));
    }

    #[test]
    fn in_progress_reports_correct_percent() {
        // 150 ticks remaining out of 300 => 50 %.
        let status = tech_status(0, None, 300, 0, Some((0, 150)), true);
        if let super::TechStatus::InProgress {
            ticks_remaining,
            duration,
        } = status
        {
            let elapsed = duration.saturating_sub(ticks_remaining);
            let pct = (elapsed * 100) / duration;
            assert_eq!(pct, 50);
        } else {
            panic!("expected InProgress");
        }
    }

    #[test]
    fn locked_when_prereq_not_researched() {
        // tech 1 requires tech 0; mask = 0 (nothing researched).
        let status = tech_status(1, Some(0), 450, 0, None, true);
        assert!(matches!(status, super::TechStatus::Locked));
    }

    #[test]
    fn no_lab_status_when_lab_absent() {
        let status = tech_status(0, None, 300, 0, None, false);
        assert!(matches!(status, super::TechStatus::NoLab));
    }

    #[test]
    fn available_when_prereq_met_and_lab_present() {
        // tech 1 requires tech 0; mask = 0b0001 (tech 0 done).
        let status = tech_status(1, Some(0), 450, 0b0001, None, true);
        assert!(matches!(status, super::TechStatus::Available));
    }
}
