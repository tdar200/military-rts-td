extends RefCounted
## overlay_feed.gd: the Logistics lenses as world marks. Entities use the bridge's real keys (owner, category, kind, x_bits,
## z_bits, construction, river_kw, ore_bonus); per-building delivered power is services[].power (0..1000) keyed by entity id.
const Feed := preload("res://scripts/world/overlay_feed.gd")
const VM := preload("res://scripts/ui/vm_gameplay.gd")


func _kestrel() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _bits(col: int, row: int) -> Array:
	var sx := col * 0.75 + 0.5
	var sz := row + 0.5 + (0.5 if col % 2 != 0 else 0.0)
	return [int(sx * 65536.0), int(sz * 65536.0)]


func _ent(id: int, kind: String, col: int, row: int, extra := {}) -> Dictionary:
	var b := _bits(col, row)
	var e := {"id": id, "owner": 0, "category": "building", "kind": kind, "x_bits": b[0], "z_bits": b[1], "construction": 0}
	e.merge(extra, true)
	return e


func _svc(id: int, power: int) -> Dictionary:
	return {"id": id, "power": power, "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false}


func _snap(entities: Array, services := []) -> Dictionary:
	return {"entities": entities, "services": services, "map_width": 44, "map_height": 26}


func _count(marks: Array, kind: String) -> int:
	var n := 0
	for m in marks:
		if str(m.get("kind", "")) == kind:
			n += 1
	return n


# ---- the three normative assertions, in the bridge's real shape

func test_power_lens_marks_broken_links_under_five_hundred(t) -> void:
	var snap := _snap([_ent(1, "PowerPlant", 5, 5), _ent(2, "Barracks", 7, 5)], [_svc(1, 1000), _svc(2, 300)])
	var marks: Array = Feed.marks(snap, "power")
	var broken := 0
	for m in marks:
		if bool(m.get("broken", false)):
			broken += 1
	t.ok(broken == 1, "the 300/1000 consumer gets a broken link")
	t.eq(_count(marks, "link"), 1, "one link, plant to barracks")


func test_no_power_plants_gives_no_marks(t) -> void:
	t.ok(Feed.marks({"entities": []}, "power").is_empty(), "nothing to link")
	t.ok(Feed.marks(_snap([_ent(2, "Barracks", 7, 5)], [_svc(2, 1000)]), "power").is_empty(), "consumers but no plant or battery: no links")
	t.ok(Feed.marks(_snap([_ent(1, "PowerPlant", 5, 5)], [_svc(1, 1000)]), "power").is_empty(), "a plant with nothing to power: no links")


func test_river_badge_only_when_real(t) -> void:
	var with_b := Feed.marks(_snap([_ent(1, "PowerPlant", 1, 1, {"river_kw": 12})]), "yield")
	var without := Feed.marks(_snap([_ent(1, "PowerPlant", 1, 1, {"river_kw": 0})]), "yield")
	t.ok(with_b.size() > without.size(), "badge appears only with river_kw > 0")
	t.eq(with_b[0]["text"], "river +12", "the badge carries the real river_kw")
	var other := Feed.marks(_snap([_ent(1, "PowerPlant", 1, 1, {"river_kw": 7})]), "yield")
	t.eq(other[0]["text"], "river +7", "not a literal 12")


# ---- power lens

func test_power_colour_follows_delivered_power(t) -> void:
	var snap := _snap([_ent(1, "PowerPlant", 5, 5), _ent(2, "Refinery", 7, 5), _ent(3, "Barracks", 8, 6), _ent(4, "ResearchLab", 9, 5)],
		[_svc(1, 1000), _svc(2, 1000), _svc(3, 640), _svc(4, 499)])
	var by_to := {}
	for m in Feed.marks(snap, "power"):
		by_to[int(m["to_id"])] = m
	t.eq(by_to[2]["tone"], "ok", "1000 is full delivery")
	t.eq(by_to[3]["tone"], "warn", "500..999 is throttled")
	t.ok(not bool(by_to[3].get("broken", false)), "640 is not broken")
	t.eq(by_to[4]["tone"], "bad", "under 500 is broken")
	t.eq(by_to[4]["broken"], true, "499 is broken")
	t.eq(by_to[3]["load"], 640, "load is the real power_fraction")


func test_power_links_run_in_tier_order_then_id(t) -> void:
	# tiers: turret 0, refinery 1, barracks 2, lab 3
	var snap := _snap([_ent(1, "PowerPlant", 5, 5), _ent(10, "ResearchLab", 6, 5), _ent(11, "Barracks", 7, 5), _ent(12, "Refinery", 8, 5),
		_ent(13, "GunTurret", 9, 5), _ent(14, "GunTurret", 9, 6)], [_svc(1, 1000), _svc(10, 1000), _svc(11, 1000), _svc(12, 1000), _svc(13, 1000), _svc(14, 1000)])
	var order: Array = []
	for m in Feed.marks(snap, "power"):
		order.append(int(m["to_id"]))
	t.eq(order, [13, 14, 12, 11, 10], "defence, refinery, factories, lab; ids ascending inside a tier")


func test_each_consumer_links_to_its_nearest_source(t) -> void:
	var snap := _snap([_ent(1, "PowerPlant", 2, 5), _ent(2, "Battery", 20, 5), _ent(3, "GunTurret", 4, 5), _ent(4, "GunTurret", 18, 5)],
		[_svc(3, 1000), _svc(4, 1000)])
	var from_of := {}
	for m in Feed.marks(snap, "power"):
		from_of[int(m["to_id"])] = int(m["from_id"])
	t.eq(from_of[3], 1, "the west turret hangs off the plant")
	t.eq(from_of[4], 2, "the east turret hangs off the battery")


func test_power_lens_ignores_enemy_buildings_and_unfinished_sources_and_missing_service(t) -> void:
	var snap := _snap([_ent(1, "PowerPlant", 5, 5, {"owner": 1}), _ent(2, "PowerPlant", 6, 5, {"construction": 40}), _ent(3, "Barracks", 7, 5)], [_svc(3, 1000)])
	t.ok(Feed.marks(snap, "power").is_empty(), "enemy plant and a plant still under construction are not sources")
	var snap2 := _snap([_ent(1, "PowerPlant", 5, 5), _ent(3, "Barracks", 7, 5)], [_svc(1, 1000)])
	t.ok(Feed.marks(snap2, "power").is_empty(), "no service row means no delivered power to draw: no fake zero")


func test_tier_table_matches_the_sim_source(t) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/earthfront.rs"), FileAccess.READ)
	t.ok(f != null, "earthfront.rs is reachable")
	if f == null:
		return
	var src := f.get_as_text()
	for needle in ["Kind::Building(BuildingKind::ResearchLab) => priority == 3", "Kind::Building(BuildingKind::Refinery) => priority == 1",
			"BuildingKind::Barracks", "BuildingKind::VehicleFactory", "BuildingKind::Airfield", ") => priority == 2", "_ => priority == 0",
			"BuildingKind::GunTurret | BuildingKind::AaTurret) => 8", "Kind::Building(BuildingKind::SupplyDepot) => 5", "e.power_fraction < 500"]:
		t.ok(src.contains(needle), "earthfront.rs still has: " + needle)
	t.eq(Feed.TIER["ResearchLab"], 3, "lab tier")
	t.eq(Feed.TIER["Refinery"], 1, "refinery tier")
	t.eq(Feed.TIER["Barracks"], 2, "factory tier")
	t.eq(Feed.TIER["GunTurret"], 0, "defence tier")
	t.eq(Feed.BROKEN_BELOW, 500, "the sim's working threshold")


# ---- coverage

func test_coverage_rings_use_the_real_turret_range_and_highland_bonus(t) -> void:
	var snap := _kestrel()
	snap["entities"] = [_ent(60, "GunTurret", 12, 9), _ent(61, "AaTurret", 30, 4), _ent(62, "Barracks", 14, 9)]
	var marks: Array = Feed.marks(snap, "coverage")
	t.eq(_count(marks, "ring"), 2, "one ring per turret, none for the barracks")
	var gun: Dictionary = marks[0]
	t.near(float(gun["r"]), float(VM.GUN_TURRET_RANGE), 0.001, "gun turret on flat ground: the sim range")
	var ground = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	var pct := int(ground.props_at(30, 4).get("range_pct", 0))
	t.eq(pct, 25, "(30,4) is Highland in the Kestrel ground table")
	var aa: Dictionary = marks[1]
	t.near(float(aa["r"]), float(VM.AA_TURRET_RANGE) * 1.25, 0.001, "AA turret on Highland: +25% from ground_table range_pct")
	var badges := marks.filter(func(m): return m["kind"] == "badge")
	t.eq(badges.size(), 1, "only the Highland turret wears a badge")
	t.eq(badges[0]["text"], "+25%", "the real range_pct")


func test_coverage_ignores_enemy_unfinished_and_without_ground_table(t) -> void:
	var snap := _kestrel()
	snap["entities"] = [_ent(60, "GunTurret", 12, 9, {"owner": 1}), _ent(61, "GunTurret", 13, 9, {"construction": 20})]
	t.ok(Feed.marks(snap, "coverage").is_empty(), "enemy and unfinished turrets have no field of fire yet")
	t.ok(Feed.marks(_snap([_ent(60, "GunTurret", 12, 9)]), "coverage").size() == 1, "no ground table: the base range, no bonus")


# ---- yield

func test_yield_ring_for_every_refinery_badge_only_with_the_ore_bonus_flag(t) -> void:
	var snap := _snap([_ent(1, "Refinery", 10, 5, {"ore_bonus": true}), _ent(2, "Refinery", 14, 5, {"ore_bonus": false}), _ent(3, "Barracks", 3, 3)])
	var marks: Array = Feed.marks(snap, "yield")
	t.eq(_count(marks, "ring"), 2, "a ring around each refinery")
	for m in marks:
		if m["kind"] == "ring":
			t.near(float(m["r"]), 1.0, 0.001, "radius 1 hex")
	var badges := marks.filter(func(m): return m["kind"] == "badge")
	t.eq(badges.size(), 1, "one ore-bonus badge")
	t.eq(badges[0]["text"], "+20%", "the sim's ore bonus")
	t.eq(badges[0]["cell"], [10, 5], "on the flagged refinery")


func test_yield_with_nothing_builds_nothing(t) -> void:
	t.ok(Feed.marks(_snap([_ent(3, "Barracks", 3, 3)]), "yield").is_empty(), "no refinery or plant, no marks")
	t.ok(Feed.marks({}, "yield").is_empty(), "no entities key")


# ---- borders

func test_borders_outline_the_construction_zone_and_label_enemy_territory(t) -> void:
	var snap := _kestrel()
	var marks: Array = Feed.marks(snap, "borders")
	var own := marks.filter(func(m): return m["kind"] == "border" and m["tone"] == "own")
	var enemy := marks.filter(func(m): return m["kind"] == "border" and m["tone"] == "enemy")
	t.eq(own.size(), 1, "one player border")
	t.eq(enemy.size(), 1, "one enemy border")
	t.ok((own[0]["edges"] as Array).size() > 0, "player border has edges")
	var zone := {}
	for c in snap["construction_zone"]:
		zone[Vector2i(int(c[0]), int(c[1]))] = true
	for e in own[0]["edges"]:
		t.ok(zone.has(Vector2i(int(e[0][0]), int(e[0][1]))) and not zone.has(Vector2i(int(e[1][0]), int(e[1][1]))), "each edge separates zone from outside")
	var labels := marks.filter(func(m): return m["kind"] == "callout")
	t.eq(labels.size(), 1, "one label")
	t.eq(labels[0]["title"], "Enemy territory", "enemy border is labelled")
	var border_cells := VM.enemy_border(snap)
	t.ok(border_cells.has(labels[0]["cell"]), "the label sits on enemy territory")


func test_borders_without_data_build_nothing(t) -> void:
	t.ok(Feed.marks({"entities": []}, "borders").is_empty(), "no zone, no enemy anchors, no marks")


func test_a_single_cell_has_six_edges(t) -> void:
	var snap := {"entities": [], "construction_zone": [[5, 5]], "map_width": 44, "map_height": 26}
	var own: Array = Feed.marks(snap, "borders")
	t.eq((own[0]["edges"] as Array).size(), 6, "a hexagon has six sides")
	snap["construction_zone"] = [[0, 0]]
	t.eq((Feed.marks(snap, "borders")[0]["edges"] as Array).size(), 2, "the map edge is not a border: a corner cell keeps only its in-map sides")


# ---- supply and unknown lenses

func test_supply_and_unknown_lenses_have_no_data(t) -> void:
	var snap := _kestrel()
	t.eq(Feed.marks(snap, "supply"), [], "the bridge exposes no supply route, so none is drawn")
	t.eq(Feed.marks(snap, ""), [], "off")
	t.eq(Feed.marks(snap, "nonsense"), [], "unknown lens")
	t.ok(not Feed.available(snap).has("supply"), "no supply button")
	var avail: Array = Feed.available(snap)
	for want in ["power", "borders", "coverage", "yield"]:
		t.ok(avail.has(want), "lens available on the Kestrel snapshot: " + want)
	t.eq(Feed.available({}), [], "an empty snapshot backs no lens")


func test_logistics_tab_needs_the_ground_layer(t) -> void:
	t.ok(Feed.tab_available(_kestrel()), "Earthfront snapshot carries ground")
	t.ok(not Feed.tab_available({"entities": []}), "no ground, no tab")
	t.ok(not Feed.tab_available({}), "empty")


# ---- projection

func _proj(x: int, y: int) -> Vector2:
	return Vector2(x * 36.0, y * 48.0 + (24.0 if x % 2 != 0 else 0.0))


func test_project_turns_hex_marks_into_world_marks_schema(t) -> void:
	var hex := [
		{"kind": "ring", "cell": [10, 4], "r": 5.0, "dashed": true, "tone": "cyan"},
		{"kind": "link", "cell": [2, 2], "to_cell": [6, 2], "tone": "warn", "broken": false, "load": 640},
		{"kind": "badge", "cell": [10, 4], "text": "+25%"},
	]
	var out: Array = Feed.project(hex, _proj)
	t.eq(out.size(), 3, "every mark projects")
	var ring: Dictionary = out[0]
	t.near(float(ring["x"]), 360.0, 0.01, "ring centre x")
	t.near(float(ring["y"]), 192.0, 0.01, "ring centre y")
	t.near(float(ring["rx"]), 5.0 * 48.0, 0.01, "rx: sim units times the screen size of one unit across")
	t.near(float(ring["ry"]), 5.0 * 48.0, 0.01, "ry: one row is one sim unit down")
	t.eq(ring["dashed"], true, "style rides along")
	var link: Dictionary = out[1]
	t.near(float(link["x"]), 72.0, 0.01, "link start x")
	t.eq(link["to"], _proj(6, 2), "link end")
	t.eq(link["tone"], "warn", "tone rides along")
	t.near(float(link["width"]), 2.0 + 4.0 * 0.64, 0.01, "line weight follows the delivered fraction")
	t.eq(out[2]["text"], "+25%", "badge text")


func test_project_drops_marks_behind_the_camera(t) -> void:
	var behind := func(x: int, y: int) -> Vector2: return Vector2.INF if x > 5 else Vector2(x * 10.0, y * 10.0)
	var hex := [{"kind": "ring", "cell": [8, 4], "r": 3.0}, {"kind": "link", "cell": [2, 2], "to_cell": [8, 2], "tone": "ok"},
		{"kind": "ring", "cell": [1, 1], "r": 2.0}]
	var out: Array = Feed.project(hex, behind)
	t.eq(out.size(), 1, "only the mark fully in front of the camera survives")


func test_project_border_edges_become_short_segments(t) -> void:
	var hex := [{"kind": "border", "tone": "own", "edges": [[[5, 5], [6, 5]]]}]
	var out: Array = Feed.project(hex, _proj)
	t.eq(out.size(), 1, "one border mark")
	var segs: Array = out[0]["segs"]
	t.eq(segs.size(), 1, "one segment per edge")
	var a: Vector2 = segs[0][0]
	var b: Vector2 = segs[0][1]
	var mid := (a + b) * 0.5
	var want := (_proj(5, 5) + _proj(6, 5)) * 0.5
	t.near(mid.x, want.x, 0.01, "the segment is centred between the two cells")
	t.near(mid.y, want.y, 0.01, "centred in y too")
	var d := _proj(6, 5) - _proj(5, 5)
	t.near((b - a).dot(d), 0.0, 0.01, "and runs across the line joining the centres")
	t.near((b - a).length(), d.length() / sqrt(3.0), 0.01, "one hex side long")


func test_project_callout_sits_above_its_cell_and_points_back(t) -> void:
	var out: Array = Feed.project([{"kind": "callout", "cell": [10, 4], "title": "Enemy territory"}], _proj)
	t.eq(out.size(), 1, "callout")
	var c: Dictionary = out[0]
	t.eq(c["title"], "Enemy territory", "text carried")
	t.near(float(c["tx"]), _proj(10, 4).x, 0.01, "arrow target is the cell")
	t.near(float(c["ty"]), _proj(10, 4).y, 0.01, "arrow target is the cell")
	t.ok(float(c["y"]) < _proj(10, 4).y, "label floats above the cell")


# ---- legend, notes, summary

func test_summary_counts_what_is_drawn(t) -> void:
	var snap := _snap([_ent(1, "PowerPlant", 5, 5), _ent(2, "Barracks", 7, 5), _ent(3, "GunTurret", 8, 5)], [_svc(1, 1000), _svc(2, 300), _svc(3, 1000)])
	t.eq(Feed.summary(snap, "power", Feed.marks(snap, "power")), "2 links, 1 broken", "link count and broken count")
	t.eq(Feed.summary(snap, "power", []), "", "nothing drawn, no summary")
	var cov := _kestrel()
	cov["entities"] = [_ent(60, "GunTurret", 12, 9)]
	t.eq(Feed.summary(cov, "coverage", Feed.marks(cov, "coverage")), "1 turret field", "turrets drawn")


func test_legend_rows_carry_real_numbers(t) -> void:
	var snap := _kestrel()
	var rows: Array = Feed.legend(snap, "power")
	t.eq(rows.size(), 3, "ok, throttled, broken")
	t.ok(str(rows[2]["text"]).contains("500"), "broken threshold from the sim")
	var cov: Array = Feed.legend(snap, "coverage")
	var joined := ""
	for r in cov:
		joined += str(r["text"]) + "|"
	t.ok(joined.contains("Highland") and joined.contains("25"), "Highland range bonus read from ground_table")
	t.ok(str(Feed.legend(snap, "yield")[0]["text"]).length() > 0, "yield legend")
	t.eq(Feed.legend(snap, ""), [], "off has no legend")
