extends Control
## The mock's .bar: 6px high, 1px LINE_DIM border on a dark track, flat fill. `ratio` is 0..1 of the inner width.
const T = preload("res://scripts/ui/tokens.gd")

var ratio := 0.0
var fill_color: Color = T.CYAN
var hatched := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(r: float, color: Color = T.CYAN) -> Control:
	ratio = clampf(r, 0.0, 1.0)
	fill_color = color
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, T.BAR_BG)
	var inner := rect.grow(-1)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), fill_color)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = T.LINE_DIM
	draw_style_box(box, rect)
