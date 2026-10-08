extends RefCounted
## Personal bests (Task 22): Records is the only code that opens user://records.cfg. Every file here lives under
## user://test_records* and is removed again; no test touches user://records.cfg. The debrief's score rows, grade and
## best come from the bridge's depth.score and the Records file, submitted once per decided Kestrel match.
const Records := preload("res://scripts/records.gd")
const LiveScreens := preload("res://scripts/ui/live_screens.gd")
const Debrief := preload("res://scripts/ui/debrief.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
const SessionLog := preload("res://scripts/ui/session_log.gd")
const Stub := preload("res://tests/stub_game.gd")
const TextBox := preload("res://scripts/ui/components/text_box.gd")
const DIR := "user://test_records"
const P := DIR + "/records.cfg"


func _wipe(dir := DIR) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _texts(node: Node, out: Array = []) -> Array:
	if node is TextBox:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


## A Kestrel stub whose snapshot carries `score` in its depth block (the committed fixture, then the given values).
func _kestrel(score: Dictionary, difficulty := "normal", winner := 0) -> Object:
	var g := Stub.new()
	g.use_kestrel()
	g.bridge_snapshot["depth"]["score"] = score
	g.bridge_snapshot["depth"]["difficulty"] = difficulty
	g.bridge_winner = winner
	g.bridge_tick = 32857
	return g


const WIN := {"waves_held": 6, "destroyed": 19690, "lost": 12800, "victory_bonus": 1214, "total": 17504, "grade": "S"}


# ------------------------------------------------------------------ the module

func test_records_round_trip_per_map_and_difficulty(t) -> void:
	_wipe()
	t.ok(Records.PATH.begins_with("user://") and Records.PATH.ends_with("records.cfg"), "the real file lives under user://")
	t.eq(Records.best("kestrel", "normal", P), 0, "no file: no best")
	t.eq(Records.submit("kestrel", "normal", 5000, P), true, "the first score is a new best")
	t.eq(Records.best("kestrel", "normal", P), 5000, "and is kept")
	t.eq(Records.best("kestrel", "hard", P), 0, "per difficulty")
	t.eq(Records.best("survival", "normal", P), 0, "per map")
	t.eq(Records.submit("kestrel", "hard", 900, P), true, "another preset has its own best")
	t.eq(Records.submit("kestrel", "normal", 7000, P), true, "a higher score is a new best")
	t.eq(Records.best("kestrel", "normal", P), 7000, "and replaces the old one")
	t.eq(Records.best("kestrel", "hard", P), 900, "the other preset is untouched")
	t.ok(not FileAccess.file_exists(P + ".next"), "the temporary file was renamed into place")
	_wipe()


func test_a_lower_or_equal_score_is_not_a_new_best(t) -> void:
	_wipe()
	Records.submit("kestrel", "normal", 6000, P)
	t.eq(Records.submit("kestrel", "normal", 5999, P), false, "lower")
	t.eq(Records.submit("kestrel", "normal", 6000, P), false, "equal")
	t.eq(Records.best("kestrel", "normal", P), 6000, "the best stands")
	_wipe()


func test_records_never_write_under_res(t) -> void:
	t.eq(Records.submit("kestrel", "normal", 100, "res://records.cfg"), false, "refused")
	t.ok(not FileAccess.file_exists("res://records.cfg"), "nothing under res://")
	t.eq(Records.best("kestrel", "normal", "res://records.cfg"), 0, "and nothing read from there")


func test_a_missing_or_corrupt_file_reads_as_no_records(t) -> void:
	_wipe()
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[[[ not a config")
	f.close()
	t.eq(Records.best("kestrel", "normal", P), 0, "corrupt: no best")
	t.eq(Records.submit("kestrel", "normal", 300, P), true, "a score still lands")
	t.eq(Records.best("kestrel", "normal", P), 300, "and reads back")
	f = FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[kestrel]\nnormal=\"lots\"\nhard=-40\n")
	f.close()
	t.eq(Records.best("kestrel", "normal", P), 0, "a value that is not a number reads as none")
	t.eq(Records.best("kestrel", "hard", P), 0, "a negative one too")
	t.eq(Records.submit("kestrel", "normal", -5, P), true, "a negative total is recorded as 0")
	t.eq(Records.best("kestrel", "normal", P), 0, "as 0")
	t.eq(Records.submit("../x", "normal", 50, P), false, "a malformed map key is refused")
	t.eq(Records.submit("kestrel", "Normal!", 50, P), false, "a malformed difficulty key is refused")
	_wipe()


# ------------------------------------------------------------------ the debrief

func test_debrief_shows_score_rows_grade_and_best(t) -> void:
	var g = _kestrel(WIN, "hard")
	var vm := LiveScreens.debrief_vm(g, SessionLog.new(), {"best": 17504, "new_best": true})
	var sc: Dictionary = vm["score"]
	t.eq(sc["total"], "17,504", "the total")
	t.eq(sc["grade"], "S", "the grade")
	t.eq(sc["best"], "17,504", "the best")
	t.eq(sc["new_best"], true, "flagged")
	var labels: Array = sc["rows"].map(func(r): return r["label"])
	var values: Array = sc["rows"].map(func(r): return r["value"])
	t.eq(labels, ["Waves held (6 x 500)", "Enemy value destroyed", "Losses (half of 12,800)", "Victory bonus", "Hard difficulty"], "the score rows")
	t.eq(values, ["+3,000", "+19,690", "-6,400", "+1,214", "x1.5"], "their values")
	# Without a record (no records file in use) the best is left out; a loss has no victory bonus row.
	var loss := {"waves_held": 3, "destroyed": 10070, "lost": 12230, "victory_bonus": 0, "total": 8182, "grade": "A"}
	g = _kestrel(loss, "normal", 1)
	vm = LiveScreens.debrief_vm(g, SessionLog.new())
	t.ok(not vm["score"].has("best"), "no best without a record")
	t.eq(vm["score"]["new_best"], false, "and no flag")
	labels = vm["score"]["rows"].map(func(r): return r["label"])
	t.ok(not labels.has("Victory bonus"), "no bonus row on a loss")
	t.eq(vm["score"]["rows"][-1]["value"], "x1", "Normal multiplies by one")
	# Survival (no depth block) and classic snapshots get no score at all.
	var s := Stub.new()
	s.bridge_winner = 0
	t.ok(not LiveScreens.debrief_vm(s, SessionLog.new()).has("score"), "Survival: no score")


func test_the_score_block_fits_the_column_beside_every_other_block(t) -> void:
	for winner in [0, 1]:
		var g = _kestrel(WIN, "easy", winner)
		var log := SessionLog.new()
		# A full record: samples, casualties of every kind, relays.
		for sec in range(0, 600, 5):
			g.bridge_tick = sec * 30
			g.bridge_money = 400 + sec
			g.bridge_power_demand = 200 if sec > 400 else 100
			g.bridge_power_generation = 150
			log.observe(g)
		for kind in ["Infantry", "AntiArmor", "Tank", "Helicopter", "Capital"]:
			log.unit_added(kind, 0, "unit")
			log.unit_removed(kind, 0, "unit")
		var vm := LiveScreens.debrief_vm(g, log, {"best": 20000, "new_best": false})
		var col := Debrief.new()
		col.apply(vm)
		t.ok(col.blocks.has("score"), "%d: the score block is drawn" % winner)
		var rects: Array = col.blocks.values()
		var names: Array = col.blocks.keys()
		for i in rects.size():
			t.ok(rects[i].end.x <= 960.0 + 0.01, "%d: %s inside the column" % [winner, names[i]])
			for j in range(i + 1, rects.size()):
				t.ok(not rects[i].intersects(rects[j]), "%d: %s overlaps %s" % [winner, names[i], names[j]])
		t.near(col.blocks["buttons"].position.y, 992.0, 0.01, "%d: the buttons stay pinned to the bottom of 1080" % winner)
		t.ok(col.content_height <= 1080.0 + 0.01, "%d: nothing grows the column past 1080" % winner)
		var texts := _texts(col)
		t.ok(texts.has("S"), "%d: the grade" % winner)
		t.ok(texts.has("17,504"), "%d: the total" % winner)
		t.ok(texts.any(func(s): return s.contains("20,000")), "%d: the best" % winner)
		t.ok(not texts.any(func(s): return s.to_upper() == "NEW BEST"), "%d: no flag when not a new best" % winner)
		col.free()
	var col := Debrief.new()
	col.apply(LiveScreens.debrief_vm(_kestrel(WIN), SessionLog.new(), {"best": 17504, "new_best": true}))
	t.ok(_texts(col).any(func(s): return s.to_upper() == "NEW BEST"), "the New best flag")
	col.free()


# ------------------------------------------------------------------ submitting from the game

func _ui(t, g) -> GameUI:
	var ui := GameUI.new()
	g.viewport = t.root
	t.root.add_child(ui)
	ui.setup(g)
	return ui


func _drop(ui: Node) -> void:
	ui.get_parent().remove_child(ui)
	ui.free()


func test_a_decided_kestrel_match_submits_its_score_once(t) -> void:
	_wipe()
	var g = _kestrel(WIN, "hard")
	g.records_path = P
	var ui := _ui(t, g)
	ui.show_debrief()
	t.eq(Records.best("kestrel", "hard", P), 17504, "the decided match's total is the best")
	var texts := _texts(ui.scrim)
	t.ok(texts.any(func(s): return s.to_upper() == "NEW BEST"), "flagged as a new best")
	# Review, then the debrief again (or a second end screen): still one submission. Lower the stored best to see it.
	ui._on_debrief_action("review", null)
	var cf := ConfigFile.new()
	cf.set_value("kestrel", "hard", 10)
	cf.save(P)
	ui.show_debrief()
	t.eq(Records.best("kestrel", "hard", P), 10, "not submitted twice for one match")
	_drop(ui)
	_wipe()


func test_survival_an_undecided_match_and_no_records_path_submit_nothing(t) -> void:
	_wipe()
	var s := Stub.new()
	s.bridge_winner = 1
	s.records_path = P
	var ui := _ui(t, s)
	ui.show_debrief()
	t.ok(not FileAccess.file_exists(P), "Survival writes no record")
	_drop(ui)
	var g = _kestrel(WIN, "normal", -1)
	g.records_path = P
	ui = _ui(t, g)
	t.eq(ui.record_score(), {}, "an undecided match (a restart mid-match) records nothing")
	t.ok(not FileAccess.file_exists(P), "no file")
	_drop(ui)
	g = _kestrel(WIN)
	t.eq(g.records_path, "", "the stub keeps no records by default")
	ui = _ui(t, g)
	ui.show_debrief()
	t.ok(not FileAccess.file_exists(P), "nothing written")
	var texts := _texts(ui.scrim)
	t.ok(texts.has("17,504"), "the score is still shown")
	t.ok(not texts.any(func(s): return s.to_upper().begins_with("BEST")), "without a best")
	_drop(ui)
	_wipe()
