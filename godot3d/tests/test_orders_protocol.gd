extends RefCounted
## Task 13 (kestrel-depth): the Kestrel order keys and the attack-target click write the bridge's depth lines
## (`stop,<id>`, `hold,<id>`, `stance,<id>,<name>`, `target,<id>,<eid>`); Survival writes none of them. The keys are
## driven through the real _unhandled_input; the right click is driven through its two halves (the enemy pick and the
## order) because a real click needs the scene in a tree to project the camera.
const MainScene = preload("res://main.tscn")
const Keybinds := preload("res://scripts/ui/keybinds.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")
const Stub := preload("res://tests/stub_game.gd")
const RUNTIME := "user://orders_protocol_runtime"

const UI_STUB := """extends Node
var session_log := Log.new()
var hud := Control.new()
func route_title_key(_event: InputEvent) -> bool:
	return false
func route_key(_event: InputEvent, _armed := false) -> bool:
	return false
func world_blocked() -> bool:
	return false
func set_tab(_tab: String) -> void:
	pass
func notify(_title: String, _body: String, _color: Color) -> void:
	pass
func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
	return true
class Log:
	func unit_added(_kind: String, _team: int, _category: String) -> void:
		pass
	func unit_removed(_kind: String, _team: int, _category: String) -> void:
		pass
"""


func _ui_stub() -> Node:
	var s := GDScript.new()
	s.source_code = UI_STUB
	s.reload()
	var n := Node.new()
	n.set_script(s)
	return n


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))


func _scene(kestrel: bool) -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var snap := _snap()
	if not kestrel:
		snap["ground"] = "g".repeat(44 * 26)
	scene._sync_ground(snap)
	scene.ui = _ui_stub()
	scene.mission_deployed = true
	scene.bridge_active = true
	_clear()
	scene.runtime_directory = RUNTIME
	return scene


func _done(scene: Node3D) -> void:
	_clear()
	scene.ui.hud.free()
	scene.ui.free()
	scene.free()


func _unit(scene, id: int, kind: String, owner: int, tile: Vector2i, stance := "") -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	var e := {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100}
	if stance != "":
		e["stance"] = stance
	return e


func _place(scene, entities: Array) -> void:
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	scene.bridge_initialized = true


## The lines written since the last call, oldest first (the packets are consumed, as the bridge would).
func _lines() -> Array:
	var dir := ProjectSettings.globalize_path(RUNTIME.path_join("commands"))
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if str(f).ends_with(".cmd"):
			out.append(FileAccess.get_file_as_string(dir.path_join(f)).strip_edges())
			DirAccess.remove_absolute(dir.path_join(f))
	return out


func _clear() -> void:
	_lines()


