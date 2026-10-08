//! Grounded Earthfront rules, isolated from legacy replay semantics.
use super::{
    BuildingKind, Command, Entity, EntityId, Fixed, Kind, PlayerId, Sim, UnitKind, Vec, Vec2,
};
use crate::game::hex;
use crate::game::map::{DepositKind, Ground};
use crate::game::tech_grid::{GridNode, RealityClass, Unlock, UnlockFamily};

/// Whether a depot-to-building supply route holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SupplyState {
    /// `supply_route` holds: the depot feeds this building.
    Supplied,
    /// A ready depot is in reach but walls or terrain cut the route.
    Severed,
}

/// One display link from a depot to a building it serves (or fails to reach).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SupplyLink {
    pub depot: EntityId,
    pub target: EntityId,
    pub state: SupplyState,
}

/// Authored scenario role, independent of a building's production or supply behavior.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ObjectiveRole {
    None,
    AlienRelay,
}

macro_rules! technology {
    ($id:expr, $name:expr, $era:expr, $branch:expr, $cost:expr, $work:expr, $deps:expr, $effect:expr) => {
        GridNode {
            id: $id,
            name: $name,
            era: $era,
            branch: $branch,
            step: 0,
            reality: if $era == 1 {
                RealityClass::Emerging
            } else {
                RealityClass::Achieved
            },
            money: $cost,
            energy: 0,
            labour: 0,
            duration: $work,
            prereqs: $deps,
            unlocks: &[Unlock {
                family: UnlockFamily::System,
                name: $effect,
            }],
        }
    };
}

/// Kestrel depth (Task 17): money the AI keeps in hand after an Upgrades
/// purchase, so a level never starves the next unit.
const AI_UPGRADE_RESERVE: i32 = 300;

/// Maximum raw ore awaiting processing at one refinery.
pub(super) const REFINERY_CAPACITY: u32 = 300;

const TECHNOLOGIES: [GridNode; 12] = [
    technology!(
        0,
        "Guided Anti-Armour",
        0,
        4,
        100,
        900,
        &[],
        "Anti-armour teams at barracks"
    ),
    technology!(
        1,
        "Armoured Vehicle Tooling",
        0,
        2,
        160,
        1200,
        &[],
        "Vehicle factory and battle tanks"
    ),
    technology!(
        2,
        "Rotary-Wing Integration",
        0,
        3,
        180,
        1500,
        &[1],
        "Airfield and helicopters"
    ),
    technology!(
        3,
        "Integrated Air Defence",
        0,
        5,
        100,
        900,
        &[0],
        "Radar-guided anti-air batteries"
    ),
    technology!(
        4,
        "Battery Buffering",
        0,
        1,
        100,
        900,
        &[],
        "2400 kJ battery storage; 40 kW discharge per battery"
    ),
    technology!(
        5,
        "Field Supply Networks",
        0,
        7,
        80,
        750,
        &[],
        "Depot supply radius increases from 5 to 7 tiles"
    ),
    technology!(
        6,
        "Precision Manufacturing",
        0,
        2,
        180,
        1500,
        &[1],
        "Powered production works 25% faster"
    ),
    technology!(
        7,
        "Robotic Workcells",
        1,
        2,
        250,
        2100,
        &[4, 6],
        "Production works 50% faster; advanced industrial era"
    ),
    technology!(
        8,
        "AI-Assisted Science",
        1,
        0,
        220,
        1800,
        &[6],
        "Double laboratory work at double active power demand"
    ),
    technology!(
        9,
        "Smart Grid Dispatch",
        1,
        1,
        140,
        1200,
        &[4],
        "Generators deliver 20% more usable power"
    ),
    technology!(
        10,
        "Autonomous Supply Scheduling",
        1,
        7,
        160,
        1500,
        &[5, 7],
        "Double depot output; same material cost per ammunition"
    ),
    technology!(
        11,
        "Industrial Resilience",
        1,
        6,
        200,
        1800,
        &[7, 8, 9],
        "Crew support rises from 60 to 90; no army damage multiplier"
    ),
];

/// Delivered services and local inventory totals for the player HUD.
#[derive(Clone, Copy, Debug, Default)]
pub struct EconomyView {
    /// Electrical generation in tactical kW.
    pub generation: u32,
    /// Requested operating power in tactical kW.
    pub demand: u32,
    /// Bounded electrical storage in kJ.
    pub stored_energy: u32,
    /// Installed energy storage capacity in kJ.
    pub storage_capacity: u32,
    /// Ore awaiting processing, excluding ore still in trucks.
    pub ore: u32,
    /// Ammunition stored in local supply anchors.
    pub ammunition: u32,
    /// Factories with a running production queue.
    pub active_factories: u32,
    /// Immediate research bottleneck for the UI.
    pub research_status: &'static str,
}

impl Sim {
    /// Activate the two-era industrial Earthfront ruleset for a new scenario.
    pub fn enable_earthfront(&mut self) {
        self.earthfront = true;
        // The Earth operation has finite metal ore, not exotic energy crystals.
        let deposits: Vec<_> = self
            .map
            .deposits()
            .map(|(x, y, d)| (x, y, d.remaining))
            .collect();
        for (x, y, remaining) in deposits {
            self.map.set_deposit(
                x,
                y,
                crate::game::map::Deposit {
                    kind: crate::game::map::DepositKind::Ore,
                    remaining,
                },
            );
        }
        for p in 0..self.civs.len() {
            let owner = PlayerId(u16::try_from(p).unwrap_or(0));
            self.set_starting_unlocks(
                owner,
                &[
                    BuildingKind::CommandCenter,
                    BuildingKind::PowerPlant,
                    BuildingKind::Refinery,
                    BuildingKind::Barracks,
                    BuildingKind::ResearchLab,
                    BuildingKind::SupplyDepot,
                    BuildingKind::GunTurret,
                    BuildingKind::Wall,
                ],
                &[UnitKind::Infantry, UnitKind::Harvester],
            );
            self.civs[p].energy = Fixed::ZERO;
            self.civs[p].labour = Fixed::from_int(60);
        }
    }

    /// Whether this operation uses industrial Earthfront rather than the legacy grid.
    #[must_use]
    pub const fn is_earthfront(&self) -> bool {
        self.earthfront
    }

