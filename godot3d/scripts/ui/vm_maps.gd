extends RefCounted
## View-model slices for the three map and codex screens (boards 6, 11 and 12), computed from one bridge snapshot and its
## GroundModel. Same rule as vm_gameplay.gd: every function answers {} when the data it needs is absent, so a screen builds
## nothing, and no number here is invented: counts come from the ground layer and the snapshot rows, bonuses from the
## constants vm_gameplay mirrors from the sim.
const VM = preload("res://scripts/ui/vm_gameplay.gd")
const Feed = preload("res://scripts/world/overlay_feed.gd")

## Label anchors tried per region, nearest to the region's own centre first.
const LABEL_CANDIDATES := 14
const HUMAN := 0
## The briefing shows for the first objective group only ("Establish a supplied base": tutorial stages 0 to 2).
const BRIEFING_LAST_STAGE := 2


static func _thousands(n: int) -> String:
	return load("res://scripts/ui/live_screens.gd").thousands(n)


# ------------------------------------------------------------------ board 11: strategic map

## The strategic map: the whole ground layer plus what the snapshot knows of borders, the expected wave route, deposits and
## the alien structures. {} without a ground layer or without named regions.
static func region_map(snap: Dictionary, ground) -> Dictionary:
	if ground == null:
		return {}
	var regions := VM.regions(snap)
	if regions.is_empty():
		return {}
	var out := {
		"name": str(snap.get("map_name", "")),
		"width": ground.width,
		"height": ground.height,
		"ground": str(snap.get("ground", "")),
		"composition": composition(ground),
		"labels": label_candidates(regions, ground),
	}
	if snap.has("era"):
		out["sub"] = "Era %02d" % (int(snap["era"]) + 1)
	var zone = snap.get("construction_zone", [])
	var cells: Array = []
	if zone is Array:
		for c in zone:
			if c is Array and c.size() >= 2:
				cells.append([int(c[0]), int(c[1])])
	out["tiles"] = cells.size()
	out["zone"] = cells
	out["enemy"] = VM.enemy_border(snap)
	var hostile: Array = []
	var own_cc: Array = []
	var known := false
	for e in snap.get("entities", []):
		if not (e is Dictionary):
			continue
		known = true
		if str(e.get("category", "")) != "building":
			continue
		if int(e.get("owner", HUMAN)) != HUMAN:
			hostile.append({"cell": VM.entity_cell(e), "kind": VM.kind_label(str(e.get("kind", "")))})
		elif str(e.get("kind", "")) == "CommandCenter":
			own_cc.append(VM.entity_cell(e))
	if known:
		out["hostile"] = hostile
	if not own_cc.is_empty():
		out["own_cc"] = own_cc
	out["borders"] = Feed.marks(snap, "borders")
	var route := VM.wave_inbound(snap)
	if not route.is_empty():
		out["route"] = route
	var pins := VM.deposit_pins(snap)
	for pin in pins:
		pin["cell"] = [pin["x"], pin["y"]]
	if not pins.is_empty():
		out["pins"] = pins
	return out


## Ground composition over the whole map: [{glyph, name, pct, count}], largest first. Percentages use the largest-remainder
## method so they total exactly 100 (the same rule as the territory card).
static func composition(ground) -> Dictionary:
	var cells: Array = []
	for y in ground.height:
		for x in ground.width:
			cells.append([x, y])
	var counts: Dictionary = ground.counts_in(cells)
	var total := cells.size()
	if total == 0:
		return {"rows": []}
	var rows: Array = []
	var assigned := 0
	for glyph in counts:
		var exact := 100.0 * float(counts[glyph]) / float(total)
		var base := int(floor(exact))
		assigned += base
		var name := ""
		for c in cells:
			if ground.glyph_at(int(c[0]), int(c[1])) == glyph:
				name = ground.name_at(int(c[0]), int(c[1]))
				break
		rows.append({"glyph": glyph, "name": name, "pct": base, "count": int(counts[glyph]), "rem": exact - base})
	var by_remainder := rows.duplicate()
	by_remainder.sort_custom(func(a, b): return a["rem"] > b["rem"] or (a["rem"] == b["rem"] and a["glyph"] < b["glyph"]))
	for i in 100 - assigned:
		by_remainder[i % by_remainder.size()]["pct"] += 1
	rows.sort_custom(func(a, b): return a["count"] > b["count"] or (a["count"] == b["count"] and a["glyph"] < b["glyph"]))
	var list: Array = []
	for row in rows:
		list.append({"glyph": row["glyph"], "name": row["name"], "pct": row["pct"], "count": row["count"]})
	return {"rows": list, "total": total}


