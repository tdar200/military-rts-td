"""Paint the Kestrel building kinds the boards never drew, from crops of the boards' own sprites.

The boards paint eight building sprites per side; the sim has thirteen building kinds. Before this script the factory and
the airfield drew the barracks, the battery and the antimatter plant the power plant, the depot the refinery and the lab
a tank (capital_v1). Each variant here is composited from recoloured crops of the existing paintings (assets/*.png), plus
plinths, crates, a landing pad and a glass dome shaded to match, so it keeps their painted look and reads with a
silhouette of its own at board size (150 to 250 px).

Every output keeps the 256 x 256 canvas and the boards' ground contact line (WorldSprites.FOOT: 0.85 of the card height,
y 217.6): the painted base rests on it and its front runs a little past it, as on every board sprite. Deterministic: no
clock, every random draw seeded.

Usage: python3 tools/ui/build_building_variants.py  (writes godot3d/assets/world/sprites/<name>.png)"""
import math, pathlib, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = pathlib.Path(__file__).absolute().parents[2]
SRC = REPO / "assets"
OUT = REPO / "godot3d/assets/world/sprites"
SIZE = 256
CONTACT = round(0.85 * SIZE)  # 218: the boards' contact line (WorldSprites.FOOT)
SQUASH = 0.55  # the boards' ground plane on screen: the foundation's square footprint is a diamond 0.55 as tall as wide

# hues on PIL's 0..255 HSV scale
CYAN = 128  # the human glass and trim (about 180 degrees)
ORANGE = 24  # the alien glow (about 34 degrees)
LIME = 56  # the batteries (about 80 degrees)
VIOLET = 196  # antimatter (about 277 degrees)
AMBER = 27  # the factory's trim (about 38 degrees)


def load(name):
    return Image.open(SRC / (name + ".png")).convert("RGBA")


def canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def arr(im):
    return np.asarray(im).astype(np.float32)


