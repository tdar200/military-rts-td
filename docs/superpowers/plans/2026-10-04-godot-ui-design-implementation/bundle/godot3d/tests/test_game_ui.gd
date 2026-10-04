extends RefCounted
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Stub = preload("res://tests/stub_game.gd")


func _make(t) -> Array:
	var g := Stub.new()
	g.viewport = t.root
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	return [g, ui]


func _drop(p: Array) -> void:
	p[1].free()


func test_title_first_then_hud_after_deploy(t) -> void:
	var p := _make(t)
	var ui = p[1]
	t.ok(ui.title.visible and not ui.hud.visible, "the title is up and the HUD is hidden before deploy")
	t.ok(ui.blocks_point(Vector2(900, 500)), "the title blocks the whole screen")
	var deploy: Button
	for b in ui.title.find_children("*", "Button", true, false):
		if b.text == "Deploy forces":
			deploy = b
	t.ok(deploy != null and not deploy.disabled, "Deploy forces is an enabled button")
	deploy.pressed.emit()
	t.eq(p[0].calls, [["deploy"]], "deploy reaches the game")
	ui.begin_operation()
	t.ok(ui.hud.visible and ui.title == null, "the HUD takes over")
	t.ok(not ui.blocks_point(Vector2(900, 500)), "open ground is free once the title is gone")
	_drop(p)


