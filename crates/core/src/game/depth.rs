//! Kestrel depth rules: RTS combat, match shape and run mode, isolated behind
//! the narrow `depth` flag that only [`crate::game::scenario::kestrel_reach`]
//! sets. Every behaviour here checks [`Sim::is_depth`] (`earthfront && depth`),
//! never `earthfront` alone: the Survival map also enables Earthfront and must
//! stay byte-identical.
//!
//! State lives in [`DepthUnit`] (one per entity, `Entity::dp`) and
//! [`DepthGlobal`] (`Sim::dg`). Both are folded into [`Sim::state_hash`] only
//! when depth is on. Later tasks append fields at the END of each struct and
//! their hash writes at the END of its `hash_into`, in task order, never
//! reordering.

use super::{attack_of, is_air_of, tile_center, EntityId, Kind, PlayerId, Sim, COMBAT_CELL};
use crate::fixed::Fixed;
use crate::game::hex;
use crate::game::map::Map;
use crate::game::stats::{AttackProfile, UnitKind};
use crate::hash::Fnv;
use crate::vec::Vec2;
use alloc::vec::Vec;

/// Extra reach of the acquisition ring beyond a unit's weapon range: an idle
/// unit engages the nearest targetable enemy within `range + ACQUIRE_BONUS`.
pub(super) const ACQUIRE_BONUS: Fixed = Fixed::from_int(3);
/// How far a unit pulled off by acquisition or a call for help may stray from
/// its anchor before it drops the fight and walks home.
pub(super) const LEASH: Fixed = Fixed::from_int(6);
/// Idle friendly units within this distance of a damaged unit or building
/// answer the hit by engaging the attacker.
pub(super) const ASSIST_RADIUS: Fixed = Fixed::from_int(6);
/// Ticks between re-paths of a chase while the engaged target keeps moving.
pub(super) const REPATH_PERIOD: u64 = 20;
/// Task 12: same-owner units on the same layer closer than this are pushed
/// apart after movement (half the overlap each).
pub(super) const SEPARATION: Fixed = Fixed::from_ratio(45, 100);

/// Unit push axes for coincident units, one per hex direction (60 degrees
/// apart, starting at 30 degrees), picked by the higher index `j % 6`.
const HEX_AXES: [(i64, i64); 6] = [
    (866, 500),
    (0, 1000),
    (-866, 500),
    (-866, -500),
    (0, -1000),
    (866, -500),
];

/// Per-entity depth state. Fields are appended at the END in task order.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthUnit {
    /// Task 11: where this unit stood when it last fell idle. Auto-acquisition
    /// and calls for help pull it off this point by at most [`LEASH`]; it walks
    /// back once the fight is over. Cleared by a player (or AI) `Move` or
    /// `AttackMove`, re-recorded where that order ends.
    pub(super) anchor: Option<Vec2>,
    /// Task 11: the enemy this unit chose to fight on its own (acquisition or a
    /// call for help). Dropped by `clear_dead` the tick its target dies, so a
    /// freed and reused entity slot is never chased.
    pub(super) engaged: Option<EntityId>,
}

impl DepthUnit {
    /// Folds this entity's depth state into the world hash (depth on only).
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        match self.anchor {
            Some(a) => {
                h.write_u64(1);
                h.write_i64(a.x.to_bits());
                h.write_i64(a.y.to_bits());
            }
            None => h.write_u64(0),
        }
        match self.engaged {
            Some(id) => {
                h.write_u64(1);
                h.write_u64(u64::from(id.0));
            }
            None => h.write_u64(0),
        }
    }
}

/// World-wide depth state. Empty until the match-shape tasks append to it.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthGlobal {}

impl DepthGlobal {
    /// Folds the global depth state into the world hash (depth on only).
    #[allow(
        clippy::unused_self,
        clippy::needless_pass_by_ref_mut,
        clippy::missing_const_for_fn,
        reason = "the fixed hash call site exists before the fields that later depth tasks append here"
    )]
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        let _ = h;
    }
}

