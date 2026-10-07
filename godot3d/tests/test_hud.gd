extends RefCounted
const Hud = preload("res://scripts/ui/hud.gd")
const Fixtures = preload("res://scripts/gallery/fixtures.gd")
const KeyCapScript = preload("res://scripts/ui/components/key_cap.gd")


func _hud(t, root: Node) -> Control:
	var hud := Hud.new()
	root.add_child(hud)
	return hud


func _texts(node: Node, out: Array = []) -> Array:
	if node is Button and node.text != "":
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


func test_empty_view_model_builds_nothing(t) -> void:
	var hud := Hud.new()
	hud.apply({})
	t.eq(hud.get_child_count(), 12 + Hud.GAMEPLAY_KEYS.size(), "one layer per section, the gameplay sections included")
	for layer in hud.get_children():
		t.eq(layer.get_child_count(), 1 if layer.name == "minimap_slot" else 0, layer.name + " layer is empty")
	hud.free()


func test_fixture_builds_all_sections(t) -> void:
	var hud := Hud.new()
	hud.apply(Fixtures.hud_main())
	for layer in hud.get_children():
		if Hud.GAMEPLAY_KEYS.has(str(layer.name)):
			t.eq(layer.get_child_count(), 0, layer.name + " builds nothing: the original board fixture carries no gameplay slice")
			continue
		t.ok(layer.get_child_count() > 0, layer.name + " has nodes")
	t.ok(hud.map_slot.get_parent() == hud.get_node("minimap_slot"), "the map slot is a persistent child")
	hud.free()


func test_unchanged_slice_keeps_nodes(t) -> void:
	var hud := Hud.new()
	var vm := Fixtures.hud_main()
	hud.apply(vm)
	var layer: Node = hud.get_node("top_speed")
	var first: Node = layer.get_child(0)
	vm["wave"]["timer"] = "T-00:44"
	hud.apply(vm)
	t.ok(hud.get_node("top_speed") == layer and layer.get_child(0) == first, "speed buttons survive a timer tick")
	var slot: Node = hud.map_slot
	vm["map_marks"]["marks"] = []
	hud.apply(vm)
	t.ok(hud.map_slot == slot and slot.is_inside_tree() == hud.is_inside_tree(), "map slot survives mark updates")
	var order: Array = []
	for c in hud.get_children():
		order.append(c.name)
	hud.apply(vm)
	var again: Array = []
	for c in hud.get_children():
		again.append(c.name)
	t.eq(order, again, "layer order is stable across rebuilds")
	t.ok(hud.get_node("top_chips") != null, "chip layer exists")
	hud.free()


func test_actions_emit(t) -> void:
	var hud := Hud.new()
	hud.apply(Fixtures.hud_main())
	var got: Array = []
	hud.action.connect(func(n, a): got.append([n, a]))
	var tabs: Node = hud.get_node("deck_tabs")
	for c in tabs.get_children():
		if c is Button and c.text == "Orders":
			c.pressed.emit()
	t.eq(got, [["deck_tab", "orders"]], "orders tab emits")
	hud.free()


func test_zero_selection_hides_panel(t) -> void:
	var hud := Hud.new()
	var vm := Fixtures.hud_main()
	vm.erase("selection")
	hud.apply(vm)
	t.eq(hud.get_node("selection").get_child_count(), 0, "no selection panel without a selection")
	hud.free()


func test_single_unit_and_empty_groups(t) -> void:
	var hud := Hud.new()
	var vm := Fixtures.hud_main()
	vm["selection"]["groups"] = []
	vm["selection"]["count"] = "1 unit"
	vm["selection"]["rows"] = []
	vm["selection"].erase("preview")
	hud.apply(vm)
	t.ok(hud.get_node("selection").get_child_count() > 0, "panel still builds")
	hud.free()


func test_long_lists_do_not_overflow(t) -> void:
	var hud := Hud.new()
	var vm := Fixtures.hud_main()
	var items: Array = []
	for i in 9:
		items.append({"t": "Objective number %d with a rather long description that must wrap or clip" % i, "state": "todo"})
	vm["objectives"]["items"] = items
	vm["alerts"] = [vm["alerts"][0], vm["alerts"][0], vm["alerts"][0], vm["alerts"][0], vm["alerts"][0]]
	hud.apply(vm)
	var obj: Control = hud.get_node("objectives").get_child(0)
	t.near(obj.size.y, 42 + 25 * 9, 0.1, "objective panel grows with the list")
	hud.free()


