extends RefCounted
## The mock boards' sample data as view models. Used by the gallery and by tests, never by the live game.
const SPR := "res://assets/ui/sprites/"


static func hud_main() -> Dictionary:
	return {
		"brand": {"title": "Ascension", "sub": "Era 1 / Earthfront"},
		"chips": [
			{"icon": "material", "tone": "cyan", "label": "Material", "value": "840"},
			{"icon": "ore", "tone": "cyan", "label": "Ore buffer", "value": "210 / 300"},
			{"icon": "power", "tone": "warn", "label": "Power", "value": "160 / 168 kW", "state": "warn"},
			{"icon": "battery", "tone": "good", "label": "Battery", "value": "62%"},
			{"icon": "crew", "tone": "cyan", "label": "Crew", "value": "22 / 60"},
			{"icon": "ammo", "tone": "cyan", "label": "Ammo supply", "value": "72%"},
			{"icon": "flask", "tone": "violet", "label": "Reserved", "value": "FACTORY 01"},
		],
		"wave": {"label": "Wave 02 Siege", "timer": "T-00:45"},
		"speed": {"rate": 1, "paused": false},
		"objectives": {"cap": "Operation Dawnshield", "items": [
			{"t": "Establish a supplied base", "state": "done"},
			{"t": "Hold wave 02 and commission Factory 02", "state": "active"},
			{"t": "Optional: disable relay A and relay B", "state": "todo"},
			{"t": "Destroy the alien Core Node", "state": "todo"},
		]},
		"power_tip": {
			"title": "Grid deficit 8 kW", "tag": "Throttling industry",
			"body": "Delivered 160 kW against 168 kW requested. Defences and construction keep priority; industry and research share the shortfall.",
			"producers": [{"n": "Reactor A", "v": "100"}, {"n": "Reactor B", "v": "60"}],
			"consumers": [{"n": "Vehicle factory", "v": "40"}, {"n": "Lab", "v": "30"}, {"n": "Refinery", "v": "24"}],
			"cta": "Build reactor", "cta_key": "P",
		},
		"wave_card": {
			"tag": "Doctrine committed", "eta": "Arrives in 00:45",
			"title": "Siege wave: observed walls and tanks",
			"body": "Estimate: 2 artillery, 4 heavy escorts, 8 raiders. Composition stays an estimate until confirmed. Support: 2 relays operating.",
		},
		"alerts": [
			{"tone": "bad", "hostile": true, "title": "Wave 02 committed", "body": "Siege, 14 units, east entry"},
			{"tone": "warn", "icon": "power", "title": "Power short by 8 kW", "body": "Factory 02 build throttled"},
			{"tone": "cyan", "icon": "ore", "title": "Ore field A 62% left", "body": "Finite deposit, plan expansion"},
		],
		"minimap": {"keys": [{"k": "Pwr", "on": true}, {"k": "Sup", "on": false}, {"k": "Thr", "on": true}]},
		"map_marks": {
			"marks": [
				{"x": 0.18, "y": 0.28, "k": "f"}, {"x": 0.27, "y": 0.38, "k": "f"}, {"x": 0.15, "y": 0.42, "k": "f"},
				{"x": 0.35, "y": 0.35, "k": "f"}, {"x": 0.32, "y": 0.49, "k": "f"}, {"x": 0.67, "y": 0.28, "k": "e"},
				{"x": 0.72, "y": 0.18, "k": "h"}, {"x": 0.79, "y": 0.26, "k": "h"}, {"x": 0.76, "y": 0.34, "k": "h"},
				{"x": 0.80, "y": 0.62, "k": "H"}, {"x": 0.87, "y": 0.80, "k": "H"},
			],
			"view": {"x": 0.14, "y": 0.08, "w": 0.55, "h": 0.60},
		},
		"selection": {
			"name": "Vanguard", "count": "11 units", "sub": "Wedge formation / face north-east",
			"groups": [
				{"id": "tank", "sprite": SPR + "tank_v2.png", "label": "TANK x4", "ratio": 0.84, "tone": "good", "on": true},
				{"id": "at", "sprite": SPR + "anti_armor_v2.png", "label": "AT x3", "ratio": 1.0, "tone": "good"},
				{"id": "inf", "sprite": SPR + "infantry_v2.png", "label": "INF x4", "ratio": 0.61, "tone": "warn"},
			],
			"footer": "Tab cycles subgroup / Ctrl+1 stores group",
			"rows": [
				{"label": "Health, average", "value": "82%", "ratio": 0.82, "bar": "good"},
				{"label": "Ammunition carried", "value": "72 / 90 rounds", "ratio": 0.80, "bar": "cyan"},
				{"label": "Supply path", "value": "Connected, depot 02, 14 s", "tone": "good"},
				{"label": "Current order", "value": "Attack-move, ridge", "tone": "cyan"},
				{"label": "Queued", "value": "Hold at checkpoint"},
			],
			"preview": "AT shot 90 x (1 - 0.10) = 81 HP vs alien heavy armour",
			"orders": [
				{"label": "Attack-move", "key": "A", "primary": true, "action": "order", "arg": "attack_move"},
				{"label": "Stop", "key": "S", "action": "order", "arg": "stop"},
				{"label": "Hold", "key": "Shift S", "action": "order", "arg": "hold"},
				{"label": "Resupply", "key": "R", "action": "order", "arg": "resupply"},
				{"label": "Focus group", "key": "F", "wide": true, "action": "order", "arg": "focus"},
			],
		},
		"deck": {
			"tabs": [
				{"id": "build", "label": "Build", "icon": "build"},
				{"id": "units", "label": "Units", "icon": "units", "on": true},
				{"id": "orders", "label": "Orders", "icon": "orders"},
				{"id": "science", "label": "Science", "icon": "flask"},
				{"id": "logistics", "label": "Logistics", "icon": "logistics"},
			],
			"body": {
				"title": "Barracks / rally set", "right": "Costs: material / work / kW / crew",
				"cards": [
					{"sprite": SPR + "infantry_v2.png", "name": "Riflemen", "key": "T", "cost": "60 / 8 s / 4 / 1", "on": true, "action": "train", "arg": "infantry"},
					{"sprite": SPR + "anti_armor_v2.png", "name": "Rocket", "key": "V", "cost": "90 / 10 s / 6 / 1", "action": "train", "arg": "anti_armor"},
					{"sprite": SPR + "tank_v2.png", "name": "Tank", "key": "K", "cost": "240 / 30 s / 20 / 2", "action": "train", "arg": "tank"},
					{"sprite": SPR + "helicopter_v2.png", "name": "Gunship", "key": "H", "cost": "Needs airfield", "cost_tone": "warn", "locked": true},
				],
				"queue": [
					{"label": "Tank", "ratio": 0.62, "on": true},
					{"label": "Rocket", "ratio": 0.0},
					{"label": "Rocket", "ratio": 0.0},
					{"label": "Empty", "empty": true},
					{"label": "Empty", "empty": true},
				],
				"status": {"tag": "Throttled", "tone": "warn", "text": "Grid deficit 8 kW. Tank line runs at 95%."},
			},
		},
	}
