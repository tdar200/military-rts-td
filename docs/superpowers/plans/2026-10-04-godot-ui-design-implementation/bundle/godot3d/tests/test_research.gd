extends RefCounted
const Screen = preload("res://scripts/ui/research_screen.gd")
const Layout = preload("res://scripts/ui/research_layout.gd")
const FixturesResearch = preload("res://scripts/gallery/fixtures_research.gd")


func _screen(t) -> Control:
	var s := Screen.new()
	t.root.add_child(s)
	return s


func _done(s: Control) -> void:
	t_free(s)


func t_free(s: Control) -> void:
	s.get_parent().remove_child(s)
	s.free()


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _texts(node: Node) -> Array:
	var out: Array = []
	for b in _buttons(node):
		if b.text != "":
			out.append(b.text)
	return out


func _find(node: Node, text: String) -> Button:
	for b in _buttons(node):
		if b.text == text:
			return b
	return null


func _graph_vm(count: int, o := {}) -> Dictionary:
	var nodes: Array = []
	for i in count:
		var n := {"id": "p%d" % i, "name": "Project %d" % i, "state": "available", "tags": [], "segments": [0, 0, 0], "footer": {"text": "", "tone": "dim"}}
		if i > 0:
			n["prereqs"] = ["p%d" % ((i - 1) / 2)]
		nodes.append(n)
	var g := {"nodes": nodes}
	g.merge(o, true)
	return {"graph": g}


# ---------------------------------------------------------------- layout (pure)

func test_layout_depth_columns_and_stable_rows(t) -> void:
	var nodes := [
		{"id": "a"},
		{"id": "b", "prereqs": ["a"]},
		{"id": "c", "prereqs": ["a"]},
		{"id": "d", "prereqs": ["b", "c"]},
	]
	var lay := Layout.layout(nodes)
	t.eq(lay["cells"]["a"], Vector2i(0, 0), "root in column 0")
	t.eq(lay["cells"]["b"], Vector2i(1, 0), "first child takes row 0")
	t.eq(lay["cells"]["c"], Vector2i(1, 1), "second child takes the next free row")
	t.eq(lay["cells"]["d"], Vector2i(2, 0), "join node sits after the deepest prerequisite")
	t.eq(lay["cols"], 3, "three columns")
	t.eq(lay["rows"], 2, "two rows")
	t.eq(lay["edges"].size(), 4, "four resolved edges")
	t.eq(Layout.layout(nodes)["cells"], lay["cells"], "deterministic")


func test_layout_pins_reproduce_the_mock(t) -> void:
	var lay := Layout.layout([{"id": "a", "col": 2, "row": 3}, {"id": "b", "col": 0, "row": 1}])
	t.eq(lay["cells"]["a"], Vector2i(2, 3), "pinned a")
	t.eq(lay["cells"]["b"], Vector2i(0, 1), "pinned b")
	t.eq(Layout.node_pos(Vector2i(0, 0)), Vector2(4, 12), "origin")
	t.eq(Layout.node_pos(Vector2i(1, 2)), Vector2(284, 304), "pitch 280 x 146")


func test_layout_missing_prerequisite_is_reported_not_fatal(t) -> void:
	var lay := Layout.layout([{"id": "a", "prereqs": ["ghost"]}, {"id": "b", "prereqs": ["b", "a"]}])
	t.eq(lay["missing"].get("a"), ["ghost"], "unknown id is listed")
	t.eq(lay["missing"].get("b"), ["b"], "self prerequisite is listed")
	t.eq(lay["edges"].size(), 1, "only the valid edge remains")
	t.eq(lay["cells"]["a"], Vector2i(0, 0), "a is a root")
	t.eq(lay["cells"]["b"], Vector2i(1, 0), "b follows a")


func test_layout_cycle_and_duplicates_do_not_hang(t) -> void:
	var lay := Layout.layout([{"id": "a", "prereqs": ["b"]}, {"id": "b", "prereqs": ["a"]}, {"id": "a"}])
	t.eq(lay["keys"].size(), 3, "three keys")
	t.eq(lay["cells"].size(), 3, "three cells")
	var seen := {}
	for cell in lay["cells"].values():
		t.ok(not seen.has(cell), "cell is unique")
		seen[cell] = true


func test_layout_forty_nodes_never_overlap(t) -> void:
	var nodes: Array = _graph_vm(40)["graph"]["nodes"]
	var lay := Layout.layout(nodes)
	var seen := {}
	for cell in lay["cells"].values():
		t.ok(not seen.has(cell), "no shared cell %s" % str(cell))
		seen[cell] = true
	var rects: Array = []
	for cell in lay["cells"].values():
		rects.append(Layout.node_rect(cell))
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlap = true
	t.ok(not overlap, "card rectangles are disjoint")
	var size := Layout.world_size(lay["cols"], lay["rows"])
	t.ok(size.x > 1078.0 or size.y > 734.0, "40 nodes do not fit the viewport, so the graph must pan")


