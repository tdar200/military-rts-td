extends Control
## Research graph screen, built from a plain view model. Never reads game state; emits `action` for every click.
## Geometry is the Research mock at 1920x1080 (docs/ascension/ui-mocks/Research.dc.html, tools/ui/box.py).
##
## View model (every key optional; a block whose data is missing is left out, never invented):
##   header  {title, crumbs: [{label, on}], close_label, chips: [{text, icon?, icon_tone?, tone?, border?}]}
##   gate    {label, from: {n, name}, to: {n, name}, criteria: [{state: done|active|todo, label, value, tone?}], note}
##   filters {search: {placeholder, text}, groups: [{id, title, row_h?, rows: [{id, label, on, icon?, tone?, count?}]}],
##            honesty: {title, tags: [{label, tone, dashed?}]}}
##   upgrades {title, rows: [{id, label, level, tone?, button: {label, action, arg, disabled?}}]}  (Kestrel, Task 17)
##   graph   {nodes: [node], selected: id, highlight: [ids], horizon: {...}, hint: {...}, empty: {title, body},
##            click_to_start: bool}
##   zoom    {value: 0..1, scale: 0.5..1.5, hint}
##   eras    {title, note, items: [{n, name, state: current|next|locked, progress?}]}
##   detail  {title, state: {label, tone}, tags: [{label, tone, dashed?}], boxes: [{label, value, tone?, ratio?}],
##            bottleneck: {title, text, tone?}, path: {title, note, steps: [{n, kind, label, tag?, tone?}]},
##            retrofit: {title, cells: [{label, value, tone?}]}, effect: {title, text}, honesty, empty,
##            primary: {label, action, arg?, icon?, disabled?}, secondary: {label, action, arg?, disabled?}}
## node = {id, name, state: implemented|active|available|blocked|planned|unknown, tags: [{label, tone, dashed?}],
##         segments: [ratio, ratio, ratio], footer: {text, tone}, note, step, prereqs: [ids], col?, row?, dim?}
##
## Actions: select(id), research(id) [from the detail buttons or click_to_start], close, crumb(index), zoom(+1|-1),
## zoom_to(value), filter({group, id, on}), search(text), plus whatever `action` names the detail buttons carry.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const Tag = preload("res://scripts/ui/components/tag.gd")
const Layout = preload("res://scripts/ui/research_layout.gd")
const Parts = preload("res://scripts/ui/components/research_parts.gd")

signal action(name: String, arg: Variant)

const SECTIONS := [
	["header", "_build_header"],
	["gate", "_build_gate"],
	["filters", "_build_filters"],
	["upgrades", "_build_upgrades"],
	["graph", "_build_graph"],
	["zoom", "_build_zoom"],
	["eras", "_build_eras"],
	["detail", "_build_detail"],
]
const VIEW := Rect2(313, 185, 1078, 734)
const STATE_ICON := {"implemented": "circle_check", "active": "circle_clock", "available": "circle_plus", "blocked": "lock", "planned": "flag", "unknown": "circle_help"}

var _layers: Dictionary = {}
var _hashes: Dictionary = {}
var _meter: TextBox = TextBox.new()
var _pan := Vector2.ZERO
var _scale := 1.0
var _world: Control = null
var _extent := Vector2.ZERO
var _detail_body: Control = null
var _detail_scroll := 0.0
var _detail_overflow := 0.0
var _card_by_id: Dictionary = {}
var _click_to_start := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1920, 1080)
	size = Vector2(1920, 1080)
	_build_backdrop()


## The measuring box is never in the tree, so it is freed with the screen itself (not on _exit_tree, which a screen that is
## freed outside the tree, or only re-parented, would get wrong).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_meter):
		_meter.free()


## True when `point` (in this control's space) is over the screen. The screen is a modal overlay.
func blocks_point(point: Vector2) -> bool:
	return visible and Rect2(Vector2.ZERO, size).has_point(point)


func apply(vm: Dictionary) -> void:
	for entry in SECTIONS:
		var key: String = entry[0]
		var slice: Variant = vm.get(key, null)
		var h := hash(slice)
		if _hashes.get(key, -1) == h and _layers.has(key):
			continue
		_hashes[key] = h
		_rebuild(key, entry[1], slice)


func _rebuild(key: String, builder: String, slice: Variant) -> void:
	var old: Control = _layers.get(key)
	var typing := false  # the search field is rebuilt on every keystroke; keep the caret where it was
	var caret := 0
	if old:
		var old_edit := _first_line_edit(old)
		if old_edit != null and old_edit.has_focus():
			typing = true
			caret = old_edit.caret_column
		remove_child(old)
		old.queue_free()
	var layer := Control.new()
	layer.name = key
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	_layers[key] = layer
	if slice == null or not slice is Dictionary:
		return
	call(builder, layer, slice)
	if typing:
		var edit := _first_line_edit(layer)
		if edit != null:
			edit.grab_focus()
			edit.caret_column = caret


func _first_line_edit(layer: Node) -> LineEdit:
	var found := layer.find_children("*", "LineEdit", true, false)
	return found[0] if not found.is_empty() else null


func _emit(name: String, arg: Variant = null) -> void:
	action.emit(name, arg)


# ---------------------------------------------------------------- helpers

func _col(v: Variant, fallback: Color = T.TEXT) -> Color:
	if v is Color:
		return v
	var s := str(v)
	if s.begins_with("#"):
		return Color(s)
	if s == "blue":
		return T.SHIELD
	if s == "":
		return fallback
	return T.tone(s)


## Width of `s` set in the given text style (mono / body / disp, px, spacing em).
func _w(s: String, o := {}) -> float:
	var style := {"f": "body", "wt": 0, "px": 14, "sp": 0.0, "up": false}
	style.merge(o, true)
	_meter.configure("", style)
	return _meter.measure(s)


