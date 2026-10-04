extends RefCounted
## The style guide values from the spec (section 6), the tone words the view models use, and the bundled fonts.
const T = preload("res://scripts/ui/tokens.gd")
const Icons = preload("res://scripts/ui/icons.gd")


func test_style_guide_colours(t) -> void:
	t.eq(T.BG1.to_html(false), "060910", "page background")
	t.eq(T.CYAN.to_html(false), "40dceb", "cyan")
	t.eq(T.CYAN_HI.to_html(false), "96f5ff", "cyan hi")
	t.eq(T.TEXT.to_html(false), "cee8f0", "text")
	t.eq(T.DIM.to_html(false), "8fb0bf", "dim")
	t.eq(T.GOOD.to_html(false), "50e6a0", "good")
	t.eq(T.WARN.to_html(false), "f0b040", "warn")
	t.eq(T.BAD.to_html(false), "f04e46", "bad")
	t.eq(T.VIOLET.to_html(false), "b79cff", "violet")
	t.eq(T.LINE.to_html(false), "284e60", "panel border")


func test_panel_gradient_is_92_percent_alpha(t) -> void:
	t.near(T.PANEL_TOP.a, 0.92, 0.001, "top alpha")
	t.near(T.PANEL_BOT.a, 0.92, 0.001, "bottom alpha")
	t.eq(T.PANEL_TOP.to_html(false), "12202e", "gradient top rgb(18,32,46), as the mock boards write it")
	t.eq(T.PANEL_BOT.to_html(false), "08101a", "gradient bottom rgb(8,16,26)")


func test_tone_words(t) -> void:
	t.eq(T.tone("good"), T.GOOD, "good")
	t.eq(T.tone("warn"), T.WARN, "warn")
	t.eq(T.tone("bad"), T.BAD, "bad")
	t.eq(T.tone("cyan"), T.CYAN, "cyan")
	t.eq(T.tone("dim"), T.DIM, "dim")
	t.eq(T.tone("no-such-tone"), T.TEXT, "unknown tones fall back to body text")
	t.eq(T.tone(""), T.TEXT, "empty tone falls back to body text")


func test_fonts_load_with_real_metrics(t) -> void:
	for kind in ["disp", "body", "mono"]:
		var f: Font = T.font(kind)
		t.ok(f != null, kind + " font exists")
		t.ok(T.ascent(f, 16) > 0 and T.descent(f, 16) > 0, kind + " font has metrics (file found)")
	t.ok(T.font("disp", 700) != T.font("disp", 600), "bold and semibold Rajdhani are different files")
	t.eq(T.font("mono"), T.font("mono"), "fonts are cached")


func test_icons_rasterise_and_unknown_icon_is_reported(t) -> void:
	t.ok(Icons.has("power"), "power icon is in the set")
	t.ok(not Icons.has("no-such-icon"), "unknown icon is not in the set")
	var tex: Texture2D = Icons.texture("power", 18)
	t.ok(tex != null and tex.get_width() == 18, "icon rasterises at the requested size")
