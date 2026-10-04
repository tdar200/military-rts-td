extends Control
## World-space annotations drawn over the 3D scene and under the HUD: selection brackets and ground rings, hostile
## diamonds with HP bars, the impact zone, supply links, order arrows, the Core beam, the countdown ring and labelled
## callouts. Not a Hud section on purpose: the host projects marks every frame and calls `set_marks` with screen-space
## coordinates; only callout text rebuilds, and only when its content changes.
##
## Mark = {kind, x, y, ...} in screen pixels (the viewport is this control's size, 1920x1080 by default):
##   brackets  x y w h                       friendly selection box, square corners
##   ring      x y [rx=48 ry=20 dashed tone]  selected unit ground ellipse, (x, y) is the centre; dashed is a thin
##                                           dashed range line in `tone` (cyan or good) instead of the glowing selection ring
##   hostile   x y hp [w=50]                 red diamond centred on (x, y) with an HP bar under it; dropped when off-screen
##   impact    x y r [inner]                 hatched danger disc centred on (x, y)
##   link      x y c1 c2 to [dim tone broken width]  supply path (cubic: start, two control points, end). Power lines pass
##                                           tone ok|warn|bad (cyan, amber, red), a width in px and broken (dotted, with a cross)
##   arrow     x y c1 c2 to [queued]         attack-move path with a head; queued is dotted
##   beam      x y c1 c2 to                  the Core's charge line (dashed, no head)
##   countdown x y value total [sub]         ring around (x, y), value in the middle
##   badge     x y text                      numbered step marker, (x, y) is its top-left; text longer than 2 characters
##                                           makes a pill sized by badge_size
##   border    segs tone(own|enemy)          territory outline: segs = [[Vector2 a, Vector2 b], ...] in screen pixels
##   callout   x y ...                       glass label, (x, y) is its top-left; forms below
##       tag form    {tag, tag_tone, text, border?}
##       title form  {title, sub, border?}
##       card form   {title, tag, tag_tone, ratio, body, w?, tone?}
## A callout that is not fully on screen is pinned inside the viewport with an arrow towards where it really is (`tx`,
## `ty` when given, otherwise its own position).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const A = preload("res://scripts/ui/assault/util.gd")
const Tag = preload("res://scripts/ui/components/tag.gd")

const MARGIN := 12.0
const ARROW_LEN := 14.0
const BAD_BAR := Color("5a1e1a")
const DEFAULT_SIZE := Vector2(1920, 1080)

## Marks after the last `set_marks`: hostile marks that survived and every callout with its final rect.
var resolved: Array = []
var dropped := 0

var _marks: Array = []
var _callouts: Array = []
var _callout_nodes: Array = []
var _callout_sig := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = DEFAULT_SIZE


func _ready() -> void:
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _viewport() -> Rect2:
	var s := size if size.x > 0.0 and size.y > 0.0 else DEFAULT_SIZE
	return Rect2(Vector2.ZERO, s)


func set_marks(marks: Array) -> void:
	_marks = marks
	_layout()
	queue_redraw()


# ---------------------------------------------------------------- layout

func _layout() -> void:
	resolved = []
	dropped = 0
	_callouts = []
	var view := _viewport()
	for m in _marks:
		var kind := str(m.get("kind", ""))
		var at := Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0)))
		if kind == "hostile" or kind == "badge":
			if not view.has_point(at):
				dropped += 1
				continue
		if kind == "callout":
			_callouts.append(m)
			continue
		resolved.append({"kind": kind, "mark": m})
	_sync_callouts(view)


func _sync_callouts(view: Rect2) -> void:
	var sig := hash(_callouts.map(func(c: Dictionary) -> Dictionary:
		var d := c.duplicate()
		for k in ["x", "y", "tx", "ty"]:
			d.erase(k)
		return d))
	if sig != _callout_sig:
		_callout_sig = sig
		for n in _callout_nodes:
			remove_child(n)
			n.queue_free()
		_callout_nodes = []
		for c in _callouts:
			_callout_nodes.append(_build_callout(c))
	for i in _callouts.size():
		var c: Dictionary = _callouts[i]
		var node: Control = _callout_nodes[i]
		var want := Rect2(Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0))), node.size)
		var placed := _pin(want, view, c)
		node.position = placed["rect"].position.round()
		resolved.append({"kind": "callout", "mark": c, "rect": placed["rect"], "clamped": placed["clamped"], "arrow": placed["arrow"], "tip": placed["tip"]})


