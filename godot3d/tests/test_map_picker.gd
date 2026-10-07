extends RefCounted
## Map picker (Task 3): MatchConfig writes the bridge's match.json contract, the title's New operation opens the picker,
## confirming a map writes match.json and restart.flag and deploys only once the bridge took the flag, and the debrief's
## Restart / Main menu reach the game. Every file lives under user://test_map_picker and is removed again.
const MatchConfig := preload("res://scripts/match_config.gd")
const MapPicker := preload("res://scripts/ui/sections/map_picker.gd")
const LiveScreens := preload("res://scripts/ui/live_screens.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
const Stub := preload("res://tests/stub_game.gd")
const U := preload("res://tests/section_util.gd")
const DIR := "user://test_map_picker"


func _clean() -> void:
	for f in ["match.json", "match.json.next", "restart.flag"]:
		if FileAccess.file_exists(DIR.path_join(f)):
			DirAccess.remove_absolute(DIR.path_join(f))
	if DirAccess.dir_exists_absolute(DIR):
		DirAccess.remove_absolute(DIR)
	MatchConfig.reset()


func _make(t, kestrel_on_screen := false) -> Array:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var g := Stub.new()
	g.viewport = t.root
	g.runtime_directory = DIR
	if kestrel_on_screen:
		g.use_kestrel()
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	return [g, ui]


func _drop(p: Array) -> void:
	p[1].free()
	_clean()


func _press(root: Node, text: String) -> void:
	for b in U.buttons(root):
		if (b as Button).text == text and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return
	printerr("  test_map_picker: no enabled button " + text)


func _enabled(root: Node, text: String) -> Array:
	return U.buttons(root).filter(func(b): return (b as Button).text == text and not (b as Button).disabled)


func _parsed(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(name)))


func test_write_produces_the_bridge_contract(t) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cfg := MatchConfig.defaults()
	cfg.scenario = "survival"
	t.ok(MatchConfig.write(DIR, cfg))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("match.json")))
	t.eq(parsed.scenario, "survival")
	t.eq(parsed.fog, true)
	t.ok(not FileAccess.file_exists(DIR.path_join("match.json.next")))
	DirAccess.remove_absolute(DIR.path_join("match.json"))
	DirAccess.remove_absolute(DIR)


func test_defaults_json_and_names(t) -> void:
	t.eq(MatchConfig.SCENARIOS, ["kestrel", "survival"], "two maps, Kestrel first")
	t.eq(MatchConfig.defaults(), {"scenario": "kestrel", "seed": 2026, "difficulty": "normal", "fog": true}, "defaults")
	# The bridge's hand parser wants a quoted scenario and a bare true/false fog (godot-bridge.rs parse_match_config).
	t.eq(MatchConfig.to_json(MatchConfig.defaults()), "{\"scenario\":\"kestrel\",\"seed\":2026,\"difficulty\":\"normal\",\"fog\":true}", "flat JSON in a fixed key order")
	t.eq(MatchConfig.to_json({"scenario": "mars", "fog": false}), "{\"scenario\":\"kestrel\",\"seed\":2026,\"difficulty\":\"normal\",\"fog\":false}", "an unknown map falls back to Kestrel, missing keys to the defaults")
	t.eq(MatchConfig.display_name("kestrel"), "Kestrel Reach", "Kestrel name")
	t.eq(MatchConfig.display_name("survival"), "Earthfront Survival", "Survival name")
	t.eq(MatchConfig.running({}), "", "no snapshot: unknown")
	var g := Stub.new()
	g.use_kestrel()
	t.eq(MatchConfig.running(g.bridge_snapshot), "kestrel", "a Core Node means Kestrel Reach")
	t.eq(MatchConfig.running({"tick": 0, "entities": []}), "survival", "no Core Node: Survival")
	t.ok(not MatchConfig.write("", MatchConfig.defaults()), "no runtime directory: nothing written")


