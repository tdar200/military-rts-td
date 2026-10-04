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


const SPR := "res://assets/ui/sprites/"


## Board 4 (StructureSelected): Barracks 04 selected. The board's per-unit queue names, "Queue cost", "Cancel last", "Supply
## range", "Ore +4" and the rally walk time have no data and are not here; the queue is the running job and a queued count.
static func structure_board() -> Dictionary:
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "land"},
		"site": {"cap": "Barracks 04 site", "rows": [
			{"label": "Terrain", "value": "Grassland", "tone": ""},
			{"label": "Forest edge", "value": "3 tiles S, 20% cover", "tone": ""},
			{"label": "Ford", "value": "18 tiles E", "tone": ""},
		]},
		"structure": {
			"id": 50, "kind": "Barracks", "name": "Barracks 04", "sprite": SPR + "barracks_v2.png",
			"tag": {"text": "Online", "tone": "good"},
			"hp": {"now": 480, "max": 480, "ratio": 1.0, "tone": "good"},
			"rows": [
				{"label": "Power", "value": "100% supplied", "tone": "good"},
				{"label": "Output", "value": "1 unit / 18 s", "tone": ""},
				{"label": "Rally", "value": "River bank", "tone": "good"},
			],
			"queue": {"cells": [{"name": "Infantry", "ratio": 0.38, "note": "0:11", "sprite": SPR + "infantry_v2.png"}], "queued": 2},
			"buttons": [
				{"label": "Set rally", "action": "set_rally", "arg": 50, "primary": true},
				{"label": "Repair", "key": "U", "action": "order", "arg": "repair"},
				{"label": "Focus building", "key": "F", "action": "order", "arg": "focus"},
				{"label": "Demolish", "key": "Del", "action": "order", "arg": "sell", "danger": true},
			],
		},
	}


## Board 5 (OrdersArmed): nine units selected with attack-move armed. Group names are the board's; the live game names a
## group after its commonest unit. The armed hint is the game's real wording (right click). "Confirm target", "Queue
## waypoint" and "Ford ahead" have no data and are not here.
static func orders_board() -> Dictionary:
	var kinds := [["Tank", "Tank", "tank_v2.png", 0.92], ["Tank", "Tank", "tank_v2.png", 0.74], ["Tank", "Tank", "tank_v2.png", 0.58], ["Tank", "Tank", "tank_v2.png", 1.0],
		["AntiArmor", "Anti-armour", "anti_armor_v2.png", 0.88], ["AntiArmor", "Anti-armour", "anti_armor_v2.png", 0.41],
		["Infantry", "Infantry", "infantry_v2.png", 1.0], ["Infantry", "Infantry", "infantry_v2.png", 0.66], ["AaTurret", "AA", "aa_turret_v2.png", 1.0]]
	var cards: Array = []
	for i in kinds.size():
		var k: Array = kinds[i]
		var ratio: float = k[3]
		cards.append({"id": i + 1, "kind": k[0], "name": k[1], "ratio": ratio, "tone": "bad" if ratio < 0.5 else ("warn" if ratio < 0.75 else "good"), "rank": 0, "sprite": SPR + str(k[2])})
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "land"},
		"armed": {"hint": "Right click a tile to go, Esc to cancel"},
		"control_groups": {"slots": [
			{"n": 1, "count": 9, "label": "Vanguard", "on": true},
			{"n": 2, "count": 3, "label": "Gun line", "on": false},
			{"n": 3, "count": 2, "label": "Harvesters", "on": false},
			{"n": 4, "count": 0, "label": "", "on": false},
		]},
		"roster": {"title": "Vanguard", "count": "9 units", "armed": true, "more": 0, "cards": cards, "standing": "Grassland", "speed": "speed 1.0x", "speed_tone": "good"},
	}


## Board 7 (WaveInbound): Gun turret 01 selected while the next wave is inside its window. The board's hostile count, prong
## count, "Suggested" list, turret targets, ammo percentage and "Fire across the river" row have no data and are not here.
static func wave_board() -> Dictionary:
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "thr"},
		"wave_panel": {"cap": "Wave 02", "tag": "Inbound", "title": "Hold Wyllow Ford", "rows": [
			{"label": "Next wave", "value": "03:20", "tone": "warn"},
			{"label": "Direction", "value": "From the east", "tone": ""},
		]},
		"structure": {
			"id": 61, "kind": "GunTurret", "name": "Gun turret 01", "sprite": SPR + "gun_turret_v2.png",
			"tag": {"text": "Critical", "tone": "bad"},
			"hp": {"now": 128, "max": 320, "ratio": 0.4, "tone": "bad"},
			"rows": [{"label": "Power", "value": "100% supplied", "tone": "good"}],
			"terrain": {"glyph": "g", "title": "River bank, Grassland", "sub": "Tile 17,9 / your territory", "rows": [
				{"label": "Movement", "value": "Foot 100%, vehicles 100%", "tone": ""},
				{"label": "Cover", "value": "None, open ground", "tone": "warn"},
			]},
			"buttons": [
				{"label": "Repair", "key": "U", "action": "order", "arg": "repair", "primary": true},
				{"label": "Focus building", "key": "F", "action": "order", "arg": "focus"},
				{"label": "Demolish", "key": "Del", "action": "order", "arg": "sell", "danger": true},
			],
		},
	}


static func _enemy_cells() -> Array:
	var cells: Array = []
	for i in 8:
		for j in 6:
			cells.append({"u": 0.78 + 0.02 * i, "v": 0.08 + 0.02 * j, "k": "enemy"})
	return cells
