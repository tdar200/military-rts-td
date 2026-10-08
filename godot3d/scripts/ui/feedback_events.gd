extends RefCounted
## Kestrel feedback (plan 2026-10-07-kestrel-depth, Task 7): the events a player should hear and read, derived from two
## consecutive bridge snapshots and a memo the game keeps (`state`, cleared by the game when a restart sends the tick
## back). Pure: no engine, no clock, no sound; earthfront_3d.gd turns each event into a toast and a director request on
## Kestrel only (Survival never calls this).
##
## Each event is {id, toast, body, at, sound, volume_db, key}: `id` names the event, `toast` and `body` the HUD toast (an
## empty toast means the HUD already shows one), `sound` the manifest id to request, `volume_db` its trim against the
## director's level, `key` the director's cooldown key (the sound's own id unless it shares one with another event), `at`
## always null: every cue here is placeless, so none can tell where something hidden stands.
##
## Fog: entities are only what the player sees (and remembered buildings, which carry `remembered`). Every reading below
## uses visible entities only; the wave tracking counts an attacker as beaten only where the player could have watched it
## die (see derive).

const LiveAdapter := preload("res://scripts/ui/live_adapter.gd")
const VmGameplay := preload("res://scripts/ui/vm_gameplay.gd")
const AudioDirector := preload("res://scripts/audio/audio_director.gd")

const HUMAN := 0
const TICKS_PER_SECOND := 30
## The 45 s wave warning (the HUD's "Enemy signal detected" window opens at the same tick count).
const WAVE_WARNING_TICKS := 45 * TICKS_PER_SECOND
const WAVE_WARNING_DB := -6.0
## Inside the last ten seconds the HUD's full-volume "Ten seconds" alert speaks instead.
const TEN_SECONDS_TICKS := 10 * TICKS_PER_SECOND
## At most one "units under attack" toast in this many sim ticks (10 s; the director holds the sound as long).
const ATTACKED_GAP_TICKS := 10 * TICKS_PER_SECOND


## Materials missing for an order costing `cost` with `money` in hand: 0 when affordable or when the cost is unknown (-1).
static func funds_short(cost: int, money: int) -> int:
	return maxi(0, cost - money) if cost >= 0 else 0


## A building's material cost: the deck's card (LiveAdapter.BUILD_CARDS, the game's command table), except the refinery
## when the snapshot carries a depth price for it (Task 18 makes the refinery dearer with each one built). -1 when no card.
static func build_cost(kind: String, snap: Dictionary) -> int:
	if kind == "Refinery":
		var depth = snap.get("depth", {})
		if depth is Dictionary and depth.has("refinery_cost"):
			return int(depth["refinery_cost"])
	for card in LiveAdapter.BUILD_CARDS:
		if String(card[1]) == kind:
			return int(card[4])
	return -1


## A unit's material cost from the units deck (LiveAdapter.UNIT_CARDS); -1 for a kind without a card.
static func unit_cost(kind: String) -> int:
	for spec in LiveAdapter.UNIT_CARDS:
		if String(spec[3]) == kind:
			return int(spec[4])
	return -1


## "3 Riflemen ready", "Gunship ready": the HUD's name for the kind, a count only for more than one.
static func batch_text(kind: String, count: int) -> String:
	var name := String(LiveAdapter.KIND_NAMES.get(kind, kind))
	if count <= 1:
		return "%s ready" % name
	if not name.ends_with("men"):
		name += "s"
	return "%d %s ready" % [count, name]


## The events between `prev` and `snap`. `state` is the caller's memo (an empty Dictionary at the start of a match).
static func derive(prev: Dictionary, snap: Dictionary, state: Dictionary) -> Array:
	var out: Array = []
	_power(prev, snap, out)
	_wave_warning(prev, snap, out)
	_wave_cleared(prev, snap, state, out)
	_attacked(prev, snap, state, out)
	_production(prev, snap, out)
	return out


static func _event(id: String, toast: String, body: String, sound: String, volume_db := 0.0, key := "") -> Dictionary:
	return {"id": id, "toast": toast, "body": body, "at": null, "sound": sound, "volume_db": volume_db,
		"key": key if key != "" else sound}


# ------------------------------------------------------------------ power

