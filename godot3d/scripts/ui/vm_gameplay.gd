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


# ------------------------------------------------------------------ gameplay HUD helpers (task 12)

## Context the tile inspector adds to tile_inspect: the hex itself, its ground glyph, whether it lies in the player's
## construction zone, and the deposit standing on it (kind, remaining) when there is one. {} off the map.
static func tile_context(snap: Dictionary, ground_model, x: int, y: int) -> Dictionary:
	if ground_model == null or x < 0 or y < 0 or x >= ground_model.width or y >= ground_model.height:
		return {}
	var out := {"x": x, "y": y, "glyph": ground_model.glyph_at(x, y), "zone": false}
	for c in snap.get("construction_zone", []):
		if c is Array and c.size() >= 2 and int(c[0]) == x and int(c[1]) == y:
			out["zone"] = true
			break
	for d in snap.get("deposits", []):
		if d is Dictionary and int(d.get("x", -1)) == x and int(d.get("y", -1)) == y:
			out["deposit"] = {"kind": str(d.get("kind", "")), "remaining": int(d.get("remaining", 0))}
			break
	return out


## Pills for the territory card: only quantities the snapshot really carries. Total generation is `power_generation`;
## there is no per-minute income field, so no per-minute material or work deltas exist to show. [] when none.
static func yields(snap: Dictionary) -> Array:
	var out: Array = []
	var kw := int(snap.get("power_generation", 0))
	if kw > 0:
		out.append({"text": "+%d kW" % kw, "tone": "warn"})
	return out


## Resource deposits as {x, y, kind, remaining, claimed}. A deposit is claimed when a human Refinery stands within
## ORE_BONUS_RADIUS of it (Alloy is never claimed by a refinery). Emptied deposits are left out.
static func deposit_pins(snap: Dictionary) -> Array:
	var refineries: Array = []
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "building" and str(e.get("kind", "")) == "Refinery":
			refineries.append(entity_cell(e))
	var out: Array = []
	var list = snap.get("deposits", [])
	if not (list is Array):
		return out
	for d in list:
		if not (d is Dictionary) or int(d.get("remaining", 0)) <= 0:
			continue
		var dx := int(d.get("x", 0))
		var dy := int(d.get("y", 0))
		var claimed := false
		if str(d.get("kind", "")) == "Ore":
			for r in refineries:
				if hex_distance(dx, dy, int(r[0]), int(r[1])) <= ORE_BONUS_RADIUS:
					claimed = true
					break
		out.append({"x": dx, "y": dy, "kind": str(d.get("kind", "")), "remaining": int(d.get("remaining", 0)), "claimed": claimed})
	return out


## Counts for the colony ledger: human buildings and units, crew use, battery charge. Fields the snapshot lacks stay
## out. {} without entities.
static func ledger(snap: Dictionary) -> Dictionary:
	var ents := _entities(snap)
	if ents.is_empty():
		return {}
	var buildings := 0
	var units := 0
	for e in ents:
		if e is Dictionary and int(e.get("owner", -1)) == HUMAN:
			if str(e.get("category", "")) == "building":
				buildings += 1
			elif str(e.get("category", "")) == "unit":
				units += 1
	var out := {"structures": buildings, "units": units}
	var rows := _production_rows(snap)
	if not rows.is_empty():
		out["production"] = rows
	if int(snap.get("supply_cap", 0)) > 0:
		out["crew_used"] = int(snap.get("supply_used", 0))
		out["crew_cap"] = int(snap["supply_cap"])
	if int(snap.get("storage_capacity", 0)) > 0:
		out["battery_pct"] = roundi(100.0 * float(int(snap.get("energy_bits", 0)) / 65536) / float(snap["storage_capacity"]))
	return out


const PRODUCERS := ["Barracks", "VehicleFactory", "Airfield"]


