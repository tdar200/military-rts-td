extends RefCounted
const Section := preload("res://scripts/ui/sections/placement_card.gd")
const U := preload("res://tests/section_util.gd")

const CARD := {
	"x": 604, "y": 690, "title": "Refinery", "status": "1 hex is blocked", "tone": "warn",
	"footprint": "Footprint 1 hex on Grassland",
	"rows": [
		{"label": "Ore in range", "value": "Ore, 30,000 left, +20% output", "tone": "good"},
		{"label": "Blocked tile", "value": "Shore, cannot build", "tone": "bad"},
		{"label": "Power", "value": "-25 kW, grid over capacity", "tone": "warn"},
	],
}


func test_card_shows_the_real_labels_and_numbers(t) -> void:
	var root := Control.new()
	Section.build(root, {"placing": CARD})
	t.ok(U.has_text(root, "Placing Refinery"), "title names the armed building")
	t.ok(U.has_text(root, "1 hex is blocked"), "status tag says 1 hex, never a tile count")
	t.ok(U.has_text(root, "Footprint 1 hex on Grassland"), "footprint line")
	t.ok(U.has_text(root, "Ore, 30,000 left, +20% output"), "deposit row")
	t.ok(U.has_text(root, "Shore, cannot build"), "blocked row")
	t.ok(U.has_text(root, "-25 kW, grid over capacity"), "power row")
	t.ok(not U.has_text(root, "4 x 3") and not U.has_text(root, "Slope") and not U.has_text(root, "+4"), "none of the board's unbacked claims")
	root.free()


func test_card_sits_where_the_slice_puts_it(t) -> void:
	var root := Control.new()
	Section.build(root, {"placing": CARD})
	var panel: Control = null
	for n in root.get_children():
		if n.get_class() != "Control" or n.get_script() != null:
			panel = n
			break
	t.ok(panel != null, "a panel is drawn")
	t.eq(panel.position, Vector2(604, 690), "at the slice's x and y")
	t.eq(panel.size.x, 340.0, "340px wide")
	t.eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "a floating card never swallows a map click")
	t.ok(panel.size.y > 120.0, "tall enough for the rows")
	root.free()


func test_a_clear_hex_has_a_good_tag_and_the_card_has_no_buttons(t) -> void:
	var root := Control.new()
	var clear := CARD.duplicate(true)
	clear["status"] = "1 hex is clear"
	clear["tone"] = "good"
	clear["rows"] = []
	Section.build(root, {"placing": clear})
	t.ok(U.has_text(root, "1 hex is clear"), "clear status")
	t.eq(U.buttons(root).size(), 0, "a read-only card has nothing to click")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"placing": {}})
	t.eq(root.get_child_count(), 0, "no slice, no nodes")
	root.free()

