extends RefCounted
## Kestrel prop scatter (spec addendum W5). `plan` is pure and deterministic; `build` draws every prop with two
## MultiMeshes: camera-facing cards (trees, scrub, rocks, crystals) and flat decals (drop shadows, craters, pebbles, pads).

const FogView := preload("res://scripts/world/fog_view.gd")
const ATLAS_PNG := "res://assets/world/props_atlas.png"
const ATLAS_JSON := "res://assets/world/props_atlas.json"
const TILE := 0.68
const PAD_SLOTS := 64
## glyph: [[sprite, every_n, min_tiles, max_tiles, jitter_tiles], ...]; a rule fires when hash % every_n == 0.
const RULES := {
	"t": [["forest", 1, 1.7, 2.8, 0.48], ["forest", 2, 1.3, 2.2, 0.70]],
	"g": [["scrub", 9, 0.8, 1.1, 0.35], ["forest", 23, 1.4, 1.8, 0.30]],
	"m": [["scrub", 6, 0.8, 1.1, 0.35]],
	"f": [["scrub", 7, 0.8, 1.0, 0.35], ["rock", 9, 0.9, 1.3, 0.35], ["forest_dry", 37, 1.4, 1.7, 0.30]],
	"h": [["rock", 3, 1.0, 1.7, 0.35]],
	"c": [["crater", 1, 1.5, 1.5, 0.0]],
	"w": [["pebbles", 1, 1.0, 1.0, 0.0]],
}
const BANK := ["forest", 6, 1.1, 1.5, 0.25]  # riverside willows on dry land next to river or ford
const BANK_GLYPHS := ["g", "m"]  # the grass bank only: the boards keep the dry flats bank open
const FRINGE := ["forest", 2, 1.3, 2.0, 0.45]  # canopies on about half the grass rim of a wood, so it never reads as a block
const FRINGE_GLYPHS := ["g", "m"]
const CRYSTALS := [[1.25, Vector2(0.0, 0.0)], [0.85, Vector2(0.25, 0.15)]]
const DECAL_SPRITES := ["crater", "pebbles", "shadow"]
const TREE_SPRITES := ["forest", "forest_dry"]
const CRYSTAL_SPRITES := ["ore", "alloy"]  # deposit markers: never cleared, a deposit must stay visible
const HIDDEN := Vector3(1e9, 0.0, 1e9)
const SHADOW_OFFSET := Vector2(0.16, 0.10)  # times the card width, toward the lower right (the NW sun)
const SHADOW_SCALE := 0.9
## A mined-out deposit keeps its crystals, darker (shade times SPENT_SHADE) and greyed (COLOR.b, 0 for every live card).
const SPENT_SHADE := 0.55
const SPENT_GREY := 0.85
## The card shader turns each quad to the camera, so its pixels can leave the quad's own box by up to a card size
## (2.6 tiles at most). One node spans the whole map, so there is no visibility range (it would pop every prop at once).
const CARD_CULL_MARGIN := 2.0

var cards: MultiMeshInstance3D
var decals: MultiMeshInstance3D
var _meta: Dictionary = {}
var _decal_base := 0
var _free_pads: Array[int] = []
var _pad_xf: Dictionary = {}  # CPU mirror of the pad slots' transforms (slot -> Transform3D), like _card_at
## CPU copies of every planned instance's ground point, so `clear_around` never reads the MultiMesh buffers back from
## the renderer (the dummy renderer keeps no transforms, and a GL buffer read stalls). Cleared slots move to HIDDEN.
## A drop shadow is keyed by the foot of its card.
var _card_at := PackedVector3Array()
var _decal_at := PackedVector3Array()
## 1 for deposit crystals and their shadows (a deposit tile carries nothing else), which clear_around never hides.
var _card_pinned := PackedByteArray()
var _decal_pinned := PackedByteArray()
## CPU copy of each card's instance colour (r foot sink, g shade, b grey), the crystal cards of each deposit tile, and
## the deposit tiles already shown as spent.
var _card_color := PackedColorArray()
var _crystal_cards: Dictionary = {}
var _crystal_decals: Dictionary = {}  # deposit tile -> indices of its crystals' drop shadows
var _decal_color := PackedColorArray()  # CPU mirror of the decal instance colours (white unless a spent shadow fades)
var _spent: Dictionary = {}


