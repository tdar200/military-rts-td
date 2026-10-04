extends RefCounted
const Hud = preload("res://scripts/ui/hud.gd")
const Assault = preload("res://scripts/ui/assault/assault.gd")
const WorldMarks = preload("res://scripts/ui/world_marks.gd")
const Fx = preload("res://scripts/gallery/fixtures_assault.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")


func _hud(vm: Dictionary) -> Control:
	var hud := Hud.new()
	Assault.register(hud)
	hud.apply(vm)
	return hud


func _layer(hud: Control, key: String) -> Node:
	return hud.get_node(key)


func _labels(node: Node, out: Array = []) -> Array:
	if node is TextBox and node.text != "":
		out.append(node.text)
	if node is Button and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_labels(c, out)
	return out


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _has(node: Node, text: String) -> bool:
	return _labels(node).has(text)


func _free(hud: Control) -> void:
	hud.free()


func test_fixture_builds_every_section(t) -> void:
	var hud := _hud(Fx.hud())
	for k in Assault.KEYS:
		t.ok(_layer(hud, k).get_child_count() > 0, k + " has nodes")
	t.ok(hud.map_slot != null, "as_bottom assigns map_slot")
	_free(hud)


func test_empty_view_model_builds_nothing(t) -> void:
	var hud := _hud({})
	for k in Assault.KEYS:
		t.eq(_layer(hud, k).get_child_count(), 0, k + " empty")
	_free(hud)


func test_core_hp_zero_and_full(t) -> void:
	for ratio in [0.0, 1.0, -0.5, 7.0]:
		var vm := Fx.hud()
		vm["as_boss"]["ratio"] = ratio
		vm["as_boss"]["hp_text"] = "x"
		var hud := _hud(vm)
		t.ok(_layer(hud, "as_boss").get_child_count() > 0, "boss bar builds at ratio %s" % ratio)
		t.ok(_has(_layer(hud, "as_boss"), "Alien Core Node") or _has(_layer(hud, "as_boss"), "ALIEN CORE NODE"), "name shown at %s" % ratio)
		_free(hud)


func test_boss_missing_optional_fields(t) -> void:
	var hud := _hud({"as_boss": {"name": "Core", "ratio": 0.5}})
	t.ok(_layer(hud, "as_boss").get_child_count() > 0, "boss with only name and ratio")
	_free(hud)


func test_relays_zero_of_zero_builds_no_panel(t) -> void:
	var vm := Fx.hud()
	vm["as_relays"] = {"items": []}
	var hud := _hud(vm)
	t.eq(_layer(hud, "as_relays").get_child_count(), 0, "no panel for zero relays")
	_free(hud)


func test_relays_five_items_overflow_line(t) -> void:
	var vm := Fx.hud()
	var items: Array = []
	for i in 5:
		items.append({"name": "Relay %d" % i, "state": "powered" if i % 2 == 0 else "destroyed"})
	vm["as_relays"] = {"items": items, "max": 3}
	var hud := _hud(vm)
	var layer := _layer(hud, "as_relays")
	t.ok(layer.get_child_count() > 0, "panel builds")
	var texts := _labels(layer)
	t.ok(texts.has("Relay 0"), "first relay listed")
	t.ok(not texts.has("Relay 4"), "relay beyond max is folded")
	t.ok(texts.any(func(s): return str(s).contains("2 more")), "overflow count shown: %s" % str(texts))
	_free(hud)


func test_relay_action_emits(t) -> void:
	var vm := Fx.hud()
	vm["as_relays"] = {"items": [{"name": "Relay A", "state": "powered", "action": "jump_relay", "arg": "a"}]}
	var hud := _hud(vm)
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	var btns := _buttons(_layer(hud, "as_relays"))
	t.ok(btns.size() >= 1, "relay row is a button")
	for b in btns:
		t.ok(b.text != "", "relay button has a human label")
		b.pressed.emit()
	t.eq(got.size(), btns.size(), "each button emits")
	t.eq(got[0], ["jump_relay", "a"], "relay action and arg")
	_free(hud)


func test_empty_objective_steps_drop_checklist(t) -> void:
	var full := _hud(Fx.hud())
	var vm := Fx.hud()
	vm["as_objective"]["steps"] = []
	var empty := _hud(vm)
	var n_full := _labels(_layer(full, "as_objective")).size()
	var n_empty := _labels(_layer(empty, "as_objective")).size()
	t.ok(n_empty > 0, "title and body still shown")
	t.ok(n_empty < n_full, "checklist labels are gone")
	t.ok(not _has(_layer(empty, "as_objective"), "Suppress AA"), "no step text")
	var no_key := Fx.hud()
	no_key["as_objective"].erase("steps")
	var h3 := _hud(no_key)
	t.ok(_layer(h3, "as_objective").get_child_count() > 0, "missing steps key tolerated")
	_free(full)
	_free(empty)
	_free(h3)


