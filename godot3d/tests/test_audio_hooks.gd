extends RefCounted
## Kestrel sound hooks (plan 2026-10-06-kestrel-next-level, Task 5): each game event asks the director once, through a
## recording stub put where the AudioDirector lives (no engine audio: the scenes never enter the tree, so no player is
## made). Re-delivering a snapshot asks nothing again. Survival never reaches the director and keeps its tones.
const MainScene = preload("res://main.tscn")
const Director = preload("res://scripts/audio/audio_director.gd")
const GameUI = preload("res://scripts/ui/game_ui.gd")
const RUNTIME := "user://audio_hooks_runtime"


class Recorder extends RefCounted:
	var calls: Array = []
	var loop_calls: Array = []
	var paused := false

	func request(id: String, at: Vector3, now: float) -> Dictionary:
		calls.append({"id": id, "at": at, "now": now})
		return {"play": false, "id": id, "reason": "recorded"}

	func set_view(_rect: Rect2) -> void:
		pass

	func set_paused(on: bool) -> void:
		paused = on

	func loops(moving: Dictionary) -> Dictionary:
		loop_calls.append(moving)
		return {}

	func duck_db(_now: float) -> float:
		return 0.0

	func ids() -> Array:
		return calls.map(func(c): return c["id"])


class ClickStub extends "res://tests/stub_game.gd":
	var clicks := 0

	func hud_clicked() -> void:
		clicks += 1


const UI_STUB := """extends Node
var session_log := Log.new()
var hud := Control.new()
var alerts := 0
var allow_alert := true
func set_tab(_tab: String) -> void:
	pass
func notify(_title: String, _body: String, _color: Color) -> void:
	pass
func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
	alerts += 1
	return allow_alert
class Log:
	func unit_added(_kind: String, _team: int, _category: String) -> void:
		pass
	func unit_removed(_kind: String, _team: int, _category: String) -> void:
		pass
"""


func _ui_stub() -> Node:
	var s := GDScript.new()
	s.source_code = UI_STUB
	s.reload()
	var n := Node.new()
	n.set_script(s)
	return n


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	scene.world_fx.set_view(scene._hex_world(12, 12), Vector2(12, 10))
	scene.ui = _ui_stub()
	return scene


func _survival_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var snap := _snap()
	snap["ground"] = "g".repeat(44 * 26)
	scene._sync_ground(snap)
	scene.ui = _ui_stub()
	return scene


func _done(scene: Node3D) -> void:
	if scene.ui != null:
		scene.ui.hud.free()
		scene.ui.free()
	scene.free()


func _record(scene: Node3D) -> Recorder:
	var r := Recorder.new()
	scene.audio = r
	return r


func _unit(scene, id: int, kind: String, owner: int, tile: Vector2i, hp := 100) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * hp, "max_hp_bits": 65536 * 100}


func _building(scene, id: int, kind: String, owner: int, tile: Vector2i, construction := 0, hp := 100) -> Dictionary:
	var e := _unit(scene, id, kind, owner, tile, hp)
	e["category"] = "building"
	e["construction"] = construction
	e["construction_total"] = 100
	return e


## A first poll (nothing announced), then the bridge is initialised like the live game's second poll.
func _place(scene, entities: Array) -> void:
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)


func _src() -> String:
	return (load("res://scripts/earthfront_3d.gd") as GDScript).source_code


func _func_body(src: String, header: String) -> String:
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


# ------------------------------------------------------------------ wiring

func test_kestrel_gets_a_director_and_survival_none(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.audio != null and scene.audio.get_script() == Director, "Kestrel builds the AudioDirector with its effects")
	t.ok(scene.audio.has_sound("cannon"), "configured from the manifest")
	t.eq(scene.audio_pool, null, "outside the tree (a test) no player pool is made")
	t.eq(scene.find_children("*", "AudioStreamPlayer", true, false).size(), 0, "and no player at all")
	_done(scene)
	var survival := _survival_scene()
	t.ok(not survival.world_art_on, "Survival")
	t.eq(survival.audio, null, "has no director")
	t.eq(survival.audio_pool, null, "and no pool")
	_done(survival)


