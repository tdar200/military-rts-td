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
## Added after the others once the snapshot carries the ground layer (Earthfront): the map lens tab.
const LOGISTICS_TAB := ["logistics", "Logistics", "logistics"]
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

## Where the board 2 and 3 cards sit, and the heights the adapter keeps them clear with (the sections measure the real ones).
const PLACING_CARD_W := 340
const PLACING_CARD_H := 260
const GRID_CARD_H := 116
const COMBAT_CARD_H := 170
const MAX_ALERT_ROWS := 5
## Below the core assault objective panel (20,72) at its tallest.
const ENEMY_CARD_Y := 280
## Boards 4, 5 and 7: the left cards start at y 76, under the objectives panel when it is up. The heights are the cards' own
## (CONTROL_GROUPS_H is fixed: four rows), the others are estimated from their row counts in _board_slices.
const LEFT_STACK_TOP := 76.0
const LEFT_STACK_GAP := 8.0
const CONTROL_GROUPS_H := 148.0

var g  # earthfront_3d.gd, or a stub with the same members in tests
const LiveAssault = preload("res://scripts/ui/live_assault.gd")
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")
const OverlayFeed = preload("res://scripts/world/overlay_feed.gd")
const EarlyMission = preload("res://scripts/ui/sections/early_mission.gd")

var tab := "build"
## True while the first-minutes briefing card is up (game_ui.gd sets it): that card carries the objectives, so the objectives
## panel is left out and the left card stack starts below the briefing.
var briefing_up := false
## The active minimap lens (vm_gameplay.LENSES); lives here so the HUD stays a pure view.
var lens := "land"
## The Logistics tab's map overlay (overlay_feed.gd): "" off, otherwise power, supply, borders, coverage or yield. Client-side only.
var world_lens := ""
var _overlay_snap: Variant = null
var _overlay_lens := ""
var _overlay_hex: Array = []
## Legend, note, summary and supply rows of the active lens, built once per snapshot beside _overlay_hex.
var _overlay_text: Dictionary = {}
var assault
var _alerts: Array = []
var _ticker := ""
var _deficit_since := -1.0
var _territory_ground: Variant = null  # the territory slice and the ground model and zone it was computed from
var _territory_zone: Variant = null
var _territory_slice: Dictionary = {}


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
		return _with_hostile(assault.vm(now, _alerts, _tabs(), _selection(), g.attack_move_armed), true)
	if tab == "build":
		return _with_gameplay(_build_vm(now, deficit))
	var vm := {
		"brand": {"title": "Ascension", "sub": "Era %d / %s" % [g.bridge_era + 1, "Earthfront" if g.bridge_earthfront else "Campaign"]},
		"chips": _chips(),
		"minimap": {"keys": []},
		"map_marks": {"marks": _marks(), "view": _view()},
		"deck": {"tabs": _tabs(), "body": _deck_body()},
	}
	if not briefing_up:
		vm["objectives"] = _objectives()
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


