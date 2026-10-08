extends RefCounted
## Kestrel sound (plan 2026-10-06-kestrel-next-level, Task 5): the pure AudioDirector through plain calls (no engine
## audio: nothing here makes a player except the pool test, which first proves the driver is the Dummy one), the
## generated streams Task 4 committed, the bus layout and the AudioPool's player set.
const Director = preload("res://scripts/audio/audio_director.gd")
const Pool = preload("res://scripts/audio/audio_pool.gd")
const MANIFEST := "res://assets/audio/sfx/sfx_manifest.json"
## A view on the ground: x 10..30, z 5..17, centre (20, 11), half width 10 (about the default zoom's).
const VIEW := Rect2(10, 5, 20, 12)
const MID := Vector3(20, 0, 11)


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


func _director() -> RefCounted:
	var d = Director.new()
	d.configure(_manifest())
	d.set_view(VIEW)
	return d


func _body(src: String, header: String) -> String:
	var at := src.find(header)
	if at < 0:
		return ""
	var lines := src.substr(at).split("\n")
	var keep := 1
	for i in range(1, lines.size()):
		if lines[i].begins_with("\t"):
			keep = i + 1
		elif lines[i] != "":
			break
	return "\n".join(lines.slice(0, keep))


func _base(id: String) -> float:
	for s in _manifest()["sounds"]:
		if s["id"] == id:
			return float(s["base_volume_db"])
	return INF


# ------------------------------------------------------------------ streams, imports, buses