func test_survival_never_calls_the_director(t) -> void:
	var survival := _survival_scene()
	var rec := _record(survival)  # even a director put there by mistake is never asked
	survival._sfx("cannon", Vector3(10, 0, 10))
	survival.hud_clicked()
	survival._create_unit(0, survival._hex_world(12, 12), 1)
	var tank: Node3D = survival.units.back()
	survival._set_selection([tank])
	survival._order_ack()
	survival._audio_site(5, 0, 0)
	survival._update_audio()
	t.eq(rec.calls.size(), 0, "no request from any hook")
	t.eq(rec.loop_calls.size(), 0, "no loop update")
	var src := _src()
	var process := _func_body(src, "func _process(delta: float) -> void:")
	t.ok(process.contains("if _audio_on():\n\t\t_update_audio()"), "the per-frame audio update runs only with Kestrel sound on")
	t.ok(_func_body(src, "func _audio_on() -> bool:").contains("return audio != null and world_art_on"), "which needs the director and world art")
	_done(survival)


## Survival's tones stay exactly as they were: the five shared cues pass the legacy tone's own arguments through _cue,
## which plays _play_tone unchanged whenever Kestrel sound is off; the two Survival-only effects still call it directly.
func test_survival_keeps_every_tone_with_its_arguments(t) -> void:
	var src := _src()
	t.eq(src.count("_play_tone("), 4, "_play_tone: its definition, _cue's fallback, _impact_effect and _death_effect")
	var cue := _func_body(src, "func _cue(id: String, frequency: float, duration: float, volume: float, sweep := 0.0) -> void:")
	t.ok(cue.contains("\tif _audio_on():\n\t\t_sfx(id)\n\telse:\n\t\t_play_tone(frequency, duration, volume, sweep)"), "_cue: Kestrel's sound or the legacy tone")
	t.ok(_func_body(src, "func _impact_effect(position: Vector3, human_hit: bool) -> void:").contains("_play_tone(92.0, 0.09, 0.12, -25.0)"), "the Survival hit thump")
	t.ok(_func_body(src, "func _death_effect(position: Vector3, owner: int) -> void:").contains("_play_tone(74.0, 0.16, 0.18, -34.0)"), "the Survival death thud")
	for call in [
		"_cue(\"wave_inbound\", 165.0, 0.28, 0.17, -45.0)",
		"_cue(\"alert\", 210.0, 0.18, 0.14, -30.0)",
		"_cue(AudioDirector.ack_for(kind_name), 620.0, 0.1, 0.1, 90.0)",
		"_cue(\"build_complete\", 430.0, 0.22, 0.14, 520.0)",
		"_cue(\"build_complete\" if winner == HUMAN else \"wave_inbound\", 360.0 if winner == HUMAN else 120.0, 0.34, 0.18, 420.0 if winner == HUMAN else -50.0)",
		"_cue(\"select\", 520.0, 0.13, 0.16, 180.0)",
	]:
		t.eq(src.count(call), 1, "the cue keeps its legacy tone: %s" % call)


# ------------------------------------------------------------------ one request per event

func test_unit_ready_acknowledges_once_by_class(t) -> void:
	var scene := _kestrel_scene()
	var cc := _building(scene, 1, "CommandCenter", 0, Vector2i(8, 9))
	_place(scene, [cc])
	scene.bridge_initialized = true
	var rec := _record(scene)
	var inf := _unit(scene, 500, "Infantry", 0, Vector2i(10, 10))
	scene._sync_bridge_entities([cc, inf])
	t.eq(rec.ids(), ["ack_infantry"], "a new rifle squad reports once")
	scene._sync_bridge_entities([cc, inf])
	t.eq(rec.ids(), ["ack_infantry"], "the same snapshot again asks nothing")
	var alien := _unit(scene, 501, "Tank", 1, Vector2i(30, 12))
	scene._sync_bridge_entities([cc, inf, alien])
	t.eq(rec.calls.size(), 1, "an alien unit appearing is not 'ready'")
	var heli := _unit(scene, 502, "Helicopter", 0, Vector2i(11, 10))
	var tank := _unit(scene, 503, "Tank", 0, Vector2i(12, 10))
	scene._sync_bridge_entities([cc, inf, alien, heli, tank])
	t.eq(rec.ids(), ["ack_infantry", "ack_air", "ack_vehicle"], "a gunship and a tank, each by its class")
	t.ok(rec.calls.all(func(c): return c["at"] == Vector3.INF), "announcements are global")
	_done(scene)


