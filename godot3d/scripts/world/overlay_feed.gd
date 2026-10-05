extends RefCounted
## The Logistics lenses (board 8) as world marks, computed from one bridge snapshot. Pure functions: nothing here touches
## the scene, and every lens answers [] when the snapshot lacks the data it needs (no fake zeros, no invented routes).
##
## `marks(snap, lens)` returns HEX-SPACE marks (cells, not pixels), once per snapshot:
##   link     cell to_cell tone(ok|warn|bad) broken load from_id to_id    power line, source to consumer
##   ring     cell r tone [dashed]                                       r is in sim units (one row = 1.0)
##   badge    cell text                                                  small pill above a building
##   border   edges [[cell, outside cell], ...] tone(own|enemy)          the hex sides between two territories
##   callout  cell title [sub border]                                    glass label
## `project(marks, projector)` turns them into world_marks.gd's own schema (screen pixels), every frame.
##
## Lenses and the data behind each (the bridge snapshot is the only source):
##   power     services[].power per building id (0..1000) and the entity kinds. Tier order is the sim's, mirrored in TIER.
##   borders   construction_zone (player) and vm_gameplay.enemy_border (alien structures, or the core node).
##   coverage  human turret entities, stats.rs ranges (vm_gameplay), and ground_table range_pct under the turret.
##   yield     Refinery ore_bonus flag, PowerPlant river_kw.
##   supply    supply_links [{depot, target, state ok|severed}] (bridge, additive): the sim's own supply_route verdict per
##             depot-to-building pair, refreshed on the sim's 30-tick supply beat. Absent or empty: no lens, never faked.
const VM = preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel = preload("res://scripts/terrain/ground_model.gd")
const WorldMarks = preload("res://scripts/ui/world_marks.gd")

const HUMAN := 0
## Every lens the Logistics tab knows, in button order. The buttons shown are `available(snap)`.
const LENSES := ["power", "supply", "borders", "coverage", "yield"]
const LABELS := {"power": "Power", "supply": "Supply", "borders": "Borders", "coverage": "Coverage", "yield": "Yield"}
const FULL := 1000
## The sim's working threshold: under 500 of 1000 a building does not run (earthfront.rs, power_fraction < 500).
const BROKEN_BELOW := 500
## Power allocation tiers (earthfront.rs run_earthfront_services): defence 0, extraction 1, industry 2, science 3. Only the
## kinds that draw power are listed (operating_demand). test_overlay_feed.gd checks these against the source.
const TIER := {"GunTurret": 0, "AaTurret": 0, "SupplyDepot": 0, "Refinery": 1, "Barracks": 2, "VehicleFactory": 2, "Airfield": 2, "ResearchLab": 3}
## Kinds that put power on the grid (generation_for: PowerPlant 80/96 kW, CommandCenter 10 kW; a Battery discharges).
const SOURCES := ["PowerPlant", "Battery", "CommandCenter"]
## Depot supply reach in tiles without and with Field Supply Networks (earthfront.rs supply_radius; test_overlay_feed checks it).
const SUPPLY_RADIUS := 5
const SUPPLY_RADIUS_TECH := 7
## Supply lines are thinner than power lines (px).
const SUPPLY_WIDTH := 3.0
## Line weight (px) at 0 and 1000 delivered: the mock's "weight = load".
const WIDTH_MIN := 2.0
const WIDTH_SPAN := 4.0
const BADGE_LIFT := 40.0
const CALLOUT_LIFT := 56.0


# ------------------------------------------------------------------ availability

## True when the snapshot is an Earthfront one (it carries the ground layer): the Logistics tab shows.
static func tab_available(snap: Dictionary) -> bool:
	return str(snap.get("ground", "")) != ""


## The lenses this snapshot can really back, in button order. `supply` needs at least one real link in supply_links.
static func available(snap: Dictionary) -> Array:
	var out: Array = []
	if snap.get("services") is Array:
		out.append("power")
	var links = snap.get("supply_links")
	if links is Array and not links.is_empty():
		out.append("supply")
	var zone = snap.get("construction_zone")
	if zone is Array and not zone.is_empty():
		out.append("borders")
	var table = snap.get("ground_table")
	if table is Array and not table.is_empty():
		out.append("coverage")
	if snap.get("entities") is Array:
		out.append("yield")
	return out


# ------------------------------------------------------------------ marks (hex space)

static func marks(snap: Dictionary, lens: String) -> Array:
	match lens:
		"power": return _power(snap)
		"supply": return _supply(snap)
		"borders": return _borders(snap)
		"coverage": return _coverage(snap)
		"yield": return _yield(snap)
	return []


