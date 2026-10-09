extends RefCounted
## Task 26: replays in the client. While the snapshot carries the bridge's `replay` block the client sends no order at all
## (a right click, a key, or any packet writer drops it) and only the camera and the speed bar take input; the speed bar
## writes replay_speed.txt (0.5, 1, 2, 4, 8, 0 for pause) and shows tick / END and the speed; the Replays list reads only
## user://replays (a test overrides the directory with another user:// one) and parses each file's header and its last END
## line, skipping a corrupt file; choosing a row asks the bridge for the playback, deploys (start.flag) once the playback
## snapshot is there, and says so when the bridge played a live match instead. Every file lives under
## user://test_replay_viewer and is removed again.
const MainScene = preload("res://main.tscn")
const Keybinds := preload("res://scripts/ui/keybinds.gd")
const MatchConfig := preload("res://scripts/match_config.gd")
const ReplayList := preload("res://scripts/ui/sections/replay_list.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
const LiveScreens := preload("res://scripts/ui/live_screens.gd")
const Stub := preload("res://tests/stub_game.gd")
const U := preload("res://tests/section_util.gd")
const DIR := "user://test_replay_viewer"
const RUNTIME := DIR + "/runtime"
const REPLAYS := DIR + "/replays"

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


func _rm_tree(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	for d in DirAccess.get_directories_at(abs):
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(abs)


func _clean() -> void:
	_rm_tree(DIR)
	MatchConfig.reset()


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


func _ui_stub() -> Node:
	var s := GDScript.new()
	s.source_code = UI_STUB
	s.reload()
	var n := Node.new()
	n.set_script(s)
	return n


func _unit(scene, id: int, kind: String, owner: int, tile: Vector2i) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100, "stance": "aggressive"}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _header(seed: int, difficulty := "normal", run := false) -> String:
	return "RPL1\nversion=0.1.0\nscenario=kestrel\nseed=%d\ndifficulty=%s\nrun=%s\nperk_pool=255\nfog=true\nbalance=123\n\n" % [seed, difficulty, "true" if run else "false"]


func _end(tick: int, hash: int, score: int) -> String:
	return "END %020d %020d %020d\n" % [tick, hash, score]


func test_replay_mode_drops_every_order(t) -> void:
	_clean()
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))
	scene._sync_ground(snap)
	scene.ui = _ui_stub()
	scene.mission_deployed = true
	scene.bridge_active = true
	scene.runtime_directory = RUNTIME
	scene.objective_label = Label.new()  # the ticker the order writers update (built in _ready, which never runs here)
	scene.bridge_initialized = false
	scene._sync_bridge_entities([_unit(scene, 750, "Infantry", 0, Vector2i(10, 12)), _unit(scene, 751, "Tank", 0, Vector2i(11, 12))])
	scene.bridge_initialized = true
	scene._set_selection([scene.bridge_nodes[750], scene.bridge_nodes[751]])
	var ground: Vector3 = scene._hex_world(14, 12)
	scene._write_bridge_move(scene.bridge_nodes[750], ground)
	t.eq(_lines().size(), 1, "control: a live match sends the move")
	scene.bridge_snapshot = {"replay": {"speed": 1.0, "tick": 120.0, "end": 5400.0}}
	t.ok(scene.replay_mode(), "the replay block means playback")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(900, 500)
	scene._unhandled_input(click)
	t.eq(_lines(), [], "a right click sends no order in playback")
	scene._write_bridge_move(scene.bridge_nodes[750], ground)
	t.eq(_lines(), [], "no packet writer reaches the bridge")
	for code in [Keybinds.STOP, Keybinds.HOLD, Keybinds.STANCE]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = true
		scene._unhandled_input(ev)
	t.eq(_lines(), [], "nor an order key")
	var zoom: float = scene.camera_focus_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	scene._unhandled_input(wheel)
	t.ok(scene.camera_focus_zoom > zoom, "the camera still zooms")
	t.eq(scene.coach_card(), {}, "no coach card asks a viewer to act in playback")
	scene.objective_label.free()
	scene.ui.hud.free()
	scene.ui.free()
	scene.free()
	_clean()


