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
