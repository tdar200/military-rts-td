extends RefCounted
## Combat preview (board 3): the card beside a hostile target while human units are selected. Driven by vm["combat"]:
## {x, y, sub, rows}. The board's health bars ("320 -> 110", "-96 spread over 4"), "range 7 tiles" and "walls in the
## line" need weapon, armour and line-of-fire data the snapshot does not carry, so only the matchup and the ground rows
## are built. Read-only; builds nothing without the slice.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")

const W := 330.0
const PAD_X := 14.0
const PAD_Y := 12.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("combat", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var x := float(d.get("x", 1060.0))
	var y := float(d.get("y", 360.0))
	var panel := K.panel(parent, x, y, W, 10.0, "panel", {"border": T.BAD})
	# It floats over the map: a click that lands on it must still reach the hex underneath.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cx := x + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var top := y + 1.0 + PAD_Y
	var title := K.text(parent, "Combat preview", {"x": cx, "y": top, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "lh": 26, "col": T.TEXT_HI, "up": true})
	var tag := K.tag(parent, "Attack", 0, 0, T.BAD)
	tag.position = Vector2(roundf(cx + cw - tag.size.x), roundf(top + (title.size.y - tag.size.y) * 0.5))
	var at := top + title.size.y
	var sub := K.text(parent, str(d.get("sub", "")), {"x": cx, "y": at, "w": cw, "px": 13, "lh": 17, "col": T.DIM, "wrap": true})
	at += sub.size.y
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		at += 8.0
		at += Rows.build(parent, cx, at, cw, rows)
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
