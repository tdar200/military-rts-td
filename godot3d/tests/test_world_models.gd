extends RefCounted
## Kestrel buildings and units (spec addendum W6): authored models fitted to a visual width table in tiles. Buildings and
## units with a board sprite are sprite cards now (test_world_sprites.gd); a kind without one ("Bunker") keeps the model.
const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")
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


func test_a_building_whose_sprite_fails_keeps_its_model_at_the_model_width(t) -> void:
	# the card widths (BUILDING_TILES) include a painting's transparent margin; a model has none, so it keeps its own table
	var scene := _kestrel_scene()
	WorldSprites.unavailable["barracks_v2"] = true
	var root: Node3D = scene._create_bridge_building(0, "Barracks", Vector3(10, 0, 10), 908)
	var visual := root.get_node("Visual") as Node3D
	t.ok(visual.scene_file_path.ends_with(".glb"), "the authored model")
	t.near(float(root.get_meta("visual_tiles", 0.0)), float(WorldArt.MODEL_BUILDING_TILES.Barracks), 0.001, "the model's own width")
	t.near(_width(visual), float(WorldArt.MODEL_BUILDING_TILES.Barracks) * WorldArt.TILE, 0.05, "fitted to it")
	t.ok(float(WorldArt.MODEL_BUILDING_TILES.Barracks) < float(WorldArt.BUILDING_TILES.Barracks), "narrower than the card")
	WorldSprites.unavailable.clear()
	scene.free()


func test_kestrel_kinds_without_a_sprite_keep_the_fitted_model(t) -> void:
	var scene := _kestrel_scene()
	for owner in [0, 1]:
		var root: Node3D = scene._create_bridge_building(owner, "Bunker", Vector3(10, 0, 10), 900)
		var visual := root.get_node("Visual") as Node3D
		t.ok(visual.scene_file_path.ends_with(".glb"), "owner %d: the authored model" % owner)
		t.near(_width(visual), 1.7 * WorldArt.TILE, 0.05, "owner %d: fitted to the default width" % owner)
		t.near(float(root.get_meta("visual_tiles", 0.0)), 1.7, 0.001, "owner %d: meta" % owner)
		t.eq(root.find_children("*", "Label3D", true, false).size(), 0, "owner %d: no banner" % owner)
		var bar := root.get_node("HealthBack") as Node3D
		t.ok(bar.position.y > WorldArt.merged_aabb(visual).end.y * visual.scale.y, "owner %d: health bar above the model" % owner)
		root.free()
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


func test_kestrel_unit_bars_sit_above_the_sprite_card(t) -> void:
	# units are sprite cards now (test_world_sprites.gd has the screen-space checks); the card is UNIT_TILES wide
	var scene := _kestrel_scene()
	for kind in [0, 1, 5]:
		scene._create_unit(1, Vector3(6, 0, 6), kind)
		var unit: Node3D = scene.units.back()
		var visual := unit.get_node("UnitVisual") as Node3D
		t.near(visual.scale.x, float(WorldArt.UNIT_TILES[kind]) * WorldArt.TILE, 0.001, "kind %d width" % kind)
		var top := WorldSprites.body_top_y(visual.get_meta("sprite_texture"), visual.scale.x, visual.position.y)
		var bar := unit.get_node("HealthBack") as Node3D
		t.ok(bar.position.y > top, "kind %d health bar above the painted top" % kind)
	scene.free()


