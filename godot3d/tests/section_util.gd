extends RefCounted
## Shared helpers for the test_section_*.gd files (not a test itself: no test_ prefix).


## Every text a section drew: TextBox runs and Button labels, in tree order.
static func texts(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Control", true, false):
		var s = n.get("text")
		if s is String and s != "":
			out.append(s)
	return out


static func has_text(root: Node, needle: String) -> bool:
	for s in texts(root):
		if str(s).contains(needle):
			return true
	return false


static func buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false)


static func button_with(root: Node, prefix: String) -> Button:
	for b in buttons(root):
		if (b as Button).text.begins_with(prefix):
			return b
	return null
