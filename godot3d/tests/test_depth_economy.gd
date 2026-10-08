extends RefCounted
## Task 18 (kestrel-depth): the Refinery's price rises by 50 with each one the player owns. The Kestrel snapshot carries
## the next price as `depth.refinery_cost`, and the build card, the placement preview, the planned spend chip and the
## funds check all use it. A Kestrel building on its repair cooldown (`repair_cd`) is not sent a repair: the denied cue
## and a toast say when it is ready. Survival never carries either key and keeps its flat price and instant repair.
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const Stub = preload("res://tests/stub_game.gd")
const Feedback = preload("res://scripts/ui/feedback_events.gd")
const Orders = preload("res://tests/test_orders_protocol.gd")


func _find(items: Array, key: String, value: Variant) -> Dictionary:
	for i in items:
		if i.get(key) == value:
			return i
	return {}


func _build_adapter(refinery_cost: int) -> Array:
	var g := Stub.new()
	if refinery_cost >= 0:
		g.bridge_snapshot = {"depth": {"upgrades": [0, 0, 0], "upgrade_costs": [150, 150, 150], "refinery_cost": refinery_cost}}
	var a := Adapter.new(g)
	a.tab = "build"
	return [g, a]


func test_the_refinery_card_shows_the_depth_price(t) -> void:
	var p := _build_adapter(250)
	var cards: Array = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.eq(_find(cards, "id", "refinery")["cost"], "250 M 20 kW", "the card reads the depth price")
	t.eq(_find(cards, "id", "barracks")["cost"], "200 M 10 kW", "other cards keep their own price")
	p[0].bridge_money = 200
	cards = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.ok(_find(cards, "id", "refinery").get("short", false), "200 is short of 250")
	t.eq(_find(cards, "id", "refinery")["prereq"], "Need 50 more material", "the shortfall uses the depth price")
	t.ok(not _find(cards, "id", "barracks").get("short", false), "200 still buys a barracks")


func test_an_armed_refinery_previews_and_plans_the_depth_price(t) -> void:
	var p := _build_adapter(300)
	p[0].build_mode = "Refinery"
	var vm: Dictionary = p[1].hud_vm(0.0)
	var placement: Dictionary = vm["build_placement"]
	t.eq(placement["costs"][0]["value"], "300", "materials in the preview")
	t.ok(String(placement["note"]).contains("from 840 to 540"), "material after placing (%s)" % placement["note"])
	t.eq(vm["build_top"]["chips"][0]["note"], "planned -300", "planned spend")
	p[0].bridge_money = 250
	vm = p[1].hud_vm(0.0)
	t.eq(vm["build_placement"]["status"], "Materials 50 short", "short against the depth price")
	var short_rows: Array = vm["build_alerts"]["rows"] if vm["build_alerts"] is Dictionary else vm["build_alerts"]
	var texts := []
	for r in short_rows:
		texts.append(String(r.get("text", "")))
	t.ok(texts.has("Refinery: materials 50 short"), "the alert row uses it too (%s)" % [texts])


func test_without_a_depth_block_the_refinery_keeps_its_card_price(t) -> void:
	var p := _build_adapter(-1)
	var cards: Array = p[1].hud_vm(0.0)["deck"]["body"]["cards"]
	t.eq(_find(cards, "id", "refinery")["cost"], "150 M 20 kW", "Survival: the card price")
	t.eq(Feedback.build_cost("Refinery", {}), 150, "the funds check's price without depth")
	t.eq(Feedback.build_cost("Refinery", {"depth": {"refinery_cost": 350}}), 350, "and with it")


func _scene(o, kestrel: bool) -> Node3D:
	var scene = o._scene(kestrel)
	scene.objective_label = Label.new()
	return scene


func _done(o, scene) -> void:
	scene.objective_label.free()
	o._done(scene)


