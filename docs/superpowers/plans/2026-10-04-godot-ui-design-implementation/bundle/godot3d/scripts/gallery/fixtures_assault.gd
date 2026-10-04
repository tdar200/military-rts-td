extends RefCounted
## CoreAssault.dc.html's sample data as view models and world marks. Gallery and tests only, never the live game.
const SPR := "res://assets/ui/sprites/"


static func hud() -> Dictionary:
	return {
		"as_top": {
			"groups": [
				[
					{"icon": "material", "tone": "cyan_hi", "text": "MATERIAL 1,240"},
					{"icon": "bolt_alt", "tone": "good", "text": "POWER 212 / 240 kW"},
					{"icon": "crew_alt", "tone": "cyan_hi", "text": "CREW 41 / 60"},
				],
				[
					{"icon": "target", "tone": "bad", "border": "bad", "text": "CORE 4,800 / 12,000 HP"},
					{"icon": "relay", "tone": "warn", "text": "RELAYS 1 / 2 active"},
					{"icon": "home", "tone": "warn", "border": "warn", "text": "HQ 72% integrity"},
					{"icon": "tower", "tone": "warn", "text": "AMMO 61%"},
				],
			],
			"right": [
				{"icon": "clock_alt", "tone": "warn", "border": "warn", "text": "NEXT WAVE 01:52"},
				{"icon": "", "text": "SPEED 1x", "dim": true},
			],
		},
		"as_boss": {"name": "Alien Core Node", "hp_text": "4,800 / 12,000 HP", "ratio": 0.4, "phase": "Phase 3 of 4: charge cycle", "retaliation": "Retaliation in 5 s"},
		"as_objective": {
			"cap": "Objective", "tag": "Operation Dawnshield", "title": "Destroy the Core Node",
			"body": "Ends the Earth operation. Relay destruction cuts reinforcements but is optional.",
			"steps": [
				{"t": "Suppress AA", "state": "done"},
				{"t": "Clear the AT screen", "state": "done"},
				{"t": "Move tanks up", "state": "now"},
				{"t": "Protect the forward depot", "state": "next"},
				{"t": "Focus the exposed Core", "state": "next"},
			],
		},
		"as_relays": {"items": [{"name": "Relay A", "state": "destroyed"}, {"name": "Relay B", "state": "powered"}], "note": "Each powered relay adds two units to every expedition."},
		"as_edge": {"title": "HQ under raid", "lines": ["HQ 72% integrity", "Space: jump camera"], "action": "jump_hq"},
		"as_bottom": {
			"layers": [{"id": "tactical", "label": "Tactical", "on": true}, {"id": "regional", "label": "Regional"}, {"id": "planetary", "label": "Planetary"}],
			"slot_fill": "#1f2219",
			"alerts": [
				{"tone": "bad", "marker": "diamond", "label": "HQ under raid", "time": "0:12", "action": "jump_hq"},
				{"tone": "bad", "marker": "diamond", "label": "Core charging", "time": "5 s", "time_tone": "bad_soft"},
				{"tone": "warn", "marker": "icon", "icon": "warning_alt", "label": "Ammo 61%, depot link ok", "time": "0:41"},
				{"tone": "good", "marker": "dot", "dim": true, "label": "Relay A destroyed", "time": "3:08"},
			],
		},
		"as_selection": {
			"name": "Vanguard", "sub": "18 units / wedge / face NE", "tag": "Attack-move active",
			"groups": [
				{"id": "tank", "sprite": SPR + "tank_v2.png", "label": "TANK 4", "ratio": 0.81},
				{"id": "at", "sprite": SPR + "anti_armor_v2.png", "label": "AT 3", "ratio": 0.64, "tone": "warn"},
				{"id": "inf", "sprite": SPR + "infantry_v2.png", "label": "INF 8", "ratio": 0.72},
				{"id": "aa", "sprite": SPR + "aa_turret_v2.png", "label": "AA 2", "ratio": 0.90},
				{"id": "air", "sprite": SPR + "helicopter_v2.png", "label": "AIR 1", "ratio": 0.48, "tone": "warn"},
			],
			"stats": [
				{"label": "Ammunition", "kind": "bar", "ratio": 0.61, "value": "61%", "tone": "warn"},
				{"label": "Supply path", "text": "Connected, 2 hops to depot", "tone": "good"},
				{"label": "Order, then queued", "text": "Move up, then focus Core"},
			],
		},
		"deck": {"body": {
			"kind": "assault_orders",
			"tabs": [{"id": "build", "label": "Build"}, {"id": "units", "label": "Units"}, {"id": "orders", "label": "Orders", "on": true}, {"id": "science", "label": "Science"}, {"id": "logistics", "label": "Logistics"}],
			"orders": [
				{"label": "Attack-move", "key": "A", "action": "order", "arg": "attack_move", "tone": "primary"},
				{"label": "Stop", "key": "S", "action": "order", "arg": "stop"},
				{"label": "Hold", "key": "H", "action": "order", "arg": "hold"},
				{"label": "Focus", "key": "F", "action": "order", "arg": "focus"},
				{"label": "Resupply", "key": "R", "action": "order", "arg": "resupply", "tone": "warn"},
				{"label": "Spread", "key": "Z", "action": "order", "arg": "spread"},
				{"label": "Queue", "key": "Shift", "action": "order", "arg": "queue"},
				{"label": "HQ", "key": "Home", "action": "order", "arg": "hq"},
			],
			"hint": "Right-click previews its meaning before confirming. Ctrl+1 stores this group.",
		}},
		"as_vignette": {"strength": 0.45},
	}


