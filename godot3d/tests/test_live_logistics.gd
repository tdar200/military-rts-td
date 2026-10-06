extends RefCounted
## live_adapter.gd wiring for board 8: when the Logistics tab shows, what its body holds, how a lens click is routed and when
## the overlay draws. Kestrel Reach's snapshot, plus entities the test adds (a reactor, a barracks at 30 percent, a refinery).
## The snapshot itself starts with a working base: Power Plant 5 fully feeding Refinery 6 (on ore, so it carries the ore
## bonus) and Barracks 7. Those add two healthy power links, one refinery ring and one +20% badge to every count below.
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Stub = preload("res://tests/stub_game.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const U = preload("res://tests/section_util.gd")


func _bits(col: int, row: int) -> Array:
	var sx := col * 0.75 + 0.5
	var sz := row + 0.5 + (0.5 if col % 2 != 0 else 0.0)
	return [int(sx * 65536.0), int(sz * 65536.0)]


func _entity(id: int, kind: String, col: int, row: int, extra := {}) -> Dictionary:
	var b := _bits(col, row)
	var e := {"id": id, "owner": 0, "category": "building", "kind": kind, "x_bits": b[0], "z_bits": b[1], "hp_bits": 100 * 65536, "max_hp_bits": 100 * 65536,
		"rally_x_bits": -1, "rally_z_bits": -1, "construction": 0, "construction_total": 0, "production_name": "", "production_queued": 0,
		"production_progress": 0, "production_duration": 0, "idle": false}
	e.merge(extra, true)
	return e


func _svc(id: int, power: int) -> Dictionary:
	return {"id": id, "power": power, "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false}


func _make() -> Array:
	var g := Stub.new()
	g.use_kestrel()
	g.bridge_snapshot["entities"].append_array([_entity(50, "PowerPlant", 9, 9, {"river_kw": 12}), _entity(51, "Barracks", 11, 9), _entity(52, "Refinery", 12, 11, {"ore_bonus": true})])
	g.bridge_snapshot["services"].append_array([_svc(50, 1000), _svc(51, 300), _svc(52, 1000)])
	g.bridge_snapshot["next_wave_ticks"] = -1
	g.bridge_next_wave_ticks = -1
	var a := Adapter.new(g)
	return [g, a]


func _tab_ids(vm: Dictionary) -> Array:
	var ids: Array = []
	for tb in vm["deck"]["tabs"]:
		ids.append(tb["id"])
	return ids


func _project(x: int, y: int) -> Vector2:
	return Vector2(x * 36.0, y * 48.0 + (24.0 if x % 2 != 0 else 0.0))


func test_logistics_tab_shows_with_ground_and_stays_hidden_without(t) -> void:
	var p := _make()
	p[1].tab = "units"
	t.eq(_tab_ids(p[1].hud_vm(0.0)), ["build", "units", "orders", "science", "logistics"], "Earthfront snapshot: the fifth tab")
	p[0].bridge_snapshot.erase("ground")
	t.eq(_tab_ids(p[1].hud_vm(0.0)), ["build", "units", "orders", "science"], "no ground layer, no Logistics tab")
	var bare := Stub.new()
	var a := Adapter.new(bare)
	a.tab = "units"
	t.eq(_tab_ids(a.hud_vm(0.0)), ["build", "units", "orders", "science"], "no snapshot at all, no tab")


func test_logistics_body_offers_only_lenses_with_data(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	var vm: Dictionary = p[1].hud_vm(0.0)
	var body: Dictionary = vm["deck"]["body"]
	t.eq(body["kind"], "logistics", "body kind")
	var ids: Array = body["lenses"].map(func(l): return l["id"])
	t.eq(ids, ["power", "borders", "coverage", "yield"], "no Supply button: the snapshot holds no supply link")
	t.eq(body["lens"], "", "no lens until one is clicked")
	t.ok(not body.has("legend"), "so no legend")
	t.eq(p[1].board_marks(_project), [], "and the map draws no overlay")


func test_a_lens_click_sets_the_lens_client_side(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "power")
	t.eq(p[1].world_lens, "power", "stored in the adapter")
	t.ok(p[0].calls.is_empty(), "no bridge command, no game call")
	var body: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.eq(body["lens"], "power", "the vm carries the active lens")
	t.eq(body["lenses"][0]["on"], true, "its button is lit")
	t.eq(body["legend"].size(), 3, "its legend")
	t.eq(body["summary"], "4 links, 1 broken", "what it draws: the start base's two healthy links plus the test's two; the barracks at 300 is broken")
	p[1].on_action("world_lens", "")
	t.eq(p[1].world_lens, "", "off")
	p[1].on_action("world_lens", "bogus")
	t.eq(p[1].world_lens, "", "an unknown lens is ignored")


func test_supply_cannot_be_activated_without_links(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "supply")
	var body: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.eq(body["lens"], "", "no data behind it, so it never goes active")
	t.eq(p[1].board_marks(_project), [], "and draws nothing")
	p[0].bridge_snapshot["supply_links"] = []
	t.eq(p[1].hud_vm(0.0)["deck"]["body"]["lens"], "", "an empty supply_links array is still no data")


func _with_links(p: Array) -> void:
	# A depot (id 53) feeds the refinery (52) and is cut off from the barracks (51).
	p[0].bridge_snapshot["entities"].append(_entity(53, "SupplyDepot", 10, 9))
	p[0].bridge_snapshot["supply_links"] = [{"depot": 53, "target": 52, "state": "ok"}, {"depot": 53, "target": 51, "state": "severed"}]


func test_supply_lens_appears_with_real_links_and_draws_them(t) -> void:
	var p := _make()
	_with_links(p)
	p[1].tab = "logistics"
	var body: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.eq(body["lenses"].map(func(l): return l["id"]), ["power", "supply", "borders", "coverage", "yield"], "Supply button between Power and Borders")
	p[1].on_action("world_lens", "supply")
	body = p[1].hud_vm(0.0)["deck"]["body"]
	t.eq(body["lens"], "supply", "active")
	t.eq(body["summary"], "1 supplied, 1 severed", "counts from the links")
	t.eq(body["routes"].size(), 1, "one depot row")
	t.eq(body["routes"][0]["name"], "Supply depot at 10, 9", "named by kind and cell")
	t.eq(body["routes"][0]["tag"], "Cut", "the depot has a severed link")
	var marks: Array = p[1].board_marks(_project)
	t.eq(marks.size(), 2, "one line per link")
	t.eq(marks.filter(func(m): return m["broken"]).size(), 1, "the severed one is dotted")


func test_lens_text_is_built_once_per_snapshot(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "borders")
	var first: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	var second: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.ok(first.has("legend") and first.has("note"), "legend and note present")
	t.ok(is_same(first["legend"], second["legend"]), "the legend is not rebuilt per frame")
	t.ok(is_same(p[1]._overlay_text, p[1]._overlay_text), "one held text dictionary")
	var held = p[1]._overlay_text
	p[1].hud_vm(0.0)
	t.ok(is_same(held, p[1]._overlay_text), "same snapshot, same text")
	p[0].bridge_snapshot = p[0].bridge_snapshot.duplicate(true)
	p[1].hud_vm(0.0)
	t.ok(not is_same(held, p[1]._overlay_text), "a new snapshot rebuilds it")
	p[1].on_action("world_lens", "power")
	p[1].hud_vm(0.0)
	t.eq(p[1]._overlay_text["summary"] if p[1]._overlay_text.has("summary") else "", p[1].hud_vm(0.0)["deck"]["body"].get("summary", ""), "and a lens change rebuilds it for the new lens")


func test_overlay_draws_only_on_the_logistics_tab_and_computes_nothing_otherwise(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	t.eq(p[1].board_marks(_project).size(), 0, "no lens: no marks")
	t.ok(p[1]._overlay_snap == null, "and nothing was computed")
	p[1].on_action("world_lens", "power")
	var marks: Array = p[1].board_marks(_project)
	t.eq(marks.size(), 4, "four power lines: the start base's refinery and barracks plus the test's two")
	t.eq(marks[0]["kind"], "link", "link marks in world_marks' schema")
	t.ok(marks[0].has("c1") and marks[0].has("to"), "a drawable curve")
	var broken := marks.filter(func(m): return m["broken"])
	t.eq(broken.size(), 1, "the 300/1000 barracks")
	p[1].tab = "units"
	t.eq(p[1].board_marks(_project), [], "leaving the tab hides the overlay")
	p[1].tab = "logistics"
	t.eq(p[1].board_marks(_project).size(), 4, "and coming back shows it again")


func test_overlay_marks_are_cached_per_snapshot(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "yield")
	p[1].board_marks(_project)
	var first = p[1]._overlay_hex
	p[1].board_marks(_project)
	t.ok(is_same(first, p[1]._overlay_hex), "same snapshot, same hex marks")
	p[0].bridge_snapshot = p[0].bridge_snapshot.duplicate(true)
	p[1].board_marks(_project)
	t.ok(not is_same(first, p[1]._overlay_hex), "a new snapshot recomputes")


func test_yield_lens_reads_real_flags(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "yield")
	var texts: Array = p[1].board_marks(_project).filter(func(m): return m["kind"] == "badge").map(func(m): return m["text"])
	texts.sort()
	t.eq(texts, ["+20%", "+20%", "river +12"], "ore bonus badges (the start refinery and the test's) and the river_kw badge")
	var body: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.ok(str(body["summary"]).contains("2 refinery rings, 2 with ore bonus") and str(body["summary"]).contains("1 river plant"), "summary " + str(body["summary"]))


func test_empty_lens_says_why(t) -> void:
	var p := _make()
	p[0].bridge_snapshot["entities"] = p[0].bridge_snapshot["entities"].filter(func(e): return e["kind"] != "GunTurret" or e["owner"] != 0)
	p[1].tab = "logistics"
	p[1].on_action("world_lens", "coverage")
	var body: Dictionary = p[1].hud_vm(0.0)["deck"]["body"]
	t.ok(not body.has("summary"), "no turret, no count")
	t.eq(body["empty"], "No finished turret yet.", "the honest empty line")


func test_real_hud_builds_the_tab_and_a_click_reaches_the_adapter(t) -> void:
	var p := _make()
	p[1].tab = "logistics"
	var hud := Hud.new()
	var calls: Array = []
	hud.action.connect(func(name, arg): calls.append([name, arg]))
	hud.apply(p[1].hud_vm(0.0))
	t.ok(U.has_text(hud, "Map lenses"), "the body drew")
	t.ok(U.button_with(hud, "Logistics") != null, "the deck tab is a Button")
	var power := U.button_with(hud, "Power")
	t.ok(power != null, "lens button")
	power.pressed.emit()
	t.eq(calls, [["world_lens", "power"]], "the click is an action")
	p[1].on_action(calls[0][0], calls[0][1])
	hud.apply(p[1].hud_vm(0.0))
	t.ok(U.has_text(hud, "Powered, full delivery"), "the legend appears once the lens is on")
	var logistics_tab := U.button_with(hud, "Logistics")
	logistics_tab.pressed.emit()
	t.eq(calls[calls.size() - 1], ["deck_tab", "logistics"], "the tab emits deck_tab")
	p[1].on_action("deck_tab", "logistics")
	t.eq(p[1].tab, "logistics", "which routes to the adapter's tab")
	hud.free()
