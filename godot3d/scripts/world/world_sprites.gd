extends RefCounted
## Kestrel sprite entities (plan 2026-10-05-kestrel-sprite-entities; reverses spec addendum W6 on the user's call): every
## building is the boards' own painted sprite on a card that faces the fixed north-up Kestrel camera, drawn at the boards'
## pixel size. earthfront_3d.gd uses it only when `world_art_on` is true; Survival keeps its models.
##
## Scale: the boards draw land.jpg 1:1 (3600 x 2400 px), and land.jpg maps one hex column (WorldArt.TILE) to 82 px, so a
## sprite drawn `w` px wide on a board is w / 82 tiles wide (the whole 256 px card, transparent margin included).
## Anchor: the boards sort sprites by `top + w * 0.85` and hang their drop shadows from the 84 % line, so the painted
## ground contact is FOOT of the card height below its top; that line sits on the entity's root.
##
## The card mesh folds at the contact line: above it a quad square to the view direction (so it shows the painting
## undistorted and has one depth, the root's, like the boards' painter order), below it a strip lying on the ground (so the
## painted base in front of the root is never buried by the terrain, and anything standing on it draws over it).

const WorldArt := preload("res://scripts/world/world_art.gd")

const DIR := "res://assets/world/sprites/%s.png"
const PX_PER_TILE := 82.0
const FOOT := 0.85
const ASPECT := 1.0  # every mock sprite is 256 x 256
const CARD_LIFT := 0.03  # the card's ground strip rides this far over the terrain under the root
const OPAQUE_ALPHA := 128  # a pixel above this alpha is painted body (picking, bars, pad); softer pixels are edge glow
const MASK_CELLS := 64  # the paint mask's grid (a 256 px sprite: 4 px cells)
const FOOTPRINT := 0.65  # the painted footprint's centre line, as a fraction of the card height from its top
## A construction site draws its own building's painting revealed from the painted base up by the build progress (the
## user read the boards' shared foundation slab as a ruin). The built part takes a faint scaffold tint, the rest stands as
## a faint scaffold lattice over the painting's silhouette.
const SITE_TINT := 0.18  # the built part's pull toward SITE_SCAFFOLD
const SITE_SCAFFOLD := Color(0.62, 0.56, 0.40)
const SITE_LATTICE := 0.52  # the unbuilt lattice's alpha
const SITE_PICK_FLOOR := 0.15  # a fresh site picks by at least this share of its body, from the base up
## The placement ghost: the armed kind's painting, pulled GHOST_TINT toward the validity colour, at GHOST_OPACITY.
const GHOST_TINT := 0.62
const GHOST_OPACITY := 0.6
## The boards' cast shadow (hud.css `.shd`, drawn at the sprite's `sh` opacity): the sprite's silhouette, black, flipped
## below its contact line, squashed to SHADOW_SCALE of its height and sheared by SHADOW_SHEAR toward the lower right
## (skewX(60deg) scaleY(-.34)), at opacity .40 * .52, blurred (a coarser mip level stands in for the 4 px blur).
const SHADOW_SCALE := 0.34
const SHADOW_SHEAR := 0.589  # tan(60 degrees) * SHADOW_SCALE: screen x per unit of height above the contact line
## The Kestrel post chain lifts dark ground (filmic shoulder, saturation 0.5, the gSun overlay), so both board shadows
## (.shd here, .ao below) are drawn this much stronger than the boards' CSS opacity to read as dark on screen.
const SHADOW_GAIN := 1.6
const SHADOW_ALPHA := 0.208 * SHADOW_GAIN
const SHADOW_LOD := 2.0

