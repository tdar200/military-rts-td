extends RefCounted
## Board 1 (Main) additions: slices in vm_gameplay.gd and their wiring through live_adapter.gd.
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const Stub := preload("res://tests/stub_game.gd")


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _mini(entities: Array, extra := {}) -> Dictionary:
	var snap := {"map_width": 8, "map_height": 8, "ground": "".repeat(1) + "g".repeat(64), "ground_table": _snap()["ground_table"], "entities": entities}
	snap.merge(extra, true)
	return snap


func _ent(id: int, owner: int, category: String, kind: String, x: int, y: int, extra := {}) -> Dictionary:
	var sx := 0.5 + 0.75 * x
	var sz := 0.5 + y + (0.5 if x % 2 != 0 else 0.0)
	var e := {"id": id, "owner": owner, "category": category, "kind": kind, "x_bits": roundi(sx * 65536.0), "z_bits": roundi(sz * 65536.0)}
	e.merge(extra, true)
	return e


# ------------------------------------------------------------------ slice functions

func test_yields_only_real_generation(t) -> void:
	t.eq(VM.yields({"power_generation": 168}), [{"text": "+168 kW", "tone": "warn"}], "generation becomes one kW pill")
	t.eq(VM.yields({"power_generation": 0}), [], "no generation, no pill")
	t.eq(VM.yields({}), [], "no field, no pill")


func test_tile_context_carries_coordinates_zone_and_deposit(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	var dep: Dictionary = snap["deposits"][0]
	var ctx := VM.tile_context(snap, ground, int(dep["x"]), int(dep["y"]))
	t.eq(ctx["x"], int(dep["x"]), "x")
	t.eq(ctx["deposit"]["remaining"], int(dep["remaining"]), "deposit remaining is the snapshot's")
	t.eq(ctx["glyph"], ground.glyph_at(int(dep["x"]), int(dep["y"])), "glyph from the ground model")
	var zone: Array = snap["construction_zone"][0]
	t.ok(VM.tile_context(snap, ground, int(zone[0]), int(zone[1]))["zone"], "a construction-zone hex is player territory")
	t.eq(VM.tile_context(snap, ground, -1, 0), {}, "off the map is empty")


func test_deposit_pins_mark_claimed_ore_only(t) -> void:
	var snap := _mini([_ent(1, 0, "building", "Refinery", 2, 2)], {"deposits": [
		{"x": 2, "y": 3, "kind": "Ore", "remaining": 1800},
		{"x": 6, "y": 6, "kind": "Ore", "remaining": 900},
		{"x": 2, "y": 2, "kind": "Alloy", "remaining": 500},
		{"x": 4, "y": 4, "kind": "Ore", "remaining": 0},
	]})
	var pins := VM.deposit_pins(snap)
	t.eq(pins.size(), 3, "the emptied deposit is left out")
	t.ok(pins[0]["claimed"], "ore beside a refinery is claimed")
	t.ok(not pins[1]["claimed"], "far ore is unclaimed")
	t.ok(not pins[2]["claimed"], "alloy is never claimed by a refinery")
	t.eq(pins[0]["remaining"], 1800, "real remaining")


func test_ledger_counts_only_the_players_entities(t) -> void:
	var snap := _mini([
		_ent(1, 0, "building", "Barracks", 1, 1, {"construction": 0}),
		_ent(2, 0, "building", "Refinery", 2, 1),
		_ent(3, 0, "unit", "Infantry", 3, 3),
		_ent(4, 1, "unit", "Alien", 5, 5),
		_ent(5, 1, "building", "Hive", 6, 6),
	], {"supply_used": 4, "supply_cap": 60})
	var l := VM.ledger(snap)
	t.eq(l["structures"], 2, "two human structures")
	t.eq(l["units"], 1, "one human unit")
	t.eq(l["crew_used"], 4, "crew used")
	t.eq(l["crew_cap"], 60, "crew cap")
	t.ok(not l.has("battery_pct"), "no storage capacity, no battery")
	t.eq(l["production"], [{"name": "Barracks", "state": "idle", "note": "queue empty"}], "an idle producer is an idle row")
	t.eq(VM.ledger({}), {}, "no entities, no ledger")


func test_ledger_production_row_shows_progress(t) -> void:
	var snap := _mini([
		_ent(1, 0, "building", "VehicleFactory", 1, 1, {"construction": 0, "production_name": "Tank", "production_progress": 300, "production_duration": 600}),
	], {"tick_rate": 30})
	var rows: Array = VM.ledger(snap)["production"]
	t.eq(rows.size(), 1, "one row")
	t.eq(rows[0]["state"], "busy", "busy")
	t.near(rows[0]["ratio"], 0.5, 0.001, "half way")
	t.ok(str(rows[0]["note"]).begins_with("Tank "), "note names the unit in production")


func test_lens_hexes(t) -> void:
	var snap := _snap()
	t.eq(VM.lens_hexes(snap, "land"), {}, "land draws nothing")
	t.eq(VM.lens_hexes(snap, "nonsense"), {}, "unknown lens draws nothing")
	var live := 0
	for d in snap["deposits"]:
		live += 1 if int(d["remaining"]) > 0 else 0
	t.eq(VM.lens_hexes(snap, "res")["dots"].size(), live, "one dot per live deposit")
	var cells: Array = VM.lens_hexes(snap, "bdr")["cells"]
	t.ok(cells.size() >= snap["construction_zone"].size(), "border lens has at least the own zone")
	t.eq(cells[0]["k"], "own", "own zone first")


func test_army_counts_combat_units_and_idle(t) -> void:
	var snap := _mini([
		_ent(1, 0, "unit", "Infantry", 1, 1),
		_ent(2, 0, "unit", "Tank", 2, 1),
		_ent(3, 0, "unit", "Harvester", 3, 1),
		_ent(4, 1, "unit", "Alien", 5, 5),
	])
	var a := VM.army(snap)
	t.eq(a["count"], 2, "harvesters and aliens are not army")
	t.ok(a.has("idle") and a.has("first_idle"), "idle fields always present")
	t.eq(VM.army(_mini([])), {}, "no units, no slice")


# ------------------------------------------------------------------ adapter wiring

class Cam extends Stub:
	var focused: Array = []
	var army_calls := 0

	func hex_world_point(x: int, y: int) -> Vector3:
		return Vector3(0.5 + 0.75 * x, 0.0, 0.5 + y + (0.5 if x % 2 != 0 else 0.0))

	func screen_point_of_hex(x: int, y: int) -> Vector2:
		return Vector2(100.0 + x * 40.0, 200.0 + y * 30.0)

	func select_army() -> void:
		army_calls += 1

	func focus_camera(pos: Vector3, zoom: float) -> void:
		focused.append([pos, zoom])


func _live() -> Array:
	var g := Cam.new()
	g.use_kestrel()
	g.bridge_next_wave_ticks = 2700
	g.bridge_waves = 0
	var a := Adapter.new(g)
	a.tab = "units"
	return [g, a]


func test_main_layout_gets_board_one_slices(t) -> void:
	var p := _live()
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("ledger") and vm.has("army") and vm.has("lens") and vm.has("pins"), "ledger, army, lens and pins present")
	t.eq(vm["lens"], {"on": "land"}, "land lens by default carries no overlay")
	t.eq(vm["brand"]["sub"], p[0].bridge_snapshot["map_name"], "the brand sub names the map")
	t.eq(vm["minimap"]["name"], p[0].bridge_snapshot["map_name"], "minimap header names the map")
	for pin in vm["pins"]:
		t.ok(pin["x"] >= 20 and pin["x"] <= 1900 and pin["y"] >= 110 and pin["y"] <= 760, "pins are on screen")
		t.eq((pin["cell"] as Array).size(), 2, "pins keep their hex for the click")


