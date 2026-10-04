extends RefCounted
## Core-assault HUD state (mock: CoreAssault.dc.html). Registers its sections and the orders deck body into a Hud and
## holds the helpers the section builders share. Nothing here reads game state: it is view model in, nodes out,
## `hud.action(name, arg)` out. World annotations (brackets, hostile marks, impact zone, callouts) are drawn by
## scripts/ui/world_marks.gd, which is a separate persistent control because it updates every frame.
const Chrome = preload("res://scripts/ui/assault/chrome.gd")
const Bottom = preload("res://scripts/ui/assault/bottom.gd")
const Vignette = preload("res://scripts/ui/assault/vignette.gd")

## View-model keys this state reads, in draw order. The orders deck arrives as vm.deck.body with kind "assault_orders".
const KEYS := ["as_top", "as_boss", "as_objective", "as_relays", "as_edge", "as_bottom", "as_selection", "as_vignette"]
const BODY_KIND := "assault_orders"

static func register(hud: Control) -> void:
	var emit := func(n: String, a: Variant = null) -> void: hud.action.emit(n, a)
	hud.register_section("as_top", func(layer: Control, s: Variant) -> void: Chrome.top(layer, s))
	hud.register_section("as_boss", func(layer: Control, s: Variant) -> void: Chrome.boss(layer, s))
	hud.register_section("as_objective", func(layer: Control, s: Variant) -> void: Chrome.objective(layer, s))
	hud.register_section("as_relays", func(layer: Control, s: Variant) -> void: Chrome.relays(layer, s, emit))
	hud.register_section("as_edge", func(layer: Control, s: Variant) -> void: Chrome.edge(layer, s, emit))
	hud.register_section("as_bottom", func(layer: Control, s: Variant) -> void: hud.map_slot = Bottom.bottom_left(layer, s, emit))
	hud.register_section("as_selection", func(layer: Control, s: Variant) -> void: Bottom.selection(layer, s, emit))
	hud.register_section("as_vignette", func(layer: Control, s: Variant) -> void: _vignette(layer, s, hud))
	hud.register_body(BODY_KIND, func(layer: Control, body: Dictionary) -> void: Bottom.deck(layer, body, emit))


static func _vignette(layer: Control, slice: Variant, hud: Control) -> void:
	var strength := 0.45
	if slice is Dictionary:
		strength = float(slice.get("strength", 0.45))
	elif slice is float or slice is int:
		strength = float(slice)
	var size: Vector2 = hud.size if hud.size.x > 0.0 else Vector2(1920, 1080)
	layer.add_child(Vignette.new().setup(size.x, size.y, strength))
