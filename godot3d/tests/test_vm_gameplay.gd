extends RefCounted
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const Stub := preload("res://tests/stub_game.gd")


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


## A hand-built snapshot: `rows` is the ground string row by row, the ground_table is the real one from the fixture.
func _mini(rows: Array, entities := [], extra := {}) -> Dictionary:
	var snap := {"map_width": String(rows[0]).length(), "map_height": rows.size(), "ground": "".join(rows), "ground_table": _snap()["ground_table"], "entities": entities}
	snap.merge(extra, true)
	return snap


## Entity standing on hex (x, y): the inverse of VM.entity_cell, written out from the sim's own layout.
func _ent(id: int, owner: int, category: String, kind: String, x: int, y: int, extra := {}) -> Dictionary:
	var sx := 0.5 + 0.75 * x
	var sz := 0.5 + y + (0.5 if x % 2 != 0 else 0.0)
	var e := {"id": id, "owner": owner, "category": category, "kind": kind, "x_bits": roundi(sx * 65536.0), "z_bits": roundi(sz * 65536.0)}
	e.merge(extra, true)
	return e


func _model(snap: Dictionary):
	return GroundModel.from_snapshot(snap)


# ------------------------------------------------------------------ hex geometry

func test_hex_distance_hand_checked_pairs(t) -> void:
	t.eq(VM.hex_distance(0, 0, 0, 0), 0, "same cell")
	t.eq(VM.hex_distance(0, 0, 1, 0), 1, "odd column neighbour, same row")
	t.eq(VM.hex_distance(0, 0, 1, -1), 1, "odd column neighbour, row above")
	t.eq(VM.hex_distance(0, 0, 1, 1), 2, "(1,1) is not a neighbour of (0,0) on odd-q")
	t.eq(VM.hex_distance(0, 0, 3, 2), 4, "three columns shift at most one row down, so (3,2) is four steps")
	t.eq(VM.hex_distance(0, 0, 3, 1), 3, "(3,1) is three steps")
	t.eq(VM.hex_distance(2, 3, 2, 0), 3, "same column is the row difference")
	t.eq(VM.hex_distance(1, 1, 2, 2), 1, "odd column row 1 touches even column row 2")
	t.eq(VM.hex_distance(1, 1, 2, 0), 2, "but not even column row 0")
	t.eq(VM.hex_distance(3, 2, 0, 0), VM.hex_distance(0, 0, 3, 2), "symmetric")


func test_entity_cell_matches_the_fixtures_own_coordinates(t) -> void:
	var s := _snap()
	var human_cc := {}
	var alien_cc := {}
	for e in s["entities"]:
		if e["kind"] == "CommandCenter":
			if e["owner"] == 0:
				human_cc = e
			else:
				alien_cc = e
	t.eq(VM.entity_cell(alien_cc), [37, 8], "alien Command Centre sits on core_node")
	t.eq(VM.entity_cell(alien_cc), [int(s["core_node"][0]), int(s["core_node"][1])], "same as the snapshot's core_node")
	var route: Array = s["wave_route"]
	t.eq(VM.entity_cell(human_cc), [int(route[route.size() - 1][0]), int(route[route.size() - 1][1])], "home Command Centre is where the wave route ends")
	t.eq(VM.entity_cell(_ent(1, 0, "unit", "Infantry", 5, 5)), [5, 5], "odd column round trip")
	t.eq(VM.entity_cell(_ent(1, 0, "unit", "Infantry", 4, 7)), [4, 7], "even column round trip")


func test_sim_layout_constants_have_not_drifted_from_the_game(t) -> void:
	var game = load("res://scripts/earthfront_3d.gd")
	t.ok(game != null, "game script loads")
	if game == null:
		return
	var consts: Dictionary = game.get_script_constant_map()
	t.near(float(consts["SIM_HEX_X"]), VM.SIM_HEX_X, 0.0001, "column pitch")
	t.near(float(consts["SIM_CELL_CENTER"]), VM.SIM_CELL_CENTER, 0.0001, "cell centre")
	t.eq(int(consts["HUMAN"]), VM.HUMAN, "human owner id")


