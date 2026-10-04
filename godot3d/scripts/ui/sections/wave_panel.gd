extends RefCounted
## Wave panel (board 7, top left): the next wave's number, a tag, a one-line hint and its rows (time, size, doctrine,
## direction, crossings). Driven by vm["wave_panel"] ({cap, tag, title, rows, y}) from VmGameplay.wave_panel; read-only,
## builds nothing without it. The board's "5 left of 12" and "2 prongs" have no data and are not built.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Rows = preload("res://scripts/ui/sections/rows.gd")

const X := 12.0
const Y := 76.0
const W := 332.0
const PAD_X := 14.0
const PAD_Y := 12.0


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("wave_panel", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var y := float(d.get("y", Y))
	var panel := K.panel(parent, X, y, W, 10.0, "panel", {"border": T.DANGER_EDGE})
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var at := y + 1.0 + PAD_Y
	var cap := K.text(parent, str(d.get("cap", "")), {"x": cx, "y": at, "f": "mono", "px": 12, "sp": 0.12, "col": T.BAD, "up": true})
	var row_h: float = cap.size.y
	if str(d.get("tag", "")) != "":
		var tag := K.tag(parent, str(d["tag"]), 0, 0, T.BAD)
		tag.position = Vector2(roundf(cx + cw - tag.size.x), roundf(at + (cap.size.y - tag.size.y) * 0.5))
		row_h = maxf(row_h, tag.size.y)
		cap.position.y = roundf(at + (row_h - cap.size.y) * 0.5)
	at += row_h
	if str(d.get("title", "")) != "":
		at += 4.0
		var title := K.text(parent, str(d["title"]), {"x": cx, "y": at, "w": cw, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "col": T.TEXT_HI, "up": true, "wrap": true})
		at += title.size.y
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		at += Rows.build(parent, cx, at, cw, rows)
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
