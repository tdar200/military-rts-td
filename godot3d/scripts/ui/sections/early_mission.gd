extends RefCounted
## First-minutes briefing card (board 6, top left under the top bar): the step tag, the objective title, a short paragraph, the
## three objective lines (done, current, next) and a progress bar, with a Hide button. Driven by vm_maps.briefing(), which reads
## the game's tutorial stage (the objective the HUD already shows; the snapshot has no objective text). `emit` is
## Callable(name, arg) and receives briefing_dismiss. Builds nothing without a vm. The card is a fixed HEIGHT so the left card
## stack can sit below it (live_adapter.gd).
## Not built: the board's "Mission updated" toast and its survey wording; nothing here mentions fog or surveying.
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const X := 12.0
const Y := 76.0
const W := 360.0
const HEIGHT := 240.0
const PAD_X := 16.0
const PAD_Y := 14.0
const BODY_LINES := 3
const BODY_LINE := 18.5


## The card's screen rectangle, for hit testing in the host.
static func rect() -> Rect2:
	return Rect2(X, Y, W, HEIGHT)


static func build(parent: Control, vm: Dictionary, emit := Callable()) -> void:
	if vm.is_empty():
		return
	var panel := K.panel(parent, X, Y, W, HEIGHT, "panel", {"border": T.CYAN})
	panel.name = "Briefing"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var cx := X + 1.0 + PAD_X
	var cw := W - 2.0 - 2.0 * PAD_X
	var y := Y + 1.0 + PAD_Y
	var cap := K.text(parent, "Briefing", {"x": cx, "y": y, "f": "mono", "px": 12, "sp": 0.12, "col": T.CYAN, "up": true})
	var tag := K.tag(parent, str(vm.get("tag", "")), 0, y, T.CYAN)
	tag.position = Vector2(roundf(cx + cw - tag.size.x), roundf(y + (cap.size.y - tag.size.y) * 0.5))
	y += maxf(cap.size.y, tag.size.y) + 4.0
	var title := K.text(parent, str(vm.get("title", "")), {"x": cx, "y": y, "f": "disp", "wt": 600, "px": 24, "sp": 0.04, "col": T.TEXT_HI, "up": true})
	y += title.size.y + 6.0
	var body := K.text(parent, str(vm.get("body", "")), {"x": cx, "y": y, "w": cw, "px": 14, "lh": BODY_LINE, "col": T.TEXT, "wrap": true})
	body.name = "Body"
	y += BODY_LINE * BODY_LINES + 10.0
	for item in vm.get("items", []):
		var state := str(item.get("state", "todo"))
		var icon_name := "check" if state == "done" else ("circle" if state == "active" else "circle_dashed")
		var icon_col: Color = T.GOOD if state == "done" else (T.CYAN if state == "active" else T.DIM)
		var line := K.text(parent, str(item.get("t", "")), {"x": cx + 22.0, "y": y, "w": cw - 22.0, "px": 14, "col": T.TEXT if state == "active" else T.DIM})
		K.icon(parent, icon_name, cx, y + (line.size.y - 14.0) * 0.5, icon_col, 14)
		y += line.size.y + 6.0
	var hide := K.button(parent, "Hide", 0, 0, {"min_h": 24, "px": 13, "pad": 10})
	var bar_y := Y + HEIGHT - 1.0 - PAD_Y - 6.0
	K.place(hide, cx + cw - hide.size.x, bar_y + 3.0 - hide.size.y * 0.5)
	K.bar(parent, cx, bar_y, cw - hide.size.x - 10.0, float(vm.get("ratio", 0.0)), T.CYAN, 6.0)
	if emit.is_valid():
		hide.pressed.connect(emit.bind("briefing_dismiss", null))
