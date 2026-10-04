extends Control
## The gameplay boards' .yl pill: 22px high, mono 12px, 1px LINE_DIM border on a dark fill, a coloured 8px dot first.
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const HEIGHT := 22
const PAD := 7
const GAP := 5
const DOT := 8

var dot_color: Color = T.CYAN_HI


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Adds a pill at (x, y) in `parent` and returns it; `size` tells the caller where the next one goes.
static func make(parent: Node, x: float, y: float, text: String, dot: Color) -> Control:
	var p := new()
	p.dot_color = dot
	p.position = Vector2(roundf(x), roundf(y))
	parent.add_child(p)
	var label := TextBox.new()
	p.add_child(label)
	label.configure(text, {"f": "mono", "px": 12, "col": T.TEXT})
	label.size = label.get_minimum_size()
	label.position = Vector2(1.0 + PAD + DOT + GAP, (HEIGHT - label.pitch()) * 0.5)
	p.size = Vector2(2.0 + 2.0 * PAD + DOT + GAP + label.size.x, HEIGHT)
	return p


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, T.BAR_BG)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = T.LINE_DIM
	box.set_corner_radius_all(2)
	draw_style_box(box, rect)
	draw_circle(Vector2(1.0 + PAD + DOT * 0.5, HEIGHT * 0.5), DOT * 0.5, dot_color)
