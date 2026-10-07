extends RefCounted
## Middle-mouse drag pan (Task 2, kestrel-depth). _drag_pan is pure: screen pixels in, focus delta out. The map follows the
## cursor (grab), so the focus moves against the drag, scaled so a drag of the visible height moves one screen.
const WorldArt := preload("res://scripts/world/world_art.gd")


func test_middle_drag_moves_focus_against_the_drag(t) -> void:
	var g = load("res://scripts/earthfront_3d.gd").new()
	var d: Vector3 = g._drag_pan(Vector2(100, 0))
	t.ok(d.x < 0.0, "dragging right pans the world left")
	g.free()


func test_kestrel_north_up_drag_is_a_screen_for_a_screen(t) -> void:
	var g = load("res://scripts/earthfront_3d.gd").new()
	g.camera_yaw = 0.0
	g.camera_zoom = 10.0
	var right: Vector3 = g._drag_pan(Vector2(1080, 0), 1080.0)
	t.near(right.x, -10.0, 0.01, "a drag of the view height sideways moves the focus one zoom (ortho size) left")
	t.near(right.z, 0.0, 0.001, "no depth change on a sideways drag")
	t.eq(right.y, 0.0, "the focus stays on the ground")
	var down: Vector3 = g._drag_pan(Vector2(0, 108), 108.0)
	t.near(down.z, -10.0 / WorldArt.PITCH_SIN, 0.01, "a drag down moves the focus north (up the screen), foreshortened by the pitch")
	t.near(down.x, 0.0, 0.001, "no sideways change on a vertical drag")
	t.eq(g._drag_pan(Vector2.ZERO), Vector3.ZERO, "no drag, no pan")
	g.free()


func test_drag_follows_the_camera_yaw(t) -> void:
	var g = load("res://scripts/earthfront_3d.gd").new()
	g.camera_yaw = -0.68
	var d: Vector3 = g._drag_pan(Vector2(100, 0), 1080.0)
	var right := Vector3(cos(g.camera_yaw), 0, -sin(g.camera_yaw))
	t.near(d.normalized().dot(right), -1.0, 0.001, "a sideways drag moves along the camera's own right axis")
	g.free()


func test_the_handler_pans_with_the_middle_button(t) -> void:
	var src := (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	t.ok(src.contains("MOUSE_BUTTON_MIDDLE"), "the handler reads the middle button")
	t.ok(src.contains("camera_focus_target += _drag_pan("), "a drag moves the focus target through _drag_pan")


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Through Godot's real input pipeline: an arrow press holds its pan action (the axis _update_camera_controls reads), W/A/S/D
## hold none.
func test_arrow_keys_drive_the_pan_axes_and_wasd_do_not(t) -> void:
	for pair in [[KEY_UP, "camera_up"], [KEY_LEFT, "camera_left"], [KEY_DOWN, "camera_down"], [KEY_RIGHT, "camera_right"]]:
		_key(pair[0], true)
		t.ok(Input.is_action_pressed(pair[1]), "%s holds %s" % [OS.get_keycode_string(pair[0]), pair[1]])
		_key(pair[0], false)
		t.ok(not Input.is_action_pressed(pair[1]), "released")
	_key(KEY_RIGHT, true)
	t.eq(Input.get_axis("camera_left", "camera_right"), 1.0, "right arrow: the pan axis points right")
	_key(KEY_RIGHT, false)
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(code, true)
		for action in ["camera_up", "camera_left", "camera_down", "camera_right"]:
			t.ok(not Input.is_action_pressed(action), "%s holds no %s" % [OS.get_keycode_string(code), action])
		_key(code, false)
