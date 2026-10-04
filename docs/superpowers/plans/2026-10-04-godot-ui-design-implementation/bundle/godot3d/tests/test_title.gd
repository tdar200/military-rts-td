extends RefCounted
const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const Fx = preload("res://scripts/gallery/fixtures_title.gd")

const MENU_LABELS := ["Continue campaign", "New operation", "Skirmish sandbox", "Research archive", "Settings", "Quit"]


func _screen(t, vm: Dictionary) -> Control:
	var s := TitleScreen.new()
	t.root.add_child(s)
	s.apply(vm)
	return s


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _texts(node: Node) -> Array:
	return _buttons(node).map(func(b): return b.text)


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for c in node.get_children():
		var r := _find_scroll(c)
		if r:
			return r
	return null


func _disabled_menu(ids: Array) -> Dictionary:
	var vm := Fx.title()
	var over := {}
	for id in ids:
		over[id] = {"disabled": true}
	vm["menu"] = Fx.menu(over)
	return vm


func test_empty_view_model_builds_no_widgets(t) -> void:
	var s := _screen(t, {})
	t.eq(_buttons(s).size(), 0, "no buttons")
	t.eq(s.menu_buttons().size(), 0, "no menu entries")
	s.apply({})
	s.queue_free()


func test_fixture_menu_labels_and_order(t) -> void:
	var s := _screen(t, Fx.title())
	var labels: Array = s.menu_buttons().map(func(b): return b.text)
	t.eq(labels, MENU_LABELS, "menu button text is the label, in menu order")
	for i in 6:
		t.near(s.menu_buttons()[i].position.y, 432.0 + 66.0 * i, 0.01, "row %d y" % i)
		t.near(s.menu_buttons()[i].size.x, 440.0, 0.01, "row %d width" % i)
		t.near(s.menu_buttons()[i].size.y, 56.0, 0.01, "row %d height" % i)
	s.queue_free()


func test_every_button_text_matches_its_label(t) -> void:
	var s := _screen(t, Fx.title())
	var texts := _texts(s)
	for want in MENU_LABELS + ["Continue operation", "Start over"]:
		t.ok(texts.has(want), "button %s exists" % want)
	s.queue_free()


func test_actions_are_emitted(t) -> void:
	var s := _screen(t, Fx.title())
	var got: Array = []
	s.action.connect(func(name, arg): got.append([name, arg]))
	for b in s.menu_buttons():
		b.pressed.emit()
	for b in _buttons(s.layer("campaign")):
		b.pressed.emit()
	t.eq(got.map(func(g): return g[0]), ["continue", "new", "skirmish", "research", "settings", "quit", "operation_continue", "operation_restart"], "action names in order")
	s.queue_free()


func test_all_menu_items_disabled(t) -> void:
	var s := _screen(t, _disabled_menu(["continue", "new", "skirmish", "research", "settings", "quit"]))
	for b in s.menu_buttons():
		t.ok(b.disabled, b.text + " disabled")
		t.eq(b.focus_mode, Control.FOCUS_NONE, b.text + " not focusable")
		t.eq(b.tooltip_text, "", b.text + " has no tooltip")
	var got: Array = []
	s.action.connect(func(name, arg): got.append(name))
	s.focus_first()
	t.eq(got.size(), 0, "nothing emitted")
	s.queue_free()


func test_disabled_entries_draw_at_45_percent(t) -> void:
	var s := _screen(t, _disabled_menu(["skirmish", "research", "settings"]))
	var b: Control = s.menu_buttons()[2]
	t.near(b.disabled_alpha(), 0.45, 0.001, "disabled alpha")
	t.near(s.menu_buttons()[1].disabled_alpha(), 1.0, 0.001, "enabled alpha")
	s.queue_free()


func test_continue_disabled_without_save(t) -> void:
	var vm := Fx.title()
	vm["menu"] = Fx.menu({"continue": {"disabled": true, "hint": ""}})
	var s := _screen(t, vm)
	t.ok(s.menu_buttons()[0].disabled, "continue disabled")
	t.ok(not s.menu_buttons()[1].disabled, "new operation stays enabled")
	t.eq(s.first_enabled(), s.menu_buttons()[1], "focus starts on the first enabled entry")
	s.queue_free()


