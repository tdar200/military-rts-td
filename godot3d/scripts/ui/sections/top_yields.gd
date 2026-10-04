extends RefCounted
## The yield pills row of the territory card ("+168 kW"). Driven by vm["yields"]: [{text, tone}], real quantities only.
## The snapshot has no per-minute income, so no "+38 M" or "+22 W" pills exist: a pill appears only when the adapter
## could back it. Builds nothing when the slice is absent or empty. Pills are laid out from (0, 0) in `parent`.
const T = preload("res://scripts/ui/tokens.gd")
const Pill = preload("res://scripts/ui/sections/pill.gd")

const GAP := 6.0


## Whether there is a row to draw, and how tall it is (0 when not), so a card can size itself around it.
static func row_height(vm: Dictionary) -> float:
	var list = vm.get("yields", [])
	return float(Pill.HEIGHT) if list is Array and not list.is_empty() else 0.0


static func build(parent: Control, vm: Dictionary) -> void:
	if row_height(vm) == 0.0:
		return
	var x := 0.0
	for item in vm["yields"]:
		var pill := Pill.make(parent, x, 0, str(item.get("text", "")), T.tone(str(item.get("tone", "cyan"))))
		x += pill.size.x + GAP
