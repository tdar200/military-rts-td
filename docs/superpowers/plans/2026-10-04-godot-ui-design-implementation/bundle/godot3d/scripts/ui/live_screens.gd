extends RefCounted
## View models for the full-screen layers (title, debrief) from live state. Static text is stated plainly;
## a block whose data does not exist is left out, and the screens close the gap.
const SPR := "res://assets/ui/sprites/"
const UNIT_ROWS := [["Infantry", "Infantry"], ["AntiArmor", "Anti-armour"], ["Tank", "Battle tanks"], ["Helicopter", "Gunships"], ["Harvester", "Harvesters"]]
const SessionLog = preload("res://scripts/ui/session_log.gd")
const FixturesChapters := [
	{"tag": "Eras 3-4", "tag_color": "f0b040", "name": "Solar", "blurb": "Orbital industry, launch mass and transfer windows.", "status": "Design / Locked"},
	{"tag": "Era 5", "tag_color": "78b4ff", "name": "Interstellar", "blurb": "Independent industrial seeds and communication delay.", "status": "Design / Locked"},
	{"tag": "Eras 6-9", "tag_color": "9ad0ff", "name": "Galactic", "blurb": "Sector budgets and autonomous governors.", "status": "Design / Locked"},
	{"tag": "Era 10", "tag_color": "e8f4ff", "name": "Cosmic", "blurb": "Refuge networks and survival under causal limits.", "status": "Design / Locked"},
]


## Title and campaign. `deploy_enabled` is false while the bridge is down.
static func title_vm(deploy_enabled: bool, research_projects: int) -> Dictionary:
	var primary := {"label": "Deploy forces", "action": "deploy", "disabled": not deploy_enabled}
	return {
		"eyebrow": "Earthfront / Era 1",
		"title": "Ascension",
		"tagline": "Hold the Earthfront, then take the fight to the alien Core Node.",
		"menu": [
			{"id": "continue", "label": "Continue campaign", "icon": "play", "disabled": true},
			{"id": "deploy", "label": "New operation", "icon": "plus", "emphasis": "primary", "disabled": not deploy_enabled},
			{"id": "skirmish", "label": "Skirmish sandbox", "icon": "crosshair", "disabled": true},
			{"id": "research", "label": "Research archive", "hint": "%d projects" % research_projects if research_projects > 0 else "", "icon": "flask_title", "disabled": true},
			{"id": "settings", "label": "Settings", "icon": "cog", "disabled": true},
			{"id": "quit", "label": "Quit", "icon": "restart"},
		],
		"campaign": {
			"title": "Campaign", "summary": "1 playable / 4 design",
			"featured": {
				"name": "Operation Dawnshield",
				"blurb": "Earthfront. Contemporary Humanity to Advanced Industrial Civilization.",
				"tags": [{"t": "Playable", "tone": "good"}, {"t": "Era 1-2", "tone": "dim"}],
				"facts": [{"k": "Objective", "v": "Destroy the alien Core Node"}, {"k": "Visibility", "v": "Full battlefield, no fog of war"}],
				"primary": primary,
			},
			"later_title": "Later chapters", "later_note": "Design only",
			"chapters": FixturesChapters,
		},
		"footer_left": "Ascension", "footer_right": "",
	}


static func clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


## Debrief column for the finished mission. `log` is the SessionLog the game kept.
static func debrief_vm(g, log) -> Dictionary:
	var victory: bool = g.bridge_winner == 0
	var elapsed := float(g.bridge_tick) / 30.0
	var buttons: Array = [{"label": "Review battlefield", "action": "review", "primary": true}, {"label": "Redeploy", "action": "restart"}]
	var vm := {
		"variant": "victory" if victory else "defeat",
		"tag": "Debrief / " + ("victory" if victory else "defeat"),
		"operation": "Operation Dawnshield",
		"title": "Core Node destroyed" if victory else "Headquarters lost",
		"buttons": buttons,
		"footer": "Final tick %s" % thousands(g.bridge_tick),
	}
	if victory:
		vm["status"] = "Terminal outcome committed once"
		vm["lede"] = "The alien Core Node has fallen and Earth is secured."
		var stats: Array = [{"label": "Operation time", "value": clock(elapsed)}, {"label": "Waves survived", "value": str(g.bridge_waves)}]
		if log.relays_total > 0:
			stats.append({"label": "Relays down", "value": "%d / %d" % [log.relays_total - g.bridge_relays, log.relays_total]})
		stats.append({"label": "Technologies", "value": "%d / %d" % [g.bridge_research_count, g.bridge_technology_total]})
		var hq: float = SessionLog.hq_ratio(g)
		if hq >= 0.0:
			stats.append({"label": "HQ integrity", "value": "%d%%" % roundi(hq * 100.0), "tone": "good" if hq >= 0.5 else "warn"})
		vm["stats"] = stats
		var rows: Array = []
		for pair in UNIT_ROWS:
			var made := int(log.produced.get(pair[0], 0))
			var gone := int(log.lost.get(pair[0], 0))
			if made > 0 or gone > 0:
				rows.append({"name": pair[1], "lost": gone, "produced": maxi(made, gone)})
		if not rows.is_empty():
			vm["casualties"] = {"right": "Lost / produced", "rows": rows}
		if log.samples.size() >= 2:
			var series: Array = []
			for s in log.samples:
				series.append([s["t"], float(s["money"])])
			var marks: Array = []
			for i in log.relay_times.size():
				marks.append({"t": log.relay_times[i], "label": "Relay %d" % (i + 1)})
			vm["economy"] = {"title": "Material stock", "right": "Recorded this session", "series": series, "duration": maxf(elapsed, 1.0), "waves": log.wave_times, "marks": marks,
				"final_label": thousands(int(series[series.size() - 1][1])), "note": "W marks a wave arrival. Diamonds mark relay outposts destroyed."}
	else:
		vm["lede"] = "The Command Nexus fell at %s." % clock(elapsed)
		_defeat_record(vm, log, elapsed)
	return vm


