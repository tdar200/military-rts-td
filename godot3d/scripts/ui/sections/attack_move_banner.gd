extends RefCounted
## Armed banner (board 5, top centre): shown while the next click will carry an order. Driven by vm["armed"]
## ({hint, title, tone, icon}); title defaults to "Attack-move armed" in the board's red with a crosshair, and the Set rally
## arming uses the same banner with its own wording, a cyan tone and a flag. Builds nothing without a hint. It floats over the map and swallows no clicks, because the right click
## that carries the order lands under it. The hint is the game's real wording (a right click, not the board's left click).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const Y := 80.0
const SCREEN_W := 1920.0
const PAD_X := 22.0
const PAD_Y := 8.0
const GAP := 14.0
const ICON := 22


static func build(parent: Control, vm: Dictionary) -> void:
	var d = vm.get("armed", null)
	if not (d is Dictionary) or d.is_empty():
		return
	var tone := str(d.get("tone", "bad"))
	var edge := T.tone(tone) if tone != "" else T.BAD
	var ink := T.BAD_HI if tone == "bad" else T.TEXT_HI
	var panel := K.panel(parent, 0, Y, 10.0, 10.0, "panel", {"border": edge, "glow": Color(edge.r, edge.g, edge.b, 0.3)})
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := K.text(parent, str(d.get("title", "Attack-move armed")), {"f": "disp", "wt": 600, "px": 24, "sp": 0.16, "col": ink, "up": true})
	var sub := K.text(parent, str(d.get("hint", "")), {"px": 13, "col": T.DIM})
	var inner_h := maxf(float(ICON), maxf(title.size.y, sub.size.y))
	var w := 2.0 + 2.0 * PAD_X + ICON + GAP + title.size.x + GAP + sub.size.x
	var h := 2.0 + 2.0 * PAD_Y + inner_h
	var x := roundf((SCREEN_W - w) * 0.5)
	K.place(panel, x, Y, w, h)
	panel.queue_redraw()
	var cx := x + 1.0 + PAD_X
	var mid := Y + h * 0.5
	K.icon(parent, str(d.get("icon", "crosshair")), cx, mid - ICON * 0.5, edge, ICON, 2.0)
	cx += ICON + GAP
	title.position = Vector2(roundf(cx), roundf(mid - title.size.y * 0.5))
	cx += title.size.x + GAP
	sub.position = Vector2(roundf(cx), roundf(mid - sub.size.y * 0.5))