## Where a region's name can sit: cells of its box whose ground belongs to it (a region is a bounding box, so the river's covers
## most of the map), nearest to the box centre first. A region with no ground kind (the colony) takes its box centre.
## [{name, kind, cands: [[x, y]]}], smallest box first so the specific regions claim their spot before the large ones.
static func label_candidates(regions: Array, ground) -> Array:
	var out: Array = []
	for r in regions:
		var cx := (float(r["x0"]) + float(r["x1"])) * 0.5
		var cy := (float(r["y0"]) + float(r["y1"])) * 0.5
		var names: Array = VM.REGION_GROUNDS.get(str(r["kind"]), [])
		var cells: Array = []
		for y in range(maxi(0, int(r["y0"])), mini(ground.height, int(r["y1"]) + 1)):
			for x in range(maxi(0, int(r["x0"])), mini(ground.width, int(r["x1"]) + 1)):
				if names.is_empty() or names.has(ground.name_at(x, y)):
					cells.append([x, y])
		if cells.is_empty():
			cells.append([roundi(cx), roundi(cy)])
		# Nearest to the centre of the ground the region really covers, so a diagonal river is labelled on the river.
		var mx := 0.0
		var my := 0.0
		for c in cells:
			mx += float(c[0])
			my += float(c[1])
		mx /= float(cells.size())
		my /= float(cells.size())
		cells.sort_custom(func(a, b):
			var da := (float(a[0]) - mx) * (float(a[0]) - mx) + (float(a[1]) - my) * (float(a[1]) - my)
			var db := (float(b[0]) - mx) * (float(b[0]) - mx) + (float(b[1]) - my) * (float(b[1]) - my)
			return da < db or (da == db and (a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))))
		out.append({"name": r["name"], "kind": r["kind"], "cands": cells.slice(0, LABEL_CANDIDATES), "area": (int(r["x1"]) - int(r["x0"]) + 1) * (int(r["y1"]) - int(r["y0"]) + 1)})
	out.sort_custom(func(a, b): return a["area"] < b["area"])
	return out


# ------------------------------------------------------------------ board 12: terrain guide

## One note per ground glyph, in words only: every number on a card comes from its ground_table row.
const NOTES := {
	"g": "The default ground.",
	"m": "Behaves like grassland, with a little shelter.",
	"f": "Open and quick to cross, for you and for the enemy.",
	"h": "Height extends weapon reach, but the climb is slow.",
	"t": "Infantry shelter here. Wheels and tracks slow down.",
	"r": "Ground units cannot cross.",
	"w": "Ground units can wade through here, at a cost.",
	"s": "Soft sand along the water's edge.",
	"o": "Open water. Ground units cannot enter.",
	"c": "Left by earlier landings. Good cover, awkward to build on.",
}
const NOTE_ORE := "A refinery beside a deposit raises its haul. Claim it early."
const NOTE_ALLOY := "Scenery only in this operation: nothing you can build extracts it."


## The terrain guide: a card per ground_table row, then Ore and Alloy when the snapshot has such deposits, plus the rules of
## thumb. {} without a ground table. `ground` (GroundModel) is optional: without it the cards carry no tile counts or places.
static func terrain_guide(snap: Dictionary, ground) -> Dictionary:
	var table = snap.get("ground_table", [])
	if not (table is Array) or table.is_empty():
		return {}
	var rows: Array = []
	for row in table:
		if row is Dictionary and str(row.get("name", "")) != "":
			rows.append(row)
	if rows.is_empty():
		return {}
	var regions := VM.regions(snap)
	var cards: Array = []
	for row in rows:
		cards.append(_ground_card(row, regions, ground))
	var deposits = snap.get("deposits", [])
	if deposits is Array:
		var ore := _deposit_card(snap, ground, "Ore")
		if not ore.is_empty():
			cards.append(ore)
		var alloy := _deposit_card(snap, ground, "Alloy")
		if not alloy.is_empty():
			cards.append(alloy)
	var out := {"title": "Terrain guide", "cap": "Codex", "cards": cards, "rules": rules(rows, regions),
		"sub": "The land your colony stands on. Hover any tile in the field for the same numbers."}
	if str(snap.get("map_name", "")) != "":
		out["cap"] = "Codex / %s" % str(snap["map_name"])
	return out


