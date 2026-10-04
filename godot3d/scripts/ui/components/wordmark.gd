extends Control
## The title wordmark: Rajdhani Bold, letter-spaced, filled with a vertical white-to-cyan gradient and a soft cyan glow.
## The glow is a ring of low-alpha copies under the glyphs (a stand-in for CSS drop-shadow 0 0 26px).
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const GRADIENT := """
shader_type canvas_item;
uniform float box_h = 128.0;
varying float vy;
void vertex() { vy = VERTEX.y; }
void fragment() {
	float t = clamp(vy / box_h, 0.0, 1.0);
	vec3 a = vec3(1.0, 1.0, 1.0);
	vec3 b = vec3(0.5882, 0.9608, 1.0);
	vec3 c = vec3(0.2510, 0.8627, 0.9216);
	vec3 col = t < 0.52 ? mix(a, b, t / 0.52) : mix(b, c, (t - 0.52) / 0.48);
	COLOR = vec4(col, COLOR.a);
}
"""

var word := ""
var px := 128
var spacing_em := 0.1
var _fill: TextBox


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = TextBox.new()
	add_child(_fill)


func setup(s: String, size_px := 128, sp := 0.1) -> Control:
	word = s
	px = size_px
	spacing_em = sp
	_fill.configure(s, {"f": "disp", "wt": 700, "px": px, "sp": sp, "lh": float(px), "up": true, "col": Color.WHITE})
	_fill.size = Vector2(_fill.get_minimum_size().x, float(px))
	var shader := Shader.new()
	shader.code = GRADIENT
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("box_h", float(px))
	_fill.material = mat
	custom_minimum_size = _fill.size
	size = _fill.size
	queue_redraw()
	return self


func _draw() -> void:
	if word == "":
		return
	var f := T.font("disp", 700)
	var asc := T.ascent(f, px)
	var baseline := (px - asc - T.descent(f, px)) * 0.5 + asc
	var sp := spacing_em * px
	var s := word.to_upper()
	var origins: Array = []
	for j in s.length():
		var before := f.get_string_size(s.substr(0, j), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if j > 0 else 0.0
		origins.append(before + j * sp)
	var sigma := 22.0
	for ring in range(1, 9):
		var r := ring * 5.0
		var steps := 8 + ring * 2
		var alpha := 0.45 * exp(-r * r / (2.0 * sigma * sigma)) * 0.026
		for k in steps:
			var a := TAU * k / steps
			var at := Vector2(cos(a), sin(a)) * r
			for j in s.length():
				draw_char(f, Vector2(origins[j], baseline) + at, s[j], px, Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, alpha))
