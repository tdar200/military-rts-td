extends RefCounted
## Kestrel combat effects (plan 2026-10-05-kestrel-combat-motion-fx, Task 2): layered fire, smoke and spark cards in place
## of the legacy sphere flash and shard ring. earthfront_3d.gd builds one only when `world_art_on` is true; Survival keeps
## its spheres.
##
## Cards: flipbook frames of one deterministic atlas (tools/ui/build_fx_atlas.py), drawn as POOL slots of three
## MultiMeshes, one shared material each (ground decals, smoke, glow). A card's frame, tint and fade travel in its
## instance data (INSTANCE_CUSTOM is the frame's atlas rect, COLOR the tint and fade), so no card ever owns a material or a
## node, and a busy fight costs three draw calls. Every texel is premultiplied and the shader blends ONE,
## ONE_MINUS_SRC_ALPHA: fire, flash and sparks (alpha 0) add light, smoke, debris and rubble (alpha 1) cover.
##
## Cards face the camera: their quad lies in the view plane (the camera's basis, the fixed north-up Kestrel view when there
## is no camera), centred on an anchor moved NUDGE toward the camera. The view is orthographic, so the nudge keeps the
## card's place on screen and only lifts it over the sprite card it burns on. Motion (drift, rise, fall) is in screen units.
## Ground cards (glow, dust ring, rubble) lie flat on the ground instead: a camera-facing decal would be cut by the terrain
## in front of it.
##
## Pool: POOL live cards at most; a spawn past the cap takes the oldest card's slot (a free-slot stack and a spawn-order
## ring keep both lookups O(1), so a saturated firefight never scans the pool). Every card frees its slot when its
## life ends; the layers hide when no card is live (idle frames draw nothing). An effect whose anchor is outside the view
## (set_view) plus VIEW_MARGIN spawns nothing.
##
## Dust (Task 4): `dust(pos, size)` is a soft puff rising where a moving unit's tracks or boots meet the ground, `wash(pos, size)` a moving gunship's rotor wash (a ring spreading on the ground, two puffs blown
## aside). Both are the smoke and dust-ring sprites of the human band tinted KICKED_TINT, a pale sandy tan.
##
## Shots (Task 3): `shot(from, to, attacker_kind, owner)` draws one round of the bridge's shots window on the same cards:
## a muzzle flash, a tracer, shell or plasma bolt (row 3 of the band: a vertical streak, head up) stretched along the
## shot's screen direction and flying muzzle to target, and an impact flash when it lands. Everything is screen space:
## the view is orthographic, so a card offset along the camera's right and up lands where the world point projects.

const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")

const ATLAS := "res://assets/world/fx/fx_atlas.png"
const CELL_PX := 128
const COLS := 8
const BAND_ROWS := 4  # per band: fireball frames, smoke frames, single sprites, shot sprites
const FRAMES := 8
const POOL := 128  # Task 3 doubled it: a firefight's shots (up to 6 cards each) must not recycle a collapse's rubble
const SPAWN_RING := POOL * 2  # the spawn-order ring (live cards plus the expired entries not yet dropped)
const STRIDE := 20  # floats per instance in a MultiMesh buffer: a 3x4 transform, a colour, the custom data
const NUDGE := 1.2  # world units toward the camera for smoke and glow cards
## Dust (Task 4) sits low: a moving unit's own card, drawn with a depth pre-pass, hides the dust rising behind it.
const DUST_NUDGE := 0.12
## Dust is the lowest priority: it spawns only while fewer than DUST_ROOM cards are live, so it never takes the slot of a
## combat effect (the pool recycles the oldest card at POOL).
const DUST_ROOM := 80
const DUST_LIFE := 0.85
const GROUND_LIFT := 0.06  # decals lie flat on the ground this far over the anchor (the ground height at their centre)
const VIEW_MARGIN := 2.5
## The most cards each recipe spawns (the tests hold them to it).
const FLASH_MAX_CARDS := 1
const HIT_MAX_CARDS := 4
const EXPLODE_MAX_CARDS := 9
const COLLAPSE_MAX_CARDS := 15
const SHOT_MAX_CARDS := 6
## Hit size by weight class (world units): 0 infantry, 1 anti-armour or gun, 2 tank, 3 gunship, capital or building.
const HIT_SIZE := [0.32, 0.46, 0.66, 0.86]
const FLASH_SIZE := [0.28, 0.36, 0.50, 0.62]

