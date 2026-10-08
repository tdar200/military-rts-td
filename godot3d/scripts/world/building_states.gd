extends RefCounted
## Kestrel building states (kestrel-depth Task 8): a building's look between healthy and destroyed, drawn with the pooled
## WorldFx cards (no new art, no per-building node or material).
##
## States, from the snapshot's hp_bits / max_hp_bits and what the HUD already reads (state_for):
##   fire     below FIRE_BELOW_PCT of max HP: a small flame with a flicker flash every 0.35 s, dark smoke every other one
##   smoke    below SMOKE_BELOW_PCT: a grey smoke card off the roof every 0.6 s
##   working  at or above half HP, while the building works (is_working): a pale steam puff every 2.5 s
##   ok       otherwise: nothing
## Damage outranks work. A building that works: complete, powered (services power >= POWERED, a missing entry counts as
## powered) and producing (production_name), or a Refinery with ore to process (REFINE_MIN), or the player's ResearchLab
## while the player's research runs (not paused).
##
## The scene (earthfront_3d.gd, Kestrel only) calls update() for every live, complete building the player sees now and
## forget() for one that died, is a construction site, a memory or out of sight (its cards are released at once); a
## restarted sim clears everything. step() runs on the effects clock (WorldFx.time), which stands still while the game is
## paused, so nothing is emitted or burns out behind the pause menu. Every emission is paced from that clock (no random):
## a building entering a state first emits within one interval, at a phase fixed by its id, and the roof spot it emits
## from cycles through SPOTS.

const SMOKE_BELOW_PCT := 50
const FIRE_BELOW_PCT := 25
const INTERVAL := {"smoke": 0.6, "fire": 0.35, "working": 2.5}
const POWERED := 500  # services power per mille: below it the sim stalls production and research
const REFINE_MIN := 5  # ore a powered Refinery needs in store to process a batch (earthfront.rs run_economy: ore / 5 * 5)
## Emission spots across the roof, as shares of the card width (cycled per emission, so a plume wavers without noise).
const SPOTS := [-0.08, 0.05, -0.02, 0.1, -0.12]

## id -> {state, anchor (the roof spot's ground point), lift (world height of the roof), width (card width, world
## units), owner, last (effects time of the last emission), n (emissions so far)}
var _entries := {}


## "fire" below a quarter of max HP, "smoke" below half, else "working" when `working`, else "ok". Integer maths on the
## snapshot's Fixed bits (or plain HP): exactly half is not smoke, exactly a quarter smokes. No max HP: no damage state.
static func state_for(hp: int, max_hp: int, working: bool) -> String:
	if max_hp > 0:
		if hp * 100 < max_hp * FIRE_BELOW_PCT:
			return "fire"
		if hp * 100 < max_hp * SMOKE_BELOW_PCT:
			return "smoke"
	return "working" if working else "ok"


## Seconds between two emissions of `state` (INF for a state that never emits).
static func interval(state: String) -> float:
	return float(INTERVAL.get(state, INF))


## True when a building in `state` that last emitted at `last_emit` emits again at `now` (effects time, seconds).
static func next_emit(state: String, last_emit: float, now: float) -> bool:
	var every := interval(state)
	return every < INF and now - last_emit + 1e-6 >= every


## Whether a building works, read from its snapshot entity, its services entry ({} when the bridge sent none) and whether
## the player's research is running now.
static func is_working(entity: Dictionary, service: Dictionary, researching: bool) -> bool:
	if int(entity.get("construction", 0)) > 0:
		return false
	if not service.is_empty() and int(service.get("power", 1000)) < POWERED:
		return false
	if String(entity.get("production_name", "")) != "":
		return true
	match String(entity.get("kind", "")):
		"Refinery":
			return int(service.get("ore", 0)) >= REFINE_MIN
		"ResearchLab":
			return researching and int(entity.get("owner", 1)) == 0
	return false


## Sets building `id`'s state for this poll. A new state starts its pacing at `now`, phased by the id. "ok" (or any state
## that never emits) drops the entry; its last cards fade out on their own.
func update(id: int, state: String, anchor: Vector3, lift: float, width: float, owner: int, now: float) -> void:
	if interval(state) == INF:
		_entries.erase(id)
		return
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty() or String(e.state) != state:
		var every := interval(state)
		var phase := fposmod(float(id) * 0.618034, 1.0)
		e = {"state": state, "last": now - every * (1.0 - phase), "n": int(e.get("n", 0))}
		_entries[id] = e
	e.anchor = anchor
	e.lift = lift
	e.width = width
	e.owner = owner


## Building `id` is gone, a site, a memory or out of sight: no state, and its cards leave the screen now.
func forget(id: int, fx: RefCounted) -> void:
	_entries.erase(id)
	if fx != null:
		fx.release(id)


## A restarted sim: every state and every card of one goes.
func clear(fx: RefCounted) -> void:
	for id in _entries.keys():
		forget(int(id), fx)


func count() -> int:
	return _entries.size()


## The emitting state building `id` holds ("" when it has none: healthy and idle, or forgotten).
func state_of(id: int) -> String:
	return String(_entries[id].state) if _entries.has(id) else ""


## Emits what is due at effects time `now` into `fx` (WorldFx). Returns the emissions that drew (culled ones still keep
## their pacing).
func step(fx: RefCounted, now: float) -> int:
	var drawn := 0
	for id in _entries:
		var e: Dictionary = _entries[id]
		var state := String(e.state)
		if not next_emit(state, float(e.last), now):
			continue
		var every := interval(state)
		e.last = float(e.last) + every
		if now - float(e.last) >= every:
			e.last = now  # far behind (a long frame): no burst of catch-up emissions
		var k := int(e.n)
		e.n = k + 1
		var w := float(e.width)
		var at: Vector3 = e.anchor + Vector3(float(SPOTS[k % SPOTS.size()]) * w, float(e.lift), 0.0)
		var slot := -1
		match state:
			"smoke":
				slot = fx.smoke(at, w, int(e.owner), int(id))
			"fire":
				slot = fx.fire(at, w, int(e.owner), int(id))
				if k % 2 == 0:
					fx.smoke(at + Vector3(0.0, w * 0.06, 0.0), w * 1.2, int(e.owner), int(id), true)
			"working":
				slot = fx.puff(at, w, int(id))
		if slot >= 0:
			drawn += 1
	return drawn
