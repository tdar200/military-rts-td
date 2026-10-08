extends Node
## Owns every UI surface of the live game: HUD (Main and Build layouts), title, debrief and the minimap mount.
## earthfront_3d.gd talks only to this object; the screens themselves never read game state (live_adapter.gd does).
const T = preload("res://scripts/ui/tokens.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const BuildDeck = preload("res://scripts/ui/build_deck.gd")
const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const Debrief = preload("res://scripts/ui/debrief.gd")
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const SessionLog = preload("res://scripts/ui/session_log.gd")
const LiveScreens = preload("res://scripts/ui/live_screens.gd")
const ResearchScreen = preload("res://scripts/ui/research_screen.gd")
const LiveResearch = preload("res://scripts/ui/live_research.gd")
const Assault = preload("res://scripts/ui/assault/assault.gd")
const WorldMarks = preload("res://scripts/ui/world_marks.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")
const VmGameplay = preload("res://scripts/ui/vm_gameplay.gd")
const PauseMenu = preload("res://scripts/ui/sections/pause_menu.gd")
const ControlsReference = preload("res://scripts/ui/sections/controls_reference.gd")
const VmMaps = preload("res://scripts/ui/vm_maps.gd")
const RegionMap = preload("res://scripts/ui/sections/region_map.gd")
const TerrainGuide = preload("res://scripts/ui/sections/terrain_guide.gd")
const EarlyMission = preload("res://scripts/ui/sections/early_mission.gd")
const MapPicker = preload("res://scripts/ui/sections/map_picker.gd")
const MatchConfig = preload("res://scripts/match_config.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const SettingsScreen = preload("res://scripts/ui/sections/settings_screen.gd")
const Records = preload("res://scripts/records.gd")
const PerkDraft = preload("res://scripts/ui/sections/perk_draft.gd")
const ReplayList = preload("res://scripts/ui/sections/replay_list.gd")

const VM_INTERVAL := 0.1
## The bridge may step a frame or two after pause.flag is written; more ticks than this while paused mean it still runs
## (or has not seen the flag yet: a slow frame rate stretches that gap well past this, so the marker also recovers).
const STOP_SLACK_TICKS := 6
## The tick must stand still this long (seconds) before a marker that said "still running" says "stopped" again.
const STOP_STILL_SECONDS := 0.6
## The strategic map re-reads the snapshot this often (seconds); it redraws only when what it shows changed.
const REGION_INTERVAL := 0.5
const BRIEFING_INTERVAL := 0.2
## The minimap is a second render of the whole battlefield (with its own shadow passes): about 1.9 ms and 1,160 draw calls
## a frame on Kestrel Reach when it redrew every frame. It redraws this often instead (seconds); the view box and marks
## over it are HUD controls, so they keep their own pace.
const MINIMAP_INTERVAL := 0.2
const MINIMAP_CENTER := Vector3(16.7, 34.0, 10.0)
const MINIMAP_SPAN := 35.0
## After the bridge took restart.flag (it removes the file, then writes the new sim's first snapshot), the picker waits this
## long (seconds) before it deploys, so start.flag never lands before that snapshot.
const LAUNCH_SETTLE := 0.1
## Task 26: after a replay was asked for, the bridge's playback snapshot (with its `replay` block) must arrive within this
## many seconds of the bridge taking restart.flag; otherwise the bridge could not play it (it builds a live match then).
const REPLAY_TIMEOUT := 3.0
## A run draft answered but still in the snapshot after this many ticks was not taken by the bridge: it opens again.
const DRAFT_RETRY_TICKS := 30

var g  # earthfront_3d.gd, or a stub with the same members in tests
var layer: CanvasLayer
var hud
var adapter
var session_log
var title
var scrim: Control
var marks: Control  # WorldMarks: hostile diamonds over the 3D scene, under the HUD
var research: Control  # the Science modal; the game's `science_overlay` is this node
var live_research
var selection_box: Panel
var pause_layer: Control  # the pause menu and the controls screen, over everything but the title
var pause_open := false
var controls_open := false
var confirm := ""  # "restart" or "quit" while the confirm panel is up
var guide_open := false  # the terrain guide (board 12), opened from the pause menu, shown in the pause layer
var region_open := false  # the strategic map (board 11): M toggles it, the simulation keeps running behind it
var region_layer: Control
var briefing_layer: Control  # the first-minutes briefing card (board 6)
var briefing_dismissed := false
var lens_on: Dictionary = RegionMap.DEFAULT_LENSES.duplicate()
var _region_hash := 0
var _region_clock := REGION_INTERVAL
var _briefing_hash := 0
var _briefing_clock := BRIEFING_INTERVAL
var _controls_over_play := false  # F1 opened the controls with no pause menu behind them: Back resumes
var _pause_tick := 0
## Task 22: this match's score went to the personal bests already (each match runs in a fresh scene, so this is per
## match), and what record_score() reported then.
var _score_recorded := false
var _score_record: Dictionary = {}
var _pause_seen_tick := 0
var _pause_still_s := 0.0
var _pause_moving := false  # the bridge tick moved on after the pause began and has not stood still since
var _pause_hash := 0
var minimap_view: SubViewportContainer
var _minimap_clock := 0.0
var minimap_renders := 0  # test hook: minimap redraws requested
var _clock := 0.0
var _since_vm := VM_INTERVAL
var _left_down := false
var _marks_drawn := false
var _minimap_drag := false  # Kestrel: the left button went down on the map inside the minimap and is still held
var _minimap_release_due := false  # the viewport saw the left release during a drag; the next frame ends it if the minimap did not
var _title_fogged := false  # the title already shows the Kestrel fog copy
var _title_key: Array = []  # what the title was last built from: [fogged, map, picker open or a launch pending]
var picker_layer: Control  # the map picker over the title (New operation)
var picker_open := false
var picker_choice := ""  # the map the picker has selected ("kestrel" or "survival")
var picker_difficulty := "normal"  # Task 20: the preset the picker has selected (the remembered one when it opens)
var picker_seed := 0  # Task 20: the seed the next operation runs at, drawn fresh on every open (the player may type one)
var _launch_wait := -1.0  # >= 0 while a confirmed pick waits for the bridge: seconds since restart.flag disappeared
var settings_layer: Control  # the Settings screen, over everything (the title's Settings entry or the pause menu's)
## Task 26: the run's perk draft (under the pause menu), the replay speed bar, and the Replays list over the title.
var draft_layer: Control
var _draft_ids: Array = []  # the perk ids on the cards; [] while no draft is up
var _draft_answered: Array = []  # the draft last picked, until the snapshot shows another (or none)
var _draft_answered_tick := -1
var _run_unlocked := false  # this run already grew the perk pool (once per run; each match is a fresh scene)
var replay_layer: Control
var _replay_hash := 0
var _replay_speed := "1"
var replays_layer: Control
var replays_open := false
var replays_dir := ReplayList.DIR  # tests point the list at their own user:// directory
var picker_mode := "operation"  # Task 26: Operation or Run (Kestrel only)
var settings_open := false
var _settings_from_pause := false


## The game adds this node to its tree first, then calls setup.
func setup(game) -> void:
	g = game
	layer = CanvasLayer.new()
	add_child(layer)
	adapter = Adapter.new(game)
	session_log = SessionLog.new()
	marks = WorldMarks.new()
	layer.add_child(marks)
	hud = Hud.new()
	BuildDeck.register(hud)
	Assault.register(hud)
	hud.action.connect(adapter.on_action)
	hud.action.connect(_on_hud_sound)
	hud.visible = false
	layer.add_child(hud)
	_mount_minimap()
	selection_box = Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.12)
	box.border_color = Color(T.CYAN.r, T.CYAN.g, T.CYAN.b, 0.8)
	box.set_border_width_all(1)
	selection_box.add_theme_stylebox_override("panel", box)
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.visible = false
	layer.add_child(selection_box)
	briefing_layer = _full_rect_layer("BriefingLayer")
	region_layer = _full_rect_layer("RegionLayer")
	live_research = LiveResearch.new()
	research = ResearchScreen.new()
	research.visible = false
	research.action.connect(_on_research_action)
	layer.add_child(research)
	draft_layer = _full_rect_layer("DraftLayer")
	replay_layer = _full_rect_layer("ReplayLayer")
	pause_layer = _full_rect_layer("PauseLayer")
	title = TitleScreen.new()
	title.action.connect(_on_title_action)
	layer.add_child(title)
	picker_layer = _full_rect_layer("PickerLayer")  # after the title, so the picker draws over it
	replays_layer = _full_rect_layer("ReplaysLayer")
	settings_layer = _full_rect_layer("SettingsLayer")  # last: over the title, the picker and the pause menu
	_refresh_title(true)
	title.focus_first()


## Every HUD action is a button press: the game sounds its click (Kestrel only; the game decides).
func _on_hud_sound(_name: String, _arg: Variant) -> void:
	if g.has_method("hud_clicked"):
		g.hud_clicked()


func _full_rect_layer(layer_name: String) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	return c


## The real battlefield, seen from above, inside the HUD's map slot. It shares the main world, so marks and view box draw over it.
func _mount_minimap() -> void:
	minimap_view = SubViewportContainer.new()
	minimap_view.name = "MinimapView"
	minimap_view.stretch = true
	minimap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.map_slot.add_child(minimap_view)
	var view := SubViewport.new()
	view.world_3d = g.get_viewport().world_3d
	view.render_target_update_mode = SubViewport.UPDATE_ONCE  # then every MINIMAP_INTERVAL (_refresh_minimap)
	view.transparent_bg = false
	minimap_view.add_child(view)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = MINIMAP_SPAN
	cam.position = MINIMAP_CENTER
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	view.add_child(cam)
	minimap_view.size = hud.map_slot.size
	minimap_view.gui_input.connect(_on_minimap_input)


## World-space rectangle (x, z) the minimap camera shows, for the current slot shape. Empty until the slot has a size.
func minimap_world_rect() -> Rect2:
	return _world_rect_for(hud.map_slot.size)


## The orthographic camera keeps its MINIMAP_SPAN height and the SubViewport (stretched to its container) takes the slot's
## aspect, so the view is MINIMAP_SPAN tall and as wide as the slot's shape asks: the map sits letterboxed inside it.
static func _world_rect_for(s: Vector2) -> Rect2:
	if s.x < 1.0 or s.y < 1.0:
		return Rect2()
	var w := MINIMAP_SPAN * s.x / s.y
	return Rect2(MINIMAP_CENTER.x - w * 0.5, MINIMAP_CENTER.z - MINIMAP_SPAN * 0.5, w, MINIMAP_SPAN)


## A pixel of the minimap (local to its container, `size` pixels) as the world point (x, z) the camera draws there: the
## camera looks straight down, screen right is +x and screen down is +z (the marks use the same mapping).
static func slot_to_world(local: Vector2, size: Vector2, world: Rect2) -> Vector2:
	return Vector2(world.position.x + local.x / size.x * world.size.x, world.position.y + local.y / size.y * world.size.y)


## Kestrel: the ground point under a minimap pixel, or Vector3.INF when it is past the map (the sea the letterbox shows).
## `clamp_to_map` (a drag) pulls such a point to the nearest map edge instead.
func minimap_point(local: Vector2, clamp_to_map := false) -> Vector3:
	var size: Vector2 = minimap_view.size
	var world := _world_rect_for(size)
	if world.size.x <= 0.0 or not g.has_method("map_world_rect"):
		return Vector3.INF
	var at := slot_to_world(local, size, world)
	var map: Rect2 = g.map_world_rect()
	if clamp_to_map:
		at = Vector2(clampf(at.x, map.position.x, map.end.x), clampf(at.y, map.position.y, map.end.y))
	elif at.x < map.position.x or at.x > map.end.x or at.y < map.position.y or at.y > map.end.y:
		return Vector3.INF
	return Vector3(at.x, 0.0, at.y)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_left_down = event.pressed
		# A click that focuses the window can lose the GUI's mouse focus, so the minimap may never get this release.
		_minimap_release_due = _minimap_drag and not event.pressed


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_minimap_drag = false  # the release may never arrive: the next press starts afresh


# ---------------------------------------------------------------- minimap: click and drag to move the camera (Kestrel)

## Kestrel only (world art on, and the game can jump): Survival's minimap keeps ignoring the pointer as before.
func _minimap_jumps() -> bool:
	return bool(g.get("world_art_on")) and g.has_method("minimap_jump")


## Kestrel's minimap passes the pointer to _on_minimap_input; Survival's ignores it. Called every frame the HUD runs.
func _sync_minimap_input() -> void:
	var want := Control.MOUSE_FILTER_PASS if _minimap_jumps() else Control.MOUSE_FILTER_IGNORE
	if minimap_view.mouse_filter != want:
		minimap_view.mouse_filter = want
		_minimap_drag = false


func _on_minimap_input(event: InputEvent) -> void:
	if _minimap_event(event):
		minimap_view.accept_event()


## One pointer event on the minimap (local to it). True when it is used here, so it never reaches the world's selection,
## orders or zoom. A left press on the map jumps the camera there and starts a drag that follows the pointer (clamped to
## the map) until the release. A press past the map, a right or middle click and the wheel do nothing but are still kept
## from the world. An armed placement or order stays armed: the minimap only moves the camera. A release with no drag of
## ours (a box select that ended over the minimap) is passed on, so the world closes its box.
func _minimap_event(event: InputEvent) -> bool:
	if not _minimap_jumps() or world_blocked() or research.visible or scrim != null:
		_minimap_drag = false
		return false
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return true
		if not event.pressed:
			var ours := _minimap_drag
			_minimap_drag = false
			_minimap_release_due = false
			return ours
		var at := minimap_point(event.position)
		if at.is_finite():
			_minimap_drag = true
			g.minimap_jump(at)
		return true
	if event is InputEventMouseMotion and _minimap_drag:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_minimap_drag = false  # released somewhere we never heard of
			return false
		g.minimap_jump(minimap_point(event.position, true))
		return true
	return false


## Called every frame by the game. The view model is rebuilt about ten times a second, and never while a click is
## in flight over the HUD, so a button is not replaced between its press and its release.
func process(delta: float) -> void:
	_refresh_title()
	_tick_launch(delta)
	if paused():
		# Frozen: no HUD rebuild, no ticker, no log samples, and the alert clock stands still. Only the pause screens refresh.
		_minimap_drag = false
		_watch_stop(delta)
		_since_vm += delta
		if _since_vm >= VM_INTERVAL:
			_since_vm = 0.0
			_refresh_pause()
		return
	if _minimap_release_due:
		_minimap_release_due = false
		_minimap_drag = false
	_sync_minimap_input()
	_refresh_run()
	_refresh_replay_bar()
	_refresh_hud(delta)
	_pulse_pings()


## Kestrel: the alert ping rings pulse from the game's alert clock every frame (after any HUD rebuild, so a new marks
## control gets the time before it draws). Nothing while paused: process returns before this, and the clock stops anyway.
func _pulse_pings() -> void:
	if not hud.visible or g.get("alert_pings") == null:
		return
	var now := float(g.alert_clock())
	for child in hud.get_node("minimap_marks").get_children():
		if child.has_method("set_clock"):
			child.set_clock(now)


func _refresh_hud(delta: float) -> void:
	_clock += delta
	_refresh_minimap(delta)
	session_log.observe(g)
	adapter.poll_ticker(g.objective_label.text, _clock)
	_update_marks()
	_briefing_clock += delta
	if _briefing_clock >= BRIEFING_INTERVAL:
		_briefing_clock = 0.0
		_refresh_briefing()
	_region_clock += delta
	if region_open and _region_clock >= REGION_INTERVAL:
		_region_clock = 0.0
		_refresh_region()
	_since_vm += delta
	if _since_vm < VM_INTERVAL:
		return
	if g.bridge_poll_elapsed == 0.0 and _since_vm < VM_INTERVAL * 2.0:
		return  # the game parsed a snapshot this frame: rebuild on the next one, so the two costs never share a frame
	if research.visible and not _left_down:  # the modal blocks everywhere: no rebuild between a press and its release
		_since_vm = 0.0
		research.apply(live_research.vm(g))
	if not hud.visible:
		return
	if _left_down and hud.blocks_point(g.mouse_position()):
		return
	_since_vm = 0.0
	if bool(g.get("world_art_on")):
		hud.raise_alerts()  # Kestrel: toasts over the left card stack (a structure under attack must be seen)
	hud.apply(adapter.hud_vm(_clock))
	if minimap_view.get_parent() != hud.map_slot:
		minimap_view.reparent(hud.map_slot, false)  # the assault layout draws its own slot
	minimap_view.size = hud.map_slot.size  # the Build layout reshapes the slot


## The title follows the bridge: its Visibility fact says "fog of war" once a fogged snapshot arrives (it is built before
## any snapshot, with Survival's whole-battlefield copy), the campaign card names the map the bridge runs, and its deploy
## entries wait (disabled) while the map picker covers them or a picked map is being prepared. Rebuilt only on a change.
func _refresh_title(force := false) -> void:
	if title == null or not title.visible:
		return
	var snap = g.get("bridge_snapshot")
	if not _title_fogged and snap is Dictionary and VmGameplay.fogged(snap):
		_title_fogged = true
	var busy := picker_open or replays_open or _launch_wait >= 0.0 or MatchConfig.pending_auto_deploy()
	var key := [_title_fogged, shown_scenario(), busy]
	if not force and key == _title_key:
		return
	var had_focus: bool = _title_key.size() == 3 and bool(_title_key[2]) and not busy
	_title_key = key
	title.apply(LiveScreens.title_vm(not busy, int(g.bridge_technology_total), _title_fogged, key[1]))
	if had_focus:
		title.focus_first()


## The map on the title: the one the bridge's snapshot comes from, else the running config's (before any snapshot).
func shown_scenario() -> String:
	var snap = g.get("bridge_snapshot")
	var running := MatchConfig.running(snap) if snap is Dictionary else ""
	return running if running != "" else str(MatchConfig.current.scenario)


# ---------------------------------------------------------------- map picker (New operation)

func _runtime_dir() -> String:
	var dir = g.get("runtime_directory")
	return str(dir) if dir != null else ""


func _restart_pending() -> bool:
	var dir := _runtime_dir()
	return dir != "" and FileAccess.file_exists(dir.path_join("restart.flag"))


func open_picker() -> void:
	if picker_open or title == null or _launch_wait >= 0.0:
		return
	picker_open = true
	picker_choice = shown_scenario()
	picker_difficulty = MatchConfig.clean_difficulty(Settings.get_value("game/difficulty", _settings_path()))
	picker_seed = MatchConfig.random_seed()  # a new operation never reuses the last match's seed
	picker_mode = "operation"
	_build_picker()
	_refresh_title()


func close_picker() -> void:
	picker_open = false
	for child in picker_layer.get_children():
		picker_layer.remove_child(child)
		child.queue_free()
	_refresh_title()


func _build_picker() -> void:
	for child in picker_layer.get_children():
		picker_layer.remove_child(child)
		child.queue_free()
	var vm := LiveScreens.picker_vm(picker_choice, picker_difficulty, picker_seed, picker_mode, _perk_pool())
	var confirm: Control = MapPicker.build(picker_layer, vm, Callable(self, "_on_picker_action"))
	if confirm != null and confirm.is_inside_tree():
		confirm.grab_focus()


func _on_picker_action(name: String, arg: Variant = null) -> void:
	match name:
		"pick":
			if str(arg) in MatchConfig.SCENARIOS and str(arg) != picker_choice:
				picker_choice = str(arg)
				if picker_choice != "kestrel":
					picker_mode = "operation"
				_build_picker()
		"difficulty":
			if str(arg) in MatchConfig.DIFFICULTIES and str(arg) != picker_difficulty:
				picker_difficulty = str(arg)
				_build_picker()
		"seed":
			# Typed into the seed field: no redraw (the field keeps focus); an empty or invalid entry keeps the last seed.
			picker_seed = MatchConfig.clean_seed(arg, picker_seed)
		"mode":
			# Task 26: a run is Kestrel only, so Run picks Kestrel Reach and Survival is always an operation.
			if str(arg) in MatchConfig.MODES and str(arg) != picker_mode:
				picker_mode = str(arg)
				if picker_mode == "run":
					picker_choice = "kestrel"
				_build_picker()
		"daily":
			# Task 26: today's UTC date as the seed, the same match for everyone today.
			picker_seed = MatchConfig.daily_seed(int(Time.get_unix_time_from_system()))
			_build_picker()
		"back":
			close_picker()
		"confirm":
			confirm_picker()


## Deploy the picked map: match.json for the bridge, then restart.flag. When the title already drew another map (its ground,
## its entities), the scene must be fresh for the new one: the existing restart reloads it and the new title deploys by
## itself (_tick_launch). Otherwise the bridge rebuilds in place and the mission deploys once it took the flag.
func confirm_picker() -> void:
	if not picker_open:
		return
	var cfg := MatchConfig.current
	cfg["scenario"] = picker_choice
	cfg["seed"] = picker_seed
	cfg["difficulty"] = picker_difficulty
	cfg["mode"] = picker_mode if picker_choice == "kestrel" else "operation"
	cfg["perk_pool"] = _perk_pool()
	cfg = MatchConfig.live(MatchConfig.with_settings(cfg, _settings_path()))
	MatchConfig.current = cfg
	MatchConfig.write(_runtime_dir(), cfg)
	if Settings.get_value("game/difficulty", _settings_path()) != picker_difficulty:
		Settings.set_value("game/difficulty", picker_difficulty, _settings_path())  # preselected next time
	var snap = g.get("bridge_snapshot")
	var on_screen := MatchConfig.running(snap) if snap is Dictionary else ""
	picker_open = false
	for child in picker_layer.get_children():
		picker_layer.remove_child(child)
		child.queue_free()
	if on_screen != "" and on_screen != picker_choice:
		MatchConfig.set_auto_deploy(true)
		_refresh_title()
		g._restart_mission()
		return
	_relaunch_in_place()


## restart.flag for the bridge (it rebuilds the map match.json names, here the one on screen), then the mission deploys
## once the bridge took the flag (_tick_launch).
func _relaunch_in_place() -> void:
	var dir := _runtime_dir()
	if dir != "":
		var flag := FileAccess.open(dir.path_join("restart.flag"), FileAccess.WRITE)
		if flag:
			flag.store_line("restart")
	_launch_wait = 0.0
	_refresh_title()


## The campaign card's Deploy forces: the map the bridge already serves. When the player's fog setting or remembered
## difficulty preset differs from the Kestrel frame on screen (changed since the bridge built it), match.json asks for the
## match with the settings (and a fresh seed: a new operation) and the bridge rebuilds it first; otherwise the mission
## deploys at once, as before. Task 26: a Kestrel match the bridge booted without any match.json from this client (its
## boot match) is rebuilt once, at the same seed and preset, from a match.json that names replay_dir, so the bridge
## records it like any picked match.
func deploy_from_title() -> void:
	var snap = g.get("bridge_snapshot")
	if snap is Dictionary and MatchConfig.running(snap) == "kestrel" and MatchConfig.replay_state(snap).is_empty():
		var want_fog := bool(Settings.get_value("game/fog", _settings_path()))
		var want_preset := MatchConfig.clean_difficulty(Settings.get_value("game/difficulty", _settings_path()))
		var served: Dictionary = MatchConfig.from_snapshot(snap)
		var fresh := VmGameplay.fogged(snap) != want_fog or str(served.get("difficulty", want_preset)) != want_preset
		if fresh or (not MatchConfig.written() and _runtime_dir() != ""):
			var cfg := MatchConfig.current
			cfg["scenario"] = "kestrel"
			if fresh:
				cfg["seed"] = MatchConfig.random_seed()
				cfg["difficulty"] = want_preset
			else:
				cfg.merge(served, true)  # the boot match again: same seed, same preset (and a run stays a run)
			cfg = MatchConfig.live(MatchConfig.with_settings(cfg, _settings_path()))
			MatchConfig.current = cfg
			MatchConfig.write(_runtime_dir(), cfg)
			_relaunch_in_place()
			return
	g._deploy_mission()


## Task 26: the player's run perk pool (Settings "run/perk_pool").
func _perk_pool() -> int:
	return MatchConfig.clean_pool(Settings.get_value("run/perk_pool", _settings_path()))


## Every frame while the title is up. A confirmed pick deploys LAUNCH_SETTLE seconds after the bridge removed restart.flag.
## After a reload asked for an auto deploy (the debrief's Restart, or a pick of another map), the mission deploys once the
## bridge took the flag and serves the chosen map at tick 0.
func _tick_launch(delta: float) -> void:
	if title == null:
		return
	if _launch_wait >= 0.0:
		if _restart_pending():
			_launch_wait = 0.0
			return
		_launch_wait += delta
		if _launch_wait >= LAUNCH_SETTLE:
			if _awaiting_replay():
				_await_replay()
				return
			_launch_wait = -1.0
			g._deploy_mission()
		return
	if not MatchConfig.pending_auto_deploy() or _restart_pending():
		return
	if _awaiting_replay():
		_launch_wait = 0.0  # a reload that asked for a replay: wait for the playback snapshot as above
		MatchConfig.set_auto_deploy(false)
		return
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty() or int(snap.get("tick", -1)) != 0:
		return
	if MatchConfig.running(snap) != str(MatchConfig.current.scenario):
		return
	MatchConfig.set_auto_deploy(false)
	g._deploy_mission()


## Task 26: the next match is a replay (MatchConfig.current names one).
func _awaiting_replay() -> bool:
	return str(MatchConfig.current.get("replay", "")) != ""


## The bridge took restart.flag for a replay: deploy (start.flag starts the playback, at 1x) once its playback snapshot
## is here; after REPLAY_TIMEOUT without one the bridge could not play the file and built a live match instead, so the
## list comes back with the reason and the config is live again.
func _await_replay() -> void:
	if not MatchConfig.replay_state(g.get("bridge_snapshot")).is_empty():
		_launch_wait = -1.0
		_replay_speed = "1"
		if g.has_method("write_replay_speed"):
			g.write_replay_speed("1")
		g._deploy_mission()
		return
	if _launch_wait < REPLAY_TIMEOUT:
		return
	_launch_wait = -1.0
	var cfg := MatchConfig.live(MatchConfig.current)
	MatchConfig.current = cfg
	MatchConfig.write(_runtime_dir(), cfg)  # the bridge already runs the live match; the next restart stays live
	open_replays("That replay could not be played (the bridge rejected the file). A live match is ready instead.")


## Keys on the title (the game's input handler sends them here before deploy): Esc closes the Settings screen or the map
## picker, the ui_left and ui_right actions (the arrow keys) move the picker's selection. True when the key was used.
func route_title_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if settings_open:
		if event.keycode == Keybinds.CANCEL:
			close_settings()
			return true
		return false
	if replays_open:
		if event.keycode == Keybinds.CANCEL:
			close_replays()
			return true
		return false
	if not picker_open:
		return false
	if event.keycode == Keybinds.CANCEL:
		close_picker()
		return true
	var step := -1 if event.is_action_pressed("ui_left") else (1 if event.is_action_pressed("ui_right") else 0)
	if step == 0:
		return false
	var at := MatchConfig.SCENARIOS.find(picker_choice)
	_on_picker_action("pick", MatchConfig.SCENARIOS[clampi(at + step, 0, MatchConfig.SCENARIOS.size() - 1)])
	return true


## Asks the minimap viewport for one more frame every MINIMAP_INTERVAL while the HUD is up (UPDATE_ONCE falls back to
## disabled by itself after drawing).
func _refresh_minimap(delta: float) -> void:
	_minimap_clock += delta
	if _minimap_clock < MINIMAP_INTERVAL or not hud.visible or minimap_view.get_child_count() == 0:
		return
	_minimap_clock = 0.0
	(minimap_view.get_child(0) as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	minimap_renders += 1


## World marks follow the 3D scene every frame: the assault layout's hostile marks there, otherwise the selected building's
## rally path or turret range and the inbound wave's route (live_adapter.gd board_marks). Cleared when neither applies.
func _update_marks() -> void:
	var cam: Camera3D = g.camera
	var drawn := false
	if hud.visible and cam != null:
		if adapter.assault_active():
			var view := Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size)
			marks.set_marks(adapter.assault.marks(cam.unproject_position, view, cam.is_position_behind))
			drawn = true
		elif g.has_method("screen_point_of_hex"):
			var board: Array = adapter.board_marks(func(x: int, y: int) -> Vector2: return g.screen_point_of_hex(x, y))
			if not board.is_empty():
				marks.set_marks(board)
				drawn = true
	if not drawn and _marks_drawn:
		marks.set_marks([])
	_marks_drawn = drawn


## True when the point (viewport pixels) is over any UI surface, so the 3D scene must not react to it.
func blocks_point(point: Vector2) -> bool:
	if title != null and title.visible:
		return true
	if world_blocked():
		return true
	if scrim != null or research.blocks_point(point):
		return true
	if briefing_layer.get_child_count() > 0 and EarlyMission.rect().has_point(point):
		return true
	return hud.visible and hud.blocks_point(point)


func notify(heading: String, body: String, color: Color) -> void:
	adapter.push_notification(heading, body, color, _clock)


## Kestrel: a human structure lost HP (see live_adapter.structure_attacked). True when its throttled toast went up.
func structure_attacked(id: int, kind: String, pos: Vector3, cell: Array) -> bool:
	return adapter.structure_attacked(id, kind, pos, cell, _clock)


## "build", "units" or "orders". Science is a full screen the game opens itself, so it is not a deck tab.
func set_tab(name: String) -> void:
	if name in ["build", "units", "orders"]:
		adapter.tab = name


func research_open() -> bool:
	return research.visible


## Y or the Research button: opens the Science modal on the live options, or closes it.
func toggle_research() -> void:
	if scrim != null and not research.visible:
		return
	research.visible = not research.visible
	if research.visible:
		research.apply(live_research.vm(g))


func _on_research_action(name: String, arg: Variant) -> void:
	var result: Dictionary = live_research.handle(name, arg)
	if result.has("research"):
		g._write_bridge_research(result["research"])
		research.visible = false
	elif result.has("upgrade"):
		g._write_bridge_upgrade(result["upgrade"])  # Kestrel Upgrades: the screen stays open to buy another level
		research.apply(live_research.vm(g))
	elif result.has("close"):
		research.visible = false
	elif name == "zoom_to" and _left_down:
		pass  # mid-drag: the track redraws itself, and the periodic refresh applies the scale after release
	else:
		research.apply(live_research.vm(g))
		if name == "select":
			research.focus_node(arg)


## The title fades out and the HUD takes over.
func begin_operation() -> void:
	hud.visible = true
	if title == null:
		return
	var old = title
	title = null
	var tween := create_tween()
	tween.tween_property(old, "modulate:a", 0.0, 0.32)
	tween.tween_callback(old.queue_free)


func _on_title_action(name: String, _arg: Variant) -> void:
	match name:
		"pick_map":
			open_picker()
		"replays":
			open_replays()
		"settings":
			open_settings()
		"deploy":
			deploy_from_title()
		"quit":
			get_tree().quit()


## Victory or defeat debrief over a scrim. "review" removes it so the battlefield can be inspected; "restart" replays the
## same map and seed and deploys again; "menu" returns to the title; "quit" closes the game.
func show_debrief() -> void:
	if scrim != null or replay_mode():
		return  # Task 26: a replay that ends says so on its speed bar; Leave goes back to the title
	close_region()  # the debrief owns the screen; Esc under its scrim must not reach a map left open behind it
	scrim = ColorRect.new()
	(scrim as ColorRect).color = T.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(scrim)
	var panel := Debrief.new()
	scrim.add_child(panel)
	panel.action.connect(_on_debrief_action)
	panel.apply(LiveScreens.debrief_vm(g, session_log, record_score()))
	Debrief.place_in(panel, g.get_viewport().get_visible_rect().size)


## Task 22: submits a decided Kestrel depth match's score total to the personal bests (Records, keyed by map and
## difficulty) once, and returns {best, new_best} for the debrief. {} when there is nothing to record: no winner yet (a
## restart mid-match never gets here), Survival or classic Kestrel (no depth score), or no records file in use (the game's
## records_path is ""; the test stub's default). A second call for the same match returns the first answer.
func record_score() -> Dictionary:
	if _score_recorded:
		return _score_record
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or int(g.bridge_winner) < 0 or replay_mode():
		return {}
	var depth: Variant = snap.get("depth", null)
	if not (depth is Dictionary) or not (depth.get("score", null) is Dictionary):
		return {}
	var path := _records_path()
	if path == "":
		return {}
	var map := MatchConfig.running(snap)
	var difficulty := MatchConfig.clean_difficulty(depth.get("difficulty", "normal"))
	_score_recorded = true
	var new_best := Records.submit(map, difficulty, int(depth["score"].get("total", 0)), path)
	_score_record = {"best": Records.best(map, difficulty, path), "new_best": new_best}
	return _score_record


func _on_debrief_action(name: String, _arg: Variant) -> void:
	match name:
		"review":
			if scrim != null:
				scrim.queue_free()
				scrim = null
		"restart":
			# Same map (the one the bridge runs), the same seed and preset (the bridge reports them; Task 20): match.json
			# says so, the reload's title deploys by itself.
			var cfg := MatchConfig.current
			var snap = g.get("bridge_snapshot")
			var running := MatchConfig.running(snap) if snap is Dictionary else ""
			if running != "":
				cfg["scenario"] = running
			cfg.merge(MatchConfig.from_snapshot(snap), true)
			if MatchConfig.is_run(cfg):
				cfg["perk_pool"] = _perk_pool()  # a run restarted draws from the pool as it is now
			cfg = MatchConfig.live(MatchConfig.with_settings(cfg, _settings_path()))
			MatchConfig.current = cfg
			MatchConfig.write(_runtime_dir(), cfg)
			MatchConfig.set_auto_deploy(true)
			g._restart_mission()
		"menu":
			# The title holds a fresh match (a new seed at the remembered preset), so its Deploy forces never replays the
			# finished one by accident: Restart is the only same-seed path.
			var cfg := MatchConfig.current
			var snap = g.get("bridge_snapshot")
			var running := MatchConfig.running(snap) if snap is Dictionary else ""
			if running != "":
				cfg["scenario"] = running
			cfg["seed"] = MatchConfig.random_seed()
			cfg["difficulty"] = MatchConfig.clean_difficulty(Settings.get_value("game/difficulty", _settings_path()))
			cfg["mode"] = "operation"  # Task 26: the title's Deploy forces is an operation; a run starts from the picker
			cfg = MatchConfig.live(MatchConfig.with_settings(cfg, _settings_path()))
			MatchConfig.current = cfg
			MatchConfig.write(_runtime_dir(), cfg)
			MatchConfig.set_auto_deploy(false)
			g._restart_mission()  # restart.flag, then the scene reloads to the title
		"quit":
			get_tree().quit()


# ---------------------------------------------------------------- pause menu and controls screen

## True while the pause menu or the controls screen is up: the world takes no input and the HUD does not update.
func paused() -> bool:
	return pause_open or controls_open


## True when the world must take no input: a paused game, or the strategic map covering the screen (the simulation keeps
## running behind the map, so the camera and orders just do not react to it).
func world_blocked() -> bool:
	return paused() or region_open or draft_open()


## What Esc does right now, most specific first: close the Settings screen, close the controls screen, close the terrain guide, close the confirm panel,
## resume, close the strategic map, close the Science modal, cancel an armed order or placement, otherwise open the pause menu ("none" while the debrief is up).
func escape_route(armed: bool) -> String:
	if settings_open:
		return "close_settings"
	if controls_open:
		return "close_controls"
	if guide_open:
		return "close_guide"
	if confirm != "":
		return "close_confirm"
	if pause_open:
		return "resume"
	if region_open:
		return "close_region"
	if research.visible:
		return "close_research"
	if armed:
		return "cancel_orders"
	if scrim != null or not hud.visible:
		return "none"
	return "open_pause"


## Esc and F1 for the game's input handler. True when the key was used here; the research and armed-order cases stay with
## the handler (their existing code closes the modal or cancels the order).
func route_key(event: InputEvent, armed := false) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if settings_open and event.keycode != Keybinds.CANCEL:
		return false  # the Settings screen covers everything: F1 and M wait until it closes
	if draft_open() and not paused():
		# Task 26: the draft owns the number keys while it is up (in play they are the control groups): 1 to 3 take a
		# card, the rest are swallowed. Esc and F1 still reach the pause menu and the controls; M waits.
		var n := _number_key(event)
		if n > 0:
			if n <= _draft_ids.size():
				choose_draft(n - 1)
			return true
		if event.keycode == Keybinds.REGION_MAP:
			return true
	if event.keycode == Keybinds.CONTROLS:
		# The Science modal owns the screen: F1 must not open the controls over it (the game's handler lets Esc close it).
		if scrim != null or not hud.visible or research.visible:
			return false
		if region_open:
			close_region()
		if controls_open:
			close_controls()
		else:
			open_controls()
		return true
	if event.keycode == Keybinds.REGION_MAP:
		if scrim != null or not hud.visible or paused() or research.visible:
			return false
		if region_open:
			close_region()
		else:
			open_region()
		return true
	if event.keycode != Keybinds.CANCEL:
		return false
	match escape_route(armed):
		"close_settings":
			close_settings()
		"close_controls":
			close_controls()
		"close_guide":
			close_guide()
		"close_region":
			close_region()
		"close_confirm":
			confirm = ""
			_refresh_pause(true)
		"resume":
			close_pause()
		"open_pause":
			open_pause()
		_:
			return false
	return true


func open_pause() -> void:
	if paused() or scrim != null or not hud.visible:
		return
	pause_open = true
	confirm = ""
	_enter_pause()


func close_pause() -> void:
	if settings_open and _settings_from_pause:
		close_settings()
	pause_open = false
	controls_open = false
	guide_open = false
	_controls_over_play = false
	confirm = ""
	_leave_pause()


## From the pause menu's Controls button, or F1 in play (which then pauses by itself and resumes on Back).
func open_controls() -> void:
	if scrim != null or not hud.visible:
		return
	if controls_open:
		return
	_controls_over_play = not pause_open
	controls_open = true
	if _controls_over_play:
		_enter_pause()  # F1 in play: stop the simulation too
	else:
		_refresh_pause(true)


func close_controls() -> void:
	controls_open = false
	if _controls_over_play:
		_controls_over_play = false
		_leave_pause()
	else:
		_refresh_pause(true)


## The pause menu's Terrain guide button. Needs the table the guide is built from.
func open_guide() -> void:
	if not pause_open or controls_open or guide_open or _guide_vm().is_empty():
		return
	guide_open = true
	confirm = ""
	_refresh_pause(true)


func close_guide() -> void:
	guide_open = false
	_refresh_pause(true)


## Whether the bridge really stopped: the marker follows the tick, never the request. Moving past the slack means it still
## runs; standing still for STOP_STILL_SECONDS means it stopped (late, on a slow frame rate), whatever the gap was.
func _watch_stop(delta: float) -> void:
	var tick := int(g.bridge_tick)
	if tick != _pause_seen_tick:
		_pause_seen_tick = tick
		_pause_still_s = 0.0
		if tick - _pause_tick > STOP_SLACK_TICKS:
			_pause_moving = true
	else:
		_pause_still_s += delta
		if _pause_still_s >= STOP_STILL_SECONDS:
			_pause_moving = false
			_pause_tick = tick  # the stopped tick is the new baseline for the slack


func _enter_pause() -> void:
	_minimap_drag = false  # a drag held into the pause must not resume on its own after it
	_pause_tick = int(g.bridge_tick)
	_pause_seen_tick = _pause_tick
	_pause_still_s = 0.0
	_pause_moving = false
	if g.has_method("set_sim_paused"):
		g.set_sim_paused(true)
	_refresh_pause(true)


func _leave_pause() -> void:
	if g.has_method("set_sim_paused"):
		g.set_sim_paused(false)
	_clear_pause_layer()
	_pause_hash = 0
	_since_vm = VM_INTERVAL  # the HUD redraws on the first frame back


func _clear_pause_layer() -> void:
	for child in pause_layer.get_children():
		pause_layer.remove_child(child)
		child.queue_free()


## The snapshot and its ground model, as the HUD slices read them; both empty/null before the first snapshot.
func _snapshot_and_ground() -> Array:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or snap.is_empty():
		return [{}, null]
	var ground = g.get("ground_model")
	if ground == null:
		ground = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap)
	return [snap, ground]


