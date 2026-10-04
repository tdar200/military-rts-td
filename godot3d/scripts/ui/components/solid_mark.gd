extends Control
## A solid dot or a solid rotated square (diamond) centred in its box. `size_px` is the CSS box side / diameter
## before rotation, so a diamond's bounding box is size_px * sqrt(2). Hostile things are diamonds, never colour alone.
const T = preload("res://scripts/ui/tokens.gd")

var kind := "dot"
var tone: Color = T.BAD
var side := 10.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Bounding box edge for a mark of this kind and size.
static func bound(k: String, px: float) -> float:
	return px * 1.41421356 if k == "diamond" else px


func setup(k: String, px: float, color: Color) -> Control:
	kind = k
	side = px
	tone = color
	custom_minimum_size = Vector2.ONE * bound(k, px)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var c := size * 0.5
	if kind == "diamond":
		var h := side * 0.70710678
		var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
		draw_colored_polygon(pts, tone)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), tone, 1.0, true)
	else:
		draw_circle(c, side * 0.5, tone)
