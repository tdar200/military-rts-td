extends RefCounted
## Task 17 (kestrel-depth): the Upgrades section of the Science screen (weapons, armour and vitality, read from the
## snapshot's Kestrel-only `depth` block; the forge is never offered), the `upgrade,<track>` line, and Q casting the
## selection's tactical ability on Kestrel with the denied feedback when it cannot be cast.
const Live = preload("res://scripts/ui/live_research.gd")
const Stub = preload("res://tests/stub_game.gd")
const Screen = preload("res://scripts/ui/research_screen.gd")
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Orders = preload("res://tests/test_orders_protocol.gd")
const U = preload("res://tests/section_util.gd")


func _depth(levels: Array, costs: Array) -> Dictionary:
	return {"depth": {"upgrades": levels, "upgrade_costs": costs}}


func _rows(vm: Dictionary) -> Array:
	return vm.get("upgrades", {}).get("rows", [])


func test_no_depth_block_means_no_upgrades_section(t) -> void:
	var g := Stub.new()
	t.ok(not Live.new().vm(g).has("upgrades"), "Survival's snapshot has no depth block, so no section")


func test_the_section_lists_three_tracks_with_level_and_cost(t) -> void:
	var g := Stub.new()
	g.bridge_snapshot = _depth([1, 0, 3], [250, 150, null])
	g.bridge_money = 200
	var rows := _rows(Live.new().vm(g))
	t.eq(rows.map(func(r): return r["label"]), ["Weapons", "Armour", "Vitality"], "three tracks, never the forge")
	t.eq(rows.map(func(r): return r["level"]), ["Level 1 / 3", "Level 0 / 3", "Level 3 / 3"], "level against the era 0 cap")
	t.eq(rows.map(func(r): return r["button"]["label"]), ["Upgrade weapons 250", "Upgrade armour 150", "Vitality at max"], "cost on the button")
	t.eq(rows.map(func(r): return r["button"]["disabled"]), [true, false, true], "short of funds or at the cap is disabled")
	t.eq(rows.map(func(r): return r["button"]["arg"]), ["0", "1", "2"], "the track id")
	t.eq(rows[0].get("tone", ""), "warn", "the short row says so")
	g.bridge_era = 1
	g.bridge_money = 5000
	g.bridge_snapshot = _depth([3, 0, 6], [450, 150, null])
	rows = _rows(Live.new().vm(g))
	t.eq(rows.map(func(r): return r["level"]), ["Level 3 / 6", "Level 0 / 6", "Level 6 / 6"], "era 1 raises the cap to 6")
	t.eq(rows.map(func(r): return r["button"]["disabled"]), [false, false, true], "affordable rows enable")
	g.bridge_active = false
	rows = _rows(Live.new().vm(g))
	t.ok(rows.all(func(r): return r["button"]["disabled"]), "no simulation, no upgrades")


func test_the_upgrade_action_returns_the_track(t) -> void:
	var live := Live.new()
	t.eq(live.handle("upgrade", "1"), {"upgrade": 1}, "the button's arg is the track")
	t.eq(live.handle("upgrade", "3"), {}, "the forge is never bought from here")


func test_the_screen_draws_the_section_inside_the_filter_panel_below_its_rows(t) -> void:
	var g := Stub.new()
	g.bridge_research_options = []
	for i in 8:
		g.bridge_research_options.append({"id": i, "name": "Project %d" % i, "branch": i, "money": 100, "duration": 300, "available": true})
	g.bridge_snapshot = _depth([1, 0, 0], [250, 150, 150])
	var screen := Screen.new()
	t.root.add_child(screen)
	screen.apply(Live.new().vm(g))
	var layer: Control = screen.get_node("upgrades")
	var panel := Rect2(16, 184, 280, 880)
	var lowest_filter := 0.0  # the bottom of everything the filter section drew but its 880 px tall panel
	for c in (screen.get_node("filters") as Control).get_children():
		if c is Control and (c as Control).size.y < 200.0:
			lowest_filter = maxf(lowest_filter, (c as Control).position.y + (c as Control).size.y)
	var buttons := U.buttons(layer)
	t.eq(buttons.map(func(b): return b.text), ["Upgrade weapons 250", "Upgrade armour 150", "Upgrade vitality 150"], "a button per track")
	for c in layer.get_children():
		if c is Control:
			var r := Rect2((c as Control).position, (c as Control).size)
			t.ok(panel.encloses(r), "%s stays inside the filter panel (%s)" % [c.name, r])
			t.ok(r.position.y >= lowest_filter, "%s sits below the filter rows (%s, rows end %s)" % [c.name, r, lowest_filter])
	t.ok(U.has_text(layer, "Level 1 / 3"), "the level is shown")
	var got: Array = []
	screen.action.connect(func(n, a): got.append([n, a]))
	buttons[1].pressed.emit()
	t.eq(got, [["upgrade", "1"]], "the armour button emits its track")
	screen.free()


