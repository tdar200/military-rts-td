extends RefCounted
## Prop scatter for Kestrel (spec addendum W5): deterministic, data-driven, two MultiMeshes no matter how many props.
const WorldProps := preload("res://scripts/world/world_props.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _plan() -> Array:
	var s := _snap()
	var m = GroundModel.from_snapshot(s)
	return WorldProps.plan(m, s["deposits"], Vector2(2.1, 1.0), Vector2(0.68, 0.70), 8, WorldProps.keep_out(m, s["wave_route"]))


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
	# The headless renderer keeps no MultiMesh transforms, so read the CPU mirror: exactly the cards inside the radius
	# are hidden, and every other card keeps its place.
	var cards := items.filter(func(i): return not String(i.sprite) in WorldProps.DECAL_SPRITES)
	var wrong := 0
	for i in cards.size():
		var inside: bool = cards[i].pos.distance_to(Vector2(centre.x, centre.z)) < 1.0
		if (props._card_at[i] == WorldProps.HIDDEN) != inside:
			wrong += 1
	t.eq(wrong, 0, "hidden exactly when inside the radius")
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
	t.ok(props.clear_around(Vector3(2.1 + 27.0 * 0.68, 0, 1.0 + 3.5 * 0.70), 1.0) > 0, "the ridge is untouched by the wood clear")
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


func test_clearing_next_to_a_deposit_keeps_its_crystals(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	var items := _plan()
	props.build(parent, items, func(_x, _z): return 0.0)
	var ore := Vector2i(18, 7)
	var centre := Vector2(2.1 + 18.0 * 0.68, 1.0 + 7.0 * 0.70)
	props.clear_around(Vector3(centre.x, 0, centre.y), 0.85)  # a building on the deposit itself
	props.clear_around(Vector3(centre.x, 0, centre.y + 0.70), 0.85)  # and one on the tile below it
	var cards := items.filter(func(i): return not String(i.sprite) in WorldProps.DECAL_SPRITES)
	var decals := items.filter(func(i): return String(i.sprite) in WorldProps.DECAL_SPRITES)
	var crystals := 0
	for i in cards.size():
		if cards[i].tile == ore:
			crystals += 1
			t.ok(props._card_at[i] != WorldProps.HIDDEN, "crystal %s stays" % i)
	var shadows := 0
	for i in decals.size():
		if decals[i].tile == ore:
			shadows += 1
			t.ok(props._decal_at[i] != WorldProps.HIDDEN, "crystal shadow %s stays" % i)
	t.eq(crystals, 2, "both crystal cards checked")
	t.eq(shadows, 2, "both crystal shadows checked")
	parent.free()


func test_keep_out_covers_the_route_the_ford_and_its_approach(t) -> void:
	var s := _snap()
	var m = GroundModel.from_snapshot(s)
	var keep: Dictionary = WorldProps.keep_out(m, s["wave_route"])
	for step in s["wave_route"]:
		t.ok(keep.has(Vector2i(int(step[0]), int(step[1]))), "route tile %s" % [step])
	for ford in [Vector2i(22, 10), Vector2i(23, 10)]:
		t.ok(keep.has(ford), "ford %s" % ford)
		for n in WorldProps._neighbours(ford.x, ford.y):
			t.ok(keep.has(n), "ford approach %s" % n)
	t.eq(WorldProps.keep_out(m, s["wave_route"]), keep, "deterministic")


func test_no_card_stands_on_the_wave_route(t) -> void:
	var s := _snap()
	var route := {}
	for step in s["wave_route"]:
		route[Vector2i(int(step[0]), int(step[1]))] = true
	var deposits := {}
	for d in s["deposits"]:
		deposits[Vector2i(int(d.x), int(d.y))] = true
	var on_route := 0
	for item in _plan():
		var sprite := String(item.sprite)
		if route.has(item.tile) and not sprite in WorldProps.DECAL_SPRITES:
			if not (sprite in WorldProps.CRYSTAL_SPRITES and deposits.has(item.tile)):
				on_route += 1
	t.eq(on_route, 0, "only a deposit's own crystals may stand on the route")


func test_no_tree_beside_the_route_or_the_ford(t) -> void:
	var s := _snap()
	var m = GroundModel.from_snapshot(s)
	var keep: Dictionary = WorldProps.keep_out(m, s["wave_route"])
	var beside := 0
	for item in _plan():
		if not String(item.sprite) in ["forest", "forest_dry"]:
			continue
		var tile: Vector2i = item.tile
		if WorldProps._glyph(m, tile.x, tile.y) == "t":
			continue  # a forest tile keeps its canopy
		for n in WorldProps._neighbours(tile.x, tile.y):
			if keep.has(n):
				beside += 1
				break
	t.eq(beside, 0, "no tree or willow beside the route, the ford or its approach")


func test_the_game_scatters_with_the_route_keep_out(t) -> void:
	var scene = load("res://main.tscn").instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	var cards := _plan().filter(func(i): return not String(i.sprite) in WorldProps.DECAL_SPRITES)
	t.ok(scene.world_props != null, "Kestrel builds props")
	t.eq(scene.world_props.cards.multimesh.instance_count, cards.size(), "the game plans with the same route and ford keep-out")
	scene.free()
