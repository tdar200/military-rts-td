extends RefCounted
## The snapshot's ground layer decoded: one glyph per tile (row-major, map_width x map_height) plus the ground_table
## rows that describe each glyph. Pure data, no scene access.

var width := 0
var height := 0
var _ground := ""
var _table := {}  # glyph -> ground_table row


## Null when the snapshot carries no ground string, or its length is not map_width * map_height.
static func from_snapshot(snap: Dictionary) -> RefCounted:
	var g: String = str(snap.get("ground", ""))
	var w := int(snap.get("map_width", 0))
	var h := int(snap.get("map_height", 0))
	if g == "" or w <= 0 or h <= 0 or g.length() != w * h:
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
