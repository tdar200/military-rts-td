extends RefCounted
## Tile under the cursor (board 1, bottom centre, left column). Driven by vm["inspect"]: the tile_inspect fields plus the
## adapter's context (x, y, glyph, zone, deposit). Every row comes from the ground table; bonus_text and the deposit pill
## appear only when the snapshot reports them. Builds nothing without the slice. The frame is bottom_panel.gd's.
const T = preload("res://scripts/ui/tokens.gd")
const LiveScreens = preload("res://scripts/ui/live_screens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Pill = preload("res://scripts/ui/sections/pill.gd")
const Territory = preload("res://scripts/ui/sections/territory_card.gd")
const Frame = preload("res://scripts/ui/sections/bottom_panel.gd")

const COL_W := 330.0
const THUMB := 84.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("inspect", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var x := Frame.COL1_X
	var y := Frame.COL_TOP
	var cap := K.text(parent, "Tile under cursor", {"x": x, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	y += cap.size.y + 8.0
	var text_x := x
	if d.has("glyph"):
		var swatch := ColorRect.new()
		swatch.color = Territory.color_for(str(d["glyph"]))
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		K.place(swatch, x, y, THUMB, THUMB)
		parent.add_child(swatch)
		var rim := Panel.new()
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = Color("284e60")
		box.set_corner_radius_all(2)
		rim.add_theme_stylebox_override("panel", box)
		K.place(rim, x, y, THUMB, THUMB)
		parent.add_child(rim)
		text_x = x + THUMB + 12.0
	var title := str(d.get("name", ""))
	var deposit = d.get("deposit", null)
	if deposit is Dictionary and str(deposit.get("kind", "")) != "":
		title += ", " + str(deposit["kind"])
	var title_box := K.text(parent, title, {"x": text_x, "y": y, "w": x + COL_W - text_x, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "lh": 26, "col": T.TEXT_HI, "up": true, "wrap": true})
	var block := title_box.size.y
	var sub_parts: Array = []
	if d.has("x") and d.has("y"):
		sub_parts.append("Tile %d,%d" % [int(d["x"]), int(d["y"])])
	if bool(d.get("zone", false)):
		sub_parts.append("Player territory")
	if not sub_parts.is_empty():
		var sub := K.text(parent, " / ".join(sub_parts), {"x": text_x, "y": y + block, "w": x + COL_W - text_x, "px": 13, "col": T.DIM, "wrap": true})
		block += sub.size.y
	var pills: Array = []
	var bonus := str(d.get("bonus_text", ""))
	if bonus != "":
		pills.append([bonus, T.WARN if bonus.contains("kW") else T.CYAN_HI])
	if deposit is Dictionary and int(deposit.get("remaining", 0)) > 0:
		pills.append(["%s left" % LiveScreens.thousands(int(deposit["remaining"])), T.GOOD])
	if not pills.is_empty():
		var px := text_x
		var py := y + block + 8.0
		for p in pills:
			var pill := Pill.make(parent, px, py, str(p[0]), p[1])
			if px + pill.size.x > x + COL_W and px > text_x:
				px = text_x
				py += Pill.HEIGHT + 6.0
				pill.position = Vector2(px, py)
			px += pill.size.x + 6.0
		block = py + Pill.HEIGHT - y
	y += maxf(THUMB, block) + 10.0
	var rows: Array = _rows(d)
	for i in rows.size():
		y += _row(parent, x, y, rows[i], i == rows.size() - 1)


static func _rows(d: Dictionary) -> Array:
	var rows: Array = []
	var foot := int(d.get("infantry_pct", 0))
	var wheels := int(d.get("vehicle_pct", 0))
	if foot == 0 and wheels == 0:
		rows.append(["Movement", "Impassable", T.WARN])
	else:
		rows.append(["Movement", "Foot %d%%, vehicles %d%%" % [foot, wheels], T.TEXT])
	var cover := int(d.get("cover_pct", 0))
	rows.append(["Cover", "%d%% less damage taken" % cover if cover > 0 else "None, open ground", T.GOOD if cover > 0 else T.WARN])
	if int(d.get("range_pct", 0)) > 0:
		rows.append(["Range", "+%d%% weapon range" % int(d["range_pct"]), T.GOOD])
	rows.append(["Build here", "Open to building" if bool(d.get("buildable", false)) else "Cannot build here", T.GOOD if bool(d.get("buildable", false)) else T.WARN])
	return rows


## One label / value row, 5px padding with a hairline under it except on the last row. Returns its height.
static func _row(parent: Control, x: float, y: float, row: Array, last: bool) -> float:
	var label := K.text(parent, str(row[0]), {"x": x, "y": y + 5.0, "px": 14, "col": T.DIM})
	var value := K.text(parent, str(row[1]), {"x": 0, "y": y + 5.0, "f": "mono", "px": 14, "col": row[2]})
	value.position.x = roundf(x + COL_W - value.size.x)
	var h := maxf(label.size.y, value.size.y) + 10.0
	if not last:
		K.rule(parent, x, y + h, COL_W, 1, Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.7))
		h += 1.0
	return h
