extends Control
## Renders one screen with fixture data at 1920x1080 over the flat ground colour the mock comparisons use.
## Scripts load on demand, so a screen can be captured as soon as its own files are installed.
const T = preload("res://scripts/ui/tokens.gd")

var screen := "main"


func _ready() -> void:
	size = Vector2(1920, 1080)
	var ground := ColorRect.new()
	ground.color = T.GROUND
	ground.size = size
	add_child(ground)
	match screen:
		"main":
			_hud(_l("gallery/fixtures.gd").hud_main(), false)
		"builddeck":
			_hud(_l("gallery/fixtures_build.gd").build_deck(), true)
		"builddeck_many", "builddeck_none", "builddeck_locked", "builddeck_short", "builddeck_no_queue", "builddeck_invalid":
			_hud(_l("gallery/fixtures_build.gd").edge(screen.trim_prefix("builddeck_")), true)
		"research":
			_screen(_l("ui/research_screen.gd").new(), _l("gallery/fixtures_research.gd").research())
		"coreassault":
			var marks = _l("ui/world_marks.gd").new()
			add_child(marks)
			marks.set_marks(_l("gallery/fixtures_assault.gd").marks())
			var assault_hud = _l("ui/hud.gd").new()
			add_child(assault_hud)
			_l("ui/assault/assault.gd").register(assault_hud)
			assault_hud.apply(_l("gallery/fixtures_assault.gd").hud())
		"title":
			_screen(_l("ui/title_screen.gd").new(), _l("gallery/fixtures_title.gd").title())
		"title_empty", "title_1", "title_12", "title_long", "title_disabled":
			_screen(_l("ui/title_screen.gd").new(), _l("gallery/fixtures_title.gd").edge(screen))
		"debrief":
			var win = _l("ui/debrief.gd").new()
			add_child(win)
			win.apply(_l("gallery/fixtures_debrief.gd").victory())
			var lose = _l("ui/debrief.gd").new()
			lose.position = Vector2(960, 0)
			add_child(lose)
			lose.apply(_l("gallery/fixtures_debrief.gd").defeat())
		"debrief_edge":
			# Stress layouts: long names with no chart series (left) and a 12-row timeline scaled into its half (right).
			var vm = _l("gallery/fixtures_debrief.gd").victory()
			vm["title"] = "The Extraordinarily Long Chapter Name Of The Dawnshield Campaign"
			vm["operation"] = "Operation Dawnshield " + "Dawnshield ".repeat(8)
			vm["casualties"]["rows"][0]["name"] = "Heavily armoured expeditionary infantry battalion"
			vm["economy"]["series"] = []
			var left = _l("ui/debrief.gd").new()
			add_child(left)
			left.apply(vm)
			var dv = _l("gallery/fixtures_debrief.gd").defeat()
			var rows: Array = dv["timeline"]["rows"]
			while rows.size() < 12:
				rows.append(rows[rows.size() % 6].duplicate(true))
			var right = _l("ui/debrief.gd").new()
			add_child(right)
			right.apply(dv)
			_l("ui/debrief.gd").place_in(right, Vector2(960, 1080))
			right.position.x += 960


## A Hud screen. The map slot gets the flat ground colour the mock's stand-in battlefield uses.
func _hud(vm: Dictionary, with_build: bool) -> void:
	var hud = _l("ui/hud.gd").new()
	add_child(hud)
	if with_build:
		_l("ui/build_deck.gd").register(hud)
	hud.apply(vm)
	var fill := ColorRect.new()
	fill.color = T.GROUND
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.map_slot.add_child(fill)


func _screen(node: Control, vm: Dictionary) -> void:
	add_child(node)
	node.apply(vm)


func _l(path: String) -> Variant:
	return load("res://scripts/" + path)
