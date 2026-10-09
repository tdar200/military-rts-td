extends RefCounted
## Task 27: the client starts and supervises its own bridge. The launcher names the bridge binary per OS next to the
## executable, keeps the runtime directory under user:// (this game's user://runtime/<pid>), leaves dev and QA alone when
## they pass --runtime-dir=, cleans stale exchange files before a spawn, starts the stub bridge (tests/fixtures/
## stub_bridge.sh: a tick-0 snapshot, then a bounded sleep), sees it alive, stops it, notices once a second when it
## died, offers a Restart that respawns it, and says "Simulation core missing" when there is no binary. Every file lives
## under user://test_bridge_launcher and is removed again; every stub this file starts is stopped by its pid.
const BridgeLauncher := preload("res://scripts/bridge_launcher.gd")
const U := preload("res://tests/section_util.gd")
const DIR := "user://test_bridge_launcher"
const STUB := "res://tests/fixtures/stub_bridge.sh"


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _rm_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Waits (at most `ms`) for the stub's tick-0 snapshot in `runtime`; returns it parsed, or {}.
func _await_snapshot(runtime: String, ms := 5000) -> Dictionary:
	var waited := 0
	while waited < ms:
		var path := runtime.path_join("snapshot.json")
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and parsed.get("stub", false):
				return parsed
		OS.delay_msec(20)
		waited += 20
	return {}


## Ends the child the way a crash would (a signal from outside, not Godot's kill, which also reaps it): only the pid the
## launcher started.
func _crash(pid: int) -> void:
	if pid > 0:
		OS.execute("kill", ["-KILL", str(pid)])


func test_the_bridge_binary_sits_next_to_the_executable(t) -> void:
	t.eq(BridgeLauncher.binary_path("Linux", "/opt/ascension"), "/opt/ascension/godot-bridge", "Linux")
	t.eq(BridgeLauncher.binary_path("Windows", "C:/Games/Ascension"), "C:/Games/Ascension/godot-bridge.exe", "Windows")
	t.eq(BridgeLauncher.binary_path("FreeBSD", "/usr/local/games"), "/usr/local/games/godot-bridge", "any other OS")
	t.ok(BridgeLauncher.refusal("res://godot-bridge") != "", "a res:// bridge is never started (it is packed inside an export)")
	t.ok(BridgeLauncher.refusal("user://godot-bridge") != "", "nor a user:// one")
	t.ok(BridgeLauncher.refusal("godot-bridge") != "", "nor a relative path")
	t.ok(BridgeLauncher.refusal(_abs(STUB)) == "", "a file on disk is")


func test_dev_and_qa_keep_their_external_bridge(t) -> void:
	t.ok(not BridgeLauncher.should_spawn(PackedStringArray(["--runtime-dir=/q/run"])), "--runtime-dir= means an external bridge")
	t.ok(not BridgeLauncher.should_spawn(PackedStringArray(["--qa-dir=/q", "--runtime-dir=/q", "--qa-xvfb"])), "anywhere among the arguments")
	t.ok(BridgeLauncher.should_spawn(PackedStringArray()), "no arguments: the game spawns its own")
	t.ok(BridgeLauncher.should_spawn(PackedStringArray(["--qa-dir=/q"])), "other arguments too")
	t.eq(BridgeLauncher.resolve_runtime(PackedStringArray(["--runtime-dir=/q/run"])), "/q/run", "the external directory, as given")
	t.eq(BridgeLauncher.resolve_runtime(PackedStringArray()), BridgeLauncher.runtime_dir(), "else this game's own")


