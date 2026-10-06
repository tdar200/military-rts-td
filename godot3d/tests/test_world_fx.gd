extends RefCounted
## Kestrel combat effects (plan 2026-10-05-kestrel-combat-motion-fx, Task 2): pooled flipbook cards from one atlas, three
## MultiMeshes with one shared material each, hit / death / collapse recipes, the oldest card recycled at the cap.
const WorldFx := preload("res://scripts/world/world_fx.gd")
const WorldArt := preload("res://scripts/world/world_art.gd")
const WorldSprites := preload("res://scripts/world/world_sprites.gd")
const MainScene = preload("res://main.tscn")


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
		t.eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(WorldFx.COLS * WorldFx.CELL_PX, 2 * WorldFx.BAND_ROWS * WorldFx.CELL_PX), "8 x 8 cells of 128 px")


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


func test_a_full_pool_recycles_the_oldest_without_scanning(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	for i in WorldFx.POOL:
		fx._card(WorldFx.SMOKE, 0, Vector3.ZERO, {"life": 30.0})
	t.eq(fx.pool_count(), WorldFx.POOL, "the pool is full")
	fx.advance(0.01)
	var before: int = fx.slot_probes()
	for i in 144:  # a capped poll's worst case: 24 shots x 6 cards, every one into a full pool
		fx._card(WorldFx.SMOKE, 0, Vector3.ZERO, {"life": 30.0})
	var probes: int = fx.slot_probes() - before
	t.ok(probes <= 144 * 3, "144 spawns into a full pool examine %d slots, not 144 x %d" % [probes, WorldFx.POOL])
	var serials: Array = fx.live_serials()
	serials.sort()
	t.eq(serials.size(), WorldFx.POOL, "still full")
	t.eq(int(serials[0]), 144, "the 144 oldest were recycled, oldest first")
	t.eq(int(serials.back()), WorldFx.POOL + 143, "the newest is live")
	_done(pair)


func test_the_oldest_live_card_is_recycled_after_out_of_order_expiry(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	for i in WorldFx.POOL:  # every other card short-lived: they expire out of spawn order
		fx._card(WorldFx.SMOKE, 0, Vector3.ZERO, {"life": 0.05 if i % 2 == 1 else 30.0})
	fx.advance(0.1)
	t.eq(fx.pool_count(), WorldFx.POOL / 2, "the short cards went")
	for round in 3:  # refill the holes, then overflow the pool a few times over
		for i in WorldFx.POOL:
			fx._card(WorldFx.SMOKE, 0, Vector3.ZERO, {"life": 0.05 if i % 3 == 0 else 30.0})
		fx.advance(0.1)
	for i in WorldFx.POOL + 10:
		fx._card(WorldFx.SMOKE, 0, Vector3.ZERO, {"life": 30.0})
	var serials: Array = fx.live_serials()
	serials.sort()
	t.eq(serials.size(), WorldFx.POOL, "full")
	t.eq(int(serials[0]), fx.spawned_total() - WorldFx.POOL, "the live cards are exactly the newest %d" % WorldFx.POOL)
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


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	scene._sync_ground(JSON.parse_string(f.get_as_text()))
	return scene


func _building(scene, id: int, kind: String, owner: int, tile: Vector2i) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": "building", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100, "construction": 0, "construction_total": 100}


func test_kestrel_gets_effects_and_survival_does_not(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.world_fx != null, "Kestrel builds the effect system")
	scene.free()
	var survival = MainScene.instantiate()
	t.eq(survival.world_fx, null, "Survival keeps its sphere effects")
	survival.free()


func test_a_destroyed_building_collapses_and_its_sprite_goes_at_once(t) -> void:
	var scene := _kestrel_scene()
	scene._sync_bridge_entities([_building(scene, 930, "Barracks", 1, Vector2i(10, 12))])
	var root: Node3D = scene.bridge_nodes[930]
	var before: int = scene.world_fx.pool_count()
	scene._kestrel_death(root)
	t.ok(not root.visible, "the finished painting is hidden the moment the sim drops it")
	t.ok(scene.world_fx.pool_count() - before > 4, "a staged collapse spawned (%d cards)" % (scene.world_fx.pool_count() - before))
	t.ok(scene.world_fx.live_sprites().has(WorldFx.RUBBLE), "with a burning rubble decal")
	t.ok(scene.world_fx.live_bands().has(1) and not scene.world_fx.live_bands().has(0), "an alien building burns in alien colours")
	t.ok(scene.camera_shake >= 0.78, "the camera shakes as before")
	scene.free()
	if is_instance_valid(root):
		root.free()


func test_a_dying_unit_explodes_in_its_own_colours(t) -> void:
	var scene := _kestrel_scene()
	var at: Vector3 = scene._hex_world(12, 12)
	var bits: Vector2i = scene._world_to_sim_bits(at)
	scene._sync_bridge_entities([{"id": 931, "category": "unit", "kind": "Tank", "owner": 0, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100}])
	var root: Node3D = scene.bridge_nodes[931]
	scene._kestrel_death(root)
	t.ok(scene.world_fx.live_sprites().has(WorldFx.FIREBALL), "a fireball")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.SMOKE), "a smoke plume")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.DEBRIS), "debris")
	t.ok(scene.world_fx.live_bands().has(0) and not scene.world_fx.live_bands().has(1), "a human tank burns amber")
	scene.free()
	if is_instance_valid(root):
		root.free()


