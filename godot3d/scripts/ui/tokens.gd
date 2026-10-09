extends RefCounted
## The Ascension style guide as constants. Every colour, font and size under scripts/ui comes from here.

const BG0 := Color("03050a")
const BG1 := Color("060910")
const BG2 := Color("08111a")
const RAISED := Color("101c2a")
const HOVER := Color("183446")
const ACTIVE := Color("104656")
const LINE := Color("284e60")
const LINE_DIM := Color("1b3342")
const CYAN := Color("40dceb")
const CYAN_HI := Color("96f5ff")
const CYAN_DK := Color("185a6e")
const TEXT := Color("cee8f0")
const TEXT_HI := Color("e8fcff")
const DIM := Color("8fb0bf")
const FAINT := Color("5f8191")
const GOOD := Color("50e6a0")
const WARN := Color("f0b040")
const WARN_HI := Color("ffd78a")
const BAD := Color("f04e46")
const DANGER_EDGE := Color("7a2f2b")
const BAD_HI := Color("ffd6d2")
const VIOLET := Color("b79cff")
const SHIELD := Color("78b4ff")
const GROUND := Color("30332a")
const BAR_BG := Color("0b1620")
const KEY_BG := Color("03050a")
const PANEL_TOP := Color(18.0 / 255.0, 32.0 / 255.0, 46.0 / 255.0, 0.92)
const PANEL_BOT := Color(8.0 / 255.0, 16.0 / 255.0, 26.0 / 255.0, 0.92)
const GLASS := Color(8.0 / 255.0, 15.0 / 255.0, 24.0 / 255.0, 0.82)
const SCRIM := Color(3.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.86)
const TOP_LIGHT := Color(150.0 / 255.0, 245.0 / 255.0, 1.0, 0.10)
const GLOW := Color(64.0 / 255.0, 220.0 / 255.0, 235.0 / 255.0, 0.18)

## Map a view-model tone word to its colour. Unknown tones fall back to body text.
static func tone(name: String) -> Color:
	match name:
		"cyan": return CYAN
		"good": return GOOD
		"warn": return WARN
		"bad": return BAD
		"violet": return VIOLET
		"dim": return DIM
		"shield": return SHIELD
		"hi": return TEXT_HI
		_: return TEXT


const FONT_DIR := "res://assets/fonts/"
## Plex Mono advance width in em. Chrome lays mono text out at exactly this pitch, so we do too.
const MONO_ADVANCE := 0.6

static var _fonts: Dictionary = {}


## kind: "disp" (Rajdhani), "body" (IBM Plex Sans), "mono" (IBM Plex Mono). weight: CSS weight, 0 = default.
static func font(kind: String, weight := 0) -> Font:
	var key := "%s:%d" % [kind, weight]
	if _fonts.has(key):
		return _fonts[key]
	var made: Font
	match kind:
		"disp":
			made = _file("Rajdhani-Bold.ttf" if weight >= 700 else "Rajdhani-SemiBold.ttf")
		"mono":
			made = _file("IBMPlexMono-Medium.ttf" if weight >= 500 else "IBMPlexMono-Regular.ttf")
		_:
			made = _variable("IBMPlexSans-VF.ttf", weight if weight > 0 else 400)
	_fonts[key] = made
	return made


## Task 28: the bytes come from the imported FontFile, because an exported pack carries no raw .ttf. A fresh FontFile
## holding those bytes is what FontFile.load_dynamic_font made from the source file, so the import options never apply
## and every face renders as before.
static func _file(name: String) -> FontFile:
	var file := FontFile.new()
	var imported := load(FONT_DIR + name) as FontFile
	if imported:
		file.data = imported.data
	return file


static func _variable(name: String, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = _file(name)
	# Variation axes are keyed by integer OpenType tags; string keys are silently ignored.
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation


## Chrome's "line-height: normal" is the rounded ascent plus the rounded descent of the face.
static func ascent(f: Font, px: int) -> int:
	return roundi(f.get_ascent(1000) * px / 1000.0)


static func descent(f: Font, px: int) -> int:
	return roundi(f.get_descent(1000) * px / 1000.0)
