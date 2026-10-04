extends RefCounted
## Pure helpers for the Build screen: cost formatting, shortfalls and the projected-grid bar. No nodes, no game state.


## "280 M 360 W 40 kW". `kw` is the draw (positive) or the output (negative, shown as +80 kW).
static func format_cost(material: int, work: int, kw: int) -> String:
	var power := "+%d kW" % -kw if kw < 0 else "%d kW" % kw
	return "%d M %d W %s" % [material, work, power]


static func shortfall(cost: int, have: int) -> int:
	return maxi(0, cost - have)


## The projected-grid bar. Scale is 125% of generation (so capacity sits at 80%), growing if the load would exceed it.
## Segments, left to right: current load (cyan), planned load that still fits (warn), planned load over capacity (bad_hatch).
## `marker` is the capacity line as a 0..1 ratio of the bar.
static func projection(generation: int, demand: int, added: int) -> Dictionary:
	var load_after := demand + added
	var scale := maxf(maxf(generation * 1.25, load_after), 1.0)
	var current := mini(demand, generation)
	var fits := maxi(0, mini(load_after, generation) - current)
	var over := maxi(0, load_after - generation)
	var segments: Array = []
	if current > 0:
		segments.append({"ratio": current / scale, "tone": "cyan"})
	if fits > 0:
		segments.append({"ratio": fits / scale, "tone": "warn"})
	if over > 0:
		segments.append({"ratio": over / scale, "tone": "bad_hatch"})
	return {
		"segments": segments,
		"marker": generation / scale,
		"over": over,
		"value": "%d / %d kW" % [load_after, generation],
		"tone": "warn" if added > 0 else "cyan",
	}
