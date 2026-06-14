//! Under-attack alert system — the anti-blindside layer (presentation only).
//!
//! Every frame we diff each HUMAN-owned entity's HP against last frame; any drop
//! spawns (or refreshes) an alert at its world position. Alerts coalesce so one
//! battle reads as one marker, expire on a timer, drive a throttled audio blip,
//! and feed both the minimap (pulsing rings) and the main view (edge arrows /
//! on-screen rings + the camera-jump key). None of this touches the deterministic
//! sim — it reads `sim.views()` and renders.

use macroquad::time::get_time;
use rts_core::game::sim::Sim;
use std::collections::HashMap;

use crate::HUMAN;

/// How long (wall-clock seconds) an alert lives after its last damage event.
const ALERT_TTL: f64 = 6.0;
/// Coalesce radius in world tiles: a new damage event within this distance of a
/// live alert refreshes it instead of spawning a second marker (one battle = one
/// alert).
const COALESCE_TILES: f32 = 3.0;
/// Minimum wall-clock gap between alert blips, so a sustained barrage doesn't
/// machine-gun the mixer.
const BLIP_GAP: f64 = 1.5;

/// One coalesced under-attack marker.
#[derive(Clone, Copy)]
pub struct Alert {
    /// World-tile position of the battle (the struck entity's location).
    pub world: (f32, f32),
    /// Wall-clock time of the most recent damage event feeding this alert.
    pub spawn_time: f64,
}

/// Tracks HUMAN entity HP across frames and the live set of coalesced alerts.
#[derive(Default)]
pub struct Alerts {
    /// Last-frame HP for each owned entity, keyed by entity id (as `u32`).
    last_hp: HashMap<u32, f32>,
    /// Live alerts, newest interactions refreshing existing nearby ones.
    pub active: Vec<Alert>,
    /// Wall-clock time of the last alert blip (throttle gate).
    last_blip: f64,
    /// Index used by the camera-jump key to cycle alerts newest-first.
    pub jump_cursor: usize,
}

impl Alerts {
    /// Diffs this frame's HUMAN entity HP against last frame and (de)spawns
    /// alerts. Returns `true` iff a *new* (non-refresh) alert appeared, so the
    /// caller can fire a throttled blip.
    pub fn update(&mut self, sim: &Sim) -> bool {
        let now = get_time();
        // Expire stale alerts first (so refresh vs. new is measured against live ones).
        self.active.retain(|a| now - a.spawn_time < ALERT_TTL);

        let mut new_hp: HashMap<u32, f32> = HashMap::new();
        let mut new_alert = false;
        for v in sim.views() {
            if v.owner != HUMAN {
                continue;
            }
            let hp = v.hp.to_bits() as f32 / 65536.0;
            let world = (
                v.pos.x.to_bits() as f32 / 65536.0,
                v.pos.y.to_bits() as f32 / 65536.0,
            );
            // Damage = HP strictly below what this same id had last frame. New
            // entities (no prior sample) and healed/static entities don't alert.
            if self
                .last_hp
                .get(&v.id.0)
                .is_some_and(|&prev| hp < prev - 0.001)
                && self.register(world, now)
            {
                new_alert = true;
            }
            new_hp.insert(v.id.0, hp);
        }
        self.last_hp = new_hp;

        let blip = new_alert && now - self.last_blip >= BLIP_GAP;
        if blip {
            self.last_blip = now;
        }
        blip
    }

    /// Refreshes the nearest live alert within the coalesce radius, or pushes a
    /// new one. Returns `true` iff a brand-new alert was added.
    fn register(&mut self, world: (f32, f32), now: f64) -> bool {
        let r2 = COALESCE_TILES * COALESCE_TILES;
        for a in &mut self.active {
            let dx = a.world.0 - world.0;
            let dy = a.world.1 - world.1;
            if dx * dx + dy * dy <= r2 {
                a.world = world;
                a.spawn_time = now;
                return false;
            }
        }
        self.active.push(Alert {
            world,
            spawn_time: now,
        });
        true
    }

    /// The most-recent alert's world position, or `None` if there are none.
    /// Repeated calls cycle through active alerts newest-first (for the jump key).
    pub fn cycle_jump_target(&mut self) -> Option<(f32, f32)> {
        if self.active.is_empty() {
            return None;
        }
        // Newest-first ordering by spawn_time.
        let mut order: Vec<usize> = (0..self.active.len()).collect();
        order.sort_by(|&a, &b| {
            self.active[b]
                .spawn_time
                .total_cmp(&self.active[a].spawn_time)
        });
        let pick = order[self.jump_cursor % order.len()];
        self.jump_cursor = self.jump_cursor.wrapping_add(1);
        Some(self.active[pick].world)
    }

    /// Reset all tracking (on restart / mode change), so a fresh match starts
    /// without stale HP samples or markers.
    pub fn clear(&mut self) {
        self.last_hp.clear();
        self.active.clear();
        self.jump_cursor = 0;
    }
}
