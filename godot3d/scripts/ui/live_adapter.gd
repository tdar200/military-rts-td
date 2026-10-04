extends RefCounted
## Maps the live game (bridge_* state, selection metas, notification events) to the HUD view model,
## and maps HUD actions back to the game's existing handlers. Holds no game logic.
## Data the snapshot does not carry is left out of the view model, never invented.
const SPR := "res://assets/ui/sprites/"
const TICKS_PER_SECOND := 30.0
const ALERT_TTL := 9.0
const MAX_ALERTS := 3
const AMMO_CAPACITY := 90.0

## id, display name, hotkey, bridge kind, material, crew, producing building, sprite ("" = icon card), icon
const UNIT_CARDS := [
	["infantry", "Riflemen", "T", "Infantry", 50, 1, "Barracks", "infantry_v2.png", ""],
	["anti_armor", "Rocket team", "V", "AntiArmor", 110, 1, "Barracks", "anti_armor_v2.png", ""],
	["tank", "Battle tank", "K", "Tank", 200, 2, "VehicleFactory", "tank_v2.png", ""],
	["helicopter", "Gunship", "H", "Helicopter", 160, 2, "Airfield", "helicopter_v2.png", ""],
	["harvester", "Harvester", "", "Harvester", 140, 1, "Refinery", "", "ore"],
]
const PRODUCER_NAMES := {"Barracks": "barracks", "VehicleFactory": "vehicle factory", "Airfield": "airfield", "Refinery": "refinery"}
const KIND_NAMES := {
	"CommandCenter": "Command centre", "PowerPlant": "Reactor", "Refinery": "Refinery", "Barracks": "Barracks",
	"VehicleFactory": "Vehicle factory", "Airfield": "Airfield", "SupplyDepot": "Supply depot", "Battery": "Battery",
	"GunTurret": "Gun turret", "AaTurret": "AA battery", "Wall": "Field wall", "ResearchLab": "Research lab",
	"AntimatterPlant": "Antimatter plant", "Infantry": "Riflemen", "AntiArmor": "Rocket team", "Tank": "Battle tank",
	"Helicopter": "Gunship", "Harvester": "Harvester", "Capital": "Capital unit",
}
const GROUP_LABELS := {"Infantry": "INF", "AntiArmor": "AT", "Tank": "TANK", "Helicopter": "GUNSHIP", "Harvester": "HARV", "Capital": "CAP"}
const GROUP_SPRITES := {"Infantry": "infantry_v2.png", "AntiArmor": "anti_armor_v2.png", "Tank": "tank_v2.png", "Helicopter": "helicopter_v2.png"}
## Tutorial stage -> objective group, and the detail shown while that stage is active.
const OBJECTIVE_GROUPS := [
	{"t": "Establish a supplied base", "to": 2},
	{"t": "Build science and production", "to": 6},
	{"t": "Field a strike force", "to": 7},
	{"t": "Hold the first wave", "to": 8},
	{"t": "Destroy the alien Core Node", "to": 9},
]
const STAGE_DETAIL := [
	"Secure the landing zone", "Build a power plant (P)", "Build a refinery near ore (R)", "Build a powered laboratory (L)",
	"Construct a research lab (L)", "Research anti-armour or vehicle tooling (Y)", "Construct a barracks (B)",
	"Train three combat units (T / V / K)", "Hold the Earthfront, first wave in %ds", "Destroy the hostile Core Node",
]
const TABS := [["build", "Build", "build"], ["units", "Units", "units"], ["orders", "Orders", "orders"], ["science", "Science", "flask"]]
## id, bridge kind, name, hotkey, material, kW (negative = output), role line, sprite. Costs are the game's command table.
const BUILD_CARDS := [
	["power", "PowerPlant", "Reactor", "P", 100, -80, "Adds generation", "power_plant_v2.png"],
	["refinery", "Refinery", "Refinery", "R", 150, 20, "Harvests exposed ore", "refinery_v2.png"],
	["barracks", "Barracks", "Barracks", "B", 200, 10, "Trains infantry", "barracks_v2.png"],
	["factory", "VehicleFactory", "Vehicle factory", "", 220, 30, "Builds tanks", "barracks_v2.png"],
	["airfield", "Airfield", "Airfield", "", 260, 35, "Builds gunships", "helicopter_v2.png"],
	["turret", "GunTurret", "Gun turret", "G", 120, 8, "Anti-ground defence", "gun_turret_v2.png"],
	["aa", "AaTurret", "AA battery", "J", 140, 8, "Anti-air defence", "aa_turret_v2.png"],
	["wall", "Wall", "Field wall", "C", 20, 0, "Terrain control", "wall_v2.png"],
	["depot", "SupplyDepot", "Supply depot", "", 100, 5, "Makes ammunition", "foundation_v1.png"],
	["lab", "ResearchLab", "Research lab", "L", 250, 30, "Powered research", "capital_v1.png"],
	["battery", "Battery", "Battery", "", 120, 0, "Stores surplus power", "power_plant_v2.png"],
]

