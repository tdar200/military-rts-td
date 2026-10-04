extends RefCounted
## The Build screen (mock BuildDeck.dc.html at 1920x1080): top strip, forecast popover, alert rows, minimap panel,
## placement panel, the big build deck and map pins. Everything is registered into a Hud, which feeds each section its slice:
##
##   BuildDeck.register(hud)          once, after Hud.new()
##   hud.apply({"build_top": {...}, "build_power": {...}, "build_alerts": {...}, "build_minimap": {...},
##              "build_placement": {...}, "build_world": {...}, "deck": {"body": {"kind": "build", ...}}})
##
## Any key may be omitted (its section draws nothing). Actions emitted through hud.action:
##   deck_tab(id) | arm_build(id) | power_popover_button(action, arg), plus whatever "action"/"arg" a vm button carries.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const Kbd = preload("res://scripts/ui/components/kbd.gd")
const HatchFill = preload("res://scripts/ui/components/hatch_fill.gd")
const Logic = preload("res://scripts/ui/build_logic.gd")

const NONE := Color(0, 0, 0, 0)
const MAX_ALERT_ROWS := 5
const GRID_TOP := 556.0
const GRID_BOTTOM := 962.0


static func register(hud: Control) -> void:
	hud.register_section("build_top", func(layer: Control, vm: Variant) -> void: _top(layer, vm))
	hud.register_section("build_power", func(layer: Control, vm: Variant) -> void: _power(hud, layer, vm))
	hud.register_section("build_alerts", func(layer: Control, vm: Variant) -> void: _alerts(hud, layer, vm))
	hud.register_section("build_minimap", func(layer: Control, vm: Variant) -> void: _minimap(hud, layer, vm), "minimap_slot")
	hud.register_section("build_placement", func(layer: Control, vm: Variant) -> void: _placement(layer, vm))
	hud.register_section("build_world", func(layer: Control, vm: Variant) -> void: _world(layer, vm))
	hud.register_body("build", func(layer: Control, vm: Variant) -> void: _deck(hud, layer, vm))


# ---------------------------------------------------------------- small drawn pieces

## The full-width top strip: vertical gradient and a 1px bottom rule.
class Strip extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var top := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.95)
		var bot := Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.9)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))
		draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), T.LINE)


class Dot extends Control:
	var tone: Color = T.DIM

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8, 8)
		size = Vector2(8, 8)

	func _draw() -> void:
		draw_circle(Vector2(4, 4), 4.0, tone)


## The footprint diamond under the placement preview (148px box, viewBox coordinates from the mock).
class Footprint extends Control:
	var tone: Color = T.GOOD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(74, 84), Vector2(130, 110), Vector2(74, 136), Vector2(18, 110)])
		draw_colored_polygon(pts, Color(tone.r, tone.g, tone.b, 0.2))
		var ring := pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, tone, 2.0, true)


## A rectangle that scrolls its content vertically with the mouse wheel and keeps the offset through rebuilds.
class ScrollBox extends Control:
	var content: Control
	var overflow := 0.0
	var offset := 0.0
	var on_scroll: Callable

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		content = Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(content)

	func set_extent(content_h: float) -> void:
		overflow = maxf(0.0, content_h - size.y)
		offset = clampf(offset, -overflow, 0.0)
		content.position.y = offset
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if overflow <= 0.0 or not (event is InputEventMouseButton) or not event.pressed:
			return
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = 46.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = -46.0
		if step != 0.0:
			offset = clampf(offset + step, -overflow, 0.0)
			content.position.y = offset
			if on_scroll.is_valid():
				on_scroll.call(offset)
			queue_redraw()
			accept_event()

	func _draw() -> void:
		if overflow <= 0.0:
			return
		var track := size.y - 8.0
		var thumb := maxf(24.0, track * size.y / (size.y + overflow))
		var y := 4.0 + (track - thumb) * (-offset / overflow)
		draw_rect(Rect2(size.x - 4.0, y, 3.0, thumb), Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.5))


