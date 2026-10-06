extends RefCounted
## Kestrel Reach objectives (plan 2026-10-06-kestrel-next-level, Task 3): the pure evaluator over crafted snapshots, the HUD
## card, briefing and toast wiring on Kestrel, Survival's legacy tutorial left as the only path without world art, and the
## structure-under-attack alert throttle.
const KO = preload("res://scripts/world/kestrel_objectives.gd")
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Maps = preload("res://scripts/ui/vm_maps.gd")
const Stub = preload("res://tests/stub_game.gd")
const GameUI = preload("res://scripts/ui/game_ui.gd")
const U = preload("res://tests/section_util.gd")

const HUMAN := 0
const ALIEN := 1


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _entity(snap: Dictionary, id: int) -> Dictionary:
	for e in snap["entities"]:
		if int(e["id"]) == id:
			return e
	return {}


func _remove(snap: Dictionary, id: int) -> void:
	snap["entities"] = snap["entities"].filter(func(e): return int(e["id"]) != id)


func _add(snap: Dictionary, kind: String, owner := HUMAN, category := "unit") -> Dictionary:
	var e: Dictionary = _entity(snap, 1).duplicate(true)
	e["id"] = 100 + snap["entities"].size()
	e["kind"] = kind
	e["owner"] = owner
	e["category"] = category
	snap["entities"].append(e)
	return e


## The fixture's Harvester (id 8) carrying ore: the economy objective's live signal.
func _hauling(snap: Dictionary) -> Dictionary:
	_entity(snap, 8)["cargo"] = 30
	return snap


func _squad(snap: Dictionary) -> Dictionary:
	_add(snap, "Infantry")
	_add(snap, "AntiArmor")
	return snap


func _done(r: Dictionary) -> Array:
	return r["objectives"].map(func(o): return bool(o["done"]))


# ------------------------------------------------------------------ evaluator: the stages

func test_the_five_objectives_and_their_titles(t) -> void:
	var r: Dictionary = KO.evaluate(_snap())
	t.eq(r["objectives"].map(func(o): return o["id"]), ["power", "economy", "squad", "ford", "core"], "five objectives in order")
	t.eq(r["objectives"].map(func(o): return o["title"]), ["Power the base", "Start the economy", "Raise a squad", "Hold the ford", "Break the Core Node"], "the titles")
	for o in r["objectives"]:
		t.ok(str(o["detail"]) != "", "%s has a detail line" % o["id"])
		t.ok(not str(o["detail"]).contains("\u2013") and not str(o["detail"]).contains("\u2014"), "no en or em dash in %s" % o["id"])


func test_the_opening_starts_powered_and_waits_for_the_first_ore(t) -> void:
	var r: Dictionary = KO.evaluate(_snap())
	t.eq(_done(r), [true, false, false, false, false], "the prebuilt Reactor powers the base (90 kW for 30), no ore moved yet")
	t.eq(r["stage"], 2, "the first open objective is the economy")
	t.eq(r["title"], "Start the economy", "the current title")
	t.eq(r["objectives"][0]["detail"], "Reactor online: 90 kW for 30 kW demand", "power is confirmed with the real numbers")
	t.eq(r["detail"], "Harvester heading for the ore beside the base", "the economy detail while the truck is empty")
	t.ok(not bool(r["complete"]) and not bool(r["failed"]), "the match is open")


func test_a_harvester_carrying_ore_starts_the_economy(t) -> void:
	var r: Dictionary = KO.evaluate(_hauling(_snap()))
	t.eq(_done(r), [true, true, false, false, false], "economy done once the truck carries ore")
	t.eq(r["stage"], 3, "on to the squad")
	t.eq(r["objectives"][1]["detail"], "Harvester hauling ore to the Refinery", "the done economy line")
	t.eq(r["detail"], "Train riflemen (T): 4 of 6 combat units", "the squad count from the four starting riflemen")