    /// Research definition in the active scenario's versioned registry.
    #[must_use]
    pub fn technology(&self, id: u32) -> Option<&'static GridNode> {
        if self.earthfront {
            TECHNOLOGIES.get(id as usize)
        } else {
            crate::game::tech_grid::node(id)
        }
    }

    /// Implemented research definitions for the current ruleset.
    #[must_use]
    pub const fn technology_count(&self) -> usize {
        if self.earthfront {
            TECHNOLOGIES.len()
        } else {
            crate::game::tech_grid::TECH_MAX
        }
    }

    /// Production structure required by a unit in the grounded Earthfront ruleset.
    #[must_use]
    pub const fn earthfront_producer(kind: UnitKind) -> BuildingKind {
        match kind {
            UnitKind::Harvester => BuildingKind::Refinery,
            UnitKind::Tank | UnitKind::Capital => BuildingKind::VehicleFactory,
            UnitKind::Helicopter => BuildingKind::Airfield,
            UnitKind::Infantry | UnitKind::AntiArmor => BuildingKind::Barracks,
        }
    }

    fn operating_demand(&self, idx: usize) -> u32 {
        let e = &self.entities[idx];
        if !e.alive || !matches!(e.kind, Kind::Building(_)) {
            return 0;
        }
        if e.construction_remaining > 0 {
            return 5;
        }
        match e.kind {
            Kind::Building(BuildingKind::Refinery) => 20,
            Kind::Building(BuildingKind::Barracks) => 10,
            Kind::Building(BuildingKind::VehicleFactory) => {
                if e.build_queue.is_empty()
                    && self.prototype_factory(e.owner).map(|id| id.0 as usize) != Some(idx)
                {
                    5
                } else {
                    30
                }
            }
            Kind::Building(BuildingKind::Airfield) => {
                if e.build_queue.is_empty() {
                    5
                } else {
                    35
                }
            }
            Kind::Building(BuildingKind::ResearchLab) => {
                let c = &self.civs[usize::from(e.owner.0)];
                if c.active_research.is_none() {
                    5
                } else if c.researched_techs.get(8) {
                    60
                } else {
                    30
                }
            }
            Kind::Building(BuildingKind::GunTurret | BuildingKind::AaTurret) => 8,
            Kind::Building(BuildingKind::SupplyDepot) => 5,
            _ => 0,
        }
    }

    fn generation_for(&self, owner: PlayerId) -> u32 {
        let smart = self.civs[usize::from(owner.0)].researched_techs.get(9);
        self.entities
            .iter()
            .filter(|e| e.alive && e.owner == owner && e.construction_remaining == 0)
            .map(|e| match e.kind {
                Kind::Building(BuildingKind::PowerPlant) => {
                    let base = if smart { 96 } else { 80 };
                    base + self.river_bonus_kw(e)
                }
                Kind::Building(BuildingKind::CommandCenter) => 10,
                _ => 0,
            })
            .sum()
    }

    /// Extra kW (12) a power plant draws from a River or Ford hex beside it; Earthfront only.
    pub(super) fn river_bonus_kw(&self, e: &Entity) -> u32 {
        if !self.earthfront || !matches!(e.kind, Kind::Building(BuildingKind::PowerPlant)) {
            return 0;
        }
        let (x, y) = self.world_to_tile(e.pos);
        let wet = hex::neighbors(x, y)
            .iter()
            .any(|&(nx, ny)| matches!(self.map.ground_at(nx, ny), Ground::River | Ground::Ford));
        if wet {
            12
        } else {
            0
        }
    }

    /// Extra kW (0 or 12) the living entity `id` draws from a river or ford hex.
    /// Read-only; for HUD display.
    #[must_use]
    pub fn river_bonus_kw_of(&self, id: EntityId) -> u32 {
        self.entity(id)
            .filter(|e| e.alive)
            .map_or(0, |e| self.river_bonus_kw(e))
    }

    /// Ore-yield bonus percent (0 or 20) of the living refinery `id`.
    /// Read-only; for HUD display.
    #[must_use]
    pub fn ore_bonus_pct_of(&self, id: EntityId) -> u32 {
        if self
            .entity(id)
            .is_some_and(|e| e.alive && self.refinery_near_ore(e))
        {
            20
        } else {
            0
        }
    }

    /// Whether an ore deposit lies within one hex of this refinery; Earthfront only.
    pub(super) fn refinery_near_ore(&self, e: &Entity) -> bool {
        if !self.earthfront || !matches!(e.kind, Kind::Building(BuildingKind::Refinery)) {
            return false;
        }
        let tile = self.world_to_tile(e.pos);
        self.map
            .deposits()
            .any(|(dx, dy, d)| d.kind == DepositKind::Ore && hex::distance(tile, (dx, dy)) <= 1)
    }

    /// Read-only economic state, including the binding research constraint.
    #[must_use]
    pub fn economy_view(&self, owner: PlayerId) -> EconomyView {
        let mut view = EconomyView {
            generation: self.generation_for(owner),
            ..EconomyView::default()
        };
        for (i, e) in self
            .entities
            .iter()
            .enumerate()
            .filter(|(_, e)| e.alive && e.owner == owner)
        {
            view.demand += self.operating_demand(i);
            if e.construction_remaining == 0 && e.kind == Kind::Building(BuildingKind::Battery) {
                view.storage_capacity += 2400;
            }
            view.ore += e.ore_buffer;
            view.ammunition += e.supply_stock;
            view.active_factories += u32::from(!e.build_queue.is_empty());
        }
        view.stored_energy =
            u32::try_from(self.civs[usize::from(owner.0)].energy.to_int_floor()).unwrap_or(0);
        view.research_status = self.earthfront_research_status(owner);
        view
    }

    fn earthfront_research_status(&self, owner: PlayerId) -> &'static str {
        let Some((id, work)) = self.civs[usize::from(owner.0)].active_research else {
            return "Choose a capability";
        };
        if !self.has_research_lab(owner) {
            return "Paused: rebuild research laboratory";
        }
        if !self.entities.iter().any(|e| {
            e.alive
                && e.owner == owner
                && e.construction_remaining == 0
                && e.kind == Kind::Building(BuildingKind::ResearchLab)
                && e.power_fraction >= 500
        }) {
            return "Paused: insufficient laboratory power";
        }
        if id >= 6 && self.technology(id).is_some_and(|n| work <= n.duration / 3) {
            if self
                .prototype_factory(owner)
                .and_then(|id| self.entity(id))
                .is_none_or(|e| e.power_fraction < 500)
            {
                return "Paused: prototype needs powered vehicle factory";
            }
            return "Prototype: one vehicle factory reserved for validation";
        }
        "Theory and experiments: laboratory work"
    }

    /// Stable allocation: the oldest completed works hosts the current prototype.
    /// A destroyed works is replaced automatically; surviving factories keep their queues.
    #[must_use]
    pub fn prototype_factory(&self, owner: PlayerId) -> Option<EntityId> {
        if !self.prototype_reserves_factory(owner) {
            return None;
        }
        self.entities
            .iter()
            .enumerate()
            .find(|(_, e)| {
                e.alive
                    && e.owner == owner
                    && e.construction_remaining == 0
                    && e.kind == Kind::Building(BuildingKind::VehicleFactory)
            })
            .map(|(i, _)| EntityId(u32::try_from(i).unwrap_or(u32::MAX)))
    }

    #[must_use]
    pub const fn refinery_capacity(&self) -> u32 {
        REFINERY_CAPACITY
    }

    pub(super) fn prototype_reserves_factory(&self, owner: PlayerId) -> bool {
        self.earthfront
            && self.civs[usize::from(owner.0)]
                .active_research
                .is_some_and(|(id, work)| {
                    id >= 6 && self.technology(id).is_some_and(|n| work <= n.duration / 3)
                })
    }

    pub(super) fn earthfront_available_research(&self, owner: PlayerId) -> Vec<u32> {
        let c = &self.civs[usize::from(owner.0)];
        if self.surveying() || c.active_research.is_some() || !self.has_research_lab(owner) {
            return Vec::new();
        }
        TECHNOLOGIES
            .iter()
            .filter(|n| {
                !c.researched_techs.get(n.id)
                    && n.prereqs.iter().all(|&id| c.researched_techs.get(id))
                    && c.money >= Fixed::from_int(i32::try_from(n.money).unwrap_or(i32::MAX))
            })
            .map(|n| n.id)
            .collect()
    }

    pub(super) fn start_earthfront_research(&mut self, owner: PlayerId, id: u32) {
        if !self.earthfront_available_research(owner).contains(&id) {
            return;
        }
        if let Some(n) = self.technology(id) {
            let c = &mut self.civs[usize::from(owner.0)];
            c.money = c.money - Fixed::from_int(i32::try_from(n.money).unwrap_or(0));
            c.active_research = Some((id, n.duration));
        }
    }

    pub(super) fn unlock_earthfront_tech(&mut self, p: usize, id: u32) {
        let depth = self.is_depth();
        let c = &mut self.civs[p];
        match id {
            0 => c.unlocked_units |= 1 << UnitKind::AntiArmor.index(),
            1 => {
                c.unlocked_buildings |= 1 << BuildingKind::VehicleFactory.index();
                c.unlocked_units |= 1 << UnitKind::Tank.index();
            }
            2 => {
                c.unlocked_buildings |= 1 << BuildingKind::Airfield.index();
                c.unlocked_units |= 1 << UnitKind::Helicopter.index();
            }
            3 => c.unlocked_buildings |= 1 << BuildingKind::AaTurret.index(),
            4 => c.unlocked_buildings |= 1 << BuildingKind::Battery.index(),
            7 => {
                c.era = 1;
                // Kestrel depth (Task 17): the Capital is the era 1 late unit.
                if depth {
                    c.unlocked_units |= 1 << UnitKind::Capital.index();
                }
            }
            _ => {}
        }
    }

    pub(super) fn run_earthfront_research(&mut self) {
        for p in 0..self.civs.len() {
            let owner = PlayerId(u16::try_from(p).unwrap_or(0));
            let Some((id, remaining)) = self.civs[p].active_research else {
                continue;
            };
            if self.earthfront_research_status(owner).starts_with("Paused") {
                continue;
            }
            let prototype = self.prototype_factory(owner);
            let mut work = 0;
            if let Some(factory) = prototype {
                // Physical experiments have a serial throughput limit; AI cannot double it.
                let factory_power = self.entities[factory.0 as usize].power_fraction;
                if let Some(lab) = self.entities.iter_mut().find(|e| {
                    e.alive
                        && e.owner == owner
                        && e.construction_remaining == 0
                        && e.power_fraction >= 500
                        && e.kind == Kind::Building(BuildingKind::ResearchLab)
                }) {
                    lab.work_fraction += factory_power.min(lab.power_fraction);
                    work = lab.work_fraction / 1000;
                    lab.work_fraction %= 1000;
                }
            } else {
                let speed = if self.civs[p].researched_techs.get(8) {
                    2
                } else {
                    1
                };
                for e in &mut self.entities {
                    if e.alive
                        && e.owner == owner
                        && e.construction_remaining == 0
                        && e.power_fraction >= 500
                        && e.kind == Kind::Building(BuildingKind::ResearchLab)
                    {
                        e.work_fraction += e.power_fraction * speed;
                        work += e.work_fraction / 1000;
                        e.work_fraction %= 1000;
                    }
                }
                work = work.min(4);
                // Do not let parallel theory work skip the prototype boundary.
                if id >= 6 {
                    let boundary = self.technology(id).map_or(0, |n| n.duration / 3);
                    work = work.min(remaining.saturating_sub(boundary));
                }
            }
            if work >= remaining {
                self.civs[p].researched_techs.set(id);
                self.civs[p].active_research = None;
                self.unlock_earthfront_tech(p, id);
            } else {
                self.civs[p].active_research = Some((id, remaining - work));
            }
        }
    }

    /// Authoritative placement geometry; affordability and unlocks are separate.
    #[must_use]
    pub fn construction_allowed_at(&self, owner: PlayerId, x: u16, y: u16) -> bool {
        self.map
            .tile(i32::from(x), i32::from(y))
            .is_some_and(|t| t.buildable)
            && self.can_build_on(owner, x, y)
            && self.under_building_cap(x, y)
            && (!self.earthfront || self.earthfront_build_reachable(owner, x, y))
    }

    pub(super) fn earthfront_build_reachable(&self, owner: PlayerId, x: u16, y: u16) -> bool {
        let target = super::tile_center(x, y);
        self.entities.iter().any(|e| {
            e.alive
                && e.owner == owner
                && e.construction_remaining == 0
                && matches!(
                    e.kind,
                    Kind::Building(
                        BuildingKind::CommandCenter
                            | BuildingKind::SupplyDepot
                            | BuildingKind::Refinery
                    )
                )
                && (e.pos - target).length_squared() <= Fixed::from_int(100)
        })
    }

    /// A path-connected supply route; walls and terrain can sever ground distribution.
    fn supply_route(&self, from: Vec2, to: Vec2, radius: u32) -> bool {
        if (from - to).length_squared()
            > Fixed::from_int(i32::try_from(radius * radius).unwrap_or(0))
        {
            return false;
        }
        let start = self.world_to_tile(from);
        let Some(goal) = self.nearest_passable_tile(self.world_to_tile(to)) else {
            return false;
        };
        crate::game::path::find_path(&self.map, start, goal)
            .is_some_and(|route| route.len() <= radius as usize + 2)
    }

    /// A depot that can feed ammunition this beat: finished, powered and stocked.
    /// Shared by the supply beat and `earthfront_supply_links` so they cannot drift.
    const fn supply_depot_ready(e: &Entity) -> bool {
        e.alive && e.construction_remaining == 0 && e.power_fraction >= 500 && e.supply_stock > 0
    }

    /// Supply reach in tiles for `owner`: 7 with the supply technology (5), otherwise 5.
    fn supply_radius(&self, owner: PlayerId) -> u32 {
        if self.civs[usize::from(owner.0)].researched_techs.get(5) {
            7
        } else {
            5
        }
    }

    /// Read-only supply picture for display: for each finished `owner` building (ascending
    /// index), the first ready depot that serves it. A link is `Supplied` when
    /// `supply_route` holds and `Severed` when a ready depot is within reach but a wall or
    /// terrain cuts the route (the first such depot is named). Buildings with no ready depot
    /// in reach have no link. Mobile units are left out (their endpoints move) and so are walls
    /// (they hold no ammunition and are what cuts routes).
    /// Not hashed, never mutates, and costs one path search per depot tried per building,
    /// so callers should throttle it (the supply beat itself runs every 30 ticks).
    #[must_use]
    pub fn earthfront_supply_links(&self, owner: PlayerId) -> Vec<SupplyLink> {
        let mut links = Vec::new();
        if !self.earthfront {
            return links;
        }
        let radius = self.supply_radius(owner);
        let reach = Fixed::from_int(i32::try_from(radius * radius).unwrap_or(0));
        let depots: Vec<usize> = self
            .entities
            .iter()
            .enumerate()
            .filter(|(_, e)| e.owner == owner && Self::supply_depot_ready(e))
            .map(|(i, _)| i)
            .collect();
        if depots.is_empty() {
            return links;
        }
        for (idx, e) in self.entities.iter().enumerate() {
            if !e.alive
                || e.owner != owner
                || e.construction_remaining > 0
                || !matches!(e.kind, Kind::Building(b) if b != BuildingKind::Wall)
            {
                continue;
            }
            let mut severed: Option<usize> = None;
            let mut served: Option<usize> = None;
            for &d in &depots {
                if d == idx {
                    continue;
                }
                let pos = self.entities[d].pos;
                if (pos - e.pos).length_squared() > reach {
                    continue;
                }
                if self.supply_route(pos, e.pos, radius) {
                    served = Some(d);
                    break;
                }
                severed.get_or_insert(d);
            }
            let (depot, state) = match (served, severed) {
                (Some(d), _) => (d, SupplyState::Supplied),
                (None, Some(d)) => (d, SupplyState::Severed),
                (None, None) => continue,
            };
            links.push(SupplyLink {
                depot: EntityId(u32::try_from(depot).unwrap_or(u32::MAX)),
                target: EntityId(u32::try_from(idx).unwrap_or(u32::MAX)),
                state,
            });
        }
        links
    }

    #[allow(
        clippy::too_many_lines,
        reason = "ordered power allocation, processing and local ammunition transfers share one deterministic service boundary"
    )]
    pub(super) fn run_earthfront_services(&mut self) {
        if self.surveying() {
            return;
        }
        // Shared base grid: defence, extraction, industry, then science. Integer fair sharing per tier.
        for p in 0..self.civs.len() {
            let owner = PlayerId(u16::try_from(p).unwrap_or(0));
            let view = self.economy_view(owner);
            let batteries = view.storage_capacity / 2400;
            let generated = view.generation;
            let need = view.demand.saturating_sub(generated);
            let stored = self.civs[p].energy.min(Fixed::from_int(
                i32::try_from(view.storage_capacity).unwrap_or(0),
            ));
            let can_discharge =
                u32::try_from((stored * Fixed::from_int(30)).to_int_floor()).unwrap_or(0);
            let discharge = need.min(batteries * 40).min(can_discharge);
            let charge = generated.saturating_sub(view.demand).min(batteries * 40);
            self.civs[p].energy = (stored + Fixed::from_ratio(i64::from(charge) * 9, 300)
                - Fixed::from_ratio(i64::from(discharge), 30))
            .max(Fixed::ZERO)
            .min(Fixed::from_int(
                i32::try_from(view.storage_capacity).unwrap_or(0),
            ));
            let mut available = generated + discharge;
            for priority in 0..4 {
                let indices: Vec<usize> = self
                    .entities
                    .iter()
                    .enumerate()
                    .filter(|(_, e)| {
                        e.alive
                            && e.owner == owner
                            && matches!(e.kind, Kind::Building(_))
                            && match e.kind {
                                Kind::Building(BuildingKind::ResearchLab) => priority == 3,
                                Kind::Building(BuildingKind::Refinery) => priority == 1,
                                Kind::Building(
                                    BuildingKind::Barracks
                                    | BuildingKind::VehicleFactory
                                    | BuildingKind::Airfield,
                                ) => priority == 2,
                                _ => priority == 0,
                            }
                    })
                    .map(|(i, _)| i)
                    .collect();
                let requested: u32 = indices.iter().map(|&i| self.operating_demand(i)).sum();
                let served = requested.min(available);
                let fraction = (served * 1000).checked_div(requested).unwrap_or(1000);
                for i in indices {
                    self.entities[i].power_fraction = fraction;
                }
                available -= served;
            }
            self.civs[p].labour = Fixed::from_int(if self.civs[p].researched_techs.get(11) {
                90
            } else {
                60
            });
        }
        // Process exact batches: 5 ore -> 4 material. Never mine automatically beneath a building.
        // Refineries only process on the 30-tick beat, so the (whole-map deposit scan) near-ore
        // check is computed only then.
        if self.tick.is_multiple_of(30) {
            let near_ore: Vec<bool> = self
                .entities
                .iter()
                .map(|e| self.refinery_near_ore(e))
                .collect();
            for (e, near) in self.entities.iter_mut().zip(near_ore) {
                if !e.alive
                    || e.construction_remaining > 0
                    || e.kind != Kind::Building(BuildingKind::Refinery)
                {
                    continue;
                }
                // Refinery work accumulator is separate from its queued replacement-harvester work.
                if e.power_fraction >= 500 {
                    let ore = (e.ore_buffer / 5).min(1 + e.power_fraction / 500) * 5;
                    e.ore_buffer -= ore;
                    let c = &mut self.civs[usize::from(e.owner.0)];
                    let material = ore / 5 * 4;
                    let material = if near { material * 120 / 100 } else { material };
                    c.money = c.money + Fixed::from_int(i32::try_from(material).unwrap_or(0));
                }
            }
        }
        if !self.tick.is_multiple_of(30) {
            return;
        }
        // Local depots manufacture ammunition from material, with finite stores.
        for e in &mut self.entities {
            if !e.alive
                || e.construction_remaining > 0
                || e.power_fraction < 500
                || !matches!(
                    e.kind,
                    Kind::Building(BuildingKind::CommandCenter | BuildingKind::SupplyDepot)
                )
            {
                continue;
            }
            let c = &mut self.civs[usize::from(e.owner.0)];
            let batches = if c.researched_techs.get(10) { 2 } else { 1 };
            for _ in 0..batches {
                if e.supply_stock <= 228 && c.money >= Fixed::ONE {
                    c.money = c.money - Fixed::ONE;
                    e.supply_stock += 12;
                }
            }
        }
        let depots: Vec<usize> = self
            .entities
            .iter()
            .enumerate()
            .filter(|(_, e)| Self::supply_depot_ready(e))
            .map(|(i, _)| i)
            .collect();
        for idx in 0..self.entities.len() {
            let e = &self.entities[idx];
            if !e.alive || e.ammunition >= 90 || e.kind == Kind::Unit(UnitKind::Harvester) {
                continue;
            }
            let owner = e.owner;
            let position = e.pos;
            let radius = self.supply_radius(owner);
            for &d in &depots {
                if self.entities[d].owner == owner
                    && self.entities[d].supply_stock > 0
                    && self.supply_route(self.entities[d].pos, position, radius)
                {
                    let amount = (90 - self.entities[idx].ammunition)
                        .min(12)
                        .min(self.entities[d].supply_stock);
                    self.entities[d].supply_stock -= amount;
                    self.entities[idx].ammunition += amount;
                    break;
                }
            }
        }
    }

    /// Per-entity service data for inspection and HUD overlays.
    #[must_use]
    pub fn earthfront_entity_status(&self, id: EntityId) -> (u32, u32, u32, u32) {
        self.entity(id).map_or((0, 0, 0, 0), |e| {
            (e.power_fraction, e.ammunition, e.supply_stock, e.ore_buffer)
        })
    }

    /// Scenario-authored invasion relay. Ordinary depots cannot create expedition capacity.
    pub fn add_alien_relay(&mut self, owner: PlayerId, x: u16, y: u16) -> EntityId {
        let id = self.add_building(owner, BuildingKind::SupplyDepot, x, y);
        self.entities[id.0 as usize].objective_role = ObjectiveRole::AlienRelay;
        id
    }

    #[must_use]
    pub fn is_alien_relay(&self, id: EntityId) -> bool {
        self.entity(id)
            .is_some_and(|e| e.alive && e.objective_role == ObjectiveRole::AlienRelay)
    }

    /// Surviving relays, optionally limited to those currently receiving operating power.
    #[must_use]
    pub fn alien_relay_count(&self, owner: PlayerId, operational: bool) -> u32 {
        u32::try_from(
            self.entities
                .iter()
                .filter(|e| {
                    e.alive
                        && e.owner == owner
                        && e.objective_role == ObjectiveRole::AlienRelay
                        && (!operational
                            || (e.construction_remaining == 0 && e.power_fraction >= 500))
                })
                .count(),
        )
        .unwrap_or(0)
    }

    /// Maximum force supported by the next expedition, before the active-unit ceiling.
    #[must_use]
    pub fn next_expedition_size(&self) -> u32 {
        let Some(cfg) = self.waves else {
            return 0;
        };
        (6 + self.wave_count * 2).min(24) + 2 * self.alien_relay_count(cfg.attacker, true)
    }

    /// Announced doctrine, committed before the next wave rather than sampled on arrival.
    #[must_use]
    pub const fn incoming_doctrine(&self) -> &'static str {
        match self.earthfront_wave_doctrine {
            1 => "Anti-armour expedition",
            2 => "Siege against fortifications",
            3 => "Airfield interdiction",
            4 => "Industrial supply raid",
            _ => "Mixed expedition",
        }
    }

    pub(super) fn run_earthfront_waves(&mut self) {
        let Some(cfg) = self.waves else {
            return;
        };
        if self.surveying()
            || self.winner().is_some()
            || self.command_center_pos(cfg.attacker).is_none()
        {
            return;
        }
        let elapsed = self.tick - self.phase_started;
        // Lock the composition 45 seconds before arrival; never react to same-tick counters.
        if elapsed + 1350 >= cfg.first_delay
            && (elapsed + 1350 - cfg.first_delay).is_multiple_of(cfg.interval)
        {
            let tanks = self
                .entities
                .iter()
                .filter(|e| {
                    e.alive && e.owner == cfg.defender && e.kind == Kind::Unit(UnitKind::Tank)
                })
                .count();
            let walls = self.count_alive_buildings(cfg.defender, BuildingKind::Wall);
            // Kestrel depth (Task 16): three walls already call a siege.
            let siege = if self.is_depth() {
                walls >= 3
            } else {
                walls > 5
            };
            self.earthfront_wave_doctrine = if siege {
                2
            } else if tanks > 3 {
                1
            } else if self.enemy_has_air(cfg.attacker) {
                3
            } else if self.wave_count % 3 == 2 {
                4
            } else {
                0
            };
        }
        if elapsed < cfg.first_delay || !(elapsed - cfg.first_delay).is_multiple_of(cfg.interval) {
            return;
        }
        let w = self.wave_count;
        // Explicit expedition support: bounded force count, no free stat escalation.
        let budget = self
            .next_expedition_size()
            .min(80_u32.saturating_sub(self.supply_used(cfg.attacker)));
        let target = if matches!(self.earthfront_wave_doctrine, 3 | 4) {
            self.entities
                .iter()
                .find(|e| {
                    e.alive
                        && e.owner == cfg.defender
                        && e.kind
                            == Kind::Building(if self.earthfront_wave_doctrine == 3 {
                                BuildingKind::Airfield
                            } else {
                                BuildingKind::Refinery
                            })
                })
                .map(|e| e.pos)
        } else {
            None
        }
        .or_else(|| self.command_center_pos(cfg.defender));
        // Kestrel depth (Task 16): a siege wave leads with tanks (Explosive is
        // x1.5 against structures), its first quarter rounded up.
        let siege_lead = if self.is_depth() && self.earthfront_wave_doctrine == 2 {
            budget.div_ceil(4)
        } else {
            0
        };
        for i in 0..budget {
            let kind = if self.earthfront_wave_doctrine == 2 && w >= 3 && i == 0 {
                UnitKind::Capital
            } else if i < siege_lead {
                UnitKind::Tank
            } else if w >= 3 && i % 7 == 0 {
                UnitKind::Helicopter
            } else if self.earthfront_wave_doctrine == 1 && i % 3 == 0 {
                UnitKind::AntiArmor
            } else if w >= 1 && i % 4 == 0 {
                UnitKind::Tank
            } else {
                UnitKind::Infantry
            };
            let offset = Vec2::new(
                Fixed::from_ratio(i64::from(i % 3), 2),
                Fixed::from_ratio(i64::from(i % 5) - 2, 2),
            );
            let unit = self.add_unit(cfg.attacker, kind, cfg.spawn + offset);
            if let Some(target) = target {
                self.order_unit_to(unit.0 as usize, target, true);
            }
        }
        self.wave_count += 1;
    }

    #[allow(
        clippy::too_many_lines,
        reason = "one bounded deterministic plan reserves a shared material budget across construction, science and production"
    )]
    pub(super) fn earthfront_ai(&self, player: PlayerId) -> Vec<Command> {
        let mut commands = Vec::new();
        if self.surveying() {
            if player == self.human_civ {
                commands.push(Command::FoundBase {
                    owner: player,
                    x: 2,
                    y: self.map.height() / 2,
                });
            }
            return commands;
        }
        // Kestrel depth (Task 17): the army casts its abilities (the legacy
        // AI's rule, every 5th tick, gated by `depth_ability_allowed`).
        if self.is_depth() {
            self.ai_ability_casts(player, &mut commands);
        }
        if !self.tick.is_multiple_of(30) {
            return commands;
        }
        let Some(base) = self.command_center_pos(player) else {
            return commands;
        };
        let view = self.economy_view(player);
        let count = |kind| self.count_alive_buildings(player, kind);
        let pending_power = self.entities.iter().any(|e| {
            e.alive
                && e.owner == player
                && e.kind == Kind::Building(BuildingKind::PowerPlant)
                && e.construction_remaining > 0
        });
        let desired = if view.generation < view.demand + 35 && !pending_power {
            Some(BuildingKind::PowerPlant)
        } else if count(BuildingKind::Refinery) == 0 {
            Some(BuildingKind::Refinery)
        } else if count(BuildingKind::Barracks) == 0 {
            Some(BuildingKind::Barracks)
        } else if count(BuildingKind::ResearchLab) == 0 {
            Some(BuildingKind::ResearchLab)
        } else if count(BuildingKind::GunTurret) < 2 {
            Some(BuildingKind::GunTurret)
        } else if self.building_unlocked(player, BuildingKind::VehicleFactory)
            && count(BuildingKind::VehicleFactory) == 0
        {
            Some(BuildingKind::VehicleFactory)
        } else if count(BuildingKind::SupplyDepot) < 2 {
            Some(BuildingKind::SupplyDepot)
        } else if view.ore >= REFINERY_CAPACITY * 4 / 5 && count(BuildingKind::Refinery) < 2 {
            Some(BuildingKind::Refinery)
        } else if self.enemy_has_air(player)
            && self.building_unlocked(player, BuildingKind::AaTurret)
            && count(BuildingKind::AaTurret) < 2
        {
            Some(BuildingKind::AaTurret)
        } else {
            None
        };
        let mut budget = self.money(player);
        // Task 18: `depth_building_cost` is `building_cost` with depth off.
        let mut built = false;
        if let Some(kind) = desired.filter(|&k| {
            budget >= self.depth_building_cost(player, k) && self.building_unlocked(player, k)
        }) {
            if let Some((x, y)) = self.earthfront_ai_site(player, base) {
                commands.push(Command::Build {
                    owner: player,
                    kind,
                    x,
                    y,
                });
                budget = budget - self.depth_building_cost(player, kind);
                built = true;
            }
        }
        if let Some(tech_id) = self.suggested_research(player) {
            let price =
                Fixed::from_int(i32::try_from(TECHNOLOGIES[tech_id as usize].money).unwrap_or(0));
            if budget >= price {
                commands.push(Command::Research {
                    owner: player,
                    tech_id,
                });
                budget = budget - price;
            }
        }
        let army_target: u32 = if self.player_era(player) == 0 { 10 } else { 24 };
        let mut slots = army_target.saturating_sub(self.supply_used(player));
        for (i, e) in self.entities.iter().enumerate() {
            if !e.alive || e.owner != player {
                continue;
            }
            let entity = EntityId(u32::try_from(i).unwrap_or(0));
            if e.build_queue.is_empty() && e.construction_remaining == 0 && slots > 0 {
                let unit = match e.kind {
                    Kind::Building(BuildingKind::Barracks)
                        if self
                            .entities
                            .iter()
                            .filter(|u| {
                                u.alive
                                    && u.owner == player
                                    && matches!(
                                        u.kind,
                                        Kind::Unit(UnitKind::Infantry | UnitKind::AntiArmor)
                                    )
                            })
                            .count()
                            < 8 =>
                    {
                        Some(
                            if self.unit_unlocked(player, UnitKind::AntiArmor)
                                && (self.tick / 30).is_multiple_of(3)
                            {
                                UnitKind::AntiArmor
                            } else {
                                UnitKind::Infantry
                            },
                        )
                    }
                    Kind::Building(BuildingKind::VehicleFactory) => Some(UnitKind::Tank),
                    _ => None,
                };
                if let Some(kind) = unit.filter(|&k| {
                    self.unit_unlocked(player, k)
                        && budget >= self.unit_cost(k) + Fixed::from_int(250)
                }) {
                    commands.push(Command::Train {
                        owner: player,
                        barracks: entity,
                        kind,
                    });
                    budget = budget - self.unit_cost(kind);
                    slots -= 1;
                }
            }
            // Kestrel depth (Task 16): a unit breaking a wall (its forced
            // target) is left to it unless it runs low on ammunition.
            let breaching = self.is_depth() && e.dp.forced.is_some() && e.ammunition >= 15;
            if matches!(e.kind, Kind::Unit(k) if k != UnitKind::Harvester)
                && (e.move_target.is_none() || e.ammunition < 15)
                && !breaching
            {
                let target = if e.ammunition < 15 {
                    Some(base)
                } else if self.supply_used(player) >= 18
                    && self.player_era(player) > 0
                    && i % 4 != 0
                {
                    self.entities
                        .iter()
                        .filter(|other| {
                            other.alive
                                && other.owner != player
                                && other.objective_role == ObjectiveRole::AlienRelay
                        })
                        .min_by_key(|other| (other.pos - base).length_squared())
                        .or_else(|| {
                            self.entities.iter().find(|other| {
                                other.alive
                                    && other.owner != player
                                    && other.kind == Kind::Building(BuildingKind::CommandCenter)
                            })
                        })
                        .map(|other| other.pos)
                } else {
                    let direction = if player == self.human_civ { 1 } else { -1 };
                    Some(
                        base + Vec2::new(
                            Fixed::from_int(4 * direction),
                            Fixed::from_int(i32::try_from(i % 3).unwrap_or(0) - 1),
                        ),
                    )
                };
                if let Some(target) = target {
                    if e.ammunition < 15 {
                        commands.push(Command::Move {
                            owner: player,
                            unit: entity,
                            target,
                        });
                        continue;
                    }
                    commands.push(Command::AttackMove {
                        owner: player,
                        unit: entity,
                        target,
                    });
                }
            }
        }
        // Kestrel depth (Task 17): the money left after building, science and
        // training buys the cheapest Upgrades level (lowest track on a tie),
        // keeping a reserve; at most one level per AI pass.
        if self.is_depth() {
            let cheapest = (0..super::depth::UPGRADE_TRACKS)
                .filter_map(|t| self.upgrade_cost(player, t).map(|c| (c.to_bits(), t)))
                .min();
            if let Some((bits, track)) = cheapest {
                if budget >= Fixed::from_bits(bits) + Fixed::from_int(AI_UPGRADE_RESERVE) {
                    commands.push(Command::Ascend {
                        owner: player,
                        track,
                    });
                    budget = budget - Fixed::from_bits(bits);
                }
            }
            // Task 18: money still above the surplus line (Upgrades capped
            // for the era, nothing else to buy) goes on an extra refinery at
            // its escalating price, one at a time, so the AI does not bank.
            self.earthfront_ai_surplus(player, base, budget, built, &mut commands);
        }
        commands
    }

    /// The tile the Earthfront AI builds on next: the buildable tile nearest
    /// its base (within 8) that it may reach and that keeps clear of every
    /// structure. Ties go to the lower row, then the lower column.
    fn earthfront_ai_site(&self, player: PlayerId, base: Vec2) -> Option<(u16, u16)> {
        let mut candidates = Vec::new();
        for y in 0..self.map.height() {
            for x in 0..self.map.width() {
                let point = super::tile_center(x, y);
                let distance = (point - base).length_squared();
                if distance < Fixed::from_int(64)
                    && self
                        .map
                        .tile(i32::from(x), i32::from(y))
                        .is_some_and(|t| t.buildable)
                    && self.earthfront_build_reachable(player, x, y)
                    && self
                        .entities
                        .iter()
                        .filter(|e| e.alive && matches!(e.kind, Kind::Building(_)))
                        .all(|e| (e.pos - point).length_squared() >= Fixed::from_int(3))
                {
                    candidates.push((distance, y, x));
                }
            }
        }
        candidates.sort_unstable();
        candidates.first().map(|&(_, y, x)| (x, y))
    }

    /// Kestrel depth (Task 18): when the money left after this pass's orders
    /// is still above [`super::depth::AI_SURPLUS`], nothing else was placed
    /// this pass, no refinery is under construction and the AI owns fewer than
    /// [`super::depth::AI_SURPLUS_REFINERIES`], order one more refinery (its
    /// price rises by 50 with each).
    pub(super) fn earthfront_ai_surplus(
        &self,
        player: PlayerId,
        base: Vec2,
        budget: Fixed,
        built: bool,
        commands: &mut Vec<Command>,
    ) {
        let kind = BuildingKind::Refinery;
        let price = self.depth_building_cost(player, kind);
        let pending = self.entities.iter().any(|e| {
            e.alive
                && e.owner == player
                && e.kind == Kind::Building(kind)
                && e.construction_remaining > 0
        });
        if built
            || pending
            || self.count_alive_buildings(player, kind) >= super::depth::AI_SURPLUS_REFINERIES
            || budget < Fixed::from_int(super::depth::AI_SURPLUS)
            || budget < price
            || !self.building_unlocked(player, kind)
        {
            return;
        }
        if let Some((x, y)) = self.earthfront_ai_site(player, base) {
            commands.push(Command::Build {
                owner: player,
                kind,
                x,
                y,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::map::{Deposit, DepositKind, Ground, Map, Tile};

    const HUMAN: PlayerId = PlayerId(0);
    const ALIEN: PlayerId = PlayerId(1);

    fn operation() -> Sim {
        let mut sim = Sim::new(Map::new(40, 26), 17, Fixed::from_int(8000));
        sim.enable_earthfront();
        sim.set_survival_mode(true);
        sim.add_building(HUMAN, BuildingKind::CommandCenter, 2, 12);
        sim.add_building(ALIEN, BuildingKind::CommandCenter, 37, 12);
        sim
    }

    #[test]
    fn power_is_a_flow_and_storage_requires_a_battery() {
        let mut sim = operation();
        sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 12);
        for _ in 0..120 {
            sim.step(&[]);
        }
        assert_eq!(sim.energy(HUMAN), Fixed::ZERO);
        let view = sim.economy_view(HUMAN);
        assert_eq!(view.generation, 90);
        assert_eq!(view.storage_capacity, 0);
        sim.add_building(HUMAN, BuildingKind::Battery, 4, 12);
        for _ in 0..3000 {
            sim.step(&[]);
        }
        assert_eq!(sim.energy(HUMAN), Fixed::from_int(2400));
    }

    #[test]
    fn research_pauses_when_power_or_facility_is_lost() {
        let mut sim = operation();
        let generator = sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 12);
        let lab = sim.add_building(HUMAN, BuildingKind::ResearchLab, 4, 12);
        sim.step(&[Command::Research {
            owner: HUMAN,
            tech_id: 0,
        }]);
        let before = sim.research_state(HUMAN).1;
        sim.entities[generator.0 as usize].alive = false;
        for _ in 0..60 {
            sim.step(&[]);
        }
        assert_eq!(sim.research_state(HUMAN).1, before);
        assert!(sim.economy_view(HUMAN).research_status.contains("power"));
        sim.entities[generator.0 as usize].alive = true;
        sim.step(&[]);
        assert!(sim.research_state(HUMAN).1.unwrap().1 < before.unwrap().1);
        sim.entities[lab.0 as usize].alive = false;
        let retained = sim.research_state(HUMAN).1;
        sim.step(&[]);
        assert_eq!(sim.research_state(HUMAN).1, retained);
    }

    #[test]
    fn ore_must_be_delivered_and_processed_to_become_material() {
        let mut sim = operation();
        sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 12);
        let processor = sim.add_building(HUMAN, BuildingKind::Refinery, 4, 12);
        sim.map.set_deposit(
            4,
            12,
            Deposit {
                kind: DepositKind::Ore,
                remaining: 100,
            },
        );
        sim.civs[0].money = Fixed::ZERO;
        sim.step(&[]);
        assert_eq!(
            sim.money(HUMAN),
            Fixed::ZERO,
            "a refinery cannot mine its own tile for free"
        );
        assert_eq!(sim.map.deposit(4, 12).unwrap().remaining, 100);
        sim.entities[processor.0 as usize].ore_buffer = 15;
        for _ in 0..30 {
            sim.step(&[]);
        }
        // At second boundary 15 ore -> 12 material, +20 percent (14) because the deposit lies
        // within one hex of the refinery, then one material -> 12 supply rounds.
        assert_eq!(sim.entities[processor.0 as usize].ore_buffer, 0);
        assert_eq!(sim.money(HUMAN), Fixed::from_int(13));
        assert_eq!(sim.economy_view(HUMAN).ammunition, 12);
    }

    /// The `i`th hex neighbour of `(x, y)` as map coordinates.
    fn nbr(x: u16, y: u16, i: usize) -> (u16, u16) {
        let (nx, ny) = crate::game::hex::neighbors(x, y)[i];
        (u16::try_from(nx).unwrap(), u16::try_from(ny).unwrap())
    }

    fn plant_sim(earthfront: bool) -> (Sim, u16, u16) {
        let mut s = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
        if earthfront {
            s.enable_earthfront();
        }
        s.add_building(HUMAN, BuildingKind::PowerPlant, 6, 6);
        (s, 6, 6)
    }

    #[test]
    fn power_plant_beside_river_generates_twelve_more() {
        let (mut s, x, y) = plant_sim(true);
        let before = s.generation_for(HUMAN);
        let (nx, ny) = nbr(x, y, 0);
        s.map_mut().set_ground(nx, ny, Ground::River);
        assert_eq!(s.generation_for(HUMAN), before + 12);
    }

    #[test]
    fn ford_neighbour_also_counts_and_dry_neighbours_do_not() {
        let (mut s, x, y) = plant_sim(true);
        let before = s.generation_for(HUMAN);
        let (nx, ny) = nbr(x, y, 1);
        s.map_mut().set_ground(nx, ny, Ground::Flats);
        assert_eq!(s.generation_for(HUMAN), before);
        s.map_mut().set_ground(nx, ny, Ground::Ford);
        assert_eq!(s.generation_for(HUMAN), before + 12);
    }

    #[test]
    fn power_bonus_is_zero_off_earthfront() {
        let (mut s, x, y) = plant_sim(false);
        let before = s.generation_for(HUMAN);
        let (nx, ny) = nbr(x, y, 0);
        s.map_mut().set_ground(nx, ny, Ground::River);
        assert_eq!(s.generation_for(HUMAN), before);
    }

    fn refinery_money_after_a_second(deposit_at: Option<(u16, u16)>, ore: u32) -> i64 {
        refinery_money_with(deposit_at, DepositKind::Ore, ore)
    }

    fn refinery_money_with(deposit_at: Option<(u16, u16)>, kind: DepositKind, ore: u32) -> i64 {
        let mut sim = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
        sim.enable_earthfront();
        sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 12);
        let r = sim.add_building(HUMAN, BuildingKind::Refinery, 8, 8);
        if let Some((dx, dy)) = deposit_at {
            sim.map_mut().set_deposit(
                dx,
                dy,
                Deposit {
                    kind,
                    remaining: 100,
                },
            );
        }
        sim.entities[r.0 as usize].ore_buffer = ore;
        sim.civs[0].money = Fixed::ZERO;
        for _ in 0..30 {
            sim.step(&[]);
        }
        sim.money(HUMAN).to_bits()
    }

    #[test]
    fn refinery_next_to_a_deposit_yields_twenty_percent_more() {
        let one = Fixed::from_int(1).to_bits();
        let (nx, ny) = nbr(8, 8, 2);
        let near_cell = Some((nx, ny));
        // 15 ore -> 12 material at 100 percent, 14 (12 * 120 / 100, truncated) beside ore.
        assert_eq!(refinery_money_after_a_second(Some((1, 1)), 15), 12 * one);
        assert_eq!(refinery_money_after_a_second(near_cell, 15), 14 * one);
    }

    #[test]
    fn alloy_beside_a_refinery_gives_no_ore_bonus() {
        // Alloy is decorative in Earthfront (never mined), so only an Ore deposit
        // within one hex earns the +20 percent.
        let one = Fixed::from_int(1).to_bits();
        let near_cell = Some(nbr(8, 8, 2));
        assert_eq!(
            refinery_money_with(Some((1, 1)), DepositKind::Alloy, 15),
            12 * one
        );
        assert_eq!(
            refinery_money_with(near_cell, DepositKind::Alloy, 15),
            12 * one
        );
        assert_eq!(
            refinery_money_with(near_cell, DepositKind::Ore, 15),
            14 * one
        );
    }

    #[test]
    fn refinery_ore_bonus_is_zero_off_earthfront() {
        let mut sim = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
        let r = sim.add_building(HUMAN, BuildingKind::Refinery, 8, 8);
        let (nx, ny) = nbr(8, 8, 2);
        sim.map_mut().set_deposit(
            nx,
            ny,
            Deposit {
                kind: DepositKind::Ore,
                remaining: 100,
            },
        );
        let e = sim.entities[r.0 as usize].clone();
        assert!(!sim.refinery_near_ore(&e));
    }

    #[test]
    fn refinery_near_ore_requires_a_deposit_within_one_hex() {
        let mut sim = Sim::new(Map::new(16, 16), 1, Fixed::ZERO);
        sim.enable_earthfront();
        let r = sim.add_building(HUMAN, BuildingKind::Refinery, 8, 8);
        let e = sim.entities[r.0 as usize].clone();
        assert!(!sim.refinery_near_ore(&e));
        let (nx, ny) = nbr(8, 8, 2);
        let ore = Deposit {
            kind: DepositKind::Ore,
            remaining: 100,
        };
        sim.map_mut().set_deposit(nx, ny, ore);
        assert!(sim.refinery_near_ore(&e));
    }

    #[test]
    fn tank_production_requires_its_factory_and_power() {
        let mut sim = operation();
        sim.civs[0].researched_techs.set(1);
        sim.unlock_earthfront_tech(0, 1);
        let barracks = sim.add_building(HUMAN, BuildingKind::Barracks, 4, 10);
        let factory = sim.add_building(HUMAN, BuildingKind::VehicleFactory, 5, 10);
        sim.step(&[Command::Train {
            owner: HUMAN,
            barracks,
            kind: UnitKind::Tank,
        }]);
        assert!(sim.production_status(barracks).is_none());
        sim.step(&[Command::Train {
            owner: HUMAN,
            barracks: factory,
            kind: UnitKind::Tank,
        }]);
        // Defence and infantry industry exhaust the command centre's emergency output.
        assert_eq!(sim.production_status(factory).unwrap().progress, 0);
        sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 10);
        for _ in 0..300 {
            sim.step(&[]);
        }
        assert!(sim
            .views()
            .iter()
            .any(|e| e.owner == HUMAN
                && e.kind == super::super::EntityKindView::Unit(UnitKind::Tank)));
    }

    #[test]
    fn ammunition_exhaustion_stops_fire_and_depots_restore_it() {
        let mut sim = operation();
        let gun = sim.add_unit(HUMAN, UnitKind::Infantry, super::super::tile_center(15, 10));
        let target = sim.add_unit(ALIEN, UnitKind::Tank, super::super::tile_center(16, 10));
        sim.entities[gun.0 as usize].ammunition = 0;
        sim.entities[target.0 as usize].ammunition = 0;
        let hp = sim.entities[target.0 as usize].hp;
        for _ in 0..30 {
            sim.step(&[]);
        }
        assert_eq!(sim.entities[target.0 as usize].hp, hp);
        let depot = sim.add_building(HUMAN, BuildingKind::SupplyDepot, 14, 10);
        sim.entities[depot.0 as usize].supply_stock = 24;
        sim.step(&[]);
        assert!(sim.entities[gun.0 as usize].ammunition > 0);
        assert!(sim.entities[target.0 as usize].hp < hp);
    }

    #[test]
    fn walls_sever_ground_supply_routes() {
        let mut sim = operation();
        let from = super::super::tile_center(10, 10);
        let to = super::super::tile_center(13, 10);
        assert!(sim.supply_route(from, to, 7));
        for y in 0..26 {
            sim.map.set_tile(12, y, Tile::BLOCKED);
        }
        assert!(!sim.supply_route(from, to, 7));
    }

    /// A depot at (10,10) ready to serve (stocked and powered) plus a barracks at `tx`.
    fn supply_fixture(tx: u16) -> (Sim, EntityId, EntityId) {
        let mut sim = operation();
        let depot = sim.add_building(HUMAN, BuildingKind::SupplyDepot, 10, 10);
        sim.entities[depot.0 as usize].supply_stock = 24;
        sim.entities[depot.0 as usize].power_fraction = 1000;
        let target = sim.add_building(HUMAN, BuildingKind::Barracks, tx, 10);
        (sim, depot, target)
    }

    fn links_to(sim: &Sim, target: EntityId) -> Vec<SupplyLink> {
        sim.earthfront_supply_links(HUMAN)
            .into_iter()
            .filter(|l| l.target == target)
            .collect()
    }

    #[test]
    fn supply_links_report_a_supplied_building() {
        let (sim, depot, target) = supply_fixture(13);
        assert_eq!(
            links_to(&sim, target),
            [SupplyLink {
                depot,
                target,
                state: SupplyState::Supplied
            }]
        );
        // The depot never links to itself and the output is deterministic.
        assert!(sim
            .earthfront_supply_links(HUMAN)
            .iter()
            .all(|l| l.target != depot || l.depot != depot));
        assert_eq!(
            sim.earthfront_supply_links(HUMAN),
            sim.earthfront_supply_links(HUMAN)
        );
        // Other owners and non-Earthfront sims have no links.
        assert!(sim.earthfront_supply_links(ALIEN).is_empty());
    }

    #[test]
    fn supply_links_skip_walls() {
        let (mut sim, _, _) = supply_fixture(13);
        let wall = sim.add_building(HUMAN, BuildingKind::Wall, 12, 10);
        assert!(links_to(&sim, wall).is_empty());
    }

    #[test]
    fn supply_links_turn_severed_when_walls_cut_the_route() {
        let (mut sim, depot, target) = supply_fixture(13);
        for y in 0..26 {
            sim.map.set_tile(12, y, Tile::BLOCKED);
        }
        assert_eq!(
            links_to(&sim, target),
            [SupplyLink {
                depot,
                target,
                state: SupplyState::Severed
            }]
        );
    }

    #[test]
    fn supply_links_need_a_ready_depot() {
        let (mut sim, depot, target) = supply_fixture(13);
        sim.entities[depot.0 as usize].supply_stock = 0;
        assert!(links_to(&sim, target).is_empty());
        sim.entities[depot.0 as usize].supply_stock = 24;
        sim.entities[depot.0 as usize].power_fraction = 499;
        assert!(links_to(&sim, target).is_empty());
        sim.entities[depot.0 as usize].power_fraction = 500;
        assert_eq!(links_to(&sim, target).len(), 1);
        sim.entities[depot.0 as usize].construction_remaining = 5;
        assert!(links_to(&sim, target).is_empty());
        sim.entities[depot.0 as usize].construction_remaining = 0;
        sim.entities[depot.0 as usize].alive = false;
        assert!(links_to(&sim, target).is_empty());
    }

    #[test]
    fn supply_links_radius_is_five_and_seven_with_the_supply_tech() {
        // Hex columns are 0.75 apart in world units: 7 columns is 5.25 away, outside
        // radius 5 but inside radius 7.
        let (mut sim, _, target) = supply_fixture(17);
        assert!(links_to(&sim, target).is_empty());
        sim.civs[0].researched_techs.set(5);
        assert_eq!(links_to(&sim, target).len(), 1);
        // Six columns (4.5 away) is inside the base radius.
        let (sim, _, target) = supply_fixture(16);
        assert_eq!(links_to(&sim, target).len(), 1);
        // Ten columns (7.5 away) is out of reach even with the technology.
        let (mut sim, _, target) = supply_fixture(20);
        sim.civs[0].researched_techs.set(5);
        assert!(links_to(&sim, target).is_empty());
    }

    #[test]
    fn supply_links_agree_with_the_supply_beat() {
        // Pins the shared predicate: Supplied exactly when the beat refills ammunition.
        for (walled, expect_refill) in [(false, true), (true, false)] {
            let (mut sim, _, target) = supply_fixture(13);
            if walled {
                for y in 0..26 {
                    sim.map.set_tile(12, y, Tile::BLOCKED);
                }
            }
            sim.entities[target.0 as usize].ammunition = 0;
            let state = links_to(&sim, target)[0].state;
            assert_eq!(state == SupplyState::Supplied, expect_refill);
            for _ in 0..61 {
                sim.step(&[]);
            }
            assert_eq!(
                sim.entities[target.0 as usize].ammunition > 0,
                expect_refill,
                "walled={walled}"
            );
        }
    }

    #[test]
    fn prototypes_compete_with_factory_production() {
        let mut sim = operation();
        sim.add_building(HUMAN, BuildingKind::PowerPlant, 3, 10);
        sim.add_building(HUMAN, BuildingKind::ResearchLab, 4, 10);
        let factory = sim.add_building(HUMAN, BuildingKind::VehicleFactory, 5, 10);
        sim.entities[factory.0 as usize]
            .build_queue
            .push(UnitKind::Tank);
        sim.civs[0].active_research = Some((6, 400));
        sim.step(&[]);
        assert_eq!(sim.production_status(factory).unwrap().progress, 0);
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 399)));
        sim.entities[factory.0 as usize].alive = false;
        sim.step(&[]);
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 399)));
        assert!(sim
            .economy_view(HUMAN)
            .research_status
            .contains("prototype"));
    }

    #[test]
    fn full_refineries_keep_ore_in_trucks_and_accept_partial_deliveries() {
        let mut sim = operation();
        let refinery = sim.add_building(HUMAN, BuildingKind::Refinery, 4, 12);
        let truck = sim.add_unit(HUMAN, UnitKind::Harvester, super::super::tile_center(5, 12));
        sim.entities[refinery.0 as usize].ore_buffer = REFINERY_CAPACITY - 5;
        sim.entities[truck.0 as usize].cargo = 20;
        sim.entities[truck.0 as usize].harvest_returning = true;
        sim.run_harvesters();
        assert_eq!(
            sim.entities[refinery.0 as usize].ore_buffer,
            REFINERY_CAPACITY
        );
        assert_eq!(sim.entities[truck.0 as usize].cargo, 15);
        assert!(sim.entities[truck.0 as usize].harvest_returning);
        sim.run_harvesters();
        assert_eq!(sim.entities[truck.0 as usize].cargo, 15);
        sim.entities[refinery.0 as usize].ore_buffer -= 15;
        sim.run_harvesters();
        assert_eq!(
            sim.entities[refinery.0 as usize].ore_buffer,
            REFINERY_CAPACITY
        );
        assert_eq!(sim.entities[truck.0 as usize].cargo, 0);
        assert!(!sim.entities[truck.0 as usize].harvest_returning);
    }

    #[test]
    fn trucks_deliver_to_available_processor_and_survive_its_loss_with_cargo() {
        let mut sim = operation();
        let full = sim.add_building(HUMAN, BuildingKind::Refinery, 4, 12);
        let available = sim.add_building(HUMAN, BuildingKind::Refinery, 7, 12);
        let truck = sim.add_unit(HUMAN, UnitKind::Harvester, super::super::tile_center(6, 12));
        sim.entities[full.0 as usize].ore_buffer = REFINERY_CAPACITY;
        sim.entities[truck.0 as usize].cargo = 20;
        sim.entities[truck.0 as usize].harvest_returning = true;
        sim.entities[available.0 as usize].alive = false;
        sim.run_harvesters();
        assert_eq!(sim.entities[truck.0 as usize].cargo, 20);
        sim.entities[available.0 as usize].alive = true;
        sim.run_harvesters();
        assert_eq!(sim.entities[available.0 as usize].ore_buffer, 20);
        assert_eq!(sim.entities[truck.0 as usize].cargo, 0);
    }

    #[test]
    fn prototype_reserves_only_one_factory_and_reassigns_after_destruction() {
        let mut sim = operation();
        let lab = sim.add_building(HUMAN, BuildingKind::ResearchLab, 4, 10);
        let first = sim.add_building(HUMAN, BuildingKind::VehicleFactory, 5, 10);
        let second = sim.add_building(HUMAN, BuildingKind::VehicleFactory, 7, 10);
        for id in [first, second, lab] {
            sim.entities[id.0 as usize].power_fraction = 1000;
        }
        for id in [first, second] {
            sim.entities[id.0 as usize].build_queue.push(UnitKind::Tank);
        }
        sim.civs[0].active_research = Some((6, 400));
        assert_eq!(sim.prototype_factory(HUMAN), Some(first));
        sim.run_production();
        assert_eq!(sim.production_status(first).unwrap().progress, 0);
        assert_eq!(sim.production_status(second).unwrap().progress, 1);
        sim.entities[first.0 as usize].alive = false;
        assert_eq!(sim.prototype_factory(HUMAN), Some(second));
        sim.run_production();
        assert_eq!(sim.production_status(second).unwrap().progress, 1);
        sim.run_earthfront_research();
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 399)));
        sim.civs[0].active_research = None;
        sim.run_production();
        assert_eq!(sim.production_status(second).unwrap().progress, 2);
    }

    #[test]
    fn ai_science_accelerates_theory_but_cannot_skip_or_accelerate_prototypes() {
        let mut sim = operation();
        for x in [3, 4] {
            let lab = sim.add_building(HUMAN, BuildingKind::ResearchLab, x, 10);
            sim.entities[lab.0 as usize].power_fraction = 1000;
        }
        let factory = sim.add_building(HUMAN, BuildingKind::VehicleFactory, 5, 10);
        sim.entities[factory.0 as usize].power_fraction = 1000;
        sim.civs[0].researched_techs.set(8);
        sim.civs[0].active_research = Some((6, 505));
        sim.run_earthfront_research();
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 501)));
        sim.run_earthfront_research();
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 500)));
        sim.run_earthfront_research();
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 499)));
        sim.entities[factory.0 as usize].power_fraction = 0;
        sim.run_earthfront_research();
        assert_eq!(sim.research_state(HUMAN).1, Some((6, 499)));
    }

    #[test]
    fn relay_power_and_destruction_change_actual_wave_strength() {
        let mut sim = operation();
        sim.set_waves(super::super::WaveConfig {
            first_delay: 0,
            interval: 300,
            base_size: 6,
            growth: 2,
            spawn: super::super::tile_center(35, 12),
            unit: UnitKind::Infantry,
            attacker: ALIEN,
            defender: HUMAN,
            escalate: true,
        });
        let first = sim.add_alien_relay(ALIEN, 25, 6);
        let second = sim.add_alien_relay(ALIEN, 25, 18);
        assert_eq!(sim.next_expedition_size(), 10);
        let mut disabled = sim.clone();
        disabled.entities[first.0 as usize].power_fraction = 0;
        disabled.entities[second.0 as usize].power_fraction = 0;
        assert_eq!(disabled.alien_relay_count(ALIEN, false), 2);
        assert_eq!(disabled.alien_relay_count(ALIEN, true), 0);
        sim.run_earthfront_waves();
        disabled.run_earthfront_waves();
        assert_eq!(sim.unit_count(ALIEN), 10);
        assert_eq!(disabled.unit_count(ALIEN), 6);
        sim.entities[first.0 as usize].hp = Fixed::ZERO;
        sim.clear_dead();
        assert_eq!(sim.alien_relay_count(ALIEN, false), 1);
        assert_eq!(sim.next_expedition_size(), 10); // wave two: eight base + two relay
        let depot = sim.add_building(ALIEN, BuildingKind::SupplyDepot, 25, 6);
        assert_eq!(depot, first, "exercise entity slot recycling");
        assert!(!sim.is_alien_relay(depot));
        assert_eq!(sim.alien_relay_count(ALIEN, false), 1);
    }

    #[test]
    fn relay_role_is_hashed_and_never_makes_the_core_invulnerable() {
        let mut sim = operation();
        let relay = sim.add_alien_relay(ALIEN, 25, 6);
        let mut ordinary = sim.clone();
        ordinary.entities[relay.0 as usize].objective_role = ObjectiveRole::None;
        assert_ne!(sim.state_hash(), ordinary.state_hash());
        let core = sim
            .entities
            .iter_mut()
            .find(|e| e.owner == ALIEN && e.kind == Kind::Building(BuildingKind::CommandCenter))
            .unwrap();
        core.hp = Fixed::ZERO;
        sim.clear_dead();
        assert_eq!(sim.alien_relay_count(ALIEN, false), 1);
        assert_eq!(sim.winner(), Some(HUMAN));
    }

    #[test]
    fn future_tech_and_magic_abilities_are_not_in_the_slice() {
        let mut sim = operation();
        sim.add_building(HUMAN, BuildingKind::ResearchLab, 3, 10);
        sim.step(&[Command::Research {
            owner: HUMAN,
            tech_id: 105,
        }]);
        assert_eq!(sim.research_state(HUMAN).1, None);
        assert_eq!(sim.technology_count(), 12);
        assert!(!sim.building_unlocked(HUMAN, BuildingKind::AntimatterPlant));
        for id in 0..12 {
            sim.civs[0].researched_techs.set(id);
            sim.unlock_earthfront_tech(0, id);
        }
        assert_eq!(sim.player_era(HUMAN), 1);
        assert_eq!(sim.shield_max(HUMAN), Fixed::ZERO);
        assert!(!sim.has_antigrav(HUMAN));
        assert_eq!(sim.player_weapon_bonus(HUMAN), Fixed::ZERO);
    }

    #[test]
    fn service_state_is_replayable_and_hashed() {
        let mut first = operation();
        first.add_building(HUMAN, BuildingKind::PowerPlant, 3, 10);
        first.add_building(HUMAN, BuildingKind::ResearchLab, 4, 10);
        let mut second = first.clone();
        let commands = [Command::Research {
            owner: HUMAN,
            tech_id: 0,
        }];
        first.step(&commands);
        second.step(&commands);
        for _ in 0..1000 {
            first.step(&[]);
            second.step(&[]);
        }
        assert_eq!(first.state_hash(), second.state_hash());
        assert!(first.research_state(HUMAN).0.get(0));
        second.entities[0].supply_stock += 1;
        assert_ne!(first.state_hash(), second.state_hash());
    }
}