## A flat bordered box (the mock's 1px #1b3342 boxes, chips and cost cells).
static func _box(parent: Node, x: float, y: float, w: float, h: float, fill: Color, border: Color, radius := 0) -> Control:
	var p := K.panel(parent, x, y, w, h, "glass", {"fill": fill, "border": border, "radius": radius, "light": false})
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _tone(name: Variant, fallback: Color = T.TEXT) -> Color:
	if name is Color:
		return name
	var s := str(name)
	if s == "faint":
		return T.FAINT
	return T.tone(s) if s != "" else fallback


## A chip: [text | dot | kbd] items 8px apart. Items: {k:"text", t, col, f, px, wt, sp, up} {k:"dot", col} {k:"kbd", t}.
static func _chip(parent: Control, x: float, y: float, items: Array, border: Color = T.LINE, glow := NONE) -> Control:
	var panel := K.panel(parent, x, y, 10, 28, "glass", {"fill": T.BG2, "border": border, "radius": 2, "light": false, "glow": glow})
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cursor := 11.0
	for item in items:
		var node: Control
		match item.get("k", "text"):
			"dot":
				node = Dot.new()
				node.tone = item.get("col", T.DIM)
				panel.add_child(node)
			"kbd":
				node = Kbd.new()
				panel.add_child(node)
				node.setup(str(item.get("t", "")))
			_:
				node = K.text(panel, str(item.get("t", "")), {"f": item.get("f", "mono"), "px": item.get("px", 13), "wt": item.get("wt", 0), "sp": item.get("sp", 0.0), "col": item.get("col", T.TEXT), "up": item.get("up", false)})
		node.position = Vector2(cursor, (28.0 - node.size.y) * 0.5)
		cursor += node.size.x + 8.0
	panel.size.x = cursor - 8.0 + 11.0
	panel.queue_redraw()
	return panel


# ---------------------------------------------------------------- top strip

## vm: {era, chips:[{label, value, note, note_tone, warn}], wave:{label, timer, note}, pause:{label, key}, rates:[{t, on}]}
static func _top(root: Control, vm: Dictionary) -> void:
	var strip := Strip.new()
	K.place(strip, 0, 0, 1920, 56)
	root.add_child(strip)
	var x := 16.0
	if vm.get("era", "") != "":
		var era := _chip(root, x, 13.5, [{"k": "dot", "col": T.DIM}, {"t": str(vm["era"]).to_upper()}], T.DIM)
		x += era.size.x + 12.0
	for chip in vm.get("chips", []):
		var warn: bool = chip.get("warn", false)
		var items: Array = [
			{"t": str(chip.get("label", "")), "px": 12, "sp": 0.12, "col": T.DIM, "up": true},
			{"t": str(chip.get("value", "")), "f": "disp", "px": 22, "wt": 600, "sp": 0.02, "col": T.TEXT_HI, "up": true},
		]
		if chip.get("note", "") != "":
			items.append({"t": str(chip["note"]), "col": _tone(chip.get("note_tone", ""), T.TEXT)})
		var c := _chip(root, x, 13.5, items, T.WARN if warn else T.LINE, Color(T.WARN.r, T.WARN.g, T.WARN.b, 0.2) if warn else NONE)
		x += c.size.x + 12.0
	# Right group, laid out from the right edge (1904).
	var right := 1904.0
	var rates: Array = vm.get("rates", [])
	if not rates.is_empty():
		var items: Array = []
		for r in rates:
			items.append({"t": str(r.get("t", "")), "col": T.CYAN if r.get("on", false) else T.DIM})
		var chip := _chip(root, 0, 13.5, items)
		chip.position.x = right - chip.size.x
		right = chip.position.x - 12.0
	var pause: Dictionary = vm.get("pause", {})
	if not pause.is_empty():
		var items: Array = [{"t": str(pause.get("label", ""))}]
		if pause.get("key", "") != "":
			items.append({"k": "kbd", "t": str(pause["key"])})
		var chip := _chip(root, 0, 13.5, items)
		chip.position.x = right - chip.size.x
		right = chip.position.x - 12.0
	var wave: Dictionary = vm.get("wave", {})
	if not wave.is_empty():
		var items: Array = [
			{"t": str(wave.get("label", "")), "px": 12, "sp": 0.12, "col": T.WARN, "up": true},
			{"t": str(wave.get("timer", "")), "f": "disp", "px": 22, "wt": 600, "sp": 0.04, "col": T.WARN, "up": true},
		]
		if wave.get("note", "") != "":
			items.append({"t": str(wave["note"])})
		var chip := _chip(root, 0, 13.5, items, T.WARN)
		chip.position.x = right - chip.size.x


