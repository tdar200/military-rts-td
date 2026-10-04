extends Control
## The debrief's material-stock chart: filled line over time with wave markers (W1..), relay diamonds and an end value.
## Geometry is the mock's 420x200 SVG: plot area x 40..width-10, y 24 (top) .. 150 (zero line).
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const PLOT_LEFT := 40.0
const PLOT_TOP := 24.0
const PLOT_BOTTOM := 150.0
const RELAY := Color("f06050")

var series: Array = []  # [[seconds, value], ...] ascending in time
var duration := 1.0
var y_max := 1.0
var waves: Array = []  # seconds
var marks: Array = []  # [{t: seconds, label: String}]
var final_label := ""
var _labels: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## o: width (default 420), series, duration (seconds, default last sample time), waves, marks, final_label (default the last value).
func setup(o: Dictionary) -> Control:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	series = o.get("series", [])
	var last_t := float(series[-1][0]) if series.size() > 0 else 1.0
	duration = maxf(float(o.get("duration", last_t)), 1.0)
	waves = o.get("waves", [])
	marks = o.get("marks", [])
	var top := 0.0
	for p in series:
		top = maxf(top, float(p[1]))
	y_max = float(o.get("y_max", nice_ceiling(top)))
	var w := float(o.get("width", 420))
	custom_minimum_size = Vector2(w, 200)
	size = custom_minimum_size
	final_label = str(o.get("final_label", group(roundi(float(series[-1][1]))) if series.size() > 0 else ""))
	_build_labels()
	queue_redraw()
	return self


