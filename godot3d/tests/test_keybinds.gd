extends RefCounted
## Drift guard for the controls screen. A real key event needs the whole 3D scene, so the handlers are pinned at source
## level: the sources are read as text. Three guarantees: every key the screen shows is a constant the handler compares
## against, no handler compares against a literal KEY_, and every constant is on the screen.
const KB := preload("res://scripts/ui/keybinds.gd")
const NOT_KEYS := ["THEN", "PLUS", "CAPS", "CAMERA_ACTIONS", "KESTREL_ONLY", "DEFENCES"]


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
	for code in KB.shown_codes() + KB.shown_codes(true):
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


## Kestrel's screen (world art on) lists every binding; Survival's leaves out only Kestrel's own keys (Space).
func test_every_constant_is_on_the_screen(t) -> void:
	var shown := KB.shown_codes(true)
	var survival := KB.shown_codes()
	for code in shown:
		t.ok(code in survival or code in KB.KESTREL_ONLY, "%s is on the Kestrel screen only, but is no Kestrel-only key" % KB.cap(code))
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
	for g in KB.groups() + KB.groups(true):
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
	for g in KB.groups() + KB.groups(true):
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
	# The board's six groups plus Defences: eleven build keys no longer fit one Build panel under Selection (Task 2).
	t.eq(names, ["Camera", "System", "Selection", "Build", "Defences", "Orders", "Production"], "the board's six groups and Defences")
	var vm := KB.vm()
	t.eq(vm["columns"].size(), 3, "three columns")
	# Camera, Selection and Orders head the columns as on the board; the rest are packed so every column ends above the footer.
	t.eq(vm["columns"][0].map(func(g): return g["name"]), ["Camera", "Production"], "column 1")
	t.eq(vm["columns"][1].map(func(g): return g["name"]), ["Selection", "Build"], "column 2")
	t.eq(vm["columns"][2].map(func(g): return g["name"]), ["Orders", "System", "Defences"], "column 3")


func test_the_map_key_collides_with_nothing(t) -> void:
	var owners: Array = []
	for name in _constants():
		if KEY_M in _constants()[name]:
			owners.append(str(name))
	t.eq(owners, ["REGION_MAP"], "M belongs to the strategic map alone (no build, train, ability or camera key uses it)")
	t.ok(not (KEY_M in _camera_codes()), "M is not a camera key")
	t.ok(not FileAccess.get_file_as_string("res://project.godot").contains("\"physical_keycode\":%d" % KEY_M), "project.godot binds no action to M")
	var count := 0
	for code in KB.shown_codes():
		if code == KEY_M:
			count += 1
	t.eq(count, 1, "M is on the controls screen once")
	var listed := false
	for col in KB.vm()["columns"]:
		for grp in col:
			for r in grp["rows"]:
				if r["label"] == "Strategic map" and r["keys"] == [{"t": "M"}]:
					listed = true
	t.ok(listed, "listed as Strategic map with the key cap M")


## Task 2 (kestrel-depth): the camera pans on the arrow keys, so W/A/S/D are free (A only arms attack-move).
func test_wasd_no_longer_pan(t) -> void:
	for action in ["camera_up", "camera_left", "camera_down", "camera_right"]:
		for ev in InputMap.action_get_events(action):
			t.ok(not (ev is InputEventKey and ev.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]), action)
	t.eq(KB.CAMERA_ACTIONS, {"camera_up": KEY_UP, "camera_left": KEY_LEFT, "camera_down": KEY_DOWN, "camera_right": KEY_RIGHT, "camera_rotate_left": KEY_Z, "camera_rotate_right": KEY_E}, "the six camera actions")
	var a := InputEventKey.new()
	a.keycode = KEY_A
	a.physical_keycode = KEY_A
	for action in KB.CAMERA_ACTIONS:
		t.ok(not InputMap.event_is_action(a, action), "A is no camera action (it was camera_left): " + str(action))


func test_nine_groups_and_new_build_keys_do_not_clash(t) -> void:
	t.eq(KB.GROUPS.size(), 9)
	t.eq(KB.GROUPS, [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9], "number keys 1 to 9")
	var seen := {}
	var all: Array = KB.GROUPS + KB.TRAIN.keys() + KB.BUILD.keys() + KB.CAMERA_ACTIONS.values() + [KB.ATTACK_MOVE, KB.ABILITY, KB.REPAIR, KB.SELL, KB.SCIENCE, KB.REGION_MAP, KB.FOCUS, KB.HOME, KB.JUMP_ALERT, KB.SELECT_IDLE, KB.SELECT_ARMY, KB.CONTROLS, KB.PAUSE, KB.STOP, KB.HOLD]
	for k in all:
		t.ok(not seen.has(k), "clash on %s" % KB.cap(k))
		seen[k] = true
	for kind in ["VehicleFactory", "Airfield", "SupplyDepot", "Battery"]:
		t.ok(KB.BUILD.values().has(kind), kind)
	t.eq(KB.BUILD.get(KEY_N, ""), "VehicleFactory", "N vehicle factory")
	t.eq(KB.BUILD.get(KEY_I, ""), "Airfield", "I airfield")
	t.eq(KB.BUILD.get(KEY_O, ""), "SupplyDepot", "O supply depot")
	t.eq(KB.BUILD.get(KEY_COMMA, ""), "Battery", "comma battery")
	t.eq(KB.cap(KEY_COMMA), ",", "comma cap")


