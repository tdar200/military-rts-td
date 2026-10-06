extends RefCounted
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Stub = preload("res://tests/stub_game.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const BuildDeck = preload("res://scripts/ui/build_deck.gd")


func _make() -> Array:
	var g := Stub.new()
	var a := Adapter.new(g)
	a.tab = "units"
	return [g, a]


func _find(items: Array, key: String, value: Variant) -> Dictionary:
	for i in items:
		if i.get(key) == value:
			return i
	return {}


func test_chips_use_live_numbers(t) -> void:
	var p := _make()
	p[0].bridge_services = {7: {"ore_capacity": 300}}
	var chips: Array = p[1].hud_vm(0.0)["chips"]
	t.eq(_find(chips, "label", "Material")["value"], "840", "material")
	t.eq(_find(chips, "label", "Ore buffer")["value"], "210 / 300", "ore against refinery capacity")
	var power := _find(chips, "label", "Power")
	t.eq(power["value"], "160 / 168 kW", "power")
	t.eq(power["state"], "warn", "deficit warns")
	t.eq(_find(chips, "label", "Battery")["value"], "62%", "battery percent")
	t.eq(_find(chips, "label", "Crew")["value"], "22 / 60", "crew")


## Kestrel: the game's bridge_services and bridge_nodes as _poll_bridge / _sync_bridge_entities fill them from `fixture`.
func _kestrel_from(fixture: String) -> Array:
	var p := _make()
	var g = p[0]
	g.world_art_on = true
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + fixture))
	g.bridge_snapshot = snap
	for s in snap["services"]:
		g.bridge_services[int(s["id"])] = s
	for e in snap["entities"]:
		var n: Node3D = g.add_node(int(e["id"]), str(e["kind"]), str(e["category"]), int(e["owner"]), Vector3.ZERO)
		n.set_meta("construction", int(e.get("construction", 0)))
	return p


func _free_nodes(g) -> void:
	for n in g.bridge_nodes.values():
		n.free()


func test_kestrel_ore_capacity_counts_only_finished_human_refineries(t) -> void:
	for fixture in ["kestrel_snapshot.json", "kestrel_snapshot_fog_off.json"]:
		var p := _kestrel_from(fixture)
		var g = p[0]
		t.ok(g.bridge_services.size() > 1, "%s: the bridge sends a service row (ore_capacity 300) for every shown entity" % fixture)
		t.eq(_find(p[1].hud_vm(0.0)["chips"], "label", "Ore buffer")["value"], "210 / 300", "%s: one Refinery's 300, not 300 per shown entity" % fixture)
		_free_nodes(g)
	var p2 := _kestrel_from("kestrel_snapshot.json")
	var g2 = p2[0]
	g2.bridge_services[50] = {"id": 50, "ore_capacity": 300}
	g2.add_node(50, "Refinery", "building", 0, Vector3.ZERO).set_meta("construction", 0)
	g2.bridge_services[51] = {"id": 51, "ore_capacity": 300}
	g2.add_node(51, "Refinery", "building", 0, Vector3.ZERO).set_meta("construction", 120)
	g2.bridge_services[52] = {"id": 52, "ore_capacity": 300}
	g2.add_node(52, "Refinery", "building", 1, Vector3.ZERO).set_meta("construction", 0)
	t.eq(_find(p2[1].hud_vm(0.0)["chips"], "label", "Ore buffer")["value"], "210 / 600", "a second finished human Refinery adds 300; a site or an alien one does not")
	g2.bridge_nodes[6].set_meta("construction", 10)
	g2.bridge_nodes[50].set_meta("construction", 10)
	t.eq(_find(p2[1].hud_vm(0.0)["chips"], "label", "Ore buffer")["value"], "210", "no finished human Refinery: the bare value")
	_free_nodes(g2)