## Screen-space marks at the mock's 1920x1080 coordinates.
static func marks() -> Array:
	return [
		{"kind": "impact", "x": 690, "y": 570, "r": 215, "inner": 150},
		{"kind": "link", "x": 395, "y": 700, "c1": [430, 700], "c2": [450, 690], "to": [478, 672]},
		{"kind": "link", "x": 395, "y": 720, "c1": [330, 760], "c2": [300, 790], "to": [285, 800], "dim": true},
		{"kind": "hostile", "x": 1338, "y": 154, "hp": 0.40, "w": 70},
		{"kind": "hostile", "x": 1576, "y": 144, "hp": 0.62, "w": 50},
		{"kind": "hostile", "x": 1067, "y": 206, "hp": 0.55, "w": 50},
		{"kind": "hostile", "x": 1047, "y": 414, "hp": 0.90, "w": 50},
		{"kind": "hostile", "x": 1124, "y": 324, "hp": 1.0, "w": 40},
		{"kind": "hostile", "x": 1429, "y": 442, "hp": 0.35, "w": 46},
		{"kind": "hostile", "x": 1278, "y": 532, "hp": 0.80, "w": 50},
		{"kind": "callout", "x": 252, "y": 568, "title": "Forward depot", "sub": "186 rounds"},
		{"kind": "ring", "x": 640, "y": 520},
		{"kind": "ring", "x": 720, "y": 588},
		{"kind": "ring", "x": 580, "y": 598},
		{"kind": "ring", "x": 660, "y": 660},
		{"kind": "brackets", "x": 436, "y": 370, "w": 508, "h": 382},
		{"kind": "arrow", "x": 930, "y": 470, "c1": [990, 430], "c2": [1030, 400], "to": [1050, 372]},
		{"kind": "arrow", "x": 900, "y": 590, "c1": [960, 580], "c2": [1000, 560], "to": [1075, 520]},
		{"kind": "arrow", "x": 1100, "y": 340, "c1": [1140, 300], "c2": [1170, 290], "to": [1215, 300], "queued": true},
		{"kind": "arrow", "x": 1120, "y": 500, "c1": [1160, 470], "c2": [1190, 450], "to": [1235, 420], "queued": true},
		{"kind": "beam", "x": 1565, "y": 215, "c1": [1320, 150], "c2": [900, 220], "to": [705, 555]},
		{"kind": "countdown", "x": 690, "y": 570, "value": 5, "total": 8},
		{"kind": "callout", "x": 520, "y": 340, "tag": "Impact zone", "tag_tone": "bad", "text": "Disperse or destroy the emitter", "border": "bad"},
		{"kind": "callout", "x": 1560, "y": 292, "w": 236, "title": "Core emitter", "tag": "Interruptible", "tag_tone": "bad", "ratio": 0.62, "body": "62% integrity. Destroy it to cancel the charge. 8 s warning, no screen-wide kill.", "tone": "bad"},
		{"kind": "callout", "x": 1090, "y": 690, "tag": "AA + AT screen", "tag_tone": "bad", "text": "4 anti-air and anti-armour guards remain"},
		{"kind": "badge", "x": 1216, "y": 268, "text": "2"},
	]