## Board pixel widths (Main.dc.html, BuildDeck, StructureSelected, OrdersArmed, WaveInbound, CoreAssault). Battery is the
## board's second, smaller power plant; SupplyDepot is 170 (the boards' depot slot size); the
## AntimatterPlant has no board: 190, so its painting (the power plant's base at 0.86 under a taller core) stands a
## little over the power plant's 170. Units (WorldArt.UNIT_TILES): infantry 80 (every board but
## CoreAssault's 90), tank 140, anti-armour 90 (CoreAssault 100), gunship 190 (CoreAssault, WaveInbound), capital 330
## (CoreAssault's alien capital; the human one takes the same), harvester 110 (Main's second one 105).
const MOCK_PX := {
	"CommandCenter": 250, "PowerPlant": 170, "Battery": 160, "Refinery": 200, "Barracks": 200, "VehicleFactory": 200,
	"Airfield": 200, "ResearchLab": 150, "GunTurret": 115, "AaTurret": 85, "Wall": 100, "SupplyDepot": 170,
	"AntimatterPlant": 190,
	"Infantry": 80, "Tank": 140, "AntiArmor": 90, "Helicopter": 190, "Capital": 330, "Harvester": 110,
}
## kind -> [human sprite, enemy sprite]. The boards paint seven building kinds per side (CC, power plant, refinery,
## barracks, gun turret, AA turret, wall); the other six (vehicle factory, airfield, battery, antimatter plant, supply
## depot, research lab) take the variants tools/ui/build_building_variants.py composites from crops of the boards'
## sprites: no two kinds, and no two sides, share a painting.
const SPRITES := {
	"CommandCenter": ["command_center_v2", "alien_command_center_v1"],
	"PowerPlant": ["power_plant_v2", "alien_power_plant_v1"],
	"Battery": ["battery_v1", "alien_battery_v1"],
	"AntimatterPlant": ["antimatter_plant_v1", "alien_antimatter_plant_v1"],
	"Refinery": ["refinery_v2", "alien_refinery_v1"],
	"SupplyDepot": ["supply_depot_v1", "alien_supply_depot_v1"],
	"Barracks": ["barracks_v2", "alien_barracks_v1"],
	"VehicleFactory": ["vehicle_factory_v1", "alien_vehicle_factory_v1"],
	"Airfield": ["airfield_v1", "alien_airfield_v1"],
	"ResearchLab": ["research_lab_v1", "alien_research_lab_v1"],
	"GunTurret": ["gun_turret_v2", "alien_gun_turret_v1"],
	"AaTurret": ["aa_turret_v2", "alien_aa_turret_v1"],
	"Wall": ["wall_v2", "alien_wall_v1"],
	# units: one sprite per entity (the infantry sprite is itself the boards' three-figure squad)
	"Infantry": ["infantry_v2", "alien_infantry_v1"],
	"Tank": ["tank_v2", "alien_tank_v1"],
	"AntiArmor": ["anti_armor_v2", "alien_anti_armor_v1"],
	"Helicopter": ["helicopter_v2", "alien_helicopter_v1"],
	"Capital": ["capital_v1", "alien_capital_v1"],
	"Harvester": ["harvester_v2", "alien_harvester_v1"],
}
## earthfront_3d._create_unit's kind index -> the catalogue's unit kind (the bridge's own kind names).
const UNIT_KINDS := ["Infantry", "Tank", "AntiArmor", "Helicopter", "Capital", "Harvester"]
## The way each unit painting faces on screen: -1 left, 1 right, 0 head-on (never mirrored). A unit moving the other way
## shows the painting mirrored; a stopped one keeps its last facing. The boards draw every unit as painted (no mirror).
const FACING := {
	"infantry_v2": -1, "tank_v2": -1, "anti_armor_v2": -1, "helicopter_v2": -1, "capital_v1": -1, "harvester_v2": -1,
	"alien_infantry_v1": 1, "alien_tank_v1": -1, "alien_anti_armor_v1": 1, "alien_helicopter_v1": 0,
	"alien_capital_v1": 0, "alien_harvester_v1": -1,
}
const FACING_DEADBAND := 0.02  # world units of horizontal motion below which a unit keeps its facing (a move straight north)
## The boards' contact band under every sprite (hud.css `.ao`): the silhouette, black, squashed to AO_SCALE of its height
## about the contact line, AO_DROP lower (3 px on a board unit about 120 px wide), blurred 6 px, at opacity AO_ALPHA. The
## blur is a coarse mip level across and a 7-tap Gaussian along the squashed axis (6 px there is AO_SIGMA of the
## painting's height); the band reaches AO_MARGIN past the painting on each side so the blur has room.
const AO_SCALE := 0.13
const AO_DROP := 0.025
const AO_ALPHA := minf(1.0, 0.6 * SHADOW_GAIN)
const AO_SIGMA := 0.38
const AO_LOD := 4.5
const AO_MARGIN := Vector2(0.15, 0.76)  # in card u and v: about two blur sigmas
## The cards' pre-grade (Image.adjust_bcs: multiply, contrast about mid grey, saturation about the pixel mean). The Kestrel
## post chain (filmic, exposure 0.95, saturation 0.50, the gSun overlay) draws a sprite lighter and greyer than the boards
## do; the cards sample a copy graded by this so the painting reads on screen as on the boards. Cards only: the shadows
## read the sprite's alpha, the props atlas and the ground keep their own grade.
const GRADE := {"brightness": 0.80, "contrast": 1.02, "saturation": 1.60}
## Unit kinds drawn in the air: the card rides this far (world units, vertical) over its ground lift, its cast shadow
## and contact band stay on the ground under it.
const HOVER := {"Helicopter": 0.30}
## Profile kinds that keep their fitted 3D model (none today); any kind outside SPRITES falls back the same way.
const NO_SPRITE: Array[String] = []

