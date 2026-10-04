extends ColorRect
## The mock's full-screen vignette: transparent inside an ellipse, fading to `strength` black at its rim.
## Drawn at z 50 so it sits over every HUD layer however the sections are re-ordered by rebuilds.
const SHADER := """
shader_type canvas_item;
uniform vec2 centre = vec2(960.0, 486.0);
uniform vec2 radii = vec2(1400.0, 900.0);
uniform float strength = 0.45;
uniform float inner = 0.55;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
void fragment() {
	vec2 p = UV * rect_size - centre;
	float d = length(p / radii);
	float t = clamp((d - inner) / (1.0 - inner), 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, strength * t);
}
"""

static var _shader: Shader


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	color = Color.WHITE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = _shader


## strength is the black alpha at the rim (the mock uses .45). The ellipse is centred at 50% / 45% of the rect.
func setup(w: float, h: float, strength := 0.45) -> Control:
	position = Vector2.ZERO
	size = Vector2(w, h)
	var m := material as ShaderMaterial
	m.set_shader_parameter("rect_size", Vector2(w, h))
	m.set_shader_parameter("centre", Vector2(w * 0.5, h * 0.45))
	m.set_shader_parameter("strength", strength)
	return self
