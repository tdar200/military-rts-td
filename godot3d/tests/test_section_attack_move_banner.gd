extends RefCounted
const Section := preload("res://scripts/ui/sections/attack_move_banner.gd")
const U := preload("res://tests/section_util.gd")


func test_banner_says_armed_and_how_to_use_it(t) -> void:
	var root := Control.new()
	Section.build(root, {"armed": {"hint": "Right click a tile to go, Esc to cancel"}})
	t.ok(U.has_text(root, "Attack-move armed"), "the banner title")
	t.ok(U.has_text(root, "Right click a tile to go, Esc to cancel"), "the real controls, not the board's left click")
	root.free()


func test_banner_is_centred_on_the_screen(t) -> void:
	var root := Control.new()
	Section.build(root, {"armed": {"hint": "Right click a tile to go, Esc to cancel"}})
	var panel: Control = root.get_child(0)
	t.near(panel.position.x + panel.size.x * 0.5, 960.0, 1.5, "centred on x 960")
	t.near(panel.position.y, 80.0, 0.6, "80px from the top, under the top bar")
	root.free()


func test_banner_does_not_swallow_clicks(t) -> void:
	var root := Control.new()
	Section.build(root, {"armed": {"hint": "x"}})
	var swallowed := false
	for n in root.find_children("*", "Control", true, false):
		if n.mouse_filter == Control.MOUSE_FILTER_STOP:
			swallowed = true
	t.ok(not swallowed, "the right click that carries the order must reach the map under the banner")
	t.eq(U.buttons(root).size(), 0, "it is a status banner, not a control")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"armed": {}})
	t.eq(root.get_child_count(), 0, "not armed, no banner")
	root.free()


func test_rally_arming_reuses_the_banner_with_its_own_words(t) -> void:
	var root := Control.new()
	Section.build(root, {"armed": {"title": "Set rally armed", "hint": "Left click a tile to set it, Esc to cancel", "tone": "cyan", "icon": "flag"}})
	t.ok(U.has_text(root, "Set rally armed"), "its own title")
	t.ok(not U.has_text(root, "Attack-move"), "not the attack-move title")
	t.ok(U.has_text(root, "Left click a tile to set it"), "the left-click wording is right for the rally")
	root.free()