func test_a_hit_draws_the_firing_side_and_keeps_the_alert(t) -> void:
	var scene := _kestrel_scene()
	scene.alert_cooldown = 0.0
	scene.camera_shake = 0.0
	scene._kestrel_impact(scene._hex_world(12, 12), {"owner": 0, "kind": "Tank"})
	t.ok(scene.world_fx.pool_count() > 0 and scene.world_fx.pool_count() <= WorldFx.HIT_MAX_CARDS, "a hit's cards")
	t.ok(scene.world_fx.live_bands().has(1), "a human unit is hit by alien plasma")
	t.near(scene.camera_shake, 0.42, 1e-6, "the human-hit shake as before")
	t.near(scene.alert_cooldown, 1.3, 1e-6, "and its cooldown")
	scene.free()


# ---------------------------------------------------------------- Task 3: firing effects from the shots window

## The screen direction (camera right, camera up) of a world displacement under the fixed Kestrel view.
func _screen(v: Vector3) -> Vector2:
	var s := WorldArt.PITCH_SIN
	var c := sqrt(1.0 - s * s)
	return Vector2(v.x, v.y * c - v.z * s)


func test_a_shot_draws_a_muzzle_flash_a_tracer_and_an_impact(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	var from := Vector3(0, 0, 0)
	var to := Vector3(3, 0, 1)
	var n: int = fx.shot(from, to, "Infantry", 0)
	t.ok(n >= 3 and n <= WorldFx.SHOT_MAX_CARDS, "a rifle shot: %d cards (max %d)" % [n, WorldFx.SHOT_MAX_CARDS])
	var sprites: Dictionary = fx.live_sprites()
	t.ok(sprites.has(WorldFx.FLASH), "a muzzle flash")
	t.ok(sprites.has(WorldFx.TRACER), "a tracer")
	t.ok(sprites.has(WorldFx.SPARKS), "an impact")
	t.ok(fx.live_bands().has(0) and not fx.live_bands().has(1), "a human shot is amber")
	fx.advance(0.01)
	var slot: int = fx.find_slot(WorldFx.TRACER)
	var xf: Transform3D = fx.slot_transform(slot)
	t.ok(xf.basis.y.length() > 3.0 * xf.basis.x.length(), "the tracer is a stretched card (%.3f x %.3f)" % [xf.basis.x.length(), xf.basis.y.length()])
	var along: Vector2 = _screen(xf.basis.y).normalized()
	var aim: Vector2 = _screen(to - from).normalized()
	t.ok(along.dot(aim) > 0.95, "it lies along the shot on screen (%s vs %s)" % [along, aim])
	t.ok((fx.slot_rect(slot) as Color).g >= 3.0 / 8.0 - 1e-6 and (fx.slot_rect(slot) as Color).g < 0.5, "it samples the human shot row")
	var p0: Vector2 = _screen(xf.origin)
	var flight: float = WorldFx.flight_time(from, to, "Infantry", 0)
	fx.advance(flight * 0.6)
	var p1: Vector2 = _screen(fx.slot_transform(slot).origin)
	t.ok(p1.distance_to(_screen(to)) < p0.distance_to(_screen(to)) - 0.3, "the tracer travels to the target")
	var impact: int = -1
	for s in WorldFx.POOL:
		if fx.slot_live(s) and fx.find_slot(WorldFx.SPARKS) == s:
			impact = s
	t.ok(impact >= 0, "the impact is spawned with the shot")
	t.eq(fx.slot_transform(impact).basis.x.length(), 0.0, "the impact waits for the round: undrawn before it lands")
	fx.advance(flight)
	t.ok(fx.slot_transform(fx.find_slot(WorldFx.SPARKS)).basis.x.length() > 0.0, "and flashes when it lands")
	_done(pair)


func test_a_shot_waits_on_its_delay(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.shot(Vector3.ZERO, Vector3(2, 0, 0), "Tank", 0, 0.3)
	fx.advance(0.1)
	var drawn := 0
	for s in WorldFx.POOL:
		if fx.slot_live(s) and fx.slot_transform(s).basis.x.length() > 0.0:
			drawn += 1
	t.eq(drawn, 0, "nothing shows before the shot's own tick comes round")
	fx.advance(0.25)
	t.ok(fx.live_sprites().has(WorldFx.SHELL), "then the shell flies")
	_done(pair)


func test_shot_looks_follow_the_attacker_kind_and_side(t) -> void:
	for kind in ["Infantry", "AntiArmor", "Tank", "Helicopter", "Capital", "GunTurret", "AaTurret", "CommandCenter", "Battery", "", "Wat"]:
		for owner in [0, 1]:
			var pair := _fx()
			var n: int = pair[0].shot(Vector3.ZERO, Vector3(2.5, 0, -1.0), kind, owner)
			t.ok(n > 0 and n <= WorldFx.SHOT_MAX_CARDS, "%s owner %d: %d cards" % [kind, owner, n])
			t.ok(pair[0].live_bands().size() == 1 and pair[0].live_bands().has(owner), "%s owner %d: its own side's colours" % [kind, owner])
			_done(pair)
	var looks := {}
	for case in [["Infantry", 0], ["Tank", 0], ["AntiArmor", 0], ["Helicopter", 0], ["Infantry", 1], ["Tank", 1]]:
		var pair := _fx()
		pair[0].shot(Vector3.ZERO, Vector3(2.5, 0, 0), case[0], case[1])
		looks["%s%d" % case] = pair[0].live_sprites()
		var tracers := 0
		for s in WorldFx.POOL:
			if pair[0].slot_live(s) and int(pair[0]._cards[s].sprite) in [WorldFx.TRACER, WorldFx.BOLT]:
				tracers += 1
		if case[0] == "Helicopter":
			t.eq(tracers, 2, "a gunship fires paired bursts")
		_done(pair)
	t.ok(looks["Infantry0"].has(WorldFx.TRACER), "infantry: a tracer")
	t.ok(looks["Tank0"].has(WorldFx.SHELL) and not looks["Tank0"].has(WorldFx.TRACER), "tank: a glowing shell")
	t.ok(looks["AntiArmor0"].has(WorldFx.SHELL), "anti-armour: a glowing shell")
	t.ok(looks["Infantry1"].has(WorldFx.BOLT) and looks["Tank1"].has(WorldFx.BOLT), "aliens: plasma bolts")
	t.ok(WorldFx.flight_time(Vector3.ZERO, Vector3(3, 0, 0), "Tank", 0) > WorldFx.flight_time(Vector3.ZERO, Vector3(3, 0, 0), "Infantry", 0) * 1.5,
		"a shell flies slower than a bullet")
	t.eq(WorldFx.shot_style(""), WorldFx.shot_style("Infantry"), "an unknown attacker takes the infantry look")


func test_far_shots_draw_nothing(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	fx.set_view(Vector3(10, 0, 10), Vector2(6, 4))
	t.eq(fx.shot(Vector3(40, 0, 10), Vector3(42, 0, 10), "Tank", 0), 0, "both ends far off screen: nothing")
	t.ok(fx.shot(Vector3(40, 0, 10), Vector3(15, 0, 11), "Tank", 0) > 0, "a round landing on screen draws")
	_done(pair)


func test_recoil_kicks_the_card_back_and_restores_it_exactly(t) -> void:
	var card := WorldSprites.make_card("Tank", 0, 1.71)
	card.position = Vector3(0.0, 0.031, 0.0)
	var rest := card.position
	var basis := card.transform.basis
	WorldSprites.kick(card, Vector3(1, 0, 0.5), 10.0)
	t.ok(WorldSprites.recoil_step(card, 10.03), "kicking at 30 ms")
	var moved := card.position - rest
	t.ok(moved.length() > 0.01, "the card moved (%s)" % moved)
	t.ok(moved.dot(Vector3(1, 0, 0.5)) < 0.0, "backward, away from the shot")
	t.near(card.position.y, rest.y, 1e-9, "never up or down (the bob owns y)")
	t.ok(card.transform.basis == basis, "never turned or scaled")
	t.ok(not WorldSprites.recoil_step(card, 10.2), "done after about 0.1 s")
	t.ok(card.position == rest, "back exactly where it was (%s)" % card.position)
	t.ok(not card.has_meta("recoil_t0"), "no recoil state left behind")
	WorldSprites.kick(card, Vector3(0, 0, 1), 20.0)
	t.ok(WorldSprites.recoil_step(card, 19.9), "a kick waiting on its shot's delay")
	t.ok(card.position == rest, "holds still until the muzzle flashes")
	WorldSprites.recoil_step(card, 20.02)
	WorldSprites.kick(card, Vector3(1, 0, 0), 20.03)  # fired again mid-kick: the rest is kept
	WorldSprites.recoil_step(card, 20.5)
	t.ok(card.position == rest, "a kick on a kick still comes home")
	card.free()


# ---- the dispatcher in earthfront_3d.gd

func _unit(scene, id: int, kind: String, owner: int, tile: Vector2i) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	return {"id": id, "category": "unit", "kind": kind, "owner": owner, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 100, "max_hp_bits": 65536 * 100}


func _row(scene, tick: int, a: Vector2i, b: Vector2i) -> Array:
	var ab: Vector2i = scene._world_to_sim_bits(scene._hex_world(a.x, a.y))
	var bb: Vector2i = scene._world_to_sim_bits(scene._hex_world(b.x, b.y))
	return [tick, ab.x, ab.y, bb.x, bb.y]


## Puts entities in the scene as a first poll does (no deploy effects, no session log), then marks the bridge initialized.
func _place(scene, entities: Array) -> void:
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)


func _fight_scene(entities: Array) -> Node3D:
	var scene := _kestrel_scene()
	scene._sync_bridge_entities(entities)
	scene.world_fx.set_view(scene._hex_world(12, 12), Vector2(12, 10))
	return scene


func test_dispatcher_draws_each_shot_once_across_overlapping_polls(t) -> void:
	var scene := _fight_scene([])
	var row := func(tick: int) -> Array: return _row(scene, tick, Vector2i(10, 12), Vector2i(14, 12))
	t.eq(scene._dispatch_shots({"tick": 12, "shots": [row.call(10), row.call(11), row.call(12)]}), 3, "first poll: three new shots")
	t.eq(scene._dispatch_shots({"tick": 14, "shots": [row.call(11), row.call(12), row.call(13), row.call(14)]}), 2, "second poll: two new")
	t.eq(scene._dispatch_shots({"tick": 16, "shots": [row.call(12), row.call(13), row.call(14), row.call(15), row.call(16)]}), 2, "third: two new")
	t.eq(scene.shots_drawn_total, 7, "seven shots, each drawn once")
	t.eq(scene._dispatch_shots({"tick": 16, "shots": [row.call(12), row.call(13), row.call(14), row.call(15), row.call(16)]}), 0,
		"a paused game re-sends the same window: nothing redrawn")
	var twin: Array = row.call(17)
	t.eq(scene._dispatch_shots({"tick": 17, "shots": [twin, twin.duplicate()]}), 2, "two attackers on one spot, one tick: both drawn")
	t.eq(scene._dispatch_shots({"tick": 17, "shots": [twin, twin.duplicate()]}), 0, "and neither twice")
	scene._dispatch_shots({"tick": 60, "shots": [row.call(60)]})
	for key in scene.shot_seen:
		t.ok(int(scene.shot_seen[key]) >= 60 - 18, "the dedup set keeps only the 18-tick window (%s)" % key)
	t.eq(scene._dispatch_shots({"tick": 3, "shots": [row.call(2), row.call(3)]}), 2, "a restarted sim (tick went back): its shots draw")
	scene.free()


func test_dispatcher_tolerates_missing_and_malformed_shots(t) -> void:
	var scene := _fight_scene([])
	t.eq(scene._dispatch_shots({"tick": 5}), 0, "no shots key (Survival, an old bridge): nothing, no error")
	t.eq(scene._dispatch_shots({"tick": 5, "shots": "garbage"}), 0, "not an array")
	t.eq(scene._dispatch_shots({"tick": 5, "shots": [null, 7, [1, 2], ["a", "b", "c", "d", "e"], {"x": 1}, [5, 1.5, null, 2, 3]]}), 0,
		"short, non-numeric and null rows are skipped")
	t.eq(scene.world_fx.pool_count(), 0, "and draw nothing")
	t.eq(scene._dispatch_shots({"tick": 5, "shots": [_row(scene, 5, Vector2i(10, 12), Vector2i(13, 13))]}), 1, "a good row still draws")
	scene.free()


func test_the_first_poll_only_seeds_the_dedup_set(t) -> void:
	var scene := _kestrel_scene()
	t.ok(not scene.bridge_initialized, "a fresh scene")
	t.eq(scene._dispatch_shots({"tick": 9, "shots": [_row(scene, 9, Vector2i(10, 12), Vector2i(13, 13))]}), 0,
		"the window a fresh or restarted scene first reads is history: not replayed")
	scene.bridge_initialized = true
	t.eq(scene._dispatch_shots({"tick": 10, "shots": [_row(scene, 9, Vector2i(10, 12), Vector2i(13, 13)), _row(scene, 10, Vector2i(10, 12), Vector2i(13, 13))]}), 1,
		"later polls draw what is new")
	scene.free()


func test_dispatcher_draws_a_shot_without_a_matching_entity(t) -> void:
	var scene := _fight_scene([])
	t.eq(scene._dispatch_shots({"tick": 4, "shots": [_row(scene, 4, Vector2i(10, 12), Vector2i(13, 13))]}), 1, "drawn from and to its positions")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.TRACER), "in the infantry look")
	t.ok(scene.world_fx.live_bands().has(0), "human by default")
	scene.free()


