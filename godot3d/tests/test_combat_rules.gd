extends RefCounted
## combat_rules.gd mirrors three Rust tables. These tests parse the numbers out of the Rust source (not comment text), so a
## balance change in the sim fails here. Hand-checked values pin the helpers.
const Rules := preload("res://scripts/ui/combat_rules.gd")


func _src(file: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../crates/core/src/game/").path_join(file), FileAccess.READ)
	return "" if f == null else f.get_as_text()


## Text from `start` up to (not including) the next `stop` after it.
func _between(src: String, start: String, stop: String) -> String:
	var i := src.find(start)
	if i < 0:
		return ""
	var j := src.find(stop, i + start.length())
	return src.substr(i, (j if j >= 0 else src.length()) - i)


## "Fixed::from_ratio(a, b)" or "Fixed::ONE" as a percent change from 1.
func _pct(expr: String) -> int:
	if expr.begins_with("Fixed::ONE"):
		return 0
	var re := RegEx.create_from_string("from_ratio\\((\\d+),\\s*(\\d+)\\)")
	var m := re.search(expr)
	return int(round(100.0 * float(m.get_string(1)) / float(m.get_string(2)))) - 100


func test_damage_matrix_matches_the_sim(t) -> void:
	var src := _src("stats.rs")
	t.ok(src != "", "stats.rs is reachable from the project")
	var body := _between(src, "pub const fn damage_multiplier", "\n}\n")
	t.ok(body != "", "found damage_multiplier")
	var arm := RegEx.create_from_string("((?:\\(DamageType::\\w+,\\s*ArmorType::\\w+\\)\\s*\\|?\\s*)+)=>\\s*\\{?\\s*(Fixed::from_ratio\\(\\d+,\\s*\\d+\\)|Fixed::ONE)")
	var pair := RegEx.create_from_string("DamageType::(\\w+),\\s*ArmorType::(\\w+)")
	var parsed := {}
	for m in arm.search_all(body):
		for p in pair.search_all(m.get_string(1)):
			parsed["%s/%s" % [p.get_string(1), p.get_string(2)]] = _pct(m.get_string(2))
	t.eq(parsed.size(), 5, "the sim lists five non-neutral pairs")
	# Every pair of the 3 x 3 matrix agrees, neutral included.
	for d in ["Ballistic", "AntiArmor", "Explosive"]:
		for a in ["Flesh", "Plated", "Structure"]:
			t.eq(Rules.multiplier_pct(d, a), int(parsed.get("%s/%s" % [d, a], 0)), "%s vs %s" % [d, a])
	# And the Rust enums have no variant the client lacks.
	var dmg := _between(src, "pub enum DamageType", "}")
	var arm_enum := _between(src, "pub enum ArmorType", "}")
	for name in ["Ballistic", "AntiArmor", "Explosive"]:
		t.ok(dmg.contains("\n    %s," % name), "DamageType has %s" % name)
	for name in ["Flesh", "Plated", "Structure"]:
		t.ok(arm_enum.contains("\n    %s," % name), "ArmorType has %s" % name)
	var variant := RegEx.create_from_string("\\n    [A-Z]\\w*,")
	t.eq(variant.search_all(dmg).size(), 3, "DamageType has exactly three variants")
	t.eq(variant.search_all(arm_enum).size(), 3, "ArmorType has exactly three variants")


func test_veterancy_matches_the_sim(t) -> void:
	var body := _between(_src("sim.rs"), "const fn veterancy_factor", "\n}\n")
	t.ok(body != "", "found veterancy_factor")
	var arm := RegEx.create_from_string("(\\d+|_)\\s*=>\\s*(Fixed::from_ratio\\(\\d+,\\s*\\d+\\)|Fixed::ONE)")
	var by_rank := {}
	var top := 0
	for m in arm.search_all(body):
		if m.get_string(1) == "_":
			top = _pct(m.get_string(2))
		else:
			by_rank[int(m.get_string(1))] = _pct(m.get_string(2))
	t.eq(by_rank.size(), 3, "ranks 0, 1 and 2 are listed")
	for r in 3:
		t.eq(Rules.veterancy_pct(r), int(by_rank[r]), "rank %d" % r)
	t.eq(Rules.veterancy_pct(3), top, "rank 3 is the catch-all arm")
	t.eq(Rules.veterancy_pct(9), top, "ranks above 3 share it")
	t.eq(Rules.VETERANCY_PCT, [0, 10, 20, 35], "hand check: +0, +10, +20, +35 percent")


func test_unit_armour_and_weapon_types_match_the_sim(t) -> void:
	var src := _src("stats.rs")
	var units := _between(src, "pub const fn stats(self) -> UnitStats", "impl BuildingKind")
	t.ok(units != "", "found UnitKind::stats")
	var block := RegEx.create_from_string("(?s)Self::(\\w+) => UnitStats \\{(.*?)is_air")
	var armour := RegEx.create_from_string("armor: ArmorType::(\\w+)")
	var weapon := RegEx.create_from_string("AttackProfile::ground\\(\\s*(Fixed::\\w+(?:\\([^)]*\\))?),\\s*DamageType::(\\w+)")
	var seen := 0
	for m in block.search_all(units):
		var kind := m.get_string(1)
		var text := m.get_string(2)
		seen += 1
		t.eq(Rules.ARMOUR_OF.get(kind, ""), armour.search(text).get_string(1), "%s armour" % kind)
		var w := weapon.search(text)
		if w.get_string(1) == "Fixed::ZERO":
			t.ok(not Rules.DAMAGE_OF.has(kind), "%s has no weapon, so no damage type" % kind)
		else:
			t.eq(Rules.DAMAGE_OF.get(kind, ""), w.get_string(2), "%s weapon type" % kind)
	t.eq(seen, Rules.ARMOUR_OF.size(), "the client lists every unit kind the sim has")


func test_buildings_are_all_structure_armour(t) -> void:
	var src := _src("stats.rs")
	var buildings := _between(src, "impl BuildingKind", "\n}\n")
	var armour := RegEx.create_from_string("armor: ArmorType::(\\w+)")
	var all := armour.search_all(buildings)
	t.eq(all.size(), 1, "one armour assignment, in the shared base")
	t.eq(all[0].get_string(1) if not all.is_empty() else "", "Structure", "buildings are Structure")
	t.eq(Rules.armour_of("GunTurret", "building"), "Structure", "a turret is a structure")
	t.eq(Rules.armour_of("Wall", "building"), "Structure", "a wall is a structure")
	t.eq(Rules.armour_of("Tank", "unit"), "Plated", "a tank is plated")
	t.eq(Rules.armour_of("Mystery", "unit"), "", "an unknown unit kind has no armour: no invented pair")
	t.eq(Rules.armour_of("Wall", ""), "", "no category, no armour")


func test_hand_checked_matchups(t) -> void:
	t.eq(Rules.multiplier_pct("Ballistic", "Flesh"), 50, "rifles shred flesh")
	t.eq(Rules.multiplier_pct("Explosive", "Structure"), 50, "tank shells vs buildings")
	t.eq(Rules.multiplier_pct("Ballistic", "Plated"), -50, "rifles vs vehicles")
	t.eq(Rules.multiplier_pct("AntiArmor", "Flesh"), -50, "rockets vs infantry")
	t.eq(Rules.multiplier_pct("AntiArmor", "Plated"), 75, "rockets vs vehicles")
	t.eq(Rules.multiplier_pct("Explosive", "Flesh"), 0, "neutral")
	t.eq(Rules.damage_of("Harvester"), "", "unarmed")
