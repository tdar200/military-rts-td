extends SceneTree
## Test-only runner: real viewport input events, read-only observations, screenshots.
## It never calls game commands or changes simulation state.
var game: Node3D
var qa_dir := "/tmp/earthfront-qa"
var busy := false
var last_id := -1
var elapsed := 0.0
var frame_ms: Array[float] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):
			qa_dir = arg.trim_prefix("--qa-dir=")
	call_deferred("_start")

func _start() -> void:
	root.size = Vector2i(1920, 1080)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game

func _process(delta: float) -> bool:
	if not is_instance_valid(game):
		game = current_scene as Node3D
	frame_ms.append(delta * 1000.0)
	if frame_ms.size() > 3600:
		frame_ms.pop_front()
	elapsed += delta
	if game and elapsed > 0.25 and not busy:
		elapsed = 0.0
		_observe()
		var path := qa_dir.path_join("action.json")
		if FileAccess.file_exists(path):
			var action = JSON.parse_string(FileAccess.get_file_as_string(path))
			if action is Dictionary and int(action.get("id", -1)) > last_id:
				busy = true
				_execute(action)
	return false

func _execute(action: Dictionary) -> void:
	for item in action.get("events", []):
		match String(item.get("type", "")):
			"key":
				var code := OS.find_keycode_from_string(String(item.get("key", "")))
				for down in [true, false]:
					var event := InputEventKey.new()
					event.keycode = code
					event.physical_keycode = code
					event.pressed = down
					event.ctrl_pressed = bool(item.get("ctrl", false))
					event.shift_pressed = bool(item.get("shift", false))
					root.push_input(event, true)
					await process_frame
			"click", "motion", "press", "release":
				var point := Vector2(float(item.get("x", 0)), float(item.get("y", 0)))
				root.warp_mouse(point)
				var motion := InputEventMouseMotion.new()
				motion.position = point
				motion.global_position = point
				root.push_input(motion, true)
				await process_frame
				if item.type != "motion":
					var states := [true, false] if item.type == "click" else [item.type == "press"]
					for down in states:
						var click := InputEventMouseButton.new()
						click.position = point
						click.global_position = point
						click.button_index = int(item.get("button", 1))
						click.pressed = down
						click.shift_pressed = bool(item.get("shift", false))
						click.double_click = bool(item.get("double", false))
						root.push_input(click, true)
						await process_frame
			"ui_state":
				# Presentation only (deck tab, forced assault layout, debrief); never touches the simulation.
				if item.has("tab"):
					game.ui.set_tab(String(item.tab))
				if bool(item.get("engage", false)):
					game.ui.adapter.assault.engaged = true
				if bool(item.get("debrief", false)):
					game.ui.show_debrief()
				for _i in 8:
					await process_frame
			"resize":
				root.size = Vector2i(int(item.width), int(item.height))
				await process_frame
			"capture":
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(qa_dir.path_join(String(item.name) + ".png"))
			"quit":
				quit()
	last_id = int(action.id)
	busy = false
	_observe()

## On-screen rectangle of a control after the transforms and clipping of its parents.
func _visible_rect(node: Control) -> Rect2:
	var rect: Rect2 = node.get_global_transform() * Rect2(Vector2.ZERO, node.size)
	var parent := node.get_parent()
	while parent is Control:
		if parent.clip_contents:
			rect = rect.intersection(parent.get_global_transform() * Rect2(Vector2.ZERO, parent.size))
		parent = parent.get_parent()
	return rect

## True when a click at `screen` reaches the 3D scene: on screen, off the edge-scroll band, and not over any UI surface.
func _free(screen: Vector2) -> bool:
	return Rect2(Vector2(12, 12), root.get_visible_rect().size - Vector2(24, 24)).has_point(screen) and not game.ui.blocks_point(screen)

func _observe() -> void:
	var buttons: Array = []
	for node in game.find_children("*", "Button", true, false):
		if node.is_visible_in_tree():
			var rect := _visible_rect(node)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue  # scrolled out of a clipping parent: a player cannot click it
			buttons.append({"text": node.text, "disabled": node.disabled, "x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y})
	var entities: Array = []
	for id in game.bridge_nodes:
		var node = game.bridge_nodes[id]
		if is_instance_valid(node):
			var screen: Vector2 = game.camera.unproject_position(node.global_position + Vector3.UP * 0.15)
			entities.append({"id": id, "kind": node.get_meta("kind_name", ""), "owner": node.get_meta("team", -1), "x": screen.x, "y": screen.y, "free": _free(screen)})
	var tiles: Array = []
	for tile in game.construction_zone:
		var point: Vector3 = game._hex_world(tile.x, tile.y)
		point.y = game._height_world(point.x, point.z)
		var screen: Vector2 = game.camera.unproject_position(point)
		var picked: Vector2i = game._world_to_tile(game._screen_to_ground(screen))
		tiles.append({"tx": tile.x, "ty": tile.y, "x": screen.x, "y": screen.y, "free": _free(screen), "picked_x": picked.x, "picked_y": picked.y})
	var selection: Array = []
	for unit in game.selected_units:
		if is_instance_valid(unit): selection.append(unit.get_meta("bridge_id", -1))
	var data := {"ack": last_id, "tick": game.bridge_tick, "buttons": buttons, "entities": entities, "tiles": tiles, "selection": selection,
		"build_mode": game.build_mode, "research_open": game.science_overlay.visible, "objective": game.objective_label.text,
		"window": [root.size.x, root.size.y], "viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"fps": Performance.get_monitor(Performance.TIME_FPS), "process_ms": Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"memory": Performance.get_monitor(Performance.MEMORY_STATIC), "frame_ms": frame_ms}
	var file := FileAccess.open(qa_dir.path_join("observation.next"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(qa_dir.path_join("observation.next"), qa_dir.path_join("observation.json"))