## [stub, ui, real game]: as in test_perk_draft, the stub forwards the speed writes to the real game script.
func _make(t) -> Array:
	_clean()
	DirAccess.make_dir_recursive_absolute(RUNTIME)
	var real = (load("res://scripts/earthfront_3d.gd") as GDScript).new()
	real.runtime_directory = RUNTIME
	var g := Stub.new()
	g.viewport = t.root
	g.runtime_directory = RUNTIME
	g.settings_path = DIR + "/settings.cfg"
	g.forward = real
	g.use_kestrel()
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.replays_dir = REPLAYS
	return [g, ui, real]


func _drop(p: Array) -> void:
	p[1].free()
	p[2].free()
	_clean()


func _speed() -> String:
	return FileAccess.get_file_as_string(RUNTIME.path_join("replay_speed.txt")).strip_edges()


## The HUD surfaces the speed bar must not cover at 1920x1080 (hud.gd): the top bar, the objectives card, the wave card,
## the idle-crew and next-alert chips with the coach card under them, and the bottom HUD.
const HUD_RECTS := {
	"top bar": Rect2(12, 10, 1896, 56),
	"objectives card": Rect2(12, 76, 420, 42 + 25 * 6),
	"wave card": Rect2(962, 76, 440, 150),
	"chips and coach card": Rect2(1540, 240, 370, 210),
	"bottom HUD": Rect2(0, 770, 1920, 310),
}


func test_the_speed_bar_writes_replay_speed(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 120.0, "end": 5400.0}
	g.bridge_snapshot["depth"]["run"] = {"wave": 2, "draft": [1.0, 2.0, 3.0], "pool": 255, "held": 0}
	ui.begin_operation()
	ui.process(0.2)
	t.ok(ui.replay_layer.get_child_count() > 0, "playback shows the speed bar")
	t.ok(U.has_text(ui.replay_layer, "120 / 5400"), "with tick / END")
	t.ok(U.has_text(ui.replay_layer, "1x"), "and the speed")
	t.ok(not ui.draft_open(), "a recorded draft never opens the modal (the replay plays its own pick)")
	t.ok(not FileAccess.file_exists(RUNTIME.path_join("pause.flag")), "and never pauses the bridge")
	for pair in [["4x", "4"], ["0.5x", "0.5"], ["8x", "8"], ["Pause", "0"], ["2x", "2"], ["1x", "1"]]:
		var b: Button = null
		for c in U.buttons(ui.replay_layer):
			if (c as Button).text == pair[0]:
				b = c
		t.ok(b != null, "a %s button" % pair[0])
		if b != null:
			b.pressed.emit()
			t.eq(_speed(), pair[1], "%s writes %s" % [pair[0], pair[1]])
	var bar := ui.replay_layer.find_child("ReplayBar", true, false) as Control
	var rect := Rect2(bar.position, bar.size)
	for name in HUD_RECTS:  # the wave card shows for the last 90 s before each wave, in playback too
		t.ok(not rect.intersects(HUD_RECTS[name]), "the bar %s clears the %s" % [rect, name])
	g.bridge_snapshot.erase("replay")
	ui.process(0.2)
	t.eq(ui.replay_layer.get_child_count(), 0, "a live match has no speed bar")
	_drop(p)


