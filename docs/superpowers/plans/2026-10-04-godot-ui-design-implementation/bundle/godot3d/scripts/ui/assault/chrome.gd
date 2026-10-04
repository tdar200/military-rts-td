extends RefCounted
## Top bar, boss bar, objective panel, relays card and the HQ edge alert. Geometry is CoreAssault at 1920x1080
## (tools/ui/dump_boxes.py coreassault); flow that CSS computes (wrap, auto heights, right alignment) is computed here.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const A = preload("res://scripts/ui/assault/util.gd")
const Tag = preload("res://scripts/ui/components/tag.gd")
const GradBox = preload("res://scripts/ui/components/grad_box.gd")
const SolidMark = preload("res://scripts/ui/components/solid_mark.gd")

const WIDTH := 1920.0


# ---------------------------------------------------------------- top bar

## vm: {groups: [[chip, ...], ...] (left, a 1px rule between groups), right: [chip, ...] (right aligned), width?}
## chip: {icon, tone, text, border?: tone word, dim?: bool}. A group or list may be empty.
static func top(root: Control, vm: Dictionary) -> void:
	var w: float = float(vm.get("width", WIDTH))
	var bar := GradBox.new()
	K.place(bar, 0, 0, w, 56)
	root.add_child(bar)
	bar.style({"from": Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.96), "to": Color(6.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.9), "border": T.LINE, "sides": "b", "stop": true})
	var x := 20.0
	var first := true
	for group in vm.get("groups", []):
		if not first:
			x += 6.0
			K.rule(root, x, 13.5, 1, 28, T.LINE)
			x += 1.0 + 6.0 + 10.0
		first = false
		for c in group:
			var chip := _top_chip(root, c)
			_snap_chip(chip, x)
			x += float(chip.get_meta("flow_w")) + 10.0
	var right: Array = vm.get("right", [])
	var rx := w - 20.0
	for i in range(right.size() - 1, -1, -1):
		var chip := _top_chip(root, right[i])
		rx -= chip.size.x
		_snap_chip(chip, rx)
		rx -= 10.0


## Chrome snaps both edges of the chip to whole pixels; the chip's own width stays fractional for the flow maths.
static func _snap_chip(chip: Control, x: float) -> void:
	var s := A.snap(x, chip.size.x)
	chip.position.x = s.x
	chip.set_meta("flow_w", chip.size.x)
	chip.size.x = s.y


static func _top_chip(root: Control, c: Dictionary) -> Control:
	var o := {"icon_px": 20}
	if str(c.get("border", "")) != "":
		o["border"] = A.tone(str(c["border"]))
	return K.chip(root, 0, 14, str(c.get("icon", "")), A.tone(str(c.get("tone", "cyan"))), [
		{"t": str(c.get("text", "")), "col": T.DIM if c.get("dim", false) else T.TEXT},
	], o)


# ---------------------------------------------------------------- boss bar

## vm: {name, hp_text, ratio 0..1, ticks?: [0..1] (default .25 .5 .75), phase?, retaliation?}
static func boss(root: Control, vm: Dictionary) -> void:
	var phase := str(vm.get("phase", ""))
	var retaliation := str(vm.get("retaliation", ""))
	var has_caps := phase != "" or retaliation != ""
	var height := 1.0 + 10.0 + 28.0 + 6.0 + 14.0 + (6.0 + 15.0 if has_caps else 0.0) + 12.0 + 1.0
	A.panel(root, 600, 68, 720, height, {
		"border": A.BOSS_EDGE,
		"fill_top": Color(40.0 / 255.0, 16.0 / 255.0, 16.0 / 255.0, 0.92),
		"fill_bottom": Color(14.0 / 255.0, 10.0 / 255.0, 14.0 / 255.0, 0.92),
	})
	K.text(root, str(vm.get("name", "")), {"x": 617, "y": 79, "f": "disp", "wt": 600, "px": 22, "sp": 0.1, "col": A.BOSS_TEXT, "up": true})
	var hp := K.text(root, str(vm.get("hp_text", "")), {"x": 0, "y": 79 + _baseline_gap("disp", 22, "mono", 14), "f": "mono", "px": 14, "col": A.BOSS_TEXT})
	hp.position.x = roundf(1303.0 - hp.size.x)
	var track := GradBox.new()
	K.place(track, 617, 113, 686, 14)
	root.add_child(track)
	track.style({"fill": A.BOSS_WELL, "border": A.BOSS_EDGE, "sides": "trbl"})
	var ratio := clampf(float(vm.get("ratio", 0.0)), 0.0, 1.0)
	if ratio > 0.0:
		var fill := GradBox.new()
		K.place(fill, 618, 114, 684.0 * ratio, 12)
		root.add_child(fill)
		fill.style({"from": Color("c43a33"), "to": Color("f04e46"), "horizontal": true})
	for t in vm.get("ticks", [0.25, 0.5, 0.75]):
		K.rule(root, 618.0 + 684.0 * float(t), 111, 2, 20, A.BAD_SOFT)
	if has_caps:
		K.text(root, phase, {"x": 617, "y": 133, "f": "mono", "px": 12, "sp": 0.12, "col": A.BOSS_CAP, "up": true})
		var right := K.text(root, retaliation, {"x": 0, "y": 133, "f": "mono", "px": 12, "sp": 0.12, "col": A.BOSS_CAP, "up": true})
		right.position.x = roundf(1303.0 - right.size.x)