## Sprites. FIREBALL and SMOKE are 8-frame flipbooks; the rest are single cells of row 2 (RUBBLE spans two) and, for
## the shot sprites, of row 3.
enum {FIREBALL, SMOKE, FLASH, SPARKS, DEBRIS, EMBER, GLOW, RING, RUBBLE, TRACER, SHELL, BOLT}
const SINGLE_COL := {FLASH: 0, SPARKS: 1, DEBRIS: 2, EMBER: 3, GLOW: 4, RING: 5, RUBBLE: 6}
const SHOT_COL := {TRACER: 0, SHELL: 1, BOLT: 2}
## Card layers: one MultiMesh and one material each.
enum {LAYER_GROUND, LAYER_SMOKE, LAYER_GLOW}
const LAYER_OF := {FIREBALL: LAYER_GLOW, FLASH: LAYER_GLOW, SPARKS: LAYER_GLOW, EMBER: LAYER_GLOW, SMOKE: LAYER_SMOKE,
	DEBRIS: LAYER_SMOKE, GLOW: LAYER_GROUND, RING: LAYER_GROUND, RUBBLE: LAYER_GROUND, TRACER: LAYER_GLOW, SHELL: LAYER_GLOW,
	BOLT: LAYER_GLOW}
const LAYER_NAMES := ["WorldFxGround", "WorldFxSmoke", "WorldFxGlow"]
## Render priority per layer: decals with the prop decals (under every card and overlay), smoke over the sprite cards and
## the placement ghost (1), fire over smoke.
const LAYER_PRIORITY := [-1, 2, 3]
## Tints (times the atlas colour; over 1 brightens the emissive texels).
const SMOKE_TINT := [Color(0.42, 0.40, 0.38), Color(0.40, 0.36, 0.44)]
const DUST_TINT := Color(0.95, 0.86, 0.68)
## Kicked-up dust (dust, wash): over 1, so the grey smoke and ring sprites come out a pale sandy tan over the grass.
const KICKED_TINT := Color(1.8, 1.6, 1.25)
const FIRE_TINT := Color(1.0, 1.0, 1.0)
## The Kestrel post chain halves saturation (WorldArt.ENVIRONMENT) and its filmic shoulder whitens bright fire, so the cards
## pre-grade their colour about its luminance, as WorldSprites.GRADE does for the sprite cards.
const SATURATION := 1.9
## Shots. A style per attacker kind: rifle (infantry, guns, anything unknown: a short bright streak), shell (tanks,
## anti-armour, capitals: a slower glowing slug with a trail and a muzzle puff), burst (gunships: two short streaks side
## by side). Aliens fire plasma bolts in every style. Per style: [speed (world units per s), shortest and longest flight
## (s), card width, longest streak (world units)], human then alien.
enum {STYLE_RIFLE, STYLE_SHELL, STYLE_BURST}
const SHOT_LOOK := [
	[[26.0, 0.05, 0.15, 0.15, 0.72], [16.0, 0.07, 0.22, 0.26, 0.55]],
	[[10.0, 0.12, 0.38, 0.30, 0.55], [9.0, 0.13, 0.4, 0.36, 0.62]],
	[[28.0, 0.04, 0.13, 0.13, 0.55], [18.0, 0.06, 0.18, 0.22, 0.45]],
]
const SHOT_TINT := Color(1.5, 1.5, 1.5)  # streaks and muzzle flashes over 1: they must read on sunlit grass
const BURST_GAP := 0.09  # screen units between a gunship's paired streaks
const BURST_STAGGER := 0.05  # s between them
## Where a round leaves and lands, as a screen-up offset over the ground point: MUZZLE of the attacker's card width (plus
## the card's hover), and IMPACT_LIFT over the target's ground point (the dispatcher passes its own for tall targets).
const MUZZLE := 0.3
const IMPACT_LIFT := 0.22

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float saturation = 1.0;
varying vec4 rect;
void vertex() {
    rect = INSTANCE_CUSTOM;  // the frame: atlas u, v, width, height (a negative width mirrors it)
}
void fragment() {
    vec4 c = texture(atlas, rect.xy + UV * rect.zw);
    vec3 rgb = c.rgb * COLOR.rgb;
    rgb = max(mix(vec3(dot(rgb, vec3(0.299, 0.587, 0.114))), rgb, saturation), vec3(0.0));
    ALBEDO = rgb * COLOR.a;  // premultiplied: the fade scales colour and cover together
    ALPHA = c.a * COLOR.a;
}
"""

static var _shader: Shader
static var _materials: Array = [null, null, null]

var camera: Camera3D  # optional: the cards face it; without one they face the fixed Kestrel view
## Kestrel fog of war (a FogView, or null): an effect spawns only where the player sees now or saw on the last poll.
var fog: RefCounted
var time := 0.0
var speed := 1.0  # presentation time scale; QA sets 0 to hold the effects still for a capture
var _layers: Array[MultiMeshInstance3D] = []
var _cards: Array[Dictionary] = []
var _buffers: Array[PackedFloat32Array] = []
var _serial := 0
var _live := 0
var _probes := 0  # slots examined to find a spawn its slot (tests: slot_probes)
var _free := PackedInt32Array()  # the free slots, a stack
## The live cards in spawn order, a ring of (slot, serial). A card that expires leaves its entry behind; an entry
## counts only while its slot still holds that serial, live. A full pool takes the first live entry: O(1) amortised.
var _ring_slot := PackedInt32Array()
var _ring_serial := PackedInt32Array()
var _ring_head := 0
var _ring_len := 0
var _view_focus := Vector3.ZERO
var _view_half := Vector2(INF, INF)
var _warm := 0


## The one material of `layer` (LAYER_GROUND, LAYER_SMOKE, LAYER_GLOW), shared by every effect system.
static func material_for(layer: int) -> Material:
	if _materials[layer] == null:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("atlas", load(ATLAS) as Texture2D)
		m.set_shader_parameter("saturation", SATURATION)
		m.render_priority = LAYER_PRIORITY[layer]
		_materials[layer] = m
	return _materials[layer]


## Weight class of a kind for hit sizes: 0 infantry, 1 anti-armour and guns, 2 tanks and harvesters, 3 gunships, capitals
## and buildings.
static func weight_for(kind: String) -> int:
	match kind:
		"Infantry":
			return 0
		"AntiArmor", "GunTurret", "AaTurret":
			return 1
		"Tank", "Harvester":
			return 2
	return 3


func build(parent: Node3D) -> void:
	_cards.clear()
	for i in POOL:
		_cards.append({"live": false, "serial": -1})
	_free.clear()
	for i in range(POOL - 1, -1, -1):
		_free.push_back(i)  # slot 0 first
	_ring_slot.resize(SPAWN_RING)
	_ring_serial.resize(SPAWN_RING)
	_ring_head = 0
	_ring_len = 0
	_buffers.clear()
	_layers.clear()
	for layer in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mm.mesh = q
		mm.instance_count = POOL
		mm.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))  # the cards move every frame
		var mmi := MultiMeshInstance3D.new()
		mmi.name = LAYER_NAMES[layer]
		mmi.multimesh = mm
		mmi.material_override = material_for(layer)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		parent.add_child(mmi)
		_layers.append(mmi)
		var buf := PackedFloat32Array()
		buf.resize(POOL * STRIDE)
		_buffers.append(buf)
		mm.buffer = buf
	if DisplayServer.get_name() != "headless":
		_warm = 20  # draw the empty layers for a few frames so the renderer compiles the shader before the first fight


func layers() -> Array:
	return _layers


## The camera's view on the ground: effects anchored outside it (plus VIEW_MARGIN) are not drawn.
func set_view(focus: Vector3, half_extent: Vector2) -> void:
	_view_focus = focus
	_view_half = half_extent


func pool_count() -> int:
	return _live


func spawned_total() -> int:
	return _serial


## Tests: how many pool slots the spawns have examined in all (the cost of finding a slot).
func slot_probes() -> int:
	return _probes


func live_serials() -> Array:
	var out := []
	for c in _cards:
		if c.live:
			out.append(c.serial)
	return out


func live_sprites() -> Dictionary:
	var out := {}
	for c in _cards:
		if c.live:
			out[c.sprite] = true
	return out


func live_bands() -> Dictionary:
	var out := {}
	for c in _cards:
		if c.live:
			out[c.band] = true
	return out


func slot_live(slot: int) -> bool:
	return bool(_cards[slot].live)


func find_slot(sprite: int) -> int:
	for i in _cards.size():
		if _cards[i].live and int(_cards[i].sprite) == sprite:
			return i
	return -1


## The transform a slot was last drawn with (zero while waiting on its delay or free); readable without a renderer.
func slot_transform(slot: int) -> Transform3D:
	var layer := int(_cards[slot].get("layer", 0))
	var b := _buffers[layer]
	var o := slot * STRIDE
	return Transform3D(Basis(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]), Vector3(b[o + 2], b[o + 6], b[o + 10])),
		Vector3(b[o + 3], b[o + 7], b[o + 11]))


## The atlas rect (u, v, width, height as r, g, b, a) a slot was last drawn with.
func slot_rect(slot: int) -> Color:
	var layer := int(_cards[slot].get("layer", 0))
	var o := slot * STRIDE + 16
	var b := _buffers[layer]
	return Color(b[o], b[o + 1], b[o + 2], b[o + 3])


## Whether a ground point is on screen (plus VIEW_MARGIN) and, under fog, seen: the shot dispatcher skips a shot with
## neither end in view.
func in_view(pos: Vector3) -> bool:
	return _in_view(pos)


func _in_view(pos: Vector3) -> bool:
	if absf(pos.x - _view_focus.x) > _view_half.x + VIEW_MARGIN or absf(pos.z - _view_focus.z) > _view_half.y + VIEW_MARGIN:
		return false
	return fog == null or fog.seen_recently(pos)


func _band(owner: int) -> int:
	return 0 if owner == 0 else 1


## Muzzle flash: one star, 0.08 to 0.14 s.
func flash(pos: Vector3, weight: int, owner: int) -> int:
	if _layers.is_empty() or not _in_view(pos):
		return 0
	var w := clampi(weight, 0, 3)
	var s := float(FLASH_SIZE[w])
	_card(FLASH, _band(owner), pos, {"life": 0.08 + 0.02 * w, "size": [s, s * 1.15], "off": Vector2(0, 0.25), "rot": _spin_of(_serial) * 0.8,
		"tint": FIRE_TINT, "fade_out": 0.5})
	return 1


## A round landing on `pos`: a flash and sparks, a small fireball from weight 1, a smoke puff from weight 2. `owner` is
## the firing side (its colours).
func hit(pos: Vector3, weight: int, owner: int) -> int:
	if _layers.is_empty() or not _in_view(pos):
		return 0
	var w := clampi(weight, 0, 3)
	var b := _band(owner)
	var s := float(HIT_SIZE[w])
	var lift := Vector2(0, 0.18 + s * 0.35)
	var n := 0
	_card(FLASH, b, pos, {"life": 0.13, "size": [s * 1.1, s * 1.3], "off": lift, "rot": _spin_of(_serial), "tint": FIRE_TINT, "fade_out": 0.4})
	_card(SPARKS, b, pos, {"life": 0.24, "size": [s * 0.6, s * 1.5], "off": lift, "rot": _spin_of(_serial), "tint": FIRE_TINT, "fade_out": 0.35})
	n += 2
	if w >= 1:
		_card(FIREBALL, b, pos, {"life": 0.42 + 0.1 * w, "size": [s * 0.7, s * 1.25], "off": lift, "vel": Vector2(0, 0.3), "tint": FIRE_TINT,
			"fade_out": 0.7})
		n += 1
	if w >= 2:
		_card(SMOKE, b, pos, {"delay": 0.1, "life": 1.3, "size": [s * 0.8, s * 1.9], "off": lift, "vel": Vector2(0.06, 0.45),
			"tint": SMOKE_TINT[b], "alpha": 0.75, "fade_in": 0.15, "fade_out": 0.4})
		n += 1
	return n


## A unit dying at `pos` (its ground point), `size` its card width in tiles: a ground glow, two fireballs, sparks, flying
## debris, a two-puff smoke plume, embers and a scorch that smoulders for 4 s, in the dying side's colours.
func explode(pos: Vector3, size: float, owner: int) -> int:
	if _layers.is_empty() or not _in_view(pos):
		return 0
	var b := _band(owner)
	var s := clampf(size * WorldArt.TILE, 0.5, 2.2)
	var lift := Vector2(0, s * 0.32)
	_card(GLOW, b, pos, {"life": 0.7, "size": [s * 1.6, s * 2.0], "ground": 1.0, "tint": FIRE_TINT, "alpha": 0.55, "fade_out": 0.3})
	_card(RUBBLE, b, pos, {"life": 4.0, "size": [s * 1.2, s * 1.2], "ground": 0.5, "alpha": 0.8, "fade_in": 0.03, "fade_out": 0.55})
	_card(FIREBALL, b, pos, {"life": 0.95, "size": [s * 0.8, s * 1.55], "off": lift, "vel": Vector2(0, 0.25), "tint": FIRE_TINT})
	_card(FIREBALL, b, pos, {"delay": 0.12, "life": 0.8, "size": [s * 0.6, s * 1.1], "off": lift + Vector2(s * 0.24, s * 0.18),
		"vel": Vector2(0.1, 0.35), "tint": FIRE_TINT})
	_card(SPARKS, b, pos, {"life": 0.32, "size": [s * 0.8, s * 1.9], "off": lift, "tint": FIRE_TINT, "fade_out": 0.4})
	_card(DEBRIS, b, pos, {"life": 0.95, "size": [s * 0.45, s * 1.7], "off": lift, "vel": Vector2(0, 0.7), "acc": Vector2(0, -2.2),
		"spin": 3.0, "fade_out": 0.6})
	for k in 2:
		_card(SMOKE, b, pos, {"delay": 0.3 + 0.3 * k, "life": 2.2, "size": [s * 0.7, s * 1.9], "off": lift + Vector2(0, s * 0.2),
			"vel": Vector2(0.08, 0.6), "tint": SMOKE_TINT[b], "alpha": 0.85, "fade_in": 0.12, "fade_out": 0.45})
	_card(EMBER, b, pos, {"delay": 0.15, "life": 1.4, "size": [s * 0.8, s * 1.4], "off": lift, "vel": Vector2(0.05, 0.5), "tint": FIRE_TINT,
		"fade_in": 0.1, "fade_out": 0.5})
	return 9


## A building destroyed at `pos` (its root), `tiles` its card width: a dust ring and two dust puffs, a ground glow, a
## rolling fireball (three staggered balls climbing the ruin), sparks, debris, a four-puff smoke column and embers over
## a burning rubble decal that fades over about 6 s, in the building side's colours.
func collapse(pos: Vector3, tiles: float, owner: int) -> int:
	if _layers.is_empty() or not _in_view(pos):
		return 0
	var b := _band(owner)
	var w := clampf(tiles * WorldArt.TILE, 0.6, 2.4)
	var lift := w * 0.3
	_card(RUBBLE, b, pos, {"life": 6.0, "size": [w * 1.15, w * 1.15], "ground": 0.5, "alpha": 0.95, "fade_in": 0.02, "fade_out": 0.55})
	_card(RING, b, pos, {"life": 1.4, "size": [w * 0.6, w * 2.1], "ground": 1.0, "tint": DUST_TINT, "alpha": 0.85, "fade_out": 0.35})
	_card(GLOW, b, pos, {"life": 1.2, "size": [w * 1.6, w * 2.1], "ground": 1.0, "tint": FIRE_TINT, "alpha": 0.55, "fade_out": 0.4})
	for side in [-1.0, 1.0]:
		_card(SMOKE, b, pos, {"life": 1.8, "size": [w * 0.5, w * 1.05], "off": Vector2(side * w * 0.45, w * 0.12),
			"vel": Vector2(side * 0.5, 0.12), "tint": DUST_TINT, "alpha": 0.8, "fade_out": 0.4})
	var rolls := [Vector2(-0.22, 0.5), Vector2(0.2, 0.95), Vector2(0.0, 1.6)]
	for k in rolls.size():
		var r: Vector2 = rolls[k]
		_card(FIREBALL, b, pos, {"delay": 0.18 * k, "life": 1.1, "size": [w * 0.7, w * 1.25], "off": Vector2(r.x * w, r.y * lift),
			"vel": Vector2(0, 0.35), "tint": FIRE_TINT})
	_card(SPARKS, b, pos, {"delay": 0.05, "life": 0.4, "size": [w, w * 2.0], "off": Vector2(0, lift), "tint": FIRE_TINT, "fade_out": 0.4})
	_card(DEBRIS, b, pos, {"life": 1.2, "size": [w * 0.6, w * 2.0], "off": Vector2(0, lift), "vel": Vector2(0, 0.8), "acc": Vector2(0, -2.0),
		"spin": 2.0, "fade_out": 0.6})
	for k in 4:
		_card(SMOKE, b, pos, {"delay": 0.5 + 0.55 * k, "life": 3.0, "size": [w * 0.6, w * 1.7], "off": Vector2(0, lift * 1.4),
			"vel": Vector2(0.1, 0.55), "tint": SMOKE_TINT[b], "alpha": 0.85, "fade_in": 0.12, "fade_out": 0.5})
	_card(EMBER, b, pos, {"delay": 0.4, "life": 2.5, "size": [w * 0.8, w * 1.5], "off": Vector2(0, lift), "vel": Vector2(0.06, 0.45),
		"tint": FIRE_TINT, "fade_in": 0.1, "fade_out": 0.6})
	return 15


## A dust puff `size` wide at the ground point `pos`: it swells, rises a little, drifts by `drift` (screen units per s)
## and fades over DUST_LIFE. Nothing when the pool is busy (DUST_ROOM) or `pos` is out of view. Returns the cards spawned.
func dust(pos: Vector3, size: float, drift := Vector2.ZERO, alpha := 0.45) -> int:
	if _layers.is_empty() or _live >= DUST_ROOM or not _in_view(pos):
		return 0
	_card(SMOKE, 0, pos, {"life": DUST_LIFE, "size": [size * 0.55, size], "off": Vector2(0.0, size * 0.32), "vel": drift + Vector2(0.0, 0.1),
		"tint": KICKED_TINT, "alpha": alpha, "fade_in": 0.12, "fade_out": 0.3, "nudge": DUST_NUDGE})
	return 1


## A moving gunship's rotor wash on the ground point `pos` under it: a dust ring spreading flat on the ground and a puff
## blown out to either side, `size` the puffs' width.
func wash(pos: Vector3, size: float) -> int:
	if _layers.is_empty() or _live >= DUST_ROOM or not _in_view(pos):
		return 0
	_card(RING, 0, pos, {"life": 0.6, "size": [size * 0.9, size * 2.2], "ground": 0.55, "tint": KICKED_TINT, "alpha": 0.35, "fade_in": 0.1,
		"fade_out": 0.3})
	for side in [-1.0, 1.0]:
		_card(SMOKE, 0, pos, {"life": DUST_LIFE, "size": [size * 0.4, size * 0.8], "off": Vector2(side * size * 0.35, size * 0.25),
			"vel": Vector2(side * 0.45, 0.06), "tint": KICKED_TINT, "alpha": 0.3, "fade_in": 0.12, "fade_out": 0.3, "nudge": DUST_NUDGE})
	return 3


static func shot_style(kind: String) -> int:
	match kind:
		"Tank", "AntiArmor", "Capital":
			return STYLE_SHELL
		"Helicopter":
			return STYLE_BURST
	return STYLE_RIFLE


static func _look(kind: String, owner: int) -> Array:
	return SHOT_LOOK[shot_style(kind)][0 if owner == 0 else 1]


## Seconds a round of `kind` fired by `owner` takes from `from` to `to` (ground points).
static func flight_time(from: Vector3, to: Vector3, kind: String, owner: int) -> float:
	var look := _look(kind, owner)
	var d := Vector2(to.x - from.x, to.z - from.z).length()
	return clampf(d / float(look[0]), float(look[1]), float(look[2]))


## Screen-up height of a kind's muzzle over its ground point: a share of its card width, plus a gunship's hover.
static func muzzle_lift(kind: String) -> float:
	var width := WorldSprites.tiles_for(kind) * WorldArt.TILE
	if width <= 0.0:
		width = 0.66  # an unknown kind: an infantry card
	return clampf(width * MUZZLE, 0.12, 0.7) + float(WorldSprites.HOVER.get(kind, 0.0)) * WorldSprites.cos_pitch()


## One round from `from` to `to` (ground points), fired by a `attacker_kind` of `owner` after `delay` seconds: a muzzle
## flash (and a puff of smoke for a shell), a tracer, shell or bolt card stretched along the shot's screen direction that
## flies muzzle to target, and an impact flash and sparks (and a small fireball for a shell) when it lands, sized by the
## attacker's weight. Nothing when neither end is in view. Returns the cards spawned (SHOT_MAX_CARDS at most).
func shot(from: Vector3, to: Vector3, attacker_kind: String, owner: int, delay := 0.0, target_lift := IMPACT_LIFT) -> int:
	if _layers.is_empty() or not (_in_view(from) or _in_view(to)):
		return 0
	var b := _band(owner)
	var style := shot_style(attacker_kind)
	var look := _look(attacker_kind, owner)
	var w := weight_for(attacker_kind) if WorldSprites.MOCK_PX.has(attacker_kind) else 0  # unknown: the infantry look
	var flight := flight_time(from, to, attacker_kind, owner)
	var basis := _view_basis()
	var muzzle := Vector2(0.0, muzzle_lift(attacker_kind))
	var delta := to - from
	var land := Vector2(delta.dot(basis.x), delta.dot(basis.y) + target_lift)  # the target in the muzzle anchor's screen frame
	var path := land - muzzle
	var dist := path.length()
	var dir := path / dist if dist > 1e-4 else Vector2.UP
	var angle := atan2(-dir.x, dir.y)  # turns the card's up (the streak's head) along the shot
	var n := 0
	var fw := 1 if style == STYLE_BURST else clampi(w, 0, 3)  # a gunship's rounds are light, however heavy the gunship
	var fs := float(FLASH_SIZE[fw])
	_card(FLASH, b, from, {"delay": delay, "life": 0.09 + 0.02 * fw, "size": [fs, fs * 1.15], "off": muzzle + dir * fs * 0.2,
		"rot": _spin_of(_serial) * 0.8, "tint": SHOT_TINT, "fade_out": 0.45})
	n += 1
	if style == STYLE_SHELL:
		_card(SMOKE, b, from, {"delay": delay + 0.03, "life": 0.7, "size": [fs * 0.6, fs * 1.4], "off": muzzle, "vel": Vector2(-dir.x * 0.25, 0.35),
			"tint": SMOKE_TINT[b], "alpha": 0.55, "fade_in": 0.1, "fade_out": 0.35})
		n += 1
	var sprite := BOLT if b == 1 else (SHELL if style == STYLE_SHELL else TRACER)
	var width := float(look[3]) * (1.25 if w == 3 and style == STYLE_SHELL else 1.0)
	var length := maxf(width * 1.2, minf(float(look[4]), dist * 0.6))
	var travel := maxf(0.0, dist - length)
	var streaks := 2 if style == STYLE_BURST else 1
	for k in streaks:
		var side := Vector2(-dir.y, dir.x) * (BURST_GAP * (k - 0.5) if streaks == 2 else 0.0)
		_card(sprite, b, from, {"delay": delay + BURST_STAGGER * k, "life": flight, "size": [width, width],
			"aspect": length / width, "off": muzzle + side + dir * (length * 0.5), "vel": dir * (travel / flight), "rot": angle,
			"tint": SHOT_TINT, "fade_in": 0.08, "fade_out": 0.8})
		n += 1
	var hs := float(HIT_SIZE[fw]) * (1.0 if style == STYLE_SHELL else 0.8)
	var hit_at := Vector2(0.0, target_lift)
	var lands := delay + flight + (BURST_STAGGER if streaks == 2 else 0.0)
	_card(FLASH, b, to, {"delay": lands, "life": 0.11, "size": [hs, hs * 1.3], "off": hit_at, "rot": _spin_of(_serial), "tint": FIRE_TINT,
		"fade_out": 0.4})
	_card(SPARKS, b, to, {"delay": lands, "life": 0.2, "size": [hs * 0.6, hs * 1.4], "off": hit_at, "rot": _spin_of(_serial),
		"tint": FIRE_TINT, "fade_out": 0.35})
	n += 2
	if style == STYLE_SHELL:
		_card(FIREBALL, b, to, {"delay": lands, "life": 0.45, "size": [hs * 0.7, hs * 1.3], "off": hit_at, "vel": Vector2(0, 0.3),
			"tint": FIRE_TINT, "fade_out": 0.7})
		n += 1
	return n


## A deterministic angle for a card from its serial (no randomness: replays look the same).
static func _spin_of(serial: int) -> float:
	return fposmod(float(serial) * 2.39996, TAU)


## Spawns one card: `opts` life (s), delay (s), size [from, to] (world units, the card's width), off (screen offset of
## the centre from the anchor, world units), vel and acc (screen units per s and per s squared), rot and spin (radians,
## radians per s), tint, alpha (peak), fade_in and fade_out (fractions of the life), ground (0 for a camera-facing card,
## else a decal lying flat on the ground, north up, `ground` times as deep as wide: 1 for a round sprite, 0.5 for RUBBLE),
## aspect (height over width of a standing card, default 1), nudge (world units toward the camera, default NUDGE). Returns
## the slot.
func _card(sprite: int, band: int, anchor: Vector3, opts: Dictionary) -> int:
	var slot := -1
	if not _free.is_empty():  # a free slot (the oldest is only taken when every slot is live)
		_probes += 1
		slot = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	else:
		slot = _oldest_live()
		_live -= 1
		_clear_slot(slot)
	var c := _cards[slot]
	c.live = true
	c.serial = _serial
	c.sprite = sprite
	c.band = band
	c.layer = int(LAYER_OF[sprite])
	c.anchor = anchor
	c.born = time + float(opts.get("delay", 0.0))
	c.life = maxf(0.01, float(opts.get("life", 1.0)))
	var size: Array = opts.get("size", [1.0, 1.0])
	c.size0 = float(size[0])
	c.size1 = float(size[1])
	c.off = opts.get("off", Vector2.ZERO)
	c.vel = opts.get("vel", Vector2.ZERO)
	c.acc = opts.get("acc", Vector2.ZERO)
	c.rot = float(opts.get("rot", 0.0))
	c.spin = float(opts.get("spin", 0.0)) * (1.0 if _serial % 2 == 0 else -1.0)
	c.tint = opts.get("tint", Color.WHITE)
	c.alpha = float(opts.get("alpha", 1.0))
	c.fade_in = float(opts.get("fade_in", 0.0))
	c.fade_out = float(opts.get("fade_out", 0.6))
	c.ground = float(opts.get("ground", 0.0))
	c.aspect = float(opts.get("aspect", 1.0))
	c.nudge = float(opts.get("nudge", NUDGE))
	c.flip = sprite in [FIREBALL, SMOKE, DEBRIS, EMBER] and _serial % 2 == 1  # mirrored every other card: no two alike
	_ring_push(slot, _serial)
	_serial += 1
	_live += 1
	return slot


## Pops the oldest live card's slot off the spawn ring (skipping the entries of cards that already expired).
func _oldest_live() -> int:
	while _ring_len > 0:
		_probes += 1
		var slot := _ring_slot[_ring_head]
		var serial := _ring_serial[_ring_head]
		_ring_head = (_ring_head + 1) % SPAWN_RING
		_ring_len -= 1
		if _cards[slot].live and int(_cards[slot].serial) == serial:
			return slot
	push_error("WorldFx: a full pool with no live card on the spawn ring")
	return 0


func _ring_push(slot: int, serial: int) -> void:
	if _ring_len == SPAWN_RING:  # drop the expired entries: at most POOL stay, so this runs at most every POOL spawns
		var slots := PackedInt32Array()
		var serials := PackedInt32Array()
		for k in _ring_len:
			_probes += 1
			var i := (_ring_head + k) % SPAWN_RING
			var s := _ring_slot[i]
			if _cards[s].live and int(_cards[s].serial) == _ring_serial[i]:
				slots.push_back(s)
				serials.push_back(_ring_serial[i])
		var kept := slots.size()
		slots.resize(SPAWN_RING)
		serials.resize(SPAWN_RING)
		_ring_slot = slots
		_ring_serial = serials
		_ring_head = 0
		_ring_len = kept
	var at := (_ring_head + _ring_len) % SPAWN_RING
	_ring_slot[at] = slot
	_ring_serial[at] = serial
	_ring_len += 1


func _clear_slot(slot: int) -> void:
	_cards[slot].live = false
	for layer in _buffers.size():
		var o := slot * STRIDE
		for k in STRIDE:
			_buffers[layer][o + k] = 0.0


## The frame's atlas rect for a card at life fraction `f`.
func _rect(c: Dictionary, f: float) -> Color:
	var cw := 1.0 / COLS
	var ch := 1.0 / (2 * BAND_ROWS)
	var band_row := int(c.band) * BAND_ROWS
	var r: Color
	match int(c.sprite):
		FIREBALL, SMOKE:
			var frame := mini(FRAMES - 1, int(f * FRAMES))
			r = Color(frame * cw, (band_row + (0 if int(c.sprite) == FIREBALL else 1)) * ch, cw, ch)
		TRACER, SHELL, BOLT:
			r = Color(int(SHOT_COL[int(c.sprite)]) * cw, (band_row + 3) * ch, cw, ch)
		_:
			var col := int(SINGLE_COL[int(c.sprite)])
			r = Color(col * cw, (band_row + 2) * ch, cw * (2 if int(c.sprite) == RUBBLE else 1), ch)
	if c.flip:
		r = Color(r.r + r.b, r.g, -r.b, r.a)
	return r


func _view_basis() -> Basis:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera.global_transform.basis.orthonormalized()
	var s := WorldArt.PITCH_SIN
	var c := sqrt(1.0 - s * s)
	return Basis(Vector3(1, 0, 0), Vector3(0, c, -s), Vector3(0, s, c))


## Steps every card by `delta` seconds and redraws the layers (nothing at all while no card is live).
func advance(delta: float) -> void:
	if _layers.is_empty():
		return
	time += delta * speed
	if _live == 0:
		if _warm > 0:
			_warm -= 1
			for mmi in _layers:
				mmi.visible = _warm > 0
		return
	var basis := _view_basis()
	var right := basis.x
	var up := basis.y
	var back := basis.z
	var used := [false, false, false]
	for slot in POOL:
		var c := _cards[slot]
		if not c.live:
			continue
		var age := time - float(c.born)
		var life := float(c.life)
		if age >= life:
			_clear_slot(slot)
			_live -= 1
			_free.push_back(slot)
			continue
		var layer := int(c.layer)
		var buf := _buffers[layer]
		var o := slot * STRIDE
		if age < 0.0:  # waiting on its delay: drawn as nothing
			for k in 12:
				buf[o + k] = 0.0
			used[layer] = true
			continue
		var f := age / life
		var width := lerpf(float(c.size0), float(c.size1), 1.0 - (1.0 - f) * (1.0 - f))
		var ground := float(c.ground)
		var x: Vector3
		var y: Vector3
		var z := back
		var centre: Vector3
		if ground > 0.0:  # flat on the ground, north up: a sprite `ground` times as deep as wide
			x = Vector3(width, 0.0, 0.0)
			y = Vector3(0.0, 0.0, -width * ground)
			z = Vector3.UP
			centre = c.anchor + Vector3(0.0, GROUND_LIFT, 0.0)
		else:
			var height := width * float(c.aspect)
			var off: Vector2 = c.off + c.vel * age + c.acc * (0.5 * age * age)
			var angle := float(c.rot) + float(c.spin) * age
			var ca := cos(angle)
			var sa := sin(angle)
			x = (right * ca + up * sa) * width
			y = (up * ca - right * sa) * height
			centre = c.anchor + right * off.x + up * off.y + back * float(c.nudge)
		var a := float(c.alpha)
		if float(c.fade_in) > 0.0:
			a *= smoothstep(0.0, float(c.fade_in), f)
		a *= 1.0 - smoothstep(float(c.fade_out), 1.0, f)
		var tint: Color = c.tint
		var rect := _rect(c, f)
		buf[o] = x.x
		buf[o + 1] = y.x
		buf[o + 2] = z.x
		buf[o + 3] = centre.x
		buf[o + 4] = x.y
		buf[o + 5] = y.y
		buf[o + 6] = z.y
		buf[o + 7] = centre.y
		buf[o + 8] = x.z
		buf[o + 9] = y.z
		buf[o + 10] = z.z
		buf[o + 11] = centre.z
		buf[o + 12] = tint.r
		buf[o + 13] = tint.g
		buf[o + 14] = tint.b
		buf[o + 15] = a
		buf[o + 16] = rect.r
		buf[o + 17] = rect.g
		buf[o + 18] = rect.b
		buf[o + 19] = rect.a
		used[layer] = true
	for layer in _layers.size():
		var mmi := _layers[layer]
		if used[layer] or mmi.visible:
			mmi.multimesh.buffer = _buffers[layer]
		mmi.visible = used[layer]
