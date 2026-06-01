//! The integrated RTS simulation: two players, an economy, buildings, units,
//! combat, and a win condition — all deterministic and fixed-point.
//!
//! [`Sim::step`] advances one fixed tick by, in order: applying the ordered
//! command batch, running the economy, advancing production, moving units,
//! resolving combat, and clearing the dead. [`Sim::state_hash`] fingerprints the
//! whole thing so two runs (or two platforms, or client and server) can be proven
//! identical.

use crate::fixed::Fixed;
use crate::game::map::{Map, Tile};
use crate::game::stats::{damage_multiplier, ArmorType, AttackProfile, BuildingKind, UnitKind};
use crate::hash::Fnv;
use crate::rng::Rng;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Number of players (single-player vs one AI for now; `PvP` later).
pub const PLAYER_COUNT: usize = 2;

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

/// The deterministic RTS world.
#[derive(Clone, Debug)]
pub struct Sim {
    tick: u64,
    rng: Rng,
    map: Map,
    players: [Player; PLAYER_COUNT],
    entities: Vec<Entity>,
}

const fn armor_of(kind: Kind) -> ArmorType {
    match kind {
        Kind::Unit(u) => u.stats().armor,
        Kind::Building(b) => b.stats().armor,
    }
}

const fn attack_of(kind: Kind) -> Option<AttackProfile> {
    match kind {
        Kind::Unit(u) => Some(u.stats().attack),
        Kind::Building(b) => b.stats().attack,
    }
}

const fn max_hp(kind: Kind) -> Fixed {
    match kind {
        Kind::Unit(u) => u.stats().max_hp,
        Kind::Building(b) => b.stats().max_hp,
    }
}

const fn unit_tag(u: UnitKind) -> u64 {
    match u {
        UnitKind::Infantry => 1,
        UnitKind::Tank => 2,
        UnitKind::AntiArmor => 3,
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
        }
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
        let id = EntityId(self.entities.len() as u32);
        self.entities.push(Entity {
            owner,
            kind: Kind::Building(kind),
            alive: true,
            pos,
            hp: max_hp(Kind::Building(kind)),
            cooldown: 0,
            move_target: None,
            tile: Some((x, y)),
            build_queue: Vec::new(),
            build_progress: 0,
        });
        id
    }

    /// Places a unit for free (scenario setup / production).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    pub fn add_unit(&mut self, owner: PlayerId, kind: UnitKind, pos: Vec2) -> EntityId {
        let id = EntityId(self.entities.len() as u32);
        self.entities.push(Entity {
            owner,
            kind: Kind::Unit(kind),
            alive: true,
            pos,
            hp: max_hp(Kind::Unit(kind)),
            cooldown: 0,
            move_target: None,
            tile: None,
            build_queue: Vec::new(),
            build_progress: 0,
        });
        id
    }

    /// Advances the simulation one fixed tick.
    pub fn step(&mut self, commands: &[Command]) {
        for command in commands {
            self.apply_command(command);
        }
        let powered = self.run_economy();
        self.run_production(powered);
        self.run_movement();
        self.run_combat();
        self.clear_dead();
        self.tick += 1;
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
                let cost = kind.stats().cost;
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
                let cost = kind.stats().cost;
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
                if let Some(e) = self.entities.get_mut(unit.0 as usize) {
                    if e.alive && e.owner == owner && matches!(e.kind, Kind::Unit(_)) {
                        e.move_target = Some(target);
                    }
                }
            }
        }
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
                let st = b.stats();
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
                if e.build_progress >= front.stats().build_time {
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
            if let Kind::Unit(uk) = e.kind {
                if let Some(target) = e.move_target {
                    let speed = uk.stats().speed;
                    let dir = target - e.pos;
                    let dist = dir.length();
                    if dist <= speed {
                        e.pos = target;
                        e.move_target = None;
                    } else {
                        e.pos = e.pos + dir.scale(speed / dist);
                    }
                }
            }
        }
    }

    fn run_combat(&mut self) {
        let snap: Vec<(bool, u8, Vec2, ArmorType)> = self
            .entities
            .iter()
            .map(|e| (e.alive, e.owner.0, e.pos, armor_of(e.kind)))
            .collect();
        let mut damage: Vec<(usize, Fixed)> = Vec::new();
        for e in &mut self.entities {
            if !e.alive {
                continue;
            }
            let Some(profile) = attack_of(e.kind) else {
                continue;
            };
            if e.cooldown > 0 {
                e.cooldown -= 1;
                continue;
            }
            let range_sq = profile.range * profile.range;
            let mut best: Option<(usize, Fixed)> = None;
            for (j, t) in snap.iter().enumerate() {
                if !t.0 || t.1 == e.owner.0 {
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
                e.cooldown = profile.period;
            }
        }
        for (j, dmg) in damage {
            self.entities[j].hp = self.entities[j].hp - dmg;
        }
    }

    fn clear_dead(&mut self) {
        let mut freed: Vec<(u16, u16)> = Vec::new();
        for e in &mut self.entities {
            if e.alive && e.hp <= Fixed::ZERO {
                e.alive = false;
                if let Some(tile) = e.tile {
                    freed.push(tile);
                }
            }
        }
        for (x, y) in freed {
            self.map.set_tile(x, y, Tile::OPEN);
        }
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

        // Always push idle units toward the enemy base.
        if let Some(target) = self.enemy_command_center_pos(player) {
            for unit in self.idle_units(player) {
                cmds.push(Command::Move {
                    owner: player,
                    unit,
                    target,
                });
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
        let enemy = PlayerId(1 - player.0);
        self.entities
            .iter()
            .find(|e| {
                e.alive && e.owner == enemy && e.kind == Kind::Building(BuildingKind::CommandCenter)
            })
            .map(|e| e.pos)
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
    use super::{BuildingKind, Command, EntityId, PlayerId, Sim, UnitKind};
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
    fn winner_is_the_last_player_with_a_command_center() {
        let mut only_p0 = Sim::new(Map::new(16, 16), 1, f(0));
        only_p0.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        assert_eq!(only_p0.winner(), Some(P0));

        let mut both = Sim::new(Map::new(16, 16), 1, f(0));
        both.add_building(P0, BuildingKind::CommandCenter, 1, 1);
        both.add_building(P1, BuildingKind::CommandCenter, 10, 10);
        assert_eq!(both.winner(), None);
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
}
