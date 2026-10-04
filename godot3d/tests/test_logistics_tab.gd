extends RefCounted
## Logistics deck tab (board 8): the lens buttons, the active lens's legend and the line of what it draws.
const Section := preload("res://scripts/ui/sections/logistics_tab.gd")
const U := preload("res://tests/section_util.gd")


func _body(lens := "power") -> Dictionary:
	var lenses: Array = []
	for pair in [["power", "Power"], ["borders", "Borders"], ["coverage", "Coverage"], ["yield", "Yield"]]:
		lenses.append({"id": pair[0], "label": pair[1], "on": pair[0] == lens})
	var body := {"kind": "logistics", "lenses": lenses, "lens": lens}
	if lens == "power":
		body["legend"] = [
			{"tone": "ok", "style": "solid", "text": "Powered, full delivery"},
			{"tone": "warn", "style": "solid", "text": "Throttled, under 1000 of 1000"},
			{"tone": "bad", "style": "dotted", "text": "Link broken, under 500 of 500"},
		]
		body["summary"] = "9 links, 1 broken"
		body["note"] = "Defence is served first."
	return body


func test_shows_caption_active_lens_legend_and_what_is_drawn(t) -> void:
	var root := Control.new()
	Section.build(root, _body())
	t.ok(U.has_text(root, "Map lenses"), "caption")
	t.ok(U.has_text(root, "Powered, full delivery"), "legend row 1")
	t.ok(U.has_text(root, "Throttled, under 1000 of 1000"), "legend row 2")
	t.ok(U.has_text(root, "Link broken"), "legend row 3")
	t.ok(U.has_text(root, "9 links, 1 broken"), "the real count the lens draws")
	t.ok(U.has_text(root, "Defence is served first."), "the note")
	root.free()


func test_lens_buttons_are_buttons_with_human_text_and_emit_the_lens(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, _body("power"), func(action, arg): calls.append([action, arg]))
	for label in ["Power", "Borders", "Coverage", "Yield"]:
		t.ok(U.button_with(root, label) != null, "a Button reads " + label)
	t.ok(U.button_with(root, "Supply") == null, "a lens with no data has no button")
	U.button_with(root, "Coverage").pressed.emit()
	U.button_with(root, "Yield").pressed.emit()
	t.eq(calls, [["world_lens", "coverage"], ["world_lens", "yield"]], "a click picks that lens")
	root.free()


func test_clicking_the_active_lens_turns_it_off(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, _body("power"), func(action, arg): calls.append([action, arg]))
	U.button_with(root, "Power").pressed.emit()
	t.eq(calls, [["world_lens", ""]], "the active lens toggles off")
	root.free()


func test_active_lens_button_reads_primary(t) -> void:
	var root := Control.new()
	Section.build(root, _body("borders"))
	t.eq(U.button_with(root, "Borders").primary, true, "the active lens is the primary button")
	t.eq(U.button_with(root, "Power").primary, false, "the others are not")
	root.free()


func test_no_active_lens_invites_a_choice_and_draws_no_legend(t) -> void:
	var root := Control.new()
	Section.build(root, _body(""))
	t.ok(U.has_text(root, "Pick a lens"), "empty state names the action")
	t.ok(not U.has_text(root, "Powered, full delivery"), "no legend without a lens")
	root.free()


func test_lens_that_draws_nothing_says_so_instead_of_a_zero(t) -> void:
	var body := _body("coverage")
	body["empty"] = "No finished turrets to show."
	var root := Control.new()
	Section.build(root, body)
	t.ok(U.has_text(root, "No finished turrets to show."), "honest empty text")
	t.ok(not U.has_text(root, "0 "), "no fabricated zero count")
	root.free()


func test_absent_or_empty_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"kind": "logistics", "lenses": []})
	t.eq(root.get_child_count(), 0, "no lens has data: no panel")
	root.free()
