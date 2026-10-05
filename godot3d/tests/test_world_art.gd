extends RefCounted
## The Kestrel world-art profile (spec addendum W1 to W3): gate, north-up camera, focus clamp, map-edge continuation.
const WorldArt := preload("res://scripts/world/world_art.gd")
const MainScene = preload("res://main.tscn")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


## Built like test_lighting: the scene never enters the tree (the runner is mid-_initialize).
func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	return scene


func _bounds(scene) -> Rect2:
	return WorldArt.world_bounds(scene.MAP_W, scene.MAP_H, scene.MAP_ORIGIN_X, scene.MAP_ORIGIN_Z, scene.HEX_X, scene.HEX_Z, int(WorldArt.CAMERA.edge_cells))


func test_kestrel_switches_the_profile_on(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.world_art_on, "a real ground layer turns the profile on")
	t.near(scene.camera_yaw, 0.0, 0.0001, "north-up camera")
	t.eq(scene._zoom_limits(), Vector2(7.5, 18.0), "zoom range 7.5 to 18")
	t.near(scene._zoom_default(), 10.0, 0.0001, "default zoom 10")
	t.ok(not scene.ocean_box.visible, "the legacy ocean box is hidden; the terrain draws the sea")
	scene.free()


func test_clamp_keeps_every_view_corner_inside_the_bounds(t) -> void:
	var bounds := WorldArt.world_bounds(44, 26, 2.1, 1.0, 0.68, 0.70, 8)
	for zoom in [7.5, 10.0, 18.0]:
		for yaw in [0.0, 0.4]:
			for want in [Vector3(-100, 0, -100), Vector3(100, 0, 100), Vector3(-100, 0, 100), Vector3(17, 0, 9)]:
				var f := WorldArt.clamp_focus(want, zoom, 16.0 / 9.0, yaw, bounds)
				var e := WorldArt.view_half_extent(zoom, 16.0 / 9.0, yaw)
				if yaw == 0.0:
					t.ok(bounds.size.x > 2.0 * e.x and bounds.size.y > 2.0 * e.y, "the north-up view always fits the bounds at zoom %s" % zoom)
				# A view larger than the bounds on an axis cannot fit: the clamp centres it there (next test).
				if bounds.size.x > 2.0 * e.x:
					t.ok(f.x - e.x >= bounds.position.x - 0.001 and f.x + e.x <= bounds.end.x + 0.001, "x inside at zoom %s yaw %s" % [zoom, yaw])
				else:
					t.near(f.x, bounds.get_center().x, 0.001, "x centred at zoom %s yaw %s" % [zoom, yaw])
				if bounds.size.y > 2.0 * e.y:
					t.ok(f.z - e.y >= bounds.position.y - 0.001 and f.z + e.y <= bounds.end.y + 0.001, "z inside at zoom %s yaw %s" % [zoom, yaw])
				else:
					t.near(f.z, bounds.get_center().y, 0.001, "z centred at zoom %s yaw %s" % [zoom, yaw])


func test_clamp_centres_a_view_wider_than_the_bounds(t) -> void:
	var small := Rect2(0, 0, 4, 4)
	var f := WorldArt.clamp_focus(Vector3(50, 0, -50), 18.0, 16.0 / 9.0, 0.0, small)
	t.near(f.x, 2.0, 0.001, "centred in x")
	t.near(f.z, 2.0, 0.001, "centred in z")


func test_south_row_can_sit_above_the_bottom_hud(t) -> void:
	var bounds := WorldArt.world_bounds(44, 26, 2.1, 1.0, 0.68, 0.70, 8)
	var tile_z := 1.0 + 25.0 * 0.70 + 0.35  # tile (21, 25), odd column
	var f := WorldArt.clamp_focus(Vector3(2.1 + 21.0 * 0.68, 0, tile_z), 10.0, 16.0 / 9.0, 0.0, bounds)
	var screen_y := 540.0 + (tile_z - f.z) * WorldArt.PITCH_SIN * 1080.0 / 10.0
	t.ok(screen_y <= 1080.0 - 320.0, "the south row reaches above the deck (y %s)" % screen_y)


