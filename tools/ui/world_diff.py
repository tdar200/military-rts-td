"""Score how much a live world-only frame reads like a board's battlefield. Statistics, never a pixel match.

  world_diff.py pair <mock.png> <live.png> --crop x0,y0,x1,y1 [--mask x0,y0,x1,y1]... [--out side.png]
  world_diff.py run --mocks DIR --live DIR --out DIR [--boards gp01,gp05] [--check tools/ui/world_scores.json]
                    [--require gp05:+5,gp07:+5] [--require-structure gp05:+3] [--write PATH] [--frames PATH]
    --require-structure gates the grade-proof subscore (rank detail/clutter + layout): a colour grade cannot raise it.
  world_diff.py blobs <png> [--crop x0,y0,x1,y1]
Score: 100 minus penalties (palette <= 12, saturation <= 6, warmth <= 7, detail <= 28, clutter <= 17, layout <= 30).
Capture timing: live frames are taken a fixed wall time after deploy, so moving units and the wave clock differ a little
run to run; world_frames.json "noise" and "noise_terms" record the spread seen over repeated captures."""
import argparse, json, math, pathlib, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.stats import rankdata

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


DETAIL_SIGMAS = (1.5, 6.0, 24.0)   # band energy between blurs: fine grain, tufts and sprites, region shapes
CLUTTER_LEVELS = (1, 4)            # Sobel on the luma at full size and on 4x4 block means
WEIGHTS = {"palette": 12.0, "saturation": 6.0, "warmth": 7.0, "detail": 28.0, "clutter": 17.0, "layout": 30.0}  # colour 25, spatial 75
LN16 = math.log(16.0)
LN64 = math.log(64.0)  # clutter ratios of a bare world run 0.05 to 0.2, so ln 16 would pin the term at its cap


def _fill(plane, keep):
    """Replace excluded pixels by the mean of the kept ones so blurs and Sobel see no HUD panel."""
    out = plane.copy()
    out[~keep] = plane[keep].mean() if keep.any() else 0.0
    return out


def _cells(plane, keep, cell):
    h, w = plane.shape
    ch, cw = h // cell, w // cell
    p = plane[:ch * cell, :cw * cell].reshape(ch, cell, cw, cell).mean((1, 3))
    k = keep[:ch * cell, :cw * cell].reshape(ch, cell, cw, cell).all((1, 3))
    return p, k


def _bands(plane, keep):
    blurs = [plane] + [ndimage.gaussian_filter(plane, s) for s in DETAIL_SIGMAS]
    return [float(np.abs(blurs[i] - blurs[i + 1])[keep].mean()) for i in range(len(DETAIL_SIGMAS))]


