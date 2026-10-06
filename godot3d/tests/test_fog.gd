extends RefCounted
## Kestrel fog of war in the client (plan 2026-10-06-kestrel-next-level, Task 7). The bridge sends a per-cell mask (`fog`:
## 0 unseen, 1 explored, 2 visible) and omits enemies out of sight; the client draws the mask on the ground and the props,
## never re-announces an enemy that comes back into sight, dims remembered buildings and keeps them out of picking, and
## gates every world-positioned effect and sound by what the player can see. A missing or all-visible mask (Survival,
## EARTHFRONT_FOG=0) changes nothing.
const FogView := preload("res://scripts/world/fog_view.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")
const WorldFx := preload("res://scripts/world/world_fx.gd")
const MainScene = preload("res://main.tscn")
const VM = preload("res://scripts/ui/vm_gameplay.gd")
const Maps = preload("res://scripts/ui/vm_maps.gd")
const GroundModel = preload("res://scripts/terrain/ground_model.gd")
const Stub = preload("res://tests/stub_game.gd")
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Assault = preload("res://scripts/ui/live_assault.gd")
const W := 44
const H := 26
## The client's hex geometry (earthfront_3d.gd MAP_ORIGIN_X/Z, HEX_X/Z).
const OX := 2.1
const OZ := 1.0
const HX := 0.68
const HZ := 0.70


class Recorder extends RefCounted:
	var calls: Array = []
	var loop_calls: Array = []

	func request(id: String, at: Vector3, now: float) -> Dictionary:
		calls.append({"id": id, "at": at, "now": now})
		return {"play": false, "id": id, "reason": "recorded"}

	func set_view(_rect: Rect2) -> void:
		pass

	func set_paused(_on: bool) -> void:
		pass

	func loops(moving: Dictionary) -> Dictionary:
		loop_calls.append(moving)
		return {}

	func duck_db(_now: float) -> float:
		return 0.0

	func ids() -> Array:
		return calls.map(func(c): return c["id"])


const UI_STUB := """extends Node
var session_log := Log.new()
var hud := Control.new()
var notes: Array = []
func set_tab(_tab: String) -> void:
	pass
func notify(title: String, _body: String, _color: Color) -> void:
	notes.append(title)
func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
	return true
class Log:
	var added: Array = []
	var removed: Array = []
	func unit_added(kind: String, team: int, _category: String) -> void:
		added.append([kind, team])
	func unit_removed(kind: String, team: int, _category: String) -> void:
		removed.append([kind, team])
"""


static func _hex(x: int, y: int) -> Vector3:
	return Vector3(OX + float(x) * HX, 0.0, OZ + float(y) * HZ + (HZ * 0.5 if x % 2 else 0.0))


## A mask string: every cell unseen except `explored` (1) and `visible` (2), both lists of Vector2i.
static func _mask(visible: Array, explored := []) -> String:
	var cells := PackedByteArray()
	cells.resize(W * H)
	cells.fill(48)
	for c in explored:
		cells[c.y * W + c.x] = 49
	for c in visible:
		cells[c.y * W + c.x] = 50
	return cells.get_string_from_ascii()


## Every cell within `r` hex steps of `centre`.
static func _disc(centre: Vector2i, r: int) -> Array:
	var out: Array = []
	for y in H:
		for x in W:
			if VM.hex_distance(centre.x, centre.y, x, y) <= r:
				out.append(Vector2i(x, y))
	return out


# ------------------------------------------------------------------ FogView: parse and sample

func test_parse_reads_the_three_states_at_cell_centres(t) -> void:
	var fog = FogView.new()
	t.ok(fog.parse(_mask([Vector2i(5, 6), Vector2i(7, 3)], [Vector2i(5, 7), Vector2i(0, 0)]), W, H), "a new mask is a change")
	t.ok(fog.active(), "a mask with dark cells is active")
	t.eq(fog.state_at(_hex(5, 6)), FogView.VISIBLE, "visible cell")
	t.eq(fog.state_at(_hex(7, 3)), FogView.VISIBLE, "an odd column is read half a row lower, as the hexes sit")
	t.eq(fog.state_at(_hex(5, 7)), FogView.EXPLORED, "explored cell")
	t.eq(fog.state_at(_hex(0, 0)), FogView.EXPLORED, "corner cell")
	t.eq(fog.state_at(_hex(20, 20)), FogView.UNSEEN, "unseen cell")
	t.ok(fog.is_visible(_hex(5, 6)) and not fog.is_visible(_hex(5, 7)) and not fog.is_visible(_hex(20, 20)), "is_visible is state 2 only")
	t.ok(fog.is_visible(_hex(5, 6) + Vector3(0.2, 0.3, -0.2)), "a point inside the cell (any height) reads the cell")
	t.eq(fog.cell_state(7, 3), FogView.VISIBLE, "cell_state by column and row")
	t.eq(fog.width, W, "width")
	t.eq(fog.height, H, "height")


