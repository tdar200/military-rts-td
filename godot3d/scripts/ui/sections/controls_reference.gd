extends RefCounted
## Controls reference (board 10): three columns of key groups read from keybinds.gd (Keybinds.vm), a Back button and a
## footer tip. `emit` is Callable(name, arg) and receives controls_back. Builds nothing without columns.
## Not built: Rebind keys (the game has no remapping), the "Hold Alt" footer (no such feature), and every board row whose
## key does not exist (see docs/ascension/ui-deviations.md).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const KeyChip = preload("res://scripts/ui/components/key_chip.gd")

const MARGIN := 60.0
const COLUMN_TOP := 170.0
const COLUMN_GAP := 20.0
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const ROW_RULE := Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.6)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var columns: Array = vm.get("columns", [])
	if columns.is_empty():
		return
	var back_ground := ColorRect.new()
	back_ground.name = "Ground"
	back_ground.color = Color("07101a")
	back_ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_ground.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(back_ground)
	_header(parent, vm, emit)
	var col_w := (SCREEN_W - 2.0 * MARGIN - 2.0 * COLUMN_GAP) / 3.0
	for c in columns.size():
		var y := COLUMN_TOP
		for group in columns[c]:
			y += _group(parent, MARGIN + c * (col_w + COLUMN_GAP), y, col_w, group) + COLUMN_GAP
	_footer(parent, vm)


static func _header(parent: Control, vm: Dictionary, emit: Callable) -> void:
	var cap := K.text(parent, str(vm.get("cap", "")), {"x": MARGIN, "y": 36.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var title := K.text(parent, str(vm.get("title", "Controls")), {"x": MARGIN, "y": 36.0 + cap.size.y + 2.0, "f": "disp", "wt": 600, "px": 52, "sp": 0.04, "lh": 54, "col": T.TEXT_HI, "up": true})
	var sub := K.text(parent, str(vm.get("subtitle", "")), {"x": MARGIN, "y": title.position.y + title.size.y + 4.0, "px": 15, "col": T.DIM})
	var bottom := sub.position.y + sub.size.y
	var back := K.button(parent, "Back", 0, 0, {"primary": true, "key": str(vm.get("back_key", "Esc"))})
	K.place(back, SCREEN_W - MARGIN - back.size.x, bottom - back.size.y)
	if emit.is_valid():
		back.pressed.connect(emit.bind("controls_back", null))


## One panel (.sec): a heading with a hairline to its right, then one row per binding. Returns the panel height.
static func _group(parent: Control, x: float, y: float, w: float, group: Dictionary) -> float:
	var panel := K.panel(parent, x, y, w, 10.0)
	var cx := x + 1.0 + 18.0
	var cw := w - 2.0 - 36.0
	var at := y + 1.0 + 16.0
	var head := K.text(parent, str(group.get("name", "")), {"x": cx, "y": at, "f": "disp", "wt": 600, "px": 20, "sp": 0.1, "col": T.CYAN_HI, "up": true})
	K.rule(parent, cx + head.size.x + 10.0, at + roundf(head.size.y * 0.5), cw - head.size.x - 10.0, 1, T.LINE_DIM)
	at += head.size.y + 10.0
	var rows: Array = group.get("rows", [])
	for i in rows.size():
		at += _row(parent, cx, at, cw, rows[i])
		if i < rows.size() - 1:
			K.rule(parent, cx, at, cw, 1, ROW_RULE)
			at += 1.0
	panel.size.y = roundf(at + 16.0 + 1.0 - y)
	panel.queue_redraw()
	return panel.size.y


static func _row(parent: Control, x: float, y: float, w: float, row: Dictionary) -> float:
	var label := K.text(parent, str(row.get("label", "")), {"x": x, "y": 0, "px": 15, "col": T.TEXT})
	var keys: Array = row.get("keys", [])
	var items: Array = []
	var total := 0.0
	for k in keys:
		var sep: bool = k.get("sep", false)
		var item: Control
		if sep:
			item = K.text(parent, str(k["t"]), {"f": "mono", "px": 12, "col": T.FAINT})
		else:
			item = KeyChip.new()
			parent.add_child(item)
			(item as KeyChip).setup(str(k["t"]))
		items.append(item)
		total += item.size.x
	total += 5.0 * maxi(items.size() - 1, 0)
	var note: Control = null
	if str(row.get("note", "")) != "":
		note = K.text(parent, str(row["note"]), {"px": 15, "col": T.DIM})
	var inner := maxf(label.size.y, maxf(float(KeyChip.HEIGHT) if not items.is_empty() else 0.0, note.size.y if note != null else 0.0))
	label.position.y = roundf(y + 6.0 + (inner - label.size.y) * 0.5)
	var rx := x + w - total
	for item in items:
		item.position = Vector2(roundf(rx), roundf(y + 6.0 + (inner - item.size.y) * 0.5))
		rx += item.size.x + 5.0
	if note != null:
		note.position = Vector2(roundf(x + w - note.size.x), roundf(y + 6.0 + (inner - note.size.y) * 0.5))
	return 6.0 + inner + 6.0


static func _footer(parent: Control, vm: Dictionary) -> void:
	var tip := str(vm.get("tip", ""))
	if tip == "":
		return
	var h := 52.0
	var y := SCREEN_H - 36.0 - h
	K.panel(parent, MARGIN, y, SCREEN_W - 2.0 * MARGIN, h, "glass")
	K.icon(parent, "circle_help", MARGIN + 1.0 + 20.0, y + h * 0.5 - 11.0, T.CYAN, 22, 1.75)
	var text := K.text(parent, tip, {"x": MARGIN + 1.0 + 20.0 + 22.0 + 16.0, "y": 0, "px": 14, "col": T.DIM})
	text.position.y = roundf(y + (h - text.size.y) * 0.5)
