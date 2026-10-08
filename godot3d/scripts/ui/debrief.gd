extends Control
## Victory / defeat debrief: one 960-wide column from the Debrief mock. The gallery puts two side by side (the mock board);
## the game shows one on a scrim (see place_in). Blocks whose data is absent are omitted and the column closes up.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Chart = preload("res://scripts/ui/components/line_chart.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const HoloButton = preload("res://scripts/ui/components/holo_button.gd")

signal action(name: String, arg: Variant)

const WIDTH := 960.0
const HEIGHT := 1080.0
const PAD_X := 56.0
const PAD_Y := 44.0
const GAP := 20.0
const BUTTON_H := 44.0
const DANGER_LINE := Color("5a2a2a")
const SEG_OK := Color("185a6e")
const SEG_WARN := Color("6b4a10")
const SEG_BAD := Color("7a1f1b")
const LOST := Color("f06050")
const GLOW_COPIES := 40
const GLOW_SIGMA := 11.0
const GLOW_ALPHA := 0.4
## Task 22: the score panel's least height and the step between its rows.
const SCORE_MIN_H := 130.0
const SCORE_ROW_H := 22.0
const SCORE_GRADE_COLORS := {"S": T.WARN_HI, "A": T.CYAN, "B": T.GOOD, "C": T.TEXT, "D": T.DIM}

var variant := "victory"
## Height the content needs; larger than HEIGHT only when a very long timeline or list pushes the buttons down.
var content_height := HEIGHT
## Name -> rect of every block laid out by the last apply() (tests assert none overlap).
var blocks: Dictionary = {}
var _hash := -1
var _glow: GradientTexture2D
var _top: Color
var _bottom: Color
var _glow_color: Color
var _glow_x := 0.3
var _divider := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = custom_minimum_size


## Centre the column in `host_size`, scaling it down uniformly when the host is shorter than the content.
static func place_in(col: Control, host_size: Vector2) -> void:
	var h: float = maxf(col.size.y, 1.0)
	var s := minf(1.0, minf(host_size.y / h, host_size.x / col.size.x))
	col.pivot_offset = Vector2.ZERO
	col.scale = Vector2(s, s)
	col.position = ((host_size - col.size * s) * 0.5).round()


## vm: variant, divider?, tag, operation, status?, title, lede, stats?[], score?{total, grade, rows[], best?, new_best},
## casualties?{rows[], legend?}, economy?{...chart},
## teaser?{title, tag?, body}, chips?[], timeline?{title, range, rows[], ticks[], end?}, chain?[], advice?[], footer?, buttons[].
func apply(vm: Dictionary) -> void:
	var h := hash(vm)
	if h == _hash:
		return
	_hash = h
	for c in get_children():
		remove_child(c)
		c.queue_free()
	blocks.clear()
	variant = str(vm.get("variant", "victory"))
	_divider = vm.get("divider", false)
	var victory := variant == "victory"
	_top = Color("07121c") if victory else Color("120b0e")
	_bottom = Color("060910") if victory else Color("07070b")
	_glow_color = Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.16) if victory else Color(240.0 / 255.0, 78.0 / 255.0, 70.0 / 255.0, 0.16)
	_glow_x = 0.3 if victory else 0.7
	_make_glow()
	var x0 := PAD_X + (1.0 if _divider else 0.0)
	var w := WIDTH - PAD_X - x0
	var y := PAD_Y
	y = _block("header", x0, y, _header(vm, x0, w, y, victory)) + GAP
	y = _block("headline", x0, y, _headline(vm, x0, y, victory)) + GAP
	if not vm.get("chips", []).is_empty():
		y = _block("chips", x0, y, _chips(vm["chips"], x0, w, y)) + GAP
	if not vm.get("stats", []).is_empty():
		y = _block("stats", x0, y, _stats(vm["stats"], x0, w, y)) + GAP
	if not vm.get("score", {}).is_empty():
		y = _block("score", x0, y, _score(vm["score"], x0, w, y)) + GAP
	if not vm.get("casualties", {}).get("rows", []).is_empty() or not vm.get("economy", {}).get("series", []).is_empty():
		y = _block("charts", x0, y, _casualties_and_economy(vm, x0, w, y)) + GAP
	if not vm.get("timeline", {}).get("rows", []).is_empty():
		y = _block("timeline", x0, y, _timeline(vm["timeline"], x0, w, y)) + GAP
	if not vm.get("chain", []).is_empty():
		y = _block("chain", x0, y, _chain(vm["chain"], x0, w, y)) + GAP
	if not vm.get("teaser", {}).is_empty():
		y = _block("teaser", x0, y, _teaser(vm["teaser"], x0, w, y)) + GAP
	if str(vm.get("footer", "")) != "":
		var foot := K.text(self, str(vm["footer"]), {"x": x0, "y": y, "w": w, "f": "mono", "px": 13, "sp": 0.03, "col": T.DIM, "wrap": true})
		y = _block("footer", x0, y, y + foot.size.y) + GAP
	if not vm.get("advice", []).is_empty():
		y = _block("advice", x0, y, _advice(vm["advice"], x0, w, y)) + GAP
	if vm.get("buttons", []).is_empty():
		content_height = maxf(HEIGHT, y - GAP + PAD_Y)
	else:
		var buttons_y := maxf(HEIGHT - PAD_Y - BUTTON_H, y)
		_buttons(vm["buttons"], x0, w, buttons_y)
		blocks["buttons"] = Rect2(x0, buttons_y, w, BUTTON_H)
		content_height = buttons_y + BUTTON_H + PAD_Y
	size = Vector2(WIDTH, maxf(HEIGHT, content_height))
	queue_redraw()


