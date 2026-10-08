extends RefCounted
## Kestrel sound (plan 2026-10-06-kestrel-next-level, Task 5): every decision about what is heard, as plain calls with no
## engine in them. The manifest arrives as a Dictionary (AudioPool.load_manifest reads the file), the camera's ground
## rectangle through set_view (x and z, the game's view_ground_rect), the clock as `now` in seconds. request() answers
## whether a one-shot plays and how (volume, pan, bus, pitch); loops() the rotor, tread and footstep beds; duck_db() the
## Ambient and Music level. AudioPool plays the answers. The same calls in the same order always give the same answers:
## nothing here is random (a weapon's slight pitch variance is a fixed cycle per sound).
##
## The camera is orthographic, so distance from the camera means nothing: a world sound is placed by where it sits in the
## view. Pan follows its x across the view (the Kestrel camera never turns, so world x is screen x); it is a little
## quieter toward the view's edge, clearly quieter just past it, and silent past VIEW_MARGIN (the effects' own margin, so
## a sound is heard where an effect is drawn). Zooming out lowers world sounds by up to ZOOM_DB_MAX. A sound at
## Vector3.INF is a global cue (alerts, acknowledgements, the HUD): centred, never skipped for its place.

const PAN_MAX := 0.8  # the pan at the view's left and right edges (and past them)
const PAN_STEP := 0.4  # the bus layout's panner steps: SFX_L2 -0.8, SFX_L1 -0.4, SFX 0, SFX_R1 0.4, SFX_R2 0.8
const PAN_BUSES := {-2: "SFX_L2", -1: "SFX_L1", 0: "SFX", 1: "SFX_R1", 2: "SFX_R2"}
const VIEW_MARGIN := 2.5  # world units past the view's edge still heard (WorldFx.VIEW_MARGIN)
const EDGE_DB := -3.0  # at the view's edge, against its centre
const OFFSCREEN_DB := -6.0  # just past the edge
const MARGIN_DB := -15.0  # at the margin's outer edge
const REF_HALF_WIDTH := 9.0  # half the ground width at the default zoom (10 x 16:9 / 2): no zoom trim up to this
const ZOOM_DB_MAX := 6.0

