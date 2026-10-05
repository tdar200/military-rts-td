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
	if perf_frames != null:
		_perf_sample(delta)
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
			"perf":
				await _perf_window(item)
			"sections":
				await _sections(item)
			"tweak":
				await _tweak(item)
			"ui_sweep":
				await _ui_sweep(item)
			"eval":
				_eval(item)
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

# ---------------------------------------------------------------- perf windows (measurement only, never touches the sim)
var perf_frames = null  # Array of per-frame samples while a perf window is open

## Records every frame for `seconds`: delta, script process time, draw calls, primitives, objects, nodes, and the root
## viewport's measured CPU/GPU render time. `uncapped` lifts --max-fps and vsync for the window so fps shows real headroom.
## Writes <qa-dir>/perf_<name>.json with the raw samples and a summary.
func _perf_window(item: Dictionary) -> void:
	var seconds := float(item.get("seconds", 5.0))
	var uncapped := bool(item.get("uncapped", true))
	var old_fps := Engine.max_fps
	var old_vsync := DisplayServer.window_get_vsync_mode()
	if uncapped:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_perf_brackets()
	if _mini_rid().is_valid():
		RenderingServer.viewport_set_measure_render_time(_mini_rid(), true)
	for _i in 30:  # settle after the cap change
		await process_frame
	perf_frames = []
	perf_rebuilds = {}
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await process_frame
	var samples: Array = perf_frames
	perf_frames = null
	var wall := float(Time.get_ticks_usec() - start) / 1000.0
	Engine.max_fps = old_fps
	DisplayServer.window_set_vsync_mode(old_vsync)
	var out := {"name": item.get("name", "perf"), "seconds": wall / 1000.0, "frames": samples.size(),
		"fps": float(samples.size()) / maxf(0.001, wall / 1000.0), "uncapped": uncapped, "summary": {}, "samples": samples,
		"entities": game.bridge_nodes.size(), "units": game.units.size(), "tick": game.bridge_tick,
		"motion": _motion_summary(samples), "rebuilds": perf_rebuilds.duplicate(), "snapshot_bytes": FileAccess.get_file_as_bytes(game.runtime_directory.path_join("snapshot.json")).size()}
	for key in ["frame_ms", "node_ms", "process_ms", "draw_calls", "primitives", "objects", "nodes", "gpu_ms", "cpu_render_ms", "mini_gpu_ms", "mini_cpu_ms"]:
		var values: Array = []
		for s in samples:
			values.append(float(s[key]))
		values.sort()
		if values.is_empty():
			continue
		var total := 0.0
		for v in values:
			total += v
		out.summary[key] = {"avg": total / values.size(), "p50": values[values.size() / 2],
			"p95": values[mini(values.size() - 1, int(values.size() * 0.95))], "max": values[-1]}
	var file := FileAccess.open(qa_dir.path_join("perf_%s.json" % out.name), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()

var _perf_layer_ids := {}
var perf_rebuilds := {}
var _perf_positions := {}

## Units whose node moved this frame: under 60 fps a unit that only moves when a snapshot is polled moves in few frames.
func _perf_moved() -> int:
	var moved := 0
	for unit in game.units:
		if not is_instance_valid(unit):
			continue
		var id: int = unit.get_instance_id()
		if _perf_positions.has(id) and _perf_positions[id] != unit.position:
			moved += 1
		_perf_positions[id] = unit.position
	return moved

## Of the frames in which any unit moved, how many units moved per such frame, and the share of all frames with motion.
func _motion_summary(samples: Array) -> Dictionary:
	var frames_with_motion := 0
	for s in samples:
		if int(s.moved_units) > 0:
			frames_with_motion += 1
	return {"frames_with_motion": frames_with_motion, "frames": samples.size(),
		"share": float(frames_with_motion) / maxf(1.0, float(samples.size()))}

func _perf_sample(delta: float) -> void:
	var vp := root.get_viewport_rid()
	var layers: Dictionary = game.ui.hud._layers
	for key in layers:
		var kids: Array = layers[key].get_children()
		var id: int = kids[0].get_instance_id() if not kids.is_empty() else 0
		if _perf_layer_ids.has(key) and _perf_layer_ids[key] != id:
			perf_rebuilds[key] = int(perf_rebuilds.get(key, 0)) + 1
		_perf_layer_ids[key] = id
	for other in ["briefing_layer", "pause_layer", "region_layer"]:
		var layer = game.ui.get(other)
		if layer is Node:
			var kids: Array = layer.get_children()
			var id: int = kids[0].get_instance_id() if not kids.is_empty() else 0
			if _perf_layer_ids.has(other) and _perf_layer_ids[other] != id:
				perf_rebuilds[other] = int(perf_rebuilds.get(other, 0)) + 1
			_perf_layer_ids[other] = id
	perf_frames.append({"frame_ms": delta * 1000.0, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"node_ms": float(perf_node_us) / 1000.0, "moved_units": _perf_moved(),
		"polled": game.bridge_poll_elapsed == 0.0, "vm": game.ui._since_vm == 0.0,
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"cpu_render_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"mini_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(_mini_rid()),
		"mini_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(_mini_rid())})

func _mini_rid() -> RID:
	var view = game.ui.minimap_view.get_child(0) if game.ui.minimap_view.get_child_count() > 0 else null
	return view.get_viewport_rid() if view is SubViewport else RID()

## Node-process bracket: a first and a last Node in the process order stamp the clock, so their difference is the whole
## per-frame _process cost of the game and its UI (GDScript), independent of the renderer.
var _perf_first: Node
var _perf_last: Node
var perf_node_us := 0

func _perf_brackets() -> void:
	if _perf_first != null:
		return
	var src := GDScript.new()
	src.source_code = "extends Node\nvar stamp := 0\nvar other: Node\nvar host\nfunc _process(_d):\n\tstamp = Time.get_ticks_usec()\n\tif other != null and host != null:\n\t\thost.perf_node_us = stamp - other.stamp\n"
	src.reload()
	_perf_first = Node.new()
	_perf_first.set_script(src)
	_perf_first.process_priority = -100000
	_perf_last = Node.new()
	_perf_last.set_script(src)
	_perf_last.process_priority = 100000
	_perf_last.set("other", _perf_first)
	_perf_last.set("host", self)
	root.add_child(_perf_first)
	root.add_child(_perf_last)

## Isolation timing: calls each listed piece of per-frame or per-poll work once per frame for `frames` frames and records
## microseconds. The pieces are the same calls the game makes; repeating one on the same snapshot only re-applies it.
func _sections(item: Dictionary) -> void:
	var frames := int(item.get("frames", 120))
	var totals := {}
	var counts := {}
	for _f in frames:
		await process_frame
		var snap: Dictionary = game.bridge_snapshot if game.bridge_snapshot is Dictionary else {}
		var path: String = game.runtime_directory.path_join("snapshot.json")
		var pieces := {
			"read_file": func(): FileAccess.get_file_as_string(path),
			"json_parse": func(): JSON.parse_string(FileAccess.get_file_as_string(path)),
			"sync_ground": func(): game._sync_ground(snap),
			"sync_entities": func(): game._sync_bridge_entities(snap.get("entities", [])),
			"era_visuals": func(): game._apply_era_visuals(),
			"tutorial": func(): game._update_tutorial(),
			"hover_tile": func(): game._update_hover_tile(),
			"build_ghost": func(): game._update_build_ghost(),
			"update_units": func(): game._update_units(0.016),
			"animate_world": func(): game._animate_world(0.016),
			"session_log": func(): game.ui.session_log.observe(game),
			"update_marks": func(): game.ui._update_marks(),
			"hud_vm": func(): game.ui.adapter.hud_vm(game.ui._clock),
			"hud_apply": func(): game.ui.hud.apply(game.ui.adapter.hud_vm(game.ui._clock)),
			"briefing": func(): game.ui._refresh_briefing(),
			"minimap_draw": func(): game.ui.minimap_view.queue_redraw(),
		}
		if item.has("exprs"):
			pieces = {}
			for key in item.exprs:
				var expression := Expression.new()
				if expression.parse(String(item.exprs[key]), ["snap", "ground", "VG"]) != OK:
					push_error("perf expr: " + expression.get_error_text())
					continue
				var ground = game.ground_model
				var vg = load("res://scripts/ui/vm_gameplay.gd")
				pieces[key] = func(): expression.execute([snap, ground, vg], game)
		for key in pieces:
			var t0 := Time.get_ticks_usec()
			pieces[key].call()
			var dt := Time.get_ticks_usec() - t0
			totals[key] = int(totals.get(key, 0)) + dt
			counts[key] = int(counts.get(key, 0)) + 1
	var out := {}
	for key in totals:
		out[key] = float(totals[key]) / float(counts[key])
	var file := FileAccess.open(qa_dir.path_join("sections_%s.json" % item.get("name", "s")), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()

## A/B rendering switches for measurement only (presentation, never the sim): {"type": "tweak", "minimap": false,
## "shadows": false, "splits": 2, "shadow_distance": 60.0, "msaa": 0, "atlas": 2048}.
var _hidden_layers: Array = []

func _tweak(item: Dictionary) -> void:
	var lights: Array = []
	for n in game.find_children("*", "DirectionalLight3D", true, false):
		lights.append(n)
	if item.has("minimap"):
		var view := game.ui.minimap_view.get_child(0) as SubViewport
		var throttled: bool = "_minimap_clock" in game.ui  # the game asks for a frame every MINIMAP_INTERVAL itself
		if throttled:
			game.ui._minimap_clock = 0.0 if bool(item.minimap) else -1.0e9
		view.render_target_update_mode = (SubViewport.UPDATE_ONCE if throttled else SubViewport.UPDATE_ALWAYS) if bool(item.minimap) else SubViewport.UPDATE_DISABLED
	for light in lights:
		if not light.shadow_enabled and not item.has("shadows"):
			continue
		if item.has("shadows") and light.light_energy > 0.5:
			light.shadow_enabled = bool(item.shadows)
		if item.has("splits"):
			light.directional_shadow_mode = {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, 4: DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS}[int(item.splits)]
		if item.has("shadow_distance"):
			light.directional_shadow_max_distance = float(item.shadow_distance)
	if item.has("msaa"):
		root.msaa_3d = int(item.msaa)
	if item.has("ui_visible"):
		for layer in game.find_children("*", "CanvasLayer", true, false):
			if not bool(item.ui_visible) and layer.visible:
				layer.visible = false
				_hidden_layers.append(layer)
		if bool(item.ui_visible):
			for layer in _hidden_layers:
				layer.visible = true
			_hidden_layers.clear()
	if item.has("terrain"):
		var terrain := game.find_child("ContinuousPainterlyTerrain", true, false) as Node3D
		if terrain:
			terrain.visible = bool(item.terrain)
	if item.has("dressing"):
		for node in game.terrain_dressing:
			if is_instance_valid(node):
				node.visible = bool(item.dressing)
	if item.has("hide_groups"):
		for group in item.hide_groups:
			for node in game.get_tree().get_nodes_in_group(String(group)):
				if node is Node3D:
					node.visible = false
	if item.has("atlas"):
		RenderingServer.directional_shadow_atlas_set_size(int(item.atlas), true)
	for _i in 5:
		await process_frame

## Hides one visible UI node at a time (top-level UI children, every HUD section layer, the minimap) and measures the
## uncapped frame time without it, so the cost of each piece of the interface shows directly. Restores each one.
func _ui_sweep(item: Dictionary) -> void:
	var seconds := float(item.get("seconds", 1.5))
	var old_fps := Engine.max_fps
	var old_vsync := DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var targets := {}
	for child in game.ui.layer.get_children():
		if child is CanvasItem and child.visible:
			targets["ui/" + String(child.name) + ":" + child.get_class()] = child
	for key in game.ui.hud._layers:
		var node: CanvasItem = game.ui.hud._layers[key]
		if node.visible and node.get_child_count() > 0:
			targets["hud/" + String(key)] = node
	targets["minimap_view"] = game.ui.minimap_view
	var out := {}
	out["_baseline"] = await _sweep_measure(seconds)
	for key in targets:
		var node: CanvasItem = targets[key]
		node.visible = false
		out[key] = await _sweep_measure(seconds)
		node.visible = true
	out["_baseline_end"] = await _sweep_measure(seconds)
	Engine.max_fps = old_fps
	DisplayServer.window_set_vsync_mode(old_vsync)
	var file := FileAccess.open(qa_dir.path_join("sweep_%s.json" % item.get("name", "s")), FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()

func _sweep_measure(seconds: float) -> Dictionary:
	for _i in 10:
		await process_frame
	var frames := 0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await process_frame
		frames += 1
	var ms := float(Time.get_ticks_usec() - start) / 1000.0 / float(frames)
	return {"frame_ms": ms, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}

## Read-only probe: evaluates an Expression against the game and writes its result (JSON) to eval_<name>.json.
func _eval(item: Dictionary) -> void:
	var expression := Expression.new()
	var result: Variant = null
	if expression.parse(String(item.get("expr", "null"))) == OK:
		result = expression.execute([], game)
	var file := FileAccess.open(qa_dir.path_join("eval_%s.json" % item.get("name", "e")), FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