def img(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def part(im, box, poly=None):
    """The crop `box` (x0, y0, x1, y1) of `im`; with `poly` (source coordinates) only the pixels inside the polygon."""
    out = im.crop(box)
    if poly:
        mask = Image.new("L", out.size, 0)
        ImageDraw.Draw(mask).polygon([(x - box[0], y - box[1]) for x, y in poly], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(0.6))
        out.putalpha(Image.fromarray(np.minimum(np.asarray(out.getchannel("A")), np.asarray(mask)).astype(np.uint8)))
    return out


def scaled(im, sx, sy=None):
    sy = sx if sy is None else sy
    return im.resize((max(1, round(im.width * sx)), max(1, round(im.height * sy))), Image.LANCZOS)


def put(dst, im, x, y):
    """Composites `im` over `dst` with its top left at (x, y), clipped to the canvas."""
    layer = Image.new("RGBA", dst.size, (0, 0, 0, 0))
    layer.paste(im, (round(x), round(y)), im)
    dst.alpha_composite(layer)
    return dst


def put_base(dst, im, cx, base_y):
    """Composites `im` with its bottom centre at (cx, base_y)."""
    return put(dst, im, cx - im.width / 2, base_y - im.height)


def recolour(im, lo, hi, to, sat_min=60, val_min=40, sat_mul=1.0, val_mul=1.0):
    """Moves every pixel whose hue is within lo..hi (PIL 0..255) and whose saturation and value pass the floors to hue
    `to`, scaling its saturation and value. Alpha untouched."""
    a = np.asarray(im.getchannel("A"))
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(np.float32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    sel = (h >= lo) & (h <= hi) & (s >= sat_min) & (v >= val_min)
    h = np.where(sel, to, h)
    s = np.where(sel, np.clip(s * sat_mul, 0, 255), s)
    v = np.where(sel, np.clip(v * val_mul, 0, 255), v)
    out = Image.fromarray(np.stack([h, s, v], -1).astype(np.uint8), "HSV").convert("RGB").convert("RGBA")
    out.putalpha(Image.fromarray(a))
    return out


def tint(im, rgb, amount):
    a = arr(im)
    a[..., :3] = a[..., :3] * (1 - amount) + np.array(rgb, np.float32) * amount
    return img(a)


def shade(im, k):
    a = arr(im)
    a[..., :3] *= k
    return img(a)


def glow(im, rgb, radius, strength):
    """Adds a soft halo of colour `rgb` round the bright, saturated pixels of `im`, only where `im` is painted (the
    transparent card margin stays clear: picking and shadows read the alpha)."""
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(np.float32)
    a = np.asarray(im.getchannel("A")).astype(np.float32) / 255
    src = Image.fromarray(((hsv[..., 2] / 255) ** 2 * (hsv[..., 1] / 255) * a * 255).astype(np.uint8))
    halo = np.asarray(src.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255 * strength
    out = arr(im)
    out[..., :3] += halo[..., None] * np.array(rgb, np.float32) * a[..., None]
    return img(out)


def texture(src, box, size, seed, dark=1.0, grime=True, soften=1.4):
    """A square `size` px tiled from the crop `box` of `src` (mirrored tiles, so no seam repeats), softened (its panel
    lines blur out) and worn with seeded grime."""
    tile = src.crop(box).convert("RGB").filter(ImageFilter.GaussianBlur(soften))
    out = Image.new("RGB", (size, size))
    for ty in range(0, size, tile.height):
        for tx in range(0, size, tile.width):
            t = tile
            if (tx // tile.width) % 2:
                t = t.transpose(Image.FLIP_LEFT_RIGHT)
            if (ty // tile.height) % 2:
                t = t.transpose(Image.FLIP_TOP_BOTTOM)
            out.paste(t, (tx, ty))
    if grime:
        rng = random.Random(seed)
        d = ImageDraw.Draw(out)
        for _ in range(size // 3):
            x, y, r = rng.randrange(size), rng.randrange(size), rng.randint(2, 6)
            d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(c * 0.72) for c in out.getpixel((x, y))))
        out = out.filter(ImageFilter.GaussianBlur(0.7))
    return shade(out.convert("RGBA"), dark)


def warp(face, origin, e1, e2, size):
    """Maps the square image `face` onto the parallelogram origin + s e1 + t e2 (s, t in 0..1) of a `size` canvas."""
    m = np.array([[e1[0], e2[0]], [e1[1], e2[1]]], np.float64)
    inv = np.linalg.inv(m)
    w, h = face.size
    # output (x, y) -> (s, t) = inv (p - origin) -> input (s w, t h)
    a, b = inv[0] * w
    d, e = inv[1] * h
    c = -(a * origin[0] + b * origin[1])
    f = -(d * origin[0] + e * origin[1])
    out = face.transform(size, Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC)
    mask = Image.new("L", size, 0)
    p = [origin, (origin[0] + e1[0], origin[1] + e1[1]), (origin[0] + e1[0] + e2[0], origin[1] + e1[1] + e2[1]), (origin[0] + e2[0], origin[1] + e2[1])]
    ImageDraw.Draw(mask).polygon(p, fill=255)
    out.putalpha(Image.fromarray(np.minimum(np.asarray(out.getchannel("A")), np.asarray(mask)).astype(np.uint8)))
    return out


def iso_box(a, b, height, top, left, right, shades=(1.0, 0.74, 0.52), faces=("top", "left", "right"), edge=0.55):
    """A box on the boards' ground plane: `a` px along the right-down axis, `b` along the left-down one, `height` tall,
    its faces painted with the square images `top`, `left`, `right` and shaded for the boards' light from the upper left
    (top, the left face, the right face). Dark creases on the box's edges. Returns an image (a + b) wide."""
    ky = SQUASH
    T = (b, 0.0)
    R = (b + a, a * ky)
    L = (0.0, b * ky)
    B = (a, (a + b) * ky)
    size = (round(a + b) + 1, round((a + b) * ky + height) + 2)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if "left" in faces:
        out.alpha_composite(warp(shade(left, shades[1]), (L[0], L[1]), (B[0] - L[0], B[1] - L[1]), (0, height), size))
    if "right" in faces:
        out.alpha_composite(warp(shade(right, shades[2]), (B[0], B[1]), (R[0] - B[0], R[1] - B[1]), (0, height), size))
    if "top" in faces:
        out.alpha_composite(warp(shade(top, shades[0]), T, (R[0] - T[0], R[1] - T[1]), (L[0] - T[0], L[1] - T[1]), size))
    d = ImageDraw.Draw(out)
    crease = (int(24 * edge), int(22 * edge), int(20 * edge), 200)
    if "left" in faces or "right" in faces:
        d.line([B, (B[0], B[1] + height)], fill=crease, width=1)
    if "top" in faces:
        hi = (255, 250, 236, 70)
        d.line([L, T, R], fill=hi, width=1)
        d.line([L, B, R], fill=crease, width=1)
    return out


def framed(tex, rgb_frame, inset, width=3, brace=False):
    """A crate face: `tex` with a darker frame `inset` px in (and a diagonal brace)."""
    out = tex.copy()
    d = ImageDraw.Draw(out)
    s = out.width
    d.rectangle((inset, inset, s - 1 - inset, s - 1 - inset), outline=rgb_frame + (255,), width=width)
    if brace:
        d.line([(inset, s - inset), (s - inset, inset)], fill=rgb_frame + (255,), width=width)
    return out.filter(ImageFilter.GaussianBlur(0.5))


def disk_slab(diam, top, height, side_tex, ky=None):
    """A round slab `diam` px wide on the ground plane: the top-down disk `top` (diam x diam) squashed by the boards'
    ground factor over a skirt `height` px tall painted with `side_tex`, darker to the right."""
    ky = SQUASH * 0.88 if ky is None else ky
    rx, ry = diam / 2, diam / 2 * ky
    w, h = diam + 2, round(diam * ky + height) + 3
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - rx - 1) / rx
    cy = ry + 1
    inside_skirt = (np.abs(nx) <= 1) & (yy >= cy) & (yy <= cy + height + ry * np.sqrt(np.clip(1 - nx ** 2, 0, 1)))
    st = arr(side_tex.resize((w, h)))
    lightx = np.clip(0.95 - 0.40 * (nx + 1), 0.35, 1)
    skirt = np.zeros((h, w, 4), np.float32)
    skirt[..., :3] = st[..., :3] * lightx[..., None] * 0.6
    skirt[..., 3] = np.where(inside_skirt, 255, 0)
    out = img(skirt)
    lid = scaled(top, 1.0, ky)
    out.alpha_composite(lid, (1, 1))
    return out


def dome(rx, glass, frame, elev=33.0, seed=0, lon=8, lat=3):
    """A painted glass dome `2 rx` wide on a metal ring, seen from the boards' camera (elevation `elev` degrees): glass
    tinted `glass` reflecting a pale sky toward its rim, a metal frame of `lon` meridians and `lat` parallels, a highlight
    from the upper left."""
    e = math.radians(elev)
    ring_h = max(4, round(rx * 0.16))
    w = 2 * rx + 8
    top_pad = 3
    h = round(rx * math.cos(e)) + round(rx * math.sin(e)) + ring_h + top_pad + 6
    cx = w / 2
    cy = top_pad + rx * math.cos(e)  # the screen point of the dome's base centre
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    out = np.zeros((h, w, 4), np.float32)
    L = np.array([-0.55, 0.75, 0.45])
    L /= np.linalg.norm(L)
    # the ring: a short metal cylinder under the dome (radius 1.04 rx, ring_h tall)
    rr = rx * 1.04
    for k in range(ring_h, -1, -1):
        ey = cy + k
        nx = (xx - cx) / rr
        ny = (yy - ey) / (rr * math.sin(e))
        on = (nx ** 2 + ny ** 2 <= 1) & (yy >= ey)
        lam = np.clip(0.75 - 0.45 * nx, 0.2, 1.0)
        col = np.array(frame, np.float32)[None, None, :] * (lam * (0.75 if k > 0 else 1.0))[..., None]
        out[..., :3] = np.where(on[..., None], col, out[..., :3])
        out[..., 3] = np.where(on, 255, out[..., 3])
    # the dome: ortho rays along the view direction onto a unit hemisphere (y up)
    sx = (xx - cx) / rx
    sy = -(yy - cy) / rx  # screen up from the base centre
    right = np.array([1.0, 0.0, 0.0])
    up_v = np.array([0.0, math.cos(e), -math.sin(e)])
    fwd = np.array([0.0, math.sin(e), math.cos(e)])
    rad = 1 - sx ** 2 - sy ** 2
    sz = np.sqrt(np.clip(rad, 0, 1))
    P = sx[..., None] * right + sy[..., None] * up_v + sz[..., None] * fwd
    on = (rad >= 0) & (P[..., 1] >= 0)
    n = P
    lam = np.clip((n @ L), 0, 1)
    facing = np.clip(n @ fwd, 0, 1)
    fres = (1 - facing) ** 2
    refl = n[..., 1] * 0.5 + 0.5
    sky = np.array([226, 240, 246], np.float32)
    g = np.array(glass, np.float32)
    col = g[None, None, :] * (0.55 + 0.55 * lam)[..., None]
    col = col * (1 - 0.55 * fres[..., None]) + sky * (0.55 * fres * refl)[..., None]
    hv = (L + fwd) / np.linalg.norm(L + fwd)
    spec = np.clip(n @ hv, 0, 1) ** 60
    col += 255 * 0.9 * spec[..., None]
    lat_a = np.arcsin(np.clip(P[..., 1], -1, 1))
    lon_a = np.arctan2(P[..., 0], P[..., 2])  # longitude about the dome's axis, 0 facing the camera
    fl = np.abs(((lon_a / math.pi * lon) % 1.0) - 0.5) > 0.44
    fa = (np.abs(((lat_a / (math.pi / 2) * (lat + 1)) % 1.0) - 0.5) > 0.42) & (lat_a > 0.12)
    cap = lat_a > 1.25
    frm = (fl | fa) & ~cap
    fcol = np.array(frame, np.float32)[None, None, :] * (0.45 + 0.7 * lam)[..., None]
    col = np.where(frm[..., None], fcol, col)
    rng = np.random.default_rng(seed)
    col *= (1 + rng.normal(0, 0.035, col.shape[:2]))[..., None]
    out[..., :3] = np.where(on[..., None], col, out[..., :3])
    out[..., 3] = np.where(on, 250, out[..., 3])
    im = img(out)
    im.putalpha(im.getchannel("A").filter(ImageFilter.GaussianBlur(0.5)))
    return im


def capsule_mask(im, box, rx_pad=0):
    """The crop `box` of `im` cut to the ellipse-capped column that fits it (a tank's own outline)."""
    out = im.crop(box)
    w, h = out.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    r = w / 2
    d.ellipse((0, 0, w - 1, r * 1.1), fill=255)
    d.rectangle((0, r * 0.55, w - 1, h - r * 0.6), fill=255)
    d.ellipse((0, h - r * 1.1, w - 1, h - 1), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    out.putalpha(Image.fromarray(np.minimum(np.asarray(out.getchannel("A")), np.asarray(mask)).astype(np.uint8)))
    return out


# the barracks hall without its crates (a factory floor, not a camp)
HALL_POLY = [(40, 174), (52, 122), (92, 92), (128, 64), (246, 64), (246, 230), (40, 230)]


def concrete(seed, dark=0.86):
    return texture(load("wall_v2"), (106, 122, 138, 166), 96, seed, dark)


def carapace(seed, dark=0.62):
    """The alien walls' dark ribbed metal."""
    return texture(load("alien_wall_v1"), (62, 140, 104, 166), 96, seed, dark)


def red_plate(seed, dark=0.8):
    """The alien walls' red carapace plate."""
    return texture(load("alien_wall_v1"), (140, 116, 166, 138), 96, seed, dark)


def deck(tex, cell, seed, seam=0.45, light=1.25):
    """`tex` laid as plates `cell` px square: dark seams, a lit upper-left lip on each plate, a bolt at each corner."""
    out = tex.copy()
    d = ImageDraw.Draw(out)
    n = out.width
    rng = random.Random(seed)
    for y0 in range(0, n, cell):
        for x0 in range(0, n, cell):
            k = rng.uniform(0.85, 1.12)
            box = (x0 + 1, y0 + 1, x0 + cell - 2, y0 + cell - 2)
            region = out.crop(box)
            out.paste(shade(region, k), box[:2])
            d.line([(x0, y0), (x0 + cell, y0)], fill=tuple(int(c * seam) for c in out.getpixel((x0 + 2, y0 + 2))[:3]) + (255,), width=2)
            d.line([(x0, y0), (x0, y0 + cell)], fill=tuple(int(c * seam) for c in out.getpixel((x0 + 2, y0 + 2))[:3]) + (255,), width=2)
            d.line([(x0 + 2, y0 + 2), (x0 + cell - 2, y0 + 2)], fill=tuple(min(255, int(c * light)) for c in out.getpixel((x0 + 4, y0 + 4))[:3]) + (255,), width=1)
            for bx, by in ((x0 + 4, y0 + 4), (x0 + cell - 5, y0 + cell - 5)):
                d.ellipse((bx - 1, by - 1, bx + 1, by + 1), fill=(30, 26, 26, 255))
    return out.filter(ImageFilter.GaussianBlur(0.4))


def cells_on(out, bx, by, a, b, cell, rows=(((0.2, 0.5, 0.8), 0.36), ((0.35, 0.65), 0.8)), lift=4):
    """Stands `cell` in rows on a plinth's top (drawn at bx, by): each row is (fractions along the long axis, its
    fraction across), back row first, so the bank reads front over back."""
    for fracs, across in rows:
        t = b * across
        for f in fracs:
            s = a * f
            out = put_base(out, cell, bx + b - t + s, by + (s + t) * SQUASH + lift)
    return out


def plinth(a, b, height, tex):
    return iso_box(a, b, height, tex, tex, tex)


# ---------------------------------------------------------------- drawn details (Task 9)
# The three kinds that still read as recolours (the vehicle factory: the barracks hall; the alien depot and battery: the
# human depot and battery laid out again in alien plate) take silhouettes of their own: a long low assembly hall with a
# bay door and a roof gantry, a clawed drum carrying twin capacitor coils, a relay yard of tall stores under a hoist.

HAZARD = (222, 176, 46)  # the human hazard yellow (the wall feet's stripes)
GLASS = (98, 134, 146)  # smoked factory glass: the human steel blue, kept under the accent saturation so amber stays the trim
GOLD = (255, 204, 84)  # the alien depot's signage: the alien glow pushed toward gold
LIME_GLOW = (170, 255, 90)  # the batteries' charge


def hazard(w, h, stripe=6, seed=0):
    """Yellow and black diagonal stripes `w` x `h`, worn."""
    im = Image.new("RGBA", (w, h), (36, 32, 26, 255))
    d = ImageDraw.Draw(im)
    for k in range(-h, w + h, 2 * stripe):
        d.polygon([(k, h), (k + stripe, h), (k + stripe + h, 0), (k + h, 0)], fill=HAZARD + (255,))
    rng = random.Random(seed)
    for _ in range(w * h // 40):
        x, y, r = rng.randrange(w), rng.randrange(h), rng.randint(0, 1)
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(c * 0.66) for c in im.getpixel((x, y))[:3]) + (255,))
    return im


def cladding(w, h, seed, rib=10, dark=0.9):
    """Ribbed steel cladding `w` x `h` in the walls' concrete: a dark and a lit line every `rib` px."""
    out = texture(load("wall_v2"), (106, 122, 138, 166), 96, seed, dark).resize((w, h), Image.BICUBIC)
    ribs = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ribs)
    for x in range(rib // 2, w, rib):
        d.line([(x, 0), (x, h)], fill=(64, 62, 56, 110), width=1)
        d.line([(x + 1, 0), (x + 1, h)], fill=(184, 180, 166, 90), width=1)
    out.alpha_composite(ribs)
    return out


def window_band(d, x0, y0, x1, y1, mull=18):
    """A strip of the human cyan glass between dark mullions, a sky glint along its top."""
    d.rectangle((x0, y0, x1, y1), fill=(46, 54, 56, 255))
    d.rectangle((x0 + 2, y0 + 2, x1 - 2, y1 - 2), fill=GLASS + (255,))
    d.line([(x0 + 2, y0 + 3), (x1 - 2, y0 + 3)], fill=(176, 232, 238, 255))
    for x in range(x0 + mull, x1 - 4, mull):
        d.line([(x, y0), (x, y1)], fill=(46, 54, 56, 255), width=2)


def iso_point(a, b, height, s, t, up=0.0):
    """The point at `s` along the long axis and `t` along the short one on top of an iso_box(a, b, height) (its own image
    coordinates), raised `up` px."""
    return (b + s * a - t * b, (s * a + t * b) * SQUASH - up)


def member(d, p, q, width, rgb, lit=1.0):
    """A steel member from `p` to `q`: a dark outline under a lit core."""
    d.line([p, q], fill=tuple(int(c * 0.42) for c in rgb) + (255,), width=width + 2)
    d.line([p, q], fill=tuple(min(255, int(c * lit)) for c in rgb) + (255,), width=width)


def soft_glow(size, centre, radius, rgb, alpha=110):
    """A round halo `radius` px about `centre` on a transparent `size` layer, its alpha under OPAQUE (128) so picking and
    the opaque box never count it."""
    layer = Image.new("RGBA", size, rgb + (0,))
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse((centre[0] - radius, centre[1] - radius, centre[0] + radius, centre[1] + radius), fill=alpha)
    layer.putalpha(m.filter(ImageFilter.GaussianBlur(radius * 0.45)))
    return layer


def arc(d, p, q, seed, sag=-10.0, steps=9, jitter=3.0):
    """A jagged electric arc from `p` to `q` bowed `sag` px (up when negative): the points of the polyline."""
    rng = random.Random(seed)
    pts = []
    for i in range(steps + 1):
        f = i / steps
        x = p[0] + (q[0] - p[0]) * f
        y = p[1] + (q[1] - p[1]) * f + sag * 4 * f * (1 - f)
        if 0 < i < steps:
            x += rng.uniform(-jitter, jitter)
            y += rng.uniform(-jitter, jitter)
        pts.append((x, y))
    return pts


# ---------------------------------------------------------------- human


def human_factory():
    """A long, low assembly hall (not the barracks' arched hall): ribbed cladding under a cyan window band, a wide bay
    door on its long face with hazard-striped posts and a tank rolling out down a striped ramp, skylights and a yellow
    gantry crane over the roof lifting a crate, an amber sign plate with a tank pictogram on its end."""
    tank = load("tank_v2")
    a, b, height = 170, 52, 56
    fw, fh = 2 * a, 2 * height
    left = cladding(fw, fh, 41)
    d = ImageDraw.Draw(left)
    window_band(d, 4, 8, fw - 4, 22)
    x0, x1, y0 = 70, 232, 34  # the bay door, in the face's pixels
    d.rectangle((x0 - 12, y0 - 7, x1 + 12, fh), fill=(78, 78, 72, 255))
    for y in range(y0, fh):  # the bay, lit from inside, darker toward the floor
        k = (y - y0) / (fh - y0)
        d.line([(x0, y), (x1, y)], fill=(int(96 - 50 * k), int(86 - 46 * k), int(68 - 36 * k), 255))
    for i in range(4):
        cx = x0 + 22 + i * (x1 - x0 - 44) / 3
        d.ellipse((cx - 5, y0 + 22, cx + 5, y0 + 27), fill=(255, 214, 140, 255))
    d.rectangle((x0, y0, x1, y0 + 16), fill=(132, 130, 120, 255))  # the door, rolled up
    for y in range(y0 + 3, y0 + 16, 3):
        d.line([(x0, y), (x1, y)], fill=(78, 76, 70, 255))
    left.paste(hazard(x1 - x0, 5, 4, 43), (x0, y0 + 16))
    left.paste(hazard(12, fh - y0 + 7, 5, 44), (x0 - 12, y0 - 7))
    left.paste(hazard(12, fh - y0 + 7, 5, 45), (x1, y0 - 7))
    right = cladding(2 * b, fh, 47)
    d = ImageDraw.Draw(right)
    window_band(d, 4, 8, 2 * b - 4, 22)
    d.rectangle((22, 34, 106, 80), fill=(58, 42, 20, 255))  # the sign: an amber plate, a tank stencilled on it
    d.rectangle((25, 37, 103, 77), fill=(214, 156, 50, 255))
    ink = (44, 32, 18, 255)
    d.rounded_rectangle((38, 62, 92, 70), 4, fill=ink)
    d.rectangle((42, 54, 88, 62), fill=ink)
    d.rectangle((52, 47, 72, 55), fill=ink)
    d.line([(70, 50), (98, 50)], fill=ink, width=3)
    roof = deck(texture(load("wall_v2"), (106, 122, 138, 166), 96, 49, 0.82), 24, 49).resize((fw, 2 * b))
    d = ImageDraw.Draw(roof)
    hall = iso_box(a, b, height, roof, left, right, shades=(1.0, 0.86, 0.6))
    out = canvas()
    hx = 128 - hall.width / 2 + 2
    hy = 230 - (round((a + b) * SQUASH) + height)
    # the ramp: striped concrete from the bay down to the ground, toward the viewer's left
    L = (hx, hy + b * SQUASH + height)
    B = (hx + a, hy + (a + b) * SQUASH + height)
    out_v = (-b, b * SQUASH)
    n = math.hypot(*out_v)
    out_v = (out_v[0] / n * 26, out_v[1] / n * 26)
    s0, s1 = (x0 - 4) / fw, (x1 + 4) / fw
    d0 = (L[0] + s0 * (B[0] - L[0]), L[1] + s0 * (B[1] - L[1]))
    d1 = (L[0] + s1 * (B[0] - L[0]), L[1] + s1 * (B[1] - L[1]))
    ramp = warp(framed(concrete(51, 0.8), (60, 58, 52), 1, 2).resize((96, 32)), (d0[0] + out_v[0], d0[1] + out_v[1]),
                (d1[0] - d0[0], d1[1] - d0[1]), (-out_v[0], -out_v[1]), (SIZE, SIZE))
    out.alpha_composite(ramp)
    out = put(out, hall, hx, hy)
    # the tank rolling out: its front half, fading into the dark bay
    nose = part(tank, (6, 92, 136, 212))
    nose = scaled(nose, 0.4)
    na = arr(nose)
    fade = np.clip(1.6 - np.linspace(0, 1, nose.width) * 1.4, 0.35, 1.0)
    na[..., :3] *= fade[None, :, None]
    nose = img(na)
    door_mid = 0.5 * (x0 + x1) / fw
    foot = (L[0] + door_mid * (B[0] - L[0]), L[1] + door_mid * (B[1] - L[1]))
    clip = Image.new("L", (SIZE, SIZE), 0)
    top_y = (fh - y0 - 16 - 5) / fh * height
    q = [(d0[0] + 6, d0[1] - top_y), (d1[0] - 6, d1[1] - top_y), (d1[0] - 6, d1[1] + 20), (d0[0] + 6, d0[1] + 20)]
    ImageDraw.Draw(clip).polygon(q, fill=255)
    layer = put(canvas(), nose, foot[0] - nose.width * 0.62, foot[1] + 9 - nose.height)
    layer.putalpha(Image.fromarray(np.minimum(np.asarray(layer.getchannel("A")), np.asarray(clip)).astype(np.uint8)))
    out.alpha_composite(layer)
    # a slim exhaust stack (the refinery's) behind the hall's far end
    stack = scaled(part(load("refinery_v2"), (156, 12, 190, 96), [(156, 96), (156, 24), (166, 12), (182, 12), (190, 24), (190, 96)]), 0.8, 0.74)
    sp = iso_point(a, b, height, 0.05, 0.12)
    stack_layer = put_base(canvas(), stack, hx + sp[0], hy + sp[1] + 14)
    stack_layer.alpha_composite(out)
    out = stack_layer
    # roof plant: two vent boxes at the hall's far end
    vent_tex = concrete(53, 0.7)
    vent = iso_box(16, 14, 9, vent_tex, vent_tex, vent_tex)
    for s, t in ((0.12, 0.3), (0.12, 0.7)):
        p = iso_point(a, b, height, s, t)
        out = put_base(out, vent, hx + p[0], hy + p[1] + 9)
    # a saw-tooth roof over the shop floor: each tooth rises toward the viewer's right to a north-light glass face
    tooth_roof = deck(texture(load("wall_v2"), (106, 122, 138, 166), 96, 57, 0.86), 16, 57)
    glass = Image.new("RGBA", (64, 32), (54, 60, 58, 255))
    gd = ImageDraw.Draw(glass)
    gd.rectangle((2, 3, 61, 28), fill=GLASS + (255,))
    for x in range(2, 62, 10):
        gd.line([(x, 3), (x, 28)], fill=(54, 60, 58, 255), width=2)
    gd.line([(2, 4), (61, 4)], fill=(176, 232, 238, 255))
    gable = cladding(32, 32, 59)
    w_t, ht = 0.17, 15
    for i in range(4):
        s0 = 0.24 + i * w_t
        s1 = s0 + w_t

        def at(s_, t_, up=0.0):
            q = iso_point(a, b, height, s_, t_, up)
            return (hx + q[0], hy + q[1])
        o, sr, tl = at(s0, 0), at(s1, 0, ht), at(s0, 1)
        out.alpha_composite(warp(shade(tooth_roof, 1.02), o, (sr[0] - o[0], sr[1] - o[1]), (tl[0] - o[0], tl[1] - o[1]), (SIZE, SIZE)))
        g0, g1 = at(s1, 0, ht), at(s1, 1, ht)
        out.alpha_composite(warp(shade(glass, 0.62), g0, (g1[0] - g0[0], g1[1] - g0[1]), (0, ht), (SIZE, SIZE)))
        tri = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(tri).polygon([at(s0, 1), at(s1, 1, ht), at(s1, 1)], fill=255)
        side = warp(shade(gable, 0.86), at(s0, 1), (at(s1, 1)[0] - at(s0, 1)[0], at(s1, 1)[1] - at(s0, 1)[1]), (0, -ht), (SIZE, SIZE))
        side.putalpha(Image.fromarray(np.minimum(np.asarray(side.getchannel("A")), np.asarray(tri)).astype(np.uint8)))
        out.alpha_composite(side)
        ImageDraw.Draw(out).line([at(s0, 1), at(s1, 1, ht), g0], fill=(232, 228, 214, 120), width=1)
    # the gantry crane: two A-frames on the roof's edges near its near end, a beam across, a trolley lifting a crate
    d = ImageDraw.Draw(out)
    lift = 64
    s_g = 0.76
    feet = []
    for t in (0.04, 0.96):
        f0 = iso_point(a, b, height, s_g - 0.07, t)
        f1 = iso_point(a, b, height, s_g + 0.07, t)
        apex = iso_point(a, b, height, s_g, t, lift)
        feet.append(((hx + f0[0], hy + f0[1]), (hx + f1[0], hy + f1[1]), (hx + apex[0], hy + apex[1])))
    back, front = feet[0], feet[1]
    member(d, back[0], back[2], 3, HAZARD, 0.72)
    member(d, back[1], back[2], 3, HAZARD, 0.72)
    member(d, back[2], front[2], 4, HAZARD, 1.0)
    tr = (back[2][0] + 0.45 * (front[2][0] - back[2][0]), back[2][1] + 0.45 * (front[2][1] - back[2][1]))
    crate = iso_box(14, 14, 11, framed(tint(concrete(55, 0.9), (112, 108, 62), 0.62), (54, 50, 30), 4, 3, brace=True),
                    framed(tint(concrete(55, 0.9), (112, 108, 62), 0.62), (54, 50, 30), 4, 3, brace=True),
                    framed(tint(concrete(55, 0.9), (112, 108, 62), 0.62), (54, 50, 30), 4, 3, brace=True))
    hook = (tr[0], tr[1] + 24)
    d.line([tr, hook], fill=(40, 38, 34, 255), width=1)
    out = put_base(out, crate, hook[0], hook[1] + crate.height)
    d = ImageDraw.Draw(out)
    d.rectangle((tr[0] - 5, tr[1] - 3, tr[0] + 5, tr[1] + 3), fill=(60, 56, 46, 255))
    member(d, front[0], front[2], 3, HAZARD, 1.05)
    member(d, front[1], front[2], 3, HAZARD, 1.05)
    return out


def human_airfield():
    bar, cc = load("barracks_v2"), load("command_center_v2")
    out = canvas()
    top = concrete(3, 0.80).resize((200, 200))
    top = top.crop((2, 2, 198, 198))
    d = ImageDraw.Draw(top)
    paint_y, paint_w = (196, 156, 52, 235), (206, 204, 190, 235)
    d.ellipse((28, 28, 168, 168), outline=paint_y, width=8)
    d.rectangle((70, 62, 85, 134), fill=paint_w)
    d.rectangle((111, 62, 126, 134), fill=paint_w)
    d.rectangle((85, 91, 111, 105), fill=paint_w)
    for k in range(12):  # rim lights
        t = k * math.pi / 6
        x, y = 98 + 86 * math.cos(t), 98 + 86 * math.sin(t)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(120, 226, 236, 255))
    rng = random.Random(23)
    for _ in range(140):  # wear over the paint
        x, y, r = rng.randrange(196), rng.randrange(196), rng.randint(1, 4)
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(c * 0.78) for c in top.getpixel((x, y))[:3]) + (255,))
    top = top.filter(ImageFilter.GaussianBlur(0.6))
    mask = Image.new("L", top.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 195, 195), fill=255)
    top.putalpha(mask)
    pad = disk_slab(196, top, 10, concrete(4, 0.7))
    # rear: a small hangar (the barracks hall) and the CC's radar dish, their feet behind the pad's far rim
    hangar = scaled(part(bar, (40, 60, 246, 230), HALL_POLY), 0.56)
    dish = part(cc, (94, 56, 134, 108))
    pad_top = CONTACT + 18 - pad.height
    out = put(out, dish, 34, pad_top + 30 - dish.height)
    out = put(out, hangar, 120, pad_top + 34 - hangar.height)
    out = put(out, pad, 128 - pad.width / 2, pad_top)
    return out