def _edges(plane, keep):
    out = []
    for k in CLUTTER_LEVELS:
        h, w = plane.shape
        p = plane if k == 1 else plane[:h // k * k, :w // k * k].reshape(h // k, k, w // k, k).mean((1, 3))
        kp = keep if k == 1 else keep[:h // k * k, :w // k * k].reshape(h // k, k, w // k, k).all((1, 3))
        sob = np.hypot(ndimage.sobel(p, 0), ndimage.sobel(p, 1))
        out.append(float((sob[kp] > 96).mean()) if kp.any() else 0.0)
    return out


def _rank(plane, keep):
    """Percentile of each kept pixel over the kept pixels, 0..255 (ties averaged, so a flat image stays flat). Any monotone
    colour grade leaves it unchanged, which is what keeps a histogram match from faking texture."""
    out = np.full(plane.shape, 127.5)
    if keep.any():
        r = rankdata(plane[keep], method="average")
        out[keep] = (r - 0.5) / len(r) * 255.0
    return out


def stats(img, mask):
    img = np.asarray(img)[..., :3]
    keep = ~mask if mask is not None else np.ones(img.shape[:2], bool)
    rgb = img.astype(np.float64)
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0) * 255
    luma = _fill(rgb @ np.array([0.299, 0.587, 0.114]), keep)
    ranked = _rank(luma, keep)
    lab_all = srgb_to_lab(img)
    cell = max(8, int(round(min(img.shape[:2]) / 14)))
    lum_cells, valid = _cells(luma, keep, cell)
    b_cells, _ = _cells(_fill(lab_all[..., 2], keep), keep, cell)
    lab = lab_all[keep]
    rng = np.random.default_rng(7)
    if len(lab) > 20000:
        lab = lab[rng.choice(len(lab), 20000, replace=False)]
    return {"lab": lab, "sat_p50": float(np.median(sat[keep])), "sat_p90": float(np.percentile(sat[keep], 90)),
            "detail": _bands(luma, keep), "detail_rank": _bands(ranked, keep),
            "clutter": _edges(luma, keep), "clutter_rank": _edges(ranked, keep),
            "b": float(lab[:, 2].mean()), "luma": float(luma[keep].mean()), "layout": (lum_cells, b_cells, valid)}


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


def _corr(a, b, valid):
    if valid.sum() < 4:
        return 0.0
    x, y = a[valid], b[valid]
    sx, sy = x.std(), y.std()
    if sx < 1e-6 or sy < 1e-6:
        return 0.0
    return float(((x - x.mean()) * (y - y.mean())).mean() / (sx * sy))


def _ratios(mock, live, key, floor=0.0, plus=0.0):
    """live/mock per scale; `floor` clamps both from below (energies), `plus` offsets both (fractions that can be zero)."""
    return [(max(live[key][i], floor) + plus) / (max(mock[key][i], floor) + plus) for i in range(len(mock[key]))]


def _gap(ratios, span):
    return float(np.mean([min(1.0, abs(math.log(r)) / span) for r in ratios]))


def score(mock, live):
    """100 minus penalties. Every term scales over the gap a real frame has (log ratios over ln 16, clutter over ln 64, not
    ln 4), so a partial improvement moves its term. Colour terms are only 25 points; spatial terms are 75: detail (three
    bands) and clutter (two scales) are each measured on raw luma AND on percentile-ranked luma and take the worse of the
    two (a grade or contrast stretch cannot fake the rank view, flat noise cannot fake the raw view), and layout compares
    where light and blue-yellow sit on a coarse grid. A histogram match, flat tint or shuffled pixels cannot pass."""
    pw = sliced_wasserstein(mock["lab"], live["lab"])
    sat_gap = (abs(live["sat_p50"] - mock["sat_p50"]) + abs(live["sat_p90"] - mock["sat_p90"])) / 2.0
    b_gap = abs(live["b"] - mock["b"])
    d_raw, d_rank = _ratios(mock, live, "detail", floor=1e-3), _ratios(mock, live, "detail_rank", floor=1e-3)
    c_raw, c_rank = _ratios(mock, live, "clutter", plus=1e-3), _ratios(mock, live, "clutter_rank", plus=1e-3)
    valid = mock["layout"][2] & live["layout"][2]
    corr_l = _corr(mock["layout"][0], live["layout"][0], valid)
    corr_b = _corr(mock["layout"][1], live["layout"][1], valid)
    corr = (corr_l + corr_b) / 2.0
    pen = {"palette": WEIGHTS["palette"] * min(1.0, pw / 50.0),
           "saturation": WEIGHTS["saturation"] * min(1.0, sat_gap / 200.0),
           "warmth": WEIGHTS["warmth"] * min(1.0, b_gap / 40.0),
           "detail": WEIGHTS["detail"] * max(_gap(d_raw, LN16), _gap(d_rank, LN16)),
           "clutter": WEIGHTS["clutter"] * max(_gap(c_raw, LN64), _gap(c_rank, LN64)),
           "layout": WEIGHTS["layout"] * (1.0 - corr) / 2.0}
    out = {k: round(v, 2) for k, v in pen.items()}
    out["total"] = round(100.0 - sum(pen.values()), 2)
    # structure: the grade-proof part (rank-based detail and clutter plus layout). A colour grade or histogram match cannot move it.
    st = WEIGHTS["detail"] * _gap(d_rank, LN16) + WEIGHTS["clutter"] * _gap(c_rank, LN64) + pen["layout"]
    out["structure"] = round(100.0 - st * 100.0 / (WEIGHTS["detail"] + WEIGHTS["clutter"] + WEIGHTS["layout"]), 2)
    out["raw"] = {"palette_w": round(pw, 2), "sat_gap": round(sat_gap, 1),
                  "sat_p50": [round(mock["sat_p50"], 1), round(live["sat_p50"], 1)],
                  "sat_p90": [round(mock["sat_p90"], 1), round(live["sat_p90"], 1)],
                  "b": [round(mock["b"], 1), round(live["b"], 1)],
                  "detail_ratio": [round(r, 3) for r in d_raw], "detail_rank_ratio": [round(r, 3) for r in d_rank],
                  "clutter_ratio": [round(r, 3) for r in c_raw], "clutter_rank_ratio": [round(r, 3) for r in c_rank],
                  "layout_corr": [round(corr_l, 3), round(corr_b, 3)]}
    return out


def yellow_blobs(img, min_area=400, max_area=12000):
    """Amber marks (hover torus f0be4a and the like): hue 36 to 60, saturated, bright. Orange or ochre ground is outside the
    hue and brightness band, and anything larger than max_area is ground or sky rather than a marker, so it is not returned."""
    rgb = np.asarray(img)[..., :3].astype(np.float64) / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    c = mx - mn
    s = np.where(mx > 0, c / np.maximum(mx, 1e-6), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(c == 0, 0, np.where(mx == r, ((g - b) / np.maximum(c, 1e-6)) % 6, np.where(mx == g, (b - r) / np.maximum(c, 1e-6) + 2, (r - g) / np.maximum(c, 1e-6) + 4))) * 60
    hit = (hue >= 36) & (hue <= 60) & (s > 0.55) & (mx > 0.75)
    labels, n = ndimage.label(hit)
    out = []
    for i, sl in enumerate(ndimage.find_objects(labels), 1):
        area = int((labels[sl] == i).sum())
        if min_area <= area <= max_area:
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


def _parse_required(text):
    out = {}
    for item in text.split(","):
        board, sep, value = item.partition(":")
        if not sep:
            raise ValueError(f"bad --require entry {item!r}, expected board:+N")
        out[board.strip()] = float(value)
    return out


def _gate(args, flag, key, boards, cfg_boards, prev, results, failures, tol):
    """Check one --require / --require-structure option against the check file. Every misuse is a failure."""
    text = getattr(args, flag)
    if not text:
        return
    try:
        required = _parse_required(text)
    except ValueError as e:
        failures.append(str(e))
        return
    if not args.check:
        failures.append(f"--{flag.replace('_', '-')} needs --check (nothing to improve on)")
        return
    for board, need in required.items():
        if board not in boards or board not in results:
            failures.append(f"{board} is required but was not scored (not in --boards or a typo)")
        elif board not in prev or key not in prev[board]:
            failures.append(f"{board} has no {key} in the check file; re-baseline it")
        else:
            delta = results[board][key] - prev[board][key]
            if delta < need:
                failures.append(f"{board} {key} improved {delta:+.2f}, needs +{need}")


def run(args):
    """Exit 0 only when every board was scored and every requested comparison actually happened. --require needs --check,
    and a required board that is not in cfg, in --boards, or in the check file is a failure, never a silent pass."""
    cfg = json.loads(pathlib.Path(args.frames or FRAMES).read_text())
    boards = args.boards.split(",") if args.boards else list(cfg["boards"])
    failures = []
    for board in boards:
        if board not in cfg["boards"]:
            failures.append(f"{board} is not a board in the frames file")
    prev = json.loads(pathlib.Path(args.check).read_text()) if args.check else {}
    if args.check:
        for board in boards:
            if board in cfg["boards"] and board not in prev:
                failures.append(f"{board} has no entry in the check file {args.check}")
    for opt in (args.require, args.require_structure):
        try:
            _parse_required(opt) if opt else None
        except ValueError as e:
            failures.append(str(e))
    if (args.require or args.require_structure) and not args.check:
        failures.append("--require / --require-structure need --check (nothing to improve on)")
    if failures:
        for f in failures:
            print("FAIL", f)
        return 1
    tol = max(2.0, float(cfg.get("noise", 0.0)))
    result = {}
    req_total = _parse_required(args.require) if args.require else {}
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
        delta = None if before is None else s["total"] - before
        print(f"{board:5} {s['total']:6.2f}  structure {s['structure']:6.2f}" + ("" if delta is None else f"  delta {delta:+.2f}"),
              json.dumps({k: s[k] for k in WEIGHTS}))
        print("      raw", json.dumps(s["raw"]))
        if delta is not None and board not in req_total and delta < -tol:
            failures.append(f"{board} dropped {delta:+.2f} (tolerance {tol})")
    _gate(args, "require", "total", boards, cfg["boards"], prev, result, failures, tol)
    _gate(args, "require_structure", "structure", boards, cfg["boards"], prev, result, failures, tol)
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
    r.add_argument("--boards"); r.add_argument("--check"); r.add_argument("--require"); r.add_argument("--write"); r.add_argument("--frames"); r.add_argument("--require-structure")
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
