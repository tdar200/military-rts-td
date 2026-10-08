extends RefCounted
## Replays (kestrel-depth Task 26). `scan` lists the recordings the bridge wrote to user://replays (Task 24's RPL1 files:
## the `key=value` header up to its blank line, `T <tick> <line>` per command, and the rolling
## `END <tick20> <hash20> <score20>` line, always last). It reads the header from the head of each file and the last END
## line from its tail, so a long match is never read whole; a file that is not a whole replay is skipped and counted, never
## an error. It reads only a user:// directory (user://replays; a test passes another user:// one): any other path, or one
## that climbs out with "..", is refused. Verifying a replay is the bridge's and verify-run's job, not the client's.
##
## `build` draws the list over the title (a row per replay with its Watch button; `emit` receives watch with the absolute
## path, and back). `build_bar` draws the playback speed bar at the foot of the play area (`emit` receives speed with the
## replay_speed.txt text, and leave).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const DIR := "user://replays"
const MAGIC := "RPL1"
## Header lines read at most before the blank line (the bridge writes eight).
const HEADER_LINES := 16
## Bytes read from the end of a file for its last END line (one is 66 bytes plus its newline).
const TAIL_BYTES := 200
## Rows the list shows (newest first); older ones are counted in the note.
const MAX_ROWS := 8
## The bar's speeds as replay_speed.txt spells them, with their labels ("0" is pause).
const SPEEDS := [["0.5", "0.5x"], ["1", "1x"], ["2", "2x"], ["4", "4x"], ["8", "8x"], ["0", "Pause"]]

const SCRIM := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.78)
const PANEL_X := 440.0
const PANEL_Y := 150.0
const PANEL_W := 1040.0
const PAD := 26.0
const ROW_H := 62.0
const BTN_H := 56.0
## The bar sits at the foot of the play area, above the bottom HUD (770): the top centre is the wave card's for the last
## 90 s before each wave (test_replay_viewer checks it against hud.gd's surfaces).
const BAR_X := 520.0
const BAR_Y := 694.0
const BAR_W := 880.0


## {rows: [{path, name, unix, scenario, seed, difficulty, run, perk_pool, fog, ticks, score}] newest first,
##  skipped: files that are not whole replays, older: rows past MAX_ROWS, error: "" or why the directory was refused}.
static func scan(dir: String) -> Dictionary:
	var out := {"rows": [], "skipped": 0, "older": 0, "error": ""}
	if not allowed(dir):
		out.error = "Replays are read only from user://replays"
		return out
	var abs := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return out  # nothing recorded yet
	var rows: Array = []
	for name in DirAccess.get_files_at(abs):
		if not str(name).ends_with(".rpl") or str(name).contains(".."):
			continue
		var row := read_file(abs.path_join(name))
		if row.is_empty():
			out.skipped += 1
			continue
		row["name"] = str(name)
		var stamp := str(name).get_slice("_", 0)
		row["unix"] = int(stamp) if stamp.is_valid_int() else 0
		rows.append(row)
	rows.sort_custom(func(a, b): return a.unix > b.unix if a.unix != b.unix else str(a.name) > str(b.name))
	out.older = maxi(0, rows.size() - MAX_ROWS)
	out.rows = rows.slice(0, MAX_ROWS)
	return out


## A user:// directory with no ".." segment.
static func allowed(dir: String) -> bool:
	if not dir.begins_with("user://"):
		return false
	for part in dir.trim_prefix("user://").split("/"):
		if part == "..":
			return false
	return true


## One replay's header and last END line, or {} when the file is not a whole replay.
static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var length := f.get_length()
	if length < MAGIC.length() + 2:
		return {}
	if f.get_line() != MAGIC:
		return {}
	var header := {}
	var closed := false
	for i in HEADER_LINES:
		if f.eof_reached():
			break
		var line := f.get_line()
		if line == "":
			closed = true
			break
		var eq := line.find("=")
		if eq <= 0:
			return {}
		header[line.substr(0, eq)] = line.substr(eq + 1)
	if not closed:
		return {}
	for key in ["scenario", "seed", "difficulty", "run", "perk_pool", "fog"]:
		if not header.has(key):
			return {}
	if not str(header.seed).is_valid_int() or not (str(header.run) in ["true", "false"]):
		return {}
	f.seek(maxi(0, length - TAIL_BYTES))
	var tail := f.get_buffer(mini(TAIL_BYTES, length)).get_string_from_utf8()
	var lines := tail.strip_edges(false, true).split("\n")
	var last := lines[lines.size() - 1] if lines.size() > 0 else ""
	var end := last.split(" ")
	if end.size() != 4 or end[0] != "END":
		return {}
	for i in [1, 2, 3]:
		if end[i].length() != 20 or not end[i].is_valid_int():
			return {}
	return {
		"path": path,
		"scenario": str(header.scenario),
		"seed": int(header.seed),
		"difficulty": str(header.difficulty),
		"run": str(header.run) == "true",
		"perk_pool": int(header.perk_pool) if str(header.perk_pool).is_valid_int() else 0,
		"fog": str(header.fog) == "true",
		"ticks": int(end[1]),
		"score": int(end[3]),
	}