## VmGameplay.territory walks every construction-zone hex (about 0.6 ms on Kestrel), but the zone only changes when a
## building goes up or comes down and the ground model never changes once built, so the answer is kept until either does.
func _territory(snap: Dictionary, ground) -> Dictionary:
	var zone = snap.get("construction_zone", [])
	if ground != _territory_ground or zone != _territory_zone:
		_territory_ground = ground
		_territory_zone = zone
		_territory_slice = VmGameplay.territory(snap, ground)
	return _territory_slice.duplicate(true)


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
		"territory": _territory(snap, ground),
		"idle": VmGameplay.idle_crews(snap),
		"alert": VmGameplay.next_alert(snap),
		"veterans": VmGameplay.veterans(snap),
		"yields": VmGameplay.yields(snap),
		"pins": _pins(snap),
	}
	# The bottom-centre colony panel, the minimap header and the lens exist only in the main layout: the build layout
	# draws its own deck, minimap and placement panel there, and a selection owns the bottom centre.
	var main_layout := not vm.has("build_top")
	if main_layout:
		slices["lens"] = _lens(snap)
		if not vm.has("selection"):
			var hovered = g.get("hover_cell")
			if hovered is Vector2i:
				var inspect := VmGameplay.tile_inspect(snap, ground, hovered.x, hovered.y)
				if not inspect.is_empty():
					inspect.merge(VmGameplay.tile_context(snap, ground, hovered.x, hovered.y))
					slices["inspect"] = inspect
			slices["ledger"] = VmGameplay.ledger(snap)
			slices["army"] = VmGameplay.army(snap)
	var regions := VmGameplay.regions(snap)
	if not regions.is_empty():
		slices["regions"] = regions
	for key in slices:
		if not slices[key].is_empty():
			vm[key] = slices[key]
	if not main_layout:
		_placing_slices(vm, snap, ground)
	_hostile_slices(vm, snap, ground)
	if main_layout and vm.has("minimap") and vm["minimap"] is Dictionary and str(snap.get("map_name", "")) != "":
		vm["minimap"]["name"] = str(snap["map_name"])
	if str(snap.get("map_name", "")) != "" and vm.has("brand") and vm["brand"] is Dictionary:
		vm["brand"]["sub"] = str(snap["map_name"])
	# The top bar's wave chip owns vm["wave"]; the expected route and ETA ride on it so that chip's own keys are untouched.
	var inbound := VmGameplay.wave_inbound(snap)
	if not inbound.is_empty() and vm.has("wave") and vm["wave"] is Dictionary:
		for key in inbound:
			vm["wave"][key] = inbound[key]
	if main_layout:
		_board_slices(vm, snap, ground)
	return vm


## Boards 4, 5 and 7: the selected-structure frame and site card, the armed banner and roster, the wave panel and the control
## group list. The left cards stack under the objectives panel (and push the territory card below them); a structure frame or
## roster replaces the old selection panel at the bottom centre. Needs the snapshot: without it nothing here is added.
func _board_slices(vm: Dictionary, snap: Dictionary, ground) -> void:
	var ids: Array = []
	for n in g.selected_units:
		if is_instance_valid(n) and n.has_meta("bridge_id"):
			ids.append(int(n.get_meta("bridge_id")))
	var top := LEFT_STACK_TOP
	var objectives = vm.get("objectives", null)
	if objectives is Dictionary:
		top = LEFT_STACK_TOP + 42.0 + 25.0 * (objectives.get("items", []) as Array).size() + LEFT_STACK_GAP
	elif briefing_up:
		top = EarlyMission.rect().end.y + LEFT_STACK_GAP
	var y := top
	var wave := VmGameplay.wave_panel(snap, ground)
	if not wave.is_empty():
		wave["y"] = y
		vm["wave_panel"] = wave
		# The panel carries the same time, size and doctrine as the top card, so the card steps aside.
		vm.erase("wave_card")
		y += 47.0 + (30.0 if str(wave.get("title", "")) != "" else 0.0) + 29.5 * (wave["rows"] as Array).size() + LEFT_STACK_GAP
	if ids.size() == 1:
		var structure := VmGameplay.structure(snap, ground, int(ids[0]))
		if not structure.is_empty():
			vm["structure"] = structure
			vm.erase("selection")
			var site := VmGameplay.site_card(snap, ground, int(ids[0]))
			if not site.is_empty():
				site["y"] = y
				vm["site"] = site
				y += 38.0 + 29.5 * (site["rows"] as Array).size() + LEFT_STACK_GAP
				# The site card stands in for the territory card, as on board 4.
				vm.erase("territory")
				vm.erase("yields")
	var groups := _control_groups()
	if not groups.is_empty():
		groups["y"] = y
		vm["control_groups"] = groups
		y += CONTROL_GROUPS_H + LEFT_STACK_GAP
	if (y > top or briefing_up) and vm.has("territory") and vm["territory"] is Dictionary:
		vm["territory"]["y"] = maxf(float(vm["territory"].get("y", 274.0)), y)
	if g.attack_move_armed:
		vm["armed"] = {"hint": "Right click a tile to go, Esc to cancel"}
		if not ids.is_empty():
			var roster := VmGameplay.roster(snap, ground, ids, true, vm.get("veterans", {}))
			if not roster.is_empty():
				vm["roster"] = roster
				vm.erase("selection")
	elif g.get("rally_armed") == true:
		vm["armed"] = {"title": "Set rally armed", "hint": "Left click a tile to set it, Esc to cancel", "tone": "cyan", "icon": "flag"}