func test_build_complete_sounds_once_when_a_site_finishes(t) -> void:
	var scene := _kestrel_scene()
	var site := _building(scene, 600, "Barracks", 0, Vector2i(10, 10), 50)
	var alien_site := _building(scene, 601, "Barracks", 1, Vector2i(30, 10), 50)
	_place(scene, [site, alien_site])
	scene.bridge_initialized = true
	var rec := _record(scene)
	site["construction"] = 20
	scene._sync_bridge_entities([site, alien_site])
	t.eq(rec.calls.size(), 0, "progress is silent")
	site["construction"] = 0
	alien_site["construction"] = 0
	scene._sync_bridge_entities([site, alien_site])
	t.eq(rec.ids(), ["build_complete"], "the human site finishing sounds once (the alien one never)")
	scene._sync_bridge_entities([site, alien_site])
	t.eq(rec.calls.size(), 1, "re-delivered: nothing")
	var done_already := _building(scene, 602, "PowerPlant", 0, Vector2i(12, 8), 0)
	scene._sync_bridge_entities([site, alien_site, done_already])
	t.eq(rec.calls.size(), 1, "a building first seen complete is not a completion")
	_done(scene)


func test_a_hit_asks_once_and_a_structure_hit_raises_one_alert(t) -> void:
	var scene := _kestrel_scene()
	var tank := _unit(scene, 700, "Tank", 0, Vector2i(12, 12))
	var inf := _unit(scene, 702, "Infantry", 0, Vector2i(13, 12))
	var barracks := _building(scene, 701, "Barracks", 0, Vector2i(10, 10))
	_place(scene, [tank, inf, barracks])
	scene.bridge_initialized = true
	var rec := _record(scene)
	tank["hp_bits"] = 65536 * 80
	scene._sync_bridge_entities([tank, inf, barracks])
	t.eq(rec.ids(), ["explosion_small"], "a tank-weight hit bursts once")
	t.ok((rec.calls[0]["at"] as Vector3).distance_to(scene._hex_world(12, 12)) < 0.5, "at the struck unit")
	scene._sync_bridge_entities([tank, inf, barracks])
	t.eq(rec.calls.size(), 1, "the same HP again: nothing")
	inf["hp_bits"] = 65536 * 90
	scene._sync_bridge_entities([tank, inf, barracks])
	t.eq(rec.calls.size(), 1, "a rifle-weight hit adds nothing to its shot")
	barracks["hp_bits"] = 65536 * 90
	scene._sync_bridge_entities([tank, inf, barracks])
	t.eq(rec.ids().slice(1), ["alert", "explosion_small"], "a structure hit: one alert and one hit")
	t.eq(rec.calls[1]["at"], Vector3.INF, "the alert is heard wherever the camera is")
	scene.ui.allow_alert = false  # the HUD's throttle says no
	barracks["hp_bits"] = 65536 * 80
	scene._sync_bridge_entities([tank, inf, barracks])
	t.eq(rec.ids().slice(3), ["explosion_small"], "a throttled alert stays silent; the hit still sounds")
	_done(scene)


func test_deaths_ask_once(t) -> void:
	var scene := _kestrel_scene()
	var tank := _unit(scene, 710, "Tank", 1, Vector2i(12, 12))
	var inf := _unit(scene, 711, "Infantry", 1, Vector2i(13, 12))
	var depot := _building(scene, 712, "Barracks", 1, Vector2i(10, 10))
	_place(scene, [tank, inf, depot])
	scene.bridge_initialized = true
	var rec := _record(scene)
	scene._sync_bridge_entities([inf, depot])
	t.eq(rec.ids(), ["explosion_large"], "a tank dies in a large blast")
	scene._sync_bridge_entities([inf, depot])
	t.eq(rec.calls.size(), 1, "once")
	scene._sync_bridge_entities([depot])
	scene._sync_bridge_entities([])
	t.eq(rec.ids(), ["explosion_large", "explosion_small", "collapse"], "infantry small, a building collapses")
	var far := _unit(scene, 713, "Tank", 1, Vector2i(40, 2))
	_place(scene, [far])
	scene.bridge_initialized = true
	scene.world_fx.set_view(scene._hex_world(5, 20), Vector2(3, 2))
	scene._sync_bridge_entities([])
	t.eq(rec.calls.size(), 3, "a death the effects do not draw (far off screen) is not heard")
	_done(scene)


