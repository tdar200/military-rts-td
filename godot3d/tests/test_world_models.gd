extends RefCounted
## Kestrel buildings and units (spec addendum W6): authored models fitted to a visual width table in tiles.
const WorldArt := preload("res://scripts/world/world_art.gd")
const MainScene = preload("res://main.tscn")
const WorldProps := preload("res://scripts/world/world_props.gd")


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	scene._sync_ground(JSON.parse_string(f.get_as_text()))
	return scene


func _width(node: Node3D) -> float:
	var box := WorldArt.merged_aabb(node)
	return maxf(box.size.x, box.size.z) * node.scale.x


func test_fit_factor_hits_the_target_width(t) -> void:
	var packed := load("res://assets/models/authored/human_hq.glb") as PackedScene
	var hq := packed.instantiate() as Node3D
	var k := WorldArt.fit_factor(hq, 2.8)
	hq.scale = Vector3.ONE * k
	t.near(_width(hq), 2.8 * WorldArt.TILE, 0.01, "the CC is 2.8 tiles wide")
	hq.free()


func test_every_building_kind_has_a_width(t) -> void:
	for kind in ["CommandCenter", "PowerPlant", "Refinery", "Barracks", "VehicleFactory", "Airfield", "SupplyDepot", "Battery", "GunTurret", "AaTurret", "Wall", "ResearchLab", "AntimatterPlant"]:
		t.ok(WorldArt.BUILDING_TILES.has(kind), kind)


func test_kestrel_buildings_are_authored_and_sized(t) -> void:
	var scene := _kestrel_scene()
	for kind in ["CommandCenter", "Barracks", "GunTurret", "Wall"]:
		var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 900)
		var visual := root.get_node("Visual") as Node3D
		t.ok(visual.scene_file_path.ends_with(".glb"), "%s uses the authored model" % kind)
		t.near(_width(visual), float(WorldArt.BUILDING_TILES[kind]) * WorldArt.TILE, 0.05, "%s width" % kind)
		t.near(float(root.get_meta("visual_tiles", 0.0)), float(WorldArt.BUILDING_TILES[kind]), 0.001, "%s meta" % kind)
		t.eq(root.find_children("*", "Label3D", true, false).size(), 0, "%s has no banner" % kind)
		var bar := root.get_node("HealthBack") as Node3D
		t.ok(bar.position.y > WorldArt.merged_aabb(visual).end.y * visual.scale.y, "%s health bar above the model" % kind)
	scene.free()


func test_kestrel_tank_is_bigger_than_infantry(t) -> void:
	var scene := _kestrel_scene()
	scene._create_unit(0, Vector3(6, 0, 6), 1)
	var tank: Node3D = scene.units.back()
	scene._create_unit(0, Vector3(7, 0, 6), 0)
	var rifle: Node3D = scene.units.back()
	t.near(float(tank.get_meta("visual_tiles", 0.0)), float(WorldArt.UNIT_TILES[1]), 0.001, "tank width from the table")
	t.ok(float(tank.get_meta("visual_tiles")) > float(rifle.get_meta("visual_tiles")), "tank reads bigger than a rifle squad")
	scene.free()


func test_kestrel_unit_bars_sit_above_the_fitted_model(t) -> void:
	var scene := _kestrel_scene()
	for kind in [0, 1, 5]:
		scene._create_unit(1, Vector3(6, 0, 6), kind)
		var unit: Node3D = scene.units.back()
		var visual := unit.get_node("UnitVisual") as Node3D
		t.near(_width(visual), float(WorldArt.UNIT_TILES[kind]) * WorldArt.TILE, 0.05, "kind %d width" % kind)
		var bar := unit.get_node("HealthBack") as Node3D
		t.ok(bar.position.y > WorldArt.merged_aabb(visual).end.y * visual.scale.y, "kind %d health bar above the model" % kind)
	scene.free()


func test_kestrel_construction_grows_the_fitted_model(t) -> void:
	var scene := _kestrel_scene()
	var root: Node3D = scene._create_bridge_building(0, "Barracks", Vector3(10, 0, 10), 901)
	var visual := root.get_node("Visual") as Node3D
	t.ok(visual.get_meta("authored_scale").is_equal_approx(visual.scale), "the construction scale is the fitted one")
	scene.free()


func test_kestrel_human_models_take_the_board_palette(t) -> void:
	var scene := _kestrel_scene()
	var root: Node3D = scene._create_bridge_building(0, "CommandCenter", Vector3(10, 0, 10), 902)
	var colours := {}
	for mi in root.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
			if m:
				colours[m.albedo_color.to_html(false)] = true
	t.ok(colours.has(String(WorldArt.MODEL_PALETTE.concrete)), "warm concrete from the palette: %s" % [colours.keys()])
	t.ok(not colours.has("777a70"), "not the legacy grey concrete")
	scene.free()


