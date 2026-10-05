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

const VM_INTERVAL := 0.1
## The bridge may step a frame or two after pause.flag is written; more ticks than this while paused mean it still runs
## (or has not seen the flag yet: a slow frame rate stretches that gap well past this, so the marker also recovers).
const STOP_SLACK_TICKS := 6
## The tick must stand still this long (seconds) before a marker that said "still running" says "stopped" again.
const STOP_STILL_SECONDS := 0.6
## The strategic map re-reads the snapshot this often (seconds); it redraws only when what it shows changed.
const REGION_INTERVAL := 0.5
const BRIEFING_INTERVAL := 0.2
const MINIMAP_CENTER := Vector3(16.7, 34.0, 10.0)
const MINIMAP_SPAN := 35.0

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
var _pause_seen_tick := 0
var _pause_still_s := 0.0
var _pause_moving := false  # the bridge tick moved on after the pause began and has not stood still since
var _pause_hash := 0
var minimap_view: SubViewportContainer
var _clock := 0.0
var _since_vm := VM_INTERVAL
var _left_down := false
var _marks_drawn := false


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
	pause_layer = _full_rect_layer("PauseLayer")
	title = TitleScreen.new()
	title.action.connect(_on_title_action)
	layer.add_child(title)
	title.apply(LiveScreens.title_vm(true, game.bridge_technology_total))
	title.focus_first()


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
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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


## World-space rectangle (x, z) the minimap camera shows, for the current slot shape. Empty until the slot has a size.
func minimap_world_rect() -> Rect2:
	var s: Vector2 = hud.map_slot.size
	if s.x < 1.0 or s.y < 1.0:
		return Rect2()
	var w := MINIMAP_SPAN * s.x / s.y
	return Rect2(MINIMAP_CENTER.x - w * 0.5, MINIMAP_CENTER.z - MINIMAP_SPAN * 0.5, w, MINIMAP_SPAN)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_left_down = event.pressed


## Called every frame by the game. The view model is rebuilt about ten times a second, and never while a click is
## in flight over the HUD, so a button is not replaced between its press and its release.
func process(delta: float) -> void:
	if paused():
		# Frozen: no HUD rebuild, no ticker, no log samples, and the alert clock stands still. Only the pause screens refresh.
		_watch_stop(delta)
		_since_vm += delta
		if _since_vm >= VM_INTERVAL:
			_since_vm = 0.0
			_refresh_pause()
		return
	_clock += delta
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
	if research.visible and not _left_down:  # the modal blocks everywhere: no rebuild between a press and its release
		_since_vm = 0.0
		research.apply(live_research.vm(g))
	if not hud.visible:
		return
	if _left_down and hud.blocks_point(g.mouse_position()):
		return
	_since_vm = 0.0
	hud.apply(adapter.hud_vm(_clock))
	if minimap_view.get_parent() != hud.map_slot:
		minimap_view.reparent(hud.map_slot, false)  # the assault layout draws its own slot
	minimap_view.size = hud.map_slot.size  # the Build layout reshapes the slot


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
		"deploy":
			g._deploy_mission()
		"quit":
			get_tree().quit()


## Victory or defeat debrief over a scrim. "review" removes it so the battlefield can be inspected; "restart" redeploys.
func show_debrief() -> void:
	if scrim != null:
		return
	close_region()  # the debrief owns the screen; Esc under its scrim must not reach a map left open behind it
	scrim = ColorRect.new()
	(scrim as ColorRect).color = T.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(scrim)
	var panel := Debrief.new()
	scrim.add_child(panel)
	panel.action.connect(_on_debrief_action)
	panel.apply(LiveScreens.debrief_vm(g, session_log))
	Debrief.place_in(panel, g.get_viewport().get_visible_rect().size)


func _on_debrief_action(name: String, _arg: Variant) -> void:
	match name:
		"review":
			if scrim != null:
				scrim.queue_free()
				scrim = null
		"restart":
			g._restart_mission()


# ---------------------------------------------------------------- pause menu and controls screen

## True while the pause menu or the controls screen is up: the world takes no input and the HUD does not update.
func paused() -> bool:
	return pause_open or controls_open


## True when the world must take no input: a paused game, or the strategic map covering the screen (the simulation keeps
## running behind the map, so the camera and orders just do not react to it).
func world_blocked() -> bool:
	return paused() or region_open


## What Esc does right now, most specific first: close the controls screen, close the terrain guide, close the confirm panel,
## resume, close the strategic map, close the Science modal, cancel an armed order or placement, otherwise open the pause menu ("none" while the debrief is up).
func escape_route(armed: bool) -> String:
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


## True when the match has real terrain to describe: a valid, non-flat ground model. Survival's all-Grassland layer has none
## (the client keeps its noise terrain), so the terrain guide and the briefing stay away from it. Cheap: the live game already
## holds the model; otherwise one decode of the snapshot layer.
func _has_real_ground() -> bool:
	if g.get("ground_model") != null:
		return true
	var snap = g.get("bridge_snapshot")
	return snap is Dictionary and preload("res://scripts/terrain/ground_model.gd").from_snapshot(snap) != null


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
	return vm


## Rebuilds whichever pause screen is up when its view model changed (never between a press and its release).
func _refresh_pause(force := false) -> void:
	if not paused():
		return
	var vm: Dictionary
	if controls_open:
		vm = Keybinds.vm(not _controls_over_play)
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
			g._restart_mission()  # the existing restart: restart.flag for the bridge, then the scene reloads to the title
		"quit":
			get_tree().quit()


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

## Up while the first objective group is being worked (tutorial stages 0 to 2), until the player hides it. It only exists as
## a card at the top left: once hidden or out of range its nodes are freed, so it can never block input afterwards.
func _refresh_briefing() -> void:
	var vm := {}
	if hud.visible and not briefing_dismissed and scrim == null and _has_real_ground():
		var snap = g.get("bridge_snapshot")
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
