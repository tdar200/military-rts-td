extends Control
## The mock's .chip: a bordered pill holding an optional icon followed by text parts, 8px apart.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

var icon_name := ""
var icon_color: Color = T.CYAN
var border_color: Color = T.LINE
var fill: Color = T.BG2
var ring := Color(0, 0, 0, 0)
var chip_height := 28
var icon_px := 18
var dashed := false
var pad := 10
var gap := 8
var _boxes: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## parts: [{t: text, col: Color, f: kind, px: size, wt: weight, sp: letter-spacing em}]. Mono 13px is the default run.
func setup(icon: String, icon_col: Color, parts: Array, o := {}) -> Control:
	icon_name = icon
	icon_color = icon_col
	border_color = o.get("border", T.LINE)
	fill = o.get("fill", T.BG2)
	ring = o.get("ring", Color(0, 0, 0, 0))
	chip_height = o.get("h", 28)
	icon_px = o.get("icon_px", 18)
	dashed = o.get("dashed", false)
	pad = o.get("pad", 10)
	gap = o.get("gap", 8)
	for box in _boxes:
		box.queue_free()
	_boxes.clear()
	var x := 1.0 + pad
	if icon != "":
		Icons.texture(icon, icon_px)
		x += icon_px + gap
	for part in parts:
		var box := TextBox.new()
		add_child(box)
		box.configure(part["t"], {"f": part.get("f", "mono"), "px": part.get("px", 13), "wt": part.get("wt", 0), "sp": part.get("sp", 0.0), "col": part.get("col", T.TEXT), "up": part.get("up", false)})
		var m := box.get_minimum_size()
		box.size = m
		box.position = Vector2(x, (chip_height - m.y) * 0.5)
		x += m.x + gap
		_boxes.append(box)
	custom_minimum_size = Vector2(x - gap + pad + 1.0, chip_height)
	size = custom_minimum_size
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if ring.a > 0.0:
		var halo := StyleBoxFlat.new()
		halo.draw_center = false
		halo.set_border_width_all(1)
		halo.border_color = ring
		halo.set_corner_radius_all(3)
		draw_style_box(halo, rect.grow(1))
	draw_rect(rect, fill)
	if dashed:
		var a := Vector2(0.5, 0.5)
		var c := size - Vector2(0.5, 0.5)
		var b := Vector2(c.x, a.y)
		var d := Vector2(a.x, c.y)
		for edge in [[a, b], [b, c], [c, d], [d, a]]:
			draw_dashed_line(edge[0], edge[1], border_color, 1.0, 3.0)
	else:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = border_color
		box.set_corner_radius_all(2)
		draw_style_box(box, rect)
	if icon_name != "":
		var tex := Icons.cached(icon_name, icon_px)
		if tex:
			draw_texture(tex, Vector2(1.0 + pad, (chip_height - icon_px) * 0.5), icon_color)
