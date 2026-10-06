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
static var _memory_materials := {}  # texture path -> StandardMaterial3D, material_for dimmed to MEMORY_SHADE (fog memory)
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
	_memory_materials.clear()


## Kestrel fog of war: a remembered building (seen once, now out of sight) is drawn this much darker, through one shared
## memory material per painting (material_for with albedo_color at MEMORY_SHADE; the same pipeline, nothing to warm) or,
## on a site card, its own site material's `shade`.
const MEMORY_SHADE := 0.55


static func memory_material_for(tex: Texture2D) -> Material:
	if tex == null:
		return null
	var key := _key(tex)
	if not _memory_materials.has(key):
		var m := (material_for(tex) as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = Color(MEMORY_SHADE, MEMORY_SHADE, MEMORY_SHADE, 1.0)
		m.set_meta("source_texture", tex)
		m.set_meta("memory", true)
		_memory_materials[key] = m
	return _memory_materials[key]


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
uniform float shade = 1.0;  // MEMORY_SHADE on a remembered site (fog of war), else 1
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
    ALBEDO = mix(steel, body, built) * shade;
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
	var drop := -hover / card.scale.y  # a hovering card's shadows stay on the ground
	if hover > 0.0:
		card.set_meta("shadow_drop", drop)  # apply_pose keeps them there under a tilt
	var shadow := MeshInstance3D.new()
	shadow.name = "SpriteShadow"
	shadow.mesh = shadow_mesh()
	shadow.material_override = shadow_material_for(tex)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = drop
	card.add_child(shadow)
	if contact:
		var band := MeshInstance3D.new()
		band.name = "SpriteContact"
		band.mesh = contact_mesh()
		band.material_override = contact_material_for(tex)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		band.position.y = drop
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
	return covers_ground(drawn_texture(card), card_width(card), offset, rest_lift(card), bool(card.get_meta("mirrored", false)), pick_reveal(card))


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


## Pose (plan 2026-10-05-kestrel-combat-motion-fx, Task 4): one rest transform per unit card and layers over it. A card at
## rest carries no pose state and every mover writes it as before; the first layer that starts (a recoil kick, the
## movement animation) records the rest (`pose_rest`: the card's basis, x and z, and y = base_y + hover, its lift and
## hover), and from then on each layer only sets its own offset and calls apply_pose, which draws
## rest + bob (y, the gunship's) + kick (x and z, the recoil) + the animation's reshape (about the contact line). When the
## kick and the animation have both ended the card is written back to the rest (plus the bob) and the pose state goes:
## no mover ever overwrites another, and a stopped card stands exactly where its rest says. _lift_unit_card moves the
## rest of a posed card (rest_moved); _bob_units sets the bob layer of a posed gunship. Picking, the bars, the selection
## ellipse and the hover cover read the rest (card_width, rest_lift), never the posed card.


## The card's width at rest (the posed basis is reshaped).
static func card_width(card: Node3D) -> float:
	if card.has_meta("pose_rest"):
		return (card.get_meta("pose_rest") as Transform3D).basis.x.length()
	return card.scale.x


## The card's height over its root at rest (a gunship's includes its bob while it is not posed, as before).
static func rest_lift(card: Node3D) -> float:
	if card.has_meta("pose_rest"):
		return (card.get_meta("pose_rest") as Transform3D).origin.y
	return card.position.y


## Records the card's rest the first time a layer starts (a kick on a walk keeps the walk's rest).
static func pose_begin(card: Node3D) -> void:
	if card.has_meta("pose_rest"):
		return
	var y := card.position.y  # a ground card stands at its rest whenever it is not posed
	if card.has_meta("base_y") and card.has_meta("shadow_drop"):
		y = float(card.get_meta("base_y")) + float(card.get_meta("hover", 0.0))
		card.set_meta("pose_bob", card.position.y - y)  # a gunship caught mid-bob keeps it until _bob_units sets the next
	card.set_meta("pose_rest", Transform3D(card.basis, Vector3(card.position.x, y, card.position.z)))


## The rest's height follows the card's lift (base_y) and hover; re-poses the card. False when the card is not posed.
static func rest_moved(card: Node3D) -> bool:
	if not card.has_meta("pose_rest"):
		return false
	var rest: Transform3D = card.get_meta("pose_rest")
	rest.origin.y = float(card.get_meta("base_y", rest.origin.y)) + float(card.get_meta("hover", 0.0))
	card.set_meta("pose_rest", rest)
	apply_pose(card)
	return true


## Draws the card as its rest plus every live layer; with neither a kick nor an animation left, writes the rest (plus the
## bob) and drops the pose state.
static func apply_pose(card: Node3D) -> void:
	var at = card.get_meta("pose_rest", false)  # false: not posed (a null default would be no default)
	if not at is Transform3D:
		return
	var rest: Transform3D = at
	var origin := rest.origin
	origin.y += float(card.get_meta("pose_bob", 0.0))
	var kick = card.get_meta("pose_kick", false)
	if kick is Vector2:
		origin.x += (kick as Vector2).x
		origin.z += (kick as Vector2).y
	var posed = card.get_meta("pose_anim", false)
	var aim = card.get_meta("pose_aim", false)
	if not posed is Vector3 and not aim is float:
		card.transform = Transform3D(rest.basis, origin)
		_place_shadows(card, Vector3(0.0, 1.0, 1.0))
		if not kick is Vector2:
			card.remove_meta("pose_rest")
			card.remove_meta("pose_bob")
		return
	var shape := Vector3(0.0, 1.0, 1.0)  # lean (a shear of local y into x), x scale, local y scale
	if posed is Vector3:
		shape = posed
	var xf := Transform3D(rest.basis * Basis(Vector3(shape.y, 0.0, 0.0), Vector3(shape.x, shape.z, 0.0), Vector3(0.0, 0.0, 1.0)), origin)
	var tilt := aim_transform(card, float(aim)) if aim is float else Transform3D.IDENTITY
	card.transform = xf * tilt
	_place_shadows(card, shape, tilt)


## A hovering card's shadows hang under it (shadow_drop, in card units); under a reshape they are placed so that they
## still land straight under the root on the ground. Under an aim lean (`tilt`, in the card's own space) both shadows
## take its inverse, so they lie exactly where they would without it; once the lean is over they are written back.
static func _place_shadows(card: Node3D, shape: Vector3, tilt := Transform3D.IDENTITY) -> void:
	var tilted := tilt != Transform3D.IDENTITY
	if not card.has_meta("shadow_drop") and not tilted and not card.has_meta("aim_shadows"):
		return
	var drop := float(card.get_meta("shadow_drop", 0.0))
	var at := Vector3(0.0, drop, 0.0)
	if shape != Vector3(0.0, 1.0, 1.0):
		at.y = drop / shape.z
		at.x = -shape.x * at.y / shape.y
	var xf := Transform3D(Basis(), at)
	if tilted:
		xf = tilt.affine_inverse() * xf
		card.set_meta("aim_shadows", true)
	elif card.has_meta("aim_shadows"):
		card.remove_meta("aim_shadows")
	for part in ["SpriteShadow", "SpriteContact"]:
		var n := card.get_node_or_null(part) as Node3D
		if n != null:
			n.transform = xf


## Recoil (Task 3, a pose layer since Task 4): a unit card that fires kicks back along the ground, away from its target,
## over RECOIL_S and comes home exactly. It moves the card alone (x and z: the gunship bob owns y), never the root, so the
## pick box, the bars and the selection ellipse stay where they are. Buildings never recoil.
const RECOIL_S := 0.1
const RECOIL_OUT := 0.3  # the share of RECOIL_S spent kicking out; the rest eases home
## The kick (world units) per unit kind; a kind not listed kicks RECOIL_DEFAULT.
const RECOIL := {"Infantry": 0.02, "AntiArmor": 0.04, "Tank": 0.055, "Helicopter": 0.03, "Capital": 0.05}
const RECOIL_DEFAULT := 0.025


## Starts a kick on `card` away from `toward` (the shot's world direction; only its ground part counts) at time `start`
## (the effects clock: a delayed shot kicks when its muzzle flashes). A kick on a kick keeps the first rest position.
static func kick(card: Node3D, toward: Vector3, start: float) -> void:
	var away := Vector3(-toward.x, 0.0, -toward.z)
	if away.length_squared() < 1e-10:
		return
	pose_begin(card)
	var amount := float(RECOIL.get(String(card.get_meta("sprite_kind", "")), RECOIL_DEFAULT))
	card.set_meta("recoil_dir", away.normalized() * amount)
	card.set_meta("recoil_t0", start)
	# The kick is a live layer from this moment: a bob, a lift or a walk ending before the first recoil_step must
	# not drop the pose (that lost every kick of a standing gunship).
	if not card.get_meta("pose_kick", false) is Vector2:
		card.set_meta("pose_kick", Vector2.ZERO)


## Places a kicking card for time `now`; true while the kick runs (or waits on its start), false once the card is home
## (exactly at its rest, the recoil state cleared).
static func recoil_step(card: Node3D, now: float) -> bool:
	if not card.has_meta("recoil_t0"):
		return false
	var f := (now - float(card.get_meta("recoil_t0"))) / RECOIL_S
	if f >= 1.0:
		card.remove_meta("recoil_t0")
		card.remove_meta("recoil_dir")
		card.remove_meta("pose_kick")
		apply_pose(card)
		return false
	var p := 0.0
	if f > 0.0:
		p = smoothstep(0.0, 1.0, f / RECOIL_OUT) if f < RECOIL_OUT else pow(1.0 - (f - RECOIL_OUT) / (1.0 - RECOIL_OUT), 2.0)
	var d: Vector3 = card.get_meta("recoil_dir")
	card.set_meta("pose_kick", Vector2(d.x * p, d.z * p))
	apply_pose(card)
	return true


## Aim lean (plan 2026-10-06-kestrel-next-level, Task 9): a unit card that fires leans toward its target's side of the
## screen, a turn in the card's own plane (about the view axis) of at most AIM_LEAN_DEG over AIM_LEAN_S, eased in over
## AIM_LEAN_RISE of it and eased back out, then exactly its rest again. It pivots on the painted base: the turn is about
## the root and the card rides up along its own up by the painted base's reach on the leaning side times sin(angle), so
## the base corner on that side stays on the contact line and the other lifts a little. The dispatcher starts it beside the recoil kick
## from the same shot (its direction and its muzzle time), so it faces the real target and never moves without a shot. A
## target straight up or down the screen leans by its sideways share only: none at all. The card alone turns: the pick
## box, the bars and the selection ellipse read the rest, and the shadows take the lean's inverse (_place_shadows). It
## runs on the effects clock, so the pause holds it. Buildings never lean (only UNIT_KINDS).
const AIM_LEAN_S := 0.25
const AIM_LEAN_RISE := 0.35
const AIM_LEAN_DEG := {"Infantry": 5.0, "AntiArmor": 5.0, "Tank": 4.0, "Helicopter": 6.0, "Capital": 4.0}
const AIM_LEAN_DEG_DEFAULT := 5.0
const AIM_LEAN_MAX_DEG := 6.0


## Starts an aim lean on `card` toward `toward` (the shot's world direction; only its ground part counts) at time `start`
## (the effects clock). A lean on a lean starts from the angle the card shows now, so it never jumps.
static func aim_lean(card: Node3D, toward: Vector3, start: float) -> void:
	if not UNIT_KINDS.has(String(card.get_meta("sprite_kind", ""))):
		return
	var ground := Vector2(toward.x, toward.z)
	if ground.length_squared() < 1e-10:
		return
	var deg := minf(float(AIM_LEAN_DEG.get(String(card.get_meta("sprite_kind")), AIM_LEAN_DEG_DEFAULT)), AIM_LEAN_MAX_DEG)
	var peak := deg_to_rad(deg) * ground.x / ground.length()
	var from := float(card.get_meta("pose_aim", 0.0))
	if absf(peak) < 1e-4 and absf(from) < 1e-9:
		return
	pose_begin(card)
	card.set_meta("aim_t0", start)
	card.set_meta("aim_peak", peak)
	card.set_meta("aim_from", from)
	card.set_meta("pose_aim", from)  # a live layer from now, as the kick is


## Places a leaning card for time `now`; true while the lean runs (or waits on its shot), false once it is over (the card
## exactly at its rest, or on its other layers, and the lean's state gone).
static func aim_lean_step(card: Node3D, now: float) -> bool:
	if not card.has_meta("aim_t0"):
		return false
	var f := (now - float(card.get_meta("aim_t0"))) / AIM_LEAN_S
	if f >= 1.0:
		for key in ["aim_t0", "aim_peak", "aim_from", "pose_aim"]:
			card.remove_meta(key)
		apply_pose(card)
		return false
	var peak := float(card.get_meta("aim_peak"))
	var angle := float(card.get_meta("aim_from"))
	if f >= AIM_LEAN_RISE:
		angle = peak * smoothstep(0.0, 1.0, (1.0 - f) / (1.0 - AIM_LEAN_RISE))
	elif f > 0.0:
		angle = lerpf(angle, peak, smoothstep(0.0, 1.0, f / AIM_LEAN_RISE))
	card.set_meta("pose_aim", angle)
	apply_pose(card)
	return true


## The aim lean by `angle` (radians, positive: the top to the right on screen) in the card's own space: a turn about the
## view axis through the root, lifted along the card's up so the painted base's corner on the leaning side (the lower one)
## stays on the contact line.
static func aim_transform(card: Node3D, angle: float) -> Transform3D:
	if angle == 0.0:
		return Transform3D.IDENTITY
	var c := cos_pitch()
	var s := WorldArt.PITCH_SIN
	var half := 0.5  # the painted base's reach from the root toward the leaning side (card widths)
	var tex = card.get_meta("sprite_texture", null)
	if tex is Texture2D:
		var r := opaque_bounds(tex)
		var right := (angle > 0.0) != bool(card.get_meta("mirrored", false))
		half = r.end.x - 0.5 if right else 0.5 - r.position.x
	return Transform3D(Basis(Vector3(0.0, s, c), -angle), Vector3(0.0, c, -s) * half * absf(sin(angle)))


## Movement animation (Task 4): a moving unit's card is reshaped about its contact line, so the painted ground (the
## contact line and the ground strip before it) never leaves the terrain: a lean (a shear: the top slides along x) and a
## squash or stretch (its width, and its standing height on screen). Amplitudes are shares of the card on screen, at
## full speed (ANIM_FULL); a unit standing still is never touched. One row per unit kind:
##   lean   the top's lean into the motion (share of the standing height); the gunship's is its forward tilt
##   stride, bounce, rock (on foot): world units walked per footfall; the height's swing over a footfall; the
##          side-to-side rock, to the other side each footfall
##   rumble, rumble_hz (tracks, wheels): the height's jitter on the ground and its rate
##   lurch  (vehicles): the stretch along the motion (and the lean back) as it pulls away, the squash (and the dip
##          forward) as it brakes, at a full lurch (LURCH_ACCEL)
##   sway, sway_hz (heavy kinds): a slow rock of the top
##   dust, dust_size, dust_back, dust_alpha: world units travelled per dust puff, its width, how far behind the root it
##          rises, its opacity (WorldFx.dust); wash (the gunship): seconds between rotor-wash rings (WorldFx.wash)
const ANIM := {
	"Infantry": {"lean": 0.035, "stride": 0.62, "bounce": 0.11, "rock": 0.08,
		"dust": 0.55, "dust_size": 0.26, "dust_back": 0.12, "dust_alpha": 0.4},
	"Tank": {"lean": 0.0, "rumble": 0.03, "rumble_hz": 11.0, "lurch": 0.045,
		"dust": 0.2, "dust_size": 0.42, "dust_back": 0.42, "dust_alpha": 0.6},
	# an anti-armour team is painted on foot: it walks (a longer, heavier step than a rifle squad) and lurches as it sets off
	"AntiArmor": {"lean": 0.03, "stride": 0.7, "bounce": 0.09, "rock": 0.06, "lurch": 0.04,
		"dust": 0.5, "dust_size": 0.28, "dust_back": 0.14, "dust_alpha": 0.4},
	"Harvester": {"lean": 0.01, "rumble": 0.016, "rumble_hz": 7.0, "lurch": 0.05, "sway": 0.035, "sway_hz": 1.3,
		"dust": 0.24, "dust_size": 0.4, "dust_back": 0.32, "dust_alpha": 0.6},
	"Helicopter": {"lean": 0.065, "sway": 0.02, "sway_hz": 0.8,
		"dust": 0.45, "dust_size": 0.5, "dust_back": 0.0, "dust_alpha": 0.35, "wash": 0.42},
	"Capital": {"lean": 0.0, "sway": 0.022, "sway_hz": 0.45, "rumble": 0.008, "rumble_hz": 5.0, "lurch": 0.03,
		"dust": 0.3, "dust_size": 0.7, "dust_back": 0.6, "dust_alpha": 0.55},
}
const ANIM_STILL := 0.05  # world units per s: slower is standing (the glide's last creep), the card at rest
const ANIM_FULL := 0.6  # world units per s: full amplitude from here (units march at about 0.7 to 2)
const LURCH_ACCEL := 2.5  # world units per s squared of (smoothed) speed change: a full lurch
## anim_row's slots: ANIM's keys in order, each with the value a row that omits it takes.
enum { A_LEAN, A_STRIDE, A_BOUNCE, A_ROCK, A_RUMBLE, A_RUMBLE_HZ, A_LURCH, A_SWAY, A_SWAY_HZ, A_DUST, A_DUST_SIZE, A_DUST_BACK,
	A_DUST_ALPHA, A_WASH }
const ANIM_KEYS := {"lean": 0.0, "stride": 0.0, "bounce": 0.0, "rock": 0.0, "rumble": 0.0, "rumble_hz": 10.0, "lurch": 0.0,
	"sway": 0.0, "sway_hz": 1.0, "dust": 0.0, "dust_size": 0.3, "dust_back": 0.25, "dust_alpha": 0.45, "wash": 0.0}
static var _anim_rows: Dictionary = {}


## A kind's ANIM row as packed numbers (the A_ slots), built once per kind: the per-frame paths read slots, not keys. An
## unknown kind animates as a Tank.
static func anim_row(kind: String) -> PackedFloat64Array:
	var row = _anim_rows.get(kind)
	if row == null:
		var spec: Dictionary = ANIM.get(kind, ANIM["Tank"])
		row = PackedFloat64Array()
		for key in ANIM_KEYS:
			row.append(float(spec.get(key, ANIM_KEYS[key])))
		_anim_rows[kind] = row
	return row


## Poses `card` for one frame of movement: `kind` a UNIT_KINDS name, `speed` its smoothed ground speed (world units per
## s), `t` the effects clock (s), `gait` the distance it has walked (world units), `heading` the motion's screen-x share
## (-1 left .. 1 right), `lurch` its smoothed acceleration as a share of LURCH_ACCEL (-1 braking .. 1 pulling away). At
## ANIM_STILL or slower it ends the animation layer (the card returns exactly to its rest) and returns false.
static func animate(card: Node3D, kind: String, speed: float, t: float, gait := 0.0, heading := 0.0, lurch := 0.0) -> bool:
	if speed <= ANIM_STILL:
		if card.has_meta("pose_anim"):
			card.remove_meta("pose_anim")
			apply_pose(card)
		return false
	var row := anim_row(kind)
	var a := smoothstep(ANIM_STILL, ANIM_FULL, speed)
	var lean := heading * row[A_LEAN] * a
	var g := 1.0  # the standing height's scale on screen
	var sx := 1.0
	var stride := row[A_STRIDE]
	if stride > 0.0:
		var step := sin(PI * gait / stride)  # a half wave per footfall
		g += row[A_BOUNCE] * a * (absf(step) - 0.5)
		lean += row[A_ROCK] * a * step * 0.5
	var rumble := row[A_RUMBLE]
	if rumble > 0.0:
		var hz := TAU * row[A_RUMBLE_HZ] * t
		g += rumble * a * (0.6 * sin(hz) + 0.4 * sin(hz * 1.73 + 1.1))
		lean += rumble * 0.35 * a * sin(hz * 0.61 + 2.0)
	var sway := row[A_SWAY]
	if sway > 0.0:
		var hz := TAU * row[A_SWAY_HZ] * t
		lean += sway * a * sin(hz)
		g += sway * 0.3 * a * sin(hz * 2.0 + 0.7)
	var st := row[A_LURCH]  # times the lurch: over 0 pulling away (stretch, lean back), under 0 braking
	if st > 0.0 and lurch != 0.0:
		st *= clampf(lurch, -1.0, 1.0) * smoothstep(ANIM_STILL, 3.0 * ANIM_STILL, speed)  # gone as the unit settles
		var along := absf(heading)
		lean -= heading * st
		sx += st * (along - 0.4 * (1.0 - along))
		g += st * ((1.0 - along) - 0.4 * along)
	var c := cos_pitch()
	pose_begin(card)
	# local y is the standing part's height times cos_pitch on screen: a lean of the top by `lean` of the standing height
	# is a shear of lean / c, and a screen height scale g is a local y scale 1 + (g - 1) / c^2 (the part's depth stays)
	card.set_meta("pose_anim", Vector3(lean / c, sx, 1.0 + (g - 1.0) / (c * c)))
	apply_pose(card)
	return true
