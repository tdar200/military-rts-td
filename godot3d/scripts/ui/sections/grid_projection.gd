extends RefCounted
## Projected grid panel (board 2, left above the minimap): load after the armed building against generation, a bar of
## current load / planned load that fits / planned load over capacity (hatched), and one line of advice. Driven by
## vm["power_grid"]: {y?, value, tone, segments, marker, lead, text} (build_logic.projection's maths). Read-only; builds
## nothing without the slice.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const HatchFill = preload("res://scripts/ui/components/hatch_fill.gd")

const X := 12.0
const Y := 560.0
const W := 332.0
const PAD_X := 14.0
const PAD_Y := 12.0
const BAR_H := 14.0


class Frame extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), T.BAR_BG)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = T.LINE_DIM
		draw_style_box(box, Rect2(Vector2.ZERO, size))


static func _tone(name: String) -> Color:
	match name:
		"warn":
			return T.WARN
		"bad":
			return T.BAD
		"good":
			return T.GOOD
	return T.CYAN


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("power_grid", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var y := float(d.get("y", Y))
	var panel := K.panel(parent, X, y, W, 10.0)
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var top := y + 1.0 + PAD_Y
	var value := K.text(parent, str(d.get("value", "")), {"x": 0, "y": top, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": _tone(str(d.get("tone", "cyan"))), "up": true})
	value.position.x = roundf(cx + cw - value.size.x)
	var cap := K.text(parent, "Projected grid", {"x": cx, "y": top + 10.0, "f": "mono", "px": 12, "sp": 0.12, "lh": 15, "col": T.DIM, "up": true})
	var bar_y := roundf(top + value.size.y + 6.0)
	var frame := Frame.new()
	K.place(frame, cx, bar_y, cw, BAR_H)
	parent.add_child(frame)
	var inner := cw - 2.0
	var sx := cx + 1.0
	for seg in d.get("segments", []):
		var w := roundf(inner * float(seg.get("ratio", 0.0)))
		if w <= 0.0:
			continue
		if str(seg.get("tone", "")) == "bad_hatch":
			var hatch := HatchFill.new()
			K.place(hatch, sx, bar_y + 1.0, w, BAR_H - 2.0)
			parent.add_child(hatch)
		else:
			K.rule(parent, sx, bar_y + 1.0, w, BAR_H - 2.0, _tone(str(seg.get("tone", "cyan"))))
		sx += w
	if d.has("marker"):
		K.rule(parent, cx + 1.0 + roundf(inner * float(d["marker"])), bar_y - 5.0, 2, 22, T.TEXT)
	var at := bar_y + BAR_H + 6.0
	var lead := str(d.get("lead", ""))
	var text := str(d.get("text", ""))
	if lead != "" or text != "":
		var indent := ""
		if lead != "":
			var lead_box := K.text(parent, lead, {"x": cx, "y": at, "f": "mono", "px": 13, "lh": 17, "col": T.BAD})
			var space := K.text(parent, " ", {"px": 13})
			var n := ceili((lead_box.size.x + space.size.x) / maxf(space.size.x, 1.0))
			space.free()
			indent = " ".repeat(n)
		var body := K.text(parent, indent + text, {"x": cx, "y": at, "w": cw, "px": 13, "lh": 17, "col": T.DIM, "wrap": true})
		at += body.size.y if text != "" else 17.0
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
