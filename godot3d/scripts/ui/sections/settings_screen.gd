extends RefCounted
## Settings screen (from the title's Settings entry or the pause menu): five bus volume sliders, the fog of war toggle
## (it applies to the next match), the window mode, and a read-only list of the keys built from the controls
## reference's own rows (Keybinds.vm, ControlsReference._group). Built from vm() over a full-screen ground, in the
## pause menu's kit. `emit` is Callable(name, arg) and receives set ([key, value]) and settings_back. A slider's
## percent follows it at once, so the host saves and applies without rebuilding the screen mid-drag. Builds nothing for {}.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")
const ControlsReference = preload("res://scripts/ui/sections/controls_reference.gd")

const MARGIN := 60.0
const TOP := 170.0
const LEFT_W := 560.0
const GAP := 20.0
const SCREEN_W := 1920.0
const PAD := 18.0
const ROW_H := 44.0
const LABEL_W := 120.0
const VALUE_W := 52.0
const STEP := 0.05
const VOLUMES := [["audio/master", "Master"], ["audio/sfx", "Effects"], ["audio/ui", "Interface"], ["audio/ambient", "Ambience"], ["audio/music", "Music"]]
const WINDOW_OPTIONS := [{"id": "windowed", "label": "Windowed"}, {"id": "fullscreen", "label": "Fullscreen"}]
const ROW_RULE := Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.6)

static var _grabbers: Dictionary = {}


## The screen's view model from the saved values (Settings.load_from). `from_pause` names the way back; `kestrel` adds
## the Kestrel-only keys to the list, as the controls screen does.
static func vm(values: Dictionary, from_pause := false, kestrel := false) -> Dictionary:
	var volumes: Array = []
	for pair in VOLUMES:
		volumes.append({"key": pair[0], "label": pair[1], "value": clampf(float(values.get(pair[0], 1.0)), 0.0, 1.0)})
	return {
		"cap": "Pause / Settings" if from_pause else "Settings",
		"title": "Settings",
		"subtitle": "Saved on this computer as soon as you change them.",
		"back_key": Keybinds.cap(Keybinds.PAUSE),
		"volumes": volumes,
		"fog": {"key": "game/fog", "label": "Fog of war", "on": bool(values.get("game/fog", true)), "note": "Kestrel Reach. Applies next match."},
		"window": {"key": "video/window_mode", "label": "Window", "value": str(values.get("video/window_mode", "windowed")), "options": WINDOW_OPTIONS},
		"keys": Keybinds.vm(from_pause, kestrel)["columns"],
		"keys_note": "Read only",
	}


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty():
		return
	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.color = Color("07101a")
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(ground)
	_header(parent, vm, emit)
	var y := TOP
	y += _audio(parent, MARGIN, y, LEFT_W, vm.get("volumes", []), emit) + GAP
	var fog: Dictionary = vm.get("fog", {})
	var on: bool = fog.get("on", true)
	y += _choice(parent, MARGIN, y, LEFT_W, "Game", str(fog.get("label", "")), str(fog.get("note", "")),
		[{"id": true, "label": "On"}, {"id": false, "label": "Off"}], on, str(fog.get("key", "")), emit) + GAP
	var window: Dictionary = vm.get("window", {})
	_choice(parent, MARGIN, y, LEFT_W, "Display", str(window.get("label", "")), "", window.get("options", []),
		str(window.get("value", "")), str(window.get("key", "")), emit)
	_keys(parent, vm)


