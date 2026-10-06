extends RefCounted
## Kestrel minimap interaction (plan 2026-10-06-kestrel-next-level, Task 8): click or drag on the minimap moves the camera,
## AlertPing rings where a human unit or building lost HP, Space jumps to the latest alert and cycles older ones. Kestrel
## only: Survival's minimap takes no clicks and draws no pings. Pings come from the player's own entities only, so they
## add nothing about hostile positions under the fog.
const GameUI = preload("res://scripts/ui/game_ui.gd")
const Stub = preload("res://tests/stub_game.gd")
const AlertPings = preload("res://scripts/ui/alert_pings.gd")
const MapMarks = preload("res://scripts/ui/components/map_marks.gd")
const VM = preload("res://scripts/ui/vm_gameplay.gd")
const KB = preload("res://scripts/ui/keybinds.gd")
const AlertChips = preload("res://scripts/ui/sections/alert_chips.gd")
const U = preload("res://tests/section_util.gd")
const KeyCap = preload("res://scripts/ui/components/key_cap.gd")
const MainScene = preload("res://main.tscn")
const WorldArt = preload("res://scripts/world/world_art.gd")
const RUNTIME := "user://minimap_interaction_runtime"
## Kestrel's map (44 x 26 hexes from origin 2.1, 1.0; columns 0.68 apart, rows 0.70, odd columns half a row lower), as
## earthfront_3d.map_world_rect() gives it: the hex centres plus half a cell on every side.
const MAP := Rect2(1.76, 0.65, 29.92, 18.55)


class JumpStub extends "res://tests/stub_game.gd":
	var map_rect := MAP

	func map_world_rect() -> Rect2:
		return map_rect

	func minimap_jump(at: Vector3) -> void:
		calls.append(["jump", at])


func _make(t, kestrel := true) -> Array:
	var g := JumpStub.new()
	g.viewport = t.root
	g.world_art_on = kestrel
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	g.mouse = Vector2(900, 500)
	ui.adapter.tab = "units"  # the Main layout: the 288 x 250 slot
	ui.process(0.2)
	return [g, ui]


func _drop(p: Array) -> void:
	p[1].free()


