//! Live, dependency-free JSON snapshot bridge for the Godot presentation client.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rts_core::fixed::Fixed;
use rts_core::game::hex;
use rts_core::game::kestrel;
use rts_core::game::map::{Deposit, Ground};
use rts_core::game::scenario::Scenario;
use rts_core::game::sim::{
    order_point_in_range, Command, EntityId, EntityKindView, EntityView, PlayerId, Stance,
    SupplyState,
};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;

#[cfg(test)]
fn snapshot_json(sim: &rts_core::game::sim::Sim) -> String {
    snapshot_json_with(
        sim,
        &supply_links_json(sim),
        &mut ShotWindow::new(),
        &mut FogState::new(true),
    )
}

/// `EARTHFRONT_FOG` kill switch, read once at start: `0`, `off` or `false` (any
/// case, surrounding spaces ignored) turns the presentation fog off; anything
/// else, or unset, leaves it on.
fn fog_enabled_from(value: Option<&std::ffi::OsStr>) -> bool {
    value.and_then(std::ffi::OsStr::to_str).is_none_or(|text| {
        let text = text.trim();
        !(text == "0" || text.eq_ignore_ascii_case("off") || text.eq_ignore_ascii_case("false"))
    })
}

/// The player whose view the snapshot shows.
const HUMAN: PlayerId = PlayerId(0);

/// One world unit as raw 16.16 fixed-point bits: the fog works on raw bits, so
/// every distance test is plain integer arithmetic.
const FIX_ONE: i64 = 1 << Fixed::FRAC_BITS;

/// Sight radius in world units (one unit is about one cell; see `hex::center`).
///
/// Units see `max(weapon reach, 6) + 1`, the Harvester 5 and the gunship 10;
/// structures 7 and the Command Center 9, an armed structure never less than its
/// reach + 1. The reach is the weapon range stretched by the viewer's ground
/// (`range_pct`, Highland +25 percent), rounded up, so whatever a viewer can shoot
/// it can see: nothing it fires on sits in fog.
fn sight_radius(kind: EntityKindView, range_pct: u32) -> i64 {
    let reach = |range: Fixed| {
        let bits = range.to_bits() * (100 + i64::from(range_pct)) / 100;
        (bits + FIX_ONE - 1).div_euclid(FIX_ONE)
    };
    match kind {
        EntityKindView::Unit(UnitKind::Harvester) => 5,
        EntityKindView::Unit(unit) => {
            let sight = reach(unit.stats().attack.range).max(6) + 1;
            if unit == UnitKind::Helicopter {
                sight.max(10)
            } else {
                sight
            }
        }
        EntityKindView::Building(building) => {
            let base = if building == BuildingKind::CommandCenter {
                9
            } else {
                7
            };
            building
                .stats()
                .attack
                .map_or(base, |attack| base.max(reach(attack.range) + 1))
        }
    }
}

/// Row-major index of the cell holding world point `p`.
fn cell_index(p: Vec2, width: u16, height: u16) -> usize {
    let (col, row) = hex::from_world(p, width, height);
    usize::from(row) * usize::from(width) + usize::from(col)
}

/// What the fogged snapshot shows of one living entity.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Shown {
    /// Its current state (every human entity; enemies in sight).
    Live,
    /// The remembered structure that last held this id, as last seen.
    Ghost,
    /// Nothing: an enemy out of sight.
    Hidden,
}

/// `FogState::withheld` cell marks: the placement grids must not reveal what sits there.
const CELL_OPEN: u8 = 0;
/// An unseen, never-remembered enemy structure: report the bare ground.
const CELL_HIDDEN_STRUCTURE: u8 = 1;
/// A remembered structure out of sight: report it as still standing.
const CELL_REMEMBERED: u8 = 2;

/// An enemy structure as the player last saw it.
struct Remembered {
    owner: PlayerId,
    kind: BuildingKind,
    cell: usize,
    /// Its `entities` object as last emitted, closing brace included.
    entity: String,
    /// Its `services` object as last emitted.
    service: String,
}

impl Remembered {
    /// Whether `view` (standing on `cell`) is still this structure, not a new entity
    /// that inherited its recycled id.
    fn is(&self, view: &EntityView, cell: usize) -> bool {
        view.owner == self.owner
            && view.kind == EntityKindView::Building(self.kind)
            && cell == self.cell
    }
}

/// Presentation-only fog of war for Kestrel Reach, owned by the bridge and never
/// read by the sim (which, like the AI and combat, stays omniscient).
///
/// Each snapshot write recomputes the human side's sight (an integer disc per
/// living viewer), folds it into the explored set, and decides per entity what
/// the frame may show: human entities always, enemies only on a visible cell,
/// and enemy structures once seen as remembered ghosts until their cell is seen
/// again. Scratch buffers keep their capacity, so a write allocates nothing new
/// once warm. `reset` (scenario restart) forgets everything explored and remembered.
struct FogState {
    /// False under `EARTHFRONT_FOG=0`: Kestrel gets an all-visible mask and the
    /// writer withholds nothing.
    enabled: bool,
    /// Set by `update`: Kestrel Reach with the fog enabled, so the writer filters.
    active: bool,
    width: u16,
    height: u16,
    /// World centre of every cell as raw (x, y) bits, row-major; built once.
    centers: Vec<(i64, i64)>,
    visible: Vec<bool>,
    /// The previous write's visible set: a shot whose end was in sight a frame
    /// ago (its only viewer killed by that very shot) is still drawn.
    was_visible: Vec<bool>,
    explored: Vec<bool>,
    /// Deposits as last seen, by cell. The first frame is the briefing survey.
    known_deposits: Vec<Option<Deposit>>,
    surveyed: bool,
    /// Enemy structures seen at least once, by entity id.
    remembered: BTreeMap<u32, Remembered>,
    /// Per write: what each view (by index) shows.
    shown: Vec<Shown>,
    /// Per write: view index + 1 by entity id (0 = no living entity holds the id).
    holder: Vec<usize>,
    /// Per write: `CELL_*` mark by cell.
    withheld: Vec<u8>,
    /// Per write: the human viewers as (position, sight).
    viewers: Vec<(Vec2, i64)>,
}

impl FogState {
    const fn new(enabled: bool) -> Self {
        Self {
            enabled,
            active: false,
            width: 0,
            height: 0,
            centers: Vec::new(),
            visible: Vec::new(),
            was_visible: Vec::new(),
            explored: Vec::new(),
            known_deposits: Vec::new(),
            surveyed: false,
            remembered: BTreeMap::new(),
            shown: Vec::new(),
            holder: Vec::new(),
            withheld: Vec::new(),
            viewers: Vec::new(),
        }
    }

    /// Sizes the grid buffers (once per map size; a resize forgets everything).
    fn ensure_grid(&mut self, width: u16, height: u16) {
        let cells = usize::from(width) * usize::from(height);
        if (self.width, self.height) == (width, height) && self.centers.len() == cells {
            return;
        }
        self.width = width;
        self.height = height;
        self.centers = (0..height)
            .flat_map(|row| (0..width).map(move |col| hex::center(col, row)))
            .map(|p| (p.x.to_bits(), p.y.to_bits()))
            .collect();
        self.visible = vec![false; cells];
        self.was_visible = vec![false; cells];
        self.explored = vec![false; cells];
        self.known_deposits = vec![None; cells];
        self.withheld = vec![CELL_OPEN; cells];
        self.surveyed = false;
        self.remembered.clear();
    }

    /// Recomputes the visible set from `viewers` (world position, sight radius in
    /// world units) and folds it into the explored set. A cell is visible when its
    /// centre lies within a viewer's radius (edge inclusive); integer maths only.
    fn observe(&mut self, width: u16, height: u16, viewers: &[(Vec2, i64)]) {
        self.ensure_grid(width, height);
        std::mem::swap(&mut self.visible, &mut self.was_visible);
        self.visible.fill(false);
        let (w, h) = (usize::from(width), usize::from(height));
        let half = FIX_ONE / 2;
        // Bits to a clamped grid index (negative clamps to 0).
        let clamp = |value: i64, len: usize| {
            usize::try_from(value).map_or(0, |v| v.min(len.saturating_sub(1)))
        };
        for &(pos, sight) in viewers {
            let (px, py) = (pos.x.to_bits(), pos.y.to_bits());
            let radius = sight * FIX_ONE;
            let radius_sq = radius * radius;
            // Column centres sit at 3/4 col + 1/2; row centres at row + 1/2, plus
            // 1/2 on odd columns. These bounds over-cover; the disc test decides.
            let col0 = clamp(((px - radius - half) * 4).div_euclid(3 * FIX_ONE), w);
            let col1 = clamp(((px + radius - half) * 4).div_euclid(3 * FIX_ONE) + 1, w);
            let row0 = clamp((py - radius - FIX_ONE).div_euclid(FIX_ONE), h);
            let row1 = clamp((py + radius).div_euclid(FIX_ONE), h);
            for row in row0..=row1 {
                for col in col0..=col1 {
                    let index = row * w + col;
                    let (cx, cy) = self.centers[index];
                    let (dx, dy) = (cx - px, cy - py);
                    if dx * dx + dy * dy <= radius_sq {
                        self.visible[index] = true;
                    }
                }
            }
        }
        for (explored, &visible) in self.explored.iter_mut().zip(&self.visible) {
            *explored |= visible;
        }
    }

    /// Recomputes sight and every per-entity decision for one snapshot write.
    /// Survival, or the fog switched off, leaves the writer unfiltered.
    fn update(&mut self, sim: &rts_core::game::sim::Sim, views: &[EntityView]) {
        self.active = self.enabled && is_kestrel_map(sim);
        self.shown.clear();
        if !self.active {
            return;
        }
        let map = sim.map();
        let (width, height) = (map.width(), map.height());
        let mut viewers = std::mem::take(&mut self.viewers);
        viewers.clear();
        // Living human entities see (a building under construction included: the
        // player's own site). A viewer at zero HP is dying this tick and sees nothing.
        viewers.extend(
            views
                .iter()
                .filter(|v| v.owner == HUMAN && v.hp > Fixed::ZERO)
                .map(|v| {
                    let pct = if sim.is_earthfront() {
                        let (x, y) = hex::from_world(v.pos, width, height);
                        map.ground_at(i32::from(x), i32::from(y)).props().range_pct
                    } else {
                        0
                    };
                    (v.pos, sight_radius(v.kind, pct))
                }),
        );
        self.observe(width, height, &viewers);
        self.viewers = viewers;
        self.survey(map);
        self.classify(views);
    }

    /// Refreshes deposit knowledge: every deposit on the first frame (the
    /// briefing survey), afterwards only those on visible cells.
    fn survey(&mut self, map: &rts_core::game::map::Map) {
        let all = !self.surveyed;
        self.surveyed = true;
        let width = usize::from(self.width);
        for (index, known) in self.known_deposits.iter_mut().enumerate() {
            if all || self.visible[index] {
                let x = u16::try_from(index % width).unwrap_or(u16::MAX);
                let y = u16::try_from(index / width).unwrap_or(u16::MAX);
                *known = map.deposit(x, y);
            }
        }
    }

    /// Decides what each view shows, prunes the structure memory, and marks the
    /// cells whose placement truth must be withheld.
    fn classify(&mut self, views: &[EntityView]) {
        let (width, height) = (self.width, self.height);
        self.holder.clear();
        let ids = views.iter().map(|v| v.id.0 as usize + 1).max().unwrap_or(0);
        self.holder.resize(ids, 0);
        for (index, view) in views.iter().enumerate() {
            self.holder[view.id.0 as usize] = index + 1;
        }
        let visible = &self.visible;
        self.shown.extend(views.iter().map(|v| {
            if v.owner == HUMAN || visible[cell_index(v.pos, width, height)] {
                Shown::Live
            } else {
                Shown::Hidden
            }
        }));
        // A memory survives while its cell is out of sight, unless a shown entity
        // now holds its id (ids must stay unique in a frame). Back in sight, it
        // survives only if the structure still stands (and is then shown live).
        let (holder, shown) = (&self.holder, &self.shown);
        self.remembered.retain(|&id, memory| {
            let held = holder
                .get(id as usize)
                .and_then(|&slot| slot.checked_sub(1))
                .map(|index| (index, &views[index]));
            let same = held.is_some_and(|(_, v)| memory.is(v, cell_index(v.pos, width, height)));
            if visible[memory.cell] {
                same
            } else {
                held.is_none_or(|(index, _)| shown[index] != Shown::Live || same)
            }
        });
        self.withheld.fill(CELL_OPEN);
        for (view, &shown) in views.iter().zip(&self.shown) {
            if shown == Shown::Hidden && matches!(view.kind, EntityKindView::Building(_)) {
                self.withheld[cell_index(view.pos, width, height)] = CELL_HIDDEN_STRUCTURE;
            }
        }
        for memory in self.remembered.values() {
            if !visible[memory.cell] {
                self.withheld[memory.cell] = CELL_REMEMBERED;
            }
        }
        for (view, shown) in views.iter().zip(self.shown.iter_mut()) {
            if *shown == Shown::Hidden && self.remembered.contains_key(&view.id.0) {
                *shown = Shown::Ghost;
            }
        }
    }

    /// Whether a player command may reach the sim (P2 review M1): an
    /// `AttackTarget` only on an entity this write showed live, which is what
    /// the client could click, so a hand-written line can neither learn
    /// whether a hidden enemy id is alive nor send a unit after one. Every
    /// other command, and everything while the fog is inactive, passes. The
    /// loop calls this before the next step, so the ids still name the
    /// entities this write showed.
    fn admits(&self, command: &Command) -> bool {
        let Command::AttackTarget { target, .. } = *command else {
            return true;
        };
        !self.active
            || self
                .holder
                .get(target.0 as usize)
                .and_then(|&slot| slot.checked_sub(1))
                .is_some_and(|index| self.shown(index) == Shown::Live)
    }

    /// What view `index` of this write shows (everything, when the fog is inactive).
    fn shown(&self, index: usize) -> Shown {
        self.shown.get(index).copied().unwrap_or(Shown::Live)
    }

    /// The `CELL_*` mark of `(x, y)` for this write.
    fn withheld(&self, x: u16, y: u16) -> u8 {
        if !self.active || x >= self.width || y >= self.height {
            return CELL_OPEN;
        }
        self.withheld[usize::from(y) * usize::from(self.width) + usize::from(x)]
    }

    /// Stores what the player just saw of a live enemy structure.
    fn remember_entity(&mut self, view: &EntityView, json: &str) {
        let EntityKindView::Building(kind) = view.kind else {
            return;
        };
        if !self.active || view.owner == HUMAN {
            return;
        }
        let cell = cell_index(view.pos, self.width, self.height);
        let memory = self
            .remembered
            .entry(view.id.0)
            .or_insert_with(|| Remembered {
                owner: view.owner,
                kind,
                cell,
                entity: String::new(),
                service: String::new(),
            });
        memory.owner = view.owner;
        memory.kind = kind;
        memory.cell = cell;
        memory.entity.clear();
        memory.entity.push_str(json);
    }

    /// Stores the services entry of a live enemy structure just remembered.
    fn remember_service(&mut self, view: &EntityView, json: &str) {
        if !self.active || view.owner == HUMAN {
            return;
        }
        if let Some(memory) = self.remembered.get_mut(&view.id.0) {
            memory.service.clear();
            memory.service.push_str(json);
        }
    }

    /// Writes the remembered entity object for `id`, flagged `"remembered":true`.
    fn write_ghost_entity(&self, id: u32, out: &mut String) {
        if let Some(open) = self
            .remembered
            .get(&id)
            .and_then(|memory| memory.entity.strip_suffix('}'))
        {
            out.push_str(open);
            out.push_str(",\"remembered\":true}");
        }
    }

    /// Writes the remembered services entry for `id`.
    fn write_ghost_service(&self, id: u32, out: &mut String) {
        if let Some(memory) = self.remembered.get(&id) {
            out.push_str(&memory.service);
        }
    }

