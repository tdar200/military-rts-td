extends RefCounted
## Stroke icons from the design set (24 viewBox, 1.75 stroke, round caps). Rasterised white and tinted by the caller.
## Textures are created on demand and cached. Never call texture() from inside _draw(): a texture created during
## a draw pass renders as a solid square. Create it in a setter or _ready() and read it back with cached().

const SHAPES := {
	"map": '<path d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z"/><path d="M9 4v14M15 6v14"/>',
	"chevron_left": '<path d="M15 5l-7 7 7 7"/>',
	"material": '<path d="M12 2l9 5v10l-9 5-9-5V7l9-5zM3 7l9 5 9-5M12 12v10"/>',
	"ore": '<path d="M12 2l8 4.5v9L12 20l-8-4.5v-9L12 2z"/>',
	"power": '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>',
	"battery": '<rect x="3" y="8" width="16" height="9" rx="1"/><path d="M21 11v3M7 11v3"/>',
	"crew": '<circle cx="9" cy="8" r="3"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.5"/><path d="M16 14.5c2.8.2 5 2.4 5 5.5"/>',
	"ammo": '<path d="M8 20V9a4 4 0 018 0v11M8 20h8M8 13h8"/>',
	"flask": '<path d="M9 3h6M10 3v6l-5 9a2 2 0 001.8 3h10.4a2 2 0 001.8-3l-5-9V3"/>',
	"wave": '<path d="M2 12c2.5-4 4.5-4 7 0s4.5 4 7 0 4.5-4 6-2"/>',
	"pause": '<path d="M8 5v14M16 5v14"/>',
	"check": '<path d="M4 12l5 5 11-11"/>',
	"circle": '<circle cx="12" cy="12" r="7"/>',
	"circle_dashed": '<circle cx="12" cy="12" r="7" stroke-dasharray="3 3"/>',
	"build": '<path d="M14.7 6.3a4 4 0 00-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 005.4-5.4l-2.6 2.6-2.4-.6-.6-2.4 2.6-2.6z"/>',
	"units": '<circle cx="9" cy="8" r="3"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.5"/>',
	"orders": '<path d="M4 12h12M12 6l6 6-6 6"/>',
	"logistics": '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M8 17l8-10" stroke-dasharray="3 3"/>',
	"warning": '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17v.5"/>',
	"clock": '<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
	"check_bold": '<path d="M5 12l5 5 9-10"/>',
	"lock": '<rect x="5" y="11" width="14" height="9" rx="1"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
	"play": '<path d="M7 5l12 7-12 7z"/>',
	"plus": '<path d="M12 5v14M5 12h14"/>',
	"crosshair": '<circle cx="12" cy="12" r="7"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5"/>',
	"flask_title": '<path d="M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3"/>',
	"cog": '<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/>',
	"restart": '<path d="M12 3v8M6.5 6.8a8 8 0 1 0 11 0"/>',
	"bolt_alt": '<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>',
	"circle_check": '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/>',
	"circle_clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	"circle_dashed_lg": '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/>',
	"search": '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 5 5"/>',
	"check_thin": '<path d="m5 12.5 4.5 4.5L19 7"/>',
	"circle_plus": '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>',
	"flag": '<path d="M6 21V4M6 5h11l-2 4 2 4H6"/>',
	"circle_help": '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 17v.5"/>',
	"wave_alt": '<path d="M4 18c4 0 4-12 8-12s4 12 8 12"/>',
	"signature": '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="8" stroke-dasharray="2 3"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3"/>',
	"cube": '<path d="M12 3 4 7.5v9L12 21l8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9"/>',
	"crew_alt": '<circle cx="9" cy="8" r="3"/><path d="M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6"/><circle cx="17" cy="9" r="2.4"/><path d="M17 14c2.5 0 4.5 2 4.5 5"/>',
	"target": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
	"relay": '<path d="M12 12v9M8 21h8M7 8a7 7 0 0 1 10 0M4.5 5.5a11 11 0 0 1 15 0"/><circle cx="12" cy="11" r="1.5"/>',
	"home": '<path d="M3 11 12 4l9 7M5 10v10h14V10M10 20v-6h4v6"/>',
	"tower": '<path d="M9 21V9l3-5 3 5v12M9 14h6"/>',
	"clock_alt": '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>',
	"cross_bold": '<path d="M6 6l12 12M18 6L6 18"/>',
	"warning_alt": '<path d="M12 3 2 21h20zM12 10v5M12 18v.5"/>',
}

static var _cache: Dictionary = {}


static func has(name: String) -> bool:
	return SHAPES.has(name)


## Rasterise `name` into a px-by-px white-on-transparent texture. Call from setters or _ready(), never from _draw().
static func texture(name: String, px := 18, stroke := 1.75) -> Texture2D:
	var key := "%s:%d:%s" % [name, px, str(stroke)]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="%d" height="%d" fill="none" stroke="#ffffff" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [px, px, str(stroke), SHAPES[name]]
	var image := Image.new()
	var err := image.load_svg_from_string(svg, 1.0)
	assert(err == OK, "icon %s failed to rasterise" % name)
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


## Read back a texture made earlier by texture(). Safe inside _draw().
static func cached(name: String, px := 18, stroke := 1.75) -> Texture2D:
	return _cache.get("%s:%d:%s" % [name, px, str(stroke)])


## The Ascension mark: two nested triangles, drawn in its own colours (do not tint).
static func logo(px := 26) -> Texture2D:
	var key := "logo:%d" % px
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 26 26" width="%d" height="%d" fill="none" stroke-width="1.75" stroke-linejoin="round"><path d="M13 2l10 21H3z" stroke="#96f5ff"/><path d="M13 9l4.5 10h-9z" stroke="#40dceb"/></svg>' % [px, px]
	var image := Image.new()
	image.load_svg_from_string(svg, 1.0)
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made
