extends RefCounted
const Section := preload("res://scripts/ui/sections/minimap_lenses.gd")
const U := preload("res://tests/section_util.gd")


func test_four_toggle_buttons_with_human_labels(t) -> void:
	var root := Control.new()
	Section.build(root, {"lens": {"on": "land"}})
	var labels: Array = []
	for b in U.buttons(root):
		labels.append((b as Button).text)
	t.eq(labels, ["Land", "Res", "Bdr", "Thr"], "Land, Res, Bdr, Thr in board order")
	root.free()


func test_clicking_a_key_emits_its_lens(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, {"lens": {"on": "land"}}, func(action, arg): calls.append([action, arg]))
	U.button_with(root, "Res").pressed.emit()
	U.button_with(root, "Thr").pressed.emit()
	t.eq(calls, [["minimap_lens", "res"], ["minimap_lens", "thr"]], "ids, not labels")
	root.free()


func test_keys_end_at_the_header_edge(t) -> void:
	var root := Control.new()
	Section.build(root, {"lens": {"on": "bdr"}})
	var last := U.button_with(root, "Thr")
	t.near(last.position.x + last.size.x, Section.RIGHT, 1.0, "right edge of the keys")
	root.free()


func test_overlay_only_when_the_lens_has_one(t) -> void:
	var land := Control.new()
	Section.build(land, {"lens": {"on": "land"}})
	var count := 0
	for n in land.get_children():
		count += 1 if n is Section.Overlay else 0
	t.eq(count, 0, "land draws nothing extra")
	land.free()
	var res := Control.new()
	Section.build(res, {"lens": {"on": "res", "overlay": {"dots": [{"u": 0.5, "v": 0.5, "k": "ore"}]}}})
	var overlays: Array = res.get_children().filter(func(n): return n is Section.Overlay)
	t.eq(overlays.size(), 1, "an overlay for the res lens")
	t.eq((overlays[0] as Control).size, Section.SLOT.size, "it covers the minimap slot")
	res.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"lens": {}})
	t.eq(root.get_child_count(), 0, "no lens slice, no keys")
	root.free()
