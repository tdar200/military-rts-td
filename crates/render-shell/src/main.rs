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

mod alerts;
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
use rts_core::game::civ::{
    ColonyId, ColonyIntent, SectorDoctrine, AUTONOMY_FULL, AUTONOMY_HOLD_TICKS,
};
use rts_core::game::hex;
use rts_core::game::map::{DepositKind, TerrainKind};
use rts_core::game::perk;
use rts_core::game::planet::PlanetId;
use rts_core::game::scenario;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::game::tech_grid::{self, RealityClass};
use rts_core::game::tech_grid_table::GRID as TECH_GRID;
use rts_core::vec::Vec2 as SimVec2;
use sprites::Sprites;
// Explicit theme imports (not a glob) so they take precedence over the
// like-named macroquad prelude color constants (e.g. GOLD).
use theme::{
    civ_color, glow_rect, holo_flicker, hp_color, ALERT_GLOW, BAD, BASE_CHARCOAL, BORDER_NEUTRAL,
    BRONZE, CIV_NEUTRAL, DECO_GOLD, DECO_GOLD_HI, GOLD, GOLD_HI, GOOD, GRID, GRID_HOT, GROUND,
    GROUND_MACRO, HOLO_GLOW, HP_TRACK, INK, INK_DIM, OLIVE, PANEL, PANEL_RAISED, PARCHMENT,
    PARCHMENT_EDGE, PARCHMENT_HI, PARCHMENT_LO, PIECE_SHADOW, REGAL_BG, REGAL_BG_HI, REGAL_BG_LO,
    SELECT_RING, SHIELD, TEAM_ENEMY, TEAM_PLAYER, TERRAIN_BARREN, TERRAIN_FERTILE, TERRAIN_PLAINS,
    TERRAIN_RICH, TERRAIN_WALL, TEXT, TEXT_DIM, TRACER, VARNISH, WALL_EDGE, WALL_HI, WALL_TOP,
    WARN, WELL,
};

/// Fixed simulation timestep (30 Hz), decoupled from the render frame rate.
const TICK_DT: f32 = 1.0 / 30.0;
/// Sim-speed gears (the +/- keys step through these).
const GEARS: [u32; 4] = [1, 2, 4, 8];
/// Control-group digit keys (1..=9). Index `i` maps to group slot `i + 1`.
const DIGIT_KEYS: [KeyCode; 9] = [
    KeyCode::Key1,
    KeyCode::Key2,
    KeyCode::Key3,
    KeyCode::Key4,
    KeyCode::Key5,
    KeyCode::Key6,
    KeyCode::Key7,
    KeyCode::Key8,
    KeyCode::Key9,
];
/// Capability-grid era column headers (10 eras, 1990s → cosmic).
const GRID_ERAS: [&str; 10] = [
    "FND", "QNT", "RNW", "FUS", "SPC", "ST2", "GAL", "DRK", "HiD", "CSM",
];
/// Capability-grid branch row codes (10 branches).
const GRID_BRANCHES: [&str; 10] = ["C", "E", "M", "P", "W", "D", "B", "S", "X", "G"];
/// Full branch names for the research detail readout.
const GRID_BRANCH_NAMES: [&str; 10] = [
    "Compute",
    "Energy",
    "Materials",
    "Propulsion",
    "Weapons",
    "Defense",
    "Biotech",
    "Sensors",
    "Exotic",
    "Gravity",
];
// The six sector doctrines, in the order the governance overlay's number keys
// (1..=6) select them, with display names.
const SECTOR_DOCTRINES: [SectorDoctrine; 6] = [
    SectorDoctrine::Balanced,
    SectorDoctrine::Research,
    SectorDoctrine::Mining,
    SectorDoctrine::Fortress,
    SectorDoctrine::Shipyard,
    SectorDoctrine::Frontier,
];
const SECTOR_DOCTRINE_NAMES: [&str; 6] = [
    "Balanced", "Research", "Mining", "Fortress", "Shipyard", "Frontier",
];
const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);
/// The battlefield is drawn below the top bar.
const WORLD_TOP: f32 = ui::TOP_BAR_H;
/// Camera zoom bounds: `1.0` is the default fit-to-screen view.
const MIN_ZOOM: f32 = 0.6;
const MAX_ZOOM: f32 = 4.0;
/// Wheel-tick zoom step (per detent).
const ZOOM_STEP: f32 = 0.12;
/// Surviving this many waves earns the celebratory "BEACHHEAD SECURED" milestone.
/// The run keeps going — survival stays an endurance mode; this is the goal to
/// beat, not an ending.
const SURVIVAL_MILESTONE_WAVE: u32 = 5;

/// Top-level screen state.
#[derive(Clone, Copy, PartialEq)]
enum Phase {
    Title,
    Playing,
}

/// The player's current selection: a group of friendly units and/or one planet.
///
/// A click on a friendly unit selects just that unit; a box-drag selects every
/// friendly unit inside the rectangle; a click on open planet ground selects the
/// planet (clearing the unit group). Right-click issues group move / assault
/// orders for the selected units.
#[derive(Default)]
pub struct Selection {
    pub units: Vec<EntityId>,
    pub planet: Option<PlanetId>,
}

fn window_conf() -> Conf {
    Conf {
        window_title: "Ascension".to_owned(),
        window_width: 1024,
        window_height: 768,
        high_dpi: true,
        ..Conf::default()
    }
}

