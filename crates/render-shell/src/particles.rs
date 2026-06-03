//! A small, capped particle system + persistent scorch decals. Pure view layer
//! (floats, non-deterministic randomness) — it never touches the sim.
//!
//! Particles live in **pixel** space (spawned at draw-time pixel coordinates,
//! short-lived). Scorch decals live in **world/tile** space so they stay locked
//! to the board across window resizes, since they persist much longer.

use macroquad::prelude::*;
use std::f32::consts::PI;

/// Hard cap on simultaneously live particles (spawns past this are dropped).
const MAX_PARTICLES: usize = 1500;
/// Hard cap on persistent scorch decals (oldest dropped past this).
const MAX_SCORCHES: usize = 200;

#[derive(Clone, Copy)]
struct Particle {
    pos: Vec2,
    vel: Vec2,
    life: f32,
    max_life: f32,
    size: f32,
    color: Color,
    gravity: f32,
    /// Glow particles fade their radius with life; solid debris keep their size.
    glow: bool,
}

#[derive(Clone, Copy)]
struct Scorch {
    world: Vec2,
    r_tiles: f32,
    life: f32,
    max_life: f32,
}

/// The live particle pool + scorch decals.
pub struct Particles {
    live: Vec<Particle>,
    scorches: Vec<Scorch>,
}

fn rand(lo: f32, hi: f32) -> f32 {
    macroquad::rand::gen_range(lo, hi)
}

impl Particles {
    /// Creates an empty pool with capacity pre-reserved (no per-frame growth).
    #[must_use]
    pub fn new() -> Self {
        Self {
            live: Vec::with_capacity(MAX_PARTICLES),
            scorches: Vec::with_capacity(MAX_SCORCHES),
        }
    }

    /// Drops all particles and scorches (e.g. when a new match starts).
    pub fn clear(&mut self) {
        self.live.clear();
        self.scorches.clear();
    }

    fn add(&mut self, p: Particle) {
        if self.live.len() < MAX_PARTICLES {
            self.live.push(p);
        }
    }

    /// An explosion at pixel `p`: a burst of glowing sparks scaled by `scale`.
    pub fn explosion(&mut self, p: Vec2, color: Color, scale: f32) {
        let n = (12.0 * scale) as i32;
        for _ in 0..n {
            let a = rand(0.0, PI * 2.0);
            let speed = rand(40.0, 170.0) * scale;
            let life = rand(0.25, 0.6);
            self.add(Particle {
                pos: p,
                vel: vec2(a.cos() * speed, a.sin() * speed),
                life,
                max_life: life,
                size: rand(1.5, 3.5) * scale,
                color,
                gravity: 0.0,
                glow: true,
            });
        }
        // A couple of soft expanding glow puffs at the core.
        for _ in 0..2 {
            let life = rand(0.18, 0.32);
            self.add(Particle {
                pos: p,
                vel: vec2(0.0, 0.0),
                life,
                max_life: life,
                size: rand(6.0, 11.0) * scale,
                color: Color { a: 0.5, ..color },
                gravity: 0.0,
                glow: true,
            });
        }
    }

    /// Gravity-affected debris chunks (building destruction).
    pub fn debris(&mut self, p: Vec2, color: Color) {
        for _ in 0..10 {
            let a = rand(-PI, 0.0); // upward-biased
            let speed = rand(30.0, 130.0);
            let life = rand(0.5, 1.1);
            self.add(Particle {
                pos: p,
                vel: vec2(a.cos() * speed, a.sin() * speed),
                life,
                max_life: life,
                size: rand(2.0, 4.5),
                color,
                gravity: 240.0,
                glow: false,
            });
        }
    }

    /// A brief muzzle flash at the firing end of a shot.
    pub fn muzzle(&mut self, p: Vec2, color: Color) {
        for _ in 0..3 {
            let a = rand(0.0, PI * 2.0);
            let speed = rand(20.0, 70.0);
            let life = rand(0.06, 0.14);
            self.add(Particle {
                pos: p,
                vel: vec2(a.cos() * speed, a.sin() * speed),
                life,
                max_life: life,
                size: rand(2.0, 4.0),
                color,
                gravity: 0.0,
                glow: true,
            });
        }
    }

