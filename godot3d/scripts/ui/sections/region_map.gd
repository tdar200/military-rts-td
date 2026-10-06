extends RefCounted
## Strategic map (board 11): the real ground layer as a flat hex map in the left 1620 px, the region names from the snapshot,
## the construction-zone and alien borders, the expected wave route and the deposits; a right panel with the region title,
## the ground composition, the territory tile count, the hostile site count and five lens Buttons (Terrain, Resources,
## Borders, Threat, Hex grid) that toggle the layers on this screen only. Driven by vm_maps.region_map() plus
## vm["lens_on"] ({terrain, res, bdr, thr, hex} booleans); `emit` is Callable(name, arg) and receives region_lens (id),
## region_close and focus_deposit (cell). Builds nothing without a vm.
## Kestrel fog of war: with the snapshot's mask the unseen hexes are shrouded and the explored ones dimmed (vm `unseen`,
## `explored`), a remembered hostile site is drawn dimmed, and the panel adds an "Explored" percent row.
## Not built, because the sim has no such data: the Unexplored and Islet pins, "Resources seen", Yields per minute, Next
## goals, the scale bar, the compass (see docs/ascension/ui-deviations.md).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const ResourcePins = preload("res://scripts/ui/sections/resource_pins.gd")
const TerritoryCard = preload("res://scripts/ui/sections/territory_card.gd")
const Feed = preload("res://scripts/world/overlay_feed.gd")
const Hex = preload("res://scripts/ui/components/hex_map.gd")

const AREA := Hex.AREA
const MARGIN := 16.0

const PANEL_X := 1620.0
const PANEL_W := 300.0
const LENSES := [["terrain", "Terrain"], ["res", "Resources"], ["bdr", "Borders"], ["thr", "Threat"], ["hex", "Hex grid"]]
const DEFAULT_LENSES := {"terrain": true, "res": false, "bdr": true, "thr": true, "hex": false}
const PANEL_BG := Color("08101a")
const LABEL_SIZE := {"sea": 26, "flats": 24, "highland": 22, "grassland": 20, "forest": 18, "river": 18, "ford": 12, "colony": 15}
const ROUTE_WIDTH := 3.0
const SHROUD := Color(0.02, 0.03, 0.05, 0.88)  # an unseen hex (the battlefield's near-black blue shroud)
const MEMORY := Color(0.02, 0.03, 0.05, 0.45)  # an explored hex, seen once, out of sight now



# ------------------------------------------------------------------ layers

## The ground: sea beyond the map, the tiles (Terrain lens) and the hex grid (Hex grid lens). Blocks clicks to the game below.
class Ground extends Control:
	var vm: Dictionary = {}
	var lenses: Dictionary = {}
	var _keep: Array = []  # the shroud meshes (the canvas keeps only their RIDs)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		_keep.clear()
		draw_rect(Rect2(Vector2.ZERO, size), Hex.ground_color("o") if lenses.get("terrain", true) else T.BG1)
		if lenses.get("terrain", true):
			draw_mesh(Hex.ground_mesh(vm), null)
		var l := Hex.layout(int(vm["width"]), int(vm["height"]))
		for layer in [["unseen", SHROUD], ["explored", MEMORY]]:
			var cells: Array = vm.get(layer[0], [])
			if cells.is_empty():
				continue
			var colors: Array = []
			colors.resize(cells.size())
			colors.fill(layer[1])
			var m := Hex.hex_mesh(l, cells, colors)
			_keep.append(m)
			draw_mesh(m, null)
		if lenses.get("hex", false):
			draw_multiline(Hex.grid_lines(vm), Color(1, 1, 1, 0.12), 1.0)