## 1,420 -> 1,500; 130 -> 150; step sets keep the axis ticks readable.
static func nice_ceiling(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var mag := pow(10.0, floor(log(v) / log(10.0)))
	for m in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
		if v <= m * mag + 0.000001:
			return m * mag
	return 10.0 * mag


static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


## The mock labels a 12:01 run every 3:00; longer runs step up so the axis never carries more than about four labels.
static func tick_step(seconds: float) -> float:
	for step in [30.0, 60.0, 120.0, 180.0, 300.0, 600.0, 900.0, 1800.0, 3600.0, 7200.0]:
		if seconds / step <= 4.1:
			return step
	return ceilf(seconds / 4.0 / 3600.0) * 3600.0


static func clock(seconds: float) -> String:
	var s := roundi(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func plot_right() -> float:
	return size.x - 10.0


func x_at(t: float) -> float:
	return PLOT_LEFT + (plot_right() - PLOT_LEFT) * clampf(t / duration, 0.0, 1.0)


func y_at(v: float) -> float:
	return PLOT_BOTTOM - (PLOT_BOTTOM - PLOT_TOP) * clampf(v / y_max, 0.0, 1.0)


func value_at(t: float) -> float:
	if series.is_empty():
		return 0.0
	for i in series.size():
		if float(series[i][0]) >= t:
			if i == 0:
				return float(series[0][1])
			var a: Array = series[i - 1]
			var b: Array = series[i]
			var span := maxf(float(b[0]) - float(a[0]), 0.000001)
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / span)
	return float(series[-1][1])


func _label(s: String, o: Dictionary, x: float, y: float, anchor: String) -> void:
	var box := TextBox.new()
	add_child(box)
	box.configure(s, o)
	var m := box.get_minimum_size()
	box.size = m
	var left := x
	if anchor == "end":
		left = x - m.x
	elif anchor == "middle":
		left = x - m.x * 0.5
	box.position = Vector2(roundf(left), roundf(y))
	_labels.append(box)


func _build_labels() -> void:
	var mono := {"f": "mono", "px": 12, "col": T.DIM}
	for tick in [[PLOT_TOP, 1.0], [87.0, 0.5], [PLOT_BOTTOM, 0.0]]:
		_label(group(roundi(y_max * tick[1])), mono, 34.0, tick[0] - 8.0, "end")
	var warn := {"f": "mono", "px": 12, "col": T.WARN}
	var last_x := -1000.0
	for i in waves.size():
		var wx := x_at(float(waves[i]))
		# Wave lines are always drawn; a label is dropped when it would sit on the previous one.
		if wx - last_x >= 26.0:
			_label("W%d" % (i + 1), warn, wx, 6.0, "middle")
			last_x = wx
	var relay := {"f": "mono", "px": 12, "col": RELAY}
	for m in marks:
		var t := float(m.get("t", 0.0))
		_label(str(m.get("label", "")), relay, x_at(t), y_at(value_at(t)) + 14.0, "middle")
	var step := tick_step(duration)
	var t := 0.0
	var right_edge := plot_right() - 6.0
	var end_text := clock(duration)
	var end_w := end_text.length() * T.MONO_ADVANCE * 12.0
	while t < duration - 1.0:
		var x := x_at(t)
		# The last tick label is the end time, right-aligned; skip ticks that would collide with it.
		if x + 14.4 < right_edge - end_w - 4.0:
			_label(clock(t), mono, x, 160.0, "middle")
		t += step
	_label(end_text, mono, right_edge, 160.0, "end")
	if series.size() > 0 and final_label != "":
		var last: Array = series[-1]
		_label(final_label, {"f": "disp", "wt": 600, "px": 18, "col": T.TEXT_HI}, right_edge, y_at(float(last[1])) + 6.0, "end")


## A 1px SVG stroke centred on coordinate c covers two pixel columns (rows) unless c is a half integer; split its alpha the same way.
func _vline(x: float, y0: float, y1: float, color: Color) -> void:
	var first := floorf(x - 0.5)
	var f := x - 0.5 - first
	if f < 0.001:
		draw_rect(Rect2(first, y0, 1, y1 - y0), color)
		return
	draw_rect(Rect2(first, y0, 1, y1 - y0), Color(color, color.a * (1.0 - f)))
	draw_rect(Rect2(first + 1.0, y0, 1, y1 - y0), Color(color, color.a * f))


func _hline(y: float, x0: float, x1: float, color: Color) -> void:
	var first := floorf(y - 0.5)
	var f := y - 0.5 - first
	if f < 0.001:
		draw_rect(Rect2(x0, first, x1 - x0, 1), color)
		return
	draw_rect(Rect2(x0, first, x1 - x0, 1), Color(color, color.a * (1.0 - f)))
	draw_rect(Rect2(x0, first + 1.0, x1 - x0, 1), Color(color, color.a * f))


func _draw() -> void:
	var right := plot_right()
	_hline(PLOT_TOP, PLOT_LEFT, right, T.LINE_DIM)
	_hline(87.0, PLOT_LEFT, right, T.LINE_DIM)
	_hline(PLOT_BOTTOM, PLOT_LEFT, right, T.LINE)
	for t in waves:
		var x := x_at(float(t))
		var y := 30.0
		while y < PLOT_BOTTOM:
			_vline(x, y, minf(y + 3.0, PLOT_BOTTOM), T.WARN)
			y += 7.0
	if series.is_empty():
		return
	var pts := PackedVector2Array()
	for p in series:
		pts.append(Vector2(x_at(float(p[0])), y_at(float(p[1]))))
	var fill := Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.14)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		draw_colored_polygon(PackedVector2Array([a, b, Vector2(b.x, PLOT_BOTTOM), Vector2(a.x, PLOT_BOTTOM)]), fill)
	if pts.size() > 1:
		draw_polyline(pts, T.CYAN, 2.5, true)
	for m in marks:
		var t := float(m.get("t", 0.0))
		var c := Vector2(x_at(t), y_at(value_at(t)))
		var d := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 0), c + Vector2(0, 8), c + Vector2(-6, 0)])
		draw_colored_polygon(d, RELAY)
		draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), T.BG1, 1.5, true)
	draw_circle(pts[-1], 4.0, T.CYAN_HI)
