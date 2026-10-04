extends Control
## Earthfront HUD, built from a plain view model. Never reads game state; emits `action` for every click.
## Geometry is the Main mock at 1920x1080 (see docs/ascension/ui-mocks/Main.dc.html and tools/ui/box.py).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const MapMarks = preload("res://scripts/ui/components/map_marks.gd")
const ResourcePins = preload("res://scripts/ui/sections/resource_pins.gd")
const TerritoryCard = preload("res://scripts/ui/sections/territory_card.gd")
const BottomPanel = preload("res://scripts/ui/sections/bottom_panel.gd")
const TileInspector = preload("res://scripts/ui/sections/tile_inspector.gd")
const ColonyLedger = preload("res://scripts/ui/sections/colony_ledger.gd")
const ArmyOrders = preload("res://scripts/ui/sections/army_orders.gd")
const AlertChips = preload("res://scripts/ui/sections/alert_chips.gd")
const MinimapLenses = preload("res://scripts/ui/sections/minimap_lenses.gd")
const GridProjection = preload("res://scripts/ui/sections/grid_projection.gd")
const EnemyIntel = preload("res://scripts/ui/sections/enemy_intel.gd")
const PlacementCard = preload("res://scripts/ui/sections/placement_card.gd")
const CombatPreview = preload("res://scripts/ui/sections/combat_preview.gd")
const StructurePanel = preload("res://scripts/ui/sections/structure_panel.gd")
const SiteCard = preload("res://scripts/ui/sections/site_card.gd")
const SelectionRoster = preload("res://scripts/ui/sections/selection_roster.gd")
const AttackMoveBanner = preload("res://scripts/ui/sections/attack_move_banner.gd")
const WavePanel = preload("res://scripts/ui/sections/wave_panel.gd")
const ControlGroups = preload("res://scripts/ui/sections/control_groups.gd")
const LogisticsTab = preload("res://scripts/ui/sections/logistics_tab.gd")

signal action(name: String, arg: Variant)

## Sections rebuild only when their slice of the view model changes, so a button never vanishes mid-click.
const SECTIONS := [
	["top_chips", "_build_top_chips"],
	["top_speed", "_build_top_speed"],
	["objectives", "_build_objectives"],
	["power_tip", "_build_power_tip"],
	["wave_card", "_build_wave_card"],
	["alerts", "_build_alerts"],
	["minimap", "_build_minimap"],
	["minimap_slot", ""],
	["minimap_marks", "_build_minimap_marks"],
	["selection", "_build_selection"],
	["deck_tabs", "_build_deck_tabs"],
	["deck_body", "_build_deck_body"],
]

## Gameplay sections (sections/*.gd), registered in board stacking order: hud key -> the view-model keys its builder reads.
## A section's slice is the dictionary of those keys that are present (null when none is), so it rebuilds only when its
## own data changes.
const GAMEPLAY_KEYS := {
	"resource_pins": ["pins"],
	"territory_card": ["territory", "yields"],
	"bottom_panel": ["inspect", "ledger", "army"],
	"tile_inspector": ["inspect"],
	"colony_ledger": ["ledger"],
	"army_orders": ["army"],
	"alert_chips": ["idle", "alert"],
	"minimap_lenses": ["lens"],
	"grid_projection": ["power_grid"],
	"enemy_intel": ["enemy"],
	"placement_card": ["placing"],
	"combat_preview": ["combat"],
	"structure_panel": ["structure"],
	"selection_roster": ["roster"],
	"site_card": ["site"],
	"wave_panel": ["wave_panel"],
	"control_groups": ["control_groups"],
	"attack_move_banner": ["armed"],
}

## Where the live minimap is drawn. A layout that builds its own slot (core assault) sets this; once that layout's nodes
## are removed the Hud's own slot is used again, so the host never holds a freed node.
var map_slot: Control:
	get:
		if is_instance_valid(_slot_override) and _slot_override.get_parent() != null:
			return _slot_override
		return _home_slot
	set(value):
		_slot_override = value