## World marks for the selected building and the inbound wave, from the snapshot only (vm_gameplay.gd rally_hexes, wave_arrows,
## turret_fields). `project` is Callable(hex_x, hex_y) -> screen Vector2, Vector2.INF when behind the camera. A selected
## producer with a rally point gets a dotted path to it; a selected turret gets its weapon range as a ring (columns are 0.75
## of a row apart in sim space, so the horizontal radius counts columns); while the wave panel is up the expected route is
## drawn as red dashed segments. [] without a snapshot.
func board_marks(project: Callable) -> Array:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty():
		return []
	var marks: Array = []
	var picked: Array = []
	for n in g.selected_units:
		if is_instance_valid(n) and n.has_meta("bridge_id"):
			picked.append(int(n.get_meta("bridge_id")))
	if picked.size() == 1:
		var rally := VmGameplay.rally_hexes(snap, picked[0])
		if not rally.is_empty():
			var a: Vector2 = project.call(rally["from"][0], rally["from"][1])
			var b: Vector2 = project.call(rally["to"][0], rally["to"][1])
			if a != Vector2.INF and b != Vector2.INF:
				marks.append({"kind": "arrow", "x": a.x, "y": a.y, "c1": a.lerp(b, 1.0 / 3.0), "c2": a.lerp(b, 2.0 / 3.0), "to": b, "queued": true})
		for field in VmGameplay.turret_fields(snap):
			if int(field["id"]) != picked[0]:
				continue
			var cell: Array = field["cell"]
			var reach := VmGameplay.effective_turret_range(field, _ground_for(snap))
			var c: Vector2 = project.call(cell[0], cell[1])
			var east: Vector2 = project.call(int(cell[0]) + roundi(reach / VmGameplay.SIM_HEX_X), cell[1])
			var south: Vector2 = project.call(cell[0], int(cell[1]) + roundi(reach))
			if c != Vector2.INF and east != Vector2.INF and south != Vector2.INF:
				marks.append({"kind": "ring", "x": c.x, "y": c.y, "rx": absf(east.x - c.x), "ry": absf(south.y - c.y)})
	if VmGameplay.wave_in_window(snap):
		for seg in VmGameplay.wave_arrows(snap):
			var a: Vector2 = project.call(seg["from"][0], seg["from"][1])
			var b: Vector2 = project.call(seg["to"][0], seg["to"][1])
			if a != Vector2.INF and b != Vector2.INF:
				marks.append({"kind": "beam", "x": a.x, "y": a.y, "c1": a.lerp(b, 1.0 / 3.0), "c2": a.lerp(b, 2.0 / 3.0), "to": b})
	# The Logistics overlay shares this path and schema; nothing is computed unless that tab has a lens on.
	if tab == "logistics":
		var lens_id := active_world_lens(snap)
		if lens_id != "":
			marks.append_array(OverlayFeed.project(_overlay_marks(snap, lens_id), project))
	return marks


## The four control group slots as the list needs them: the kinds of each group's live units, and which group is the current
## selection. {} when no group holds a unit.
func _control_groups() -> Dictionary:
	var groups: Array = []
	var active := -1
	var picked: Array = []
	for n in g.selected_units:
		if is_instance_valid(n):
			picked.append(n)
	var table = g.get("control_groups")
	if not (table is Dictionary):
		return {}
	for n in table:
		var kinds: Array = []
		var live: Array = []
		for node in table[n]:
			if is_instance_valid(node):
				kinds.append(String(node.get_meta("kind_name", "")))
				live.append(node)
		groups.append({"n": int(n), "kinds": kinds})
		if not live.is_empty() and live.size() == picked.size() and live.all(func(node): return picked.has(node)):
			active = int(n)
	return VmGameplay.control_groups(groups, active)


