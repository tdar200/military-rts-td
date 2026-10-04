extends RefCounted
## Terse node factories used by every screen builder. Geometry is in the mock's pixel space: (x, y) is the top-left
## of the element's CSS box, relative to the parent.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const HoloPanel = preload("res://scripts/ui/components/holo_panel.gd")
const Chip = preload("res://scripts/ui/components/chip.gd")
const Tag = preload("res://scripts/ui/components/tag.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")
const Bar = preload("res://scripts/ui/components/bar.gd")
const Icon = preload("res://scripts/ui/components/icon.gd")
const HoloButton = preload("res://scripts/ui/components/holo_button.gd")


static func place(n: Control, x: float, y: float, w := -1.0, h := -1.0) -> Control:
	n.position = Vector2(roundf(x), roundf(y))
	if w >= 0.0 or h >= 0.0:
		n.size = Vector2(maxf(w, 0.0), maxf(h, 0.0))
	return n


static func text(parent: Node, s: String, o := {}) -> Control:
	var t := TextBox.new()
	t.position = Vector2(roundf(o.get("x", 0.0)), roundf(o.get("y", 0.0)))
	if o.has("w"):
		t.size = Vector2(o["w"], 0.0)
	parent.add_child(t)
	t.configure(s, o)
	var m := t.get_minimum_size()
	t.size = Vector2(o.get("w", m.x), o.get("h", m.y))
	return t


static func panel(parent: Node, x: float, y: float, w: float, h: float, kind := "panel", o := {}) -> Control:
	var p := HoloPanel.new()
	place(p, x, y, w, h)
	parent.add_child(p)
	p.preset(kind)
	p.style(o)
	return p


static func icon(parent: Node, name: String, x: float, y: float, color: Color, px := 18, stroke := 1.75) -> Control:
	var i := Icon.new()
	place(i, x, y)
	parent.add_child(i)
	i.setup(name, color, px, stroke)
	return i


static func tag(parent: Node, s: String, x: float, y: float, color: Color, bg := Color(0, 0, 0, 0)) -> Control:
	var t := Tag.new()
	place(t, x, y)
	parent.add_child(t)
	t.setup(s, color, bg)
	return t


static func key(parent: Node, s: String, x: float, y: float, o := {}) -> Control:
	var k := KeyCap.new()
	place(k, x, y)
	parent.add_child(k)
	k.setup(s, o)
	return k


static func bar(parent: Node, x: float, y: float, w: float, ratio: float, color: Color = T.CYAN, h := 6.0) -> Control:
	var b := Bar.new()
	place(b, x, y, w, h)
	parent.add_child(b)
	b.setup(ratio, color)
	return b


static func chip(parent: Node, x: float, y: float, icon_name: String, icon_color: Color, parts: Array, o := {}) -> Control:
	var c := Chip.new()
	place(c, x, y)
	parent.add_child(c)
	c.setup(icon_name, icon_color, parts, o)
	return c


static func button(parent: Node, label: String, x: float, y: float, o := {}) -> Control:
	var b := HoloButton.new()
	place(b, x, y)
	parent.add_child(b)
	b.setup(label, o)
	return b


const Diamond = preload("res://scripts/ui/components/diamond.gd")
static var _sprites: Dictionary = {}


## Load a sprite from a res:// path or an absolute file path (the gallery uses repo art outside the project).
static func sprite_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _sprites.has(path):
		return _sprites[path]
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image:
			tex = ImageTexture.create_from_image(image)
	_sprites[path] = tex
	return tex


static func sprite(parent: Node, path: String, x: float, y: float, w: float, h: float, grey := false) -> Control:
	var rect := TextureRect.new()
	rect.texture = sprite_texture(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(rect, x, y, w, h)
	if grey:
		rect.modulate = Color(0.55, 0.55, 0.55, 1)
	parent.add_child(rect)
	return rect


static func diamond(parent: Node, cx: float, cy: float, half: float, color: Color = T.BAD, filled := true) -> Control:
	var d := Diamond.new()
	place(d, cx - half, cy - half)
	parent.add_child(d)
	d.setup(half, color, filled)
	return d


static func rule(parent: Node, x: float, y: float, w: float, h: float, color: Color) -> Control:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(r, x, y, w, h)
	parent.add_child(r)
	return r


## Invisible click target. Its `text` is the accessible label (QA tools and tests find controls by it), never drawn.
static func hit(parent: Node, x: float, y: float, w: float, h: float, label := "") -> Button:
	var b := Button.new()
	b.text = label
	b.flat = true
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(slot, Color(0, 0, 0, 0))
	place(b, x, y, w, h)
	parent.add_child(b)
	return b
