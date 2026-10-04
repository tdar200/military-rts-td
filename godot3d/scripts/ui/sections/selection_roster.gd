extends RefCounted
## Selection roster (board 5, bottom centre): the same 940x258 frame as board 1, holding a card per selected unit (sprite,
## name, health bar, veteran chevrons), a "standing on" strip and a Cancel button. Driven by vm["roster"]
## (VmGameplay.roster); builds nothing without it. Cancel exists only while attack-move is armed and emits
## ("order", "cancel_armed"). The board's "Confirm target" and "Queue waypoint" buttons have no matching command, and the
## strip's "Ford ahead" line has no data, so none of them are built.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Frame = preload("res://scripts/ui/sections/bottom_panel.gd")

const LEFT_W := 640.0
const RIGHT_W := 250.0
const TOP := 823.0
const CARD_GAP := 4.0
const CARD_MAX_W := 72.0
const CARD_H := 74.0
const BTN_H := 44.0
## Height inside the frame: 258 less its borders and 12px padding top and bottom.
const INNER_H := 232.0
const STRIP_H := 35.0


## A row of amber chevrons (the mock's .vet): `chevrons` triangles 10 wide and 7 high, 2px apart.
class Vet extends Control:
	var chevrons := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in chevrons:
			var x := i * 12.0
			draw_colored_polygon(PackedVector2Array([Vector2(x + 5.0, 0.0), Vector2(x + 10.0, 7.0), Vector2(x, 7.0)]), T.WARN)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var d = vm.get("roster", null)
	if not (d is Dictionary) or d.is_empty() or (d.get("cards", []) as Array).is_empty():
		return
	K.panel(parent, Frame.X, Frame.Y, Frame.W, Frame.H)
	var x := Frame.COL1_X
	var y := TOP
	var title := K.text(parent, str(d.get("title", "")), {"x": x, "y": y, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "lh": 26, "col": T.TEXT_HI, "up": true})
	var tx := x + title.size.x + 12.0
	var tags: Array = [[str(d.get("count", "")), T.CYAN]]
	if bool(d.get("armed", false)):
		tags.append(["Armed: attack-move", T.BAD])
	for t in tags:
		var tag := K.tag(parent, str(t[0]), tx, y + (title.size.y - 22.0) * 0.5, t[1])
		tx += tag.size.x + 12.0
	if int(d.get("more", 0)) > 0:
		var more := K.text(parent, "+%d more" % int(d["more"]), {"x": 0, "y": y, "f": "mono", "px": 12, "col": T.DIM})
		more.position = Vector2(roundf(x + LEFT_W - more.size.x), roundf(y + (title.size.y - more.size.y) * 0.5))
	y += title.size.y + 10.0
	var cards: Array = d["cards"]
	var card_w := minf(CARD_MAX_W, (LEFT_W - CARD_GAP * (cards.size() - 1)) / cards.size())
	for i in cards.size():
		_card(parent, cards[i], x + i * (card_w + CARD_GAP), y, card_w)
	y += CARD_H + 10.0
	if str(d.get("standing", "")) != "":
		_strip(parent, d, x, y)
	if bool(d.get("armed", false)):
		var bx := x + LEFT_W + 16.0
		# The board's third slot in its centred stack of three; the two buttons above it have no command.
		var by := TOP + (INNER_H - (3.0 * BTN_H + 16.0)) * 0.5 + 2.0 * (BTN_H + 8.0)
		var cancel := K.button(parent, "Cancel", bx, by, {"w": RIGHT_W, "h": BTN_H, "key": "Esc"})
		if emit.is_valid():
			(cancel as Button).pressed.connect(emit.bind("order", "cancel_armed"))


static func _card(parent: Control, c: Dictionary, x: float, y: float, w: float) -> void:
	var glass := K.panel(parent, x, y, w, CARD_H, "glass")
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(c.get("sprite", "")) != "":
		K.sprite(parent, str(c["sprite"]), x + (w - 38.0) * 0.5, y + 6.0, 38.0, 38.0)
	var name := K.text(parent, str(c.get("name", "")), {"x": 0, "y": y + 6.0 + 38.0 + 3.0, "px": 10, "col": T.TEXT})
	name.position.x = roundf(x + (w - name.size.x) * 0.5)
	K.bar(parent, x + 4.0, y + CARD_H - 1.0 - 5.0 - 5.0, w - 8.0, float(c.get("ratio", 0.0)), T.tone(str(c.get("tone", "good"))), 5.0)
	var rank := int(c.get("rank", 0))
	if rank > 0:
		var vet := Vet.new()
		vet.chevrons = rank
		K.place(vet, x + 5.0, y + 5.0, rank * 12.0, 7.0)
		parent.add_child(vet)


static func _strip(parent: Control, d: Dictionary, x: float, y: float) -> void:
	var glass := K.panel(parent, x, y, LEFT_W, STRIP_H, "glass")
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at := x + 13.0
	var a := K.text(parent, "Standing on", {"x": at, "y": 0, "px": 13, "col": T.DIM})
	var b := K.text(parent, " " + str(d["standing"]), {"x": at + a.size.x, "y": 0, "px": 13, "col": T.TEXT})
	var line := maxf(a.size.y, b.size.y)
	var top := roundf(y + (STRIP_H - line) * 0.5)
	a.position.y = top
	b.position.y = top
	at += a.size.x + b.size.x + 18.0
	if str(d.get("speed", "")) != "":
		var s := K.text(parent, str(d["speed"]), {"x": at, "y": top, "px": 13, "col": T.tone(str(d.get("speed_tone", "good")))})
		at += s.size.x + 18.0
