extends Control
## The mock's .panel and .glass surfaces: vertical gradient fill, 1px border with a small radius, an inner top light,
## optional glow ring, optional dashed border and optional left accent stripe.
const T = preload("res://scripts/ui/tokens.gd")

var fill_top: Color = T.PANEL_TOP
var fill_bottom: Color = T.PANEL_BOT
var border_color: Color = T.LINE
var border_px := 1
var radius := 3
var top_left_radius := -1
var top_light := true
var dashed := false
var ring_color := Color(0, 0, 0, 0)
var glow_color := Color(0, 0, 0, 0)
var accent_color := Color(0, 0, 0, 0)
var accent_px := 3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## kind "panel" is the large gradient surface, "glass" the flat translucent card.
func preset(kind: String) -> Control:
	if kind == "glass":
		fill_top = T.GLASS
		fill_bottom = T.GLASS
		border_color = T.LINE_DIM
		top_light = false
	else:
		fill_top = T.PANEL_TOP
		fill_bottom = T.PANEL_BOT
		border_color = T.LINE
		top_light = true
	queue_redraw()
	return self


func style(o: Dictionary) -> Control:
	border_color = o.get("border", border_color)
	ring_color = o.get("ring", ring_color)
	glow_color = o.get("glow", glow_color)
	fill_top = o.get("fill", o.get("fill_top", fill_top))
	fill_bottom = o.get("fill", o.get("fill_bottom", fill_bottom))
	radius = o.get("radius", radius)
	top_left_radius = o.get("tl", top_left_radius)
	dashed = o.get("dashed", dashed)
	accent_color = o.get("accent", accent_color)
	top_light = o.get("light", top_light)
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if glow_color.a > 0.0:
		for i in range(1, 13):
			var halo := glow_color
			halo.a = glow_color.a * pow(1.0 - i / 13.0, 2.0) * 0.55
			draw_style_box(_outline(halo, 1, radius + i), rect.grow(i))
	if ring_color.a > 0.0:
		draw_style_box(_outline(ring_color, 1, radius + 1), rect.grow(1))
	var inner := rect
	var top := PackedColorArray([fill_top, fill_top, fill_bottom, fill_bottom])
	draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]), top)
	if dashed:
		_dashed_border(rect)
	else:
		var box := _outline(border_color, border_px, radius)
		if top_left_radius >= 0:
			box.corner_radius_top_left = top_left_radius
		draw_style_box(box, rect)
	if top_light:
		draw_line(Vector2(border_px + 1, border_px + 0.5), Vector2(size.x - border_px - 1, border_px + 0.5), T.TOP_LIGHT, 1.0)
	if accent_color.a > 0.0:
		draw_rect(Rect2(0, 0, accent_px, size.y), accent_color)


func _outline(color: Color, width: int, corner: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(width)
	box.border_color = color
	box.set_corner_radius_all(corner)
	return box


func _dashed_border(rect: Rect2) -> void:
	var a := rect.position + Vector2(0.5, 0.5)
	var b := Vector2(rect.end.x - 0.5, a.y)
	var c := rect.end - Vector2(0.5, 0.5)
	var d := Vector2(a.x, c.y)
	for edge in [[a, b], [b, c], [c, d], [d, a]]:
		draw_dashed_line(edge[0], edge[1], border_color, 1.0, 3.0)