func _press(scene, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	scene._unhandled_input(ev)


func _kestrel_army(scene) -> void:
	_place(scene, [
		_unit(scene, 750, "Infantry", 0, Vector2i(10, 12), "aggressive"),
		_unit(scene, 751, "Tank", 0, Vector2i(11, 12), "aggressive"),
		_unit(scene, 760, "Infantry", 1, Vector2i(15, 12)),
	])


func test_s_d_and_z_write_depth_lines_for_the_selection_on_kestrel(t) -> void:
	var scene := _scene(true)
	t.ok(scene.world_art_on, "the committed Kestrel snapshot turns world art on")
	_kestrel_army(scene)
	scene._set_selection([scene.bridge_nodes[750], scene.bridge_nodes[751]])
	_press(scene, Keybinds.STOP)
	t.eq(_lines(), ["stop,750", "stop,751"], "S stops every selected unit")
	_press(scene, Keybinds.HOLD)
	t.eq(_lines(), ["hold,750", "hold,751"], "D holds every selected unit")
	t.eq(scene._selection_stance(), "hold", "hold is shown at once, before the next snapshot")
	_press(scene, Keybinds.STANCE)
	t.eq(_lines(), ["stance,750,aggressive", "stance,751,aggressive"], "Z from hold wraps to aggressive")
	_press(scene, Keybinds.STANCE)
	t.eq(_lines(), ["stance,750,defensive", "stance,751,defensive"], "then defensive")
	_press(scene, Keybinds.STANCE)
	t.eq(_lines(), ["stance,750,hold", "stance,751,hold"], "then hold")
	# A mixed selection is brought to one stance: the first one in the cycle.
	scene.bridge_nodes[750].set_meta("stance", "defensive")
	t.eq(scene._selection_stance(), "mixed", "mixed stances read as mixed")
	_press(scene, Keybinds.STANCE)
	t.eq(_lines(), ["stance,750,aggressive", "stance,751,aggressive"], "a mixed selection goes aggressive")
	# Enemy units and buildings in the selection are never ordered.
	scene._set_selection([scene.bridge_nodes[760]])
	_press(scene, Keybinds.STOP)
	t.eq(_lines(), [], "an enemy unit takes no order")
	scene._set_selection([])
	_press(scene, Keybinds.HOLD)
	t.eq(_lines(), [], "nothing selected, nothing sent")
	_done(scene)


func test_the_snapshot_stance_reaches_the_node(t) -> void:
	var scene := _scene(true)
	_kestrel_army(scene)
	t.eq(str(scene.bridge_nodes[750].get_meta("stance", "")), "aggressive", "stance meta from the snapshot")
	t.eq(str(scene.bridge_nodes[760].get_meta("stance", "")), "", "an alien unit has none")
	scene._sync_bridge_entities([_unit(scene, 750, "Infantry", 0, Vector2i(10, 12), "hold"), _unit(scene, 760, "Infantry", 1, Vector2i(15, 12))])
	t.eq(str(scene.bridge_nodes[750].get_meta("stance", "")), "hold", "updated by the next snapshot")
	_done(scene)


func test_survival_keys_write_nothing_and_z_still_rotates(t) -> void:
	var scene := _scene(false)
	t.ok(not scene.world_art_on, "the flat ground keeps Survival's profile")
	_place(scene, [_unit(scene, 750, "Infantry", 0, Vector2i(10, 12)), _unit(scene, 760, "Infantry", 1, Vector2i(15, 12))])
	scene._set_selection([scene.bridge_nodes[750]])
	for code in [Keybinds.STOP, Keybinds.HOLD, Keybinds.STANCE]:
		_press(scene, code)
	t.eq(_lines(), [], "S, D and Z send nothing on Survival")
	t.eq(scene._order_target(scene.bridge_nodes[760]), false, "no attack-target order on Survival")
	t.eq(_lines(), [], "and no target line")
	t.eq(Keybinds.CAMERA_ACTIONS["camera_rotate_left"], Keybinds.STANCE, "Z is the rotate key Survival keeps")
	var yaw: float = scene.camera_yaw
	scene._camera_step(0.5, Vector3.ZERO, 16.0 / 9.0, -1.0)
	t.ok(not is_equal_approx(scene.camera_yaw, yaw), "Survival still rotates on the Z axis")
	_done(scene)


func test_right_click_on_a_live_enemy_focuses_it(t) -> void:
	var scene := _scene(true)
	_kestrel_army(scene)
	var ghost := _unit(scene, 761, "Infantry", 1, Vector2i(18, 12))
	_place(scene, [
		_unit(scene, 750, "Infantry", 0, Vector2i(10, 12), "aggressive"),
		_unit(scene, 751, "Tank", 0, Vector2i(11, 12), "aggressive"),
		_unit(scene, 760, "Infantry", 1, Vector2i(15, 12)),
		ghost,
	])
	scene.bridge_nodes[761].set_meta("remembered", true)  # a memory under the fog is no target
	scene._set_selection([scene.bridge_nodes[750], scene.bridge_nodes[751]])
	var to_screen := func(n: Node3D, offset: Vector3) -> Vector2: return Vector2(n.position.x + offset.x, n.position.z + offset.z) * 100.0
	var foe: Node3D = scene.bridge_nodes[760]
	var at: Vector2 = to_screen.call(foe, Vector3.ZERO)
	t.eq(scene._pick_entity(at, to_screen, true), foe, "the enemy pick finds the live alien")
	t.eq(scene._pick_entity(at, to_screen), null, "the selection pick never does")
	var ghost_at: Vector2 = to_screen.call(scene.bridge_nodes[761], Vector3.ZERO)
	t.eq(scene._pick_entity(ghost_at, to_screen, true), null, "a remembered enemy is not picked")
	var own_at: Vector2 = to_screen.call(scene.bridge_nodes[750], Vector3.ZERO)
	t.eq(scene._pick_entity(own_at, to_screen, true), null, "nor is one of ours")
	t.ok(scene._order_target(foe), "the order is sent")
	t.eq(_lines(), ["target,750,760", "target,751,760"], "every selected unit focuses the enemy")
	t.ok(not scene._order_target(null), "a click on no enemy is no target order")
	t.ok(not scene._order_target(scene.bridge_nodes[750]), "nor a click on a friend")
	t.eq(_lines(), [], "nothing written for either")
	# The real click handler tries the target before the move, and only on a unit selection.
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	var input := src.substr(src.find("func _unhandled_input(event: InputEvent) -> void:"))
	input = input.substr(0, input.find("\nfunc ", 10))
	var target_at := input.find("_order_target(foe)")
	var move_at := input.find("_write_bridge_move(unit, ground")
	t.ok(target_at > 0 and target_at < move_at, "the right click tries the target first")
	_done(scene)


func test_kestrel_selection_offers_stop_hold_and_a_stance_chip(t) -> void:
	var g := Stub.new()
	var a := Adapter.new(g)
	a.tab = "units"
	g.world_art_on = true
	var rifle: Node3D = g.add_node(5, "Infantry", "unit", 0, Vector3.ZERO)
	var tank: Node3D = g.add_node(6, "Tank", "unit", 0, Vector3.ZERO)
	rifle.set_meta("stance", "aggressive")
	tank.set_meta("stance", "aggressive")
	g.selected_units = [rifle, tank]
	g.selected = rifle
	var sel: Dictionary = a.hud_vm(0.0)["selection"]
	var labels: Array = sel["orders"].map(func(o): return str(o["label"]))
	t.eq(labels, ["Attack-move", "Stop", "Hold", "Stance", "Focus group"], "four order cells and Focus")
	t.eq(sel["orders"].map(func(o): return str(o.get("key", ""))), ["A", "S", "D", "Z", "F"], "with their keys")
	var chip := {}
	for r in sel["rows"]:
		if r.get("label") == "Stance":
			chip = r
	t.eq(chip.get("value", ""), "Aggressive", "the stance chip")
	tank.set_meta("stance", "hold")
	rifle.set_meta("stance", "hold")
	for r in a.hud_vm(0.0)["selection"]["rows"]:
		if r.get("label") == "Stance":
			chip = r
	t.eq(chip.get("value", ""), "Hold", "follows the units")
	t.eq(chip.get("tone", ""), "warn", "hold stands out")
	rifle.set_meta("stance", "defensive")
	for r in a.hud_vm(0.0)["selection"]["rows"]:
		if r.get("label") == "Stance":
			chip = r
	t.eq(chip.get("value", ""), "Mixed", "a mixed selection says so")
	for verb in ["stop", "hold", "stance"]:
		a.on_action("order", verb)
	t.eq(g.calls.slice(-3), [["command", "stop"], ["command", "hold"], ["command", "stance"]], "the buttons reach the game")
	# Survival keeps two orders and no chip.
	g.world_art_on = false
	sel = a.hud_vm(0.0)["selection"]
	t.eq(sel["orders"].size(), 2, "Survival: attack-move and focus only")
	t.ok(sel["rows"].all(func(r): return r.get("label") != "Stance"), "Survival: no stance chip")
	rifle.free()
	tank.free()