var _ground_key := 0  # cache for _has_real_ground
var _ground_real := false
var _ground_decodes := 0  # test hook: how often the layer was really decoded


## True when the match has real terrain to describe: a valid, non-flat ground model. Survival's all-Grassland layer has none
## (the client keeps its noise terrain), so the terrain guide and the briefing stay away from it. Cheap: the live game already
## holds the model; otherwise one decode of the snapshot layer.
func _has_real_ground() -> bool:
	if g.get("ground_model") != null:
		return true
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary):
		return false
	# The layer is fixed for a match, so decode it once per distinct (ground, size) rather than on every briefing and pause
	# refresh: a String hash is far cheaper than from_snapshot, which also copies the table.
	var key := hash([str(snap.get("ground", "")), int(snap.get("map_width", 0)), int(snap.get("map_height", 0))])
	if key != _ground_key:
		_ground_key = key
		_ground_real = preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap) != null
		_ground_decodes += 1
	return _ground_real


## Cheap: true when there is a real (non-flat) ground model AND the snapshot carries a named ground_table row, i.e. exactly when
## _guide_vm has anything to build (the pause view model asks every 0.1 s, so it must not build the whole guide).
func _can_guide() -> bool:
	var snap = g.get("bridge_snapshot")
	if not (snap is Dictionary) or not _has_real_ground():
		return false
	var table = snap.get("ground_table", [])
	if not (table is Array):
		return false
	for row in table:  # a handful of rows; the guide itself skips unnamed ones
		if row is Dictionary and str(row.get("name", "")) != "":
			return true
	return false