func test_vm_is_throttled_and_skipped_during_a_hud_click(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.begin_operation()
	ui.process(0.02)
	t.ok(ui.hud.get_node("build_top").get_child_count() > 0, "first frame draws the HUD (Build layout is the default tab)")
	var before: int = ui.hud.get_node("build_top").get_child(0).get_instance_id()
	p[0].bridge_money = 5
	ui.process(0.02)
	t.eq(ui.hud.get_node("build_top").get_child(0).get_instance_id(), before, "no rebuild inside 100 ms")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	ui._input(down)
	p[0].mouse = Vector2(300, 30)  # inside the top bar
	ui.process(0.2)
	t.eq(ui.hud.get_node("build_top").get_child(0).get_instance_id(), before, "no rebuild while a click is held over the HUD")
	p[0].mouse = Vector2(900, 500)  # open ground: a drag-select must not freeze the HUD
	ui.process(0.2)
	t.ok(ui.hud.get_node("build_top").get_child(0).get_instance_id() != before, "rebuild resumes once the pointer is over open ground")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	ui._input(up)
	_drop(p)


func test_minimap_is_mounted_in_the_map_slot_and_follows_it(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.begin_operation()
	ui.process(0.2)
	t.eq(ui.minimap_view.get_parent(), ui.hud.map_slot, "mounted in the slot")
	t.eq(ui.minimap_view.size, ui.hud.map_slot.size, "same size as the slot")
	var rect: Rect2 = ui.minimap_world_rect()
	t.near(rect.size.y, 35.0, 0.01, "vertical span")
	t.near(rect.size.x / rect.size.y, ui.hud.map_slot.size.x / ui.hud.map_slot.size.y, 0.001, "slot aspect")
	t.near(rect.position.x + rect.size.x * 0.5, 16.7, 0.01, "centred on the map")
	p[0].mouse = Vector2(900, 500)
	ui.adapter.tab = "orders"
	ui.process(0.2)
	t.eq(ui.minimap_view.size, Vector2(288, 250), "follows the slot back to the Main layout")
	_drop(p)


func test_tab_names_map_to_the_adapter(t) -> void:
	var p := _make(t)
	p[1].set_tab("ORDERS".to_lower())
	t.eq(p[1].adapter.tab, "orders", "orders")
	p[1].set_tab("science")
	t.eq(p[1].adapter.tab, "orders", "science is not a deck tab")
	_drop(p)


func test_debrief_blocks_input_and_both_buttons_work(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.begin_operation()
	p[0].bridge_winner = 0
	ui.show_debrief()
	t.ok(ui.blocks_point(Vector2(900, 500)), "the scrim blocks the scene")
	ui.show_debrief()
	t.eq(ui.layer.get_children().filter(func(c): return c is ColorRect).size(), 1, "a second call adds no second scrim")
	ui._on_debrief_action("restart", null)
	t.eq(p[0].calls.back(), ["restart"], "restart reaches the game")
	ui._on_debrief_action("review", null)
	t.ok(ui.scrim == null, "review drops the scrim")
	_drop(p)


func test_notifications_reach_the_hud(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.begin_operation()
	ui.adapter.tab = "orders"
	ui.notify("WAVE COMMITTED", "SIEGE, 14 UNITS", Color("f04e46"))
	ui.process(0.2)
	t.ok(ui.hud.get_node("alerts").get_child_count() > 0, "toast drawn")
	_drop(p)


func _options() -> Array:
	return [
		{"id": 1, "name": "Batteries", "branch": 1, "step": 0, "reality": "Achieved", "money": 100, "duration": 900, "unlocks": "System: Storage", "available": true, "researched": false, "prerequisites": ""},
		{"id": 2, "name": "Smart grids", "branch": 1, "step": 1, "reality": "Emerging", "money": 140, "duration": 1200, "unlocks": "System: Power", "available": false, "researched": false, "prerequisites": "Batteries"},
	]


func test_research_modal_opens_blocks_and_starts_a_project(t) -> void:
	var p := _make(t)
	var ui = p[1]
	p[0].bridge_research_options = _options()
	ui.begin_operation()
	t.ok(not ui.research_open(), "closed at first")
	ui.toggle_research()
	t.ok(ui.research_open() and ui.blocks_point(Vector2(900, 500)), "open: blocks the scene")
	var card: Button
	for b in ui.research.find_children("*", "Button", true, false):
		if b.text.begins_with("Batteries"):
			card = b
	t.ok(card != null, "the Batteries card is a button")
	card.pressed.emit()
	t.eq(p[0].calls.back(), ["research", 1], "one click on an available project starts it")
	t.ok(not ui.research_open(), "the modal closes after starting")
	ui.toggle_research()
	ui._on_research_action("close", null)
	t.ok(not ui.research_open() and not ui.blocks_point(Vector2(900, 500)), "close releases the scene")
	_drop(p)


func test_research_modal_selecting_a_blocked_project_starts_nothing(t) -> void:
	var p := _make(t)
	var ui = p[1]
	p[0].bridge_research_options = _options()
	ui.begin_operation()
	ui.toggle_research()
	ui._on_research_action("select", "2")
	t.eq(ui.live_research.selected, "2", "selection kept")
	t.ok(not p[0].calls.any(func(c): return c[0] == "research"), "blocked: no start")
	ui.process(0.2)
	t.ok(ui.research_open(), "still open")
	_drop(p)


func test_the_minimap_moves_into_the_assault_slot_and_back(t) -> void:
	var p := _make(t)
	var ui = p[1]
	var g = p[0]
	g.add_node(1, "CommandCenter", "building", 0, Vector3(3, 0, 14), 800.0, 1000.0)
	g.add_node(2, "CommandCenter", "building", 1, Vector3(40, 0, 4), 500.0, 1000.0)
	ui.begin_operation()
	ui.adapter.tab = "orders"
	ui.process(0.2)
	t.ok(ui.adapter.assault_active(), "the damaged core engages the assault layout")
	t.ok(ui.minimap_view.get_parent() != ui.hud._home_slot, "the minimap left the main slot")
	t.eq(ui.minimap_view.get_parent(), ui.hud.map_slot, "and sits in the assault slot")
	t.eq(ui.minimap_view.size, ui.hud.map_slot.size, "sized to it")
	ui.adapter.tab = "units"
	ui.process(0.2)
	t.ok(is_instance_valid(ui.minimap_view), "the minimap survived the layout change")
	t.eq(ui.minimap_view.get_parent(), ui.hud._home_slot, "and is back in the main slot")
	t.ok(ui.hud.get_node("as_bottom").get_child_count() == 0, "assault sections cleared")
	_drop(p)
