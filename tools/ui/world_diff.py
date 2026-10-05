"""Score how much a live world-only frame reads like a board's battlefield. Statistics, never a pixel match.

  world_diff.py pair <mock.png> <live.png> --crop x0,y0,x1,y1 [--mask x0,y0,x1,y1]... [--out side.png]
  world_diff.py run --mocks DIR --live DIR --out DIR [--boards gp01,gp05] [--check tools/ui/world_scores.json]
                    [--require gp05:+5,gp07:+5] [--write PATH]
  world_diff.py blobs <png> [--crop x0,y0,x1,y1]
Score: 100 minus penalties (palette <= 40, saturation <= 20, detail <= 15, clutter <= 10, warmth <= 15)."""
import argparse, json, math, pathlib, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = pathlib.Path(__file__).absolute().parent
FRAMES = HERE / "world_frames.json"
_M = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])


def srgb_to_lab(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = lin @ _M.T / np.array([0.95047, 1.0, 1.08883])
    e = (6 / 29) ** 3
    f = np.where(xyz > e, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float64)


def delta_e(a, b):
    return float(np.linalg.norm(srgb_to_lab(hex_rgb(a)) - srgb_to_lab(hex_rgb(b))))


def rect_mask(shape, rects):
    """True = excluded. Rects are [x0, y0, x1, y1] in the image's own pixels."""
    m = np.zeros(shape[:2], bool)
    for x0, y0, x1, y1 in rects:
        m[y0:y1, x0:x1] = True
    return m


def stats(img, mask):
    img = np.asarray(img)[..., :3]
    keep = ~mask if mask is not None else np.ones(img.shape[:2], bool)
    rgb = img.astype(np.float64)
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0) * 255
    luma = rgb @ np.array([0.299, 0.587, 0.114])
    hp = np.abs(luma - ndimage.gaussian_filter(luma, 6))
    sob = np.hypot(ndimage.sobel(luma, 0), ndimage.sobel(luma, 1))
    lab = srgb_to_lab(img[keep])
    rng = np.random.default_rng(7)
    if len(lab) > 20000:
        lab = lab[rng.choice(len(lab), 20000, replace=False)]
    return {"lab": lab, "sat_p50": float(np.median(sat[keep])), "detail": float(hp[keep].mean()),
            "clutter": float((sob[keep] > 96).mean()), "b": float(lab[:, 2].mean()), "luma": float(luma[keep].mean())}


def sliced_wasserstein(a, b, n=64, seed=7):
    rng = np.random.default_rng(seed)
    q = np.linspace(0, 1, 256)
    total = 0.0
    for _ in range(n):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        total += np.abs(np.quantile(a @ d, q) - np.quantile(b @ d, q)).mean()
    return total / n


def _log_ratio(a, b):
    return abs(math.log(max(a, 1e-6) / max(b, 1e-6)))


def score(mock, live):
    pw = sliced_wasserstein(mock["lab"], live["lab"])
    pen = {"palette": min(40.0, pw),
           "saturation": min(20.0, abs(live["sat_p50"] - mock["sat_p50"]) / 4.0),
           "detail": min(15.0, 15.0 * _log_ratio(live["detail"], mock["detail"]) / math.log(4)),
           "clutter": min(10.0, 10.0 * _log_ratio(live["clutter"] + 1e-3, mock["clutter"] + 1e-3) / math.log(4)),
           "warmth": min(15.0, abs(live["b"] - mock["b"]))}
    out = {k: round(v, 2) for k, v in pen.items()}
    out["total"] = round(100.0 - sum(pen.values()), 2)
    out["raw"] = {"palette_w": round(pw, 2), "sat_mock": round(mock["sat_p50"], 1), "sat_live": round(live["sat_p50"], 1),
                  "detail_ratio": round(live["detail"] / max(mock["detail"], 1e-6), 3),
                  "clutter_ratio": round((live["clutter"] + 1e-3) / (mock["clutter"] + 1e-3), 3),
                  "b_mock": round(mock["b"], 1), "b_live": round(live["b"], 1)}
    return out