    /// A small impact spark spray at the receiving end of a hit, sized by `scale`
    /// (bigger damage → bigger spray).
    pub fn impact(&mut self, p: Vec2, color: Color, scale: f32) {
        let n = (4.0 * scale).clamp(3.0, 14.0) as i32;
        for _ in 0..n {
            let a = rand(0.0, PI * 2.0);
            let speed = rand(30.0, 100.0) * scale.clamp(0.7, 1.6);
            let life = rand(0.12, 0.3);
            self.add(Particle {
                pos: p,
                vel: vec2(a.cos() * speed, a.sin() * speed),
                life,
                max_life: life,
                size: rand(1.2, 2.6),
                color,
                gravity: 0.0,
                glow: true,
            });
        }
    }

    /// Upward dust when a building is placed.
    pub fn poof(&mut self, p: Vec2, color: Color) {
        for _ in 0..8 {
            let a = rand(-PI, 0.0);
            let speed = rand(20.0, 60.0);
            let life = rand(0.3, 0.6);
            self.add(Particle {
                pos: p,
                vel: vec2(a.cos() * speed, a.sin() * speed),
                life,
                max_life: life,
                size: rand(2.0, 4.0),
                color: Color { a: 0.6, ..color },
                gravity: 70.0,
                glow: true,
            });
        }
    }

    /// A warp-in shimmer when a unit appears.
    pub fn warp_in(&mut self, p: Vec2, color: Color) {
        for _ in 0..10 {
            let a = rand(0.0, PI * 2.0);
            let r = rand(10.0, 26.0);
            let life = rand(0.18, 0.4);
            // Start on a ring and drift inward toward the spawn point.
            self.add(Particle {
                pos: vec2(p.x + a.cos() * r, p.y + a.sin() * r),
                vel: vec2(-a.cos() * r * 3.0, -a.sin() * r * 3.0),
                life,
                max_life: life,
                size: rand(1.5, 3.0),
                color,
                gravity: 0.0,
                glow: true,
            });
        }
    }

    /// Adds a persistent scorch decal at world/tile position `world`.
    pub fn scorch(&mut self, world: Vec2, r_tiles: f32) {
        if self.scorches.len() >= MAX_SCORCHES {
            self.scorches.remove(0);
        }
        let life = 9.0;
        self.scorches.push(Scorch {
            world,
            r_tiles,
            life,
            max_life: life,
        });
    }

    /// Advances all particles and decays scorches.
    pub fn update(&mut self, dt: f32) {
        self.live.retain_mut(|p| {
            p.life -= dt;
            p.vel.y += p.gravity * dt;
            p.pos += p.vel * dt;
            p.life > 0.0
        });
        self.scorches.retain_mut(|s| {
            s.life -= dt;
            s.life > 0.0
        });
    }

    /// Draws scorch decals under the pieces. `(ox, wtop)` is the board origin and
    /// `cell` the pixels-per-tile, so world coords map to the (shaken) board.
    pub fn draw_scorches(&self, ox: f32, wtop: f32, cell: f32) {
        for s in &self.scorches {
            let t = (s.life / s.max_life).clamp(0.0, 1.0);
            let px = ox + s.world.x * cell;
            let py = wtop + s.world.y * cell;
            draw_circle(
                px,
                py,
                s.r_tiles * cell,
                Color::new(0.02, 0.02, 0.03, 0.5 * t),
            );
            draw_circle(
                px,
                py,
                s.r_tiles * cell * 0.6,
                Color::new(0.0, 0.0, 0.0, 0.4 * t),
            );
        }
    }

    /// Draws all live particles, offset by the screen-shake `(sx, sy)` so they
    /// move with the shaking world layer.
    pub fn draw(&self, sx: f32, sy: f32) {
        for p in &self.live {
            let t = (p.life / p.max_life).clamp(0.0, 1.0);
            let col = Color {
                a: p.color.a * t,
                ..p.color
            };
            let r = if p.glow {
                p.size * t.mul_add(0.6, 0.4)
            } else {
                p.size
            };
            draw_circle(p.pos.x + sx, p.pos.y + sy, r, col);
        }
    }
}