## Longest prefix of `s` that fits `max_w`, with "..." when cut.
func _fit(s: String, max_w: float, o := {}) -> String:
	if _w(s, o) <= max_w + 0.6:
		return s
	var n := s.length()
	while n > 1 and _w(s.substr(0, n) + "...", o) > max_w:
		n -= 1
	return s.substr(0, n).strip_edges(false, true) + "..."


func _ground(parent: Node, rect: Rect2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = rect.position
	r.size = rect.size
	parent.add_child(r)
	return r


func _box(parent: Node, rect: Rect2, fill: Color, border: Color, dashed := false, radius := 0, width := 1.0) -> Control:
	var b := Parts.Box.new()
	b.position = rect.position
	b.size = rect.size
	parent.add_child(b)
	b.setup(fill, border, dashed, radius, width)
	return b


func _tag(parent: Node, label: String, color: Color, x: float, y: float, o := {}) -> Control:
	var t := Tag.new()
	parent.add_child(t)
	t.setup(label, color, Color(0, 0, 0, 0), o)
	t.position = Vector2(roundf(x), roundf(y))
	return t


func _cap(parent: Node, s: String, x: float, y: float, color: Color = T.DIM, o := {}) -> Control:
	var d := {"x": x, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": color, "up": true}
	d.merge(o, true)
	return K.text(parent, s, d)


# ---------------------------------------------------------------- backdrop

func _build_backdrop() -> void:
	var layer := Control.new()
	layer.name = "backdrop"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = Vector2(1920, 1080)
	add_child(layer)
	_ground(layer, Rect2(0, 0, 1920, 1080), T.BG1)
	Parts.radial(layer, Rect2(-40, 10, 1680, 980), Vector2(840, 490), Vector2(1200, 700), Color("0b1a26"), T.BG1, 0.7)
	var scan := TextureRect.new()
	var img := Image.create(1, 4, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 3, Color(120.0 / 255.0, 245.0 / 255.0, 1.0, 0.035))
	scan.texture = ImageTexture.create_from_image(img)
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.size = Vector2(1920, 1080)
	layer.add_child(scan)


# ---------------------------------------------------------------- header

func _build_header(root: Control, vm: Dictionary) -> void:
	_ground(root, Rect2(0, 0, 1920, 64), Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.9))
	_ground(root, Rect2(0, 63, 1920, 1), T.LINE)
	var title := K.text(root, str(vm.get("title", "")), {"x": 20, "y": 11, "f": "disp", "wt": 600, "px": 32, "sp": 0.14, "col": T.TEXT_HI, "up": true})
	var x: float = 20.0 + title.size.x + 20.0
	K.rule(root, x, 16.5, 1, 30, T.LINE)
	x += 1.0 + 20.0
	var crumbs: Array = vm.get("crumbs", [])
	for i in crumbs.size():
		var c: Dictionary = crumbs[i]
		var on: bool = c.get("on", false)
		var label := str(c.get("label", ""))
		var cw := _w(label.to_upper(), {"f": "mono", "px": 12, "sp": 0.12}) + 24.0 + 2.0
		_box(root, Rect2(roundf(x), 17, roundf(cw), 29), T.ACTIVE if on else Color(0, 0, 0, 0), T.CYAN if on else T.LINE_DIM)
		_cap(root, label, x + 13.0, 24.0, T.TEXT_HI if on else T.DIM)
		var hit := K.hit(root, x, 17, cw, 29, label)
		hit.pressed.connect(_emit.bind("crumb", i))
		x += cw
		if i < crumbs.size() - 1:
			x += 8.0
			K.text(root, ">", {"x": x, "y": 21.5, "f": "mono", "px": 16, "col": T.FAINT})
			x += 9.6 + 8.0
	x += 20.0
	var close_label := str(vm.get("close_label", ""))
	if close_label != "":
		var cl := _cap(root, close_label, x, 24.0, T.FAINT)
		var close := K.hit(root, x - 6, 17, cl.size.x + 12, 29, "Close")
		close.pressed.connect(_emit.bind("close", null))
	# Chips are right-aligned: 20px gap, 20px page padding.
	var chips: Array = vm.get("chips", [])
	var right := 1900.0
	for i in range(chips.size() - 1, -1, -1):
		var chip: Dictionary = chips[i]
		var icon_name := str(chip.get("icon", ""))
		var o := {"h": 28, "icon_px": 20}
		if chip.has("border"):
			o["border"] = _col(chip["border"])
		var c := K.chip(root, 0, 17.5, icon_name, _col(chip.get("icon_tone", "cyan")), [{"t": str(chip.get("text", "")), "col": _col(chip.get("tone", "text"))}], o)
		right -= c.size.x
		c.position.x = roundf(right)
		right -= 20.0


# ---------------------------------------------------------------- era gate strip

func _build_gate(root: Control, vm: Dictionary) -> void:
	K.panel(root, 16, 72, 1888, 96)
	var x := 37.0
	var from: Dictionary = vm.get("from", {})
	var to: Dictionary = vm.get("to", {})
	var left_w := 0.0
	if vm.has("label") or not from.is_empty() or not to.is_empty():
		_cap(root, str(vm.get("label", "")), x, 95.5, T.CYAN_HI)
		var cx := x
		if not from.is_empty():
			var c1 := K.chip(root, cx, 116.5, "", T.CYAN, [
				{"t": "Era %s" % str(from.get("n", "")), "f": "disp", "px": 16, "wt": 600, "sp": 0.04, "col": T.TEXT_HI, "up": true},
				{"t": str(from.get("name", ""))},
			], {"border": T.DIM})
			cx += c1.size.x + 10.0
		if not from.is_empty() and not to.is_empty():
			var arrow := Parts.GateArrow.new()
			K.place(arrow, cx, 120.5)
			root.add_child(arrow)
			cx += 34.0 + 10.0
		if not to.is_empty():
			var c2 := K.chip(root, cx, 116.5, "lock", T.CYAN, [
				{"t": "Era %s" % str(to.get("n", "")), "f": "disp", "px": 16, "wt": 600, "sp": 0.04, "col": T.TEXT_HI, "up": true},
				{"t": str(to.get("name", ""))},
			], {"border": T.CYAN, "dashed": true, "icon_px": 16})
			cx += c2.size.x
		left_w = maxf(cx - x, _w(str(vm.get("label", "")).to_upper(), {"f": "mono", "px": 12, "sp": 0.12}))
		x += left_w + 26.0
		K.rule(root, x, 90, 1, 60, T.LINE_DIM)
		x += 1.0 + 26.0
	var criteria: Array = vm.get("criteria", [])
	if not criteria.is_empty():
		for i in criteria.size():
			var item: Dictionary = criteria[i]
			var ix := x + (i % 2) * 394.0
			var iy := 88.0 + (i / 2) * 36.0
			var state := str(item.get("state", "todo"))
			var icon_name := "circle_check" if state == "done" else ("circle_clock" if state == "active" else "circle_dashed_lg")
			var icon_col: Color = T.GOOD if state == "done" else (T.CYAN if state == "active" else T.DIM)
			K.icon(root, icon_name, ix, iy + 4.0, icon_col, 20)
			var value_col := _col(item.get("tone", ""), T.DIM)
			var value := K.text(root, str(item.get("value", "")), {"x": 0, "y": iy + 5.5, "f": "mono", "px": 13, "col": value_col})
			value.position.x = roundf(ix + 366.0 - value.size.x)
			K.text(root, _fit(str(item.get("label", "")), 366.0 - 30.0 - value.size.x - 10.0, {"px": 14}), {"x": ix + 30.0, "y": iy + 5.0, "px": 14, "col": T.TEXT})
		x += 760.0 + 26.0
		K.rule(root, x, 90, 1, 60, T.LINE_DIM)
		x += 1.0 + 26.0
	var note := str(vm.get("note", ""))
	if note != "":
		var width := 1904.0 - 1.0 - 20.0 - x
		var para := K.text(root, note, {"x": x, "y": 0, "w": width, "px": 14, "lh": 20.3, "col": T.DIM, "wrap": true})
		para.position.y = roundf(73.0 + (94.0 - para.size.y) * 0.5)


# ---------------------------------------------------------------- filter rail

func _build_filters(root: Control, vm: Dictionary) -> void:
	K.panel(root, 16, 184, 280, 880)
	var y := 201.0
	var search: Dictionary = vm.get("search", {})
	var field := K.panel(root, 33, y, 246, 38, "glass")
	K.icon(root, "search", 46, y + 9.0, T.DIM, 20)
	var edit := LineEdit.new()
	edit.flat = true
	edit.placeholder_text = str(search.get("placeholder", "Search projects"))
	edit.text = str(search.get("text", ""))
	edit.focus_mode = Control.FOCUS_CLICK
	for state in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var body := T.font("body")
	edit.add_theme_font_override("font", body)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_color_override("font_color", T.TEXT)
	edit.add_theme_color_override("font_placeholder_color", T.DIM)
	edit.add_theme_color_override("caret_color", T.CYAN_HI)
	K.place(edit, 76, y + 1.0, 195, 36)
	root.add_child(edit)
	edit.text_changed.connect(func(text: String) -> void: _emit("search", text))  # bind() would append, not prepend, the name
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	y += 38.0 + 12.0
	var groups: Array = vm.get("groups", [])
	for gi in groups.size():
		var group: Dictionary = groups[gi]
		if gi > 0:
			K.rule(root, 33, y, 246, 1, T.LINE_DIM)
			y += 1.0 + 12.0
		_cap(root, str(group.get("title", "")), 33, y, T.CYAN_HI)
		y += 15.0 + 12.0
		var row_h: float = float(group.get("row_h", 30.0))
		for row in group.get("rows", []):
			_filter_row(root, group, row, y, row_h)
			y += row_h
		y += 12.0
	var honesty: Dictionary = vm.get("honesty", {})
	var tags: Array = honesty.get("tags", [])
	if not tags.is_empty():
		if not groups.is_empty():
			K.rule(root, 33, y, 246, 1, T.LINE_DIM)
			y += 1.0 + 12.0
		_cap(root, str(honesty.get("title", "")), 33, y, T.CYAN_HI)
		y += 15.0 + 12.0
		for t in tags:
			_tag(root, str(t.get("label", "")), _col(t.get("tone", "dim")), 33, y, {"dashed": t.get("dashed", false)})
			y += 22.0 + 7.0


func _filter_row(root: Control, group: Dictionary, row: Dictionary, y: float, row_h: float) -> void:
	var on: bool = row.get("on", true)
	var label := str(row.get("label", ""))
	var hover := Parts.Box.new()
	hover.position = Vector2(33, y)
	hover.size = Vector2(246, row_h)
	root.add_child(hover)
	hover.setup(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	var check := Parts.Check.new()
	K.place(check, 33, y + (row_h - 18.0) * 0.5)
	root.add_child(check)
	check.setup(on)
	var x := 33.0 + 18.0 + 10.0
	if row.has("icon"):
		K.icon(root, str(row["icon"]), x, y + (row_h - 20.0) * 0.5, _col(row.get("tone", "dim")), 20)
		x += 20.0 + 10.0
	var lh := 18.0
	var count_w := 0.0
	var count_text := str(row.get("count", ""))
	if count_text != "":
		var count := K.text(root, count_text, {"x": 0, "y": y + (row_h - 17.0) * 0.5, "f": "mono", "px": 13, "col": T.DIM})
		count.position.x = roundf(279.0 - count.size.x)
		count_w = count.size.x + 8.0
	K.text(root, _fit(label, 279.0 - x - count_w, {"px": 14}), {"x": x, "y": y + (row_h - lh) * 0.5, "px": 14, "col": T.TEXT if on else T.DIM})
	var hit := K.hit(root, 33, y, 246, row_h, label)
	hit.pressed.connect(_emit.bind("filter", {"group": group.get("id", ""), "id": row.get("id", label), "on": not on}))
	hit.mouse_entered.connect(hover.setup.bind(Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.07), Color(0, 0, 0, 0)))
	hit.mouse_exited.connect(hover.setup.bind(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))


## Task 17: the Upgrades section sits at the foot of the filter panel (its rows end near y 702 with every branch
## listed), inside the panel's 16,184 280x880 rect: a rule, the caption and a row per track (name, level, buy button).
const UPGRADES_TOP := 812.0
const UPGRADE_ROW_H := 66.0


func _build_upgrades(root: Control, vm: Dictionary) -> void:
	var y := UPGRADES_TOP
	K.rule(root, 33, y, 246, 1, T.LINE_DIM)
	y += 1.0 + 12.0
	_cap(root, str(vm.get("title", "Upgrades")), 33, y, T.CYAN_HI)
	y += 15.0 + 12.0
	for row in vm.get("rows", []):
		var tone := _col(row.get("tone", "text"), T.TEXT)
		K.text(root, str(row.get("label", "")), {"x": 33, "y": y, "px": 14, "col": T.TEXT})
		var level := K.text(root, str(row.get("level", "")), {"x": 0, "y": y + 1.0, "f": "mono", "px": 13, "col": tone if tone != T.TEXT else T.DIM})
		level.position.x = roundf(279.0 - level.size.x)
		var spec: Dictionary = row.get("button", {})
		var btn := K.button(root, str(spec.get("label", "")), 33, y + 22.0, {"min_h": 34, "w": 246.0, "h": 34.0, "px": 14, "pad": 12})
		btn.disabled = bool(spec.get("disabled", false))
		btn.pressed.connect(_emit.bind(str(spec.get("action", "upgrade")), spec.get("arg")))
		y += UPGRADE_ROW_H


# ---------------------------------------------------------------- graph

func _build_graph(root: Control, vm: Dictionary) -> void:
	_card_by_id.clear()
	_click_to_start = bool(vm.get("click_to_start", false))
	_ground(root, VIEW, Color("060b12"))
	Parts.radial(root, VIEW, Vector2(560, 360), Vector2(700, 400), Color(24.0 / 255.0, 90.0 / 255.0, 110.0 / 255.0, 0.16), Color(6.0 / 255.0, 9.0 / 255.0, 16.0 / 255.0, 0.9), 0.75)
	var dots := TextureRect.new()
	var tile := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var dot := Color(143.0 / 255.0, 176.0 / 255.0, 191.0 / 255.0, 0.16)
	for dy in 2:
		for dx in 2:
			tile.set_pixel(11 + dx, 11 + dy, dot)
	dots.texture = ImageTexture.create_from_image(tile)
	dots.stretch_mode = TextureRect.STRETCH_TILE
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(dots, VIEW.position.x, VIEW.position.y, VIEW.size.x, VIEW.size.y)
	root.add_child(dots)
	K.panel(root, 312, 184, 1080, 736, "panel", {"fill": Color(0, 0, 0, 0)})
	var pane := Parts.Pane.new()
	K.place(pane, VIEW.position.x, VIEW.position.y, VIEW.size.x, VIEW.size.y)
	root.add_child(pane)
	pane.panned.connect(_on_pan)
	pane.wheel.connect(_on_wheel)
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(_world)
	var nodes: Array = vm.get("nodes", [])
	var lay := Layout.layout(nodes)
	var cells: Dictionary = lay["cells"]
	var keys: Array = lay["keys"]
	var selected := str(vm.get("selected", ""))
	var highlight: Array = []
	for h in vm.get("highlight", []):
		highlight.append(str(h))
	# Edges
	var edge_layer := Parts.EdgeLayer.new()
	edge_layer.size = Vector2(2000, 2000)
	_world.add_child(edge_layer)
	var node_by_key: Dictionary = {}
	for i in nodes.size():
		node_by_key[keys[i]] = nodes[i]
	var edges: Array = []
	for pair in lay["edges"]:
		var target: Dictionary = node_by_key[pair[1]]
		var kind := "normal"
		var hi_a := highlight.find(pair[0])
		var hi_b := highlight.find(pair[1])
		if hi_a >= 0 and hi_b == hi_a + 1:
			kind = "path"
		elif str(target.get("state", "")) == "unknown":
			kind = "unknown"
		edges.append({"points": Layout.edge_points(Layout.edge(cells[pair[0]], cells[pair[1]])), "kind": kind})
	edge_layer.setup(edges)
	# Extra blocks that sit in the graph space
	var extent := Layout.world_size(lay["cols"], lay["rows"])
	var horizon: Dictionary = vm.get("horizon", {})
	var hint: Dictionary = vm.get("hint", {})
	var next_col: int = lay["cols"]
	var h_cell := Vector2i(int(horizon.get("col", next_col)), int(horizon.get("row", 0)))
	var hy := 0.0
	if not horizon.is_empty():
		var hp := Layout.node_pos(h_cell)
		hy = _build_horizon(_world, hp, horizon)
		extent = extent.max(Vector2(hp.x + Layout.NODE_W + 4.0, hp.y + hy + 12.0))
	if not hint.is_empty():
		var default_cell := Vector2i(h_cell.x, 4)
		var cell := Vector2i(int(hint.get("col", default_cell.x)), int(hint.get("row", default_cell.y)))
		var pos := Layout.node_pos(cell)
		if hint.has("y"):
			pos.y = float(hint["y"])
		elif not hint.has("row"):
			pos.y = 600.0
		var bottom := _build_hint(_world, pos, hint)
		extent = extent.max(Vector2(pos.x + Layout.NODE_W + 4.0, bottom + 12.0))
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var key: String = keys[i]
		_build_card(_world, node, cells[key], key == selected or str(node.get("id", "")) == selected and selected != "")
	if nodes.is_empty():
		_build_empty(root, vm.get("empty", {}))
	_extent = extent
	_apply_pan()


func _build_empty(root: Control, e: Dictionary) -> void:
	var box := _box(root, Rect2(VIEW.position.x + 339.0, VIEW.position.y + 292.0, 400, 150), Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.7), T.LINE_DIM, true, 3)
	K.icon(box, "flask", 24, 22, T.DIM, 24)
	K.text(box, str(e.get("title", "No projects to show")), {"x": 60, "y": 22, "w": 316, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "col": T.TEXT, "up": true})
	K.text(box, str(e.get("body", "Nothing matches the current filters, or no research is available yet.")), {"x": 24, "y": 62, "w": 352, "px": 14, "lh": 20.3, "col": T.DIM, "wrap": true})


