extends RefCounted
## Site card (board 4, top left): what surrounds the building that is selected (ground, nearest forest edge, nearest ford).
## Driven by vm["site"] ({cap, rows, y}); builds nothing without rows. The board's "Supply range" row has no data and is not
## built. `y` lets the adapter stack it below the objectives card (default 76, the board's value).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")

const X := 12.0
const Y := 76.0
const W := 332.0
const PAD_X := 14.0
const PAD_Y := 12.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("site", null)
	if not (d is Dictionary) or d.is_empty() or (d.get("rows", []) as Array).is_empty():
		return
	var y := float(d.get("y", Y))
	var panel := K.panel(parent, X, y, W, 10.0)
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var at := y + 1.0 + PAD_Y
	var cap := K.text(parent, str(d.get("cap", "")), {"x": cx, "y": at, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	at += cap.size.y
	at += Rows.build(parent, cx, at, cw, d["rows"])
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
