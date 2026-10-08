extends RefCounted
## Kestrel feedback (plan 2026-10-07-kestrel-depth, Task 7): FeedbackEvents reads two consecutive snapshots and a memo the
## game keeps, and names the events the player should hear and read: power lost and restored, the 45 s wave warning, a
## wave cleared, units under attack and finished production (one toast per batch). Pure, so every case is a crafted pair.
const FE := preload("res://scripts/ui/feedback_events.gd")
const Adapter := preload("res://scripts/ui/live_adapter.gd")


func _snap(gen, dem, waves, next_ticks, ents := [], tick := 0) -> Dictionary:
	return {"tick": tick, "power_generation": gen, "power_demand": dem, "waves_survived": waves, "next_wave_ticks": next_ticks,
		"entities": ents}


func _ids(events: Array) -> Array:
	return events.map(func(e): return e.id)


## An entity the way the bridge sends it (16.16 fixed point), on hex cell (col, row).
func _ent(id: int, owner: int, kind: String, hp := 100, col := 10, row := 10, category := "unit") -> Dictionary:
	var sx := float(col) * 0.75 + 0.5
	var sz := float(row) + 0.5 + (0.5 if col % 2 != 0 else 0.0)
	return {"id": id, "owner": owner, "kind": kind, "category": category, "hp_bits": hp * 65536,
		"x_bits": int(sx * 65536.0), "z_bits": int(sz * 65536.0)}


# ------------------------------------------------------------------ the brief's cases

func test_power_down_then_up_fire_once_each(t) -> void:
	var st := {}
	var a := FE.derive(_snap(100, 80, 0, 4000), _snap(100, 120, 0, 3990), st)
	t.eq(a.map(func(e): return e.id), ["power_down"])
	t.eq(FE.derive(_snap(100, 120, 0, 3990), _snap(100, 130, 0, 3980), st).size(), 0)
	var b := FE.derive(_snap(100, 130, 0, 3980), _snap(150, 130, 0, 3970), st)
	t.eq(b.map(func(e): return e.id), ["power_up"])
	t.eq(a[0]["sound"], "power_down", "power lost sounds power_down")
	t.eq(b[0]["sound"], "power_up", "and back on, power_up")
	t.eq(String(a[0]["toast"]), "LOW POWER", "a toast says so")
	t.ok(String(a[0]["body"]).contains("120") and String(a[0]["body"]).contains("100"), "with the demand and the output")
	t.eq(a[0]["at"], null, "a placeless cue")
	t.eq(FE.derive(_snap(150, 130, 0, 3970), _snap(150, 150, 0, 3960), st).size(), 0, "demand equal to output is still powered")


func test_funds_short(t) -> void:
	t.eq(FE.funds_short(150, 100), 50)
	t.eq(FE.funds_short(100, 100), 0)
	t.eq(FE.funds_short(-1, 0), 0, "an unknown cost (-1) is never short")


func test_batch_of_three_riflemen_is_one_toast(t) -> void:
	var st := {}
	var before := _snap(100, 50, 0, 4000, [])
	var ents := []
	for i in 3:
		ents.append({"id": 40 + i, "owner": 0, "kind": "Infantry", "hp": 100})
	var ev := FE.derive(before, _snap(100, 50, 0, 3990, ents), st)
	t.eq(ev.filter(func(e): return e.id == "production_complete").size(), 1)
	var e: Dictionary = ev.filter(func(x): return x.id == "production_complete")[0]
	t.eq(e["toast"], "3 Riflemen ready", "the batch's count and the HUD's name for the kind")
	t.eq(e["sound"], "ack_infantry", "one acknowledgement by class")


# ------------------------------------------------------------------ production

func test_production_counts_by_kind_and_skips_aliens_and_known_units(t) -> void:
	var st := {}
	var old := [_ent(1, 0, "Infantry"), _ent(2, 1, "Infantry")]
	var now := old + [_ent(3, 0, "Tank"), _ent(4, 0, "Tank"), _ent(5, 0, "Helicopter"), _ent(6, 1, "Tank"),
		_ent(7, 0, "Barracks", 100, 4, 4, "building")]
	var ev := FE.derive(_snap(100, 50, 0, 4000, old, 10), _snap(100, 50, 0, 3990, now, 11), st)
	var prod := ev.filter(func(e): return e.id == "production_complete")
	t.eq(prod.map(func(e): return e.toast), ["2 Battle tanks ready", "Gunship ready"], "one per kind; a single unit has no count")
	t.eq(prod.map(func(e): return e.sound), ["ack_vehicle", "ack_air"], "each by its class")
	t.eq(FE.derive(_snap(100, 50, 0, 3990, now, 11), _snap(100, 50, 0, 3980, now, 12), st).size(), 0, "the same units next poll: nothing")
	var recycled := now.duplicate()
	recycled[0] = _ent(1, 0, "AntiArmor")  # the dead rifle squad's id reused by a new rocket team
	var r := FE.derive(_snap(100, 50, 0, 3980, now, 12), _snap(100, 50, 0, 3970, recycled, 13), st)
	t.eq(_ids(r), ["production_complete"], "a reused id with another kind is a new unit")
	t.eq(r[0]["toast"], "Rocket team ready")