## The game's ground model, or one decoded from the snapshot; null on flat or ground-less maps.
func _ground_for(snap: Dictionary):
	var ground = g.get("ground_model")
	if ground == null:
		ground = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	return ground


## The assault layout keeps its own panels; it only gains what board 3 adds on top: the enemy territory card and, over a
## hostile hex with units selected, the combat preview and its pin.
func _with_hostile(vm: Dictionary, enemy_card: bool) -> Dictionary:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty():
		return vm
	var ground = g.get("ground_model")
	if ground == null:
		ground = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	if enemy_card:
		var intel := VmGameplay.enemy_intel(snap, ground)
		if not intel.is_empty():
			intel["y"] = ENEMY_CARD_Y
			vm["enemy"] = intel
	_hostile_slices(vm, snap, ground)
	return vm


## Combat preview and hostile pin: the hovered hex holds an alien entity and human units are selected. Needs a game that
## can project a hex; nothing is added otherwise.
func _hostile_slices(vm: Dictionary, snap: Dictionary, ground) -> void:
	var hovered = g.get("hover_cell")
	if not (hovered is Vector2i) or ground == null or not g.has_method("screen_point_of_hex"):
		return
	var ids: Array = []
	for n in g.selected_units:
		if is_instance_valid(n) and n.has_meta("bridge_id"):
			ids.append(int(n.get_meta("bridge_id")))
	if ids.is_empty():
		return
	var combat := VmGameplay.combat_preview(snap, ground, ids, [hovered.x, hovered.y])
	if combat.is_empty():
		return
	var at: Vector2 = g.screen_point_of_hex(hovered.x, hovered.y)
	if at == Vector2.INF:
		return
	combat["x"] = clampi(roundi(at.x) + 40, 12, 1920 - 12 - 330)
	combat["y"] = clampi(roundi(at.y) + 74, 70, 1080 - 12 - COMBAT_CARD_H)
	vm["combat"] = combat
	var kind := ""
	for e in snap.get("entities", []):
		if e is Dictionary and int(e.get("owner", 0)) != VmGameplay.HUMAN:
			var c := VmGameplay.entity_cell(e)
			if int(c[0]) == hovered.x and int(c[1]) == hovered.y:
				kind = str(KIND_NAMES.get(str(e.get("kind", "")), str(e.get("kind", ""))))
				break
	if kind != "" and at.x >= 20.0 and at.x <= 1900.0 and at.y >= 110.0 and at.y <= 760.0:
		var pins: Array = vm.get("pins", [])
		pins = pins.duplicate()
		pins.append({"x": roundf(at.x), "y": roundf(at.y), "kind": kind, "hostile": true})
		vm["pins"] = pins


## Right edge for the top-strip placement hint chip: left of the wave chip, whose width is estimated from its text (the strip
## is laid out from the right edge by build_deck.gd, which does not report widths).
func _hint_right(vm: Dictionary) -> float:
	var top = vm.get("build_top", {})
	var wave = top.get("wave", {}) if top is Dictionary else {}
	if not (wave is Dictionary) or wave.is_empty():
		return 1892.0
	var width := 22.0 + 60.5 + 8.0 + 50.0
	var note := str(wave.get("note", ""))
	if note != "":
		width += 8.0 + 7.8 * note.length()
	return 1904.0 - width - 12.0 - 8.0