func _guide_vm() -> Dictionary:
	var sg := _snapshot_and_ground()
	return VmMaps.terrain_guide(sg[0], sg[1]) if sg[1] != null else {}


## The pause menu's view model: the snapshot rows (vm_gameplay.pause) plus the host's state. `stopped` is true while the
## bridge tick has not moved since the pause began, so the marker never claims a stop that is not happening.
func _pause_vm() -> Dictionary:
	var snap = g.get("bridge_snapshot")
	var losses := -1
	if session_log != null:
		losses = 0
		for kind in session_log.lost:
			losses += int(session_log.lost[kind])
	var stopped: bool = not _pause_moving
	var vm := VmGameplay.pause(snap if snap is Dictionary else {}, losses, stopped)
	if vm.is_empty():
		vm = {"stopped": stopped, "keys": VmGameplay.pause_keys()}
	vm["confirm"] = confirm
	vm["can_restart"] = g.has_method("_restart_mission")
	vm["can_guide"] = _can_guide()
	vm["can_settings"] = true
	return vm


## Rebuilds whichever pause screen is up when its view model changed (never between a press and its release).
func _refresh_pause(force := false) -> void:
	if not paused():
		return
	var vm: Dictionary
	if controls_open:
		vm = Keybinds.vm(not _controls_over_play, bool(g.get("world_art_on")))
	elif guide_open:
		vm = _guide_vm()
	else:
		vm = _pause_vm()
	var h := hash([controls_open, guide_open, vm])
	if not force and (h == _pause_hash or _left_down):
		return
	_pause_hash = h
	_clear_pause_layer()
	var emit := Callable(self, "_on_pause_action")
	if controls_open:
		ControlsReference.build(pause_layer, vm, emit)
	elif guide_open:
		TerrainGuide.build(pause_layer, vm, emit)
	else:
		PauseMenu.build(pause_layer, vm, emit)


