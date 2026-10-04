extends RefCounted
## Code-drawn atmosphere for the title screen: elliptical radial gradients, vertical/horizontal gradients, the Earth limb.
## Every builder adds one node to `parent` and returns it. Colours that fade to "transparent" must carry the same RGB with alpha 0.

const RADIAL := """
shader_type canvas_item;
uniform vec2 box_size;
uniform vec2 center;
uniform vec2 radii;
uniform vec4 c0; uniform vec4 c1; uniform vec4 c2; uniform vec4 c3;
uniform vec4 pos;
vec4 pm(vec4 c) { return vec4(c.rgb * c.a, c.a); }
void fragment() {
	vec2 p = UV * box_size;
	float t = length((p - center) / radii);
	vec4 r = pm(c0);
	if (t > pos.x) { r = mix(pm(c0), pm(c1), clamp((t - pos.x) / max(pos.y - pos.x, 1e-5), 0.0, 1.0)); }
	if (t > pos.y) { r = mix(pm(c1), pm(c2), clamp((t - pos.y) / max(pos.z - pos.y, 1e-5), 0.0, 1.0)); }
	if (t > pos.z) { r = mix(pm(c2), pm(c3), clamp((t - pos.z) / max(pos.w - pos.z, 1e-5), 0.0, 1.0)); }
	COLOR = vec4(r.rgb / max(r.a, 1e-5), r.a);
}
"""

const LIMB := """
shader_type canvas_item;
uniform vec2 origin;
uniform vec2 box_size;
uniform vec2 c = vec2(960.0, 2290.0);
uniform float R = 1500.0;
vec4 pm(vec4 col) { return vec4(col.rgb * col.a, col.a); }
vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }
vec4 body(vec2 p) {
	float g = length(p - vec2(960.0, 790.0)) / 3354.1;
	vec4 a = vec4(0.0706, 0.2588, 0.3608, 1.0);
	vec4 b = vec4(0.0431, 0.1647, 0.2471, 1.0);
	vec4 d = vec4(0.0275, 0.0863, 0.1216, 1.0);
	vec4 e = vec4(0.0118, 0.0275, 0.0510, 1.0);
	vec4 col = mix(a, b, clamp(g / 0.12, 0.0, 1.0));
	col = mix(col, d, clamp((g - 0.12) / 0.24, 0.0, 1.0));
	col = mix(col, e, clamp((g - 0.36) / 0.34, 0.0, 1.0));
	return col;
}
void fragment() {
	vec2 p = origin + UV * box_size;
	float sd = length(p - c) - R;
	vec4 glow_col = vec4(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 1.0);
	// outside: blurred shadow (0 -26px 90px .38) under a 2px rim light (0 -2px 0 .6)
	float sd_glow = length(p - (c + vec2(0.0, -26.0))) - R;
	vec4 outer = pm(vec4(glow_col.rgb, 0.38 / (1.0 + exp(1.702 * sd_glow / 45.0))));
	float sd_rim = length(p - (c + vec2(0.0, -2.0))) - R;
	if (sd_rim <= 0.0) { outer = over(pm(vec4(150.0 / 255.0, 245.0 / 255.0, 1.0, 0.6)), outer); }
	// inside: gradient with the inset glow (0 40px 100px .20)
	float sd_hole = length(p - (c + vec2(0.0, 40.0))) - R;
	vec4 inner = over(pm(vec4(glow_col.rgb, 0.20 / (1.0 + exp(-1.702 * sd_hole / 50.0)))), pm(body(p)));
	float e = clamp(0.5 - sd, 0.0, 1.0);
	vec4 r = inner * e + outer * (1.0 - e);
	COLOR = vec4(r.rgb / max(r.a, 1e-5), r.a);
}
"""


## Elliptical radial gradient, like CSS radial-gradient(rx ry at cx cy, stops...). stops: [[Color, position 0..1], ...] (1 to 4).
static func radial(parent: Node, rect: Rect2, center: Vector2, radii: Vector2, stops: Array) -> ColorRect:
	var node := ColorRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = rect.position
	node.size = rect.size
	var shader := Shader.new()
	shader.code = RADIAL
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("box_size", rect.size)
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("radii", radii)
	var filled: Array = stops.duplicate()
	while filled.size() < 4:
		filled.append([filled[-1][0], 1.0])
	var positions := Vector4(filled[0][1], filled[1][1], filled[2][1], filled[3][1])
	for i in 4:
		mat.set_shader_parameter("c%d" % i, filled[i][0])
	mat.set_shader_parameter("pos", positions)
	node.material = mat
	parent.add_child(node)
	return node


## Linear gradient over `rect`. horizontal = false runs top to bottom. stops: [[Color, offset], ...].
static func linear(parent: Node, rect: Rect2, stops: Array, horizontal := false) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s): return s[1]))
	gradient.colors = PackedColorArray(stops.map(func(s): return s[0]))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	tex.width = 256 if horizontal else 2
	tex.height = 2 if horizontal else 256
	var node := TextureRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture = tex
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.position = rect.position
	node.size = rect.size
	parent.add_child(node)
	return node


## The big Earth disc rising from the bottom of the title screen (3000px circle, centre (960, 2290)), clipped to `rect`.
static func limb(parent: Node, rect: Rect2) -> ColorRect:
	var node := ColorRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = rect.position
	node.size = rect.size
	var shader := Shader.new()
	shader.code = LIMB
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("origin", rect.position)
	mat.set_shader_parameter("box_size", rect.size)
	node.material = mat
	parent.add_child(node)
	return node
