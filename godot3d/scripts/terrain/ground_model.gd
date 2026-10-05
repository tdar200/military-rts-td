extends RefCounted
## The snapshot's ground layer decoded: one glyph per tile (row-major, map_width x map_height) plus the ground_table
## rows that describe each glyph. Pure data, no scene access.

var width := 0
var height := 0
var _ground := ""
var _table := {}  # glyph -> ground_table row


## True for a well-formed layer that is Grassland everywhere. Survival's bridge emits one (the sim always carries a ground
## layer), and it describes no terrain: the client keeps its noise terrain and shows no ground UI for it. A wrong-sized
## all-g string is not "flat", it is malformed, and still reported as such.
static func is_flat(snap: Dictionary) -> bool:
	var g: String = str(snap.get("ground", ""))
	return g != "" and g.length() == int(snap.get("map_width", 0)) * int(snap.get("map_height", 0)) and g.count("g") == g.length()


## Null when the snapshot carries no ground string, a flat all-Grassland one, or one whose length is not map_width * map_height.
static func from_snapshot(snap: Dictionary) -> RefCounted:
	var g: String = str(snap.get("ground", ""))
	var w := int(snap.get("map_width", 0))
	var h := int(snap.get("map_height", 0))
	if g == "" or w <= 0 or h <= 0 or g.length() != w * h or is_flat(snap):
		return null
	var m := new()
	m.width = w
	m.height = h
	m._ground = g
	for row in snap.get("ground_table", []):
		if row is Dictionary:
			m._table[str(row.get("glyph", ""))] = row
	return m


## Off-map reads answer Grassland so edge smoothing and lookups never fail.
func glyph_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return "g"
	return _ground[y * width + x]


func props_at(x: int, y: int) -> Dictionary:
	return _table.get(glyph_at(x, y), {})


func name_at(x: int, y: int) -> String:
	return str(props_at(x, y).get("name", ""))


func is_wet(x: int, y: int) -> bool:
	var n := name_at(x, y)
	return n == "River" or n == "Ford" or n == "Sea"


## glyph -> number of listed cells ([x, y] pairs) on that glyph.
func counts_in(cells: Array) -> Dictionary:
	var out := {}
	for c in cells:
		var gl := glyph_at(int(c[0]), int(c[1]))
		out[gl] = int(out.get(gl, 0)) + 1
	return out