# ------------------------------------------------------------------ territory

func test_territory_composition_hand_checked(t) -> void:
	# ggrr / mggg: g 5, r 2, m 1 of 8 = 62.5 / 25 / 12.5; floors 62+25+12 = 99, the spare point goes to the larger remainder (g before m).
	var s := _mini(["ggrr", "mggg"], [], {"construction_zone": [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1], [9, 9], [-1, 0]]})
	var tv: Dictionary = VM.territory(s, _model(s))
	t.eq(tv["tiles"], 8, "off-map cells are not counted")
	var comp: Array = tv["composition"]
	t.eq(comp.size(), 3, "three ground types")
	t.eq(comp[0], {"glyph": "g", "name": "Grassland", "pct": 63}, "largest first")
	t.eq(comp[1], {"glyph": "r", "name": "River", "pct": 25}, "second")
	t.eq(comp[2], {"glyph": "m", "name": "Meadow", "pct": 12}, "third")


func test_territory_thirds_still_total_one_hundred(t) -> void:
	var s := _mini(["grm"], [], {"construction_zone": [[0, 0], [1, 0], [2, 0]]})
	var comp: Array = VM.territory(s, _model(s))["composition"]
	var sum := 0
	for row in comp:
		sum += int(row["pct"])
	t.eq(sum, 100, "33+33+33 is topped up to 100")
	t.eq(comp[0]["pct"], 34, "ties go to the lower glyph")


func test_territory_on_the_kestrel_fixture(t) -> void:
	var s := _snap()
	var tv: Dictionary = VM.territory(s, _model(s))
	t.eq(tv["tiles"], 343, "every construction_zone cell is on the map")
	var sum := 0
	for row in tv["composition"]:
		sum += int(row["pct"])
		t.ok(str(row["name"]) != "", "each row is named from the ground_table")
	t.eq(sum, 100, "percentages total 100")


func test_territory_empty_cases(t) -> void:
	var s := _snap()
	t.ok(VM.territory({}, null).is_empty(), "no ground model")
	t.ok(VM.territory(s, null).is_empty(), "snapshot but no model")
	var bare := _mini(["gg"])
	t.ok(VM.territory(bare, _model(bare)).is_empty(), "no construction_zone")
	var off := _mini(["gg"], [], {"construction_zone": [[5, 5]]})
	t.ok(VM.territory(off, _model(off)).is_empty(), "zone entirely off the map")


# ------------------------------------------------------------------ tile inspect

func test_tile_inspect_reports_the_table_row_and_nothing_else(t) -> void:
	var s := _mini(["ghwm", "rsot"])
	var gm = _model(s)
	var hi: Dictionary = VM.tile_inspect(s, gm, 1, 0)
	t.eq(hi["name"], "Highland", "name")
	t.eq(hi["cover_pct"], 25, "cover from the row")
	t.eq(hi["range_pct"], 25, "range from the row")
	t.eq(hi["infantry_pct"], 70, "infantry speed")
	t.eq(hi["vehicle_pct"], 70, "vehicle speed")
	t.eq(hi["buildable"], true, "buildable")
	t.eq(hi["bonus_text"], "", "no building, no bonus")
	t.eq(hi.keys().size(), 7, "exactly the seven documented fields, no sight or river penalty")
	var ford: Dictionary = VM.tile_inspect(s, gm, 2, 0)
	t.eq(ford["name"], "Ford", "ford")
	t.eq(ford["vehicle_pct"], 50, "ford slows vehicles to 50")
	t.eq(ford["infantry_pct"], 70, "ford slows infantry to 70")
	t.eq(ford["buildable"], false, "ford is not buildable")
	var river: Dictionary = VM.tile_inspect(s, gm, 0, 1)
	t.eq(river["infantry_pct"], 0, "river is impassable")
	t.eq(river["buildable"], false, "river is not buildable")