static func _movement(row: Dictionary) -> Array:
	if not bool(row.get("passable", true)) or (int(row.get("infantry_pct", 0)) <= 0 and int(row.get("vehicle_pct", 0)) <= 0):
		return ["Blocked", "bad"]
	var foot := int(row.get("infantry_pct", 100))
	var wheels := int(row.get("vehicle_pct", 100))
	if foot == wheels:
		return ["%d%%" % foot, ""]
	return ["Foot %d%%, vehicles %d%%" % [foot, wheels], ""]


static func _ground_card(row: Dictionary, regions: Array, ground) -> Dictionary:
	var glyph := str(row.get("glyph", ""))
	var name := str(row.get("name", ""))
	var passable: bool = bool(row.get("passable", true))
	var buildable: bool = bool(row.get("buildable", false))
	var cover := int(row.get("cover_pct", 0))
	var reach := int(row.get("range_pct", 0))
	var tag := "Open"
	var tone := "dim"
	if not passable:
		tag = "Barrier"
		tone = "bad"
	elif reach > 0:
		tag = "High ground"
		tone = "violet"
	elif not buildable:
		tag = "No building"
		tone = "warn"
	elif cover > 0:
		tag = "Cover"
		tone = "good"
	elif int(row.get("infantry_pct", 100)) > 100:
		tag = "Fast"
		tone = "warn"
	var chips: Array = []
	if reach > 0:
		chips.append({"text": "+%d%% range" % reach, "tone": "violet"})
	if name == "River" or name == "Ford":
		chips.append({"text": "Reactor beside +%d kW" % VM.RIVER_BONUS_KW, "tone": "cyan"})
	var move := _movement(row)
	var rows: Array = [
		{"label": "Movement", "value": move[0], "tone": move[1]},
		{"label": "Cover", "value": "+%d%%" % cover if cover > 0 else "None", "tone": ""},
		{"label": "Build", "value": "Allowed" if buildable else "Not allowed", "tone": "" if buildable else "bad"},
	]
	var where := ""
	var tiles := 0
	if ground != null:
		where = _where(row, regions, ground)
		for y in ground.height:
			for x in ground.width:
				if ground.glyph_at(x, y) == glyph:
					tiles += 1
	var sub_parts: Array = []
	if where != "":
		sub_parts.append(where)
	if ground != null:
		sub_parts.append("%d tiles" % tiles)
	return {"kind": "ground", "glyph": glyph, "name": name, "sub": " / ".join(sub_parts), "tag": tag, "tone": tone,
		"chips": chips, "rows": rows, "note": str(NOTES.get(glyph, ""))}


## The smallest named region whose ground this row belongs to and whose box really holds a tile of it ("" when none).
static func _where(row: Dictionary, regions: Array, ground) -> String:
	var best := ""
	var best_area := 1 << 30
	for r in regions:
		var names: Array = VM.REGION_GROUNDS.get(str(r["kind"]), [])
		if not names.has(str(row.get("name", ""))):
			continue
		var found := false
		for y in range(maxi(0, int(r["y0"])), mini(ground.height, int(r["y1"]) + 1)):
			for x in range(maxi(0, int(r["x0"])), mini(ground.width, int(r["x1"]) + 1)):
				if ground.glyph_at(x, y) == str(row.get("glyph", "")):
					found = true
					break
			if found:
				break
		var area := (int(r["x1"]) - int(r["x0"]) + 1) * (int(r["y1"]) - int(r["y0"]) + 1)
		if found and area < best_area:
			best = str(r["name"])
			best_area = area
	return best