impl Sim {
    /// Turns on the Kestrel depth rules. Called only by
    /// [`crate::game::scenario::kestrel_reach`], after `enable_earthfront`;
    /// depth means nothing without Earthfront (see [`Sim::is_depth`]).
    #[allow(
        clippy::missing_const_for_fn,
        reason = "later depth tasks draw deterministic match state here"
    )]
    pub fn enable_depth(&mut self) {
        self.depth = true;
    }

    /// Whether the Kestrel depth rules are active: Earthfront AND depth. Every
    /// depth behaviour and every depth hash write checks this, never
    /// `earthfront` alone.
    #[must_use]
    pub const fn is_depth(&self) -> bool {
        self.earthfront && self.depth
    }

    /// The weapon of entity `i` when it is a unit that may fight on its own:
    /// alive, built, not stunned, armed and not a Harvester. Ammunition is
    /// checked by the callers (a dry unit still walks home).
    fn depth_fighter(&self, i: usize) -> Option<AttackProfile> {
        let e = &self.entities[i];
        if !e.alive || e.construction_remaining > 0 || e.stun_ticks > 0 {
            return None;
        }
        if !matches!(e.kind, Kind::Unit(k) if k != UnitKind::Harvester) {
            return None;
        }
        attack_of(&self.balance, e.kind)
    }

    /// Whether a unit with weapon `profile` owned by `owner` may shoot entity
    /// `j`: the same test `run_combat` applies (alive, another owner, and the
    /// weapon reaches the target's layer).
    fn depth_can_hit(&self, profile: AttackProfile, owner: PlayerId, j: usize) -> bool {
        let Some(t) = self.entities.get(j) else {
            return false;
        };
        if !t.alive || t.hp <= Fixed::ZERO || t.owner == owner {
            return false;
        }
        if is_air_of(&self.balance, t.kind) {
            profile.targets_air
        } else {
            profile.targets_ground
        }
    }

    /// The nearest enemy of unit `i` (weapon `profile`) within `radius` of the
    /// unit and within `reach` of `anchor`; ties go to the lowest index.
    fn depth_nearest_enemy(
        &self,
        grid: &DepthGrid,
        scratch: &mut Vec<usize>,
        i: usize,
        profile: AttackProfile,
        radius: Fixed,
        (anchor, reach): (Vec2, Fixed),
    ) -> Option<usize> {
        let e = &self.entities[i];
        let radius_sq = radius * radius;
        let reach_sq = reach * reach;
        grid.gather(e.pos, radius, scratch);
        let mut best: Option<(usize, Fixed)> = None;
        for &j in scratch.iter() {
            if !self.depth_can_hit(profile, e.owner, j) {
                continue;
            }
            let tpos = self.entities[j].pos;
            let d = (tpos - e.pos).length_squared();
            if d > radius_sq || (tpos - anchor).length_squared() > reach_sq {
                continue;
            }
            if best.is_none_or(|(_, bd)| d < bd) {
                best = Some((j, d));
            }
        }
        best.map(|(j, _)| j)
    }

    /// Sends unit `i` back to its anchor. A return that cannot be pathed (or is
    /// redirected to a substitute tile) re-anchors the unit where the order
    /// really ends, so it never retries a hopeless walk every tick.
    fn depth_return(&mut self, i: usize, anchor: Vec2) {
        let e = &mut self.entities[i];
        e.dp.engaged = None;
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, anchor, false);
        let e = &mut self.entities[i];
        match e.move_target {
            None => e.dp.anchor = Some(e.pos),
            Some(t) if t != anchor => e.dp.anchor = Some(t),
            Some(_) => {}
        }
    }

    /// Orders unit `i` after its engaged target at `tpos`. Returns false when
    /// the chase cannot stay on the leash: no path, or a path that leaves the
    /// leash before the target is in weapon range (a detour around water). The
    /// failed move is cancelled so the unit never wanders off on it.
    fn depth_chase(&mut self, i: usize, tpos: Vec2, anchor: Vec2, range: Fixed) -> bool {
        let e = &mut self.entities[i];
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, tpos, true);
        let leash = leash_of(&self.entities[i].dp);
        let leash_sq = leash * leash;
        let range_sq = range * range;
        let e = &mut self.entities[i];
        let fits = e.move_target.is_some()
            && e.path.iter().all(|&(x, y)| {
                let c = tile_center(x, y);
                (c - anchor).length_squared() <= leash_sq || (c - tpos).length_squared() <= range_sq
            });
        if !fits {
            e.move_target = None;
            e.path.clear();
            e.attack_move = false;
        }
        fits
    }

    /// Engages enemy `j` with unit `i`: records it, and chases it when it is out
    /// of weapon range. A chase that cannot stay on the leash leaves a unit at
    /// home engaged and waiting (it re-tries every [`REPATH_PERIOD`] ticks while
    /// the target moves); a unit away from home drops the fight and walks back.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 for any real game"
    )]
    fn depth_engage(&mut self, i: usize, j: usize, anchor: Vec2, range: Fixed) {
        self.entities[i].dp.engaged = Some(EntityId(j as u32));
        let pos = self.entities[i].pos;
        let tpos = self.entities[j].pos;
        if (tpos - pos).length_squared() <= range * range {
            return;
        }
        if !self.depth_chase(i, tpos, anchor, range)
            && (pos - anchor).length_squared() > HOME_SLACK * HOME_SLACK
        {
            self.depth_return(i, anchor);
        }
    }

    /// Task 11 auto-acquire and leash, run every depth tick before movement in
    /// ascending entity index. For every unit that may fight on its own:
    /// - an idle unit (no move order) records its anchor if it has none; a unit
    ///   moving on someone else's order (no anchor) is left alone;
    /// - an engagement is dropped when its target is dead, untargetable, or
    ///   further than `LEASH + range` from the anchor, when the unit has strayed
    ///   more than [`LEASH`] from the anchor, or when it is out of ammunition;
    /// - a unit with no engagement takes the nearest targetable enemy within
    ///   `range + ACQUIRE_BONUS` of itself (and `LEASH + range` of its anchor),
    ///   chasing it with an attack-move when it is out of weapon range and
    ///   re-pathing every [`REPATH_PERIOD`] ticks while the target moves;
    /// - with nothing to fight it walks back to its anchor. A unit walking home
    ///   does not acquire on the way (no ping-pong at the leash edge), though
    ///   `run_combat` still fires at anything in range as it passes.
    #[allow(
        clippy::cast_possible_truncation,
        reason = "entity index fits u32 and u64 for any real game"
    )]
    pub(super) fn run_depth_acquire(&mut self) {
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        for i in 0..self.entities.len() {
            let Some(profile) = self.depth_fighter(i) else {
                continue;
            };
            let e = &self.entities[i];
            let (pos, owner, idle) = (e.pos, e.owner, e.move_target.is_none());
            let anchor = match e.dp.anchor {
                Some(a) => a,
                None if idle => {
                    self.entities[i].dp.anchor = Some(pos);
                    pos
                }
                // Moving on a player or AI order: not ours to steer here.
                None => continue,
            };
            let e = &self.entities[i];
            let armed = e.ammunition > 0;
            let range = profile.range;
            let leash = leash_of(&e.dp);
            let leash_sq = leash * leash;
            let reach = leash + range;
            let home_sq = (pos - anchor).length_squared();
            let returning = !idle && e.move_target == Some(anchor) && e.dp.engaged.is_none();
            // Validate the current engagement.
            let mut engaged = e.dp.engaged.map(|t| t.0 as usize).filter(|&j| {
                armed
                    && home_sq <= leash_sq
                    && self.depth_can_hit(profile, owner, j)
                    && (self.entities[j].pos - anchor).length_squared() <= reach * reach
            });
            if engaged.is_none() {
                self.entities[i].dp.engaged = None;
            }
            if home_sq > leash_sq || !armed {
                // Off the leash (or dry): drop everything and walk home.
                if !returning && home_sq > HOME_SLACK * HOME_SLACK {
                    self.depth_return(i, anchor);
                }
                continue;
            }
            // Look for a (nearer) enemy when standing still, or when a chase has
            // lost its target; never while walking home.
            if may_acquire(&self.entities[i].dp) && (idle || (engaged.is_none() && !returning)) {
                let ring = range + ACQUIRE_BONUS;
                if let Some(j) =
                    self.depth_nearest_enemy(&grid, &mut scratch, i, profile, ring, (anchor, reach))
                {
                    let nearer = engaged.is_none_or(|k| {
                        let d = |x: usize| (self.entities[x].pos - pos).length_squared();
                        k != j && d(j) < d(k)
                    });
                    if nearer {
                        self.depth_engage(i, j, anchor, range);
                        continue;
                    }
                }
            }
            if let Some(j) = engaged.take() {
                // Keep after a target that has stepped out of weapon range.
                let tpos = self.entities[j].pos;
                let e = &self.entities[i];
                let out_of_range = (tpos - pos).length_squared() > range * range;
                let due = (self.tick + i as u64).is_multiple_of(REPATH_PERIOD);
                if out_of_range && due && e.order_goal != Some(tpos) && may_chase(&e.dp) {
                    let ok = self.depth_chase(i, tpos, anchor, range);
                    if !ok && home_sq > HOME_SLACK * HOME_SLACK {
                        self.depth_return(i, anchor);
                    }
                }
                continue;
            }
            if !returning && home_sq > HOME_SLACK * HOME_SLACK {
                self.depth_return(i, anchor);
            }
        }
    }

    /// Task 11 under-attack response, run at the end of `run_combat` with this
    /// tick's hits as (victim, attacker) in damage order: idle friendly units
    /// within [`ASSIST_RADIUS`] of the victim that are not already fighting and
    /// whose weapon can hit the attacker engage it, on the same leash (the
    /// attacker must lie within `LEASH + range` of the responder's anchor).
    /// Applies to every owner, so the alien base and its waves answer too.
    pub(super) fn depth_respond_to_hits(&mut self, hits: &[(usize, usize)]) {
        if hits.is_empty() {
            return;
        }
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        let assist_sq = ASSIST_RADIUS * ASSIST_RADIUS;
        for &(victim, attacker) in hits {
            let vpos = self.entities[victim].pos;
            let side = self.entities[victim].owner;
            if !self.entities[attacker].alive || self.entities[attacker].hp <= Fixed::ZERO {
                continue;
            }
            grid.gather(vpos, ASSIST_RADIUS, &mut scratch);
            for &k in &scratch {
                let Some(profile) = self.depth_fighter(k) else {
                    continue;
                };
                let e = &self.entities[k];
                if e.owner != side
                    || e.move_target.is_some()
                    || e.dp.engaged.is_some()
                    || e.ammunition == 0
                    || !may_respond(&e.dp)
                    || (e.pos - vpos).length_squared() > assist_sq
                    || !self.depth_can_hit(profile, e.owner, attacker)
                {
                    continue;
                }
                let anchor = e.dp.anchor.unwrap_or(e.pos);
                let reach = leash_of(&e.dp) + profile.range;
                if (self.entities[attacker].pos - anchor).length_squared() > reach * reach {
                    continue;
                }
                self.entities[k].dp.anchor = Some(anchor);
                self.depth_engage(k, attacker, anchor, profile.range);
            }
        }
    }

    /// `clear_dead` hook: forget engagements whose target slot was just freed,
    /// before production or waves can hand the slot to a new entity.
    pub(super) fn depth_drop_dangling(&mut self, freed: &[u32]) {
        for e in &mut self.entities {
            if e.dp.engaged.is_some_and(|t| freed.contains(&t.0)) {
                e.dp.engaged = None;
            }
        }
    }

    /// Re-issues unit `i`'s current order from where it stands (its path no
    /// longer starts beside its tile). An order that can no longer be pathed
    /// is dropped, so the unit idles instead of retrying every tick.
    pub(super) fn depth_repath(&mut self, i: usize) {
        let e = &mut self.entities[i];
        let Some(goal) = e.order_goal.or(e.move_target) else {
            return;
        };
        let attack_move = e.attack_move;
        e.move_target = None;
        e.path.clear();
        e.attack_move = false;
        self.order_unit_to(i, goal, attack_move);
    }

    /// Every entity's position, taken just before `run_movement` so
    /// [`Sim::run_depth_separation`] can tell which units advanced this tick.
    pub(super) fn depth_positions(&self) -> Vec<Vec2> {
        self.entities.iter().map(|e| e.pos).collect()
    }

    /// Task 12 separation, run every depth tick right after `run_movement`
    /// (`before` holds the positions from just before it). Living units are
    /// bucketed by the combat grid; every same-owner pair `i < j` (ascending
    /// index, positions updated in place) on the same layer (ground with
    /// ground, air with air) closer than [`SEPARATION`] is pushed apart along
    /// its axis by half the overlap each. Coincident units use the hex axis
    /// `j % 6`. A unit that advanced this tick is never pushed: the unit at
    /// rest steps aside by the whole overlap instead, and two advancing units
    /// pass, so separation never alters a marching unit's route and can never
    /// jam a ford, a corridor or a waypoint (a crowd converging on one point
    /// spreads once it stops). A push that would put a ground unit on an
    /// impassable tile (water, a building footprint) or any unit off the map
    /// is skipped for that unit only. An idle unit's anchor moves with its
    /// push, so the leash never walks it back into the crowd.
    pub(super) fn run_depth_separation(&mut self, before: &[Vec2]) {
        let layer: Vec<Option<bool>> = self
            .entities
            .iter()
            .map(|e| {
                (e.alive && e.hp > Fixed::ZERO && matches!(e.kind, Kind::Unit(_)))
                    .then(|| is_air_of(&self.balance, e.kind))
            })
            .collect();
        let moved: Vec<bool> = self
            .entities
            .iter()
            .enumerate()
            .map(|(i, e)| before.get(i).is_some_and(|&p| p != e.pos))
            .collect();
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        let sep_sq = SEPARATION * SEPARATION;
        for i in 0..self.entities.len() {
            let Some(air) = layer[i] else {
                continue;
            };
            grid.gather(self.entities[i].pos, SEPARATION, &mut scratch);
            for &j in &scratch {
                if j <= i
                    || layer[j] != Some(air)
                    || self.entities[j].owner != self.entities[i].owner
                {
                    continue;
                }
                let d = self.entities[j].pos - self.entities[i].pos;
                let dsq = d.length_squared();
                if dsq >= sep_sq {
                    continue;
                }
                let dist = if dsq > Fixed::ZERO {
                    d.length()
                } else {
                    Fixed::ZERO
                };
                let overlap = SEPARATION - dist;
                let axis = if dist > Fixed::ZERO {
                    d.scale(Fixed::ONE / dist)
                } else {
                    let (ax, ay) = HEX_AXES[j % 6];
                    Vec2::new(Fixed::from_ratio(ax, 1000), Fixed::from_ratio(ay, 1000))
                };
                // Half the overlap each between units at rest; a unit that
                // advanced this tick holds its ground and the one at rest steps
                // aside by the whole overlap; two advancing units pass.
                let (pi, pj) = match (moved[i], moved[j]) {
                    (false, false) => {
                        let half = overlap / Fixed::from_int(2);
                        (half, half)
                    }
                    (true, false) => (Fixed::ZERO, overlap),
                    (false, true) => (overlap, Fixed::ZERO),
                    (true, true) => continue,
                };
                if pi > Fixed::ZERO {
                    self.depth_push(i, axis.scale(-pi), air);
                }
                if pj > Fixed::ZERO {
                    self.depth_push(j, axis.scale(pj), air);
                }
            }
        }
    }

    /// Moves unit `k` by `delta` unless that lands a ground unit on an
    /// impassable tile or any unit off the map; an idle unit's anchor follows.
    fn depth_push(&mut self, unit: usize, delta: Vec2, air: bool) {
        let next = self.entities[unit].pos + delta;
        let (width, height) = (self.map.width(), self.map.height());
        let max_x = Fixed::from_int(i32::from(width) - 1) * Fixed::from_ratio(3, 4) + Fixed::ONE;
        let max_y = Fixed::from_int(i32::from(height)) + Fixed::from_ratio(1, 2);
        if next.x < Fixed::ZERO || next.y < Fixed::ZERO || next.x > max_x || next.y > max_y {
            return;
        }
        if !air {
            let (tx, ty) = hex::from_world(next, width, height);
            if !self
                .map
                .tile(i32::from(tx), i32::from(ty))
                .is_some_and(|t| t.passable)
            {
                return;
            }
        }
        let e = &mut self.entities[unit];
        e.pos = next;
        if e.move_target.is_none() {
            if let Some(a) = e.dp.anchor {
                e.dp.anchor = Some(a + delta);
            }
        }
    }

    /// For each attack-mover, the nearest targetable enemy inside its
    /// acquisition ring (`range + ACQUIRE_BONUS`), measured before anyone moves
    /// this tick. `run_movement` steps the unit straight at it when nothing is
    /// in weapon range yet and the step lands on passable ground.
    pub(super) fn depth_steer_points(&self) -> Vec<Option<Vec2>> {
        let grid = DepthGrid::build(self);
        let mut scratch = Vec::new();
        (0..self.entities.len())
            .map(|i| {
                let e = &self.entities[i];
                if !e.attack_move || e.move_target.is_none() || e.ammunition == 0 {
                    return None;
                }
                let profile = self.depth_fighter(i)?;
                let ring = profile.range + ACQUIRE_BONUS;
                // No anchor bound for an order-driven attack-move: the ring is
                // the only limit (`reach` = `ring` keeps the anchor test inert).
                self.depth_nearest_enemy(&grid, &mut scratch, i, profile, ring, (e.pos, ring))
                    .map(|j| self.entities[j].pos)
            })
            .collect()
    }
}