func test_dispatcher_caps_the_shots_drawn_per_poll(t) -> void:
	var scene := _fight_scene([])
	var rows := []
	for i in 40:
		rows.append(_row(scene, 20 + i % 10, Vector2i(8 + i % 8, 10 + i / 8), Vector2i(12 + i % 5, 14)))
	var drawn: int = scene._dispatch_shots({"tick": 30, "shots": rows})
	t.eq(drawn, scene.SHOTS_PER_POLL, "at most %d drawn, the rest dropped" % scene.SHOTS_PER_POLL)
	t.ok(scene.world_fx.pool_count() <= WorldFx.POOL, "the pool holds")
	t.eq(scene._dispatch_shots({"tick": 30, "shots": rows}), 0, "dropped shots are never drawn late")
	scene.free()


func test_dispatcher_skips_shots_far_outside_the_view(t) -> void:
	var scene := _fight_scene([])
	scene.world_fx.set_view(scene._hex_world(5, 5), Vector2(3, 2))
	t.eq(scene._dispatch_shots({"tick": 4, "shots": [_row(scene, 4, Vector2i(30, 20), Vector2i(33, 21))]}), 0, "both ends far off screen")
	t.eq(scene._dispatch_shots({"tick": 5, "shots": [_row(scene, 5, Vector2i(30, 20), Vector2i(5, 5))]}), 1, "a round landing on screen draws")
	scene.free()


