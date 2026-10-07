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
		if not (e is Dictionary) or str(e.get("category", "")) != "building" or bool(e.get("remembered", false)):
			continue
		var cell := entity_cell(e)
		if int(cell[0]) != x or int(cell[1]) != y:
			continue
		if int(e.get("river_kw", 0)) > 0:
			return "River +%d kW" % int(e["river_kw"])
		# ore_bonus is a bool on refineries. The haul claim is made only when an Ore deposit (never Alloy) is really there.
		if bool(e.get("ore_bonus", false)) and _ore_deposit_near(snap, x, y):
			return "Ore haul +%d%%" % ORE_BONUS_PCT
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
## Kestrel feeds its alert pings in `pings` ({jump: alerts Space can frame, key: its cap, attack: a ring is live}; empty
## in Survival and before the first hit): they ride on the same chip, timer or not.
static func next_alert(snap: Dictionary, pings := {}) -> Dictionary:
	var out := {}
	if snap.has("next_wave_ticks") and int(snap["next_wave_ticks"]) >= 0:
		out = {"label": "Wave %02d" % (int(snap.get("waves_survived", 0)) + 1), "seconds": _seconds(int(snap["next_wave_ticks"]))}
	if int(pings.get("jump", 0)) > 0:
		out["jump"] = int(pings["jump"])
		out["key"] = str(pings.get("key", ""))
		if bool(pings.get("attack", false)):
			out["attack"] = true
	return out


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


## The display name of a building or unit kind (Supply Depot, not SupplyDepot).
static func kind_label(kind: String) -> String:
	return _kind_label(kind)


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


## Pause menu (board 9): the mission snapshot rows and the confirm sub-panel text, all from the snapshot. The board's
## Objective, wave "of 05" total and "Last save" rows are not built: the snapshot has no objective text, no wave total and
## the game has no save. `losses` is the client's own count of lost units (session_log), -1 when it has none. `stopped`
## says the simulation really is not stepping (the caller compares the bridge tick). {} without a snapshot.
static func pause(snap: Dictionary, losses := -1, stopped := true) -> Dictionary:
	if snap.is_empty() or not snap.has("tick"):
		return {}
	var elapsed := _mmss(int(float(int(snap["tick"])) / _ticks_per_second()))
	var rows: Array = [
		{"label": "Waves survived", "value": str(int(snap.get("waves_survived", 0)))},
		{"label": "Elapsed", "value": elapsed, "mono": true},
	]
	var next_ticks := int(snap.get("next_wave_ticks", -1))
	if next_ticks >= 0:
		rows.append({"label": "Next wave", "value": _mmss(_seconds(next_ticks)), "mono": true})
	if snap.has("money_bits"):
		rows.append({"label": "Material", "value": str(int(snap["money_bits"]) / 65536), "mono": true})
	if snap.has("power_generation") and snap.has("power_demand"):
		var gen := int(snap["power_generation"])
		var demand := int(snap["power_demand"])
		rows.append({"label": "Power", "value": "%d / %d kW" % [gen, demand], "mono": true, "tone": "warn" if demand > gen else ""})
	var led := ledger(snap)
	if led.has("units"):
		rows.append({"label": "Units alive", "value": str(int(led["units"])), "mono": true})
	if losses >= 0:
		rows.append({"label": "Losses", "value": str(losses), "mono": true})
	var out := {"stopped": stopped, "elapsed": elapsed, "rows": rows, "keys": pause_keys()}
	if str(snap.get("map_name", "")) != "":
		out["map"] = str(snap["map_name"])
	return out


## The key caps printed on the menu's Resume and Controls buttons, from the one keybinding list.
static func pause_keys() -> Dictionary:
	var kb = load("res://scripts/ui/keybinds.gd")
	return {"resume": kb.cap(kb.PAUSE), "controls": kb.cap(kb.CONTROLS)}


