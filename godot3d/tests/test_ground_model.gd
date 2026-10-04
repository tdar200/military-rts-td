extends RefCounted
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Terrain := preload("res://scripts/continuous_terrain.gd")
const Stub = preload("res://tests/stub_game.gd")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _first_cell(m, glyph: String) -> Vector2i:
	for y in range(m.height):
		for x in range(m.width):
			if m.glyph_at(x, y) == glyph:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_from_snapshot_decodes_ground_and_table(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	t.ok(m != null, "model builds from the Kestrel fixture")
	if m == null:
		return
	t.eq(m.width, 44, "width from map_width")
	t.eq(m.height, 26, "height from map_height")
	t.ok(m.name_at(0, 0) != "", "name resolves")
	t.eq(m.props_at(0, 0).get("glyph"), m.glyph_at(0, 0), "props row matches the glyph")
	var wet_found := false
	var dry_found := false
	for y in range(26):
		for x in range(44):
			if m.is_wet(x, y):
				wet_found = true
			else:
				dry_found = true
	t.ok(wet_found, "river/sea present")
	t.ok(dry_found, "land present")


func test_missing_ground_returns_null(t) -> void:
	t.ok(GroundModel.from_snapshot({"schema": 5, "map_width": 44, "map_height": 26}) == null, "no ground field -> null")


func test_wrong_length_returns_null(t) -> void:
	t.ok(GroundModel.from_snapshot({"map_width": 44, "map_height": 26, "ground": "ggg", "ground_table": []}) == null, "short string -> null")


func test_counts_in_matches_hand_count(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	var counts: Dictionary = m.counts_in([[0, 0], [1, 0], [2, 0]])
	var total := 0
	for k in counts:
		total += int(counts[k])
	t.eq(total, 3, "three cells counted")
	var same: Dictionary = m.counts_in([[5, 5], [5, 5]])
	t.eq(int(same.get(m.glyph_at(5, 5), 0)), 2, "repeated cell counted twice under its glyph")


func test_out_of_range_reads_are_safe(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	t.eq(m.glyph_at(-1, 0), "g", "off-map glyph falls back to grass")
	t.eq(m.glyph_at(44, 0), "g", "off-map glyph falls back to grass")


func _terrain(m) -> Node3D:
	var terrain: Node3D = Terrain.new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, null)
	if m != null:
		terrain.apply_ground(m)
	return terrain


func _height_at_cell(terrain: Node3D, x: int, y: int) -> float:
	var wz := 1.0 + float(y) * 0.70 + (0.35 if x % 2 else 0.0)
	return terrain.height_at_world(2.1 + float(x) * 0.68, wz)


func test_apply_ground_orders_heights_by_class(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	var terrain := _terrain(m)
	var river := _first_cell(m, "r")
	var high := _first_cell(m, "h")
	var flats := _first_cell(m, "f")
	t.ok(river.x >= 0 and high.x >= 0 and flats.x >= 0, "fixture has river, highland and flats")
	var h_river := _height_at_cell(terrain, river.x, river.y)
	var h_high := _height_at_cell(terrain, high.x, high.y)
	var h_flats := _height_at_cell(terrain, flats.x, flats.y)
	t.ok(h_river < h_flats, "river hex is carved below flats (%s < %s)" % [h_river, h_flats])
	t.ok(h_high > h_flats + 0.4, "highland rises above flats (%s > %s)" % [h_high, h_flats])
	terrain.free()


func test_wet_cells_are_below_the_waterline_land_is_not(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	var terrain := _terrain(m)
	var sea := _first_cell(m, "o")
	var h_sea := _height_at_cell(terrain, sea.x, sea.y)
	t.ok(h_sea < -0.4, "sea hex is deep (%s)" % h_sea)
	t.ok(_height_at_cell(terrain, _first_cell(m, "g").x, _first_cell(m, "g").y) > -0.1, "grassland is above water")
	terrain.free()


func test_without_model_terrain_matches_noise_fallback(t) -> void:
	var plain := _terrain(null)
	var again := _terrain(null)
	t.eq(plain.height_at_world(10.0, 8.0), again.height_at_world(10.0, 8.0), "fallback is deterministic")
	var before: float = plain.height_at_world(11.8, 8.0)
	plain.apply_ground(null)
	t.eq(plain.height_at_world(11.8, 8.0), before, "apply_ground(null) leaves the noise terrain alone")
	plain.free()
	again.free()


func test_apply_ground_rebuilds_once_not_per_call(t) -> void:
	var m = GroundModel.from_snapshot(_snap())
	var terrain := _terrain(m)
	var meshes := 0
	for c in terrain.get_children():
		if c is MeshInstance3D:
			meshes += 1
	t.eq(meshes, 1, "one terrain mesh after configure plus apply_ground")
	terrain.free()


func test_stub_kestrel_flag_loads_the_fixture(t) -> void:
	var g = Stub.new()
	t.ok(not g.kestrel and g.ground_model == null, "stub is not Kestrel by default")
	g.use_kestrel()
	t.ok(g.kestrel and g.ground_model != null, "use_kestrel loads snapshot and ground model")
	t.eq(String(g.bridge_snapshot.get("map_name", "")), "Kestrel Reach", "fixture map name")
