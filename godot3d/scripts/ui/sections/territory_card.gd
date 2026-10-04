extends RefCounted
## Territory card (board 1, left): tile count, a ground composition bar and its legend, then the yield pills.
## Driven by vm["territory"] ({tiles, composition: [{glyph, name, pct}]}); builds nothing without it.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const TopYields = preload("res://scripts/ui/sections/top_yields.gd")

const X := 12.0
const Y := 274.0
const W := 332.0
const PAD_X := 14.0
const PAD_Y := 12.0
## Board legend colours for the five grounds it names; the other grounds extend the same palette.
const COLORS := {
	"g": Color("6a9a3a"), "m": Color("97a64a"), "t": Color("2f8a52"), "r": Color("2e86ac"), "s": Color("c9b27a"),
	"f": Color("b69a55"), "h": Color("8a8478"), "w": Color("5aa6c4"), "o": Color("1f5f8a"), "c": Color("6b5f52"),
}


static func color_for(glyph: String) -> Color:
	return COLORS.get(glyph, T.FAINT)


## The composition bar: a 10px box with a 1px border, segments inside it split by percentage.
class Bar extends Control:
	var segments: Array = []  # [[pct, Color]]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var inner := Rect2(1, 1, size.x - 2.0, size.y - 2.0)
		var done := 0.0
		var x := inner.position.x
		for seg in segments:
			done += float(seg[0])
			var right := inner.position.x + roundf(inner.size.x * done / 100.0)
			if right > x:
				draw_rect(Rect2(x, inner.position.y, right - x, inner.size.y), seg[1])
			x = right
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = T.LINE_DIM
		box.set_corner_radius_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))


static func build(parent: Control, vm: Dictionary) -> void:
	var data = vm.get("territory", null)
	if not (data is Dictionary) or data.is_empty():
		return
	var rows: Array = data.get("composition", [])
	var panel := K.panel(parent, X, Y, W, 10.0)
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var y := Y + 1.0 + PAD_Y
	var cap := K.text(parent, "Territory", {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	var tiles := K.text(parent, "%d tiles" % int(data.get("tiles", 0)), {"x": 0, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	tiles.position.x = roundf(cx + cw - tiles.size.x)
	y += cap.size.y + 8.0
	var bar := Bar.new()
	K.place(bar, cx, y, cw, 10)
	parent.add_child(bar)
	for row in rows:
		bar.segments.append([float(row.get("pct", 0)), color_for(str(row.get("glyph", "")))])
	y += 10.0 + 8.0
	var col_w := (cw - 12.0) * 0.5
	var legend_h := 0.0
	var line_h := 0.0
	for i in rows.size():
		var cell := K.text(parent, "%s %d%%" % [str(rows[i].get("name", "")), int(rows[i].get("pct", 0))], {"x": cx + (i % 2) * (col_w + 12.0), "y": y + (i / 2) * 0.0, "px": 13, "col": T.DIM})
		line_h = cell.size.y
		cell.position.y = roundf(y + (i / 2) * (line_h + 3.0))
	var n_rows := (rows.size() + 1) / 2
	legend_h = n_rows * line_h + maxf(0.0, n_rows - 1.0) * 3.0
	y += legend_h
	var pills_h := TopYields.row_height(vm)
	if pills_h > 0.0:
		y += 10.0
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		K.place(holder, cx, y)
		parent.add_child(holder)
		TopYields.build(holder, vm)
		y += pills_h
	panel.size.y = roundf(y + PAD_Y + 1.0 - Y)
	panel.queue_redraw()
