extends RefCounted
## Survival never builds a ground model, so it keeps every legacy world value. Each world-art task adds its own lines here.
const MainScene = preload("res://main.tscn")


func _survival_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	snap["ground"] = "g".repeat(44 * 26)
	scene._sync_ground(snap)
	return scene


func test_survival_keeps_the_legacy_camera(t) -> void:
	var scene := _survival_scene()
	t.ok(not scene.world_art_on, "no profile without a real ground layer")
	t.near(scene.camera_yaw, -0.68, 0.0001, "rotated legacy camera")
	t.eq(scene._zoom_limits(), Vector2(7.5, 24.0), "legacy zoom range")
	t.near(scene._zoom_default(), 8.8, 0.0001, "legacy default zoom")
	t.ok(scene.ocean_box.visible, "legacy ocean box")
	t.near(scene.terrain_renderer.edge_margin_cells, 4.0, 0.001, "legacy noise mesh margin")
	scene.free()


func test_survival_keeps_rotation_focus_zoom_and_placement(t) -> void:
	var scene := _survival_scene()
	scene._camera_step(1.0, Vector3.ZERO, 16.0 / 9.0, 1.0)
	t.near(scene.camera_yaw, -0.68 + 0.72, 0.0001, "Z/E still rotate Survival")
	scene.focus_camera(Vector3(10, 0, 8), 8.2)
	t.near(scene.camera_focus_zoom, 8.2, 0.0001, "focus jumps keep their own zoom")
	scene.camera_focus_target = Vector3(-30, 0, -30)
	scene._camera_step(0.016, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.near(scene.camera_focus_target.x, scene.MAP_ORIGIN_X, 0.001, "legacy clamp to the map")
	t.eq(scene.camera_view_target(), scene.camera_target, "the shown view is the plain target")
	t.ok(not scene._off_map(Vector3(-50, 0, -50)), "off-map points are not special in Survival")
	t.ok(scene.sea_backdrop == null, "no sea backdrop")
	scene.free()


func test_survival_keeps_the_amber_hover_torus(t) -> void:
	var scene := _survival_scene()
	var torus := scene.hover_tile.mesh as TorusMesh
	t.ok(torus != null, "legacy torus")
	t.near(torus.inner_radius, 0.42, 0.0001, "inner")
	t.near(torus.outer_radius, 0.47, 0.0001, "outer")
	t.ok(scene.hover_tile.material_override == scene.materials.hover, "legacy amber material")
	scene.free()


func test_survival_keeps_the_legacy_environment(t) -> void:
	var scene := _survival_scene()
	var env: Environment = scene.environment
	t.near(env.tonemap_exposure, 0.78, 0.0001, "exposure")
	t.near(env.adjustment_saturation, 0.85, 0.0001, "saturation")
	t.eq(env.background_mode, Environment.BG_SKY, "sky background")
	t.ok(scene.world_atmosphere == null, "no atmosphere layer")
	scene.free()


## Byte-level pins of the Survival terrain (noise shader source, every mesh channel) taken on f258da1, before the Kestrel
## painted ground: Survival's terrain look must not move when the snapshot-driven ground changes.
func _mesh_digest(mesh: ArrayMesh) -> String:
	var arrays := mesh.surface_get_arrays(0)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
		ctx.update(var_to_bytes(arrays[slot]))
	return ctx.finish().hex_encode()


func test_survival_keeps_the_legacy_terrain_look(t) -> void:
	var scene := _survival_scene()
	var terrain: Node3D = scene.terrain_renderer
	var inst := terrain.get_node("ContinuousPainterlyTerrain") as MeshInstance3D
	var mat := inst.material_override as ShaderMaterial
	t.ok(terrain.ground == null, "no ground model in Survival")
	t.eq(mat.shader.code.sha256_text(), "7703388a649501384902595f77763aea8ebe71be18ac2c254c4dd34bb51de5bb", "noise shader source unchanged")
	t.eq(_mesh_digest(inst.mesh as ArrayMesh), "fbadf6e28b06edba4f3dee3ecc601ff0b34ecfc18e54bd66bb7c817a46ec0121", "terrain mesh (positions, normals, colours, UVs, indices) unchanged")
	t.ok(mat.get_shader_parameter("rock_texture") == null, "no rock texture on the Survival terrain")
	var detail: Texture2D = mat.get_shader_parameter("detail_texture")
	t.ok(detail == load("res://assets/terrain/painterly/continuous_ground_detail_v4.png"), "Survival samples the imported detail texture")
	t.ok(detail != null and not detail.get_image().has_mipmaps(), "unchanged import: no mipmaps on Survival")
	t.eq((inst.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2, 0, "no UV2 channel in Survival")
	scene.free()


func test_only_kestrel_gets_the_painted_ground(t) -> void:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var m = load("res://scripts/terrain/ground_model.gd").from_snapshot(JSON.parse_string(f.get_as_text()))
	var terrain: Node3D = load("res://scripts/continuous_terrain.gd").new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, null)
	terrain.apply_ground(m)
	var inst := terrain.get_node("ContinuousPainterlyTerrain") as MeshInstance3D
	var mat := inst.material_override as ShaderMaterial
	t.ok(mat.get_shader_parameter("rock_texture") is Texture2D, "Kestrel ground carries the rock texture")
	t.ok((inst.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2 != 0, "Kestrel ground carries UV2 (sea, rock)")
	terrain.free()


func test_survival_keeps_the_legacy_dressing(t) -> void:
	var scene := _survival_scene()
	t.ok(scene.world_props == null, "no prop MultiMeshes")
	t.eq(scene.find_children("*", "MultiMeshInstance3D", true, false).size(), 0, "nothing new in the scene")
	scene.free()


func test_survival_deposits_keep_their_disk_and_label(t) -> void:
	var scene := _survival_scene()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	scene._sync_bridge_map(snap)
	var labels := 0
	for d in scene.find_children("Deposit_*", "Node3D", true, false):
		labels += d.find_children("*", "Label3D", true, false).size()
	t.ok(labels > 0, "legacy ORE labels")
	scene.free()


func test_survival_keeps_tactical_buildings(t) -> void:
	var scene := _survival_scene()
	var site := Node3D.new()
	scene.add_child(site)
	var hq: Node3D = scene.tactical_models.building(scene, site, "CommandCenter")
	t.ok(hq != null, "the box-built CC still builds")
	t.ok(not site.has_meta("visual_tiles"), "no width table outside the profile")
	scene.free()


func test_survival_units_keep_the_legacy_size(t) -> void:
	var scene := _survival_scene()
	scene._create_unit(0, Vector3(6, 0, 6), 1)
	var tank: Node3D = scene.units.back()
	t.ok(not tank.has_meta("visual_tiles"), "no width table outside the profile")
	t.eq((tank.get_node("UnitVisual") as Node3D).scale, Vector3.ONE * 0.70, "legacy tank scale")
	t.near((tank.get_node("HealthBack") as Node3D).position.y, 0.88, 1e-6, "legacy health bar height")
	t.near((tank.get_node("ShieldFill") as Node3D).position.y, 0.958, 1e-6, "legacy shield bar height")
	t.near((tank.get_node("StrategicBadge") as Node3D).position.y, 0.48, 1e-6, "legacy badge height")
	t.near(scene._label_y(tank), 0.9, 1e-6, "legacy relay label height")
	scene.free()


func test_survival_blocked_tiles_keep_their_ruins_and_rocks(t) -> void:
	var scene := _survival_scene()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	var before: int = scene.get_child_count()
	scene._sync_bridge_map(snap)
	var legacy := 0  # _sync_bridge_map's own rule: a ruin on (x * 3 + z) % 37 == 0, else rocks on (x + z) % 9 == 0
	for c in snap.blocked:
		if (int(c[0]) * 3 + int(c[1])) % 37 == 0 or (int(c[0]) + int(c[1])) % 9 == 0:
			legacy += 1
	t.ok(legacy > 0, "the fixture has legacy ruin and rock tiles")
	t.eq(scene.get_child_count() - before, snap.deposits.size() + legacy, "one deposit root per deposit plus the legacy ruins and rocks")
	scene.free()
