//! Shared visual theme — the "FIELD COMMAND" palette.
//!
//! A two-register system inspired by Civilization VII's gold-on-dark regality,
//! adapted to a military command HUD: a lean, functional **gunmetal + olive-drab**
//! in-match HUD where gold appears only on *live/important* elements, with the
//! brass/stencil flourish reserved for the menus. Civ VII's strengths are
//! borrowed (restrained palette, gold accent, refined panels) while its
//! documented flaws are avoided — we keep a *cool* structural neutral for resting
//! borders so gold stays meaningful, code state by hue + semantic color (not
//! grey-on-grey), and keep text density and contrast high.
//!
//! Every color the shell draws lives here as a token so the battlefield and the
//! HUD stay one coherent system.

use macroquad::prelude::*;

// --- backdrops ---
/// Title/menu clear color — the deepest charcoal (regal register). Also the
/// letterbox outside the battlefield play area.
pub const BASE_CHARCOAL: Color = color_u8!(14, 16, 19, 255);
/// Battlefield ground tile (base shade).
pub const GROUND: Color = color_u8!(26, 31, 20, 255);
/// Alternating ground tile — a visibly lighter olive so the checkerboard reads.
pub const GROUND_ALT: Color = color_u8!(38, 48, 28, 255);
/// Coarse macro-sector overlay, breaking the field into 4x4 blocks.
pub const GROUND_MACRO: Color = color_u8!(32, 38, 26, 40);
/// Tile grid over the ground — visible enough to read as a tactical surface.
pub const GRID: Color = color_u8!(70, 80, 60, 55);
/// Impassable terrain (walls) — olive-gray body (middle face).
pub const TERRAIN_WALL: Color = color_u8!(51, 56, 43, 255);
/// Lit top face of a wall block.
pub const WALL_TOP: Color = color_u8!(78, 85, 62, 255);
/// Bright highlight line along a wall's top edge.
pub const WALL_HI: Color = color_u8!(92, 102, 72, 255);
/// Wall outline / dark groove.
pub const WALL_EDGE: Color = color_u8!(20, 23, 15, 255);
/// Soft drop-shadow under a unit/building (translucent, stacked for soft edge).
pub const PIECE_SHADOW: Color = color_u8!(0, 0, 0, 70);

// --- panels ---
/// Primary HUD panel fill (gunmetal, slightly translucent over the map).
pub const PANEL: Color = color_u8!(21, 24, 28, 242);
/// Button rest / minimap inner field — one step up from `PANEL`.
pub const PANEL_RAISED: Color = color_u8!(28, 32, 38, 255);
/// Button hover — a cool steel lift, distinct in hue from the warm active fill.
pub const PANEL_HOVER: Color = color_u8!(42, 55, 68, 255);
/// Active/selected build button — a warm brass-brown (a *hue* jump from the cool
/// rest/hover greys, so "selected" reads at a glance, not by brightness alone).
pub const PANEL_ACTIVE: Color = color_u8!(58, 46, 18, 255);

// --- structure / accent ---
/// Resting border + separators on all in-match HUD panels (kept cool, so gold
/// stays a highlight rather than the everywhere-border).
pub const BORDER_NEUTRAL: Color = color_u8!(58, 68, 80, 255);
/// The gold accent — used sparingly, only where something is live/important
/// (credits value, active build, minimap viewport, keybind, menu rules).
pub const GOLD: Color = color_u8!(217, 169, 56, 255);
/// Brighter gold for menu wordmark/markers and the single brightest active cue.
pub const GOLD_HI: Color = color_u8!(242, 204, 102, 255);
/// Shadowed gold for the dark side of a brass bevel (panel/tooltip rims).
pub const GOLD_DK: Color = color_u8!(108, 84, 28, 255);
/// Dark inset well behind medallions / under HUD chrome.
pub const WELL: Color = color_u8!(9, 11, 14, 255);

// --- military anchor ---
/// Olive-drab — selection-panel gutter, minimap terrain, command-bar group
/// divider. Carries the "field command" identity brass cannot.
pub const OLIVE: Color = color_u8!(58, 64, 41, 255);