func test_game_ui_routes_an_upgrade_to_the_game_and_keeps_the_screen_open(t) -> void:
	var g := Stub.new()
	g.viewport = t.root
	g.use_kestrel()
	g.bridge_snapshot["depth"] = {"upgrades": [0, 0, 0], "upgrade_costs": [150, 150, 150]}
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	ui.toggle_research()
	ui._on_research_action("upgrade", "2")
	t.eq(g.calls.filter(func(c): return c[0] == "upgrade"), [["upgrade", 2]], "the game writes the line")
	t.ok(ui.research_open(), "the screen stays open to buy another level")
	ui.free()


# ------------------------------------------------------------------ the game: lines and denials

func test_an_upgrade_writes_its_line_and_a_short_or_capped_one_is_denied(t) -> void:
	var o := Orders.new()
	var scene = o._scene(true)
	scene.bridge_snapshot = _depth([2, 0, 3], [350, 150, null])
	scene.bridge_money = 400
	t.ok(scene._write_bridge_upgrade(0), "weapons for 350 of 400")
	t.eq(o._lines(), ["upgrade,0"], "the line")
	t.ok(not scene._write_bridge_upgrade(1), "150 more is short: 350 is counted as spent until the next snapshot")
	t.ok(not scene._write_bridge_upgrade(2), "vitality is at the cap")
	t.ok(not scene._write_bridge_upgrade(3), "the forge is never bought")
	t.eq(o._lines(), [], "nothing else is written")
	o._done(scene)
	scene = o._scene(false)
	scene.bridge_money = 5000
	t.ok(not scene._write_bridge_upgrade(0), "Survival has no upgrades")
	t.eq(o._lines(), [], "and writes nothing")
	o._done(scene)


func test_q_casts_the_first_ready_ability_in_the_selection(t) -> void:
	var o := Orders.new()
	var scene = o._scene(true)
	o._place(scene, [
		o._unit(scene, 750, "Infantry", 0, Vector2i(10, 12)),
		o._unit(scene, 751, "Tank", 0, Vector2i(11, 12)),
		o._unit(scene, 752, "Helicopter", 0, Vector2i(11, 13)),
		o._unit(scene, 760, "Infantry", 1, Vector2i(13, 12)),
	])
	var near: Vector3 = scene._hex_world(13, 12)
	scene.bridge_research_options = [{"id": 6, "name": "Precision Manufacturing", "researched": false}]
	scene._set_selection([scene.bridge_nodes[750]])
	t.eq(scene._cast_depth_ability(near), "no_ability", "rifles carry no ability")
	scene._set_selection([scene.bridge_nodes[760]])
	t.eq(scene._cast_depth_ability(near), "no_ability", "an enemy never casts for us")
	scene._set_selection([scene.bridge_nodes[750], scene.bridge_nodes[751]])
	t.eq(scene._cast_depth_ability(near), "needs_tech", "a Barrage waits for Precision Manufacturing")
	t.eq(o._lines(), [], "nothing written")
	scene.bridge_research_options[0]["researched"] = true
	t.eq(scene._cast_depth_ability(scene._hex_world(30, 12)), "range", "beyond the Barrage's 6 tiles")
	t.eq(scene._cast_depth_ability(near), "", "cast")
	var lines := o._lines()
	t.eq(lines.size(), 1, "one line")
	var bits: Vector2i = scene._world_to_sim_bits(near)
	t.eq(lines[0] if lines.size() == 1 else "", "ability,751,%d,%d" % [bits.x, bits.y], "the Tank casts at the ground")
	scene.bridge_nodes[751].set_meta("ability_cd", 300)
	t.eq(scene._cast_depth_ability(near), "recharging", "a recharging Tank alone cannot cast")
	scene._set_selection([scene.bridge_nodes[751], scene.bridge_nodes[752]])
	t.eq(scene._cast_depth_ability(near), "", "the ready Helicopter casts instead")
	lines = o._lines()
	t.ok(lines.size() == 1 and str(lines[0]).begins_with("ability,752,"), "an EMP from the Helicopter (%s)" % [lines])
	o._done(scene)


## The Capital (era 1 on Kestrel, after Robotic Workcells) comes from a vehicle factory, as the core's
## `earthfront_producer` says; X used to send it to a barracks, which the sim refuses.
func test_x_trains_the_capital_at_a_vehicle_factory(t) -> void:
	var o := Orders.new()
	var scene = o._scene(true)
	var barracks := o._unit(scene, 700, "Barracks", 0, Vector2i(6, 12))
	barracks["category"] = "building"
	var factory := o._unit(scene, 701, "VehicleFactory", 0, Vector2i(6, 14))
	factory["category"] = "building"
	o._place(scene, [barracks, factory])
	scene.bridge_money = 5000
	var label := Label.new()  # the ticker the train order reports on (the scene is not in the tree, so _ready made none)
	scene.objective_label = label
	o._press(scene, KEY_X)
	t.eq(o._lines(), ["train,701,Capital"], "the factory trains it")
	t.eq(label.text, "CAPITAL UNIT ORDER SENT TO VEHICLE FACTORY", "and says so")
	label.free()
	o._done(scene)
