extends RefCounted
## The gameplay boards' sample data (docs/ascension/ui-mocks-gameplay) as view models, with the numbers the boards print.
## Used by the gallery and tests, never by the live game. Only slices the live adapter can really back are present: the
## boards' per-minute income deltas, "+4 haul" and worker tags have no data and are not here.


## Board 1 (Main): base overview, nothing selected, cursor on the ore.
static func main() -> Dictionary:
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "land"},
		"territory": {"tiles": 38, "composition": [
			{"glyph": "g", "name": "Grassland", "pct": 44},
			{"glyph": "m", "name": "Meadow", "pct": 24},
			{"glyph": "t", "name": "Forest", "pct": 14},
			{"glyph": "r", "name": "River", "pct": 10},
			{"glyph": "s", "name": "Shore", "pct": 8},
		]},
		"yields": [{"text": "+168 kW", "tone": "warn"}],
		"inspect": {
			"name": "River bank", "cover_pct": 0, "range_pct": 0, "infantry_pct": 100, "vehicle_pct": 100, "buildable": true,
			"bonus_text": "Ore haul +20%", "x": 21, "y": 10, "glyph": "g", "zone": true, "deposit": {"kind": "Ore", "remaining": 1800},
		},
		"ledger": {"structures": 11, "units": 23, "crew_used": 23, "crew_cap": 60, "battery_pct": 62, "production": [
			{"name": "Barracks", "state": "idle", "note": "queue empty"},
			{"name": "Factory", "state": "busy", "ratio": 0.48, "note": "Tank 0:41"},
			{"name": "Lab", "state": "busy", "ratio": 0.62, "note": "Radar 1:40"},
		]},
		"army": {"count": 12, "idle": 3, "first_idle": 41},
		"idle": {"count": 3, "first_id": 41},
		"alert": {"label": "Wave 03", "seconds": 112},
		"pins": [{"x": 861, "y": 434, "kind": "Ore", "remaining": 1800, "claimed": true, "cell": [21, 10]}],
	}


## Board 2 (BuildDeck): placing a Refinery beside the river. The deck, top strip and queue are the Build screen's own
## (fixtures_build.gd); the board's hatched footprint, "4 x 3 tiles", slope and "Ore +4" have no data and are not here.
static func build_board() -> Dictionary:
	var vm: Dictionary = load("res://scripts/gallery/fixtures_build.gd").build_deck()
	for key in ["build_placement", "build_alerts", "build_minimap", "build_power"]:
		vm.erase(key)
	vm["build_top"] = {
		"era": "Era 01 Contemporary",
		"chips": [
			{"label": "Material", "value": "840"},
			{"label": "Power", "value": "160 / 168 kW", "note": "forecast 185", "note_tone": "warn", "warn": true},
			{"label": "Crew", "value": "23 / 60"},
		],
		"wave": {"label": "Wave 03", "timer": "01:52"},
	}
	vm["minimap"] = {"keys": [], "name": "Kestrel Reach"}
	vm["lens"] = {"on": "land"}
	vm["placing"] = {
		"x": 604, "y": 690, "title": "Refinery", "status": "1 hex is blocked", "tone": "warn",
		"footprint": "Footprint 1 hex on Grassland",
		"rows": [
			{"label": "Ore in range", "value": "Ore, 24,000 left, +20% output", "tone": "good"},
			{"label": "Blocked tile", "value": "Shore, cannot build", "tone": "bad"},
			{"label": "Power", "value": "-25 kW, grid over capacity", "tone": "warn"},
		],
	}
	vm["placement_hint"] = {"right": 1751.0}
	vm["power_grid"] = {
		"y": 560, "value": "185 / 168 kW", "tone": "warn", "over": 17,
		"segments": [{"ratio": 0.70, "tone": "cyan"}, {"ratio": 0.12, "tone": "warn"}, {"ratio": 0.06, "tone": "bad_hatch"}],
		"marker": 0.82, "lead": "17 kW over.", "text": "Build a Reactor beside the river for +12 kW cooling.",
	}
	vm["pins"] = [{"x": 853, "y": 434, "kind": "Ore", "remaining": 24000, "claimed": false, "in_range": true, "cell": [19, 10]}]
	return vm


## Board 3 (CoreAssault): four tanks hover a gun turret. The objective panel, core bar, alerts and orders belong to the
## assault layout (assault/*.gd); the health forecast, "range 7" and "walls in the line" have no data and are not here.
static func assault_board() -> Dictionary:
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "thr", "overlay": {
			"cell": {"w": 0.017, "h": 0.02},
			"cells": _enemy_cells(),
			"route": [{"u": 0.05, "v": 0.5}, {"u": 0.3, "v": 0.42}, {"u": 0.6, "v": 0.2}],
		}},
		"enemy": {"y": 262, "rows": [
			{"label": "Defences", "value": "2 gun, 1 AA, 4 walls", "tone": ""},
			{"label": "Garrison", "value": "8 units", "tone": ""},
			{"label": "Terrain", "value": "Dry flats, Highland", "tone": ""},
			{"label": "Reinforce", "value": "45 s, 10 units", "tone": "warn"},
		]},
		"combat": {"x": 1060, "y": 360, "sub": "4 x Battle tank vs Alien gun turret", "rows": [
			{"label": "Explosive vs Structure", "value": "+50% damage", "tone": "good"},
			{"label": "Veteran rank 2, 2 units", "value": "+20% damage", "tone": "good"},
			{"label": "Standing on Dry flats", "value": "speed +10%", "tone": "good"},
			{"label": "Target on Highland", "value": "-25% damage", "tone": "bad"},
		]},
		"pins": [{"x": 1075, "y": 328, "kind": "Gun turret", "hostile": true}],
	}


static func _enemy_cells() -> Array:
	var cells: Array = []
	for i in 8:
		for j in 6:
			cells.append({"u": 0.78 + 0.02 * i, "v": 0.08 + 0.02 * j, "k": "enemy"})
	return cells
