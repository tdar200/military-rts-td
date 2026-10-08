extends RefCounted
## Kestrel building states (kestrel-depth Task 8): a damaged building smokes below half HP and burns below a quarter, a
## working one (producing, refining ore, researching, powered) puffs now and then. Every card comes from the pooled WorldFx,
## gated by the fog, frozen by the pause, and Survival never draws any.
const BuildingStates := preload("res://scripts/world/building_states.gd")
const WorldFx := preload("res://scripts/world/world_fx.gd")
const FogView := preload("res://scripts/world/fog_view.gd")
const MainScene = preload("res://main.tscn")

const HP := 65536  # one HP in Fixed bits, as the snapshot sends it


func _fx() -> Array:
	var parent := Node3D.new()
	var fx = WorldFx.new()
	fx.build(parent)
	return [fx, parent]


func _done(pair: Array) -> void:
	(pair[1] as Node3D).free()


# ---------------------------------------------------------------- pure rules

func test_states_follow_the_hp_thresholds(t) -> void:
	t.eq(BuildingStates.state_for(49, 100, false), "smoke", "49% smokes")
	t.eq(BuildingStates.state_for(24, 100, false), "fire", "24% burns")
	t.eq(BuildingStates.state_for(100, 100, true), "working", "full HP while producing: working")
	t.eq(BuildingStates.state_for(100, 100, false), "ok", "full HP and idle: nothing")
	t.eq(BuildingStates.state_for(50, 100, false), "ok", "exactly half is not smoke yet")
	t.eq(BuildingStates.state_for(25, 100, false), "smoke", "exactly a quarter smokes, it does not burn yet")
	t.eq(BuildingStates.state_for(49, 100, true), "smoke", "damage outranks work")
	t.eq(BuildingStates.state_for(24, 100, true), "fire", "fire outranks work")
	t.eq(BuildingStates.state_for(1, 100, false), "fire", "a building on its last HP burns")
	t.eq(BuildingStates.state_for(49 * HP, 100 * HP, false), "smoke", "Fixed bits read the same (no overflow)")
	t.eq(BuildingStates.state_for(24 * HP + HP / 2, 100 * HP, false), "fire", "24.5% burns")
	t.eq(BuildingStates.state_for(0, 0, false), "ok", "no max HP: no damage state")
	t.eq(BuildingStates.state_for(0, 0, true), "working", "no max HP but working")


func test_emit_cadence_per_state(t) -> void:
	t.ok(not BuildingStates.next_emit("smoke", 1.0, 1.59), "smoke waits 0.6 s")
	t.ok(BuildingStates.next_emit("smoke", 1.0, 1.6), "then puffs")
	t.ok(not BuildingStates.next_emit("fire", 1.0, 1.34), "fire waits 0.35 s")
	t.ok(BuildingStates.next_emit("fire", 1.0, 1.35), "then flickers")
	t.ok(not BuildingStates.next_emit("working", 1.0, 3.49), "a working puff waits 2.5 s")
	t.ok(BuildingStates.next_emit("working", 1.0, 3.5), "then puffs")
	t.ok(not BuildingStates.next_emit("ok", 0.0, 1000.0), "a healthy idle building never emits")
	t.ok(not BuildingStates.next_emit("garbage", 0.0, 1000.0), "an unknown state never emits")
	t.near(BuildingStates.interval("smoke"), 0.6, 1e-9, "smoke interval")
	t.near(BuildingStates.interval("fire"), 0.35, 1e-9, "fire interval")
	t.near(BuildingStates.interval("working"), 2.5, 1e-9, "working interval")


