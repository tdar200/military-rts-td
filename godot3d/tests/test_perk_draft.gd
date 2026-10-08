extends RefCounted
## Task 26: run mode in the client. The daily seed is the UTC date; a run's match.json names `run` and the remembered
## `perk_pool`; a snapshot with a pending draft pauses the bridge (pause.flag) behind a three-card modal, and a pick sends
## `perk,<id>` and lifts the flag; the perk pool gains one depth perk per run that reached wave 6, never past 0xFFF; the
## Kestrel objective and HUD read the run's wave counter. The pause flag and the packets are written by the real
## earthfront_3d.gd (out of the tree) the stub forwards to, so the files on disk are the ones the bridge would read. Every
## file lives under user://test_perk_draft and is removed again.
const MatchConfig := preload("res://scripts/match_config.gd")
const Settings := preload("res://scripts/ui/settings.gd")
const PerkDraft := preload("res://scripts/ui/sections/perk_draft.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
const Stub := preload("res://tests/stub_game.gd")
const U := preload("res://tests/section_util.gd")
const KestrelObjectives := preload("res://scripts/world/kestrel_objectives.gd")
const FeedbackEvents := preload("res://scripts/ui/feedback_events.gd")
const DIR := "user://test_perk_draft"
const SETTINGS := DIR + "/settings.cfg"


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


## [stub, ui, real game]: the GameUI on the stub; the stub's pause, perk and speed calls reach the real game script, whose
## runtime directory is DIR.
func _make(t) -> Array:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var real = (load("res://scripts/earthfront_3d.gd") as GDScript).new()  # not in the tree: _ready never runs
	real.runtime_directory = DIR
	var g := Stub.new()
	g.viewport = t.root
	g.runtime_directory = DIR
	g.settings_path = SETTINGS
	g.forward = real
	g.use_kestrel()
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	return [g, ui, real]


func _drop(p: Array) -> void:
	p[1].free()
	p[2].free()
	_clean()


func _run_snapshot(g, wave: int, draft: Variant, held := 0, pool := 0xFF) -> void:
	g.bridge_snapshot["depth"]["run"] = {"wave": wave, "draft": draft, "pool": pool, "held": held}


## The lines written to the commands directory since the last call (consumed, as the bridge would).
func _lines() -> Array:
	var dir := ProjectSettings.globalize_path(DIR.path_join("commands"))
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


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _flag() -> bool:
	return FileAccess.file_exists(DIR.path_join("pause.flag"))


func test_daily_seed_is_the_utc_date(t) -> void:
	t.eq(MatchConfig.daily_seed(1791415800), 20261007, "23:30 UTC on 7 October is still the 7th (UTC, whatever the local zone)")
	t.eq(MatchConfig.daily_seed(1791418200), 20261008, "00:10 UTC on 8 October is the 8th")
	t.eq(MatchConfig.daily_seed(1798761599), 20261231, "the last second of the year")
	t.ok(MatchConfig.daily_seed(1791415800) <= MatchConfig.SEED_MAX, "a daily seed is a valid seed")


func test_a_run_config_names_run_and_the_pool(t) -> void:
	var run := MatchConfig.to_json({"scenario": "kestrel", "seed": 20261007, "difficulty": "normal", "fog": true, "mode": "run", "perk_pool": 0x1FF})
	t.eq(run, "{\"scenario\":\"kestrel\",\"seed\":20261007,\"difficulty\":\"normal\",\"fog\":true,\"run\":true,\"perk_pool\":511}", "a run names run and its pool")
	var plain := MatchConfig.to_json({"scenario": "kestrel", "seed": 5, "mode": "operation", "perk_pool": 0x1FF})
	t.ok(not plain.contains("run") and not plain.contains("perk_pool"), "an operation names neither")
	var survival := MatchConfig.to_json({"scenario": "survival", "mode": "run", "perk_pool": 0x1FF})
	t.ok(not survival.contains("run"), "Survival never runs")
	var bad := MatchConfig.to_json({"scenario": "kestrel", "mode": "run", "perk_pool": 0x10000})
	t.ok(bad.contains("\"perk_pool\":255"), "a pool out of range is the default pool")
	var replay := MatchConfig.to_json({"scenario": "kestrel", "replay": "/abs/replays/1_kestrel_5.rpl"}, "/abs/replays")
	t.ok(replay.ends_with(",\"replay_dir\":\"/abs/replays\",\"replay\":\"/abs/replays/1_kestrel_5.rpl\"}"), "a replay config names the file to play: " + replay)
	var snap := {"depth": {"seed": 77.0, "difficulty": "hard", "run": {"wave": 3.0, "draft": null, "pool": 511.0, "held": 1.0}}}
	t.eq(MatchConfig.from_snapshot(snap), {"seed": 77, "difficulty": "hard", "mode": "run", "perk_pool": 511}, "Restart of a run replays the run")


func test_the_pool_unlock_adds_one_bit_per_run_that_reached_wave_six(t) -> void:
	t.eq(Settings.defaults()["run/perk_pool"], 0xFF, "the default pool is the first eight perks")
	t.eq(Settings.next_pool(0xFF), 0x1FF, "one more bit")
	t.eq(Settings.next_pool(0x7FF), 0xFFF, "the last bit")
	t.eq(Settings.next_pool(0xFFF), 0xFFF, "never past the full pool")
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui.begin_operation()
	_run_snapshot(g, 5, null)
	ui.process(0.2)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0xFF, "wave 5 unlocks nothing")
	_run_snapshot(g, 6, null)
	ui.process(0.2)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0x1FF, "reaching wave 6 adds exactly one bit")
	_run_snapshot(g, 7, null)
	ui.process(0.2)
	ui.process(0.2)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0x1FF, "once per run, not once per wave")
	p[1].free()
	var ui2 := GameUI.new()
	t.root.add_child(ui2)
	ui2.setup(g)
	ui2.begin_operation()
	ui2.process(0.2)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0x3FF, "the next run that reaches wave 6 adds the next bit")
	ui2.free()
	Settings.set_value("run/perk_pool", 0xFFF, SETTINGS)
	var ui3 := GameUI.new()
	t.root.add_child(ui3)
	ui3.setup(g)
	ui3.begin_operation()
	ui3.process(0.2)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0xFFF, "the full pool stays full")
	g.bridge_snapshot.erase("depth")
	p[1] = ui3
	_drop(p)