func test_every_manifest_id_loads_as_a_stream(t) -> void:
	var m := _manifest()
	t.eq(m["sounds"].size(), 26, "the twenty-six generated sounds (kestrel-depth Task 6 added eight event cues)")
	t.eq(Pool.load_manifest(), m, "the pool reads the same manifest")
	var d := _director()
	for s in m["sounds"]:
		var stream = load(String(m["base_path"]) + String(s["file"]))
		t.ok(stream is AudioStreamWAV, "%s loads as an AudioStreamWAV" % s["id"])
		t.ok(d.has_sound(String(s["id"])), "the director knows %s" % s["id"])
		if not stream is AudioStreamWAV:
			continue
		var wav := stream as AudioStreamWAV
		t.near(wav.get_length(), float(s["duration_s"]), 0.01, "%s length" % s["id"])
		if bool(s["loop"]):
			t.eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops forward" % s["id"])
			t.eq(wav.loop_begin, 0, "%s from its first sample" % s["id"])
			t.eq(wav.loop_end, roundi(float(s["duration_s"]) * 44100.0), "%s to its last" % s["id"])
		else:
			t.eq(wav.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s plays once" % s["id"])
	t.ok(not d.has_sound("nope"), "and nothing else")


## Task 4 review: QOA is block based and could smear a loop's seam, so the three loops import lossless.
func test_the_loops_import_lossless_and_the_one_shots_stay_compressed(t) -> void:
	for s in _manifest()["sounds"]:
		var file := "res://assets/audio/sfx/%s.import" % s["file"]
		var text := FileAccess.get_file_as_string(file)
		var wav := load("res://assets/audio/sfx/" + String(s["file"])) as AudioStreamWAV
		if bool(s["loop"]):
			t.ok(text.contains("\ncompress/mode=0\n") or text.ends_with("\ncompress/mode=0"), "%s imports with compress/mode=0" % s["id"])
			t.eq(wav.format, AudioStreamWAV.FORMAT_16_BITS, "%s is 16-bit PCM in memory, not QOA" % s["id"])
		else:
			t.ok(text.contains("compress/mode=2"), "%s keeps the QOA import" % s["id"])


func test_the_bus_layout_has_the_five_buses_and_the_pan_buses(t) -> void:
	for bus in ["Master", "SFX", "UI", "Ambient", "Music"]:
		t.ok(AudioServer.get_bus_index(bus) >= 0, "bus %s" % bus)
	for bus in ["UI", "Ambient", "Music", "SFX"]:
		t.eq(String(AudioServer.get_bus_send(AudioServer.get_bus_index(bus))), "Master", "%s sends to Master" % bus)
	t.near(AudioServer.get_bus_volume_db(0), 0.0, 1e-6, "Master at 0 dB (Survival's players use it unchanged)")
	t.eq(AudioServer.get_bus_effect_count(0), 0, "and Master has no effect")
	for step in Director.PAN_BUSES:
		var name: String = Director.PAN_BUSES[step]
		var idx := AudioServer.get_bus_index(name)
		t.ok(idx >= 0, "pan bus %s" % name)
		if step == 0:
			t.eq(name, "SFX", "the centre is the SFX bus itself")
			continue
		t.eq(String(AudioServer.get_bus_send(idx)), "SFX", "%s sends to SFX" % name)
		var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
		t.ok(fx != null, "%s pans" % name)
		if fx != null:
			t.near(fx.pan, float(step) * Director.PAN_STEP, 1e-6, "%s pan value" % name)


## The only test that makes engine players: the runner is --headless, whose audio driver is Dummy; it says so first. The
## runner cannot put nodes in the tree mid-_initialize, and a pool outside the tree never starts a player, so this checks
## how each player is set up for a start, the pause, the delay queue and the duck, not playback itself.
func test_the_pool_owns_sixteen_sfx_players_a_ui_player_and_the_loops(t) -> void:
	t.eq(AudioServer.get_driver_name(), "Dummy", "the suite only ever runs on the Dummy audio driver")
	if AudioServer.get_driver_name() != "Dummy":
		return
	var pool = Pool.new()
	pool.setup(_manifest())
	var players := pool.find_children("*", "AudioStreamPlayer", false, false)
	t.eq(players.size(), Pool.SFX_VOICES + 1 + Director.LOOP_IDS.size(), "16 SFX + 1 UI + one per loop")
	t.eq(Pool.SFX_VOICES, 16, "sixteen SFX voices")
	t.eq(pool.streams.size(), _manifest()["sounds"].size(), "every stream preloaded at setup")
	for id in Director.LOOP_IDS:
		t.eq((pool.get_node(String(id).to_pascal_case()) as AudioStreamPlayer).stream, pool.streams[id], "%s has its own player" % id)
	var d := _director()
	var r: Dictionary = d.request("cannon", Vector3(28, 0, 11), 1.0)
	pool.play(r)
	t.eq(pool.plays, 1, "one start")
	var set_up: Array = players.filter(func(p): return p.stream == pool.streams["cannon"])
	t.eq(set_up.size(), 1, "one player holds the cannon")
	if set_up.size() == 1:
		var p: AudioStreamPlayer = set_up[0]
		t.ok(String(p.name).begins_with("Sfx"), "an SFX player")
		t.eq(String(p.bus), String(r["bus"]), "on the director's bus (%s)" % r["bus"])
		t.near(p.volume_db, float(r["volume_db"]), 1e-4, "at its volume")
		t.near(p.pitch_scale, float(r["pitch"]), 1e-6, "and pitch")
	pool.play(d.request("ui_click", Vector3.INF, 1.0))
	var ui_player := pool.get_node("Ui") as AudioStreamPlayer
	t.eq(ui_player.stream, pool.streams["ui_click"], "a click goes to the UI player")
	t.eq(String(ui_player.bus), "UI", "on the UI bus")
	pool.play({"play": false, "id": "rifle"})
	t.eq(pool.plays, 2, "a refusal starts nothing")
	pool.set_paused(true)
	t.ok(pool.paused, "the pool pauses")
	# stream_paused only sticks on a live playback (none outside the tree), so the hold is read from the source
	var hold := _body((load("res://scripts/audio/audio_pool.gd") as GDScript).source_code, "func set_paused(on: bool) -> void:")
	t.ok(hold.contains("for p in _sfx:\n\t\tp.stream_paused = on"), "holding every SFX player")
	t.ok(hold.contains("(_loops[id] as AudioStreamPlayer).stream_paused = on"), "and every loop player")
	t.ok(not hold.contains("_ui") and not hold.contains("_ambient"), "but not the HUD's clicks or the ambience")
	pool.set_paused(false)
	t.ok(not pool.paused, "and resumes")
	pool.play(d.request("rifle", MID, 2.0), 0.3)
	t.eq(pool.pending_count(), 1, "a delayed shot waits on the pool's clock")
	pool.set_paused(true)
	pool.advance(1.0)
	t.eq(pool.pending_count(), 1, "which stands still while paused")
	pool.set_paused(false)
	pool.advance(0.31)
	t.eq(pool.pending_count(), 0, "and starts once the delay ran")
	t.eq(pool.plays, 3, "as one start")
	pool.set_duck(-9.0)
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambient")), -9.0, 1e-4, "the duck lowers Ambient")
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -9.0, 1e-4, "and Music")
	pool.free()
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambient")), 0.0, 1e-4, "a freed pool restores Ambient")
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), 0.0, 1e-4, "and Music")