/// One straight step of `speed` from `pos` toward `goal` for an attack-mover
/// closing on an enemy in its acquisition ring, or `None` when a ground unit's
/// step would land on an impassable tile (it then keeps following its path).
pub(super) fn steer_step(
    map: &Map,
    pos: Vec2,
    goal: Vec2,
    speed: Fixed,
    flies: bool,
) -> Option<Vec2> {
    let dir = goal - pos;
    let dist = dir.length();
    if dist <= Fixed::ZERO {
        return None;
    }
    let next = if dist <= speed {
        goal
    } else {
        pos + dir.scale(speed / dist)
    };
    let (x, y) = hex::from_world(next, map.width(), map.height());
    (flies
        || map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.passable))
    .then_some(next)
}

/// What a depth ground unit does with its next movement step.
pub(super) enum GroundStep {
    /// The step lands on passable ground: take it.
    Clear,
    /// The step would land in water or on a footprint: walk toward the centre
    /// of the unit's own tile instead (a segment inside one hex), from where
    /// the straight line to an adjacent waypoint never leaves the two hexes.
    Recentre(Vec2),
    /// Already centred and still blocked: the path no longer starts next to
    /// this tile, so path again from here.
    Repath,
}

/// Task 12 corner guard for a ground unit at `pos` about to take one step of
/// `speed` toward `subgoal`. Units travel between adjacent tile centres, a
/// segment that stays inside those two hexes; a unit pushed off centre by
/// separation could otherwise clip a corner of a river hex beside the ford.
pub(super) fn ground_step(map: &Map, pos: Vec2, subgoal: Vec2, speed: Fixed) -> GroundStep {
    let dir = subgoal - pos;
    let dist = dir.length();
    let next = if dist <= speed {
        subgoal
    } else {
        pos + dir.scale(speed / dist)
    };
    let passable = |p: Vec2| {
        let (x, y) = hex::from_world(p, map.width(), map.height());
        map.tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.passable)
    };
    // A unit already standing somewhere impassable (a structure raised under
    // it) walks out along its path exactly as before.
    if passable(next) || !passable(pos) {
        return GroundStep::Clear;
    }
    let (hx, hy) = hex::from_world(pos, map.width(), map.height());
    let centre = hex::center(hx, hy);
    if centre == pos {
        return GroundStep::Repath;
    }
    let d = centre - pos;
    let len = d.length();
    GroundStep::Recentre(if len <= speed {
        centre
    } else {
        pos + d.scale(speed / len)
    })
}

/// Within this distance of its anchor an idle unit counts as home (a return
/// order always ends exactly on the anchor; the slack only absorbs drift).
const HOME_SLACK: Fixed = Fixed::ONE;

