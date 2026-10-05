extends RefCounted
## Pause menu (board 9): the "Paused" marker, the command menu, the mission snapshot and, after Restart or Quit is pressed,
## a confirm panel. Driven by vm_gameplay.pause() plus the host's state ({confirm, can_restart}); `emit` is Callable(name, arg)
## and receives resume, open_controls, ask_restart, ask_quit, keep_playing, restart and quit. Builds nothing for {}.
## Not built, because the game has no such feature: Settings, Save and keep playing, the Objective and Last save rows.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const SCRIM := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.72)
const MENU_X := 560.0
const MENU_Y := 190.0
const MENU_W := 480.0
const SNAP_X := 1080.0
const SNAP_W := 440.0
const CONFIRM_Y := 760.0
const CONFIRM_W := 960.0
const SCREEN_W := 1920.0
const BTN_H := 56.0
const BTN_GAP := 10.0


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty():
		return
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP  # the paused game takes no clicks
	parent.add_child(scrim)
	_marker(parent, vm)
	_menu(parent, vm, emit)
	if not (vm.get("rows", []) as Array).is_empty():
		_snapshot(parent, vm)
	var confirm := str(vm.get("confirm", ""))
	if confirm == "restart" or confirm == "quit":
		_confirm(parent, vm, confirm, emit)


static func _marker(parent: Control, vm: Dictionary) -> void:
	var stopped: bool = vm.get("stopped", true)
	var panel := K.panel(parent, 0, 34, 10.0, 10.0, "panel", {"border": T.CYAN if stopped else T.WARN})
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := K.text(parent, "Paused", {"f": "disp", "wt": 600, "px": 26, "sp": 0.2, "col": T.TEXT_HI, "up": true})
	var note := K.text(parent, "Simulation stopped" if stopped else "Simulation still running", {"f": "mono", "px": 12, "sp": 0.12, "col": T.DIM if stopped else T.WARN, "up": true})
	var inner_h := maxf(22.0, maxf(title.size.y, note.size.y))
	var w := 2.0 + 52.0 + 22.0 + 14.0 + title.size.x + 14.0 + note.size.x
	var h := 2.0 + 20.0 + inner_h
	var x := roundf((SCREEN_W - w) * 0.5)
	K.place(panel, x, 34, w, h)
	panel.queue_redraw()
	var mid := 34.0 + h * 0.5
	var cx := x + 1.0 + 26.0
	K.icon(parent, "pause", cx, mid - 11.0, T.CYAN_HI if stopped else T.WARN, 22, 2.0)
	cx += 22.0 + 14.0
	title.position = Vector2(roundf(cx), roundf(mid - title.size.y * 0.5))
	cx += title.size.x + 14.0
	note.position = Vector2(roundf(cx), roundf(mid - note.size.y * 0.5))


