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


## The sprite a card draws (its material samples a pre-graded copy and names the source).
func _card_texture(card: Node3D) -> Texture2D:
	var m := (card as MeshInstance3D).material_override as StandardMaterial3D
	return m.get_meta("source_texture", m.albedo_texture)


## Mean luma and mean chroma (max - min channel) of the painted body (alpha > 250) of an RGBA8 image.
func _body_tone(img: Image) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.98:
				sum += Vector2(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b, maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)))
				n += 1
	return sum / maxf(1.0, float(n))


func _rgba8(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


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


func test_card_material_pre_grades_the_painting(t) -> void:
	# The Kestrel post chain (filmic, saturation 0.5, the gSun overlay) lifts and greys what it draws; the cards (only
	# them) sample a copy of the sprite pre-graded by WorldSprites.GRADE so the painting reads on screen as on the boards.
	var tex := WorldSprites.texture_for("CommandCenter", 0)
	var m := WorldSprites.material_for(tex) as StandardMaterial3D
	t.ok(m.get_meta("source_texture", null) == tex, "the material names its source sprite")
	t.ok(m.albedo_texture != tex, "and draws a graded copy, not the sprite itself")
	var src := _rgba8(tex.get_image().duplicate() as Image)
	var graded_tex := m.albedo_texture
	var img := _rgba8(graded_tex.get_image().duplicate() as Image) if graded_tex != null and graded_tex.get_image() != null else null
	t.ok(img != null and img.get_size() == src.get_size(), "same size as the sprite")
	if img == null or img.get_size() != src.get_size():
		return
	var want := src.duplicate() as Image
	want.adjust_bcs(float(WorldSprites.GRADE.brightness), float(WorldSprites.GRADE.contrast), float(WorldSprites.GRADE.saturation))
	for p in [Vector2i(128, 128), Vector2i(60, 150), Vector2i(200, 90), Vector2i(3, 3)]:
		t.ok(img.get_pixelv(p).is_equal_approx(want.get_pixelv(p)), "pixel %s graded by GRADE" % p)
		t.near(img.get_pixelv(p).a, src.get_pixelv(p).a, 0.002, "alpha %s untouched (picking, shadows)" % p)
	var a := _body_tone(src)
	var b := _body_tone(img)
	t.ok(b.x < a.x * 0.95, "darker body (luma %.3f < %.3f)" % [b.x, a.x])
	t.ok(b.y > a.y * 1.05, "more colourful body (chroma %.3f > %.3f)" % [b.y, a.y])
	var shadow := WorldSprites.shadow_material_for(tex) as ShaderMaterial
	t.ok(shadow.get_shader_parameter("sprite") == tex, "the shadows read the ungraded alpha")


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
			t.ok((parts[0] as AABB).is_equal_approx(_expected_pick_box(visual)), "%s pick box from the opaque bounds" % kind)
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


## alpha > 128 boxes measured with PIL (pixels, end exclusive)
const CC_BODY_PX := Rect2(16, 26, 227, 212)  # command_center_v2.png
const TANK_BODY_PX := Rect2(13, 35, 227, 193)  # tank_v2.png
const TURRET_BODY_PX := Rect2(13, 37, 229, 193)  # gun_turret_v2.png


func _in_body_box(px: Rect2, uv: Vector2) -> bool:
	return Rect2(px.position / 256.0, px.size / 256.0).has_point(uv)


## Whether `point` falls in the screen rectangle of `node`'s pick box (its eight corners projected), alpha ignored.
func _box_holds(node: Node3D, point: Vector2, to_screen: Callable) -> bool:
	for box in node.get_meta("pick_parts", []):
		var rect := Rect2()
		for corner in 8:
			var at: Vector2 = to_screen.call(node, (box as AABB).get_endpoint(corner))
			rect = Rect2(at, Vector2.ZERO) if corner == 0 else rect.expand(at)
		if rect.has_point(point):
			return true
	return false


## Moves `node` (keeping its height) so its root-space offset `own` lands on screen where `anchor`'s offset `at` does.
func _overlay(anchor: Node3D, at: Vector3, node: Node3D, own: Vector3) -> void:
	node.position.x = anchor.position.x + at.x - own.x
	node.position.z = anchor.position.z + at.z - own.z + ((node.position.y + own.y) - (anchor.position.y + at.y)) * _cos_pitch() / WorldArt.PITCH_SIN


## The pick box a card must have, from its opaque rect through this file's own projection (_card_point): its corners land
## on the rect's corners on screen (mirrored: the rect read right to left).
func _expected_pick_box(card: Node3D, mirrored := false) -> AABB:
	var r := WorldSprites.opaque_bounds(_card_texture(card))
	var u0 := 1.0 - r.end.x if mirrored else r.position.x
	var lo := _card_point(card, u0, r.end.y)
	var hi := _card_point(card, u0 + r.size.x, r.position.y)
	return AABB(lo, hi - lo)


func test_click_on_a_see_through_pixel_inside_the_box_misses_and_the_body_hits(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 950)
	scene.bridge_nodes[950] = cc
	var card := cc.get_node("Visual") as Node3D
	var body: Vector2 = to_screen.call(cc, _card_point(card, 0.5, 0.55))
	t.eq(scene._pick_entity(body, to_screen), cc, "a click on the painted body selects the CC")
	var roof: Vector2 = to_screen.call(cc, _card_point(card, 0.566, 0.2))  # solid paint 4 px around (PIL)
	t.eq(scene._pick_entity(roof, to_screen), cc, "a click on the painted roof selects it too")
	t.ok(to_screen.call(cc, Vector3.UP * 0.15).distance_to(roof) > 32.0, "and that click is past the legacy 32 px reach")
	for corner in [Vector2(0.03, 0.03), Vector2(0.97, 0.04), Vector2(0.03, 0.97), Vector2(0.97, 0.97)]:
		var at: Vector2 = to_screen.call(cc, _card_point(card, corner.x, corner.y))
		t.eq(scene._pick_entity(at, to_screen), null, "the transparent corner %s selects nothing" % corner)
	# inside the painted body's box, between the roof towers: alpha <= 128 over a 4 px cell and all its neighbours (PIL)
	for uv in [Vector2(0.305, 0.164), Vector2(0.273, 0.242), Vector2(0.227, 0.352)]:
		var at: Vector2 = to_screen.call(cc, _card_point(card, uv.x, uv.y))
		t.ok(_in_body_box(CC_BODY_PX, uv) and _box_holds(cc, at, to_screen), "%s lies inside the CC's opaque box" % uv)
		t.eq(scene._pick_entity(at, to_screen), null, "the see-through pixel %s inside the box selects nothing" % uv)
	scene.free()


func test_a_see_through_pixel_does_not_steal_a_neighbours_click(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 951)
	scene.bridge_nodes[951] = cc
	# a turret north-east of it, placed so a gap in its painting (inside its opaque box) shows the CC's painted body:
	# the narrower card wins any click both hold, so only its painted pixels may count
	var turret: Node3D = scene._create_bridge_building(0, "GunTurret", scene._hex_world(11, 9), 952)
	scene.bridge_nodes[952] = turret
	var card := turret.get_node("Visual") as Node3D
	var gap := Vector2(0.352, 0.43)
	_overlay(cc, _card_point(cc.get_node("Visual"), 0.5, 0.55), turret, _card_point(card, gap.x, gap.y))
	var click: Vector2 = to_screen.call(turret, _card_point(card, gap.x, gap.y))
	t.ok(click.distance_to(to_screen.call(cc, _card_point(cc.get_node("Visual"), 0.5, 0.55))) < 0.01, "the gap lies on the CC's body")
	t.ok(_in_body_box(TURRET_BODY_PX, gap) and _box_holds(turret, click, to_screen), "inside the turret's opaque box")
	t.eq(scene._pick_entity(click, to_screen), cc, "the turret's see-through gap leaves the click to the CC")
	var body: Vector2 = to_screen.call(turret, _card_point(card, 0.5, 0.6))
	t.eq(scene._pick_entity(body, to_screen), turret, "the turret's own body still takes its click")
	scene.free()


func test_a_building_seen_through_a_units_gap_takes_the_click(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var cc: Node3D = scene._create_bridge_building(0, "CommandCenter", scene._hex_world(10, 10), 953)
	scene.bridge_nodes[953] = cc
	scene._create_unit(0, scene._hex_world(10, 12), 1)
	var tank: Node3D = scene.units.back()
	scene.bridge_nodes[954] = tank
	var card := tank.get_node("UnitVisual") as Node3D
	var gap := Vector2(0.414, 0.195)  # over the tank's hull, under its barrel: no paint (PIL)
	var cc_body := _card_point(cc.get_node("Visual"), 0.5, 0.55)
	_overlay(cc, cc_body, tank, _card_point(card, gap.x, gap.y))
	t.ok(tank.position.z > cc.position.z, "the tank stands in front of (south of) the CC")
	var click: Vector2 = to_screen.call(tank, _card_point(card, gap.x, gap.y))
	t.ok(click.distance_to(to_screen.call(cc, cc_body)) < 0.01, "the gap shows the CC's painted body")
	t.ok(_in_body_box(TANK_BODY_PX, gap) and _box_holds(tank, click, to_screen), "inside the tank's opaque box")
	t.eq(scene._pick_entity(click, to_screen), cc, "a unit ranks first, but its see-through gap leaves the click to the CC")
	t.eq(scene._pick_entity(to_screen.call(tank, _card_point(card, 0.5, 0.45)), to_screen), tank, "the tank's painted hull is still the tank")
	scene.free()


func test_a_mirrored_unit_is_picked_by_its_mirrored_painting(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	scene._create_unit(0, scene._hex_world(14, 12), 1)
	var tank: Node3D = scene.units.back()
	scene.bridge_nodes[955] = tank
	var card := tank.get_node("UnitVisual") as MeshInstance3D
	var clear := Vector2(0.2422, 0.3828)  # tank_v2.png: no paint here, solid paint at its mirror (0.7578) (PIL)
	var solid := Vector2(1.0 - clear.x, clear.y)
	var pick := func(uv: Vector2) -> Node3D: return scene._pick_entity(to_screen.call(tank, _card_point(card, uv.x, uv.y)), to_screen)
	t.eq(pick.call(clear), null, "as painted: the gap selects nothing")
	t.eq(pick.call(solid), tank, "as painted: the paint selects the tank")
	t.ok(WorldSprites.face(card, 1.0), "moving toward +x mirrors the left-facing tank")
	scene._refresh_unit_pick(tank, card)
	t.eq(pick.call(solid), null, "mirrored: that screen pixel now shows the painting's gap")
	t.eq(pick.call(clear), tank, "mirrored: and the mirrored paint takes the click")
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


func test_card_casts_the_boards_silhouette_shadow(t) -> void:
	# hud.css .shd: the silhouette, black, flipped below the contact line, squashed to 0.34 and sheared right by
	# skewX(60deg), at opacity .40 * .52; one shared shadow material per texture, on the ground before the root
	var card := WorldSprites.make_card("CommandCenter", 0, 3.05)
	var shadow := card.get_node_or_null("SpriteShadow") as MeshInstance3D
	t.ok(shadow != null, "the card carries its cast shadow")
	if shadow == null:
		card.free()
		return
	var other := WorldSprites.make_card("CommandCenter", 0, 2.0)
	t.ok(shadow.material_override == (other.get_node("SpriteShadow") as MeshInstance3D).material_override, "shared per texture")
	t.eq(shadow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts no real shadow either")
	var box := shadow.mesh.get_aabb()
	t.near(box.size.y, 0.0, 1e-5, "flat on the ground")
	t.ok(box.position.z >= -1e-5, "before the root (south)")
	var d := WorldSprites.FOOT * WorldSprites.ASPECT
	t.near(box.end.z * WorldArt.PITCH_SIN, 0.34 * d, 1e-4, "0.34 of the height above the line, on screen")
	t.near(box.end.x - 0.5, tan(deg_to_rad(60.0)) * 0.34 * d, 1e-3, "sheared toward the lower right")
	var m := shadow.material_override as ShaderMaterial
	t.ok(WorldSprites.SHADOW_GAIN > 1.0, "the post chain lifts dark ground: the live shadows are drawn stronger")
	t.near(float(m.get_shader_parameter("strength")), 0.40 * 0.52 * WorldSprites.SHADOW_GAIN, 0.001, "the boards' opacity, compensated")
	t.ok(m.get_shader_parameter("sprite") == WorldSprites.texture_for("CommandCenter", 0), "the sprite's own silhouette")
	WorldSprites.show_built(card, false)
	t.ok((shadow.material_override as ShaderMaterial).get_shader_parameter("sprite") == WorldSprites.foundation(), "a site's shadow is the foundation's")
	card.free()
	other.free()


func test_props_clear_under_the_painted_footprint(t) -> void:
	var scene := _kestrel_scene()
	var props = scene.world_props
	var tex := WorldSprites.texture_for("CommandCenter", 0)
	var w := float(WorldArt.BUILDING_TILES.CommandCenter) * WorldArt.TILE
	var at := Vector3.INF
	var prop := Vector3.INF
	for i in props._card_at.size():  # a real prop card 0.8 north of the footprint centre: under the painted body, outside the root's radius
		if props._card_pinned[i] == 0 and props._card_at[i] != WorldProps.HIDDEN:
			prop = Vector3(props._card_at[i].x, 0.0, props._card_at[i].z)
			at = prop - WorldSprites.pad_spot(tex, w) + Vector3(0, 0, 0.8)
			break
	var spot := at + WorldSprites.pad_spot(tex, w)
	t.ok(spot.z < at.z, "the footprint centre is north of the root")
	t.ok(Vector2(prop.x, prop.z).distance_to(Vector2(at.x, at.z)) > w * 0.5, "the prop is outside the root's own radius")
	scene._create_bridge_building(0, "CommandCenter", at, 970)
	var left := 0
	for i in props._card_at.size():
		var p: Vector3 = props._card_at[i]
		if props._card_pinned[i] == 0 and Vector2(p.x, p.z).distance_to(Vector2(spot.x, spot.z)) < w * 0.5:
			left += 1
	t.eq(left, 0, "no prop card left under the painted footprint")
	scene.free()


# --- Task 2: units --------------------------------------------------------------------------------------------------

const UNIT_SPRITE_FILES := [["infantry_v2", "alien_infantry_v1"], ["tank_v2", "alien_tank_v1"],
	["anti_armor_v2", "alien_anti_armor_v1"], ["helicopter_v2", "alien_helicopter_v1"], ["capital_v1", "alien_capital_v1"],
	["harvester_v2", "alien_harvester_v1"]]


## A bridge unit entity at hex `tile` (the sim's own coordinates, as the snapshot sends them).
func _unit_entity(scene, id: int, kind: String, owner: int, at: Vector3) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(at)
	return {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100}


func test_unit_widths_follow_the_boards(t) -> void:
	t.eq(WorldSprites.UNIT_KINDS, ["Infantry", "Tank", "AntiArmor", "Helicopter", "Capital", "Harvester"], "by _create_unit kind")
	for i in WorldSprites.UNIT_KINDS.size():
		var kind: String = WorldSprites.UNIT_KINDS[i]
		t.near(float(WorldArt.UNIT_TILES[i]), float(WorldSprites.MOCK_PX[kind]) / 82.0, 0.006, "%s card width in tiles" % kind)
	t.near(float(WorldArt.UNIT_TILES[3]), 2.32, 0.006, "gunship 190 px (CoreAssault, WaveInbound)")
	t.near(float(WorldArt.UNIT_TILES[4]), 4.02, 0.006, "capital 330 px (CoreAssault)")
	t.ok(float(WorldArt.UNIT_TILES[1]) > float(WorldArt.UNIT_TILES[0]), "a tank reads bigger than a squad")


func test_every_unit_kind_has_a_human_and_an_alien_sprite(t) -> void:
	for i in WorldSprites.UNIT_KINDS.size():
		var kind: String = WorldSprites.UNIT_KINDS[i]
		for owner in [0, 1]:
			var tex := WorldSprites.texture_for(kind, owner)
			t.ok(tex != null and tex.resource_path.ends_with("/%s.png" % UNIT_SPRITE_FILES[i][owner]), "%s owner %d: %s" % [kind, owner, tex])


func test_kestrel_units_are_sprite_cards(t) -> void:
	var scene := _kestrel_scene()
	for owner in [0, 1]:
		for kind in 6:
			scene._create_unit(owner, Vector3(10, 0, 10), kind)
			var unit: Node3D = scene.units.back()
			var visual := unit.get_node_or_null("UnitVisual") as Node3D
			var label := "owner %d kind %d" % [owner, kind]
			t.ok(visual is MeshInstance3D and visual.has_meta("sprite_kind"), "%s: the UnitVisual is a sprite card" % label)
			if not (visual is MeshInstance3D):
				continue
			t.ok(_card_texture(visual).resource_path.ends_with("/%s.png" % UNIT_SPRITE_FILES[kind][owner]), "%s: its sprite" % label)
			for n in unit.find_children("*", "Node3D", true, false):
				t.ok(not String(n.scene_file_path).ends_with(".glb"), "%s: no authored model" % label)
			t.eq(visual.get_child_count(), 2, "%s: only the card's two shadows under it (no box-built figures)" % label)
			var tiles := float(WorldArt.UNIT_TILES[kind])
			t.near(visual.scale.x, tiles * WorldArt.TILE, 0.001, "%s: card width" % label)
			t.near(float(unit.get_meta("visual_tiles", 0.0)), tiles, 0.001, "%s: visual_tiles" % label)
			t.eq(visual.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: no real cast shadow" % label)
			var parts: Array = unit.get_meta("pick_parts", [])
			t.eq(parts.size(), 1, "%s: one pick box" % label)
			if parts.size() == 1:
				t.ok((parts[0] as AABB).is_equal_approx(_expected_pick_box(visual)), "%s: the opaque rect" % label)
	scene.free()


func test_unit_card_stands_on_the_units_ground_point(t) -> void:
	var scene := _kestrel_scene()
	var at: Vector3 = scene._hex_world(12, 12)
	scene._sync_bridge_entities([_unit_entity(scene, 980, "Tank", 0, at)])
	var unit: Node3D = scene.bridge_nodes[980]
	var card := unit.get_node("UnitVisual") as Node3D
	var goal: Vector3 = unit.get_meta("glide_to")
	var ground: float = scene._height_world(goal.x, goal.z)
	var contact: float = goal.y + card.position.y  # where the card's contact line (the painted ground) ends up
	t.ok(contact >= ground + WorldSprites.CARD_LIFT - 1e-4, "not buried (%.3f over the ground)" % (contact - ground))
	t.ok(contact <= ground + WorldSprites.CARD_LIFT + 0.08, "and not floating (%.3f over the ground)" % (contact - ground))
	t.near(card.position.x, 0.0, 1e-6, "centred on the root")
	t.near(float(card.get_meta("base_y", -1.0)), card.position.y, 1e-6, "the bob's rest height is the lift")
	scene.free()


func test_unit_shadows_the_boards_way(t) -> void:
	# hud.css .shd (the cast silhouette) and .ao (the dark contact band: silhouette squashed to 0.13 at the 84 % line,
	# 3 px down, blur 6, opacity .6), one shared material per texture
	var card := WorldSprites.make_card("Tank", 0, 1.71, true)
	var other := WorldSprites.make_card("Tank", 0, 1.71, true)
	t.ok(card.get_node_or_null("SpriteShadow") != null, "the cast silhouette")
	var ao := card.get_node_or_null("SpriteContact") as MeshInstance3D
	t.ok(ao != null, "the contact band")
	if ao != null:
		t.ok(ao.material_override == (other.get_node("SpriteContact") as MeshInstance3D).material_override, "shared per texture")
		t.ok(ao.mesh == (other.get_node("SpriteContact") as MeshInstance3D).mesh, "one shared mesh")
		t.eq(ao.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no real shadow")
		var box := ao.mesh.get_aabb()
		t.near(box.size.y, 0.0, 1e-5, "flat on the ground")
		t.ok(box.position.z < 0.0 and box.end.z > 0.0, "around the contact line")
		var tall := WorldSprites.AO_SCALE * (1.0 + 2.0 * WorldSprites.AO_MARGIN.y)  # the squashed painting plus its blur room
		t.near(box.size.z * WorldArt.PITCH_SIN, tall, 1e-4, "squashed to 0.13 on screen, blur room included")
		t.ok(tall < 0.35, "a thin band (%.3f of the width)" % tall)
		var m := ao.material_override as ShaderMaterial
		t.near(float(m.get_shader_parameter("strength")), minf(1.0, 0.6 * WorldSprites.SHADOW_GAIN), 0.001, "the boards' .ao opacity, compensated")
	var building := WorldSprites.make_card("Barracks", 0, 2.44)
	t.ok(building.get_node_or_null("SpriteContact") == null, "a building keeps its contact pad instead")
	card.free()
	other.free()
	building.free()


func test_unit_faces_its_horizontal_screen_motion(t) -> void:
	var scene := _kestrel_scene()
	var start: Vector3 = scene._hex_world(14, 12)
	var west: Vector3 = scene._hex_world(12, 12)
	var east: Vector3 = scene._hex_world(16, 12)
	var north: Vector3 = scene._hex_world(16, 10)
	# both units in every snapshot (a unit missing from one is removed, one appearing later is announced to the HUD)
	# each snapshot is followed by the glide arriving (the test scene runs no frames)
	var sync := func(squad_at: Vector3, tank_at: Vector3) -> void:
		scene._sync_bridge_entities([_unit_entity(scene, 981, "Infantry", 1, squad_at), _unit_entity(scene, 982, "Tank", 0, tank_at)])
		for id in [981, 982]:
			var node: Node3D = scene.bridge_nodes[id]
			node.position = node.get_meta("glide_to")
	sync.call(start, start)
	# the alien squad is painted facing right: moving toward -x mirrors it, and it keeps the mirror when it stops
	var squad: Node3D = scene.bridge_nodes[981]
	var card := squad.get_node("UnitVisual") as MeshInstance3D
	var tank: Node3D = scene.bridge_nodes[982]
	var tank_card := tank.get_node("UnitVisual") as MeshInstance3D
	t.ok(not bool(card.get_meta("mirrored", true)), "spawned as painted")
	sync.call(west, west)
	t.ok(bool(card.get_meta("mirrored", false)), "moving toward -x: mirrored")
	t.ok(card.mesh == WorldSprites.card_mesh(true), "the mirrored card mesh")
	t.ok((card.get_node("SpriteShadow") as MeshInstance3D).mesh == WorldSprites.shadow_mesh(true), "the shadow's silhouette mirrors too")
	t.ok((card.get_node("SpriteContact") as MeshInstance3D).mesh == WorldSprites.contact_mesh(true), "and the contact band")
	t.ok(not squad.has_meta("glide_yaw"), "a card never turns")
	t.near(squad.rotation.y, 0.0, 1e-6, "the root stays square to the camera")
	# the human tank is painted facing left: moving toward -x shows it as painted
	t.ok(not bool(tank_card.get_meta("mirrored", true)), "a left-facing painting moving toward -x is not mirrored")
	sync.call(west, west)
	t.ok(bool(card.get_meta("mirrored", false)), "stopped: keeps its last facing")
	var parts: Array = squad.get_meta("pick_parts", [])
	t.ok(parts.size() == 1 and (parts[0] as AABB).is_equal_approx(_expected_pick_box(card, true)), "the pick box mirrors with it")
	sync.call(east, east)
	t.ok(not bool(card.get_meta("mirrored", true)), "moving toward +x: as painted again")
	t.ok(bool(tank_card.get_meta("mirrored", false)), "the tank mirrors moving toward +x")
	t.near(north.x, east.x, 1e-6, "hex (16, 10) is straight north of (16, 12)")
	sync.call(east, north)
	t.ok(bool(tank_card.get_meta("mirrored", false)), "a purely vertical move keeps the facing")
	scene.free()


func test_gunship_bob_rides_on_the_card_lift(t) -> void:
	var scene := _kestrel_scene()
	scene._create_unit(0, Vector3(10, 0, 10), 3)
	var gunship: Node3D = scene.units.back()
	scene._create_unit(0, Vector3(11, 0, 10), 1)
	var tank: Node3D = scene.units.back()
	scene.time_alive = 0.6
	scene._bob_units()
	var g := gunship.get_node("UnitVisual") as Node3D
	var k := tank.get_node("UnitVisual") as Node3D
	var hover := float(WorldSprites.HOVER["Helicopter"])
	t.near(g.position.y, float(g.get_meta("base_y")) + hover + sin(1.2) * 0.018, 1e-6, "the gunship bobs over its lift and hover")
	t.near(k.position.y, float(k.get_meta("base_y")), 1e-6, "a tank stays on its lift")
	scene.free()


func test_gunship_hovers_over_its_ground_shadow(t) -> void:
	var scene := _kestrel_scene()
	var at: Vector3 = scene._hex_world(12, 12)
	scene._sync_bridge_entities([_unit_entity(scene, 990, "Helicopter", 0, at), _unit_entity(scene, 991, "Tank", 0, scene._hex_world(14, 12))])
	var hover := float(WorldSprites.HOVER.get("Helicopter", 0.0))
	t.ok(hover > 0.15 and hover < 0.6, "a small hover lift (%.2f)" % hover)
	for id in [990, 991]:
		var unit: Node3D = scene.bridge_nodes[id]
		var card := unit.get_node("UnitVisual") as MeshInstance3D
		var lifted := hover if id == 990 else 0.0
		var base := float(card.get_meta("base_y"))
		t.near(card.position.y, base + lifted, 1e-5, "%d: the card rides %.2f over its ground lift" % [id, lifted])
		for part in ["SpriteShadow", "SpriteContact"]:
			var shade := card.get_node(part) as Node3D
			var y := card.position.y + shade.position.y * card.scale.y
			t.near(y, base, 1e-5, "%d: the %s stays on the ground" % [id, part])
		var box: AABB = (unit.get_meta("pick_parts") as Array)[0]
		t.ok(box.is_equal_approx(_expected_pick_box(card)), "%d: the pick box follows the painted body up" % id)
		var top := _card_point(card, 0.5, WorldSprites.opaque_bounds(_card_texture(card)).position.y).y
		t.ok((unit.get_node("HealthBack") as Node3D).position.y > top, "%d: bars over the lifted painting" % id)
	scene.free()


func test_unit_bars_sit_over_the_painted_top_and_no_badge_shows(t) -> void:
	# the boards draw no badge over a unit (the team ring at the feet says whose it is); Survival keeps its badges
	var scene := _kestrel_scene()
	var cos_pitch := _cos_pitch()
	for owner in [0, 1]:
		for kind in 6:
			scene._create_unit(owner, Vector3(10, 0, 10), kind)
			var unit: Node3D = scene.units.back()
			var card := unit.get_node("UnitVisual") as Node3D
			if not card.has_meta("sprite_kind"):
				t.ok(false, "owner %d kind %d is not a card" % [owner, kind])
				continue
			var top := _card_point(card, 0.5, WorldSprites.opaque_bounds(_card_texture(card)).position.y).y * cos_pitch
			var badge := unit.get_node_or_null("StrategicBadge") as Node3D
			t.ok(badge == null or not badge.visible, "owner %d kind %d: no badge over the painting" % [owner, kind])
			var bar := (unit.get_node("HealthBack") as Node3D).position.y * cos_pitch
			t.ok(bar > top + 0.02, "owner %d kind %d: health bar over the painted top" % [owner, kind])
			t.ok(bar < top + 0.15, "owner %d kind %d: and close to it (%.3f)" % [owner, kind, bar - top])
			t.ok((unit.get_node("ShieldBack") as Node3D).position.y > (unit.get_node("HealthFill") as Node3D).position.y, "shield over health")
			t.ok((unit.get_node("TeamMarker") as Node3D).visible, "owner %d kind %d: the team ring stays at the feet" % [owner, kind])
	scene.free()


func test_click_on_a_unit_takes_its_painted_body_only(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	scene._create_unit(0, scene._hex_world(14, 12), 1)
	var tank: Node3D = scene.units.back()
	scene.bridge_nodes[983] = tank
	var card := tank.get_node("UnitVisual") as Node3D
	t.eq(scene._pick_entity(to_screen.call(tank, _card_point(card, 0.5, 0.45)), to_screen), tank, "the painted hull")
	t.eq(scene._pick_entity(to_screen.call(tank, _card_point(card, 0.41, 0.375)), to_screen), tank, "the painted turret (solid paint, PIL), past the old reach")
	for corner in [Vector2(0.02, 0.03), Vector2(0.98, 0.03)]:
		t.eq(scene._pick_entity(to_screen.call(tank, _card_point(card, corner.x, corner.y)), to_screen), null, "transparent corner %s" % corner)
	scene.free()


func test_click_between_two_touching_units_picks_the_nearer_root(t) -> void:
	var scene := _kestrel_scene()
	var to_screen := _ortho(108.0)
	var at: Vector3 = scene._hex_world(14, 12)
	scene._create_unit(0, at, 1)
	var tank: Node3D = scene.units.back()
	scene.bridge_nodes[984] = tank
	scene._create_unit(0, at + Vector3(0.3, 0, 0), 0)
	var squad: Node3D = scene.units.back()
	scene.bridge_nodes[985] = squad
	# the same ground height and card lift: only the horizontal distance differs
	squad.position.y = tank.position.y
	var lift: float = tank.get_node("UnitVisual").position.y
	var squad_card := squad.get_node("UnitVisual") as Node3D
	squad_card.position.y = lift
	squad_card.set_meta("base_y", lift)
	scene._refresh_unit_pick(squad, squad_card)
	# where the squad's rifles cross the tank's hull: paint in both sprites 3 px around (PIL), either side of the midpoint
	for x in [0.1, 0.275]:
		var click: Vector2 = to_screen.call(tank, Vector3(x, lift + 0.37, 0.0))
		t.ok(scene._parts_hold(tank, click, to_screen) and scene._parts_hold(squad, click, to_screen), "x %.2f: both painted bodies hold it" % x)
		var want: Node3D = tank if x < 0.15 else squad
		t.eq(scene._pick_entity(click, to_screen), want, "x %.2f: the nearer root" % x)
	scene.free()


func test_survival_units_keep_their_models(t) -> void:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	for kind in 6:
		scene._create_unit(1, Vector3(10, 0, 10), kind)
		var unit: Node3D = scene.units.back()
		var visual := unit.get_node("UnitVisual") as Node3D
		t.ok(not visual.has_meta("sprite_kind"), "kind %d: no card" % kind)
		t.ok(not visual.has_meta("base_y") and not unit.has_meta("pick_parts"), "kind %d: no profile metas" % kind)
	scene.free()