# ------------------------------------------------------------------ director: cooldowns and caps

func test_a_cooldown_blocks_a_repeat_inside_its_window(t) -> void:
	var d := _director()
	var cd: float = Director.COOLDOWN["cannon"]
	t.ok(d.request("cannon", MID, 1.0)["play"], "the first cannon plays")
	var again: Dictionary = d.request("cannon", MID, 1.0 + cd * 0.5)
	t.ok(not again["play"], "a second inside %.2f s does not" % cd)
	t.eq(again["reason"], "cooldown", "because of the cooldown")
	t.ok(d.request("rifle", MID, 1.0 + cd * 0.5)["play"], "another id is not held by it")
	t.ok(d.request("cannon", MID, 1.0 + cd + 0.001)["play"], "after the window it plays again")
	for id in Director.COOLDOWN:
		t.ok(float(Director.COOLDOWN[id]) > 0.0, "%s has a cooldown" % id)
	t.ok(float(Director.COOLDOWN["alert"]) >= 2.0, "the under-attack alert repeats at most every 2 s")


func test_thirty_shots_in_a_second_stay_inside_the_caps(t) -> void:
	var d := _director()
	var ids := ["rifle", "plasma_bolt", "cannon"]
	var plays := 0
	for i in 30:
		var now := 5.0 + float(i) / 30.0
		var r: Dictionary = d.request(ids[i % 3], Vector3(12 + i % 15, 0, 9), now)
		if r["play"]:
			plays += 1
		t.ok(d.active_voices("weapon", now) <= int(Director.CATEGORY_VOICES["weapon"]), "never more weapon voices than the cap (t %.2f)" % now)
		for id in ids:
			t.ok(d.active_voices(id, now) <= int(Director.ID_VOICES[id]), "nor of one id")
	t.ok(plays <= int(Director.CATEGORY_RATE["weapon"]), "30 requests in a second start at most %d (%d)" % [Director.CATEGORY_RATE["weapon"], plays])
	t.ok(plays <= int(Director.CATEGORY_VOICES["weapon"]) + 2, "about the voice cap")
	t.ok(plays >= 4, "but a fight is still heard (%d)" % plays)


func test_the_caps_fit_the_pool_and_low_priority_leaves_room_for_alerts(t) -> void:
	var sum := 0
	for c in Director.CATEGORY_VOICES:
		if c != "ui":
			sum += int(Director.CATEGORY_VOICES[c])
	t.ok(sum <= Pool.SFX_VOICES, "the category caps (%d) fit the 16 SFX players" % sum)
	t.ok(Director.PRIORITY["alert"] > Director.PRIORITY["impact"] and Director.PRIORITY["impact"] > Director.PRIORITY["weapon"], "alert over impact over weapon")
	var d := _director()
	var now := 3.0
	# a saturated fight: requests every 10 ms for a second
	for i in 100:
		var id: String = ["explosion_small", "rifle", "explosion_large", "plasma_bolt", "cannon", "collapse"][i % 6]
		d.request(id, Vector3(11 + i % 18, 0, 6 + i % 10), now + i * 0.01)
		t.ok(d.active_voices("", now + i * 0.01) <= int(Director.ROOM[2]), "weapons and impacts stay under the impact room")
	var r: Dictionary = d.request("alert", Vector3.INF, now + 1.0)
	t.ok(r["play"], "an alert still gets a voice in a saturated fight")


# ------------------------------------------------------------------ director: place, pan, attenuation

func test_pan_follows_screen_x(t) -> void:
	var d := _director()
	var left: Dictionary = d.request("rifle", Vector3(15, 0, 11), 1.0)
	var right: Dictionary = d.request("plasma_bolt", Vector3(25, 0, 11), 1.0)
	var centre: Dictionary = d.request("cannon", MID, 1.0)
	t.ok(left["pan"] < 0.0, "left of centre pans left (%.2f)" % left["pan"])
	t.ok(right["pan"] > 0.0, "right of centre pans right (%.2f)" % right["pan"])
	t.near(centre["pan"], 0.0, 1e-6, "the centre is centred")
	t.near(left["pan"], -0.5 * Director.PAN_MAX, 1e-5, "a quarter view left is half the pan width")
	t.near(right["pan"], 0.5 * Director.PAN_MAX, 1e-5, "and right")
	t.eq(left["bus"], "SFX_L1", "on the near-left pan bus")
	t.eq(right["bus"], "SFX_R1", "near right")
	t.eq(centre["bus"], "SFX", "centre on SFX")
	var edge: Dictionary = d.request("explosion_small", Vector3(30, 0, 11), 1.0)
	t.near(edge["pan"], Director.PAN_MAX, 1e-5, "the right edge is the full pan width")
	t.eq(edge["bus"], "SFX_R2", "on the far-right bus")
	var past: Dictionary = d.request("explosion_large", Vector3(31, 0, 11), 1.0)
	t.near(past["pan"], Director.PAN_MAX, 1e-5, "past the edge stays at the full width")
	t.ok(absf(float(d.request("collapse", Vector3(20, 0, 16), 1.0)["pan"])) < 1e-6, "z alone does not pan")


