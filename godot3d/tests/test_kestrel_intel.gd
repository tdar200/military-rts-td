extends RefCounted
## Kestrel briefing intel (fix round, final review I1): under fog the alien probe's picket on the east bank is dark, so the
## first-minute warning the probe was staged for never showed. The client now gives one scouting toast and the alert sound
## at the probe's scripted stage tick, without revealing where the probe is: no minimap ring, no camera move, no alert ping.
const Intel = preload("res://scripts/world/kestrel_intel.gd")
const MainScene = preload("res://main.tscn")
const RUNTIME := "user://kestrel_intel_runtime"


class Recorder extends RefCounted:
	var calls: Array = []

	func request(id: String, at: Vector3, now: float) -> Dictionary:
		calls.append({"id": id, "at": at, "now": now})
		return {"play": false, "id": id, "reason": "recorded"}

	func set_view(_rect: Rect2) -> void:
		pass

	func set_paused(_on: bool) -> void:
		pass

	func loops(_moving: Dictionary) -> Dictionary:
		return {}

	func duck_db(_now: float) -> float:
		return 0.0

	func ids() -> Array:
		return calls.map(func(c): return c["id"])


const UI_STUB := """extends Node
var session_log := Log.new()
var hud := Control.new()
var notes: Array = []
var alerts := 0
func set_tab(_tab: String) -> void:
	pass
func notify(title: String, body: String, _color: Color) -> void:
	notes.append([title, body])
func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
	alerts += 1
	return true
class Log:
	func unit_added(_kind: String, _team: int, _category: String) -> void:
		pass
	func unit_removed(_kind: String, _team: int, _category: String) -> void:
		pass
"""


# ------------------------------------------------------------------ the constants mirror scenario.rs

func _rust_const(name: String) -> int:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/scenario.rs"), FileAccess.READ)
	if f == null:
		return -1
	var re := RegEx.new()
	re.compile("pub const %s: u64 = ([0-9_]+);" % name)
	var m := re.search(f.get_as_text())
	return int(m.get_string(1).replace("_", "")) if m != null else -1


func test_the_probe_ticks_match_the_scenario(t) -> void:
	t.eq(Intel.PROBE_STAGE_TICK, _rust_const("KESTREL_PROBE_STAGE_TICK"), "the client's stage tick is scenario.rs KESTREL_PROBE_STAGE_TICK")
	t.eq(Intel.PROBE_STRIKE_TICK, _rust_const("KESTREL_PROBE_STRIKE_TICK"), "the client's strike tick is scenario.rs KESTREL_PROBE_STRIKE_TICK")
	t.eq(Intel.PROBE_STAGE_TICK, 1650, "and it is the 55 s mark (fails if scenario.rs cannot be read: -1)")


# ------------------------------------------------------------------ the pure latch

func test_the_warning_fires_once_in_its_window_and_rearms_on_a_restart(t) -> void:
	t.eq(Intel.probe_warning(0, false), {"given": false, "fire": false}, "before the stage tick: armed, quiet")
	t.eq(Intel.probe_warning(1649, false), {"given": false, "fire": false}, "one tick before: quiet")
	t.eq(Intel.probe_warning(1650, false), {"given": true, "fire": true}, "at the stage tick: fire")
	t.eq(Intel.probe_warning(1650, true), {"given": true, "fire": false}, "the same snapshot re-delivered: nothing")
	t.eq(Intel.probe_warning(2000, true), {"given": true, "fire": false}, "later: nothing")
	t.eq(Intel.probe_warning(1700, false), {"given": true, "fire": true}, "a first poll past the stage tick still warns")
	t.eq(Intel.probe_warning(3300, false), {"given": true, "fire": false}, "too late (the probe is striking): stays quiet")
	t.eq(Intel.probe_warning(0, true), {"given": false, "fire": false}, "a restarted sim (tick back before the stage) re-arms")


func test_the_copy_names_no_place_beyond_the_briefing(t) -> void:
	t.eq(Intel.PROBE_TITLE, "SCOUTS REPORT MOVEMENT NEAR THE FORD", "the toast title")
	t.ok(Intel.PROBE_BODY != "", "and a body")
	for s in [Intel.PROBE_TITLE, Intel.PROBE_BODY]:
		t.ok(not s.contains("\u2013") and not s.contains("\u2014"), "no en or em dash: %s" % s)
		t.ok(not s.contains("(") and not s.to_lower().contains("picket"), "no cell or position: %s" % s)


# ------------------------------------------------------------------ the game

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
	if kestrel:
		scene.world_fx.set_view(scene._hex_world(12, 12), Vector2(12, 10))
	scene.ui = _ui_stub()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
	scene.runtime_directory = RUNTIME
	return scene


func _done(scene: Node3D) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME.path_join("snapshot.json")))
	scene.ui.hud.free()
	scene.ui.free()
	scene.free()


func _poll(scene: Node3D, snap: Dictionary, tick: int) -> void:
	snap["tick"] = tick
	snap["next_wave_ticks"] = maxi(4500 - tick, 2000)  # far from the wave's own 45 s and 10 s notices
	snap["shots"] = []
	var f := FileAccess.open(RUNTIME.path_join("snapshot.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	scene.bridge_poll_elapsed = 0.0
	scene._poll_bridge(1.0)


func _probe_notes(scene: Node3D) -> int:
	return scene.ui.notes.filter(func(n): return n[0] == Intel.PROBE_TITLE).size()


func test_kestrel_warns_once_with_the_alert_sound_and_no_position(t) -> void:
	var scene := _scene(true)
	var rec := Recorder.new()
	scene.audio = rec
	var snap := _snap()
	_poll(scene, snap, 0)
	_poll(scene, snap, 1600)
	t.eq(_probe_notes(scene), 0, "nothing before the probe moves")
	var camera_before: Vector3 = scene.camera_target
	var focus_before: Vector3 = scene.camera_focus_target
	_poll(scene, snap, 1650)
	t.eq(_probe_notes(scene), 1, "one toast at the stage tick")
	t.eq(rec.ids(), ["alert"], "with the existing alert sound")
	t.ok(not (rec.calls[0]["at"] as Vector3).is_finite(), "a sound with no place (never fog-gated, never panned to the probe)")
	t.eq(scene.alert_pings.pings.size(), 0, "no minimap ring")
	t.eq(scene.alert_pings.history.size(), 0, "nothing for Space to jump to")
	t.eq(scene.ui.alerts, 0, "not a structure alert")
	t.eq(scene.camera_target, camera_before, "the camera does not move")
	t.eq(scene.camera_focus_target, focus_before, "nor its focus")
	_poll(scene, snap, 1650)
	_poll(scene, snap, 1700)
	_poll(scene, snap, 2400)
	t.eq(_probe_notes(scene), 1, "re-delivered and later snapshots: no repeat")
	t.eq(rec.ids(), ["alert"], "and no second sound")
	_poll(scene, snap, 0)  # restart: the bridge starts a fresh sim
	_poll(scene, snap, 1660)
	t.eq(_probe_notes(scene), 2, "re-armed by the restart: the new run warns again")
	_done(scene)


func test_survival_never_warns(t) -> void:
	var scene := _scene(false)
	var snap := _snap()
	snap["ground"] = "g".repeat(44 * 26)
	_poll(scene, snap, 0)
	_poll(scene, snap, 1650)
	t.eq(_probe_notes(scene), 0, "no world art: no Kestrel intel")
	_done(scene)