func test_dispatcher_resolves_the_attacker_and_kicks_its_card(t) -> void:
	var scene := _fight_scene([])
	_place(scene, [_unit(scene, 701, "Tank", 1, Vector2i(10, 12)), _unit(scene, 702, "Infantry", 0, Vector2i(14, 12))])
	var tank: Node3D = scene.bridge_nodes[701]
	var card := tank.get_node("UnitVisual") as MeshInstance3D
	var rest := card.position
	var pick: Array = (tank.get_meta("pick_parts") as Array).duplicate(true)
	var row := _row(scene, 30, Vector2i(10, 12), Vector2i(14, 12))
	row[1] = int(row[1]) + 6000  # a little off the tank's own position: still within 0.6 tiles
	t.eq(scene._dispatch_shots({"tick": 30, "shots": [row]}), 1, "the tank's shot")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.BOLT), "an alien tank fires a plasma bolt")
	t.ok(scene.world_fx.live_bands().has(1) and not scene.world_fx.live_bands().has(0), "in alien colours")
	scene._advance_fx(0.03)
	t.ok(card.position.distance_to(rest) > 0.005, "its card kicks")
	t.ok(card.position.x < rest.x, "back, away from a target to the east")
	t.eq(tank.get_meta("pick_parts"), pick, "picking never moves with the kick")
	for i in 10:
		scene._advance_fx(0.05)
	t.ok(card.position == rest, "and comes home exactly")
	scene.free()