func test_missing_or_malformed_masks_mean_all_visible_without_a_warning(t) -> void:
	for bad in ["", "2", _mask([]).substr(1), _mask([]) + "0"]:
		var fog = FogView.new()
		fog.parse(bad, W, H)
		t.ok(not fog.active(), "a mask of length %d is not a fog" % bad.length())
		t.eq(fog.state_at(_hex(20, 20)), FogView.VISIBLE, "everything reads visible (length %d)" % bad.length())
		t.ok(fog.is_visible(Vector3(-50, 0, -50)), "even far off the map")
	var fog = FogView.new()
	t.ok(not fog.active() and fog.is_visible(_hex(3, 3)), "a fresh view (Survival: no key ever) is all visible")
	fog.parse(_mask([Vector2i(1, 1)]), 0, H)
	t.ok(not fog.active(), "a zero width is no grid")
	fog.parse("2".repeat(W * H), W, H)
	t.ok(not fog.active(), "an all-visible mask (EARTHFRONT_FOG=0) is not active")
	t.eq(fog.state_at(_hex(9, 9)), FogView.VISIBLE, "and reads visible")
	var src := (FogView as GDScript).source_code
	t.ok(not src.contains("push_warning") and not src.contains("push_error") and not src.contains("printerr"), "the safe path never warns")


func test_positions_off_the_grid_read_the_nearest_edge_cell(t) -> void:
	var fog = FogView.new()
	fog.parse(_mask([Vector2i(0, 0), Vector2i(43, 25)], [Vector2i(43, 0)]), W, H)
	t.eq(fog.state_at(Vector3(-30.0, 0.0, -30.0)), FogView.VISIBLE, "far north-west clamps to cell 0,0")
	t.eq(fog.state_at(Vector3(500.0, 0.0, 500.0)), FogView.VISIBLE, "far south-east clamps to 43,25")
	t.eq(fog.state_at(Vector3(500.0, 0.0, -30.0)), FogView.EXPLORED, "far north-east clamps to 43,0")
	t.eq(fog.state_at(Vector3(-30.0, 0.0, 500.0)), FogView.UNSEEN, "far south-west clamps to 0,25")
	t.eq(fog.cell_state(-1, 5), FogView.UNSEEN, "a column off the grid is clamped too (0,5 is dark)")
	t.eq(fog.cell_state(99, 99), FogView.VISIBLE, "and the far corner")


func test_seen_recently_covers_the_previous_poll(t) -> void:
	var fog = FogView.new()
	fog.parse(_mask([Vector2i(10, 10)]), W, H)
	fog.parse(_mask([Vector2i(12, 10)], [Vector2i(10, 10)]), W, H)
	t.ok(not fog.is_visible(_hex(10, 10)), "the old cell is no longer visible")
	t.ok(fog.seen_recently(_hex(10, 10)), "but was a poll ago (a viewer killed this tick still shows its death)")
	t.ok(fog.seen_recently(_hex(12, 10)), "the new cell is seen")
	fog.parse(_mask([Vector2i(12, 10)], [Vector2i(10, 10)]), W, H)
	t.ok(not fog.seen_recently(_hex(10, 10)), "one poll later it is forgotten")
	t.ok(not fog.seen_recently(_hex(30, 10)), "a cell never seen is never recent")


func test_deep_visible_needs_the_ring_around_the_point(t) -> void:
	var fog = FogView.new()
	fog.parse(_mask(_disc(Vector2i(20, 12), 3)), W, H)
	t.ok(fog.deep_visible(_hex(20, 12), 0.7), "the middle of a sight disc is deep inside")
	t.ok(fog.is_visible(_hex(23, 12)), "the rim cell is visible")
	t.ok(not fog.deep_visible(_hex(23, 12), 0.7), "but a unit there could have stepped into the dark")
	t.ok(not fog.deep_visible(_hex(30, 12), 0.1), "a dark point is never deep")
	var off = FogView.new()
	t.ok(off.deep_visible(_hex(30, 12), 2.0), "without fog everything is deep visible")


func test_explored_share_counts_explored_and_visible_cells(t) -> void:
	var fog = FogView.new()
	fog.parse(_mask([Vector2i(1, 1), Vector2i(2, 2)], [Vector2i(3, 3), Vector2i(4, 4)]), W, H)
	t.eq(fog.known_cells(), 4, "two explored plus two visible")
	t.eq(fog.explored_pct(), roundi(400.0 / float(W * H)), "as a whole percent of the map")
	t.eq(FogView.new().explored_pct(), 100, "no fog: the whole map is known")