func test_delivered_ore_in_the_refinery_also_counts(t) -> void:
	var snap := _snap()
	snap["ore_buffer"] = 40
	t.ok(KO.evaluate(snap)["objectives"][1]["done"], "ore_buffer > 0 means a load reached the Refinery")


func test_the_economy_latches_between_loads_but_not_past_a_lost_truck(t) -> void:
	var first: Dictionary = KO.evaluate(_hauling(_snap()))
	var empty := _snap()  # truck unloaded, buffer processed: the gap between two loads
	t.ok(not KO.evaluate(empty)["objectives"][1]["done"], "a fresh read of an empty truck is not proof of an economy")
	t.ok(KO.evaluate(empty, first)["objectives"][1]["done"], "but after a seen load the gap between loads does not flicker it")
	var no_truck := _snap()
	_remove(no_truck, 8)
	var lost: Dictionary = KO.evaluate(no_truck, first)
	t.ok(not lost["objectives"][1]["done"], "a destroyed Harvester reopens the economy")
	t.eq(lost["objectives"][1]["detail"], "Train a Harvester at the Refinery", "with the fix")
	var no_refinery := _snap()
	_remove(no_refinery, 6)
	var gone: Dictionary = KO.evaluate(_hauling(no_refinery), first)
	t.ok(not gone["objectives"][1]["done"], "no Refinery, no economy, even with a loaded truck")
	t.eq(gone["objectives"][1]["detail"], "Build a Refinery beside the ore (R)", "with the fix")
	t.ok(not KO.evaluate(_snap(), lost)["objectives"][1]["done"], "the latch is gone once it was lost")


func test_a_squad_of_six_combat_units_opens_the_ford(t) -> void:
	var snap := _squad(_hauling(_snap()))
	var r: Dictionary = KO.evaluate(snap)
	t.eq(_done(r), [true, true, true, false, false], "4 riflemen + 2 trained = 6")
	t.eq(r["stage"], 4, "hold the ford next")
	t.eq(r["objectives"][2]["detail"], "Squad ready: 6 combat units", "the done squad line")
	t.eq(r["detail"], "Hold Wyllow Ford: first wave in 2:30", "the ford by its region name and the live wave timer")
	snap["next_wave_ticks"] = 95
	t.eq(KO.evaluate(snap)["detail"], "Hold Wyllow Ford: first wave in 0:04", "the timer rounds up")


func test_harvesters_aliens_and_sites_do_not_make_a_squad(t) -> void:
	var snap := _hauling(_snap())
	_add(snap, "Harvester")
	_add(snap, "Infantry", ALIEN)
	_add(snap, "Tank", ALIEN)
	t.eq(KO.evaluate(snap)["detail"], "Train riflemen (T): 4 of 6 combat units", "only human combat units count")
	_squad(snap)
	_remove(snap, 7)
	var r: Dictionary = KO.evaluate(snap)
	t.ok(not r["objectives"][2]["done"], "six units but no Barracks is not a squad objective met")
	t.eq(r["detail"], "Build a Barracks (B) to train riflemen", "the fix")
	var site := _add(snap, "Barracks", HUMAN, "building")
	site["construction"] = 120
	t.ok(not KO.evaluate(snap)["objectives"][2]["done"], "a Barracks still under construction does not count")
	site["construction"] = 0
	t.ok(KO.evaluate(snap)["objectives"][2]["done"], "a finished one does")


func test_surviving_wave_one_points_at_the_core_node(t) -> void:
	var snap := _squad(_hauling(_snap()))
	snap["waves_survived"] = 1
	var r: Dictionary = KO.evaluate(snap)
	t.eq(_done(r), [true, true, true, true, false], "the ford is held")
	t.eq(r["stage"], 5, "last objective")
	t.eq(r["objectives"][3]["detail"], "Wave one held at Wyllow Ford", "the done ford line")
	t.eq(r["detail"], "Destroy the Core Node at (37, 8)", "the core node's cell from the snapshot")
	snap.erase("core_node")
	t.eq(KO.evaluate(snap)["detail"], "Destroy the alien Core Node", "no cell in the snapshot, none invented")