    /// Remembered structures no living entity holds the id of (destroyed out of
    /// sight), in id order: written after the live entities.
    fn dead_ghosts(&self) -> impl Iterator<Item = u32> + '_ {
        self.remembered
            .keys()
            .copied()
            .filter(|&id| self.holder.get(id as usize).copied().unwrap_or(0) == 0)
    }

    /// Whether a shot from `attacker` to `target` may be drawn: either end on a
    /// cell in sight now or on the previous write.
    fn sees_shot(&self, attacker: Vec2, target: Vec2) -> bool {
        !self.active
            || [attacker, target].into_iter().any(|p| {
                let cell = cell_index(p, self.width, self.height);
                self.visible[cell] || self.was_visible[cell]
            })
    }

    /// Writes the `fog` mask: one digit per cell, row-major (0 unseen, 1 explored,
    /// 2 visible); all `2` when the fog is switched off.
    fn write_mask(&self, out: &mut String, cells: usize) {
        if self.enabled && self.visible.len() == cells {
            out.extend(
                self.visible
                    .iter()
                    .zip(&self.explored)
                    .map(|(&seen, &explored)| {
                        if seen {
                            '2'
                        } else if explored {
                            '1'
                        } else {
                            '0'
                        }
                    }),
            );
        } else {
            out.extend(std::iter::repeat_n('2', cells));
        }
    }

    /// Deposits as the player knows them, `(x, y, deposit)` in row-major order.
    fn known_deposits(&self) -> impl Iterator<Item = (u16, u16, Deposit)> + '_ {
        let width = usize::from(self.width);
        self.known_deposits
            .iter()
            .enumerate()
            .filter_map(move |(index, known)| {
                let deposit = (*known)?;
                let x = u16::try_from(index % width).ok()?;
                let y = u16::try_from(index / width).ok()?;
                Some((x, y, deposit))
            })
    }

    #[cfg(test)]
    fn mask_string(&self) -> String {
        let mut out = String::new();
        self.write_mask(&mut out, self.visible.len());
        out
    }

    /// Capacities of every buffer the fog reuses (a growth check for tests).
    #[cfg(test)]
    fn buffer_capacities(&self) -> [usize; 10] {
        [
            self.centers.capacity(),
            self.visible.capacity(),
            self.was_visible.capacity(),
            self.explored.capacity(),
            self.known_deposits.capacity(),
            self.shown.capacity(),
            self.holder.capacity(),
            self.withheld.capacity(),
            self.viewers.capacity(),
            self.remembered
                .values()
                .map(|m| m.entity.capacity() + m.service.capacity())
                .sum(),
        ]
    }
}

/// Whether a completed human Command Center, Supply Depot or Refinery stands within
/// 10 world units of cell `(x, y)`: the sim's Earthfront construction reach
/// (`earthfront_build_reachable`), recomputed here because the sim keeps it private.
fn human_build_reach(views: &[EntityView], x: u16, y: u16) -> bool {
    let target = hex::center(x, y);
    views.iter().any(|v| {
        v.owner == HUMAN
            && v.construction_remaining == 0
            && matches!(
                v.kind,
                EntityKindView::Building(
                    BuildingKind::CommandCenter
                        | BuildingKind::SupplyDepot
                        | BuildingKind::Refinery
                )
            )
            && (v.pos - target).length_squared() <= Fixed::from_int(100)
    })
}

/// How many ticks of shots the snapshot carries (0.6 s at 30 Hz). The sim steps at
/// 30 Hz but the Godot client polls about every 0.12 s, so the latest tick alone would
/// miss most shots; the client dedups the overlapping windows by (tick, attacker, target).
const SHOT_WINDOW_TICKS: u64 = 18;

/// One shot: the tick it was fired on, the attacker and target positions, and
/// whether the fog has let it be drawn (latched on the first write that sees an end).
type Shot = (u64, Vec2, Vec2, bool);

/// Rolling window of the most recent shots, oldest first. Cosmetic only: it is never
/// part of the sim state and never read back by it.
struct ShotWindow {
    shots: Vec<Shot>,
    /// The tick last recorded. A finished sim stops advancing its tick but keeps
    /// reporting its final attacks, so a repeat must not be added again.
    last_tick: Option<u64>,
}

impl ShotWindow {
    const fn new() -> Self {
        Self {
            shots: Vec::new(),
            last_tick: None,
        }
    }

    /// Adds the shots the sim fired on `tick` (its tick counter right after the step),
    /// then drops everything `SHOT_WINDOW_TICKS` or more ticks old. Does nothing once
    /// the sim is `finished` or when `tick` was already recorded: the window freezes
    /// on the victory or defeat screen instead of growing every frame.
    fn record(&mut self, tick: u64, attacks: &[(Vec2, Vec2)], finished: bool) {
        if finished || self.last_tick == Some(tick) {
            return;
        }
        self.last_tick = Some(tick);
        self.shots.extend(
            attacks
                .iter()
                .map(|&(attacker, target)| (tick, attacker, target, false)),
        );
        self.shots
            .retain(|&(fired, _, _, _)| tick.saturating_sub(fired) < SHOT_WINDOW_TICKS);
    }

    /// Latches every shot the fog lets the player see (an end in sight now or a
    /// frame ago); a latched shot stays drawn for the rest of its window.
    fn reveal(&mut self, fog: &FogState) {
        for shot in &mut self.shots {
            shot.3 = shot.3 || fog.sees_shot(shot.1, shot.2);
        }
    }

    /// Forgets every shot (scenario restart).
    fn clear(&mut self) {
        self.shots.clear();
        self.last_tick = None;
    }

    #[cfg(test)]
    const fn len(&self) -> usize {
        self.shots.len()
    }

    #[cfg(test)]
    const fn is_empty(&self) -> bool {
        self.shots.is_empty()
    }

    /// `[[tick,ax_bits,az_bits,tx_bits,tz_bits],...]`, oldest first; with
    /// `revealed_only`, just the shots the fog has let through.
    fn json_array(&self, revealed_only: bool) -> String {
        let mut out = String::from("[");
        let shots = self.shots.iter().filter(|shot| !revealed_only || shot.3);
        for (i, (tick, attacker, target, _)) in shots.enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(
                out,
                "[{tick},{},{},{},{}]",
                attacker.x.to_bits(),
                attacker.y.to_bits(),
                target.x.to_bits(),
                target.y.to_bits()
            )
            .expect("string write");
        }
        out.push(']');
        out
    }
}

/// The human's depot-to-building supply links as a JSON array (see `SupplyLinkCache`).
fn supply_links_json(sim: &rts_core::game::sim::Sim) -> String {
    let mut out = String::from("[");
    for (i, link) in sim
        .earthfront_supply_links(PlayerId(0))
        .into_iter()
        .enumerate()
    {
        if i > 0 {
            out.push(',');
        }
        let state = match link.state {
            SupplyState::Supplied => "ok",
            SupplyState::Severed => "severed",
        };
        write!(
            out,
            "{{\"depot\":{},\"target\":{},\"state\":\"{state}\"}}",
            link.depot.0, link.target.0
        )
        .expect("string write");
    }
    out.push(']');
    out
}

/// Throttle for `supply_links_json`: each link costs path searches, so the live loop
/// recomputes only on the supply beat (the sim feeds ammunition every 30 ticks) and
/// serves the cached array in between. The loop writes one snapshot per tick, so the
/// array shown at tick T is always the sim's links at the last multiple of 30 at or
/// below T (or at the first snapshot after a start or restart): deterministic per tick.
struct SupplyLinkCache {
    tick: Option<u64>,
    json: String,
}

impl SupplyLinkCache {
    const BEAT: u64 = 30;

    const fn new() -> Self {
        Self {
            tick: None,
            json: String::new(),
        }
    }

    fn get(&mut self, sim: &rts_core::game::sim::Sim) -> &str {
        let now = sim.tick();
        let stale = self
            .tick
            .is_none_or(|t| now < t || now / Self::BEAT != t / Self::BEAT);
        if stale {
            self.json = supply_links_json(sim);
            self.tick = Some(now);
        }
        &self.json
    }
}

#[allow(
    clippy::too_many_lines,
    reason = "one explicit JSON frame keeps the dependency-free bridge schema easy to audit"
)]
fn snapshot_json_with(
    sim: &rts_core::game::sim::Sim,
    supply_links: &str,
    shots: &mut ShotWindow,
    fog: &mut FogState,
) -> String {
    let views = sim.views();
    fog.update(sim, &views);
    let mut out = String::with_capacity(512 + views.len() * 240);
    let human = PlayerId(0);
    let winner = sim.winner().map_or(-1, |PlayerId(id)| i32::from(id));
    let (researched, active) = sim.research_state(human);
    let active_id = active.map_or(-1_i64, |(id, _)| i64::from(id));
    let active_ticks = active.map_or(0, |(_, ticks)| ticks);
    let active_name = active
        .and_then(|(id, _)| sim.technology(id))
        .map_or_else(String::new, |node| node.name.to_owned());
    let suggested_id = sim.suggested_research(human);
    let suggested_name = suggested_id
        .and_then(|id| sim.technology(id))
        .map_or_else(String::new, |node| node.name.to_owned());
    let waves_survived = sim.waves_survived();
    let next_wave_ticks = sim
        .ticks_until_next_wave()
        .map_or(-1_i64, |ticks| i64::try_from(ticks).unwrap_or(i64::MAX));
    write!(
        out,
        "{{\"schema\":5,\"tick\":{},\"hash\":{},\"winner\":{},\"money_bits\":{},\"energy_bits\":{},\"labour_bits\":{},\"supply_used\":{},\"supply_cap\":{},\"era\":{},\"research_count\":{},\"active_research_id\":{},\"active_research_ticks\":{},\"active_research_name\":{:?},\"suggested_research_id\":{},\"suggested_research_name\":{:?},\"waves_survived\":{},\"next_wave_ticks\":{},\"map_width\":{},\"map_height\":{},\"surveying\":{},\"unlocked_buildings\":[",
        sim.tick(),
        sim.state_hash(),
        winner,
        sim.money(human).to_bits(),
        sim.energy(human).to_bits(),
        sim.labour(human).to_bits(),
        sim.supply_used(human),
        sim.supply_cap(human),
        sim.player_era(human),
        researched.count(),
        active_id,
        active_ticks,
        active_name,
        suggested_id.map_or(-1_i64, i64::from),
        suggested_name,
        waves_survived,
        next_wave_ticks,
        sim.map().width(),
        sim.map().height(),
        sim.surveying(),
    )
    .expect("writing to String cannot fail");

    let building_roster = [
        BuildingKind::PowerPlant,
        BuildingKind::Refinery,
        BuildingKind::Barracks,
        BuildingKind::GunTurret,
        BuildingKind::AaTurret,
        BuildingKind::Wall,
        BuildingKind::ResearchLab,
        BuildingKind::AntimatterPlant,
        BuildingKind::VehicleFactory,
        BuildingKind::Airfield,
        BuildingKind::SupplyDepot,
        BuildingKind::Battery,
    ];
    for (index, kind) in building_roster
        .into_iter()
        .filter(|kind| sim.building_unlocked(human, *kind))
        .enumerate()
    {
        if index != 0 {
            out.push(',');
        }
        write!(out, "{:?}", format!("{kind:?}")).expect("writing to String cannot fail");
    }
    out.push_str("],\"unlocked_units\":[");
    let unit_roster = [
        UnitKind::Infantry,
        UnitKind::AntiArmor,
        UnitKind::Tank,
        UnitKind::Helicopter,
        UnitKind::Capital,
        UnitKind::Harvester,
    ];
    for (index, kind) in unit_roster
        .into_iter()
        .filter(|kind| sim.unit_unlocked(human, *kind))
        .enumerate()
    {
        if index != 0 {
            out.push(',');
        }
        write!(out, "{:?}", format!("{kind:?}")).expect("writing to String cannot fail");
    }
    out.push_str("],\"blocked\":[");

    let mut blocked_index = 0_usize;
    for y in 0..sim.map().height() {
        for x in 0..sim.map().width() {
            // Fog: an unseen enemy structure must not show as a blocked cell (its
            // bare ground is reported); a remembered one stays blocked as last seen.
            let blocked = match fog.withheld(x, y) {
                CELL_HIDDEN_STRUCTURE => {
                    !sim.map()
                        .ground_at(i32::from(x), i32::from(y))
                        .props()
                        .buildable
                }
                CELL_REMEMBERED => true,
                _ => sim
                    .map()
                    .tile(i32::from(x), i32::from(y))
                    .is_some_and(|tile| !tile.buildable),
            };
            if blocked {
                if blocked_index != 0 {
                    out.push(',');
                }
                write!(out, "[{x},{y}]").expect("writing to String cannot fail");
                blocked_index += 1;
            }
        }
    }
    out.push_str("],\"deposits\":[");
    // Fog: deposits out of sight read as last seen, so enemy mining stays unseen.
    let deposits: Box<dyn Iterator<Item = (u16, u16, Deposit)>> = if fog.active {
        Box::new(fog.known_deposits())
    } else {
        Box::new(sim.map().deposits())
    };
    for (index, (x, y, deposit)) in deposits.enumerate() {
        if index != 0 {
            out.push(',');
        }
        write!(
            out,
            "{{\"x\":{x},\"y\":{y},\"kind\":{:?},\"remaining\":{}}}",
            format!("{:?}", deposit.kind),
            deposit.remaining,
        )
        .expect("writing to String cannot fail");
    }
    out.push_str("],\"research_options\":[");
    let available = sim.available_research(human);
    let visible: Vec<u32> = if sim.is_earthfront() {
        (0..u32::try_from(sim.technology_count()).unwrap_or(0)).collect()
    } else {
        available.clone()
    };
    for (index, id) in visible.into_iter().enumerate() {
        if index != 0 {
            out.push(',');
        }
        let node = sim
            .technology(id)
            .expect("available research id is a grid node");
        let unlocks = node
            .unlocks
            .iter()
            .map(|unlock| format!("{:?}: {}", unlock.family, unlock.name))
            .collect::<Vec<_>>()
            .join("  •  ");
        write!(
            out,
            "{{\"id\":{},\"name\":{:?},\"era\":{},\"branch\":{},\"step\":{},\"reality\":\"{:?}\",\"money\":{},\"energy\":{},\"labour\":{},\"duration\":{},\"unlocks\":{:?},\"recommended\":{},\"available\":{},\"researched\":{},\"prerequisites\":{:?}}}",
            node.id,
            node.name,
            node.era,
            node.branch,
            node.step,
            node.reality,
            node.money,
            node.energy,
            node.labour,
            node.duration,
            unlocks,
            suggested_id == Some(node.id),
            available.contains(&id),
            researched.get(id),
            node.prereqs.iter().filter_map(|&required| sim.technology(required)).map(|n| n.name).collect::<Vec<_>>().join(" + "),
        )
        .expect("writing to String cannot fail");
    }
    out.push_str("],\"entities\":[");

    // Fog: enemies out of sight are left out and remembered structures are written
    // as last seen (flagged `remembered`); with the fog inactive every entity is live.
    let mut first_entity = true;
    for (index, entity) in views.iter().enumerate() {
        let shown = fog.shown(index);
        if shown == Shown::Hidden {
            continue;
        }
        if !first_entity {
            out.push(',');
        }
        first_entity = false;
        if shown == Shown::Ghost {
            fog.write_ghost_entity(entity.id.0, &mut out);
            continue;
        }
        let start = out.len();
        let (category, kind) = match entity.kind {
            EntityKindView::Building(kind) => ("building", format!("{kind:?}")),
            EntityKindView::Unit(kind) => ("unit", format!("{kind:?}")),
        };
        let production = sim.production_status(entity.id);
        let production_name =
            production.map_or_else(String::new, |status| format!("{:?}", status.unit));
        write!(
            out,
            "{{\"id\":{},\"owner\":{},\"category\":\"{}\",\"kind\":\"{}\",\"x_bits\":{},\"z_bits\":{},\"hp_bits\":{},\"max_hp_bits\":{},\"shield_bits\":{},\"max_shield_bits\":{},\"ability_cd\":{},\"stun_ticks\":{},\"cargo\":{},\"rally_x_bits\":{},\"rally_z_bits\":{},\"construction\":{},\"construction_total\":{},\"production_name\":{:?},\"production_queued\":{},\"production_progress\":{},\"production_duration\":{}",
            entity.id.0,
            entity.owner.0,
            category,
            kind,
            entity.pos.x.to_bits(),
            entity.pos.y.to_bits(),
            entity.hp.to_bits(),
            entity.max_hp.to_bits(),
            entity.shield.to_bits(),
            entity.max_shield.to_bits(),
            entity.ability_cd,
            entity.stun_ticks,
            entity.cargo,
            entity.rally.map_or(-1, |point| point.x.to_bits()),
            entity.rally.map_or(-1, |point| point.y.to_bits()),
            entity.construction_remaining,
            entity.construction_total,
            production_name,
            production.map_or(0, |status| status.queued),
            production.map_or(0, |status| status.progress),
            production.map_or(0, |status| status.duration),
        )
        .expect("writing to String cannot fail");
        // Additive per-entity fields, appended last so existing consumers are untouched.
        write!(
            out,
            ",\"idle\":{}",
            entity.owner == human && sim.is_idle_unit(entity.id)
        )
        .expect("writing to String cannot fail");
        match entity.kind {
            EntityKindView::Unit(_) => {
                write!(out, ",\"rank\":{}", sim.rank_of(entity.id))
                    .expect("writing to String cannot fail");
                // Only the player's own units, and only on a depth map: the
                // alien side's stances never reach the client, and Survival
                // snapshots stay byte-identical.
                match sim.stance_of(entity.id) {
                    Some(stance) if entity.owner == human => {
                        write!(out, ",\"stance\":\"{}\"", stance.name())
                            .and_then(|()| write_queue(sim, entity.id, &mut out))
                    }
                    _ => Ok(()),
                }
            }
            EntityKindView::Building(BuildingKind::PowerPlant) => {
                write!(out, ",\"river_kw\":{}", sim.river_bonus_kw_of(entity.id))
            }
            EntityKindView::Building(BuildingKind::Refinery) => {
                write!(
                    out,
                    ",\"ore_bonus\":{}",
                    sim.ore_bonus_pct_of(entity.id) > 0
                )
            }
            EntityKindView::Building(_) => Ok(()),
        }
        .expect("writing to String cannot fail");
        // Kestrel depth (Task 18): the player's own buildings carry the ticks
        // until they may be repaired again. Never on Survival or the aliens.
        if let Some(cd) = sim
            .repair_cooldown(entity.id)
            .filter(|_| entity.owner == human)
        {
            write!(out, ",\"repair_cd\":{cd}").expect("writing to String cannot fail");
        }
        out.push('}');
        fog.remember_entity(entity, &out[start..]);
    }
    for id in fog.dead_ghosts() {
        if !first_entity {
            out.push(',');
        }
        first_entity = false;
        fog.write_ghost_entity(id, &mut out);
    }
    let economy = sim.economy_view(human);
    write!(out, "],\"earthfront\":{},\"technology_total\":{},\"power_generation\":{},\"power_demand\":{},\"stored_energy\":{},\"storage_capacity\":{},\"ore_buffer\":{},\"depot_ammunition\":{},\"active_factories\":{},\"research_status\":{:?},\"incoming_doctrine\":{:?},\"services\":[",
        sim.is_earthfront(), sim.technology_count(), economy.generation, economy.demand,
        economy.stored_energy, economy.storage_capacity, economy.ore, economy.ammunition,
        economy.active_factories, economy.research_status, sim.incoming_doctrine()).expect("string write");
    let mut first_service = true;
    for (index, entity) in views.iter().enumerate() {
        let shown = fog.shown(index);
        if shown == Shown::Hidden {
            continue;
        }
        if !first_service {
            out.push(',');
        }
        first_service = false;
        if shown == Shown::Ghost {
            fog.write_ghost_service(entity.id.0, &mut out);
            continue;
        }
        let start = out.len();
        let (power, ammo, stock, ore) = sim.earthfront_entity_status(entity.id);
        write!(
            out,
            "{{\"id\":{},\"power\":{},\"ammo\":{},\"stock\":{},\"ore\":{},\"ore_capacity\":{},\"prototype\":{},\"alien_relay\":{}}}",
            entity.id.0, power, ammo, stock, ore, sim.refinery_capacity(),
            sim.prototype_factory(entity.owner) == Some(entity.id), sim.is_alien_relay(entity.id)
        )
        .expect("string write");
        fog.remember_service(entity, &out[start..]);
    }
    for id in fog.dead_ghosts() {
        if !first_service {
            out.push(',');
        }
        first_service = false;
        fog.write_ghost_service(id, &mut out);
    }
    write!(out, "],\"alien_relays\":{},\"active_alien_relays\":{},\"next_expedition_size\":{},\"construction_zone\":[",
        sim.alien_relay_count(PlayerId(1), false), sim.alien_relay_count(PlayerId(1), true), sim.next_expedition_size()).expect("string write");
    let mut first_tile = true;
    for y in 0..sim.map().height() {
        for x in 0..sim.map().width() {
            // Fog: a hidden enemy structure's cell reads as its bare ground in reach
            // of a human depot; a remembered one stays unbuildable as last seen.
            let allowed = match fog.withheld(x, y) {
                CELL_HIDDEN_STRUCTURE => {
                    sim.map()
                        .ground_at(i32::from(x), i32::from(y))
                        .props()
                        .buildable
                        && human_build_reach(&views, x, y)
                }
                CELL_REMEMBERED => false,
                _ => sim.construction_allowed_at(human, x, y),
            };
            if allowed {
                if !first_tile {
                    out.push(',');
                }
                first_tile = false;
                write!(out, "[{x},{y}]").expect("string write");
            }
        }
    }
    out.push(']');
    write_additive_fields(&mut out, sim);
    // Kestrel depth (Task 17): the human's Upgrades levels and the price of
    // each next level (null at the era cap); Task 18 appends the price of the
    // human's next Refinery. Never on Survival.
    if sim.is_depth() {
        let levels = sim.upgrade_levels(human);
        write!(
            out,
            ",\"depth\":{{\"upgrades\":[{},{},{}],\"upgrade_costs\":[",
            levels[0], levels[1], levels[2]
        )
        .expect("string write");
        for track in 0..3u8 {
            if track > 0 {
                out.push(',');
            }
            match sim.upgrade_cost(human, track) {
                Some(cost) => write!(out, "{}", cost.to_int_floor()).expect("string write"),
                None => out.push_str("null"),
            }
        }
        write!(
            out,
            "],\"refinery_cost\":{}}}",
            sim.depth_building_cost(human, BuildingKind::Refinery)
                .to_int_floor()
        )
        .expect("string write");
    }
    out.push_str(",\"supply_links\":");
    out.push_str(supply_links);
    // Kestrel only (the ground-layer scenario): Survival keeps its exact shape.
    if is_kestrel_map(sim) {
        let map = sim.map();
        out.push_str(",\"fog\":\"");
        fog.write_mask(
            &mut out,
            usize::from(map.width()) * usize::from(map.height()),
        );
        out.push_str("\",\"shots\":");
        if fog.active {
            shots.reveal(fog);
        }
        out.push_str(&shots.json_array(fog.active));
    }
    out.push('}');
    out
}

