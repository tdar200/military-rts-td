extends RefCounted
## Enemy territory card (board 3, left): what the snapshot holds of the alien side. Driven by vm["enemy"]: {y?, rows}.
## The caption is plain "Enemy territory" (R6) and nothing is estimated: without fog every count is exact; under Kestrel's
## presentation fog the rows count what the player knows (in sight, last seen, share scouted). Read-only; builds nothing
## without rows.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")

const X := 12.0
const Y := 262.0
const W := 332.0
const PAD_X := 14.0
const PAD_Y := 12.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("enemy", null)
	if not (d is Dictionary) or not (d.get("rows", []) is Array) or d.get("rows", []).is_empty():
		return
	var y := float(d.get("y", Y))
	var panel := K.panel(parent, X, y, W, 10.0)
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var top := y + 1.0 + PAD_Y
	var cap := K.text(parent, "Enemy territory", {"x": cx, "y": top, "f": "mono", "px": 12, "sp": 0.12, "lh": 15, "col": T.BAD, "up": true})
	var end := top + cap.size.y + Rows.build(parent, cx, top + cap.size.y, cw, d["rows"])
	panel.size.y = roundf(end + PAD_Y + 1.0 - y)
	panel.queue_redraw()