## Seconds before the same sound may start again: a volley is a few distinct shots, not a buzz of one sample.
const COOLDOWN := {
	"rifle": 0.11, "plasma_bolt": 0.12, "cannon": 0.22,
	"explosion_small": 0.15, "explosion_large": 0.4, "collapse": 0.9,
	"ui_click": 0.03, "ui_hover": 0.05,
	"select": 0.12, "ack_infantry": 0.3, "ack_vehicle": 0.3, "ack_air": 0.3,
	"alert": 2.5, "build_complete": 0.8, "wave_inbound": 3.0,
	"rotor_loop": 0.1, "tread_loop": 0.1, "foot_loop": 0.1,
	# kestrel-depth Task 7: the event cues. A denied order answers a quick retry; power and wave news are rare by nature
	# and a flicker across the threshold must not chatter; a sting sounds once per match end.
	"denied": 0.35, "place_thunk": 0.15, "power_down": 4.0, "power_up": 4.0, "wave_cleared": 3.0,
	"research_complete": 1.0, "victory_sting": 5.0, "defeat_sting": 5.0,
	# a cooldown key, not a sound: units under attack sound the alert at most once per 10 s (request's "key" option)
	"unit_attacked": 10.0,
}
## At most this many of one sound at once.
const ID_VOICES := {
	"rifle": 3, "plasma_bolt": 3, "cannon": 2,
	"explosion_small": 3, "explosion_large": 2, "collapse": 1,
	"ui_click": 1, "ui_hover": 1,
	"select": 1, "ack_infantry": 1, "ack_vehicle": 1, "ack_air": 1,
	"alert": 1, "build_complete": 1, "wave_inbound": 1,
	"denied": 1, "place_thunk": 1, "power_down": 1, "power_up": 1, "wave_cleared": 1,
	"research_complete": 1, "victory_sting": 1, "defeat_sting": 1,
}
## At most this many of one category at once (the non-UI caps sum to 15, inside the pool's 16 SFX players).
const CATEGORY_VOICES := {"weapon": 6, "impact": 5, "voice": 2, "alert": 2, "ui": 2}
## At most this many starts of one category in any second.
const CATEGORY_RATE := {"weapon": 8, "impact": 6, "voice": 4, "alert": 3, "ui": 16}
const PRIORITY := {"loop": 0, "weapon": 1, "impact": 2, "ui": 3, "voice": 3, "alert": 4}
## A sound of priority p starts only while fewer than ROOM[p] SFX voices are busy (default SFX_VOICES): the last voices
## are kept for impacts, and the very last for acknowledgements and alerts, however loud the fight.
const ROOM := {1: 10, 2: 13}
const SFX_VOICES := 16
## These duck Ambient and Music: DUCK_DB for as long as they sound (DUCK_HOLD_MIN at least), then back over DUCK_RECOVER.
const DUCKS := ["explosion_large", "collapse", "alert", "wave_inbound", "victory_sting", "defeat_sting"]
const DUCK_DB := -9.0
const DUCK_HOLD_MIN := 0.5
const DUCK_RECOVER := 1.5
## Pitch offsets cycled per sound, scaled by the category's spread (alerts, the HUD and acknowledgements never vary).
const PITCH_CYCLE := [0.0, 0.031, -0.024, 0.012, -0.037, 0.022, -0.008]
const PITCH_SPREAD := {"weapon": 1.0, "impact": 0.6}
const LOOP_IDS := ["rotor_loop", "tread_loop", "foot_loop"]
const LOOP_COUNT_CAP := 8  # more movers than this are no louder
const LOOP_DB_PER_DOUBLING := 3.0

var paused := false
var _sounds: Dictionary = {}  # id -> {category, loop, base_volume_db, duration}
var _view := Rect2()
var _last: Dictionary = {}  # id -> the start time of its last play
var _plays: Dictionary = {}  # id -> plays so far (the pitch cycle's position)
var _voices: Array = []  # {id, category, end}: the sounds started and not yet over (or scheduled)
var _starts: Dictionary = {}  # category -> start times inside the last second
var _duck_until := -INF


## The manifest's sounds (Task 4's sfx_manifest.json, parsed).
func configure(manifest: Dictionary) -> void:
	_sounds.clear()
	for s in manifest.get("sounds", []):
		if not s is Dictionary or not s.has("id"):
			continue
		_sounds[String(s["id"])] = {
			"category": String(s.get("category", "")),
			"loop": bool(s.get("loop", false)),
			"base_volume_db": float(s.get("base_volume_db", 0.0)),
			"duration": float(s.get("duration_s", 0.0)),
		}


func has_sound(id: String) -> bool:
	return _sounds.has(id)


## The ground the camera sees (x in x, z in y); an empty rectangle (no view yet) silences every world sound.
func set_view(rect: Rect2) -> void:
	_view = rect


func set_paused(on: bool) -> void:
	paused = on


