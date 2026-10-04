extends RefCounted
const Live = preload("res://scripts/ui/live_research.gd")
const Stub = preload("res://tests/stub_game.gd")
const Screen = preload("res://scripts/ui/research_screen.gd")


func _opt(id: int, name: String, o := {}) -> Dictionary:
	var d := {"id": id, "name": name, "branch": 1, "step": 0, "reality": "Achieved", "money": 250, "duration": 900, "unlocks": "Building: Lab  •  Unit: Tank", "recommended": false, "available": false, "researched": false, "prerequisites": ""}
	d.merge(o, true)
	return d


func _game() -> Stub:
	var g := Stub.new()
	g.bridge_research_options = [
		_opt(0, "Aircraft", {"researched": true}),
		_opt(1, "Batteries", {"researched": true, "branch": 1}),
		_opt(2, "Smart grids", {"available": true, "prerequisites": "Batteries"}),
		_opt(3, "AI-assisted science", {"prerequisites": "Smart grids + Missing project", "branch": 0}),
	]
	return g


func _node(vm: Dictionary, id: String) -> Dictionary:
	for n in vm["graph"]["nodes"]:
		if n["id"] == id:
			return n
	return {}


func test_states_and_prereqs_from_live_options(t) -> void:
	var g := _game()
	var vm: Dictionary = Live.new().vm(g)
	t.eq(_node(vm, "0")["state"], "implemented", "researched")
	t.eq(_node(vm, "2")["state"], "available", "available")
	t.eq(_node(vm, "3")["state"], "blocked", "blocked")
	t.eq(_node(vm, "2")["prereqs"], ["1"], "name resolved to an id")
	t.eq(_node(vm, "3")["prereqs"], ["2"], "an unknown prerequisite name is dropped")
	t.eq(_node(vm, "0")["prereqs"], [], "a project with no prerequisites has no edges")
	t.eq(_node(vm, "0")["segments"], [1.0, 1.0, 1.0], "complete")
	t.eq(_node(vm, "2")["footer"]["text"], "Building: Lab, Unit: Tank", "bullets become commas")
	t.ok(vm["graph"]["click_to_start"], "one click starts an available project (QA and players)")
	g.bridge_active_research_id = 2
	g.bridge_active_research_ticks = 450
	vm = Live.new().vm(g)
	t.eq(_node(vm, "2")["state"], "active", "active")
	t.near(_node(vm, "2")["segments"][1], 0.5, 0.001, "half done")


func test_no_options_means_an_empty_graph_not_an_error(t) -> void:
	var g := Stub.new()
	var vm: Dictionary = Live.new().vm(g)
	t.eq(vm["graph"]["nodes"], [], "no nodes")
	t.ok(vm["graph"]["empty"]["body"].contains("laboratory"), "tells the player what to do")
	t.ok(vm["detail"].has("empty"), "detail asks for a selection")
	t.eq(vm["filters"]["groups"].size(), 1, "only the state group when there are no branches to list")
	var screen := Screen.new()
	screen.apply(vm)
	screen.free()


func test_selection_drives_detail_and_highlight(t) -> void:
	var g := _game()
	var live := Live.new()
	t.eq(live.handle("select", "3"), {}, "select returns no command")
	var vm: Dictionary = live.vm(g)
	t.eq(vm["graph"]["highlight"], ["1", "2", "3"], "chain from the root to the selection")
	t.eq(vm["detail"]["title"], "AI-assisted science", "detail title")
	t.eq(vm["detail"]["state"]["label"], "Blocked", "state tag")
	t.eq(vm["detail"]["bottleneck"]["text"], "Needs Smart grids.", "what is missing")
	t.ok(vm["detail"]["primary"]["disabled"], "cannot start a blocked project")
	live.handle("select", "2")
	vm = live.vm(g)
	t.ok(not vm["detail"]["primary"]["disabled"], "an available project can start")
	t.ok(not vm["detail"].has("bottleneck"), "nothing blocks it")
	g.bridge_active_research_id = 7
	g.bridge_active_research_name = "Other"
	vm = live.vm(g)
	t.ok(vm["detail"]["primary"]["disabled"], "a running project blocks starting another")
	t.eq(vm["detail"]["bottleneck"]["title"], "Laboratory busy", "says why")
	live.handle("select", "0")
	vm = live.vm(g)
	t.ok(not vm["detail"].has("bottleneck"), "a project with no prerequisites has no bottleneck")
	t.eq(vm["graph"]["highlight"], ["0"], "its chain is just itself")


func test_actions(t) -> void:
	var live := Live.new()
	t.eq(live.handle("research", "2"), {"research": 2}, "start research")
	t.eq(live.handle("close", null), {"close": true}, "close")
	live.handle("zoom", 1)
	t.near(live.scale, 1.1, 0.001, "zoom in")
	for i in 20:
		live.handle("zoom", -1)
	t.near(live.scale, 0.5, 0.001, "zoom clamps at the minimum")
	live.handle("zoom_to", 1.0)
	t.near(live.scale, 1.5, 0.001, "zoom_to maps 0..1 onto the range")
	live.handle("search", "grid")
	live.handle("filter", {"group": "state", "id": "blocked", "on": false})
	var vm: Dictionary = live.vm(_game())
	t.ok(_node(vm, "3").get("dim", false), "blocked row is switched off")
	t.ok(not _node(vm, "2").get("dim", false), "matches the search and is not filtered")
	t.ok(_node(vm, "0").get("dim", false), "does not match the search")
	live.handle("filter", {"group": "state", "id": "blocked", "on": true})
	t.ok(not live.vm(_game())["graph"]["nodes"].is_empty(), "switching it back on keeps nodes")


func test_vm_drives_the_real_screen_with_name_buttons(t) -> void:
	var g := _game()
	var live := Live.new()
	live.handle("select", "2")
	var screen := Screen.new()
	t.root.add_child(screen)
	screen.apply(live.vm(g))
	var texts: Array = []
	for b in screen.find_children("*", "Button", true, false):
		texts.append(b.text)
	t.ok(texts.has("Smart grids"), "a project card is a button named after the project")
	t.ok(texts.has("Close"), "the header close button")
	t.ok(texts.has("Start research"), "the detail action")
	var got: Array = []
	screen.action.connect(func(n, a): got.append([n, a]))
	for b in screen.find_children("*", "Button", true, false):
		if b.text == "Smart grids":
			b.pressed.emit()
	t.eq(got, [["select", "2"], ["research", "2"]], "clicking an available card selects and starts it")
	screen.free()


func test_card_tags_fit_beside_the_state_tag_for_every_branch(t) -> void:
	var g := Stub.new()
	for branch in 8:
		g.bridge_research_options.append(_opt(branch, "Project %d" % branch, {"branch": branch}))
	g.bridge_research_options.append(_opt(9, "Unknown branch", {"branch": 99}))
	var vm: Dictionary = Live.new().vm(g)
	for n in vm["graph"]["nodes"]:
		t.ok(String(n["tags"][0]["label"]).length() <= 16, "card tag short enough: " + n["tags"][0]["label"])
	vm = Live.new().vm(g)
	t.eq(vm["graph"]["nodes"][6]["tags"][0]["label"], "Biology", "the long branch is shortened on cards")
	var detail_live := Live.new()
	detail_live.selected = "6"
	t.eq(detail_live.vm(g)["detail"]["tags"][0]["label"], "Biology / civilisation", "the drawer keeps the full name")