## One row per finished human producer: busy rows carry the unit in production, its progress ratio and seconds left, idle
## rows (empty queue) say so. A running research becomes one more busy row. Producers are numbered only when there are
## several of the same kind, in entity order.
static func _production_rows(snap: Dictionary) -> Array:
	var names: Dictionary = load("res://scripts/ui/live_adapter.gd").KIND_NAMES
	var total := {}
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "building" and str(e.get("kind", "")) in PRODUCERS and int(e.get("construction", 0)) == 0:
			total[str(e["kind"])] = int(total.get(str(e["kind"]), 0)) + 1
	var seen := {}
	var rows: Array = []
	for e in _entities(snap):
		if not (e is Dictionary) or int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "building":
			continue
		var kind := str(e.get("kind", ""))
		if not (kind in PRODUCERS) or int(e.get("construction", 0)) != 0:
			continue
		seen[kind] = int(seen.get(kind, 0)) + 1
		var label := str(names.get(kind, kind))
		if int(total[kind]) > 1:
			label += " %d" % int(seen[kind])
		var duration := int(e.get("production_duration", 0))
		if str(e.get("production_name", "")) != "" and duration > 0:
			var left := maxi(0, duration - int(e.get("production_progress", 0)))
			rows.append({"name": label, "state": "busy", "ratio": clampf(float(e.get("production_progress", 0)) / float(duration), 0.0, 1.0), "note": "%s %d:%02d" % [str(e["production_name"]), _seconds(left) / 60, _seconds(left) % 60]})
		else:
			rows.append({"name": label, "state": "idle", "note": "queue empty"})
	var research_ticks := int(snap.get("active_research_ticks", 0))
	if int(snap.get("active_research_id", -1)) >= 0 and research_ticks > 0 and str(snap.get("active_research_name", "")) != "":
		var lab := {"name": "Lab", "state": "busy", "note": "%s %d:%02d" % [str(snap["active_research_name"]), _seconds(research_ticks) / 60, _seconds(research_ticks) % 60]}
		for option in snap.get("research_options", []):
			if option is Dictionary and int(option.get("id", -2)) == int(snap["active_research_id"]) and int(option.get("duration", 0)) > 0:
				lab["ratio"] = clampf(1.0 - float(research_ticks) / float(option["duration"]), 0.0, 1.0)
		rows.append(lab)
	return rows


const LENSES := ["land", "res", "bdr", "thr"]


## What a minimap lens draws, in hex coordinates: dots [{x, y, k}] (res: deposits k ore or alloy), cells [{x, y, k}]
## (bdr: k own for the construction zone and k enemy for enemy_border; thr: the enemy cells alone) and route [[x, y]]
## (thr: the expected wave route).
## Land and unknown lenses draw nothing: {}.
static func lens_hexes(snap: Dictionary, lens: String) -> Dictionary:
	match lens:
		"res":
			var dots: Array = []
			for d in snap.get("deposits", []):
				if d is Dictionary and int(d.get("remaining", 0)) > 0:
					dots.append({"x": int(d.get("x", 0)), "y": int(d.get("y", 0)), "k": "alloy" if str(d.get("kind", "")) == "Alloy" else "ore"})
			return {"dots": dots} if not dots.is_empty() else {}
		"bdr":
			var cells: Array = []
			for c in snap.get("construction_zone", []):
				if c is Array and c.size() >= 2:
					cells.append({"x": int(c[0]), "y": int(c[1]), "k": "own"})
			for c in enemy_border(snap):
				cells.append({"x": int(c[0]), "y": int(c[1]), "k": "enemy"})
			return {"cells": cells} if not cells.is_empty() else {}
		"thr":
			# The expected wave route and the enemy territory it leads to (R6: hexes within BORDER_RADIUS of alien structures).
			var out := {}
			var inbound := wave_inbound(snap)
			if not inbound.is_empty():
				out["route"] = inbound["route"]
			var cells: Array = []
			for c in enemy_border(snap):
				cells.append({"x": int(c[0]), "y": int(c[1]), "k": "enemy"})
			if not cells.is_empty():
				out["cells"] = cells
			return out
	return {}


## The army column of the colony panel: how many combat units the player has (every human unit but Harvesters) and how
## many of them stand idle, with the first idle id. {} when there are neither.
static func army(snap: Dictionary) -> Dictionary:
	var count := 0
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "unit" and str(e.get("kind", "")) != "Harvester":
			count += 1
	var idle := idle_crews(snap)
	if count == 0 and idle.is_empty():
		return {}
	return {"count": count, "idle": int(idle.get("count", 0)), "first_idle": int(idle.get("first_id", -1))}


