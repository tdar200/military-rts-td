extends RefCounted
## The Research mock's own sample data, as a research_screen view model.


static func _node(id: String, name: String, state: String, col: int, row: int, tags: Array, segments: Array, footer: String, o := {}) -> Dictionary:
	var d := {"id": id, "name": name, "state": state, "col": col, "row": row, "tags": tags, "segments": segments, "footer": {"text": footer, "tone": o.get("footer_tone", "dim")}, "prereqs": o.get("prereqs", [])}
	if o.has("step"):
		d["step"] = o["step"]
	if o.has("note"):
		d["note"] = o["note"]
	return d


static func _done(id: String, name: String, row: int, footer: String, col := 0, o := {}) -> Dictionary:
	return _node(id, name, "implemented", col, row, [{"label": "Established", "tone": "good"}, {"label": "Implemented", "tone": "good"}], [1, 1, 1], footer, o)


static func research() -> Dictionary:
	var nodes: Array = [
		_done("aircraft", "Aircraft", 0, "Airfield"),
		_done("anti_armour", "Guided anti-armour", 1, "Barracks"),
		_done("vehicle_tooling", "Vehicle tooling", 2, "Vehicle factory", 0, {"step": 1}),
		_done("batteries", "Batteries", 3, "Grid storage"),
		_done("field_supply", "Field supply", 4, "Supply depot"),
		_done("air_defence", "Air defence", 0, "AA turret", 1, {"prereqs": ["aircraft"]}),
		_node("precision", "Precision manufacturing", "active", 1, 2, [{"label": "Established", "tone": "good"}, {"label": "In progress", "tone": "cyan"}], [1, 0.45, 0], "Powered lab, built", {"step": 2, "prereqs": ["vehicle_tooling"]}),
		_node("smart_grids", "Smart grids", "available", 1, 3, [{"label": "Engineering", "tone": "blue"}, {"label": "Available", "tone": "cyan"}], [0, 0, 0], "Powered lab", {"prereqs": ["batteries"]}),
		_node("unknown_fn", "Unknown function", "unknown", 2, 0, [{"label": "Unknown", "tone": "violet", "dashed": true}, {"label": "Not studied", "tone": "violet", "dashed": true}], [], "Lab + relay wreck", {"note": "Alien relay emitter. Evidence 0 / 1 wreck analysed. Never labelled discovered.", "prereqs": ["air_defence"]}),
		_node("robotic", "Robotic workcells", "active", 2, 2, [{"label": "Engineering", "tone": "blue"}, {"label": "In progress", "tone": "cyan"}], [0.62, 0, 0], "Factory 01 reserved", {"step": 3, "footer_tone": "warn", "prereqs": ["precision"]}),
		_node("ai_science", "AI-assisted science", "blocked", 2, 3, [{"label": "Engineering", "tone": "blue"}, {"label": "Blocked", "tone": "warn"}], [0, 0, 0], "Needs precision prototype", {"footer_tone": "#f0c872", "prereqs": ["precision", "smart_grids"]}),
		_node("resilience", "Industrial resilience", "planned", 2, 4, [{"label": "Engineering", "tone": "blue"}, {"label": "Planned", "tone": "dim", "dashed": true}], [0, 0, 0], "Smart grid + depots", {"prereqs": ["smart_grids", "field_supply"]}),
		_node("autonomous", "Autonomous supply", "blocked", 3, 2, [{"label": "Engineering", "tone": "blue"}, {"label": "Blocked", "tone": "warn"}], [0, 0, 0], "Needs workcells + AI", {"footer_tone": "#f0c872", "prereqs": ["robotic", "ai_science"]}),
	]
	var eras: Array = []
	var names := ["Contemporary", "Advanced Industrial", "Fusion", "Solar", "Interstellar", "Stellar Eng.", "Post-Biological", "Spacetime", "Galactic", "Cosmic"]
	for i in names.size():
		var item := {"n": i + 1, "name": names[i], "state": "locked"}
		if i == 0:
			item["state"] = "current"
			item["progress"] = 0.86
		elif i == 1:
			item["state"] = "next"
		eras.append(item)
	return {
		"header": {
			"title": "Science",
			"crumbs": [{"label": "Node", "on": true}, {"label": "Domain"}, {"label": "Era"}],
			"close_label": "Close view",
			"chips": [
				{"icon": "bolt_alt", "icon_tone": "warn", "text": "POWER 30 kW needed"},
				{"text": "SCIENCE 62% theory"},
				{"text": "PROTOTYPE 0 / 1"},
				{"icon": "lock", "icon_tone": "warn", "border": "warn", "text": "FACTORY 01 reserved"},
				{"text": "Y close", "tone": "dim"},
			],
		},
		"gate": {
			"label": "Era gate",
			"from": {"n": 1, "name": "Contemporary Humanity"},
			"to": {"n": 2, "name": "Advanced Industrial"},
			"criteria": [
				{"state": "done", "label": "Supplied base held for 120 s", "value": "Done"},
				{"state": "active", "label": "Core wartime projects deployed", "value": "6 / 7", "tone": "#96f5ff"},
				{"state": "todo", "label": "Robotic workcell prototype validated", "value": "0 / 1"},
				{"state": "todo", "label": "First workcell commissioned", "value": "Pending"},
			],
			"note": "The gate tests sustained delivered capacity over an observation window. Knowledge is never revoked if infrastructure is later damaged. Entering Era 2 completes no technology by itself.",
		},
		"filters": {
			"search": {"placeholder": "Search projects", "text": ""},
			"groups": [
				{"id": "state", "title": "State", "row_h": 30, "rows": [
					{"id": "implemented", "label": "Implemented", "icon": "circle_check", "tone": "good", "on": true, "count": 6},
					{"id": "active", "label": "In progress", "icon": "circle_clock", "tone": "cyan", "on": true, "count": 2},
					{"id": "available", "label": "Available", "icon": "circle_plus", "tone": "cyan", "on": true, "count": 1},
					{"id": "blocked", "label": "Blocked", "icon": "lock", "tone": "warn", "on": true, "count": 2},
					{"id": "planned", "label": "Planned", "icon": "flag", "tone": "dim", "on": true, "count": 1},
					{"id": "unknown", "label": "Unknown", "icon": "circle_help", "tone": "violet", "on": true, "count": 1},
				]},
				{"id": "physics", "title": "Physics category", "row_h": 28, "rows": [
					{"id": "mech", "label": "Mechanics and materials", "on": true},
					{"id": "em", "label": "Electromagnetism and power", "on": true},
					{"id": "comp", "label": "Computation and control", "on": true},
					{"id": "thermo", "label": "Thermodynamics", "on": false},
				]},
				{"id": "effect", "title": "Strategic effect", "row_h": 28, "rows": [
					{"id": "defence", "label": "Defence", "on": true},
					{"id": "industry", "label": "Industry and throughput", "on": true},
					{"id": "logistics", "label": "Logistics", "on": true},
					{"id": "gate", "label": "Era gate", "on": true},
				]},
			],
			"honesty": {"title": "Honesty label", "tags": [
				{"label": "Established", "tone": "good"},
				{"label": "Engineering extrapolation", "tone": "blue"},
				{"label": "Speculative", "tone": "violet"},
				{"label": "Unknown", "tone": "violet", "dashed": true},
			]},
		},
		"graph": {
			"nodes": nodes,
			"selected": "robotic",
			"highlight": ["vehicle_tooling", "precision", "robotic"],
			"horizon": {"col": 3, "row": 0, "icon": "lock", "cap": "Horizon", "title": "Era 3\nFusion", "body": "Gate: demonstrate net delivered fusion power, a breeding chain and maintainable components.", "tag": {"label": "Design only", "tone": "dim"}},
			"hint": {"col": 3, "y": 600, "title": "Reading the graph", "body": "Square corner = project. Number badge = step on the highlighted path to Robotic workcells."},
		},
		"zoom": {"value": 0.0, "scale": 1.0, "hint": "Wheel zooms. Far view = eras."},
		"eras": {"title": "Far view: era band", "note": "Milestones, not nodes", "items": eras},
		"detail": {
			"title": "Robotic workcells",
			"state": {"label": "In progress", "tone": "cyan"},
			"tags": [{"label": "Engineering extrapolation", "tone": "blue"}, {"label": "Era gate", "tone": "dim"}, {"label": "Industry", "tone": "dim"}],
			"boxes": [
				{"label": "Theory", "value": "62%", "tone": "hi", "ratio": 0.62},
				{"label": "Prototype", "value": "0 / 1", "tone": "dim", "ratio": 0.0},
				{"label": "Deploy", "value": "Locked", "tone": "dim", "ratio": 0.0},
			],
			"bottleneck": {"title": "Bottleneck", "text": "FACTORY 01 reserved for the prototype. Factory 02 keeps its tank queue. Theory is lab-bound now; more power alone cannot replace experiments."},
			"path": {"title": "Path to capability", "note": "5 steps, shortest feasible", "steps": [
				{"n": 1, "kind": "Research", "label": "Vehicle tooling", "tone": "good", "tag": {"label": "Done", "tone": "good"}},
				{"n": 2, "kind": "Research", "label": "Precision manufacturing", "tag": {"label": "Proto 45%", "tone": "cyan"}},
				{"n": 3, "kind": "Construct", "label": "Powered laboratory, 30 kW", "tone": "good", "tag": {"label": "Built", "tone": "good"}},
				{"n": 4, "kind": "Evidence", "label": "Prototype validated, Factory 01", "tone": "#b8c9d1", "tag": {"label": "Pending", "tone": "dim"}},
				{"n": 5, "kind": "Construct", "label": "Commission first workcell", "tone": "#b8c9d1", "tag": {"label": "Pending", "tone": "dim"}},
			]},
			"retrofit": {"title": "Retrofit per facility (proposed)", "cells": [
				{"label": "Materials", "value": "120"},
				{"label": "Downtime", "value": "20 s"},
				{"label": "Power", "value": "+30 kW", "tone": "warn"},
			]},
			"effect": {"title": "Effect", "text": "Compatible work rate +25% on each retrofitted line. Commissioning the first workcell unlocks Era 2 infrastructure. Existing tanks keep their model and role."},
			"honesty": "Robotics is established; flexible, reliable automation at this scale depends on engineering and energy. Design values, not current balance.",
			"primary": {"label": "Path to capability", "action": "path", "arg": "robotic", "icon": "wave_alt"},
			"secondary": {"label": "Fund theory", "action": "research", "arg": "robotic"},
		},
	}