static func _entities(snap: Dictionary) -> Array:
	var list = snap.get("entities", [])
	return list if list is Array else []


static func _own_building(e: Variant) -> bool:
	return e is Dictionary and int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "building"


## Links from each consumer back to the nearest plant or battery. The sim shares one grid and serves it tier by tier, so
## which source feeds which building is not exposed; "nearest source" is a documented presentation choice. Links are
## emitted in tier order (defence, refinery, factories, lab), ids ascending inside a tier. A consumer with no services row
## has no delivered power to show and is skipped.
static func _power(snap: Dictionary) -> Array:
	var delivered := {}
	for s in snap.get("services", []):
		if s is Dictionary and s.has("power"):
			delivered[int(s.get("id", -1))] = int(s["power"])
	var sources: Array = []
	var consumers: Array = []
	for e in _entities(snap):
		if not _own_building(e):
			continue
		var kind := str(e.get("kind", ""))
		if kind in SOURCES:
			if int(e.get("construction", 0)) == 0:
				sources.append({"id": int(e.get("id", -1)), "cell": VM.entity_cell(e)})
		elif TIER.has(kind) and delivered.has(int(e.get("id", -1))):
			consumers.append({"id": int(e.get("id", -1)), "cell": VM.entity_cell(e), "tier": int(TIER[kind]), "power": int(delivered[int(e.get("id", -1))])})
	if sources.is_empty() or consumers.is_empty():
		return []
	consumers.sort_custom(func(a, b): return a["tier"] < b["tier"] or (a["tier"] == b["tier"] and a["id"] < b["id"]))
	var out: Array = []
	for c in consumers:
		var best: Dictionary = {}
		var best_d := 1 << 30
		for s in sources:
			var d := VM.hex_distance(int(s["cell"][0]), int(s["cell"][1]), int(c["cell"][0]), int(c["cell"][1]))
			if d < best_d or (d == best_d and int(s["id"]) < int(best["id"])):
				best = s
				best_d = d
		var power := int(c["power"])
		var broken := power < BROKEN_BELOW
		out.append({
			"kind": "link", "cell": best["cell"], "to_cell": c["cell"], "from_id": best["id"], "to_id": c["id"],
			"tone": "bad" if broken else ("warn" if power < FULL else "ok"), "broken": broken, "load": power,
		})
	return out


## One link per supply_links entry, depot to building: cyan when the sim's route holds, red dotted when a wall or terrain
## cuts it. Entries naming an entity the snapshot does not hold, or a state other than ok or severed, are skipped (no guessing).
static func _supply(snap: Dictionary) -> Array:
	var links = snap.get("supply_links")
	if not (links is Array) or links.is_empty():
		return []
	var by_id := _own_buildings_by_id(snap)
	var out: Array = []
	for l in links:
		if not (l is Dictionary):
			continue
		var state := str(l.get("state", ""))
		if state != "ok" and state != "severed":
			continue
		var depot = by_id.get(int(l.get("depot", -1)))
		var target = by_id.get(int(l.get("target", -1)))
		if depot == null or target == null:
			continue
		var severed := state == "severed"
		out.append({
			"kind": "link", "cell": VM.entity_cell(depot), "to_cell": VM.entity_cell(target), "from_id": int(depot["id"]), "to_id": int(target["id"]),
			"tone": "bad" if severed else "ok", "broken": severed, "load": FULL, "width": SUPPLY_WIDTH,
		})
	return out


static func _own_buildings_by_id(snap: Dictionary) -> Dictionary:
	var by_id := {}
	for e in _entities(snap):
		if _own_building(e):
			by_id[int(e.get("id", -1))] = e
	return by_id