# ------------------------------------------------------------------ boards 2 and 3 (task 12B)

## What the sim gives: a Power Plant beside a River or Ford hex draws +12 kW, a Refinery within one hex of Ore +20%
## (earthfront.rs river_bonus_kw / refinery_near_ore). test_vm_gameplay_boards23.gd asserts these have not drifted.
const RIVER_BONUS_KW := 12
const ORE_BONUS_PCT := 20


static func _wet_neighbour(ground_model, x: int, y: int) -> bool:
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if hex_distance(x, y, nx, ny) == 1 and nx >= 0 and ny >= 0 and nx < ground_model.width and ny < ground_model.height:
				var n: String = ground_model.name_at(nx, ny)
				if n == "River" or n == "Ford":
					return true
	return false


static func _kind_label(kind: String) -> String:
	return str(load("res://scripts/ui/live_adapter.gd").KIND_NAMES.get(kind, kind))


static func _thousands(n: int) -> String:
	return load("res://scripts/ui/live_screens.gd").thousands(n)


## The placement card under the cursor (board 2): the armed building on hex (x, y). `kw` is the card's draw (positive) or
## output (negative). Every row comes from the snapshot or the ground table: the board's 4 x 3 footprint and slope are not
## built (footprints are single hexes, R1, and the snapshot has no slope). {} off the map or without a ground model.
static func placing(snap: Dictionary, ground_model, kind: String, label: String, x: int, y: int, valid: bool, kw: int) -> Dictionary:
	if ground_model == null or x < 0 or y < 0 or x >= ground_model.width or y >= ground_model.height:
		return {}
	var props: Dictionary = ground_model.props_at(x, y)
	var ground_name := str(props.get("name", "ground"))
	var rows: Array = []
	var earthfront := bool(snap.get("earthfront", false))
	if kind == "Refinery" and earthfront:
		var best: Dictionary = {}
		for d in snap.get("deposits", []):
			if d is Dictionary and str(d.get("kind", "")) == "Ore" and int(d.get("remaining", 0)) > 0 and hex_distance(x, y, int(d.get("x", -99)), int(d.get("y", -99))) <= ORE_BONUS_RADIUS:
				if best.is_empty() or int(d["remaining"]) > int(best["remaining"]):
					best = d
		if best.is_empty():
			rows.append({"label": "Ore in range", "value": "None within 1 hex, no bonus", "tone": "dim"})
		else:
			rows.append({"label": "Ore in range", "value": "Ore, %s left, +%d%% output" % [_thousands(int(best["remaining"])), ORE_BONUS_PCT], "tone": "good"})
	if kind == "PowerPlant" and earthfront:
		if _wet_neighbour(ground_model, x, y):
			rows.append({"label": "River", "value": "River or ford beside it, +%d kW" % RIVER_BONUS_KW, "tone": "good"})
		else:
			rows.append({"label": "River", "value": "No river or ford beside it", "tone": "dim"})
	if not bool(props.get("buildable", false)):
		rows.append({"label": "Blocked tile", "value": "%s, cannot build" % ground_name, "tone": "bad"})
	var zone: Array = snap.get("construction_zone", [])
	if not zone.is_empty():
		var inside := false
		for c in zone:
			if c is Array and c.size() >= 2 and int(c[0]) == x and int(c[1]) == y:
				inside = true
				break
		if not inside:
			rows.append({"label": "Territory", "value": "Outside the construction zone", "tone": "bad"})
	if kw < 0:
		rows.append({"label": "Power", "value": "+%d kW generation" % -kw, "tone": "good"})
	elif kw > 0:
		var over := int(snap.get("power_demand", 0)) + kw > int(snap.get("power_generation", 0))
		rows.append({"label": "Power", "value": "-%d kW, %s" % [kw, "grid over capacity" if over else "within capacity"], "tone": "warn" if over else "good"})
	return {
		"title": label,
		"valid": valid,
		"status": "1 hex is clear" if valid else "1 hex is blocked",
		"tone": "good" if valid else "warn",
		"footprint": "Footprint 1 hex on %s" % ground_name,
		"rows": rows,
	}


