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
