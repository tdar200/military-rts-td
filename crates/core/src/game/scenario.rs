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
        remaining: 11_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 6_000,
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
        first_delay: 300,
        interval: 600,
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
        remaining: 11_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 6_000,
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
        remaining: 11_000,
    };
    let alloy = Deposit {
        kind: DepositKind::Alloy,
        remaining: 6_000,
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
        first_delay: 450,
        interval: 800,
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
            remaining: 14_000,
        },
    );
    let mut sim = Sim::new(map, seed, Fixed::from_int(1800));

    // Player base (left margin, kept clear by procgen).
    sim.add_building(HUMAN, BuildingKind::CommandCenter, 3, mid);
    sim.add_building(HUMAN, BuildingKind::PowerPlant, 2, mid - 2);
    sim.add_building(HUMAN, BuildingKind::Refinery, 2, mid + 2);
    sim.add_building(HUMAN, BuildingKind::Barracks, 5, mid);

    // Endurance run: you outlast the waves rather than race to a win. Losing your
    // own Command Center ends it; the alien beachhead is just the wave source.
    sim.set_survival_mode(true);

    // Alien beachhead (right margin): a Core Node + power that pours out the waves.
    sim.add_building(ENEMY, BuildingKind::CommandCenter, w - 4, mid);
    sim.add_building(ENEMY, BuildingKind::PowerPlant, w - 3, mid - 2);

    // Escalating waves from the beachhead toward the player.
    sim.set_waves(WaveConfig {
        first_delay: 5400,
        interval: 540,
        base_size: 2,
        growth: 1,
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
    use super::{crossroads, lane_defense, open_clash, survival, Scenario};
    use crate::game::map::Map;
    use crate::game::path::find_path;
    use crate::game::sim::PlayerId;
    use alloc::vec::Vec;

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
        // No air on this map, so the AI builds no AA. The four essentials
        // (PowerPlant/Refinery/Barracks/CommandCenter) are pre-placed, so the AI
        // only adds one ResearchLab per side — 8 starting + 2 labs = 10 total.
        let buildings = s.entity_count() - after;
        assert_eq!(
            buildings, 10,
            "AI built unexpected structures on open_clash"
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
        for _ in 0..320 {
            s.step(&[]);
        }
        // first_delay is 300, so a wave has spawned for the enemy by now
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
    fn survival_sets_up_both_bases_and_stays_connected() {
        let s = survival(7);
        assert_eq!(s.winner(), None, "a base is already dead");
        // 4 player buildings + 2 beachhead buildings.
        assert!(s.entity_count() >= 6, "too few starting buildings");
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
    fn survival_overruns_an_undefended_base() {
        // Player does nothing; the enemy AI (+ escalating waves once the grace
        // period expires) must eventually take the base so the run resolves with
        // no soft-lock. Wave-spawn coverage is handled by
        // `survival_has_a_three_minute_grace_period`.
        let mut s = survival(3);
        let mut winner = None;
        for _ in 0..20000 {
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
    fn survival_has_a_three_minute_grace_period() {
        let mut s = survival(7);
        // 30 Hz -> 3 minutes = 5400 ticks. No enemy units before then.
        for _ in 0..5000 {
            s.step(&[]);
        }
        assert_eq!(
            s.unit_count(PlayerId(1)),
            0,
            "no waves should spawn during the grace period"
        );
        for _ in 0..1000 {
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
        for t in 0..18_000u64 {
            let cmds = s.ai_commands(PlayerId(0)); // player-AI builds + fights
            s.step(&cmds);
            let w = s.waves_survived();
            if w != last_waves {
                last_waves = w;
                std::eprintln!(
                    "wave {} @ t={} ({}s): minerals={} research={} alloys={} units(P0)={} units(P1)={}",
                    w, t, t / 30,
                    s.minerals(PlayerId(0)).to_bits() / 65536,
                    s.research(PlayerId(0)).to_bits() / 65536,
                    s.alloys(PlayerId(0)).to_bits() / 65536,
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
            "END: winner={:?}, waves_survived={}, final minerals={}",
            winner,
            s.waves_survived(),
            s.minerals(PlayerId(0)).to_bits() / 65536
        );
    }

    #[test]
    fn survival_opening_economy_flows_during_the_peaceful_grace() {
        // The player's pre-placed Extractor now sits on a home ore deposit, so the
        // economy mines from the first tick — even with no player input.
        let mut s = survival(3);
        let start = s.minerals(PlayerId(0)).to_bits();
        for _ in 0..2000 {
            s.step(&[]);
        }
        assert!(
            s.minerals(PlayerId(0)).to_bits() > start,
            "opening economy should mine minerals from the home deposit"
        );
        // ...and the build-up stays peaceful (first wave is at tick 5400).
        assert_eq!(
            s.unit_count(PlayerId(1)),
            0,
            "no enemy units during the grace period"
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