## The projected grid panel (board 2): the Build screen's own bar maths (build_logic.projection) with the one-line advice
## under it. "Build a Reactor beside the river" appears only when a River or Ford hex really borders the construction
## zone. {} when the snapshot carries no power figures.
static func power_grid(snap: Dictionary, ground_model, _kind: String, kw: int) -> Dictionary:
	if not snap.has("power_generation") or not snap.has("power_demand"):
		return {}
	var generation := int(snap["power_generation"]) + maxi(-kw, 0)
	var after: Dictionary = preload("res://scripts/ui/build_logic.gd").projection(generation, int(snap["power_demand"]), maxi(kw, 0))
	var over := int(after["over"])
	var out := {"value": after["value"], "tone": after["tone"], "segments": after["segments"], "marker": after["marker"], "over": over, "lead": "", "text": ""}
	if over > 0:
		out["lead"] = "%d kW over." % over
		var river := ground_model != null and _river_by_zone(snap, ground_model)
		out["text"] = "Build a Reactor beside the river for +%d kW cooling." % RIVER_BONUS_KW if river else "Defence keeps priority; industry shares the deficit."
	return out


## Whether a River or Ford hex borders any hex of the construction zone. Called every frame while a building is armed, so
## the answer is kept until the zone or the map changes (the scan is hundreds of hexes).
static var _river_cache := {"key": 0, "has": false}


static func _river_by_zone(snap: Dictionary, ground_model) -> bool:
	var zone: Array = snap.get("construction_zone", [])
	var key := hash([zone, str(snap.get("map_name", "")), snap.get("ground", "").length()])
	if int(_river_cache["key"]) == key:
		return bool(_river_cache["has"])
	var found := false
	for c in zone:
		if c is Array and c.size() >= 2 and _wet_neighbour(ground_model, int(c[0]), int(c[1])):
			found = true
			break
	_river_cache = {"key": key, "has": found}
	return found


## "1:30" for a minute or more, "45 s" below.
static func _clock(seconds: int) -> String:
	return "%d s" % seconds if seconds < 60 else "%d:%02d" % [seconds / 60, seconds % 60]


## Enemy territory card (board 3): what the snapshot holds of the alien side. There is no fog in the sim, so the board's
## "partly seen" and "~14 est." are not built; counts are exact. {} when no alien entity exists.
static func enemy_intel(snap: Dictionary, ground_model) -> Dictionary:
	var guns := 0
	var aa := 0
	var walls := 0
	var units := 0
	for e in _entities(snap):
		if not (e is Dictionary) or int(e.get("owner", HUMAN)) == HUMAN:
			continue
		if str(e.get("category", "")) == "unit":
			units += 1
		else:
			match str(e.get("kind", "")):
				"GunTurret": guns += 1
				"AaTurret": aa += 1
				"Wall": walls += 1
	var hostile := false
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", HUMAN)) != HUMAN:
			hostile = true
			break
	if not hostile:
		return {}
	var rows: Array = []
	var defences: Array = []
	if guns > 0:
		defences.append("%d gun" % guns)
	if aa > 0:
		defences.append("%d AA" % aa)
	if walls > 0:
		defences.append("%d wall%s" % [walls, "" if walls == 1 else "s"])
	rows.append({"label": "Defences", "value": ", ".join(defences) if not defences.is_empty() else "None", "tone": ""})
	rows.append({"label": "Garrison", "value": "%d unit%s" % [units, "" if units == 1 else "s"], "tone": ""})
	if ground_model != null:
		var counts := {}
		for c in enemy_border(snap):
			var n: String = ground_model.name_at(int(c[0]), int(c[1]))
			counts[n] = int(counts.get(n, 0)) + 1
		var names: Array = counts.keys()
		names.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and str(a) < str(b)))
		if not names.is_empty():
			rows.append({"label": "Terrain", "value": ", ".join(names.slice(0, 2)), "tone": ""})
	if int(snap.get("next_wave_ticks", -1)) >= 0:
		var value := _clock(_seconds(int(snap["next_wave_ticks"])))
		if int(snap.get("next_expedition_size", 0)) > 0:
			value += ", %d units" % int(snap["next_expedition_size"])
		rows.append({"label": "Reinforce", "value": value, "tone": "warn"})
	return {"rows": rows}


