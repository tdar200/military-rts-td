extends Control
## The mock's .panel outer shadow (0 8px 28px rgba(0,0,0,.45)). Child of the panel, drawn behind it, sized with it.
## A gaussian edge is built from stacked rounded rects; the panel's own fill hides everything inside its border box.
const T = preload("res://scripts/ui/tokens.gd")

var offset_y := 8.0
var blur := 28.0
var strength := 0.45
var radius := 3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Upper tail of the standard normal (logistic approximation).
static func _tail(z: float) -> float:
	return 1.0 / (1.0 + exp(1.702 * z))


func _draw() -> void:
	var sigma := blur * 0.5
	var base := Rect2(Vector2(0.0, offset_y), size)
	var box := StyleBoxFlat.new()
	var prior := 0.0
	for e in range(int(blur), -int(blur * 0.5) - 1, -1):
		var target := strength * _tail(float(e) / sigma)
		var a := 1.0 - (1.0 - target) / (1.0 - prior)
		prior = target
		var r := base.grow(float(e))
		if r.size.x <= 0.0 or r.size.y <= 0.0 or a <= 0.002:
			continue
		box.bg_color = Color(0, 0, 0, a)
		box.set_corner_radius_all(maxi(0, radius + e))
		draw_style_box(box, r)