/// True when the sim's ground layer is exactly the authored Kestrel Reach text map.
/// The sim carries no scenario tag, so the bridge recognises the fixed map by content.
fn is_kestrel_map(sim: &rts_core::game::sim::Sim) -> bool {
    let ground = sim.map().ground_iter().map(Ground::glyph);
    ground.eq(kestrel::ROWS.iter().flat_map(|row| row.chars()))
}

/// The route alien waves take: holdfast tile to home Command Center tile, inclusive of
/// both ends; empty when the map offers none.
///
/// The home Command Center's own tile is blocked once the building stands, so a
/// forward search to it fails; the free-standing holdfast tile is not, so search
/// home to holdfast and reverse (the waypoints after `HOME_CC`, including `HOLDFAST`).
fn kestrel_wave_route(map: &rts_core::game::map::Map) -> Vec<(u16, u16)> {
    use rts_core::game::path::find_path;
    if let Some(forward) = find_path(map, kestrel::HOLDFAST, kestrel::HOME_CC) {
        return std::iter::once(kestrel::HOLDFAST).chain(forward).collect();
    }
    find_path(map, kestrel::HOME_CC, kestrel::HOLDFAST).map_or_else(Vec::new, |back| {
        back.into_iter()
            .rev()
            .chain(std::iter::once(kestrel::HOME_CC))
            .collect()
    })
}

/// Additive top-level fields (schema stays 5): appended after every pre-existing key.
/// `map_name`, `regions` and `core_node` appear only for Kestrel Reach; `ground`,
/// `ground_table` and `wave_route` appear for every scenario.
fn write_additive_fields(out: &mut String, sim: &rts_core::game::sim::Sim) {
    let kestrel_map = is_kestrel_map(sim);
    if kestrel_map {
        write!(out, ",\"map_name\":{:?},\"regions\":[", kestrel::MAP_NAME).expect("string write");
        for (i, r) in kestrel::REGIONS.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(
                out,
                "{{\"name\":{:?},\"kind\":{:?},\"x0\":{},\"y0\":{},\"x1\":{},\"y1\":{}}}",
                r.name, r.kind, r.x0, r.y0, r.x1, r.y1
            )
            .expect("string write");
        }
        out.push(']');
    }
    out.push_str(",\"ground\":\"");
    out.extend(sim.map().ground_iter().map(Ground::glyph));
    out.push_str("\",\"ground_table\":[");
    for (i, g) in Ground::ALL.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let p = g.props();
        write!(
            out,
            "{{\"glyph\":\"{}\",\"name\":{:?},\"path_cost\":{},\"infantry_pct\":{},\"vehicle_pct\":{},\"cover_pct\":{},\"range_pct\":{},\"buildable\":{},\"passable\":{}}}",
            g.glyph(), g.name(), p.path_cost, p.infantry_pct, p.vehicle_pct, p.cover_pct,
            p.range_pct, p.buildable, p.passable
        )
        .expect("string write");
    }
    out.push_str("],\"wave_route\":[");
    if kestrel_map {
        for (i, (x, y)) in kestrel_wave_route(sim.map()).into_iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            write!(out, "[{x},{y}]").expect("string write");
        }
    }
    out.push(']');
    if kestrel_map {
        write!(
            out,
            ",\"core_node\":[{},{}]",
            kestrel::CORE_NODE.0,
            kestrel::CORE_NODE.1
        )
        .expect("string write");
    }
}

fn write_atomic(path: &Path, contents: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension("json.next");
    std::fs::write(&temporary, contents)?;
    std::fs::rename(temporary, path)
}

/// Task 14: the player's own unit's waypoint queue on a depth map, appended
/// after its stance: `"queue":N` (legs waiting behind the current order), and
/// while N > 0 its `"route"` still to walk as `[x_bits,z_bits,attack]` legs,
/// the current destination first. The points are the player's own clicks, so
/// nothing hidden by the fog is revealed (a forced target is never listed).
fn write_queue(sim: &rts_core::game::sim::Sim, id: EntityId, out: &mut String) -> std::fmt::Result {
    write!(out, ",\"queue\":{}", sim.queue_len(id))?;
    let route = sim.queue_route(id);
    if route.is_empty() {
        return Ok(());
    }
    out.push_str(",\"route\":[");
    for (k, (point, attack_move)) in route.iter().enumerate() {
        if k > 0 {
            out.push(',');
        }
        write!(
            out,
            "[{},{},{}]",
            point.x.to_bits(),
            point.y.to_bits(),
            u8::from(*attack_move)
        )?;
    }
    out.push(']');
    Ok(())
}

/// The `<x_bits>,<z_bits>` world point of an order line, or `None` when a
/// field is missing, malformed or outside
/// [`rts_core::game::sim::ORDER_COORD_LIMIT`] (P2 review
/// M5: raw bits such as `i64::MIN` overflow the fixed-point maths; the sim
/// drops such points too).
fn order_point<'a>(fields: &mut impl Iterator<Item = &'a str>) -> Option<Vec2> {
    let x_bits = fields.next()?.parse::<i64>().ok()?;
    let z_bits = fields.next()?.parse::<i64>().ok()?;
    let point = Vec2::new(Fixed::from_bits(x_bits), Fixed::from_bits(z_bits));
    order_point_in_range(point).then_some(point)
}

#[allow(
    clippy::too_many_lines,
    reason = "a flat one-arm-per-line-kind parser; Task 24 moves it into bridge_protocol unchanged"
)]
fn take_commands(path: &Path) -> Vec<Command> {
    // Legacy single-file input remains readable for older tools. The player client
    // publishes immutable packets with atomic rename, so polling cannot unlink an
    // open append stream or consume half an order.
    let mut contents = std::fs::read_to_string(path).unwrap_or_default();
    let _ = std::fs::remove_file(path);
    let directory = path.with_file_name("commands");
    let mut packets: Vec<_> = std::fs::read_dir(directory)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|packet| packet.extension().is_some_and(|ext| ext == "cmd"))
        .collect();
    packets.sort();
    for packet in packets {
        if let Ok(text) = std::fs::read_to_string(&packet) {
            contents.push_str(&text);
            contents.push('\n');
            let _ = std::fs::remove_file(packet);
        }
    }
    contents
        .lines()
        .filter_map(|line| {
            let mut fields = line.split(',');
            match fields.next()? {
                "move" | "attack" => {
                    let mode = line.starts_with("attack,");
                    let unit = fields.next()?.parse::<u32>().ok()?;
                    let target = order_point(&mut fields)?;
                    Some(if mode {
                        Command::AttackMove {
                            owner: PlayerId(0),
                            unit: EntityId(unit),
                            target,
                        }
                    } else {
                        Command::Move {
                            owner: PlayerId(0),
                            unit: EntityId(unit),
                            target,
                        }
                    })
                }
                "train" => {
                    let barracks = fields.next()?.parse::<u32>().ok()?;
                    let kind = match fields.next()? {
                        "Harvester" => UnitKind::Harvester,
                        "Infantry" => UnitKind::Infantry,
                        "Tank" => UnitKind::Tank,
                        "AntiArmor" => UnitKind::AntiArmor,
                        "Helicopter" => UnitKind::Helicopter,
                        "Capital" => UnitKind::Capital,
                        _ => return None,
                    };
                    Some(Command::Train {
                        owner: PlayerId(0),
                        barracks: EntityId(barracks),
                        kind,
                    })
                }
                "build" => {
                    let kind = match fields.next()? {
                        "PowerPlant" => BuildingKind::PowerPlant,
                        "Refinery" => BuildingKind::Refinery,
                        "Barracks" => BuildingKind::Barracks,
                        "GunTurret" => BuildingKind::GunTurret,
                        "AaTurret" => BuildingKind::AaTurret,
                        "Wall" => BuildingKind::Wall,
                        "ResearchLab" => BuildingKind::ResearchLab,
                        "AntimatterPlant" => BuildingKind::AntimatterPlant,
                        "VehicleFactory" => BuildingKind::VehicleFactory,
                        "Airfield" => BuildingKind::Airfield,
                        "SupplyDepot" => BuildingKind::SupplyDepot,
                        "Battery" => BuildingKind::Battery,
                        _ => return None,
                    };
                    let x = fields.next()?.parse::<u16>().ok()?;
                    let y = fields.next()?.parse::<u16>().ok()?;
                    Some(Command::Build {
                        owner: PlayerId(0),
                        kind,
                        x,
                        y,
                    })
                }
                "research" => {
                    let tech_id = fields.next()?.parse::<u32>().ok()?;
                    Some(Command::Research {
                        owner: PlayerId(0),
                        tech_id,
                    })
                }
                "rally" | "ability" => {
                    let ability = line.starts_with("ability,");
                    let entity = fields.next()?.parse::<u32>().ok()?;
                    let target = order_point(&mut fields)?;
                    Some(if ability {
                        Command::UseAbility {
                            owner: PlayerId(0),
                            unit: EntityId(entity),
                            target,
                        }
                    } else {
                        Command::SetRally {
                            owner: PlayerId(0),
                            producer: EntityId(entity),
                            target,
                        }
                    })
                }
                "repair" | "sell" => {
                    let repair = line.starts_with("repair,");
                    let building = EntityId(fields.next()?.parse::<u32>().ok()?);
                    Some(if repair {
                        Command::Repair {
                            owner: PlayerId(0),
                            building,
                        }
                    } else {
                        Command::Sell {
                            owner: PlayerId(0),
                            building,
                        }
                    })
                }
                // Depth orders (Kestrel). The sim ignores them on any other map.
                "stop" | "hold" => {
                    let hold = line.starts_with("hold,");
                    let unit = EntityId(fields.next()?.parse::<u32>().ok()?);
                    Some(if hold {
                        Command::HoldPosition {
                            owner: PlayerId(0),
                            unit,
                        }
                    } else {
                        Command::Stop {
                            owner: PlayerId(0),
                            unit,
                        }
                    })
                }
                "stance" => {
                    let unit = EntityId(fields.next()?.parse::<u32>().ok()?);
                    let stance = Stance::from_name(fields.next()?)?;
                    Some(Command::SetStance {
                        owner: PlayerId(0),
                        unit,
                        stance,
                    })
                }
                "target" => {
                    let unit = EntityId(fields.next()?.parse::<u32>().ok()?);
                    let target = EntityId(fields.next()?.parse::<u32>().ok()?);
                    Some(Command::AttackTarget {
                        owner: PlayerId(0),
                        unit,
                        target,
                    })
                }
                // Shift-queued waypoints (Kestrel): `qmove`/`qattack,<id>,<x_bits>,<z_bits>`.
                "qmove" | "qattack" => {
                    let attack_move = line.starts_with("qattack,");
                    let unit = EntityId(fields.next()?.parse::<u32>().ok()?);
                    let target = order_point(&mut fields)?;
                    Some(Command::QueueMove {
                        owner: PlayerId(0),
                        unit,
                        target,
                        attack_move,
                    })
                }
                // Upgrades (Kestrel, Task 17): `upgrade,<track>` buys the next
                // level (0 weapons, 1 armour, 2 vitality); the core refuses
                // the forge, the cap and an empty purse.
                "upgrade" => {
                    let track = fields.next()?.parse::<u8>().ok()?;
                    Some(Command::Ascend {
                        owner: PlayerId(0),
                        track,
                    })
                }
                _ => None,
            }
        })
        .collect()
}

fn clear_command_packets(path: &Path) -> std::io::Result<()> {
    let directory = path.with_file_name("commands");
    std::fs::create_dir_all(&directory)?;
    for entry in std::fs::read_dir(directory)? {
        let packet = entry?.path();
        if packet
            .extension()
            .is_some_and(|ext| ext == "cmd" || ext == "next")
        {
            std::fs::remove_file(packet)?;
        }
    }
    Ok(())
}

/// Every file the bridge and the Godot client exchange, all beside the snapshot.
#[derive(Debug)]
struct RuntimePaths {
    /// The snapshot the bridge rewrites every frame.
    snapshot: PathBuf,
    /// The legacy command file (packets live in the `commands` directory beside it).
    commands: PathBuf,
    /// Godot's Deploy click: the mission starts stepping.
    start: PathBuf,
    /// Godot's restart request: rebuild the match (reading `match_config`).
    restart: PathBuf,
    /// Godot's pause menu holds the world still by keeping this file in place;
    /// removing it resumes the run.
    pause: PathBuf,
    /// The next match's settings, written by the client before a restart.
    match_config: PathBuf,
}

