extends RefCounted
## Kestrel fog of war, client side (presentation only; the sim and its AI stay omniscient). Holds the bridge's per-cell
## mask (snapshot key `fog`: one digit per cell, row-major, 0 unseen, 1 explored, 2 visible), answers "can the player see
## this point" for effects, sounds and entity sync, and keeps an L8 texture of the mask (0, 128, 255 per cell) for the
## ground and prop shaders. A missing, empty or wrong-length mask is no fog at all: every query answers visible and nothing
## warns (Survival never sends the key; EARTHFRONT_FOG=0 sends an all-visible mask, which is also inactive).
##
## The rule the client follows: the ground and the props are shaded by the mask (soft edges, one texel per cell, linear
## filter); entities exist only when the bridge sends them (visible now, or a remembered building flagged `remembered`);
## effects and world sounds are skipped at spawn when their point is not seen (now or on the previous poll).

const UNSEEN := 0
const EXPLORED := 1
const VISIBLE := 2
## Texel value per state in the L8 mask.
const LEVELS := [0, 128, 255]

## Shared by the Kestrel ground and both prop shaders. `fog_at` samples the mask at a world xz point: the two nearest
## columns are read at their texel centres (an odd column half a row lower, as the hexes sit), each with a linear blend
## along its rows, then blended across with a smoothstep, so cell edges stay soft. Off the map the edge texel is clamped.
## `fog_tint` maps 0 (unseen) to a near-black blue shroud, 0.5 (explored) to a dim, slightly desaturated ground and 1
## (visible) to the colour itself. Callers apply it only when `fog_enabled` is on, so fog off draws exactly as before.
const SHADER_FUNCTIONS := """
uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform float fog_enabled = 0.0;
uniform vec4 fog_grid = vec4(2.1, 1.0, 0.68, 0.70);
uniform vec2 fog_cells = vec2(44.0, 26.0);
float fog_column(float col, float gz) {
    float c = clamp(col, 0.0, fog_cells.x - 1.0);
    float r = gz - mod(c, 2.0) * 0.5;
    return texture(fog_mask, vec2((c + 0.5) / fog_cells.x, (r + 0.5) / fog_cells.y)).r;
}
float fog_at(vec2 xz) {
    float gx = (xz.x - fog_grid.x) / fog_grid.z;
    float gz = (xz.y - fog_grid.y) / fog_grid.w;
    float c0 = floor(gx);
    float t = smoothstep(0.0, 1.0, gx - c0);
    return mix(fog_column(c0, gz), fog_column(c0 + 1.0, gz), t);
}
vec3 fog_tint(vec3 c, float v) {
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 dim = mix(c, vec3(l), 0.35) * 0.48 + vec3(0.0, 0.004, 0.014);
    vec3 shroud = c * 0.05 + vec3(0.010, 0.014, 0.026);
    float a = smoothstep(0.0, 0.5, v);
    float b = smoothstep(0.5, 1.0, v);
    return mix(mix(shroud, dim, a), c, b);
}
"""

var width := 0
var height := 0
var origin_x := 2.1
var origin_z := 1.0
var hex_x := 0.68
var hex_z := 0.70
var texture_updates := 0
var _mask := ""
var _cells := PackedByteArray()  # state per cell (0, 1, 2); empty when inactive
var _prev := PackedByteArray()  # the cells of the previous parse (empty when that one was inactive)
var _active := false
var _image: Image
var _texture: ImageTexture


func configure(map_origin_x: float, map_origin_z: float, cell_x: float, cell_z: float) -> void:
	origin_x = map_origin_x
	origin_z = map_origin_z
	hex_x = cell_x
	hex_z = cell_z


## Reads one snapshot's mask. Returns true when it differs from the last one (the texture was rewritten). Every call moves
## the current cells to the previous slot, so `seen_recently` always covers exactly one poll back.
func parse(mask: String, w: int, h: int) -> bool:
	_prev = _cells
	var valid := w > 0 and h > 0 and mask.length() == w * h
	if not valid:
		var was := not _cells.is_empty()
		_cells = PackedByteArray()
		_mask = ""
		_active = false
		width = 0
		height = 0
		return was
	if mask == _mask and w == width and h == height:
		return false
	width = w
	height = h
	_mask = mask
	var raw := mask.to_ascii_buffer()
	var cells := PackedByteArray()
	cells.resize(raw.size())
	var any_dark := false
	for i in raw.size():
		var s := UNSEEN if raw[i] == 48 else (EXPLORED if raw[i] == 49 else VISIBLE)
		cells[i] = s
		if s != VISIBLE:
			any_dark = true
	_cells = cells
	_active = any_dark
	_write_image()
	return true