func test_kestrel_badges_and_relay_labels_clear_the_fitted_model(t) -> void:
	# a unit whose sprite failed to load falls back to its fitted model at the model's own width, badge included
	var scene := _kestrel_scene()
	var names := {0: "infantry_v2", 1: "tank_v2", 5: "harvester_v2"}
	for kind in names:
		WorldSprites.unavailable[names[kind]] = true
	for kind in [0, 1, 5]:
		scene._create_unit(0, Vector3(6, 0, 6), kind)
		var unit: Node3D = scene.units.back()
		var visual := unit.get_node("UnitVisual") as Node3D
		t.ok(not visual.has_meta("sprite_kind"), "kind %d: no sprite, the model" % kind)
		t.near(float(unit.get_meta("visual_tiles", 0.0)), float(WorldArt.MODEL_UNIT_TILES[kind]), 0.001, "kind %d: the model's own width" % kind)
		t.near(_width(visual), float(WorldArt.MODEL_UNIT_TILES[kind]) * WorldArt.TILE, 0.05, "kind %d: fitted to it" % kind)
		var badge := unit.get_node_or_null("StrategicBadge") as Node3D
		t.ok(badge != null and badge.position.y > WorldArt.merged_aabb(visual).end.y * visual.scale.y, "kind %d badge above the model" % kind)
	scene._create_unit(1, Vector3(7, 0, 6), 1)
	t.ok((scene.units.back() as Node3D).get_node("UnitVisual").has_meta("sprite_kind"), "the enemy tank keeps its own sprite")
	WorldSprites.unavailable.clear()
	var core: Node3D = scene._create_bridge_building(1, "AntimatterPlant", Vector3(10, 0, 10), 902)
	var model := core.get_node("Visual") as Node3D
	t.ok(scene._label_y(core) > WorldArt.merged_aabb(model).end.y * model.scale.y, "a relay label clears the fitted model")
	scene.free()


func test_kestrel_construction_grows_the_fitted_model(t) -> void:
	var scene := _kestrel_scene()
	var root: Node3D = scene._create_bridge_building(0, "Bunker", Vector3(10, 0, 10), 901)
	var visual := root.get_node("Visual") as Node3D
	t.ok(visual.get_meta("authored_scale").is_equal_approx(visual.scale), "the construction scale is the fitted one")
	scene.free()


func test_kestrel_human_models_take_the_board_palette(t) -> void:
	var scene := _kestrel_scene()
	var root: Node3D = scene._create_bridge_building(0, "Bunker", Vector3(10, 0, 10), 902)
	var colours := {}
	for mi in root.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
			if m:
				colours[m.albedo_color.to_html(false)] = true
	for key in ["concrete", "olive", "gunmetal"]:
		t.ok(colours.has(String(WorldArt.MODEL_PALETTE[key])), "%s from the palette: %s" % [key, colours.keys()])
	for legacy in ["777a70", "59614e", "333c40"]:
		t.ok(not colours.has(legacy), "no legacy colour %s" % legacy)
	scene.free()


func _cards_within(props, at: Vector3, radius: float) -> int:
	var n := 0
	for i in props._card_at.size():
		var p: Vector3 = props._card_at[i]
		if props._card_pinned[i] == 0 and Vector2(p.x, p.z).distance_to(Vector2(at.x, at.z)) < radius:
			n += 1
	return n


func test_kestrel_buildings_clear_by_width_and_take_a_pad(t) -> void:
	var scene := _kestrel_scene()
	var props = scene.world_props
	var radius: float = float(WorldArt.BUILDING_TILES.CommandCenter) * WorldArt.TILE * 0.5
	var at := Vector3.INF
	for i in props._card_at.size():  # build on a real prop card, so the clear has something to clear
		if props._card_pinned[i] == 0 and props._card_at[i] != WorldProps.HIDDEN:
			at = Vector3(props._card_at[i].x, 0.0, props._card_at[i].z)
			break
	t.ok(at != Vector3.INF and _cards_within(props, at, radius) > 0, "a prop card stands inside the CC's radius before the build")
	var free_before: int = props._free_pads.size()
	scene._create_bridge_building(0, "CommandCenter", at, 903)
	t.eq(_cards_within(props, at, radius), 0, "no prop card left under the CC")
	t.eq(props._free_pads.size(), free_before - 1, "one pad slot taken")
	var slot: int = props._decal_base + WorldProps.PAD_SLOTS - free_before
	var tex := WorldSprites.texture_for("CommandCenter", 0)
	var card_w := float(WorldArt.BUILDING_TILES.CommandCenter) * WorldArt.TILE
	var width := WorldSprites.pad_width(tex, card_w)
	var spot := at + WorldSprites.pad_spot(tex, card_w)
	var pad: Transform3D = props.pad_transform(slot)  # CPU mirror: the dummy renderer reads transforms back as identity
	t.near(pad.basis.x.length(), width * 1.15, 0.001, "the pad is as wide as the painted body, plus a soft margin")
	t.near(pad.origin.x, spot.x + 0.08 * width, 0.001, "the pad sits under the painted footprint, nudged toward the sun's shadow (x)")
	t.near(pad.origin.z, spot.z + 0.06 * width, 0.001, "and z")
	props.release_pad(slot)
	t.eq(props._free_pads.size(), free_before, "release gives the slot back")
	t.near(props.pad_transform(slot).basis.x.length(), 0.0, 0.0001, "a released pad is collapsed")
	scene.free()


