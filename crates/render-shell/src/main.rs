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

mod anim;
mod audio;
mod input;
mod meta;
mod particles;
mod sprites;
mod theme;
mod ui;
mod view;

use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::hex;
use rts_core::game::map::DepositKind;
use rts_core::game::perk;
use rts_core::game::scenario::Scenario;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::game::tech::TECHS;
use rts_core::vec::Vec2 as SimVec2;
use sprites::Sprites;
// Explicit theme imports (not a glob) so they take precedence over the
// like-named macroquad prelude color constants (e.g. GOLD).
use theme::{
    glow_rect, holo_flicker, hp_color, BAD, BASE_CHARCOAL, BORDER_NEUTRAL, BRONZE, DECO_GOLD,
    DECO_GOLD_HI, GOLD, GOLD_HI, GOOD, GRID, GRID_HOT, GROUND, GROUND_MACRO, HOLO_GLOW, HP_TRACK,
    INK, INK_DIM, MAP_FOREST, MAP_GRASS, MAP_GRASS2, MAP_PLAINS, OLIVE, PANEL, PANEL_RAISED,
    PARCHMENT, PARCHMENT_EDGE, PARCHMENT_HI, PARCHMENT_LO, PIECE_SHADOW, REGAL_BG, REGAL_BG_HI,
    REGAL_BG_LO, SELECT_RING, SHIELD, TEAM_ENEMY, TEAM_PLAYER, TERRAIN_WALL, TEXT, TEXT_DIM,
    TRACER, VARNISH, WALL_EDGE, WALL_HI, WALL_TOP, WARN, WELL,
};

/// Fixed simulation timestep (30 Hz), decoupled from the render frame rate.
const TICK_DT: f32 = 1.0 / 30.0;
const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);
/// The battlefield is drawn below the top bar.
const WORLD_TOP: f32 = ui::TOP_BAR_H;
/// Surviving this many waves earns the celebratory "BEACHHEAD SECURED" milestone.
/// The run keeps going — survival stays an endurance mode; this is the goal to
/// beat, not an ending.
const SURVIVAL_MILESTONE_WAVE: u32 = 15;

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

/// A fresh, run-varying seed for a Survival match (derived from the wall clock).
/// Survival runs aren't replayed or networked, so a non-deterministic seed is
/// fine — each run stays fully deterministic *given* its seed, and every run gets
/// a different procedural map.
fn survival_seed() -> u64 {
    (get_time() * 1000.0) as u64 ^ 0xA5A5_5A5A_C3C3_3C3C
}

