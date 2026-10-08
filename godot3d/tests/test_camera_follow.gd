extends RefCounted
## Camera group centring and hold-F follow (kestrel-depth Task 9). A bare game instance is driven through the same pure
## functions the key handler calls: _group_tap (a second tap of the same group key within GROUP_TAP_WINDOW centres it),
## _focus_key (F down focuses the selection at once, as before; held past FOLLOW_HOLD the camera follows the selection's
## centre until F comes up) and _camera_step (one frame; any pan motion ends the follow).
const FRAME := 1.0 / 60.0


func _game() -> Node3D:
	var g = load("res://scripts/earthfront_3d.gd").new()
	g.camera_focus_zoom = 10.0
	g.camera_zoom = 10.0
	return g


## A point well inside the Survival map clamp, `dx` hex columns east and `dz` rows south of the origin corner.
func _at(g, dx: float, dz: float) -> Vector3:
	return Vector3(g.MAP_ORIGIN_X + dx * g.HEX_X, 0.0, g.MAP_ORIGIN_Z + dz * g.HEX_Z)


func _unit(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	return n


func test_a_second_tap_within_the_window_centres(t) -> void:
	var g := _game()
	t.eq(g.GROUP_TAP_WINDOW, 0.35, "the plan's window")
	t.eq(g._group_tap(2, 10.0), false, "a first tap only recalls")
	t.eq(g._group_tap(2, 10.2), true, "the same key 0.2 s later centres")
	t.eq(g._group_tap(2, 10.3), false, "a third tap starts over")
	t.eq(g._group_tap(2, 10.6), true, "a quick fourth is a double tap again")
	g.free()


func test_a_slow_or_different_second_tap_does_not_centre(t) -> void:
	var g := _game()
	t.eq(g._group_tap(3, 20.0), false, "first")
	t.eq(g._group_tap(3, 20.5), false, "0.5 s later is two single taps")
	t.eq(g._group_tap(1, 30.0), false, "group 1")
	t.eq(g._group_tap(2, 30.1), false, "then group 2: a different key never centres")
	t.eq(g._group_tap(2, 30.2), true, "group 2 twice does")
	g.free()


func test_centring_frames_the_groups_middle(t) -> void:
	var g := _game()
	var a := _unit(_at(g, 6, 6))
	var b := _unit(_at(g, 10, 8))
	g.control_groups = {4: [a, b]}
	t.eq(g._centre_on_group(4), true, "a group with units centres")
	var mid: Vector3 = (a.position + b.position) * 0.5
	t.ok(g.camera_focus_target.distance_to(mid) < 0.001, "the focus is the group's middle (got %s, want %s)" % [g.camera_focus_target, mid])
	t.eq(g._centre_on_group(7), false, "an empty slot does nothing")
	a.free()
	b.free()
	g.control_groups = {4: [a, b]}
	t.eq(g._centre_on_group(4), false, "a group whose units are gone does nothing")
	g.free()


func test_the_group_handler_centres_on_a_double_tap(t) -> void:
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.ok(src.contains("_group_tap(group, time_alive)"), "the number keys time their taps")
	t.ok(src.contains("_centre_on_group(group)"), "and centre on the second")
	t.ok(src.contains("_focus_key(true)") and src.contains("_focus_key(false)"), "F down and F up both reach the camera")


func test_hold_f_follows_a_moving_selection_for_30_frames(t) -> void:
	var g := _game()
	var a := _unit(_at(g, 6, 6))
	var b := _unit(_at(g, 8, 6))
	g.selected_units.assign([a, b])
	g.selected = a
	g._focus_key(true)
	t.ok(g.camera_focus_target.distance_to(a.position) < 0.001, "F down focuses the selection at once (the tap)")
	var step := Vector3(0.05, 0.0, 0.02)
	var following_frames := 0
	var off_frames := 0
	for frame in 30:
		a.position += step
		b.position += step
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
		var mid: Vector3 = (a.position + b.position) * 0.5
		if float(frame + 1) * FRAME >= g.FOLLOW_HOLD + FRAME * 0.5:  # past the hold (clear of the float boundary)
			following_frames += 1
			if g.camera_focus_target.distance_to(mid) > 0.001:
				off_frames += 1
	t.ok(following_frames >= 14, "held past FOLLOW_HOLD for most of the 30 frames (%d)" % following_frames)
	t.eq(off_frames, 0, "every held frame keeps the focus on the moving centre")
	t.eq(g.camera_following, true, "following")
	var mid_now: Vector3 = (a.position + b.position) * 0.5
	t.ok(g.camera_target.distance_to(mid_now) < 0.6, "the view itself trails close behind (%s)" % g.camera_target.distance_to(mid_now))
	g._focus_key(false)
	t.eq(g.camera_following, false, "F up ends the follow")
	var held_at: Vector3 = g.camera_focus_target
	a.position += Vector3(1, 0, 0)
	g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.ok(g.camera_focus_target.distance_to(held_at) < 0.001, "after release the camera stays put")
	a.free()
	b.free()
	g.free()


func test_a_short_tap_never_follows(t) -> void:
	var g := _game()
	var a := _unit(_at(g, 6, 6))
	g.selected_units.assign([a])
	g.selected = a
	g._focus_key(true)
	for frame in 5:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	g._focus_key(false)
	a.position += Vector3(2, 0, 0)
	for frame in 30:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, false, "a tap focuses but never follows")
	t.ok(g.camera_focus_target.distance_to(a.position) > 1.0, "the camera does not chase the unit after a tap")
	a.free()
	g.free()