func test_a_building_never_recoils(t) -> void:
	var scene := _fight_scene([])
	_place(scene, [_building(scene, 801, "GunTurret", 0, Vector2i(10, 12))])
	var turret: Node3D = scene.bridge_nodes[801]
	var visual := turret.get_node("Visual") as Node3D
	var before := visual.position
	t.eq(scene._dispatch_shots({"tick": 30, "shots": [_row(scene, 30, Vector2i(10, 12), Vector2i(14, 12))]}), 1, "the turret fires")
	scene._advance_fx(0.03)
	t.ok(visual.position == before, "a building does not kick")
	scene.free()


func test_an_hp_drop_under_a_drawn_impact_does_not_flash_twice(t) -> void:
	var scene := _fight_scene([])
	_place(scene, [_unit(scene, 702, "Tank", 1, Vector2i(14, 12))])
	scene.alert_cooldown = 0.0
	scene._dispatch_shots({"tick": 30, "shots": [_row(scene, 30, Vector2i(10, 12), Vector2i(14, 12))]})
	var cards: int = scene.world_fx.pool_count()
	scene._kestrel_impact(scene._hex_world(14, 12), {"owner": 1, "kind": "Tank"})
	t.eq(scene.world_fx.pool_count(), cards, "the shot's impact already marks the hit")
	scene._kestrel_impact(scene._hex_world(4, 4), {"owner": 1, "kind": "Tank"})
	t.ok(scene.world_fx.pool_count() > cards, "a hit nobody was seen firing still flashes")
	scene.free()