func _press(at: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	return e


func _motion(at: Vector2, held := true) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return e


## The slot pixel (local to the minimap) that shows world point (x, z).
func _local_of(ui, x: float, z: float) -> Vector2:
	var rect: Rect2 = ui.minimap_world_rect()
	var size: Vector2 = ui.minimap_view.size
	return Vector2((x - rect.position.x) / rect.size.x * size.x, (z - rect.position.y) / rect.size.y * size.y)


func _jumps(g) -> Array:
	return g.calls.filter(func(c): return c[0] == "jump")


# ------------------------------------------------------------------ pointer to world

func test_pointer_maps_to_the_minimap_cameras_world_rect_at_the_corners_and_centre(t) -> void:
	var p := _make(t)
	var ui = p[1]
	var size: Vector2 = ui.minimap_view.size
	t.eq(size, Vector2(288, 250), "the Main layout slot")
	var rect: Rect2 = ui.minimap_world_rect()
	var corners := [[Vector2.ZERO, rect.position], [Vector2(size.x, 0), Vector2(rect.end.x, rect.position.y)],
		[size, rect.end], [Vector2(0, size.y), Vector2(rect.position.x, rect.end.y)]]
	for c in corners:
		var w: Vector2 = GameUI.slot_to_world(c[0], size, rect)
		t.near(w.x, c[1].x, 0.001, "corner %s x" % str(c[0]))
		t.near(w.y, c[1].y, 0.001, "corner %s z" % str(c[0]))
	var centre: Vector2 = GameUI.slot_to_world(size * 0.5, size, rect)
	t.near(centre.x, GameUI.MINIMAP_CENTER.x, 0.001, "the centre pixel is the camera's x")
	t.near(centre.y, GameUI.MINIMAP_CENTER.z, 0.001, "and its z")
	# The slot is wider than tall, the camera keeps its 35-unit height: the map sits letterboxed inside, so the slot's own
	# corners are sea, past the map.
	t.ok(rect.size.x > MAP.size.x and rect.size.y > MAP.size.y, "the map is letterboxed inside the minimap's view")
	for c in corners:
		t.ok(not ui.minimap_point(c[0]).is_finite(), "slot corner %s is off the map: no point" % str(c[0]))
	_drop(p)


func test_the_mapping_is_the_inverse_of_the_marks_at_the_map_corners_and_centre(t) -> void:
	var p := _make(t)
	var ui = p[1]
	var inset := 0.05
	var points := [Vector2(MAP.position.x + inset, MAP.position.y + inset), Vector2(MAP.end.x - inset, MAP.position.y + inset),
		Vector2(MAP.end.x - inset, MAP.end.y - inset), Vector2(MAP.position.x + inset, MAP.end.y - inset), MAP.get_center()]
	for w in points:
		var at: Vector3 = ui.minimap_point(_local_of(ui, w.x, w.y))
		t.near(at.x, w.x, 0.001, "x of %s" % str(w))
		t.near(at.z, w.y, 0.001, "z of %s" % str(w))
		t.eq(at.y, 0.0, "a ground point")
	# The marks use the same rectangle: a node at a world point is drawn at the pixel that maps back to it.
	var g = p[0]
	g.world_rect = ui.minimap_world_rect()
	g.add_node(5, "Infantry", "unit", 0, Vector3(20.0, 0.0, 12.0))
	var mark: Dictionary = ui.adapter._marks()[0]
	var back: Vector3 = ui.minimap_point(Vector2(float(mark["x"]) * 288.0, float(mark["y"]) * 250.0))
	t.near(back.x, 20.0, 0.25, "mark and click agree on x (the mark is snapped to 0.005)")
	t.near(back.z, 12.0, 0.25, "and on z")
	g.bridge_nodes[5].free()
	_drop(p)


func test_the_build_layout_slot_reshapes_the_mapping(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.adapter.tab = "build"
	ui.process(0.2)
	t.eq(ui.minimap_view.size, Vector2(322, 222), "the Build layout slot")
	var at: Vector3 = ui.minimap_point(_local_of(ui, 10.0, 5.0))
	t.near(at.x, 10.0, 0.001, "x through the wider slot")
	t.near(at.z, 5.0, 0.001, "z through the wider slot")
	t.near(ui.minimap_world_rect().size.x / 35.0, 322.0 / 222.0, 0.001, "the view is 35 high and the slot's aspect wide")
	_drop(p)


# ------------------------------------------------------------------ click and drag

func test_a_click_on_the_map_moves_the_camera_and_is_kept_from_the_world(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	t.eq(ui.minimap_view.mouse_filter, Control.MOUSE_FILTER_PASS, "Kestrel: the minimap takes the pointer")
	var used: bool = ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	t.ok(used, "the press is used here, so it never reaches the world's selection or orders")
	var j := _jumps(g)
	t.eq(j.size(), 1, "one camera jump")
	t.near(j[0][1].x, 12.0, 0.001, "to the clicked x")
	t.near(j[0][1].z, 8.0, 0.001, "and z")
	t.ok(ui._minimap_event(_press(_local_of(ui, 12.0, 8.0), MOUSE_BUTTON_LEFT, false)), "its release is used too")
	t.eq(g.calls.filter(func(c): return c[0] != "jump"), [], "no selection, order or focus call")
	t.ok(ui.minimap_view.gui_input.is_connected(ui._on_minimap_input), "the minimap's own input feeds the handler")
	_drop(p)


func test_clicks_outside_the_map_rect_do_nothing_and_still_stop_there(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	for at in [Vector2(2, 2), Vector2(286, 3), Vector2(4, 248), _local_of(ui, MAP.end.x + 0.2, 9.0), _local_of(ui, 16.0, MAP.position.y - 0.2)]:
		t.ok(ui._minimap_event(_press(at)), "a press on the sea around the map is still kept from the world")
		ui._minimap_event(_press(at, MOUSE_BUTTON_LEFT, false))
	t.eq(_jumps(g), [], "and moves nothing")
	t.ok(not ui._minimap_drag, "and starts no drag")
	ui._minimap_event(_motion(_local_of(ui, 12.0, 8.0)))
	t.eq(_jumps(g), [], "a held pointer after an off-map press drags nothing")
	_drop(p)


func test_right_click_wheel_and_middle_click_on_the_minimap_do_nothing(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	var inside := _local_of(ui, 12.0, 8.0)
	g.attack_move_armed = true
	for b in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		t.ok(ui._minimap_event(_press(inside, b)), "button %d is kept from the world (no order, no zoom)" % b)
		t.ok(ui._minimap_event(_press(inside, b, false)), "and its release")
	t.eq(g.calls, [], "nothing reached the game")
	t.ok(g.attack_move_armed, "an armed attack-move stays armed for a click on the battlefield")
	_drop(p)


func test_dragging_follows_the_pointer_clamped_to_the_map_and_ends_on_release(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	t.ok(ui._minimap_drag, "a press on the map starts a drag")
	t.ok(ui._minimap_event(_motion(_local_of(ui, 14.0, 9.0))), "the drag's motion is used here")
	t.ok(ui._minimap_event(_motion(Vector2(-40, -40))), "past the slot's corner too (the GUI keeps sending to the pressed control)")
	t.ok(ui._minimap_event(_motion(_local_of(ui, MAP.end.x + 3.0, MAP.end.y + 3.0))), "and past the far corner")
	var j := _jumps(g)
	t.eq(j.size(), 4, "press plus three moves")
	t.near(j[1][1].x, 14.0, 0.001, "follows x")
	t.near(j[1][1].z, 9.0, 0.001, "follows z")
	t.near(j[2][1].x, MAP.position.x, 0.001, "clamped to the map's west edge")
	t.near(j[2][1].z, MAP.position.y, 0.001, "and north edge")
	t.near(j[3][1].x, MAP.end.x, 0.001, "clamped to the east edge")
	t.near(j[3][1].z, MAP.end.y, 0.001, "and south edge")
	t.ok(ui._minimap_event(_press(Vector2(-40, -40), MOUSE_BUTTON_LEFT, false)), "the release ends it, wherever it lands")
	t.ok(not ui._minimap_drag, "no drag")
	t.ok(not ui._minimap_event(_motion(_local_of(ui, 13.0, 9.0), false)), "a plain move over the minimap is not ours")
	t.eq(_jumps(g).size(), 4, "and moves nothing")
	_drop(p)


func test_a_release_that_never_came_does_not_leave_the_drag_stuck(t) -> void:
	var p := _make(t)
	var g = p[0]
	var ui = p[1]
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	t.ok(not ui._minimap_event(_motion(_local_of(ui, 13.0, 8.0), false)), "a move with the button up (released elsewhere) ends it")
	t.ok(not ui._minimap_drag, "drag cleared")
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.ok(not ui._minimap_drag, "losing the window's focus clears it")
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	ui.open_pause()
	t.ok(not ui._minimap_drag, "opening the pause menu clears it")
	var before := _jumps(g).size()
	t.ok(not ui._minimap_event(_press(_local_of(ui, 12.0, 8.0))), "while paused the minimap takes nothing")
	t.eq(_jumps(g).size(), before, "and jumps nowhere")
	ui.close_pause()
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	t.ok(ui._minimap_drag, "a new drag after resuming")
	g.world_art_on = false
	ui.process(0.2)
	t.ok(not ui._minimap_drag, "turning the feature off clears it")
	g.world_art_on = true
	ui.process(0.2)
	# Live QA: a click that focuses the window loses the GUI's mouse focus, so the release reaches the viewport (_input)
	# but never the minimap. The next frame ends the drag anyway.
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	ui._input(_press(_local_of(ui, 12.0, 8.0), MOUSE_BUTTON_LEFT, false))
	t.ok(ui._minimap_drag, "the release seen by the viewport leaves the drag for the minimap's own release this frame")
	ui.process(0.05)
	t.ok(not ui._minimap_drag, "a release the minimap never got ends the drag on the next frame")
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	ui._input(_press(_local_of(ui, 12.0, 8.0), MOUSE_BUTTON_LEFT, false))
	t.ok(ui._minimap_event(_press(_local_of(ui, 12.0, 8.0), MOUSE_BUTTON_LEFT, false)), "the minimap's own release is still ours")
	ui.process(0.05)
	ui._minimap_event(_press(_local_of(ui, 12.0, 8.0)))
	ui.process(0.05)
	t.ok(ui._minimap_drag, "a later drag is not ended by the earlier release")
	_drop(p)


func test_a_stray_release_from_a_world_drag_passes_on(t) -> void:
	var p := _make(t)
	var ui = p[1]
	t.ok(not ui._minimap_event(_press(_local_of(ui, 12.0, 8.0), MOUSE_BUTTON_LEFT, false)), "a release with no minimap drag (a box select that ended here) is not ours: the world ends its box")
	_drop(p)


func test_an_armed_placement_or_order_survives_a_minimap_click(t) -> void:
	var scene := _kestrel_scene()
	scene.build_mode = "Barracks"
	scene.attack_move_armed = true
	var zoom: float = scene.camera_focus_zoom
	scene.minimap_jump(Vector3(14.0, 0.0, 9.0))
	t.eq(scene.build_mode, "Barracks", "the placement stays armed: a minimap click only moves the camera")
	t.ok(scene.attack_move_armed, "attack-move stays armed")
	t.eq(scene.camera_focus_zoom, zoom, "the zoom is kept")
	var want: Vector3 = WorldArt.clamp_focus(Vector3(14.0, 0.0, 9.0), scene._zoom_limits().x, scene.camera_aspect, float(WorldArt.CAMERA.yaw), scene._art_bounds())
	t.ok(scene.camera_focus_target.is_equal_approx(want), "the focus is the point under the camera's own clamp")
	t.ok(scene.camera_target.is_equal_approx(want), "and the camera is there at once (no glide behind a drag)")
	scene.minimap_jump(Vector3(-50.0, 0.0, 90.0))
	var edge: Vector3 = WorldArt.clamp_focus(Vector3(-50.0, 0.0, 90.0), scene._zoom_limits().x, scene.camera_aspect, float(WorldArt.CAMERA.yaw), scene._art_bounds())
	t.ok(scene.camera_focus_target.is_equal_approx(edge), "a far point is clamped like a pan")
	var r: Rect2 = scene.map_world_rect()
	t.near(r.position.x, MAP.position.x, 0.001, "map rect west")
	t.near(r.position.y, MAP.position.y, 0.001, "map rect north")
	t.near(r.size.x, MAP.size.x, 0.001, "map rect width")
	t.near(r.size.y, MAP.size.y, 0.001, "map rect height")
	_done(scene)


# ------------------------------------------------------------------ AlertPings

func test_a_ping_lives_three_seconds_and_pulses_from_its_age(t) -> void:
	var pings := AlertPings.new()
	t.ok(pings.hit(Vector3(10, 0, 8), 5.0), "the first hit makes a ping")
	t.eq(pings.live(5.0).size(), 1, "live at once")
	t.near(pings.live(6.5)[0]["age"], 1.5, 0.0001, "age is the clock since the hit")
	t.eq(pings.live(7.999).size(), 1, "still live just before 3 s")
	t.eq(pings.live(8.0).size(), 0, "gone at exactly 3 s")
	t.eq(pings.live(4.0).size(), 0, "not live before it was made")
	t.near(AlertPings.pulse(0.0)["phase"], 0.0, 0.0001, "a pulse starts at its hit")
	t.near(AlertPings.pulse(0.25)["phase"], 0.25, 0.0001, "and grows with age")
	t.near(AlertPings.pulse(1.25)["phase"], 0.25, 0.0001, "once a second")
	t.near(AlertPings.pulse(2.9)["phase"], 0.9, 0.0001, "three pulses in a life")
	t.eq(AlertPings.pulse(1.7), AlertPings.pulse(1.7), "the same age draws the same ring (no randomness)")
	t.near(AlertPings.pulse(0.5)["fade"], 1.0, 0.0001, "full strength while young")
	t.ok(AlertPings.pulse(2.9)["fade"] < 0.3, "fading out at the end")
	t.ok(pings.active(7.9) and not pings.active(8.0), "active while a ring is live")


func test_hits_merge_within_one_and_a_half_seconds_and_three_tiles(t) -> void:
	var pings := AlertPings.new()
	pings.hit(Vector3(10, 0, 8), 0.0)
	t.ok(not pings.hit(Vector3(10.5, 0, 8.5), 0.4), "a hit nearby inside 1.5 s merges")
	t.ok(not pings.hit(Vector3(10, 0, 8 + 2.0), 1.49), "2 world units (under three tiles) away merges")
	t.eq(pings.live(1.5).size(), 1, "one ring")
	t.ok(pings.hit(Vector3(10, 0, 8 + 2.2), 1.0), "more than three tiles away is its own ping")
	t.ok(pings.hit(Vector3(10, 0, 8), 2.0), "the same place 2 s later is a new ping")
	t.eq(pings.live(2.0).size(), 3, "three rings")
	t.near(AlertPings.MERGE_RADIUS, 3.0 * 0.70, 0.0001, "three tiles at the row pitch")


func test_live_pings_are_capped_and_the_oldest_goes_first(t) -> void:
	var pings := AlertPings.new()
	for i in 9:
		pings.hit(Vector3(4.0 * i, 0, 5), 0.1 * i)
	var live: Array = pings.live(0.9)
	t.eq(live.size(), AlertPings.MAX_LIVE, "at most six rings")
	t.eq(AlertPings.MAX_LIVE, 6, "six")
	t.near(live[0]["pos"].x, 12.0, 0.0001, "the three oldest went first")
	t.near(live[live.size() - 1]["pos"].x, 32.0, 0.0001, "the newest is kept")


func test_space_jumps_to_the_newest_alert_then_cycles_older_ones(t) -> void:
	var pings := AlertPings.new()
	t.ok(not pings.jump(0.0).is_finite(), "no alert: nothing to jump to")
	for i in 7:
		pings.hit(Vector3(4.0 * i, 0, 5), 1.0 * i)
	t.eq(pings.history.size(), AlertPings.MAX_HISTORY, "five alerts kept")
	t.eq(AlertPings.MAX_HISTORY, 5, "five")
	t.near(pings.jump(10.0).x, 24.0, 0.0001, "the first press goes to the newest")
	t.near(pings.jump(10.5).x, 20.0, 0.0001, "a quick second press to the one before")
	t.near(pings.jump(11.0).x, 16.0, 0.0001, "then older")
	t.near(pings.jump(11.5).x, 12.0, 0.0001, "older")
	t.near(pings.jump(12.0).x, 8.0, 0.0001, "the oldest kept")
	t.near(pings.jump(12.5).x, 24.0, 0.0001, "and round again")
	t.near(pings.jump(12.5 + AlertPings.CYCLE_WINDOW + 0.01).x, 24.0, 0.0001, "after a pause the next press starts at the newest")
	pings.hit(Vector3(25.0, 0, 5.5), 20.0)
	t.eq(pings.history.size(), 5, "a new hit at a place already listed moves it to the front, no duplicate")
	t.near(pings.history[0].x, 25.0, 0.0001, "newest first")


# ------------------------------------------------------------------ the HUD: marks and the alert chip

func test_live_pings_are_minimap_marks_and_feed_the_alert_chip(t) -> void:
	var g := JumpStub.new()
	g.use_kestrel()
	g.alert_pings = AlertPings.new()
	g.clock = 3.0
	var adapter = load("res://scripts/ui/live_adapter.gd").new(g)
	t.eq(adapter._marks().filter(func(m): return m["k"] == "p"), [], "no hit, no ping mark")
	var plain: Dictionary = adapter._with_gameplay({})["alert"]
	t.ok(not plain.has("jump"), "no alert yet: the chip is the wave timer alone")
	g.alert_pings.hit(Vector3(20, 0, 15), 3.0)
	var marks: Array = adapter._marks().filter(func(m): return m["k"] == "p")
	t.eq(marks.size(), 1, "one ping mark")
	t.near(float(marks[0]["x"]), 0.5, 0.001, "placed like the unit marks (x)")
	t.near(float(marks[0]["y"]), 0.5, 0.001, "and y")
	t.eq(float(marks[0]["t"]), 3.0, "it carries its hit time, so the slice holds still while it pulses")
	var alert: Dictionary = adapter._with_gameplay({})["alert"]
	t.eq(int(alert["jump"]), 1, "the chip knows there is an alert to jump to")
	t.eq(str(alert["key"]), "Space", "with the bound key's cap")
	t.ok(bool(alert["attack"]), "and that a ring is live")
	t.eq(alert["seconds"], VM.next_alert(g.bridge_snapshot)["seconds"], "the wave timer stays")
	g.clock = 6.0
	t.eq(adapter._marks().filter(func(m): return m["k"] == "p"), [], "the mark is gone at 3 s")
	alert = adapter._with_gameplay({})["alert"]
	t.ok(not alert.has("attack") and int(alert["jump"]) == 1, "the alert can still be jumped to")


func test_next_alert_takes_the_ping_feed(t) -> void:
	t.eq(VM.next_alert({"next_wave_ticks": 90}, {}), VM.next_alert({"next_wave_ticks": 90}), "no feed: unchanged")
	var fed := VM.next_alert({"next_wave_ticks": 90}, {"jump": 2, "key": "Space", "attack": true})
	t.eq(fed["seconds"], 3, "the timer")
	t.eq(fed["jump"], 2, "how many alerts Space cycles")
	t.ok(fed["attack"], "a ring is live")
	var bare := VM.next_alert({}, {"jump": 1, "key": "Space"})
	t.eq(bare.get("seconds", -1), -1, "no timer invented")
	t.eq(bare["jump"], 1, "the jump alone")


func _has_cap(root: Node, cap: String) -> bool:
	for n in root.find_children("*", "Control", true, false):
		if n.get_script() == KeyCap and str(n.get("label")) == cap:
			return true
	return false


func test_the_alert_chip_shows_the_space_cap_only_with_an_alert(t) -> void:
	var root := Control.new()
	AlertChips.build(root, {"alert": {"label": "Wave 02", "seconds": 75}})
	t.ok(not _has_cap(root, "Space"), "the wave timer alone has no cap (Survival, or before any hit)")
	root.free()
	var fed := Control.new()
	AlertChips.build(fed, {"alert": {"label": "Wave 02", "seconds": 75, "jump": 2, "key": "Space", "attack": true}})
	t.ok(U.has_text(fed, "Next alert") and U.has_text(fed, "01:15"), "the timer stays")
	t.ok(_has_cap(fed, "Space"), "the Space cap shows there is an alert to jump to")
	fed.free()
	var bare := Control.new()
	AlertChips.build(bare, {"alert": {"jump": 1, "key": "Space"}})
	t.ok(U.has_text(bare, "Last alert") and _has_cap(bare, "Space"), "without a timer the chip names the jump")
	bare.free()


func test_map_marks_draw_a_ring_from_the_clock_and_hold_still_without_it(t) -> void:
	t.eq(MapMarks.ring(2.0, 1.9), {}, "nothing before the hit")
	t.eq(MapMarks.ring(2.0, 5.0), {}, "nothing at 3 s")
	var a: Dictionary = MapMarks.ring(2.0, 2.0)
	var b: Dictionary = MapMarks.ring(2.0, 2.5)
	t.ok(b["radius"] > a["radius"], "the ring grows through a pulse")
	t.ok(b["alpha"] < a["alpha"], "and fades as it grows")
	t.eq(MapMarks.ring(2.0, 3.7), MapMarks.ring(2.0, 3.7), "deterministic")
	var m := MapMarks.new()
	m.setup([{"x": 0.5, "y": 0.5, "k": "f"}], {})
	t.ok(not m.set_clock(4.0), "no ping: the clock asks for no redraw")
	m.setup([{"x": 0.5, "y": 0.5, "k": "p", "t": 3.0}], {})
	t.ok(m.set_clock(4.0), "a ping redraws with the clock")
	t.eq(m.get_child_count(), 0, "drawn by the control itself: no node per ping")
	m.free()


# ------------------------------------------------------------------ the game: hits, pause, Space

class UIStub extends Node:
	var session_log := Log.new()
	var hud := Control.new()
	var blocked := false

	func set_tab(_tab: String) -> void:
		pass

	func notify(_title: String, _body: String, _color: Color) -> void:
		pass

	func structure_attacked(_id: int, _kind: String, _pos: Vector3, _cell: Array) -> bool:
		return false

	func route_key(_event: InputEvent, _armed := false) -> bool:
		return false

	func world_blocked() -> bool:
		return blocked

	class Log:
		func unit_added(_kind: String, _team: int, _category: String) -> void:
			pass

		func unit_removed(_kind: String, _team: int, _category: String) -> void:
			pass


func _snap() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/kestrel_snapshot.json"))


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene.runtime_directory = RUNTIME
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	scene.ui = UIStub.new()
	return scene


func _survival_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene.runtime_directory = RUNTIME
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var snap := _snap()
	snap["ground"] = "g".repeat(44 * 26)
	scene._sync_ground(snap)
	scene.ui = UIStub.new()
	return scene


func _done(scene: Node3D) -> void:
	if scene.ui != null:
		scene.ui.hud.free()
		scene.ui.free()
	scene.free()


func _entity(scene, id: int, kind: String, owner: int, tile: Vector2i, hp := 100, category := "unit") -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": category, "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * hp, "max_hp_bits": 65536 * 100, "construction": 0, "construction_total": 100}


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_a_human_unit_or_building_losing_hp_pings_and_a_hostile_never_does(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.alert_pings != null, "Kestrel keeps alert pings")
	var rifle := _entity(scene, 1, "Infantry", 0, Vector2i(10, 10))
	var barracks := _entity(scene, 2, "Barracks", 0, Vector2i(20, 12), 100, "building")
	var alien := _entity(scene, 3, "Infantry", 1, Vector2i(30, 8))
	scene.bridge_initialized = false
	scene._sync_bridge_entities([rifle, barracks, alien])
	t.eq(scene.alert_pings.live(scene.alert_clock()).size(), 0, "no hit, no ping")
	var hurt_alien := alien.duplicate()
	hurt_alien["hp_bits"] = 65536 * 40
	scene._sync_bridge_entities([rifle, barracks, hurt_alien])
	t.eq(scene.alert_pings.live(scene.alert_clock()).size(), 0, "a hostile losing HP adds nothing (pings only say where the player's own things are)")
	var hurt_rifle := rifle.duplicate()
	hurt_rifle["hp_bits"] = 65536 * 80
	scene._sync_bridge_entities([hurt_rifle, barracks, hurt_alien])
	var live: Array = scene.alert_pings.live(scene.alert_clock())
	t.eq(live.size(), 1, "a rifleman hit pings")
	var at: Vector3 = scene._hex_world(10, 10)
	t.near(live[0]["pos"].x, at.x, 0.01, "at its x")
	t.near(live[0]["pos"].z, at.z, 0.01, "and z")
	var hurt_barracks := barracks.duplicate()
	hurt_barracks["hp_bits"] = 65536 * 90
	scene._sync_bridge_entities([hurt_rifle, hurt_barracks, hurt_alien])
	t.eq(scene.alert_pings.live(scene.alert_clock()).size(), 2, "a building hit far from it pings too")
	_done(scene)


func test_pause_freezes_the_ping_clock(t) -> void:
	var scene := _kestrel_scene()
	scene.world_fx.advance(4.0)
	t.near(scene.alert_clock(), scene.world_fx.time, 0.0001, "pings run on the effects clock")
	scene._alert_ping(Vector3(10, 0, 8))
	scene._advance_fx(1.0)
	t.near(scene.alert_pings.live(scene.alert_clock())[0]["age"], 1.0, 0.0001, "ages with the game")
	scene.set_sim_paused(true)
	scene._advance_fx(5.0)
	t.near(scene.alert_pings.live(scene.alert_clock())[0]["age"], 1.0, 0.0001, "frozen while paused, so it is still live")
	scene.set_sim_paused(false)
	scene._advance_fx(2.0)
	t.eq(scene.alert_pings.live(scene.alert_clock()).size(), 0, "and expires 3 s of play after the hit")
	_done(scene)


func test_space_jumps_to_the_latest_alert_cycles_and_is_quiet_without_one(t) -> void:
	var scene := _kestrel_scene()
	scene.mission_deployed = true
	var start: Vector3 = scene.camera_focus_target
	scene._unhandled_input(_key(KB.JUMP_ALERT))
	t.eq(scene.camera_focus_target, start, "no alert: Space does nothing (and no toast: nothing is announced)")
	var a := Vector3(12.0, 0.0, 9.0)
	var b := Vector3(20.0, 0.0, 12.0)
	scene._alert_ping(a)
	scene.world_fx.advance(0.5)
	scene._alert_ping(b)
	scene.build_mode = "PowerPlant"
	scene._unhandled_input(_key(KB.JUMP_ALERT))
	var clamp := func(p: Vector3) -> Vector3: return WorldArt.clamp_focus(p, scene._zoom_limits().x, scene.camera_aspect, float(WorldArt.CAMERA.yaw), scene._art_bounds())
	t.ok(scene.camera_focus_target.is_equal_approx(clamp.call(b)), "the first press frames the newest alert")
	t.eq(scene.build_mode, "PowerPlant", "an armed placement stays armed")
	scene.time_alive += 0.4
	scene._unhandled_input(_key(KB.JUMP_ALERT))
	t.ok(scene.camera_focus_target.is_equal_approx(clamp.call(a)), "a second press soon after goes to the older one")
	scene.ui.blocked = true
	scene.time_alive += 0.4
	scene._unhandled_input(_key(KB.JUMP_ALERT))
	t.ok(scene.camera_focus_target.is_equal_approx(clamp.call(a)), "paused or under the strategic map, Space does nothing")
	_done(scene)


func test_survival_has_no_pings_no_minimap_clicks_and_no_space(t) -> void:
	var scene := _survival_scene()
	t.ok(not scene.world_art_on, "Survival")
	t.eq(scene.alert_pings, null, "no alert pings")
	scene._alert_ping(Vector3(10, 0, 8))
	t.eq(scene.alert_pings, null, "a hit makes none")
	# (A live Survival hit would sound its legacy tone, which needs the tree; the branch is pinned at source level instead.)
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.ok(src.contains("\t\t\tif world_art_on and int(entity_data.get(\"owner\", 0)) == HUMAN:\n\t\t\t\t_alert_ping(destination)"), "the HP-drop branch pings only on Kestrel and only for the player's own entities")
	t.eq(src.count("_alert_ping("), 2, "one call site and the definition")
	scene.mission_deployed = true
	var start: Vector3 = scene.camera_focus_target
	scene._unhandled_input(_key(KB.JUMP_ALERT))
	scene.minimap_jump(Vector3(5, 0, 5))
	t.eq(scene.camera_focus_target, start, "Space and the minimap move no Survival camera")
	_done(scene)
	var p := _make(t, false)
	var g = p[0]
	var ui = p[1]
	t.eq(ui.minimap_view.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Survival's minimap takes no pointer, as before")
	t.ok(not ui._minimap_event(_press(_local_of(ui, 12.0, 8.0))), "and its handler takes nothing")
	t.eq(_jumps(g), [], "no jump")
	t.eq(ui.adapter._marks().filter(func(m): return m["k"] == "p"), [], "no ping marks")
	_drop(p)


# ------------------------------------------------------------------ the key

func test_space_is_free_bound_once_and_listed_only_on_kestrel(t) -> void:
	t.eq(KB.JUMP_ALERT, KEY_SPACE, "Space jumps to the latest alert")
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue  # Godot's built-in GUI actions act only on a focused control; the HUD's buttons take no focus
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		t.ok(not InputMap.event_is_action(ev, action), "Space is also the project action " + str(action))
	var owners: Array = []
	var map: Dictionary = (KB as GDScript).get_script_constant_map()
	for name in map:
		if name in ["JUMP_ALERT", "KESTREL_ONLY", "CAPS"]:
			continue  # Space itself, the list of Kestrel keys and the cap names
		var v: Variant = map[name]
		if (v is int and v == KEY_SPACE) or (v is Array and KEY_SPACE in v) or (v is Dictionary and v.has(KEY_SPACE)):
			owners.append(name)
	t.eq(owners, [], "no other binding uses Space")
	t.ok(KEY_SPACE in KB.shown_codes(true), "the Kestrel controls screen lists Space")
	t.ok(not (KEY_SPACE in KB.shown_codes()), "Survival's does not (Space does nothing there)")
	var labels: Array = []
	for g in KB.groups(true):
		for r in g["rows"]:
			labels.append(r["label"])
	t.ok("Jump to alert" in labels and "Jump on minimap" in labels, "both Kestrel rows")
	for g in KB.groups():
		for r in g["rows"]:
			t.ok(not str(r["label"]).begins_with("Jump to alert") and r["label"] != "Jump on minimap", "Survival has no minimap or alert jump row")
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.eq(src.split("Keybinds.JUMP_ALERT").size() - 1, 1, "Space is handled in exactly one place")

