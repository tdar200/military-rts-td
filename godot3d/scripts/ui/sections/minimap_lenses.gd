extends RefCounted
## Minimap lenses (board 1, minimap header): four toggle Buttons Land / Res / Bdr / Thr plus the lens overlay drawn over
## the minimap slot. Driven by vm["lens"] ({on, overlay}); `on` is the active lens and lives in the adapter. Clicking a
## key emits "minimap_lens" with its id. The overlay is in 0..1 minimap space: dots (deposits), cells (borders), route
## (the expected wave route). Land draws nothing extra. Builds nothing without the slice.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")

const KEYS := [["land", "Land"], ["res", "Res"], ["bdr", "Bdr"], ["thr", "Thr"]]
## Right edge of the header keys: panel x 12 + width 304 - border 1 - padding 8 - header padding 4.
const RIGHT := 303.0
const KEY_Y := 782.0
const SLOT := Rect2(21, 811, 288, 250)


class Overlay extends Control:
	var data: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _at(p: Dictionary) -> Vector2:
		return Vector2(float(p.get("u", 0.0)) * size.x, float(p.get("v", 0.0)) * size.y)

	func _draw() -> void:
		var cell: Dictionary = data.get("cell", {})
		var cw := maxf(2.0, float(cell.get("w", 0.017)) * size.x)
		var ch := maxf(2.0, float(cell.get("h", 0.02)) * size.y)
		for c in data.get("cells", []):
			var col: Color = T.BAD if str(c.get("k", "")) == "enemy" else T.CYAN
			col.a = 0.32 if str(c.get("k", "")) == "enemy" else 0.2
			draw_rect(Rect2(_at(c) - Vector2(cw, ch) * 0.5, Vector2(cw, ch)), col)
		var route: Array = data.get("route", [])
		if route.size() >= 2:
			var pts := PackedVector2Array()
			for p in route:
				pts.append(_at(p))
			draw_polyline(pts, T.WARN, 2.0, true)
			draw_circle(pts[pts.size() - 1], 3.0, T.WARN)
		for d in data.get("dots", []):
			draw_circle(_at(d), 3.5, T.VIOLET if str(d.get("k", "")) == "alloy" else T.CYAN_HI)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var lens = vm.get("lens", null)
	if not (lens is Dictionary) or lens.is_empty():
		return
	var overlay_data = lens.get("overlay", null)
	if overlay_data is Dictionary and not overlay_data.is_empty():
		var o := Overlay.new()
		o.data = overlay_data
		K.place(o, SLOT.position.x, SLOT.position.y, SLOT.size.x, SLOT.size.y)
		parent.add_child(o)
	var total := 4.0 * 3.0
	for k in KEYS:
		total += KeyCap.measure(str(k[1]))
	var x := RIGHT - total
	for k in KEYS:
		var on: bool = str(lens.get("on", "land")) == str(k[0])
		var cap := K.key(parent, str(k[1]), x, KEY_Y, {"border": T.CYAN if on else T.LINE, "col": T.CYAN_HI if on else T.TEXT, "fill": T.ACTIVE if on else T.KEY_BG})
		var hit := K.hit(parent, x, KEY_Y, cap.size.x, 22, str(k[1]))
		if emit.is_valid():
			hit.pressed.connect(emit.bind("minimap_lens", str(k[0])))
		x += cap.size.x + 4.0
