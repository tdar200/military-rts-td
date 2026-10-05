extends RefCounted
## Terrain guide (board 12): a card per ground_table row plus Ore and Alloy, and the rules-of-thumb footer. Driven by
## vm_maps.terrain_guide(): every number on a card is a ground_table value or a constant mirrored from the sim; the notes are
## words only. `emit` is Callable(name, arg) and receives guide_back. Builds nothing without cards.
## Not built: the other Codex tabs (Resources, Structures, Units: no such pages), the board's "-25% across the river" and the
## Fog rule (the sim has neither), and the map-image swatches (a flat hex crop of the ground colour stands in).
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const Hex = preload("res://scripts/ui/components/hex_map.gd")

const MARGIN := 60.0
const GRID_TOP := 128.0
const COLUMNS := 4
const GAP := 16.0
const SWATCH := Vector2(132.0, 96.0)
const ROW_RULE := Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.7)
const SCREEN := Vector2(1920.0, 1080.0)
## Hex size (px, point to point) of the swatch crop.
const SWATCH_HEX := 22.0


## The 132 x 96 swatch: a crop of hex tiles in the ground's own colour (shaded a little per tile so it reads as terrain), or
## a dark crop with accent hexes for a deposit.
class Swatch extends Control:
	var base: Color = T.GROUND
	var accent := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), base if not accent else T.BG2)
		var step_x := SWATCH_HEX * 0.75
		for col in range(-1, int(size.x / step_x) + 2):
			for row in range(-1, int(size.y / SWATCH_HEX) + 2):
				var c := Vector2(col * step_x + SWATCH_HEX * 0.5, row * SWATCH_HEX + SWATCH_HEX * 0.5 + (SWATCH_HEX * 0.5 if col % 2 != 0 else 0.0))
				var shade := 1.0 + 0.05 * float(((col * 7 + row * 13) % 5) - 2) / 2.0
				var fill: Color = base if not accent else T.BG2
				if accent and (col * 3 + row * 5) % 7 == 0:
					fill = base
				fill = Color(clampf(fill.r * shade, 0, 1), clampf(fill.g * shade, 0, 1), clampf(fill.b * shade, 0, 1), 1.0)
				var pts := PackedVector2Array()
				for k in Hex.CORNERS:
					pts.append(c + k * (SWATCH_HEX - 1.0))
				draw_colored_polygon(pts, fill)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = T.LINE
		box.set_corner_radius_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))


## The board's .yl chip without its dot: 22px high, mono 12px, coloured text on a dark fill.
class Chip extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), T.BAR_BG)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(1)
		box.border_color = T.LINE_DIM
		box.set_corner_radius_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var cards: Array = vm.get("cards", [])
	if cards.is_empty():
		return
	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.color = Color("07101a")
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(ground)
	_header(parent, vm, emit)
	var card_w := (SCREEN.x - 2.0 * MARGIN - float(COLUMNS - 1) * GAP) / float(COLUMNS)
	var heights: Array = []
	var per_row := (cards.size() + COLUMNS - 1) / COLUMNS
	var y := GRID_TOP
	for r in per_row:
		var row_h := 0.0
		for i in range(r * COLUMNS, mini(cards.size(), (r + 1) * COLUMNS)):
			row_h = maxf(row_h, _card(parent, MARGIN + float(i % COLUMNS) * (card_w + GAP), y, card_w, cards[i]))
		y += row_h + GAP
	_footer(parent, vm)