func test_shots_ask_once_per_drawn_shot_by_attacker(t) -> void:
	var scene := _kestrel_scene()
	var tank := _unit(scene, 720, "Tank", 0, Vector2i(10, 12))
	var alien := _unit(scene, 721, "Infantry", 1, Vector2i(15, 12))
	_place(scene, [tank, alien])
	scene.bridge_initialized = true
	var rec := _record(scene)
	var row := func(tick: int, a: Vector2i, b: Vector2i) -> Array:
		var ab: Vector2i = scene._world_to_sim_bits(scene._hex_world(a.x, a.y))
		var bb: Vector2i = scene._world_to_sim_bits(scene._hex_world(b.x, b.y))
		return [tick, ab.x, ab.y, bb.x, bb.y]
	var shots := [row.call(10, Vector2i(10, 12), Vector2i(15, 12)), row.call(11, Vector2i(15, 12), Vector2i(10, 12))]
	var snap := {"tick": 12, "entities": [tank, alien], "shots": shots}
	t.eq(scene._dispatch_shots(snap), 2, "two shots drawn")
	t.eq(rec.ids(), ["cannon", "plasma_bolt"], "a human tank's cannon, an alien rifle's plasma")
	t.ok((rec.calls[0]["at"] as Vector3).distance_to(scene._hex_world(10, 12)) < 0.6, "heard at the muzzle")
	t.ok(rec.calls[1]["now"] > rec.calls[0]["now"], "replayed at the shots' own rhythm (later tick, later sound)")
	t.eq(scene._dispatch_shots(snap), 0, "the same window again draws nothing")
	t.eq(rec.calls.size(), 2, "and asks nothing")
	_done(scene)


func test_selection_and_orders(t) -> void:
	var scene := _kestrel_scene()
	var tank := _unit(scene, 730, "Tank", 0, Vector2i(10, 12))
	var inf := _unit(scene, 731, "Infantry", 0, Vector2i(11, 12))
	var barracks := _building(scene, 732, "Barracks", 0, Vector2i(8, 8))
	_place(scene, [tank, inf, barracks])
	var rec := _record(scene)
	scene._set_selection([scene.bridge_nodes[731], scene.bridge_nodes[730]])
	t.eq(rec.ids(), ["select"], "a selection blips once")
	scene._set_selection([])
	t.eq(rec.calls.size(), 1, "clearing it is silent")
	scene._order_ack()
	t.eq(rec.calls.size(), 1, "no order acknowledgement with nothing selected")
	scene._set_selection([scene.bridge_nodes[730], scene.bridge_nodes[731]])
	scene._order_ack()
	t.eq(rec.ids().slice(1), ["select", "ack_vehicle"], "a move order: one acknowledgement by the first unit's class")
	scene._set_selection([scene.bridge_nodes[732]])
	scene._order_ack()
	t.eq(rec.ids().slice(3), ["select"], "a building takes no order acknowledgement")
	var input := _func_body(_src(), "func _unhandled_input(event: InputEvent) -> void:")
	var loop_at := input.find("for unit in selected_units:")
	var ack_at := input.find("_order_ack()")
	t.ok(loop_at > 0 and ack_at > loop_at, "the right-click order acknowledges after writing every unit's move")
	t.eq(input.count("_order_ack()"), 1, "once per order, not once per unit")
	_done(scene)