func test_survival_ore_capacity_is_unchanged(t) -> void:
	var p := _make()
	p[0].bridge_services = {7: {"ore_capacity": 300}, 8: {"ore_capacity": 300}}
	p[0].add_node(8, "Infantry", "unit", 0, Vector3.ZERO)
	t.eq(_find(p[1].hud_vm(0.0)["chips"], "label", "Ore buffer")["value"], "210 / 600", "Survival keeps summing every service row, as before")
	_free_nodes(p[0])


func test_missing_data_hides_chips_instead_of_faking(t) -> void:
	var p := _make()
	p[0].bridge_storage_capacity = 0
	var chips: Array = p[1].hud_vm(0.0)["chips"]
	t.ok(_find(chips, "label", "Battery").is_empty(), "no battery chip without storage")
	t.ok(_find(chips, "label", "Reserved").is_empty(), "no reserved chip without a prototype")
	t.eq(_find(chips, "label", "Ore buffer")["value"], "210", "no capacity, bare value")
	p[0].bridge_services = {3: {"prototype": true}}
	t.ok(not _find(p[1].hud_vm(0.0)["chips"], "label", "Reserved").is_empty(), "reserved chip appears with a prototype")


func test_wave_chip_and_card(t) -> void:
	var p := _make()
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.eq(vm["wave"]["label"], "Wave 02 Siege", "wave label")
	t.eq(vm["wave"]["timer"], "T-00:45", "1350 ticks = 45 s")
	t.eq(vm["wave_card"]["tag"], "Doctrine committed", "committed inside 45 s")
	t.ok(vm["wave_card"]["body"].contains("14 units"), "expedition size")
	t.ok(not vm["wave_card"]["body"].contains("artillery"), "no invented composition")
	p[0].bridge_next_wave_ticks = -1
	vm = p[1].hud_vm(0.0)
	t.ok(not vm.has("wave") and not vm.has("wave_card"), "no wave data, no wave UI")
	p[0].bridge_next_wave_ticks = 5000
	vm = p[1].hud_vm(0.0)
	t.ok(vm.has("wave") and not vm.has("wave_card"), "card only inside 90 s")


func test_power_tip_only_on_deficit_and_hover_or_new(t) -> void:
	var p := _make()
	t.ok(p[1].hud_vm(0.0).has("power_tip"), "shown when the deficit starts")
	t.ok(not p[1].hud_vm(30.0).has("power_tip"), "hidden later when the pointer is away from the top bar")
	p[0].mouse = Vector2(500, 30)
	t.ok(p[1].hud_vm(31.0).has("power_tip"), "shown while hovering the top bar")
	p[0].bridge_power_generation = 200
	t.ok(not p[1].hud_vm(32.0).has("power_tip"), "no deficit, no tip")
	var tip: Dictionary = {}
	p[0].bridge_power_generation = 160
	tip = p[1].hud_vm(40.0)["power_tip"]
	t.ok(not tip.has("producers") and not tip.has("consumers"), "no invented breakdown")


func test_objectives_follow_tutorial_stage(t) -> void:
	var p := _make()
	var items: Array = p[1].hud_vm(0.0)["objectives"]["items"]
	t.eq(items[0]["state"], "done", "base done at stage 8")
	t.eq(items[3]["state"], "active", "first wave active")
	t.ok(items[3]["t"].contains("first wave in 45s"), "wave countdown in the active line")
	t.ok(not _find(items, "t", "Optional: disable alien relays (2 active)").is_empty(), "relay line from live counts")
	p[0].bridge_relays = 0
	t.eq(p[1].hud_vm(0.0)["objectives"]["items"].size(), 5, "no relay line without relays")
	p[0].tutorial_stage = -1
	items = p[1].hud_vm(0.0)["objectives"]["items"]
	t.eq(items[0]["state"], "todo", "stage -1 has nothing active")