/// Stance hook (Task 13): how far this unit may stray from its anchor
/// (Defensive will use 3).
#[allow(
    clippy::missing_const_for_fn,
    reason = "Task 13 reads the appended stance field here"
)]
fn leash_of(dp: &DepthUnit) -> Fixed {
    let _ = dp;
    LEASH
}

/// Stance hook (Task 13): whether this unit picks fights on sight. Defensive
/// will answer only calls for help; Hold only targets already in range.
#[allow(
    clippy::missing_const_for_fn,
    reason = "Task 13 reads the appended stance field here"
)]
fn may_acquire(dp: &DepthUnit) -> bool {
    let _ = dp;
    true
}

/// Stance hook (Task 13): whether this unit answers a call for help.
#[allow(
    clippy::missing_const_for_fn,
    reason = "Task 13 reads the appended stance field here"
)]
fn may_respond(dp: &DepthUnit) -> bool {
    let _ = dp;
    true
}

/// Stance hook (Task 13): whether this unit may leave its spot to chase (Hold
/// never moves on its own).
#[allow(
    clippy::missing_const_for_fn,
    reason = "Task 13 reads the appended stance field here"
)]
fn may_chase(dp: &DepthUnit) -> bool {
    let _ = dp;
    true
}

/// Living entities bucketed by the combat grid (`COMBAT_CELL` tiles), each
/// cell in ascending index, rebuilt from the current positions on demand.
struct DepthGrid {
    cols: i32,
    rows: i32,
    cells: Vec<Vec<usize>>,
}

impl DepthGrid {
    #[allow(
        clippy::cast_sign_loss,
        reason = "cell counts are positive for any real map"
    )]
    fn build(sim: &Sim) -> Self {
        let cols = (i32::from(sim.map.width()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let rows = (i32::from(sim.map.height()) + COMBAT_CELL - 1) / COMBAT_CELL;
        let mut g = Self {
            cols,
            rows,
            cells: alloc::vec![Vec::new(); (cols * rows).max(1) as usize],
        };
        for (i, e) in sim.entities.iter().enumerate() {
            if e.alive {
                let c = g.cell(e.pos);
                g.cells[c].push(i);
            }
        }
        g
    }

    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "cell coordinates are clamped into the map bounds"
    )]
    fn coords(&self, p: Vec2) -> (i32, i32) {
        let cx = (p.x.to_int_floor() as i32 / COMBAT_CELL).clamp(0, self.cols - 1);
        let cy = (p.y.to_int_floor() as i32 / COMBAT_CELL).clamp(0, self.rows - 1);
        (cx, cy)
    }

    #[allow(clippy::cast_sign_loss, reason = "cell coordinates are clamped")]
    fn cell(&self, p: Vec2) -> usize {
        let (cx, cy) = self.coords(p);
        (cy * self.cols + cx) as usize
    }

    /// Every living entity in the cells that can hold a point within `radius`
    /// of `p`, in ascending index order.
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "radius is a few tiles; cell coordinates are bounds-checked"
    )]
    fn gather(&self, p: Vec2, radius: Fixed, out: &mut Vec<usize>) {
        out.clear();
        let k = radius.to_int_floor() as i32 / COMBAT_CELL + 1;
        let (cx, cy) = self.coords(p);
        for ny in (cy - k).max(0)..=(cy + k).min(self.rows - 1) {
            for nx in (cx - k).max(0)..=(cx + k).min(self.cols - 1) {
                out.extend_from_slice(&self.cells[(ny * self.cols + nx) as usize]);
            }
        }
        out.sort_unstable();
    }
}

#[cfg(test)]
mod tests {
    use super::{is_air_of, Kind, ACQUIRE_BONUS, LEASH};
    use crate::fixed::Fixed;
    use crate::game::hex;
    use crate::game::map::Map;
    use crate::game::scenario::{
        kestrel_reach, kestrel_reach_classic, lane_defense, survival, Scenario,
    };
    use crate::game::sim::{Command, EntityKindView, PlayerId, Sim};
    use crate::game::stats::{BuildingKind, UnitKind};
    use crate::vec::Vec2;
    use alloc::vec::Vec;

    /// `survival(7)` after 3000 host ticks, measured at 503fd7c (before the
    /// depth flag existed). Every later core task re-runs this unchanged.
    const SURVIVAL_PIN: u64 = 1_622_883_436_588_820_810;
    /// Classic Kestrel (`kestrel_reach_classic(3)`, no depth) after 6000 host
    /// ticks, measured at 503fd7c with the bridge's command list.
    const KESTREL_CLASSIC_PIN: u64 = 2_849_524_003_663_712_283;

    #[test]
    fn depth_is_only_enabled_by_kestrel() {
        assert!(kestrel_reach(3).is_depth());
        assert!(!survival(3).is_depth());
        assert!(!lane_defense(3).is_depth());
        assert!(!kestrel_reach_classic(3).is_depth());
    }

    #[test]
    fn survival_and_classic_kestrel_hashes_are_pinned_across_depth() {
        let mut s = survival(7);
        for _ in 0..3000 {
            let c = Scenario::Survival.host_commands(&s);
            s.step(&c);
        }
        assert_eq!(s.state_hash(), SURVIVAL_PIN);
        let mut k = kestrel_reach_classic(3);
        for _ in 0..6000 {
            let c = Scenario::KestrelReach.host_commands(&k);
            k.step(&c);
        }
        assert_eq!(k.state_hash(), KESTREL_CLASSIC_PIN);
    }