static func _deposit_card(snap: Dictionary, ground, kind: String) -> Dictionary:
	var count := 0
	var left := 0
	var under: Array = []
	for d in snap.get("deposits", []):
		if not (d is Dictionary) or str(d.get("kind", "")) != kind or int(d.get("remaining", 0)) <= 0:
			continue
		count += 1
		left += int(d["remaining"])
		if ground != null:
			var n: String = ground.name_at(int(d.get("x", -1)), int(d.get("y", -1)))
			if n != "" and not under.has(n):
				under.append(n)
	if count == 0:
		return {}
	if kind == "Alloy":
		# Alloy is scenery in the Earthfront sim (earthfront.rs: never mined), so the card says only that, and only there.
		if not bool(snap.get("earthfront", false)):
			return {}
		return {"kind": "alloy", "glyph": "", "name": "Alloy crystals", "sub": "%d deposits" % count, "tag": "Scenery", "tone": "violet", "chips": [],
			"rows": [
				{"label": "Deposits", "value": str(count), "tone": ""},
				{"label": "Mining", "value": "None", "tone": "warn"},
				{"label": "Sits on", "value": ", ".join(under) if not under.is_empty() else "Unknown", "tone": ""},
			], "note": NOTE_ALLOY}
	return {"kind": "ore", "glyph": "", "name": "Ore deposit", "sub": "%d deposits" % count, "tag": "Resource", "tone": "cyan", "chips": [],
		"rows": [
			{"label": "Deposits", "value": str(count), "tone": ""},
			{"label": "Refinery near", "value": "+%d%%" % VM.ORE_BONUS_PCT, "tone": "good"},
			{"label": "Left in the ground", "value": _thousands(left), "tone": ""},
		], "note": NOTE_ORE}


## The footer: one rule per fact the ground table and regions really support, numbers read from the table.
static func rules(rows: Array, regions: Array) -> Array:
	var out: Array = []
	var high: Dictionary = {}
	for row in rows:
		if int(row.get("range_pct", 0)) > int(high.get("range_pct", 0)):
			high = row
	if not high.is_empty():
		out.append({"head": "High ground", "tail": "adds %d%% range" % int(high["range_pct"])})
	for row in rows:
		if int(row.get("infantry_pct", 100)) > 100 and int(row.get("cover_pct", 0)) == 0 and bool(row.get("passable", true)):
			out.append({"head": str(row["name"]), "tail": "are fast and offer no cover"})
			break
	var river := ""
	var ford := ""
	for r in regions:
		if str(r["kind"]) == "river" and river == "":
			river = str(r["name"])
		elif str(r["kind"]) == "ford" and ford == "":
			ford = str(r["name"])
	var blocked := false
	var wade := false
	for row in rows:
		if str(row.get("name", "")) == "River" and not bool(row.get("passable", true)):
			blocked = true
		if str(row.get("name", "")) == "Ford" and bool(row.get("passable", false)):
			wade = true
	if river != "" and ford != "" and blocked and wade:
		out.append({"head": river, "tail": "crosses only at %s" % ford})
	for row in rows:
		if str(row.get("name", "")) == "Forest" and int(row.get("cover_pct", 0)) > 0:
			var tail := "gives %d%% cover" % int(row["cover_pct"])
			if int(row.get("vehicle_pct", 100)) < 100:
				tail += " and slows vehicles"
			out.append({"head": "Forest", "tail": tail})
			break
	return out


# ------------------------------------------------------------------ board 6: first-minutes briefing

## The briefing card for the first objective group, from the game's own tutorial stage (the objective the HUD already shows;
## the snapshot carries no objective text). {} outside stages 0 to BRIEFING_LAST_STAGE, after the match ended, or without a
## stage. Copy that names a place uses a region of the snapshot and is left out when that region does not exist.
const TITLES := ["Secure the landing zone", "Power the beachhead", "Establish income"]


static func briefing(stage: int, snap: Dictionary, winner := -1) -> Dictionary:
	if stage < 0 or stage > BRIEFING_LAST_STAGE or winner >= 0:
		return {}
	var details: Array = load("res://scripts/ui/live_adapter.gd").STAGE_DETAIL
	var items: Array = []
	var first := maxi(stage - 1, 0)
	for i in range(first, first + 3):
		if i >= details.size():
			break
		items.append({"t": str(details[i]), "state": "done" if i < stage else ("active" if i == stage else "todo")})
	var river := ""
	for r in VM.regions(snap):
		if str(r["kind"]) == "river":
			river = str(r["name"])
			break
	var body := ""
	match stage:
		0:
			body = "Your Command Centre founds the colony. Everything you build must stand inside its territory."
		1:
			body = "Build a Reactor for more generation."
			if river != "":
				body += " One beside %s gains +%d kW of river cooling." % [river, VM.RIVER_BONUS_KW]
		2:
			body = "A Refinery beside an ore deposit hauls %d%% more. Haulers carry it to your stock." % VM.ORE_BONUS_PCT
	return {"tag": "Step %d of %d" % [stage + 1, details.size()], "title": TITLES[stage], "body": body, "items": items, "ratio": float(stage) / float(details.size())}