var _home_slot: Control
var _slot_override: Control
var _layers: Dictionary = {}
var _hashes: Dictionary = {}
var _extra: Array = []
var _body_builders: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Layers are created once, in section order, so z-order never changes and persistent children (the map slot) survive rebuilds.
	for entry in SECTIONS:
		_layer(entry[0])
	_home_slot = Control.new()
	_home_slot.name = "MapSlot"
	_home_slot.clip_contents = true
	_home_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(_home_slot, 21, 811, 288, 250)
	_layers["minimap_slot"].add_child(_home_slot)
	_register_gameplay()


## The gameplay sections. Pins sit under every panel (they are world-anchored); the rest stack in the board's order.
func _register_gameplay() -> void:
	var emit := Callable(self, "_emit")
	register_section("resource_pins", func(layer: Control, slice: Variant) -> void: ResourcePins.build(layer, slice, emit), "top_chips")
	register_section("territory_card", func(layer: Control, slice: Variant) -> void: TerritoryCard.build(layer, slice))
	register_section("bottom_panel", func(layer: Control, slice: Variant) -> void: BottomPanel.build(layer, slice))
	register_section("tile_inspector", func(layer: Control, slice: Variant) -> void: TileInspector.build(layer, slice))
	register_section("colony_ledger", func(layer: Control, slice: Variant) -> void: ColonyLedger.build(layer, slice))
	register_section("army_orders", func(layer: Control, slice: Variant) -> void: ArmyOrders.build(layer, slice, emit))
	register_section("alert_chips", func(layer: Control, slice: Variant) -> void: AlertChips.build(layer, slice, emit))
	register_section("minimap_lenses", func(layer: Control, slice: Variant) -> void: MinimapLenses.build(layer, slice, emit))
	# Boards 2 and 3. The cards float over the map, so they come last (on top of the panels).
	register_section("grid_projection", func(layer: Control, slice: Variant) -> void: GridProjection.build(layer, slice))
	register_section("enemy_intel", func(layer: Control, slice: Variant) -> void: EnemyIntel.build(layer, slice))
	register_section("placement_card", func(layer: Control, slice: Variant) -> void: PlacementCard.build(layer, slice))
	register_section("combat_preview", func(layer: Control, slice: Variant) -> void: CombatPreview.build(layer, slice))
	# Boards 4, 5 and 7: the selected structure and the roster take the bottom frame, the cards stack down the left side.
	register_section("structure_panel", func(layer: Control, slice: Variant) -> void: StructurePanel.build(layer, slice, emit))
	register_section("selection_roster", func(layer: Control, slice: Variant) -> void: SelectionRoster.build(layer, slice, emit))
	register_section("site_card", func(layer: Control, slice: Variant) -> void: SiteCard.build(layer, slice))
	register_section("wave_panel", func(layer: Control, slice: Variant) -> void: WavePanel.build(layer, slice))
	register_section("control_groups", func(layer: Control, slice: Variant) -> void: ControlGroups.build(layer, slice, emit))
	register_section("attack_move_banner", func(layer: Control, slice: Variant) -> void: AttackMoveBanner.build(layer, slice))
	# Board 8: the Logistics deck tab replaces the deck body while its tab is open.
	register_body("logistics", func(layer: Control, body: Variant) -> void: LogisticsTab.build(layer, body, emit))


func _layer(key: String) -> Control:
	var layer := Control.new()
	layer.name = key
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	_layers[key] = layer
	return layer


## Add a section fed by vm[key]. `builder` is Callable(layer: Control, slice: Variant); it is rebuilt only when the slice changes.
## `before` names an existing section whose layer this one must sit under (used to keep a frame below the map slot).
func register_section(key: String, builder: Callable, before := "") -> void:
	_extra.append([key, builder])
	var layer := _layer(key)
	if before != "" and _layers.has(before):
		move_child(layer, (_layers[before] as Control).get_index())


