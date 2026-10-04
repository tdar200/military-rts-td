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

const VM_INTERVAL := 0.1
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
	live_research = LiveResearch.new()
	research = ResearchScreen.new()
	research.visible = false
	research.action.connect(_on_research_action)
	layer.add_child(research)
	title = TitleScreen.new()
	title.action.connect(_on_title_action)
	layer.add_child(title)
	title.apply(LiveScreens.title_vm(true, game.bridge_technology_total))
	title.focus_first()


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
	_clock += delta
	session_log.observe(g)
	adapter.poll_ticker(g.objective_label.text, _clock)
	_update_marks()
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


## Hostile marks follow the 3D scene every frame while the assault layout is up, and are cleared otherwise.
func _update_marks() -> void:
	var cam: Camera3D = g.camera
	if hud.visible and cam != null and adapter.assault_active():
		var view := Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size)
		marks.set_marks(adapter.assault.marks(cam.unproject_position, view, cam.is_position_behind))
	elif _marks_drawn:
		marks.set_marks([])
	_marks_drawn = hud.visible and cam != null and adapter.assault_active()


## True when the point (viewport pixels) is over any UI surface, so the 3D scene must not react to it.
func blocks_point(point: Vector2) -> bool:
	if title != null and title.visible:
		return true
	if scrim != null or research.blocks_point(point):
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