## Task 27: the bridge's replay block says whether the file came from another sim build (`stale`) and, at END, whether
## the playback reproduced the recorded end (`check`). The viewer shows it in one small line over the speed bar.
func test_the_viewer_says_whether_the_replay_holds(t) -> void:
	t.eq(ReplayList.replay_notice({"speed": 1.0, "tick": 5.0, "end": 9.0}), {}, "an older bridge's block: no notice")
	t.eq(ReplayList.replay_notice({"stale": false, "check": "pending"}), {}, "a current file still playing: no notice")
	t.eq(str(ReplayList.replay_notice({"stale": true, "check": "pending"}).get("text")), "Replay is from another build", "stale")
	t.eq(str(ReplayList.replay_notice({"stale": false, "check": "match"}).get("text")), "Replay verified", "match")
	t.eq(str(ReplayList.replay_notice({"stale": false, "check": "mismatch"}).get("text")), "Replay does not match its recorded end", "mismatch")
	t.eq(str(ReplayList.replay_notice({"stale": true, "check": "mismatch"}).get("text")), "Replay is from another build. Replay does not match its recorded end", "both")
	t.eq(str(ReplayList.replay_notice({"stale": false, "check": "match"}).get("tone")), "good", "verified reads good")
	t.eq(str(ReplayList.replay_notice({"stale": true, "check": "match"}).get("tone")), "warn", "another build warns")
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.begin_operation()
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 120.0, "end": 5400.0, "stale": true, "check": "pending"}
	ui.process(0.2)
	t.ok(U.has_text(ui.replay_layer, "Replay is from another build"), "the viewer shows a stale file")
	var bar := ui.replay_layer.find_child("ReplayBar", true, false) as Control
	var note := ui.replay_layer.find_child("ReplayNotice", true, false) as Control
	t.ok(note != null, "in its own small line")
	if note != null and bar != null:
		var rect := Rect2(note.position, note.size)
		t.ok(not rect.intersects(Rect2(bar.position, bar.size)), "over the bar, not on it")
		for name in HUD_RECTS:
			t.ok(not rect.intersects(HUD_RECTS[name]), "the notice %s clears the %s" % [rect, name])
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 5400.0, "end": 5400.0, "stale": false, "check": "match"}
	ui.process(0.2)
	t.ok(U.has_text(ui.replay_layer, "Replay verified"), "a reproduced end is verified")
	t.ok(not U.has_text(ui.replay_layer, "another build"), "and the stale line is gone")
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 5400.0, "end": 5400.0, "stale": false, "check": "mismatch"}
	ui.process(0.2)
	t.ok(U.has_text(ui.replay_layer, "Replay does not match its recorded end"), "a different end says so")
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 200.0, "end": 5400.0, "stale": false, "check": "pending"}
	ui.process(0.2)
	t.ok(ui.replay_layer.find_child("ReplayNotice", true, false) == null, "nothing while a current file plays")
	_drop(p)


func test_leave_returns_to_a_live_title(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	var cfg := MatchConfig.current
	cfg["replay"] = "/abs/x.rpl"
	MatchConfig.current = cfg
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 10.0, "end": 50.0}
	ui.begin_operation()
	ui.process(0.2)
	U.button_with(ui.replay_layer, "Leave").pressed.emit()
	t.ok(not MatchConfig.current.has("replay"), "the next match is live")
	var json = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME.path_join("match.json")))
	t.ok(json is Dictionary and not json.has("replay"), "and match.json says so")
	t.ok(["restart"] in g.calls, "back to the title")
	t.ok(not FileAccess.file_exists(RUNTIME.path_join("replay_speed.txt")), "the speed file is cleared")
	_drop(p)


