extends RefCounted
const Screens = preload("res://scripts/ui/live_screens.gd")
const SessionLog = preload("res://scripts/ui/session_log.gd")
const Stub = preload("res://tests/stub_game.gd")
const Debrief = preload("res://scripts/ui/debrief.gd")
const TitleScreen = preload("res://scripts/ui/title_screen.gd")


func _find(items: Array, key: String, value: Variant) -> Dictionary:
	for i in items:
		if i.get(key) == value:
			return i
	return {}


func _played(g, log, seconds: int, power_short_from := -1, ammo_zero_from := -1) -> void:
	for sec in range(0, seconds + 1, 5):
		g.bridge_tick = sec * 30
		g.bridge_power_generation = 100
		g.bridge_power_demand = 120 if power_short_from >= 0 and sec >= power_short_from else 80
		g.bridge_depot_ammo = 0 if ammo_zero_from >= 0 and sec >= ammo_zero_from else 60
		g.bridge_money = 200 + sec
		log.observe(g)


func test_title_menu_has_one_deploy_path(t) -> void:
	var vm := Screens.title_vm(true, 12)
	t.eq(_find(vm["menu"], "id", "deploy")["label"], "New operation", "deploy entry")
	t.ok(not _find(vm["menu"], "id", "deploy").get("disabled", false), "enabled with the bridge up")
	t.ok(_find(vm["menu"], "id", "continue")["disabled"], "no saves exist, so continue is disabled")
	t.eq(vm["campaign"]["featured"]["primary"]["label"], "Deploy forces", "label the QA driver looks for, case-insensitively")
	t.eq(vm["campaign"]["chapters"].size(), 4, "four locked chapters")
	t.eq(_find(vm["menu"], "id", "research")["hint"], "12 projects", "hint from live data")
	vm = Screens.title_vm(false, 0)
	t.ok(_find(vm["menu"], "id", "deploy")["disabled"], "deploy disabled while the bridge is down")
	t.eq(_find(vm["menu"], "id", "research")["hint"], "", "no hint without data")


func test_title_vm_drives_the_real_screen(t) -> void:
	var screen := TitleScreen.new()
	screen.apply(Screens.title_vm(true, 12))
	var seen: Array = []
	for b in screen.menu_buttons():
		seen.append(b.text)
	t.ok(seen.has("New operation") and seen.has("Quit"), "menu buttons carry their labels")
	screen.free()


