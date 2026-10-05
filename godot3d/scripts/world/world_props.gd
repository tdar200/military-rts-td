extends RefCounted
## Kestrel prop scatter (spec addendum W5). `plan` is pure and deterministic; `build` draws every prop with two
## MultiMeshes: camera-facing cards (trees, scrub, rocks, crystals) and flat decals (drop shadows, craters, pebbles, pads).

const ATLAS_PNG := "res://assets/world/props_atlas.png"
const ATLAS_JSON := "res://assets/world/props_atlas.json"
const TILE := 0.68
const PAD_SLOTS := 64
## glyph: [[sprite, every_n, min_tiles, max_tiles, jitter_tiles], ...]; a rule fires when hash % every_n == 0.
const RULES := {
	"t": [["forest", 1, 1.9, 2.6, 0.30], ["forest", 2, 1.5, 2.0, 0.45]],
	"g": [["scrub", 9, 0.8, 1.1, 0.35], ["forest", 23, 1.4, 1.8, 0.30]],
	"m": [["scrub", 6, 0.8, 1.1, 0.35]],
	"f": [["scrub", 7, 0.8, 1.0, 0.35], ["rock", 9, 0.9, 1.3, 0.35], ["forest_dry", 37, 1.4, 1.7, 0.30]],
	"h": [["rock", 3, 1.0, 1.7, 0.35]],
	"c": [["crater", 1, 1.5, 1.5, 0.0]],
	"w": [["pebbles", 1, 1.0, 1.0, 0.0]],
}
const BANK := ["forest", 6, 1.1, 1.5, 0.25]  # riverside willows on dry land next to river or ford
const BANK_GLYPHS := ["g", "m"]  # the grass bank only: the boards keep the dry flats bank open
const CRYSTALS := [[1.25, Vector2(0.0, 0.0)], [0.85, Vector2(0.25, 0.15)]]
const DECAL_SPRITES := ["crater", "pebbles", "shadow"]
const HIDDEN := Vector3(1e9, 0.0, 1e9)

var cards: MultiMeshInstance3D
var decals: MultiMeshInstance3D
var _meta: Dictionary = {}
var _decal_base := 0
var _free_pads: Array[int] = []
## CPU copies of every planned instance's ground point, so `clear_around` never reads the MultiMesh buffers back from
## the renderer (the dummy renderer keeps no transforms, and a GL buffer read stalls). Cleared slots move to HIDDEN.
var _card_at := PackedVector3Array()
var _decal_at := PackedVector3Array()


static func _hash(x: int, y: int, salt: int) -> int:
	return absi(((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff)


static func _neighbours(x: int, y: int) -> Array[Vector2i]:
	var odd := posmod(x, 2) == 1
	var out: Array[Vector2i] = [Vector2i(x, y - 1), Vector2i(x, y + 1)]
	for dx in [-1, 1]:
		out.append(Vector2i(x + dx, y if odd else y - 1))
		out.append(Vector2i(x + dx, y + 1 if odd else y))
	return out


static func _glyph(model, x: int, y: int) -> String:
	return String(model.glyph_at(clampi(x, 0, model.width - 1), clampi(y, 0, model.height - 1)))


static func _place(out: Array, rule: Array, x: int, y: int, salt: int, origin: Vector2, hex: Vector2) -> void:
	var h := _hash(x, y, salt)
	if h % int(rule[1]) != 0:
		return
	var t := float((h >> 8) % 1000) / 999.0
	var jitter := float(rule[4]) * TILE
	var jx := (float((h >> 12) % 1000) / 999.0 - 0.5) * 2.0 * jitter
	var jz := (float((h >> 20) % 1000) / 999.0 - 0.5) * 2.0 * jitter
	var centre := Vector2(origin.x + float(x) * hex.x, origin.y + float(y) * hex.y + (hex.y * 0.5 if posmod(x, 2) == 1 else 0.0))
	out.append({"sprite": String(rule[0]), "pos": centre + Vector2(jx, jz), "size": lerpf(float(rule[2]), float(rule[3]), t) * TILE,
		"flip": (h >> 3) & 1 == 1, "tile": Vector2i(x, y)})


static func plan(model, deposits: Array, origin: Vector2, hex: Vector2, margin: int) -> Array:
	var out: Array = []
	var deposit_tiles := {}
	for d in deposits:
		if d is Dictionary:
			deposit_tiles[Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))] = String(d.get("kind", "Ore"))
	for y in range(-margin, model.height + margin):
		for x in range(-margin, model.width + margin):
			var tile := Vector2i(x, y)
			if deposit_tiles.has(tile):
				continue
			var g := _glyph(model, x, y)
			var rules: Array = RULES.get(g, [])
			for k in rules.size():
				_place(out, rules[k], x, y, k + 1, origin, hex)
			if g in BANK_GLYPHS:
				for n in _neighbours(x, y):
					if _glyph(model, n.x, n.y) in ["r", "w"]:
						_place(out, BANK, x, y, 97, origin, hex)
						break
	for tile in deposit_tiles:
		var sprite := "alloy" if deposit_tiles[tile] == "Alloy" else "ore"
		var centre := Vector2(origin.x + float(tile.x) * hex.x, origin.y + float(tile.y) * hex.y + (hex.y * 0.5 if posmod(tile.x, 2) == 1 else 0.0))
		for c in CRYSTALS:
			out.append({"sprite": sprite, "pos": centre + c[1] * TILE, "size": float(c[0]) * TILE, "flip": false, "tile": tile})
	# one soft drop shadow per card, toward the lower right like the boards (the NW sun)
	var shadows: Array = []
	for item in out:
		if not String(item.sprite) in DECAL_SPRITES:
			shadows.append({"sprite": "shadow", "pos": item.pos + Vector2(0.16, 0.10) * item.size, "size": item.size * 0.9, "flip": false, "tile": item.tile})
	out.append_array(shadows)
	return out


