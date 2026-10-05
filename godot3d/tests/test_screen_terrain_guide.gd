extends RefCounted
## Board 12 (Terrain guide): cards from the real ground_table plus Ore and Alloy, numbers equal to the table, no invented rules.
const Guide := preload("res://scripts/ui/sections/terrain_guide.gd")
const Maps := preload("res://scripts/ui/vm_maps.gd")
const Ground := preload("res://scripts/terrain/ground_model.gd")
const U := preload("res://tests/section_util.gd")


func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ).get_as_text())


func _vm(snap := {}) -> Dictionary:
	var s: Dictionary = snap if not snap.is_empty() else _snapshot()
	return Maps.terrain_guide(s, Ground.from_snapshot(s))


func _card(vm: Dictionary, name: String) -> Dictionary:
	for c in vm["cards"]:
		if c["name"] == name:
			return c
	return {}


func _row(card: Dictionary, label: String) -> String:
	for r in card["rows"]:
		if r["label"] == label:
			return str(r["value"])
	return ""


func _all_text(root: Node) -> String:
	return " ".join(U.texts(root)).to_lower()


func _screen(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Guide.build(root, vm, func(name: String, _arg: Variant = null) -> void: log.append(name))
	return [root, log]


func test_one_card_per_table_row_then_ore_and_alloy(t) -> void:
	var snap := _snapshot()
	var vm := _vm(snap)
	var names: Array = []
	for c in vm["cards"]:
		names.append(c["name"])
	var want: Array = []
	for row in snap["ground_table"]:
		want.append(row["name"])
	want.append("Ore deposit")
	want.append("Alloy crystals")
	t.eq(names, want, "the table rows in order, then the two deposit cards")


func test_ground_numbers_are_the_table_numbers(t) -> void:
	var snap := _snapshot()
	var vm := _vm(snap)
	for row in snap["ground_table"]:
		var card := _card(vm, row["name"])
		var cover := int(row["cover_pct"])
		t.eq(_row(card, "Cover"), "+%d%%" % cover if cover > 0 else "None", "%s cover" % row["name"])
		t.eq(_row(card, "Build"), "Allowed" if row["buildable"] else "Not allowed", "%s build" % row["name"])
		if row["passable"]:
			t.ok(_row(card, "Movement").contains(str(int(row["infantry_pct"]))), "%s movement carries the infantry percentage" % row["name"])
		else:
			t.eq(_row(card, "Movement"), "Blocked", "%s is blocked" % row["name"])
	var highland := _card(vm, "Highland")
	var chips: Array = highland["chips"].map(func(c): return c["text"])
	t.ok(chips.has("+25% range"), "the highland range bonus is the table's range_pct")


func test_deposit_cards_carry_the_real_counts(t) -> void:
	var snap := _snapshot()
	var vm := _vm(snap)
	var ore := _card(vm, "Ore deposit")
	var alloy := _card(vm, "Alloy crystals")
	t.eq(ore["sub"], "6 deposits", "six ore deposits in the snapshot")
	t.eq(alloy["sub"], "3 deposits", "three alloy deposits in the snapshot")
	var left := 0
	for d in snap["deposits"]:
		if d["kind"] == "Ore":
			left += int(d["remaining"])
	t.eq(_row(ore, "Left in the ground").replace(",", ""), str(left), "the ore total is the sum of the deposits")
	t.eq(_row(ore, "Refinery near"), "+%d%%" % Maps.VM.ORE_BONUS_PCT, "the refinery bonus is the mirrored sim constant")
	t.eq(_row(alloy, "Mining"), "None", "alloy is scenery in this sim")


func test_alloy_card_only_in_earthfront_and_only_with_deposits(t) -> void:
	var snap := _snapshot()
	snap["earthfront"] = false
	t.ok(_card(_vm(snap), "Alloy crystals").is_empty(), "no alloy card outside Earthfront")
	snap = _snapshot()
	snap["deposits"] = snap["deposits"].filter(func(d): return d["kind"] != "Alloy")
	t.ok(_card(_vm(snap), "Alloy crystals").is_empty(), "no alloy deposits, no card")
	t.ok(not _card(_vm(snap), "Ore deposit").is_empty(), "the ore card stays")


func test_no_table_builds_nothing(t) -> void:
	var snap := _snapshot()
	snap.erase("ground_table")
	t.ok(Maps.terrain_guide(snap, Ground.from_snapshot(snap)).is_empty(), "no ground_table gives an empty view model")
	var p := _screen({})
	t.eq(p[0].get_child_count(), 0, "an empty view model draws nothing")
	snap = _snapshot()
	snap["ground_table"] = []
	t.ok(Maps.terrain_guide(snap, null).is_empty(), "an empty table gives an empty view model")
	p[0].free()


func test_no_invented_rules(t) -> void:
	var vm := _vm()
	var p := _screen(vm)
	var text := _all_text(p[0]) + " " + JSON.stringify(vm).to_lower()
	for banned in ["-25%", "25% across", "fog", "sight", "river penalty", "survey", "unexplored"]:
		t.ok(not text.contains(banned), "the guide never says '%s'" % banned)
	p[0].free()


func test_the_footer_rules_come_from_the_table(t) -> void:
	var snap := _snapshot()
	var heads: Array = _vm(snap)["rules"].map(func(r): return r["head"] + " " + r["tail"])
	t.ok(heads.has("High ground adds 25% range"), "the highland rule uses the table's 25")
	for row in snap["ground_table"]:
		if row["name"] == "Highland":
			row["range_pct"] = 40
	heads = _vm(snap)["rules"].map(func(r): return r["head"] + " " + r["tail"])
	t.ok(heads.has("High ground adds 40% range"), "change the table and the rule follows")
	for row in snap["ground_table"]:
		if row["name"] == "Highland":
			row["range_pct"] = 0
	heads = _vm(snap)["rules"].map(func(r): return r["head"] + " " + r["tail"])
	t.ok(not heads.any(func(h): return h.begins_with("High ground")), "no range bonus in the table, no high-ground rule")


func test_screen_shows_the_cards_and_a_back_button(t) -> void:
	var vm := _vm()
	var p := _screen(vm)
	var root: Control = p[0]
	var text := _all_text(root)
	for want in ["terrain guide", "grassland", "highland", "ore deposit", "alloy crystals", "rules of thumb", "100%", "none", "not allowed"]:
		t.ok(text.contains(want), "the screen shows '%s'" % want)
	var back := U.button_with(root, "Back")
	t.ok(back != null, "a Back Button with human text")
	back.pressed.emit()
	t.eq(p[1], ["guide_back"], "Back emits guide_back")
	root.free()


func test_swatches_stay_inside_their_card(t) -> void:
	var p := _screen(_vm())
	var seen := 0
	for n in p[0].find_children("*", "Control", true, false):
		if n is Control and n.get("accent") != null and n.get("base") != null:
			seen += 1
			t.ok(n.clip_contents, "a swatch clips its hex crop to its own rectangle")
	t.ok(seen >= 12, "a swatch per card")
	p[0].free()