var g  # earthfront_3d.gd, or a stub with the same members in tests
const LiveAssault = preload("res://scripts/ui/live_assault.gd")
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")

var tab := "build"
var assault
var _alerts: Array = []
var _ticker := ""
var _deficit_since := -1.0


func _init(game) -> void:
	g = game
	assault = LiveAssault.new(game)


## True while the core-assault layout is the one on screen: the core has been reached and the Orders tab is open.
func assault_active() -> bool:
	return tab == "orders" and assault.engaged


# ------------------------------------------------------------------ events in

## Called from the game's _show_notification.
func push_notification(title: String, body: String, color: Color, now: float) -> void:
	var tone := "cyan"
	if color.r > color.g + 0.3:
		tone = "bad"
	elif color.r > 0.6 and color.g > 0.5 and color.b < 0.5:
		tone = "warn"
	_push({"tone": tone, "hostile": tone == "bad", "icon": "power" if tone == "warn" else "wave", "title": _sentence(title), "body": _sentence(body)}, now)


## Called every frame with objective_label.text; a changed, non-empty text becomes a toast.
func poll_ticker(text: String, now: float) -> void:
	if text == _ticker:
		return
	_ticker = text
	if text == "":
		return
	var parts := text.split(" — ", false, 1)
	var title := parts[0]
	var body := parts[1] if parts.size() > 1 else ""
	_push({"tone": "cyan", "icon": "wave", "title": _sentence(title), "body": _sentence(body.replace(" • ", ", "))}, now)


func _push(alert: Dictionary, now: float) -> void:
	alert["until"] = now + ALERT_TTL
	alert["at"] = now
	for old in _alerts:
		if old["title"] == alert["title"]:
			_alerts.erase(old)
			break
	_alerts.append(alert)
	while _alerts.size() > MAX_ALERTS:
		_alerts.pop_front()


static func _sentence(s: String) -> String:
	var t := s.strip_edges().to_lower()
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""


# ------------------------------------------------------------------ view model out

func hud_vm(now: float) -> Dictionary:
	_alerts = _alerts.filter(func(a): return a["until"] > now)
	var deficit: int = g.bridge_power_demand - g.bridge_power_generation
	if deficit > 0 and _deficit_since < 0.0:
		_deficit_since = now
	elif deficit <= 0:
		_deficit_since = -1.0
	assault.update(now)
	if assault_active():
		return assault.vm(now, _alerts, _tabs(), _selection(), g.attack_move_armed)
	if tab == "build":
		return _with_gameplay(_build_vm(now, deficit))
	var vm := {
		"brand": {"title": "Ascension", "sub": "Era %d / %s" % [g.bridge_era + 1, "Earthfront" if g.bridge_earthfront else "Campaign"]},
		"chips": _chips(),
		"objectives": _objectives(),
		"minimap": {"keys": []},
		"map_marks": {"marks": _marks(), "view": _view()},
		"deck": {"tabs": _tabs(), "body": _deck_body()},
	}
	var wave := _wave_chip()
	if not wave.is_empty():
		vm["wave"] = wave
	var card := _wave_card()
	if not card.is_empty():
		vm["wave_card"] = card
	var tip := _power_tip(deficit, now)
	if not tip.is_empty():
		vm["power_tip"] = tip
	if not _alerts.is_empty():
		vm["alerts"] = _alerts.map(func(a): return a.duplicate())
	var selection := _selection()
	if not selection.is_empty():
		vm["selection"] = selection
	return _with_gameplay(vm)


