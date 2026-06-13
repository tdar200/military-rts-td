//! Shared visual theme — the "HOLOGRAPHIC TACTICAL COMMAND" palette.
//!
//! A single coherent sci-fi register: a deep-space near-black field lit by
//! **cyan/teal holographic glow**, which carries the "live/important" role that
//! gold used to (credits, active build, selection, menu rules). A restrained
//! **warm red** is reserved for hostile/alert signals (enemy faction, incoming
//! wave, low HP, defeat) so threat reads instantly and stays hue-distinct from
//! the cyan accent and the green "good" indicator. Resting borders stay a cool,
//! dim steel so the cyan glow remains a highlight rather than an everywhere line.
//!
//! The constant *names* are kept stable across the theme overhaul (e.g. `GOLD`,
//! `DECO_GOLD`, `PARCHMENT`, the `MAP_*`/`REGAL_*` families) so every call site
//! recolors at once; only their *values* changed from the old parchment register
//! to this holographic one. Every color the shell draws lives here as a token so
//! the battlefield and the HUD stay one system.

use macroquad::prelude::*;

// --- backdrops ---
/// Title/menu clear color — the deepest space-black-blue. Also the letterbox
/// outside the battlefield play area.
pub const BASE_CHARCOAL: Color = color_u8!(6, 9, 16, 255);
/// Battlefield ground tile (base shade) — dark blue-slate.
pub const GROUND: Color = color_u8!(10, 16, 26, 255);
/// Alternating ground tile — a step lighter so the grid reads as a surface.
pub const GROUND_ALT: Color = color_u8!(14, 22, 34, 255);
/// Coarse macro-sector overlay, breaking the field into 4x4 blocks (translucent).
pub const GROUND_MACRO: Color = color_u8!(18, 34, 52, 40);
/// Tile grid over the ground — cyan, low alpha, reads as a holographic graticule.
pub const GRID: Color = color_u8!(40, 120, 150, 70);
/// Brighter grid pulse line (used for the moving graticule sweep on the board).
pub const GRID_HOT: Color = color_u8!(70, 200, 235, 110);
/// Impassable terrain (walls) — dark crystalline body (middle face).
pub const TERRAIN_WALL: Color = color_u8!(14, 30, 44, 255);
/// Lit top face of a wall/pylon block.
pub const WALL_TOP: Color = color_u8!(24, 90, 110, 255);
/// Bright highlight line along a wall's top edge.
pub const WALL_HI: Color = color_u8!(64, 220, 235, 255);
/// Wall outline / dark groove.
pub const WALL_EDGE: Color = color_u8!(3, 5, 10, 255);
/// Soft drop-shadow under a unit/building (translucent, stacked for soft edge).
pub const PIECE_SHADOW: Color = color_u8!(0, 0, 0, 90);

// --- panels ---
/// Primary HUD panel fill (dark translucent glass over the map).
pub const PANEL: Color = color_u8!(10, 18, 28, 225);
/// Button rest / minimap inner field — one step up from `PANEL`.
pub const PANEL_RAISED: Color = color_u8!(16, 28, 42, 255);
/// Button hover — a cool steel lift.
pub const PANEL_HOVER: Color = color_u8!(24, 52, 70, 255);
/// Active/selected build button — a cyan-saturated fill (a *hue* jump from the
/// cooler rest/hover panels, so "selected" reads at a glance).
pub const PANEL_ACTIVE: Color = color_u8!(16, 70, 86, 255);

// --- structure / accent ---
/// Resting border + separators on all in-match HUD panels (kept cool/dim so the
/// cyan glow stays a highlight rather than the everywhere-border).
pub const BORDER_NEUTRAL: Color = color_u8!(40, 78, 96, 255);
/// The primary holographic accent ("HOLO") — used where something is
/// live/important (credits value, active build, minimap viewport, menu rules).
/// Kept under the historical name `GOLD` so existing call sites recolor cyan.
pub const GOLD: Color = color_u8!(64, 220, 235, 255);
/// Brightest holographic highlight — wordmark, scanline crest, brightest cue.
pub const GOLD_HI: Color = color_u8!(150, 245, 255, 255);
/// Shadowed holo for the dark side of a glowing bevel (panel/tooltip rims).
pub const GOLD_DK: Color = color_u8!(24, 90, 110, 255);
/// Dark inset well behind medallions / under HUD chrome (the deepest void).
pub const WELL: Color = color_u8!(3, 5, 10, 255);

