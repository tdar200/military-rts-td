extends RefCounted
## The "pasted on" fix: a warm, shadow-casting sun from the north-west plus an ambient level that keeps the shadows readable.

const MainScene = preload("res://main.tscn")


## The scene is built without entering the tree (the test runner is mid-_initialize, where root.add_child is refused),
## so the builders are called directly: the same code _ready runs, minus the bridge and the UI.
func _scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	return scene


func _sun(scene: Node) -> DirectionalLight3D:
	var found: DirectionalLight3D = null
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled:
			found = n
	return found


func test_scene_has_a_shadow_casting_sun(t) -> void:
	var scene := _scene()
	var sun := _sun(scene)
	t.ok(sun != null, "a shadow-casting DirectionalLight3D exists")
	if sun != null:
		t.eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "four cascades")
		t.near(sun.shadow_bias, 0.04, 0.0001, "shadow bias")
		t.near(sun.shadow_normal_bias, 1.0, 0.0001, "shadow normal bias")
		t.near(sun.directional_shadow_max_distance, 120.0, 0.0001, "shadow reaches the whole base")
		t.ok(sun.light_color.r > sun.light_color.b, "the sun is warm")
	scene.free()


func test_sun_comes_from_the_north_west_at_38_degrees(t) -> void:
	var scene := _scene()
	var sun := _sun(scene)
	t.ok(sun != null, "sun exists")
	if sun != null:
		var travel := -sun.transform.basis.z  # the direction the light travels; the scene root is the identity
		t.near(rad_to_deg(asin(-travel.y)), 38.0, 0.5, "elevation above the horizon")
		# North is -Z and west is -X, so a north-west sun sits at (-x, -z) and its light travels toward (+x, +z).
		t.ok(travel.x > 0.1 and travel.z > 0.1, "light travels south-east, i.e. the sun is in the north-west")
		t.near(travel.x, travel.z, 0.02, "due north-west, not skewed")
	scene.free()


func test_only_one_shadow_casting_light(t) -> void:
	var scene := _scene()
	var casters := 0
	for n in scene.find_children("*", "Light3D", true, false):
		if (n as Light3D).shadow_enabled:
			casters += 1
	t.eq(casters, 1, "a single sun casts shadows; the fill light stays shadowless")
	scene.free()


func test_ambient_keeps_shadows_readable(t) -> void:
	var scene := _scene()
	var env: Environment = null
	for n in scene.find_children("*", "WorldEnvironment", true, false):
		env = (n as WorldEnvironment).environment
	t.ok(env != null, "a WorldEnvironment exists")
	if env != null:
		t.near(env.ambient_light_sky_contribution, 0.35, 0.0001, "sky contributes 35 percent of the ambient light")
		t.ok(env.ambient_light_color.get_luminance() > 0.1, "the rest of the ambient is a real colour, not black")
		var renderer := String(RenderingServer.get_current_rendering_method())
		if renderer == "gl_compatibility" or DisplayServer.get_name() == "headless":
			t.ok(not env.ssao_enabled, "SSAO stays off where the renderer cannot draw it")
	scene.free()


func test_terrain_casts_and_receives_shadows(t) -> void:
	var scene := _scene()
	scene._build_terrain()
	var terrain := scene.terrain_renderer.find_child("ContinuousPainterlyTerrain", true, false) as MeshInstance3D
	t.ok(terrain != null, "the continuous terrain mesh exists")
	if terrain != null:
		t.eq(terrain.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "terrain casts shadows (ridges shade the valleys)")
	scene.free()


func test_buildings_and_units_cast_shadows(t) -> void:
	var scene := _scene()
	var site := Node3D.new()
	scene.add_child(site)
	var hq: Node3D = scene.tactical_models.building(scene, site, "CommandCenter")
	var casters := 0
	for m in hq.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			casters += 1
	t.ok(casters > 0, "the command centre model casts shadows")
	scene._create_unit(0, Vector3(6, 0, 6), 0)
	var unit: Node3D = scene.units.back()
	casters = 0
	for m in unit.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			casters += 1
	t.ok(casters > 0, "the infantry model casts shadows")
	var model := Node3D.new()
	scene.add_child(model)
	var glb: Node3D = scene._place_scene(model, "res://assets/models/authored/human_industry.glb", Vector3.ZERO, Vector3.ONE * 0.3)
	var all_on := true
	var count := 0
	for m in glb.find_children("*", "MeshInstance3D", true, false):
		count += 1
		all_on = all_on and (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	t.ok(count > 0 and all_on, "every mesh of a loaded .glb building casts shadows")
	scene.free()