## Adds the gameplay slices (vm_gameplay.gd) that the latest snapshot can back; absent data adds no key. The snapshot,
## its ground model and the hovered hex are read off the game when it exposes them (`bridge_snapshot`, `ground_model`,
## `hover_cell`); a game that does not simply gets none of the slices.
func _with_gameplay(vm: Dictionary) -> Dictionary:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty():
		return vm
	var ground = g.get("ground_model")
	if ground == null:
		ground = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	var slices := {
		"territory": VmGameplay.territory(snap, ground),
		"idle": VmGameplay.idle_crews(snap),
		"alert": VmGameplay.next_alert(snap),
		"veterans": VmGameplay.veterans(snap),
	}
	var hovered = g.get("hover_cell")
	if hovered is Vector2i:
		slices["inspect"] = VmGameplay.tile_inspect(snap, ground, hovered.x, hovered.y)
	var regions := VmGameplay.regions(snap)
	if not regions.is_empty():
		slices["regions"] = regions
	for key in slices:
		if not slices[key].is_empty():
			vm[key] = slices[key]
	# The top bar's wave chip owns vm["wave"]; the expected route and ETA ride on it so that chip's own keys are untouched.
	var inbound := VmGameplay.wave_inbound(snap)
	if not inbound.is_empty() and vm.has("wave") and vm["wave"] is Dictionary:
		for key in inbound:
			vm["wave"][key] = inbound[key]
	return vm


func _chips() -> Array:
	var ore_capacity := 0
	for service in g.bridge_services.values():
		ore_capacity += int(service.get("ore_capacity", 0))
	var chips: Array = [
		{"icon": "material", "tone": "cyan", "label": "Material", "value": str(g.bridge_money)},
		{"icon": "ore", "tone": "cyan", "label": "Ore buffer", "value": "%d / %d" % [g.bridge_ore, ore_capacity] if ore_capacity > 0 else str(g.bridge_ore)},
	]
	var short: bool = g.bridge_power_demand > g.bridge_power_generation
	chips.append({"icon": "power", "tone": "warn" if short else "cyan", "label": "Power", "value": "%d / %d kW" % [g.bridge_power_generation, g.bridge_power_demand], "state": "warn" if short else ""})
	if g.bridge_storage_capacity > 0:
		chips.append({"icon": "battery", "tone": "good", "label": "Battery", "value": "%d%%" % roundi(100.0 * g.bridge_energy / g.bridge_storage_capacity)})
	chips.append({"icon": "crew", "tone": "cyan", "label": "Crew", "value": "%d / %d" % [g.bridge_supply_used, g.bridge_supply_cap]})
	chips.append({"icon": "ammo", "tone": "cyan", "label": "Ammo supply", "value": str(g.bridge_depot_ammo)})
	for service in g.bridge_services.values():
		if bool(service.get("prototype", false)):
			chips.append({"icon": "flask", "tone": "violet", "label": "Reserved", "value": "PROTOTYPE"})
			break
	return chips


func _wave_chip() -> Dictionary:
	if g.bridge_next_wave_ticks < 0:
		return {}
	var seconds := ceili(float(g.bridge_next_wave_ticks) / TICKS_PER_SECOND)
	return {"label": "Wave %02d %s" % [g.bridge_waves + 1, str(g.bridge_incoming_doctrine).get_slice(" ", 0)], "timer": "T-%02d:%02d" % [seconds / 60, seconds % 60]}


func _wave_card() -> Dictionary:
	var ticks: int = g.bridge_next_wave_ticks
	if ticks < 0 or ticks > 2700:
		return {}
	var seconds := ceili(float(ticks) / TICKS_PER_SECOND)
	var body := "Up to %d units expected." % g.bridge_expedition_size
	if g.bridge_active_relays > 0:
		body += " Support: %d relay%s operating." % [g.bridge_active_relays, "" if g.bridge_active_relays == 1 else "s"]
	return {"tag": "Doctrine committed" if ticks <= 1350 else "Wave forming", "eta": "Arrives in %02d:%02d" % [seconds / 60, seconds % 60], "title": str(g.bridge_incoming_doctrine), "body": body}


func _power_tip(deficit: int, now: float) -> Dictionary:
	if deficit <= 0:
		return {}
	var recent: bool = now - _deficit_since < 8.0
	if not recent and g.mouse_position().y > 66.0:
		return {}
	return {
		"title": "Grid deficit %d kW" % deficit, "tag": "Throttling industry",
		"body": "Generation %d kW against %d kW demand. Defence and extraction receive power before factories and science." % [g.bridge_power_generation, g.bridge_power_demand],
		"cta": "Build reactor", "cta_key": "P",
	}


