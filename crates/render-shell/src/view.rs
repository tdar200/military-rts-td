//! Shell-side animated view layer.
//!
//! The deterministic sim advances in fixed 30 Hz ticks; this layer interpolates
//! entity positions between ticks for smooth motion, damps health/shield bars so
//! they slide instead of jumping, pops new entities in, flashes them on hit, and
//! derives death/spawn/hit FX events by diffing successive view snapshots (the
//! sim exposes no event stream). It is pure view state — it never feeds back into
//! the sim, so it cannot affect determinism.

use crate::anim::{damp, ease_out_back, lerp};
use macroquad::math::{vec2, Vec2};
use rts_core::game::sim::{EntityId, EntityKindView, PlayerId, Sim};

use std::collections::HashMap;

const HUMAN: PlayerId = PlayerId(0);
/// Seconds for a freshly spawned entity to pop to full size.
const SPAWN_POP: f32 = 0.28;
/// How fast hit-flash fades (per second).
const FLASH_DECAY: f32 = 4.0;
/// Bar damping rate (higher = snappier).
const BAR_RATE: f32 = 12.0;
/// Minimum HP drop (in HP units) that counts as a "hit" worth flashing.
const HIT_EPS: f32 = 0.5;
/// Seconds a floating damage number lives.
const POPUP_LIFE: f32 = 0.8;
/// Cap on simultaneous damage popups.
const MAX_POPUPS: usize = 80;

/// A cosmetic FX event derived from a tick-to-tick diff, consumed by the shell to
/// spawn particles, play sound, and shake the camera.
pub enum FxEvent {
    /// An entity died (left the view set) at `world`.
    Death {
        world: Vec2,
        building: bool,
        human: bool,
    },
    /// A new entity appeared at `world`.
    Spawn {
        world: Vec2,
        building: bool,
        human: bool,
    },
    /// An entity took damage at `world`.
    Hit {
        world: Vec2,
        human: bool,
        amount: f32,
    },
}

struct Ent {
    seen: u64,
    tag: u32,
    human: bool,
    building: bool,
    prev: Vec2,
    curr: Vec2,
    hp_target: f32,
    hp_shown: f32,
    max_hp: f32,
    sh_target: f32,
    sh_shown: f32,
    max_sh: f32,
    flash: f32,
    spawn_age: f32,
}

/// Interpolated render values for one entity this frame.
pub struct EntDraw {
    pub world: Vec2,
    pub hp: f32,
    pub max_hp: f32,
    pub shield: f32,
    pub max_shield: f32,
    pub flash: f32,
    pub scale: f32,
}

/// A rising, fading damage number.
struct Popup {
    world: Vec2,
    amount: f32,
    age: f32,
}

/// The animated view layer.
#[derive(Default)]
pub struct ViewState {
    ents: HashMap<u32, Ent>,
    gen: u64,
    /// FX events produced since the last drain.
    pub events: Vec<FxEvent>,
    popups: Vec<Popup>,
}

fn world_of(p: rts_core::vec::Vec2) -> Vec2 {
    vec2(
        p.x.to_bits() as f32 / 65536.0,
        p.y.to_bits() as f32 / 65536.0,
    )
}

const fn is_building(kind: EntityKindView) -> bool {
    matches!(kind, EntityKindView::Building(_))
}

/// A stable tag distinguishing entity kinds, so a recycled id reused for a
/// different kind reads as death+spawn rather than a teleport.
const fn tag_of(kind: EntityKindView) -> u32 {
    match kind {
        EntityKindView::Unit(u) => 1000 + u as u32,
        EntityKindView::Building(b) => 2000 + b as u32,
    }
}

