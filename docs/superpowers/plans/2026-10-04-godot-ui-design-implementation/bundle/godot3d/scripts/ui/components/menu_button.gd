extends Button
## The title screen's .menu-btn: icon, Rajdhani label and a right-aligned mono hint on a 440x56 bar.
## The three items shrink in proportion when they do not fit (CSS flex-shrink), then wrap, as the mock does for
## "Continue campaign". `text` carries the label so QA tools find the button by name; the Button's own text is never drawn.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const PAD := 20.0
const GAP := 14.0
const ICON_PX := 24.0

var emphasis := ""
var hint := ""
var icon_name := ""
var _label: TextBox
var _hint: TextBox
var _icon_w := ICON_PX


func _init() -> void:
	flat = true
	clip_text = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(slot, Color(0, 0, 0, 0))
	add_theme_font_size_override("font_size", 1)
	_label = TextBox.new()
	_hint = TextBox.new()
	add_child(_label)
	add_child(_hint)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Options: hint, icon, emphasis ("primary" | "secondary" | ""), disabled, w, h.
func setup(label: String, o := {}) -> Control:
	text = label
	hint = str(o.get("hint", ""))
	icon_name = str(o.get("icon", ""))
	emphasis = str(o.get("emphasis", ""))
	disabled = o.get("disabled", false)
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	size = Vector2(o.get("w", 440.0), o.get("h", 56.0))
	custom_minimum_size = size
	if icon_name != "":
		Icons.texture(icon_name, int(ICON_PX))
	_label.configure(label, {"f": "disp", "wt": 600, "px": 21, "sp": 0.1, "up": true, "wrap": true})
	_hint.configure(hint, {"f": "mono", "wt": 600, "px": 13, "sp": 0.06, "wrap": true, "faux": true})
	_layout()
	queue_redraw()
	return self


## Alpha the entry is drawn with: 0.45 when disabled, else 1.
func disabled_alpha() -> float:
	return 0.45 if disabled else 1.0


func _layout() -> void:
	var items := 1 + (1 if icon_name != "" else 0) + (1 if hint != "" else 0)
	var inner := size.x - 2.0 - 2.0 * PAD - GAP * (items - 1)
	var icon_nat := ICON_PX if icon_name != "" else 0.0
	var label_nat := _label.measure(text.to_upper())
	var hint_nat := _hint.measure(hint) if hint != "" else 0.0
	var total := icon_nat + label_nat + hint_nat
	var shrink := maxf(total - inner, 0.0) / maxf(total, 1.0)
	_icon_w = icon_nat * (1.0 - shrink)
	var label_w := label_nat * (1.0 - shrink)
	var hint_w := hint_nat * (1.0 - shrink)
	var x := 1.0 + PAD + (_icon_w + GAP if icon_name != "" else 0.0)
	_label.size = Vector2(label_w + 0.5, 0.0)
	_label.configure(text, {"wrap": true})
	_label.size = Vector2(label_w + 0.5, _label.get_minimum_size().y)
	_label.position = Vector2(x, roundf((size.y - _label.size.y) * 0.5))
	_hint.visible = hint != ""
	if hint != "":
		_hint.size = Vector2(hint_w + 0.5, 0.0)
		_hint.configure(hint, {"wrap": true})
		_hint.size = Vector2(hint_w + 0.5, _hint.get_minimum_size().y)
		_hint.position = Vector2(roundf(size.x - 1.0 - PAD - hint_w), roundf((size.y - _hint.size.y) * 0.5 - 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _label:
		_layout()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill := Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.82)
	var edge: Color = T.LINE_DIM
	var ink: Color = T.TEXT
	var hint_ink: Color = T.DIM
	var lit := is_hovered() and not disabled
	if emphasis == "primary":
		fill = T.HOVER if lit else T.ACTIVE
		edge = T.CYAN
		ink = T.TEXT_HI
		hint_ink = T.TEXT
	elif emphasis == "secondary" or lit:
		fill = T.HOVER
		edge = T.CYAN_DK
	if is_pressed() and not disabled:
		fill = fill.lightened(0.12)
	var fade := 0.45 if disabled else 1.0
	if emphasis == "primary":
		for i in range(1, 12):
			var halo := StyleBoxFlat.new()
			halo.draw_center = false
			halo.set_border_width_all(1)
			halo.border_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.25 * fade * pow(1.0 - i / 12.0, 2.0) * 0.6)
			halo.set_corner_radius_all(2 + i)
			draw_style_box(halo, rect.grow(i))
	draw_rect(rect, Color(fill.r, fill.g, fill.b, fill.a * fade))
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = Color(edge.r, edge.g, edge.b, edge.a * fade)
	box.set_corner_radius_all(2)
	draw_style_box(box, rect)
	_label.set_color(Color(ink.r, ink.g, ink.b, fade))
	_hint.set_color(Color(hint_ink.r, hint_ink.g, hint_ink.b, fade))
	if icon_name != "":
		var tex := Icons.cached(icon_name, int(ICON_PX))
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(1.0 + PAD, (size.y - ICON_PX) * 0.5), Vector2(_icon_w, ICON_PX)), false, Color(ink.r, ink.g, ink.b, fade))
	if has_focus():
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(2)
		ring.border_color = T.CYAN_HI
		ring.set_corner_radius_all(3)
		draw_style_box(ring, rect.grow(3))