## Sprite name -> true: treated as missing. A load that fails records itself here (the entity keeps its model, warned
## once); the tests set it to stand in for a missing file.
static var unavailable := {}
static var _materials := {}  # texture path -> StandardMaterial3D
static var _bounds := {}  # texture path -> Rect2
static var _masks := {}  # texture path -> PackedByteArray, MASK_CELLS x MASK_CELLS (painted_at)
static var _meshes: Array[ArrayMesh] = [null, null]  # as painted, mirrored
static var _shadow_meshes: Array[ArrayMesh] = [null, null]
static var _contact_meshes: Array[ArrayMesh] = [null, null]
static var _shadow_shader: Shader
static var _shadow_materials := {}  # texture path -> ShaderMaterial
static var _site_shader: Shader
static var _site_materials := {}  # texture path -> ShaderMaterial (each site card draws a duplicate: its own cut)
static var _ghost_shader: Shader
static var _ghost_materials := {}  # texture path + tint -> ShaderMaterial
static var _contact_shader: Shader
static var _contact_materials := {}  # texture path -> ShaderMaterial


static func cos_pitch() -> float:
	return sqrt(1.0 - WorldArt.PITCH_SIN * WorldArt.PITCH_SIN)


static func tiles_for(kind: String) -> float:
	return float(MOCK_PX.get(kind, 0)) / PX_PER_TILE


## The sprite for `kind` drawn for `owner` (0 human, 1 enemy; the enemy falls back to the human sprite), or null when
## neither loads (the caller keeps its model).
static func texture_for(kind: String, owner: int) -> Texture2D:
	if not SPRITES.has(kind):
		return null
	var names: Array = SPRITES[kind]
	var tex: Texture2D = null
	if owner != 0 and names.size() > 1:
		tex = _load(String(names[1]))
	if tex == null:
		tex = _load(String(names[0]))
	return tex


static func _load(name: String) -> Texture2D:
	if unavailable.has(name) or not ResourceLoader.exists(DIR % name):
		return null
	var tex := load(DIR % name) as Texture2D
	if tex == null:
		unavailable[name] = true
		push_warning("Kestrel sprite %s failed to load: its entities keep their models" % name)
	return tex


## Empties the per-texture caches (bounds, masks, materials); the next use rebuilds them. Tests use it.
static func clear_caches() -> void:
	_materials.clear()
	_bounds.clear()
	_masks.clear()
	_shadow_materials.clear()
	_contact_materials.clear()
	_site_materials.clear()
	_ghost_materials.clear()


## Builds every catalogue sprite's caches at once (the alpha scan, the graded copy, the shadow materials) so the first
## frame a kind appears does no image work. earthfront_3d calls it once, as the Kestrel ground comes in.
static func prewarm() -> void:
	var seen := {}
	var all: Array[Texture2D] = []
	for kind in SPRITES:
		for owner in [0, 1]:
			all.append(texture_for(kind, owner))
	for tex in all:
		if tex == null or seen.has(_key(tex)):
			continue
		seen[_key(tex)] = true
		opaque_bounds(tex)
		material_for(tex)
		shadow_material_for(tex)
		contact_material_for(tex)
		site_material_for(tex)


## One shared unshaded material per texture: alpha blended with a depth pre-pass, so the painted body hides what stands
## behind it and the soft painted edges still blend. It samples the sprite pre-graded by GRADE and names the sprite in its
## `source_texture` meta.
static func material_for(tex: Texture2D) -> Material:
	if tex == null:
		return null
	var key := _key(tex)
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = graded(tex)
		m.set_meta("source_texture", tex)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.texture_repeat = false  # clamped: a painted edge never bleeds the opposite edge in
		_materials[key] = m
	return _materials[key]