## Add a deck body kind: vm.deck.body.kind == kind is drawn by Callable(layer: Control, body: Dictionary).
func register_body(kind: String, builder: Callable) -> void:
	_body_builders[kind] = builder


func apply(vm: Dictionary) -> void:
	var entries: Array = SECTIONS + _extra
	# The marks overlay follows the map slot, so it is rebuilt after whichever section moved the slot.
	entries.sort_custom(func(a, b): return str(b[0]) == "minimap_marks" and str(a[0]) != "minimap_marks")
	for entry in entries:
		var key: String = entry[0]
		if entry[1] is String and entry[1] == "":
			continue
		var slice: Variant = _slice(vm, key)
		var h := hash(slice)
		if _hashes.get(key, -1) == h and _layers.has(key):
			continue
		_hashes[key] = h
		_rebuild(key, entry[1], slice)


## Which part of the view model feeds each section.
func _slice(vm: Dictionary, key: String) -> Variant:
	match key:
		"top_chips":
			if not vm.has("chips"):
				return null
			return {"brand": vm.get("brand", {}), "chips": vm["chips"], "wave": vm.get("wave", {}), "has_speed": vm.has("speed")}
		"minimap_marks":
			var m: Variant = vm.get("map_marks", null)
			if m == null:
				return null
			return {"marks": m.get("marks", []), "view": m.get("view", {}), "rect": [map_slot.position, map_slot.size]}
		"top_speed":
			return vm.get("speed", null)
		"deck_tabs":
			return vm["deck"].get("tabs", []) if vm.has("deck") else null
		"deck_body":
			return vm["deck"].get("body", {}) if vm.has("deck") else null
		_:
			if GAMEPLAY_KEYS.has(key):
				var part := {}
				for k in GAMEPLAY_KEYS[key]:
					if vm.has(k):
						part[k] = vm[k]
				return part if not part.is_empty() else null
			return vm.get(key, null)


func _rebuild(key: String, builder: Variant, slice: Variant) -> void:
	var layer: Control = _layers[key]
	for child in layer.get_children():
		layer.remove_child(child)
		child.queue_free()
	if slice == null:
		return
	if builder is Callable:
		builder.call(layer, slice)
	else:
		call(builder, layer, slice)


## True when `point` (in this control's space) is over any HUD surface, so the 3D scene must not react to it.
func blocks_point(point: Vector2) -> bool:
	for layer in _layers.values():
		for child in layer.get_children():
			if child is Control and child.visible and child.mouse_filter == Control.MOUSE_FILTER_STOP:
				if Rect2(child.position, child.size).has_point(point):
					return true
	return false


func _emit(name: String, arg: Variant = null) -> void:
	action.emit(name, arg)


# ---------------------------------------------------------------- top bar

