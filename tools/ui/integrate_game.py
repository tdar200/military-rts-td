#!/usr/bin/env python3
"""One-shot migration: godot3d/scripts/earthfront_3d.gd from the hand-built HUD to scripts/ui/game_ui.gd.
Usage: integrate_game.py <path to earthfront_3d.gd>. Every edit asserts that its anchor exists exactly once, so a
file that has drifted from the baseline fails loudly instead of being half-edited. Writes the file in place."""
import re, sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
lines_before = src.count("\n")


def once(text, old, new):
    n = text.count(old)
    assert n == 1, "anchor found %d times (want 1): %r" % (n, old[:80])
    return text.replace(old, new)


def drop_func(text, name):
    """Remove `func name(` through the line before the next top-level declaration."""
    m = re.search(r"^func %s\(.*?(?=^(?:func|var|const|signal|class|@)\b)" % re.escape(name), text, re.S | re.M)
    assert m, "function not found: " + name
    return text[:m.start()] + text[m.end():]


def replace_func(text, name, new_body):
    m = re.search(r"^func %s\(.*?(?=^(?:func|var|const|signal|class|@)\b)" % re.escape(name), text, re.S | re.M)
    assert m, "function not found: " + name
    return text[:m.start()] + new_body.rstrip("\n") + "\n\n\n" + text[m.end():]


# ---- declarations
src = once(src, "const TICKS_PER_SECOND := 30.0\n", "const TICKS_PER_SECOND := 30.0\nconst GameUI = preload(\"res://scripts/ui/game_ui.gd\")\n")
src = once(src, "var selection_box: ColorRect\n", "var selection_box: Control\nvar ui: Node  # GameUI: every on-screen surface\nvar build_cursor_is_valid := false\n")
for dead in ["var unit_portrait: TextureRect\n", "var status_label: Label\n", "var relay_objective_label: Label\n", "var unit_card_label: Label\n",
             "var research_button: Button\n", "var science_list: VBoxContainer\n", "var science_summary: Label\n", "var resource_label: Label\n",
             "var wave_label: Label\n", "var wave_progress: ProgressBar\n", "var command_bar: GridContainer\n", "var command_buttons: Dictionary = {}\n",
             "var tab_buttons: Dictionary = {}\n", "var notification_layer: Control\n", "var ui_theme: Theme\n"]:
    src = once(src, dead, "")
src = once(src, 'var active_command_tab := "BUILD"\n', "")

# ---- _ready
src = once(src, "\t_create_ui_theme()\n", "")
src = drop_func(src, "_create_ui_theme")

# ---- _process: the label block becomes one call
start = src.index("\tif status_label:\n\t\tvar human_count := _living_team(HUMAN)")
end = src.index("func _animate_world(")
src = src[:start] + "\tif mission_deployed and not battle_started and time_alive > 1.5:\n\t\tbattle_started = true\n\tui.process(delta)\n\n\n" + src[end:]

# ---- _poll_bridge
src = once(src, """		bridge_research_options = next_options
		_refresh_science_panel()
	elif previous_active_research_id != bridge_active_research_id:
		_refresh_science_panel()
""", """		bridge_research_options = next_options
""")
src = once(src, "\tvar previous_active_research_id := bridge_active_research_id\n", "")
src = once(src, "\t_apply_era_visuals()\n\t_refresh_command_availability()\n", "\t_apply_era_visuals()\n")

# ---- selection
src = once(src, """	if not is_instance_valid(selected):
		if is_instance_valid(selection_ring):
			selection_ring.visible = false
		if unit_portrait:
			unit_portrait.texture = null
""", """	if not is_instance_valid(selected):
		if is_instance_valid(selection_ring):
			selection_ring.visible = false
""")
src = once(src, "\tselection_ring.visible = true\n\t_update_portrait()\n", "\tselection_ring.visible = true\n")
src = once(src, """		_set_command_tab("ORDERS")
	_refresh_command_availability()
	var category_name := "STRUCTURE" if category == "building" else ("UNIT" if selected_units.size() == 1 else "FORMATION")
	objective_label.text = "%s SELECTED — RIGHT-CLICK FOR CONTEXT ORDER" % category_name
""", """		_set_command_tab("ORDERS")
""")
src = drop_func(src, "_update_portrait")

# ---- the whole old UI
src = replace_func(src, "_build_ui", '''func _build_ui() -> void:
	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)
	selection_box = ui.selection_box
	science_overlay = ui.research
	# State holders the game still writes to: the HUD turns objective_label changes into toasts, and _update_tutorial
	# only runs while tutorial_label exists. They are never shown.
	objective_label = Label.new()
	tutorial_label = Label.new()
	for holder in [objective_label, tutorial_label]:
		holder.visible = false
		ui.add_child(holder)
''')
src = replace_func(src, "_set_command_tab", '''func _set_command_tab(tab_name: String) -> void:
	ui.set_tab(tab_name.to_lower())
''')
src = replace_func(src, "_toggle_science_panel", '''func _toggle_science_panel() -> void:
	ui.toggle_research()
''')
for dead in ["_build_science_panel", "_refresh_science_panel", "_refresh_command_availability", "_build_briefing", "_build_minimap",
             "_panel_style", "_progress_style", "_living_team"]:  # the last three were only used by the code above
    src = drop_func(src, dead)