    /// Fixed player script exercising every depth command (later tasks append theirs).
    pub(super) fn scripted_player(s: &Sim) -> Vec<Command> {
        let mut out = Vec::new();
        if s.tick() == 600 {
            for v in s.views().into_iter().filter(|v| {
                v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(UnitKind::Infantry))
            }) {
                out.push(Command::AttackMove {
                    owner: PlayerId(0),
                    unit: v.id,
                    target: hex::center(20, 10),
                });
            }
        }
        out
    }

    #[test]
    fn same_inputs_twice_give_the_same_depth_hash_and_replay() {
        let run = || {
            let mut s = kestrel_reach(11);
            let mut log = Vec::new();
            for _ in 0..5000 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                c.extend(scripted_player(&s));
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = kestrel_reach(11);
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// Host commands are a pure function of the world: building them never
    /// mutates the sim and asking twice gives the same list, so a replay that
    /// re-derives them per tick (the bridge, the tests, `verify-run`) and one
    /// that replays a recorded log reach the same hash, including from a save
    /// (a clone) taken mid-match just before the alien AI wakes up.
    #[test]
    fn host_commands_are_pure_and_replay_from_a_mid_match_save() {
        // Fixed step counts, never `while tick < n`: a decided Earthfront match
        // stops advancing its tick (the undefended base falls near t=5000).
        const STEPS: u32 = 6000;
        const SAVE_AT: u32 = 4000;
        let mut s = kestrel_reach(11);
        let mut save = None;
        let mut log = Vec::new();
        for step in 0..STEPS {
            let before = s.state_hash();
            let c = Scenario::KestrelReach.host_commands(&s);
            assert_eq!(s.state_hash(), before, "host_commands mutated the sim");
            assert_eq!(
                alloc::format!("{c:?}"),
                alloc::format!("{:?}", Scenario::KestrelReach.host_commands(&s)),
                "host_commands is not repeatable at tick {}",
                s.tick()
            );
            let mut c = c;
            c.extend(scripted_player(&s));
            if step == SAVE_AT {
                save = Some(s.clone());
            }
            if step >= SAVE_AT {
                log.push(c.clone());
            }
            s.step(&c);
        }
        assert!(
            s.waves_survived() > 0,
            "the horizon must reach the alien AI"
        );
        // Continue the save by re-deriving host commands live.
        let mut live = save.clone().expect("save taken");
        for _ in SAVE_AT..STEPS {
            let mut c = Scenario::KestrelReach.host_commands(&live);
            c.extend(scripted_player(&live));
            live.step(&c);
        }
        // Continue the save from the recorded log only.
        let mut logged = save.expect("save taken");
        for c in &log {
            logged.step(c);
        }
        assert_eq!(live.state_hash(), s.state_hash());
        assert_eq!(logged.state_hash(), s.state_hash());
    }

    /// Depth changes nothing about the starting world: the depth and classic
    /// Kestrel builds show the same entities, yet only the depth one hashes the
    /// depth state (its marker), so a depth replay can never verify against a
    /// classic world.
    #[test]
    fn depth_kestrel_starts_from_the_classic_world_but_hashes_apart() {
        let depth = kestrel_reach(3);
        let classic = kestrel_reach_classic(3);
        assert_eq!(
            alloc::format!("{:?}", depth.views()),
            alloc::format!("{:?}", classic.views())
        );
        assert_ne!(depth.state_hash(), classic.state_hash());
    }

    const P0: PlayerId = PlayerId(0);
    const P1: PlayerId = PlayerId(1);

    fn v(x: i32, y: i32) -> Vec2 {
        Vec2::new(Fixed::from_int(x), Fixed::from_int(y))
    }

    /// An open 40x40 Earthfront arena with the depth rules on.
    fn depth_arena() -> Sim {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        s.enable_depth();
        s
    }

    #[test]
    fn idle_rifle_engages_an_enemy_inside_its_acquisition_ring() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Infantry,
            v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
        );
        let hp0 = s.views().iter().find(|x| x.id == b).unwrap().hp;
        for _ in 0..120 {
            s.step(&[]);
        }
        let hp1 = s
            .views()
            .iter()
            .find(|x| x.id == b)
            .map_or(Fixed::ZERO, |x| x.hp);
        assert!(hp1 < hp0, "the idle unit never engaged");
        let _ = a;
    }

    #[test]
    fn idle_rifle_ignores_an_enemy_outside_the_ring() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.add_unit(
            P1,
            UnitKind::Harvester,
            v(10, 20) + Vec2::new(r + Fixed::from_int(4), Fixed::ZERO),
        );
        for _ in 0..120 {
            s.step(&[]);
        }
        assert_eq!(s.position(a), Some(v(10, 20)));
    }

    #[test]
    fn unit_returns_to_anchor_after_target_flees_past_leash() {
        let mut s = depth_arena();
        let r = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Tank,
            v(10, 20) + Vec2::new(r + Fixed::from_int(2), Fixed::ZERO),
        );
        // Dry, so the tank cannot simply kill the chaser before it flees.
        s.entities[b.0 as usize].ammunition = 0;
        let mut furthest = Fixed::ZERO;
        for _ in 0..30 {
            s.step(&[]);
        }
        s.step(&[Command::Move {
            owner: P1,
            unit: b,
            target: v(38, 20),
        }]);
        for _ in 0..900 {
            s.step(&[]);
            furthest = furthest.max((s.position(a).unwrap() - v(10, 20)).length());
        }
        let home = s.position(a).unwrap();
        assert!(
            (home - v(10, 20)).length_squared() < Fixed::ONE,
            "never came back: {home:?}"
        );
        assert!(furthest > Fixed::ONE, "it never chased at all");
        assert!(
            furthest <= LEASH + Fixed::ONE,
            "chased {furthest:?} from its anchor"
        );
        // Home and idle: no order left.
        assert!(s.entities[a.0 as usize].move_target.is_none());
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
    }

    #[test]
    fn idle_units_defend_a_building_under_attack() {
        let mut s = depth_arena();
        s.add_building(P0, BuildingKind::Barracks, 20, 20);
        let bpos = s.views().iter().find(|x| x.owner == P0).unwrap().pos;
        let r = UnitKind::Infantry.stats().attack.range;
        // attacker hits the barracks from the east; the riflemen stand 5 west of the
        // barracks, beyond their own acquisition ring of the attacker
        s.add_unit(P1, UnitKind::Infantry, bpos + Vec2::new(r, Fixed::ZERO));
        let guards: Vec<_> = (0..3)
            .map(|i| {
                s.add_unit(
                    P0,
                    UnitKind::Infantry,
                    bpos + Vec2::new(Fixed::from_int(-5), Fixed::from_int(i)),
                )
            })
            .collect();
        for _ in 0..300 {
            s.step(&[]);
        }
        assert_eq!(s.unit_count(P1), 0, "guards never answered the attack");
        let _ = guards;
    }

    #[test]
    fn a_player_move_clears_the_anchor() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        s.step(&[]);
        s.step(&[Command::Move {
            owner: P0,
            unit: a,
            target: v(14, 20),
        }]);
        for _ in 0..200 {
            s.step(&[]);
        }
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!(
            (s.position(a).unwrap() - v(14, 20)).length_squared() < Fixed::ONE,
            "snapped back to the old anchor"
        );
    }

    /// A unit carrying a player Move walks past an enemy inside its acquisition
    /// ring along exactly the path it takes with depth off: auto-acquire never
    /// pulls it off the order.
    #[test]
    fn a_unit_with_a_player_move_is_never_acquired_away() {
        let trace = |depth: bool| {
            let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
            s.enable_earthfront();
            if depth {
                s.enable_depth();
            }
            let a = s.add_unit(P0, UnitKind::Infantry, v(4, 20));
            // Beside the route: inside the ring (6), outside weapon range (3).
            // Dry, so it never fires or moves itself.
            let b = s.add_unit(
                P1,
                UnitKind::Infantry,
                v(17, 16) + Vec2::new(Fixed::ZERO, Fixed::from_ratio(1, 2)),
            );
            s.entities[b.0 as usize].ammunition = 0;
            s.step(&[Command::Move {
                owner: P0,
                unit: a,
                target: v(30, 20),
            }]);
            let mut path = Vec::new();
            let mut closest = Fixed::from_int(100);
            for _ in 0..900 {
                s.step(&[]);
                let p = s.position(a).unwrap();
                closest = closest.min((p - s.position(b).unwrap()).length());
                path.push(p);
            }
            (path, closest, s)
        };
        let (classic, _, _) = trace(false);
        let (path, closest, s) = trace(true);
        let r = UnitKind::Infantry.stats().attack.range;
        assert!(
            closest > r && closest <= r + ACQUIRE_BONUS,
            "the route must pass through the ring only: {closest:?}"
        );
        assert_eq!(path, classic, "depth changed a player-ordered route");
        let p = *path.last().unwrap();
        assert!(
            (p - v(30, 20)).length_squared() < Fixed::ONE,
            "ended at {p:?}"
        );
        // Arrived and idle: the destination is the new anchor.
        assert_eq!(s.entities[0].dp.anchor, Some(p));
    }

    /// An engaged unit given an attack-move follows the attack-move: the
    /// engagement and the old anchor are dropped, it fights on the way, and it
    /// settles at the attack-move destination instead of snapping home.
    #[test]
    fn attack_move_wins_over_an_engagement() {
        let mut s = depth_arena();
        let range = UnitKind::Infantry.stats().attack.range;
        let a = s.add_unit(P0, UnitKind::Tank, v(10, 20));
        let b = s.add_unit(
            P1,
            UnitKind::Infantry,
            v(10, 20) + Vec2::new(range + Fixed::from_int(2), Fixed::ZERO),
        );
        s.entities[b.0 as usize].ammunition = 0;
        for _ in 0..5 {
            s.step(&[]);
        }
        assert_eq!(s.entities[a.0 as usize].dp.engaged, Some(b), "precondition");
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: a,
            target: v(10, 34),
        }]);
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
        assert!(s.entities[a.0 as usize].dp.anchor.is_none());
        for _ in 0..900 {
            s.step(&[]);
        }
        let end = s.position(a).unwrap();
        assert!(
            (end - v(10, 34)).length_squared() < Fixed::ONE,
            "ended at {end:?}"
        );
        assert_eq!(s.entities[a.0 as usize].dp.anchor, Some(end));
    }

    /// An attack-mover that sees an enemy inside its acquisition ring but out of
    /// weapon range steps straight at it instead of marching past.
    #[test]
    fn attack_move_steps_toward_an_enemy_in_its_ring() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(4, 20));
        // Dry, so it never fires back or moves itself.
        let b = s.add_unit(P1, UnitKind::Infantry, v(16, 15));
        s.entities[b.0 as usize].ammunition = 0;
        let hp0 = s.views().iter().find(|x| x.id == b).unwrap().hp;
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: a,
            target: v(30, 20),
        }]);
        for _ in 0..900 {
            s.step(&[]);
        }
        let hp1 = s
            .views()
            .iter()
            .find(|x| x.id == b)
            .map_or(Fixed::ZERO, |x| x.hp);
        assert!(hp1 < hp0, "marched past the enemy");
        let p = s.position(a).unwrap();
        assert!(
            (p - v(30, 20)).length_squared() < Fixed::ONE,
            "never finished the attack-move: {p:?}"
        );
    }

    /// A dead engagement whose entity slot is freed (and reused by a fresh unit)
    /// is never chased: `clear_dead` drops the dangling id at once.
    #[test]
    fn a_dead_engagement_is_dropped_before_its_slot_is_reused() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(10, 20));
        let b = s.add_unit(P1, UnitKind::Infantry, v(14, 20));
        for _ in 0..3 {
            s.step(&[]);
        }
        assert_eq!(s.entities[a.0 as usize].dp.engaged, Some(b), "precondition");
        s.entities[b.0 as usize].hp = Fixed::ZERO;
        s.step(&[]);
        assert!(s.entities[a.0 as usize].dp.engaged.is_none());
        // The slot comes back as an ally far away: nothing chases it.
        let c = s.add_unit(P0, UnitKind::Infantry, v(30, 30));
        assert_eq!(c, b, "slot reused");
        for _ in 0..200 {
            s.step(&[]);
        }
        assert!((s.position(a).unwrap() - v(10, 20)).length_squared() < Fixed::ONE);
        assert_eq!(s.position(c), Some(v(30, 30)));
    }

    /// One audit scenario, in a fresh arena: a human Barracks with 4 idle rifles
    /// parked 4 west of it, and 4 alien rifles attack-moving onto it from the
    /// east. Returns (barracks alive, human rifles left, alien rifles left).
    fn barracks_raid(depth: bool) -> (bool, usize, usize) {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        let barracks = s.add_building(P0, BuildingKind::Barracks, 20, 20);
        let bpos = s.position(barracks).unwrap();
        for i in 0..4 {
            s.add_unit(
                P0,
                UnitKind::Infantry,
                bpos + Vec2::new(Fixed::from_int(-4), Fixed::from_ratio(i64::from(i) - 1, 2)),
            );
        }
        let raiders: Vec<_> = (0..4)
            .map(|i| {
                s.add_unit(
                    P1,
                    UnitKind::Infantry,
                    bpos + Vec2::new(Fixed::from_int(12), Fixed::from_ratio(i64::from(i) - 1, 2)),
                )
            })
            .collect();
        let orders: Vec<_> = raiders
            .iter()
            .map(|&unit| Command::AttackMove {
                owner: P1,
                unit,
                target: bpos,
            })
            .collect();
        s.step(&orders);
        for _ in 0..1200 {
            s.step(&[]);
        }
        (
            s.position(barracks).is_some(),
            s.unit_count(P0),
            s.unit_count(P1),
        )
    }

    /// The gameplay audit's measurement (4 rifles parked about 4 from a Barracks
    /// raided by 4 alien rifles: Barracks destroyed, all 4 aliens alive). With
    /// depth off that is still what happens; with depth on the parked rifles
    /// answer the first hit and the Barracks stands.
    #[test]
    fn parked_rifles_now_defend_their_barracks() {
        let before = barracks_raid(false);
        let after = barracks_raid(true);
        std::eprintln!(
            "barracks raid (barracks alive, human rifles, alien rifles): depth off {before:?}, depth on {after:?}"
        );
        assert!(
            !before.0,
            "depth off: the barracks should fall as the audit measured"
        );
        assert_eq!(before.2, 4, "depth off: every raider survives");
        assert!(after.0, "depth on: the barracks fell");
        assert_eq!(after.2, 0, "depth on: raiders left alive");
    }

    /// A busy depth skirmish (two rifle lines, a tank pair, a barracks) run twice
    /// gives the same hash, and replaying the recorded orders reproduces it.
    #[test]
    fn acquisition_and_response_are_deterministic_and_replay() {
        let run = || {
            let mut s = depth_arena();
            s.add_building(P0, BuildingKind::Barracks, 12, 20);
            for i in 0..8 {
                s.add_unit(P0, UnitKind::Infantry, v(8, 14 + i));
                s.add_unit(P1, UnitKind::Infantry, v(26, 14 + i));
            }
            let tanks = [
                s.add_unit(P1, UnitKind::Tank, v(30, 18)),
                s.add_unit(P1, UnitKind::Tank, v(30, 22)),
            ];
            let mut log = Vec::new();
            for t in 0..1500u32 {
                let mut c = Vec::new();
                if t == 100 {
                    for &unit in &tanks {
                        c.push(Command::AttackMove {
                            owner: P1,
                            unit,
                            target: v(10, 20),
                        });
                    }
                }
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = depth_arena();
        r.add_building(P0, BuildingKind::Barracks, 12, 20);
        for i in 0..8 {
            r.add_unit(P0, UnitKind::Infantry, v(8, 14 + i));
            r.add_unit(P1, UnitKind::Infantry, v(26, 14 + i));
        }
        r.add_unit(P1, UnitKind::Tank, v(30, 18));
        r.add_unit(P1, UnitKind::Tank, v(30, 22));
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// Ten rifles dropped on one exact point spread out to at least 0.40 apart.
    #[test]
    fn ten_riflemen_on_one_point_spread_out() {
        let mut s = depth_arena();
        for _ in 0..10 {
            s.add_unit(P0, UnitKind::Infantry, v(20, 20));
        }
        for _ in 0..90 {
            s.step(&[]);
        }
        let pos: Vec<Vec2> = s.views().iter().map(|x| x.pos).collect();
        let min_sq = Fixed::from_ratio(40, 100) * Fixed::from_ratio(40, 100);
        let mut closest = Fixed::from_int(100);
        for i in 0..pos.len() {
            for j in i + 1..pos.len() {
                closest = closest.min((pos[i] - pos[j]).length());
                assert!(
                    (pos[i] - pos[j]).length_squared() >= min_sq,
                    "{i} {j} still stacked"
                );
            }
        }
        let spread = pos
            .iter()
            .map(|&p| (p - v(20, 20)).length())
            .max()
            .unwrap_or(Fixed::ZERO);
        let milli = |f: Fixed| f.to_bits() * 1000 / Fixed::ONE.to_bits();
        std::eprintln!(
            "ten rifles after 90 ticks: closest pair {} milli-tiles, furthest from the drop point {}",
            milli(closest),
            milli(spread)
        );
    }

    /// The spread crowd settles: after the spread every rifle is idle (no walk
    /// home fighting the push), unengaged, within its anchor's home slack, and
    /// the crowd stays put from then on.
    #[test]
    fn a_spread_crowd_settles_at_home_and_stays_put() {
        let mut s = depth_arena();
        let ids: Vec<_> = (0..10)
            .map(|_| s.add_unit(P0, UnitKind::Infantry, v(20, 20)))
            .collect();
        for _ in 0..90 {
            s.step(&[]);
        }
        let settled: Vec<Vec2> = ids.iter().map(|&id| s.position(id).unwrap()).collect();
        let mut orders = 0u32;
        for _ in 0..600 {
            s.step(&[]);
            orders += u32::try_from(
                ids.iter()
                    .filter(|&&id| s.entities[id.0 as usize].move_target.is_some())
                    .count(),
            )
            .unwrap();
        }
        assert_eq!(orders, 0, "a spread unit walked home into the crowd");
        for (k, &id) in ids.iter().enumerate() {
            let e = &s.entities[id.0 as usize];
            assert_eq!(s.position(id), Some(settled[k]), "unit {k} kept drifting");
            let a = e.dp.anchor.expect("anchored");
            assert!(
                (e.pos - a).length_squared() <= Fixed::ONE,
                "unit {k} off its anchor"
            );
            assert!(
                (e.pos - v(20, 20)).length() < Fixed::from_ratio(3, 2),
                "unit {k} wandered off"
            );
        }
    }

    /// Separation is per owner and per layer: an enemy rifle or a friendly
    /// helicopter on the same point is never pushed.
    #[test]
    fn separation_ignores_enemies_and_the_other_layer() {
        let mut s = depth_arena();
        let a = s.add_unit(P0, UnitKind::Infantry, v(20, 20));
        let heli = s.add_unit(P0, UnitKind::Helicopter, v(20, 20));
        let foe = s.add_unit(P1, UnitKind::Infantry, v(20, 20));
        for id in [a, heli, foe] {
            s.entities[id.0 as usize].ammunition = 0;
        }
        for _ in 0..30 {
            s.step(&[]);
        }
        for id in [a, heli, foe] {
            assert_eq!(s.position(id), Some(v(20, 20)));
        }
        // Two friendly helicopters do separate among themselves.
        let h2 = s.add_unit(P0, UnitKind::Helicopter, v(20, 20));
        s.entities[h2.0 as usize].ammunition = 0;
        for _ in 0..30 {
            s.step(&[]);
        }
        let d = (s.position(h2).unwrap() - s.position(heli).unwrap()).length();
        assert!(
            d >= Fixed::from_ratio(40, 100),
            "helicopters still stacked: {d:?}"
        );
        assert_eq!(s.position(a), Some(v(20, 20)));
    }

    /// Eight rifles on one ford hex: the push never puts one in the river.
    #[test]
    fn separation_never_pushes_onto_water() {
        let mut s = kestrel_reach(3);
        let ford = hex::center(22, 10);
        for _ in 0..8 {
            s.add_unit(PlayerId(0), UnitKind::Infantry, ford);
        }
        for _ in 0..90 {
            s.step(&[]);
        }
        for v in s.views() {
            if matches!(v.kind, EntityKindView::Unit(_)) {
                let (x, y) = hex::from_world(v.pos, 44, 26);
                assert!(
                    s.map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable),
                    "unit on impassable tile at {x},{y}"
                );
            }
        }
    }

    /// A crowd dropped between three buildings is never pushed onto a footprint.
    #[test]
    fn separation_never_pushes_onto_a_building() {
        let mut s = depth_arena();
        s.add_building(P0, BuildingKind::Barracks, 20, 19);
        s.add_building(P0, BuildingKind::PowerPlant, 19, 20);
        s.add_building(P0, BuildingKind::Refinery, 21, 20);
        let spot = hex::center(20, 20);
        let ids: Vec<_> = (0..8)
            .map(|_| s.add_unit(P0, UnitKind::Infantry, spot))
            .collect();
        for _ in 0..120 {
            s.step(&[]);
            for &id in &ids {
                let (x, y) = hex::from_world(s.position(id).unwrap(), 40, 40);
                assert!(
                    s.map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable),
                    "unit on a footprint at {x},{y}"
                );
            }
        }
    }

    /// Infantry attack-moving past an enemy helicopter it cannot shoot keeps
    /// going (the halt scan used to stop it under the gunship for good). The
    /// gunship is dry so the measurement is the movement alone.
    #[test]
    fn attack_move_does_not_halt_under_an_untargetable_helicopter() {
        let mut s = depth_arena();
        let inf = s.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let heli = s.add_unit(P1, UnitKind::Helicopter, v(8, 20));
        s.entities[heli.0 as usize].ammunition = 0;
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..600 {
            s.step(&[]);
        }
        let p = s.position(inf).expect("the rifle survives a dry gunship");
        assert!(
            p.x > Fixed::from_int(20),
            "halted under the gunship at {p:?}"
        );
    }

    /// The same march with a ground enemy it can shoot still halts there (the
    /// fix only skips enemies the weapon cannot reach). Depth off, the rifle
    /// halts under the gunship exactly as before.
    #[test]
    fn attack_move_still_halts_for_a_shootable_enemy_and_classic_is_unchanged() {
        let mut s = depth_arena();
        let inf = s.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let foe = s.add_unit(P1, UnitKind::Tank, v(8, 20));
        s.entities[foe.0 as usize].ammunition = 0;
        s.debug_set_hp(foe, Fixed::from_int(1_000_000));
        s.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..300 {
            s.step(&[]);
        }
        assert!(
            s.position(inf).unwrap().x < Fixed::from_int(9),
            "marched past a target"
        );

        let mut c = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        c.enable_earthfront();
        let inf = c.add_unit(P0, UnitKind::Infantry, v(5, 20));
        let heli = c.add_unit(P1, UnitKind::Helicopter, v(8, 20));
        c.entities[heli.0 as usize].ammunition = 0;
        c.step(&[Command::AttackMove {
            owner: P0,
            unit: inf,
            target: v(30, 20),
        }]);
        for _ in 0..600 {
            c.step(&[]);
        }
        let p = c.position(inf).unwrap();
        assert!(
            p.x < Fixed::from_int(12),
            "classic no longer halts under the gunship: {p:?}"
        );
    }

    /// One column of a ford test: (start tile, destination tile).
    type ColumnLeg = ((u16, u16), (u16, u16));

    /// Walks a column of `n` rifles from `from` to `to` on Kestrel (the river
    /// is crossable only at the two-hex Wyllow Ford, (22,10) and (23,10)), with
    /// every unit made unkillable so the measurement is movement only. Returns
    /// (tick the last one arrived, every unit stayed on passable ground every
    /// tick, every unit crossed the ford).
    fn ford_column(
        depth: bool,
        groups: &[ColumnLeg],
        per_column: u16,
        parked: bool,
    ) -> (Option<u32>, bool, bool) {
        let mut s = if depth {
            kestrel_reach(3)
        } else {
            kestrel_reach_classic(3)
        };
        // Optionally three idle rifles parked on each ford hex, in the way.
        let mut idle = Vec::new();
        for tile in [(22, 10), (23, 10)].into_iter().filter(|_| parked) {
            for _ in 0..3 {
                let id = s.add_unit(P0, UnitKind::Infantry, hex::center(tile.0, tile.1));
                s.debug_set_hp(id, Fixed::from_int(1_000_000));
                idle.push(id);
            }
        }
        let mut units = Vec::new();
        let mut orders = Vec::new();
        for &(from, to) in groups {
            for i in 0..per_column {
                let id = s.add_unit(P0, UnitKind::Infantry, hex::center(from.0, from.1));
                s.debug_set_hp(id, Fixed::from_int(1_000_000));
                // A column: each rifle leaves a little after the one before.
                orders.push((u32::from(i) * 6, id, hex::center(to.0, to.1)));
                units.push((id, from.0 < 22));
            }
        }
        let (width, height) = (s.map().width(), s.map().height());
        let mut dry = true;
        let mut crossed = alloc::vec![false; units.len()];
        // First tick each rifle is within 1.5 of its destination (a spread crowd
        // fits; after that the depth rules may send it after an enemy).
        let mut arrived: Vec<Option<u32>> = alloc::vec![None; units.len()];
        for t in 0..1500u32 {
            let cmds: Vec<_> = orders
                .iter()
                .filter(|o| o.0 == t)
                .map(|&(_, unit, target)| Command::Move {
                    owner: P0,
                    unit,
                    target,
                })
                .collect();
            s.step(&cmds);
            for &id in &idle {
                let (x, y) = hex::from_world(s.position(id).expect("unkillable"), width, height);
                let ok = s
                    .map()
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.passable);
                dry &= ok;
            }
            for (k, &(id, west)) in units.iter().enumerate() {
                let p = s.position(id).expect("unkillable");
                let (x, y) = hex::from_world(p, width, height);
                dry &= s
                    .map()
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|t| t.passable);
                crossed[k] |= if west { x >= 24 } else { x <= 21 };
                let near = (p - orders[k].2).length_squared() <= Fixed::from_ratio(9, 4);
                if arrived[k].is_none() && t > orders[k].0 && near {
                    arrived[k] = Some(t);
                }
            }
        }
        let done = arrived.iter().try_fold(0, |m, a| a.map(|a| m.max(a)));
        (done, dry, crossed.iter().all(|&ok| ok))
    }

    /// A ten-rifle column through the two-hex ford, two columns crossing it in
    /// opposite directions at once, and a column through six rifles parked on
    /// the ford: with separation every rifle still crosses, nobody (parked or
    /// marching) ever stands in the river, and the last one arrives within 10
    /// percent of the classic (no separation) time. No corridor deadlock.
    #[test]
    fn columns_cross_the_two_hex_ford_without_wading_or_deadlock() {
        let one = [((17, 10), (28, 10))];
        let two = [((17, 10), (28, 10)), ((28, 11), (17, 11))];
        for (label, groups, parked) in [
            ("one column", &one[..], false),
            ("two columns", &two[..], false),
            ("one column past 6 parked rifles", &one[..], true),
        ] {
            let classic = ford_column(false, groups, 10, parked);
            let depth = ford_column(true, groups, 10, parked);
            std::eprintln!("ford {label}: classic {classic:?}, depth {depth:?} (last arrival tick, dry, all crossed)");
            assert!(depth.1, "{label}: a rifle waded into the river");
            assert!(depth.2, "{label}: a rifle never crossed");
            let (c, d) = (
                classic.0.expect("classic arrives"),
                depth.0.expect("depth deadlocked"),
            );
            assert!(d * 10 <= c * 11, "{label}: depth {d} vs classic {c}");
        }
    }

    /// Unit-ticks a ground unit spends on an impassable tile (river, sea, a
    /// structure) over `steps` ticks of the AI-defended Kestrel match.
    fn wading_unit_ticks(mut s: Sim, steps: u32) -> u32 {
        let (width, height) = (s.map().width(), s.map().height());
        let mut wading = 0;
        for _ in 0..steps {
            let mut cmds = s.ai_commands(P0);
            cmds.extend(Scenario::KestrelReach.host_commands(&s));
            s.step(&cmds);
            for e in s.entities.iter().filter(|e| e.alive) {
                if matches!(e.kind, Kind::Unit(_)) && !is_air_of(&s.balance, e.kind) {
                    let (x, y) = hex::from_world(e.pos, width, height);
                    if !s
                        .map()
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.passable)
                    {
                        wading += 1;
                    }
                }
            }
        }
        wading
    }

    /// Over a whole defended match (both AIs crowding fords, bases and
    /// rally points), separation and the corner guard never leave a ground
    /// unit on an impassable tile more often than the classic rules do (the
    /// classic count is units walking off the producer that spawned them).
    #[test]
    fn a_defended_match_wades_no_more_than_classic() {
        let classic = wading_unit_ticks(kestrel_reach_classic(3), 13_000);
        let depth = wading_unit_ticks(kestrel_reach(3), 13_000);
        std::eprintln!("ground unit-ticks on impassable tiles in 13000 defended ticks: classic {classic}, depth {depth}");
        assert!(depth <= classic, "depth {depth} vs classic {classic}");
    }

    /// Mines one ore hex with four harvesters feeding one refinery for 3000
    /// ticks and returns the ore taken out of the ground.
    fn harvest_run(depth: bool) -> u32 {
        let mut s = Sim::new(Map::new(40, 40), 1, Fixed::ZERO);
        s.enable_earthfront();
        if depth {
            s.enable_depth();
        }
        s.add_building(P0, BuildingKind::PowerPlant, 16, 16);
        s.add_building(P0, BuildingKind::Refinery, 20, 20);
        s.map.set_deposit(
            25,
            20,
            crate::game::map::Deposit {
                kind: crate::game::map::DepositKind::Ore,
                remaining: 30_000,
            },
        );
        for _ in 0..4 {
            s.add_unit(P0, UnitKind::Harvester, hex::center(21, 21));
        }
        for _ in 0..3000 {
            s.step(&[]);
        }
        30_000 - s.map.deposit(25, 20).map_or(0, |d| d.remaining)
    }

    /// Harvesters crowding one refinery and one ore hex still dock and mine:
    /// with separation the four trucks take at least 95 percent of the ore
    /// they take without it.
    #[test]
    fn harvesters_still_dock_and_mine_with_separation() {
        let classic = harvest_run(false);
        let depth = harvest_run(true);
        std::eprintln!("ore mined in 3000 ticks by 4 harvesters: classic {classic}, depth {depth}");
        assert!(classic > 0);
        assert!(
            depth * 100 >= classic * 95,
            "depth {depth} vs classic {classic}"
        );
    }

    /// A crowd that separates every tick is still deterministic: two runs give
    /// the same hash and replaying the recorded orders reproduces it.
    #[test]
    fn separation_is_deterministic_and_replays() {
        let setup = || {
            let mut s = depth_arena();
            let mut ids = Vec::new();
            for i in 0..12 {
                ids.push(s.add_unit(P0, UnitKind::Infantry, v(10, 20)));
                ids.push(s.add_unit(P1, UnitKind::Infantry, v(30, 18 + i % 4)));
            }
            (s, ids)
        };
        let run = || {
            let (mut s, ids) = setup();
            let mut log = Vec::new();
            for t in 0..900u32 {
                let mut c = Vec::new();
                if t == 60 {
                    for &unit in ids.iter().step_by(2) {
                        c.push(Command::AttackMove {
                            owner: P0,
                            unit,
                            target: v(30, 20),
                        });
                    }
                }
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let (mut r, _) = setup();
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// The bridge budget at 80 units on Kestrel: a 30 Hz tick must stay far
    /// under its 33 ms, with separation and acquisition both running.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_tick_budget -- --ignored --nocapture"]
    fn depth_tick_budget() {
        let mut s = kestrel_reach(3);
        for i in 0..40u16 {
            s.add_unit(
                PlayerId(0),
                UnitKind::Infantry,
                hex::center(10, 5 + (i % 15)),
            );
        }
        for i in 0..40u16 {
            s.add_unit(
                PlayerId(1),
                UnitKind::Infantry,
                hex::center(30, 5 + (i % 15)),
            );
        }
        let t = std::time::Instant::now();
        let mut worst = std::time::Duration::ZERO;
        for _ in 0..900 {
            let c = Scenario::KestrelReach.host_commands(&s);
            let t0 = std::time::Instant::now();
            s.step(&c);
            worst = worst.max(t0.elapsed());
        }
        let mean = t.elapsed() / 900;
        std::eprintln!("depth tick mean {mean:?} worst {worst:?}");
        assert!(
            mean < std::time::Duration::from_millis(5)
                && worst < std::time::Duration::from_millis(15)
        );
    }

    /// Headless tick cost with 80+ units on Kestrel, depth vs classic, hosted
    /// as the bridge hosts them: two 40-rifle lines either 6 apart (inside each
    /// other's acquisition ring, so the depth run acquires, chases, answers
    /// hits and walks home) or 15 apart (idle scans only), plus the
    /// scenario's own units.
    #[test]
    #[ignore = "bench: cargo test --release -p rts-core --offline depth_acquire_tick_cost -- --ignored --nocapture"]
    fn depth_acquire_tick_cost() {
        let bench = |mut s: Sim, cols: (u16, u16)| {
            for i in 0..40u16 {
                s.add_unit(P0, UnitKind::Infantry, hex::center(cols.0, 5 + (i % 15)));
            }
            for i in 0..40u16 {
                s.add_unit(P1, UnitKind::Infantry, hex::center(cols.1, 5 + (i % 15)));
            }
            let units = s.unit_count(P0) + s.unit_count(P1);
            let t = std::time::Instant::now();
            let mut worst = std::time::Duration::ZERO;
            for _ in 0..900 {
                let c = Scenario::KestrelReach.host_commands(&s);
                let t0 = std::time::Instant::now();
                s.step(&c);
                worst = worst.max(t0.elapsed());
            }
            let left = s.unit_count(P0) + s.unit_count(P1);
            (units, left, t.elapsed() / 900, worst)
        };
        for (label, cols) in [("lines 6 apart", (12, 20)), ("lines 15 apart", (10, 30))] {
            let (n, left, mean, worst) = bench(kestrel_reach(3), cols);
            let (cn, cleft, cmean, cworst) = bench(kestrel_reach_classic(3), cols);
            std::eprintln!(
                "{label}: depth {n} units ({left} left) mean {mean:?} worst {worst:?}; classic {cn} units ({cleft} left) mean {cmean:?} worst {cworst:?}"
            );
            assert!(n >= 80);
            assert!(mean < std::time::Duration::from_millis(5));
            assert!(worst < std::time::Duration::from_millis(15));
        }
    }
}
