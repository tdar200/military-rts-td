extends RefCounted
## Kestrel ground and water channels baked into the terrain (spec addendum W3, W4). Pure data, no rendering.
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Terrain := preload("res://scripts/continuous_terrain.gd")


func _terrain() -> Node3D:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var m = GroundModel.from_snapshot(JSON.parse_string(f.get_as_text()))
	var terrain: Node3D = Terrain.new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, null)
	terrain.apply_ground(m)
	return terrain


func _at(terrain, x: int, y: int) -> Vector4:
	return terrain.extras_at_world(2.1 + float(x) * 0.68, 1.0 + float(y) * 0.70 + (0.35 if x % 2 else 0.0))


func test_rock_share_marks_the_ridge_only(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 33, 1).z > 0.9, "deep in Ironback Ridge is rock")
	t.ok(_at(terrain, 5, 9).z < 0.05, "Sunfield grass is not rock")
	terrain.free()


func test_sea_share_separates_sea_from_river(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 40, 22).y > 0.9, "Kestrel Bay is sea")
	t.ok(_at(terrain, 24, 11).y < 0.05, "the Calder River is not sea")
	t.ok(_at(terrain, 24, 11).x > 0.5, "but it is water")
	terrain.free()


func test_palette_is_calm_and_ordered(t) -> void:
	var look: Dictionary = Terrain.GROUND_LOOK
	var g := Color(String(look["g"][2]))
	var f := Color(String(look["f"][2]))
	var h := Color(String(look["h"][2]))
	t.ok(g.s < 0.55, "grass is olive, not saturated green (s %s)" % g.s)
	t.ok(f.s < 0.50, "the Dry Flats are sand, not orange (s %s)" % f.s)
	t.ok(f.get_luminance() > g.get_luminance(), "flats are lighter than grass")
	t.ok(h.s < 0.15, "the ridge is grey rock (s %s)" % h.s)
	t.ok(float(look["h"][0]) <= 0.80, "the ridge is low relief, not a 1.6 plateau")
