extends RefCounted
const Section := preload("res://scripts/ui/sections/resource_pins.gd")
const U := preload("res://tests/section_util.gd")

const PINS := [
	{"x": 861, "y": 434, "kind": "Ore", "remaining": 1800, "claimed": true, "cell": [21, 10]},
	{"x": 1400, "y": 700, "kind": "Ore", "remaining": 24000, "claimed": false, "cell": [31, 17]},
	{"x": 300, "y": 300, "kind": "Alloy", "remaining": 15000, "claimed": false, "cell": [35, 1]},
]


func test_pin_text_uses_the_real_amounts(t) -> void:
	var root := Control.new()
	Section.build(root, {"pins": PINS})
	t.ok(U.has_text(root, "1,800 left"), "claimed ore shows what is left")
	t.ok(U.has_text(root, "Ore, unclaimed"), "an ore deposit without a refinery says so")
	t.ok(U.has_text(root, "15,000 left"), "alloy shows what is left")
	t.ok(not U.has_text(root, "+4"), "no invented haul figure")
	root.free()


func test_pins_are_buttons_that_centre_the_camera(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, {"pins": PINS}, func(action, arg): calls.append([action, arg]))
	t.eq(U.buttons(root).size(), 3, "one Button per pin")
	var claimed := U.button_with(root, "Ore 1,800")
	t.ok(claimed != null, "claimed pin reads Ore 1,800 left")
	claimed.pressed.emit()
	U.button_with(root, "Ore, unclaimed").pressed.emit()
	t.eq(calls, [["focus_deposit", [21, 10]], ["focus_deposit", [31, 17]]], "each pin emits its own hex cell")
	root.free()


func test_pin_sits_above_its_screen_point(t) -> void:
	var root := Control.new()
	Section.build(root, {"pins": [PINS[0]]})
	var hit := U.button_with(root, "Ore")
	t.near(hit.position.x + hit.size.x * 0.5, 861.0, 1.0, "centred on the deposit")
	t.near(hit.position.y + Section.H + Section.LIFT, 434.0, 1.0, "pin body floats LIFT above the deposit")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"pins": []})
	t.eq(root.get_child_count(), 0, "no pins, no nodes")
	root.free()
