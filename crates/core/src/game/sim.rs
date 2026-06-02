//! The integrated RTS simulation: two players, an economy, buildings, units,
//! combat, and a win condition — all deterministic and fixed-point.
//!
//! [`Sim::step`] advances one fixed tick by, in order: applying the ordered
//! command batch, running the economy, advancing production, moving units,
//! resolving combat, and clearing the dead. [`Sim::state_hash`] fingerprints the
//! whole thing so two runs (or two platforms, or client and server) can be proven
//! identical.

use crate::fixed::Fixed;
use crate::game::balance::Balance;
use crate::game::map::{Map, Tile};
use crate::game::path::find_path;
use crate::game::stats::{damage_multiplier, ArmorType, AttackProfile, BuildingKind, UnitKind};
use crate::hash::Fnv;
use crate::rng::Rng;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Number of players (single-player vs one AI for now; `PvP` later).
pub const PLAYER_COUNT: usize = 2;

/// How often (in ticks) the AI re-issues move orders to idle units, throttling
/// pathfinding work.
const MOVE_REISSUE_PERIOD: u64 = 20;

/// Combat spatial-grid cell size in tiles. Must be >= the largest attack range so
/// a 3x3 cell query around an attacker contains every in-range enemy.
const COMBAT_CELL: i32 = 8;

/// Identifies a player (`0` or `1`).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct PlayerId(pub u8);

/// Stable handle to an entity (index into the entity list).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct EntityId(pub u32);

/// What an entity is.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum Kind {
    Building(BuildingKind),
    Unit(UnitKind),
}

/// A simulated entity — a building or a unit.
#[derive(Clone, Debug)]
struct Entity {
    owner: PlayerId,
    kind: Kind,
    alive: bool,
    pos: Vec2,
    hp: Fixed,
    cooldown: u32,
    move_target: Option<Vec2>,
    /// Remaining tile waypoints toward `move_target` (from A*), nearest first.
    path: Vec<(u16, u16)>,
    tile: Option<(u16, u16)>,
    build_queue: Vec<UnitKind>,
    build_progress: u32,
}

/// Per-player resources.
#[derive(Clone, Copy, Debug)]
struct Player {
    credits: Fixed,
}

/// A player or AI input, applied at a tick boundary.
#[derive(Clone, Debug)]
pub enum Command {
    /// Construct a building on a tile (costs credits; tile must be buildable).
    Build {
        /// Owning player.
        owner: PlayerId,
        /// What to build.
        kind: BuildingKind,
        /// Tile column.
        x: u16,
        /// Tile row.
        y: u16,
    },
    /// Queue a unit for training at a barracks (costs credits).
    Train {
        /// Owning player.
        owner: PlayerId,
        /// The barracks entity.
        barracks: EntityId,
        /// What to train.
        kind: UnitKind,
    },
    /// Order a unit to move to a world position.
    Move {
        /// Owning player.
        owner: PlayerId,
        /// The unit entity.
        unit: EntityId,
        /// Destination.
        target: Vec2,
    },
}

/// Building or unit, for the render/UI layer (public projection of the internal
/// entity kind).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum EntityKindView {
    /// A building of the given kind.
    Building(BuildingKind),
    /// A unit of the given kind.
    Unit(UnitKind),
}

/// A read-only snapshot of one living entity, for rendering and UI.
#[derive(Clone, Copy, Debug)]
pub struct EntityView {
    /// Stable handle, for issuing commands back to the sim.
    pub id: EntityId,
    /// Owning player.
    pub owner: PlayerId,
    /// Building or unit (and which kind).
    pub kind: EntityKindView,
    /// World position.
    pub pos: Vec2,
    /// Current health.
    pub hp: Fixed,
    /// Maximum health (for health bars).
    pub max_hp: Fixed,
}

/// Configures periodic enemy waves — the attack/defend loop.
///
/// Every `interval` ticks (after `first_delay`) a growing group of `unit`s
/// spawns at `spawn` for `attacker` and attack-moves toward `defender`'s base.
#[derive(Clone, Copy, Debug)]
pub struct WaveConfig {
    /// Ticks before the first wave.
    pub first_delay: u64,
    /// Ticks between waves.
    pub interval: u64,
    /// Units in the first wave.
    pub base_size: u32,
    /// Extra units added per subsequent wave.
    pub growth: u32,
    /// World position units spawn at.
    pub spawn: Vec2,
    /// What to spawn.
    pub unit: UnitKind,
    /// Player the wave belongs to.
    pub attacker: PlayerId,
    /// Player the wave marches against.
    pub defender: PlayerId,
}

/// The deterministic RTS world.
#[derive(Clone, Debug)]
pub struct Sim {
    tick: u64,
    rng: Rng,
    map: Map,
    players: [Player; PLAYER_COUNT],
    entities: Vec<Entity>,
    /// Indices of dead entity slots available for reuse, so long matches don't
    /// grow the entity list without bound.
    free: Vec<u32>,
    waves: Option<WaveConfig>,
    wave_count: u32,
    balance: Balance,
    /// Transient render hint: (attacker, target) world positions of shots fired
    /// on the most recent combat tick. Deterministically derived, so it is not
    /// part of the state hash.
    attacks: Vec<(Vec2, Vec2)>,
}

const fn armor_of(balance: &Balance, kind: Kind) -> ArmorType {
    match kind {
        Kind::Unit(u) => balance.unit(u).armor,
        Kind::Building(b) => balance.building(b).armor,
    }
}

