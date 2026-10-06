extends RefCounted
## Core-assault HUD (mock: CoreAssault) from live game state. It knows when the assault is on, fills the as_* sections
## from what the snapshot carries, and projects hostile marks onto the screen. Values the snapshot lacks (boss phase and
## retaliation timer, objective steps, supply path, queued orders) are left out and the screen drops those blocks.
const SPR := "res://assets/ui/sprites/"
const TICKS_PER_SECOND := 30.0
const ENGAGE_RANGE := 9.0
const HQ_ALERT_SECONDS := 12.0
const AMMO_CAPACITY := 90.0
const HUMAN := 0
const MAX_MARKS := 24
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")

var g
var engaged := false  # latched: once the alien core has been reached or hurt, the assault layout stays available
var _hq_ratio := -1.0
var _hq_hurt_at := -1000.0


func _init(game) -> void:
	g = game


## The alien Command Center, or null.
func core_node() -> Node3D:
	for n in g.bridge_nodes.values():
		if is_instance_valid(n) and int(n.get_meta("team", HUMAN)) != HUMAN and String(n.get_meta("kind_name", "")) == "CommandCenter":
			return n
	return null


func hq_node() -> Node3D:
	for n in g.bridge_nodes.values():
		if is_instance_valid(n) and int(n.get_meta("team", -1)) == HUMAN and String(n.get_meta("kind_name", "")) == "CommandCenter":
			return n
	return null


## Called every view-model pass. Latches `engaged` and watches HQ health for the edge alert.
func update(now: float) -> void:
	var core := core_node()
	if core != null and not engaged:
		var hurt := float(core.get_meta("hp", 1.0)) < float(core.get_meta("max_hp", 1.0)) - 0.5
		var near := false
		for n in g.bridge_nodes.values():
			if is_instance_valid(n) and int(n.get_meta("team", -1)) == HUMAN and String(n.get_meta("category", "")) == "unit":
				if Vector2(n.position.x - core.position.x, n.position.z - core.position.z).length() <= ENGAGE_RANGE:
					near = true
					break
		engaged = hurt or near
	var hq := hq_node()
	if hq != null:
		var ratio := _ratio(hq)
		if _hq_ratio >= 0.0 and ratio < _hq_ratio - 0.001:
			_hq_hurt_at = now
		_hq_ratio = ratio
	else:
		_hq_ratio = -1.0


static func _ratio(n: Node3D) -> float:
	return clampf(float(n.get_meta("hp", 0.0)) / maxf(1.0, float(n.get_meta("max_hp", 1.0))), 0.0, 1.0)


