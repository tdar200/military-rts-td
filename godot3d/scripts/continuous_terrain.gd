extends Node3D
class_name ContinuousTerrain

const WorldArt := preload("res://scripts/world/world_art.gd")

var map_width := 0
var map_height := 0
var origin_x := 0.0
var origin_z := 0.0
var cell_x := 1.0
var cell_z := 1.0
var height_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var coast_noise := FastNoiseLite.new()
var ground: RefCounted = null  # GroundModel; null keeps the cosmetic noise terrain
var edge_margin_cells := 4.0  # mesh reach past the map; WorldArt.TERRAIN_MARGIN_CELLS once a ground model is applied
var _detail_texture: Texture2D

## Per-glyph look of the snapshot ground layer: base height, noise amplitude, sRGB colour, water flag.
const GROUND_LOOK := {
	"g": [0.20, 0.08, "6a9a3a", 0.0],
	"m": [0.20, 0.08, "97a64a", 0.0],
	"f": [0.05, 0.02, "c9923a", 0.0],
	"h": [1.60, 0.05, "6e747a", 0.0],
	"t": [0.30, 0.05, "2f8a52", 0.0],
	"r": [-0.50, 0.0, "3f86b8", 1.0],
	"w": [-0.15, 0.0, "6fb0c4", 1.0],
	"s": [0.05, 0.0, "c9b27a", 0.0],
	"o": [-0.80, 0.0, "2a6a9a", 1.0],
	"c": [-0.30, 0.0, "5b5346", 0.0],
}
const RASTER_STEP := 0.25
const RASTER_MARGIN := 11.0
const BLEND_RADIUS := 1.3
var _cell_h := PackedFloat32Array()
var _cell_amp := PackedFloat32Array()
var _cell_color := PackedColorArray()
var _cell_wet := PackedFloat32Array()
var _raster_h := PackedFloat32Array()
var _raster_c := PackedColorArray()  # rgb linear ground colour, alpha = water share
var _raster_cols := 0
var _raster_rows := 0


func configure(width: int, height: int, map_origin_x: float, map_origin_z: float, hex_x: float, hex_z: float, detail_texture: Texture2D) -> void:
	map_width = width
	map_height = height
	origin_x = map_origin_x
	origin_z = map_origin_z
	cell_x = hex_x
	cell_z = hex_z
	_detail_texture = detail_texture
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


## Drives the terrain from the snapshot ground layer: rebuilds the surface mesh once from the model. A null model leaves
## the noise terrain exactly as configure() built it.
func apply_ground(model: RefCounted) -> void:
	if model == null:
		return
	ground = model
	map_width = int(model.width)
	map_height = int(model.height)
	edge_margin_cells = float(WorldArt.TERRAIN_MARGIN_CELLS)
	_bake_ground()
	var old := get_node_or_null("ContinuousPainterlyTerrain")
	if old != null:
		remove_child(old)
		old.free()
	_build_surface(_detail_texture)


func height_at_world(world_x: float, world_z: float) -> float:
	var gx := (world_x - origin_x) / cell_x
	var gz := (world_z - origin_z) / cell_z
	return _surface_height(gx, gz)


func biome_at_world(world_x: float, world_z: float) -> float:
	if ground != null:
		return _ground_biome((world_x - origin_x) / cell_x, (world_z - origin_z) / cell_z)
	return biome_noise.get_noise_2d((world_x - origin_x) / cell_x, (world_z - origin_z) / cell_z)


func _land_height(gx: float, gz: float) -> float:
	var broad := height_noise.get_noise_2d(gx, gz)
	var rolling := smoothstep(-0.42, 0.60, broad) * 0.56
	var highland := smoothstep(0.28, 0.72, broad) * 0.58
	return rolling + highland


func _surface_height(gx: float, gz: float) -> float:
	if ground != null:
		return _raster_sample_height(gx, gz)
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
	surface.set_color(_raster_sample_color(gx, gz) if ground != null else _biome_color(gx, gz, elevation))
	surface.set_uv(Vector2(world_x, world_z) * 0.17)
	var epsilon := 0.05
	var dx := (_surface_height(gx + epsilon, gz) - _surface_height(gx - epsilon, gz)) / (2.0 * epsilon * cell_x)
	var dz := (_surface_height(gx, gz + epsilon) - _surface_height(gx, gz - epsilon)) / (2.0 * epsilon * cell_z)
	surface.set_normal(Vector3(-dx, 1.0, -dz).normalized())
	surface.add_vertex(Vector3(world_x, elevation, world_z))


