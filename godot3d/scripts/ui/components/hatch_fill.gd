extends Control
## A rectangle filled with repeating-linear-gradient(135deg, a 0 4px, b 4px 8px): diagonal stripes running up and to the right.
## Used for the "over capacity" part of the projected grid bar.
const T = preload("res://scripts/ui/tokens.gd")

var stripe_a: Color = T.BAD
var stripe_b := Color("7a1f1b")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), stripe_a)
	# Stripe k covers x + y in [8k*sqrt2 + 4*sqrt2, (8k+8)*sqrt2) measured from the top-left corner.
	var period := 8.0 * sqrt(2.0)
	var half := 4.0 * sqrt(2.0)
	var reach := size.x + size.y
	var c := half
	while c < reach:
		var pts := PackedVector2Array([Vector2(c, 0), Vector2(c + half, 0), Vector2(0, c + half), Vector2(0, c)])
		draw_colored_polygon(pts, stripe_b)
		c += period