func test_an_hp_drop_takes_the_attacker_weight_when_known(t) -> void:
	var scene := _fight_scene([])
	_place(scene, [_unit(scene, 703, "Infantry", 1, Vector2i(10, 12))])
	var rows := []
	rows.append(_row(scene, 20, Vector2i(10, 12), Vector2i(16, 14)))  # the oldest: dropped by the cap, its impact never drawn
	for i in scene.SHOTS_PER_POLL:
		rows.append(_row(scene, 21, Vector2i(10, 12), Vector2i(12, 8 + i % 3)))
	scene._dispatch_shots({"tick": 21, "shots": rows})
	var before: int = scene.world_fx.pool_count()
	var at: Vector3 = scene._hex_world(16, 14)
	scene._kestrel_impact(at, {"owner": 0, "kind": "Tank"})
	var spawned: int = scene.world_fx.pool_count() - before
	var pair := _fx()
	var infantry_hit: int = pair[0].hit(Vector3.ZERO, WorldFx.weight_for("Infantry"), 1)
	_done(pair)
	t.eq(spawned, infantry_hit, "the tank struck by alien infantry flashes an infantry-weight hit (%d cards)" % spawned)
	scene.free()


func test_effects_freeze_while_the_game_is_paused(t) -> void:
	var scene := _fight_scene([])
	var dir := OS.get_cache_dir().path_join("rts_fx_pause_test")
	DirAccess.make_dir_recursive_absolute(dir)
	scene.runtime_directory = dir
	scene._dispatch_shots({"tick": 4, "shots": [_row(scene, 4, Vector2i(10, 12), Vector2i(13, 13))]})
	scene._advance_fx(0.02)
	var t0: float = scene.world_fx.time
	var live: int = scene.world_fx.pool_count()
	var slot: int = scene.world_fx.find_slot(WorldFx.TRACER)
	var at: Transform3D = scene.world_fx.slot_transform(slot)
	scene.set_sim_paused(true)
	for i in 30:
		scene._advance_fx(0.1)
	t.near(scene.world_fx.time, t0, 1e-9, "effect time stands still while paused")
	t.eq(scene.world_fx.pool_count(), live, "no card burns out behind the pause menu")
	t.ok(scene.world_fx.slot_transform(slot).is_equal_approx(at), "a round in flight hangs where it was")
	scene.set_sim_paused(false)
	scene._advance_fx(0.02)
	t.ok(scene.world_fx.time > t0, "time runs again on resume")
	t.ok(not scene.world_fx.slot_transform(slot).is_equal_approx(at), "and the round flies on from where it stopped")
	for i in 40:
		scene._advance_fx(0.1)
	t.eq(scene.world_fx.pool_count(), 0, "then finishes as usual")
	DirAccess.remove_absolute(dir)
	scene.free()


