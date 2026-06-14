//! Prebuilt scenarios — concrete maps + setups that realize the core fantasy.
//!
//! [`lane_defense`] is the attack/defend hybrid: your base on the left, the enemy
//! base on the right, a central wall band funnelling movement into a top and a
//! bottom lane, and escalating enemy waves. You defend with towers and units while
//! you can also push a lane to destroy the enemy Command Center.

use crate::fixed::Fixed;
use crate::game::map::{Deposit, DepositKind, Map, Tile};
use crate::game::procgen;
use crate::game::sim::{PlayerId, Sim, WaveConfig};
use crate::game::stats::{BuildingKind, UnitKind};
use crate::vec::Vec2;

const HUMAN: PlayerId = PlayerId(0);
const ENEMY: PlayerId = PlayerId(1);

/// Builds the lane-defense scenario, seeded for deterministic randomness.
#[must_use]
pub fn lane_defense(seed: u64) -> Sim {
    let mut map = Map::new(48, 21);
    // Central wall band: splits the field into a top lane (rows 0..9) and a
    // bottom lane (rows 12..21) between columns 12 and 35.
    for x in 12..36 {
        for y in 9..=11 {
            map.set_tile(x, y, Tile::BLOCKED);
        }
    }

    // Ore near each base, alloy on the contested mid-flanks (all clear of the
    // wall band rows 9..=11 and the building tiles).
    let ore = Deposit {
        kind: DepositKind::Ore,
        remaining: 24_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 15_000,
    };
    map.set_deposit(8, 5, ore);
    map.set_deposit(8, 15, ore);
    map.set_deposit(40, 5, ore);
    map.set_deposit(40, 15, ore);
    map.set_deposit(24, 3, alloy);
    map.set_deposit(24, 18, alloy);
    // Home ore under the player's starting Extractor so the opening economy flows.
    // (The enemy AI claims the ore scattered near its base.)
    map.set_deposit(2, 12, ore);

    let mut sim = Sim::new(map, seed, Fixed::from_int(1500));

    // Player base (left).
    sim.add_building(HUMAN, BuildingKind::CommandCenter, 3, 10);
    sim.add_building(HUMAN, BuildingKind::PowerPlant, 2, 8);
    sim.add_building(HUMAN, BuildingKind::Refinery, 2, 12);
    sim.add_building(HUMAN, BuildingKind::Barracks, 5, 10);

    // Enemy base (right).
    sim.add_building(ENEMY, BuildingKind::CommandCenter, 44, 10);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, 45, 8);
    sim.add_building(ENEMY, BuildingKind::Barracks, 45, 12);

    // Escalating enemy waves marching on the player's base.
    sim.set_waves(WaveConfig {
        first_delay: 3600,
        interval: 1800,
        base_size: 4,
        growth: 2,
        spawn: Vec2::new(Fixed::from_int(43), Fixed::from_int(10)),
        unit: UnitKind::Infantry,
        attacker: ENEMY,
        defender: HUMAN,
        escalate: false,
    });

    sim
}

/// An open-field skirmish: no walls, no waves, two full bases in opposite corners.
/// Pure RTS — out-produce and out-maneuver the enemy across open ground, where air
/// and flanking matter most.
#[must_use]
pub fn open_clash(seed: u64) -> Sim {
    let mut map = Map::new(40, 24);

    // Ore near each base corner; alloy in the contested centre.
    let ore = Deposit {
        kind: DepositKind::Ore,
        remaining: 24_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 15_000,
    };
    map.set_deposit(8, 17, ore);
    map.set_deposit(8, 21, ore);
    map.set_deposit(31, 4, ore);
    map.set_deposit(31, 8, ore);
    map.set_deposit(20, 12, alloy);
    // Home ore under each side's pre-placed Extractor (both have one here).
    map.set_deposit(2, 21, ore); // player Refinery tile
    map.set_deposit(37, 6, ore); // enemy Refinery tile

    let mut sim = Sim::new(map, seed, Fixed::from_int(2000));

    // Player base, bottom-left.
    sim.add_building(HUMAN, BuildingKind::CommandCenter, 4, 19);
    sim.add_building(HUMAN, BuildingKind::PowerPlant, 2, 17);
    sim.add_building(HUMAN, BuildingKind::Refinery, 2, 21);
    sim.add_building(HUMAN, BuildingKind::Barracks, 6, 19);

    // Enemy base, top-right.
    sim.add_building(ENEMY, BuildingKind::CommandCenter, 35, 4);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, 37, 2);
    sim.add_building(ENEMY, BuildingKind::Refinery, 37, 6);
    sim.add_building(ENEMY, BuildingKind::Barracks, 33, 4);

    sim
}

/// A central fortress map: an impassable block in the middle forces every push
/// around one of two flanks, with bases in opposite corners and enemy waves
/// pressing the player — terrain-driven tower defense.
#[must_use]
pub fn crossroads(seed: u64) -> Sim {
    let mut map = Map::new(30, 30);
    // Central fortress block (cols 11..19, rows 11..19) — units route around it.
    for x in 11..19 {
        for y in 11..19 {
            map.set_tile(x, y, Tile::BLOCKED);
        }
    }

    // Ore near each base corner; alloy on the open flanks beside the fortress.
    let ore = Deposit {
        kind: DepositKind::Ore,
        remaining: 24_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 15_000,
    };
    map.set_deposit(7, 3, ore);
    map.set_deposit(3, 7, ore);
    map.set_deposit(23, 26, ore);
    map.set_deposit(26, 23, ore);
    map.set_deposit(2, 15, alloy);
    map.set_deposit(27, 15, alloy);
    // Home ore under the player's starting Extractor so the opening economy flows.
    map.set_deposit(1, 5, ore);

    let mut sim = Sim::new(map, seed, Fixed::from_int(1500));

    // Player base, top-left corner.
    sim.add_building(HUMAN, BuildingKind::CommandCenter, 3, 3);
    sim.add_building(HUMAN, BuildingKind::PowerPlant, 1, 1);
    sim.add_building(HUMAN, BuildingKind::Refinery, 1, 5);
    sim.add_building(HUMAN, BuildingKind::Barracks, 5, 3);

    // Enemy base, bottom-right corner.
    sim.add_building(ENEMY, BuildingKind::CommandCenter, 26, 26);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, 28, 28);
    sim.add_building(ENEMY, BuildingKind::Barracks, 28, 24);

    // A siege cadence distinct from Lane Defense: fewer, larger, slower-building
    // waves that batter the fortress flanks rather than a steady trickle.
    sim.set_waves(WaveConfig {
        first_delay: 4500,
        interval: 2400,
        base_size: 6,
        growth: 3,
        spawn: Vec2::new(Fixed::from_int(25), Fixed::from_int(25)),
        unit: UnitKind::Infantry,
        attacker: ENEMY,
        defender: HUMAN,
        escalate: false,
    });

    sim
}

