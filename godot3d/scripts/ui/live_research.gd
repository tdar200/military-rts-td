extends RefCounted
## Research screen view model from the live snapshot (bridge_research_options and the active-research fields), plus the
## screen's own state: selected project, zoom, search text and which filter rows are switched off.
## A block the snapshot cannot fill (era gate criteria, theory/prototype split, retrofit, path steps) is left out.
const BRANCHES := ["Computation / AI", "Energy / power", "Materials", "Propulsion", "Weapons", "Defence", "Biology / civilisation", "Logistics"]
## Card tags sit beside the state tag in a 232 px card, so the one long branch name is shortened there. Filters and the detail drawer use BRANCHES.
const CARD_BRANCHES := ["Computation / AI", "Energy / power", "Materials", "Propulsion", "Weapons", "Defence", "Biology", "Logistics"]
const ERAS := ["Contemporary", "Advanced Industrial", "Fusion", "Solar", "Interstellar", "Stellar Engineering", "Post-biological", "Spacetime", "Galactic", "Cosmic"]
const STATE_ROWS := [["available", "Available"], ["active", "In progress"], ["implemented", "Complete"], ["blocked", "Blocked"]]
const TICKS_PER_SECOND := 30.0
const MIN_SCALE := 0.5
const MAX_SCALE := 1.5

var selected := ""
var scale := 1.0
var search := ""
var off: Dictionary = {}  # "branch:3" / "state:blocked" -> true when that filter row is unchecked


## Applies an action emitted by the research screen. Returns {"research": id} when a project should be started,
## {"close": true} when the screen should close, otherwise {}.
func handle(name: String, arg: Variant) -> Dictionary:
	match name:
		"select":
			selected = str(arg)
		"research":
			return {"research": int(str(arg))}
		"close":
			return {"close": true}
		"zoom":
			scale = clampf(snappedf(scale + 0.1 * float(arg), 0.05), MIN_SCALE, MAX_SCALE)
		"zoom_to":
			scale = clampf(MIN_SCALE + float(arg) * (MAX_SCALE - MIN_SCALE), MIN_SCALE, MAX_SCALE)
		"search":
			search = str(arg)
		"filter":
			if arg is Dictionary:
				off["%s:%s" % [arg.get("group", ""), arg.get("id", "")]] = not bool(arg.get("on", true))
	return {}


static func node_state(option: Dictionary, active_id: int) -> String:
	if bool(option.get("researched", false)):
		return "implemented"
	if int(option.get("id", -1)) == active_id:
		return "active"
	return "available" if bool(option.get("available", false)) else "blocked"


static func state_tag(state: String) -> Dictionary:
	match state:
		"implemented": return {"label": "Complete", "tone": "good"}
		"active": return {"label": "In progress", "tone": "cyan"}
		"available": return {"label": "Available", "tone": "cyan"}
	return {"label": "Blocked", "tone": "warn"}


static func branch_name(option: Dictionary) -> String:
	return BRANCHES[clampi(int(option.get("branch", 0)), 0, BRANCHES.size() - 1)]


static func card_branch(option: Dictionary) -> String:
	return CARD_BRANCHES[clampi(int(option.get("branch", 0)), 0, CARD_BRANCHES.size() - 1)]


static func _unlocks(option: Dictionary) -> String:
	var rx := RegEx.new()
	rx.compile("\\s+\u2022\\s+")
	return rx.sub(String(option.get("unlocks", "")), ", ", true)


## Prerequisite names are a " + " joined string; resolve them to option ids. A name that matches no option is dropped.
static func prereq_ids(option: Dictionary, options: Array) -> Array:
	var text := String(option.get("prerequisites", ""))
	var ids: Array = []
	if text == "":
		return ids
	for part in text.split(" + "):
		for other in options:
			if other is Dictionary and String(other.get("name", "")) == part.strip_edges():
				ids.append(str(int(other.get("id", -1))))
	return ids


## Prerequisite chain ending at `id`, root first, following the first unfinished prerequisite at every step.
static func chain(id: String, options: Array) -> Array:
	var by_id: Dictionary = {}
	for o in options:
		if o is Dictionary:
			by_id[str(int(o.get("id", -1)))] = o
	var out: Array = []
	var cur := id
	while cur != "" and by_id.has(cur) and not out.has(cur):
		out.push_front(cur)
		var next := ""
		for p in prereq_ids(by_id[cur], options):
			if next == "":
				next = p
			if not bool(by_id[p].get("researched", false)):
				next = p
				break
		cur = next
	return out


func _is_dim(option: Dictionary, state: String) -> bool:
	if off.get("branch:%d" % int(option.get("branch", 0)), false) or off.get("state:%s" % state, false):
		return true
	return search != "" and not String(option.get("name", "")).to_lower().contains(search.to_lower())