## Borders, route and hostile sites over the ground. Redrawn only when the screen is built (lens toggle or a changed vm).
class Overlay extends Control:
	var vm: Dictionary = {}
	var lenses: Dictionary = {}
	## The canvas keeps only the mesh RID, so a mesh built inside _draw must outlive it (else "mesh is null" at render time).
	var _keep: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		_keep.clear()
		var l := Hex.layout(int(vm["width"]), int(vm["height"]))
		if lenses.get("bdr", true):
			_fill(l, vm.get("zone", []), Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.10))
			_fill(l, vm.get("enemy", []), Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.10))
			for m in vm.get("borders", []):
				if str(m.get("kind", "")) != "border":
					continue
				var col: Color = T.BAD if str(m.get("tone", "")) == "enemy" else T.CYAN
				for e in m.get("edges", []):
					var side := Hex.shared_side(l, e[0], e[1])
					if not side.is_empty():
						draw_line(side[0], side[1], col, 3.5, true)
		if lenses.get("thr", true):
			var route: Dictionary = vm.get("route", {})
			var pts := PackedVector2Array()
			for c in route.get("route", []):
				pts.append(Hex.center(l, int(c[0]), int(c[1])))
			if pts.size() >= 2:
				draw_polyline(pts, Color(T.BAD.r, T.BAD.g, T.BAD.b, 0.18), 22.0, true)
				for i in pts.size() - 1:
					draw_dashed_line(pts[i], pts[i + 1], T.BAD, ROUTE_WIDTH, 9.0, true)
			for h in vm.get("hostile", []):
				var tone: Color = T.BAD.darkened(0.45) if bool(h.get("remembered", false)) else T.BAD  # last seen: dimmed
				_diamond(Hex.center(l, int(h["cell"][0]), int(h["cell"][1])), float(l["u"]) * 0.3, tone)
		for c in vm.get("own_cc", []):
			_diamond(Hex.center(l, int(c[0]), int(c[1])), float(l["u"]) * 0.3, T.CYAN_HI)

	func _fill(l: Dictionary, cells: Array, color: Color) -> void:
		if cells.is_empty():
			return
		var colors: Array = []
		colors.resize(cells.size())
		colors.fill(color)
		var m := Hex.hex_mesh(l, cells, colors)
		_keep.append(m)
		draw_mesh(m, null)

	func _diamond(c: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, color)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 1.5, true)


# ------------------------------------------------------------------ build

static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty() or int(vm.get("width", 0)) <= 0:
		return
	var lenses: Dictionary = DEFAULT_LENSES.duplicate()
	lenses.merge(vm.get("lens_on", {}), true)
	var l := Hex.layout(int(vm["width"]), int(vm["height"]))
	var ground := Ground.new()
	ground.name = "Ground"
	ground.vm = vm
	ground.lenses = lenses
	K.place(ground, 0, 0, AREA.x, AREA.y)
	parent.add_child(ground)
	var overlay := Overlay.new()
	overlay.name = "Overlay"
	overlay.vm = vm
	overlay.lenses = lenses
	K.place(overlay, 0, 0, AREA.x, AREA.y)
	parent.add_child(overlay)
	var placed: Array = [Rect2(12, 10, 380, 44)]  # the title bar
	_map_name(parent, vm, placed)
	_labels(parent, vm, l, placed)
	_pins(parent, vm, l, lenses, emit)
	_panel(parent, vm, lenses, emit)
	_title_bar(parent, emit)


static func _map_name(parent: Control, vm: Dictionary, placed: Array) -> void:
	var name := str(vm.get("name", ""))
	if name == "":
		return
	var t := K.text(parent, name, {"f": "disp", "wt": 600, "px": 40, "sp": 0.5, "col": Color(1, 1, 1, 0.7), "up": true})
	t.position = Vector2(roundf((AREA.x - t.size.x) * 0.5), 20.0)
	placed.append(Rect2(t.position, t.size))


## Region names from `regions`, each on a cell of the ground it names; a name that would cover another takes the next cell.
static func _labels(parent: Control, vm: Dictionary, l: Dictionary, placed: Array) -> void:
	for r in vm.get("labels", []):
		var kind := str(r.get("kind", ""))
		var px: int = LABEL_SIZE.get(kind, 18)
		var col := Color(1, 1, 1, 0.66)
		if kind == "river" or kind == "sea":
			col = Color(190.0 / 255.0, 235.0 / 255.0, 1.0, 0.7)
		elif kind == "ford":
			col = T.WARN_HI
		elif kind == "colony":
			col = T.CYAN_HI
		var t := K.text(parent, str(r["name"]), {"f": "disp", "wt": 600, "px": px, "sp": 0.3, "col": col, "up": true})
		var chosen := Rect2()
		for i in (r["cands"] as Array).size():
			var c: Array = r["cands"][i]
			var at := Hex.center(l, int(c[0]), int(c[1]))
			var rect := Rect2(at - t.size * 0.5, t.size)
			var clash := false
			for other in placed:
				if rect.grow(4.0).intersects(other):
					clash = true
					break
			if i == 0 or not clash:
				chosen = rect
			if not clash:
				break
		t.position = chosen.position.round()
		placed.append(Rect2(t.position, t.size))