static func _menu(parent: Control, vm: Dictionary, emit: Callable) -> void:
	var keys: Dictionary = vm.get("keys", {})
	var panel := K.panel(parent, MENU_X, MENU_Y, MENU_W, 10.0)
	var cx := MENU_X + 1.0 + 26.0
	var cw := MENU_W - 2.0 - 52.0
	var y := MENU_Y + 1.0 + 26.0
	var cap := K.text(parent, str(vm.get("map", "")), {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	y += cap.size.y + 4.0
	var title := K.text(parent, "Command pause", {"x": cx, "y": y, "f": "disp", "wt": 600, "px": 44, "sp": 0.04, "lh": 46, "col": T.TEXT_HI, "up": true})
	y += title.size.y + 22.0
	var resume := _button(parent, "Resume", cx, y, cw, {"primary": true, "key": str(keys.get("resume", ""))})
	if emit.is_valid():
		resume.pressed.connect(emit.bind("resume", null))
	y += BTN_H + BTN_GAP
	var controls := _button(parent, "Controls", cx, y, cw, {"key": str(keys.get("controls", ""))})
	if emit.is_valid():
		controls.pressed.connect(emit.bind("open_controls", null))
	y += BTN_H
	var can_restart: bool = vm.get("can_restart", true)
	y += BTN_GAP + 4.0
	K.rule(parent, cx, y, cw, 1, T.LINE_DIM)
	y += 1.0 + 4.0 + BTN_GAP
	if can_restart:
		var restart := _button(parent, "Restart mission", cx, y, cw, {"danger": true})
		if emit.is_valid():
			restart.pressed.connect(emit.bind("ask_restart", null))
		y += BTN_H + BTN_GAP
	var quit := _button(parent, "Quit game", cx, y, cw, {"danger": true})
	if emit.is_valid():
		quit.pressed.connect(emit.bind("ask_quit", null))
	y += BTN_H + 16.0
	var note := "Restart and quit ask for a second confirmation. There is no save, so progress is lost."
	if can_restart:
		note += " Restart returns to the title with a fresh mission."
	var foot := K.text(parent, note, {"x": cx, "y": y, "w": cw, "px": 13, "col": T.DIM, "wrap": true})
	y += foot.size.y
	panel.size.y = roundf(y + 22.0 + 1.0 - MENU_Y)
	panel.queue_redraw()


static func _button(parent: Control, label: String, x: float, y: float, w: float, o: Dictionary) -> Button:
	var opts := {"w": w, "h": BTN_H, "px": 20, "sp": 0.1, "pad": 20.0, "spread": true}
	opts.merge(o)
	return K.button(parent, label, x, y, opts) as Button


static func _snapshot(parent: Control, vm: Dictionary) -> void:
	var rows: Array = vm["rows"]
	var panel := K.panel(parent, SNAP_X, MENU_Y, SNAP_W, 10.0)
	var cx := SNAP_X + 1.0 + 24.0
	var cw := SNAP_W - 2.0 - 48.0
	var y := MENU_Y + 1.0 + 22.0
	var cap := K.text(parent, "Mission snapshot", {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	y += cap.size.y + 10.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var tone := str(row.get("tone", ""))
		var label := K.text(parent, str(row.get("label", "")), {"x": cx, "y": y + 7.0, "px": 14, "col": T.DIM})
		var value_opts := {"x": 0, "y": y + 7.0, "px": 14, "col": T.tone(tone) if tone != "" else T.TEXT}
		if row.get("mono", false):
			value_opts["f"] = "mono"
		var value := K.text(parent, str(row.get("value", "")), value_opts)
		value.position.x = roundf(cx + cw - value.size.x)
		var inner := maxf(label.size.y, value.size.y)
		y += 7.0 + inner + 7.0
		if i < rows.size() - 1:
			K.rule(parent, cx, y, cw, 1, T.LINE_DIM)
			y += 1.0
	panel.size.y = roundf(y + 22.0 + 1.0 - MENU_Y)
	panel.queue_redraw()


## The second state of Restart and Quit: a danger-edged strip under the menu with the two choices.
static func _confirm(parent: Control, vm: Dictionary, which: String, emit: Callable) -> void:
	var elapsed := str(vm.get("elapsed", ""))
	var restart := which == "restart"
	var panel := K.panel(parent, MENU_X, CONFIRM_Y, CONFIRM_W, 88.0, "panel", {"border": T.DANGER_EDGE})
	panel.name = "Confirm"
	var cy := CONFIRM_Y + 44.0
	K.icon(parent, "warning", MENU_X + 1.0 + 24.0, cy - 15.0, T.BAD, 30, 1.75)
	var title := K.text(parent, "Restart this mission?" if restart else "Quit the game?", {"f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": T.BAD_HI, "up": true})
	var lost := "You will lose %s of progress. " % elapsed if elapsed != "" else "You will lose your progress. "
	var sub := K.text(parent, lost + ("This cannot be undone." if restart else "There is no save."), {"px": 14, "col": T.DIM})
	var keep := K.button(parent, "Keep playing", 0, 0, {"px": 20, "sp": 0.1, "pad": 20.0, "spread": true, "min_h": 48})
	var go_label := "Restart" if restart else "Quit game"
	var go := K.button(parent, go_label, 0, 0, {"px": 20, "sp": 0.1, "pad": 20.0, "spread": true, "min_h": 48, "danger": true})
	for b in [keep, go]:
		b.size.x = maxf(150.0, b.size.x)  # the board's min-width
		b.custom_minimum_size = b.size
	var right := MENU_X + CONFIRM_W - 1.0 - 24.0
	K.place(go, right - go.size.x, cy - 24.0)
	K.place(keep, right - go.size.x - 24.0 - keep.size.x, cy - 24.0)
	var text_x := MENU_X + 1.0 + 24.0 + 30.0 + 24.0
	var block_h := title.size.y + 2.0 + sub.size.y
	title.position = Vector2(text_x, roundf(cy - block_h * 0.5))
	sub.position = Vector2(text_x, roundf(cy - block_h * 0.5 + title.size.y + 2.0))
	if emit.is_valid():
		keep.pressed.connect(emit.bind("keep_playing", null))
		go.pressed.connect(emit.bind("restart" if restart else "quit", null))