func test_the_runtime_dir_is_under_user_never_res(t) -> void:
	var own := BridgeLauncher.runtime_dir()
	var user := _abs("user://")
	t.ok(own.is_absolute_path(), "a filesystem path the bridge can take: %s" % own)
	t.ok(own.begins_with(_abs("user://runtime")), "under user://runtime")
	t.ok(own.begins_with(user) and not own.begins_with(_abs("res://")), "under user://, never res://")
	t.eq(own.get_file(), str(OS.get_process_id()), "one directory per game process: two games never share one")
	t.ok(BridgeLauncher.runtime_dir(41) != BridgeLauncher.runtime_dir(42), "another pid, another directory")
	var src: String = (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.ok(not src.contains("\"res://runtime\""), "the game no longer defaults to res://runtime")
	t.ok(src.contains("BridgeLauncher.resolve_runtime("), "the game resolves its directory through the launcher")


func test_a_missing_binary_says_so_and_never_hangs(t) -> void:
	var l = BridgeLauncher.new()
	var runtime := _abs(DIR).path_join("missing")
	t.eq(l.start(_abs(DIR).path_join("no-such-bridge"), runtime), -1, "nothing to start")
	t.eq(l.state, "missing", "the missing state")
	t.ok(not l.alive(), "and no child")
	var notice: Control = l.notice()
	t.ok(notice != null and U.has_text(notice, "Simulation core missing"), "the notice says the core is missing")
	t.ok(notice != null and U.has_text(notice, "no-such-bridge"), "and names the path it looked for")
	t.ok(notice != null and U.button_with(notice, "Try again") != null and U.button_with(notice, "Quit") != null, "with Try again and Quit")
	t.eq(l.start("res://godot-bridge", runtime), -1, "a res:// binary is refused")
	t.eq(l.state, "missing", "as missing")
	l.free()
	_rm_tree(_abs(DIR))


func test_the_launcher_starts_and_stops_the_stub(t) -> void:
	_rm_tree(_abs(DIR))
	var runtime := _abs(DIR).path_join("runtime").path_join("777")
	# A previous session's leftovers: every one is gone before the bridge starts.
	_write(runtime.path_join("snapshot.json"), "{\"schema\":5,\"tick\":4321}")
	for f in ["match.json", "start.flag", "restart.flag", "pause.flag", "replay_speed.txt", "commands.txt"]:
		_write(runtime.path_join(f), "stale")
	_write(runtime.path_join("commands/00000000000000000001.cmd"), "move,1,0,0")
	_write(runtime.path_join("commands/00000000000000000002.next"), "stop,1")
	# The player's things beside it are never touched.
	_write(_abs(DIR).path_join("replays/1_kestrel_1.rpl"), "RPL1\n")
	_write(_abs(DIR).path_join("settings.cfg"), "[audio]\n")
	var l = BridgeLauncher.new()
	var pid: int = l.start(_abs(STUB), runtime)
	t.ok(pid > 0, "the stub started (pid %d)" % pid)
	t.eq(l.state, "running", "running")
	t.ok(l.alive(), "alive")
	t.ok(l.notice() == null, "no notice while it runs")
	var snap := _await_snapshot(runtime)
	t.eq(int(snap.get("tick", -1)), 0, "the stub's tick-0 snapshot reached the runtime directory")
	for f in ["match.json", "start.flag", "restart.flag", "pause.flag", "replay_speed.txt", "commands.txt"]:
		t.ok(not FileAccess.file_exists(runtime.path_join(f)), "the stale %s was cleaned before the spawn" % f)
	t.eq(Array(DirAccess.get_files_at(runtime.path_join("commands"))), [], "and the stale command packets")
	t.ok(FileAccess.file_exists(_abs(DIR).path_join("replays/1_kestrel_1.rpl")), "replays stay")
	t.ok(FileAccess.file_exists(_abs(DIR).path_join("settings.cfg")), "settings stay")
	l.poll(1.0)
	t.eq(l.state, "running", "a live child stays running across a poll")
	l.stop()
	t.ok(not l.alive(), "stop ends it")
	t.eq(l.pid, -1, "and forgets the pid")
	var out := []
	OS.execute("ps", ["-o", "stat=", "-p", str(pid)], out)
	t.eq(str(out[0]).strip_edges() if out.size() > 0 else "", "", "no process (and no zombie) is left behind")
	l.free()
	_rm_tree(_abs(DIR))


func test_a_dead_bridge_raises_the_stopped_notice_and_restart_respawns(t) -> void:
	_rm_tree(_abs(DIR))
	var runtime := _abs(DIR).path_join("runtime").path_join("778")
	var l = BridgeLauncher.new()
	var first: int = l.start(_abs(STUB), runtime)
	t.ok(first > 0 and not _await_snapshot(runtime).is_empty(), "the stub runs")
	_crash(first)
	OS.delay_msec(100)
	l.poll(0.4)
	t.eq(l.state, "running", "the next check waits for its second")
	l.poll(0.7)
	t.eq(l.state, "stopped", "a second later the dead child raises the stopped state")
	t.ok(not l.alive(), "alive() flipped")
	var out := []
	OS.execute("ps", ["-o", "stat=", "-p", str(first)], out)
	t.eq(str(out[0]).strip_edges() if out.size() > 0 else "", "", "the dead child was reaped (no zombie)")
	var notice: Control = l.notice()
	t.ok(notice != null and U.has_text(notice, "Simulation core stopped"), "the notice says the core stopped")
	var restart: Button = U.button_with(notice, "Restart") if notice != null else null
	t.ok(restart != null, "with a Restart button")
	var states: Array = []
	l.state_changed.connect(func(s: String) -> void: states.append(s))
	if restart != null:
		restart.pressed.emit()
	t.eq(l.state, "running", "Restart respawns the bridge")
	t.ok(l.pid > 0 and l.pid != first and l.alive(), "a new child")
	t.eq(states, ["running"], "one state change")
	t.ok(not _await_snapshot(runtime).is_empty(), "which writes its snapshot again")
	t.ok(l.notice() == null, "the notice is gone")
	l.shutdown()
	t.ok(not l.alive(), "shutdown ends it")
	t.ok(not DirAccess.dir_exists_absolute(runtime), "and removes the game's runtime directory")
	l.free()
	_rm_tree(_abs(DIR))


func test_the_launcher_never_asks_about_a_pid_it_does_not_own(t) -> void:
	var l = BridgeLauncher.new()
	for bogus in [0, -1]:
		l.pid = bogus
		t.ok(not l.alive(), "pid %d is never a child" % bogus)
		l.stop()
		t.eq(l.pid, -1, "and stop never signals it")
	l.free()


func test_stale_runtime_dirs_of_dead_games_are_swept(t) -> void:
	_rm_tree(_abs(DIR))
	var root := _abs(DIR).path_join("runtime")
	_write(root.path_join("101/snapshot.json"), "{}")
	_write(root.path_join("101/commands/0001.cmd"), "stop,1")
	_write(root.path_join("102/snapshot.json"), "{}")
	_write(root.path_join("notes/readme.txt"), "not a runtime dir")
	var now := int(Time.get_unix_time_from_system())
	t.eq(BridgeLauncher.sweep_stale(root, "102", now), [], "a fresh snapshot means a running game: kept")
	var later := now + BridgeLauncher.STALE_SECS + 5
	t.eq(BridgeLauncher.sweep_stale(root, "102", later), ["101"], "an old one is swept, the own one kept")
	t.ok(not DirAccess.dir_exists_absolute(root.path_join("101")), "101 is gone")
	t.ok(DirAccess.dir_exists_absolute(root.path_join("102")), "102 stays")
	t.ok(FileAccess.file_exists(root.path_join("notes/readme.txt")), "a directory that is not a pid is never touched")
	_rm_tree(_abs(DIR))
