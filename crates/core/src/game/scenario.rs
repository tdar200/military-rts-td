//! Prebuilt scenarios — concrete maps + setups that realize the core fantasy.
//!
//! [`lane_defense`] is the attack/defend hybrid: your base on the left, the enemy
//! base on the right, a central wall band funnelling movement into a top and a
//! bottom lane, and escalating enemy waves. You defend with towers and units while
//! you can also push a lane to destroy the enemy Command Center.

use crate::fixed::Fixed;
use crate::game::kestrel;
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
    // Finite home ore: harvesters must deliver it to powered refineries.
    // Other deposits support longer games and exposed expansion routes.
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
    // Earthfront starts with the complete BASIC RTS loop: economy, a production
    // building, and infantry. Research expands the roster and defences; it must
    // never be a prerequisite for issuing the player's first army command. The
    // alien beachhead (P1) stays fully unlocked.
    sim.set_starting_unlocks(
        HUMAN,
        &[
            BuildingKind::CommandCenter,
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
            BuildingKind::Wall,
        ],
        &[UnitKind::Harvester, UnitKind::Infantry],
    );

    // Defend-and-counterattack mission: losing your Command Center is defeat;
    // destroying the alien Core Node is victory. Waves prevent a cheap unchecked
    // rush and force the player to establish an economy and combined-arms force.
    sim.set_survival_mode(true);
    sim.enable_earthfront();

    // Alien beachhead (right margin): a defended base, not a naked wave spawner.
    // Static guns and a garrison prevent a single early rifle squad from ending
    // the mission before its economy/tech decisions matter.
    sim.add_building(ENEMY, BuildingKind::CommandCenter, w - 4, mid);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, w - 3, mid - 2);
    sim.add_building(ENEMY, BuildingKind::Barracks, w - 3, mid + 2);
    sim.add_building(ENEMY, BuildingKind::GunTurret, w - 7, mid - 2);
    sim.add_building(ENEMY, BuildingKind::GunTurret, w - 7, mid + 2);
    for dy in [-2, -1, 1, 2] {
        sim.add_unit(
            ENEMY,
            UnitKind::Infantry,
            Vec2::new(
                Fixed::from_int(i32::from(w) - 6),
                Fixed::from_int(i32::from(mid) + dy),
            ),
        );
    }

    // Optional logistical objectives screen the two approaches to the Core Node.
    // Clear small pads without filling the central route with impassable structures.
    for y in [mid - 5, mid + 5] {
        let x = w - 13;
        for dy in y - 2..=y + 2 {
            for dx in x - 2..=x + 2 {
                sim.map_mut().set_tile(dx, dy, Tile::OPEN);
            }
        }
        sim.add_alien_relay(ENEMY, x, y);
        sim.add_building(ENEMY, BuildingKind::GunTurret, x - 1, y - 1);
        sim.add_building(ENEMY, BuildingKind::AaTurret, x + 1, y + 1);
        sim.add_unit(
            ENEMY,
            UnitKind::AntiArmor,
            Vec2::new(
                Fixed::from_int(i32::from(x)),
                Fixed::from_int(i32::from(y + 1)),
            ),
        );
    }
    sim.add_building(ENEMY, BuildingKind::PowerPlant, w - 2, mid + 4);

    // Escalating waves from the beachhead toward the player.
    sim.set_waves(WaveConfig {
        // Ninety-second founding grace, then three-minute expeditions.
        // Earthfront locks tactical doctrine 45 seconds before arrival.
        first_delay: 2_700,
        interval: 5_400,
        // Earthfront uses bounded escalation plus two units per powered relay;
        // these base values also describe the baseline without relay support.
        base_size: 6,
        growth: 2,
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

/// Kestrel Reach: the fixed, hand-authored Earthfront map ([`kestrel`]).
///
/// The same mission as [`survival`] (Earthfront rules, the alien Core district,
/// two defended relays, escalating waves, basic starting unlocks) on the
/// authored river basin instead of a procgen field. The home base is already
/// founded at [`kestrel::HOME_CC`] (no survey phase), exactly as a `FoundBase`
/// there would found it; the alien district is re-anchored on
/// [`kestrel::CORE_NODE`] with `survival`'s relative offsets, and waves muster at
/// [`kestrel::HOLDFAST`] and must cross the Wyllow Ford.
#[must_use]
pub fn kestrel_reach(seed: u64) -> Sim {
    let mut sim = Sim::new(kestrel::build_map(), seed, Fixed::from_int(1800));
    let at = |(x, y): (u16, u16)| crate::game::hex::center(x, y);

    sim.set_starting_unlocks(
        HUMAN,
        &[
            BuildingKind::CommandCenter,
            BuildingKind::PowerPlant,
            BuildingKind::Refinery,
            BuildingKind::Barracks,
            BuildingKind::Wall,
        ],
        &[UnitKind::Harvester, UnitKind::Infantry],
    );
    sim.set_survival_mode(true);
    sim.enable_earthfront();
    // `enable_earthfront` turns every deposit into ore. Restore the authored
    // Ironback Ridge alloy seams afterwards so the ridge keeps its alloy (the map
    // contract). Earthfront trucks only mine ore, so the seams are not harvested.
    for (x, y, d) in kestrel::DEPOSITS {
        if d.kind == DepositKind::Alloy {
            sim.map_mut().set_deposit(x, y, d);
        }
    }

    // Home colony, founded as `Command::FoundBase` founds it: the Command Center,
    // a manual (autonomy 0) colony and four Earthfront rifle squads. The home ore
    // is two hexes away, so no founding ore bonus applies (as in `survival`).
    let (hx, hy) = kestrel::HOME_CC;
    let cc = sim.add_building(HUMAN, BuildingKind::CommandCenter, hx, hy);
    sim.add_colony(HUMAN, cc, 0);
    for i in 0..4 {
        sim.add_unit(
            HUMAN,
            UnitKind::Infantry,
            at(kestrel::HOME_CC) + Vec2::new(Fixed::ONE, Fixed::from_int(i)),
        );
    }

    // Alien holdfast on the east flats: `survival`'s Core district, re-anchored on
    // the Core Node with the same relative offsets.
    let (cx, cy) = kestrel::CORE_NODE;
    sim.add_building(ENEMY, BuildingKind::CommandCenter, cx, cy);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, cx + 1, cy - 2);
    sim.add_building(ENEMY, BuildingKind::Barracks, cx + 1, cy + 2);
    sim.add_building(ENEMY, BuildingKind::GunTurret, cx - 3, cy - 2);
    sim.add_building(ENEMY, BuildingKind::GunTurret, cx - 3, cy + 2);
    for dy in [-2, -1, 1, 2] {
        sim.add_unit(
            ENEMY,
            UnitKind::Infantry,
            at((cx - 2, cy.saturating_add_signed(dy))),
        );
    }

    // The two relay outposts screen the approaches from the ford: one on the
    // Ironback Ridge (north), one on the flats (south, two hexes further east
    // than `survival`'s offset so it stands clear of the riverbank). The authored
    // ground there is open, so no pad clearing is needed (clearing would also
    // erase river tiles' impassability).
    for (x, y) in [(cx - 9, cy - 5), (cx - 7, cy + 5)] {
        sim.add_alien_relay(ENEMY, x, y);
        sim.add_building(ENEMY, BuildingKind::GunTurret, x - 1, y - 1);
        sim.add_building(ENEMY, BuildingKind::AaTurret, x + 1, y + 1);
        sim.add_unit(ENEMY, UnitKind::AntiArmor, at((x, y + 1)));
    }
    sim.add_building(ENEMY, BuildingKind::PowerPlant, cx + 2, cy + 4);

    // Escalating waves from the holdfast toward the player (`survival`'s config).
    sim.set_waves(WaveConfig {
        first_delay: 2_700,
        interval: 5_400,
        base_size: 6,
        growth: 2,
        spawn: at(kestrel::HOLDFAST),
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
    /// Standing Infantry pre-placed at the favoured civ's forward base. Kept BELOW
    /// the AI's assault-commit threshold (`ASSAULT_STACK`, 14) so the forward base
    /// must MASS before it can assault — a sustained grind, never an instant
    /// homeworld delete (the old value of 32 captured an idle neighbour in ~8s).
    const EDGE_GARRISON: i32 = 10;

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
        // NEVER aim an AI's forward base at the human (Earth / civ 0): the human
        // starts MANUAL and army-light, so a forward base next door would delete
        // Earth before the player can act. When the human IS the favoured civ it
        // may still forward-base an AI rival.
        let rival = (0..8)
            .filter(|&p| owner[p].is_some() && owner[p] != Some(PlayerId(edge_civ)))
            .filter(|&p| edge_civ == 0 || owner[p] != Some(PlayerId(0)))
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

    // The human (civ 0, Earth) starts MANUAL with zero army while every AI is fully
    // autonomous and already producing; without a footing, Earth is overrun before the
    // player can build or train anything. A small starting garrison offsets that
    // manual-vs-autonomous opening gap so the opening is survivable and the agency
    // tools (alerts, control groups, attack-move) are reachable in real play.
    // Conquest-only ⇒ golden-neutral (the golden replay uses survival()).
    {
        const HUMAN_GARRISON: i32 = 6;
        let (ex, ey) = SOLAR[EARTH];
        let c = hex::center(ex, ey);
        for n in 0..HUMAN_GARRISON {
            let pos = Vec2::new(
                c.x + Fixed::from_int(n % 3 - 1),
                c.y + Fixed::from_int(3 + n / 3),
            );
            sim.add_unit(PlayerId(0), UnitKind::Infantry, pos);
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
    /// [`survival`] — procedural Earth defence, endless escalating alien waves.
    /// Deliberately excluded from [`Scenario::ALL`] (the skirmish roster): it is
    /// its own mode with its own tests, launched separately by the shell.
    Survival,
    /// [`kestrel_reach`] — the fixed Kestrel Reach river basin under Earthfront
    /// rules. Like Survival, excluded from [`Scenario::ALL`].
    KestrelReach,
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
            Self::Survival => "Earthfront",
            Self::KestrelReach => kestrel::MAP_NAME,
        }
    }

    /// A one-line description for the map-select menu.
    #[must_use]
    pub const fn tagline(self) -> &'static str {
        match self {
            Self::LaneDefense => "Hold the approach lanes against alien waves",
            Self::OpenClash => "Open-field clash — no walls, no waves",
            Self::Crossroads => "Flank a central wreck under pressure",
            Self::Survival => "Build, command, defend Earth, and counterattack in real time",
            Self::KestrelReach => "A coastal river basin. Hold the ford.",
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
            Self::KestrelReach => kestrel_reach(seed),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        conquest, crossroads, kestrel_reach, lane_defense, open_clash, survival, Scenario,
    };
    use crate::game::civ::ColonyId;
    use crate::game::map::Map;
    use crate::game::path::find_path;
    use crate::game::planet::PlanetId;
    use crate::game::sim::{Command, PlayerId};
    use crate::game::stats::{BuildingKind, UnitKind};
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
            Scenario::KestrelReach,
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
        // actually happening), not panic, and reach a decisive winner. A selectable
        // skirmish which can attrition-loop forever is not a complete RTS match.
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
            assert!(resolved_at.is_some(), "{}: scenario soft-locked", sc.name());
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
        assert!(
            s.building_unlocked(PlayerId(0), BuildingKind::Barracks),
            "Earthfront must expose basic production before research"
        );
        assert!(
            s.unit_unlocked(PlayerId(0), UnitKind::Infantry),
            "Earthfront must expose a basic combat unit before research"
        );
        // The Core district and two relay outposts are pre-placed; the human
        // still chooses where to deploy.
        assert_eq!(
            s.entity_count(),
            18,
            "Core district plus two defended relays"
        );
        assert_eq!(s.alien_relay_count(PlayerId(1), false), 2);
        let cmds = s.ai_commands(PlayerId(0));
        s.step(&cmds);
        assert!(!s.surveying(), "founding ends survey");
        assert_eq!(
            s.entity_count(),
            23,
            "the human CC and four starting squads now exist"
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
        // The survival human starts with basic infantry production; driven by
        // ai_commands it must still research its way to a lab and a later era,
        // while fielding a standing army — proving progression is not soft-locked.
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
            if got_lab && got_era && got_army {
                break;
            }
        }
        assert!(got_lab, "human should research the Lab (Orbital Logistics)");
        assert!(got_era, "human should advance at least one era: economy={:?}, research={:?}, money={:?}, winner={:?}", s.economy_view(PlayerId(0)), s.research_state(PlayerId(0)), s.money(PlayerId(0)), s.winner());
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
        let garrison = s.unit_count(PlayerId(1));
        assert_eq!(garrison, 6, "Core and relay garrisons are defensive");
        // 30 Hz -> first_delay 2_700 ticks (~90s) from founding. The garrison
        // remains, but no additional attack wave appears before that deadline.
        for _ in 0..2_500 {
            s.step(&[]);
        }
        assert_eq!(
            s.unit_count(PlayerId(1)),
            garrison,
            "no waves should spawn during the grace period"
        );
        for _ in 0..600 {
            s.step(&[]);
        }
        assert!(
            s.unit_count(PlayerId(1)) > garrison,
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
        let mut investment = 0_i64;
        for _ in 0..2400 {
            let c = s.ai_commands(PlayerId(0));
            investment += c
                .iter()
                .map(|command| match *command {
                    crate::game::sim::Command::Build { kind, .. } => {
                        s.building_cost(kind).to_bits()
                    }
                    crate::game::sim::Command::Train { kind, .. } => s.unit_cost(kind).to_bits(),
                    crate::game::sim::Command::Research { tech_id, .. } => s
                        .technology(tech_id)
                        .map_or(0, |n| i64::from(n.money) * 65536),
                    _ => 0,
                })
                .sum::<i64>();
            s.step(&c);
        }
        assert!(
            s.money(PlayerId(0)).to_bits() + investment > start,
            "post-founding economy should mine money"
        );
        assert_eq!(
            s.unit_count(PlayerId(1)),
            6,
            "the base and relay garrisons remain, but no attack wave spawns during the peace window"
        );
    }

    #[test]
    fn kestrel_text_map_is_44_by_26_and_all_glyphs_known() {
        use crate::game::{kestrel::ROWS, map::Ground};
        assert_eq!(ROWS.len(), 26);
        for row in ROWS {
            assert_eq!(row.chars().count(), 44, "row: {row}");
            assert!(row.chars().all(|c| Ground::from_glyph(c).is_some()));
        }
    }

    #[test]
    fn kestrel_regions_match_the_text_map() {
        use crate::game::kestrel::{Region, HOLDFAST, HOME_CC, MAP_NAME, REGIONS, ROWS};
        let region = |name: &str| -> &Region {
            REGIONS
                .iter()
                .find(|r| r.name == name)
                .unwrap_or_else(|| panic!("missing region {name}"))
        };
        let inside = |r: &Region, (x, y): (u16, u16)| {
            (r.x0..=r.x1).contains(&x) && (r.y0..=r.y1).contains(&y)
        };
        assert_eq!(MAP_NAME, "Kestrel Reach");
        for r in &REGIONS {
            assert!(
                r.x0 <= r.x1 && r.x1 < 44 && r.y0 <= r.y1 && r.y1 < 26,
                "{}",
                r.name
            );
        }
        // Every river, ford, sea and highland glyph lies inside its named region.
        for (y, row) in ROWS.iter().enumerate() {
            for (x, c) in row.chars().enumerate() {
                let at = (u16::try_from(x).unwrap(), u16::try_from(y).unwrap());
                let name = match c {
                    'r' => "Calder River",
                    'w' => "Wyllow Ford",
                    'o' => "Kestrel Bay",
                    'h' => "Ironback Ridge",
                    'c' => "The Dry Flats",
                    _ => continue,
                };
                assert!(inside(region(name), at), "{c} at {at:?} outside {name}");
            }
        }
        // The river band touches every row of the Calder River bounds down to the bay.
        let calder = region("Calder River");
        assert!(ROWS[usize::from(calder.y0)].contains('r'));
        // Hollow Wood is mostly forest; the colony and Sunfield hold the home CC.
        let wood = region("Hollow Wood");
        let (mut trees, mut cells) = (0, 0);
        for y in wood.y0..=wood.y1 {
            for x in wood.x0..=wood.x1 {
                cells += 1;
                trees += usize::from(ROWS[usize::from(y)].as_bytes()[usize::from(x)] == b't');
            }
        }
        assert!(trees * 2 > cells, "Hollow Wood: {trees}/{cells} forest");
        assert!(inside(region("Colony"), HOME_CC));
        assert!(inside(region("Sunfield"), HOME_CC));
        assert!(inside(region("The Dry Flats"), HOLDFAST));
    }

    #[test]
    fn kestrel_reach_builds_and_ground_matches_text() {
        let sim = kestrel_reach(2026);
        assert_eq!(sim.map().width(), 44);
        assert_eq!(sim.map().height(), 26);
        // Earthfront with the home Command Centre already standing at HOME_CC: its
        // 10 kW only counts under the Earthfront economy.
        assert!(
            !sim.surveying(),
            "Kestrel Reach opens with the base founded"
        );
        assert!(sim.economy_view(PlayerId(0)).generation >= 10);
        assert_eq!(sim.colony_count_for(PlayerId(0)), 1);
        let (cx, cy) = crate::game::kestrel::HOME_CC;
        assert!(
            !sim.map()
                .tile(i32::from(cx), i32::from(cy))
                .unwrap()
                .passable
        );
        for (y, row) in crate::game::kestrel::ROWS.iter().enumerate() {
            for (x, c) in row.chars().enumerate() {
                let (x, y) = (i32::try_from(x).unwrap(), i32::try_from(y).unwrap());
                assert_eq!(sim.map().ground_at(x, y).glyph(), c, "({x},{y})");
            }
        }
    }

    #[test]
    fn kestrel_river_is_crossable_only_at_the_ford() {
        use crate::game::kestrel::{ford_tiles, HOLDFAST, HOME_CC};
        use crate::game::map::Ground;
        let sim = kestrel_reach(2026);
        assert_eq!(ford_tiles().count(), 2, "the Wyllow Ford is two hexes");
        let path = find_path(sim.map(), HOME_CC, HOLDFAST).expect("ford connects the banks");
        assert!(path
            .iter()
            .any(|&(x, y)| sim.map().ground_at(x.into(), y.into()) == Ground::Ford));
        // Plug the ford: no path.
        let mut s2 = kestrel_reach(2026);
        for (x, y) in ford_tiles() {
            s2.map_mut().set_ground(x, y, Ground::River);
        }
        assert!(find_path(s2.map(), HOME_CC, HOLDFAST).is_none());
        // Hex flood fill (six odd-q neighbours) from home with the ford plugged: no
        // diagonal leak reaches ANY tile east of the river band.
        let map = s2.map();
        let (w, h) = (map.width(), map.height());
        let mut seen = alloc::vec![false; usize::from(w) * usize::from(h)];
        let mut stack = alloc::vec![HOME_CC];
        let idx = |(x, y): (u16, u16)| usize::from(y) * usize::from(w) + usize::from(x);
        seen[idx(HOME_CC)] = true;
        while let Some((x, y)) = stack.pop() {
            for (nx, ny) in crate::game::hex::neighbors(x, y) {
                let (Ok(nx), Ok(ny)) = (u16::try_from(nx), u16::try_from(ny)) else {
                    continue;
                };
                if nx >= w || ny >= h || seen[idx((nx, ny))] {
                    continue;
                }
                if map.ground_at(nx.into(), ny.into()).props().passable {
                    seen[idx((nx, ny))] = true;
                    stack.push((nx, ny));
                }
            }
        }
        // Per row, the river band (or, below the river mouth, the bay) starts at the
        // first 'r'/'w'/'o' glyph of the authored text; everything from there east
        // is the far side. Reachable == exactly the passable tiles west of it.
        for (y, row) in (0u16..).zip(crate::game::kestrel::ROWS) {
            let band = row
                .find(['r', 'w', 'o'])
                .unwrap_or_else(|| panic!("row {y} has no river or bay"));
            for x in 0..w {
                let west = usize::from(x) < band;
                let passable = map.ground_at(x.into(), y.into()).props().passable;
                assert_eq!(
                    seen[idx((x, y))],
                    west && passable,
                    "flood fill mismatch at ({x},{y}): west={west} passable={passable}"
                );
            }
        }
    }

    /// Orders a fresh infantry at `from` to `to` on Kestrel Reach and steps 300
    /// ticks; returns the unit's final tile.
    fn kestrel_walk(from: (u16, u16), to: (u16, u16)) -> (crate::game::sim::Sim, (u16, u16), bool) {
        use crate::game::hex;
        let mut sim = kestrel_reach(2026);
        let unit = sim.add_unit(PlayerId(0), UnitKind::Infantry, hex::center(from.0, from.1));
        // Garrisons and relays are hostile: keep the walker alive so the test
        // measures movement only.
        sim.debug_set_hp(unit, crate::fixed::Fixed::from_int(1_000_000));
        let target = hex::center(to.0, to.1);
        sim.step(&[Command::Move {
            owner: PlayerId(0),
            unit,
            target,
        }]);
        let mut passable_every_tick = true;
        let mut visited_ford = false;
        for _ in 0..300 {
            sim.step(&[]);
            if let Some(p) = sim.position(unit) {
                let (x, y) = hex::from_world(p, sim.map().width(), sim.map().height());
                let g = sim.map().ground_at(x.into(), y.into());
                passable_every_tick &= g.props().passable;
                visited_ford |= g == crate::game::map::Ground::Ford;
            }
        }
        assert!(passable_every_tick, "unit stepped onto an impassable tile");
        let p = sim.position(unit).expect("unit alive");
        let tile = hex::from_world(p, sim.map().width(), sim.map().height());
        (sim, tile, visited_ford)
    }

    #[test]
    fn kestrel_ground_unit_ordered_onto_river_or_sea_stays_on_passable_ground() {
        use crate::game::map::Ground;
        for (from, to, ground) in [
            ((12, 2), (16, 2), Ground::River),
            ((27, 23), (32, 24), Ground::Sea),
        ] {
            let (sim, (x, y), _) = kestrel_walk(from, to);
            assert_eq!(
                sim.map().ground_at(i32::from(to.0), i32::from(to.1)),
                ground
            );
            assert!(
                sim.map().ground_at(x.into(), y.into()).props().passable,
                "unit ended on impassable ({x},{y}) after ordered onto {ground:?}"
            );
        }
    }

    #[test]
    fn kestrel_east_bank_unit_ordered_onto_river_never_stands_in_it_or_skips_the_ford() {
        use crate::game::map::Ground;
        // From the east bank, order the unit onto river tiles. Without the fix the final
        // straight leg walks it into the water. Whichever bank the substitute goal lands on,
        // it must be passable ground, and the west bank is reachable only through the ford.
        for to in [(16, 2), (17, 2), (22, 9)] {
            let (sim, (x, y), visited_ford) = kestrel_walk((26, 10), to);
            assert_eq!(
                sim.map().ground_at(i32::from(to.0), i32::from(to.1)),
                Ground::River
            );
            assert!(
                sim.map().ground_at(x.into(), y.into()).props().passable,
                "ordered onto river {to:?}, unit ended in the water at ({x},{y})"
            );
            let band = crate::game::kestrel::ROWS[usize::from(y)]
                .find(['r', 'w'])
                .expect("every row has a river band");
            let west_bank = usize::from(x) < band;
            assert!(
                !west_bank || visited_ford,
                "ordered onto {to:?}: reached the west bank at ({x},{y}) without using the ford"
            );
        }
    }

    #[test]
    fn kestrel_apply_build_rejects_non_buildable_ground() {
        use crate::game::map::Ground;
        let build_at = |ground: Ground| {
            let mut sim = kestrel_reach(2026);
            sim.map_mut().set_ground(9, 9, ground);
            let before = sim.buildings_owned_by(PlayerId(0));
            sim.step(&[Command::Build {
                owner: PlayerId(0),
                kind: BuildingKind::Wall,
                x: 9,
                y: 9,
            }]);
            sim.buildings_owned_by(PlayerId(0)) - before
        };
        assert_eq!(build_at(Ground::Grass), 1, "control: grass is buildable");
        for g in [
            Ground::Shore,
            Ground::Crater,
            Ground::River,
            Ground::Sea,
            Ground::Ford,
        ] {
            assert_eq!(build_at(g), 0, "{g:?} must not accept a building");
        }
    }

    #[test]
    fn kestrel_rally_set_on_water_resolves_to_a_passable_tile() {
        use crate::game::hex;
        let mut sim = kestrel_reach(2026);
        let barracks = sim.add_building(PlayerId(0), BuildingKind::Barracks, 9, 9);
        for water in [(16, 2), (32, 24)] {
            sim.step(&[Command::SetRally {
                owner: PlayerId(0),
                producer: barracks,
                target: hex::center(water.0, water.1),
            }]);
            let rally = sim
                .views()
                .into_iter()
                .find(|v| v.id == barracks)
                .and_then(|v| v.rally)
                .expect("rally set");
            let (x, y) = hex::from_world(rally, sim.map().width(), sim.map().height());
            assert!(
                sim.map().ground_at(x.into(), y.into()).props().passable,
                "rally for {water:?} landed on impassable ({x},{y})"
            );
        }
    }

    /// A returning harvester is ordered to a Refinery, which is a building (impassable), so
    /// `order_unit_to` stores the adjacent passable tile as the move target. The harvester
    /// loop must compare against the order it GAVE, or it re-paths every truck every tick.
    #[test]
    fn survival_returning_harvesters_do_not_repath_every_tick() {
        let mut s = survival(3);
        for _ in 0..8000u64 {
            let mut cmds = s.ai_commands(PlayerId(0));
            if s.waves_survived() > 0 {
                cmds.extend(s.ai_commands(PlayerId(1)));
            }
            s.step(&cmds);
        }
        // Measured 4122 order_unit_to calls (and P0 money 2597) at tick 8000 on the fixed
        // code and on 10ab36a; the every-tick re-path bug made it 11644 (money 4365).
        assert!(
            s.order_calls_for_test() < 6000,
            "order_unit_to called {} times in 8000 ticks: harvesters are re-pathing every tick",
            s.order_calls_for_test()
        );
        assert_eq!(
            s.money(PlayerId(0)).to_bits() / 65536,
            2597,
            "survival(3) P0 money at tick 8000"
        );
    }

    #[test]
    fn kestrel_reach_is_deterministic_and_replays() {
        let (mut a, mut b) = (kestrel_reach(7), kestrel_reach(7));
        for _ in 0..600 {
            a.step(&[]);
            b.step(&[]);
        }
        assert_eq!(a.state_hash(), b.state_hash());
        // Full both-sides command log replays bit-identically (spec 4.6 replay).
        let mut original = kestrel_reach(5);
        let mut log = Vec::new();
        for _ in 0..3000 {
            let mut cmds = original.ai_commands(PlayerId(0));
            cmds.extend(original.ai_commands(PlayerId(1)));
            original.step(&cmds);
            log.push(cmds);
        }
        let mut replay = kestrel_reach(5);
        for batch in &log {
            replay.step(batch);
        }
        assert_eq!(
            replay.state_hash(),
            original.state_hash(),
            "Kestrel replay diverged"
        );
    }

    #[test]
    fn kestrel_reach_has_ore_on_both_banks_and_alloy_on_the_ridge() {
        use crate::game::map::{DepositKind, Ground};
        let sim = kestrel_reach(2026);
        let map = sim.map();
        let (mut west, mut east, mut alloy) = (0, 0, 0);
        for (x, y, d) in map.deposits() {
            let g = map.ground_at(i32::from(x), i32::from(y));
            match d.kind {
                DepositKind::Ore if x < 20 => west += 1,
                DepositKind::Ore => east += 1,
                DepositKind::Alloy if g == Ground::Highland => alloy += 1,
                DepositKind::Alloy => {}
            }
        }
        assert!(
            west >= 3 && east >= 2 && alloy >= 2,
            "west={west} east={east} alloy={alloy}"
        );
        // A buildable river-side plant site (Task 6 river bonus) that is also a
        // refinery site within 1 hex of ore (Task 6 ore bonus) exists on the west bank.
        let riverside = |x: u16, y: u16| {
            crate::game::hex::neighbors(x, y)
                .iter()
                .any(|&(nx, ny)| map.ground_at(nx, ny) == Ground::River)
        };
        let site = (0..map.height()).any(|y| {
            (0..20).any(|x| {
                map.tile(i32::from(x), i32::from(y)).unwrap().buildable
                    && riverside(x, y)
                    && map.deposits().any(|(dx, dy, d)| {
                        d.kind == DepositKind::Ore
                            && crate::game::hex::distance((x, y), (dx, dy)) <= 1
                    })
            })
        });
        assert!(
            site,
            "no river-side plant/refinery site beside west-bank ore"
        );
    }

    /// Waves the AI-defended Kestrel base must hold: the ported playtest's one
    /// tunable threshold. `survival_balance_playtest` (seed 3) holds 3 waves and
    /// falls at t=14489; Kestrel Reach (seed 3) also holds 3, falling at t=13917.
    const KESTREL_DEFENDED_WAVES: u32 = 3;

    #[test]
    fn kestrel_reach_overruns_an_undefended_base_and_holds_with_the_playtest_defence() {
        // Port of `survival_overruns_an_undefended_base`: the player does nothing;
        // the enemy AI (+ escalating waves once the grace period expires) must take
        // the base so the run resolves with no soft-lock. Kestrel Reach opens with
        // the base already founded at HOME_CC, so there is no founding step.
        let mut s = kestrel_reach(3);
        assert!(!s.surveying());
        let mut winner = None;
        let mut undefended_fell_at = 0;
        for t in 0..40000u64 {
            let enemy = s.ai_commands(PlayerId(1));
            s.step(&enemy);
            if let Some(w) = s.winner() {
                winner = Some(w);
                undefended_fell_at = t;
                break;
            }
        }
        assert_eq!(
            winner,
            Some(PlayerId(1)),
            "undefended Kestrel Reach never resolved"
        );

        // Port of `survival_balance_playtest`: a competent AI plays the PLAYER side
        // against the waves; the beachhead AI acts once the first wave has spawned,
        // mirroring the shell. The defence must hold several waves and outlast the
        // undefended base.
        let mut s = kestrel_reach(3);
        let mut resolved_at = None;
        for t in 0..140_000u64 {
            let mut cmds = s.ai_commands(PlayerId(0));
            if s.waves_survived() > 0 {
                cmds.extend(s.ai_commands(PlayerId(1)));
            }
            s.step(&cmds);
            if s.winner().is_some() {
                resolved_at = Some(t);
                break;
            }
        }
        assert!(
            s.waves_survived() >= KESTREL_DEFENDED_WAVES,
            "defended Kestrel base held only {} waves",
            s.waves_survived()
        );
        assert!(
            resolved_at.is_none_or(|t| t > undefended_fell_at),
            "the playtest defence must outlast an undefended base"
        );
    }

    #[test]
    fn kestrel_reach_is_its_own_mode_outside_the_skirmish_roster() {
        assert!(!Scenario::ALL.contains(&Scenario::KestrelReach));
        assert_eq!(Scenario::KestrelReach.name(), "Kestrel Reach");
        assert_eq!(
            Scenario::KestrelReach.tagline(),
            "A coastal river basin. Hold the ford."
        );
        assert_eq!(
            Scenario::KestrelReach.build(9).state_hash(),
            kestrel_reach(9).state_hash()
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
