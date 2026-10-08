//! The Godot bridge's text protocol, shared by the `godot-bridge` binary and
//! replay tools (Task 24): the player's command lines, the client's
//! `match.json`, and replay files.
//!
//! # Replay files
//!
//! A replay is a text file named `<unix seconds>_<scenario>_<seed>.rpl` (a
//! `_2`, `_3`, ... suffix when that name is taken) in the absolute directory
//! `match.json` names as `replay_dir`:
//!
//! ```text
//! RPL1
//! version=0.1.0
//! scenario=kestrel
//! seed=77
//! difficulty=normal
//! run=true
//! perk_pool=255
//! fog=true
//! balance=<FNV-1a 64 of the shipped balance.ron>
//!
//! T <tick> <raw player line>
//! END <tick> <state hash> <score>
//! ```
//!
//! The `END` numbers are zero-padded to 20 characters so the line keeps one
//! width as it is rewritten (see [`ReplayWriter::checkpoint`]).
//!
//! A `T` line is one player line the bridge applied, against `sim.tick()`
//! before the step that applied it, in the order applied. Only player lines
//! are logged: the host commands (survey AI, alien AI, scenario script) are
//! rebuilt by [`Scenario::host_commands`]. Only lines that parsed and passed
//! the bridge's fog filter are logged, so a replay applies its lines as they
//! stand and never needs the fog state (`fog` in the header is informational:
//! the presentation the player saw). `END` is the state after the last
//! stepped tick: the bridge rewrites it after every step, so the file ends
//! with a current `END` whether the match is won, restarted, quit or killed.
//! Re-simulating `header.scenario` at `header.seed` with its options and the
//! shipped balance, stepping the host commands plus the logged lines of each
//! tick from 0 to the `END` tick, reproduces the `END` hash and score.
//!
//! # Verification and playback (Task 25)
//!
//! [`verify`] (the `verify-run` binary) re-simulates a replay headless and
//! compares the tick, hash and score it reaches with the file's `END`. The
//! bridge's `--replay <file>` (or a `replay` path in `match.json`) plays one
//! back through the normal snapshot path with [`ReplayPlayback`], at the speed
//! in `replay_speed.txt` ([`parse_speed`]). Both read the file with
//! [`ReplayPlayer`], which treats it as untrusted input, and both step through
//! [`step_tick`], the body the live bridge steps through, so recording,
//! verification and playback cannot drift.

use std::fmt::Write as _;
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write as _};
use std::path::{Path, PathBuf};

use rts_core::fixed::Fixed;
use rts_core::game::perk::DEFAULT_RUN_POOL;
use rts_core::game::scenario::{MatchOptions, Scenario};
use rts_core::game::sim::{
    order_point_in_range, Command, Difficulty, EntityId, PlayerId, Sim, Stance,
};
use rts_core::game::stats::{BuildingKind, UnitKind};
use rts_core::vec::Vec2;

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

/// The player's command for one text line, or `None` for a malformed or
/// unknown line.
///
/// Lines read `move,<id>,<x_bits>,<z_bits>`, `perk,<id>` and so on. Every
/// order is the human's (`PlayerId(0)`); fields after the ones a line kind
/// reads are ignored.
#[must_use]
#[allow(
    clippy::too_many_lines,
    reason = "a flat one-arm-per-line-kind parser, moved unchanged from the bridge (Task 24)"
)]
pub fn parse_command_line(line: &str) -> Option<Command> {
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
        // Run drafts (Kestrel, Task 23): `perk,<id>` takes a perk
        // from the pending draft; the core ignores any other id.
        "perk" => {
            let perk = fields.next()?.parse::<u32>().ok()?;
            Some(Command::ChoosePerk {
                owner: PlayerId(0),
                perk,
            })
        }
        _ => None,
    }
}

/// Takes every pending player line, raw and in order.
///
/// The legacy command file at `path` comes first, then the packets (`*.cmd`)
/// of the `commands` directory beside it in name order. Each file is removed
/// once read.
#[must_use]
pub fn read_command_lines(path: &Path) -> Vec<String> {
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
    contents.lines().map(str::to_owned).collect()
}

/// Every pending player command ([`read_command_lines`] then
/// [`parse_command_line`]; malformed lines are dropped).
#[must_use]
pub fn take_commands(path: &Path) -> Vec<Command> {
    read_command_lines(path)
        .iter()
        .filter_map(|line| parse_command_line(line))
        .collect()
}

/// The lines that parse and that `admit` lets through (the bridge's fog
/// filter), each with its command, in order: what a stepped frame applies
/// and what a replay logs.
pub fn accept_lines(
    lines: Vec<String>,
    mut admit: impl FnMut(&Command) -> bool,
) -> Vec<(String, Command)> {
    lines
        .into_iter()
        .filter_map(|line| {
            let command = parse_command_line(&line)?;
            admit(&command).then_some((line, command))
        })
        .collect()
}

/// The match the client asked for in `match.json`.
///
/// A key that is missing or malformed keeps its default (`fog: None` means
/// "as the environment says"; Task 20: seed 2026, difficulty Normal, the match
/// the bridge always built).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct MatchConfig {
    pub scenario: Scenario,
    pub fog: Option<bool>,
    pub seed: u64,
    pub difficulty: Difficulty,
    /// Task 23: a roguelite run (Kestrel only), false by default.
    pub run: bool,
    /// Task 23: the run's perk pool bitmask, `DEFAULT_RUN_POOL` (0xFF) by default.
    pub perk_pool: u32,
    /// Task 24: where this match's replay goes (the client's `user://replays`,
    /// globalized). Only an absolute path is taken; `None` records nothing.
    pub replay_dir: Option<PathBuf>,
    /// Task 25: a replay file to play back instead of a live match (an
    /// absolute path, as `replay_dir`; the bridge's `--replay` sets it for
    /// the boot match). The replay's own header names the match it plays.
    pub replay: Option<PathBuf>,
}

/// Task 20: the seed of a match whose `match.json` gives none (or a malformed one).
pub const DEFAULT_SEED: u64 = 2026;

impl MatchConfig {
    /// `scenario` with every other key at its default: the boot match, and the
    /// fallback for a missing or malformed `match.json`.
    #[must_use]
    pub const fn boot(scenario: Scenario) -> Self {
        Self {
            scenario,
            fog: None,
            seed: DEFAULT_SEED,
            difficulty: Difficulty::Normal,
            run: false,
            perk_pool: DEFAULT_RUN_POOL,
            replay_dir: None,
            replay: None,
        }
    }
}

/// Task 20: the sim for `cfg` (its scenario at its seed and difficulty, with the
/// shipped balance), as the bridge builds it at boot and on every restart.
#[must_use]
pub fn build_match(cfg: &MatchConfig) -> Sim {
    let mut sim = cfg.scenario.build_with(
        cfg.seed,
        MatchOptions {
            difficulty: cfg.difficulty,
            run: cfg.run,
            perk_pool: cfg.perk_pool,
        },
    );
    sim.set_balance(rts_data::load_default());
    sim
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

/// Task 24: `dir` as a replay directory (Task 25: or a replay file), only when
/// it is an absolute path with no JSON escape in it (the hand parser reads
/// strings raw, so a backslash would name another path). `res://`, `user://`
/// and relative paths are refused: the bridge never writes beside its runtime
/// files or the game.
fn replay_dir_from(dir: &str) -> Option<PathBuf> {
    let path = Path::new(dir);
    (!dir.contains('\\') && path.is_absolute()).then(|| path.to_path_buf())
}

/// Parses `match.json` (a flat JSON object written by the client).
///
/// Unknown keys are ignored; a malformed value keeps that key's default; text
/// that is not an object yields `fallback` with the environment's fog.
#[must_use]
pub fn parse_match_config(text: &str, fallback: Scenario) -> MatchConfig {
    let mut config = MatchConfig::boot(fallback);
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
    // Task 20: a bare unsigned integer seed and a quoted preset name.
    if let Some(RawValue::Bare(seed)) = raw_json_value(text, "seed") {
        if seed.bytes().all(|b| b.is_ascii_digit()) {
            config.seed = seed.parse().unwrap_or(DEFAULT_SEED);
        }
    }
    if let Some(RawValue::Quoted(name)) = raw_json_value(text, "difficulty") {
        config.difficulty = Difficulty::from_name(name).unwrap_or_default();
    }
    // Task 23: a bare boolean run flag and a bare unsigned integer pool.
    config.run = matches!(raw_json_value(text, "run"), Some(RawValue::Bare("true")));
    if let Some(RawValue::Bare(pool)) = raw_json_value(text, "perk_pool") {
        if pool.bytes().all(|b| b.is_ascii_digit()) {
            config.perk_pool = pool.parse().unwrap_or(DEFAULT_RUN_POOL);
        }
    }
    // Task 24: a quoted absolute directory for the replay.
    if let Some(RawValue::Quoted(dir)) = raw_json_value(text, "replay_dir") {
        config.replay_dir = replay_dir_from(dir);
    }
    // Task 25: a quoted absolute replay file to play back.
    if let Some(RawValue::Quoted(file)) = raw_json_value(text, "replay") {
        config.replay = replay_dir_from(file);
    }
    config
}

/// Reads and parses `match.json`; a missing or unreadable file yields `fallback`.
#[must_use]
pub fn read_match_config(path: &Path, fallback: Scenario) -> MatchConfig {
    std::fs::read_to_string(path).map_or_else(
        |_| MatchConfig::boot(fallback),
        |text| parse_match_config(&text, fallback),
    )
}

/// Maps a `--scenario` value to a scenario (Kestrel Reach is the default).
///
/// # Errors
///
/// Any name other than `kestrel` or `survival`, with a message naming it.
pub fn parse_scenario(value: &str) -> Result<Scenario, String> {
    match value {
        "survival" => Ok(Scenario::Survival),
        "kestrel" => Ok(Scenario::KestrelReach),
        other => Err(format!(
            "unknown scenario '{other}' (expected 'kestrel' or 'survival')"
        )),
    }
}

/// FNV-1a 64 of the shipped balance (`rts_data::DEFAULT_RON`, the balance the
/// bridge loads): a replay recorded under other numbers cannot verify.
#[must_use]
pub fn balance_hash() -> u64 {
    rts_data::DEFAULT_RON
        .bytes()
        .fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
        })
}

/// The first line of every replay file (the format version).
pub const REPLAY_MAGIC: &str = "RPL1";

/// The server version a replay records (`version=` in its header).
pub const REPLAY_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The scenarios a replay header names, by key.
const SCENARIO_KEYS: [(Scenario, &str); 5] = [
    (Scenario::KestrelReach, "kestrel"),
    (Scenario::Survival, "survival"),
    (Scenario::LaneDefense, "lane_defense"),
    (Scenario::OpenClash, "open_clash"),
    (Scenario::Crossroads, "crossroads"),
];

