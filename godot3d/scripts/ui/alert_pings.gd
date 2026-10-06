extends RefCounted
## Kestrel alert pings (pure, no engine state): where the player's own units and buildings were hit. Each hit makes a ring
## on the minimap that pulses for LIFE seconds, and the place joins a short history that Space walks through (newest
## first). The clock is whatever the caller passes: the game passes its effects clock (WorldFx.time), which stands still
## while the sim is paused, so a ring freezes with the game. The pulse is a function of the ring's age alone.
## Only human-owned entities are ever reported (earthfront_3d.gd), so nothing here says where a hidden enemy stands.

## Seconds a ring lives.
const LIFE := 3.0
## A hit within MERGE_TIME seconds of a ring's own hit and MERGE_RADIUS world units of it adds no ring.
const MERGE_TIME := 1.5
## Three tiles at the row pitch (earthfront_3d.HEX_Z = 0.70 world units).
const MERGE_RADIUS := 3.0 * 0.70
## Rings drawn at once; the oldest goes first.
const MAX_LIVE := 6
## Places Space can jump to.
const MAX_HISTORY := 5
## One pulse per second: three in a ring's life.
const PULSE_PERIOD := 1.0
## The last FADE seconds of a ring's life fade it out.
const FADE := 0.6
## A Space press within this many seconds of the last one steps to an older alert; a later one starts at the newest.
const CYCLE_WINDOW := 2.5

## Live and recently expired rings, oldest first: {pos: Vector3, t: float (the clock at the hit)}.
var pings: Array = []
## Ground points of the latest alerts, newest first, no two within MERGE_RADIUS.
var history: Array = []
var _cycle_index := -1
var _cycle_at := -INF


## A human unit or building lost HP at `pos` at clock `now`. True when it made a new ring (false: merged into a recent one).
func hit(pos: Vector3, now: float) -> bool:
	var at := Vector3(pos.x, 0.0, pos.z)
	_prune(now)
	for p in pings:
		if now - float(p["t"]) < MERGE_TIME and now >= float(p["t"]) and _near(p["pos"], at):
			return false
	pings.append({"pos": at, "t": now})
	while pings.size() > MAX_LIVE:
		pings.pop_front()
	for i in range(history.size() - 1, -1, -1):
		if _near(history[i], at):
			history.remove_at(i)
	history.push_front(at)
	while history.size() > MAX_HISTORY:
		history.pop_back()
	return true


## The rings to draw at clock `now`, oldest first: {pos, t, age} with 0 <= age < LIFE.
func live(now: float) -> Array:
	var out: Array = []
	for p in pings:
		var age := now - float(p["t"])
		if age >= 0.0 and age < LIFE:
			out.append({"pos": p["pos"], "t": p["t"], "age": age})
	return out


## True while any ring is live.
func active(now: float) -> bool:
	return not live(now).is_empty()


## Space: the alert to frame. The first press goes to the newest; each press within CYCLE_WINDOW (on `press_time`, the
## caller's real clock) steps one older, wrapping round. Vector3.INF when there is none (the press does nothing).
func jump(press_time: float) -> Vector3:
	if history.is_empty():
		return Vector3.INF
	if press_time - _cycle_at <= CYCLE_WINDOW and _cycle_index >= 0:
		_cycle_index = (_cycle_index + 1) % history.size()
	else:
		_cycle_index = 0
	_cycle_at = press_time
	return history[mini(_cycle_index, history.size() - 1)]


## A ring's look at `age` seconds: phase 0..1 through the current pulse (the ring grows and fades with it) and fade 1..0
## over the last FADE seconds of its life. Deterministic: the same age always draws the same ring.
static func pulse(age: float) -> Dictionary:
	var phase := fposmod(age, PULSE_PERIOD) / PULSE_PERIOD
	return {"phase": phase, "fade": clampf((LIFE - age) / FADE, 0.0, 1.0)}


func _prune(now: float) -> void:
	var keep: Array = []
	for p in pings:
		var age := now - float(p["t"])
		if age < LIFE:
			keep.append(p)
	pings = keep


static func _near(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= MERGE_RADIUS