func test_tile_inspect_bonus_text_only_from_real_entity_fields(t) -> void:
	var rows := []
	for i in 10:
		rows.append("gggggggggg")
	var ents := [
		_ent(1, 0, "building", "PowerPlant", 5, 5, {"river_kw": 12}),
		_ent(2, 0, "building", "PowerPlant", 6, 5, {"river_kw": 0}),
		_ent(3, 0, "building", "Refinery", 2, 2, {"ore_bonus": true}),
		_ent(4, 0, "building", "Refinery", 8, 8, {"ore_bonus": true}),
		_ent(5, 0, "building", "Refinery", 0, 8, {"ore_bonus": false}),
		_ent(6, 0, "unit", "Infantry", 9, 0, {"river_kw": 12}),
	]
	var deposits := [{"x": 2, "y": 3, "kind": "Ore", "remaining": 100}, {"x": 8, "y": 9, "kind": "Alloy", "remaining": 100}, {"x": 0, "y": 9, "kind": "Ore", "remaining": 100}]
	var s := _mini(rows, ents, {"deposits": deposits})
	var gm = _model(s)
	t.eq(VM.tile_inspect(s, gm, 5, 5)["bonus_text"], "River +12 kW", "riverside plant reports its real kW")
	t.eq(VM.tile_inspect(s, gm, 6, 5)["bonus_text"], "", "river_kw 0 is no bonus")
	t.eq(VM.tile_inspect(s, gm, 2, 2)["bonus_text"], "Ore haul +20%", "ore bonus with an Ore deposit beside the refinery")
	t.eq(VM.tile_inspect(s, gm, 8, 8)["bonus_text"], "", "alloy beside a refinery is never a haul bonus")
	t.eq(VM.tile_inspect(s, gm, 0, 8)["bonus_text"], "", "ore_bonus false is no bonus even beside ore")
	t.eq(VM.tile_inspect(s, gm, 9, 0)["bonus_text"], "", "only buildings carry bonuses")
	t.eq(VM.tile_inspect(s, gm, 4, 4)["bonus_text"], "", "empty tile")


func test_tile_inspect_empty_cases(t) -> void:
	var s := _mini(["gg"])
	t.ok(VM.tile_inspect({}, null, 0, 0).is_empty(), "no model")
	t.ok(VM.tile_inspect(s, _model(s), -1, 0).is_empty(), "negative x")
	t.ok(VM.tile_inspect(s, _model(s), 2, 0).is_empty(), "past the right edge")
	t.ok(VM.tile_inspect(s, _model(s), 0, 1).is_empty(), "past the bottom edge")
	var f := _snap()
	var info: Dictionary = VM.tile_inspect(f, _model(f), 0, 0)
	for k in ["name", "cover_pct", "range_pct", "infantry_pct", "vehicle_pct", "buildable", "bonus_text"]:
		t.ok(info.has(k), "fixture tile has " + k)
	t.eq(info["bonus_text"], "", "no human building on tile 0,0")


# ------------------------------------------------------------------ idle crews

func test_idle_crews_counts_idle_human_units_only(t) -> void:
	var ents := [
		_ent(4, 0, "unit", "Infantry", 1, 1, {"idle": false}),
		_ent(7, 0, "unit", "Infantry", 2, 1, {"idle": true}),
		_ent(9, 0, "unit", "Tank", 3, 1, {"idle": true}),
		_ent(11, 0, "unit", "Harvester", 4, 1, {"idle": true}),
		_ent(12, 0, "building", "Barracks", 5, 1, {"idle": true}),
		_ent(13, 1, "unit", "Infantry", 6, 1, {"idle": true}),
		_ent(14, 0, "unit", "Infantry", 7, 1),
	]
	var r: Dictionary = VM.idle_crews({"entities": ents})
	t.eq(r["count"], 2, "two idle human units: the infantry and the tank")
	t.eq(r["first_id"], 7, "first idle in entity order")


