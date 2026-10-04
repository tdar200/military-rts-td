extends RefCounted
## The bottom-centre frame of board 1 (nothing selected): one 940x258 panel holding the tile inspector, the colony ledger
## and the army orders column, with a 1px rule between columns that are present. Drawn when any of vm["inspect"],
## vm["ledger"] or vm["army"] exists; the columns are separate sections that draw over it.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const X := 328.0
const Y := 810.0
const W := 940.0
const H := 258.0
## Column origins inside the frame (1px border + 16px padding, then 330 / 1fr / 230 with 16px gaps).
const COL1_X := 345.0
const COL2_X := 691.0
const COL3_X := 1004.0
const COL_TOP := 825.0
const COL_H := 228.0


static func _filled(vm: Dictionary, key: String) -> bool:
	var v = vm.get(key, null)
	return v is Dictionary and not v.is_empty()


static func present(vm: Dictionary) -> bool:
	return _filled(vm, "inspect") or _filled(vm, "ledger") or _filled(vm, "army")


static func build(parent: Control, vm: Dictionary) -> void:
	if not present(vm):
		return
	K.panel(parent, X, Y, W, H)
	if _filled(vm, "ledger"):
		K.rule(parent, COL2_X, COL_TOP, 1, COL_H, T.LINE_DIM)
	if _filled(vm, "army"):
		K.rule(parent, COL3_X, COL_TOP, 1, COL_H, T.LINE_DIM)
