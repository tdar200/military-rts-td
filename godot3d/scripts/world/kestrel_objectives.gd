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
##   4 Hold the ford:       wave one BEATEN with the base alive (the sim has not named another winner). The snapshot's
##                          waves_survived is the sim's wave_count, the waves that have SPAWNED, so it alone says only
##                          that wave one is on its way. Beaten = wave one spawned at least MIN_TICKS ago and no visible
##                          non-human unit on the home side of the ford (cell column <= the ford region's x1) for
##                          QUIET_TICKS, or a second wave has spawned. Attackers that reach the base are inside human sight,
##                          so they are in `entities` even under fog; units beyond the ford (the alien base with fog off)
##                          never count. Two latches ride in the result and come back through `previous`: ford_spawn_tick
##                          (first tick with waves_survived >= 1) and ford_threat_tick (last tick an attacker was seen on
##                          the home side), plus ford_held itself, so a held ford stays held.
##   5 Break the Core Node: winner == human. While the snapshot's depth.core_shielded is true (kestrel-depth Task 21: a
##                          relay stands or the sixth expedition has not spawned, so the sim spares the Core Node) the
##                          detail names that gate instead of the Core Node's cell.
## Rule for a lost building (chosen and tested): before wave one the setup objectives 1 to 3 are judged live, so a destroyed
## Reactor honestly sends the card back to "Power the base". Once wave one has spawned the setup phase is over and 1 to 3
## stay done (a later power loss is the power tip's job, not an objective regression), so a mid-game load with two waves
## spawned goes straight to the Core Node whatever the current squad or truck state.
## The current stage is the first objective not done (5 when everything is: a won match stays on the last objective).

const VmGameplay := preload("res://scripts/ui/vm_gameplay.gd")
const HUMAN := 0
const SQUAD_SIZE := 6
## Hold the ford: wave one must have spawned this long ago (20 s; Task 10 saw it in sight about 280 ticks after spawning)...
const FORD_MIN_TICKS := 600
## ...and the home side must have been clear of visible attackers this long (10 s).
const FORD_QUIET_TICKS := 300
const TICKS_PER_SECOND := 30.0
const IDS := ["power", "economy", "squad", "ford", "core"]
const TITLES := ["Power the base", "Start the economy", "Raise a squad", "Hold the ford", "Break the Core Node"]
## Stage 5's detail while the Core Node is shielded (kestrel-depth Task 21).
const CORE_SHIELDED_DETAIL := "Destroy both relays and outlast the sixth expedition to expose the Core Node"


## {stage: 1..5, title, detail (the current objective's), complete, failed, economy_seen, ford_spawn_tick, ford_threat_tick,
##  ford_held (the latches), objectives: [{id, title, detail, done}] x5}. `previous` is the last result (or {}): only its
##  latches are read.
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
	var tick := int(snap.get("tick", 0))
	var waves := int(snap.get("waves_survived", 0))
	var spawned := waves >= 1 and not failed
	var spawn_tick := -1
	var threat_tick := -1
	if waves >= 1:
		spawn_tick = int(previous.get("ford_spawn_tick", -1))
		if spawn_tick < 0:
			spawn_tick = tick
		threat_tick = maxi(int(previous.get("ford_threat_tick", -1)), spawn_tick)
		if _attacker_on_home_side(snap):
			threat_tick = tick
	var beaten := spawned and (bool(previous.get("ford_held", false)) or waves >= 2 \
			or (tick - spawn_tick >= FORD_MIN_TICKS and tick - threat_tick >= FORD_QUIET_TICKS))
	var done := [
		spawned or complete or (reactors > 0 and generation >= demand),
		spawned or complete or economy_seen,
		spawned or complete or (barracks > 0 and combat >= SQUAD_SIZE),
		beaten or complete,
		complete,
	]
	var ford := _region(snap, "ford", "the ford")
	var ford_detail := _ford_detail(snap, ford)
	if done[3]:
		ford_detail = "Wave one held at %s" % ford
	elif spawned:
		ford_detail = "Wave one crossing at %s" % ford
	var details := [
		_power_detail(done[0], reactors, generation, demand),
		_economy_detail(done[1], refineries, harvesters),
		_squad_detail(done[2], barracks, combat),
		ford_detail,
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
		"economy_seen": economy_seen, "ford_spawn_tick": spawn_tick, "ford_threat_tick": threat_tick, "ford_held": beaten,
		"objectives": objectives,
	}


static func _entities(snap: Dictionary) -> Array:
	var list = snap.get("entities", [])
	return list.filter(func(e): return e is Dictionary) if list is Array else []


## A visible non-human unit on the home side of the ford: cell column <= the ford region's x1 (half the map without one).
static func _attacker_on_home_side(snap: Dictionary) -> bool:
	var line := int(snap.get("map_width", 0)) / 2
	var list = snap.get("regions", [])
	if list is Array:
		for r in list:
			if r is Dictionary and str(r.get("kind", "")) == "ford":
				line = int(r.get("x1", line))
				break
	for e in _entities(snap):
		if int(e.get("owner", HUMAN)) != HUMAN and str(e.get("category", "")) == "unit" and int(VmGameplay.entity_cell(e)[0]) <= line:
			return true
	return false


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


## The bridge's depth.core_shielded (kestrel-depth Task 21). False with no depth block (Survival, classic Kestrel), a
## malformed one, or an empty snapshot: only the sim's own word raises the shield.
static func core_shielded(snap: Dictionary) -> bool:
	var depth = snap.get("depth", null)
	return depth is Dictionary and bool(depth.get("core_shielded", false))


## A depth match (kestrel-depth Task 21): the depth block carries core_shielded, so the relays gate the Core Node's shield
## and are no longer the optional side objective they are on classic Kestrel.
static func relays_required(snap: Dictionary) -> bool:
	var depth = snap.get("depth", null)
	return depth is Dictionary and depth.has("core_shielded")


static func _core_detail(snap: Dictionary) -> String:
	if core_shielded(snap):
		return CORE_SHIELDED_DETAIL
	var core = snap.get("core_node", null)
	if core is Array and core.size() >= 2:
		return "Destroy the Core Node at (%d, %d)" % [int(core[0]), int(core[1])]
	return "Destroy the alien Core Node"
