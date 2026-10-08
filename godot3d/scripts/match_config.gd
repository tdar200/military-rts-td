extends RefCounted
## The next match, as the bridge reads it: `match.json` in the runtime directory, read when `restart.flag` arrives
## (godot-bridge.rs parse_match_config: a quoted `scenario`, a bare `fog`, a bare unsigned `seed` and a quoted
## `difficulty`; a malformed seed is 2026 there and an unknown preset Normal). The fog comes from the player's settings
## (with_settings); the map picker draws a fresh seed on every open (random_seed) and the debrief's Restart replays the
## running match's seed and preset, which the bridge reports in the Kestrel depth block (from_snapshot). The config of
## the running match and the "deploy after this reload" request live in Engine meta, so they survive the scene reload a
## restart does (a static var alone is not promised to). Task 24: a Kestrel match.json also names `replay_dir`, the
## absolute path of user://replays, where the bridge records the match (it refuses any other kind of path).
## Task 26: a config may also hold `mode` ("operation" or "run": a Kestrel run sends `"run":true` and the remembered
## `perk_pool`) and `replay` (the absolute path of a recording the bridge plays back instead of a live match). Both are
## optional, so defaults() and the JSON of an operation are what they were.
const Settings = preload("res://scripts/ui/settings.gd")
const SCENARIOS := ["kestrel", "survival"]
const NAMES := {"kestrel": "Kestrel Reach", "survival": "Earthfront Survival"}
const KEYS := ["scenario", "seed", "difficulty", "fog"]
## Task 20: the Kestrel difficulty presets (godot-bridge.rs reads these names), Easy first.
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFFICULTY_NAMES := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
## Seeds the client draws or accepts: 1 to 2^31 - 1 (the bridge takes any u64; the client keeps to what an int and the
## seed field hold).
const SEED_MAX := 2147483647
const DEFAULT_SEED := 2026
const META := "match_config"
## Task 24: the bridge records Kestrel replays here (sent globalized; nothing in the client creates it).
const REPLAY_DIR := "user://replays"
const AUTO_META := "auto_deploy"
## Task 26: set once this process wrote a match.json (so the bridge's boot match is the only one it ever built without one).
const WRITTEN_META := "match_written"
## Task 26: the two ways to play Kestrel Reach. A run holds twelve waves with a perk draft after each cleared one.
const MODES := ["operation", "run"]
const MODE_NAMES := {"operation": "Operation", "run": "Run"}
## The perk pool a run may draw from (perk.rs DEFAULT_RUN_POOL and FULL_RUN_POOL): the first eight perks always, one more
## per run that reached wave 6 (Settings "run/perk_pool").
const DEFAULT_POOL := 0xFF
const FULL_POOL := 0xFFF
## A run ends at this many cleared waves (core RUN_WAVES).
const RUN_WAVES := 12

## The running match's config: the defaults until one is chosen. Reading returns a copy; assigning stores a copy.
static var current: Dictionary:
	get:
		return (Engine.get_meta(META) as Dictionary).duplicate() if Engine.has_meta(META) else defaults()
	set(value):
		Engine.set_meta(META, value.duplicate())


static func defaults() -> Dictionary:
	return {"scenario": "kestrel", "seed": DEFAULT_SEED, "difficulty": "normal", "fog": true}


## Flat JSON in a fixed key order. Missing keys take the defaults and an unknown map falls back to Kestrel Reach, so the
## bridge never sees a value it would have to reject. Task 24: a Kestrel match ends with `replay_dir` when `replays` is
## given (write passes replay_dir()); Survival never records, so its JSON is unchanged.
static func to_json(cfg: Dictionary, replays := "") -> String:
	var base := defaults()
	var out := {}
	for key in KEYS:
		out[key] = cfg.get(key, base[key])
	if not (str(out.scenario) in SCENARIOS):
		out.scenario = base.scenario
	out.seed = clean_seed(out.seed)
	out.difficulty = clean_difficulty(out.difficulty)
	out.fog = bool(out.fog)
	if out.scenario == "kestrel" and is_run(cfg):
		out["run"] = true
		out["perk_pool"] = clean_pool(cfg.get("perk_pool", DEFAULT_POOL))
	if out.scenario == "kestrel" and replays != "":
		out["replay_dir"] = replays
	var replay := str(cfg.get("replay", ""))
	if out.scenario == "kestrel" and replay.is_absolute_path():
		out["replay"] = replay
	return JSON.stringify(out, "", false)


## Task 26: a Kestrel run (`mode` "run"); anything else, or a missing mode, is an operation.
static func is_run(cfg: Dictionary) -> bool:
	return str(cfg.get("scenario", "kestrel")) == "kestrel" and str(cfg.get("mode", "operation")) == "run"


## A perk pool the bridge accepts from the client: the default eight bits set, nothing past the twelfth; else the default.
static func clean_pool(value: Variant) -> int:
	var n := int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else -1
	return n if n >= DEFAULT_POOL and n <= FULL_POOL and (n & DEFAULT_POOL) == DEFAULT_POOL else DEFAULT_POOL


## How many perks a pool holds.
static func pool_size(pool: int) -> int:
	var count := 0
	for bit in 12:
		if pool & (1 << bit):
			count += 1
	return count


