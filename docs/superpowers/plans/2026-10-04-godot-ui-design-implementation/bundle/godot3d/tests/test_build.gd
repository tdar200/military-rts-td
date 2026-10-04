extends RefCounted
const Hud = preload("res://scripts/ui/hud.gd")
const BuildDeck = preload("res://scripts/ui/build_deck.gd")
const Logic = preload("res://scripts/ui/build_logic.gd")
const Fx = preload("res://scripts/gallery/fixtures_build.gd")

const KEYS := ["build_top", "build_power", "build_alerts", "build_minimap", "build_placement", "build_world"]


func _hud(vm: Dictionary) -> Control:
	var hud := Hud.new()
	BuildDeck.register(hud)
	hud.apply(vm)
	return hud


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button and node.text != "":
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _texts(node: Node) -> Array:
	var out: Array = []
	for b in _buttons(node):
		out.append(b.text)
	return out


func _scroll(hud: Control) -> Control:
	for c in hud.get_node("deck_body").get_children():
		if "overflow" in c:
			return c
	return null


func test_cost_and_shortfall_format(t) -> void:
	t.eq(Logic.format_cost(600, 600, 20), "600 M 600 W 20 kW", "plain draw")
	t.eq(Logic.format_cost(220, 240, -80), "220 M 240 W +80 kW", "output is signed plus")
	t.eq(Logic.format_cost(20, 20, 0), "20 M 20 W 0 kW", "zero draw")
	t.eq(Logic.shortfall(140, 128), 12, "short by 12")
	t.eq(Logic.shortfall(100, 400), 0, "never negative")


func test_projection_160_130_40(t) -> void:
	var p := Logic.projection(160, 130, 40)
	t.eq(p["over"], 10, "10 kW over capacity")
	t.eq(p["value"], "170 / 160 kW", "label")
	t.eq(p["tone"], "warn", "valid but over is a warning")
	t.eq(p["segments"].size(), 3, "cyan, warn, hatch")
	t.eq(p["segments"][2]["tone"], "bad_hatch", "overflow is hatched")
	t.near(p["marker"], 0.8, 0.001, "capacity marker sits at 80% of the scale")
	var ok := Logic.projection(160, 100, 20)
	t.eq(ok["over"], 0, "no overflow")
	t.eq(ok["segments"].size(), 2, "no hatch segment")
	var idle := Logic.projection(0, 0, 0)
	t.eq(idle["segments"].size(), 0, "zero grid draws nothing")
	t.ok(is_finite(idle["marker"]), "no divide by zero")


func test_empty_view_model_builds_nothing(t) -> void:
	var hud := _hud({})
	for key in KEYS + ["deck_body"]:
		t.eq(hud.get_node(key).get_child_count(), 0, key + " is empty without a slice")
	hud.free()


func test_fixture_builds_every_section(t) -> void:
	var hud := _hud(Fx.build_deck())
	for key in ["build_top", "build_power", "build_alerts", "build_minimap", "build_placement", "deck_body"]:
		t.ok(hud.get_node(key).get_child_count() > 0, key + " has nodes")
	t.ok(hud.map_slot != null, "minimap slot is exposed")
	hud.free()


func test_cards_are_buttons_named_after_the_building(t) -> void:
	var hud := _hud(Fx.build_deck())
	var names := _texts(hud.get_node("deck_body"))
	for n in ["Command Centre", "Reactor", "Vehicle Factory", "Wall", "Lab", "Build", "Science"]:
		t.ok(names.has(n), n + " is findable")
	t.ok(not names.has("Airfield"), "a locked card is not clickable")
	hud.free()


func test_actions_emit(t) -> void:
	var hud := _hud(Fx.build_deck())
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	for b in _buttons(hud.get_node("deck_body")):
		if b.text == "Reactor" or b.text == "Science":
			b.pressed.emit()
	t.eq(got, [["deck_tab", "science"], ["arm_build", "reactor"]], "tab then card")
	got.clear()
	for b in _buttons(hud.get_node("build_power")):
		if b.text == "Plan a Reactor (P)":
			b.pressed.emit()
	t.eq(got, [["arm_build", "reactor"]], "popover button carries its action")
	hud.free()


