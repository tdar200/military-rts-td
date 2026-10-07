extends RefCounted
## Control groups list (board 5, top left): slots 1 to 4, then any assigned 5 to 9, each with a key cap, the group's main unit
## and its size (every row is ROW_STEP tall, so the adapter stacks the cards under it from the slot count). Driven by
## vm["control_groups"] ({slots: [{n, count, label, on}], y}); builds nothing without it. An assigned slot is a Button that
## emits ("recall_group", n), the same as pressing the number key; an empty slot reads "empty" and is not clickable.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")

const X := 12.0
const Y := 76.0
const W := 200.0
const PAD_X := 12.0
const PAD_Y := 10.0
const ROW_GAP := 5.0
## One slot row: the key cap's height plus the gap below it.
const ROW_STEP: float = KeyCap.HEIGHT + ROW_GAP


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var d = vm.get("control_groups", null)
	if not (d is Dictionary) or (d.get("slots", []) as Array).is_empty():
		return
	var y := float(d.get("y", Y))
	var panel := K.panel(parent, X, y, W, 10.0)
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var at := y + 1.0 + PAD_Y
	var cap := K.text(parent, "Control groups", {"x": cx, "y": at, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	at += cap.size.y + 6.0
	for slot in d["slots"]:
		var n := int(slot.get("n", 0))
		var count := int(slot.get("count", 0))
		var on: bool = bool(slot.get("on", false))
		var key := K.key(parent, str(n), cx, at, {"border": T.CYAN, "col": T.CYAN_HI} if on else {})
		var h: float = key.size.y
		if count > 0:
			var label := K.text(parent, str(slot.get("label", "")), {"x": cx + key.size.x + 8.0, "y": 0, "px": 14, "col": T.TEXT})
			label.position.y = roundf(at + (h - label.size.y) * 0.5)
			var num := K.text(parent, str(count), {"x": 0, "y": 0, "f": "mono", "px": 14, "col": T.DIM})
			num.position = Vector2(roundf(cx + cw - num.size.x), roundf(at + (h - num.size.y) * 0.5))
			var hit := K.hit(parent, cx, at, cw, h, "Group %d" % n)
			if emit.is_valid():
				hit.pressed.connect(emit.bind("recall_group", n))
		else:
			var empty := K.text(parent, "empty", {"x": cx + key.size.x + 8.0, "y": 0, "px": 14, "col": T.DIM})
			empty.position.y = roundf(at + (h - empty.size.y) * 0.5)
		at += h + ROW_GAP
	at -= ROW_GAP
	panel.size.y = roundf(at + PAD_Y + 1.0 - y)
	panel.queue_redraw()
