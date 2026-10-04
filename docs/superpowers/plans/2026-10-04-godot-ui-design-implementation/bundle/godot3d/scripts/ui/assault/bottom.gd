extends RefCounted
## The bottom row of the core-assault state: minimap with the alert queue, the selection panel and the orders deck.
## Geometry is CoreAssault at 1920x1080 (tools/ui/dump_boxes.py coreassault).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const A = preload("res://scripts/ui/assault/util.gd")
const Tag = preload("res://scripts/ui/components/tag.gd")
const GradBox = preload("res://scripts/ui/components/grad_box.gd")
const SolidMark = preload("res://scripts/ui/components/solid_mark.gd")
const OrderButton = preload("res://scripts/ui/assault/order_button.gd")

## The alert column has room for four 34px rows under its caption; older alerts are only counted.
const MAX_ALERTS := 4
const MAX_GROUPS := 8
const MAX_ORDERS := 8


# ---------------------------------------------------------------- minimap and alert queue

## vm: {layers: [{id, label, on}], slot_fill?: "#rrggbb", alert_count?: int, alerts: [alert]} (alerts newest first).
## alert: {tone: "bad"|"warn"|..., marker: "diamond"|"icon"|"dot", icon?, label, time?, time_tone?, dim?, action?, arg?}.
## Returns the map slot (the host draws the live minimap into it).
static func bottom_left(root: Control, vm: Dictionary, emit: Callable) -> Control:
	A.panel(root, 16, 824, 572, 240)
	_layer_tabs(root, vm.get("layers", []), emit)
	var slot := Control.new()
	slot.name = "MapSlot"
	slot.clip_contents = true
	K.place(slot, 29, 858, 216, 192)
	root.add_child(slot)
	var fill := ColorRect.new()
	fill.color = Color(str(vm.get("slot_fill", "#1f2219")))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(fill)
	var rim := GradBox.new()
	K.place(rim, 29, 858, 216, 192)
	root.add_child(rim)
	rim.style({"fill": Color(0, 0, 0, 0), "border": T.LINE, "sides": "trbl"})
	var alerts: Array = vm.get("alerts", [])
	K.text(root, "Alert queue", {"x": 257, "y": 837, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var count := K.text(root, str(vm.get("alert_count", alerts.size())), {"x": 0, "y": 837, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM})
	count.position.x = roundf(575.0 - count.size.x)
	for i in mini(alerts.size(), MAX_ALERTS):
		_alert(root, 858.0 + 40.0 * i, alerts[i], emit)
	return slot


## Layer names with "/" between them. The mock lets the third name overflow into the alert column, so names that
## do not fit in the map's 216px are left out rather than drawn over the queue.
static func _layer_tabs(root: Control, layers: Array, emit: Callable) -> void:
	var sep_w := A.width("mono", 12, 0, 0.12, "/")
	var x := 29.0
	var shown := 0
	for l in layers:
		var label := str(l.get("label", ""))
		var w := A.width("mono", 12, 0, 0.12, label.to_upper())
		var lead := 0.0 if shown == 0 else 6.0 + sep_w + 6.0
		if x + lead + w > 29.0 + 216.0:
			break
		if shown > 0:
			K.text(root, "/", {"x": x + 6.0, "y": 837, "f": "mono", "px": 12, "sp": 0.12, "col": T.FAINT})
		x += lead
		K.text(root, label, {"x": x, "y": 837, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI if l.get("on", false) else T.DIM, "up": true})
		var hit := K.hit(root, x, 837, w, 15, label)
		hit.pressed.connect(emit.bind("minimap_layer", l.get("id")))
		x += w
		shown += 1


static func _alert(root: Control, y: float, a: Dictionary, emit: Callable) -> void:
	var tone_name := str(a.get("tone", ""))
	var tone: Color = A.tone(tone_name) if tone_name != "" else T.DIM
	var border: Color = tone if tone_name == "bad" or tone_name == "warn" else T.LINE_DIM
	K.panel(root, 257, y, 318, 34, "glass", {"fill": T.BG2, "border": border, "radius": 2})
	var marker := str(a.get("marker", "dot"))
	var text_x := 288.0
	if marker == "icon":
		K.icon(root, str(a.get("icon", "warning_alt")), 268, y + 9, tone, 16)
		text_x = 294.0
	else:
		var mark := SolidMark.new()
		root.add_child(mark)
		mark.setup("diamond" if marker == "diamond" else "dot", 10.0, tone)
		mark.position = Vector2(273.0, y + 17.0) - mark.size * 0.5
	var time := K.text(root, str(a.get("time", "")), {"x": 0, "y": y + 9.5, "f": "mono", "px": 12, "col": A.tone(str(a.get("time_tone", "dim")))})
	time.position.x = roundf(564.0 - time.size.x)
	var room := 564.0 - time.size.x - 10.0 - text_x if time.size.x > 0.0 else 564.0 - text_x
	var label := A.fit(str(a.get("label", "")), "body", 14, 0, 0.0, room)
	K.text(root, label, {"x": text_x, "y": y + 8, "px": 14, "col": T.DIM if a.get("dim", false) else T.TEXT})
	if str(a.get("action", "")) != "":
		var hit := K.hit(root, 257, y, 318, 34, str(a.get("label", "")))
		hit.pressed.connect(emit.bind(str(a["action"]), a.get("arg")))


# ---------------------------------------------------------------- selection

## vm: {name, sub?, tag?, tag_tone?, groups: [{id, sprite, label, ratio, tone?, on?}], stats: [{label, kind: "bar"|"text",
## ratio?, value?, text?, tone?}] (three at most), empty_title?, hint?}. No name and no groups draws the empty state.
static func selection(root: Control, vm: Dictionary, emit: Callable) -> void:
	A.panel(root, 604, 824, 700, 240)
	var name := str(vm.get("name", ""))
	var groups: Array = vm.get("groups", [])
	if name == "" and groups.is_empty():
		K.text(root, str(vm.get("empty_title", "No selection")), {"x": 621, "y": 839, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": T.DIM, "up": true})
		var hint := str(vm.get("hint", ""))
		if hint != "":
			K.text(root, hint, {"x": 621, "y": 879, "w": 666, "px": 14, "col": T.DIM, "wrap": true})
		return
	var title := K.text(root, name, {"x": 621, "y": 839, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": T.TEXT_HI, "up": true})
	var sub := str(vm.get("sub", ""))
	if sub != "":
		var gap: int = T.ascent(T.font("disp", 600), 24) - T.ascent(T.font("mono", 0), 14)
		K.text(root, sub, {"x": 621.0 + title.size.x + 12.0, "y": 839 + gap, "f": "mono", "px": 14, "col": T.DIM})
	var tag_text := str(vm.get("tag", ""))
	if tag_text != "":
		var tag := Tag.new()
		K.place(tag, 0, 843)
		root.add_child(tag)
		tag.setup(tag_text, A.tone(str(vm.get("tag_tone", "cyan"))))
		tag.position.x = roundf(1287.0 - tag.size.x)
	var n := mini(groups.size(), MAX_GROUPS)
	for i in n:
		var cw := (666.0 - 8.0 * (n - 1)) / n
		_group(root, 621.0 + i * (cw + 8.0), cw, groups[i], emit)
	var stats: Array = vm.get("stats", [])
	var col_w := (666.0 - 20.0) / 3.0
	for i in mini(stats.size(), 3):
		_stat(root, 621.0 + i * (col_w + 10.0), col_w, stats[i])


static func _group(root: Control, x: float, w: float, g: Dictionary, emit: Callable) -> void:
	var box := A.snap(x, w)
	K.panel(root, box.x, 879, box.y, 95, "glass", {"border": T.CYAN if g.get("on", false) else T.LINE_DIM})
	var sprite := str(g.get("sprite", ""))
	if sprite != "":
		K.sprite(root, sprite, x + (w - 54.0) * 0.5, 886, 54, 54)
	var label := str(g.get("label", ""))
	K.text(root, A.fit(label, "mono", 13, 0, 0.0, w - 14.0), {"x": x + 7.0, "y": 942, "w": w - 14.0, "f": "mono", "px": 13, "al": "c"})
	var bar_w := 0.7 * (w - 14.0)
	K.bar(root, x + (w - bar_w) * 0.5, 961, bar_w, float(g.get("ratio", 0.0)), A.tone(str(g.get("tone", "cyan"))))
	var hit := K.hit(root, x, 879, w, 95, label)
	hit.pressed.connect(emit.bind("select_group", g.get("id")))


static func _stat(root: Control, x: float, w: float, s: Dictionary) -> void:
	K.text(root, str(s.get("label", "")), {"x": x, "y": 984, "w": w, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var tone := A.tone(str(s.get("tone", "cyan")))
	if str(s.get("kind", "text")) == "bar":
		var value := K.text(root, str(s.get("value", "")), {"x": 0, "y": 1002, "f": "mono", "px": 13})
		value.position.x = roundf(x + w - value.size.x)
		K.bar(root, x, 1007.5, w - 8.0 - value.size.x, float(s.get("ratio", 0.0)), tone)
	else:
		var color: Color = A.tone(str(s["tone"])) if s.has("tone") else T.TEXT
		K.text(root, A.fit(str(s.get("text", "")), "body", 14, 0, 0.0, w), {"x": x, "y": 1002, "px": 14, "col": color})


# ---------------------------------------------------------------- orders deck

## vm: {tabs: [{id, label, on}], orders: [{label, key?, action, arg?, tone?: "primary"|"warn", disabled?}] (eight at most,
## four per row), hint?}. Tabs emit ("deck_tab", id); orders emit their own action.
static func deck(root: Control, vm: Dictionary, emit: Callable) -> void:
	A.panel(root, 1320, 824, 584, 240)
	var x := 1333.0
	for tab in vm.get("tabs", []):
		var label := str(tab.get("label", ""))
		var w := A.width("mono", 12, 0, 0.12, label.to_upper()) + 24.0 + 2.0
		if x + w > 1891.0:
			break
		var on: bool = tab.get("on", false)
		var snapped := A.snap(x, w)
		var box := GradBox.new()
		K.place(box, snapped.x, 837, snapped.y, 31)
		root.add_child(box)
		box.style({"fill": T.ACTIVE if on else Color(0, 0, 0, 0), "border": T.CYAN if on else T.LINE_DIM, "sides": "trbl"})
		K.text(root, label, {"x": x + 13.0, "y": 845, "f": "mono", "px": 12, "sp": 0.12, "col": T.TEXT_HI if on else T.DIM, "up": true})
		var hit := K.hit(root, snapped.x, 837, snapped.y, 31, label)
		hit.pressed.connect(emit.bind("deck_tab", tab.get("id")))
		x += w + 4.0
	var hint_h := 0.0
	var hint_text := str(vm.get("hint", ""))
	if hint_text != "":
		var hint := K.text(root, hint_text, {"x": 1333, "y": 1034, "w": 558, "px": 13, "col": T.DIM, "wrap": true})
		hint_h = hint.size.y
		hint.position.y = roundf(1051.0 - hint_h)
	var orders: Array = vm.get("orders", [])
	var count := mini(orders.size(), MAX_ORDERS)
	if count == 0:
		return
	var grid_h := 214.0 - 31.0 - 10.0 - (10.0 + hint_h if hint_text != "" else 0.0)
	var rows := int(ceil(count / 4.0))
	var cell_h := (grid_h - 8.0 * (rows - 1)) / rows
	var cell_w := (558.0 - 24.0) / 4.0
	for i in count:
		var order: Dictionary = orders[i]
		var tone := str(order.get("tone", ""))
		var button := OrderButton.new()
		var col := A.snap(1333.0 + (i % 4) * (cell_w + 8.0), cell_w)
		var row := A.snap(878.0 + (i / 4) * (cell_h + 8.0), cell_h)
		K.place(button, col.x, row.x)
		root.add_child(button)
		button.setup(str(order.get("label", "")), str(order.get("key", "")), col.y, row.y, tone)
		button.disabled = order.get("disabled", false)
		button.pressed.connect(emit.bind(str(order.get("action", "")), order.get("arg")))
