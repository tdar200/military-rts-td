extends RefCounted
const Section := preload("res://scripts/ui/sections/alert_chips.gd")
const U := preload("res://tests/section_util.gd")


func test_idle_chip_shows_real_count_and_is_a_button(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, {"idle": {"count": 3, "first_id": 41}}, func(action, arg): calls.append([action, arg]))
	var btn := U.button_with(root, "Idle crews")
	t.ok(btn != null and btn.text.contains("3"), "idle crews chip with the count")
	t.ok(U.has_text(root, "3 idle crews"), "the chip reads like the board")
	btn.pressed.emit()
	t.eq(calls, [["select_idle", 41]], "clicking selects the first idle unit")
	root.free()


func test_singular_and_next_alert_clock(t) -> void:
	var root := Control.new()
	Section.build(root, {"idle": {"count": 1, "first_id": 7}, "alert": {"label": "Wave 03", "seconds": 112}})
	t.ok(U.has_text(root, "1 idle crew"), "singular")
	t.ok(not U.has_text(root, "1 idle crews"), "no plural for one")
	t.ok(U.has_text(root, "Next alert"), "next alert label")
	t.ok(U.has_text(root, "01:52"), "112 s is 01:52")
	t.eq(U.buttons(root).size(), 1, "only the idle chip is clickable")
	root.free()
	t.eq(Section.clock(5), "00:05", "clock pads")
	t.eq(Section.clock(600), "10:00", "clock minutes")


func test_each_chip_needs_its_own_slice(t) -> void:
	var only_alert := Control.new()
	Section.build(only_alert, {"alert": {"label": "Wave 01", "seconds": 90}})
	t.ok(U.button_with(only_alert, "Idle crews") == null, "no idle slice, no idle chip")
	t.ok(U.has_text(only_alert, "01:30"), "alert chip alone")
	only_alert.free()
	var zero := Control.new()
	Section.build(zero, {"idle": {"count": 0, "first_id": -1}})
	t.eq(zero.get_child_count(), 0, "zero idle crews builds nothing")
	zero.free()


func test_absent_slices_build_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	t.eq(root.get_child_count(), 0, "no slice, no nodes, no fake zero")
	root.free()