func _build_horizon(world: Control, pos: Vector2, h: Dictionary) -> float:
	var height: float = float(h.get("h", 280.0))
	var card := _box(world, Rect2(pos, Vector2(Layout.NODE_W, height)), Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.5), T.LINE, true, 3)
	var y := 15.0
	K.icon(card, str(h.get("icon", "lock")), 15, y, T.DIM, 20)
	_cap(card, str(h.get("cap", "Horizon")), 43, y + 2.5, T.DIM)
	y += 20.0 + 10.0
	var title := K.text(card, str(h.get("title", "")), {"x": 15, "y": y, "w": 202, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "lh": 25.2, "col": T.TEXT, "up": true, "wrap": true})
	y += title.size.y + 10.0
	var body := K.text(card, str(h.get("body", "")), {"x": 15, "y": y, "w": 202, "px": 14, "lh": 20.3, "col": T.DIM, "wrap": true})
	y += body.size.y + 10.0
	var tag: Dictionary = h.get("tag", {})
	if not tag.is_empty():
		var t := _tag(card, str(tag.get("label", "")), _col(tag.get("tone", "dim")), 15, y)
		y += t.size.y
	return height


func _build_hint(world: Control, pos: Vector2, h: Dictionary) -> float:
	var title := str(h.get("title", ""))
	var card := _box(world, Rect2(pos, Vector2(Layout.NODE_W, 60)), Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.7), T.LINE_DIM, false, 3)
	var y := 13.0
	if title != "":
		_cap(card, title, 13, y, T.CYAN_HI, {"lh": 17.4})
		y += 17.4 + 6.0
	var body := K.text(card, str(h.get("body", "")), {"x": 13, "y": y, "w": 206, "px": 13, "lh": 18.85, "col": T.DIM, "wrap": true})
	card.size.y = roundf(y + body.size.y + 13.0)
	return pos.y + card.size.y