func test_an_off_screen_sound_is_attenuated_then_skipped(t) -> void:
	var d := _director()
	var inside: Dictionary = d.request("cannon", MID, 1.0)
	t.near(inside["volume_db"], _base("cannon") + d.zoom_db(), 1e-5, "the centre at the base volume (and the zoom trim)")
	var near_edge: Dictionary = d.request("rifle", Vector3(29.9, 0, 11), 1.0)
	t.ok(float(near_edge["volume_db"]) >= _base("rifle") + d.zoom_db() + Director.EDGE_DB - 0.01, "inside the view at most EDGE_DB quieter")
	var just_out: Dictionary = d.request("plasma_bolt", Vector3(30.5, 0, 11), 1.0)
	t.ok(just_out["play"], "just past the edge (inside the margin) still plays")
	t.ok(float(just_out["volume_db"]) <= _base("plasma_bolt") - 6.0, "but at least 6 dB down (%.1f)" % just_out["volume_db"])
	var far: Dictionary = d.request("explosion_small", Vector3(30 + Director.VIEW_MARGIN + 0.5, 0, 11), 1.0)
	t.ok(not far["play"], "beyond the margin: silent")
	t.eq(far["reason"], "offscreen", "skipped as off-screen")
	t.ok(not d.request("collapse", Vector3(20, 0, -10), 1.0)["play"], "off the top too")
	t.ok(d.request("explosion_large", Vector3(-100, 0, -100), 1.0)["reason"] == "offscreen", "a far fight is never heard")
	var blind = Director.new()
	blind.configure(_manifest())
	t.ok(not blind.request("cannon", MID, 1.0)["play"], "with no view yet a positional sound is skipped")
	t.ok(blind.request("alert", Vector3.INF, 1.0)["play"], "a global cue still plays")


func test_global_cues_are_centred(t) -> void:
	var d := _director()
	var alert: Dictionary = d.request("alert", Vector3.INF, 1.0)
	t.ok(alert["play"] and alert["pan"] == 0.0 and alert["bus"] == "SFX", "an alert: centred on SFX")
	var click: Dictionary = d.request("ui_click", Vector3.INF, 1.0)
	t.eq(click["bus"], "UI", "a click on the UI bus")
	t.near(click["volume_db"], _base("ui_click"), 1e-6, "at its base volume")
	t.eq(d.request("ack_vehicle", Vector3.INF, 1.0)["bus"], "SFX", "an acknowledgement on SFX")
	t.eq(d.request("rotor_loop", MID, 1.0)["reason"], "loop", "a loop is not a one-shot request")
	t.eq(d.request("nope", MID, 1.0)["reason"], "unknown", "an unknown id plays nothing")


func test_zooming_out_lowers_world_sounds_a_little(t) -> void:
	var d := _director()
	var near: float = d.request("cannon", MID, 1.0)["volume_db"]
	d.set_view(Rect2(0, 0, 40, 24))
	var far: float = d.request("cannon", Vector3(20, 0, 12), 3.0)["volume_db"]
	t.ok(far < near and far >= near - Director.ZOOM_DB_MAX - 1e-4, "farther out is quieter, by at most %.0f dB (%.1f vs %.1f)" % [Director.ZOOM_DB_MAX, far, near])
	t.near(d.request("alert", Vector3.INF, 3.0)["volume_db"], _base("alert"), 1e-6, "global cues ignore the zoom")


# ------------------------------------------------------------------ director: ducking, pause, loops, determinism