## The deck's supply list, one row per depot that has links, from the same supply_links as the map lines: {name, detail,
## tone good|bad, tag, supplied, severed}. Cut depots first, then by id. The board's route names and ETAs are not data.
static func routes(snap: Dictionary) -> Array:
	var counts := {}
	var order: Array = []
	for m in _supply(snap):
		var id := int(m["from_id"])
		if not counts.has(id):
			counts[id] = {"supplied": 0, "severed": 0, "cell": m["cell"]}
			order.append(id)
		counts[id]["severed" if bool(m["broken"]) else "supplied"] += 1
	var by_id := _own_buildings_by_id(snap)
	var rows: Array = []
	for id in order:
		var c: Dictionary = counts[id]
		var cut := int(c["severed"]) > 0
		var detail := "%d supplied" % int(c["supplied"])
		if cut:
			detail += ", %d severed" % int(c["severed"])
		rows.append({
			"id": id, "name": "%s at %d, %d" % [VM.kind_label(str(by_id[id].get("kind", ""))), int(c["cell"][0]), int(c["cell"][1])],
			"detail": detail, "tone": "bad" if cut else "good", "tag": "Cut" if cut else "OK",
			"supplied": int(c["supplied"]), "severed": int(c["severed"]),
		})
	rows.sort_custom(func(a, b): return (int(a["severed"]) > 0) > (int(b["severed"]) > 0) or ((int(a["severed"]) > 0) == (int(b["severed"]) > 0) and int(a["id"]) < int(b["id"])))
	return rows


static func _coverage(snap: Dictionary) -> Array:
	var fields := VM.turret_fields(snap)
	if fields.is_empty():
		return []
	var ground = GroundModel.from_snapshot(snap)
	var out: Array = []
	for f in fields:
		var cell: Array = f["cell"]
		var pct := 0
		if ground != null:
			pct = int(ground.props_at(int(cell[0]), int(cell[1])).get("range_pct", 0))
		out.append({"kind": "ring", "cell": cell, "r": float(f["range"]) * float(100 + pct) / 100.0, "dashed": true, "tone": "good" if f["kind"] == "AaTurret" else "cyan"})
		if pct > 0:
			out.append({"kind": "badge", "cell": cell, "text": "+%d%%" % pct})
	return out


static func _yield(snap: Dictionary) -> Array:
	var out: Array = []
	for e in _entities(snap):
		if not _own_building(e):
			continue
		match str(e.get("kind", "")):
			"Refinery":
				out.append({"kind": "ring", "cell": VM.entity_cell(e), "r": float(VM.ORE_BONUS_RADIUS), "dashed": true, "tone": "cyan"})
				if bool(e.get("ore_bonus", false)):
					out.append({"kind": "badge", "cell": VM.entity_cell(e), "text": "+%d%%" % VM.ORE_BONUS_PCT})
			"PowerPlant":
				if int(e.get("river_kw", 0)) > 0:
					out.append({"kind": "badge", "cell": VM.entity_cell(e), "text": "river +%d" % int(e["river_kw"])})
	return out


static func _borders(snap: Dictionary) -> Array:
	var width := int(snap.get("map_width", 0))
	var height := int(snap.get("map_height", 0))
	var out: Array = []
	var zone: Array = []
	for c in snap.get("construction_zone", []):
		if c is Array and c.size() >= 2:
			zone.append([int(c[0]), int(c[1])])
	var own := _edges(zone, width, height)
	if not own.is_empty():
		out.append({"kind": "border", "tone": "own", "edges": own})
	var enemy := VM.enemy_border(snap)
	var theirs := _edges(enemy, width, height)
	if not theirs.is_empty():
		out.append({"kind": "border", "tone": "enemy", "edges": theirs})
		out.append({"kind": "callout", "cell": _centre_cell(enemy), "title": "Enemy territory", "sub": "", "border": "bad"})
	return out


## The hex sides between a cell of `cells` and an in-map neighbour outside it, as [cell, neighbour] pairs.
static func _edges(cells: Array, width: int, height: int) -> Array:
	var inside := {}
	for c in cells:
		inside[Vector2i(int(c[0]), int(c[1]))] = true
	var out: Array = []
	for c in cells:
		var x := int(c[0])
		var y := int(c[1])
		for n in neighbours(x, y):
			if inside.has(Vector2i(n[0], n[1])):
				continue
			if n[0] < 0 or n[1] < 0 or (width > 0 and n[0] >= width) or (height > 0 and n[1] >= height):
				continue
			out.append([[x, y], [n[0], n[1]]])
	return out


## The six neighbours of an odd-q offset cell (odd columns sit half a row lower, as in vm_gameplay.hex_distance).
static func neighbours(x: int, y: int) -> Array:
	if x % 2 == 0:
		return [[x, y - 1], [x, y + 1], [x - 1, y - 1], [x - 1, y], [x + 1, y - 1], [x + 1, y]]
	return [[x, y - 1], [x, y + 1], [x - 1, y], [x - 1, y + 1], [x + 1, y], [x + 1, y + 1]]