func _load_meta() -> void:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))


func _rect(sprite: String, flip: bool) -> Color:
	var uv: Array = _meta.sprites[sprite].uv
	return Color(float(uv[0]) + float(uv[2]), float(uv[1]), -float(uv[2]), float(uv[3])) if flip else Color(float(uv[0]), float(uv[1]), float(uv[2]), float(uv[3]))


func build(parent: Node3D, items: Array, height_at: Callable) -> void:
	_load_meta()
	var atlas := load(ATLAS_PNG) as Texture2D
	var card_items := items.filter(func(i): return not String(i.sprite) in DECAL_SPRITES)
	var decal_items := items.filter(func(i): return String(i.sprite) in DECAL_SPRITES)
	cards = _multimesh(parent, "WorldPropCards", _card_material(atlas), _card_mesh(), card_items.size())
	decals = _multimesh(parent, "WorldPropDecals", _decal_material(atlas), _decal_mesh(), decal_items.size() + PAD_SLOTS)
	_card_at.resize(card_items.size())
	_decal_at.resize(decal_items.size())
	for i in card_items.size():
		var it: Dictionary = card_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var w: float = it.size
		var basis := Basis.from_scale(Vector3(w, w * float(s.aspect), 1.0))
		_card_at[i] = Vector3(it.pos.x, height_at.call(it.pos.x, it.pos.y), it.pos.y)
		cards.multimesh.set_instance_transform(i, Transform3D(basis, _card_at[i]))
		cards.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
		cards.multimesh.set_instance_color(i, Color(float(s.sink), 0.92 + float(_hash(it.tile.x, it.tile.y, i) % 16) / 100.0, 0, 1))
	for i in decal_items.size():
		var it: Dictionary = decal_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var basis := Basis.from_scale(Vector3(it.size, 1.0, it.size * float(s.aspect)))
		_decal_at[i] = Vector3(it.pos.x, height_at.call(it.pos.x, it.pos.y) + 0.035, it.pos.y)
		decals.multimesh.set_instance_transform(i, Transform3D(basis, _decal_at[i]))
		decals.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
	_decal_base = decal_items.size()
	_free_pads.clear()
	for k in range(PAD_SLOTS - 1, -1, -1):
		_free_pads.append(_decal_base + k)
		decals.multimesh.set_instance_transform(_decal_base + k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		decals.multimesh.set_instance_custom_data(_decal_base + k, _rect("shadow", false))


func clear_around(world: Vector3, radius: float) -> int:
	if cards == null or decals == null:
		return 0
	return _clear(cards.multimesh, _card_at, world, radius) + _clear(decals.multimesh, _decal_at, world, radius)


func _clear(mm: MultiMesh, at: PackedVector3Array, world: Vector3, radius: float) -> int:
	var hidden := 0
	var centre := Vector2(world.x, world.z)
	for i in at.size():
		if Vector2(at[i].x, at[i].z).distance_to(centre) < radius:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), at[i]))
			at[i] = HIDDEN
			hidden += 1
	return hidden


func add_pad(world: Vector3, width: float) -> int:
	if _free_pads.is_empty():
		return -1
	var slot: int = _free_pads.pop_back()
	var aspect := float(_meta.sprites["shadow"].aspect)
	var at := world + Vector3(0.08 * width, 0.03, 0.06 * width)
	decals.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3(width * 1.15, 1.0, width * 1.15 * aspect * 2.2)), at))
	return slot


func release_pad(slot: int) -> void:
	if slot < 0 or decals == null:
		return
	decals.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_free_pads.append(slot)


func _multimesh(parent: Node3D, node_name: String, material: Material, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _card_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.center_offset = Vector3(0, 0.5, 0)
	return q


func _decal_mesh() -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2.ONE
	return p


func _card_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.0;
varying vec4 rect;
varying float shade;
void vertex() {
    rect = INSTANCE_CUSTOM;
    shade = COLOR.g;
    VERTEX.y -= COLOR.r;  // sink the sprite's painted foot into the ground
    float sx = length(MODEL_MATRIX[0].xyz);
    float sy = length(MODEL_MATRIX[1].xyz);
    // camera-facing card: in an orthographic view the whole card has the depth of its base
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec4 c = texture(atlas, rect.xy + vec2(UV.x, UV.y) * rect.zw);
    ALBEDO = c.rgb * brightness * shade;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	return m


func _decal_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
varying vec4 rect;
void vertex() { rect = INSTANCE_CUSTOM; }
void fragment() {
    vec4 c = texture(atlas, rect.xy + UV * rect.zw);
    ALBEDO = c.rgb;
    ALPHA = c.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	return m