func test_ambient_ducks_under_a_large_explosion_and_recovers(t) -> void:
	var d := _director()
	t.near(d.duck_db(1.0), 0.0, 1e-6, "no duck at rest")
	d.request("rifle", MID, 1.0)
	t.near(d.duck_db(1.05), 0.0, 1e-6, "a rifle does not duck")
	t.ok(d.request("explosion_large", MID, 2.0)["play"], "a large explosion")
	t.near(d.duck_db(2.1), Director.DUCK_DB, 1e-6, "ducks Ambient to DUCK_DB")
	var hold_end: float = 2.0 + 2.5  # its length at pitch 1.0
	var before: float = d.duck_db(hold_end + 0.1)
	var later: float = d.duck_db(hold_end + Director.DUCK_RECOVER * 0.7)
	t.ok(before < later and later < 0.0, "recovering gradually (%.2f then %.2f)" % [before, later])
	t.near(d.duck_db(hold_end + Director.DUCK_RECOVER + 0.6), 0.0, 1e-6, "and back to 0 dB")
	t.ok(d.request("alert", Vector3.INF, 20.0)["play"], "an alert")
	t.near(d.duck_db(20.2), Director.DUCK_DB, 1e-6, "ducks too")


func test_a_paused_sim_requests_nothing(t) -> void:
	var d := _director()
	d.set_paused(true)
	for id in ["rifle", "cannon", "explosion_large", "collapse", "select", "ack_infantry", "alert", "build_complete", "wave_inbound"]:
		var r: Dictionary = d.request(id, MID if id in ["rifle", "cannon", "explosion_large", "collapse"] else Vector3.INF, 1.0)
		t.ok(not r["play"] and r["reason"] == "paused", "%s is silent while paused" % id)
	t.ok(d.request("ui_click", Vector3.INF, 1.0)["play"], "the pause menu's own clicks still sound")
	var loops: Dictionary = d.loops({"tread_loop": [MID], "rotor_loop": [MID], "foot_loop": [MID]})
	for id in Director.LOOP_IDS:
		t.ok(not loops[id]["play"], "%s stops while paused" % id)
	d.set_paused(false)
	t.ok(d.request("cannon", MID, 1.0)["play"], "after the pause it plays: the refused requests used no cooldown")
	t.ok(d.loops({"tread_loop": [MID]})["tread_loop"]["play"], "and the loops come back")


func test_loops_follow_the_visible_moving_units(t) -> void:
	var d := _director()
	var none: Dictionary = d.loops({})
	t.eq(none.keys().size(), 3, "an answer for each loop")
	for id in Director.LOOP_IDS:
		t.ok(not none[id]["play"], "%s off with nothing moving" % id)
	var one: Dictionary = d.loops({"tread_loop": [MID]})
	t.ok(one["tread_loop"]["play"] and not one["rotor_loop"]["play"] and not one["foot_loop"]["play"], "one moving tank: only the treads")
	t.near(one["tread_loop"]["volume_db"], _base("tread_loop") + d.zoom_db(), 1e-5, "at the base volume")
	var four: Dictionary = d.loops({"tread_loop": [MID, MID, MID, MID]})
	t.near(four["tread_loop"]["volume_db"], float(one["tread_loop"]["volume_db"]) + 2.0 * Director.LOOP_DB_PER_DOUBLING, 1e-4, "four are louder by two doublings")
	var crowd := []
	for i in 50:
		crowd.append(Vector3(12 + i % 16, 0, 8))
	var many: Dictionary = d.loops({"foot_loop": crowd})
	var capped: float = _base("foot_loop") + d.zoom_db() + Director.LOOP_DB_PER_DOUBLING * log(float(Director.LOOP_COUNT_CAP)) / log(2.0)
	t.near(many["foot_loop"]["volume_db"], capped, 1e-4, "fifty are capped at %d" % Director.LOOP_COUNT_CAP)
	t.eq(many["foot_loop"]["count"], 50, "though all are counted")
	var hidden: Dictionary = d.loops({"rotor_loop": [Vector3(31, 0, 11), Vector3(-50, 0, 0)]})
	t.ok(not hidden["rotor_loop"]["play"], "units moving off screen are not heard")
	var lefty: Dictionary = d.loops({"rotor_loop": [Vector3(12, 0, 11), Vector3(14, 0, 11), Vector3(31, 0, 11)]})
	t.ok(lefty["rotor_loop"]["pan"] < -0.3 and lefty["rotor_loop"]["count"] == 2, "the bed pans toward the visible movers")