func test_idle_crews_on_the_fixture_and_when_absent(t) -> void:
	var r: Dictionary = VM.idle_crews(_snap())
	t.eq(r["count"], 4, "four idle riflemen at the start")
	t.eq(r["first_id"], 1, "first id")
	t.ok(VM.idle_crews({"entities": []}).is_empty(), "no entities")
	t.ok(VM.idle_crews({}).is_empty(), "no entities key")
	t.ok(VM.idle_crews({"entities": [_ent(1, 0, "unit", "Infantry", 1, 1, {"idle": false})]}).is_empty(), "nobody idle")
	t.eq(VM.idle_crews({"entities": []}).get("count", 0), 0, "absent data reads as zero, never invented")


# ------------------------------------------------------------------ next alert

func test_next_alert_ticks_to_seconds_at_the_top_bar_rate(t) -> void:
	var tps: float = Adapter.TICKS_PER_SECOND
	t.eq(VM.next_alert({"next_wave_ticks": 1350})["seconds"], 45, "1350 ticks = 45 s at 30 tps")
	t.eq(VM.next_alert({"next_wave_ticks": 1351})["seconds"], 46, "rounds up like the top bar chip")
	t.eq(VM.next_alert({"next_wave_ticks": 0})["seconds"], 0, "zero is a real answer")
	t.eq(VM.next_alert({"next_wave_ticks": 2700})["seconds"], ceili(2700.0 / tps), "uses the adapter's rate")
	t.eq(VM.next_alert({"next_wave_ticks": 90, "waves_survived": 1})["label"], "Wave 02", "label counts survived waves")
	t.eq(VM.next_alert(_snap())["seconds"], 90, "fixture: 2700 ticks")
	t.eq(VM.next_alert(_snap())["label"], "Wave 01", "fixture label")


func test_next_alert_empty_cases(t) -> void:
	t.ok(VM.next_alert({}).is_empty(), "no timer key")
	t.ok(VM.next_alert({"next_wave_ticks": -1}).is_empty(), "negative means no wave coming")


# ------------------------------------------------------------------ wave inbound

func test_wave_inbound_carries_the_route_wave_and_eta(t) -> void:
	var w: Dictionary = VM.wave_inbound({"wave_route": [[5, 5], [4, 5]], "next_wave_ticks": 600, "waves_survived": 2})
	t.eq(w["route"], [[5, 5], [4, 5]], "route verbatim")
	t.eq(w["wave"], 3, "next wave number")
	t.eq(w["eta_s"], 20, "600 ticks = 20 s")
	var f: Dictionary = VM.wave_inbound(_snap())
	t.eq(f["route"].size(), 30, "fixture route length")
	t.eq(f["route"][0], [36, 8], "starts at the holdfast")
	t.eq(f["eta_s"], 90, "fixture eta")
	var no_timer: Dictionary = VM.wave_inbound({"wave_route": [[1, 1]]})
	t.ok(not no_timer.has("eta_s"), "no timer, no invented eta")
	t.eq(no_timer["route"], [[1, 1]], "route still reported")


func test_wave_inbound_empty_cases(t) -> void:
	t.ok(VM.wave_inbound({}).is_empty(), "no wave_route")
	t.ok(VM.wave_inbound({"wave_route": []}).is_empty(), "walled off: empty route")
	t.ok(VM.wave_inbound({"wave_route": "x"}).is_empty(), "wrong type")
	t.ok(VM.wave_inbound({"wave_route": [5, "a"]}).is_empty(), "no usable hexes")


# ------------------------------------------------------------------ enemy border

