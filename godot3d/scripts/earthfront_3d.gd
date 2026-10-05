extends Node3D

# 44 x 26 until a snapshot carrying a ground layer reports its own map_width/map_height.
var MAP_W := 44
var MAP_H := 26
const HEX_X := 0.68
const HEX_Z := 0.70
const MAP_ORIGIN_X := 2.1
const MAP_ORIGIN_Z := 1.0
const SIM_HEX_X := 0.75
const SIM_CELL_CENTER := 0.5
const HUMAN := 0
const ALIEN := 1
const TICKS_PER_SECOND := 30.0
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")
const GroundModel = preload("res://scripts/terrain/ground_model.gd")
const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldProps := preload("res://scripts/world/world_props.gd")
const ERA_NAMES := [
	"CONTEMPORARY HUMANITY", "ADVANCED INDUSTRIAL", "FUSION", "SOLAR",
	"INTERSTELLAR", "STELLAR ENGINEERING", "POST-BIOLOGICAL OPTIONS",
	"SPACETIME ENGINEERING", "GALACTIC", "COSMIC",
]
const BRANCH_NAMES := [
	"COMPUTATION / AI",
	"ENERGY / POWER",
	"MATERIALS",
	"PROPULSION",
	"WEAPONS",
	"DEFENCE",
	"BIOLOGY / CIVILIZATION",
	"LOGISTICS",
	"DARK SECTOR",
	"QUANTUM GRAVITY",
]

var camera: Camera3D
var camera_target := Vector3(16.7, 0.0, 10.0)
var camera_yaw := -0.68
var camera_zoom := 12.2
var terrain_height: Dictionary = {}
var terrain_renderer: Node3D
var ground_model: RefCounted  # GroundModel from the snapshot ground layer; null = cosmetic noise terrain
var environment: Environment  # the WorldEnvironment's resource, kept so the Kestrel grade can be applied later
var world_atmosphere: CanvasLayer  # Kestrel only: warm light and vignette under the HUD
var world_art_on := false  # Kestrel world-art profile (a real ground layer arrived); Survival keeps every legacy value
var world_props: RefCounted  # Kestrel only: WorldProps, the painted props as two MultiMeshes (null in Survival)
var _fit_cache: Dictionary = {}  # Kestrel only: model key -> Vector2(fit scale, fitted top), one AABB walk per model
var _ground_deposits: Array = []  # deposits of the snapshot that carried the ground layer, for the prop scatter
var _ground_route: Array = []  # its wave route: the scatter keeps cards off it (and off the ford and its approach)
var ocean_box: MeshInstance3D
var sea_backdrop: MeshInstance3D  # Kestrel: flat sea far below the terrain, so the minimap and any frame past the mesh never show the clear colour
var camera_aspect := 16.0 / 9.0
var ground_warnings := 0  # times a malformed ground layer was reported: once, not on every poll
var bridge_snapshot: Dictionary = {}  # the latest parsed bridge snapshot; live_adapter.gd derives the gameplay HUD slices from it
const NO_HOVER := Vector2i(-1, -1)
## Snapshots are polled every BRIDGE_POLL seconds. Units glide toward the last polled position every frame at the rate that
## used to be applied once per poll (38 percent of the gap per poll), so they move smoothly at the frame rate instead of
## jumping about eight times a second, and trail the simulation by the same amount as before.
const BRIDGE_POLL := 0.12
const GLIDE_RATE := 3.98  # = -ln(1 - 0.38) / BRIDGE_POLL, per second
const TURN_RATE := 3.46  # = -ln(1 - 0.34) / BRIDGE_POLL, per second
var hover_cell := NO_HOVER  # hex under the cursor, NO_HOVER when none; only reassigned when the hex changes
## The pointer as the last mouse event placed it (see mouse_position). Unknown until one arrives, and again once the
## pointer leaves the window, when mouse_position falls back to asking the window system.
var pointer_position := Vector2.ZERO
var pointer_known := false
var terrain_dressing: Array = []  # nodes built on top of the terrain surface (trees, rocks, lattice, river)
var materials: Dictionary = {}
var tactical_models = preload("res://scripts/tactical_models.gd").new()
var units: Array[Node3D] = []
var selected: Node3D
var selected_units: Array[Node3D] = []
var control_groups: Dictionary = {}
var drag_start := Vector2.ZERO
var dragging := false
var selection_double_click := false
var selection_box: Control
var ui: Node  # GameUI: every on-screen surface
var build_cursor_is_valid := false
var attack_move_armed := false
## True after the structure panel's Set rally button: the next left click on the map sets the selected producer's rally point.
var rally_armed := false
var build_mode := ""
var selection_ring: MeshInstance3D
var objective_label: Label
var bridge_relays := 0
var bridge_active_relays := 0
var bridge_expedition_size := 0
var bridge_active := false
var bridge_poll_elapsed := 0.0
var bridge_nodes: Dictionary = {}
var bridge_map_synced := false
var bridge_money := 0
var bridge_energy := 0
var bridge_labour := 0
var bridge_supply_used := 0
var bridge_supply_cap := 0
var bridge_era := 0
var runtime_directory := "res://runtime"
var command_sequence := 0
var bridge_earthfront := true
var bridge_technology_total := 12
var bridge_power_generation := 0
var bridge_power_demand := 0
var bridge_ore := 0
var bridge_depot_ammo := 0
var bridge_incoming_doctrine := "Mixed expedition"
var bridge_storage_capacity := 0
var bridge_research_status := ""
var bridge_services: Dictionary = {}
var bridge_research_count := 0
var bridge_active_research_id := -1
var bridge_active_research_ticks := 0
var bridge_active_research_name := ""
var bridge_suggested_research_id := -1
var bridge_suggested_research_name := ""
var bridge_research_options: Array = []
var bridge_research_signature := ""
var bridge_winner := -1
var science_overlay: Control
var time_alive := 0.0
var battle_started := false
var mission_deployed := false
var bridge_tick := 0
var bridge_waves := 0
var bridge_next_wave_ticks := -1
var bridge_unlocked_buildings: Array = []
var bridge_unlocked_units: Array = []
var bridge_frame_entities: Dictionary = {}
var bridge_initialized := false
var tutorial_label: Label
var tutorial_stage := -1
var end_screen_shown := false
var camera_shake := 0.0
var alert_cooldown := 0.0
var wave_warning_level := 0
var build_ghost: MeshInstance3D
var blocked_tiles: Dictionary = {}
var construction_zone: Dictionary = {}
var deposit_tiles: Dictionary = {}
var hover_tile: MeshInstance3D
var hover_outline_key := Vector3i(-1, -1, -1)  # hex and zoom the Kestrel hover outline was last built for
const HOVER_LIFT_KESTREL := 0.07
var range_ring: MeshInstance3D
var camera_focus_target := Vector3(16.7, 0.0, 10.0)
var camera_focus_zoom := 12.2
var camera_cinematic := 0.0
var last_dust_time := 0.0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--runtime-dir="):
			runtime_directory = argument.trim_prefix("--runtime-dir=")
	# A pause.flag left by a crash or a force-quit while paused would hold the bridge still on the next launch; a fresh scene
	# is never paused. Same path logic as set_sim_paused.
	set_sim_paused(false)
	# Outside the window there are no mouse events, so mouse_position asks the window system again (edge panning).
	get_window().mouse_exited.connect(func() -> void: pointer_known = false)
	_create_materials()
	_setup_environment()
	_setup_audio()
	_build_terrain()
	_build_ui()
	_update_camera()


func _create_materials() -> void:
	materials.uniform = _material(Color("424c3b"), 0.90)
	materials.steel = _material(Color("252d30"), 0.80, 0.15)
	materials.industrial = _material(Color("666b63"), 0.90)
	materials.foundation = _material(Color("484c48"), 1.0)
	materials.canvas = _material(Color("65604b"), 1.0)
	materials.skin = _material(Color("aa8e74"), 1.0)
	materials.window = _material(Color("243d43"), 0.4, 0.15)
	materials.marking = _material(Color("849f9f"), 0.9)
	materials.grass = _material(Color("8ba061"), 0.9)
	materials.grass_light = _material(Color("a5ae6d"), 0.9)
	materials.plains = _material(Color("a98558"), 0.94)
	materials.earth = _material(Color("795b3c"), 1.0)
	materials.rock = _material(Color("85847a"), 0.96)
	materials.cliff = _material(Color("8b6946"), 1.0)
	materials.water = _water_material()
	materials.road = _material(Color("6b6860"), 0.98)
	materials.road_edge = _material(Color("454740"), 1.0)
	materials.farm = _material(Color("e3bf42"), 0.9)
	materials.human = _material(Color("3265b5"), 0.64, 0.26)
	materials.human_dark = _material(Color("173554"), 0.58, 0.38)
	materials.alien = _material(Color("aa344f"), 0.5, 0.48)
	materials.alien_dark = _material(Color("3c1833"), 0.48, 0.58)
	materials.concrete = _material(Color("746b5a"), 0.98)
	materials.roof = _material(Color("315170"), 0.68, 0.2)
	materials.glass = _material(Color("4cbfe1"), 0.24, 0.1, Color("39c7e8"), 0.15)
	materials.plasma = _material(Color("d857c6"), 0.22, 0.18, Color("e647d4"), 0.4)
	materials.amber = _material(Color("e5a93c"), 0.42, 0.2, Color("ffbd48"), 0.1)
	materials.trunk = _material(Color("68472f"), 1.0)
	materials.leaf = _material(Color("317044"), 0.96)
	materials.sandbag = _material(Color("aa936d"), 1.0)
	materials.human_marker = _material(Color("2f82db"), 0.3, 0.16, Color("42b8f2"), 0.2)
	materials.alien_marker = _material(Color("d93662"), 0.34, 0.16, Color("f43b76"), 0.2)
	materials.ghost_valid = _transparent_material(Color(0.20, 0.82, 0.64, 0.34), Color("4fe0b0"))
	materials.ghost_invalid = _transparent_material(Color(0.92, 0.18, 0.24, 0.4), Color("f4415a"))
	materials.hover = _transparent_material(Color(0.95, 0.76, 0.30, 0.24), Color("f0be4a"))
	materials.sand = _material(Color("c5a567"), 0.98)
	materials.river_bank = _material(Color("776040"), 1.0)
	materials.territory_human = _transparent_material(Color(0.10, 0.36, 0.78, 0.13), Color("2f82db"))
	materials.territory_alien = _transparent_material(Color(0.68, 0.08, 0.22, 0.13), Color("d93662"))
	materials.dust = _transparent_material(Color(0.48, 0.36, 0.22, 0.28), Color("6d5435"))
	materials.snow = _material(Color("c8c7bd"), 0.90)
	materials.foam = _transparent_material(Color(0.82, 0.94, 0.91, 0.48), Color("d7f2ec"))
	materials.human_district = _district_material(load("res://assets/cities/human_district_foundation_v6.png"))
	materials.alien_district = _district_material(load("res://assets/cities/alien_district_foundation_v6.png"))
	var grid_material := StandardMaterial3D.new()
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.12, 0.16, 0.12, 0.20)
	grid_material.no_depth_test = false
	materials.grid = grid_material

	var painterly_textures := {
		"grass": load("res://assets/terrain/painterly/grass_lush_v3.png"),
		"grass_light": load("res://assets/terrain/painterly/meadow_v3.png"),
		"plains": load("res://assets/terrain/painterly/plains_v3.png"),
		"rock": load("res://assets/terrain/painterly/highland_v3.png"),
	}
	for material_name in painterly_textures:
		var terrain_material := materials[material_name] as StandardMaterial3D
		terrain_material.albedo_texture = painterly_textures[material_name]
		terrain_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		terrain_material.uv1_triplanar = true
		terrain_material.uv1_world_triplanar = true
		terrain_material.uv1_scale = Vector3.ONE * 0.72


