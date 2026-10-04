extends Control
## One text run laid out the way the mocks' CSS lays it out: font, px size, letter-spacing in em, line-height in px,
## word wrap and text-transform. Draws itself and owns no child nodes. Position it by the top-left of its CSS line box.
const T = preload("res://scripts/ui/tokens.gd")

var text := ""
var kind := "body"
var weight := 0
var px := 14
var color: Color = T.TEXT
var spacing_em := 0.0
var line_px := 0.0
var align := "l"
var wrap := false
var upper := false
var strike := false
var faux := false
var lead_len := 0
var lead_color: Color = T.TEXT

var _lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Options (faux = Chrome's synthetic bold on mono: weight 600 asked of a 500 face): f kind, wt weight, px size, col colour, sp letter-spacing em, lh line-height px, al l|c|r, wrap, up, strike.
func configure(s: String, o := {}) -> Control:
	text = s
	kind = o.get("f", kind)
	weight = o.get("wt", weight)
	px = o.get("px", px)
	color = o.get("col", color)
	spacing_em = o.get("sp", spacing_em)
	line_px = o.get("lh", line_px)
	align = o.get("al", align)
	wrap = o.get("wrap", wrap)
	upper = o.get("up", upper)
	strike = o.get("strike", strike)
	faux = o.get("faux", faux)
	lead_len = o.get("lead_len", lead_len)
	lead_color = o.get("lead_col", lead_color)
	_relayout()
	return self


func set_text(s: String) -> void:
	if s != text:
		text = s
		_relayout()


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _font() -> Font:
	return T.font(kind, weight)


func _shown() -> String:
	return text.to_upper() if upper else text


func pitch() -> float:
	if line_px > 0.0:
		return line_px
	var f := _font()
	return float(T.ascent(f, px) + T.descent(f, px))


func spacing_px() -> float:
	return spacing_em * px


## Width of one line exactly as CSS reports it: letter-spacing is added after every character, the last included.
func measure(s: String) -> float:
	var n := s.length()
	if kind == "mono":
		return n * (T.MONO_ADVANCE * px + spacing_px())
	return _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + n * spacing_px()


func lines() -> PackedStringArray:
	return _lines


func _relayout() -> void:
	var s := _shown()
	if wrap and size.x > 0.0:
		_lines = _break(s, size.x)
	else:
		_lines = s.split("\n")
	update_minimum_size()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and wrap:
		_relayout()


func _get_minimum_size() -> Vector2:
	var widest := 0.0
	if not wrap:
		for line in _lines:
			widest = maxf(widest, measure(line))
	return Vector2(widest, maxf(1.0, _lines.size()) * pitch())


func _break(s: String, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for paragraph in s.split("\n"):
		var line := ""
		for token in _tokens(paragraph):
			var trial := line + token
			if line != "" and measure(trial.strip_edges(false, true)) > width:
				out.append(line.strip_edges(false, true))
				line = token
			else:
				line = trial
		out.append(line.strip_edges(false, true))
	return out


## Break opportunities: after a space, or after a hyphen that is followed by a letter (CSS does the same).
func _tokens(paragraph: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var current := ""
	for i in paragraph.length():
		current += paragraph[i]
		var after_hyphen := paragraph[i] == "-" and i + 1 < paragraph.length() and paragraph[i + 1] != " "
		if paragraph[i] == " " or after_hyphen:
			tokens.append(current)
			current = ""
	if current != "":
		tokens.append(current)
	return tokens


func _draw() -> void:
	var f := _font()
	var asc := T.ascent(f, px)
	var line_height := pitch()
	var baseline_offset := (line_height - asc - T.descent(f, px)) * 0.5 + asc
	var shown := _shown()
	var consumed := 0
	for i in _lines.size():
		var line := _lines[i]
		var start := maxi(shown.find(line, consumed), 0) if line != "" else consumed
		consumed = start + line.length()
		var width := measure(line)
		var x := 0.0
		if align == "c":
			x = (size.x - width) * 0.5
		elif align == "r":
			x = size.x - width
		var baseline := i * line_height + baseline_offset
		_draw_line(f, line, Vector2(x, baseline), width, start)


func _draw_line(f: Font, line: String, origin: Vector2, width: float, start := 0) -> void:
	var sp := spacing_px()
	var lead := clampi(lead_len - start, 0, line.length())
	if kind == "mono":
		var step := T.MONO_ADVANCE * px + sp
		for j in line.length():
			if line[j] != " ":
				draw_char(f, Vector2(origin.x + j * step, origin.y), line[j], px, lead_color if j < lead else color)
				if faux:
					draw_char(f, Vector2(origin.x + j * step + px / 26.0, origin.y), line[j], px, lead_color if j < lead else color)
	elif sp == 0.0:
		if lead > 0:
			var lead_w := f.get_string_size(line.substr(0, lead), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_string(f, origin, line.substr(0, lead), HORIZONTAL_ALIGNMENT_LEFT, -1, px, lead_color)
			draw_string(f, origin + Vector2(lead_w, 0), line.substr(lead), HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		else:
			draw_string(f, origin, line, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	else:
		for j in line.length():
			var before := f.get_string_size(line.substr(0, j), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if j > 0 else 0.0
			draw_char(f, Vector2(origin.x + before + j * sp, origin.y), line[j], px, lead_color if j < lead else color)
	if strike:
		var y := origin.y - 0.3 * px
		draw_line(Vector2(origin.x, y), Vector2(origin.x + width, y), color, 1.0)