func test_working_reads_production_refining_research_and_power(t) -> void:
	var barracks := {"kind": "Barracks", "owner": 0, "construction": 0, "production_name": "Infantry"}
	var powered := {"power": 1000}
	t.ok(BuildingStates.is_working(barracks, powered, false), "a powered barracks training")
	t.ok(not BuildingStates.is_working(barracks, {"power": 300}, false), "under half power it stalls: no puff")
	t.ok(BuildingStates.is_working(barracks, {}, false), "no services entry: counted as powered")
	var idle := barracks.duplicate()
	idle["production_name"] = ""
	t.ok(not BuildingStates.is_working(idle, powered, false), "an idle barracks")
	var site := barracks.duplicate()
	site["construction"] = 40
	t.ok(not BuildingStates.is_working(site, powered, false), "a construction site never works")
	var refinery := {"kind": "Refinery", "owner": 0, "construction": 0, "production_name": ""}
	t.ok(BuildingStates.is_working(refinery, {"power": 1000, "ore": 30}, false), "a refinery with ore to process")
	t.ok(not BuildingStates.is_working(refinery, {"power": 1000, "ore": 0}, false), "an empty refinery")
	t.ok(not BuildingStates.is_working(refinery, {"power": 1000, "ore": 4}, false), "under one batch of ore: nothing to process")
	t.ok(not BuildingStates.is_working(refinery, {"power": 400, "ore": 200}, false), "an unpowered refinery processes nothing")
	var factory := {"kind": "VehicleFactory", "owner": 0, "construction": 0, "production_name": "Tank"}
	t.ok(BuildingStates.is_working(factory, powered, false), "a factory building a tank")
	var lab := {"kind": "ResearchLab", "owner": 0, "construction": 0, "production_name": ""}
	t.ok(BuildingStates.is_working(lab, powered, true), "a powered lab while research runs")
	t.ok(not BuildingStates.is_working(lab, powered, false), "a lab with no research (or paused research)")
	var alien_lab := lab.duplicate()
	alien_lab["owner"] = 1
	t.ok(not BuildingStates.is_working(alien_lab, powered, true), "the player's research never lights an alien lab")
	var cc := {"kind": "CommandCenter", "owner": 0, "construction": 0, "production_name": ""}
	t.ok(not BuildingStates.is_working(cc, powered, true), "a command centre with nothing queued")


# ---------------------------------------------------------------- emitter on a bare WorldFx