func _build_card(world: Control, node: Dictionary, cell: Vector2i, selected: bool) -> void:
	var name_text := str(node.get("name", node.get("id", "")))
	var state := str(node.get("state", "available"))
	if not STATE_ICON.has(state):
		state = "available"
	var bw := 2 if state in ["active", "blocked", "unknown"] else 1
	var c := float(bw + 10)
	var rect := Layout.node_rect(cell)
	var card := Parts.Card.new()
	card.position = rect.position
	card.size = rect.size
	world.add_child(card)
	card.setup(state, bw, selected)
	if node.get("dim", false):
		card.modulate.a = 0.38
	var inner := Layout.NODE_W - 2.0 * c
	var nh_h := 24.0 if bw == 1 else 22.0
	var icon_col: Color = T.CYAN_HI if selected else _state_color(state)
	K.icon(card, STATE_ICON[state], c, c + (nh_h - 20.0) * 0.5, icon_col, 20)
	var title_col: Color = T.TEXT_HI
	if state == "unknown":
		title_col = Color("e4daff")
	var title_o := {"f": "disp", "wt": 600, "px": 17, "sp": 0.01}
	K.text(card, _fit(name_text, inner - 28.0, title_o), {"x": c + 28.0, "y": c + (nh_h - 22.0) * 0.5, "f": "disp", "wt": 600, "px": 17, "sp": 0.01, "col": title_col})
	var y := c + nh_h + 6.0
	var tags: Array = node.get("tags", [])
	if not tags.is_empty():
		var left: Dictionary = tags[0]
		var lt := _tag(card, _fit(str(left.get("label", "")), inner - 8.0, {"f": "mono", "px": 12, "sp": 0.03}), _col(left.get("tone", "dim")), c, y, {"pad": 6, "sp": 0.03, "dashed": left.get("dashed", false)})
		if tags.size() > 1:
			var right: Dictionary = tags[1]
			var room := inner - lt.size.x - 6.0
			var rt := _tag(card, _fit(str(right.get("label", "")), room - 14.0, {"f": "mono", "px": 12, "sp": 0.03}), _col(right.get("tone", "dim")), 0, y, {"pad": 6, "sp": 0.03, "dashed": right.get("dashed", false)})
			rt.position.x = roundf(Layout.NODE_W - c - rt.size.x)
	y += 22.0 + 6.0
	var note := str(node.get("note", ""))
	var footer: Dictionary = node.get("footer", {})
	var footer_y := 0.0
	if note != "":
		var para := K.text(card, note, {"x": c, "y": y + 2.0, "w": inner, "px": 13, "lh": 18.2, "col": Color("cfc3f2"), "wrap": true})
		footer_y = maxf(y + 2.0 + para.size.y + 6.0, Layout.NODE_H - c - 17.0)
	else:
		var cells: Array = []
		var segments: Array = node.get("segments", [])
		var seg_col: Color = T.GOOD if state == "implemented" else T.CYAN
		for i in 3:
			var ratio := clampf(float(segments[i]) if i < segments.size() else 0.0, 0.0, 1.0)
			cells.append({"ratio": ratio, "col": seg_col})
		var seg_y := y + 2.0
		card.set_cells(cells, c, seg_y, inner, state == "planned")
		var labels: Array = node.get("labels", ["Theory", "Prototype", "Deploy"])
		var texts: Array = []
		for i in 3:
			var s := str(labels[i]) if i < labels.size() else ""
			var ratio: float = cells[i]["ratio"]
			if ratio > 0.0 and ratio < 1.0:
				s += " %d%%" % roundi(ratio * 100.0)
			texts.append(s)
		var ws: Array = []
		var total := 0.0
		for s in texts:
			var wv := _w(s, {"f": "mono", "px": 12, "sp": 0.02})
			ws.append(wv)
			total += wv
		var gap := (inner - total) * 0.5
		var lx := c
		var ly := seg_y + 8.0 + 6.0
		for i in 3:
			K.text(card, texts[i], {"x": lx, "y": ly, "f": "mono", "px": 12, "sp": 0.02, "col": T.DIM})
			lx += ws[i] + gap
		footer_y = ly + 15.0 + 6.0
	if not footer.is_empty() and str(footer.get("text", "")) != "":
		var fo := {"px": 13}
		K.text(card, _fit(str(footer.get("text", "")), inner, fo), {"x": c, "y": footer_y, "px": 13, "col": _col(footer.get("tone", ""), T.DIM)})
	var step := int(node.get("step", 0))
	if step > 0:
		var badge := Parts.Badge.new()
		K.place(badge, Layout.NODE_W - bw + 10.0 - 26.0, float(bw) - 10.0)
		card.add_child(badge)
		K.text(badge, str(step), {"x": 0, "y": 2, "w": 26, "f": "disp", "wt": 700, "px": 17, "col": Color("03181d"), "al": "c"})
	var hit := K.hit(card, 0, 0, Layout.NODE_W, Layout.NODE_H, name_text)
	var id: Variant = node.get("id", name_text)
	hit.pressed.connect(_on_card.bind(id, state))
	hit.mouse_entered.connect(card.set_hover.bind(true))
	hit.mouse_exited.connect(card.set_hover.bind(false))
	_card_by_id[str(id)] = card


