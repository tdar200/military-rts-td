extends RefCounted
## The selected-structure frame (boards 4 and 7, bottom centre): the same 940x258 panel as board 1, three columns. Left:
## sprite, name, state tag, health bar and the building's rows. Middle: the production queue for a producer, otherwise the
## terrain under the building. Right: the buttons the bridge can carry out. Driven by vm["structure"]
## (VmGameplay.structure); builds nothing without it. Every button is a real Button and emits (action, arg) through the
## supplied callback. The board's per-unit queue names, "Queue cost" line and "Cancel last" are not built: the snapshot only
## knows the running job and a queued count, and the sim has no cancel command (docs/ascension/ui-deviations.md).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")
const Frame = preload("res://scripts/ui/sections/bottom_panel.gd")
const Territory = preload("res://scripts/ui/sections/territory_card.gd")

const COL_GAP := 16.0
const BTN_COL_W := 210.0
const QUEUE_COL_W := 230.0
const TERRAIN_COL_W := 260.0
const BOX := 86.0
const SPRITE := 76.0
const BTN_H := 34.0
## Chrome's line box for 12px mono caps (1.3 x 12), so the rows below land on the mock's pixel.
const CAP_LH := 15.6


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var d = vm.get("structure", null)
	if not (d is Dictionary) or d.is_empty():
		return
	K.panel(parent, Frame.X, Frame.Y, Frame.W, Frame.H)
	var col1_w := TERRAIN_COL_W if d.has("terrain") else QUEUE_COL_W
	_left(parent, d, Frame.COL1_X, col1_w)
	var mid_x := Frame.COL1_X + col1_w + COL_GAP
	var btn_x := Frame.X + Frame.W - 1.0 - 16.0 - BTN_COL_W
	var mid_w := btn_x - COL_GAP - mid_x
	K.rule(parent, mid_x, Frame.COL_TOP, 1, Frame.COL_H, T.LINE_DIM)
	K.rule(parent, btn_x - COL_GAP - 1.0, Frame.COL_TOP, 1, Frame.COL_H, T.LINE_DIM)
	if d.has("queue"):
		_queue(parent, d["queue"], mid_x + 1.0 + 16.0, mid_w - 2.0 - 32.0)
	elif d.has("terrain"):
		_terrain(parent, d["terrain"], mid_x + 1.0 + 16.0, mid_w - 2.0 - 32.0)
	_buttons(parent, d.get("buttons", []), btn_x, emit)


static func _left(parent: Control, d: Dictionary, x: float, w: float) -> void:
	var y := Frame.COL_TOP
	# The mock's flex row shrinks the sprite box and the name block in proportion when the name does not fit on one line.
	var probe := K.text(parent, str(d.get("name", "")), {"f": "disp", "wt": 600, "px": 26, "sp": 0.04, "lh": 26, "up": true})
	var name_w: float = probe.size.x
	probe.free()
	var over := maxf(0.0, BOX + 12.0 + name_w - w)
	# The sprite inside has a fixed width, so the box cannot go below the sprite plus its border.
	var box_w := maxf(SPRITE + 2.0, roundf(BOX - over * BOX / (BOX + name_w)))
	var box := K.panel(parent, x, y, box_w, BOX, "glass")
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite_w := minf(SPRITE, box_w - 2.0)
	if str(d.get("sprite", "")) != "":
		K.sprite(parent, str(d["sprite"]), x + (box_w - sprite_w) * 0.5, y + (BOX - sprite_w) * 0.5, sprite_w, sprite_w)
	var tx := x + box_w + 12.0
	var name := K.text(parent, str(d.get("name", "")), {"x": tx, "y": y, "w": x + w - tx, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "lh": 26, "col": T.TEXT_HI, "up": true, "wrap": true})
	var tag = d.get("tag", null)
	var block: float = name.size.y
	var tag_node: Control = null
	if tag is Dictionary:
		tag_node = K.tag(parent, str(tag.get("text", "")), tx, 0, T.tone(str(tag.get("tone", "cyan"))))
		block += 4.0 + tag_node.size.y
	var top := roundf(y + (BOX - block) * 0.5)
	name.position.y = top
	if tag_node != null:
		tag_node.position.y = top + name.size.y + 4.0
	y += BOX + 12.0
	var hp = d.get("hp", null)
	if hp is Dictionary:
		var label := K.text(parent, "Health", {"x": x, "y": y, "px": 13, "col": T.DIM})
		var tone := T.tone(str(hp.get("tone", "good")))
		var value := K.text(parent, "%d / %d" % [int(hp.get("now", 0)), int(hp.get("max", 0))], {"x": 0, "y": y, "f": "mono", "px": 13, "col": tone if str(hp.get("tone", "")) != "good" else T.TEXT})
		value.position.x = roundf(x + w - value.size.x)
		y += label.size.y
		K.bar(parent, x, y, w, float(hp.get("ratio", 0.0)), tone, 5.0)
		y += 5.0
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		Rows.build(parent, x, y, w, rows)


