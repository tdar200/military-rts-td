extends RefCounted
## Kestrel music hooks (kestrel-depth Task 30): the pure MusicDirector's states and its hysteresis through plain calls, and
## the game's thin hook. No track exists yet, so track_for answers "" for every state and play makes no player: nothing
## here can sound.
const Music = preload("res://scripts/audio/music_director.gd")
const MainScene = preload("res://main.tscn")


func _ctx(on_title: bool, winner := -1, recent := INF) -> Dictionary:
	return {"on_title": on_title, "winner": winner, "recent_combat_s": recent}


func test_states_are_the_five_named(t) -> void:
	t.eq(Music.STATES, ["menu", "calm", "combat", "victory", "defeat"], "the five states, in order")
	var m = Music.new()
	t.eq(m.state, "menu", "a new director starts on the menu")


func test_title_then_calm_on_deploy(t) -> void:
	var m = Music.new()
	t.eq(m.update(_ctx(true), 0.0), "menu", "on the title")
	t.eq(m.update(_ctx(true), 5.0), "menu", "still the title")
	t.eq(m.update(_ctx(false), 6.0), "calm", "deployed and no shot: calm")
	t.eq(m.update(_ctx(false), 30.0), "calm", "no shot for a while: calm stays")


func test_calm_to_combat_on_a_shot_within_three_seconds(t) -> void:
	var m = Music.new()
	m.update(_ctx(false), 1.0)
	t.eq(m.update(_ctx(false, -1, 3.5), 10.0), "calm", "a shot 3.5 s ago is not combat")
	t.eq(m.update(_ctx(false, -1, 3.0), 11.0), "combat", "a shot 3 s ago is combat")
	var n = Music.new()
	n.update(_ctx(false), 1.0)
	t.eq(n.update(_ctx(false, -1, 0.0), 2.0), "combat", "a shot this frame is combat")


func test_combat_returns_to_calm_only_after_eight_quiet_seconds(t) -> void:
	var m = Music.new()
	m.update(_ctx(false), 0.0)
	t.eq(m.update(_ctx(false, -1, 0.0), 10.0), "combat", "the last shot at 10 s")
	t.eq(m.update(_ctx(false, -1, 4.0), 14.0), "combat", "4 s quiet: still combat (past the 3 s entry window)")
	t.eq(m.update(_ctx(false, -1, 7.9), 17.9), "combat", "7.9 s quiet: still combat")
	t.eq(m.update(_ctx(false, -1, 8.0), 18.0), "calm", "8 s quiet: calm")
	t.eq(m.update(_ctx(false, -1, 1.0), 20.0), "combat", "a new shot: combat again")
	t.eq(m.update(_ctx(false, -1, 2.0), 21.0), "combat", "a shot inside the hold renews it")
	t.eq(m.update(_ctx(false, -1, 7.0), 26.0), "combat", "7 s after the shot at 19 s")
	t.eq(m.update(_ctx(false, -1, 8.5), 27.5), "calm", "8.5 s after it: calm")
	t.eq(Music.COMBAT_ENTER_S, 3.0, "the entry window")
	t.eq(Music.COMBAT_HOLD_S, 8.0, "the hysteresis")


func test_victory_and_defeat_are_terminal(t) -> void:
	var m = Music.new()
	m.update(_ctx(false), 0.0)
	m.update(_ctx(false, -1, 0.0), 1.0)
	t.eq(m.update(_ctx(false, 0, 0.0), 2.0), "victory", "the player (owner 0) wins, even mid fight")
	t.eq(m.update(_ctx(false, -1, 0.0), 3.0), "victory", "a later shot does not leave it")
	t.eq(m.update(_ctx(true), 4.0), "victory", "nor the title")
	t.eq(m.update(_ctx(false, 1), 5.0), "victory", "nor another winner")
	var d = Music.new()
	d.update(_ctx(false), 0.0)
	t.eq(d.update(_ctx(false, 1), 1.0), "defeat", "the aliens win: defeat")
	t.eq(d.update(_ctx(false, 0), 2.0), "defeat", "terminal")
	t.eq(d.update(_ctx(false, -1, 0.0), 3.0), "defeat", "a shot does not leave it")
	var e = Music.new()
	t.eq(e.update(_ctx(true, 1), 0.0), "defeat", "a decided match even from the title")


func test_every_state_has_no_track_and_play_makes_no_player(t) -> void:
	var m = Music.new()
	var host := Node.new()
	for state in Music.STATES:
		t.eq(m.track_for(state), "", "no track yet for " + state)
		t.eq(m.play(m.track_for(state), host), null, "play is a no-op on an empty track (" + state + ")")
	t.eq(m.track_for("nonsense"), "", "an unknown state has none either")
	t.eq(host.get_child_count(), 0, "no player was created")
	host.free()


func test_the_game_feeds_the_director_on_kestrel_and_makes_no_player(t) -> void:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json")))
	t.ok(scene.world_art_on, "the Kestrel scene")
	t.eq(scene.music_state, "menu", "the title before any update")
	scene.mission_deployed = false
	scene._update_music()
	t.eq(scene.music_state, "menu", "on the title")
	scene.mission_deployed = true
	scene.time_alive = 10.0
	scene._update_music()
	t.eq(scene.music_state, "calm", "deployed, no shot seen")
	scene.music_shot_at = 9.0
	scene._update_music()
	t.eq(scene.music_state, "combat", "a seen shot 1 s ago")
	scene.time_alive = 16.0
	scene._update_music()
	t.eq(scene.music_state, "combat", "7 s quiet")
	scene.time_alive = 17.5
	scene._update_music()
	t.eq(scene.music_state, "calm", "8.5 s quiet")
	scene.bridge_winner = 1
	scene._update_music()
	t.eq(scene.music_state, "defeat", "the aliens won")
	t.eq(scene.find_children("*", "AudioStreamPlayer", true, false).size(), 0, "no player anywhere: every track is empty")
	t.eq(scene.music_player, null, "and the game holds none")
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	var at := src.find("func _update_audio() -> void:")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	t.ok(body.contains("_update_music()"), "the music hook rides the Kestrel-only per-frame audio update")
	scene.free()
