extends RefCounted
## Kestrel sprite buildings (plan 2026-10-05-kestrel-sprite-entities, Task 1): every building is the boards' own painted
## sprite on a camera-facing card, sized by the boards' pixel widths. Survival keeps its models (test_world_art_survival).
const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")
const WorldProps := preload("res://scripts/world/world_props.gd")
const MainScene = preload("res://main.tscn")

const PROFILE_KINDS := ["CommandCenter", "PowerPlant", "Refinery", "Barracks", "VehicleFactory", "Airfield", "SupplyDepot",
	"Battery", "GunTurret", "AaTurret", "Wall", "ResearchLab", "AntimatterPlant"]


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	scene._sync_ground(JSON.parse_string(f.get_as_text()))
	return scene


func _cos_pitch() -> float:
	return sqrt(1.0 - WorldArt.PITCH_SIN * WorldArt.PITCH_SIN)


## The Kestrel orthographic camera as a function (north up, pitched): x across, z and height share the screen y axis.
func _ortho(ppu: float) -> Callable:
	var cos_pitch := _cos_pitch()
	return func(node: Node3D, offset: Vector3) -> Vector2:
		var p := node.position + offset
		return Vector2(p.x, p.z * WorldArt.PITCH_SIN - p.y * cos_pitch) * ppu


## The root-space offset whose screen point is the card pixel (u, v) (0..1, v down from the card's top).
func _card_point(card: Node3D, u: float, v: float) -> Vector3:
	var w: float = card.scale.x
	var h: float = w * WorldSprites.ASPECT
	return Vector3((u - 0.5) * w, card.position.y + (WorldSprites.FOOT - v) * h / _cos_pitch(), 0.0)