# ------------------------------------------------------------------ FogView: texture

func test_texture_is_l8_one_texel_per_cell_and_refreshes_only_on_change(t) -> void:
	var fog = FogView.new()
	fog.parse(_mask([Vector2i(5, 6)], [Vector2i(6, 6)]), W, H)
	var tex: ImageTexture = fog.texture()
	t.ok(tex != null, "a texture")
	var img: Image = fog.image()
	t.eq(img.get_format(), Image.FORMAT_L8, "L8")
	t.eq(Vector2i(img.get_width(), img.get_height()), Vector2i(W, H), "one texel per cell")
	t.near(img.get_pixel(5, 6).r, 1.0, 0.01, "visible is white")
	t.near(img.get_pixel(6, 6).r, 128.0 / 255.0, 0.01, "explored is mid grey")
	t.near(img.get_pixel(20, 20).r, 0.0, 0.01, "unseen is black")
	var updates: int = fog.texture_updates
	t.ok(not fog.parse(_mask([Vector2i(5, 6)], [Vector2i(6, 6)]), W, H), "the same string again is no change")
	t.eq(fog.texture_updates, updates, "and the texture is not rewritten")
	t.ok(fog.parse(_mask([Vector2i(5, 7)], [Vector2i(6, 6), Vector2i(5, 6)]), W, H), "a moved viewer is a change")
	t.eq(fog.texture_updates, updates + 1, "rewritten once")
	t.ok(fog.texture() == tex, "the same texture object (materials keep their reference)")
	t.near(fog.image().get_pixel(5, 6).r, 128.0 / 255.0, 0.01, "the old cell now explored")


# ------------------------------------------------------------------ scene helpers

func _ui_stub() -> Node:
	var s := GDScript.new()
	s.source_code = UI_STUB
	s.reload()
	var n := Node.new()
	n.set_script(s)
	return n


func _snap(fog_off := false) -> Dictionary:
	var path := "res://tests/fixtures/kestrel_snapshot_fog_off.json" if fog_off else "res://tests/fixtures/kestrel_snapshot.json"
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	scene.world_fx.set_view(scene._hex_world(20, 12), Vector2(40, 30))
	scene.ui = _ui_stub()
	return scene


func _survival_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var snap := _snap()
	snap["ground"] = "g".repeat(W * H)
	scene._sync_ground(snap)
	scene.ui = _ui_stub()
	return scene


func _done(scene: Node3D) -> void:
	if scene.ui != null:
		scene.ui.hud.free()
		scene.ui.free()
	scene.free()


func _record(scene: Node3D) -> Recorder:
	var r := Recorder.new()
	scene.audio = r
	return r


func _unit(scene, id: int, kind: String, owner: int, tile: Vector2i, hp := 100) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * hp, "max_hp_bits": 65536 * 100}


func _building(scene, id: int, kind: String, owner: int, tile: Vector2i, construction := 0, hp := 100) -> Dictionary:
	var e := _unit(scene, id, kind, owner, tile, hp)
	e["category"] = "building"
	e["construction"] = construction
	e["construction_total"] = 100
	return e


## One poll's fog and entities, in the order _poll_bridge runs them (fog first).
func _poll(scene, tick: int, mask: String, entities: Array) -> void:
	scene._sync_fog({"tick": tick, "fog": mask})
	scene._sync_bridge_entities(entities)
	scene.bridge_tick = tick


## Effect cards alive plus deploy rings (a TorusMesh straight under the scene): what a death or an arrival would add.
func _live_cards(scene) -> int:
	var rings := 0
	for child in scene.get_children():
		if child is MeshInstance3D and child.mesh is TorusMesh and child != scene.hover_tile:
			rings += 1
	return scene.world_fx.pool_count() + rings


# ------------------------------------------------------------------ ground and props