/// A fresh, run-varying seed for a Survival match (derived from the wall clock).
/// Survival runs aren't replayed or networked, so a non-deterministic seed is
/// fine — each run stays fully deterministic *given* its seed, and every run gets
/// a different procedural map.
fn survival_seed() -> u64 {
    (get_time() * 1000.0) as u64 ^ 0xA5A5_5A5A_C3C3_3C3C
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

/// Camera = (`zoom`, `cam` world-space center). Returns the effective per-unit
/// scale `cell` and the world→screen base offsets `(ox, wtop_base)` such that
/// `screen = (ox + world.x * cell, wtop_base + world.y * cell)`. `cam` is mapped
/// to the center of the playfield viewport (between the top + command bars), so
/// at `zoom == 1` and `cam == board center` this reproduces the default framing.
/// Screen-shake is applied by callers on top of `(ox, wtop_base)`.
fn camera_transform(sim: &Sim, zoom: f32, cam: (f32, f32)) -> (f32, f32, f32) {
    let cell = cell_size(sim) * zoom;
    let (vcx, vcy) = viewport_center();
    let ox = vcx - cam.0 * cell;
    let wtop_base = vcy - cam.1 * cell;
    (cell, ox, wtop_base)
}

/// Center of the playfield viewport: full window width, vertically between the
/// top bar and the command bar.
fn viewport_center() -> (f32, f32) {
    let vcx = screen_width() / 2.0;
    let vcy = WORLD_TOP + (screen_height() - ui::CMD_BAR_H - WORLD_TOP) / 2.0;
    (vcx, vcy)
}

/// The default camera target (world units), chosen so that at `zoom == 1` the
/// transform reproduces today's framing *exactly*: it inverts [`camera_transform`]
/// against the legacy offsets `ox = board_origin_x` and `wtop = WORLD_TOP`. Using
/// the inverse (rather than a nominal board center) guarantees the default view is
/// pixel-identical regardless of whether the fit is width- or height-constrained.
fn default_cam(sim: &Sim) -> (f32, f32) {
    let cell = cell_size(sim);
    let (vcx, vcy) = viewport_center();
    let ox = board_origin_x(sim, cell);
    ((vcx - ox) / cell, (vcy - WORLD_TOP) / cell)
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
    let mut sim = scenario::survival(survival_seed());
    let mut selected = Selection::default();
    // Under-attack alert tracker (anti-blindside): diffs HUMAN entity HP each
    // frame, coalesces battles into pulsing markers, and drives the jump key.
    let mut alerts = alerts::Alerts::default();
    // Control groups 1..=9 (index 0 unused). Recall sets the selection to a slot's
    // living members; Ctrl+digit assigns; Shift+digit appends; a double-tap also
    // centers the camera on the group's centroid. Purely shell-side selection.
    let mut groups: [Vec<EntityId>; 10] = Default::default();
    // Wall-clock of the last bare press per slot, for ~300 ms double-tap detection.
    let mut group_last_press: [f64; 10] = [0.0; 10];
    // Screen-space anchor of an in-progress left-drag box-select (None = not dragging).
    let mut drag_start: Option<(f32, f32)> = None;
    let mut build_mode: Option<BuildingKind> = None;
    // Attack-move mode: armed by `A`, consumed by the next left/right map click.
    let mut attack_move_armed = false;
    let mut pending = Vec::new();
    let mut accumulator = 0.0_f32;
    let mut paused = false;
    // Sim speed multiplier (gears 1/2/4/8×): Civ-pace games need a fast-forward for the
    // quiet stretches. `-` slows, `=`/`+` speeds up; determinism is untouched
    // (the same ticks run, just more per wall-clock second).
    let mut game_speed: u32 = 1;
    let mut research_open = false;
    let mut research_cursor: usize = 0;
    let mut doctrine_open = false;
    let mut doctrine_cursor: usize = 0;
    // Read-only viewer for the 500-slot Ascension capability grid (toggle: G).
    let mut grid_open = false;
    // Sector governance overlay (toggle: K) — assign colonies a doctrine.
    let mut sector_open = false;
    let mut sector_cursor: usize = 0;
    let mut phase = Phase::Title;
    // Shell-side animated view layer (interpolation, bars, FX events) + particle
    // pool. Pure view state — never feeds back into the deterministic sim.
    let mut view = view::ViewState::default();
    let mut particles = particles::Particles::new();
    let mut camera = anim::Camera::default();
    // Player camera (independent of the screen-shake `camera`): mouse-wheel zoom +
    // middle-drag pan. `zoom == 1` and `cam == default_cam` reproduce today's view.
    // `cam` is the world-space point pinned to the playfield viewport center.
    // Lazily initialized once the first sim exists (needs the map dimensions).
    let mut zoom: f32 = 1.0;
    let mut cam: Option<(f32, f32)> = None;
    // Last mouse position, for computing middle-drag pan deltas.
    let mut last_mouse: (f32, f32) = mouse_position();
    // Hit-stop: while > 0 the sim is frozen (in wall-clock) for impact emphasis.
    let mut hitstop = 0.0_f32;
    // Audio bookkeeping: one-shot game-over jingle + wave-incoming alarm edges.
    let mut over_announced = false;
    let mut prev_wave_secs: i64 = i64::MAX;
    // Commanded-time auto-pause: freeze + banner on a key event so the player is
    // never ambushed mid-menu and never misses a beat. Edge-detected, fires once.
    let mut auto_pause_msg: Option<(&'static str, f32)> = None;
    let mut prev_era: u8 = 0;
    let mut prev_researching = false;
    // Whether the current match is a survival run (drives the score HUD + summary).
    let mut survival_run = true;
    // Title-screen mode selection: false = Survival, true = Conquest (N-civ
    // planetary war with growing cities). Toggled with Left/Right on the title.
    // Default to Conquest — it's the main game (planets, cities, interplanetary
    // war); Survival is the legacy siege mode.
    let mut selected_conquest = true;
    // Survival perk draft: a modal opens each new wave until all perks are taken.
    let mut perk_open = false;
    let mut prev_waves = 0_u32;
    let mut best_waves = meta::best_waves();
    // Seconds left on the transient "BEACHHEAD SECURED" milestone banner.
    let mut milestone_flash: f32 = 0.0;

    loop {
        if phase == Phase::Title {
            // Two modes: Survival (procedural siege) and Conquest (N-civ
            // planetary war with growing cities). Left/Right/Tab switches the
            // selection; Enter/Space/click begins the selected mode.
            if is_key_pressed(KeyCode::Left)
                || is_key_pressed(KeyCode::Right)
                || is_key_pressed(KeyCode::Tab)
            {
                selected_conquest = !selected_conquest;
            }
            let start = is_key_pressed(KeyCode::Enter)
                || is_key_pressed(KeyCode::Space)
                || is_mouse_button_pressed(MouseButton::Left);
            if start {
                survival_run = !selected_conquest;
                phase = Phase::Playing;
                sim = if selected_conquest {
                    scenario::conquest(survival_seed(), 4)
                } else {
                    scenario::survival(survival_seed())
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
                auto_pause_msg = None;
                prev_era = 0;
                prev_researching = false;
                audio.set_music(audio::Music::Combat);
                selected = Selection::default();
                alerts.clear();
                for g in &mut groups {
                    g.clear();
                }
                group_last_press = [0.0; 10];
                drag_start = None;
                build_mode = None;
                attack_move_armed = false;
                pending.clear();
                accumulator = 0.0;
                research_open = false;
                doctrine_open = false;
                grid_open = false;
                // Reset the player camera for the fresh match (re-centers on map).
                zoom = 1.0;
                cam = None;
            }
            draw_title(&sprites, selected_conquest);
            next_frame().await;
            continue;
        }

        let over = sim.winner().is_some();
        // Lazily anchor the camera on the current map (default == today's view).
        let cam_center = *cam.get_or_insert_with(|| default_cam(&sim));
        // --- Player camera input: wheel-zoom (to cursor) + middle-drag pan ---
        // Gated to map interaction: not over the UI, not in a modal, while Playing.
        let (mx, my) = mouse_position();
        let cam_input_ok = !over
            && !ui::pointer_over_ui()
            && !research_open
            && !perk_open
            && !doctrine_open
            && !sector_open;
        if cam_input_ok {
            let (vcx, vcy) = viewport_center();
            // Zoom toward the cursor: keep the world point under the cursor fixed.
            let (_, wheel_y) = mouse_wheel();
            if wheel_y != 0.0 {
                let (cell_pre, ox_pre, wtop_pre) = camera_transform(&sim, zoom, cam_center);
                let wpx = (mx - ox_pre) / cell_pre;
                let wpy = (my - wtop_pre) / cell_pre;
                zoom = (zoom * (1.0 + wheel_y.signum() * ZOOM_STEP)).clamp(MIN_ZOOM, MAX_ZOOM);
                let cell_post = cell_size(&sim) * zoom;
                cam = Some((wpx - (mx - vcx) / cell_post, wpy - (my - vcy) / cell_post));
            }
            // Pan: hold the middle button and drag (left=select / right=order are
            // untouched). Move `cam` by the inverse of the mouse delta in world units.
            if is_mouse_button_down(MouseButton::Middle) {
                let (cell_now, _, _) = camera_transform(&sim, zoom, cam.unwrap_or(cam_center));
                let c = cam.unwrap_or(cam_center);
                cam = Some((
                    c.0 - (mx - last_mouse.0) / cell_now,
                    c.1 - (my - last_mouse.1) / cell_now,
                ));
            }
            // Reset to the default view (Home).
            if is_key_pressed(KeyCode::Home) {
                zoom = 1.0;
                cam = Some(default_cam(&sim));
            }
        }
        last_mouse = (mx, my);
        // Clamp the camera so the board can't be panned entirely off-screen (loose).
        let world_w = 0.75 * f32::from(sim.map().width());
        let world_h = f32::from(sim.map().height());
        if let Some(c) = cam.as_mut() {
            c.0 = c.0.clamp(0.0, world_w);
            c.1 = c.1.clamp(0.0, world_h);
        }
        // Final camera transform for THIS frame — the single source of truth shared
        // by both drawing and input, so clicks stay correct at any zoom/pan.
        let (cell, ox_cam, wtop_cam) = camera_transform(&sim, zoom, cam.unwrap_or(cam_center));

        // --- Alert-jump key (backtick `): snap the camera to the most-recent
        // under-attack alert; repeated presses cycle active alerts newest-first.
        // Gated only on having a live camera + not over (no overlay needed; it's a
        // pure camera move and shares no key with build/train/overlay toggles).
        if !over && is_key_pressed(KeyCode::GraveAccent) {
            if let Some(target) = alerts.cycle_jump_target() {
                cam = Some(target);
            }
        }

        // --- Control groups (1..=9): only when NO overlay/modal is open and not in
        // the founding survey, so the digit keys can't collide with the perk draft
        // (1..4), the doctrine modal (1..4), or the sector governance overlay (1..6).
        let groups_input_ok = !over
            && !sim.surveying()
            && !research_open
            && !perk_open
            && !doctrine_open
            && !sector_open
            && !grid_open;
        if groups_input_ok {
            let ctrl = is_key_down(KeyCode::LeftControl) || is_key_down(KeyCode::RightControl);
            let shift = is_key_down(KeyCode::LeftShift) || is_key_down(KeyCode::RightShift);
            for (i, &key) in DIGIT_KEYS.iter().enumerate() {
                if !is_key_pressed(key) {
                    continue;
                }
                let slot = i + 1; // groups[1..=9]
                if ctrl {
                    // Assign the current unit selection to this slot (copy).
                    groups[slot].clone_from(&selected.units);
                } else if shift {
                    // Append the current selection, deduped.
                    for &id in &selected.units {
                        if !groups[slot].contains(&id) {
                            groups[slot].push(id);
                        }
                    }
                } else {
                    // Recall: select this slot's living members, dropping the planet.
                    groups[slot].retain(|&id| sim.entity_alive(id));
                    selected.units.clone_from(&groups[slot]);
                    selected.planet = None;
                    // Double-tap (<=300 ms) also centers the camera on the centroid.
                    let now = get_time();
                    if now - group_last_press[slot] <= 0.3 && !groups[slot].is_empty() {
                        let views = sim.views();
                        let mut sum = (0.0_f32, 0.0_f32);
                        let mut n = 0.0_f32;
                        for &id in &groups[slot] {
                            if let Some(v) = views.iter().find(|v| v.id == id) {
                                sum.0 += v.pos.x.to_bits() as f32 / 65536.0;
                                sum.1 += v.pos.y.to_bits() as f32 / 65536.0;
                                n += 1.0;
                            }
                        }
                        if n > 0.0 {
                            cam = Some((sum.0 / n, sum.1 / n));
                        }
                    }
                    group_last_press[slot] = now;
                }
            }
        }

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
            // Reject clicks in the letterbox margins: cursor_tile clamps off-board
            // points onto an edge tile, so check the raw world position is in bounds.
            let (mx, my) = mouse_position();
            let wx = (mx - ox_cam) / cell;
            let wy = (my - wtop_cam) / cell;
            let on_board = wx >= 0.0
                && wy >= 0.0
                && wx < f32::from(sim.map().width())
                && wy < f32::from(sim.map().height());
            if on_board && is_mouse_button_pressed(MouseButton::Left) && !ui::pointer_over_ui() {
                let (col, row) = input::cursor_tile(&sim, cell, (ox_cam, wtop_cam));
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
        } else if !research_open && !perk_open && !doctrine_open && !sector_open {
            // Input: UI command bar first, then map (suppressed while over the UI
            // or a modal).
            if is_mouse_button_pressed(MouseButton::Left) && ui::pointer_over_ui() {
                audio.play(audio::Sfx::UiClick);
            }
            pending.extend(ui::handle_click(&sim, &mut build_mode));
            pending.extend(input::gather_commands(
                &sim,
                &mut selected,
                &mut drag_start,
                &mut build_mode,
                &mut attack_move_armed,
                ui::pointer_over_ui(),
                cell,
                (ox_cam, wtop_cam),
            ));
        }
        // Survey allows only founding — pause/speed/modals are suppressed until
        // the base exists.
        if !surveying && !research_open && !doctrine_open && is_key_pressed(KeyCode::Space) {
            paused = !paused;
        }
        // Speed gears (GEARS): fast-forward the long peaceful build stretches.
        if !surveying && is_key_pressed(KeyCode::Equal) {
            let i = GEARS.iter().position(|&g| g == game_speed).unwrap_or(0);
            game_speed = GEARS[(i + 1).min(GEARS.len() - 1)];
        }
        if !surveying && is_key_pressed(KeyCode::Minus) {
            let i = GEARS.iter().position(|&g| g == game_speed).unwrap_or(0);
            game_speed = GEARS[i.saturating_sub(1)];
        }
        // Colony autonomy: ] delegates more (the colony self-runs via the AI
        // brain), [ takes back control. Affects the founded colony (id 0).
        if !surveying && !over && !sector_open {
            let delta: i32 = if is_key_pressed(KeyCode::RightBracket) {
                1
            } else if is_key_pressed(KeyCode::LeftBracket) {
                -1
            } else {
                0
            };
            if delta != 0 {
                if let Some(c) = sim.colony(ColonyId(0)) {
                    let lvl = (i32::from(c.autonomy_level) + delta).clamp(0, 9);
                    pending.push(Command::SetColonyAutonomy {
                        owner: HUMAN,
                        colony: ColonyId(0),
                        level: u8::try_from(lvl).unwrap_or(0),
                    });
                }
            }
        }
        // Toggle research modal with Y (only while playing, not paused/surveying).
        if !over
            && !paused
            && !surveying
            && !doctrine_open
            && !sector_open
            && is_key_pressed(KeyCode::Y)
        {
            research_open = !research_open;
        }
        // Toggle the Ascendancy Doctrines modal with U (Upgrades). Mutually
        // exclusive with research; unlike research it does NOT freeze time, so the
        // surplus can be spent on the fly and several levels bought in a row.
        if !over
            && !paused
            && !surveying
            && !research_open
            && !perk_open
            && !sector_open
            && is_key_pressed(KeyCode::U)
        {
            doctrine_open = !doctrine_open;
        }
        // Toggle the read-only capability-grid viewer with G.
        if !over
            && !paused
            && !surveying
            && !research_open
            && !doctrine_open
            && !perk_open
            && !sector_open
            && is_key_pressed(KeyCode::G)
        {
            grid_open = !grid_open;
        }
        if grid_open && is_key_pressed(KeyCode::Escape) {
            grid_open = false;
        }
        // Toggle the sector governance overlay with K (only while playing). It
        // freezes nothing; the player assigns colonies a doctrine on the fly.
        if !over
            && !paused
            && !surveying
            && !research_open
            && !doctrine_open
            && !perk_open
            && !grid_open
            && is_key_pressed(KeyCode::K)
        {
            sector_open = !sector_open;
        }
        if sector_open {
            // The human's living colonies, in id order, are the cursor targets.
            let cols: Vec<ColonyId> = (0..sim.colonies_len())
                .map(|i| ColonyId(u32::try_from(i).unwrap_or(0)))
                .filter(|&id| sim.colony(id).is_some_and(|c| c.owner == HUMAN))
                .collect();
            if !cols.is_empty() {
                if is_key_pressed(KeyCode::Down) {
                    sector_cursor = (sector_cursor + 1) % cols.len();
                }
                if is_key_pressed(KeyCode::Up) {
                    sector_cursor = (sector_cursor + cols.len() - 1) % cols.len();
                }
                let colony = cols[sector_cursor.min(cols.len() - 1)];
                // 1..=6 govern the selected colony with that doctrine (1 = Balanced).
                let keys = [
                    KeyCode::Key1,
                    KeyCode::Key2,
                    KeyCode::Key3,
                    KeyCode::Key4,
                    KeyCode::Key5,
                    KeyCode::Key6,
                ];
                for (i, key) in keys.into_iter().enumerate() {
                    if is_key_pressed(key) {
                        pending.push(Command::GovernColony {
                            owner: HUMAN,
                            colony,
                            doctrine: SECTOR_DOCTRINES[i],
                        });
                    }
                }
                // ←/→ adjust the selected colony's requested autonomy, so
                // the overlay manages every colony, not just colony 0.
                let adelta: i32 = if is_key_pressed(KeyCode::Right) {
                    1
                } else if is_key_pressed(KeyCode::Left) {
                    -1
                } else {
                    0
                };
                if adelta != 0 {
                    if let Some(c) = sim.colony(colony) {
                        let lvl = (i32::from(c.autonomy_level) + adelta).clamp(0, 9);
                        pending.push(Command::SetColonyAutonomy {
                            owner: HUMAN,
                            colony,
                            level: u8::try_from(lvl).unwrap_or(0),
                        });
                    }
                }
            }
            if is_key_pressed(KeyCode::Escape) {
                sector_open = false;
            }
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
        // Research grid: ←/→ move the cursor by era, ↑/↓ by branch, [ ] by step;
        // Enter researches the highlighted node, or click a pip directly. Escape
        // closes. The core validates prereqs/lab/affordability, so a bad pick is a
        // harmless no-op. The cursor is a grid id (era*50 + branch*5 + step).
        if research_open {
            let (mut era, mut branch, mut step) = (
                research_cursor as u32 / 50,
                (research_cursor as u32 / 5) % 10,
                research_cursor as u32 % 5,
            );
            if is_key_pressed(KeyCode::Left) {
                era = (era + 9) % 10;
            }
            if is_key_pressed(KeyCode::Right) {
                era = (era + 1) % 10;
            }
            if is_key_pressed(KeyCode::Up) {
                branch = (branch + 9) % 10;
            }
            if is_key_pressed(KeyCode::Down) {
                branch = (branch + 1) % 10;
            }
            if is_key_pressed(KeyCode::LeftBracket) {
                step = (step + 4) % 5;
            }
            if is_key_pressed(KeyCode::RightBracket) {
                step = (step + 1) % 5;
            }
            research_cursor = (era * 50 + branch * 5 + step) as usize;

            let mut chosen: Option<u32> =
                is_key_pressed(KeyCode::Enter).then_some(research_cursor as u32);
            if is_mouse_button_pressed(MouseButton::Left) {
                let (mx, my) = mouse_position();
                if let Some(id) = grid_pip_at(&grid_layout(), mx, my) {
                    research_cursor = id as usize;
                    chosen = Some(id);
                }
            }
            if let Some(tech_id) = chosen {
                if sim.research_state(HUMAN).1.is_none() {
                    pending.push(Command::Research {
                        owner: HUMAN,
                        tech_id,
                    });
                }
                // Keep the grid open so the player can queue the next pick / browse.
            }
            if is_key_pressed(KeyCode::Escape) {
                research_open = false;
            }
        }
        if over && is_key_pressed(KeyCode::R) {
            // Restart the current mode on a fresh procedural map.
            sim = if survival_run {
                scenario::survival(survival_seed())
            } else {
                scenario::conquest(survival_seed(), 4)
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
            auto_pause_msg = None;
            prev_era = 0;
            prev_researching = false;
            audio.set_music(audio::Music::Combat);
            selected = Selection::default();
            alerts.clear();
            for g in &mut groups {
                g.clear();
            }
            group_last_press = [0.0; 10];
            drag_start = None;
            build_mode = None;
            attack_move_armed = false;
            pending.clear();
            accumulator = 0.0;
            research_open = false;
            doctrine_open = false;
        }
        // Return to the map-select screen.
        if over && is_key_pressed(KeyCode::M) {
            phase = Phase::Title;
            audio.set_music(audio::Music::Menu);
            selected = Selection::default();
            drag_start = None;
            build_mode = None;
            attack_move_armed = false;
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
            if survival_run {
                // Survival: keep the build-up peaceful — the alien beachhead AI
                // only acts once the first wave has spawned.
                if sim.waves_survived() > 0 {
                    commands.extend(sim.ai_commands(ENEMY));
                }
            } else {
                // Conquest: drive every living non-human civ's empire AI.
                for id in 1..sim.civ_count() {
                    let civ = PlayerId(id as u16);
                    if sim.civ_alive(civ) {
                        commands.extend(sim.ai_commands(civ));
                    }
                }
            }
            // Sectors govern first: each pushes its doctrine onto member colonies
            // (empty until the player forms sectors). Then colonies execute their
            // resulting policy (empty while every colony is at manual autonomy 0).
            commands.extend(sim.sector_commands());
            commands.extend(sim.colony_commands());
            sim.step(&commands);
            view.on_tick(&sim);
            accumulator -= TICK_DT;
        }
        // Drop selected units whose entity died: slots are recycled, so a stale id
        // could otherwise issue Move/UseAbility through a different unit that
        // reused it. Keep only living, still-friendly entities.
        if !selected.units.is_empty() {
            let views = sim.views();
            selected
                .units
                .retain(|&id| views.iter().any(|v| v.id == id && v.owner == HUMAN));
        }
        // Under-attack alerts: diff HUMAN HP vs. last frame, coalesce into markers,
        // and blip (throttled) when a genuinely new battle appears. Read-only.
        if !over && alerts.update(&sim) {
            audio.play_throttled(audio::Sfx::WaveIncoming, 1.5);
        }
        view.frame(dt);
        // Turn this frame's FX events into particles, then advance the pool. Spawn
        // at the shared camera transform (no shake, matching the legacy framing) so
        // explosions/spawns/muzzle flashes land on-piece at any zoom/pan.
        let ofx = ox_cam;
        for ev in view.events.drain(..) {
            match ev {
                view::FxEvent::Death {
                    world,
                    building,
                    human,
                } => {
                    let p = vec2(ofx + world.x * cell, wtop_cam + world.y * cell);
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
                    let p = vec2(ofx + world.x * cell, wtop_cam + world.y * cell);
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
                    let p = vec2(ofx + world.x * cell, wtop_cam + world.y * cell);
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
                wtop_cam + tile_to_px(from.y, cell),
            );
            particles.muzzle(f, TRACER);
        }
        if !sim.recent_attacks().is_empty() {
            audio.play_throttled(audio::Sfx::Laser, 0.05);
        }
        particles.update(dt);
        camera.update(dt);

        // Wave-incoming alarm + auto-pause: a siege telegraphs at 30 s out.
        let wave_secs = sim
            .ticks_until_next_wave()
            .map_or(i64::MAX, |t| (t / 30) as i64);
        if prev_wave_secs > 5 && wave_secs <= 5 {
            audio.play(audio::Sfx::WaveIncoming);
        }
        // Commanded-time auto-pause edges (skip while a modal already holds time):
        // siege warning (30 s out), an era advance, and research completing.
        // Survival-only: the commanded-time auto-pause (never be ambushed
        // mid-menu). Conquest is real-time grand strategy — auto-pausing on every
        // AI research/era event would be maddening, so it's suppressed there.
        if survival_run && !over && !paused && !research_open && !doctrine_open && !perk_open {
            let era = sim.player_era(HUMAN);
            let researching = sim.research_state(HUMAN).1.is_some();
            let mut event: Option<&'static str> = None;
            if prev_wave_secs > 30 && wave_secs <= 30 {
                event = Some("ASSAULT INBOUND  \u{2014}  from the east");
            } else if era > prev_era {
                event = Some("NEW ERA REACHED");
            } else if prev_researching && !researching {
                event = Some("RESEARCH COMPLETE");
            }
            if let Some(msg) = event {
                paused = true;
                auto_pause_msg = Some((msg, 4.0));
            }
            prev_era = era;
            prev_researching = researching;
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
            &sim, &view, &particles, &selected, drag_start, build_mode, cell, ox_cam, wtop_cam,
            alpha, sx, sy, &sprites,
        );
        if surveying {
            draw_survey_overlay(&sim, cell, ox_cam, wtop_cam, &sprites);
        }
        // Under-attack alerts on the main view: on-screen rings + off-screen edge
        // arrows pointing toward the battle. Drawn over the world, under the HUD.
        draw_alert_overlay(&alerts.active, cell, ox_cam, wtop_cam);
        // Attack-move armed: a banner + cursor reticle telling the player the next
        // click issues an attack-move (mirrors how build_mode shows a ghost).
        if attack_move_armed {
            draw_attack_move_banner(&sprites);
        }
        // The selection panel shows a single unit's stats; with exactly one unit
        // selected, behave as before. A planet selection drives Task 4's panel.
        let panel_unit = (selected.units.len() == 1).then(|| selected.units[0]);
        ui::draw(
            &sim,
            build_mode,
            paused,
            game_speed,
            panel_unit,
            &alerts.active,
            &sprites,
        );
        // Planet/city info + action panel (bottom-left), only while a planet is
        // selected. A planet selection clears the unit group, so this never
        // collides with the single-unit selection panel.
        if let Some(pid) = selected.planet {
            ui::draw_planet_panel(&sim, pid, &sprites);
        }
        // Colony autonomy readout (the player's delegation dial) — shows the
        // effective/requested level, *why* it sits there (the binding constraint),
        // and, while still earning, progress toward the next level.
        if !surveying {
            if let Some(c) = sim.colony(ColonyId(0)) {
                let eff = c.effective_autonomy();
                let requested = c.autonomy_level;
                let earned = c.earned_autonomy();
                let frozen = matches!(c.directive, ColonyIntent::Hold | ColonyIntent::Evacuate);
                let s = format!("COLONY AUTONOMY  {eff}/{requested}   [ / ] delegate");
                let col = if eff == 0 { TEXT_DIM } else { GOLD_HI };
                draw_text_ex(
                    &s,
                    14.0,
                    ui::TOP_BAR_H + 18.0,
                    TextParams {
                        font: sprites.font(),
                        font_size: 14,
                        color: col,
                        ..Default::default()
                    },
                );
                // The binding constraint on the effective level — actionable, not a
                // raw number (coherence rule R4).
                let earning = !frozen && earned < requested && earned < AUTONOMY_FULL;
                let (why, why_col) = if frozen {
                    (
                        "\u{2022} frozen by Hold/Evacuate directive".to_owned(),
                        WARN,
                    )
                } else if eff >= AUTONOMY_FULL {
                    ("\u{2022} fully autonomous".to_owned(), GOOD)
                } else if earning {
                    let into = c.autonomy_progress % AUTONOMY_HOLD_TICKS;
                    (
                        format!(
                            "\u{2022} earning L{}: {into}/{AUTONOMY_HOLD_TICKS}",
                            earned + 1
                        ),
                        TEXT_DIM,
                    )
                } else {
                    (
                        format!("\u{2022} running at requested L{requested}"),
                        TEXT_DIM,
                    )
                };
                let wy = ui::TOP_BAR_H + 34.0;
                draw_text_ex(
                    &why,
                    14.0,
                    wy,
                    TextParams {
                        font: sprites.font(),
                        font_size: 12,
                        color: why_col,
                        ..Default::default()
                    },
                );
                if earning {
                    let into = c.autonomy_progress % AUTONOMY_HOLD_TICKS;
                    let frac = into as f32 / AUTONOMY_HOLD_TICKS as f32;
                    let (bx, by, bw, bh) = (14.0, wy + 6.0, 150.0, 4.0);
                    draw_rectangle(bx, by, bw, bh, with_alpha(GOLD, 0.18));
                    draw_rectangle(bx, by, bw * frac, bh, GOLD_HI);
                }
            }
        }
        if survival_run && !surveying {
            draw_survival_hud(&sim, &sprites);
            if milestone_flash > 0.0 {
                milestone_flash -= get_frame_time();
                draw_milestone_banner(milestone_flash, &sprites);
            }
        }
        // Auto-pause banner: what froze the game, and how to resume.
        if let Some((msg, t)) = auto_pause_msg.as_mut() {
            *t -= get_frame_time();
            if *t <= 0.0 || !paused {
                auto_pause_msg = None;
            } else {
                draw_auto_pause_banner(msg, &sprites);
            }
        }
        if research_open {
            draw_research_modal(&sim, research_cursor, &sprites);
        }
        if doctrine_open {
            draw_doctrine_modal(&sim, doctrine_cursor, &sprites);
        }
        if grid_open {
            draw_grid_viewer(&sprites);
        }
        if sector_open {
            draw_sector_modal(&sim, sector_cursor, &sprites);
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

/// A compact horizontal color legend (swatch + label pairs), centered at `y`.
/// Used by the capability-grid overlays so players can decode the pip colours.
/// Each entry's swatch reuses the exact colour the cells draw with.
fn color_legend(entries: &[(Color, &str)], y: f32, font: Option<&Font>) {
    const SW: f32 = 11.0;
    const PAD: f32 = 6.0;
    const GAP: f32 = 18.0;
    let fs = 13u16;
    // Total width to center the whole row.
    let total: f32 = entries
        .iter()
        .map(|(_, label)| SW + PAD + measure_text(label, font, fs, 1.0).width + GAP)
        .sum::<f32>()
        - GAP;
    let mut x = (screen_width() - total) / 2.0;
    for (col, label) in entries {
        draw_rectangle(x, y - SW + 1.0, SW, SW, *col);
        draw_rectangle_lines(x, y - SW + 1.0, SW, SW, 1.0, BORDER_NEUTRAL);
        let lx = x + SW + PAD;
        draw_text_ex(
            label,
            lx,
            y,
            TextParams {
                font,
                font_size: fs,
                color: TEXT_DIM,
                ..Default::default()
            },
        );
        x = lx + measure_text(label, font, fs, 1.0).width + GAP;
    }
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

fn draw_title(sprites: &Sprites, conquest: bool) {
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
        "ASCENSION",
        c.y - 80.0,
        62.0,
        with_alpha(DECO_GOLD_HI, holo_flicker()),
        sprites.font_regal(),
    );
    deco_rule(cx, c.y - 46.0, 180.0);

    // --- parchment cartouche ---
    draw_cartouche(c);
    let (mode_name, mode_desc, mode_line) = if conquest {
        (
            "CONQUEST",
            "Settle planets, grow cities, conquer the star system.",
            "Up to 6 civilizations vie for planets; cities grow and mature.".to_string(),
        )
    } else {
        (
            "SURVIVAL",
            "Survey a world, found your colony, hold the line.",
            format!(
                "Hold {SURVIVAL_MILESTONE_WAVE} escalating sieges on an ever-changing procedural front."
            ),
        )
    };
    centered(mode_name, c.y + 30.0, 24.0, INK, sprites.font_regal());
    centered(mode_desc, c.y + 52.0, 13.0, INK_DIM, sprites.font());
    centered(
        &mode_line,
        c.y + c.h - 16.0,
        13.0,
        with_alpha(INK, 0.8),
        sprites.font(),
    );

    centered(
        "PRESS ENTER OR CLICK TO BEGIN",
        c.y + c.h + 40.0,
        19.0,
        with_alpha(GOLD_HI, holo_flicker()),
        sprites.font_bold(),
    );
    centered(
        "Y tech tree  \u{2022}  U doctrines  \u{2022}  K sectors  \u{2022}  Q ability  \u{2022}  G grid  \u{2022}  Space pause  \u{2022}  +/- speed (to 8\u{00d7})",
        c.y + c.h + 70.0,
        13.0,
        INK_DIM,
        sprites.font(),
    );
    centered(
        "1-9 control groups (Ctrl set, Shift add, double-tap recenter)  \u{2022}  ` jump to attack",
        c.y + c.h + 92.0,
        13.0,
        INK_DIM,
        sprites.font(),
    );
    centered(
        "Left / Right or Tab  \u{2022}  switch mode",
        c.y + c.h + 116.0,
        12.0,
        with_alpha(GOLD_HI, 0.75),
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
        "Press R to restart",
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
fn draw_survey_overlay(sim: &Sim, cell: f32, ox: f32, wtop: f32, sprites: &Sprites) {
    let map = sim.map();
    let (cur_c, cur_r) = input::cursor_tile(sim, cell, (ox, wtop));
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
                // Match the core's true hex adjacency (apply_found_base) so the
                // green tint marks exactly the tiles that pay the founding bonus.
                matches!(d.kind, rts_core::game::map::DepositKind::Ore)
                    && hex::distance((col, row), (dx, dy)) <= 1
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

/// Attack-move affordance: a centered banner plus a reticle at the cursor, so it
/// is unmistakable that the next click issues an attack-move (`StarCraft` `A`-move).
fn draw_attack_move_banner(sprites: &Sprites) {
    let fb = sprites.font_bold();
    let msg = "ATTACK-MOVE \u{2014} click target";
    let tw = measure_text(msg, fb, 24, 1.0).width;
    let x = (screen_width() - tw) / 2.0;
    let y = WORLD_TOP + 84.0;
    draw_rectangle(x - 24.0, y - 30.0, tw + 48.0, 58.0, with_alpha(PANEL, 0.9));
    glow_rect(x - 24.0, y - 30.0, tw + 48.0, 58.0, ALERT_GLOW, 3);
    draw_rectangle(x - 24.0, y - 30.0, tw + 48.0, 3.0, BAD);
    draw_text_ex(
        msg,
        x,
        y,
        TextParams {
            font: fb,
            font_size: 24,
            color: BAD,
            ..Default::default()
        },
    );
    centered(
        "A again or Esc to cancel",
        y + 22.0,
        14.0,
        TEXT_DIM,
        sprites.font(),
    );
    // Cursor reticle: crosshair ring at the mouse so the armed state is local too.
    let (mx, my) = mouse_position();
    draw_circle_lines(mx, my, 11.0, 1.5, BAD);
    draw_line(mx - 16.0, my, mx - 6.0, my, 1.5, BAD);
    draw_line(mx + 6.0, my, mx + 16.0, my, 1.5, BAD);
    draw_line(mx, my - 16.0, mx, my - 6.0, 1.5, BAD);
    draw_line(mx, my + 6.0, mx, my + 16.0, 1.5, BAD);
}

/// The commanded-time auto-pause banner: names the event that froze the game and
/// how to resume. Centered high so it doesn't fight the world view.
fn draw_auto_pause_banner(msg: &str, sprites: &Sprites) {
    let fb = sprites.font_bold();
    let tw = measure_text(msg, fb, 26, 1.0).width;
    let x = (screen_width() - tw) / 2.0;
    let y = WORLD_TOP + 84.0;
    draw_rectangle(x - 24.0, y - 30.0, tw + 48.0, 58.0, with_alpha(PANEL, 0.9));
    glow_rect(x - 24.0, y - 30.0, tw + 48.0, 58.0, ALERT_GLOW, 3);
    draw_rectangle(x - 24.0, y - 30.0, tw + 48.0, 3.0, WARN);
    draw_text_ex(
        msg,
        x,
        y,
        TextParams {
            font: fb,
            font_size: 26,
            color: WARN,
            ..Default::default()
        },
    );
    centered(
        "PAUSED \u{2014} Space to resume",
        y + 22.0,
        14.0,
        TEXT_DIM,
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

/// Returns the display status of grid node `node` given the player's research
/// bitset, active research slot, and whether a research lab exists.
fn tech_status(
    node: &rts_core::game::tech_grid::GridNode,
    set: &rts_core::game::tech_grid::TechBitset,
    active: Option<(u32, u32)>,
    has_lab: bool,
) -> TechStatus {
    if set.get(node.id) {
        return TechStatus::Researched;
    }
    if let Some((active_id, ticks_remaining)) = active {
        if active_id == node.id {
            return TechStatus::InProgress {
                ticks_remaining,
                duration: node.duration,
            };
        }
    }
    // Locked while any prerequisite node is still unresearched.
    if node.prereqs.iter().any(|&p| !set.get(p)) {
        return TechStatus::Locked;
    }
    // Era 0 is the bootstrap (no lab); every later era needs a Research Lab.
    if node.era > 0 && !has_lab {
        return TechStatus::NoLab;
    }
    TechStatus::Available
}

/// Screen geometry of the 10×10 capability grid, shared by the read-only viewer,
/// the interactive research modal, and the mouse hit-test so they always agree.
struct GridLayout {
    ox: f32,
    oy: f32,
    cell_w: f32,
    cell_h: f32,
    pip_w: f32,
    gap: f32,
    label_w: f32,
}

fn grid_layout() -> GridLayout {
    let (w, h) = (screen_width(), screen_height());
    let label_w = 26.0;
    let pad = 20.0;
    let gap = 2.0;
    let cell_w = ((w - pad * 2.0 - label_w) / 10.0).min(96.0);
    let cell_h = ((h - 150.0) / 10.0).min(40.0);
    let grid_w = cell_w * 10.0;
    let ox = (w - grid_w - label_w) / 2.0 + label_w;
    GridLayout {
        ox,
        oy: 92.0,
        cell_w,
        cell_h,
        pip_w: (cell_w - gap * 6.0) / 5.0,
        gap,
        label_w,
    }
}

/// Screen rect of one grid pip (era column, branch row, step within the cell).
fn grid_pip_rect(l: &GridLayout, era: u32, branch: u32, step: u32) -> Rect {
    let cx = l.ox + era as f32 * l.cell_w;
    let ry = l.oy + branch as f32 * l.cell_h;
    let px = cx + l.gap + step as f32 * (l.pip_w + l.gap);
    Rect::new(px, ry + 4.0, l.pip_w, l.cell_h - 8.0)
}

/// The grid id whose pip is under `(mx, my)`, if any.
fn grid_pip_at(l: &GridLayout, mx: f32, my: f32) -> Option<u32> {
    (0..500u32).find(|&id| {
        let (era, branch, step) = (id / 50, (id / 5) % 10, id % 5);
        grid_pip_rect(l, era, branch, step).contains(vec2(mx, my))
    })
}

/// Short label for a building kind (tech-tree unlock hints).
const fn building_label(b: BuildingKind) -> &'static str {
    match b {
        BuildingKind::CommandCenter => "Command",
        BuildingKind::PowerPlant => "Reactor",
        BuildingKind::Refinery => "Extractor",
        BuildingKind::Barracks => "Hangar",
        BuildingKind::GunTurret => "Laser Turret",
        BuildingKind::AaTurret => "Flak Turret",
        BuildingKind::Wall => "Wall",
        BuildingKind::ResearchLab => "Research Lab",
        BuildingKind::AntimatterPlant => "Antimatter",
    }
}

/// Short label for a unit kind (tech-tree unlock hints).
const fn unit_label(u: UnitKind) -> &'static str {
    match u {
        UnitKind::Infantry => "Infantry",
        UnitKind::Tank => "Crawler",
        UnitKind::AntiArmor => "Lancer",
        UnitKind::Helicopter => "Gunship",
        UnitKind::Capital => "Capital",
    }
}

/// Pip colour for a node's reality class (how grounded-in-real-science it is).
const fn reality_color(r: RealityClass) -> Color {
    match r {
        RealityClass::Achieved => GOOD,
        RealityClass::Emerging => GRID_HOT,
        RealityClass::Theoretical => SHIELD,
        RealityClass::Speculative => WARN,
        RealityClass::Lore => TEXT_DIM,
    }
}

/// Human-readable name of a reality class (the honesty label).
const fn reality_name(r: RealityClass) -> &'static str {
    match r {
        RealityClass::Achieved => "Achieved",
        RealityClass::Emerging => "Emerging",
        RealityClass::Theoretical => "Theoretical",
        RealityClass::Speculative => "Speculative",
        RealityClass::Lore => "Lore",
    }
}

/// Draws the 10×10 capability-grid backdrop (era headers, branch codes, every
/// node pip coloured by `tint`, and the "Frontier of Known Physics" divider).
/// `tint(id)` returns each pip's colour so callers can show reality (read-only
/// viewer) or research status (interactive modal). Returns the shared layout.
fn draw_grid_backdrop(l: &GridLayout, sprites: &Sprites, tint: impl Fn(u32) -> Color) {
    let f = sprites.font();
    let fb = sprites.font_bold();
    for (e, name) in GRID_ERAS.iter().enumerate() {
        let cx = l.ox + e as f32 * l.cell_w;
        let tw = measure_text(name, f, 12, 1.0).width;
        draw_text_ex(
            name,
            cx + (l.cell_w - tw) / 2.0,
            l.oy - 6.0,
            TextParams {
                font: f,
                font_size: 12,
                color: TEXT_DIM,
                ..Default::default()
            },
        );
    }
    for (b, code) in GRID_BRANCHES.iter().enumerate() {
        let ry = l.oy + b as f32 * l.cell_h;
        draw_text_ex(
            code,
            l.ox - l.label_w + 6.0,
            ry + l.cell_h / 2.0 + 4.0,
            TextParams {
                font: fb,
                font_size: 14,
                color: GOLD,
                ..Default::default()
            },
        );
        for e in 0..10u32 {
            let cx = l.ox + e as f32 * l.cell_w;
            draw_rectangle_lines(cx, ry, l.cell_w, l.cell_h, 1.0, BORDER_NEUTRAL);
            for step in 0..5u32 {
                let id = e * 50 + b as u32 * 5 + step;
                let r = grid_pip_rect(l, e, b as u32, step);
                draw_rectangle(r.x, r.y, r.w, r.h, tint(id));
            }
        }
    }
    // The "Frontier of Known Physics" divider after era 4.
    let fx = l.ox + 5.0 * l.cell_w;
    draw_rectangle(fx - 1.5, l.oy, 3.0, l.cell_h * 10.0, WARN);
    draw_text_ex(
        "FRONTIER OF KNOWN PHYSICS",
        l.ox + l.cell_w,
        l.oy + l.cell_h * 10.0 + 18.0,
        TextParams {
            font: f,
            font_size: 12,
            color: WARN,
            ..Default::default()
        },
    );
}

/// A read-only viewer for the 500-slot Ascension capability grid, pips coloured
/// by reality class. Toggle with G; Esc closes.
fn draw_grid_viewer(sprites: &Sprites) {
    draw_rectangle(
        0.0,
        0.0,
        screen_width(),
        screen_height(),
        Color::from_rgba(0, 0, 0, 180),
    );
    centered(
        "ASCENSION — CAPABILITY GRID",
        38.0,
        24.0,
        GOLD,
        sprites.font_bold(),
    );
    centered(
        "10 eras × 10 branches × 5 steps   •   G / Esc to close",
        60.0,
        14.0,
        TEXT_DIM,
        sprites.font(),
    );
    // Legend: pips here are coloured by reality class (see `reality_color`).
    color_legend(
        &[
            (reality_color(RealityClass::Achieved), "Researched"),
            (reality_color(RealityClass::Emerging), "Available"),
            (reality_color(RealityClass::Speculative), "Frontier"),
            (reality_color(RealityClass::Lore), "Locked"),
        ],
        82.0,
        sprites.font(),
    );
    let l = grid_layout();
    draw_grid_backdrop(&l, sprites, |id| {
        reality_color(TECH_GRID[id as usize].reality)
    });
}

/// The display name of a sector doctrine (index into [`SECTOR_DOCTRINE_NAMES`]).
fn doctrine_name(d: SectorDoctrine) -> &'static str {
    let idx = SECTOR_DOCTRINES.iter().position(|&x| x == d).unwrap_or(0);
    SECTOR_DOCTRINE_NAMES[idx]
}

/// The sector governance overlay (toggle: K). Lists the player's colonies and the
/// doctrine governing each; number keys 1..=6 govern the highlighted colony.
fn draw_sector_modal(sim: &Sim, cursor: usize, sprites: &Sprites) {
    let cols: Vec<ColonyId> = (0..sim.colonies_len())
        .map(|i| ColonyId(u32::try_from(i).unwrap_or(0)))
        .filter(|&id| sim.colony(id).is_some_and(|c| c.owner == HUMAN))
        .collect();

    let (w, h) = (screen_width(), screen_height());
    draw_rectangle(0.0, 0.0, w, h, Color::from_rgba(0, 0, 0, 120));

    let pw = 700.0_f32.min(w - 40.0);
    let row_h = 30.0;
    let head_h = 50.0;
    let foot_h = 56.0;
    let rows = cols.len().max(1) as f32;
    let ph = head_h + rows * row_h + foot_h + 16.0;
    let px = (w - pw) / 2.0;
    let py = (h - ph) / 2.0;

    draw_rectangle(px, py, pw, ph, PANEL);
    draw_rectangle(px, py, pw, 4.0, GOLD);
    draw_rectangle_lines(px, py, pw, ph, 1.0, BORDER_NEUTRAL);

    let fb = sprites.font_bold();
    let f = sprites.font();
    centered("COLONY GOVERNANCE", py + 32.0, 24.0, GOLD, fb);
    draw_rectangle(px + 12.0, py + head_h - 4.0, pw - 24.0, 1.0, OLIVE);

    if cols.is_empty() {
        centered(
            "No colonies yet \u{2014} found a base first.",
            py + head_h + 28.0,
            16.0,
            TEXT_DIM,
            f,
        );
    }
    for (i, &id) in cols.iter().enumerate() {
        let Some(c) = sim.colony(id) else { continue };
        let ry = py + head_h + i as f32 * row_h + 8.0;
        if i == cursor.min(cols.len().saturating_sub(1)) {
            draw_rectangle(
                px + 8.0,
                ry - 4.0,
                pw - 16.0,
                row_h - 2.0,
                with_alpha(GOLD, 0.16),
            );
            draw_rectangle_lines(px + 8.0, ry - 4.0, pw - 16.0, row_h - 2.0, 1.5, GOLD_HI);
        }
        let label = format!("Colony #{}", id.0);
        draw_text_ex(
            &label,
            px + 18.0,
            ry + 16.0,
            TextParams {
                font: fb,
                font_size: 16,
                color: TEXT,
                ..Default::default()
            },
        );
        // City size: current population and food progress toward the next pop.
        // Fixed values are rendered as integers via the shell's bits/65536 idiom.
        let pop = sim.colony_population(id);
        let (food, threshold) = sim.colony_food_progress(id);
        let food_now = food.to_bits() / 65536;
        let food_next = threshold.to_bits() / 65536;
        let city = format!("pop {pop}  food {food_now}/{food_next}");
        draw_text_ex(
            &city,
            px + 100.0,
            ry + 16.0,
            TextParams {
                font: f,
                font_size: 13,
                color: TEXT_DIM,
                ..Default::default()
            },
        );
        let auto = format!("auto {}/{}", c.effective_autonomy(), c.autonomy_level);
        draw_text_ex(
            &auto,
            px + 250.0,
            ry + 16.0,
            TextParams {
                font: f,
                font_size: 14,
                color: TEXT_DIM,
                ..Default::default()
            },
        );
        let doc = sim.colony_doctrine(id);
        let governed = c.sector.is_some();
        draw_text_ex(
            doctrine_name(doc),
            px + 380.0,
            ry + 16.0,
            TextParams {
                font: fb,
                font_size: 15,
                color: if governed { GOOD } else { TEXT_DIM },
                ..Default::default()
            },
        );
        // Per-colony autonomy status — earning/frozen stand out (rules R2/R4).
        let (st, st_col) = if matches!(c.directive, ColonyIntent::Hold | ColonyIntent::Evacuate) {
            ("FROZEN", WARN)
        } else if c.effective_autonomy() >= AUTONOMY_FULL {
            ("AUTO", GOOD)
        } else if c.earned_autonomy() < c.autonomy_level {
            ("EARNING", GOLD_HI)
        } else if c.autonomy_level == 0 {
            ("MANUAL", TEXT_DIM)
        } else {
            ("ACTIVE", TEXT)
        };
        draw_text_ex(
            st,
            px + 530.0,
            ry + 16.0,
            TextParams {
                font: f,
                font_size: 13,
                color: st_col,
                ..Default::default()
            },
        );
    }

    // Footer: the doctrine legend (number keys) + controls.
    let legend = "1 Balanced   2 Research   3 Mining   4 Fortress   5 Shipyard   6 Frontier";
    centered(legend, py + ph - 34.0, 13.0, GOLD_HI, f);
    centered(
        "Up/Dn select   \u{2022}   1\u{2013}6 doctrine   \u{2022}   Left/Right autonomy   \u{2022}   Esc close",
        py + ph - 14.0,
        13.0,
        TEXT_DIM,
        f,
    );
}

fn draw_doctrine_modal(sim: &Sim, cursor: usize, sprites: &Sprites) {
    const NAMES: [&str; 4] = ["WEAPONS", "ARMOR", "VITALITY", "FORGE"];
    const DESCS: [&str; 4] = [
        "+1 damage / level",
        "+0.5 armor / level",
        "+8 shield / level",
        "+0.25 damage & armor / level  \u{2022}  Money only",
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

    let money = sim.money(HUMAN).to_bits() / 65536;
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
        // Doctrines are paid entirely from Money now (money + research folded).
        let afford = lab_ok && money >= mc_i + rc_i;

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

        // Cost (right-aligned), tinted by affordability. Doctrines are Money-only
        // now (the old research portion is folded in).
        let cost_s = format!("${}", mc_i + rc_i);
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
        "Up/Dn select  \u{2022}  Enter / 1-4 ascend  \u{2022}  Esc close",
        footer_y,
        15.0,
        TEXT_DIM,
        f,
    );
}

/// Status-aware pip colour for the interactive research grid.
const fn status_color(status: TechStatus, reality: RealityClass) -> Color {
    match status {
        TechStatus::Researched => GOOD,
        TechStatus::InProgress { .. } => WARN,
        TechStatus::Available => GOLD_HI,
        TechStatus::NoLab => BAD,
        // Locked nodes still show the science landscape, but muted.
        TechStatus::Locked => with_alpha(reality_color(reality), 0.3),
    }
}

/// The interactive capability-grid research modal. The `cursor` grid id is
/// highlighted; the panel below reads out the selected node. Toggle with Y;
/// ←/→ era, ↑/↓ branch, [ ] step, Enter/click to research, Esc closes.
fn draw_research_modal(sim: &Sim, cursor: usize, sprites: &Sprites) {
    draw_rectangle(
        0.0,
        0.0,
        screen_width(),
        screen_height(),
        Color::from_rgba(0, 0, 0, 205),
    );
    let font = sprites.font();
    let font_bold = sprites.font_bold();
    centered(
        "RESEARCH \u{2014} CAPABILITY GRID",
        38.0,
        24.0,
        GOLD,
        font_bold,
    );
    // Legend: pips here are coloured by research status (see `status_color`).
    // "Locked" mirrors the muted reality tint cells use for unreachable nodes.
    color_legend(
        &[
            (GOOD, "Researched"),
            (GOLD_HI, "Available"),
            (WARN, "Frontier"),
            (with_alpha(SHIELD, 0.3), "Locked"),
        ],
        62.0,
        font,
    );

    let (set, active) = sim.research_state(HUMAN);
    let has_lab = sim.has_research_lab(HUMAN);
    let l = grid_layout();
    draw_grid_backdrop(&l, sprites, |id| {
        let node = &TECH_GRID[id as usize];
        status_color(tech_status(node, &set, active, has_lab), node.reality)
    });

    // Cursor highlight: outline the selected pip and its enclosing cell.
    let cid = u32::try_from(cursor).unwrap_or(0).min(499);
    let (era, branch, step) = (cid / 50, (cid / 5) % 10, cid % 5);
    let pip = grid_pip_rect(&l, era, branch, step);
    draw_rectangle_lines(
        pip.x - 1.0,
        pip.y - 1.0,
        pip.w + 2.0,
        pip.h + 2.0,
        2.0,
        GOLD,
    );
    let cx = l.ox + era as f32 * l.cell_w;
    let cy = l.oy + branch as f32 * l.cell_h;
    draw_rectangle_lines(cx, cy, l.cell_w, l.cell_h, 1.5, GOLD_HI);

    // Detail panel for the selected node.
    let node = &TECH_GRID[cid as usize];
    let status = tech_status(node, &set, active, has_lab);
    let dy = l.oy + l.cell_h * 10.0 + 34.0;
    draw_text_ex(
        node.name,
        l.ox - l.label_w,
        dy,
        TextParams {
            font: font_bold,
            font_size: 18,
            color: GOLD,
            ..Default::default()
        },
    );
    let branch_name = GRID_BRANCH_NAMES[branch as usize];
    let coord = format!(
        "{} \u{00b7} {} \u{00b7} step {}/5 \u{00b7} {}",
        GRID_ERAS[era as usize],
        branch_name,
        step + 1,
        reality_name(node.reality),
    );
    draw_text_ex(
        &coord,
        l.ox - l.label_w,
        dy + 20.0,
        TextParams {
            font,
            font_size: 13,
            color: TEXT_DIM,
            ..Default::default()
        },
    );
    let status_word = match status {
        TechStatus::Researched => "RESEARCHED".to_owned(),
        TechStatus::InProgress {
            ticks_remaining,
            duration,
        } => {
            let pct = (duration.saturating_sub(ticks_remaining) * 100)
                .checked_div(duration)
                .unwrap_or(100);
            format!("RESEARCHING {pct}%")
        }
        TechStatus::Available => "AVAILABLE".to_owned(),
        TechStatus::NoLab => "NEEDS RESEARCH LAB".to_owned(),
        TechStatus::Locked => "LOCKED".to_owned(),
    };
    let costs = format!(
        "${}   EN {}   LB {}   \u{2022}   {}",
        node.money, node.energy, node.labour, status_word,
    );
    let cost_col = match status {
        TechStatus::Available => GOLD_HI,
        TechStatus::Researched => GOOD,
        TechStatus::InProgress { .. } => WARN,
        _ => BAD,
    };
    draw_text_ex(
        &costs,
        l.ox - l.label_w,
        dy + 40.0,
        TextParams {
            font,
            font_size: 13,
            color: cost_col,
            ..Default::default()
        },
    );
    // What gameplay door this node opens, if any.
    let unlock = tech_grid::real_building(node.id)
        .map(building_label)
        .or_else(|| tech_grid::real_unit(node.id).map(unit_label));
    if let Some(name) = unlock {
        let unlock_s = format!("Unlocks: {name}");
        draw_text_ex(
            &unlock_s,
            l.ox - l.label_w,
            dy + 60.0,
            TextParams {
                font,
                font_size: 13,
                color: SHIELD,
                ..Default::default()
            },
        );
    }

    centered(
        "Left/Right era  \u{2022}  Up/Dn branch  \u{2022}  [ ] step  \u{2022}  Enter/click research  \u{2022}  Y / Esc close",
        screen_height() - 14.0,
        13.0,
        TEXT_DIM,
        font,
    );
}

#[allow(
    clippy::too_many_arguments,
    reason = "the single render entry point threads sim, view/particle layers, selection, the in-progress drag box, camera and assets"
)]
fn draw(
    sim: &Sim,
    view: &view::ViewState,
    particles: &particles::Particles,
    selected: &Selection,
    drag_start: Option<(f32, f32)>,
    build_mode: Option<BuildingKind>,
    cell: f32,
    ox_base: f32,
    wtop_base: f32,
    alpha: f32,
    sx: f32,
    sy: f32,
    sprites: &Sprites,
) {
    clear_background(BASE_CHARCOAL);
    // `ox_base`/`wtop_base` are the camera transform (zoom + pan) shared with input;
    // the world layer adds the screen-shake (sx, sy) on top. The HUD does not.
    let ox = ox_base + sx;
    let wtop = wtop_base + sy;
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
        if selected.units.contains(&v.id) {
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
    // Cities: each planet rendered as a glowing world that grows with its colony.
    // Drawn over pieces (the Command Center sprite sits under the city glow) so the
    // planets read as the focal points of the map.
    draw_cities(sim, cell, ox, wtop, sprites);
    // A selected planet gets a pulsing cyan ring at its center, sized to its
    // radius (in tiles) so it reads as the chosen world, not a unit.
    if let Some(pid) = selected.planet {
        if let Some(c) = sim.planet_center(pid) {
            let px = ox + tile_to_px(c.x, cell);
            let py = wtop + tile_to_px(c.y, cell);
            let r = sim
                .planet_radius(pid)
                .map_or(cell * 1.5, |rad| tile_to_px(rad, cell).max(cell));
            let pulse = (get_time() as f32 * 2.0).sin() * 0.5 + 0.5;
            draw_circle_lines(px, py, r, 2.5, SELECT_RING);
            draw_circle_lines(
                px,
                py,
                r + 4.0 + pulse * 6.0,
                1.5,
                with_alpha(SELECT_RING, 0.3 + pulse * 0.4),
            );
        }
    }
    if let Some(kind) = build_mode {
        draw_build_grid(sim, cell, ox, wtop);
        draw_build_ghost(sim, kind, cell, ox, wtop);
    }
    // The in-progress box-select rectangle, drawn last (over the world) in raw
    // screen space — the HUD/cursor frame, so it ignores the screen-shake offset.
    if let Some((dx, dy)) = drag_start {
        let (mx, my) = mouse_position();
        let (rx, ry) = (dx.min(mx), dy.min(my));
        let (rw, rh) = ((dx - mx).abs(), (dy - my).abs());
        // Only draw once it's actually a drag, not a pending click.
        if rw > 2.0 || rh > 2.0 {
            draw_rectangle(rx, ry, rw, rh, with_alpha(SELECT_RING, 0.10));
            draw_rectangle_lines(rx, ry, rw, rh, 1.0, with_alpha(SELECT_RING, 0.9));
        }
    }
}

/// Counts buildings standing on planet `pid` by mapping each building's world
/// position to a tile and asking the map which planet owns that tile.
fn buildings_on_planet(sim: &Sim, pid: PlanetId) -> u32 {
    let (w, h) = (sim.map().width(), sim.map().height());
    sim.views()
        .iter()
        .filter(|v| matches!(v.kind, EntityKindView::Building(_)))
        .filter(|v| {
            let (col, row) = hex::from_world(v.pos, w, h);
            sim.map().planet_at(i32::from(col), i32::from(row)) == Some(pid)
        })
        .count() as u32
}

/// A solid natural color from raw RGB bytes (full alpha), for surface palettes.
fn srgb(r: u8, g: u8, b: u8) -> Color {
    Color::new(
        f32::from(r) / 255.0,
        f32::from(g) / 255.0,
        f32::from(b) / 255.0,
        1.0,
    )
}

/// A deterministic 32-bit hash of a planet id — the world's fixed "identity".
/// Surface style, continent positions, crater scatter etc. are all sliced from
/// this so a given planet always looks the same (no rng in presentation).
fn planet_hash(pid: PlanetId) -> u32 {
    u32::from(pid.0).wrapping_add(1).wrapping_mul(2_654_435_761)
}

/// Maps a hash word to a float in `[0, 1)` from a chosen bit-slice (`shift`).
fn hash01(h: u32, shift: u32) -> f32 {
    ((h >> (shift & 0x18)) & 0xFF) as f32 / 256.0
}

/// The Conquest scenario is literally our Solar System: planets are pushed in
/// solar order, so `pid.0` maps directly to a real body. This returns the body's
/// relative display size (× the base radius) so Jupiter dwarfs Mercury.
const fn planet_size_scale(pid: PlanetId) -> f32 {
    match pid.0 {
        0 => 0.7,     // Mercury — small
        3 => 0.8,     // Mars
        4 => 1.6,     // Jupiter — largest
        5 => 1.4,     // Saturn
        6 | 7 => 1.2, // Uranus / Neptune — ice giants
        _ => 1.0,     // Venus, Earth
    }
}

/// Draws Saturn's ring system as a wide flat ellipse around the body. `front`
/// selects which half is drawn: the back half (behind the planet) before the
/// disc, the front half (over the planet) after it, so the rings read as
/// encircling the world. A subtle Cassini gap is left between two ring bands.
fn draw_saturn_rings(px: f32, py: f32, r: f32, front: bool) {
    let rx = r * 2.05;
    let ry = r * 0.45;
    // A vertical clip: we approximate the front/back split by drawing the full
    // ellipse but masking is unavailable, so we draw thin ellipse outlines and
    // rely on the planet disc (drawn between the two calls) to occlude the back
    // half. The front pass uses slightly brighter tan to sit over the body.
    let tan_outer = srgb(210, 190, 140);
    let tan_inner = srgb(180, 158, 110);
    let alpha = if front { 0.8 } else { 0.55 };
    // Filled ring band (outer), then a darker gap, then an inner band.
    draw_ellipse(px, py, rx, ry, 0.0, with_alpha(tan_outer, alpha * 0.5));
    draw_ellipse(
        px,
        py,
        rx * 0.86,
        ry * 0.86,
        0.0,
        with_alpha(srgb(20, 18, 14), alpha * 0.5),
    );
    draw_ellipse(
        px,
        py,
        rx * 0.78,
        ry * 0.78,
        0.0,
        with_alpha(tan_inner, alpha * 0.5),
    );
    draw_ellipse(
        px,
        py,
        rx * 0.62,
        ry * 0.62,
        0.0,
        with_alpha(srgb(20, 18, 14), alpha * 0.4),
    );
    // Crisp ring outlines for definition.
    draw_ellipse_lines(px, py, rx, ry, 0.0, 1.5, with_alpha(tan_outer, alpha));
    draw_ellipse_lines(
        px,
        py,
        rx * 0.78,
        ry * 0.78,
        0.0,
        1.0,
        with_alpha(tan_inner, alpha),
    );
    draw_ellipse_lines(
        px,
        py,
        rx * 0.6,
        ry * 0.6,
        0.0,
        1.0,
        with_alpha(tan_inner, alpha * 0.8),
    );
}

/// Draws the natural (un-owned) surface of a world onto a disc of radius `r`
/// centred at `(px, py)`. The body is chosen by its real solar-order id
/// (`pid.0` 0..7 = Mercury..Neptune); all detail derives deterministically from
/// `h`. Every fleck/blob is kept inside the disc so it reads as a sphere once
/// the shading pass is layered on top. Surfaces use natural palettes (never civ
/// colours) — ownership reads from the atmosphere tint + city-lights elsewhere.
#[allow(clippy::too_many_lines)]
fn draw_planet_surface(px: f32, py: f32, r: f32, pid: PlanetId, h: u32) {
    match pid.0 {
        // --- 0 Mercury: small grey, heavily cratered.
        0 => {
            draw_circle(px, py, r, srgb(140, 134, 126));
            draw_circle(px, py, r, with_alpha(srgb(96, 90, 84), 0.4));
            for k in 0..8u32 {
                let a = hash01(h, k * 3) * std::f32::consts::TAU;
                let d = (0.08 + 0.72 * hash01(h, k * 3 + 8)) * r;
                let cx = px + a.cos() * d;
                let cy = py + a.sin() * d;
                let cr = r * (0.06 + 0.14 * hash01(h, k * 3 + 16));
                draw_circle(cx, cy, cr, with_alpha(srgb(86, 80, 74), 0.7));
                draw_circle_lines(cx, cy, cr, 1.0, with_alpha(srgb(54, 50, 46), 0.85));
            }
        }
        // --- 1 Venus: pale yellow-cream, smooth featureless cloud cover.
        1 => {
            draw_circle(px, py, r, srgb(225, 205, 150));
            draw_circle(px, py, r, with_alpha(srgb(235, 222, 178), 0.5));
            // A couple of faint lighter cloud swirls.
            for k in 0..3u32 {
                let f = (k as f32 + 0.5) / 3.0;
                let by = py - r + f * 2.0 * r;
                let dy = (by - py) / r;
                let half = r * (1.0 - dy * dy).max(0.0).sqrt();
                draw_ellipse(
                    px,
                    by,
                    half * 0.9,
                    r * 0.12,
                    0.0,
                    with_alpha(srgb(245, 235, 205), 0.35),
                );
            }
        }
        // --- 2 Earth: blue oceans + green/brown continents + white cloud arcs.
        2 => {
            draw_circle(px, py, r, srgb(28, 64, 120));
            draw_circle(px, py, r, with_alpha(srgb(40, 90, 150), 0.4));
            let lands = [srgb(70, 130, 70), srgb(96, 132, 78), srgb(120, 110, 72)];
            for k in 0..3u32 {
                let a = hash01(h, k * 4) * std::f32::consts::TAU;
                let d = (0.15 + 0.5 * hash01(h, k * 4 + 8)) * r;
                let lx = px + a.cos() * d;
                let ly = py + a.sin() * d;
                let lr = r * (0.18 + 0.22 * hash01(h, k * 4 + 16));
                let lc = lands[(k as usize) % lands.len()];
                draw_ellipse(lx, ly, lr * 1.2, lr * 0.85, a * 20.0, lc);
            }
            // White cloud arcs, kept inside the disc.
            for k in 0..2u32 {
                let a = hash01(h, k * 6 + 4) * std::f32::consts::TAU;
                let d = 0.4 * r;
                let cxx = px + a.cos() * d;
                let cyy = py + a.sin() * d;
                draw_ellipse(
                    cxx,
                    cyy,
                    r * 0.34,
                    r * 0.12,
                    a * 30.0,
                    with_alpha(WHITE, 0.35),
                );
            }
        }
        // --- 3 Mars: rusty red base + darker maria + a white polar cap (top).
        3 => {
            draw_circle(px, py, r, srgb(200, 95, 55));
            draw_circle(px, py, r, with_alpha(srgb(165, 75, 45), 0.35));
            for k in 0..4u32 {
                let a = hash01(h, k * 4) * std::f32::consts::TAU;
                let d = (0.1 + 0.6 * hash01(h, k * 4 + 8)) * r;
                let mx = px + a.cos() * d;
                let my = py + a.sin() * d;
                let mr = r * (0.12 + 0.18 * hash01(h, k * 4 + 16));
                draw_ellipse(
                    mx,
                    my,
                    mr * 1.1,
                    mr * 0.8,
                    a * 20.0,
                    with_alpha(srgb(120, 55, 35), 0.6),
                );
            }
            // North polar cap — bright white ellipse clipped near the top.
            draw_ellipse(
                px,
                py - r * 0.66,
                r * 0.5,
                r * 0.2,
                0.0,
                with_alpha(WHITE, 0.85),
            );
        }
        // --- 4 Jupiter: large cream/orange/brown bands + a Great Red Spot.
        4 => {
            draw_circle(px, py, r, srgb(200, 170, 130));
            let bands = 7u32;
            for k in 0..bands {
                let f = (k as f32 + 0.5) / bands as f32;
                let by = py - r + f * 2.0 * r;
                let dy = (by - py) / r;
                let half = r * (1.0 - dy * dy).max(0.0).sqrt();
                let bh = r * (0.07 + 0.06 * hash01(h, k * 4));
                let tone = match k % 3 {
                    0 => srgb(225, 200, 160), // pale cream
                    1 => srgb(170, 120, 80),  // orange-brown
                    _ => srgb(130, 90, 60),   // dark brown
                };
                draw_ellipse(px, by, half, bh, 0.0, with_alpha(tone, 0.9));
            }
            // Great Red Spot: lower-left oval.
            draw_ellipse(
                px - r * 0.32,
                py + r * 0.22,
                r * 0.26,
                r * 0.15,
                0.0,
                with_alpha(srgb(200, 90, 60), 0.85),
            );
            draw_ellipse_lines(
                px - r * 0.32,
                py + r * 0.22,
                r * 0.26,
                r * 0.15,
                0.0,
                1.0,
                with_alpha(srgb(150, 60, 40), 0.7),
            );
        }
        // --- 5 Saturn: pale-gold banded body (rings drawn in draw_cities).
        5 => {
            draw_circle(px, py, r, srgb(220, 200, 150));
            let bands = 5u32;
            for k in 0..bands {
                let f = (k as f32 + 0.5) / bands as f32;
                let by = py - r + f * 2.0 * r;
                let dy = (by - py) / r;
                let half = r * (1.0 - dy * dy).max(0.0).sqrt();
                let bh = r * (0.08 + 0.05 * hash01(h, k * 4));
                let tone = if (k & 1) == 0 {
                    srgb(232, 214, 168)
                } else {
                    srgb(196, 172, 120)
                };
                draw_ellipse(px, by, half, bh, 0.0, with_alpha(tone, 0.8));
            }
        }
        // --- 6 Uranus: pale cyan, smooth with faint banding.
        6 => {
            draw_circle(px, py, r, srgb(160, 220, 225));
            draw_circle(px, py, r, with_alpha(srgb(190, 235, 235), 0.4));
            for k in 0..3u32 {
                let f = (k as f32 + 0.5) / 3.0;
                let by = py - r + f * 2.0 * r;
                let dy = (by - py) / r;
                let half = r * (1.0 - dy * dy).max(0.0).sqrt();
                draw_ellipse(
                    px,
                    by,
                    half * 0.95,
                    r * 0.1,
                    0.0,
                    with_alpha(srgb(140, 205, 210), 0.3),
                );
            }
            // Thin vertical ring (Uranus is tilted on its side).
            draw_ellipse_lines(
                px,
                py,
                r * 0.4,
                r * 1.5,
                0.0,
                1.0,
                with_alpha(srgb(180, 220, 225), 0.3),
            );
        }
        // --- 7 Neptune: deep blue, smooth, a darker Great Dark Spot + faint bands.
        _ => {
            draw_circle(px, py, r, srgb(45, 80, 190));
            draw_circle(px, py, r, with_alpha(srgb(60, 100, 210), 0.4));
            for k in 0..3u32 {
                let f = (k as f32 + 0.5) / 3.0;
                let by = py - r + f * 2.0 * r;
                let dy = (by - py) / r;
                let half = r * (1.0 - dy * dy).max(0.0).sqrt();
                draw_ellipse(
                    px,
                    by,
                    half * 0.95,
                    r * 0.1,
                    0.0,
                    with_alpha(srgb(35, 65, 160), 0.4),
                );
            }
            // Great Dark Spot — upper-right darker oval.
            draw_ellipse(
                px + r * 0.28,
                py - r * 0.2,
                r * 0.24,
                r * 0.15,
                0.0,
                with_alpha(srgb(20, 40, 110), 0.75),
            );
        }
    }
}

/// Overlays sphere shading on a freshly-drawn surface disc: a soft specular
/// highlight upper-left, a dark terminator crescent lower-right, and a thin
/// dark rim. Makes the flat disc read as a lit 3-D ball.
fn shade_sphere(px: f32, py: f32, r: f32) {
    // Terminator: a dark disc offset down-right, fading the night side.
    draw_circle(
        px + r * 0.35,
        py + r * 0.35,
        r * 0.92,
        Color::new(0.0, 0.0, 0.04, 0.34),
    );
    draw_circle(
        px + r * 0.5,
        py + r * 0.5,
        r * 0.7,
        Color::new(0.0, 0.0, 0.03, 0.28),
    );
    // Specular highlight: small soft white blob upper-left.
    draw_circle(
        px - r * 0.34,
        py - r * 0.34,
        r * 0.30,
        with_alpha(WHITE, 0.18),
    );
    draw_circle(
        px - r * 0.36,
        py - r * 0.36,
        r * 0.14,
        with_alpha(WHITE, 0.28),
    );
    // Thin dark rim to seat the ball against the void.
    draw_circle_lines(px, py, r, 1.5, Color::new(0.0, 0.0, 0.0, 0.45));
}

/// Renders every planet as an actual *world* at its center, the heart of the map.
///
/// Each planet gets a fixed natural surface style (terran / gas-giant / rocky /
/// volcanic / ice, chosen from `pid % 5`) under 3-D sphere shading and an
/// atmosphere halo. **Owned** worlds tint that halo in the owner's civ colour
/// and grow a glittering city of light-dots on their night side whose count
/// tracks the colony population (the "city that grows"), with the population
/// number above. **Neutral** worlds stay natural and dim with a faint pulsing
/// "settle here" dot, clearly unclaimed.
fn draw_cities(sim: &Sim, cell: f32, ox: f32, wtop: f32, sprites: &Sprites) {
    let pf = sprites.font_bold();
    let t = get_time() as f32;
    for i in 0..sim.planets_len() {
        let pid = PlanetId(i as u16);
        let Some(c) = sim.planet_center(pid) else {
            continue;
        };
        let px = ox + tile_to_px(c.x, cell);
        let py = wtop + tile_to_px(c.y, cell);
        // Base body radius from the planet's tile radius, with a sane floor,
        // then scaled by the real body's relative size (Jupiter >> Mercury).
        let body_r = sim
            .planet_radius(pid)
            .map_or(cell * 0.9, |rad| tile_to_px(rad, cell).max(cell * 0.7))
            * planet_size_scale(pid);
        let hash = planet_hash(pid);
        let owner = sim.planet_owner(pid);
        // Atmosphere halo behind the body: tinted by owner, faint grey if neutral.
        let atmo = match owner {
            Some(o) if o == HUMAN => TEAM_PLAYER,
            Some(o) => civ_color(o.0),
            None => CIV_NEUTRAL,
        };
        let pulse = (t * 1.6 + i as f32).sin() * 0.5 + 0.5;
        draw_circle(px, py, body_r * 1.35, with_alpha(atmo, 0.10));
        draw_circle(px, py, body_r * 1.18, with_alpha(atmo, 0.08));
        // Saturn (pid 5): draw the back half of the ring system behind the body.
        if pid.0 == 5 {
            draw_saturn_rings(px, py, body_r, false);
        }
        // The world itself.
        draw_planet_surface(px, py, body_r, pid, hash);
        shade_sphere(px, py, body_r);
        // Saturn: front half of the rings, over the body, so it encircles it.
        if pid.0 == 5 {
            draw_saturn_rings(px, py, body_r, true);
        }
        // Atmosphere rim line in the owner colour (gentle pulse).
        draw_circle_lines(
            px,
            py,
            body_r + 2.0 + pulse * 2.0,
            1.5,
            with_alpha(atmo, if owner.is_some() { 0.7 } else { 0.4 }),
        );

        if let Some(owner) = owner {
            let human = owner == HUMAN;
            let col = if human {
                TEAM_PLAYER
            } else {
                civ_color(owner.0)
            };
            let pop = sim
                .planet_colony(pid)
                .map_or(0, |cid| sim.colony_population(cid));
            // City lights: count grows with population (a few up to ~60), each a
            // deterministic speck on the disc, biased toward the shaded night
            // side (lower-right) so the city reads as a glowing nightscape.
            let lights = usize::try_from(pop.min(60).max(buildings_on_planet(sim, pid).min(60)))
                .unwrap_or(60);
            // Soft owner-coloured city glow over the lit area, growing with pop.
            let glow_a = 0.06 + 0.22 * (lights as f32 / 60.0);
            draw_circle(
                px + body_r * 0.18,
                py + body_r * 0.18,
                body_r * 0.7,
                with_alpha(col, glow_a),
            );
            for k in 0..lights {
                // Deterministic per-light hash from planet hash + index.
                let lh = hash
                    ^ ((k as u32)
                        .wrapping_mul(2_246_822_519)
                        .wrapping_add(0x9E37_79B9));
                let a = (lh & 0xFFFF) as f32 / 65_536.0 * std::f32::consts::TAU;
                // sqrt radius for even areal spread; bias center-out toward night.
                let rad = ((lh >> 16) & 0xFF) as f32 / 256.0;
                let d = rad.sqrt() * body_r * 0.82;
                let lx = px + a.cos() * d + body_r * 0.12;
                let ly = py + a.sin() * d + body_r * 0.12;
                // Keep the speck inside the disc.
                if (lx - px) * (lx - px) + (ly - py) * (ly - py) > body_r * body_r * 0.9 {
                    continue;
                }
                let twk = 0.6 + 0.4 * ((t * 3.0 + k as f32 * 1.7).sin() * 0.5 + 0.5);
                let sz = (body_r * 0.045).max(1.0);
                draw_circle(lx, ly, sz, with_alpha(col, 0.9 * twk));
                draw_circle(lx, ly, sz * 0.55, with_alpha(WHITE, 0.8 * twk));
            }
            // Population number, centered above the world (brighter for human).
            let s = format!("{pop}");
            let tw = measure_text(&s, pf, 14, 1.0).width;
            let tc = if human { GOLD_HI } else { col };
            draw_text_ex(
                &s,
                px - tw / 2.0,
                py - body_r * 1.35 - 6.0,
                TextParams {
                    font: pf,
                    font_size: 14,
                    color: tc,
                    ..Default::default()
                },
            );
        } else {
            // Neutral: natural & dim, with a faint pulsing "settle here" dot.
            draw_circle(
                px,
                py,
                (body_r * 0.14).max(2.5),
                with_alpha(GOOD, 0.25 + 0.45 * pulse),
            );
            draw_circle(
                px,
                py,
                (body_r * 0.07).max(1.5),
                with_alpha(WHITE, 0.3 + 0.4 * pulse),
            );
        }
        // Planet name, centred under the world (pop number sits above it). The
        // ring system pushes Saturn's label a little lower so it clears the rings.
        let names = [
            "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune",
        ];
        if let Some(name) = names.get(usize::from(pid.0)) {
            let nw = measure_text(name, pf, 12, 1.0).width;
            let drop = if pid.0 == 5 { body_r * 0.6 } else { 0.0 };
            draw_text_ex(
                name,
                px - nw / 2.0,
                py + body_r + 16.0 + drop,
                TextParams {
                    font: pf,
                    font_size: 12,
                    color: with_alpha(WHITE, 0.7),
                    ..Default::default()
                },
            );
        }
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

/// Distinct base tone for a real gameplay `TerrainKind`, so the board shows the
/// actual terrain layer (fertile green vs barren grey vs mineral teal) rather
/// than decorative position-noise. Tuned dark + muted to read on the holo board.
const fn terrain_color(kind: TerrainKind) -> Color {
    match kind {
        TerrainKind::Barren => TERRAIN_BARREN,
        TerrainKind::Plains => TERRAIN_PLAINS,
        TerrainKind::Fertile => TERRAIN_FERTILE,
        TerrainKind::Rich => TERRAIN_RICH,
    }
}

/// Per-tile fill: the real terrain tone with a small deterministic brightness
/// jitter (±~6% by position hash) so each region gets subtle texture instead of
/// a flat slab, while staying fully deterministic (no rng).
fn terrain_tile_color(sim: &Sim, tx: u16, ty: u16) -> Color {
    let base = terrain_color(sim.map().terrain_at(i32::from(tx), i32::from(ty)));
    // 0..16 → roughly -6%..+6% multiplicative value jitter, centered.
    let n = (u32::from(tx) * 73 + u32::from(ty) * 151) % 16;
    let jitter = 0.94 + (n as f32) * (0.12 / 15.0);
    Color {
        r: (base.r * jitter).clamp(0.0, 1.0),
        g: (base.g * jitter).clamp(0.0, 1.0),
        b: (base.b * jitter).clamp(0.0, 1.0),
        a: base.a,
    }
}

/// Pixel bounds of the hex board (for the frame + vignette).
fn board_size(sim: &Sim, cell: f32) -> (f32, f32) {
    let cols = f32::from(sim.map().width().saturating_sub(1));
    let rows = f32::from(sim.map().height());
    ((0.75 * cols + 1.0) * cell, (rows + 0.5) * cell)
}

/// Renders the Conquest board as deep space: a near-black fill and a fixed
/// deterministic starfield (hashed positions, varied brightness/size, a few
/// bright cross-glint stars, a subtle per-star twinkle). No hex lattice — the
/// planets and the Sun carry the visual. A faint cool void-vignette seats the
/// rect against the letterbox.
fn draw_space(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let (bw, bh) = board_size(sim, cell);
    let t = get_time() as f32;
    // Deep-space fill: a very dark blue-charcoal.
    draw_rectangle(ox, wtop, bw, bh, Color::from_rgba(3, 5, 12, 255));
    // A barely-there nebular gradient lifting the centre, cool and dim.
    draw_ellipse(
        ox + bw / 2.0,
        wtop + bh * 0.5,
        bw * 0.55,
        bh * 0.5,
        0.0,
        Color::from_rgba(10, 16, 34, 40),
    );
    // Starfield: ~220 stars at deterministic positions across the board rect.
    // Each star's x/y/brightness/size is sliced from a hash of its index, so the
    // sky is fixed (no rng); a sin() term gives a gentle twinkle.
    let stars = 220u32;
    for k in 0..stars {
        let h = k
            .wrapping_mul(2_654_435_761)
            .wrapping_add(0x9E37_79B9)
            .wrapping_mul(2_246_822_519);
        let fx = (h & 0xFFFF) as f32 / 65_536.0;
        let fy = ((h >> 16) & 0xFFFF) as f32 / 65_536.0;
        let sx = ox + fx * bw;
        let sy = wtop + fy * bh;
        let g = (h >> 5) & 0xFF; // brightness slice
        let base_a = 0.25 + 0.55 * (g as f32 / 255.0);
        let twk = 0.7 + 0.3 * ((t * 1.5 + k as f32 * 0.7).sin() * 0.5 + 0.5);
        let a = base_a * twk;
        // ~1 in 9 stars is a brighter 2px star with a tiny cross-glint.
        if k % 9 == 0 {
            draw_circle(sx, sy, 1.6, with_alpha(WHITE, a));
            let gl = 3.2;
            draw_line(sx - gl, sy, sx + gl, sy, 1.0, with_alpha(WHITE, a * 0.5));
            draw_line(sx, sy - gl, sx, sy + gl, 1.0, with_alpha(WHITE, a * 0.5));
        } else {
            // Faint colour cast on a few stars (warm/cool) for depth.
            let tint = match k % 5 {
                0 => Color::from_rgba(200, 210, 255, 255),
                1 => Color::from_rgba(255, 225, 200, 255),
                _ => WHITE,
            };
            draw_circle(sx, sy, 0.9, with_alpha(tint, a));
        }
    }
    // Cool void-vignette: concentric darkening frames, heaviest at the rim.
    for (i, alpha) in [70u8, 50, 34].into_iter().enumerate() {
        let inset = i as f32 * cell;
        draw_rectangle_lines(
            ox + inset,
            wtop + inset,
            bw - inset * 2.0,
            bh - inset * 2.0,
            cell,
            Color::from_rgba(1, 2, 6, alpha),
        );
    }
    // The Sun and orbit rings sit under the planets (drawn later in draw_cities).
    draw_sun(sim, cell, ox, wtop);
}

/// Screen-space centroid of all planet centres — the point the planets orbit,
/// where the Sun sits. `None` if there are no planets.
fn system_center(sim: &Sim, cell: f32, ox: f32, wtop: f32) -> Option<(f32, f32)> {
    let n = sim.planets_len();
    if n == 0 {
        return None;
    }
    let (mut sx, mut sy, mut count) = (0.0f32, 0.0f32, 0.0f32);
    for i in 0..n {
        if let Some(c) = sim.planet_center(PlanetId(i as u16)) {
            sx += ox + tile_to_px(c.x, cell);
            sy += wtop + tile_to_px(c.y, cell);
            count += 1.0;
        }
    }
    if count == 0.0 {
        None
    } else {
        Some((sx / count, sy / count))
    }
}

/// Draws the system's Sun at the centroid of the planets, plus one faint orbit
/// ring per planet (a circle on the Sun centred at the planet's screen radius).
/// The Sun is a blazing warm star: stacked translucent glow discs (white→orange
/// →transparent), a hot white-yellow core, a gently pulsing corona, and a few
/// faint rotating rays. Warm colours only — never a civ colour.
fn draw_sun(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    let Some((cx, cy)) = system_center(sim, cell, ox, wtop) else {
        return;
    };
    let t = get_time() as f32;
    // Orbit rings: one faint cool circle per planet, radius = Sun→planet distance.
    for i in 0..sim.planets_len() {
        let Some(c) = sim.planet_center(PlanetId(i as u16)) else {
            continue;
        };
        let px = ox + tile_to_px(c.x, cell);
        let py = wtop + tile_to_px(c.y, cell);
        let rad = (px - cx).hypot(py - cy);
        if rad < 1.0 {
            continue;
        }
        // Faint cool steel-blue orbit ring, low alpha.
        draw_circle_lines(cx, cy, rad, 1.0, Color::from_rgba(120, 150, 200, 30));
    }
    // Sun radius scaled to the cell so it reads as the blazing system heart.
    let r = (cell * 1.6).max(18.0);
    // Soft radial glow: several stacked translucent discs warm-white→orange→clear,
    // with a slow breathing pulse.
    let pulse = 0.5 + 0.5 * (t * 0.8).sin();
    let glow = r * (3.4 + 0.25 * pulse);
    draw_circle(cx, cy, glow, Color::from_rgba(255, 170, 60, 14));
    draw_circle(cx, cy, glow * 0.72, Color::from_rgba(255, 190, 90, 20));
    draw_circle(cx, cy, glow * 0.5, Color::from_rgba(255, 215, 130, 32));
    draw_circle(cx, cy, r * 1.7, Color::from_rgba(255, 235, 180, 60));
    // Faint rotating rays — a subtle corona, gently animated.
    for k in 0..8u32 {
        let ang = t * 0.15 + k as f32 * (std::f32::consts::TAU / 8.0);
        let len = r * (2.2 + 0.3 * (t * 1.1 + k as f32).sin());
        let x1 = cx + ang.cos() * len;
        let y1 = cy + ang.sin() * len;
        draw_line(cx, cy, x1, y1, 2.0, Color::from_rgba(255, 210, 130, 18));
    }
    // Core disc: bright white-yellow body with a hot white centre.
    draw_circle(cx, cy, r, srgb(255, 240, 200));
    draw_circle(cx, cy, r * 0.78, srgb(255, 250, 225));
    draw_circle(cx, cy, r * 0.45, WHITE);
    // Thin warm rim to seat the corona against the core.
    draw_circle_lines(cx, cy, r, 1.5, with_alpha(srgb(255, 200, 120), 0.6));
}

/// Draws the battlefield as a gilded antique **hex** campaign-map: flat-top hex
/// terrain tiles in warm painted tones, a sepia varnish + edge vignette, and an
/// ornate gold deco frame with corner ornaments — matching the regal menu.
fn draw_ground(sim: &Sim, cell: f32, ox: f32, wtop: f32) {
    // Conquest (planetary) → render the board as deep space with a starfield,
    // not the gilded hex campaign-map. Survival (no planets) keeps the hex look.
    if sim.planets_len() > 0 {
        draw_space(sim, cell, ox, wtop);
        return;
    }
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
            draw_hex(cx, cy, cell, terrain_tile_color(sim, col, row));
            if (col / 4 + row / 4).is_multiple_of(2) {
                draw_hex(cx, cy, cell, GROUND_MACRO);
            }
            // Planetary territory: tint the tile by its owning civ (neutral grey
            // for unclaimed planets). Open space (no planet) stays untinted.
            if let Some(pid) = sim.map().planet_at(i32::from(col), i32::from(row)) {
                let tint = sim
                    .planet_owner(pid)
                    .map_or(theme::CIV_NEUTRAL, |owner| theme::civ_color(owner.0));
                draw_hex(cx, cy, cell, with_alpha(tint, 0.22));
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

/// The hovered hex during building placement (mouse → cell), using the shared
/// camera transform `ox`/`wtop` so the ghost lands under the cursor at any zoom/pan.
fn mouse_hex(sim: &Sim, cell: f32, ox: f32, wtop: f32) -> (u16, u16) {
    let (mx, my) = mouse_position();
    let wx = Fixed::from_bits((((mx - ox) / cell) * 65536.0) as i64);
    let wy = Fixed::from_bits((((my - wtop) / cell) * 65536.0) as i64);
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
    let (col, row) = mouse_hex(sim, cell, ox, wtop);
    let buildable = sim
        .map()
        .tile(i32::from(col), i32::from(row))
        .is_some_and(|t| t.buildable);
    let affordable = sim.money(HUMAN) >= sim.building_cost(kind);
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

/// Draws the under-attack alerts on the main view: a pulsing red ring at each
/// on-screen battle, or — when the battle is off-screen — a red triangle clamped
/// to the playfield border pointing toward it. No arrow glyphs (the font lacks
/// them); the directional cue is a `draw_triangle` chevron. Read-only.
fn draw_alert_overlay(alerts: &[alerts::Alert], cell: f32, ox: f32, wtop: f32) {
    // Playfield viewport rect (between the top bar and the command bar).
    let (vx0, vy0) = (0.0_f32, WORLD_TOP);
    let vx1 = screen_width();
    let vy1 = screen_height() - ui::CMD_BAR_H;
    let pulse = (get_time() as f32 * 5.0).sin() * 0.5 + 0.5; // 0..1
    for a in alerts {
        let sx = ox + a.world.0 * cell;
        let sy = wtop + a.world.1 * cell;
        let on_screen = sx >= vx0 && sx <= vx1 && sy >= vy0 && sy <= vy1;
        if on_screen {
            // Subtle pulsing red ring at the battle location.
            let r = cell * (1.1 + 0.25 * pulse);
            draw_circle_lines(sx, sy, r, 2.0, with_alpha(BAD, 0.45 + 0.45 * pulse));
            draw_circle_lines(sx, sy, r * 0.6, 1.5, with_alpha(BAD, 0.3 + 0.3 * pulse));
        } else {
            // Off-screen: clamp the alert's screen position to the viewport border
            // (inset a little) and draw a triangle pointing outward toward it.
            const PAD: f32 = 22.0;
            let cx = (sx).clamp(vx0 + PAD, vx1 - PAD);
            let cy = (sy).clamp(vy0 + PAD, vy1 - PAD);
            // Direction from the clamped edge point toward the true (off-screen) pos.
            let mut dx = sx - cx;
            let mut dy = sy - cy;
            let len = dx.hypot(dy).max(0.0001);
            dx /= len;
            dy /= len;
            // Perpendicular for the triangle base.
            let (px, py) = (-dy, dx);
            let tip = vec2(cx + dx * 16.0, cy + dy * 16.0);
            let b1 = vec2(cx + px * 9.0, cy + py * 9.0);
            let b2 = vec2(cx - px * 9.0, cy - py * 9.0);
            let glow = with_alpha(BAD, 0.55 + 0.4 * pulse);
            draw_triangle(tip, b1, b2, glow);
            // A small backing dot anchors the arrow on the border.
            draw_circle(cx, cy, 4.0, with_alpha(BAD, 0.7));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{tech_status, TechStatus};
    use rts_core::game::tech_grid::{node, TechBitset};

    // Node 20 (Combined-Arms Doctrine) is an era-0 root: no prereqs, no lab.
    const ROOT: u32 = 20;
    // Node 70 (Solid-State Laser) is an era-1 node with prereqs [24, 9].
    const ERA1: u32 = 70;

    fn bits(ids: &[u32]) -> TechBitset {
        let mut b = TechBitset::empty();
        for &id in ids {
            b.set(id);
        }
        b
    }

    #[test]
    fn researched_bit_takes_priority() {
        let status = tech_status(node(ROOT).unwrap(), &bits(&[ROOT]), None, true);
        assert!(matches!(status, TechStatus::Researched));
    }

    #[test]
    fn in_progress_reports_correct_percent() {
        let n = node(ROOT).unwrap();
        let status = tech_status(n, &TechBitset::empty(), Some((ROOT, n.duration / 2)), true);
        if let TechStatus::InProgress {
            ticks_remaining,
            duration,
        } = status
        {
            let elapsed = duration.saturating_sub(ticks_remaining);
            assert_eq!((elapsed * 100) / duration, 50);
        } else {
            panic!("expected InProgress");
        }
    }

    #[test]
    fn locked_when_prereq_not_researched() {
        // Node 70 needs [24, 9]; an empty bitset → locked.
        let status = tech_status(node(ERA1).unwrap(), &TechBitset::empty(), None, true);
        assert!(matches!(status, TechStatus::Locked));
    }

    #[test]
    fn no_lab_status_when_lab_absent() {
        // Direct prereqs met but era 1 → a Research Lab is required.
        let status = tech_status(node(ERA1).unwrap(), &bits(&[24, 9]), None, false);
        assert!(matches!(status, TechStatus::NoLab));
    }

    #[test]
    fn available_when_prereq_met_and_lab_present() {
        let status = tech_status(node(ERA1).unwrap(), &bits(&[24, 9]), None, true);
        assert!(matches!(status, TechStatus::Available));
    }
}