# ------------------------------------------------------------------ evaluator: the edge cases

func test_a_destroyed_power_plant_reopens_power_before_wave_one(t) -> void:
	var snap := _squad(_hauling(_snap()))
	t.eq(KO.evaluate(snap)["stage"], 4, "everything up to the ford is done")
	_remove(snap, 5)
	snap["power_generation"] = 10  # the Command Centre's own 10 kW
	var r: Dictionary = KO.evaluate(snap)
	t.eq(_done(r), [false, true, true, false, false], "only power reverts: the setup objectives are judged live")
	t.eq(r["stage"], 1, "the card honestly goes back to power")
	t.eq(r["detail"], "Build a Reactor (P): 10 of 30 kW", "with the real shortfall")
	var short := _squad(_hauling(_snap()))
	short["power_demand"] = 120
	var s: Dictionary = KO.evaluate(short)
	t.ok(not s["objectives"][0]["done"], "a standing Reactor that is overdrawn is not power met")
	t.eq(s["detail"], "Power short: 90 of 120 kW, build a Reactor (P)", "the overdraw fix")
	var site := _snap()
	_entity(site, 5)["construction"] = 300
	t.ok(not KO.evaluate(site)["objectives"][0]["done"], "a Reactor still being built is not online")


func test_after_wave_one_the_setup_stays_done(t) -> void:
	var snap := _squad(_hauling(_snap()))
	snap["waves_survived"] = 1
	_remove(snap, 5)
	_remove(snap, 8)
	snap["power_generation"] = 10
	var r: Dictionary = KO.evaluate(snap)
	t.eq(_done(r), [true, true, true, true, false], "once the ford is held the setup phase is over: no regression")
	t.eq(r["stage"], 5, "the card keeps pointing at the Core Node")


func test_a_mid_game_load_jumps_to_the_core_node(t) -> void:
	var snap := _snap()
	snap["tick"] = 16000
	snap["waves_survived"] = 2
	snap["next_wave_ticks"] = 1300
	for kind in ["PowerPlant", "PowerPlant", "Refinery", "VehicleFactory", "GunTurret", "GunTurret", "SupplyDepot", "ResearchLab"]:
		_add(snap, kind, HUMAN, "building")
	_remove(snap, 1)
	_remove(snap, 2)  # losses: only two riflemen left, the truck between loads
	var r: Dictionary = KO.evaluate(snap)  # no previous result: a fresh client
	t.eq(_done(r), [true, true, true, true, false], "a fresh client with no history still reads the state right")
	t.eq(r["stage"], 5, "straight to the Core Node")


func test_a_won_match_completes_everything_and_a_lost_one_fails(t) -> void:
	var snap := _snap()
	snap["winner"] = HUMAN
	snap["waves_survived"] = 3
	var won: Dictionary = KO.evaluate(snap)
	t.eq(_done(won), [true, true, true, true, true], "the Core Node is broken")
	t.ok(won["complete"] and not won["failed"], "complete")
	t.eq(won["stage"], 5, "the stage stays on the last objective")
	t.eq(won["objectives"][4]["detail"], "Core Node destroyed", "the done core line")
	snap["winner"] = ALIEN
	var lost: Dictionary = KO.evaluate(snap)
	t.ok(lost["failed"] and not lost["complete"], "failed")
	t.ok(not lost["objectives"][4]["done"] and not lost["objectives"][3]["done"], "a lost base holds no ford and breaks no node")


func test_an_empty_snapshot_is_safe(t) -> void:
	var r: Dictionary = KO.evaluate({})
	t.eq(r["stage"], 1, "nothing known: the first objective")
	t.eq(_done(r), [false, false, false, false, false], "nothing done")
	t.eq(r["detail"], "Build a Reactor (P): 0 of 0 kW", "no invented numbers")