static func _pins(parent: Control, vm: Dictionary, l: Dictionary, lenses: Dictionary, emit: Callable) -> void:
	var pins: Array = []
	if lenses.get("res", false):
		for p in vm.get("pins", []):
			var at := Hex.center(l, int(p["x"]), int(p["y"]))
			var pin: Dictionary = p.duplicate()
			pin["x"] = roundf(at.x)
			pin["y"] = roundf(at.y)
			pins.append(pin)
	var hostile_pins: Array = []
	if lenses.get("bdr", true):
		for m in vm.get("borders", []):
			if str(m.get("kind", "")) == "callout":
				var at := Hex.center(l, int(m["cell"][0]), int(m["cell"][1]))
				hostile_pins.append({"x": roundf(at.x), "y": roundf(at.y), "kind": str(m.get("title", "Enemy territory")), "hostile": true})
	if lenses.get("thr", true):
		var route: Dictionary = vm.get("route", {})
		var cells: Array = route.get("route", [])
		if not cells.is_empty():
			var mid: Array = cells[cells.size() / 3]
			var at := Hex.center(l, int(mid[0]), int(mid[1]))
			var text := "Wave %02d route" % int(route.get("wave", 1))
			if route.has("eta_s"):
				text += ", %02d:%02d" % [int(route["eta_s"]) / 60, int(route["eta_s"]) % 60]
			hostile_pins.append({"x": roundf(at.x), "y": roundf(at.y), "kind": text, "hostile": true})
	var layer := Control.new()
	layer.name = "Pins"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(layer, 0, 0, AREA.x, AREA.y)
	parent.add_child(layer)
	ResourcePins.build(layer, {"pins": pins + hostile_pins}, emit)