func _card_texture(card: Node3D) -> Texture2D:
	return ((card as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture


func test_every_profile_building_has_a_sprite_or_is_listed(t) -> void:
	for kind in PROFILE_KINDS:
		var listed := WorldSprites.NO_SPRITE.has(kind)
		t.ok(WorldSprites.SPRITES.has(kind) != listed, "%s: a sprite or NO_SPRITE, never both or neither" % kind)
		if not listed:
			t.ok(WorldSprites.texture_for(kind, 0) != null, "%s human texture loads" % kind)
			t.ok(WorldSprites.texture_for(kind, 1) != null, "%s enemy texture loads" % kind)
	t.eq(WorldSprites.texture_for("Bunker", 0), null, "an unknown kind has no sprite (the caller keeps the model)")


func test_enemy_owner_takes_the_alien_sprite(t) -> void:
	t.ok(WorldSprites.texture_for("CommandCenter", 0).resource_path.ends_with("/command_center_v2.png"), "human CC")
	t.ok(WorldSprites.texture_for("CommandCenter", 1).resource_path.ends_with("/alien_command_center_v1.png"), "alien CC")
	t.ok(WorldSprites.texture_for("GunTurret", 1).resource_path.ends_with("/alien_gun_turret_v1.png"), "alien turret")
	t.ok(WorldSprites.texture_for("ResearchLab", 0).resource_path.ends_with("/capital_v1.png"), "the boards' lab sprite")


func test_building_widths_follow_the_boards(t) -> void:
	# Main.dc.html draws land.jpg 1:1 (3600 x 2400 px), and land.jpg maps one hex column (TILE) to 82 px
	t.near(WorldSprites.PX_PER_TILE, 82.0, 0.0, "board pixels per tile")
	for kind in PROFILE_KINDS:
		t.ok(WorldSprites.MOCK_PX.has(kind), "%s has a board size" % kind)
		t.near(float(WorldArt.BUILDING_TILES[kind]), float(WorldSprites.MOCK_PX[kind]) / 82.0, 0.006, "%s width in tiles" % kind)
	t.near(float(WorldSprites.MOCK_PX.CommandCenter), 250.0, 0.0, "CC 250 px on the boards")
	t.ok(float(WorldArt.BUILDING_TILES.CommandCenter) > float(WorldArt.BUILDING_TILES.Barracks), "CC reads bigger than barracks")
	t.ok(float(WorldArt.BUILDING_TILES.Barracks) > float(WorldArt.BUILDING_TILES.GunTurret), "barracks bigger than a turret")


func test_one_material_per_texture(t) -> void:
	var cc := WorldSprites.texture_for("CommandCenter", 0)
	var m := WorldSprites.material_for(cc)
	t.ok(m == WorldSprites.material_for(cc), "the same texture gives the same material instance")
	t.ok(m != WorldSprites.material_for(WorldSprites.texture_for("Barracks", 0)), "another texture, another material")
	var sm := m as StandardMaterial3D
	t.ok(sm != null and sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "unshaded: the painted light is kept")
	t.ok(sm != null and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "transparent corners")
	var a := WorldSprites.make_card("CommandCenter", 0, 3.0)
	var b := WorldSprites.make_card("CommandCenter", 0, 2.0)
	t.ok((a as MeshInstance3D).material_override == (b as MeshInstance3D).material_override, "two cards share the material")
	t.ok((a as MeshInstance3D).mesh == (b as MeshInstance3D).mesh, "and the card mesh")
	t.eq((a as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a card casts no shadow")
	a.free()
	b.free()


func test_card_is_tiles_wide_and_stands_on_its_root(t) -> void:
	var card := WorldSprites.make_card("Barracks", 0, 2.44)
	var w := 2.44 * WorldArt.TILE
	var box := (card as MeshInstance3D).get_aabb()
	t.near(box.size.x * card.scale.x, w, 0.001, "width = tiles * TILE")
	t.near(box.position.y, 0.0, 1e-5, "the mesh's bottom edge is at the root (y = 0)")
	t.ok(card.position.y >= 0.0 and card.position.y < 0.05, "lifted only a hair off the ground (%s)" % card.position.y)
	# every vertex projected with the Kestrel camera: the card is w wide and w * aspect tall on screen, the contact line
	# (v = FOOT) sits on the root, and it faces the camera (every vertex at the depth of the root or on the ground before it)
	var arrays := ((card as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var cos_pitch := _cos_pitch()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in verts.size():
		var p := verts[i] * card.scale.x
		var s := Vector2(p.x, p.z * WorldArt.PITCH_SIN - p.y * cos_pitch)
		lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
		hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
		if is_equal_approx(uvs[i].y, WorldSprites.FOOT):
			t.near(s.y, 0.0, 1e-4, "the contact line projects onto the root")
		if p.y > 1e-5:
			var depth := p.y * WorldArt.PITCH_SIN + p.z * cos_pitch  # along the view direction, toward the camera
			t.near(depth, 0.0, 1e-4, "a standing vertex is at the root's depth (camera-facing)")
		else:
			t.ok(p.z >= -1e-5, "a ground vertex lies on or before the root")
	t.near(hi.x - lo.x, w, 1e-4, "screen width")
	t.near(hi.y - lo.y, w * WorldSprites.ASPECT, 1e-4, "screen height")
	t.near(-lo.y, w * WorldSprites.FOOT * WorldSprites.ASPECT, 1e-4, "FOOT of the card above the root on screen")
	card.free()


func test_opaque_bounds_are_a_proper_sub_rect(t) -> void:
	var tex := WorldSprites.texture_for("CommandCenter", 0)
	var r := WorldSprites.opaque_bounds(tex)
	t.ok(r.position.x > 0.0 and r.position.y > 0.0 and r.end.x < 1.0 and r.end.y < 1.0, "inside the card: %s" % r)
	t.ok(r.size.x > 0.5 and r.size.y > 0.5, "and most of it: %s" % r)
	# alpha > 128 box of command_center_v2.png measured with PIL: (16, 26) to (243, 238), end exclusive
	t.near(r.position.x, 16.0 / 256.0, 0.5 / 256.0, "left")
	t.near(r.position.y, 26.0 / 256.0, 0.5 / 256.0, "top")
	t.near(r.end.x, 243.0 / 256.0, 0.5 / 256.0, "right")
	t.near(r.end.y, 238.0 / 256.0, 0.5 / 256.0, "bottom")
	t.eq(WorldSprites.opaque_bounds(tex), r, "cached")


func test_kestrel_building_is_a_sprite_card(t) -> void:
	var scene := _kestrel_scene()
	for kind in ["CommandCenter", "Barracks", "GunTurret", "Wall", "ResearchLab"]:
		var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 930)
		var visual := root.get_node("Visual") as Node3D
		t.ok(visual is MeshInstance3D and visual.has_meta("sprite_kind"), "%s draws a sprite card" % kind)
		t.eq(visual.scene_file_path, "", "%s: no .glb" % kind)
		for n in root.find_children("*", "Node3D", true, false):
			t.ok(not String(n.scene_file_path).ends_with(".glb"), "%s: no authored model under the root" % kind)
		t.ok(_card_texture(visual) == WorldSprites.texture_for(kind, 0), "%s: its own sprite" % kind)
		t.near(visual.scale.x, float(WorldArt.BUILDING_TILES[kind]) * WorldArt.TILE, 0.001, "%s card width" % kind)
		t.near(float(root.get_meta("visual_tiles", 0.0)), float(WorldArt.BUILDING_TILES[kind]), 0.001, "%s visual_tiles" % kind)
		var parts: Array = root.get_meta("pick_parts", [])
		t.eq(parts.size(), 1, "%s picks by one box, its opaque rect" % kind)
		if parts.size() == 1:
			var want := WorldSprites.pick_box(WorldSprites.texture_for(kind, 0), visual.scale.x, visual.position.y)
			t.ok((parts[0] as AABB).is_equal_approx(want), "%s pick box from the opaque bounds" % kind)
		t.eq(root.find_children("*", "Label3D", true, false).size(), 0, "%s has no banner" % kind)
		root.free()
	var alien: Node3D = scene._create_bridge_building(1, "CommandCenter", Vector3(12, 0, 10), 931)
	t.ok(_card_texture(alien.get_node("Visual")).resource_path.ends_with("/alien_command_center_v1.png"), "enemy CC sprite")
	alien.free()
	var bunker: Node3D = scene._create_bridge_building(0, "Bunker", Vector3(14, 0, 10), 932)
	t.ok(String((bunker.get_node("Visual") as Node3D).scene_file_path).ends_with(".glb"), "no sprite: the model stays")
	bunker.free()
	scene.free()


func test_bars_crown_and_label_sit_over_the_painted_top(t) -> void:
	var scene := _kestrel_scene()
	var cos_pitch := _cos_pitch()
	for kind in ["CommandCenter", "GunTurret", "Wall"]:
		var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 933)
		var visual := root.get_node("Visual") as Node3D
		var top := _card_point(visual, 0.5, WorldSprites.opaque_bounds(_card_texture(visual)).position.y).y * cos_pitch
		var card_top := _card_point(visual, 0.5, 0.0).y * cos_pitch
		var bar := (root.get_node("HealthBack") as Node3D).position.y * cos_pitch
		t.ok(bar > top, "%s health bar over the painted top (%.3f > %.3f)" % [kind, bar, top])
		t.ok(bar < card_top + 0.35, "%s and not floating far above the card (%.3f)" % [kind, bar])
		t.ok(float(root.get_meta("crown_y")) * cos_pitch > top, "%s crown over the painted top" % kind)
		t.ok(scene._label_y(root) * cos_pitch > bar, "%s relay label over the bars" % kind)
		root.free()
	scene.free()


func test_construction_shows_the_foundation_then_the_building(t) -> void:
	var scene := _kestrel_scene()
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(10, 10))
	var entity := {"id": 940, "category": "building", "kind": "Barracks", "owner": 0, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100, "construction": 60, "construction_total": 100}
	scene._sync_bridge_entities([entity])
	var root: Node3D = scene.bridge_nodes[940]
	var visual := root.get_node("Visual") as Node3D
	var built_scale := visual.scale
	t.ok(_card_texture(visual).resource_path.ends_with("/foundation_v1.png"), "under construction: the foundation sprite")
	t.ok(visual.scale.is_equal_approx(built_scale) and visual.scale.y > 0.5, "the card is never squashed by the growth")
	entity.construction = 0
	scene._sync_bridge_entities([entity])
	t.ok(_card_texture(visual) == WorldSprites.texture_for("Barracks", 0), "complete: the finished sprite")
	t.ok(visual.scale.is_equal_approx(built_scale), "same card size")
	scene.free()


func test_kestrel_card_casts_no_shadow_and_takes_a_contact_pad(t) -> void:
	var scene := _kestrel_scene()
	var props = scene.world_props
	var free_before: int = props._free_pads.size()
	var at: Vector3 = scene._hex_world(12, 9)
	var root: Node3D = scene._create_bridge_building(0, "CommandCenter", at, 941)
	var visual := root.get_node("Visual") as GeometryInstance3D
	t.eq(visual.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no cast shadow")
	t.eq(props._free_pads.size(), free_before - 1, "one contact pad")
	var slot: int = props._decal_base + WorldProps.PAD_SLOTS - free_before
	var pad: Transform3D = props.pad_transform(slot)
	var body := WorldSprites.opaque_bounds(_card_texture(visual))
	var w: float = visual.scale.x
	t.near(pad.basis.x.length(), body.size.x * w * 1.15, 0.001, "the pad is the painted body's width plus a margin")
	t.ok(pad.origin.z < at.z, "the pad sits north of the root, under the painted footprint")
	root.free()
	scene.free()


func test_click_on_a_transparent_corner_misses_and_the_body_hits(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 950)
	scene.bridge_nodes[950] = cc
	var card := cc.get_node("Visual") as Node3D
	var body: Vector2 = to_screen.call(cc, _card_point(card, 0.5, 0.55))
	t.eq(scene._pick_entity(body, to_screen), cc, "a click on the painted body selects the CC")
	var roof: Vector2 = to_screen.call(cc, _card_point(card, 0.5, 0.16))
	t.eq(scene._pick_entity(roof, to_screen), cc, "a click on the painted roof selects it too")
	t.ok(to_screen.call(cc, Vector3.UP * 0.15).distance_to(roof) > 32.0, "and that click is past the legacy 32 px reach")
	for corner in [Vector2(0.03, 0.03), Vector2(0.97, 0.04), Vector2(0.03, 0.97), Vector2(0.97, 0.97)]:
		var at: Vector2 = to_screen.call(cc, _card_point(card, corner.x, corner.y))
		t.eq(scene._pick_entity(at, to_screen), null, "the transparent corner %s selects nothing" % corner)
	scene.free()


func test_a_transparent_corner_does_not_steal_a_neighbours_click(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 951)
	scene.bridge_nodes[951] = cc
	# a turret on the north-east neighbour: the narrower card wins any click both hold, so only its opaque rect may count
	var turret: Node3D = scene._create_bridge_building(0, "GunTurret", scene._hex_world(11, 9), 952)
	scene.bridge_nodes[952] = turret
	var card := turret.get_node("Visual") as Node3D
	var corner: Vector2 = to_screen.call(turret, _card_point(card, 0.03, 0.97))
	t.ok(scene._parts_hold(cc, corner, to_screen), "the turret card's bottom-left corner lies on the CC's painted body")
	t.eq(scene._pick_entity(corner, to_screen), cc, "the turret's transparent corner leaves the click to the CC")
	var body: Vector2 = to_screen.call(turret, _card_point(card, 0.5, 0.6))
	t.eq(scene._pick_entity(body, to_screen), turret, "the turret's own body still takes its click")
	scene.free()


func test_survival_buildings_keep_the_legacy_model(t) -> void:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var root: Node3D = scene._create_bridge_building(1, "CommandCenter", Vector3(10, 0, 10), 960)
	var visual := root.get_node("Visual") as Node3D
	t.ok(String(visual.scene_file_path).ends_with(".glb"), "Survival keeps the authored model")
	t.ok(not visual.has_meta("sprite_kind"), "no sprite card")
	t.ok(not root.has_meta("pick_parts") and not root.has_meta("visual_tiles"), "no profile metas")
	scene.free()