## The cell of `cells` nearest their average, so a label sits on the territory it names.
static func _centre_cell(cells: Array) -> Array:
	var sx := 0.0
	var sy := 0.0
	for c in cells:
		sx += float(c[0])
		sy += float(c[1])
	sx /= float(cells.size())
	sy /= float(cells.size())
	var best: Array = cells[0]
	var best_d := INF
	for c in cells:
		var d := (float(c[0]) - sx) * (float(c[0]) - sx) + (float(c[1]) - sy) * (float(c[1]) - sy)
		if d < best_d:
			best_d = d
			best = c
	return [int(best[0]), int(best[1])]


# ------------------------------------------------------------------ projection (screen space)

## world_marks.gd's schema from hex-space marks. `project` is Callable(col, row) -> screen Vector2, Vector2.INF when behind
## the camera. A mark with any needed point behind the camera is dropped. Ring radii are scaled from the screen size of
## three sim units east and south of the centre (columns are 0.75 apart, rows 1.0).
static func project(hex_marks: Array, project: Callable) -> Array:
	var cache := {}
	var at := func(cell: Array) -> Vector2:
		var key := Vector2i(int(cell[0]), int(cell[1]))
		if not cache.has(key):
			cache[key] = project.call(key.x, key.y)
		return cache[key]
	var out: Array = []
	for m in hex_marks:
		match str(m.get("kind", "")):
			"link":
				var a: Vector2 = at.call(m["cell"])
				var b: Vector2 = at.call(m["to_cell"])
				if a == Vector2.INF or b == Vector2.INF:
					continue
				var load_ratio := clampf(float(m.get("load", FULL)) / float(FULL), 0.0, 1.0)
				out.append({"kind": "link", "x": a.x, "y": a.y, "c1": a.lerp(b, 1.0 / 3.0), "c2": a.lerp(b, 2.0 / 3.0), "to": b,
					"tone": m.get("tone", "ok"), "broken": bool(m.get("broken", false)), "width": float(m.get("width", WIDTH_MIN + WIDTH_SPAN * load_ratio))})
			"ring":
				var cell: Array = m["cell"]
				var c: Vector2 = at.call(cell)
				var east: Vector2 = at.call([int(cell[0]) + 4, int(cell[1])])
				var south: Vector2 = at.call([int(cell[0]), int(cell[1]) + 3])
				if c == Vector2.INF or east == Vector2.INF or south == Vector2.INF:
					continue
				var r := float(m.get("r", 1.0))
				out.append({"kind": "ring", "x": c.x, "y": c.y, "rx": r * absf(east.x - c.x) / 3.0, "ry": r * absf(south.y - c.y) / 3.0,
					"dashed": bool(m.get("dashed", false)), "tone": m.get("tone", "cyan")})
			"badge":
				var p: Vector2 = at.call(m["cell"])
				if p == Vector2.INF:
					continue
				var text := str(m.get("text", ""))
				var size := WorldMarks.badge_size(text)
				out.append({"kind": "badge", "x": roundf(p.x - size.x * 0.5), "y": roundf(p.y - BADGE_LIFT), "text": text})
			"border":
				var segs: Array = []
				for e in m.get("edges", []):
					var a2: Vector2 = at.call(e[0])
					var b2: Vector2 = at.call(e[1])
					if a2 == Vector2.INF or b2 == Vector2.INF:
						continue
					# The shared side is perpendicular to the line joining the two centres, one hex side long
					# (centre distance = sqrt(3) sides), centred halfway.
					var mid := (a2 + b2) * 0.5
					var d := b2 - a2
					var half := Vector2(-d.y, d.x) / (2.0 * sqrt(3.0))
					segs.append([mid + half, mid - half])
				if not segs.is_empty():
					out.append({"kind": "border", "tone": m.get("tone", "own"), "segs": segs})
			"callout":
				var q: Vector2 = at.call(m["cell"])
				if q == Vector2.INF:
					continue
				var label: Dictionary = m.duplicate()
				label.erase("cell")
				label["x"] = q.x
				label["y"] = q.y - CALLOUT_LIFT
				label["tx"] = q.x
				label["ty"] = q.y
				out.append(label)
	return out


# ------------------------------------------------------------------ text for the Logistics tab