def yellow_blobs(img, min_area=400):
    rgb = np.asarray(img)[..., :3].astype(np.float64) / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    c = mx - mn
    s = np.where(mx > 0, c / np.maximum(mx, 1e-6), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(c == 0, 0, np.where(mx == r, ((g - b) / np.maximum(c, 1e-6)) % 6, np.where(mx == g, (b - r) / np.maximum(c, 1e-6) + 2, (r - g) / np.maximum(c, 1e-6) + 4))) * 60
    hit = (hue >= 30) & (hue <= 65) & (s > 0.55) & (mx > 0.55)
    labels, n = ndimage.label(hit)
    out = []
    for i, sl in enumerate(ndimage.find_objects(labels), 1):
        area = int((labels[sl] == i).sum())
        if area >= min_area:
            ys, xs = sl
            out.append({"x": xs.start, "y": ys.start, "w": xs.stop - xs.start, "h": ys.stop - ys.start, "area": area,
                        "cx": (xs.start + xs.stop) // 2, "cy": (ys.start + ys.stop) // 2})
    return sorted(out, key=lambda b: -b["area"])


def swatches(live, points, palette, patch=12):
    img = np.asarray(live)[..., :3]
    h, w = img.shape[:2]
    out = {}
    for glyph, (x, y, on_screen) in points.items():
        x, y = int(x), int(y)
        if not on_screen or not (patch <= x < w - patch and patch <= y < h - patch) or glyph not in palette:
            continue
        med = np.median(img[y - patch:y + patch, x - patch:x + patch].reshape(-1, 3), 0)
        live_hex = "".join(f"{int(v):02x}" for v in med)
        out[glyph] = {"live": live_hex, "mock": palette[glyph], "de": round(delta_e(live_hex, palette[glyph]), 2)}
    return out


def side_by_side(mock, live, mask, path, title):
    mock, live = np.asarray(mock)[..., :3].copy(), np.asarray(live)[..., :3]
    if mask is not None:
        mock[mask] = (mock[mask] * 0.35 + np.array([90, 90, 90]) * 0.65).astype(np.uint8)
    h, w = mock.shape[:2]
    canvas = Image.new("RGB", (2 * w + 12, h + 28), (12, 18, 24))
    canvas.paste(Image.fromarray(mock), (0, 28))
    canvas.paste(Image.fromarray(live), (w + 12, 28))
    ImageDraw.Draw(canvas).text((6, 6), "MOCK | LIVE   " + title, fill=(220, 230, 235))
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def _crop(img, rect):
    x0, y0, x1, y1 = rect
    return np.asarray(img)[y0:y1, x0:x1, :3]


def _local_masks(rect, masks):
    x0, y0 = rect[0], rect[1]
    return [[m[0] - x0, m[1] - y0, m[2] - x0, m[3] - y0] for m in masks]


def run(args):
    cfg = json.loads(FRAMES.read_text())
    boards = args.boards.split(",") if args.boards else list(cfg["boards"])
    prev = json.loads(pathlib.Path(args.check).read_text()) if args.check else {}
    required = dict((k, float(v)) for k, v in (r.split(":") for r in args.require.split(","))) if args.require else {}
    tol = max(2.0, float(cfg.get("noise", 0.0)))
    result, failures = {}, []
    for board in boards:
        b = cfg["boards"][board]
        mock = np.asarray(Image.open(pathlib.Path(args.mocks) / f"{board}.png").convert("RGB"))
        live_png = pathlib.Path(args.live) / f"{b['frame']}.png"
        live = np.asarray(Image.open(live_png).convert("RGB"))
        m, l = _crop(mock, b["crop"]), _crop(live, b["crop"])
        mask = rect_mask(m.shape, _local_masks(b["crop"], b.get("mask", [])))
        s = score(stats(m, mask), stats(l, mask))
        side = live_png.with_suffix(".json")
        if side.exists():
            pts = json.loads(side.read_text()).get("swatches", {})
            s["swatches"] = swatches(live, pts, cfg["palette"])
        side_by_side(m, l, mask, pathlib.Path(args.out) / f"side_{board}.png", f"{board} {b['frame']} {s['total']}")
        result[board] = s
        before = prev.get(board, {}).get("total")
        need = required.get(board)
        delta = None if before is None else s["total"] - before
        line = f"{board:5} {s['total']:6.2f}" + ("" if delta is None else f"  delta {delta:+.2f}")
        print(line, json.dumps({k: s[k] for k in ("palette", "saturation", "detail", "clutter", "warmth")}))
        if delta is not None and need is not None and delta < need:
            failures.append(f"{board} improved {delta:+.2f}, needs +{need}")
        if delta is not None and need is None and delta < -tol:
            failures.append(f"{board} dropped {delta:+.2f} (tolerance {tol})")
    if args.write:
        pathlib.Path(args.write).write_text(json.dumps(result, indent=1, default=float) + "\n")
    for f in failures:
        print("FAIL", f)
    return 1 if failures else 0


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("pair")
    a.add_argument("mock"); a.add_argument("live")
    a.add_argument("--crop", required=True); a.add_argument("--mask", action="append", default=[]); a.add_argument("--out")
    r = sub.add_parser("run")
    for k in ("--mocks", "--live", "--out"):
        r.add_argument(k, required=True)
    r.add_argument("--boards"); r.add_argument("--check"); r.add_argument("--require"); r.add_argument("--write")
    bl = sub.add_parser("blobs")
    bl.add_argument("png"); bl.add_argument("--crop")
    args = p.parse_args(argv)
    if args.cmd == "run":
        return run(args)
    if args.cmd == "blobs":
        img = np.asarray(Image.open(args.png).convert("RGB"))
        rect = [int(v) for v in args.crop.split(",")] if args.crop else [0, 0, img.shape[1], img.shape[0]]
        found = yellow_blobs(_crop(img, rect))
        for f in found:
            f["x"] += rect[0]; f["y"] += rect[1]; f["cx"] += rect[0]; f["cy"] += rect[1]
        print(json.dumps(found, indent=1))
        return 0
    rect = [int(v) for v in args.crop.split(",")]
    m = _crop(Image.open(args.mock).convert("RGB"), rect)
    l = _crop(Image.open(args.live).convert("RGB"), rect)
    mask = rect_mask(m.shape, _local_masks(rect, [[int(v) for v in s.split(",")] for s in args.mask]))
    s = score(stats(m, mask), stats(l, mask))
    if args.out:
        side_by_side(m, l, mask, args.out, f"{s['total']}")
    print(json.dumps(s, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
