extends RefCounted
## Colony ledger (board 1, bottom centre, middle column): structure and unit counts, crew use, battery charge, then one
## production row per finished producer and the running research. Driven by vm["ledger"]; fields the snapshot lacks are
## left out, and it builds nothing without the slice. The frame and column rules are bottom_panel.gd's.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Frame = preload("res://scripts/ui/sections/bottom_panel.gd")

const X := 708.0
const W := 280.0
const CELL_W := 131.0
const CELL_GAP := 18.0
const MAX_ROWS := 4


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("ledger", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var y := Frame.COL_TOP
	var cap := K.text(parent, "Colony ledger", {"x": X, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	y += cap.size.y + 6.0
	var cells: Array = []
	if d.has("structures"):
		cells.append(["Structures", str(int(d["structures"])), T.TEXT])
	if d.has("units"):
		cells.append(["Units", str(int(d["units"])), T.TEXT])
	if d.has("crew_used") and d.has("crew_cap"):
		cells.append(["Crew", "%d / %d" % [int(d["crew_used"]), int(d["crew_cap"])], T.TEXT])
	if d.has("battery_pct"):
		cells.append(["Battery", "%d%%" % int(d["battery_pct"]), T.TEXT])
	var track := 0.0
	for i in cells.size():
		var cx := X + (i % 2) * (CELL_W + CELL_GAP)
		var cy := y + (i / 2) * (track + 4.0)
		var label := K.text(parent, str(cells[i][0]), {"x": cx, "y": cy + 5.0, "px": 14, "col": T.DIM})
		var value := K.text(parent, str(cells[i][1]), {"x": 0, "y": cy + 5.0, "f": "mono", "px": 14, "col": cells[i][2]})
		value.position.x = roundf(cx + CELL_W - value.size.x)
		track = maxf(label.size.y, value.size.y) + 10.0 + 1.0
		# Every item but the last child of the grid has a hairline under it.
		if i != cells.size() - 1:
			K.rule(parent, cx, cy + track - 1.0, CELL_W, 1, Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.7))
	if not cells.is_empty():
		var grid_rows := (cells.size() + 1) / 2
		y += grid_rows * track + (grid_rows - 1) * 4.0 - (1.0 if cells.size() % 2 == 1 else 0.0) + 10.0
	var rows: Array = d.get("production", [])
	if rows.is_empty():
		return
	var cap2 := K.text(parent, "Production", {"x": X, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	y += cap2.size.y + 6.0
	for i in mini(rows.size(), MAX_ROWS):
		y += _production_row(parent, y, rows[i]) + 6.0


static func _production_row(parent: Control, y: float, row: Dictionary) -> float:
	var idle := str(row.get("state", "")) == "idle"
	var h := 22.0 if idle else 18.0
	var name_box := K.text(parent, str(row.get("name", "")), {"x": X, "y": y + (h - 18.0) * 0.5, "w": 100, "px": 14, "col": T.TEXT})
	var note := K.text(parent, str(row.get("note", "")), {"x": 0, "y": y, "f": "mono", "px": 13, "col": T.DIM})
	note.position = Vector2(roundf(X + W - note.size.x), roundf(y + (h - note.size.y) * 0.5))
	if idle:
		K.tag(parent, "Idle", X + 110.0, y, T.WARN)
	elif row.has("ratio"):
		var bar_x := X + 110.0
		var bar_w := note.position.x - 10.0 - bar_x
		if bar_w > 8.0:
			K.bar(parent, bar_x, y + (h - 6.0) * 0.5, bar_w, float(row["ratio"]), T.VIOLET if str(row.get("name", "")) == "Lab" else T.CYAN)
	return maxf(h, name_box.size.y)