// --- text ---
/// Primary text on panels — warm off-white/parchment, high contrast on gunmetal.
pub const TEXT: Color = color_u8!(236, 228, 208, 255);
/// Secondary captions/labels — never carries a number read at a glance.
pub const TEXT_DIM: Color = color_u8!(163, 156, 134, 255);

// --- semantic state ---
/// Positive: power surplus, high HP, affordable price, victory.
pub const GOOD: Color = color_u8!(91, 196, 107, 255);
/// Caution: next-wave countdown, paused, mid HP. Pushed orange to separate it
/// from `GOLD` by hue.
pub const WARN: Color = color_u8!(240, 169, 60, 255);
/// Threat: incoming wave, power deficit, unaffordable, low HP, defeat, enemy.
pub const BAD: Color = color_u8!(226, 72, 61, 255);

// --- factions / on-map ---
/// Player faction tint — a desaturated steel-teal that sits in the olive/gold
/// palette instead of reading like a bright debug cyan.
pub const TEAM_PLAYER: Color = color_u8!(90, 147, 168, 255);
/// Alien (enemy) faction tint — an acidic chartreuse that reads as toxic and
/// synthetic, kept hue-distinct from the green full-HP bars (`GOOD`) and bright
/// against the darker terrain so enemy silhouettes stay legible.
pub const TEAM_ENEMY: Color = color_u8!(140, 210, 30, 255);
/// On-map selection ring — shares the active-gold language.
pub const SELECT_RING: Color = GOLD_HI;
/// Combat tracer line (warmed toward the gold family, translucent).
pub const TRACER: Color = color_u8!(255, 228, 140, 200);
/// Health-bar track (behind the colored fill), on-map and in the selection panel.
pub const HP_TRACK: Color = color_u8!(40, 46, 34, 255);

// --- REGAL register (Civ-VII menu): parchment + antiquarian field + deco gold ---
/// Deep antiquarian teal-green menu field.
pub const REGAL_BG: Color = color_u8!(21, 39, 31, 255);
/// Darkest corner of the menu vignette.
pub const REGAL_BG_LO: Color = color_u8!(10, 22, 17, 255);
/// Lit center of the menu field.
pub const REGAL_BG_HI: Color = color_u8!(33, 57, 45, 255);
/// Aged-paper panel fill (base).
pub const PARCHMENT: Color = color_u8!(233, 220, 189, 255);
/// Lit top of parchment.
pub const PARCHMENT_HI: Color = color_u8!(244, 234, 208, 255);
/// Shaded/aged lower parchment.
pub const PARCHMENT_LO: Color = color_u8!(214, 195, 154, 255);
/// Foxed/worn parchment edge.
pub const PARCHMENT_EDGE: Color = color_u8!(179, 156, 105, 255);
/// Dark sepia ink — serif text on parchment.
pub const INK: Color = color_u8!(44, 36, 21, 255);
/// Muted ink — captions on parchment.
pub const INK_DIM: Color = color_u8!(106, 88, 54, 255);
/// Antique bronze — ornament body / shadow line.
pub const BRONZE: Color = color_u8!(124, 92, 39, 255);
/// Antique deco gold — ornaments & frames (warmer than the HUD gold).
pub const DECO_GOLD: Color = color_u8!(201, 164, 76, 255);
/// Lit deco-gold highlight.
pub const DECO_GOLD_HI: Color = color_u8!(236, 202, 116, 255);

// --- warm Civ campaign-map terrain tones (square tiles painted, varnished) ---
/// Grassland base.
pub const MAP_GRASS: Color = color_u8!(93, 110, 60, 255);
/// Grassland variant (lighter).
pub const MAP_GRASS2: Color = color_u8!(107, 124, 69, 255);
/// Plains / steppe (yellow-green).
pub const MAP_PLAINS: Color = color_u8!(139, 137, 80, 255);
/// Forest (dark green).
pub const MAP_FOREST: Color = color_u8!(63, 85, 48, 255);
/// Warm sepia varnish wash unifying the board with the parchment register.
pub const VARNISH: Color = color_u8!(201, 164, 76, 36);

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
