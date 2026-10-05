extends RefCounted
## live_adapter.gd wiring for boards 4, 5 and 7: which slices a real selection and armed state add to the view model, what
## they replace, and which game handler each new action reaches. Kestrel Reach's snapshot, plus entities the test adds.
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Stub = preload("res://tests/stub_game.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")


func _bits(col: int, row: int) -> Array:
	var sx := col * 0.75 + 0.5
	var sz := row + 0.5 + (0.5 if col % 2 != 0 else 0.0)
	return [int(sx * 65536.0), int(sz * 65536.0)]


func _entity(id: int, kind: String, category: String, col: int, row: int) -> Dictionary:
	var b := _bits(col, row)
	return {"id": id, "owner": 0, "category": category, "kind": kind, "x_bits": b[0], "z_bits": b[1], "hp_bits": 100 * 65536, "max_hp_bits": 100 * 65536,
		"rally_x_bits": -1, "rally_z_bits": -1, "construction": 0, "construction_total": 0, "production_name": "", "production_queued": 0,
		"production_progress": 0, "production_duration": 0, "idle": false, "rank": 0}


## A game on Kestrel Reach with a Barracks (id 50), a Tank (60) and a Rifleman (61) of the player's.
func _make() -> Array:
	var g := Stub.new()
	g.use_kestrel()
	g.bridge_snapshot["entities"].append(_entity(50, "Barracks", "building", 9, 9))
	g.bridge_snapshot["entities"].append(_entity(60, "Tank", "unit", 10, 9))
	g.bridge_snapshot["entities"].append(_entity(61, "Infantry", "unit", 10, 10))
	g.bridge_snapshot["services"].append({"id": 50, "power": 1000, "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false})
	g.bridge_next_wave_ticks = -1
	g.bridge_snapshot["next_wave_ticks"] = -1
	g.add_node(50, "Barracks", "building", 0, Vector3.ZERO)
	g.add_node(60, "Tank", "unit", 0, Vector3.ZERO)
	g.add_node(61, "Infantry", "unit", 0, Vector3.ZERO)
	var a := Adapter.new(g)
	a.tab = "orders"
	return [g, a]


func _select(g, ids: Array) -> void:
	var picked: Array = []
	for id in ids:
		picked.append(g.bridge_nodes[id])
	g.selected_units = picked
	g.selected = picked[0] if not picked.is_empty() else null


func test_selected_building_gets_the_structure_frame_and_site_card(t) -> void:
	var p := _make()
	_select(p[0], [50])
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("structure"), "a lone own building selected: the structure frame")
	t.eq(vm["structure"]["kind"], "Barracks", "for that building")
	t.ok(vm.has("site"), "with its site card")
	t.ok(not vm.has("selection"), "the old selection panel steps aside")
	t.ok(not vm.has("territory"), "the site card stands in for the territory card, as on board 4")
	t.ok(not vm.has("inspect") and not vm.has("ledger"), "nothing else draws in the bottom centre")
	t.ok(float(vm["site"]["y"]) >= 76.0 + 42.0, "the card sits under the objectives panel")


func test_no_selection_and_unit_selection_keep_the_old_panels(t) -> void:
	var p := _make()
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(not vm.has("structure") and not vm.has("roster") and not vm.has("armed") and not vm.has("site"), "nothing selected, nothing armed")
	t.ok(vm.has("ledger"), "the colony ledger still owns the bottom centre")
	_select(p[0], [60, 61])
	vm = p[1].hud_vm(0.0)
	t.ok(vm.has("selection") and not vm.has("structure"), "units keep the old selection panel while unarmed")
	t.ok(not vm.has("roster"), "the roster is for the armed state")


func test_armed_attack_move_shows_banner_and_roster(t) -> void:
	var p := _make()
	_select(p[0], [60, 61])
	p[0].attack_move_armed = true
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("armed") and str(vm["armed"]["hint"]).contains("Right click"), "the banner, with the real right-click wording")
	t.eq(vm["roster"]["cards"].size(), 2, "a card per selected unit")
	t.eq(vm["roster"]["count"], "2 units", "count")
	t.ok(bool(vm["roster"]["armed"]), "armed tag on")
	t.ok(not vm.has("selection"), "the roster replaces the selection panel")
	p[0].attack_move_armed = false
	t.ok(not p[1].hud_vm(0.0).has("armed"), "disarmed, the banner goes")


func test_armed_with_nothing_selected_still_shows_the_banner(t) -> void:
	var p := _make()
	p[0].attack_move_armed = true
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("armed"), "A was pressed, so the banner shows")
	t.ok(not vm.has("roster"), "but there is no roster without units")