# ---- hover tile and build ghost use the HUD's own hit test instead of pixel thresholds
src = once(src, """	if not mission_deployed or (science_overlay and science_overlay.visible):
		hover_tile.visible = false
		return
	var pointer := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size
	if pointer.y > viewport_size.y - 285.0 or pointer.y < 68.0:
		hover_tile.visible = false
		return
""", """	if not mission_deployed:
		hover_tile.visible = false
		return
	var pointer := get_viewport().get_mouse_position()
	if ui.blocks_point(pointer):
		hover_tile.visible = false
		return
""")
src = once(src, """	if build_mode == "":
		build_ghost.visible = false
		return
	var ground := _screen_to_ground(get_viewport().get_mouse_position())
	if ground == Vector3.INF:
		build_ghost.visible = false
		return
	var tile := _world_to_tile(ground)
	var snapped := _hex_world(tile.x, tile.y)
	snapped.y = _height_world(snapped.x, snapped.z) + 0.06
	build_ghost.position = snapped
	build_ghost.material_override = materials.ghost_valid if _is_build_valid(tile) else materials.ghost_invalid
	build_ghost.visible = true
""", """	build_cursor_is_valid = false
	if build_mode == "":
		build_ghost.visible = false
		return
	var pointer := get_viewport().get_mouse_position()
	var ground := _screen_to_ground(pointer)
	if ground == Vector3.INF or ui.blocks_point(pointer):
		build_ghost.visible = false
		return
	var tile := _world_to_tile(ground)
	var snapped := _hex_world(tile.x, tile.y)
	snapped.y = _height_world(snapped.x, snapped.z) + 0.06
	build_ghost.position = snapped
	build_cursor_is_valid = _is_build_valid(tile)
	build_ghost.material_override = materials.ghost_valid if build_cursor_is_valid else materials.ghost_invalid
	build_ghost.visible = true
""")

# ---- notifications, debrief, deploy
src = replace_func(src, "_show_notification", '''func _show_notification(title: String, body: String, color: Color) -> void:
	ui.notify(title, body, color)
''')
src = replace_func(src, "_show_end_screen", '''func _show_end_screen(winner: int) -> void:
	if end_screen_shown:
		return
	end_screen_shown = true
	_play_tone(360.0 if winner == HUMAN else 120.0, 0.34, 0.18, 420.0 if winner == HUMAN else -50.0)
	ui.show_debrief()
''')
src = once(src, "func _deploy_mission(briefing: Control) -> void:", "func _deploy_mission() -> void:")
src = once(src, """	objective_label.text = "COMMAND LINK ESTABLISHED"
	var tween := create_tween()
	tween.tween_property(briefing, "modulate:a", 0.0, 0.32)
	tween.tween_callback(briefing.queue_free)
""", """	objective_label.text = "COMMAND LINK ESTABLISHED"
	ui.begin_operation()
""")

# ---- session log hooks
src = once(src, """			entity_node.set_meta("kind_name", incoming_kind)
			bridge_nodes[bridge_id] = entity_node
			if bridge_initialized:
""", """			entity_node.set_meta("kind_name", incoming_kind)
			bridge_nodes[bridge_id] = entity_node
			if bridge_initialized:
				ui.session_log.unit_added(kind_name, owner, category)
""")
src = once(src, """		bridge_nodes.erase(bridge_id)
		units.erase(stale)
		if is_instance_valid(stale):
			if bridge_initialized:
""", """		bridge_nodes.erase(bridge_id)
		units.erase(stale)
		if is_instance_valid(stale):
			if bridge_initialized:
				ui.session_log.unit_removed(String(stale.get_meta("kind_name", "")), int(stale.get_meta("team", ALIEN)), String(stale.get_meta("category", "")))
""")

# ---- accessors the HUD adapter reads
src = once(src, "func _screen_to_ground(screen_position: Vector2) -> Vector3:", '''## Pointer position in viewport pixels (the HUD adapter reads this instead of the window).
func mouse_position() -> Vector2:
	return get_viewport().get_mouse_position()


## World rectangle (x, z) shown by the minimap.
func minimap_world_rect() -> Rect2:
	return ui.minimap_world_rect()


## Bounding rectangle (x, z) of the ground the main camera sees; empty when a corner looks past the horizon.
func view_ground_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var rect := Rect2()
	var first := true
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var ground := _screen_to_ground(corner)
		if ground == Vector3.INF:
			return Rect2()
		if first:
			rect = Rect2(Vector2(ground.x, ground.z), Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(Vector2(ground.x, ground.z))
	return rect


func focus_camera(position: Vector3, zoom: float) -> void:
	camera_focus_target = position
	camera_focus_zoom = zoom
	camera_cinematic = 0.8


func era_name() -> String:
	return _era_name()


## True while the build ghost is over a tile the order would be accepted on.
func build_cursor_valid() -> bool:
	return build_cursor_is_valid


func _screen_to_ground(screen_position: Vector2) -> Vector3:''')

open(path, "w", encoding="utf-8").write(src)
print("ok: %d -> %d lines" % (lines_before, src.count("\n")))
