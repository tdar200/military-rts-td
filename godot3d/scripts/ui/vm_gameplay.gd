extends RefCounted
## Pure view-model slices for the gameplay HUD, computed from one bridge snapshot (and its GroundModel).
## Every function answers {} / [] when the data it needs is absent, so a section simply builds nothing. Nothing here
## is invented: counts, percentages and bonuses come from the snapshot rows, never from constants of the game rules.

const HUMAN := 0
## Same values as earthfront_3d.gd (SIM_HEX_X, SIM_CELL_CENTER); test_vm_gameplay.gd asserts they have not drifted.
const SIM_HEX_X := 0.75
const SIM_CELL_CENTER := 0.5
const BORDER_RADIUS := 3
## An ore deposit this close to a refinery is what the sim counts as the ore bonus.
const ORE_BONUS_RADIUS := 1


# ------------------------------------------------------------------ helpers

## Hex distance between two flat-top odd-q offset cells (odd columns sit half a row lower, as in _hex_world).
static func hex_distance(ax: int, ay: int, bx: int, by: int) -> int:
	var ar := ay - (ax - (ax & 1)) / 2
	var br := by - (bx - (bx & 1)) / 2
	var dq := bx - ax
	var dr := br - ar
	return maxi(maxi(absi(dq), absi(dr)), absi(dq + dr))


## Hex cell [x, y] an entity stands on. The snapshot carries sim coordinates (16.16 fixed point): columns are 0.75 apart,
## rows 1.0 apart, odd columns half a row lower; a cell centre is at +0.5.
static func entity_cell(e: Dictionary) -> Array:
	var sx := float(int(e.get("x_bits", 0))) / 65536.0
	var sz := float(int(e.get("z_bits", 0))) / 65536.0
	var col := roundi((sx - SIM_CELL_CENTER) / SIM_HEX_X)
	var row := roundi(sz - SIM_CELL_CENTER - (0.5 if col % 2 != 0 else 0.0))
	return [col, row]


static func _entities(snap: Dictionary) -> Array:
	var list = snap.get("entities", [])
	return list if list is Array else []


## Resolved at call time (not preloaded) so this file and live_adapter.gd never depend on each other at load.
static func _ticks_per_second() -> float:
	return float(load("res://scripts/ui/live_adapter.gd").TICKS_PER_SECOND)


static func _seconds(ticks: int) -> int:
	return ceili(float(ticks) / _ticks_per_second())


# ------------------------------------------------------------------ slices

## Construction zone by ground type: {"tiles", "composition": [{glyph, name, pct}]}, largest first. Percentages use
## the largest-remainder method so they total exactly 100. {} without a ground model or a zone.
static func territory(snap: Dictionary, ground_model) -> Dictionary:
	if ground_model == null:
		return {}
	var zone = snap.get("construction_zone", [])
	if not (zone is Array) or zone.is_empty():
		return {}
	var cells: Array = []
	for c in zone:
		if c is Array and c.size() >= 2 and int(c[0]) >= 0 and int(c[1]) >= 0 and int(c[0]) < ground_model.width and int(c[1]) < ground_model.height:
			cells.append(c)
	if cells.is_empty():
		return {}
	var counts: Dictionary = ground_model.counts_in(cells)
	var total := cells.size()
	var rows: Array = []
	var assigned := 0
	for glyph in counts:
		var exact := 100.0 * float(counts[glyph]) / float(total)
		var base := int(floor(exact))
		assigned += base
		rows.append({"glyph": glyph, "name": "", "pct": base, "count": int(counts[glyph]), "rem": exact - base})
	for c in cells:
		for row in rows:
			if row["name"] == "" and row["glyph"] == ground_model.glyph_at(int(c[0]), int(c[1])):
				row["name"] = ground_model.name_at(int(c[0]), int(c[1]))
	var by_remainder := rows.duplicate()
	by_remainder.sort_custom(func(a, b): return a["rem"] > b["rem"] or (a["rem"] == b["rem"] and a["glyph"] < b["glyph"]))
	for i in 100 - assigned:
		by_remainder[i % by_remainder.size()]["pct"] += 1
	rows.sort_custom(func(a, b): return a["count"] > b["count"] or (a["count"] == b["count"] and a["glyph"] < b["glyph"]))
	var composition: Array = []
	for row in rows:
		composition.append({"glyph": row["glyph"], "name": row["name"], "pct": row["pct"]})
	return {"tiles": total, "composition": composition}


## What the tile under the cursor is: the ground_table row for its glyph, plus bonus_text only when a building standing
## on that exact tile reports a real river_kw / ore_bonus. {} off the map or without a ground model.
static func tile_inspect(snap: Dictionary, ground_model, x: int, y: int) -> Dictionary:
	if ground_model == null or x < 0 or y < 0 or x >= ground_model.width or y >= ground_model.height:
		return {}
	var row: Dictionary = ground_model.props_at(x, y)
	if row.is_empty():
		return {}
	return {
		"name": str(row.get("name", "")),
		"cover_pct": int(row.get("cover_pct", 0)),
		"range_pct": int(row.get("range_pct", 0)),
		"infantry_pct": int(row.get("infantry_pct", 0)),
		"vehicle_pct": int(row.get("vehicle_pct", 0)),
		"buildable": bool(row.get("buildable", false)),
		"bonus_text": _bonus_text(snap, x, y),
	}