# ---------------------------------------------------------------- forecast popover

## vm: {title, tag, body, buttons:[{label, action, arg, primary}]}
static func _power(hud: Control, root: Control, vm: Dictionary) -> void:
	var panel := K.panel(root, 470, 66, 420, 100, "panel", {"border": T.WARN})
	var tag := K.tag(root, str(vm.get("tag", "")), 0, 0, T.WARN)
	var title := K.text(root, str(vm.get("title", "")), {"x": 489, "y": 83, "w": 382.0 - tag.size.x, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "col": T.WARN, "up": true, "wrap": true})
	tag.position = Vector2(roundf(871.0 - tag.size.x), roundf(83.0 + (maxf(title.size.y, 22.0) - tag.size.y) * 0.5))
	var y := 83.0 + maxf(title.size.y, 22.0) + 10.0
	var body := K.text(root, str(vm.get("body", "")), {"x": 489, "y": y, "w": 382, "px": 14, "lh": 20.3, "col": T.DIM, "wrap": true})
	y += body.size.y + 10.0
	var x := 489.0
	for b in vm.get("buttons", []):
		var btn := K.button(root, str(b.get("label", "")), x, y, {"min_h": 44, "px": 15, "primary": b.get("primary", false)})
		btn.pressed.connect(func() -> void: hud.action.emit(str(b.get("action", "")), b.get("arg")))
		x += btn.size.x + 10.0
	panel.size.y = (y + 44.0 + 16.0 + 1.0) - 66.0 if not vm.get("buttons", []).is_empty() else (y - 10.0 + 16.0 + 1.0) - 66.0
	panel.queue_redraw()


# ---------------------------------------------------------------- alerts and breadcrumb

## vm: {rows:[{tone, icon, text}], crumbs:[...]}. Rows grow upward from a fixed bottom row at y=736.
static func _alerts(hud: Control, root: Control, vm: Dictionary) -> void:
	var rows: Array = vm.get("rows", [])
	if rows.size() > MAX_ALERT_ROWS:
		rows = rows.slice(rows.size() - MAX_ALERT_ROWS)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := 736.0 - (rows.size() - 1 - i) * 46.0
		var tone: String = row.get("tone", "")
		var border: Color = _tone(tone, T.LINE_DIM) if tone != "" else T.LINE_DIM
		K.panel(root, 16, y, 340, 40, "glass", {"border": border})
		K.icon(root, str(row.get("icon", "warning")), 29, y + 11, border if tone != "" else T.DIM)
		K.text(root, str(row.get("text", "")), {"x": 57, "y": y + 11, "w": 287, "px": 14, "col": T.TEXT})
		if row.get("action", "") != "":
			var hit := K.hit(root, 16, y, 340, 40, str(row.get("text", "")))
			hit.pressed.connect(func() -> void: hud.action.emit(str(row["action"]), row.get("arg")))
	var crumbs: Array = vm.get("crumbs", [])
	var x := 16.0
	for i in crumbs.size():
		var last := i == crumbs.size() - 1
		var box := K.text(root, str(crumbs[i]), {"x": x, "y": 793.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI if last else T.DIM, "up": true})
		x += box.size.x + 8.0
		if not last:
			var slash := K.text(root, "/", {"x": x, "y": 793.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.FAINT})
			x += slash.size.x + 8.0


# ---------------------------------------------------------------- minimap

## vm: {}. The frame goes under the persistent map slot, which is moved to 322x222 at 25,833.
static func _minimap(hud: Control, root: Control, _vm: Dictionary) -> void:
	K.panel(root, 16, 824, 340, 240)
	K.place(hud.map_slot, 25, 833, 322, 222)