func test_the_evaluator_is_pure(t) -> void:
	var snap := _hauling(_snap())
	var before := JSON.stringify(snap)
	var a: Dictionary = KO.evaluate(snap)
	var b: Dictionary = KO.evaluate(snap)
	t.eq(JSON.stringify(snap), before, "the snapshot is not modified")
	t.eq(a, b, "same input, same answer")


# ------------------------------------------------------------------ HUD wiring

func _adapter(kestrel: bool) -> Array:
	var g := Stub.new()
	if kestrel:
		g.use_kestrel()
	var a := Adapter.new(g)
	a.tab = "units"
	return [g, a]


func test_the_kestrel_card_shows_the_kestrel_stage_text(t) -> void:
	var p := _adapter(true)
	var card: Dictionary = p[1].hud_vm(0.0)["objectives"]
	t.eq(card["cap"], "Kestrel Reach", "the card names the map")
	var items: Array = card["items"]
	var texts: Array = items.map(func(i): return i["t"])
	t.eq(texts.slice(0, 5), ["Power the base", "Harvester heading for the ore beside the base", "Raise a squad", "Hold the ford", "Break the Core Node"], "titles, and the active objective's detail")
	t.eq(items.slice(0, 5).map(func(i): return i["state"]), ["done", "active", "todo", "todo", "todo"], "states")
	t.eq(items[5], {"t": "Optional: disable alien relays (2 active)", "state": "todo"}, "the relay line after the Core Node, todo before the ford")
	for legacy in Adapter.STAGE_DETAIL:
		t.ok(not texts.has(legacy), "no Survival stage text on Kestrel: %s" % legacy)
	t.ok(not texts.has("Establish a supplied base"), "no Survival group title either")


func test_the_card_reads_the_games_own_objectives(t) -> void:
	var p := _adapter(true)
	var snap := _squad(_hauling(_snap()))
	p[0].kestrel_objectives = KO.evaluate(snap)  # what earthfront_3d holds after its last poll
	var items: Array = p[1].hud_vm(0.0)["objectives"]["items"]
	t.eq(items[3], {"t": "Hold Wyllow Ford: first wave in 2:30", "state": "active"}, "the game's result, not a recount of the stub snapshot")
	t.eq(items[4]["state"], "todo", "the core is next")
	t.eq(items[5]["state"], "active", "the optional relay line is live from the ford on")


func test_survival_keeps_the_legacy_stage_text(t) -> void:
	var p := _adapter(false)
	var card: Dictionary = p[1].hud_vm(0.0)["objectives"]
	t.eq(card["cap"], "Operation Dawnshield", "Survival's cap")
	var texts: Array = card["items"].map(func(i): return i["t"])
	t.ok(texts.has("Establish a supplied base"), "the legacy group titles")
	t.ok(texts.has("Hold the Earthfront, first wave in 45s"), "and the legacy stage detail at stage 8")
	t.ok(not texts.has("Power the base") and not texts.has("Hold the ford"), "no Kestrel text on Survival")


# ------------------------------------------------------------------ briefing

func test_the_kestrel_briefing_names_the_ore_the_ford_the_wave_the_probe_and_the_core(t) -> void:
	var vm: Dictionary = Maps.kestrel_briefing(KO.evaluate(_hauling(_snap())), _snap())
	t.eq(vm["title"], "Raise a squad", "the current objective")
	t.eq(vm["tag"], "Step 3 of 5", "the step out of the five objectives")
	t.eq(vm["items"], [
		{"t": "Start the economy", "state": "done"},
		{"t": "Train riflemen (T): 4 of 6 combat units", "state": "active"},
		{"t": "Hold the ford", "state": "todo"},
	], "done, current, next")
	t.near(vm["ratio"], 2.0 / 5.0, 0.0001, "two of five done")
	var body: String = vm["body"]
	for want in ["Ore", "Command Centre", "Wyllow Ford", "2:30", "probe", "(37, 8)"]:
		t.ok(body.contains(want), "the body mentions '%s': %s" % [want, body])
	for banned in ["fog", "survey", "explor", "scout", "sight", "\u2013", "\u2014"]:
		t.ok(not body.to_lower().contains(banned), "the body never says '%s'" % banned)


