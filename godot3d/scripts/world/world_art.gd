extends RefCounted
## Kestrel world-art profile (spec addendum 2026-10-05, W1 to W9): constant tables and pure helpers. No scene access;
## earthfront_3d.gd applies them only when `world_art_on` is true.

const TILE := 0.68  # one hex column in world units; land.jpg maps one column to 82 px
const PITCH_SIN := 0.839  # 1.05 / sqrt(1.05^2 + 0.68^2): the camera rig in earthfront_3d._update_camera
const TERRAIN_MARGIN_CELLS := 10
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