static func _header(parent: Control, vm: Dictionary, emit: Callable) -> void:
	var cap := K.text(parent, str(vm.get("cap", "")), {"x": MARGIN, "y": 36.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	var title := K.text(parent, str(vm.get("title", "Settings")), {"x": MARGIN, "y": 36.0 + cap.size.y + 2.0, "f": "disp", "wt": 600, "px": 52, "sp": 0.04, "lh": 54, "col": T.TEXT_HI, "up": true})
	var sub := K.text(parent, str(vm.get("subtitle", "")), {"x": MARGIN, "y": title.position.y + title.size.y + 4.0, "px": 15, "col": T.DIM})
	var bottom := sub.position.y + sub.size.y
	var back := K.button(parent, "Back", 0, 0, {"primary": true, "key": str(vm.get("back_key", "Esc"))})
	K.place(back, SCREEN_W - MARGIN - back.size.x, bottom - back.size.y)
	if emit.is_valid():
		back.pressed.connect(emit.bind("settings_back", null))


## A panel heading (the controls reference's .sec style): the name and a hairline to its right. Returns its height.
## `reserve` keeps that much of the right end free (for a tag).
static func _head(parent: Control, x: float, y: float, w: float, name: String, reserve := 0.0) -> float:
	var head := K.text(parent, name, {"x": x, "y": y, "f": "disp", "wt": 600, "px": 20, "sp": 0.1, "col": T.CYAN_HI, "up": true})
	K.rule(parent, x + head.size.x + 10.0, y + roundf(head.size.y * 0.5), w - head.size.x - 10.0 - reserve, 1, T.LINE_DIM)
	return head.size.y


## The Audio panel: one row per bus, a label, the slider and its percent. Returns the panel height.
static func _audio(parent: Control, x: float, y: float, w: float, volumes: Array, emit: Callable) -> float:
	var panel := K.panel(parent, x, y, w, 10.0)
	var cx := x + 1.0 + PAD
	var cw := w - 2.0 - 2.0 * PAD
	var at := y + 1.0 + 16.0
	at += _head(parent, cx, at, cw, "Audio") + 6.0
	for i in volumes.size():
		var row: Dictionary = volumes[i]
		var mid := at + ROW_H * 0.5
		var label := K.text(parent, str(row.get("label", "")), {"x": cx, "y": 0, "px": 15, "col": T.TEXT})
		label.position.y = roundf(mid - label.size.y * 0.5)
		var value: float = row.get("value", 1.0)
		var pct := K.text(parent, _pct(value), {"x": 0, "y": 0, "f": "mono", "px": 13, "col": T.DIM})
		pct.position = Vector2(roundf(cx + cw - pct.size.x), roundf(mid - pct.size.y * 0.5))
		var slider := _slider(str(row.get("key", "")), value)
		K.place(slider, cx + LABEL_W, mid - 12.0, cw - LABEL_W - VALUE_W - 12.0, 24.0)
		parent.add_child(slider)
		var key := str(row.get("key", ""))
		slider.value_changed.connect(func(v: float) -> void:
			pct.set_text(_pct(v))
			pct.position.x = roundf(cx + cw - pct.size.x)
			if emit.is_valid():
				emit.call("set", [key, v]))
		at += ROW_H
		if i < volumes.size() - 1:
			K.rule(parent, cx, at, cw, 1, ROW_RULE)
			at += 1.0
	panel.size.y = roundf(at + 12.0 + 1.0 - y)
	panel.queue_redraw()
	return panel.size.y


static func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


## A styled HSlider named after its key ("audio/sfx" is the node "audio_sfx"), 0..1 in STEP steps.
static func _slider(key: String, value: float) -> HSlider:
	var s := HSlider.new()
	s.name = key.replace("/", "_")
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = STEP
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var track := StyleBoxFlat.new()
	track.bg_color = T.BAR_BG
	track.border_color = T.LINE_DIM
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = T.CYAN_DK
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3.0
	fill.content_margin_bottom = 3.0
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.55)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", _grabber(T.CYAN))
	s.add_theme_icon_override("grabber_highlight", _grabber(T.CYAN_HI))
	s.add_theme_icon_override("grabber_disabled", _grabber(T.FAINT))
	return s


## A round grabber: a dark core ringed in `color`, 18 px.
static func _grabber(color: Color) -> Texture2D:
	var key := color.to_html()
	if _grabbers.has(key):
		return _grabbers[key]
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for py in n:
		for px in n:
			var d := Vector2(px - c, py - c).length()
			var a := clampf(c + 0.5 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var ink: Color = color if d > c - 2.5 else T.BG2
			img.set_pixel(px, py, Color(ink.r, ink.g, ink.b, a))
	var tex := ImageTexture.create_from_image(img)
	_grabbers[key] = tex
	return tex


## A panel with one row: a label (and a note under it) and a segmented choice, the chosen option primary. Each option
## emits set with [key, its id]. Returns the panel height.
static func _choice(parent: Control, x: float, y: float, w: float, heading: String, label: String, note: String, options: Array,
		chosen: Variant, key: String, emit: Callable) -> float:
	var panel := K.panel(parent, x, y, w, 10.0)
	var cx := x + 1.0 + PAD
	var cw := w - 2.0 - 2.0 * PAD
	var at := y + 1.0 + 16.0
	at += _head(parent, cx, at, cw, heading) + 12.0
	var buttons: Array = []
	var total := 0.0
	for o in options:
		var b := K.button(parent, str(o.get("label", "")), 0, 0, {"primary": o.get("id") == chosen, "px": 16, "pad": 16.0, "min_h": 40})
		b.size.x = maxf(110.0, b.size.x)
		b.custom_minimum_size = b.size
		b.name = "%s_%s" % [key.replace("/", "_"), str(o.get("id", "")).to_lower()]
		if emit.is_valid():
			b.pressed.connect(emit.bind("set", [key, o.get("id")]))
		buttons.append(b)
		total += b.size.x
	total += 8.0 * maxi(buttons.size() - 1, 0)
	var row_h := 40.0
	var name := K.text(parent, label, {"x": cx, "y": 0, "px": 15, "col": T.TEXT})
	var hint: Control = null
	var block := name.size.y
	if note != "":
		hint = K.text(parent, note, {"x": cx, "y": 0, "px": 13, "col": T.DIM})
		block += 2.0 + hint.size.y
	var inner := maxf(row_h, block)
	name.position.y = roundf(at + (inner - block) * 0.5)
	if hint != null:
		hint.position.y = roundf(name.position.y + name.size.y + 2.0)
	var bx := cx + cw - total
	for b in buttons:
		K.place(b, bx, at + (inner - row_h) * 0.5)
		bx += b.size.x + 8.0
	at += inner
	panel.size.y = roundf(at + 16.0 + 1.0 - y)
	panel.queue_redraw()
	return panel.size.y


## The keys, read only: a heading with its note, then the controls screen's three columns of groups, drawn by the
## controls reference itself.
static func _keys(parent: Control, vm: Dictionary) -> void:
	var columns: Array = vm.get("keys", [])
	if columns.is_empty():
		return
	var x := MARGIN + LEFT_W + GAP
	var w := SCREEN_W - MARGIN - x
	var note := K.tag(parent, str(vm.get("keys_note", "")), 0, TOP, T.DIM)
	var head_h := _head(parent, x, TOP, w, "Keys", note.size.x + 10.0)
	note.position = Vector2(roundf(x + w - note.size.x), roundf(TOP + (head_h - note.size.y) * 0.5))
	var top := TOP + head_h + 14.0
	var col_w := (w - 2.0 * GAP) / 3.0
	for c in columns.size():
		var y := top
		for group in columns[c]:
			y += ControlsReference._group(parent, x + c * (col_w + GAP), y, col_w, group) + GAP
