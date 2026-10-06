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


## Board 8 (MapOverlays): the Logistics tab on the Supply lens, whose list the board shows in the deck. The data is the
## committed Kestrel snapshot with the player's base laid out where the board draws it plus a supply_links array in the
## bridge's shape; legend, summary, rows and marks come from overlay_feed.gd, the same code the live game runs. Not built
## (no data): the board's route names and ETAs, the grid ledger, node pins, tile-yield numbers, alert rows. The board draws
## the alien base's borders, so it reads the EARTHFRONT_FOG=0 twin of the snapshot (the fogged start hides that base).
static func logistics_snapshot() -> Dictionary:
	var snap := _kestrel_fog_off()
	var base := [
		[1, "PowerPlant", 4, 6, 1000, {"river_kw": 0}], [2, "PowerPlant", 3, 9, 1000, {"river_kw": 12}], [3, "ResearchLab", 15, 4, 750, {}],
		[4, "Refinery", 14, 9, 1000, {"ore_bonus": true}], [5, "Barracks", 10, 11, 300, {}], [6, "GunTurret", 17, 6, 1000, {}],
		[7, "GunTurret", 21, 10, 1000, {}], [8, "SupplyDepot", 8, 2, 1000, {}], [9, "SupplyDepot", 12, 10, 1000, {}],
	]
	var entities: Array = []
	var services: Array = []
	for row in base:
		var sx: float = float(row[2]) * 0.75 + 0.5
		var sz: float = float(row[3]) + 0.5 + (0.5 if int(row[2]) % 2 != 0 else 0.0)
		var e := {"id": row[0], "owner": 0, "category": "building", "kind": row[1], "x_bits": int(sx * 65536.0), "z_bits": int(sz * 65536.0),
			"construction": 0, "idle": false}
		e.merge(row[5], true)
		entities.append(e)
		services.append({"id": row[0], "power": row[4], "ammo": 90, "stock": 0, "ore": 0, "ore_capacity": 300, "prototype": false, "alien_relay": false})
	snap["entities"] = entities + (snap["entities"] as Array).filter(func(e): return int(e["owner"]) != 0)
	snap["services"] = services
	snap["supply_links"] = [
		{"depot": 9, "target": 4, "state": "ok"}, {"depot": 9, "target": 5, "state": "severed"},
		{"depot": 8, "target": 1, "state": "ok"}, {"depot": 8, "target": 3, "state": "ok"},
	]
	return snap


static func logistics_board() -> Dictionary:
	var feed = load("res://scripts/world/overlay_feed.gd")
	var snap := logistics_snapshot()
	var drawn: Array = feed.marks(snap, "supply")
	var lenses: Array = []
	for id in feed.available(snap):
		lenses.append({"id": id, "label": feed.LABELS[id], "on": id == "supply"})
	return {
		"minimap": {"keys": [], "name": "Kestrel Reach"},
		"lens": {"on": "land"},
		"deck": {
			"tabs": [{"id": "build", "label": "Build", "icon": "build"}, {"id": "units", "label": "Units", "icon": "units"},
				{"id": "orders", "label": "Orders", "icon": "orders"}, {"id": "science", "label": "Science", "icon": "flask"},
				{"id": "logistics", "label": "Logistics", "icon": "logistics", "on": true}],
			"body": {"kind": "logistics", "lenses": lenses, "lens": "supply", "legend": feed.legend(snap, "supply"),
				"summary": feed.summary(snap, "supply", drawn), "note": feed.note("supply"), "routes": feed.routes(snap)},
		},
	}


## The overlay marks of board 8 in screen pixels, through a flat stand-in projector (no 3D scene in the gallery).
static func logistics_marks() -> Array:
	var feed = load("res://scripts/world/overlay_feed.gd")
	var project := func(x: int, y: int) -> Vector2: return Vector2(60.0 + x * 42.0, 80.0 + y * 52.0 + (26.0 if x % 2 != 0 else 0.0))
	var snap := logistics_snapshot()
	var hex: Array = feed.marks(snap, "power") + feed.marks(snap, "supply") + feed.marks(snap, "borders") + feed.marks(snap, "coverage") + feed.marks(snap, "yield")
	return feed.project(hex, project)


