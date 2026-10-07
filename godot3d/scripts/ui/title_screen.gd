extends Control
## Title and campaign screen, built from a plain view model. Geometry is the Title mock at 1920x1080
## (docs/ascension/ui-mocks/Title.dc.html, measured with tools/ui/dump_boxes.py).
## Emits action(name, arg): menu entries emit their `action` when they have one, else their `id` ("continue", "new", ...);
## the featured card's buttons emit their `action`.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Fx = preload("res://scripts/ui/fx.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const MenuBtn = preload("res://scripts/ui/components/menu_button.gd")
const Wordmark = preload("res://scripts/ui/components/wordmark.gd")

signal action(name: String, arg: Variant)

const SECTIONS := [
	["backdrop", "_build_backdrop"],
	["brand", "_build_brand"],
	["menu", "_build_menu"],
	["campaign", "_build_campaign"],
	["footer", "_build_footer"],
]
const PANEL := Rect2(1180, 56, 664, 920)
const GRID_BOTTOM := 951.0
const CARD_MIN_H := 160.0
const CARD_MAX_H := 187.8

var _layers: Dictionary = {}
var _hashes: Dictionary = {}
var _menu_buttons: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func apply(vm: Dictionary) -> void:
	var slices := {
		"backdrop": vm.get("backdrop", true),
		"brand": {"eyebrow": vm.get("eyebrow", ""), "title": vm.get("title", ""), "tagline": vm.get("tagline", "")},
		"menu": vm.get("menu", []),
		"campaign": vm.get("campaign", {}),
		"footer": {"left": vm.get("footer_left", ""), "right": vm.get("footer_right", "")},
	}
	for entry in SECTIONS:
		var key: String = entry[0]
		var slice: Variant = slices[key]
		var h := hash(slice)
		if _hashes.get(key, -1) == h and _layers.has(key):
			continue
		_hashes[key] = h
		_rebuild(key, entry[1], slice)


## Give keyboard focus to the first enabled menu entry (the host calls this when the screen opens).
func focus_first() -> void:
	var b := first_enabled()
	if b and b.is_inside_tree():
		b.grab_focus()


func first_enabled() -> Control:
	for b in _menu_buttons:
		if not b.disabled:
			return b
	return null


## Menu buttons in menu order (the order keyboard focus follows).
func menu_buttons() -> Array:
	return _menu_buttons


func layer(key: String) -> Control:
	return _layers.get(key)


## True when `point` is over any screen surface that must swallow the click (menu, campaign cards).
func blocks_point(point: Vector2) -> bool:
	for key in ["menu", "campaign"]:
		var l: Control = _layers.get(key)
		if l == null:
			continue
		for child in l.get_children():
			if child is Control and child.visible and child.mouse_filter == Control.MOUSE_FILTER_STOP:
				if Rect2(child.position, child.size).has_point(point):
					return true
	return false


func _rebuild(key: String, builder: String, slice: Variant) -> void:
	var old: Control = _layers.get(key)
	if old:
		remove_child(old)
		old.queue_free()
	var l := Control.new()
	l.name = key
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(l)
	_layers[key] = l
	if key == "menu":
		_menu_buttons = []
	if slice is bool and not slice:
		return
	call(builder, l, slice)


func _emit(name: String, arg: Variant = null) -> void:
	action.emit(name, arg)


# ---------------------------------------------------------------- backdrop (code-drawn; the host may hide it to show a 3D scene)