func _objectives() -> Dictionary:
	var stage: int = g.tutorial_stage
	var items: Array = []
	for i in OBJECTIVE_GROUPS.size():
		var group: Dictionary = OBJECTIVE_GROUPS[i]
		var first: int = 0 if i == 0 else int(OBJECTIVE_GROUPS[i - 1]["to"]) + 1
		var state := "todo"
		if g.bridge_winner == 0 or stage > int(group["to"]):
			state = "done"
		elif stage >= first:
			state = "active"
		var text: String = group["t"]
		if state == "active":
			text = STAGE_DETAIL[clampi(stage, 0, STAGE_DETAIL.size() - 1)]
			if stage == 8:
				text = text % ceili(float(maxi(0, g.bridge_next_wave_ticks)) / TICKS_PER_SECOND)
		if i == OBJECTIVE_GROUPS.size() - 1 and g.bridge_relays > 0:
			items.append({"t": "Optional: disable alien relays (%d active)" % g.bridge_active_relays, "state": "done" if g.bridge_active_relays == 0 else ("active" if stage >= 8 else "todo")})
		items.append({"t": text, "state": state})
	return {"cap": "Operation Dawnshield", "items": items}


# ------------------------------------------------------------------ minimap

func _marks() -> Array:
	var rect: Rect2 = g.minimap_world_rect()
	var marks: Array = []
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return marks
	for node in g.bridge_nodes.values():
		if not is_instance_valid(node):
			continue
		var kind := "f"
		var human: bool = int(node.get_meta("team", -1)) == 0
		var core: bool = String(node.get_meta("kind_name", "")) == "CommandCenter"
		if human:
			kind = "e" if core else "f"
		else:
			kind = "H" if core or String(node.get_meta("category", "")) == "building" else "h"
		marks.append({"x": snappedf(clampf((node.position.x - rect.position.x) / rect.size.x, 0.0, 1.0), 0.005), "y": snappedf(clampf((node.position.z - rect.position.y) / rect.size.y, 0.0, 1.0), 0.005), "k": kind})
	return marks


func _view() -> Dictionary:
	var world: Rect2 = g.minimap_world_rect()
	var seen: Rect2 = g.view_ground_rect()
	if world.size.x <= 0.0 or seen.size.x <= 0.0:
		return {}
	var x := clampf((seen.position.x - world.position.x) / world.size.x, 0.0, 1.0)
	var y := clampf((seen.position.y - world.position.y) / world.size.y, 0.0, 1.0)
	var x2 := clampf((seen.end.x - world.position.x) / world.size.x, 0.0, 1.0)
	var y2 := clampf((seen.end.y - world.position.y) / world.size.y, 0.0, 1.0)
	return {"x": snappedf(x, 0.005), "y": snappedf(y, 0.005), "w": snappedf(x2 - x, 0.005), "h": snappedf(y2 - y, 0.005)}


# ------------------------------------------------------------------ selection

