extends RefCounted
## Boards 2 and 3 (BuildDeck, CoreAssault): slice functions in vm_gameplay.gd and their wiring through live_adapter.gd.
## Cells below are Kestrel Reach's (the committed snapshot): zone ground is grass, an Ore deposit sits at (7,11) and the
## river runs down columns 15-16.
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const Stub := preload("res://tests/stub_game.gd")


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _row(rows: Array, label: String) -> Dictionary:
	for r in rows:
		if str(r.get("label", "")) == label:
			return r
	return {}


# ------------------------------------------------------------------ placing

func test_placing_a_refinery_on_ore_names_the_deposit_and_the_bonus(t) -> void:
	var snap := _snap()
	var p := VM.placing(snap, GroundModel.from_snapshot(snap), "Refinery", "Refinery", 7, 10, true, 20)
	t.eq(p["title"], "Refinery", "title is the building name")
	t.eq(p["status"], "1 hex is clear", "single-hex footprint, never a tile grid")
	t.eq(p["tone"], "good", "valid hex is good")
	t.eq(p["footprint"], "Footprint 1 hex on Grassland", "footprint line says 1 hex and the real ground")
	var ore := _row(p["rows"], "Ore in range")
	t.eq(ore["value"], "Ore, 30,000 left, +20% output", "the deposit's real remaining and the sim's bonus")
	t.eq(ore["tone"], "good", "bonus is good")
	t.ok(_row(p["rows"], "Slope").is_empty(), "no slope data, no slope row")


func test_refinery_far_from_ore_says_there_is_no_bonus(t) -> void:
	var snap := _snap()
	var p := VM.placing(snap, GroundModel.from_snapshot(snap), "Refinery", "Refinery", 1, 18, true, 20)
	var ore := _row(p["rows"], "Ore in range")
	t.eq(ore["value"], "None within 1 hex, no bonus", "no deposit nearby")
	t.eq(ore["tone"], "dim", "dim")


