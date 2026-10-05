extends Button
## Mock buttons and tabs. The Button's own text stays set (QA tooling finds buttons by it) but is drawn invisible;
## this control paints itself. Variants: "btn" (.btn / .btn.pri) and "tab" (.tab / .tab.on).
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

var variant := "btn"
var primary := false
## The mock's .btn.danger: a dull red edge and pale red ink (Demolish).
var danger := false
var active := false
var key_text := ""
var icon_name := ""
var column := false
var min_height := 44.0
var pad_x := 18.0
var label_px := 17
var label_sp := 0.08
var wrap_label := false
## Label at the left padding and the key cap at the right padding (the pause menu .btn is a space-between row).
var spread := false
var icon_px := 18
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


## Options: variant, primary, danger, key, icon, column, px, sp, min_h, pad, w, h (explicit size), tab_on, spread.
func setup(label: String, o := {}) -> Control:
	text = label
	variant = o.get("variant", variant)
	primary = o.get("primary", primary)
	danger = o.get("danger", danger)
	active = o.get("on", active)
	key_text = str(o.get("key", key_text)).to_upper()
	icon_name = o.get("icon", icon_name)
	column = o.get("column", column)
	wrap_label = o.get("wrap", wrap_label)
	spread = o.get("spread", spread)
	icon_px = o.get("icon_px", icon_px)
	min_height = o.get("min_h", 40.0 if variant == "tab" else min_height)
	pad_x = o.get("pad", 14.0 if variant == "tab" else pad_x)
	label_px = o.get("px", 16 if variant == "tab" else label_px)
	label_sp = o.get("sp", 0.08)
	if icon_name != "":
		Icons.texture(icon_name, icon_px)
	_label.configure(label, {"f": "disp", "wt": 600, "px": label_px, "sp": label_sp, "up": true, "al": "c" if column or wrap_label else "l", "wrap": column or wrap_label})
	var natural := natural_size()
	size = Vector2(o.get("w", natural.x), o.get("h", natural.y))
	custom_minimum_size = size
	_place_label()
	queue_redraw()
	return self


func _key_width() -> float:
	return KeyCap.measure(key_text, label_sp * label_px) if key_text != "" else 0.0


func natural_size() -> Vector2:
	var line := _label.pitch()
	if variant == "tab":
		var w := 2.0 + 2.0 * pad_x + (icon_px + 8.0 if icon_name != "" else 0.0) + _label.measure(text.to_upper())
		return Vector2(w, min_height)
	var content_w := _label.measure(text.to_upper())
	if icon_name != "":
		content_w += icon_px + (8.0 if text != "" else 0.0)
	var h := min_height
	if column:
		return Vector2(2.0 + 2.0 * pad_x + content_w, maxf(min_height, 2.0 + line + (2.0 + KeyCap.HEIGHT if key_text != "" else 0.0)))
	if key_text != "":
		content_w += 8.0 + _key_width()
	return Vector2(2.0 + 2.0 * pad_x + content_w, h)


func _place_label() -> void:
	var inner_w := size.x - 2.0 - 2.0 * pad_x
	if column:
		_label.size = Vector2(inner_w, 0)
		_label.configure(text, {"wrap": true, "al": "c"})
		var lh := _label.get_minimum_size().y
		_label.size = Vector2(inner_w, lh)
		var total := lh + (2.0 + KeyCap.HEIGHT if key_text != "" else 0.0)
		_label.position = Vector2(1.0 + pad_x, (size.y - total) * 0.5)
	elif variant == "tab":
		_label.size = _label.get_minimum_size()
		_label.position = Vector2(1.0 + pad_x + (icon_px + 8.0 if icon_name != "" else 0.0), (size.y - _label.size.y) * 0.5)
	elif wrap_label:
		# Icon at the left padding, the label wraps in the space left over and is centred in it.
		var lead_w := icon_px + 8.0 if icon_name != "" else 0.0
		_label.size = Vector2(inner_w - lead_w, 0)
		_label.configure(text, {"wrap": true, "al": "c"})
		var wrapped_h := _label.get_minimum_size().y
		_label.size = Vector2(inner_w - lead_w, wrapped_h)
		_label.position = Vector2(1.0 + pad_x + lead_w, (size.y - wrapped_h) * 0.5)
	elif spread:
		_label.size = _label.get_minimum_size()
		_label.position = Vector2(1.0 + pad_x, (size.y - _label.size.y) * 0.5)
	else:
		_label.size = _label.get_minimum_size()
		var total := _label.size.x + (8.0 + _key_width() if key_text != "" else 0.0)
		var lead := icon_px + 8.0 if icon_name != "" and text != "" else 0.0
		_label.position = Vector2((size.x - total + lead) * 0.5, (size.y - _label.size.y) * 0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _label:
		_place_label()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill: Color
	var edge: Color
	var ink: Color
	if variant == "tab":
		fill = T.ACTIVE if active else T.BG2
		edge = T.CYAN if active else T.LINE_DIM
		ink = T.TEXT_HI if active else T.DIM
	elif primary:
		fill = T.HOVER if is_hovered() and not disabled else T.ACTIVE
		edge = T.CYAN
		ink = T.TEXT_HI
	else:
		fill = T.HOVER if is_hovered() and not disabled else T.RAISED
		edge = T.DANGER_EDGE if danger else T.LINE
		ink = T.BAD_HI if danger else T.TEXT
	if is_pressed() and not disabled:
		fill = fill.lightened(0.12)
	var fade := 0.45 if disabled else 1.0
	fill.a *= fade
	edge.a *= fade
	ink.a *= fade
	_label.set_color(ink)
	if primary and variant != "tab":
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
	if variant == "tab":
		box.border_width_bottom = 0
		box.corner_radius_top_left = 3
		box.corner_radius_top_right = 3
	else:
		box.set_corner_radius_all(2)
	draw_style_box(box, rect)
	if icon_name != "":
		var tex := Icons.cached(icon_name, icon_px)
		if tex:
			draw_texture(tex, Vector2(1.0 + pad_x, (size.y - icon_px) * 0.5), ink)
	if key_text != "":
		var sp := label_sp * label_px
		var at: Vector2
		if column:
			at = Vector2((size.x - _key_width()) * 0.5, _label.position.y + _label.size.y + 2.0)
		elif spread:
			at = Vector2(size.x - 1.0 - pad_x - _key_width(), (size.y - KeyCap.HEIGHT) * 0.5)
		else:
			at = Vector2(_label.position.x + _label.size.x + 8.0, (size.y - KeyCap.HEIGHT) * 0.5)
		KeyCap.paint(self, at, key_text, sp, T.LINE, T.TEXT, T.KEY_BG, 600)