func test_current_and_auto_deploy_live_in_engine_meta(t) -> void:
	MatchConfig.reset()
	t.eq(MatchConfig.current, MatchConfig.defaults(), "the defaults until a match is chosen")
	t.ok(not MatchConfig.pending_auto_deploy(), "no auto deploy by default")
	var cfg := MatchConfig.defaults()
	cfg.scenario = "survival"
	MatchConfig.current = cfg
	cfg.scenario = "kestrel"  # a later edit of the caller's copy does not leak into the stored config
	t.eq(MatchConfig.current.scenario, "survival", "kept")
	t.eq(Engine.get_meta("match_config").scenario, "survival", "across the scene reload, in Engine meta")
	MatchConfig.set_auto_deploy(true)
	t.ok(MatchConfig.pending_auto_deploy() and Engine.get_meta("auto_deploy"), "auto deploy pending")
	MatchConfig.set_auto_deploy(false)
	t.ok(not MatchConfig.pending_auto_deploy(), "cleared")
	MatchConfig.reset()
	t.ok(not Engine.has_meta("match_config") and not Engine.has_meta("auto_deploy"), "reset leaves no meta")


func test_picker_vm_has_two_cards_with_kestrel_first(t) -> void:
	var vm := LiveScreens.picker_vm("kestrel")
	t.eq(vm.cards.map(func(c): return c.id), ["kestrel", "survival"], "Kestrel first")
	t.eq(vm.cards.map(func(c): return c.name), ["Kestrel Reach", "Earthfront Survival"], "named by MatchConfig")
	t.eq(vm.cards.map(func(c): return c.selected), [true, false], "one selected")
	t.eq(LiveScreens.picker_vm("survival").cards.map(func(c): return c.selected), [false, true], "the other")
	var root := Control.new()
	var got: Array = []
	MapPicker.build(root, vm, func(name, arg): got.append([name, arg]))
	t.ok(U.button_with(root, "Kestrel Reach") != null and U.button_with(root, "Earthfront Survival") != null, "each card is a click target named after its map")
	U.button_with(root, "Earthfront Survival").pressed.emit()
	U.button_with(root, "Back").pressed.emit()
	U.button_with(root, "Deploy forces").pressed.emit()
	t.eq(got, [["pick", "survival"], ["back", null], ["confirm", null]], "pick, back, confirm")
	t.ok(U.has_text(root, "Fog of war") and U.has_text(root, "Full battlefield"), "the cards say what differs")
	root.free()
	var empty := Control.new()
	MapPicker.build(empty, {}, Callable())
	t.eq(empty.get_child_count(), 0, "nothing for {}")
	empty.free()