const fn attack_of(balance: &Balance, kind: Kind) -> Option<AttackProfile> {
    match kind {
        Kind::Unit(u) => Some(balance.unit(u).attack),
        Kind::Building(b) => balance.building(b).attack,
    }
}

const fn max_hp(balance: &Balance, kind: Kind) -> Fixed {
    match kind {
        Kind::Unit(u) => balance.unit(u).max_hp,
        Kind::Building(b) => balance.building(b).max_hp,
    }
}

/// World-space center of tile `(x, y)`.
fn tile_center(x: u16, y: u16) -> Vec2 {
    Vec2::new(
        Fixed::from_int(i32::from(x)) + Fixed::from_ratio(1, 2),
        Fixed::from_int(i32::from(y)) + Fixed::from_ratio(1, 2),
    )
}

const fn unit_tag(u: UnitKind) -> u64 {
    match u {
        UnitKind::Infantry => 1,
        UnitKind::Tank => 2,
        UnitKind::AntiArmor => 3,
        UnitKind::Helicopter => 4,
    }
}

const fn is_air_of(balance: &Balance, kind: Kind) -> bool {
    match kind {
        Kind::Unit(u) => balance.unit(u).is_air,
        Kind::Building(_) => false,
    }
}

const fn kind_tag(kind: Kind) -> u64 {
    match kind {
        Kind::Unit(u) => 0x100 | unit_tag(u),
        Kind::Building(b) => {
            let t = match b {
                BuildingKind::CommandCenter => 1,
                BuildingKind::PowerPlant => 2,
                BuildingKind::Refinery => 3,
                BuildingKind::Barracks => 4,
                BuildingKind::GunTurret => 5,
                BuildingKind::AaTurret => 7,
                BuildingKind::Wall => 6,
            };
            0x200 | t
        }
    }
}

impl Sim {
    /// Creates a fresh world on `map`, with each player holding
    /// `starting_credits`, seeded for deterministic randomness.
    #[must_use]
    pub const fn new(map: Map, seed: u64, starting_credits: Fixed) -> Self {
        Self {
            tick: 0,
            rng: Rng::from_seed(seed),
            map,
            players: [Player {
                credits: starting_credits,
            }; PLAYER_COUNT],
            entities: Vec::new(),
            free: Vec::new(),
            waves: None,
            wave_count: 0,
            balance: Balance::const_default(),
            attacks: Vec::new(),
        }
    }

    /// Shots fired on the most recent combat tick, as (attacker, target) world
    /// positions — for drawing tracers. Transient; not part of the state.
    #[must_use]
    pub fn recent_attacks(&self) -> &[(Vec2, Vec2)] {
        &self.attacks
    }