func _transparent_material(color: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 0.8
	return mat


func _water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec4 deep_color : source_color = vec4(0.025, 0.16, 0.24, 1.0);
uniform vec4 crest_color : source_color = vec4(0.10, 0.37, 0.45, 1.0);
void vertex() {
    VERTEX.y += sin(VERTEX.x * 3.7 + TIME * 0.72) * 0.018;
    VERTEX.y += cos(VERTEX.z * 4.9 - TIME * 0.55) * 0.012;
}
void fragment() {
    float ripple = sin((UV.x + UV.y) * 22.0 + TIME * 0.72) * 0.5 + 0.5;
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
    ALBEDO = mix(deep_color.rgb, crest_color.rgb, ripple * 0.10 + fresnel * 0.28);
    ROUGHNESS = 0.48;
    METALLIC = 0.0;
    EMISSION = crest_color.rgb * (0.008 + ripple * 0.006);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _material(
	color: Color,
	roughness: float,
	metallic := 0.0,
	emission := Color.BLACK,
	emission_energy := 0.0
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


func _district_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _setup_audio() -> void:
	var ambience := AudioStreamPlayer.new()
	ambience.name = "EarthfrontAmbience"
	ambience.stream = load("res://assets/audio/earthfront_ambient_v1.ogg")
	ambience.volume_db = -17.0
	ambience.finished.connect(ambience.play)
	add_child(ambience)
	ambience.play()


func _play_deploy_sound() -> void:
	var confirmation := AudioStreamPlayer.new()
	confirmation.stream = load("res://assets/audio/deploy_confirm_v1.wav")
	confirmation.volume_db = -7.0
	confirmation.finished.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.play()


func _setup_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("78acd0")
	sky_material.sky_horizon_color = Color("f1dfbd")
	sky_material.ground_bottom_color = Color("456f7d")
	sky_material.ground_horizon_color = Color("d8c59f")
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.12
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Only 35 percent of the ambient light comes from the sky; the rest is a cool flat colour, so the sun's cast
	# shadows keep a readable edge instead of being filled in to the same brightness as the lit ground.
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color("8fa3b8")
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 0.85
	env.glow_enabled = false
	env.glow_intensity = 0.22
	if _renderer_supports_ssao():
		env.ssao_enabled = true
		env.ssao_radius = 1.65
		env.ssao_intensity = 1.45
	world_environment.environment = env
	environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	# One warm sun in the north-west (north is -Z, west is -X) at 38 degrees elevation: its light travels toward
	# (+x, +z), so shadows fall toward the south-east, in front of the buildings for the default camera.
	sun.rotation_degrees = Vector3(-38.0, -135.0, 0.0)
	sun.light_color = Color("ffe8c8")
	sun.light_energy = 1.0
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38.0, 142.0, 0.0)
	fill.light_color = Color("9dcced")
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	add_child(fill)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.far = 160.0
	add_child(camera)


## SSAO needs the Forward+ or Mobile renderer and a real GPU; Compatibility, headless and CPU rasterisers skip it silently.
func _renderer_supports_ssao() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if String(RenderingServer.get_current_rendering_method()) == "gl_compatibility":
		return false
	return RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_CPU


func _build_terrain() -> void:
	var ocean := BoxMesh.new()
	ocean.size = Vector3(96.0, 0.22, 72.0)
	ocean_box = _mesh(ocean, materials.water, Vector3(16.0, -0.48, 9.0))

	var terrain_script := load("res://scripts/continuous_terrain.gd")
	terrain_renderer = terrain_script.new()
	terrain_renderer.name = "ContinuousTerrainRenderer"
	add_child(terrain_renderer)
	terrain_renderer.configure(
		MAP_W, MAP_H, MAP_ORIGIN_X, MAP_ORIGIN_Z, HEX_X, HEX_Z,
		load("res://assets/terrain/painterly/continuous_ground_detail_v4.png")
	)

	_build_terrain_dressing()
	var hover_mesh := TorusMesh.new()
	hover_mesh.inner_radius = 0.42
	hover_mesh.outer_radius = 0.47
	hover_mesh.rings = 24
	hover_mesh.ring_segments = 8
	hover_tile = _mesh(hover_mesh, materials.hover, Vector3.ZERO)
	hover_tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_tile.visible = false


## Everything standing on the terrain surface. Built once for the noise terrain and once more (replacing the first set)
## when the first snapshot with a ground layer arrives.
func _build_terrain_dressing() -> void:
	for node in terrain_dressing:
		if is_instance_valid(node):
			remove_child(node)
			node.free()
	terrain_dressing.clear()
	terrain_height.clear()
	var first_child := get_child_count()
	for x in range(MAP_W):
		for z in range(MAP_H):
			var world := _hex_world(x, z)
			var elevation: float = terrain_renderer.height_at_world(world.x, world.z)
			var biome_signal: float = terrain_renderer.biome_at_world(world.x, world.z)
			terrain_height[Vector2i(x, z)] = elevation
			if ground_model == null:
				_dress_tile(x, z, world, elevation, biome_signal)
			elif not world_art_on:
				_dress_ground_tile(x, z, world, elevation)
	if ground_model == null:
		_build_shoreline_details()
		_build_river()
		_build_strategic_routes()
	world_props = null
	if world_art_on:
		world_props = WorldProps.new()
		var keep := WorldProps.keep_out(ground_model, _ground_route)
		var items := WorldProps.plan(ground_model, _ground_deposits, Vector2(MAP_ORIGIN_X, MAP_ORIGIN_Z), Vector2(HEX_X, HEX_Z), int(WorldArt.CAMERA.edge_cells), keep)
		world_props.build(self, items, func(x: float, z: float) -> float: return terrain_renderer.height_at_world(x, z))
	_build_hex_grid()
	if ground_model == null:
		_place_scene(self, "res://assets/models/world/bridge.glb", Vector3(12.0, _height_world(12.0, 6.9) + 0.08, 6.9), Vector3.ONE * 0.62, 90.0)
	for index in range(first_child, get_child_count()):
		terrain_dressing.append(get_child(index))


## First snapshot with a ground layer: the terrain, its dressing and the map size follow the snapshot. Later snapshots
## carry the same layer and are ignored, so the mesh is rebuilt once, not per poll.
## First ground layer wins for the life of the process: the terrain and its dressing are built once, so a different ground
## sent after a bridge restart in the same process is ignored (a new map needs a new launch). A malformed layer is reported
## once and the cosmetic noise terrain stays.
func _sync_ground(snapshot: Dictionary) -> void:
	if ground_model != null or not snapshot.has("ground") or GroundModel.is_flat(snapshot):
		return
	var model: RefCounted = GroundModel.from_snapshot(snapshot)
	if model == null:
		if ground_warnings == 0:
			ground_warnings += 1
			push_warning("Bridge ground layer does not match its map dimensions")
		return
	ground_model = model
	MAP_W = int(model.width)
	MAP_H = int(model.height)
	terrain_renderer.apply_ground(model)
	world_art_on = WorldArt.active(model)
	if world_art_on:
		_apply_world_art(snapshot)
	_ground_deposits = snapshot.get("deposits", [])
	_ground_route = snapshot.get("wave_route", [])
	_build_terrain_dressing()


## Kestrel world-art profile (spec addendum W1 to W9). Runs once, when the first real ground layer arrives.
func _apply_world_art(_snapshot: Dictionary) -> void:
	camera_yaw = float(WorldArt.CAMERA.yaw)
	if environment != null:
		WorldArt.apply_environment(environment)
	if world_atmosphere == null:
		world_atmosphere = WorldArt.atmosphere_layer()
		add_child(world_atmosphere)
	if is_instance_valid(ocean_box):
		ocean_box.visible = false
	if not is_instance_valid(sea_backdrop):
		var plane := PlaneMesh.new()
		plane.size = Vector2(240.0, 240.0)
		var sea := StandardMaterial3D.new()
		sea.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # the colour of the terrain's open sea in the minimap, unlit
		sea.albedo_color = Color8(31, 68, 119)
		sea_backdrop = _mesh(plane, sea, Vector3(16.7, -0.95, 10.0))
		sea_backdrop.name = "SeaBackdrop"
		sea_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if is_instance_valid(hover_tile):
		hover_tile.mesh = _hover_outline_mesh(Vector3.ZERO)
		hover_tile.material_override = WorldArt.hover_material()


func _zoom_limits() -> Vector2:
	return Vector2(WorldArt.CAMERA.min_zoom, WorldArt.CAMERA.max_zoom) if world_art_on else Vector2(7.5, 24.0)


func _zoom_default() -> float:
	return float(WorldArt.CAMERA.default_zoom) if world_art_on else 8.8


func _dress_ground_tile(x: int, z: int, world: Vector3, elevation: float) -> void:
	var signature := absi((x * 73856093) ^ (z * 19349663))
	match String(ground_model.glyph_at(x, z)):
		"t":
			if signature % 2 == 0:
				_create_tree(world + Vector3(0, elevation, 0), 0.34 + float(signature % 3) * 0.04)
		"h":
			if signature % 13 == 0:
				_create_rocks(world + Vector3(0, elevation, 0), 0.24)


func _build_shoreline_details() -> void:
	for x in range(0, MAP_W, 2):
		for z in [0, MAP_H - 1]:
			var edge := _hex_world(x, z)
			edge.y = -0.34
			_create_foam_patch(edge, float((x * 17 + z) % 180))
	for z in range(1, MAP_H - 1, 2):
		for x in [0, MAP_W - 1]:
			var edge := _hex_world(x, z)
			edge.y = -0.34
			_create_foam_patch(edge, float((z * 19 + x) % 180))


func _create_foam_patch(position: Vector3, rotation_y: float) -> void:
	var foam := _sphere(self, Vector3(0.34, 0.025, 0.10), position, materials.foam)
	foam.rotation_degrees.y = rotation_y
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam.visibility_range_end = 27.0
	foam.add_to_group("shore_foam")


func _river_vertex(surface: SurfaceTool, position: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(position)


func _create_river_ribbon(points: Array[Vector3], width: float, material: Material, label: String, y_offset: float) -> void:
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for index in range(points.size()):
		var previous: Vector3 = points[maxi(0, index - 1)]
		var next: Vector3 = points[mini(points.size() - 1, index + 1)]
		var tangent := (next - previous).normalized()
		var perpendicular := Vector3(-tangent.z, 0, tangent.x).normalized()
		var center := points[index]
		center.y = _height_world(center.x, center.z) + y_offset
		left.append(center + perpendicular * width * 0.5)
		right.append(center - perpendicular * width * 0.5)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size() - 1):
		var v0 := float(index) / float(points.size() - 1)
		var v1 := float(index + 1) / float(points.size() - 1)
		_river_vertex(surface, left[index], Vector2(0, v0))
		_river_vertex(surface, right[index], Vector2(1, v0))
		_river_vertex(surface, right[index + 1], Vector2(1, v1))
		_river_vertex(surface, left[index], Vector2(0, v0))
		_river_vertex(surface, right[index + 1], Vector2(1, v1))
		_river_vertex(surface, left[index + 1], Vector2(0, v1))
	var ribbon := MeshInstance3D.new()
	ribbon.name = label
	ribbon.mesh = surface.commit()
	ribbon.material_override = material
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbon)


func _build_river() -> void:
	var points: Array[Vector3] = []
	for index in range(29):
		var z := 1.4 + float(index) * 0.61
		var x := 11.8 + sin(float(index) * 0.36) * 0.72
		points.append(Vector3(x, 0, z))
	_create_river_ribbon(points, 0.90, materials.river_bank, "AsterRiverBanks", 0.028)
	_create_river_ribbon(points, 0.58, materials.water, "AsterRiverWater", 0.052)
	for index in range(2, points.size() - 2, 4):
		var p := points[index]
		p.y = _height_world(p.x, p.z) + 0.03
		_create_rocks(p + Vector3(0.48 if index % 8 == 0 else -0.48, 0, 0), 0.24)


func _route_points(control_points: Array[Vector3], steps_per_leg := 7) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for leg in range(control_points.size() - 1):
		var a := control_points[leg]
		var b := control_points[leg + 1]
		for step in range(steps_per_leg):
			points.append(a.lerp(b, float(step) / float(steps_per_leg)))
	points.append(control_points.back())
	return points


func _create_ground_route(control_points: Array[Vector3], alien := false) -> void:
	var points := _route_points(control_points)
	_create_river_ribbon(points, 0.48, materials.road_edge, "StrategicRouteEdge", 0.036)
	_create_river_ribbon(points, 0.34, materials.alien_dark if alien else materials.road, "StrategicRoute", 0.052)
	for index in range(4, points.size() - 3, 7):
		var marker := points[index]
		marker.y = _height_world(marker.x, marker.z) + 0.075
		var inset := _box(self, Vector3(0.08, 0.018, 0.24), marker, materials.plasma if alien else materials.amber)
		var direction: Vector3 = points[index + 1] - points[index - 1]
		inset.rotation.y = atan2(direction.x, direction.z)
		inset.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_strategic_routes() -> void:
	_create_ground_route([
		Vector3(6.2, 0, 9.4), Vector3(8.0, 0, 8.4), Vector3(9.9, 0, 7.4), Vector3(11.65, 0, 6.9)
	])
	_create_ground_route([
		Vector3(12.35, 0, 6.9), Vector3(14.7, 0, 7.35), Vector3(17.1, 0, 8.25), Vector3(19.0, 0, 8.8)
	])
	_create_ground_route([
		Vector3(29.3, 0, 10.1), Vector3(26.8, 0, 9.55), Vector3(24.2, 0, 9.3), Vector3(21.5, 0, 9.0)
	], true)


func _build_hex_grid() -> void:
	var grid_surface := SurfaceTool.new()
	grid_surface.begin(Mesh.PRIMITIVE_LINES)
	for x in range(MAP_W):
		for z in range(MAP_H):
			var center := _hex_world(x, z)
			for edge in range(6):
				var angle_a := TAU * float(edge) / 6.0
				var angle_b := TAU * float(edge + 1) / 6.0
				var a := center + Vector3(cos(angle_a) * 0.44, 0, sin(angle_a) * 0.405)
				var b := center + Vector3(cos(angle_b) * 0.44, 0, sin(angle_b) * 0.405)
				a.y = _height_world(a.x, a.z) + 0.038
				b.y = _height_world(b.x, b.z) + 0.038
				grid_surface.add_vertex(a)
				grid_surface.add_vertex(b)
	var grid := MeshInstance3D.new()
	grid.name = "TerrainHexLattice"
	grid.mesh = grid_surface.commit()
	grid.material_override = materials.grid
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.visibility_range_end = 27.0
	grid.visible = false
	add_child(grid)


func _build_territory_readability() -> void:
	for spec in [[Vector3(6.2, 0, 9.4), HUMAN], [Vector3(29.3, 0, 10.1), ALIEN]]:
		var center: Vector3 = spec[0]
		var team := int(spec[1])
		var border_material: Material = materials.territory_human if team == HUMAN else materials.territory_alien
		for segment in range(32):
			if segment % 4 == 3:
				continue
			var angle_a := TAU * float(segment) / 32.0
			var angle_b := TAU * float(segment + 1) / 32.0
			var radius := 3.72 + sin(float(segment) * 1.73) * 0.12
			var a := center + Vector3(cos(angle_a) * radius, 0, sin(angle_a) * radius)
			var b := center + Vector3(cos(angle_b) * radius, 0, sin(angle_b) * radius)
			a.y = _height_world(a.x, a.z) + 0.052
			b.y = _height_world(b.x, b.z) + 0.052
			var border := _beam(self, a, b, 0.065, border_material, 0.025)
			border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _create_map_label(text: String, position: Vector3, color: Color, size := 36) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(position.x, _height_world(position.x, position.z) + 0.46, position.z)
	label.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	label.font_size = size
	label.pixel_size = 0.008
	label.modulate = color
	label.outline_modulate = Color(0.055, 0.085, 0.09, 0.82)
	label.outline_size = 9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.visibility_range_begin = 8.0
	label.visibility_range_end = 44.0
	add_child(label)


func _build_world_landmarks() -> void:
	_create_map_label("ASTER RIVER", Vector3(12.0, 0, 14.2), Color("c7e1dc"), 31)
	_create_map_label("VERDANT BASIN", Vector3(18.1, 0, 3.3), Color("e7d9aa"), 32)
	_create_map_label("CROWN HIGHLANDS", Vector3(22.8, 0, 15.3), Color("ddd7c4"), 30)
	_create_map_label("THE FIRST FRONT", Vector3(17.0, 0, 10.8), Color("e0bb72"), 34)


func _create_human_farmstead(position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "EarthfrontFarmstead"
	root.position = Vector3(position.x, _height_world(position.x, position.z), position.z)
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_place_scene(root, "res://assets/models/human/windmill.glb", Vector3(-0.62, 0.02, -0.18), Vector3.ONE * 0.42, 0.0)
	_place_scene(root, "res://assets/models/human/water-tower.glb", Vector3(0.58, 0.01, 0.28), Vector3.ONE * 0.38, 25.0)
	for row in range(5):
		_box(root, Vector3(1.55, 0.035, 0.075), Vector3(0, 0.035, -0.70 + float(row) * 0.22), materials.farm)
	for post_index in range(6):
		var px := -0.82 + float(post_index) * 0.33
		_cylinder(root, 0.018, 0.20, Vector3(px, 0.10, 0.62), materials.trunk, 6)


func _create_alien_outgrowth(position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.name = "CoreNodeOutgrowth"
	root.position = Vector3(position.x, _height_world(position.x, position.z), position.z)
	root.rotation_degrees.y = rotation_y
	add_child(root)
	var pad := _cylinder(root, 0.76, 0.07, Vector3(0, 0.035, 0), materials.alien_dark, 6)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_place_scene(root, "res://assets/models/alien/corridor-junction.glb", Vector3.ZERO, Vector3.ONE * 0.40, 0.0)
	for node_index in range(5):
		var angle := TAU * float(node_index) / 5.0
		var p := Vector3(cos(angle) * 0.56, 0.25, sin(angle) * 0.56)
		var crystal := _cylinder(root, 0.045, 0.42 + float(node_index % 2) * 0.15, p, materials.plasma, 6)
		crystal.rotation_degrees.z = cos(angle) * 13.0


func _create_frontier_outpost(position: Vector3) -> void:
	var root := Node3D.new()
	root.name = "FirstFrontOutpost"
	root.position = Vector3(position.x, _height_world(position.x, position.z), position.z)
	add_child(root)
	var pad := _cylinder(root, 0.82, 0.06, Vector3(0, 0.03, 0), materials.earth, 14)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_box(root, Vector3(0.82, 0.26, 0.48), Vector3(0, 0.16, 0), materials.concrete)
	for barrier_index in range(5):
		var angle := -0.9 + float(barrier_index) * 0.45
		var barrier := _box(root, Vector3(0.32, 0.13, 0.12), Vector3(cos(angle) * 0.72, 0.07, sin(angle) * 0.72), materials.sandbag)
		barrier.rotation_degrees.y = -rad_to_deg(angle)
	_create_floodlight(position + Vector3(0.72, 0, -0.55), materials.amber)


func _build_regional_improvements() -> void:
	_create_human_farmstead(Vector3(4.5, 0, 14.1), -18.0)
	_create_human_farmstead(Vector3(8.8, 0, 13.5), 26.0)
	_create_frontier_outpost(Vector3(17.4, 0, 12.1))
	_create_alien_outgrowth(Vector3(25.0, 0, 14.0), 18.0)
	_create_alien_outgrowth(Vector3(27.1, 0, 5.6), -24.0)


func _terrain_material(noise_value: float, x: int, z: int) -> Material:
	if x < 2 or z < 2 or x > MAP_W - 3 or z > MAP_H - 3:
		return materials.sand
	if float(terrain_height.get(Vector2i(x, z), 0.0)) > 0.5:
		return materials.rock
	if noise_value < -0.20:
		return materials.plains
	if noise_value > 0.22:
		return materials.grass_light
	return materials.grass


func _dress_tile(x: int, z: int, world: Vector3, elevation: float, noise_value: float) -> void:
	# Sparse, three-dimensional cover; leave the deployment area readable.
	if (x < 7 and z > 8 and z < 19) or (x > 29 and z > 5 and z < 22):
		return
	var signature := absi((x * 73856093) ^ (z * 19349663))
	if noise_value < -0.10 and signature % 9 == 0:
		_create_tree(world + Vector3(0, elevation, 0), 0.34 + float(signature % 3) * 0.04)
	elif elevation > 0.5 and signature % 17 == 0:
		_create_rocks(world + Vector3(0, elevation, 0), 0.24)


func _district_vertex(surface: SurfaceTool, position: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(Vector3(position.x, _height_world(position.x, position.z) + 0.042, position.z))


func _create_district_foundation(center: Vector3, team: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions := 12
	var diameter := 7.4
	for x_index in range(divisions):
		for z_index in range(divisions):
			var u0 := float(x_index) / float(divisions)
			var u1 := float(x_index + 1) / float(divisions)
			var v0 := float(z_index) / float(divisions)
			var v1 := float(z_index + 1) / float(divisions)
			var p00 := center + Vector3((u0 - 0.5) * diameter, 0, (v0 - 0.5) * diameter)
			var p10 := center + Vector3((u1 - 0.5) * diameter, 0, (v0 - 0.5) * diameter)
			var p11 := center + Vector3((u1 - 0.5) * diameter, 0, (v1 - 0.5) * diameter)
			var p01 := center + Vector3((u0 - 0.5) * diameter, 0, (v1 - 0.5) * diameter)
			_district_vertex(surface, p00, Vector2(u0, v0))
			_district_vertex(surface, p10, Vector2(u1, v0))
			_district_vertex(surface, p11, Vector2(u1, v1))
			_district_vertex(surface, p00, Vector2(u0, v0))
			_district_vertex(surface, p11, Vector2(u1, v1))
			_district_vertex(surface, p01, Vector2(u0, v1))
	var foundation := MeshInstance3D.new()
	foundation.name = "EarthfrontDistrict" if team == HUMAN else "CoreNodeDistrict"
	foundation.mesh = surface.commit()
	foundation.material_override = materials.human_district if team == HUMAN else materials.alien_district
	foundation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foundation)


func _create_city_dressing(center: Vector3, team: int) -> void:
	var faction_material: Material = materials.territory_human if team == HUMAN else materials.territory_alien
	var dark_material: Material = materials.human_dark if team == HUMAN else materials.alien_dark
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.78
	ring_mesh.outer_radius = 2.84
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 7
	var district_ring := _mesh(ring_mesh, faction_material, center + Vector3.UP * 0.028)
	district_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for segment in range(12):
		if segment % 3 == 0:
			continue
		var angle := TAU * float(segment) / 12.0
		var p := center + Vector3(cos(angle) * 3.25, 0, sin(angle) * 3.25)
		p.y = _height_world(p.x, p.z)
		var post := _box(self, Vector3(0.42, 0.32, 0.16), p + Vector3.UP * 0.16, dark_material)
		post.rotation_degrees.y = -rad_to_deg(angle)
	for activity_index in range(4):
		var activity := Node3D.new()
		activity.set_meta("team", team)
		activity.set_meta("phase", float(activity_index) * TAU / 4.0)
		activity.add_to_group("city_activity")
		add_child(activity)
		activity.position = center
		var light_material: Material = materials.glass if team == HUMAN else materials.plasma
		_box(activity, Vector3(0.22, 0.08, 0.12), Vector3(2.1, 0.12, 0), light_material)
	var radar := Node3D.new()
	radar.position = center + Vector3(2.35, 0.0, 2.15)
	radar.position.y = _height_world(radar.position.x, radar.position.z)
	radar.add_to_group("radar")
	add_child(radar)
	_cylinder(radar, 0.045, 0.9, Vector3(0, 0.45, 0), dark_material, 10)
	var dish := _box(radar, Vector3(0.62, 0.05, 0.13), Vector3(0, 0.91, 0), materials.glass if team == HUMAN else materials.plasma)
	dish.rotation_degrees.z = -18.0


func _create_shrub(pos: Vector3, signature: int) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = float(signature % 360)
	add_child(root)
	for leaf_index in range(4):
		var angle := TAU * float(leaf_index) / 4.0
		var leaf := _sphere(root, Vector3(0.16, 0.09, 0.11), Vector3(cos(angle) * 0.10, 0.10, sin(angle) * 0.10), materials.leaf)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.visibility_range_end = 24.0
	if signature % 2 == 0:
		var bloom := _sphere(root, Vector3.ONE * 0.045, Vector3(0, 0.21, 0), materials.amber)
		bloom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_human_city(origin: Vector3) -> void:
	var y := _height_world(origin.x, origin.z)
	var center := Vector3(origin.x, y, origin.z)
	_create_district_foundation(center, HUMAN)
	_create_city_dressing(center, HUMAN)
	_create_city_road(center + Vector3(-2.4, 0.035, 0.0), center + Vector3(3.0, 0.035, 0.0))
	_create_city_road(center + Vector3(0.0, 0.035, -2.5), center + Vector3(0.0, 0.035, 2.5))
	_create_human_command(center)
	_create_human_building(center + Vector3(-1.65, 0.0, -1.25), Vector3(1.3, 0.85, 1.0), true)
	_create_human_building(center + Vector3(1.55, 0.0, -1.2), Vector3(1.15, 1.35, 1.0), false)
	_create_human_building(center + Vector3(-1.65, 0.0, 1.35), Vector3(1.4, 0.72, 1.05), false)
	_create_human_building(center + Vector3(1.55, 0.0, 1.3), Vector3(1.15, 0.95, 1.15), true)
	_create_farms(center + Vector3(-3.0, 0.0, 1.7), false)
	_create_farms(center + Vector3(-3.0, 0.0, -1.1), true)
	_create_floodlight(center + Vector3(2.65, 0.0, -2.0), materials.glass)
	_place_scene(self, "res://assets/models/authored/human_industry.glb", center + Vector3(-3.0, 0.02, -2.3), Vector3.ONE * 0.50, 20.0)


func _build_alien_city(origin: Vector3) -> void:
	var y := _height_world(origin.x, origin.z)
	var center := Vector3(origin.x, y, origin.z)
	_create_district_foundation(center, ALIEN)
	_create_city_dressing(center, ALIEN)
	_create_city_road(center + Vector3(-2.6, 0.03, 0.0), center + Vector3(2.7, 0.03, 0.0), true)
	_create_alien_core(center)
	for offset in [Vector3(-1.8, 0, -1.35), Vector3(1.75, 0, -1.25), Vector3(-1.7, 0, 1.35), Vector3(1.65, 0, 1.4)]:
		_create_alien_spire(center + offset, 0.85 + abs(offset.x) * 0.18)
	_create_floodlight(center + Vector3(-2.6, 0, 2.0), materials.plasma)


func _create_human_command(pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Earth_Command_Nexus"
	add_child(root)
	root.position = pos
	_place_scene(root, "res://assets/models/authored/human_hq.glb", Vector3.ZERO, Vector3.ONE * 0.78, 180.0)
	_add_city_nameplate(root, "EARTHFRONT", Color("244d78"))


func _create_human_building(pos: Vector3, size: Vector3, industrial: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, _height_world(pos.x, pos.z), pos.z)
	var signature: int = absi(int(pos.x * 19.0 + pos.z * 31.0))
	var asset_name := "human_industry.glb" if industrial else "human_barracks.glb"
	var model_scale := 0.58 + size.y * 0.05
	_place_scene(root, "res://assets/models/authored/" + asset_name, Vector3.ZERO, Vector3.ONE * model_scale, float(signature % 4) * 90.0)


func _create_alien_core(pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Alien_Core"
	add_child(root)
	root.position = pos
	_place_scene(root, "res://assets/models/authored/alien_core.glb", Vector3.ZERO, Vector3.ONE * 0.82, 45.0)
	_add_city_nameplate(root, "CORE NODE", Color("6b203d"))


func _add_city_nameplate(root: Node3D, city_name: String, outline: Color) -> void:
	var plaque_mesh := QuadMesh.new()
	plaque_mesh.size = Vector2(2.25, 0.46)
	var plaque_material := StandardMaterial3D.new()
	plaque_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plaque_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plaque_material.albedo_color = Color(outline.r, outline.g, outline.b, 0.92)
	plaque_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var plaque := _mesh(plaque_mesh, plaque_material, Vector3(0, 1.88, 0), root)
	plaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plate := Label3D.new()
	plate.text = city_name
	plate.position = Vector3(0, 1.88, 0.012)
	plate.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	plate.font_size = 42
	plate.pixel_size = 0.008
	plate.modulate = Color("f4e7c4")
	plate.outline_modulate = outline
	plate.outline_size = 13
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(plate)


func _create_alien_spire(pos: Vector3, height: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, _height_world(pos.x, pos.z), pos.z)
	_place_scene(root, "res://assets/models/authored/alien_spire.glb", Vector3.ZERO, Vector3.ONE * (0.68 + height * 0.05), float(int(pos.x * 37.0) % 4) * 90.0)


func _create_farms(pos: Vector3, rotated: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, _height_world(pos.x, pos.z) + 0.035, pos.z)
	root.rotation_degrees.y = 90.0 if rotated else 0.0
	_box(root, Vector3(1.75, 0.06, 1.35), Vector3.ZERO, materials.earth)
	for row in range(6):
		_box(root, Vector3(1.55, 0.055, 0.09), Vector3(0, 0.06, -0.53 + row * 0.21), materials.farm)


func _create_city_road(a: Vector3, b: Vector3, alien := false) -> void:
	_beam(self, a, b, 0.82, materials.road_edge, 0.07)
	_beam(self, a + Vector3.UP * 0.04, b + Vector3.UP * 0.04, 0.62, materials.alien_dark if alien else materials.road, 0.075)


func _create_tree(pos: Vector3, scale_factor: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.add_to_group("scenery")
	var signature := absi(int(pos.x * 17.0 + pos.z * 13.0))
	_place_scene(root, "res://assets/models/authored/world_tree.glb", Vector3.ZERO, Vector3.ONE * scale_factor, float(signature % 360))


func _create_mountain(pos: Vector3, scale_factor: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = float(abs(int(pos.x * 31.0 + pos.z * 17.0)) % 360)
	add_child(root)
	for peak_index in range(3):
		var peak_mesh := CylinderMesh.new()
		peak_mesh.top_radius = 0.03
		peak_mesh.bottom_radius = 0.62 - float(peak_index) * 0.08
		peak_mesh.height = 1.55 - float(peak_index) * 0.18
		peak_mesh.radial_segments = 7
		var offset := Vector3(-0.42 + float(peak_index) * 0.40, 0.72 - float(peak_index) * 0.08, float((peak_index % 2) * 2 - 1) * 0.12)
		var peak := _mesh(peak_mesh, materials.rock, offset, root)
		peak.scale = Vector3.ONE * scale_factor
		peak.visibility_range_end = 42.0
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.02
		cap_mesh.bottom_radius = 0.15
		cap_mesh.height = 0.22
		cap_mesh.radial_segments = 7
		var cap := _mesh(cap_mesh, materials.snow, offset + Vector3.UP * (0.68 * scale_factor), root)
		cap.scale = Vector3.ONE * scale_factor
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _create_rocks(pos: Vector3, scale_factor: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	_place_scene(root, "res://assets/models/authored/world_rock.glb", Vector3.ZERO, Vector3.ONE * scale_factor, float(abs(int(pos.x * 29.0 + pos.z * 11.0)) % 360))


func _create_ruin(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = float((int(pos.x * 11.0) + int(pos.z * 17.0)) % 90)
	_box(root, Vector3(0.9, 0.18, 0.22), Vector3(0, 0.09, 0), materials.concrete)
	_box(root, Vector3(0.18, 0.38, 0.75), Vector3(-0.32, 0.19, 0.18), materials.concrete)


func _create_floodlight(pos: Vector3, light_material: Material) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, _height_world(pos.x, pos.z), pos.z)
	_cylinder(root, 0.05, 1.45, Vector3(0, 0.72, 0), materials.human_dark)
	_box(root, Vector3(0.4, 0.24, 0.12), Vector3(0, 1.42, 0), light_material)


func _build_armies() -> void:
	for i in range(7):
		var lane := float(i % 4) * 0.55
		var row := float(i / 4) * 0.72
		var human_pos := Vector3(7.0 - row, _height_world(7.0 - row, 6.6 + lane), 6.6 + lane)
		var alien_pos := Vector3(17.2 + row, _height_world(17.2 + row, 8.0 + lane), 8.0 + lane)
		_create_unit(HUMAN, human_pos, i % 3)
		_create_unit(ALIEN, alien_pos, i % 3)


func _create_unit(team: int, pos: Vector3, kind: int) -> void:
	var root := Node3D.new()
	root.name = ("Human" if team == HUMAN else "Alien") + "_Unit_%02d" % units.size()
	add_child(root)
	root.position = pos + Vector3.UP * 0.08
	root.set_meta("team", team)
	var max_hp: float = 240.0 if kind == 0 else 380.0
	root.set_meta("hp", max_hp)
	root.set_meta("max_hp", max_hp)
	root.set_meta("shield", 0.0)
	root.set_meta("max_shield", 0.0)
	root.set_meta("cooldown", 0.3 + float(units.size() % 5) * 0.08)
	root.set_meta("kind", kind)
	root.set_meta("manual_target", Vector3.INF)
	root.set_meta("speed", 0.62 if kind == 0 else 0.48)
	root.set_meta("current_speed", 0.0)
	root.set_meta("last_dust", 0.0)
	var formation_angle := TAU * float(units.size() % 7) / 7.0
	root.set_meta("formation_offset", Vector3(cos(formation_angle), 0, sin(formation_angle)) * (0.34 + float(units.size() % 3) * 0.12))
	if team == HUMAN:
		_create_human_unit_model(root, kind)
	else:
		_create_alien_unit_model(root, kind)
	var bar_y: Array = [0.88, 0.885, 0.955, 0.958]  # health back, fill, shield back, fill
	if world_art_on:
		# spec addendum W6: every unit model (the box-built squads included, they build UnitVisual too) fits its width
		var tiles := float(WorldArt.UNIT_TILES[clampi(kind, 0, WorldArt.UNIT_TILES.size() - 1)])
		var visual := root.get_node_or_null("UnitVisual") as Node3D
		if visual != null:
			var fit := _fitted(visual, "unit:%d:%d:%s" % [team, kind, tiles], tiles)
			visual.scale = Vector3.ONE * fit.x
			bar_y = [fit.y + 0.12, fit.y + 0.125, fit.y + 0.195, fit.y + 0.198]
		root.set_meta("visual_tiles", tiles)
	_add_unit_badge(root, team, kind)
	var team_material: Material = materials.human_marker if team == HUMAN else materials.alien_marker
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.15 if kind == 0 else 0.26
	marker_mesh.outer_radius = 0.17 if kind == 0 else 0.28
	marker_mesh.rings = 20
	marker_mesh.ring_segments = 7
	var marker := _mesh(marker_mesh, team_material, Vector3(0, 0.022, 0), root)
	marker.name = "TeamMarker"
	marker.visible = true
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var health_back := _box(root, Vector3(0.62, 0.035, 0.055), Vector3(0, bar_y[0], 0), materials.alien_dark)
	health_back.name = "HealthBack"
	health_back.visible = false
	var health_fill := _box(root, Vector3(0.56, 0.045, 0.065), Vector3(0, bar_y[1], 0), materials.glass if team == HUMAN else materials.alien)
	health_fill.name = "HealthFill"
	health_fill.visible = false
	var shield_back := _box(root, Vector3(0.62, 0.028, 0.045), Vector3(0, bar_y[2], 0), materials.alien_dark)
	shield_back.name = "ShieldBack"
	shield_back.visible = false
	var shield_fill := _box(root, Vector3(0.56, 0.036, 0.055), Vector3(0, bar_y[3], 0), materials.plasma)
	shield_fill.name = "ShieldFill"
	shield_fill.visible = false
	units.append(root)


func _add_unit_badge(root: Node3D, team: int, kind: int) -> void:
	var badge := Node3D.new()
	badge.name = "StrategicBadge"
	badge.position = Vector3(0, 0.48, 0)
	root.add_child(badge)
	var badge_mesh := QuadMesh.new()
	badge_mesh.size = Vector2(0.22, 0.13)
	var badge_material := StandardMaterial3D.new()
	badge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	badge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	badge_material.albedo_color = Color(0.08, 0.30, 0.56, 0.92) if team == HUMAN else Color(0.52, 0.08, 0.20, 0.92)
	badge_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var backing := _mesh(badge_mesh, badge_material, Vector3.ZERO, badge)
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var symbol := Label3D.new()
	var symbols := ["I", "AR", "AT", "AIR", "CAP", "HAR"]
	symbol.text = symbols[clampi(kind, 0, symbols.size() - 1)]
	symbol.position = Vector3(0, 0, 0.018)
	symbol.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	symbol.font_size = 30
	symbol.pixel_size = 0.0035
	symbol.modulate = Color("f6e7bd")
	symbol.outline_modulate = Color("102033")
	symbol.outline_size = 3
	symbol.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.add_child(symbol)


func _create_human_unit_model(root: Node3D, kind: int) -> void:
	if kind == 0 or kind == 2:
		tactical_models.infantry(self, root, kind == 2)
		return
	var paths: Array[String] = [
		"res://assets/models/authored/human_infantry.glb",
		"res://assets/models/authored/human_tank.glb",
		"res://assets/models/authored/human_anti_armor.glb",
		"res://assets/models/authored/human_gunship.glb",
		"res://assets/models/authored/human_capital.glb",
		"res://assets/models/authored/human_harvester.glb",
	]
	var scales := [0.72, 0.70, 0.72, 0.76, 0.64, 0.70]
	var model_kind := clampi(kind, 0, paths.size() - 1)
	var visual := _place_scene(root, paths[model_kind], Vector3.ZERO, Vector3.ONE * scales[model_kind], 0.0)
	visual.name = "UnitVisual"


func _create_alien_unit_model(root: Node3D, kind: int) -> void:
	var paths: Array[String] = [
		"res://assets/models/authored/alien_drone.glb",
		"res://assets/models/authored/alien_walker.glb",
		"res://assets/models/authored/alien_anti_armor.glb",
		"res://assets/models/authored/alien_gunship.glb",
		"res://assets/models/authored/alien_capital.glb",
		"res://assets/models/authored/alien_harvester.glb",
	]
	var scales := [0.72, 0.74, 0.76, 0.76, 0.64, 0.70]
	var model_kind := clampi(kind, 0, paths.size() - 1)
	var visual := _place_scene(root, paths[model_kind], Vector3.ZERO, Vector3.ONE * scales[model_kind], 180.0)
	visual.name = "UnitVisual"


func _process(delta: float) -> void:
	time_alive += delta
	var terrain_grid := get_node_or_null("TerrainHexLattice") as MeshInstance3D
	if terrain_grid:
		terrain_grid.visible = build_mode != ""
	camera_shake = maxf(0.0, camera_shake - delta * 2.8)
	alert_cooldown = maxf(0.0, alert_cooldown - delta)
	_poll_bridge(delta)
	_update_tutorial()
	_update_hover_tile()
	_update_build_ghost()
	if not ui.world_blocked():
		_update_camera_controls(delta)  # a paused game (or the strategic map) does not pan or orbit under the screen
	_update_units(delta)
	_glide_bridge_nodes(delta)
	_animate_world(delta)
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var hp_ratio := float(unit.get_meta("hp")) / maxf(1.0, float(unit.get_meta("max_hp")))
		var max_shield := float(unit.get_meta("max_shield", 0.0))
		var shield_ratio := float(unit.get_meta("shield", 0.0)) / maxf(1.0, max_shield)
		var show_status := unit in selected_units or hp_ratio < 0.995
		var show_shield := max_shield > 0.0 and (unit in selected_units or shield_ratio < 0.995)
		var marker := unit.get_node_or_null("TeamMarker") as MeshInstance3D
		if marker:
			marker.visible = true
			var marker_scale := 1.18 if unit in selected_units else 0.76
			marker.scale = Vector3.ONE * marker_scale
		var health_back := unit.get_node_or_null("HealthBack") as MeshInstance3D
		var health_fill := unit.get_node_or_null("HealthFill") as MeshInstance3D
		var shield_back := unit.get_node_or_null("ShieldBack") as MeshInstance3D
		var shield_fill := unit.get_node_or_null("ShieldFill") as MeshInstance3D
		if health_back:
			health_back.visible = show_status
		if health_fill:
			health_fill.visible = show_status
		if shield_back:
			shield_back.visible = show_shield
		if shield_fill:
			shield_fill.visible = show_shield
	if is_instance_valid(selected) and String(selected.get_meta("category", "unit")) == "building":
		for status_name in ["HealthBack", "HealthFill"]:
			var status_bar := selected.get_node_or_null(status_name) as MeshInstance3D
			if status_bar:
				status_bar.visible = true
		var selected_max_shield := float(selected.get_meta("max_shield", 0.0))
		for status_name in ["ShieldBack", "ShieldFill"]:
			var status_bar := selected.get_node_or_null(status_name) as MeshInstance3D
			if status_bar:
				status_bar.visible = selected_max_shield > 0.0
	if is_instance_valid(selection_ring) and is_instance_valid(selected):
		selection_ring.global_position = selected.global_position + Vector3.UP * 0.035
		selection_ring.rotation_degrees.y += delta * 24.0
	if is_instance_valid(range_ring) and is_instance_valid(selected) and range_ring.visible:
		range_ring.global_position = selected.global_position + Vector3.UP * 0.045
	if mission_deployed and not battle_started and time_alive > 1.5:
		battle_started = true
	ui.process(delta)


## Every frame: each bridge entity closes GLIDE_RATE of its gap to the last polled position (and turns toward its heading
## at TURN_RATE), so motion is as smooth as the frame rate while the snapshot is read only every BRIDGE_POLL seconds.
func _glide_bridge_nodes(delta: float) -> void:
	var move := 1.0 - exp(-delta * GLIDE_RATE)
	var turn := 1.0 - exp(-delta * TURN_RATE)
	for node in bridge_nodes.values():
		if not is_instance_valid(node) or not node.has_meta("glide_to"):
			continue
		var goal: Vector3 = node.get_meta("glide_to")
		if node.position.distance_squared_to(goal) > 0.000001:
			node.position = node.position.lerp(goal, move)
		if node.has_meta("glide_yaw"):
			node.rotation.y = lerp_angle(node.rotation.y, float(node.get_meta("glide_yaw")), turn)


func _animate_world(delta: float) -> void:
	for tree in get_tree().get_nodes_in_group("wind"):
		if is_instance_valid(tree):
			tree.rotation.z = sin(time_alive * 0.72 + float(tree.get_instance_id() % 17)) * 0.018
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var visual := unit.get_node_or_null("UnitVisual") as Node3D
		if visual:
			visual.position.y = sin(time_alive * 2.0) * 0.018 if int(unit.get_meta("kind", 0)) == 3 else 0.0
			visual.rotation.z = 0.0
			var turret := visual.find_child("Turret", true, false) as Node3D
			if turret:
				turret.rotation.y = 0.0
	for standard in get_tree().get_nodes_in_group("standards"):
		if is_instance_valid(standard):
			standard.rotation.y = sin(time_alive * 1.35 + float(standard.get_instance_id() % 7)) * 0.055
	for radar in get_tree().get_nodes_in_group("radar"):
		if is_instance_valid(radar):
			radar.rotate_y(delta * 0.35)
	for foam in get_tree().get_nodes_in_group("shore_foam"):
		if is_instance_valid(foam):
			foam.scale.x = 1.0 + sin(time_alive * 0.85 + float(foam.get_instance_id() % 11)) * 0.12
	for activity in get_tree().get_nodes_in_group("city_activity"):
		if is_instance_valid(activity):
			var phase := float(activity.get_meta("phase", 0.0)) + time_alive * (0.16 if int(activity.get_meta("team", HUMAN)) == HUMAN else -0.13)
			var vehicle := activity.get_child(0) as Node3D
			if vehicle:
				vehicle.position = Vector3(cos(phase) * 2.1, 0.12, sin(phase) * 2.1)
				vehicle.rotation.y = -phase
	for deposit in get_tree().get_nodes_in_group("resource_deposits"):
		if is_instance_valid(deposit):
			var halo := deposit.get_node_or_null("ResourceHalo") as Node3D
			if halo:
				var phase := time_alive * 1.4 + float(deposit.get_meta("phase", 0.0))
				halo.rotation.y = phase
				halo.scale = Vector3.ONE * (1.0 + sin(phase) * 0.07)


func _update_camera_controls(delta: float) -> void:
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var forward := Vector3(-right.z, 0, right.x)
	var motion := Vector3.ZERO
	motion += right * Input.get_axis("camera_left", "camera_right")
	motion += forward * Input.get_axis("camera_up", "camera_down")
	if mission_deployed:
		var pointer := mouse_position()
		var viewport_size := get_viewport().get_visible_rect().size
		if pointer.x < 10.0:
			motion -= right
		elif pointer.x > viewport_size.x - 10.0:
			motion += right
		if pointer.y < 10.0:
			motion -= forward
		elif pointer.y > viewport_size.y - 10.0:
			motion += forward
	_camera_step(delta, motion, get_viewport().get_visible_rect().size.aspect(), Input.get_axis("camera_rotate_left", "camera_rotate_right"))
	_update_camera()


## One frame of camera state (no scene access beyond fields, so tests can drive it). Kestrel keeps the focus target clamped
## only for the tightest zoom, so zooming out never drags it inward; the shown view is clamped per frame for the zoom the
## camera really has (camera_view_target). Yaw is locked north-up on Kestrel (the mock is north-up, shadows assume it).
func _camera_step(delta: float, motion: Vector3, aspect: float, rotate_axis: float) -> void:
	camera_aspect = aspect
	if motion.length() > 0.0:
		camera_focus_target += motion.normalized() * delta * camera_focus_zoom * 0.48
	camera_target = camera_target.lerp(camera_focus_target, 1.0 - exp(-delta * 7.5))
	camera_zoom = lerpf(camera_zoom, camera_focus_zoom, 1.0 - exp(-delta * 8.5))
	camera_cinematic = maxf(0.0, camera_cinematic - delta)
	if world_art_on:
		camera_yaw = float(WorldArt.CAMERA.yaw)
		camera_focus_target = WorldArt.clamp_focus(camera_focus_target, _zoom_limits().x, aspect, camera_yaw, _art_bounds())
	else:
		camera_yaw += rotate_axis * delta * 0.72
		camera_focus_target.x = clampf(camera_focus_target.x, MAP_ORIGIN_X, MAP_ORIGIN_X + float(MAP_W - 1) * HEX_X)
		camera_focus_target.z = clampf(camera_focus_target.z, MAP_ORIGIN_Z, MAP_ORIGIN_Z + float(MAP_H - 1) * HEX_Z)


func _art_bounds() -> Rect2:
	return WorldArt.world_bounds(MAP_W, MAP_H, MAP_ORIGIN_X, MAP_ORIGIN_Z, HEX_X, HEX_Z, int(WorldArt.CAMERA.edge_cells))


## The point the camera looks at. Kestrel clamps a copy for the current zoom, so the view never leaves the ground while the
## zoom changes and the stored target is never displaced.
func camera_view_target() -> Vector3:
	if not world_art_on:
		return camera_target
	return WorldArt.clamp_focus(camera_target, camera_zoom, camera_aspect, camera_yaw, _art_bounds())


func _update_camera() -> void:
	camera.size = camera_zoom
	var horizontal := Vector3(sin(camera_yaw), 0, cos(camera_yaw)) * camera_zoom * 0.68
	var shake := Vector3(sin(time_alive * 73.0), 0.0, cos(time_alive * 61.0)) * camera_shake * 0.12
	var view_target := camera_view_target()
	camera.position = view_target + horizontal + Vector3.UP * camera_zoom * 1.05 + shake
	camera.look_at(view_target + shake * 0.25, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not mission_deployed:
		return
	# F1 and Esc first (game_ui.gd escape_route holds the precedence), then a paused game takes no further input.
	if ui.route_key(event, _orders_armed()):
		return
	if ui.world_blocked():
		return
	if science_overlay and science_overlay.visible:
		if event is InputEventKey and event.pressed and event.keycode in [Keybinds.CANCEL, Keybinds.SCIENCE]:
			science_overlay.visible = false
		return
	if event is InputEventMouseMotion and dragging:
		_update_selection_box(event.position)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_focus_zoom = maxf(_zoom_limits().x, camera_focus_zoom - 1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_focus_zoom = minf(_zoom_limits().y, camera_focus_zoom + 1.25)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if rally_armed:
					rally_armed = false
					var rally_ground := _screen_to_ground(event.position)
					if rally_ground != Vector3.INF and is_instance_valid(selected) and String(selected.get_meta("category", "unit")) == "building":
						_write_bridge_rally(selected, rally_ground)
					return
				if build_mode != "":
					_try_place_build(_screen_to_ground(event.position))
					return
				selection_double_click = event.double_click
				drag_start = event.position
				dragging = true
				_update_selection_box(event.position)
			elif dragging:
				dragging = false
				selection_box.visible = false
				if drag_start.distance_to(event.position) > 10.0:
					_select_in_rect(Rect2(drag_start, event.position - drag_start).abs(), event.shift_pressed)
				else:
					_select_at(event.position, event.shift_pressed, selection_double_click)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not selected_units.is_empty():
			var ground := _screen_to_ground(event.position)
			if ground != Vector3.INF:
				if String(selected.get_meta("category", "unit")) == "building":
					_write_bridge_rally(selected, ground)
				else:
					for unit in selected_units:
						if not is_instance_valid(unit) or String(unit.get_meta("category", "unit")) != "unit":
							continue
						if bridge_active and bool(unit.get_meta("bridge_controlled", false)):
							_write_bridge_move(unit, ground, attack_move_armed)
						else:
							unit.set_meta("manual_target", ground)
					_show_move_marker(ground, attack_move_armed)
					_show_order_path(selected_units, ground, attack_move_armed)
				attack_move_armed = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == Keybinds.SELECT_ARMY:
			if select_army() > 0:
				objective_label.text = "ARMY SELECTED"
		elif event.keycode == Keybinds.SELECT_IDLE:
			select_idle_crew()
		elif event.keycode == Keybinds.ATTACK_MOVE:
			attack_move_armed = true
			rally_armed = false
			build_mode = ""
			objective_label.text = "ATTACK-MOVE ARMED — RIGHT-CLICK A DESTINATION"
		elif event.keycode == Keybinds.CANCEL:
			# Only reached while something is armed: with nothing armed game_ui.route_key opened the pause menu above.
			attack_move_armed = false
			rally_armed = false
			build_mode = ""
			if is_instance_valid(build_ghost):
				build_ghost.visible = false
			if science_overlay:
				science_overlay.visible = false
			objective_label.text = "COMMAND MODE CANCELLED"
		elif event.keycode in Keybinds.GROUPS:
			var group := int(Keybinds.GROUPS.find(event.keycode)) + 1
			if event.ctrl_pressed:
				control_groups[group] = selected_units.duplicate()
				objective_label.text = "CONTROL GROUP %d ASSIGNED" % group
			else:
				recall_control_group(group)
		elif Keybinds.TRAIN.has(event.keycode):
			_write_bridge_train(Keybinds.TRAIN[event.keycode])
		elif event.keycode == Keybinds.ABILITY:
			_write_bridge_ability()
		elif event.keycode == Keybinds.REPAIR:
			_write_bridge_structure_action("repair")
		elif event.keycode == Keybinds.SELL:
			_write_bridge_structure_action("sell")
		elif Keybinds.BUILD.has(event.keycode):
			_arm_build(Keybinds.BUILD[event.keycode])
		elif event.keycode == Keybinds.SCIENCE:
			_toggle_science_panel()
		elif event.keycode == Keybinds.FOCUS and is_instance_valid(selected):
			camera_focus_target = selected.global_position
			camera_focus_zoom = float(WorldArt.CAMERA.focus_zoom) if world_art_on else 8.2
			camera_cinematic = 0.8
		elif event.keycode == Keybinds.HOME:
			camera_focus_target = home_focus()
			camera_focus_zoom = _zoom_default()


## A left click in build mode. A point past the map edge (Kestrel) is ignored: no order, build mode stays armed.
func _try_place_build(build_ground: Vector3) -> void:
	if build_ground == Vector3.INF or _off_map(build_ground):
		return
	var build_tile := _world_to_tile(build_ground)
	if _is_build_valid(build_tile):
		_write_bridge_build(build_mode, build_ground)
		build_mode = ""
	else:
		objective_label.text = "INVALID FOUNDATION — CHOOSE OPEN TERRAIN"


func _update_selection_box(current: Vector2) -> void:
	if not selection_box:
		return
	var rect := Rect2(drag_start, current - drag_start).abs()
	selection_box.position = rect.position
	selection_box.size = rect.size
	selection_box.visible = rect.size.length() > 6.0


func _select_in_rect(rect: Rect2, additive := false) -> void:
	var found: Array[Node3D] = []
	if additive:
		found.assign(selected_units)
	for unit in units:
		if not is_instance_valid(unit) or int(unit.get_meta("team")) != HUMAN:
			continue
		var screen := camera.unproject_position(unit.global_position)
		if rect.has_point(screen) and not found.has(unit):
			found.append(unit)
	_set_selection(found)


func _select_at(screen_position: Vector2, additive := false, similar := false) -> void:
	var nearest: Node3D
	var nearest_distance := 32.0
	for candidate in bridge_nodes.values():
		if not is_instance_valid(candidate) or int(candidate.get_meta("team", -1)) != HUMAN:
			continue
		var projected := camera.unproject_position(candidate.global_position + Vector3.UP * 0.15)
		var distance := projected.distance_to(screen_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	var found: Array = selected_units.duplicate() if additive else []
	if is_instance_valid(nearest):
		if similar:
			for candidate in bridge_nodes.values():
				if is_instance_valid(candidate) and int(candidate.get_meta("team", -1)) == HUMAN and candidate.get_meta("kind_name", "") == nearest.get_meta("kind_name", ""):
					var projected := camera.unproject_position(candidate.global_position)
					if get_viewport().get_visible_rect().has_point(projected) and not found.has(candidate):
						found.append(candidate)
		elif not found.has(nearest):
			found.append(nearest)
	_set_selection(found)


## Selects control group `group` (the number keys and the control group list both end here).
func recall_control_group(group: int) -> void:
	if control_groups.has(group):
		_set_selection(control_groups[group])
		objective_label.text = "CONTROL GROUP %d RECALLED" % group


## Structure panel's Set rally: the next left click on the map sets the selected producer's rally point (the existing
## `rally` bridge command; right click on the map does the same). Esc cancels.
func arm_rally() -> void:
	if not is_instance_valid(selected) or String(selected.get_meta("kind_name", "")) not in ["Barracks", "Refinery", "VehicleFactory", "Airfield"]:
		objective_label.text = "SELECT A BARRACKS OR REFINERY TO SET A RALLY POINT"
		return
	rally_armed = true
	attack_move_armed = false
	build_mode = ""
	objective_label.text = "SET RALLY ARMED: CLICK A TILE, ESC CANCELS"


func _set_selection(selection: Array) -> void:
	rally_armed = false
	selected_units.clear()
	for candidate in selection:
		if is_instance_valid(candidate) and candidate is Node3D:
			selected_units.append(candidate)
	selected = selected_units[0] if not selected_units.is_empty() else null
	if not is_instance_valid(selected):
		if is_instance_valid(selection_ring):
			selection_ring.visible = false
		if is_instance_valid(range_ring):
			range_ring.visible = false
		return
	if not is_instance_valid(selection_ring):
		var torus := TorusMesh.new()
		torus.inner_radius = 0.43
		torus.outer_radius = 0.49
		torus.rings = 24
		torus.ring_segments = 8
		selection_ring = _mesh(torus, materials.glass, selected.position + Vector3.UP * 0.04)
	selection_ring.visible = true
	if world_art_on:  # spec addendum W6: the ring wraps the fitted model (the torus is 0.46 across its tube centre)
		var ring_scale := 1.0
		if selected.has_meta("visual_tiles"):
			ring_scale = float(selected.get_meta("visual_tiles")) * WorldArt.TILE * 0.55 / 0.46
		selection_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	var category := String(selected.get_meta("category", "unit"))
	if not is_instance_valid(range_ring):
		var range_mesh := TorusMesh.new()
		range_mesh.inner_radius = 2.16
		range_mesh.outer_radius = 2.20
		range_mesh.rings = 56
		range_mesh.ring_segments = 7
		range_ring = _mesh(range_mesh, materials.territory_human, selected.position + Vector3.UP * 0.045)
		range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_ring.position = selected.position + Vector3.UP * 0.045
	range_ring.visible = category == "unit" or String(selected.get_meta("kind_name", "")) in ["GunTurret", "AaTurret"]
	if category == "unit":
		_set_command_tab("ORDERS")
	elif String(selected.get_meta("kind_name", "")) in ["Barracks", "VehicleFactory", "Airfield"]:
		_set_command_tab("UNITS")
	else:
		_set_command_tab("ORDERS")


func _show_move_marker(ground: Vector3, hostile: bool) -> void:
	var marker := _cylinder(self, 0.28, 0.025, ground + Vector3.UP * 0.035, materials.alien if hostile else materials.glass, 20)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE * 1.8, 0.38).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(marker, "scale", Vector3.ZERO, 0.28)
	tween.tween_callback(marker.queue_free)


func _show_order_path(formation: Array[Node3D], destination: Vector3, hostile: bool) -> void:
	var material: Material = materials.alien_marker if hostile else materials.human_marker
	for index in range(mini(formation.size(), 8)):
		var member := formation[index]
		if not is_instance_valid(member):
			continue
		var offset_angle := TAU * float(index) / maxf(1.0, float(formation.size()))
		var end := destination + Vector3(cos(offset_angle), 0, sin(offset_angle)) * (0.36 + float(index % 3) * 0.16)
		end.y = _height_world(end.x, end.z) + 0.055
		var line := _beam(self, member.global_position + Vector3.UP * 0.05, end, 0.028, material, 0.02)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tween := create_tween()
		tween.tween_interval(0.75)
		tween.tween_property(line, "scale", Vector3(0.0, 1.0, 1.0), 0.28)
		tween.tween_callback(line.queue_free)


func _dust_puff(position: Vector3) -> void:
	var puff := _sphere(self, Vector3(0.18, 0.05, 0.18), position + Vector3.UP * 0.04, materials.dust)
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "position:y", puff.position.y + 0.18, 0.48)
	tween.tween_property(puff, "scale", Vector3(1.8, 0.5, 1.8), 0.48)
	tween.set_parallel(false)
	tween.tween_callback(puff.queue_free)


## Pointer position in viewport pixels (the HUD adapter reads this instead of the window). Viewport.get_mouse_position
## asks the window system on every call (a synchronous X server round trip, measured at 0.15 to 0.65 ms on a busy desktop),
## and the hover hex, edge panning and the HUD each wanted it every frame, so the position comes from the mouse events
## instead, which carry it in the same viewport coordinates.
func mouse_position() -> Vector2:
	return pointer_position if pointer_known else get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_position = (event as InputEventMouse).position
		pointer_known = true


## World rectangle (x, z) shown by the minimap.
func minimap_world_rect() -> Rect2:
	return ui.minimap_world_rect()


## Bounding rectangle (x, z) of the ground the main camera sees; empty when a corner looks past the horizon.
func view_ground_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var rect := Rect2()
	var first := true
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var ground := _screen_to_ground(corner)
		if ground == Vector3.INF:
			return Rect2()
		if first:
			rect = Rect2(Vector2(ground.x, ground.z), Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(Vector2(ground.x, ground.z))
	return rect


## Where Home and the deploy shot look: the survival colony's fixed corner, or, on a map that sends a ground layer (Kestrel
## Reach, whose colony is elsewhere), your own Command Center. Under the world-art profile the view sits
## `WorldArt.CAMERA.home_offset` east of it, so the base fills the left of the frame and the river shows on the right.
func home_focus() -> Vector3:
	if ground_model != null:
		for node in bridge_nodes.values():
			if is_instance_valid(node) and int(node.get_meta("team", -1)) == 0 and String(node.get_meta("kind_name", "")) == "CommandCenter":
				var at: Vector3 = node.global_position if node.is_inside_tree() else node.position
				var offset: Vector2 = WorldArt.CAMERA.home_offset if world_art_on else Vector2.ZERO
				return Vector3(at.x + offset.x, 0.0, at.z + offset.y)
	return _hex_world(3, 14)


func focus_camera(position: Vector3, zoom: float) -> void:
	camera_focus_target = position
	camera_focus_zoom = float(WorldArt.CAMERA.focus_zoom) if world_art_on else zoom  # one focus-jump zoom on Kestrel
	camera_cinematic = 0.8


## World point of a hex centre on the rendered ground (what the HUD anchors deposit pins and lens overlays to).
func hex_world_point(x: int, y: int) -> Vector3:
	var world := _hex_world(x, y)
	world.y = _height_world(world.x, world.z)
	return world


## Where a hex centre lands on screen, in HUD pixels; Vector2.INF when it is behind the camera.
func screen_point_of_hex(x: int, y: int) -> Vector2:
	var world := hex_world_point(x, y)
	if not is_instance_valid(camera) or camera.is_position_behind(world):
		return Vector2.INF
	return camera.unproject_position(world)


## Selects every human unit but Harvesters (the "army"). Returns how many were selected; selection is left alone when none.
func select_army() -> int:
	var army: Array = []
	for node in bridge_nodes.values():
		if is_instance_valid(node) and int(node.get_meta("team", -1)) == HUMAN and String(node.get_meta("category", "")) == "unit" and String(node.get_meta("kind_name", "")) != "Harvester":
			army.append(node)
	if not army.is_empty():
		_set_selection(army)
	return army.size()


## Selects the first idle human unit (never a Harvester) from the latest snapshot and frames it. False when none is idle.
func select_idle_crew() -> bool:
	var idle: Dictionary = preload("res://scripts/ui/vm_gameplay.gd").idle_crews(bridge_snapshot)
	if idle.is_empty():
		return false
	var node = bridge_nodes.get(int(idle["first_id"]))
	if not is_instance_valid(node):
		return false
	_set_selection([node])
	focus_camera(node.global_position, 8.2)
	return true


func era_name() -> String:
	return _era_name()


## True while the build ghost is over a tile the order would be accepted on.
func build_cursor_valid() -> bool:
	return build_cursor_is_valid


func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.y >= -0.001:
		return Vector3.INF
	# Intersect the rendered height field instead of an invisible y=0 plane.
	var plane_distance := -origin.y / direction.y
	var low := maxf(0.0, plane_distance - 5.0)
	var high := plane_distance + 5.0
	for iteration in range(22):
		var middle := (low + high) * 0.5
		var sample := origin + direction * middle
		if sample.y > _height_world(sample.x, sample.z):
			low = middle
		else:
			high = middle
	return origin + direction * ((low + high) * 0.5)


func _update_units(delta: float) -> void:
	for unit in units.duplicate():
		if not is_instance_valid(unit):
			units.erase(unit)
			continue
		if bool(unit.get_meta("bridge_controlled", false)):
			continue
		var cooldown: float = maxf(0.0, float(unit.get_meta("cooldown")) - delta)
		unit.set_meta("cooldown", cooldown)
		var enemy := _nearest_enemy(unit)
		var manual: Vector3 = unit.get_meta("manual_target")
		var target_position: Vector3 = manual if manual != Vector3.INF else (enemy.position if enemy else unit.position)
		if enemy and manual == Vector3.INF:
			target_position += unit.get_meta("formation_offset") as Vector3
		var flat_delta := Vector3(target_position.x - unit.position.x, 0, target_position.z - unit.position.z)
		var attack_range := 2.4 if int(unit.get_meta("kind")) > 0 else 1.75
		if enemy and manual == Vector3.INF and flat_delta.length() <= attack_range:
			unit.look_at(Vector3(enemy.position.x, unit.position.y, enemy.position.z), Vector3.UP)
			if cooldown <= 0.0:
				unit.set_meta("cooldown", 1.05 + float(int(unit.get_meta("kind"))) * 0.32)
				_fire(unit, enemy)
		elif flat_delta.length() > 0.16:
			var direction := flat_delta.normalized()
			var separation := Vector3.ZERO
			for neighbor in units:
				if neighbor == unit or not is_instance_valid(neighbor) or int(neighbor.get_meta("team")) != int(unit.get_meta("team")):
					continue
				var neighbor_node := neighbor as Node3D
				var away: Vector3 = unit.position - neighbor_node.position
				away.y = 0.0
				if away.length_squared() > 0.001 and away.length_squared() < 0.52:
					separation += away.normalized() * (0.52 - away.length_squared())
			direction = (direction + separation * 0.58).normalized()
			var current_speed := move_toward(float(unit.get_meta("current_speed", 0.0)), float(unit.get_meta("speed")), delta * 1.65)
			unit.set_meta("current_speed", current_speed)
			unit.position += direction * current_speed * delta
			unit.position.y = _height_world(unit.position.x, unit.position.z) + 0.08 + sin(time_alive * 7.0 + float(unit.get_instance_id() % 13)) * 0.015
			unit.rotation.y = lerp_angle(unit.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-delta * 8.0))
			if time_alive - float(unit.get_meta("last_dust", 0.0)) > 0.34 and int(unit.get_meta("kind")) > 0:
				unit.set_meta("last_dust", time_alive)
				_dust_puff(unit.position - direction * 0.28)
		else:
			unit.set_meta("current_speed", move_toward(float(unit.get_meta("current_speed", 0.0)), 0.0, delta * 2.2))
			unit.set_meta("manual_target", Vector3.INF)


func _nearest_enemy(unit: Node3D) -> Node3D:
	var best: Node3D
	var best_distance := INF
	var team := int(unit.get_meta("team"))
	for other in units:
		if not is_instance_valid(other) or other == unit or int(other.get_meta("team")) == team:
			continue
		var distance := unit.position.distance_squared_to(other.position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _fire(attacker: Node3D, target: Node3D) -> void:
	var team := int(attacker.get_meta("team"))
	var color_material: Material = materials.glass if team == HUMAN else materials.plasma
	_tracer(attacker.position + Vector3.UP * 0.48, target.position + Vector3.UP * 0.34, color_material)
	var damage := 9.0 + float(int(attacker.get_meta("kind"))) * 6.0
	target.set_meta("hp", float(target.get_meta("hp")) - damage)
	var hp_ratio: float = clampf(float(target.get_meta("hp")) / float(target.get_meta("max_hp")), 0.0, 1.0)
	var health_fill := target.get_node_or_null("HealthFill") as MeshInstance3D
	if health_fill:
		health_fill.scale.x = hp_ratio
		health_fill.position.x = -0.28 * (1.0 - hp_ratio)
	if float(target.get_meta("hp")) <= 0.0:
		_destroy_unit(target, color_material)


func _tracer(a: Vector3, b: Vector3, material: Material) -> void:
	var flash := _sphere(self, Vector3.ONE * 0.16, a, material)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bolt := _sphere(self, Vector3(0.08, 0.08, 0.22), a, material)
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.look_at(b, Vector3.UP)
	var trail := _beam(self, a, b, 0.025, material)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var travel := clampf(a.distance_to(b) * 0.035, 0.08, 0.22)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.10)
	tween.tween_property(bolt, "position", b, travel).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(trail, "scale:x", 0.05, travel)
	tween.set_parallel(false)
	tween.tween_callback(flash.queue_free)
	tween.tween_callback(bolt.queue_free)
	tween.tween_callback(trail.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color("67ddff") if material == materials.glass else Color("f260cf")
	light.light_energy = 2.1
	light.omni_range = 1.7
	bolt.add_child(light)

func _destroy_unit(unit: Node3D, material: Material) -> void:
	if unit == selected:
		selected = null
		if is_instance_valid(selection_ring):
			selection_ring.queue_free()
	var burst := Node3D.new()
	add_child(burst)
	burst.position = unit.position + Vector3.UP * 0.35
	for i in range(7):
		var shard := _sphere(burst, Vector3.ONE * (0.09 + float(i % 3) * 0.035), Vector3.ZERO, material)
		var angle := TAU * float(i) / 7.0
		var end := Vector3(cos(angle), 0.6 + float(i % 2) * 0.4, sin(angle)) * 0.75
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", end, 0.42)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.42)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb04a")
	light.light_energy = 6.0
	light.omni_range = 4.0
	burst.add_child(light)
	var fade := create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.34)
	fade.tween_interval(0.2)
	fade.tween_callback(burst.queue_free)
	units.erase(unit)
	unit.queue_free()


func _append_bridge_command(line: String) -> void:
	var directory := runtime_directory.path_join("commands")
	DirAccess.make_dir_recursive_absolute(directory)
	command_sequence += 1
	var packet := directory.path_join("%020d_%08d.cmd" % [Time.get_ticks_usec(), command_sequence])
	var temporary := packet + ".next"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file:
		file.store_line(line)
		file.close()
		DirAccess.rename_absolute(temporary, packet)


func _write_bridge_move(unit: Node3D, ground: Vector3, attack_move := false) -> void:
	if int(unit.get_meta("team")) != HUMAN:
		objective_label.text = "ENEMY TELEMETRY ONLY — SELECT AN EARTH DEFENCE UNIT"
		return
	var simulation_bits := _world_to_sim_bits(ground)
	var simulation_x_bits := simulation_bits.x
	var simulation_z_bits := simulation_bits.y
	var verb := "attack" if attack_move else "move"
	_append_bridge_command("%s,%d,%d,%d" % [verb, int(unit.get_meta("bridge_id")), simulation_x_bits, simulation_z_bits])
	objective_label.text = "%s ORDER TRANSMITTED — %d UNIT%s" % ["ATTACK-MOVE" if attack_move else "MOVE", selected_units.size(), "" if selected_units.size() == 1 else "S"]


func _write_bridge_train(kind_name: String) -> void:
	if not bridge_active:
		objective_label.text = "SIMULATION CORE OFFLINE — PRODUCTION UNAVAILABLE"
		return
	var producer_kind := "Refinery" if kind_name == "Harvester" else ("VehicleFactory" if kind_name == "Tank" else ("Airfield" if kind_name == "Helicopter" else "Barracks"))
	var producers: Array = bridge_nodes.values()
	if is_instance_valid(selected):
		producers.push_front(selected)
	for node in producers:
		if is_instance_valid(node) and int(node.get_meta("team", -1)) == HUMAN and String(node.get_meta("kind_name", "")) == producer_kind and int(node.get_meta("construction", 0)) == 0:
			_append_bridge_command("train,%d,%s" % [int(node.get_meta("bridge_id")), kind_name])
			objective_label.text = "%s ORDER SENT TO %s" % [kind_name.to_upper(), producer_kind.to_upper()]
			return
	objective_label.text = "BUILD %s BEFORE TRAINING THIS UNIT" % producer_kind.to_upper()


func _write_bridge_rally(producer: Node3D, ground: Vector3) -> void:
	var kind_name := String(producer.get_meta("kind_name", ""))
	if kind_name not in ["Barracks", "Refinery", "VehicleFactory", "Airfield"]:
		objective_label.text = "SELECT A BARRACKS OR REFINERY TO SET A RALLY POINT"
		return
	var simulation_bits := _world_to_sim_bits(ground)
	var simulation_x_bits := simulation_bits.x
	var simulation_z_bits := simulation_bits.y
	_append_bridge_command("rally,%d,%d,%d" % [int(producer.get_meta("bridge_id")), simulation_x_bits, simulation_z_bits])
	objective_label.text = "RALLY POINT UPDATED"
	_show_move_marker(ground, false)


func _write_bridge_ability() -> void:
	if not is_instance_valid(selected) or String(selected.get_meta("category", "unit")) != "unit":
		objective_label.text = "SELECT A COMBAT UNIT BEFORE CASTING AN ABILITY"
		return
	if int(selected.get_meta("ability_cd", 0)) > 0:
		objective_label.text = "TACTICAL ABILITY RECHARGING"
		return
	var ground := _screen_to_ground(mouse_position())
	if ground == Vector3.INF:
		return
	var simulation_bits := _world_to_sim_bits(ground)
	var simulation_x_bits := simulation_bits.x
	var simulation_z_bits := simulation_bits.y
	_append_bridge_command("ability,%d,%d,%d" % [int(selected.get_meta("bridge_id")), simulation_x_bits, simulation_z_bits])
	objective_label.text = "TACTICAL ABILITY TRANSMITTED"
	_show_move_marker(ground, true)


func _write_bridge_structure_action(verb: String) -> void:
	if not is_instance_valid(selected) or String(selected.get_meta("category", "unit")) != "building":
		objective_label.text = "SELECT AN OWNED STRUCTURE FIRST"
		return
	_append_bridge_command("%s,%d" % [verb, int(selected.get_meta("bridge_id"))])
	objective_label.text = "%s ORDER TRANSMITTED" % verb.to_upper()
	if verb == "sell":
		_set_selection([])


func _write_bridge_build(kind_name: String, ground: Vector3) -> void:
	if not bridge_active:
		return
	var tile := _world_to_tile(ground)
	_append_bridge_command("build,%s,%d,%d" % [kind_name, tile.x, tile.y])
	objective_label.text = "%s FOUNDATION ORDERED" % kind_name.to_upper()
	_show_move_marker(ground, false)


func _write_bridge_research(tech_id := -1) -> void:
	if not bridge_active:
		objective_label.text = "SIMULATION CORE OFFLINE — SCIENCE UNAVAILABLE"
		return
	if bridge_active_research_id >= 0:
		objective_label.text = "RESEARCH IN PROGRESS — %s" % bridge_active_research_name.to_upper()
		return
	var chosen_id: int = bridge_suggested_research_id if tech_id < 0 else int(tech_id)
	if chosen_id < 0:
		objective_label.text = "NO AFFORDABLE RESEARCH — EXPAND POWER, LABOUR, OR MINERALS"
		return
	var chosen_name := bridge_suggested_research_name
	for option in bridge_research_options:
		if option is Dictionary and int(option.get("id", -1)) == chosen_id:
			chosen_name = String(option.get("name", chosen_name))
			break
	_append_bridge_command("research,%d" % chosen_id)
	objective_label.text = "RESEARCH ORDERED — %s" % chosen_name.to_upper()
	if science_overlay:
		science_overlay.visible = false


func _era_name() -> String:
	return ERA_NAMES[clampi(bridge_era, 0, ERA_NAMES.size() - 1)]


func _science_status() -> String:
	if bridge_active_research_id >= 0:
		return "%s  %ds" % [bridge_active_research_name.to_upper(), ceili(float(bridge_active_research_ticks) / TICKS_PER_SECOND)]
	if bridge_suggested_research_id >= 0:
		return "NEXT: %s" % bridge_suggested_research_name.to_upper()
	return "AWAITING CAPACITY"


func _poll_bridge(delta: float) -> void:
	bridge_poll_elapsed += delta
	if bridge_poll_elapsed < BRIDGE_POLL:
		return
	bridge_poll_elapsed = 0.0
	var snapshot_path := runtime_directory.path_join("snapshot.json")
	if not FileAccess.file_exists(snapshot_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(snapshot_path))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 5:
		return
	var was_bridge_active := bridge_active
	var previous_research_count := bridge_research_count
	var completed_research_name := bridge_active_research_name
	var previous_era := bridge_era
	var previous_waves := bridge_waves
	var previous_winner := bridge_winner
	if not bridge_active:
		bridge_active = true
		for preview_unit in units.duplicate():
			if is_instance_valid(preview_unit):
				preview_unit.queue_free()
		units.clear()
		selected_units.clear()
		selected = null
		if is_instance_valid(selection_ring):
			selection_ring.queue_free()
	bridge_snapshot = parsed
	bridge_tick = int(parsed.get("tick", 0))
	bridge_money = int(parsed.get("money_bits", 0)) / 65536
	bridge_energy = int(parsed.get("energy_bits", 0)) / 65536
	bridge_earthfront = bool(parsed.get("earthfront", true))
	bridge_technology_total = int(parsed.get("technology_total", 12))
	bridge_power_generation = int(parsed.get("power_generation", 0))
	bridge_power_demand = int(parsed.get("power_demand", 0))
	bridge_storage_capacity = int(parsed.get("storage_capacity", 0))
	bridge_ore = int(parsed.get("ore_buffer", 0))
	bridge_depot_ammo = int(parsed.get("depot_ammunition", 0))
	var previous_relays := bridge_relays
	bridge_relays = int(parsed.get("alien_relays", 0))
	bridge_active_relays = int(parsed.get("active_alien_relays", 0))
	bridge_expedition_size = int(parsed.get("next_expedition_size", 0))
	if bridge_initialized and bridge_relays < previous_relays and bridge_winner < 0:
		_show_notification("ALIEN RELAY DESTROYED", "EXPEDITION SUPPORT REDUCED • PUSH TOWARD THE CORE", Color("65e4da"))
	bridge_incoming_doctrine = String(parsed.get("incoming_doctrine", "Mixed expedition"))
	bridge_research_status = String(parsed.get("research_status", ""))
	construction_zone.clear()
	for tile in parsed.get("construction_zone", []):
		construction_zone[Vector2i(int(tile[0]), int(tile[1]))] = true
	bridge_services.clear()
	for service in parsed.get("services", []):
		bridge_services[int(service.get("id", -1))] = service
	bridge_labour = int(parsed.get("labour_bits", 0)) / 65536
	bridge_supply_used = int(parsed.get("supply_used", 0))
	bridge_supply_cap = int(parsed.get("supply_cap", 0))
	bridge_era = int(parsed.get("era", 0))
	bridge_research_count = int(parsed.get("research_count", 0))
	bridge_waves = int(parsed.get("waves_survived", 0))
	bridge_next_wave_ticks = int(parsed.get("next_wave_ticks", -1))
	bridge_unlocked_buildings = parsed.get("unlocked_buildings", [])
	bridge_unlocked_units = parsed.get("unlocked_units", [])
	bridge_active_research_id = int(parsed.get("active_research_id", -1))
	bridge_active_research_ticks = int(parsed.get("active_research_ticks", 0))
	bridge_active_research_name = String(parsed.get("active_research_name", ""))
	bridge_suggested_research_id = int(parsed.get("suggested_research_id", -1))
	bridge_suggested_research_name = String(parsed.get("suggested_research_name", ""))
	var next_options: Array = parsed.get("research_options", [])
	var next_signature := JSON.stringify(next_options)
	if next_signature != bridge_research_signature:
		bridge_research_signature = next_signature
		bridge_research_options = next_options
	bridge_winner = int(parsed.get("winner", -1))
	_sync_ground(parsed)
	_sync_bridge_map(parsed)
	_sync_spent_deposits(parsed)
	_sync_bridge_entities(parsed.get("entities", []))
	_apply_era_visuals()
	if was_bridge_active and bridge_research_count > previous_research_count:
		var completed := completed_research_name if completed_research_name != "" else "NEW CAPABILITY"
		_show_notification("SCIENCE COMPLETE", completed.to_upper() + " • BATTLEFIELD SYSTEMS UPDATED", Color("66f0df"))
		_science_pulse()
	if was_bridge_active and bridge_era > previous_era:
		_show_notification("ERA ASCENDED", "ERA %02d • %s" % [bridge_era + 1, _era_name()], Color("ffd071"))
		camera_shake = 0.65
	if bridge_waves > previous_waves:
		wave_warning_level = 0
		_show_notification("ALIEN WAVE %02d INBOUND" % bridge_waves, "HOSTILE FORMATIONS ENTERING THE EARTHFRONT", Color("ff5968"))
		_play_tone(165.0, 0.28, 0.17, -45.0)
	elif bridge_next_wave_ticks > 0 and bridge_next_wave_ticks <= 300 and wave_warning_level < 2:
		wave_warning_level = 2
		_show_notification("TEN SECONDS", "ALIEN WAVE APPROACHING • FORM A DEFENSIVE LINE", Color("ff8b62"))
		_play_tone(210.0, 0.18, 0.14, -30.0)
	elif bridge_next_wave_ticks > 300 and bridge_next_wave_ticks <= 1350 and wave_warning_level < 1:
		wave_warning_level = 1
		_show_notification("ENEMY SIGNAL DETECTED", bridge_incoming_doctrine.to_upper() + " • ARRIVAL IN 45 SECONDS", Color("ffd071"))
	if bridge_next_wave_ticks > 1350:
		wave_warning_level = 0
	if bridge_winner >= 0 and previous_winner < 0:
		_show_end_screen(bridge_winner)


func _sync_bridge_map(snapshot: Dictionary) -> void:
	if bridge_map_synced:
		return
	if int(snapshot.get("map_width", 0)) != MAP_W or int(snapshot.get("map_height", 0)) != MAP_H:
		push_warning("Bridge map dimensions do not match the 3D battlefield")
		return
	bridge_map_synced = true
	for coordinate in snapshot.get("blocked", []):
		if not coordinate is Array or coordinate.size() < 2:
			continue
		var x := int(coordinate[0])
		var z := int(coordinate[1])
		var world := _hex_world(x, z)
		var elevation := _height_world(world.x, world.z)
		blocked_tiles[Vector2i(x, z)] = true
		if world_art_on:
			continue  # the painted props dress blocked ground; legacy slabs and rocks would float in the river and sea
		if (x * 3 + z) % 37 == 0:
			_create_ruin(Vector3(world.x, elevation, world.z))
		elif (x + z) % 9 == 0:
			_create_rocks(Vector3(world.x, elevation, world.z), 0.44)
	for deposit in snapshot.get("deposits", []):
		if not deposit is Dictionary:
			continue
		var x := int(deposit.get("x", 0))
		var z := int(deposit.get("y", 0))
		var world := _hex_world(x, z)
		deposit_tiles[Vector2i(x, z)] = true
		var root := Node3D.new()
		root.name = "Deposit_%s_%d_%d" % [String(deposit.get("kind", "Ore")), x, z]
		root.add_to_group("resource_deposits")
		root.set_meta("phase", float((x * 13 + z * 7) % 19) * 0.31)
		add_child(root)
		root.position = Vector3(world.x, _height_world(world.x, world.z), world.z)
		if world_art_on:
			continue  # crystals are cards in WorldProps (spec addendum W9); the HUD pins carry the label
		_cylinder(root, 0.36, 0.025, Vector3(0, 0.015, 0), materials.earth, 16)
		for rock_index in range(5):
			var angle := TAU * float(rock_index) / 5.0
			var stone := SphereMesh.new()
			stone.radius = 0.09 + float(rock_index % 3) * 0.025
			stone.height = stone.radius * 1.25
			stone.radial_segments = 7
			stone.rings = 4
			_mesh(stone, materials.rock, Vector3(cos(angle) * 0.20, 0.07, sin(angle) * 0.20), root)
		var marker := Label3D.new()
		marker.text = "ORE"
		marker.position = Vector3(0, 0.34, 0)
		marker.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
		marker.font_size = 24
		marker.pixel_size = 0.004
		marker.modulate = Color("cab98b")
		marker.outline_size = 4
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(marker)


## Kestrel only: a deposit the sim has mined out (it leaves the snapshot list, or reads zero) keeps its crystals, dimmed
## and greyed, so the site reads as spent; its HUD pin is already gone (vm_gameplay.deposit_pins). Survival is untouched.
func _sync_spent_deposits(snapshot: Dictionary) -> void:
	if world_props != null and snapshot.has("deposits"):  # a snapshot without the list must not spend every site
		world_props.mark_spent(snapshot.get("deposits", []))


## Kestrel only (spec addendum W6): the absolute scale that makes `visual` `tiles` tiles wide (x) and the fitted model's
## top in its parent's space (y). `merged_aabb` measures before the visual's own scale, so x is never multiplied by the
## authored scale. Cached per model key.
func _fitted(visual: Node3D, key: String, tiles: float) -> Vector2:
	if not _fit_cache.has(key):
		var k := WorldArt.fit_factor(visual, tiles)
		_fit_cache[key] = Vector2(k, WorldArt.merged_aabb(visual).end.y * k)
	return _fit_cache[key]


func _create_bridge_building(owner: int, kind_name: String, destination: Vector3, bridge_id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Core_%s_%03d" % [kind_name, bridge_id]
	add_child(root)
	root.position = destination
	root.set_meta("bridge_controlled", true)
	root.set_meta("bridge_id", bridge_id)
	root.set_meta("team", owner)
	root.set_meta("category", "building")
	root.set_meta("kind_name", kind_name)
	var human_assets := {
		"CommandCenter": "human_hq",
		"PowerPlant": "human_power",
		"Refinery": "human_refinery",
		"Barracks": "human_barracks",
		"VehicleFactory": "human_barracks",
		"Airfield": "human_barracks",
		"SupplyDepot": "human_refinery",
		"Battery": "human_power",
		"GunTurret": "human_gun_turret",
		"AaTurret": "human_aa_turret",
		"Wall": "human_wall",
		"ResearchLab": "human_lab",
		"AntimatterPlant": "human_antimatter",
	}
	var alien_assets := {
		"CommandCenter": "alien_core",
		"PowerPlant": "alien_power",
		"Refinery": "alien_refinery",
		"Barracks": "alien_barracks",
		"VehicleFactory": "alien_barracks",
		"Airfield": "alien_barracks",
		"SupplyDepot": "alien_refinery",
		"Battery": "alien_power",
		"GunTurret": "alien_gun_turret",
		"AaTurret": "alien_aa_turret",
		"Wall": "alien_wall",
		"ResearchLab": "alien_lab",
		"AntimatterPlant": "alien_antimatter",
	}
	var asset_map: Dictionary = human_assets if owner == HUMAN else alien_assets
	var fallback := "human_industry" if owner == HUMAN else "alien_spire"
	var asset_name := String(asset_map.get(kind_name, fallback))
	if world_art_on and owner == HUMAN and kind_name == "VehicleFactory":
		asset_name = "human_industry"  # the profile shows every human building as its authored model; the factory has its own
	var model_scale := 0.32 if kind_name == "CommandCenter" else (0.40 if kind_name == "Wall" else 0.30)
	var visual: Node3D
	if not world_art_on and owner == HUMAN and kind_name in ["CommandCenter", "ResearchLab", "Barracks", "VehicleFactory", "Airfield", "PowerPlant", "Battery", "Refinery", "SupplyDepot"]:
		visual = tactical_models.building(self, root, kind_name)
	else:
		visual = _place_scene(root, "res://assets/models/authored/%s.glb" % asset_name, Vector3.ZERO, Vector3.ONE * model_scale, 0.0)
	visual.name = "Visual"
	var bar_y: Array = [1.15, 1.155, 1.24, 1.245]  # health back, fill, shield back, fill
	if world_art_on:
		# spec addendum W6: the model is fitted to its width in tiles; the props under it go, a soft pad goes under it
		var tiles := float(WorldArt.BUILDING_TILES.get(kind_name, 1.7))
		var fit := _fitted(visual, "%d:%s:%s" % [owner, asset_name, tiles], tiles)  # one model can serve two widths
		visual.scale = Vector3.ONE * fit.x
		visual.set_meta("authored_scale", visual.scale)  # construction grows the fitted model, not the legacy scale
		root.set_meta("visual_tiles", tiles)
		bar_y = [fit.y + 0.18, fit.y + 0.185, fit.y + 0.27, fit.y + 0.275]
		if world_props != null:
			world_props.clear_around(destination, tiles * WorldArt.TILE * 0.5)
			var slot: int = world_props.add_pad(destination, tiles * WorldArt.TILE)
			if slot >= 0:
				var props: RefCounted = world_props
				root.tree_exiting.connect(func(): props.release_pad(slot))
	else:
		for prop in get_tree().get_nodes_in_group("scenery"):
			if prop is Node3D and prop.global_position.distance_to(destination) < 0.85:
				prop.hide()
	if kind_name == "CommandCenter" and not world_art_on:  # the HUD names buildings under the profile
		var banner := Label3D.new()
		banner.text = "COMMAND" if owner == HUMAN else "CORE NODE"
		banner.position = Vector3(0, 1.0, 0)
		banner.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
		banner.font_size = 28
		banner.pixel_size = 0.004
		banner.modulate = Color("a4c9cb") if owner == HUMAN else Color("db9393")
		banner.outline_size = 4
		banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(banner)
	var health_back := _box(root, Vector3(0.82, 0.045, 0.07), Vector3(0, bar_y[0], 0), materials.alien_dark)
	health_back.name = "HealthBack"
	health_back.visible = false
	var health_fill := _box(root, Vector3(0.76, 0.055, 0.08), Vector3(0, bar_y[1], 0), materials.glass if owner == HUMAN else materials.alien)
	health_fill.name = "HealthFill"
	health_fill.visible = false
	var shield_back := _box(root, Vector3(0.82, 0.035, 0.055), Vector3(0, bar_y[2], 0), materials.alien_dark)
	shield_back.name = "ShieldBack"
	shield_back.visible = false
	var shield_fill := _box(root, Vector3(0.76, 0.044, 0.065), Vector3(0, bar_y[3], 0), materials.plasma)
	shield_fill.name = "ShieldFill"
	shield_fill.visible = false
	return root
func _sync_bridge_entities(entities: Array) -> void:
	var seen: Dictionary = {}
	var next_frame_entities: Dictionary = {}
	for entity_data in entities:
		if not entity_data is Dictionary:
			continue
		var category := String(entity_data.get("category", ""))
		if category not in ["unit", "building"]:
			continue
		var bridge_id := int(entity_data.get("id", -1))
		seen[bridge_id] = true
		var entity_node := bridge_nodes.get(bridge_id) as Node3D
		var incoming_kind := String(entity_data.get("kind", "Infantry"))
		var incoming_owner := int(entity_data.get("owner", 0))
		if is_instance_valid(entity_node) and (entity_node.get_meta("kind_name", "") != incoming_kind or int(entity_node.get_meta("team", -1)) != incoming_owner):
			units.erase(entity_node)
			selected_units.erase(entity_node)
			for group in control_groups.values():
				group.erase(entity_node)
			if selected == entity_node:
				selected = null
			entity_node.queue_free()
			entity_node = null
		var destination := _sim_bits_to_world(int(entity_data.get("x_bits", 0)), int(entity_data.get("z_bits", 0)))
		destination.y = _height_world(destination.x, destination.z) + (0.08 if category == "unit" else 0.0)
		if not is_instance_valid(entity_node):
			var owner := int(entity_data.get("owner", 0))
			var kind_name := String(entity_data.get("kind", "Infantry"))
			if category == "unit":
				_create_unit(owner, destination, _bridge_kind_index(kind_name))
				entity_node = units.back()
				entity_node.name = "Core_%s_%03d" % [kind_name, bridge_id]
				entity_node.set_meta("bridge_controlled", true)
				entity_node.set_meta("bridge_id", bridge_id)
				entity_node.set_meta("category", "unit")
			else:
				entity_node = _create_bridge_building(owner, kind_name, destination, bridge_id)
			entity_node.set_meta("kind_name", incoming_kind)
			bridge_nodes[bridge_id] = entity_node
			if bridge_initialized:
				ui.session_log.unit_added(kind_name, owner, category)
				_deploy_effect(destination, owner)
				if owner == HUMAN and category == "unit":
					_show_notification("UNIT READY", kind_name.to_upper() + " REPORTING FOR DUTY", Color("65e4da"))
					_play_tone(620.0, 0.1, 0.1, 90.0)
		var bridge_motion := destination - entity_node.position
		bridge_motion.y = 0.0
		if category == "unit" and bridge_motion.length_squared() > 0.001:
			var direction := bridge_motion.normalized()
			entity_node.set_meta("glide_yaw", atan2(-direction.x, -direction.z))
			if time_alive - float(entity_node.get_meta("last_dust", 0.0)) > 0.38 and int(entity_node.get_meta("kind", 0)) > 0:
				entity_node.set_meta("last_dust", time_alive)
				_dust_puff(entity_node.position - direction * 0.26)
		else:
			entity_node.remove_meta("glide_yaw")
		entity_node.set_meta("glide_to", destination)  # _glide_bridge_nodes moves the node there over the next frames
		var hp: float = float(entity_data.get("hp_bits", 0)) / 65536.0
		var max_hp: float = maxf(1.0, float(entity_data.get("max_hp_bits", 65536)) / 65536.0)
		var shield: float = float(entity_data.get("shield_bits", 0)) / 65536.0
		var max_shield: float = float(entity_data.get("max_shield_bits", 0)) / 65536.0
		var previous_data = bridge_frame_entities.get(bridge_id)
		if bridge_initialized and previous_data is Dictionary and int(previous_data.get("hp_bits", 0)) > int(entity_data.get("hp_bits", 0)):
			_impact_effect(destination, int(entity_data.get("owner", 0)) == HUMAN)
		next_frame_entities[bridge_id] = {
			"hp_bits": int(entity_data.get("hp_bits", 0)),
			"owner": int(entity_data.get("owner", 0)),
			"kind": String(entity_data.get("kind", "")),
		}
		var relay_service: Dictionary = bridge_services.get(bridge_id, {})
		var relay_marker := entity_node.get_node_or_null("RelayMarker") as Label3D
		if bool(relay_service.get("alien_relay", false)):
			if not relay_marker:
				relay_marker = Label3D.new()
				relay_marker.name = "RelayMarker"
				relay_marker.position = Vector3(0, 0.9, 0)
				relay_marker.font_size = 24
				relay_marker.pixel_size = 0.004
				relay_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				relay_marker.modulate = Color("ffac83")
				entity_node.add_child(relay_marker)
			relay_marker.text = "INVASION RELAY +2 / WAVE" if int(relay_service.get("power", 0)) >= 500 else "INVASION RELAY — OFFLINE"
		elif relay_marker:
			relay_marker.queue_free()
		entity_node.set_meta("hp", hp)
		entity_node.set_meta("max_hp", max_hp)
		entity_node.set_meta("shield", shield)
		entity_node.set_meta("max_shield", max_shield)
		entity_node.set_meta("ability_cd", int(entity_data.get("ability_cd", 0)))
		entity_node.set_meta("stun_ticks", int(entity_data.get("stun_ticks", 0)))
		entity_node.set_meta("cargo", int(entity_data.get("cargo", 0)))
		entity_node.set_meta("rally_x_bits", int(entity_data.get("rally_x_bits", -1)))
		entity_node.set_meta("rally_z_bits", int(entity_data.get("rally_z_bits", -1)))
		entity_node.set_meta("construction", int(entity_data.get("construction", 0)))
		entity_node.set_meta("construction_total", int(entity_data.get("construction_total", 0)))
		entity_node.set_meta("production_name", String(entity_data.get("production_name", "")))
		entity_node.set_meta("production_queued", int(entity_data.get("production_queued", 0)))
		entity_node.set_meta("production_progress", int(entity_data.get("production_progress", 0)))
		entity_node.set_meta("production_duration", int(entity_data.get("production_duration", 0)))
		var health_fill := entity_node.get_node_or_null("HealthFill") as MeshInstance3D
		if health_fill:
			var ratio := clampf(hp / max_hp, 0.0, 1.0)
			health_fill.scale.x = ratio
			health_fill.position.x = -0.28 * (1.0 - ratio)
			if category == "building":
				health_fill.visible = ratio < 0.999
				var health_back := entity_node.get_node_or_null("HealthBack") as MeshInstance3D
				health_back.visible = health_fill.visible
		var shield_fill := entity_node.get_node_or_null("ShieldFill") as MeshInstance3D
		if shield_fill:
			var shield_ratio := clampf(shield / maxf(1.0, max_shield), 0.0, 1.0)
			shield_fill.scale.x = shield_ratio
			shield_fill.position.x = -0.28 * (1.0 - shield_ratio)
			if category == "building":
				shield_fill.visible = max_shield > 0.0
				var shield_back := entity_node.get_node_or_null("ShieldBack") as MeshInstance3D
				shield_back.visible = shield_fill.visible
		var visual := entity_node.get_node_or_null("Visual") as Node3D
		if visual:
			var remaining := int(entity_data.get("construction", 0))
			var total := maxi(1, int(entity_data.get("construction_total", 1)))
			var authored_scale: Vector3 = visual.get_meta("authored_scale", visual.scale)
			var build_progress := clampf(1.0 - float(remaining) / float(total), 0.08, 1.0)
			visual.visible = true
			visual.scale = Vector3(authored_scale.x, authored_scale.y * build_progress, authored_scale.z)

	for bridge_id in bridge_nodes.keys():
		if seen.has(bridge_id):
			continue
		var stale := bridge_nodes[bridge_id] as Node3D
		bridge_nodes.erase(bridge_id)
		units.erase(stale)
		if is_instance_valid(stale):
			if bridge_initialized:
				ui.session_log.unit_removed(String(stale.get_meta("kind_name", "")), int(stale.get_meta("team", ALIEN)), String(stale.get_meta("category", "")))
				_death_effect(stale.position, int(stale.get_meta("team", ALIEN)))
			stale.queue_free()
	bridge_frame_entities = next_frame_entities
	bridge_initialized = true


func _apply_era_visuals() -> void:
	for entity in bridge_nodes.values():
		if not is_instance_valid(entity) or String(entity.get_meta("category", "")) != "building":
			continue
		var crown := entity.get_node_or_null("EraCrown") as Node3D
		var owner := int(entity.get_meta("team", HUMAN))
		if not crown:
			crown = Node3D.new()
			crown.name = "EraCrown"
			crown.position = Vector3(0, 0.78, 0)
			entity.add_child(crown)
			var crown_mesh := TorusMesh.new()
			crown_mesh.inner_radius = 0.34
			crown_mesh.outer_radius = 0.39
			crown_mesh.rings = 24
			crown_mesh.ring_segments = 7
			var ring := _mesh(crown_mesh, materials.glass if owner == HUMAN else materials.plasma, Vector3.ZERO, crown)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cylinder(crown, 0.026, 0.62, Vector3(0, 0.28, 0), materials.glass if owner == HUMAN else materials.plasma, 8)
		crown.visible = bridge_era > 0
		crown.scale = Vector3.ONE * (0.86 + float(bridge_era) * 0.055)
		crown.rotation.y = time_alive * (0.16 if owner == HUMAN else -0.19)


func _bridge_kind_index(kind_name: String) -> int:
	match kind_name:
		"Tank":
			return 1
		"AntiArmor":
			return 2
		"Helicopter":
			return 3
		"Capital":
			return 4
		"Harvester":
			return 5
		_:
			return 0


func _build_ui() -> void:
	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)
	selection_box = ui.selection_box
	science_overlay = ui.research
	# State holders the game still writes to: the HUD turns objective_label changes into toasts, and _update_tutorial
	# only runs while tutorial_label exists. They are never shown.
	objective_label = Label.new()
	tutorial_label = Label.new()
	for holder in [objective_label, tutorial_label]:
		holder.visible = false
		ui.add_child(holder)


func _set_command_tab(tab_name: String) -> void:
	ui.set_tab(tab_name.to_lower())


func _on_command_button(action: String) -> void:
	match action:
		"attack":
			attack_move_armed = true
			rally_armed = false
			build_mode = ""
			objective_label.text = "ATTACK-MOVE ARMED — RIGHT-CLICK A DESTINATION"
		"cancel_orders":
			attack_move_armed = false
			rally_armed = false
			build_mode = ""
			if is_instance_valid(build_ghost):
				build_ghost.visible = false
			objective_label.text = "COMMAND MODE CANCELLED"
		"train_infantry":
			_write_bridge_train("Infantry")
		"train_tank":
			_write_bridge_train("Tank")
		"train_anti_armor":
			_write_bridge_train("AntiArmor")
		"train_harvester":
			_write_bridge_train("Harvester")
		"train_helicopter":
			_write_bridge_train("Helicopter")
		"train_capital":
			_write_bridge_train("Capital")
		"use_ability":
			_write_bridge_ability()
		"repair":
			_write_bridge_structure_action("repair")
		"sell":
			_write_bridge_structure_action("sell")
		"build_power":
			_arm_build("PowerPlant")
		"build_refinery":
			_arm_build("Refinery")
		"build_barracks":
			_arm_build("Barracks")
		"build_turret":
			_arm_build("GunTurret")
		"build_aa":
			_arm_build("AaTurret")
		"build_wall":
			_arm_build("Wall")
		"build_lab":
			_arm_build("ResearchLab")
		"build_factory":
			_arm_build("VehicleFactory")
		"build_airfield":
			_arm_build("Airfield")
		"build_depot":
			_arm_build("SupplyDepot")
		"build_battery":
			_arm_build("Battery")
		"research_next":
			_toggle_science_panel()


func _toggle_science_panel() -> void:
	ui.toggle_research()


func _has_selected_combat_unit() -> bool:
	for candidate in selected_units:
		if is_instance_valid(candidate) and int(candidate.get_meta("team", -1)) == HUMAN and String(candidate.get_meta("category", "")) == "unit":
			return true
	return false


func _update_hover_tile() -> void:
	if not is_instance_valid(hover_tile):
		return
	if not mission_deployed:
		hover_tile.visible = false
		_set_hover_cell(NO_HOVER)
		return
	var pointer := mouse_position()
	if ui.blocks_point(pointer):
		# Over the HUD the last hovered hex stays, so the inspector does not vanish as the cursor reaches for its panel.
		hover_tile.visible = false
		return
	var ground := _screen_to_ground(pointer)
	if ground == Vector3.INF or _off_map(ground):
		hover_tile.visible = false
		_set_hover_cell(NO_HOVER)
		return
	_show_hover_at(ground)


## Puts the hover marker on the hex under `ground` (the Kestrel outline drapes over the terrain and is rebuilt only when the
## hex or the zoom changes). Hidden off the map and while a build is armed.
func _show_hover_at(ground: Vector3) -> void:
	if _off_map(ground):
		hover_tile.visible = false
		_set_hover_cell(NO_HOVER)
		return
	var tile := _world_to_tile(ground)
	_set_hover_cell(tile)
	var world := _hex_world(tile.x, tile.y)
	hover_tile.position = Vector3(world.x, _height_world(world.x, world.z) + (HOVER_LIFT_KESTREL if world_art_on else 0.055), world.z)
	if world_art_on:
		var key := Vector3i(tile.x, tile.y, roundi(camera_zoom * 20.0))
		if key != hover_outline_key:
			hover_outline_key = key
			hover_tile.mesh = _hover_outline_mesh(world)
	hover_tile.visible = build_mode == "" and not (world_art_on and _hex_occupied(tile))


## Kestrel only: a bridge building or unit stands on `tile`. The outline draws without a depth test (so a tree card in
## front cannot hide it), so on an occupied hex it would paint over the model; the hex stays hovered for the inspector.
func _hex_occupied(tile: Vector2i) -> bool:
	for node in bridge_nodes.values():
		if is_instance_valid(node) and _world_to_tile((node as Node3D).position) == tile:
			return true
	return false


## Pixels per world unit along x: the orthographic camera shows `camera_zoom` units over the viewport height.
func _pixels_per_world() -> float:
	var h := get_viewport().get_visible_rect().size.y if is_inside_tree() else 1080.0
	return h / maxf(camera_zoom, 1.0)


## The Kestrel hover outline for the hex centred on `world`: a 3 px bright line with 2 px dark edges at the current zoom,
## every vertex lifted to the terrain under it (heights are offsets from the hex centre; the node sits at the centre height).
func _hover_outline_mesh(world: Vector3) -> ArrayMesh:
	var ppu := _pixels_per_world()
	var base := _height_world(world.x, world.z)
	var drape := func(p: Vector2) -> float: return _height_world(world.x + p.x, world.z + p.y) - base
	return WorldArt.hex_outline_mesh(HEX_X / 1.5 * 0.96, HEX_Z * 0.5 * 0.96, 3.0 / ppu, 2.0 / ppu, drape, 3)


## The HUD hashes its slices, so the hex is only reassigned when it really changes.
func _set_hover_cell(cell: Vector2i) -> void:
	if cell != hover_cell:
		hover_cell = cell


func _update_build_ghost() -> void:
	if not is_instance_valid(build_ghost):
		return
	build_cursor_is_valid = false
	if build_mode == "":
		build_ghost.visible = false
		return
	var pointer := mouse_position()
	var ground := _screen_to_ground(pointer)
	if ground == Vector3.INF or _off_map(ground) or ui.blocks_point(pointer):
		build_ghost.visible = false
		return
	var tile := _world_to_tile(ground)
	var snapped := _hex_world(tile.x, tile.y)
	snapped.y = _height_world(snapped.x, snapped.z) + 0.06
	build_ghost.position = snapped
	build_cursor_is_valid = _is_build_valid(tile)
	build_ghost.material_override = materials.ghost_valid if build_cursor_is_valid else materials.ghost_invalid
	build_ghost.visible = true


func _is_build_valid(tile: Vector2i) -> bool:
	if bridge_earthfront:
		return construction_zone.has(tile)
	if blocked_tiles.has(tile):
		return false
	if build_mode == "Refinery" and not deposit_tiles.has(tile):
		return false
	if build_mode != "Refinery" and deposit_tiles.has(tile):
		return false
	var world := _hex_world(tile.x, tile.y)
	for node in bridge_nodes.values():
		if is_instance_valid(node) and String(node.get_meta("category", "")) == "building":
			if Vector2(node.position.x, node.position.z).distance_to(Vector2(world.x, world.z)) < 0.62:
				return false
	return true


func _human_count(category: String, kind_name := "") -> int:
	var count := 0
	for node in bridge_nodes.values():
		if not is_instance_valid(node) or int(node.get_meta("team", -1)) != HUMAN:
			continue
		if String(node.get_meta("category", "")) != category:
			continue
		if kind_name == "" or String(node.get_meta("kind_name", "")) == kind_name:
			count += 1
	return count


func _advance_tutorial(next_stage: int, message: String) -> void:
	if next_stage <= tutorial_stage:
		return
	tutorial_stage = next_stage
	_show_notification("MISSION UPDATED", message, Color("65e4da"))
	match tutorial_stage:
		1, 2, 4, 6:
			_set_command_tab("BUILD")
		3, 5:
			_set_command_tab("SCIENCE")
		7:
			_set_command_tab("UNITS")
		8, 9:
			_set_command_tab("ORDERS")


func _update_tutorial() -> void:
	if not mission_deployed or not tutorial_label or bridge_winner >= 0:
		return
	if tutorial_stage == 0 and _human_count("building", "CommandCenter") > 0:
		_advance_tutorial(1, "Power the beachhead")
	elif tutorial_stage == 1 and _human_count("building", "PowerPlant") > 0:
		_advance_tutorial(2, "Secure a mineral deposit")
	elif tutorial_stage == 2 and _human_count("building", "Refinery") > 0:
		_advance_tutorial(3, "Unlock field science")
	elif tutorial_stage == 3 and bridge_unlocked_buildings.has("ResearchLab"):
		_advance_tutorial(4, "Construct the first research lab")
	elif tutorial_stage == 4 and _human_count("building", "ResearchLab") > 0:
		_advance_tutorial(5, "Unlock combined-arms command")
	elif tutorial_stage == 5 and bridge_unlocked_buildings.has("Barracks"):
		_advance_tutorial(6, "Establish frontline production")
	elif tutorial_stage == 6 and _human_count("building", "Barracks") > 0:
		_advance_tutorial(7, "Field at least three combat units")
	elif tutorial_stage == 7 and _human_count("unit") >= 3:
		_advance_tutorial(8, "Prepare for the first alien assault")
	elif tutorial_stage == 8 and bridge_waves >= 1:
		_advance_tutorial(9, "Counterattack and destroy the hostile Core Node")
	match tutorial_stage:
		0:
			tutorial_label.text = "01  SECURE THE LANDING ZONE  •  SURVEY IN PROGRESS"
		1:
			tutorial_label.text = "02  POWER THE BEACHHEAD  •  BUILD A POWER PLANT [P]"
		2:
			tutorial_label.text = "03  ESTABLISH INCOME  •  BUILD A REFINERY NEAR ORE; HAULERS DELIVER TO IT [R]"
		3:
			tutorial_label.text = "04  UNLOCK THE LAB  •  BUILD A POWERED LABORATORY [L]"
		4:
			tutorial_label.text = "05  BUILD SCIENCE CAPACITY  •  CONSTRUCT A RESEARCH LAB [L]"
		5:
			tutorial_label.text = "06  UNLOCK THE ARMY  •  RESEARCH ANTI-ARMOUR OR VEHICLE TOOLING [Y]"
		6:
			tutorial_label.text = "07  ESTABLISH PRODUCTION  •  CONSTRUCT A BARRACKS [B]"
		7:
			tutorial_label.text = "08  FIELD A STRIKE FORCE  •  TRAIN THREE UNITS [T / V / K]"
		8:
			tutorial_label.text = "09  HOLD THE EARTHFRONT  •  FIRST WAVE IN %ds" % ceili(float(maxi(0, bridge_next_wave_ticks)) / TICKS_PER_SECOND)
		9:
			tutorial_label.text = "10  COUNTERATTACK  •  DESTROY THE HOSTILE CORE NODE"


func _show_notification(title: String, body: String, color: Color) -> void:
	ui.notify(title, body, color)


func _play_tone(frequency: float, duration: float, volume: float, sweep := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = maxf(0.12, duration + 0.06)
	player.stream = stream
	player.volume_db = -8.0
	add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback:
		var frame_count := int(stream.mix_rate * duration)
		for frame in range(frame_count):
			var t := float(frame) / stream.mix_rate
			var envelope := minf(1.0, t * 35.0) * maxf(0.0, 1.0 - t / duration)
			var hz := frequency + sweep * t / maxf(duration, 0.001)
			var sample := sin(TAU * hz * t) * volume * envelope
			playback.push_frame(Vector2(sample, sample))
	get_tree().create_timer(duration + 0.12).timeout.connect(player.queue_free)


func _impact_effect(position: Vector3, human_hit: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = position + Vector3.UP * 0.35
	var flash := _sphere(root, Vector3.ONE * 0.18, Vector3.ZERO, materials.amber if human_hit else materials.plasma)
	var light := OmniLight3D.new()
	light.light_color = Color("ff9b45") if human_hit else Color("57f1df")
	light.light_energy = 3.2
	light.omni_range = 2.6
	root.add_child(light)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.0, 0.13)
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)
	if human_hit and alert_cooldown <= 0.0:
		alert_cooldown = 1.3
		camera_shake = maxf(camera_shake, 0.42)
		_play_tone(92.0, 0.09, 0.12, -25.0)


func _death_effect(position: Vector3, owner: int) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = position + Vector3.UP * 0.25
	var material: Material = materials.human_marker if owner == HUMAN else materials.alien_marker
	for i in range(10):
		var shard := _sphere(root, Vector3.ONE * (0.07 + float(i % 3) * 0.025), Vector3.ZERO, material)
		var angle := TAU * float(i) / 10.0
		var destination := Vector3(cos(angle) * 0.9, 0.35 + float(i % 4) * 0.18, sin(angle) * 0.9)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", destination, 0.45)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.48)
	var light := OmniLight3D.new()
	light.light_color = Color("ff9c47")
	light.light_energy = 6.0
	light.omni_range = 4.0
	root.add_child(light)
	var wreck := _box(self, Vector3(0.58, 0.10, 0.42), position + Vector3.UP * 0.05, materials.human_dark if owner == HUMAN else materials.alien_dark)
	wreck.rotation_degrees = Vector3(0, float((int(position.x * 37.0) + int(position.z * 19.0)) % 180), 7.0)
	wreck.visibility_range_end = 28.0
	var wreck_fade := create_tween()
	wreck_fade.tween_interval(10.0)
	wreck_fade.tween_property(wreck, "scale", Vector3.ZERO, 1.8)
	wreck_fade.tween_callback(wreck.queue_free)
	for smoke_index in range(3):
		var smoke := _sphere(self, Vector3.ONE * (0.12 + float(smoke_index) * 0.04), position + Vector3(0, 0.22, 0), materials.dust)
		var smoke_tween := create_tween()
		smoke_tween.tween_interval(float(smoke_index) * 0.12)
		smoke_tween.tween_property(smoke, "position:y", smoke.position.y + 0.9, 1.1)
		smoke_tween.tween_property(smoke, "scale", Vector3.ZERO, 0.45)
		smoke_tween.tween_callback(smoke.queue_free)
	var fade := create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.3)
	fade.tween_interval(0.22)
	fade.tween_callback(root.queue_free)
	camera_shake = maxf(camera_shake, 0.78)
	_play_tone(74.0, 0.16, 0.18, -34.0)


func _deploy_effect(position: Vector3, owner: int) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.34
	mesh.outer_radius = 0.41
	mesh.rings = 20
	mesh.ring_segments = 7
	var ring := _mesh(mesh, materials.human_marker if owner == HUMAN else materials.alien_marker, position + Vector3.UP * 0.05)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 2.4, 0.45)
	tween.tween_property(ring, "scale", Vector3.ZERO, 0.24)
	tween.tween_callback(ring.queue_free)


func _science_pulse() -> void:
	for node in bridge_nodes.values():
		if is_instance_valid(node) and int(node.get_meta("team", -1)) == HUMAN:
			_deploy_effect(node.position, HUMAN)
	_play_tone(430.0, 0.22, 0.14, 520.0)


func _show_end_screen(winner: int) -> void:
	if end_screen_shown:
		return
	end_screen_shown = true
	_play_tone(360.0 if winner == HUMAN else 120.0, 0.34, 0.18, 420.0 if winner == HUMAN else -50.0)
	ui.show_debrief()


## True while an order, a rally or a placement waits for its click (what Esc cancels before it opens the pause menu).
func _orders_armed() -> bool:
	return attack_move_armed or rally_armed or build_mode != ""


## The pause menu's real effect. The bridge stops stepping the simulation while `pause.flag` exists in the runtime
## directory (godot-bridge.rs), the same file-flag channel as start.flag and restart.flag; removing it resumes the run.
func set_sim_paused(on: bool) -> void:
	var path := runtime_directory.path_join("pause.flag")
	if on:
		var flag := FileAccess.open(path, FileAccess.WRITE)
		if flag:
			flag.store_line("pause")
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _restart_mission() -> void:
	var restart_file := FileAccess.open(runtime_directory.path_join("restart.flag"), FileAccess.WRITE)
	if restart_file:
		restart_file.store_line("restart")
	await get_tree().create_timer(0.35).timeout
	get_tree().reload_current_scene()


func _arm_build(kind_name: String) -> void:
	build_mode = kind_name
	attack_move_armed = false
	rally_armed = false
	if not is_instance_valid(build_ghost):
		var ghost_mesh := CylinderMesh.new()
		ghost_mesh.top_radius = 0.58
		ghost_mesh.bottom_radius = 0.58
		ghost_mesh.height = 0.08
		ghost_mesh.radial_segments = 6
		build_ghost = _mesh(ghost_mesh, materials.ghost_valid, Vector3.ZERO)
		build_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	build_ghost.visible = true
	objective_label.text = "PLACE %s — GREEN IS VALID • ESC CANCELS" % kind_name.to_upper()


func _deploy_camera() -> void:
	camera_target = Vector3(12.4, 0.0, 9.4)
	camera_zoom = WorldArt.CAMERA.deploy_from if world_art_on else 15.5
	camera_focus_target = home_focus()
	camera_focus_zoom = _zoom_default()
	camera_cinematic = 1.4


func _deploy_mission() -> void:
	var start_file := FileAccess.open(runtime_directory.path_join("start.flag"), FileAccess.WRITE)
	if start_file:
		start_file.store_line("deploy")
	mission_deployed = true
	tutorial_stage = 0
	_deploy_camera()
	_play_deploy_sound()
	_play_tone(520.0, 0.13, 0.16, 180.0)
	objective_label.text = "COMMAND LINK ESTABLISHED"
	ui.begin_operation()


func _world_to_sim_bits(world: Vector3) -> Vector2i:
	var simulation_x := (world.x - MAP_ORIGIN_X) / HEX_X * SIM_HEX_X + SIM_CELL_CENTER
	var simulation_z := (world.z - MAP_ORIGIN_Z) / HEX_Z + SIM_CELL_CENTER
	return Vector2i(roundi(simulation_x * 65536.0), roundi(simulation_z * 65536.0))


func _sim_bits_to_world(x_bits: int, z_bits: int) -> Vector3:
	var simulation_x := float(x_bits) / 65536.0
	var simulation_z := float(z_bits) / 65536.0
	return Vector3(
		MAP_ORIGIN_X + (simulation_x - SIM_CELL_CENTER) / SIM_HEX_X * HEX_X,
		0.0,
		MAP_ORIGIN_Z + (simulation_z - SIM_CELL_CENTER) * HEX_Z
	)


## Kestrel only: true when a ground point lies past the map edge (the mesh continues there, but nothing can be placed or hovered).
func _off_map(world: Vector3) -> bool:
	if not world_art_on:
		return false
	var column := roundi((world.x - MAP_ORIGIN_X) / HEX_X)
	if column < 0 or column > MAP_W - 1:
		return true
	var parity_offset := HEX_Z * 0.5 if column % 2 else 0.0
	var row := roundi((world.z - MAP_ORIGIN_Z - parity_offset) / HEX_Z)
	return row < 0 or row > MAP_H - 1


func _world_to_tile(world: Vector3) -> Vector2i:
	var column := clampi(roundi((world.x - MAP_ORIGIN_X) / HEX_X), 0, MAP_W - 1)
	var parity_offset := HEX_Z * 0.5 if column % 2 else 0.0
	var row := clampi(roundi((world.z - MAP_ORIGIN_Z - parity_offset) / HEX_Z), 0, MAP_H - 1)
	return Vector2i(column, row)


func _hex_world(x: int, z: int) -> Vector3:
	return Vector3(MAP_ORIGIN_X + float(x) * HEX_X, 0.0, MAP_ORIGIN_Z + float(z) * HEX_Z + (HEX_Z * 0.5 if x % 2 else 0.0))


func _height_world(x: float, z: float) -> float:
	if is_instance_valid(terrain_renderer) and terrain_renderer.has_method("height_at_world"):
		return float(terrain_renderer.height_at_world(x, z))
	var gx := clampi(roundi((x - MAP_ORIGIN_X) / HEX_X), 0, MAP_W - 1)
	var gz := clampi(roundi((z - MAP_ORIGIN_Z - (HEX_Z * 0.5 if gx % 2 else 0.0)) / HEX_Z), 0, MAP_H - 1)
	return float(terrain_height.get(Vector2i(gx, gz), 0.0))


func _mesh(mesh: Mesh, material: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


func _place_scene(parent: Node, path: String, pos: Vector3, scale_value: Vector3, rotation_y := 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Missing 3D asset: " + path)
		return null
	var instance := packed.instantiate() as Node3D
	parent.add_child(instance)
	instance.position = pos
	instance.scale = scale_value
	instance.set_meta("authored_scale", scale_value)
	instance.rotation_degrees.y = rotation_y
	for geometry in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := geometry as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source:
				var matte := source.duplicate() as StandardMaterial3D
				matte.roughness = maxf(matte.roughness, 0.68)
				matte.metallic = minf(matte.metallic, 0.35)
				matte.emission_enabled = false
				var material_name := source.resource_name.to_lower()
				if path.contains("human_"):
					if world_art_on:  # the boards' warm concrete, olive and gunmetal (spec addendum W6)
						for key in WorldArt.MODEL_PALETTE:
							if key in material_name:
								matte.albedo_color = Color(String(WorldArt.MODEL_PALETTE[key]))
								break
					elif "energy" in material_name:
						matte.albedo_color = Color("31545c")
					elif "olive" in material_name:
						matte.albedo_color = Color("59614e")
					elif "concrete" in material_name:
						matte.albedo_color = Color("777a70")
					elif "gunmetal" in material_name:
						matte.albedo_color = Color("333c40")
				mesh_instance.set_surface_override_material(surface, matte)
	return instance


func _box(parent: Node, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, material, pos, parent)


func _sphere(parent: Node, scale_value: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 7
	var instance := _mesh(mesh, material, pos, parent)
	instance.scale = scale_value
	return instance


func _cylinder(
	parent: Node,
	radius: float,
	height: float,
	pos: Vector3,
	material: Material,
	segments := 12
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.05
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(mesh, material, pos, parent)


func _beam(
	parent: Node,
	a: Vector3,
	b: Vector3,
	width: float,
	material: Material,
	height := -1.0
) -> MeshInstance3D:
	var midpoint := (a + b) * 0.5
	var length := a.distance_to(b)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width if height < 0.0 else height, length)
	var beam := _mesh(mesh, material, midpoint, parent)
	beam.look_at(b, Vector3.UP)
	return beam
