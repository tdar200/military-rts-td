extends RefCounted
const Section := preload("res://scripts/ui/sections/bottom_panel.gd")


func test_frame_appears_with_any_column_slice(t) -> void:
	for key in ["inspect", "ledger", "army"]:
		var root := Control.new()
		Section.build(root, {key: {"x": 1}})
		t.ok(root.get_child_count() >= 1, key + " alone draws the frame")
		root.free()


func test_rules_only_between_present_columns(t) -> void:
	var one := Control.new()
	Section.build(one, {"inspect": {"name": "Grassland"}})
	t.eq(one.get_child_count(), 1, "inspector only: just the panel")
	one.free()
	var all := Control.new()
	Section.build(all, {"inspect": {"name": "Grassland"}, "ledger": {"structures": 1}, "army": {"count": 1}})
	t.eq(all.get_child_count(), 3, "panel plus two column rules")
	all.free()


func test_absent_slices_build_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"inspect": {}, "ledger": {}, "army": {}})
	t.eq(root.get_child_count(), 0, "no data, no frame")
	root.free()