## One line of what the active lens is drawing, from the marks. "" when it draws nothing.
static func summary(snap: Dictionary, lens: String, drawn: Array) -> String:
	if drawn.is_empty():
		return ""
	match lens:
		"power":
			var links := 0
			var broken := 0
			for m in drawn:
				if m["kind"] == "link":
					links += 1
					broken += 1 if bool(m.get("broken", false)) else 0
			return "%d links, %d broken" % [links, broken]
		"supply":
			var cut := 0
			for m in drawn:
				cut += 1 if m["kind"] == "link" and bool(m.get("broken", false)) else 0
			return "%d supplied, %d severed" % [drawn.size() - cut, cut]
		"coverage":
			var rings := drawn.filter(func(m): return m["kind"] == "ring").size()
			return "%d turret field%s" % [rings, "" if rings == 1 else "s"]
		"yield":
			var refineries := drawn.filter(func(m): return m["kind"] == "ring").size()
			var bonus := drawn.filter(func(m): return m["kind"] == "badge" and str(m["text"]).begins_with("+")).size()
			var river := drawn.filter(func(m): return m["kind"] == "badge" and str(m["text"]).begins_with("river")).size()
			var parts: Array = []
			if refineries > 0:
				parts.append("%d refinery ring%s, %d with ore bonus" % [refineries, "" if refineries == 1 else "s", bonus])
			if river > 0:
				parts.append("%d river plant%s" % [river, "" if river == 1 else "s"])
			return ", ".join(parts)
		"borders":
			var zone = snap.get("construction_zone", [])
			var parts2: Array = []
			if zone is Array and not zone.is_empty():
				parts2.append("Your zone %d tiles" % zone.size())
			var enemy := VM.enemy_border(snap)
			if not enemy.is_empty():
				parts2.append("enemy %d tiles" % enemy.size())
			return ", ".join(parts2)
	return ""


## Legend rows for a lens: {tone, style (solid|dashed|dotted), text}. Numbers come from the sim thresholds and the
## snapshot's ground_table, never literals.
static func legend(snap: Dictionary, lens: String) -> Array:
	match lens:
		"power":
			return [
				{"tone": "ok", "style": "solid", "text": "Powered, full delivery"},
				{"tone": "warn", "style": "solid", "text": "Throttled, under %d of %d" % [FULL, FULL]},
				{"tone": "bad", "style": "dotted", "text": "Not running, under %d of %d" % [BROKEN_BELOW, FULL]},
			]
		"supply":
			return [
				{"tone": "ok", "style": "solid", "text": "Supplied, within %d tiles (%d with Field Supply Networks)" % [SUPPLY_RADIUS, SUPPLY_RADIUS_TECH]},
				{"tone": "bad", "style": "dotted", "text": "Severed, in reach but a wall or terrain cuts the route"},
			]
		"borders":
			return [
				{"tone": "own", "style": "solid", "text": "Your construction zone"},
				{"tone": "enemy", "style": "solid", "text": "Enemy territory"},
			]
		"coverage":
			var rows: Array = [
				{"tone": "cyan", "style": "dashed", "text": "Gun turret range"},
				{"tone": "good", "style": "dashed", "text": "Anti-air turret range"},
			]
			for row in snap.get("ground_table", []):
				if row is Dictionary and int(row.get("range_pct", 0)) > 0:
					rows.append({"tone": "cyan", "style": "badge", "text": "%s adds %d%% range" % [str(row.get("name", "")), int(row["range_pct"])]})
			return rows
		"yield":
			return [
				{"tone": "cyan", "style": "dashed", "text": "Refinery ore reach, %d hex" % VM.ORE_BONUS_RADIUS},
				{"tone": "cyan", "style": "badge", "text": "+%d%% ore bonus, ore within reach" % VM.ORE_BONUS_PCT},
				{"tone": "cyan", "style": "badge", "text": "River cooling, kW added to a reactor"},
			]
	return []


## One sentence about what the lens means, for the tab's note line. "" for an unknown lens.
static func note(lens: String) -> String:
	match lens:
		"power":
			return "Lines run to the nearest reactor, battery or Command Center for display only; the grid is shared and served defence first, then refineries, factories and the lab."
		"supply":
			return "Each line joins a powered, stocked depot to a building it feeds. Lines show reach, not ammunition in flight."
		"borders":
			return "Cyan marks where you may build; red is where alien structures hold ground."
		"coverage":
			return "Rings show where each finished turret can hit, at its real range."
		"yield":
			return "Badges appear only where the sim reports a bonus."
	return ""


## What to say when the active lens has nothing to draw (instead of showing a zero).
static func empty_text(lens: String) -> String:
	match lens:
		"power":
			return "Nothing to link yet: needs a finished reactor or battery and a building that draws power."
		"supply":
			return "No powered depot with stock has a building in reach yet."
		"borders":
			return "No territory to outline."
		"coverage":
			return "No finished turret yet."
		"yield":
			return "No refinery or river-side reactor yet."
	return ""