func test_new_operation_opens_the_picker_and_back_closes_it(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	_press(ui.title, "New operation")
	t.ok(ui.picker_open, "the picker is up")
	t.eq(g.calls, [], "nothing reaches the game yet")
	t.eq(_enabled(ui.layer, "Deploy forces").size(), 1, "one enabled Deploy forces: the picker's (the title's waits under the scrim)")
	t.ok(U.has_text(ui.picker_layer, "Kestrel Reach"), "Kestrel Reach offered")
	t.eq(ui.picker_choice, "kestrel", "Kestrel is the default")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.physical_keycode = KEY_RIGHT
	right.pressed = true
	t.ok(ui.route_title_key(right), "the right arrow is the picker's")
	t.eq(ui.picker_choice, "survival", "and moves the selection")
	t.ok(U.has_text(ui.picker_layer, "Selected"), "redrawn")
	t.ok(ui.route_title_key(esc), "Esc is the picker's")
	t.ok(not ui.picker_open and ui.picker_layer.get_child_count() == 0, "Esc closes it")
	_press(ui.title, "New operation")
	_press(ui.picker_layer, "Back")
	t.ok(not ui.picker_open, "Back closes it")
	t.ok(not ui.title.menu_buttons()[1].disabled, "New operation is enabled again")
	t.ok(not FileAccess.file_exists(DIR.path_join("match.json")), "closing writes nothing")
	_drop(p)


func test_confirming_survival_writes_the_files_and_deploys_after_the_bridge_took_the_flag(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	_press(ui.title, "New operation")
	_press(ui.picker_layer, "Earthfront Survival")
	t.eq(ui.picker_choice, "survival", "Survival selected")
	_press(ui.picker_layer, "Deploy forces")
	t.eq(_parsed("match.json").scenario, "survival", "match.json names the chosen map")
	t.eq(_parsed("match.json").fog, true, "and keeps the fog choice")
	t.ok(FileAccess.file_exists(DIR.path_join("restart.flag")), "restart.flag asks the bridge to rebuild")
	t.eq(MatchConfig.current.scenario, "survival", "the running match's config")
	t.ok(not ui.picker_open, "the picker closed")
	ui.process(0.5)
	t.eq(g.calls, [], "no deploy while the bridge has not taken the flag")
	DirAccess.remove_absolute(DIR.path_join("restart.flag"))  # the bridge restarts and removes it
	ui.process(0.05)
	t.eq(g.calls, [], "and not before 0.1 s more")
	ui.process(0.06)
	t.eq(g.calls, [["deploy"]], "then the mission deploys, without a scene reload")
	ui.process(0.5)
	t.eq(g.calls, [["deploy"]], "once")
	t.ok(not MatchConfig.pending_auto_deploy(), "no auto deploy left behind")
	_drop(p)


func test_switching_away_from_the_map_on_screen_reloads_and_auto_deploys(t) -> void:
	var p := _make(t, true)  # the title scene already drew Kestrel's ground: a new map needs a fresh scene
	var g = p[0]
	var ui = p[1]
	_press(ui.title, "New operation")
	t.eq(ui.picker_choice, "kestrel", "the map on screen is preselected")
	_press(ui.picker_layer, "Earthfront Survival")
	_press(ui.picker_layer, "Deploy forces")
	t.eq(_parsed("match.json").scenario, "survival", "match.json written first")
	t.eq(g.calls, [["restart"]], "the existing restart: restart.flag, then the scene reloads")
	t.ok(MatchConfig.pending_auto_deploy(), "the fresh title deploys by itself")
	_drop(p)


func test_auto_deploy_waits_for_the_flag_tick_0_and_the_chosen_map(t) -> void:
	var p := _make(t, true)
	var g = p[0]
	var ui = p[1]
	var cfg := MatchConfig.defaults()
	cfg.scenario = "survival"
	MatchConfig.current = cfg
	MatchConfig.set_auto_deploy(true)
	g.bridge_snapshot["tick"] = 0
	ui.process(0.2)
	t.eq(g.calls, [], "the bridge still serves Kestrel: wait")
	cfg.scenario = "kestrel"
	MatchConfig.current = cfg
	FileAccess.open(DIR.path_join("restart.flag"), FileAccess.WRITE).store_line("restart")
	ui.process(0.2)
	t.eq(g.calls, [], "restart.flag still there: wait")
	DirAccess.remove_absolute(DIR.path_join("restart.flag"))
	g.bridge_snapshot["tick"] = 31
	ui.process(0.2)
	t.eq(g.calls, [], "an old sim past tick 0: wait")
	g.bridge_snapshot["tick"] = 0
	ui.process(0.2)
	t.eq(g.calls, [["deploy"]], "fresh Kestrel at tick 0: deploy")
	t.ok(not MatchConfig.pending_auto_deploy(), "consumed")
	_drop(p)


func test_debrief_restart_replays_the_match_and_main_menu_does_not_deploy(t) -> void:
	var p := _make(t, true)
	var g = p[0]
	var ui = p[1]
	ui.begin_operation()
	g.bridge_winner = 1
	ui.show_debrief()
	var labels: Array = U.buttons(ui.scrim).map(func(b): return b.text).filter(func(s): return s != "")
	t.eq(labels, ["Review battlefield", "Restart", "Main menu", "Quit"], "the debrief's buttons")
	ui._on_debrief_action("restart", null)
	t.eq(g.calls, [["restart"]], "Restart reaches the game's restart")
	t.eq(_parsed("match.json").scenario, "kestrel", "with the running map")
	t.eq(int(_parsed("match.json").seed), 2026, "and the same seed")
	t.ok(MatchConfig.pending_auto_deploy(), "and deploys again after the reload")
	ui._on_debrief_action("menu", null)
	t.eq(g.calls, [["restart"], ["restart"]], "Main menu is the restart to the title")
	t.ok(not MatchConfig.pending_auto_deploy(), "without the auto deploy")
	_drop(p)