func _block(name: String, x: float, top: float, bottom: float) -> float:
	blocks[name] = Rect2(x, top, WIDTH - PAD_X - x, bottom - top)
	return bottom


## `s` cut with an ellipsis so one line of it fits `max_w` (`o` are the K.text options the line will use).
func _fit(s: String, o: Dictionary, max_w: float) -> String:
	var probe := TextBox.new()
	probe.configure("", o)
	var upper: bool = o.get("up", false)
	var n := s.length()
	var out := s
	if probe.measure(s.to_upper() if upper else s) > max_w:
		while n > 1:
			n -= 1
			out = s.substr(0, n).strip_edges(false, true) + "\u2026"
			if probe.measure(out.to_upper() if upper else out) <= max_w:
				break
	probe.free()
	return out


func _make_glow() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.65])
	g.colors = PackedColorArray([_glow_color, Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 450
	_glow.height = 280


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, 0), rect.end, Vector2(0, rect.end.y)]), PackedColorArray([_top, _top, _bottom, _bottom]))
	if _glow:
		# CSS radial-gradient(900px 560px at X 0, c, transparent 65%): an ellipse of 900x560 radius centred on the top edge.
		draw_texture_rect(_glow, Rect2(WIDTH * _glow_x - 900.0, -560.0, 1800.0, 1120.0), false)
	if _divider:
		draw_rect(Rect2(0, 0, 1, size.y), T.LINE)


# ---------------------------------------------------------------- blocks