/// Clickable band for the "press S for Survival" banner on the title screen,
/// shared by the renderer and the hit-test so they can't drift.
fn survival_button_rect() -> Rect {
    let c = cartouche();
    let w = 520.0_f32.min(screen_width() - 40.0);
    Rect::new((screen_width() - w) / 2.0, c.y + c.h + 44.0, w, 30.0)
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
fn hex_center_px(col: u16, row: u16, cell: f32, ox: f32, wtop: f32) -> (f32, f32) {
    let c = hex::center(col, row);
    (ox + tile_to_px(c.x, cell), wtop + tile_to_px(c.y, cell))
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
    let mut audio = audio::AudioMgr::load().await;
    let mut scenario = Scenario::LaneDefense;
    let mut sim = new_match(scenario);
    let mut selected: Option<EntityId> = None;
    let mut build_mode: Option<BuildingKind> = None;
    let mut pending = Vec::new();
    let mut accumulator = 0.0_f32;
    let mut paused = false;
    // Sim speed multiplier (1–3×): Civ-pace games need a fast-forward for the
    // quiet stretches. `-` slows, `=`/`+` speeds up; determinism is untouched
    // (the same ticks run, just more per wall-clock second).
    let mut game_speed: u32 = 1;
    let mut research_open = false;
    let mut research_cursor: usize = 0;
    let mut doctrine_open = false;
    let mut doctrine_cursor: usize = 0;
    let mut phase = Phase::Title;
    // Shell-side animated view layer (interpolation, bars, FX events) + particle
    // pool. Pure view state — never feeds back into the deterministic sim.
    let mut view = view::ViewState::default();
    let mut particles = particles::Particles::new();
    let mut camera = anim::Camera::default();
    // Hit-stop: while > 0 the sim is frozen (in wall-clock) for impact emphasis.
    let mut hitstop = 0.0_f32;
    // Audio bookkeeping: one-shot game-over jingle + wave-incoming alarm edges.
    let mut over_announced = false;
    let mut prev_wave_secs: i64 = i64::MAX;
    // Whether the current match is a survival run (drives the score HUD + summary).
    let mut survival_run = false;
    // Survival perk draft: a modal opens each new wave until all perks are taken.
    let mut perk_open = false;
    let mut prev_waves = 0_u32;
    let mut best_waves = meta::best_waves();
    // Seconds left on the transient "BEACHHEAD SECURED" milestone banner.
    let mut milestone_flash: f32 = 0.0;

    loop {
        if phase == Phase::Title {
            // Hover highlights a map; click / number key / Enter chooses one.
            if let Some(hovered) = scenario_at_pointer() {
                scenario = hovered;
            }
            let clicked = is_mouse_button_pressed(MouseButton::Left);
            let (mx, my) = mouse_position();
            let on_survival = survival_button_rect().contains(vec2(mx, my));
            // 'S' or the Survival banner launches a Survival run on a fresh
            // procedural map; a map row / number key / Enter launches the picked
            // skirmish scenario.
            let start = if is_key_pressed(KeyCode::S) || (clicked && on_survival) {
                Some((Scenario::Survival, survival_seed()))
            } else {
                scenario_hotkey()
                    .or_else(|| (clicked && !on_survival).then_some(scenario))
                    .or_else(|| is_key_pressed(KeyCode::Enter).then_some(scenario))
                    .map(|sc| (sc, MATCH_SEED))
            };
            if let Some((sc, seed)) = start {
                scenario = sc;
                survival_run = sc == Scenario::Survival;
                phase = Phase::Playing;
                sim = sc.build(seed);
                view = view::ViewState::default();
                view.on_tick(&sim);
                particles.clear();
                camera = anim::Camera::default();
                hitstop = 0.0;
                over_announced = false;
                prev_wave_secs = i64::MAX;
                perk_open = false;
                prev_waves = 0;
                milestone_flash = 0.0;
                audio.set_music(audio::Music::Combat);
                selected = None;
                build_mode = None;
                pending.clear();
                accumulator = 0.0;
                research_open = false;
                doctrine_open = false;
            }
            draw_title(&sprites, scenario);
            next_frame().await;
            continue;
        }

        let cell = cell_size(&sim);
        let over = sim.winner().is_some();

        // Survival perk draft: each newly-spawned wave grants a perk pick until
        // all are taken, opening a (time-freezing) draft modal.
        if survival_run && !over {
            let w = sim.waves_survived();
            if w > prev_waves {
                // Crossing the milestone wave earns the celebration (run continues).
                if prev_waves < SURVIVAL_MILESTONE_WAVE && w >= SURVIVAL_MILESTONE_WAVE {
                    milestone_flash = 5.0;
                    audio.play(audio::Sfx::Victory);
                }
                prev_waves = w;
                if sim.perks(HUMAN).count_ones() < perk::PERK_COUNT {
                    perk_open = true;
                }
            }
        }
        // Perk-draft input: number keys 1..N choose an untaken perk; Esc defers.
        if perk_open {
            let owned = sim.perks(HUMAN);
            let keys = [KeyCode::Key1, KeyCode::Key2, KeyCode::Key3, KeyCode::Key4];
            for (i, key) in keys.into_iter().enumerate() {
                let pid = u32::try_from(i).unwrap_or(0);
                if pid < perk::PERK_COUNT && is_key_pressed(key) && owned & (1 << pid) == 0 {
                    pending.push(Command::ChoosePerk {
                        owner: HUMAN,
                        perk: pid,
                    });
                    perk_open = false;
                }
            }
            if is_key_pressed(KeyCode::Escape) {
                perk_open = false;
            }
        }

        // Survey phase: the only interaction is founding the Command Center. A
        // left-click on a buildable hex emits FoundBase; normal map/UI input is
        // suppressed until the base exists.
        let surveying = sim.surveying();
        if surveying {
            if is_mouse_button_pressed(MouseButton::Left) && !ui::pointer_over_ui() {
                let (col, row) = input::cursor_tile(&sim, cell);
                if sim
                    .map()
                    .tile(i32::from(col), i32::from(row))
                    .is_some_and(|t| t.buildable)
                {
                    pending.push(Command::FoundBase {
                        owner: HUMAN,
                        x: col,
                        y: row,
                    });
                    audio.play(audio::Sfx::Build);
                }
            }
        } else if !research_open && !perk_open && !doctrine_open {
            // Input: UI command bar first, then map (suppressed while over the UI
            // or a modal).
            if is_mouse_button_pressed(MouseButton::Left) && ui::pointer_over_ui() {
                audio.play(audio::Sfx::UiClick);
            }
            pending.extend(ui::handle_click(&sim, &mut build_mode));
            pending.extend(input::gather_commands(
                &sim,
                &mut selected,
                &mut build_mode,
                ui::pointer_over_ui(),
                cell,
            ));
        }
        if !research_open && !doctrine_open && is_key_pressed(KeyCode::Space) {
            paused = !paused;
        }
        if is_key_pressed(KeyCode::Equal) {
            game_speed = (game_speed + 1).min(3);
        }
        if is_key_pressed(KeyCode::Minus) {
            game_speed = game_speed.saturating_sub(1).max(1);
        }
        // Toggle research modal with Y (only while playing, not paused, not on title/game-over).
        if !over && !paused && !doctrine_open && is_key_pressed(KeyCode::Y) {
            research_open = !research_open;
        }
        // Toggle the Ascendancy Doctrines modal with U (Upgrades). Mutually
        // exclusive with research; unlike research it does NOT freeze time, so the
        // surplus can be spent on the fly and several levels bought in a row.
        if !over && !paused && !research_open && !perk_open && is_key_pressed(KeyCode::U) {
            doctrine_open = !doctrine_open;
        }
        if doctrine_open {
            let n = 4usize;
            if is_key_pressed(KeyCode::Down) {
                doctrine_cursor = (doctrine_cursor + 1) % n;
            }
            if is_key_pressed(KeyCode::Up) {
                doctrine_cursor = (doctrine_cursor + n - 1) % n;
            }
            let keys = [KeyCode::Key1, KeyCode::Key2, KeyCode::Key3, KeyCode::Key4];
            let mut chosen: Option<usize> =
                is_key_pressed(KeyCode::Enter).then_some(doctrine_cursor);
            for (i, key) in keys.into_iter().enumerate() {
                if is_key_pressed(key) {
                    doctrine_cursor = i;
                    chosen = Some(i);
                }
            }
            if let Some(track) = chosen {
                // Core validates affordability + lab presence; emit the intent and
                // keep the modal open so the player can buy several levels.
                pending.push(Command::Ascend {
                    owner: HUMAN,
                    track: u8::try_from(track).unwrap_or(0),
                });
            }
            if is_key_pressed(KeyCode::Escape) {
                doctrine_open = false;
            }
        }
        // Research modal: ↑/↓ move the cursor over the full tree, Enter researches
        // the highlighted tech; number keys 1-0 are quick shortcuts for the first
        // ten; Escape closes. (Cursor navigation makes every tech reachable —
        // eras, shields, anti-grav, and the doctrine fork, not just the first 10.)
        if research_open {
            let n = TECHS.len();
            if is_key_pressed(KeyCode::Down) {
                research_cursor = (research_cursor + 1) % n;
            }
            if is_key_pressed(KeyCode::Up) {
                research_cursor = (research_cursor + n - 1) % n;
            }
            let num_keys = [
                KeyCode::Key1,
                KeyCode::Key2,
                KeyCode::Key3,
                KeyCode::Key4,
                KeyCode::Key5,
                KeyCode::Key6,
                KeyCode::Key7,
                KeyCode::Key8,
                KeyCode::Key9,
                KeyCode::Key0,
            ];
            let mut chosen: Option<u32> = is_key_pressed(KeyCode::Enter)
                .then_some(u32::try_from(research_cursor).unwrap_or(0));
            for (i, key) in num_keys.into_iter().enumerate() {
                if is_key_pressed(key) {
                    research_cursor = i;
                    chosen = Some(u32::try_from(i).unwrap_or(0));
                }
            }
            if let Some(tech_id) = chosen {
                // Core validates affordability, prereq, fork lock, and lab presence.
                if sim.research_state(HUMAN).1.is_none() {
                    pending.push(Command::Research {
                        owner: HUMAN,
                        tech_id,
                    });
                }
                research_open = false;
            }
            if is_key_pressed(KeyCode::Escape) {
                research_open = false;
            }
        }
        if over && is_key_pressed(KeyCode::R) {
            // Survival restarts on a fresh procedural map; skirmish replays its map.
            sim = if survival_run {
                scenario.build(survival_seed())
            } else {
                new_match(scenario)
            };
            view = view::ViewState::default();
            view.on_tick(&sim);
            particles.clear();
            camera = anim::Camera::default();
            hitstop = 0.0;
            over_announced = false;
            prev_wave_secs = i64::MAX;
            perk_open = false;
            prev_waves = 0;
            milestone_flash = 0.0;
            audio.set_music(audio::Music::Combat);
            selected = None;
            build_mode = None;
            pending.clear();
            accumulator = 0.0;
            research_open = false;
            doctrine_open = false;
        }
        // Return to the map-select screen.
        if over && is_key_pressed(KeyCode::M) {
            phase = Phase::Title;
            audio.set_music(audio::Music::Menu);
            selected = None;
            build_mode = None;
            pending.clear();
            accumulator = 0.0;
            research_open = false;
            doctrine_open = false;
        }

        // Advance the fixed-timestep sim unless paused, the match is over, or the
        // research modal is open (the modal freezes time so the player can read it).
        // Clamp frame time so a stall / slow frame can't dump hundreds of ticks at
        // once (the "spiral of death") and fast-forward past wave spawns.
        let dt = get_frame_time().min(0.1);
        // Hit-stop freezes the sim (in wall-clock) for a beat on big impacts; the
        // accumulator simply doesn't grow, so no ticks run and rendering continues.
        if hitstop > 0.0 {
            hitstop = (hitstop - dt).max(0.0);
        } else {
            accumulator += dt * game_speed as f32;
        }
        if paused || over || research_open || perk_open {
            accumulator = 0.0;
            pending.clear();
        }
        while accumulator >= TICK_DT {
            let mut commands = std::mem::take(&mut pending);
            // In survival, keep the build-up peaceful: the alien beachhead AI only acts
            // once the first wave has spawned. Skirmish AI is unaffected.
            if !survival_run || sim.waves_survived() > 0 {
                commands.extend(sim.ai_commands(ENEMY));
            }
            sim.step(&commands);
            view.on_tick(&sim);
            accumulator -= TICK_DT;
        }
        // Drop a selection whose entity died: slots are recycled, so a stale id
        // could otherwise issue Move/UseAbility through a different unit that
        // reused it.
        if let Some(id) = selected {
            if !sim.views().iter().any(|v| v.id == id && v.owner == HUMAN) {
                selected = None;
            }
        }
        view.frame(dt);
        // Turn this frame's FX events into particles, then advance the pool.
        let ofx = board_origin_x(&sim, cell);
        for ev in view.events.drain(..) {
            match ev {
                view::FxEvent::Death {
                    world,
                    building,
                    human,
                } => {
                    let p = vec2(ofx + world.x * cell, WORLD_TOP + world.y * cell);
                    let col = if human { TEAM_PLAYER } else { TEAM_ENEMY };
                    particles.explosion(p, col, if building { 1.8 } else { 1.0 });
                    if building {
                        particles.debris(p, col);
                        hitstop = hitstop.max(0.07);
                    }
                    particles.scorch(world, if building { 0.9 } else { 0.45 });
                    camera.add_trauma(if building { 0.5 } else { 0.18 });
                    audio.play_throttled(audio::Sfx::Explosion, 0.04);
                }
                view::FxEvent::Spawn {
                    world,
                    building,
                    human,
                } => {
                    let p = vec2(ofx + world.x * cell, WORLD_TOP + world.y * cell);
                    let col = if human { TEAM_PLAYER } else { TEAM_ENEMY };
                    if building {
                        particles.poof(p, col);
                        audio.play_throttled(audio::Sfx::Build, 0.06);
                    } else {
                        particles.warp_in(p, col);
                        audio.play_throttled(audio::Sfx::Train, 0.06);
                    }
                }
                view::FxEvent::Hit {
                    world,
                    human,
                    amount,
                } => {
                    let p = vec2(ofx + world.x * cell, WORLD_TOP + world.y * cell);
                    let col = if human { TEAM_PLAYER } else { TEAM_ENEMY };
                    particles.impact(p, col, amount * 0.12);
                    camera.add_trauma((amount * 0.01).min(0.12));
                }
            }
        }
        // Muzzle flashes at the firing end of this tick's shots.
        for &(from, _to) in sim.recent_attacks() {
            let f = vec2(
                ofx + tile_to_px(from.x, cell),
                WORLD_TOP + tile_to_px(from.y, cell),
            );
            particles.muzzle(f, TRACER);
        }
        if !sim.recent_attacks().is_empty() {
            audio.play_throttled(audio::Sfx::Laser, 0.05);
        }
        particles.update(dt);
        camera.update(dt);

        // Wave-incoming alarm: fire once as the countdown crosses 5 seconds.
        let wave_secs = sim
            .ticks_until_next_wave()
            .map_or(i64::MAX, |t| (t / 30) as i64);
        if prev_wave_secs > 5 && wave_secs <= 5 {
            audio.play(audio::Sfx::WaveIncoming);
        }
        prev_wave_secs = wave_secs;

        // Game-over jingle, once; stop the music; record the survival high score.
        if let Some(winner) = sim.winner() {
            if !over_announced {
                over_announced = true;
                audio.stop_music();
                audio.play(if winner == HUMAN {
                    audio::Sfx::Victory
                } else {
                    audio::Sfx::Defeat
                });
                if survival_run {
                    best_waves = meta::record_waves(sim.waves_survived());
                }
            }
        }

        let alpha = (accumulator / TICK_DT).clamp(0.0, 1.0);
        let (sx, sy) = camera.offset(7.0);

        draw(
            &sim, &view, &particles, selected, build_mode, cell, alpha, sx, sy, &sprites,
        );
        if surveying {
            draw_survey_overlay(&sim, cell, &sprites);
        }
        ui::draw(&sim, build_mode, paused, game_speed, selected, &sprites);
        if survival_run && !surveying {
            draw_survival_hud(&sim, &sprites);
            if milestone_flash > 0.0 {
                milestone_flash -= get_frame_time();
                draw_milestone_banner(milestone_flash, &sprites);
            }
        }
        if research_open {
            draw_research_modal(&sim, research_cursor, &sprites);
        }
        if doctrine_open {
            draw_doctrine_modal(&sim, doctrine_cursor, &sprites);
        }
        if perk_open {
            draw_perk_modal(&sim, &sprites);
        }
        if let Some(winner) = sim.winner() {
            let score = survival_run.then(|| (sim.waves_survived(), best_waves));
            draw_game_over(winner, score, &sprites);
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
    // tactical-console linework: contour rings + graticule (faint holo cyan)
    let ring = Color::from_rgba(64, 220, 235, 18);
    for r in [150.0_f32, 280.0, 430.0] {
        draw_circle_lines(cx, fc, r, 1.0, ring);
    }
    let grat = Color::from_rgba(64, 220, 235, 12);
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
            Color::from_rgba(3, 6, 12, a),
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
        with_alpha(DECO_GOLD_HI, holo_flicker()),
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
    centered(
        &format!(
            "— or press  S  for SURVIVAL: hold {SURVIVAL_MILESTONE_WAVE} endless waves to secure the beachhead —"
        ),
        c.y + c.h + 58.0,
        16.0,
        GOLD_HI,
        sprites.font_bold(),
    );
    centered(
        "in battle:  Y research  \u{2022}  U doctrines  \u{2022}  Q cast ability  \u{2022}  Space pause  \u{2022}  +/- speed",
        c.y + c.h + 82.0,
        13.0,
        INK_DIM,
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
            Color::from_rgba(64, 220, 235, 56),
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

fn draw_game_over(winner: PlayerId, survival_score: Option<(u32, u32)>, sprites: &Sprites) {
    let (w, h) = (screen_width(), screen_height());
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 175));
    // Survival runs get a taller card: waves + (possibly) the milestone + best.
    let pw = 440.0;
    let ph = if survival_score.is_some() {
        240.0
    } else {
        212.0
    };
    let (px, py) = ((w - pw) / 2.0, (h - ph) / 2.0);
    draw_rectangle(px, py, pw, ph, PANEL);
    glow_rect(px, py, pw, ph, HOLO_GLOW, 3);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);
    let (msg, color) = if winner == HUMAN {
        ("REPELLED", GOOD)
    } else {
        ("OVERRUN", BAD)
    };
    centered(msg, py + 78.0, 54.0, color, sprites.font_display());
    if let Some((waves, best)) = survival_score {
        centered(
            &format!("WAVES SURVIVED  {waves}"),
            py + 116.0,
            22.0,
            GOLD_HI,
            sprites.font_bold(),
        );
        if waves >= SURVIVAL_MILESTONE_WAVE {
            centered(
                "\u{2605}  BEACHHEAD SECURED  \u{2605}",
                py + 142.0,
                17.0,
                GOOD,
                sprites.font_bold(),
            );
        }
        centered(
            &format!("BEST  {best}"),
            py + 164.0,
            16.0,
            TEXT_DIM,
            sprites.font(),
        );
    }
    centered(
        "R to restart    •    M for map select",
        py + ph - 36.0,
        20.0,
        TEXT,
        sprites.font(),
    );
}

/// A compact survival readout (waves survived = score) under the top bar.
/// The Survey-phase overlay: tint every hex by foundability (red illegal / cyan
/// legal / green deposit-adjacent premium), ring the cursor tile, and prompt the
/// player to choose a site. Founding adjacent to an Ore deposit pays a bonus, so
/// green tiles are the recommended picks.
fn draw_survey_overlay(sim: &Sim, cell: f32, sprites: &Sprites) {
    let ox = board_origin_x(sim, cell);
    let wtop = WORLD_TOP;
    let map = sim.map();
    let (cur_c, cur_r) = input::cursor_tile(sim, cell);
    let pulse = (get_time() as f32 * 2.5).sin() * 0.5 + 0.5;
    for row in 0..map.height() {
        for col in 0..map.width() {
            let buildable = map
                .tile(i32::from(col), i32::from(row))
                .is_some_and(|t| t.buildable);
            if !buildable {
                continue; // leave blocked/occupied tiles untinted (read as illegal)
            }
            let near_ore = map.deposits().any(|(dx, dy, d)| {
                matches!(d.kind, rts_core::game::map::DepositKind::Ore)
                    && (i32::from(dx) - i32::from(col)).abs() <= 1
                    && (i32::from(dy) - i32::from(row)).abs() <= 1
            });
            let (cx, cy) = hex_center_px(col, row, cell, ox, wtop);
            let tint = if near_ore {
                with_alpha(GOOD, 0.22)
            } else {
                with_alpha(HOLO_GLOW, 0.10)
            };
            draw_hex(cx, cy, cell * 0.9, tint);
        }
    }
    // Cursor: green ring on a legal tile (brighter if a premium ore site), red if
    // illegal.
    let legal = map
        .tile(i32::from(cur_c), i32::from(cur_r))
        .is_some_and(|t| t.buildable);
    let (cx, cy) = hex_center_px(cur_c, cur_r, cell, ox, wtop);
    let ring = if legal { GOOD } else { BAD };
    draw_circle_lines(cx, cy, cell * (0.5 + pulse * 0.12), 2.5, ring);

    // Prompt banner.
    let fd = sprites.font_display();
    let title = "SURVEY  \u{2014}  CHOOSE A FOUNDING SITE";
    let tw = measure_text(title, fd, 30, 1.0).width;
    let bx = (screen_width() - tw) / 2.0;
    let by = WORLD_TOP + 36.0;
    draw_rectangle(
        bx - 22.0,
        by - 30.0,
        tw + 44.0,
        64.0,
        with_alpha(PANEL, 0.85),
    );
    glow_rect(bx - 22.0, by - 30.0, tw + 44.0, 64.0, HOLO_GLOW, 3);
    draw_text_ex(
        title,
        bx,
        by,
        TextParams {
            font: fd,
            font_size: 30,
            color: GOLD_HI,
            ..Default::default()
        },
    );
    centered(
        "click a tile to land your Command Center  \u{2022}  green = beside ore (bonus)",
        by + 22.0,
        15.0,
        TEXT_DIM,
        sprites.font(),
    );
}

fn draw_survival_hud(sim: &Sim, sprites: &Sprites) {
    let s = format!("WAVE {}", sim.waves_survived() + 1);
    let fb = sprites.font_bold();
    let tw = measure_text(&s, fb, 20, 1.0).width;
    let x = (screen_width() - tw) / 2.0;
    let y = WORLD_TOP + 20.0;
    draw_rectangle(x - 12.0, y - 17.0, tw + 24.0, 24.0, PANEL);
    glow_rect(x - 12.0, y - 17.0, tw + 24.0, 24.0, HOLO_GLOW, 2);
    draw_text_ex(
        &s,
        x,
        y,
        TextParams {
            font: fb,
            font_size: 20,
            color: GOLD_HI,
            ..Default::default()
        },
    );
}

/// Transient celebration when the survival milestone wave is reached. The run
/// keeps going — this marks the goal beaten, it is not an ending. Fades out over
/// its final second.
fn draw_milestone_banner(remaining: f32, sprites: &Sprites) {
    let alpha = remaining.clamp(0.0, 1.0);
    let fd = sprites.font_display();
    let s = "BEACHHEAD SECURED";
    let tw = measure_text(s, fd, 40, 1.0).width;
    let x = (screen_width() - tw) / 2.0;
    let y = WORLD_TOP + 110.0;
    draw_rectangle(
        x - 26.0,
        y - 36.0,
        tw + 52.0,
        72.0,
        with_alpha(PANEL, 0.88 * alpha),
    );
    glow_rect(x - 26.0, y - 36.0, tw + 52.0, 72.0, HOLO_GLOW, 3);
    draw_rectangle(x - 26.0, y - 36.0, tw + 52.0, 3.0, with_alpha(GOOD, alpha));
    draw_text_ex(
        s,
        x,
        y + 8.0,
        TextParams {
            font: fd,
            font_size: 40,
            color: with_alpha(GOOD, alpha),
            ..Default::default()
        },
    );
    centered(
        "the line held — now see how long you can last",
        y + 28.0,
        14.0,
        with_alpha(TEXT_DIM, alpha),
        sprites.font(),
    );
}

/// Survival perk-draft overlay: pick one untaken perk with number keys 1-N.
fn draw_perk_modal(sim: &Sim, sprites: &Sprites) {
    let (w, h) = (screen_width(), screen_height());
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 200));
    let owned = sim.perks(HUMAN);
    let n = perk::PERK_COUNT;
    let row_h = 52.0;
    let pw = 460.0_f32.min(w - 40.0);
    let ph = 64.0 + n as f32 * row_h + 44.0;
    let px = (w - pw) / 2.0;
    let py = (h - ph) / 2.0;
    draw_rectangle(px, py, pw, ph, PANEL);
    glow_rect(px, py, pw, ph, HOLO_GLOW, 3);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);
    centered("CHOOSE A PERK", py + 38.0, 26.0, GOLD, sprites.font_bold());
    let fb = sprites.font_bold();
    let f = sprites.font();
    for i in 0..n {
        let ry = py + 64.0 + i as f32 * row_h;
        let taken = owned & (1 << i) != 0;
        let row = Rect::new(px + 12.0, ry, pw - 24.0, row_h - 8.0);
        draw_rectangle(
            row.x,
            row.y,
            row.w,
            row.h,
            if taken { WELL } else { PANEL_RAISED },
        );
        let rim = if taken { BORDER_NEUTRAL } else { GOLD_HI };
        draw_rectangle_lines(row.x, row.y, row.w, row.h, 1.5, rim);
        // Number chip.
        let key_s = format!("{}", i + 1);
        draw_text_ex(
            &key_s,
            row.x + 12.0,
            row.y + 30.0,
            TextParams {
                font: fb,
                font_size: 22,
                color: if taken { TEXT_DIM } else { GOLD_HI },
                ..Default::default()
            },
        );
        let name_col = if taken { TEXT_DIM } else { TEXT };
        draw_text_ex(
            perk::name(i),
            row.x + 44.0,
            row.y + 22.0,
            TextParams {
                font: fb,
                font_size: 19,
                color: name_col,
                ..Default::default()
            },
        );
        let desc = if taken {
            "— already taken —"
        } else {
            perk::description(i)
        };
        draw_text_ex(
            desc,
            row.x + 44.0,
            row.y + 40.0,
            TextParams {
                font: f,
                font_size: 15,
                color: if taken { TEXT_DIM } else { GOOD },
                ..Default::default()
            },
        );
    }
    centered(
        "press 1-4 to choose  \u{2022}  Esc to skip",
        py + ph - 18.0,
        15.0,
        TEXT_DIM,
        f,
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
    // A doctrine fork locks out its counterpart once the other is researched.
    if rts_core::game::tech::excludes(tech_id).is_some_and(|other| mask & (1 << other) != 0) {
        return TechStatus::Locked;
    }
    if !has_lab {
        return TechStatus::NoLab;
    }
    TechStatus::Available
}