func test_the_director_is_deterministic(t) -> void:
	var script := []
	for i in 80:
		var id: String = ["rifle", "cannon", "plasma_bolt", "explosion_small", "alert", "ack_air", "ui_hover", "explosion_large"][(i * 7) % 8]
		script.append([id, Vector3(8 + (i * 13) % 26, 0, 4 + (i * 5) % 15) if i % 4 else Vector3.INF, 1.0 + i * 0.037])
	var runs := []
	for k in 2:
		var d := _director()
		var out := []
		for step in script:
			out.append(d.request(step[0], step[1], step[2]))
			out.append(d.duck_db(float(step[2]) + 0.01))
		out.append(d.loops({"tread_loop": [MID, Vector3(12, 0, 6)], "foot_loop": [Vector3(29, 0, 16)]}))
		runs.append(out)
	t.eq(runs[0], runs[1], "the same calls give the same answers")
	var d2 := _director()
	var pitches := {}
	for i in 7:
		pitches[d2.request("rifle", MID, 10.0 + i)["pitch"]] = true
	t.ok(pitches.size() >= 5, "a rifle's repeats vary in pitch (%d values)" % pitches.size())
	for p in pitches:
		t.ok(p >= 0.94 and p <= 1.06, "slightly (%.3f)" % p)
	t.near(d2.request("alert", Vector3.INF, 30.0)["pitch"], 1.0, 1e-9, "alerts never vary")


func test_event_mappings(t) -> void:
	t.eq(Director.weapon_for("Infantry", 0), "rifle", "human infantry fire rifles")
	t.eq(Director.weapon_for("Helicopter", 0), "rifle", "the gunship's burst")
	t.eq(Director.weapon_for("GunTurret", 0), "rifle", "a gun turret")
	for k in ["Tank", "AntiArmor", "Capital"]:
		t.eq(Director.weapon_for(k, 0), "cannon", "a human %s fires a shell" % k)
	for k in ["Infantry", "Tank", "Helicopter", "GunTurret", ""]:
		t.eq(Director.weapon_for(k, 1), "plasma_bolt", "an alien %s fires plasma" % k)
	t.eq(Director.ack_for("Infantry"), "ack_infantry", "infantry ack")
	t.eq(Director.ack_for("AntiArmor"), "ack_infantry", "anti-armour squads are infantry")
	for k in ["Tank", "Harvester", "Capital"]:
		t.eq(Director.ack_for(k), "ack_vehicle", "%s is a vehicle" % k)
	t.eq(Director.ack_for("Helicopter"), "ack_air", "the gunship is air")
	t.eq(Director.loop_for("Helicopter"), "rotor_loop", "rotor")
	for k in ["Tank", "Harvester", "Capital"]:
		t.eq(Director.loop_for(k), "tread_loop", "%s treads" % k)
	for k in ["Infantry", "AntiArmor"]:
		t.eq(Director.loop_for(k), "foot_loop", "%s walks" % k)
	t.eq(Director.loop_for("Barracks"), "", "a building never moves")
	t.eq(Director.death_sound("Barracks", "building"), "collapse", "a building collapses")
	t.eq(Director.death_sound("Infantry", "unit"), "explosion_small", "infantry: a small blast")
	t.eq(Director.death_sound("AntiArmor", "unit"), "explosion_small", "anti-armour: small")
	for k in ["Tank", "Harvester", "Helicopter", "Capital"]:
		t.eq(Director.death_sound(k, "unit"), "explosion_large", "%s: a large blast" % k)
	t.eq(Director.hit_sound(0), "", "an infantry-weight hit adds nothing to its shot")
	t.eq(Director.hit_sound(1), "", "nor a gun's")
	t.eq(Director.hit_sound(2), "explosion_small", "a tank-weight hit bursts")
	t.eq(Director.hit_sound(3), "explosion_small", "a heavy one too")


func test_the_director_is_pure(t) -> void:
	var src := (load("res://scripts/audio/audio_director.gd") as GDScript).source_code
	t.ok(src.begins_with("extends RefCounted"), "a RefCounted, never a node")
	for banned in ["AudioServer", "AudioStreamPlayer", "Node", "load(", "FileAccess", "get_tree", "Time.", "randf", "randi", "OS."]:
		t.ok(not src.contains(banned), "no %s in the director" % banned)
	var pool := (load("res://scripts/audio/audio_pool.gd") as GDScript).source_code
	t.ok(not pool.contains("AudioStreamGenerator") and not pool.contains("push_frame"), "the pool plays files, never a generator loop")
	t.ok(not pool.contains("AudioStreamPlayer3D") and not pool.contains("AudioStreamPlayer2D"), "plain players: the director pans")
