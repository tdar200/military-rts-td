extends RefCounted
## Boards 4, 5 and 7 (StructureSelected, OrdersArmed, WaveInbound): slice functions in vm_gameplay.gd. Cells are Kestrel
## Reach's (the committed snapshot): the player's Command Center stands on (7,9), the wave route runs (36,8) -> (7,9) and
## enters the construction zone at (20,10), Wyllow Ford is the region around (21..24, 10..12).
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


## sim coordinates of a hex centre (columns 0.75 apart, odd columns half a row lower), as 16.16 fixed point.
func _bits(col: int, row: int) -> Array:
	var sx := col * 0.75 + 0.5
	var sz := row + 0.5 + (0.5 if col % 2 != 0 else 0.0)
	return [int(sx * 65536.0), int(sz * 65536.0)]


func _entity(id: int, kind: String, category: String, col: int, row: int, hp := 100, max_hp := 100, owner := 0) -> Dictionary:
	var b := _bits(col, row)
	return {"id": id, "owner": owner, "category": category, "kind": kind, "x_bits": b[0], "z_bits": b[1],
		"hp_bits": hp * 65536, "max_hp_bits": max_hp * 65536, "rally_x_bits": -1, "rally_z_bits": -1, "construction": 0,
		"construction_total": 0, "production_name": "", "production_queued": 0, "production_progress": 0, "production_duration": 0, "idle": false, "rank": 0}


func _with(snap: Dictionary, extra: Array) -> Dictionary:
	var out := snap.duplicate(true)
	out["entities"].append_array(extra)
	return out


func _row(rows: Array, label: String) -> Dictionary:
	for r in rows:
		if str(r.get("label", "")) == label:
			return r
	return {}


func _button(buttons: Array, label: String) -> Dictionary:
	for b in buttons:
		if str(b.get("label", "")) == label:
			return b
	return {}


# ------------------------------------------------------------------ structure panel (board 4)

