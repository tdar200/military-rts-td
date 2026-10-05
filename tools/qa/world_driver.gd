extends "ui_driver.gd"
## QA world driver: ui_driver plus two presentation-only events for world-art captures. It moves the camera and hides
## canvas layers for one frame; it never sends a game command or changes simulation state.
## Events must be sent in their own action: {"events": [{"type": "world_shot", ...}]}.

const WORLD_EVENTS := ["world_shot", "probe"]
## launch_ui.py passes --qa-xvfb only for its private Xvfb display. On a real display warp_mouse would move the user's cursor.
var _on_xvfb := OS.get_cmdline_user_args().has("--qa-xvfb")


func _execute(action: Dictionary) -> void:
	var events: Array = action.get("events", [])
	var mine := events.filter(func(e): return String(e.get("type", "")) in WORLD_EVENTS)
	if mine.is_empty():
		await super._execute(action)
		return
	for item in events:
		match String(item.get("type", "")):
			"world_shot":
				await _world_shot(item)
			"probe":
				_probe(item)
			_:
				push_error("world_driver: mix world events with other events in separate actions")
	last_id = int(action.id)
	busy = false
	_observe()


func _world_shot(item: Dictionary) -> void:
	var focus: Vector3 = game.home_focus() if String(item.get("focus", "")) == "home" else game._hex_world(int(item.tile[0]), int(item.tile[1]))
	var zoom := float(item.get("zoom", game.camera_focus_zoom))
	var centre := root.get_visible_rect().size * 0.5
	if _on_xvfb:
		root.warp_mouse(centre)  # off the edge-scroll band
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	root.push_input(motion, true)
	game.camera_cinematic = 0.0
	game.camera_focus_target = focus
	game.camera_target = focus
	game.camera_focus_zoom = zoom
	game.camera_zoom = zoom
	for _i in 12:
		await process_frame
	var hidden: Array = []
	for layer in game.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not layer.get_meta("world_art", false):
			layer.visible = false
			hidden.append(layer)
	# The game's _process re-shows the hover marker every frame from the pointer (parked at the centre above), so toggling
	# `visible` here lost the race and every frame carried the outline. Render layers are never touched by the game: with
	# none set no camera draws the marker, whatever _update_hover_tile decides.
	var hover_layers := 0
	if is_instance_valid(game.hover_tile):
		hover_layers = game.hover_tile.layers
		game.hover_tile.layers = 0
	await process_frame
	RenderingServer.force_draw(false)
	var name := String(item.get("name", "world"))
	root.get_texture().get_image().save_png(qa_dir.path_join(name + ".png"))
	var points := {}
	var sw: Dictionary = item.get("swatches", {})
	for glyph in sw:
		var w: Vector3 = game._hex_world(int(sw[glyph][0]), int(sw[glyph][1]))
		w.y = game._height_world(w.x, w.z)
		var on: bool = not game.camera.is_position_behind(w)
		var p: Vector2 = game.camera.unproject_position(w)
		points[glyph] = [p.x, p.y, on and root.get_visible_rect().has_point(p)]
	var hover_drawn: bool = is_instance_valid(game.hover_tile) and game.hover_tile.is_visible_in_tree() and game.hover_tile.layers != 0
	var data := {"camera": {"yaw": game.camera_yaw, "zoom": game.camera_zoom, "focus": [game.camera_target.x, game.camera_target.z]},
		"hover_drawn": hover_drawn,
		"swatches": points, "fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0}
	FileAccess.open(qa_dir.path_join(name + ".json"), FileAccess.WRITE).store_string(JSON.stringify(data))
	for layer in hidden:
		layer.visible = true
	if is_instance_valid(game.hover_tile):
		game.hover_tile.layers = hover_layers


func _screen_rect(g: GeometryInstance3D) -> Rect2:
	var box: AABB = g.get_aabb()
	var rect := Rect2()
	var first := true
	for i in 8:
		var corner: Vector3 = g.global_transform * box.get_endpoint(i)
		if game.camera.is_position_behind(corner):
			return Rect2()
		var p: Vector2 = game.camera.unproject_position(corner)
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	return rect


func _colour_of(g: GeometryInstance3D) -> Dictionary:
	var mat: Material = g.material_override
	if mat == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		mat = (g as MeshInstance3D).get_active_material(0)
	if mat is StandardMaterial3D:
		var s := mat as StandardMaterial3D
		return {"colour": s.albedo_color.to_html(true), "transparent": s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			"unshaded": s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED}
	return {"colour": "shader" if mat is ShaderMaterial else "none", "transparent": false, "unshaded": false}


func _probe(item: Dictionary) -> void:
	var hits: Array = []
	var scope: Node = game
	if item.has("node"):
		scope = game.find_child(String(item.node), true, false)
		if scope == null:
			hits.append({"error": "no node " + String(item.node)})
	if scope != null:
		var point := Vector2(float(item.get("x", 0)), float(item.get("y", 0)))
		for n in scope.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree():
				continue
			var rect := _screen_rect(g)
			if rect.get_area() <= 0.0 or (not item.has("node") and not rect.has_point(point)):
				continue
			var hit := {"path": String(game.get_path_to(g)), "class": g.get_class(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "area": rect.get_area()}
			hit.merge(_colour_of(g))
			hits.append(hit)
	hits.sort_custom(func(a, b): return float(a.get("area", 0)) > float(b.get("area", 0)))
	FileAccess.open(qa_dir.path_join(String(item.get("name", "probe")) + ".json"), FileAccess.WRITE).store_string(JSON.stringify({"hits": hits}))