// --- divider anchor ---
/// Structural divider — selection-panel gutter, minimap terrain, command-bar
/// group divider. Kept under the historical name `OLIVE`; now a dim holo steel.
pub const OLIVE: Color = color_u8!(30, 64, 80, 255);

// --- text ---
/// Primary text on panels — cool off-white, high contrast on the dark glass.
pub const TEXT: Color = color_u8!(206, 232, 240, 255);
/// Secondary captions/labels — never carries a number read at a glance.
pub const TEXT_DIM: Color = color_u8!(120, 158, 174, 255);

// --- semantic state ---
/// Positive: power surplus, high HP, affordable price, victory.
pub const GOOD: Color = color_u8!(80, 230, 160, 255);
/// Caution: next-wave countdown, paused, mid HP. Warm amber — reads as alert
/// against the cyan field and stays hue-distinct from `GOLD`.
pub const WARN: Color = color_u8!(240, 176, 64, 255);
/// Threat: incoming wave, power deficit, unaffordable, low HP, defeat, enemy.
pub const BAD: Color = color_u8!(240, 78, 70, 255);

// --- factions / on-map ---
/// Player faction tint — a bright friendly cyan hologram.
pub const TEAM_PLAYER: Color = color_u8!(70, 200, 235, 255);
/// Alien (enemy) faction tint — a hostile warm red, the standard "incoming
/// threat" signal in a cyan UI and hue-distinct from `GOOD` and `GRID`.
pub const TEAM_ENEMY: Color = color_u8!(240, 96, 80, 255);
/// Neutral / unowned planet tint — a dim steel-grey, distinct from every civ
/// colour and from open space, so unclaimed territory reads as "up for grabs".
pub const CIV_NEUTRAL: Color = color_u8!(120, 130, 142, 255);
/// Per-civ identity palette for N-civ conquest. Index by `CivId.0`; eight
/// hue-distinct holographic tints so civs 0..7 each read as a separate faction.
/// Civ 0 keeps the friendly cyan (`TEAM_PLAYER`) and civ 1 the hostile red
/// (`TEAM_ENEMY`) so existing 2-civ matches look unchanged.
pub const CIV_COLORS: [Color; 8] = [
    color_u8!(70, 200, 235, 255),  // 0 cyan (player)
    color_u8!(240, 96, 80, 255),   // 1 red (classic enemy)
    color_u8!(120, 230, 140, 255), // 2 green
    color_u8!(240, 200, 70, 255),  // 3 amber
    color_u8!(190, 130, 245, 255), // 4 violet
    color_u8!(245, 150, 70, 255),  // 5 orange
    color_u8!(245, 130, 200, 255), // 6 magenta
    color_u8!(130, 245, 230, 255), // 7 teal
];

/// Resolves the holographic identity colour for civ `id`. Wraps past 8 civs so
/// it never panics; the engine only spawns up to ~6, well inside the palette.
#[must_use]
pub const fn civ_color(id: u16) -> Color {
    CIV_COLORS[(id as usize) % CIV_COLORS.len()]
}

/// On-map selection ring — the brightest holo highlight.
pub const SELECT_RING: Color = GOLD_HI;
/// Combat tracer line — a bright cyan laser bolt (translucent).
pub const TRACER: Color = color_u8!(150, 245, 255, 220);
/// Health-bar track (behind the colored fill), on-map and in the selection panel.
pub const HP_TRACK: Color = color_u8!(16, 30, 40, 255);
/// Energy-shield bar tint — blue-violet, distinct from HP and the team cyan.
pub const SHIELD: Color = color_u8!(120, 180, 255, 255);

// --- holographic FX tokens ---
/// Translucent cyan bloom fill — stack a few expanding copies for a cheap glow.
pub const HOLO_GLOW: Color = color_u8!(64, 220, 235, 70);
/// Moving scanline sweep tint over panels/pieces/board.
pub const SCANLINE: Color = color_u8!(120, 245, 255, 22);
/// Translucent warm-red bloom for enemy/incoming alert glows.
pub const ALERT_GLOW: Color = color_u8!(240, 96, 80, 90);

