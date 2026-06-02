//! In-game UI: a top resource bar and a bottom command bar of build/train
//! buttons. Styled for a production look with a custom font, a consistent
//! palette, and clear button states. Buttons emit the same `Command`s as the
//! hotkeys, so the UI is just another input source.

use crate::sprites::Sprites;
use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};

const HUMAN: PlayerId = PlayerId(0);
/// Height of the top resource bar.
pub const TOP_BAR_H: f32 = 38.0;
/// Height of the bottom command bar.
pub const CMD_BAR_H: f32 = 76.0;

// --- palette ---
const PANEL: Color = color_u8!(18, 22, 28, 245);
const BORDER: Color = color_u8!(58, 68, 80, 255);
const SEP: Color = color_u8!(48, 56, 66, 255);
const ACCENT: Color = color_u8!(64, 196, 255, 255);
const TEXT: Color = color_u8!(222, 230, 238, 255);
const TEXT_DIM: Color = color_u8!(138, 150, 162, 255);
const GOOD: Color = color_u8!(108, 212, 128, 255);
const WARN: Color = color_u8!(240, 190, 92, 255);
const BAD: Color = color_u8!(236, 98, 88, 255);

fn text(s: &str, x: f32, y: f32, size: f32, color: Color, font: Option<&Font>) {
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

fn text_width(s: &str, size: f32, font: Option<&Font>) -> f32 {
    measure_text(s, font, size as u16, 1.0).width
}

#[derive(Clone, Copy)]
enum Action {
    Build(BuildingKind),
    Train(UnitKind),
}

struct Button {
    rect: Rect,
    label: &'static str,
    key: char,
    action: Action,
}

fn layout() -> [Button; 7] {
    let w = 104.0;
    let h = CMD_BAR_H - 16.0;
    let pad = 6.0;
    let y = screen_height() - CMD_BAR_H + 8.0;
    // A gap separates the build group (first 5) from the unit group (last 2).
    let group_gap = 22.0;
    let mk = |i: usize, label, key, action| {
        let gap = if i >= 5 { group_gap } else { 0.0 };
        Button {
            rect: Rect::new(12.0 + i as f32 * (w + pad) + gap, y, w, h),
            label,
            key,
            action,
        }
    };
    [
        mk(0, "Power", 'P', Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Refinery", 'R', Action::Build(BuildingKind::Refinery)),
        mk(2, "Barracks", 'B', Action::Build(BuildingKind::Barracks)),
        mk(3, "Gun Turret", 'G', Action::Build(BuildingKind::GunTurret)),
        mk(4, "AA Turret", 'A', Action::Build(BuildingKind::AaTurret)),
        mk(5, "Infantry", 'T', Action::Train(UnitKind::Infantry)),
        mk(6, "Helicopter", 'H', Action::Train(UnitKind::Helicopter)),
    ]
}

const fn cost(sim: &Sim, action: Action) -> Fixed {
    match action {
        Action::Build(k) => sim.building_cost(k),
        Action::Train(k) => sim.unit_cost(k),
    }
}

fn build_active(action: Action, build_mode: Option<BuildingKind>) -> bool {
    matches!((action, build_mode), (Action::Build(k), Some(m)) if k == m)
}

fn action_texture(sprites: &Sprites, action: Action) -> Option<&Texture2D> {
    match action {
        Action::Build(k) => sprites.building(k),
        Action::Train(k) => sprites.unit(k),
    }
}

fn first_barracks(sim: &Sim) -> Option<EntityId> {
    sim.views()
        .into_iter()
        .find(|v| {
            v.owner == HUMAN && matches!(v.kind, EntityKindView::Building(BuildingKind::Barracks))
        })
        .map(|v| v.id)
}

/// Whether the pointer is over a UI bar (so map clicks should be suppressed).
#[must_use]
pub fn pointer_over_ui() -> bool {
    let (_, my) = mouse_position();
    my < TOP_BAR_H || my > screen_height() - CMD_BAR_H
}

/// Handles a click on the command bar, returning any command it produced and
/// updating the pending build placement.
#[must_use]
pub fn handle_click(sim: &Sim, build_mode: &mut Option<BuildingKind>) -> Vec<Command> {
    let mut cmds = Vec::new();
    if !is_mouse_button_pressed(MouseButton::Left) {
        return cmds;
    }
    let (mx, my) = mouse_position();
    for b in layout() {
        if b.rect.contains(vec2(mx, my)) {
            match b.action {
                Action::Build(kind) => *build_mode = Some(kind),
                Action::Train(kind) => {
                    if let Some(barracks) = first_barracks(sim) {
                        cmds.push(Command::Train {
                            owner: HUMAN,
                            barracks,
                            kind,
                        });
                    }
                }
            }
            break;
        }
    }
    cmds
}

/// Draws the resource bar and the command bar.
pub fn draw(sim: &Sim, build_mode: Option<BuildingKind>, paused: bool, sprites: &Sprites) {
    draw_top_bar(sim, paused, sprites);
    draw_command_bar(sim, build_mode, sprites);
}

fn segment(x: f32, label: &str, value: &str, vcolor: Color, sprites: &Sprites) -> f32 {
    let f = sprites.font();
    let fb = sprites.font_bold();
    text(label, x, 19.0, 14.0, TEXT_DIM, f);
    let vx = x + text_width(label, 14.0, f) + 7.0;
    text(value, vx, 26.0, 22.0, vcolor, fb);
    let end = vx + text_width(value, 22.0, fb) + 24.0;
    draw_rectangle(end - 13.0, 9.0, 1.0, 20.0, SEP);
    end
}

fn draw_top_bar(sim: &Sim, paused: bool, sprites: &Sprites) {
    draw_rectangle(0.0, 0.0, screen_width(), TOP_BAR_H, PANEL);
    draw_rectangle(
        0.0,
        TOP_BAR_H - 2.0,
        screen_width(),
        2.0,
        color_u8!(38, 46, 56, 255),
    );

    let credits = sim.credits(HUMAN).to_bits() / 65536;
    let mut x = segment(14.0, "CREDITS", &credits.to_string(), ACCENT, sprites);
    let (produced, consumed) = sim.power_balance(HUMAN);
    let power_color = if produced >= consumed { GOOD } else { BAD };
    x = segment(
        x,
        "POWER",
        &format!("{produced}/{consumed}"),
        power_color,
        sprites,
    );
    let _ = segment(
        x,
        "UNITS",
        &sim.unit_count(HUMAN).to_string(),
        TEXT,
        sprites,
    );

    let fb = sprites.font_bold();
    if let Some(ticks) = sim.ticks_until_next_wave() {
        let secs = ticks / 30;
        let (label, col) = if secs <= 5 {
            ("INCOMING", BAD)
        } else {
            ("NEXT WAVE", WARN)
        };
        let s = format!("{label}  {secs}s");
        text(
            &s,
            screen_width() - text_width(&s, 21.0, fb) - 14.0,
            26.0,
            21.0,
            col,
            fb,
        );
    }
    if paused {
        let s = "PAUSED";
        text(
            s,
            (screen_width() - text_width(s, 22.0, fb)) / 2.0,
            26.0,
            22.0,
            WARN,
            fb,
        );
    }
}

fn draw_command_bar(sim: &Sim, build_mode: Option<BuildingKind>, sprites: &Sprites) {
    let top = screen_height() - CMD_BAR_H;
    draw_rectangle(0.0, top, screen_width(), CMD_BAR_H, PANEL);
    draw_rectangle(0.0, top, screen_width(), 2.0, color_u8!(38, 46, 56, 255));
    let pointer = {
        let (mx, my) = mouse_position();
        vec2(mx, my)
    };
    for b in layout() {
        let price = cost(sim, b.action);
        let affordable = sim.credits(HUMAN) >= price;
        let active = build_active(b.action, build_mode);
        let hover = b.rect.contains(pointer);
        draw_button(
            &b,
            sprites,
            affordable,
            active,
            hover,
            price.to_bits() / 65536,
        );
    }
}

fn draw_button(
    b: &Button,
    sprites: &Sprites,
    affordable: bool,
    active: bool,
    hover: bool,
    price: i64,
) {
    let r = b.rect;
    let bg = if active {
        color_u8!(26, 60, 80, 255)
    } else if hover {
        color_u8!(34, 41, 50, 255)
    } else {
        color_u8!(24, 29, 36, 255)
    };
    draw_rectangle(r.x, r.y, r.w, r.h, bg);
    let accent = if active {
        ACCENT
    } else if affordable {
        color_u8!(70, 82, 96, 255)
    } else {
        color_u8!(96, 56, 56, 255)
    };
    draw_rectangle(r.x, r.y, r.w, 2.0, accent);
    draw_rectangle_lines(
        r.x,
        r.y,
        r.w,
        r.h,
        1.0,
        if active { ACCENT } else { BORDER },
    );

    if let Some(tex) = action_texture(sprites, b.action) {
        let s = 28.0;
        let tint = if affordable {
            WHITE
        } else {
            color_u8!(120, 124, 130, 255)
        };
        draw_texture_ex(
            tex,
            r.x + (r.w - s) / 2.0,
            r.y + 7.0,
            tint,
            DrawTextureParams {
                dest_size: Some(vec2(s, s)),
                ..Default::default()
            },
        );
    }

    let f = sprites.font();
    let name_color = if affordable { TEXT } else { TEXT_DIM };
    let nw = text_width(b.label, 16.0, f);
    text(
        b.label,
        r.x + (r.w - nw) / 2.0,
        r.y + r.h - 17.0,
        16.0,
        name_color,
        f,
    );

    let price_s = format!("${price}");
    let pw = text_width(&price_s, 16.0, f);
    text(
        &price_s,
        r.x + (r.w - pw) / 2.0,
        r.y + r.h - 3.0,
        16.0,
        if affordable { GOOD } else { BAD },
        f,
    );

    // keybind chip
    let key = b.key.to_string();
    text(&key, r.x + r.w - 13.0, r.y + 15.0, 14.0, ACCENT, f);
}