func _on_pause_action(name: String, _arg: Variant = null) -> void:
	match name:
		"resume":
			close_pause()
		"open_controls":
			open_controls()
		"open_guide":
			open_guide()
		"open_settings":
			open_settings()
		"guide_back":
			close_guide()
		"controls_back":
			close_controls()
		"ask_restart":
			confirm = "restart"
			_refresh_pause(true)
		"ask_quit":
			confirm = "quit"
			_refresh_pause(true)
		"keep_playing":
			confirm = ""
			_refresh_pause(true)
		"restart":
			close_pause()
			if replay_mode():
				leave_replay()  # Task 26: a replay restarts as the live title, never as the recording again
				return
			g._restart_mission()  # the existing restart: restart.flag for the bridge, then the scene reloads to the title
		"quit":
			get_tree().quit()


# ---------------------------------------------------------------- Settings screen

## Where the settings live: the game's settings_path (tests point the stub at their own file), else Settings.PATH.
func _settings_path() -> String:
	var path = g.get("settings_path")
	return str(path) if path != null and str(path) != "" else Settings.PATH


## The personal bests file: the game's records_path (Records.PATH, under user://), "" when the game keeps none.
func _records_path() -> String:
	var path = g.get("records_path")
	return Records.PATH if path == null else str(path)