## Keep a callout on screen. Returns {rect, clamped, arrow: "" | left | right | top | bottom, tip: Vector2}.
func _pin(want: Rect2, view: Rect2, c: Dictionary) -> Dictionary:
	if view.encloses(want):
		return {"rect": want, "clamped": false, "arrow": "", "tip": Vector2.ZERO}
	var inner := view.grow(-(MARGIN + ARROW_LEN))
	var pos := Vector2(
		clampf(want.position.x, inner.position.x, maxf(inner.position.x, inner.end.x - want.size.x)),
		clampf(want.position.y, inner.position.y, maxf(inner.position.y, inner.end.y - want.size.y)))
	var rect := Rect2(pos, want.size)
	var target := Vector2(float(c.get("tx", want.get_center().x)), float(c.get("ty", want.get_center().y)))
	var d := target - rect.get_center()
	var side := ""
	if absf(d.x) >= absf(d.y):
		side = "right" if d.x > 0.0 else "left"
	else:
		side = "bottom" if d.y > 0.0 else "top"
	return {"rect": rect, "clamped": true, "arrow": side, "tip": _arrow_tip(rect, side)}


func _arrow_tip(rect: Rect2, side: String) -> Vector2:
	match side:
		"left": return Vector2(rect.position.x - ARROW_LEN, rect.get_center().y)
		"right": return Vector2(rect.end.x + ARROW_LEN, rect.get_center().y)
		"top": return Vector2(rect.get_center().x, rect.position.y - ARROW_LEN)
		_: return Vector2(rect.get_center().x, rect.end.y + ARROW_LEN)


# ---------------------------------------------------------------- callout nodes

func _build_callout(c: Dictionary) -> Control:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	var edge: Color = A.tone(str(c["border"])) if c.has("border") else T.LINE_DIM
	var panel: Control
	if c.has("ratio"):
		panel = _card(node, c)
	elif c.has("title"):
		var title := K.text(node, str(c["title"]), {"x": 11, "y": 5, "f": "disp", "wt": 600, "px": 15, "sp": 0.04, "col": T.CYAN_HI, "up": true})
		var sub := K.text(node, str(c.get("sub", "")), {"x": 11.0 + title.size.x + 8.0, "y": 7, "f": "mono", "px": 12, "col": T.DIM})
		var w := 1.0 + 10.0 + title.size.x + 8.0 + sub.size.x + 10.0 + 1.0
		panel = K.panel(node, 0, 0, w, 29, "glass", {"border": T.LINE if not c.has("border") else edge})
		node.size = Vector2(w, 29)
	else:
		var tag := Tag.new()
		K.place(tag, 13, 7)
		node.add_child(tag)
		tag.setup(str(c.get("tag", "")), A.tone(str(c.get("tag_tone", "bad"))))
		var text := K.text(node, str(c.get("text", "")), {"x": 13.0 + tag.size.x + 10.0, "y": 9, "px": 14})
		var w2 := 1.0 + 12.0 + tag.size.x + 10.0 + text.size.x + 12.0 + 1.0
		panel = K.panel(node, 0, 0, w2, 36, "glass", {"border": edge})
		node.size = Vector2(w2, 36)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.move_child(panel, 0)
	return node