func test_the_kestrel_funds_check_uses_the_depth_price(t) -> void:
	var o := Orders.new()
	var scene = _scene(o, true)
	var ground: Vector3 = scene._hex_world(8, 14)
	scene.bridge_snapshot = {"depth": {"refinery_cost": 250}}
	scene.bridge_money = 200
	scene._write_bridge_build("Refinery", ground)
	t.eq(o._lines(), [], "200 of 250: denied, nothing written")
	scene.bridge_money = 260
	scene._write_bridge_build("Refinery", ground)
	var lines := o._lines()
	t.ok(lines.size() == 1 and String(lines[0]).begins_with("build,Refinery,"), "260 of 250 is sent (%s)" % [lines])
	_done(o, scene)


func _building(scene, id: int, kind: String, tile: Vector2i, repair_cd: int) -> Dictionary:
	var bits: Vector2i = scene._world_to_sim_bits(scene._hex_world(tile.x, tile.y))
	var e := {"id": id, "category": "building", "kind": kind, "owner": 0, "x_bits": bits.x, "z_bits": bits.y,
		"hp_bits": 65536 * 200, "max_hp_bits": 65536 * 400}
	if repair_cd >= 0:
		e["repair_cd"] = repair_cd
	return e


func test_a_repair_on_cooldown_is_denied_on_kestrel(t) -> void:
	var o := Orders.new()
	var scene = _scene(o, true)
	o._place(scene, [_building(scene, 800, "Barracks", Vector2i(6, 12), 300), _building(scene, 801, "Refinery", Vector2i(9, 12), 0)])
	t.eq(int(scene.bridge_nodes[800].get_meta("repair_cd", -1)), 300, "the snapshot's cooldown reaches the node")
	scene._set_selection([scene.bridge_nodes[800]])
	t.eq(scene._repair_block(scene.bridge_nodes[800]), "REPAIR RECHARGING", "300 ticks left")
	scene._write_bridge_structure_action("repair")
	t.eq(o._lines(), [], "nothing written while it recharges")
	t.eq(scene.objective_label.text, "REPAIR RECHARGING", "the denial is said")
	scene._set_selection([scene.bridge_nodes[801]])
	t.eq(scene._repair_block(scene.bridge_nodes[801]), "", "a ready building")
	scene._write_bridge_structure_action("repair")
	t.eq(o._lines(), ["repair,801"], "a ready building is repaired")
	scene._set_selection([scene.bridge_nodes[800]])
	scene._write_bridge_structure_action("sell")
	t.eq(o._lines(), ["sell,800"], "selling ignores the repair cooldown")
	_done(o, scene)


func test_survival_repair_is_never_held_back(t) -> void:
	var o := Orders.new()
	var scene = _scene(o, false)
	scene.world_art_on = false
	o._place(scene, [_building(scene, 810, "Barracks", Vector2i(6, 12), -1)])
	scene.bridge_nodes[810].set_meta("repair_cd", 300)
	scene._set_selection([scene.bridge_nodes[810]])
	t.eq(scene._repair_block(scene.bridge_nodes[810]), "", "Survival has no repair cooldown")
	scene._write_bridge_structure_action("repair")
	t.eq(o._lines(), ["repair,810"], "sent as before")
	_done(o, scene)


## Found by the Task 18 live check: a selected building died during its repair and `_order_units` (the queue markers
## call it every frame) handed the freed node to a typed lambda, one engine ERROR per frame. A dead selection is skipped.
func test_a_selection_that_dies_is_skipped_by_the_order_units(t) -> void:
	var o := Orders.new()
	var scene = _scene(o, true)
	o._place(scene, [o._unit(scene, 820, "Infantry", 0, Vector2i(6, 12)), _building(scene, 821, "Barracks", Vector2i(9, 12), 0)])
	var soldier: Node3D = scene.bridge_nodes[820]
	scene._set_selection([soldier, scene.bridge_nodes[821]])
	t.eq(scene._order_units(), [soldier], "the living soldier is orderable")
	scene.bridge_nodes[821].free()
	soldier.free()
	t.eq(scene._order_units(), [], "nothing orderable is left, and no error")
	_done(o, scene)
