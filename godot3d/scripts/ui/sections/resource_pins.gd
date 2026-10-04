extends RefCounted
## Resource pins floating over the deposits on screen: "Ore 24,000 left" (claimed by a refinery), "Ore, unclaimed" and
## "Alloy 15,000 left". Driven by vm["pins"]: [{x, y, kind, remaining, claimed, cell}] where x, y is the deposit's screen
## point. Each pin is a Button that emits "focus_deposit" with its hex cell (the game centres the camera there). The
## board's "+4" haul figure and the worker "Harvesting" tags have no data behind them and are not built.
## Two variants from boards 2 and 3: `in_range` (a deposit within a refinery's ore reach of the hex being placed on) reads
## "Ore" + dim "in range"; `hostile` (the alien entity a combat preview is about) has a red edge and is a plain label,
## never a Button, because clicking it would have to mean something the game does not define.
const T = preload("res://scripts/ui/tokens.gd")
const LiveScreens = preload("res://scripts/ui/live_screens.gd")
const K = preload("res://scripts/ui/kit.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")

const H := 26.0
## Pins float this far above the deposit, so the tip points at it without covering it.
const LIFT := 16.0
const FILL := Color(6.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.88)


## The pin's visible text: [main, dim] (dim may be "").
static func parts(pin: Dictionary) -> Array:
	var kind := str(pin.get("kind", "Ore"))
	if bool(pin.get("hostile", false)):
		return [kind, ""]
	if bool(pin.get("in_range", false)):
		return [kind, "in range"]
	if kind == "Ore" and not bool(pin.get("claimed", false)):
		return ["Ore, unclaimed", ""]
	return [kind, "%s left" % LiveScreens.thousands(int(pin.get("remaining", 0)))]


class Body extends Control:
	var edge: Color = T.CYAN

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = FILL
		box.border_color = edge
		box.set_border_width_all(1)
		box.set_corner_radius_all(int(H / 2.0))
		# The tail: an 8px square turned 45 degrees, centred 2px below the pin; only its lower two borders are stroked.
		var c := Vector2(size.x * 0.5, size.y + 2.0)
		var r := 4.0 * 1.4142
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		draw_colored_polygon(pts, FILL)
		draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3]]), edge, 1.0, true)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var pins = vm.get("pins", null)
	if not (pins is Array) or pins.is_empty():
		return
	for pin in pins:
		if not (pin is Dictionary):
			continue
		var kind := str(pin.get("kind", "Ore"))
		var hostile := bool(pin.get("hostile", false))
		var in_range := bool(pin.get("in_range", false))
		var unclaimed: bool = kind == "Ore" and not bool(pin.get("claimed", false)) and not hostile and not in_range
		var edge: Color = T.BAD if hostile else (T.FAINT if unclaimed else (T.VIOLET if kind == "Alloy" else T.CYAN))
		var text_col: Color = T.DIM if unclaimed else T.TEXT_HI
		var p := parts(pin)
		var body := Body.new()
		body.edge = edge
		parent.add_child(body)
		var x := 1.0 + 5.0
		var main := TextBox.new()
		body.add_child(main)
		main.configure(str(p[0]), {"f": "mono", "px": 12, "col": text_col})
		main.size = main.get_minimum_size()
		var main_x := x + 16.0 + 6.0
		main.position = Vector2(main_x, (H - main.pitch()) * 0.5)
		var w := main_x + main.size.x
		if str(p[1]) != "":
			var rest := TextBox.new()
			body.add_child(rest)
			rest.configure(str(p[1]), {"f": "mono", "px": 12, "col": T.DIM})
			rest.size = rest.get_minimum_size()
			rest.position = Vector2(w + 6.0, (H - rest.pitch()) * 0.5)
			w += 6.0 + rest.size.x
		w += 9.0 + 1.0
		body.size = Vector2(w, H)
		body.position = Vector2(roundf(float(pin.get("x", 0.0)) - w * 0.5), roundf(float(pin.get("y", 0.0)) - H - LIFT))
		var badge := Badge.new()
		badge.tone = edge
		badge.position = Vector2(x, (H - 16.0) * 0.5)
		badge.size = Vector2(16, 16)
		body.add_child(badge)
		if hostile:
			continue
		var label := ("%s, unclaimed" % kind) if unclaimed else ("%s in range" % kind if in_range else "%s %s" % [kind, p[1]])
		var hit := K.hit(parent, body.position.x, body.position.y, w, H, label)
		if emit.is_valid():
			hit.pressed.connect(emit.bind("focus_deposit", pin.get("cell", [])))


class Badge extends Control:
	var tone: Color = T.CYAN

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 8.0, tone)
