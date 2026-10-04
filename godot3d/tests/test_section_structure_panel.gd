extends RefCounted
const Section := preload("res://scripts/ui/sections/structure_panel.gd")
const U := preload("res://tests/section_util.gd")


func _barracks() -> Dictionary:
	return {"structure": {
		"id": 50, "kind": "Barracks", "name": "Barracks 2", "sprite": "res://assets/ui/sprites/barracks_v2.png",
		"tag": {"text": "Online", "tone": "good"},
		"hp": {"now": 480, "max": 480, "ratio": 1.0, "tone": "good"},
		"rows": [{"label": "Power", "value": "100% supplied", "tone": "good"}, {"label": "Output", "value": "1 unit / 18 s", "tone": ""}, {"label": "Rally", "value": "Grassland", "tone": "good"}],
		"queue": {"cells": [{"name": "Riflemen", "ratio": 0.63, "note": "0:07", "sprite": "res://assets/ui/sprites/infantry_v2.png"}], "queued": 2},
		"buttons": [
			{"label": "Set rally", "action": "set_rally", "arg": 50, "primary": true},
			{"label": "Repair", "key": "U", "action": "order", "arg": "repair"},
			{"label": "Focus building", "key": "F", "action": "order", "arg": "focus"},
			{"label": "Demolish", "key": "Del", "action": "order", "arg": "sell", "danger": true},
		],
	}}


func test_panel_shows_the_real_numbers_of_the_slice(t) -> void:
	var root := Control.new()
	Section.build(root, _barracks())
	t.ok(U.has_text(root, "Barracks 2"), "the structure's name")
	t.ok(U.has_text(root, "Online"), "its state tag")
	t.ok(U.has_text(root, "480 / 480"), "health now over max")
	t.ok(U.has_text(root, "1 unit / 18 s"), "the output row")
	t.ok(U.has_text(root, "Riflemen") and U.has_text(root, "0:07"), "the running job and its time left")
	t.ok(U.has_text(root, "2 more queued"), "the queued count, the only thing known about the rest")
	t.ok(U.has_text(root, "Production queue"), "the queue caption")
	root.free()


func test_every_button_is_a_button_and_emits_its_command(t) -> void:
	var root := Control.new()
	var calls: Array = []
	Section.build(root, _barracks(), func(action, arg): calls.append([action, arg]))
	for label in ["Set rally", "Repair", "Focus building", "Demolish"]:
		var b := U.button_with(root, label)
		t.ok(b != null, "a Button labelled %s" % label)
		if b != null:
			b.pressed.emit()
	t.eq(calls, [["set_rally", 50], ["order", "repair"], ["order", "focus"], ["order", "sell"]], "each button emits the bridge-backed action")
	t.ok(U.button_with(root, "Cancel last") == null, "no cancel button: the sim has no cancel command")
	root.free()


func test_terrain_column_replaces_the_queue_for_other_buildings(t) -> void:
	var vm := _barracks()
	vm["structure"].erase("queue")
	vm["structure"]["terrain"] = {"title": "Grassland", "sub": "Tile 17,9 / your territory", "rows": [{"label": "Movement", "value": "Foot 100%, vehicles 100%", "tone": ""}, {"label": "Cover", "value": "None, open ground", "tone": "warn"}]}
	var root := Control.new()
	Section.build(root, vm)
	t.ok(U.has_text(root, "Terrain at this tile"), "terrain caption")
	t.ok(U.has_text(root, "Tile 17,9"), "the tile")
	t.ok(U.has_text(root, "None, open ground"), "cover row")
	t.ok(not U.has_text(root, "Production queue"), "no queue column")
	root.free()


func test_empty_queue_says_so(t) -> void:
	var vm := _barracks()
	vm["structure"]["queue"] = {"cells": [], "queued": 0}
	var root := Control.new()
	Section.build(root, vm)
	t.ok(U.has_text(root, "Queue empty"), "an idle producer reads Queue empty")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"structure": {}})
	t.eq(root.get_child_count(), 0, "no structure, no panel")
	root.free()


func test_only_buttons_in_the_slice_are_built(t) -> void:
	var vm := _barracks()
	vm["structure"]["buttons"] = [{"label": "Repair", "key": "U", "action": "order", "arg": "repair", "primary": true}]
	var root := Control.new()
	Section.build(root, vm)
	t.eq(U.buttons(root).size(), 1, "exactly the buttons the slice lists")
	root.free()
