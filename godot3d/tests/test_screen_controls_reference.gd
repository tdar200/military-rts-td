extends RefCounted
const Screen := preload("res://scripts/ui/sections/controls_reference.gd")
const KB := preload("res://scripts/ui/keybinds.gd")
const KeyChip := preload("res://scripts/ui/components/key_chip.gd")
const U := preload("res://tests/section_util.gd")


func _build(vm: Dictionary) -> Array:
	var root := Control.new()
	var log: Array = []
	Screen.build(root, vm, func(name: String, _arg: Variant = null) -> void: log.append(name))
	return [root, log]


## Every drawn key chip's text, in tree order.
func _chips(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Control", true, false):
		if n is KeyChip:
			out.append((n as KeyChip).label)
	return out


func test_every_key_shown_is_in_the_binding_list(t) -> void:
	var root: Control = _build(KB.vm())[0]
	var allowed := {}
	for g in KB.groups():
		for row in g["rows"]:
			for k in row["keys"]:
				if k is int:
					allowed[KB.cap(k)] = true
				elif k is Array:
					allowed["%s-%s" % [KB.cap(int(k[0])), KB.cap(int(k[k.size() - 1]))]] = true
				elif k != KB.THEN and k != KB.PLUS:
					allowed[str(k)] = true
	var shown := _chips(root)
	t.ok(shown.size() > 30, "a real list was drawn (%d chips)" % shown.size())
	for c in shown:
		t.ok(allowed.has(c), "chip %s comes from keybinds.gd" % c)
	root.free()


func test_the_real_bindings_are_on_screen(t) -> void:
	var root: Control = _build(KB.vm())[0]
	var chips := _chips(root)
	for expected in ["\u2191", "\u2190", "\u2193", "\u2192", "A", "Z", "E", "Esc", "F1", "F2", ".", "Del", "Q", "U", "Y", "F", "Home", "T", "K", "V", "H", "X", "P", "R", "B", "G", "J", "C", "L", "N", "I", "O", ",", "1-9", "Wheel", "Middle drag"]:
		t.ok(chips.has(expected), "shows the " + expected + " key")
	for label in ["Pan", "Drag pan", "Rotate", "Vehicle factory", "Airfield", "Supply depot", "Battery", "Defences", "Attack-move", "Select all army", "Select idle crew", "Pause menu", "This screen", "Repair", "Sell", "Tactical ability", "Train riflemen", "Reactor", "Cancel order or placement"]:
		t.ok(U.has_text(root, label), "labels " + label)
	t.ok(U.has_text(root, "Cursor at screen edge"), "edge pan is a note, not a key")
	root.free()


func test_groups_are_the_boards_six(t) -> void:
	var root: Control = _build(KB.vm())[0]
	for name in ["Camera", "System", "Selection", "Build", "Orders", "Production"]:
		t.ok(U.has_text(root, name), "group " + name)
	root.free()


func test_keys_the_game_does_not_have_are_dropped(t) -> void:
	var root: Control = _build(KB.vm())[0]
	var chips := _chips(root)
	for gone in ["Tab", "F5", "F10", "Alt", "Space", "+", "9", "1-4", "x2", "W", "S", "D", "Up", "Left", "Down", "Right", "Comma"]:
		t.ok(not chips.has(gone), "no %s chip" % gone)
	for gone in ["Rebind keys", "Orbit", "Quick save", "Pause simulation", "Game speed", "Map overlays", "Hold position", "Focus fire", "Resupply", "Spread out", "Queue waypoint", "Rotate ghost", "Queue five", "Cancel last queued", "Recall and centre", "Clear selection", "Jump to alert", "Jump on minimap", "Hold "]:
		t.ok(not U.has_text(root, gone), "no row or text: " + gone)
	t.ok(U.button_with(root, "Rebind") == null, "no rebind button: the game has no remapping")
	for s in U.texts(root):
		t.ok(not str(s).contains("\u2014") and not str(s).contains("\u2013"), "no dash in: " + str(s))
	root.free()


func test_back_is_a_button_that_closes(t) -> void:
	var p := _build(KB.vm())
	var back := U.button_with(p[0], "Back") as Button
	t.ok(back != null, "Back is a Button with human text")
	t.eq(U.buttons(p[0]).size(), 1, "it is the only control")
	back.pressed.emit()
	t.eq(p[1], ["controls_back"], "Back reaches the host")
	t.eq(back.get("key_text"), "ESC", "Back shows its key")
	p[0].free()


func test_opened_from_play_it_is_not_called_a_pause_screen(t) -> void:
	var root: Control = _build(KB.vm(false))[0]
	t.ok(U.has_text(root, "Controls"), "the title")
	t.ok(not U.has_text(root, "Pause / Controls"), "no pause breadcrumb when F1 opened it in play")
	root.free()
	var from_menu: Control = _build(KB.vm(true))[0]
	t.ok(U.has_text(from_menu, "Pause / Controls"), "the breadcrumb when it came from the pause menu")
	from_menu.free()


func test_absent_data_builds_nothing(t) -> void:
	var root := Control.new()
	Screen.build(root, {}, Callable())
	Screen.build(root, {"columns": []}, Callable())
	t.eq(root.get_child_count(), 0, "no columns, no screen")
	root.free()


func test_rows_stay_inside_their_panels_and_the_screen(t) -> void:
	var root: Control = _build(KB.vm())[0]
	for n in root.find_children("*", "Control", true, false):
		if n is KeyChip:
			var c := n as KeyChip
			t.ok(c.position.x >= 0.0 and c.position.x + c.size.x <= 1920.0 and c.position.y + c.size.y <= 1080.0, "chip on screen: " + c.label)
	var lowest := 0.0
	for n in root.find_children("*", "Control", true, false):
		if n.get_class() != "ColorRect" and n.size.y > 40.0 and n.size.y < 800.0 and n.size.x > 500.0 and n.position.y < 950.0:
			lowest = maxf(lowest, n.position.y + n.size.y)
	t.ok(lowest < 990.0, "the tallest column ends above the footer (%d)" % int(lowest))
	root.free()
	# Kestrel's screen has two more camera rows (alert and minimap jumps): it must fit too.
	var kestrel: Control = _build(KB.vm(false, true))[0]
	var low_k := 0.0
	for n in kestrel.find_children("*", "Control", true, false):
		if n.get_class() != "ColorRect" and n.size.y > 40.0 and n.size.y < 800.0 and n.size.x > 500.0 and n.position.y < 950.0:
			low_k = maxf(low_k, n.position.y + n.size.y)
	t.ok(low_k > 0.0 and low_k < 990.0, "Kestrel: the tallest column ends above the footer (%d)" % int(low_k))
	kestrel.free()