## The game's audio_server / display_server when it has one (the test stub's recorders), else null: the real servers.
func _audio_server() -> Object:
	return g.get("audio_server") as Object


func _display_server() -> Object:
	return g.get("display_server") as Object


## From the title's Settings entry, or the pause menu's (the game stays paused under it).
func open_settings() -> void:
	if settings_open:
		return
	settings_open = true
	_settings_from_pause = pause_open
	_build_settings()


func close_settings() -> void:
	settings_open = false
	for child in settings_layer.get_children():
		settings_layer.remove_child(child)
		child.queue_free()
	if title != null and title.visible:
		title.focus_first()


func _build_settings() -> void:
	for child in settings_layer.get_children():
		settings_layer.remove_child(child)
		child.queue_free()
	var values := Settings.load_from(_settings_path())
	SettingsScreen.build(settings_layer, SettingsScreen.vm(values, _settings_from_pause, bool(g.get("world_art_on"))), Callable(self, "_on_settings_action"))


## A change is saved and applied at once: volumes on the buses, the window mode on the window, the fog for the next match.
## A slider keeps its own percent, so only the toggles rebuild the screen (never mid-drag).
func _on_settings_action(name: String, arg: Variant = null) -> void:
	match name:
		"settings_back":
			close_settings()
		"set":
			var key := str(arg[0])
			Settings.set_value(key, arg[1], _settings_path())
			var values := Settings.load_from(_settings_path())
			if key.begins_with("audio/"):
				Settings.apply_audio(values, _audio_server())
			elif key == "video/window_mode":
				Settings.apply_window(values, _display_server())
			if not key.begins_with("audio/"):
				_build_settings()