func test_wave_and_ten_second_cues_once(t) -> void:
	var scene := _kestrel_scene()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
	scene.runtime_directory = RUNTIME
	var rec := _record(scene)
	var snap := _snap()
	snap["shots"] = []
	var poll := func() -> void:
		var f := FileAccess.open(RUNTIME.path_join("snapshot.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(snap))
		f.close()
		scene.bridge_poll_elapsed = 0.0
		scene._poll_bridge(1.0)
	poll.call()
	t.eq(rec.calls.size(), 0, "the first poll announces nothing")
	snap["next_wave_ticks"] = 250
	poll.call()
	t.eq(rec.ids(), ["alert"], "ten seconds out: one alert")
	poll.call()
	t.eq(rec.calls.size(), 1, "re-delivered: nothing")
	snap["waves_survived"] = 1
	snap["next_wave_ticks"] = 4000
	poll.call()
	t.eq(rec.ids(), ["alert", "wave_inbound"], "the wave: once")
	poll.call()
	t.eq(rec.calls.size(), 2, "and only once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME.path_join("snapshot.json")))
	_done(scene)


func test_the_pause_reaches_the_director(t) -> void:
	var scene := _kestrel_scene()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
	scene.runtime_directory = RUNTIME
	var rec := _record(scene)
	scene.set_sim_paused(true)
	t.ok(rec.paused, "set_sim_paused (the only pause path) pauses the director")
	scene.set_sim_paused(false)
	t.ok(not rec.paused, "and resumes it")
	var body := _func_body(_src(), "func set_sim_paused(on: bool) -> void:")
	t.ok(body.contains("audio_pool.set_paused(on)"), "and holds the pool's players")
	_done(scene)


func test_loops_follow_moving_units_on_kestrel(t) -> void:
	var scene := _kestrel_scene()
	var tank := _unit(scene, 740, "Tank", 0, Vector2i(10, 12))
	var heli := _unit(scene, 741, "Helicopter", 1, Vector2i(12, 12))
	var inf := _unit(scene, 742, "Infantry", 0, Vector2i(14, 12))
	var idle := _unit(scene, 743, "Infantry", 0, Vector2i(16, 12))
	_place(scene, [tank, heli, inf, idle])
	var rec := _record(scene)
	for id in [740, 741, 742, 743]:
		var node: Node3D = scene.bridge_nodes[id]
		scene._track_motion(node, node.position)
		scene.unit_motion[node.get_instance_id()].speed = 0.0 if id == 743 else 1.0
	var moving: Dictionary = scene._audio_moving()
	t.eq(moving.keys().size(), 3, "treads, rotor and feet")
	t.eq(moving["tread_loop"], [scene.bridge_nodes[740].position], "the moving tank")
	t.eq(moving["rotor_loop"], [scene.bridge_nodes[741].position], "the gunship (either side)")
	t.eq(moving["foot_loop"], [scene.bridge_nodes[742].position], "the walking squad, not the idle one")
	scene._update_audio()
	t.eq(rec.loop_calls, [moving], "the frame update hands them to the director")
	_done(scene)


func test_hud_clicks_and_hovers(t) -> void:
	var g := ClickStub.new()
	g.viewport = t.root
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.hud.action.emit("minimap_layer", "terrain")
	t.eq(g.clicks, 1, "every HUD action is one click")
	ui.free()
	var scene := _kestrel_scene()
	var rec := _record(scene)
	scene.hud_clicked()
	t.eq(rec.ids(), ["ui_click"], "the game's click is the ui_click sound")
	var button := Button.new()
	button.size = Vector2(40, 20)
	scene.ui.hud.add_child(button)
	scene._hover_control(button)
	t.eq(rec.ids().slice(1), ["ui_hover"], "hovering a HUD button ticks")
	scene._hover_control(button)
	t.eq(rec.calls.size(), 2, "staying on it does not")
	var rebuilt := Button.new()
	rebuilt.size = Vector2(40, 20)
	scene.ui.hud.add_child(rebuilt)
	scene._hover_control(rebuilt)
	t.eq(rec.calls.size(), 2, "the HUD rebuilding the same button under the pointer does not")
	scene._hover_control(null)
	scene._hover_control(button)
	t.eq(rec.calls.size(), 3, "leaving and coming back does")
	button.disabled = true
	scene._hover_control(null)
	scene._hover_control(button)
	t.eq(rec.calls.size(), 3, "a disabled button is silent")
	var outside := Button.new()
	scene._hover_control(outside)
	t.eq(rec.calls.size(), 3, "a button outside the HUD is not the HUD's")
	outside.free()
	_done(scene)