func test_the_replay_list_reads_only_user_replays(t) -> void:
	_clean()
	t.eq(ReplayList.DIR, "user://replays", "the list's own directory")
	_write(REPLAYS.path_join("1791415800_kestrel_20261007.rpl"), _header(20261007, "normal", true) + "T 12 perk,4\n" + _end(900, 77, 1500) + _end(5400, 99, 4321))
	_write(REPLAYS.path_join("1791400000_kestrel_5.rpl"), _header(5, "hard") + _end(3000, 1, -40))
	_write(REPLAYS.path_join("1791300000_kestrel_6.rpl"), "garbage\n")
	var junk := FileAccess.open(REPLAYS.path_join("1791300000_kestrel_6.rpl"), FileAccess.READ_WRITE)
	junk.seek_end()
	junk.store_buffer(PackedByteArray([0, 1, 255, 254]))
	junk.close()
	_write(REPLAYS.path_join("1791200000_kestrel_7.rpl"), _header(7) + "END 12 34\n")
	_write(REPLAYS.path_join("notes.txt"), _header(8) + _end(1, 1, 1))
	var scan := ReplayList.scan(REPLAYS)
	t.eq(scan.rows.size(), 2, "two readable replays")
	t.eq(scan.skipped, 2, "two corrupt files skipped without an error")
	var first: Dictionary = scan.rows[0]
	t.eq(first.seed, 20261007, "newest first, its seed")
	t.eq(first.difficulty, "normal", "difficulty")
	t.eq(first.run, true, "a run")
	t.eq(first.ticks, 5400, "the LAST END line's tick")
	t.eq(first.score, 4321, "and its score")
	t.eq(first.scenario, "kestrel", "the scenario")
	t.ok(str(first.path).is_absolute_path() and str(first.path).ends_with("1791415800_kestrel_20261007.rpl"), "an absolute path for the bridge")
	t.eq(scan.rows[1].score, -40, "a negative score reads")
	for bad in ["res://tests", "/tmp", "user://../x", "user://replays/../..", ""]:
		var refused := ReplayList.scan(bad)
		t.ok(refused.rows.is_empty() and str(refused.error) != "", "refused: " + bad)
	var vm := LiveScreens.replays_vm(scan)
	t.ok(str(vm.rows[0].label).contains("20261007") and str(vm.rows[0].label).contains("Run"), "the row label: " + str(vm.rows[0].label))
	t.ok(str(vm.note).contains("2 unreadable"), "the note counts the skipped files")
	_clean()


func test_choosing_a_replay_plays_it_or_says_why_not(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	_write(REPLAYS.path_join("1791415800_kestrel_20261007.rpl"), _header(20261007) + _end(5400, 99, 4321))
	t.ok(LiveScreens.title_vm(true, 12, true, "kestrel").menu.any(func(m): return str(m.get("action", "")) == "replays"), "the title has a Replays entry")
	ui.open_replays()
	t.ok(ui.replays_open, "the list opens")
	t.ok(U.has_text(ui.replays_layer, "20261007"), "with the replay")
	U.button_with(ui.replays_layer, "Watch").pressed.emit()
	var json = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME.path_join("match.json")))
	t.ok(json is Dictionary and str(json.get("replay", "")).ends_with("1791415800_kestrel_20261007.rpl"), "match.json names the replay")
	t.ok(FileAccess.file_exists(RUNTIME.path_join("restart.flag")), "and the bridge rebuilds")
	t.ok(not ui.replays_open, "the list closes while it loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME.path_join("restart.flag")))  # the bridge took it
	for i in 60:
		ui.process(0.1)
	t.ok(not (["deploy"] in g.calls), "a live snapshot (the replay was rejected) never deploys")
	t.ok(ui.replays_open, "the list is back")
	t.ok(U.has_text(ui.replays_layer, "could not be played"), "with the reason")
	t.ok(not MatchConfig.current.has("replay"), "and the config is live again")
	U.button_with(ui.replays_layer, "Watch").pressed.emit()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME.path_join("restart.flag")))
	g.bridge_snapshot["replay"] = {"speed": 1.0, "tick": 0.0, "end": 5400.0}
	for i in 5:
		ui.process(0.1)
	t.ok(["deploy"] in g.calls, "the playback snapshot deploys (start.flag starts the playback)")
	t.eq(FileAccess.get_file_as_string(RUNTIME.path_join("replay_speed.txt")).strip_edges(), "1", "at 1x")
	_drop(p)