func test_the_kestrel_ground_and_props_sample_the_mask_and_fog_off_draws_as_today(t) -> void:
	var scene := _kestrel_scene()
	var ground: ShaderMaterial = scene.terrain_renderer.get_node("ContinuousPainterlyTerrain").material_override
	t.ok(ground.shader.code.contains("uniform sampler2D fog_mask : filter_linear, repeat_disable"), "the ground samples the mask with a linear filter (soft edges), clamped at the map edge")
	t.eq(float(ground.get_shader_parameter("fog_enabled")), 0.0, "no fog before a mask arrives")
	scene._sync_fog({"tick": 10, "fog": _mask(_disc(Vector2i(8, 9), 4))})
	t.eq(float(ground.get_shader_parameter("fog_enabled")), 1.0, "a fogged mask switches the ground shroud on")
	t.ok(ground.get_shader_parameter("fog_mask") == scene.fog_view.texture(), "with the view's texture")
	for mmi in [scene.world_props.cards, scene.world_props.decals]:
		var m: ShaderMaterial = mmi.material_override
		t.ok(m.shader.code.contains("fog_mask"), "%s samples the mask" % mmi.name)
		t.eq(float(m.get_shader_parameter("fog_enabled")), 1.0, "%s is shrouded with the ground" % mmi.name)
		t.ok(m.get_shader_parameter("fog_mask") == scene.fog_view.texture(), "%s shares the texture" % mmi.name)
	var grid: Vector4 = ground.get_shader_parameter("fog_grid")
	t.eq(grid, Vector4(OX, OZ, HX, HZ), "the grid the shader maps world points to cells with")
	scene._sync_fog({"tick": 11, "fog": "2".repeat(W * H)})
	t.eq(float(ground.get_shader_parameter("fog_enabled")), 0.0, "EARTHFRONT_FOG=0 (all visible): the shroud is off, the ground draws as before fog")
	t.eq(float((scene.world_props.cards.material_override as ShaderMaterial).get_shader_parameter("fog_enabled")), 0.0, "and so do the props")
	scene._sync_fog({"tick": 12})
	t.eq(float(ground.get_shader_parameter("fog_enabled")), 0.0, "a snapshot without the key: off")
	_done(scene)


func test_the_shroud_is_near_black_blue_unseen_and_dim_explored(t) -> void:
	var code := FogView.SHADER_FUNCTIONS
	t.ok(code.contains("vec3 fog_tint(vec3 c, float v)"), "one shared tint function for the ground and the props")
	# The same arithmetic in GDScript (FogView.tint mirrors the shader): unseen is near black with more blue than red,
	# explored is a dim version of the ground, visible is the ground itself.
	var grass := Color(0.38, 0.42, 0.20)
	var unseen: Color = FogView.tint(grass, 0.0)
	var explored: Color = FogView.tint(grass, 0.5)
	var seen: Color = FogView.tint(grass, 1.0)
	t.ok(unseen.r < 0.04 and unseen.g < 0.05 and unseen.b < 0.05, "unseen is near black (%s)" % unseen)
	t.ok(unseen.b > unseen.r, "with a slight blue")
	t.ok(explored.get_luminance() > unseen.get_luminance() * 3.0 and explored.get_luminance() < grass.get_luminance() * 0.6, "explored is dim, not black")
	t.eq(seen, grass, "visible is untouched")


func test_survival_has_no_fog_anywhere(t) -> void:
	var scene := _survival_scene()
	var ground: ShaderMaterial = scene.terrain_renderer.get_node("ContinuousPainterlyTerrain").material_override
	t.ok(not ground.shader.code.contains("fog"), "the noise ground has no mask")
	t.eq(ground.get_shader_parameter("fog_mask"), null, "and no texture is set on it")
	scene._sync_fog({"tick": 5, "fog": _mask([])})
	t.ok(not scene.fog_view.active(), "Survival never reads a mask (the bridge sends none; even a stray one is ignored)")
	t.eq(scene.world_props, null, "no props, so no prop shroud")
	t.eq(scene.find_children("*Fog*", "", true, false).size(), 0, "no fog node")
	_done(scene)


# ------------------------------------------------------------------ entities

func test_an_enemy_leaving_sight_vanishes_silently_and_returns_without_a_reannouncement(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 5)
	var scout := _unit(scene, 500, "Tank", 1, Vector2i(19, 9))  # on the rim of sight
	scene.bridge_initialized = false
	_poll(scene, 100, _mask(sight), [cc, scout])
	scene.bridge_initialized = true
	t.ok(scene.bridge_nodes.has(500), "the alien tank in sight has a node")
	var cards := _live_cards(scene)
	# it walks east, out of sight: the bridge omits it, and its old cell is still visible
	_poll(scene, 104, _mask(sight), [cc])
	t.ok(not scene.bridge_nodes.has(500), "out of sight: its node is gone")
	t.eq(_live_cards(scene), cards, "no explosion: it walked into the dark, it did not die")
	t.eq(rec.calls.size(), 0, "and no sound")
	t.eq(scene.ui.session_log.removed, [], "no loss logged")
	t.ok(scene.fog_seen_ids.has(500), "it is remembered as seen")
	# it comes back
	_poll(scene, 140, _mask(sight), [cc, scout])
	t.ok(scene.bridge_nodes.has(500), "back in sight: a node again")
	t.eq(_live_cards(scene), cards, "no deploy ring for a unit walking back in")
	t.eq(scene.ui.session_log.added, [], "and no unit-added")
	t.eq(scene.ui.notes, [], "no toast")
	t.eq(rec.calls.size(), 0, "no sound")
	_done(scene)


