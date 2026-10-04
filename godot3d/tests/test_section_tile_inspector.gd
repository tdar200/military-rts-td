extends RefCounted
const Section := preload("res://scripts/ui/sections/tile_inspector.gd")
const U := preload("res://tests/section_util.gd")

const BASE := {"name": "Highland", "cover_pct": 25, "range_pct": 25, "infantry_pct": 70, "vehicle_pct": 70, "buildable": true, "bonus_text": ""}


func _with(extra: Dictionary) -> Dictionary:
	var d := BASE.duplicate()
	d.merge(extra, true)
	return {"inspect": d}


func test_rows_carry_the_real_numbers(t) -> void:
	var root := Control.new()
	Section.build(root, _with({"x": 21, "y": 10, "glyph": "h", "zone": true}))
	t.ok(U.has_text(root, "Highland"), "ground name")
	t.ok(U.has_text(root, "Tile 21,10 / Player territory"), "tile and territory line")
	t.ok(U.has_text(root, "Foot 70%, vehicles 70%"), "movement from infantry_pct and vehicle_pct")
	t.ok(U.has_text(root, "25% less damage taken"), "cover from cover_pct")
	t.ok(U.has_text(root, "+25% weapon range"), "range row only because range_pct > 0")
	t.ok(U.has_text(root, "Open to building"), "buildable")
	root.free()


func test_no_range_row_and_open_ground_for_zero_values(t) -> void:
	var root := Control.new()
	Section.build(root, _with({"cover_pct": 0, "range_pct": 0, "name": "Grassland", "infantry_pct": 100, "vehicle_pct": 100}))
	t.ok(U.has_text(root, "None, open ground"), "no cover says so")
	t.ok(not U.has_text(root, "weapon range"), "no range row at 0")
	t.ok(not U.has_text(root, "Player territory"), "no coordinates or zone in the slice, no tile line")
	root.free()


func test_impassable_and_unbuildable_tiles(t) -> void:
	var root := Control.new()
	Section.build(root, _with({"name": "River", "infantry_pct": 0, "vehicle_pct": 0, "buildable": false, "cover_pct": 0, "range_pct": 0}))
	t.ok(U.has_text(root, "Impassable"), "river cannot be crossed")
	t.ok(U.has_text(root, "Cannot build here"), "river cannot be built on")
	root.free()


func test_bonus_and_deposit_pills_only_when_reported(t) -> void:
	var root := Control.new()
	Section.build(root, _with({"bonus_text": "Ore haul +20%", "deposit": {"kind": "Ore", "remaining": 24000}, "x": 3, "y": 4, "glyph": "g"}))
	t.ok(U.has_text(root, "Ore haul +20%"), "bonus pill from bonus_text")
	t.ok(U.has_text(root, "24,000 left"), "deposit pill with grouped thousands")
	t.ok(U.has_text(root, "Highland, Ore"), "title names the deposit kind")
	root.free()
	var plain := Control.new()
	Section.build(plain, _with({}))
	t.ok(not U.has_text(plain, "left"), "no deposit, no pill")
	t.ok(not U.has_text(plain, "haul"), "no bonus, no pill")
	plain.free()


func test_absent_slice_builds_nothing_and_no_clickables(t) -> void:
	var root := Control.new()
	Section.build(root, {})
	Section.build(root, {"inspect": {}})
	t.eq(root.get_child_count(), 0, "off-map hover builds nothing")
	root.free()
	var full := Control.new()
	Section.build(full, _with({}))
	t.eq(U.buttons(full).size(), 0, "the inspector is read-only")
	full.free()