func test_kestrel_buildings_clear_by_width_and_take_a_pad(t) -> void:
	var scene := _kestrel_scene()
	var props = scene.world_props
	var free_before: int = props._free_pads.size()
	var at := Vector3(14.0, 0.0, 9.0)
	scene._create_bridge_building(0, "CommandCenter", at, 903)
	t.eq(props._free_pads.size(), free_before - 1, "one pad slot taken")
	var slot: int = props._decal_base + WorldProps.PAD_SLOTS - free_before  # the dummy renderer reads transforms back as identity
	var radius: float = float(WorldArt.BUILDING_TILES.CommandCenter) * WorldArt.TILE * 0.5
	for i in props._card_at.size():
		var p: Vector3 = props._card_at[i]
		if props._card_pinned[i] == 0 and Vector2(p.x, p.z).distance_to(Vector2(at.x, at.z)) < radius:
			t.ok(false, "a prop card is left under the CC at %s" % p)
			break
	props.release_pad(slot)
	t.eq(props._free_pads.size(), free_before, "release gives the slot back")
	scene.free()


func test_kestrel_selection_ring_wraps_the_model(t) -> void:
	var scene := _kestrel_scene()
	var ui_stub := GDScript.new()
	ui_stub.source_code = "extends Node\nfunc set_tab(_tab: String) -> void:\n\tpass\n"
	ui_stub.reload()
	scene.ui = Node.new()
	scene.ui.set_script(ui_stub)
	var root: Node3D = scene._create_bridge_building(0, "CommandCenter", Vector3(10, 0, 10), 904)
	scene._set_selection([root])
	t.near(scene.selection_ring.scale.x, 2.8 * WorldArt.TILE * 0.55 / 0.46, 0.001, "ring scaled to the CC width")
	scene._create_unit(0, Vector3(6, 0, 6), 0)
	scene._set_selection([scene.units.back()])
	t.near(scene.selection_ring.scale.x, 1.0 * WorldArt.TILE * 0.55 / 0.46, 0.001, "ring scaled to a squad")
	scene.ui.free()
	scene.free()


func test_kestrel_blocked_tiles_get_no_legacy_ruins_or_rocks(t) -> void:
	var scene := _kestrel_scene()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	var before: int = scene.get_child_count()
	scene._sync_bridge_map(snap)
	t.ok(scene.blocked_tiles.size() > 100, "blocked tiles still recorded for the rules")
	t.eq(scene.get_child_count() - before, snap.deposits.size(), "only the deposit roots are added (the painted props dress blocked ground)")
	scene.free()


func test_kestrel_hover_outline_stays_off_occupied_hexes(t) -> void:
	# the outline draws without a depth test (Task 7), so on a building or unit hex it would paint over the model
	var scene := _kestrel_scene()
	var tile := Vector2i(10, 10)
	var world: Vector3 = scene._hex_world(tile.x, tile.y)
	scene.bridge_nodes[905] = scene._create_bridge_building(0, "Barracks", world, 905)
	scene._show_hover_at(world)
	t.ok(not scene.hover_tile.visible, "hidden on the building's own hex")
	t.eq(scene.hover_cell, tile, "the hex is still hovered (the inspector reads it)")
	var east: Vector3 = scene._hex_world(tile.x + 1, tile.y)
	scene._show_hover_at(east)
	t.ok(scene.hover_tile.visible, "shown on the neighbour hex under the model's overhang")
	scene._create_unit(0, east, 1)
	scene.bridge_nodes[906] = scene.units.back()
	scene._show_hover_at(east)
	t.ok(not scene.hover_tile.visible, "hidden under a unit")
	scene.free()


func test_kestrel_shared_models_keep_each_kinds_width(t) -> void:
	# Refinery (2.1) and SupplyDepot (1.7) share human_refinery; an unknown kind falls back to human_industry (1.7), the
	# VehicleFactory model (2.1). Build order must not decide the size.
	for order in [["Refinery", "SupplyDepot"], ["SupplyDepot", "Refinery"], ["VehicleFactory", "Bunker"], ["Bunker", "VehicleFactory"]]:
		var scene := _kestrel_scene()
		for kind in order:
			var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 910)
			var want := float(WorldArt.BUILDING_TILES.get(kind, 1.7)) * WorldArt.TILE
			t.near(_width(root.get_node("Visual") as Node3D), want, 0.05, "%s width after %s" % [kind, order[0]])
		scene.free()
