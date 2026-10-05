"""Bake the Kestrel combat effect atlas (plan 2026-10-05-kestrel-combat-motion-fx, Task 2): flipbook frames for the
pooled effect cards of godot3d/scripts/world/world_fx.gd. Deterministic: hashed value noise and fixed seeds only.
Usage: python3 tools/ui/build_fx_atlas.py  (writes godot3d/assets/world/fx/fx_atlas.png)

Layout: 128 px cells, 8 columns, two bands of four rows (band 0 human amber fire, band 1 alien teal and magenta plasma):
  row 0  fireball, 8 frames (a turbulent hot core cooling through orange to a dark smoke edge)
  row 1  smoke puff, 8 frames (a soft billow that grows and thins; the cards tint it per use: smoke, dust)
  row 2  flash (muzzle star), sparks, debris, ember, glow, ring (dust), rubble (a burning decal two cells wide)
  row 3  shot sprites (Task 3), each a vertical streak with its head at the top of the cell (a card stretches it and
         turns it along the shot): tracer (a thin bright streak), shell (a hot slug with a short glowing trail), bolt (a
         fat plasma lozenge with a wispy tail); the rest of the row is empty

Every texel is premultiplied: colour = smoke colour x alpha + emission. The effect shader blends ONE, ONE_MINUS_SRC_ALPHA,
so a texel with alpha 0 adds light (fire, flash, sparks) and a texel with alpha 1 covers (smoke, debris). The import keeps
the colour of fully transparent texels (fix_alpha_border off), or the emission would be lost."""
import math, pathlib, random
import numpy as np
from PIL import Image, ImageDraw

REPO = pathlib.Path(__file__).absolute().parents[2]
OUT = REPO / "godot3d/assets/world/fx/fx_atlas.png"
CELL = 128
COLS = 8
BAND_ROWS = 4
FIREBALL_FRAMES = 8
SMOKE_FRAMES = 8
SINGLES = {"flash": (0, 1), "sparks": (1, 1), "debris": (2, 1), "ember": (3, 1), "glow": (4, 1), "ring": (5, 1), "rubble": (6, 2)}
SHOTS = {"tracer": 0, "shell": 1, "bolt": 2}  # row 3 columns
BORDER = 3  # outer pixels of every cell left empty

# heat (0..1) -> emission colour, per band
RAMPS = (
    [(0.0, (50, 12, 4)), (0.22, (150, 38, 8)), (0.42, (235, 100, 18)), (0.62, (255, 165, 45)), (0.82, (255, 222, 130)), (1.0, (255, 252, 230))],
    [(0.0, (40, 6, 56)), (0.22, (140, 26, 160)), (0.42, (225, 60, 215)), (0.62, (70, 205, 225)), (0.82, (150, 250, 240)), (1.0, (238, 255, 255))],
)
SMOKE_DARK = ((52, 46, 42), (46, 38, 58))  # the fireball's own smoke edge
SMOKE_LIGHT = ((176, 170, 162), (170, 162, 180))  # the smoke puff, lit from above
DEBRIS = ((52, 47, 42), (48, 40, 62))
SEEDS = (101, 211)


