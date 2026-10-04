extends Control
## A tinted stroke icon from icons.gd.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var icon_name := ""
var tint: Color = T.TEXT
var px := 18
var stroke := 1.75


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(name: String, color: Color, size_px := 18, stroke_w := 1.75) -> Control:
	icon_name = name
	tint = color
	px = size_px
	stroke = stroke_w
	Icons.texture(name, px, stroke)
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var tex := Icons.cached(icon_name, px, stroke)
	if tex:
		draw_texture(tex, Vector2.ZERO, tint)
