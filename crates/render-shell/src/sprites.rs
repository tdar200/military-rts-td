//! Loads and holds the unit/building sprite textures.
//!
//! Earthfront uses native-colour, pre-rendered isometric sprites. Faction identity
//! is supplied by the renderer's ground marker rather than destructive whole-image
//! tinting, preserving the material detail and readable silhouettes.

use macroquad::prelude::*;
use rts_core::game::stats::{BuildingKind, UnitKind};
use std::collections::HashMap;

const ALL: [&str; 38] = [
    "infantry_v2",
    "tank_v2",
    "anti_armor_v2",
    "helicopter_v2",
    "harvester_v2",
    "command_center_v2",
    "power_plant_v2",
    "refinery_v2",
    "barracks_v2",
    "gun_turret_v2",
    "aa_turret_v2",
    "wall_v2",
    "capital_v1",
    "alien_infantry_v1",
    "alien_tank_v1",
    "alien_anti_armor_v1",
    "alien_helicopter_v1",
    "alien_harvester_v1",
    "alien_command_center_v1",
    "alien_power_plant_v1",
    "alien_refinery_v1",
    "alien_barracks_v1",
    "alien_gun_turret_v1",
    "alien_aa_turret_v1",
    "alien_wall_v1",
    "alien_capital_v1",
    "rock_cluster_v1",
    "scrub_cluster_v1",
    "dead_tree_v1",
    "sandbags_v1",
    "wrecked_car_v1",
    "concrete_barriers_v1",
    "floodlight_v1",
    "crater_v1",
    "ore_crystals_v1",
    "alloy_crystals_v1",
    "foundation_v1",
    "chain_fence_v1",
];

const ENVIRONMENT: [&str; 12] = [
    "rock_cluster_v1",
    "scrub_cluster_v1",
    "dead_tree_v1",
    "sandbags_v1",
    "wrecked_car_v1",
    "concrete_barriers_v1",
    "floodlight_v1",
    "crater_v1",
    "ore_crystals_v1",
    "alloy_crystals_v1",
    "foundation_v1",
    "chain_fence_v1",
];

const fn unit_name(kind: UnitKind, alien: bool) -> &'static str {
    if alien {
        return match kind {
            UnitKind::Infantry => "alien_infantry_v1",
            UnitKind::Tank => "alien_tank_v1",
            UnitKind::Capital => "alien_capital_v1",
            UnitKind::Harvester => "alien_harvester_v1",
            UnitKind::AntiArmor => "alien_anti_armor_v1",
            UnitKind::Helicopter => "alien_helicopter_v1",
        };
    }
    match kind {
        UnitKind::Infantry => "infantry_v2",
        UnitKind::Tank => "tank_v2",
        UnitKind::Capital => "capital_v1",
        UnitKind::Harvester => "harvester_v2",
        UnitKind::AntiArmor => "anti_armor_v2",
        UnitKind::Helicopter => "helicopter_v2",
    }
}

const fn building_name(kind: BuildingKind, alien: bool) -> &'static str {
    if alien {
        return match kind {
            BuildingKind::CommandCenter => "alien_command_center_v1",
            BuildingKind::PowerPlant | BuildingKind::AntimatterPlant | BuildingKind::Battery => {
                "alien_power_plant_v1"
            }
            BuildingKind::Refinery | BuildingKind::SupplyDepot => "alien_refinery_v1",
            BuildingKind::Barracks
            | BuildingKind::ResearchLab
            | BuildingKind::VehicleFactory
            | BuildingKind::Airfield => "alien_barracks_v1",
            BuildingKind::GunTurret => "alien_gun_turret_v1",
            BuildingKind::AaTurret => "alien_aa_turret_v1",
            BuildingKind::Wall => "alien_wall_v1",
        };
    }
    match kind {
        BuildingKind::CommandCenter => "command_center_v2",
        BuildingKind::PowerPlant | BuildingKind::AntimatterPlant | BuildingKind::Battery => {
            "power_plant_v2"
        }
        BuildingKind::Refinery | BuildingKind::SupplyDepot => "refinery_v2",
        BuildingKind::Barracks
        | BuildingKind::ResearchLab
        | BuildingKind::VehicleFactory
        | BuildingKind::Airfield => "barracks_v2",
        BuildingKind::GunTurret => "gun_turret_v2",
        BuildingKind::AaTurret => "aa_turret_v2",
        BuildingKind::Wall => "wall_v2",
    }
}

/// The loaded sprite textures and UI fonts.
pub struct Sprites {
    map: HashMap<&'static str, Texture2D>,
    font: Option<Font>,
    font_bold: Option<Font>,
    font_display: Option<Font>,
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
        Self {
            map,
            font,
            font_bold,
            font_display,
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

    /// The wide geometric sci-fi face used for the wordmark and menu headers — now
    /// the bold UI font (Rajdhani-Bold), so the holographic register stays
    /// consistent rather than reverting to a serif.
    #[must_use]
    pub const fn font_regal(&self) -> Option<&Font> {
        self.font_bold.as_ref()
    }

    /// Texture for a unit kind, if loaded.
    #[must_use]
    pub fn unit(&self, kind: UnitKind) -> Option<&Texture2D> {
        self.map.get(unit_name(kind, false))
    }

    /// Texture for a building kind, if loaded.
    #[must_use]
    pub fn building(&self, kind: BuildingKind) -> Option<&Texture2D> {
        self.map.get(building_name(kind, false))
    }

    /// Faction-aware unit texture for world and inspection rendering.
    #[must_use]
    pub fn unit_for(&self, kind: UnitKind, alien: bool) -> Option<&Texture2D> {
        self.map.get(unit_name(kind, alien))
    }

    /// Faction-aware building texture for world and inspection rendering.
    #[must_use]
    pub fn building_for(&self, kind: BuildingKind, alien: bool) -> Option<&Texture2D> {
        self.map.get(building_name(kind, alien))
    }

    /// Environment prop by stable atlas index (0..12).
    #[must_use]
    pub fn environment(&self, index: usize) -> Option<&Texture2D> {
        ENVIRONMENT.get(index).and_then(|name| self.map.get(name))
    }
}
