//! Loads and holds the unit/building sprite textures.
//!
//! Sprites are white silhouettes (game-icons.net, CC BY 3.0 — see
//! `assets/CREDITS.md`) so they can be tinted to a team colour at draw time.
//! Loading is async because the browser fetches the PNGs over the network.

use macroquad::prelude::*;
use rts_core::game::stats::{BuildingKind, UnitKind};
use std::collections::HashMap;

const ALL: [&str; 11] = [
    "infantry",
    "tank",
    "anti_armor",
    "helicopter",
    "command_center",
    "power_plant",
    "refinery",
    "barracks",
    "gun_turret",
    "aa_turret",
    "wall",
];

const fn unit_name(kind: UnitKind) -> &'static str {
    match kind {
        UnitKind::Infantry => "infantry",
        // Capital reuses the tank sprite as a placeholder; update when a real
        // capital asset is available.
        UnitKind::Tank | UnitKind::Capital => "tank",
        UnitKind::AntiArmor => "anti_armor",
        UnitKind::Helicopter => "helicopter",
    }
}

const fn building_name(kind: BuildingKind) -> &'static str {
    match kind {
        BuildingKind::CommandCenter => "command_center",
        BuildingKind::PowerPlant => "power_plant",
        BuildingKind::Refinery => "refinery",
        // ResearchLab reuses the barracks sprite as a placeholder; when a real
        // research_lab asset is added, update this arm AND the `ALL` preload list.
        BuildingKind::Barracks | BuildingKind::ResearchLab => "barracks",
        BuildingKind::GunTurret => "gun_turret",
        BuildingKind::AaTurret => "aa_turret",
        BuildingKind::Wall => "wall",
    }
}

/// The loaded sprite textures and UI fonts.
pub struct Sprites {
    map: HashMap<&'static str, Texture2D>,
    font: Option<Font>,
    font_bold: Option<Font>,
    font_display: Option<Font>,
    font_regal: Option<Font>,
}

impl Sprites {
    /// Loads every sprite and the UI fonts from `assets/`. Missing assets are
    /// skipped — the renderer falls back to shapes / the built-in font.
    pub async fn load() -> Self {
        let mut map = HashMap::new();
        for &name in &ALL {
            if let Ok(texture) = load_texture(&format!("assets/{name}.png")).await {
                texture.set_filter(FilterMode::Linear);
                map.insert(name, texture);
            }
        }
        let font = load_ttf_font("assets/fonts/Rajdhani-SemiBold.ttf")
            .await
            .ok();
        let font_bold = load_ttf_font("assets/fonts/Rajdhani-Bold.ttf").await.ok();
        // Military-stencil display face for menu headers/banners only (Black Ops
        // One, OFL). Falls back to the bold UI font if missing.
        let font_display = load_ttf_font("assets/fonts/BlackOpsOne-Regular.ttf")
            .await
            .ok();
        // Inscriptional Roman serif (Cinzel) for the regal menu register.
        let font_regal = load_ttf_font("assets/fonts/Cinzel-Bold.ttf").await.ok();
        Self {
            map,
            font,
            font_bold,
            font_display,
            font_regal,
        }
    }

    /// The regular UI font (built-in fallback if it failed to load).
    #[must_use]
    pub const fn font(&self) -> Option<&Font> {
        self.font.as_ref()
    }

    /// The bold UI font for headings.
    #[must_use]
    pub const fn font_bold(&self) -> Option<&Font> {
        self.font_bold.as_ref()
    }

    /// The military-stencil display face for menu titles and banners. Falls back
    /// to the bold UI font when the stencil face is unavailable.
    #[must_use]
    pub const fn font_display(&self) -> Option<&Font> {
        match self.font_display.as_ref() {
            Some(font) => Some(font),
            None => self.font_bold.as_ref(),
        }
    }

    /// The inscriptional Roman serif (Cinzel) for the regal menu register. Falls
    /// back to the bold UI font when unavailable.
    #[must_use]
    pub const fn font_regal(&self) -> Option<&Font> {
        match self.font_regal.as_ref() {
            Some(font) => Some(font),
            None => self.font_bold.as_ref(),
        }
    }

    /// Texture for a unit kind, if loaded.
    #[must_use]
    pub fn unit(&self, kind: UnitKind) -> Option<&Texture2D> {
        self.map.get(unit_name(kind))
    }

    /// Texture for a building kind, if loaded.
    #[must_use]
    pub fn building(&self, kind: BuildingKind) -> Option<&Texture2D> {
        self.map.get(building_name(kind))
    }
}
