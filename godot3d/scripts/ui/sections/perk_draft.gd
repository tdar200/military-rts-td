extends RefCounted
## Run perk draft (kestrel-depth Task 26): after each cleared wave of a run the bridge offers up to three perks (snapshot
## depth.run.draft) and the client holds the simulation (pause.flag) until the player takes one. The modal is a panel in
## the play area between the top bar and the bottom HUD, over a click-swallowing layer, so nothing reaches the world or the
## HUD under it: three cards (name, perk.rs description, the key that takes it), a line on the run, and the pool. It shows
## perk text only, never anything the fog hides. `emit` is Callable(name, arg) and receives `perk` with the card's index.
## Each card is one click target whose (invisible) text is "perk:<id>", so QA and tests find it.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const MatchConfig = preload("res://scripts/match_config.gd")

## [name, description] by perk id, as rts_core::game::perk name() and description() say them (test_perk_draft checks
## the two tables agree). Ids 0 to 3 are the classic perks, 4 to 11 the depth perks a run drafts from.
const PERK_TEXT := [
	["Overcharge", "+25% weapon damage"],
	["Logistics", "+50% credit income"],
	["Conscription", "+8 supply cap"],
	["Bulwark", "+2 armor mitigation"],
	["Field Upgrade", "One free level on your lowest Upgrades track"],
	["Rapid Cycle", "Ability cooldowns 25% shorter"],
	["Refinery Discount", "Every refinery costs the base price"],
	["Long Sight", "+1 turret range"],
	["Early Tooling", "Tank tooling (tech 1) completes at once"],
	["Hardened Walls", "Walls take one third less damage"],
	["Field Repair", "Repairs cost half"],
	["Capital Discount", "The Capital costs 25% less"],
]
const CAPITAL_DISCOUNT := 11
const CAPITAL_PRICE := 500
const CAPITAL_DISCOUNTED := 375

## The play area at 1920x1080 (test_perk_draft checks it against hud.gd's surfaces): right of the objectives card (x 12
## to 432), under the wave card (y 76 to 226), left of the idle-crew and next-alert chips (x 1540 on), above the bottom
## HUD (770).
const PANEL_X := 448.0
const PANEL_Y := 240.0
const PANEL_W := 1052.0
const PAD := 26.0
const CARD_GAP := 20.0
const CARD_PAD := 22.0
const CARD_H := 250.0
## The dimmed play area (between the objectives card, the chips, the wave card and the bottom HUD).
const DIM_PLAY := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.45)
const DIM_RECT := Rect2(440, 232, 1096, 528)


static func perk_name(id: int) -> String:
	return str(PERK_TEXT[id][0]) if id >= 0 and id < PERK_TEXT.size() else "Perk %d" % id


static func perk_description(id: int) -> String:
	return str(PERK_TEXT[id][1]) if id >= 0 and id < PERK_TEXT.size() else ""


## A perk's extra line on its card: what it changes in numbers the HUD shows (the Capital's price).
static func perk_extra(id: int) -> String:
	if id == CAPITAL_DISCOUNT:
		return "Capital %d to %d credits" % [CAPITAL_PRICE, CAPITAL_DISCOUNTED]
	return ""


## The perks a held bitmask names, in id order.
static func held_ids(held: int) -> Array:
	var out: Array = []
	for id in PERK_TEXT.size():
		if held & (1 << id):
			out.append(id)
	return out


## The modal's view model from a run block ({wave, draft, pool, held}); {} when there is no draft to take.
static func vm(run: Dictionary) -> Dictionary:
	var draft: Variant = run.get("draft", null)
	if not (draft is Array) or (draft as Array).is_empty():
		return {}
	var cards: Array = []
	for i in mini(3, draft.size()):
		var id := int(draft[i])
		cards.append({"id": id, "key": str(i + 1), "name": perk_name(id), "desc": perk_description(id), "extra": perk_extra(id)})
	var held := int(run.get("held", 0))
	var pool := MatchConfig.clean_pool(int(run.get("pool", MatchConfig.DEFAULT_POOL)))
	var taken := held_ids(held).size()
	return {
		"cap": "Run / wave %d of %d cleared" % [int(run.get("wave", 0)), MatchConfig.RUN_WAVES],
		"title": "Choose a perk",
		"note": "The battle is paused until you choose. Press 1, 2 or 3, or click a card.",
		"cards": cards,
		"footer": "Perks drafted %d / Pool %d of 12 perks" % [taken, MatchConfig.pool_size(pool)],
	}