## The Build board's placement card and projected grid, in place of the old 728px preview panel. Both need the hovered hex
## and its ground; without them (no snapshot, pointer off the map or over the HUD) the old panel stays.
func _placing_slices(vm: Dictionary, snap: Dictionary, ground) -> void:
	var armed := _armed_card()
	var hovered = g.get("hover_cell")
	if armed.is_empty() or ground == null or not (hovered is Vector2i) or not g.has_method("screen_point_of_hex"):
		return
	var ghost = g.get("build_ghost")
	if ghost is Node3D and is_instance_valid(ghost) and not ghost.visible:
		return
	var card := VmGameplay.placing(snap, ground, armed[1], armed[2], hovered.x, hovered.y, g.build_cursor_valid(), armed[5])
	var at: Vector2 = g.screen_point_of_hex(hovered.x, hovered.y)
	if card.is_empty() or at == Vector2.INF:
		return
	# The board puts the card 138px below and 76px left of the cursor; it is kept on screen and clear of the deck (x 1124+).
	card["x"] = clampi(roundi(at.x) - 76, 12, 1124 - PLACING_CARD_W - 12)
	card["y"] = clampi(roundi(at.y) + 138, 70, 1068 - PLACING_CARD_H)
	vm["placement_hint"] = {"right": _hint_right(vm)}
	vm["placing"] = card
	var grid := VmGameplay.power_grid(snap, ground, armed[1], armed[5])
	if not grid.is_empty():
		var rows: Array = []
		if vm.get("build_alerts") is Dictionary:
			rows = vm["build_alerts"].get("rows", [])
		var n := mini(rows.size(), MAX_ALERT_ROWS)
		var rows_top := 736.0 - 46.0 * (n - 1) if n > 0 else 736.0
		grid["y"] = mini(560, int(rows_top - 14.0 - GRID_CARD_H))
		vm["power_grid"] = grid
	vm.erase("build_placement")
	if armed[1] == "Refinery" and vm.get("pins") is Array:
		for pin in vm["pins"]:
			if str(pin.get("kind", "")) == "Ore" and pin.has("cell") and VmGameplay.hex_distance(hovered.x, hovered.y, int(pin["cell"][0]), int(pin["cell"][1])) <= VmGameplay.ORE_BONUS_RADIUS:
				pin["in_range"] = true


## Deposit pins: the deposits on screen, anchored to where the camera sees them. Needs a game that can project a hex.
func _pins(snap: Dictionary) -> Array:
	if not g.has_method("screen_point_of_hex"):
		return []
	var pins: Array = []
	for pin in VmGameplay.deposit_pins(snap):
		var at: Vector2 = g.screen_point_of_hex(int(pin["x"]), int(pin["y"]))
		if at == Vector2.INF or at.x < 20.0 or at.x > 1900.0 or at.y < 110.0 or at.y > 760.0:
			continue
		pin["cell"] = [pin["x"], pin["y"]]
		pin["x"] = roundf(at.x)
		pin["y"] = roundf(at.y)
		pins.append(pin)
	return pins


## The minimap lens: which one is on, and its overlay in 0..1 minimap space (hex centres through the minimap's world rect).
func _lens(snap: Dictionary) -> Dictionary:
	var out := {"on": lens}
	if lens == "land" or not g.has_method("hex_world_point"):
		return out
	var world: Rect2 = g.minimap_world_rect()
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return out
	var hexes := VmGameplay.lens_hexes(snap, lens)
	if hexes.is_empty():
		return out
	var to_unit := func(c) -> Dictionary:
		var p: Vector3 = g.hex_world_point(int(c["x"]) if c is Dictionary else int(c[0]), int(c["y"]) if c is Dictionary else int(c[1]))
		var d := {"u": snappedf((p.x - world.position.x) / world.size.x, 0.001), "v": snappedf((p.z - world.position.y) / world.size.y, 0.001)}
		if c is Dictionary and c.has("k"):
			d["k"] = c["k"]
		return d
	var overlay := {}
	for key in ["dots", "cells", "route"]:
		if hexes.has(key):
			overlay[key] = hexes[key].map(to_unit)
	var step_x: float = absf(g.hex_world_point(2, 0).x - g.hex_world_point(0, 0).x) * 0.5
	var step_z: float = absf(g.hex_world_point(0, 1).z - g.hex_world_point(0, 0).z)
	overlay["cell"] = {"w": snappedf(step_x / world.size.x, 0.001), "h": snappedf(step_z / world.size.y, 0.001)}
	out["overlay"] = overlay
	return out


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

## The deck's tab list: Logistics joins once the snapshot has ground (Earthfront); it stays hidden otherwise.
func _tab_defs() -> Array:
	var snap = g.get("bridge_snapshot")
	if snap is Dictionary and OverlayFeed.tab_available(snap):
		return TABS + [LOGISTICS_TAB]
	return TABS


