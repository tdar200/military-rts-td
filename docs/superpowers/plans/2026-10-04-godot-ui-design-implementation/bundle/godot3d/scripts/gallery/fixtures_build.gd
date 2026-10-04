extends RefCounted
## The Build board's sample data (BuildDeck.dc.html) as a view model. Gallery and tests only, never the live game.
const SPR := "res://assets/ui/sprites/"
const Logic = preload("res://scripts/ui/build_logic.gd")


static func card(id: String, name: String, sprite: String, key: String, cost: Array, prereq: String, o := {}) -> Dictionary:
	var d := {"id": id, "name": name, "sprite": SPR + sprite + ".png", "key": key,
		"cost": Logic.format_cost(cost[0], cost[1], cost[2]), "prereq": prereq}
	d.merge(o)
	return d


static func cards() -> Array:
	return [
		card("command_center", "Command Centre", "command_center_v2", "", [600, 600, 20], "Needs: forward site", {"short": true}),
		card("reactor", "Reactor", "power_plant_v2", "P", [220, 240, -80], "Needs: Command Centre"),
		card("refinery", "Refinery", "refinery_v2", "R", [300, 300, 25], "Needs: Command Centre"),
		card("barracks", "Barracks", "barracks_v2", "B", [180, 200, 10], "Needs: Command Centre"),
		card("vehicle_factory", "Vehicle Factory", "barracks_v2", "", [280, 360, 40], "Needs: Barracks", {"selected": true}),
		card("airfield", "Airfield", "helicopter_v2", "", [360, 400, 45], "Needs: Aircraft tech", {"locked": true}),
		card("laser_turret", "Laser Turret", "gun_turret_v2", "G", [150, 120, 15], "Needs: Barracks"),
		card("aa_turret", "AA Turret", "aa_turret_v2", "", [170, 140, 15], "Needs: Air defence", {"locked": true}),
		card("wall", "Wall", "wall_v2", "W", [20, 20, 0], "Needs: Command Centre"),
		card("supply_depot", "Supply Depot", "foundation_v1", "", [140, 160, 8], "Needs: Refinery"),
		card("lab", "Lab", "capital_v1", "", [320, 320, 30], "Needs: Reactor"),
		card("battery", "Battery", "power_plant_v2", "", [160, 180, 6], "Needs: Battery tech", {"locked": true}),
	]


