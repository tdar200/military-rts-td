extends RefCounted
## M and the strategic map, the terrain guide in the pause menu, the first-minutes briefing, and the F1 / Science guard,
## through the real GameUI over the stub game (Kestrel snapshot).
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Stub = preload("res://tests/stub_game.gd")
const U = preload("res://tests/section_util.gd")


func _make(t, kestrel := true) -> Array:
	var g := Stub.new()
	g.viewport = t.root
	if kestrel:
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


func _pauses(g) -> Array:
	return g.calls.filter(func(c): return c[0] == "pause")


func _click(root: Node, text: String) -> void:
	U.button_with(root, text).pressed.emit()


# ------------------------------------------------------------------ strategic map

func test_m_opens_the_map_and_esc_closes_it_without_pausing(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	t.ok(ui.route_key(_key(KEY_M)), "M is used by the UI")
	t.ok(ui.region_open and ui.world_blocked(), "the map is open and the world takes no input")
	t.ok(not ui.paused(), "the map is not a pause")
	t.eq(_pauses(g), [], "the simulation is not told to stop")
	t.ok(U.has_text(ui.region_layer, "Strategic map"), "the map is on screen")
	t.ok(U.button_with(ui.region_layer, "Hex grid") != null, "with its lens Buttons")
	t.ok(ui.blocks_point(Vector2(900, 500)), "a click on the map does not reach the 3D scene")
	t.eq(ui.escape_route(false), "close_region", "Esc closes the map first")
	t.ok(ui.route_key(_key(KEY_ESCAPE)), "Esc is used by the UI")
	t.ok(not ui.region_open and not ui.world_blocked(), "closed")
	t.eq(ui.region_layer.get_child_count(), 0, "its nodes are freed")
	t.ok(not ui.pause_open, "Esc did not also open the pause menu")
	_drop(p)


func test_m_again_closes_the_map_and_the_close_button_too(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.route_key(_key(KEY_M))
	t.ok(ui.route_key(_key(KEY_M)), "M again")
	t.ok(not ui.region_open, "closes it")
	ui.route_key(_key(KEY_M))
	_click(ui.region_layer, "Close")
	t.ok(not ui.region_open, "the Close Button closes it")
	_drop(p)


func test_m_does_nothing_without_a_ground_or_over_other_screens(t) -> void:
	var bare := _make(t, false)
	bare[1].route_key(_key(KEY_M))
	t.ok(not bare[1].region_open and bare[1].region_layer.get_child_count() == 0, "no snapshot, no map")
	_drop(bare)
	var p := _make(t)
	var ui = p[1]
	ui.research.visible = true
	t.ok(not ui.route_key(_key(KEY_M)) and not ui.region_open, "M does not open over the Science modal")
	ui.research.visible = false
	ui.open_pause()
	t.ok(not ui.route_key(_key(KEY_M)) and not ui.region_open, "M does not open over the pause menu")
	ui.close_pause()
	ui.show_debrief()
	t.ok(not ui.route_key(_key(KEY_M)) and not ui.region_open, "M does not open over the debrief")
	_drop(p)


func test_lens_buttons_toggle_and_redraw(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.route_key(_key(KEY_M))
	t.ok(U.has_text(ui.region_layer, "Enemy territory"), "Borders lens is on by default")
	_click(ui.region_layer, "Borders")
	t.ok(not ui.lens_on["bdr"], "the lens state flipped")
	t.ok(not U.has_text(ui.region_layer, "Enemy territory"), "and the label is gone")
	_click(ui.region_layer, "Resources")
	t.ok(ui.lens_on["res"], "Resources lens on")
	t.ok(ui.region_open, "toggling a lens keeps the map open")
	_drop(p)


func test_the_map_redraws_only_when_something_changed(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.route_key(_key(KEY_M))
	var first: Node = ui.region_layer.get_child(0)
	ui._refresh_region()
	t.ok(ui.region_layer.get_child(0) == first, "an unchanged snapshot keeps the drawn nodes")
	g.bridge_snapshot["construction_zone"].append([1, 1])
	ui._refresh_region()
	t.ok(ui.region_layer.get_child(0) != first, "a changed construction zone redraws")
	_drop(p)


func test_focus_deposit_closes_the_map_and_centres_the_camera(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.route_key(_key(KEY_M))
	ui._on_region_action("focus_deposit", [10, 10])
	t.ok(not ui.region_open, "a pin click leaves the map")
	_drop(p)


func test_the_game_gates_world_input_on_the_map_too(t) -> void:
	var src: String = (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.ok(src.contains("if ui.world_blocked():\n\t\treturn"), "the input handler stops at the map as at the pause menu")
	t.ok(src.contains("if not ui.world_blocked():\n\t\t_update_camera_controls(delta)"), "the camera stays put under the map")


# ------------------------------------------------------------------ the Science modal and F1

func test_f1_does_not_open_the_controls_over_the_science_modal(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.research.visible = true
	t.ok(not ui.route_key(_key(KEY_F1)), "F1 is left alone while Science is up")
	t.ok(not ui.controls_open and not ui.paused(), "no controls screen")
	t.eq(_pauses(g), [], "and no pause")
	ui.research.visible = false
	t.ok(ui.route_key(_key(KEY_F1)) and ui.controls_open, "with the modal closed F1 works as before")
	_drop(p)


# ------------------------------------------------------------------ terrain guide in the pause menu

func test_pause_menu_opens_the_guide_and_back_returns_to_the_menu(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.route_key(_key(KEY_ESCAPE))
	t.ok(U.button_with(ui.pause_layer, "Terrain guide") != null, "the Codex entry is a Button with human text in the pause menu")
	_click(ui.pause_layer, "Terrain guide")
	t.ok(ui.guide_open and ui.pause_open, "the guide is up over the paused game")
	t.ok(U.has_text(ui.pause_layer, "Grassland") and U.has_text(ui.pause_layer, "Rules of thumb"), "with the real cards")
	t.eq(ui.escape_route(false), "close_guide", "Esc backs out of the guide first")
	ui.route_key(_key(KEY_ESCAPE))
	t.ok(not ui.guide_open and ui.pause_open, "Esc returned to the menu, not to the game")
	t.ok(U.button_with(ui.pause_layer, "Resume") != null, "the menu is back")
	_click(ui.pause_layer, "Terrain guide")
	_click(ui.pause_layer, "Back")
	t.ok(not ui.guide_open and ui.pause_open, "the Back Button does the same")
	_click(ui.pause_layer, "Terrain guide")
	ui.close_pause()
	t.ok(not ui.guide_open, "resuming clears the guide state")
	t.eq(_pauses(g).back(), ["pause", false], "and the simulation runs")
	_drop(p)


func test_pause_menu_has_no_guide_entry_without_a_table(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	g.bridge_snapshot.erase("ground_table")
	ui.route_key(_key(KEY_ESCAPE))
	t.ok(U.button_with(ui.pause_layer, "Terrain guide") == null, "no ground_table, no entry")
	ui.open_guide()
	t.ok(not ui.guide_open, "and the guide cannot be opened")
	_drop(p)


func test_can_guide_is_a_cheap_table_check_that_agrees_with_the_guide(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	t.ok(ui._can_guide() and not ui._guide_vm().is_empty(), "a named ground_table row: the guide can open")
	t.ok(ui._pause_vm()["can_guide"], "and the pause menu offers it")
	g.bridge_snapshot["ground_table"] = [{"glyph": "g"}]
	t.ok(not ui._can_guide() and ui._guide_vm().is_empty(), "rows without names build nothing, so no entry")
	g.bridge_snapshot["ground_table"] = []
	t.ok(not ui._can_guide() and ui._guide_vm().is_empty(), "an empty table: no entry")
	g.bridge_snapshot.erase("ground_table")
	t.ok(not ui._can_guide() and not ui._pause_vm()["can_guide"], "no table: no entry")
	var src: String = (load("res://scripts/ui/game_ui.gd") as GDScript).source_code
	t.ok(src.contains('vm["can_guide"] = _can_guide()'), "the 0.1 s pause refresh never builds the guide")
	_drop(p)


func test_the_debrief_closes_an_open_map_so_esc_cannot_reach_it(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.route_key(_key(KEY_M))
	t.ok(ui.region_open, "the map is open")
	ui.show_debrief()
	t.ok(not ui.region_open, "the debrief closes it")
	t.eq(ui.region_layer.get_child_count(), 0, "and its nodes are freed")
	t.ok(ui.escape_route(false) != "close_region", "Esc under the scrim no longer targets the map")
	_drop(p)


## Survival's bridge emits an all-Grassland ground layer plus a named ground_table row; the client has no ground model for it.
func _make_flat(t) -> Array:
	var p := _make(t)
	var g = p[0]
	var cells: int = int(g.bridge_snapshot["map_width"]) * int(g.bridge_snapshot["map_height"])
	g.bridge_snapshot["ground"] = "g".repeat(cells)
	g.ground_model = null
	return p


func test_survival_flat_ground_offers_no_terrain_guide(t) -> void:
	var p := _make_flat(t)
	var g = p[0]
	var ui = p[1]
	t.ok(not ui._can_guide(), "a named table row on flat ground is not enough: nothing to guide")
	t.ok(not ui._pause_vm()["can_guide"], "the pause view model does not offer it")
	ui.route_key(_key(KEY_ESCAPE))
	t.ok(U.button_with(ui.pause_layer, "Terrain guide") == null, "no dead Terrain guide button on Survival")
	ui.open_guide()
	t.ok(not ui.guide_open, "and the guide cannot be opened")
	for i in 20:
		ui._can_guide()
		ui._refresh_briefing()
	t.eq(ui._ground_decodes, 1, "the flat layer is decoded once, not on every refresh")
	_drop(p)


# ------------------------------------------------------------------ briefing

func test_the_briefing_shows_in_the_first_stages_and_hides_for_good(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	g.world_art_on = false  # the tutorial's briefing; with world art on Kestrel has its own (test_kestrel_objectives.gd)
	g.tutorial_stage = 1
	ui._refresh_briefing()
	t.ok(U.has_text(ui.briefing_layer, "Power the beachhead"), "the briefing is up at stage 1")
	t.ok(ui.adapter.briefing_up, "the HUD is told, so it leaves its objectives panel out")
	t.ok(ui.blocks_point(Vector2(100, 150)), "the card takes clicks over its own rectangle")
	t.ok(not ui.blocks_point(Vector2(1000, 300)), "and none outside it")
	_click(ui.briefing_layer, "Hide")
	t.eq(ui.briefing_layer.get_child_count(), 0, "Hide frees the card")
	t.ok(not ui.adapter.briefing_up and not ui.blocks_point(Vector2(100, 150)), "it never blocks input afterwards")
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "and does not come back")
	_drop(p)


func test_the_briefing_follows_the_stage_and_ends_with_the_first_group(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	g.world_art_on = false  # the tutorial's briefing; with world art on Kestrel has its own (test_kestrel_objectives.gd)
	g.tutorial_stage = 0
	ui._refresh_briefing()
	t.ok(U.has_text(ui.briefing_layer, "Secure the landing zone"), "stage 0")
	g.tutorial_stage = 2
	ui._refresh_briefing()
	t.ok(U.has_text(ui.briefing_layer, "Establish income"), "stage 2")
	g.tutorial_stage = 3
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "gone after the first group")
	t.ok(not ui.blocks_point(Vector2(100, 150)), "and it blocks nothing")
	g.tutorial_stage = 1
	g.bridge_winner = 0
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "no briefing once the match is decided")
	_drop(p)


func test_the_hud_drops_its_objectives_while_the_briefing_is_up(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	g.tutorial_stage = 1
	ui.adapter.tab = "units"  # the main layout carries the objectives panel
	ui.adapter.briefing_up = false
	t.ok(ui.adapter.hud_vm(0.0).has("objectives"), "without the briefing the objectives panel is there")
	ui.adapter.briefing_up = true
	var vm: Dictionary = ui.adapter.hud_vm(0.0)
	t.ok(not vm.has("objectives"), "with the briefing the card carries the objectives")
	if vm.has("territory"):
		t.ok(float(vm["territory"]["y"]) >= 316.0 + 8.0, "the territory card sits below the briefing")
	_drop(p)


func test_pause_flag_is_cleared_when_the_game_starts(t) -> void:
	var src: String = (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	var ready_at := src.find("func _ready() -> void:")
	var arg_at := src.find("runtime_directory = argument.trim_prefix", ready_at)
	var clear_at := src.find("set_sim_paused(false)", ready_at)
	var next_func := src.find("\nfunc ", ready_at + 10)
	t.ok(arg_at > 0 and clear_at > arg_at and clear_at < next_func, "_ready removes a stale pause.flag after reading --runtime-dir, with the same path logic as set_sim_paused")
	var dir := OS.get_cache_dir().path_join("rts_pause_flag_ready_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var flag := FileAccess.open(dir.path_join("pause.flag"), FileAccess.WRITE)
	flag.store_line("pause")
	flag = null
	var game = (load("res://scripts/earthfront_3d.gd") as GDScript).new()
	game.runtime_directory = dir
	game.set_sim_paused(false)
	t.ok(not FileAccess.file_exists(dir.path_join("pause.flag")), "a stale flag left by a crash is removed by the call _ready makes")
	game.free()
	DirAccess.remove_absolute(dir)


func test_survival_flat_ground_shows_no_briefing_card(t) -> void:
	var p := _make_flat(t)
	var g = p[0]
	var ui = p[1]
	g.tutorial_stage = 1
	ui._refresh_briefing()
	t.eq(ui.briefing_layer.get_child_count(), 0, "no briefing card without real terrain")
	t.ok(not ui.adapter.briefing_up, "and the HUD keeps its objectives panel")
	_drop(p)
