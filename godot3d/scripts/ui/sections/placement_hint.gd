extends RefCounted
## The top-strip "PLACEMENT" hint chip (board 2) while a building is armed. The slice is vm["placement_hint"] itself: {right}, the
## x its right edge sits at (the adapter leaves room for the wave chip). It lists only the controls the game really binds:
## a click places and Esc cancels. The board's "R rotate" and "Enter confirm" are not built: footprints are single hexes
## that do not rotate, and Enter is not bound. Registered by BuildDeck so that it draws above the top strip.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")


static func build(parent: Control, d: Variant) -> void:
	if not (d is Dictionary) or not d.has("right"):
		return
	var parts := [{"t": "PLACEMENT", "col": T.CYAN}, {"key": "Click"}, {"t": "place", "col": T.DIM}, {"key": "Esc"}, {"t": "cancel", "col": T.DIM}]
	var chip := K.chip(parent, 0, 21, "", T.CYAN, parts, {"h": 34, "border": T.CYAN})
	chip.position.x = roundf(float(d["right"]) - chip.size.x)