## Power and depot record from the samples; nothing is added when there are fewer than three samples.
static func _defeat_record(vm: Dictionary, log, elapsed: float) -> void:
	var window: Array = log.samples.filter(func(s): return s["t"] >= elapsed - 180.0)
	if window.size() < 3:
		return
	var start: float = window[0]["t"]
	var span := maxf(elapsed - start, 1.0)
	var power_rows := _segments(window, start, span, elapsed, func(s): return "ok" if s["gen"] >= s["demand"] else "warn", {"ok": "Balanced", "warn": "Deficit"})
	var rows: Array = [{"label": "Power", "segments": power_rows}]
	var chips: Array = []
	var deficit := _seconds_where(window, elapsed, func(s): return s["gen"] < s["demand"])
	if deficit > 0.0:
		chips.append({"label": "Power deficit", "value": "%s total" % clock(deficit), "tone": "warn"})
	var ever_stocked := window.any(func(s): return s["ammo"] > 0)
	if ever_stocked:
		rows.append({"label": "Depot ammo", "segments": _segments(window, start, span, elapsed, func(s): return "ok" if s["ammo"] > 0 else "bad", {"ok": "Stocked", "bad": "Empty"})})
		var empty := _seconds_where(window, elapsed, func(s): return s["ammo"] <= 0)
		if empty > 0.0:
			chips.append({"label": "Depots empty", "value": "%s total" % clock(empty), "tone": "bad"})
	if window.any(func(s): return s["hq"] >= 0.0):
		rows.append({"label": "HQ integrity", "segments": _segments(window, start, span, elapsed, func(s): return "ok" if s["hq"] >= 0.999 else "warn", {"ok": "Intact", "warn": "Under attack"})})
	vm["timeline"] = {"title": "What failed", "range": "%s to %s" % [clock(start), clock(elapsed)], "rows": rows,
		"ticks": [{"at": 0.0, "t": clock(start)}, {"at": 0.5, "t": clock(start + span * 0.5)}], "end": {"t": "%s HQ destroyed" % clock(elapsed), "tone": "bad"}}
	if not chips.is_empty():
		vm["chips"] = chips
	var advice: Array = []
	if deficit > 0.0:
		advice.append("Add a Reactor or Battery so defences stay powered.")
	if ever_stocked and _seconds_where(window, elapsed, func(s): return s["ammo"] <= 0) > 0.0:
		advice.append("Keep a supply depot stocked and its route open.")
	if not advice.is_empty():
		vm["advice"] = advice


## Merge consecutive samples with the same state into {from, to, text, tone} segments over 0..1.
static func _segments(window: Array, start: float, span: float, end_t: float, state: Callable, names: Dictionary) -> Array:
	var out: Array = []
	for i in window.size():
		var tone: String = state.call(window[i])
		var from: float = (window[i]["t"] - start) / span
		var to: float = ((window[i + 1]["t"] if i + 1 < window.size() else end_t) - start) / span
		if not out.is_empty() and out[out.size() - 1]["tone"] == tone:
			out[out.size() - 1]["to"] = to
		else:
			out.append({"from": from, "to": to, "tone": tone, "text": names[tone]})
	return out


static func _seconds_where(window: Array, end_t: float, pred: Callable) -> float:
	var total := 0.0
	for i in window.size():
		var to: float = window[i + 1]["t"] if i + 1 < window.size() else end_t
		if pred.call(window[i]):
			total += to - window[i]["t"]
	return total