## Builds the modal into `layer` (a full-rect control); returns the first card's click target (null for {}).
static func build(layer: Control, model: Dictionary, emit := Callable()) -> Control:
	var cards: Array = model.get("cards", [])
	if model.is_empty() or cards.is_empty():
		return null
	var block := ColorRect.new()  # the whole screen takes no click while the draft is up; only the play area is dimmed
	block.name = "DraftBlock"
	block.color = Color(0, 0, 0, 0)
	block.set_anchors_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(block)
	var dim := ColorRect.new()
	dim.color = DIM_PLAY
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(dim, DIM_RECT.position.x, DIM_RECT.position.y, DIM_RECT.size.x, DIM_RECT.size.y)
	layer.add_child(dim)
	var panel := K.panel(layer, PANEL_X, PANEL_Y, PANEL_W, 10.0)
	panel.name = "DraftPanel"
	var cx := PANEL_X + 1.0 + PAD
	var cw := PANEL_W - 2.0 - 2.0 * PAD
	var y := PANEL_Y + 1.0 + PAD
	var cap := K.text(layer, str(model.get("cap", "")), {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	y += cap.size.y + 4.0
	var title := K.text(layer, str(model.get("title", "")), {"x": cx, "y": y, "f": "disp", "wt": 600, "px": 40, "sp": 0.04, "lh": 42, "col": T.TEXT_HI, "up": true})
	y += title.size.y + 6.0
	var note := K.text(layer, str(model.get("note", "")), {"x": cx, "y": y, "w": cw, "px": 15, "col": T.DIM})
	y += note.size.y + 18.0
	var card_w := floorf((cw - CARD_GAP * 2.0) / 3.0)
	var first: Control = null
	for i in cards.size():
		var x := cx + i * (card_w + CARD_GAP)
		_card(layer, cards[i], x, y, card_w)
		var hit := K.hit(layer, x, y, card_w, CARD_H, "perk:%d" % int(cards[i].get("id", -1)))
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.tooltip_text = str(cards[i].get("name", ""))
		if emit.is_valid():
			hit.pressed.connect(emit.bind("perk", i))
		if first == null:
			first = hit
	y += CARD_H + 16.0
	var footer := K.text(layer, str(model.get("footer", "")), {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	y += footer.size.y
	panel.size.y = roundf(y + PAD + 1.0 - PANEL_Y)
	panel.queue_redraw()
	return first


static func _card(parent: Control, card: Dictionary, x: float, y: float, w: float) -> void:
	var frame := K.panel(parent, x, y, w, CARD_H, "panel", {"border": T.LINE, "light": false})
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ix := x + CARD_PAD
	var iw := w - 2.0 * CARD_PAD
	var cy := y + CARD_PAD
	var key := K.key(parent, str(card.get("key", "")), ix, cy)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := K.tag(parent, "Perk", 0, cy, T.CYAN_HI)
	tag.position.x = roundf(x + w - CARD_PAD - tag.size.x)
	cy += maxf(key.size.y, tag.size.y) + 14.0
	var name := K.text(parent, str(card.get("name", "")), {"x": ix, "y": cy, "w": iw, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "col": T.TEXT_HI, "up": true, "wrap": true})
	cy += name.size.y + 8.0
	var desc := K.text(parent, str(card.get("desc", "")), {"x": ix, "y": cy, "w": iw, "px": 16, "col": T.TEXT, "wrap": true})
	cy += desc.size.y + 10.0
	var extra := str(card.get("extra", ""))
	if extra != "":
		K.text(parent, extra, {"x": ix, "y": cy, "w": iw, "f": "mono", "px": 13, "col": T.GOOD, "wrap": true})
