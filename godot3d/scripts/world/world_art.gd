extends RefCounted
## Kestrel world-art profile (spec addendum 2026-10-05, W1 to W9): constant tables and pure helpers. No scene access;
## earthfront_3d.gd applies them only when `world_art_on` is true.

const TILE := 0.68  # one hex column in world units; land.jpg maps one column to 82 px
const PITCH_SIN := 0.839  # 1.05 / sqrt(1.05^2 + 0.68^2): the camera rig in earthfront_3d._update_camera
const TERRAIN_MARGIN_CELLS := 10
const ENVIRONMENT := {"exposure": 0.95, "saturation": 0.50, "contrast": 1.04, "ambient_energy": 0.72, "background": "0c2a40"}
const CAMERA := {"yaw": 0.0, "default_zoom": 10.0, "deploy_from": 15.5, "min_zoom": 7.5, "max_zoom": 18.0, "edge_cells": 8, "focus_zoom": 10.0}


static func active(model) -> bool:
	return model != null


## Half size (x, z) of the axis-aligned ground box that holds the four corners of an orthographic view on y = 0.
static func view_half_extent(zoom: float, aspect: float, yaw: float) -> Vector2:
	var half_w := zoom * aspect * 0.5
	var half_d := zoom * 0.5 / PITCH_SIN
	var right := Vector2(cos(yaw), -sin(yaw))
	var toward_camera := Vector2(sin(yaw), cos(yaw))
	return Vector2(absf(right.x) * half_w + absf(toward_camera.x) * half_d, absf(right.y) * half_w + absf(toward_camera.y) * half_d)


## The ground the camera may show: the map plus `cells` hex cells on every side (x in position.x, z in position.y).
static func world_bounds(map_w: int, map_h: int, origin_x: float, origin_z: float, hex_x: float, hex_z: float, cells: int) -> Rect2:
	var x0 := origin_x - float(cells) * hex_x
	var z0 := origin_z - float(cells) * hex_z
	return Rect2(x0, z0, float(map_w - 1 + 2 * cells) * hex_x, float(map_h - 1 + 2 * cells) * hex_z + hex_z * 0.5)


static func clamp_focus(focus: Vector3, zoom: float, aspect: float, yaw: float, bounds: Rect2) -> Vector3:
	var e := view_half_extent(zoom, aspect, yaw)
	return Vector3(_clamp_axis(focus.x, e.x, bounds.position.x, bounds.end.x), focus.y, _clamp_axis(focus.z, e.y, bounds.position.y, bounds.end.y))


static func _clamp_axis(value: float, half: float, lo: float, hi: float) -> float:
	if hi - lo <= 2.0 * half:
		return (lo + hi) * 0.5
	return clampf(value, lo + half, hi - half)


## A flat hex ring on y = 0: outer corners (+-rx, 0), (+-rx/2, +-hz); the inner ring is `width` thinner.
static func hex_outline_mesh(radius_x: float, half_z: float, width: float) -> ArrayMesh:
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var shrink := (radius_x - width) / radius_x
	for p in [Vector2(radius_x, 0), Vector2(radius_x * 0.5, half_z), Vector2(-radius_x * 0.5, half_z), Vector2(-radius_x, 0), Vector2(-radius_x * 0.5, -half_z), Vector2(radius_x * 0.5, -half_z)]:
		outer.append(Vector3(p.x, 0, p.y))
		inner.append(Vector3(p.x * shrink, 0, p.y * shrink))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in 6:
		var j := (i + 1) % 6
		for v in [outer[i], outer[j], inner[j], outer[i], inner[j], inner[i]]:
			st.add_vertex(v)
	return st.commit()


static func hover_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.435, 0.839, 0.910, 0.55)  # 6fd6e8
	return m


static func apply_environment(env: Environment) -> void:
	env.tonemap_exposure = float(ENVIRONMENT.exposure)
	env.adjustment_saturation = float(ENVIRONMENT.saturation)
	env.adjustment_contrast = float(ENVIRONMENT.contrast)
	env.ambient_light_energy = float(ENVIRONMENT.ambient_energy)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(String(ENVIRONMENT.background))


## gen.py's "gSun": warm light from the top-left, darker toward the bottom-right, plus a soft edge vignette.
static func atmosphere_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "WorldAtmosphere"
	layer.layer = 0
	layer.set_meta("world_art", true)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 warm : source_color = vec4(1.0, 0.949, 0.784, 0.14);
uniform vec4 dark : source_color = vec4(0.0, 0.0, 0.0, 0.22);
uniform float vignette = 0.22;
void fragment() {
    vec2 uv = SCREEN_UV;
    float diag = clamp(uv.x * 0.55 + uv.y * 0.45, 0.0, 1.0);
    float w = warm.a * (1.0 - smoothstep(0.0, 0.6, diag));
    float edge = smoothstep(0.55, 1.05, length((uv - 0.5) * vec2(1.25, 1.6)));
    float d = clamp(dark.a * smoothstep(0.4, 1.0, diag) + vignette * edge, 0.0, 0.6);
    COLOR = vec4(mix(warm.rgb, dark.rgb, d / max(w + d, 0.001)), max(w, d));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)
	return layer