static func build_deck() -> Dictionary:
	var proj := Logic.projection(160, 130, 40)
	return {
		"build_top": {
			"era": "Era 01 Contemporary",
			"chips": [
				{"label": "Material", "value": "840", "note": "planned -280", "note_tone": "warn"},
				{"label": "Power", "value": "130 / 160 kW", "note": "forecast 170", "note_tone": "warn", "warn": true},
				{"label": "Industry", "value": "360", "note": "work reserved"},
				{"label": "Crew", "value": "22 / 60"},
			],
			"wave": {"label": "Wave 01", "timer": "01:12", "note": "doctrine in 00:27"},
			"pause": {"label": "Paused", "key": "Space"},
			"rates": [{"t": "1x", "on": true}, {"t": "2x"}, {"t": "4x"}],
		},
		"build_power": {
			"title": "Forecast deficit 10 kW", "tag": "After commissioning",
			"body": "Producer: Reactor A, 160 kW. Consumers: defences 45, refinery 25, lab 30, command centre 12, barracks 10, supply depot 8, planned Vehicle Factory 40.",
			"buttons": [{"label": "Focus on map", "action": "focus_map"}, {"label": "Plan a Reactor (P)", "action": "arm_build", "arg": "reactor"}],
		},
		"build_alerts": {
			"rows": [
				{"tone": "warn", "icon": "warning", "text": "Placement preview: power forecast"},
				{"tone": "", "icon": "clock", "text": "Supply Depot: materials 12 short"},
			],
			"crumbs": ["Earth", "Earthfront", "Base"],
		},
		"build_minimap": {},
		"map_marks": {"marks": [], "view": {}},
		"build_placement": {
			"sprite": SPR + "barracks_v2.png", "tone": "good", "status": "Valid and affordable",
			"title": "Vehicle Factory / Preview",
			"costs": [{"cap": "Materials", "value": "280"}, {"cap": "Work", "value": "360"}, {"cap": "Power", "value": "40 kW", "tone": "warn"}, {"cap": "Build", "value": "30 s"}],
			"note": "Enter reserves 280 once. Available materials fall from 840 to 560.",
			"grid": {"value": proj["value"], "tone": proj["tone"], "note": "after commissioning", "segments": proj["segments"], "marker": proj["marker"],
				"lead": "%d kW over capacity." % proj["over"] if proj["over"] > 0 else "", "text": "Defences keep priority; industry shares the deficit."},
			"checks": [{"ok": true, "text": "Barracks built"}, {"ok": true, "text": "Inside territory"}, {"ok": true, "text": "Delivery access clear"}],
			"hints": [{"key": "Enter", "label": "confirm"}, {"key": "R", "label": "rotate"}, {"key": "Esc", "label": "cancel"}],
		},
		"build_world": {
			"pins": [],
			"labels": [],
		},
		"deck": {"body": {
			"kind": "build",
			"tabs": [{"id": "build", "label": "Build", "on": true}, {"id": "units", "label": "Units"}, {"id": "orders", "label": "Orders"}, {"id": "science", "label": "Science"}, {"id": "logistics", "label": "Logistics"}],
			"cards": cards(),
			"queue": {"sprite": SPR + "foundation_v1.png", "title": "Queue: Supply Depot", "tag": "Stalled", "tone": "warn",
				"detail": "Waiting: materials 12 short (delivered 128 / 140)", "ratio": 0.91, "ratio_label": "91% delivered"},
		}},
	}


## Edge-case variants of the board: "many" (16 cards, scrolls), "none" (no cards), "locked", "short", "no_queue", "invalid" (failing checks).
static func edge(kind: String) -> Dictionary:
	var vm := build_deck()
	var body: Dictionary = vm["deck"]["body"]
	match kind:
		"many":
			var cards_all: Array = cards()
			for i in 4:
				cards_all.append(card("extra_%d" % i, "Outpost %d" % (i + 1), "wall_v2", "", [90 + i, 80, 5], "Needs: Wall"))
			body["cards"] = cards_all
		"none":
			body["cards"] = []
		"locked":
			var all_locked: Array = []
			for c in cards():
				c["locked"] = true
				c["selected"] = false
				c["short"] = false
				all_locked.append(c)
			body["cards"] = all_locked
		"short":
			var all_short: Array = []
			for c in cards():
				c["short"] = true
				c["locked"] = false
				all_short.append(c)
			body["cards"] = all_short
		"no_queue":
			body["queue"] = {"empty": true, "title": "Queue empty", "detail": "Pick a structure and place it to start building"}
		"invalid":
			var proj := Logic.projection(160, 150, 40)
			vm["build_placement"] = {
				"sprite": SPR + "barracks_v2.png", "tone": "bad", "status": "Blocked",
				"title": "Vehicle Factory / Preview",
				"costs": [{"cap": "Materials", "value": "280", "tone": "bad"}, {"cap": "Work", "value": "360"}, {"cap": "Power", "value": "40 kW", "tone": "bad"}, {"cap": "Build", "value": "30 s"}],
				"note": "Materials 280 needed, 120 available.",
				"grid": {"value": proj["value"], "tone": "bad", "note": "after commissioning", "segments": proj["segments"], "marker": proj["marker"],
					"lead": "%d kW over capacity." % proj["over"], "text": "Defences keep priority; industry shares the deficit."},
				"checks": [{"ok": false, "text": "Barracks built"}, {"ok": true, "text": "Inside territory"}, {"ok": false, "text": "Delivery access clear"}],
				"hints": [{"key": "R", "label": "rotate"}, {"key": "Esc", "label": "cancel"}],
			}
	return vm