/// The header and file-name key of `scenario` (`kestrel`, `survival`, ...).
#[must_use]
pub fn scenario_key(scenario: Scenario) -> &'static str {
    SCENARIO_KEYS
        .iter()
        .find(|(s, _)| *s == scenario)
        .map_or("unknown", |(_, key)| key)
}

/// The header keys, in file order.
const HEADER_KEYS: [&str; 8] = [
    "version",
    "scenario",
    "seed",
    "difficulty",
    "run",
    "perk_pool",
    "fog",
    "balance",
];

/// Everything a replay needs to rebuild its match: the header of a replay
/// file (see the module docs).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ReplayHeader {
    /// The recording server's version ([`REPLAY_VERSION`]).
    pub version: String,
    pub scenario: Scenario,
    pub seed: u64,
    pub difficulty: Difficulty,
    pub run: bool,
    /// The run's perk pool as `match.json` gave it (the sim masks it).
    pub perk_pool: u32,
    /// The presentation fog the player had. Informational: the logged lines
    /// already passed the fog filter.
    pub fog: bool,
    /// [`balance_hash`] of the balance the match ran under.
    pub balance: u64,
}

/// A run of ASCII digits (no sign, no space) as a number.
fn digits<T: std::str::FromStr>(key: &str, value: &str) -> Result<T, String> {
    if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
        return Err(format!(
            "{key}: '{}' is not an unsigned integer",
            clip(value)
        ));
    }
    value
        .parse()
        .map_err(|_| format!("{key}: '{}' is out of range", clip(value)))
}

/// `true` or `false`.
fn boolean(key: &str, value: &str) -> Result<bool, String> {
    match value {
        "true" => Ok(true),
        "false" => Ok(false),
        other => Err(format!("{key}: '{other}' is not true or false")),
    }
}

impl ReplayHeader {
    /// The header of a replay of `cfg`'s match, with the fog the player has,
    /// this server's version and the shipped balance.
    #[must_use]
    pub fn for_match(cfg: &MatchConfig, fog: bool) -> Self {
        Self {
            version: REPLAY_VERSION.to_owned(),
            scenario: cfg.scenario,
            seed: cfg.seed,
            difficulty: cfg.difficulty,
            run: cfg.run,
            perk_pool: cfg.perk_pool,
            fog,
            balance: balance_hash(),
        }
    }

    /// The header as it opens a replay file: `RPL1`, one `key=value` line per
    /// field, then the blank line that ends the header.
    #[must_use]
    pub fn to_text(&self) -> String {
        format!(
            "{REPLAY_MAGIC}\nversion={}\nscenario={}\nseed={}\ndifficulty={}\nrun={}\n\
             perk_pool={}\nfog={}\nbalance={}\n\n",
            self.version,
            scenario_key(self.scenario),
            self.seed,
            self.difficulty.name(),
            self.run,
            self.perk_pool,
            self.fog,
            self.balance,
        )
    }

    /// Reads the header of a replay (the whole file or just its header): the
    /// `RPL1` line, then `key=value` lines up to the first blank line.
    ///
    /// # Errors
    ///
    /// A message when the magic line is missing, a key is unknown, repeated
    /// or missing, or a value is malformed. Nothing is defaulted: a header
    /// either names its whole match or is refused.
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut lines = text.lines();
        if lines.next() != Some(REPLAY_MAGIC) {
            return Err(format!(
                "not a replay: the first line is not {REPLAY_MAGIC}"
            ));
        }
        let mut values: [Option<&str>; HEADER_KEYS.len()] = [None; HEADER_KEYS.len()];
        for line in lines.take_while(|line| !line.is_empty()) {
            let (key, value) = line
                .split_once('=')
                .ok_or_else(|| format!("malformed header line '{line}'"))?;
            let slot = HEADER_KEYS
                .iter()
                .position(|k| *k == key)
                .ok_or_else(|| format!("unknown header key '{key}'"))?;
            if values[slot].replace(value).is_some() {
                return Err(format!("header key '{key}' appears twice"));
            }
        }
        let get = |key: &str| {
            HEADER_KEYS
                .iter()
                .position(|k| *k == key)
                .and_then(|slot| values[slot])
                .ok_or_else(|| format!("header key '{key}' is missing"))
        };
        let version = get("version")?;
        if version.is_empty() {
            return Err("version is empty".to_owned());
        }
        let scenario = get("scenario")?;
        let scenario = SCENARIO_KEYS
            .iter()
            .find(|(_, key)| *key == scenario)
            .map(|(s, _)| *s)
            .ok_or_else(|| format!("scenario: unknown '{scenario}'"))?;
        let difficulty = get("difficulty")?;
        Ok(Self {
            version: version.to_owned(),
            scenario,
            seed: digits("seed", get("seed")?)?,
            difficulty: Difficulty::from_name(difficulty)
                .ok_or_else(|| format!("difficulty: unknown '{difficulty}'"))?,
            run: boolean("run", get("run")?)?,
            perk_pool: digits("perk_pool", get("perk_pool")?)?,
            fog: boolean("fog", get("fog")?)?,
            balance: digits("balance", get("balance")?)?,
        })
    }
}

/// Writes one replay file (see the module docs).
///
/// Lines given to [`ReplayWriter::tick`] are held until the next [`ReplayWriter::checkpoint`]
/// (or [`ReplayWriter::finish`]), which appends them and rewrites the closing
/// `END` line, so the file on disk always ends with the `END` of the last
/// checkpoint. Once finished, every call is a no-op.
#[derive(Debug)]
pub struct ReplayWriter {
    file: File,
    path: PathBuf,
    /// Byte offset of the closing `END` line (the end of the logged lines).
    end_at: u64,
    /// `T` lines not yet on disk.
    pending: String,
    finished: bool,
}