impl RuntimePaths {
    fn from_output(output: &Path) -> Self {
        Self {
            snapshot: output.to_path_buf(),
            commands: output.with_file_name("commands.txt"),
            start: output.with_file_name("start.flag"),
            restart: output.with_file_name("restart.flag"),
            pause: output.with_file_name("pause.flag"),
            match_config: output.with_file_name("match.json"),
        }
    }
}

/// The match the client asked for in `match.json`. A key that is missing or
/// malformed keeps its default (`fog: None` means "as the environment says").
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct MatchConfig {
    scenario: Scenario,
    fog: Option<bool>,
}

/// One raw value of a flat JSON object: a quoted string (no escapes) or a bare token.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum RawValue<'a> {
    Quoted(&'a str),
    Bare(&'a str),
}

/// The raw value of `"key":` in a flat JSON object (first occurrence used as a key).
fn raw_json_value<'a>(text: &'a str, key: &str) -> Option<RawValue<'a>> {
    let needle = format!("\"{key}\"");
    let mut from = 0;
    while let Some(found) = text[from..].find(&needle) {
        let after = from + found + needle.len();
        from = after;
        let Some(rest) = text[after..].trim_start().strip_prefix(':') else {
            continue; // the same text as a value, not a key
        };
        let rest = rest.trim_start();
        if let Some(quoted) = rest.strip_prefix('"') {
            return quoted.find('"').map(|end| RawValue::Quoted(&quoted[..end]));
        }
        let end = rest.find([',', '}']).unwrap_or(rest.len());
        return Some(RawValue::Bare(rest[..end].trim()));
    }
    None
}

/// Parses `match.json` (a flat JSON object written by the client). Unknown keys are
/// ignored; a malformed value keeps that key's default; text that is not an object
/// yields `fallback` with the environment's fog.
fn parse_match_config(text: &str, fallback: Scenario) -> MatchConfig {
    let mut config = MatchConfig {
        scenario: fallback,
        fog: None,
    };
    let text = text.trim();
    if !(text.starts_with('{') && text.ends_with('}')) {
        return config;
    }
    if let Some(RawValue::Quoted(name)) = raw_json_value(text, "scenario") {
        config.scenario = parse_scenario(name).unwrap_or(fallback);
    }
    config.fog = match raw_json_value(text, "fog") {
        Some(RawValue::Bare("true")) => Some(true),
        Some(RawValue::Bare("false")) => Some(false),
        _ => None,
    };
    config
}

/// Reads and parses `match.json`; a missing or unreadable file yields `fallback`.
fn read_match_config(path: &Path, fallback: Scenario) -> MatchConfig {
    std::fs::read_to_string(path).map_or(
        MatchConfig {
            scenario: fallback,
            fog: None,
        },
        |text| parse_match_config(&text, fallback),
    )
}

/// Parsed command line: the two historical positional arguments plus the flags.
#[derive(Debug)]
struct Options {
    output: PathBuf,
    frame_limit: u64,
    scenario: Scenario,
    dump_snapshot: Option<PathBuf>,
}

/// Maps a `--scenario` value to a scenario (Kestrel Reach is the default).
fn parse_scenario(value: &str) -> Result<Scenario, String> {
    match value {
        "survival" => Ok(Scenario::Survival),
        "kestrel" => Ok(Scenario::KestrelReach),
        other => Err(format!(
            "unknown scenario '{other}' (expected 'kestrel' or 'survival')"
        )),
    }
}

/// Parses `[--scenario S] [--dump-snapshot P] [output [frame_limit]]`. Flags (also
/// as `--flag=value`) may appear anywhere; they are stripped before the positional
/// arguments (arg 1 = output path, arg 2 = frame limit) are read.
fn parse_args(args: impl IntoIterator<Item = String>) -> Result<Options, String> {
    let mut positional = Vec::new();
    let mut scenario = Scenario::KestrelReach;
    let mut dump_snapshot = None;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let (flag, inline) = match arg.split_once('=') {
            Some((flag, value)) if flag.starts_with("--") => {
                (flag.to_owned(), Some(value.to_owned()))
            }
            _ => (arg.clone(), None),
        };
        match flag.as_str() {
            "--scenario" | "--dump-snapshot" => {
                let value = inline
                    .or_else(|| args.next())
                    .ok_or_else(|| format!("{flag} needs a value"))?;
                if flag == "--scenario" {
                    scenario = parse_scenario(&value)?;
                } else {
                    dump_snapshot = Some(PathBuf::from(value));
                }
            }
            _ if flag.starts_with("--") => return Err(format!("unknown flag '{flag}'")),
            _ => positional.push(arg),
        }
    }
    Ok(Options {
        output: positional.first().map_or_else(
            || PathBuf::from("godot3d/runtime/snapshot.json"),
            PathBuf::from,
        ),
        frame_limit: positional
            .get(1)
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(u64::MAX),
        scenario,
        dump_snapshot,
    })
}