const FOOT_KINDS := ["Infantry", "AntiArmor"]
const AIR_KINDS := ["Helicopter"]


static func _entity_by_id(snap: Dictionary, id: int) -> Dictionary:
	for e in _entities(snap):
		if e is Dictionary and int(e.get("id", -1)) == id:
			return e
	return {}


static func _speed_text(pct: int) -> String:
	if pct == 100:
		return "normal speed"
	return "speed %s%d%%" % ["+" if pct > 100 else "-", absi(pct - 100)]


## Combat preview (board 3, Civ-style): the selected human units `attacker_ids` against the alien entity standing on
## `target` hex. Only what the data backs: the matchup, the speed and range the attackers' ground gives, and the cover the
## target's ground gives. The snapshot has no weapon, armour or range data, so health forecasts, damage and "range 7 tiles"
## are not built, nor the board's "walls in the line" (no line-of-fire data). {} without attackers or a hostile target.
static func combat_preview(snap: Dictionary, ground_model, attacker_ids: Array, target: Array) -> Dictionary:
	if ground_model == null or target.size() < 2:
		return {}
	var foe: Dictionary = {}
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", HUMAN)) != HUMAN:
			var c := entity_cell(e)
			if int(c[0]) == int(target[0]) and int(c[1]) == int(target[1]):
				foe = e
				break
	if foe.is_empty():
		return {}
	var kinds := {}
	var ground_votes := {}
	var stand_at := {}
	var foot := 0
	var wheels := 0
	for id in attacker_ids:
		var a := _entity_by_id(snap, int(id))
		if a.is_empty() or int(a.get("owner", -1)) != HUMAN or str(a.get("category", "")) != "unit":
			continue
		var kind := str(a.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind in AIR_KINDS:
			continue
		var cell := entity_cell(a)
		var glyph: String = ground_model.glyph_at(int(cell[0]), int(cell[1]))
		ground_votes[glyph] = int(ground_votes.get(glyph, 0)) + 1
		if not stand_at.has(glyph):
			stand_at[glyph] = cell
		if kind in FOOT_KINDS:
			foot += 1
		else:
			wheels += 1
	if kinds.is_empty():
		return {}
	var parts: Array = []
	var order: Array = kinds.keys()
	order.sort()
	for k in order:
		parts.append("%d x %s" % [int(kinds[k]), _kind_label(str(k))])
	var out := {"sub": "%s vs Alien %s" % [", ".join(parts), _kind_label(str(foe.get("kind", ""))).to_lower()], "rows": []}
	var rows: Array = out["rows"]
	if not ground_votes.is_empty():
		var best := ""
		for glyph in ground_votes:
			if best == "" or int(ground_votes[glyph]) > int(ground_votes[best]):
				best = glyph
		var spot: Array = stand_at[best]
		var here: Dictionary = ground_model.props_at(int(spot[0]), int(spot[1]))
		var name := str(here.get("name", "ground"))
		var pct := int(here.get("infantry_pct", 100)) if foot >= wheels else int(here.get("vehicle_pct", 100))
		rows.append({"label": "Standing on %s" % name, "value": _speed_text(pct), "tone": "good" if pct > 100 else ("bad" if pct < 100 else "dim")})
		if int(here.get("range_pct", 0)) > 0:
			rows.append({"label": "Holding %s" % name, "value": "+%d%% range" % int(here["range_pct"]), "tone": "good"})
	var fc := entity_cell(foe)
	var there: Dictionary = ground_model.props_at(int(fc[0]), int(fc[1]))
	var cover := int(there.get("cover_pct", 0))
	rows.append({"label": "Target on %s" % str(there.get("name", "ground")), "value": "-%d%% damage" % cover if cover > 0 else "no cover", "tone": "bad" if cover > 0 else "dim"})
	return out