func test_rally_arming_has_its_own_banner(t) -> void:
	var p := _make()
	_select(p[0], [50])
	p[0].rally_armed = true
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.eq(vm["armed"]["title"], "Set rally armed", "title")
	t.ok(str(vm["armed"]["hint"]).begins_with("Left click"), "a left click sets the rally")


func test_control_groups_list_follows_the_game_table(t) -> void:
	var p := _make()
	t.ok(not p[1].hud_vm(0.0).has("control_groups"), "no groups, no list")
	p[0].control_groups = {1: [p[0].bridge_nodes[60], p[0].bridge_nodes[61]]}
	_select(p[0], [60, 61])
	var vm: Dictionary = p[1].hud_vm(0.0)
	var slots: Array = vm["control_groups"]["slots"]
	t.eq(slots.size(), 4, "four bound slots")
	t.eq(slots[0]["count"], 2, "two units in group 1")
	t.ok(bool(slots[0]["on"]), "the selection is group 1, so it is lit")
	_select(p[0], [60])
	t.ok(not bool(p[1].hud_vm(0.0)["control_groups"]["slots"][0]["on"]), "a narrower selection is not the group")
	t.ok(float(vm["control_groups"]["y"]) >= 76.0, "stacked in the left column")


func test_territory_card_is_pushed_below_the_left_cards(t) -> void:
	var p := _make()
	var plain: Dictionary = p[1].hud_vm(0.0)
	t.ok(not plain["territory"].has("y"), "alone it keeps its own place")
	p[0].control_groups = {1: [p[0].bridge_nodes[60]]}
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(float(vm["territory"]["y"]) >= float(vm["control_groups"]["y"]) + 140.0, "it moves under the control group list")


func test_wave_panel_replaces_the_top_wave_card_inside_its_window(t) -> void:
	var p := _make()
	p[0].bridge_next_wave_ticks = 1350
	p[0].bridge_snapshot["next_wave_ticks"] = 1350
	p[0].bridge_snapshot["waves_survived"] = 1
	var vm: Dictionary = p[1].hud_vm(0.0)
	t.ok(vm.has("wave_panel"), "inside the 90 s window")
	t.ok(not vm.has("wave_card"), "the older card would repeat it")
	t.eq(vm["wave_panel"]["cap"], "Wave 02", "wave number from waves survived")
	p[0].bridge_next_wave_ticks = 9000
	p[0].bridge_snapshot["next_wave_ticks"] = 9000
	vm = p[1].hud_vm(0.0)
	t.ok(not vm.has("wave_panel"), "outside the window")


func test_no_snapshot_adds_none_of_it(t) -> void:
	var g := Stub.new()
	var a := Adapter.new(g)
	a.tab = "orders"
	var n: Node3D = g.add_node(8, "Barracks", "building", 0, Vector3.ZERO)
	g.selected_units = [n]
	g.selected = n
	g.attack_move_armed = true
	var vm: Dictionary = a.hud_vm(0.0)
	t.ok(vm.has("selection"), "the old selection panel stays")
	for key in ["structure", "site", "roster", "armed", "wave_panel", "control_groups"]:
		t.ok(not vm.has(key), "no %s without a snapshot" % key)


func test_new_actions_reach_the_game(t) -> void:
	var p := _make()
	p[1].on_action("set_rally", 50)
	p[1].on_action("recall_group", 2)
	p[1].on_action("order", "cancel_armed")
	t.eq(p[0].calls, [["arm_rally"], ["recall_group", 2], ["command", "cancel_orders"]], "each action reaches its game handler")


func test_the_real_hud_builds_every_new_section(t) -> void:
	var p := _make()
	_select(p[0], [50])
	p[0].control_groups = {1: [p[0].bridge_nodes[60]]}
	p[0].bridge_next_wave_ticks = 1350
	p[0].bridge_snapshot["next_wave_ticks"] = 1350
	p[0].rally_armed = true
	var hud := Hud.new()
	var root := Control.new()
	root.add_child(hud)
	var seen: Array = []
	hud.action.connect(func(name, arg): seen.append([name, arg]))
	hud.apply(p[1].hud_vm(0.0))
	for key in ["structure_panel", "site_card", "wave_panel", "control_groups", "attack_move_banner"]:
		t.ok(hud._layers[key].get_child_count() > 0, "%s drew" % key)
	var found: Button = null
	for b in hud._layers["structure_panel"].find_children("*", "Button", true, false):
		if (b as Button).text == "Set rally":
			found = b
	t.ok(found != null, "the structure panel's Set rally button is in the real HUD")
	if found != null:
		found.pressed.emit()
		t.eq(seen, [["set_rally", 50]], "pressing it emits the action the adapter routes")
	root.free()