fn main() -> std::io::Result<()> {
    let options = match parse_args(std::env::args().skip(1)) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("godot-bridge: {message}");
            std::process::exit(2);
        }
    };
    let Options {
        output,
        frame_limit,
        mut scenario,
        dump_snapshot,
    } = options;

    // The presentation fog kill switch is read once, here; a running bridge never re-reads it.
    let fog_enabled = fog_enabled_from(std::env::var_os("EARTHFRONT_FOG").as_deref());
    let mut sim = scenario.build(2026);
    sim.set_balance(rts_data::load_default());
    if let Some(path) = dump_snapshot {
        // One frame of the chosen scenario's initial snapshot, for Godot test fixtures.
        let snapshot = snapshot_json_with(
            &sim,
            &supply_links_json(&sim),
            &mut ShotWindow::new(),
            &mut FogState::new(fog_enabled),
        );
        return write_atomic(&path, &snapshot);
    }
    // Match the primary client: the deterministic simulation is authored at 30 Hz.
    // Godot renders between snapshots, but must not double the gameplay speed.
    let frame_time = Duration::from_micros(33_333);
    let paths = RuntimePaths::from_output(&output);
    // Never let an order left by a previous closed match disable opening AI, and never
    // let a previous session's match choice hijack this session's first restart.
    let _ = std::fs::remove_file(&paths.commands);
    let _ = std::fs::remove_file(&paths.start);
    let _ = std::fs::remove_file(&paths.restart);
    let _ = std::fs::remove_file(&paths.pause);
    let _ = std::fs::remove_file(&paths.match_config);
    clear_command_packets(&paths.commands)?;
    let mut mission_started = false;
    let mut supply_cache = SupplyLinkCache::new();
    let mut shots = ShotWindow::new();
    let mut fog = FogState::new(fog_enabled);

    for _ in 0..frame_limit {
        if paths.restart.exists() {
            let _ = std::fs::remove_file(&paths.restart);
            // A rapid second Deploy click must not auto-start the next mission.
            let _ = std::fs::remove_file(&paths.start);
            let _ = std::fs::remove_file(&paths.commands);
            let _ = std::fs::remove_file(&paths.pause);
            clear_command_packets(&paths.commands)?;
            // The client may switch the map (and the fog) for the next match; with no
            // `match.json` the current scenario restarts as before.
            let config = read_match_config(&paths.match_config, scenario);
            scenario = config.scenario;
            sim = scenario.build(2026);
            sim.set_balance(rts_data::load_default());
            mission_started = false;
            supply_cache = SupplyLinkCache::new();
            shots.clear();
            // Explored ground and remembered enemy structures belong to the old match.
            // The environment kill switch always wins over the client's fog choice.
            fog = FogState::new(fog_enabled && config.fog.unwrap_or(true));
        }
        if !mission_started {
            if paths.start.exists() {
                let _ = std::fs::remove_file(&paths.start);
                mission_started = true;
            } else {
                write_atomic(
                    &paths.snapshot,
                    &snapshot_json_with(&sim, supply_cache.get(&sim), &mut shots, &mut fog),
                )?;
                std::thread::sleep(frame_time);
                continue;
            }
        }
        if paths.pause.exists() {
            // Paused: no step, no commands taken (they wait for the resume), the same snapshot stays current.
            write_atomic(
                &paths.snapshot,
                &snapshot_json_with(&sim, supply_cache.get(&sim), &mut shots, &mut fog),
            )?;
            std::thread::sleep(frame_time);
            continue;
        }
        let started = Instant::now();
        let mut player_commands = take_commands(&paths.commands);
        // Orders on enemies the last fogged frame did not show never reach the sim.
        player_commands.retain(|command| fog.admits(command));
        // Host commands (survey AI, alien AI, scenario script) from the one shared
        // builder, so headless tests and replay verification step the same list.
        let mut commands = scenario.host_commands(&sim);
        commands.extend(player_commands);
        sim.step(&commands);
        shots.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
        write_atomic(
            &paths.snapshot,
            &snapshot_json_with(&sim, supply_cache.get(&sim), &mut shots, &mut fog),
        )?;
        std::thread::sleep(frame_time.saturating_sub(started.elapsed()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        fog_enabled_from, parse_args, parse_match_config, read_match_config, sight_radius,
        snapshot_json, snapshot_json_with, supply_links_json, take_commands, BuildingKind, Command,
        EntityId, FogState, PlayerId, RuntimePaths, ShotWindow, SupplyLinkCache, UnitKind,
        SHOT_WINDOW_TICKS,
    };
    use rts_core::game::scenario::Scenario;

    /// Value of the string field `"key":"..."` (first occurrence).
    fn extract_str(json: &str, key: &str) -> String {
        let needle = format!("\"{key}\":\"");
        let start = json.find(&needle).expect("key present") + needle.len();
        let end = json[start..].find('"').expect("closing quote") + start;
        json[start..end].to_owned()
    }

    /// The `{...}` object of the entity with this id (entity objects hold no nesting).
    fn entity_object(json: &str, id: u32) -> String {
        let needle = format!("{{\"id\":{id},\"owner\"");
        let start = json.find(&needle).expect("entity present");
        let end = json[start..].find('}').expect("entity end") + start;
        json[start..=end].to_owned()
    }

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_owned()).collect()
    }

    fn human_infantry(sim: &rts_core::game::sim::Sim) -> EntityId {
        sim.views()
            .into_iter()
            .find(|v| {
                v.owner.0 == 0
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Unit(UnitKind::Infantry)
                    )
            })
            .expect("a human infantry unit")
            .id
    }

    #[test]
    fn qa_concurrent_command_transport_preserves_every_order() {
        use std::sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        };
        let root =
            std::env::temp_dir().join(format!("earthfront-transport-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("commands.txt");
        std::fs::create_dir_all(root.join("commands")).unwrap();
        let done = Arc::new(AtomicBool::new(false));
        let producer_done = done.clone();
        let producer_path = path.clone();
        let producer = std::thread::spawn(move || {
            for id in 0..1000 {
                let packet = producer_path
                    .with_file_name("commands")
                    .join(format!("{id:020}.cmd"));
                let temporary = packet.with_extension("next");
                std::fs::write(&temporary, format!("move,{id},0,0\n")).unwrap();
                std::fs::rename(temporary, packet).unwrap();
                std::thread::sleep(std::time::Duration::from_micros(100));
            }
            producer_done.store(true, Ordering::SeqCst);
        });
        let mut received = Vec::new();
        while !done.load(Ordering::SeqCst) {
            received.extend(take_commands(&path));
            std::thread::sleep(std::time::Duration::from_micros(100));
        }
        producer.join().unwrap();
        received.extend(take_commands(&path));
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(received.len(), 1000, "concurrent player orders were lost");
    }

    #[test]
    fn snapshot_is_parseable_shape_and_contains_entities() {
        let sim = Scenario::Survival.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(json.contains("\"era\":0"));
        assert!(json.contains("\"alien_relays\":2"));
        assert!(json.contains("\"next_expedition_size\":10"));
        assert_eq!(json.matches("\"alien_relay\":true").count(), 2);
        assert!(json.contains("\"research_count\":0"));
        assert!(json.contains("\"suggested_research_name\":"));
        assert!(json.contains("\"waves_survived\":0"));
        assert!(json.contains("\"next_wave_ticks\":"));
        assert!(json.contains("\"unlocked_buildings\":["));
        assert!(json.contains("\"unlocked_units\":["));
        assert!(json.contains("\"max_shield_bits\":"));
        assert!(json.contains("\"ability_cd\":"));
        assert!(json.contains("\"rally_x_bits\":"));
        assert!(json.contains("\"map_width\":44"));
        assert!(json.contains("\"map_height\":26"));
        assert!(json.contains("\"surveying\":true"));
        assert!(json.contains("\"blocked\":["));
        assert!(json.contains("\"deposits\":["));
        assert!(json.contains("\"research_options\":["));
        assert!(json.contains("\"construction_total\":"));
        assert!(json.contains("\"production_name\":"));
        assert!(json.contains("\"entities\":[{"));
        assert!(json.ends_with("]}"));
        assert!(json.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn survival_snapshot_is_unchanged_in_shape_and_has_all_grass_ground() {
        let sim = Scenario::Survival.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(!json.contains("\"map_name\""));
        assert!(!json.contains("\"regions\""));
        assert!(!json.contains("\"core_node\""));
        let g = extract_str(&json, "ground");
        assert_eq!(g.len(), 44 * 26);
        assert!(g.chars().all(|c| c == 'g'));
        assert!(json.contains("\"ground_table\":["));
        assert!(json.contains("\"wave_route\":[]"));
        assert!(json.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn kestrel_snapshot_carries_names_regions_ground_and_table() {
        let sim = Scenario::KestrelReach.build(2026);
        let json = snapshot_json(&sim);
        assert!(json.starts_with("{\"schema\":5,"));
        assert!(json.contains("\"map_name\":\"Kestrel Reach\""));
        assert!(json.contains("\"name\":\"Wyllow Ford\""));
        assert!(json.contains("\"ground_table\":["));
        assert!(json.contains("\"wave_route\":["));
        assert!(json.contains("\"core_node\":[37,8]"));
        let g = extract_str(&json, "ground");
        assert_eq!(g.len(), 44 * 26);
        assert!(g.contains('r') && g.contains('w') && g.contains('h'));
        // Additive and last: at tick 0 the Command Center holds no stock yet, so the
        // three prebuilt structures beside it are not served until the first supply beat.
        // The presentation fog mask (Task 6) sits between the supply links and the shots.
        // The depth Upgrades block (Task 17) sits between the core node and the links;
        // Task 18 appends the next refinery's price to it.
        let fog = extract_str(&json, "fog");
        assert!(json.ends_with(&format!(
            "\"core_node\":[37,8],\"depth\":{{\"upgrades\":[0,0,0],\"upgrade_costs\":[150,150,150],\
             \"refinery_cost\":200}},\
             \"supply_links\":[],\"fog\":\"{fog}\",\"shots\":[]}}"
        )));
        assert!(json.starts_with("{\"schema\":5,"));
    }

    /// A Kestrel sim where the home Command Center (id 0) has stock and a turret in reach.
    fn kestrel_with_a_served_turret() -> (rts_core::game::sim::Sim, EntityId) {
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let turret = sim.add_building(PlayerId(0), BuildingKind::GunTurret, 9, 10);
        while sim.tick() < 30 {
            sim.step(&[]);
        }
        (sim, turret)
    }

    #[test]
    fn supply_links_key_lists_a_supplied_building() {
        let (sim, turret) = kestrel_with_a_served_turret();
        let json = snapshot_json(&sim);
        let link = format!("{{\"depot\":0,\"target\":{},\"state\":\"ok\"}}", turret.0);
        assert!(json.contains(&link), "{link} missing");
        // The Kestrel start also has the Power Plant (5), Refinery (6) and Barracks (7)
        // standing beside the Command Center, so the CC serves them too, listed before
        // the turret in ascending entity order.
        let served: Vec<String> = [5, 6, 7, turret.0]
            .iter()
            .map(|t| format!("{{\"depot\":0,\"target\":{t},\"state\":\"ok\"}}"))
            .collect();
        let fog = extract_str(&json, "fog");
        assert!(
            json.ends_with(&format!(
                "\"supply_links\":[{}],\"fog\":\"{fog}\",\"shots\":[]}}",
                served.join(",")
            )),
            "supply_links precedes the fog mask and the trailing shots key"
        );
        // Pure and deterministic for a given sim state.
        assert_eq!(supply_links_json(&sim), supply_links_json(&sim));
    }

    #[test]
    fn supply_link_cache_recomputes_only_on_the_beat() {
        let (mut sim, turret) = kestrel_with_a_served_turret();
        let mut cache = SupplyLinkCache::new();
        let at_beat = cache.get(&sim).to_owned();
        assert_eq!(at_beat, supply_links_json(&sim));
        assert!(at_beat.contains(&format!("\"target\":{}", turret.0)));
        // A second building in reach appears fresh immediately but not in the cache...
        sim.step(&[]);
        let late = sim.add_building(PlayerId(0), BuildingKind::GunTurret, 9, 12);
        let fresh = supply_links_json(&sim);
        assert!(fresh.contains(&format!("\"target\":{}", late.0)));
        assert_eq!(cache.get(&sim), at_beat);
        while sim.tick() < 59 {
            sim.step(&[]);
            assert_eq!(cache.get(&sim), at_beat, "tick {}", sim.tick());
        }
        // ...until the next supply beat.
        sim.step(&[]);
        assert_eq!(sim.tick(), 60);
        assert!(cache.get(&sim).contains(&format!("\"target\":{}", late.0)));
    }

    #[test]
    fn kestrel_snapshot_is_valid_json_shape() {
        let json = snapshot_json(&Scenario::KestrelReach.build(1));
        assert_eq!(json.matches('{').count(), json.matches('}').count());
        assert_eq!(json.matches('[').count(), json.matches(']').count());
        assert!(!json.contains(",]") && !json.contains(",}"));
        let survival = snapshot_json(&Scenario::Survival.build(1));
        assert_eq!(survival.matches('{').count(), survival.matches('}').count());
        assert!(!survival.contains(",]") && !survival.contains(",}"));
    }

    /// A Kestrel sim with two opposing infantry squads in rifle range, in open ground.
    fn kestrel_firefight() -> (rts_core::game::sim::Sim, EntityId, EntityId) {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let at = |x: i32, y: i32| Vec2::new(Fixed::from_int(x), Fixed::from_int(y));
        let ours = sim.add_unit(PlayerId(0), UnitKind::Infantry, at(20, 12));
        let theirs = sim.add_unit(PlayerId(1), UnitKind::Infantry, at(21, 12));
        (sim, ours, theirs)
    }

    /// One snapshot with the fog on (a fresh fog, as `--dump-snapshot` writes it).
    fn snap(sim: &rts_core::game::sim::Sim, window: &mut ShotWindow) -> String {
        snapshot_json_with(sim, "[]", window, &mut FogState::new(true))
    }

    /// Steps once and feeds the window the way the main loop does.
    fn step_into(sim: &mut rts_core::game::sim::Sim, window: &mut ShotWindow) {
        sim.step(&[]);
        window.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
    }

    /// Parses the `"shots":[[...],...]` value into rows of five integers.
    fn parse_shots(json: &str) -> Vec<[i64; 5]> {
        let start = json.find("\"shots\":[").expect("shots key") + "\"shots\":[".len();
        let body = &json[start..json.len() - 2];
        if body.is_empty() {
            return Vec::new();
        }
        body.trim_start_matches('[')
            .split("],[")
            .map(|row| {
                let nums: Vec<i64> = row
                    .trim_end_matches(']')
                    .split(',')
                    .map(|n| n.parse().expect("integer"))
                    .collect();
                <[i64; 5]>::try_from(nums).expect("five integers per shot")
            })
            .collect()
    }

    #[test]
    fn kestrel_snapshot_carries_the_recent_shots_of_the_real_shooters() {
        let (mut sim, ours, theirs) = kestrel_firefight();
        let mut window = ShotWindow::new();
        let mut guard = 0;
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
            guard += 1;
            assert!(guard < 200, "the two squads never fired");
        }
        let pos = |id: EntityId| {
            sim.views()
                .into_iter()
                .find(|v| v.id == id)
                .expect("unit")
                .pos
        };
        let (a, t) = (pos(ours), pos(theirs));
        let json = snap(&sim, &mut window);
        assert!(json.ends_with("]]}"), "shots is the final key: {json}");
        let shots = parse_shots(&json);
        assert!(!shots.is_empty());
        let tick = i64::try_from(sim.tick()).unwrap();
        let last = shots.last().unwrap();
        assert_eq!(last[0], tick, "tagged with the tick it was fired on");
        let pair = |p: rts_core::vec::Vec2| (p.x.to_bits(), p.y.to_bits());
        let shot_pair = |s: &[i64; 5]| ((s[1], s[2]), (s[3], s[4]));
        assert!(
            shots
                .iter()
                .any(|s| shot_pair(s) == (pair(a), pair(t)) || shot_pair(s) == (pair(t), pair(a))),
            "an entry must run from one real unit to the other: {shots:?}"
        );
    }

    #[test]
    fn shot_window_does_not_grow_after_a_win() {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let mut window = ShotWindow::new();
        let a = (
            Vec2::new(Fixed::ONE, Fixed::ONE),
            Vec2::new(Fixed::from_int(2), Fixed::ONE),
        );
        window.record(100, &[a], false);
        let len = window.len();
        for _ in 0..100 {
            window.record(100, &[a], false); // tick did not advance
            window.record(100, &[a], true); // finished sim
        }
        assert_eq!(window.len(), len);
    }

    #[test]
    fn won_sim_stepped_for_100_frames_keeps_the_window_length() {
        let mut sim = Scenario::KestrelReach.build(2026);
        let mut window = ShotWindow::new();
        // Drive to a winner the cheap way: the undefended run.
        while sim.winner().is_none() {
            let cmds = sim.ai_commands(PlayerId(1));
            sim.step(&cmds);
            window.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
        }
        let len = window.len();
        let bytes = snap(&sim, &mut window).len();
        for _ in 0..100 {
            sim.step(&[]);
            window.record(sim.tick(), sim.recent_attacks(), sim.winner().is_some());
        }
        assert_eq!(window.len(), len);
        // The bridge rewrites this snapshot every frame on the victory screen.
        assert_eq!(snap(&sim, &mut window).len(), bytes);
    }

    #[test]
    fn match_config_parses_and_falls_back() {
        let c = parse_match_config(
            r#"{"scenario":"survival","seed":7,"difficulty":"hard","fog":false}"#,
            Scenario::KestrelReach,
        );
        assert_eq!(c.scenario, Scenario::Survival);
        assert_eq!(c.fog, Some(false));
        let c = parse_match_config("not json", Scenario::KestrelReach);
        assert_eq!((c.scenario, c.fog), (Scenario::KestrelReach, None));
        let c = parse_match_config(
            r#"{"scenario":"mars","fog":"maybe"}"#,
            Scenario::KestrelReach,
        );
        assert_eq!((c.scenario, c.fog), (Scenario::KestrelReach, None));
        let c = read_match_config(
            std::path::Path::new("/nonexistent/match.json"),
            Scenario::Survival,
        );
        assert_eq!(c.scenario, Scenario::Survival);
    }

    #[test]
    fn runtime_paths_sit_beside_the_snapshot() {
        let p = RuntimePaths::from_output(std::path::Path::new("/r/snapshot.json"));
        assert_eq!(p.restart, std::path::PathBuf::from("/r/restart.flag"));
        assert_eq!(p.match_config, std::path::PathBuf::from("/r/match.json"));
        assert_eq!(p.commands, std::path::PathBuf::from("/r/commands.txt"));
    }

    #[test]
    fn shots_older_than_the_window_are_pruned_oldest_first() {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let p = |n: i32| Vec2::new(Fixed::from_int(n), Fixed::from_int(n));
        let mut window = ShotWindow::new();
        window.record(10, &[(p(1), p(2))], false);
        window.record(11, &[(p(3), p(4)), (p(5), p(6))], false);
        assert_eq!(window.len(), 3);
        // Still inside: age 17 at tick 27.
        window.record(10 + SHOT_WINDOW_TICKS - 1, &[], false);
        assert_eq!(window.len(), 3);
        // Tick 10 falls out at age 18, tick 11 one tick later.
        window.record(10 + SHOT_WINDOW_TICKS, &[], false);
        assert_eq!(window.len(), 2);
        window.record(11 + SHOT_WINDOW_TICKS, &[], false);
        assert_eq!(window.len(), 0);
        // Order is oldest first.
        window.record(100, &[(p(1), p(2))], false);
        window.record(101, &[(p(3), p(4))], false);
        let json = window.json_array(false);
        assert!(
            json.starts_with("[[100,") && json.contains("],[101,"),
            "{json}"
        );
    }

    #[test]
    fn the_snapshot_drops_a_shot_once_it_is_older_than_the_window() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        let fired = sim.tick();
        assert!(!parse_shots(&snap(&sim, &mut window)).is_empty());
        // The firefight ends (no further attacks fed in); the window runs out.
        window.record(fired + SHOT_WINDOW_TICKS - 1, &[], false);
        assert!(!window.is_empty());
        window.record(fired + SHOT_WINDOW_TICKS, &[], false);
        assert!(parse_shots(&snap(&sim, &mut window)).is_empty());
    }

    #[test]
    fn survival_snapshot_has_no_shots_key_even_with_a_full_window() {
        use rts_core::fixed::Fixed;
        use rts_core::vec::Vec2;
        let sim = Scenario::Survival.build(2026);
        let mut window = ShotWindow::new();
        let p = Vec2::new(Fixed::from_int(1), Fixed::from_int(1));
        window.record(sim.tick(), &[(p, p)], false);
        let with_window = snap(&sim, &mut window);
        assert!(!with_window.contains("\"shots\""));
        assert_eq!(with_window, snap(&sim, &mut ShotWindow::new()));
        assert!(with_window.ends_with("\"supply_links\":[]}"));
    }

    #[test]
    fn clearing_the_window_on_restart_drops_every_shot() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        assert!(!window.is_empty());
        window.clear();
        assert!(window.is_empty());
        let json = snap(&sim, &mut window);
        assert!(json.ends_with("\"shots\":[]}"));
    }

    #[test]
    fn kestrel_snapshot_with_shots_is_valid_json_shape() {
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        let json = snap(&sim, &mut window);
        assert_eq!(json.matches('{').count(), json.matches('}').count());
        assert_eq!(json.matches('[').count(), json.matches(']').count());
        assert!(!json.contains(",]") && !json.contains(",}"));
        assert!(json.contains("\"shots\":[["));
    }

    #[test]
    fn kestrel_wave_route_starts_at_the_holdfast_and_reaches_home() {
        use rts_core::game::kestrel::{HOLDFAST, HOME_CC};
        let json = snapshot_json(&Scenario::KestrelReach.build(2026));
        let start = json.find("\"wave_route\":[").expect("wave_route") + "\"wave_route\":".len();
        let end = json[start..].find("]]").expect("route end") + start + 2;
        let route = &json[start..end];
        assert!(route.len() > 2, "route must be non-empty");
        let first = format!("[[{},{}]", HOLDFAST.0, HOLDFAST.1);
        assert!(
            route.starts_with(&first),
            "route starts at holdfast: {route}"
        );
        let last = format!("[{},{}]]", HOME_CC.0, HOME_CC.1);
        assert!(route.ends_with(&last), "route ends at home CC: {route}");
    }

    #[test]
    fn idle_is_false_for_a_moving_unit_and_true_for_a_stationary_one() {
        use rts_core::fixed::Fixed;
        use rts_core::game::sim::PlayerId;
        use rts_core::vec::Vec2;
        // Kestrel opens with four founding rifle squads; Survival opens mid-survey.
        let mut sim = Scenario::KestrelReach.build(2026);
        let id = human_infantry(&sim);
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, id.0).contains("\"idle\":true"));
        let pos = sim
            .views()
            .into_iter()
            .find(|v| v.id == id)
            .expect("unit")
            .pos;
        sim.step(&[Command::Move {
            owner: PlayerId(0),
            unit: id,
            target: pos + Vec2::new(Fixed::from_int(5), Fixed::ZERO),
        }]);
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, id.0).contains("\"idle\":false"));
        let obj = entity_object(&json, id.0);
        assert!(obj.contains("\"rank\":0"));
        // Buildings are never idle units.
        let cc = sim
            .views()
            .into_iter()
            .find(|v| {
                v.owner.0 == 0
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Building(BuildingKind::CommandCenter)
                    )
            })
            .map(|v| v.id);
        if let Some(cc) = cc {
            assert!(entity_object(&json, cc.0).contains("\"idle\":false"));
        }
    }

    #[test]
    fn river_kw_is_twelve_for_a_riverside_plant_and_zero_elsewhere() {
        // Kestrel's river-side plant site is (18, 6); (10, 12) is dry meadow.
        let mut sim = Scenario::KestrelReach.build(2026);
        let wet = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::PowerPlant,
            18,
            6,
        );
        let dry = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::PowerPlant,
            10,
            12,
        );
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, wet.0).contains("\"river_kw\":12"));
        assert!(entity_object(&json, dry.0).contains("\"river_kw\":0"));
        let refinery = sim.add_building(
            rts_core::game::sim::PlayerId(0),
            BuildingKind::Refinery,
            19,
            7,
        );
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, refinery.0).contains("\"ore_bonus\":true"));
        // Non-plant entities carry no river_kw.
        assert!(!entity_object(&json, refinery.0).contains("river_kw"));
    }

    #[test]
    fn scenario_flag_parses_anywhere_without_breaking_positional_args() {
        let o = parse_args(args(&[])).unwrap();
        assert_eq!(o.scenario, Scenario::KestrelReach);
        assert_eq!(o.frame_limit, u64::MAX);
        assert_eq!(
            o.output,
            std::path::PathBuf::from("godot3d/runtime/snapshot.json")
        );
        let o = parse_args(args(&["out.json", "5"])).unwrap();
        assert_eq!((o.output.to_str(), o.frame_limit), (Some("out.json"), 5));
        let o = parse_args(args(&["--scenario", "kestrel", "out.json", "5"])).unwrap();
        assert_eq!(o.scenario, Scenario::KestrelReach);
        assert_eq!((o.output.to_str(), o.frame_limit), (Some("out.json"), 5));
        let o = parse_args(args(&["out.json", "--scenario=survival", "7"])).unwrap();
        assert_eq!(o.scenario, Scenario::Survival);
        assert_eq!(o.frame_limit, 7);
        let o = parse_args(args(&["out.json", "9", "--scenario", "kestrel"])).unwrap();
        assert_eq!(o.scenario, Scenario::KestrelReach);
        assert_eq!(o.frame_limit, 9);
        let o = parse_args(args(&[
            "--scenario",
            "kestrel",
            "--dump-snapshot",
            "f.json",
        ]))
        .unwrap();
        assert_eq!(
            o.dump_snapshot.as_deref().and_then(|p| p.to_str()),
            Some("f.json")
        );
    }

    #[test]
    fn scenario_flag_rejects_unknown_values_and_missing_arguments() {
        let err = parse_args(args(&["--scenario", "mars"])).unwrap_err();
        assert!(err.contains("mars") && err.contains("kestrel"), "{err}");
        assert!(parse_args(args(&["--scenario"])).is_err());
        assert!(parse_args(args(&["--dump-snapshot"])).is_err());
        assert!(parse_args(args(&["--bogus"])).is_err());
    }

    #[test]
    fn godot_command_file_supports_rts_orders() {
        let path =
            std::env::temp_dir().join(format!("earthfront-commands-{}.txt", std::process::id()));
        std::fs::write(
            &path,
            "move,7,65536,131072\nattack,8,196608,262144\ntrain,9,Tank\nbuild,Barracks,4,5\nresearch,20\nrally,9,327680,393216\nability,7,458752,524288\nrepair,11\nsell,12\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 9);
        assert!(matches!(
            commands[0],
            Command::Move {
                unit: EntityId(7),
                ..
            }
        ));
        assert!(matches!(
            commands[1],
            Command::AttackMove {
                unit: EntityId(8),
                ..
            }
        ));
        assert!(matches!(
            commands[2],
            Command::Train {
                barracks: EntityId(9),
                kind: UnitKind::Tank,
                ..
            }
        ));
        assert!(matches!(
            commands[3],
            Command::Build {
                kind: BuildingKind::Barracks,
                x: 4,
                y: 5,
                ..
            }
        ));
        assert!(matches!(commands[4], Command::Research { tech_id: 20, .. }));
        assert!(matches!(
            commands[5],
            Command::SetRally {
                producer: EntityId(9),
                ..
            }
        ));
        assert!(matches!(
            commands[6],
            Command::UseAbility {
                unit: EntityId(7),
                ..
            }
        ));
        assert!(matches!(
            commands[7],
            Command::Repair {
                building: EntityId(11),
                ..
            }
        ));
        assert!(matches!(
            commands[8],
            Command::Sell {
                building: EntityId(12),
                ..
            }
        ));
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }

    #[test]
    fn godot_command_file_supports_depth_orders() {
        use rts_core::game::sim::Stance;
        let path = std::env::temp_dir().join(format!(
            "earthfront-depth-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "stop,7\nhold,8\nstance,9,defensive\ntarget,10,44\n\
             stop,x\nhold,\nstance,9,Defensive\nstance,9\nstance,x,hold\n\
             target,10\ntarget,10,y\ntarget,-1,3\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 4, "malformed depth lines are dropped");
        assert!(matches!(
            commands[0],
            Command::Stop {
                owner: PlayerId(0),
                unit: EntityId(7)
            }
        ));
        assert!(matches!(
            commands[1],
            Command::HoldPosition {
                owner: PlayerId(0),
                unit: EntityId(8)
            }
        ));
        assert!(matches!(
            commands[2],
            Command::SetStance {
                owner: PlayerId(0),
                unit: EntityId(9),
                stance: Stance::Defensive
            }
        ));
        assert!(matches!(
            commands[3],
            Command::AttackTarget {
                owner: PlayerId(0),
                unit: EntityId(10),
                target: EntityId(44)
            }
        ));
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }

    #[test]
    fn godot_command_file_supports_upgrades() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-upgrade-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "upgrade,0\nupgrade,2\nupgrade,3\n\
             upgrade,x\nupgrade,\nupgrade\nupgrade,-1\nupgrade,256\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        // The forge (3) parses; the core refuses it (Task 17).
        assert_eq!(commands.len(), 3, "malformed upgrade lines are dropped");
        for (command, want) in commands.iter().zip([0u8, 2, 3]) {
            assert!(
                matches!(*command, Command::Ascend { owner: PlayerId(0), track } if track == want),
                "{command:?}"
            );
        }
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }

    #[test]
    fn kestrel_snapshot_carries_the_upgrades_block_and_survival_none() {
        let mut sim = Scenario::KestrelReach.build(2026);
        let json = snapshot_json(&sim);
        assert!(
            json.contains(
                ",\"depth\":{\"upgrades\":[0,0,0],\"upgrade_costs\":[150,150,150],\
                 \"refinery_cost\":200}"
            ),
            "{}",
            &json[json.len().saturating_sub(300)..]
        );
        for track in [0, 0, 0, 2] {
            sim.step(&[Command::Ascend {
                owner: PlayerId(0),
                track,
            }]);
        }
        let json = snapshot_json(&sim);
        assert!(
            json.contains(
                ",\"depth\":{\"upgrades\":[3,0,1],\"upgrade_costs\":[null,150,250],\
                 \"refinery_cost\":200}"
            ),
            "{}",
            &json[json.len().saturating_sub(300)..]
        );
        let survival = snapshot_json(&Scenario::Survival.build(2026));
        assert!(!survival.contains("\"depth\""));
        assert!(!survival.contains("upgrade"));
    }

    #[test]
    fn kestrel_depth_block_prices_the_next_refinery_and_buildings_carry_their_repair_cooldown() {
        use rts_core::game::sim::EntityKindView;
        use rts_core::game::stats::BuildingKind;
        let mut sim = Scenario::KestrelReach.build(2026);
        let json = snapshot_json(&sim);
        // One refinery stands at the start, so the next costs 150 + 50.
        assert!(
            json.contains(",\"upgrade_costs\":[150,150,150],\"refinery_cost\":200}"),
            "{}",
            &json[json.len().saturating_sub(300)..]
        );
        let cc = sim
            .views()
            .into_iter()
            .find(|v| {
                v.owner == PlayerId(0)
                    && matches!(
                        v.kind,
                        EntityKindView::Building(BuildingKind::CommandCenter)
                    )
            })
            .expect("home command center")
            .id;
        assert!(entity_object(&json, cc.0).ends_with(",\"repair_cd\":0}"));
        let (x, y) = (0..sim.map().height())
            .flat_map(|y| (0..sim.map().width()).map(move |x| (x, y)))
            .find(|&(x, y)| sim.construction_allowed_at(PlayerId(0), x, y))
            .expect("a build site");
        sim.grant_money(PlayerId(0), rts_core::fixed::Fixed::from_int(2000));
        sim.step(&[Command::Build {
            owner: PlayerId(0),
            kind: BuildingKind::Refinery,
            x,
            y,
        }]);
        // An alien squad beside the Command Center scratches it, then a repair.
        let cc_view = |sim: &rts_core::game::sim::Sim| {
            sim.views().into_iter().find(|v| v.id == cc).expect("cc")
        };
        let at = cc_view(&sim).pos
            + rts_core::vec::Vec2::new(
                rts_core::fixed::Fixed::from_int(1),
                rts_core::fixed::Fixed::ZERO,
            );
        sim.add_unit(PlayerId(1), UnitKind::Tank, at);
        for _ in 0..300 {
            if cc_view(&sim).hp < cc_view(&sim).max_hp {
                break;
            }
            sim.step(&[]);
        }
        assert!(
            cc_view(&sim).hp < cc_view(&sim).max_hp,
            "the CC was never hit"
        );
        sim.step(&[Command::Repair {
            owner: PlayerId(0),
            building: cc,
        }]);
        let json = snapshot_json(&sim);
        assert!(json.contains(",\"refinery_cost\":250}"));
        assert!(
            entity_object(&json, cc.0).ends_with(",\"repair_cd\":449}"),
            "{}",
            entity_object(&json, cc.0)
        );
        // Units and the alien side's buildings carry no repair cooldown.
        let mut checked = 0;
        for v in sim.views() {
            let own_building =
                v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Building(_));
            let shown = json.contains(&format!("{{\"id\":{},\"owner\"", v.id.0));
            if !shown {
                continue;
            }
            let obj = entity_object(&json, v.id.0);
            assert_eq!(obj.contains("repair_cd"), own_building, "{obj}");
            checked += 1;
        }
        assert!(checked > 5);
        let survival = snapshot_json(&Scenario::Survival.build(2026));
        assert!(!survival.contains("refinery_cost"));
        assert!(!survival.contains("repair_cd"));
    }

    #[test]
    fn godot_command_file_supports_queued_waypoints() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-queue-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "qmove,7,65536,-131072\nqattack,8,196608,262144\n\
             qmove,x,1,2\nqmove,7,1\nqattack,8,1,y\nqmove,-1,1,2\nqattack,\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 2, "malformed queue lines are dropped");
        assert!(matches!(
            commands[0],
            Command::QueueMove {
                owner: PlayerId(0),
                unit: EntityId(7),
                attack_move: false,
                target
            } if target.x.to_bits() == 65536 && target.y.to_bits() == -131_072
        ));
        assert!(matches!(
            commands[1],
            Command::QueueMove {
                owner: PlayerId(0),
                unit: EntityId(8),
                attack_move: true,
                target
            } if target.x.to_bits() == 196_608 && target.y.to_bits() == 262_144
        ));
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }

    /// P2 review M5: a point line whose raw bits lie outside any map (up to
    /// `i64::MIN`, which used to panic `hex::from_world` in a debug verifier)
    /// is dropped like any malformed line; points at the limit still parse.
    #[test]
    fn godot_command_file_drops_hostile_order_points() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-hostile-commands-{}.txt",
            std::process::id()
        ));
        let limit = rts_core::game::sim::ORDER_COORD_LIMIT.to_bits();
        let min = i64::MIN;
        let max = i64::MAX;
        let over = limit + 1;
        std::fs::write(
            &path,
            format!(
                "qmove,7,{min},0\nqattack,7,0,{max}\nmove,7,{min},{min}\n\
                 attack,7,{over},0\nrally,3,0,-{over}\nability,7,{max},0\n\
                 qmove,7,{limit},-{limit}\nmove,7,65536,65536\n"
            ),
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 2, "hostile point lines are dropped");
        assert!(matches!(
            commands[0],
            Command::QueueMove { target, .. }
                if target.x.to_bits() == limit && target.y.to_bits() == -limit
        ));
        assert!(matches!(commands[1], Command::Move { .. }));
    }

    /// P2 review M1: the bridge passes a `target` order to the sim only when
    /// the fogged snapshot the player last saw showed that enemy live, so a
    /// hand-written line cannot probe or chase a hidden enemy id; with the fog
    /// off (or on Survival) every order passes.
    #[test]
    fn fog_drops_attack_target_orders_on_enemies_out_of_sight() {
        use rts_core::fixed::Fixed;
        use rts_core::game::sim::EntityKindView;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let rifle = human_infantry(&sim);
        let hidden = sim
            .views()
            .into_iter()
            .find(|v| v.owner != PlayerId(0) && matches!(v.kind, EntityKindView::Unit(_)))
            .expect("an alien unit")
            .id;
        let order = |target| Command::AttackTarget {
            owner: PlayerId(0),
            unit: rifle,
            target,
        };
        let mut fog = FogState::new(true);
        let _ = snapshot_json_with(&sim, "[]", &mut ShotWindow::new(), &mut fog);
        assert!(!fog.admits(&order(hidden)), "a hidden enemy was targeted");
        assert!(!fog.admits(&order(EntityId(9999))), "an unknown id passed");
        assert!(fog.admits(&Command::Stop {
            owner: PlayerId(0),
            unit: rifle,
        }));
        // An enemy that walks into sight can be targeted on the next frame.
        let near = sim.position(rifle).expect("rifle") + Vec2::new(Fixed::ONE, Fixed::ZERO);
        let seen = sim.add_unit(PlayerId(1), UnitKind::Infantry, near);
        let _ = snapshot_json_with(&sim, "[]", &mut ShotWindow::new(), &mut fog);
        assert!(fog.admits(&order(seen)));
        assert!(!fog.admits(&order(hidden)));
        // Fog off: the player sees everything, so nothing is filtered.
        let mut off = FogState::new(false);
        let _ = snapshot_json_with(&sim, "[]", &mut ShotWindow::new(), &mut off);
        assert!(off.admits(&order(hidden)));
    }

    #[test]
    fn kestrel_human_units_carry_their_queue_and_nothing_else_does() {
        use rts_core::game::hex;
        use rts_core::game::sim::EntityKindView;
        let mut sim = Scenario::KestrelReach.build(2026);
        let id = human_infantry(&sim);
        let json = snapshot_json(&sim);
        let obj = entity_object(&json, id.0);
        assert!(obj.contains(",\"queue\":0"), "{obj}");
        assert!(!obj.contains("\"route\""), "{obj}");
        let legs = [
            (hex::center(9, 7), false),
            (hex::center(12, 9), true),
            (hex::center(9, 11), false),
        ];
        let orders: Vec<Command> = legs
            .iter()
            .map(|&(target, attack_move)| Command::QueueMove {
                owner: PlayerId(0),
                unit: id,
                target,
                attack_move,
            })
            .collect();
        sim.step(&orders);
        let json = snapshot_json(&sim);
        let obj = entity_object(&json, id.0);
        let bits = |p: rts_core::vec::Vec2| (p.x.to_bits(), p.y.to_bits());
        let route: String = legs
            .iter()
            .map(|&(p, a)| {
                let (x, z) = bits(p);
                format!("[{x},{z},{}]", u8::from(a))
            })
            .collect::<Vec<_>>()
            .join(",");
        assert!(
            obj.contains(&format!(",\"queue\":2,\"route\":[{route}]")),
            "{obj}"
        );
        // Enemy units and buildings never carry a queue or a route.
        let mut checked = 0;
        for v in sim.views() {
            let own_unit = v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(_));
            let shown = json.contains(&format!("{{\"id\":{},\"owner\"", v.id.0));
            if own_unit || !shown {
                continue;
            }
            let obj = entity_object(&json, v.id.0);
            assert!(
                !obj.contains("\"queue\"") && !obj.contains("\"route\""),
                "{obj}"
            );
            checked += 1;
        }
        assert!(checked > 0, "no building or alien was checked");
        // A Stop clears the queue and the route with it.
        sim.step(&[Command::Stop {
            owner: PlayerId(0),
            unit: id,
        }]);
        let json = snapshot_json(&sim);
        let obj = entity_object(&json, id.0);
        assert!(
            obj.contains(",\"queue\":0") && !obj.contains("\"route\""),
            "{obj}"
        );
        // Survival has no depth: no queue key anywhere.
        let survival = snapshot_json(&Scenario::Survival.build(2026));
        assert!(!survival.contains("\"queue\"") && !survival.contains("\"route\""));
    }

    #[test]
    fn kestrel_human_units_carry_their_stance_and_nothing_else_does() {
        use rts_core::game::sim::{EntityKindView, Stance};
        let mut sim = Scenario::KestrelReach.build(2026);
        let id = human_infantry(&sim);
        let json = snapshot_json(&sim);
        assert!(
            entity_object(&json, id.0).contains("\"stance\":\"aggressive\""),
            "{}",
            entity_object(&json, id.0)
        );
        sim.step(&[Command::SetStance {
            owner: PlayerId(0),
            unit: id,
            stance: Stance::Hold,
        }]);
        let json = snapshot_json(&sim);
        assert!(entity_object(&json, id.0).contains("\"stance\":\"hold\""));
        // Enemy units and every building carry no stance, so nothing about
        // the alien side's orders reaches the client.
        let mut checked = 0;
        for v in sim.views() {
            let own_unit = v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(_));
            let shown = json.contains(&format!("{{\"id\":{},\"owner\"", v.id.0));
            if own_unit || !shown {
                continue;
            }
            let obj = entity_object(&json, v.id.0);
            assert!(!obj.contains("stance"), "{obj}");
            checked += 1;
        }
        assert!(checked > 0, "no building or alien was checked");
        let alien = sim.add_unit(
            PlayerId(1),
            UnitKind::Infantry,
            sim.views()
                .into_iter()
                .find(|v| v.id == id)
                .expect("unit")
                .pos,
        );
        let json = snapshot_json(&sim);
        assert!(!entity_object(&json, alien.0).contains("stance"));
        // Survival has no depth, so it never mentions a stance.
        let survival = snapshot_json(&Scenario::Survival.build(2026));
        assert!(!survival.contains("\"stance\""));
    }

    #[test]
    fn godot_command_file_covers_the_complete_combat_roster() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-roster-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "train,9,AntiArmor\ntrain,9,Helicopter\ntrain,9,Capital\nbuild,AaTurret,1,2\nbuild,Wall,2,3\nbuild,ResearchLab,3,4\nbuild,AntimatterPlant,4,5\n",
        )
        .expect("write complete-roster fixture");
        let commands = take_commands(&path);
        assert_eq!(commands.len(), 7);
        assert!(matches!(
            commands[0],
            Command::Train {
                kind: UnitKind::AntiArmor,
                ..
            }
        ));
        assert!(matches!(
            commands[1],
            Command::Train {
                kind: UnitKind::Helicopter,
                ..
            }
        ));
        assert!(matches!(
            commands[2],
            Command::Train {
                kind: UnitKind::Capital,
                ..
            }
        ));
        assert!(matches!(
            commands[3],
            Command::Build {
                kind: BuildingKind::AaTurret,
                ..
            }
        ));
        assert!(matches!(
            commands[4],
            Command::Build {
                kind: BuildingKind::Wall,
                ..
            }
        ));
        assert!(matches!(
            commands[5],
            Command::Build {
                kind: BuildingKind::ResearchLab,
                ..
            }
        ));
        assert!(matches!(
            commands[6],
            Command::Build {
                kind: BuildingKind::AntimatterPlant,
                ..
            }
        ));
        assert!(!path.exists(), "bridge consumes the roster file atomically");
    }

    // ---- Presentation fog of war (Kestrel only) ----

    const W: u16 = 44;
    const H: u16 = 26;

    /// FNV-1a 64 of a snapshot string: a compact, dependency-free byte fingerprint.
    fn fnv1a(text: &str) -> u64 {
        text.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
        })
    }

    // A tiny strict JSON parser for the fog tests (no serde in this crate).
    fn ws(b: &[u8], i: &mut usize) {
        while *i < b.len() && b" \t\n\r".contains(&b[*i]) {
            *i += 1;
        }
    }
    fn string(b: &[u8], i: &mut usize) -> bool {
        if b.get(*i) != Some(&b'"') {
            return false;
        }
        *i += 1;
        while let Some(&c) = b.get(*i) {
            *i += 1;
            match c {
                b'"' => return true,
                b'\\' => *i += 1,
                c if c < 0x20 => return false,
                _ => {}
            }
        }
        false
    }
    fn digits(b: &[u8], i: &mut usize) -> bool {
        let start = *i;
        while b.get(*i).is_some_and(u8::is_ascii_digit) {
            *i += 1;
        }
        *i > start
    }
    fn number(b: &[u8], i: &mut usize) -> bool {
        if b.get(*i) == Some(&b'-') {
            *i += 1;
        }
        if !digits(b, i) {
            return false;
        }
        if b.get(*i) == Some(&b'.') {
            *i += 1;
            if !digits(b, i) {
                return false;
            }
        }
        if matches!(b.get(*i), Some(b'e' | b'E')) {
            *i += 1;
            if matches!(b.get(*i), Some(b'+' | b'-')) {
                *i += 1;
            }
            return digits(b, i);
        }
        true
    }
    fn items(b: &[u8], i: &mut usize, close: u8, keyed: bool) -> bool {
        *i += 1;
        ws(b, i);
        if b.get(*i) == Some(&close) {
            *i += 1;
            return true;
        }
        loop {
            ws(b, i);
            if keyed {
                if !string(b, i) {
                    return false;
                }
                ws(b, i);
                if b.get(*i) != Some(&b':') {
                    return false;
                }
                *i += 1;
            }
            if !value(b, i) {
                return false;
            }
            ws(b, i);
            match b.get(*i) {
                Some(b',') => *i += 1,
                Some(&c) if c == close => {
                    *i += 1;
                    return true;
                }
                _ => return false,
            }
        }
    }
    fn value(b: &[u8], i: &mut usize) -> bool {
        ws(b, i);
        let literal = |word: &[u8], i: &mut usize| {
            let ok = b[*i..].starts_with(word);
            *i += word.len();
            ok
        };
        match b.get(*i) {
            Some(b'{') => items(b, i, b'}', true),
            Some(b'[') => items(b, i, b']', false),
            Some(b'"') => string(b, i),
            Some(b't') => literal(b"true", i),
            Some(b'f') => literal(b"false", i),
            Some(b'n') => literal(b"null", i),
            Some(c) if *c == b'-' || c.is_ascii_digit() => number(b, i),
            _ => false,
        }
    }

    /// Strict JSON check (RFC 8259 grammar, no extensions): the snapshot must stay
    /// parseable by Godot's `JSON.parse` whatever the fog drops or adds.
    fn json_ok(text: &str) -> bool {
        let b = text.as_bytes();
        let mut i = 0;
        let ok = value(b, &mut i);
        ws(b, &mut i);
        ok && i == b.len()
    }

    #[test]
    fn the_json_checker_rejects_what_godot_would_reject() {
        assert!(json_ok("{\"a\":[1,-2.5e3,true,null,\"x\\\"y\"],\"b\":{}}"));
        for bad in [
            "{\"a\":1,}",
            "[1,]",
            "{\"a\" 1}",
            "{\"a\":1}}",
            "[01x]",
            "{'a':1}",
            "",
        ] {
            assert!(!json_ok(bad), "{bad}");
        }
    }

    fn fog_of(json: &str) -> String {
        extract_str(json, "fog")
    }

    fn cell(c: u16, r: u16) -> usize {
        usize::from(r) * usize::from(W) + usize::from(c)
    }

    fn has_entity(json: &str, id: u32) -> bool {
        json.contains(&format!("{{\"id\":{id},\"owner\""))
    }

    fn has_service(json: &str, id: u32) -> bool {
        json.contains(&format!("{{\"id\":{id},\"power\""))
    }

    /// The `[x,y]` pairs listed under a top-level array key such as `blocked`.
    fn cells_under(json: &str, key: &str) -> Vec<(u16, u16)> {
        let needle = format!("\"{key}\":[");
        let start = json.find(&needle).expect("key present") + needle.len();
        let end = json[start..].find("]]").map_or(start, |e| start + e + 1);
        if json[start..].starts_with(']') {
            return Vec::new();
        }
        json[start..end]
            .trim_start_matches('[')
            .trim_end_matches(']')
            .split("],[")
            .map(|pair| {
                let (x, y) = pair.split_once(',').expect("x,y");
                (x.parse().expect("x"), y.parse().expect("y"))
            })
            .collect()
    }

    /// `remaining` of the deposit listed at `(x, y)`, if it is listed.
    fn deposit_remaining(json: &str, x: u16, y: u16) -> Option<u32> {
        let needle = format!("{{\"x\":{x},\"y\":{y},");
        let start = json.find(&needle)?;
        let object = &json[start..start + json[start..].find('}')?];
        let value = object.split("\"remaining\":").nth(1)?;
        value.parse().ok()
    }

    fn view_pos(sim: &rts_core::game::sim::Sim, id: EntityId) -> rts_core::vec::Vec2 {
        sim.views()
            .into_iter()
            .find(|v| v.id == id)
            .expect("entity alive")
            .pos
    }

    #[test]
    fn fog_sight_table_matches_the_brief() {
        use rts_core::game::sim::EntityKindView::{Building, Unit};
        for unit in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::AntiArmor,
            UnitKind::Capital,
        ] {
            assert_eq!(sight_radius(Unit(unit), 0), 7, "{unit:?}");
        }
        assert_eq!(sight_radius(Unit(UnitKind::Harvester), 0), 5);
        assert_eq!(sight_radius(Unit(UnitKind::Helicopter), 0), 10);
        assert_eq!(sight_radius(Building(BuildingKind::CommandCenter), 0), 9);
        for building in [
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
            BuildingKind::GunTurret,
            BuildingKind::AaTurret,
            BuildingKind::Wall,
            BuildingKind::ResearchLab,
            BuildingKind::AntimatterPlant,
            BuildingKind::VehicleFactory,
            BuildingKind::Airfield,
            BuildingKind::SupplyDepot,
            BuildingKind::Battery,
        ] {
            assert_eq!(sight_radius(Building(building), 0), 7, "{building:?}");
        }
    }

    #[test]
    fn fog_sight_always_exceeds_the_weapon_range_even_on_high_ground() {
        use rts_core::game::map::Ground;
        use rts_core::game::sim::EntityKindView::{Building, Unit};
        let mut kinds: Vec<_> = [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::AntiArmor,
            UnitKind::Helicopter,
            UnitKind::Capital,
        ]
        .into_iter()
        .map(|u| (Unit(u), Some(u.stats().attack.range)))
        .collect();
        kinds.push((
            Building(BuildingKind::GunTurret),
            BuildingKind::GunTurret.stats().attack.map(|a| a.range),
        ));
        kinds.push((
            Building(BuildingKind::AaTurret),
            BuildingKind::AaTurret.stats().attack.map(|a| a.range),
        ));
        for ground in Ground::ALL {
            let pct = ground.props().range_pct;
            for (kind, range) in &kinds {
                let reach = range.expect("armed").to_bits() * (100 + i64::from(pct)) / 100;
                let sight = sight_radius(*kind, pct) << 16;
                assert!(
                    sight > reach,
                    "{kind:?} on {ground:?}: sight {sight} must exceed reach {reach}"
                );
            }
        }
        // Highland's +25 percent pushes the Capital's 6 and the AA turret's 6 to 7.5.
        assert_eq!(sight_radius(Unit(UnitKind::Capital), 25), 9);
        assert_eq!(sight_radius(Building(BuildingKind::AaTurret), 25), 9);
        assert_eq!(sight_radius(Unit(UnitKind::Infantry), 25), 7);
    }

    #[test]
    fn fog_radius_fill_reveals_cells_within_sight_and_explored_persists() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        let mut fog = FogState::new(true);
        let home = hex::center(10, 12);
        fog.observe(W, H, &[(home, 7)]);
        let mask = fog.mask_string();
        assert_eq!(mask.len(), usize::from(W) * usize::from(H));
        for r in 0..H {
            for c in 0..W {
                let inside = (hex::center(c, r) - home).length_squared() <= Fixed::from_int(49);
                let want = if inside { b'2' } else { b'0' };
                assert_eq!(mask.as_bytes()[cell(c, r)], want, "cell ({c},{r})");
            }
        }
        // The edge is inclusive: (10,19) sits exactly 7 below the viewer, (10,20) is 8.
        assert_eq!(mask.as_bytes()[cell(10, 19)], b'2');
        assert_eq!(mask.as_bytes()[cell(10, 20)], b'0');
        let first_disc = mask.matches('2').count();
        // The viewer leaves: what it saw stays explored, the new ground is visible.
        let away = hex::center(34, 12);
        fog.observe(W, H, &[(away, 7)]);
        let mask = fog.mask_string();
        assert_eq!(mask.as_bytes()[cell(10, 12)], b'1');
        assert_eq!(mask.as_bytes()[cell(34, 12)], b'2');
        assert_eq!(mask.as_bytes()[cell(22, 0)], b'0');
        assert_eq!(
            mask.matches('1').count(),
            first_disc,
            "discs do not overlap"
        );
        // No viewer left at all: nothing is visible, everything seen stays explored.
        fog.observe(W, H, &[]);
        let mask = fog.mask_string();
        assert!(!mask.contains('2'));
        assert_eq!(mask.matches('1').count(), first_disc * 2);
    }

    #[test]
    fn fog_reset_forgets_explored_ground() {
        use rts_core::game::hex;
        let mut fog = FogState::new(true);
        fog.observe(W, H, &[(hex::center(10, 12), 7)]);
        fog.observe(W, H, &[]);
        assert!(fog.mask_string().contains('1'));
        // A restart replaces the fog, exactly as `main` does.
        fog = FogState::new(true);
        fog.observe(W, H, &[]);
        assert!(fog.mask_string().bytes().all(|b| b == b'0'));
    }

    #[test]
    fn fog_kill_switch_is_zero_off_or_false() {
        use std::ffi::OsStr;
        assert!(fog_enabled_from(None));
        for on in ["1", "", "on", "yes", "2"] {
            assert!(fog_enabled_from(Some(OsStr::new(on))), "{on:?}");
        }
        for off in ["0", "off", "OFF", "false", "False", " 0 "] {
            assert!(!fog_enabled_from(Some(OsStr::new(off))), "{off:?}");
        }
    }

    #[test]
    fn kestrel_fog_key_has_one_digit_per_cell_and_sits_before_shots() {
        use rts_core::game::kestrel::{CORE_NODE, HOME_CC};
        let sim = Scenario::KestrelReach.build(2026);
        let json = snapshot_json(&sim);
        let fog = fog_of(&json);
        assert_eq!(
            fog.len(),
            usize::from(sim.map().width()) * usize::from(sim.map().height())
        );
        assert!(
            fog.bytes().all(|b| matches!(b, b'0' | b'2')),
            "nothing is merely explored on the first frame"
        );
        assert_eq!(fog.as_bytes()[cell(HOME_CC.0, HOME_CC.1)], b'2');
        assert_eq!(fog.as_bytes()[cell(CORE_NODE.0, CORE_NODE.1)], b'0');
        assert!(json.ends_with(&format!(
            "\"supply_links\":[],\"fog\":\"{fog}\",\"shots\":[]}}"
        )));
        assert!(json_ok(&json));
    }

    #[test]
    fn kestrel_fog_omits_alien_entities_out_of_sight_and_keeps_every_human_one() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        use rts_core::game::kestrel::HOME_CC;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let json = snapshot_json(&sim);
        let mut aliens = 0;
        for v in sim.views() {
            let shown = has_entity(&json, v.id.0);
            if v.owner == PlayerId(0) {
                assert!(
                    shown && has_service(&json, v.id.0),
                    "human {} missing",
                    v.id.0
                );
            } else {
                aliens += 1;
                assert!(!shown, "alien {} leaked into entities", v.id.0);
                assert!(
                    !has_service(&json, v.id.0),
                    "alien {} leaked into services",
                    v.id.0
                );
            }
        }
        assert!(aliens > 15, "the alien base is out of sight at the start");
        // Their structures do not show through the placement grids either: a hidden
        // building's cell is reported as its bare ground.
        let blocked = cells_under(&json, "blocked");
        for v in sim.views().into_iter().filter(|v| v.owner != PlayerId(0)) {
            if let rts_core::game::sim::EntityKindView::Building(_) = v.kind {
                let (x, y) = hex::from_world(v.pos, W, H);
                let ground_blocks = !sim
                    .map()
                    .ground_at(i32::from(x), i32::from(y))
                    .props()
                    .buildable;
                assert_eq!(
                    blocked.contains(&(x, y)),
                    ground_blocks,
                    "hidden building at ({x},{y})"
                );
            }
        }
        // An alien squad that walks into sight of the Command Center appears; one
        // far out in the dark does not.
        let cc = hex::center(HOME_CC.0, HOME_CC.1);
        let near = sim.add_unit(
            PlayerId(1),
            UnitKind::Infantry,
            cc + Vec2::new(Fixed::from_int(3), Fixed::ZERO),
        );
        let far = sim.add_unit(PlayerId(1), UnitKind::Infantry, hex::center(30, 22));
        let json = snapshot_json(&sim);
        let seen = entity_object(&json, near.0);
        assert!(seen.contains("\"owner\":1") && !seen.contains("remembered"));
        assert!(has_service(&json, near.0));
        assert!(!has_entity(&json, far.0) && !has_service(&json, far.0));
        assert!(json_ok(&json));
    }

    #[test]
    fn a_seen_alien_building_is_remembered_until_its_cell_is_seen_empty() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let mut fog = FogState::new(true);
        let mut window = ShotWindow::new();
        let mut write = |sim: &rts_core::game::sim::Sim, fog: &mut FogState| {
            snapshot_json_with(sim, "[]", &mut window, fog)
        };
        // The east relay depot (id 25), scouted from five tiles west.
        let depot = EntityId(25);
        let depot_pos = view_pos(&sim, depot);
        let depot_cell = hex::from_world(depot_pos, W, H);
        let lookout = depot_pos - Vec2::new(Fixed::from_int(5), Fixed::ZERO);
        let scout = sim.add_unit(PlayerId(0), UnitKind::Infantry, lookout);
        let seen = write(&sim, &mut fog);
        let live = entity_object(&seen, depot.0);
        assert!(live.contains("\"kind\":\"SupplyDepot\"") && !live.contains("remembered"));
        assert!(has_service(&seen, depot.0));
        assert!(
            has_entity(&seen, 28),
            "the depot's anti-armour guard is in sight too"
        );

        // The scout falls: the depot leaves sight but stays as remembered intel,
        // exactly as last seen; the guard (a unit) is not remembered.
        sim.debug_set_hp(scout, Fixed::ZERO);
        sim.step(&[]);
        assert!(!sim.entity_alive(scout));
        let dark = write(&sim, &mut fog);
        let ghost = entity_object(&dark, depot.0);
        assert_eq!(
            ghost,
            format!("{},\"remembered\":true}}", &live[..live.len() - 1])
        );
        assert!(has_service(&dark, depot.0));
        assert!(!has_entity(&dark, 28));
        assert_eq!(
            fog_of(&dark).as_bytes()[cell(depot_cell.0, depot_cell.1)],
            b'1'
        );
        assert!(json_ok(&dark));

        // Destroyed while unseen: the player cannot know, so the ghost stays (and
        // its cell stays blocked) even after an alien squatter takes its free slot.
        sim.debug_set_hp(depot, Fixed::ZERO);
        sim.step(&[]);
        assert!(!sim.entity_alive(depot));
        let squatter = sim.add_unit(PlayerId(1), UnitKind::Infantry, hex::center(36, 22));
        assert_eq!(
            squatter, depot,
            "freed slots are recycled last-in first-out"
        );
        let unseen_death = write(&sim, &mut fog);
        assert_eq!(
            unseen_death
                .matches(&format!("{{\"id\":{},\"owner\"", depot.0))
                .count(),
            1
        );
        assert_eq!(entity_object(&unseen_death, depot.0), ghost);
        assert!(cells_under(&unseen_death, "blocked").contains(&depot_cell));
        assert!(json_ok(&unseen_death));

        // A second scout sees the empty cell: the ghost is dropped for good, and the
        // squatter far away in the dark stays hidden.
        let scout2 = sim.add_unit(PlayerId(0), UnitKind::Infantry, lookout);
        let seen_again = write(&sim, &mut fog);
        assert!(!seen_again.contains("remembered"));
        assert!(!has_entity(&seen_again, depot.0));
        sim.debug_set_hp(scout2, Fixed::ZERO);
        sim.step(&[]);
        let later = write(&sim, &mut fog);
        assert!(!has_entity(&later, depot.0));
        // The guard turret seen beside it is still remembered: only the gone depot went.
        assert!(entity_object(&later, 26).ends_with(",\"remembered\":true}"));

        // A restart forgets every remembered structure.
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let scout = sim.add_unit(PlayerId(0), UnitKind::Infantry, lookout);
        assert!(has_entity(&write(&sim, &mut fog), depot.0));
        // A restart replaces the fog, exactly as `main` does.
        fog = FogState::new(true);
        sim.debug_set_hp(scout, Fixed::ZERO);
        sim.step(&[]);
        let fresh = write(&sim, &mut fog);
        assert!(!fresh.contains("remembered") && !has_entity(&fresh, depot.0));
        assert!(
            !fog_of(&fresh).contains('1'),
            "explored ground is forgotten too"
        );
    }

    #[test]
    fn a_ghost_yields_its_id_when_a_shown_entity_reuses_the_slot() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        use rts_core::game::kestrel::HOME_CC;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let mut fog = FogState::new(true);
        let mut window = ShotWindow::new();
        let depot = EntityId(25);
        let lookout = view_pos(&sim, depot) - Vec2::new(Fixed::from_int(5), Fixed::ZERO);
        let scout = sim.add_unit(PlayerId(0), UnitKind::Infantry, lookout);
        snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        sim.debug_set_hp(scout, Fixed::ZERO);
        sim.step(&[]);
        sim.debug_set_hp(depot, Fixed::ZERO);
        sim.step(&[]);
        // A fresh rifle squad at home takes the depot's slot: ids must stay unique,
        // so the ghost gives way (an accepted, documented edge: see the task report).
        let recruit = sim.add_unit(
            PlayerId(0),
            UnitKind::Infantry,
            hex::center(HOME_CC.0, HOME_CC.1) + Vec2::new(Fixed::ONE, Fixed::ZERO),
        );
        assert_eq!(recruit, depot);
        let json = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        assert_eq!(
            json.matches(&format!("{{\"id\":{},\"owner\"", depot.0))
                .count(),
            1
        );
        let recruit_object = entity_object(&json, depot.0);
        assert!(recruit_object.contains("\"owner\":0") && !recruit_object.contains("remembered"));
        assert_eq!(
            json.matches(&format!("{{\"id\":{},\"power\"", depot.0))
                .count(),
            1
        );
    }

    #[test]
    fn fog_drops_shots_with_both_ends_in_the_dark_and_keeps_a_visible_end() {
        use rts_core::game::hex;
        use rts_core::game::kestrel::HOME_CC;
        let sim = Scenario::KestrelReach.build(2026);
        let cc = hex::center(HOME_CC.0, HOME_CC.1);
        let (dark_a, dark_b) = (hex::center(36, 20), hex::center(38, 21));
        let mut window = ShotWindow::new();
        window.record(
            sim.tick(),
            &[(dark_a, dark_b), (dark_a, cc), (cc, dark_b)],
            false,
        );
        let shots = parse_shots(&snap(&sim, &mut window));
        assert_eq!(shots.len(), 2, "{shots:?}");
        let dark = [
            dark_a.x.to_bits(),
            dark_a.y.to_bits(),
            dark_b.x.to_bits(),
            dark_b.y.to_bits(),
        ];
        assert!(shots.iter().all(|s| s[1..] != dark));
        // With the fog off every shot is drawn, exactly as before.
        let all = snapshot_json_with(&sim, "[]", &mut window, &mut FogState::new(false));
        assert_eq!(parse_shots(&all).len(), 3);
    }

    #[test]
    fn a_shot_at_a_viewer_killed_this_tick_stays_drawn_for_its_window() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let mut fog = FogState::new(true);
        let mut window = ShotWindow::new();
        let lonely_pos = hex::center(30, 22);
        let lonely = sim.add_unit(PlayerId(0), UnitKind::Infantry, lonely_pos);
        let killer = lonely_pos + Vec2::new(Fixed::from_int(9), Fixed::ZERO);
        snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        // The only viewer dies on the tick the shot lands; its cell was in sight a
        // frame ago, so the shot is drawn, and stays drawn while it is in the window.
        sim.debug_set_hp(lonely, Fixed::ZERO);
        sim.step(&[]);
        window.record(sim.tick(), &[(killer, lonely_pos)], false);
        let json = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        assert_eq!(parse_shots(&json).len(), 1);
        assert_eq!(fog_of(&json).as_bytes()[cell(30, 22)], b'1');
        sim.step(&[]);
        window.record(sim.tick(), &[(killer, hex::center(32, 23))], false);
        let json = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        assert_eq!(
            parse_shots(&json).len(),
            1,
            "latched shot kept, dark shot dropped"
        );
    }

    /// The non-player list the `main` loop built inline before
    /// `Scenario::host_commands` existed (503fd7c), kept verbatim as the oracle.
    fn pre_depth_loop_host_commands(
        sim: &rts_core::game::sim::Sim,
        scenario: Scenario,
    ) -> Vec<Command> {
        let mut commands = if sim.surveying() {
            sim.ai_commands(PlayerId(0))
        } else {
            Vec::new()
        };
        if sim.waves_survived() > 0 {
            commands.extend(sim.ai_commands(PlayerId(1)));
        }
        commands.extend(scenario.scripted_commands(sim));
        commands
    }

    #[test]
    fn host_commands_equal_the_list_the_bridge_loop_used_to_build() {
        let mut sim = Scenario::Survival.build(2026);
        sim.set_balance(rts_data::load_default());
        let first = Scenario::Survival.host_commands(&sim);
        assert!(
            sim.surveying() && !first.is_empty(),
            "the survey AI acts at tick 0"
        );
        assert_eq!(
            format!("{first:?}"),
            format!("{:?}", sim.ai_commands(PlayerId(0)))
        );
        // Every tick through Survival's survey and Kestrel's probe and wave one.
        // Narrowed by Task 19: under the Kestrel depth rules the alien AI now
        // runs from tick 0, so before wave one the list gains a prefix the old
        // loop never built. Survival stays exactly equal; Kestrel before wave
        // one must end with the old list, and every extra order is the alien
        // AI's (owner P1) and never moves a probe unit, which stay scripted.
        // From wave one on both lists are equal again. The awake alien takes
        // an undefended base before wave one, so in Kestrel the playtest AI
        // plays the human side (its orders are the player's, outside both
        // lists) to carry the run past wave one.
        for (scenario, ticks) in [(Scenario::Survival, 3000), (Scenario::KestrelReach, 5000)] {
            let mut sim = scenario.build(2026);
            sim.set_balance(rts_data::load_default());
            let mut extra = 0;
            for _ in 0..ticks {
                let ours = scenario.host_commands(&sim);
                let old = pre_depth_loop_host_commands(&sim, scenario);
                if scenario == Scenario::KestrelReach && sim.waves_survived() == 0 {
                    let split = ours.len().checked_sub(old.len()).expect("a prefix");
                    assert_eq!(
                        format!("{:?}", &ours[split..]),
                        format!("{old:?}"),
                        "{scenario:?} tick {}",
                        sim.tick()
                    );
                    let probe = rts_core::game::scenario::kestrel_probe_units(&sim);
                    for c in &ours[..split] {
                        assert!(format!("{c:?}").contains("owner: PlayerId(1)"), "{c:?}");
                        assert!(
                            !matches!(c, Command::Move { unit, .. } | Command::AttackMove { unit, .. }
                                if probe.contains(unit)),
                            "{c:?}"
                        );
                    }
                    extra += split;
                } else {
                    assert_eq!(
                        format!("{ours:?}"),
                        format!("{old:?}"),
                        "{scenario:?} tick {}",
                        sim.tick()
                    );
                }
                let mut all = ours;
                if scenario == Scenario::KestrelReach {
                    all.extend(sim.ai_commands(PlayerId(0)));
                }
                sim.step(&all);
            }
            if scenario == Scenario::KestrelReach {
                assert!(extra > 0, "the alien AI acted before wave one");
                assert!(
                    sim.waves_survived() > 0,
                    "the alien AI branch was exercised"
                );
            }
        }
    }

    #[test]
    fn survival_snapshots_are_byte_identical_to_the_pre_fog_bridge() {
        // Fingerprints taken from the bridge at 8fbb7c9, before the fog existed.
        let survival0 = snapshot_json(&Scenario::Survival.build(2026));
        assert_eq!(
            (survival0.len(), fnv1a(&survival0)),
            (17354, 0x61af_c445_3163_1aa1)
        );
        assert!(!survival0.contains("\"fog\"") && !survival0.contains("remembered"));
        let mut sim = Scenario::Survival.build(2026);
        sim.set_balance(rts_data::load_default());
        let mut window = ShotWindow::new();
        let mut fog = FogState::new(true);
        let mut last = String::new();
        for _ in 0..400 {
            step_into(&mut sim, &mut window);
            last = snapshot_json_with(&sim, &supply_links_json(&sim), &mut window, &mut fog);
        }
        assert_eq!((last.len(), fnv1a(&last)), (17356, 0x9aa3_dbac_e8aa_ccd9));
        assert!(json_ok(&survival0) && json_ok(&last));
    }

    #[test]
    fn fog_off_restores_the_pre_fog_kestrel_snapshot_exactly() {
        let all_visible = format!(
            ",\"fog\":\"{}\"",
            "2".repeat(usize::from(W) * usize::from(H))
        );
        let strip = |json: &str| {
            assert!(
                json.contains(&all_visible),
                "fog off still sends an all-visible mask"
            );
            // Task 13 appends `"stance"` to the player's own units, and Task
            // 14 `"queue":0` after it (no unit here has a queue, so no
            // `"route"`); both are additive, so they are stripped here like
            // the mask and every other byte must still match the pins below.
            // Task 17's `"depth"` Upgrades block is additive too, and goes the
            // same way, with Task 18's `"refinery_cost"` inside it and the
            // `"repair_cd":0` on the player's buildings (no repair runs here).
            let json = ["aggressive", "defensive", "hold"]
                .iter()
                .fold(json.replacen(&all_visible, "", 1), |acc, name| {
                    acc.replace(&format!(",\"stance\":\"{name}\""), "")
                })
                .replace(",\"queue\":0", "")
                .replace(",\"repair_cd\":0", "");
            let start = json.find(",\"depth\":{").expect("the depth block");
            let end = start + json[start..].find('}').expect("its end") + 1;
            format!("{}{}", &json[..start], &json[end..])
        };
        let sim = Scenario::KestrelReach.build(2026);
        let off = snapshot_json_with(
            &sim,
            &supply_links_json(&sim),
            &mut ShotWindow::new(),
            &mut FogState::new(false),
        );
        let off = strip(&off);
        // Re-pinned by the depth flag (Task 10): Kestrel's state hash now folds
        // in the depth marker, so only the snapshot's `hash` value changed
        // (one digit longer at tick 0); every other byte is as before. Was
        // (27265, 0x9a65_3391_e66d_8920) and (28516, 0x8f6a_ba55_027b_186e).
        //
        // Re-pinned by Task 11 (auto-acquire and leash): the per-entity depth
        // state (anchor, engagement) is now hashed, so the tick-0 `hash` value
        // changed again (same length); every other byte is identical. Was
        // (27266, 0x3fbb_4c7d_dbd5_fa57) and (28516, 0xee0f_54cf_6c06_7e37).
        //
        // Re-pinned by Task 13 (orders): each unit's stance and forced target
        // are now hashed, so the tick-0 `hash` value changed again (same
        // length); every other byte is identical (checked against the
        // committed fixtures with the hash masked). Was
        // (27266, 0xda83_524c_dd7e_782f) and (28515, 0x17d2_6a57_4400_cc38);
        // the mid-firefight hash is one digit longer, nothing else moved.
        //
        // Re-pinned by Task 14 (queued waypoints): each unit's queue is now
        // hashed (its length, 0 here), so the `hash` value changed again; the
        // additive `"queue":0` is stripped above and every other byte is
        // identical. Was (27266, 0x39f8_16c8_d6c2_8b72) and
        // (28516, 0x75a7_17ec_27d9_da19).
        //
        // Re-pinned by Task 16 (breach pathing): each unit's `breach_tried`
        // flag is now hashed (false everywhere here), so the `hash` value
        // changed again (one digit shorter at tick 0, two mid-firefight);
        // every other byte is identical (both old pins still match with that
        // one hash write removed). Was (27266, 0x8634_c753_bb2f_6ad4) and
        // (28516, 0x7d35_35b4_8d90_c906).
        //
        // Re-pinned by the P2 review fixes: each unit's `order_goal` (I2) and
        // `breach_failed` (M6) are now hashed under depth, so the `hash` value
        // changed again; every other byte is identical (both old pins still
        // match with those two hash writes removed). Was
        // (27265, 0x955e_5aec_e12d_4c8b) and (28514, 0x0d21_e3c2_ea31_b1a6).
        //
        // Re-pinned by Task 18 (depth economy): each entity's repair job and
        // cooldown are now hashed under depth, so the `hash` value changed
        // again (one digit shorter at tick 0 and mid-firefight); the additive
        // `"refinery_cost"` and `"repair_cd":0` are stripped above, and both
        // old pins still match with those two hash writes removed. Was
        // (27266, 0x3e21_0ade_88ab_a2db) and (28516, 0xa8bc_08e9_df4f_5ff5).
        //
        // Re-pinned by Task 19 (depth waves): the seeded doctrine order is
        // drawn from the depth rng at build, and the order, the cleared-wave
        // count and each unit's wave tag are now hashed under depth, so only
        // the `hash` value changed (one digit longer mid-firefight); every
        // other byte is identical (tick 0 checked against the regenerated
        // fixtures with the hash masked; the firefight steps with no
        // commands, so no AI, raid or wave runs in it). Was
        // (27265, 0xb9cd_e28f_e163_370f) and (28515, 0x7f04_e3f7_5668_c2de).
        assert_eq!((off.len(), fnv1a(&off)), (27265, 0x4bec_637c_99ae_933b));
        // Mid-firefight, with shots in the window, the same holds. Since Task 11
        // the fight also moves one alien rifle (id 20, about 5.8 from its hit
        // ally): it answers the hit and steps toward the human shooter, so its
        // position and the hash differ from the Task 10 pin (one byte shorter).
        let (mut sim, _, _) = kestrel_firefight();
        let mut window = ShotWindow::new();
        while sim.recent_attacks().is_empty() {
            step_into(&mut sim, &mut window);
        }
        for _ in 0..5 {
            step_into(&mut sim, &mut window);
        }
        let fight = snapshot_json_with(
            &sim,
            &supply_links_json(&sim),
            &mut window,
            &mut FogState::new(false),
        );
        let fight = strip(&fight);
        assert_eq!((fight.len(), fnv1a(&fight)), (28516, 0xd3c8_02cc_1bbc_0b45));
    }

    #[test]
    fn hidden_alien_buildings_do_not_show_through_the_construction_zone() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let humans: Vec<_> = sim
            .views()
            .into_iter()
            .filter(|v| v.owner == PlayerId(0))
            .collect();
        let free = |sim: &rts_core::game::sim::Sim, c: u16, r: u16| {
            sim.map()
                .tile(i32::from(c), i32::from(r))
                .is_some_and(|t| t.buildable)
        };
        let far_from_home = |p: rts_core::vec::Vec2| {
            humans
                .iter()
                .all(|h| (h.pos - p).length_squared() > Fixed::from_int(400))
        };
        // A forward human depot D, and a buildable cell T in its 10-tile construction
        // ring but outside the depot's 7-tile sight.
        let mut pick = None;
        'search: for dr in 0..H {
            for dc in 0..W {
                let d = hex::center(dc, dr);
                if !free(&sim, dc, dr) || !far_from_home(d) {
                    continue;
                }
                for tr in 0..H {
                    for tc in 0..W {
                        let gap = (hex::center(tc, tr) - d).length_squared();
                        if free(&sim, tc, tr)
                            && gap > Fixed::from_int(64)
                            && gap <= Fixed::from_int(100)
                            && far_from_home(hex::center(tc, tr))
                        {
                            pick = Some(((dc, dr), (tc, tr)));
                            break 'search;
                        }
                    }
                }
            }
        }
        let ((dc, dr), (tc, tr)) = pick.expect("a depot and ring cell exist");
        sim.add_building(PlayerId(0), BuildingKind::SupplyDepot, dc, dr);
        let turret = sim.add_building(PlayerId(1), BuildingKind::GunTurret, tc, tr);
        let fogged = snapshot_json(&sim);
        assert!(!has_entity(&fogged, turret.0));
        assert!(!cells_under(&fogged, "blocked").contains(&(tc, tr)));
        assert!(cells_under(&fogged, "construction_zone").contains(&(tc, tr)));
        // With the fog off the truth shows, as it always did.
        let open = snapshot_json_with(
            &sim,
            "[]",
            &mut ShotWindow::new(),
            &mut FogState::new(false),
        );
        assert!(has_entity(&open, turret.0));
        assert!(cells_under(&open, "blocked").contains(&(tc, tr)));
        assert!(!cells_under(&open, "construction_zone").contains(&(tc, tr)));
        // And the zone the fogged frame shows equals the zone with no turret at all.
        let mut bare = Scenario::KestrelReach.build(2026);
        bare.set_balance(rts_data::load_default());
        bare.add_building(PlayerId(0), BuildingKind::SupplyDepot, dc, dr);
        let bare_json = snapshot_json(&bare);
        assert_eq!(
            cells_under(&fogged, "construction_zone"),
            cells_under(&bare_json, "construction_zone")
        );
        assert_eq!(
            cells_under(&fogged, "blocked"),
            cells_under(&bare_json, "blocked")
        );
    }

    #[test]
    fn deposits_in_the_dark_report_the_last_known_amount() {
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        let mut fog = FogState::new(true);
        let mut window = ShotWindow::new();
        let first = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        let hidden = deposit_remaining(&first, 31, 17).expect("east ore listed");
        let home = deposit_remaining(&first, 7, 11).expect("home ore listed");
        // Somebody mines both: the home seam is in sight, the east one is not.
        sim.map_mut().mine(31, 17, 7);
        sim.map_mut().mine(7, 11, 5);
        let json = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        assert_eq!(deposit_remaining(&json, 31, 17), Some(hidden));
        assert_eq!(deposit_remaining(&json, 7, 11), Some(home - 5));
        // Even mined out, the dark seam stays listed as last known.
        sim.map_mut().mine(31, 17, u32::MAX);
        let json = snapshot_json_with(&sim, "[]", &mut window, &mut fog);
        assert_eq!(deposit_remaining(&json, 31, 17), Some(hidden));
        assert!(json_ok(&json));
        // With the fog off the truth shows.
        let open = snapshot_json_with(&sim, "[]", &mut window, &mut FogState::new(false));
        assert_eq!(deposit_remaining(&open, 31, 17), None);
    }

    #[test]
    fn fog_update_is_cheap_and_its_buffers_stop_growing() {
        use rts_core::fixed::Fixed;
        use rts_core::game::hex;
        use rts_core::vec::Vec2;
        let mut sim = Scenario::KestrelReach.build(2026);
        sim.set_balance(rts_data::load_default());
        // A large late-game army: 80 human viewers spread over the west half.
        for i in 0..80_u16 {
            let p = hex::center(2 + i % 20, 2 + (i / 20) * 5);
            sim.add_unit(
                PlayerId(0),
                UnitKind::Infantry,
                p + Vec2::new(Fixed::ZERO, Fixed::ZERO),
            );
        }
        let views = sim.views();
        let mut fog = FogState::new(true);
        fog.update(&sim, &views);
        let warm = fog.buffer_capacities();
        let started = std::time::Instant::now();
        for _ in 0..300 {
            fog.update(&sim, &views);
        }
        let elapsed = started.elapsed();
        assert_eq!(fog.buffer_capacities(), warm, "no per-write buffer growth");
        // Unoptimised test build on a loaded machine: 300 updates well under 3 s
        // (a release bridge does one per 33 ms frame).
        assert!(elapsed < std::time::Duration::from_secs(3), "{elapsed:?}");
    }
}
