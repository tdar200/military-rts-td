extends RefCounted
## Every key the Godot client binds, in one place. earthfront_3d.gd and game_ui.gd compare against these constants and
## the controls screen (sections/controls_reference.gd) lists them, so what the screen shows is what the handler reads.
## tests/test_keybinds.gd fails when a key shown here is not read by the handler, when a handler compares against a
## literal KEY_ instead of a constant here, and when a constant here is missing from the screen.
## The six camera keys are InputMap actions in project.godot, not handler comparisons: CAMERA_ACTIONS names them.

const PAUSE := KEY_ESCAPE  # opens the pause menu when nothing is armed
const CANCEL := KEY_ESCAPE  # cancels an armed order or placement first
const CONTROLS := KEY_F1
## The HUD's top-bar reminder (hud.gd draws the key cap from the first word, the label from the rest; a click opens Controls).
const CONTROLS_HINT := "F1 Controls"
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
## Kestrel only: frames the latest alert ping, a quick second press the one before (alert_pings.gd). Space was bound to
## nothing before (no project action, no constant here; the HUD's buttons take no keyboard focus, so Godot's ui_accept
## never fires on them in play).
const JUMP_ALERT := KEY_SPACE
## Kestrel only (the depth orders, Task 13): S stops the selection (clears its orders and queue, keeps its stance), D
## holds it (stops and takes the hold stance), Z cycles its stance aggressive, defensive, hold. S and D were free since
## Task 2 moved the pan to the arrows; Z still rotates the Survival camera (Kestrel's yaw is locked north-up).
const STOP := KEY_S
const HOLD := KEY_D
const STANCE := KEY_Z
## Keys that do something only on Kestrel (world art on): the controls screen lists them there and nowhere else.
const KESTREL_ONLY := [JUMP_ALERT, STOP, HOLD, STANCE]
## Number keys 1..9 recall a control group; Ctrl with one assigns it.
const GROUPS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
## Train hotkeys: key -> bridge unit kind.
const TRAIN := {KEY_T: "Infantry", KEY_K: "Tank", KEY_V: "AntiArmor", KEY_H: "Helicopter", KEY_X: "Capital"}
## Build hotkeys: key -> bridge building kind.
const BUILD := {
	KEY_P: "PowerPlant", KEY_R: "Refinery", KEY_B: "Barracks", KEY_N: "VehicleFactory", KEY_I: "Airfield", KEY_O: "SupplyDepot",
	KEY_L: "ResearchLab", KEY_COMMA: "Battery", KEY_G: "GunTurret", KEY_J: "AaTurret", KEY_C: "Wall",
}
## Build kinds the Controls screen lists under Defences instead of Build: eleven build rows do not fit one panel under
## Selection above the footer (the columns are packed in vm(); test_screen_controls_reference checks the fit on both maps).
## On Kestrel the order keys add rows to Orders, so Defences rejoin Build there and Build sits over System (see vm()).
const DEFENCES := ["GunTurret", "AaTurret", "Wall"]
## InputMap action -> the physical key project.godot binds it to (checked against the real InputMap by the test). Pan is on
## the arrow keys, so W/A/S/D are free (A only arms attack-move).
const CAMERA_ACTIONS := {
	"camera_up": KEY_UP, "camera_left": KEY_LEFT, "camera_down": KEY_DOWN, "camera_right": KEY_RIGHT,
	"camera_rotate_left": KEY_Z, "camera_rotate_right": KEY_E,
}