## The list over the title; returns the first Watch button (null when there is none).
static func build(parent: Control, vm: Dictionary, emit := Callable()) -> Control:
	if vm.is_empty():
		return null
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(scrim)
	var panel := K.panel(parent, PANEL_X, PANEL_Y, PANEL_W, 10.0)
	var cx := PANEL_X + 1.0 + PAD
	var cw := PANEL_W - 2.0 - 2.0 * PAD
	var y := PANEL_Y + 1.0 + PAD
	var cap := K.text(parent, str(vm.get("cap", "")), {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN_HI, "up": true})
	y += cap.size.y + 4.0
	var title := K.text(parent, str(vm.get("title", "")), {"x": cx, "y": y, "f": "disp", "wt": 600, "px": 44, "sp": 0.04, "lh": 46, "col": T.TEXT_HI, "up": true})
	y += title.size.y + 14.0
	var error := str(vm.get("error", ""))
	if error != "":
		var e := K.text(parent, error, {"x": cx, "y": y, "w": cw, "px": 16, "col": T.WARN, "wrap": true})
		y += e.size.y + 12.0
	var first: Control = null
	var rows: Array = vm.get("rows", [])
	if rows.is_empty():
		var none := K.text(parent, str(vm.get("empty", "")), {"x": cx, "y": y, "w": cw, "px": 16, "col": T.DIM, "wrap": true})
		y += none.size.y + 12.0
	for row in rows:
		K.rule(parent, cx, y, cw, 1, T.LINE_DIM)
		var watch := K.button(parent, "Watch", 0, 0, {"px": 16, "pad": 18.0, "min_h": 44.0})
		watch.size.x = maxf(120.0, watch.size.x)
		watch.custom_minimum_size = watch.size
		K.place(watch, cx + cw - watch.size.x, y + (ROW_H - watch.size.y) * 0.5)
		var tw := cw - watch.size.x - 24.0
		K.text(parent, str(row.get("label", "")), {"x": cx, "y": y + 8.0, "w": tw, "px": 18, "col": T.TEXT_HI})
		K.text(parent, str(row.get("detail", "")), {"x": cx, "y": y + 34.0, "w": tw, "f": "mono", "px": 12, "sp": 0.06, "col": T.DIM})
		if emit.is_valid():
			watch.pressed.connect(emit.bind("watch", str(row.get("path", ""))))
		if first == null:
			first = watch
		y += ROW_H
	y += 12.0
	var note := K.text(parent, str(vm.get("note", "")), {"x": cx, "y": y, "w": cw - 200.0, "px": 14, "col": T.DIM, "wrap": true})
	var back := K.button(parent, str(vm.get("back", "Back")), 0, 0, {"px": 20, "sp": 0.1, "pad": 20.0, "spread": true, "min_h": BTN_H, "key": "Esc"})
	back.size.x = maxf(150.0, back.size.x)
	back.custom_minimum_size = back.size
	K.place(back, cx + cw - back.size.x, y)
	note.position.y = roundf(y + (back.size.y - note.size.y) * 0.5)
	if emit.is_valid():
		back.pressed.connect(emit.bind("back", null))
	y += back.size.y
	panel.size.y = roundf(y + PAD + 1.0 - PANEL_Y)
	panel.queue_redraw()
	return first if first != null else back


## The playback bar: the Replay tag, tick / END with the clock, the speed, the six speed buttons (the current one on) and
## Leave. `vm` is {tick, end, speed ("1"), status}.
static func build_bar(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty():
		return
	var panel := K.panel(parent, BAR_X, BAR_Y, BAR_W, 10.0)
	panel.name = "ReplayBar"
	var x := BAR_X + 1.0 + 18.0
	var y := BAR_Y + 1.0 + 12.0
	var tag := K.tag(parent, "Replay", x, y + 8.0, T.VIOLET)
	x += tag.size.x + 14.0
	var tick := int(vm.get("tick", 0))
	var end := int(vm.get("end", 0))
	var where := K.text(parent, "Tick %d / %d" % [tick, end], {"x": x, "y": y, "f": "mono", "px": 14, "col": T.TEXT_HI})
	K.text(parent, "%s / %s  %s" % [_clock(tick), _clock(end), str(vm.get("status", ""))], {"x": x, "y": y + where.size.y + 2.0, "f": "mono", "px": 12, "col": T.DIM})
	x += 230.0
	var speed := str(vm.get("speed", "1"))
	var bh := 0.0
	for pair in SPEEDS:
		var b := K.button(parent, str(pair[1]), x, y, {"variant": "tab", "on": speed == str(pair[0]), "px": 14, "pad": 12.0, "min_h": 40.0})
		b.size.x = maxf(58.0, b.size.x)
		b.custom_minimum_size = b.size
		if emit.is_valid():
			b.pressed.connect(emit.bind("speed", str(pair[0])))
		x += b.size.x + 6.0
		bh = maxf(bh, b.size.y)
	var leave := K.button(parent, "Leave", 0, y, {"px": 14, "pad": 14.0, "min_h": 40.0})
	K.place(leave, BAR_X + BAR_W - 1.0 - 18.0 - leave.size.x, y)
	if emit.is_valid():
		leave.pressed.connect(emit.bind("leave", null))
	panel.size.y = roundf(y + maxf(bh, 40.0) + 12.0 + 1.0 - BAR_Y)
	panel.queue_redraw()


static func _clock(tick: int) -> String:
	var s := tick / 30
	return "%d:%02d" % [s / 60, s % 60]