static func _enemy_cells() -> Array:
	var cells: Array = []
	for i in 8:
		for j in 6:
			cells.append({"u": 0.78 + 0.02 * i, "v": 0.08 + 0.02 * j, "k": "enemy"})
	return cells


## Board 9 (PauseMenu): the committed Kestrel snapshot at the board's clock (14:36 elapsed, next wave 01:52, 840 material,
## 160 / 168 kW), run through the same vm_gameplay.pause() the live game uses, in the Restart confirmation state the board
## shows. Not built (no feature): the Objective and Last save rows, Settings, Save and keep playing.
static func pause_board() -> Dictionary:
	var snap: Dictionary = JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())
	var tps: int = load("res://scripts/ui/live_adapter.gd").TICKS_PER_SECOND
	snap["tick"] = (14 * 60 + 36) * tps
	snap["next_wave_ticks"] = (60 + 52) * tps
	snap["money_bits"] = 840 * 65536
	snap["power_generation"] = 160
	snap["power_demand"] = 168
	snap["waves_survived"] = 1
	var vm: Dictionary = load("res://scripts/ui/vm_gameplay.gd").pause(snap, 4, true)
	vm["confirm"] = "restart"
	vm["can_restart"] = true
	return vm


## Board 10 (Controls): the one keybinding list, opened from the pause menu.
static func controls_board() -> Dictionary:
	return load("res://scripts/ui/keybinds.gd").vm(true)


static func _kestrel() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


## The same start with the bridge's fog off (EARTHFRONT_FOG=0): the whole alien base, an all-visible mask.
static func _kestrel_fog_off() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot_fog_off.json", FileAccess.READ).get_as_text())


## Board 11 (RegionMap): the committed Kestrel snapshot at the board's clock (wave 03 due in 01:52), through the same
## vm_maps.region_map() the live game runs, from the EARTHFRONT_FOG=0 twin: the board shows the whole alien side, which the
## fogged start hides (the live map shrouds unseen hexes and adds an Explored row; test_fog covers that). Not built (no
## data): Unexplored and Islet pins, Resources seen, Yields per minute, Next goals, scale bar and compass.
static func region_board() -> Dictionary:
	var snap := _kestrel_fog_off()
	var tps: int = load("res://scripts/ui/live_adapter.gd").TICKS_PER_SECOND
	snap["waves_survived"] = 2
	snap["next_wave_ticks"] = (60 + 52) * tps
	var ground = load("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	return load("res://scripts/ui/vm_maps.gd").region_map(snap, ground)


## Board 12 (TerrainGuide): the Kestrel ground_table and regions through vm_maps.terrain_guide(). The board's -25% across the
## river, Fog rule, Codex tabs and map-image swatches are not built.
static func guide_board() -> Dictionary:
	var snap := _kestrel()
	var ground = load("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	return load("res://scripts/ui/vm_maps.gd").terrain_guide(snap, ground)


## Board 6 (EarlyMission): the Build layout at the start of the mission with the briefing for tutorial stage 1 (power the
## beachhead). The briefing card is the section under test; the rest is the Build screen's own fixture, with the Kestrel
## start's numbers (material, power, crew) in the top strip. The board's placement card, tile card and "Mission updated" toast
## are other boards' sections or have no data and are not here.
static func early_board() -> Dictionary:
	var snap := _kestrel()
	var vm := build_board()
	for key in ["placing", "power_grid", "placement_hint", "pins"]:
		vm.erase(key)
	vm["build_top"] = {
		"era": "Era 01 Contemporary",
		"chips": [
			{"label": "Material", "value": str(int(snap["money_bits"]) / 65536)},
			{"label": "Power", "value": "%d / %d kW" % [int(snap["power_demand"]), int(snap["power_generation"])]},
			{"label": "Crew", "value": "%d / %d" % [int(snap["supply_used"]), int(snap["supply_cap"])]},
		],
		"wave": {"label": "Wave 01", "timer": "01:30"},
	}
	return vm


static func briefing_board() -> Dictionary:
	return load("res://scripts/ui/vm_maps.gd").briefing(1, _kestrel())
