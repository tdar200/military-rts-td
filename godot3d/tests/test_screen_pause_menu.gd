extends RefCounted
const Menu := preload("res://scripts/ui/sections/pause_menu.gd")
const Vm := preload("res://scripts/ui/vm_gameplay.gd")
const U := preload("res://tests/section_util.gd")


func _snapshot() -> Dictionary:
	var s: Dictionary = JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())
	s["tick"] = 26280  # 14:36 at 30 ticks a second
	s["waves_survived"] = 2
	s["next_wave_ticks"] = 3360  # 112 s
	s["money_bits"] = 840 * 65536
	s["power_generation"] = 160
	s["power_demand"] = 168
	return s


func _row(vm: Dictionary, label: String) -> Dictionary:
	for r in vm["rows"]:
		if r["label"] == label:
			return r
	return {}


## Builds the screen with a recording emit and returns [root, log].
func _screen(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Menu.build(root, vm, func(name: String, _arg: Variant = null) -> void: log.append(name))
	return [root, log]


func _click(root: Node, text: String, nth := 0) -> void:
	var matches: Array = []
	for b in U.buttons(root):
		if (b as Button).text == text:
			matches.append(b)
	matches.sort_custom(func(a, b): return a.position.y < b.position.y)
	(matches[nth] as Button).pressed.emit()


# ------------------------------------------------------------------ the snapshot rows

func test_snapshot_rows_are_the_kestrel_values(t) -> void:
	var vm := Vm.pause(_snapshot(), 4, true)
	t.eq(vm["map"], "Kestrel Reach", "the map name from the snapshot")
	t.eq(_row(vm, "Waves survived")["value"], "2", "waves survived")
	t.eq(_row(vm, "Elapsed")["value"], "14:36", "tick 26280 at 30 ticks a second is 14:36")
	t.eq(_row(vm, "Next wave")["value"], "01:52", "3360 ticks is 112 s")
	t.eq(_row(vm, "Material")["value"], "840", "material")
	t.eq(_row(vm, "Power")["value"], "160 / 168 kW", "generation over demand, as the top bar prints it")
	t.eq(_row(vm, "Power")["tone"], "warn", "demand above generation is a warning")
	t.eq(_row(vm, "Units alive")["value"], "5", "the Kestrel start's four riflemen and its harvester")
	t.eq(_row(vm, "Losses")["value"], "4", "the client's own loss count")


func test_rows_that_have_no_data_are_not_built(t) -> void:
	var s := _snapshot()
	s.erase("next_wave_ticks")
	s.erase("money_bits")
	var vm := Vm.pause(s, -1, true)
	t.ok(_row(vm, "Next wave").is_empty(), "no countdown, no row")
	t.ok(_row(vm, "Material").is_empty(), "no material, no row")
	t.ok(_row(vm, "Losses").is_empty(), "no loss count, no row")
	for fake in ["Objective", "Last save"]:
		t.ok(_row(Vm.pause(_snapshot(), 4, true), fake).is_empty(), fake + " has no data and is never built")
	t.ok(Vm.pause({}, 0, true).is_empty(), "no snapshot, no slice")
	var cool := _snapshot()
	cool["power_demand"] = 100
	t.eq(_row(Vm.pause(cool, 0, true), "Power")["tone"], "", "no warning while generation covers demand")


func test_tick_rate_is_the_huds_constant(t) -> void:
	var s := _snapshot()
	s["tick"] = int(load("res://scripts/ui/live_adapter.gd").TICKS_PER_SECOND) * 61
	t.eq(_row(Vm.pause(s, 0, true), "Elapsed")["value"], "01:01", "61 s")


# ------------------------------------------------------------------ the screen

func test_screen_shows_the_real_labels_and_values(t) -> void:
	var p := _screen(Vm.pause(_snapshot(), 4, true))
	var root: Control = p[0]
	for s in ["Paused", "Simulation stopped", "Kestrel Reach", "Command pause", "Mission snapshot", "Waves survived", "Elapsed", "14:36", "01:52", "840", "160 / 168 kW", "Units alive", "Losses"]:
		t.ok(U.has_text(root, s), "shows " + s)
	root.free()


func test_menu_actions_are_buttons_with_human_text(t) -> void:
	var p := _screen(Vm.pause(_snapshot(), 4, true))
	var root: Control = p[0]
	var labels: Array = U.buttons(root).map(func(b): return b.text)
	t.eq(labels, ["Resume", "Controls", "Restart mission", "Quit game"], "four buttons, in menu order")
	for b in U.buttons(root):
		t.ok(b is Button and b.text != "" and not b.text.contains("_"), "human text: " + b.text)
	_click(root, "Resume")
	_click(root, "Controls")
	t.eq(p[1], ["resume", "open_controls"], "Resume and Controls reach the host")
	root.free()


func test_key_hints_come_from_the_binding_list(t) -> void:
	var vm := Vm.pause(_snapshot(), 4, true)
	t.eq(vm["keys"], {"resume": "Esc", "controls": "F1"}, "Esc and F1")
	var root: Control = _screen(vm)[0]
	var resume := U.button_with(root, "Resume") as Button
	t.eq(resume.get("key_text"), "ESC", "the Resume button carries its key")
	root.free()


func test_restart_asks_first_and_only_the_confirm_button_restarts(t) -> void:
	var vm := Vm.pause(_snapshot(), 4, true)
	var first := _screen(vm)
	_click(first[0], "Restart mission")
	t.eq(first[1], ["ask_restart"], "the menu's Restart only asks")
	t.ok(not U.has_text(first[0], "Keep playing"), "no confirm panel until asked")
	first[0].free()
	vm["confirm"] = "restart"
	var second := _screen(vm)
	var root: Control = second[0]
	t.ok(U.has_text(root, "Restart this mission?"), "the question")
	t.ok(U.has_text(root, "You will lose 14:36 of progress. This cannot be undone."), "what is lost, from the tick")
	t.ok(U.button_with(root, "Keep playing") != null, "Keep playing is a Button")
	t.eq(U.buttons(root).filter(func(b): return b.text == "Restart mission").size(), 1, "the menu button")
	t.eq(U.buttons(root).filter(func(b): return b.text == "Restart").size(), 1, "and the confirm button, labelled as the board has it")
	_click(root, "Keep playing")
	t.eq(second[1], ["keep_playing"], "Keep playing does not restart")
	_click(root, "Restart mission")
	t.eq(second[1], ["keep_playing", "ask_restart"], "the menu's Restart mission is still only the ask")
	_click(root, "Restart")
	t.eq(second[1], ["keep_playing", "ask_restart", "restart"], "the confirm Restart button emits restart")
	root.free()


func test_quit_asks_first_too(t) -> void:
	var vm := Vm.pause(_snapshot(), 4, true)
	var first := _screen(vm)
	_click(first[0], "Quit game")
	t.eq(first[1], ["ask_quit"], "Quit only asks")
	first[0].free()
	vm["confirm"] = "quit"
	var second := _screen(vm)
	t.ok(U.has_text(second[0], "Quit the game?"), "the quit question")
	t.ok(U.has_text(second[0], "There is no save."), "honest about saving")
	_click(second[0], "Quit game", 1)
	t.eq(second[1], ["quit"], "only the confirm button quits")
	second[0].free()


func test_restart_is_hidden_when_the_host_has_no_restart(t) -> void:
	var vm := Vm.pause(_snapshot(), 4, true)
	vm["can_restart"] = false
	var root: Control = _screen(vm)[0]
	t.ok(U.button_with(root, "Restart") == null, "no Restart button without a restart command")
	t.ok(U.button_with(root, "Quit game") != null, "Quit stays")
	t.ok(not U.has_text(root, "Restart returns to the title"), "no sentence about a restart that is not there")
	root.free()


func test_features_the_game_lacks_are_not_built(t) -> void:
	var root: Control = _screen(Vm.pause(_snapshot(), 4, true))[0]
	for fake in ["Settings", "Save", "Last save", "Objective", "Autosave", "wave 02 of 05", "F10", "F5"]:
		t.ok(not U.has_text(root, fake), "no " + fake)
	for s in U.texts(root):
		t.ok(not str(s).contains("\u2014") and not str(s).contains("\u2013"), "no dash in: " + str(s))
	root.free()


func test_marker_never_claims_a_stop_that_is_not_happening(t) -> void:
	var root: Control = _screen(Vm.pause(_snapshot(), 4, false))[0]
	t.ok(U.has_text(root, "Simulation still running"), "says so when the tick keeps moving")
	t.ok(not U.has_text(root, "Simulation stopped"), "and does not claim a stop")
	root.free()


func test_absent_data_builds_nothing_or_only_the_menu(t) -> void:
	var empty := Control.new()
	Menu.build(empty, {}, Callable())
	t.eq(empty.get_child_count(), 0, "no view model, no screen")
	empty.free()
	var root: Control = _screen({"stopped": true, "keys": Vm.pause_keys()})[0]
	t.ok(U.button_with(root, "Resume") != null, "the menu still works without a snapshot")
	t.ok(not U.has_text(root, "Mission snapshot"), "but no snapshot panel with nothing to say")
	root.free()


func test_scrim_swallows_clicks_and_panels_stay_on_screen(t) -> void:
	var root: Control = _screen(Vm.pause(_snapshot(), 4, true))[0]
	var scrim := root.get_node("Scrim") as ColorRect
	t.eq(scrim.mouse_filter, Control.MOUSE_FILTER_STOP, "nothing reaches the game under the menu")
	for n in root.find_children("*", "Control", true, false):
		if n is Button:
			var b := n as Button
			t.ok(b.position.x >= 0.0 and b.position.y >= 0.0 and b.position.x + b.size.x <= 1920.0 and b.position.y + b.size.y <= 1080.0, "button inside the screen: " + b.text)
	root.free()
