extends RefCounted
## Restart (fix round, final review M3): _restart_mission writes restart.flag and waits 0.35 s before reloading the scene.
## The bridge restarts at once and writes a tick-0 snapshot; the old scene used to read it, take every unit missing from
## the fresh start as dead and play death explosions and sounds just before the reload. While `_restarting` is set the old
## scene reads no snapshot and asks the audio director for nothing.
const MainScene = preload("res://main.tscn")
const RUNTIME := "user://restart_wait_runtime"


class Recorder extends RefCounted:
	var calls: Array = []
	var loop_calls := 0

	func request(id: String, at: Vector3, now: float) -> Dictionary:
		calls.append({"id": id, "at": at, "now": now})
		return {"play": false, "id": id, "reason": "recorded"}

	func set_view(_rect: Rect2) -> void:
		pass

	func set_paused(_on: bool) -> void:
		pass

	func loops(_moving: Dictionary) -> Dictionary:
		loop_calls += 1
		return {}

	func duck_db(_now: float) -> float:
		return 0.0


const UI_STUB := """extends Node
var session_log := Log.new()
var hud := Control.new()
func set_tab(_tab: String) -> void:
	pass
func notify(_title: String, _body: String, _color: Color) -> void:
	pass
func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
	return false
class Log:
	var removed := 0
	func unit_added(_kind: String, _team: int, _category: String) -> void:
		pass
	func unit_removed(_kind: String, _team: int, _category: String) -> void:
		removed += 1
"""


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))


func _scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	scene.world_fx.set_view(scene._hex_world(12, 12), Vector2(12, 10))
	var s := GDScript.new()
	s.source_code = UI_STUB
	s.reload()
	var ui := Node.new()
	ui.set_script(s)
	scene.ui = ui
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
	scene.runtime_directory = RUNTIME
	return scene


func _poll(scene: Node3D, snap: Dictionary) -> void:
	snap["shots"] = []
	var f := FileAccess.open(RUNTIME.path_join("snapshot.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	scene.bridge_poll_elapsed = 0.0
	scene._poll_bridge(1.0)


func test_the_old_scene_ignores_the_restarted_bridge(t) -> void:
	var scene := _scene()
	var rec := Recorder.new()
	scene.audio = rec
	var first := _snap()
	first["tick"] = 2400
	_poll(scene, first)
	var nodes: int = scene.bridge_nodes.size()
	t.ok(nodes > 0, "the running match has its entities")
	t.ok(not scene._restarting, "not restarting while playing")
	var cues: int = rec.calls.size()  # the running match's own cues (the probe warning at this tick)
	scene._restarting = true  # what _restart_mission sets before its 0.35 s wait
	var fresh := _snap()
	fresh["tick"] = 0
	fresh["entities"] = []  # everything the old scene knew is missing from the new sim's first frame
	_poll(scene, fresh)
	t.eq(scene.bridge_tick, 2400, "the restarted bridge's snapshot is not read")
	t.eq(scene.bridge_nodes.size(), nodes, "no entity is taken as dead")
	t.eq(scene.ui.session_log.removed, 0, "no unit-lost log line")
	t.eq(rec.calls.size(), cues, "no death sound or any other cue")
	scene._update_audio()
	t.eq(rec.loop_calls, 0, "the audio update stands still too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME.path_join("snapshot.json")))
	scene.ui.hud.free()
	scene.ui.free()
	scene.free()


func test_restart_sets_the_flag_before_it_waits(t) -> void:
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	var at := src.find("func _restart_mission() -> void:")
	t.ok(at >= 0, "_restart_mission exists")
	var body := src.substr(at, src.find("\n\n\n", at) - at)
	var flag := body.find("_restarting = true")
	t.ok(flag > 0 and flag < body.find("await "), "the flag is set before the wait: %s" % body)
	var poll := src.substr(src.find("func _poll_bridge(delta: float) -> void:"), 200)
	t.ok(poll.contains("if _restarting:\n\t\treturn"), "the poll returns early while restarting")
	var audio := src.substr(src.find("func _update_audio() -> void:"), 200)
	t.ok(audio.contains("_restarting"), "and the audio update")
