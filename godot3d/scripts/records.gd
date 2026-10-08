extends RefCounted
## Personal bests (Task 22): the only code that opens `user://records.cfg`. One section per map, one key per difficulty,
## the best score total as an int ("[kestrel]" then "normal=17504"). Every function takes the file path so tests use
## their own (user://test_<name>/...); nothing is ever written under res://. A missing, unreadable or malformed file
## reads as no records; a value that is not a non-negative int reads as none.
const PATH := "user://records.cfg"
## Map and difficulty keys: lower case letters, digits and underscores ("kestrel", "normal").
const KEY_PATTERN := "^[a-z0-9_]+$"


## The best total recorded for `map` at `difficulty`, 0 when there is none (or the file cannot be read).
static func best(map: String, difficulty: String, path := PATH) -> int:
	return int(load_from(path).get(_key(map, difficulty), 0))


## Records `total` (negative counts as 0) when it beats the stored best for `map` at `difficulty`, or when there is none
## yet. True only when it was a new best and the file was written. Refuses res:// paths and malformed keys (false).
static func submit(map: String, difficulty: String, total: int, path := PATH) -> bool:
	if path.begins_with("res://") or not _valid(map) or not _valid(difficulty):
		return false
	var all := load_from(path)
	var key := _key(map, difficulty)
	var score := maxi(total, 0)
	if all.has(key) and score <= int(all[key]):
		return false
	all[key] = score
	return save_to(path, all) == OK


## Every record in the file as {"map/difficulty": total}. Missing, unreadable or malformed: {}.
static func load_from(path := PATH) -> Dictionary:
	var out := {}
	if path.begins_with("res://") or not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	# ConfigFile reports a parse error as an engine ERROR line; text this module did not write is checked first.
	if not _well_formed(text):
		return out
	var cf := ConfigFile.new()
	if cf.parse(text) != OK:
		return out
	for map in cf.get_sections():
		if not _valid(map):
			continue
		for difficulty in cf.get_section_keys(map):
			var v: Variant = cf.get_value(map, difficulty)
			if _valid(difficulty) and typeof(v) == TYPE_INT and int(v) >= 0:
				out[_key(map, difficulty)] = int(v)
	return out


## Writes `records` ({"map/difficulty": total}) through `path`.next and a rename, so a crash never leaves half a file.
## ERR_FILE_NO_PERMISSION for a res:// path.
static func save_to(path: String, records: Dictionary) -> int:
	if path.begins_with("res://"):
		return ERR_FILE_NO_PERMISSION
	var cf := ConfigFile.new()
	for key in records:
		var parts: PackedStringArray = str(key).split("/")
		if parts.size() == 2 and _valid(parts[0]) and _valid(parts[1]):
			cf.set_value(parts[0], parts[1], maxi(int(records[key]), 0))
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


static func _key(map: String, difficulty: String) -> String:
	return map + "/" + difficulty


static func _valid(key: String) -> bool:
	return RegEx.create_from_string(KEY_PATTERN).search(key) != null


## True when every line is blank, a ; or # comment, a [section] header or a `key=value` with a scalar value (a number,
## true/false or a quoted string): what ConfigFile.save writes. Anything else would make ConfigFile log an error.
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