## A copy of `tex` graded by GRADE (alpha untouched, mipmaps rebuilt), or `tex` itself when its image cannot be read.
static func graded(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img = img.duplicate() as Image  # a headless texture hands out its own image: never grade the sprite in place
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(float(GRADE.brightness), float(GRADE.contrast), float(GRADE.saturation))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The painted body's box in card UV (0..1, v down from the top): the bounding box of the pixels whose alpha passes
## OPAQUE_ALPHA. Scanned once per texture (with its paint mask, painted_at).
static func opaque_bounds(tex: Texture2D) -> Rect2:
	var key := _key(tex)
	if not _bounds.has(key):
		_scan(tex, key)
	return _bounds[key]


## Whether the sprite has paint at texture UV `uv` (0..1, v down): on a MASK_CELLS x MASK_CELLS grid, a cell that holds a
## pixel over OPAQUE_ALPHA or touches one (dilated by a cell, so a click on a painted edge still lands). Picking reads it
## after the box test: about 40 % of a painting's opaque box is see-through (between towers, under a barrel).
static func painted_at(tex: Texture2D, uv: Vector2) -> bool:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return false
	var key := _key(tex)
	if not _bounds.has(key):
		_scan(tex, key)
	var mask: PackedByteArray = _masks[key]
	if mask.is_empty():
		return true  # an unreadable image: the box alone decides
	var cx := clampi(int(uv.x * MASK_CELLS), 0, MASK_CELLS - 1)
	var cy := clampi(int(uv.y * MASK_CELLS), 0, MASK_CELLS - 1)
	return mask[cy * MASK_CELLS + cx] != 0


## The card v of a site's build line: the painted body is drawn from its base (opaque_bounds' bottom) up to here, a share
## `reveal` (0..1) of its height. A finished building's is the body's top.
static func reveal_cut(tex: Texture2D, reveal: float) -> float:
	var r := opaque_bounds(tex)
	return r.end.y - clampf(reveal, 0.0, 1.0) * r.size.y


## The part of the painted body drawn at `reveal`: opaque_bounds from the build line down.
static func drawn_bounds(tex: Texture2D, reveal := 1.0) -> Rect2:
	var r := opaque_bounds(tex)
	var cut := reveal_cut(tex, reveal)
	return Rect2(r.position.x, cut, r.size.x, r.end.y - cut)


## How much of its painting a card draws (show_progress): 1 for a finished building or a unit.
static func drawn_reveal(card: Node) -> float:
	return float(card.get_meta("reveal", 1.0))


## The reveal a card picks by: what it draws, never less than SITE_PICK_FLOOR (a fresh site can be clicked).
static func pick_reveal(card: Node) -> float:
	return maxf(drawn_reveal(card), SITE_PICK_FLOOR)


## A click at `frac` of a pick box's screen rectangle (0..1, left to right and top to bottom) lands on paint: the box spans
## the drawn part of the opaque rect (drawn_bounds at `reveal`), read right to left on a `mirrored` card.
static func box_hit(tex: Texture2D, frac: Vector2, mirrored := false, reveal := 1.0) -> bool:
	var r := drawn_bounds(tex, reveal)
	var u := r.position.x + frac.x * r.size.x
	if mirrored:
		u = r.end.x - frac.x * r.size.x
	return painted_at(tex, Vector2(u, r.position.y + frac.y * r.size.y))


## The sprite a card draws now (a site draws its own building's, revealed: drawn_reveal).
static func drawn_texture(card: Node) -> Texture2D:
	var m := (card as GeometryInstance3D).material_override if card is GeometryInstance3D else null
	if m != null and m.has_meta("source_texture"):
		return m.get_meta("source_texture")
	return card.get_meta("sprite_texture", null)


static func _key(tex: Texture2D) -> String:
	return tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())


## One pass over the sprite's alpha: the opaque box and the dilated paint mask.
static func _scan(tex: Texture2D, key: String) -> void:
	var img := tex.get_image()
	var out := Rect2(0, 0, 1, 1)
	var mask := PackedByteArray()
	if img != null and not img.is_empty():
		img = img.duplicate() as Image  # a headless texture hands out its own image
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var size := img.get_size()
		var data := img.get_data()
		var cells := PackedByteArray()
		cells.resize(MASK_CELLS * MASK_CELLS)
		var col_cell := PackedInt32Array()
		col_cell.resize(size.x)
		for x in size.x:
			col_cell[x] = x * MASK_CELLS / size.x
		var lo := Vector2i(size.x, size.y)
		var hi := Vector2i(-1, -1)
		for y in size.y:
			var row := y * size.x * 4
			var row_cell := (y * MASK_CELLS / size.y) * MASK_CELLS
			var first := -1
			var last := -1
			for x in size.x:
				if data[row + x * 4 + 3] > OPAQUE_ALPHA:
					if first < 0:
						first = x
					last = x
					cells[row_cell + col_cell[x]] = 1
			if first >= 0:
				lo = Vector2i(mini(lo.x, first), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, last), maxi(hi.y, y))
		if hi.x >= 0:
			out = Rect2(float(lo.x) / size.x, float(lo.y) / size.y, float(hi.x - lo.x + 1) / size.x, float(hi.y - lo.y + 1) / size.y)
		mask.resize(MASK_CELLS * MASK_CELLS)
		for cy in MASK_CELLS:
			for cx in MASK_CELLS:
				if cells[cy * MASK_CELLS + cx] == 0:
					continue
				for ny in range(maxi(0, cy - 1), mini(MASK_CELLS, cy + 2)):
					for nx in range(maxi(0, cx - 1), mini(MASK_CELLS, cx + 2)):
						mask[ny * MASK_CELLS + nx] = 1
	_bounds[key] = out
	_masks[key] = mask


