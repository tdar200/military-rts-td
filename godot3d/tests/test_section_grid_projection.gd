extends RefCounted
const Section := preload("res://scripts/ui/sections/grid_projection.gd")
const HatchFill := preload("res://scripts/ui/components/hatch_fill.gd")
const U := preload("res://tests/section_util.gd")

const GRID := {
	"y": 560, "value": "185 / 168 kW", "tone": "warn", "over": 17,
	"segments": [{"ratio": 0.7, "tone": "cyan"}, {"ratio": 0.12, "tone": "warn"}, {"ratio": 0.06, "tone": "bad_hatch"}],
	"marker": 0.82, "lead": "17 kW over.", "text": "Build a Reactor beside the river for +12 kW cooling.",
}


func test_panel_prints_the_projection_and_the_advice(t) -> void:
	var root := Control.new()
	Section.build(root, {"power_grid": GRID})
	t.ok(U.has_text(root, "Projected grid"), "caption")
	t.ok(U.has_text(root, "185 / 168 kW"), "load after against generation")
	t.ok(U.has_text(root, "17 kW over."), "lead sentence")
	t.ok(U.has_text(root, "Build a Reactor beside the river for +12 kW cooling."), "advice")
	t.eq(U.buttons(root).size(), 0, "read-only")
	root.free()


func test_overflow_is_drawn_hatched_and_the_marker_sits_on_the_capacity_line(t) -> void:
	var root := Control.new()
	Section.build(root, {"power_grid": GRID})
	t.eq(root.find_children("*", "Control", true, false).filter(func(n): return n is HatchFill).size(), 1, "one hatched segment")
	var marker: Control = null
	for n in root.find_children("*", "ColorRect", true, false):
		if n.size == Vector2(2, 22):
			marker = n
	t.ok(marker != null, "a 2x22 marker")
	t.near(marker.position.x, 28.0 + 0.82 * 300.0 - 0.0, 1.5, "marker at 82% of the 300px bar")
	root.free()


func test_a_grid_that_fits_has_no_warning_line(t) -> void:
	var root := Control.new()
	var fits := GRID.duplicate(true)
	fits["over"] = 0
	fits["lead"] = ""
	fits["text"] = ""
	fits["tone"] = "cyan"
	fits["segments"] = [{"ratio": 0.5, "tone": "cyan"}]
	Section.build(root, {"power_grid": fits})
	t.ok(not U.has_text(root, "over."), "no overflow sentence")
	t.ok(U.has_text(root, "185 / 168 kW"), "still prints the value")
	root.free()


func test_panel_follows_the_y_in_the_slice(t) -> void:
	var root := Control.new()
	var high := GRID.duplicate(true)
	high["y"] = 468
	Section.build(root, {"power_grid": high})
	var top := 99999.0
	for n in root.get_children():
		top = minf(top, n.position.y)
	t.eq(top, 468.0, "the panel climbs with the slice")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"power_grid": {}})
	t.eq(root.get_child_count(), 0, "no slice, no nodes")
	root.free()
