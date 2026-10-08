extends RefCounted
## The Kestrel onboarding coach (kestrel-depth Task 9): KestrelCoach is pure (steps, events, hints, visibility, the
## persisted "never show again"), the game holds the current step and feeds it the player's own orders, and the HUD draws
## the card in the right column under the alert chips. Every settings file here is a temporary user://test_kestrel_coach
## path, deleted at the end; the real user://settings.cfg is never touched.
const Coach := preload("res://scripts/ui/kestrel_coach.gd")
const Settings := preload("res://scripts/ui/settings.gd")
const KB := preload("res://scripts/ui/keybinds.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const Stub := preload("res://tests/stub_game.gd")
const KestrelObjectives := preload("res://scripts/world/kestrel_objectives.gd")
const EarlyMission := preload("res://scripts/ui/sections/early_mission.gd")
const AlertChips := preload("res://scripts/ui/sections/alert_chips.gd")

const DIR := "user://test_kestrel_coach"
const EVENTS := ["selected_units", "move_sent", "build_sent", "train_sent", "attack_move_sent"]


func _path(name: String) -> String:
	return DIR.path_join(name + ".cfg")


func _cleanup() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_steps_are_the_five_lessons_then_done(t) -> void:
	t.eq(Coach.STEPS, ["select_squad", "move", "place_building", "train", "attack_move", "done"], "the plan's step list")


func test_each_step_advances_only_on_its_own_event(t) -> void:
	for i in Coach.STEPS.size() - 1:
		var step: String = Coach.STEPS[i]
		for event in EVENTS + ["", "nonsense"]:
			var want: String = Coach.STEPS[i + 1] if event == EVENTS[i] else step
			t.eq(Coach.advance(step, event), want, "%s on %s" % [step, event])
	for event in EVENTS:
		t.eq(Coach.advance("done", event), "done", "done stays done on " + event)


func test_the_coach_skips_nothing(t) -> void:
	# Later lessons' events arriving first move nothing; the lessons are walked one at a time, in order.
	var step := "select_squad"
	for event in ["attack_move_sent", "train_sent", "build_sent", "move_sent"]:
		step = Coach.advance(step, event)
	t.eq(step, "select_squad", "no later event moves the first lesson")
	var seen: Array = [step]
	for event in EVENTS:
		step = Coach.advance(step, event)
		seen.append(step)
	t.eq(seen, Coach.STEPS, "the events in order visit every step exactly once")
	t.eq(Coach.advance("select_squad", "selected_units"), "move", "one event, one step")


func test_every_lesson_has_a_hint_with_real_keys(t) -> void:
	for step in Coach.STEPS:
		var h: Dictionary = Coach.hint(step)
		if step == "done":
			t.eq(h, {}, "done has no hint")
			continue
		for key in ["title", "body", "keys"]:
			t.ok(h.has(key), "%s hint has %s" % [step, key])
		t.ok(str(h["title"]) != "" and str(h["body"]) != "", step + " has words")
		t.ok(h["keys"] is Array and not (h["keys"] as Array).is_empty(), step + " names its keys")
		t.ok(str(h["body"]).length() <= 72, "%s body fits two card lines (%d chars)" % [step, str(h["body"]).length()])
	t.ok(KB.cap(KB.SELECT_ARMY) in Coach.hint("select_squad")["keys"], "select names the army key")
	t.ok("Right click" in Coach.hint("move")["keys"], "move names the right click")
	t.ok(KB.cap(KB.BUILD.find_key("GunTurret")) in Coach.hint("place_building")["keys"], "build names the gun turret key")
	t.ok(KB.cap(KB.TRAIN.find_key("Infantry")) in Coach.hint("train")["keys"], "train names the riflemen key")
	t.ok(KB.cap(KB.ATTACK_MOVE) in Coach.hint("attack_move")["keys"], "attack-move names its key")
	for step in Coach.STEPS:
		var text := JSON.stringify(Coach.hint(step))
		t.ok(text.find(String.chr(0x2014)) < 0 and text.find(String.chr(0x2013)) < 0, step + " has no long dash")


func test_hints_follow_the_objectives(t) -> void:
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))
	var result := KestrelObjectives.evaluate(snap)
	t.eq(KestrelObjectives.IDS[int(result["stage"]) - 1], "economy", "at tick 0 the Kestrel opening still waits for ore")
	t.eq(Coach.hint_for("place_building", result)["objective"], str(result["detail"]), "the build lesson shows the economy line")
	t.eq(Coach.hint_for("train", result)["objective"], "", "the train lesson waits for the squad objective")
	t.eq(Coach.hint_for("select_squad", result)["objective"], "", "select has no objective line")
	var squad := result.duplicate(true)
	squad["stage"] = 3
	squad["detail"] = "Train riflemen (T): 4 of 6 combat units"
	t.eq(Coach.hint_for("train", squad)["objective"], "Train riflemen (T): 4 of 6 combat units", "train names the squad count")
	t.eq(Coach.hint_for("attack_move", squad)["objective"], "", "the ford line waits for the ford objective")
	var ford := result.duplicate(true)
	ford["stage"] = 4
	ford["detail"] = "Hold Wyllow Ford: first wave in 1:00"
	t.eq(Coach.hint_for("attack_move", ford)["objective"], "Hold Wyllow Ford: first wave in 1:00", "attack-move names the ford")
	ford["complete"] = true
	t.eq(Coach.hint_for("attack_move", ford)["objective"], "", "a won match has no objective line")
	t.eq(Coach.hint_for("train", {}).get("objective", ""), "", "no objective result, no line")
	t.eq(Coach.hint_for("done", result), {}, "done has nothing")


