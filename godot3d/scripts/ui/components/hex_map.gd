extends RefCounted
## Flat hex-map geometry shared by the strategic map and the terrain guide swatches: where a cell sits in the 1620 x 1080 map
## area, its corners, the side two cells share, the 3D terrain's ground palette, and the meshes that draw the whole ground in
## one call (built once per ground string and kept).
const Look = preload("res://scripts/continuous_terrain.gd")

const AREA := Vector2(1620.0, 1080.0)
const MARGIN := 16.0
## A hex is 1 unit wide (point to point) and 1 unit tall (side to side); columns are 0.75 apart, rows 1.0, odd columns half a
## row lower: the spacing the sim and the 3D terrain use (vm_gameplay SIM_HEX_X).
const COL_STEP := 0.75
const CORNERS := [Vector2(-0.5, 0.0), Vector2(-0.25, -0.5), Vector2(0.25, -0.5), Vector2(0.5, 0.0), Vector2(0.25, 0.5), Vector2(-0.25, 0.5)]
const CACHE_LIMIT := 4

static var _mesh_cache: Dictionary = {}
static var _grid_cache: Dictionary = {}
static var cache_hits := 0


## Pixel size of one map unit and the top-left of the map, for a map of `w` x `h` cells centred in the left area.
static func layout(w: int, h: int) -> Dictionary:
	var span_x := float(w - 1) * COL_STEP + 1.0
	var span_y := float(h) + 0.5
	var u := floorf(minf((AREA.x - 2.0 * MARGIN) / span_x, (AREA.y - 2.0 * MARGIN) / span_y))
	return {"u": u, "origin": Vector2(roundf((AREA.x - span_x * u) * 0.5), roundf((AREA.y - span_y * u) * 0.5)), "w": w, "h": h}


static func center(l: Dictionary, x: int, y: int) -> Vector2:
	var u: float = l["u"]
	var o: Vector2 = l["origin"]
	return o + Vector2((float(x) * COL_STEP + 0.5) * u, (float(y) + 0.5 + (0.5 if x % 2 != 0 else 0.0)) * u)


static func corners(l: Dictionary, x: int, y: int) -> PackedVector2Array:
	var c := center(l, x, y)
	var u: float = l["u"]
	var out := PackedVector2Array()
	for k in CORNERS:
		out.append(c + k * u)
	return out


## The two corners cells a and b share (their common hex side), [] when they are not neighbours.
static func shared_side(l: Dictionary, a: Array, b: Array) -> Array:
	var pa := corners(l, int(a[0]), int(a[1]))
	var pb := corners(l, int(b[0]), int(b[1]))
	var out: Array = []
	for p in pa:
		for q in pb:
			if p.distance_to(q) < 0.5:
				out.append(p)
				break
	return out if out.size() == 2 else []


## Drops every cached mesh and line list (tests, and a map whose ground changed).
static func clear_caches() -> void:
	_mesh_cache.clear()
	_grid_cache.clear()
	cache_hits = 0


## The UI key colour of a ground glyph (continuous_terrain.gd GROUND_LEGEND, next to the 3D albedo in GROUND_LOOK).
static func ground_color(glyph: String) -> Color:
	return Color(str(Look.GROUND_LEGEND.get(glyph, Look.GROUND_LEGEND["g"])))


## One mesh for a list of cells [[x, y]] with a colour each (vertex colours), so a whole map is a single draw call.
static func hex_mesh(l: Dictionary, cells: Array, colors: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in cells.size():
		var base := verts.size()
		verts.append_array(corners(l, int(cells[i][0]), int(cells[i][1])))
		for k in 6:
			cols.append(colors[i])
		for k in range(1, 5):
			idx.append_array(PackedInt32Array([base, base + k, base + k + 1]))
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The ground mesh for a snapshot ground string, built once and kept: the ground never changes during a mission, so opening
## the map again (or toggling a lens) reuses it.
static func ground_mesh(vm: Dictionary) -> ArrayMesh:
	var l := layout(int(vm["width"]), int(vm["height"]))
	var key := hash([str(vm["ground"]), l["u"]])
	if _mesh_cache.has(key):
		cache_hits += 1
		return _mesh_cache[key]
	var glyphs: String = str(vm["ground"])
	var cells: Array = []
	var colors: Array = []
	for i in glyphs.length():
		cells.append([i % int(vm["width"]), i / int(vm["width"])])
		colors.append(ground_color(glyphs[i]))
	var mesh := hex_mesh(l, cells, colors)
	if _mesh_cache.size() >= CACHE_LIMIT:
		_mesh_cache.clear()
	_mesh_cache[key] = mesh
	return mesh


## Every hex outline of the map as line segments, cached beside the mesh.
static func grid_lines(vm: Dictionary) -> PackedVector2Array:
	var l := layout(int(vm["width"]), int(vm["height"]))
	var key := hash([int(vm["width"]), int(vm["height"]), l["u"]])
	if _grid_cache.has(key):
		return _grid_cache[key]
	var lines := PackedVector2Array()
	for y in int(vm["height"]):
		for x in int(vm["width"]):
			var p := corners(l, x, y)
			for k in 6:
				lines.append(p[k])
				lines.append(p[(k + 1) % 6])
	if _grid_cache.size() >= CACHE_LIMIT:
		_grid_cache.clear()
	_grid_cache[key] = lines
	return lines


