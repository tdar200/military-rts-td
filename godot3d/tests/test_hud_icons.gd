extends RefCounted
## HUD icon truth: on Kestrel (world art on) every building and unit icon in the deck, the queue card and the group chips is the
## kind's own world sprite (WorldSprites.SPRITES), not another kind's stand-in. Survival keeps its legacy icon table.
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Stub = preload("res://tests/stub_game.gd")
const WorldSprites = preload("res://scripts/world/world_sprites.gd")
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")

const STALE := ["VehicleFactory", "Airfield", "SupplyDepot", "ResearchLab", "Battery"]


func _world_path(kind: String) -> String:
	return "res://assets/world/sprites/%s.png" % WorldSprites.SPRITES[kind][0]


func _make(kestrel := true) -> Array:
	var g := Stub.new()
	g.world_art_on = kestrel
	var a := Adapter.new(g)
	a.tab = "build"
	return [g, a]


func test_every_build_card_resolves_to_its_own_world_sprite(t) -> void:
	for card in Adapter.BUILD_CARDS:
		var kind := String(card[1])
		var path: String = Adapter.icon_path_for_building(kind)
		t.eq(path, _world_path(kind), "%s icon is its world sprite" % kind)
		t.ok(ResourceLoader.exists(path), "%s icon texture exists" % kind)
		if kind != "Barracks":
			t.ok(not path.contains("barracks_v2"), "%s does not borrow the barracks art" % kind)


func test_the_five_stale_kinds_have_distinct_art(t) -> void:
	var seen := {}
	for card in Adapter.BUILD_CARDS:
		var path: String = Adapter.icon_path_for_building(String(card[1]))
		t.ok(not seen.has(path), "%s shares an icon with %s" % [card[1], seen.get(path, "")])
		seen[path] = card[1]
	for kind in STALE:
		t.ok(Adapter.icon_path_for_building(kind).begins_with("res://assets/world/sprites/"), "%s uses the world sprite folder" % kind)


func test_all_six_unit_kinds_resolve(t) -> void:
	for kind in WorldSprites.UNIT_KINDS:
		var path: String = Adapter.icon_path_for_unit(kind)
		t.eq(path, _world_path(kind), "%s icon is its world sprite" % kind)
		t.ok(ResourceLoader.exists(path), "%s unit icon texture exists" % kind)
	t.eq(Adapter.icon_path_for_unit("Barracks"), "", "a building is not a unit icon")
	t.eq(Adapter.icon_path_for_building("Tank"), "", "a unit is not a building icon")
	t.eq(Adapter.icon_path_for_building("NoSuchKind"), "", "an unknown kind falls back to the generic icon")


func test_the_build_deck_cards_use_the_mapping_on_kestrel(t) -> void:
	var p := _make()
	var cards: Array = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.eq(cards.size(), Adapter.BUILD_CARDS.size(), "one card per spec")
	for i in cards.size():
		t.eq(cards[i]["sprite"], Adapter.icon_path_for_building(String(Adapter.BUILD_CARDS[i][1])), "%s card sprite" % Adapter.BUILD_CARDS[i][2])


func test_survival_keeps_its_legacy_deck_icons(t) -> void:
	var p := _make(false)
	var cards: Array = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	var factory := {}
	for c in cards:
		if c["id"] == "factory":
			factory = c
	t.eq(factory.get("sprite", ""), "res://assets/ui/sprites/barracks_v2.png", "Survival factory card unchanged")
	t.eq(p[1].BUILD_CARDS.size(), 11, "Survival deck keeps its eleven cards")


func test_the_queue_card_shows_the_producing_unit_sprite(t) -> void:
	for pair in [["Tank", "VehicleFactory"], ["Helicopter", "Airfield"], ["Harvester", "Refinery"], ["Infantry", "Barracks"]]:
		var p := _make()
		var node: Node3D = p[0].add_node(8, pair[1], "building", 0, Vector3.ZERO)
		node.set_meta("production_name", pair[0])
		node.set_meta("production_progress", 10)
		node.set_meta("production_duration", 60)
		p[0].selected = node
		p[0].selected_units = [node]
		var q: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]["queue"]
		t.eq(q["sprite"], Adapter.icon_path_for_unit(pair[0]), "%s queue sprite" % pair[0])
		t.ok(not String(q["sprite"]).contains("foundation_v1"), "%s queue is not the foundation slab" % pair[0])
		node.free()


func test_the_queue_card_keeps_the_slab_on_survival(t) -> void:
	var p := _make(false)
	var node: Node3D = p[0].add_node(8, "Barracks", "building", 0, Vector3.ZERO)
	node.set_meta("production_name", "Infantry")
	node.set_meta("production_duration", 60)
	p[0].selected = node
	p[0].selected_units = [node]
	t.eq(p[1].hud_vm(0.0)["deck"]["body"]["queue"]["sprite"], "res://assets/ui/sprites/foundation_v1.png", "Survival queue unchanged")
	node.free()


func test_group_chips_cover_all_six_unit_kinds_on_kestrel(t) -> void:
	var p := _make()
	p[1].tab = "units"
	var list: Array[Node3D] = []
	var id := 10
	for kind in WorldSprites.UNIT_KINDS:
		for i in 2:
			list.append(p[0].add_node(id, kind, "unit", 0, Vector3.ZERO, 90.0, 100.0))
			id += 1
	p[0].selected_units = list
	p[0].selected = list[0]
	var groups: Array = p[1].hud_vm(0.0)["selection"]["groups"]
	t.eq(groups.size(), 6, "six kinds")
	for g in groups:
		t.eq(g.get("sprite", ""), Adapter.icon_path_for_unit(String(g["id"])), "%s group chip sprite" % g["id"])
		t.ok(not g.has("icon"), "%s group chip needs no generic icon" % g["id"])
	for n in list:
		n.free()


func test_group_chips_keep_the_generic_icon_on_survival(t) -> void:
	var p := _make(false)
	p[1].tab = "units"
	var list: Array[Node3D] = [p[0].add_node(20, "Harvester", "unit", 0, Vector3.ZERO), p[0].add_node(21, "Harvester", "unit", 0, Vector3.ZERO)]
	p[0].selected_units = list
	p[0].selected = list[0]
	var groups: Array = p[1].hud_vm(0.0)["selection"]["groups"]
	t.ok(groups[0].has("icon"), "Survival harvester chip keeps the icon")
	for n in list:
		n.free()


func test_the_structure_panel_uses_the_same_mapping(t) -> void:
	for kind in ["VehicleFactory", "Airfield", "SupplyDepot", "ResearchLab", "Battery", "Barracks", "CommandCenter", "Tank", "Harvester"]:
		var want: String = Adapter.icon_path_for_building(kind) if kind in WorldSprites.SPRITES and not kind in WorldSprites.UNIT_KINDS else Adapter.icon_path_for_unit(kind)
		t.eq(VmGameplay._sprite_path(kind), want, "%s snapshot panel sprite" % kind)
