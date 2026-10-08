extends RefCounted
## Kind names in the order toasts (fix round, final review I5): the ticker built its text from the raw enum name
## ("GUNTURRET FOUNDATION ORDERED") and the HUD's _sentence case-folds it, so Kestrel read "Gunturret", "Vehiclefactory",
## "Antiarmor". On Kestrel (world art on) earthfront_3d._kind_text spells the kind by LiveAdapter.KIND_NAMES, as the HUD
## cards do; Survival keeps the raw upper-cased name, so its ticker text is byte for byte what it was.
const MainScene = preload("res://main.tscn")
const Adapter = preload("res://scripts/ui/live_adapter.gd")
const RUNTIME := "user://kind_text_runtime"
## Every kind a toast can name: buildings (place, foundation, producer) and units (train, unit ready).
const BUILDINGS := ["CommandCenter", "PowerPlant", "Refinery", "Barracks", "VehicleFactory", "Airfield", "SupplyDepot",
	"Battery", "GunTurret", "AaTurret", "Wall", "ResearchLab", "AntimatterPlant"]
const UNITS := ["Infantry", "AntiArmor", "Tank", "Helicopter", "Harvester", "Capital"]


func _scene(kestrel: bool) -> Node3D:
	var scene = MainScene.instantiate()
	scene.world_art_on = kestrel
	return scene


func _src() -> String:
	return (load("res://scripts/earthfront_3d.gd") as GDScript).source_code


func test_every_kind_has_a_spelled_name(t) -> void:
	for kind in BUILDINGS + UNITS:
		t.ok(Adapter.KIND_NAMES.has(kind), "KIND_NAMES spells %s" % kind)


func test_kestrel_toasts_spell_every_kind_with_its_word_breaks(t) -> void:
	var scene := _scene(true)
	var want := {
		"CommandCenter": "Command centre", "PowerPlant": "Reactor", "Refinery": "Refinery", "Barracks": "Barracks",
		"VehicleFactory": "Vehicle factory", "Airfield": "Airfield", "SupplyDepot": "Supply depot", "Battery": "Battery",
		"GunTurret": "Gun turret", "AaTurret": "Aa battery", "Wall": "Field wall", "ResearchLab": "Research lab",
		"AntimatterPlant": "Antimatter plant",
	}
	for kind in BUILDINGS:
		var place := Adapter._sentence("PLACE %s, GREEN IS VALID" % scene._kind_text(kind))
		t.ok(place.begins_with("Place " + str(want[kind]).to_lower() + ","), "%s: %s" % [kind, place])
		var ordered := Adapter._sentence("%s FOUNDATION ORDERED" % scene._kind_text(kind))
		t.eq(ordered, "%s foundation ordered" % want[kind], "%s foundation toast" % kind)
	var units := {"Infantry": "Riflemen", "AntiArmor": "Rocket team", "Tank": "Battle tank", "Helicopter": "Gunship",
		"Harvester": "Harvester", "Capital": "Capital unit"}
	for kind in UNITS:
		var ready := Adapter._sentence(scene._kind_text(kind) + " REPORTING FOR DUTY")
		t.eq(ready, "%s reporting for duty" % units[kind], "%s unit ready toast" % kind)
	t.eq(Adapter._sentence("%s ORDER SENT TO %s" % [scene._kind_text("Tank"), scene._kind_text("VehicleFactory")]),
		"Battle tank order sent to vehicle factory", "the train toast names both")
	t.eq(Adapter._sentence("GUNTURRET FOUNDATION ORDERED"), "Gunturret foundation ordered", "(the old text, for the record)")
	t.eq(Adapter._sentence("%s FOUNDATION ORDERED" % scene._kind_text("GunTurret")), "Gun turret foundation ordered", "the review's example")
	t.eq(scene._kind_text("SomethingNew"), "SOMETHINGNEW", "an unknown kind falls back to its raw name")
	scene.free()


func test_survival_ticker_text_is_byte_identical(t) -> void:
	var scene := _scene(false)
	for kind in BUILDINGS + UNITS + ["SomethingNew"]:
		t.eq(scene._kind_text(kind), kind.to_upper(), "Survival: %s is the raw name upper-cased, as before" % kind)
	scene.free()


func test_the_five_sites_use_the_helper(t) -> void:
	var src := _src()
	for line in [
		"objective_label.text = \"%s ORDER SENT TO %s\" % [_kind_text(kind_name), _kind_text(producer_kind)]",
		"objective_label.text = \"BUILD %s BEFORE TRAINING THIS UNIT\" % _kind_text(producer_kind)",
		"objective_label.text = \"%s FOUNDATION ORDERED\" % _kind_text(kind_name)",
		"_show_notification(\"UNIT READY\", _kind_text(kind_name) + \" REPORTING FOR DUTY\", Color(\"65e4da\"))",
	]:
		t.ok(src.contains(line), "site uses _kind_text: %s" % line)
	t.ok(src.contains("objective_label.text = \"PLACE %s \\u2014 GREEN IS VALID • ESC CANCELS\" % _kind_text(kind_name)"), "the placement site too")
	for old in ["kind_name.to_upper()", "producer_kind.to_upper()"]:
		t.eq(src.count(old), 0, "no raw %s left" % old)


func test_the_build_and_train_toasts_on_a_live_scene(t) -> void:
	for kestrel in [true, false]:
		var scene := _scene(kestrel)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME))
		scene.runtime_directory = RUNTIME
		scene.bridge_active = true
		scene.bridge_money = 1000  # kestrel-depth Task 7: Kestrel refuses an order it cannot pay for before sending it
		scene.objective_label = Label.new()
		scene._create_materials()
		scene._write_bridge_build("GunTurret", Vector3.ZERO)
		t.eq(scene.objective_label.text, "GUN TURRET FOUNDATION ORDERED" if kestrel else "GUNTURRET FOUNDATION ORDERED", "build toast (kestrel %s)" % kestrel)
		scene._write_bridge_train("Tank")
		t.eq(scene.objective_label.text, "BUILD VEHICLE FACTORY BEFORE TRAINING THIS UNIT" if kestrel else "BUILD VEHICLEFACTORY BEFORE TRAINING THIS UNIT", "train toast with no factory (kestrel %s)" % kestrel)
		scene._arm_build("GunTurret")
		t.eq(scene.objective_label.text, "PLACE %s \u2014 GREEN IS VALID \u2022 ESC CANCELS" % ("GUN TURRET" if kestrel else "GUNTURRET"), "placement toast, the em dash and bullet as before (kestrel %s)" % kestrel)
		var dir := DirAccess.open(RUNTIME.path_join("commands"))
		if dir != null:
			for f in dir.get_files():
				dir.remove(f)
		scene.objective_label.free()
		scene.free()
