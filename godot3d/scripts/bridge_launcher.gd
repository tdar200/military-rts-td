extends Node
## Task 27: the shipped game starts and supervises its own simulation core. The deterministic Rust sim runs in
## `godot-bridge`, a separate process that exchanges files with the client in a runtime directory (snapshot.json,
## match.json, start/restart/pause flags, replay_speed.txt and command packets; godot-bridge.rs RuntimePaths). An
## exported game cannot ship a repo-relative `godot3d/runtime` nor ask the player to start a second program, so:
##
## - resolve_runtime is THE one place the client decides its runtime directory. `--runtime-dir=<dir>` (a user argument
##   after `--`) means a developer or a QA launcher runs the bridge itself (run-3d.sh, tools/qa/launch_ui.py): the
##   client only reads and writes that directory and never spawns anything. Otherwise the directory is
##   user://runtime/<this game's pid>, globalized (never res://, which is read-only inside an export).
## - Single instance: the per-pid subdirectory means two running games never share a directory (each spawns its own
##   bridge into its own subdirectory). A crashed game's subdirectory is swept by the next launch once its snapshot is
##   STALE_SECS old (a live bridge rewrites it 30 times a second, paused or not).
## - start cleans the directory's exchange files (never user://replays or the settings), then spawns the bridge next to
##   the executable (binary_path) with `--runtime-dir <dir> --exit-with-parent`. A missing binary is a clear "Simulation
##   core missing" notice, never a hang.
## - poll checks once a second that the child still runs; a dead bridge raises "Simulation core stopped" with a Restart
##   button that respawns it and reloads the scene to the title.
## - stop kills only the pid this launcher started (never a pattern, never another process), on quit, on the window's
##   close request, on the node's exit and on Godot's crash notification. Best effort: a game killed outright (SIGKILL,
##   power loss) runs none of that; the bridge's --exit-with-parent then ends it within a second on Linux (its parent id
##   changes), and on Windows such an orphan keeps running until the player ends it.
## - No zombie: Godot's OS.kill reaps the child it kills, and is_process_running reaps a child that ended by itself. A
##   pid is never queried again after either (Godot logs an error for a pid it no longer knows).
##
## The game scene adds one launcher under the tree root (outside the scene), so a restart's reload_current_scene keeps
## the bridge running; the scene finds it again by NODE_NAME.
const K = preload("res://scripts/ui/kit.gd")
const T = preload("res://scripts/ui/tokens.gd")
const MatchConfig = preload("res://scripts/match_config.gd")

const NODE_NAME := "BridgeLauncher"
const RUNTIME_ROOT := "user://runtime"
const RUNTIME_ARG := "--runtime-dir="
## Seconds between two liveness checks.
const POLL := 1.0
## A sibling runtime directory whose snapshot is older than this belongs to no running bridge.
const STALE_SECS := 120
## The exchange files of a runtime directory: godot-bridge.rs RuntimePaths and the `.next` files of its write_atomic,
## MatchConfig.write and write_replay_speed. Command packets live in COMMANDS_DIR.
const RUNTIME_FILES := ["snapshot.json", "snapshot.json.next", "match.json", "match.json.next", "commands.txt",
	"start.flag", "restart.flag", "pause.flag", "replay_speed.txt", "replay_speed.txt.next"]
const COMMANDS_DIR := "commands"
## The notice's geometry in the 1920x1080 design space.
const PANEL_W := 720.0
const PANEL_Y := 330.0
const PAD := 32.0

signal state_changed(state: String)

## The bridge's pid while this launcher owns a running child, else -1.
var pid := -1
var binary := ""
var dir := ""
## "idle" (nothing started), "running", "missing" (no bridge binary to start) or "stopped" (the child ended).
var state := "idle"
## Why the last start failed (shown in the notice).
var detail := ""
var _since_poll := 0.0
var _overlay: CanvasLayer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- where things are

## The bridge binary's file name on `os_name` (OS.get_name()).
static func binary_name(os_name: String) -> String:
	return "godot-bridge.exe" if os_name == "Windows" else "godot-bridge"


## The bridge shipped next to the game executable (`exe_dir`, OS.get_executable_path().get_base_dir()).
static func binary_path(os_name: String, exe_dir: String) -> String:
	return exe_dir.path_join(binary_name(os_name))


