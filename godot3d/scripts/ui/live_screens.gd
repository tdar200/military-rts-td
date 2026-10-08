extends RefCounted
## View models for the full-screen layers (title, debrief) from live state. Static text is stated plainly;
## a block whose data does not exist is left out, and the screens close the gap.
const SPR := "res://assets/ui/sprites/"
const UNIT_ROWS := [["Infantry", "Infantry"], ["AntiArmor", "Anti-armour"], ["Tank", "Battle tanks"], ["Helicopter", "Gunships"], ["Harvester", "Harvesters"], ["Capital", "Capital units"]]
const SessionLog = preload("res://scripts/ui/session_log.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const FixturesChapters := [
	{"tag": "Eras 3-4", "tag_color": "f0b040", "name": "Solar", "blurb": "Orbital industry, launch mass and transfer windows.", "status": "Design / Locked"},
	{"tag": "Era 5", "tag_color": "78b4ff", "name": "Interstellar", "blurb": "Independent industrial seeds and communication delay.", "status": "Design / Locked"},
	{"tag": "Eras 6-9", "tag_color": "9ad0ff", "name": "Galactic", "blurb": "Sector budgets and autonomous governors.", "status": "Design / Locked"},
	{"tag": "Era 10", "tag_color": "e8f4ff", "name": "Cosmic", "blurb": "Refuge networks and survival under causal limits.", "status": "Design / Locked"},
]


const FOG_COPY := "Fog of war, scout the alien side"


## The map picker's two cards, Kestrel Reach first. Only what really differs between the maps is stated.
const MAP_CARDS := [
	{"id": "kestrel", "tags": [{"t": "Recommended", "tone": "good"}],
		"blurb": "A painted frontier of river, ridge and forest. Scout through the fog, take down the alien relays and break the Core Node.",
		"facts": [{"k": "Visibility", "v": "Fog of war"}, {"k": "Terrain", "v": "River, ford, ridge, forest"}]},
	{"id": "survival", "tags": [{"t": "Classic", "tone": "dim"}],
		"blurb": "The original Earthfront battlefield on open grassland. Hold against the alien waves with the whole map in view.",
		"facts": [{"k": "Visibility", "v": "Full battlefield"}, {"k": "Terrain", "v": "Open grassland"}]},
]


## Title and campaign. `deploy_enabled` is false while the bridge is down (and while the map picker covers the title).
## `fogged`: the bridge runs Kestrel Reach with its fog of war (game_ui re-applies the title once a fogged snapshot arrives);
## Survival shows the whole battlefield. `scenario` is the map the card names ("" = MatchConfig.current). New operation
## opens the map picker; the card's Deploy forces deploys the map the bridge already runs.
static func title_vm(deploy_enabled: bool, research_projects: int, fogged := false, scenario := "") -> Dictionary:
	var primary := {"label": "Deploy forces", "action": "deploy", "disabled": not deploy_enabled}
	var map := scenario if scenario != "" else str(MatchConfig.current.scenario)
	return {
		"eyebrow": "Earthfront / Era 1",
		"title": "Ascension",
		"tagline": "Hold the Earthfront. Break the Core Node.",
		"menu": [
			{"id": "continue", "label": "Continue campaign", "icon": "play", "disabled": true},
			{"id": "deploy", "action": "pick_map", "label": "New operation", "icon": "plus", "emphasis": "primary", "disabled": not deploy_enabled},
			{"id": "skirmish", "label": "Skirmish sandbox", "icon": "crosshair", "disabled": true},
			{"id": "research", "label": "Research archive", "hint": "%d projects" % research_projects if research_projects > 0 else "", "icon": "flask_title", "disabled": true},
			{"id": "settings", "label": "Settings", "icon": "cog"},
			{"id": "quit", "label": "Quit", "icon": "restart"},
		],
		"campaign": {
			"title": "Campaign", "summary": "1 playable / 4 design",
			"featured": {
				"name": MatchConfig.display_name(map),
				"blurb": "Earthfront. Contemporary Humanity to Advanced Industrial Civilization.",
				"tags": [{"t": "Playable", "tone": "good"}, {"t": "Era 1-2", "tone": "dim"}],
				"facts": [{"k": "Objective", "v": "Destroy the alien Core Node"}, {"k": "Visibility", "v": FOG_COPY if fogged else "Full battlefield, no fog of war"}],
				"primary": primary,
			},
			"later_title": "Later chapters", "later_note": "Design only",
			"chapters": FixturesChapters,
		},
		"footer_left": "Ascension", "footer_right": "",
	}


## Task 20: what each Kestrel preset means, in the picker's words (godot-bridge.rs builds rts_core Difficulty).
const DIFFICULTY_DETAIL := {
	"easy": "1,500 credits. First wave at 3:00, then every 3:30, at three quarters size.",
	"normal": "1,200 credits. First wave at 2:30, then every 3:00, at full size.",
	"hard": "1,000 credits. First wave at 2:00, then every 2:30, a quarter larger.",
}
const SURVIVAL_DIFFICULTY := "Presets apply to Kestrel Reach. Survival keeps its classic waves."