## The emitter card: title and tag on one row (the title wraps before the tag shrinks), a bar, then wrapped body text.
func _card(node: Control, c: Dictionary) -> Control:
	var w := float(c.get("w", 236.0))
	var inner := w - 26.0
	var tag := Tag.new()
	node.add_child(tag)
	tag.setup(str(c.get("tag", "")), A.tone(str(c.get("tag_tone", "bad"))))
	var title_text := str(c.get("title", ""))
	var avail := inner - tag.size.x
	var natural := A.width("disp", 16, 600, 0.04, title_text.to_upper())
	var wraps := natural > avail - 0.2
	var title := K.text(node, title_text, {"x": 13, "y": 11, "w": avail - 0.2 if wraps else natural + 1.0, "f": "disp", "wt": 600, "px": 16, "sp": 0.04, "col": A.BAD_SOFT, "up": true, "wrap": wraps})
	var row_h := maxf(title.size.y, 22.0)
	title.position.y = roundf(11.0 + (row_h - title.size.y) * 0.5)
	K.place(tag, 13.0 + inner - tag.size.x, 11.0 + (row_h - 22.0) * 0.5)
	var y := 11.0 + row_h + 6.0
	_bar(node, 13, y, inner, float(c.get("ratio", 0.0)))
	y += 6.0 + 6.0
	var body_h := 0.0
	if str(c.get("body", "")) != "":
		var body := K.text(node, str(c["body"]), {"x": 13, "y": y, "w": inner, "px": 13, "lh": 17.55, "col": T.TEXT, "wrap": true})
		body_h = body.size.y
	var h := y + body_h + 10.0 + 1.0
	node.size = Vector2(w, h)
	var edge: Color = A.tone(str(c.get("tone", "bad")))
	var panel := K.panel(node, 0, 0, w, h, "glass", {"border": edge})
	return panel


func _bar(parent: Control, x: float, y: float, w: float, ratio: float) -> Control:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(b, x, y, w, 6)
	parent.add_child(b)
	b.draw.connect(func() -> void: _draw_bar(b, Rect2(Vector2.ZERO, Vector2(w, 6)), ratio))
	return b


func _draw_bar(ci: CanvasItem, rect: Rect2, ratio: float) -> void:
	ci.draw_rect(rect, T.BAR_BG)
	var inner := rect.grow(-1)
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(ratio, 0.0, 1.0), inner.size.y)), T.BAD)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = BAD_BAR
	ci.draw_style_box(box, rect)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	for pass_kinds in [["border"], ["impact", "link"], ["hostile"], ["ring"], ["brackets", "arrow", "beam", "countdown"], ["badge"]]:
		for r in resolved:
			if r["kind"] in pass_kinds:
				_draw_mark(r["kind"], r["mark"])
	for r in resolved:
		if r["kind"] == "callout" and r["clamped"]:
			_draw_edge_arrow(r)


func _draw_mark(kind: String, m: Dictionary) -> void:
	var at := Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0)))
	match kind:
		"brackets": _brackets(Rect2(at, Vector2(float(m.get("w", 0.0)), float(m.get("h", 0.0)))))
		"ring":
			if m.get("dashed", false):
				_range_ring(at, float(m.get("rx", 48.0)), float(m.get("ry", 20.0)), T.tone(str(m.get("tone", "cyan"))))
			else:
				_ring(at, float(m.get("rx", 48.0)), float(m.get("ry", 20.0)))
		"hostile": _hostile(at, float(m.get("hp", 1.0)), float(m.get("w", 50.0)))
		"impact": _impact(at, float(m.get("r", 215.0)), float(m.get("inner", m.get("r", 215.0) * 0.7)))
		"link": _link(at, m)
		"arrow": _arrow(at, m)
		"beam": _beam(at, m)
		"countdown": _countdown(at, m)
		"badge": _badge(at, str(m.get("text", "")))
		"border": _border(m)


static func _pt(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	return Vector2(float(v[0]), float(v[1]))


static func bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, steps := 96) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p1)
	return out


## SVG stroke-dasharray along a polyline. Round caps add a half-width disc at each end of every dash.
func _dashed(points: PackedVector2Array, on: float, off: float, width: float, color: Color, round_caps := false) -> void:
	var drawing := true
	var left := on
	var current := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while seg - pos > left:
			pos += left
			var p := a.lerp(b, pos / seg)
			if drawing:
				current.append(p)
				_dash(current, width, color, round_caps)
				current = PackedVector2Array()
			else:
				current = PackedVector2Array([p])
			drawing = not drawing
			left = on if drawing else off
		left -= seg - pos
		if drawing:
			current.append(b)
	if drawing and current.size() > 1:
		_dash(current, width, color, round_caps)