static func _hash(x: int, y: int, salt: int) -> int:
	return absi(((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff)


## An integer finaliser (two multiply-xorshift rounds): turns one tile hash into independent draws per property.
static func _mix(v: int) -> int:
	v = ((v >> 16) ^ v) * 0x45d9f3b & 0xffffffff
	v = ((v >> 16) ^ v) * 0x45d9f3b & 0xffffffff
	return (v >> 16) ^ v


## A uniform draw in [0, 1] for one property (`axis`) of a rule that fired with hash `h`.
static func _draw(h: int, axis: int) -> float:
	return float(_mix(h + axis * 0x9e3779b) % 1000) / 999.0


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
	var t := _draw(h, 1)
	var jitter := float(rule[4]) * TILE
	var jx := (_draw(h, 2) - 0.5) * 2.0 * jitter
	var jz := (_draw(h, 3) - 0.5) * 2.0 * jitter
	var centre := Vector2(origin.x + float(x) * hex.x, origin.y + float(y) * hex.y + (hex.y * 0.5 if posmod(x, 2) == 1 else 0.0))
	out.append({"sprite": String(rule[0]), "pos": centre + Vector2(jx, jz), "size": lerpf(float(rule[2]), float(rule[3]), t) * TILE,
		"flip": _draw(h, 4) >= 0.5, "tile": Vector2i(x, y)})


## Tiles where no card may stand: the wave route, every ford tile and the ford's approach (its neighbours). Opaque cards
## write depth, so a tree there would hide the route dashes, units and rings behind it.
static func keep_out(model, wave_route: Array) -> Dictionary:
	var out := {}
	for step in wave_route:
		if step is Array and step.size() >= 2:
			out[Vector2i(int(step[0]), int(step[1]))] = true
	for y in model.height:
		for x in model.width:
			if String(model.glyph_at(x, y)) == "w":
				out[Vector2i(x, y)] = true
				for n in _neighbours(x, y):
					out[n] = true
	return out


## `keep_out` tiles get decals only (pebbles, craters); their neighbours get no trees or willows, except a forest tile,
## which keeps its canopy. A deposit's own crystals are placed whatever the keep-out says.
static func plan(model, deposits: Array, origin: Vector2, hex: Vector2, margin: int, keep: Dictionary = {}) -> Array:
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
			var blocked := keep.has(tile)
			var beside := false
			if not blocked and g != "t":
				for n in _neighbours(x, y):
					if keep.has(n):
						beside = true
						break
			var rules: Array = RULES.get(g, [])
			for k in rules.size():
				var sprite := String(rules[k][0])
				if (blocked and not sprite in DECAL_SPRITES) or (beside and sprite in TREE_SPRITES):
					continue
				_place(out, rules[k], x, y, k + 1, origin, hex)
			if g in FRINGE_GLYPHS and not blocked and not beside:
				for n in _neighbours(x, y):
					if _glyph(model, n.x, n.y) == "t":
						_place(out, FRINGE, x, y, 89, origin, hex)
						break
			if g in BANK_GLYPHS and not blocked and not beside:
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
			shadows.append({"sprite": "shadow", "pos": item.pos + SHADOW_OFFSET * item.size, "size": item.size * SHADOW_SCALE, "flip": false, "tile": item.tile})
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
	cards.extra_cull_margin = CARD_CULL_MARGIN
	decals = _multimesh(parent, "WorldPropDecals", _decal_material(atlas), _decal_mesh(), decal_items.size() + PAD_SLOTS)
	_card_at.resize(card_items.size())
	_decal_at.resize(decal_items.size())
	_card_pinned.resize(card_items.size())
	_decal_pinned.resize(decal_items.size())
	_card_color.resize(card_items.size())
	_decal_color.resize(decal_items.size())
	_crystal_cards.clear()
	_crystal_decals.clear()
	_spent.clear()
	var crystal_tiles := {}
	for i in card_items.size():
		if String(card_items[i].sprite) in CRYSTAL_SPRITES:
			crystal_tiles[card_items[i].tile] = true
			if not _crystal_cards.has(card_items[i].tile):
				_crystal_cards[card_items[i].tile] = []
			_crystal_cards[card_items[i].tile].append(i)
	for i in card_items.size():
		var it: Dictionary = card_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var w: float = it.size
		var basis := Basis.from_scale(Vector3(w, w * float(s.aspect), 1.0))
		_card_at[i] = Vector3(it.pos.x, height_at.call(it.pos.x, it.pos.y), it.pos.y)
		_card_pinned[i] = 1 if String(it.sprite) in CRYSTAL_SPRITES else 0
		cards.multimesh.set_instance_transform(i, Transform3D(basis, _card_at[i]))
		cards.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
		_card_color[i] = Color(float(s.sink), 0.92 + float(_hash(it.tile.x, it.tile.y, i) % 16) / 100.0, 0, 1)
		cards.multimesh.set_instance_color(i, _card_color[i])
	for i in decal_items.size():
		var it: Dictionary = decal_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var basis := Basis.from_scale(Vector3(it.size, 1.0, it.size * float(s.aspect)))
		var at := Vector3(it.pos.x, decal_height(height_at, it.pos, float(it.size)), it.pos.y)
		decals.multimesh.set_instance_transform(i, Transform3D(basis, at))
		# a drop shadow is cleared with its card, so it is keyed by the card's foot, not its own offset centre
		var foot: Vector2 = it.pos - SHADOW_OFFSET * float(it.size) / SHADOW_SCALE if String(it.sprite) == "shadow" else it.pos
		_decal_at[i] = Vector3(foot.x, at.y, foot.y)
		_decal_pinned[i] = 1 if String(it.sprite) == "shadow" and crystal_tiles.has(it.tile) else 0
		if _decal_pinned[i] == 1:
			if not _crystal_decals.has(it.tile):
				_crystal_decals[it.tile] = []
			_crystal_decals[it.tile].append(i)
		_decal_color[i] = Color.WHITE
		decals.multimesh.set_instance_color(i, Color.WHITE)
		decals.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
	_decal_base = decal_items.size()
	_free_pads.clear()
	_pad_xf.clear()
	for k in range(PAD_SLOTS - 1, -1, -1):
		_free_pads.append(_decal_base + k)
		decals.multimesh.set_instance_transform(_decal_base + k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		decals.multimesh.set_instance_custom_data(_decal_base + k, _rect("shadow", false))
		decals.multimesh.set_instance_color(_decal_base + k, Color.WHITE)


## A flat decal rests a hair above the highest ground under its centre and its four half-width points, so a crater
## decal clears the crater's own rim and a drop shadow on a slope never cuts into the hill.
static func decal_height(height_at: Callable, pos: Vector2, size: float) -> float:
	var h: float = height_at.call(pos.x, pos.y)
	var r := size * 0.5
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		h = maxf(h, float(height_at.call(pos.x + d.x, pos.y + d.y)))
	return h + 0.035


func clear_around(world: Vector3, radius: float) -> int:
	if cards == null or decals == null:
		return 0
	return _clear(cards.multimesh, _card_at, _card_pinned, world, radius) + _clear(decals.multimesh, _decal_at, _decal_pinned, world, radius)


func _clear(mm: MultiMesh, at: PackedVector3Array, pinned: PackedByteArray, world: Vector3, radius: float) -> int:
	var hidden := 0
	var centre := Vector2(world.x, world.z)
	for i in at.size():
		if pinned[i] == 0 and Vector2(at[i].x, at[i].z).distance_to(centre) < radius:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			at[i] = HIDDEN
			hidden += 1
	return hidden


## Dims and greys the crystals of every deposit tile that is no longer live (absent from `live_deposits`, the snapshot's
## list, or at zero). Each tile changes once; returns how many cards changed.
func mark_spent(live_deposits: Array) -> int:
	if cards == null:
		return 0
	var live := {}
	for d in live_deposits:
		if d is Dictionary and int(d.get("remaining", 0)) > 0:
			live[Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))] = true
	var changed := 0
	for tile in _crystal_cards:
		if live.has(tile) or _spent.has(tile):
			continue
		_spent[tile] = true
		for i in _crystal_cards[tile]:
			var c := _card_color[i]
			_card_color[i] = Color(c.r, c.g * SPENT_SHADE, SPENT_GREY, c.a)
			cards.multimesh.set_instance_color(i, _card_color[i])
			changed += 1
		for i in _crystal_decals.get(tile, []):  # the drop shadow fades with its darker crystal
			_decal_color[i] = Color(1, 1, 1, SPENT_SHADE)
			decals.multimesh.set_instance_color(i, _decal_color[i])
	return changed


## Kestrel fog of war: both prop layers shade by the FogView mask `texture` while `enabled` (a card by its foot, so a
## tree is shrouded whole; a decal per point, like the ground). Off, they draw exactly as without fog.
func set_fog(texture: Texture2D, enabled: bool, grid := Vector4(2.1, 1.0, 0.68, 0.70), cells := Vector2(44, 26)) -> void:
	for mmi in [cards, decals]:
		if mmi == null or not mmi.material_override is ShaderMaterial:
			continue
		var m: ShaderMaterial = mmi.material_override
		m.set_shader_parameter("fog_enabled", 1.0 if enabled and texture != null else 0.0)
		m.set_shader_parameter("fog_grid", grid)
		m.set_shader_parameter("fog_cells", cells)
		if texture != null:
			m.set_shader_parameter("fog_mask", texture)


func add_pad(world: Vector3, width: float) -> int:
	if _free_pads.is_empty():
		return -1
	var slot: int = _free_pads.pop_back()
	var aspect := float(_meta.sprites["shadow"].aspect)
	var at := world + Vector3(0.08 * width, 0.03, 0.06 * width)
	_pad_xf[slot] = Transform3D(Basis.from_scale(Vector3(width * 1.15, 1.0, width * 1.15 * aspect * 2.2)), at)
	decals.multimesh.set_instance_transform(slot, _pad_xf[slot])
	return slot


## The transform a pad slot was given (collapsed when free); readable without a renderer.
func pad_transform(slot: int) -> Transform3D:
	return _pad_xf.get(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func release_pad(slot: int) -> void:
	if slot < 0 or not is_instance_valid(decals):  # a building can leave the tree with the whole scene
		return
	decals.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_pad_xf.erase(slot)
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
""" + FogView.SHADER_FUNCTIONS + """
varying vec4 rect;
varying float shade;
varying float grey;
varying vec2 fog_xz;
void vertex() {
    rect = INSTANCE_CUSTOM;
    fog_xz = MODEL_MATRIX[3].xz;  // the card's foot: a tree is shrouded whole
    shade = COLOR.g;
    grey = COLOR.b;  // 0 on every live card; a spent deposit's crystals fade toward grey
    VERTEX.y -= COLOR.r;  // sink the sprite's painted foot into the ground
    float sx = length(MODEL_MATRIX[0].xyz);
    float sy = length(MODEL_MATRIX[1].xyz);
    // camera-facing card: in an orthographic view the whole card has the depth of its base
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec4 c = texture(atlas, rect.xy + vec2(UV.x, UV.y) * rect.zw);
    vec3 albedo = mix(c.rgb, vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), grey) * brightness * shade;
    if (fog_enabled > 0.5) {
        albedo = fog_tint(albedo, fog_at(fog_xz));
    }
    ALBEDO = albedo;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("fog_enabled", 0.0)
	return m


func _decal_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
""" + FogView.SHADER_FUNCTIONS + """
varying vec4 rect;
varying float fade;
varying vec2 fog_xz;
void vertex() {
    rect = INSTANCE_CUSTOM;
    fade = COLOR.a;  // instance alpha: 1, or SPENT_SHADE for a spent deposit's crystal shadows
    fog_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
    vec4 c = texture(atlas, rect.xy + UV * rect.zw);
    vec3 albedo = c.rgb;
    if (fog_enabled > 0.5) {
        albedo = fog_tint(albedo, fog_at(fog_xz));
    }
    ALBEDO = albedo;
    ALPHA = c.a * fade;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("fog_enabled", 0.0)
	m.render_priority = -1  # one sort key spans the map: blend under the grid, territory and hover overlays
	return m
