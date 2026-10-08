extends RefCounted
## Settings (Task 4): the user://settings.cfg owner (load, clamp, save, never under res://), the bus volumes and window
## mode it applies (on recording stubs, never a real audio device or window), the Settings screen, the title and pause
## entries, and the fog choice landing in the next match.json. Every file lives under user://test_settings* and is
## removed again; no test touches user://settings.cfg.
const Settings := preload("res://scripts/ui/settings.gd")
const Screen := preload("res://scripts/ui/sections/settings_screen.gd")
const MatchConfig := preload("res://scripts/match_config.gd")
const LiveScreens := preload("res://scripts/ui/live_screens.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
const Stub := preload("res://tests/stub_game.gd")
const U := preload("res://tests/section_util.gd")
const P := "user://test_settings/settings.cfg"
const UI_DIR := "user://test_settings_ui"


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# ------------------------------------------------------------------ the module

func test_round_trip_and_clamp(t) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	var v := Settings.defaults()
	v["audio/sfx"] = 0.25
	v["game/fog"] = false
	t.eq(Settings.save_to(P, v), OK)
	var back := Settings.load_from(P)
	t.near(back["audio/sfx"], 0.25, 0.001)
	t.eq(back["game/fog"], false)
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", 7.0)
	cf.save(P)
	t.near(Settings.load_from(P)["audio/master"], 1.0, 0.001)
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")


func test_settings_never_write_under_res(t) -> void:
	t.eq(Settings.save_to("res://settings.cfg", Settings.defaults()), ERR_FILE_NO_PERMISSION)
	t.ok(not FileAccess.file_exists("res://settings.cfg"))
	t.eq(Settings.set_value("audio/music", 0.5, "res://settings.cfg"), ERR_FILE_NO_PERMISSION, "set_value refuses too")
	t.ok(not FileAccess.file_exists("res://settings.cfg"), "still nothing under res://")
	t.ok(Settings.PATH.begins_with("user://"), "the real file lives under user://")


func test_corrupt_file_gives_defaults(t) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[[[ not a config")
	f.close()
	t.eq(Settings.load_from(P), Settings.defaults())
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")


func test_defaults_missing_file_and_bad_values(t) -> void:
	t.eq(Settings.defaults(), {"audio/master": 1.0, "audio/sfx": 1.0, "audio/ui": 1.0, "audio/ambient": 1.0, "audio/music": 1.0, "game/fog": true, "video/window_mode": "windowed", "coach/never_show": false, "game/difficulty": "normal"}, "the brief's defaults, plus Task 9's coach bit and Task 20's preset")
	t.eq(Settings.load_from("user://test_settings/none.cfg"), Settings.defaults(), "a missing file reads as the defaults")
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[audio]\nmaster=-3.0\nsfx=\"loud\"\nmusic=0\n\n[game]\nfog=1\ndifficulty=\"brutal\"\n\n[video]\nwindow_mode=\"kiosk\"\n")
	f.close()
	var v := Settings.load_from(P)
	t.near(v["audio/master"], 0.0, 1e-6, "a negative volume is clamped to 0")
	t.near(v["audio/sfx"], 1.0, 1e-6, "a volume that is not a number is the default")
	t.near(v["audio/music"], 0.0, 1e-6, "an integer volume is read")
	t.eq(v["game/fog"], true, "the fog is a bool or the default")
	t.eq(v["video/window_mode"], "windowed", "an unknown window mode is the default")
	t.eq(v["game/difficulty"], "normal", "an unknown preset is the default")
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")


func test_get_and_set_value_save_at_once(t) -> void:
	t.eq(Settings.get_value("audio/music", P), 1.0, "the default before any file")
	t.eq(Settings.set_value("audio/music", 0.4, P), OK, "set_value makes the folder and saves")
	t.near(float(Settings.get_value("audio/music", P)), 0.4, 1e-6, "read back from the file")
	t.eq(Settings.set_value("video/window_mode", "fullscreen", P), OK)
	t.eq(Settings.get_value("video/window_mode", P), "fullscreen", "window mode saved")
	t.near(float(Settings.get_value("audio/music", P)), 0.4, 1e-6, "an earlier key is kept")
	t.eq(Settings.set_value("audio/bass", 0.5, P), ERR_INVALID_PARAMETER, "an unknown key is refused")
	t.eq(Settings.get_value("audio/bass", P), null, "and reads as null")
	t.ok(not FileAccess.file_exists(P + ".next"), "the temporary file was renamed away")
	var text := FileAccess.get_file_as_string(P)
	t.ok(text.contains("[audio]") and text.contains("[game]") and text.contains("[video]"), "one section per group")
	DirAccess.remove_absolute(P)
	DirAccess.remove_absolute("user://test_settings")


# ------------------------------------------------------------------ applying (recording stubs only)

func test_apply_audio_sets_each_bus_and_zero_mutes(t) -> void:
	var rec := Stub.BusRecorder.new()
	var v := Settings.defaults()
	v["audio/sfx"] = 0.25
	v["audio/music"] = 0.0
	Settings.apply_audio(v, rec)
	t.eq(rec.mute.get("Music"), true, "music at 0 mutes the Music bus")
	t.eq(rec.mute.get("SFX"), false, "SFX is not muted")
	t.near(float(rec.volume["SFX"]), linear_to_db(0.25), 1e-4, "linear 0.25 is about -12 dB on SFX")
	for bus in ["Master", "UI", "Ambient"]:
		t.near(float(rec.volume[bus]), 0.0, 1e-6, "%s at full volume is 0 dB" % bus)
		t.eq(rec.mute[bus], false, "%s not muted" % bus)
	t.ok(not rec.volume.has("SFX_L1") and not rec.volume.has("SFX_R2"), "the panned sub-buses follow SFX, untouched")
	v["audio/music"] = 0.5
	Settings.apply_audio(v, rec)
	t.eq(rec.mute["Music"], false, "raised again: unmuted")
	t.near(float(rec.volume["Music"]), linear_to_db(0.5), 1e-4, "at its level")


func test_the_duck_lowers_the_players_level_instead_of_replacing_it(t) -> void:
	var rec := Stub.BusRecorder.new()
	var v := Settings.defaults()
	v["audio/ambient"] = 0.5
	Settings.apply_audio(v, rec)
	Settings.apply_duck(-9.0, rec)
	t.near(float(rec.volume["Ambient"]), linear_to_db(0.5) - 9.0, 1e-4, "Ambient: the player's level plus the duck")
	t.near(float(rec.volume["Music"]), -9.0, 1e-4, "Music at full volume: just the duck")
	t.near(float(rec.volume["SFX"]), 0.0, 1e-6, "SFX is never ducked")
	Settings.apply_duck(0.0, rec)
	t.near(float(rec.volume["Ambient"]), linear_to_db(0.5), 1e-4, "the duck released: back to the player's level")
	v["audio/ambient"] = 0.25
	Settings.apply_duck(-6.0, rec)
	Settings.apply_audio(v, rec)
	t.near(float(rec.volume["Ambient"]), linear_to_db(0.25) - 6.0, 1e-4, "a volume change keeps a running duck")
	var pool := (load("res://scripts/audio/audio_pool.gd") as GDScript).source_code
	t.ok(pool.contains("Settings.apply_duck(db)"), "the audio pool ducks through Settings")
	t.ok(not pool.contains("set_bus_volume_db"), "and sets no bus volume of its own")


func test_apply_window_changes_only_a_real_difference(t) -> void:
	var win := Stub.WindowRecorder.new()
	Settings.apply_window(Settings.defaults(), win)
	t.eq(win.sets, [], "windowed on a windowed window: nothing")
	var v := Settings.defaults()
	v["video/window_mode"] = "fullscreen"
	Settings.apply_window(v, win)
	t.eq(win.sets, [DisplayServer.WINDOW_MODE_FULLSCREEN], "fullscreen")
	Settings.apply_window(v, win)
	t.eq(win.sets.size(), 1, "already fullscreen: nothing")
	Settings.apply_window(Settings.defaults(), win)
	t.eq(win.sets.back(), DisplayServer.WINDOW_MODE_WINDOWED, "back to a window")
	win.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	win.sets.clear()
	Settings.apply_window(Settings.defaults(), win)
	t.eq(win.sets, [], "a maximised window already counts as windowed")


# ------------------------------------------------------------------ the screen

func _build(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Screen.build(root, vm, func(name: String, arg: Variant = null) -> void: log.append([name, arg]))
	return [root, log]


## What a drag does. Godot 4.7 emits value_changed only for the player's input, not for `value` set in code, so the test
## sets the value and emits the signal the drag would.
func _move(slider: HSlider, v: float) -> void:
	slider.value = v
	slider.value_changed.emit(slider.value)


func _slider(root: Node, key: String) -> HSlider:
	return root.find_child(key.replace("/", "_"), true, false) as HSlider


func test_screen_shows_five_sliders_fog_window_and_the_keys(t) -> void:
	var v := Settings.defaults()
	v["audio/sfx"] = 0.25
	var b := _build(Screen.vm(v, false, true))
	var root: Control = b[0]
	for key in Settings.BUSES:
		t.ok(_slider(root, key) != null, "a slider for " + key)
	t.near(_slider(root, "audio/sfx").value, 0.25, 1e-6, "at the saved value")
	for label in ["Master", "Effects", "Interface", "Ambience", "Music", "25%", "100%"]:
		t.ok(U.has_text(root, label), "shows " + label)
	t.ok(U.has_text(root, "Fog of war") and U.has_text(root, "Applies next match"), "the fog toggle says when it applies")
	t.ok(U.button_with(root, "On") != null and U.button_with(root, "Off") != null, "fog on and off")
	t.ok(U.button_with(root, "Windowed") != null and U.button_with(root, "Fullscreen") != null, "window mode options")
	for label in ["Pause menu", "Attack-move", "Jump to alert", "Read only"]:
		t.ok(U.has_text(root, label), "the read-only key list shows " + label)
	t.ok(U.button_with(root, "Rebind") == null, "no rebinding")
	for s in U.texts(root):
		t.ok(not str(s).contains(String.chr(0x2014)) and not str(s).contains(String.chr(0x2013)), "no dash in: " + str(s))
	root.free()
	var empty := Control.new()
	Screen.build(empty, {}, Callable())
	t.eq(empty.get_child_count(), 0, "nothing for {}")
	empty.free()


func test_screen_emits_each_change(t) -> void:
	var b := _build(Screen.vm(Settings.defaults(), true, false))
	var root: Control = b[0]
	var log: Array = b[1]
	t.ok(U.has_text(root, "Pause / Settings"), "opened from the pause menu")
	_move(_slider(root, "audio/master"), 0.4)
	t.eq(log.back(), ["set", ["audio/master", 0.4]], "a slider change is a set")
	t.ok(U.has_text(root, "40%"), "its percent follows at once")
	U.button_with(root, "Off").pressed.emit()
	t.eq(log.back(), ["set", ["game/fog", false]], "fog off")
	U.button_with(root, "Fullscreen").pressed.emit()
	t.eq(log.back(), ["set", ["video/window_mode", "fullscreen"]], "fullscreen")
	U.button_with(root, "Back").pressed.emit()
	t.eq(log.back(), ["settings_back", null], "Back")
	root.free()


# ------------------------------------------------------------------ the title entry and the next match.json

func _make(t, kestrel := false) -> Array:
	_wipe(UI_DIR)
	MatchConfig.reset()
	DirAccess.make_dir_recursive_absolute(UI_DIR)
	var g := Stub.new()
	g.viewport = t.root
	g.runtime_directory = UI_DIR
	g.settings_path = UI_DIR.path_join("settings.cfg")
	if kestrel:
		g.use_kestrel()
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	return [g, ui]


func _drop(p: Array) -> void:
	p[1].free()
	_wipe(UI_DIR)
	MatchConfig.reset()


func _press(root: Node, text: String) -> void:
	for b in U.buttons(root):
		if (b as Button).text == text and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return
	printerr("  test_settings: no enabled button " + text)


func _match_json() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(UI_DIR.path_join("match.json")))


func test_title_settings_entry_is_enabled_and_opens_the_screen(t) -> void:
	var item: Dictionary = LiveScreens.title_vm(true, 12)["menu"].filter(func(i): return i.id == "settings")[0]
	t.ok(not item.get("disabled", false), "the title's Settings entry is enabled")
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	_press(ui.title, "Settings")
	t.ok(ui.settings_open, "Settings opens the screen")
	t.eq(ui.settings_layer.find_children("*", "HSlider", true, false).size(), 5, "with five sliders")
	t.ok(U.has_text(ui.settings_layer, "Settings") and not U.has_text(ui.settings_layer, "Pause / Settings"), "titled for the title screen")
	_move(ui.settings_layer.find_child("audio_music", true, false) as HSlider, 0.0)
	t.eq(g.audio_server.mute.get("Music"), true, "music at 0 mutes the Music bus at once")
	t.near(float(Settings.get_value("audio/music", g.settings_path)), 0.0, 1e-6, "and is saved")
	_press(ui.settings_layer, "Fullscreen")
	t.eq(g.display_server.sets, [DisplayServer.WINDOW_MODE_FULLSCREEN], "window mode applied at once")
	t.eq(Settings.get_value("video/window_mode", g.settings_path), "fullscreen", "and saved")
	t.ok(U.has_text(ui.settings_layer, "Fullscreen"), "the screen is rebuilt with the choice")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	t.ok(ui.route_title_key(esc), "Esc on the title is the settings screen's")
	t.ok(not ui.settings_open and ui.settings_layer.get_child_count() == 0, "and closes it")
	_press(ui.title, "Settings")
	_press(ui.settings_layer, "Back")
	t.ok(not ui.settings_open, "Back closes it")
	t.ok(not FileAccess.file_exists("user://settings.cfg.next"), "the real settings file was never written")
	_drop(p)


func test_the_fog_choice_lands_in_the_next_match_json(t) -> void:
	var p := _make(t)
	var ui = p[1]
	var g = p[0]
	_press(ui.title, "Settings")
	_press(ui.settings_layer, "Off")
	t.eq(Settings.get_value("game/fog", g.settings_path), false, "fog off saved")
	_press(ui.settings_layer, "Back")
	_press(ui.title, "New operation")
	_press(ui.picker_layer, "Deploy forces")
	t.eq(_match_json().fog, false, "the picked match is written without fog")
	t.eq(_match_json().scenario, "kestrel", "on the picked map")
	_drop(p)


func test_debrief_restart_takes_the_current_fog_choice(t) -> void:
	var p := _make(t, true)
	var g = p[0]
	var ui = p[1]
	Settings.set_value("game/fog", false, g.settings_path)
	ui.begin_operation()
	g.bridge_winner = 1
	ui.show_debrief()
	_press(ui.scrim, "Restart")
	t.eq(_match_json().fog, false, "Restart writes the fog choice of now")
	t.eq(g.calls.back(), ["restart"], "and restarts")
	_drop(p)


func test_title_deploy_relaunches_only_when_the_fog_differs(t) -> void:
	var p := _make(t, true)  # a fogged Kestrel start frame is on screen
	var g = p[0]
	var ui = p[1]
	_press(ui.title, "Deploy forces")
	t.eq(g.calls, [["deploy"]], "fog on and a fogged map: deploys at once, as before")
	_drop(p)
	p = _make(t, true)
	g = p[0]
	ui = p[1]
	Settings.set_value("game/fog", false, g.settings_path)
	_press(ui.title, "Deploy forces")
	t.eq(g.calls, [], "fog off but the bridge serves a fogged map: no deploy yet")
	t.eq(_match_json().fog, false, "match.json asks for the match without fog")
	t.ok(FileAccess.file_exists(UI_DIR.path_join("restart.flag")), "and restart.flag rebuilds it")
	DirAccess.remove_absolute(UI_DIR.path_join("restart.flag"))
	ui.process(0.2)
	t.eq(g.calls, [["deploy"]], "deployed once the bridge took the flag")
	_drop(p)