func test_forty_burning_buildings_never_exceed_the_pool(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	var states = BuildingStates.new()
	for i in 40:
		states.update(i, "fire", Vector3(float(i % 8) * 1.5, 0.0, float(i / 8) * 1.5), 0.6, 1.5, i % 2, fx.time)
	var peak := 0
	var peak_state := 0
	for f in 600:
		fx.advance(1.0 / 60.0)
		states.step(fx, fx.time)
		peak = maxi(peak, fx.pool_count())
		var mine := 0
		for i in 40:
			mine += fx.tag_count(i)
		peak_state = maxi(peak_state, mine)
	t.ok(peak <= WorldFx.POOL, "never more than the pool's %d cards (peak %d)" % [WorldFx.POOL, peak])
	t.ok(peak_state <= WorldFx.STATE_ROOM, "building states keep below their room of %d cards (peak %d)" % [WorldFx.STATE_ROOM, peak_state])
	t.ok(peak_state > 20, "and they did burn (peak %d)" % peak_state)
	t.ok(fx.hit(Vector3(3, 0, 3), 2, 0) > 0, "a combat hit still finds room among 40 fires")
	_done(pair)


func test_emission_is_deterministic(t) -> void:
	var runs := []
	for r in 2:
		var pair := _fx()
		var fx = pair[0]
		var states = BuildingStates.new()
		states.update(7, "fire", Vector3(1, 0, 1), 0.6, 1.5, 0, fx.time)
		states.update(8, "smoke", Vector3(3, 0, 1), 0.6, 1.2, 1, fx.time)
		states.update(9, "working", Vector3(5, 0, 1), 0.5, 1.4, 0, fx.time)
		var trace := []
		for f in 300:
			fx.advance(1.0 / 60.0)
			trace.append(states.step(fx, fx.time))
		var tfs := []
		for slot in WorldFx.POOL:
			if fx.slot_live(slot):
				tfs.append(fx.slot_transform(slot))
		runs.append([trace, fx.spawned_total(), tfs])
		_done(pair)
	t.eq(runs[0][0], runs[1][0], "the same emissions frame by frame")
	t.eq(runs[0][1], runs[1][1], "the same card count")
	t.ok(runs[0][2] == runs[1][2], "every card in the same place")


func test_states_spawn_their_own_looks(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	var states = BuildingStates.new()
	states.update(1, "smoke", Vector3(0, 0, 0), 0.6, 1.5, 0, fx.time)
	for f in 60:
		fx.advance(1.0 / 60.0)
		states.step(fx, fx.time)
	t.ok(fx.live_sprites().has(WorldFx.SMOKE), "smoke rises")
	t.ok(not fx.live_sprites().has(WorldFx.FIREBALL), "and does not burn")
	fx.release(1)
	states.update(1, "fire", Vector3(0, 0, 0), 0.6, 1.5, 0, fx.time)
	for f in 60:
		fx.advance(1.0 / 60.0)
		states.step(fx, fx.time)
	t.ok(fx.live_sprites().has(WorldFx.FIREBALL), "fire burns")
	t.ok(fx.live_sprites().has(WorldFx.FLASH), "with a flicker")
	t.ok(fx.live_sprites().has(WorldFx.SMOKE), "under its smoke")
	states.update(1, "ok", Vector3(0, 0, 0), 0.6, 1.5, 0, fx.time)
	var before: int = fx.spawned_total()
	for f in 300:
		fx.advance(1.0 / 60.0)
		states.step(fx, fx.time)
	t.eq(fx.spawned_total(), before, "repaired: nothing more")
	_done(pair)


func test_a_fogged_building_emits_nothing(t) -> void:
	var pair := _fx()
	var fx = pair[0]
	var fog := FogView.new()
	fog.configure(2.1, 1.0, 0.68, 0.70)
	var lit := Vector3(2.1 + 4 * 0.68, 0.0, 1.0 + 4 * 0.70)  # cell (4, 4)
	var dark := Vector3(2.1 + 30 * 0.68, 0.0, 1.0 + 20 * 0.70)  # cell (30, 20)
	var mask := "0".repeat(44 * 26)
	mask = mask.substr(0, 4 * 44 + 4) + "2" + mask.substr(4 * 44 + 5)
	fog.parse(mask, 44, 26)
	fog.parse(mask, 44, 26)  # twice: the previous poll saw the same, so nothing is "seen recently" in the dark
	t.ok(fog.is_visible(lit) and not fog.is_visible(dark), "one lit cell in the dark")
	fx.fog = fog
	t.eq(fx.smoke(dark, 1.2), -1, "smoke on an unseen building: culled")
	t.eq(fx.fire(dark, 1.2), -1, "fire on an unseen building: culled")
	t.eq(fx.puff(dark, 1.2), -1, "a working puff on an unseen building: culled")
	t.eq(fx.pool_count(), 0, "nothing spawned")
	t.ok(fx.smoke(lit, 1.2) >= 0, "the lit building smokes")
	var states = BuildingStates.new()
	states.update(5, "fire", dark, 0.6, 1.5, 1, fx.time)
	for f in 120:
		fx.advance(1.0 / 60.0)
		states.step(fx, fx.time)
	t.eq(fx.tag_count(5), 0, "a burning building under the fog draws nothing")
	_done(pair)


# ---------------------------------------------------------------- in the Kestrel scene

func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	scene._sync_ground(JSON.parse_string(f.get_as_text()))
	return scene


## The fog-off fixture's buildings (the opening base and the alien side), with `hp_pct` per id and `production` per id applied:
## the damaged and working fixtures every scene test reads.
func _fixture_buildings(hp_pct: Dictionary, production := {}) -> Array:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot_fog_off.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	var out := []
	for e in snap["entities"]:
		if String(e.get("category", "")) != "building":
			continue
		var d: Dictionary = e.duplicate()
		var id := int(d["id"])
		if hp_pct.has(id):
			d["hp_bits"] = int(d["max_hp_bits"]) * int(hp_pct[id]) / 100
		if production.has(id):
			d["production_name"] = String(production[id])
		out.append(d)
	return out


func _by_kind(entities: Array, kind: String, owner := 0) -> int:
	for e in entities:
		if String(e["kind"]) == kind and int(e["owner"]) == owner:
			return int(e["id"])
	return -1


func _scene_with(entities: Array, tick := 100) -> Node3D:
	var scene := _kestrel_scene()
	scene.bridge_tick = tick
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	scene.world_fx.set_view(scene._hex_world(20, 12), Vector2(40, 30))  # the whole map in view
	return scene


func _run(scene, seconds: float) -> void:
	for i in int(seconds * 20.0):
		scene._advance_fx(0.05)


func test_the_idle_fixture_draws_nothing(t) -> void:
	var entities := _fixture_buildings({})
	var scene := _scene_with(entities)
	_run(scene, 5.0)
	t.eq(scene.world_fx.spawned_total(), 0, "the opening base and the alien side at full HP, idle: not one card")
	scene.free()


func test_damaged_buildings_smoke_and_burn_in_the_scene(t) -> void:
	var base := _fixture_buildings({})
	var barracks := _by_kind(base, "Barracks")
	var plant := _by_kind(base, "PowerPlant")
	var entities := _fixture_buildings({barracks: 40, plant: 20})
	var scene := _scene_with(entities)
	t.eq(scene.building_states.state_of(barracks), "smoke", "the barracks at 40% smokes")
	t.eq(scene.building_states.state_of(plant), "fire", "the reactor at 20% burns")
	_run(scene, 2.0)
	t.ok(scene.world_fx.tag_count(barracks) > 0, "smoke cards over the barracks")
	t.ok(scene.world_fx.tag_count(plant) > 0, "fire cards over the reactor")
	t.ok(scene.world_fx.live_sprites().has(WorldFx.FIREBALL), "a flame")
	scene.free()


func test_a_working_barracks_puffs_and_an_idle_one_does_not(t) -> void:
	var base := _fixture_buildings({})
	var barracks := _by_kind(base, "Barracks")
	var entities := _fixture_buildings({}, {barracks: "Infantry"})
	var scene := _kestrel_scene()
	scene.bridge_services[barracks] = {"id": barracks, "power": 1000}
	scene.bridge_tick = 100
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	scene.world_fx.set_view(scene._hex_world(20, 12), Vector2(40, 30))
	t.eq(scene.building_states.state_of(barracks), "working", "training: working")
	_run(scene, 1.5)
	t.ok(scene.world_fx.tag_count(barracks) > 0, "a puff over the working barracks")
	t.eq(scene.world_fx.spawned_total(), scene.world_fx.tag_count(barracks), "and nothing else drew")
	scene.bridge_services[barracks] = {"id": barracks, "power": 200}
	scene.bridge_tick = 104
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	t.eq(scene.building_states.state_of(barracks), "", "unpowered, its queue stalls: no state, no puff")
	scene.free()


func test_effects_stop_for_sites_deaths_memories_and_fog(t) -> void:
	var base := _fixture_buildings({})
	var barracks := _by_kind(base, "Barracks")
	var entities := _fixture_buildings({barracks: 20})
	var scene := _scene_with(entities)
	_run(scene, 1.0)
	t.ok(scene.world_fx.tag_count(barracks) > 0, "burning")
	# A construction site never shows a state.
	for e in entities:
		if int(e["id"]) == barracks:
			e["construction"] = 50
	scene.bridge_tick = 104
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	t.eq(scene.building_states.state_of(barracks), "", "a site has no state")
	t.eq(scene.world_fx.tag_count(barracks), 0, "and its cards are gone at once")
	for e in entities:
		if int(e["id"]) == barracks:
			e["construction"] = 0
	scene.bridge_tick = 108
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	_run(scene, 1.0)
	t.ok(scene.world_fx.tag_count(barracks) > 0, "finished and still burning")
	# Death: the building leaves the snapshot.
	scene.bridge_tick = 112
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities.filter(func(e): return int(e["id"]) != barracks))
	t.eq(scene.building_states.state_of(barracks), "", "a dead building has no state")
	t.eq(scene.world_fx.tag_count(barracks), 0, "its smoke and fire stop with it")
	scene.free()


func test_a_remembered_or_fogged_alien_building_shows_no_live_state(t) -> void:
	var base := _fixture_buildings({})
	var alien := -1
	for e in base:
		if int(e["owner"]) == 1:
			alien = int(e["id"])
			break
	t.ok(alien >= 0, "the fixture has an alien building")
	var entities := _fixture_buildings({alien: 20})
	var scene := _scene_with(entities)
	_run(scene, 1.0)
	t.ok(scene.world_fx.tag_count(alien) > 0, "fog off: a burning alien building burns")
	# The same building as a memory.
	for e in entities:
		if int(e["id"]) == alien:
			e["remembered"] = true
	scene.bridge_tick = 104
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	t.eq(scene.building_states.state_of(alien), "", "a memory carries no live state")
	t.eq(scene.world_fx.tag_count(alien), 0, "and its cards are gone")
	_run(scene, 1.0)
	t.eq(scene.world_fx.tag_count(alien), 0, "nothing new on a memory")
	# Live again but its cell is dark (a building still listed on ground out of sight).
	for e in entities:
		if int(e["id"]) == alien:
			e.erase("remembered")
	scene._sync_fog({"tick": 108, "fog": "0".repeat(44 * 26)})
	scene._sync_fog({"tick": 108, "fog": "0".repeat(44 * 26)})
	scene.bridge_tick = 108
	scene.bridge_initialized = false
	scene._sync_bridge_entities(entities)
	_run(scene, 1.0)
	t.eq(scene.world_fx.tag_count(alien), 0, "an unseen building draws nothing")
	scene.free()


func test_states_freeze_while_paused_and_clear_on_restart(t) -> void:
	var base := _fixture_buildings({})
	var barracks := _by_kind(base, "Barracks")
	var entities := _fixture_buildings({barracks: 20})
	var scene := _scene_with(entities, 500)
	var dir := OS.get_cache_dir().path_join("rts_building_states_pause_test")
	DirAccess.make_dir_recursive_absolute(dir)
	scene.runtime_directory = dir
	_run(scene, 1.0)
	var spawned: int = scene.world_fx.spawned_total()
	var live: int = scene.world_fx.tag_count(barracks)
	scene.set_sim_paused(true)
	_run(scene, 3.0)
	t.eq(scene.world_fx.spawned_total(), spawned, "paused: no new smoke or fire")
	t.eq(scene.world_fx.tag_count(barracks), live, "and the cards hang where they were")
	scene.set_sim_paused(false)
	_run(scene, 1.0)
	t.ok(scene.world_fx.spawned_total() > spawned, "resumed: it burns on")
	# A restarted sim (the tick goes back): the old match's states and cards are gone.
	scene.bridge_tick = 3
	scene.bridge_initialized = false
	scene._sync_bridge_entities(_fixture_buildings({}))
	t.eq(scene.world_fx.tag_count(barracks), 0, "restart clears the cards")
	t.eq(scene.building_states.count(), 0, "and the states")
	DirAccess.remove_absolute(dir)
	scene.free()


func test_survival_never_draws_building_states(t) -> void:
	var survival = MainScene.instantiate()
	survival._create_materials()
	survival._setup_environment()
	survival._build_terrain()
	t.eq(survival.building_states, null, "no building states without the Kestrel effects")
	var b := {"id": 77, "category": "building", "kind": "Barracks", "owner": 0, "x_bits": 65536 * 8, "z_bits": 65536 * 8,
		"hp_bits": 65536 * 10, "max_hp_bits": 65536 * 100, "construction": 0, "construction_total": 100}
	survival._sync_bridge_entities([b])
	survival._advance_fx(0.5)
	t.eq(survival.world_fx, null, "Survival keeps its sphere effects")
	t.ok(FileAccess.get_file_as_string("res://scripts/earthfront_3d.gd").contains("if category == \"building\" and building_states != null:"),
		"the entity sync only feeds building states on Kestrel")
	survival.free()