## The unit card (1 wide, ASPECT tall on screen) shared by every sprite entity; the node's uniform scale sets the width.
## `mirrored` reads the painting right to left (u flipped); the geometry is the same.
static func card_mesh(mirrored := false) -> ArrayMesh:
	var i := 1 if mirrored else 0
	if _meshes[i] == null:
		var c := cos_pitch()
		var s := WorldArt.PITCH_SIN
		var up := Vector3(0.0, c, -s) * ASPECT  # the camera's up vector: square to the view, one depth
		var fwd := Vector3(0.0, 0.0, 1.0) * (ASPECT / s)  # along the ground toward the camera: v grows by 1 per ASPECT/s
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3(0.0, s, c))
		# standing part: v 0 (top) .. FOOT (contact line, on the root)
		var a0 := Vector3(-0.5, 0, 0) + up * FOOT
		var a1 := Vector3(0.5, 0, 0) + up * FOOT
		var b0 := Vector3(-0.5, 0, 0)
		var b1 := Vector3(0.5, 0, 0)
		# ground strip: v FOOT .. 1, lying before the root
		var g0 := b0 + fwd * (1.0 - FOOT)
		var g1 := b1 + fwd * (1.0 - FOOT)
		_quad(st, [a0, a1, b1, b0], _uvs([Vector2(0, 0), Vector2(1, 0), Vector2(1, FOOT), Vector2(0, FOOT)], mirrored))
		_quad(st, [b0, b1, g1, g0], _uvs([Vector2(0, FOOT), Vector2(1, FOOT), Vector2(1, 1), Vector2(0, 1)], mirrored))
		_meshes[i] = st.commit()
	return _meshes[i]


## The cast shadow's ground quad for the unit card: the part above the contact line (v 0 .. FOOT) laid on the ground in
## front of the root, flattened and sheared as the boards draw it (screen down 0.34 d, right 0.589 d for a pixel d above
## the line; a screen-down distance s is s / PITCH_SIN on the ground).
static func shadow_mesh(mirrored := false) -> ArrayMesh:
	var i := 1 if mirrored else 0
	if _shadow_meshes[i] == null:
		var d := FOOT * ASPECT
		var far := Vector3(SHADOW_SHEAR * d, 0.0, SHADOW_SCALE * d / WorldArt.PITCH_SIN)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var b0 := Vector3(-0.5, 0, 0)
		var b1 := Vector3(0.5, 0, 0)
		_quad(st, [b0 + far, b1 + far, b1, b0], _uvs([Vector2(0, 0), Vector2(1, 0), Vector2(1, FOOT), Vector2(0, FOOT)], mirrored))
		_shadow_meshes[i] = st.commit()
	return _shadow_meshes[i]


## The contact band's ground quad for the unit card: card pixel (u, v) lands AO_SCALE * (v - FOOT) + AO_DROP below the
## root on screen (s / PITCH_SIN on the ground), with AO_MARGIN of blur room around the painting (UVs past 0..1 read
## the clamped, transparent edge).
static func contact_mesh(mirrored := false) -> ArrayMesh:
	var i := 1 if mirrored else 0
	if _contact_meshes[i] == null:
		var u0 := -AO_MARGIN.x
		var u1 := 1.0 + AO_MARGIN.x
		var v0 := -AO_MARGIN.y
		var v1 := 1.0 + AO_MARGIN.y
		var z := func(v: float) -> float: return (AO_SCALE * (v - FOOT) + AO_DROP) * ASPECT / WorldArt.PITCH_SIN
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var p := [Vector3(u0 - 0.5, 0, z.call(v0)), Vector3(u1 - 0.5, 0, z.call(v0)), Vector3(u1 - 0.5, 0, z.call(v1)), Vector3(u0 - 0.5, 0, z.call(v1))]
		_quad(st, p, _uvs([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)], mirrored))
		_contact_meshes[i] = st.commit()
	return _contact_meshes[i]


static func contact_material_for(tex: Texture2D) -> Material:
	if tex == null:
		return null
	var key := _key(tex)
	if not _contact_materials.has(key):
		if _contact_shader == null:
			_contact_shader = Shader.new()
			_contact_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float strength = 0.6;