func test_an_enemy_dying_in_plain_sight_still_explodes(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 6)
	var tank := _unit(scene, 510, "Tank", 1, Vector2i(14, 9))
	var turret := _building(scene, 511, "GunTurret", 1, Vector2i(16, 9))
	scene.bridge_initialized = false
	_poll(scene, 100, _mask(sight), [cc, tank, turret])
	scene.bridge_initialized = true
	_poll(scene, 104, _mask(sight), [cc, turret])
	t.ok(_live_cards(scene) > 0, "a unit vanishing deep inside sight died: its explosion is drawn")
	t.eq(rec.ids(), ["explosion_large"], "and heard")
	_poll(scene, 108, _mask(sight), [cc])
	t.eq(rec.ids(), ["explosion_large", "collapse"], "a visible enemy building gone from a visible cell collapsed")
	_done(scene)


func test_an_enemy_unit_first_seen_walking_in_gets_no_deploy_ring_but_one_produced_in_sight_does(t) -> void:
	var scene := _kestrel_scene()
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 6)
	scene.bridge_initialized = false
	_poll(scene, 100, _mask(sight), [cc])
	scene.bridge_initialized = true
	var cards := _live_cards(scene)
	var edge := _unit(scene, 520, "Infantry", 1, Vector2i(20, 9))
	_poll(scene, 104, _mask(sight), [cc, edge])
	t.eq(_live_cards(scene), cards, "first seen on the rim of sight: it walked in, no deploy ring")
	var fresh := _unit(scene, 521, "Infantry", 1, Vector2i(14, 9))
	_poll(scene, 108, _mask(sight), [cc, edge, fresh])
	t.eq(scene.ui.session_log.added.size(), 1, "a unit first seen deep inside sight was produced there: announced as before")
	_done(scene)


func test_fog_off_keeps_todays_appearance_and_death_rules(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	var all := "2".repeat(W * H)
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	scene.bridge_initialized = false
	_poll(scene, 100, all, [cc])
	scene.bridge_initialized = true
	var far := _unit(scene, 530, "Tank", 1, Vector2i(30, 9))
	_poll(scene, 104, all, [cc, far])
	t.eq(scene.ui.session_log.added, [["Tank", 1]], "every new entity is announced, as before fog")
	_poll(scene, 108, all, [cc])
	t.eq(rec.ids(), ["explosion_large"], "every vanished entity died, as before fog")
	_done(scene)


func test_a_remembered_building_is_dim_has_no_bars_and_cannot_be_picked(t) -> void:
	var scene := _kestrel_scene()
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 6)
	var turret := _building(scene, 540, "GunTurret", 1, Vector2i(16, 9), 0, 60)
	scene.bridge_initialized = false
	_poll(scene, 100, _mask(sight), [cc, turret])
	scene.bridge_initialized = true
	var node: Node3D = scene.bridge_nodes[540]
	var card: MeshInstance3D = node.get_node("Visual")
	var live_material: Material = card.material_override
	t.ok(node.get_node("HealthFill").visible, "seen damaged: its health bar shows")
	var ghost := turret.duplicate()
	ghost["remembered"] = true
	_poll(scene, 104, _mask([], sight), [cc, ghost])
	t.ok(scene.bridge_nodes[540] == node, "the same node: no re-creation, no effect")
	t.ok(bool(node.get_meta("remembered", false)), "flagged remembered")
	var dim: StandardMaterial3D = card.material_override
	t.ok(dim != live_material, "drawn with the memory material")
	t.near(dim.albedo_color.r, WorldSprites.MEMORY_SHADE, 0.001, "dimmed to MEMORY_SHADE")
	t.ok(dim.albedo_texture == (live_material as StandardMaterial3D).albedo_texture, "the same painting")
	var other := _building(scene, 541, "GunTurret", 1, Vector2i(16, 11))
	other["remembered"] = true
	_poll(scene, 105, _mask([], sight), [cc, ghost, other])
	t.ok((scene.bridge_nodes[541].get_node("Visual") as MeshInstance3D).material_override == dim, "one shared memory material per painting, not one per building")
	for bar in ["HealthBack", "HealthFill", "ShieldBack", "ShieldFill"]:
		t.ok(not node.get_node(bar).visible, "no %s on a memory" % bar)
	scene.bridge_era = 1
	scene._apply_era_visuals()
	t.ok(not node.get_node("EraCrown").visible, "no era crown on a memory")
	var to_screen := func(n: Node3D, offset: Vector3) -> Vector2: return Vector2(n.position.x + offset.x, n.position.z + offset.z) * 100.0
	var at: Vector2 = to_screen.call(node, Vector3.ZERO)
	t.eq(scene._pick_entity(at, to_screen), null, "a click on it picks nothing")
	_poll(scene, 140, _mask(sight), [cc, turret])
	t.ok(not bool(node.get_meta("remembered", false)), "seen again: live")
	t.ok(card.material_override == WorldSprites.material_for(card.get_meta("sprite_texture")), "with its live material")
	t.ok(node.get_node("HealthFill").visible, "and its bar")
	_done(scene)


