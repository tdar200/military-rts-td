extends Node
## Kestrel sound (plan 2026-10-06-kestrel-next-level, Task 5): the thin engine side of AudioDirector. It owns 16 plain
## SFX players (the camera is orthographic, so no positional players: the director pans and attenuates, and its pan picks
## one of the bus layout's panner buses), one UI player, one player per loop bed, and the scene's existing ambience
## player (moved onto the Ambient bus). Every stream is loaded once at setup from Task 4's files; nothing is synthesised
## at run time. Only the game makes one, and only on Kestrel, once the scene is in the tree.
const Director := preload("res://scripts/audio/audio_director.gd")
const MANIFEST := "res://assets/audio/sfx/sfx_manifest.json"
const SFX_VOICES := 16
const LOOP_SLEW_DB := 60.0  # dB per second a loop moves toward its level (fades in and out instead of clicking)
const LOOP_OFF_DB := -60.0  # a fading loop stops below this
const LOOP_FADE_FROM := 24.0  # a loop starts this far under its level and fades up

var streams: Dictionary = {}  # id -> AudioStream
var paused := false
var plays := 0  # started one-shots (the QA log counts them)
var log_plays := false  # EARTHFRONT_AUDIO_LOG=1 prints every start
var _sfx: Array[AudioStreamPlayer] = []
var _ui: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _loops: Dictionary = {}  # loop id -> AudioStreamPlayer
var _loop_level: Dictionary = {}  # loop id -> target volume_db, or LOOP_OFF_DB when it should stop
var _pending: Array = []  # {at: pool clock, result}: delayed shots, released by advance() in order
var _clock := 0.0
var _duck := 0.0


static func load_manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func setup(manifest: Dictionary) -> void:
	var base := String(manifest.get("base_path", "res://assets/audio/sfx/"))
	for s in manifest.get("sounds", []):
		var stream := load(base + String(s.get("file", ""))) as AudioStream
		if stream != null:
			streams[String(s["id"])] = stream
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%02d" % i
		p.bus = &"SFX"
		add_child(p)
		_sfx.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.name = "Ui"
	_ui.bus = &"UI"
	add_child(_ui)
	for id in Director.LOOP_IDS:
		var lp := AudioStreamPlayer.new()
		lp.name = String(id).to_pascal_case()
		lp.bus = &"SFX"
		lp.stream = streams.get(id)
		lp.volume_db = LOOP_OFF_DB
		add_child(lp)
		_loops[id] = lp
		_loop_level[id] = LOOP_OFF_DB
	log_plays = OS.get_environment("EARTHFRONT_AUDIO_LOG") == "1"


## The scene's ambience player (earthfront_3d._setup_audio) joins the Ambient bus, so the director's duck reaches it.
func adopt_ambient(player: AudioStreamPlayer) -> void:
	_ambient = player
	if player != null:
		player.bus = &"Ambient"


## Starts a director answer now, or after `delay` seconds of the pool's clock (which stands still while paused).
func play(result: Dictionary, delay := 0.0) -> void:
	if not bool(result.get("play", false)) or not streams.has(String(result.get("id", ""))):
		return
	if delay > 0.0:
		_pending.append({"at": _clock + delay, "result": result})
		_pending.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
		return
	_start(result)


func pending_count() -> int:
	return _pending.size()


## The loop beds from AudioDirector.loops: each fades toward its level, and out (then stops) when it is off.
func set_loops(levels: Dictionary) -> void:
	for id in _loops:
		var lv: Dictionary = levels.get(id, {})
		var p: AudioStreamPlayer = _loops[id]
		if bool(lv.get("play", false)) and not paused:
			_loop_level[id] = float(lv["volume_db"])
			p.bus = StringName(String(lv.get("bus", "SFX")))
			if not p.playing and p.stream != null and p.is_inside_tree():
				p.volume_db = float(lv["volume_db"]) - LOOP_FADE_FROM
				p.stream_paused = false
				p.play()
		else:
			_loop_level[id] = LOOP_OFF_DB


## The Ambient and Music level from AudioDirector.duck_db.
func set_duck(db: float) -> void:
	if is_equal_approx(db, _duck):
		return
	_duck = db
	for bus in ["Ambient", "Music"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, db)


## The sim's pause (earthfront_3d.set_sim_paused): every SFX and loop player holds where it is, delayed shots wait.
## The HUD's player and the ambience go on (the pause menu clicks; the wind keeps blowing).
func set_paused(on: bool) -> void:
	paused = on
	for p in _sfx:
		p.stream_paused = on
	for id in _loops:
		(_loops[id] as AudioStreamPlayer).stream_paused = on


func _process(delta: float) -> void:
	advance(delta)


## One frame: the clock (not while paused), the delayed shots now due, the loop fades.
func advance(delta: float) -> void:
	if paused:
		return
	_clock += delta
	while not _pending.is_empty() and float(_pending[0]["at"]) <= _clock:
		var due: Dictionary = _pending.pop_front()
		_start(due["result"])
	for id in _loops:
		var p: AudioStreamPlayer = _loops[id]
		if not p.playing:
			continue
		var goal := float(_loop_level[id])
		p.volume_db = move_toward(p.volume_db, goal, LOOP_SLEW_DB * delta)
		if goal <= LOOP_OFF_DB and p.volume_db <= LOOP_OFF_DB + 0.01:
			p.stop()


## Leaving the tree (a scene reload) or being freed puts Ambient and Music back at 0 dB: the bus layout outlives the pool.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		set_duck(0.0)


func _start(result: Dictionary) -> void:
	var id := String(result["id"])
	var p: AudioStreamPlayer = _ui if String(result.get("category", "")) == "ui" else _voice(int(result.get("priority", 0)))
	if p == null:
		return
	p.stop()
	p.stream = streams[id]
	p.bus = StringName(String(result.get("bus", "SFX")))
	p.volume_db = float(result.get("volume_db", 0.0))
	p.pitch_scale = float(result.get("pitch", 1.0))
	p.stream_paused = false
	p.set_meta("priority", int(result.get("priority", 0)))
	p.set_meta("started", _clock)
	if p.is_inside_tree():  # outside the tree (never in the game) a player cannot start; it is only set up
		p.play()
	plays += 1
	if log_plays:
		print("[audio] %s %.1f dB pan %.2f %s x%.3f (%d)" % [id, p.volume_db, float(result.get("pan", 0.0)), p.bus, p.pitch_scale, plays])


## A free SFX player, else the oldest of the lowest priority no higher than `priority` (the director's caps make this
## rare), else none.
func _voice(priority: int) -> AudioStreamPlayer:
	var steal: AudioStreamPlayer = null
	for p in _sfx:
		if not p.playing:
			return p
		var pr := int(p.get_meta("priority", 0))
		if pr > priority:
			continue
		if steal == null or pr < int(steal.get_meta("priority", 0)) or (pr == int(steal.get_meta("priority", 0)) and float(p.get_meta("started", 0.0)) < float(steal.get_meta("started", 0.0))):
			steal = p
	return steal