func test_kestrel_selection_ring_wraps_the_painted_base_like_the_boards(t) -> void:
	# StructureSelected: a 200 px barracks drawn at top 570 takes the ellipse rx 132, ry 46 centred at y 725 (x on the
	# sprite's centre). CoreAssault: each 140 px tank takes rx 58, ry 22 centred 19 px over its contact line (top + 119).
	var scene := _kestrel_scene()
	var ui_stub := GDScript.new()
	ui_stub.source_code = "extends Node\nfunc set_tab(_tab: String) -> void:\n\tpass\n"
	ui_stub.reload()
	scene.ui = Node.new()
	scene.ui.set_script(ui_stub)
	var barracks: Node3D = scene._create_bridge_building(0, "Barracks", scene._hex_world(10, 10), 904)
	scene._create_unit(0, scene._hex_world(14, 12), 1)
	var tank: Node3D = scene.units.back()
	for case in [[barracks, "Visual", 200.0, 725.0 - 570.0, 132.0, 46.0], [tank, "UnitVisual", 140.0, 119.0 - 19.0, 58.0, 22.0]]:
		var node: Node3D = case[0]
		var card := node.get_node(String(case[1])) as Node3D
		var px: float = card.scale.x / float(case[2])  # world units per board pixel
		scene._set_selection([node])
		var ring: MeshInstance3D = scene.selection_ring
		var shape: Dictionary = scene._ring_shape(node)
		var centre: Vector3 = shape.centre
		var label := String(node.name)
		t.near((centre.x - node.position.x) / px, 0.0, 3.0, "%s: centred under the painting (board px)" % label)
		var below_top := WorldSprites.FOOT * float(case[2]) + (centre.z - node.position.z) * WorldArt.PITCH_SIN / px
		t.near(below_top, float(case[3]), 3.0, "%s: centre %.1f board px below the sprite's top" % [label, below_top])
		t.near(float(shape.rx) / px, float(case[4]), 3.0, "%s: rx in board px" % label)
		t.near(float(shape.rz) * WorldArt.PITCH_SIN / px, float(case[5]), 2.0, "%s: ry on screen in board px" % label)
		t.near(centre.y, scene._height_world(centre.x, centre.z), 1e-4, "%s: on the ground" % label)
		t.ok(ring.position.is_equal_approx(centre), "%s: the ring stands on that centre" % label)
		t.ok(ring.scale.is_equal_approx(Vector3.ONE) and is_zero_approx(ring.rotation.y), "%s: an ellipse, never scaled or spun" % label)
		var box := ring.mesh.get_aabb()
		t.near(box.size.x, 2.0 * (float(shape.rx) + scene.RING_LINE), 0.01, "%s: the drawn ellipse is rx wide" % label)
		t.near(box.size.z, 2.0 * (float(shape.rz) + scene.RING_LINE / WorldArt.PITCH_SIN), 0.01, "%s: and rz deep" % label)
		var body := WorldSprites.opaque_bounds(WorldSprites.drawn_texture(card))
		var front := (below_top + float(shape.rz) * WorldArt.PITCH_SIN / px) / float(case[2])
		var over := (ring.material_override as BaseMaterial3D).no_depth_test
		if node == barracks:
			# StructureSelected draws it under the sprites: the back arc hides behind the painting, the front wraps the base
			t.ok(not over, "a building's ellipse is depth tested (under the painting)")
			t.ok(front > body.end.y, "%s: the front arc passes under the painted base (v %.3f > %.3f)" % [label, front, body.end.y])
			t.ok(float(shape.rx) > body.size.x * card.scale.x * 0.5, "%s: and its sides stand out past the painted body" % label)
		else:
			# CoreAssault draws the unit ellipses over the sprites (z-index 1400), round the lower hull
			t.ok(over, "a unit's ellipse draws over its painting")
			t.ok(front < body.end.y and front > WorldSprites.FOOT, "%s: its front arc crosses the painted tracks (v %.3f)" % [label, front])
	# a mirrored unit's ellipse mirrors with its painting; a hovering gunship's stays on the ground
	var before: float = (scene._ring_shape(tank).centre as Vector3).x - tank.position.x
	WorldSprites.face(tank.get_node("UnitVisual"), 1.0)
	t.near((scene._ring_shape(tank).centre as Vector3).x - tank.position.x, -before, 1e-5, "mirrored with the card")
	scene._create_unit(0, scene._hex_world(16, 12), 3)
	var gunship: Node3D = scene.units.back()
	var g: Vector3 = scene._ring_shape(gunship).centre
	t.near(g.y, scene._height_world(g.x, g.z), 1e-4, "a gunship's ellipse is on the ground under it")
	# the CC: the same board shape from its own painted width
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(20, 10), 905)
	scene._set_selection([cc])
	var cc_card := cc.get_node("Visual") as Node3D
	var cc_body := WorldSprites.opaque_bounds(WorldSprites.drawn_texture(cc_card))
	var cc_shape: Dictionary = scene._ring_shape(cc)
	t.near(float(cc_shape.rx), 132.0 / 177.0 * cc_body.size.x * cc_card.scale.x, 0.02, "CC: rx is the board's 132 px for a 177 px painted body, scaled")
	t.ok(scene.selection_ring.position.is_equal_approx(cc_shape.centre), "the ring moved to the CC")
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
	t.ok(scene.hover_tile.visible, "shown on the south-east neighbour: its centre is below the painted base on screen")
	scene._show_hover_at(scene._hex_world(tile.x, tile.y - 1))
	t.ok(not scene.hover_tile.visible, "hidden on the north neighbour: the barracks' painted body covers its centre on screen")
	scene._create_unit(0, east, 1)
	scene.bridge_nodes[906] = scene.units.back()
	scene._show_hover_at(east)
	t.ok(not scene.hover_tile.visible, "hidden under a unit")
	scene.free()


