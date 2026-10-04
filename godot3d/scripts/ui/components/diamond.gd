extends Control
## Hostile mark: a diamond (colour plus shape, never colour alone). `half` is the half-diagonal in px.
const T = preload("res://scripts/ui/tokens.gd")

var half := 8.5
var tone: Color = T.BAD
var filled := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(h: float, color: Color = T.BAD, fill := true) -> Control:
	half = h
	tone = color
	filled = fill
	custom_minimum_size = Vector2(2.0 * h, 2.0 * h)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var c := Vector2(half, half)
	var outer := PackedVector2Array([c + Vector2(0, -half), c + Vector2(half, 0), c + Vector2(0, half), c + Vector2(-half, 0)])
	if filled:
		draw_colored_polygon(outer, Color(tone.r, tone.g, tone.b, 0.25))
	var ring := outer.duplicate()
	ring.append(outer[0])
	draw_polyline(ring, tone, 2.0, true)