/// The survival "Beachhead" run.
///
/// A **procedurally generated** battlefield with the player base on the left and a
/// fixed alien beachhead on the right that pours out **escalating** waves
/// (broadening composition + a Capital boss every 5th wave). Hold out as long as
/// you can; destroy the beachhead Core Node to win. Each seed is a different map,
/// so no two runs are alike.
#[must_use]
pub fn survival(seed: u64) -> Sim {
    let mut map = procgen::generate(seed);
    let w = map.width();
    let mid = map.height() / 2;
    // A rich HOME ore deposit under the starting Extractor, so the base mines from
    // the first tick; the player expands to the procgen deposits as it depletes.
    map.set_deposit(
        2,
        mid + 2,
        Deposit {
            kind: DepositKind::Ore,
            remaining: 30_000,
        },
    );
    let mut sim = Sim::new(map, seed, Fixed::from_int(1800));

    // No pre-placed base: the run opens in the SURVEY phase and the player's
    // first act is choosing where to found the Command Center (the home ore
    // deposit above is one premium option among the procgen sites). The wave
    // clock starts at the founding tick.
    sim.begin_survey();
    // The human starts with only a founding kit; the tech tree unlocks the rest
    // (Barracks/Infantry via Mobilization, turrets/lab/capitals deeper in). The
    // alien beachhead (P1) stays fully unlocked.
    sim.set_starting_unlocks(
        HUMAN,
        &[
            BuildingKind::CommandCenter,
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Wall,
        ],
        &[],
    );

    // Endurance run: you outlast the waves rather than race to a win. Losing your
    // own Command Center ends it; the alien beachhead is just the wave source.
    sim.set_survival_mode(true);

    // Alien beachhead (right margin): a Core Node + power that pours out the waves.
    sim.add_building(ENEMY, BuildingKind::CommandCenter, w - 4, mid);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, w - 3, mid - 2);

    // Escalating waves from the beachhead toward the player.
    sim.set_waves(WaveConfig {
        // Tighter pace so the run has real stakes: ~90s to found and build an
        // opening, then a TELEGRAPHED siege roughly every ~3 minutes. Each siege
        // escalates hard (size + an adapting, doctrine-stacking swarm) so a
        // teched army is genuinely tested rather than coasting.
        first_delay: 2_700,
        interval: 5_400,
        // `size = base_size + growth * wave`, plus a Capital boss every 5th wave,
        // plus the adapting swarm (each wave hardens the attacker — run_waves).
        base_size: 12,
        growth: 6,
        spawn: Vec2::new(
            Fixed::from_int(i32::from(w) - 5),
            Fixed::from_int(i32::from(mid)),
        ),
        unit: UnitKind::Infantry,
        attacker: ENEMY,
        defender: HUMAN,
        escalate: true,
    });

    sim
}

/// An N-civ conquest map.
///
/// Every civ starts on its own **home planet** (a marked tile block with a
/// `CommandCenter` seat + fully autonomous colony), spread deterministically
/// around the field, plus a couple of **neutral planets** in the contested
/// centre as expansion targets. Wholly index-driven — no RNG — so the layout is
/// identical for a given `(seed, civ_count)`. AI civs expand to the neutral
/// planets and assault each other's seats (see `ai_commands`).
///
/// `civ_count` is clamped to `1..=HOME_CENTERS.len()` (the number of pre-laid home
/// regions); the `seed` only feeds `Sim`'s RNG (combat/wave jitter), never layout.
/// A construction-only deterministic PRNG (mirrors the private `Lcg` in
/// `procgen`), used solely to vary the [`conquest`] start per seed at BUILD time.
/// It never runs in the tick loop, so it does not affect sim determinism: the
/// same `(seed, civ_count)` always builds a bit-identical world.
struct ConquestLcg(u64);

impl ConquestLcg {
    const fn next(&mut self) -> u32 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        #[allow(
            clippy::cast_possible_truncation,
            reason = "taking the high 32 bits of the 64-bit LCG state, as in procgen::Lcg"
        )]
        {
            (self.0 >> 33) as u32
        }
    }

    /// A value in `lo..hi` (hi exclusive; requires `lo < hi`).
    #[allow(
        clippy::cast_possible_truncation,
        reason = "modulo by (hi-lo) keeps the result within u16 range"
    )]
    fn range(&mut self, lo: u16, hi: u16) -> u16 {
        lo + (self.next() % u32::from(hi - lo)) as u16
    }
}