func test_alerts_expire_and_cap(t) -> void:
	var p := _make()
	p[1].push_notification("WAVE COMMITTED", "SIEGE, 14 UNITS", Color("f04e46"), 0.0)
	var vm: Dictionary = p[1].hud_vm(1.0)
	t.eq(vm["alerts"][0]["title"], "Wave committed", "sentence case")
	t.ok(vm["alerts"][0]["hostile"], "red is hostile")
	t.ok(not p[1].hud_vm(20.0).has("alerts"), "expired after the TTL")
	for i in 5:
		p[1].push_notification("Alert %d" % i, "", Color("65e4da"), 30.0)
	t.eq(p[1].hud_vm(31.0)["alerts"].size(), 3, "at most three toasts")
	p[1].push_notification("Alert 4", "again", Color("65e4da"), 32.0)
	t.eq(p[1].hud_vm(33.0)["alerts"].size(), 3, "same title replaces itself")


func test_ticker_text_becomes_a_toast(t) -> void:
	var p := _make()
	p[1].poll_ticker("ATTACK-MOVE ARMED — RIGHT-CLICK A DESTINATION", 0.0)
	p[1].poll_ticker("ATTACK-MOVE ARMED — RIGHT-CLICK A DESTINATION", 0.1)
	var alerts: Array = p[1].hud_vm(0.2)["alerts"]
	t.eq(alerts.size(), 1, "an unchanged ticker adds nothing")
	t.eq(alerts[0]["title"], "Attack-move armed", "title")
	t.eq(alerts[0]["body"], "Right-click a destination", "body")
	t.ok(not alerts[0]["title"].contains("—") and not alerts[0]["body"].contains("—"), "no em dash reaches the screen")


func test_minimap_marks_and_view(t) -> void:
	var p := _make()
	p[0].add_node(1, "Tank", "unit", 0, Vector3(10, 0, 15))
	p[0].add_node(2, "CommandCenter", "building", 1, Vector3(30, 0, 6))
	p[0].add_node(3, "Infantry", "unit", 1, Vector3(60, 0, -9))
	var mm: Dictionary = p[1].hud_vm(0.0)["map_marks"]
	t.eq(mm["marks"][0], {"x": 0.25, "y": 0.5, "k": "f"}, "friendly mark in 0..1")
	t.eq(mm["marks"][1]["k"], "H", "hostile core is a big mark")
	t.eq(mm["marks"][2], {"x": 1.0, "y": 0.0, "k": "h"}, "out of range clamps to the rim")
	t.eq(mm["view"], {"x": 0.1, "y": 0.1, "w": 0.5, "h": 0.5}, "frustum")
	p[0].world_rect = Rect2()
	t.eq(p[1].hud_vm(0.0)["map_marks"]["marks"], [], "no map rect, no marks")


func test_no_selection_means_no_panel(t) -> void:
	var p := _make()
	t.ok(not p[1].hud_vm(0.0).has("selection"), "nothing selected")


func test_single_unit_has_no_groups(t) -> void:
	var p := _make()
	var tank: Node3D = p[0].add_node(5, "Tank", "unit", 0, Vector3.ZERO, 50.0, 100.0)
	p[0].selected_units = [tank]
	p[0].selected = tank
	p[0].bridge_services = {5: {"ammo": 45}}
	var sel: Dictionary = p[1].hud_vm(0.0)["selection"]
	t.eq(sel["name"], "Battle tank", "name")
	t.eq(sel["count"], "1 unit", "count")
	t.ok(not sel.has("groups"), "a single unit has no subgroups")
	t.eq(_find(sel["rows"], "label", "Health")["value"], "50%", "health")
	t.eq(_find(sel["rows"], "label", "Ammunition carried")["value"], "45 / 90 rounds", "ammo from the service")
	t.eq(sel["orders"].size(), 2, "attack-move and focus")