impl ReplayWriter {
    /// Creates `<unix seconds>_<scenario>_<seed>.rpl` in `dir` (created if
    /// missing) and writes `header`.
    ///
    /// # Errors
    ///
    /// `InvalidInput` when `dir` is not an absolute path (nothing is created);
    /// any I/O error creating the directory or the file.
    pub fn create(dir: &Path, header: &ReplayHeader) -> std::io::Result<Self> {
        let secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs());
        Self::create_at(dir, header, secs)
    }

    /// [`ReplayWriter::create`] at a given unix time. A name already taken
    /// (two matches in the same second) gets the first free `_2`, `_3`, ...
    /// suffix; an existing file is never opened.
    ///
    /// # Errors
    ///
    /// As [`ReplayWriter::create`]; `AlreadyExists` after 1000 taken names.
    pub fn create_at(dir: &Path, header: &ReplayHeader, unix_secs: u64) -> std::io::Result<Self> {
        if !dir.is_absolute() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!("replay directory '{}' is not absolute", dir.display()),
            ));
        }
        std::fs::create_dir_all(dir)?;
        let stem = format!(
            "{unix_secs}_{}_{}",
            scenario_key(header.scenario),
            header.seed
        );
        for n in 1..=1000_u32 {
            let path = if n == 1 {
                dir.join(format!("{stem}.rpl"))
            } else {
                dir.join(format!("{stem}_{n}.rpl"))
            };
            match OpenOptions::new().write(true).create_new(true).open(&path) {
                Ok(mut file) => {
                    let text = header.to_text();
                    file.write_all(text.as_bytes())?;
                    return Ok(Self {
                        file,
                        path,
                        end_at: text.len() as u64,
                        pending: String::new(),
                        finished: false,
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
                Err(error) => return Err(error),
            }
        }
        Err(std::io::Error::new(
            std::io::ErrorKind::AlreadyExists,
            format!("every replay name for {stem} is taken"),
        ))
    }

    /// The file being written.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Logs the player lines applied at `tick` (`sim.tick()` before the
    /// step), as `T <tick> <line>`. Control characters are dropped, so each
    /// order stays one file line (in a line that parsed they can only sit in
    /// ignored trailing fields); a line left empty is skipped.
    pub fn tick(&mut self, tick: u64, lines: &[String]) {
        if self.finished {
            return;
        }
        for line in lines {
            let clean: String = line.chars().filter(|c| !c.is_control()).collect();
            if !clean.is_empty() {
                let _ = writeln!(self.pending, "T {tick} {clean}");
            }
        }
    }

    /// Appends the held lines and rewrites the closing line as
    /// `END <tick> <hash> <score>` (the state after the last step).
    ///
    /// The three numbers are zero-padded to 20 characters (`-` first for a
    /// negative score), so every `END` line has one width: the held lines
    /// and the new `END` go down in one write over the old `END`, the file
    /// never shrinks and no truncation is needed, so a kill at any moment
    /// leaves a whole `END` last. Readers parse the numbers as plain integers.
    ///
    /// # Errors
    ///
    /// Any I/O error; the file may then lack its `END`.
    pub fn checkpoint(&mut self, tick: u64, hash: u64, score: i64) -> std::io::Result<()> {
        if self.finished {
            return Ok(());
        }
        let mut chunk = std::mem::take(&mut self.pending);
        let logged = chunk.len() as u64;
        let _ = writeln!(chunk, "END {tick:020} {hash:020} {score:020}");
        self.file.seek(SeekFrom::Start(self.end_at))?;
        self.file.write_all(chunk.as_bytes())?;
        self.end_at += logged;
        Ok(())
    }

    /// The last [`ReplayWriter::checkpoint`]: the file is complete and later
    /// calls write nothing.
    ///
    /// # Errors
    ///
    /// Any I/O error writing or flushing the file.
    pub fn finish(&mut self, tick: u64, hash: u64, score: i64) -> std::io::Result<()> {
        if self.finished {
            return Ok(());
        }
        self.checkpoint(tick, hash, score)?;
        self.finished = true;
        self.file.flush()
    }

    /// Whether [`ReplayWriter::finish`] ran.
    #[must_use]
    pub const fn is_finished(&self) -> bool {
        self.finished
    }
}

/// `(tick, state hash, score)` of `sim` as an `END` line records it (the score
/// is the depth score's total, 0 without depth).
fn end_state(sim: &Sim) -> (u64, u64, i64) {
    (
        sim.tick(),
        sim.state_hash(),
        sim.depth_score().map_or(0, |score| score.total),
    )
}

/// The bridge's replay of the running mission.
///
/// It is off until a mission starts with a `replay_dir`, and finished on a
/// winner, a restart or exit. An I/O
/// failure turns it off (the error is returned for the bridge to log) and
/// never touches the match.
#[derive(Debug, Default)]
pub struct ReplayRecorder {
    writer: Option<ReplayWriter>,
}

impl ReplayRecorder {
    /// A recorder that records nothing yet.
    #[must_use]
    pub const fn new() -> Self {
        Self { writer: None }
    }

    /// The mission of `cfg` starts on `sim` (with presentation fog `fog`):
    /// any open replay is finished first, then a new one is opened when `cfg`
    /// has a `replay_dir`. Returns the new file's path (`None`: not recording).
    ///
    /// # Errors
    ///
    /// The I/O error that kept the replay from opening; the recorder is off.
    pub fn start(
        &mut self,
        cfg: &MatchConfig,
        fog: bool,
        sim: &Sim,
    ) -> std::io::Result<Option<PathBuf>> {
        self.stop(sim)?;
        let Some(dir) = &cfg.replay_dir else {
            return Ok(None);
        };
        let mut writer = ReplayWriter::create(dir, &ReplayHeader::for_match(cfg, fog))?;
        let (tick, hash, score) = end_state(sim);
        writer.checkpoint(tick, hash, score)?;
        let path = writer.path().to_path_buf();
        self.writer = Some(writer);
        Ok(Some(path))
    }

    /// Whether a replay is open.
    #[must_use]
    pub const fn is_recording(&self) -> bool {
        self.writer.is_some()
    }

    /// Logs the player lines about to be applied to `sim` (against
    /// `sim.tick()`, before the step). Nothing is logged once the match is
    /// decided: its tick no longer advances.
    pub fn before_step(&mut self, sim: &Sim, lines: &[String]) {
        if sim.winner().is_some() {
            return;
        }
        if let Some(writer) = &mut self.writer {
            writer.tick(sim.tick(), lines);
        }
    }

    /// After a step: rewrites the `END` line with `sim`'s state, and finishes
    /// the replay once the match is decided.
    ///
    /// # Errors
    ///
    /// The I/O error that ended the recording; the recorder is off.
    pub fn after_step(&mut self, sim: &Sim) -> std::io::Result<()> {
        let Some(writer) = &mut self.writer else {
            return Ok(());
        };
        let (tick, hash, score) = end_state(sim);
        let result = if sim.winner().is_some() {
            writer.finish(tick, hash, score)
        } else {
            writer.checkpoint(tick, hash, score)
        };
        if result.is_err() || writer.is_finished() {
            self.writer = None;
        }
        result
    }

    /// Finishes the open replay, if any, with `sim`'s state (a restart or
    /// exit); the recorder is then off.
    ///
    /// # Errors
    ///
    /// The I/O error finishing the file.
    pub fn stop(&mut self, sim: &Sim) -> std::io::Result<()> {
        self.writer.take().map_or(Ok(()), |mut writer| {
            let (tick, hash, score) = end_state(sim);
            writer.finish(tick, hash, score)
        })
    }
}

/// One stepped bridge frame.
///
/// The accepted player lines ([`accept_lines`]) are logged against
/// `sim.tick()`, then the sim steps the host commands
/// ([`Scenario::host_commands`]) followed by the player's, and the replay's
/// `END` follows the new state. The step happens whatever the recorder does.
///
/// # Errors
///
/// A recording I/O error (the recorder is then off; the step still happened).
pub fn step_frame(
    sim: &mut Sim,
    scenario: Scenario,
    accepted: Vec<(String, Command)>,
    recorder: &mut ReplayRecorder,
) -> std::io::Result<()> {
    let (lines, player): (Vec<String>, Vec<Command>) = accepted.into_iter().unzip();
    recorder.before_step(sim, &lines);
    step_tick(sim, scenario, player);
    recorder.after_step(sim)
}

/// One tick of `scenario`: the host commands ([`Scenario::host_commands`],
/// the one builder of the survey AI, alien AI and scenario script) followed by
/// the player's, then the step.
///
/// The single stepping body: the live bridge ([`step_frame`]), playback
/// ([`ReplayPlayback::frame`]) and [`verify`] all step through it, so the three
/// cannot drift apart.
pub fn step_tick(sim: &mut Sim, scenario: Scenario, player: Vec<Command>) {
    let mut commands = scenario.host_commands(sim);
    commands.extend(player);
    sim.step(&commands);
}

/// The most ticks a replay may span (its `END` tick).
///
/// A replay is untrusted input: the cap bounds the work of [`verify`] and
/// playback. 400,000 ticks is 3 h 42 min at 30 Hz, five times the longest
/// 12-wave run measured (about 75,000 ticks).
pub const VERIFY_MAX_TICKS: u64 = 400_000;

/// The largest replay file read, in bytes (64 MiB). A real recording logs a
/// few lines per order (Task 24 measured 311 bytes for a 200-tick session).
pub const VERIFY_MAX_BYTES: usize = 64 << 20;

/// The text of the replay file at `path`, read whole but never more than
/// [`VERIFY_MAX_BYTES`].
///
/// # Errors
///
/// A message when the file cannot be opened or read, is larger than the cap
/// or is not UTF-8.
pub fn read_replay_text(path: &Path) -> Result<String, String> {
    use std::io::Read as _;
    let file = File::open(path).map_err(|e| format!("cannot open: {e}"))?;
    let mut bytes = Vec::new();
    file.take(VERIFY_MAX_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| format!("cannot read: {e}"))?;
    if bytes.len() > VERIFY_MAX_BYTES {
        return Err(format!("larger than {VERIFY_MAX_BYTES} bytes"));
    }
    String::from_utf8(bytes).map_err(|_| "not UTF-8 text".to_owned())
}

/// At most the first 60 characters of an untrusted line, for a message.
fn clip(line: &str) -> String {
    let mut clipped: String = line.chars().take(60).collect();
    if clipped.len() < line.len() {
        clipped.push_str("...");
    }
    clipped
}

/// An optionally negative run of ASCII digits (`-` then digits; no `+`).
fn signed(key: &str, value: &str) -> Result<i64, String> {
    digits::<u64>(key, value.strip_prefix('-').unwrap_or(value))?;
    value
        .parse()
        .map_err(|_| format!("{key}: '{}' is out of range", clip(value)))
}

/// A parsed replay: the match its header names, its player commands by tick,
/// and the `END` it claims.
///
/// The file is untrusted. [`ReplayPlayer::new`] accepts exactly what
/// [`ReplayWriter`] produces and refuses everything else with a message, never
/// a panic:
/// - the header must parse ([`ReplayHeader::parse`]: an unknown scenario or
///   difficulty is refused) and its balance must be this build's
///   ([`balance_hash`]);
/// - after the header's blank line, each line is `T <tick> <line>` or the
///   one `END <tick> <hash> <score>`, which comes last (a duplicate `END`, a
///   line after it, a blank or unknown line is refused);
/// - `T` ticks are unsigned decimal, never decrease and lie before the `END`
///   tick; each line must parse as a protocol line ([`parse_command_line`],
///   which also drops hostile order points), since the writer logs only lines
///   that parsed;
/// - a file without an `END` (truncated, or torn mid-write) is refused: with
///   no claimed end state there is nothing to verify against;
/// - the `END` tick is at most [`VERIFY_MAX_TICKS`] and the text at most
///   [`VERIFY_MAX_BYTES`].
///
/// The header's `fog` is ignored: the logged lines already passed the fog
/// filter, so replaying them needs no fog state.
#[derive(Debug)]
pub struct ReplayPlayer {
    header: ReplayHeader,
    /// `(tick, command)` in file order (ticks never decrease).
    commands: Vec<(u64, Command)>,
    end_tick: u64,
    expected_hash: u64,
    expected_score: i64,
}

impl ReplayPlayer {
    /// Parses and checks a replay (see the type docs).
    ///
    /// # Errors
    ///
    /// A message naming the first problem found.
    pub fn new(text: &str) -> Result<Self, String> {
        Self::parse(text, VERIFY_MAX_TICKS)
    }

    fn parse(text: &str, max_ticks: u64) -> Result<Self, String> {
        if text.len() > VERIFY_MAX_BYTES {
            return Err(format!("larger than {VERIFY_MAX_BYTES} bytes"));
        }
        let header = ReplayHeader::parse(text)?;
        if header.balance != balance_hash() {
            return Err(format!(
                "refused: recorded under balance {}, this build ships balance {}",
                header.balance,
                balance_hash()
            ));
        }
        // The body follows the header's blank line (the header parsed, so
        // the magic and its key lines come first).
        let mut lines = text.lines();
        lines
            .by_ref()
            .take_while(|line| !line.is_empty())
            .for_each(drop);
        let mut commands: Vec<(u64, Command)> = Vec::new();
        let mut end: Option<(u64, u64, i64)> = None;
        for line in lines {
            if end.is_some() {
                return Err(if line.starts_with("END") {
                    "two END lines (a replay has one END, last)".to_owned()
                } else {
                    format!("'{}' follows END (END comes last)", clip(line))
                });
            }
            if let Some(rest) = line.strip_prefix("T ") {
                let (tick, raw) = rest
                    .split_once(' ')
                    .ok_or_else(|| format!("'{}' is not T <tick> <line>", clip(line)))?;
                let tick: u64 = digits("T tick", tick)?;
                if commands.last().is_some_and(|&(last, _)| tick < last) {
                    return Err(format!("T {tick} comes after a later tick"));
                }
                let command = parse_command_line(raw)
                    .ok_or_else(|| format!("T {tick}: '{}' is not a command line", clip(raw)))?;
                commands.push((tick, command));
            } else if let Some(rest) = line.strip_prefix("END ") {
                let mut fields = rest.split(' ');
                let (Some(tick), Some(hash), Some(score), None) =
                    (fields.next(), fields.next(), fields.next(), fields.next())
                else {
                    return Err(format!("'{}' is not END <tick> <hash> <score>", clip(line)));
                };
                end = Some((
                    digits("END tick", tick)?,
                    digits("END hash", hash)?,
                    signed("END score", score)?,
                ));
            } else {
                return Err(format!("unknown line '{}'", clip(line)));
            }
        }
        let (end_tick, expected_hash, expected_score) =
            end.ok_or("no END line: the file is truncated")?;
        if end_tick > max_ticks {
            return Err(format!(
                "END tick {end_tick} is beyond the verify limit of {max_ticks} ticks"
            ));
        }
        if let Some(&(tick, _)) = commands.last() {
            if tick >= end_tick {
                return Err(format!("T {tick} is not before END {end_tick}"));
            }
        }
        Ok(Self {
            header,
            commands,
            end_tick,
            expected_hash,
            expected_score,
        })
    }

    /// The replay's header.
    #[must_use]
    pub const fn header(&self) -> &ReplayHeader {
        &self.header
    }

    /// The `END` tick: the last stepped tick of the recording.
    #[must_use]
    pub const fn end_tick(&self) -> u64 {
        self.end_tick
    }

    /// The state hash the `END` line claims.
    #[must_use]
    pub const fn expected_hash(&self) -> u64 {
        self.expected_hash
    }

    /// The score the `END` line claims.
    #[must_use]
    pub const fn expected_score(&self) -> i64 {
        self.expected_score
    }

    /// The match the header names, as a config (no replay directory: a
    /// replayed match is never recorded again).
    #[must_use]
    pub fn match_config(&self) -> MatchConfig {
        let h = &self.header;
        MatchConfig {
            fog: Some(h.fog),
            seed: h.seed,
            difficulty: h.difficulty,
            run: h.run,
            perk_pool: h.perk_pool,
            ..MatchConfig::boot(h.scenario)
        }
    }

    /// The header's match at tick 0, with the shipped balance ([`build_match`]).
    #[must_use]
    pub fn build(&self) -> Sim {
        build_match(&self.match_config())
    }

    /// The player's commands logged at `tick`, in file order.
    #[must_use]
    pub fn commands_for(&self, tick: u64) -> Vec<Command> {
        let from = self.commands.partition_point(|&(t, _)| t < tick);
        self.commands[from..]
            .iter()
            .take_while(|&&(t, _)| t == tick)
            .map(|(_, command)| command.clone())
            .collect()
    }

    /// Whether `sim` has reached the end of the recording: the `END` tick, or
    /// a decided match (the recorder closes the file at the first decided
    /// tick, in every scenario; an Earthfront mission also stops its tick).
    #[must_use]
    pub fn is_done(&self, sim: &Sim) -> bool {
        sim.tick() >= self.end_tick || sim.winner().is_some()
    }

    /// Steps `sim` one tick with the commands logged at its tick ([`step_tick`]).
    pub fn step(&self, sim: &mut Sim) {
        step_tick(sim, self.header.scenario, self.commands_for(sim.tick()));
    }
}

/// The playback speeds and the half ticks each adds per frame: 0 pauses, 0.5
/// steps every other frame, 8 steps eight ticks a frame.
const SPEEDS: [(f32, u32); 6] = [(0.0, 0), (0.5, 1), (1.0, 2), (2.0, 4), (4.0, 8), (8.0, 16)];

/// The playback speed in `replay_speed.txt`: 0, 0.5, 1, 2, 4 or 8 (surrounding
/// space ignored); anything else is 1.
#[must_use]
pub fn parse_speed(text: &str) -> f32 {
    text.trim()
        .parse::<f32>()
        .ok()
        .and_then(|value| {
            SPEEDS
                .iter()
                .find(|(speed, _)| (speed - value).abs() < f32::EPSILON)
        })
        .map_or(1.0, |&(speed, _)| speed)
}

/// A replay being played back by the bridge, one frame at a time.
#[derive(Debug)]
pub struct ReplayPlayback {
    player: ReplayPlayer,
    /// Half ticks carried to the next frame (0.5x).
    half_ticks: u32,
}

impl ReplayPlayback {
    /// Plays `player` from tick 0.
    #[must_use]
    pub const fn new(player: ReplayPlayer) -> Self {
        Self {
            player,
            half_ticks: 0,
        }
    }

    /// The replay played.
    #[must_use]
    pub const fn player(&self) -> &ReplayPlayer {
        &self.player
    }

    /// The `END` tick, where the playback stops and holds.
    #[must_use]
    pub const fn end_tick(&self) -> u64 {
        self.player.end_tick
    }

    /// The replay's match at tick 0.
    #[must_use]
    pub fn build(&self) -> Sim {
        self.player.build()
    }

    /// One 33 ms frame at `speed` ([`parse_speed`] values; another value
    /// counts as 1): steps `sim` 0 to 8 ticks through [`ReplayPlayer::step`],
    /// calling `after_step` after each, and holds once the recording's end
    /// is reached. Speed changes how many ticks a frame steps, never which
    /// commands a tick gets. Returns the ticks stepped.
    pub fn frame(&mut self, sim: &mut Sim, speed: f32, mut after_step: impl FnMut(&Sim)) -> u32 {
        let half = SPEEDS
            .iter()
            .find(|(s, _)| (s - speed).abs() < f32::EPSILON)
            .map_or(2, |&(_, half)| half);
        self.half_ticks += half;
        let ticks = self.half_ticks / 2;
        self.half_ticks %= 2;
        let mut stepped = 0;
        for _ in 0..ticks {
            if self.player.is_done(sim) {
                self.half_ticks = 0;
                break;
            }
            self.player.step(sim);
            after_step(sim);
            stepped += 1;
        }
        stepped
    }
}

/// The result of re-simulating a replay ([`verify`]).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct VerifyReport {
    /// The tick the re-simulation reached.
    pub ticks: u64,
    /// The state hash it reached.
    pub hash: u64,
    /// The hash the file's `END` claims.
    pub expected_hash: u64,
    /// The score it reached (the depth score's total, 0 without depth).
    pub score: i64,
    /// The score the file's `END` claims.
    pub expected_score: i64,
    /// The tick the file's `END` claims.
    pub expected_ticks: u64,
}