func _tabs() -> Array:
	var tabs: Array = []
	for t in _tab_defs():
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
		"logistics":
			return _logistics_body()
		_:
			return {"title": "Build", "right": "", "cards": []}


## The lens the overlay really uses: the chosen one, if the snapshot can back it ("" otherwise).
func active_world_lens(snap: Dictionary) -> String:
	return world_lens if world_lens != "" and OverlayFeed.available(snap).has(world_lens) else ""


## Hex-space marks of the lens, recomputed only when the snapshot (a new dictionary per bridge tick) or the lens changes.
func _overlay_marks(snap: Dictionary, lens: String) -> Array:
	if not (is_same(snap, _overlay_snap) and lens == _overlay_lens):
		_overlay_snap = snap
		_overlay_lens = lens
		_overlay_hex = OverlayFeed.marks(snap, lens)
		_overlay_text = _lens_text(snap, lens, _overlay_hex)
	return _overlay_hex


## What the Logistics tab says about the lens: the legend, note, summary (or the empty line) and, for Supply, the depot rows.
## Held per snapshot with the marks: the borders summary walks the enemy border, which must not run every frame.
func _lens_text(snap: Dictionary, lens: String, drawn: Array) -> Dictionary:
	var text := {"legend": OverlayFeed.legend(snap, lens), "note": OverlayFeed.note(lens)}
	var summary := OverlayFeed.summary(snap, lens, drawn)
	if summary != "":
		text["summary"] = summary
	else:
		text["empty"] = OverlayFeed.empty_text(lens)
	if lens == "supply":
		text["routes"] = OverlayFeed.routes(snap)
	return text


## Lens buttons for the lenses the snapshot backs (Supply only when the bridge sent real supply_links), plus the active
## lens's legend and what it draws, held per snapshot. {} without a snapshot.
func _logistics_body() -> Dictionary:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty():
		return {}
	var lenses: Array = []
	var active := active_world_lens(snap)
	for id in OverlayFeed.available(snap):
		lenses.append({"id": id, "label": OverlayFeed.LABELS[id], "on": id == active})
	var body := {"kind": "logistics", "lenses": lenses, "lens": active}
	if active != "":
		_overlay_marks(snap, active)
		body.merge(_overlay_text, true)
	return body


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
	for t in _tab_defs():
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
		"set_rally":
			if g.has_method("arm_rally"):
				g.arm_rally()
		"recall_group":
			if g.has_method("recall_control_group"):
				g.recall_control_group(int(arg))
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
		"select_army":
			if g.has_method("select_army"):
				g.select_army()
		"select_idle":
			var node = g.bridge_nodes.get(int(arg), null)
			if is_instance_valid(node):
				g._set_selection([node])
				g.focus_camera(node.global_position if node.is_inside_tree() else node.position, 8.2)
		"focus_deposit":
			if arg is Array and arg.size() >= 2 and g.has_method("hex_world_point"):
				g.focus_camera(g.hex_world_point(int(arg[0]), int(arg[1])), 8.2)
		"minimap_lens":
			if str(arg) in VmGameplay.LENSES:
				lens = str(arg)
		"world_lens":
			if str(arg) == "" or OverlayFeed.LENSES.has(str(arg)):
				world_lens = str(arg)
		"minimap_layer", "speed":
			pass


func _order(verb: String) -> void:
	match verb:
		"attack_move":
			g._on_command_button("attack")
		"repair", "sell":
			g._on_command_button(verb)
		"cancel_armed":
			g._on_command_button("cancel_orders")
		"focus":
			if is_instance_valid(g.selected):
				g.focus_camera(g.selected.global_position, 8.2)
		"hq":
			_focus_hq()


## Centres the CC. On Kestrel the Home key frames the base east of it (`home_focus`); this jump answers an HQ alert, so the
## fight around the CC stays mid-frame instead of at the left edge.
func _focus_hq() -> void:
	var hq: Node3D = assault.hq_node()
	if hq != null:
		g.focus_camera(hq.global_position if hq.is_inside_tree() else hq.position, 8.8)