func test_edge_geometry(t) -> void:
	var straight := Layout.edge(Vector2i(0, 0), Vector2i(1, 0))
	t.ok(straight["straight"], "same row is straight")
	t.near(straight["p0"].x, 236.0, 0.01, "leaves the right edge")
	t.near(straight["p1"].x, 282.0, 0.01, "stops 2px short of the target")
	t.eq(Layout.edge_points(straight).size(), 2, "straight edge is two points")
	var curve := Layout.edge(Vector2i(0, 0), Vector2i(1, 2))
	t.ok(not curve["straight"], "different rows curve")
	t.eq(Layout.edge_points(curve).size(), 29, "bezier is sampled")


# ---------------------------------------------------------------- screen

func test_empty_view_model_builds_empty_layers(t) -> void:
	var s := _screen(t)
	s.apply({})
	t.eq(s.get_child_count() >= 7, true, "a layer per section")
	for layer in s.get_children():
		if layer.name in ["header", "gate", "filters", "graph", "zoom", "eras", "detail"]:
			t.eq(layer.get_child_count(), 0, layer.name + " layer is empty")
	_done(s)


func test_fixture_builds_every_section(t) -> void:
	var s := _screen(t)
	s.apply(FixturesResearch.research())
	for name in ["header", "gate", "filters", "graph", "zoom", "eras", "detail"]:
		t.ok(s.get_node(name).get_child_count() > 0, name + " has nodes")
	_done(s)


func test_node_cards_are_buttons_named_after_the_project(t) -> void:
	var s := _screen(t)
	var vm := FixturesResearch.research()
	s.apply(vm)
	var texts := _texts(s)
	for node in vm["graph"]["nodes"]:
		t.ok(texts.has(node["name"]), "button text %s" % node["name"])
	t.ok(texts.has("Close"), "close control is a Button named Close")
	t.ok(texts.has("Fund theory"), "secondary action button")
	_done(s)


func test_select_emits_and_does_not_start_by_default(t) -> void:
	var s := _screen(t)
	s.apply(FixturesResearch.research())
	var got: Array = []
	s.action.connect(func(n, a): got.append([n, a]))
	_find(s, "Smart grids").pressed.emit()
	t.eq(got, [["select", "smart_grids"]], "a node press only selects")
	_done(s)


func test_click_to_start_researches_available_nodes_only(t) -> void:
	var s := _screen(t)
	var vm := FixturesResearch.research()
	vm["graph"]["click_to_start"] = true
	s.apply(vm)
	var got: Array = []
	s.action.connect(func(n, a): got.append([n, a]))
	_find(s, "Smart grids").pressed.emit()
	t.eq(got, [["select", "smart_grids"], ["research", "smart_grids"]], "available node selects and starts")
	got.clear()
	_find(s, "Aircraft").pressed.emit()
	t.eq(got, [["select", "aircraft"]], "an implemented node only selects")
	got.clear()
	_find(s, "Autonomous supply").pressed.emit()
	t.eq(got, [["select", "autonomous"]], "a blocked node only selects")
	_done(s)


func test_detail_buttons_emit_their_actions(t) -> void:
	var s := _screen(t)
	s.apply(FixturesResearch.research())
	var got: Array = []
	s.action.connect(func(n, a): got.append([n, a]))
	_find(s, "Fund theory").pressed.emit()
	_find(s, "Close").pressed.emit()
	_find(s, "Path to capability").pressed.emit()
	t.eq(got[0], ["research", "robotic"], "fund theory starts research on the selection")
	t.eq(got[1], ["close", null], "close")
	t.eq(got[2][0], "path", "primary button carries its own action name")
	_done(s)


func test_chrome_actions_emit(t) -> void:
	var s := _screen(t)
	s.apply(FixturesResearch.research())
	var got: Array = []
	s.action.connect(func(n, a): got.append([n, a]))
	_find(s, "Zoom in").pressed.emit()
	_find(s, "Zoom out").pressed.emit()
	_find(s, "Domain").pressed.emit()
	_find(s, "Implemented").pressed.emit()
	t.eq(got[0], ["zoom", 1], "zoom in")
	t.eq(got[1], ["zoom", -1], "zoom out")
	t.eq(got[2][0], "crumb", "crumb")
	t.eq(got[3][0], "filter", "filter")
	t.eq(got[3][1]["group"], "state", "filter group")
	t.eq(got[3][1]["on"], false, "a checked row toggles off")
	_done(s)


func test_zero_options_shows_the_empty_state(t) -> void:
	var s := _screen(t)
	s.apply({"graph": {"nodes": [], "empty": {"title": "No projects yet", "body": "Build a lab to start research."}}, "detail": {}})
	t.eq(_texts(s.get_node("graph")), [], "no node buttons")
	t.ok(s.get_node("graph").get_child_count() > 0, "backdrop and empty card still draw")
	t.near(s.pan().length(), 0.0, 0.01, "nothing to pan")
	s.apply({"graph": {"nodes": []}})
	_done(s)