    /// Stores an entity in a recycled dead slot if one is free, else appends.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn alloc_slot(&mut self, entity: Entity) -> EntityId {
        if let Some(index) = self.free.pop() {
            self.entities[index as usize] = entity;
            EntityId(index)
        } else {
            let index = self.entities.len() as u32;
            self.entities.push(entity);
            EntityId(index)
        }
    }

    /// Replaces the balance table (e.g. one loaded from data).
    pub const fn set_balance(&mut self, balance: Balance) {
        self.balance = balance;
    }

    /// Enables periodic enemy waves (the attack/defend loop).
    pub const fn set_waves(&mut self, config: WaveConfig) {
        self.waves = Some(config);
    }

    /// The current tick count.
    #[must_use]
    pub const fn tick(&self) -> u64 {
        self.tick
    }

    /// The battlefield map.
    #[must_use]
    pub const fn map(&self) -> &Map {
        &self.map
    }

    /// A player's current credit balance.
    #[must_use]
    pub fn credits(&self, player: PlayerId) -> Fixed {
        self.players[usize::from(player.0)].credits
    }

    /// Credit cost to construct a building (for UI affordability hints).
    #[must_use]
    pub const fn building_cost(&self, kind: BuildingKind) -> Fixed {
        self.balance.building(kind).cost
    }

    /// Ticks until the next enemy wave, or `None` if waves are disabled.
    #[must_use]
    pub fn ticks_until_next_wave(&self) -> Option<u64> {
        let cfg = self.waves?;
        if self.tick < cfg.first_delay {
            return Some(cfg.first_delay - self.tick);
        }
        let into = (self.tick - cfg.first_delay) % cfg.interval;
        Some(if into == 0 { 0 } else { cfg.interval - into })
    }

    /// Number of living entities.
    #[must_use]
    pub fn entity_count(&self) -> usize {
        self.entities.iter().filter(|e| e.alive).count()
    }

    /// Number of living units owned by `player`.
    #[must_use]
    pub fn unit_count(&self, player: PlayerId) -> usize {
        self.entities
            .iter()
            .filter(|e| e.alive && e.owner == player && matches!(e.kind, Kind::Unit(_)))
            .count()
    }

    /// Whether the entity exists and is alive.
    #[must_use]
    pub fn is_alive(&self, id: EntityId) -> bool {
        self.entity(id).is_some_and(|e| e.alive)
    }

    /// The position of a living entity.
    #[must_use]
    pub fn position(&self, id: EntityId) -> Option<Vec2> {
        self.entity(id).filter(|e| e.alive).map(|e| e.pos)
    }

    /// A snapshot of every living entity, for the render/UI layer.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn views(&self) -> Vec<EntityView> {
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, e)| e.alive)
            .map(|(i, e)| EntityView {
                id: EntityId(i as u32),
                owner: e.owner,
                kind: match e.kind {
                    Kind::Building(b) => EntityKindView::Building(b),
                    Kind::Unit(u) => EntityKindView::Unit(u),
                },
                pos: e.pos,
                hp: e.hp,
                max_hp: max_hp(&self.balance, e.kind),
            })
            .collect()
    }

    /// The winner: the only player still holding a Command Center, if exactly
    /// one does; otherwise `None` (game ongoing or no bases left).
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "the index is a player slot < PLAYER_COUNT (2), so it fits u8"
    )]
    pub fn winner(&self) -> Option<PlayerId> {
        let mut has_cc = [false; PLAYER_COUNT];
        for e in &self.entities {
            if e.alive && e.kind == Kind::Building(BuildingKind::CommandCenter) {
                has_cc[usize::from(e.owner.0)] = true;
            }
        }
        let alive: usize = has_cc.iter().filter(|&&b| b).count();
        if alive == 1 {
            has_cc.iter().position(|&b| b).map(|i| PlayerId(i as u8))
        } else {
            None
        }
    }

    /// A deterministic fingerprint of the entire world.
    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        reason = "queue length comfortably fits u64 for any real game"
    )]
    pub fn state_hash(&self) -> u64 {
        let mut h = Fnv::new();
        h.write_u64(self.tick);
        h.write_u64(self.rng.current_state());
        h.write_u64(u64::from(self.wave_count));
        for p in &self.players {
            h.write_i64(p.credits.to_bits());
        }
        for e in &self.entities {
            h.write_u64(u64::from(e.alive));
            h.write_u64(u64::from(e.owner.0));
            h.write_u64(kind_tag(e.kind));
            h.write_i64(e.pos.x.to_bits());
            h.write_i64(e.pos.y.to_bits());
            h.write_i64(e.hp.to_bits());
            h.write_u64(u64::from(e.cooldown));
            match e.move_target {
                Some(t) => {
                    h.write_u64(1);
                    h.write_i64(t.x.to_bits());
                    h.write_i64(t.y.to_bits());
                }
                None => h.write_u64(0),
            }
            h.write_u64(u64::from(e.build_progress));
            h.write_u64(e.build_queue.len() as u64);
            for q in &e.build_queue {
                h.write_u64(unit_tag(*q));
            }
            h.write_u64(e.path.len() as u64);
            for &(wx, wy) in &e.path {
                h.write_u64(u64::from(wx));
                h.write_u64(u64::from(wy));
            }
        }
        h.write_u64(self.free.len() as u64);
        for &slot in &self.free {
            h.write_u64(u64::from(slot));
        }
        h.finish()
    }

    /// Places a building for free (scenario setup), blocking its tile.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn add_building(
        &mut self,
        owner: PlayerId,
        kind: BuildingKind,
        x: u16,
        y: u16,
    ) -> EntityId {
        let pos = Vec2::new(
            Fixed::from_int(i32::from(x)) + Fixed::from_ratio(1, 2),
            Fixed::from_int(i32::from(y)) + Fixed::from_ratio(1, 2),
        );
        self.map.set_tile(x, y, Tile::BLOCKED);
        let hp = max_hp(&self.balance, Kind::Building(kind));
        self.alloc_slot(Entity {
            owner,
            kind: Kind::Building(kind),
            alive: true,
            pos,
            hp,
            cooldown: 0,
            move_target: None,
            path: Vec::new(),
            tile: Some((x, y)),
            build_queue: Vec::new(),
            build_progress: 0,
        })
    }

    /// Places a unit for free (scenario setup / production).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn add_unit(&mut self, owner: PlayerId, kind: UnitKind, pos: Vec2) -> EntityId {
        let hp = max_hp(&self.balance, Kind::Unit(kind));
        self.alloc_slot(Entity {
            owner,
            kind: Kind::Unit(kind),
            alive: true,
            pos,
            hp,
            cooldown: 0,
            move_target: None,
            path: Vec::new(),
            tile: None,
            build_queue: Vec::new(),
            build_progress: 0,
        })
    }

    /// Advances the simulation one fixed tick.
    pub fn step(&mut self, commands: &[Command]) {
        for command in commands {
            self.apply_command(command);
        }
        let powered = self.run_economy();
        self.run_production(powered);
        self.run_waves();
        self.run_movement();
        self.run_combat();
        self.clear_dead();
        self.tick += 1;
    }

    /// Spawns a scheduled enemy wave, if one is due this tick, and points it at
    /// the defender's base.
    fn run_waves(&mut self) {
        let Some(cfg) = self.waves else { return };
        if self.tick < cfg.first_delay {
            return;
        }
        if !(self.tick - cfg.first_delay).is_multiple_of(cfg.interval) {
            return;
        }
        let size = cfg.base_size + cfg.growth * self.wave_count;
        let target = self.command_center_pos(cfg.defender);
        for i in 0..size {
            let offset = Vec2::new(Fixed::ZERO, Fixed::from_ratio(i64::from(i), 3));
            let spawned = self.add_unit(cfg.attacker, cfg.unit, cfg.spawn + offset);
            if let Some(t) = target {
                self.order_unit_to(spawned.0 as usize, t);
            }
        }
        self.wave_count += 1;
    }

    /// Sets a unit's move target and computes its A* path. Shared by the Move
    /// command and wave spawning. If the target tile is blocked (e.g. it *is* a
    /// building like the enemy Command Center), the unit paths to the nearest
    /// passable tile beside it and then closes the last step directly — so
    /// "attack the base" actually routes there.
    fn order_unit_to(&mut self, idx: usize, target: Vec2) {
        if is_air_of(&self.balance, self.entities[idx].kind) {
            // Air units fly straight to the target, ignoring terrain.
            let e = &mut self.entities[idx];
            e.move_target = Some(target);
            e.path = Vec::new();
            return;
        }
        let start = self.world_to_tile(self.entities[idx].pos);
        let goal_tile = self.world_to_tile(target);
        let goal = if self.is_passable_tile(goal_tile) {
            goal_tile
        } else {
            match self.nearest_passable_tile(goal_tile) {
                Some(tile) => tile,
                None => return,
            }
        };
        if let Some(path) = find_path(&self.map, start, goal) {
            let e = &mut self.entities[idx];
            e.move_target = Some(target);
            e.path = path;
        }
    }

    fn is_passable_tile(&self, tile: (u16, u16)) -> bool {
        self.map
            .tile(i32::from(tile.0), i32::from(tile.1))
            .is_some_and(|t| t.passable)
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "ring scan stays within the bounds-checked, non-negative u16 grid"
    )]
    fn nearest_passable_tile(&self, center: (u16, u16)) -> Option<(u16, u16)> {
        let cx = i32::from(center.0);
        let cy = i32::from(center.1);
        for r in 1..=24i32 {
            for dy in -r..=r {
                for dx in -r..=r {
                    if dx.abs().max(dy.abs()) != r {
                        continue;
                    }
                    let (x, y) = (cx + dx, cy + dy);
                    if x >= 0 && y >= 0 && self.map.tile(x, y).is_some_and(|t| t.passable) {
                        return Some((x as u16, y as u16));
                    }
                }
            }
        }
        None
    }

    fn command_center_pos(&self, player: PlayerId) -> Option<Vec2> {
        self.entities
            .iter()
            .find(|e| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .map(|e| e.pos)
    }

    fn entity(&self, id: EntityId) -> Option<&Entity> {
        self.entities.get(id.0 as usize)
    }

    fn apply_command(&mut self, command: &Command) {
        match *command {
            Command::Build { owner, kind, x, y } => {
                let buildable = self
                    .map
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.buildable);
                let cost = self.balance.building(kind).cost;
                let p = usize::from(owner.0);
                if buildable && self.players[p].credits >= cost {
                    self.players[p].credits = self.players[p].credits - cost;
                    self.add_building(owner, kind, x, y);
                }
            }
            Command::Train {
                owner,
                barracks,
                kind,
            } => {
                let cost = self.balance.unit(kind).cost;
                let p = usize::from(owner.0);
                let ok = self.entity(barracks).is_some_and(|e| {
                    e.alive
                        && e.owner == owner
                        && matches!(e.kind, Kind::Building(BuildingKind::Barracks))
                });
                if ok && self.players[p].credits >= cost {
                    self.players[p].credits = self.players[p].credits - cost;
                    if let Some(e) = self.entities.get_mut(barracks.0 as usize) {
                        e.build_queue.push(kind);
                    }
                }
            }
            Command::Move {
                owner,
                unit,
                target,
            } => {
                let idx = unit.0 as usize;
                let valid = self.entities.get(idx).is_some_and(|e| {
                    e.alive && e.owner == owner && matches!(e.kind, Kind::Unit(_))
                });
                if valid {
                    self.order_unit_to(idx, target);
                }
            }
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "value is clamped into the non-negative u16 grid before the cast"
    )]
    fn world_to_tile(&self, p: Vec2) -> (u16, u16) {
        let max_x = i64::from(self.map.width()) - 1;
        let max_y = i64::from(self.map.height()) - 1;
        let x = p.x.to_int_floor().clamp(0, max_x) as u16;
        let y = p.y.to_int_floor().clamp(0, max_y) as u16;
        (x, y)
    }

    fn run_economy(&mut self) -> [bool; PLAYER_COUNT] {
        let mut produced = [0i32; PLAYER_COUNT];
        let mut consumed = [0i32; PLAYER_COUNT];
        let mut income = [Fixed::ZERO; PLAYER_COUNT];
        for e in &self.entities {
            if !e.alive {
                continue;
            }
            if let Kind::Building(b) = e.kind {
                let st = self.balance.building(b);
                let p = usize::from(e.owner.0);
                produced[p] += st.power_produced;
                consumed[p] += st.power_consumed;
                income[p] = income[p] + st.credit_income;
            }
        }
        let mut powered = [false; PLAYER_COUNT];
        for p in 0..PLAYER_COUNT {
            powered[p] = produced[p] >= consumed[p];
            let factor = if powered[p] {
                Fixed::ONE
            } else {
                Fixed::from_ratio(1, 2)
            };
            self.players[p].credits = self.players[p].credits + income[p] * factor;
        }
        powered
    }

    fn run_production(&mut self, powered: [bool; PLAYER_COUNT]) {
        let mut spawns: Vec<(PlayerId, UnitKind, Vec2)> = Vec::new();
        for e in &mut self.entities {
            if !e.alive || !matches!(e.kind, Kind::Building(BuildingKind::Barracks)) {
                continue;
            }
            if !powered[usize::from(e.owner.0)] {
                continue;
            }
            if let Some(&front) = e.build_queue.first() {
                e.build_progress += 1;
                if e.build_progress >= self.balance.unit(front).build_time {
                    e.build_progress = 0;
                    e.build_queue.remove(0);
                    let pos = e.pos + Vec2::new(Fixed::ONE, Fixed::ZERO);
                    spawns.push((e.owner, front, pos));
                }
            }
        }
        for (owner, kind, pos) in spawns {
            self.add_unit(owner, kind, pos);
        }
    }

    fn run_movement(&mut self) {
        for e in &mut self.entities {
            if !e.alive {
                continue;
            }
            let Kind::Unit(uk) = e.kind else { continue };
            let Some(target) = e.move_target else {
                continue;
            };
            let speed = uk.stats().speed;
            // Head to the next waypoint, or straight to the target once the path
            // is exhausted.
            let subgoal = e
                .path
                .first()
                .map_or(target, |&(wx, wy)| tile_center(wx, wy));
            let dir = subgoal - e.pos;
            let dist = dir.length();
            if dist <= speed {
                e.pos = subgoal;
                if e.path.is_empty() {
                    e.move_target = None;
                } else {
                    e.path.remove(0);
                }
            } else {
                e.pos = e.pos + dir.scale(speed / dist);
            }
        }
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::cast_possible_wrap,
        reason = "grid cell coordinates are clamped into the map bounds before use"
    )]
    fn run_combat(&mut self) {
        let snap: Vec<(bool, u8, Vec2, ArmorType, bool)> = self
            .entities
            .iter()
            .map(|e| {
                (
                    e.alive,
                    e.owner.0,
                    e.pos,
                    armor_of(&self.balance, e.kind),
                    is_air_of(&self.balance, e.kind),
                )
            })
            .collect();

        // Spatial grid over living entities so target lookup is ~O(neighbours)
        // rather than O(n^2). The cell size is >= the largest attack range, so a
        // 3x3 cell query around an attacker contains every in-range enemy.
        let cols = (i32::from(self.map.width()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let rows = (i32::from(self.map.height()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let mut grid = alloc::vec![Vec::<usize>::new(); (cols * rows).max(1) as usize];
        for (i, t) in snap.iter().enumerate() {
            if t.0 {
                let cx = (t.2.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, cols - 1);
                let cy = (t.2.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, rows - 1);
                grid[(cy * cols + cx) as usize].push(i);
            }
        }

        let mut damage: Vec<(usize, Fixed)> = Vec::new();
        let mut lines: Vec<(Vec2, Vec2)> = Vec::new();
        let mut candidates: Vec<usize> = Vec::new();
        for e in &mut self.entities {
            if !e.alive {
                continue;
            }
            let Some(profile) = attack_of(&self.balance, e.kind) else {
                continue;
            };
            if e.cooldown > 0 {
                e.cooldown -= 1;
                continue;
            }
            // Gather candidates from the 3x3 neighbourhood in ascending index
            // order so distance ties resolve to the lowest index — identical to a
            // full linear scan (keeps the simulation bit-for-bit deterministic).
            candidates.clear();
            let cx = (e.pos.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, cols - 1);
            let cy = (e.pos.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, rows - 1);
            for ny in (cy - 1)..=(cy + 1) {
                for nx in (cx - 1)..=(cx + 1) {
                    if nx >= 0 && ny >= 0 && nx < cols && ny < rows {
                        candidates.extend_from_slice(&grid[(ny * cols + nx) as usize]);
                    }
                }
            }
            candidates.sort_unstable();

            let range_sq = profile.range * profile.range;
            let mut best: Option<(usize, Fixed)> = None;
            for &j in &candidates {
                let t = snap[j];
                if t.1 == e.owner.0 {
                    continue;
                }
                // Respect air/ground targeting: AA hits only air, most weapons
                // hit only ground.
                let target_is_air = t.4;
                if (target_is_air && !profile.targets_air)
                    || (!target_is_air && !profile.targets_ground)
                {
                    continue;
                }
                let dist_sq = (t.2 - e.pos).length_squared();
                if dist_sq <= range_sq && best.is_none_or(|(_, bd)| dist_sq < bd) {
                    best = Some((j, dist_sq));
                }
            }
            if let Some((j, _)) = best {
                let mult = damage_multiplier(profile.damage_type, snap[j].3);
                damage.push((j, profile.damage * mult));
                lines.push((e.pos, snap[j].2));
                e.cooldown = profile.period;
            }
        }
        for (j, dmg) in damage {
            self.entities[j].hp = self.entities[j].hp - dmg;
        }
        self.attacks = lines;
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn clear_dead(&mut self) {
        let mut freed_tiles: Vec<(u16, u16)> = Vec::new();
        let mut freed_slots: Vec<u32> = Vec::new();
        for (i, e) in self.entities.iter_mut().enumerate() {
            if e.alive && e.hp <= Fixed::ZERO {
                e.alive = false;
                if let Some(tile) = e.tile {
                    freed_tiles.push(tile);
                }
                freed_slots.push(i as u32);
            }
        }
        for (x, y) in freed_tiles {
            self.map.set_tile(x, y, Tile::OPEN);
        }
        self.free.extend(freed_slots);
    }
}

impl Sim {
    /// Rule-based commands for `player` this tick: follow a build order, train
    /// infantry from an idle barracks, and attack-move idle units toward the
    /// enemy base. Pure function of state (no RNG), so AI-vs-AI replays bit-for-bit.
    #[must_use]
    pub fn ai_commands(&self, player: PlayerId) -> Vec<Command> {
        let mut cmds = Vec::new();
        let Some(cc_tile) = self.command_center_tile(player) else {
            return cmds; // no base, no orders
        };
        let credits = self.credits(player);

        // Build order: act on the first missing essential, then build no more
        // this tick (keeps spending paced and deterministic).
        let mut building_this_tick = false;
        for kind in [
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
        ] {
            if !self.has_building(player, kind) {
                if credits >= kind.stats().cost {
                    if let Some((x, y)) = self.find_buildable_near(cc_tile) {
                        cmds.push(Command::Build {
                            owner: player,
                            kind,
                            x,
                            y,
                        });
                    }
                }
                building_this_tick = true;
                break;
            }
        }

        // Economy is up: train infantry from an idle barracks.
        if !building_this_tick {
            if let Some(barracks) = self.idle_barracks(player) {
                if credits >= UnitKind::Infantry.stats().cost {
                    cmds.push(Command::Train {
                        owner: player,
                        barracks,
                        kind: UnitKind::Infantry,
                    });
                }
            }
        }

        // Periodically push idle units toward the enemy base. Re-issuing a Move
        // (and thus running A*) for every idle unit every tick is the classic RTS
        // perf trap; throttling by tick keeps pathfinding cheap and is still fully
        // deterministic.
        if self.tick.is_multiple_of(MOVE_REISSUE_PERIOD) {
            if let Some(target) = self.enemy_command_center_pos(player) {
                for unit in self.idle_units(player) {
                    cmds.push(Command::Move {
                        owner: player,
                        unit,
                        target,
                    });
                }
            }
        }
        cmds
    }

    fn command_center_tile(&self, player: PlayerId) -> Option<(u16, u16)> {
        self.entities
            .iter()
            .find(|e| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .and_then(|e| e.tile)
    }

    fn enemy_command_center_pos(&self, player: PlayerId) -> Option<Vec2> {
        self.command_center_pos(PlayerId(1 - player.0))
    }

    fn has_building(&self, player: PlayerId, kind: BuildingKind) -> bool {
        self.entities
            .iter()
            .any(|e| e.alive && e.owner == player && e.kind == Kind::Building(kind))
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn idle_barracks(&self, player: PlayerId) -> Option<EntityId> {
        self.entities
            .iter()
            .enumerate()
            .find(|(_, e)| {
                e.alive
                    && e.owner == player
                    && e.kind == Kind::Building(BuildingKind::Barracks)
                    && e.build_queue.is_empty()
            })
            .map(|(i, _)| EntityId(i as u32))
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn idle_units(&self, player: PlayerId) -> Vec<EntityId> {
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, e)| {
                e.alive
                    && e.owner == player
                    && matches!(e.kind, Kind::Unit(_))
                    && e.move_target.is_none()
            })
            .map(|(i, _)| EntityId(i as u32))
            .collect()
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "scan stays within the bounds-checked, non-negative u16 grid"
    )]
    fn find_buildable_near(&self, center: (u16, u16)) -> Option<(u16, u16)> {
        let cx = i32::from(center.0);
        let cy = i32::from(center.1);
        for r in 1..=24i32 {
            for dy in -r..=r {
                for dx in -r..=r {
                    if dx.abs().max(dy.abs()) != r {
                        continue;
                    }
                    let x = cx + dx;
                    let y = cy + dy;
                    if x >= 0 && y >= 0 && self.map.tile(x, y).is_some_and(|t| t.buildable) {
                        return Some((x as u16, y as u16));
                    }
                }
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::{
        BuildingKind, Command, EntityId, EntityKindView, PlayerId, Sim, UnitKind, WaveConfig,
    };
    use crate::fixed::Fixed;
    use crate::game::map::Map;
    use crate::vec::Vec2;

    fn f(n: i32) -> Fixed {
        Fixed::from_int(n)
    }
    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(f(x), f(y))
    }
    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    #[test]
    fn new_sim_has_starting_credits_and_no_winner() {
        let s = Sim::new(Map::new(16, 16), 1, f(500));
        assert_eq!(s.credits(P0), f(500));
        assert_eq!(s.credits(P1), f(500));
        assert_eq!(s.winner(), None);
        assert_eq!(s.tick(), 0);
    }

    #[test]
    fn income_accrues_when_powered() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        s.add_building(P0, BuildingKind::Refinery, 5, 1);
        s.step(&[]);
        // Refinery income is 5/tick while powered.
        assert_eq!(s.credits(P0), f(5));
    }

    #[test]
    fn power_deficit_halves_income() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        // Refinery consumes 20 but there is no power plant -> deficit.
        s.add_building(P0, BuildingKind::Refinery, 5, 1);
        s.step(&[]);
        assert_eq!(s.credits(P0), Fixed::from_ratio(5, 2)); // 2.5
    }

    #[test]
    fn build_command_places_building_and_charges() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(1000));
        let before = s.entity_count();
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::PowerPlant,
            x: 5,
            y: 5,
        }]);
        assert_eq!(s.entity_count(), before + 1);
        assert_eq!(s.credits(P0), f(900)); // 1000 - 100
        assert!(!s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn build_fails_when_unaffordable() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(50));
        s.step(&[Command::Build {
            owner: P0,
            kind: BuildingKind::PowerPlant,
            x: 5,
            y: 5,
        }]);
        assert_eq!(s.entity_count(), 0);
        assert_eq!(s.credits(P0), f(50));
        assert!(s.map().tile(5, 5).unwrap().buildable);
    }

    #[test]
    fn training_spawns_a_unit_after_build_time() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        s.add_building(P0, BuildingKind::PowerPlant, 3, 1);
        let barracks = s.add_building(P0, BuildingKind::Barracks, 5, 1);
        let units_before = s.unit_count(P0);
        s.step(&[Command::Train {
            owner: P0,
            barracks,
            kind: UnitKind::Infantry,
        }]);
        assert_eq!(s.credits(P0), f(950)); // charged immediately
                                           // Infantry build time is 30 ticks; not yet spawned at 29.
        for _ in 0..28 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P0), units_before);
        s.step(&[]); // 30th tick
        assert_eq!(s.unit_count(P0), units_before + 1);
    }

    #[test]
    fn unit_moves_toward_target_and_arrives() {
        let mut s = Sim::new(Map::new(64, 64), 1, f(0));
        let u = s.add_unit(P0, UnitKind::Infantry, v(0, 0));
        s.step(&[Command::Move {
            owner: P0,
            unit: u,
            target: v(10, 0),
        }]);
        // moved at least a little on the first tick
        assert!(s.position(u).unwrap().x > Fixed::ZERO);
        for _ in 0..200 {
            s.step(&[]);
        }
        assert_eq!(s.position(u), Some(v(10, 0)));
    }

    #[test]
    fn combat_destroys_an_enemy_structure() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let tank = s.add_unit(P0, UnitKind::Tank, v(0, 0));
        let wall = s.add_building(P1, BuildingKind::Wall, 1, 1);
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(!s.is_alive(wall));
        assert!(s.is_alive(tank));
    }

    #[test]
    fn unit_does_not_move_to_a_walled_off_target() {
        let mut s = Sim::new(Map::new(8, 8), 1, f(0));
        // A full wall on column x=4 splits the map in two.
        for y in 0..8 {
            s.add_building(P1, BuildingKind::Wall, 4, y);
        }
        let u = s.add_unit(P0, UnitKind::Infantry, v(0, 0));
        let before = s.position(u);
        s.step(&[Command::Move {
            owner: P0,
            unit: u,
            target: Vec2::new(f(7), f(7)),
        }]);
        for _ in 0..50 {
            s.step(&[]);
        }
        // No route across the wall, so the unit never accepted a move target.
        assert_eq!(s.position(u), before);
    }

    #[test]
    fn winner_is_the_last_player_with_a_command_center() {
        let mut only_p0 = Sim::new(Map::new(16, 16), 1, f(0));
        only_p0.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        assert_eq!(only_p0.winner(), Some(P0));

        let mut both = Sim::new(Map::new(16, 16), 1, f(0));
        both.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        both.add_building(P1, BuildingKind::CommandCenter, 10, 10);
        assert_eq!(both.winner(), None);
    }

    #[test]
    fn views_report_living_entities_for_rendering() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let cc = s.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        let tank = s.add_unit(P1, UnitKind::Tank, v(3, 3));
        let views = s.views();
        assert_eq!(views.len(), 2);
        let cc_view = views.iter().find(|w| w.id == cc).unwrap();
        assert_eq!(cc_view.owner, P0);
        assert!(matches!(
            cc_view.kind,
            EntityKindView::Building(BuildingKind::CommandCenter)
        ));
        let tank_view = views.iter().find(|w| w.id == tank).unwrap();
        assert_eq!(tank_view.pos, v(3, 3));
        assert!(matches!(
            tank_view.kind,
            EntityKindView::Unit(UnitKind::Tank)
        ));
    }

    fn scenario(seed: u64) -> Sim {
        let mut s = Sim::new(Map::new(48, 48), seed, f(1000));
        s.add_building(P0, BuildingKind::CommandCenter, 2, 2);
        s.add_building(P0, BuildingKind::PowerPlant, 4, 2);
        s.add_building(P1, BuildingKind::CommandCenter, 40, 40);
        s.add_unit(P0, UnitKind::Tank, v(5, 5));
        s.add_unit(P1, UnitKind::Infantry, v(7, 5));
        s
    }

    #[test]
    fn same_setup_and_commands_produce_same_hash() {
        let mut a = scenario(99);
        let mut b = scenario(99);
        let script: [&[Command]; 5] = [
            &[Command::Build {
                owner: P0,
                kind: BuildingKind::Barracks,
                x: 6,
                y: 2,
            }],
            &[Command::Move {
                owner: P0,
                unit: EntityId(3),
                target: Vec2::new(f(7), f(5)),
            }],
            &[],
            &[Command::Build {
                owner: P0,
                kind: BuildingKind::Refinery,
                x: 8,
                y: 2,
            }],
            &[],
        ];
        for cmds in script {
            a.step(cmds);
            b.step(cmds);
            assert_eq!(a.state_hash(), b.state_hash());
        }
        // and they keep agreeing for a while
        for _ in 0..50 {
            a.step(&[]);
            b.step(&[]);
            assert_eq!(a.state_hash(), b.state_hash());
        }
    }

    #[test]
    fn ai_builds_up_its_economy_and_army() {
        let mut s = Sim::new(Map::new(32, 32), 1, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        for _ in 0..400 {
            let cmds = s.ai_commands(P0);
            s.step(&cmds);
        }
        // It should have expanded its base and trained at least one unit.
        assert!(s.unit_count(P0) >= 1);
        assert!(s.entity_count() >= 4); // CC + power + refinery + barracks (+ units)
    }

    fn run_ai_vs_ai(seed: u64) -> Vec<u64> {
        let mut s = Sim::new(Map::new(40, 40), seed, f(3000));
        s.add_building(P0, BuildingKind::CommandCenter, 4, 4);
        s.add_building(P1, BuildingKind::CommandCenter, 35, 35);
        let mut hashes = Vec::new();
        for _ in 0..300 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
            hashes.push(s.state_hash());
        }
        hashes
    }

    #[test]
    fn ai_vs_ai_is_deterministic() {
        assert_eq!(run_ai_vs_ai(7), run_ai_vs_ai(7));
    }

    #[test]
    fn golden_hash_pins_cross_target_determinism() {
        // A fixed scripted AI-vs-AI run. This constant must be byte-identical on
        // every target — native, wasm, mobile, server. A mismatch when this test
        // is run on another platform is a determinism regression, full stop.
        let mut s = Sim::new(Map::new(40, 40), 12_345, f(1500));
        s.add_building(P0, BuildingKind::CommandCenter, 5, 20);
        s.add_building(P1, BuildingKind::CommandCenter, 34, 20);
        for _ in 0..120 {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(s.ai_commands(P1));
            s.step(&cmds);
        }
        assert_eq!(s.state_hash(), 10_799_591_089_414_755_275);
    }

    fn wave_cfg() -> WaveConfig {
        WaveConfig {
            first_delay: 0,
            interval: 50,
            base_size: 2,
            growth: 1,
            spawn: v(36, 20),
            unit: UnitKind::Infantry,
            attacker: P1,
            defender: P0,
        }
    }

    #[test]
    fn wave_countdown_reports_time_to_next_wave() {
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        assert_eq!(s.ticks_until_next_wave(), None);
        s.set_waves(wave_cfg());
        assert_eq!(s.ticks_until_next_wave(), Some(0)); // first_delay is 0
        s.step(&[]);
        assert_eq!(s.ticks_until_next_wave(), Some(49)); // interval 50, 1 tick in
    }

    #[test]
    fn waves_spawn_on_schedule_and_grow() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
        s.set_waves(wave_cfg());
        s.step(&[]); // tick 0 -> wave 0 (base_size = 2)
        assert_eq!(s.unit_count(P1), 2);
        for _ in 0..50 {
            s.step(&[]);
        }
        // 51 steps total -> tick 50 fired wave 1 (size 3); none have died yet.
        assert_eq!(s.unit_count(P1), 5);
    }

    #[test]
    fn wave_units_march_toward_the_defender() {
        let mut s = Sim::new(Map::new(40, 40), 1, f(0));
        s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
        s.set_waves(wave_cfg());
        s.step(&[]);
        let uid = s.views().into_iter().find(|w| w.owner == P1).unwrap().id;
        let x0 = s.position(uid).unwrap().x;
        for _ in 0..20 {
            s.step(&[]);
        }
        // Spawned at x=36, base at x=3, so it should be moving left.
        assert!(s.position(uid).unwrap().x < x0);
    }

    #[test]
    fn waves_are_deterministic() {
        let run = |seed: u64| {
            let mut s = Sim::new(Map::new(40, 40), seed, f(0));
            s.add_building(P0, BuildingKind::CommandCenter, 3, 20);
            s.set_waves(wave_cfg());
            let mut hashes = Vec::new();
            for _ in 0..120 {
                s.step(&[]);
                hashes.push(s.state_hash());
            }
            hashes
        };
        assert_eq!(run(7), run(7));
    }

    #[test]
    fn combat_scales_with_the_spatial_grid() {
        // Two interleaved blobs of infantry, in range of each other.
        let mut s = Sim::new(Map::new(48, 48), 1, f(0));
        let n: i32 = 150;
        for i in 0..n {
            let row = i % 10;
            let col = i / 10;
            s.add_unit(P0, UnitKind::Infantry, v(10 + col, 5 + row));
            s.add_unit(P1, UnitKind::Infantry, v(12 + col, 5 + row));
        }
        let start = s.entity_count();
        assert_eq!(start, 300); // 150 per side
        for _ in 0..120 {
            s.step(&[]);
        }
        // They were within range and fought, so casualties occurred.
        assert!(s.entity_count() < start);
    }

    #[test]
    fn dead_slots_are_recycled() {
        let mut s = Sim::new(Map::new(16, 16), 1, f(0));
        let _tank = s.add_unit(P0, UnitKind::Tank, v(0, 0)); // slot 0
        let wall = s.add_building(P1, BuildingKind::Wall, 1, 1); // slot 1
        for _ in 0..200 {
            s.step(&[]); // the tank destroys the wall
        }
        assert!(!s.is_alive(wall));
        // The next spawn reuses the wall's freed slot rather than growing the list.
        let reused = s.add_unit(P0, UnitKind::Infantry, v(5, 5));
        assert_eq!(reused, wall);
    }

    #[test]
    fn air_is_immune_to_ground_fire_but_dies_to_anti_air() {
        // A helicopter shreds adjacent infantry, which cannot hit air at all.
        let mut s = Sim::new(Map::new(20, 20), 1, f(0));
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(5, 5));
        let inf = s.add_unit(P1, UnitKind::Infantry, v(6, 5));
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(s.is_alive(heli));
        assert!(!s.is_alive(inf));

        // An AA turret brings the helicopter down.
        let mut s2 = Sim::new(Map::new(20, 20), 1, f(0));
        let heli2 = s2.add_unit(P0, UnitKind::Helicopter, v(5, 5));
        s2.add_building(P1, BuildingKind::AaTurret, 6, 5);
        for _ in 0..400 {
            s2.step(&[]);
        }
        assert!(!s2.is_alive(heli2));
    }
}
