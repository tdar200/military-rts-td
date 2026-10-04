#!/usr/bin/env python3
"""Compare a Godot capture with the Chrome render of its mock.

usage: diff_screens.py <screen> <mock.png> <godot.png> <outdir> [--threshold PCT]
Rect lists come from compare.json: {"screen": {"rects": [{"name","x","y","w","h","max"}], "ignore": [[x,y,w,h]]}}.
A pixel is bad when any channel differs by more than TOL. Exit 1 if any rect exceeds its max (or --threshold).
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

TOL = 24
HERE = Path(__file__).absolute().parent


def load(p):
    im = Image.open(p).convert("RGB")
    if im.size != (1920, 1080):
        sys.exit(f"{p}: expected 1920x1080, got {im.size}")
    return np.asarray(im).astype(np.int16)


def main():
    skip = {sys.argv[i + 1] for i, a in enumerate(sys.argv) if a in ("--spec", "--threshold") and i + 1 < len(sys.argv)}
    args = [a for a in sys.argv[1:] if not a.startswith("--") and a not in skip]
    screen, mock_p, god_p, outdir = args[:4]
    thr = None
    if "--threshold" in sys.argv:
        thr = float(sys.argv[sys.argv.index("--threshold") + 1])
    spec_path = Path(sys.argv[sys.argv.index("--spec") + 1]) if "--spec" in sys.argv else HERE / "compare.json"
    spec = json.load(open(spec_path))[screen]
    a, b = load(mock_p), load(god_p)
    keep = np.ones(a.shape[:2], bool)
    for x, y, w, h in spec.get("ignore", []):
        keep[y:y + h, x:x + w] = False
    bad = (np.abs(a - b).max(axis=2) > TOL) & keep
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    fail = False
    print(f"{'rect':28s} {'bad%':>6s} {'max%':>6s}")
    for r in spec["rects"]:
        x, y, w, h = r["x"], r["y"], r["w"], r["h"]
        k = keep[y:y + h, x:x + w]
        n = int(k.sum())
        pct = 100.0 * int(bad[y:y + h, x:x + w].sum()) / max(n, 1)
        limit = thr if thr is not None else r.get("max", 100.0)
        flag = "FAIL" if pct > limit else "ok"
        fail |= pct > limit
        print(f"{r['name']:28s} {pct:6.2f} {limit:6.2f} {flag}")
    heat = np.asarray(Image.open(mock_p).convert("RGB")).copy()
    heat[bad] = (255, 0, 80)
    Image.fromarray(heat).save(out / f"{screen}-heat.png")
    side = np.concatenate([a.astype(np.uint8), b.astype(np.uint8)], axis=1)
    Image.fromarray(side).save(out / f"{screen}-side.png")
    sys.exit(1 if fail else 0)


main()