func test_enemy_border_is_every_cell_within_three_of_the_structure(t) -> void:
	var s := _mini(["gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg"], [_ent(1, 1, "building", "Barracks", 5, 5)], {})
	var cells: Array = VM.enemy_border(s)
	t.eq(cells.size(), 37, "1 + 6 + 12 + 18 hexes in radius 3")
	for c in cells:
		t.ok(VM.hex_distance(5, 5, int(c[0]), int(c[1])) <= 3, "within 3 of the structure")
	t.ok(cells.has([5, 5]), "includes the structure's own hex")
	t.ok(cells.has([5, 8]), "three straight down")
	t.ok(not cells.has([5, 9]), "four straight down is outside")
	t.ok(cells.has([8, 6]), "three columns across, shifted one down: distance 3")
	t.ok(cells.has([8, 7]), "same column count, row below: still distance 3")
	t.ok(not cells.has([8, 8]), "one row lower again is four")


func test_enemy_border_is_clipped_and_deduplicated(t) -> void:
	var s := _mini(["gggggg", "gggggg", "gggggg", "gggggg", "gggggg"], [_ent(1, 1, "building", "CommandCenter", 0, 0), _ent(2, 1, "building", "GunTurret", 1, 0)])
	var cells: Array = VM.enemy_border(s)
	var seen := {}
	for c in cells:
		t.ok(int(c[0]) >= 0 and int(c[1]) >= 0 and int(c[0]) < 6 and int(c[1]) < 5, "inside the map")
		var key := "%d,%d" % [c[0], c[1]]
		t.ok(not seen.has(key), "no duplicate " + key)
		seen[key] = true
	t.ok(cells.has([0, 3]), "(0,3) is three from (0,0)")
	t.ok(not cells.has([0, 4]), "(0,4) is four from both")
	t.eq(cells[0], [0, 0], "row-major order starts at the top left")


func test_enemy_border_ignores_human_structures_and_alien_units(t) -> void:
	var s := _mini(["gggggggggg", "gggggggggg", "gggggggggg"], [_ent(1, 0, "building", "CommandCenter", 5, 1), _ent(2, 1, "unit", "Infantry", 5, 1)])
	t.ok(VM.enemy_border(s).is_empty(), "only alien buildings anchor a border")


func test_enemy_border_falls_back_to_the_core_node(t) -> void:
	var s := _mini(["gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg", "gggggggggg"], [], {"core_node": [5, 4]})
	var cells: Array = VM.enemy_border(s)
	t.eq(cells.size(), 37, "radius 3 around the core node")
	t.ok(cells.has([5, 4]), "core node itself")
	t.ok(VM.enemy_border({}).is_empty(), "no structures, no core node")


func test_enemy_border_on_the_kestrel_fixture(t) -> void:
	var s := _snap()
	var cells: Array = VM.enemy_border(s)
	t.ok(cells.size() > 37, "the holdfast has several structures, so more than one disc")
	t.ok(cells.has([37, 8]), "core node is inside")
	t.ok(not cells.has([7, 9]), "the home base is not")
	var near_alien := 0
	for c in cells:
		var ok := false
		for e in s["entities"]:
			if e["owner"] == 1 and e["category"] == "building":
				var a: Array = VM.entity_cell(e)
				if VM.hex_distance(int(a[0]), int(a[1]), int(c[0]), int(c[1])) <= 3:
					ok = true
					break
		near_alien += 1 if ok else 0
	t.eq(near_alien, cells.size(), "every border cell is within 3 of an alien building")


# ------------------------------------------------------------------ regions and veterans

func test_regions_pass_through_and_empty(t) -> void:
	var r: Array = VM.regions(_snap())
	t.eq(r.size(), 8, "eight named regions")
	t.eq(r[0], {"name": "Sunfield", "kind": "grassland", "x0": 2, "y0": 4, "x1": 13, "y1": 14}, "first region")
	t.ok(VM.regions({}).is_empty(), "no regions key")
	t.ok(VM.regions({"regions": []}).is_empty(), "empty list")
	t.ok(VM.regions({"regions": "x"}).is_empty(), "wrong type")
	t.eq(VM.regions({"regions": [{"kind": "x"}, {"name": "A", "kind": "k", "x0": 1, "y0": 2, "x1": 3, "y1": 4}]}).size(), 1, "unnamed rows dropped")


