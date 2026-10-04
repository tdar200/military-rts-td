extends Control
## The mock's .key: mono 12px key label in a 22px high box, 1px border, radius 2.
const T = preload("res://scripts/ui/tokens.gd")

const HEIGHT := 22
const MIN_WIDTH := 22
const PAD := 5

var label := ""
var tone: Color = T.LINE
var text_color: Color = T.TEXT
var spacing := 0.0
var fill: Color = T.KEY_BG
var weight := 400


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Width of a key cap for `s` with extra letter-spacing `sp` px (buttons pass their own spacing down).
static func measure(s: String, sp := 0.0) -> float:
	return maxf(MIN_WIDTH, s.length() * (T.MONO_ADVANCE * 12.0 + sp) + 2 * (PAD + 1))


func setup(s: String, o := {}) -> Control:
	label = s
	spacing = o.get("sp", 0.0)
	tone = o.get("border", T.LINE)
	text_color = o.get("col", T.TEXT)
	fill = o.get("fill", T.KEY_BG)
	weight = o.get("wt", 400)
	if o.get("up", false):
		label = s.to_upper()
	custom_minimum_size = Vector2(measure(s, spacing), HEIGHT)
	size = custom_minimum_size
	queue_redraw()
	return self


## Draw a key cap onto any CanvasItem at `at` (used by buttons so they need no child nodes).
static func paint(ci: CanvasItem, at: Vector2, s: String, sp := 0.0, border: Color = T.LINE, col: Color = T.TEXT, bg: Color = T.KEY_BG, wt := 400) -> float:
	var width := measure(s, sp)
	var rect := Rect2(at, Vector2(width, HEIGHT))
	ci.draw_rect(rect, bg)
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(2)
	ci.draw_style_box(box, rect)
	var f := T.font("mono", wt)
	var step := T.MONO_ADVANCE * 12.0 + sp
	var text_w := s.length() * step
	var x := at.x + (width - text_w) * 0.5
	var baseline := at.y + (HEIGHT - (T.ascent(f, 12) + T.descent(f, 12))) * 0.5 + T.ascent(f, 12)
	for i in s.length():
		if s[i] != " ":
			ci.draw_char(f, Vector2(x + i * step, baseline), s[i], 12, col)
	return width


func _draw() -> void:
	paint(self, Vector2.ZERO, label, spacing, tone, text_color, fill, weight)