func _terrain_material(detail_texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _ground_shader_code() if ground != null else _noise_shader_code()
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("detail_texture", detail_texture)
	return material


func _noise_shader_code() -> String:
	return """
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


## Snapshot-driven look: vertex colour is the ground palette, vertex alpha the water share (River, Ford, Sea).
func _ground_shader_code() -> String:
	return """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
    vec3 micro = vec3(0.90 + detail_luma * 0.16);
    float patches = ground_noise(world_position.xz * 0.9) * 0.6 + ground_noise(world_position.xz * 3.6) * 0.4;
    float water = smoothstep(0.42, 0.62, COLOR.a);
    float ripple = sin(world_position.x * 3.1 + TIME * 0.7) * cos(world_position.z * 2.7 - TIME * 0.5);
    vec3 land = COLOR.rgb * micro * (0.90 + patches * 0.20);
    vec3 wet = COLOR.rgb * (0.92 + ripple * 0.05 + patches * 0.08);
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    vec3 shaded = mix(land, land * 0.62, smoothstep(0.25, 0.65, slope) * 0.6);
    ALBEDO = mix(shaded, wet, water);
    ROUGHNESS = mix(0.95, 0.18, water);
    SPECULAR = mix(0.08, 0.55, water);
}
"""


func _build_surface(detail_texture: Texture2D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var subdivisions := 3
	var min_gx := -edge_margin_cells
	var max_gx := float(map_width - 1) + edge_margin_cells
	var min_gz := -edge_margin_cells
	var max_gz := float(map_height - 1) + edge_margin_cells
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


# ---- snapshot ground layer ----

func _bake_ground() -> void:
	var count := map_width * map_height
	_cell_h.resize(count)
	_cell_amp.resize(count)
	_cell_color.resize(count)
	_cell_wet.resize(count)
	for y in range(map_height):
		for x in range(map_width):
			var look: Array = GROUND_LOOK.get(ground.glyph_at(x, y), GROUND_LOOK["g"])
			var i := y * map_width + x
			_cell_h[i] = float(look[0])
			_cell_amp[i] = float(look[1])
			_cell_color[i] = Color(String(look[2])).srgb_to_linear()
			_cell_wet[i] = float(look[3])
	_raster_cols = int((float(map_width - 1) + 2.0 * RASTER_MARGIN) / RASTER_STEP) + 1
	_raster_rows = int((float(map_height - 1) + 2.0 * RASTER_MARGIN) / RASTER_STEP) + 1
	_raster_h.resize(_raster_cols * _raster_rows)
	_raster_c.resize(_raster_cols * _raster_rows)
	for row in range(_raster_rows):
		var gz := -RASTER_MARGIN + float(row) * RASTER_STEP
		for col in range(_raster_cols):
			var gx := -RASTER_MARGIN + float(col) * RASTER_STEP
			var blend := _blend_cells(gx, gz)
			_raster_h[row * _raster_cols + col] = blend[0]
			_raster_c[row * _raster_cols + col] = Color(blend[1], blend[2], blend[3], blend[4])


## Distance-weighted blend of the hex cells around a point: [height, r, g, b, water share]. Off-map cells continue the
## nearest edge cell, so land and sea run past the frame (spec addendum W3).
func _blend_cells(gx: float, gz: float) -> Array:
	var total := 0.0
	var height_sum := 0.0
	var amp_sum := 0.0
	var color_sum := Color(0, 0, 0, 0)
	var wet_sum := 0.0
	var col0 := roundi(gx)
	for c in range(col0 - 1, col0 + 2):
		var offset := 0.5 if posmod(c, 2) == 1 else 0.0
		var row0 := roundi(gz - offset)
		for r in range(row0 - 1, row0 + 2):
			var d := Vector2(gx - float(c), gz - (float(r) + offset)).length()
			if d >= BLEND_RADIUS:
				continue
			var w := 1.0 - d / BLEND_RADIUS
			w *= w
			var cc := clampi(c, 0, map_width - 1)
			var rr := clampi(r, 0, map_height - 1)
			var i := rr * map_width + cc
			var h := _cell_h[i]
			var amp := _cell_amp[i]
			var color := _cell_color[i]
			var wet := _cell_wet[i]
			total += w
			height_sum += h * w
			amp_sum += amp * w
			color_sum += color * w
			wet_sum += wet * w
	if total <= 0.0:
		return [-0.8, 0.0, 0.0, 0.0, 1.0]
	var inv := 1.0 / total
	var noise := height_noise.get_noise_2d(gx, gz)
	return [height_sum * inv + noise * amp_sum * inv, color_sum.r * inv, color_sum.g * inv, color_sum.b * inv, wet_sum * inv]


func _raster_index(gx: float, gz: float) -> Array:
	var fx := clampf((gx + RASTER_MARGIN) / RASTER_STEP, 0.0, float(_raster_cols - 1) - 0.0001)
	var fz := clampf((gz + RASTER_MARGIN) / RASTER_STEP, 0.0, float(_raster_rows - 1) - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	return [iz * _raster_cols + ix, fx - float(ix), fz - float(iz)]


func _raster_sample_height(gx: float, gz: float) -> float:
	var at := _raster_index(gx, gz)
	var i: int = at[0]
	var tx: float = at[1]
	var tz: float = at[2]
	var top := lerpf(_raster_h[i], _raster_h[i + 1], tx)
	var bottom := lerpf(_raster_h[i + _raster_cols], _raster_h[i + _raster_cols + 1], tx)
	return lerpf(top, bottom, tz)


func _raster_sample_color(gx: float, gz: float) -> Color:
	var at := _raster_index(gx, gz)
	var i: int = at[0]
	var tx: float = at[1]
	var tz: float = at[2]
	var top := _raster_c[i].lerp(_raster_c[i + 1], tx)
	var bottom := _raster_c[i + _raster_cols].lerp(_raster_c[i + _raster_cols + 1], tx)
	return top.lerp(bottom, tz)


## Stand-in for the biome noise so tile dressing (trees, rocks) follows the ground classes.
func _ground_biome(gx: float, gz: float) -> float:
	var col := clampi(roundi(gx), 0, map_width - 1)
	var row := clampi(roundi(gz - (0.5 if col % 2 == 1 else 0.0)), 0, map_height - 1)
	match String(ground.glyph_at(col, row)):
		"t":
			return -0.5
		"m":
			return 0.4
		"f":
			return -0.3
	return 0.0
