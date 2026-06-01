//! The deterministic world: entity state, the fixed-timestep tick, the ordered
//! command queue, and the state hash.
//!
//! This is the simulation *engine*. Given a seed and an ordered sequence of
//! command batches (one batch per tick), [`World::step`] advances the world
//! deterministically, and [`World::state_hash`] fingerprints the result. The
//! RTS *gameplay* (economy, units, towers, AI) is layered on top in later work;
//! here we prove the loop is reproducible.

use crate::fixed::Fixed;
use crate::hash::Fnv;
use crate::rng::Rng;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Stable handle to an entity (its index in the world's entity list).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct EntityId(pub u32);

/// A simulated entity. Minimal for now — position, velocity, and health.
#[derive(Clone, Debug)]
struct Entity {
    alive: bool,
    pos: Vec2,
    vel: Vec2,
    hp: Fixed,
}

/// An input applied to the world at a tick boundary. Player and AI both produce
/// these; the order within a tick is significant and part of determinism.
#[derive(Clone, Debug)]
pub enum Command {
    /// Create a new entity.
    Spawn {
        /// Starting position.
        pos: Vec2,
        /// Starting velocity (units per tick).
        vel: Vec2,
        /// Starting health.
        hp: Fixed,
    },
    /// Change an entity's velocity.
    SetVelocity {
        /// Target entity.
        id: EntityId,
        /// New velocity.
        vel: Vec2,
    },
    /// Apply damage to an entity; it dies when health reaches zero.
    Damage {
        /// Target entity.
        id: EntityId,
        /// Amount of health to remove.
        amount: Fixed,
    },
}

/// The deterministic simulation world.
#[derive(Clone, Debug)]
pub struct World {
    tick: u64,
    rng: Rng,
    entities: Vec<Entity>,
}

impl World {
    /// Creates an empty world seeded for deterministic randomness.
    #[must_use]
    pub const fn new(seed: u64) -> Self {
        Self {
            tick: 0,
            rng: Rng::from_seed(seed),
            entities: Vec::new(),
        }
    }

    /// The current tick count (number of completed steps).
    #[must_use]
    pub const fn tick(&self) -> u64 {
        self.tick
    }

    /// Number of currently-alive entities.
    #[must_use]
    pub fn alive_count(&self) -> usize {
        self.entities.iter().filter(|e| e.alive).count()
    }

    #[must_use]
    fn get(&self, id: EntityId) -> Option<&Entity> {
        self.entities.get(id.0 as usize)
    }

    /// Whether the entity exists and is alive.
    #[must_use]
    pub fn is_alive(&self, id: EntityId) -> bool {
        self.get(id).is_some_and(|e| e.alive)
    }

    /// The position of a living entity, or `None` if it is dead or unknown.
    #[must_use]
    pub fn position(&self, id: EntityId) -> Option<Vec2> {
        self.get(id).filter(|e| e.alive).map(|e| e.pos)
    }

    /// Advances the simulation one tick: applies the ordered command batch, then
    /// integrates motion for living entities. Determinism depends on this order.
    pub fn step(&mut self, commands: &[Command]) {
        for command in commands {
            self.apply(command);
        }
        for entity in &mut self.entities {
            if entity.alive {
                entity.pos = entity.pos + entity.vel;
            }
        }
        self.tick += 1;
    }

    fn apply(&mut self, command: &Command) {
        match *command {
            Command::Spawn { pos, vel, hp } => {
                self.entities.push(Entity {
                    alive: true,
                    pos,
                    vel,
                    hp,
                });
            }
            Command::SetVelocity { id, vel } => {
                if let Some(entity) = self.entities.get_mut(id.0 as usize) {
                    if entity.alive {
                        entity.vel = vel;
                    }
                }
            }
            Command::Damage { id, amount } => {
                if let Some(entity) = self.entities.get_mut(id.0 as usize) {
                    if entity.alive {
                        entity.hp = entity.hp - amount;
                        if entity.hp <= Fixed::ZERO {
                            entity.alive = false;
                        }
                    }
                }
            }
        }
    }

    /// A deterministic fingerprint of the entire world state. Equal hashes across
    /// two runs (or two targets) mean the simulations are in lock-step.
    #[must_use]
    pub fn state_hash(&self) -> u64 {
        let mut h = Fnv::new();
        h.write_u64(self.tick);
        h.write_u64(self.rng.current_state());
        for entity in &self.entities {
            h.write_u64(u64::from(entity.alive));
            h.write_i64(entity.pos.x.to_bits());
            h.write_i64(entity.pos.y.to_bits());
            h.write_i64(entity.vel.x.to_bits());
            h.write_i64(entity.vel.y.to_bits());
            h.write_i64(entity.hp.to_bits());
        }
        h.finish()
    }
}

#[cfg(test)]
mod tests {
    use super::{Command, EntityId, World};
    use crate::fixed::Fixed;
    use crate::vec::Vec2;

    fn f(n: i32) -> Fixed {
        Fixed::from_int(n)
    }
    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(f(x), f(y))
    }

    #[test]
    fn new_world_starts_empty_at_tick_zero() {
        let w = World::new(1);
        assert_eq!(w.tick(), 0);
        assert_eq!(w.alive_count(), 0);
    }

    #[test]
    fn step_advances_tick() {
        let mut w = World::new(1);
        w.step(&[]);
        w.step(&[]);
        assert_eq!(w.tick(), 2);
    }

    #[test]
    fn spawn_adds_an_entity() {
        let mut w = World::new(1);
        w.step(&[Command::Spawn {
            pos: v(5, 5),
            vel: Vec2::ZERO,
            hp: f(10),
        }]);
        assert_eq!(w.alive_count(), 1);
        assert!(w.is_alive(EntityId(0)));
    }

    #[test]
    fn velocity_integrates_each_tick() {
        let mut w = World::new(1);
        w.step(&[Command::Spawn {
            pos: v(0, 0),
            vel: v(1, 0),
            hp: f(10),
        }]);
        // Commands apply, then motion integrates, so the unit has moved once.
        assert_eq!(w.position(EntityId(0)), Some(v(1, 0)));
        w.step(&[]);
        assert_eq!(w.position(EntityId(0)), Some(v(2, 0)));
    }

    #[test]
    fn set_velocity_changes_motion() {
        let mut w = World::new(1);
        w.step(&[Command::Spawn {
            pos: v(0, 0),
            vel: Vec2::ZERO,
            hp: f(10),
        }]);
        assert_eq!(w.position(EntityId(0)), Some(v(0, 0)));
        w.step(&[Command::SetVelocity {
            id: EntityId(0),
            vel: v(2, 0),
        }]);
        assert_eq!(w.position(EntityId(0)), Some(v(2, 0)));
    }

    #[test]
    fn damage_reduces_then_kills() {
        let mut w = World::new(1);
        w.step(&[Command::Spawn {
            pos: v(0, 0),
            vel: Vec2::ZERO,
            hp: f(10),
        }]);
        w.step(&[Command::Damage {
            id: EntityId(0),
            amount: f(4),
        }]);
        assert!(w.is_alive(EntityId(0)));
        w.step(&[Command::Damage {
            id: EntityId(0),
            amount: f(6),
        }]);
        assert!(!w.is_alive(EntityId(0)));
        assert_eq!(w.alive_count(), 0);
        assert_eq!(w.position(EntityId(0)), None);
    }

    #[test]
    fn same_seed_and_commands_produce_same_hash() {
        let script: [&[Command]; 4] = [
            &[Command::Spawn {
                pos: v(0, 0),
                vel: v(1, 1),
                hp: f(10),
            }],
            &[Command::Spawn {
                pos: v(3, 0),
                vel: v(0, 1),
                hp: f(8),
            }],
            &[Command::Damage {
                id: EntityId(0),
                amount: f(3),
            }],
            &[Command::SetVelocity {
                id: EntityId(1),
                vel: v(-1, 0),
            }],
        ];
        let mut a = World::new(777);
        let mut b = World::new(777);
        for cmds in script {
            a.step(cmds);
            b.step(cmds);
            assert_eq!(a.state_hash(), b.state_hash());
        }
    }

    #[test]
    fn hash_changes_when_state_changes() {
        let mut w = World::new(1);
        let before = w.state_hash();
        w.step(&[Command::Spawn {
            pos: v(1, 1),
            vel: Vec2::ZERO,
            hp: f(5),
        }]);
        assert_ne!(before, w.state_hash());
    }
}