## Whether the one-shot `id` at `at` (Vector3.INF for a global cue) starts at `now`, and how. A refusal is
## {play: false, id, reason} with reason unknown, loop, paused, offscreen, cooldown, voices, priority or rate; it changes
## nothing, so a refused request never uses up a cooldown. While paused only the HUD's own sounds play.
## `opts` (kestrel-depth Task 7): "volume_db" trims this play against the sound's level (the 45 s wave warning is the
## alert 6 dB down); "key" names a cooldown of its own (COOLDOWN[key]) held on top of the sound's (units under attack
## share the alert but repeat at most every 10 s).
func request(id: String, at: Vector3, now: float, opts := {}) -> Dictionary:
	var s: Dictionary = _sounds.get(id, {})
	if s.is_empty():
		return _no(id, "unknown")
	var category := String(s["category"])
	if bool(s["loop"]):
		return _no(id, "loop")
	if paused and category != "ui":
		return _no(id, "paused")
	var place := _place(at, true)
	if not bool(place["heard"]):
		return _no(id, "offscreen")
	if _last.has(id) and now - float(_last[id]) < float(COOLDOWN.get(id, 0.0)):
		return _no(id, "cooldown")
	var key := String(opts.get("key", id))
	if key != id and _last.has(key) and now - float(_last[key]) < float(COOLDOWN.get(key, 0.0)):
		return _no(id, "cooldown")
	_prune(now)
	if active_voices(id, now) >= int(ID_VOICES.get(id, 1)) or active_voices(category, now) >= int(CATEGORY_VOICES.get(category, 1)):
		return _no(id, "voices")
	var priority := int(PRIORITY.get(category, 0))
	if category != "ui" and active_voices("", now) >= int(ROOM.get(priority, SFX_VOICES)):
		return _no(id, "priority")
	var starts: Array = _starts.get(category, [])
	if starts.size() >= int(CATEGORY_RATE.get(category, 1)):
		return _no(id, "rate")
	var n := int(_plays.get(id, 0))
	_plays[id] = n + 1
	var pitch := 1.0 + float(PITCH_CYCLE[n % PITCH_CYCLE.size()]) * float(PITCH_SPREAD.get(category, 0.0))
	var length := float(s["duration"]) / pitch
	_voices.append({"id": id, "category": category, "end": now + length})
	starts.append(now)
	_starts[category] = starts
	_last[id] = now
	_last[key] = now
	if id in DUCKS:
		_duck_until = maxf(_duck_until, now + maxf(DUCK_HOLD_MIN, length))
	var pan := float(place["pan"])
	var bus := "UI" if category == "ui" else _pan_bus(pan)
	return {"play": true, "id": id, "category": category,
		"volume_db": float(s["base_volume_db"]) + float(place["db"]) + float(opts.get("volume_db", 0.0)),
		"pan": pan, "bus": bus, "pitch": pitch, "priority": priority, "duration": length}


## The loop beds for this frame. `moving` maps a loop id to the ground positions of the units moving with that sound
## (either side); only those inside the view count. Each answer is {play: false, id} or {play: true, id, category,
## volume_db, pan, bus, count, pitch}: louder by LOOP_DB_PER_DOUBLING per doubling of the movers up to LOOP_COUNT_CAP,
## panned to their mean position. All stop while paused.
func loops(moving: Dictionary) -> Dictionary:
	var out := {}
	for id in LOOP_IDS:
		var s: Dictionary = _sounds.get(id, {})
		var n := 0
		var pan_sum := 0.0
		if not paused and not s.is_empty():
			for p in moving.get(id, []):
				var place := _place(p, false)
				if bool(place["heard"]):
					n += 1
					pan_sum += float(place["pan"])
		if n == 0:
			out[id] = {"play": false, "id": id}
			continue
		var k := float(mini(n, LOOP_COUNT_CAP))
		var pan := pan_sum / float(n)
		out[id] = {"play": true, "id": id, "category": "loop", "count": n, "pitch": 1.0, "pan": pan, "bus": _pan_bus(pan),
			"volume_db": float(s["base_volume_db"]) + zoom_db() + LOOP_DB_PER_DOUBLING * log(k) / log(2.0)}
	return out


## The Ambient and Music level at `now`: DUCK_DB while a ducking sound plays, then a straight line back to 0 dB.
func duck_db(now: float) -> float:
	if now < _duck_until:
		return DUCK_DB
	var k := (now - _duck_until) / DUCK_RECOVER
	return 0.0 if k >= 1.0 else DUCK_DB * (1.0 - k)