static func _header(parent: Control, vm: Dictionary, emit: Callable) -> void:
	var cap := K.text(parent, str(vm.get("cap", "Codex")), {"x": MARGIN, "y": 30.0, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	var title := K.text(parent, str(vm.get("title", "Terrain guide")), {"x": MARGIN, "y": 30.0 + cap.size.y + 2.0, "f": "disp", "wt": 600, "px": 48, "sp": 0.04, "lh": 50, "col": T.TEXT_HI, "up": true})
	var sub := K.text(parent, str(vm.get("sub", "")), {"x": MARGIN, "y": title.position.y + title.size.y + 2.0, "px": 15, "col": T.DIM})
	var back := K.button(parent, "Back", 0, 0, {"primary": true, "key": "Esc"})
	K.place(back, SCREEN.x - MARGIN - back.size.x, sub.position.y + sub.size.y - back.size.y)
	if emit.is_valid():
		back.pressed.connect(emit.bind("guide_back", null))


## One card at (x, y); returns its height.
static func _card(parent: Control, x: float, y: float, w: float, card: Dictionary) -> float:
	var panel := K.panel(parent, x, y, w, 10.0)
	var cx := x + 1.0 + 10.0
	var cw := w - 2.0 - 20.0
	var top := y + 1.0 + 10.0
	var swatch := Swatch.new()
	K.place(swatch, cx, top, SWATCH.x, SWATCH.y)
	var glyph := str(card.get("glyph", ""))
	match str(card.get("kind", "ground")):
		"ore":
			swatch.base = T.CYAN
			swatch.accent = true
		"alloy":
			swatch.base = T.VIOLET
			swatch.accent = true
		_:
			swatch.base = Hex.ground_color(glyph)
	parent.add_child(swatch)
	var tx := cx + SWATCH.x + 12.0
	var tw := cw - SWATCH.x - 12.0
	var name := K.text(parent, str(card.get("name", "")), {"x": tx, "y": top, "w": tw, "f": "disp", "wt": 600, "px": 22, "sp": 0.04, "lh": 24, "col": T.TEXT_HI, "up": true})
	var ty := top + name.size.y
	if str(card.get("sub", "")) != "":
		var sub := K.text(parent, str(card["sub"]), {"x": tx, "y": ty, "w": tw, "px": 13, "lh": 17.55, "col": T.DIM, "wrap": true})
		ty += sub.size.y
	ty += 6.0
	var chip_x := tx
	var chip_list: Array = [{"text": str(card.get("tag", "")), "tone": str(card.get("tone", "dim"))}]
	chip_list.append_array(card.get("chips", []))
	var chip_y := ty
	for c in chip_list:
		if str(c.get("text", "")) == "":
			continue
		var label := K.text(parent, str(c["text"]), {"f": "mono", "px": 12, "col": T.tone(str(c.get("tone", "dim")))})
		var chip := Chip.new()
		var chip_w := label.size.x + 16.0
		if chip_x + chip_w > tx + tw and chip_x > tx:
			chip_x = tx
			chip_y += 22.0 + 4.0
		K.place(chip, chip_x, chip_y, chip_w, 22)
		chip.name = "Chip"
		parent.add_child(chip)
		parent.move_child(chip, label.get_index())
		label.position = Vector2(chip_x + 8.0, roundf(chip_y + (22.0 - label.size.y) * 0.5))
		chip_x += chip_w + 4.0
	var ry := top + SWATCH.y + 6.0
	var rows: Array = card.get("rows", [])
	for i in rows.size():
		var row: Dictionary = rows[i]
		var left := K.text(parent, str(row.get("label", "")), {"x": cx, "px": 13, "col": T.DIM})
		var right := K.text(parent, str(row.get("value", "")), {"f": "mono", "px": 13, "col": T.tone(str(row.get("tone", ""))) if str(row.get("tone", "")) != "" else T.TEXT})
		var h := maxf(left.size.y, right.size.y)
		left.position.y = roundf(ry + 3.0 + (h - left.size.y) * 0.5)
		right.position = Vector2(roundf(cx + cw - right.size.x), roundf(ry + 3.0 + (h - right.size.y) * 0.5))
		if i < rows.size() - 1:
			K.rule(parent, cx, ry + 3.0 + h + 3.0, cw, 1, ROW_RULE)
		ry += 3.0 + h + 3.0 + 1.0 + 6.0
	var note_h := 0.0
	if str(card.get("note", "")) != "":
		var note := K.text(parent, str(card["note"]), {"x": cx, "y": ry, "w": cw, "px": 12, "lh": 16.2, "col": T.DIM, "wrap": true})
		note_h = note.size.y
	panel.size.y = roundf(ry + note_h + 10.0 + 1.0 - y)
	panel.queue_redraw()
	return panel.size.y


static func _footer(parent: Control, vm: Dictionary) -> void:
	var rules: Array = vm.get("rules", [])
	if rules.is_empty():
		return
	var h := 46.0
	var y := SCREEN.y - 28.0 - h
	K.panel(parent, MARGIN, y, SCREEN.x - 2.0 * MARGIN, h, "glass")
	var x := MARGIN + 1.0 + 18.0
	var cap := K.text(parent, "Rules of thumb", {"x": x, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	cap.position.y = roundf(y + (h - cap.size.y) * 0.5)
	x += cap.size.x + 34.0
	for r in rules:
		var head := K.text(parent, str(r.get("head", "")), {"x": x, "wt": 600, "px": 14, "col": T.TEXT_HI})
		var tail := K.text(parent, str(r.get("tail", "")), {"px": 14, "col": T.DIM})
		head.position.y = roundf(y + (h - head.size.y) * 0.5)
		tail.position = Vector2(roundf(x + head.size.x + 4.0), roundf(y + (h - tail.size.y) * 0.5))
		x += head.size.x + 4.0 + tail.size.x + 34.0
