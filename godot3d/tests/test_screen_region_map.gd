extends RefCounted
## Board 11 (Strategic map): the real ground layer, regions, borders and route, honest composition and counts, one cached draw.
const Map := preload("res://scripts/ui/sections/region_map.gd")
const Hex := preload("res://scripts/ui/components/hex_map.gd")
const Maps := preload("res://scripts/ui/vm_maps.gd")
const Ground := preload("res://scripts/terrain/ground_model.gd")
const U := preload("res://tests/section_util.gd")


func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _vm(snap := {}) -> Dictionary:
	var s: Dictionary = snap if not snap.is_empty() else _snapshot()
	return Maps.region_map(s, Ground.from_snapshot(s))


func _all_text(root: Node) -> String:
	return " ".join(U.texts(root)).to_lower()


func _screen(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Map.build(root, vm, func(name: String, arg: Variant = null) -> void: log.append([name, arg]))
	return [root, log]


func test_counts_are_the_snapshot_counts(t) -> void:
	var snap := _snapshot()
	var vm := _vm(snap)
	t.eq(vm["name"], "Kestrel Reach", "the map name")
	t.eq(vm["tiles"], snap["construction_zone"].size(), "Territory tiles is the real construction_zone count")
	var hostile := 0
	for e in snap["entities"]:
		if e["category"] == "building" and int(e["owner"]) != 0:
			hostile += 1
	t.eq(vm["hostile"].size(), hostile, "Hostile sites is the real alien structure count")
	t.eq(vm["width"] * vm["height"], str(snap["ground"]).length(), "the ground layer covers width times height")


func test_composition_is_exact_and_totals_100(t) -> void:
	var snap := _snapshot()
	var comp: Dictionary = _vm(snap)["composition"]
	var pct := 0
	var tiles := 0
	for row in comp["rows"]:
		pct += int(row["pct"])
		tiles += int(row["count"])
	t.eq(pct, 100, "largest remainder makes the legend total exactly 100")
	t.eq(tiles, str(snap["ground"]).length(), "every tile is counted once")
	var grass := str(snap["ground"]).count("g")
	var first: Dictionary = comp["rows"][0]
	t.eq(first["glyph"], "g", "grassland is the largest ground")
	t.eq(first["count"], grass, "and its count is the glyph count in the ground string")


func test_screen_shows_real_labels_and_numbers(t) -> void:
	var snap := _snapshot()
	var vm := _vm(snap)
	var p := _screen(vm)
	var root: Control = p[0]
	var text := _all_text(root)
	for r in snap["regions"]:
		t.ok(text.contains(str(r["name"]).to_lower()), "region label %s is drawn" % r["name"])
	for want in ["strategic map", "composition", "territory", "343 tiles", "hostile sites", "enemy territory", "wave %02d route" % int(vm["route"]["wave"]), "lenses", "m to close"]:
		t.ok(text.contains(want), "the screen shows '%s'" % want)
	t.ok(text.contains("grassland 51%"), "the legend reads the ground counts")
	root.free()


func test_lens_buttons_have_human_text_and_emit_their_id(t) -> void:
	var p := _screen(_vm())
	var root: Control = p[0]
	var want := {"Terrain": "terrain", "Resources": "res", "Borders": "bdr", "Threat": "thr", "Hex grid": "hex"}
	for label in want:
		var b := U.button_with(root, label)
		t.ok(b != null, "a '%s' lens Button" % label)
		if b != null:
			b.pressed.emit()
	t.eq(p[1].map(func(c): return c[1]), want.values(), "each lens Button emits region_lens with its id")
	U.button_with(root, "Close").pressed.emit()
	t.eq(p[1][-1][0], "region_close", "Close emits region_close")
	root.free()


func test_lenses_switch_what_is_drawn(t) -> void:
	var vm := _vm()
	vm["lens_on"] = {"bdr": false, "thr": false, "res": true}
	var p := _screen(vm)
	var text := _all_text(p[0])
	t.ok(not text.contains("enemy territory"), "Borders off hides the Enemy territory label")
	t.ok(not text.contains("route"), "Threat off hides the wave route label")
	t.ok(text.contains("ore") or text.contains("alloy"), "Resources on shows the deposit pins")
	p[0].free()


func test_absent_data_builds_nothing(t) -> void:
	var snap := _snapshot()
	snap.erase("ground")
	t.ok(Maps.region_map(snap, null).is_empty(), "no ground model, no map")
	snap = _snapshot()
	snap.erase("regions")
	t.ok(Maps.region_map(snap, Ground.from_snapshot(snap)).is_empty(), "no regions, no map")
	var p := _screen({})
	t.eq(p[0].get_child_count(), 0, "an empty view model draws nothing")
	p[0].free()


func test_no_invented_panels(t) -> void:
	var vm := _vm()
	var p := _screen(vm)
	var text := _all_text(p[0]) + " " + JSON.stringify(vm).to_lower()
	for banned in ["fog", "explored", "unexplored", "islet", "resources seen", "next goals", "yields per minute", "coastal river basin"]:
		t.ok(not text.contains(banned), "the map never says '%s'" % banned)
	p[0].free()


func test_ground_mesh_is_cached_per_ground(t) -> void:
	var vm := _vm()
	Hex.clear_caches()
	var a := Hex.ground_mesh(vm)
	t.eq(Hex.cache_hits, 0, "the first request builds the mesh")
	var b := Hex.ground_mesh(vm)
	t.ok(a == b and Hex.cache_hits == 1, "the second request returns the same mesh")
	var lensed := vm.duplicate()
	lensed["lens_on"] = {"hex": true, "bdr": false}
	t.ok(Hex.ground_mesh(lensed) == a, "a lens toggle does not rebuild the ground")
	var grid := Hex.grid_lines(vm)
	t.ok(Hex.grid_lines(vm) == grid and not grid.is_empty(), "the hex grid lines are cached too")
	var other := _snapshot()
	other["ground"] = str(other["ground"]).replace("g", "m")
	t.ok(Hex.ground_mesh(_vm(other)) != a, "a different ground string is a different mesh")
	var src: String = (load("res://scripts/ui/sections/region_map.gd") as GDScript).source_code
	t.ok(not src.contains("_process"), "the map never redraws itself per frame; the host rebuilds it on a change")
	t.ok(src.contains("Hex.ground_mesh(vm)"), "the ground is drawn from the cached mesh")


func test_ground_colours_come_from_the_shared_legend(t) -> void:
	var terrain := preload("res://scripts/continuous_terrain.gd")
	var look: Dictionary = terrain.GROUND_LOOK
	var legend: Dictionary = terrain.GROUND_LEGEND
	for glyph in look:
		t.ok(legend.has(glyph), "glyph %s has a legend colour" % glyph)
		t.eq(Hex.ground_color(glyph), Color(str(legend.get(glyph, ""))), "glyph %s uses the shared legend colour" % glyph)
	# The UI key stays the palette the gp11 board was matched against; the 3D albedo is calibrated for the grade separately.
	t.eq(String(legend["f"]), "c9923a", "Dry Flats key colour")
	t.eq(String(legend["h"]), "6e747a", "Highland key colour")
	Hex.clear_caches()  # the static mesh caches outlive the tests; drop them so the exit leak check stays quiet