func test_group_selection_averages_and_groups(t) -> void:
	var p := _make()
	var list: Array[Node3D] = []
	for i in 4:
		list.append(p[0].add_node(10 + i, "Tank", "unit", 0, Vector3.ZERO, 80.0, 100.0))
	list.append(p[0].add_node(20, "Infantry", "unit", 0, Vector3.ZERO, 20.0, 100.0))
	list.append(p[0].add_node(21, "Harvester", "unit", 0, Vector3.ZERO, 100.0, 100.0))
	p[0].selected_units = list
	p[0].selected = list[0]
	var sel: Dictionary = p[1].hud_vm(0.0)["selection"]
	t.eq(sel["count"], "6 units", "count")
	t.eq(sel["groups"].size(), 3, "three kinds")
	var tank := _find(sel["groups"], "id", "Tank")
	t.eq(tank["label"], "TANK x4", "label")
	t.eq(tank["tone"], "good", "tank health tone")
	t.eq(_find(sel["groups"], "id", "Infantry")["tone"], "bad", "infantry nearly dead")
	t.ok(_find(sel["groups"], "id", "Harvester").has("icon"), "a kind without a sprite gets an icon")
	t.eq(_find(sel["rows"], "label", "Health, average")["value"], "73%", "mean of 4x80, 20, 100")


func test_structure_selection_rows(t) -> void:
	var p := _make()
	var ref: Node3D = p[0].add_node(8, "Refinery", "building", 0, Vector3.ZERO)
	ref.set_meta("production_name", "Harvester")
	ref.set_meta("production_progress", 30)
	ref.set_meta("production_duration", 60)
	ref.set_meta("production_queued", 2)
	p[0].selected_units = [ref]
	p[0].selected = ref
	p[0].bridge_services = {8: {"power": 1000, "ore": 120, "ore_capacity": 300}}
	var sel: Dictionary = p[1].hud_vm(0.0)["selection"]
	t.eq(sel["count"], "Structure", "structure")
	t.eq(_find(sel["rows"], "label", "Ore stored")["value"], "120 / 300", "ore")
	t.eq(_find(sel["rows"], "label", "Producing harvester")["value"], "50%", "production")
	t.eq(_find(sel["rows"], "label", "Queued")["value"], "2", "queued")
	t.eq(sel["orders"][0]["label"], "Repair", "structure orders")
	var cc: Node3D = p[0].add_node(9, "CommandCenter", "building", 0, Vector3.ZERO)
	p[0].selected_units = [cc]
	p[0].selected = cc
	t.ok(p[1].hud_vm(0.0)["selection"]["orders"][1]["disabled"], "the command center cannot be sold")


func test_units_deck_states_the_reason_a_card_is_blocked(t) -> void:
	var p := _make()
	p[1].tab = "units"
	p[0].add_node(1, "Barracks", "building", 0, Vector3.ZERO)
	var cards: Array = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.eq(_find(cards, "name", "Riflemen")["cost"], "50 / 1", "affordable")
	t.ok(not _find(cards, "name", "Riflemen").has("locked"), "enabled")
	t.eq(_find(cards, "name", "Battle tank")["cost"], "Needs vehicle factory", "no producer")
	t.eq(_find(cards, "name", "Gunship")["cost"], "Not unlocked", "not researched")
	p[0].bridge_money = 40
	cards = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.eq(_find(cards, "name", "Riflemen")["cost"], "Need 50 material", "cannot afford")
	p[0].bridge_money = 840
	p[0].bridge_supply_used = 60
	t.eq(_find(p[1].hud_vm(0.0)["deck"]["body"]["cards"], "name", "Riflemen")["cost"], "Crew full", "supply cap")
	p[0].bridge_active = false
	t.eq(_find(p[1].hud_vm(0.0)["deck"]["body"]["cards"], "name", "Riflemen")["cost"], "Not unlocked", "bridge down")


func test_actions_reach_game_handlers(t) -> void:
	var p := _make()
	p[1].on_action("train", "tank")
	p[1].on_action("order", "attack_move")
	p[1].on_action("order", "sell")
	p[1].on_action("build_power", null)
	p[1].on_action("deck_tab", "science")
	t.eq(p[0].calls, [["command", "train_tank"], ["command", "attack"], ["command", "sell"], ["command", "build_power"], ["command", "research_next"]], "routed")
	p[1].on_action("deck_tab", "units")
	t.eq(p[1].tab, "units", "tab switches without a game call")


