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


## A terrain-like height field with a step across x = 0: the right half is 0.5 higher.
func _step_height(p: Vector2) -> float:
	return 0.5 if p.x > 0.0 else 0.0


func _surface_colours(mesh: ArrayMesh) -> PackedColorArray:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]


func test_kestrel_hover_is_a_hex_outline_not_the_amber_torus(t) -> void:
	var scene := _kestrel_scene()
	var mesh: Mesh = scene.hover_tile.mesh
	t.ok(not (mesh is TorusMesh), "no amber torus under the profile")
	t.ok(mesh is ArrayMesh and mesh.get_surface_count() == 1, "one outline surface, so one draw call")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	for v in verts:
		widest = maxf(widest, absf(v.x))
	t.ok(widest <= scene.HEX_X / 1.5 + 0.001, "never wider than one hex (%s)" % widest)
	var mat := scene.hover_tile.material_override as StandardMaterial3D
	t.ok(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "unshaded")
	t.ok(mat.vertex_color_use_as_albedo and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "vertex colours, see-through")
	t.ok(not mat.emission_enabled, "no glow")
	t.eq(scene.hover_tile.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
	scene.free()


func test_hex_outline_has_three_bands_dark_bright_dark(t) -> void:
	var mesh := WorldArt.hex_outline_mesh(0.44, 0.34, 0.03, 0.02, Callable(), 1)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.eq(verts.size(), 3 * 6 * 6, "three bands, six sides, two triangles each")
	var cols := _surface_colours(mesh)
	t.eq(cols.size(), verts.size(), "a colour per vertex")
	var per_band := 6 * 6
	t.eq(cols[0], WorldArt.HOVER_DARK, "outer edge is dark")
	t.eq(cols[per_band], WorldArt.HOVER_BRIGHT, "then the bright line")
	t.eq(cols[2 * per_band], WorldArt.HOVER_DARK, "then the dark inner edge")
	t.ok(WorldArt.HOVER_BRIGHT.b > WorldArt.HOVER_BRIGHT.r and WorldArt.HOVER_BRIGHT.a > 0.9, "the line is a strong pale cyan")
	t.ok(WorldArt.HOVER_BRIGHT.get_luminance() - WorldArt.HOVER_DARK.get_luminance() > 0.6, "bright against dark by luminance")
	for v in verts:
		t.near(v.y, 0.0, 0.0001, "flat without a height function")


func test_hex_outline_drapes_over_a_height_step(t) -> void:
	var mesh := WorldArt.hex_outline_mesh(0.44, 0.34, 0.03, 0.02, _step_height, 3)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := 1000.0
	var high := -1000.0
	for v in verts:
		var ground := _step_height(Vector2(v.x, v.z))
		t.ok(v.y >= ground - 0.0001, "vertex (%s, %s) is not buried" % [v.x, v.z])
		low = minf(low, v.y)
		high = maxf(high, v.y)
	t.near(high - low, 0.5, 0.0001, "the corners follow the step instead of staying level")


func test_kestrel_hover_outline_follows_real_terrain(t) -> void:
	var scene := _kestrel_scene()
	var best := Vector2i(-1, -1)
	var best_range := 0.0
	for x in range(2, scene.MAP_W - 2):
		for y in range(2, scene.MAP_H - 2):
			var w: Vector3 = scene._hex_world(x, y)
			var lo := 1000.0
			var hi := -1000.0
			for d in [Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0.2, 0.3), Vector2(-0.2, -0.3)]:
				var h: float = scene._height_world(w.x + d.x, w.z + d.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
			if hi - lo > best_range:
				best_range = hi - lo
				best = Vector2i(x, y)
	t.ok(best_range > 0.1, "the fixture has a sloped tile (%s)" % best_range)
	var world: Vector3 = scene._hex_world(best.x, best.y)
	var mesh: ArrayMesh = scene._hover_outline_mesh(world)
	var base: float = scene._height_world(world.x, world.z)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := 1000.0
	var high := -1000.0
	for v in verts:
		var ground: float = scene._height_world(world.x + v.x, world.z + v.z)
		t.ok(base + v.y >= ground - 0.0001, "outline vertex sits on or above the terrain")
		low = minf(low, v.y)
		high = maxf(high, v.y)
	t.ok(high - low > 0.05, "the outline is not level on a sloped tile")
	scene.free()


func test_hover_outline_width_follows_zoom(t) -> void:
	var scene := _kestrel_scene()
	var world: Vector3 = scene._hex_world(10, 10)
	scene.camera_zoom = 10.0
	var near_widest := _band_width(scene._hover_outline_mesh(world))
	scene.camera_zoom = 18.0
	var far_widest := _band_width(scene._hover_outline_mesh(world))
	t.ok(far_widest > near_widest * 1.5, "farther out the world width grows so the line keeps its pixel size (%s vs %s)" % [near_widest, far_widest])
	t.near(near_widest, 7.0 / (1080.0 / 10.0), 0.002, "about 7 px across at zoom 10 (3 bright, 2 + 2 dark)")
	scene.free()


## Outer edge to inner edge, measured along +x on the first corner.
func _band_width(mesh: ArrayMesh) -> float:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var outer := -1000.0
	var inner := 1000.0
	for v in verts:
		if absf(v.z) < 0.0001 and v.x > 0.0:
			outer = maxf(outer, v.x)
			inner = minf(inner, v.x)
	return outer - inner


func test_hover_lift_and_visibility_on_kestrel(t) -> void:
	var scene := _kestrel_scene()
	var tile := Vector2i(10, 10)
	var world: Vector3 = scene._hex_world(tile.x, tile.y)
	scene._show_hover_at(world)
	t.ok(scene.hover_tile.visible, "shown on a map tile")
	t.near(scene.hover_tile.position.y, scene._height_world(world.x, world.z) + 0.07, 0.0001, "Kestrel lift 0.07")
	t.eq(scene.hover_cell, tile, "the hovered hex is recorded")
	scene.build_mode = "reactor"
	scene._show_hover_at(world)
	t.ok(not scene.hover_tile.visible, "hidden while a build is armed")
	scene.build_mode = ""
	scene._show_hover_at(Vector3(scene.MAP_ORIGIN_X - 2.0, 0.0, 5.0))
	t.ok(not scene.hover_tile.visible, "hidden off the map")
	t.eq(scene.hover_cell, scene.NO_HOVER, "and no hex is hovered there")
	scene.free()


func _env(scene) -> Environment:
	return scene.environment


func test_kestrel_grade_is_calmer_and_never_shows_sky(t) -> void:
	var scene := _kestrel_scene()
	var env := _env(scene)
	t.near(env.adjustment_saturation, float(WorldArt.ENVIRONMENT.saturation), 0.0001, "grade saturation from the table")
	t.ok(env.adjustment_saturation < 0.85, "less saturated than the legacy grade")
	t.eq(env.background_mode, Environment.BG_COLOR, "a colour background, so no sky can show")
	t.eq(env.background_color.to_html(false), String(WorldArt.ENVIRONMENT.background), "deep sea background")
	t.near(env.tonemap_exposure, float(WorldArt.ENVIRONMENT.exposure), 0.0001, "exposure applied")
	t.near(env.adjustment_contrast, float(WorldArt.ENVIRONMENT.contrast), 0.0001, "contrast applied")
	t.near(env.ambient_light_energy, float(WorldArt.ENVIRONMENT.ambient_energy), 0.0001, "ambient energy applied")
	scene.free()


func test_atmosphere_layer_sits_under_the_hud_and_takes_no_clicks(t) -> void:
	var scene := _kestrel_scene()
	var layer: CanvasLayer = scene.world_atmosphere
	t.ok(layer != null and layer.get_meta("world_art", false), "atmosphere exists and survives world shots")
	var hud_layer := CanvasLayer.new()  # GameUI.setup makes its HUD layer exactly like this, with the default layer number
	t.ok(layer.layer < hud_layer.layer, "below the HUD CanvasLayer (layer %d)" % hud_layer.layer)
	hud_layer.free()
	var rect := layer.get_child(0) as ColorRect
	t.eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never eats a click")
	t.ok(rect.material is ShaderMaterial, "gradient and vignette shader")
	var shader: Shader = (rect.material as ShaderMaterial).shader
	t.ok(shader.code.contains("void fragment()"), "the shader has a fragment function")
	t.eq(shader.get_mode(), Shader.MODE_CANVAS_ITEM, "it compiles as a canvas_item shader")
	var uniforms: Array = []
	for u in shader.get_shader_uniform_list():
		uniforms.append(String(u.name))
	t.ok(uniforms.has("warm") and uniforms.has("dark") and uniforms.has("vignette"), "its uniforms parsed, so it compiled")
	scene.free()


func test_kestrel_deposits_are_crystals_without_labels(t) -> void:
	var scene := _kestrel_scene()
	scene._sync_bridge_map(_snap())
	var deposits := scene.find_children("Deposit_*", "Node3D", true, false)
	t.eq(deposits.size(), _snap()["deposits"].size(), "one deposit node per deposit")
	for d in deposits:
		t.eq(d.get_child_count(), 0, "no disk, spheres or ORE label under the profile (%s)" % d.name)
		t.ok(d.is_in_group("resource_deposits"), "still in its group")
	t.eq(scene.deposit_tiles.size(), _snap()["deposits"].size(), "build rules still see every deposit tile")
	scene.bridge_earthfront = false  # the deposit rule of _is_build_valid (Earthfront asks the construction zone instead)
	scene.build_mode = "Refinery"
	t.ok(scene._is_build_valid(Vector2i(18, 7)), "a Refinery is valid on the ore site")
	t.ok(not scene._is_build_valid(Vector2i(10, 10)), "and invalid off it")
	scene.build_mode = "Barracks"
	t.ok(not scene._is_build_valid(Vector2i(18, 7)), "other buildings stay off the ore site")
	scene.free()


func test_kestrel_mined_out_deposit_crystals_turn_spent(t) -> void:
	var scene := _kestrel_scene()
	var snap := _snap()
	scene._sync_bridge_map(snap)
	scene._sync_spent_deposits(snap)
	t.eq(scene.world_props._spent.size(), 0, "every deposit still has ore, nothing is spent")
	# the sim drops an exhausted deposit from the snapshot list (Map::mine clears it); a zero amount counts the same
	var later := _snap()
	later["deposits"] = later["deposits"].filter(func(d): return not (int(d["x"]) == 18 and int(d["y"]) == 7))
	for d in later["deposits"]:
		if int(d["x"]) == 31 and int(d["y"]) == 2:
			d["remaining"] = 0
	scene._sync_spent_deposits(later)
	t.ok(scene.world_props._spent.has(Vector2i(18, 7)), "the mined-out ore site reads as spent")
	t.ok(scene.world_props._spent.has(Vector2i(31, 2)), "an alloy site at zero reads as spent")
	t.eq(scene.world_props._spent.size(), 2, "the other sites keep their bright crystals")
	t.eq(scene.deposit_tiles.size(), snap["deposits"].size(), "build rules are untouched")
	scene.free()