func _header(vm: Dictionary, x0: float, w: float, y: float, victory: bool) -> float:
	var tag := K.tag(self, str(vm.get("tag", "")), x0, y, T.GOOD if victory else T.BAD)
	var cap := {"f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true, "y": y + 3.5}
	var op_x := x0 + tag.size.x + 12.0
	var status := str(vm.get("status", ""))
	var op := K.text(self, _fit(str(vm.get("operation", "")), cap, w - tag.size.x - 12.0), cap.merged({"x": op_x}))
	var bottom := y + 22.0
	if status != "":
		var st := K.text(self, status, cap)
		var right_x := roundf(x0 + w - st.size.x)
		if right_x >= op_x + op.size.x + 16.0:
			st.position.x = right_x
		else:
			# No room beside the operation name: the status takes its own line, left aligned and cut to the column.
			remove_child(st)
			st.free()
			st = K.text(self, _fit(status, cap, w), cap.merged({"x": x0, "y": y + 28.0}, true))
			bottom = y + 28.0 + st.size.y
	return bottom


func _headline(vm: Dictionary, x0: float, y: float, victory: bool) -> float:
	var col: Color = T.TEXT_HI if victory else Color("ffd9d4")
	# CSS filter: drop-shadow(0 0 22px c): a Gaussian (sigma 11) of the glyph mask. Approximated by GLOW_COPIES faint copies
	# laid out on a golden-angle spiral whose radii follow that Gaussian.
	var tint: Color = T.CYAN if victory else Color("f04e46")
	var opts := {"x": x0, "y": y, "w": WIDTH - PAD_X - x0, "f": "disp", "wt": 600, "px": 76, "sp": 0.05, "lh": 76, "col": col, "up": true, "wrap": true}
	var title_text := str(vm.get("title", ""))
	for i in GLOW_COPIES:
		var r := GLOW_SIGMA * sqrt(-2.0 * log(1.0 - (i + 0.5) / GLOW_COPIES))
		var a := i * 2.399963
		var o := opts.duplicate()
		o["x"] = x0 + cos(a) * r
		o["y"] = y + sin(a) * r
		o["col"] = Color(tint.r, tint.g, tint.b, GLOW_ALPHA / GLOW_COPIES)
		K.text(self, title_text, o)
	var title := K.text(self, title_text, opts)
	var end: float = y + title.size.y
	var lede := str(vm.get("lede", ""))
	if lede != "":
		var body := K.text(self, lede, {"x": x0, "y": end + 12.0, "w": minf(760.0, WIDTH - PAD_X - x0), "px": 17, "lh": 25.5, "col": T.DIM if victory else Color("c9aaa6"), "wrap": true})
		end = body.position.y + body.size.y
	return end


func _stats(stats: Array, x0: float, w: float, y: float) -> float:
	var n := stats.size()
	var cw := (w - 10.0 * (n - 1)) / n
	for i in n:
		var s: Dictionary = stats[i]
		var x := x0 + i * (cw + 10.0)
		K.panel(self, x, y, roundf(x + cw) - roundf(x), 85)
		var label := {"f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true}
		K.text(self, _fit(str(s.get("label", "")), label, cw - 30), label.merged({"x": x + 15, "y": y + 13}))
		var value := {"f": "disp", "wt": 600, "px": 40, "sp": 0.02, "lh": 44, "col": T.tone(str(s.get("tone", "hi")))}
		K.text(self, _fit(str(s.get("value", "")), value, cw - 30), value.merged({"x": x + 15, "y": y + 28}))
	return y + 85.0


## Task 22: one panel, the grade on the left, the total with the personal best (and the New best flag) beside it, and
## the score rows (label left, signed value right) in the right half.
func _score(sc: Dictionary, x0: float, w: float, y: float) -> float:
	var rows: Array = sc.get("rows", [])
	var h := maxf(SCORE_MIN_H, 16.0 + rows.size() * SCORE_ROW_H + 14.0)
	K.panel(self, x0, y, w, h)
	var cap := {"f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true}
	K.text(self, "Grade", cap.merged({"x": x0 + 21, "y": y + 16}))
	var grade := str(sc.get("grade", ""))
	K.text(self, grade, {"x": x0 + 21, "y": y + 34, "f": "disp", "wt": 600, "px": 64, "lh": 64, "col": SCORE_GRADE_COLORS.get(grade, T.TEXT_HI)})
	var mid := x0 + 128.0
	K.text(self, "Score", cap.merged({"x": mid, "y": y + 16}))
	var value := {"f": "disp", "wt": 600, "px": 40, "sp": 0.02, "lh": 44, "col": T.TEXT_HI}
	var total := K.text(self, str(sc.get("total", "0")), value.merged({"x": mid, "y": y + 34}))
	var rows_x := x0 + w * 0.5
	if sc.has("best"):
		var best := K.text(self, "Best %s" % sc["best"], {"x": mid, "y": y + 34 + total.size.y + 8, "f": "mono", "px": 13, "sp": 0.03, "col": T.DIM})
		if sc.get("new_best", false):
			var chip := K.chip(self, mid + best.size.x + 12.0, best.position.y - 6.0, "", T.GOOD, [{"t": "New best", "col": T.GOOD, "px": 12, "sp": 0.12, "up": true}], {"border": T.GOOD})
			if chip.position.x + chip.size.x > rows_x - 16.0:
				chip.position = Vector2(roundf(mid), roundf(best.position.y + best.size.y + 6.0))
	var rw := x0 + w - 21.0 - rows_x
	var ry := y + 16.0
	for r in rows:
		var row_o := {"px": 14, "col": T.DIM}
		var v := K.text(self, str(r.get("value", "")), {"y": ry, "f": "mono", "px": 14, "col": T.TEXT})
		v.position.x = roundf(rows_x + rw - v.size.x)
		K.text(self, _fit(str(r.get("label", "")), row_o, rw - v.size.x - 12.0), row_o.merged({"x": rows_x, "y": ry}))
		ry += SCORE_ROW_H
	return y + h


func _casualties_and_economy(vm: Dictionary, x0: float, w: float, y: float) -> float:
	var cas: Dictionary = vm.get("casualties", {})
	var eco: Dictionary = vm.get("economy", {})
	var has_cas: bool = not cas.get("rows", []).is_empty()
	var has_eco: bool = not eco.get("series", []).is_empty()
	if not has_cas and not has_eco:
		return y - GAP
	var cas_w := 368.0 if has_eco else w
	var eco_w := w - cas_w - 16.0 if has_cas else w
	var height := 0.0
	if has_cas:
		height = 1.0 + 18.0 + 26.0 + 12.0 + 4.0 + _rows_h(cas["rows"].size()) + 12.0 + 17.0 + 18.0 + 1.0
	if has_eco:
		height = maxf(height, 301.0 + (_note_extra(eco, eco_w)))
	if has_cas:
		_casualties(cas, x0, y, cas_w, height)
	if has_eco:
		_economy(eco, x0 + (cas_w + 16.0 if has_cas else 0.0), y, eco_w, height)
	return y + height


func _rows_h(n: int) -> float:
	return n * 35.0 + maxi(n - 1, 0) * 14.0


func _note_extra(eco: Dictionary, w: float) -> float:
	var note := str(eco.get("note", ""))
	if note == "":
		return -25.0
	var probe := TextBox.new()
	probe.size = Vector2(w - 42.0, 0)
	probe.configure(note, {"px": 13, "wrap": true})
	var extra := probe.get_minimum_size().y - 17.0
	probe.free()
	return extra


func _section_title(title: String, right: String, x: float, y: float, w: float) -> void:
	K.text(self, title, {"x": x, "y": y, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "up": true})
	if right != "":
		var cap := K.text(self, right, {"y": y + 7, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
		cap.position.x = roundf(x + w - cap.size.x)


func _casualties(cas: Dictionary, x: float, y: float, w: float, h: float) -> void:
	K.panel(self, x, y, w, h)
	_section_title("Casualties", str(cas.get("right", "Lost / produced")), x + 21, y + 19, w - 42)
	var rows: Array = cas["rows"]
	var scale := 1.0
	for r in rows:
		scale = maxf(scale, float(r.get("produced", 0)))
	var iw := w - 42.0
	var ry := y + 61.0
	for r in rows:
		var name_o := {"px": 15}
		K.text(self, _fit(str(r.get("name", "")), name_o, iw - 70), name_o.merged({"x": x + 21, "y": ry}))
		var value := K.text(self, "%d / %d" % [int(r.get("lost", 0)), int(r.get("produced", 0))], {"y": ry, "f": "disp", "wt": 600, "px": 15, "sp": 0.02})
		value.position.x = roundf(x + 21 + iw - value.size.x)
		var track := K.panel(self, x + 21, ry + 23, iw, 12, "glass", {"fill": T.BAR_BG, "radius": 0, "light": false})
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner := iw - 2.0
		K.rule(self, x + 22, ry + 24, inner * float(r.get("produced", 0)) / scale, 10, SEG_OK)
		var lost_w := inner * float(r.get("lost", 0)) / scale
		if lost_w > 0.0:
			K.rule(self, x + 22, ry + 24, lost_w, 10, LOST)
		ry += 49.0
	var ly := y + h - 19.0 - 17.0
	K.rule(self, x + 21, ly + 2.5, 12, 12, LOST)
	K.text(self, "Lost", {"x": x + 39, "y": ly, "px": 13, "col": T.DIM})
	K.rule(self, x + 79.5, ly + 2.5, 12, 12, SEG_OK)
	K.text(self, "Produced", {"x": x + 97.5, "y": ly, "px": 13, "col": T.DIM})


func _economy(eco: Dictionary, x: float, y: float, w: float, h: float) -> void:
	K.panel(self, x, y, w, h)
	_section_title(str(eco.get("title", "Material stock")), str(eco.get("right", "")), x + 21, y + 19, w - 42)
	var o := eco.duplicate()
	o["width"] = w - 44.0
	var chart: Control = Chart.new()
	K.place(chart, x + 21, y + 57)
	add_child(chart)
	chart.setup(o)
	var note := str(eco.get("note", ""))
	if note != "":
		K.text(self, note, {"x": x + 21, "y": y + 265, "w": w - 42, "px": 13, "col": T.DIM, "wrap": true})


func _chips(chips: Array, x0: float, w: float, y: float) -> float:
	var x := x0
	var ry := y
	for c in chips:
		var tone: Color = T.tone(str(c.get("tone", "warn")))
		var chip := K.chip(self, x, ry, "", tone, [
			{"t": str(c.get("label", "")), "col": tone, "px": 12, "sp": 0.12, "up": true},
			{"t": str(c.get("value", ""))},
		], {"border": tone})
		if x > x0 and x + chip.size.x > x0 + w:
			x = x0
			ry += 38.0
			chip.position = Vector2(roundf(x), roundf(ry))
		x += chip.size.x + 10.0
	return ry + 28.0


func _timeline(tl: Dictionary, x0: float, w: float, y: float) -> float:
	var rows: Array = tl["rows"]
	var ticks: Array = tl.get("ticks", [])
	var h := 1.0 + 18.0 + 26.0 + 12.0 + rows.size() * 38.0 - 6.0 + 18.0 + 1.0
	if not ticks.is_empty() or tl.has("end"):
		h += 6.0 + 36.0
	K.panel(self, x0, y, w, h, "panel", {"border": DANGER_LINE})
	_section_title(str(tl.get("title", "")), str(tl.get("range", "")), x0 + 21, y + 19, w - 42)
	var ry := y + 57.0
	var tx := x0 + 21.0 + 120.0
	var tw := 684.0
	for row in rows:
		var row_o := {"px": 14}
		K.text(self, _fit(str(row.get("label", "")), row_o, 110.0), row_o.merged({"x": x0 + 21, "y": ry + 7}))
		var track := K.panel(self, tx, ry, tw, 32, "glass", {"fill": T.BAR_BG, "radius": 0, "light": false})
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for seg in row.get("segments", []):
			_segment(tx + 1.0 + float(seg.get("from", 0.0)) * tw, ry + 1.0, (float(seg.get("to", 1.0)) - float(seg.get("from", 0.0))) * tw, str(seg.get("text", "")), str(seg.get("tone", "ok")))
		if row.has("marker"):
			var mx: float = tx + 1.0 + float(row["marker"]) * tw
			K.rule(self, mx, ry, 2, 32, T.BAD)
			var d := _solid_diamond(mx + 1.0, ry + 15.0)
			add_child(d)
		ry += 38.0
	if not ticks.is_empty() or tl.has("end"):
		for t in ticks:
			K.text(self, str(t.get("t", "")), {"x": tx + float(t.get("at", 0.0)) * 685.0, "y": ry + 2, "f": "mono", "px": 12, "col": T.DIM})
		var end: Dictionary = tl.get("end", {})
		if not end.is_empty():
			var e := K.text(self, str(end.get("t", "")), {"y": ry + 2, "f": "mono", "px": 12, "col": T.tone(str(end.get("tone", "bad")))})
			e.position.x = roundf(tx + 685.0 - e.size.x)
	return y + h


func _segment(x: float, y: float, w: float, label: String, tone: String) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	K.place(holder, x, y, w, 30)
	add_child(holder)
	var bg := {"ok": SEG_OK, "warn": SEG_WARN, "bad": SEG_BAD}.get(tone, SEG_OK) as Color
	var ink := {"ok": T.TEXT, "warn": Color("ffe3ae"), "bad": Color("ffd9d4")}.get(tone, T.TEXT) as Color
	var fill := ColorRect.new()
	fill.color = bg
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(w, 30)
	holder.add_child(fill)
	K.text(holder, label, {"x": 8, "y": 7.5, "f": "mono", "px": 12, "sp": 0.06, "col": ink, "up": true})


func _solid_diamond(cx: float, cy: float) -> Control:
	var d := Control.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = Vector2(cx - 8.5, cy - 8.5)
	d.size = Vector2(17, 17)
	d.draw.connect(func(): d.draw_colored_polygon(PackedVector2Array([Vector2(8.5, 0), Vector2(17, 8.5), Vector2(8.5, 17), Vector2(0, 8.5)]), T.BAD))
	return d


func _chain(chain: Array, x0: float, w: float, y: float) -> float:
	var inner_x := x0 + 21.0
	var inner_w := w - 42.0
	var items: Array = []
	var cap := K.text(self, "Cause chain", {"f": "mono", "px": 12, "sp": 0.12, "col": T.BAD, "up": true})
	items.append([cap, 15.0, 0.0])
	for i in chain.size():
		var step: Dictionary = chain[i] if chain[i] is Dictionary else {"t": str(chain[i])}
		var final: bool = step.get("final", i == chain.size() - 1)
		var chip_text := _fit(str(step.get("t", "")), {"f": "mono", "px": 13}, inner_w - 22.0)
		var chip := K.chip(self, 0, 0, "", T.TEXT, [{"t": chip_text, "col": Color("ffd9d4") if final else T.TEXT}], {"border": T.BAD if final else T.LINE})
		items.append([chip, 28.0, 0.0])
		if i < chain.size() - 1:
			var arrow := K.text(self, "→", {"px": 16, "col": T.DIM})
			items.append([arrow, 20.0, 0.0])
	var rows: Array = [[]]
	var cx := 0.0
	for it in items:
		var iw: float = it[0].size.x
		if cx > 0.0 and cx + iw > inner_w:
			rows.append([])
			cx = 0.0
		rows[-1].append(it)
		cx += iw + 10.0
	var h := 1.0 + 14.0 + rows.size() * 28.0 + (rows.size() - 1) * 10.0 + 14.0 + 1.0
	var panel := K.panel(self, x0, y, w, h, "panel", {"border": DANGER_LINE})
	move_child(panel, items[0][0].get_index())
	var ry := y + 15.0
	for row in rows:
		var rx := inner_x
		for it in row:
			var node: Control = it[0]
			node.position = Vector2(roundf(rx), roundf(ry + (28.0 - it[1]) * 0.5))
			rx += node.size.x + 10.0
		ry += 38.0
	return y + h


func _teaser(tz: Dictionary, x0: float, w: float, y: float) -> float:
	var left := x0 + 79.0
	var tag: Control = null
	if str(tz.get("tag", "")) != "":
		tag = K.tag(self, str(tz["tag"]), left, y + 18.0, T.VIOLET)
	var title_o := {"f": "disp", "wt": 600, "px": 22, "sp": 0.04, "col": Color("e6dcff"), "up": true}
	var room := w - 79.0 - 21.0 - (tag.size.x + 10.0 if tag else 0.0)
	var title := K.text(self, _fit(str(tz.get("title", "")), title_o, maxf(room, 80.0)), title_o.merged({"x": left, "y": y + 15.0}))
	var head_h := 28.0
	if tag:
		tag.position.x = roundf(left + title.size.x + 10.0)
	var body := K.text(self, str(tz.get("body", "")), {"x": left, "y": y + 15.0 + head_h + 2.0, "w": w - 79.0 - 21.0, "px": 15, "wrap": true})
	var h := 2.0 + 28.0 + maxf(head_h + 2.0 + body.size.y, 40.0)
	var panel := _teaser_panel(x0, y, w, h)
	move_child(panel, (tag if tag else title).get_index())
	K.icon(self, "signature", x0 + 21.0, y + (h - 40.0) * 0.5, T.VIOLET, 40, 1.5)
	return y + h


func _teaser_panel(x: float, y: float, w: float, h: float) -> Control:
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(p, x, y, w, h)
	add_child(p)
	p.draw.connect(func():
		var left := Color(183.0 / 255.0, 156.0 / 255.0, 1.0, 0.14)
		var right := Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.9)
		# CSS interpolates gradients in premultiplied alpha; draw_polygon would not, so slice the span.
		var step := 4.0
		var i := 0.0
		while i < w:
			var t := (i + step * 0.5) / w
			var a := lerpf(left.a, right.a, t)
			var rgb := (Vector3(left.r, left.g, left.b) * left.a).lerp(Vector3(right.r, right.g, right.b) * right.a, t) / a
			p.draw_rect(Rect2(i, 0, minf(step, w - i), h), Color(rgb.x, rgb.y, rgb.z, a))
			i += step
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = T.VIOLET
		box.set_corner_radius_all(3)
		p.draw_style_box(box, Rect2(0, 0, w, h)))
	return p


func _advice(items: Array, x0: float, w: float, y: float) -> float:
	var title := K.text(self, "What to try next", {"x": x0, "y": y, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "up": true})
	var ry := y + title.size.y + 8.0
	for i in items.size():
		var body := K.text(self, str(items[i]), {"x": x0 + 53.0, "y": 0, "w": w - 2.0 - 32.0 - 22.0 - 14.0, "px": 16, "wrap": true})
		var h := maxf(52.0, 2.0 + 20.0 + body.size.y)
		K.panel(self, x0, ry, w, h, "glass")
		move_child(get_child(get_child_count() - 1), body.get_index())
		body.position.y = roundf(ry + (h - body.size.y) * 0.5)
		K.text(self, str(i + 1), {"x": x0 + 17.0, "y": ry + (h - 30.0) * 0.5, "f": "disp", "wt": 600, "px": 24, "sp": 0.02, "col": T.CYAN})
		ry += h + 8.0
	return ry - 8.0


func _buttons(buttons: Array, x0: float, w: float, y: float) -> void:
	if buttons.is_empty():
		return
	# CSS flex: G 1 0 on border-box buttons; the base size is the 38px of padding and border, free space splits by grow.
	var n := buttons.size()
	var grows: Array[float] = []
	var total := 0.0
	for b in buttons:
		grows.append(float(b.get("grow", 1.4 if b.get("primary", false) else 1.0)))
		total += grows[-1]
	var free := w - 12.0 * (n - 1) - 38.0 * n
	var x := x0
	for i in n:
		var b: Dictionary = buttons[i]
		var bw := 38.0 + free * grows[i] / total
		# Chrome snaps both edges of a fractional box to whole pixels.
		var node := K.button(self, str(b.get("label", "")), x, y, {"primary": b.get("primary", false), "w": roundf(x + bw) - roundf(x), "h": BUTTON_H})
		node.disabled = b.get("disabled", false)
		node.pressed.connect(_emit.bind(str(b.get("action", ""))))
		x += bw + 12.0


func _emit(name: String) -> void:
	action.emit(name, null)
