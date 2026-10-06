extends Control
## Unit dots and the camera frustum drawn over the live minimap, and on Kestrel the alert pings: a red ring that pulses
## where one of the player's units or buildings was hit (alert_pings.gd).
const T = preload("res://scripts/ui/tokens.gd")
const AlertPings = preload("res://scripts/ui/alert_pings.gd")

## A ping ring grows from RING_MIN to RING_MAX pixels through each pulse.
const RING_MIN := 3.0
const RING_MAX := 15.0

var _marks: Array = []
var _view: Dictionary = {}
var _pinged := false  # a ping mark is in _marks, so the clock redraws
var _now := 0.0  # the alert clock (set_clock); a ping's age is _now minus its hit time


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## marks: [{x, y, k}] with x,y in 0..1 of this control; k is "f" friendly square, "e" elite square, "h" hostile diamond, "H" large hostile diamond,
## "p" alert ping (with t, the alert clock at its hit; drawn as a pulsing ring from set_clock's time).
## view: {x, y, w, h} in the same space, the camera frustum.
func setup(marks: Array, view: Dictionary) -> Control:
	_marks = marks
	_view = view
	_pinged = false
	for mark in marks:
		if str(mark.get("k", "")) == "p":
			_pinged = true
	queue_redraw()
	return self


## The alert clock, every frame the game runs (a paused game stops calling, so the rings hold still). True when it asked
## for a redraw: only while a ping mark is up. The rings are drawn by this control itself, no node and no material per ping.
func set_clock(now: float) -> bool:
	if not _pinged:
		return false
	_now = now
	queue_redraw()
	return true


## A ping ring hit at `t0` seen at `now`: {radius px, alpha, core alpha}; {} before its hit and from AlertPings.LIFE on.
static func ring(t0: float, now: float) -> Dictionary:
	var age := now - t0
	if age < 0.0 or age >= AlertPings.LIFE:
		return {}
	var p: Dictionary = AlertPings.pulse(age)
	var phase: float = p["phase"]
	var fade: float = p["fade"]
	return {"radius": lerpf(RING_MIN, RING_MAX, phase), "alpha": (1.0 - phase) * 0.95 * fade, "core": 0.9 * fade}


func _draw() -> void:
	for mark in _marks:
		var u := float(mark.get("x", -1.0))
		var v := float(mark.get("y", -1.0))
		if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
			continue
		var at := Vector2(u * size.x, v * size.y)
		match str(mark.get("k", "f")):
			"f":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), T.CYAN)
			"e":
				draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), T.CYAN_HI)
			"h", "H":
				var r := 6.4 if str(mark.get("k")) == "h" else 7.8
				var outer := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
				draw_colored_polygon(outer, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.35))
				outer.append(outer[0])
				draw_polyline(outer, T.BAD, 2.0, true)
	for mark in _marks:  # pings over the unit marks they point at
		if str(mark.get("k", "")) != "p":
			continue
		var r := ring(float(mark.get("t", 0.0)), _now)
		if r.is_empty():
			continue
		var at := Vector2(float(mark.get("x", 0.0)) * size.x, float(mark.get("y", 0.0)) * size.y)
		draw_arc(at, float(r["radius"]), 0.0, TAU, 32, Color(T.BAD.r, T.BAD.g, T.BAD.b, float(r["alpha"])), 2.0, true)
		draw_arc(at, 4.0, 0.0, TAU, 20, Color(T.BAD_HI.r, T.BAD_HI.g, T.BAD_HI.b, float(r["core"])), 1.5, true)
	if not _view.is_empty():
		var rect := Rect2(float(_view.get("x", 0.0)) * size.x, float(_view.get("y", 0.0)) * size.y, float(_view.get("w", 0.0)) * size.x, float(_view.get("h", 0.0)) * size.y)
		rect = rect.intersection(Rect2(Vector2.ZERO, size))
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			for i in range(1, 7):
				var halo := Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.4 * pow(1.0 - i / 7.0, 2.0) * 0.5)
				draw_rect(rect.grow(i), halo, false, 1.0)
			draw_rect(rect, T.CYAN_HI, false, 1.5)
