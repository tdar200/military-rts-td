extends RefCounted
## Map picker (New operation on the title): a scrim over the title, then one panel with a card per map and the Back and
## Deploy forces buttons. Built from LiveScreens.picker_vm() with the pause menu's kit; `emit` is Callable(name, arg) and
## receives pick (the card's map id), back and confirm. Each card is one invisible click target named after its map (QA
## and tests find it by that name). Builds nothing for {}; returns the Deploy forces button (the host focuses it).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const SCRIM := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.78)
const PANEL_X := 440.0
const PANEL_Y := 214.0
const PANEL_W := 1040.0
const PAD := 26.0
const CARD_GAP := 20.0
const CARD_PAD := 22.0
const BTN_H := 56.0
const RING := Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.55)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> Control:
	var cards: Array = vm.get("cards", [])
	if vm.is_empty() or cards.is_empty():
		return null
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP  # the title under the picker takes no clicks
	parent.add_child(scrim)
	var panel := K.panel(parent, PANEL_X, PANEL_Y, PANEL_W, 10.0)
	var cx := PANEL_X + 1.0 + PAD
	var cw := PANEL_W - 2.0 - 2.0 * PAD
	var y := PANEL_Y + 1.0 + PAD
	var cap := K.text(parent, str(vm.get("cap", "")), {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	y += cap.size.y + 4.0
	var title := K.text(parent, str(vm.get("title", "")), {"x": cx, "y": y, "f": "disp", "wt": 600, "px": 44, "sp": 0.04, "lh": 46, "col": T.TEXT_HI, "up": true})
	y += title.size.y + 22.0
	var card_w := floorf((cw - CARD_GAP * (cards.size() - 1)) / cards.size())
	var frames: Array = []
	var bottom := y
	for i in cards.size():
		var x := cx + i * (card_w + CARD_GAP)
		var r := _card(parent, cards[i], x, y, card_w)
		frames.append(r)
		bottom = maxf(bottom, r[1])
	var card_h := bottom + CARD_PAD - y
	for i in cards.size():
		var frame: Control = frames[i][0]
		frame.size.y = card_h
		frame.queue_redraw()
		var hit := K.hit(parent, cx + i * (card_w + CARD_GAP), y, card_w, card_h, str(cards[i].get("name", "")))
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		if emit.is_valid():
			hit.pressed.connect(emit.bind("pick", str(cards[i].get("id", ""))))
	y += card_h + 22.0
	var note := K.text(parent, str(vm.get("note", "")), {"x": cx, "y": y, "px": 14, "col": T.DIM})
	var confirm := K.button(parent, str(vm.get("confirm", "Deploy forces")), 0, 0, {"primary": true, "px": 20, "sp": 0.1, "pad": 20.0, "spread": true, "min_h": BTN_H})
	var back := K.button(parent, str(vm.get("back", "Back")), 0, 0, {"px": 20, "sp": 0.1, "pad": 20.0, "spread": true, "min_h": BTN_H, "key": "Esc"})
	confirm.size.x = maxf(240.0, confirm.size.x)
	back.size.x = maxf(150.0, back.size.x)
	for b in [confirm, back]:
		b.custom_minimum_size = b.size
	var right := cx + cw
	K.place(confirm, right - confirm.size.x, y)
	K.place(back, right - confirm.size.x - 16.0 - back.size.x, y)
	note.position.y = roundf(y + (confirm.size.y - note.size.y) * 0.5)
	(back as Control).focus_neighbor_right = (back as Control).get_path_to(confirm)
	(confirm as Control).focus_neighbor_left = (confirm as Control).get_path_to(back)
	if emit.is_valid():
		back.pressed.connect(emit.bind("back", null))
		confirm.pressed.connect(emit.bind("confirm", null))
	y += confirm.size.y
	panel.size.y = roundf(y + PAD + 1.0 - PANEL_Y)
	panel.queue_redraw()
	return confirm


## One map card: its frame (ringed when selected), the tags, the name, the blurb and two facts. Returns [frame, content bottom].
static func _card(parent: Control, card: Dictionary, x: float, y: float, w: float) -> Array:
	var selected: bool = card.get("selected", false)
	var o := {"border": T.LINE, "light": false}
	if selected:
		o = {"border": Color(0, 0, 0, 0), "light": false, "ring": RING, "glow": T.GLOW,
			"fill_top": Color(16.0 / 255.0, 70.0 / 255.0, 86.0 / 255.0, 0.55), "fill_bottom": Color(8.0 / 255.0, 17.0 / 255.0, 26.0 / 255.0, 0.9)}
	var frame := K.panel(parent, x, y, w, 10.0, "panel", o)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ix := x + CARD_PAD
	var iw := w - 2.0 * CARD_PAD
	var cy := y + CARD_PAD
	var tx := ix
	var tag_h := 0.0
	for tag in card.get("tags", []):
		var t := K.tag(parent, str(tag.get("t", "")), tx, cy, T.tone(str(tag.get("tone", "dim"))))
		tx += t.size.x + 8.0
		tag_h = maxf(tag_h, t.size.y)
	if selected:
		var mark := K.tag(parent, "Selected", 0, cy, T.CYAN_HI)
		mark.position.x = roundf(x + w - CARD_PAD - mark.size.x)
		tag_h = maxf(tag_h, mark.size.y)
	cy += tag_h + 16.0
	var name := K.text(parent, str(card.get("name", "")), {"x": ix, "y": cy, "w": iw, "f": "disp", "wt": 600, "px": 30, "sp": 0.04, "col": T.TEXT_HI if selected else T.TEXT, "up": true, "wrap": true})
	cy += name.size.y + 6.0
	var blurb := K.text(parent, str(card.get("blurb", "")), {"x": ix, "y": cy, "w": iw, "px": 15, "col": T.DIM, "wrap": true})
	cy += blurb.size.y + 16.0
	K.rule(parent, ix, cy, iw, 1, T.LINE_DIM)
	cy += 1.0 + 12.0
	for fact in card.get("facts", []):
		var k := K.text(parent, str(fact.get("k", "")), {"x": ix, "y": cy, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
		var v := K.text(parent, str(fact.get("v", "")), {"x": ix + 130.0, "y": cy - 2.0, "w": iw - 130.0, "px": 15, "col": T.TEXT})
		cy += maxf(k.size.y, v.size.y) + 8.0
	return [frame, cy - 8.0]