func test_a_remembered_building_dropped_unseen_vanishes_without_a_collapse(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 6)
	var turret := _building(scene, 550, "GunTurret", 1, Vector2i(16, 9))
	scene.bridge_initialized = false
	_poll(scene, 100, _mask(sight), [cc, turret])
	scene.bridge_initialized = true
	var ghost := turret.duplicate()
	ghost["remembered"] = true
	_poll(scene, 104, _mask([], sight), [cc, ghost])
	var cards := _live_cards(scene)
	# re-scouted: the cell is visible and the building is gone (it died while unseen)
	_poll(scene, 200, _mask(sight), [cc])
	t.ok(not scene.bridge_nodes.has(550), "the memory is dropped")
	t.eq(_live_cards(scene), cards, "no collapse: it fell while nobody watched")
	t.eq(rec.calls.size(), 0, "and no sound")
	_done(scene)


func test_a_restart_forgets_the_seen_ids(t) -> void:
	var scene := _kestrel_scene()
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(14, 9), 6)
	scene.bridge_initialized = false
	_poll(scene, 900, _mask(sight), [cc, _unit(scene, 560, "Tank", 1, Vector2i(14, 9))])
	t.ok(scene.fog_seen_ids.has(560), "seen")
	scene._sync_fog({"tick": 3, "fog": _mask(sight)})
	t.ok(scene.fog_seen_ids.is_empty(), "a tick going back is a new sim: nothing has been seen")
	_done(scene)


# ------------------------------------------------------------------ effects, shots and sound

