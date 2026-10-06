extends RefCounted
## Stands in for earthfront_3d.gd: the members and methods live_adapter.gd reads, with the real game's names.
var bridge_active := true
var bridge_money := 840
var bridge_ore := 210
var bridge_energy := 1488
var bridge_storage_capacity := 2400
var bridge_power_generation := 160
var bridge_power_demand := 168
var bridge_supply_used := 22
var bridge_supply_cap := 60
var bridge_depot_ammo := 72
var bridge_era := 0
var bridge_earthfront := true
var bridge_services: Dictionary = {}
var bridge_relays := 2
var bridge_active_relays := 2
var bridge_expedition_size := 14
var bridge_incoming_doctrine := "Siege expedition"
var bridge_next_wave_ticks := 1350
var bridge_waves := 1
var bridge_tick := 0
var bridge_poll_elapsed := 0.05  # seconds since the last snapshot poll; 0.0 on a poll frame
var bridge_research_count := 0
var bridge_technology_total := 12
var bridge_winner := -1
var bridge_research_options: Array = []
var bridge_active_research_id := -1
var bridge_active_research_ticks := 0
var bridge_active_research_name := ""
var bridge_unlocked_buildings: Array = ["PowerPlant", "Refinery", "Barracks"]
var bridge_unlocked_units: Array = ["Infantry", "AntiArmor", "Tank", "Harvester"]
var bridge_nodes: Dictionary = {}
var tutorial_stage := 8
var selected: Node3D
var selected_units: Array = []
var attack_move_armed := false
var rally_armed := false
var control_groups: Dictionary = {}
var build_mode := ""
var mouse := Vector2(900, 500)
var camera: Camera3D
var calls: Array = []
var objective_label := FakeLabel.new()
var viewport: Viewport  # set by tests that mount UI: the SceneTree root
var world_rect := Rect2(0, 0, 40, 30)
var seen_rect := Rect2(4, 3, 20, 15)


var cursor_valid := true

## Kestrel Reach: `use_kestrel()` loads the committed real snapshot, and the same members the game fills from it.
var kestrel := false
## Mirrors earthfront_3d.world_art_on: the HUD draws world sprites as its icons only when this is true.
var world_art_on := false
## Mirrors earthfront_3d.kestrel_objectives (the last KestrelObjectives result); empty here, so the HUD evaluates the snapshot.
var kestrel_objectives: Dictionary = {}
var bridge_snapshot: Dictionary = {}
var ground_model: RefCounted = null
## Hex under the cursor as a Vector2i, null when the pointer is off the map. The real game has no such member yet.
var hover_cell = null
## Mirrors earthfront_3d.alert_pings (Kestrel's AlertPings, null in Survival) and its clock (alert_clock: the effects time).
var alert_pings = null
var clock := 0.0


## `fog_off` loads the EARTHFRONT_FOG=0 twin of the start frame (every alien entity present) for tests about the alien base.
func use_kestrel(fog_off := false) -> void:
	var path := "res://tests/fixtures/kestrel_snapshot_fog_off.json" if fog_off else "res://tests/fixtures/kestrel_snapshot.json"
	var f := FileAccess.open(path, FileAccess.READ)
	bridge_snapshot = JSON.parse_string(f.get_as_text())
	ground_model = preload("res://scripts/terrain/ground_model.gd").from_snapshot(bridge_snapshot)
	kestrel = true
	world_art_on = true


func era_name() -> String:
	return "Contemporary"


func build_cursor_valid() -> bool:
	return cursor_valid


class FakeLabel:
	var text := ""


func get_viewport() -> Viewport:
	return viewport


func _deploy_mission() -> void:
	calls.append(["deploy"])


func _write_bridge_research(tech_id := -1) -> void:
	calls.append(["research", tech_id])


func _restart_mission() -> void:
	calls.append(["restart"])


func set_sim_paused(on: bool) -> void:
	calls.append(["pause", on])


func mouse_position() -> Vector2:
	return mouse


func minimap_world_rect() -> Rect2:
	return world_rect


func view_ground_rect() -> Rect2:
	return seen_rect


func alert_clock() -> float:
	return clock


func focus_camera(pos: Vector3, zoom: float) -> void:
	calls.append(["focus", pos, zoom])


func arm_rally() -> void:
	calls.append(["arm_rally"])


func recall_control_group(group: int) -> void:
	calls.append(["recall_group", group])


func _on_command_button(action: String) -> void:
	calls.append(["command", action])


func _set_selection(list: Array) -> void:
	selected_units.clear()
	for n in list:
		selected_units.append(n)
	selected = selected_units[0] if not selected_units.is_empty() else null
	calls.append(["select", list.size()])


func _has_selected_combat_unit() -> bool:
	for n in selected_units:
		if is_instance_valid(n) and String(n.get_meta("category", "")) == "unit":
			return true
	return false


func _human_count(category: String, kind_name := "") -> int:
	var count := 0
	for n in bridge_nodes.values():
		if int(n.get_meta("team", -1)) == 0 and String(n.get_meta("category", "")) == category and (kind_name == "" or String(n.get_meta("kind_name", "")) == kind_name):
			count += 1
	return count


## Helpers for tests.
func add_node(id: int, kind: String, category: String, team: int, pos: Vector3, hp := 100.0, max_hp := 100.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.set_meta("bridge_id", id)
	n.set_meta("kind_name", kind)
	n.set_meta("category", category)
	n.set_meta("team", team)
	n.set_meta("hp", hp)
	n.set_meta("max_hp", max_hp)
	bridge_nodes[id] = n
	return n