func test_zero_cards(t) -> void:
	var hud := _hud(Fx.edge("none"))
	var names := _texts(hud.get_node("deck_body"))
	t.ok(names.has("Build"), "tabs stay")
	t.eq(names.size(), 5, "only the five tabs are clickable")
	t.near(_scroll(hud).overflow, 0.0, 0.01, "nothing to scroll")
	hud.free()


func test_all_locked_cards_are_not_clickable(t) -> void:
	var hud := _hud(Fx.edge("locked"))
	t.eq(_texts(hud.get_node("deck_body")).size(), 5, "tabs only")
	hud.free()


func test_every_card_short_still_clickable(t) -> void:
	var hud := _hud(Fx.edge("short"))
	t.eq(_texts(hud.get_node("deck_body")).size(), 5 + 12, "a short card is still armable")
	hud.free()


func test_empty_queue(t) -> void:
	var hud := _hud(Fx.edge("no_queue"))
	t.ok(hud.get_node("deck_body").get_child_count() > 0, "deck still builds")
	var vm := Fx.edge("no_queue")
	vm["deck"]["body"].erase("queue")
	var bare := _hud(vm)
	t.ok(bare.get_node("deck_body").get_child_count() > 0, "deck builds with no queue key at all")
	hud.free()
	bare.free()


func test_many_cards_scroll_inside_the_grid(t) -> void:
	var hud := _hud(Fx.edge("many"))
	var s := _scroll(hud)
	t.ok(s.clip_contents, "grid clips")
	t.ok(s.overflow > 0.0, "16 cards overflow four rows")
	t.near(s.overflow, 4.0 * 138.0 - 10.0 - s.size.y, 0.01, "overflow equals content minus window")
	var w := 0.0
	for c in s.content.get_children():
		w = maxf(w, c.position.x + c.size.x)
	t.ok(w <= s.size.x, "no card pokes out sideways")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	s._gui_input(down)
	t.ok(s.content.position.y < 0.0, "wheel scrolls down")
	for i in 20:
		s._gui_input(down)
	t.near(s.content.position.y, -s.overflow, 0.01, "scroll stops at the end")
	hud.free()


func test_twelve_cards_fit_without_scrolling(t) -> void:
	var hud := _hud(Fx.build_deck())
	t.near(_scroll(hud).overflow, 0.0, 0.01, "three rows fit")
	hud.free()


func test_scroll_position_survives_a_rebuild(t) -> void:
	var hud := _hud(Fx.edge("many"))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	_scroll(hud)._gui_input(down)
	var vm := Fx.edge("many")
	vm["deck"]["body"]["queue"]["ratio"] = 0.95
	hud.apply(vm)
	t.near(_scroll(hud).content.position.y, -46.0, 0.01, "offset kept when the live data ticks")
	hud.free()


func test_placement_with_failing_checks(t) -> void:
	var hud := _hud(Fx.edge("invalid"))
	t.ok(hud.get_node("build_placement").get_child_count() > 0, "panel builds")
	var vm := Fx.edge("invalid")
	vm["build_placement"]["checks"] = []
	vm["build_placement"]["hints"] = []
	vm["build_placement"].erase("grid")
	var bare := _hud(vm)
	t.ok(bare.get_node("build_placement").get_child_count() > 0, "panel builds with no checks, hints or grid")
	hud.free()
	bare.free()


func test_placement_checks_never_overlap_the_hints(t) -> void:
	var hud := _hud(Fx.build_deck())
	var layer: Node = hud.get_node("build_placement")
	var hint_left := 99999.0
	var check_right := 0.0
	for c in layer.get_children():
		if c.position.y >= 1005.0 and c.position.y <= 1040.0:
			if c.get_script() != null and c.get_script().resource_path.ends_with("kbd.gd"):
				hint_left = minf(hint_left, c.position.x)
	for c in layer.get_children():
		if c.position.y >= 1005.0 and c.position.y <= 1040.0 and c.position.x + c.size.x < hint_left + 1.0 and c.size.x > 0.0 and c.position.x < hint_left:
			check_right = maxf(check_right, c.position.x + c.size.x)
	t.ok(check_right <= hint_left, "checks end before the first key hint (%s vs %s)" % [check_right, hint_left])
	hud.free()