def _plant_column(pp):
    return part(pp, (96, 18, 186, 150), [(96, 150), (96, 60), (120, 16), (162, 16), (186, 60), (186, 150)])


def human_battery():
    pp = load("power_plant_v2")
    out = canvas()
    cell = recolour(_plant_column(pp), CYAN - 26, CYAN + 26, LIME, sat_min=35, val_min=40, sat_mul=1.6, val_mul=1.12)
    cell = glow(scaled(cell, 0.46), (170, 255, 90), 3, 0.5)
    a, b = 120, 84
    base = plinth(a, b, 18, concrete(5, 0.92))
    bx, by = 128 - base.width / 2, CONTACT + 18 - base.height
    out = put(out, base, bx, by)
    return cells_on(out, bx, by, a, b, cell)


def human_antimatter():
    pp = load("power_plant_v2")
    plant = recolour(pp, CYAN - 26, CYAN + 26, VIOLET, sat_min=35, val_min=40, sat_mul=1.7, val_mul=1.25)
    col = _plant_column(plant)
    tall = scaled(col, 1.04, 1.46)
    full = canvas()
    full = put(full, plant, 0, 0)
    full = put(full, tall, 141 - tall.width / 2, 150 - tall.height)  # the stretched column hides the plant's own
    full = glow(full, (200, 120, 255), 6, 0.7)
    k = 0.86  # shrink about the contact line so the taller column fits the card
    return put(canvas(), scaled(full, k), 128 - 128 * k, CONTACT - CONTACT * k)