## This game's own runtime directory: user://runtime/<pid>, globalized (the bridge takes a filesystem path).
static func runtime_dir(process_id := OS.get_process_id()) -> String:
	return ProjectSettings.globalize_path(RUNTIME_ROOT).path_join(str(process_id))


## False when the user arguments name `--runtime-dir=`: dev and QA run their own bridge there.
static func should_spawn(user_args: PackedStringArray) -> bool:
	return external_dir(user_args) == ""


## The `--runtime-dir=` value among the user arguments ("" when there is none).
static func external_dir(user_args: PackedStringArray) -> String:
	var found := ""
	for argument in user_args:
		if argument.begins_with(RUNTIME_ARG):
			found = argument.trim_prefix(RUNTIME_ARG)
	return found


## THE runtime directory: the external bridge's (`--runtime-dir=`) or this game's own (runtime_dir).
static func resolve_runtime(user_args: PackedStringArray) -> String:
	var external := external_dir(user_args)
	return external if external != "" else runtime_dir()


## "" when `path` may be started as the bridge, else why not. A res:// or user:// path is refused: res:// is packed
## inside an export and nothing there can run.
static func refusal(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or not path.is_absolute_path():
		return "the simulation core must be a file on disk, not %s" % path
	if not FileAccess.file_exists(path):
		return "not found: %s" % path
	return ""


# ---------------------------------------------------------------- the runtime directory

## Removes the exchange files a previous bridge or client left in `path` (a snapshot, a match.json, flags, the speed
## file and command packets), and creates the directory. Nothing else in it, and nothing outside it, is touched.
static func clean_runtime(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for f in RUNTIME_FILES:
		if FileAccess.file_exists(path.path_join(f)):
			DirAccess.remove_absolute(path.path_join(f))
	var commands := path.path_join(COMMANDS_DIR)
	if DirAccess.dir_exists_absolute(commands):
		for f in DirAccess.get_files_at(commands):
			if f.ends_with(".cmd") or f.ends_with(".next"):
				DirAccess.remove_absolute(commands.path_join(f))


## Removes `path` (a runtime directory) when only exchange files were in it.
static func remove_runtime(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	clean_runtime(path)
	var commands := path.path_join(COMMANDS_DIR)
	if DirAccess.dir_exists_absolute(commands) and DirAccess.get_files_at(commands).is_empty():
		DirAccess.remove_absolute(commands)
	if DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty():
		DirAccess.remove_absolute(path)


## Sweeps the per-pid runtime directories under `root` that no running bridge writes any more (their snapshot, or the
## directory when it has none, is older than STALE_SECS at `now`), except `keep`. Returns the names removed.
static func sweep_stale(root: String, keep: String, now: int) -> Array:
	var removed: Array = []
	if not DirAccess.dir_exists_absolute(root):
		return removed
	for name in DirAccess.get_directories_at(root):
		if name == keep or not name.is_valid_int():
			continue
		var sub := root.path_join(name)
		var probe := sub.path_join("snapshot.json")
		var touched := FileAccess.get_modified_time(probe if FileAccess.file_exists(probe) else sub)
		if now - int(touched) < STALE_SECS:
			continue
		remove_runtime(sub)
		if not DirAccess.dir_exists_absolute(sub):
			removed.append(name)
	return removed


# ---------------------------------------------------------------- the child process

## Starts the bridge `binary_file` writing into `runtime` (cleaned first): returns its pid, or -1 with the "missing"
## state and its notice when there is nothing to start.
func start(binary_file: String, runtime: String) -> int:
	stop()
	binary = binary_file
	dir = runtime
	var why := refusal(binary)
	if why != "":
		detail = why
		_set_state("missing")
		return -1
	clean_runtime(dir)
	sweep_stale(dir.get_base_dir(), dir.get_file(), int(Time.get_unix_time_from_system()))
	var started := OS.create_process(binary, ["--runtime-dir", dir, "--exit-with-parent"])
	if started <= 0:
		detail = "could not start %s" % binary
		_set_state("missing")
		return -1
	pid = started
	detail = ""
	_set_state("running")
	return pid


## Ends the child this launcher started, if it still runs (Godot's kill reaps it). Never touches any other pid.
func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1


## True while the child this launcher started still runs. A child that ended is reaped here and never asked about again.
func alive() -> bool:
	if pid <= 0:
		return false
	if OS.is_process_running(pid):
		return true
	pid = -1
	return false


## The notice's Restart: a new bridge in the same directory, then a fresh title (the old match died with its bridge;
## MatchConfig forgets it, as a new process would).
func restart() -> int:
	var started := start(binary, dir)
	if started > 0:
		MatchConfig.reset()
		if is_inside_tree() and get_tree().current_scene != null:
			get_tree().reload_current_scene()
	return started


## Once a second (POLL): a running child that ended raises the "stopped" state and its notice.
func poll(delta: float) -> void:
	_since_poll += delta
	if _since_poll < POLL:
		return
	_since_poll = 0.0
	if state == "running" and not alive():
		detail = ""
		_set_state("stopped")


## Kills the child and removes this game's runtime directory (quit, close, crash).
func shutdown() -> void:
	stop()
	if dir != "" and state != "idle":
		remove_runtime(dir)
	if state == "running":
		state = "idle"


func _process(delta: float) -> void:
	poll(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH or what == NOTIFICATION_PREDELETE:
		shutdown()


func _exit_tree() -> void:
	shutdown()


func _set_state(next: String) -> void:
	state = next
	_refresh_notice()
	state_changed.emit(state)


# ---------------------------------------------------------------- the notice

## What the notice shows for `which` ("missing" or "stopped"; {} for any other state). `binary_file` and `why` explain it.
static func notice_vm(which: String, binary_file := "", why := "") -> Dictionary:
	match which:
		"missing":
			return {"title": "Simulation core missing",
				"body": "The game could not start its simulation core (%s). Reinstall the game. Developers: start the bridge yourself and pass --runtime-dir=<dir> after --." % (why if why != "" else binary_file),
				"actions": [["restart", "Try again"], ["quit", "Quit"]]}
		"stopped":
			return {"title": "Simulation core stopped",
				"body": "The simulation process ended, so the match on screen is frozen. Restart starts a new one and returns to the title.",
				"actions": [["restart", "Restart"], ["quit", "Quit"]]}
	return {}


## Builds the notice for `vm` into `parent` (1920x1080 design space): a scrim that takes every click, a panel with the
## title, the body and one button per action; a press calls `emit(action)`.
static func build_notice(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty():
		return
	var scrim := ColorRect.new()
	scrim.name = "CoreScrim"
	scrim.color = T.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	K.place(scrim, 0, 0, 1920, 1080)
	parent.add_child(scrim)
	var x := (1920.0 - PANEL_W) * 0.5
	var panel := K.panel(parent, x, PANEL_Y, PANEL_W, 10.0)
	panel.name = "CoreNotice"
	var y := PANEL_Y + PAD
	var head := K.text(parent, str(vm.get("title", "")), {"x": x + PAD, "y": y, "w": PANEL_W - PAD * 2.0, "px": 30, "col": T.WARN_HI})
	y += head.size.y + 14.0
	var body := K.text(parent, str(vm.get("body", "")), {"x": x + PAD, "y": y, "w": PANEL_W - PAD * 2.0, "px": 16, "col": T.TEXT, "wrap": true})
	y += body.size.y + 24.0
	var right := x + PANEL_W - PAD
	var tallest := 0.0
	var actions: Array = vm.get("actions", [])
	for i in range(actions.size() - 1, -1, -1):
		var pair: Array = actions[i]
		var b := K.button(parent, str(pair[1]), 0, y, {"px": 18, "pad": 20.0, "min_h": 48.0, "primary": i == 0})
		b.size.x = maxf(150.0, b.size.x)
		b.custom_minimum_size = b.size
		K.place(b, right - b.size.x, y)
		right -= b.size.x + 12.0
		tallest = maxf(tallest, b.size.y)
		if emit.is_valid():
			b.pressed.connect(emit.bind(str(pair[0])))
	panel.size.y = roundf(y + tallest + PAD - PANEL_Y)
	panel.queue_redraw()


func _refresh_notice() -> void:
	if _overlay != null:
		remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null
	var vm := notice_vm(state, binary, detail)
	if vm.is_empty():
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	var root := Control.new()
	root.name = "CoreNoticeRoot"
	K.place(root, 0, 0, 1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)
	build_notice(root, vm, Callable(self, "_on_notice"))


## The notice's buttons.
func _on_notice(action: String) -> void:
	match action:
		"restart":
			restart()
		"quit":
			shutdown()
			if is_inside_tree():
				get_tree().quit()


## The notice now on screen (tests read it), or null.
func notice() -> Control:
	return _overlay.get_child(0) as Control if _overlay != null and _overlay.get_child_count() > 0 else null