static func _bonus_text(snap: Dictionary, x: int, y: int) -> String:
	for e in _entities(snap):
		if not (e is Dictionary) or str(e.get("category", "")) != "building":
			continue
		var cell := entity_cell(e)
		if int(cell[0]) != x or int(cell[1]) != y:
			continue
		if int(e.get("river_kw", 0)) > 0:
			return "River +%d kW" % int(e["river_kw"])
		# ore_bonus is a bool on refineries. The haul claim is made only when an Ore deposit (never Alloy) is really there.
		if bool(e.get("ore_bonus", false)) and _ore_deposit_near(snap, x, y):
			return "Ore haul +20%"
	return ""


static func _ore_deposit_near(snap: Dictionary, x: int, y: int) -> bool:
	for d in snap.get("deposits", []):
		if d is Dictionary and str(d.get("kind", "")) == "Ore" and hex_distance(x, y, int(d.get("x", -99)), int(d.get("y", -99))) <= ORE_BONUS_RADIUS:
			return true
	return false


## Idle human units (the snapshot emits `idle` for the human player only; Harvesters are never idle). The client has no
## separate "crew" class (crew is the supply meter), so this counts every idle human unit. {} when none.
static func idle_crews(snap: Dictionary) -> Dictionary:
	var count := 0
	var first_id := -1
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "unit" and bool(e.get("idle", false)) and str(e.get("kind", "")) != "Harvester":
			count += 1
			if first_id < 0:
				first_id = int(e.get("id", -1))
	if count == 0:
		return {}
	return {"count": count, "first_id": first_id}


## Seconds until the next wave, from next_wave_ticks at the top bar's tick rate. {} when the snapshot has no timer.
static func next_alert(snap: Dictionary) -> Dictionary:
	if not snap.has("next_wave_ticks") or int(snap["next_wave_ticks"]) < 0:
		return {}
	return {"label": "Wave %02d" % (int(snap.get("waves_survived", 0)) + 1), "seconds": _seconds(int(snap["next_wave_ticks"]))}


## The expected route of the next wave (live-computed by the bridge, so it can change; [] if the base is walled off).
## eta_s is left out when the snapshot has no wave timer.
static func wave_inbound(snap: Dictionary) -> Dictionary:
	var route = snap.get("wave_route", [])
	if not (route is Array) or route.is_empty():
		return {}
	var hexes: Array = []
	for c in route:
		if c is Array and c.size() >= 2:
			hexes.append([int(c[0]), int(c[1])])
	if hexes.is_empty():
		return {}
	var out := {"route": hexes, "wave": int(snap.get("waves_survived", 0)) + 1}
	if snap.has("next_wave_ticks") and int(snap["next_wave_ticks"]) >= 0:
		out["eta_s"] = _seconds(int(snap["next_wave_ticks"]))
	return out


## Hexes within BORDER_RADIUS of an alien structure (non-unit buildings of the non-human owner; the core node if the
## snapshot lists no alien structure), clipped to the map, row-major, no duplicates.
static func enemy_border(snap: Dictionary) -> Array:
	var anchors: Array = []
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", HUMAN)) != HUMAN and str(e.get("category", "")) == "building":
			anchors.append(entity_cell(e))
	if anchors.is_empty():
		var core = snap.get("core_node", [])
		if core is Array and core.size() >= 2:
			anchors.append([int(core[0]), int(core[1])])
	if anchors.is_empty():
		return []
	var width := int(snap.get("map_width", 0))
	var height := int(snap.get("map_height", 0))
	var seen := {}
	for a in anchors:
		for y in range(int(a[1]) - BORDER_RADIUS - 1, int(a[1]) + BORDER_RADIUS + 2):
			for x in range(int(a[0]) - BORDER_RADIUS, int(a[0]) + BORDER_RADIUS + 1):
				if x < 0 or y < 0 or (width > 0 and x >= width) or (height > 0 and y >= height):
					continue
				if hex_distance(int(a[0]), int(a[1]), x, y) <= BORDER_RADIUS:
					seen[Vector2i(x, y)] = true
	var keys: Array = seen.keys()
	keys.sort_custom(func(p, q): return p.y < q.y or (p.y == q.y and p.x < q.x))
	return keys.map(func(v): return [v.x, v.y])


## Named map regions as {name, kind, x0, y0, x1, y1}. [] when the snapshot has none.
static func regions(snap: Dictionary) -> Array:
	var out: Array = []
	var list = snap.get("regions", [])
	if not (list is Array):
		return out
	for r in list:
		if r is Dictionary and str(r.get("name", "")) != "":
			out.append({"name": str(r["name"]), "kind": str(r.get("kind", "")), "x0": int(r.get("x0", 0)), "y0": int(r.get("y0", 0)), "x1": int(r.get("x1", 0)), "y1": int(r.get("y1", 0))})
	return out


## {unit id: rank} for units that have earned a rank (rank > 0).
static func veterans(snap: Dictionary) -> Dictionary:
	var out := {}
	for e in _entities(snap):
		if e is Dictionary and int(e.get("rank", 0)) > 0:
			out[int(e.get("id", -1))] = int(e["rank"])
	return out