def human_depot():
    pp, cc = load("power_plant_v2"), load("command_center_v2")
    out = canvas()
    apron = plinth(132, 112, 7, concrete(7, 0.74))
    ax, ay = 128 - apron.width / 2, CONTACT + 14 - apron.height
    out = put(out, apron, ax, ay)
    tank = capsule_mask(cc, (202, 100, 236, 154))
    tank = scaled(tank, 1.25)
    # fuel tanks at the back, then crate stacks
    out = put_base(out, tank, 108, ay + 52)
    out = put_base(out, tank, 146, ay + 50)
    out = put_base(out, scaled(tank, 0.9), 186, ay + 74)
    olive = tint(concrete(9, 0.9), (112, 108, 62), 0.62)
    tan = tint(concrete(11, 0.95), (150, 122, 80), 0.6)
    crate_o = framed(olive, (54, 50, 30), 4, 3, brace=True)
    crate_t = framed(tan, (82, 62, 38), 4, 3)
    big = iso_box(26, 26, 22, crate_o, crate_o, crate_o)
    small = iso_box(20, 20, 17, crate_t, crate_t, crate_t)
    for x, y, c in [(66, 172, big), (92, 186, big), (78, 168, small), (162, 196, small), (186, 182, big), (126, 200, small), (176, 205, small)]:
        out = put_base(out, c, x, y)
    out = put_base(out, small, 74, 150)  # the stack's top crate
    return out


