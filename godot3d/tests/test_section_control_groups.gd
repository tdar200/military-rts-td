extends RefCounted
const Section := preload("res://scripts/ui/sections/control_groups.gd")
const U := preload("res://tests/section_util.gd")


func _groups() -> Dictionary:
	return {"control_groups": {"slots": [
		{"n": 1, "count": 9, "label": "Battle tank", "on": true},
		{"n": 2, "count": 3, "label": "Rocket team", "on": false},
		{"n": 3, "count": 0, "label": "", "on": false},
		{"n": 4, "count": 0, "label": "", "on": false},
	]}}


func test_rows_show_slot_key_label_and_count(t) -> void:
	var root := Control.new()
	Section.build(root, _groups())
	t.ok(U.has_text(root, "Control groups"), "caption")
	t.ok(U.has_text(root, "Battle tank"), "slot 1 label")
	t.ok(U.has_text(root, "9"), "slot 1 count")
	t.ok(U.has_text(root, "Rocket team"), "slot 2 label")
	t.ok(U.has_text(root, "empty"), "unassigned slots read empty")
	root.free()


func test_assigned_slots_recall_their_group(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, _groups(), func(action, arg): calls.append([action, arg]))
	var b1 := U.button_with(root, "Group 1")
	var b2 := U.button_with(root, "Group 2")
	t.ok(b1 != null and b2 != null, "Buttons for the assigned slots, with human labels")
	b1.pressed.emit()
	b2.pressed.emit()
	t.eq(calls, [["recall_group", 1], ["recall_group", 2]], "each recalls its group")
	t.ok(U.button_with(root, "Group 3") == null, "an empty slot is not clickable")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"control_groups": {}})
	t.eq(root.get_child_count(), 0, "no groups, no panel")
	root.free()