func test_names_and_plurals(t) -> void:
	t.eq(FE.batch_text("Infantry", 1), "Riflemen ready")
	t.eq(FE.batch_text("Infantry", 4), "4 Riflemen ready", "riflemen is already plural")
	t.eq(FE.batch_text("AntiArmor", 2), "2 Rocket teams ready")
	t.eq(FE.batch_text("Harvester", 2), "2 Harvesters ready")
	t.eq(FE.batch_text("Capital", 1), "Capital unit ready")


# ------------------------------------------------------------------ wave warning

func test_wave_warning_once_when_the_wave_crosses_45_s(t) -> void:
	var st := {}
	t.eq(FE.derive(_snap(90, 30, 0, 1400), _snap(90, 30, 0, 1360), st).size(), 0, "46 s out: nothing")
	var ev := FE.derive(_snap(90, 30, 0, 1360), _snap(90, 30, 0, 1350), st)
	t.eq(_ids(ev), ["wave_warning"], "45 s out: the warning")
	t.eq(ev[0]["sound"], "alert", "the alert sound")
	t.eq(float(ev[0]["volume_db"]), -6.0, "6 dB under the ten-second alert")
	t.eq(ev[0]["toast"], "", "no second toast: the HUD's Enemy signal detected toast already says it")
	t.eq(FE.derive(_snap(90, 30, 0, 1350), _snap(90, 30, 0, 1340), st).size(), 0, "inside the window: nothing more")
	t.eq(FE.derive(_snap(90, 30, 0, 1340), _snap(90, 30, 0, 4000), st).size(), 0, "the timer resetting is no warning")
	t.eq(_ids(FE.derive(_snap(90, 30, 1, 1500), _snap(90, 30, 1, 1300), st)), ["wave_warning"], "the next wave warns again")
	t.eq(FE.derive(_snap(90, 30, 0, -1), _snap(90, 30, 0, 1000), st).size(), 0, "no timer before: no crossing")
	t.eq(FE.derive(_snap(90, 30, 0, 4000), _snap(90, 30, 0, 250), st).size(), 0, "a jump into the last ten seconds: the full alert speaks instead")


# ------------------------------------------------------------------ units under attack

func test_unit_attacked_at_most_once_per_ten_seconds(t) -> void:
	var st := {}
	var full := [_ent(1, 0, "Infantry", 100), _ent(2, 1, "Infantry", 100)]
	var hit := [_ent(1, 0, "Infantry", 80), _ent(2, 1, "Infantry", 100)]
	var ev := FE.derive(_snap(90, 30, 0, 4000, full, 100), _snap(90, 30, 0, 3990, hit, 101), st)
	t.eq(_ids(ev), ["unit_attacked"], "a human squad lost HP")
	t.eq(ev[0]["sound"], "alert")
	t.eq(ev[0]["key"], "unit_attacked", "its own cooldown key in the director")
	t.eq(String(ev[0]["toast"]), "UNITS UNDER ATTACK")
	t.ok(String(ev[0]["body"]).contains("RIFLEMEN"), "names the unit")
	var hit2 := [_ent(1, 0, "Infantry", 60), _ent(2, 1, "Infantry", 100)]
	t.eq(FE.derive(_snap(90, 30, 0, 3990, hit, 101 + 299), _snap(90, 30, 0, 3980, hit2, 101 + 299), st).size(), 0, "9.97 s later: silent")
	var hit3 := [_ent(1, 0, "Infantry", 40), _ent(2, 1, "Infantry", 100)]
	t.eq(_ids(FE.derive(_snap(90, 30, 0, 3980, hit2, 400), _snap(90, 30, 0, 3970, hit3, 401), st)), ["unit_attacked"], "10 s later: again")
	var alien_hit := [_ent(1, 0, "Infantry", 40), _ent(2, 1, "Infantry", 10)]
	t.eq(FE.derive(_snap(90, 30, 0, 3970, hit3, 900), _snap(90, 30, 0, 3960, alien_hit, 901), st).size(), 0, "an alien losing HP is not ours")
	var building := [_ent(9, 0, "Barracks", 100, 4, 4, "building")]
	var building_hit := [_ent(9, 0, "Barracks", 50, 4, 4, "building")]
	t.eq(FE.derive(_snap(90, 30, 0, 3970, building, 2000), _snap(90, 30, 0, 3960, building_hit, 2001), st).size(), 0, "a structure has its own alert")
	t.eq(FE.derive(_snap(90, 30, 0, 3970, hit3, 3000), _snap(90, 30, 0, 3960, hit3, 3001), st).size(), 0, "no HP lost: nothing")