def human_lab():
    cc = load("command_center_v2")
    out = canvas()
    body = part(cc, (14, 108, 246, 240), [(14, 240), (14, 140), (60, 118), (96, 108), (196, 108), (246, 130), (246, 240)])
    body = scaled(body, 0.88)
    by = CONTACT + 20 - body.height
    out = put(out, part(cc, (94, 56, 134, 108)), 30, by + 22 - 52)  # the radar dish, its foot behind the body
    aerial = part(cc, (172, 54, 196, 112))
    out = put(out, aerial, 190, by + 18 - aerial.height)
    out = put(out, body, 128 - body.width / 2, by)
    glass = dome(50, (84, 172, 190), (150, 156, 160), seed=31)
    out = put(out, glass, 128 - glass.width / 2 + 4, by + 26 - glass.height)
    return out


# ---------------------------------------------------------------- alien


def alien_factory():
    bar, ref = load("alien_barracks_v1"), load("alien_refinery_v1")
    out = canvas()
    # the refinery's glowing pods and chimney behind the right of the hall, their cut edge hidden by it
    pods = part(ref, (140, 12, 238, 192), [(140, 192), (140, 60), (146, 12), (162, 12), (168, 60), (238, 92), (238, 192)])
    out = put(out, pods, 150, CONTACT - 16 - pods.height)
    out = put(out, pods.transpose(Image.FLIP_LEFT_RIGHT), 6, CONTACT - 36 - pods.height)
    hall = scaled(part(bar, (16, 14, 246, 230)), 0.92, 0.80)
    out = put(out, hall, 128 - hall.width / 2 - 4, CONTACT + 10 - hall.height)
    return glow(out, (255, 150, 40), 4, 0.25)


