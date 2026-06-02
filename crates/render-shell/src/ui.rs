//! In-game UI: a top resource ribbon and a bottom command bar of build/train
//! buttons, in the "FIELD COMMAND" theme (see [`crate::theme`]).
//!
//! The in-match HUD is the *lean* register: gunmetal panels with cool neutral
//! borders, gold reserved for live/important elements, an olive-drab military
//! anchor, and button states that read by hue (warm active vs cool rest/hover)
//! rather than brightness alone. Buttons emit the same `Command`s as the hotkeys,
//! so the UI is just another input source.

use crate::sprites::Sprites;
use crate::theme::{
    hp_color, BAD, BORDER_NEUTRAL, BRONZE, DECO_GOLD, DECO_GOLD_HI, GOLD, GOLD_DK, GOLD_HI, GOOD,
    GROUND_ALT, HP_TRACK, OLIVE, PANEL, PANEL_ACTIVE, PANEL_HOVER, PANEL_RAISED, SHIELD,
    TEAM_ENEMY, TEAM_PLAYER, TEXT, TEXT_DIM, WARN, WELL,
};
use macroquad::prelude::*;
use rts_core::fixed::Fixed;
use rts_core::game::sim::{Command, EntityId, EntityKindView, PlayerId, Sim};
use rts_core::game::stats::{BuildingKind, UnitKind};

const HUMAN: PlayerId = PlayerId(0);
/// Height of the top resource bar.
pub const TOP_BAR_H: f32 = 38.0;
/// Height of the bottom command bar.
pub const CMD_BAR_H: f32 = 76.0;
/// Gap separating the build-button group from the unit-button group.
const GROUP_GAP: f32 = 22.0;

/// Desaturated tint for an unaffordable build icon.
const ICON_DISABLED: Color = color_u8!(106, 101, 90, 255);

/// Era name labels for the HUD indicator, indexed by era number (0–3).
const ERA_NAMES: [&str; 4] = ["Modern", "Orbital", "Interplanetary", "Interstellar"];

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