func test_sun_shadows_fall_screen_right_and_down_north_up(t) -> void:
	var scene := _kestrel_scene()
	var sun: DirectionalLight3D = null
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled:
			sun = n
	var travel := -sun.transform.basis.z
	var yaw: float = scene.camera_yaw
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var down := Vector3(sin(yaw), 0, cos(yaw))
	t.ok(travel.dot(right) > 0.1 and travel.dot(down) > 0.1, "drop shadows go lower-right like the boards")
	scene.free()


func test_off_map_ground_continues_the_edge_cell(t) -> void:
	var scene := _kestrel_scene()
	var terrain = scene.terrain_renderer
	var west: float = terrain.height_at_world(2.1 - 6.0 * 0.68, 1.0 + 10.0 * 0.70)  # 6 cells west of grass (0, 10)
	var south_east: float = terrain.height_at_world(2.1 + 49.0 * 0.68, 1.0 + 22.0 * 0.70)  # 6 cells east of sea (43, 22)
	t.ok(west > -0.1, "land continues past the west edge (%s)" % west)
	t.ok(south_east < -0.4, "sea continues past the sea edge (%s)" % south_east)
	t.near(terrain.edge_margin_cells, 10.0, 0.001, "the mesh reaches 10 cells past the map, two beyond the camera bounds")
	scene.free()


func _settle(scene, steps: int = 600) -> void:
	for _i in steps:
		scene._camera_step(1.0 / 60.0, Vector3.ZERO, 16.0 / 9.0, 0.0)


func test_deploy_zoom_in_ends_with_the_command_center_centred(t) -> void:
	var scene := _kestrel_scene()
	var command := Node3D.new()  # the harness Command Center sits at (7.13, 7.65)
	command.set_meta("team", 0)
	command.set_meta("kind_name", "CommandCenter")
	command.position = Vector3(7.13, 0.0, 7.65)
	scene.bridge_nodes[0] = command
	scene._deploy_camera()
	t.near(scene.camera_zoom, 15.5, 0.001, "deploy starts zoomed out")
	_settle(scene)
	var home: Vector3 = scene.home_focus()
	t.near(scene.camera_zoom, 10.0, 0.01, "zoom settles at the default")
	t.near(scene.camera_focus_target.x, home.x, 0.001, "the stored target is not displaced (x)")
	t.near(scene.camera_focus_target.z, home.z, 0.001, "the stored target is not displaced (z)")
	var view: Vector3 = scene.camera_view_target()
	t.near(view.x, home.x, 0.02, "the Command Center is at the screen centre (x)")
	t.near(view.z, home.z, 0.02, "the Command Center is at the screen centre (z)")
	t.near(home.x, 7.13, 0.001, "home_focus found the Command Center")
	command.free()
	scene.free()


func test_focus_jump_from_max_zoom_centres_on_the_unit(t) -> void:
	var scene := _kestrel_scene()
	scene.camera_focus_zoom = 18.0
	scene.camera_zoom = 18.0
	scene.camera_focus_target = scene.home_focus()
	scene.camera_target = scene.home_focus()
	_settle(scene, 30)
	var unit: Vector3 = scene.hex_world_point(8, 12)
	scene.focus_camera(unit, 8.2)
	t.near(scene.camera_focus_zoom, float(WorldArt.CAMERA.focus_zoom), 0.001, "one focus-jump zoom on Kestrel")
	_settle(scene)
	var view: Vector3 = scene.camera_view_target()
	t.near(view.x, unit.x, 0.02, "the unit is centred (x)")
	t.near(view.z, unit.z, 0.02, "the unit is centred (z)")
	scene.free()