func _build_backdrop(root: Control, _on: Variant) -> void:
	var full := Rect2(0, 0, 1920, 1080)
	Fx.linear(root, full, [[Color("03050a"), 0.0], [Color("060b14"), 0.6], [Color("08121c"), 1.0]])
	Fx.radial(root, full, Vector2(0.18 * 1920, 0.08 * 1080), Vector2(900, 600), [[Color(24.0 / 255.0, 90.0 / 255.0, 110.0 / 255.0, 0.28), 0.0], [Color(24.0 / 255.0, 90.0 / 255.0, 110.0 / 255.0, 0.0), 0.65]])
	Fx.radial(root, full, Vector2(0.72 * 1920, 0.80 * 1080), Vector2(1200, 700), [[Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.10), 0.0], [Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.0), 0.6]])
	var sky := _Sky.new()
	sky.size = full.size
	root.add_child(sky)
	Fx.limb(root, Rect2(0, 700, 1920, 380))
	Fx.linear(root, Rect2(300, 842, 1320, 3), [[Color(240.0 / 255.0, 176.0 / 255.0, 64.0 / 255.0, 0.0), 0.0], [Color(240.0 / 255.0, 176.0 / 255.0, 64.0 / 255.0, 0.5), 0.5], [Color(240.0 / 255.0, 176.0 / 255.0, 64.0 / 255.0, 0.0), 1.0]], true)
	Fx.linear(root, Rect2(0, 760, 1920, 320), [[Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.0), 0.0], [Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.55), 1.0]])


## Stars, the dashed orbital arc and its marker.
class _Sky extends Control:
	const STARS := [
		[140, 90, 1.5, "cee8f0"], [330, 210, 1.0, "8fb0bf"], [520, 60, 1.5, "96f5ff"], [760, 150, 1.0, "cee8f0"],
		[910, 40, 1.0, "8fb0bf"], [1090, 120, 1.5, "cee8f0"], [1260, 70, 1.0, "8fb0bf"], [1500, 30, 1.0, "cee8f0"],
		[1710, 100, 1.5, "96f5ff"], [1850, 260, 1.0, "8fb0bf"], [60, 380, 1.0, "8fb0bf"], [640, 330, 1.0, "cee8f0"],
		[1010, 300, 1.0, "8fb0bf"], [1620, 440, 1.5, "cee8f0"],
	]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for s in STARS:
			var col := Color(s[3])
			draw_circle(Vector2(s[0], s[1]), s[2] * 0.75, Color(col.r, col.g, col.b, 0.9))
		# 2500x900 ellipse centred (990, 750), rotated -7 degrees, 1px dashes 3 on / 3 off.
		var rot := deg_to_rad(-7.0)
		var arc := Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.32)
		var prev := Vector2.ZERO
		var run := 0.0
		var have_prev := false
		var steps := 9000
		for i in steps + 1:
			var a := TAU * i / steps
			var p := Vector2(1250.0 * cos(a), 450.0 * sin(a)).rotated(rot) + Vector2(990, 750)
			if have_prev:
				var d := p.distance_to(prev)
				if int(floor(run / 3.0)) % 2 == 0 and p.x > -10 and p.x < 1930 and p.y > -10 and p.y < 1090:
					draw_line(prev, p, arc, 1.0)
				run += d
			prev = p
			have_prev = true
		for i in range(1, 9):
			draw_circle(Vector2(1123, 329), 5.0 + i * 1.6, Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.55 * pow(1.0 - i / 9.0, 2.0) * 0.5))
		draw_circle(Vector2(1123, 329), 5.0, T.CYAN_HI)


# ---------------------------------------------------------------- wordmark

