extends RefCounted
const Section := preload("res://scripts/ui/sections/territory_card.gd")
const U := preload("res://tests/section_util.gd")
const VM := preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")

const SLICE := {"tiles": 38, "composition": [
	{"glyph": "g", "name": "Grassland", "pct": 44}, {"glyph": "m", "name": "Meadow", "pct": 24},
	{"glyph": "t", "name": "Forest", "pct": 14}, {"glyph": "r", "name": "River", "pct": 10}, {"glyph": "s", "name": "Shore", "pct": 8},
]}


func test_card_shows_tiles_and_every_composition_row(t) -> void:
	var root := Control.new()
	Section.build(root, {"territory": SLICE})
	t.ok(U.has_text(root, "38 tiles"), "tile count from the slice")
	t.ok(U.has_text(root, "Grassland 44%"), "largest ground with its percent")
	t.ok(U.has_text(root, "Shore 8%"), "smallest ground with its percent")
	t.eq(U.buttons(root).size(), 0, "the card is read-only")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"territory": {}})
	t.eq(root.get_child_count(), 0, "no territory, no card")
	root.free()


func test_card_grows_with_rows_and_yield_pills(t) -> void:
	var a := Control.new()
	Section.build(a, {"territory": SLICE})
	var b := Control.new()
	Section.build(b, {"territory": SLICE, "yields": [{"text": "+168 kW", "tone": "warn"}]})
	var panel_a: Control = a.get_child(0)
	var panel_b: Control = b.get_child(0)
	t.ok(panel_b.size.y > panel_a.size.y + 20.0, "the pill row adds its 22px plus margin")
	t.ok(U.has_text(b, "+168 kW"), "the yield pill is drawn inside the card")
	a.free()
	b.free()


func test_composition_segments_follow_the_percentages(t) -> void:
	var root := Control.new()
	Section.build(root, {"territory": SLICE})
	var bar: Control = null
	for n in root.get_children():
		if n is Section.Bar:
			bar = n
	t.ok(bar != null, "a composition bar exists")
	var total := 0.0
	for seg in bar.segments:
		total += seg[0]
	t.near(total, 100.0, 0.001, "segments total 100")
	t.eq(bar.segments.size(), 5, "one segment per ground")
	root.free()


func test_card_from_the_kestrel_snapshot(t) -> void:
	var snap: Dictionary = JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())
	var slice := VM.territory(snap, GroundModel.from_snapshot(snap))
	var root := Control.new()
	Section.build(root, {"territory": slice})
	t.ok(U.has_text(root, "%d tiles" % slice["tiles"]), "the real tile count")
	t.ok(U.has_text(root, "%s %d%%" % [slice["composition"][0]["name"], slice["composition"][0]["pct"]]), "the real largest ground")
	root.free()