# ---------------------------------------------------------------- strategic map (board 11)

## M: opens the map over the HUD. The simulation keeps running; the world takes no input until it closes.
func open_region() -> void:
	if region_open or scrim != null or not hud.visible or paused():
		return
	var sg := _snapshot_and_ground()
	if VmMaps.region_map(sg[0], sg[1]).is_empty():
		return  # no ground layer or no named regions yet: nothing honest to draw
	region_open = true
	_region_clock = 0.0
	_refresh_region(true)


func close_region() -> void:
	region_open = false
	_region_hash = 0
	for child in region_layer.get_children():
		region_layer.remove_child(child)
		child.queue_free()


## Rebuilds the map when the lenses or anything it draws changed (hash of the whole view model); never between a press and its
## release. The ground mesh is cached by Hex, so a rebuild reuses it.
func _refresh_region(force := false) -> void:
	if not region_open:
		return
	var sg := _snapshot_and_ground()
	var vm := VmMaps.region_map(sg[0], sg[1])
	if vm.is_empty():
		close_region()
		return
	vm["lens_on"] = lens_on.duplicate()
	var h := hash(vm)
	if not force and (h == _region_hash or _left_down):
		return
	_region_hash = h
	for child in region_layer.get_children():
		region_layer.remove_child(child)
		child.queue_free()
	var holder := ColorRect.new()  # swallows clicks over the whole screen
	holder.name = "RegionBackdrop"
	holder.color = Color("07101a")
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	region_layer.add_child(holder)
	RegionMap.build(region_layer, vm, Callable(self, "_on_region_action"))


