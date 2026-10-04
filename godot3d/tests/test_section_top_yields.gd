extends RefCounted
const Section := preload("res://scripts/ui/sections/top_yields.gd")
const U := preload("res://tests/section_util.gd")


func test_yield_pills_show_the_real_quantities(t) -> void:
	var root := Control.new()
	Section.build(root, {"yields": [{"text": "+168 kW", "tone": "warn"}, {"text": "+38 M", "tone": "cyan"}]})
	t.ok(U.has_text(root, "+168 kW"), "kW pill with the real figure")
	t.ok(U.has_text(root, "+38 M"), "a second pill when the adapter supplies one")
	t.eq(root.get_child_count(), 2, "one node per pill")
	t.near((root.get_child(1) as Control).position.x, (root.get_child(0) as Control).size.x + 6.0, 1.0, "pills sit 6px apart")
	t.eq(Section.row_height({"yields": [{"text": "x"}]}), 22.0, "row height is the pill height")
	root.free()


func test_absent_or_empty_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"yields": []})
	t.eq(root.get_child_count(), 0, "no slice, no pills, no fake zeros")
	t.eq(Section.row_height({}), 0.0, "no row height either")
	root.free()


func test_pills_are_not_clickable(t) -> void:
	var root := Control.new()
	Section.build(root, {"yields": [{"text": "+168 kW", "tone": "warn"}]})
	t.eq(U.buttons(root).size(), 0, "yield pills are read-only")
	root.free()