func test_every_build_card_has_a_key(t) -> void:
	for card in load("res://scripts/ui/live_adapter.gd").BUILD_CARDS:
		t.ok(str(card[3]) != "", "%s has a hotkey" % card[1])


func test_pan_row_shows_the_arrows_and_drag_pan_is_listed(t) -> void:
	for kestrel in [false, true]:
		var rows := {}
		for g in KB.groups(kestrel):
			if g["name"] == "Camera":
				for r in g["rows"]:
					rows[r["label"]] = r
		t.eq(rows["Pan"]["keys"], [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT], "Pan shows the four arrows")
		t.ok(rows.has("Drag pan"), "a Drag pan row")
		t.eq(rows["Drag pan"]["keys"], ["Middle drag"], "Drag pan is the middle mouse button")
		t.eq(rows["Drag pan"]["proof"], "_drag_pan(", "proved by the handler's _drag_pan call")
	t.eq(KB.cap(KEY_UP) + KB.cap(KEY_LEFT) + KB.cap(KEY_DOWN) + KB.cap(KEY_RIGHT), "↑←↓→", "arrow caps")


func test_controls_hint_names_the_controls_key(t) -> void:
	t.eq(KB.CONTROLS_HINT, "F1 Controls")
	t.ok(KB.CONTROLS_HINT.begins_with(KB.cap(KB.CONTROLS) + " "), "the hint starts with the key that opens the screen")


## Task 13 (kestrel-depth): S stop, D hold and Z stance are Kestrel's order keys. S and D clash with nothing (no
## InputMap action, no other constant); Z is shared on purpose with camera_rotate_left, which only Survival reads
## (Kestrel's yaw is locked), so it means one thing per map. Shift stays a modifier.
func test_depth_order_keys_are_kestrel_only_and_clash_with_nothing(t) -> void:
	t.eq([KB.STOP, KB.HOLD, KB.STANCE], [KEY_S, KEY_D, KEY_Z], "S, D and Z")
	for code in [KB.STOP, KB.HOLD, KB.STANCE]:
		t.ok(code in KB.KESTREL_ONLY, "%s is a Kestrel-only key" % KB.cap(code))
	for code in [KB.STOP, KB.HOLD]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		for action in InputMap.get_actions():
			if str(action).begins_with("ui_"):
				continue  # Godot's built-in text and graph editing actions (Ctrl+D); the HUD takes no keyboard focus
			t.ok(not InputMap.event_is_action(ev, action), "%s is also the InputMap action %s" % [KB.cap(code), action])
		var owners: Array = []
		for name in _constants():
			if code in _constants()[name]:
				owners.append(str(name))
		t.eq(owners.size(), 1, "%s belongs to one constant (%s)" % [KB.cap(code), owners])
	var z_owners: Array = []
	for name in _constants():
		if KEY_Z in _constants()[name]:
			z_owners.append(str(name))
	t.eq(z_owners, ["STANCE"], "Z is no other key constant")
	t.eq(KB.CAMERA_ACTIONS["camera_rotate_left"], KB.STANCE, "Z also rotates, on Survival only")
	var src := _handler_sources()
	t.ok(src.contains("world_art_on and event.keycode in [Keybinds.STOP, Keybinds.HOLD]"), "S and D are read on Kestrel only")
	t.ok(src.contains("world_art_on and event.keycode == Keybinds.STANCE"), "Z cycles the stance on Kestrel only")
	t.ok(not (KEY_SHIFT in KB.shown_codes(true)), "Shift is a modifier, never a key of its own")


func test_kestrel_controls_list_the_depth_orders_and_survival_does_not(t) -> void:
	var rows := func(kestrel: bool) -> Dictionary:
		var out := {}
		for g in KB.groups(kestrel):
			for r in g["rows"]:
				out[r["label"]] = r
		return out
	var k: Dictionary = rows.call(true)
	var s: Dictionary = rows.call(false)
	t.eq(k.get("Stop", {}).get("keys", []), [KB.STOP], "Kestrel: Stop on S")
	t.eq(k.get("Hold position", {}).get("keys", []), [KB.HOLD], "Kestrel: Hold position on D")
	t.eq(k.get("Cycle stance", {}).get("keys", []), [KB.STANCE], "Kestrel: Cycle stance on Z")
	t.ok(k.has("Move, or attack a target") and not k.has("Move or attack"), "Kestrel: the right click attacks a target")
	t.ok(not k.has("Rotate"), "Kestrel: no Rotate (the yaw is locked; Z is the stance)")
	for label in ["Stop", "Hold position", "Cycle stance", "Move, or attack a target"]:
		t.ok(not s.has(label), "Survival: no %s row" % label)
	t.ok(s.has("Rotate") and s.has("Move or attack"), "Survival keeps Rotate and Move or attack")
	var names: Array = KB.groups(true).map(func(g): return g["name"])
	t.eq(names, ["Camera", "System", "Selection", "Build", "Orders", "Production"], "Kestrel folds Defences into Build")
	var cols: Array = KB.vm(false, true)["columns"]
	t.eq(cols.map(func(c): return c.map(func(g): return g["name"])), [["Camera", "Selection"], ["Build", "System"], ["Orders", "Production"]], "Kestrel's packing")
