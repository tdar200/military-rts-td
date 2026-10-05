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