func _dash(pts: PackedVector2Array, width: float, color: Color, round_caps: bool) -> void:
	draw_polyline(pts, color, width, true)
	if round_caps:
		draw_circle(pts[0], width * 0.5, color)
		draw_circle(pts[pts.size() - 1], width * 0.5, color)


func _head(tip: Vector2, tangent: Vector2, stroke: float, color: Color) -> void:
	var s := 0.75 * stroke
	var dir := tangent.normalized()
	var nor := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for v in [Vector2(-8, -5), Vector2(2, 0), Vector2(-8, 5)]:
		pts.append(tip + dir * v.x * s + nor * v.y * s)
	draw_colored_polygon(pts, color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), color, 1.0, true)


func _curve(at: Vector2, m: Dictionary) -> PackedVector2Array:
	return bezier(at, _pt(m.get("c1", at)), _pt(m.get("c2", at)), _pt(m.get("to", at)))


func _link(at: Vector2, m: Dictionary) -> void:
	var pts := _curve(at, m)
	if m.has("tone"):
		_power_line(pts, m)
	elif m.get("dim", false):
		_dashed(pts, 6.0, 6.0, 2.0, T.LINE_DIM)
	else:
		_dashed(pts, 3.0, 9.0, 3.0, T.CYAN, true)


## A power line: solid in the tone's colour, as thick as `width`; a broken one is red, dotted and crossed halfway.
func _power_line(pts: PackedVector2Array, m: Dictionary) -> void:
	var width := float(m.get("width", 3.0))
	var tone_name := str(m.get("tone", "ok"))
	var color: Color = T.CYAN if tone_name == "ok" else T.tone(tone_name)
	if m.get("broken", false):
		_dashed(pts, 3.0, 8.0, width, color, true)
		var mid := pts[pts.size() / 2]
		draw_circle(mid, 12.0, Color(T.BG2.r, T.BG2.g, T.BG2.b, 0.9))
		draw_arc(mid, 12.0, 0.0, TAU, 32, color, 2.0, true)
		draw_line(mid + Vector2(-6, -6), mid + Vector2(6, 6), color, 2.0, true)
		draw_line(mid + Vector2(6, -6), mid + Vector2(-6, 6), color, 2.0, true)
	else:
		draw_polyline(pts, color, width, true)
		draw_circle(pts[0], width * 0.5, color)
		draw_circle(pts[pts.size() - 1], width * 0.5, color)


func _arrow(at: Vector2, m: Dictionary) -> void:
	var pts := _curve(at, m)
	var tangent := pts[pts.size() - 1] - pts[pts.size() - 2]
	if m.get("queued", false):
		_dashed(pts, 2.0, 9.0, 3.0, T.CYAN, true)
		_head(pts[pts.size() - 1], tangent, 3.0, T.CYAN)
	else:
		draw_polyline(pts, T.CYAN_HI, 4.0, true)
		draw_circle(pts[0], 2.0, T.CYAN_HI)
		_head(pts[pts.size() - 1], tangent, 4.0, T.CYAN_HI)


func _beam(at: Vector2, m: Dictionary) -> void:
	_dashed(_curve(at, m), 10.0, 8.0, 2.5, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.9))


func _brackets(r: Rect2) -> void:
	const ARM := 26.0
	const W := 3.0
	var h := W * 0.5
	for corner in [[r.position, 1.0, 1.0], [Vector2(r.end.x, r.position.y), -1.0, 1.0], [Vector2(r.position.x, r.end.y), 1.0, -1.0], [r.end, -1.0, -1.0]]:
		var c: Vector2 = corner[0]
		var sx: float = corner[1]
		var sy: float = corner[2]
		draw_rect(_span(c.x - h, c.x + h, c.y - h * sy, c.y + (ARM + h) * sy), T.CYAN_HI)
		draw_rect(_span(c.x - h * sx, c.x + (ARM + h) * sx, c.y - h, c.y + h), T.CYAN_HI)


static func _span(x0: float, x1: float, y0: float, y1: float) -> Rect2:
	return Rect2(minf(x0, x1), minf(y0, y1), absf(x1 - x0), absf(y1 - y0))