func test_a_draft_pauses_and_a_pick_sends_the_perk(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	var real = p[2]
	ui.begin_operation()
	_run_snapshot(g, 1, null)
	ui.process(0.2)
	t.ok(not ui.draft_open(), "no draft, no modal")
	t.ok(not _flag(), "and no pause")
	_run_snapshot(g, 1, [4.0, 0.0, 11.0])
	ui.process(0.2)
	t.ok(ui.draft_open(), "a pending draft opens the modal")
	t.ok(_flag(), "and pause.flag holds the bridge")
	t.ok(ui.world_blocked(), "the world takes no input under it")
	for name in ["Field Upgrade", "Overcharge", "Capital Discount"]:
		t.ok(U.has_text(ui.draft_layer, name), "the card " + name)
	t.ok(U.has_text(ui.draft_layer, "One free level on your lowest Upgrades track"), "with its perk.rs description")
	t.ok(U.has_text(ui.draft_layer, "500 to 375"), "the Capital Discount card shows the price it gives")
	t.ok(ui.route_key(_key(KEY_5)), "the draft captures the control-group keys while open")
	t.ok(ui.draft_open() and _lines().is_empty(), "a key past the cards picks nothing")
	t.ok(ui.route_key(_key(KEY_3)), "3 takes the third card")
	t.eq(_lines(), ["perk,11"], "the pick reaches the bridge")
	t.ok(not _flag(), "and the bridge runs again")
	t.ok(not ui.draft_open(), "the modal closes")
	ui.process(0.2)
	t.ok(not ui.draft_open(), "the same draft, still in the last snapshot, does not open again")
	_run_snapshot(g, 2, null, 1 << 11)
	ui.process(0.2)
	_run_snapshot(g, 2, [1.0, 2.0], 1 << 11)
	ui.process(0.2)
	t.ok(ui.draft_open(), "the next draft opens")
	t.eq(U.buttons(ui.draft_layer).filter(func(b): return (b as Button).text.begins_with("perk:")).size(), 2, "a draft of two shows two cards")
	var card: Button = U.button_with(ui.draft_layer, "perk:2")
	card.pressed.emit()
	t.eq(_lines(), ["perk,2"], "a click picks too")
	t.ok(not _flag(), "the flag is gone")
	t.ok(not ui.route_key(_key(KEY_1)), "keys 1 to 9 belong to the control groups again")
	# Esc pauses over a draft; resuming keeps the draft's hold until the pick.
	_run_snapshot(g, 3, [5.0, 6.0, 7.0], (1 << 11) | (1 << 2))
	ui.process(0.2)
	t.ok(ui.draft_open() and _flag(), "a third draft holds the bridge")
	t.ok(ui.route_key(_key(KEY_ESCAPE)), "Esc opens the pause menu over it")
	t.ok(ui.paused(), "paused")
	ui.close_pause()
	t.ok(_flag(), "resuming the menu leaves the draft's hold")
	t.ok(ui.route_key(_key(KEY_1)), "1 takes the first card")
	t.eq(_lines(), ["perk,5"], "Rapid Cycle")
	t.ok(not _flag(), "now it runs")
	t.eq(real.sim_paused, false, "the game is not paused")
	_drop(p)


## The HUD surfaces a draft must not cover at 1920x1080 (hud.gd): the top bar, the objectives card at its run height
## (six rows), the wave card, the idle-crew and next-alert chips, and the bottom HUD.
const HUD_RECTS := {
	"top bar": Rect2(12, 10, 1896, 56),
	"objectives card": Rect2(12, 76, 420, 42 + 25 * 6),
	"wave card": Rect2(962, 76, 440, 150),
	"alert chips": Rect2(1540, 240, 370, 45),
	"bottom HUD": Rect2(0, 770, 1920, 310),
}


func test_the_draft_fits_the_play_area_without_covering_the_hud(t) -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	var model := PerkDraft.vm({"wave": 11, "draft": [4, 6, 11], "pool": 0xFFF, "held": 0x7FF})
	PerkDraft.build(layer, model)
	var panel := layer.get_node("DraftPanel") as Control
	var rect := Rect2(panel.position, panel.size)
	t.ok(Rect2(0, 0, 1920, 1080).encloses(rect), "the panel is on screen: %s" % rect)
	for name in HUD_RECTS:
		t.ok(not rect.intersects(HUD_RECTS[name]), "the panel %s clears the %s" % [rect, name])
		t.ok(not PerkDraft.DIM_RECT.intersects(HUD_RECTS[name]), "the dim %s clears the %s" % [PerkDraft.DIM_RECT, name])
	for b in U.buttons(layer):
		if (b as Button).text.begins_with("perk:"):
			t.ok(rect.encloses(Rect2(b.position, b.size)), "each card sits inside the panel")
	layer.free()


func test_the_pause_flag_belongs_to_the_menu_and_the_draft_together(t) -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var game = (load("res://scripts/earthfront_3d.gd") as GDScript).new()
	game.runtime_directory = DIR
	game.set_draft_hold(true)
	t.ok(_flag(), "a draft writes pause.flag")
	game.set_sim_paused(true)
	game.set_sim_paused(false)
	t.ok(_flag(), "the menu closing does not lift the draft's hold")
	game.set_draft_hold(false)
	t.ok(not _flag(), "the pick does")
	game.set_sim_paused(true)
	game.set_draft_hold(true)
	game.set_draft_hold(false)
	t.ok(_flag(), "a draft answered under the menu leaves the menu's pause")
	game.set_sim_paused(false)
	t.ok(not _flag(), "both gone, the bridge runs")
	game.free()
	_clean()


func test_perk_text_mirrors_perk_rs(t) -> void:
	var src := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/perk.rs"))
	t.ok(src != "", "perk.rs is readable from the project")
	t.eq(PerkDraft.PERK_TEXT.size(), 12, "twelve perks")
	var ids := {"OVERCHARGE": 0, "LOGISTICS": 1, "CONSCRIPTION": 2, "BULWARK": 3, "FIELD_UPGRADE": 4, "RAPID_CYCLE": 5,
		"REFINERY_DISCOUNT": 6, "LONG_SIGHT": 7, "EARLY_TOOLING": 8, "HARDENED_WALLS": 9, "FIELD_REPAIR": 10, "CAPITAL_DISCOUNT": 11}
	var name_fn := src.substr(src.find("pub const fn name"), src.find("pub const fn description") - src.find("pub const fn name"))
	var desc_fn := src.substr(src.find("pub const fn description"))
	for key in ids:
		var id: int = ids[key]
		var row: Array = PerkDraft.PERK_TEXT[id]
		var name_rs: String = "Bulwark" if key == "BULWARK" else _arm(name_fn, key)
		var desc_rs: String = "+2 armor mitigation" if key == "BULWARK" else _arm(desc_fn, key)
		t.eq(row[0], name_rs, "name of %d" % id)
		t.eq(row[1], desc_rs, "description of %d" % id)


## The string a `KEY => "..."` match arm returns.
func _arm(fn_text: String, key: String) -> String:
	var at := fn_text.find(key + " => \"")
	if at < 0:
		return ""
	var start := at + key.length() + 5
	return fn_text.substr(start, fn_text.find("\"", start) - start)


func test_the_capital_price_follows_capital_discount(t) -> void:
	t.eq(FeedbackEvents.unit_cost("Capital", {}), 500, "the Capital costs 500")
	var snap := {"depth": {"run": {"wave": 2, "draft": null, "pool": 255, "held": 1 << 11}}}
	t.eq(FeedbackEvents.unit_cost("Capital", snap), 375, "Capital Discount takes a quarter off")
	t.eq(FeedbackEvents.unit_cost("Tank", snap), FeedbackEvents.unit_cost("Tank"), "other units keep their price")


func test_a_run_objective_holds_twelve_waves(t) -> void:
	var g := Stub.new()
	g.use_kestrel()
	var snap: Dictionary = g.bridge_snapshot.duplicate(true)
	snap["depth"]["run"] = {"wave": 4, "draft": null, "pool": 255, "held": 3}
	t.eq(KestrelObjectives.TITLES.size(), 5, "five objectives")
	t.eq(KestrelObjectives.title_for(4, snap), "Hold twelve waves", "a run's last objective is the twelfth wave")
	t.eq(KestrelObjectives.title_for(4, g.bridge_snapshot), KestrelObjectives.TITLES[4], "an operation still breaks the Core Node")
	t.ok(KestrelObjectives.run_detail(snap).contains("4 of 12"), "the wave counter: " + KestrelObjectives.run_detail(snap))
	g.bridge_snapshot = snap
	var LiveAdapter := preload("res://scripts/ui/live_adapter.gd")
	var adapter = LiveAdapter.new(g)
	var line := adapter.run_line()
	t.ok(line.contains("4 of 12") and line.contains("2 perks"), "the HUD's run line: " + line)
	# The counter rides on the run's own objective row, so a run's card is no taller than an operation's (the live
	# capture showed an extra row running into the Territory panel under the card).
	var items: Array = adapter._kestrel_card()["items"]
	g.bridge_snapshot = _without_run(snap)
	var op_items: Array = LiveAdapter.new(g)._kestrel_card()["items"]
	t.eq(items.size(), op_items.size(), "a run's card has as many rows as an operation's")
	var texts := items.map(func(i): return str(i["t"]))
	t.ok(texts.has(line) and line.begins_with("Hold twelve waves"), "the run row carries the counter: %s" % [texts])


func _without_run(snap: Dictionary) -> Dictionary:
	var out := snap.duplicate(true)
	out["depth"].erase("run")
	return out


func _press(root: Node, text: String) -> bool:
	for b in U.buttons(root):
		if (b as Button).text == text and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return true
	return false


func test_the_picker_starts_a_daily_run(t) -> void:
	var p := _make(t)
	var ui = p[1]
	Settings.set_value("run/perk_pool", 0x1FF, SETTINGS)
	ui.open_picker()
	t.ok(U.has_text(ui.picker_layer, "Operation") and U.has_text(ui.picker_layer, "Run"), "the Mode tabs")
	t.ok(_press(ui.picker_layer, "Run"), "Run")
	t.ok(U.has_text(ui.picker_layer, "Pool: 9 of 12 perks (unlocked: Early Tooling)"), "the run names its pool")
	t.ok(U.has_text(ui.picker_layer, "unlock Hardened Walls"), "and the next unlock")
	t.ok(_press(ui.picker_layer, "Daily seed"), "Daily seed")
	var today := MatchConfig.daily_seed(int(Time.get_unix_time_from_system()))
	t.eq(ui.picker_seed, today, "the seed is today's UTC date")
	t.eq(ui.picker_difficulty, "normal", "Normal stays the default preset")
	t.ok(_press(ui.picker_layer, "Deploy forces"), "Deploy forces")
	var json = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("match.json")))
	t.ok(json is Dictionary, "match.json written")
	if json is Dictionary:
		t.eq(int(json.seed), today, "the daily seed")
		t.eq(json.get("run", false), true, "a run")
		t.eq(int(json.get("perk_pool", 0)), 0x1FF, "with the remembered pool")
		t.ok(not json.has("replay"), "never a replay")
	ui.open_picker()
	_press(ui.picker_layer, "Run")
	ui._on_picker_action("pick", "survival")
	t.eq(ui.picker_mode, "operation", "Survival is always an operation")
	ui.close_picker()
	Settings.set_value("run/perk_pool", 0x10FF, SETTINGS)
	t.eq(Settings.get_value("run/perk_pool", SETTINGS), 0xFF, "a pool past the twelfth perk reads as the default")
	_drop(p)
