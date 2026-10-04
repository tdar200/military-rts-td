extends RefCounted
const Section := preload("res://scripts/ui/sections/wave_panel.gd")
const U := preload("res://tests/section_util.gd")


func _wave() -> Dictionary:
	return {"wave_panel": {
		"cap": "Wave 02", "tag": "Inbound", "title": "Fortify Wyllow Ford",
		"rows": [
			{"label": "Next wave", "value": "00:45", "tone": "warn"},
			{"label": "Expected", "value": "10 units", "tone": ""},
			{"label": "Direction", "value": "From the east", "tone": ""},
			{"label": "Crosses", "value": "The Dry Flats, Wyllow Ford", "tone": "warn"},
		],
	}}


func test_panel_carries_wave_number_eta_route_and_hint(t) -> void:
	var root := Control.new()
	Section.build(root, _wave())
	t.ok(U.has_text(root, "Wave 02"), "wave number")
	t.ok(U.has_text(root, "Inbound"), "tag")
	t.ok(U.has_text(root, "Fortify Wyllow Ford"), "fortify hint from the wave slice")
	t.ok(U.has_text(root, "00:45"), "eta")
	t.ok(U.has_text(root, "10 units"), "expected size")
	t.ok(U.has_text(root, "From the east"), "direction")
	t.ok(U.has_text(root, "The Dry Flats, Wyllow Ford"), "route crossings")
	root.free()


func test_no_hint_when_the_slice_has_no_title(t) -> void:
	var vm := _wave()
	vm["wave_panel"]["title"] = ""
	var root := Control.new()
	Section.build(root, vm)
	t.ok(not U.has_text(root, "Fortify"), "no invented hint")
	t.ok(U.has_text(root, "00:45"), "rows still drawn")
	root.free()


func test_panel_follows_the_slice_y(t) -> void:
	var vm := _wave()
	vm["wave_panel"]["y"] = 240
	var root := Control.new()
	Section.build(root, vm)
	var panel: Control = root.get_child(0)
	t.near(panel.position.y, 240.0, 0.6, "stacked below the objectives")
	root.free()


func test_panel_has_no_buttons(t) -> void:
	var root := Control.new()
	Section.build(root, _wave())
	t.eq(U.buttons(root).size(), 0, "read-only")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"wave_panel": {}})
	t.eq(root.get_child_count(), 0, "no wave in the window, no panel")
	root.free()
