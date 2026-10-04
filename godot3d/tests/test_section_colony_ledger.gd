extends RefCounted
const Section := preload("res://scripts/ui/sections/colony_ledger.gd")
const U := preload("res://tests/section_util.gd")

const LEDGER := {"structures": 11, "units": 23, "crew_used": 23, "crew_cap": 60, "battery_pct": 62, "production": [
	{"name": "Barracks", "state": "idle", "note": "queue empty"},
	{"name": "Factory", "state": "busy", "ratio": 0.48, "note": "Tank 0:41"},
	{"name": "Lab", "state": "busy", "ratio": 0.62, "note": "Radar 1:40"},
]}


func test_counts_and_production_rows_carry_the_slice_numbers(t) -> void:
	var root := Control.new()
	Section.build(root, {"ledger": LEDGER})
	t.ok(U.has_text(root, "Structures"), "structures label")
	t.ok(U.has_text(root, "11"), "structure count")
	t.ok(U.has_text(root, "23 / 60"), "crew use")
	t.ok(U.has_text(root, "62%"), "battery charge")
	t.ok(U.has_text(root, "Tank 0:41"), "factory row note")
	t.ok(U.has_text(root, "queue empty"), "idle producer says its queue is empty")
	t.ok(U.has_text(root, "Idle"), "idle tag")
	t.eq(U.buttons(root).size(), 0, "the ledger is read-only")
	root.free()


func test_missing_fields_are_left_out_not_zeroed(t) -> void:
	var root := Control.new()
	Section.build(root, {"ledger": {"structures": 4, "units": 0}})
	t.ok(U.has_text(root, "Structures"), "present field")
	t.ok(not U.has_text(root, "Crew"), "no crew fields, no crew cell")
	t.ok(not U.has_text(root, "Battery"), "no storage, no battery cell")
	t.ok(not U.has_text(root, "Production"), "no production rows, no heading")
	root.free()


func test_absent_slice_builds_nothing(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"ledger": {}})
	t.eq(root.get_child_count(), 0, "no ledger, no nodes")
	root.free()
