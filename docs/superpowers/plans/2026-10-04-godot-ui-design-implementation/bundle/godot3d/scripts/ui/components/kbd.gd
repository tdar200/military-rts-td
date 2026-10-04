extends Control
## The Build screen's keyboard hint (.kbd): 24px high, 26px minimum width, mono 12px, 2px bottom border like a physical key.
## Not the same as KeyCap (the HUD's 22px recessed key): the two boards style keys differently.
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const HEIGHT := 24.0
const MIN_WIDTH := 26.0
const PAD := 7.0

var _label: TextBox


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = TextBox.new()
	add_child(_label)


static func measure(s: String) -> float:
	return maxf(MIN_WIDTH, s.length() * T.MONO_ADVANCE * 12.0 + 2.0 * PAD + 2.0)


func setup(s: String, color: Color = T.TEXT) -> Control:
	_label.configure(s, {"f": "mono", "px": 12, "col": color})
	_label.size = _label.get_minimum_size()
	var w := measure(s)
	custom_minimum_size = Vector2(w, HEIGHT)
	size = custom_minimum_size
	# Content box is 21px tall (1px top border, 2px bottom border); the label is centred in it.
	_label.position = Vector2(roundf((w - _label.size.x) * 0.5), 1.0 + (21.0 - _label.size.y) * 0.5)
	queue_redraw()
	return self


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = T.RAISED
	box.border_color = T.LINE
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 2
	box.set_corner_radius_all(3)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