func test_effects_and_world_sounds_in_the_dark_are_skipped(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	scene._sync_fog({"tick": 10, "fog": _mask(_disc(Vector2i(8, 9), 4))})
	var dark: Vector3 = scene._hex_world(30, 9)
	var lit: Vector3 = scene._hex_world(8, 9)
	t.eq(scene.world_fx.hit(dark, 2, 1), 0, "no hit card in the dark")
	t.eq(scene.world_fx.explode(dark, 1.0, 1), 0, "no explosion")
	t.eq(scene.world_fx.collapse(dark, 2.0, 1), 0, "no collapse")
	t.eq(scene.world_fx.dust(dark, 0.4), 0, "no dust")
	t.eq(scene.world_fx.flash(dark, 1, 1), 0, "no flash")
	t.ok(scene.world_fx.hit(lit, 2, 1) > 0, "a hit in sight draws")
	scene._sfx("cannon", dark)
	t.eq(rec.calls.size(), 0, "a sound placed in the dark is not requested")
	scene._sfx("cannon", lit)
	scene._sfx("wave_inbound")
	t.eq(rec.ids(), ["cannon", "wave_inbound"], "in sight, and global cues, pass")
	_done(scene)


func test_a_shot_with_both_ends_dark_draws_and_sounds_nothing(t) -> void:
	var scene := _kestrel_scene()
	var rec := _record(scene)
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var sight := _disc(Vector2i(8, 9), 4)
	scene.bridge_initialized = false
	_poll(scene, 10, _mask(sight), [cc])
	scene.bridge_initialized = true
	var row := func(tick: int, a: Vector2i, b: Vector2i) -> Array:
		var ab: Vector2i = scene._world_to_sim_bits(scene._hex_world(a.x, a.y))
		var bb: Vector2i = scene._world_to_sim_bits(scene._hex_world(b.x, b.y))
		return [tick, ab.x, ab.y, bb.x, bb.y]
	var dark := {"tick": 12, "entities": [cc], "shots": [row.call(11, Vector2i(30, 9), Vector2i(34, 9))]}
	t.eq(scene._dispatch_shots(dark), 0, "both ends dark: nothing drawn")
	t.eq(rec.calls.size(), 0, "and nothing requested")
	var inbound := {"tick": 14, "entities": [cc], "shots": [row.call(13, Vector2i(14, 9), Vector2i(8, 9))]}
	t.eq(scene._dispatch_shots(inbound), 1, "fired from the dark at a building in sight: drawn")
	t.eq(rec.ids(), ["plasma_bolt"], "and heard")
	t.ok((rec.calls[0]["at"] as Vector3).distance_to(scene._hex_world(8, 9)) < 0.6, "at the end the player can see (the struck command centre)")
	_done(scene)


func test_loops_only_carry_units_in_sight(t) -> void:
	var scene := _kestrel_scene()
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	var tank := _unit(scene, 570, "Tank", 0, Vector2i(9, 9))
	scene.bridge_initialized = false
	_poll(scene, 10, _mask(_disc(Vector2i(8, 9), 4)), [cc, tank])
	var node: Node3D = scene.bridge_nodes[570]
	scene._track_motion(node, node.position)
	scene.unit_motion[node.get_instance_id()].speed = 1.0
	t.eq(scene._audio_moving().get("tread_loop", []).size(), 1, "the moving tank in sight is heard")
	scene._sync_fog({"tick": 11, "fog": _mask([Vector2i(30, 9)], _disc(Vector2i(8, 9), 4))})
	scene._sync_fog({"tick": 12, "fog": _mask([Vector2i(30, 9)], _disc(Vector2i(8, 9), 4))})
	t.eq(scene._audio_moving().get("tread_loop", []).size(), 0, "a unit standing on dark ground is not")
	_done(scene)


# ------------------------------------------------------------------ panels

func _fogged_snap() -> Dictionary:
	## The fog-off start with one alien turret in sight, one remembered, the rest unknown; the mask matches.
	var snap := _snap(true)
	var keep: Array = []
	var aliens := 0
	for e in snap["entities"]:
		if int(e["owner"]) == 0:
			keep.append(e)
		elif str(e["kind"]) == "GunTurret" and aliens < 2:
			var copy: Dictionary = e.duplicate()
			if aliens == 1:
				copy["remembered"] = true
			keep.append(copy)
			aliens += 1
	snap["entities"] = keep
	var visible: Array = _disc(Vector2i(8, 9), 6)
	visible.append(VM.entity_cell(keep.filter(func(e): return int(e["owner"]) != 0 and not e.has("remembered"))[0]))
	var remembered_cell: Array = VM.entity_cell(keep.filter(func(e): return e.has("remembered"))[0])
	snap["fog"] = _mask(visible.map(func(c): return c if c is Vector2i else Vector2i(int(c[0]), int(c[1]))), [Vector2i(int(remembered_cell[0]), int(remembered_cell[1]))])
	return snap


func test_enemy_intel_under_fog_counts_known_entities_and_says_so(t) -> void:
	var snap := _fogged_snap()
	var e := VM.enemy_intel(snap, GroundModel.from_snapshot(snap))
	var rows: Dictionary = {}
	for r in e["rows"]:
		rows[r["label"]] = r["value"]
	t.eq(rows.get("Defences"), "2 gun", "the visible turret and the remembered one: known structures")
	t.eq(rows.get("Garrison"), "0 units in sight", "units are counted in sight only")
	t.ok(str(rows.get("Scouted", "")).ends_with("% of the map"), "the explored share is stated")
	t.eq(rows.get("Memory"), "1 last seen", "remembered structures are named as last seen")
	var empty := snap.duplicate(true)
	empty["entities"] = empty["entities"].filter(func(x): return int(x["owner"]) == 0)
	var none := VM.enemy_intel(empty, GroundModel.from_snapshot(empty))
	t.ok(not none.is_empty(), "under fog the card shows before contact")
	t.eq(none["rows"][0]["value"], "Not scouted", "and says nothing is known yet")
	var off := _snap(true)
	t.ok(not VM.enemy_intel(off, GroundModel.from_snapshot(off))["rows"].any(func(r): return r["label"] in ["Scouted", "Memory"]), "fog off: today's card")


func test_the_wave_panel_shows_relay_totals_never_how_many_are_powered(t) -> void:
	var snap := _fogged_snap()
	snap["next_wave_ticks"] = 300
	snap["alien_relays"] = 3
	snap["active_alien_relays"] = 1
	var out := VM.wave_panel(snap, GroundModel.from_snapshot(snap))
	var relays: Array = out["rows"].filter(func(r): return r["label"] == "Relays")
	t.eq(relays.size(), 1, "one relay row")
	t.eq(relays[0]["value"], "3 known", "the total from the briefing intel")
	t.ok(not JSON.stringify(out).contains("operating"), "never the powered count")
	var off := _snap(true)
	off["next_wave_ticks"] = 300
	off["active_alien_relays"] = 1
	t.eq(VM.wave_panel(off, GroundModel.from_snapshot(off))["rows"].filter(func(r): return r["label"] == "Relays")[0]["value"], "1 operating", "fog off: as today")


func test_combat_preview_and_hostile_pin_ignore_a_remembered_building(t) -> void:
	var snap := _fogged_snap()
	var ground := GroundModel.from_snapshot(snap)
	var human_ids: Array = snap["entities"].filter(func(e): return int(e["owner"]) == 0 and str(e["category"]) == "unit").map(func(e): return int(e["id"]))
	var seen: Dictionary = snap["entities"].filter(func(e): return int(e["owner"]) != 0 and not e.has("remembered"))[0]
	var ghost: Dictionary = snap["entities"].filter(func(e): return e.has("remembered"))[0]
	t.ok(not VM.combat_preview(snap, ground, human_ids, VM.entity_cell(seen)).is_empty(), "a visible enemy gets a preview")
	t.ok(VM.combat_preview(snap, ground, human_ids, VM.entity_cell(ghost)).is_empty(), "a memory gets none: no live intel")


func test_region_map_shades_unexplored_ground_and_marks_memories(t) -> void:
	var snap := _fogged_snap()
	var vm := Maps.region_map(snap, GroundModel.from_snapshot(snap))
	t.ok(vm.has("unseen") and (vm["unseen"] as Array).size() > 0, "the unseen hexes are listed for the shroud")
	t.eq(int(vm["explored_pct"]), snap["fog"].count("1") * 0 + roundi(100.0 * float(W * H - snap["fog"].count("0")) / float(W * H)), "the explored percent")
	t.eq(vm["hostile"].size(), 2, "both known structures")
	t.eq(vm["hostile"].filter(func(h): return bool(h.get("remembered", false))).size(), 1, "one drawn as last seen")
	var off := _snap(true)
	var plain := Maps.region_map(off, GroundModel.from_snapshot(off))
	t.ok(not plain.has("unseen") and not plain.has("explored_pct"), "fog off: today's map")


func test_no_view_model_ever_carries_the_state_hash(t) -> void:
	var snap := _fogged_snap()
	snap["hash"] = "1234567890abcdef"
	var ground := GroundModel.from_snapshot(snap)
	var text := JSON.stringify([VM.enemy_intel(snap, ground), VM.wave_panel(snap, ground), Maps.region_map(snap, ground), VM.pause(snap)])
	t.ok(not text.contains("1234567890abcdef"), "the hash is never shown")


func test_assault_marks_skip_memories_and_the_minimap_keeps_known_marks(t) -> void:
	var g := Stub.new()
	var live := Node3D.new()
	live.set_meta("team", 1)
	live.set_meta("category", "building")
	live.set_meta("kind_name", "GunTurret")
	live.position = Vector3(10, 0, 10)
	var ghost := Node3D.new()
	ghost.set_meta("team", 1)
	ghost.set_meta("category", "building")
	ghost.set_meta("kind_name", "GunTurret")
	ghost.set_meta("remembered", true)
	ghost.position = Vector3(12, 0, 10)
	g.bridge_nodes = {1: live, 2: ghost}
	var assault = Assault.new(g)
	var marks: Array = assault.marks(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z) * 50.0, Rect2(0, 0, 1920, 1080), func(_p: Vector3) -> bool: return false)
	t.eq(marks.size(), 1, "the live diamond with its HP bar only")
	var adapter = Adapter.new(g)
	t.eq(adapter._marks().size(), 2, "the minimap shows both known sites (it renders what the player knows)")
	live.free()
	ghost.free()