func test_session_log_records_samples_waves_relays(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	g.bridge_waves = 0
	_played(g, log, 20)
	t.eq(log.samples.size(), 5, "one sample per 5 s")
	g.bridge_tick = 25 * 30
	g.bridge_waves = 1
	g.bridge_relays = 1
	log.observe(g)
	t.eq(log.wave_times, [25.0], "wave arrival recorded")
	t.eq(log.relay_times, [25.0], "relay destroyed recorded")
	t.eq(log.relays_total, 2, "relay total is the maximum seen")


func test_session_log_never_grows_without_bound(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	for sec in range(0, 5 * 3000, 5):
		g.bridge_tick = sec * 30
		log.observe(g)
	t.ok(log.samples.size() <= SessionLog.MAX_SAMPLES, "thinned past %d" % SessionLog.MAX_SAMPLES)
	t.ok(log.samples[0]["t"] == 0.0 and log.samples[log.samples.size() - 1]["t"] > 14000.0, "still spans the whole mission")


func test_unit_counts_only_the_players_units(t) -> void:
	var log := SessionLog.new()
	log.unit_added("Tank", 0, "unit")
	log.unit_added("Tank", 1, "unit")
	log.unit_added("Barracks", 0, "building")
	log.unit_removed("Tank", 0, "unit")
	t.eq(log.produced, {"Tank": 1}, "only human units produced")
	t.eq(log.lost, {"Tank": 1}, "only human units lost")


func test_victory_debrief_uses_recorded_data_and_hides_the_rest(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	g.bridge_winner = 0
	g.bridge_research_count = 12
	g.bridge_technology_total = 12
	_played(g, log, 600)
	var vm := Screens.debrief_vm(g, log)
	t.eq(vm["variant"], "victory", "variant")
	t.eq(_find(vm["stats"], "label", "Operation time")["value"], "10:00", "elapsed from the tick")
	t.eq(_find(vm["stats"], "label", "Technologies")["value"], "12 / 12", "research")
	t.ok(_find(vm["stats"], "label", "HQ integrity").is_empty(), "no HQ node, no HQ stat")
	t.ok(not vm.has("casualties"), "nothing produced, no casualty block")
	t.ok(vm.has("economy"), "chart from samples")
	t.eq(vm["footer"], "Final tick 18,000", "thousands separators")
	log.unit_added("Tank", 0, "unit")
	log.unit_removed("Tank", 0, "unit")
	log.unit_removed("Infantry", 0, "unit")
	var rows: Array = Screens.debrief_vm(g, log)["casualties"]["rows"]
	t.eq(_find(rows, "name", "Battle tanks")["produced"], 1, "tank produced")
	t.ok(_find(rows, "name", "Infantry")["produced"] >= _find(rows, "name", "Infantry")["lost"], "produced is never below lost")
	t.ok(_find(rows, "name", "Capital units").is_empty(), "no capital row until one is trained")
	log.unit_added("Capital", 0, "unit")
	log.unit_removed("Capital", 0, "unit")
	rows = Screens.debrief_vm(g, log)["casualties"]["rows"]
	t.eq(_find(rows, "name", "Capital units")["produced"], 1, "capital units are counted in the casualty rows")
	t.eq(_find(rows, "name", "Capital units")["lost"], 1, "and their losses")


func test_debrief_with_no_samples_is_just_the_headline(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	g.bridge_winner = 0
	var vm := Screens.debrief_vm(g, log)
	t.ok(not vm.has("economy") and not vm.has("casualties"), "no invented blocks")
	g.bridge_winner = 1
	vm = Screens.debrief_vm(g, log)
	t.eq(vm["variant"], "defeat", "defeat variant")
	t.ok(not vm.has("timeline") and not vm.has("chain") and not vm.has("advice"), "no record, no timeline")
	var col := Debrief.new()
	col.apply(vm)
	t.ok(col.get_child_count() > 0, "the screen still draws")
	col.free()


func test_defeat_timeline_comes_from_the_record(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	g.bridge_winner = 1
	_played(g, log, 300, 200, 250)
	var vm := Screens.debrief_vm(g, log)
	var timeline: Dictionary = vm["timeline"]
	var power := _find(timeline["rows"], "label", "Power")
	t.eq(power["segments"].size(), 2, "balanced then deficit")
	t.eq(power["segments"][1]["tone"], "warn", "deficit segment")
	t.near(power["segments"][1]["to"], 1.0, 0.001, "segments end at the right edge")
	t.ok(not _find(timeline["rows"], "label", "Depot ammo").is_empty(), "depot row present")
	t.eq(_find(vm["chips"], "label", "Power deficit")["value"], "01:40 total", "deficit total")
	t.ok(vm["advice"].size() == 2, "rule-based advice from the record")
	var col := Debrief.new()
	col.apply(vm)
	t.ok(col.get_child_count() > 0, "drawn")
	col.free()


func test_victory_vm_drives_the_real_column(t) -> void:
	var g := Stub.new()
	var log := SessionLog.new()
	g.bridge_winner = 0
	_played(g, log, 120)
	var col := Debrief.new()
	col.apply(Screens.debrief_vm(g, log))
	var labels: Array = []
	var stack: Array = [col]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.text != "":
			labels.append(n.text)
		stack.append_array(n.get_children())
	t.ok(labels.has("Review battlefield") and labels.has("Redeploy"), "buttons carry their labels")
	col.free()