func test_zero_alerts(t) -> void:
	var vm := Fx.hud()
	vm["as_bottom"]["alerts"] = []
	var hud := _hud(vm)
	t.ok(_layer(hud, "as_bottom").get_child_count() > 0, "minimap panel still builds")
	t.ok(hud.map_slot != null, "map_slot present")
	t.ok(not _has(_layer(hud, "as_bottom"), "HQ under raid"), "no alert rows")
	_free(hud)


func test_twelve_alerts_newest_four_plus_count(t) -> void:
	var vm := Fx.hud()
	var alerts: Array = []
	for i in 12:
		alerts.append({"tone": "warn", "marker": "dot", "label": "Alert %d" % i, "time": "0:%02d" % i})
	vm["as_bottom"]["alerts"] = alerts
	var hud := _hud(vm)
	var layer := _layer(hud, "as_bottom")
	var texts := _labels(layer)
	var rows := 0
	for i in 12:
		if texts.has("Alert %d" % i):
			rows += 1
	t.eq(rows, 4, "only four alert rows drawn")
	t.ok(texts.has("Alert 0"), "newest (first in list) kept")
	t.ok(not texts.has("Alert 11"), "oldest dropped")
	t.ok(texts.has("12"), "count of 12 shown: %s" % str(texts))
	_free(hud)


func test_alert_action_emits(t) -> void:
	var hud := _hud(Fx.hud())
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	for b in _buttons(_layer(hud, "as_bottom")):
		t.ok(b.text != "", "every clickable has a label")
		if b.text == "HQ under raid":
			b.pressed.emit()
	t.ok(got.any(func(g): return g[0] == "jump_hq"), "alert emits its action")
	_free(hud)


func test_no_selection_shows_empty_state(t) -> void:
	var vm := Fx.hud()
	vm["as_selection"] = {"empty_title": "No selection", "hint": "Drag to select units."}
	var hud := _hud(vm)
	var layer := _layer(hud, "as_selection")
	t.ok(layer.get_child_count() > 0, "empty-state panel builds")
	t.ok(not _has(layer, "Vanguard"), "no group name")
	t.ok(_buttons(layer).is_empty(), "no group cards")
	_free(hud)


func test_null_selection_builds_nothing(t) -> void:
	var vm := Fx.hud()
	vm["as_selection"] = null
	var hud := _hud(vm)
	t.eq(_layer(hud, "as_selection").get_child_count(), 0, "null slice builds nothing")
	_free(hud)


func test_selection_groups_emit(t) -> void:
	var hud := _hud(Fx.hud())
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	var cards := _buttons(_layer(hud, "as_selection"))
	t.eq(cards.size(), 5, "five group cards")
	for b in cards:
		t.ok(b.text != "", "card label")
	cards[1].pressed.emit()
	t.eq(got, [["select_group", "at"]], "group id emitted")
	_free(hud)


func test_deck_orders_and_tabs(t) -> void:
	var hud := Hud.new()
	Assault.register(hud)
	var vm := Fx.hud()
	hud.apply({"deck": vm["deck"]})
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	var btns := _buttons(hud)
	var labels: Array = btns.map(func(b): return b.text)
	for want in ["Build", "Units", "Orders", "Science", "Logistics", "Attack-move", "Resupply", "HQ"]:
		t.ok(labels.has(want), "button %s" % want)
	for b in btns:
		if b.text == "Resupply":
			b.pressed.emit()
		if b.text == "Science":
			b.pressed.emit()
	t.ok(got.has(["order", "resupply"]), "order emits: %s" % str(got))
	t.ok(got.has(["deck_tab", "science"]), "tab emits")
	hud.free()


func test_deck_without_orders(t) -> void:
	var hud := Hud.new()
	Assault.register(hud)
	hud.apply({"deck": {"body": {"kind": "assault_orders"}}})
	t.ok(true, "empty orders body does not crash")
	hud.free()


func test_top_bar_tolerates_empty(t) -> void:
	for slice in [{}, {"groups": []}, {"groups": [[]], "right": []}]:
		var hud := _hud({"as_top": slice})
		t.ok(hud != null, "top bar survives %s" % str(slice))
		_free(hud)


func test_edge_alert_sides(t) -> void:
	for side in ["left", "right"]:
		var vm := Fx.hud()
		vm["as_edge"]["side"] = side
		var hud := _hud(vm)
		t.ok(_layer(hud, "as_edge").get_child_count() > 0, "edge alert on %s" % side)
		_free(hud)
	var hud := _hud(Fx.hud())
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	for b in _buttons(_layer(hud, "as_edge")):
		t.ok(b.text != "", "edge button label")
		b.pressed.emit()
	t.eq(got.size(), 1, "one edge action")
	t.eq(got[0][0], "jump_hq", "edge action name")
	_free(hud)


# ---------------------------------------------------------------- world marks

func _marks(list: Array) -> WorldMarks:
	var wm := WorldMarks.new()
	wm.size = Vector2(1920, 1080)
	wm.set_marks(list)
	return wm


func test_marks_fixture_resolves(t) -> void:
	var wm := _marks(Fx.marks())
	t.eq(wm.dropped, 0, "nothing dropped at the mock coordinates")
	t.eq(wm.resolved.size(), Fx.marks().size(), "every mark resolves")
	wm.free()