## The zoom's trim on world sounds: 0 dB up to the default zoom's view width, down to -ZOOM_DB_MAX zoomed out.
func zoom_db() -> float:
	var hw := _view.size.x * 0.5
	if hw <= REF_HALF_WIDTH:
		return 0.0
	return -minf(ZOOM_DB_MAX, 20.0 * log(hw / REF_HALF_WIDTH) / log(10.0))


## Voices sounding (or scheduled) at `now`: of the sound `key`, of the category `key`, or of every SFX category for "".
func active_voices(key: String, now: float) -> int:
	var count := 0
	for v in _voices:
		if float(v["end"]) <= now:
			continue
		if key == "":
			if v["category"] != "ui":
				count += 1
		elif v["id"] == key or v["category"] == key:
			count += 1
	return count


## Where `at` sits in the view: {heard, db, pan}. `margin` lets a one-shot just past the edge be heard, quieter.
func _place(at: Vector3, margin: bool) -> Dictionary:
	if not is_finite(at.x) or not is_finite(at.z):
		return {"heard": true, "db": 0.0, "pan": 0.0}
	if _view.size.x <= 0.0 or _view.size.y <= 0.0:
		return {"heard": false}
	var hw := _view.size.x * 0.5
	var hh := _view.size.y * 0.5
	var c := _view.get_center()
	var dx := at.x - c.x
	var dz := at.z - c.y
	var past := maxf(absf(dx) - hw, absf(dz) - hh)  # how far outside the view (0 or less inside)
	if past > (VIEW_MARGIN if margin else 0.0):
		return {"heard": false}
	var db := zoom_db()
	if past > 0.0:
		db += OFFSCREEN_DB + (MARGIN_DB - OFFSCREEN_DB) * past / VIEW_MARGIN
	else:
		db += EDGE_DB * maxf(absf(dx) / hw, absf(dz) / hh)
	return {"heard": true, "db": db, "pan": clampf(dx / hw, -1.0, 1.0) * PAN_MAX}


func _pan_bus(pan: float) -> String:
	return PAN_BUSES[clampi(roundi(pan / PAN_STEP), -2, 2)]


func _prune(now: float) -> void:
	_voices = _voices.filter(func(v): return float(v["end"]) > now)
	for category in _starts:
		_starts[category] = (_starts[category] as Array).filter(func(at): return float(at) > now - 1.0)


static func _no(id: String, reason: String) -> Dictionary:
	return {"play": false, "id": id, "reason": reason}


# ------------------------------------------------------------------ which sound an event makes

## A shot's sound by its attacker: every alien weapon is plasma; a human shell gun (tank, anti-armour, capital) a cannon;
## the rest (infantry, the gunship's burst, turrets, an unknown shooter) a rifle.
static func weapon_for(kind: String, owner: int) -> String:
	if owner != 0:
		return "plasma_bolt"
	return "cannon" if kind in ["Tank", "AntiArmor", "Capital"] else "rifle"


## An acknowledgement bark by unit class.
static func ack_for(kind: String) -> String:
	match kind:
		"Tank", "Harvester", "Capital":
			return "ack_vehicle"
		"Helicopter":
			return "ack_air"
	return "ack_infantry"


## The bed a moving unit adds ("" for anything that does not move).
static func loop_for(kind: String) -> String:
	match kind:
		"Helicopter":
			return "rotor_loop"
		"Tank", "Harvester", "Capital":
			return "tread_loop"
		"Infantry", "AntiArmor":
			return "foot_loop"
	return ""


## A death: a building collapses; a squad goes in a small blast, a vehicle or gunship in a large one.
static func death_sound(kind: String, category: String) -> String:
	if category == "building":
		return "collapse"
	return "explosion_small" if kind in ["Infantry", "AntiArmor", ""] else "explosion_large"


## A hit by its WorldFx weight class: a light round's hit is already in its shot's sound; a heavy one bursts.
static func hit_sound(weight: int) -> String:
	return "explosion_small" if weight >= 2 else ""
