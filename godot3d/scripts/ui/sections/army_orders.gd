extends RefCounted
## Army orders column (board 1, bottom centre, right column): "Select army" and "Idle crews N", real Buttons that emit
## their action through the supplied callback. Driven by vm["army"] ({count, idle, first_idle}); each button exists only
## when its own count is above zero, and nothing is built otherwise. The board's "Ctrl A" key cap is not drawn: Ctrl+A
## still arms attack-move and A pans the camera, so select-army sits on F2 and the board shows no key text. The board's
## "Open lab" button has no matching command and is not built.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")
const Frame = preload("res://scripts/ui/sections/bottom_panel.gd")

const X := 1021.0
const W := 230.0
const BTN_H := 44.0
const GAP := 8.0


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var army = vm.get("army", null)
	var has_army: bool = army is Dictionary and int(army.get("count", 0)) > 0
	var has_idle: bool = army is Dictionary and int(army.get("idle", 0)) > 0
	var n := (1 if has_army else 0) + (1 if has_idle else 0)
	if n == 0:
		return
	# The board centres three buttons in the column; the first one sits here whatever number are present.
	var y := Frame.COL_TOP + (Frame.COL_H - (3.0 * BTN_H + 2.0 * GAP)) * 0.5
	if has_army:
		var b := K.button(parent, "Select army", X, y, {"w": W, "h": BTN_H, "primary": true})
		_wire(b, emit, "select_army", null)
		y += BTN_H + GAP
	if has_idle:
		var b := K.button(parent, "Idle crews %d" % int(army["idle"]), X, y, {"w": W, "h": BTN_H})
		_wire(b, emit, "select_idle", army.get("first_idle"))


static func _wire(b: Control, emit: Callable, action: String, arg: Variant) -> void:
	if emit.is_valid():
		(b as Button).pressed.connect(emit.bind(action, arg))