impl ViewState {
    /// Called once per completed sim tick: shifts positions, updates bar targets,
    /// and emits death/spawn/hit events from the diff.
    pub fn on_tick(&mut self, sim: &Sim) {
        self.gen = self.gen.wrapping_add(1);
        let g = self.gen;
        for v in sim.views() {
            let id = v.id.0;
            let tag = tag_of(v.kind);
            let world = world_of(v.pos);
            let hp = v.hp.to_bits() as f32 / 65536.0;
            let max_hp = (v.max_hp.to_bits() as f32 / 65536.0).max(1.0);
            let shield = v.shield.to_bits() as f32 / 65536.0;
            let max_sh = v.max_shield.to_bits() as f32 / 65536.0;
            let human = v.owner == HUMAN;
            let building = is_building(v.kind);

            // Update an existing same-kind entity (borrow scoped so we can push
            // the hit event afterwards without a borrow conflict).
            let mut handled = false;
            let mut hit_amount: Option<f32> = None;
            if let Some(e) = self.ents.get_mut(&id) {
                if e.tag == tag {
                    e.seen = g;
                    e.prev = e.curr;
                    e.curr = world;
                    if hp < e.hp_target - HIT_EPS {
                        hit_amount = Some(e.hp_target - hp);
                        e.flash = 1.0;
                    }
                    e.hp_target = hp;
                    e.max_hp = max_hp;
                    e.sh_target = shield;
                    e.max_sh = max_sh;
                    handled = true;
                }
            }
            if let Some(amount) = hit_amount {
                self.events.push(FxEvent::Hit {
                    world,
                    human,
                    amount,
                });
                if self.popups.len() < MAX_POPUPS {
                    self.popups.push(Popup {
                        world,
                        amount,
                        age: 0.0,
                    });
                }
            }
            if !handled {
                if let Some(old) = self.ents.get(&id) {
                    // Recycled slot now holds a different kind — old one died.
                    self.events.push(FxEvent::Death {
                        world: old.curr,
                        building: old.building,
                        human: old.human,
                    });
                }
                self.events.push(FxEvent::Spawn {
                    world,
                    building,
                    human,
                });
                self.ents.insert(
                    id,
                    Ent {
                        seen: g,
                        tag,
                        human,
                        building,
                        prev: world,
                        curr: world,
                        hp_target: hp,
                        hp_shown: hp,
                        max_hp,
                        sh_target: shield,
                        sh_shown: shield,
                        max_sh,
                        flash: 0.0,
                        spawn_age: 0.0,
                    },
                );
            }
        }
        // Anything not seen this tick has died — collect first, then mutate.
        let dead: Vec<(u32, Vec2, bool, bool)> = self
            .ents
            .iter()
            .filter(|(_, e)| e.seen != g)
            .map(|(id, e)| (*id, e.curr, e.building, e.human))
            .collect();
        for (id, world, building, human) in dead {
            self.events.push(FxEvent::Death {
                world,
                building,
                human,
            });
            self.ents.remove(&id);
        }
    }

    /// Per-frame animation update (flash decay, spawn pop, bar damping, popups).
    pub fn frame(&mut self, dt: f32) {
        for e in self.ents.values_mut() {
            e.flash = (e.flash - FLASH_DECAY * dt).max(0.0);
            e.spawn_age += dt;
            e.hp_shown = damp(e.hp_shown, e.hp_target, BAR_RATE, dt);
            e.sh_shown = damp(e.sh_shown, e.sh_target, BAR_RATE, dt);
        }
        self.popups.retain_mut(|p| {
            p.age += dt;
            p.age < POPUP_LIFE
        });
    }

    /// Floating damage numbers to draw: `(world, amount, t)` where `t` is 0..1 age.
    pub fn popups(&self) -> impl Iterator<Item = (Vec2, i32, f32)> + '_ {
        self.popups
            .iter()
            .map(|p| (p.world, p.amount.round() as i32, p.age / POPUP_LIFE))
    }

    /// Interpolated render values for `id` at sub-tick `alpha` (0..1), if known.
    #[must_use]
    pub fn entity(&self, id: EntityId, alpha: f32) -> Option<EntDraw> {
        let e = self.ents.get(&id.0)?;
        let world = vec2(
            lerp(e.prev.x, e.curr.x, alpha),
            lerp(e.prev.y, e.curr.y, alpha),
        );
        let scale = ease_out_back((e.spawn_age / SPAWN_POP).min(1.0));
        Some(EntDraw {
            world,
            hp: e.hp_shown,
            max_hp: e.max_hp,
            shield: e.sh_shown,
            max_shield: e.max_sh,
            flash: e.flash,
            scale,
        })
    }
}
