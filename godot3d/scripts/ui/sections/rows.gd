extends RefCounted
## Label / value rows shared by the board 2 and 3 cards (placement card, enemy territory, combat preview): the mock's .row,
## 14px text, 5px above and below, a hairline between rows, the label dim on the left and the value in mono on the right.
## When both do not fit the width they shrink in proportion and wrap, the way the mock's flex row does.
## A row is {label, value, tone} with tone one of "", "good", "bad", "warn", "dim".
const T = preload("res://scripts/ui/tokens.gd")
const K = preload("res://scripts/ui/kit.gd")

const GAP := 12.0
const RULE := Color(27.0 / 255.0, 51.0 / 255.0, 66.0 / 255.0, 0.7)


static func tone_color(tone: String) -> Color:
	match tone:
		"good":
			return T.GOOD
		"bad":
			return T.BAD
		"warn":
			return T.WARN
		"dim":
			return T.DIM
	return T.TEXT


## Draws the rows from (x, y) across `w` px and returns the block's height.
static func build(parent: Control, x: float, y: float, w: float, rows: Array) -> float:
	var top := y
	for i in rows.size():
		var row: Dictionary = rows[i]
		var label_s := str(row.get("label", ""))
		var value_s := str(row.get("value", ""))
		var probe_l := K.text(parent, label_s, {"px": 14})
		var probe_v := K.text(parent, value_s, {"f": "mono", "px": 14})
		var lw: float = probe_l.size.x
		var vw: float = probe_v.size.x
		probe_l.free()
		probe_v.free()
		var wrap := lw + vw + GAP > w
		var label: Control
		var value: Control
		var colour := tone_color(str(row.get("tone", "")))
		if wrap:
			var over := lw + vw + GAP - w
			var lw2 := ceilf(lw - over * lw / (lw + vw))
			var vw2 := w - GAP - lw2
			label = K.text(parent, label_s, {"x": x, "y": y + 5.0, "w": lw2, "px": 14, "col": T.DIM, "wrap": true})
			value = K.text(parent, value_s, {"x": x + w - vw2, "y": y + 5.0, "w": vw2, "f": "mono", "px": 14, "col": colour, "wrap": true, "al": "r"})
		else:
			label = K.text(parent, label_s, {"x": x, "y": y + 5.0, "px": 14, "col": T.DIM})
			value = K.text(parent, value_s, {"x": 0, "y": y + 5.0, "f": "mono", "px": 14, "col": colour})
			value.position.x = roundf(x + w - value.size.x)
		var inner := maxf(label.size.y, value.size.y)
		label.position.y = roundf(y + 5.0 + (inner - label.size.y) * 0.5)
		value.position.y = roundf(y + 5.0 + (inner - value.size.y) * 0.5)
		y += inner + 10.0
		if i < rows.size() - 1:
			K.rule(parent, x, y, w, 1, RULE)
			y += 1.0
	return y - top