# ---------------------------------------------------------------- placement panel

## vm: {sprite, tone, status, title, costs:[{cap, value, tone}], note, grid:{value, tone, note, segments, marker, lead, text},
##      checks:[{ok, text}], hints:[{key, label}]}
static func _placement(root: Control, vm: Dictionary) -> void:
	var tone: Color = _tone(vm.get("tone", "good"), T.GOOD)
	var ring := Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.55) if tone != T.BAD else Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.55)
	var glow := Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.18) if tone != T.BAD else Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.18)
	K.panel(root, 376, 724, 728, 340, "panel", {"ring": ring, "glow": glow})
	# Preview box: radial ground, footprint, sprite.
	var ground := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("3b3d30"), Color("23251e")])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.7)
	tex.fill_to = Vector2(1.207, 0.7)
	tex.width = 148
	tex.height = 148
	ground.texture = tex
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(ground, 398, 746, 148, 148)
	root.add_child(ground)
	var foot := Footprint.new()
	foot.tone = tone
	K.place(foot, 398, 746, 148, 148)
	root.add_child(foot)
	K.sprite(root, str(vm.get("sprite", "")), 408, 748, 128, 128)
	var rim := _box(root, 397, 745, 150, 150, NONE, T.LINE_DIM)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Header: caption and status tag.
	K.text(root, "Placement preview", {"x": 567, "y": 748.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var tag := K.tag(root, str(vm.get("status", "")), 0, 745, tone)
	tag.position.x = roundf(1083.0 - tag.size.x)
	K.text(root, str(vm.get("title", "")), {"x": 567, "y": 775, "w": 516, "f": "disp", "wt": 600, "px": 32, "sp": 0.04, "lh": 32, "col": T.TEXT_HI, "up": true})
	var costs: Array = vm.get("costs", [])
	var n := maxi(costs.size(), 1)
	var cell_w := (516.0 - 10.0 * (n - 1)) / n
	for i in costs.size():
		var c: Dictionary = costs[i]
		var cx := 567.0 + i * (cell_w + 10.0)
		var hot: bool = c.get("tone", "") == "warn" or c.get("tone", "") == "bad"
		_box(root, cx, 815, cell_w, 57.6, T.BG2, _tone(c["tone"]) if hot else T.LINE_DIM)
		K.text(root, str(c.get("cap", "")), {"x": cx + 11, "y": 822, "w": cell_w - 22, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
		K.text(root, str(c.get("value", "")), {"x": cx + 11, "y": 837, "w": cell_w - 22, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "lh": 28.6, "col": _tone(c["tone"]) if hot else T.TEXT_HI, "up": true})
	if vm.get("note", "") != "":
		K.text(root, str(vm["note"]), {"x": 567, "y": 880.6, "w": 516, "px": 14, "col": T.DIM})
	# Projected grid.
	var grid: Dictionary = vm.get("grid", {})
	if not grid.is_empty():
		K.text(root, "Projected grid", {"x": 397, "y": 925, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
		var value := K.text(root, str(grid.get("value", "")), {"x": 0, "y": 913, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "col": _tone(grid.get("tone", "cyan")), "up": true})
		var note := K.text(root, str(grid.get("note", "")), {"x": 0, "y": 923, "px": 14, "col": T.DIM})
		var note_w: float = note.size.x
		note.position.x = roundf(1083.0 - note_w)
		value.position.x = roundf(1083.0 - note_w - 8.0 - value.size.x) if note_w > 0.0 else roundf(1083.0 - value.size.x)
		_box(root, 397, 952, 686, 14, T.BAR_BG, T.LINE_DIM)
		var sx := 398.0
		for seg in grid.get("segments", []):
			var w: float = 684.0 * float(seg.get("ratio", 0.0))
			if w <= 0.0:
				continue
			if seg.get("tone", "") == "bad_hatch":
				var hatch := HatchFill.new()
				K.place(hatch, sx, 953, w, 12)
				root.add_child(hatch)
			else:
				K.rule(root, sx, 953, w, 12, _tone(seg.get("tone", "cyan")))
			sx += w
		if grid.has("marker"):
			K.rule(root, 398.0 + 684.0 * float(grid["marker"]) - 0.8, 948, 2, 22, T.TEXT)
		var lead := str(grid.get("lead", ""))
		var text_x := 397.0
		if lead != "":
			var lead_box := K.text(root, lead, {"x": 397, "y": 972, "f": "mono", "px": 14, "col": _tone(grid.get("lead_tone", "bad"))})
			var space := K.text(root, " ", {"x": 0, "y": 0, "px": 14})
			text_x += lead_box.size.x + space.size.x
			space.queue_free()
		K.text(root, str(grid.get("text", "")), {"x": text_x, "y": 972, "px": 14, "col": T.TEXT})
	# Key hints (right) and checks (left). Like the mock's flex row, the checks shrink and wrap their text when
	# they do not fit beside the hints, so the two groups never overlap.
	var hints: Array = vm.get("hints", [])
	var hint_w := 0.0
	for hint in hints:
		var word := K.text(root, str(hint.get("label", "")), {"px": 14})
		hint_w += Kbd.measure(str(hint.get("key", ""))) + 8.0 + word.size.x + 8.0
		word.queue_free()
	hint_w = maxf(0.0, hint_w - 8.0)
	var hx := 1083.0 - hint_w
	for hint in hints:
		var cap := Kbd.new()
		root.add_child(cap)
		cap.setup(str(hint.get("key", "")))
		cap.position = Vector2(roundf(hx), 1013)
		hx += cap.size.x + 8.0
		var word := K.text(root, str(hint.get("label", "")), {"x": hx, "y": 1016, "px": 14, "col": T.DIM})
		hx += word.size.x + 8.0
	var checks: Array = vm.get("checks", [])
	if checks.is_empty():
		return
	var natural: Array = []
	var total := 0.0
	for check in checks:
		var probe := K.text(root, str(check.get("text", "")), {"px": 14})
		natural.append(probe.size.x)
		total += 22.0 + probe.size.x
		probe.queue_free()
	var avail := 686.0 - (hint_w + 18.0 if hint_w > 0.0 else 0.0) - 18.0 * (checks.size() - 1)
	var shrink := maxf(0.0, (total - avail) / total)
	var cx := 397.0
	for i in checks.size():
		var ok: bool = checks[i].get("ok", true)
		var icon_w := 16.0 * (1.0 - shrink)
		K.icon(root, "check_bold" if ok else "cross_bold", cx, 1017, T.GOOD if ok else T.BAD, 16, 2.2)
		var text_w: float = natural[i] * (1.0 - shrink)
		var opts := {"x": cx + icon_w + 6.0, "y": 1016, "px": 14, "col": T.TEXT}
		if shrink > 0.0:
			opts["w"] = ceilf(text_w)
			opts["wrap"] = true
		var label := K.text(root, str(checks[i].get("text", "")), opts)
		label.position.y = roundf(1025.0 - label.size.y * 0.5)
		cx += icon_w + 6.0 + text_w + 18.0


# ---------------------------------------------------------------- deck

## vm: {tabs:[{id, label, on}], cards:[{id, name, sprite, key, cost, prereq, selected, locked, short}], legend:[...],
##      empty_title, empty_hint, queue:{sprite, title, tag, tone, detail, ratio, ratio_label} | {empty:true, title, detail}}
static func _deck(hud: Control, root: Control, vm: Dictionary) -> void:
	K.panel(root, 1124, 494, 780, 570)
	_deck_tabs(hud, root, vm.get("tabs", []))
	var cards: Array = vm.get("cards", [])
	var scroll := ScrollBox.new()
	K.place(scroll, 1125, GRID_TOP, 778, GRID_BOTTOM - GRID_TOP)
	root.add_child(scroll)
	if cards.is_empty():
		K.text(scroll.content, str(vm.get("empty_title", "No structures available")), {"x": 12, "y": 150, "w": 754, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "al": "c", "col": T.DIM, "up": true})
		K.text(scroll.content, str(vm.get("empty_hint", "Unlock more in the Science tab")), {"x": 12, "y": 184, "w": 754, "px": 14, "al": "c", "col": T.FAINT})
	for i in cards.size():
		_card(hud, scroll.content, 12.0 + (i % 4) * 191.0, float(i / 4) * 138.0, cards[i])
	var rows := ceili(cards.size() / 4.0)
	scroll.offset = float(hud.get_meta("build_scroll", 0.0))
	scroll.on_scroll = func(y: float) -> void: hud.set_meta("build_scroll", y)
	scroll.set_extent(maxf(0.0, rows * 138.0 - 10.0))
	# Legend.
	var lx := 1137.0
	for entry in vm.get("legend", ["M materials", "W work", "kW power draw (+ is output)"]):
		var t := K.text(root, str(entry), {"x": lx, "y": 970, "f": "mono", "px": 13, "col": T.DIM})
		lx += t.size.x + 18.0
	_queue(root, vm.get("queue", {}))


static func _deck_tabs(hud: Control, root: Control, tabs: Array) -> void:
	if tabs.is_empty():
		return
	var w := 778.0 / tabs.size()
	K.rule(root, 1125, 543, 778, 1, T.LINE)
	for i in tabs.size():
		var tab: Dictionary = tabs[i]
		var x := 1125.0 + i * w
		var on: bool = tab.get("on", false)
		if on:
			K.rule(root, x, 495, w, 48, T.ACTIVE)
			K.rule(root, x, 541, w, 2, T.CYAN)
		var label := K.text(root, str(tab.get("label", "")), {"x": x, "y": 495, "w": w, "f": "disp", "wt": 600, "px": 18, "sp": 0.1, "al": "c", "col": T.TEXT_HI if on else T.DIM, "up": true})
		label.position.y = 495.0 + (46.0 - label.size.y) * 0.5
		var hit := K.hit(root, x, 495, w, 48, str(tab.get("label", "")))
		hit.pressed.connect(func() -> void: hud.action.emit("deck_tab", tab.get("id")))


static func _card(hud: Control, parent: Control, x: float, y: float, card: Dictionary) -> void:
	var locked: bool = card.get("locked", false)
	var short: bool = card.get("short", false)
	var selected: bool = card.get("selected", false)
	var style := {"fill": Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.92), "border": T.LINE_DIM, "radius": 3, "light": false}
	if selected:
		style["fill"] = T.ACTIVE
		style["border"] = T.CYAN_HI
		style["ring"] = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.55)
		style["glow"] = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.28)
	var panel := K.panel(parent, x, y, 181, 128, "glass", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.sprite(parent, str(card.get("sprite", "")), x + 11, y + 9, 48, 48)
	# Right-aligned markers, 6px apart: key last, then the warning, then the lock (right to left).
	var rx := x + 181.0 - 11.0
	if str(card.get("key", "")) != "":
		var cap := Kbd.new()
		parent.add_child(cap)
		cap.setup(str(card["key"]))
		rx -= cap.size.x
		cap.position = Vector2(roundf(rx), y + 9)
		rx -= 6.0
	if short:
		rx -= 18.0
		K.icon(parent, "warning", rx, y + 9, T.BAD)
		rx -= 6.0
	if locked:
		rx -= 18.0
		K.icon(parent, "lock", rx, y + 9, T.DIM)
	var dim := locked
	K.text(parent, str(card.get("name", "")), {"x": x + 11, "y": y + 59, "w": 159, "f": "disp", "wt": 600, "px": 17, "sp": 0.04, "lh": 19.55, "col": T.DIM if dim else (T.TEXT_HI if selected else T.TEXT), "up": true})
	var cost_col: Color = T.DIM if dim else (T.BAD if short else T.TEXT)
	K.text(parent, str(card.get("cost", "")), {"x": x + 11, "y": y + 80.5, "w": 159, "f": "mono", "px": 13, "col": cost_col})
	K.text(parent, str(card.get("prereq", "")), {"x": x + 11, "y": y + 99.5, "w": 159, "px": 13, "col": T.DIM})
	if not locked:
		var hit := K.hit(parent, x, y, 181, 128, str(card.get("name", "")))
		hit.pressed.connect(func() -> void: hud.action.emit("arm_build", card.get("id", card.get("name"))))


static func _queue(root: Control, q: Dictionary) -> void:
	if q.is_empty():
		return
	if q.get("empty", false):
		var empty := K.panel(root, 1137, 993, 754, 58, "glass", {"border": T.FAINT, "dashed": true, "fill": NONE, "radius": 3, "light": false})
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		K.text(root, str(q.get("title", "Queue empty")), {"x": 1150, "y": 1002, "f": "disp", "wt": 600, "px": 17, "sp": 0.04, "col": T.DIM, "up": true})
		K.text(root, str(q.get("detail", "")), {"x": 1150, "y": 1024, "px": 14, "col": T.DIM})
		return
	var tone: Color = _tone(q.get("tone", "warn"), T.WARN)
	var box := K.panel(root, 1137, 993, 754, 58, "glass", {"fill": Color(tone.r, tone.g, tone.b, 0.06), "border": tone, "radius": 3, "light": false})
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.sprite(root, str(q.get("sprite", "")), 1150, 1002, 40, 40)
	var title := K.text(root, str(q.get("title", "")), {"x": 1204, "y": 1002, "f": "disp", "wt": 600, "px": 17, "sp": 0.04, "col": T.TEXT_HI, "up": true})
	if q.get("tag", "") != "":
		K.tag(root, str(q["tag"]), 1204 + title.size.x + 10, 1002, tone)
	K.text(root, str(q.get("detail", "")), {"x": 1204, "y": 1024, "w": 540, "px": 14, "col": T.TEXT})
	if q.has("ratio"):
		K.bar(root, 1758, 1010, 120, float(q["ratio"]), tone)
		K.text(root, str(q.get("ratio_label", "")), {"x": 1758, "y": 1019, "w": 120, "f": "mono", "px": 12, "al": "r", "col": T.DIM})


# ---------------------------------------------------------------- map pins and labels

## vm: {pins:[{x, y, badge, text, tone}], labels:[{x, y, text, kind: "cap"|"tag", tone}]} in screen pixels; never blocks input.
static func _world(root: Control, vm: Dictionary) -> void:
	for pin in vm.get("pins", []):
		var tone: Color = _tone(pin.get("tone", "cyan"), T.CYAN)
		var label := K.text(root, str(pin.get("text", "")), {"x": 0, "y": 0, "px": 14, "col": T.TEXT})
		var w := 1.0 + 4.0 + 22.0 + 8.0 + label.size.x + 12.0 + 1.0
		var px: float = pin.get("x", 0.0)
		var py: float = pin.get("y", 0.0)
		var holder := _box(root, px, py, w, 30, Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.86), tone, 15)
		root.move_child(holder, label.get_index())
		var badge := Panel.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var disc := StyleBoxFlat.new()
		disc.bg_color = tone
		disc.set_corner_radius_all(11)
		badge.add_theme_stylebox_override("panel", disc)
		K.place(badge, px + 5, py + 4, 22, 22)
		root.add_child(badge)
		var letter := K.text(root, str(pin.get("badge", "")), {"x": px + 5, "y": py + 4, "w": 22, "f": "disp", "wt": 700, "px": 15, "al": "c", "col": Color("03050a"), "up": true})
		letter.position.y = py + 4.0 + (22.0 - letter.size.y) * 0.5
		label.position = Vector2(roundf(px + 35.0), roundf(py + 6.0))
	for item in vm.get("labels", []):
		var lx: float = item.get("x", 0.0)
		var ly: float = item.get("y", 0.0)
		if item.get("kind", "cap") == "tag":
			var tag := K.tag(root, str(item.get("text", "")), lx, ly, _tone(item.get("tone", "good"), T.GOOD), Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.86))
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var cap := K.text(root, str(item.get("text", "")), {"x": lx + 9, "y": ly + 5, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
			var frame := _box(root, lx, ly, cap.size.x + 18.0, 15.0 + 10.0, Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.75), T.CYAN_DK, 2)
			root.move_child(frame, cap.get_index())