func _selection() -> Dictionary:
	var picked: Array = []
	for n in g.selected_units:
		if is_instance_valid(n):
			picked.append(n)
	if picked.is_empty():
		return {}
	var first: Node3D = picked[0]
	var is_building: bool = String(first.get_meta("category", "unit")) == "building"
	var by_kind: Dictionary = {}
	var hp_sum := 0.0
	var ammo_sum := 0.0
	var ammo_units := 0
	for n in picked:
		var kind := String(n.get_meta("kind_name", ""))
		var ratio: float = clampf(float(n.get_meta("hp", 0.0)) / maxf(1.0, float(n.get_meta("max_hp", 1.0))), 0.0, 1.0)
		hp_sum += ratio
		if not by_kind.has(kind):
			by_kind[kind] = {"count": 0, "hp": 0.0}
		by_kind[kind]["count"] += 1
		by_kind[kind]["hp"] += ratio
		var service: Dictionary = g.bridge_services.get(int(n.get_meta("bridge_id", -1)), {})
		if not is_building and kind != "Harvester" and not service.is_empty():
			ammo_sum += float(service.get("ammo", 0))
			ammo_units += 1
	var average: float = hp_sum / picked.size()
	var kind0 := String(first.get_meta("kind_name", ""))
	var vm := {
		"name": KIND_NAMES.get(kind0, kind0) if picked.size() == 1 else "Strike group",
		"count": "Structure" if is_building else ("1 unit" if picked.size() == 1 else "%d units" % picked.size()),
		"sub": "Earth defence",
		"rows": [],
		"orders": _orders(is_building, kind0),
	}
	if not is_building and by_kind.size() > 0 and picked.size() > 1:
		var groups: Array = []
		for kind in by_kind:
			var entry: Dictionary = {"id": kind, "label": "%s x%d" % [GROUP_LABELS.get(kind, String(kind).to_upper()), by_kind[kind]["count"]], "ratio": by_kind[kind]["hp"] / by_kind[kind]["count"], "tone": _health_tone(by_kind[kind]["hp"] / by_kind[kind]["count"])}
			if GROUP_SPRITES.has(kind):
				entry["sprite"] = SPR + GROUP_SPRITES[kind]
			else:
				entry["icon"] = "units"
			groups.append(entry)
		vm["groups"] = groups
		vm["footer"] = "Click a group to select only it"
	var rows: Array = [{"label": "Health, average" if picked.size() > 1 else "Health", "value": "%d%%" % roundi(average * 100.0), "ratio": average, "bar": _health_tone(average)}]
	if ammo_units > 0:
		var carried: float = ammo_sum / ammo_units
		rows.append({"label": "Ammunition carried", "value": "%d / %d rounds" % [roundi(carried), int(AMMO_CAPACITY)], "ratio": clampf(carried / AMMO_CAPACITY, 0.0, 1.0), "bar": "cyan" if carried > 0.0 else "bad"})
	if is_building and picked.size() == 1:
		rows.append_array(_structure_rows(first))
	vm["rows"] = rows
	return vm


static func _health_tone(ratio: float) -> String:
	return "good" if ratio >= 0.6 else ("warn" if ratio >= 0.3 else "bad")


func _structure_rows(node: Node3D) -> Array:
	var rows: Array = []
	var service: Dictionary = g.bridge_services.get(int(node.get_meta("bridge_id", -1)), {})
	var construction := int(node.get_meta("construction", 0))
	var production := String(node.get_meta("production_name", ""))
	if construction > 0:
		var done := 1.0 - float(construction) / maxf(1.0, float(node.get_meta("construction_total", 1)))
		rows.append({"label": "Construction", "value": "%d%%" % roundi(done * 100.0), "ratio": clampf(done, 0.0, 1.0), "bar": "cyan"})
	elif production != "":
		var progress := clampf(float(node.get_meta("production_progress", 0)) / maxf(1.0, float(node.get_meta("production_duration", 1))), 0.0, 1.0)
		rows.append({"label": "Producing " + production.to_lower(), "value": "%d%%" % roundi(progress * 100.0), "ratio": progress, "bar": "cyan"})
		if int(node.get_meta("production_queued", 0)) > 0:
			rows.append({"label": "Queued", "value": str(int(node.get_meta("production_queued", 0)))})
	if not service.is_empty():
		var power := clampf(float(service.get("power", 0)) / 1000.0, 0.0, 1.0)
		rows.append({"label": "Power", "value": "%d%%" % roundi(power * 100.0), "ratio": power, "bar": "good" if power >= 0.95 else "warn"})
		if String(node.get_meta("kind_name", "")) == "Refinery":
			var capacity := maxi(1, int(service.get("ore_capacity", 300)))
			rows.append({"label": "Ore stored", "value": "%d / %d" % [int(service.get("ore", 0)), capacity], "ratio": clampf(float(service.get("ore", 0)) / capacity, 0.0, 1.0), "bar": "cyan"})
		if int(service.get("stock", 0)) > 0:
			rows.append({"label": "Ammunition stock", "value": "%d rounds" % int(service.get("stock", 0))})
		if bool(service.get("prototype", false)):
			rows.append({"label": "Prototype testing", "value": "Queue paused", "tone": "warn"})
	return rows


