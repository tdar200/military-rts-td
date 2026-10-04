extends RefCounted
const Section := preload("res://scripts/ui/sections/combat_preview.gd")
const U := preload("res://tests/section_util.gd")

const COMBAT := {"x": 1060, "y": 360, "sub": "4 x Riflemen vs Alien gun turret", "rows": [
	{"label": "Standing on Grassland", "value": "normal speed", "tone": "dim"},
	{"label": "Holding Highland", "value": "+25% range", "tone": "good"},
	{"label": "Target on Highland", "value": "-25% damage", "tone": "bad"},
]}


func test_card_shows_the_matchup_and_the_ground_rows(t) -> void:
	var root := Control.new()
	Section.build(root, {"combat": COMBAT})
	t.ok(U.has_text(root, "Combat preview"), "title")
	t.ok(U.has_text(root, "Attack"), "red attack tag")
	t.ok(U.has_text(root, "4 x Riflemen vs Alien gun turret"), "matchup")
	t.ok(U.has_text(root, "Target on Highland"), "ground row label")
	t.ok(U.has_text(root, "-25% damage"), "cover value")
	t.ok(not U.has_text(root, "health") and not U.has_text(root, "320") and not U.has_text(root, "range 7"), "no invented damage or range figures")
	t.eq(U.buttons(root).size(), 0, "read-only")
	root.free()


func test_card_sits_at_the_slice_position_with_a_red_frame(t) -> void:
	var root := Control.new()
	Section.build(root, {"combat": COMBAT})
	var panel: Control = root.get_child(0)
	t.eq(panel.position, Vector2(1060, 360), "at the slice's x and y")
	t.near(panel.size.x, 330.0, 0.5, "330 wide")
	t.eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "a floating card never swallows a map click")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"combat": {}})
	t.eq(root.get_child_count(), 0, "no slice, no nodes")
	root.free()