func test_the_hp_field_falls_back_to_plain_hp(t) -> void:
	var st := {}
	var a := [{"id": 1, "owner": 0, "kind": "Tank", "category": "unit", "hp": 100}]
	var b := [{"id": 1, "owner": 0, "kind": "Tank", "category": "unit", "hp": 90}]
	t.eq(_ids(FE.derive(_snap(90, 30, 0, 4000, a), _snap(90, 30, 0, 3990, b, 1), st)), ["unit_attacked"])


# ------------------------------------------------------------------ wave cleared

func test_wave_cleared_after_the_spawned_aliens_are_gone(t) -> void:
	var st := {}
	var base := [_ent(1, 0, "Infantry"), _ent(50, 1, "Infantry", 100, 40, 5)]  # an alien garrison squad, seen before the wave
	var wave := base + [_ent(90, 1, "Infantry", 100, 38, 12), _ent(91, 1, "Tank", 100, 38, 13)]
	var ev := FE.derive(_snap(90, 30, 0, 10, base, 100), _snap(90, 30, 1, 4000, wave, 101), st)
	t.eq(ev.filter(func(e): return e.id == "wave_cleared").size(), 0, "the spawn is no clearing")
	var one_left := base + [_ent(91, 1, "Tank", 100, 30, 13)]
	t.eq(FE.derive(_snap(90, 30, 1, 4000, wave, 101), _snap(90, 30, 1, 3990, one_left, 102), st).size(), 0, "one attacker still stands")
	var cleared := FE.derive(_snap(90, 30, 1, 3990, one_left, 102), _snap(90, 30, 1, 3980, base, 103), st)
	t.eq(_ids(cleared), ["wave_cleared"], "the last one gone: cleared, though the garrison squad still stands")
	t.eq(cleared[0]["sound"], "wave_cleared")
	t.eq(String(cleared[0]["toast"]), "WAVE 01 CLEARED")
	t.eq(FE.derive(_snap(90, 30, 1, 3980, base, 103), _snap(90, 30, 1, 3970, base, 104), st).size(), 0, "once")
	var after := base + [_ent(95, 1, "Infantry", 100, 39, 12)]  # the alien base trains a squad after the wave: not the wave
	t.eq(FE.derive(_snap(90, 30, 1, 3970, base, 104), _snap(90, 30, 1, 3960, after, 105), st).size(), 0, "a later alien is no new wave")
	t.eq(FE.derive(_snap(90, 30, 1, 3960, after, 105), _snap(90, 30, 1, 3950, base, 106), st).size(), 0, "and its death clears nothing")


func test_no_wave_no_clearing(t) -> void:
	var st := {}
	var a := [_ent(1, 0, "Infantry"), _ent(50, 1, "Infantry", 100, 30, 5)]
	var b := [_ent(1, 0, "Infantry")]
	t.eq(FE.derive(_snap(90, 30, 0, 4000, a, 1), _snap(90, 30, 0, 3990, b, 2), st).size(), 0, "a probe dying before wave one clears nothing")


