extends RefCounted
## The player's settings: the only code that opens `user://settings.cfg` (sections audio, video, game; later tasks add
## coach and run). Every function takes the file path so tests use their own (user://test_<name>/...); nothing is ever
## written under res://. Values are flat keys "section/name" with the defaults() shape: a missing or corrupt file reads
## as the defaults, a wrong type falls back to the default and a volume is clamped to 0..1.
##
## Volumes act on the buses of default_bus_layout.tres (linear 0..1 to dB, 0 mutes the bus). The audio pool's duck of the
## Ambient and Music buses (audio_pool.set_duck) goes through apply_duck, so it lowers the player's level instead of
## replacing it. Both take the audio server as an optional argument (tests pass a recording stub, never a real device).
const PATH := "user://settings.cfg"
const BUSES := {"audio/master": "Master", "audio/sfx": "SFX", "audio/ui": "UI", "audio/ambient": "Ambient", "audio/music": "Music"}
## The buses the audio pool ducks under explosions and alerts.
const DUCKED := ["Ambient", "Music"]
const WINDOW_MODES := ["windowed", "fullscreen"]
## A muted bus keeps this level under its mute flag (linear_to_db(0) is -inf).
const SILENT_DB := -80.0
## Per audio server object: {bus: dB the player chose} and the pool's current duck (Object meta, so a test stub never
## shares state with the real AudioServer).
const LEVELS_META := "settings_bus_db"
const DUCK_META := "settings_duck_db"


static func defaults() -> Dictionary:
	return {"audio/master": 1.0, "audio/sfx": 1.0, "audio/ui": 1.0, "audio/ambient": 1.0, "audio/music": 1.0, "game/fog": true, "video/window_mode": "windowed"}


## The file's values over the defaults. Missing file, unreadable or malformed text: the defaults.
static func load_from(path: String) -> Dictionary:
	var out := defaults()
	if not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	# ConfigFile reports a parse error as an engine ERROR line; a file this module did not write is checked first and
	# read as the defaults instead.
	if not _well_formed(text):
		return out
	var cf := ConfigFile.new()
	if cf.parse(text) != OK:
		return out
	for key in out:
		var parts: PackedStringArray = str(key).split("/")
		if cf.has_section_key(parts[0], parts[1]):
			out[key] = _clean(key, cf.get_value(parts[0], parts[1]))
	return out


## Writes every known key (cleaned) through `path`.next and a rename, so a crash never leaves half a file. Refuses any
## res:// path with ERR_FILE_NO_PERMISSION.
static func save_to(path: String, values: Dictionary) -> int:
	if path.begins_with("res://"):
		return ERR_FILE_NO_PERMISSION
	var base := defaults()
	var cf := ConfigFile.new()
	for key in base:
		var parts: PackedStringArray = str(key).split("/")
		cf.set_value(parts[0], parts[1], _clean(key, values.get(key, base[key])))
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var next := path + ".next"
	var err := cf.save(next)
	if err != OK:
		return err
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(next), ProjectSettings.globalize_path(path))


## One value (the default when the key is unknown to the file); null for a key defaults() does not have.
static func get_value(key: String, path := PATH) -> Variant:
	return load_from(path).get(key)


## Changes one known key and saves the file. ERR_INVALID_PARAMETER for a key defaults() does not have.
static func set_value(key: String, value: Variant, path := PATH) -> int:
	if not defaults().has(key):
		return ERR_INVALID_PARAMETER
	var values := load_from(path)
	values[key] = value
	return save_to(path, values)


## Sets each bus from its volume: linear to dB, and 0 mutes the bus. `server` defaults to the AudioServer.
static func apply_audio(values: Dictionary, server: Object = null) -> void:
	var s: Object = server if server != null else AudioServer
	var levels := {}
	for key in BUSES:
		var v: float = _clean(key, values.get(key, 1.0))
		levels[BUSES[key]] = linear_to_db(v) if v > 0.0 else SILENT_DB
	s.set_meta(LEVELS_META, levels)
	for key in BUSES:
		var bus: String = BUSES[key]
		var idx: int = s.get_bus_index(bus)
		if idx < 0:
			continue
		s.set_bus_mute(idx, float(_clean(key, values.get(key, 1.0))) <= 0.0)
		s.set_bus_volume_db(idx, bus_db(bus, s))


## The audio pool's duck (dB, 0 = none) on the Ambient and Music buses, added to the player's level for each.
static func apply_duck(db: float, server: Object = null) -> void:
	var s: Object = server if server != null else AudioServer
	s.set_meta(DUCK_META, db)
	for bus in DUCKED:
		var idx: int = s.get_bus_index(bus)
		if idx >= 0:
			s.set_bus_volume_db(idx, bus_db(bus, s))


## What a bus is set to: the player's level (0 dB before apply_audio) plus the duck on the ducked buses.
static func bus_db(bus: String, server: Object = null) -> float:
	var s: Object = server if server != null else AudioServer
	var levels: Dictionary = s.get_meta(LEVELS_META, {})
	var db := float(levels.get(bus, 0.0))
	if bus in DUCKED:
		db += float(s.get_meta(DUCK_META, 0.0))
	return db


## Windowed or fullscreen. Only a real change is made (a maximised window already counts as windowed), so a launch with
## the defaults never touches the window. Nothing on the headless display server. `display` defaults to the DisplayServer.
static func apply_window(values: Dictionary, display: Object = null) -> void:
	var d: Object = display
	if d == null:
		if DisplayServer.get_name() == "headless":
			return
		d = DisplayServer
	var full: bool = _clean("video/window_mode", values.get("video/window_mode", "windowed")) == "fullscreen"
	var now: int = d.window_get_mode()
	var is_full := now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if full and not is_full:
		d.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and is_full:
		d.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## A value as the key's type: volumes clamped to 0..1, a bool for the fog, a known window mode. Anything else: the default.
static func _clean(key: String, value: Variant) -> Variant:
	var base: Variant = defaults().get(key)
	if key.begins_with("audio/"):
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return base
		var v := float(value)
		return clampf(v, 0.0, 1.0) if is_finite(v) else base
	if key == "game/fog":
		return value if typeof(value) == TYPE_BOOL else base
	if key == "video/window_mode":
		return value if typeof(value) == TYPE_STRING and value in WINDOW_MODES else base
	return value if typeof(value) == typeof(base) else base


## True when every line is blank, a ; or # comment, a [section] header or a `key=value` with a scalar value (a number,
## true/false or a quoted string): what ConfigFile.save writes for these keys.
static func _well_formed(text: String) -> bool:
	var header := RegEx.create_from_string("^\\[[A-Za-z0-9_]+\\]$")
	var pair := RegEx.create_from_string("^[A-Za-z0-9_]+\\s*=\\s*(true|false|-?[0-9]+(\\.[0-9]+)?([eE][-+]?[0-9]+)?|\"[^\"\\\\]*\")$")
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if header.search(line) == null and pair.search(line) == null:
			return false
	return true