func test_dispatcher_reads_the_shooter_from_the_snapshot_entities(t) -> void:
	var scene := _fight_scene([])
	var tank := _unit(scene, 704, "Tank", 0, Vector2i(10, 12))  # spawned this poll: not in bridge_nodes yet
	t.eq(scene._dispatch_shots({"tick": 8, "entities": [tank], "shots": [_row(scene, 8, Vector2i(10, 12), Vector2i(14, 13))]}), 1, "drawn")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.SHELL), "a human tank fires a glowing shell")
	scene.free()


func test_survival_never_draws_shots(t) -> void:
	var survival = MainScene.instantiate()
	survival.bridge_initialized = true
	t.eq(survival._dispatch_shots({"tick": 8, "shots": [[8, 65536, 65536, 131072, 65536]]}), 0, "no effect system: nothing")
	t.ok(FileAccess.get_file_as_string("res://scripts/earthfront_3d.gd").contains("if world_art_on and world_fx != null:\n\t\t_dispatch_shots(parsed)"),
		"the poll only dispatches shots on Kestrel")
	survival.free()


func test_landed_shot_records_do_not_pile_up(t) -> void:
	var scene := _fight_scene([])
	scene._dispatch_shots({"tick": 4, "shots": [_row(scene, 4, Vector2i(10, 12), Vector2i(13, 13))]})
	for i in 20:
		scene._advance_fx(0.1)
	scene._dispatch_shots({"tick": 70, "shots": [_row(scene, 70, Vector2i(10, 12), Vector2i(14, 13))]})
	t.eq(scene.shot_impacts.size(), 1, "a poll drops the records of shots long landed, HP drop or not")
	scene.free()
