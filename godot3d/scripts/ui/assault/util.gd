extends RefCounted
## Colours and text helpers shared by the core-assault builders and world_marks.gd.
const T = preload("res://scripts/ui/tokens.gd")
const TextBox = preload("res://scripts/ui/components/text_box.gd")
const K = preload("res://scripts/ui/kit.gd")
const DropShadow = preload("res://scripts/ui/components/drop_shadow.gd")

const BOSS_EDGE := Color("7a2a26")
const BOSS_TRACK := Color("5a1e1a")
const BOSS_WELL := Color("150a0b")
const BOSS_TEXT := Color("ffd2cf")
const BOSS_CAP := Color("f4b3ae")
const BAD_SOFT := Color("ffb3ad")


## Tone words used by this state: the shared ones plus the soft red and the bright cyan the mock uses for icons.
static func tone(name: String) -> Color:
	match name:
		"cyan_hi": return T.CYAN_HI
		"bad_soft": return BAD_SOFT
		"line": return T.LINE
		_: return T.tone(name)


## CSS width of `s` in the given face; `sp` is letter-spacing in em.
static func width(kind: String, px: int, wt: int, sp: float, s: String) -> float:
	var probe := TextBox.new()
	probe.configure(s, {"f": kind, "px": px, "wt": wt, "sp": sp})
	var w := probe.measure(s)
	probe.free()
	return w


## `s` cut to one line of at most `max_w` px, ending in "..." when it had to be shortened.
static func fit(s: String, kind: String, px: int, wt: int, sp: float, max_w: float) -> String:
	if width(kind, px, wt, sp, s) <= max_w:
		return s
	var cut := s
	while cut.length() > 1 and width(kind, px, wt, sp, cut + "...") > max_w:
		cut = cut.substr(0, cut.length() - 1)
	return cut.strip_edges(false, true) + "..."


## Chrome snaps a box's edges to whole pixels: left = round(x), right = round(x + w). Returns Vector2(left, width).
static func snap(x: float, w: float) -> Vector2:
	var left := roundf(x)
	return Vector2(left, roundf(x + w) - left)


## A HoloPanel "panel" with the mock's outer drop shadow behind it (glass cards have none, use K.panel for those).
static func panel(root: Control, x: float, y: float, w: float, h: float, o := {}) -> Control:
	var p := K.panel(root, x, y, w, h, "panel", o)
	p.add_child(DropShadow.new())
	return p
