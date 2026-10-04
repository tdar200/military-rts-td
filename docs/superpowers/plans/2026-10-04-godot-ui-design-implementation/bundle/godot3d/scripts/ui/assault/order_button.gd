extends Button
## One tile of the orders deck: a Rajdhani 15px caps label over a 20px key hint, centred in the tile. The Button's
## own text stays set (QA tooling finds buttons by it) but is drawn invisible; this control paints itself.
## Tones: "" (plain), "primary" (cyan, glowing), "warn" (amber edge and label).
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const KEY_H := 20
const LABEL_PX := 15
## The mock buttons inherit letter-spacing .08em of their own 17px size as an absolute 1.36px.
const SPACING := 1.36

var tone := ""
var key_text := ""
var _label: TextBox


func _init() -> void:
	flat = true
	clip_text = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(slot, Color(0, 0, 0, 0))
	add_theme_font_size_override("font_size", 1)
	_label = TextBox.new()
	add_child(_label)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


static func key_width(s: String) -> float:
	return s.length() * (T.MONO_ADVANCE * 12.0 + SPACING) + 12.0


func setup(label: String, key: String, w: float, h: float, tone_name := "") -> Control:
	text = label
	key_text = key.to_upper()
	tone = tone_name
	size = Vector2(w, h)
	custom_minimum_size = size
	_label.configure(label, {"f": "disp", "wt": 600, "px": LABEL_PX, "sp": SPACING / LABEL_PX, "up": true, "al": "c", "wrap": false})
	_place()
	queue_redraw()
	return self


func _place() -> void:
	var lh := _label.pitch()
	var total := lh + (2.0 + KEY_H if key_text != "" else 0.0)
	var inner_w := size.x - 2.0
	_label.size = Vector2(inner_w, lh)
	_label.position = Vector2(1.0, roundf((size.y - total) * 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _label:
		_place()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill: Color = T.ACTIVE if tone == "primary" else T.RAISED
	var edge: Color = T.CYAN if tone == "primary" else (T.WARN if tone == "warn" else T.LINE)
	var ink: Color = T.TEXT_HI if tone == "primary" else (T.WARN if tone == "warn" else T.TEXT)
	if is_hovered() and not disabled:
		fill = T.HOVER
	if is_pressed() and not disabled:
		fill = fill.lightened(0.12)
	var fade := 0.45 if disabled else 1.0
	fill.a *= fade
	edge.a *= fade
	ink.a *= fade
	_label.set_color(ink)
	if tone == "primary":
		for i in range(1, 10):
			var halo := StyleBoxFlat.new()
			halo.draw_center = false
			halo.set_border_width_all(1)
			halo.border_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.22 * fade * pow(1.0 - i / 10.0, 2.0) * 0.6)
			halo.set_corner_radius_all(2 + i)
			draw_style_box(halo, rect.grow(i))
	draw_rect(rect, fill)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = edge
	box.set_corner_radius_all(2)
	draw_style_box(box, rect)
	if key_text != "":
		var kw := key_width(key_text)
		var kx := roundf((size.x - kw) * 0.5 * 2.0) * 0.5
		var ky := _label.position.y + _label.pitch() + 2.0
		var kbox := StyleBoxFlat.new()
		kbox.draw_center = false
		kbox.set_border_width_all(1)
		kbox.border_color = Color(T.LINE.r, T.LINE.g, T.LINE.b, T.LINE.a * fade)
		kbox.set_corner_radius_all(2)
		draw_style_box(kbox, Rect2(kx, ky, kw, KEY_H))
		var f := T.font("mono", 600)
		var asc := T.ascent(f, 12)
		var baseline := ky + (KEY_H - (asc + T.descent(f, 12))) * 0.5 + asc
		var step := T.MONO_ADVANCE * 12.0 + SPACING
		var dim := Color(T.DIM.r, T.DIM.g, T.DIM.b, T.DIM.a * fade)
		for i in key_text.length():
			if key_text[i] != " ":
				draw_char(f, Vector2(kx + 6.0 + i * step, baseline), key_text[i], 12, dim)
