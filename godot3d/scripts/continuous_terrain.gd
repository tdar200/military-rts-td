extends Node3D
class_name ContinuousTerrain

var map_width := 0
var map_height := 0
var origin_x := 0.0
var origin_z := 0.0
var cell_x := 1.0
var cell_z := 1.0
var height_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var coast_noise := FastNoiseLite.new()


func configure(width: int, height: int, map_origin_x: float, map_origin_z: float, hex_x: float, hex_z: float, detail_texture: Texture2D) -> void:
	map_width = width
	map_height = height
	origin_x = map_origin_x
	origin_z = map_origin_z
	cell_x = hex_x
	cell_z = hex_z
	height_noise.seed = 8128
	height_noise.frequency = 0.055
	height_noise.fractal_octaves = 4
	height_noise.fractal_gain = 0.46
	height_noise.fractal_lacunarity = 1.9
	biome_noise.seed = 4317
	biome_noise.frequency = 0.038
	biome_noise.fractal_octaves = 3
	biome_noise.fractal_gain = 0.52
	coast_noise.seed = 99173
	coast_noise.frequency = 0.13
	coast_noise.fractal_octaves = 3
	coast_noise.fractal_gain = 0.5
	_build_surface(detail_texture)


func height_at_world(world_x: float, world_z: float) -> float:
	var gx := (world_x - origin_x) / cell_x
	var gz := (world_z - origin_z) / cell_z
	return _surface_height(gx, gz)


func biome_at_world(world_x: float, world_z: float) -> float:
	return biome_noise.get_noise_2d((world_x - origin_x) / cell_x, (world_z - origin_z) / cell_z)


func _land_height(gx: float, gz: float) -> float:
	var broad := height_noise.get_noise_2d(gx, gz)
	var rolling := smoothstep(-0.42, 0.60, broad) * 0.56
	var highland := smoothstep(0.28, 0.72, broad) * 0.58
	return rolling + highland


func _surface_height(gx: float, gz: float) -> float:
	var land := _land_height(gx, gz)
	var world_x := origin_x + gx * cell_x
	var world_z := origin_z + gz * cell_z
	if world_z >= 1.2 and world_z <= 18.8:
		var river_index := (world_z - 1.4) / 0.61
		var river_x := 11.8 + sin(river_index * 0.36) * 0.72
		var river_carve := 1.0 - smoothstep(0.22, 0.82, absf(world_x - river_x))
		land -= river_carve * 0.24
	var edge_distance := minf(minf(gx, float(map_width - 1) - gx), minf(gz, float(map_height - 1) - gz))
	var irregularity := coast_noise.get_noise_2d(gx, gz) * 0.72
	var shore := smoothstep(-1.45 + irregularity, 0.48 + irregularity, edge_distance)
	return lerpf(-0.72, land, shore)


func _biome_color(gx: float, gz: float, elevation: float) -> Color:
	var biome := biome_noise.get_noise_2d(gx, gz)
	if elevation < -0.12:
		return Color("756244")
	if elevation < 0.07:
		return Color("7d7866")
	if elevation > 0.72:
		return Color("62635d")
	var plains := Color("625f53")
	var grass := Color("485442")
	var meadow := Color("57634f")
	if biome < -0.18:
		return plains.lerp(grass, smoothstep(-0.34, -0.10, biome))
	return grass.lerp(meadow, smoothstep(0.05, 0.42, biome))


func _add_vertex(surface: SurfaceTool, gx: float, gz: float) -> void:
	var elevation := _surface_height(gx, gz)
	var world_x := origin_x + gx * cell_x
	var world_z := origin_z + gz * cell_z
	surface.set_color(_biome_color(gx, gz, elevation))
	surface.set_uv(Vector2(world_x, world_z) * 0.17)
	var epsilon := 0.05
	var dx := (_surface_height(gx + epsilon, gz) - _surface_height(gx - epsilon, gz)) / (2.0 * epsilon * cell_x)
	var dz := (_surface_height(gx, gz + epsilon) - _surface_height(gx, gz - epsilon)) / (2.0 * epsilon * cell_z)
	surface.set_normal(Vector3(-dx, 1.0, -dz).normalized())
	surface.add_vertex(Vector3(world_x, elevation, world_z))


func _terrain_material(detail_texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ground_color : source_color = vec4(0.22, 0.27, 0.20, 1.0);
uniform vec4 dry_color : source_color = vec4(0.34, 0.30, 0.24, 1.0);
varying vec3 world_position;
varying vec3 world_normal;
float ground_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ground_noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(ground_hash(i), ground_hash(i + vec2(1, 0)), f.x),
               mix(ground_hash(i + vec2(0, 1)), ground_hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
    vec3 detail = texture(detail_texture, UV).rgb;
    float detail_luma = dot(detail, vec3(0.299, 0.587, 0.114));
    vec3 micro = vec3(0.88 + detail_luma * 0.20);
    float cloud = sin(world_position.x * 0.19 + TIME * 0.035) * cos(world_position.z * 0.16 - TIME * 0.025);
    float cloud_light = mix(0.88, 1.02, smoothstep(-0.35, 0.42, cloud));
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    vec3 escarpment = vec3(0.10, 0.11, 0.10);
    float macro = sin(world_position.x * 0.43) * cos(world_position.z * 0.37) * 0.035;
    float patches = ground_noise(world_position.xz * 0.55) * 0.65 + ground_noise(world_position.xz * 2.2) * 0.25 + ground_noise(world_position.xz * 8.8) * 0.10;
    vec3 painted = mix(ground_color.rgb, dry_color.rgb, smoothstep(0.32, 0.68, patches)) * micro * (cloud_light + macro);
    ALBEDO = mix(painted, escarpment * micro, smoothstep(0.18, 0.58, slope) * 0.72);
    ROUGHNESS = mix(0.92, 1.0, slope);
    SPECULAR = 0.08;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("detail_texture", detail_texture)
	return material


func _build_surface(detail_texture: Texture2D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var subdivisions := 3
	var min_gx := -4.0
	var max_gx := float(map_width - 1) + 4.0
	var min_gz := -4.0
	var max_gz := float(map_height - 1) + 4.0
	var columns := int((max_gx - min_gx) * subdivisions)
	var rows := int((max_gz - min_gz) * subdivisions)
	for x_index in range(columns):
		for z_index in range(rows):
			var x0 := min_gx + float(x_index) / float(subdivisions)
			var x1 := min_gx + float(x_index + 1) / float(subdivisions)
			var z0 := min_gz + float(z_index) / float(subdivisions)
			var z1 := min_gz + float(z_index + 1) / float(subdivisions)
			_add_vertex(surface, x0, z0)
			_add_vertex(surface, x1, z0)
			_add_vertex(surface, x1, z1)
			_add_vertex(surface, x0, z0)
			_add_vertex(surface, x1, z1)
			_add_vertex(surface, x0, z1)
	surface.index()
	var terrain_mesh := surface.commit()
	var instance := MeshInstance3D.new()
	instance.name = "ContinuousPainterlyTerrain"
	instance.mesh = terrain_mesh
	instance.material_override = _terrain_material(detail_texture)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