func test_the_minimap_draws_the_same_shrouded_world(t) -> void:
	# The minimap is a SubViewport sharing the main World3D, so the ground and prop shaders (and their fog uniforms) are the
	# very materials it renders: no second shroud to keep in step.
	var src := (load("res://scripts/ui/game_ui.gd") as GDScript).source_code
	var at := src.find("func _mount_minimap() -> void:")
	t.ok(at >= 0 and src.substr(at, 900).contains("view.world_3d = g.get_viewport().world_3d"), "the minimap shares the battlefield's world")


func test_the_title_says_fog_of_war_once_kestrel_is_fogged(t) -> void:
	var Screens = load("res://scripts/ui/live_screens.gd")
	var fact := func(vm: Dictionary) -> String:
		for f in vm["campaign"]["featured"]["facts"]:
			if f["k"] == "Visibility":
				return f["v"]
		return ""
	t.eq(fact.call(Screens.title_vm(true, 12)), "Full battlefield, no fog of war", "before a fogged snapshot (and Survival)")
	t.eq(fact.call(Screens.title_vm(true, 12, true)), "Fog of war, scout the alien side", "Kestrel with its fog")
	var copy := "Fog of war, scout the alien side"
	t.ok(not copy.contains(String.chr(0x2014)) and not copy.contains(String.chr(0x2013)), "no dashes")
