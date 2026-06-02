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
        UnitKind::Tank => "tank",
        UnitKind::AntiArmor => "anti_armor",
        UnitKind::Helicopter => "helicopter",
    }
}

const fn building_name(kind: BuildingKind) -> &'static str {
    match kind {
        BuildingKind::CommandCenter => "command_center",
        BuildingKind::PowerPlant => "power_plant",
        BuildingKind::Refinery => "refinery",
        BuildingKind::Barracks => "barracks",
        BuildingKind::GunTurret => "gun_turret",
        BuildingKind::AaTurret => "aa_turret",
        BuildingKind::Wall => "wall",
    }
}

/// The loaded sprite textures, keyed by asset name.
pub struct Sprites {
    map: HashMap<&'static str, Texture2D>,
}

impl Sprites {
    /// Loads every sprite from `assets/`. Missing textures are simply skipped —
    /// the renderer falls back to solid shapes for any that fail.
    pub async fn load() -> Self {
        let mut map = HashMap::new();
        for &name in &ALL {
            if let Ok(texture) = load_texture(&format!("assets/{name}.png")).await {
                texture.set_filter(FilterMode::Linear);
                map.insert(name, texture);
            }
        }
        Self { map }
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
