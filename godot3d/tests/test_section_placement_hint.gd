extends RefCounted
const Section := preload("res://scripts/ui/sections/placement_hint.gd")
const U := preload("res://tests/section_util.gd")


func test_chip_lists_only_the_bound_controls(t) -> void:
	var root := Control.new()
	Section.build(root, {"right": 1751.0})
	var caps: Array = []
	for n in root.find_children("*", "Control", true, false):
		if n.get_script() != null and n.get("label") is String and n.get("text_color") != null:
			caps.append(n.get("label"))
	t.ok(U.has_text(root, "PLACEMENT"), "chip caption")
	t.eq(caps, ["Click", "Esc"], "two key caps: a click places, Esc cancels")
	t.ok(U.has_text(root, "place") and U.has_text(root, "cancel"), "their verbs")
	t.ok(not U.has_text(root, "rotate") and not caps.has("Enter") and not caps.has("R"), "no rotate and no Enter: neither is bound")
	t.eq(U.buttons(root).size(), 0, "read-only")
	root.free()


func test_chip_ends_at_the_requested_edge(t) -> void:
	var root := Control.new()
	Section.build(root, {"right": 1751.0})
	var chip: Control = root.get_child(0)
	t.near(chip.position.x + chip.size.x, 1751.0, 1.0, "right edge")
	t.near(chip.position.y, 21.0, 0.5, "inside the 56px strip")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	t.eq(root.get_child_count(), 0, "no hint, no chip")
	root.free()
