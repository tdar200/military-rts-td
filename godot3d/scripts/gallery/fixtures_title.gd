extends RefCounted
## Title screen fixtures. `title()` equals the Title mock's numbers; the others are the edge cases the tests use.
const SPRITES := "res://assets/ui/sprites/"


static func menu(overrides := {}) -> Array:
	var items := [
		{"id": "continue", "label": "Continue campaign", "hint": "Dawnshield 07:12", "icon": "play", "emphasis": "primary"},
		{"id": "new", "label": "New operation", "hint": "Seed 2026", "icon": "plus", "emphasis": "secondary"},
		{"id": "skirmish", "label": "Skirmish sandbox", "hint": "Legacy map", "icon": "crosshair"},
		{"id": "research", "label": "Research archive", "hint": "12 projects", "icon": "flask_title"},
		{"id": "settings", "label": "Settings", "hint": "Remap keys", "icon": "cog"},
		{"id": "quit", "label": "Quit", "hint": "Alt F4", "icon": "restart"},
	]
	for item in items:
		if overrides.has(item["id"]):
			item.merge(overrides[item["id"]], true)
	return items


static func chapters(n := 4) -> Array:
	var base := [
		{"tag": "Eras 3-4", "tag_color": "f0b040", "name": "Solar", "blurb": "Orbital industry, launch mass and transfer windows.", "status": "Design / Locked"},
		{"tag": "Era 5", "tag_color": "78b4ff", "name": "Interstellar", "blurb": "Independent industrial seeds and communication delay.", "status": "Design / Locked"},
		{"tag": "Eras 6-9", "tag_color": "9ad0ff", "name": "Galactic", "blurb": "Sector budgets and autonomous governors.", "status": "Design / Locked"},
		{"tag": "Era 10", "tag_color": "e8f4ff", "name": "Cosmic", "blurb": "Refuge networks and survival under causal limits.", "status": "Design / Locked"},
	]
	var out: Array = []
	for i in n:
		var c: Dictionary = base[i % 4].duplicate()
		if i >= 4:
			c["name"] = "%s %d" % [c["name"], i / 4 + 1]
		out.append(c)
	return out


static func featured() -> Dictionary:
	return {
		"name": "Operation Dawnshield",
		"blurb": "Earthfront. Contemporary Humanity to Advanced Industrial Civilization.",
		"tags": [{"t": "Playable", "tone": "good"}, {"t": "Era 1-2", "tone": "dim"}],
		"art": [
			{"sprite": SPRITES + "command_center_v2.png", "x": 30, "y": -10, "s": 170},
			{"sprite": SPRITES + "tank_v2.png", "x": 190, "y": 30, "s": 130},
			{"sprite": SPRITES + "alien_tank_v1.png", "x": 400, "y": 26, "s": 130},
			{"sprite": SPRITES + "alien_command_center_v1.png", "x": 500, "y": -14, "s": 160},
		],
		"facts": [
			{"k": "Objective", "v": "Destroy the alien Core Node"},
			{"k": "Target length", "v": "25 to 40 minutes"},
			{"k": "Visibility", "v": "Fog of war, scout the alien side"},
			{"k": "Tempo", "v": "Pause and speed control"},
		],
		"primary": {"label": "Continue operation", "action": "operation_continue"},
		"secondary": {"label": "Start over", "action": "operation_restart"},
	}


static func title() -> Dictionary:
	return {
		"backdrop": true,
		"eyebrow": "A real-time science RTS",
		"title": "Ascension",
		"tagline": "Earthfront to the cosmic frontier",
		"menu": menu(),
		"campaign": {
			"title": "Campaign",
			"summary": "5 chapters / 1 playable",
			"featured": featured(),
			"later_title": "Later chapters",
			"later_note": "Design only, not yet built",
			"chapters": chapters(4),
		},
		"footer_left": "DESIGN PREVIEW / Earthfront slice, eras 1-2 / deterministic core, 30 Hz",
		"footer_right": "WASD pan / Wheel zoom / A attack-move / Y research / Esc menu",
	}


## Edge cases, all derived from the mock fixture.
static func with_chapters(n: int) -> Dictionary:
	var vm := title()
	vm["campaign"]["chapters"] = chapters(n)
	vm["campaign"]["summary"] = "%d chapters / 1 playable" % (n + 1)
	return vm


static func long_name() -> Dictionary:
	var vm := title()
	vm["campaign"]["featured"]["name"] = "Operation Dawnshield Resurgence Of The Northern Frontier Garrison"
	return vm


## Gallery arm for the edge-case screens: title_empty, title_1, title_12, title_long, title_disabled.
static func edge(screen: String) -> Dictionary:
	match screen:
		"title_empty":
			return with_chapters(0)
		"title_1":
			return with_chapters(1)
		"title_12":
			return with_chapters(12)
		"title_long":
			return long_name()
		"title_disabled":
			var vm := title()
			vm["menu"] = menu({"continue": {"disabled": true}, "new": {"disabled": true}, "skirmish": {"disabled": true}, "research": {"disabled": true}, "settings": {"disabled": true}, "quit": {"disabled": true}})
			return vm
	return {}