func _orders(is_building: bool, kind: String) -> Array:
	var armed: bool = g.attack_move_armed
	if is_building:
		return [
			{"label": "Repair", "key": "U", "action": "order", "arg": "repair"},
			{"label": "Sell", "key": "Del", "action": "order", "arg": "sell", "disabled": kind == "CommandCenter"},
			{"label": "Focus", "key": "F", "wide": true, "action": "order", "arg": "focus"},
		]
	return [
		{"label": "Attack-move", "key": "A", "primary": armed, "action": "order", "arg": "attack_move"},
		{"label": "Focus group", "key": "F", "wide": true, "action": "order", "arg": "focus"},
	]


# ------------------------------------------------------------------ deck

func _tabs() -> Array:
	var tabs: Array = []
	for t in TABS:
		var entry := {"id": t[0], "label": t[1], "icon": t[2]}
		if t[0] == tab:
			entry["on"] = true
		tabs.append(entry)
	return tabs


func _deck_body() -> Dictionary:
	match tab:
		"units":
			return _units_body()
		"orders":
			return _orders_body()
		_:
			return {"title": "Build", "right": "", "cards": []}


func _units_body() -> Dictionary:
	var cards: Array = []
	for spec in UNIT_CARDS:
		var reason := _unit_block_reason(spec)
		var card := {"name": spec[1], "key": spec[2], "action": "train", "arg": spec[0]}
		if spec[7] != "":
			card["sprite"] = SPR + spec[7]
		else:
			card["icon"] = spec[8]
		if reason != "":
			card["locked"] = true
			card["cost"] = reason
			card["cost_tone"] = "warn"
		else:
			card["cost"] = "%d / %d" % [spec[4], spec[5]]
		cards.append(card)
	var body := {"title": "Production", "right": "Costs: material / crew", "cards": cards}
	var queue := _queue()
	if not queue.is_empty():
		body["queue"] = queue
	return body


func _unit_block_reason(spec: Array) -> String:
	if not g.bridge_active or not g.bridge_unlocked_units.has(spec[3]):
		return "Not unlocked"
	if g._human_count("building", spec[6]) == 0:
		return "Needs " + PRODUCER_NAMES.get(spec[6], str(spec[6]))
	if g.bridge_money < spec[4]:
		return "Need %d material" % spec[4]
	if g.bridge_supply_used + spec[5] > g.bridge_supply_cap:
		return "Crew full"
	return ""


## Production queue of the selected structure; empty when nothing is producing.
func _queue() -> Array:
	var node = g.selected  # untyped: the game never clears it, so it may be a freed instance
	if not is_instance_valid(node) or String(node.get_meta("category", "")) != "building" or String(node.get_meta("production_name", "")) == "":
		return []
	var progress := clampf(float(node.get_meta("production_progress", 0)) / maxf(1.0, float(node.get_meta("production_duration", 1))), 0.0, 1.0)
	var cells: Array = [{"label": String(node.get_meta("production_name", "")), "ratio": progress, "on": true}]
	for i in mini(int(node.get_meta("production_queued", 0)), 4):
		cells.append({"label": "Queued", "ratio": 0.0})
	while cells.size() < 5:
		cells.append({"label": "Empty", "empty": true})
	return cells


func _orders_body() -> Dictionary:
	var combat: bool = g._has_selected_combat_unit()
	var structure: bool = is_instance_valid(g.selected) and String(g.selected.get_meta("category", "")) == "building" and int(g.selected.get_meta("team", -1)) == 0
	var cards: Array = [
		{"icon": "crosshair", "name": "Attack-move", "key": "A", "cost": "Right-click a target" if combat else "Select combat units", "cost_tone": "dim" if combat else "warn", "locked": not combat, "on": g.attack_move_armed, "action": "order", "arg": "attack_move"},
		{"icon": "cog", "name": "Field repair", "key": "U", "cost": "Selected structure" if structure else "Select a structure", "cost_tone": "dim" if structure else "warn", "locked": not structure, "action": "order", "arg": "repair"},
		{"icon": "circle_dashed", "name": "Sell", "key": "Del", "cost": "Partial refund" if structure else "Select a structure", "cost_tone": "dim" if structure else "warn", "locked": not structure, "action": "order", "arg": "sell"},
	]
	return {"title": "Orders", "right": "", "cards": cards}


# ------------------------------------------------------------------ build layout