uniform float lod = 4.5;
uniform float sigma = 0.38;
void fragment() {
    float a = 0.0;
    float norm = 0.0;
    for (int i = -3; i <= 3; i++) {
        float w = exp(-float(i * i) / 4.5);
        a += w * textureLod(sprite, vec2(UV.x, UV.y + float(i) * sigma / 1.5), lod).a;
        norm += w;
    }
    ALBEDO = vec3(0.0);
    ALPHA = a / norm * strength;
}
"""
		var m := ShaderMaterial.new()
		m.shader = _contact_shader
		m.set_shader_parameter("sprite", tex)
		m.set_shader_parameter("strength", AO_ALPHA)
		m.set_shader_parameter("lod", AO_LOD)
		m.set_shader_parameter("sigma", AO_SIGMA)
		m.render_priority = -1  # with the silhouette shadow and the prop decals
		_contact_materials[key] = m
	return _contact_materials[key]


static func _uvs(uv: Array, mirrored: bool) -> Array:
	if not mirrored:
		return uv
	var out := []
	for p in uv:
		out.append(Vector2(1.0 - (p as Vector2).x, (p as Vector2).y))
	return out


static func shadow_material_for(tex: Texture2D) -> Material:
	if tex == null:
		return null
	var key := _key(tex)
	if not _shadow_materials.has(key):
		if _shadow_shader == null:
			_shadow_shader = Shader.new()
			_shadow_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float strength = 0.208;
uniform float lod = 2.0;
uniform float cut = 0.0;
void fragment() {
    ALBEDO = vec3(0.0);
    ALPHA = textureLod(sprite, UV, lod).a * strength * step(cut, UV.y);
}
"""
		var m := ShaderMaterial.new()
		m.shader = _shadow_shader
		m.set_shader_parameter("sprite", tex)
		m.set_shader_parameter("strength", SHADOW_ALPHA)
		m.set_shader_parameter("lod", SHADOW_LOD)
		m.set_shader_parameter("cut", 0.0)  # a site's copy casts only what it has built (show_progress)
		m.render_priority = -1  # with the prop decals: under the grid, territory and hover overlays
		_shadow_materials[key] = m
	return _shadow_materials[key]


## The construction site's material for `tex` (a template: show_progress gives each site card its own copy, since each
## carries its own build line): the graded painting under the build line `cut`, pulled SITE_TINT toward the scaffold
## colour with a lit seam along the line; over it, a faint scaffold lattice clipped to the painting's blurred silhouette.
## It names the sprite in its `source_texture` meta, as material_for does.
static func site_material_for(tex: Texture2D) -> Material:
	if tex == null:
		return null
	var key := _key(tex)
	if not _site_materials.has(key):
		if _site_shader == null:
			_site_shader = Shader.new()
			_site_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled, shadows_disabled;
uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float cut = 1.0;
uniform float tint = 0.18;
uniform vec3 scaffold : source_color = vec3(0.62, 0.56, 0.40);
uniform float lattice = 0.34;
void fragment() {
    vec4 c = texture(sprite, UV);
    float built = step(cut, UV.y);
    // the built part: the painting under a faint scaffold tint, a lit weld seam along the build line
    float seam = (1.0 - smoothstep(0.0, 0.02, UV.y - cut)) * built;
    vec3 body = mix(c.rgb, scaffold, tint);
    body = mix(body, vec3(1.0, 0.84, 0.48), seam * 0.75);
    // the unbuilt part: a scaffold lattice (poles, ledgers, braces) and a faint sheeting over the painting's silhouette,
    // with a plank deck just over the build line
    float sil = smoothstep(0.2, 0.6, textureLod(sprite, UV, 2.5).a);
    vec2 g = UV * vec2(11.0, 13.0);
    vec2 cell = fract(g);
    vec2 w = fwidth(g) * 1.4 + 0.05;
    float pole = 1.0 - smoothstep(0.0, w.x, min(cell.x, 1.0 - cell.x));
    float ledger = 1.0 - smoothstep(0.0, w.y, min(cell.y, 1.0 - cell.y));
    float brace = 1.0 - smoothstep(0.0, w.x * 1.3, abs(cell.x - cell.y));
    float deck = 1.0 - smoothstep(0.012, 0.022, cut - UV.y);
    float frame = max(max(pole, ledger), brace * 0.55);
    vec3 steel = mix(scaffold * 0.55, vec3(0.76, 0.70, 0.54), frame);
    steel = mix(steel, vec3(0.42, 0.33, 0.22), deck);
    float sheet = 0.16;
    ALBEDO = mix(steel, body, built);
    ALPHA = mix(sil * max(max(frame * lattice, sheet), deck * 0.9), c.a, built);
}
"""
		var m := ShaderMaterial.new()
		m.shader = _site_shader
		m.set_shader_parameter("sprite", (material_for(tex) as StandardMaterial3D).albedo_texture)
		m.set_shader_parameter("cut", 1.0)
		m.set_shader_parameter("tint", SITE_TINT)
		m.set_shader_parameter("scaffold", SITE_SCAFFOLD)
		m.set_shader_parameter("lattice", SITE_LATTICE)
		m.set_meta("source_texture", tex)
		_site_materials[key] = m
	return _site_materials[key]


## The placement ghost's material for `tex` tinted `tint` (the legacy validity colour; its alpha is ignored): the graded
## painting pulled GHOST_TINT toward the tint at GHOST_OPACITY, drawn after the transparent pass without a depth test, so
## a tall building in front never hides whether the hex is valid.
## One per texture and tint, shared.
static func ghost_material_for(tex: Texture2D, tint: Color) -> Material:
	if tex == null:
		return null
	var key := "%s|%s" % [_key(tex), tint.to_html()]
	if not _ghost_materials.has(key):
		if _ghost_shader == null:
			_ghost_shader = Shader.new()
			_ghost_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.2, 0.82, 0.64, 1.0);
uniform float amount = 0.5;
uniform float opacity = 0.6;
void fragment() {
    vec4 c = texture(sprite, UV);
    ALBEDO = mix(c.rgb, tint.rgb, amount);
    ALPHA = c.a * opacity;
}
"""
		var m := ShaderMaterial.new()
		m.shader = _ghost_shader
		m.set_shader_parameter("sprite", (material_for(tex) as StandardMaterial3D).albedo_texture)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("amount", GHOST_TINT)
		m.set_shader_parameter("opacity", GHOST_OPACITY)
		m.set_meta("source_texture", tex)
		m.render_priority = 1  # over the buildings' transparent pass
		_ghost_materials[key] = m
	return _ghost_materials[key]


