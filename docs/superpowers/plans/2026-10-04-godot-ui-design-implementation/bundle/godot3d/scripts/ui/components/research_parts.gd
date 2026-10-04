extends RefCounted
## Small self-drawing controls used only by the research screen: a bordered box (solid or dashed), a radial backdrop,
## a checkbox, a project card, the edge layer, the zoom knob track and the gate arrow. Each draws itself; the screen
## owns layout. Gfx pattern is Chrome's: dash 3 x border width, gap 2 x border width, fitted per edge.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Layout = preload("res://scripts/ui/research_layout.gd")

const BACKDROP_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.0, 0.0);
uniform vec2 radii = vec2(100.0, 100.0);
uniform vec4 c0 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 c1 = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stop = 1.0;
varying vec2 pos;
void vertex() { pos = VERTEX; }
void fragment() {
	float t = clamp(length((pos - center) / radii) / stop, 0.0, 1.0);
	vec4 m = mix(vec4(c0.rgb * c0.a, c0.a), vec4(c1.rgb * c1.a, c1.a), t);
	COLOR = m.a > 0.0 ? vec4(m.rgb / m.a, m.a) : vec4(0.0);
}
"""

static var _shader: Shader = null


static func _backdrop_material(center: Vector2, radii: Vector2, c0: Color, c1: Color, stop: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BACKDROP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("radii", radii)
	mat.set_shader_parameter("c0", Vector4(c0.r, c0.g, c0.b, c0.a))
	mat.set_shader_parameter("c1", Vector4(c1.r, c1.g, c1.b, c1.a))
	mat.set_shader_parameter("stop", stop)
	return mat


## A rectangle filled with an elliptical radial gradient (CSS `radial-gradient(rx ry at cx cy, c0, c1 stop)`).
static func radial(parent: Node, rect: Rect2, center: Vector2, radii: Vector2, c0: Color, c1: Color, stop := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = rect.position
	r.size = rect.size
	r.material = _backdrop_material(center, radii, c0, c1, stop)
	parent.add_child(r)
	return r


class Gfx extends RefCounted:
	## Gfxed rectangle outline drawn as crisp axis-aligned runs. `inset` pulls the corners in (rounded radius).
	static func dashed_rect(ci: CanvasItem, rect: Rect2, w: float, color: Color, inset := 3.0) -> void:
		var l := rect.position.x
		var t := rect.position.y
		var r := rect.end.x
		var b := rect.end.y
		_dash_run(ci, Vector2(l + inset, t), Vector2(r - inset, t), w, color, true)
		_dash_run(ci, Vector2(l + inset, b - w), Vector2(r - inset, b - w), w, color, true)
		_dash_run(ci, Vector2(l, t + inset), Vector2(l, b - inset), w, color, false)
		_dash_run(ci, Vector2(r - w, t + inset), Vector2(r - w, b - inset), w, color, false)


	static func _dash_run(ci: CanvasItem, a: Vector2, b: Vector2, w: float, color: Color, horizontal: bool) -> void:
		var length := (b.x - a.x) if horizontal else (b.y - a.y)
		if length <= 0.0:
			return
		var dash := 3.0 * w
		var gap := 2.0 * w
		var count := maxi(1, roundi((length + gap) / (dash + gap)))
		var fitted := (length - count * dash) / float(count - 1) if count > 1 else 0.0
		if count > 1 and fitted < 1.0:
			count -= 1
			fitted = (length - count * dash) / float(count - 1) if count > 1 else 0.0
		for i in count:
			var s := i * (dash + fitted)
			var from := roundf(s)
			var to := roundf(s + dash)
			if horizontal:
				ci.draw_rect(Rect2(a.x + from, a.y, to - from, w), color)
			else:
				ci.draw_rect(Rect2(a.x, a.y + from, w, to - from), color)

	static var _stripes: Dictionary = {}


	## Pixels of `repeating-linear-gradient(135deg, A 0 6px, B 6px 12px)` over a w x h box (the blocked card background).
	static func stripe_texture(w: int, h: int) -> Texture2D:
		var key := "%dx%d" % [w, h]
		if _stripes.has(key):
			return _stripes[key]
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var a := Color(240.0 / 255.0, 176.0 / 255.0, 64.0 / 255.0, 0.10)
		var b := Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.95)
		var half := (w + h) * 0.70710678 * 0.5
		for y in h:
			for x in w:
				var t := ((x + 0.5 - w * 0.5) + (y + 0.5 - h * 0.5)) * 0.70710678 + half
				img.set_pixel(x, y, a if fposmod(t, 12.0) < 6.0 else b)
		var tex := ImageTexture.create_from_image(img)
		_stripes[key] = tex
		return tex


	## CSS box-shadow with blur: rings of falling alpha outside `rect` (sigma = blur / 2, no spread).
	static func shadow(ci: CanvasItem, rect: Rect2, radius: int, color: Color, blur: float) -> void:
		var sigma := blur * 0.5
		for i in range(1, int(blur) + 1):
			var z := (i - 0.5) / sigma
			var a := color.a * 0.5 * (1.0 - tanh(0.7978845608 * (z + 0.044715 * z * z * z)))
			if a < 0.004:
				continue
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(1)
			sb.border_color = Color(color.r, color.g, color.b, a)
			sb.set_corner_radius_all(radius + i)
			ci.draw_style_box(sb, rect.grow(i))


## Bordered rectangle: optional fill, solid or dashed border, optional corner radius.
class Box extends Control:
	var fill := Color(0, 0, 0, 0)
	var border := T.LINE
	var bw := 1.0
	var dashed := false
	var radius := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(fill_color: Color, border_color: Color, dash := false, corner := 0, width := 1.0) -> Control:
		fill = fill_color
		border = border_color
		dashed = dash
		radius = corner
		bw = width
		queue_redraw()
		return self

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if fill.a > 0.0:
			draw_rect(rect, fill)
		if border.a <= 0.0:
			return
		if dashed:
			Gfx.dashed_rect(self, rect, bw, border, float(radius))
		else:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(int(bw))
			sb.border_color = border
			sb.set_corner_radius_all(radius)
			draw_style_box(sb, rect)


## The 18px filter checkbox (.cb / .cb.on).
class Check extends Control:
	var on := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(18, 18)
		size = Vector2(18, 18)
		Icons.texture("check_thin", 14, 2.4)

	func setup(checked: bool) -> Control:
		on = checked
		queue_redraw()
		return self

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if on:
			draw_rect(rect, T.ACTIVE)
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(1)
		sb.border_color = T.CYAN if on else T.FAINT
		sb.set_corner_radius_all(2)
		draw_style_box(sb, rect)
		if on:
			var tex := Icons.cached("check_thin", 14, 2.4)
			if tex:
				draw_texture(tex, Vector2(2, 2), T.TEXT_HI)


## The arrow between the two era chips in the gate strip (34x20 viewBox, stroke 2, round caps).
class GateArrow extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(34, 20)
		size = Vector2(34, 20)

	func _draw() -> void:
		draw_line(Vector2(2, 10), Vector2(28, 10), T.CYAN_HI, 2.0, true)
		draw_polyline(PackedVector2Array([Vector2(22, 4), Vector2(29, 10), Vector2(22, 16)]), T.CYAN_HI, 2.0, true)
		draw_circle(Vector2(2, 10), 1.0, T.CYAN_HI)
		draw_circle(Vector2(22, 4), 1.0, T.CYAN_HI)
		draw_circle(Vector2(22, 16), 1.0, T.CYAN_HI)


## The zoom slider: 4px track and a 14px glowing knob at `value` (0..1).
class ZoomTrack extends Control:
	var value := 0.0
	var dragging := false
	signal changed(value: float)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func setup(v: float) -> Control:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
		return self

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				_set_from(event.position.x)
		elif event is InputEventMouseMotion and dragging:
			_set_from(event.position.x)

	func _set_from(x: float) -> void:
		var v := clampf((x - 7.0) / maxf(size.x - 14.0, 1.0), 0.0, 1.0)
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()
			changed.emit(v)

	func _draw() -> void:
		var cy := size.y * 0.5
		draw_rect(Rect2(0, cy - 2, size.x, 4), T.LINE_DIM)
		var cx := 7.0 + value * (size.x - 14.0)
		for i in range(1, 8):
			draw_circle(Vector2(cx, cy), 7.0 + i, Color(T.CYAN_HI.r, T.CYAN_HI.g, T.CYAN_HI.b, 0.7 * pow(1.0 - i / 8.0, 2.0) * 0.35), true, -1.0, true)
		draw_circle(Vector2(cx, cy), 7.0, T.CYAN_HI, true, -1.0, true)


## Dependency edges under the cards. `edges`: Array of {points: PackedVector2Array, kind: "normal"|"unknown"|"path"}.
class EdgeLayer extends Control:
	var edges: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(list: Array) -> Control:
		edges = list
		queue_redraw()
		return self

	func _draw() -> void:
		# Same paint order as the mock: plain edges, then the dashed unknown edge, then the highlighted path on top.
		for kind in ["normal", "unknown", "path"]:
			for e in edges:
				if e["kind"] == kind:
					_edge(e["points"], kind)

	func _edge(pts: PackedVector2Array, kind: String) -> void:
		if pts.size() < 2:
			return
		var stroke := 2.0
		var line_col := Color("3a6a7e")
		var head_col := T.FAINT
		var scale := 1.6
		if kind == "unknown":
			line_col = T.VIOLET
			head_col = T.VIOLET
		elif kind == "path":
			stroke = 4.0
			line_col = T.CYAN_HI
			head_col = T.CYAN_HI
			scale = 2.8
		var last := pts[pts.size() - 1]
		var dir := (last - pts[pts.size() - 2]).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var norm := Vector2(-dir.y, dir.x)
		var straight := pts.size() == 2 and is_equal_approx(pts[0].y, pts[1].y)
		var tip := last + dir * (1.0 * scale)
		var back := last - dir * (7.0 * scale)
		var tri := PackedVector2Array([tip, back + norm * (4.0 * scale), back - norm * (4.0 * scale)])
		if kind == "path":
			# drop-shadow(0 0 6px rgba(150,245,255,.7)): stacked translucent layers, widest first
			for k in range(6, 0, -1):
				var halo := Color(T.CYAN_HI.r, T.CYAN_HI.g, T.CYAN_HI.b, 0.04)
				if straight:
					var grown := Rect2(pts[0].x - k, pts[0].y - stroke * 0.5 - k, pts[1].x - pts[0].x + 2.0 * k, stroke + 2.0 * k)
					draw_rect(grown, halo)
				else:
					draw_polyline(pts, halo, stroke + 2.0 * k, true)
				var grown_tri := Geometry2D.offset_polygon(tri, float(k), Geometry2D.JOIN_ROUND)
				for poly in grown_tri:
					draw_colored_polygon(poly, halo)
		if kind == "unknown":
			_dashed_polyline(pts, line_col, stroke, 5.0, 5.0)
		elif straight:
			draw_rect(Rect2(pts[0].x, pts[0].y - stroke * 0.5, pts[1].x - pts[0].x, stroke), line_col)
		else:
			draw_polyline(pts, line_col, stroke, true)
			draw_circle(pts[0], stroke * 0.5, line_col)
		# Marker: viewBox triangle (1,1)(9,5)(1,9) about refX 8 refY 5, scaled by markerWidth x strokeWidth / 10.
		draw_colored_polygon(tri, head_col)

	func _dashed_polyline(pts: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
		var travelled := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var d := (b - a) / maxf(seg, 0.001)
			var at := 0.0
			while at < seg:
				var phase := fmod(travelled + at, dash + gap)
				if phase < dash:
					var run := minf(dash - phase, seg - at)
					if is_equal_approx(a.y, b.y):
						draw_rect(Rect2(a.x + at, a.y - width * 0.5, run, width), color)
					else:
						draw_line(a + d * at, a + d * (at + run), color, width, true)
					at += run
				else:
					at += (dash + gap) - phase
			travelled += seg



## A project card: background, border, glow and the three progress cells. Texts, tags and the icon are child nodes.
class Card extends Control:
	var state := "available"
	var bw := 1
	var selected := false
	var hovered := false
	var seg_cells: Array = []
	var seg_x := 0.0
	var seg_y := 0.0
	var seg_w := 0.0
	var seg_dashed := false
	var _stripe: Texture2D = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(st: String, border_w: int, is_selected: bool) -> Control:
		state = st
		bw = border_w
		selected = is_selected
		if st == "blocked":
			_stripe = Gfx.stripe_texture(int(size.x) - 2 * bw, int(size.y) - 2 * bw)
		queue_redraw()
		return self

	## cells: Array of {ratio: float, col: Color}; x/y/w locate the row of cells (w = row width, 5px gaps).
	func set_cells(cells: Array, x: float, y: float, w: float, dashed: bool) -> void:
		seg_cells = cells
		seg_x = x
		seg_y = y
		seg_w = w
		seg_dashed = dashed
		queue_redraw()

	func set_hover(on: bool) -> void:
		if hovered != on:
			hovered = on
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if selected:
			Gfx.shadow(self, rect, 3, Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.35), 30.0)
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_border_width_all(3)
			ring.border_color = Color(T.CYAN_HI.r, T.CYAN_HI.g, T.CYAN_HI.b, 0.25)
			ring.set_corner_radius_all(6)
			draw_style_box(ring, rect.grow(3))
		elif state == "active":
			Gfx.shadow(self, rect, 3, Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.18), 22.0)
		_fill(rect)
		if hovered:
			draw_rect(rect, Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.07))
		var edge := _edge_color()
		if state == "planned" or state == "unknown":
			Gfx.dashed_rect(self, rect, float(bw), edge, 3.0)
		else:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(bw)
			sb.border_color = edge
			sb.set_corner_radius_all(3)
			draw_style_box(sb, rect)
		if hovered and not selected:
			var hr := StyleBoxFlat.new()
			hr.draw_center = false
			hr.set_border_width_all(1)
			hr.border_color = Color(T.CYAN_HI.r, T.CYAN_HI.g, T.CYAN_HI.b, 0.55)
			hr.set_corner_radius_all(4)
			draw_style_box(hr, rect.grow(1))
		_cells()

	func _edge_color() -> Color:
		if selected:
			return T.CYAN_HI
		match state:
			"implemented": return Color("2f6a5a")
			"active", "available": return T.CYAN
			"blocked": return T.WARN
			"planned": return Color("6d93a4")
			"unknown": return T.VIOLET
		return T.LINE

	func _fill(rect: Rect2) -> void:
		var top := Color.TRANSPARENT
		var bot := Color.TRANSPARENT
		match state:
			"implemented":
				top = Color("10262a")
				bot = Color("0a1a1e")
			"active":
				top = Color("0f3340")
				bot = Color("0a202c")
			"available":
				top = Color("0b1d2a")
				bot = top
			"planned":
				top = Color("08111a")
				bot = top
			"unknown":
				top = Color("150f26")
				bot = top
			"blocked":
				if _stripe:
					draw_texture(_stripe, Vector2(bw, bw))
				return
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([top, top, bot, bot]))

	func _cells() -> void:
		var n := seg_cells.size()
		if n == 0:
			return
		var w := (seg_w - 5.0 * (n - 1)) / n
		for i in n:
			var x0 := roundf(seg_x + i * (w + 5.0))
			var x1 := roundf(seg_x + i * (w + 5.0) + w)
			var cell := Rect2(x0, seg_y, x1 - x0, 8.0)
			var ratio: float = seg_cells[i]["ratio"]
			var col: Color = seg_cells[i]["col"]
			draw_rect(cell, T.BAR_BG)
			var border := T.LINE
			if ratio >= 1.0:
				draw_rect(cell, col)
				border = col
			elif ratio > 0.0:
				var inner := cell.grow(-1)
				draw_rect(Rect2(inner.position, Vector2(roundf(inner.size.x * ratio), inner.size.y)), col)
			if seg_dashed:
				Gfx.dashed_rect(self, cell, 1.0, border, 0.0)
			else:
				var sb := StyleBoxFlat.new()
				sb.draw_center = false
				sb.set_border_width_all(1)
				sb.border_color = border
				draw_style_box(sb, cell)


## The numbered step badge on a card (26px disc, glow). The number is a child text node.
class Badge extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 26)
		size = Vector2(26, 26)

	func _draw() -> void:
		var c := Vector2(13, 13)
		for i in range(1, 15):
			draw_circle(c, 13.0 + i, Color(T.CYAN_HI.r, T.CYAN_HI.g, T.CYAN_HI.b, 0.6 * 0.5 * (1.0 - tanh(0.7978845608 * (((i - 0.5) / 7.0) + 0.044715 * pow((i - 0.5) / 7.0, 3.0)))) * 0.6), false, 1.0, true)
		draw_circle(c, 13.0, T.CYAN_HI, true, -1.0, true)


## A flat filled disc (the step number in the path list).
class Disc extends Control:
	var color: Color = T.CYAN_HI

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(c: Color, px: float) -> Control:
		color = c
		size = Vector2(px, px)
		custom_minimum_size = size
		queue_redraw()
		return self

	func _draw() -> void:
		draw_circle(size * 0.5, size.x * 0.5, color, true, -1.0, true)


## Wheel and drag-to-pan surface for the graph. Children (cards) get their clicks first; empty space pans.
class Pane extends Control:
	signal panned(delta: Vector2)
	signal wheel(direction: int, shift: bool)
	var _drag := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
				_drag = event.pressed
			elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
				wheel.emit(1, event.shift_pressed)
			elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				wheel.emit(-1, event.shift_pressed)
		elif event is InputEventMouseMotion and _drag:
			panned.emit(event.relative)
