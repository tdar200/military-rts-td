extends RefCounted
## Guards for the per-frame costs measured in docs/ascension/perf-2026-10-05.md: each test pins one fix so the cost it
## removed does not creep back.
const GameUI = preload("res://scripts/ui/game_ui.gd")
const WorldMarks = preload("res://scripts/ui/world_marks.gd")
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const VM = preload("res://scripts/ui/vm_gameplay.gd")
const GroundModel = preload("res://scripts/terrain/ground_model.gd")
const Stub = preload("res://tests/stub_game.gd")


func _make(t) -> Array:
	var g := Stub.new()
	g.viewport = t.root
	var ui := GameUI.new()
	t.root.add_child(ui)
	ui.setup(g)
	ui.begin_operation()
	return [g, ui]


func test_the_minimap_renders_five_times_a_second_not_every_frame(t) -> void:
	var p := _make(t)
	var ui = p[1]
	ui.process(0.2)
	var view := ui.minimap_view.get_child(0) as SubViewport
	t.ok(view.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "the minimap viewport never redraws on its own every frame")
	var start: int = ui.minimap_renders
	for i in 60:
		ui.process(1.0 / 60.0)
	var renders: int = ui.minimap_renders - start
	t.ok(renders >= 4 and renders <= 5, "one second at 60 fps asks for about five minimap frames (got %d)" % renders)
	ui.hud.visible = false
	for i in 60:
		ui.process(1.0 / 60.0)
	t.eq(ui.minimap_renders - start, renders, "no minimap frames while the HUD is hidden")
	p[1].free()


func test_a_dash_off_screen_adds_nothing_to_the_stroke(t) -> void:
	var marks := WorldMarks.new()
	var view := Rect2(0, 0, 1920, 1080)
	marks._dash(PackedVector2Array([Vector2(-400, 50), Vector2(-300, 50)]), view, true)
	marks._dash(PackedVector2Array([Vector2(100, 2000), Vector2(200, 2100)]), view, true)
	t.eq(marks._segs.size(), 0, "dashes wholly outside the viewport are skipped")
	t.eq(marks._caps.size(), 0, "and so are their caps")
	marks._dash(PackedVector2Array([Vector2(-20, 500), Vector2(40, 500), Vector2(60, 520)]), view, true)
	t.eq(marks._segs, PackedVector2Array([Vector2(-20, 500), Vector2(40, 500), Vector2(40, 500), Vector2(60, 520)]), "a dash crossing the edge goes into the one multiline as segment pairs")
	t.eq(marks._caps, PackedVector2Array([Vector2(-20, 500), Vector2(60, 520)]), "with a cap at each end")
	marks.free()


func test_the_game_reads_the_pointer_from_mouse_events(t) -> void:
	var src: String = (load("res://scripts/earthfront_3d.gd") as GDScript).source_code
	# Viewport.get_mouse_position is a window-system round trip per call (0.15 to 0.65 ms measured); once a frame is too many.
	t.eq(src.count("get_mouse_position()"), 1, "only mouse_position() itself may ask the window system")
	t.ok(src.contains("pointer_position = (event as InputEventMouse).position"), "mouse events keep the pointer")
	t.ok(src.contains("mouse_exited.connect"), "and leaving the window falls back to asking")


func test_bridge_units_glide_at_the_same_speed_at_any_frame_rate(t) -> void:
	var game = (load("res://scripts/earthfront_3d.gd") as GDScript).new()
	var fast := Node3D.new()
	var slow := Node3D.new()
	for node in [fast, slow]:
		node.set_meta("glide_to", Vector3(10, 0, 0))
		node.set_meta("glide_yaw", PI * 0.5)
	game.bridge_nodes = {1: fast}
	for i in 18:
		game._glide_bridge_nodes(0.12 / 18.0)  # one snapshot poll at 150 fps
	game.bridge_nodes = {1: slow}
	game._glide_bridge_nodes(0.12)  # the same poll in a single frame
	t.near(fast.position.x, 3.8, 0.05, "a poll interval covers 38% of the way, as the per-poll step it replaced did")
	t.near(fast.position.x, slow.position.x, 0.001, "and does not depend on the frame rate")
	t.near(fast.rotation.y, slow.rotation.y, 0.001, "turning neither")
	t.ok(fast.rotation.y > 0.4 and fast.rotation.y < 0.6, "the turn covers about a third of the angle per poll")
	fast.free()
	slow.free()
	game.free()