func vm(g) -> Dictionary:
	var options: Array = []
	for o in g.bridge_research_options:
		if o is Dictionary:
			options.append(o)
	var active_id: int = g.bridge_active_research_id
	var nodes: Array = []
	var counts: Dictionary = {}
	var state_counts: Dictionary = {}
	for o in options:
		var state := node_state(o, active_id)
		var id := str(int(o.get("id", -1)))
		var tags: Array = [{"label": card_branch(o), "tone": "blue"}, state_tag(state)]
		var cells := [0.0, 0.0, 0.0]
		if state == "implemented":
			cells = [1.0, 1.0, 1.0]
		elif state == "active":
			var total := maxf(1.0, float(o.get("duration", 1)))
			cells = [1.0, clampf(1.0 - float(g.bridge_active_research_ticks) / total, 0.0, 1.0), 0.0]
		var footer := _unlocks(o)
		var node := {"id": id, "name": String(o.get("name", "")), "state": state, "tags": tags, "segments": cells,
			"labels": ["Ordered", "Working", "Complete"], "prereqs": prereq_ids(o, options)}
		if footer != "":
			node["footer"] = {"text": footer, "tone": "warn" if state == "blocked" else "dim"}
		if _is_dim(o, state):
			node["dim"] = true
		nodes.append(node)
		counts[int(o.get("branch", 0))] = int(counts.get(int(o.get("branch", 0)), 0)) + 1
		state_counts[state] = int(state_counts.get(state, 0)) + 1
	var out := {
		"header": {"title": "Science", "close_label": "Close", "chips": _chips(g)},
		"graph": {"nodes": nodes, "selected": selected, "highlight": chain(selected, options) if selected != "" else [], "click_to_start": true,
			"empty": {"title": "No projects available", "body": "Build a laboratory, deliver refined material and complete prerequisites. Research needs continuous power; advanced prototypes reserve a vehicle factory."}},
		"zoom": {"value": (scale - MIN_SCALE) / (MAX_SCALE - MIN_SCALE), "scale": scale},
		"filters": _filters(counts, state_counts),
		"eras": _eras(g),
	}
	var detail := _detail(g, options, active_id)
	if not detail.is_empty():
		out["detail"] = detail
	else:
		out["detail"] = {"empty": "Select a project in the graph to see its cost, prerequisites and effect."}
	return out


func _chips(g) -> Array:
	var chips: Array = [{"text": "ERA %02d" % (g.bridge_era + 1)}, {"text": "PROJECTS %d / %d" % [g.bridge_research_count, g.bridge_technology_total]}]
	if g.bridge_active_research_id >= 0:
		chips.append({"icon": "flask", "icon_tone": "cyan", "text": "%s %ds" % [String(g.bridge_active_research_name).to_upper(), ceili(float(g.bridge_active_research_ticks) / TICKS_PER_SECOND)]})
	chips.append({"text": "Y close", "tone": "dim"})
	return chips


func _filters(counts: Dictionary, state_counts: Dictionary) -> Dictionary:
	var branch_rows: Array = []
	for i in BRANCHES.size():
		if counts.has(i):
			branch_rows.append({"id": str(i), "label": BRANCHES[i], "on": not off.get("branch:%d" % i, false), "count": str(counts[i])})
	var state_rows: Array = []
	for pair in STATE_ROWS:
		state_rows.append({"id": pair[0], "label": pair[1], "on": not off.get("state:%s" % pair[0], false), "count": str(state_counts.get(pair[0], 0))})
	var groups: Array = []
	if not state_rows.is_empty():
		groups.append({"id": "state", "title": "State", "rows": state_rows})
	if not branch_rows.is_empty():
		groups.append({"id": "branch", "title": "Branch", "rows": branch_rows})
	return {"search": {"placeholder": "Search projects", "text": search}, "groups": groups}


func _eras(g) -> Dictionary:
	var items: Array = []
	for i in ERAS.size():
		var state := "locked"
		if i == g.bridge_era:
			state = "current"
		elif i == g.bridge_era + 1:
			state = "next"
		items.append({"n": i + 1, "name": ERAS[i], "state": state})
	return {"title": "Eras", "items": items}


func _detail(g, options: Array, active_id: int) -> Dictionary:
	var option := {}
	for o in options:
		if str(int(o.get("id", -1))) == selected:
			option = o
	if option.is_empty():
		return {}
	var state := node_state(option, active_id)
	var cost := int(option.get("money", 0))
	var tags: Array = [{"label": branch_name(option), "tone": "blue"}, {"label": String(option.get("reality", "")), "tone": "dim"}]
	if tags[1]["label"] == "":
		tags.remove_at(1)
	var boxes: Array = [
		{"label": "Material", "value": str(cost), "tone": "good" if g.bridge_money >= cost else "warn", "ratio": clampf(float(g.bridge_money) / maxf(1.0, float(cost)), 0.0, 1.0)},
		{"label": "Base work", "value": "%d s" % ceili(float(option.get("duration", 0)) / TICKS_PER_SECOND), "tone": "text",
			"ratio": clampf(1.0 - float(g.bridge_active_research_ticks) / maxf(1.0, float(option.get("duration", 1))), 0.0, 1.0) if state == "active" else 0.0},
	]
	var out := {"title": String(option.get("name", "")), "state": state_tag(state), "tags": tags, "boxes": boxes}
	if state == "blocked":
		var missing: Array = []
		for p in prereq_ids(option, options):
			for o in options:
				if str(int(o.get("id", -1))) == p and not bool(o.get("researched", false)):
					missing.append(String(o.get("name", "")))
		out["bottleneck"] = {"title": "Blocked", "text": "Needs %s." % " and ".join(missing) if not missing.is_empty() else "Needs a powered laboratory.", "tone": "warn"}
	elif state == "available" and active_id >= 0:
		out["bottleneck"] = {"title": "Laboratory busy", "text": "%s is in progress. One project runs at a time." % g.bridge_active_research_name, "tone": "warn"}
	var unlocks := _unlocks(option)
	if unlocks != "":
		out["effect"] = {"title": "Unlocks", "text": unlocks}
	out["primary"] = {"label": "Start research", "action": "research", "arg": str(int(option.get("id", -1))), "disabled": state != "available" or active_id >= 0 or not g.bridge_active}
	return out