## Top offset that puts a second face's line box on the first one's baseline (CSS align-items: baseline).
static func _baseline_gap(kind_a: String, px_a: int, kind_b: String, px_b: int) -> int:
	return T.ascent(T.font(kind_a, 600), px_a) - T.ascent(T.font(kind_b, 0), px_b)


# ---------------------------------------------------------------- objective panel

## vm: {cap?, tag?, title, body?, steps: [{t, state: "done"|"now"|"next", tag?}]}. Empty steps drop the checklist block.
static func objective(root: Control, vm: Dictionary) -> void:
	var steps: Array = vm.get("steps", [])
	var body_text := str(vm.get("body", ""))
	var panel := A.panel(root, 20, 72, 384, 100, {"border": T.CYAN})
	K.text(root, str(vm.get("cap", "Objective")), {"x": 37, "y": 90.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var tag_text := str(vm.get("tag", ""))
	if tag_text != "":
		var tag := _tag(root, tag_text, 0, 87, T.CYAN)
		tag.position.x = roundf(387.0 - tag.size.x)
	var y := 87.0 + 22.0 + 10.0
	var title := K.text(root, str(vm.get("title", "")), {"x": 37, "y": y, "w": 350, "f": "disp", "wt": 600, "px": 30, "sp": 0.04, "lh": 30, "col": T.TEXT_HI, "up": true, "wrap": true})
	y += title.size.y
	if body_text != "":
		y += 10.0
		var body := K.text(root, body_text, {"x": 37, "y": y, "w": 350, "px": 14, "lh": 19.6, "col": T.DIM, "wrap": true})
		y += body.size.y
	if not steps.is_empty():
		y += 10.0
		K.rule(root, 37, y, 350, 1, T.LINE_DIM)
		y += 1.0 + 4.0
		for i in steps.size():
			y += _step(root, y, steps[i]) + (7.0 if i < steps.size() - 1 else 0.0)
	panel.size.y = roundf(y + 14.0 + 1.0 - 72.0)
	panel.queue_redraw()


## One checklist row; returns its height (the tag is 22 high, the text can wrap past that).
static func _step(root: Control, y: float, step: Dictionary) -> float:
	var state := str(step.get("state", "next"))
	var label := str(step.get("tag", {"done": "Done", "now": "Now"}.get(state, "Next")))
	var tone: Color = T.GOOD if state == "done" else (T.CYAN if state == "now" else T.DIM)
	var text_o := {"x": 105, "px": 14, "lh": 18.2, "w": 282, "wrap": true, "col": T.TEXT}
	if state == "done":
		text_o["col"] = T.DIM
		text_o["strike"] = true
	elif state == "now":
		text_o["col"] = T.TEXT_HI
		text_o["wt"] = 500
	text_o["y"] = y
	var text := K.text(root, str(step.get("t", "")), text_o)
	var row_h := maxf(22.0, text.size.y)
	text.position.y = roundf(y + (row_h - text.size.y) * 0.5)
	_tag(root, label, 37, y + (row_h - 22.0) * 0.5, tone, T.ACTIVE if state == "now" else Color(0, 0, 0, 0), 58.0)
	return row_h


static func _tag(root: Control, s: String, x: float, y: float, color: Color, bg := Color(0, 0, 0, 0), min_w := 0.0) -> Control:
	var t := Tag.new()
	K.place(t, x, y)
	root.add_child(t)
	t.setup(s, color, bg, {"min_w": min_w})
	return t


# ---------------------------------------------------------------- relays card

## vm: {cap?, items: [{name, state: "destroyed"|"powered"|other, tag?, action?, arg?}], note?, max?}.
## With no items the card is not built. More than `max` (8) items show the first ones and a "+N more" line.
static func relays(root: Control, vm: Dictionary, emit: Callable) -> void:
	var items: Array = vm.get("items", [])
	if items.is_empty():
		return
	var shown := mini(items.size(), int(vm.get("max", 8)))
	var panel := A.panel(root, 1640, 72, 260, 100)
	K.text(root, str(vm.get("cap", "Invasion relays")), {"x": 1655, "y": 85, "w": 230, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var y := 85.0 + 15.0 + 8.0
	for i in shown:
		var item: Dictionary = items[i]
		var state := str(item.get("state", ""))
		var destroyed := state == "destroyed"
		var tone: Color = T.GOOD if destroyed else (T.BAD if state == "powered" else T.DIM)
		var mid := y + 11.0
		var mark := SolidMark.new()
		root.add_child(mark)
		mark.setup("dot" if state != "powered" else "diamond", 10.0, tone)
		mark.position = Vector2(1660.0, mid) - mark.size * 0.5
		K.text(root, str(item.get("name", "")), {"x": 1675, "y": y + 2, "w": 108, "px": 14})
		var label := str(item.get("tag", state.capitalize()))
		var tag := _tag(root, label, 0, y, tone)
		tag.position.x = roundf(1885.0 - tag.size.x)
		if item.get("action", "") != "":
			var hit := K.hit(root, 1640, y, 260, 22, str(item.get("name", "")))
			hit.pressed.connect(emit.bind(str(item["action"]), item.get("arg")))
		y += 22.0 + 8.0
	if items.size() > shown:
		K.text(root, "+%d more" % (items.size() - shown), {"x": 1655, "y": y, "px": 13, "col": T.DIM})
		y += 18.2 + 8.0
	var note := str(vm.get("note", ""))
	if note != "":
		var n := K.text(root, note, {"x": 1655, "y": y, "w": 230, "px": 13, "lh": 18.2, "col": T.DIM, "wrap": true})
		y += n.size.y + 8.0
	panel.size.y = roundf(y - 8.0 + 12.0 + 1.0 - 72.0)
	panel.queue_redraw()


# ---------------------------------------------------------------- HQ edge alert

## vm: {title, lines?: [String], side?: "left"|"right", y?: 690, action?, arg?}. The red arrow points at the screen edge
## the threatened thing is off; a click anywhere on the card emits `action`.
static func edge(root: Control, vm: Dictionary, emit: Callable) -> void:
	var title := str(vm.get("title", ""))
	if title == "":
		return
	var lines: Array = vm.get("lines", [])
	var y: float = float(vm.get("y", 690))
	var right_side := str(vm.get("side", "left")) == "right"
	var title_w := A.width("disp", 17, 600, 0.04, title.to_upper())
	var wide := title_w
	for l in lines:
		wide = maxf(wide, A.width("mono", 12, 0, 0.0, str(l)))
	var card_w := roundf(wide + 26.0 * 1.0)
	var card_h := 1.0 + 8.0 + 22.0 + 17.0 * lines.size() + 8.0 + 1.0
	var arrow_x := 12.0 if not right_side else WIDTH - 12.0 - 30.0
	var card_x := 38.0 if not right_side else arrow_x + 4.0 - card_w
	var arrow := Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(arrow, arrow_x, y + (card_h - 44.0) * 0.5, 30, 44)
	root.add_child(arrow)
	var pts := PackedVector2Array([Vector2(28, 2), Vector2(3, 22), Vector2(28, 42)])
	if right_side:
		for i in pts.size():
			pts[i].x = 30.0 - pts[i].x
	var fill := Polygon2D.new()
	fill.polygon = pts
	fill.color = T.BAD
	arrow.add_child(fill)
	var edge_line := Line2D.new()
	edge_line.points = pts
	edge_line.closed = true
	edge_line.width = 1.5
	edge_line.joint_mode = Line2D.LINE_JOINT_ROUND
	edge_line.default_color = Color("ffd2cf")
	edge_line.antialiased = true
	arrow.add_child(edge_line)
	A.panel(root, card_x, y, card_w, card_h, {"border": T.BAD})
	K.text(root, title, {"x": card_x + 13, "y": y + 9, "f": "disp", "wt": 600, "px": 17, "sp": 0.04, "col": A.BAD_SOFT, "up": true})
	var ly := y + 9.0 + 22.0 + 2.0
	for i in lines.size():
		K.text(root, str(lines[i]), {"x": card_x + 13, "y": ly, "f": "mono", "px": 12, "col": T.TEXT if i == 0 else T.DIM})
		ly += 17.0
	if str(vm.get("action", "")) != "":
		var hit := K.hit(root, card_x, y, card_w, card_h, title)
		hit.pressed.connect(emit.bind(str(vm["action"]), vm.get("arg")))