/// Full-screen overlay listing the whole tech tree with status + progress. The
/// `cursor` row is highlighted; ↑/↓ move it, Enter (or 1-0 for the first ten)
/// starts research; Escape closes.
/// The Ascendancy Doctrines panel (key: U). Four endless, escalating-cost
/// upgrade tracks that spend the late-game Minerals/Research surplus on permanent
/// army-wide quality. Unlike research it does not freeze time, so the overlay is
/// kept light and the player can buy several levels between waves.
fn draw_doctrine_modal(sim: &Sim, cursor: usize, sprites: &Sprites) {
    const NAMES: [&str; 4] = ["WEAPONS", "ARMOR", "VITALITY", "FORGE"];
    const DESCS: [&str; 4] = [
        "+1 damage / level",
        "+0.5 armor / level",
        "+8 shield / level",
        "+0.25 damage & armor / level  \u{2022}  Minerals only",
    ];
    let (w, h) = (screen_width(), screen_height());
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 120));

    let pw = 560.0_f32.min(w - 40.0);
    let row_h = 58.0;
    let head_h = 50.0;
    let foot_h = 36.0;
    let ph = head_h + 4.0 * row_h + foot_h + 16.0;
    let px = (w - pw) / 2.0;
    let py = (h - ph) / 2.0;

    draw_rectangle(px, py, pw, ph, PANEL);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);

    let fb = sprites.font_bold();
    let f = sprites.font();
    centered("ASCENDANCY DOCTRINES", py + 32.0, 24.0, GOLD, fb);
    draw_rectangle(px + 12.0, py + head_h - 4.0, pw - 24.0, 1.0, OLIVE);

    let minerals = sim.minerals(HUMAN).to_bits() / 65536;
    let research = sim.research(HUMAN).to_bits() / 65536;
    let has_lab = sim.has_research_lab(HUMAN);

    for track in 0..4usize {
        let ry = py + head_h + track as f32 * row_h + 8.0;
        if track % 2 == 0 {
            draw_rectangle(px + 8.0, ry - 4.0, pw - 16.0, row_h - 4.0, WELL);
        }
        if track == cursor {
            draw_rectangle(
                px + 8.0,
                ry - 4.0,
                pw - 16.0,
                row_h - 4.0,
                with_alpha(GOLD, 0.16),
            );
            draw_rectangle_lines(px + 8.0, ry - 4.0, pw - 16.0, row_h - 4.0, 1.5, GOLD_HI);
        }

        // Number-key chip.
        let key_s = (track + 1).to_string();
        draw_rectangle(px + 14.0, ry + 6.0, 18.0, 18.0, PANEL);
        draw_rectangle_lines(px + 14.0, ry + 6.0, 18.0, 18.0, 1.0, BORDER_NEUTRAL);
        let kw = measure_text(&key_s, f, 14, 1.0).width;
        draw_text_ex(
            &key_s,
            px + 23.0 - kw / 2.0,
            ry + 20.0,
            TextParams {
                font: f,
                font_size: 14,
                color: TEXT_DIM,
                ..Default::default()
            },
        );

        let track_u8 = u8::try_from(track).unwrap_or(0);
        let level = sim.doctrine_level(HUMAN, track_u8);
        let (mc, rc) = sim.doctrine_cost(HUMAN, track_u8);
        let mc_i = mc.to_bits() / 65536;
        let rc_i = rc.to_bits() / 65536;
        let is_forge = track == 3;
        let lab_ok = is_forge || has_lab;
        let afford = lab_ok && minerals >= mc_i && research >= rc_i;

        // Name + current level.
        draw_text_ex(
            NAMES[track],
            px + 42.0,
            ry + 18.0,
            TextParams {
                font: fb,
                font_size: 17,
                color: TEXT,
                ..Default::default()
            },
        );
        let lvl_s = format!("Lv {level}");
        draw_text_ex(
            &lvl_s,
            px + 180.0,
            ry + 18.0,
            TextParams {
                font: f,
                font_size: 15,
                color: GOLD_HI,
                ..Default::default()
            },
        );
        // Description.
        draw_text_ex(
            DESCS[track],
            px + 42.0,
            ry + 38.0,
            TextParams {
                font: f,
                font_size: 13,
                color: TEXT_DIM,
                ..Default::default()
            },
        );

        // Cost (right-aligned), tinted by affordability.
        let cost_s = if rc_i > 0 {
            format!("{mc_i}M  {rc_i}R")
        } else {
            format!("{mc_i}M")
        };
        let col = if afford {
            GOOD
        } else if lab_ok {
            TEXT_DIM
        } else {
            BAD
        };
        let cw = measure_text(&cost_s, f, 15, 1.0).width;
        draw_text_ex(
            &cost_s,
            px + pw - cw - 20.0,
            ry + 18.0,
            TextParams {
                font: f,
                font_size: 15,
                color: col,
                ..Default::default()
            },
        );
        if !lab_ok {
            let note = "needs Research Lab";
            let nw = measure_text(note, f, 12, 1.0).width;
            draw_text_ex(
                note,
                px + pw - nw - 20.0,
                ry + 38.0,
                TextParams {
                    font: f,
                    font_size: 12,
                    color: BAD,
                    ..Default::default()
                },
            );
        }
    }

    let footer_y = py + head_h + 4.0 * row_h + foot_h;
    draw_rectangle(
        px + 12.0,
        py + head_h + 4.0 * row_h + 4.0,
        pw - 24.0,
        1.0,
        OLIVE,
    );
    centered(
        "\u{2191}\u{2193} select  \u{2022}  Enter / 1-4 ascend  \u{2022}  Esc close",
        footer_y,
        15.0,
        TEXT_DIM,
        f,
    );
}

