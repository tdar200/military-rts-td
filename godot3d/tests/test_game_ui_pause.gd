extends RefCounted
## Esc and F1 routing, the pause freeze and the restart path, through the real GameUI over the stub game.
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Stub = preload("res://tests/stub_game.gd")
const U = preload("res://tests/section_util.gd")


func _make(t) -> Array:
	var g := Stub.new()
	g.viewport = t.root
	g.use_kestrel()
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	return [g, ui]


func _drop(p: Array) -> void:
	p[1].free()


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _click(ui, text: String, nth := 0) -> void:
	var matches: Array = []
	for b in U.buttons(ui.pause_layer):
		if (b as Button).text == text:
			matches.append(b)
	matches.sort_custom(func(a, b): return a.position.y < b.position.y)
	(matches[nth] as Button).pressed.emit()


func _pauses(g) -> Array:
	return g.calls.filter(func(c): return c[0] == "pause")


# ------------------------------------------------------------------ Esc

func test_esc_with_nothing_armed_opens_the_pause_menu_and_again_resumes(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc is used by the UI")
	t.ok(ui.pause_open and ui.paused(), "paused")
	t.eq(_pauses(g), [["pause", true]], "the simulation is told to stop")
	t.ok(U.button_with(ui.pause_layer, "Resume") != null, "the menu is on screen with a Resume Button")
	t.ok(U.has_text(ui.pause_layer, "Kestrel Reach"), "and shows the Kestrel snapshot")
	t.ok(ui.blocks_point(Vector2(900, 500)), "the paused game takes no mouse input")
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc again")
	t.ok(not ui.paused(), "resumed")
	t.eq(_pauses(g), [["pause", true], ["pause", false]], "the simulation is told to run again")
	t.eq(ui.pause_layer.get_child_count(), 0, "the menu is gone")
	_drop(p)


func test_esc_precedence(t) -> void:
	var p := _make(t)
	var ui = p[1]
	t.eq(ui.escape_route(false), "open_pause", "nothing open, nothing armed")
	t.eq(ui.escape_route(true), "cancel_orders", "armed orders are cancelled before the menu opens")
	ui.research.visible = true
	t.eq(ui.escape_route(true), "close_research", "the Science modal closes before armed orders cancel")
	t.ok(not ui.route_key(_key(KEY_ESCAPE), true), "the handler keeps the research and cancel cases")
	t.ok(not ui.route_key(_key(KEY_ESCAPE), false), "Esc with the modal open does not open the menu")
	t.ok(not ui.paused(), "still playing")
	ui.research.visible = false
	t.ok(not ui.route_key(_key(KEY_ESCAPE), true), "armed: left to the existing cancel")
	t.ok(not ui.paused(), "an armed Esc never opens the pause menu")
	ui.open_pause()
	ui._on_pause_action("ask_restart")
	t.eq(ui.escape_route(false), "close_confirm", "confirm closes first")
	ui._on_pause_action("open_controls")
	t.eq(ui.escape_route(true), "close_controls", "the controls screen closes before anything else")
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc closes controls")
	t.ok(ui.pause_open and not ui.controls_open and ui.confirm == "restart", "back to the menu with the confirm still up")
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc closes the confirm")
	t.ok(ui.pause_open and ui.confirm == "", "the menu stays")
	t.eq(ui.escape_route(false), "resume", "then Esc resumes")
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc resumes")
	t.ok(not ui.paused(), "playing")
	_drop(p)


func test_esc_does_nothing_before_deploy_or_under_the_debrief(t) -> void:
	var g := Stub.new()
	g.viewport = t.root
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	t.ok(not ui.route_key(_key(KEY_ESCAPE), false), "the title screen is up: Esc is not ours")
	t.ok(not ui.route_key(_key(KEY_F1), false), "nor F1")
	t.ok(not ui.paused(), "not paused")
	ui.begin_operation()
	ui.show_debrief()
	t.eq(ui.escape_route(false), "none", "the debrief owns the screen")
	t.ok(not ui.route_key(_key(KEY_ESCAPE), false), "Esc is left alone")
	t.ok(not ui.route_key(_key(KEY_F1), false), "F1 is left alone")
	ui.free()


# ------------------------------------------------------------------ F1

func test_f1_opens_controls_over_play_and_pauses(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	t.ok(ui.route_key(_key(KEY_F1), false), "F1 is used")
	t.ok(ui.controls_open and not ui.pause_open and ui.paused(), "the controls screen, paused behind it")
	t.eq(_pauses(g), [["pause", true]], "F1 stops the simulation too")
	t.ok(U.has_text(ui.pause_layer, "Controls") and U.button_with(ui.pause_layer, "Back") != null, "the reference is up")
	t.ok(ui.route_key(_key(KEY_F1), false), "F1 again")
	t.ok(not ui.paused(), "closed and playing")
	t.eq(_pauses(g), [["pause", true], ["pause", false]], "and running again")
	ui.route_key(_key(KEY_F1), false)
	t.ok(ui.route_key(_key(KEY_ESCAPE), false), "Esc closes it as well")
	t.ok(not ui.paused(), "playing")
	_drop(p)


func test_controls_from_the_menu_return_to_the_menu(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.open_pause()
	_click(ui, "Controls")
	t.ok(ui.controls_open and ui.pause_open, "controls over the menu")
	t.ok(U.has_text(ui.pause_layer, "Pause / Controls"), "with the pause breadcrumb")
	_click(ui, "Back")
	t.ok(not ui.controls_open and ui.pause_open, "Back returns to the menu, still paused")
	t.ok(U.button_with(ui.pause_layer, "Resume") != null, "the menu is drawn again")
	t.eq(_pauses(g), [["pause", true]], "never resumed on the way")
	ui.route_key(_key(KEY_F1), false)
	t.ok(ui.controls_open, "F1 in the menu opens controls")
	ui.route_key(_key(KEY_F1), false)
	t.ok(not ui.controls_open and ui.pause_open, "and F1 closes them back to the menu")
	_drop(p)


# ------------------------------------------------------------------ freeze

func test_a_paused_hud_does_not_update_and_the_alert_clock_stands_still(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.process(0.2)
	var chip: int = ui.hud.get_node("build_top").get_child(0).get_instance_id()
	var clock: float = ui._clock
	ui.open_pause()
	g.bridge_money = 5
	ui.process(0.5)
	ui.process(0.5)
	t.eq(ui.hud.get_node("build_top").get_child(0).get_instance_id(), chip, "no HUD rebuild while paused")
	t.near(ui._clock, clock, 0.0001, "the notification clock stands still")
	ui.close_pause()
	ui.process(0.05)
	t.ok(ui.hud.get_node("build_top").get_child(0).get_instance_id() != chip, "the HUD redraws on the first frame back")
	_drop(p)


func test_the_process_is_not_frozen_the_menu_stays_live(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.open_pause()
	var before := U.has_text(ui.pause_layer, "Simulation stopped")
	t.ok(before, "stopped while the tick stands still")
	g.bridge_tick += 100  # a bridge that ignores pause.flag
	ui.process(0.2)
	t.ok(U.has_text(ui.pause_layer, "Simulation still running"), "the marker tells the truth when the tick keeps moving")
	_click(ui, "Resume")
	t.ok(not ui.paused(), "buttons keep working: the menu is not frozen")
	_drop(p)


# ------------------------------------------------------------------ restart and quit

func test_restart_needs_the_confirm_and_uses_the_existing_restart(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.open_pause()
	_click(ui, "Restart mission")
	t.eq(ui.confirm, "restart", "the menu button only asks")
	t.ok(not g.calls.any(func(c): return c[0] == "restart"), "nothing restarted yet")
	_click(ui, "Keep playing")
	t.eq(ui.confirm, "", "Keep playing closes the question")
	t.ok(ui.pause_open and not g.calls.any(func(c): return c[0] == "restart"), "still paused, still not restarted")
	_click(ui, "Restart mission")
	_click(ui, "Restart")
	t.eq(g.calls.filter(func(c): return c[0] == "restart"), [["restart"]], "the confirm button calls the game's _restart_mission once")
	t.ok(not ui.paused(), "the pause screens are closed")
	t.eq(_pauses(g).back(), ["pause", false], "the simulation flag is lifted before the restart")
	_drop(p)


func test_quit_only_asks_in_a_test(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.open_pause()
	_click(ui, "Quit game")
	t.eq(ui.confirm, "quit", "Quit asks first")
	t.ok(U.has_text(ui.pause_layer, "Quit the game?"), "the quit question is up")
	_click(ui, "Keep playing")
	t.eq(ui.confirm, "", "and can be declined")
	_drop(p)


func test_a_stub_game_without_restart_hides_the_button(t) -> void:
	# The stub's own source with `_restart_mission` renamed away: a game with no restart command at all.
	var src: String = (load("res://tests/stub_game.gd") as GDScript).source_code.replace("func _restart_mission()", "func _renamed_restart()")
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	var g = script.new()
	t.ok(not g.has_method("_restart_mission"), "the stub really has no restart")
	g.viewport = t.root
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	ui.open_pause()
	t.ok(U.button_with(ui.pause_layer, "Restart") == null, "no restart command, no Restart button")
	t.ok(U.button_with(ui.pause_layer, "Resume") != null, "the rest of the menu works")
	ui.free()


# ------------------------------------------------------------------ the game's handler, at source level

func test_the_game_routes_keys_through_the_ui_before_anything_else(t) -> void:
	var script: GDScript = load("res://scripts/earthfront_3d.gd")
	t.ok(script.can_instantiate(), "earthfront_3d.gd still compiles")
	var src: String = script.source_code
	var i_route := src.find("if ui.route_key(event, _orders_armed()):")
	var i_paused := src.find("if ui.paused():\n\t\treturn")
	var i_science := src.find("if science_overlay and science_overlay.visible:")
	var i_mouse := src.find("if event is InputEventMouseMotion and dragging:")
	t.ok(i_route > 0 and i_route < i_paused and i_paused < i_science and i_science < i_mouse, "route_key, then the paused gate, then the Science modal, then the world")
	t.ok(src.contains("func _orders_armed() -> bool:\n\treturn attack_move_armed or rally_armed or build_mode != \"\""), "armed means attack-move, rally or a placement")
	t.ok(src.contains("elif event.keycode == Keybinds.CANCEL:"), "the armed-order cancel is still there")
	t.ok(src.contains("\"pause.flag\""), "the pause reaches the bridge through pause.flag")
	t.ok(src.contains("if not ui.paused():\n\t\t_update_camera_controls(delta)"), "the camera does not pan under the menu")
	var ui_src: String = (load("res://scripts/ui/game_ui.gd") as GDScript).source_code
	t.ok(ui_src.contains("Keybinds.CONTROLS") and ui_src.contains("Keybinds.CANCEL"), "game_ui routes the keys through the constants")


func test_set_sim_paused_writes_and_removes_the_flag(t) -> void:
	var dir := OS.get_cache_dir().path_join("rts_pause_flag_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var game = (load("res://scripts/earthfront_3d.gd") as GDScript).new()  # not in the tree: _ready never runs
	game.runtime_directory = dir
	var path := dir.path_join("pause.flag")
	game.set_sim_paused(true)
	t.ok(FileAccess.file_exists(path), "pausing creates pause.flag where the bridge looks")
	game.set_sim_paused(false)
	t.ok(not FileAccess.file_exists(path), "resuming removes it")
	game.set_sim_paused(false)
	t.ok(not FileAccess.file_exists(path), "resuming twice is harmless")
	game.free()
	DirAccess.remove_absolute(dir)