func test_blocks_point_over_panels_only(t) -> void:
	var hud := Hud.new()
	hud.apply(Fixtures.hud_main())
	t.ok(hud.blocks_point(Vector2(100, 40)), "top bar blocks the 3D scene")
	t.ok(hud.blocks_point(Vector2(1500, 900)), "deck blocks the 3D scene")
	t.ok(not hud.blocks_point(Vector2(960, 500)), "open battlefield does not")
	hud.free()


func test_clickable_cards_carry_their_name(t) -> void:
	var hud := Hud.new()
	hud.apply(Fixtures.hud_main())
	var names := _texts(hud)
	t.ok(names.has("Riflemen"), "deck card button is findable by name")
	t.ok(names.has("TANK x4"), "subgroup button is findable by label")
	t.ok(names.has("Orders"), "tab is findable")
	hud.free()


## Task 2: "F1 Controls" in the top bar, left of the wave chip, never over a resource chip; it opens the controls screen.
func test_controls_hint_sits_in_the_top_bar_and_opens_the_controls(t) -> void:
	var vm := Fixtures.hud_main()
	vm["chips"] = (vm["chips"] as Array).slice(0, 5)
	vm["controls_hint"] = "F1 Controls"
	var hud := Hud.new()
	var got: Array = []
	hud.action.connect(func(name, arg): got.append([name, arg]))
	hud.apply(vm)
	var hit: Button = null
	var right_of_chips := 0.0
	var wave_left := 1920.0
	var layer := hud.get_node("top_chips")
	for c in layer.get_children():
		if c is Button and c.text == "F1 Controls":
			hit = c
	t.ok(hit != null, "the hint is a button named F1 Controls")
	if hit == null:
		hud.free()
		return
	t.ok(_has_label(layer, "Controls"), "the hint reads Controls")
	t.ok(_has_key(layer, "F1"), "beside an F1 key cap")
	for c in layer.get_children():
		if c is Control and c != hit and c.get_class() != "Button" and c.position.y >= 18.0 and c.size.y >= 24.0 and c.size.x > 60.0:
			if c.position.x < hit.position.x:
				right_of_chips = maxf(right_of_chips, c.position.x + c.size.x)
			else:
				wave_left = minf(wave_left, c.position.x)
	t.ok(hit.position.x >= right_of_chips, "right of every chip (%d >= %d)" % [hit.position.x, right_of_chips])
	t.ok(hit.position.x + hit.size.x <= wave_left, "left of the wave chip (%d <= %d)" % [hit.position.x + hit.size.x, wave_left])
	t.ok(hit.position.y >= 10.0 and hit.position.y + hit.size.y <= 66.0, "inside the top bar")
	hit.pressed.emit()
	t.eq(got, [["open_controls", null]], "clicking it opens the controls")
	hud.free()


func test_controls_hint_absent_without_the_key_and_when_it_would_overlap(t) -> void:
	var hud := Hud.new()
	hud.apply(Fixtures.hud_main())
	t.ok(not _has_label(hud.get_node("top_chips"), "Controls"), "the board fixtures carry no hint, so the gallery boards are unchanged")
	hud.free()
	var vm := Fixtures.hud_main()
	var many: Array = []
	for i in 9:
		many.append({"icon": "material", "tone": "cyan", "label": "Material", "value": "840"})
	vm["chips"] = many
	vm["controls_hint"] = "F1 Controls"
	var crowded := Hud.new()
	crowded.apply(vm)
	t.ok(not _has_label(crowded.get_node("top_chips"), "Controls"), "no room between the chips and the wave chip: no hint")
	crowded.free()


func _has_label(root: Node, s: String) -> bool:
	for n in root.find_children("*", "", true, false):
		if n.get("text") != null and str(n.get("text")) == s and not (n is Button):
			return true
	return false


func _has_key(root: Node, s: String) -> bool:
	for n in root.find_children("*", "", true, false):
		if n is KeyCapScript and str(n.get("label")) == s:
			return true
	return false