func _state_color(state: String) -> Color:
	match state:
		"implemented": return T.GOOD
		"active", "available": return T.CYAN
		"blocked": return T.WARN
		"unknown": return T.VIOLET
	return T.DIM


func _on_card(id: Variant, state: String) -> void:
	_emit("select", id)
	if _click_to_start and state == "available":
		_emit("research", id)


## Scroll the graph so card `id` is centred (clamped). The host calls this after a selection it wants in view.
func focus_node(id: Variant) -> void:
	var card: Control = _card_by_id.get(str(id))
	if card == null:
		return
	_pan = (card.position + card.size * 0.5) * _scale - VIEW.size * 0.5
	_apply_pan()


func _on_pan(delta: Vector2) -> void:
	_pan -= delta
	_apply_pan()


func _on_wheel(direction: int, shift: bool) -> void:
	if shift:
		_pan.x -= direction * 120.0
		_apply_pan()
	else:
		_emit("zoom", direction)


func _apply_pan() -> void:
	if _world == null:
		return
	var room := (_extent * _scale - VIEW.size).max(Vector2.ZERO)
	_pan = _pan.clamp(Vector2.ZERO, room)
	_world.scale = Vector2(_scale, _scale)
	_world.position = -_pan


## Where the graph is currently scrolled (graph pixels), for tests and the host.
func pan() -> Vector2:
	return _pan