func test_marks_empty(t) -> void:
	var wm := _marks([])
	t.eq(wm.resolved.size(), 0, "no marks")
	t.eq(wm.dropped, 0, "none dropped")
	wm.free()


func test_offscreen_hostile_dropped(t) -> void:
	var wm := _marks([
		{"kind": "hostile", "x": -40, "y": 100, "hp": 0.5},
		{"kind": "hostile", "x": 2500, "y": 100, "hp": 0.5},
		{"kind": "hostile", "x": 400, "y": 1200, "hp": 0.5},
		{"kind": "hostile", "x": 400, "y": 300, "hp": 0.5}])
	t.eq(wm.dropped, 3, "three off-screen hostiles dropped")
	t.eq(wm.resolved.size(), 1, "one kept")
	wm.free()


func test_callout_inside_not_clamped(t) -> void:
	var wm := _marks([{"kind": "callout", "x": 500, "y": 300, "tag": "Impact zone", "tag_tone": "bad", "text": "Disperse"}])
	var r: Dictionary = wm.resolved[0]
	t.ok(not r["clamped"], "inside the viewport")
	t.eq(r["arrow"], "", "no edge arrow")
	wm.free()


func test_callout_clamps_each_edge(t) -> void:
	var cases := {
		"left": {"x": -300, "y": 400, "tx": -500, "ty": 400},
		"right": {"x": 2300, "y": 400, "tx": 2500, "ty": 400},
		"top": {"x": 900, "y": -300, "tx": 900, "ty": -500},
		"bottom": {"x": 900, "y": 1400, "tx": 900, "ty": 1600},
	}
	for side in cases:
		var m: Dictionary = cases[side].duplicate()
		m["kind"] = "callout"
		m["title"] = "Forward depot"
		m["sub"] = "186 rounds"
		var wm := _marks([m])
		var r: Dictionary = wm.resolved[0]
		var view := Rect2(0, 0, 1920, 1080)
		t.ok(r["clamped"], side + " flagged clamped")
		t.ok(view.encloses(r["rect"]), side + " rect inside viewport: %s" % str(r["rect"]))
		t.eq(r["arrow"], side, side + " arrow points to the target side")
		t.ok(view.has_point(r["tip"]), side + " arrow tip on screen: %s" % str(r["tip"]))
		wm.free()


func test_callout_card_clamps_to_corner(t) -> void:
	var wm := _marks([{"kind": "callout", "x": 5000, "y": 5000, "w": 236, "title": "Core emitter", "tag": "Interruptible", "ratio": 0.62, "body": "62% integrity.", "tone": "bad"}])
	var r: Dictionary = wm.resolved[0]
	t.ok(r["clamped"], "far corner clamped")
	t.ok(Rect2(0, 0, 1920, 1080).encloses(r["rect"]), "inside viewport")
	wm.free()


func test_callout_content_survives_position_change(t) -> void:
	var m := {"kind": "callout", "x": 500, "y": 300, "tag": "Impact zone", "text": "Disperse"}
	var wm := _marks([m])
	var first: Node = wm._callout_nodes[0]
	var moved := m.duplicate()
	moved["x"] = 640
	wm.set_marks([moved])
	t.ok(wm._callout_nodes[0] == first, "moving a callout keeps its nodes")
	moved["text"] = "Different"
	wm.set_marks([moved])
	t.ok(wm._callout_nodes[0] != first, "changing its content rebuilds")
	wm.free()


func test_marks_tolerate_missing_fields(t) -> void:
	var wm := _marks([
		{"kind": "hostile", "x": 100, "y": 100},
		{"kind": "brackets", "x": 10, "y": 10, "w": 0, "h": 0},
		{"kind": "arrow", "x": 0, "y": 0, "to": [0, 0]},
		{"kind": "countdown", "x": 300, "y": 300, "value": 0, "total": 0},
		{"kind": "impact", "x": 300, "y": 300},
		{"kind": "ring", "x": 300, "y": 300},
		{"kind": "unknown", "x": 1, "y": 1},
		{"kind": "callout", "x": 10, "y": 10}])
	t.eq(wm.resolved.size(), 8, "nothing crashes, nothing lost")
	wm.free()


func test_bezier_endpoints(t) -> void:
	var pts := WorldMarks.bezier(Vector2(0, 0), Vector2(10, 0), Vector2(20, 10), Vector2(30, 10))
	t.near(pts[0].distance_to(Vector2(0, 0)), 0.0, 0.01, "starts at p0")
	t.near(pts[pts.size() - 1].distance_to(Vector2(30, 10)), 0.0, 0.01, "ends at p1")


func test_panels_block_clicks_through(t) -> void:
	var hud := _hud(Fx.hud())
	t.ok(hud.blocks_point(Vector2(300, 900)), "minimap panel blocks")
	t.ok(hud.blocks_point(Vector2(900, 900)), "selection panel blocks")
	t.ok(hud.blocks_point(Vector2(1600, 900)), "deck blocks")
	t.ok(not hud.blocks_point(Vector2(960, 500)), "open ground does not block")
	_free(hud)
