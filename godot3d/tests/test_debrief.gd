extends RefCounted
const Debrief = preload("res://scripts/ui/debrief.gd")
const Chart = preload("res://scripts/ui/components/line_chart.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const Fixtures = preload("res://scripts/gallery/fixtures_debrief.gd")
const LiveScreens = preload("res://scripts/ui/live_screens.gd")
const StubGame = preload("res://tests/stub_game.gd")


func _col(vm: Dictionary) -> Control:
	var col := Debrief.new()
	col.apply(vm)
	return col


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button and node.text != "":
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _find(node: Node, script: Script, out: Array = []) -> Array:
	if node.get_script() == script:
		out.append(node)
	for c in node.get_children():
		_find(c, script, out)
	return out


func _texts(node: Node, out: Array = []) -> Array:
	if node is TextBox:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


## Every block sits inside the column and no two blocks share a pixel row.
func _check_layout(t, col: Control, what: String) -> void:
	var rects: Array = col.blocks.values()
	var names: Array = col.blocks.keys()
	for i in rects.size():
		var r: Rect2 = rects[i]
		t.ok(r.position.x >= 0.0 and r.end.x <= 960.0 + 0.01, "%s: %s inside the column (%s)" % [what, names[i], str(r)])
		t.ok(r.size.y >= 0.0, "%s: %s has a height" % [what, names[i]])
		for j in range(i + 1, rects.size()):
			t.ok(not r.intersects(rects[j]), "%s: %s overlaps %s (%s vs %s)" % [what, names[i], names[j], str(r), str(rects[j])])
	if col.blocks.has("buttons"):
		var below: float = col.blocks["buttons"].position.y
		for i in rects.size():
			if names[i] != "buttons":
				t.ok(rects[i].end.y <= below + 0.01, "%s: %s ends above the buttons" % [what, names[i]])
	t.ok(col.content_height <= col.size.y + 0.01, what + ": the column is as tall as its content")


func test_empty_view_model(t) -> void:
	var col := _col({})
	t.eq(col.variant, "victory", "variant defaults to victory")
	t.ok(_buttons(col).is_empty(), "no buttons without data")
	t.eq(col.size, Vector2(960, 1080), "column keeps its size")
	t.eq(col.mouse_filter, Control.MOUSE_FILTER_IGNORE, "empty areas let clicks through")
	col.free()


func test_victory_fixture(t) -> void:
	var col := _col(Fixtures.victory())
	for name in ["header", "headline", "stats", "charts", "teaser", "footer", "buttons"]:
		t.ok(col.blocks.has(name), "victory has " + name)
	t.ok(not col.blocks.has("timeline") and not col.blocks.has("chain"), "defeat blocks stay out of a victory")
	t.eq(_find(col, Chart).size(), 1, "one economy chart")
	var labels := []
	for b in _buttons(col):
		labels.append(b.text)
	t.eq(labels, ["Next horizon", "Replay", "Restart"], "buttons carry their labels")
	_check_layout(t, col, "victory")
	col.free()


func test_defeat_fixture(t) -> void:
	var col := _col(Fixtures.defeat())
	t.eq(col.variant, "defeat", "variant")
	for name in ["header", "headline", "chips", "timeline", "chain", "advice", "buttons"]:
		t.ok(col.blocks.has(name), "defeat has " + name)
	t.ok(not col.blocks.has("stats") and not col.blocks.has("charts"), "victory blocks stay out of a defeat")
	var labels := []
	for b in _buttons(col):
		labels.append(b.text)
	t.eq(labels, ["Retry from checkpoint", "Review replay", "Restart"], "buttons carry their labels")
	_check_layout(t, col, "defeat")
	t.near(col.blocks["buttons"].position.y, 992.0, 0.01, "buttons pinned to the bottom")
	col.free()


func test_actions_emit(t) -> void:
	for vm in [Fixtures.victory(), Fixtures.defeat()]:
		var col := _col(vm)
		var got: Array = []
		col.action.connect(func(n, a): got.append([n, a]))
		for b in _buttons(col):
			b.pressed.emit()
		t.eq(got, [["continue", null], ["replay", null], ["restart", null]], vm["variant"] + " actions in order")
		col.free()


func test_same_view_model_keeps_nodes(t) -> void:
	var vm := Fixtures.victory()
	var col := _col(vm)
	var first: Node = col.get_child(0)
	col.apply(vm.duplicate(true))
	t.ok(col.get_child(0) == first, "an unchanged view model does not rebuild (a click would be lost)")
	vm["stats"][0]["value"] = "13:00"
	col.apply(vm)
	t.ok(col.get_child(0) != first, "a changed view model rebuilds")
	col.free()


func test_no_chart_series(t) -> void:
	var vm := Fixtures.victory()
	vm["economy"]["series"] = []
	var col := _col(vm)
	t.eq(_find(col, Chart).size(), 0, "no chart without a series")
	t.ok(col.blocks.has("charts"), "casualties remain")
	t.near(col.blocks["charts"].size.x, 848.0, 0.01, "casualties take the whole row")
	_check_layout(t, col, "no series")
	col.free()
	vm = Fixtures.victory()
	vm.erase("economy")
	col = _col(vm)
	t.eq(_find(col, Chart).size(), 0, "no chart without an economy block")
	col.free()


func test_chart_without_casualties_closes_up(t) -> void:
	var vm := Fixtures.victory()
	vm.erase("casualties")
	var col := _col(vm)
	t.eq(_find(col, Chart).size(), 1, "chart stays")
	t.near(col.blocks["charts"].size.x, 848.0, 0.01, "chart takes the whole row")
	_check_layout(t, col, "chart only")
	col.free()


func test_nothing_to_show_omits_everything(t) -> void:
	var vm := Fixtures.victory()
	for k in ["stats", "casualties", "economy", "teaser", "footer"]:
		vm.erase(k)
	var col := _col(vm)
	t.eq(col.blocks.keys().size(), 3, "header, headline and buttons only")
	_check_layout(t, col, "bare")
	col.free()


func test_chart_series_sizes(t) -> void:
	for n in [1, 2, 500]:
		var series := []
		for i in n:
			series.append([i * 3.0, 100.0 + (i % 37) * 20.0])
		var vm := Fixtures.victory()
		vm["economy"] = {"series": series, "waves": [], "marks": []}
		var col := _col(vm)
		var chart: Chart = _find(col, Chart)[0]
		t.eq(chart.series.size(), n, "%d points kept" % n)
		t.ok(chart.y_max >= 100.0 and chart.y_max <= 1000.0, "%d points: axis fits the data" % n)
		t.ok(chart.get_child_count() < 30, "%d points: the label count stays bounded (%d)" % [n, chart.get_child_count()])
		t.ok(chart.x_at(series[-1][0]) <= chart.plot_right() + 0.01, "%d points end inside the plot" % n)
		_check_layout(t, col, "series %d" % n)
		col.free()


func test_chart_helpers(t) -> void:
	t.near(Chart.nice_ceiling(1416.7), 1500.0, 0.001, "1,417 rounds to 1,500")
	t.near(Chart.nice_ceiling(0.0), 1.0, 0.001, "empty data gets a unit axis")
	t.near(Chart.nice_ceiling(7.0), 8.0, 0.001, "7 rounds to 8")
	t.eq(Chart.group(1420), "1,420", "thousands grouping")
	t.eq(Chart.group(-1234567), "-1,234,567", "negative grouping")
	t.eq(Chart.clock(721.0), "12:01", "clock")
	t.near(Chart.tick_step(721.0), 180.0, 0.001, "the mock's run steps every 3:00")
	t.ok(721.0 / Chart.tick_step(721.0) <= 4.1 and 100000.0 / Chart.tick_step(100000.0) <= 4.1, "long runs keep four ticks")
	var chart := Chart.new()
	chart.setup({"series": [[0, 0], [100, 100]], "width": 420})
	t.near(chart.value_at(50.0), 50.0, 0.001, "value interpolates")
	t.near(chart.value_at(500.0), 100.0, 0.001, "value clamps past the end")
	chart.setup({})
	t.eq(chart.series.size(), 0, "an empty chart builds")
	chart.free()


func test_zero_casualties(t) -> void:
	var vm := Fixtures.victory()
	for r in vm["casualties"]["rows"]:
		r["lost"] = 0
	var col := _col(vm)
	t.ok(_texts(col).has("0 / 31"), "zero losses are shown, not hidden")
	_check_layout(t, col, "zero losses")
	col.free()
	for r in vm["casualties"]["rows"]:
		r["produced"] = 0
	col = _col(vm)
	t.ok(_texts(col).has("0 / 0"), "zero produced does not divide by zero")
	col.free()


func test_defeat_empty_timeline(t) -> void:
	var vm := Fixtures.defeat()
	vm["timeline"]["rows"] = []
	var col := _col(vm)
	t.ok(not col.blocks.has("timeline"), "no timeline block")
	t.ok(col.blocks.has("chain") and col.blocks.has("advice"), "the rest closes up")
	t.ok(col.blocks["chain"].position.y < 400.0, "the chain moves up under the chips")
	_check_layout(t, col, "empty timeline")
	col.free()
	vm = Fixtures.defeat()
	vm.erase("timeline")
	vm.erase("chips")
	vm.erase("chain")
	vm.erase("advice")
	col = _col(vm)
	_check_layout(t, col, "defeat with only a headline")
	col.free()


func test_defeat_twelve_rows(t) -> void:
	var vm := Fixtures.defeat()
	var rows: Array = vm["timeline"]["rows"]
	while rows.size() < 12:
		rows.append(rows[rows.size() % 6].duplicate(true))
	var col := _col(vm)
	t.ok(col.blocks["timeline"].size.y > 560.0, "timeline grows with its rows")
	t.ok(col.content_height > 1080.0, "the column grows, the buttons go down")
	t.eq(col.size.y, col.content_height, "size follows content")
	t.near(col.blocks["buttons"].end.y + 44.0, col.content_height, 0.01, "bottom padding kept")
	_check_layout(t, col, "twelve rows")
	var host := Vector2(1920, 1080)
	Debrief.place_in(col, host)
	t.ok(col.scale.x < 1.0, "an over-tall column is scaled to fit")
	t.near(col.size.y * col.scale.y, 1080.0, 1.0, "scaled height fits the host")
	col.free()


func test_long_names(t) -> void:
	var long := "Operation " + "Dawnshield ".repeat(12)
	var vm := Fixtures.victory()
	vm["operation"] = long
	vm["title"] = "The " + "Extraordinarily Long Chapter Name ".repeat(4)
	vm["casualties"]["rows"][0]["name"] = "Heavily armoured expeditionary infantry battalion " + "x".repeat(40)
	vm["teaser"]["title"] = "Off-world command signature detected " + "again ".repeat(10)
	vm["stats"][1]["label"] = "Waves survived in the northern campaign"
	var col := _col(vm)
	_check_layout(t, col, "long victory names")
	t.ok(col.blocks["headline"].size.y >= 76.0 * 2.0, "a long title wraps onto more lines")
	col.free()
	vm = Fixtures.defeat()
	vm["status"] = "Alien Core Node survived at 4,800 / 12,000 HP " + "and kept going ".repeat(5)
	vm["operation"] = long
	vm["title"] = "Headquarters " + "overrun ".repeat(20)
	vm["timeline"]["rows"][0]["label"] = "Supply route to the far northern outpost"
	vm["chain"] = ["A very long first step " + "indeed ".repeat(20), "Second", "Third"]
	vm["advice"] = ["Place a forward depot " + "far ".repeat(60)]
	col = _col(vm)
	_check_layout(t, col, "long defeat names")
	col.free()


func _header_boxes(col: Control) -> Array:
	var out: Array = []
	var limit: float = col.blocks["header"].end.y
	for c in col.get_children():
		if (c is TextBox or c.get_script() != null) and c.position.y < limit and c.size.x > 0.0 and c.size.y < 30.0:
			out.append(Rect2(c.position, c.size))
	return out


func test_header_texts_never_collide(t) -> void:
	var vm := Fixtures.victory()
	vm["operation"] = "Operation " + "Dawnshield ".repeat(12)
	var col := _col(vm)
	var boxes := _header_boxes(col)
	t.ok(boxes.size() >= 3, "tag, operation and status are all there")
	for i in boxes.size():
		t.ok(boxes[i].end.x <= 904.01, "header text %d stays inside the column" % i)
		for j in range(i + 1, boxes.size()):
			t.ok(not boxes[i].intersects(boxes[j]), "header texts %d and %d overlap (%s, %s)" % [i, j, str(boxes[i]), str(boxes[j])])
	col.free()
	vm = Fixtures.defeat()
	vm["operation"] = "Operation Dawnshield"
	col = _col(vm)
	boxes = _header_boxes(col)
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			t.ok(not boxes[i].intersects(boxes[j]), "the mock's own header does not collide (%d, %d)" % [i, j])
	col.free()


func test_place_in(t) -> void:
	var col := _col(Fixtures.victory())
	Debrief.place_in(col, Vector2(1920, 1080))
	t.eq(col.position, Vector2(480, 0), "centred on the scrim")
	t.eq(col.scale, Vector2(1, 1), "no scaling when it fits")
	Debrief.place_in(col, Vector2(1280, 720))
	t.near(col.scale.x, 720.0 / 1080.0, 0.001, "scaled to the shorter side")
	t.near(col.position.x, (1280.0 - 960.0 * col.scale.x) * 0.5, 1.0, "still centred")
	Debrief.place_in(col, Vector2(2560, 1440))
	t.eq(col.scale, Vector2(1, 1), "never enlarged")
	col.free()


func test_debrief_offers_restart_menu_and_quit(t) -> void:
	var g := StubGame.new()  # tests/stub_game.gd
	g.bridge_winner = 1
	var vm := LiveScreens.debrief_vm(g, null)
	var actions := []
	for b in vm.buttons:
		actions.append(b.action)
	t.eq(actions, ["review", "restart", "menu", "quit"])
	t.eq(vm.buttons.map(func(b): return b.label), ["Review battlefield", "Restart", "Main menu", "Quit"], "labels")
	g.bridge_winner = 0
	t.eq(LiveScreens.debrief_vm(g, null).buttons.map(func(b): return b.action), ["review", "restart", "menu", "quit"], "victory too")
	var col := _col(vm)
	_check_layout(t, col, "four buttons")
	for b in _buttons(col):
		t.ok(b.get_minimum_size().x <= b.size.x + 0.5, "%s fits its button" % b.text)
	col.free()
