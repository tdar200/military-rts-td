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