# ---------------------------------------------------------------- zoom and era band

func _build_zoom(root: Control, vm: Dictionary) -> void:
	_scale = clampf(float(vm.get("scale", 1.0)), 0.25, 2.0)
	_apply_pan()
	K.panel(root, 312, 936, 1080, 128)
	_cap(root, "Zoom", 329, 949, T.CYAN_HI)
	var minus := K.button(root, "-", 329, 974, {"min_h": 36, "pad": 12, "px": 20})
	minus.text = "Zoom out"
	minus.pressed.connect(_emit.bind("zoom", -1))
	var plus := K.button(root, "+", 0, 974, {"min_h": 36, "pad": 12, "px": 20})
	plus.text = "Zoom in"
	plus.position.x = roundf(329.0 + 196.0 - plus.size.x)
	plus.pressed.connect(_emit.bind("zoom", 1))
	var track := Parts.ZoomTrack.new()
	var tx := 329.0 + minus.size.x + 8.0
	K.place(track, tx, 974, plus.position.x - 8.0 - tx, 36)
	root.add_child(track)
	track.setup(float(vm.get("value", 0.0)))
	track.changed.connect(func(value: float) -> void: _emit("zoom_to", value))
	var hint := str(vm.get("hint", ""))
	if hint != "":
		K.text(root, hint, {"x": 329, "y": 1020, "w": 196, "f": "mono", "px": 12, "col": T.DIM, "wrap": true})


func _build_eras(root: Control, vm: Dictionary) -> void:
	var items: Array = vm.get("items", [])
	if items.is_empty():
		return
	K.rule(root, 543, 949, 1, 102, T.LINE_DIM)
	_cap(root, str(vm.get("title", "")), 562, 949, T.CYAN_HI)
	var note := str(vm.get("note", ""))
	if note != "":
		var n := _cap(root, note, 0, 949, T.DIM)
		n.position.x = roundf(1375.0 - n.size.x)
	var mins: Array = []
	for item in items:
		var widest := 0.0
		for word in str(item.get("name", "")).replace("-", "- ").split(" "):
			widest = maxf(widest, _w(word, {"px": 12}))
		mins.append(widest + 14.0)
	var widths := _flex_fill(813.0 - 4.0 * (items.size() - 1), mins)
	var x := 562.0
	for i in items.size():
		var item: Dictionary = items[i]
		var state := str(item.get("state", "locked"))
		var w: float = widths[i]
		var fill := Color(0, 0, 0, 0)
		var border: Color = T.LINE_DIM
		var dashed := false
		var ink: Color = T.DIM
		if state == "current":
			fill = T.ACTIVE
			border = T.CYAN_HI
			ink = T.TEXT_HI
		elif state == "next":
			border = T.CYAN
			dashed = true
			ink = T.TEXT
		_box(root, Rect2(x, 972, w, 79), fill, border, dashed)
		K.text(root, str(item.get("n", "")), {"x": x + 7.0, "y": 979, "f": "disp", "wt": 600, "px": 16, "sp": 0.04, "col": ink, "up": true})
		K.text(root, str(item.get("name", "")), {"x": x + 7.0, "y": 1002, "w": w - 14.0, "px": 12, "lh": 13.8, "col": ink, "wrap": true})
		var progress := float(item.get("progress", 0.0))
		if progress > 0.0:
			var bar_w := w - 14.0
			_ground(root, Rect2(roundf(x + 7.0), 1043, bar_w, 3), Color("0b1620"))
			_ground(root, Rect2(roundf(x + 7.0), 1043, roundf(bar_w * clampf(progress, 0.0, 1.0)), 3), T.CYAN_HI)
		x += w + 4.0