static func _mmss(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


## Whether the snapshot carries a Kestrel fog mask that hides something (the bridge's `fog`: one digit per cell, 0
## unseen, 1 explored, 2 visible). Without one (Survival, EARTHFRONT_FOG=0) every panel reads as before fog.
static func fogged(snap: Dictionary) -> bool:
	var mask = snap.get("fog", "")
	if not (mask is String) or mask == "":
		return false
	var w := int(snap.get("map_width", 0))
	var h := int(snap.get("map_height", 0))
	if w > 0 and h > 0 and mask.length() != w * h:
		return false
	return mask.count("2") != mask.length()


## Percent of the map explored or visible under the fog mask (100 without fog).
static func scouted_pct(snap: Dictionary) -> int:
	if not fogged(snap):
		return 100
	var mask: String = snap["fog"]
	return roundi(100.0 * float(mask.length() - mask.count("0")) / float(mask.length()))


## Enemy territory card (board 3): what the snapshot holds of the alien side. Without fog the counts are exact (the
## board's "partly seen" and "~14 est." are not built). Under Kestrel fog the snapshot holds only what the player knows:
## structures in sight or remembered (named as last seen), units in sight, and how much of the map is scouted; the card
## then shows before contact ("Not scouted"). {} without fog when no alien entity exists.
static func enemy_intel(snap: Dictionary, ground_model) -> Dictionary:
	var fog := fogged(snap)
	var guns := 0
	var aa := 0
	var walls := 0
	var units := 0
	var memories := 0
	for e in _entities(snap):
		if not (e is Dictionary) or int(e.get("owner", HUMAN)) == HUMAN:
			continue
		if str(e.get("category", "")) == "unit":
			units += 1
		else:
			if bool(e.get("remembered", false)):
				memories += 1
			match str(e.get("kind", "")):
				"GunTurret": guns += 1
				"AaTurret": aa += 1
				"Wall": walls += 1
	var hostile := false
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", HUMAN)) != HUMAN:
			hostile = true
			break
	if not hostile and not fog:
		return {}
	var rows: Array = []
	var defences: Array = []
	if guns > 0:
		defences.append("%d gun" % guns)
	if aa > 0:
		defences.append("%d AA" % aa)
	if walls > 0:
		defences.append("%d wall%s" % [walls, "" if walls == 1 else "s"])
	if fog:
		rows.append({"label": "Defences", "value": ", ".join(defences) if not defences.is_empty() else ("Not scouted" if not hostile else "None seen"), "tone": ""})
		rows.append({"label": "Garrison", "value": "%d unit%s in sight" % [units, "" if units == 1 else "s"], "tone": ""})
		if memories > 0:
			rows.append({"label": "Memory", "value": "%d last seen" % memories, "tone": ""})
		rows.append({"label": "Scouted", "value": "%d%% of the map" % scouted_pct(snap), "tone": ""})
	else:
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


const Rules := preload("res://scripts/ui/combat_rules.gd")
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
## `target` hex. Rows, in order: the damage type of each attacker kind against the target's armour class (sim damage
## matrix), the veterancy bonus of any selected veterans (sim rank factors), the speed and range the attackers' ground
## gives, and the cover the target's ground gives. A damage row is built only when both the attacker kind and the target's
## kind and category are known; a rank row only for armed units with rank above 0. {} without attackers or a hostile
## target.
static func combat_preview(snap: Dictionary, ground_model, attacker_ids: Array, target: Array) -> Dictionary:
	if ground_model == null or target.size() < 2:
		return {}
	var foe: Dictionary = {}
	for e in _entities(snap):
		if e is Dictionary and int(e.get("owner", HUMAN)) != HUMAN and not bool(e.get("remembered", false)):  # a memory carries no live intel
			var c := entity_cell(e)
			if int(c[0]) == int(target[0]) and int(c[1]) == int(target[1]):
				foe = e
				break
	if foe.is_empty():
		return {}
	var kinds := {}
	var ranks := {}
	var grounded: Array = []
	for id in attacker_ids:
		var a := _entity_by_id(snap, int(id))
		if a.is_empty() or int(a.get("owner", -1)) != HUMAN or str(a.get("category", "")) != "unit":
			continue
		var kind := str(a.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if int(a.get("rank", 0)) > 0 and Rules.damage_of(kind) != "":
			var rk := mini(int(a["rank"]), Rules.VETERANCY_PCT.size() - 1)
			ranks[rk] = int(ranks.get(rk, 0)) + 1
		if not (kind in AIR_KINDS):
			grounded.append(a)
	if kinds.is_empty():
		return {}
	var parts: Array = []
	var order: Array = kinds.keys()
	order.sort()
	for k in order:
		parts.append("%d x %s" % [int(kinds[k]), _kind_label(str(k))])
	var out := {"sub": "%s vs Alien %s" % [", ".join(parts), _kind_label(str(foe.get("kind", ""))).to_lower()], "rows": []}
	var rows: Array = out["rows"]
	var armour := Rules.armour_of(str(foe.get("kind", "")), str(foe.get("category", "")))
	for k in order:
		var dmg := Rules.damage_of(str(k))
		if dmg == "" or armour == "":
			continue
		var pct := Rules.multiplier_pct(dmg, armour)
		var label := "%s vs %s" % [Rules.DAMAGE_NAMES[dmg], Rules.ARMOUR_NAMES[armour]]
		if order.size() > 1:
			label = "%s: %s" % [_kind_label(str(k)), label]
		rows.append({"label": label, "value": "normal damage" if pct == 0 else "%s%d%% damage" % ["+" if pct > 0 else "-", absi(pct)], "tone": "good" if pct > 0 else ("bad" if pct < 0 else "dim")})
	var rank_order: Array = ranks.keys()
	rank_order.sort()
	for rk in rank_order:
		var n := int(ranks[rk])
		rows.append({"label": "Veteran rank %d%s" % [rk, ", %d units" % n if n > 1 else ""], "value": "+%d%% damage" % Rules.veterancy_pct(int(rk)), "tone": "good"})
	var under := ground_under(ground_model, grounded)
	if not under.is_empty():
		var spot: Array = under["spot"]
		var here: Dictionary = ground_model.props_at(int(spot[0]), int(spot[1]))
		var name := str(here.get("name", "ground"))
		var pct := int(here.get("infantry_pct", 100)) if int(under["foot"]) >= int(under["wheels"]) else int(here.get("vehicle_pct", 100))
		rows.append({"label": "Standing on %s" % name, "value": _speed_text(pct), "tone": "good" if pct > 100 else ("bad" if pct < 100 else "dim")})
		if int(here.get("range_pct", 0)) > 0:
			rows.append({"label": "Holding %s" % name, "value": "+%d%% range" % int(here["range_pct"]), "tone": "good"})
	var fc := entity_cell(foe)
	var there: Dictionary = ground_model.props_at(int(fc[0]), int(fc[1]))
	var cover := int(there.get("cover_pct", 0))
	rows.append({"label": "Target on %s" % str(there.get("name", "ground")), "value": "-%d%% damage" % cover if cover > 0 else "no cover", "tone": "bad" if cover > 0 else "dim"})
	return out



# ------------------------------------------------------------------ boards 4, 5 and 7 (task 12C)

## Buildings the sim lets the player set a rally point on (earthfront_3d.gd _write_bridge_rally) and that run a queue.
const PRODUCER_KINDS := ["Barracks", "VehicleFactory", "Airfield", "Refinery"]
## The roster draws at most this many unit cards in its row; the rest is a count.
const ROSTER_MAX := 12
## The wave panel shows for the same window as the top bar's wave card (live_adapter.gd _wave_card): 90 s at 30 ticks a second.
const WAVE_PANEL_WINDOW := 2700
## Weapon ranges of the two turrets, in sim distance (stats.rs BuildingKind::stats); test_vm_gameplay_boards457.gd parses
## the Rust source so a rebalance fails a test here instead of drifting.
const GUN_TURRET_RANGE := 5
const AA_TURRET_RANGE := 6
## Control group slots always listed once any group has units (keys 1 to 4, the board's four rows).
const CONTROL_SLOTS := 4
## Every group key the game binds (Keybinds.GROUPS, 1 to 9): slots past CONTROL_SLOTS are listed only while they hold units.
const CONTROL_SLOTS_MAX := 9
## Route arrows are drawn between every this-many route hexes.
const WAVE_ARROW_STEP := 6
## The fortify hint looks this many route hexes back from where the route enters the player's zone for a named crossing.
const WAVE_FORTIFY_LOOKBACK := 4
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const COMPASS_WORDS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
## Region kinds (snapshot `regions`) and the ground names that really belong to them: a route hex counts as crossing a
## region only when its ground matches, because a region is a bounding box and the river's covers most of the map.
const REGION_GROUNDS := {
	"grassland": ["Grassland", "Meadow"], "forest": ["Forest"], "river": ["River", "Ford"], "ford": ["Ford"],
	"flats": ["Dry flats"], "highland": ["Highland"], "sea": ["Sea", "Shore"],
}
const QUIET_REGIONS := ["grassland", "colony", "sea"]


static func _service_of(snap: Dictionary, id: int) -> Dictionary:
	for s in snap.get("services", []):
		if s is Dictionary and int(s.get("id", -1)) == id:
			return s
	return {}


static func _hp_tone(ratio: float) -> String:
	return "bad" if ratio < 0.5 else ("warn" if ratio < 0.75 else "good")


## Hex a pair of 16.16 sim coordinates falls in (same maths as entity_cell).
static func cell_of_bits(x_bits: int, z_bits: int) -> Array:
	return entity_cell({"x_bits": x_bits, "z_bits": z_bits})


## Compass index 0..7 (E, SE, S, SW, W, NW, N, NE) from hex a to hex b; rows grow southward, odd columns sit half a row lower.
static func _compass(a: Array, b: Array) -> int:
	var dx := (int(b[0]) - int(a[0])) * SIM_HEX_X
	var dz := float(int(b[1]) - int(a[1])) + 0.5 * float((int(b[0]) & 1) - (int(a[0]) & 1))
	var sector := roundi(rad_to_deg(atan2(dz, dx)) / 45.0)
	return posmod(sector, 8)


## The snapshot panels only exist with a ground layer (Kestrel), where the HUD draws a kind's own world sprite.
static func _sprite_path(kind: String) -> String:
	var adapter = load("res://scripts/ui/live_adapter.gd")
	var path: String = adapter.icon_path_for_building(kind)
	return path if path != "" else adapter.icon_path_for_unit(kind)


## The name a human building of `kind` shows: numbered (Barracks 2) only when the player has several of that kind, in
## snapshot entity order, as the colony ledger numbers its producers.
static func _structure_name(snap: Dictionary, e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	var total := 0
	var index := 0
	for o in _entities(snap):
		if o is Dictionary and int(o.get("owner", -1)) == HUMAN and str(o.get("category", "")) == "building" and str(o.get("kind", "")) == kind:
			total += 1
			if int(o.get("id", -1)) == int(e.get("id", -2)):
				index = total
	var label := _kind_label(kind)
	return label if total <= 1 else "%s %d" % [label, index]


## The selected structure panel (board 4 and 7): one of the player's own buildings. Everything is read from its entity, its
## service row and the ground under it. Buttons are only those the bridge can carry out: Set rally (producers), Repair, Focus
## building and Demolish (the sim's Sell, refused for the HQ). "Cancel last" is not built, the sim has no cancel command.
## {} for units, alien buildings and unknown ids.
static func structure(snap: Dictionary, ground_model, id: int) -> Dictionary:
	var e := _entity_by_id(snap, id)
	if e.is_empty() or int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "building":
		return {}
	var kind := str(e.get("kind", ""))
	var construction := int(e.get("construction", 0))
	var service := _service_of(snap, id)
	var out := {"id": id, "kind": kind, "name": _structure_name(snap, e), "sprite": _sprite_path(kind)}
	var ratio := 1.0
	var max_hp := float(int(e.get("max_hp_bits", 0))) / 65536.0
	if max_hp > 0.0:
		var now := float(int(e.get("hp_bits", 0))) / 65536.0
		ratio = clampf(now / max_hp, 0.0, 1.0)
		out["hp"] = {"now": roundi(now), "max": roundi(max_hp), "ratio": ratio, "tone": _hp_tone(ratio)}
	var power := float(int(service.get("power", 1000))) / 1000.0 if not service.is_empty() else 1.0
	if construction > 0:
		out["tag"] = {"text": "Under construction", "tone": "cyan"}
	elif ratio < 0.5:
		out["tag"] = {"text": "Critical", "tone": "bad"}
	elif not service.is_empty() and power < 0.5:
		out["tag"] = {"text": "Underpowered", "tone": "warn"}
	elif ratio < 0.75:
		out["tag"] = {"text": "Damaged", "tone": "warn"}
	else:
		out["tag"] = {"text": "Online", "tone": "good"}
	var rows: Array = []
	if construction > 0:
		var done := 1.0 - float(construction) / maxf(1.0, float(int(e.get("construction_total", 1))))
		rows.append({"label": "Construction", "value": "%d%%" % roundi(clampf(done, 0.0, 1.0) * 100.0), "tone": "dim"})
	if not service.is_empty():
		rows.append({"label": "Power", "value": "%d%% supplied" % roundi(power * 100.0), "tone": "good" if power >= 0.95 else "warn"})
	var duration := int(e.get("production_duration", 0))
	var producing := str(e.get("production_name", "")) != "" and duration > 0
	if producing:
		rows.append({"label": "Output", "value": "1 unit / %d s" % _seconds(duration), "tone": ""})
	if kind == "Refinery" and not service.is_empty():
		rows.append({"label": "Ore stored", "value": "%d / %d" % [int(service.get("ore", 0)), int(service.get("ore_capacity", 300))], "tone": ""})
	if int(service.get("stock", 0)) > 0:
		rows.append({"label": "Ammunition stock", "value": "%d rounds" % int(service["stock"]), "tone": ""})
	if bool(service.get("prototype", false)):
		rows.append({"label": "Prototype testing", "value": "Queue paused", "tone": "warn"})
	var producer := kind in PRODUCER_KINDS
	if producer:
		var rally_at := int(e.get("rally_x_bits", -1))
		if rally_at >= 0 and ground_model != null:
			var cell := cell_of_bits(rally_at, int(e.get("rally_z_bits", 0)))
			rows.append({"label": "Rally", "value": str(ground_model.name_at(int(cell[0]), int(cell[1]))), "tone": "good"})
		else:
			rows.append({"label": "Rally", "value": "Not set", "tone": "dim"})
	out["rows"] = rows
	if producer and construction == 0:
		var cells: Array = []
		if producing:
			var left := maxi(0, duration - int(e.get("production_progress", 0)))
			var unit := str(e.get("production_name", ""))
			cells.append({"name": _kind_label(unit), "ratio": clampf(float(int(e.get("production_progress", 0))) / float(duration), 0.0, 1.0), "note": "%d:%02d" % [_seconds(left) / 60, _seconds(left) % 60], "sprite": _sprite_path(unit)})
		out["queue"] = {"cells": cells, "queued": int(e.get("production_queued", 0))}
	elif ground_model != null:
		var cell := entity_cell(e)
		var props: Dictionary = ground_model.props_at(int(cell[0]), int(cell[1]))
		if not props.is_empty():
			var inside := false
			for c in snap.get("construction_zone", []):
				if c is Array and c.size() >= 2 and int(c[0]) == int(cell[0]) and int(c[1]) == int(cell[1]):
					inside = true
					break
			var foot := int(props.get("infantry_pct", 100))
			var wheels := int(props.get("vehicle_pct", 100))
			var cover := int(props.get("cover_pct", 0))
			var trows: Array = [
				{"label": "Movement", "value": "Foot %d%%, vehicles %d%%" % [foot, wheels] if foot + wheels > 0 else "Impassable", "tone": "" if foot + wheels > 0 else "warn"},
				{"label": "Cover", "value": "%d%% less damage taken" % cover if cover > 0 else "None, open ground", "tone": "good" if cover > 0 else "warn"},
			]
			if int(props.get("range_pct", 0)) > 0:
				trows.append({"label": "Range", "value": "+%d%% weapon range" % int(props["range_pct"]), "tone": "good"})
			out["terrain"] = {"glyph": ground_model.glyph_at(int(cell[0]), int(cell[1])), "title": str(props.get("name", "")), "sub": "Tile %d,%d / %s" % [int(cell[0]), int(cell[1]), "your territory" if inside else "outside your territory"], "rows": trows}
	var buttons: Array = []
	if producer and construction == 0:
		buttons.append({"label": "Set rally", "action": "set_rally", "arg": id})
	buttons.append({"label": "Repair", "key": "U", "action": "order", "arg": "repair"})
	buttons.append({"label": "Focus building", "key": "F", "action": "order", "arg": "focus"})
	if kind != "CommandCenter":
		buttons.append({"label": "Demolish", "key": "Del", "action": "order", "arg": "sell", "danger": true})
	buttons[0]["primary"] = true
	out["buttons"] = buttons
	return out


## The card on the left of board 4: what surrounds the selected building. Terrain from the ground table, then the nearest
## Forest and Ford tile as a hex count and compass direction (the board's "Supply range" row has no data and is not built).
## {} for unknown ids or without a ground model.
static func site_card(snap: Dictionary, ground_model, id: int) -> Dictionary:
	var e := _entity_by_id(snap, id)
	if ground_model == null or e.is_empty() or int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "building":
		return {}
	var at := entity_cell(e)
	var rows: Array = [{"label": "Terrain", "value": ground_model.name_at(int(at[0]), int(at[1])), "tone": ""}]
	for pair in [["Forest edge", "Forest"], ["Ford", "Ford"]]:
		var best := 1 << 30
		var spot: Array = []
		for y in ground_model.height:
			for x in ground_model.width:
				if ground_model.name_at(x, y) != str(pair[1]):
					continue
				var d := hex_distance(int(at[0]), int(at[1]), x, y)
				if d > 0 and d < best:
					best = d
					spot = [x, y]
		if spot.is_empty():
			continue
		var value := "%d tile%s %s" % [best, "" if best == 1 else "s", COMPASS[_compass(at, spot)]]
		var cover := int(ground_model.props_at(int(spot[0]), int(spot[1])).get("cover_pct", 0))
		if cover > 0:
			value += ", %d%% cover" % cover
		rows.append({"label": pair[0], "value": value, "tone": ""})
	return {"cap": "%s site" % _structure_name(snap, e), "rows": rows}


## The player's units among `ids`, as the shared "where do they stand" answer: the ground most of the ground units are on,
## a hex that has it, and how many are foot units against wheeled. {} when none are ground units.
static func ground_under(ground_model, units: Array) -> Dictionary:
	var votes := {}
	var stand_at := {}
	var foot := 0
	var wheels := 0
	for u in units:
		var cell := entity_cell(u)
		var glyph: String = ground_model.glyph_at(int(cell[0]), int(cell[1]))
		votes[glyph] = int(votes.get(glyph, 0)) + 1
		if not stand_at.has(glyph):
			stand_at[glyph] = cell
		if str(u.get("kind", "")) in FOOT_KINDS:
			foot += 1
		else:
			wheels += 1
	if votes.is_empty():
		return {}
	var best := ""
	for glyph in votes:
		if best == "" or int(votes[glyph]) > int(votes[best]):
			best = glyph
	return {"spot": stand_at[best], "foot": foot, "wheels": wheels}


## The selection roster (board 5): one card per selected player unit with its real health and rank, capped at ROSTER_MAX.
## `veterans` is the veterans slice ({unit id: rank}). With a ground model it also says what the group stands on and how fast
## it moves there. {} when none of `ids` is a player unit.
static func roster(snap: Dictionary, ground_model, ids: Array, armed: bool, vets: Dictionary) -> Dictionary:
	var units: Array = []
	for id in ids:
		var e := _entity_by_id(snap, int(id))
		if not e.is_empty() and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "unit":
			units.append(e)
	if units.is_empty():
		return {}
	var cards: Array = []
	for e in units:
		var max_hp := float(int(e.get("max_hp_bits", 0))) / 65536.0
		var ratio := clampf(float(int(e.get("hp_bits", 0))) / 65536.0 / max_hp, 0.0, 1.0) if max_hp > 0.0 else 1.0
		var kind := str(e.get("kind", ""))
		cards.append({"id": int(e.get("id", -1)), "kind": kind, "name": _kind_label(kind), "ratio": ratio, "tone": _hp_tone(ratio), "rank": int(vets.get(int(e.get("id", -1)), 0)), "sprite": _sprite_path(kind)})
	var out := {
		"title": str(cards[0]["name"]) if units.size() == 1 else "Strike group",
		"count": "1 unit" if units.size() == 1 else "%d units" % units.size(),
		"armed": armed,
		"cards": cards.slice(0, ROSTER_MAX),
		"more": maxi(0, cards.size() - ROSTER_MAX),
	}
	if ground_model != null:
		var grounded := units.filter(func(u): return not (str(u.get("kind", "")) in AIR_KINDS))
		var under := ground_under(ground_model, grounded)
		if not under.is_empty():
			var spot: Array = under["spot"]
			var here: Dictionary = ground_model.props_at(int(spot[0]), int(spot[1]))
			var pct := int(here.get("infantry_pct", 100)) if int(under["foot"]) >= int(under["wheels"]) else int(here.get("vehicle_pct", 100))
			out["standing"] = str(here.get("name", "ground"))
			out["speed"] = "speed %.1fx" % (float(pct) / 100.0)
			out["speed_tone"] = "good" if pct >= 100 else "warn"
	return out


## The smallest named region whose box and ground kind both fit this route hex ("" when none). `quiet` leaves out regions
## that are not worth a mention (home grassland, the colony, the sea).
static func _region_of(regions: Array, ground_model, x: int, y: int, quiet: bool) -> String:
	var best := ""
	var best_area := 1 << 30
	var ground_name: String = ground_model.name_at(x, y) if ground_model != null else ""
	for r in regions:
		if x < int(r["x0"]) or x > int(r["x1"]) or y < int(r["y0"]) or y > int(r["y1"]):
			continue
		var kind := str(r["kind"])
		if quiet and kind in QUIET_REGIONS:
			continue
		if ground_model != null and REGION_GROUNDS.has(kind) and not (ground_name in REGION_GROUNDS[kind]):
			continue
		var area := (int(r["x1"]) - int(r["x0"]) + 1) * (int(r["y1"]) - int(r["y0"]) + 1)
		if area < best_area:
			best_area = area
			best = str(r["name"])
	return best


## True when the next wave is inside WAVE_PANEL_WINDOW ticks of arriving.
static func wave_in_window(snap: Dictionary) -> bool:
	return snap.has("next_wave_ticks") and int(snap["next_wave_ticks"]) >= 0 and int(snap["next_wave_ticks"]) <= WAVE_PANEL_WINDOW


## The wave panel (board 7, left): the next wave from the snapshot's own fields (timer, size, doctrine, route). It shows
## only inside WAVE_PANEL_WINDOW of the wave arriving. Title: "Fortify <region>" for the named crossing (not home grassland)
## within WAVE_FORTIFY_LOOKBACK hexes before the route enters the player's construction zone ("Fortify tile x,y" for the
## hex before it when none is named), else the doctrine. The board's
## "5 left of 12" and "East bank, 2 prongs" have no data, so no hostile count and no prong count are built.
static func wave_panel(snap: Dictionary, ground_model) -> Dictionary:
	if not wave_in_window(snap):
		return {}
	var seconds := _seconds(int(snap["next_wave_ticks"]))
	var rows: Array = [{"label": "Next wave", "value": "%02d:%02d" % [seconds / 60, seconds % 60], "tone": "warn"}]
	var out := {"cap": "Wave %02d" % (int(snap.get("waves_survived", 0)) + 1), "tag": "Inbound", "title": "", "rows": rows}
	var doctrine := str(snap.get("incoming_doctrine", ""))
	var route: Array = []
	for c in snap.get("wave_route", []):
		if c is Array and c.size() >= 2:
			route.append([int(c[0]), int(c[1])])
	var regions := regions(snap)
	if int(snap.get("next_expedition_size", 0)) > 0:
		rows.append({"label": "Expected", "value": "%d units" % int(snap["next_expedition_size"]), "tone": ""})
	if doctrine != "":
		rows.append({"label": "Doctrine", "value": doctrine, "tone": ""})
	out["title"] = doctrine
	if route.size() >= 2:
		var home: Array = route[route.size() - 1]
		rows.append({"label": "Direction", "value": "From the %s" % COMPASS_WORDS[_compass(home, route[0])], "tone": ""})
		var crossed: Array = []
		for hex in route:
			var name := _region_of(regions, ground_model, int(hex[0]), int(hex[1]), true)
			if name != "" and not (name in crossed):
				crossed.append(name)
		if not crossed.is_empty():
			rows.append({"label": "Crosses", "value": ", ".join(crossed), "tone": "warn"})
		var zone := {}
		for c in snap.get("construction_zone", []):
			if c is Array and c.size() >= 2:
				zone[Vector2i(int(c[0]), int(c[1]))] = true
		for i in range(1, route.size()):
			if zone.has(Vector2i(int(route[i][0]), int(route[i][1]))):
				var before: Array = route[i - 1]
				if not zone.has(Vector2i(int(before[0]), int(before[1]))):
					# The nearest named crossing just before the zone (the ford the wave wades), else the tile itself.
					var region := ""
					for k in range(i - 1, maxi(i - 1 - WAVE_FORTIFY_LOOKBACK, -1), -1):
						region = _region_of(regions, ground_model, int(route[k][0]), int(route[k][1]), true)
						if region != "":
							break
					out["title"] = "Fortify %s" % region if region != "" else "Fortify tile %d,%d" % [int(before[0]), int(before[1])]
				break
	if fogged(snap):
		# under fog the player knows the relays exist (briefing intel), not how many are powered
		if int(snap.get("alien_relays", 0)) > 0:
			rows.append({"label": "Relays", "value": "%d known" % int(snap["alien_relays"]), "tone": "warn"})
	elif int(snap.get("active_alien_relays", 0)) > 0:
		rows.append({"label": "Relays", "value": "%d operating" % int(snap["active_alien_relays"]), "tone": "warn"})
	return out


## The control group list (board 5, left). `groups` is [{n, kinds: [kind names of the live units]}]; slots 1 to 4 are
## always listed once any has units (an unassigned one reads "empty"), slots 5 to 9 only while they hold units, so the
## panel keeps the board's shape until a high group is used. `active` is the slot whose units are selected (or -1).
## {} when no slot has units.
static func control_groups(groups: Array, active: int) -> Dictionary:
	var any := false
	var slots: Array = []
	for n in range(1, CONTROL_SLOTS_MAX + 1):
		var kinds: Array = []
		for g in groups:
			if int(g.get("n", 0)) == n:
				kinds = g.get("kinds", [])
		var label := ""
		if not kinds.is_empty():
			any = true
			var counts := {}
			for k in kinds:
				counts[str(k)] = int(counts.get(str(k), 0)) + 1
			var best := ""
			for k in counts:
				if best == "" or int(counts[k]) > int(counts[best]) or (int(counts[k]) == int(counts[best]) and k < best):
					best = k
			label = _kind_label(best)
		if n <= CONTROL_SLOTS or not kinds.is_empty():
			slots.append({"n": n, "count": kinds.size(), "label": label, "on": n == active and not kinds.is_empty()})
	return {"slots": slots} if any else {}


## World overlay data (hex space, projected by the adapter): the line from a producer to its rally point.
static func rally_hexes(snap: Dictionary, id: int) -> Dictionary:
	var e := _entity_by_id(snap, id)
	if e.is_empty() or int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "building" or int(e.get("rally_x_bits", -1)) < 0:
		return {}
	return {"from": entity_cell(e), "to": cell_of_bits(int(e.get("rally_x_bits", 0)), int(e.get("rally_z_bits", 0)))}


## World overlay data: the expected wave route as segments between every WAVE_ARROW_STEP-th hex, in travel order (alien end
## first, home last). [] without a route.
static func wave_arrows(snap: Dictionary) -> Array:
	var route: Array = []
	for c in snap.get("wave_route", []):
		if c is Array and c.size() >= 2:
			route.append([int(c[0]), int(c[1])])
	var out: Array = []
	if route.size() < 2:
		return out
	var i := 0
	while i < route.size() - 1:
		var j := mini(i + WAVE_ARROW_STEP, route.size() - 1)
		out.append({"from": route[i], "to": route[j]})
		i = j
	return out


## A turret's weapon range as the sim applies it: the base range extended by the range_pct of the ground it stands on
## (Highland +25%). `ground_model` may be null (no ground layer): the base range.
static func effective_turret_range(field: Dictionary, ground_model) -> float:
	var pct := 0
	if ground_model != null:
		var cell: Array = field["cell"]
		pct = int(ground_model.props_at(int(cell[0]), int(cell[1])).get("range_pct", 0))
	return float(field["range"]) * float(100 + pct) / 100.0


## World overlay data: the player's finished turrets with the sim's weapon range.
static func turret_fields(snap: Dictionary) -> Array:
	var out: Array = []
	for e in _entities(snap):
		if not (e is Dictionary) or int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "building" or int(e.get("construction", 0)) != 0:
			continue
		var kind := str(e.get("kind", ""))
		if kind == "GunTurret":
			out.append({"id": int(e.get("id", -1)), "cell": entity_cell(e), "range": GUN_TURRET_RANGE, "kind": kind})
		elif kind == "AaTurret":
			out.append({"id": int(e.get("id", -1)), "cell": entity_cell(e), "range": AA_TURRET_RANGE, "kind": kind})
	return out