func _ellipse(c: Vector2, rx: float, ry: float, steps := 72) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ring(c: Vector2, rx: float, ry: float) -> void:
	for d in range(14, 0, -1):
		var a := 0.5 * _tail(float(d) / 7.0)
		var pts := _ellipse(c, rx + d, ry + d)
		pts.append(pts[0])
		draw_polyline(pts, Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, a), 1.0, true)
	draw_colored_polygon(_ellipse(c, rx, ry), Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.06))
	var edge := _ellipse(c, rx - 1.0, ry - 1.0)
	edge.append(edge[0])
	draw_polyline(edge, T.CYAN, 2.0, true)


## A coverage or reach ring: thin dashed ellipse over a faint wash, no glow (several can be on screen at once).
func _range_ring(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := _ellipse(c, rx, ry, 120)
	pts.append(pts[0])
	draw_colored_polygon(_ellipse(c, rx, ry, 120), Color(color.r, color.g, color.b, 0.05))
	_dashed(pts, 8.0, 8.0, 1.5, Color(color.r, color.g, color.b, 0.55))


func _border(m: Dictionary) -> void:
	var color: Color = T.BAD if str(m.get("tone", "own")) == "enemy" else T.CYAN
	for seg in m.get("segs", []):
		draw_line(seg[0], seg[1], Color(color.r, color.g, color.b, 0.28), 7.0, true)
		draw_line(seg[0], seg[1], color, 3.0, true)


## Upper tail of the standard normal (logistic approximation): how much of a gaussian shadow reaches z sigmas out.
static func _tail(z: float) -> float:
	return 1.0 / (1.0 + exp(1.702 * z))


func _hostile(c: Vector2, hp: float, bar_w: float) -> void:
	var half := 12.0 * 0.70710678 - 0.5
	var prior := 0.0
	for d in range(10, 0, -1):
		var target := 0.5 * _tail((float(d) - 0.5) / 4.5)
		var a := 1.0 - (1.0 - target) / (1.0 - prior)
		prior = target
		draw_colored_polygon(_rounded_diamond(c, half, float(d)), Color(T.BAD.r, T.BAD.g, T.BAD.b, a))
	var pts := _rounded_diamond(c, half, 0.0)
	draw_colored_polygon(pts, T.BAD)
	pts.append(pts[0])
	draw_polyline(pts, T.BAD, 1.0, true)
	_draw_bar(self, Rect2(Vector2(roundf(c.x - bar_w * 0.5), roundf(c.y + 10.0)), Vector2(bar_w, 6)), hp)


## A diamond of half-diagonal `half` grown by `grow` px in every direction (corners become arcs of radius `grow`).
static func _rounded_diamond(c: Vector2, half: float, grow: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0)]
	for i in 4:
		if grow <= 0.0:
			pts.append(c + corners[i])
			continue
		var a0 := deg_to_rad(-135.0 + 90.0 * i)
		for s in 7:
			var a := a0 + deg_to_rad(90.0) * s / 6.0
			pts.append(c + corners[i] + Vector2(cos(a), sin(a)) * grow)
	return pts


func _impact(c: Vector2, r: float, inner: float) -> void:
	var n := Vector2(0.70710678, 0.70710678)
	var t := Vector2(-0.70710678, 0.70710678)
	var centre_dot := c.dot(n)
	## The mock's pattern tile clips its 3px stroke to the tile, so each hatch line is the 1.5px right half of the stroke.
	var k0 := int(ceil((centre_dot - r - 0.75) / 14.0))
	var k1 := int(floor((centre_dot + r - 0.75) / 14.0))
	var hatch := Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.45)
	for k in range(k0, k1 + 1):
		var off := 14.0 * k + 0.75 - centre_dot
		var half_chord := sqrt(maxf(r * r - off * off, 0.0))
		var mid := c + n * off
		draw_line(mid - t * half_chord, mid + t * half_chord, hatch, 1.5, true)
	draw_circle(c, r, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.07))
	var rim := PackedVector2Array()
	for i in 361:
		var a := TAU * i / 360.0
		rim.append(c + Vector2(cos(a), sin(a)) * r)
	_dashed(rim, 14.0, 8.0, 3.0, T.BAD)
	draw_arc(c, inner, 0.0, TAU, 96, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.6), 1.5, true)


