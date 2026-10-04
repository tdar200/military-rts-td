extends RefCounted
const Section := preload("res://scripts/ui/sections/army_orders.gd")
const U := preload("res://tests/section_util.gd")


func test_buttons_carry_the_real_counts_and_emit(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, {"army": {"count": 12, "idle": 3, "first_idle": 41}}, func(action, arg): calls.append([action, arg]))
	var army := U.button_with(root, "Select army")
	var idle := U.button_with(root, "Idle crews")
	t.ok(army != null, "a Select army button")
	t.ok(idle != null and idle.text.contains("3"), "Idle crews button with the real count")
	army.pressed.emit()
	idle.pressed.emit()
	t.eq(calls, [["select_army", null], ["select_idle", 41]], "each button emits its action; idle carries the first idle id")
	root.free()


func test_each_button_exists_only_with_its_own_count(t) -> void:
	var only_army := Control.new()
	Section.build(only_army, {"army": {"count": 5, "idle": 0, "first_idle": -1}})
	t.ok(U.button_with(only_army, "Select army") != null, "army present")
	t.ok(U.button_with(only_army, "Idle crews") == null, "no idle units, no idle button")
	only_army.free()
	var only_idle := Control.new()
	Section.build(only_idle, {"army": {"count": 0, "idle": 2, "first_idle": 9}})
	t.ok(U.button_with(only_idle, "Select army") == null, "no army, no select button")
	t.ok(U.button_with(only_idle, "Idle crews 2") != null, "idle present")
	only_idle.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"army": {"count": 0, "idle": 0, "first_idle": -1}})
	t.eq(root.get_child_count(), 0, "no units, no buttons, no fake zeros")
	root.free()


func test_select_army_shows_no_ctrl_a_key_cap(t) -> void:
	var root := Control.new()
	Section.build(root, {"army": {"count": 5, "idle": 1, "first_idle": 3}})
	t.ok(not U.has_text(root, "Ctrl"), "Ctrl+A would collide with camera pan, so no key text")
	root.free()