func test_kestrel_hover_outline_stays_off_a_command_center_overhang(t) -> void:
	# the CC sprite stands on its root and rises north on screen: its painted body covers the centres of the hexes north,
	# north-east, north-west and two north of it, not the ones beside or south of its base
	var scene := _kestrel_scene()
	var tile := Vector2i(10, 10)
	var world: Vector3 = scene._hex_world(tile.x, tile.y)
	scene.bridge_nodes[907] = scene._create_bridge_building(0, "CommandCenter", world, 907)
	for n in [Vector2i(10, 9), Vector2i(11, 9), Vector2i(9, 9), Vector2i(10, 8)]:
		scene._show_hover_at(scene._hex_world(n.x, n.y))
		t.ok(not scene.hover_tile.visible, "hidden on %s under the CC's painted body" % n)
		t.eq(scene.hover_cell, n, "the hex is still hovered (the inspector reads it)")
	for n in [Vector2i(11, 10), Vector2i(9, 10), Vector2i(10, 11), Vector2i(12, 10), Vector2i(10, 7)]:
		scene._show_hover_at(scene._hex_world(n.x, n.y))
		t.ok(scene.hover_tile.visible, "shown on %s, clear of the painted body" % n)
	scene.free()


func test_kestrel_shared_sprites_keep_each_kinds_width(t) -> void:
	# Refinery (2.44) and SupplyDepot (2.07) share the refinery sprite, Barracks and VehicleFactory the barracks one; an
	# unknown kind falls back to a fitted model (1.7). Build order must not decide the size.
	for order in [["Refinery", "SupplyDepot"], ["SupplyDepot", "Refinery"], ["VehicleFactory", "Bunker"], ["Bunker", "VehicleFactory"]]:
		var scene := _kestrel_scene()
		for kind in order:
			var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 910)
			var want := float(WorldArt.BUILDING_TILES.get(kind, 1.7)) * WorldArt.TILE
			var visual := root.get_node("Visual") as Node3D
			var got := visual.scale.x if visual.has_meta("sprite_kind") else _width(visual)
			t.near(got, want, 0.05, "%s width after %s" % [kind, order[0]])
		scene.free()