func _build_top_chips(root: Control, vm: Dictionary) -> void:
	var bar := K.panel(root, 12, 10, 1896, 56)
	var brand: Dictionary = vm.get("brand", {})
	var logo := TextureRect.new()
	logo.texture = Icons.logo(25)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.place(logo, 27, 25.5, 25, 25)
	root.add_child(logo)
	K.text(root, str(brand.get("title", "Ascension")), {"x": 61.6, "y": 15, "w": 134.8, "f": "disp", "wt": 600, "px": 20, "sp": 0.14, "lh": 20, "col": T.TEXT_HI, "up": true})
	K.text(root, str(brand.get("sub", "")), {"x": 61.6, "y": 35, "w": 134.8, "f": "mono", "px": 11, "sp": 0.12, "lh": 13, "col": T.DIM, "up": true, "wrap": true})
	K.rule(root, 210, 20, 1, 36, T.LINE_DIM)
	var x := 221.4
	for chip in vm.get("chips", []):
		var warn: bool = chip.get("state", "") == "warn"
		var value_col: Color = T.WARN if warn else T.TEXT_HI
		var o := {}
		if warn:
			o = {"border": T.WARN, "ring": Color(T.WARN.r, T.WARN.g, T.WARN.b, 0.35)}
		var c := K.chip(root, x, 24, str(chip.get("icon", "")), T.tone(str(chip.get("tone", "cyan"))), [
			{"t": str(chip.get("label", "")), "col": T.DIM, "up": true},
			{"t": str(chip.get("value", "")), "col": value_col, "wt": 500},
		], o)
		x += c.size.x + 10.0
	var wave: Dictionary = vm.get("wave", {})
	if not wave.is_empty():
		var chip := K.chip(root, 0, 20, "wave", T.WARN, [
			{"t": str(wave.get("label", "")), "col": T.WARN, "sp": 0.1, "up": true},
			{"t": str(wave.get("timer", "")), "col": T.WARN_HI, "f": "disp", "px": 22, "wt": 600, "sp": 0.06, "up": true},
		], {"h": 36, "pad": 14, "gap": 12, "border": T.WARN, "fill": Color(T.WARN.r, T.WARN.g, T.WARN.b, 0.10)})
		# Right-aligned against the speed group (137.2 wide, 6px margin, 10px gap), or the bar edge when there is none.
		var right_edge := 1893.0 - 137.2 - 6.0 - 10.0 if vm.get("has_speed", false) else 1893.0
		chip.position = Vector2(roundf(right_edge - chip.size.x), 20)


func _build_top_speed(root: Control, vm: Dictionary) -> void:
	var pause := K.button(root, "", 0, 20, {"icon": "pause", "min_h": 36, "pad": 10})
	var rate: int = int(vm.get("rate", 1))
	var one := K.button(root, "1x", 0, 20, {"min_h": 36, "pad": 12, "primary": rate == 1 and not vm.get("paused", false)})
	var two := K.button(root, "2x", 0, 20, {"min_h": 36, "pad": 12, "primary": rate == 2 and not vm.get("paused", false)})
	if vm.get("paused", false):
		pause.primary = true
	var total: float = pause.size.x + one.size.x + two.size.x + 8.0
	var x := 1893.0 - total
	for b in [pause, one, two]:
		b.position = Vector2(roundf(x), 20)
		x += b.size.x + 4.0
	pause.pressed.connect(_emit.bind("speed", 0))
	one.pressed.connect(_emit.bind("speed", 1))
	two.pressed.connect(_emit.bind("speed", 2))


# ---------------------------------------------------------------- objectives, wave card, power tip