## True when the mask hides something. A missing mask or an all-visible one (fog off) is not active.
func active() -> bool:
	return _active


func cell_state(x: int, y: int) -> int:
	if not _active:
		return VISIBLE
	return _cells[clampi(y, 0, height - 1) * width + clampi(x, 0, width - 1)]


## The cell a world point falls in: the column is rounded first, then the row with that column's half-row offset (as
## `_world_to_tile`). Points off the grid read the nearest edge cell, as the shader's clamp does.
func cell_of(world: Vector3) -> Vector2i:
	var col := clampi(roundi((world.x - origin_x) / hex_x), 0, maxi(width - 1, 0))
	var off := hex_z * 0.5 if col % 2 == 1 else 0.0
	var row := clampi(roundi((world.z - origin_z - off) / hex_z), 0, maxi(height - 1, 0))
	return Vector2i(col, row)


func state_at(world: Vector3) -> int:
	if not _active:
		return VISIBLE
	var c := cell_of(world)
	return _cells[c.y * width + c.x]


func is_visible(world: Vector3) -> bool:
	return state_at(world) == VISIBLE


## Visible now, or on the previous poll: an effect whose cause the player just saw (a viewer killed this tick) still shows.
func seen_recently(world: Vector3) -> bool:
	if not _active or is_visible(world):
		return true
	if _prev.size() != width * height or width == 0:
		return false
	var c := cell_of(world)
	return _prev[c.y * width + c.x] == VISIBLE


## Visible on the previous poll (true without fog; false when the previous poll had no mask): ground the player was
## already watching, so something new there was made there, not found.
func was_visible(world: Vector3) -> bool:
	if not _active:
		return true
	if _prev.size() != width * height or width == 0:
		return false
	var c := cell_of(world)
	return _prev[c.y * width + c.x] == VISIBLE


## The point and the eight points `radius` away around it are all visible: something there cannot have stepped out of
## sight since the last poll.
func deep_visible(world: Vector3, radius: float) -> bool:
	if not _active:
		return true
	if not is_visible(world):
		return false
	for k in 8:
		var a := float(k) * TAU / 8.0
		if not is_visible(world + Vector3(cos(a) * radius, 0.0, sin(a) * radius)):
			return false
	return true


## Explored plus visible cells (the whole map without fog).
func known_cells() -> int:
	if not _active:
		return width * height
	var n := 0
	for s in _cells:
		if s != UNSEEN:
			n += 1
	return n


func explored_pct() -> int:
	if not _active:
		return 100
	return roundi(100.0 * float(known_cells()) / float(width * height))


## The L8 mask image (one texel per cell); a single white texel without a valid mask.
func image() -> Image:
	if _image == null:
		_image = Image.create(1, 1, false, Image.FORMAT_L8)
		_image.set_pixel(0, 0, Color.WHITE)
	return _image


## One texture object for the life of the view: materials keep the reference and see each update.
func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image())
	return _texture


func _write_image() -> void:
	var data := PackedByteArray()
	data.resize(_cells.size())
	for i in _cells.size():
		data[i] = LEVELS[_cells[i]]
	var img := Image.create_from_data(width, height, false, Image.FORMAT_L8, data)
	var resized := _image == null or _image.get_size() != img.get_size()
	_image = img
	if _texture == null:
		return
	if resized:
		_texture.set_image(_image)
	else:
		_texture.update(_image)
	texture_updates += 1


## The shader's `fog_tint` in GDScript (tests and the region map use it).
static func tint(c: Color, v: float) -> Color:
	var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var dim := Color(_mixf(c.r, l, 0.35) * 0.48, _mixf(c.g, l, 0.35) * 0.48 + 0.004, _mixf(c.b, l, 0.35) * 0.48 + 0.014)
	var shroud := Color(c.r * 0.05 + 0.010, c.g * 0.05 + 0.014, c.b * 0.05 + 0.026)
	var a := smoothstep(0.0, 0.5, v)
	var b := smoothstep(0.5, 1.0, v)
	var mid := Color(_mixf(shroud.r, dim.r, a), _mixf(shroud.g, dim.g, a), _mixf(shroud.b, dim.b, a))
	return Color(_mixf(mid.r, c.r, b), _mixf(mid.g, c.g, b), _mixf(mid.b, c.b, b), c.a)


static func _mixf(a: float, b: float, t: float) -> float:
	return a * (1.0 - t) + b * t