#[must_use]
#[allow(
    clippy::too_many_lines,
    reason = "one cohesive scenario builder: solar layout, seeded ownership + forward \
              colony, the push loop, and terrain painting read best as a single unit"
)]
pub fn conquest(seed: u64, civ_count: usize) -> Sim {
    use crate::game::civ::AUTONOMY_FULL;
    use crate::game::hex;
    use crate::game::map::TerrainKind;
    use crate::game::planet::{Planet, PlanetId};

    // Landscape field (~2.4:1) so the hex board fills a 16:9 screen instead of
    // letterboxing into a tall centred square. Planets spread across the width
    // like bodies strung along a star system.
    const W: u16 = 72;
    const H: u16 = 28;
    /// Half-extent (in tiles) of a planet's square tile block: a 3x3 region.
    const PLANET_HALF: u16 = 1;
    /// Claim radius in world units (auxiliary; exact membership is the Map layer).
    const PLANET_RADIUS: i32 = 3;

    // ===== OUR SOLAR SYSTEM =====
    // The Sun sits at the map centre (a render-only star — not a settleable planet).
    // The eight planets are hand-placed in SOLAR ORDER at monotonically increasing
    // distance from the centre (so their orbits nest) and spread in angle, with all
    // 3x3 blocks in-bounds and non-overlapping on the 72x28 field. Planet IDs ARE
    // the solar order (0=Mercury .. 7=Neptune), so the renderer styles + names each
    // world from its id. You (civ 0) always start on EARTH.
    const SOLAR: [(u16, u16); 8] = [
        (44, 16), // 0 Mercury
        (26, 10), // 1 Venus
        (50, 11), // 2 Earth  <- the human homeworld
        (20, 20), // 3 Mars
        (55, 19), // 4 Jupiter
        (14, 9),  // 5 Saturn
        (61, 11), // 6 Uranus
        (9, 17),  // 7 Neptune
    ];
    const EARTH: usize = 2;
    /// Seeded FAIR edge granted to one civ per seed (see the comment at its use):
    /// a starting-Money bump plus a standing garrison at its forward colony.
    const EDGE_MONEY: i32 = 2400;
    /// Standing Infantry pre-placed at the favoured civ's forward base.
    const EDGE_GARRISON: i32 = 32;

    let civ_count = civ_count.clamp(1, 8);
    let mut sim = Sim::with_civ_count(Map::new(W, H), seed, Fixed::from_int(2000), civ_count);

    // ===== CONSTRUCTION-ONLY SEEDED PRNG =====
    // A tiny LCG (mirroring `procgen::Lcg`) used ONLY here at build time to vary the
    // start per seed. This runs once during construction — it never touches the tick
    // loop — so it is determinism-SAFE: the same `(seed, civ_count)` always builds a
    // bit-identical world, exactly like `procgen::generate(seed)`. The golden test
    // uses `survival()`, not `conquest()`, so this is golden-neutral.
    let mut rng = ConquestLcg(seed ^ 0xC0FF_EE15_600D_5EED);

    // VARY: AI home geography. The 7 non-Earth planet ids are shuffled (Fisher-Yates
    // with the construction RNG), then the (civ_count-1) AI civs home on the first
    // shuffled ids. Every other world stays neutral. Earth is always the human's, so
    // it is held out of the shuffle. Different seeds => different neighbours, threats
    // and expansion races on the SAME solar system.
    let mut ai_pool: [usize; 7] = [0, 1, 3, 4, 5, 6, 7]; // all but Earth (2)
    for i in (1..ai_pool.len()).rev() {
        let j = usize::from(rng.range(0, u16::try_from(i + 1).unwrap_or(1)));
        ai_pool.swap(i, j);
    }

    // VARY: a gentle, FAIR per-civ strength edge to break the symmetric deadlock.
    // Each seed nominates exactly ONE civ (any of the civ_count, INCLUDING the human
    // civ 0) to receive the head-start. The chosen civ rotates across seeds and the
    // human is on equal footing (it can be the favoured civ too), so no side is
    // systematically advantaged. The edge has two parts, applied below:
    //   * a starting-Money bump (out-produces neighbours into a bigger army),
    //   * a pre-settled FORWARD production colony seated on the neutral planet nearest
    //     a rival (a CC + Power/Refinery/Barracks + a standing garrison — see below).
    // The forward colony is the decisive, FAIR lever: a homeworld's seat is captured
    // (not destroyed) only by a stack that reaches the seat at full strength, but
    // outgoing damage decays with distance from the nearest friendly Command Center
    // (`supply_decay_factor`), and a one-shot stack bounces off a ring the defender's
    // home keeps re-crewing. A forward base that out-produces a rival from right next
    // door lets the favoured civ apply CONTINUOUS full-strength pressure, so the
    // borderless symmetric stand-off tips and one neighbour falls — while the other
    // civs, fighting at the decay floor across the system, stay in a longer contest.
    // It is one developed colony, not a doomstack, so games resolve mid-match rather
    // than snowball instantly; geography (above) decides WHO the favoured civ borders,
    // and on seeds where its border rival is too strong the match simply stays a
    // longer multi-way contest (a fortified-homeworld balance ceiling, by design).
    let edge_civ = rng.range(0, u16::try_from(civ_count).unwrap_or(1));
    sim.grant_money(PlayerId(edge_civ), Fixed::from_int(EDGE_MONEY));

    // Marks the 3x3 tile block centred on `(cx, cy)` as belonging to `planet_id`.
    let mark_block = |sim: &mut Sim, cx: u16, cy: u16, planet_id: PlanetId| {
        for dy in -i32::from(PLANET_HALF)..=i32::from(PLANET_HALF) {
            for dx in -i32::from(PLANET_HALF)..=i32::from(PLANET_HALF) {
                let (Ok(tx), Ok(ty)) = (
                    u16::try_from(i32::from(cx) + dx),
                    u16::try_from(i32::from(cy) + dy),
                ) else {
                    continue;
                };
                sim.map_mut().set_planet(tx, ty, planet_id);
            }
        }
    };

    // Decide each world's owner: Earth -> you (civ 0); each AI civ -> the next id
    // from the per-seed shuffled pool; every other world stays neutral (settle or
    // conquer it). With 8 planets and civ_count <= 4 this leaves >= 3 neutral before
    // the forward colony below claims one — still >= 1 neutral, which
    // `conquest_scenario_is_deterministic_and_resolves` depends on.
    let mut owner: [Option<PlayerId>; 8] = [None; 8];
    owner[EARTH] = Some(PlayerId(0));
    for k in 1..civ_count {
        owner[ai_pool[k - 1]] = Some(PlayerId(u16::try_from(k).unwrap_or(0)));
    }

    // The favoured civ's FORWARD colony: among the rivals it does NOT yet border, aim
    // at the nearest rival home, then settle the still-NEUTRAL planet closest to that
    // rival as the favoured civ's second seat. Squared-distance compares on the
    // hand-placed SOLAR coords; lowest planet index breaks ties. All static integer
    // math — no rng beyond `edge_civ` — so the pick is deterministic per seed. Skips
    // cleanly (leaving the edge purely economic) if there is no rival or no spare
    // neutral, so the >= 1-neutral and fairness invariants always hold.
    let d2 = |a: usize, b: usize| {
        let (ax, ay) = (i32::from(SOLAR[a].0), i32::from(SOLAR[a].1));
        let (bx, by) = (i32::from(SOLAR[b].0), i32::from(SOLAR[b].1));
        (ax - bx) * (ax - bx) + (ay - by) * (ay - by)
    };
    let mut edge_forward: Option<usize> = None;
    let edge_home = (0..8).find(|&p| owner[p] == Some(PlayerId(edge_civ)));
    if let Some(home) = edge_home {
        // Nearest RIVAL home (a different owned planet), lowest index on ties.
        let rival = (0..8)
            .filter(|&p| owner[p].is_some() && owner[p] != Some(PlayerId(edge_civ)))
            .min_by_key(|&p| (d2(home, p), p));
        if let Some(rival) = rival {
            // Nearest still-NEUTRAL planet to that rival, lowest index on ties, but
            // keep >= 1 planet neutral overall (never settle the last free world).
            let neutral_count = (0..8).filter(|&p| owner[p].is_none()).count();
            if neutral_count > 1 {
                if let Some(fwd) = (0..8)
                    .filter(|&p| owner[p].is_none())
                    .min_by_key(|&p| (d2(rival, p), p))
                {
                    owner[fwd] = Some(PlayerId(edge_civ));
                    edge_forward = Some(fwd);
                }
            }
        }
    }

    // Push all eight planets in solar order, so PlanetId == solar index. Owned
    // worlds get a CommandCenter seat + a colony (you start MANUAL on Earth so you
    // drive it; AI civs start fully autonomous). The tile block is marked with the
    // id `push_planet` returns — one source of truth, no parallel counter.
    for (idx, &(cx, cy)) in SOLAR.iter().enumerate() {
        let holder = owner[idx];
        let seat = holder.map(|civ| sim.add_building(civ, BuildingKind::CommandCenter, cx, cy));
        let planet_id = sim.push_planet(Planet {
            owner: holder,
            seat,
            center: hex::center(cx, cy),
            radius: Fixed::from_int(PLANET_RADIUS),
        });
        mark_block(&mut sim, cx, cy, planet_id);
        if let (Some(civ), Some(cc)) = (holder, seat) {
            let autonomy = if civ.0 == 0 { 0 } else { AUTONOMY_FULL };
            let _ = sim.add_colony(civ, cc, autonomy);
            // Planetary defense: ring the seat with turrets at the block corners so
            // taking a homeworld is a real assault, not a drive-by seat-snipe — this
            // is the main brake on runaway conquest. AA on one corner covers air.
            for (i, &(dx, dy)) in [(-1i32, -1i32), (1, -1), (-1, 1), (1, 1)]
                .iter()
                .enumerate()
            {
                let (Ok(tx), Ok(ty)) = (
                    u16::try_from(i32::from(cx) + dx),
                    u16::try_from(i32::from(cy) + dy),
                ) else {
                    continue;
                };
                let kind = if i == 0 {
                    BuildingKind::AaTurret
                } else {
                    BuildingKind::GunTurret
                };
                sim.add_building(civ, kind, tx, ty);
            }
        }
    }

    // FAIR seeded edge (offensive half): make the favoured civ's FORWARD colony a
    // working PRODUCTION base, not just a flagged seat — a PowerPlant + Refinery +
    // Barracks beside the bordered rival, plus a standing Infantry garrison. The
    // reason a 4-way of fortified homeworlds deadlocks is that a one-shot assault
    // bounces off a ring that the defender's home keeps re-crewing; cracking a seat
    // needs CONTINUOUS pressure at full supply. A forward base that out-produces the
    // rival from right next door provides exactly that, so the favoured civ can grind
    // one neighbour down and snowball — while the others, fighting at the supply
    // decay floor across the system, stay in a longer contest. It is one developed
    // colony, not a doomstack, so it tips the match toward a resolution rather than an
    // instant win; geography decides WHO it borders and the favoured civ rotates
    // across seeds (the human included), so no side is systematically advantaged.
    if let Some(fwd) = edge_forward {
        let (fx, fy) = SOLAR[fwd];
        // Support buildings just outside the 3x3 block + ring (offsets >= 2), placed
        // only where in-bounds. add_building marks the tile BLOCKED, so they never
        // overlap the seat, ring, or each other.
        for (dx, dy, kind) in [
            (2i32, 0i32, BuildingKind::PowerPlant),
            (-2, 0, BuildingKind::Refinery),
            (0, 2, BuildingKind::Barracks),
        ] {
            if let (Ok(tx), Ok(ty)) = (
                u16::try_from(i32::from(fx) + dx),
                u16::try_from(i32::from(fy) + dy),
            ) {
                sim.add_building(PlayerId(edge_civ), kind, tx, ty);
            }
        }
        // A standing garrison so the FIRST assault already has mass; the forward
        // Barracks then keeps the pressure on. Units sit on world-space tiles clear
        // of the building tiles (a 4-wide grid offset below the seat).
        let c = hex::center(fx, fy);
        for n in 0..EDGE_GARRISON {
            let col = n % 4 - 2;
            let row = n / 4;
            let pos = Vec2::new(c.x + Fixed::from_int(col), c.y + Fixed::from_int(3 + row));
            sim.add_unit(PlayerId(edge_civ), UnitKind::Infantry, pos);
        }
    }

    // Paint deterministic, non-Barren terrain on every planet tile so colonies have
    // food to grow during real play. The terrain layer defaults to Barren (zero
    // yield); without this, every colony is stuck at population 1. The scheme is
    // index-driven (`(x + y) % 3`) for a little texture — Plains/Fertile/Rich —
    // and never leaves a planet tile Barren. Open space stays Barren (it is never
    // worked). Terrain is a static, NON-HASHED layer, so this does not touch the
    // state hash; it only changes colony growth behaviour.
    for y in 0..H {
        for x in 0..W {
            if sim.map().planet_at(i32::from(x), i32::from(y)).is_some() {
                let kind = match (u32::from(x) + u32::from(y)) % 3 {
                    0 => TerrainKind::Plains,
                    1 => TerrainKind::Fertile,
                    _ => TerrainKind::Rich,
                };
                sim.map_mut().set_terrain(x, y, kind);
            }
        }
    }
    // Recompute the planet-yield cache from the freshly painted terrain (must run
    // AFTER painting). `conquest` did not previously call this.
    sim.rebuild_planet_yield();

    sim
}

