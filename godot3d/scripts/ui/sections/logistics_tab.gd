extends RefCounted
## The Logistics deck tab (board 8, bottom right): the map lens buttons, the active lens's legend and a line of what it
## currently draws on the map. Driven by the deck body vm {kind: "logistics", lenses: [{id, label, on}], lens, legend, summary,
## note, empty, routes}; builds nothing without a lens. A lens button emits ("world_lens", id); the active one emits ("world_lens", "")
## to turn the overlay off. Lenses the snapshot cannot back are simply absent from `lenses` (see overlay_feed.gd).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const X := 1284.0
const Y := 810.0
const W := 624.0
const H := 258.0
const PAD_X := 13.0
const BUTTON_Y := 844.0
const BUTTON_GAP := 8.0
const LEGEND_Y := 896.0
const ROW_H := 24.0
const SWATCH_W := 36.0
## The Supply lens list (board 8's "Supply routes" rows, built from supply_links only): rows of ROUTE_H at ROUTE_PITCH,
## three at most; with more depots than that two rows and a "+N more" line, so it always ends inside the panel.
const ROUTE_H := 26.0
const ROUTE_PITCH := 30.0
const ROUTE_MAX := 3


## Swatch and tone words used by the lens legends (overlay_feed.gd legend rows).
static func tone_color(tone: String) -> Color:
	match tone:
		"ok", "own":
			return T.CYAN
		"enemy":
			return T.BAD
		_:
			return T.tone(tone)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var lenses = vm.get("lenses", [])
	if not (lenses is Array) or lenses.is_empty():
		return
	K.panel(parent, X, Y, W, H, "panel", {"tl": 0})
	var cx := X + PAD_X
	K.text(parent, "Map lenses", {"x": cx, "y": 821, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var active := str(vm.get("lens", ""))
	var shown := "Off"
	for l in lenses:
		if str(l.get("id", "")) == active:
			shown = str(l.get("label", active))
	var right := K.text(parent, shown, {"x": 0, "y": 821, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN if active != "" else T.DIM, "up": true})
	right.position.x = roundf(X + W - 13.0 - right.size.x)
	var x := cx
	for l in lenses:
		var id := str(l.get("id", ""))
		var on := bool(l.get("on", false))
		var b := K.button(parent, str(l.get("label", id)), x, BUTTON_Y, {"min_h": 36, "px": 15, "pad": 14, "primary": on})
		x += b.size.x + BUTTON_GAP
		if emit.is_valid():
			b.pressed.connect(emit.bind("world_lens", "" if on else id))
	var y := LEGEND_Y
	var legend = vm.get("legend", [])
	if active == "" or not (legend is Array) or legend.is_empty():
		if active == "":
			K.text(parent, "Pick a lens to draw it on the map.", {"x": cx, "y": y, "px": 14, "col": T.DIM})
		elif str(vm.get("empty", "")) != "":
			K.text(parent, str(vm["empty"]), {"x": cx, "y": y, "px": 14, "col": T.DIM})
		return
	for row in legend:
		_legend_row(parent, cx, y, row)
		y += ROW_H
	y += 4.0
	var routes = vm.get("routes", [])
	if routes is Array and not routes.is_empty():
		_routes(parent, cx, y, routes, str(vm.get("summary", "")))
		return
	var summary := str(vm.get("summary", ""))
	if summary != "":
		K.text(parent, summary, {"x": cx, "y": y, "f": "mono", "px": 13, "col": T.CYAN_HI})
		y += 22.0
	elif str(vm.get("empty", "")) != "":
		K.text(parent, str(vm["empty"]), {"x": cx, "y": y, "px": 14, "col": T.WARN})
		y += 22.0
	var note := str(vm.get("note", ""))
	if note != "":
		K.text(parent, note, {"x": cx, "y": y, "w": W - 2.0 * PAD_X, "px": 14, "col": T.DIM, "wrap": true})


static func _legend_row(parent: Control, x: float, y: float, row: Dictionary) -> void:
	var color := tone_color(str(row.get("tone", "")))
	var mid := y + 11.0
	match str(row.get("style", "solid")):
		"dotted":
			for i in 4:
				K.rule(parent, x + 1.0 + i * 9.0, mid - 1.5, 3, 3, color)
		"dashed":
			for i in 3:
				K.rule(parent, x + i * 14.0, mid - 1.0, 8, 2, color)
		"badge":
			K.panel(parent, x + 3.0, y + 1.0, 30, 20, "glass", {"border": color})
			# The swatch shows what the map badge reads ("+20%", "+12"), so the key matches the thing it explains.
			K.text(parent, str(row.get("sample", "+")), {"x": x + 3.0, "y": y + 4.0, "w": 30, "f": "mono", "px": 11, "al": "c", "col": color})
		_:
			K.rule(parent, x, mid - 2.0, SWATCH_W, 4, color)
	K.text(parent, str(row.get("text", "")), {"x": x + SWATCH_W + 12.0, "y": y + 2.0, "px": 14, "col": T.TEXT})


## Header ("Supply depots / N" and the summary on the right) then a glass row per depot: name, what it feeds, OK or Cut.
static func _routes(parent: Control, x: float, y: float, routes: Array, summary: String) -> void:
	K.text(parent, "Supply depots / %d" % routes.size(), {"x": x, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	if summary != "":
		var right := K.text(parent, summary, {"x": 0, "y": y, "f": "mono", "px": 12, "col": T.DIM})
		right.position.x = roundf(X + W - PAD_X - right.size.x)
	y += 24.0
	var shown := routes.size() if routes.size() <= ROUTE_MAX else ROUTE_MAX - 1
	var width := W - 2.0 * PAD_X
	for i in shown:
		var row: Dictionary = routes[i]
		var color := T.BAD if str(row.get("tone", "")) == "bad" else T.GOOD
		K.panel(parent, x, y, width, ROUTE_H, "glass", {"border": T.BAD if color == T.BAD else T.LINE})
		K.text(parent, str(row.get("name", "")), {"x": x + 10.0, "y": y + 4.0, "px": 14, "col": T.TEXT})
		var tag := K.tag(parent, str(row.get("tag", "")), 0.0, y + 2.0, color)
		tag.position.x = roundf(x + width - 10.0 - tag.size.x)
		var detail := K.text(parent, str(row.get("detail", "")), {"x": 0, "y": y + 5.0, "f": "mono", "px": 13, "col": color})
		detail.position.x = roundf(tag.position.x - 12.0 - detail.size.x)
		y += ROUTE_PITCH
	if shown < routes.size():
		K.text(parent, "+%d more depots" % (routes.size() - shown), {"x": x, "y": y + 2.0, "f": "mono", "px": 12, "col": T.DIM})
