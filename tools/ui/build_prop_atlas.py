"""Bake the Kestrel prop atlas from the game's own painted sprites (spec addendum W5).
Usage: python3 tools/ui/build_prop_atlas.py  (writes godot3d/assets/world/props_atlas.png and .json)"""
import colorsys, json, pathlib, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

REPO = pathlib.Path(__file__).absolute().parents[2]
SIZE = 1024
PAD = 4
# name: (source, target width, kind, sink as a fraction of the card height)
SPRITES = {
    "forest": (REPO / "godot3d/assets/terrain/painterly/forest_cluster_v5.png", 500, "card", 0.10),
    "forest_dry": (None, 500, "card", 0.10),
    "scrub": (REPO / "assets/scrub_cluster_v1.png", 240, "card", 0.12),
    "rock": (REPO / "assets/rock_cluster_v1.png", 240, "card", 0.14),
    "ore": (REPO / "assets/ore_crystals_v1.png", 240, "card", 0.12),
    "alloy": (None, 240, "card", 0.12),
    "crater": (REPO / "assets/crater_v1.png", 240, "decal", 0.0),
    "pebbles": (None, 120, "decal", 0.0),
    "shadow": (None, 120, "decal", 0.0),
}


def crop_to_alpha(im):
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    return im.crop(box) if box else im


def fit(im, width):
    im = crop_to_alpha(im.convert("RGBA"))
    return im.resize((width, max(1, round(im.height * width / im.width))), Image.LANCZOS)


def dry(im):
    """gen.py's 'dry' filter: saturate(.75) sepia(.25) brightness(.95)."""
    rgb, a = im.convert("RGB"), im.getchannel("A")
    rgb = ImageEnhance.Color(rgb).enhance(0.75)
    sep = Image.merge("RGB", [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(rgb.convert("L").convert("RGB").split(), (1.07, 0.95, 0.74))])
    rgb = Image.blend(rgb, sep, 0.25)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.95)
    return Image.merge("RGBA", (*rgb.split(), a))


def hue_rotate(im, degrees):
    px = im.load()
    out = im.copy()
    po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            r2, g2, b2 = colorsys.hls_to_rgb((h + degrees / 360) % 1, l, s)
            po[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return out


def pebbles(w):
    im = Image.new("RGBA", (w, w // 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    import random
    rng = random.Random(11)
    for _ in range(26):
        x, y = rng.randint(6, w - 6), rng.randint(4, w // 2 - 4)
        rx, ry = rng.randint(3, 6), rng.randint(2, 4)
        d.ellipse((x - rx, y - ry, x + rx, y + ry), fill=rng.choice([(154, 165, 168, 235), (125, 135, 139, 235), (181, 190, 192, 235)]))
    return im


def shadow(w):
    im = Image.new("RGBA", (w, w // 3), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((6, 4, w - 6, w // 3 - 4), fill=(10, 15, 8, 150))
    return im.filter(ImageFilter.GaussianBlur(5))


def build(png_out, json_out):
    images = {}
    for name, (src, width, kind, sink) in SPRITES.items():
        if name == "forest_dry":
            images[name] = dry(images["forest"])
        elif name == "alloy":
            images[name] = hue_rotate(images["ore"], 95)
        elif name == "pebbles":
            images[name] = pebbles(width)
        elif name == "shadow":
            images[name] = shadow(width)
        else:
            images[name] = fit(Image.open(src), width)
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    meta = {"size": [SIZE, SIZE], "sprites": {}}
    x = y = row_h = 0
    for name in SPRITES:
        im = images[name]
        if x + im.width + PAD > SIZE:
            x, y, row_h = 0, y + row_h + PAD, 0
        if y + im.height > SIZE:
            raise SystemExit("atlas overflow at " + name)
        atlas.paste(im, (x, y))
        _, _, kind, sink = SPRITES[name]
        meta["sprites"][name] = {"rect": [x, y, im.width, im.height], "uv": [x / SIZE, y / SIZE, im.width / SIZE, im.height / SIZE],
                                 "aspect": im.height / im.width, "sink": sink, "kind": kind}
        x += im.width + PAD
        row_h = max(row_h, im.height)
    pathlib.Path(png_out).parent.mkdir(parents=True, exist_ok=True)
    atlas.save(png_out)
    pathlib.Path(json_out).write_text(json.dumps(meta, indent=1) + "\n")


if __name__ == "__main__":
    out = REPO / "godot3d/assets/world"
    build(out / "props_atlas.png", out / "props_atlas.json")
    print(out / "props_atlas.png")