func _build_brand(root: Control, vm: Dictionary) -> void:
	var eyebrow := str(vm.get("eyebrow", ""))
	if eyebrow != "":
		K.rule(root, 120, 103, 36, 1, T.CYAN)
		K.text(root, eyebrow, {"x": 168, "y": 96, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	if str(vm.get("title", "")) != "":
		var mark := Wordmark.new()
		K.place(mark, 120, 125)
		root.add_child(mark)
		mark.setup(str(vm.get("title", "")), 128, 0.1)
	var tagline := str(vm.get("tagline", ""))
	if tagline != "":
		K.text(root, tagline, {"x": 120, "y": 263, "f": "disp", "wt": 600, "px": 30, "sp": 0.2, "col": T.TEXT, "up": true})


# ---------------------------------------------------------------- menu

func _build_menu(root: Control, items: Array) -> void:
	_menu_buttons = []
	var y := 432.0
	for item in items:
		var b := MenuBtn.new()
		b.name = "menu_%s" % str(item.get("id", _menu_buttons.size()))
		K.place(b, 120, y)
		root.add_child(b)
		b.setup(str(item.get("label", "")), item)
		b.pressed.connect(_emit.bind(str(item.get("action", item.get("id", ""))), null))
		_menu_buttons.append(b)
		y += 66.0
	var order: Array = _menu_buttons.filter(func(b): return not b.disabled)
	for i in order.size():
		var prev: Control = order[(i - 1 + order.size()) % order.size()]
		var next: Control = order[(i + 1) % order.size()]
		order[i].focus_next = NodePath("../" + String(next.name))
		order[i].focus_previous = NodePath("../" + String(prev.name))
		order[i].focus_neighbor_bottom = order[i].focus_next
		order[i].focus_neighbor_top = order[i].focus_previous


# ---------------------------------------------------------------- campaign panel

func _build_campaign(root: Control, vm: Dictionary) -> void:
	if vm.is_empty():
		return
	K.panel(root, PANEL.position.x, PANEL.position.y, PANEL.size.x, PANEL.size.y)
	K.text(root, str(vm.get("title", "Campaign")), {"x": 1205, "y": 81, "f": "disp", "wt": 600, "px": 28, "sp": 0.04, "col": T.TEXT, "up": true})
	var summary := K.text(root, str(vm.get("summary", "")), {"x": 0, "y": 91.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	summary.position.x = roundf(1819.0 - summary.size.x)
	var y := 133.0
	var featured: Dictionary = vm.get("featured", {})
	if not featured.is_empty():
		y += _featured_card(root, featured, y) + 16.0
	var chapters: Array = vm.get("chapters", [])
	if chapters.is_empty():
		return
	K.text(root, str(vm.get("later_title", "")), {"x": 1205, "y": y + 2.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var note := K.text(root, str(vm.get("later_note", "")), {"x": 0, "y": y + 2.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.VIOLET, "up": true})
	note.position.x = roundf(1819.0 - note.size.x)
	_chapter_grid(root, chapters, y + 2.0 + 15.0 + 16.0)


func _featured_card(root: Control, f: Dictionary, y: float) -> float:
	var facts: Array = f.get("facts", [])
	var name_o := {"f": "disp", "wt": 600, "px": 34, "sp": 0.04, "lh": 37.4, "up": true}
	var blurb_o := {"px": 16}
	var name_s := TextBoxProbe.clip(str(f.get("name", "")), name_o, 574.0, 2)
	var blurb_s := TextBoxProbe.clip(str(f.get("blurb", "")), blurb_o, 574.0, 2)
	var name_box := TextBoxProbe.measure_wrapped(name_s, name_o, 574.0)
	var blurb_box := TextBoxProbe.measure_wrapped(blurb_s, blurb_o, 574.0)
	var fact_rows := int(ceil(facts.size() / 2.0))
	var facts_h := fact_rows * 36.0 + maxf(fact_rows - 1, 0) * 10.0
	var h := 130.0 + 16.0 + name_box + (4.0 + blurb_box if blurb_box > 0.0 else 0.0) + (14.0 + facts_h if fact_rows > 0 else 0.0) + 14.0 + 44.0 + 20.0
	K.panel(root, 1205, y, 614, h, "panel", {
		"fill_top": Color(16.0 / 255.0, 70.0 / 255.0, 86.0 / 255.0, 0.55), "fill_bottom": Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.9),
		"border": Color(0, 0, 0, 0), "light": false,
		"ring": Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.55), "glow": Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.18),
	})
	_card_header(root, f, y)
	var cy := y + 130.0 + 16.0
	var name := K.text(root, name_s, {"x": 1225, "y": cy, "w": 574, "f": "disp", "wt": 600, "px": 34, "sp": 0.04, "lh": 37.4, "col": T.TEXT_HI, "up": true, "wrap": true})
	cy += name.size.y
	if blurb_box > 0.0:
		var blurb := K.text(root, blurb_s, {"x": 1225, "y": cy + 4.0, "w": 574, "px": 16, "col": T.DIM, "wrap": true})
		cy += 4.0 + blurb.size.y
	if fact_rows > 0:
		cy += 14.0
		for i in facts.size():
			var fx := 1225.0 + (i % 2) * 297.0
			var fy := cy + (i / 2) * 46.0
			K.text(root, str(facts[i].get("k", "")), {"x": fx, "y": fy, "w": 277, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
			K.text(root, TextBoxProbe.clip(str(facts[i].get("v", "")), {"px": 15}, 277.0, 1), {"x": fx, "y": fy + 17.0, "w": 277, "px": 15, "col": T.TEXT, "wrap": true})
		cy += facts_h
	cy += 14.0
	var primary: Dictionary = f.get("primary", {})
	var secondary: Dictionary = f.get("secondary", {})
	if not primary.is_empty():
		var b := K.button(root, str(primary.get("label", "")), 1225, cy, {"w": 281, "h": 44, "primary": true})
		b.disabled = primary.get("disabled", false)
		b.pressed.connect(_emit.bind(str(primary.get("action", "operation_continue")), primary.get("arg")))
	if not secondary.is_empty():
		var b2 := K.button(root, str(secondary.get("label", "")), 1518, cy, {"w": 281, "h": 44})
		b2.disabled = secondary.get("disabled", false)
		b2.pressed.connect(_emit.bind(str(secondary.get("action", "operation_restart")), secondary.get("arg")))
	return h


## 130px banner: dark ground gradient, 48px grid, sprites, a fade into the card body, and the tag row.
func _card_header(root: Control, f: Dictionary, y: float) -> void:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(clip, 1205, y, 614, 130)
	root.add_child(clip)
	Fx.radial(clip, Rect2(0, 0, 614, 130), Vector2(0.3 * 614.0, 1.1 * 130.0), Vector2(0.7 * 614.0 * 1.4142, 1.1 * 130.0 * 1.4142), [[Color("3b3d30"), 0.0], [Color("30332a"), 0.55], [Color("23251e"), 1.0]])
	var grid := _Grid.new()
	grid.size = Vector2(614, 130)
	clip.add_child(grid)
	for art in f.get("art", []):
		K.sprite(clip, str(art.get("sprite", "")), float(art.get("x", 0)), float(art.get("y", 0)), float(art.get("s", 120)), float(art.get("s", 120)))
	Fx.linear(clip, Rect2(0, 0, 614, 130), [[Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.0), 0.4], [Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.92), 1.0]])
	var x := 16.0
	for tag in f.get("tags", []):
		var t := K.tag(clip, str(tag.get("t", "")), x, 14, T.tone(str(tag.get("tone", "dim"))), Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.7))
		x += t.size.x + 8.0


class _Grid extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col := Color(176.0 / 255.0, 190.0 / 255.0, 154.0 / 255.0, 0.08)
		for gx in range(0, int(size.x) + 1, 48):
			draw_rect(Rect2(gx, 0, 1, size.y), col)
		for gy in range(0, int(size.y) + 1, 48):
			draw_rect(Rect2(0, gy, size.x, 1), col)


## Later chapters: two columns, rows stretch between 160 and 187.8 px to fill the panel; more rows scroll.
func _chapter_grid(root: Control, chapters: Array, top: float) -> void:
	if chapters.is_empty():
		return
	var rows := int(ceil(chapters.size() / 2.0))
	var avail := maxf(GRID_BOTTOM - top, CARD_MIN_H)
	var fit := (avail - 12.0 * (rows - 1)) / rows
	var scrolls := fit < CARD_MIN_H
	var row_h := clampf(fit, CARD_MIN_H, CARD_MAX_H)
	var host: Control = root
	var origin := Vector2(1205, top)
	var col_w := 301.0
	var content_w := 614.0
	if scrolls:
		var scroll := ScrollContainer.new()
		scroll.name = "chapters_scroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		K.place(scroll, 1205, top, 614, avail)
		root.add_child(scroll)
		var inner := Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_PASS
		content_w = 600.0
		col_w = (content_w - 12.0) / 2.0
		inner.custom_minimum_size = Vector2(content_w, rows * row_h + 12.0 * (rows - 1))
		scroll.add_child(inner)
		host = inner
		origin = Vector2.ZERO
	for i in chapters.size():
		var c: Dictionary = chapters[i]
		var cx := origin.x + (i % 2) * (col_w + 12.0)
		var cy := origin.y + (i / 2) * (row_h + 12.0)
		K.panel(host, cx, cy, col_w, row_h, "glass", {"border": T.LINE, "dashed": true, "fill": Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.7), "light": false})
		K.tag(host, str(c.get("tag", "")), cx + 17.0, cy + 15.0, Color(str(c.get("tag_color", "8fb0bf"))))
		K.icon(host, "lock", cx + col_w - 37.0, cy + 16.0, T.DIM, 20)
		var cname_o := {"f": "disp", "wt": 600, "px": 26, "sp": 0.04, "up": true}
		K.text(host, TextBoxProbe.clip(str(c.get("name", "")), cname_o, col_w - 34.0, 1), {"x": cx + 17.0, "y": cy + 43.0, "w": col_w - 34.0, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "col": T.TEXT, "up": true, "wrap": true})
		K.text(host, TextBoxProbe.clip(str(c.get("blurb", "")), {"px": 14, "lh": 19.6}, col_w - 34.0, 2), {"x": cx + 17.0, "y": cy + 82.0, "w": col_w - 34.0, "px": 14, "lh": 19.6, "col": T.DIM, "wrap": true})
		if str(c.get("status", "")) != "":
			K.tag(host, str(c["status"]), cx + 17.0, cy + row_h - 37.0, T.DIM)


# ---------------------------------------------------------------- footer

func _build_footer(root: Control, vm: Dictionary) -> void:
	var left := str(vm.get("left", ""))
	var right := str(vm.get("right", ""))
	if left != "":
		K.text(root, left, {"x": 120, "y": 1035, "f": "mono", "px": 13, "sp": 0.04, "col": T.DIM})
	if right != "":
		var r := K.text(root, right, {"x": 0, "y": 1035, "f": "mono", "px": 13, "sp": 0.04, "col": T.DIM})
		r.position.x = roundf(1844.0 - r.size.x)


## Wrapped-text probes that never touch the tree (used to size the featured card and to clip long strings).
class TextBoxProbe:
	const TextBox = preload("res://scripts/ui/components/text_box.gd")

	static func _probe(s: String, o: Dictionary, width: float) -> TextBox:
		var probe := TextBox.new()
		probe.size = Vector2(width, 0)
		var opts := o.duplicate()
		opts["wrap"] = true
		probe.configure(s, opts)
		return probe

	static func measure_wrapped(s: String, o: Dictionary, width: float) -> float:
		if s == "":
			return 0.0
		var probe := _probe(s, o, width)
		var h := probe.get_minimum_size().y
		probe.free()
		return h

	static func line_count(s: String, o: Dictionary, width: float) -> int:
		if s == "":
			return 0
		var probe := _probe(s, o, width)
		var n := probe.lines().size()
		probe.free()
		return n

	## `s` cut with "..." so that it wraps to at most `max_lines` lines at `width`.
	static func clip(s: String, o: Dictionary, width: float, max_lines: int) -> String:
		if line_count(s, o, width) <= max_lines:
			return s
		var lo := 0
		var hi := s.length()
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if line_count(s.substr(0, mid).strip_edges(false, true) + "...", o, width) <= max_lines:
				lo = mid
			else:
				hi = mid - 1
		return s.substr(0, lo).strip_edges(false, true) + "..."