## The map picker (sections/map_picker.gd): one card per map, `selected` marked, then the difficulty presets
## (`difficulty` selected) and the match seed (Task 20).
static func picker_vm(selected: String, difficulty := "normal", seed := MatchConfig.DEFAULT_SEED) -> Dictionary:
	var cards: Array = []
	for c in MAP_CARDS:
		var card: Dictionary = c.duplicate(true)
		card["name"] = MatchConfig.display_name(c.id)
		card["selected"] = c.id == selected
		cards.append(card)
	var preset := MatchConfig.clean_difficulty(difficulty)
	var options: Array = []
	for id in MatchConfig.DIFFICULTIES:
		options.append({"id": id, "label": MatchConfig.difficulty_name(id), "selected": id == preset})
	return {"cap": "New operation", "title": "Choose a battlefield", "cards": cards, "back": "Back", "confirm": "Deploy forces",
		"note": "The bridge rebuilds the chosen map, then the operation starts.",
		"difficulty": {"cap": "Difficulty", "options": options, "detail": DIFFICULTY_DETAIL[preset] if selected != "survival" else SURVIVAL_DIFFICULTY},
		"seed": {"cap": "Seed", "value": str(seed), "hint": "New each operation"}}


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


## Debrief column for the finished mission. `log` is the SessionLog the game kept (null reads as an empty one). Restart
## replays the same map and seed and deploys at once; Main menu returns to the title; Quit closes the game. Task 22:
## `record` is game_ui.record_score() ({best, new_best} once the decided Kestrel match's score is recorded, else {}).
static func debrief_vm(g, log, record := {}) -> Dictionary:
	if log == null:
		log = SessionLog.new()
	var victory: bool = g.bridge_winner == 0
	var elapsed := float(g.bridge_tick) / 30.0
	var buttons: Array = [{"label": "Review battlefield", "action": "review", "primary": true}, {"label": "Restart", "action": "restart"},
		{"label": "Main menu", "action": "menu"}, {"label": "Quit", "action": "quit"}]
	var vm := {
		"variant": "victory" if victory else "defeat",
		"tag": "Debrief / " + ("victory" if victory else "defeat"),
		"operation": "Operation Dawnshield",
		"title": "Core Node destroyed" if victory else "Headquarters lost",
		"buttons": buttons,
		"footer": _footer(g),
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
	var score := score_vm(g.get("bridge_snapshot"), record)
	if not score.is_empty():
		vm["score"] = score
	return vm


## Task 22: the score block from the Kestrel depth block's "score" (the bridge's Sim::depth_score): the total, the grade,
## one row per term and, with a `record` ({best, new_best}), the personal best and the New best flag. {} without a score
## (Survival, classic Kestrel or no snapshot).
static func score_vm(snapshot: Variant, record := {}) -> Dictionary:
	if not (snapshot is Dictionary):
		return {}
	var depth: Variant = snapshot.get("depth", null)
	if not (depth is Dictionary) or not (depth.get("score", null) is Dictionary):
		return {}
	var sc: Dictionary = depth["score"]
	var waves := int(sc.get("waves_held", 0))
	var lost := int(sc.get("lost", 0))
	var bonus := int(sc.get("victory_bonus", 0))
	var difficulty := MatchConfig.clean_difficulty(depth.get("difficulty", "normal"))
	var rows: Array = [
		{"label": "Waves held (%d x 500)" % waves, "value": _signed(waves * 500)},
		{"label": "Enemy value destroyed", "value": _signed(int(sc.get("destroyed", 0)))},
		{"label": "Losses (half of %s)" % thousands(lost), "value": _signed(-floori(lost / 2.0))},
	]
	if bonus > 0:
		rows.append({"label": "Victory bonus", "value": _signed(bonus)})
	rows.append({"label": "%s difficulty" % MatchConfig.difficulty_name(difficulty), "value": SCORE_MULTIPLIERS[difficulty]})
	var out := {"total": thousands(int(sc.get("total", 0))), "grade": str(sc.get("grade", "D")), "rows": rows, "new_best": bool(record.get("new_best", false))}
	if record.has("best"):
		out["best"] = thousands(int(record["best"]))
	return out


## The score multiplier each preset shows (Difficulty::score_pct in the core: 75, 100, 150).
const SCORE_MULTIPLIERS := {"easy": "x0.75", "normal": "x1", "hard": "x1.5"}


static func _signed(n: int) -> String:
	if n == 0:
		return "0"
	return ("+" if n > 0 else "") + thousands(n)


## The debrief's last line: the final tick, then (Kestrel, whose snapshot carries them) the preset and the seed, so a
## match can be replayed or shared.
static func _footer(g) -> String:
	var text := "Final tick %s" % thousands(g.bridge_tick)
	var played := MatchConfig.from_snapshot(g.get("bridge_snapshot"))
	if not played.is_empty():
		text += " / %s / Seed %d" % [MatchConfig.difficulty_name(played.difficulty), played.seed]
	return text


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