## Demand crossing above generation (power_down), and back at or below it (power_up). Edge triggered, so a steady state
## and a re-delivered snapshot say nothing.
static func _power(prev: Dictionary, snap: Dictionary, out: Array) -> void:
	if not prev.has("power_generation") or not snap.has("power_generation"):
		return
	var was_short := int(prev.get("power_demand", 0)) > int(prev["power_generation"])
	var gen := int(snap["power_generation"])
	var dem := int(snap.get("power_demand", 0))
	var short := dem > gen
	if short and not was_short:
		out.append(_event("power_down", "LOW POWER", "DEMAND %d KW OVER %d KW OUTPUT • BUILD A REACTOR" % [dem, gen], "power_down"))
	elif was_short and not short:
		out.append(_event("power_up", "POWER RESTORED", "OUTPUT %d KW COVERS %d KW DEMAND" % [gen, dem], "power_up"))


# ------------------------------------------------------------------ wave warning

## The next wave's timer crossing 45 s (into the HUD's (10 s, 45 s] "Enemy signal detected" window, which already raises
## its own toast, so this event carries none): the alert sound, 6 dB under the ten-second alert.
static func _wave_warning(prev: Dictionary, snap: Dictionary, out: Array) -> void:
	var before := int(prev.get("next_wave_ticks", -1))
	var now := int(snap.get("next_wave_ticks", -1))
	if before > WAVE_WARNING_TICKS and now > TEN_SECONDS_TICKS and now <= WAVE_WARNING_TICKS:
		out.append(_event("wave_warning", "", "", "alert", WAVE_WARNING_DB))


# ------------------------------------------------------------------ wave cleared

## A wave is cleared when every attacker that came with it is gone. The memo tracks the wave's alien units (id -> last
## seen cell) from the spawn poll (waves_survived rising): the alien units new on that poll, and, under fog, every alien
## unit first seen after it (the wave walking out of the dark). A tracked unit missing from the snapshot was beaten when
## its last cell and the cells around it are in sight now, and lost (it may have walked out of view) otherwise; a lost
## unit seen again is tracked again. Cleared: no tracked unit left in sight and at least `target` beaten, where `target`
## is the number tracked at the spawn without fog, and with fog the expedition size the HUD announced before the spawn
## (plus any attackers of the last wave still in sight). Without fog that is exactly "the spawned ids are all gone"; with
## fog it never claims a clearing from something the player could not see, at the price of sometimes saying nothing.
static func _wave_cleared(prev: Dictionary, snap: Dictionary, state: Dictionary, out: Array) -> void:
	var fog := _fog(snap)
	var aliens := {}  # id -> cell, alien units in sight now
	for e in _units(snap):
		if int(e.get("owner", HUMAN)) != HUMAN and not bool(e.get("remembered", false)):
			aliens[int(e.get("id", -1))] = VmGameplay.entity_cell(e)
	var known: Dictionary = state.get("known_aliens", {})
	var wave: Dictionary = state.get("wave", {})
	var lost: Dictionary = state.get("wave_lost", {})
	var waves := int(snap.get("waves_survived", 0))
	if waves > int(prev.get("waves_survived", waves)):
		var prev_aliens := {}
		for e in _units(prev):
			if int(e.get("owner", HUMAN)) != HUMAN:
				prev_aliens[int(e.get("id", -1))] = true
		var leftover := 0
		for id in wave.keys():
			if aliens.has(id):
				leftover += 1
			else:
				wave.erase(id)
		lost.clear()
		for id in aliens:
			if not prev_aliens.has(id) and not wave.has(id):
				wave[id] = aliens[id]
		var expected := int(prev.get("next_expedition_size", snap.get("next_expedition_size", 0)))
		state["wave_target"] = (maxi(1, expected) + leftover) if fog["active"] else maxi(1, wave.size())
		state["wave_beaten"] = 0
		state["wave_open"] = true
		state["wave_number"] = waves
	elif bool(state.get("wave_open", false)):
		for id in aliens:
			if lost.has(id):
				lost.erase(id)
				wave[id] = aliens[id]
			elif fog["active"] and not known.has(id) and not wave.has(id):
				wave[id] = aliens[id]
		for id in wave.keys():
			if aliens.has(id):
				wave[id] = aliens[id]
				continue
			if _deep_visible(fog, wave[id]):
				state["wave_beaten"] = int(state.get("wave_beaten", 0)) + 1
			else:
				lost[id] = true
			wave.erase(id)
		var beaten := int(state.get("wave_beaten", 0))
		if wave.is_empty() and beaten > 0 and beaten >= int(state.get("wave_target", 1)):
			state["wave_open"] = false
			var n := int(state.get("wave_number", waves))
			out.append(_event("wave_cleared", "WAVE %02d CLEARED" % n, "NO ATTACKER FROM IT REMAINS • REPAIR AND REGROUP", "wave_cleared"))
	for id in aliens:
		known[id] = true
	state["known_aliens"] = known
	state["wave"] = wave
	state["wave_lost"] = lost


