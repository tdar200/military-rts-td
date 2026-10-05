extends RefCounted
## Every key the Godot client binds, in one place. earthfront_3d.gd and game_ui.gd compare against these constants and
## the controls screen (sections/controls_reference.gd) lists them, so what the screen shows is what the handler reads.
## tests/test_keybinds.gd fails when a key shown here is not read by the handler, when a handler compares against a
## literal KEY_ instead of a constant here, and when a constant here is missing from the screen.
## The six camera keys are InputMap actions in project.godot, not handler comparisons: CAMERA_ACTIONS names them.

const PAUSE := KEY_ESCAPE  # opens the pause menu when nothing is armed
const CANCEL := KEY_ESCAPE  # cancels an armed order or placement first
const CONTROLS := KEY_F1
const SELECT_ARMY := KEY_F2
const SELECT_IDLE := KEY_PERIOD
const ATTACK_MOVE := KEY_A
const ABILITY := KEY_Q
const REPAIR := KEY_U
const SELL := KEY_DELETE
const SCIENCE := KEY_Y
## Opens and closes the strategic map (screen over play, the simulation keeps running). M is free: no train, build or camera key uses it.
const REGION_MAP := KEY_M
const FOCUS := KEY_F
const HOME := KEY_HOME
## Number keys 1..4 recall a control group; Ctrl with one assigns it.
const GROUPS := [KEY_1, KEY_2, KEY_3, KEY_4]
## Train hotkeys: key -> bridge unit kind.
const TRAIN := {KEY_T: "Infantry", KEY_K: "Tank", KEY_V: "AntiArmor", KEY_H: "Helicopter", KEY_X: "Capital"}
## Build hotkeys: key -> bridge building kind.
const BUILD := {KEY_P: "PowerPlant", KEY_R: "Refinery", KEY_B: "Barracks", KEY_G: "GunTurret", KEY_J: "AaTurret", KEY_C: "Wall", KEY_L: "ResearchLab"}
## InputMap action -> the physical key project.godot binds it to (checked against the real InputMap by the test).
const CAMERA_ACTIONS := {
	"camera_up": KEY_W, "camera_left": KEY_A, "camera_down": KEY_S, "camera_right": KEY_D,
	"camera_rotate_left": KEY_Z, "camera_rotate_right": KEY_E,
}

## Row separators on the screen; every other string in a row's keys is a key cap.
const THEN := "then"
const PLUS := "+"
const CAPS := {KEY_ESCAPE: "Esc", KEY_DELETE: "Del", KEY_PERIOD: ".", KEY_HOME: "Home"}


## The text drawn on a key cap.
static func cap(code: int) -> String:
	return str(CAPS.get(code, OS.get_keycode_string(code)))


## The name shown for a bridge kind ("Reactor" for PowerPlant).
static func _kind(kind: String) -> String:
	return str(load("res://scripts/ui/live_adapter.gd").KIND_NAMES.get(kind, kind))


static func _lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1)


static func _row(label: String, keys: Array, proof := "", note := "") -> Dictionary:
	return {"label": label, "keys": keys, "proof": proof, "note": note}


## The rows, grouped as the Controls board groups them. `keys` mixes keycodes (int, shown with cap()), a run of
## keycodes (GROUPS, shown "1-4"), THEN / PLUS separators and literal caps for the mouse and modifiers. `proof` is a
## source needle for rows with no keycode (the mouse): the test looks for it in the handler sources, so a mouse row
## cannot describe something the handler does not do. A row with a keycode is proven by its constant instead.
static func groups() -> Array:
	var build_rows: Array = []
	for code in BUILD:
		build_rows.append(_row(_kind(BUILD[code]), [code]))
	build_rows.append(_row("Place structure", ["Left click"], "_write_bridge_build(build_mode"))
	var train_rows: Array = []
	for code in TRAIN:
		train_rows.append(_row("Train " + _lower_first(_kind(TRAIN[code])), [code]))
	train_rows.append(_row("Queue from the deck", ["Click card"], "_deck_card("))
	return [
		{"name": "Camera", "rows": [
			_row("Pan", [KEY_W, KEY_A, KEY_S, KEY_D], "camera_up"),
			_row("Edge pan", [], "viewport_size.x - 10.0", "Cursor at screen edge"),
			_row("Rotate", [KEY_Z, KEY_E], "camera_rotate_left"),
			_row("Zoom", ["Wheel"], "MOUSE_BUTTON_WHEEL_UP"),
			_row("Focus selection", [FOCUS]),
			_row("Jump to base", [HOME]),
		]},
		{"name": "System", "rows": [
			_row("Pause menu", [PAUSE]),
			_row("This screen", [CONTROLS]),
			_row("Science panel", [SCIENCE]),
			_row("Strategic map", [REGION_MAP]),
		]},
		{"name": "Selection", "rows": [
			_row("Select", ["Left click"], "MOUSE_BUTTON_LEFT"),
			_row("Box select", ["Left drag"], "_select_in_rect("),
			_row("Add to selection", ["Shift", PLUS, "Click"], "event.shift_pressed"),
			_row("Select all of a type", ["Double click"], "event.double_click"),
			_row("Select all army", [SELECT_ARMY]),
			_row("Select idle crew", [SELECT_IDLE]),
			_row("Save control group", ["Ctrl", PLUS, GROUPS], "event.ctrl_pressed"),
			_row("Recall control group", [GROUPS]),
		]},
		{"name": "Build", "rows": build_rows},
		{"name": "Orders", "rows": [
			_row("Move or attack", ["Right click"], "MOUSE_BUTTON_RIGHT"),
			_row("Attack-move", [ATTACK_MOVE, THEN, "Right click"]),
			_row("Tactical ability", [ABILITY]),
			_row("Repair", [REPAIR]),
			_row("Sell", [SELL]),
			_row("Cancel order or placement", [CANCEL]),
		]},
		{"name": "Production", "rows": train_rows},
	]


## Every keycode a row shows, ranges expanded.
static func shown_codes() -> Array:
	var out: Array = []
	for g in groups():
		for row in g["rows"]:
			for k in row["keys"]:
				if k is int:
					out.append(k)
				elif k is Array:
					for c in k:
						out.append(int(c))
	return out


## The view model of the controls screen: three columns of groups, every key already turned into its cap text.
static func vm(from_pause := true) -> Dictionary:
	var by_name := {}
	for g in groups():
		var rows: Array = []
		for r in g["rows"]:
			var keys: Array = []
			for k in r["keys"]:
				if k is int:
					keys.append({"t": cap(k)})
				elif k is Array:
					keys.append({"t": "%s-%s" % [cap(int(k[0])), cap(int(k[k.size() - 1]))]})
				elif k == THEN or k == PLUS:
					keys.append({"t": str(k), "sep": true})
				else:
					keys.append({"t": str(k)})
			rows.append({"label": r["label"], "keys": keys, "note": r["note"]})
		by_name[g["name"]] = {"name": g["name"], "rows": rows}
	return {
		"cap": "Pause / Controls" if from_pause else "Controls",
		"title": "Controls",
		"subtitle": "Mouse and keyboard. Build, train, repair and sell are also on the deck.",
		"columns": [
			[by_name["Camera"], by_name["System"]],
			[by_name["Selection"], by_name["Build"]],
			[by_name["Orders"], by_name["Production"]],
		],
		"tip": "%s cancels an armed order or placement first. With nothing armed it opens the pause menu." % cap(CANCEL),
		"back_key": cap(PAUSE),
	}