## The Build board: shown while the Build tab is active. Keys the main HUD uses are left out so those sections clear.
func _build_vm(now: float, deficit: int) -> Dictionary:
	var armed := _armed_card()
	var added_kw: int = armed[5] if not armed.is_empty() else 0
	var chips: Array = []
	var money := {"label": "Material", "value": str(g.bridge_money)}
	if not armed.is_empty():
		money["note"] = "planned -%d" % armed[4]
		money["note_tone"] = "warn"
	chips.append(money)
	var power := {"label": "Power", "value": "%d / %d kW" % [g.bridge_power_demand, g.bridge_power_generation], "warn": deficit > 0}
	if not armed.is_empty() and added_kw != 0:
		power["note"] = "forecast %d" % (g.bridge_power_demand + added_kw)
		power["note_tone"] = "warn" if g.bridge_power_demand + added_kw > g.bridge_power_generation else "dim"
	chips.append(power)
	chips.append({"label": "Crew", "value": "%d / %d" % [g.bridge_supply_used, g.bridge_supply_cap]})
	var top := {"era": "Era %02d %s" % [g.bridge_era + 1, g.era_name()], "chips": chips}
	if g.bridge_next_wave_ticks >= 0:
		var seconds := ceili(float(g.bridge_next_wave_ticks) / TICKS_PER_SECOND)
		var commit := ceili(float(g.bridge_next_wave_ticks - 1350) / TICKS_PER_SECOND)
		top["wave"] = {"label": "Wave %02d" % (g.bridge_waves + 1), "timer": "%02d:%02d" % [seconds / 60, seconds % 60], "note": "doctrine in %02d:%02d" % [commit / 60, commit % 60] if commit > 0 else "doctrine committed"}
	var vm := {
		"build_top": top,
		"build_minimap": {},
		"map_marks": {"marks": _marks(), "view": _view()},
		"build_alerts": {"rows": _build_alert_rows(armed), "crumbs": ["Earth", "Earthfront", "Base"]},
		"deck": {"body": _build_body()},
	}
	var forecast: int = g.bridge_power_demand + maxi(added_kw, 0) - g.bridge_power_generation - maxi(-added_kw, 0)
	if forecast > 0 and (not armed.is_empty() or now - _deficit_since < 8.0 or g.mouse_position().y <= 66.0):
		vm["build_power"] = {
			"title": "%s %d kW" % ["Forecast deficit" if not armed.is_empty() and deficit <= 0 else "Grid deficit", forecast],
			"tag": "After commissioning" if not armed.is_empty() else "Throttling industry",
			"body": "Generation %d kW against %d kW demand. Defence and extraction receive power before factories and science." % [g.bridge_power_generation, g.bridge_power_demand + maxi(added_kw, 0)],
			"buttons": [{"label": "Focus on map", "action": "focus_power"}, {"label": "Plan a Reactor (P)", "action": "arm_build", "arg": "power"}],
		}
	if not armed.is_empty():
		vm["build_placement"] = _placement(armed, added_kw)
	return vm


func _armed_card() -> Array:
	for card in BUILD_CARDS:
		if card[1] == g.build_mode:
			return card
	return []


func _card_block_reason(card: Array) -> String:
	if not g.bridge_active or not g.bridge_unlocked_buildings.has(card[1]):
		return "Not researched"
	return ""


func _build_alert_rows(armed: Array) -> Array:
	var rows: Array = []
	for a in _alerts:
		rows.append({"tone": a["tone"] if a["tone"] != "cyan" else "", "icon": "warning" if a["tone"] != "cyan" else "clock", "text": a["title"]})
	if not armed.is_empty() and g.bridge_money < armed[4]:
		rows.append({"tone": "warn", "icon": "clock", "text": "%s: materials %d short" % [armed[2], armed[4] - g.bridge_money]})
	return rows


