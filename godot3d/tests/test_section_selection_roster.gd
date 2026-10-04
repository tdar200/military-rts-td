extends RefCounted
const Section := preload("res://scripts/ui/sections/selection_roster.gd")
const U := preload("res://tests/section_util.gd")


func _roster() -> Dictionary:
	return {"roster": {
		"title": "Strike group", "count": "3 units", "armed": true, "more": 0,
		"cards": [
			{"id": 1, "kind": "Tank", "name": "Battle tank", "ratio": 0.92, "tone": "good", "rank": 2, "sprite": "res://assets/ui/sprites/tank_v2.png"},
			{"id": 2, "kind": "AntiArmor", "name": "Rocket team", "ratio": 0.41, "tone": "bad", "rank": 0, "sprite": "res://assets/ui/sprites/anti_armor_v2.png"},
			{"id": 3, "kind": "Infantry", "name": "Riflemen", "ratio": 1.0, "tone": "good", "rank": 1, "sprite": "res://assets/ui/sprites/infantry_v2.png"},
		],
		"standing": "Grassland", "speed": "speed 1.0x", "speed_tone": "good",
	}}


func _chevrons(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Control", true, false):
		if n.get("chevrons") != null:
			out.append(n.get("chevrons"))
	return out


func test_roster_has_a_card_per_unit_with_name_count_and_state(t) -> void:
	var root := Control.new()
	Section.build(root, _roster())
	t.ok(U.has_text(root, "Strike group"), "title")
	t.ok(U.has_text(root, "3 units"), "unit count tag")
	t.ok(U.has_text(root, "Armed: attack-move"), "armed tag while the stance is armed")
	for name in ["Battle tank", "Rocket team", "Riflemen"]:
		t.ok(U.has_text(root, name), "a card for %s" % name)
	t.ok(U.has_text(root, "Standing on") and U.has_text(root, "Grassland"), "ground under the group")
	t.ok(U.has_text(root, "speed 1.0x"), "its speed")
	root.free()


func test_veteran_chevrons_follow_rank(t) -> void:
	var root := Control.new()
	Section.build(root, _roster())
	var ranks := _chevrons(root)
	ranks.sort()
	t.eq(ranks, [1, 2], "one marker per ranked unit: rank 2 and rank 1, none for the rookie")
	root.free()


func test_unarmed_roster_has_no_armed_tag(t) -> void:
	var vm := _roster()
	vm["roster"]["armed"] = false
	var root := Control.new()
	Section.build(root, vm)
	t.ok(not U.has_text(root, "Armed"), "no tag when not armed")
	root.free()


func test_cancel_is_the_only_button_and_it_emits(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, _roster(), func(action, arg): calls.append([action, arg]))
	t.eq(U.buttons(root).size(), 1, "Confirm target and Queue waypoint have no command, so only Cancel exists")
	var cancel := U.button_with(root, "Cancel")
	t.ok(cancel != null, "a Cancel Button")
	cancel.pressed.emit()
	t.eq(calls, [["order", "cancel_armed"]], "cancel disarms attack-move")
	root.free()


func test_unarmed_roster_has_no_cancel(t) -> void:
	var vm := _roster()
	vm["roster"]["armed"] = false
	var root := Control.new()
	Section.build(root, vm)
	t.eq(U.buttons(root).size(), 0, "nothing to cancel")
	root.free()


func test_more_units_than_cards_is_a_count(t) -> void:
	var vm := _roster()
	vm["roster"]["more"] = 5
	var root := Control.new()
	Section.build(root, vm)
	t.ok(U.has_text(root, "+5 more"), "the overflow is a number, not hidden")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"roster": {}})
	t.eq(root.get_child_count(), 0, "no roster, no panel")
	root.free()