impl VerifyReport {
    /// Whether the re-simulation reproduced the claimed tick, hash and score.
    #[must_use]
    pub const fn ok(&self) -> bool {
        self.ticks == self.expected_ticks
            && self.hash == self.expected_hash
            && self.score == self.expected_score
    }
}

/// Re-simulates a replay headless and reports what it reached against the
/// `END` the file claims.
///
/// The header's match is rebuilt (`header.scenario.build_with(header.seed,
/// MatchOptions { difficulty, run, perk_pool })` with the shipped balance; no
/// settings or meta file is read), then each tick steps the host commands plus
/// that tick's logged lines ([`step_tick`], the bridge's own body) up to the
/// `END` tick, or until the match is decided.
///
/// A logged command goes through the core's own guards exactly as it did live
/// (ownership, cost, cooldown, draft, coordinate range): a command the core
/// refuses is a silent no-op, live and replayed alike. A tampered line the
/// core now accepts or refuses differently changes the state, so the report
/// mismatches. Verification proves the file is consistent with its `END`; the
/// `END` itself is not signed.
///
/// # Errors
///
/// A message when the file cannot be verified at all ([`ReplayPlayer::new`]:
/// malformed, too long, or recorded under another balance).
pub fn verify(text: &str) -> Result<VerifyReport, String> {
    verify_with_limit(text, VERIFY_MAX_TICKS)
}

