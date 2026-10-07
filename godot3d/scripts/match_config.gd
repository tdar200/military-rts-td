extends RefCounted
## The next match, as the bridge reads it: `match.json` in the runtime directory, read when `restart.flag` arrives
## (godot-bridge.rs parse_match_config: a quoted `scenario`, a bare `fog`; `seed` and `difficulty` ride along for later
## tasks). The config of the running match and the "deploy after this reload" request live in Engine meta, so they survive
## the scene reload a restart does (a static var alone is not promised to).
const SCENARIOS := ["kestrel", "survival"]
const NAMES := {"kestrel": "Kestrel Reach", "survival": "Earthfront Survival"}
const KEYS := ["scenario", "seed", "difficulty", "fog"]
const META := "match_config"
const AUTO_META := "auto_deploy"

## The running match's config: the defaults until one is chosen. Reading returns a copy; assigning stores a copy.
static var current: Dictionary:
	get:
		return (Engine.get_meta(META) as Dictionary).duplicate() if Engine.has_meta(META) else defaults()
	set(value):
		Engine.set_meta(META, value.duplicate())


static func defaults() -> Dictionary:
	return {"scenario": "kestrel", "seed": 2026, "difficulty": "normal", "fog": true}


## Flat JSON in a fixed key order. Missing keys take the defaults and an unknown map falls back to Kestrel Reach, so the
## bridge never sees a value it would have to reject.
static func to_json(cfg: Dictionary) -> String:
	var base := defaults()
	var out := {}
	for key in KEYS:
		out[key] = cfg.get(key, base[key])
	if not (str(out.scenario) in SCENARIOS):
		out.scenario = base.scenario
	out.seed = int(out.seed)
	out.fog = bool(out.fog)
	return JSON.stringify(out, "", false)


## Writes `match.json` atomically (`match.json.next`, then a rename), so the bridge never reads half a file. False when
## there is no runtime directory or the write failed.
static func write(runtime_dir: String, cfg: Dictionary) -> bool:
	if runtime_dir == "":
		return false
	var next := ProjectSettings.globalize_path(runtime_dir.path_join("match.json.next"))
	var file := FileAccess.open(next, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(cfg))
	file.close()
	return DirAccess.rename_absolute(next, ProjectSettings.globalize_path(runtime_dir.path_join("match.json"))) == OK


static func display_name(scenario: String) -> String:
	return NAMES.get(scenario, scenario)


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
	for key in [META, AUTO_META]:
		if Engine.has_meta(key):
			Engine.remove_meta(key)