func _barracks(snap: Dictionary, id := 50, col := 9, row := 9) -> Dictionary:
	var b := _entity(id, "Barracks", "building", col, row, 480, 480)
	b["production_name"] = "Infantry"
	b["production_queued"] = 2
	b["production_progress"] = 342
	b["production_duration"] = 540
	snap["services"].append({"id": id, "power": 1000, "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false})
	return b


func test_structure_carries_real_health_state_and_queue(t) -> void:
	var snap := _snap()
	var b := _barracks(snap)
	snap = _with(snap, [b])
	# The start base's own Barracks (id 7) is removed so the test's barracks is the only one.
	snap["entities"] = snap["entities"].filter(func(e): return int(e["id"]) != 7)
	var s := VM.structure(snap, GroundModel.from_snapshot(snap), 50)
	t.eq(s["kind"], "Barracks", "the entity's kind")
	t.eq(s["name"], "Barracks", "a lone barracks is not numbered")
	t.eq(s["hp"]["now"], 480, "health from hp_bits")
	t.eq(s["hp"]["max"], 480, "max from max_hp_bits")
	t.eq(s["tag"]["text"], "Online", "a powered, healthy, finished building is online")
	t.eq(s["tag"]["tone"], "good", "good tone")
	t.eq(_row(s["rows"], "Output")["value"], "1 unit / 18 s", "540 ticks at 30 per second")
	var q: Dictionary = s["queue"]
	t.eq(q["cells"].size(), 1, "one running job")
	t.eq(q["cells"][0]["name"], "Riflemen", "the unit's display name")
	t.near(q["cells"][0]["ratio"], 342.0 / 540.0, 0.001, "progress ratio from the snapshot")
	t.eq(q["cells"][0]["note"], "0:07", "198 ticks left is 7 s")
	t.eq(q["queued"], 2, "queued count is the only thing the snapshot says about the rest")
	t.ok(not s.has("terrain"), "a producer shows the queue, not the terrain column")


func test_structure_numbers_buildings_of_the_same_kind_in_entity_order(t) -> void:
	var snap := _snap()
	var a := _barracks(snap, 50, 9, 9)
	var b := _barracks(snap, 51, 9, 11)
	snap = _with(snap, [a, b])
	var ground := GroundModel.from_snapshot(snap)
	# The start base already holds a Barracks (id 7), first in entity order.
	t.eq(VM.structure(snap, ground, 7)["name"], "Barracks 1", "the start barracks is first of three")
	t.eq(VM.structure(snap, ground, 50)["name"], "Barracks 2", "second of three")
	t.eq(VM.structure(snap, ground, 51)["name"], "Barracks 3", "third of three")


func test_structure_tag_follows_health_power_and_construction(t) -> void:
	var snap := _snap()
	var hurt := _entity(60, "GunTurret", "building", 12, 9, 128, 320)
	var dim := _entity(61, "GunTurret", "building", 12, 11, 320, 320)
	var site := _entity(62, "GunTurret", "building", 12, 13, 160, 320)
	site["construction"] = 100
	site["construction_total"] = 400
	snap = _with(snap, [hurt, dim, site])
	snap["services"].append({"id": 61, "power": 300, "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false})
	var ground := GroundModel.from_snapshot(snap)
	var s := VM.structure(snap, ground, 60)
	t.eq(s["tag"], {"text": "Critical", "tone": "bad"}, "40 percent health is critical")
	t.eq(s["hp"]["tone"], "bad", "bar tone follows")
	t.eq(VM.structure(snap, ground, 61)["tag"], {"text": "Underpowered", "tone": "warn"}, "power service under 500 of 1000")
	var building := VM.structure(snap, ground, 62)
	t.eq(building["tag"], {"text": "Under construction", "tone": "cyan"}, "construction remaining")
	t.eq(_row(building["rows"], "Construction")["value"], "75%", "done share of construction_total")
	t.ok(_button(building["buttons"], "Set rally").is_empty(), "no rally while it is a foundation")


func test_non_producer_gets_the_terrain_column_from_the_ground_table(t) -> void:
	var snap := _snap()
	snap = _with(snap, [_entity(60, "GunTurret", "building", 17, 9, 128, 320)])
	var s := VM.structure(snap, GroundModel.from_snapshot(snap), 60)
	t.ok(not s.has("queue"), "a turret has no production queue")
	var tr: Dictionary = s["terrain"]
	t.eq(tr["title"], "Grassland", "ground name under the building")
	t.ok(str(tr["sub"]).begins_with("Tile 17,9"), "the tile")
	t.ok(_row(tr["rows"], "Movement")["value"].contains("100%"), "movement from the ground table")
	t.eq(_row(tr["rows"], "Cover")["value"], "None, open ground", "grass gives no cover")


func test_structure_buttons_hide_what_has_no_command(t) -> void:
	var snap := _snap()
	snap = _with(snap, [_barracks(snap, 50), _entity(60, "GunTurret", "building", 12, 9)])
	var ground := GroundModel.from_snapshot(snap)
	var barracks: Array = VM.structure(snap, ground, 50)["buttons"]
	t.eq(barracks.map(func(b): return b["label"]), ["Set rally", "Repair", "Focus building", "Demolish"], "no Cancel last: the sim has no cancel command")
	t.eq(_button(barracks, "Set rally")["action"], "set_rally", "arms the rally click")
	t.eq(_button(barracks, "Repair")["arg"], "repair", "repair order")
	t.eq(_button(barracks, "Demolish")["arg"], "sell", "demolish is the sell command")
	t.eq(_button(barracks, "Focus building")["arg"], "focus", "focus order")
	var turret: Array = VM.structure(snap, ground, 60)["buttons"]
	t.ok(_button(turret, "Set rally").is_empty(), "a turret has no rally")
	var hq: Array = VM.structure(snap, ground, 0)["buttons"]
	t.ok(_button(hq, "Demolish").is_empty(), "the sim refuses to sell the HQ, so no button")


func test_rally_row_names_the_ground_at_the_rally_point(t) -> void:
	var snap := _snap()
	var b := _barracks(snap)
	var at := _bits(17, 9)
	b["rally_x_bits"] = at[0]
	b["rally_z_bits"] = at[1]
	snap = _with(snap, [b])
	var s := VM.structure(snap, GroundModel.from_snapshot(snap), 50)
	t.eq(_row(s["rows"], "Rally")["value"], "Grassland", "the tile name at the rally point")
	var none := _snap()
	none = _with(none, [_barracks(none)])
	t.eq(_row(VM.structure(none, GroundModel.from_snapshot(none), 50)["rows"], "Rally")["value"], "Not set", "no rally yet")


func test_structure_is_empty_for_units_aliens_and_unknown_ids(t) -> void:
	var snap := _snap()
	var ground := GroundModel.from_snapshot(snap)
	t.eq(VM.structure(snap, ground, 1), {}, "an infantry unit is not a structure")
	t.eq(VM.structure(snap, ground, 14), {}, "alien buildings get no controls (14 is the alien Barracks)")
	t.eq(VM.structure(snap, ground, 999), {}, "unknown id")
	t.eq(VM.structure(snap, null, 0).get("terrain", {}), {}, "without a ground model the terrain column is left out")


func test_site_card_measures_distance_and_direction_to_forest_and_ford(t) -> void:
	var snap := _snap()
	snap = _with(snap, [_barracks(snap)])
	var ground := GroundModel.from_snapshot(snap)
	var site := VM.site_card(snap, ground, 50)
	t.eq(site["cap"], "Barracks 2 site", "caption names the structure, numbered after the start base's Barracks 7")
	t.eq(_row(site["rows"], "Terrain")["value"], "Grassland", "ground under it")
	var ford := _row(site["rows"], "Ford")
	t.ok(ford["value"].contains("tiles") and ford["value"].contains("E"), "the ford is east of the base, with a tile count")
	var d := int(str(ford["value"]).split(" ")[0])
	var best := 999
	for y in ground.height:
		for x in ground.width:
			if ground.name_at(x, y) == "Ford":
				best = mini(best, VM.hex_distance(9, 9, x, y))
	t.eq(d, best, "distance is the real hex distance to the nearest Ford tile")
	t.eq(VM.site_card(snap, ground, 999), {}, "unknown id builds nothing")
	t.eq(VM.site_card(snap, null, 50), {}, "no ground model, no card")


# ------------------------------------------------------------------ roster (board 5)

func test_roster_has_one_card_per_unit_with_real_hp_and_rank(t) -> void:
	var snap := _snap()
	var tank := _entity(70, "Tank", "unit", 9, 9, 74, 100)
	tank["rank"] = 2
	var at := _entity(71, "AntiArmor", "unit", 9, 10, 41, 100)
	snap = _with(snap, [tank, at])
	var r := VM.roster(snap, GroundModel.from_snapshot(snap), [70, 71], true, VM.veterans(snap))
	t.eq(r["count"], "2 units", "unit count")
	t.eq(r["title"], "Strike group", "more than one unit is a group")
	t.ok(r["armed"], "armed flag passes through")
	t.eq(r["cards"].size(), 2, "one card per unit")
	t.eq(r["cards"][0]["name"], "Battle tank", "display name")
	t.near(r["cards"][0]["ratio"], 0.74, 0.001, "hp_bits over max_hp_bits")
	t.eq(r["cards"][0]["rank"], 2, "rank from the veterans slice")
	t.eq(r["cards"][1]["rank"], 0, "no rank, no chevrons")
	t.eq(r["cards"][1]["tone"], "bad", "41 percent is a bad bar")


func test_roster_names_a_lone_unit_and_reports_the_ground_under_the_group(t) -> void:
	var snap := _snap()
	snap = _with(snap, [_entity(70, "Tank", "unit", 9, 9)])
	var r := VM.roster(snap, GroundModel.from_snapshot(snap), [70], false, {})
	t.eq(r["title"], "Battle tank", "a single unit keeps its own name")
	t.eq(r["count"], "1 unit", "singular")
	t.ok(not r["armed"], "not armed")
	t.eq(r["standing"], "Grassland", "the ground the group stands on")
	t.eq(r["speed"], "speed 1.0x", "vehicle speed on grass from the ground table")


func test_roster_caps_cards_and_ignores_non_human_or_missing_ids(t) -> void:
	var snap := _snap()
	var extra: Array = []
	for i in 15:
		extra.append(_entity(100 + i, "Infantry", "unit", 9, 5 + i))
	extra.append(_entity(200, "Infantry", "unit", 30, 8, 100, 100, 1))
	snap = _with(snap, extra)
	var ids: Array = range(100, 115)
	ids.append(200)
	ids.append(999)
	var r := VM.roster(snap, GroundModel.from_snapshot(snap), ids, true, {})
	t.eq(r["count"], "15 units", "only the player's real units count")
	t.eq(r["cards"].size(), VM.ROSTER_MAX, "cards are capped")
	t.eq(r["more"], 15 - VM.ROSTER_MAX, "the rest is a count")
	t.eq(VM.roster(snap, GroundModel.from_snapshot(snap), [200], true, {}), {}, "an alien unit is not a roster")
	t.eq(VM.roster(snap, GroundModel.from_snapshot(snap), [], true, {}), {}, "nothing selected")


# ------------------------------------------------------------------ wave panel (board 7)

func test_wave_panel_reads_the_real_wave(t) -> void:
	var snap := _snap()
	snap["next_wave_ticks"] = 1350
	snap["waves_survived"] = 1
	var w := VM.wave_panel(snap, GroundModel.from_snapshot(snap))
	t.eq(w["cap"], "Wave 02", "waves survived plus one")
	t.eq(_row(w["rows"], "Next wave")["value"], "00:45", "1350 ticks at 30 per second")
	t.eq(_row(w["rows"], "Expected")["value"], "10 units", "next_expedition_size")
	t.eq(_row(w["rows"], "Doctrine")["value"], "Mixed expedition", "incoming doctrine from the snapshot")
	t.eq(_row(w["rows"], "Direction")["value"], "From the east", "the route starts east of the base")
	t.ok(_row(w["rows"], "Crosses")["value"].contains("Wyllow Ford"), "the route wades the named ford")
	t.ok(_row(w["rows"], "Crosses")["value"].contains("The Dry Flats"), "and starts on the flats")
	t.eq(w["title"], "Fortify Wyllow Ford", "the route wades the ford three hexes before it enters the zone")
	t.ok(not w.has("hostiles"), "no remaining-hostile count exists in the snapshot")


func test_wave_panel_is_only_for_the_inbound_window(t) -> void:
	var snap := _snap()
	snap["next_wave_ticks"] = VM.WAVE_PANEL_WINDOW + 1
	t.eq(VM.wave_panel(snap, GroundModel.from_snapshot(snap)), {}, "too early")
	snap["next_wave_ticks"] = -1
	t.eq(VM.wave_panel(snap, GroundModel.from_snapshot(snap)), {}, "no timer")
	snap["next_wave_ticks"] = 0
	t.ok(not VM.wave_panel(snap, GroundModel.from_snapshot(snap)).is_empty(), "the moment it arrives still counts")


func test_wave_panel_without_a_route_keeps_only_what_the_timer_and_doctrine_say(t) -> void:
	var snap := _snap()
	snap["next_wave_ticks"] = 900
	snap["wave_route"] = []
	var w := VM.wave_panel(snap, GroundModel.from_snapshot(snap))
	t.ok(_row(w["rows"], "Direction").is_empty(), "no route, no direction")
	t.ok(_row(w["rows"], "Crosses").is_empty(), "no route, no crossings")
	t.eq(w["title"], "Mixed expedition", "title falls back to the doctrine")
	t.eq(_row(w["rows"], "Next wave")["value"], "00:30", "timer stays")


func test_wave_panel_title_names_the_tile_when_no_region_matches(t) -> void:
	var snap := _snap()
	snap["next_wave_ticks"] = 900
	snap["regions"] = []
	var w := VM.wave_panel(snap, GroundModel.from_snapshot(snap))
	t.eq(w["title"], "Fortify tile 21,10", "the last hex outside the zone, no region names")


# ------------------------------------------------------------------ control groups (board 5)

func test_control_group_rows_count_units_and_name_the_main_kind(t) -> void:
	var groups := [
		{"n": 1, "kinds": ["Tank", "Tank", "Infantry"]},
		{"n": 2, "kinds": []},
		{"n": 3, "kinds": ["Harvester", "Harvester"]},
	]
	var c := VM.control_groups(groups, 1)
	t.eq(c["slots"].size(), 4, "the four bound slots are listed")
	t.eq(c["slots"][0], {"n": 1, "count": 3, "label": "Battle tank", "on": true}, "slot 1: three units, mostly tanks, selected")
	t.eq(c["slots"][1], {"n": 2, "count": 0, "label": "", "on": false}, "an empty slot stays empty")
	t.eq(c["slots"][2]["label"], "Harvester", "harvesters")
	t.eq(c["slots"][3]["count"], 0, "slot 4 was never assigned")


func test_control_groups_absent_when_none_has_units(t) -> void:
	t.eq(VM.control_groups([], -1), {}, "no groups")
	t.eq(VM.control_groups([{"n": 1, "kinds": []}], -1), {}, "an emptied group is not a panel")


# ------------------------------------------------------------------ world marks feed (pure functions)

func test_rally_marks_follow_the_real_rally_point(t) -> void:
	var snap := _snap()
	var b := _barracks(snap)
	var at := _bits(17, 9)
	b["rally_x_bits"] = at[0]
	b["rally_z_bits"] = at[1]
	snap = _with(snap, [b])
	var m := VM.rally_hexes(snap, 50)
	t.eq(m, {"from": [9, 9], "to": [17, 9]}, "building hex and rally hex")
	var none := _snap()
	none = _with(none, [_barracks(none)])
	t.eq(VM.rally_hexes(none, 50), {}, "no rally set, no flag")
	t.eq(VM.rally_hexes(snap, 0), {}, "the HQ has none")


func test_wave_route_marks_are_the_snapshot_route_sampled(t) -> void:
	var snap := _snap()
	var arrows := VM.wave_arrows(snap)
	t.ok(arrows.size() >= 1, "a route yields at least one arrow")
	var route: Array = snap["wave_route"].map(func(c): return [int(c[0]), int(c[1])])
	t.eq(arrows[0]["from"], route[0], "the first arrow starts at the route's first hex")
	t.eq(arrows[arrows.size() - 1]["to"], route[route.size() - 1], "the last arrow ends at the route's last hex")
	snap["wave_route"] = []
	t.eq(VM.wave_arrows(snap), [], "no route, no arrows")


func test_turret_fields_are_human_turrets_with_the_sim_range(t) -> void:
	var snap := _snap()
	snap = _with(snap, [_entity(60, "GunTurret", "building", 12, 9), _entity(61, "AaTurret", "building", 12, 11), _entity(62, "Barracks", "building", 14, 9)])
	var fields := VM.turret_fields(snap)
	t.eq(fields.size(), 2, "the two player turrets, not the barracks or the alien turrets")
	t.eq(fields[0], {"id": 60, "cell": [12, 9], "range": VM.GUN_TURRET_RANGE, "kind": "GunTurret"}, "gun turret with its sim range")
	t.eq(fields[1]["range"], VM.AA_TURRET_RANGE, "AA range")


## The turret ranges the world rings use are the sim's: parsed from stats.rs (the third Fixed argument of the AttackProfile).
func test_turret_ranges_match_the_sim_source(t) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/stats.rs"), FileAccess.READ)
	t.ok(f != null, "stats.rs is reachable from the project")
	if f == null:
		return
	var src := f.get_as_text()
	var re := RegEx.create_from_string("Self::(GunTurret|AaTurret) => BuildingStats \\{\\s*attack: Some\\(AttackProfile::\\w+\\(\\s*Fixed::from_int\\(\\d+\\),\\s*DamageType::\\w+,\\s*Fixed::from_int\\((\\d+)\\)")
	var found := {}
	for m in re.search_all(src):
		found[m.get_string(1)] = int(m.get_string(2))
	t.eq(found.get("GunTurret", -1), VM.GUN_TURRET_RANGE, "gun turret range")
	t.eq(found.get("AaTurret", -1), VM.AA_TURRET_RANGE, "AA turret range")