func test_merged_aabb_and_fit_factor_against_a_hand_built_model(t) -> void:
	# root (scaled 3: ignored, the box is in root's own space)
	#   arm: at (1, 0, 0), turned 90 degrees about y, scaled 2
	#     box 1 x 1 x 0.5 at (0, 0.5, 0): scale -> x [-1, 1] y [0, 2] z [-0.5, 0.5]; turn -> x [-0.5, 0.5] z [-1, 1];
	#     move -> x [0.5, 1.5] y [0, 2] z [-1, 1]
	#   cube 0.5 at (-2, 0, 0): x [-2.25, -1.75] y [-0.25, 0.25] z [-0.25, 0.25]
	var root := Node3D.new()
	root.scale = Vector3.ONE * 3.0
	var arm := Node3D.new()
	arm.position = Vector3(1, 0, 0)
	arm.rotation_degrees.y = 90.0
	arm.scale = Vector3.ONE * 2.0
	root.add_child(arm)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 0.5)
	box.mesh = bm
	box.position = Vector3(0, 0.5, 0)
	arm.add_child(box)
	var cube := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3.ONE * 0.5
	cube.mesh = cm
	cube.position = Vector3(-2, 0, 0)
	root.add_child(cube)
	var empty := MeshInstance3D.new()  # a mesh-less instance adds nothing
	empty.position = Vector3(50, 50, 50)
	root.add_child(empty)
	var got := WorldArt.merged_aabb(root)
	t.ok(got.position.is_equal_approx(Vector3(-2.25, -0.25, -1.0)), "aabb position %s" % got.position)
	t.ok(got.size.is_equal_approx(Vector3(3.75, 2.25, 2.0)), "aabb size %s" % got.size)
	t.near(WorldArt.fit_factor(root, 2.0), 2.0 * 0.68 / 3.75, 0.00001, "fit factor = tiles * TILE / widest ground axis")
	var bare := Node3D.new()
	t.near(WorldArt.fit_factor(bare, 2.0), 1.0, 0.0, "no mesh: scale 1")
	bare.free()
	root.free()


func test_kestrel_hover_outline_reads_a_units_painted_body(t) -> void:
	# a capital card is 4 tiles wide: its painted body covers the hex north of it on screen, not the one south of its base
	var scene := _kestrel_scene()
	var tile := Vector2i(12, 10)
	scene._create_unit(0, scene._hex_world(tile.x, tile.y), 4)
	scene.bridge_nodes[909] = scene.units.back()
	scene._show_hover_at(scene._hex_world(tile.x, tile.y - 1))
	t.ok(not scene.hover_tile.visible, "hidden on the north neighbour, under the painted hull")
	scene._show_hover_at(scene._hex_world(tile.x, tile.y + 1))
	t.ok(scene.hover_tile.visible, "shown on the south neighbour, clear of the painting (inside the old 2-tile radius)")
	scene.free()