# ------------------------------------------------------------------ world marks

func _project(x: int, y: int) -> Vector2:
	return Vector2(100.0 + x * 40.0, 50.0 + y * 30.0)


func _kinds(marks: Array) -> Array:
	return marks.map(func(m): return m["kind"])


func test_no_marks_without_a_selection_or_a_wave(t) -> void:
	var p := _make()
	t.eq(p[1].board_marks(_project), [], "nothing selected, no wave in the window")
	var bare := Adapter.new(Stub.new())
	t.eq(bare.board_marks(_project), [], "no snapshot, no marks")


func test_selected_producer_with_a_rally_gets_a_dotted_path(t) -> void:
	var p := _make()
	var b := _bits(14, 9)
	for e in p[0].bridge_snapshot["entities"]:
		if int(e["id"]) == 50:
			e["rally_x_bits"] = b[0]
			e["rally_z_bits"] = b[1]
	_select(p[0], [50])
	var marks: Array = p[1].board_marks(_project)
	t.eq(_kinds(marks), ["arrow"], "one rally path")
	var at := _project(9, 9)
	t.near(marks[0]["x"], at.x, 0.01, "starts at the producer's hex")
	t.near(marks[0]["to"].x, _project(14, 9).x, 0.01, "ends at the rally hex")
	t.ok(bool(marks[0]["queued"]), "dotted, the way queued paths draw")
	_select(p[0], [60])
	t.eq(p[1].board_marks(_project), [], "a unit has no rally")


func test_a_producer_without_a_rally_draws_nothing(t) -> void:
	var p := _make()
	_select(p[0], [50])
	t.eq(p[1].board_marks(_project), [], "no rally set, nothing invented")


func test_selected_turret_gets_its_range_as_a_ring(t) -> void:
	var p := _make()
	p[0].bridge_snapshot["entities"].append(_entity(70, "GunTurret", "building", 12, 12))
	p[0].add_node(70, "GunTurret", "building", 0, Vector3.ZERO)
	_select(p[0], [70])
	var marks: Array = p[1].board_marks(_project)
	t.eq(_kinds(marks), ["ring"], "the weapon range")
	t.near(marks[0]["ry"], 5.0 * 30.0, 0.01, "five sim units of rows")
	t.near(marks[0]["rx"], 7.0 * 40.0, 0.01, "five sim units is seven columns of 0.75")
	_select(p[0], [50])
	t.eq(p[1].board_marks(_project), [], "only the selected turret shows its range")


func test_selected_turret_ring_includes_the_highland_range_bonus(t) -> void:
	var p := _make()
	var ground = p[0].ground_model
	# Kestrel's Ironback Ridge (columns 24+, rows 0 to 5) is Highland: +25% range.
	t.eq(String(ground.name_at(30, 2)), "Highland", "fixture: (30, 2) is Highland")
	p[0].bridge_snapshot["entities"].append(_entity(70, "GunTurret", "building", 30, 2))
	p[0].add_node(70, "GunTurret", "building", 0, Vector3.ZERO)
	_select(p[0], [70])
	var marks: Array = p[1].board_marks(_project)
	t.eq(_kinds(marks), ["ring"], "the weapon range")
	t.near(marks[0]["ry"], 6.0 * 30.0, 0.01, "5 x 1.25 = 6.25 rows (rounded to whole hexes), not the base 5")
	t.near(marks[0]["rx"], 8.0 * 40.0, 0.01, "and 8 columns of 0.75, not 7")
	t.near(VmGameplay.effective_turret_range({"cell": [30, 2], "range": 5}, ground), 6.25, 0.001, "the helper is exact")
	t.near(VmGameplay.effective_turret_range({"cell": [30, 2], "range": 5}, null), 5.0, 0.001, "no ground model: the base range")


func test_wave_route_draws_while_the_panel_is_up(t) -> void:
	var p := _make()
	p[0].bridge_snapshot["next_wave_ticks"] = 1350
	var marks: Array = p[1].board_marks(_project)
	t.ok(marks.size() >= 2, "the route is split into segments")
	for m in marks:
		t.eq(m["kind"], "beam", "red dashed segment")
	p[0].bridge_snapshot["next_wave_ticks"] = 9000
	t.eq(p[1].board_marks(_project), [], "outside the window the route is not drawn")


func test_marks_behind_the_camera_are_dropped(t) -> void:
	var p := _make()
	p[0].bridge_snapshot["next_wave_ticks"] = 1350
	var behind := func(_x: int, _y: int) -> Vector2: return Vector2.INF
	t.eq(p[1].board_marks(behind), [], "nothing projects, nothing draws")