func test_selection_hides_the_bottom_centre_slices(t) -> void:
	var p := _live()
	p[0].hover_cell = Vector2i(3, 3)
	var vm: Dictionary = p[1]._with_gameplay({"selection": {"name": "x"}, "minimap": {}})
	t.ok(not vm.has("ledger") and not vm.has("army") and not vm.has("inspect"), "a selection owns the bottom centre")
	t.ok(vm.has("lens"), "the minimap lens still shows")


func test_build_layout_has_no_colony_panel_or_lens(t) -> void:
	var p := _live()
	var vm: Dictionary = p[1]._with_gameplay({"build_top": {}})
	t.ok(not vm.has("ledger") and not vm.has("army") and not vm.has("lens") and not vm.has("inspect"), "build layout draws its own deck")
	t.ok(vm.has("territory"), "territory card is shared")


func test_hovered_hex_adds_tile_context(t) -> void:
	var p := _live()
	p[0].hover_cell = Vector2i(7, 9)
	var inspect: Dictionary = p[1].hud_vm(0.0)["inspect"]
	t.eq(inspect["x"], 7, "x from the hover")
	t.eq(inspect["y"], 9, "y from the hover")
	t.ok(inspect.has("glyph") and inspect.has("zone"), "context merged in")


func test_lens_action_switches_and_ignores_unknown(t) -> void:
	var p := _live()
	p[1].on_action("minimap_lens", "res")
	t.eq(p[1].hud_vm(0.0)["lens"]["on"], "res", "res lens on")
	t.ok(p[1].hud_vm(0.0)["lens"].has("overlay"), "res lens carries deposit dots")
	p[1].on_action("minimap_lens", "bogus")
	t.eq(p[1].lens, "res", "unknown lens ignored")
	p[1].on_action("minimap_lens", "land")
	t.eq(p[1].lens, "land", "back to land")


func test_select_army_focus_deposit_and_select_idle_actions(t) -> void:
	var p := _live()
	p[1].on_action("select_army", null)
	t.eq(p[0].army_calls, 1, "select_army reaches the game")
	p[1].on_action("focus_deposit", [5, 6])
	t.eq(p[0].focused.size(), 1, "focus_deposit moves the camera once")
	t.eq(p[0].focused[0][0], p[0].hex_world_point(5, 6), "to that hex")
	p[1].on_action("focus_deposit", [])
	t.eq(p[0].focused.size(), 1, "a malformed cell does nothing")


func test_pins_need_a_projecting_game(t) -> void:
	var g := Stub.new()
	g.use_kestrel()
	var a := Adapter.new(g)
	a.tab = "units"
	var vm: Dictionary = a.hud_vm(0.0)
	t.ok(not vm.has("pins"), "no screen_point_of_hex, no pins")
	t.eq(vm["lens"], {"on": "land"}, "lens still reports")


# ------------------------------------------------------------------ earthfront_3d.gd wiring (source level)

func test_earthfront_exposes_the_members_the_adapter_reads(t) -> void:
	var script: GDScript = load("res://scripts/earthfront_3d.gd")
	var src: String = script.source_code
	for needle in ["var bridge_snapshot: Dictionary", "var hover_cell", "func screen_point_of_hex", "func hex_world_point", "func select_army", "func select_idle_crew"]:
		t.ok(src.contains(needle), "earthfront_3d.gd declares " + needle)
	var names: Array = script.get_script_property_list().map(func(p): return p["name"])
	t.ok("hover_cell" in names and "bridge_snapshot" in names, "both are real script members")
