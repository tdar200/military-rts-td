//! In-game UI: a top resource bar and a bottom command bar of clickable
//! build/train buttons (with cost + affordability). Buttons feed the same
//! `Command` set as the hotkeys, so the UI is just another input source.

use crate::sprites::Sprites;
use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};

const HUMAN: PlayerId = PlayerId(0);
/// Height of the top resource bar.
pub const TOP_BAR_H: f32 = 30.0;
/// Height of the bottom command bar.
pub const CMD_BAR_H: f32 = 58.0;

#[derive(Clone, Copy)]
enum Action {
    Build(BuildingKind),
    Train(UnitKind),
}

struct Button {
    rect: Rect,
    label: &'static str,
    action: Action,
}

fn layout() -> [Button; 7] {
    let h = CMD_BAR_H - 12.0;
    let y = screen_height() - CMD_BAR_H + 6.0;
    let w = 116.0;
    let pad = 6.0;
    let mk = |i: usize, label, action| Button {
        rect: Rect::new(8.0 + i as f32 * (w + pad), y, w, h),
        label,
        action,
    };
    [
        mk(0, "Power [P]", Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Refinery [R]", Action::Build(BuildingKind::Refinery)),
        mk(2, "Barracks [B]", Action::Build(BuildingKind::Barracks)),
        mk(3, "Gun Trt [G]", Action::Build(BuildingKind::GunTurret)),
        mk(4, "AA Trt [A]", Action::Build(BuildingKind::AaTurret)),
        mk(5, "Infantry [T]", Action::Train(UnitKind::Infantry)),
        mk(6, "Heli [H]", Action::Train(UnitKind::Helicopter)),
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

fn action_texture(sprites: &Sprites, action: Action) -> Option<&Texture2D> {
    match action {
        Action::Build(k) => sprites.building(k),
        Action::Train(k) => sprites.unit(k),
    }
}

/// Draws the resource bar and the command bar.
pub fn draw(sim: &Sim, build_mode: Option<BuildingKind>, paused: bool, sprites: &Sprites) {
    draw_top_bar(sim, paused);
    draw_command_bar(sim, build_mode, sprites);
}

fn draw_top_bar(sim: &Sim, paused: bool) {
    draw_rectangle(
        0.0,
        0.0,
        screen_width(),
        TOP_BAR_H,
        Color::from_rgba(24, 28, 32, 235),
    );
    let (produced, consumed) = sim.power_balance(HUMAN);
    let wave = sim
        .ticks_until_next_wave()
        .map_or_else(String::new, |t| format!("    next wave {}s", t / 30));
    let credits = sim.credits(HUMAN).to_bits() / 65536;
    let text = format!(
        "Credits {credits}    Power {produced}/{consumed}    Units {}{wave}",
        sim.unit_count(HUMAN),
    );
    draw_text(&text, 8.0, 21.0, 22.0, WHITE);
    if paused {
        draw_text("PAUSED", screen_width() - 90.0, 21.0, 22.0, YELLOW);
    }
}

fn draw_command_bar(sim: &Sim, build_mode: Option<BuildingKind>, sprites: &Sprites) {
    let top = screen_height() - CMD_BAR_H;
    draw_rectangle(
        0.0,
        top,
        screen_width(),
        CMD_BAR_H,
        Color::from_rgba(24, 28, 32, 235),
    );
    let (mx, my) = mouse_position();
    let pointer = vec2(mx, my);
    for b in layout() {
        let price = cost(sim, b.action);
        let affordable = sim.credits(HUMAN) >= price;
        let active = build_active(b.action, build_mode);
        let hover = b.rect.contains(pointer);
        let bg = if active {
            Color::from_rgba(60, 140, 80, 255)
        } else if !affordable {
            Color::from_rgba(70, 40, 40, 255)
        } else if hover {
            Color::from_rgba(70, 80, 92, 255)
        } else {
            Color::from_rgba(46, 52, 60, 255)
        };
        draw_rectangle(b.rect.x, b.rect.y, b.rect.w, b.rect.h, bg);
        draw_rectangle_lines(b.rect.x, b.rect.y, b.rect.w, b.rect.h, 1.0, DARKGRAY);
        if let Some(texture) = action_texture(sprites, b.action) {
            let s = 30.0;
            draw_texture_ex(
                texture,
                b.rect.x + b.rect.w - s - 6.0,
                b.rect.y + (b.rect.h - s) / 2.0,
                WHITE,
                DrawTextureParams {
                    dest_size: Some(vec2(s, s)),
                    ..DrawTextureParams::default()
                },
            );
        }
        draw_text(b.label, b.rect.x + 6.0, b.rect.y + 18.0, 16.0, WHITE);
        let price_text = format!("${}", price.to_bits() / 65536);
        let price_color = if affordable { GREEN } else { RED };
        draw_text(
            &price_text,
            b.rect.x + 6.0,
            b.rect.y + 38.0,
            18.0,
            price_color,
        );
    }
}