fn draw_research_modal(sim: &Sim, cursor: usize, sprites: &Sprites) {
    let (w, h) = (screen_width(), screen_height());
    // Dark full-screen overlay — time is frozen while this is up.
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 200));

    let pw = 560.0_f32.min(w - 40.0);
    // One row per tech + title bar + footer.
    let row_h = 30.0;
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
        // Highlight the cursor row.
        if i == cursor {
            draw_rectangle(
                px + 8.0,
                ry - 4.0,
                pw - 16.0,
                row_h - 2.0,
                with_alpha(GOLD, 0.16),
            );
            draw_rectangle_lines(px + 8.0, ry - 4.0, pw - 16.0, row_h - 2.0, 1.5, GOLD_HI);
        }

        // Number-key chip for the first ten techs (the rest use ↑/↓ + Enter).
        if i < 10 {
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
        }

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
        "\u{2191}\u{2193} select  \u{2022}  Enter / 1-0 research  \u{2022}  Esc close",
        footer_y,
        15.0,
        TEXT_DIM,
        f,
    );
}

#[allow(
    clippy::too_many_arguments,
    reason = "the single render entry point threads sim, view/particle layers, selection, camera and assets"
)]
fn draw(
    sim: &Sim,
    view: &view::ViewState,
    particles: &particles::Particles,
    selected: Option<EntityId>,
    build_mode: Option<BuildingKind>,
    cell: f32,
    alpha: f32,
    sx: f32,
    sy: f32,
    sprites: &Sprites,
) {
    clear_background(BASE_CHARCOAL);
    // The world layer is offset by the screen-shake (sx, sy); the HUD is not.
    let ox = board_origin_x(sim, cell) + sx;
    let wtop = WORLD_TOP + sy;
    draw_ground(sim, cell, ox, wtop);
    // Resource deposits sit on the ground, above the terrain but under pieces/fog.
    draw_deposits(sim, cell, ox, wtop);
    // Scorch decals sit on the ground, under terrain and pieces.
    particles.draw_scorches(ox, wtop, cell);
    draw_terrain(sim, cell, ox, wtop);
    for v in sim.views() {
        let team = if v.owner == HUMAN {
            TEAM_PLAYER
        } else {
            TEAM_ENEMY
        };
        let (texture, base_size, is_building) = match v.kind {
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
        // Smoothly interpolated transform + animated stats from the view layer,
        // falling back to the raw sim values if the entity isn't tracked yet.
        let (wx, wy, hp, max_hp, sh, max_sh, scale, flash) = view.entity(v.id, alpha).map_or_else(
            || {
                (
                    v.pos.x.to_bits() as f32 / 65536.0,
                    v.pos.y.to_bits() as f32 / 65536.0,
                    v.hp.to_bits() as f32 / 65536.0,
                    (v.max_hp.to_bits() as f32 / 65536.0).max(1.0),
                    v.shield.to_bits() as f32 / 65536.0,
                    v.max_shield.to_bits() as f32 / 65536.0,
                    1.0,
                    0.0,
                )
            },
            |e| {
                (
                    e.world.x,
                    e.world.y,
                    e.hp,
                    e.max_hp,
                    e.shield,
                    e.max_shield,
                    e.scale,
                    e.flash,
                )
            },
        );
        let x = ox + wx * cell;
        let y = wtop + wy * cell;
        draw_piece(x, y, base_size * scale, texture, team, is_building, flash);
        draw_health_bar(x, y, cell, hp, max_hp);
        draw_shield_bar(x, y, cell, sh, max_sh);
        if Some(v.id) == selected {
            // Pulsing double ring — a live holographic selection lock.
            let pulse = (get_time() as f32 * 3.0).sin() * 0.5 + 0.5;
            draw_circle_lines(x, y, base_size * 0.62, 2.0, SELECT_RING);
            draw_circle_lines(
                x,
                y,
                base_size * (0.66 + pulse * 0.08),
                1.5,
                with_alpha(SELECT_RING, 0.35 + pulse * 0.4),
            );
        }
        if v.stun_ticks > 0 {
            // EMP crackle: a flickering amber ring marks a stunned, silenced unit.
            let jitter = (get_time() as f32 * 17.0).sin() * 0.08;
            draw_circle_lines(x, y, base_size * (0.5 + jitter), 2.0, with_alpha(WARN, 0.8));
            draw_circle_lines(x, y, base_size * 0.34, 1.0, with_alpha(WARN, 0.5));
        }
    }
    draw_tracers(sim, cell, ox, wtop);
    // Particles (muzzle flashes, explosions, debris, warp-ins) over the pieces.
    particles.draw(sx, sy);
    // Floating damage numbers, rising and fading.
    let pf = sprites.font_bold();
    for (world, amount, t) in view.popups() {
        let s = format!("-{amount}");
        let tw = measure_text(&s, pf, 16, 1.0).width;
        let px = ox + world.x * cell - tw / 2.0;
        let py = wtop + world.y * cell - 0.6 * cell - t * 22.0;
        draw_text_ex(
            &s,
            px,
            py,
            TextParams {
                font: pf,
                font_size: 16,
                color: with_alpha(BAD, 1.0 - t),
                ..Default::default()
            },
        );
    }
    if let Some(kind) = build_mode {
        draw_build_grid(sim, cell, ox, wtop);
        draw_build_ghost(sim, kind, cell, ox, wtop);
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
        // Hologram: a slightly larger team-tinted glow copy behind a bright core,
        // so the silhouette reads as a projection rather than solid clip-art.
        let g = isz * 1.12;
        draw_texture_ex(
            tex,
            x - g / 2.0,
            y - g / 2.0,
            with_alpha(team, 0.5),
            DrawTextureParams {
                dest_size: Some(vec2(g, g)),
                ..DrawTextureParams::default()
            },
        );
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
fn draw_piece(
    x: f32,
    y: f32,
    size: f32,
    texture: Option<&Texture2D>,
    team: Color,
    building: bool,
    flash: f32,
) {
    let base = size * 0.5;
    contact_shadow(x, y, base);
    if building {
        let s = size * 0.86;
        // Soft holographic projection bloom around the structure.
        glow_rect(x - s / 2.0, y - s / 2.0, s, s, with_alpha(team, 0.28), 3);
        // Extruded team slab, lit top face, holo-rimmed (a map "plinth").
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
        if flash > 0.0 {
            draw_rectangle(
                x - s / 2.0,
                y - s / 2.0,
                s,
                s,
                with_alpha(WHITE, flash * 0.6),
            );
        }
    } else {
        let r = size * 0.58;
        draw_circle(x, y, r + 4.0, with_alpha(team, 0.14)); // holographic halo
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
        if flash > 0.0 {
            draw_circle(x, y, r, with_alpha(WHITE, flash * 0.6));
        }
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
fn draw_ground(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let cols = sim.map().width();
    let rows = sim.map().height();
    let (bw, bh) = board_size(sim, cell);
    draw_rectangle(ox, wtop, bw, bh, GROUND);
    // A diagonal band of hexes sweeps across the board over time, lit brighter —
    // a holographic graticule scan.
    let pulse = (get_time() * 4.0) as i32;
    for row in 0..rows {
        for col in 0..cols {
            let (cx, cy) = hex_center_px(col, row, cell, ox, wtop);
            draw_hex(cx, cy, cell, terrain_tone(col, row));
            if (col / 4 + row / 4).is_multiple_of(2) {
                draw_hex(cx, cy, cell, GROUND_MACRO);
            }
            let on_band = (i32::from(col) + i32::from(row) - pulse).rem_euclid(14) == 0;
            draw_hex_outline(cx, cy, cell, 1.0, if on_band { GRID_HOT } else { GRID });
        }
    }
    // Cool holographic center bloom lifting the lit center.
    draw_ellipse(
        ox + bw / 2.0,
        wtop + bh * 0.42,
        bw * 0.5,
        bh * 0.42,
        0.0,
        VARNISH,
    );
    // Edge vignette: concentric darkening frames, heaviest at the rim (cool void).
    for (i, alpha) in [80u8, 60, 45, 30].into_iter().enumerate() {
        let inset = i as f32 * cell;
        draw_rectangle_lines(
            ox + inset,
            wtop + inset,
            bw - inset * 2.0,
            bh - inset * 2.0,
            cell,
            Color::from_rgba(2, 5, 10, alpha),
        );
    }
    // Glowing holographic frame (cyan bevel) + soft outer bloom + corner ornaments.
    let board = Rect::new(ox, wtop, bw, bh);
    glow_rect(ox, wtop, bw, bh, HOLO_GLOW, 3);
    beveled_frame(board, 5.0, DECO_GOLD_HI, theme::GOLD_DK);
    draw_rectangle_lines(ox, wtop, bw, bh, 1.0, BRONZE);
    draw_rectangle_lines(
        ox + 8.0,
        wtop + 8.0,
        bw - 16.0,
        bh - 16.0,
        1.5,
        with_alpha(DECO_GOLD, 0.7),
    );
    corner_ornament(ox, wtop, 1.0, 1.0);
    corner_ornament(ox + bw, wtop, -1.0, 1.0);
    corner_ornament(ox, wtop + bh, 1.0, -1.0);
    corner_ornament(ox + bw, wtop + bh, -1.0, -1.0);
}

/// The hovered hex during building placement (mouse → cell), board centered.
fn mouse_hex(sim: &Sim, cell: f32) -> (u16, u16) {
    let (mx, my) = mouse_position();
    let ox = board_origin_x(sim, cell);
    let wx = Fixed::from_bits((((mx - ox) / cell) * 65536.0) as i64);
    let wy = Fixed::from_bits((((my - WORLD_TOP) / cell) * 65536.0) as i64);
    hex::from_world(SimVec2::new(wx, wy), sim.map().width(), sim.map().height())
}

/// Draws a small cluster of diamonds on each deposit tile so resource nodes read
/// as distinct map features: cyan (`GOLD`) for Ore, amber (`WARN`) for Alloy.
/// Placed after `draw_ground` so deposits sit on the ground under pieces and fog.
fn draw_deposits(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let r = cell * 0.16;
    for (x, y, dep) in sim.map().deposits() {
        let (cx, cy) = hex_center_px(x, y, cell, ox, wtop);
        let (fill, rim) = match dep.kind {
            DepositKind::Ore => (GOLD, with_alpha(GOLD_HI, 0.55)),
            DepositKind::Alloy => (WARN, with_alpha(WARN, 0.55)),
        };
        // Faint ring so the cluster reads as a resource node.
        draw_circle_lines(cx, cy, r * 2.6, 1.0, rim);
        // Cluster of 4 small diamonds offset from the center.
        for (dx, dy) in [(-r, 0.0_f32), (r, 0.0), (0.0, -r), (0.0, r)] {
            draw_poly(cx + dx, cy + dy, 4, r, 45.0, fill);
        }
    }
}

/// Faint hex outlines over buildable cells, shown while placing a building.
fn draw_build_grid(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let col = Color::from_rgba(255, 255, 255, 24);
    for row in 0..sim.map().height() {
        for tx in 0..sim.map().width() {
            if sim
                .map()
                .tile(i32::from(tx), i32::from(row))
                .is_some_and(|t| t.buildable)
            {
                let (cx, cy) = hex_center_px(tx, row, cell, ox, wtop);
                draw_hex_outline(cx, cy, cell, 1.0, col);
            }
        }
    }
}

/// Draws shot tracers for the most recent combat tick (combat juice): a wide
/// translucent cyan glow under a bright thin core, so lasers read as energy bolts.
fn draw_tracers(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    for &(from, to) in sim.recent_attacks() {
        let (fx, fy) = (
            ox + tile_to_px(from.x, cell),
            wtop + tile_to_px(from.y, cell),
        );
        let (tx, ty) = (ox + tile_to_px(to.x, cell), wtop + tile_to_px(to.y, cell));
        draw_line(fx, fy, tx, ty, 4.0, with_alpha(TRACER, 0.28));
        draw_line(fx, fy, tx, ty, 1.5, TRACER);
    }
}

/// Draws a translucent placement ghost on the moused hex: green if buildable and
/// affordable (and on a deposit for extractors), red otherwise.
/// For `Refinery` and `AntimatterPlant` (extractors), also outlines every deposit
/// tile in cyan so the player can see where extractors belong.
fn draw_build_ghost(sim: &Sim, kind: BuildingKind, cell: f32, ox: f32, wtop: f32) {
    let (col, row) = mouse_hex(sim, cell);
    let buildable = sim
        .map()
        .tile(i32::from(col), i32::from(row))
        .is_some_and(|t| t.buildable);
    let affordable = sim.minerals(HUMAN) >= sim.building_cost(kind);
    let is_extractor = matches!(kind, BuildingKind::Refinery | BuildingKind::AntimatterPlant);

    // For extractors: outline all deposit tiles in cyan so the player sees where to place.
    if is_extractor {
        for (dx, dy, _dep) in sim.map().deposits() {
            let (dcx, dcy) = hex_center_px(dx, dy, cell, ox, wtop);
            draw_hex_outline(dcx, dcy, cell, 2.0, GOLD);
        }
    }

    let on_deposit = is_extractor && sim.map().deposit(col, row).is_some();
    // Ghost is green when both buildable+affordable, and — for extractors — when
    // the moused tile has a deposit (so the player gets confirmation they're on-site).
    let good = buildable && affordable && (!is_extractor || on_deposit);
    let fill = if good {
        Color::from_rgba(80, 200, 120, 120)
    } else {
        Color::from_rgba(200, 80, 80, 120)
    };
    let (cx, cy) = hex_center_px(col, row, cell, ox, wtop);
    draw_hex(cx, cy, cell, fill);
    draw_hex_outline(cx, cy, cell, 2.0, if good { GOOD } else { BAD });
}

fn draw_terrain(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let map = sim.map();
    for row in 0..map.height() {
        for col in 0..map.width() {
            if map.tile(i32::from(col), i32::from(row)).unwrap().passable {
                continue;
            }
            let (cx, cy) = hex_center_px(col, row, cell, ox, wtop);
            draw_hex(cx, cy, cell, TERRAIN_WALL); // rampart body
            draw_hex(cx, cy - cell * 0.12, cell * 0.6, WALL_TOP); // raised lit peak
            draw_hex(cx, cy - cell * 0.2, cell * 0.28, WALL_HI); // bright cap
            draw_hex_outline(cx, cy, cell, 1.5, WALL_EDGE);
        }
    }
}

/// Health bar over a piece. Full-health pieces are left clean; once damaged a
/// framed gauge appears so it reads as a deliberate readout, not a stray sliver.
fn draw_health_bar(x: f32, y: f32, cell: f32, hp: f32, max_hp: f32) {
    let frac = (hp / max_hp).clamp(0.0, 1.0);
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

/// Cyan shield bar drawn directly above the HP bar. Only visible when the entity
/// has a non-zero shield max (i.e. the owner has researched at least Shield I).
fn draw_shield_bar(x: f32, y: f32, cell: f32, shield: f32, max_shield: f32) {
    if max_shield <= 0.0 {
        return;
    }
    let frac = (shield / max_shield).clamp(0.0, 1.0);
    let width = cell * 1.1;
    let left = x - width / 2.0;
    // Position 3 px above the HP bar track (HP bar top = y - cell * 0.82).
    let top = y - cell * 0.82 - 4.0;
    draw_rectangle(left - 1.0, top - 1.0, width + 2.0, 4.0, WALL_EDGE); // frame plate
    draw_rectangle(left, top, width, 2.0, HP_TRACK);
    draw_rectangle(left, top, width * frac, 2.0, SHIELD);
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