func test_the_kestrel_briefing_runs_to_the_squad_and_ends_with_the_match(t) -> void:
	var start: Dictionary = Maps.kestrel_briefing(KO.evaluate(_snap()), _snap())
	t.eq(start["items"][0], {"t": "Power the base", "state": "done"}, "stage 2 shows the done power line first")
	t.eq(start["items"][1]["state"], "active", "then the economy")
	var ford := _squad(_hauling(_snap()))
	t.ok(Maps.kestrel_briefing(KO.evaluate(ford), ford).is_empty(), "once the squad is up the objectives panel takes over")
	var won := _snap()
	won["winner"] = HUMAN
	t.ok(Maps.kestrel_briefing(KO.evaluate(won), won).is_empty(), "no briefing once the match is decided")
	t.ok(Maps.kestrel_briefing({}, _snap()).is_empty(), "no objectives, no briefing")
	var later := _hauling(_snap())
	later["tick"] = 900
	later["next_wave_ticks"] = 3600
	t.ok(Maps.kestrel_briefing(KO.evaluate(later), later)["body"].contains("2:30"), "the wave time is the mission clock time, not the countdown")


func test_the_live_briefing_card_on_kestrel_and_none_on_survival(t) -> void:
	var g := Stub.new()
	g.viewport = t.root
	g.use_kestrel()
	g.tutorial_stage = 1  # the tutorial's stage is ignored on Kestrel
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	ui._refresh_briefing()
	var shown := " ".join(U.texts(ui.briefing_layer))
	t.ok(shown.contains("Start the economy") and shown.contains("Wyllow Ford"), "the Kestrel briefing is up: " + shown)
	t.ok(not shown.contains("Power the beachhead"), "not the tutorial's")
	t.ok(ui.adapter.briefing_up, "and the HUD card steps aside for it")
	g.bridge_winner = 0
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "no briefing once the match is decided")
	g.bridge_winner = -1
	g.world_art_on = false
	g.bridge_snapshot["ground"] = "g".repeat(int(g.bridge_snapshot["map_width"]) * int(g.bridge_snapshot["map_height"]))
	g.ground_model = null
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "Survival's flat ground still shows none")
	ui.free()


# ------------------------------------------------------------------ game wiring (source: the game needs a full scene)

func _source() -> String:
	return (load("res://scripts/earthfront_3d.gd") as GDScript).source_code


## The function from its header to its last indented line (blank lines inside it kept, trailing ones and the next
## function's comments left out).
func _func_body(src: String, header: String) -> String:
	var at := src.find(header)
	if at < 0:
		return ""
	var lines := src.substr(at).split("\n")
	var keep := 1
	for i in range(1, lines.size()):
		if lines[i].begins_with("\t"):
			keep = i + 1
		elif lines[i] != "":
			break
	return "\n".join(lines.slice(0, keep))


func test_survival_runs_only_the_legacy_tutorial(t) -> void:
	var process := _func_body(_source(), "func _process(delta: float) -> void:")
	var branch := process.find("if world_art_on:\n\t\t_update_kestrel_objectives()\n\telse:\n\t\t_update_tutorial()")
	t.ok(branch > 0, "_process runs the legacy tutorial only without world art, and the Kestrel objectives with it")
	t.eq(process.count("_update_tutorial()"), 1, "no other call of the legacy tutorial in _process")
	var kestrel := _func_body(_source(), "func _update_kestrel_objectives() -> void:")
	t.ok(kestrel != "", "the Kestrel update exists")
	t.ok(not kestrel.contains("tutorial_stage") and not kestrel.contains("tutorial_label"), "and never touches the legacy tutorial state")
	t.ok(kestrel.contains("KestrelObjectives.evaluate(bridge_snapshot, previous)"), "it evaluates the latest snapshot with the last result as the latch")