/// [`verify`] with another tick cap (tests bound their work with it).
fn verify_with_limit(text: &str, max_ticks: u64) -> Result<VerifyReport, String> {
    let player = ReplayPlayer::parse(text, max_ticks)?;
    let mut sim = player.build();
    // At most END steps, so the loop ends even if the tick stops advancing.
    for _ in 0..player.end_tick {
        if player.is_done(&sim) {
            break;
        }
        player.step(&mut sim);
    }
    let (ticks, hash, score) = end_state(&sim);
    Ok(VerifyReport {
        ticks,
        hash,
        expected_hash: player.expected_hash,
        score,
        expected_score: player.expected_score,
        expected_ticks: player.end_tick,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rts_core::game::stats::{BuildingKind, UnitKind};
    use std::collections::BTreeMap;

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
        assert_eq!((c.seed, c.difficulty), (2026, Difficulty::Normal));
    }

    /// Task 20: `seed` (a bare unsigned integer) and `difficulty` (a quoted
    /// preset name); anything malformed keeps 2026 and Normal.
    #[test]
    fn match_config_parses_seed_and_difficulty_and_falls_back() {
        let c = parse_match_config(
            r#"{"scenario":"kestrel","seed":7,"difficulty":"hard","fog":true}"#,
            Scenario::Survival,
        );
        assert_eq!(c.scenario, Scenario::KestrelReach);
        assert_eq!((c.seed, c.difficulty), (7, Difficulty::Hard));
        let c = parse_match_config(
            r#"{"seed":2147483646,"difficulty":"easy"}"#,
            Scenario::KestrelReach,
        );
        assert_eq!((c.seed, c.difficulty), (2_147_483_646, Difficulty::Easy));
        for bad in [
            r#"{"seed":"7"}"#,
            r#"{"seed":-5}"#,
            r#"{"seed":1.5}"#,
            r#"{"seed":abc}"#,
            r#"{"seed":}"#,
            r#"{"seed":184467440737095516160}"#,
            r#"{"scenario":"kestrel"}"#,
        ] {
            let c = parse_match_config(bad, Scenario::KestrelReach);
            assert_eq!(c.seed, 2026, "{bad}");
        }
        for bad in [
            r#"{"difficulty":"brutal"}"#,
            r#"{"difficulty":"Hard"}"#,
            r#"{"difficulty":2}"#,
            r#"{"difficulty":""}"#,
            r#"{"scenario":"kestrel"}"#,
        ] {
            let c = parse_match_config(bad, Scenario::KestrelReach);
            assert_eq!(c.difficulty, Difficulty::Normal, "{bad}");
        }
        let c = parse_match_config("[1,2]", Scenario::KestrelReach);
        assert_eq!((c.seed, c.difficulty), (2026, Difficulty::Normal));
    }

    /// Task 20: the bridge builds the match `match.json` asks for: Kestrel at
    /// its seed and preset, Survival at its seed (the preset ignored).
    #[test]
    fn the_bridge_builds_the_configured_seed_and_difficulty() {
        use rts_core::game::scenario::{kestrel_reach_with, MatchOptions};
        let cfg = parse_match_config(
            r#"{"scenario":"kestrel","seed":99,"difficulty":"easy","fog":true}"#,
            Scenario::Survival,
        );
        let sim = build_match(&cfg);
        let want = kestrel_reach_with(
            99,
            MatchOptions {
                difficulty: Difficulty::Easy,
                ..MatchOptions::default()
            },
        );
        assert_eq!(sim.state_hash(), {
            let mut w = want;
            w.set_balance(rts_data::load_default());
            w.state_hash()
        });
        assert_eq!((sim.seed(), sim.difficulty()), (99, Difficulty::Easy));
        let cfg = parse_match_config(
            r#"{"scenario":"survival","seed":5,"difficulty":"hard"}"#,
            Scenario::KestrelReach,
        );
        let sim = build_match(&cfg);
        let mut want = Scenario::Survival.build(5);
        want.set_balance(rts_data::load_default());
        assert_eq!(sim.state_hash(), want.state_hash());
        // The boot match (no match.json) is the old `build(2026)`.
        let boot = MatchConfig::boot(Scenario::KestrelReach);
        let mut old = Scenario::KestrelReach.build(2026);
        old.set_balance(rts_data::load_default());
        assert_eq!(build_match(&boot).state_hash(), old.state_hash());
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
    fn godot_command_file_supports_perk_picks() {
        let path = std::env::temp_dir().join(format!(
            "earthfront-perk-commands-{}.txt",
            std::process::id()
        ));
        std::fs::write(
            &path,
            "perk,4\nperk,0\nperk,11\nperk,4294967295\n\
             perk,x\nperk,\nperk\nperk,-1\nperk,4294967296\nperk,1.5\n",
        )
        .expect("write command fixture");
        let commands = take_commands(&path);
        // Any u32 parses; the core takes only an id in the pending draft (Task 23).
        assert_eq!(commands.len(), 4, "malformed perk lines are dropped");
        for (command, want) in commands.iter().zip([4u32, 0, 11, u32::MAX]) {
            assert!(
                matches!(*command, Command::ChoosePerk { owner: PlayerId(0), perk } if perk == want),
                "{command:?}"
            );
        }
        assert!(!path.exists(), "bridge consumes the order file atomically");
    }

    /// Task 23: `run` (bare true/false) and `perk_pool` (a bare unsigned
    /// integer); anything malformed keeps false and the default pool (0xFF).
    #[test]
    fn match_config_parses_run_and_perk_pool_and_falls_back() {
        let c = parse_match_config(
            r#"{"scenario":"kestrel","seed":7,"run":true,"perk_pool":4095}"#,
            Scenario::Survival,
        );
        assert_eq!((c.run, c.perk_pool, c.seed), (true, 4095, 7));
        let c = parse_match_config(r#"{"run":false,"perk_pool":0}"#, Scenario::KestrelReach);
        assert_eq!((c.run, c.perk_pool), (false, 0));
        let boot = MatchConfig::boot(Scenario::KestrelReach);
        assert_eq!((boot.run, boot.perk_pool), (false, 0xFF));
        for bad in [
            r#"{"run":"true"}"#,
            r#"{"run":1}"#,
            r#"{"run":}"#,
            r#"{"run":TRUE}"#,
            r#"{"scenario":"kestrel"}"#,
        ] {
            assert!(
                !parse_match_config(bad, Scenario::KestrelReach).run,
                "{bad}"
            );
        }
        for bad in [
            r#"{"perk_pool":"255"}"#,
            r#"{"perk_pool":-1}"#,
            r#"{"perk_pool":0xFF}"#,
            r#"{"perk_pool":4294967296}"#,
            r#"{"perk_pool":}"#,
            r#"{"run":true}"#,
        ] {
            let c = parse_match_config(bad, Scenario::KestrelReach);
            assert_eq!(c.perk_pool, 0xFF, "{bad}");
        }
        let c = parse_match_config("not json", Scenario::KestrelReach);
        assert_eq!((c.run, c.perk_pool), (false, 0xFF));
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
    // ---- Task 24: the shared parser, the replay header, writer and recorder ----

    /// A fresh scratch directory for one test (removed by the test).
    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("earthfront-replay-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Every `.rpl` file in `dir`, sorted by name.
    fn replays_in(dir: &Path) -> Vec<PathBuf> {
        let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
            .map(|entries| {
                entries
                    .filter_map(Result::ok)
                    .map(|entry| entry.path())
                    .filter(|path| path.extension().is_some_and(|ext| ext == "rpl"))
                    .collect()
            })
            .unwrap_or_default();
        files.sort();
        files
    }

    fn header(seed: u64) -> ReplayHeader {
        ReplayHeader {
            version: REPLAY_VERSION.to_owned(),
            scenario: Scenario::KestrelReach,
            seed,
            difficulty: Difficulty::Hard,
            run: true,
            perk_pool: 511,
            fog: false,
            balance: balance_hash(),
        }
    }

    /// `(tick, hash, score)` of the `END` line that closes `text`.
    fn end_of(text: &str) -> (u64, u64, i64) {
        let last = text.lines().last().expect("a last line");
        let mut f = last.strip_prefix("END ").expect("END last").split(' ');
        let tick = f.next().unwrap().parse().unwrap();
        let hash = f.next().unwrap().parse().unwrap();
        let score = f.next().unwrap().parse().unwrap();
        assert!(f.next().is_none(), "{last}");
        (tick, hash, score)
    }

    /// Re-simulates a replay from its text alone: the header's match, then per
    /// tick the host commands and the `T` lines of that tick, up to the END
    /// tick. Returns the end `(tick, hash, score)` it reached.
    fn replay(text: &str) -> (u64, u64, i64) {
        let h = ReplayHeader::parse(text).expect("header");
        assert_eq!(h.balance, balance_hash());
        let cfg = MatchConfig {
            scenario: h.scenario,
            seed: h.seed,
            difficulty: h.difficulty,
            run: h.run,
            perk_pool: h.perk_pool,
            ..MatchConfig::boot(h.scenario)
        };
        let mut sim = build_match(&cfg);
        let (end, ..) = end_of(text);
        let body = text
            .split_once("\n\n")
            .expect("blank line after the header")
            .1;
        let mut lines: BTreeMap<u64, Vec<String>> = BTreeMap::new();
        for line in body.lines() {
            if let Some(rest) = line.strip_prefix("T ") {
                let (tick, raw) = rest.split_once(' ').expect("T <tick> <line>");
                lines
                    .entry(tick.parse().unwrap())
                    .or_default()
                    .push(raw.to_owned());
            }
        }
        assert!(lines.keys().all(|&t| t < end), "a T line at or after END");
        for tick in 0..end {
            assert_eq!(sim.tick(), tick);
            let mut commands = h.scenario.host_commands(&sim);
            for raw in lines.get(&tick).into_iter().flatten() {
                commands.push(parse_command_line(raw).expect("a recorded line parses"));
            }
            sim.step(&commands);
        }
        (
            sim.tick(),
            sim.state_hash(),
            sim.depth_score().map_or(0, |s| s.total),
        )
    }

    /// A scripted player: orders for the human's first rifle and a perk pick
    /// whenever a draft is pending, every 37th tick, plus junk lines the
    /// parser drops.
    fn scripted_lines(sim: &Sim) -> Vec<String> {
        let t = sim.tick();
        if t % 37 != 5 {
            return Vec::new();
        }
        let rifle = sim
            .views()
            .into_iter()
            .find(|v| {
                v.owner == PlayerId(0)
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Unit(UnitKind::Infantry)
                    )
            })
            .map_or(0, |v| v.id.0);
        let mut lines = vec![
            format!("attack,{rifle},{},{}", 20 << 16, 22 << 16),
            "junk,1,2".to_owned(),
            format!("stance,{rifle},defensive"),
        ];
        if t % 74 == 5 {
            lines.push(format!("stop,{rifle}"));
        }
        if let Some([first, ..]) = sim.depth_draft() {
            lines.push(format!("perk,{first}"));
        }
        lines
    }

    /// The bridge's stepped-frame body over `frames` frames: the player's
    /// lines (parsed, the malformed ones dropped) through [`step_frame`].
    fn run_frames(sim: &mut Sim, scenario: Scenario, recorder: &mut ReplayRecorder, frames: u32) {
        for _ in 0..frames {
            let accepted = accept_lines(scripted_lines(sim), |_| true);
            step_frame(sim, scenario, accepted, recorder).expect("recording");
        }
    }

    #[test]
    fn read_command_lines_returns_the_legacy_file_then_sorted_packets_raw() {
        let dir = scratch("lines");
        let path = dir.join("commands.txt");
        std::fs::create_dir_all(dir.join("commands")).unwrap();
        std::fs::write(&path, "stop,1\nnot a command\n").unwrap();
        std::fs::write(dir.join("commands").join("0002.cmd"), "hold,3").unwrap();
        std::fs::write(dir.join("commands").join("0001.cmd"), "perk,4\n").unwrap();
        std::fs::write(dir.join("commands").join("0003.next"), "stop,9\n").unwrap();
        let lines = read_command_lines(&path);
        // As before the move: a packet ending in a newline leaves an empty line.
        assert_eq!(lines, ["stop,1", "not a command", "perk,4", "", "hold,3"]);
        assert!(!path.exists());
        assert!(!dir.join("commands").join("0001.cmd").exists());
        assert!(
            dir.join("commands").join("0003.next").exists(),
            "a half-written packet waits"
        );
        assert_eq!(
            lines.iter().filter_map(|l| parse_command_line(l)).count(),
            3
        );
        assert!(read_command_lines(&path).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn accept_lines_keeps_parsed_admitted_lines_in_order() {
        let lines = ["stop,1", "junk", "target,2,9", "hold,3", "target,2,8"]
            .map(str::to_owned)
            .to_vec();
        let accepted = accept_lines(lines, |c| {
            !matches!(
                c,
                Command::AttackTarget {
                    target: EntityId(9),
                    ..
                }
            )
        });
        let raw: Vec<&str> = accepted.iter().map(|(line, _)| line.as_str()).collect();
        assert_eq!(raw, ["stop,1", "hold,3", "target,2,8"]);
        for (line, command) in &accepted {
            assert_eq!(
                format!("{:?}", parse_command_line(line)),
                format!("{:?}", Some(command))
            );
        }
    }

    #[test]
    fn balance_hash_is_stable_and_covers_the_shipped_balance() {
        assert_eq!(balance_hash(), balance_hash());
        let fnv = rts_data::DEFAULT_RON
            .bytes()
            .fold(0xcbf2_9ce4_8422_2325_u64, |h, b| {
                (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
            });
        assert_eq!(balance_hash(), fnv);
    }

    #[test]
    fn replay_header_round_trips_and_refuses_malformed_text() {
        let h = header(77);
        let text = h.to_text();
        assert_eq!(
            text,
            format!(
                "RPL1\nversion={REPLAY_VERSION}\nscenario=kestrel\nseed=77\ndifficulty=hard\nrun=true\n\
                 perk_pool=511\nfog=false\nbalance={}\n\n",
                balance_hash()
            )
        );
        assert_eq!(ReplayHeader::parse(&text), Ok(h.clone()));
        let survival = ReplayHeader {
            scenario: Scenario::Survival,
            difficulty: Difficulty::Normal,
            run: false,
            fog: true,
            ..h.clone()
        };
        assert_eq!(ReplayHeader::parse(&survival.to_text()), Ok(survival));
        // A whole replay parses too (the header stops at the blank line).
        assert_eq!(
            ReplayHeader::parse(&format!("{text}T 0 stop,1\nEND 1 2 3\n")),
            Ok(h)
        );
        let bad = [
            String::new(),
            text.replacen("RPL1", "RPL2", 1),
            text.replacen("seed=77", "seed=+77", 1),
            text.replacen("seed=77", "seed=-1", 1),
            text.replacen("seed=77", "seed=", 1),
            text.replacen("difficulty=hard", "difficulty=Hard", 1),
            text.replacen("run=true", "run=1", 1),
            text.replacen("perk_pool=511", "perk_pool=4294967296", 1),
            text.replacen("fog=false", "fog=no", 1),
            text.replacen("scenario=kestrel", "scenario=mars", 1),
            text.replacen("version=", "versio=", 1),
            text.replacen("seed=77\n", "", 1),
            text.replacen("seed=77\n", "seed=77\nseed=78\n", 1),
            text.replacen("fog=false\n", "fog=false\nnonsense\n", 1),
            text.replacen(&format!("version={REPLAY_VERSION}"), "version=", 1),
        ];
        for b in &bad {
            assert!(ReplayHeader::parse(b).is_err(), "{b:?}");
        }
    }

    #[test]
    fn replay_writer_produces_the_exact_format() {
        let dir = scratch("format");
        let h = header(77);
        let mut w = ReplayWriter::create(&dir, &h).unwrap();
        let path = w.path().to_path_buf();
        let name = path.file_name().unwrap().to_str().unwrap().to_owned();
        let (secs, rest) = name.split_once('_').unwrap();
        assert!(
            secs.bytes().all(|b| b.is_ascii_digit()) && !secs.is_empty(),
            "{name}"
        );
        assert_eq!(rest, "kestrel_77.rpl");
        w.tick(0, &["stop,5".to_owned(), "perk,4".to_owned()]);
        w.tick(1, &[]);
        // Control characters only ride in ignored trailing fields of a parsed
        // line; they are stripped so the file keeps one line per order.
        w.tick(3, &["move,7,65536,65536,\r".to_owned()]);
        w.finish(10, 12345, 678).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert_eq!(
            text,
            format!(
                "{}T 0 stop,5\nT 0 perk,4\nT 3 move,7,65536,65536,\n\
                 END 00000000000000000010 00000000000000012345 00000000000000000678\n",
                h.to_text()
            )
        );
        // Finished: later calls write nothing.
        w.tick(11, &["stop,1".to_owned()]);
        w.finish(12, 1, 1).unwrap();
        drop(w);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), text);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_checkpoint_keeps_one_end_line_last() {
        let dir = scratch("checkpoint");
        let h = header(5);
        let mut w = ReplayWriter::create(&dir, &h).unwrap();
        let path = w.path().to_path_buf();
        w.checkpoint(0, 99_999_999_999, 1234).unwrap();
        w.tick(0, &["hold,2".to_owned()]);
        w.checkpoint(1, 7, 0).unwrap();
        w.checkpoint(2, 8, -3).unwrap();
        // Dropped mid-match (the bridge exits or is killed between frames):
        // the file already ends with the END of the last stepped tick.
        drop(w);
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            format!(
                "{}T 0 hold,2\nEND 00000000000000000002 00000000000000000008 -0000000000000000003\n",
                h.to_text()
            )
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The END line has one width for every value, so rewriting it never
    /// shrinks the file: each checkpoint is one write over the old END, with
    /// no truncation a kill could interrupt.
    #[test]
    fn end_lines_have_one_width_and_the_file_never_shrinks() {
        let dir = scratch("end-width");
        let h = header(6);
        let mut w = ReplayWriter::create(&dir, &h).unwrap();
        let path = w.path().to_path_buf();
        let mut last_len = 0;
        for (tick, hash, score) in [
            (u64::MAX, u64::MAX, i64::MAX),
            (0, 0, i64::MIN),
            (1, 9, -1),
            (2, 10, 0),
        ] {
            w.checkpoint(tick, hash, score).unwrap();
            let text = std::fs::read_to_string(&path).unwrap();
            let end = text.lines().last().unwrap();
            assert_eq!(end.len(), 66, "{end}");
            assert_eq!(end_of(&text), (tick, hash, score));
            assert!(text.len() >= last_len);
            last_len = text.len();
        }
        assert_eq!(last_len, h.to_text().len() + 67);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn two_replays_in_the_same_second_do_not_overwrite_each_other() {
        let dir = scratch("same-second");
        let head = header(9);
        let mut first = ReplayWriter::create_at(&dir, &head, 1_700_000_000).unwrap();
        let mut second = ReplayWriter::create_at(&dir, &head, 1_700_000_000).unwrap();
        let mut third = ReplayWriter::create(&dir, &head).unwrap();
        let mut fourth = ReplayWriter::create(&dir, &head).unwrap();
        assert_eq!(first.path(), dir.join("1700000000_kestrel_9.rpl"));
        assert_eq!(second.path(), dir.join("1700000000_kestrel_9_2.rpl"));
        assert_ne!(third.path(), fourth.path());
        first.finish(1, 1, 1).unwrap();
        second.finish(2, 2, 2).unwrap();
        third.finish(3, 3, 3).unwrap();
        fourth.finish(4, 4, 4).unwrap();
        let ends: Vec<u64> = replays_in(&dir)
            .iter()
            .map(|p| end_of(&std::fs::read_to_string(p).unwrap()).0)
            .collect();
        assert_eq!(ends.len(), 4);
        let mut sorted = ends;
        sorted.sort_unstable();
        assert_eq!(sorted, [1, 2, 3, 4]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn replay_dir_must_be_absolute() {
        let dir = scratch("relative");
        let h = header(1);
        for relative in [
            "replays",
            "./replays",
            "res://replays",
            "user://replays",
            "",
        ] {
            let err = ReplayWriter::create(Path::new(relative), &h).unwrap_err();
            assert_eq!(err.kind(), std::io::ErrorKind::InvalidInput, "{relative}");
        }
        assert!(!Path::new("res:").exists() && !Path::new("user:").exists());
        let cfg = |json: &str| parse_match_config(json, Scenario::KestrelReach).replay_dir;
        let abs = dir.join("r");
        assert_eq!(
            cfg(&format!(
                r#"{{"scenario":"kestrel","replay_dir":"{}"}}"#,
                abs.display()
            )),
            Some(abs)
        );
        for bad in [
            r#"{"scenario":"kestrel"}"#,
            r#"{"replay_dir":"res://replays"}"#,
            r#"{"replay_dir":"user://replays"}"#,
            r#"{"replay_dir":"replays"}"#,
            r#"{"replay_dir":"./replays"}"#,
            r#"{"replay_dir":""}"#,
            r#"{"replay_dir":/tmp/x}"#,
            r#"{"replay_dir":"/tmp/a\"b"}"#,
            r#"{"replay_dir":"C:\\replays"}"#,
            "not json",
        ] {
            assert_eq!(cfg(bad), None, "{bad}");
        }
        assert_eq!(MatchConfig::boot(Scenario::KestrelReach).replay_dir, None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn no_replay_dir_means_no_recording() {
        let dir = scratch("none");
        let cfg = parse_match_config(r#"{"scenario":"kestrel","seed":4}"#, Scenario::KestrelReach);
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        assert_eq!(recorder.start(&cfg, true, &sim).unwrap(), None);
        assert!(!recorder.is_recording());
        run_frames(&mut sim, cfg.scenario, &mut recorder, 40);
        recorder.stop(&sim).unwrap();
        assert!(replays_in(&dir).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_unwritable_replay_dir_leaves_the_match_unrecorded_and_running() {
        let dir = scratch("unwritable");
        let blocker = dir.join("a-file");
        std::fs::write(&blocker, "not a directory").unwrap();
        let cfg = parse_match_config(
            &format!(
                r#"{{"scenario":"kestrel","seed":4,"replay_dir":"{}"}}"#,
                blocker.join("replays").display()
            ),
            Scenario::KestrelReach,
        );
        assert!(cfg.replay_dir.is_some());
        let mut sim = build_match(&cfg);
        let mut twin = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        assert!(recorder.start(&cfg, true, &sim).is_err());
        assert!(!recorder.is_recording());
        run_frames(&mut sim, cfg.scenario, &mut recorder, 60);
        run_frames(&mut twin, cfg.scenario, &mut ReplayRecorder::new(), 60);
        assert_eq!(
            sim.state_hash(),
            twin.state_hash(),
            "recording never changes the match"
        );
        assert!(recorder.stop(&sim).is_ok());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_recorded_match_replays_to_its_end_hash_and_score() {
        let dir = scratch("round-trip");
        let cfg = parse_match_config(
            &format!(
                r#"{{"scenario":"kestrel","seed":11,"difficulty":"easy","run":true,"perk_pool":4095,"replay_dir":"{}"}}"#,
                dir.display()
            ),
            Scenario::KestrelReach,
        );
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        let path = recorder
            .start(&cfg, false, &sim)
            .unwrap()
            .expect("recording");
        assert!(recorder.is_recording());
        run_frames(&mut sim, cfg.scenario, &mut recorder, 1500);
        // Mid-match the file already closes with the current END.
        let mid = std::fs::read_to_string(&path).unwrap();
        assert_eq!(
            end_of(&mid),
            (1500, sim.state_hash(), sim.depth_score().unwrap().total)
        );
        recorder.stop(&sim).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        let h = ReplayHeader::parse(&text).unwrap();
        assert_eq!(
            (h.scenario, h.seed, h.difficulty, h.run, h.perk_pool, h.fog),
            (
                Scenario::KestrelReach,
                11,
                Difficulty::Easy,
                true,
                4095,
                false
            )
        );
        assert!(text.contains("\nT 5 attack,"), "player lines are logged");
        assert!(!text.contains("junk"), "only parsed lines are logged");
        let end = end_of(&text);
        assert_eq!(
            end,
            (1500, sim.state_hash(), sim.depth_score().unwrap().total)
        );
        assert_eq!(replay(&text), end);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_restart_ends_the_old_replay_and_the_next_mission_opens_a_new_one() {
        let dir = scratch("restart");
        let json = |seed: u64| {
            format!(
                r#"{{"scenario":"kestrel","seed":{seed},"replay_dir":"{}"}}"#,
                dir.display()
            )
        };
        let mut recorder = ReplayRecorder::new();
        let first = parse_match_config(&json(21), Scenario::KestrelReach);
        let mut sim = build_match(&first);
        let a = recorder.start(&first, true, &sim).unwrap().unwrap();
        run_frames(&mut sim, first.scenario, &mut recorder, 200);
        let first_end = (
            sim.tick(),
            sim.state_hash(),
            sim.depth_score().unwrap().total,
        );
        // Restart: the bridge finishes the old file, rebuilds, and opens the
        // next one when the new mission starts.
        recorder.stop(&sim).unwrap();
        assert!(!recorder.is_recording());
        let second = parse_match_config(&json(22), Scenario::KestrelReach);
        sim = build_match(&second);
        let b = recorder.start(&second, true, &sim).unwrap().unwrap();
        assert_ne!(a, b);
        run_frames(&mut sim, second.scenario, &mut recorder, 100);
        drop(recorder);
        let text_a = std::fs::read_to_string(&a).unwrap();
        let text_b = std::fs::read_to_string(&b).unwrap();
        assert_eq!(end_of(&text_a), first_end);
        assert_eq!(ReplayHeader::parse(&text_b).unwrap().seed, 22);
        assert_eq!(end_of(&text_b).0, 100);
        assert_eq!(replay(&text_a), end_of(&text_a));
        assert_eq!(replay(&text_b), end_of(&text_b));
        assert_eq!(replays_in(&dir).len(), 2);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_decided_match_stops_logging_at_the_winning_tick() {
        let dir = scratch("winner");
        let cfg = parse_match_config(
            &format!(
                r#"{{"scenario":"kestrel","seed":3,"difficulty":"hard","replay_dir":"{}"}}"#,
                dir.display()
            ),
            Scenario::KestrelReach,
        );
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        let path = recorder.start(&cfg, true, &sim).unwrap().unwrap();
        // Undefended on Hard the base falls near t=4006; the bridge keeps
        // stepping a decided match (its tick stops) and the player keeps
        // sending lines.
        run_frames(&mut sim, cfg.scenario, &mut recorder, 4600);
        let won_at = sim.tick();
        assert!(sim.winner().is_some(), "the undefended base fell");
        assert!(won_at < 4600, "the tick stopped at {won_at}");
        assert!(
            !recorder.is_recording(),
            "a decided match closes its replay"
        );
        let text = std::fs::read_to_string(&path).unwrap();
        let end = end_of(&text);
        assert_eq!(
            end,
            (won_at, sim.state_hash(), sim.depth_score().unwrap().total)
        );
        assert_eq!(text.matches("\nEND ").count(), 1);
        assert_eq!(replay(&text), end);
        recorder.stop(&sim).unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), text);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // ---- Task 25: verify, ReplayPlayer, playback speed ----

    /// A folder under the workspace `target/` for one test, removed on drop.
    struct TargetTempDir(PathBuf);

    impl Drop for TargetTempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    impl std::ops::Deref for TargetTempDir {
        type Target = Path;
        fn deref(&self) -> &Path {
            &self.0
        }
    }

    fn tempdir_in_target(name: &str) -> TargetTempDir {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target/tmp")
            .join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        TargetTempDir(dir)
    }

    /// The id of the human's first rifle (0 when it has none).
    fn first_rifle(sim: &Sim) -> u32 {
        sim.views()
            .into_iter()
            .find(|v| {
                v.owner == PlayerId(0)
                    && matches!(
                        v.kind,
                        rts_core::game::sim::EntityKindView::Unit(UnitKind::Infantry)
                    )
            })
            .map_or(0, |v| v.id.0)
    }

    /// Task 25's scripted player: protocol lines only. An `attack` alone at
    /// every 60th tick up to 600 (so `T 600 attack,` is the only line of tick
    /// 600 and moving it keeps the ticks in order); the last one sends the
    /// rifle far east and the `stop` at 640 freezes it mid-route, so moving
    /// that order by one tick moves where the rifle stands for good. Then a
    /// stance cycle, more `stop`s, a `perk` pick the core refuses (no draft
    /// is pending) every 300 ticks, a real pick whenever a draft is pending,
    /// and a junk line the parser drops.
    fn t25_lines(sim: &Sim) -> Vec<String> {
        let t = sim.tick();
        let rifle = first_rifle(sim);
        let mut lines = Vec::new();
        if t > 0 && t <= 600 && t.is_multiple_of(60) {
            let (x, z) = match t {
                600 => (30, 9),
                _ if (t / 60).is_multiple_of(2) => (12, 12),
                _ => (9, 14),
            };
            lines.push(format!("attack,{rifle},{},{}", x << 16, z << 16));
        }
        if t % 60 == 20 {
            let stance = ["defensive", "aggressive", "hold"][usize::try_from(t / 60 % 3).unwrap()];
            lines.push(format!("stance,{rifle},{stance}"));
        }
        if t % 120 == 40 {
            lines.push(format!("stop,{rifle}"));
        }
        if t % 300 == 150 {
            lines.push(format!("perk,{}", t / 300 % 12));
            lines.push("junk,9".to_owned());
        }
        if t % 30 == 10 {
            if let Some([first, ..]) = sim.depth_draft() {
                lines.push(format!("perk,{first}"));
            }
        }
        lines
    }

    /// Records `frames` bridge frames of `scenario` at `seed` (Normal; a run
    /// with the default pool when `run`) into `dir` through the bridge's
    /// stepped-frame body ([`step_frame`] with a [`ReplayRecorder`]), and
    /// returns the replay text.
    fn record_test_match(
        dir: &Path,
        scenario: Scenario,
        seed: u64,
        run: bool,
        frames: u32,
    ) -> String {
        let cfg = MatchConfig {
            seed,
            run,
            replay_dir: Some(dir.to_path_buf()),
            ..MatchConfig::boot(scenario)
        };
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        let path = recorder
            .start(&cfg, true, &sim)
            .unwrap()
            .expect("recording");
        for _ in 0..frames {
            let accepted = accept_lines(t25_lines(&sim), |_| true);
            step_frame(&mut sim, scenario, accepted, &mut recorder).expect("recording");
        }
        recorder.stop(&sim).unwrap();
        std::fs::read_to_string(path).unwrap()
    }

    /// Plays `text` back through [`ReplayPlayback::frame`] at `speed` until it
    /// holds at its END: the `(tick, hash)` after every stepped tick.
    fn play_back(text: &str, speed: f32) -> Vec<(u64, u64)> {
        let mut playback = ReplayPlayback::new(ReplayPlayer::new(text).unwrap());
        let mut sim = playback.build();
        let mut seen = Vec::new();
        let mut idle_frames = 0;
        while idle_frames < 4 {
            let stepped =
                playback.frame(&mut sim, speed, |s| seen.push((s.tick(), s.state_hash())));
            idle_frames = if stepped == 0 { idle_frames + 1 } else { 0 };
        }
        seen
    }

    #[test]
    fn recorded_bridge_run_verifies_headless() {
        let dir = tempdir_in_target("verify_round_trip");
        let text = record_test_match(&dir, Scenario::KestrelReach, 77, /* run */ true, 3000);
        assert!(
            text.contains("\nT 600 attack,"),
            "the scripted player was recorded"
        );
        assert!(
            text.contains(" perk,"),
            "refused perk picks are recorded too"
        );
        let r = verify(&text).unwrap();
        assert!(r.ok(), "{r:?}");
        assert_eq!(r.ticks, 3000);
    }

    #[test]
    fn tampered_replay_fails() {
        let dir = tempdir_in_target("verify_tamper");
        let text = record_test_match(&dir, Scenario::KestrelReach, 77, false, 3000);
        // The untampered file passes, so a failure below is the tamper's.
        assert!(verify(&text).unwrap().ok());
        let bad = text.replacen("T 600 attack,", "T 601 attack,", 1);
        assert_ne!(bad, text, "the tamper changed the file");
        let r = verify(&bad).unwrap();
        assert!(!r.ok(), "{r:?}");
        let bad_end = text
            .rsplit_once("END")
            .map(|(a, _)| format!("{a}END 3000 1 0\n"))
            .unwrap();
        assert!(!verify(&bad_end).unwrap().ok());
    }

    #[test]
    fn playback_at_8x_equals_1x() {
        let dir = tempdir_in_target("verify_speed");
        let text = record_test_match(&dir, Scenario::KestrelReach, 9, false, 2000);
        let one = play_back(&text, 1.0);
        assert_eq!(one.len(), 2000, "every tick is stepped once");
        assert_eq!(one, play_back(&text, 8.0));
        assert_eq!(play_back(&text, 0.5), one);
        assert_eq!(play_back(&text, 2.0), one);
        assert_eq!(play_back(&text, 4.0), one);
        let end = ReplayPlayer::new(&text).unwrap();
        assert_eq!(one.last(), Some(&(2000, end.expected_hash())));
    }

    #[test]
    fn verify_reads_pool_from_header_only() {
        let dir = tempdir_in_target("verify_pool");
        let text = record_test_match(&dir, Scenario::KestrelReach, 5, true, 3000);
        // no settings or meta file is consulted: the header pool alone rebuilds the run
        assert!(text.contains("perk_pool="));
        assert!(verify(&text).unwrap().ok());
        // Another pool in the header is another run: it no longer verifies.
        let other = text.replacen("perk_pool=255", "perk_pool=4095", 1);
        assert_ne!(other, text);
        assert!(!verify(&other).unwrap().ok());
    }

    /// The speed control file: 0 (pause), 0.5, 1, 2, 4 and 8; anything else is 1.
    #[test]
    fn parse_speed_takes_the_six_speeds_and_falls_back_to_one() {
        for (text, want) in [
            ("0", 0.0),
            ("0.5", 0.5),
            ("1", 1.0),
            ("2", 2.0),
            ("4", 4.0),
            ("8\n", 8.0),
            (" 4 ", 4.0),
            ("8.0", 8.0),
        ] {
            assert!((parse_speed(text) - want).abs() < f32::EPSILON, "{text:?}");
        }
        for text in [
            "", "3", "16", "-1", "0.25", "NaN", "inf", "fast", "8x", "1e9",
        ] {
            assert!((parse_speed(text) - 1.0).abs() < f32::EPSILON, "{text:?}");
        }
    }

    /// 0.5x steps on every other frame, 8x eight ticks a frame, 0 holds, and
    /// the playback holds at END whatever the speed.
    /// The recorder closes a replay at the first decided tick (its `END` is the
    /// winning tick), and `ReplayPlayer::is_done` stops on a winner, so a
    /// decided match verifies and plays back to exactly that tick.
    #[test]
    fn a_decided_match_verifies_and_plays_back_to_its_winning_tick() {
        let dir = tempdir_in_target("verify_decided");
        let cfg = MatchConfig {
            seed: 3,
            difficulty: Difficulty::Hard,
            replay_dir: Some(dir.0.clone()),
            ..MatchConfig::boot(Scenario::KestrelReach)
        };
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        let path = recorder.start(&cfg, true, &sim).unwrap().unwrap();
        // Undefended on Hard the base falls near t=4006 (Task 24's recipe).
        run_frames(&mut sim, cfg.scenario, &mut recorder, 4600);
        let won_at = sim.tick();
        assert!(
            sim.winner().is_some() && won_at < 4600,
            "decided at {won_at}"
        );
        let text = std::fs::read_to_string(path).unwrap();
        let report = verify(&text).unwrap();
        assert!(report.ok(), "{report:?}");
        assert_eq!(report.ticks, won_at);
        let seen = play_back(&text, 8.0);
        assert_eq!(seen.last(), Some(&(won_at, sim.state_hash())));
    }

    #[test]
    fn playback_frames_step_by_speed_and_hold_at_end() {
        let dir = tempdir_in_target("verify_frames");
        let text = record_test_match(&dir, Scenario::KestrelReach, 9, false, 40);
        let mut playback = ReplayPlayback::new(ReplayPlayer::new(&text).unwrap());
        let mut sim = playback.build();
        let mut frame = |speed: f32| playback.frame(&mut sim, speed, |_| {});
        assert_eq!(
            [frame(0.5), frame(0.5), frame(0.5), frame(0.5)],
            [0, 1, 0, 1]
        );
        assert_eq!(frame(0.0), 0);
        assert_eq!(frame(8.0), 8);
        assert_eq!(frame(1.0), 1);
        assert_eq!(frame(4.0), 4);
        assert_eq!(frame(8.0), 8);
        assert_eq!(frame(8.0), 8);
        // 31 stepped; the END at 40 caps the next frames.
        assert_eq!(frame(8.0), 8);
        assert_eq!(frame(8.0), 1);
        assert_eq!(frame(8.0), 0);
        assert_eq!(frame(1.0), 0);
        assert_eq!(sim.tick(), 40);
        assert_eq!(sim.tick(), playback.end_tick());
    }

    #[test]
    fn replay_player_groups_lines_by_tick() {
        let text = format!(
            "{}T 3 stop,1\nT 3 hold,2\nT 9 perk,4\nEND 00000000000000000012 00000000000000000001 -0000000000000000003\n",
            header(4).to_text()
        );
        let player = ReplayPlayer::new(&text).unwrap();
        assert_eq!(player.end_tick(), 12);
        assert_eq!(player.expected_hash(), 1);
        assert_eq!(player.expected_score(), -3);
        assert_eq!(player.header().seed, 4);
        let three = player.commands_for(3);
        assert!(matches!(
            three.as_slice(),
            [
                Command::Stop {
                    unit: EntityId(1),
                    ..
                },
                Command::HoldPosition {
                    unit: EntityId(2),
                    ..
                }
            ]
        ));
        assert!(matches!(
            player.commands_for(9).as_slice(),
            [Command::ChoosePerk { perk: 4, .. }]
        ));
        for tick in [0, 2, 4, 8, 10, 12, u64::MAX] {
            assert!(player.commands_for(tick).is_empty(), "{tick}");
        }
    }

    /// The file is untrusted: every malformed or hostile variant is refused
    /// with a message, never a panic.
    #[test]
    fn verify_refuses_malformed_and_hostile_files() {
        let head = header(4).to_text();
        let end = "END 00000000000000000012 00000000000000000001 00000000000000000000\n";
        let good = format!("{head}T 3 stop,1\n{end}");
        assert!(ReplayPlayer::new(&good).is_ok());
        assert!(
            ReplayPlayer::new(&format!("{head}END 12 1 -3\n")).is_ok(),
            "unpadded numbers parse"
        );
        let min = i64::MIN;
        let bad = [
            String::new(),
            "RPL0\n".to_owned(),
            good.replacen("RPL1", "rpl1", 1),
            good.replacen("scenario=kestrel", "scenario=atlantis", 1),
            good.replacen("difficulty=hard", "difficulty=nightmare", 1),
            good.replacen(&format!("balance={}", balance_hash()), "balance=1", 1),
            // truncated: no END at all, or a torn END
            head.clone(),
            format!("{head}T 3 stop,1\n"),
            format!("{head}T 3 stop,1\nEND 0000000000"),
            // two ENDs, a line after END
            format!("{head}{end}{end}"),
            format!("{head}{end}T 3 stop,1\n"),
            // non-monotonic ticks, a line at or past END
            format!("{head}T 5 stop,1\nT 4 stop,1\n{end}"),
            format!("{head}T 12 stop,1\n{end}"),
            format!("{head}T 13 stop,1\n{end}"),
            // malformed or hostile T lines
            format!("{head}T 99999999999999999999999 stop,1\n{end}"),
            format!("{head}T -3 stop,1\n{end}"),
            format!("{head}T +3 stop,1\n{end}"),
            format!("{head}T 3\n{end}"),
            format!("{head}T 3 \n{end}"),
            format!("{head}T 3 junk,1\n{end}"),
            format!("{head}T 3 move,1,{min},0\n{end}"),
            format!("{head}T  3 stop,1\n{end}"),
            // malformed END lines, an absurd END tick
            format!("{head}END 12 1\n"),
            format!("{head}END 12 1 0 0\n"),
            format!("{head}END x 1 0\n"),
            format!("{head}END 12 1 +0\n"),
            format!("{head}END 12 18446744073709551616 0\n"),
            format!("{head}END 12 1 9223372036854775808\n"),
            format!("{head}END 400001 1 0\n"),
            format!("{head}END 18446744073709551615 1 0\n"),
            // unknown or blank body lines
            format!("{head}X 3 stop,1\n{end}"),
            format!("{head}\n{end}"),
        ];
        for text in &bad {
            let err = ReplayPlayer::new(text).expect_err(text);
            assert!(!err.is_empty());
            assert!(verify(text).is_err(), "{text:?}");
        }
        // The documented cap itself is accepted (it only bounds the work).
        assert_eq!(
            ReplayPlayer::new(&format!("{head}END {VERIFY_MAX_TICKS} 1 0\n"))
                .unwrap()
                .end_tick(),
            400_000
        );
        assert!(verify(&"T".repeat(VERIFY_MAX_BYTES + 1)).is_err());
    }

    /// A command the core refuses (here: selling a building that does not
    /// exist, a perk with no draft pending) is a no-op when replayed, exactly
    /// as it would have been live: inserted into
    /// a recording it changes nothing, so the replay still verifies.
    #[test]
    fn an_inserted_command_the_core_refuses_changes_nothing() {
        let dir = tempdir_in_target("verify_refused");
        let text = record_test_match(&dir, Scenario::KestrelReach, 12, false, 300);
        assert!(verify(&text).unwrap().ok());
        let with_refused = text.replacen("\n\n", "\n\nT 7 sell,99999\nT 8 perk,3\n", 1);
        assert_ne!(with_refused, text);
        assert!(verify(&with_refused).unwrap().ok());
    }

    /// Deterministic fuzzing over mutations of a real recording: verify never
    /// panics, whatever the bytes (each run capped at 1500 ticks for speed;
    /// the cap itself is the documented guard against absurd END ticks).
    #[test]
    fn mutated_recordings_never_panic_the_verifier() {
        let dir = tempdir_in_target("verify_fuzz");
        let text = record_test_match(&dir, Scenario::KestrelReach, 31, true, 400);
        assert!(verify(&text).unwrap().ok());
        let base: Vec<&str> = text.lines().collect();
        let mut state = 0x2545_f491_4f6c_dd1d_u64;
        let mut next = |bound: usize| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            usize::try_from(state % u64::try_from(bound.max(1)).unwrap()).unwrap()
        };
        let (mut refused, mut matched, mut mismatched) = (0, 0, 0);
        for round in 0..400 {
            let mut lines: Vec<String> = base.iter().map(|l| (*l).to_owned()).collect();
            let at = next(lines.len());
            match round % 10 {
                0 => {
                    lines.remove(at);
                }
                1 => {
                    let copy = lines[at].clone();
                    lines.insert(next(lines.len()), copy);
                }
                2 => {
                    let other = next(lines.len());
                    lines.swap(at, other);
                }
                3 => {
                    // one byte becomes a digit, a letter, a sign or a space
                    let mut bytes = lines[at].clone().into_bytes();
                    if !bytes.is_empty() {
                        let i = next(bytes.len());
                        bytes[i] = b"0123456789-+ ,xT\t"[next(17)];
                    }
                    lines[at] = String::from_utf8(bytes).unwrap();
                }
                4 => {
                    // a torn line (the recording is ASCII)
                    let cut = next(lines[at].len() + 1);
                    lines[at].truncate(cut);
                }
                5 => lines.truncate(at),
                6 => lines.insert(at, format!("T {} stop,{}", next(2000), next(50))),
                7 => {
                    let huge = ["18446744073709551615", "99999999999999999999999", "-1", ""];
                    lines.insert(at, format!("T {} stop,1", huge[next(4)]));
                }
                8 => {
                    let end = format!(
                        "END {} {} {}",
                        ["400001", "1499", "0", "18446744073709551615"][next(4)],
                        next(1000),
                        ["0", "-5", "9223372036854775807", "-9223372036854775808"][next(4)]
                    );
                    lines.push(end);
                }
                _ => {
                    let junk = [
                        "",
                        "END",
                        "T",
                        "RPL1",
                        "seed=1",
                        "T 1 move,1,9223372036854775807,0",
                    ];
                    lines.insert(at, junk[next(junk.len())].to_owned());
                }
            }
            let mutated = lines.join("\n") + "\n";
            match verify_with_limit(&mutated, 1500) {
                Err(_) => refused += 1,
                Ok(report) if report.ok() => matched += 1,
                Ok(_) => mismatched += 1,
            }
        }
        assert_eq!(refused + matched + mismatched, 400);
        assert!(
            refused > 100 && mismatched > 0,
            "{refused} {matched} {mismatched}"
        );
    }

    /// Task 25: `match.json` may name a replay to play back (an absolute
    /// path, as `replay_dir`); anything else plays no replay.
    #[test]
    fn match_config_parses_an_absolute_replay_file() {
        let c = parse_match_config(
            r#"{"scenario":"kestrel","replay":"/tmp/r/1_kestrel_7.rpl","replay_dir":"/tmp/r"}"#,
            Scenario::KestrelReach,
        );
        assert_eq!(c.replay, Some(PathBuf::from("/tmp/r/1_kestrel_7.rpl")));
        assert_eq!(c.replay_dir, Some(PathBuf::from("/tmp/r")));
        for bad in [
            r#"{"scenario":"kestrel","replay_dir":"/tmp/r"}"#,
            r#"{"replay":"r.rpl"}"#,
            r#"{"replay":"user://replays/a.rpl"}"#,
            r#"{"replay":7}"#,
            r#"{"replay":""}"#,
            "not json",
        ] {
            assert_eq!(
                parse_match_config(bad, Scenario::KestrelReach).replay,
                None,
                "{bad}"
            );
        }
        assert_eq!(MatchConfig::boot(Scenario::KestrelReach).replay, None);
    }
}