func test_select_group_narrows_selection(t) -> void:
	var p := _make()
	var a: Node3D = p[0].add_node(1, "Tank", "unit", 0, Vector3.ZERO)
	var b: Node3D = p[0].add_node(2, "Infantry", "unit", 0, Vector3.ZERO)
	p[0].selected_units = [a, b]
	p[1].on_action("select_group", "Infantry")
	t.eq(p[0].selected_units.size(), 1, "only infantry left")
	t.eq(p[0].selected, b, "selected is the infantry")


func test_full_vm_drives_the_real_hud(t) -> void:
	var p := _make()
	var hud := Hud.new()
	var tank: Node3D = p[0].add_node(5, "Tank", "unit", 0, Vector3.ZERO, 50.0, 100.0)
	var inf: Node3D = p[0].add_node(6, "Infantry", "unit", 0, Vector3.ZERO)
	p[0].selected_units = [tank, inf]
	p[0].selected = tank
	p[1].tab = "units"
	p[1].push_notification("Power short", "factory throttled", Color("f0b040"), 0.0)
	hud.apply(p[1].hud_vm(0.5))
	t.ok(hud.get_node("selection").get_child_count() > 0, "selection drawn")
	t.ok(hud.get_node("power_tip").get_child_count() > 0, "power tip drawn")
	t.ok(hud.get_node("alerts").get_child_count() > 0, "alert drawn")
	hud.free()


func test_build_tab_switches_to_the_build_layout(t) -> void:
	var p := _make()
	p[1].tab = "build"
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("build_top") and vm.has("build_alerts") and vm.has("build_minimap"), "build sections present")
	t.ok(not vm.has("chips") and not vm.has("selection") and not vm.has("objectives"), "main sections cleared")
	t.eq(vm["deck"]["body"]["kind"], "build", "build deck body")
	t.ok(not vm["deck"].has("tabs"), "the build body draws its own tabs")
	var cards: Array = vm["deck"]["body"]["cards"]
	t.eq(cards.size(), 11, "every structure the game can build")
	t.ok(_find(cards, "id", "lab").get("locked", false), "lab locked until researched")
	t.ok(not _find(cards, "id", "power").has("locked"), "reactor unlocked")
	t.eq(_find(cards, "id", "power")["cost"], "100 M +80 kW", "output is signed")
	t.eq(_find(cards, "id", "refinery")["cost"], "150 M 20 kW", "draw")
	p[0].bridge_money = 120
	cards = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.ok(_find(cards, "id", "barracks")["short"], "short on material")
	t.eq(_find(cards, "id", "barracks")["prereq"], "Need 80 more material", "shortfall stated")
	t.ok(_find(cards, "id", "wall").get("short", false) == false and _find(cards, "id", "wall").get("locked", false) == true, "wall locked, not short")


func test_armed_building_shows_a_placement_preview(t) -> void:
	var p := _make()
	p[1].tab = "build"
	p[0].build_mode = "Barracks"
	var vm: Dictionary = p[1].hud_vm(0.0)
	var placement: Dictionary = vm["build_placement"]
	t.eq(placement["tone"], "good", "valid and affordable")
	t.eq(placement["title"], "Barracks / Preview", "title")
	t.eq(placement["costs"][0]["value"], "200", "materials")
	t.ok(placement["note"].contains("from 840 to 640"), "material after placing")
	t.ok(_find(vm["deck"]["body"]["cards"], "id", "barracks")["selected"], "card selected")
	t.eq(vm["build_top"]["chips"][0]["note"], "planned -200", "planned spend")
	p[0].cursor_valid = false
	t.eq(p[1].hud_vm(0.0)["build_placement"]["status"], "Invalid location", "invalid tile")
	p[0].cursor_valid = true
	p[0].bridge_money = 150
	placement = p[1].hud_vm(0.0)["build_placement"]
	t.eq(placement["tone"], "bad", "cannot afford")
	t.eq(placement["status"], "Materials 50 short", "shortfall in the status")
	p[0].build_mode = ""
	t.ok(not p[1].hud_vm(0.0).has("build_placement"), "nothing armed, no preview")