def alien_airfield():
    bar, ref = load("alien_barracks_v1"), load("alien_refinery_v1")
    out = canvas()
    top = deck(red_plate(13, 0.55), 24, 13).resize((200, 200)).crop((2, 2, 198, 198))
    d = ImageDraw.Draw(top)
    d.ellipse((24, 24, 172, 172), outline=(255, 146, 38, 255), width=7)
    d.ellipse((64, 64, 132, 132), outline=(255, 186, 70, 255), width=5)
    for k in range(10):
        t = k * math.pi / 5 + 0.3
        x, y = 98 + 86 * math.cos(t), 98 + 86 * math.sin(t)
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(255, 168, 48, 255))
    top = top.filter(ImageFilter.GaussianBlur(0.6))
    mask = Image.new("L", top.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 195, 195), fill=255)
    top.putalpha(mask)
    pad = disk_slab(196, top, 11, carapace(14, 1.4))
    hangar = scaled(part(bar, (16, 14, 246, 230)), 0.50)
    chimney = part(ref, (138, 12, 166, 96))
    pad_top = CONTACT + 18 - pad.height
    out = put(out, chimney, 48, pad_top + 30 - chimney.height)
    out = put(out, hangar, 118, pad_top + 36 - hangar.height)
    out = put(out, pad, 128 - pad.width / 2, pad_top)
    return glow(out, (255, 150, 40), 5, 0.3)


def _alien_core(pp):
    return part(pp, (90, 12, 202, 150), [(98, 150), (92, 60), (130, 12), (160, 12), (196, 40), (201, 70), (190, 110), (186, 150)])