/// The selectable scenarios — the skirmish map roster shown to the player.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Scenario {
    /// [`lane_defense`] — funnelled lanes plus escalating enemy waves.
    LaneDefense,
    /// [`open_clash`] — wall-free open-field skirmish, no waves.
    OpenClash,
    /// [`crossroads`] — a central fortress forcing flank pushes, with waves.
    Crossroads,
    /// [`survival`] — procedural map, endless escalating waves (the solo run).
    /// Deliberately excluded from [`Scenario::ALL`] (the skirmish roster): it is
    /// its own mode with its own tests, launched separately by the shell.
    Survival,
}

impl Scenario {
    /// Every skirmish scenario, in menu order. (Survival is a separate mode.)
    pub const ALL: [Self; 3] = [Self::LaneDefense, Self::OpenClash, Self::Crossroads];

    /// The scenario's display name.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::LaneDefense => "Orbital Siege",
            Self::OpenClash => "Open Front",
            Self::Crossroads => "Crater Crossroads",
            Self::Survival => "Beachhead",
        }
    }

    /// A one-line description for the map-select menu.
    #[must_use]
    pub const fn tagline(self) -> &'static str {
        match self {
            Self::LaneDefense => "Hold the approach lanes against alien waves",
            Self::OpenClash => "Open-field clash — no walls, no waves",
            Self::Crossroads => "Flank a central wreck under pressure",
            Self::Survival => "Endless escalating waves on a procedural front",
        }
    }

    /// Builds the scenario's starting world, seeded for deterministic randomness.
    #[must_use]
    pub fn build(self, seed: u64) -> Sim {
        match self {
            Self::LaneDefense => lane_defense(seed),
            Self::OpenClash => open_clash(seed),
            Self::Crossroads => crossroads(seed),
            Self::Survival => survival(seed),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{conquest, crossroads, lane_defense, open_clash, survival, Scenario};
    use crate::game::civ::ColonyId;
    use crate::game::map::Map;
    use crate::game::path::find_path;
    use crate::game::planet::PlanetId;
    use crate::game::sim::{Command, PlayerId};
    use alloc::vec::Vec;

    #[test]
    fn conquest_scenario_is_deterministic_and_resolves() {
        fn run() -> u64 {
            let mut s = conquest(12_345, 4); // 4 civs, generated planets
            for _ in 0..400 {
                let cmds: Vec<Command> = (0..4u16)
                    .filter(|&id| s.civ_alive(PlayerId(id)))
                    .flat_map(|id| s.ai_commands(PlayerId(id)))
                    .collect();
                s.step(&cmds);
            }
            s.state_hash()
        }
        assert_eq!(
            run(),
            run(),
            "conquest scenario must be bit-identical across runs"
        );

        // Resolution: at least one initially-neutral planet is claimed by the AI by
        // the end of a run. Guards against a regression that silently makes
        // `ai_conquest_commands` a no-op (which determinism alone would not catch).
        let mut s = conquest(12_345, 4);
        let planet_count = u16::try_from(s.planets_len()).unwrap();
        let neutrals: Vec<PlanetId> = (0..planet_count)
            .map(PlanetId)
            .filter(|&p| s.planet_owner(p).is_none())
            .collect();
        assert!(
            !neutrals.is_empty(),
            "scenario must start with neutral planets"
        );
        for _ in 0..400 {
            let cmds: Vec<Command> = (0..4u16)
                .filter(|&id| s.civ_alive(PlayerId(id)))
                .flat_map(|id| s.ai_commands(PlayerId(id)))
                .collect();
            s.step(&cmds);
        }
        assert!(
            neutrals.iter().any(|&p| s.planet_owner(p).is_some()),
            "conquest-expansion AI must claim at least one neutral planet"
        );
    }

    #[test]
    fn conquest_varies_by_seed() {
        // Different seeds build DIFFERENT starts (the whole point of the rewrite:
        // shuffled AI homes + a seeded forward-colony edge), while the SAME seed is
        // bit-identical (construction-only PRNG ⇒ determinism preserved). We compare
        // the freshly-built state hash, before any ticks, so this isolates the SETUP.
        assert_ne!(
            conquest(1, 4).state_hash(),
            conquest(2, 4).state_hash(),
            "different seeds must produce different conquest starts"
        );
        assert_eq!(
            conquest(7, 4).state_hash(),
            conquest(7, 4).state_hash(),
            "the same seed must produce a bit-identical conquest start"
        );
    }

    #[test]
    fn conquest_colonies_grow_on_painted_terrain() {
        let mut s = conquest(2024, 3);
        // Each home colony's planet now has painted (non-Barren) terrain, so the
        // colony has a non-zero food rate. Run a while and assert at least one
        // colony grew beyond its starting population of 1.
        for _ in 0..3000 {
            let cmds: Vec<Command> = (0..3u16)
                .filter(|&i| s.civ_alive(PlayerId(i)))
                .flat_map(|i| s.ai_commands(PlayerId(i)))
                .collect();
            s.step(&cmds);
        }
        let grew = (0..s.colonies_len()).any(|i| {
            s.colony(ColonyId(u32::try_from(i).unwrap()))
                .is_some_and(|c| c.population > 1)
        });
        assert!(grew, "conquest colonies must grow on painted terrain");
    }

    #[test]
    fn survival_founding_registers_a_manual_colony() {
        let mut s = survival(7);
        assert_eq!(s.colony_count_for(PlayerId(0)), 0);
        let cmds = s.ai_commands(PlayerId(0)); // survey AI founds the base
        s.step(&cmds);
        assert_eq!(
            s.colony_count_for(PlayerId(0)),
            1,
            "founding registers the owner's first colony"
        );
        // It starts fully manual — the player opts into delegation.
        assert_eq!(s.colony(ColonyId(0)).unwrap().autonomy_level, 0);
    }

    /// The first passable tile scanning from one corner — used to prove the open
    /// area of a map is a single connected region (no base sealed off).
    fn corner_passable(map: &Map, from_far_corner: bool) -> (u16, u16) {
        let order: Vec<u16> = if from_far_corner {
            (0..map.height()).rev().collect()
        } else {
            (0..map.height()).collect()
        };
        let cols: Vec<u16> = if from_far_corner {
            (0..map.width()).rev().collect()
        } else {
            (0..map.width()).collect()
        };
        for &y in &order {
            for &x in &cols {
                if map.tile(i32::from(x), i32::from(y)).unwrap().passable {
                    return (x, y);
                }
            }
        }
        panic!("map has no passable tile");
    }

    #[test]
    fn every_wave_map_has_minable_deposits() {
        for &sc in &[
            Scenario::LaneDefense,
            Scenario::Crossroads,
            Scenario::Survival,
        ] {
            let s = sc.build(7);
            let count = s.map().deposits().count();
            assert!(
                count >= 2,
                "{}: needs deposits to mine ({count})",
                sc.name()
            );
        }
    }

    #[test]
    fn every_scenario_builds_with_two_live_bases() {
        for &sc in &Scenario::ALL {
            let s = sc.build(7);
            assert_eq!(s.winner(), None, "{}: a base is already dead", sc.name());
            assert!(
                s.entity_count() >= 6,
                "{}: too few starting buildings",
                sc.name()
            );
            assert!(!sc.name().is_empty() && !sc.tagline().is_empty());
        }
    }

    #[test]
    fn every_scenario_keeps_the_battlefield_connected() {
        // A path must exist across the whole open area, so neither base can be
        // walled off from the other (which would soft-lock the match).
        for &sc in &Scenario::ALL {
            let s = sc.build(7);
            let start = corner_passable(s.map(), false);
            let goal = corner_passable(s.map(), true);
            assert!(
                find_path(s.map(), start, goal).is_some(),
                "{}: battlefield is bisected",
                sc.name()
            );
        }
    }

    #[test]
    fn every_scenario_replays_to_the_same_result() {
        for &sc in &Scenario::ALL {
            let mut original = sc.build(5);
            let mut log = Vec::new();
            for _ in 0..400 {
                let mut cmds = original.ai_commands(PlayerId(0));
                cmds.extend(original.ai_commands(PlayerId(1)));
                original.step(&cmds);
                log.push(cmds);
            }
            let expected = original.state_hash();
            let mut replay = sc.build(5);
            for batch in &log {
                replay.step(batch);
            }
            assert_eq!(
                replay.state_hash(),
                expected,
                "{} not deterministic",
                sc.name()
            );
        }
    }

    #[test]
    fn every_scenario_resolves_decisively() {
        // Guard against a soft-lock: every scenario must field units (so combat is
        // actually happening) and not panic. The two wave-pressured maps must also
        // reach a decisive winner. Open Clash has no waves, so two identical AIs
        // reach a deterministic attrition stalemate — that is expected (a human
        // breaks the symmetry), so it is only required to stay live, not resolve.
        for &sc in &Scenario::ALL {
            let mut s = sc.build(7);
            let mut peak = 0;
            let mut resolved_at = None;
            for t in 0..12_000_u64 {
                let mut cmds = s.ai_commands(PlayerId(0));
                cmds.extend(s.ai_commands(PlayerId(1)));
                s.step(&cmds);
                peak = peak.max(s.unit_count(PlayerId(0)) + s.unit_count(PlayerId(1)));
                if s.winner().is_some() {
                    resolved_at = Some(t + 1);
                    break;
                }
            }
            assert!(
                peak > 0,
                "{}: no units were ever fielded (soft-lock)",
                sc.name()
            );
            if sc == Scenario::OpenClash {
                continue; // no-wave symmetric map: stalemate is the expected AI-vs-AI result
            }
            assert!(resolved_at.is_some(), "{}: wave map soft-locked", sc.name());
            assert!(
                resolved_at.unwrap() > 60,
                "{}: resolved implausibly fast",
                sc.name()
            );
        }
    }

    #[test]
    fn open_clash_has_no_walls_and_trains_armies() {
        let mut s = open_clash(3);
        // No terrain walls: the only impassable tiles are the buildings themselves.
        let mut blocked = 0_usize;
        for ty in 0..s.map().height() {
            for tx in 0..s.map().width() {
                if !s.map().tile(i32::from(tx), i32::from(ty)).unwrap().passable {
                    blocked += 1;
                }
            }
        }
        assert_eq!(blocked, s.entity_count(), "open_clash has terrain walls");
        // With no waves, units only appear once the AIs train them. Run partway —
        // before either base can fall — so we can also check what was built.
        let before = s.unit_count(PlayerId(0)) + s.unit_count(PlayerId(1));
        for _ in 0..400 {
            let mut cmds = s.ai_commands(PlayerId(0));
            cmds.extend(s.ai_commands(PlayerId(1)));
            s.step(&cmds);
        }
        assert_eq!(s.winner(), None, "match resolved sooner than expected");
        let after = s.unit_count(PlayerId(0)) + s.unit_count(PlayerId(1));
        assert!(after > before, "no armies were ever trained");
        // The four essentials (PowerPlant/Refinery/Barracks/CommandCenter) are
        // pre-placed (8 structures). Beyond that each AI now expands its economy —
        // a ResearchLab, plus claiming map deposits with extra Extractors and adding
        // Reactors to keep them powered — instead of only adding a lab. Expansion is
        // bounded (`MAX_AI_EXTRACTORS` + power-gated Reactors), so the count grows
        // modestly rather than carpeting the map.
        let buildings = s.entity_count() - after;
        assert!(
            (12..=20).contains(&buildings),
            "AI built an unexpected number of structures on open_clash: {buildings}"
        );
    }

    #[test]
    fn crossroads_has_a_central_fortress_with_open_flanks() {
        let s = crossroads(1);
        // The center is walled (the fortress)...
        assert!(!s.map().tile(15, 15).unwrap().passable);
        // ...but the corners the bases sit in stay open ground.
        assert!(s.map().tile(0, 0).unwrap().passable);
        assert!(s.map().tile(29, 29).unwrap().passable);
    }

    #[test]
    fn sets_up_both_bases_with_no_winner_yet() {
        let s = lane_defense(1);
        assert_eq!(s.winner(), None); // both Command Centers alive
        assert!(s.entity_count() >= 7); // 4 player + 3 enemy buildings
    }

    #[test]
    fn a_wave_eventually_spawns() {
        let mut s = lane_defense(1);
        assert_eq!(s.unit_count(PlayerId(1)), 0);
        for _ in 0..3700 {
            s.step(&[]);
        }
        // first_delay is 3600, so a wave has spawned for the enemy by now
        assert!(s.unit_count(PlayerId(1)) >= 4);
    }

    #[test]
    fn the_central_wall_band_blocks_movement() {
        let s = lane_defense(1);
        assert!(!s.map().tile(20, 10).unwrap().passable); // inside the wall band
        assert!(s.map().tile(20, 2).unwrap().passable); // top lane open
        assert!(s.map().tile(20, 18).unwrap().passable); // bottom lane open
    }

    #[test]
    fn an_undefended_base_falls_and_the_match_is_won() {
        // The enemy plays (AI + waves); the human does nothing, so the base falls
        // and the win condition fires for the enemy. Drives a full match to a
        // decisive result through real simulation.
        let mut s = lane_defense(1);
        let mut winner = None;
        for _ in 0..8000 {
            let enemy = s.ai_commands(PlayerId(1));
            s.step(&enemy);
            if let Some(w) = s.winner() {
                winner = Some(w);
                break;
            }
        }
        assert_eq!(winner, Some(PlayerId(1)));
    }

    #[test]
    fn scenarios_use_space_theme_names() {
        assert_eq!(Scenario::LaneDefense.name(), "Orbital Siege");
        assert_eq!(Scenario::OpenClash.name(), "Open Front");
        assert_eq!(Scenario::Crossroads.name(), "Crater Crossroads");
        assert_eq!(
            Scenario::LaneDefense.tagline(),
            "Hold the approach lanes against alien waves"
        );
        assert_eq!(
            Scenario::OpenClash.tagline(),
            "Open-field clash — no walls, no waves"
        );
        assert_eq!(
            Scenario::Crossroads.tagline(),
            "Flank a central wreck under pressure"
        );
    }

    #[test]
    fn survival_opens_in_survey_then_founds_and_stays_connected() {
        let mut s = survival(7);
        assert!(s.surveying(), "survival opens in the survey phase");
        assert_eq!(s.winner(), None, "no base yet is not a loss");
        // Only the alien beachhead is pre-placed (CC + power); the human founds.
        assert_eq!(s.entity_count(), 2, "only the beachhead is pre-placed");
        let cmds = s.ai_commands(PlayerId(0));
        s.step(&cmds);
        assert!(!s.surveying(), "founding ends survey");
        assert_eq!(
            s.entity_count(),
            3,
            "the human CC now exists (2 beachhead + 1)"
        );
        let start = corner_passable(s.map(), false);
        let goal = corner_passable(s.map(), true);
        assert!(
            find_path(s.map(), start, goal).is_some(),
            "survival battlefield is bisected"
        );
        assert_eq!(s.waves_survived(), 0);
    }

    #[test]
    fn survival_is_deterministic() {
        let mut a = survival(11);
        let mut log = Vec::new();
        for _ in 0..500 {
            let enemy = a.ai_commands(PlayerId(1));
            a.step(&enemy);
            log.push(enemy);
        }
        let expected = a.state_hash();
        let mut b = survival(11);
        for batch in &log {
            b.step(batch);
        }
        assert_eq!(b.state_hash(), expected, "survival not deterministic");
    }

    #[test]
    fn survival_replays_across_the_founding_transition() {
        // Drive BOTH sides and record the full command log, so the run crosses the
        // Survey→Active flip (FoundBase: phase + phase_started + ore bonus). Replay
        // into a fresh sim and assert the state hashes match — locks determinism of
        // the one genuinely new hashed control-flow branch.
        let mut a = survival(5);
        let mut log = Vec::new();
        for _ in 0..3000 {
            let mut cmds = a.ai_commands(PlayerId(0));
            cmds.extend(a.ai_commands(PlayerId(1)));
            a.step(&cmds);
            log.push(cmds);
        }
        assert!(
            !a.surveying(),
            "the run should have founded and crossed to Active"
        );
        let expected = a.state_hash();
        let mut b = survival(5);
        for batch in &log {
            b.step(batch);
        }
        assert_eq!(
            b.state_hash(),
            expected,
            "survival replay diverged across the founding transition"
        );
    }

    #[test]
    fn restricted_human_progresses_through_the_tech_tree() {
        // The survival human starts with no army and a 3-building kit; driven by
        // ai_commands it must research its way to a lab, an era, and a standing
        // army — proving the progression is not soft-locked.
        //
        // We track each milestone the FIRST time it's reached over the run rather
        // than only sampling the final tick: the late game is a deliberately
        // lethal siege (escalating waves + a Capital boss whose main gun now has
        // area splash), so a fully-teched human can still eventually be overrun.
        // The soft-lock guarantee is that the human DOES tech up, not that it
        // survives the endgame — so reaching the milestones is what we assert.
        let mut s = survival(3);
        let mut got_lab = false;
        let mut got_era = false;
        let mut got_army = false;
        for _ in 0..40_000u32 {
            let cmds = s.ai_commands(PlayerId(0));
            s.step(&cmds);
            got_lab |= s.has_research_lab(PlayerId(0));
            got_era |= s.player_era(PlayerId(0)) >= 1;
            got_army |= s.unit_count(PlayerId(0)) > 0;
        }
        assert!(got_lab, "human should research the Lab (Orbital Logistics)");
        assert!(got_era, "human should advance at least one era");
        assert!(got_army, "human should unlock + train an army");
    }

    #[test]
    fn survival_overruns_an_undefended_base() {
        // Player does nothing; the enemy AI (+ escalating waves once the grace
        // period expires) must eventually take the base so the run resolves with
        // no soft-lock. Wave-spawn coverage is handled by
        // `survival_has_a_three_minute_grace_period`.
        let mut s = survival(3);
        let found = s.ai_commands(PlayerId(0)); // human founds, then does nothing
        s.step(&found);
        let mut winner = None;
        for _ in 0..40000 {
            let enemy = s.ai_commands(PlayerId(1));
            s.step(&enemy);
            if let Some(w) = s.winner() {
                winner = Some(w);
                break;
            }
        }
        assert_eq!(
            winner,
            Some(PlayerId(1)),
            "undefended survival never resolved"
        );
    }

    #[test]
    fn survival_has_a_peaceful_founding_grace_period() {
        let mut s = survival(7);
        let cmds = s.ai_commands(PlayerId(0)); // found, starting the wave clock
        s.step(&cmds);
        // 30 Hz -> first_delay 2_700 ticks (~90s) from founding. None before.
        for _ in 0..2_500 {
            s.step(&[]);
        }
        assert_eq!(
            s.unit_count(PlayerId(1)),
            0,
            "no waves should spawn during the grace period"
        );
        for _ in 0..600 {
            s.step(&[]);
        }
        assert!(
            s.unit_count(PlayerId(1)) > 0,
            "waves should begin after the grace period"
        );
    }

    #[test]
    #[ignore = "balance playtest — run with --ignored --nocapture to read the curve"]
    fn survival_balance_playtest() {
        // A competent AI plays the PLAYER side (claims deposits, builds, defends)
        // against the waves. Prints the economy + survival curve for tuning.
        let mut s = survival(3);
        let mut last_waves = 0;
        let mut winner = None;
        for t in 0..140_000u64 {
            let mut cmds = s.ai_commands(PlayerId(0)); // player-AI builds + fights
                                                       // Mirror the shell exactly: the beachhead AI acts once the first wave
                                                       // has spawned (render-shell main.rs gates it the same way), so enemy
                                                       // Tanks/Helis cast their abilities and the beachhead expands.
            if s.waves_survived() > 0 {
                cmds.extend(s.ai_commands(PlayerId(1)));
            }
            s.step(&cmds);
            let w = s.waves_survived();
            if w != last_waves {
                last_waves = w;
                std::eprintln!(
                    "wave {} @ t={} ({}s): money={} energy={} labour={} units(P0)={} units(P1)={}",
                    w,
                    t,
                    t / 30,
                    s.money(PlayerId(0)).to_bits() / 65536,
                    s.energy(PlayerId(0)).to_bits() / 65536,
                    s.labour(PlayerId(0)).to_bits() / 65536,
                    s.unit_count(PlayerId(0)),
                    s.unit_count(PlayerId(1)),
                );
            }
            if let Some(win) = s.winner() {
                winner = Some(win);
                std::eprintln!(
                    "RESOLVED at t={} ({}s): winner={:?}, waves_survived={}",
                    t,
                    t / 30,
                    win,
                    w
                );
                break;
            }
        }
        std::eprintln!(
            "END: winner={:?}, waves_survived={}, final money={}",
            winner,
            s.waves_survived(),
            s.money(PlayerId(0)).to_bits() / 65536
        );
    }

    #[test]
    fn survival_economy_flows_after_founding_and_stays_peaceful() {
        // The survey-AI founds then builds an Extractor on the home deposit, so the
        // economy mines; the build-up stays peaceful (first wave is ~90s AFTER
        // founding, not from map load).
        let mut s = survival(3);
        let cmds = s.ai_commands(PlayerId(0)); // founds
        s.step(&cmds);
        let start = s.money(PlayerId(0)).to_bits();
        for _ in 0..2400 {
            let c = s.ai_commands(PlayerId(0));
            s.step(&c);
        }
        assert!(
            s.money(PlayerId(0)).to_bits() > start,
            "post-founding economy should mine money"
        );
        assert_eq!(
            s.unit_count(PlayerId(1)),
            0,
            "no enemy units during the founding peace window"
        );
    }

    #[test]
    fn a_recorded_match_replays_to_the_same_result() {
        // Save = (seed, input log). Replaying the log from the same seed
        // reproduces the exact final state — the determinism-based save/replay.
        let mut original = lane_defense(5);
        let mut log = Vec::new();
        for _ in 0..400 {
            let enemy = original.ai_commands(PlayerId(1));
            original.step(&enemy);
            log.push(enemy);
        }
        let expected = original.state_hash();

        let mut replay = lane_defense(5);
        for batch in &log {
            replay.step(batch);
        }
        assert_eq!(replay.state_hash(), expected);
    }
}