func test_covers_ground_mirrors_and_lifts_with_the_card(t) -> void:
	# alien_infantry_v1's painted body is 21 px off centre (PIL: x 35 .. 242 of 256)
	var tex := WorldSprites.texture_for("Infantry", 1)
	var w := 2.0
	var differs := 0
	for ix in range(-10, 11):
		for iz in range(-12, 4):
			var off := Vector2(ix * 0.1, iz * 0.1)
			var mirrored := WorldSprites.covers_ground(tex, w, off, 0.0, true)
			t.eq(mirrored, WorldSprites.covers_ground(tex, w, Vector2(-off.x, off.y), 0.0, false), "mirrored at %s" % off)
			if mirrored != WorldSprites.covers_ground(tex, w, off, 0.0, false):
				differs += 1
	t.ok(differs > 0, "and the mirror changes what it covers (%d points)" % differs)
	# a lifted card (a gunship) shows its painting higher: a ground point just south of the painted base is clear of it
	var heli := WorldSprites.texture_for("Helicopter", 0)
	var bottom := WorldSprites.opaque_bounds(heli).end.y
	var just_in := Vector2(0.0, (bottom - WorldSprites.FOOT - 0.02) * w / WorldArt.PITCH_SIN)
	t.ok(WorldSprites.covers_ground(heli, w, just_in, 0.0), "on the ground: covered")
	t.ok(not WorldSprites.covers_ground(heli, w, just_in, 0.3), "lifted 0.3: clear")


func test_kestrel_hover_outline_follows_a_unit_leaving_the_hex(t) -> void:
	# _update_hover_tile runs every frame (_process), so the occupied state is re-read without any mouse motion
	var scene := _kestrel_scene()
	var tile := Vector2i(12, 10)
	var world: Vector3 = scene._hex_world(tile.x, tile.y)
	scene._create_unit(0, world, 1)
	var unit: Node3D = scene.units.back()
	scene.bridge_nodes[907] = unit
	scene._show_hover_at(world)
	t.ok(not scene.hover_tile.visible, "hidden while the unit stands there")
	unit.position = scene._hex_world(tile.x + 3, tile.y)
	scene._show_hover_at(world)
	t.ok(scene.hover_tile.visible, "back as soon as the unit has left, same pointer")
	scene.free()


func test_kestrel_pads_run_out_quietly(t) -> void:
	var scene := _kestrel_scene()
	var props = scene.world_props
	var roots: Array = []
	for i in WorldProps.PAD_SLOTS + 1:
		roots.append(scene._create_bridge_building(0, "Wall", scene._hex_world(4 + i % 30, 3 + i / 30), 1000 + i))
	t.eq(props._free_pads.size(), 0, "every pad slot in use")
	t.eq((roots.back() as Node3D).tree_exiting.get_connections().size(), 0, "the building past the last slot has no pad to release")
	t.eq((roots.front() as Node3D).tree_exiting.get_connections().size(), 1, "the first one releases its pad on exit")
	scene.free()


func test_kestrel_destroyed_building_gives_its_pad_back(t) -> void:
	# The runner calls tests from SceneTree._initialize, before its root is inside the tree, so no node here can really
	# leave the tree; the building's own tree_exiting signal is emitted by hand, as a destroy (queue_free) would.
	var scene := _kestrel_scene()
	var props = scene.world_props
	var free_before: int = props._free_pads.size()
	var root: Node3D = scene._create_bridge_building(0, "Barracks", Vector3(12, 0, 9), 920)
	var slot: int = props._decal_base + WorldProps.PAD_SLOTS - free_before
	t.eq(props._free_pads.size(), free_before - 1, "built: one slot taken")
	root.tree_exiting.emit()
	scene.remove_child(root)
	root.free()
	t.eq(props._free_pads.size(), free_before, "destroyed: the slot is free again")
	t.near(props.pad_transform(slot).basis.x.length(), 0.0, 0.0001, "and its pad collapsed")
	scene._create_bridge_building(0, "Barracks", Vector3(12, 0, 9), 921)
	t.eq(props._free_pads.size(), free_before - 1, "rebuilt: a slot is taken again")
	var card_w := float(WorldArt.BUILDING_TILES.Barracks) * WorldArt.TILE
	var pad_w := WorldSprites.pad_width(WorldSprites.texture_for("Barracks", 0), card_w)
	t.near(props.pad_transform(slot).basis.x.length(), pad_w * 1.15, 0.001, "the same slot, placed for the new building")
	scene.free()