func test_visible_only_on_kestrel_until_never_show(t) -> void:
	for step in Coach.STEPS:
		t.eq(Coach.visible(step, false, true), step != "done", step + " on Kestrel")
		t.eq(Coach.visible(step, true, true), false, step + " after never show again")
		t.eq(Coach.visible(step, false, false), false, step + " on Survival")
	t.eq(Coach.visible("bogus", false, true), false, "an unknown step shows nothing")


func test_dismissal_persists_through_the_settings_file(t) -> void:
	_cleanup()
	var path := _path("dismiss")
	t.eq(Coach.never_show(path), false, "a fresh install shows the coach")
	t.eq(Settings.defaults()["coach/never_show"], false, "the default is to show it")
	t.eq(Coach.dismiss(path), OK, "dismiss saves")
	t.eq(Coach.never_show(path), true, "read back")
	t.eq(Settings.load_from(path)["coach/never_show"], true, "through the Settings owner")
	t.eq(Settings.load_from(path)["game/fog"], true, "other settings untouched")
	t.ok(Coach.dismiss("res://coach.cfg") != OK, "never under res://")
	t.ok(not FileAccess.file_exists("res://coach.cfg"), "nothing written under res://")
	_cleanup()


func _game(path: String, kestrel := true) -> Node3D:
	var g = load("res://scripts/earthfront_3d.gd").new()
	g.settings_path = path
	g.world_art_on = kestrel
	g.mission_deployed = true
	g._load_coach()
	return g


func test_the_game_walks_the_coach_on_the_players_orders(t) -> void:
	_cleanup()
	var g := _game(_path("walk"))
	t.eq(g.coach_step, "select_squad", "a first match starts at the first lesson")
	t.eq(str(g.coach_card().get("title", "")), Coach.hint("select_squad")["title"], "and shows it")
	t.eq(g.coach_card()["index"], 1, "lesson 1")
	t.eq(g.coach_card()["count"], 5, "of 5")
	g._coach_event("train_sent")
	t.eq(g.coach_step, "select_squad", "an out-of-order order moves nothing")
	for event in EVENTS:
		g._coach_event(event)
	t.eq(g.coach_step, "done", "five orders, five lessons")
	t.eq(g.coach_card(), {}, "a finished coach shows nothing")
	t.eq(Coach.never_show(_path("walk")), true, "a finished coach does not come back on the next launch")
	g.free()
	_cleanup()


func test_hide_is_for_this_match_and_never_show_is_saved(t) -> void:
	_cleanup()
	var g := _game(_path("hide"))
	g.coach_dismiss(false)
	t.eq(g.coach_card(), {}, "Hide takes the card away")
	t.ok(not FileAccess.file_exists(_path("hide")), "Hide writes nothing")
	g.free()
	var again := _game(_path("hide"))
	t.ok(not again.coach_card().is_empty(), "the next match (a scene reload) shows it again")
	again.coach_dismiss(true)
	t.eq(again.coach_card(), {}, "never show again takes it away")
	t.eq(Coach.never_show(_path("hide")), true, "and is saved")
	again.free()
	var fresh := _game(_path("hide"))
	t.eq(fresh.coach_card(), {}, "a fresh launch with the saved setting shows nothing")
	fresh.free()
	_cleanup()


func test_survival_and_a_finished_match_show_no_coach(t) -> void:
	_cleanup()
	var s := _game(_path("surv"), false)
	t.eq(s.coach_card(), {}, "Survival has no coach")
	s._coach_event("selected_units")
	t.eq(s.coach_step, "select_squad", "and Survival orders do not walk it")
	s.free()
	var k := _game(_path("won"))
	k.bridge_winner = 0
	t.eq(k.coach_card(), {}, "nothing once the match has a winner")
	k.free()
	var title := _game(_path("title"))
	title.mission_deployed = false
	t.eq(title.coach_card(), {}, "nothing on the title")
	title.free()
	t.ok(not FileAccess.file_exists(_path("surv")) and not FileAccess.file_exists(_path("won")), "nothing saved")
	_cleanup()


