extends RefCounted
## Alert chips (board 1, top right): "N idle crews" (a Button that selects the first idle unit) and "Next alert mm:ss"
## (the next wave timer). Driven by vm["idle"] ({count, first_id}) and vm["alert"] ({label, seconds}); each chip exists
## only with its own slice and nothing is built when neither does. The idle chip shows its "." key cap because the game
## binds "." to select-first-idle; the board's Space cap on the other chip has no binding and is not drawn.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const X := 1548.0
const Y := 248.0
const H := 30
const GAP := 6.0


static func clock(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	var idle = vm.get("idle", null)
	var alert = vm.get("alert", null)
	var x := X
	if idle is Dictionary and int(idle.get("count", 0)) > 0:
		var n := int(idle["count"])
		var text := "%d idle crew%s" % [n, "" if n == 1 else "s"]
		var chip := K.chip(parent, x, Y, "", T.CYAN, [{"t": text, "col": T.CYAN}, {"key": "."}], {"h": H, "border": T.CYAN})
		var hit := K.hit(parent, x, Y, chip.size.x, H, "Idle crews %d" % n)
		if emit.is_valid():
			hit.pressed.connect(emit.bind("select_idle", idle.get("first_id")))
		x += chip.size.x + GAP
	if alert is Dictionary and alert.has("seconds"):
		K.chip(parent, x, Y, "", T.DIM, [{"t": "Next alert", "col": T.DIM}, {"t": clock(int(alert["seconds"])), "col": T.TEXT_HI, "wt": 500}], {"h": H})