func test_kestrel_missing_deposit_list_marks_nothing_spent(t) -> void:
	var scene := _kestrel_scene()
	var before: PackedColorArray = scene.world_props._card_color.duplicate()
	scene._sync_spent_deposits({"tick": 5})
	var changed := 0
	for i in before.size():
		if scene.world_props._card_color[i] != before[i]:
			changed += 1
	t.eq(changed, 0, "a snapshot without a deposits key changes no crystal")
	scene.free()


## A stand-in for the Kestrel orthographic camera (north up, pitched): x across, z and height share the screen y axis.
## The camera cannot unproject while the test scene sits outside the tree.
func _ortho(ppu: float) -> Callable:
	var cos_pitch := sqrt(1.0 - WorldArt.PITCH_SIN * WorldArt.PITCH_SIN)
	return func(node: Node3D, offset: Vector3) -> Vector2:
		var p := node.position + offset
		return Vector2(p.x, p.z * WorldArt.PITCH_SIN - p.y * cos_pitch) * ppu


func test_kestrel_click_clear_of_the_painted_body_selects_nothing(t) -> void:
	# the roof, body and transparent-corner clicks are in test_world_sprites.gd; here, hexes clear of the CC sprite
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)  # the Home view: the 3.05-tile CC card is about 224 px wide
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 910)
	scene.bridge_nodes[910] = cc
	t.eq((cc.get_meta("pick_parts", []) as Array).size(), 1, "the CC picks by its painted body's box")
	for n in [Vector2i(12, 10), Vector2i(8, 10), Vector2i(10, 7), Vector2i(10, 12)]:
		var away := Node3D.new()
		away.position = scene._hex_world(n.x, n.y)
		t.eq(scene._pick_entity(to_screen.call(away, Vector3.ZERO), to_screen), null, "hex %s, clear of the model: nothing" % n)
		away.free()
	scene.free()


func test_kestrel_unit_beside_a_building_still_wins_its_own_click(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 911)
	scene.bridge_nodes[911] = cc
	scene._create_unit(0, scene._hex_world(11, 9), 0)  # north-east: under the CC sprite's painted body on screen
	var squad: Node3D = scene.units.back()
	scene.bridge_nodes[912] = squad
	t.ok(not (squad.get_meta("pick_parts", []) as Array).is_empty(), "a fitted unit records its parts too")
	var click: Vector2 = to_screen.call(squad, Vector3.UP * 0.15)
	t.ok(scene._parts_hold(cc, click, to_screen), "the CC's hull covers the squad's root on screen")
	t.eq(scene._pick_entity(click, to_screen), squad, "the squad on the neighbour hex, not the CC over it")
	scene._create_unit(1, scene._hex_world(13, 10), 1)
	scene.bridge_nodes[913] = scene.units.back()
	var enemy_click: Vector2 = to_screen.call(scene.units.back(), Vector3.UP * 0.15)
	t.eq(scene._pick_entity(enemy_click, to_screen), null, "an enemy is never picked, and the CC does not reach three hexes")
	scene.free()


func test_kestrel_era_crown_sits_above_the_fitted_model(t) -> void:
	var scene := _kestrel_scene()
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 914)
	scene.bridge_nodes[914] = cc
	scene.bridge_era = 1
	scene._apply_era_visuals()
	var crown := cc.get_node_or_null("EraCrown") as Node3D
	t.ok(crown != null and crown.visible, "the era crown shows")
	var model := cc.get_node("Visual") as Node3D
	if crown != null:
		t.ok(crown.position.y > WorldArt.merged_aabb(model).end.y * model.scale.y, "the crown clears the fitted roof")
	scene.free()