func test_any_pan_input_cancels_the_follow(t) -> void:
	var g := _game()
	var a := _unit(_at(g, 6, 6))
	g.selected_units.assign([a])
	g.selected = a
	g._focus_key(true)
	for frame in 20:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, true, "following after 20 frames")
	g._camera_step(FRAME, Vector3(1, 0, 0), 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, false, "a pan (arrows or the screen edge) ends it")
	var after_pan: Vector3 = g.camera_focus_target
	a.position += Vector3(0, 0, 1)
	for frame in 20:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, false, "and it stays off while F is still held")
	t.ok(g.camera_focus_target.distance_to(after_pan) < 0.001, "the camera stays where the pan left it")
	# The other pan inputs: a middle drag, a minimap jump or Space, Home, a group centring.
	for cancel in ["_end_follow()"]:
		t.ok((load("res://scripts/earthfront_3d.gd") as GDScript).source_code.contains(cancel), "the game has " + cancel)
	g._focus_key(false)
	g._focus_key(true)
	for frame in 20:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, true, "a fresh hold follows again")
	g._end_follow()
	t.eq(g.camera_following, false, "_end_follow stops it")
	a.free()
	g.free()


func test_the_other_pan_inputs_end_the_follow(t) -> void:
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	var bodies := {}
	var current := ""
	for line in src.split("\n"):
		if line.begins_with("func "):
			current = line.substr(5, line.find("(") - 5)
			bodies[current] = ""
		elif current != "":
			bodies[current] += line + "\n"
	t.ok(str(bodies.get("minimap_jump", "")).contains("_end_follow()"), "a minimap click or Space ends the follow")
	t.ok(str(bodies.get("_centre_on_group", "")).contains("_end_follow()"), "a group centring ends it")
	t.ok(str(bodies.get("_input", "")).contains("_end_follow()"), "a middle drag ends it")
	t.ok(str(bodies.get("_unhandled_input", "")).contains("_end_follow()"), "Home ends it")


func test_the_selection_vanishing_ends_the_follow(t) -> void:
	var g := _game()
	var a := _unit(_at(g, 6, 6))
	g.selected_units.assign([a])
	g.selected = a
	g._focus_key(true)
	for frame in 20:
		g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	a.free()
	g._camera_step(FRAME, Vector3.ZERO, 16.0 / 9.0, 0.0)
	t.eq(g.camera_following, false, "a dead selection has no centre to follow")
	g.free()
