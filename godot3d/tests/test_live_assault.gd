extends RefCounted
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Assault = preload("res://scripts/ui/assault/assault.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const BuildDeck = preload("res://scripts/ui/build_deck.gd")
const Stub = preload("res://tests/stub_game.gd")


func _game() -> Stub:
	var g := Stub.new()
	g.add_node(1, "CommandCenter", "building", 0, Vector3(3, 0, 14), 800.0, 1000.0)
	g.add_node(2, "CommandCenter", "building", 1, Vector3(40, 0, 4), 1000.0, 1000.0)
	g.add_node(3, "Tank", "unit", 0, Vector3(10, 0, 12))
	return g


func _live(g) -> Array:
	var a := Adapter.new(g)
	return [a, a.assault]


func _hud() -> Control:
	var h := Hud.new()
	BuildDeck.register(h)
	Assault.register(h)
	return h


func test_engages_when_the_core_is_hurt_or_a_unit_is_close_and_stays_engaged(t) -> void:
	var g := _game()
	var a: Array = _live(g)
	a[1].update(0.0)
	t.ok(not a[1].engaged, "core untouched and the army far away")
	g.bridge_nodes[3].position = Vector3(33, 0, 4)  # 7 units from the core
	a[1].update(0.1)
	t.ok(a[1].engaged, "a unit within range engages")
	g.bridge_nodes[3].position = Vector3(10, 0, 12)
	a[1].update(0.2)
	t.ok(a[1].engaged, "latched once engaged")
	var g2 := _game()
	var b: Array = _live(g2)
	g2.bridge_nodes[2].set_meta("hp", 900.0)
	b[1].update(0.0)
	t.ok(b[1].engaged, "a damaged core engages")
	var g3 := Stub.new()
	var c: Array = _live(g3)
	c[1].update(0.0)
	t.ok(not c[1].engaged, "no core in play: never engaged, no error")


func test_layout_follows_the_orders_tab_only_once_engaged(t) -> void:
	var g := _game()
	var a: Array = _live(g)
	a[0].tab = "orders"
	t.ok(not a[0].hud_vm(0.0).has("as_top"), "not engaged: the main layout")
	g.bridge_nodes[2].set_meta("hp", 500.0)
	var vm: Dictionary = a[0].hud_vm(0.2)
	t.ok(vm.has("as_top") and vm.has("as_boss") and vm.has("as_bottom"), "engaged on Orders: the assault layout")
	t.ok(not vm.has("chips") and not vm.has("selection") and not vm.has("alerts") and not vm.has("map_marks"), "main keys are left out so those sections clear")
	a[0].tab = "build"
	vm = a[0].hud_vm(0.3)
	t.ok(vm.has("build_top") and not vm.has("as_top"), "the Build tab keeps the Build layout so the player can still build")
	a[0].tab = "units"
	vm = a[0].hud_vm(0.4)
	t.ok(vm.has("chips") and not vm.has("as_top"), "the Units tab keeps the main layout")


func test_numbers_and_missing_pieces(t) -> void:
	var g := _game()
	g.bridge_nodes[2].set_meta("hp", 4800.0)
	g.bridge_nodes[2].set_meta("max_hp", 12000.0)
	g.bridge_relays = 0
	g.bridge_next_wave_ticks = -1
	var a: Array = _live(g)
	a[1].update(0.0)
	var vm: Dictionary = a[1].vm(0.0, [], [], {}, false)
	t.eq(vm["as_boss"]["hp_text"], "4,800 / 12,000 HP", "thousands separators")
	t.near(vm["as_boss"]["ratio"], 0.4, 0.001, "ratio")
	t.ok(not vm["as_boss"].has("phase") and not vm["as_boss"].has("retaliation"), "no invented boss phase or timer")
	t.ok(not vm.has("as_relays"), "no relays: no relays card")
	t.eq(vm["as_top"]["right"], [], "no wave scheduled: no wave chip")
	t.ok(not vm.has("as_edge"), "HQ untouched: no edge alert")
	t.eq(vm["as_top"]["groups"][1].size(), 3, "core, HQ and ammo chips (relays and the wave are absent)")
	g.bridge_nodes.erase(2)
	vm = a[1].vm(0.0, [], [], {}, false)
	t.ok(not vm.has("as_boss"), "core destroyed: the boss bar goes")
	g.bridge_nodes.erase(1)
	vm = a[1].vm(0.0, [], [], {}, false)
	t.eq(vm["as_top"]["groups"][1].size(), 1, "no HQ and no core: only ammo")


func test_relays_follow_the_counts(t) -> void:
	var g := _game()
	g.bridge_relays = 3
	g.bridge_active_relays = 1
	var vm: Dictionary = _live(g)[1].vm(0.0, [], [], {}, false)
	var states: Array = vm["as_relays"]["items"].map(func(i): return i["state"])
	t.eq(states, ["powered", "destroyed", "destroyed"], "powered first, then destroyed")
	t.eq(vm["as_relays"]["items"][2]["name"], "Relay C", "lettered")


func test_hq_edge_alert_appears_on_damage_and_expires(t) -> void:
	var g := _game()
	var a: Array = _live(g)
	a[1].update(0.0)
	t.ok(not a[1].vm(0.0, [], [], {}, false).has("as_edge"), "healthy HQ")
	g.bridge_nodes[1].set_meta("hp", 700.0)
	a[1].update(1.0)
	var vm: Dictionary = a[1].vm(1.0, [], [], {}, false)
	t.eq(vm["as_edge"]["action"], "jump_hq", "alert jumps to the HQ")
	t.eq(vm["as_bottom"]["alerts"][0]["label"], "HQ under raid", "and is the first queue row")
	t.ok(not a[1].vm(14.0, [], [], {}, false).has("as_edge"), "expires after 12 s")
	a[0].on_action("jump_hq", null)
	t.eq(g.calls.back()[0], "focus", "jump_hq moves the camera")


func test_selection_with_none_one_and_many_units(t) -> void:
	var g := _game()
	var a: Array = _live(g)
	var vm: Dictionary = a[1].vm(0.0, [], [], {}, false)
	t.eq(vm["as_selection"]["empty_title"], "No selection", "nothing selected")
	g.selected_units = [g.bridge_nodes[3]]
	g.selected = g.bridge_nodes[3]
	a[0].tab = "orders"
	g.bridge_nodes[2].set_meta("hp", 10.0)
	vm = a[0].hud_vm(0.0)
	t.eq(vm["as_selection"]["name"], "Battle tank", "one unit")
	t.eq(vm["as_selection"]["groups"], [], "one unit: no group tiles")
	t.ok(vm["as_selection"]["stats"].size() >= 1 and vm["as_selection"]["stats"].size() <= 3, "a health bar and at most two more")
	g.add_node(4, "Infantry", "unit", 0, Vector3(11, 0, 12), 50.0, 100.0)
	g.selected_units = [g.bridge_nodes[3], g.bridge_nodes[4]]
	vm = a[0].hud_vm(0.0)
	t.eq(vm["as_selection"]["groups"].size(), 2, "two kinds, two tiles")
	var h := _hud()
	h.apply(vm)
	t.ok(h.get_node("as_selection").get_child_count() > 0, "the panel draws")
	h.free()


func test_the_assault_hud_draws_and_clears_the_main_layout(t) -> void:
	var g := _game()
	var a: Array = _live(g)
	a[0].tab = "units"
	var h := _hud()
	h.apply(a[0].hud_vm(0.0))
	t.ok(h.get_node("top_chips").get_child_count() > 0, "main layout first")
	g.bridge_nodes[2].set_meta("hp", 500.0)
	a[0].tab = "orders"
	h.apply(a[0].hud_vm(0.2))
	for key in ["as_top", "as_boss", "as_objective", "as_relays", "as_bottom", "as_selection", "as_vignette"]:
		t.ok(h.get_node(key).get_child_count() > 0, key + " drawn")
	for key in ["top_chips", "objectives", "minimap", "minimap_marks", "selection", "alerts"]:
		t.eq(h.get_node(key).get_child_count(), 0, key + " cleared")
	var tiles := h.find_children("*", "Button", true, false).filter(func(b): return b.text == "Attack-move")
	t.eq(tiles.size(), 1, "the Attack-move order tile is there for the QA driver")
	h.free()


func test_marks_only_hostiles_on_screen_and_capped(t) -> void:
	var g := _game()
	for i in 40:
		g.add_node(10 + i, "Infantry", "unit", 1, Vector3(30 + i * 0.1, 0, 5), 50.0, 100.0)
	var a: Array = _live(g)
	var project := func(p: Vector3) -> Vector2: return Vector2(p.x * 40.0, 500.0)
	var behind := func(_p: Vector3) -> bool: return false
	var out: Array = a[1].marks(project, Rect2(0, 0, 1920, 1080), behind)
	t.eq(out.size(), 24, "capped")
	t.ok(out.all(func(m): return m["kind"] == "hostile" and m["hp"] >= 0.0 and m["hp"] <= 1.0), "hostile marks with a health ratio")
	var far := func(p: Vector3) -> Vector2: return Vector2(5000.0, 500.0)
	t.eq(a[1].marks(far, Rect2(0, 0, 1920, 1080), behind), [], "off-screen marks are dropped")
	var behind_all := func(_p: Vector3) -> bool: return true
	t.eq(a[1].marks(project, Rect2(0, 0, 1920, 1080), behind_all), [], "behind the camera is dropped")