func test_the_legacy_tutorial_is_byte_identical(t) -> void:
	var src := _source()
	var legacy := _func_body(src, "func _advance_tutorial(next_stage: int, message: String) -> void:") + _func_body(src, "func _update_tutorial() -> void:")
	t.eq(legacy.sha256_text(), "de531e29f3631d631621f84a07410cf14aad707e3f89fc91c86db6fd19695599", "_advance_tutorial and _update_tutorial unchanged since Task 2 (aa712b9)")


# ------------------------------------------------------------------ structure under attack

func test_structure_alerts_are_throttled_per_structure_and_overall(t) -> void:
	var a: Variant = _adapter(true)[1]
	t.ok(a.structure_attacked(7, "Barracks", Vector3(1, 0, 2), [9, 7], 10.0), "the first hit on a structure alerts")
	var vm: Dictionary = a.hud_vm(10.5)
	var alert: Dictionary = vm["alerts"].back()
	t.eq(alert["title"], "Barracks under attack", "named by the HUD's kind name")
	t.eq(alert["body"], "Send units to defend it", "with the fix")
	t.ok(alert["hostile"] and alert["tone"] == "bad", "a hostile toast")
	t.ok(not a.structure_attacked(7, "Barracks", Vector3(1, 0, 3), [9, 8], 12.0), "the same structure 2 s later is quiet")
	t.eq(a.last_structure_attack, {"id": 7, "kind": "Barracks", "pos": Vector3(1, 0, 3), "cell": [9, 8], "at": 12.0}, "but the latest attack position is kept for the minimap")
	t.ok(not a.structure_attacked(5, "PowerPlant", Vector3(0, 0, 0), [5, 8], 13.0), "another structure inside the overall gap is quiet too")
	t.ok(a.structure_attacked(5, "PowerPlant", Vector3(0, 0, 0), [5, 8], 10.0 + Adapter.STRUCTURE_ALERT_GAP), "another structure after the overall gap alerts")
	t.eq(a.hud_vm(16.0)["alerts"].back()["title"], "Reactor under attack", "the power plant by its HUD name")
	t.ok(not a.structure_attacked(7, "Barracks", Vector3.ZERO, [9, 7], 10.0 + Adapter.STRUCTURE_ALERT_REPEAT - 0.5), "the Barracks again before its own repeat gap is quiet")
	t.ok(a.structure_attacked(7, "Barracks", Vector3.ZERO, [9, 7], 10.0 + Adapter.STRUCTURE_ALERT_REPEAT), "and alerts again after it")
	var titles: Array = a.hud_vm(10.0 + Adapter.STRUCTURE_ALERT_REPEAT)["alerts"].map(func(x): return x["title"])
	t.eq(titles.count("Barracks under attack"), 1, "a repeat replaces the older toast instead of stacking")


func test_the_structure_alert_is_kestrel_only_and_reuses_the_shake_and_tone(t) -> void:
	var sync := _func_body(_source(), "func _sync_bridge_entities(entities: Array) -> void:")
	var at := sync.find("if world_art_on and category == \"building\" and int(entity_data.get(\"owner\", 0)) == HUMAN:")
	t.ok(at > 0, "only a human structure on Kestrel")
	t.ok(sync.find("_structure_under_attack(", at) > at, "raises the alert")
	var body := _func_body(_source(), "func _structure_under_attack(position: Vector3, entity_data: Dictionary) -> void:")
	t.ok(body.contains("ui.structure_attacked("), "through the HUD's alert plumbing")
	t.ok(body.contains("camera_shake = maxf(camera_shake, 0.42)") and body.contains("_play_tone(92.0, 0.09, 0.12, -25.0)"), "with the existing hit shake and tone")
