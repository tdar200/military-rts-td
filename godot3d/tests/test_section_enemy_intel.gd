extends RefCounted
const Section := preload("res://scripts/ui/sections/enemy_intel.gd")
const U := preload("res://tests/section_util.gd")

const ENEMY := {"y": 262, "rows": [
	{"label": "Defences", "value": "4 gun, 2 AA", "tone": ""},
	{"label": "Garrison", "value": "6 units", "tone": ""},
	{"label": "Terrain", "value": "Dry flats, Highland", "tone": ""},
	{"label": "Reinforce", "value": "1:30, 10 units", "tone": "warn"},
]}


func test_card_lists_the_snapshot_counts(t) -> void:
	var root := Control.new()
	Section.build(root, {"enemy": ENEMY})
	t.ok(U.has_text(root, "Enemy territory"), "caption is the R6 label")
	t.ok(U.has_text(root, "4 gun, 2 AA"), "defences")
	t.ok(U.has_text(root, "6 units"), "garrison")
	t.ok(U.has_text(root, "Dry flats, Highland"), "terrain")
	t.ok(U.has_text(root, "1:30, 10 units"), "reinforcements")
	t.ok(not U.has_text(root, "partly seen") and not U.has_text(root, "est."), "no estimate language: the counts are what the snapshot holds")
	t.eq(U.buttons(root).size(), 0, "read-only")
	root.free()


## Kestrel fog of war (Task 7): the card states what is known, in sight and last seen, and how much is scouted. It still
## never estimates what is hidden.
func test_card_under_fog_names_what_is_known(t) -> void:
	var root := Control.new()
	Section.build(root, {"enemy": {"y": 262, "rows": [
		{"label": "Defences", "value": "2 gun", "tone": ""},
		{"label": "Garrison", "value": "1 unit in sight", "tone": ""},
		{"label": "Memory", "value": "1 last seen", "tone": ""},
		{"label": "Scouted", "value": "18% of the map", "tone": ""},
	]}})
	for want in ["2 gun", "1 unit in sight", "1 last seen", "18% of the map"]:
		t.ok(U.has_text(root, want), "shows '%s'" % want)
	t.ok(not U.has_text(root, "partly seen") and not U.has_text(root, "est."), "no estimate of the hidden side")
	root.free()


func test_card_geometry_matches_the_board(t) -> void:
	var root := Control.new()
	Section.build(root, {"enemy": ENEMY})
	var panel: Control = root.get_child(0)
	t.eq(panel.position, Vector2(12, 262), "12,262")
	t.near(panel.size.x, 332.0, 0.5, "332 wide")
	t.ok(panel.size.y > 120.0, "tall enough for the caption and four rows (exact height is checked against the board by tools/ui)")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"enemy": {}})
	Section.build(root, {"enemy": {"rows": []}})
	t.eq(root.get_child_count(), 0, "no slice, no nodes")
	root.free()
