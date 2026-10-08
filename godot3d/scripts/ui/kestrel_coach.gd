extends RefCounted
## Kestrel Reach's onboarding coach (kestrel-depth Task 9). Pure: five first-run lessons walked one at a time, each
## finished only by the player's own order of that kind (earthfront_3d.gd reports them through _coach_event), never by
## the snapshot, so no lesson can be skipped and nothing about hidden enemies can leak through it. The hint text names the
## keys from Keybinds; three lessons add the current objective's own line (KestrelObjectives.evaluate, which already reads
## only what the player can see) when that objective is the one the lesson serves.
##
## "Never show again" (the card's button, or the last lesson finished) is the one persisted bit: Settings key
## coach/never_show in user://settings.cfg, read and written only through the Settings owner (tests pass their own path).
## Survival never shows the coach.
const Settings := preload("res://scripts/ui/settings.gd")
const Keybinds := preload("res://scripts/ui/keybinds.gd")
const KestrelObjectives := preload("res://scripts/world/kestrel_objectives.gd")

const STEPS := ["select_squad", "move", "place_building", "train", "attack_move", "done"]
## The order that finishes each lesson (STEPS[i] is finished by EVENTS[i]).
const EVENTS := ["selected_units", "move_sent", "build_sent", "train_sent", "attack_move_sent"]
const KEY := "coach/never_show"
## The objectives (KestrelObjectives.IDS) a lesson serves: while one of them is the current objective, the card shows its line.
const SERVES := {"place_building": ["power", "economy"], "train": ["squad"], "attack_move": ["ford", "core"]}


## The step after `step` when `event` is the order that finishes it; otherwise `step` unchanged ("done" absorbs everything).
static func advance(step: String, event: String) -> String:
	var i := STEPS.find(step)
	if i < 0 or i >= EVENTS.size():
		return step
	return STEPS[i + 1] if event == EVENTS[i] else step


## {title, body, keys} for a lesson ({} for "done" or an unknown step). Bodies stay within two card lines.
static func hint(step: String) -> Dictionary:
	match step:
		"select_squad":
			return {"title": "Select your squad", "body": "Drag a box round your riflemen, or press %s for the whole army." % Keybinds.cap(Keybinds.SELECT_ARMY),
				"keys": ["Left drag", Keybinds.cap(Keybinds.SELECT_ARMY)]}
		"move":
			return {"title": "Move out", "body": "Right click open ground to send the selected units there.", "keys": ["Right click"]}
		"place_building":
			var turret := Keybinds.cap(int(Keybinds.BUILD.find_key("GunTurret")))
			return {"title": "Place a building", "body": "Press %s for a gun turret, then left click open ground in your zone." % turret,
				"keys": [turret, "Left click"]}
		"train":
			var rifles := Keybinds.cap(int(Keybinds.TRAIN.find_key("Infantry")))
			return {"title": "Train a unit", "body": "Press %s to train riflemen at the Barracks, or click a Units card." % rifles, "keys": [rifles]}
		"attack_move":
			var attack := Keybinds.cap(Keybinds.ATTACK_MOVE)
			return {"title": "Attack-move", "body": "Press %s, then right click: the squad fights whatever it meets." % attack,
				"keys": [attack, "Right click"]}
	return {}


## hint(step) plus "objective": the current objective's detail line when the lesson serves it (SERVES), else "". `objectives`
## is the game's last KestrelObjectives.evaluate result ({} before the first snapshot).
static func hint_for(step: String, objectives: Dictionary) -> Dictionary:
	var out := hint(step)
	if out.is_empty():
		return out
	out["objective"] = ""
	var stage := int(objectives.get("stage", 0))
	if stage >= 1 and stage <= KestrelObjectives.IDS.size() and not bool(objectives.get("complete", false)):
		if KestrelObjectives.IDS[stage - 1] in SERVES.get(step, []):
			out["objective"] = str(objectives.get("detail", ""))
	return out


## Shown on Kestrel only, for a lesson still to do, until the player chose never to see it again.
static func visible(step: String, never_show: bool, kestrel: bool) -> bool:
	return kestrel and not never_show and step in STEPS and step != "done"


## The saved "never show again" (false on a fresh install).
static func never_show(path := Settings.PATH) -> bool:
	return bool(Settings.get_value(KEY, path))


## Saves "never show again" (through Settings, which refuses res://). Returns the Settings error code.
static func dismiss(path := Settings.PATH) -> int:
	return Settings.set_value(KEY, true, path)
