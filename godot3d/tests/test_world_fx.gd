extends RefCounted
## Kestrel combat effects (plan 2026-10-05-kestrel-combat-motion-fx, Task 2): pooled flipbook cards from one atlas, three
## MultiMeshes with one shared material each, hit / death / collapse recipes, the oldest card recycled at the cap.
const WorldFx := preload("res://scripts/world/world_fx.gd")
const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")


func _fx() -> Array:
	var parent := Node3D.new()
	var fx = WorldFx.new()
	fx.build(parent)
	return [fx, parent]


func _done(pair: Array) -> void:
	(pair[1] as Node3D).free()


func test_atlas_is_the_documented_grid(t) -> void:
	var tex := load(WorldFx.ATLAS) as Texture2D
	t.ok(tex != null, "the effect atlas loads")
	if tex != null:
		t.eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(WorldFx.COLS * WorldFx.CELL_PX, 2 * WorldFx.BAND_ROWS * WorldFx.CELL_PX), "8 x 6 cells of 128 px")


func test_every_recipe_spawns_at_most_its_documented_cards(t) -> void:
	for weight in 4:
		for owner in [0, 1]:
			var pair := _fx()
			var n: int = pair[0].hit(Vector3(3, 0, 3), weight, owner)
			t.ok(n > 0 and n <= WorldFx.HIT_MAX_CARDS, "hit weight %d: %d cards (max %d)" % [weight, n, WorldFx.HIT_MAX_CARDS])
			t.eq(pair[0].pool_count(), n, "hit weight %d: the pool holds what it spawned" % weight)
			_done(pair)
	var heavier := []
	for weight in 4:
		var pair := _fx()
		heavier.append(pair[0].hit(Vector3.ZERO, weight, 0))
		_done(pair)
	t.ok(heavier[0] < heavier[3], "a gunship-class hit draws more than an infantry hit (%s)" % str(heavier))
	for size in [0.98, 1.71, 4.02]:
		var pair := _fx()
		var n: int = pair[0].explode(Vector3.ZERO, size, 1)
		t.ok(n > 0 and n <= WorldFx.EXPLODE_MAX_CARDS, "explode %.2f tiles: %d cards" % [size, n])
		_done(pair)
	var pair := _fx()
	var c: int = pair[0].collapse(Vector3.ZERO, 2.44, 0)
	t.ok(c > 0 and c <= WorldFx.COLLAPSE_MAX_CARDS, "collapse: %d cards (max %d)" % [c, WorldFx.COLLAPSE_MAX_CARDS])
	var f: int = pair[0].flash(Vector3.ZERO, 2, 0)
	t.ok(f > 0 and f <= WorldFx.FLASH_MAX_CARDS, "flash: %d card" % f)
	_done(pair)