func _countdown(c: Vector2, m: Dictionary) -> void:
	var value := float(m.get("value", 0.0))
	var total := maxf(float(m.get("total", 1.0)), 0.001)
	draw_circle(c, 46.0, Color(8.0 / 255.0, 15.0 / 255.0, 24.0 / 255.0, 0.88))
	draw_arc(c, 46.0, 0.0, TAU, 96, Color("3a1815"), 8.0, true)
	var ratio := clampf(value / total, 0.0, 1.0)
	if ratio > 0.0:
		draw_arc(c, 46.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 96, T.BAD, 8.0, true)
	var big := T.font("disp", 700)
	var shown := str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
	var w := big.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	draw_string(big, Vector2(c.x - w * 0.5, c.y + 10.0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("ffe8e6"))
	var sub := str(m.get("sub", "OF %d S" % int(total)))
	var mono := T.font("mono", 0)
	var step := T.MONO_ADVANCE * 12.0 + 1.5
	var x0 := c.x - sub.length() * step * 0.5
	for i in sub.length():
		if sub[i] != " ":
			draw_char(mono, Vector2(x0 + i * step, c.y + 38.0), sub[i], 12, Color("f4b3ae"))


## A badge is a 22px disc for one or two characters, a pill of the same height for longer text.
static func badge_size(s: String) -> Vector2:
	if s.length() <= 2:
		return Vector2(22, 22)
	return Vector2(ceilf(s.length() * T.MONO_ADVANCE * 12.0) + 16.0, 22)


func _badge(top_left: Vector2, s: String) -> void:
	if s.length() > 2:
		_pill_badge(top_left, s)
		return
	var c := top_left + Vector2(11, 11)
	draw_circle(c, 11.0, T.BG2)
	draw_arc(c, 10.25, 0.0, TAU, 48, T.CYAN, 1.5, true)
	var f := T.font("mono", 0)
	var asc := T.ascent(f, 12)
	var base := top_left.y + (22.0 - (asc + T.descent(f, 12))) * 0.5 + asc
	var x0 := c.x - s.length() * T.MONO_ADVANCE * 12.0 * 0.5
	for i in s.length():
		draw_char(f, Vector2(x0 + i * T.MONO_ADVANCE * 12.0, base), s[i], 12, T.CYAN_HI)


func _pill_badge(top_left: Vector2, s: String) -> void:
	var size := badge_size(s)
	var box := StyleBoxFlat.new()
	box.bg_color = T.BG2
	box.set_border_width_all(1)
	box.border_color = T.CYAN
	box.set_corner_radius_all(11)
	draw_style_box(box, Rect2(top_left, size))
	var f := T.font("mono", 0)
	var asc := T.ascent(f, 12)
	var base := top_left.y + (22.0 - (asc + T.descent(f, 12))) * 0.5 + asc
	var x0 := top_left.x + (size.x - s.length() * T.MONO_ADVANCE * 12.0) * 0.5
	for i in s.length():
		draw_char(f, Vector2(x0 + i * T.MONO_ADVANCE * 12.0, base), s[i], 12, T.CYAN_HI)


func _draw_edge_arrow(r: Dictionary) -> void:
	var rect: Rect2 = r["rect"]
	var tip: Vector2 = r["tip"]
	var tone := A.tone(str(r["mark"].get("tone", r["mark"].get("border", "bad"))))
	if str(r["mark"].get("border", "")) == "" and str(r["mark"].get("tone", "")) == "":
		tone = T.CYAN
	var half := 9.0
	var pts: PackedVector2Array
	match str(r["arrow"]):
		"left", "right":
			var x := rect.position.x if r["arrow"] == "left" else rect.end.x
			pts = PackedVector2Array([Vector2(x, tip.y - half), tip, Vector2(x, tip.y + half)])
		_:
			var y := rect.position.y if r["arrow"] == "top" else rect.end.y
			pts = PackedVector2Array([Vector2(tip.x - half, y), tip, Vector2(tip.x + half, y)])
	draw_colored_polygon(pts, tone)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color("ffd2cf"), 1.5, true)
