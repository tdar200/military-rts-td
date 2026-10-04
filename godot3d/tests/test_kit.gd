extends RefCounted
## The node factories every screen builder uses. Geometry is in mock pixels, so positions land on whole pixels.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")


func test_place_rounds_to_whole_pixels_and_keeps_size_when_not_given(t) -> void:
	var n := Control.new()
	n.size = Vector2(7, 9)
	K.place(n, 10.4, 20.6)
	t.eq(n.position, Vector2(10, 21), "rounded position")
	t.eq(n.size, Vector2(7, 9), "size untouched without w and h")
	K.place(n, 0, 0, 30, -1)
	t.eq(n.size.x, 30.0, "width set")
	K.place(n, 0, 0, -5, 12)
	t.eq(n.size, Vector2(0, 12), "a negative width clamps to zero")
	n.free()


func test_text_sizes_itself_to_its_content_unless_told_otherwise(t) -> void:
	var host := Control.new()
	var a := K.text(host, "HULL", {"x": 4, "y": 6})
	t.eq(a.get_parent(), host, "added to the parent")
	t.eq(a.position, Vector2(4, 6), "position")
	t.ok(a.size.x > 0.0 and a.size.y > 0.0, "sized to its content")
	var wide := K.text(host, "HULL", {"w": 200.0})
	t.eq(wide.size.x, 200.0, "explicit width wins")
	var empty := K.text(host, "")
	t.ok(empty.size.x >= 0.0 and empty.size.y >= 0.0, "empty text does not produce a negative size")
	host.free()


func test_panel_and_rule_take_the_given_rectangle(t) -> void:
	var host := Control.new()
	var p := K.panel(host, 12, 56, 420, 90)
	t.eq(Rect2(p.position, p.size), Rect2(12, 56, 420, 90), "panel rectangle")
	var r := K.rule(host, 0, 0, 40, 1, T.LINE)
	t.eq(r.mouse_filter, Control.MOUSE_FILTER_IGNORE, "rules never take clicks")
	t.eq((r as ColorRect).color, T.LINE, "rule colour")
	host.free()


func test_hit_is_an_invisible_button_that_keeps_its_label(t) -> void:
	var host := Control.new()
	var b := K.hit(host, 5, 6, 100, 40, "Battle tank")
	t.eq(b.text, "Battle tank", "QA tools and tests find controls by this text")
	t.eq(b.focus_mode, Control.FOCUS_NONE, "no focus ring")
	t.eq(b.get_theme_color("font_color").a, 0.0, "label is never drawn")
	t.eq(Rect2(b.position, b.size), Rect2(5, 6, 100, 40), "rectangle")
	host.free()


func test_widget_factories_attach_to_the_parent(t) -> void:
	var host := Control.new()
	var made: Array = [
		K.icon(host, "power", 1, 2, T.WARN),
		K.tag(host, "READY", 3, 4, T.GOOD),
		K.key(host, "Q", 5, 6),
		K.bar(host, 7, 8, 120, 0.5),
		K.chip(host, 9, 10, "power", T.WARN, [{"t": "200"}]),
		K.button(host, "Close", 11, 12),
		K.diamond(host, 50, 50, 8),
	]
	for n in made:
		t.ok(n != null and n.get_parent() == host, "%s is a child of the host" % n.get_class())
	t.eq(host.get_child_count(), made.size(), "one node per factory call")
	host.free()


func test_sprite_texture_handles_missing_and_empty_paths(t) -> void:
	t.ok(K.sprite_texture("") == null, "empty path")
	t.ok(K.sprite_texture("/no/such/file.png") == null, "missing absolute path")
	var tank := K.sprite_texture("res://assets/ui/sprites/tank_v2.png")
	t.ok(tank != null and tank.get_width() > 0, "a bundled sprite loads")
	t.eq(K.sprite_texture("res://assets/ui/sprites/tank_v2.png"), tank, "cached")


func test_chip_grows_with_its_parts(t) -> void:
	var host := Control.new()
	var one := K.chip(host, 0, 0, "power", T.WARN, [{"t": "200"}])
	var two := K.chip(host, 0, 40, "power", T.WARN, [{"t": "200"}, {"t": "/ 160 kW"}])
	t.eq(one.size.y, 28.0, "chip height from the mock")
	t.ok(two.size.x > one.size.x, "a second text part widens the chip")
	var bare := K.chip(host, 0, 80, "", T.WARN, [{"t": "Y close"}])
	t.ok(bare.size.x > 0.0, "a chip without an icon still sizes")
	host.free()
