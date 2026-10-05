extends Control
## The Controls board's .key: mono 13px label in a 26px high chip, 1px border (2px at the bottom), radius 3, dark fill.
const T = preload("res://scripts/ui/tokens.gd")

const HEIGHT := 26
const MIN_WIDTH := 26
const PAD := 7
const PX := 13

var label := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func measure(s: String) -> float:
	return maxf(MIN_WIDTH, s.length() * T.MONO_ADVANCE * PX + 2 * (PAD + 1))


func setup(s: String) -> Control:
	label = s
	custom_minimum_size = Vector2(measure(s), HEIGHT)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, T.KEY_BG)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.border_color = T.LINE
	box.set_corner_radius_all(3)
	draw_style_box(box, rect)
	var f := T.font("mono", 400)
	var step := T.MONO_ADVANCE * PX
	var x := (size.x - label.length() * step) * 0.5
	var baseline := (size.y - (T.ascent(f, PX) + T.descent(f, PX))) * 0.5 + T.ascent(f, PX)
	for i in label.length():
		if label[i] != " ":
			draw_char(f, Vector2(x + i * step, baseline), label[i], PX, T.TEXT_HI)