## The snapshot's fog mask: {active, mask, w, h}. Inactive (everything in sight) without a mask of the map's size or when
## every cell is visible (EARTHFRONT_FOG=0), as FogView reads it.
static func _fog(snap: Dictionary) -> Dictionary:
	var mask := String(snap.get("fog", ""))
	var w := int(snap.get("map_width", 0))
	var h := int(snap.get("map_height", 0))
	var valid := w > 0 and h > 0 and mask.length() == w * h
	return {"active": valid and mask.count("2") != mask.length(), "mask": mask, "w": w, "h": h}


## True when the cell and every cell around it are in sight (always, without fog).
static func _deep_visible(fog: Dictionary, cell: Array) -> bool:
	if not bool(fog["active"]):
		return true
	var w := int(fog["w"])
	var h := int(fog["h"])
	var mask := String(fog["mask"])
	for dc in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			var c := clampi(int(cell[0]) + dc, 0, w - 1)
			var r := clampi(int(cell[1]) + dr, 0, h - 1)
			if mask[r * w + c] != "2":
				return false
	return true


# ------------------------------------------------------------------ units under attack

## A human unit lost HP since the last snapshot (structures have their own alert): one event per ATTACKED_GAP_TICKS of
## sim time. The sound is the alert under its own director cooldown key, so it never repeats faster than 10 s either.
static func _attacked(prev: Dictionary, snap: Dictionary, state: Dictionary, out: Array) -> void:
	var before := {}
	for e in _units(prev):
		if int(e.get("owner", -1)) == HUMAN:
			before[int(e.get("id", -1))] = e
	var tick := int(snap.get("tick", 0))
	for e in _units(snap):
		if int(e.get("owner", -1)) != HUMAN:
			continue
		var p = before.get(int(e.get("id", -1)))
		if p == null or String(p.get("kind", "")) != String(e.get("kind", "")) or _hp(e) >= _hp(p):
			continue
		if state.has("attacked_tick") and tick - int(state["attacked_tick"]) < ATTACKED_GAP_TICKS:
			return
		state["attacked_tick"] = tick
		var name := String(LiveAdapter.KIND_NAMES.get(String(e.get("kind", "")), String(e.get("kind", ""))))
		out.append(_event("unit_attacked", "UNITS UNDER ATTACK", "%s TAKING FIRE" % name.to_upper(), "alert", 0.0, "unit_attacked"))
		return


static func _hp(e: Dictionary) -> int:
	return int(e["hp_bits"]) if e.has("hp_bits") else int(e.get("hp", 0)) * 65536


# ------------------------------------------------------------------ production

## Human units that are new on this poll (an id the last snapshot did not have, or had as another kind), counted by kind
## in order of first appearance: one toast and one acknowledgement per kind, "3 Riflemen ready".
static func _production(prev: Dictionary, snap: Dictionary, out: Array) -> void:
	var before := {}
	for e in _units(prev):
		before[int(e.get("id", -1))] = e
	var counts := {}
	for e in _units(snap):
		if int(e.get("owner", -1)) != HUMAN:
			continue
		var p = before.get(int(e.get("id", -1)))
		var kind := String(e.get("kind", ""))
		if p != null and String(p.get("kind", "")) == kind and int(p.get("owner", -1)) == HUMAN:
			continue
		counts[kind] = int(counts.get(kind, 0)) + 1
	for kind in counts:
		out.append(_event("production_complete", batch_text(kind, int(counts[kind])), "REPORTING FOR DUTY", AudioDirector.ack_for(kind)))


## The snapshot's units (an entity without a category counts as one).
static func _units(snap: Dictionary) -> Array:
	var list = snap.get("entities", [])
	if not list is Array:
		return []
	return (list as Array).filter(func(e): return e is Dictionary and String(e.get("category", "unit")) == "unit")