static func _num(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0 and s[i - 1] != "-":
			out += ","
		out += s[i]
	return out


## The as_* sections. `alerts` and `tabs` come from the adapter so the toast queue and tab strip stay one thing.
func vm(now: float, alerts: Array, tabs: Array, selection: Dictionary, attack_armed: bool) -> Dictionary:
	var core := core_node()
	var out := {
		"as_top": _top(core),
		"as_objective": {"cap": "Objective", "tag": "Operation Dawnshield", "title": "Destroy the Core Node", "body": "Ends the Earth operation. Relay destruction cuts reinforcements but is optional."},
		"as_bottom": {"layers": [], "slot_fill": "#1f2219", "alerts": _alerts(now, alerts)},
		"as_selection": _selection(selection),
		"deck": {"body": {"kind": "assault_orders", "tabs": tabs, "orders": _orders(attack_armed), "hint": "Right-click a target while Attack-move is armed."}},
		"as_vignette": {"strength": 0.45},
	}
	if core != null:
		var max_hp := maxf(1.0, float(core.get_meta("max_hp", 1.0)))
		out["as_boss"] = {"name": "Alien Core Node", "hp_text": "%s / %s HP" % [_num(float(core.get_meta("hp", 0.0))), _num(max_hp)], "ratio": _ratio(core)}
	var relays := _relays()
	if not relays.is_empty():
		out["as_relays"] = relays
	var edge := _edge(now)
	if not edge.is_empty():
		out["as_edge"] = edge
	return out


func _top(core: Node3D) -> Dictionary:
	var deficit: int = g.bridge_power_demand - g.bridge_power_generation
	var left: Array = [
		{"icon": "material", "tone": "cyan_hi", "text": "MATERIAL %s" % _num(g.bridge_money)},
		{"icon": "bolt_alt", "tone": "warn" if deficit > 0 else "good", "text": "POWER %d / %d kW" % [g.bridge_power_generation, g.bridge_power_demand]},
		{"icon": "crew_alt", "tone": "cyan_hi", "text": "CREW %d / %d" % [g.bridge_supply_used, g.bridge_supply_cap]},
	]
	var status: Array = []
	if core != null and bool(core.get_meta("remembered", false)):
		status.append({"icon": "target", "tone": "bad", "border": "bad", "text": "CORE LAST SEEN"})  # fog: no live HP
	elif core != null:
		status.append({"icon": "target", "tone": "bad", "border": "bad", "text": "CORE %s / %s HP" % [_num(float(core.get_meta("hp", 0.0))), _num(float(core.get_meta("max_hp", 0.0)))]})
	if g.bridge_relays > 0 and _fogged():
		status.append({"icon": "relay", "tone": "warn", "text": "RELAYS %d known" % g.bridge_relays})
	elif g.bridge_relays > 0:
		status.append({"icon": "relay", "tone": "warn" if g.bridge_active_relays > 0 else "good", "text": "RELAYS %d / %d active" % [g.bridge_active_relays, g.bridge_relays]})
	var hq := hq_node()
	if hq != null:
		var pct := roundi(_ratio(hq) * 100.0)
		status.append({"icon": "home", "tone": "bad" if pct < 40 else ("warn" if pct < 75 else "good"), "border": "warn" if pct < 75 else "", "text": "HQ %d%% integrity" % pct})
	status.append({"icon": "tower", "tone": "warn" if g.bridge_depot_ammo < 30 else "cyan_hi", "text": "AMMO %d%%" % roundi(clampf(float(g.bridge_depot_ammo) / AMMO_CAPACITY, 0.0, 1.0) * 100.0)})
	var right: Array = []
	if g.bridge_next_wave_ticks >= 0:
		var seconds := ceili(float(g.bridge_next_wave_ticks) / TICKS_PER_SECOND)
		right.append({"icon": "clock_alt", "tone": "warn", "border": "warn", "text": "NEXT WAVE %02d:%02d" % [seconds / 60, seconds % 60]})
	return {"groups": [left, status], "right": right}


func _relays() -> Dictionary:
	var items: Array = []
	var fog := _fogged()
	for i in g.bridge_relays:
		var state := "known" if fog else ("powered" if i < g.bridge_active_relays else "destroyed")  # fog: power unseen
		items.append({"name": "Relay %s" % char(65 + i % 26), "state": state})
	if items.is_empty():
		return {}
	return {"items": items, "note": "Powered relays reinforce every expedition."}


## Kestrel fog of war: the snapshot's mask hides something. The relays' power state is then never shown.
func _fogged() -> bool:
	var snap = g.get("bridge_snapshot")
	return snap is Dictionary and VmGameplay.fogged(snap)


func _edge(now: float) -> Dictionary:
	if _hq_ratio < 0.0 or now - _hq_hurt_at > HQ_ALERT_SECONDS:
		return {}
	return {"title": "HQ under raid", "lines": ["HQ %d%% integrity" % roundi(_hq_ratio * 100.0)], "action": "jump_hq"}


func _alerts(now: float, source: Array) -> Array:
	var rows: Array = []
	if not _edge(now).is_empty():
		rows.append({"tone": "bad", "marker": "diamond", "label": "HQ under raid", "time": "now", "action": "jump_hq"})
	for a in source:
		var tone := str(a.get("tone", "cyan"))
		var age := maxi(0, int(now - float(a.get("at", now))))
		rows.append({"tone": "bad" if tone == "bad" else ("warn" if tone == "warn" else "good"), "marker": "diamond" if bool(a.get("hostile", false)) else "dot", "label": str(a.get("title", "")), "time": "%d:%02d" % [age / 60, age % 60]})
	return rows.slice(0, 3)


## The selection summary as the assault bottom panel wants it. `selection` is the adapter's vm for the main HUD.
func _selection(sel: Dictionary) -> Dictionary:
	if sel.is_empty():
		return {"empty_title": "No selection", "hint": "Drag to select units, then press A and right-click the Core."}
	var out := {"name": str(sel.get("name", "")), "sub": str(sel.get("count", "")), "groups": [], "stats": []}
	for group in sel.get("groups", []):
		var entry: Dictionary = group.duplicate()
		if not entry.has("sprite"):
			entry["sprite"] = ""
		out["groups"].append(entry)
	for row in sel.get("rows", []):
		if row.has("ratio"):
			out["stats"].append({"label": str(row.get("label", "")), "kind": "bar", "ratio": float(row.get("ratio", 0.0)), "value": str(row.get("value", "")), "tone": str(row.get("bar", "cyan"))})
		else:
			out["stats"].append({"label": str(row.get("label", "")), "text": str(row.get("value", ""))})
	out["stats"] = out["stats"].slice(0, 3)
	return out


func _orders(armed: bool) -> Array:
	return [
		{"label": "Attack-move", "key": "A", "action": "order", "arg": "attack_move", "tone": "primary" if armed else ""},
		{"label": "Focus", "key": "F", "action": "order", "arg": "focus"},
		{"label": "HQ", "key": "Home", "action": "order", "arg": "hq"},
	]


## Screen-space marks (WorldMarks). `project` is a Callable(Vector3) -> Vector2 (Camera3D.unproject_position), or an
## invalid Callable in tests; `behind` tells whether a point is in front of the camera.
func marks(project: Callable, visible_rect: Rect2, behind: Callable) -> Array:
	var out: Array = []
	var core := core_node()
	for n in g.bridge_nodes.values():
		if out.size() >= MAX_MARKS:
			break
		if not is_instance_valid(n) or int(n.get_meta("team", HUMAN)) == HUMAN or bool(n.get_meta("remembered", false)):
			continue  # a remembered building (fog of war) has no live HP to show
		var p: Vector3 = n.global_position if n.is_inside_tree() else n.position
		if behind.call(p):
			continue
		var s: Vector2 = project.call(p + Vector3(0, 0.9, 0))
		if not visible_rect.grow(40.0).has_point(s):
			continue
		var big: bool = n == core or String(n.get_meta("category", "")) == "building"
		out.append({"kind": "hostile", "x": roundf(s.x), "y": roundf(s.y), "hp": _ratio(n), "w": 70 if n == core else (50 if big else 40)})
	return out