func _build_body() -> Dictionary:
	var cards: Array = []
	for card in BUILD_CARDS:
		var reason := _card_block_reason(card)
		var entry := {"id": card[0], "name": card[2], "sprite": SPR + card[7], "key": card[3], "cost": _cost_line(card[4], card[5]), "prereq": card[6]}
		if reason != "":
			entry["locked"] = true
			entry["prereq"] = reason
		elif g.bridge_money < card[4]:
			entry["short"] = true
			entry["prereq"] = "Need %d more material" % (card[4] - g.bridge_money)
		if g.build_mode == card[1]:
			entry["selected"] = true
		cards.append(entry)
	var tabs: Array = []
	for t in TABS:
		tabs.append({"id": t[0], "label": t[1], "on": t[0] == tab})
	var body := {"kind": "build", "tabs": tabs, "cards": cards, "legend": ["M materials", "kW power draw (+ is output)"]}
	var queue := _queue()
	if not queue.is_empty():
		body["queue"] = {"title": "Queue: " + String(g.selected.get_meta("production_name", "")), "tag": "Producing", "tone": "cyan", "detail": "Selected structure", "ratio": queue[0]["ratio"], "ratio_label": "%d%%" % roundi(queue[0]["ratio"] * 100.0), "sprite": SPR + "foundation_v1.png"}
	return body


static func _cost_line(material: int, kw: int) -> String:
	return "%d M %s kW" % [material, "+%d" % -kw if kw < 0 else str(kw)]


func _placement(card: Array, added_kw: int) -> Dictionary:
	var valid: bool = g.build_cursor_valid()
	var affordable: bool = g.bridge_money >= card[4]
	var tone := "good" if valid and affordable else "bad"
	var status := "Valid and affordable" if valid and affordable else ("Invalid location" if not valid else "Materials %d short" % (card[4] - g.bridge_money))
	var generation: int = g.bridge_power_generation + maxi(-added_kw, 0)
	var after := _projection(generation, g.bridge_power_demand, maxi(added_kw, 0))
	var note := "Click to place. Available material falls from %d to %d." % [g.bridge_money, g.bridge_money - card[4]] if affordable else "Short by %d material." % (card[4] - g.bridge_money)
	return {
		"sprite": SPR + card[7], "tone": tone, "status": status, "title": "%s / Preview" % card[2],
		"costs": [{"cap": "Materials", "value": str(card[4])}, {"cap": "Power", "value": "%s kW" % ("+%d" % -card[5] if card[5] < 0 else str(card[5])), "tone": "warn" if after["over"] > 0 else ""}],
		"note": note,
		"grid": {"value": after["value"], "tone": after["tone"], "note": "after commissioning", "segments": after["segments"], "marker": after["marker"],
			"lead": "%d kW over capacity." % after["over"] if after["over"] > 0 else "", "text": "Defence keeps priority; industry shares the deficit." if after["over"] > 0 else ""},
		"checks": [{"ok": valid, "text": "Inside construction zone"}, {"ok": affordable, "text": "Material available"}],
		"hints": [{"key": "Click", "label": "place"}, {"key": "Esc", "label": "cancel"}],
	}


## Same maths as build_logic.projection, repeated here so the adapter has no dependency on the Build screen script.
static func _projection(generation: int, demand: int, added: int) -> Dictionary:
	return preload("res://scripts/ui/build_logic.gd").projection(generation, demand, added)


# ------------------------------------------------------------------ actions in

## Routes a HUD action to the game's existing handlers.
func on_action(name: String, arg: Variant) -> void:
	match name:
		"deck_tab":
			if arg == "science":
				g._on_command_button("research_next")
			else:
				tab = str(arg)
		"train":
			g._on_command_button("train_" + str(arg))
		"arm_build":
			g._on_command_button("build_" + str(arg))
		"build_power":
			g._on_command_button("build_power")
		"order":
			_order(str(arg))
		"select_group":
			var same: Array = g.selected_units.filter(func(n): return is_instance_valid(n) and String(n.get_meta("kind_name", "")) == str(arg))
			if not same.is_empty():
				g._set_selection(same)
		"focus_power":
			for node in g.bridge_nodes.values():
				if is_instance_valid(node) and String(node.get_meta("kind_name", "")) == "PowerPlant":
					g.focus_camera(node.global_position, 8.2)
					break
		"jump_hq":
			_focus_hq()
		"minimap_layer", "speed":
			pass


func _order(verb: String) -> void:
	match verb:
		"attack_move":
			g._on_command_button("attack")
		"repair", "sell":
			g._on_command_button(verb)
		"focus":
			if is_instance_valid(g.selected):
				g.focus_camera(g.selected.global_position, 8.2)
		"hq":
			_focus_hq()


func _focus_hq() -> void:
	var hq: Node3D = assault.hq_node()
	if hq != null:
		g.focus_camera(hq.global_position if hq.is_inside_tree() else hq.position, 8.8)