func _build_objectives(root: Control, vm: Dictionary) -> void:
	var items: Array = vm.get("items", [])
	var panel := K.panel(root, 12, 76, 420, 42 + 25 * items.size())
	K.text(root, str(vm.get("cap", "")), {"x": 27, "y": 89, "w": 390, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var y := 112.0
	for item in items:
		var state: String = item.get("state", "todo")
		var icon_col: Color = T.GOOD if state == "done" else (T.CYAN if state == "active" else T.DIM)
		var icon_name := "check" if state == "done" else ("circle" if state == "active" else "circle_dashed")
		K.icon(root, icon_name, 27, y, icon_col)
		K.text(root, str(item.get("t", "")), {"x": 55, "y": y, "w": 362, "px": 14, "col": T.CYAN if state == "active" else T.DIM, "strike": state == "done"})
		y += 25.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP


func _build_wave_card(root: Control, vm: Dictionary) -> void:
	var panel := K.panel(root, 962, 76, 440, 150, "panel", {"border": Color(T.WARN.r, T.WARN.g, T.WARN.b, 0.6)})
	var tag := K.tag(root, str(vm.get("tag", "")), 977, 89, T.WARN)
	K.text(root, str(vm.get("eta", "")), {"x": 977 + tag.size.x + 10, "y": 92.5, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var title := K.text(root, str(vm.get("title", "")), {"x": 977, "y": 117, "w": 410, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "col": T.WARN_HI, "up": true, "wrap": true})
	var y: float = 117.0 + title.size.y + 4.0
	var body_h := 0.0
	var body_text := str(vm.get("body", ""))
	if body_text != "":
		var body := K.text(root, body_text, {"x": 977, "y": y, "w": 410, "px": 14, "col": T.DIM, "wrap": true})
		body_h = body.size.y
	panel.size.y = (y - 76.0) + body_h + 12.0 + 1.0
	panel.queue_redraw()


func _build_power_tip(root: Control, vm: Dictionary) -> void:
	var panel := K.panel(root, 462, 76, 448, 257, "panel", {"border": T.WARN, "ring": Color(T.WARN.r, T.WARN.g, T.WARN.b, 0.5)})
	K.text(root, str(vm.get("title", "")), {"x": 479, "y": 91, "f": "disp", "wt": 600, "px": 20, "sp": 0.04, "col": T.WARN, "up": true})
	var tag := K.tag(root, str(vm.get("tag", "")), 0, 93, T.WARN)
	tag.position.x = roundf(893.0 - tag.size.x)
	var para := K.text(root, str(vm.get("body", "")), {"x": 479, "y": 123, "w": 414, "px": 14, "col": T.DIM, "wrap": true})
	var top: float = 123.0 + para.size.y + 10.0
	var col_h := 0.0
	var columns: Array = [["Producers", vm.get("producers", []), 479.0], ["Largest consumers", vm.get("consumers", []), 693.0]]
	if vm.get("producers", []).is_empty() and vm.get("consumers", []).is_empty():
		columns = []
		top -= 10.0
	for col in columns:
		K.text(root, col[0], {"x": col[2], "y": top, "w": 200, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
		var ry := top + 15.0 + 6.0
		for row in col[1]:
			K.text(root, str(row.get("n", "")), {"x": col[2], "y": ry, "px": 14})
			var v := K.text(root, str(row.get("v", "")), {"x": 0, "y": ry, "f": "mono", "px": 14})
			v.position.x = roundf(col[2] + 200.0 - v.size.x)
			ry += 22.0
		col_h = maxf(col_h, ry - 4.0 - top)
	var btn_y: float = top + col_h + 12.0
	var focus := K.button(root, "Focus on map", 479, btn_y, {"min_h": 36, "px": 15})
	var build := K.button(root, str(vm.get("cta", "Build reactor")), 479 + focus.size.x + 10, btn_y, {"min_h": 36, "px": 15, "primary": true, "key": str(vm.get("cta_key", ""))})
	focus.pressed.connect(_emit.bind("focus_power", null))
	build.pressed.connect(_emit.bind("build_power", null))
	panel.size.y = (btn_y + 36.0 + 14.0 + 1.0) - 76.0
	panel.queue_redraw()


# ---------------------------------------------------------------- alerts and minimap

func _build_alerts(root: Control, vm: Array) -> void:
	var y := 520.0
	for alert in vm:
		var tone: Color = T.tone(str(alert.get("tone", "cyan")))
		var hostile: bool = alert.get("hostile", false)
		var panel := K.panel(root, 12, y, 300, 53, "glass", {"accent": tone, "radius": 3})
		var x := 25.0
		if hostile:
			K.diamond(root, 31, y + 26.5, 8.5, T.BAD)
			x = 47.0
		else:
			K.icon(root, str(alert.get("icon", "wave")), 25, y + 17.5, tone)
			x = 53.0
		var head_col: Color = T.BAD_HI if tone == T.BAD else (T.WARN_HI if tone == T.WARN else T.TEXT)
		K.text(root, str(alert.get("title", "")), {"x": x, "y": y + 9, "w": 300 - (x - 12) - 11, "px": 14, "wt": 600, "col": head_col})
		K.text(root, str(alert.get("body", "")), {"x": x, "y": y + 27, "w": 300 - (x - 12) - 11, "px": 13, "col": T.DIM})
		if alert.get("action", "") != "":
			var hit := K.hit(root, 12, y, 300, 53, str(alert.get("title", "")))
			hit.pressed.connect(_emit.bind(str(alert["action"]), alert.get("arg")))
		y += 59.0


func _build_minimap(root: Control, vm: Dictionary) -> void:
	K.place(map_slot, 21, 811, 288, 250)
	K.panel(root, 12, 770, 304, 298)
	K.text(root, "Tactical", {"x": 25, "y": 778, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	K.text(root, "/", {"x": 102.8, "y": 778, "f": "mono", "px": 12, "sp": 0.12, "col": T.FAINT})
	K.text(root, str(vm.get("name", "Earthfront")), {"x": 25, "y": 793, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var x := 194.2
	for key in vm.get("keys", []):
		var cap := K.key(root, str(key.get("k", "")), x, 782, {"border": T.CYAN if key.get("on", false) else T.LINE, "col": T.CYAN_HI if key.get("on", false) else T.TEXT})
		var hit := K.hit(root, x, 782, cap.size.x, 22, str(key.get("k", "")))
		hit.pressed.connect(_emit.bind("minimap_layer", key.get("k")))
		x += cap.size.x + 4.0


## Unit dots and the camera frustum over the live map. Marks are {x, y, k} in 0..1 map space; k is f friendly, e elite, h hostile, H big hostile.
func _build_minimap_marks(root: Control, vm: Dictionary) -> void:
	var at: Vector2 = map_slot.position
	var span: Vector2 = map_slot.size
	var marks := MapMarks.new()
	K.place(marks, at.x, at.y, span.x, span.y)
	root.add_child(marks)
	marks.setup(vm.get("marks", []), vm.get("view", {}))
	var rim := Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = T.LINE_DIM
	rim.add_theme_stylebox_override("panel", box)
	K.place(rim, at.x, at.y, span.x, span.y)
	root.add_child(rim)


# ---------------------------------------------------------------- selection panel

func _build_selection(root: Control, vm: Dictionary) -> void:
	var panel := K.panel(root, 328, 810, 940, 258)
	var name_box := K.text(root, str(vm.get("name", "")), {"x": 347, "y": 825, "f": "disp", "wt": 600, "px": 26, "sp": 0.04, "lh": 26, "col": T.TEXT_HI, "up": true})
	K.tag(root, str(vm.get("count", "")), 347 + name_box.size.x + 10, 827, T.CYAN)
	K.text(root, str(vm.get("sub", "")), {"x": 347, "y": 855, "w": 330, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true, "wrap": true})
	var x := 347.0
	for group in vm.get("groups", []):
		var card := K.panel(root, x, 882, 96, 111, "glass", {"border": T.CYAN if group.get("on", false) else T.LINE_DIM})
		if group.get("icon", "") != "":
			K.icon(root, str(group["icon"]), x + 28, 897, T.CYAN_HI if group.get("on", false) else T.DIM, 40, 1.5)
		else:
			K.sprite(root, str(group.get("sprite", "")), x + 16, 889, 64, 64)
		K.text(root, str(group.get("label", "")), {"x": x + 7, "y": 957, "w": 82, "f": "mono", "px": 13, "al": "c", "col": T.TEXT})
		K.bar(root, x + 7, 978, 82, float(group.get("ratio", 0.0)), T.tone(str(group.get("tone", "good"))))
		var hit := K.hit(root, x, 882, 96, 111, str(group.get("label", "")))
		hit.pressed.connect(_emit.bind("select_group", group.get("id")))
		x += 104.0
	K.text(root, str(vm.get("footer", "")), {"x": 347, "y": 1005, "w": 330, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true, "wrap": true})
	K.rule(root, 695, 825, 1, 228, T.LINE_DIM)
	K.rule(root, 980, 825, 1, 228, T.LINE_DIM)
	var y := 825.0
	for row in vm.get("rows", []):
		y += _selection_row(root, 714.0, y, 248.0, row) + 10.0
	var preview: String = str(vm.get("preview", ""))
	if preview != "":
		var body := K.text(root, "Preview: " + preview, {"x": 725, "y": y + 9, "w": 226, "px": 13, "col": T.DIM, "wrap": true, "lead_len": 8, "lead_col": T.WARN})
		var glass := K.panel(root, 714, y, 248, body.size.y + 18.0, "glass", {"border": T.LINE})
		root.move_child(glass, body.get_index())
	_build_orders(root, vm.get("orders", []))


## One label/value row. Bars sit 4px under the text. Returns the row height.
func _selection_row(root: Control, x: float, y: float, w: float, row: Dictionary) -> float:
	var label := str(row.get("label", ""))
	var value := str(row.get("value", ""))
	var lw: float = _width("body", 14, 0, label)
	var vw: float = _width("mono", 14, 0, value)
	if lw + vw > w:
		var over := lw + vw - w
		var l2 := lw - over * lw / (lw + vw)
		var v2 := vw - over * vw / (lw + vw)
		lw = l2
		vw = v2
	var lb := K.text(root, label, {"x": x, "y": y, "w": lw + 0.5, "px": 14, "col": T.DIM, "wrap": true})
	var vb := K.text(root, value, {"x": x + w - vw, "y": y, "w": vw + 0.5, "f": "mono", "px": 14, "col": T.tone(str(row.get("tone", ""))) if row.get("tone", "") != "" else T.TEXT, "wrap": true})
	var h := maxf(lb.size.y, vb.size.y)
	if row.has("ratio"):
		K.bar(root, x, y + h + 4.0, w, float(row["ratio"]), T.tone(str(row.get("bar", "cyan"))))
		h += 4.0 + 6.0
	return h


func _width(kind: String, px: int, wt: int, s: String) -> float:
	var probe := TextBox.new()
	probe.configure(s, {"f": kind, "px": px, "wt": wt})
	var w := probe.measure(s)
	probe.free()
	return w


## Orders: up to four column buttons in a 2x2 grid (121x70 then 121x58), then at most one wide 250x44 button underneath.
func _build_orders(root: Control, orders: Array) -> void:
	var cells: Array = []
	var wide: Dictionary = {}
	for order in orders:
		if order.get("wide", false):
			if wide.is_empty():
				wide = order
		elif cells.size() < 4:
			cells.append(order)
	var origins := [Vector2(999, 825), Vector2(1128, 825), Vector2(999, 903), Vector2(1128, 903)]
	var heights := [70, 70, 58, 58]
	var rows := (cells.size() + 1) / 2
	for i in cells.size():
		var order: Dictionary = cells[i]
		var b := K.button(root, str(order.get("label", "")), origins[i].x, origins[i].y, {"column": true, "w": 121, "h": heights[i], "primary": order.get("primary", false), "key": str(order.get("key", ""))})
		b.pressed.connect(_emit.bind(str(order.get("action", "")), order.get("arg")))
		b.disabled = order.get("disabled", false)
	if not wide.is_empty():
		var wy := 825.0 + (70.0 + 8.0 if rows >= 1 else 0.0) + (58.0 + 8.0 if rows >= 2 else 0.0)
		var b := K.button(root, str(wide.get("label", "")), 999, wy, {"w": 250, "h": 44, "key": str(wide.get("key", ""))})
		b.pressed.connect(_emit.bind(str(wide.get("action", "")), wide.get("arg")))
		b.disabled = wide.get("disabled", false)


# ---------------------------------------------------------------- deck

func _build_deck_tabs(root: Control, tabs: Array) -> void:
	var x := 1284.0
	for tab in tabs:
		var b := K.button(root, str(tab.get("label", "")), x, 770, {"variant": "tab", "icon": str(tab.get("icon", "")), "on": tab.get("on", false)})
		b.pressed.connect(_emit.bind("deck_tab", tab.get("id")))
		x += b.size.x + 4.0


func _build_deck_body(root: Control, vm: Dictionary) -> void:
	var kind: String = vm.get("kind", "cards")
	if _body_builders.has(kind):
		_body_builders[kind].call(root, vm)
		return
	K.panel(root, 1284, 810, 624, 258, "panel", {"tl": 0})
	K.text(root, str(vm.get("title", "")), {"x": 1297, "y": 821, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var right := K.text(root, str(vm.get("right", "")), {"x": 0, "y": 821, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	right.position.x = roundf(1895.0 - right.size.x)
	var i := 0
	for card in vm.get("cards", []):
		_deck_card(root, 1297.0 + i * 151.5, 844.0, card)
		i += 1
	if vm.has("queue"):
		K.text(root, "Production queue", {"x": 1297, "y": 984, "w": 598, "f": "mono", "px": 12, "sp": 0.12, "col": T.DIM, "up": true})
	var q := 0
	for cell in vm.get("queue", []):
		var cx := 1297.0 + q * 82.0
		var empty: bool = cell.get("empty", false)
		K.panel(root, cx, 1005, 76, 34, "glass", {"border": T.CYAN if cell.get("on", false) else T.LINE_DIM, "dashed": empty})
		K.text(root, str(cell.get("label", "")), {"x": cx + 5, "y": 1010, "w": 66, "f": "mono", "px": 12, "al": "c", "col": T.FAINT if empty else T.TEXT, "up": true})
		if not empty:
			K.bar(root, cx + 5, 1028, 66, float(cell.get("ratio", 0.0)), T.CYAN)
		q += 1
	var status: Dictionary = vm.get("status", {})
	if not status.is_empty():
		var tag := K.tag(root, str(status.get("tag", "")), 1297, 1049, T.tone(str(status.get("tone", "warn"))))
		K.text(root, str(status.get("text", "")), {"x": 1297 + tag.size.x + 8, "y": 1051, "px": 14, "col": T.TEXT})


func _deck_card(root: Control, x: float, y: float, card: Dictionary) -> void:
	var locked: bool = card.get("locked", false)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.55 if locked else 1.0
	root.add_child(holder)
	K.panel(holder, x, y, 143.5, 130, "glass", {"border": T.CYAN if card.get("on", false) else T.LINE_DIM})
	if card.get("icon", "") != "":
		K.icon(holder, str(card["icon"]), x + 51.75, y + 17, T.CYAN_HI if card.get("on", false) else T.DIM, 40, 1.5)
	else:
		K.sprite(holder, str(card.get("sprite", "")), x + 41.75, y + 7, 60, 60, locked)
	var name_text := str(card.get("name", ""))
	var key_text := str(card.get("key", ""))
	var name_w := _spaced("disp", 15, 600, 0.04, name_text.to_upper() + " ")
	var key_w: float = KeyCap.measure(key_text) if key_text != "" else 0.0
	var left: float = x + 71.75 - (name_w + key_w) * 0.5
	K.text(holder, name_text, {"x": left, "y": y + 71, "f": "disp", "wt": 600, "px": 15, "sp": 0.04, "up": true})
	if key_text != "":
		K.key(holder, key_text, left + name_w, y + 71, {"wt": 600, "up": true, "sp": 0.04 * 15.0})
	K.text(holder, str(card.get("cost", "")), {"x": x + 7, "y": y + 93, "w": 129.5, "f": "mono", "px": 12, "al": "c", "col": T.tone(str(card.get("cost_tone", "dim"))), "wrap": true})
	if card.get("action", "") != "" and not locked:
		var hit := K.hit(root, x, y, 143.5, 130, name_text)
		hit.pressed.connect(_emit.bind(str(card["action"]), card.get("arg")))


func _spaced(kind: String, px: int, wt: int, sp_em: float, s: String) -> float:
	var probe := TextBox.new()
	probe.configure(s, {"f": kind, "px": px, "wt": wt, "sp": sp_em})
	var w := probe.measure(s)
	probe.free()
	return w