// --- REGAL register (now the holographic command-console menu surfaces) ---
/// Menu field base — deep space (kept under the `REGAL_BG` name).
pub const REGAL_BG: Color = color_u8!(8, 12, 20, 255);
/// Darkest corner of the menu vignette.
pub const REGAL_BG_LO: Color = color_u8!(3, 5, 10, 255);
/// Lit center of the menu field.
pub const REGAL_BG_HI: Color = color_u8!(14, 24, 38, 255);
/// Console panel fill (was parchment) — dark holographic glass.
pub const PARCHMENT: Color = color_u8!(12, 22, 34, 235);
/// Lit top of a console panel.
pub const PARCHMENT_HI: Color = color_u8!(20, 36, 52, 235);
/// Shaded lower console panel.
pub const PARCHMENT_LO: Color = color_u8!(8, 16, 26, 235);
/// Console panel edge / frame seat.
pub const PARCHMENT_EDGE: Color = color_u8!(40, 78, 96, 255);
/// Primary console text (was sepia ink) — cool off-white.
pub const INK: Color = color_u8!(206, 232, 240, 255);
/// Muted console caption text.
pub const INK_DIM: Color = color_u8!(120, 158, 174, 255);
/// Ornament shadow line (was bronze) — dim holo.
pub const BRONZE: Color = color_u8!(24, 90, 110, 255);
/// Deco accent for ornaments & frames — the primary holo cyan.
pub const DECO_GOLD: Color = color_u8!(64, 220, 235, 255);
/// Lit deco-cyan highlight.
pub const DECO_GOLD_HI: Color = color_u8!(150, 245, 255, 255);

// --- board terrain tones (holographic floor) ---
/// Floor base.
pub const MAP_GRASS: Color = color_u8!(10, 16, 26, 255);
/// Floor variant (a step lighter).
pub const MAP_GRASS2: Color = color_u8!(14, 22, 34, 255);
/// Floor sector accent (faint cyan-tinted).
pub const MAP_PLAINS: Color = color_u8!(16, 28, 40, 255);
/// Floor low band (darker).
pub const MAP_FOREST: Color = color_u8!(8, 14, 22, 255);
/// Cool holographic center-bloom wash unifying the board.
pub const VARNISH: Color = color_u8!(64, 220, 235, 30);

/// Health-bar fill color by remaining fraction: green → amber → red. Used by both
/// the on-map bars and the selection panel so they read identically.
#[must_use]
pub fn hp_color(frac: f32) -> Color {
    if frac > 0.5 {
        GOOD
    } else if frac > 0.25 {
        WARN
    } else {
        BAD
    }
}

/// A subtle alpha multiplier (0..1) that makes "live" holographic elements
/// flicker faintly. Frame-rate independent (driven by wall-clock `get_time`).
#[must_use]
pub fn holo_flicker() -> f32 {
    const FLOOR: f32 = 0.86;
    #[allow(
        clippy::cast_possible_truncation,
        reason = "wall-clock time only drives a cosmetic flicker; precision loss is irrelevant"
    )]
    let t = get_time() as f32;
    FLOOR + (1.0 - FLOOR) * (t * 9.0).sin().abs()
}

/// Returns `base` with its alpha scaled by `mul` (clamped 0..1). Handy for
/// pulsing/flickering a token without defining a new constant.
#[must_use]
pub fn with_alpha(base: Color, mul: f32) -> Color {
    Color {
        a: (base.a * mul).clamp(0.0, 1.0),
        ..base
    }
}

/// Draws a cheap fake-bloom glow: `layers` expanding translucent outlines of
/// `color` around the rectangle `(x, y, w, h)`. Cyan glow without a shader.
pub fn glow_rect(x: f32, y: f32, w: f32, h: f32, color: Color, layers: u8) {
    for layer in 1..=layers {
        let grow = f32::from(layer) * 2.0;
        let alpha = color.a * (1.0 - f32::from(layer) / f32::from(layers + 1));
        draw_rectangle_lines(
            x - grow,
            y - grow,
            w + grow * 2.0,
            h + grow * 2.0,
            1.5,
            Color { a: alpha, ..color },
        );
    }
}

/// Draws a framed "pill" chip: a dark inset well, a bloom halo, and a 1.5px
/// outline in `outline`. Used for HUD readout chips (alert pill, ribbon group
/// backings) so they share one seated-glass look.
pub fn pill(x: f32, y: f32, w: f32, h: f32, glow: Color, outline: Color) {
    draw_rectangle(x, y, w, h, WELL);
    glow_rect(x, y, w, h, glow, 3);
    draw_rectangle_lines(x, y, w, h, 1.5, outline);
}

/// Draws a single horizontal scanline sweeping down the rectangle over time.
pub fn scanline(x: f32, y: f32, w: f32, h: f32) {
    #[allow(
        clippy::cast_possible_truncation,
        reason = "wall-clock time only drives a cosmetic sweep position"
    )]
    let phase = (get_time() as f32 * 0.35).fract();
    let sy = y + phase * h;
    draw_rectangle(x, sy, w, 1.5, SCANLINE);
}
