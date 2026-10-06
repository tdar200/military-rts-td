extends RefCounted
## Kestrel Reach objectives (plan 2026-10-06-kestrel-next-level, Task 3). Pure: everything is derived from one bridge
## snapshot (plus, optionally, the previous result as a latch); the snapshot carries no objective text. earthfront_3d.gd
## evaluates it once per snapshot on Kestrel (world art on) and the HUD card, the briefing and the toasts read that result.
## Survival never calls this: it keeps the legacy tutorial (_update_tutorial) byte for byte.
##
## The five objectives fit the Task 2 opening (CC, Reactor, Refinery, Barracks, one Harvester and 4 riflemen built):
##   1 Power the base:      a finished human PowerPlant and generation >= demand. True at the start, so it shows done from
##                          the first frame; it reopens (naming the kW shortfall) if the Reactor falls or is overdrawn.
##   2 Start the economy:   a finished human Refinery, a living human Harvester, and ore moving: a Harvester with cargo or
##                          ore in the refinery buffer (ore_buffer). Once seen, the previous result latches it, so the gap
##                          between two loads (empty truck, buffer processed) does not flicker it; losing the Refinery or
##                          every Harvester still reopens it.
##   3 Raise a squad:       a finished human Barracks and SQUAD_SIZE or more human combat units (every unit but Harvester).
##   4 Hold the ford:       waves_survived >= 1 with the base alive (the sim has not named another winner).
##   5 Break the Core Node: winner == human.
## Rule for a lost building (chosen and tested): before wave one the setup objectives 1 to 3 are judged live, so a destroyed
## Reactor honestly sends the card back to "Power the base". Once the ford is held the setup phase is over and 1 to 3 stay
## done (a later power loss is the power tip's job, not an objective regression), so a mid-game load with waves survived
## goes straight to the Core Node whatever the current squad or truck state.
## The current stage is the first objective not done (5 when everything is: a won match stays on the last objective).

const HUMAN := 0
const SQUAD_SIZE := 6
const TICKS_PER_SECOND := 30.0
const IDS := ["power", "economy", "squad", "ford", "core"]
const TITLES := ["Power the base", "Start the economy", "Raise a squad", "Hold the ford", "Break the Core Node"]


## {stage: 1..5, title, detail (the current objective's), complete, failed, economy_seen (the latch),
##  objectives: [{id, title, detail, done}] x5}. `previous` is the last result (or {}): only its economy latch is read.
static func evaluate(snap: Dictionary, previous: Dictionary = {}) -> Dictionary:
	var winner := int(snap.get("winner", -1))
	var complete := winner == HUMAN
	var failed := winner >= 0 and not complete
	var generation := int(snap.get("power_generation", 0))
	var demand := int(snap.get("power_demand", 0))
	var reactors := _built(snap, "PowerPlant")
	var refineries := _built(snap, "Refinery")
	var barracks := _built(snap, "Barracks")
	var harvesters := 0
	var carrying := false
	var combat := 0
	for e in _entities(snap):
		if int(e.get("owner", -1)) != HUMAN or str(e.get("category", "")) != "unit":
			continue
		if str(e.get("kind", "")) == "Harvester":
			harvesters += 1
			carrying = carrying or int(e.get("cargo", 0)) > 0
		else:
			combat += 1
	var ore_moving := carrying or int(snap.get("ore_buffer", 0)) > 0
	var economy_seen := refineries > 0 and harvesters > 0 and (ore_moving or bool(previous.get("economy_seen", false)))
	var held := int(snap.get("waves_survived", 0)) >= 1 and not failed
	var done := [
		held or complete or (reactors > 0 and generation >= demand),
		held or complete or economy_seen,
		held or complete or (barracks > 0 and combat >= SQUAD_SIZE),
		held or complete,
		complete,
	]
	var ford := _region(snap, "ford", "the ford")
	var details := [
		_power_detail(done[0], reactors, generation, demand),
		_economy_detail(done[1], refineries, harvesters),
		_squad_detail(done[2], barracks, combat),
		("Wave one held at %s" % ford) if done[3] else _ford_detail(snap, ford),
		"Core Node destroyed" if done[4] else _core_detail(snap),
	]
	var objectives: Array = []
	var stage := 0
	for i in IDS.size():
		objectives.append({"id": IDS[i], "title": TITLES[i], "detail": details[i], "done": done[i]})
		if stage == 0 and not done[i]:
			stage = i + 1
	if stage == 0:
		stage = IDS.size()
	return {
		"stage": stage, "title": TITLES[stage - 1], "detail": details[stage - 1], "complete": complete, "failed": failed,
		"economy_seen": economy_seen, "objectives": objectives,
	}


static func _entities(snap: Dictionary) -> Array:
	var list = snap.get("entities", [])
	return list.filter(func(e): return e is Dictionary) if list is Array else []


## Finished human buildings of `kind` (a construction site still has construction > 0 left).
static func _built(snap: Dictionary, kind: String) -> int:
	var n := 0
	for e in _entities(snap):
		if int(e.get("owner", -1)) == HUMAN and str(e.get("category", "")) == "building" and str(e.get("kind", "")) == kind and int(e.get("construction", 0)) <= 0:
			n += 1
	return n


## The snapshot's name for the first region of `kind`, else `fallback`.
static func _region(snap: Dictionary, kind: String, fallback: String) -> String:
	var list = snap.get("regions", [])
	if list is Array:
		for r in list:
			if r is Dictionary and str(r.get("kind", "")) == kind and str(r.get("name", "")) != "":
				return str(r["name"])
	return fallback


static func clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _power_detail(met: bool, reactors: int, generation: int, demand: int) -> String:
	if met:
		return "Reactor online: %d kW for %d kW demand" % [generation, demand]
	if reactors == 0:
		return "Build a Reactor (P): %d of %d kW" % [generation, demand]
	return "Power short: %d of %d kW, build a Reactor (P)" % [generation, demand]


static func _economy_detail(met: bool, refineries: int, harvesters: int) -> String:
	if met:
		return "Harvester hauling ore to the Refinery"
	if refineries == 0:
		return "Build a Refinery beside the ore (R)"
	if harvesters == 0:
		return "Train a Harvester at the Refinery"
	return "Harvester heading for the ore beside the base"


static func _squad_detail(met: bool, barracks: int, combat: int) -> String:
	if met:
		return "Squad ready: %d combat units" % combat
	if barracks == 0:
		return "Build a Barracks (B) to train riflemen"
	return "Train riflemen (T): %d of %d combat units" % [combat, SQUAD_SIZE]


static func _ford_detail(snap: Dictionary, ford: String) -> String:
	var ticks := int(snap.get("next_wave_ticks", -1))
	if ticks < 0:
		return "Hold %s against wave one" % ford
	return "Hold %s: first wave in %s" % [ford, clock(ceili(float(ticks) / TICKS_PER_SECOND))]


static func _core_detail(snap: Dictionary) -> String:
	var core = snap.get("core_node", null)
	if core is Array and core.size() >= 2:
		return "Destroy the Core Node at (%d, %d)" % [int(core[0]), int(core[1])]
	return "Destroy the alien Core Node"