func test_option_without_prerequisites_is_a_plain_root(t) -> void:
	var s := _screen(t)
	s.apply({"graph": {"nodes": [{"id": "solo", "name": "Solo", "state": "available"}]}})
	t.eq(_texts(s), ["Solo"], "one card")
	_done(s)


func test_missing_prerequisite_id_still_builds(t) -> void:
	var s := _screen(t)
	s.apply({"graph": {"nodes": [{"id": "a", "name": "Alpha", "state": "available", "prereqs": ["ghost"]}, {"id": "b", "name": "Beta", "state": "blocked", "prereqs": ["a"]}]}})
	t.eq(_texts(s), ["Alpha", "Beta"], "both cards exist, no crash")
	_done(s)


func test_forty_options_build_and_pan(t) -> void:
	var s := _screen(t)
	s.apply(_graph_vm(40))
	var names: Array = _texts(s)
	t.eq(names.size(), 40, "forty card buttons")
	t.near(s.pan().x, 0.0, 0.01, "starts at the origin")
	s._on_pan(Vector2(-5000, -5000))
	t.ok(s.pan().x > 0.0, "the viewport pans right")
	t.ok(s.pan().x <= Layout.world_size(7, 8).x, "pan is clamped to the world")
	s.focus_node("p39")
	t.ok(s.pan().length() > 0.0, "focus_node scrolls to a far card")
	_done(s)


func test_very_long_name_is_truncated_but_keeps_its_button_text(t) -> void:
	var long_name := "Hyper-extended multi-domain autonomous industrial logistics orchestration programme"
	var s := _screen(t)
	s.apply({"graph": {"nodes": [{"id": "long", "name": long_name, "state": "available", "tags": [{"label": "Engineering", "tone": "blue"}]}]}})
	t.eq(_texts(s), [long_name], "the hit button keeps the full name for QA")
	var shown := ""
	for l in s.get_node("graph").find_children("*", "Control", true, false):
		var txt = l.get("text")
		if txt is String and txt.begins_with("Hyper") and txt != long_name:
			shown = txt
	t.ok(shown != "" and shown.ends_with("..."), "title is ellipsised to fit the card (%s)" % shown)
	t.ok(shown.length() < long_name.length(), "shorter than the full name")
	_done(s)


func test_optional_detail_blocks_are_omitted_when_absent(t) -> void:
	var s := _screen(t)
	var full := FixturesResearch.research()
	s.apply(full)
	var full_nodes: int = s.get_node("detail").find_children("*", "", true, false).size()
	var bare := {"detail": {"title": "Smart grids", "state": {"label": "Available", "tone": "cyan"}, "primary": {"label": "Research", "action": "research", "arg": "smart_grids"}}}
	s.apply(bare)
	var bare_nodes: int = s.get_node("detail").find_children("*", "", true, false).size()
	t.ok(bare_nodes < full_nodes / 2, "no bottleneck, path, retrofit, effect or honesty nodes (%d vs %d)" % [bare_nodes, full_nodes])
	t.ok(_find(s, "Research") != null, "primary button still present")
	t.ok(_find(s, "Fund theory") == null, "no secondary button when absent")
	var got: Array = []
	s.action.connect(func(n, a): got.append([n, a]))
	_find(s, "Research").pressed.emit()
	t.eq(got, [["research", "smart_grids"]], "research emits the project id")
	_done(s)


func test_detail_empty_state_when_nothing_selected(t) -> void:
	var s := _screen(t)
	s.apply({"detail": {"empty": "Select a project."}})
	t.ok(s.get_node("detail").get_child_count() > 0, "drawer shell and hint draw")
	t.eq(_texts(s.get_node("detail")), [], "no buttons")
	_done(s)


func test_disabled_primary_button(t) -> void:
	var s := _screen(t)
	s.apply({"detail": {"title": "X", "primary": {"label": "Fund theory", "action": "research", "arg": "x", "disabled": true}}})
	t.ok(_find(s, "Fund theory").disabled, "disabled is applied")
	_done(s)


func test_unchanged_slice_keeps_nodes(t) -> void:
	var s := _screen(t)
	var vm := FixturesResearch.research()
	s.apply(vm)
	var graph: Node = s.get_node("graph")
	var first := graph.get_child(0)
	vm["detail"]["title"] = "Other"
	s.apply(vm)
	t.ok(s.get_node("graph") == graph and graph.get_child(0) == first, "graph survives a detail change")
	_done(s)


func test_zoom_scale_applies_to_the_world(t) -> void:
	var s := _screen(t)
	var vm := FixturesResearch.research()
	s.apply(vm)
	vm["zoom"]["scale"] = 0.5
	s.apply(vm)
	t.near(s._world.scale.x, 0.5, 0.001, "world scale follows zoom.scale")
	_done(s)


func test_blocks_point(t) -> void:
	var s := _screen(t)
	t.ok(s.blocks_point(Vector2(10, 10)), "modal overlay blocks clicks")
	s.visible = false
	t.ok(not s.blocks_point(Vector2(10, 10)), "hidden screen does not")
	_done(s)
