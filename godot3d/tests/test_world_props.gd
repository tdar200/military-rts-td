extends RefCounted
## Prop scatter for Kestrel (spec addendum W5): deterministic, data-driven, two MultiMeshes no matter how many props.
const WorldProps := preload("res://scripts/world/world_props.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _plan() -> Array:
	var s := _snap()
	return WorldProps.plan(GroundModel.from_snapshot(s), s["deposits"], Vector2(2.1, 1.0), Vector2(0.68, 0.70), 8)


func test_plan_is_deterministic(t) -> void:
	t.eq(_plan(), _plan(), "same snapshot, same props")


func test_every_forest_tile_gets_a_canopy_and_water_gets_no_cards(t) -> void:
	var s := _snap()
	var m = GroundModel.from_snapshot(s)
	var canopy := {}
	for item in _plan():
		var tile: Vector2i = item.tile
		if tile.x < 0 or tile.y < 0 or tile.x >= 44 or tile.y >= 26:
			continue
		var g := String(m.glyph_at(tile.x, tile.y))
		if g in ["r", "o"]:
			t.ok(false, "no prop on %s at %s" % [g, tile])
		if g == "w":
			t.eq(String(item.sprite), "pebbles", "the ford only gets pebbles")
		if g == "t" and String(item.sprite) == "forest":
			canopy[tile] = true
	for y in 26:
		for x in 44:
			if m.glyph_at(x, y) == "t":
				t.ok(canopy.has(Vector2i(x, y)), "forest tile %s has a canopy" % Vector2i(x, y))


func test_deposits_get_crystals_and_nothing_else(t) -> void:
	var items := _plan()
	for d in _snap()["deposits"]:
		var tile := Vector2i(int(d.x), int(d.y))
		var crystals := 0
		for item in items:
			if item.tile == tile:
				t.ok(String(item.sprite) in ["ore", "alloy", "shadow"], "only crystals on a deposit (%s)" % item.sprite)
				if String(item.sprite) == ("alloy" if String(d.kind) == "Alloy" else "ore"):
					crystals += 1
		t.eq(crystals, 2, "two crystal cards on %s" % tile)


func test_props_continue_past_the_map_edge(t) -> void:
	var outside := 0
	for item in _plan():
		if item.pos.x < 2.1 or item.pos.y < 1.0:
			outside += 1
	t.ok(outside > 10, "the edge margin is dressed too (%s)" % outside)


func test_counts_are_in_the_board_range(t) -> void:
	var n := {}
	for item in _plan():
		n[item.sprite] = int(n.get(item.sprite, 0)) + 1
	t.ok(int(n.get("forest", 0)) >= 66, "dense canopy (%s)" % n.get("forest", 0))
	t.ok(int(n.get("scrub", 0)) >= 40 and int(n.get("scrub", 0)) <= 260, "scrub (%s)" % n.get("scrub", 0))
	t.ok(int(n.get("rock", 0)) >= 30, "rocks on the ridge and flats (%s)" % n.get("rock", 0))
	t.eq(int(n.get("crater", 0)), 2, "one decal per crater tile")


func test_build_uses_two_multimeshes_without_shadow_casting(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	props.build(parent, _plan(), func(_x, _z): return 0.0)
	var mmis := parent.find_children("*", "MultiMeshInstance3D", true, false)
	t.eq(mmis.size(), 2, "cards and decals, nothing per prop")
	for mmi in mmis:
		t.eq((mmi as MultiMeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow pass for props")
	t.ok(props.cards.multimesh.use_custom_data, "atlas rect per instance")
	parent.free()


func test_clear_around_hides_only_nearby_props(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	var items := _plan()
	props.build(parent, items, func(_x, _z): return 0.0)
	var centre := Vector3(2.1 + 8.0 * 0.68, 0, 1.0 + 19.0 * 0.70)  # Hollow Wood
	var hidden: int = props.clear_around(centre, 1.0)
	t.ok(hidden > 0, "trees near a new building are cleared (%s)" % hidden)
	var mm: MultiMesh = props.cards.multimesh
	var still := 0
	for i in mm.instance_count:
		var tr := mm.get_instance_transform(i)
		if tr.basis.get_scale().length() > 0.001 and Vector2(tr.origin.x, tr.origin.z).distance_to(Vector2(centre.x, centre.z)) < 1.0:
			still += 1
	t.eq(still, 0, "nothing visible is left inside the radius")
	parent.free()


func test_pads_reuse_slots(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	props.build(parent, _plan(), func(_x, _z): return 0.0)
	var a: int = props.add_pad(Vector3(5, 0, 5), 1.9)
	props.release_pad(a)
	t.eq(props.add_pad(Vector3(6, 0, 6), 1.9), a, "a released pad slot is reused")
	parent.free()


func test_clear_around_remembers_what_it_hid(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	props.build(parent, _plan(), func(_x, _z): return 0.0)
	var wood := Vector3(2.1 + 8.0 * 0.68, 0, 1.0 + 19.0 * 0.70)
	t.ok(props.clear_around(wood, 1.0) > 0, "first clear hides props")
	t.eq(props.clear_around(wood, 1.0), 0, "a second clear finds nothing left")
	t.ok(props.clear_around(Vector3(2.1 + 30.0 * 0.68, 0, 1.0 + 2.0 * 0.70), 1.0) > 0, "the ridge is untouched by the wood clear")
	parent.free()


func test_clear_around_takes_each_cleared_card_shadow_with_it(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	var items := _plan()
	props.build(parent, items, func(_x, _z): return 0.0)
	var wood := Vector2(2.1 + 8.0 * 0.68, 1.0 + 19.0 * 0.70)
	var cards := 0
	for item in items:
		if not String(item.sprite) in WorldProps.DECAL_SPRITES and item.pos.distance_to(wood) < 1.0:
			cards += 1
	t.ok(cards > 0, "Hollow Wood has cards to clear")
	t.eq(props.clear_around(Vector3(wood.x, 0, wood.y), 1.0), 2 * cards, "every cleared card takes its own drop shadow, and no other")
	parent.free()


func test_cards_keep_their_billboard_inside_the_cull_box(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	var items := _plan()
	props.build(parent, items, func(_x, _z): return 0.0)
	var tallest := 0.0
	for item in items:
		tallest = maxf(tallest, float(item.size))
	t.ok(props.cards.extra_cull_margin >= tallest, "a camera-facing card turned off its quad still sits inside the culling box (%s)" % tallest)
	t.eq(props.cards.visibility_range_end, 0.0, "no visibility range: one node spans the map, a range would pop every prop at once")
	parent.free()


func test_decals_rest_on_the_highest_ground_they_cover(t) -> void:
	var bowl := func(x: float, z: float) -> float: return 0.3 * (x * x + z * z)  # a crater: rim higher than the centre
	var y: float = WorldProps.decal_height(bowl, Vector2.ZERO, 1.0)
	t.ok(y >= 0.3 * 0.25 + 0.03, "the decal clears the rim instead of sinking under it (%s)" % y)
	t.near(WorldProps.decal_height(func(_x, _z): return 0.5, Vector2(3, 4), 1.0), 0.535, 0.0001, "flat ground: a hair above it")