static func _queue(parent: Control, q: Dictionary, x: float, w: float) -> void:
	var cap := K.text(parent, "Production queue", {"x": x, "y": Frame.COL_TOP, "f": "mono", "px": 12, "sp": 0.12, "lh": CAP_LH, "col": T.CYAN, "up": true})
	var y := Frame.COL_TOP + cap.size.y + 8.0
	var cells: Array = q.get("cells", [])
	var queued := int(q.get("queued", 0))
	if cells.is_empty() and queued == 0:
		K.text(parent, "Queue empty", {"x": x, "y": y, "w": w, "px": 13, "col": T.DIM})
		return
	for i in cells.size():
		var c: Dictionary = cells[i]
		var glass := K.panel(parent, x, y, w, 48.0, "glass", {"border": T.CYAN} if i == 0 else {})
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tx := x + 11.0
		if str(c.get("sprite", "")) != "":
			K.sprite(parent, str(c["sprite"]), x + 11.0, y + 7.0, 34.0, 34.0)
		tx = x + 11.0 + 34.0 + 10.0
		var name := K.text(parent, str(c.get("name", "")), {"x": tx, "y": 0, "px": 14, "col": T.TEXT})
		var note := K.text(parent, str(c.get("note", "")), {"x": 0, "y": 0, "f": "mono", "px": 14, "col": T.DIM})
		# The text block (name line, 3px, bar) is centred against the 34px sprite.
		var top := y + 7.0 + (34.0 - (name.size.y + 3.0 + 6.0)) * 0.5
		name.position.y = roundf(top)
		note.position = Vector2(roundf(x + w - 11.0 - note.size.x), roundf(top))
		K.bar(parent, tx, top + name.size.y + 3.0, x + w - 11.0 - tx, float(c.get("ratio", 0.0)), T.CYAN, 6.0)
		y += 48.0 + 8.0
	if queued > 0:
		var glass := K.panel(parent, x, y, w, 48.0, "glass")
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := K.text(parent, "%d more queued" % queued, {"x": x + 11.0, "y": 0, "px": 14, "col": T.TEXT})
		label.position.y = roundf(y + (48.0 - label.size.y) * 0.5)


static func _terrain(parent: Control, t: Dictionary, x: float, w: float) -> void:
	var cap := K.text(parent, "Terrain at this tile", {"x": x, "y": Frame.COL_TOP, "f": "mono", "px": 12, "sp": 0.12, "lh": CAP_LH, "col": T.CYAN, "up": true})
	var y := Frame.COL_TOP + cap.size.y + 8.0
	var thumb := 70.0
	var swatch := ColorRect.new()
	swatch.color = Territory.color_for(str(t.get("glyph", "")))
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(swatch, x, y, thumb, thumb)
	parent.add_child(swatch)
	var rim := Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = T.LINE
	rim.add_theme_stylebox_override("panel", box)
	K.place(rim, x, y, thumb, thumb)
	parent.add_child(rim)
	var tx := x + thumb + 12.0
	var title := K.text(parent, str(t.get("title", "")), {"x": tx, "y": y, "w": x + w - tx, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "col": T.TEXT_HI, "up": true, "wrap": true})
	var sub := K.text(parent, str(t.get("sub", "")), {"x": tx, "y": y + title.size.y, "w": x + w - tx, "px": 13, "col": T.DIM, "wrap": true})
	var block: float = title.size.y + sub.size.y
	title.position.y = roundf(y + (thumb - block) * 0.5)
	sub.position.y = title.position.y + title.size.y
	var rows: Array = t.get("rows", [])
	if not rows.is_empty():
		Rows.build(parent, x, y + thumb + 6.0, w, rows)


static func _buttons(parent: Control, buttons: Array, x: float, emit: Callable) -> void:
	var y := Frame.COL_TOP
	for b in buttons:
		var node := K.button(parent, str(b.get("label", "")), x, y, {"w": BTN_COL_W, "h": BTN_H, "px": 15, "pad": 12.0, "min_h": BTN_H, "key": str(b.get("key", "")), "primary": bool(b.get("primary", false)), "danger": bool(b.get("danger", false))})
		if emit.is_valid():
			(node as Button).pressed.connect(emit.bind(str(b.get("action", "")), b.get("arg", null)))
		y += BTN_H + 6.0