## Row separators on the screen; every other string in a row's keys is a key cap.
const THEN := "then"
const PLUS := "+"
const CAPS := {
	KEY_ESCAPE: "Esc", KEY_DELETE: "Del", KEY_PERIOD: ".", KEY_COMMA: ",", KEY_HOME: "Home", KEY_SPACE: "Space",
	KEY_UP: "\u2191", KEY_LEFT: "\u2190", KEY_DOWN: "\u2193", KEY_RIGHT: "\u2192",
}


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
## keycodes (GROUPS, shown "1-9"), THEN / PLUS separators and literal caps for the mouse and modifiers. `proof` is a
## source needle for rows with no keycode (the mouse): the test looks for it in the handler sources, so a mouse row
## cannot describe something the handler does not do. A row with a keycode is proven by its constant instead.
## `kestrel` (world art on) adds the minimap and alert jumps and the depth orders (stop, hold, stance, attack a target),
## which exist only there, drops Rotate (the yaw is locked) and folds Defences back into Build.
static func groups(kestrel := false) -> Array:
	var build_rows: Array = []
	var defence_rows: Array = []
	for code in BUILD:
		var defence: bool = BUILD[code] in DEFENCES and not kestrel
		(defence_rows if defence else build_rows).append(_row(_kind(BUILD[code]), [code]))
	var train_rows: Array = []
	for code in TRAIN:
		train_rows.append(_row("Train " + _lower_first(_kind(TRAIN[code])), [code]))
	train_rows.append(_row("Queue from the deck", ["Click card"], "_deck_card("))
	var camera_rows: Array = [
		_row("Pan", [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT], "camera_up"),
		_row("Edge pan", [], "viewport_size.x - 10.0", "Cursor at screen edge"),
		_row("Rotate", [KEY_Z, KEY_E], "camera_rotate_left"),
		_row("Zoom", ["Wheel"], "MOUSE_BUTTON_WHEEL_UP"),
		_row("Drag pan", ["Middle drag"], "_drag_pan("),
		_row("Focus, hold to follow", [FOCUS]),
		_row("Jump to base", [HOME]),
	]
	var order_rows: Array = [
		_row("Move or attack", ["Right click"], "MOUSE_BUTTON_RIGHT"),
		_row("Attack-move", [ATTACK_MOVE, THEN, "Right click"]),
		_row("Place structure", ["Left click"], "_write_bridge_build(build_mode"),
		_row("Tactical ability", [ABILITY]),
		_row("Repair", [REPAIR]),
		_row("Sell", [SELL]),
		_row("Cancel order or placement", [CANCEL]),
	]
	if kestrel:
		camera_rows.remove_at(2)  # no Rotate: Kestrel's yaw is locked north-up, and Z cycles the stance there
		camera_rows.append(_row("Jump to alert", [JUMP_ALERT]))  # pressed again soon after: the alert before
		camera_rows.append(_row("Jump on minimap", ["Click map"], "g.minimap_jump("))  # a drag follows the pointer
		# A right click on a live enemy focuses the selection on it; anywhere else it moves, as before.
		order_rows[0] = _row("Move, or attack a target", ["Right click"], "_order_target(foe)")
		order_rows.insert(2, _row("Stop", [STOP]))
		order_rows.insert(3, _row("Hold position", [HOLD]))
		order_rows.insert(4, _row("Cycle stance", [STANCE]))
	return [
		{"name": "Camera", "rows": camera_rows},
		{"name": "System", "rows": [
			_row("Pause menu", [PAUSE]),
			_row("This screen", [CONTROLS]),
			_row("Science and upgrades" if kestrel else "Science panel", [SCIENCE]),  # Kestrel's Upgrades live there
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
			_row("Recall group, twice to centre", [GROUPS]),
		]},
		{"name": "Build", "rows": build_rows},
	] + ([] if kestrel else [{"name": "Defences", "rows": defence_rows}]) + [
		{"name": "Orders", "rows": order_rows},
		{"name": "Production", "rows": train_rows},
	]


## Every keycode a row shows, ranges expanded.
static func shown_codes(kestrel := false) -> Array:
	var out: Array = []
	for g in groups(kestrel):
		for row in g["rows"]:
			for k in row["keys"]:
				if k is int:
					out.append(k)
				elif k is Array:
					for c in k:
						out.append(int(c))
	return out


## The view model of the controls screen: three columns of groups, every key already turned into its cap text.
static func vm(from_pause := true, kestrel := false) -> Dictionary:
	var by_name := {}
	for g in groups(kestrel):
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
			[by_name["Camera"], by_name["Selection"]],
			[by_name["Build"], by_name["System"]],
			[by_name["Orders"], by_name["Production"]],
		] if kestrel else [
			[by_name["Camera"], by_name["Production"]],
			[by_name["Selection"], by_name["Build"]],
			[by_name["Orders"], by_name["System"], by_name["Defences"]],
		],
		"tip": "%s cancels an armed order or placement first. With nothing armed it opens the pause menu." % cap(CANCEL),
		"back_key": cap(PAUSE),
	}
