extends RefCounted
## The Debrief mock board's two columns as view models (sample data, exactly the mock's numbers).


static func victory() -> Dictionary:
	return {
		"variant": "victory",
		"tag": "Debrief / victory",
		"operation": "Operation Dawnshield",
		"status": "Terminal outcome committed once",
		"title": "Core Node destroyed",
		"lede": "The Earth operation is over. Hostile simulation is frozen, and no later shot, refund or build order can change this result.",
		"stats": [
			{"label": "Operation time", "value": "12:01"},
			{"label": "Waves survived", "value": "4"},
			{"label": "Relays down", "value": "2 / 2"},
			{"label": "Technologies", "value": "12 / 12"},
			{"label": "HQ integrity", "value": "72%", "tone": "good"},
		],
		"casualties": {"right": "Lost / produced", "rows": [
			{"name": "Infantry", "lost": 14, "produced": 31},
			{"name": "Anti-armour", "lost": 6, "produced": 12},
			{"name": "Battle tanks", "lost": 5, "produced": 18},
			{"name": "Gunships", "lost": 2, "produced": 6},
			{"name": "Harvesters", "lost": 1, "produced": 4},
		]},
		"economy": {
			"title": "Material stock",
			"right": "Sample history",
			"series": [[0.0, 261.9], [39.0, 452.4], [89.6, 381.0], [136.4, 654.8], [194.9, 833.3], [268.9, 690.5], [321.5, 1000.0], [380.0, 857.1], [450.1, 1166.7], [506.6, 1309.5], [559.3, 1047.6], [629.4, 1214.3], [682.0, 1333.3], [721.0, 1416.7]],
			"duration": 721,
			"waves": [89.6, 268.9, 450.1, 629.4],
			"marks": [{"t": 380.0, "label": "Relay 1"}, {"t": 559.3, "label": "Relay 2"}],
			"final_label": "1,420",
			"y_max": 1500,
			"note": "W marks a wave arrival. Diamonds mark relay outposts destroyed.",
		},
		"teaser": {
			"title": "Off-world command signature detected",
			"tag": "Narrative / not playable",
			"body": "A transmission pattern routes beyond Earth orbit. The Solar chapter is design only.",
		},
		"footer": "Final state hash 11859179164159499449 / tick 21,642 / seed 2026 / sample data",
		"buttons": [
			{"label": "Next horizon", "action": "continue", "primary": true},
			{"label": "Replay", "action": "replay"},
			{"label": "Restart", "action": "restart"},
		],
	}


static func defeat() -> Dictionary:
	return {
		"variant": "defeat",
		"divider": true,
		"tag": "Debrief / defeat",
		"operation": "Operation Dawnshield",
		"status": "Alien Core Node survived at 4,800 / 12,000 HP",
		"title": "Headquarters lost",
		"lede": "The invasion broke the base at 08:55. Here is the chain that led there and what to change.",
		"chips": [
			{"label": "Last supply cut", "value": "07:40", "tone": "bad"},
			{"label": "Production pauses", "value": "1 / 35 s", "tone": "warn"},
			{"label": "Power deficit", "value": "01:20 total", "tone": "warn"},
		],
		"timeline": {
			"title": "What failed",
			"range": "06:00 to 09:00 / sample data",
			"rows": [
				{"label": "Supply route", "segments": [
					{"from": 0.0, "to": 0.5556, "text": "Connected", "tone": "ok"},
					{"from": 0.5556, "to": 1.0, "text": "Route 02 severed 07:40", "tone": "bad"}]},
				{"label": "Depot ammo", "segments": [
					{"from": 0.0, "to": 0.5556, "text": "Stocked", "tone": "ok"},
					{"from": 0.5556, "to": 0.8333, "text": "Draining", "tone": "warn"},
					{"from": 0.8333, "to": 1.0, "text": "Empty 08:30", "tone": "bad"}]},
				{"label": "Power", "segments": [
					{"from": 0.0, "to": 0.3333, "text": "Balanced", "tone": "ok"},
					{"from": 0.3333, "to": 0.7778, "text": "Deficit 07:00 to 08:20", "tone": "warn"},
					{"from": 0.7778, "to": 1.0, "text": "Balanced", "tone": "ok"}]},
				{"label": "Production", "segments": [
					{"from": 0.0, "to": 0.5, "text": "Running", "tone": "ok"},
					{"from": 0.5, "to": 0.6944, "text": "Paused", "tone": "bad"},
					{"from": 0.6944, "to": 1.0, "text": "Running", "tone": "ok"}]},
				{"label": "Defences", "segments": [
					{"from": 0.0, "to": 0.7778, "text": "Firing", "tone": "ok"},
					{"from": 0.7778, "to": 0.9722, "text": "No rounds", "tone": "bad"}]},
				{"label": "HQ integrity", "marker": 0.9722, "segments": [
					{"from": 0.0, "to": 0.7222, "text": "Intact", "tone": "ok"},
					{"from": 0.7222, "to": 0.9722, "text": "Under attack", "tone": "warn"}]},
			],
			"ticks": [{"at": 0.0, "t": "06:00"}, {"at": 0.31825, "t": "07:00"}, {"at": 0.65109, "t": "08:00"}],
			"end": {"t": "08:55 HQ destroyed", "tone": "bad"},
		},
		"chain": ["Route cut", "Depot drained", "Rounds exhausted", "Firing stopped", "HQ breached"],
		"advice": [
			"Place a forward depot beyond the bridge before the siege wave commits.",
			"Add a Reactor or Battery before the second Vehicle Factory to keep defences powered.",
			"Hold a mobile reserve near the headquarters for the late raid.",
		],
		"buttons": [
			{"label": "Retry from checkpoint", "action": "continue", "primary": true},
			{"label": "Review replay", "action": "replay"},
			{"label": "Restart", "action": "restart"},
		],
	}