static func _title_bar(parent: Control, emit: Callable) -> void:
	K.panel(parent, 12, 10, 380, 44)
	K.icon(parent, "map", 12 + 1 + 14, 10 + 22 - 9, T.CYAN, 18)
	var title := K.text(parent, "Strategic map", {"f": "disp", "wt": 600, "px": 20, "sp": 0.1, "col": T.TEXT_HI, "up": true})
	title.position = Vector2(12 + 1 + 14 + 18 + 12, roundf(10 + 22 - title.size.y * 0.5))
	var hint := K.text(parent, "M to close", {"f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	hint.position = Vector2(roundf(title.position.x + title.size.x + 12), roundf(10 + 22 - hint.size.y * 0.5))
	var close := K.button(parent, "Close", 0, 0, {"min_h": 34, "px": 15, "pad": 12})
	K.place(close, AREA.x - 12 - close.size.x, 10)
	if emit.is_valid():
		close.pressed.connect(emit.bind("region_close", null))


static func _panel(parent: Control, vm: Dictionary, lenses: Dictionary, emit: Callable) -> void:
	var back := ColorRect.new()
	back.name = "RightPanel"
	back.color = PANEL_BG
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	K.place(back, PANEL_X, 0, PANEL_W, AREA.y)
	parent.add_child(back)
	var x := PANEL_X + MARGIN
	var w := PANEL_W - 2.0 * MARGIN
	var y := MARGIN
	var cap := K.text(parent, "Region", {"x": x, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	y += cap.size.y + 2.0
	var title := K.text(parent, str(vm.get("name", "")), {"x": x, "y": y, "w": w, "f": "disp", "wt": 600, "px": 34, "sp": 0.04, "lh": 36, "col": T.TEXT_HI, "up": true})
	y += title.size.y
	if str(vm.get("sub", "")) != "":
		var sub := K.text(parent, str(vm["sub"]), {"x": x, "y": y, "px": 13, "col": T.DIM})
		y += sub.size.y
	y += 12.0
	y += _composition(parent, vm, x, y, w) + 12.0
	_lenses(parent, lenses, x, w, emit)


## The composition panel: the bar and legend from the ground counts of the whole map, then Territory and Hostile sites.
static func _composition(parent: Control, vm: Dictionary, x: float, top: float, w: float) -> float:
	var comp: Dictionary = vm.get("composition", {})
	var rows: Array = comp.get("rows", [])
	var panel := K.panel(parent, x, top, w, 10.0)
	var cx := x + 1.0 + 12.0
	var cw := w - 2.0 - 24.0
	var y := top + 1.0 + 12.0
	var cap := K.text(parent, "Composition", {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	y += cap.size.y + 8.0
	var bar := TerritoryCard.Bar.new()
	K.place(bar, cx, y, cw, 10)
	parent.add_child(bar)
	for row in rows:
		bar.segments.append([float(row.get("pct", 0)), Hex.ground_color(str(row.get("glyph", "")))])
	y += 10.0 + 8.0
	var col_w := (cw - 10.0) * 0.5
	var line_h := 0.0
	for i in rows.size():
		var cell := K.text(parent, "%s %d%%" % [str(rows[i].get("name", "")), int(rows[i].get("pct", 0))], {"x": cx + (i % 2) * (col_w + 10.0), "px": 12, "col": T.DIM})
		line_h = cell.size.y
		cell.position.y = roundf(y + (i / 2) * (line_h + 3.0))
	var n_rows := (rows.size() + 1) / 2
	y += n_rows * line_h + maxf(0.0, n_rows - 1.0) * 3.0 + 8.0
	y = _row(parent, "Territory", "%d tiles" % int(vm.get("tiles", 0)), "", cx, y, cw)
	if vm.has("hostile"):
		var count: int = (vm["hostile"] as Array).size()
		y = _row(parent, "Hostile sites", str(count), "bad" if count > 0 else "", cx, y, cw)
	if vm.has("explored_pct"):
		y = _row(parent, "Explored", "%d%%" % int(vm["explored_pct"]), "", cx, y, cw)
	panel.size.y = roundf(y + 12.0 + 1.0 - top)
	panel.queue_redraw()
	return panel.size.y


static func _row(parent: Control, label: String, value: String, tone: String, x: float, y: float, w: float) -> float:
	var left := K.text(parent, label, {"x": x, "px": 14, "col": T.DIM})
	var right := K.text(parent, value, {"f": "mono", "px": 14, "col": T.tone(tone) if tone != "" else T.TEXT})
	var h := maxf(left.size.y, right.size.y)
	left.position = Vector2(x, roundf(y + 5.0 + (h - left.size.y) * 0.5))
	right.position = Vector2(roundf(x + w - right.size.x), roundf(y + 5.0 + (h - right.size.y) * 0.5))
	return y + 5.0 + h + 5.0


static func _lenses(parent: Control, lenses: Dictionary, x: float, w: float, emit: Callable) -> void:
	var cw := w - 2.0 - 24.0
	var btn_w := roundf((cw - 6.0) * 0.5)
	var h := 1.0 + 12.0 + 15.0 + 8.0 + 3.0 * 34.0 + 2.0 * 6.0 + 12.0 + 1.0
	var top := AREA.y - MARGIN - h
	K.panel(parent, x, top, w, h)
	var cx := x + 1.0 + 12.0
	var cap := K.text(parent, "Lenses", {"x": cx, "y": top + 1.0 + 12.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var y := top + 1.0 + 12.0 + cap.size.y + 8.0
	for i in LENSES.size():
		var id: String = LENSES[i][0]
		var wide := i == LENSES.size() - 1
		var bx := cx + (0.0 if wide else float(i % 2) * (btn_w + 6.0))
		var by := y + float(i / 2) * 40.0
		var b := K.button(parent, str(LENSES[i][1]), bx, by, {"min_h": 34, "px": 15, "pad": 12, "primary": bool(lenses.get(id, false)), "w": cw if wide else btn_w, "h": 34})
		b.set_meta("lens", id)
		if emit.is_valid():
			b.pressed.connect(emit.bind("region_lens", id))