func test_power_plant_beside_the_river_shows_the_cooling_bonus(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	var wet := VM.placing(snap, ground, "PowerPlant", "Reactor", 14, 1, true, -80)
	t.eq(_row(wet["rows"], "River")["value"], "River or ford beside it, +12 kW", "river hex beside it")
	var dry := VM.placing(snap, ground, "PowerPlant", "Reactor", 7, 10, true, -80)
	t.eq(_row(dry["rows"], "River")["value"], "No river or ford beside it", "no wet neighbour")
	t.ok(_row(wet["rows"], "Ore in range").is_empty(), "ore row is for refineries only")


func test_blocked_ground_and_territory_come_from_the_tables(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	var shore := VM.placing(snap, ground, "Barracks", "Barracks", 39, 17, false, 10)
	t.eq(shore["status"], "1 hex is blocked", "invalid hex is blocked")
	t.eq(shore["tone"], "warn", "warn tone")
	t.eq(_row(shore["rows"], "Blocked tile"), {"label": "Blocked tile", "value": "Shore, cannot build", "tone": "bad"}, "the ground table says shore is not buildable")
	t.eq(_row(shore["rows"], "Territory")["value"], "Outside the construction zone", "zone membership")
	var fine := VM.placing(snap, ground, "Barracks", "Barracks", 7, 10, true, 10)
	t.ok(_row(fine["rows"], "Blocked tile").is_empty() and _row(fine["rows"], "Territory").is_empty(), "a clear hex lists no blockers")


func test_power_row_follows_demand_against_generation(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	snap["power_generation"] = 168
	snap["power_demand"] = 160
	var over := VM.placing(snap, ground, "Refinery", "Refinery", 7, 10, true, 25)
	t.eq(_row(over["rows"], "Power"), {"label": "Power", "value": "-25 kW, grid over capacity", "tone": "warn"}, "demand 160 + 25 against 168")
	var fits := VM.placing(snap, ground, "Refinery", "Refinery", 7, 10, true, 5)
	t.eq(_row(fits["rows"], "Power")["value"], "-5 kW, within capacity", "165 of 168 fits")
	var makes := VM.placing(snap, ground, "PowerPlant", "Reactor", 7, 10, true, -80)
	t.eq(_row(makes["rows"], "Power")["value"], "+80 kW generation", "a reactor adds output")
	t.ok(_row(VM.placing(snap, ground, "Wall", "Field wall", 7, 10, true, 0)["rows"], "Power").is_empty(), "a wall draws nothing: no row")


func test_placing_off_the_map_or_without_ground_is_empty(t) -> void:
	var snap := _snap()
	t.eq(VM.placing(snap, GroundModel.from_snapshot(snap), "Barracks", "Barracks", -1, 3, false, 10), {}, "off the map")
	t.eq(VM.placing(snap, null, "Barracks", "Barracks", 3, 3, true, 10), {}, "no ground model")


# ------------------------------------------------------------------ power grid

func test_power_grid_projects_with_the_build_screens_maths(t) -> void:
	var snap := _snap()
	snap["power_generation"] = 168
	snap["power_demand"] = 160
	var g := VM.power_grid(snap, GroundModel.from_snapshot(snap), "Refinery", 25)
	t.eq(g["value"], "185 / 168 kW", "load after against generation")
	t.eq(g["tone"], "warn", "adding load is warn")
	t.eq(g["over"], 17, "17 kW over")
	t.eq(g["lead"], "17 kW over.", "lead sentence")
	t.eq(g["segments"].size(), 3, "load, planned load, hatched overflow")
	t.eq(g["segments"][2]["tone"], "bad_hatch", "overflow is hatched")
	t.near(g["marker"], 168.0 / 210.0, 0.001, "capacity marker")


func test_power_grid_hint_points_at_the_river_only_when_there_is_one(t) -> void:
	var snap := _snap()
	snap["power_generation"] = 168
	snap["power_demand"] = 160
	var ground := GroundModel.from_snapshot(snap)
	t.eq(VM.power_grid(snap, ground, "Refinery", 25)["text"], "Build a Reactor beside the river for +12 kW cooling.", "a river hex lies beside the zone")
	var dry := _snap()
	dry["power_generation"] = 168
	dry["power_demand"] = 160
	dry["construction_zone"] = [[7, 10], [7, 11]]
	t.eq(VM.power_grid(dry, GroundModel.from_snapshot(dry), "Refinery", 25)["text"], "Defence keeps priority; industry shares the deficit.", "no river by the zone: the generic line")


func test_power_grid_within_capacity_has_no_warning_line(t) -> void:
	var snap := _snap()
	snap["power_generation"] = 168
	snap["power_demand"] = 100
	var g := VM.power_grid(snap, GroundModel.from_snapshot(snap), "Refinery", 20)
	t.eq(g["over"], 0, "fits")
	t.eq(g["lead"], "", "no lead")
	t.eq(g["text"], "", "no text")
	t.eq(VM.power_grid({}, null, "Refinery", 20), {}, "no snapshot power, no slice")


# ------------------------------------------------------------------ enemy intel

func test_enemy_intel_counts_what_the_snapshot_holds(t) -> void:
	var snap := _snap()
	var e := VM.enemy_intel(snap, GroundModel.from_snapshot(snap))
	t.eq(_row(e["rows"], "Defences")["value"], "4 gun, 2 AA", "four gun turrets and two AA, no walls listed")
	t.eq(_row(e["rows"], "Garrison")["value"], "6 units", "six alien units, no seen/estimated split")
	t.eq(_row(e["rows"], "Terrain")["value"], "Dry flats, Highland", "the two commonest grounds inside the border")
	var reinforce := _row(e["rows"], "Reinforce")
	t.eq(reinforce["value"], "1:30, 10 units", "next wave timer and expedition size")
	t.eq(reinforce["tone"], "warn", "warn")
	t.ok(not str(e).contains("est."), "no estimates")
	t.ok(not str(e).contains("seen"), "no fog language")


func test_enemy_intel_walls_and_short_timers(t) -> void:
	var snap := _snap()
	var wall: Dictionary = snap["entities"][8].duplicate()
	wall["id"] = 99
	wall["kind"] = "Wall"
	snap["entities"].append(wall)
	snap["next_wave_ticks"] = 1350
	var e := VM.enemy_intel(snap, GroundModel.from_snapshot(snap))
	t.eq(_row(e["rows"], "Defences")["value"], "4 gun, 2 AA, 1 wall", "walls are counted when present")
	t.eq(_row(e["rows"], "Reinforce")["value"], "45 s, 10 units", "under a minute reads in seconds")


func test_enemy_intel_is_empty_without_aliens(t) -> void:
	var snap := _snap()
	snap["entities"] = snap["entities"].filter(func(x): return x["owner"] == 0)
	t.eq(VM.enemy_intel(snap, GroundModel.from_snapshot(snap)), {}, "nothing hostile, nothing to say")
	t.eq(VM.enemy_intel({}, null), {}, "no snapshot")


# ------------------------------------------------------------------ combat preview

func test_combat_preview_names_the_matchup_and_reads_the_ground(t) -> void:
	var snap := _snap()
	var c := VM.combat_preview(snap, GroundModel.from_snapshot(snap), [1, 2, 3, 4], [34, 6])
	t.eq(c["sub"], "4 x Riflemen vs Alien gun turret", "attackers by kind against the target kind")
	t.eq(_row(c["rows"], "Standing on Grassland")["value"], "normal speed", "grass is 100% for infantry")
	var target := _row(c["rows"], "Target on Dry flats")
	t.eq(target["value"], "no cover", "dry flats give no cover")
	t.ok(not str(c).contains("range 7"), "no range figure is shown")
	t.ok(not str(c).contains("health"), "no health figure is shown")


func test_combat_preview_cover_and_range_come_from_the_ground_table(t) -> void:
	var snap := _snap()
	var c := VM.combat_preview(snap, GroundModel.from_snapshot(snap), [1], [27, 2])
	var cover := _row(c["rows"], "Target on Highland")
	t.eq(cover["value"], "-25% damage", "highland cover is 25%")
	t.eq(cover["tone"], "bad", "cover works against the attacker")
	# Put the rifleman on the ridge: speed -30%, range +25%.
	for e in snap["entities"]:
		if int(e["id"]) == 1:
			var at := [27, 2]
			e["x_bits"] = roundi((0.5 + 0.75 * at[0]) * 65536.0)
			e["z_bits"] = roundi((0.5 + at[1] + (0.5 if at[0] % 2 != 0 else 0.0)) * 65536.0)
	var ridge := VM.combat_preview(snap, GroundModel.from_snapshot(snap), [1], [34, 6])
	t.eq(_row(ridge["rows"], "Standing on Highland")["value"], "speed -30%", "highland slows infantry 30%")
	t.eq(_row(ridge["rows"], "Holding Highland")["value"], "+25% range", "ridge range bonus")


func test_combat_preview_needs_attackers_and_a_hostile_target(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	t.eq(VM.combat_preview(snap, ground, [], [34, 6]), {}, "no selection")
	t.eq(VM.combat_preview(snap, ground, [1], [20, 20]), {}, "empty hex")
	t.eq(VM.combat_preview(snap, ground, [1], [7, 9]), {}, "own building is not a target")
	t.eq(VM.combat_preview(snap, ground, [5], [34, 6]), {}, "an alien id is not an attacker")


func _with_ranks(snap: Dictionary, ranks: Dictionary) -> void:
	for e in snap["entities"]:
		if ranks.has(int(e["id"])):
			e["rank"] = ranks[int(e["id"])]


func test_combat_preview_shows_the_damage_type_against_the_target_armour(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	# Riflemen (Ballistic) against a gun turret (Structure): neutral.
	var turret := VM.combat_preview(snap, ground, [1, 2], [34, 6])
	var neutral := _row(turret["rows"], "Ballistic vs Structure")
	t.eq(neutral["value"], "normal damage", "Ballistic against Structure is neutral in the sim")
	t.eq(neutral["tone"], "dim", "neutral is dim")
	# Riflemen against an alien rifleman (Flesh): +50%.
	var foe := {}
	for e in snap["entities"]:
		if int(e["owner"]) == 1 and e["kind"] == "Infantry":
			foe = e
			break
	var at := VM.entity_cell(foe)
	var flesh := VM.combat_preview(snap, ground, [1], [at[0], at[1]])
	var plus := _row(flesh["rows"], "Ballistic vs Flesh")
	t.eq(plus["value"], "+50% damage", "Ballistic against Flesh is x1.5")
	t.eq(plus["tone"], "good", "an edge is good")
	# Rocket team (Anti-armor) against Flesh is -50%, bad.
	for e in snap["entities"]:
		if int(e["id"]) == 2:
			e["kind"] = "AntiArmor"
	var rockets := VM.combat_preview(snap, ground, [2], [at[0], at[1]])
	var minus := _row(rockets["rows"], "Anti-armor vs Flesh")
	t.eq(minus["value"], "-50% damage", "Anti-armor against Flesh is x0.5")
	t.eq(minus["tone"], "bad", "a handicap is bad")
	# Rocket team against a turret: Anti-armor vs Structure is neutral.
	t.eq(_row(VM.combat_preview(snap, ground, [2], [34, 6])["rows"], "Anti-armor vs Structure")["value"], "normal damage", "neutral")


func test_mixed_attackers_get_one_damage_row_per_kind(t) -> void:
	var snap := _snap()
	for e in snap["entities"]:
		if int(e["id"]) == 3:
			e["kind"] = "Tank"
	var c := VM.combat_preview(snap, GroundModel.from_snapshot(snap), [1, 2, 3], [34, 6])
	t.eq(_row(c["rows"], "Riflemen: Ballistic vs Structure")["value"], "normal damage", "riflemen row carries the kind name")
	t.eq(_row(c["rows"], "Battle tank: Explosive vs Structure")["value"], "+50% damage", "tank shells against a building: x1.5")
	t.ok(_row(c["rows"], "Ballistic vs Structure").is_empty(), "with two kinds the plain label is not used")


func test_rank_bonus_uses_the_sim_veterancy_values(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	_with_ranks(snap, {1: 2, 2: 2, 3: 1, 4: 0})
	var c := VM.combat_preview(snap, ground, [1, 2, 3, 4], [34, 6])
	t.eq(_row(c["rows"], "Veteran rank 2, 2 units")["value"], "+20% damage", "rank 2 is +20% and two units have it")
	t.eq(_row(c["rows"], "Veteran rank 1")["value"], "+10% damage", "rank 1 is +10%, one unit")
	t.ok(_row(c["rows"], "Veteran rank 0").is_empty(), "rank 0 earns no row")
	_with_ranks(snap, {1: 3})
	var top := VM.combat_preview(snap, ground, [1], [34, 6])
	t.eq(_row(top["rows"], "Veteran rank 3")["value"], "+35% damage", "rank 3 is +35%")


func test_no_rank_row_without_veterans_and_none_for_unarmed_units(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	for r in VM.combat_preview(snap, ground, [1, 2], [34, 6])["rows"]:
		t.ok(not str(r["label"]).begins_with("Veteran"), "no veterans selected, no rank rows")
	for e in snap["entities"]:
		if int(e["id"]) == 1:
			e["kind"] = "Harvester"
			e["rank"] = 2
	var c := VM.combat_preview(snap, ground, [1], [34, 6])
	t.ok(c.is_empty() or _row(c["rows"], "Veteran rank 2").is_empty(), "a harvester has no weapon, so no rank bonus")
	if not c.is_empty():
		for r in c["rows"]:
			t.ok(not str(r["label"]).contains(" vs Structure"), "and no damage-type row")


func test_unknown_pairs_build_no_damage_row(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	for e in snap["entities"]:
		if int(e["owner"]) == 1 and e["kind"] == "GunTurret":
			e["category"] = "mystery"
	var c := VM.combat_preview(snap, ground, [1], [34, 6])
	for r in c.get("rows", []):
		t.ok(not str(r["label"]).contains(" vs "), "an unknown target class builds no matchup row")


# ------------------------------------------------------------------ thr lens

func test_threat_lens_draws_the_route_and_the_enemy_territory(t) -> void:
	var h := VM.lens_hexes(_snap(), "thr")
	t.ok(h.has("route") and h["route"].size() > 1, "route")
	t.ok(h.has("cells") and h["cells"].size() > 10, "enemy territory cells")
	for c in h["cells"]:
		t.eq(c["k"], "enemy", "only enemy cells")
		break


# ------------------------------------------------------------------ adapter wiring

class Cam extends Stub:
	var focused: Array = []

	func hex_world_point(x: int, y: int) -> Vector3:
		return Vector3(0.5 + 0.75 * x, 0.0, 0.5 + y + (0.5 if x % 2 != 0 else 0.0))

	func screen_point_of_hex(x: int, y: int) -> Vector2:
		return Vector2(100.0 + x * 40.0, 200.0 + y * 30.0)

	func focus_camera(pos: Vector3, zoom: float) -> void:
		focused.append([pos, zoom])


func _live() -> Array:
	var g := Cam.new()
	g.use_kestrel()
	g.bridge_next_wave_ticks = 2700
	g.bridge_waves = 0
	g.bridge_power_generation = 168
	g.bridge_power_demand = 160
	g.bridge_snapshot["power_generation"] = 168
	g.bridge_snapshot["power_demand"] = 160
	g.bridge_money = 840
	return [g, Adapter.new(g)]


func test_build_layout_swaps_the_old_panel_for_the_card_and_the_grid(t) -> void:
	var p := _live()
	p[0].build_mode = "Refinery"
	p[0].hover_cell = Vector2i(7, 10)
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("placing") and vm.has("power_grid"), "placing card and grid slices")
	t.ok(not vm.has("build_placement"), "the old 728px panel is replaced when the ground is known")
	t.eq(vm["placing"]["title"], "Refinery", "armed card")
	t.eq(vm["placing"]["footprint"], "Footprint 1 hex on Grassland", "hovered hex")
	t.eq(vm["power_grid"]["value"], "180 / 168 kW", "refinery draws 20 kW")
	t.ok(vm["placing"]["x"] >= 12 and vm["placing"]["y"] >= 70, "card sits on screen")
	t.ok(vm["placement_hint"]["right"] > 800.0 and vm["placement_hint"]["right"] <= 1892.0, "the hint chip ends left of the wave chip")


func test_card_follows_the_hovered_hex_and_stays_clear_of_the_deck(t) -> void:
	var p := _live()
	p[0].build_mode = "Refinery"
	p[0].hover_cell = Vector2i(30, 15)
	var vm: Dictionary = p[1].hud_vm(0.0)
	var card: Dictionary = vm["placing"]
	t.ok(card["x"] + 340 <= 1124 or card["y"] + 300 <= 494, "never over the deck (x 1124+, y 494+)")
	t.ok(card["y"] + 250 <= 1080, "never below the screen")


func test_no_hover_or_no_ground_keeps_the_old_panel(t) -> void:
	var p := _live()
	p[0].build_mode = "Refinery"
	p[0].hover_cell = null
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("build_placement"), "off the map: the old panel still tells the player what is armed")
	t.ok(not vm.has("placing"), "no card without a hovered hex")
	var bare := Stub.new()
	bare.build_mode = "Refinery"
	t.ok(Adapter.new(bare).hud_vm(0.0).has("build_placement"), "no snapshot: the old panel")


func test_grid_panel_rises_above_a_tall_alert_stack(t) -> void:
	var p := _live()
	p[0].build_mode = "Refinery"
	p[0].hover_cell = Vector2i(7, 10)
	var quiet: Dictionary = p[1].hud_vm(0.0)
	t.eq(quiet["power_grid"]["y"], 560, "one or no alert row: the board's place")
	for i in 4:
		p[1].push_notification("Alert %d" % i, "", Color.WHITE, 0.0)
	var busy: Dictionary = p[1].hud_vm(1.0)
	t.ok(busy["power_grid"]["y"] < 560, "the panel climbs so the alert rows never overlap it")


func test_hostile_hover_with_a_selection_adds_enemy_combat_and_pin(t) -> void:
	var p := _live()
	p[1].tab = "units"
	for id in [1, 2]:
		var n: Node3D = p[0].add_node(id, "Infantry", "unit", 0, Vector3(0, 0, 0))
		p[0].selected_units.append(n)
	p[0].hover_cell = Vector2i(34, 6)
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("combat"), "combat preview over a hostile hex")
	t.eq(vm["combat"]["sub"], "2 x Riflemen vs Alien gun turret", "matchup")
	var hostile: Array = vm["pins"].filter(func(x): return x.get("hostile", false))
	t.eq(hostile.size(), 1, "one hostile pin on the target")
	t.eq(hostile[0]["kind"], "Gun turret", "named by the target kind")
	p[0].hover_cell = Vector2i(7, 9)
	t.ok(not p[1].hud_vm(0.0).has("combat"), "no preview over your own base")
	for n in p[0].selected_units:
		n.free()


func test_enemy_intel_rides_the_assault_layout_only(t) -> void:
	var p := _live()
	p[1].tab = "orders"
	p[1].assault.engaged = true
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("enemy"), "enemy territory card in the core assault layout")
	t.eq(_row(vm["enemy"]["rows"], "Defences")["value"], "4 gun, 2 AA", "from the snapshot")
	t.ok(vm["enemy"]["y"] >= 270, "below the objective panel")
	t.ok(not vm.has("territory") and not vm.has("ledger"), "the assault layout keeps its own panels")
	p[1].assault.engaged = false
	p[1].tab = "units"
	t.ok(not p[1].hud_vm(0.0).has("enemy"), "the main layout has the territory card in that spot")


func test_sim_bonus_constants_have_not_drifted(t) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/earthfront.rs"), FileAccess.READ)
	t.ok(f != null, "the Rust source is reachable from the project (the repo layout the tests assume)")
	if f == null:
		return
	var src := f.get_as_text()
	t.ok(src.contains("Extra kW (12) a power plant draws from a River or Ford hex beside it"), "river bonus is still 12 kW")
	t.eq(VM.RIVER_BONUS_KW, 12, "client river bonus")
	t.ok(src.contains("Ore-yield bonus percent (0 or 20)"), "ore bonus is still 20%")
	t.eq(VM.ORE_BONUS_PCT, 20, "client ore bonus")
	t.ok(src.contains("hex::distance(tile, (dx, dy)) <= 1"), "ore reach is still one hex")
	t.eq(VM.ORE_BONUS_RADIUS, 1, "client ore reach")
