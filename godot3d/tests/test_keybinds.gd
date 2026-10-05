extends RefCounted
## Drift guard for the controls screen. A real key event needs the whole 3D scene, so the handlers are pinned at source
## level: the sources are read as text. Three guarantees: every key the screen shows is a constant the handler compares
## against, no handler compares against a literal KEY_, and every constant is on the screen.
const KB := preload("res://scripts/ui/keybinds.gd")
const NOT_KEYS := ["THEN", "PLUS", "CAPS", "CAMERA_ACTIONS"]


func _handler_sources() -> String:
	var text := ""
	for path in ["res://scripts/earthfront_3d.gd", "res://scripts/ui/game_ui.gd", "res://scripts/ui/hud.gd"]:
		text += (load(path) as GDScript).source_code + "\n"
	return text + FileAccess.get_file_as_string("res://project.godot")


## constant name -> keycodes it holds (an int, an array of ints, or a dictionary keyed by int).
func _constants() -> Dictionary:
	var out := {}
	var script: GDScript = KB
	var map: Dictionary = script.get_script_constant_map()
	for name in map:
		if name in NOT_KEYS:
			continue
		var v: Variant = map[name]
		if v is int:
			out[name] = [v]
		elif v is Array:
			out[name] = v.duplicate()
		elif v is Dictionary:
			out[name] = v.keys()
	return out


func _camera_codes() -> Array:
	return KB.CAMERA_ACTIONS.values()


func test_every_key_shown_is_a_constant_the_handler_reads(t) -> void:
	var src := _handler_sources()
	var consts := _constants()
	for code in KB.shown_codes():
		if code in _camera_codes():
			continue
		var read := false
		var any_const := false
		for name in consts:
			if code in consts[name]:
				any_const = true
				if src.contains("Keybinds." + name):
					read = true
		t.ok(any_const, "key %s is shown but is no constant in keybinds.gd" % KB.cap(code))
		t.ok(read, "key %s is shown but no handler reads Keybinds.<its constant>" % KB.cap(code))


func test_every_constant_is_on_the_screen(t) -> void:
	var shown := KB.shown_codes()
	var consts := _constants()
	for name in consts:
		for code in consts[name]:
			t.ok(code in shown, "%s (%s) is bound but missing from the controls screen" % [name, KB.cap(code)])


func test_handlers_hold_no_literal_key_constants(t) -> void:
	for path in ["res://scripts/earthfront_3d.gd", "res://scripts/ui/game_ui.gd"]:
		var code := ""
		for line in (load(path) as GDScript).source_code.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		t.ok(not code.contains("KEY_"), "%s compares against a literal KEY_ instead of a Keybinds constant" % path)


func test_camera_keys_are_the_real_input_map(t) -> void:
	for action in KB.CAMERA_ACTIONS:
		t.ok(InputMap.has_action(action), action + " exists in project.godot")
		var bound := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and ev.physical_keycode == KB.CAMERA_ACTIONS[action]:
				bound = true
		t.ok(bound, "%s is bound to %s" % [action, KB.cap(KB.CAMERA_ACTIONS[action])])
		t.ok(_handler_sources().contains("\"%s\"" % action), "the camera code reads " + action)
	for action in InputMap.get_actions():
		if str(action).begins_with("camera_"):
			t.ok(KB.CAMERA_ACTIONS.has(str(action)), "%s is an InputMap camera action the controls screen does not list" % action)


func test_rows_without_a_key_are_proved_by_a_source_needle(t) -> void:
	var src := _handler_sources()
	for g in KB.groups():
		for row in g["rows"]:
			var has_code := false
			for k in row["keys"]:
				if k is int or k is Array:
					has_code = true
			if not has_code:
				t.ok(str(row["proof"]) != "", "%s has no keycode and no proof" % row["label"])
			if str(row["proof"]) != "":
				t.ok(src.contains(str(row["proof"])), "%s: the handler has no `%s`" % [row["label"], row["proof"]])


func test_f1_collides_with_nothing(t) -> void:
	for action in InputMap.get_actions():
		var ev := InputEventKey.new()
		ev.keycode = KB.CONTROLS
		ev.physical_keycode = KB.CONTROLS
		t.ok(not InputMap.event_is_action(ev, action), "F1 is also the InputMap action " + str(action))
	var consts := _constants()
	for name in consts:
		if name != "CONTROLS":
			t.ok(not (KB.CONTROLS in consts[name]), "F1 is also " + name)
	t.eq(KB.PAUSE, KEY_ESCAPE, "Esc opens the pause menu")
	t.eq(KB.CANCEL, KB.PAUSE, "the cancel key and the pause key are the same Esc")
	t.eq(KB.CONTROLS, KEY_F1, "F1 opens the controls")


func test_deck_card_hotkeys_agree_with_the_bindings(t) -> void:
	var adapter = load("res://scripts/ui/live_adapter.gd")
	for card in adapter.BUILD_CARDS:
		var kind: String = card[1]
		var shown: String = card[3]
		var code := -1
		for k in KB.BUILD:
			if KB.BUILD[k] == kind:
				code = k
		t.eq(shown, KB.cap(code) if code >= 0 else "", "%s: the deck card hotkey is the bound key" % kind)
	for card in adapter.UNIT_CARDS:
		var kind: String = card[3]
		var shown: String = card[2]
		var code := -1
		for k in KB.TRAIN:
			if KB.TRAIN[k] == kind:
				code = k
		t.eq(shown, KB.cap(code) if code >= 0 else "", "%s: the deck card hotkey is the bound key" % kind)


func test_screen_text_has_no_dashes_and_rows_are_unique(t) -> void:
	for g in KB.groups():
		var seen := {}
		for row in g["rows"]:
			var label: String = row["label"]
			t.ok(label != "" and not label.contains("\u2014") and not label.contains("\u2013"), "label: " + label)
			t.ok(not seen.has(label), "%s is listed twice in %s" % [label, g["name"]])
			seen[label] = true
	var vm := KB.vm()
	for key in ["subtitle", "tip", "cap"]:
		t.ok(not str(vm[key]).contains("\u2014") and not str(vm[key]).contains("\u2013"), key)
	t.eq(KB.cap(KEY_ESCAPE), "Esc", "Esc cap")
	t.eq(KB.cap(KEY_F2), "F2", "F2 cap")
	t.eq(KB.cap(KEY_PERIOD), ".", "period cap")
	t.eq(KB.cap(KEY_DELETE), "Del", "delete cap")


func test_the_screen_is_grouped_as_the_board_groups_it(t) -> void:
	var names: Array = []
	for g in KB.groups():
		names.append(g["name"])
	t.eq(names, ["Camera", "System", "Selection", "Build", "Orders", "Production"], "the six board groups")
	var vm := KB.vm()
	t.eq(vm["columns"].size(), 3, "three columns")
	t.eq(vm["columns"][0].map(func(g): return g["name"]), ["Camera", "System"], "column 1")
	t.eq(vm["columns"][1].map(func(g): return g["name"]), ["Selection", "Build"], "column 2")
	t.eq(vm["columns"][2].map(func(g): return g["name"]), ["Orders", "Production"], "column 3")