def _fin(diam, seed, thick=4):
    """A capacitor fin: a round red carapace plate `diam` px across with a bone rim, `thick` px deep."""
    lid = deck(red_plate(seed, 0.7), 12, seed).resize((diam, diam))
    d = ImageDraw.Draw(lid)
    d.ellipse((0, 0, diam - 1, diam - 1), outline=(214, 198, 172, 255), width=max(2, diam // 12))
    m = Image.new("L", (diam, diam), 0)
    ImageDraw.Draw(m).ellipse((0, 0, diam - 1, diam - 1), fill=255)
    lid.putalpha(m)
    return disk_slab(diam, lid, thick, carapace(seed + 1, 1.2))


def _coil(height, seed):
    """A capacitor coil `height` px tall: the power plant's glass vial turned lime and stretched into a column, three
    carapace fins round it (back half behind the column, front half over it), a lime orb on top. Returns the image and
    the orb's centre in it."""
    pp = load("alien_power_plant_v1")
    vial = recolour(part(pp, (192, 84, 218, 126)), 8, 44, LIME, sat_min=60, val_min=60, sat_mul=1.1, val_mul=1.15)
    col = scaled(vial, 1.25, height / 42)
    w = 52
    out = Image.new("RGBA", (w, height + 26), (0, 0, 0, 0))
    base_y = out.height
    cx = w / 2
    fins = [(0.18, 50), (0.45, 42), (0.72, 34), (1.0, 22)]
    imgs = [_fin(dm, seed + i) for i, (_, dm) in enumerate(fins)]
    for (f, dm), fin in zip(fins, imgs):  # the backs
        y = base_y - f * height
        back = fin.crop((0, 0, fin.width, fin.height // 2 + 1))
        out = put(out, back, cx - fin.width / 2, y - fin.height / 2)
    out = put_base(out, col, cx, base_y)
    for (f, dm), fin in zip(fins, imgs):  # the fronts
        y = base_y - f * height
        front = fin.crop((0, fin.height // 2 - 1, fin.width, fin.height))
        out = put(out, front, cx - fin.width / 2, y - fin.height / 2 + fin.height // 2 - 1)
    orb_c = (cx, base_y - height - 9)
    yy, xx = np.mgrid[0:out.height, 0:w].astype(np.float32)
    r = 9.0
    dist = np.hypot(xx - orb_c[0] + 2, yy - orb_c[1] + 2) / r
    on = np.hypot(xx - orb_c[0], yy - orb_c[1]) <= r
    core = np.clip(1.1 - dist, 0, 1)[..., None]
    col_rgb = np.array(LIME_GLOW, np.float32) * (0.55 + 0.45 * core) + 255 * core ** 3 * 0.8
    o = arr(out)
    o[..., :3] = np.where(on[..., None], col_rgb, o[..., :3])
    o[..., 3] = np.where(on, 255, o[..., 3])
    return img(o), orb_c


def alien_battery():
    """A clawed drum (the alien gun turret's base without its gun) carrying twin capacitor coils, an arc of charge
    jumping between their orbs: two spires and a gap, where the power plant is one bulb in claws."""
    tur = load("alien_gun_turret_v1")
    out = canvas()
    drum = part(tur, (38, 108, 248, 224), [(38, 224), (38, 150), (90, 122), (100, 108), (150, 108), (166, 122), (248, 150), (248, 224)])
    drum = recolour(drum, 12, 44, 64, sat_min=110, val_min=110)  # its orange charge slots carry the coils' lime
    dx, dy = 128 - drum.width / 2 + 3, 235 - 2 - drum.height + 6
    deck_c = (128 + 10, dy + 26)  # the drum top's centre on the canvas
    coils = []
    for i, (ox, h) in enumerate(((-30, 92), (30, 104))):
        coil, orb = _coil(h, 61 + 7 * i)
        coils.append((coil, deck_c[0] + ox, deck_c[1] + 8 - 8 * i, orb))
    halo = canvas()
    for coil, x, y, orb in coils:
        halo.alpha_composite(soft_glow((SIZE, SIZE), (x - coil.width / 2 + orb[0], y - coil.height + orb[1]), 20, LIME_GLOW, 120))
    out.alpha_composite(halo)
    out = put(out, drum, dx, dy)
    for coil, x, y, _ in (coils[1], coils[0]):  # the back coil first
        out = put_base(out, coil, x, y)
    # the arc between the orbs
    p = [(x - c.width / 2 + o[0], y - c.height + o[1]) for c, x, y, o in coils]
    d = ImageDraw.Draw(out)
    for seed, sag, width in ((71, -16.0, 2), (72, -6.0, 1)):
        pts = arc(d, p[0], p[1], seed, sag)
        glow_l = canvas()
        ImageDraw.Draw(glow_l).line(pts, fill=LIME_GLOW + (120,), width=6)
        out.alpha_composite(glow_l.filter(ImageFilter.GaussianBlur(1.8)))
        d = ImageDraw.Draw(out)
        d.line(pts, fill=(226, 255, 196, 255), width=width)
    return glow(out, (140, 255, 80), 3, 0.35)


def alien_antimatter():
    pp = part(load("alien_power_plant_v1"), (0, 0, 256, 226))  # the stray fragments under the plant stay out
    pp = recolour(pp, 8, 44, VIOLET, sat_min=90, val_min=90, sat_mul=1.0, val_mul=1.1)
    col = part(pp, (88, 8, 200, 152), [(88, 152), (88, 60), (124, 8), (166, 8), (200, 60), (200, 152)])
    tall = scaled(col, 1.0, 1.42)
    full = canvas()
    full = put(full, pp, 0, 0)
    full = put(full, tall, 88, 152 - tall.height)
    full = glow(full, (200, 120, 255), 6, 0.7)
    k = 0.86
    return put(canvas(), scaled(full, k), 128 - 128 * k, CONTACT - CONTACT * k)


def _cargo_cell(seed, size=28, height=22):
    """A carapace cargo cell: red plate lid with a bone frame, dark ribbed sides, a gold seam round its waist."""
    lid = framed(red_plate(seed, 0.95), (214, 196, 168), 3, 2)
    side = framed(carapace(seed + 1, 1.5), (120, 96, 86), 3, 2)
    cell = iso_box(size, size, height, lid, side, side, shades=(1.0, 0.8, 0.6))
    d = ImageDraw.Draw(cell)
    ky = SQUASH
    y = height * 0.55
    d.line([(0, size * ky + y), (size, 2 * size * ky + y), (2 * size, size * ky + y)], fill=GOLD + (255,), width=1)
    return cell


def _claw_jib(pp):
    """The hoist's arm: the power plant's tall left claw laid over sideways, its tip curling down."""
    claw = part(pp, (54, 40, 104, 162), [(54, 162), (54, 96), (70, 56), (96, 40), (104, 46), (84, 74), (74, 110), (78, 162)])
    return claw.rotate(-72, resample=Image.BICUBIC, expand=True)


def alien_depot():
    """A relay yard, not a slab of the human depot: three tall cylindrical stores (the refinery's pods drawn out) at the
    back carrying a gold glyph beacon, a hoist mast whose claw arm swings a cage of crystal over the yard, carapace cargo
    cells stacked two high at the front with gold seams, gold chevrons along the apron's edge."""
    ref, harv, pp = load("alien_refinery_v1"), load("alien_harvester_v1"), load("alien_power_plant_v1")
    out = canvas()
    a, b = 124, 104
    apron = iso_box(a, b, 8, deck(red_plate(19, 0.55), 20, 19), carapace(20, 1.1), carapace(20, 1.1))
    ax, ay = 128 - apron.width / 2, 231 - apron.height
    out = put(out, apron, ax, ay)
    d = ImageDraw.Draw(out)
    for k in range(9):  # a dashed gold guide line inside the apron's near edge
        p0 = iso_point(a, b, 8, 0.08 + 0.1 * k, 0.9)
        p1 = iso_point(a, b, 8, 0.13 + 0.1 * k, 0.9)
        d.line([(ax + p0[0], ay + p0[1]), (ax + p1[0], ay + p1[1])], fill=GOLD + (230,), width=2)

    def on_deck(s_, t_):
        p = iso_point(a, b, 8, s_, t_)
        return ax + p[0], ay + p[1]
    # the stores at the back left, the tallest furthest back
    pod = capsule_mask(ref, (196, 126, 234, 190))
    pod2 = capsule_mask(ref, (158, 96, 198, 160))
    stores = [(0.10, 0.20, scaled(pod, 1.25, 1.75)), (0.30, 0.16, scaled(pod2, 1.0, 1.4)), (0.08, 0.52, scaled(pod, 1.05, 1.3))]
    beacon = None
    for k, (s_, t_, st) in enumerate(stores):
        x, y = on_deck(s_, t_)
        out = put_base(out, st, x, y + 6)
        if k == 0:
            beacon = (x - 3, y + 6 - st.height * 0.62)
    d = ImageDraw.Draw(out)
    gx, gy = beacon  # a gold glyph panel on the tallest store
    d.rounded_rectangle((gx - 6, gy - 16, gx + 6, gy + 16), 3, fill=(48, 28, 20, 255))
    for j in range(4):
        yy = gy - 11 + j * 7
        d.line([(gx - 3, yy), (gx + 3 - 3 * (j % 2), yy)], fill=GOLD + (255,), width=2)
        d.ellipse((gx + 1, yy + 2, gx + 3, yy + 4), fill=GOLD + (255,))
    # the hoist: a mast at the back right, the claw arm reaching back over the yard
    mast = scaled(part(ref, (140, 14, 164, 84)), 1.2, 1.75)
    mx, my = on_deck(0.86, 0.10)
    jib = scaled(_claw_jib(pp), 0.56)
    out = put(out, jib, mx - jib.width + 10, my - mast.height - 10)
    out = put_base(out, mast, mx, my)
    tip = (mx - jib.width + 16, my - mast.height - 10 + jib.height * 0.72)
    hang = (tip[0], tip[1] + 22)
    d = ImageDraw.Draw(out)
    d.line([tip, hang], fill=(28, 22, 20, 255), width=1)
    crystals = part(harv, (86, 56, 154, 118), [(86, 118), (92, 78), (120, 54), (154, 70), (150, 118)])
    cage = scaled(crystals, 0.5)
    out = put_base(out, cage, hang[0], hang[1] + 6 + cage.height)
    d = ImageDraw.Draw(out)
    cx0, cx1 = hang[0] - cage.width / 2 - 2, hang[0] + cage.width / 2 + 2
    bottom = hang[1] + 8 + cage.height
    for x in (cx0, hang[0], cx1):
        d.line([hang, (x, hang[1] + 6)], fill=(36, 26, 24, 255))
        d.line([(x, hang[1] + 6), (x, bottom)], fill=(150, 124, 108, 255))
    d.line([(cx0, hang[1] + 6), (cx1, hang[1] + 6)], fill=(150, 124, 108, 255), width=2)
    d.line([(cx0, bottom), (cx1, bottom)], fill=(150, 124, 108, 255), width=2)
    # cargo cells stacked two high at the front right, back to front
    cells = [(0.58, 0.58, 0), (0.80, 0.58, 0), (0.58, 0.84, 0), (0.80, 0.84, 0), (0.69, 0.71, 22)]
    for k, (s_, t_, up) in enumerate(sorted(cells, key=lambda c: (c[2], c[0] + c[1]))):
        x, y = on_deck(s_, t_)
        cell = _cargo_cell(101 + k)
        out = put_base(out, cell, x, y - up + 15)
    return glow(out, (255, 176, 60), 4, 0.25)


def alien_lab():
    cc, ref = load("alien_command_center_v1"), load("alien_refinery_v1")
    out = canvas()
    body = part(cc, (40, 92, 242, 230), [(40, 230), (40, 92), (80, 92), (98, 128), (160, 128), (182, 92), (242, 92), (242, 230)])
    body = scaled(body, 0.92)
    by = CONTACT + 10 - body.height
    mast = recolour(part(ref, (138, 12, 166, 96)), 8, 44, CYAN, sat_min=90, val_min=90, sat_mul=0.8, val_mul=1.1)
    out = put(out, mast, 176, by + 30 - mast.height)
    out = put(out, body, 128 - body.width / 2 + 2, by)
    glass = dome(46, (90, 184, 200), (96, 44, 46), seed=37)
    out = put(out, glass, 128 - glass.width / 2 + 2, by + 40 - glass.height)
    return out


VARIANTS = {
    "vehicle_factory_v1": human_factory,
    "airfield_v1": human_airfield,
    "battery_v1": human_battery,
    "antimatter_plant_v1": human_antimatter,
    "supply_depot_v1": human_depot,
    "research_lab_v1": human_lab,
    "alien_vehicle_factory_v1": alien_factory,
    "alien_airfield_v1": alien_airfield,
    "alien_battery_v1": alien_battery,
    "alien_antimatter_plant_v1": alien_antimatter,
    "alien_supply_depot_v1": alien_depot,
    "alien_research_lab_v1": alien_lab,
}
# variant -> the board sprite the kind drew before (what it must no longer look like)
SOURCES = {
    "vehicle_factory_v1": "barracks_v2", "airfield_v1": "barracks_v2", "battery_v1": "power_plant_v2",
    "antimatter_plant_v1": "power_plant_v2", "supply_depot_v1": "refinery_v2", "research_lab_v1": "capital_v1",
    "alien_vehicle_factory_v1": "alien_barracks_v1", "alien_airfield_v1": "alien_barracks_v1",
    "alien_battery_v1": "alien_power_plant_v1", "alien_antimatter_plant_v1": "alien_power_plant_v1",
    "alien_supply_depot_v1": "alien_refinery_v1", "alien_research_lab_v1": "alien_capital_v1",
}


def build(out_dir):
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    written = {}
    for name, fn in VARIANTS.items():
        im = fn()
        assert im.size == (SIZE, SIZE), name
        path = out_dir / (name + ".png")
        im.save(path)
        written[name] = path
    return written


if __name__ == "__main__":
    for p in build(OUT).values():
        print(p)
