extends RefCounted
## What the client itself observes during a mission, for the debrief. The bridge snapshot has no history, so
## casualties, the material curve and the interruption record are kept here. Nothing is invented: no samples, no chart.
const SAMPLE_EVERY := 5.0
const MAX_SAMPLES := 720

var samples: Array = []        # {t, money, gen, demand, ammo, hq}; t is operation seconds
var produced: Dictionary = {}  # unit kind -> count produced by the player after the opening state
var lost: Dictionary = {}     # unit kind -> count of the player's units destroyed
var wave_times: Array = []
var relay_times: Array = []
var relays_total := 0
var _next_sample := 0.0
var _waves := 0
var _relays := -1


## Call every frame with the game node (or a stub). Cheap: it only records every SAMPLE_EVERY seconds.
func observe(g) -> void:
	var t: float = float(g.bridge_tick) / 30.0
	relays_total = maxi(relays_total, g.bridge_relays)
	if _relays >= 0 and g.bridge_relays < _relays:
		for i in _relays - g.bridge_relays:
			relay_times.append(t)
	_relays = g.bridge_relays
	if g.bridge_waves > _waves:
		wave_times.append(t)
		_waves = g.bridge_waves
	if t < _next_sample:
		return
	_next_sample = t + SAMPLE_EVERY
	samples.append({"t": t, "money": g.bridge_money, "gen": g.bridge_power_generation, "demand": g.bridge_power_demand, "ammo": g.bridge_depot_ammo, "hq": hq_ratio(g)})
	if samples.size() > MAX_SAMPLES:
		var thinned: Array = []
		for i in samples.size():
			if i % 2 == 0:
				thinned.append(samples[i])
		samples = thinned
		_next_sample = t + SAMPLE_EVERY * 2.0


## Command centre health as 0..1, or -1 when the player has none.
static func hq_ratio(g) -> float:
	for node in g.bridge_nodes.values():
		if is_instance_valid(node) and int(node.get_meta("team", -1)) == 0 and String(node.get_meta("kind_name", "")) == "CommandCenter":
			return clampf(float(node.get_meta("hp", 0.0)) / maxf(1.0, float(node.get_meta("max_hp", 1.0))), 0.0, 1.0)
	return -1.0


func unit_added(kind: String, team: int, category: String) -> void:
	if team == 0 and category == "unit":
		produced[kind] = int(produced.get(kind, 0)) + 1


func unit_removed(kind: String, team: int, category: String) -> void:
	if team == 0 and category == "unit":
		lost[kind] = int(lost.get(kind, 0)) + 1
