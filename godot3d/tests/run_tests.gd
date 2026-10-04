extends SceneTree
## Headless test runner: godot --headless --path godot3d --script res://tests/run_tests.gd [-- name_filter]
## Every tests/test_*.gd is a script with `func test_*(t)`; `t` offers ok / eq / near. Exit code 1 on any failure.

var passed := 0
var failed := 0
var _current := ""


func ok(cond: bool, msg := "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		printerr("  FAIL %s: %s" % [_current, msg])


func eq(actual: Variant, expected: Variant, msg := "") -> void:
	ok(typeof(actual) == typeof(expected) and actual == expected, "%s (got %s, want %s)" % [msg, str(actual), str(expected)])


func near(actual: float, expected: float, eps := 0.5, msg := "") -> void:
	ok(absf(actual - expected) <= eps, "%s (got %s, want %s +-%s)" % [msg, str(actual), str(expected), str(eps)])


func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var dir := DirAccess.open("res://tests")
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("  FAIL %s: the test script did not compile (a script it preloads is missing or has an error)" % f)
			continue
		var unit = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (filter != "" and not (f + ":" + name).contains(filter)):
				continue
			_current = f + ":" + name
			unit.call(name, self)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
