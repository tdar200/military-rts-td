extends Control
## The mock's .tag: 22px high, mono 12px caps with 0.08em spacing, 1px border and text in the same colour.
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const HEIGHT := 22
const PAD := 8

var tone: Color = T.CYAN
var fill := Color(0, 0, 0, 0)
var label: Control
var dashed := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = TextBox.new()
	add_child(label)


## Options: pad (default 8), sp letter-spacing em (default 0.08), min_w minimum width (text is centred), dashed border.
func setup(s: String, color: Color, bg := Color(0, 0, 0, 0), o := {}) -> Control:
	tone = color
	fill = bg
	dashed = o.get("dashed", false)
	var pad: float = o.get("pad", PAD)
	label.configure(s, {"f": "mono", "px": 12, "sp": o.get("sp", 0.08), "up": true, "col": color})
	label.size = label.get_minimum_size()
	custom_minimum_size = Vector2(maxf(float(o.get("min_w", 0.0)), label.size.x + 2 * (pad + 1)), HEIGHT)
	label.position = Vector2((custom_minimum_size.x - label.size.x) * 0.5, (HEIGHT - label.pitch()) * 0.5)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if fill.a > 0.0:
		draw_rect(rect, fill)
	if dashed:
		var a := Vector2(0.5, 0.5)
		var c := size - Vector2(0.5, 0.5)
		var b := Vector2(c.x, a.y)
		var d := Vector2(a.x, c.y)
		for edge in [[a, b], [b, c], [c, d], [d, a]]:
			draw_dashed_line(edge[0], edge[1], tone, 1.0, 3.0)
		return
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = tone
	box.set_corner_radius_all(2)
	draw_style_box(box, rect)