func _on_region_action(name: String, arg: Variant = null) -> void:
	match name:
		"region_close":
			close_region()
		"region_lens":
			if lens_on.has(str(arg)):
				lens_on[str(arg)] = not lens_on[str(arg)]
				_refresh_region(true)
		"focus_deposit":
			close_region()
			adapter.on_action("focus_deposit", arg)


# ---------------------------------------------------------------- first-minutes briefing (board 6)

## Up while the first objective group is being worked (tutorial stages 0 to 2; on Kestrel the first three objectives,
## vm_maps.KESTREL_BRIEFING_LAST_STAGE), until the player hides it. It only exists as
## a card at the top left: once hidden or out of range its nodes are freed, so it can never block input afterwards.
func _refresh_briefing() -> void:
	var vm := {}
	if hud.visible and not briefing_dismissed and scrim == null and _has_real_ground():
		var snap = g.get("bridge_snapshot")
		if bool(g.get("world_art_on")):  # Kestrel: its own objectives (kestrel_objectives.gd); Survival keeps the tutorial's
			vm = VmMaps.kestrel_briefing(adapter.kestrel_objectives(), snap if snap is Dictionary else {}, int(g.bridge_winner))
		else:
			vm = VmMaps.briefing(int(g.tutorial_stage), snap if snap is Dictionary else {}, int(g.bridge_winner))
	adapter.briefing_up = not vm.is_empty()
	var h := hash(vm)
	if h == _briefing_hash and (briefing_layer.get_child_count() > 0) == not vm.is_empty():
		return
	if _left_down and briefing_layer.get_child_count() > 0 and not vm.is_empty():
		return
	_briefing_hash = h
	for child in briefing_layer.get_children():
		briefing_layer.remove_child(child)
		child.queue_free()
	EarlyMission.build(briefing_layer, vm, Callable(self, "_on_briefing_action"))


func _on_briefing_action(name: String, _arg: Variant = null) -> void:
	if name == "briefing_dismiss":
		briefing_dismissed = true
		adapter.briefing_up = false
		_since_vm = VM_INTERVAL
		_refresh_briefing()


# ---------------------------------------------------------------- Task 26: run drafts

## True while a run's perk draft is up (the bridge held by pause.flag until the pick).
func draft_open() -> bool:
	return not _draft_ids.is_empty()


## 1 to 9 for the number-row keys (the control-group keys), else 0.
static func _number_key(event: InputEvent) -> int:
	if not (event is InputEventKey):
		return 0
	return Keybinds.GROUPS.find(event.keycode) + 1