func test_veterans_only_ranks_above_zero(t) -> void:
	var ents := [
		_ent(5, 0, "unit", "Infantry", 1, 1, {"rank": 1}),
		_ent(6, 0, "unit", "Infantry", 2, 1, {"rank": 0}),
		_ent(8, 0, "unit", "Tank", 3, 1, {"rank": 2}),
		_ent(9, 0, "building", "Barracks", 4, 1),
	]
	t.eq(VM.veterans({"entities": ents}), {5: 1, 8: 2}, "ids map to ranks, zero and rankless omitted")
	t.ok(VM.veterans(_snap()).is_empty(), "fixture: nobody ranked yet")
	t.ok(VM.veterans({}).is_empty(), "no entities")


# ------------------------------------------------------------------ hud_vm wiring

func _kestrel_adapter() -> Array:
	var g := Stub.new()
	g.use_kestrel()
	g.bridge_next_wave_ticks = 2700
	g.bridge_waves = 0
	var a := Adapter.new(g)
	a.tab = "units"
	return [g, a]


func test_hud_vm_gets_slices_from_the_kestrel_snapshot(t) -> void:
	var p := _kestrel_adapter()
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.eq(vm["territory"]["tiles"], 343, "territory slice")
	t.eq(vm["idle"], {"count": 4, "first_id": 1}, "idle slice")
	t.eq(vm["alert"], {"label": "Wave 01", "seconds": 90}, "alert slice")
	t.eq(vm["regions"].size(), 8, "regions slice")
	t.ok(not vm.has("veterans"), "nobody ranked: no veterans key")
	t.ok(not vm.has("inspect"), "no hover, no inspect")
	t.eq(vm["wave"]["route"].size(), 30, "route rides on the wave chip")
	t.eq(vm["wave"]["eta_s"], 90, "eta")
	t.eq(vm["wave"]["label"], "Wave 01 Siege", "the chip's own label is untouched")
	t.eq(vm["wave"]["timer"], "T-01:30", "the chip's own timer is untouched")


func test_hud_vm_inspect_follows_the_hovered_hex(t) -> void:
	var p := _kestrel_adapter()
	p[0].hover_cell = Vector2i(7, 9)
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.eq(vm["inspect"]["name"], p[0].ground_model.name_at(7, 9), "inspect names the hovered tile")
	p[0].hover_cell = Vector2i(99, 99)
	t.ok(not p[1].hud_vm(0.0).has("inspect"), "off-map hover adds nothing")
	p[0].hover_cell = null
	t.ok(not p[1].hud_vm(0.0).has("inspect"), "no hover adds nothing")


func test_hud_vm_veterans_appear_once_a_unit_has_rank(t) -> void:
	var p := _kestrel_adapter()
	p[0].bridge_snapshot["entities"][1]["rank"] = 2
	t.eq(p[1].hud_vm(0.0)["veterans"], {1: 2}, "unit 1 is a rank 2 veteran")


func test_hud_vm_unchanged_without_a_snapshot(t) -> void:
	var g := Stub.new()
	var a := Adapter.new(g)
	a.tab = "units"
	var vm: Dictionary = a.hud_vm(0.0)
	for key in ["territory", "inspect", "idle", "alert", "regions", "veterans"]:
		t.ok(not vm.has(key), "no snapshot, no " + key)
	t.ok(not vm["wave"].has("route"), "wave chip carries no route")
	t.eq(vm["wave"].keys().size(), 2, "wave chip is still label + timer")
	a.tab = "build"
	t.ok(not a.hud_vm(0.0).has("territory"), "build layout also clean without a snapshot")


func test_hud_vm_build_layout_gets_the_slices_too(t) -> void:
	var p := _kestrel_adapter()
	p[1].tab = "build"
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("build_top"), "still the build layout")
	t.eq(vm["territory"]["tiles"], 343, "territory present")
	t.eq(vm["idle"]["count"], 4, "idle present")
	t.ok(not vm.has("wave"), "the build layout has no wave chip to extend")
