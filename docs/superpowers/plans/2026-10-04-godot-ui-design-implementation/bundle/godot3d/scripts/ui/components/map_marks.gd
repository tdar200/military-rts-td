extends Control
## Unit dots and the camera frustum drawn over the live minimap.
const T = preload("res://scripts/ui/tokens.gd")

var _marks: Array = []
var _view: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## marks: [{x, y, k}] with x,y in 0..1 of this control; k is "f" friendly square, "e" elite square, "h" hostile diamond, "H" large hostile diamond.
## view: {x, y, w, h} in the same space, the camera frustum.
func setup(marks: Array, view: Dictionary) -> Control:
	_marks = marks
	_view = view
	queue_redraw()
	return self


func _draw() -> void:
	for mark in _marks:
		var u := float(mark.get("x", -1.0))
		var v := float(mark.get("y", -1.0))
		if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
			continue
		var at := Vector2(u * size.x, v * size.y)
		match str(mark.get("k", "f")):
			"f":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), T.CYAN)
			"e":
				draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), T.CYAN_HI)
			"h", "H":
				var r := 6.4 if str(mark.get("k")) == "h" else 7.8
				var outer := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
				draw_colored_polygon(outer, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.35))
				outer.append(outer[0])
				draw_polyline(outer, T.BAD, 2.0, true)
	if not _view.is_empty():
		var rect := Rect2(float(_view.get("x", 0.0)) * size.x, float(_view.get("y", 0.0)) * size.y, float(_view.get("w", 0.0)) * size.x, float(_view.get("h", 0.0)) * size.y)
		rect = rect.intersection(Rect2(Vector2.ZERO, size))
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			for i in range(1, 7):
				var halo := Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.4 * pow(1.0 - i / 7.0, 2.0) * 0.5)
				draw_rect(rect.grow(i), halo, false, 1.0)
			draw_rect(rect, T.CYAN_HI, false, 1.5)