## Fog: the bridge sends only what the player sees, so the wave is invisible at its spawn tick. Its attackers count from
## the moment they come out of the dark; a vanished attacker counts as beaten only when its last cell and every cell
## around it are in sight (next to the dark it may simply have walked out of view); and under fog the wave is cleared
## only once as many have been beaten as the HUD announced (`next_expedition_size`, read just before the spawn). Nothing
## is ever said about a cell the player cannot see.
func test_fogged_wave_counts_only_seen_deaths_up_to_the_announced_size(t) -> void:
	var w := 44
	var h := 26
	var mask := ""
	for row in h:
		for col in w:
			mask += "2" if col <= 24 else "0"  # columns 0..24 in sight, the rest dark
	var fs := func(waves: int, ents: Array, tick: int, size := 3) -> Dictionary:
		var s := _snap(90, 30, waves, 4000, ents, tick)
		s["fog"] = mask
		s["map_width"] = w
		s["map_height"] = h
		s["next_expedition_size"] = size
		return s
	var st := {}
	var me := [_ent(1, 0, "Tank", 100, 10, 10)]
	t.eq(FE.derive(fs.call(0, me, 100, 3), fs.call(1, me, 101, 5), st).size(), 0, "the spawn: nothing seen")
	var two := me + [_ent(90, 1, "Infantry", 100, 20, 10), _ent(91, 1, "Infantry", 100, 20, 11)]
	t.eq(FE.derive(fs.call(1, me, 101), fs.call(1, two, 102), st).size(), 0, "two attackers come out of the fog")
	var one := me + [_ent(91, 1, "Infantry", 100, 20, 11)]
	t.eq(FE.derive(fs.call(1, two, 102), fs.call(1, one, 103), st).size(), 0, "one dies in plain sight")
	t.eq(FE.derive(fs.call(1, one, 103), fs.call(1, me, 104), st).size(), 0, "the other too: two of the three announced, not cleared yet")
	var edge := me + [_ent(92, 1, "Tank", 100, 24, 12)]
	t.eq(FE.derive(fs.call(1, me, 104), fs.call(1, edge, 105), st).size(), 0, "the third shows at the edge of sight")
	t.eq(FE.derive(fs.call(1, edge, 105), fs.call(1, me, 106), st).size(), 0, "and vanishes beside the dark: lost, not beaten")
	var back := me + [_ent(92, 1, "Tank", 100, 22, 12)]
	t.eq(FE.derive(fs.call(1, me, 106), fs.call(1, back, 107), st).size(), 0, "it comes back into sight")
	t.eq(_ids(FE.derive(fs.call(1, back, 107), fs.call(1, me, 108), st)), ["wave_cleared"], "and dies in sight: three beaten, cleared")
	t.eq(FE.derive(fs.call(1, me, 108), fs.call(1, me, 109), st).size(), 0, "once")
	# a wave the player only glimpsed: the one attacker seen walks back into the dark, so nothing is ever claimed
	var st2 := {}
	FE.derive(fs.call(1, me, 200, 1), fs.call(2, me, 201, 1), st2)
	var w2 := me + [_ent(80, 1, "Infantry", 100, 24, 10)]
	FE.derive(fs.call(2, me, 201, 1), fs.call(2, w2, 202, 1), st2)
	t.eq(FE.derive(fs.call(2, w2, 202, 1), fs.call(2, me, 203, 1), st2).size(), 0, "gone where it may have walked out of view: silent")
	t.eq(FE.derive(fs.call(2, me, 203, 1), fs.call(2, me, 204, 1), st2).size(), 0, "and stays silent")


func test_restart_rearms_through_a_fresh_memo(t) -> void:
	var st := {}
	t.eq(_ids(FE.derive(_snap(100, 80, 0, 4000), _snap(100, 120, 0, 3990), st)), ["power_down"])
	st.clear()  # the game clears its memo when the tick goes back
	t.eq(_ids(FE.derive(_snap(100, 80, 0, 4000), _snap(100, 120, 0, 3990), st)), ["power_down"], "after a restart it fires again")


func test_costs_come_from_the_deck_and_prefer_the_depth_refinery_price(t) -> void:
	for card in Adapter.BUILD_CARDS:
		t.eq(FE.build_cost(String(card[1]), {}), int(card[4]), "%s costs what its card says" % card[1])
	for spec in Adapter.UNIT_CARDS:
		t.eq(FE.unit_cost(String(spec[3])), int(spec[4]), "%s costs what its card says" % spec[3])
	t.eq(FE.build_cost("Refinery", {"depth": {"refinery_cost": 230}}), 230, "Task 18's rising refinery price wins")
	t.eq(FE.build_cost("PowerPlant", {"depth": {"refinery_cost": 230}}), 100, "only for the refinery")
	t.eq(FE.build_cost("Refinery", {"depth": {}}), 150, "no price in the depth block: the card")
	t.eq(FE.unit_cost("Scout"), -1, "a kind with no card is unknown (never denied)")
	t.eq(FE.unit_cost("Capital"), 500, "Task 26: the Capital (no card, X trains it) is priced from balance.ron")
	t.eq(FE.build_cost("CommandCenter", {}), -1)


func test_the_module_is_pure(t) -> void:
	var src := (load("res://scripts/ui/feedback_events.gd") as GDScript).source_code
	t.ok(src.begins_with("extends RefCounted"), "a RefCounted")
	for banned in ["FileAccess", "get_tree", "Time.", "randf", "randi", "OS.", "AudioServer", "_sfx(", "notify("]:
		t.ok(not src.contains(banned), "no %s in FeedbackEvents" % banned)