func test_pool_cap_holds_and_recycles_the_oldest(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.collapse(Vector3.ZERO, 2.44, 0)  # the first cards spawned: a rubble decal that would live 6 s
	var spawned := WorldFx.COLLAPSE_MAX_CARDS
	var total := 0
	for i in 200:
		total += fx.hit(Vector3(float(i % 7), 0, float(i % 5)), i % 4, i % 2)
		t.ok(fx.pool_count() <= WorldFx.POOL, "never more than %d live cards" % WorldFx.POOL)
	t.eq(fx.pool_count(), WorldFx.POOL, "the pool is full")
	var serials: Array = fx.live_serials()
	serials.sort()
	t.eq(int(serials[0]), fx.spawned_total() - WorldFx.POOL, "the live cards are the newest %d: the oldest were recycled" % WorldFx.POOL)
	t.ok(fx.spawned_total() > spawned + total - 1, "every spawn counted")
	_done(pair)


func test_effects_free_themselves_after_their_duration(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.hit(Vector3.ZERO, 3, 0)
	fx.explode(Vector3(2, 0, 0), 1.71, 1)
	fx.collapse(Vector3(-2, 0, 0), 3.05, 0)
	t.ok(fx.pool_count() > 0, "live after spawning")
	fx.advance(0.2)
	t.ok(fx.pool_count() > 0, "still burning at 0.2 s")
	for i in 80:
		fx.advance(0.1)
	t.eq(fx.pool_count(), 0, "every card freed itself within 8.2 s (the rubble lasts about 6 s)")
	for layer in fx.layers():
		t.ok(not (layer as MultiMeshInstance3D).visible, "%s hidden when idle: no draw call" % (layer as Node).name)
	_done(pair)


func test_rubble_outlasts_the_fire_and_fades_over_about_six_seconds(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.collapse(Vector3.ZERO, 2.44, 0)
	fx.advance(4.0)
	t.ok(fx.live_sprites().has(WorldFx.RUBBLE), "rubble still smouldering at 4 s")
	t.ok(not fx.live_sprites().has(WorldFx.FIREBALL), "the fireballs are long gone")
	for i in 25:
		fx.advance(0.1)
	t.ok(not fx.live_sprites().has(WorldFx.RUBBLE), "rubble gone by 6.5 s")
	_done(pair)


func test_materials_are_shared_never_per_card(t) -> void:
	var a := _fx()
	var b := _fx()
	for i in 40:
		a[0].hit(Vector3(i, 0, 0), i % 4, i % 2)
		b[0].explode(Vector3(i, 0, 0), 1.0, i % 2)
	a[0].advance(0.05)
	b[0].advance(0.05)
	var mats := {}
	for pair in [a, b]:
		var layers: Array = pair[0].layers()
		t.eq(layers.size(), 3, "three card layers: ground, smoke, glow")
		for i in layers.size():
			var mmi := layers[i] as MultiMeshInstance3D
			t.ok(mmi.material_override == WorldFx.material_for(i), "layer %d draws the one shared material" % i)
			t.eq(mmi.get_child_count(), 0, "no per-card nodes")
			t.eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow casting")
			mats[mmi.material_override] = true
		t.eq((pair[1] as Node3D).get_child_count(), 3, "the parent gains three nodes whatever the card count")
	t.eq(mats.size(), 3, "three materials across two effect systems and 80 effects")
	var code: String = (WorldFx.material_for(1) as ShaderMaterial).shader.code
	t.ok(code.contains("blend_premul_alpha"), "premultiplied: alpha 0 texels add (fire), alpha 1 texels cover (smoke)")
	t.ok(code.contains("depth_draw_never"), "effects never write depth")
	t.ok(code.contains("INSTANCE_CUSTOM"), "the flipbook frame comes from the instance, not a material")
	t.ok(WorldFx.material_for(0).render_priority < 0 and WorldFx.material_for(2).render_priority > WorldFx.material_for(1).render_priority,
		"ground decals under the cards, fire over smoke")
	_done(a)
	_done(b)


func test_cards_face_the_kestrel_camera(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.hit(Vector3(1, 0, 1), 2, 0)
	fx.advance(0.05)
	var back := Vector3(0.0, WorldArt.PITCH_SIN, sqrt(1.0 - WorldArt.PITCH_SIN * WorldArt.PITCH_SIN))
	var checked := 0
	for slot in WorldFx.POOL:
		if not fx.slot_live(slot):
			continue
		var xf: Transform3D = fx.slot_transform(slot)
		if xf.basis.x.length() < 1e-6:
			continue  # still waiting on its delay
		t.ok(xf.basis.z.normalized().is_equal_approx(back), "slot %d faces the camera (%s)" % [slot, xf.basis.z])
		t.near(xf.basis.x.dot(back), 0.0, 1e-4, "its width lies in the view plane")
		t.near(xf.basis.y.dot(back), 0.0, 1e-4, "its height too")
		checked += 1
	t.ok(checked >= 2, "checked %d cards" % checked)
	_done(pair)


func test_flipbook_frames_advance_and_bands_follow_the_owner(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.explode(Vector3.ZERO, 1.0, 0)
	var slot: int = fx.find_slot(WorldFx.FIREBALL)
	t.ok(slot >= 0, "a fireball card")
	fx.advance(0.02)
	var first: Color = fx.slot_rect(slot)
	fx.advance(0.4)
	var later: Color = fx.slot_rect(slot)
	t.ok(absf(first.r - later.r) > 0.1, "the fireball steps through its frames (u %.3f -> %.3f)" % [first.r, later.r])
	t.ok(first.g < 0.5, "human fire samples the amber band")
	_done(pair)
	pair = _fx()
	pair[0].explode(Vector3.ZERO, 1.0, 1)
	pair[0].advance(0.02)
	var alien: int = pair[0].find_slot(WorldFx.FIREBALL)
	t.ok((pair[0].slot_rect(alien) as Color).g >= 0.5, "alien fire samples the plasma band")
	_done(pair)


func test_far_effects_are_culled(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.set_view(Vector3(10, 0, 10), Vector2(6, 4))
	t.eq(fx.hit(Vector3(40, 0, 10), 3, 0), 0, "a hit far off screen draws nothing")
	t.eq(fx.collapse(Vector3(10, 0, -20), 3.0, 0), 0, "a collapse far off screen draws nothing")
	t.ok(fx.hit(Vector3(12, 0, 11), 1, 0) > 0, "a hit on screen draws")
	_done(pair)


func test_headless_without_a_camera_or_tree_is_safe(t) -> void:
	var fx = WorldFx.new()
	t.eq(fx.pool_count(), 0, "unbuilt: empty")
	t.eq(fx.hit(Vector3.ZERO, 1, 0), 0, "unbuilt: a spawn is a no-op")
	fx.advance(0.1)
	var pair := _fx()
	pair[0].camera = null
	pair[0].hit(Vector3.ZERO, 3, 1)
	pair[0].advance(0.1)
	t.ok(pair[0].pool_count() > 0, "built outside the tree, no camera: still runs")
	_done(pair)


func test_weight_classes(t) -> void:
	t.eq(WorldFx.weight_for("Infantry"), 0, "infantry")
	t.eq(WorldFx.weight_for("AntiArmor"), 1, "anti-armour")
	t.eq(WorldFx.weight_for("GunTurret"), 1, "gun")
	t.eq(WorldFx.weight_for("Tank"), 2, "tank")
	t.eq(WorldFx.weight_for("Helicopter"), 3, "gunship")
	t.eq(WorldFx.weight_for("Capital"), 3, "capital")
	t.eq(WorldFx.weight_for("Barracks"), 3, "a building")