def _hash(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return h.astype(np.float64) / 4294967295.0


def vnoise(x, y, seed):
    x0, y0 = np.floor(x), np.floor(y)
    fx, fy = x - x0, y - y0
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    ix, iy = x0.astype(np.int64), y0.astype(np.int64)
    n00, n10 = _hash(ix, iy, seed), _hash(ix + 1, iy, seed)
    n01, n11 = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return (n00 + (n10 - n00) * sx) * (1 - sy) + (n01 + (n11 - n01) * sx) * sy


def fbm(x, y, seed, octaves=5):
    total, amp, freq, norm = 0.0, 0.5, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * vnoise(x * freq, y * freq, seed + o * 101)
        norm += amp
        amp *= 0.5
        freq *= 2.03
    return total / norm


def warped(x, y, seed, strength=1.6):
    w1 = fbm(x + 5.2, y + 1.3, seed + 7, 4)
    w2 = fbm(x - 3.1, y + 8.7, seed + 13, 4)
    return fbm(x + strength * (w1 - 0.5) * 2, y + strength * (w2 - 0.5) * 2, seed, 5)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(heat, band):
    stops = RAMPS[band]
    out = np.zeros(heat.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(heat, [s[0] for s in stops], [s[1][c] for s in stops])
    return out / 255.0


def grid(w=CELL, h=CELL):
    """Pixel centres in [-1, 1] (x right, y DOWN as in the image), the vertical axis scaled to keep pixels square."""
    xs = (np.arange(w) + 0.5) / (w / 2) - 1
    ys = ((np.arange(h) + 0.5) / (h / 2) - 1) * (h / w) * (w / h)
    return np.meshgrid(xs, ys)


def border_mask(w=CELL, h=CELL):
    xs, ys = np.arange(w), np.arange(h)
    d = np.minimum.outer(np.minimum(ys, h - 1 - ys), np.minimum(xs, w - 1 - xs)).astype(float)
    return np.clip((d - (BORDER - 0.5)) / 8.0, 0.0, 1.0)


def pack(cover_rgb, alpha, emission, w=CELL, h=CELL):
    """Premultiplied RGBA uint8: cover_rgb (0..1, straight) x alpha + emission (0..1), inside the empty border."""
    m = border_mask(w, h)
    a = np.clip(alpha, 0, 1) * m
    rgb = np.clip(cover_rgb * a[..., None] + emission * m[..., None], 0, 1)
    a8 = np.round(a * 255).astype(np.uint8)
    rgb8 = np.round(rgb * 255).astype(np.uint8)
    glow = emission.max(axis=2) * m > 1.5 / 255
    rgb8 = np.where(glow[..., None], rgb8, np.minimum(rgb8, a8[..., None]))  # covered texels stay premultiplied
    return np.dstack([rgb8, a8])


def fireball(t, band):
    x, y = grid()
    seed = SEEDS[band] + 3
    y = y + 0.12 * t  # the ball climbs as it burns
    r = np.sqrt(x * x + (y * 1.06) ** 2)
    a = np.arctan2(y, x)
    R = 0.40 + 0.46 * (1 - (1 - t) ** 2)
    lobes = fbm(np.cos(a) * 1.6 + 7.0, np.sin(a) * 1.6 + t * 0.9, seed + 31, 3)  # billows around the rim
    R = R * (0.68 + 0.64 * lobes)
    n = warped(x * 2.6, y * 2.6 + t * 1.6, seed, 1.0)
    fine = fbm(x * 7.0, y * 7.0 + t * 3.0, seed + 61, 3)  # small licks and curls inside and along the rim
    edge = (R - r) / R + (n - 0.5) * 1.05 + (fine - 0.5) * 0.55
    density = smoothstep(-0.02, 0.22, edge)
    core = np.clip(1 - r / (R * 0.9), 0, 1)
    heat = core * (1.65 - 1.55 * t) + (n - 0.5) * (0.9 - 0.5 * t) * (0.4 + core) + 0.10 * (1 - t)
    heat = np.clip(heat, 0, 1) * density
    heat = heat * np.clip(0.72 + (fine - 0.5) * 1.3 + core * 0.55, 0, 1)  # cooler veins through the body
    glow = smoothstep(0.05, 0.38, heat) * (1.0 - 0.3 * t)
    emission = ramp(heat, band) * glow[..., None]
    smoke_amount = (0.30 + 0.70 * t) * (1 - 0.9 * glow) * (1 - 0.4 * smoothstep(0.8, 1.0, t))
    alpha = density * np.clip(smoke_amount, 0, 1) * (0.6 + 0.4 * smoothstep(0.0, 0.25, edge))
    alpha = np.maximum(alpha, glow * 0.6 * density)  # the fire also hides what is behind it: saturated, never washed out
    shade = np.clip(0.75 + (n - 0.5) * 1.3 - y * 0.35, 0.3, 1.4)
    cover = np.array(SMOKE_DARK[band]) / 255.0 * shade[..., None]
    return pack(np.clip(cover, 0, 1), alpha, emission)


def smoke(t, band):
    x, y = grid()
    seed = SEEDS[band] + 17
    y = y + 0.10 * t
    r = np.sqrt(x * x + (y * 1.05) ** 2)
    R = 0.56 + 0.32 * t
    n = warped(x * 2.0, y * 2.0 + t * 1.2, seed, 1.3)
    edge = (R - r) / R + (n - 0.5) * 1.25
    alpha = smoothstep(0.0, 0.42, edge) * (0.95 - 0.6 * t)
    light = np.clip(0.62 + (n - 0.5) * 1.1 - y / max(R, 0.1) * 0.28, 0.25, 1.15)
    cover = np.array(SMOKE_LIGHT[band]) / 255.0 * light[..., None]
    return pack(np.clip(cover, 0, 1), alpha, np.zeros(x.shape + (3,)))


def flash(band):
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    a = np.arctan2(y, x)
    core = np.exp(-(r / 0.16) ** 2)
    spikes = np.abs(np.cos(2 * a)) ** 36 * np.exp(-r / 0.30) + 0.7 * np.abs(np.cos(2 * a + math.pi / 4)) ** 70 * np.exp(-r / 0.20)
    halo = 0.35 * np.exp(-(r / 0.42) ** 2)
    i = np.clip(core * 1.3 + spikes + halo, 0, 1.4)
    emission = ramp(np.clip(i, 0, 1), band) * np.clip(i, 0, 1)[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def _segments(w, h, segs, width):
    """Max over line segments (x0, y0, x1, y1, head) of a soft streak brightening toward its head."""
    x, y = grid(w, h)
    out = np.zeros(x.shape)
    for x0, y0, x1, y1, head in segs:
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        s = np.clip(((x - x0) * dx + (y - y0) * dy) / L2, 0, 1)
        d = np.sqrt((x - (x0 + s * dx)) ** 2 + (y - (y0 + s * dy)) ** 2)
        out = np.maximum(out, np.exp(-(d / width) ** 2) * (0.25 + 0.75 * s ** 1.5) * head)
    return out


def sparks(band):
    rng = random.Random(31 + band)
    segs = []
    for k in range(10):
        a = 2 * math.pi * k / 10 + rng.uniform(-0.3, 0.3)
        r0 = rng.uniform(0.25, 0.5)
        r1 = r0 + rng.uniform(0.12, 0.35)
        segs.append((math.cos(a) * r0, math.sin(a) * r0, math.cos(a) * r1, math.sin(a) * r1, rng.uniform(0.55, 0.95)))
    i = _segments(CELL, CELL, segs, 0.016)
    x, y = grid()
    i = np.clip(i + 0.35 * np.exp(-((x * x + y * y) / 0.008)), 0, 1)
    emission = ramp(0.35 + 0.5 * i, band) * i[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def debris(band):
    rng = random.Random(47 + band)
    S = 4
    big = Image.new("L", (CELL * S, CELL * S), 0)
    hot = Image.new("L", (CELL * S, CELL * S), 0)
    d, dh = ImageDraw.Draw(big), ImageDraw.Draw(hot)
    for k in range(8):
        a = 2 * math.pi * k / 8 + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.38, 0.74)
        cx, cy = (1 + math.cos(a) * rr) * CELL * S / 2, (1 + math.sin(a) * rr) * CELL * S / 2
        size = rng.uniform(5, 10) * S
        pts = []
        for j in range(rng.randint(4, 6)):
            pa = 2 * math.pi * j / 5 + rng.uniform(-0.4, 0.4)
            pr = size * rng.uniform(0.55, 1.0)
            pts.append((cx + math.cos(pa) * pr, cy + math.sin(pa) * pr))
        d.polygon(pts, fill=255)
        dh.polygon([(px + (CELL * S / 2 - cx) * 0.08, py + (CELL * S / 2 - cy) * 0.08) for px, py in pts], fill=255)
    alpha = np.asarray(big.resize((CELL, CELL), Image.LANCZOS)).astype(float) / 255.0
    inner = np.asarray(hot.resize((CELL, CELL), Image.LANCZOS)).astype(float) / 255.0
    x, y = grid()
    n = fbm(x * 6, y * 6, SEEDS[band] + 29, 3)
    cover = np.array(DEBRIS[band]) / 255.0 * (0.75 + 0.6 * n)[..., None]
    rim = np.clip(inner - 0.6 * alpha + 0.25, 0, 1) * alpha  # the side of each chunk toward the blast still glows
    emission = ramp(np.full(x.shape, 0.5), band) * (rim * 0.55)[..., None]
    return pack(cover, np.clip(alpha, 0, 1), emission)


def ember(band):
    rng = random.Random(59 + band)
    x, y = grid()
    i = np.zeros(x.shape)
    for _ in range(16):
        cx, cy = rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7)
        s = rng.uniform(0.018, 0.04)
        i = np.maximum(i, np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (s * s)) * rng.uniform(0.6, 1.0))
    emission = ramp(0.35 + 0.6 * i, band) * i[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def glow(band):
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    i = np.exp(-(r / 0.5) ** 2) * (1 - smoothstep(0.75, 0.95, r))
    emission = ramp(0.35 + 0.4 * i, band) * (i * 0.85)[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def ring(band):
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    n = fbm(x * 3.5, y * 3.5, SEEDS[band] + 41, 4)
    alpha = np.exp(-((r - 0.66 + (n - 0.5) * 0.25) / 0.15) ** 2) * (0.45 + 0.75 * n) + 0.18 * smoothstep(0.7, 0.2, r) * n
    cover = np.array(SMOKE_LIGHT[band]) / 255.0 * np.clip(0.75 + (n - 0.5), 0.4, 1.1)[..., None]
    return pack(np.clip(cover, 0, 1), np.clip(alpha, 0, 0.9), np.zeros(x.shape + (3,)))


def rubble(band):
    w, h = 2 * CELL, CELL
    xs = (np.arange(w) + 0.5) / (w / 2) - 1
    ys = (np.arange(h) + 0.5) / (h / 2) - 1
    x, y = np.meshgrid(xs, ys)
    seed = SEEDS[band] + 53
    r = np.sqrt(x * x + y * y)
    n = warped(x * 2.6, y * 1.6, seed, 1.0)
    char = smoothstep(0.0, 0.35, (0.9 - r) + (n - 0.5) * 0.9)
    # chunks: bright-topped bits of broken wall scattered over the scorch
    rng = random.Random(67 + band)
    chunk = np.zeros(x.shape)
    jag = fbm(x * 14.0, y * 14.0, seed + 9, 2)
    for _ in range(34):
        cx, cy = rng.uniform(-0.72, 0.72), rng.uniform(-0.6, 0.6)
        sx, sy = rng.uniform(0.02, 0.055), rng.uniform(0.04, 0.10)
        d = ((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2 + (jag - 0.5) * 2.2
        chunk = np.maximum(chunk, (d < 1).astype(float) * rng.uniform(0.45, 0.9))
    chunk = chunk * char
    alpha = np.clip(char * 0.82 + chunk * 0.18, 0, 1)
    base = np.array(DEBRIS[band]) / 255.0 * 0.55
    stone = np.array(SMOKE_LIGHT[band]) / 255.0 * 0.42
    cover = base * (0.7 + 0.6 * n)[..., None] * (1 - chunk[..., None]) + stone * chunk[..., None]
    cracks = np.clip(1 - np.abs(warped(x * 4.0, y * 2.6, seed + 5, 1.2) - 0.5) / 0.045, 0, 1) * smoothstep(0.75, 0.25, r)
    hot = np.clip(cracks * (1 - chunk) + 0.6 * smoothstep(0.45, 0.0, r) * smoothstep(0.55, 0.75, n), 0, 1)
    emission = ramp(0.35 + 0.55 * hot, band) * (hot * 0.95)[..., None]
    return pack(cover, alpha, emission, w, h)


def _streak(x, y, head, tail, core_w, halo_w, taper=1.0):
    """A vertical streak from `head` (top, image y) down to `tail`: along it the brightness rises toward the head, across it
    a hot core of half-width core_w inside a soft halo of halo_w; `taper` narrows it toward the tail."""
    s = np.clip((y - head) / (tail - head), 0.0, 1.0)  # 0 at the head, 1 at the tail
    inside = (y >= head - 0.12) & (y <= tail + 0.12)
    narrow = 1.0 - taper * 0.65 * s
    d = np.abs(x) / narrow
    along = (1.0 - s) ** 1.1 * smoothstep(head - 0.12, head + 0.02, y) * smoothstep(tail + 0.12, tail - 0.05, y)
    core = np.exp(-(d / core_w) ** 2)
    halo = np.exp(-(d / halo_w) ** 2) * 0.45
    return np.where(inside, (core + halo) * along, 0.0), core * along


def tracer(band):
    """A thin bright streak: a white-hot core in a band-coloured halo."""
    x, y = grid()
    i, core = _streak(x, y, -0.86, 0.86, 0.10, 0.30, 0.5)
    i = np.clip(i, 0, 1)
    heat = np.clip(0.42 + 0.58 * core, 0, 1)
    emission = ramp(heat, band) * i[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def shell(band):
    """A hot round slug near the top with a short trail cooling down the cell."""
    x, y = grid()
    hy = -0.64
    r = np.sqrt(x * x + ((y - hy) * 0.9) ** 2)
    head = np.exp(-(r / 0.15) ** 2) * 1.3 + 0.3 * np.exp(-(r / 0.30) ** 2)
    trail, tcore = _streak(x, y, hy, 0.86, 0.13, 0.30, 0.75)
    n = fbm(x * 5.0, y * 3.0, SEEDS[band] + 73, 3)
    trail = trail * (0.75 + 0.6 * n)
    i = np.clip(np.maximum(head, trail), 0, 1)
    heat = np.clip(0.30 + 0.70 * np.clip(head, 0, 1) + 0.25 * tcore, 0, 1)
    emission = ramp(heat, band) * i[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def bolt(band):
    """A fat plasma lozenge (white core, coloured rim) trailing wisps down the cell."""
    x, y = grid()
    cy = -0.42
    e = np.sqrt((x / 0.20) ** 2 + ((y - cy) / 0.42) ** 2)
    n = warped(x * 3.0, y * 2.0, SEEDS[band] + 79, 0.8)
    body = np.exp(-(e / 0.75) ** 2) * 1.3
    rim = np.exp(-((e - 0.95 + (n - 0.5) * 0.4) / 0.28) ** 2) * 0.55
    tail, _ = _streak(x + (n - 0.5) * 0.18, y, cy + 0.2, 0.88, 0.10, 0.26, 0.6)
    tail = tail * (0.45 + 0.7 * n)
    i = np.clip(body + rim + tail * 0.7, 0, 1)
    heat = np.clip(0.36 + 0.64 * np.clip(body, 0, 1) - 0.05 * rim, 0, 1)
    emission = ramp(heat, band) * i[..., None]
    return pack(np.zeros(x.shape + (3,)), np.zeros(x.shape), emission)


def build(png_out):
    atlas = np.zeros((2 * BAND_ROWS * CELL, COLS * CELL, 4), np.uint8)

    def put(band, row, col, px):
        y = (band * BAND_ROWS + row) * CELL
        atlas[y:y + px.shape[0], col * CELL:col * CELL + px.shape[1]] = px

    for band in range(2):
        for i in range(FIREBALL_FRAMES):
            put(band, 0, i, fireball(i / (FIREBALL_FRAMES - 1), band))
        for i in range(SMOKE_FRAMES):
            put(band, 1, i, smoke(i / (SMOKE_FRAMES - 1), band))
        for name, fn in (("flash", flash), ("sparks", sparks), ("debris", debris), ("ember", ember), ("glow", glow), ("ring", ring), ("rubble", rubble)):
            put(band, 2, SINGLES[name][0], fn(band))
        for name, fn in (("tracer", tracer), ("shell", shell), ("bolt", bolt)):
            put(band, 3, SHOTS[name], fn(band))
    pathlib.Path(png_out).parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(png_out, optimize=False)


if __name__ == "__main__":
    build(OUT)
    print(OUT)
