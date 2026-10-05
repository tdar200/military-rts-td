extends RefCounted
## Kestrel ground and water channels baked into the terrain (spec addendum W3, W4). Pure data, no rendering.
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Terrain := preload("res://scripts/continuous_terrain.gd")


func _terrain() -> Node3D:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var m = GroundModel.from_snapshot(JSON.parse_string(f.get_as_text()))
	var terrain: Node3D = Terrain.new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, null)
	terrain.apply_ground(m)
	return terrain


func _at(terrain, x: int, y: int) -> Vector4:
	return terrain.extras_at_world(2.1 + float(x) * 0.68, 1.0 + float(y) * 0.70 + (0.35 if x % 2 else 0.0))


func test_rock_share_marks_the_ridge_only(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 33, 1).z > 0.9, "deep in Ironback Ridge is rock")
	t.ok(_at(terrain, 5, 9).z < 0.05, "Sunfield grass is not rock")
	terrain.free()


func test_sea_share_separates_sea_from_river(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 40, 22).y > 0.9, "Kestrel Bay is sea")
	t.ok(_at(terrain, 24, 11).y < 0.05, "the Calder River is not sea")
	t.ok(_at(terrain, 24, 11).x > 0.5, "but it is water")
	terrain.free()


func test_palette_is_calm_and_ordered(t) -> void:
	var look: Dictionary = Terrain.GROUND_LOOK
	var g := Color(String(look["g"][2]))
	var f := Color(String(look["f"][2]))
	var h := Color(String(look["h"][2]))
	t.ok(g.s < 0.55, "grass is olive, not saturated green (s %s)" % g.s)
	t.ok(f.s < 0.50, "the Dry Flats are sand, not orange (s %s)" % f.s)
	t.ok(f.get_luminance() > g.get_luminance(), "flats are lighter than grass")
	t.ok(h.s < 0.15, "the ridge is grey rock (s %s)" % h.s)
	t.ok(float(look["h"][0]) <= 0.80, "the ridge is low relief, not a 1.6 plateau")


## Reads the mip chain from the texture data (ImageTexture.has_mipmaps() asks the renderer, which is a dummy headless).
func _mips(texture: Texture2D) -> bool:
	return texture != null and texture.get_image() != null and texture.get_image().has_mipmaps()


func _material(terrain: Node3D) -> ShaderMaterial:
	return (terrain.get_node("ContinuousPainterlyTerrain") as MeshInstance3D).material_override as ShaderMaterial


## The painted ground samples its textures well below 1:1 (2 to 3.5 texels per pixel at zoom 10 to 18). The imported
## PNGs carry no mipmaps (shared with Survival), so the Kestrel path builds mipmapped copies.
func test_kestrel_ground_samples_mipmapped_textures(t) -> void:
	var detail: Texture2D = load("res://assets/terrain/painterly/continuous_ground_detail_v4.png")
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var m = GroundModel.from_snapshot(JSON.parse_string(f.get_as_text()))
	var terrain: Node3D = Terrain.new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, detail)
	terrain.apply_ground(m)
	var mat := _material(terrain)
	var d: Texture2D = mat.get_shader_parameter("detail_texture")
	var r: Texture2D = mat.get_shader_parameter("rock_texture")
	t.ok(_mips(d), "detail texture has mipmaps on the Kestrel path")
	t.ok(_mips(r), "rock texture has mipmaps on the Kestrel path")
	t.ok(d != null and d.get_size() == detail.get_size(), "same size as the source")
	var again: Node3D = Terrain.new()
	again.configure(44, 26, 2.1, 1.0, 0.68, 0.70, detail)
	again.apply_ground(m)
	t.ok(_material(again).get_shader_parameter("detail_texture") == d, "a live mipmapped copy is reused, not rebuilt")
	t.ok(not _mips(detail), "the imported texture itself is untouched")
	terrain.free()
	again.free()


func test_painted_ground_shader_parses_with_its_uniforms(t) -> void:
	var terrain: Node3D = Terrain.new()
	var shader := Shader.new()
	shader.code = terrain._ground_shader_code()
	var names: Array = shader.get_shader_uniform_list().map(func(u): return String(u.name))
	for want in ["detail_texture", "rock_texture", "detail_strength", "rotated_strength", "patch_strength", "rock_strength"]:
		t.ok(names.has(want), "painted ground shader compiles and exposes %s (got %s)" % [want, names])
	terrain.free()