func test_the_order_handlers_report_to_the_coach(t) -> void:
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	for event in EVENTS:
		t.ok(src.contains("_coach_event(\"%s\")" % event), "the game sends %s" % event)
	var adapter_src := (Adapter as GDScript).source_code
	t.ok(adapter_src.contains("\"coach_hide\"") and adapter_src.contains("\"coach_never\""), "the adapter routes both buttons")


class CoachStub extends "res://tests/stub_game.gd":
	var card: Dictionary = {"index": 2, "count": 5, "title": "Move out", "body": "Right click open ground to send the selected units there.", "keys": ["Right click"], "objective": ""}
	var dismissed: Array = []

	func coach_card() -> Dictionary:
		return card

	func coach_dismiss(forever: bool) -> void:
		dismissed.append(forever)


func test_the_adapter_carries_the_card_and_routes_the_buttons(t) -> void:
	var g := CoachStub.new()
	var a := Adapter.new(g)
	a.tab = "units"
	t.eq(a.hud_vm(0.0).get("coach"), g.card, "the main layout carries the card")
	g.card = {}
	t.ok(not a.hud_vm(0.0).has("coach"), "an empty card adds no key")
	a.on_action("coach_hide", null)
	a.on_action("coach_never", null)
	t.eq(g.dismissed, [false, true], "Hide for this match, then never show again")
	var plain := Adapter.new(Stub.new())
	plain.tab = "units"
	t.ok(not plain.hud_vm(0.0).has("coach"), "a game without a coach adds none")


func _hud_with(card: Dictionary) -> Control:
	var hud := Hud.new()
	hud.apply({"coach": card})
	return hud


func test_the_card_sits_in_the_right_column_and_blocks_nothing(t) -> void:
	var card := {"index": 3, "count": 5, "title": "Place a building", "body": "Press G for a gun turret, then left click open ground in your zone.", "keys": ["G", "Left click"], "objective": "Build a Reactor (P): 60 of 90 kW"}
	var hud := _hud_with(card)
	var layer: Control = hud._layers["coach"]
	var panel: Control = layer.get_node_or_null("Coach")
	t.ok(panel != null, "the card is built")
	if panel == null:
		hud.free()
		return
	var r := Rect2(panel.position, panel.size)
	t.eq(r.position, Hud.COACH_RECT.position, "under the alert chips, right column")
	t.ok(r.end.y <= Hud.COACH_RECT.end.y, "no taller than its slot (bottom %s)" % r.end.y)
	t.ok(r.position.y >= AlertChips.Y + AlertChips.H + 8.0, "clear of the idle and next-alert chips")
	t.ok(not r.intersects(EarlyMission.rect()), "clear of the briefing card")
	t.ok(not r.intersects(Rect2(12, 76, 420, 1000)), "clear of the objectives panel and the toast column")
	t.ok(r.end.y < 494.0, "clear of the build deck panel (y 494)")
	t.ok(r.end.x <= 1908.0, "inside the top bar's right edge")
	t.eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the card itself never takes a click")
	var buttons := layer.find_children("*", "Button", true, false)
	var labels: Array = []
	for b in buttons:
		labels.append(str(b.text))
		t.eq(b.focus_mode, Control.FOCUS_NONE, str(b.text) + " never takes keyboard focus")
		t.ok(r.encloses(Rect2(b.position, b.size)), str(b.text) + " inside the card")
	t.ok("Hide" in labels and "Never show again" in labels, "two buttons (got %s)" % str(labels))
	t.ok(not hud.blocks_point(r.position + Vector2(20, 40)), "the card body lets the click through to the world")
	var got: Array = []
	hud.action.connect(func(n, _a): got.append(n))
	for b in buttons:
		b.pressed.emit()
	got.sort()
	t.eq(got, ["coach_hide", "coach_never"], "the buttons emit their actions")
	var texts := ""
	for c in layer.find_children("*", "", true, false):
		if c.get("text") != null:
			texts += str(c.text) + "|"
	t.ok(texts.to_upper().contains("PLACE A BUILDING"), "the title is drawn")
	t.ok(texts.contains("Build a Reactor (P)"), "the objective line is drawn")
	hud.free()
	var empty := _hud_with({})
	t.eq((empty._layers["coach"] as Control).get_child_count(), 0, "no card, no nodes")
	empty.free()
