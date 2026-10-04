extends RefCounted
const Section := preload("res://scripts/ui/sections/site_card.gd")
const U := preload("res://tests/section_util.gd")


func test_card_shows_the_site_rows(t) -> void:
	var root := Control.new()
	Section.build(root, {"site": {"cap": "Barracks site", "rows": [{"label": "Terrain", "value": "Grassland", "tone": ""}, {"label": "Forest edge", "value": "3 tiles S, 20% cover", "tone": ""}, {"label": "Ford", "value": "12 tiles E", "tone": ""}]}})
	t.ok(U.has_text(root, "Barracks site"), "caption")
	t.ok(U.has_text(root, "3 tiles S, 20% cover"), "forest distance and cover")
	t.ok(U.has_text(root, "12 tiles E"), "ford distance")
	root.free()


func test_card_follows_the_slice_y(t) -> void:
	var root := Control.new()
	Section.build(root, {"site": {"cap": "Barracks site", "y": 200, "rows": [{"label": "Terrain", "value": "Grassland", "tone": ""}]}})
	var panel: Control = root.get_child(0)
	t.near(panel.position.y, 200.0, 0.6, "the adapter stacks it below other left cards")
	root.free()


func test_absent_or_empty_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"site": {"cap": "Barracks site", "rows": []}})
	t.eq(root.get_child_count(), 0, "no rows, no card")
	root.free()