func test_zooming_out_at_an_edge_and_back_returns_the_view(t) -> void:
	var scene := _kestrel_scene()
	var edge: Vector3 = scene.hex_world_point(2, 3)
	scene.camera_focus_target = edge
	scene.camera_target = edge
	scene.camera_zoom = 10.0
	scene.camera_focus_zoom = 10.0
	_settle(scene, 200)
	var before: Vector3 = scene.camera_view_target()
	scene.camera_focus_zoom = 18.0
	_settle(scene, 200)
	var out: Vector3 = scene.camera_view_target()
	t.ok(out.distance_to(before) > 1.0, "zoomed out at the edge the shown view moves inward")
	var bounds := _bounds(scene)
	var e := WorldArt.view_half_extent(scene.camera_zoom, 16.0 / 9.0, 0.0)
	t.ok(out.x - e.x >= bounds.position.x - 0.01 and out.z - e.y >= bounds.position.y - 0.01, "and stays inside the ground")
	scene.camera_focus_zoom = 10.0
	_settle(scene, 400)
	var back: Vector3 = scene.camera_view_target()
	t.near(back.x, before.x, 0.02, "zooming back in returns the view (x)")
	t.near(back.z, before.z, 0.02, "zooming back in returns the view (z)")
	t.near(scene.camera_focus_target.x, edge.x, 0.001, "the stored target never moved")
	scene.free()


func test_rotate_keys_do_nothing_on_kestrel(t) -> void:
	var scene := _kestrel_scene()
	scene._camera_step(1.0, Vector3.ZERO, 16.0 / 9.0, 1.0)
	scene._camera_step(1.0, Vector3.ZERO, 16.0 / 9.0, -1.0)
	t.near(scene.camera_yaw, 0.0, 0.0001, "north-up stays north-up")
	scene.free()


func test_off_map_ground_is_not_hoverable_or_placeable(t) -> void:
	var scene := _kestrel_scene()
	var inside: Vector3 = scene._hex_world(10, 10)
	t.ok(not scene._off_map(inside), "a map tile is on the map")
	t.ok(scene._off_map(Vector3(scene.MAP_ORIGIN_X - 2.0, 0.0, 5.0)), "west of the map is off")
	t.ok(scene._off_map(Vector3(20.0, 0.0, scene.MAP_ORIGIN_Z - 2.0)), "north of the map is off")
	t.ok(scene._off_map(Vector3(20.0, 0.0, scene.MAP_ORIGIN_Z + float(scene.MAP_H + 3) * scene.HEX_Z)), "south of the map is off")
	scene.build_mode = "reactor"
	scene._try_place_build(Vector3(scene.MAP_ORIGIN_X - 2.0, 0.0, 5.0))
	t.eq(scene.build_mode, "reactor", "an off-map click is ignored and placement stays armed")
	scene.free()


func test_sea_backdrop_covers_the_minimap_rect(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.sea_backdrop != null and scene.sea_backdrop.visible, "a sea backdrop exists")
	var plane: PlaneMesh = scene.sea_backdrop.mesh
	var half := plane.size * 0.5
	var centre := Vector2(scene.sea_backdrop.position.x, scene.sea_backdrop.position.z)
	var GameUI = preload("res://scripts/ui/game_ui.gd")
	var span: float = GameUI.MINIMAP_SPAN
	var wide := span * 2.5  # a slot up to 2.5:1
	var cx: float = GameUI.MINIMAP_CENTER.x
	var cz: float = GameUI.MINIMAP_CENTER.z
	t.ok(cx - wide * 0.5 >= centre.x - half.x and cx + wide * 0.5 <= centre.x + half.x, "covers the minimap width")
	t.ok(cz - span * 0.5 >= centre.y - half.y and cz + span * 0.5 <= centre.y + half.y, "covers the minimap depth")
	t.ok(scene.sea_backdrop.position.y < -0.85, "below the terrain sea level, so the terrain still draws the sea")
	scene.free()