## Walks `focus_next` from the first enabled entry the way Tab does and returns the labels visited.
func _tab_order(s: Control, count: int) -> Array:
	var order: Array = []
	var cur: Control = s.first_enabled()
	for i in count:
		order.append(cur.text)
		cur = cur.get_node(cur.focus_next)
	order.append(cur.text)
	return order


func test_focus_order_equals_menu_order(t) -> void:
	var s := _screen(t, Fx.title())
	t.eq(_tab_order(s, 6), MENU_LABELS + ["Continue campaign"], "Tab walks the menu top to bottom and wraps")
	var back: Control = s.menu_buttons()[0].get_node(s.menu_buttons()[0].focus_previous)
	t.eq(back.text, "Quit", "Shift+Tab from the first entry wraps to the last")
	s.queue_free()


func test_focus_skips_disabled(t) -> void:
	var s := _screen(t, _disabled_menu(["skirmish"]))
	t.eq(_tab_order(s, 5), ["Continue campaign", "New operation", "Research archive", "Settings", "Quit", "Continue campaign"], "disabled entry skipped")
	s.queue_free()


func test_no_chapters(t) -> void:
	var s := _screen(t, Fx.with_chapters(0))
	t.ok(_find_scroll(s) == null, "no scroll region")
	t.eq(_texts(s.layer("campaign")), ["Continue operation", "Start over"], "only the featured buttons")
	s.queue_free()


func test_one_chapter(t) -> void:
	var s := _screen(t, Fx.with_chapters(1))
	t.ok(_find_scroll(s) == null, "one row fits without scrolling")
	s.queue_free()


func test_twelve_chapters_scroll_inside_panel(t) -> void:
	var s := _screen(t, Fx.with_chapters(12))
	var sc := _find_scroll(s)
	t.ok(sc != null, "scroll region exists")
	if sc:
		var r := Rect2(sc.position, sc.size)
		t.ok(TitleScreen.PANEL.encloses(r), "scroll region inside the panel")
		t.ok(r.end.y <= TitleScreen.GRID_BOTTOM + 0.01, "scroll region ends at the grid bottom")
		t.near(sc.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, 0.1, "no horizontal scroll")
		for c in sc.get_child(0).get_children():
			t.ok(c.position.x + c.size.x <= sc.size.x + 0.01, "card inside the scroll width")
	s.queue_free()


func test_long_operation_name_stays_inside_card(t) -> void:
	var s := _screen(t, Fx.long_name())
	var panel_bottom := TitleScreen.PANEL.end.y
	for c in s.layer("campaign").get_children():
		t.ok(c.position.y + c.size.y <= panel_bottom + 0.5, "%s inside the panel" % c.get_class())
	t.ok(TitleScreen.TextBoxProbe.line_count("Operation Dawnshield Resurgence Of The Northern Frontier Garrison", {"f": "disp", "wt": 600, "px": 34, "sp": 0.04, "lh": 37.4, "up": true}, 574.0) > 2, "fixture really is long")
	s.queue_free()


func test_clip_helper(t) -> void:
	var o := {"px": 15}
	t.eq(TitleScreen.TextBoxProbe.clip("short", o, 277.0, 1), "short", "short text unchanged")
	var cut := TitleScreen.TextBoxProbe.clip("a very long fact value that cannot possibly fit on one line of this card", o, 277.0, 1)
	t.ok(cut.ends_with("..."), "long text ends with an ellipsis")
	t.eq(TitleScreen.TextBoxProbe.line_count(cut, o, 277.0), 1, "clipped text fits")


func test_reapply_is_idempotent(t) -> void:
	var s := _screen(t, Fx.title())
	var first: Node = s.layer("menu")
	s.apply(Fx.title())
	t.ok(s.layer("menu") == first, "identical menu slice is not rebuilt")
	var vm := Fx.title()
	vm["menu"] = Fx.menu({"quit": {"disabled": true}})
	s.apply(vm)
	t.ok(s.layer("menu") != first, "changed menu slice is rebuilt")
	t.ok(s.menu_buttons()[5].disabled, "quit disabled after the change")
	s.queue_free()


func test_backdrop_can_be_hidden(t) -> void:
	var vm := Fx.title()
	vm["backdrop"] = false
	var s := _screen(t, vm)
	t.eq(s.layer("backdrop").get_child_count(), 0, "no backdrop nodes, the host's 3D scene shows through")
	s.queue_free()