## `cfg` with no replay in it: every path that starts a live match goes through this.
static func live(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	out.erase("replay")
	return out


## Task 26: the daily seed, the UTC date of `unix_time` as YYYYMMDD (20261007): everyone who plays the daily run on the
## same UTC day plays the same match, whatever their time zone.
static func daily_seed(unix_time: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(unix_time)
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


## Writes `match.json` atomically (`match.json.next`, then a rename), so the bridge never reads half a file. False when
## there is no runtime directory or the write failed.
static func write(runtime_dir: String, cfg: Dictionary) -> bool:
	if runtime_dir == "":
		return false
	var next := ProjectSettings.globalize_path(runtime_dir.path_join("match.json.next"))
	var file := FileAccess.open(next, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(cfg, replay_dir()))
	file.close()
	var ok := DirAccess.rename_absolute(next, ProjectSettings.globalize_path(runtime_dir.path_join("match.json"))) == OK
	if ok:
		Engine.set_meta(WRITTEN_META, true)
	return ok


## Task 26: true once this process wrote a match.json (write); the bridge's boot match was built without one.
static func written() -> bool:
	return bool(Engine.get_meta(WRITTEN_META, false))


## `cfg` for the next match: the fog follows the player's setting (Settings "game/fog" in `settings_path`), so the
## Settings screen's fog toggle lands in the next match.json whichever way the match starts.
static func with_settings(cfg: Dictionary, settings_path := Settings.PATH) -> Dictionary:
	var out := cfg.duplicate()
	out["fog"] = bool(Settings.get_value("game/fog", settings_path))
	return out


## Task 24: the absolute path of user://replays (the bridge takes only an absolute replay directory).
static func replay_dir() -> String:
	return ProjectSettings.globalize_path(REPLAY_DIR)


static func display_name(scenario: String) -> String:
	return NAMES.get(scenario, scenario)


## A fresh match seed in 1..SEED_MAX from a randomized generator: the map picker draws one on every open.
static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, SEED_MAX)


## `value` as a seed: an int, or a string of digits, in 1..SEED_MAX. Anything else (a float, a sign, a letter, out of
## range, empty) is `fallback`.
static func clean_seed(value: Variant, fallback := DEFAULT_SEED) -> int:
	var n := -1
	if typeof(value) == TYPE_INT:
		n = value
	elif typeof(value) == TYPE_STRING and value != "" and value.length() <= 10 and value.is_valid_int() and not value.begins_with("-") and not value.begins_with("+"):
		n = int(value)
	return n if n >= 1 and n <= SEED_MAX else fallback


## A known preset name, else "normal".
static func clean_difficulty(value: Variant) -> String:
	return str(value) if typeof(value) == TYPE_STRING and value in DIFFICULTIES else "normal"


## "Easy", "Normal" or "Hard" (an unknown preset reads as Normal).
static func difficulty_name(difficulty: Variant) -> String:
	return DIFFICULTY_NAMES[clean_difficulty(difficulty)]


## The running match's {seed, difficulty} from a bridge snapshot's Kestrel depth block; {} when there is none (no
## snapshot yet, or Survival, which has no presets). Task 26: a run adds {mode: "run", perk_pool}, so Restart replays it.
static func from_snapshot(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {}
	var depth: Variant = snapshot.get("depth", null)
	if not (depth is Dictionary) or not depth.has("seed"):
		return {}
	var seed: Variant = depth["seed"]
	if typeof(seed) == TYPE_FLOAT:
		seed = int(seed)  # JSON numbers parse as floats
	var out := {"seed": clean_seed(seed), "difficulty": clean_difficulty(depth.get("difficulty", "normal"))}
	var run: Variant = depth.get("run", null)
	if run is Dictionary:
		out["mode"] = "run"
		out["perk_pool"] = clean_pool(run.get("pool", DEFAULT_POOL))
	return out


## Task 26: the snapshot's run block ({wave, draft, pool, held}), or {} for an operation, Survival or no snapshot.
static func run_state(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {}
	var depth: Variant = snapshot.get("depth", null)
	if not (depth is Dictionary):
		return {}
	var run: Variant = depth.get("run", null)
	return run if run is Dictionary else {}


## Task 26: the bridge's replay block ({speed, tick, end}) while it plays a recording back, else {}.
static func replay_state(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {}
	var replay: Variant = snapshot.get("replay", null)
	return replay if replay is Dictionary else {}


## The map a bridge snapshot comes from ("" when there is none yet): only Kestrel Reach sends its Core Node.
static func running(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	return "kestrel" if snapshot.has("core_node") else "survival"


static func pending_auto_deploy() -> bool:
	return bool(Engine.get_meta(AUTO_META, false))


static func set_auto_deploy(on: bool) -> void:
	if on:
		Engine.set_meta(AUTO_META, true)
	elif Engine.has_meta(AUTO_META):
		Engine.remove_meta(AUTO_META)


## Forgets the chosen config and any pending auto deploy (tests; a new process starts this way anyway).
static func reset() -> void:
	for key in [META, AUTO_META, WRITTEN_META]:
		if Engine.has_meta(key):
			Engine.remove_meta(key)