static func _quad(st: SurfaceTool, p: Array, uv: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(p[i])


## A sprite card for `kind` and `owner`, `tiles` tiles wide, its contact line on the parent's origin (null without a
## sprite). It casts no real shadow; it carries the boards' silhouette shadow, and with `contact` (units: they move, so
## they take no ground pad) the boards' contact band too.
static func make_card(kind: String, owner: int, tiles: float, contact := false) -> MeshInstance3D:
	var tex := texture_for(kind, owner)
	if tex == null:
		return null
	var card := MeshInstance3D.new()
	card.mesh = card_mesh()
	card.material_override = material_for(tex)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.scale = Vector3.ONE * tiles * WorldArt.TILE
	var hover := float(HOVER.get(kind, 0.0))
	card.position = Vector3(0.0, CARD_LIFT + hover, 0.0)
	card.set_meta("hover", hover)
	card.set_meta("sprite_kind", kind)
	card.set_meta("sprite_texture", tex)
	card.set_meta("native_facing", int(FACING.get(tex.resource_path.get_file().get_basename(), 0)))
	card.set_meta("mirrored", false)
	var shadow := MeshInstance3D.new()
	shadow.name = "SpriteShadow"
	shadow.mesh = shadow_mesh()
	shadow.material_override = shadow_material_for(tex)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = -hover / card.scale.y  # a hovering card's shadows stay on the ground
	card.add_child(shadow)
	if contact:
		var band := MeshInstance3D.new()
		band.name = "SpriteContact"
		band.mesh = contact_mesh()
		band.material_override = contact_material_for(tex)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		band.position.y = -hover / card.scale.y
		card.add_child(band)
	return card


## Turns the card toward its horizontal screen motion `dx` (world x: the Kestrel camera is north up): the painting shows
## mirrored when it moves against the way it is painted facing. A move under FACING_DEADBAND, or a head-on painting, keeps
## the facing. Returns whether the card flipped.
static func face(card: MeshInstance3D, dx: float) -> bool:
	var native := int(card.get_meta("native_facing", 0))
	if native == 0 or absf(dx) < FACING_DEADBAND:
		return false
	var mirrored := signf(dx) != float(native)
	if mirrored == bool(card.get_meta("mirrored", false)):
		return false
	card.set_meta("mirrored", mirrored)
	card.mesh = card_mesh(mirrored)
	var shadow := card.get_node_or_null("SpriteShadow") as MeshInstance3D
	if shadow != null:
		shadow.mesh = shadow_mesh(mirrored)
	var band := card.get_node_or_null("SpriteContact") as MeshInstance3D
	if band != null:
		band.mesh = contact_mesh(mirrored)
	return true


## Shows a building `progress` (0..1) built: under 1, its own painting from the base up to reveal_cut, through its own
## copy of the site material (and its cast shadow through its own copy of the shadow material, cut the same); at 1 the
## shared finished materials. Returns the sprite drawn; earthfront_3d fits the bars and the pick box to drawn_reveal.
static func show_progress(card: MeshInstance3D, progress: float) -> Texture2D:
	var tex: Texture2D = card.get_meta("sprite_texture")
	progress = clampf(progress, 0.0, 1.0)
	card.set_meta("reveal", progress)
	var shadow := card.get_node_or_null("SpriteShadow") as MeshInstance3D
	if progress >= 1.0:
		var m := material_for(tex)
		if card.material_override != m:
			card.material_override = m
			if shadow != null:
				shadow.material_override = shadow_material_for(tex)
		return tex
	var site := card.material_override as ShaderMaterial
	if site == null or not site.has_meta("site_of"):
		site = site_material_for(tex).duplicate() as ShaderMaterial
		site.set_meta("source_texture", tex)
		site.set_meta("site_of", card.get_instance_id())
		card.material_override = site
		if shadow != null:
			shadow.material_override = shadow_material_for(tex).duplicate()
	var cut := reveal_cut(tex, progress)
	site.set_shader_parameter("cut", cut)
	if shadow != null:
		(shadow.material_override as ShaderMaterial).set_shader_parameter("cut", cut)
	return tex


## The painted body's height over the root, as a vertical offset in the root's space whose screen point is the body's top
## (the Kestrel camera shows a vertical metre as cos_pitch() of a screen metre). `width` is the card width (world units).
static func body_top_y(tex: Texture2D, width: float, lift: float = CARD_LIFT, reveal := 1.0) -> float:
	return lift + (FOOT - reveal_cut(tex, reveal)) * width * ASPECT / cos_pitch()


## The pick box: a flat box in the root's space whose eight corners project onto the painted body's screen rectangle
## (earthfront_3d._parts_hold), so a click on a transparent corner of the card is not a click on the building.
static func pick_box(tex: Texture2D, width: float, lift: float = CARD_LIFT, mirrored := false, reveal := 1.0) -> AABB:
	var r := drawn_bounds(tex, reveal)
	if mirrored:
		r.position.x = 1.0 - r.end.x
	var h := width * ASPECT
	var y_top := lift + (FOOT - r.position.y) * h / cos_pitch()
	var y_bottom := lift + (FOOT - r.end.y) * h / cos_pitch()
	return AABB(Vector3((r.position.x - 0.5) * width, y_bottom, 0.0), Vector3(r.size.x * width, y_top - y_bottom, 0.0))


## Whether `card`'s painted body covers the ground point `offset` (x, z from the root) on screen, as the hover outline
## sees it: lifted and mirrored as drawn, a site by what it picks (pick_reveal: at least SITE_PICK_FLOOR of its body).
static func card_covers_ground(card: MeshInstance3D, offset: Vector2) -> bool:
	return covers_ground(drawn_texture(card), card.scale.x, offset, card.position.y, bool(card.get_meta("mirrored", false)), pick_reveal(card))


## Whether the painted body's box covers the ground point `offset` (x, z from the root) on screen: hover outlines skip it.
## `lift` is the card's height over the root (it shows the painting lift * cos_pitch higher), `mirrored` its facing.
static func covers_ground(tex: Texture2D, width: float, offset: Vector2, lift := 0.0, mirrored := false, reveal := 1.0) -> bool:
	var r := drawn_bounds(tex, reveal)
	if mirrored:
		r.position.x = 1.0 - r.end.x
	var h := width * ASPECT
	var down := offset.y * WorldArt.PITCH_SIN + lift * cos_pitch()  # screen distance below the card's contact line
	var u := offset.x / width + 0.5
	var v := FOOT + down / h
	return r.has_point(Vector2(u, v))


## Where the contact pad goes: the painted footprint's centre on the ground (north of the root) and its width.
static func pad_spot(tex: Texture2D, width: float) -> Vector3:
	var r := opaque_bounds(tex)
	var h := width * ASPECT
	return Vector3((r.get_center().x - 0.5) * width, 0.0, -(FOOT - FOOTPRINT) * h / WorldArt.PITCH_SIN)


static func pad_width(tex: Texture2D, width: float) -> float:
	return opaque_bounds(tex).size.x * width


## The selection ellipse under a card, in card terms: the card v of its centre, rx as a share of the painted body's width,
## and ry / rx on screen. StructureSelected: a 200 px barracks drawn at top 570 (painted body 177 px wide) takes rx 132,
## ry 46 centred at 725. CoreAssault: each 140 px tank (body 124 px) takes rx 58, ry 22 centred 19 px over its contact
## line. Its back arc passes behind the painting there as here.
const RING_BUILDING := Vector3(0.775, 0.745, 0.35)
const RING_UNIT := Vector3(0.714, 0.467, 0.38)


## The selection ellipse under a card `width` wide: {centre: its ground point as an offset (x, 0, z) from the root,
## rx: its radius along x, rz: along z (world units)}. Centred under the painted body, mirrored with the card.
static func ring(tex: Texture2D, width: float, unit := false, mirrored := false) -> Dictionary:
	var shape := RING_UNIT if unit else RING_BUILDING
	var r := opaque_bounds(tex)
	var x := (r.get_center().x - 0.5) * width
	if mirrored:
		x = -x
	var rx := shape.y * r.size.x * width
	var z := (shape.x - FOOT) * width * ASPECT / WorldArt.PITCH_SIN
	return {"centre": Vector3(x, 0.0, z), "rx": rx, "rz": rx * shape.z / WorldArt.PITCH_SIN}
