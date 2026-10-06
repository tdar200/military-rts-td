extends RefCounted
## Board 6 (briefing card): objectives from the game's real tutorial stage, dismissable, never blocks input once gone.
const Card := preload("res://scripts/ui/sections/early_mission.gd")
const Maps := preload("res://scripts/ui/vm_maps.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const U := preload("res://tests/section_util.gd")


func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _screen(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Card.build(root, vm, func(name: String, _arg: Variant = null) -> void: log.append(name))
	return [root, log]


func test_items_are_the_real_stage_text(t) -> void:
	var vm := Maps.briefing(1, _snapshot())
	var details: Array = Adapter.STAGE_DETAIL
	t.eq(vm["tag"], "Step 2 of %d" % details.size(), "the step counts the real objective list")
	t.eq(vm["items"].size(), 3, "done, current, next")
	t.eq(vm["items"][0], {"t": details[0], "state": "done"}, "the finished objective")
	t.eq(vm["items"][1], {"t": details[1], "state": "active"}, "the current objective is the HUD's own text")
	t.eq(vm["items"][2], {"t": details[2], "state": "todo"}, "the next objective")
	t.near(vm["ratio"], 1.0 / float(details.size()), 0.0001, "progress is stage over the objective count")


func test_stage_zero_has_no_done_item_and_stage_three_has_no_briefing(t) -> void:
	var first := Maps.briefing(0, _snapshot())
	t.eq(first["items"][0]["state"], "active", "stage 0 starts on the active objective")
	t.ok(Maps.briefing(3, _snapshot()).is_empty(), "past the first group there is no briefing")
	t.ok(Maps.briefing(-1, _snapshot()).is_empty(), "no stage, no briefing")
	t.ok(Maps.briefing(1, _snapshot(), 0).is_empty(), "no briefing once the match is decided")


func test_region_copy_needs_its_region(t) -> void:
	var snap := _snapshot()
	t.ok(Maps.briefing(1, snap)["body"].contains("Calder River"), "the river bonus line names the snapshot's river")
	t.ok(Maps.briefing(1, snap)["body"].contains("+12 kW"), "and the mirrored sim constant")
	snap["regions"] = snap["regions"].filter(func(r): return r["kind"] != "river")
	var body: String = Maps.briefing(1, snap)["body"]
	t.ok(not body.contains("Calder") and not body.contains("beside"), "no river region, no river sentence")
	t.ok(Maps.briefing(1, {})["body"] != "", "without a snapshot the region-free copy still stands")


## This is Survival's briefing (Kestrel has its own, vm_maps.kestrel_briefing, which names the fog: test_kestrel_objectives).
## Survival has no fog of war, so whatever snapshot it is given, fogged or not, it never speaks of fog or scouting.
func test_survival_briefing_has_no_fog_or_survey_wording(t) -> void:
	var off := JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot_fog_off.json", FileAccess.READ).get_as_text()) as Dictionary
	for snap in [_snapshot(), off]:
		for stage in [0, 1, 2]:
			var vm := Maps.briefing(stage, snap)
			var text := JSON.stringify(vm).to_lower()
			for banned in ["fog", "survey", "explor", "scout", "sight"]:
				t.ok(not text.contains(banned), "stage %d never says '%s'" % [stage, banned])


func test_card_shows_title_items_and_a_hide_button(t) -> void:
	var vm := Maps.briefing(1, _snapshot())
	var p := _screen(vm)
	var root: Control = p[0]
	var shown := " ".join(U.texts(root)).to_lower()
	for want in ["briefing", "step 2 of", "power the beachhead", vm["items"][1]["t"].to_lower(), "river"]:
		t.ok(shown.contains(want), "the card shows '%s'" % want)
	var hide := U.button_with(root, "Hide")
	t.ok(hide != null, "a Hide Button with human text")
	hide.pressed.emit()
	t.eq(p[1], ["briefing_dismiss"], "Hide emits briefing_dismiss")
	root.free()


func test_empty_view_model_builds_nothing_and_rect_matches_the_panel(t) -> void:
	var p := _screen({})
	t.eq(p[0].get_child_count(), 0, "no briefing, no nodes")
	p[0].free()
	var q := _screen(Maps.briefing(1, _snapshot()))
	var panel: Control = q[0].get_node("Briefing")
	t.eq(Rect2(panel.position, panel.size), Card.rect(), "rect() is the panel's own rectangle, for hit testing")
	q[0].free()