func test_forecast_deficit_only_when_the_plan_overloads_the_grid(t) -> void:
	var p := _make()
	p[1].tab = "build"
	p[0].bridge_power_generation = 160
	p[0].bridge_power_demand = 130
	p[0].build_mode = "VehicleFactory"
	t.ok(not p[1].hud_vm(0.0).has("build_power"), "130 + 30 fits in 160")
	p[0].bridge_power_demand = 140
	var tip: Dictionary = p[1].hud_vm(0.0)["build_power"]
	t.eq(tip["title"], "Forecast deficit 10 kW", "10 kW over after commissioning")
	t.eq(tip["buttons"][1]["arg"], "power", "plan a reactor")
	p[0].build_mode = "PowerPlant"
	p[0].bridge_power_demand = 130
	t.ok(not p[1].hud_vm(0.0).has("build_power"), "a reactor adds output")


func test_build_layout_drives_the_real_screen(t) -> void:
	var p := _make()
	p[1].tab = "build"
	p[0].build_mode = "Refinery"
	var hud := Hud.new()
	BuildDeck.register(hud)
	hud.apply(p[1].hud_vm(0.0))
	t.ok(hud.get_node("build_placement").get_child_count() > 0, "placement drawn")
	t.ok(hud.get_node("deck_body").get_child_count() > 0, "deck drawn")
	t.eq(hud.get_node("top_chips").get_child_count(), 0, "main top bar cleared")
	hud.apply(_flip(p, "units"))
	t.eq(hud.get_node("build_top").get_child_count(), 0, "build top bar cleared on return to main")
	t.ok(hud.get_node("top_chips").get_child_count() > 0, "main top bar back")
	hud.free()


func _flip(p: Array, tab_name: String) -> Dictionary:
	p[1].on_action("deck_tab", tab_name)
	return p[1].hud_vm(1.0)


func test_arm_build_action_reaches_the_game(t) -> void:
	var p := _make()
	p[1].on_action("arm_build", "refinery")
	t.eq(p[0].calls, [["command", "build_refinery"]], "routed to the existing handler")


func _freed_selection(p: Array) -> void:
	var tank: Node3D = p[0].add_node(9, "Tank", "unit", 0, Vector3.ZERO)
	p[0].selected_units = [tank]
	p[0].selected = tank
	p[0].bridge_nodes.erase(9)  # the game drops the entity from its bridge map but keeps `selected`
	tank.free()


## A freed selection fails silently (the runner does not count engine errors), so guard the cause in the source.
func test_queue_does_not_type_assign_a_possibly_freed_selection(t) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/live_adapter.gd")
	t.ok(not src.contains("var node: Node3D = g.selected"), "_queue must not type-assign g.selected (it may be freed)")


func test_a_freed_selection_does_not_break_the_build_tab(t) -> void:
	var p := _make()
	_freed_selection(p)
	t.eq(p[1]._queue(), [], "a freed structure produces no queue (an empty array, not a failed call)")
	p[1].tab = "build"
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.eq(vm["deck"]["body"]["kind"], "build", "build deck still built")
	t.ok(not vm["deck"]["body"].has("queue"), "no queue from a freed structure")
	t.ok(not vm.has("selection"), "no selection panel for a freed unit")


func test_a_freed_selection_does_not_break_the_units_and_orders_tabs(t) -> void:
	var p := _make()
	_freed_selection(p)
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("deck"), "units deck still built")
	t.ok(not vm.has("selection"), "no selection panel for a freed unit")
	p[1].tab = "orders"
	vm = p[1].hud_vm(0.0)
	var cards: Array = vm["deck"]["body"]["cards"]
	t.ok(_find(cards, "name", "Attack-move").get("locked", false), "attack-move locked with nothing valid selected")
	t.ok(_find(cards, "name", "Sell").get("locked", false), "sell locked with nothing valid selected")
