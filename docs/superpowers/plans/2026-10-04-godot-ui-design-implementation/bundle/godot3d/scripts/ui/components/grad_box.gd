extends Control
## A flat or gradient rectangle with optional single-side borders (the mock's top bar, boss bar track and fill).
## Square corners; use HoloPanel for the rounded gradient surfaces.
const T = preload("res://scripts/ui/tokens.gd")

var from_color: Color = T.PANEL_TOP
var to_color: Color = T.PANEL_BOT
var horizontal := false
var border_color := Color(0, 0, 0, 0)
## Any of "t", "r", "b", "l"; each draws a 1px edge inside the box.
var sides: PackedStringArray = PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## o: from, to (colours; `fill` sets both), horizontal, border (colour), sides ("trbl" subset), stop (true = swallow clicks).
func style(o: Dictionary) -> Control:
	from_color = o.get("from", o.get("fill", from_color))
	to_color = o.get("to", o.get("fill", to_color))
	horizontal = o.get("horizontal", horizontal)
	border_color = o.get("border", border_color)
	sides = PackedStringArray(Array(str(o.get("sides", "")).split("")).filter(func(s): return s != ""))
	if o.get("stop", false):
		mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()
	return self


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([from_color, to_color, to_color, from_color]) if horizontal else PackedColorArray([from_color, from_color, to_color, to_color])
	draw_polygon(pts, cols)
	if border_color.a <= 0.0:
		return
	if "t" in sides:
		draw_rect(Rect2(0, 0, size.x, 1), border_color)
	if "b" in sides:
		draw_rect(Rect2(0, size.y - 1, size.x, 1), border_color)
	if "l" in sides:
		draw_rect(Rect2(0, 0, 1, size.y), border_color)
	if "r" in sides:
		draw_rect(Rect2(size.x - 1, 0, 1, size.y), border_color)
