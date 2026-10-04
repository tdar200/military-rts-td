extends RefCounted
## Pure layout helpers for the research graph (no nodes, no drawing). Geometry is the Research mock's: node cards are
## 232x134, columns are 280 apart, rows 146 apart, and the first card sits at (4, 12) in graph space.
const NODE_W := 232.0
const NODE_H := 134.0
const COL_PITCH := 280.0
const ROW_PITCH := 146.0
const ORIGIN := Vector2(4, 12)
## How far an edge stops short of the card it points at (the mock leaves a 2px gap for the arrowhead tip).
const EDGE_GAP := 2.0


## Place `nodes` on a (col, row) grid.
## Each node is a Dictionary with optional `id`, `prereqs` (Array of ids), `col` and `row` (explicit cell pins).
## A node without `col` goes in the column of its longest-path depth (0 when it has no valid prerequisite). A node without
## `row` takes the first free row of its column, in input order, so the result is stable. A pinned cell that is already
## taken is treated as unpinned for its row, so two nodes never share a cell.
## Returns {keys, cells, cols, rows, depth, edges, missing}:
##   keys    Array[String]  unique key per input node (the id as a string; later duplicates get "#index" appended)
##   cells   key -> Vector2i (col, row)
##   cols    number of columns used, rows the number of rows used
##   depth   key -> longest-path depth
##   edges   Array of [from_key, to_key] for every prerequisite that resolves
##   missing key -> Array of prerequisite ids that do not exist (or point at the node itself)
static func layout(nodes: Array) -> Dictionary:
	var keys: Array = []
	var by_id: Dictionary = {}
	for i in nodes.size():
		var node: Dictionary = nodes[i] if nodes[i] is Dictionary else {}
		var id := str(node.get("id", "node%d" % i))
		var key := id
		if by_id.has(id):
			key = "%s#%d" % [id, i]
		else:
			by_id[id] = key
		keys.append(key)
	var edges: Array = []
	var missing: Dictionary = {}
	var prereq_keys: Dictionary = {}
	for i in nodes.size():
		var node: Dictionary = nodes[i] if nodes[i] is Dictionary else {}
		var resolved: Array = []
		var lost: Array = []
		var seen: Dictionary = {}
		for p in node.get("prereqs", []):
			var pid := str(p)
			if seen.has(pid):
				continue
			seen[pid] = true
			if by_id.has(pid) and by_id[pid] != keys[i]:
				resolved.append(by_id[pid])
				edges.append([by_id[pid], keys[i]])
			else:
				lost.append(p)
		prereq_keys[keys[i]] = resolved
		if not lost.is_empty():
			missing[keys[i]] = lost
	var depth: Dictionary = {}
	for key in keys:
		_depth_of(key, prereq_keys, depth, {})
	var cells: Dictionary = {}
	var taken: Dictionary = {}
	# Pass 1: nodes pinned to both a column and a row.
	for i in nodes.size():
		var node: Dictionary = nodes[i] if nodes[i] is Dictionary else {}
		if node.has("col") and node.has("row"):
			var cell := Vector2i(maxi(int(node["col"]), 0), maxi(int(node["row"]), 0))
			if not taken.has(cell):
				taken[cell] = true
				cells[keys[i]] = cell
	# Pass 2: everything else takes the first free row of its column.
	for i in nodes.size():
		if cells.has(keys[i]):
			continue
		var node: Dictionary = nodes[i] if nodes[i] is Dictionary else {}
		var col: int = maxi(int(node["col"]), 0) if node.has("col") else int(depth[keys[i]])
		var row := 0
		if node.has("row"):
			row = maxi(int(node["row"]), 0)
		while taken.has(Vector2i(col, row)):
			row += 1
		var cell := Vector2i(col, row)
		taken[cell] = true
		cells[keys[i]] = cell
	var cols := 0
	var rows := 0
	for cell in cells.values():
		cols = maxi(cols, cell.x + 1)
		rows = maxi(rows, cell.y + 1)
	return {"keys": keys, "cells": cells, "cols": cols, "rows": rows, "depth": depth, "edges": edges, "missing": missing}


static func _depth_of(key: String, prereq_keys: Dictionary, memo: Dictionary, visiting: Dictionary) -> int:
	if memo.has(key):
		return memo[key]
	if visiting.has(key):
		return 0
	visiting[key] = true
	var d := 0
	for p in prereq_keys.get(key, []):
		if visiting.has(p):
			continue
		d = maxi(d, _depth_of(p, prereq_keys, memo, visiting) + 1)
	visiting.erase(key)
	memo[key] = d
	return d


## Top-left of a cell's card in graph space.
static func node_pos(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell.x * COL_PITCH, cell.y * ROW_PITCH)


static func node_rect(cell: Vector2i) -> Rect2:
	return Rect2(node_pos(cell), Vector2(NODE_W, NODE_H))


## Graph-space size that holds `cols` x `rows` cards plus the 12px margin the mock keeps below the last row.
static func world_size(cols: int, rows: int) -> Vector2:
	if cols <= 0 or rows <= 0:
		return Vector2.ZERO
	return Vector2(ORIGIN.x + (cols - 1) * COL_PITCH + NODE_W + ORIGIN.x, ORIGIN.y + (rows - 1) * ROW_PITCH + NODE_H + ORIGIN.y)


## Edge from the right side of `from_cell` to the left side of `to_cell`: {p0, c1, c2, p1, straight}.
## Same-row edges are straight lines; others are cubic beziers with horizontal tangents (control offsets +24 / -22).
static func edge(from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	var a := node_rect(from_cell)
	var b := node_rect(to_cell)
	var p0 := Vector2(a.end.x, a.position.y + NODE_H * 0.5)
	var p1 := Vector2(b.position.x - EDGE_GAP, b.position.y + NODE_H * 0.5)
	return {"p0": p0, "p1": p1, "c1": p0 + Vector2(24, 0), "c2": p1 - Vector2(22, 0), "straight": is_equal_approx(p0.y, p1.y)}


## Points along an edge for drawing (2 points when straight).
static func edge_points(e: Dictionary, steps := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if e["straight"]:
		pts.append(e["p0"])
		pts.append(e["p1"])
		return pts
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(u * u * u * e["p0"] + 3.0 * u * u * t * e["c1"] + 3.0 * u * t * t * e["c2"] + t * t * t * e["p1"])
	return pts