## Every frame the HUD runs (never while the pause menu is up). A run's pending draft (snapshot depth.run.draft) opens
## the modal and holds the bridge; once picked, the same draft never opens again unless the bridge still offers it
## DRAFT_RETRY_TICKS later (the pick did not land). A replay never drafts (the recording plays its own pick), nor does a
## decided match or one under the debrief. Reaching wave 6 in a run grows the perk pool once.
func _refresh_run() -> void:
	var snap = g.get("bridge_snapshot")
	var run := MatchConfig.run_state(snap)
	var replay := replay_mode()
	if not run.is_empty() and not replay and not _run_unlocked and int(run.get("wave", 0)) >= Settings.UNLOCK_WAVE:
		_run_unlocked = true
		if Settings.unlock_after_run(int(run.get("wave", 0)), _settings_path()):
			var pool := _perk_pool()
			notify("Perk unlocked", "%s joins the run pool (%d of 12)" % [_newest_perk(pool), MatchConfig.pool_size(pool)], T.GOOD)
	var ids: Array = []
	if not replay and hud.visible and scrim == null and int(g.bridge_winner) < 0:
		var draft: Variant = run.get("draft", null)
		if draft is Array:
			for id in draft:
				ids.append(int(id))
			ids = ids.slice(0, 3)
	if ids.is_empty() or ids != _draft_answered:
		_draft_answered = []
	elif int(g.bridge_tick) - _draft_answered_tick <= DRAFT_RETRY_TICKS:
		ids = []
	if ids == _draft_ids:
		return
	_draft_ids = ids
	_clear_draft_layer()
	if g.has_method("set_draft_hold"):
		g.set_draft_hold(not ids.is_empty())
	if not ids.is_empty():
		var vm := PerkDraft.vm(run)
		vm["cards"] = (vm.get("cards", []) as Array).slice(0, ids.size())
		PerkDraft.build(draft_layer, vm, Callable(self, "_on_draft_action"))


## The highest unlocked depth perk's name (the one a pool unlock just added).
static func _newest_perk(pool: int) -> String:
	for bit in range(11, 7, -1):
		if pool & (1 << bit):
			return PerkDraft.perk_name(bit)
	return "A perk"


func _on_draft_action(name: String, arg: Variant = null) -> void:
	if name == "perk":
		choose_draft(int(arg))


## Takes card `index`: `perk,<id>` to the bridge first, then the hold is lifted, so the pick lands on the next step.
func choose_draft(index: int) -> void:
	if index < 0 or index >= _draft_ids.size():
		return
	var id: int = _draft_ids[index]
	_draft_answered = _draft_ids.duplicate()
	_draft_answered_tick = int(g.bridge_tick)
	if g.has_method("choose_perk"):
		g.choose_perk(id)
	_draft_ids = []
	_clear_draft_layer()
	if g.has_method("set_draft_hold"):
		g.set_draft_hold(false)
	notify("Perk drafted", "%s: %s" % [PerkDraft.perk_name(id), PerkDraft.perk_description(id)], T.CYAN_HI)
	_since_vm = VM_INTERVAL  # the HUD's run line redraws on the next frame


func _clear_draft_layer() -> void:
	for child in draft_layer.get_children():
		draft_layer.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------- Task 26: replay viewer

## True while the bridge plays a recording back (the snapshot's `replay` block).
func replay_mode() -> bool:
	return not MatchConfig.replay_state(g.get("bridge_snapshot")).is_empty()


## The speed bar while a replay plays (rebuilt when what it shows changed, never between a press and its release).
func _refresh_replay_bar() -> void:
	var rs := MatchConfig.replay_state(g.get("bridge_snapshot"))
	var vm := {}
	if not rs.is_empty() and hud.visible:
		var tick := int(rs.get("tick", 0))
		var end := int(rs.get("end", 0))
		var status := "Playing"
		if int(g.bridge_winner) >= 0:
			status = "Ended: " + ("victory" if int(g.bridge_winner) == 0 else "defeat")
		elif tick >= end:
			status = "Ended"
		elif _replay_speed == "0":
			status = "Paused"
		vm = {"tick": tick, "end": end, "speed": _replay_speed, "status": status}
	var h := hash(vm)
	if h == _replay_hash and (replay_layer.get_child_count() > 0) == not vm.is_empty():
		return
	if _left_down and not vm.is_empty() and replay_layer.get_child_count() > 0:
		return
	_replay_hash = h
	for child in replay_layer.get_children():
		replay_layer.remove_child(child)
		child.queue_free()
	ReplayList.build_bar(replay_layer, vm, Callable(self, "_on_replay_action"))


func _on_replay_action(name: String, arg: Variant = null) -> void:
	match name:
		"speed":
			_replay_speed = str(arg)
			if g.has_method("write_replay_speed"):
				g.write_replay_speed(_replay_speed)
			_replay_hash = 0
			_refresh_replay_bar()
		"leave":
			leave_replay()


## Back to the title with a live match: match.json without the replay (a fresh seed at the remembered preset, an
## operation), the speed file removed, then the existing restart (restart.flag and a scene reload).
func leave_replay() -> void:
	var cfg := MatchConfig.live(MatchConfig.current)
	cfg["scenario"] = "kestrel"
	cfg["seed"] = MatchConfig.random_seed()
	cfg["difficulty"] = MatchConfig.clean_difficulty(Settings.get_value("game/difficulty", _settings_path()))
	cfg["mode"] = "operation"
	cfg = MatchConfig.with_settings(cfg, _settings_path())
	MatchConfig.current = cfg
	MatchConfig.write(_runtime_dir(), cfg)
	MatchConfig.set_auto_deploy(false)
	if g.has_method("write_replay_speed"):
		g.write_replay_speed("")
	g._restart_mission()


# ---------------------------------------------------------------- Task 26: Replays list (title)

## The title's Replays entry: the recordings in user://replays (replays_dir), newest first. `error` is shown above them.
func open_replays(error := "") -> void:
	if title == null:
		return
	if picker_open:
		close_picker()
	replays_open = true
	for child in replays_layer.get_children():
		replays_layer.remove_child(child)
		child.queue_free()
	var focus: Control = ReplayList.build(replays_layer, LiveScreens.replays_vm(ReplayList.scan(replays_dir), error), Callable(self, "_on_replays_action"))
	if focus != null and focus.is_inside_tree():
		focus.grab_focus()
	_refresh_title()


func close_replays() -> void:
	replays_open = false
	for child in replays_layer.get_children():
		replays_layer.remove_child(child)
		child.queue_free()
	_refresh_title()
	if title != null and title.visible and _launch_wait < 0.0:
		title.focus_first()


func _on_replays_action(name: String, arg: Variant = null) -> void:
	match name:
		"watch":
			watch_replay(str(arg))
		"back":
			close_replays()


## Plays the recording at `path` (absolute, from the list): match.json names it, the bridge rebuilds (in place, or after
## a reload when another map is on screen) and _await_replay deploys once the playback snapshot is there.
func watch_replay(path: String) -> void:
	if not path.is_absolute_path() or _launch_wait >= 0.0:
		return
	var cfg := MatchConfig.current
	cfg["scenario"] = "kestrel"
	cfg["replay"] = path
	MatchConfig.current = cfg
	MatchConfig.write(_runtime_dir(), cfg)
	close_replays()
	var snap = g.get("bridge_snapshot")
	var on_screen := MatchConfig.running(snap) if snap is Dictionary else ""
	if on_screen != "" and on_screen != "kestrel":
		MatchConfig.set_auto_deploy(true)
		_refresh_title()
		g._restart_mission()
		return
	_relaunch_in_place()
