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


## Groups 5 to 9 (Task 2): an assigned high slot is listed after the four bound ones and recalls like any other.
func test_a_high_group_is_listed_and_recalls(t) -> void:
	var d := _groups()
	d["control_groups"]["slots"].append({"n": 7, "count": 4, "label": "Gunship", "on": false})
	var root := Control.new()
	var calls: Array = []
	Section.build(root, d, func(action, arg): calls.append([action, arg]))
	t.ok(U.has_text(root, "Gunship"), "slot 7 label")
	var b7 := U.button_with(root, "Group 7")
	t.ok(b7 != null, "slot 7 is clickable")
	if b7 != null:
		b7.pressed.emit()
	t.eq(calls, [["recall_group", 7]], "it recalls group 7")
	var four := Control.new()
	Section.build(four, _groups())
	var panel_4 := _panel_height(four)
	var panel_5 := _panel_height(root)
	t.ok(panel_5 > panel_4, "the panel grows by the extra row (%d vs %d)" % [panel_5, panel_4])
	t.near(panel_5 - panel_4, Section.ROW_STEP, 1.0, "one row step taller")
	four.free()
	root.free()


func _panel_height(root: Control) -> float:
	var tallest := 0.0
	for c in root.get_children():
		if c is Control:
			tallest = maxf(tallest, (c as Control).size.y)
	return tallest