fn layout() -> [Button; 10] {
    let w = 104.0;
    let h = CMD_BAR_H - 16.0;
    let pad = 6.0;
    let y = screen_height() - CMD_BAR_H + 8.0;
    let mk = |i: usize, label, key, action| {
        // The unit group starts at index 7 (after 7 build buttons 0–6).
        let gap = if i >= 7 { GROUP_GAP } else { 0.0 };
        Button {
            rect: Rect::new(12.0 + i as f32 * (w + pad) + gap, y, w, h),
            label,
            key,
            action,
        }
    };
    [
        mk(0, "Reactor", 'P', Action::Build(BuildingKind::PowerPlant)),
        mk(1, "Extractor", 'R', Action::Build(BuildingKind::Refinery)),
        mk(2, "Hangar", 'B', Action::Build(BuildingKind::Barracks)),
        mk(
            3,
            "Laser Turret",
            'G',
            Action::Build(BuildingKind::GunTurret),
        ),
        mk(4, "Flak Turret", 'A', Action::Build(BuildingKind::AaTurret)),
        mk(5, "Lab", 'L', Action::Build(BuildingKind::ResearchLab)),
        mk(
            6,
            "Antimatter",
            'N',
            Action::Build(BuildingKind::AntimatterPlant),
        ),
        mk(7, "Infantry", 'T', Action::Train(UnitKind::Infantry)),
        mk(8, "Gunship", 'H', Action::Train(UnitKind::Helicopter)),
        mk(9, "Capital", 'C', Action::Train(UnitKind::Capital)),
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

/// Draws all HUD layers: minimap, resource bar, selection panel, command bar.
pub fn draw(
    sim: &Sim,
    build_mode: Option<BuildingKind>,
    paused: bool,
    selected: Option<EntityId>,
    sprites: &Sprites,
) {
    draw_minimap(sim);
    draw_top_bar(sim, paused, sprites);
    draw_selection_panel(sim, selected, sprites);
    draw_command_bar(sim, build_mode, sprites);
}

/// L-shaped gold corner brackets — the Civ-style framed-panel filigree.
fn corner_brackets(x: f32, y: f32, w: f32, h: f32, leg: f32, col: Color) {
    let thick = 2.0;
    // top-left
    draw_rectangle(x, y, leg, thick, col);
    draw_rectangle(x, y, thick, leg, col);
    // top-right
    draw_rectangle(x + w - leg, y, leg, thick, col);
    draw_rectangle(x + w - thick, y, thick, leg, col);
    // bottom-left
    draw_rectangle(x, y + h - thick, leg, thick, col);
    draw_rectangle(x, y + h - leg, thick, leg, col);
    // bottom-right
    draw_rectangle(x + w - leg, y + h - thick, leg, thick, col);
    draw_rectangle(x + w - thick, y + h - leg, thick, leg, col);
}

/// Civ-style gilded panel chrome: dark fill, an inner neutral hairline, a gold rim
/// with a **brass bevel** (lit top/left, shadowed bottom/right) for dimensional
/// relief, and gold corner brackets — an ornate frame that reads as premium rather
/// than a flat sticker.
fn fill_panel(x: f32, y: f32, w: f32, h: f32) {
    draw_rectangle(x, y, w, h, PANEL);
    draw_rectangle_lines(x + 3.0, y + 3.0, w - 6.0, h - 6.0, 1.0, BORDER_NEUTRAL);
    draw_rectangle_lines(x, y, w, h, 1.5, GOLD);
    // Brass bevel: lit top + left, shadowed bottom + right.
    draw_line(x, y + 0.5, x + w, y + 0.5, 1.0, GOLD_HI);
    draw_line(x + 0.5, y, x + 0.5, y + h, 1.0, GOLD_HI);
    draw_line(x, y + h - 0.5, x + w, y + h - 0.5, 1.0, GOLD_DK);
    draw_line(x + w - 0.5, y, x + w - 0.5, y + h, 1.0, GOLD_DK);
    corner_brackets(x, y, w, h, 12.0, GOLD_HI);
}

/// A gold yield-coin glyph (credits): a struck coin with a lit face and an
/// embossed mark, rather than a hollow donut.
fn icon_coin(cx: f32, cy: f32, r: f32) {
    draw_circle(cx, cy, r, GOLD);
    draw_circle(cx, cy, r - 1.5, GOLD_HI);
    draw_rectangle(cx - 1.0, cy - r * 0.45, 2.0, r * 0.9, GOLD_DK);
}

/// A lightning-bolt glyph (power), built from two triangles, in `col`.
fn icon_bolt(cx: f32, cy: f32, s: f32, col: Color) {
    draw_triangle(
        vec2(cx + s * 0.15, cy - s),
        vec2(cx - s * 0.55, cy + s * 0.15),
        vec2(cx + s * 0.2, cy + s * 0.05),
        col,
    );
    draw_triangle(
        vec2(cx - s * 0.15, cy + s),
        vec2(cx + s * 0.55, cy - s * 0.15),
        vec2(cx - s * 0.2, cy - s * 0.05),
        col,
    );
}

/// Stacked military rank chevrons (units).
fn icon_chevrons(cx: f32, cy: f32, s: f32, col: Color) {
    for i in 0..2 {
        let yy = cy - s * 0.35 + i as f32 * s * 0.55;
        draw_line(cx - s * 0.6, yy + s * 0.3, cx, yy - s * 0.15, 2.5, col);
        draw_line(cx, yy - s * 0.15, cx + s * 0.6, yy + s * 0.3, 2.5, col);
    }
}

/// A circular medallion holding a tinted sprite, rimmed in `ring`. Gold rings are
/// reserved for live elements (active build, ribbon coin, selection); resting
/// buttons pass a neutral ring so gold stays meaningful.
fn medallion(cx: f32, cy: f32, r: f32, tex: Option<&Texture2D>, tint: Color, ring: Color) {
    draw_circle(cx, cy, r, WELL);
    if let Some(tex) = tex {
        let d = r * 1.4;
        draw_texture_ex(
            tex,
            cx - d / 2.0,
            cy - d / 2.0,
            tint,
            DrawTextureParams {
                dest_size: Some(vec2(d, d)),
                ..Default::default()
            },
        );
    }
    draw_circle_lines(cx, cy, r, 2.0, ring);
}

/// Display name + one-line role for an entity, themed by faction (Human P0 vs the
/// Alien AI). Stats are identical across factions — only the cosmetic name and
/// blurb differ.
fn kind_name_role(kind: EntityKindView, owner: PlayerId) -> (&'static str, &'static str) {
    if owner == HUMAN {
        human_name_role(kind)
    } else {
        // Any non-human owner (P1 today) is the alien faction.
        alien_name_role(kind)
    }
}

const fn human_name_role(kind: EntityKindView) -> (&'static str, &'static str) {
    match kind {
        EntityKindView::Unit(UnitKind::Infantry) => ("Infantry", "Cheap anti-infantry"),
        EntityKindView::Unit(UnitKind::Tank) => ("Tank", "Heavy armour, anti-ground"),
        EntityKindView::Unit(UnitKind::AntiArmor) => {
            ("Anti-Armor", "Beats tanks, weak vs infantry")
        }
        EntityKindView::Unit(UnitKind::Helicopter) => ("Gunship", "Air — only flak can hit it"),
        EntityKindView::Unit(UnitKind::Capital) => ("Capital Ship", "Era-4 heavy warship"),
        EntityKindView::Building(BuildingKind::CommandCenter) => {
            ("Command Nexus", "Your base — protect it")
        }
        EntityKindView::Building(BuildingKind::PowerPlant) => ("Reactor", "Supplies power"),
        EntityKindView::Building(BuildingKind::Refinery) => ("Extractor", "+credits while powered"),
        EntityKindView::Building(BuildingKind::Barracks) => ("Hangar", "Trains units"),
        EntityKindView::Building(BuildingKind::GunTurret) => {
            ("Laser Turret", "Anti-ground defence")
        }
        EntityKindView::Building(BuildingKind::AaTurret) => ("Flak Turret", "Anti-air defence"),
        EntityKindView::Building(BuildingKind::Wall) => ("Barrier", "Blocks movement"),
        EntityKindView::Building(BuildingKind::ResearchLab) => {
            ("Research Lab", "Researches upgrades")
        }
        EntityKindView::Building(BuildingKind::AntimatterPlant) => {
            ("Antimatter Plant", "Produces antimatter")
        }
    }
}

const fn alien_name_role(kind: EntityKindView) -> (&'static str, &'static str) {
    match kind {
        EntityKindView::Unit(UnitKind::Infantry) => ("Drone", "Cheap anti-infantry swarm"),
        EntityKindView::Unit(UnitKind::Tank) => ("Crawler", "Heavy armour, anti-ground"),
        EntityKindView::Unit(UnitKind::AntiArmor) => ("Lancer", "Beats armour, weak vs swarm"),
        EntityKindView::Unit(UnitKind::Helicopter) => ("Wasp", "Flyer — only flak can hit it"),
        EntityKindView::Unit(UnitKind::Capital) => ("Leviathan", "Era-4 alien warship"),
        EntityKindView::Building(BuildingKind::CommandCenter) => {
            ("Core Node", "Alien core — destroy it")
        }
        EntityKindView::Building(BuildingKind::PowerPlant) => {
            ("Power Node", "Powers the alien base")
        }
        EntityKindView::Building(BuildingKind::Refinery) => {
            ("Extractor", "Feeds the alien economy")
        }
        EntityKindView::Building(BuildingKind::Barracks) => ("Assembler", "Builds alien units"),
        EntityKindView::Building(BuildingKind::GunTurret) => ("Sentry", "Anti-ground defence"),
        EntityKindView::Building(BuildingKind::AaTurret) => ("Interceptor", "Anti-air defence"),
        EntityKindView::Building(BuildingKind::Wall) => ("Barrier", "Blocks movement"),
        EntityKindView::Building(BuildingKind::ResearchLab) => {
            ("Fabricator", "Researches alien upgrades")
        }
        EntityKindView::Building(BuildingKind::AntimatterPlant) => {
            ("Singularity", "Produces antimatter")
        }
    }
}

const fn action_kind(action: Action) -> EntityKindView {
    match action {
        Action::Build(k) => EntityKindView::Building(k),
        Action::Train(k) => EntityKindView::Unit(k),
    }
}

fn draw_selection_panel(sim: &Sim, selected: Option<EntityId>, sprites: &Sprites) {
    let Some(id) = selected else { return };
    let Some(view) = sim.views().into_iter().find(|v| v.id == id) else {
        return;
    };
    let (name, role) = kind_name_role(view.kind, view.owner);
    let panel_w = 252.0;
    let panel_h = 66.0;
    let px = 12.0;
    let py = screen_height() - CMD_BAR_H - panel_h - 10.0;
    fill_panel(px, py, panel_w, panel_h);
    // Olive dossier gutter behind the medallion (military register).
    draw_rectangle(px + 5.0, py + 5.0, 3.0, panel_h - 10.0, OLIVE);
    let owned = view.owner == HUMAN;
    let team = if owned { TEAM_PLAYER } else { TEAM_ENEMY };
    let texture = match view.kind {
        EntityKindView::Building(k) => sprites.building(k),
        EntityKindView::Unit(k) => sprites.unit(k),
    };
    // Medallion: native-color sprite, team-colored ring for allegiance.
    medallion(px + 34.0, py + panel_h / 2.0, 24.0, texture, WHITE, team);
    let text_x = px + 66.0;
    text(name, text_x, py + 24.0, 20.0, TEXT, sprites.font_bold());
    // Thin olive separator (the gilded frame already carries the brass).
    draw_rectangle(
        text_x,
        py + 28.0,
        panel_w - (text_x - px) - 12.0,
        1.0,
        OLIVE,
    );
    text(role, text_x, py + 41.0, 14.0, TEXT_DIM, sprites.font());
    let frac = (view.hp.to_bits() as f32 / view.max_hp.to_bits() as f32).clamp(0.0, 1.0);
    let bar_w = panel_w - 84.0;
    let bar_y = py + 50.0;
    // Numeric HP readout, right-justified above the bar.
    let hp = view.hp.to_bits() / 65536;
    let max_hp = view.max_hp.to_bits() / 65536;
    let hp_s = format!("{hp}/{max_hp}");
    let fb = sprites.font();
    text(
        &hp_s,
        text_x + bar_w - text_width(&hp_s, 14.0, fb),
        py + 24.0,
        14.0,
        TEXT_DIM,
        fb,
    );
    draw_rectangle(text_x, bar_y, bar_w, 7.0, HP_TRACK);
    draw_rectangle(text_x, bar_y, bar_w * frac, 7.0, hp_color(frac));
    draw_rectangle_lines(text_x, bar_y, bar_w, 7.0, 1.0, BORDER_NEUTRAL);
}

fn draw_minimap(sim: &Sim) {
    let map_w = f32::from(sim.map().width());
    let map_h = f32::from(sim.map().height());
    let mm_w = 188.0;
    let mm_h = mm_w * map_h / map_w;
    let origin_x = screen_width() - mm_w - 12.0;
    let origin_y = TOP_BAR_H + 10.0;
    // Restrained frame: gunmetal fill + terrain field, not the full gilded chrome.
    draw_rectangle(origin_x, origin_y, mm_w, mm_h, PANEL);
    draw_rectangle(
        origin_x + 2.0,
        origin_y + 2.0,
        mm_w - 4.0,
        mm_h - 4.0,
        GROUND_ALT,
    );
    let scale_x = (mm_w - 4.0) / map_w;
    let scale_y = (mm_h - 4.0) / map_h;
    let field_x = origin_x + 2.0;
    let field_y = origin_y + 2.0;
    for ty in 0..sim.map().height() {
        for tx in 0..sim.map().width() {
            if !sim
                .map()
                .tile(i32::from(tx), i32::from(ty))
                .unwrap()
                .passable
            {
                draw_rectangle(
                    field_x + f32::from(tx) * scale_x,
                    field_y + f32::from(ty) * scale_y,
                    scale_x + 1.0,
                    scale_y + 1.0,
                    OLIVE,
                );
            }
        }
    }
    for v in sim.views() {
        let col = if v.owner == HUMAN {
            TEAM_PLAYER
        } else {
            TEAM_ENEMY
        };
        let dot_x = field_x + (v.pos.x.to_bits() as f32 / 65536.0) * scale_x;
        let dot_y = field_y + (v.pos.y.to_bits() as f32 / 65536.0) * scale_y;
        // Dark backing makes the faction dot pop against the terrain.
        draw_rectangle(dot_x - 3.0, dot_y - 3.0, 6.0, 6.0, WELL);
        draw_rectangle(dot_x - 2.0, dot_y - 2.0, 4.0, 4.0, col);
    }
    // Ornate gold deco frame (brass bevel) — matches the map + menu frames.
    draw_rectangle(origin_x, origin_y, mm_w, 2.0, DECO_GOLD_HI);
    draw_rectangle(origin_x, origin_y, 2.0, mm_h, DECO_GOLD_HI);
    draw_rectangle(origin_x, origin_y + mm_h - 2.0, mm_w, 2.0, GOLD_DK);
    draw_rectangle(origin_x + mm_w - 2.0, origin_y, 2.0, mm_h, GOLD_DK);
    draw_rectangle_lines(
        origin_x + 3.0,
        origin_y + 3.0,
        mm_w - 6.0,
        mm_h - 6.0,
        1.0,
        color_u8!(201, 164, 76, 102),
    );
    draw_rectangle_lines(
        origin_x - 1.0,
        origin_y - 1.0,
        mm_w + 2.0,
        mm_h + 2.0,
        1.0,
        BRONZE,
    );
}

fn draw_tooltip(button: Rect, action: Action, price: i64, sprites: &Sprites) {
    let (name, role) = kind_name_role(action_kind(action), HUMAN);
    let cost_s = format!("Cost  ${price}");
    let font = sprites.font();
    let font_bold = sprites.font_bold();
    let tip_w = text_width(name, 17.0, font_bold)
        .max(text_width(role, 14.0, font))
        .max(text_width(&cost_s, 14.0, font))
        + 16.0;
    let tip_w = tip_w + 4.0;
    let tip_h = 60.0;
    // Clamp so the tooltip never runs off the right edge.
    let tip_x = button.x.min(screen_width() - tip_w - 4.0).max(4.0);
    let tip_y = button.y - tip_h - 6.0;
    // Beveled chrome consistent with the gilded panels.
    draw_rectangle(tip_x, tip_y, tip_w, tip_h, WELL);
    draw_rectangle_lines(
        tip_x + 3.0,
        tip_y + 3.0,
        tip_w - 6.0,
        tip_h - 6.0,
        1.0,
        BORDER_NEUTRAL,
    );
    draw_rectangle_lines(tip_x, tip_y, tip_w, tip_h, 1.5, GOLD);
    draw_line(tip_x, tip_y + 0.5, tip_x + tip_w, tip_y + 0.5, 1.0, GOLD_HI);
    draw_line(
        tip_x,
        tip_y + tip_h - 0.5,
        tip_x + tip_w,
        tip_y + tip_h - 0.5,
        1.0,
        GOLD_DK,
    );
    text(name, tip_x + 10.0, tip_y + 19.0, 17.0, TEXT, font_bold);
    text(role, tip_x + 10.0, tip_y + 36.0, 14.0, TEXT_DIM, font);
    text(&cost_s, tip_x + 10.0, tip_y + 53.0, 14.0, GOOD, font);
}

/// A thin neutral divider between ribbon yields (gold is reserved for values).
fn ribbon_divider(x: f32) {
    draw_rectangle(x, 11.0, 1.0, TOP_BAR_H - 22.0, BORDER_NEUTRAL);
}

/// Civ-style yield ribbon: a gilded strip of icon+number pairs, with a framed
/// alert pill for the incoming wave.
fn draw_top_bar(sim: &Sim, paused: bool, sprites: &Sprites) {
    let fb = sprites.font_bold();
    draw_rectangle(0.0, 0.0, screen_width(), TOP_BAR_H, PANEL);
    // Seated, brass-beveled bottom edge: dark groove + deco-gold rule + lit line.
    draw_rectangle(0.0, TOP_BAR_H - 4.0, screen_width(), 3.0, DECO_GOLD);
    draw_rectangle(0.0, TOP_BAR_H - 4.0, screen_width(), 1.0, DECO_GOLD_HI);
    draw_rectangle(0.0, TOP_BAR_H - 1.0, screen_width(), 1.0, WELL);

    // CREDITS — the headline yield: gold coin + large gold value.
    let mut x = 14.0;
    icon_coin(x + 7.0, 18.0, 8.0);
    x += 22.0;
    let credits = (sim.credits(HUMAN).to_bits() / 65536).to_string();
    text(&credits, x, 26.0, 22.0, GOLD_HI, fb);
    x += text_width(&credits, 22.0, fb) + 18.0;
    ribbon_divider(x - 9.0);

    // POWER — bolt + produced/consumed (secondary: smaller).
    icon_bolt(x + 5.0, 19.0, 8.0, WARN);
    x += 16.0;
    let (produced, consumed) = sim.power_balance(HUMAN);
    let power_color = if produced >= consumed { GOOD } else { BAD };
    let power = format!("{produced}/{consumed}");
    text(&power, x, 25.0, 18.0, power_color, fb);
    x += text_width(&power, 18.0, fb) + 18.0;
    ribbon_divider(x - 9.0);

    // UNITS — rank chevrons + count (secondary: smaller).
    icon_chevrons(x + 7.0, 19.0, 8.0, TEXT_DIM);
    x += 20.0;
    let units = sim.unit_count(HUMAN).to_string();
    text(&units, x, 25.0, 18.0, TEXT, fb);
    x += text_width(&units, 18.0, fb) + 18.0;
    ribbon_divider(x - 9.0);

    // ERA indicator — shows the human player's current era name.
    let era = ERA_NAMES[(sim.player_era(HUMAN) as usize).min(3)];
    text(era, x, 25.0, 18.0, DECO_GOLD, fb);
    x += text_width(era, 18.0, fb) + 18.0;
    ribbon_divider(x - 9.0);

    // ANTIMATTER — abbreviated "AM" to keep the ribbon compact; tinted in the
    // shield-teal so it's visually distinct from credits (gold) and power (amber).
    let am_label = "AM";
    text(am_label, x, 25.0, 18.0, SHIELD, fb);
    x += text_width(am_label, 18.0, fb) + 4.0;
    let am_val = (sim.antimatter(HUMAN).to_bits() / 65536).to_string();
    text(&am_val, x, 25.0, 18.0, SHIELD, fb);

    // Incoming-wave alert pill (right).
    if let Some(ticks) = sim.ticks_until_next_wave() {
        let secs = ticks / 30;
        let (label, col) = if secs <= 5 {
            ("INCOMING", BAD)
        } else {
            ("NEXT WAVE", WARN)
        };
        let s = format!("{label}  {secs}s");
        let tw = text_width(&s, 20.0, fb);
        let pill_w = tw + 22.0;
        let px = screen_width() - pill_w - 10.0;
        draw_rectangle(px, 5.0, pill_w, TOP_BAR_H - 12.0, WELL);
        draw_rectangle_lines(px, 5.0, pill_w, TOP_BAR_H - 12.0, 1.5, col);
        text(&s, px + 11.0, 25.0, 20.0, col, fb);
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
    // Brass-beveled top edge to match the ribbon and gilded map.
    draw_rectangle(0.0, top, screen_width(), 3.0, DECO_GOLD);
    draw_rectangle(0.0, top, screen_width(), 1.0, DECO_GOLD_HI);
    let buttons = layout();
    // Olive group divider between the build group and the unit group.
    let divider_x = (buttons[6].rect.x + buttons[6].rect.w + buttons[7].rect.x) / 2.0;
    draw_rectangle(divider_x - 0.5, top + 12.0, 1.0, CMD_BAR_H - 24.0, OLIVE);
    let pointer = {
        let (mx, my) = mouse_position();
        vec2(mx, my)
    };
    for b in &buttons {
        let price = cost(sim, b.action);
        let affordable = sim.credits(HUMAN) >= price;
        let active = build_active(b.action, build_mode);
        let hover = b.rect.contains(pointer);
        let price_int = price.to_bits() / 65536;
        draw_button(b, sprites, affordable, active, hover, price_int);
        if hover {
            draw_tooltip(b.rect, b.action, price_int, sprites);
        }
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
    // Fill reads by HUE: warm brass when active vs cool rest/hover.
    let bg = if active {
        PANEL_ACTIVE
    } else if hover {
        PANEL_HOVER
    } else {
        PANEL_RAISED
    };
    draw_rectangle(r.x, r.y, r.w, r.h, bg);
    // Gold is reserved for the ACTIVE build — everything else rests neutral, so
    // the selected tool is the one thing that glows.
    let (rim, ring) = if active {
        (GOLD_HI, GOLD_HI)
    } else if affordable {
        (BORDER_NEUTRAL, BORDER_NEUTRAL)
    } else {
        (BAD, BAD)
    };
    draw_rectangle_lines(r.x, r.y, r.w, r.h, 1.5, rim);
    if active {
        draw_rectangle(r.x, r.y, r.w, 2.0, GOLD_HI);
        corner_brackets(r.x, r.y, r.w, r.h, 10.0, GOLD_HI);
    }

    // Icon medallion (neutral ring at rest, gold only when active).
    let icon_tint = if affordable { WHITE } else { ICON_DISABLED };
    medallion(
        r.x + r.w / 2.0,
        r.y + 20.0,
        15.0,
        action_texture(sprites, b.action),
        icon_tint,
        ring,
    );

    let f = sprites.font();
    let name_color = if affordable { TEXT } else { TEXT_DIM };
    let nw = text_width(b.label, 15.0, f);
    text(
        b.label,
        r.x + (r.w - nw) / 2.0,
        r.y + r.h - 18.0,
        15.0,
        name_color,
        f,
    );

    let price_s = format!("${price}");
    let pw = text_width(&price_s, 15.0, f);
    text(
        &price_s,
        r.x + (r.w - pw) / 2.0,
        r.y + r.h - 5.0,
        15.0,
        if affordable { GOOD } else { BAD },
        f,
    );

    // Keybind chip — a small neutral plate (gold stays reserved for 'active').
    let key = b.key.to_string();
    draw_rectangle(r.x + r.w - 20.0, r.y + 4.0, 16.0, 14.0, WELL);
    draw_rectangle_lines(r.x + r.w - 20.0, r.y + 4.0, 16.0, 14.0, 1.0, BORDER_NEUTRAL);
    let kw = text_width(&key, 14.0, f);
    text(
        &key,
        r.x + r.w - 12.0 - kw / 2.0,
        r.y + 15.0,
        14.0,
        TEXT_DIM,
        f,
    );
}

#[cfg(test)]
mod tests {
    use super::{kind_name_role, HUMAN};
    use rts_core::game::sim::{EntityKindView, PlayerId};
    use rts_core::game::stats::{BuildingKind, UnitKind};

    const ALIEN: PlayerId = PlayerId(1);

    #[test]
    fn names_are_faction_aware() {
        let inf = EntityKindView::Unit(UnitKind::Infantry);
        assert_eq!(kind_name_role(inf, HUMAN).0, "Infantry");
        assert_eq!(kind_name_role(inf, ALIEN).0, "Drone");

        let cc = EntityKindView::Building(BuildingKind::CommandCenter);
        assert_eq!(kind_name_role(cc, HUMAN).0, "Command Nexus");
        assert_eq!(kind_name_role(cc, ALIEN).0, "Core Node");

        let heli = EntityKindView::Unit(UnitKind::Helicopter);
        assert_eq!(kind_name_role(heli, HUMAN).0, "Gunship");
        assert_eq!(kind_name_role(heli, ALIEN).0, "Wasp");

        // The blurb (.1) is part of the reskin — pin one so copy regressions fail.
        assert_eq!(
            kind_name_role(heli, ALIEN).1,
            "Flyer — only flak can hit it"
        );

        // Wall is intentionally "Barrier" for both factions.
        let wall = EntityKindView::Building(BuildingKind::Wall);
        assert_eq!(kind_name_role(wall, HUMAN).0, "Barrier");
        assert_eq!(kind_name_role(wall, ALIEN).0, "Barrier");
    }
}