## CSS `flex: 1` with min-content floors: items whose floor exceeds their share are frozen at the floor, the rest split what is left.
func _flex_fill(total: float, mins: Array) -> Array:
	var n := mins.size()
	var widths: Array = []
	var frozen: Array = []
	for i in n:
		widths.append(0.0)
		frozen.append(false)
	var free := total
	while true:
		var open := 0
		for i in n:
			if not frozen[i]:
				open += 1
		if open == 0:
			break
		var share := free / open
		var violated := false
		for i in n:
			if not frozen[i] and mins[i] > share:
				frozen[i] = true
				widths[i] = mins[i]
				free -= mins[i]
				violated = true
		if not violated:
			for i in n:
				if not frozen[i]:
					widths[i] = share
			break
	return widths


# ---------------------------------------------------------------- detail drawer

func _build_detail(root: Control, vm: Dictionary) -> void:
	K.panel(root, 1408, 184, 496, 880, "panel", {"border": T.CYAN, "ring": Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.55), "glow": Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.18), "light": false})
	var clip := Control.new()
	clip.name = "body"
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	clip.clip_contents = true
	K.place(clip, 1429, 203, 454, 784)
	root.add_child(clip)
	var body := Control.new()
	body.name = "content"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = Vector2(454, 784)
	clip.add_child(body)
	_detail_body = body
	var y := 0.0
	var state: Dictionary = vm.get("state", {})
	var head_cap := _cap(body, str(vm.get("cap", "Selected project")), 0, 3.5, T.CYAN_HI)
	if not state.is_empty():
		var st := _tag(body, str(state.get("label", "")), _col(state.get("tone", "cyan")), 0, 0)
		st.position.x = roundf(454.0 - st.size.x)
	head_cap.name = "cap"
	y += 22.0
	var title_text := str(vm.get("title", ""))
	if title_text == "":
		K.text(body, str(vm.get("empty", "Select a project in the graph to see its path, cost and effect.")), {"x": 0, "y": y + 12.0, "w": 454, "px": 14, "lh": 20.3, "col": T.DIM, "wrap": true})
		_detail_overflow = 0.0
		_detail_scroll = 0.0
		return
	y += 8.0
	var title := K.text(body, title_text, {"x": 0, "y": y, "w": 454, "f": "disp", "wt": 600, "px": 34, "sp": 0.04, "lh": 34, "col": T.TEXT_HI, "up": true, "wrap": true})
	y += title.size.y
	var tags: Array = vm.get("tags", [])
	if not tags.is_empty():
		y += 8.0
		var tx := 0.0
		var ty := y
		for t in tags:
			var tg := _tag(body, str(t.get("label", "")), _col(t.get("tone", "dim")), 0, 0, {"dashed": t.get("dashed", false)})
			if tx > 0.0 and tx + tg.size.x > 454.0:
				tx = 0.0
				ty += 22.0 + 8.0
			tg.position = Vector2(roundf(tx), roundf(ty))
			tx += tg.size.x + 8.0
		y = ty + 22.0
	var boxes: Array = vm.get("boxes", [])
	if not boxes.is_empty():
		y += 12.0
		var rows := ceili(boxes.size() / 3.0)
		for i in boxes.size():
			var b: Dictionary = boxes[i]
			var bx := (i % 3) * (146.0 + 8.0)
			var by := y + (i / 3) * (77.0 + 8.0)
			K.panel(body, bx, by, 146, 77, "glass")
			_cap(body, str(b.get("label", "")), bx + 11.0, by + 9.0, T.DIM)
			K.text(body, str(b.get("value", "")), {"x": bx + 11.0, "y": by + 29.0, "w": 124, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "col": _col(b.get("tone", ""), T.DIM), "up": true})
			K.bar(body, bx + 11.0, by + 62.0, 124, clampf(float(b.get("ratio", 0.0)), 0.0, 1.0), T.CYAN, 6)
		y += rows * 77.0 + (rows - 1) * 8.0
	var bn: Dictionary = vm.get("bottleneck", {})
	if not bn.is_empty():
		y += 12.0
		var tone := _col(bn.get("tone", "warn"))
		var text := K.text(body, str(bn.get("text", "")), {"x": 13, "y": y + 36.0, "w": 428, "px": 14, "lh": 20.3, "col": T.TEXT, "wrap": true})
		var bh := 1.0 + 10.0 + 20.0 + 5.0 + text.size.y + 10.0 + 1.0
		var frame := K.panel(body, 0, y, 454, bh, "glass", {"border": tone, "fill": Color(tone.r, tone.g, tone.b, 0.08)})
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.move_child(frame, text.get_index())
		K.icon(body, str(bn.get("icon", "lock")), 13, y + 11.0, tone, 20)
		_cap(body, str(bn.get("title", "")), 41, y + 13.5, tone)
		y += bh
	var path: Dictionary = vm.get("path", {})
	var steps: Array = path.get("steps", [])
	if not path.is_empty() and not steps.is_empty():
		y += 12.0
		_cap(body, str(path.get("title", "")), 0, y, T.CYAN_HI)
		var note := str(path.get("note", ""))
		if note != "":
			var nt := K.text(body, note, {"x": 0, "y": y, "f": "mono", "px": 12, "col": T.DIM})
			nt.position.x = roundf(454.0 - nt.size.x)
		y += 15.0 + 2.0
		for i in steps.size():
			var s: Dictionary = steps[i]
			var last := i == steps.size() - 1
			var row_h := 34.0
			var cy := y + (row_h - (0.0 if last else 1.0)) * 0.5
			_step_disc(body, str(s.get("n", i + 1)), 0, cy - 11.0, _col(s.get("tone", ""), Color("96f5ff")))
			K.text(body, str(s.get("kind", "")), {"x": 32, "y": cy - 7.5, "f": "mono", "px": 12, "sp": 0.08, "col": T.DIM})
			var tag_w := 0.0
			var st: Dictionary = s.get("tag", {})
			if not st.is_empty():
				var tg := _tag(body, str(st.get("label", "")), _col(st.get("tone", "dim")), 0, cy - 11.0)
				tg.position.x = roundf(454.0 - tg.size.x)
				tag_w = tg.size.x + 10.0
			K.text(body, _fit(str(s.get("label", "")), 454.0 - 128.0 - tag_w, {"px": 14}), {"x": 128, "y": cy - 9.0, "px": 14, "col": T.TEXT})
			if not last:
				K.rule(body, 0, y + 33.0, 454, 1, T.LINE_DIM)
			y += row_h
	var retro: Dictionary = vm.get("retrofit", {})
	var cells: Array = retro.get("cells", [])
	if not retro.is_empty() and not cells.is_empty():
		y += 12.0
		_cap(body, str(retro.get("title", "")), 0, y, T.CYAN_HI)
		y += 15.0 + 6.0
		var rrows := ceili(cells.size() / 3.0)
		for i in cells.size():
			var cell: Dictionary = cells[i]
			var cx := (i % 3) * (146.0 + 8.0)
			var cyy := y + (i / 3) * (63.0 + 8.0)
			K.panel(body, cx, cyy, 146, 63, "glass")
			_cap(body, str(cell.get("label", "")), cx + 11.0, cyy + 9.0, T.DIM)
			K.text(body, str(cell.get("value", "")), {"x": cx + 11.0, "y": cyy + 24.0, "w": 124, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": _col(cell.get("tone", ""), T.TEXT_HI), "up": true})
		y += rrows * 63.0 + (rrows - 1) * 8.0
	var eff: Dictionary = vm.get("effect", {})
	if not eff.is_empty() and str(eff.get("text", "")) != "":
		y += 12.0
		_cap(body, str(eff.get("title", "")), 0, y, T.CYAN_HI, {"lh": 18})
		var et := K.text(body, str(eff.get("text", "")), {"x": 0, "y": y + 18.0 + 4.0, "w": 454, "px": 14, "lh": 21, "col": T.TEXT, "wrap": true})
		y += 18.0 + 4.0 + et.size.y
	var honesty := str(vm.get("honesty", ""))
	if honesty != "":
		y += 12.0
		K.rule(body, 0, y, 454, 1, T.LINE_DIM)
		var ht := K.text(body, honesty, {"x": 0, "y": y + 11.0, "w": 454, "px": 13, "lh": 18.85, "col": T.DIM, "wrap": true})
		y += 11.0 + ht.size.y
	_detail_overflow = maxf(0.0, y - clip.size.y)
	_detail_scroll = 0.0
	clip.gui_input.connect(_on_detail_input)
	var specs: Array = []
	for key in ["primary", "secondary"]:
		if vm.has(key):
			specs.append([key, vm[key]])
	if specs.is_empty():
		return
	# Equal-width flex row, 10px gap. A label that does not fit its button wraps and makes every button two lines tall.
	var bw := (454.0 - 10.0 * (specs.size() - 1)) / specs.size()
	var wrapped := false
	for entry in specs:
		var spec: Dictionary = entry[1]
		var room := bw - 2.0 - 36.0 - (28.0 if spec.has("icon") else 0.0)
		if _w(str(spec.get("label", "")).to_upper(), {"f": "disp", "wt": 600, "px": 17, "sp": 0.08}) > room:
			wrapped = true
	var bx := 1429.0
	for entry in specs:
		var spec: Dictionary = entry[1]
		var opts := {"min_h": 44, "w": bw, "h": 46.0 if wrapped else 44.0, "primary": entry[0] == "primary", "wrap": true}
		if spec.has("icon"):
			opts["icon"] = spec["icon"]
			opts["icon_px"] = 20
		var btn := K.button(root, str(spec.get("label", "")), bx, 1045.0 - opts["h"], opts)
		btn.disabled = bool(spec.get("disabled", false))
		btn.pressed.connect(_emit.bind(str(spec.get("action", "")), spec.get("arg")))
		bx += bw + 10.0


func _step_disc(parent: Control, n: String, x: float, y: float, color: Color) -> void:
	var disc := Parts.Disc.new()
	K.place(disc, x, y)
	parent.add_child(disc)
	disc.setup(color, 22.0)
	K.text(disc, n, {"x": 0, "y": 0, "w": 22, "f": "disp", "wt": 700, "px": 15, "col": Color("03181d"), "al": "c"})


func _on_detail_input(event: InputEvent) -> void:
	if _detail_body == null or _detail_overflow <= 0.0:
		return
	if event is InputEventMouseButton and event.pressed:
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -48.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 48.0
		if step != 0.0:
			_detail_scroll = clampf(_detail_scroll + step, 0.0, _detail_overflow)
			_detail_body.position.y = -_detail_scroll
