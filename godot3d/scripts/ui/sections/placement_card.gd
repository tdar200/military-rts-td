extends RefCounted
## Placement card (board 2): the card that follows the cursor while a building is armed. Driven by vm["placing"]:
## {x, y, title, status, tone, footprint, rows}, where rows are the label / value rows rows.gd draws. The board's 4 x 3
## footprint and slope are not built: footprints are single hexes (R1) and the snapshot has no slope, so the status tag
## and the footprint line say "1 hex". The status reads "1 hex is clear" / "1 hex is blocked": like the board's "1 tile
## blocked" it is wide enough that the title wraps to two lines, so the card keeps one height as the cursor moves between
## clear and blocked hexes. Read-only; builds nothing without the slice.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")

const W := 340.0
const PAD_X := 14.0
const PAD_Y := 12.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("placing", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var x := float(d.get("x", 604.0))
	var y := float(d.get("y", 690.0))
	var panel := K.panel(parent, x, y, W, 10.0)
	# It floats over the map: a click that lands on it must still reach the hex underneath.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cx := x + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var top := y + 1.0 + PAD_Y
	var tone: Color = T.GOOD if str(d.get("tone", "warn")) == "good" else T.WARN
	var tag := K.tag(parent, str(d.get("status", "")), 0, 0, tone)
	var title := K.text(parent, "Placing %s" % str(d.get("title", "")), {"x": cx, "y": top, "w": cw - tag.size.x, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "lh": 28, "col": T.TEXT_HI, "up": true, "wrap": true})
	var head := maxf(title.size.y, tag.size.y)
	tag.position = Vector2(roundf(cx + cw - tag.size.x), roundf(top + (head - tag.size.y) * 0.5))
	var at := top + head + 2.0
	var sub := K.text(parent, str(d.get("footprint", "")), {"x": cx, "y": at, "w": cw, "px": 13, "lh": 17, "col": T.DIM})
	at += sub.size.y
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		at += 8.0
		at += Rows.build(parent, cx, at, cw, rows)
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
