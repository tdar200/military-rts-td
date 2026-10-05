# Kestrel Reach World Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-art the Kestrel Reach 3D battlefield so a live frame reads like gameplay boards 1 and 3 to 8 (olive painted ground, banked river, deep sea, dense painted props, crystals, big readable buildings, north-up framing, warm grade) while it stays 3D and Survival does not change.

**Architecture:** A client-only `WorldArt` profile switches on when the first non-flat ground layer arrives (`_sync_ground`); every new path is behind it, so Survival keeps the legacy look byte for byte. Ground, water and shore are one terrain shader fed by extra baked vertex channels; props and crystals are camera-facing billboard cards and flat decals in two MultiMeshes drawn from a baked atlas of the game's own painted sprites; buildings and units are the authored glbs fitted to a width table. A new QA world driver plus `tools/ui/world_diff.py` capture world-only frames and score them statistically against each board's battlefield crop.

**Tech Stack:** Godot 4.7.2 GDScript, Compatibility (OpenGL 3.3) renderer, spatial and canvas_item shaders (no compute, no screen or depth textures), MultiMesh; Python 3 with numpy 1.26, Pillow 10.2, scipy 1.11, `unittest` (no pytest, no skimage); headless Chrome via `tools/ui/mockkit.py`.

**Spec:** `docs/superpowers/specs/2026-10-04-gameplay-hud-kestrel-reach-design.md` (binding, sections 5.1 and 5.2) and its addendum `docs/superpowers/specs/2026-10-05-kestrel-world-art-design.md` (rulings W1 to W9, budgets, verification). Executors read both. Boards: `docs/ascension/ui-mocks-gameplay/*.dc.html`; world image `docs/ascension/ui-mocks-gameplay/terrain/land.jpg`, made by `terrain/gen.py` (read gen.py: it is the recipe this plan reproduces in 3D).

## Global Constraints

- Client only. `crates/` is not touched: `git diff --stat d81deab..HEAD -- crates/` stays empty; golden hash `2_081_234_273_307_305_018` cannot move.
- Every new behaviour is gated on `world_art_on` (set only when `_sync_ground` builds a ground model). Survival and other scenarios never build one (`GroundModel.is_flat`), so they keep: `camera_yaw = -0.68`, zoom 15.5 to 8.8 on deploy, wheel range 7.5 to 24, environment (exposure 0.78, saturation 0.85, sky background), amber hover torus 0.42/0.47, ocean box, tactical box-built human buildings, world_tree dressing, deposit disks with `ORE` labels.
- Renderer: Compatibility. No compute shaders, no `hint_screen_texture`, no `hint_depth_texture`, no SSAO reliance. Shaders live in GDScript strings like `continuous_terrain.gd` does.
- Budgets (spec addendum section 4): idle draw calls no more than baseline + 120 at default and max zoom; primitives no more than baseline + 150k; GPU idle fps at least 0.9x baseline; `process_ms` up no more than 10 percent; one-time ground bake plus prop scatter under 1.5 s.
- Godot rules from the parent plan: `preload`, never `class_name`; no em dashes or en dashes in code comments, copy or docs (plain hyphens); run `$GODOT --headless --path godot3d --import` after adding or replacing any asset; grep every Godot log for `SCRIPT ERROR` and `SHADER ERROR`.
- Godot gate: `$GODOT --headless --path godot3d --script res://tests/run_tests.gd` stays green (1519+ passing at the start; record the exact number in Task 1). Exit leak lines no worse than today: at most `4` ObjectDB instances leaked and `2` resources still in use.
- Headless tests need no GPU: they never read the viewport texture, never depend on shader compilation, never sleep on wall time.
- QA harness rules: never make sound (launch_ui already forces the Dummy audio driver); never touch an already-running game window; use `tools/qa/launch_ui.py <dir> --software --scenario kestrel --display :94` (Task 1 adds `--display`; another agent may own `:93`); kill only the PIDs in `<dir>/pids.json`; captures and scratch files go to the session scratchpad `$SCRATCH` the controller gives you, never into the repo. Do NOT use `git stash`.
- A GPU (non `--software`) harness opens a real window on the user's display: ask the controller before any GPU run.
- Commits stage only the task's own paths (`git add <paths>`, never `-A`; `tools/qa/ui_driver.gd` carries another agent's uncommitted work and is never staged by this plan). Commit trailer: the implementing model's own `Co-Authored-By:` line, as the controller supplies it.
- Visual acceptance is a measured `world_diff` improvement plus the task's visual checklist, never a pixel match. Thresholds are deltas against `tools/ui/world_scores.json`; no task may lower any board by more than 2 points (or the measured noise from Task 1, whichever is larger).
- One table per tunable: colours in `GROUND_LOOK` and `WorldArt.ENVIRONMENT`, sizes in `WorldArt.BUILDING_TILES` / `UNIT_TILES`, scatter in `WorldProps.RULES`. Tuning edits the table, not the code.

Shorthands used below: `$GODOT` = `tools/godot/Godot_v4.7.2-stable_linux.x86_64`; `$SCRATCH` = the session scratchpad; `$TESTS` = `$GODOT --headless --path godot3d --script res://tests/run_tests.gd`; a filter runs one file: `$TESTS -- test_world_art`.

## Review Focus

- Survival regression: a flat ground layer (Survival) must keep every legacy value listed in Global Constraints. Pinned by `godot3d/tests/test_world_art_survival.gd`, which each task extends for the path it gates (Tasks 2 to 9), plus a live Survival world frame compared with its Task 1 baseline (Task 10).
- Low-end frame rate: props must cost a constant number of draw calls, never one per tree. Pinned by Task 7 (exactly two MultiMeshInstance3D, shadow casting off) and the live perf gate in Task 10 (draw calls, primitives, fps, process_ms against `tools/ui/world_baseline.json`).
- Headless tests without a GPU: every new test runs under `--headless`, the dummy rendering server, no viewport reads. Pinned by running the whole suite headless in every task and by Task 10's full-suite run on a machine with no DISPLAY (`env -u DISPLAY`).
- Leaks at exit: scenes built in tests (MultiMesh, atlas texture, ArrayMesh, CanvasLayer) must be freed. Pinned by Task 7 and Task 10 (log lines at most 4 ObjectDB, 2 resources).
- Golden hash and Rust untouched: pinned by Task 10 (`git diff --stat d81deab..HEAD -- crates/` empty, `cargo test -p rts-core golden_hash_pins_cross_target_determinism --offline` passes).
- Picking after north-up and big models: every `construction_zone` tile must still pick itself (`picked_x/picked_y` in the observation) at zoom 7.5, 10 and 18; a click on a big CC model's overhang hits the tile under the cursor, not the CC. Pinned by Task 2 and Task 9 harness steps.
- Map edge: at max zoom on all four corners no sky, void or cliff shows. Pinned by Task 2 (pure clamp math test plus four corner frames).

---

## Precondition (controller, before Task 1)

- `git status --short` shows `M tools/qa/ui_driver.gd` (182 lines of perf/sections/tweak events from the perf agent). This plan never edits or stages it; Task 1 subclasses it instead. If the perf agent's commit lands first, nothing changes. If `ui_driver.gd` is renamed or its `_execute(action: Dictionary)` signature changes, stop and re-read Task 1 Step 3 against it.
- Baseline commit for diffs: `d81deab` (HEAD when this plan was written).

## File Structure

New, Godot (`godot3d/`):
- `scripts/world/world_art.gd` - the profile: constant tables (camera, environment, model widths, palette) and pure static helpers (focus clamp, view footprint, hex outline mesh, model fit). No scene access.
- `scripts/world/world_props.gd` - deterministic prop planning (pure static `plan`) plus the two MultiMesh nodes (cards, decals), `clear_around`, pad slots.
- `assets/world/props_atlas.png`, `assets/world/props_atlas.json` - baked by `tools/ui/build_prop_atlas.py` from the game's own sprites.
- `tests/test_world_art.gd`, `tests/test_world_art_survival.gd`, `tests/test_world_props.gd`, `tests/test_world_water.gd`, `tests/test_world_models.gd`.

Modified, Godot:
- `scripts/earthfront_3d.gd` - `world_art_on` gate, `_apply_world_art`, camera, hover, deposits, buildings, units, selection ring.
- `scripts/continuous_terrain.gd` - edge continuation, margin, extra channels (UV, UV2), painted ground and water shader.
- `tests/test_ground_model.gd` - re-pinned GROUND_LOOK values (Task 5).

New, tools:
- `tools/qa/world_driver.gd` - extends `ui_driver.gd` with `world_shot` and `probe` events (presentation only).
- `tools/qa/world_capture.py` - launches an isolated harness, deploys, shoots the frames, kills its own PIDs.
- `tools/ui/world_diff.py`, `tools/ui/test_world_diff.py` - scorer, swatches, yellow-blob finder, side-by-side PNG.
- `tools/ui/world_frames.json` - live frames, board crops and masks, swatch tiles, mock palette.
- `tools/ui/world_baseline.json` (frozen after Task 1), `tools/ui/world_scores.json` (rolling, updated by each art task).
- `tools/ui/gameplay-blob-map.json` - the 30 gameplay sprite blobs (so boards render with sprites).
- `tools/ui/build_prop_atlas.py`, `tools/ui/test_build_prop_atlas.py`.

Modified, tools: `tools/ui/mockkit.py` (merge the gameplay blob map), `tools/qa/launch_ui.py` (`--display`, `--driver`).

Docs (Task 11): `docs/ascension/ui-deviations.md`, `docs/ascension/ui-mocks-gameplay/README.md`.

---

### Task 1: QA world tooling and the baseline

**Files:**
- Create: `tools/ui/gameplay-blob-map.json`, `tools/ui/world_diff.py`, `tools/ui/test_world_diff.py`, `tools/ui/world_frames.json`, `tools/ui/world_baseline.json`, `tools/ui/world_scores.json`, `tools/qa/world_driver.gd`, `tools/qa/world_capture.py`
- Modify: `tools/ui/mockkit.py:54` (blob map merge), `tools/qa/launch_ui.py` (`--display`, `--driver`)

**Interfaces:**
- Consumes: `tools/qa/ui_driver.gd` fields `game`, `qa_dir`, `busy`, `last_id`, `root`, methods `_execute(action)`, `_observe()`; game members `camera`, `camera_target`, `camera_focus_target`, `camera_zoom`, `camera_focus_zoom`, `camera_cinematic`, `hover_tile`, `_hex_world(x, z)`, `_height_world(x, z)`, `_update_camera()`, `home_focus()`.
- Produces:
  - World driver events (each sent in its own action): `{"type": "world_shot", "name": str, "tile": [x, y] | "focus": "home", "zoom": float, "swatches": {glyph: [x, y]}}` writes `<qa>/<name>.png` (HUD hidden, hover hidden, atmosphere kept) and `<qa>/<name>.json` `{"camera": {...}, "swatches": {glyph: [sx, sy, on_screen]}, "fps", "draw_calls", "primitives", "process_ms"}`. `{"type": "probe", "name": str, "x": float, "y": float}` or `{"type": "probe", "name": str, "node": str}` writes `<qa>/<name>.json` `{"hits": [{"path", "class", "rect": [x, y, w, h], "area", "colour", "transparent", "unshaded"}]}` sorted by area, largest first.
  - `world_capture.py <qa_dir> [--scenario kestrel|survival] [--only a,b] [--display :94] [--gpu] [--perf SECONDS]` -> PNG plus JSON per frame in `<qa_dir>`.
  - `world_diff.py pair|run|blobs` (see Step 1 code); score dict keys `total, palette, saturation, detail, clutter, warmth, raw`.
  - Canvas nodes that must survive `world_shot` carry `set_meta("world_art", true)`.

- [ ] **Step 1: Write the failing scorer tests**

`tools/ui/test_world_diff.py`:

```python
"""Unit tests for world_diff: synthetic images only, no Godot, no Chrome."""
import json, pathlib, tempfile, unittest
import numpy as np
from PIL import Image
import world_diff as wd


def olive_texture(w=320, h=200, seed=1):
    rng = np.random.default_rng(seed)
    base = np.array([0x80, 0x88, 0x44], float)
    noise = rng.normal(0, 12, (h, w, 1))
    return np.clip(base + noise, 0, 255).astype(np.uint8)


def flat(w, h, hexcol):
    c = [int(hexcol[i:i + 2], 16) for i in (0, 2, 4)]
    return np.tile(np.array(c, np.uint8), (h, w, 1))


class ScoreTests(unittest.TestCase):
    def test_identical_images_score_100(self):
        img = olive_texture()
        s = wd.score(wd.stats(img, None), wd.stats(img, None))
        self.assertGreaterEqual(s["total"], 99.5)

    def test_flat_saturated_green_scores_far_below_olive(self):
        mock = olive_texture()
        live = flat(320, 200, "246c07")
        s = wd.score(wd.stats(mock, None), wd.stats(live, None))
        self.assertLess(s["total"], 60)
        for key in ("palette", "saturation", "detail"):
            self.assertGreater(s[key], 0, key)

    def test_mask_excludes_pixels(self):
        mock = olive_texture()
        dirty = mock.copy()
        dirty[20:80, 20:120] = (255, 0, 255)
        mask = wd.rect_mask(mock.shape, [[20, 20, 120, 80]])
        a = wd.score(wd.stats(mock, None), wd.stats(mock, None))["total"]
        b = wd.score(wd.stats(dirty, mask), wd.stats(mock, mask))["total"]
        self.assertAlmostEqual(a, b, delta=0.6)

    def test_delta_e_white_black_is_100(self):
        self.assertAlmostEqual(wd.delta_e("ffffff", "000000"), 100.0, delta=0.01)
        self.assertAlmostEqual(wd.delta_e("808844", "808844"), 0.0, delta=1e-6)

    def test_yellow_blobs_finds_big_yellow_only(self):
        img = olive_texture()
        img[40:80, 40:80] = (240, 190, 74)     # 1600 px amber, like the hover torus colour f0be4a
        img[150:160, 200:210] = (240, 190, 74)  # 100 px, below min_area
        blobs = wd.yellow_blobs(img, min_area=400)
        self.assertEqual(len(blobs), 1)
        self.assertEqual((blobs[0]["x"], blobs[0]["y"], blobs[0]["w"], blobs[0]["h"]), (40, 40, 40, 40))

    def test_side_by_side_writes_png(self):
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d) / "side.png"
            wd.side_by_side(olive_texture(), flat(320, 200, "246c07"), wd.rect_mask((200, 320, 3), [[0, 0, 10, 10]]), out, "gp01 home 42.0")
            im = Image.open(out)
            self.assertEqual(im.size, (640 + 12, 200 + 28))

    def test_swatches_reports_delta_e_per_glyph(self):
        live = flat(200, 200, "808844")
        res = wd.swatches(live, {"g": [100, 100, True], "o": [5000, 5000, False]}, {"g": "808844", "o": "133a51"})
        self.assertLess(res["g"]["de"], 0.5)
        self.assertNotIn("o", res)  # off-screen swatches are skipped, never guessed


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd tools/ui && python3 -m unittest test_world_diff -v`
Expected: `ModuleNotFoundError: No module named 'world_diff'`.

- [ ] **Step 3: Implement `world_diff.py`**

```python
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
```

Note the yellow test colour `(240, 190, 74)` has hue 41, S 0.69, V 0.94, so it is found; olive `808844` has V 0.53 and is not.

- [ ] **Step 4: Run the scorer tests**

Run: `cd tools/ui && python3 -m unittest test_world_diff -v`
Expected: 7 tests, OK. If `test_flat_saturated_green_scores_far_below_olive` fails on `detail` being 0, check the `_log_ratio` floor: a flat image has detail 0 and the penalty must saturate at 15.

- [ ] **Step 5: Boards render with their sprites**

Write `tools/ui/gameplay-blob-map.json` with exactly these 30 entries (blob id to file under repo `assets/`, matched by SHA-256 of the canvas assets on 2026-10-05):

```json
{
 "004852755ece3a8e81b95a9e93489852": "anti_armor_v2.png",
 "0c1162f156a5a2751d5e1bf04d886a38": "alien_anti_armor_v1.png",
 "0cff440ac0f27a92e113ec4de32ee9a8": "infantry_v2.png",
 "10188eed0323bf70c0aa84a87d3bbcb9": "alien_infantry_v1.png",
 "318ba1a2dd09b4736f000e8ba021bf70": "aa_turret_v2.png",
 "439ac4aa47c8b40430b3ce1b7550277d": "harvester_v2.png",
 "508d97c7b872d6502bb31b3fe2de001c": "gun_turret_v2.png",
 "5424ebd27e4afeb6edf08fa6c06bfcda": "rock_cluster_v1.png",
 "5828f353f51d19ec36c3c638831bfb96": "command_center_v2.png",
 "6c29c5788f12d88cfae3914221f234a9": "refinery_v2.png",
 "7290d27eb185c00fe39d20c0df565b94": "alien_helicopter_v1.png",
 "73037d5e6ad6e787627e98ef11935b3c": "alien_tank_v1.png",
 "78e61f98c011d522897cd27a878b8b66": "alien_capital_v1.png",
 "87aab1971d525ecad863691237ae2a71": "tank_v2.png",
 "8ca8156819c69b8820bad06f2c16b569": "alien_power_plant_v1.png",
 "8cb9cb29d95752ec982142bf671a1e6d": "capital_v1.png",
 "991214c0cce9696bd809eb293c3b9804": "wrecked_car_v1.png",
 "992e20da27a46fee7526831f11ebecff": "alien_gun_turret_v1.png",
 "a208753ee858587a05fa96e19584d2f8": "wall_v2.png",
 "a2f24d2a3b0741c42aa6cda8914ef309": "alien_wall_v1.png",
 "a4eaf3d750fb4f6ea76eabd82202f198": "alien_aa_turret_v1.png",
 "b32b316f8a54cfb3e4e96b8ab7a2f79e": "power_plant_v2.png",
 "b68e987fd5fe7400ef76a4e86344f108": "floodlight_v1.png",
 "bbb3bae9af99ea696ff5f34401784754": "foundation_v1.png",
 "c28b4de3839198732e73d3041feec1e6": "barracks_v2.png",
 "da391d1df1491ea1875475d3e439e791": "sandbags_v1.png",
 "dd84ec04431e6bc7a5bbc71c8d82019f": "concrete_barriers_v1.png",
 "df45512203a3212ed1030c81c397e959": "helicopter_v2.png",
 "ecef6e4a5fce7ea118d71be333bc0d36": "crater_v1.png",
 "f7ec8be19aeb99fc5975b38136419d82": "ore_crystals_v1.png"
}
```

In `tools/ui/mockkit.py` `prepare()`, replace the `blob = json.loads(...)` line with:

```python
    blob = json.loads((MOCKS / "blob-map.json").read_text())
    if gameplay:
        blob.update(json.loads((HERE / "gameplay-blob-map.json").read_text()))
```

Verify every value exists: `python3 -c "import json,os;m=json.load(open('tools/ui/gameplay-blob-map.json'));print(all(os.path.exists('assets/'+v) for v in m.values()), len(m))"` prints `True 30`.

Render the boards: `for b in gp01 gp03 gp04 gp05 gp06 gp07 gp08; do python3 tools/ui/render_mock.py $b $SCRATCH/world/mocks/$b.png; done`. Open `gp01.png` and check by eye: the command center, tanks and infantry sprites are visible (before this step they were broken images).

Run the chrome regression that uses mockkit: `bash tools/ui/verify_all.sh` must report the same chrome numbers as before this edit (the merge only fills previously blank gameplay sprites, and the battlefield is masked in every `compare_gp*.json`). If a gameplay chrome number moves by more than 0.1, stop and report it.

- [ ] **Step 6: The world driver**

`tools/qa/world_driver.gd` (a subclass, so the uncommitted `ui_driver.gd` is never edited):

```gdscript
extends "ui_driver.gd"
## QA world driver: ui_driver plus two presentation-only events for world-art captures. It moves the camera and hides
## canvas layers for one frame; it never sends a game command or changes simulation state.
## Events must be sent in their own action: {"events": [{"type": "world_shot", ...}]}.

const WORLD_EVENTS := ["world_shot", "probe"]


func _execute(action: Dictionary) -> void:
	var events: Array = action.get("events", [])
	var mine := events.filter(func(e): return String(e.get("type", "")) in WORLD_EVENTS)
	if mine.is_empty():
		await super._execute(action)
		return
	for item in events:
		match String(item.get("type", "")):
			"world_shot":
				await _world_shot(item)
			"probe":
				_probe(item)
			_:
				push_error("world_driver: mix world events with other events in separate actions")
	last_id = int(action.id)
	busy = false
	_observe()


func _world_shot(item: Dictionary) -> void:
	var focus: Vector3 = game.home_focus() if String(item.get("focus", "")) == "home" else game._hex_world(int(item.tile[0]), int(item.tile[1]))
	var zoom := float(item.get("zoom", game.camera_focus_zoom))
	var centre := root.get_visible_rect().size * 0.5
	root.warp_mouse(centre)  # off the edge-scroll band
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	root.push_input(motion, true)
	game.camera_cinematic = 0.0
	game.camera_focus_target = focus
	game.camera_target = focus
	game.camera_focus_zoom = zoom
	game.camera_zoom = zoom
	for _i in 12:
		await process_frame
	var hidden: Array = []
	for layer in game.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not layer.get_meta("world_art", false):
			layer.visible = false
			hidden.append(layer)
	var hover_was: bool = game.hover_tile.visible if is_instance_valid(game.hover_tile) else false
	if is_instance_valid(game.hover_tile):
		game.hover_tile.visible = false
	await process_frame
	RenderingServer.force_draw(false)
	var name := String(item.get("name", "world"))
	root.get_texture().get_image().save_png(qa_dir.path_join(name + ".png"))
	var points := {}
	var sw: Dictionary = item.get("swatches", {})
	for glyph in sw:
		var w: Vector3 = game._hex_world(int(sw[glyph][0]), int(sw[glyph][1]))
		w.y = game._height_world(w.x, w.z)
		var on := not game.camera.is_position_behind(w)
		var p: Vector2 = game.camera.unproject_position(w)
		points[glyph] = [p.x, p.y, on and root.get_visible_rect().has_point(p)]
	var data := {"camera": {"yaw": game.camera_yaw, "zoom": game.camera_zoom, "focus": [game.camera_target.x, game.camera_target.z]},
		"swatches": points, "fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0}
	FileAccess.open(qa_dir.path_join(name + ".json"), FileAccess.WRITE).store_string(JSON.stringify(data))
	for layer in hidden:
		layer.visible = true
	if is_instance_valid(game.hover_tile):
		game.hover_tile.visible = hover_was


func _screen_rect(g: GeometryInstance3D) -> Rect2:
	var box: AABB = g.get_aabb()
	var rect := Rect2()
	var first := true
	for i in 8:
		var corner: Vector3 = g.global_transform * box.get_endpoint(i)
		if game.camera.is_position_behind(corner):
			return Rect2()
		var p: Vector2 = game.camera.unproject_position(corner)
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	return rect


func _colour_of(g: GeometryInstance3D) -> Dictionary:
	var mat: Material = g.material_override
	if mat == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		mat = (g as MeshInstance3D).get_active_material(0)
	if mat is StandardMaterial3D:
		var s := mat as StandardMaterial3D
		return {"colour": s.albedo_color.to_html(true), "transparent": s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			"unshaded": s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED}
	return {"colour": "shader" if mat is ShaderMaterial else "none", "transparent": false, "unshaded": false}


func _probe(item: Dictionary) -> void:
	var hits: Array = []
	var scope: Node = game
	if item.has("node"):
		scope = game.find_child(String(item.node), true, false)
		if scope == null:
			hits.append({"error": "no node " + String(item.node)})
	if scope != null:
		var point := Vector2(float(item.get("x", 0)), float(item.get("y", 0)))
		for n in scope.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree():
				continue
			var rect := _screen_rect(g)
			if rect.get_area() <= 0.0 or (not item.has("node") and not rect.has_point(point)):
				continue
			var hit := {"path": String(game.get_path_to(g)), "class": g.get_class(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "area": rect.get_area()}
			hit.merge(_colour_of(g))
			hits.append(hit)
	hits.sort_custom(func(a, b): return float(a.get("area", 0)) > float(b.get("area", 0)))
	FileAccess.open(qa_dir.path_join(String(item.get("name", "probe")) + ".json"), FileAccess.WRITE).store_string(JSON.stringify({"hits": hits}))
```

In `tools/qa/launch_ui.py`, add after the `scenario=` line:

```python
display=sys.argv[sys.argv.index('--display')+1] if '--display' in sys.argv else ':93'
driver='world_driver.gd' if '--driver' in sys.argv and sys.argv[sys.argv.index('--driver')+1]=='world' else 'ui_driver.gd'
```

replace ` display=':93'` with nothing (the variable now comes from above) and `str(root/'tools/qa/ui_driver.gd')` with `str(root/'tools/qa'/driver)`. Update the docstring usage line to `launch_ui.py <dir> [--software] [--scenario kestrel|survival] [--display :NN] [--driver world]`.

- [ ] **Step 7: The capture script**

`tools/qa/world_capture.py`:

```python
"""Capture world-only frames from an isolated harness for world_diff. Kills only the PIDs it started.
Usage: world_capture.py <qa_dir> [--scenario kestrel|survival] [--only a,b] [--display :94] [--gpu] [--perf SECONDS]"""
import json, os, pathlib, signal, subprocess, sys, time
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from ui_client import UI


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    qa = pathlib.Path(sys.argv[1]).resolve()
    scenario = arg("--scenario", "kestrel")
    cfg = json.loads((ROOT / "tools/ui/world_frames.json").read_text())
    frames = cfg["live"][scenario]
    only = arg("--only")
    if only:
        frames = {k: v for k, v in frames.items() if k in only.split(",")}
    cmd = [sys.executable, str(HERE / "launch_ui.py"), str(qa), "--scenario", scenario, "--driver", "world"]
    if "--gpu" not in sys.argv:
        cmd += ["--software", "--display", arg("--display", ":94")]
    subprocess.run(cmd, check=True)
    pids = json.loads((qa / "pids.json").read_text())
    try:
        ui = UI(qa)
        deadline = time.monotonic() + 120
        while not (qa / "observation.json").exists():
            if time.monotonic() > deadline:
                raise SystemExit("no observation after 120 s; see " + str(qa / "godot.log"))
            time.sleep(1)
        ui.button("New operation", soft=True)
        time.sleep(2)
        ui.button("Deploy forces", soft=True)
        time.sleep(6)
        for name, f in frames.items():
            event = {"type": "world_shot", "name": name, "zoom": f["zoom"], "swatches": f.get("swatches", {})}
            if "tile" in f:
                event["tile"] = f["tile"]
            else:
                event["focus"] = "home"
            ui.send(event, timeout=120)
            print(name, json.loads((qa / f"{name}.json").read_text())["draw_calls"])
        seconds = float(arg("--perf", "0"))
        if seconds > 0:
            samples = []
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                o = ui.observe()
                samples.append({"fps": o["fps"], "process_ms": o["process_ms"], "draw_calls": o["draw_calls"]})
                time.sleep(0.5)
            (qa / "perf.json").write_text(json.dumps(samples))
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


if __name__ == "__main__":
    main()
```

If `ui.button("Deploy forces", soft=True)` finds no such button (a quick start deploys straight after "New operation"), that is fine: `soft=True` does not raise.

- [ ] **Step 8: Frames, crops and palette**

`tools/ui/world_frames.json` (tiles from `godot3d/tests/fixtures/kestrel_snapshot.json`: human CC at (7, 9), alien core at (37, 8), ford (22, 10), craters (33, 12) and (35, 15); palette = land.jpg medians measured 2026-10-05):

```json
{
 "noise": 0.0,
 "palette": {"g": "808844", "m": "848948", "f": "ac965e", "h": "888680", "s": "b9a373", "o": "133a51", "r": "3a6c81"},
 "live": {
  "kestrel": {
   "home":   {"focus": "home", "zoom": 8.8, "swatches": {"g": [2, 8], "m": [4, 13]}},
   "ford":   {"tile": [22, 10], "zoom": 8.8, "swatches": {"g": [16, 10], "f": [28, 10], "r": [24, 11]}},
   "flats":  {"tile": [32, 12], "zoom": 8.8, "swatches": {"f": [30, 10], "h": [32, 4]}},
   "bay":    {"tile": [37, 21], "zoom": 8.8, "swatches": {"o": [40, 22], "s": [31, 23], "f": [33, 17]}},
   "forest": {"tile": [8, 19], "zoom": 8.8, "swatches": {"g": [2, 20]}},
   "enemy":  {"tile": [37, 8], "zoom": 8.8, "swatches": {"f": [36, 10], "h": [36, 3]}},
   "max":    {"tile": [21, 12], "zoom": 24.0},
   "corner_nw": {"tile": [0, 0], "zoom": 24.0},
   "corner_se": {"tile": [43, 25], "zoom": 24.0}
  },
  "survival": {
   "survival_home": {"focus": "home", "zoom": 8.8}
  }
 },
 "boards": {
  "gp01": {"frame": "home",  "crop": [340, 70, 1540, 740], "mask": []},
  "gp03": {"frame": "enemy", "crop": [360, 70, 1540, 740], "mask": []},
  "gp04": {"frame": "home",  "crop": [350, 70, 1560, 740], "mask": [[980, 520, 1280, 680]]},
  "gp05": {"frame": "ford",  "crop": [140, 130, 1500, 740], "mask": [[1180, 420, 1510, 610]]},
  "gp06": {"frame": "home",  "crop": [360, 70, 1540, 740], "mask": []},
  "gp07": {"frame": "ford",  "crop": [350, 70, 1540, 740], "mask": []},
  "gp08": {"frame": "home",  "crop": [360, 70, 1420, 740], "mask": []}
 }
}
```

The zooms (8.8 and 24) are today's values so the baseline is captured on today's framing. Task 2 changes them to the new defaults (10.0 and 18.0) in the same commit that changes the camera.

Check the crops by eye: render `python3 tools/ui/world_diff.py pair $SCRATCH/world/mocks/gp03.png $SCRATCH/world/mocks/gp03.png --crop 360,70,1540,740 --out $SCRATCH/world/crop_gp03.png` and the same for gp06; open both PNGs. Any HUD panel, tooltip or chip larger than about 80x40 px inside the crop gets a `mask` rect (board pixels) in `world_frames.json`. Do the same check for the other five boards.

- [ ] **Step 9: Capture the baseline and measure noise**

```bash
python3 tools/qa/world_capture.py $SCRATCH/world/base1 --display :94
python3 tools/qa/world_capture.py $SCRATCH/world/base2 --display :94
python3 tools/qa/world_capture.py $SCRATCH/world/surv --scenario survival --display :94
grep -c "SCRIPT ERROR\|SHADER ERROR" $SCRATCH/world/base1/godot.log   # expect 0
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/base1 --out $SCRATCH/world/side_base1 --write $SCRATCH/world/base1.json
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/base2 --out $SCRATCH/world/side_base2 --write $SCRATCH/world/base2.json
```

Set `"noise"` in `world_frames.json` to the largest per-board `|total(base1) - total(base2)|`, rounded up to 0.1. Copy `base1.json` to `tools/ui/world_baseline.json` and to `tools/ui/world_scores.json`, then add top-level `"_perf"` to the baseline: `{"home": {"draw_calls": ..., "primitives": ..., "process_ms": ...}, "max": {...}}` from `base1/home.json` and `base1/max.json` (software numbers; Task 10 adds GPU numbers if the controller approves a GPU run). Keep `$SCRATCH/world/surv/survival_home.png` for Task 10. Record the headless suite's pass count and leak lines: `$TESTS 2>&1 | tail -5`.

Open `side_gp01.png` and `side_gp05.png`: the left half is the board battlefield with sprites, the right half today's live world without HUD.

- [ ] **Step 10: Commit**

```bash
git add tools/ui/gameplay-blob-map.json tools/ui/mockkit.py tools/ui/world_diff.py tools/ui/test_world_diff.py tools/ui/world_frames.json tools/ui/world_baseline.json tools/ui/world_scores.json tools/qa/world_driver.gd tools/qa/world_capture.py tools/qa/launch_ui.py
git commit -m "QA: world-only captures, world_diff scorer and the Kestrel world-art baseline"
```

Report the baseline totals per board, the noise value and the suite pass count to the controller.

---

### Task 2: WorldArt profile, north-up camera, focus clamp, map-edge continuation

**Files:**
- Create: `godot3d/scripts/world/world_art.gd`, `godot3d/tests/test_world_art.gd`, `godot3d/tests/test_world_art_survival.gd`
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_build_terrain` 365, `_sync_ground` 426, `_update_camera_controls` 1171, wheel zoom 1224-1226, zoom literals 1314/1318, `_deploy_mission` 2620), `godot3d/scripts/continuous_terrain.gd` (`RASTER_MARGIN`, `_blend_cells`, `_build_surface`), `tools/ui/world_frames.json` (zooms), `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: Task 1 tooling.
- Produces (later tasks rely on these exact names):
  - `const WorldArt := preload("res://scripts/world/world_art.gd")` with `TILE := 0.68`, `PITCH_SIN := 0.839`, `TERRAIN_MARGIN_CELLS := 9`, `CAMERA := {"yaw": 0.0, "default_zoom": 10.0, "deploy_from": 15.5, "min_zoom": 7.5, "max_zoom": 18.0, "edge_cells": 8}`, `static func active(model) -> bool`, `static func view_half_extent(zoom: float, aspect: float, yaw: float) -> Vector2`, `static func world_bounds(map_w: int, map_h: int, origin_x: float, origin_z: float, hex_x: float, hex_z: float, cells: int) -> Rect2`, `static func clamp_focus(focus: Vector3, zoom: float, aspect: float, yaw: float, bounds: Rect2) -> Vector3`.
  - On the game (`earthfront_3d.gd`): `var world_art_on := false`, `var ocean_box: MeshInstance3D`, `func _apply_world_art(snapshot: Dictionary) -> void` (later tasks append to it), `func _zoom_limits() -> Vector2`, `func _zoom_default() -> float`.
  - On the terrain: `var edge_margin_cells := 4.0` (9.0 after `apply_ground`), off-map cells read the nearest on-map cell.

- [ ] **Step 1: Write the failing tests**

`godot3d/tests/test_world_art.gd`:

```gdscript
extends RefCounted
## The Kestrel world-art profile (spec addendum W1 to W3): gate, north-up camera, focus clamp, map-edge continuation.
const WorldArt := preload("res://scripts/world/world_art.gd")
const MainScene = preload("res://main.tscn")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


## Built like test_lighting: the scene never enters the tree (the runner is mid-_initialize).
func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	scene._sync_ground(_snap())
	return scene


func _bounds(scene) -> Rect2:
	return WorldArt.world_bounds(scene.MAP_W, scene.MAP_H, scene.MAP_ORIGIN_X, scene.MAP_ORIGIN_Z, scene.HEX_X, scene.HEX_Z, int(WorldArt.CAMERA.edge_cells))


func test_kestrel_switches_the_profile_on(t) -> void:
	var scene := _kestrel_scene()
	t.ok(scene.world_art_on, "a real ground layer turns the profile on")
	t.near(scene.camera_yaw, 0.0, 0.0001, "north-up camera")
	t.eq(scene._zoom_limits(), Vector2(7.5, 18.0), "zoom range 7.5 to 18")
	t.near(scene._zoom_default(), 10.0, 0.0001, "default zoom 10")
	t.ok(not scene.ocean_box.visible, "the legacy ocean box is hidden; the terrain draws the sea")
	scene.free()


func test_clamp_keeps_every_view_corner_inside_the_bounds(t) -> void:
	var bounds := WorldArt.world_bounds(44, 26, 2.1, 1.0, 0.68, 0.70, 8)
	for zoom in [7.5, 10.0, 18.0]:
		for yaw in [0.0, 0.4]:
			for want in [Vector3(-100, 0, -100), Vector3(100, 0, 100), Vector3(-100, 0, 100), Vector3(17, 0, 9)]:
				var f := WorldArt.clamp_focus(want, zoom, 16.0 / 9.0, yaw, bounds)
				var e := WorldArt.view_half_extent(zoom, 16.0 / 9.0, yaw)
				t.ok(f.x - e.x >= bounds.position.x - 0.001 and f.x + e.x <= bounds.end.x + 0.001, "x inside at zoom %s yaw %s" % [zoom, yaw])
				t.ok(f.z - e.y >= bounds.position.y - 0.001 and f.z + e.y <= bounds.end.y + 0.001, "z inside at zoom %s yaw %s" % [zoom, yaw])


func test_clamp_centres_a_view_wider_than_the_bounds(t) -> void:
	var small := Rect2(0, 0, 4, 4)
	var f := WorldArt.clamp_focus(Vector3(50, 0, -50), 18.0, 16.0 / 9.0, 0.0, small)
	t.near(f.x, 2.0, 0.001, "centred in x")
	t.near(f.z, 2.0, 0.001, "centred in z")


func test_south_row_can_sit_above_the_bottom_hud(t) -> void:
	var bounds := WorldArt.world_bounds(44, 26, 2.1, 1.0, 0.68, 0.70, 8)
	var tile_z := 1.0 + 25.0 * 0.70 + 0.35  # tile (21, 25), odd column
	var f := WorldArt.clamp_focus(Vector3(2.1 + 21.0 * 0.68, 0, tile_z), 10.0, 16.0 / 9.0, 0.0, bounds)
	var screen_y := 540.0 + (tile_z - f.z) * WorldArt.PITCH_SIN * 1080.0 / 10.0
	t.ok(screen_y <= 1080.0 - 320.0, "the south row reaches above the deck (y %s)" % screen_y)


func test_sun_shadows_fall_screen_right_and_down_north_up(t) -> void:
	var scene := _kestrel_scene()
	var sun: DirectionalLight3D = null
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled:
			sun = n
	var travel := -sun.transform.basis.z
	var yaw: float = scene.camera_yaw
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var down := Vector3(sin(yaw), 0, cos(yaw))
	t.ok(travel.dot(right) > 0.1 and travel.dot(down) > 0.1, "drop shadows go lower-right like the boards")
	scene.free()


func test_off_map_ground_continues_the_edge_cell(t) -> void:
	var scene := _kestrel_scene()
	var terrain = scene.terrain_renderer
	var west := terrain.height_at_world(2.1 - 6.0 * 0.68, 1.0 + 10.0 * 0.70)  # 6 cells west of grass (0, 10)
	var south_east := terrain.height_at_world(2.1 + 49.0 * 0.68, 1.0 + 22.0 * 0.70)  # 6 cells east of sea (43, 22)
	t.ok(west > -0.1, "land continues past the west edge (%s)" % west)
	t.ok(south_east < -0.4, "sea continues past the sea edge (%s)" % south_east)
	t.near(terrain.edge_margin_cells, 9.0, 0.001, "the mesh reaches 9 cells past the map")
	scene.free()
```

`godot3d/tests/test_world_art_survival.gd`:

```gdscript
extends RefCounted
## Survival never builds a ground model, so it keeps every legacy world value. Each world-art task adds its own lines here.
const MainScene = preload("res://main.tscn")


func _survival_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	snap["ground"] = "g".repeat(44 * 26)
	scene._sync_ground(snap)
	return scene


func test_survival_keeps_the_legacy_camera(t) -> void:
	var scene := _survival_scene()
	t.ok(not scene.world_art_on, "no profile without a real ground layer")
	t.near(scene.camera_yaw, -0.68, 0.0001, "rotated legacy camera")
	t.eq(scene._zoom_limits(), Vector2(7.5, 24.0), "legacy zoom range")
	t.near(scene._zoom_default(), 8.8, 0.0001, "legacy default zoom")
	t.ok(scene.ocean_box.visible, "legacy ocean box")
	t.near(scene.terrain_renderer.edge_margin_cells, 4.0, 0.001, "legacy noise mesh margin")
	scene.free()
```

- [ ] **Step 2: Run them to see them fail**

Run: `$TESTS -- test_world_art`
Expected: FAIL (`world_art.gd` missing: parse error on preload).

- [ ] **Step 3: Implement `world_art.gd`**

```gdscript
extends RefCounted
## Kestrel world-art profile (spec addendum 2026-10-05, W1 to W9): constant tables and pure helpers. No scene access;
## earthfront_3d.gd applies them only when `world_art_on` is true.

const TILE := 0.68  # one hex column in world units; land.jpg maps one column to 82 px
const PITCH_SIN := 0.839  # 1.05 / sqrt(1.05^2 + 0.68^2): the camera rig in earthfront_3d._update_camera
const TERRAIN_MARGIN_CELLS := 9
const CAMERA := {"yaw": 0.0, "default_zoom": 10.0, "deploy_from": 15.5, "min_zoom": 7.5, "max_zoom": 18.0, "edge_cells": 8}


static func active(model) -> bool:
	return model != null


## Half size (x, z) of the axis-aligned ground box that holds the four corners of an orthographic view on y = 0.
static func view_half_extent(zoom: float, aspect: float, yaw: float) -> Vector2:
	var half_w := zoom * aspect * 0.5
	var half_d := zoom * 0.5 / PITCH_SIN
	var right := Vector2(cos(yaw), -sin(yaw))
	var toward_camera := Vector2(sin(yaw), cos(yaw))
	return Vector2(absf(right.x) * half_w + absf(toward_camera.x) * half_d, absf(right.y) * half_w + absf(toward_camera.y) * half_d)


## The ground the camera may show: the map plus `cells` hex cells on every side (x in position.x, z in position.y).
static func world_bounds(map_w: int, map_h: int, origin_x: float, origin_z: float, hex_x: float, hex_z: float, cells: int) -> Rect2:
	var x0 := origin_x - float(cells) * hex_x
	var z0 := origin_z - float(cells) * hex_z
	return Rect2(x0, z0, float(map_w - 1 + 2 * cells) * hex_x, float(map_h - 1 + 2 * cells) * hex_z + hex_z * 0.5)


static func clamp_focus(focus: Vector3, zoom: float, aspect: float, yaw: float, bounds: Rect2) -> Vector3:
	var e := view_half_extent(zoom, aspect, yaw)
	return Vector3(_clamp_axis(focus.x, e.x, bounds.position.x, bounds.end.x), focus.y, _clamp_axis(focus.z, e.y, bounds.position.y, bounds.end.y))


static func _clamp_axis(value: float, half: float, lo: float, hi: float) -> float:
	if hi - lo <= 2.0 * half:
		return (lo + hi) * 0.5
	return clampf(value, lo + half, hi - half)
```

- [ ] **Step 4: Edge continuation in the terrain**

In `continuous_terrain.gd`:
- Add `var edge_margin_cells := 4.0` next to `var ground`.
- Change `const RASTER_MARGIN := 5.0` to `const RASTER_MARGIN := 10.0` (the raster only exists with a ground model, so Survival is unaffected).
- In `apply_ground`, before `_bake_ground()`: `edge_margin_cells = 9.0`.
- In `_build_surface`, replace the four `4.0` literals with `edge_margin_cells` (`var min_gx := -edge_margin_cells` and so on).
- In `_blend_cells`, replace the off-map branch: instead of the sea look, read the nearest on-map cell:

```gdscript
			var cc := clampi(c, 0, map_width - 1)
			var rr := clampi(r, 0, map_height - 1)
			var i := rr * map_width + cc
			h = _cell_h[i]
			amp = _cell_amp[i]
			color = _cell_color[i]
			wet = _cell_wet[i]
```

(drop the `if c < 0 or ...` split; every cell goes through the clamped read) and update the doc comment: "Off-map cells continue the nearest edge cell, so land and sea run past the frame (spec addendum W3)."

- [ ] **Step 5: Gate and camera in `earthfront_3d.gd`**

- Add near the other `const ... := preload(...)` lines: `const WorldArt := preload("res://scripts/world/world_art.gd")`. Add vars: `var world_art_on := false` and `var ocean_box: MeshInstance3D`.
- In `_build_terrain`: `ocean_box = _mesh(ocean, materials.water, Vector3(16.0, -0.48, 9.0))`.
- In `_sync_ground`, after `ground_model = model` and the `MAP_W/MAP_H` lines, keep `terrain_renderer.apply_ground(model)`, then:

```gdscript
	world_art_on = WorldArt.active(model)
	if world_art_on:
		_apply_world_art(snapshot)
	_build_terrain_dressing()
```

- Add:

```gdscript
## Kestrel world-art profile (spec addendum W1 to W9). Runs once, when the first real ground layer arrives.
func _apply_world_art(_snapshot: Dictionary) -> void:
	camera_yaw = float(WorldArt.CAMERA.yaw)
	if is_instance_valid(ocean_box):
		ocean_box.visible = false


func _zoom_limits() -> Vector2:
	return Vector2(WorldArt.CAMERA.min_zoom, WorldArt.CAMERA.max_zoom) if world_art_on else Vector2(7.5, 24.0)


func _zoom_default() -> float:
	return float(WorldArt.CAMERA.default_zoom) if world_art_on else 8.8
```

- Wheel zoom (lines 1224/1226): `camera_focus_zoom = maxf(_zoom_limits().x, camera_focus_zoom - 1.25)` and `camera_focus_zoom = minf(_zoom_limits().y, camera_focus_zoom + 1.25)`.
- Lines 1314/1318: `8.2` becomes `_zoom_default() - 0.6`, `8.8` becomes `_zoom_default()`.
- `_deploy_mission`: `camera_zoom = WorldArt.CAMERA.deploy_from if world_art_on else 15.5` and `camera_focus_zoom = _zoom_default()`.
- `_update_camera_controls`: replace the two `camera_focus_target.x/z = clampf(...)` lines with:

```gdscript
	if world_art_on:
		var aspect := get_viewport().get_visible_rect().size.aspect()
		var bounds := WorldArt.world_bounds(MAP_W, MAP_H, MAP_ORIGIN_X, MAP_ORIGIN_Z, HEX_X, HEX_Z, int(WorldArt.CAMERA.edge_cells))
		camera_focus_target = WorldArt.clamp_focus(camera_focus_target, maxf(camera_zoom, camera_focus_zoom), aspect, camera_yaw, bounds)
	else:
		camera_focus_target.x = clampf(camera_focus_target.x, MAP_ORIGIN_X, MAP_ORIGIN_X + float(MAP_W - 1) * HEX_X)
		camera_focus_target.z = clampf(camera_focus_target.z, MAP_ORIGIN_Z, MAP_ORIGIN_Z + float(MAP_H - 1) * HEX_Z)
```

- [ ] **Step 6: Run the tests**

Run: `$TESTS -- test_world_art` then the full `$TESTS 2>&1 | tail -5`.
Expected: all pass; total pass count = Task 1 count + the new tests; leak lines unchanged; no `SCRIPT ERROR`. `test_ground_model.gd` still passes (its tests never read off-map heights).

- [ ] **Step 7: Harness check**

In `tools/ui/world_frames.json`, change every Kestrel `"zoom": 8.8` to `10.0` and every `24.0` to `18.0` (Survival keeps 8.8). Then:

```bash
python3 tools/qa/world_capture.py $SCRATCH/world/t2 --display :94
grep -c "SCRIPT ERROR\|SHADER ERROR" $SCRATCH/world/t2/godot.log      # 0
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t2 --out $SCRATCH/world/side_t2 --check tools/ui/world_scores.json
```

Visual checklist (open the PNGs): `home.png` is north-up (river runs top-middle to lower-right like gp01); `max.png`, `corner_nw.png`, `corner_se.png` show no sky, no void and no island cliff, land or sea reaches every frame edge. Picking: in a separate harness run (`launch_ui.py $SCRATCH/world/t2p --software --scenario kestrel --display :94`, deploy, then for zoom 7.5, 10 and 18 send a wheel `click` with button 4/5 until `camera_focus_zoom` matches) every entry of `observation.json["tiles"]` has `picked_x == tx` and `picked_y == ty`; kill that harness's PIDs. Score: framing alone may move totals either way; the check must not FAIL on drops beyond the tolerance for gp01/gp05/gp07 (if it does, report the numbers and side-by-sides instead of tuning).

Write the new scores: rerun the `run` command with `--write tools/ui/world_scores.json`.

- [ ] **Step 8: Commit**

```bash
git add godot3d/scripts/world/world_art.gd godot3d/tests/test_world_art.gd godot3d/tests/test_world_art_survival.gd godot3d/scripts/earthfront_3d.gd godot3d/scripts/continuous_terrain.gd tools/ui/world_frames.json tools/ui/world_scores.json
git commit -m "Godot: Kestrel world-art profile with a north-up clamped camera and land past the map edge"
```

(`git add` the `.uid` files Godot creates next to new scripts, e.g. `godot3d/scripts/world/world_art.gd.uid`, if they appear.)

---

### Task 3: Hover outline and the yellow blob

**Files:**
- Modify: `godot3d/scripts/world/world_art.gd`, `godot3d/scripts/earthfront_3d.gd` (`_apply_world_art`), `godot3d/tests/test_world_art.gd`, `godot3d/tests/test_world_art_survival.gd`

**Interfaces:**
- Consumes: `WorldArt`, `_apply_world_art`, world driver `probe`, `world_diff.py blobs`.
- Produces: `static func hex_outline_mesh(radius_x: float, half_z: float, width: float) -> ArrayMesh`, `static func hover_material() -> StandardMaterial3D` (unshaded, alpha, cyan `6fd6e8` at alpha 0.55, no shadows).

- [ ] **Step 1: Confirm what the user saw (probe before fixing)**

```bash
python3 tools/qa/launch_ui.py $SCRATCH/world/blob --software --scenario kestrel --display :94 --driver world
```

With `ui_client.UI`: "New operation", "Deploy forces" (soft), wait 6 s; read the human CC screen point from `observe()["entities"]` (kind `CommandCenter`, owner 0); send `{"type": "motion", "x": cx, "y": cy}` then `{"type": "capture", "name": "hover_cc"}`; then a grass point 200 px left of the CC: motion + `capture` `hover_grass`; then `{"type": "world_shot", "name": "flats", "tile": [32, 12], "zoom": 10.0}`. For each PNG run `python3 tools/ui/world_diff.py blobs <png> --crop 340,70,1540,740` and for every blob send `{"type": "probe", "name": "blob_<png>_<i>", "x": cx, "y": cy}`. Kill the PIDs in `$SCRATCH/world/blob/pids.json`.

Record which meshes own the blobs (expect `HoverTile`-like torus with colour `f0be4a` on hover captures, `ContinuousTerrainRenderer/ContinuousPainterlyTerrain` with colour `shader` on the flats capture). The flats are fixed by Task 5 (its palette test pins flats saturation); this task fixes the hover marker. If a blob belongs to anything else, report it to the controller before continuing.

- [ ] **Step 2: Write the failing tests**

Append to `godot3d/tests/test_world_art.gd`:

```gdscript
func test_kestrel_hover_is_a_thin_cyan_hex_outline(t) -> void:
	var scene := _kestrel_scene()
	var mesh: Mesh = scene.hover_tile.mesh
	t.ok(not (mesh is TorusMesh), "no amber torus under the profile")
	t.ok(mesh is ArrayMesh and mesh.get_surface_count() == 1, "one outline surface")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	for v in verts:
		widest = maxf(widest, absf(v.x))
	t.ok(widest <= scene.HEX_X / 1.5 + 0.001, "never wider than one hex (%s)" % widest)
	var mat := scene.hover_tile.material_override as StandardMaterial3D
	t.ok(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "unshaded")
	t.ok(mat.albedo_color.b > mat.albedo_color.r and mat.albedo_color.a <= 0.6, "cyan and see-through")
	t.ok(not mat.emission_enabled, "no glow")
	scene.free()


func test_hex_outline_is_a_closed_six_sided_ring(t) -> void:
	var mesh := WorldArt.hex_outline_mesh(0.44, 0.34, 0.035)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.eq(verts.size(), 6 * 6, "six quads, two triangles each")
```

Append to `test_world_art_survival.gd`:

```gdscript
func test_survival_keeps_the_amber_hover_torus(t) -> void:
	var scene := _survival_scene()
	var torus := scene.hover_tile.mesh as TorusMesh
	t.ok(torus != null, "legacy torus")
	t.near(torus.inner_radius, 0.42, 0.0001, "inner")
	t.near(torus.outer_radius, 0.47, 0.0001, "outer")
	scene.free()
```

- [ ] **Step 3: Run them to see them fail**

Run: `$TESTS -- test_world_art`
Expected: FAIL on "no amber torus under the profile" and a missing `hex_outline_mesh`.

- [ ] **Step 4: Implement**

In `world_art.gd`:

```gdscript
## A flat hex ring on y = 0: outer corners (+-rx, 0), (+-rx/2, +-hz); the inner ring is `width` thinner.
static func hex_outline_mesh(radius_x: float, half_z: float, width: float) -> ArrayMesh:
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var shrink := (radius_x - width) / radius_x
	for p in [Vector2(radius_x, 0), Vector2(radius_x * 0.5, half_z), Vector2(-radius_x * 0.5, half_z), Vector2(-radius_x, 0), Vector2(-radius_x * 0.5, -half_z), Vector2(radius_x * 0.5, -half_z)]:
		outer.append(Vector3(p.x, 0, p.y))
		inner.append(Vector3(p.x * shrink, 0, p.y * shrink))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in 6:
		var j := (i + 1) % 6
		for v in [outer[i], outer[j], inner[j], outer[i], inner[j], inner[i]]:
			st.add_vertex(v)
	return st.commit()


static func hover_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.435, 0.839, 0.910, 0.55)  # 6fd6e8
	return m
```

In `_apply_world_art`:

```gdscript
	if is_instance_valid(hover_tile):
		hover_tile.mesh = WorldArt.hex_outline_mesh(HEX_X / 1.5 * 0.96, HEX_Z * 0.5 * 0.96, 0.035)
		hover_tile.material_override = WorldArt.hover_material()
```

In `_update_hover_tile`, the `+ 0.055` lift becomes `+ (0.07 if world_art_on else 0.055)` so the flat ring clears terrain relief.

- [ ] **Step 5: Run the tests**

Run: `$TESTS -- test_world_art` then `$TESTS -- test_world_art_survival`, then the full suite. Expected: pass, leak lines unchanged.

- [ ] **Step 6: Harness check**

Repeat Step 1's `hover_cc` and `hover_grass` captures on a fresh dir `$SCRATCH/world/blob2`. `world_diff.py blobs` must return no blob whose probe top hit is the hover mesh. Visual: the hovered hex shows a thin cyan outline no wider than one hex. Kill the PIDs.

- [ ] **Step 7: Commit**

```bash
git add godot3d/scripts/world/world_art.gd godot3d/scripts/earthfront_3d.gd godot3d/tests/test_world_art.gd godot3d/tests/test_world_art_survival.gd
git commit -m "Godot: Kestrel hover marker becomes a thin cyan hex outline (no amber blob)"
```

Put the Step 1 probe findings (which mesh owned each yellow blob) in the commit body.

---

### Task 4: Kestrel light, grade and atmosphere layer

**Files:**
- Modify: `godot3d/scripts/world/world_art.gd`, `godot3d/scripts/earthfront_3d.gd` (`_setup_environment` keeps a reference, `_apply_world_art`), `godot3d/tests/test_world_art.gd`, `godot3d/tests/test_world_art_survival.gd`, `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: `_apply_world_art`, world driver (keeps canvas layers with meta `world_art`).
- Produces: `const ENVIRONMENT := {"exposure": 0.95, "saturation": 0.70, "contrast": 1.04, "ambient_energy": 0.72, "background": "0c2a40"}`, `static func apply_environment(env: Environment) -> void`, `static func atmosphere_layer() -> CanvasLayer` (named `WorldAtmosphere`, `layer = 0`, meta `world_art = true`, one full-rect `ColorRect` with `mouse_filter = MOUSE_FILTER_IGNORE` and a canvas_item shader); game var `var environment: Environment` (set in `_setup_environment`), `var world_atmosphere: CanvasLayer`.

- [ ] **Step 1: Write the failing tests**

Append to `test_world_art.gd`:

```gdscript
func _env(scene) -> Environment:
	return scene.environment


func test_kestrel_grade_is_calmer_and_never_shows_sky(t) -> void:
	var scene := _kestrel_scene()
	var env := _env(scene)
	t.near(env.adjustment_saturation, float(WorldArt.ENVIRONMENT.saturation), 0.0001, "grade saturation from the table")
	t.ok(env.adjustment_saturation < 0.85, "less saturated than the legacy grade")
	t.eq(env.background_mode, Environment.BG_COLOR, "a colour background, so no sky can show")
	t.eq(env.background_color.to_html(false), String(WorldArt.ENVIRONMENT.background), "deep sea background")
	scene.free()


func test_atmosphere_layer_sits_under_the_hud_and_takes_no_clicks(t) -> void:
	var scene := _kestrel_scene()
	var layer: CanvasLayer = scene.world_atmosphere
	t.ok(layer != null and layer.get_meta("world_art", false), "atmosphere exists and survives world shots")
	t.ok(layer.layer < 1, "below the HUD CanvasLayer (layer 1)")
	var rect := layer.get_child(0) as ColorRect
	t.eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never eats a click")
	t.ok(rect.material is ShaderMaterial, "gradient and vignette shader")
	scene.free()
```

Append to `test_world_art_survival.gd`:

```gdscript
func test_survival_keeps_the_legacy_environment(t) -> void:
	var scene := _survival_scene()
	var env: Environment = scene.environment
	t.near(env.tonemap_exposure, 0.78, 0.0001, "exposure")
	t.near(env.adjustment_saturation, 0.85, 0.0001, "saturation")
	t.eq(env.background_mode, Environment.BG_SKY, "sky background")
	t.ok(scene.world_atmosphere == null, "no atmosphere layer")
	scene.free()
```

- [ ] **Step 2: Run them to see them fail**

Run: `$TESTS -- test_world_art`
Expected: FAIL (`environment` is not a member).

- [ ] **Step 3: Implement**

Check first that no other CanvasLayer in the game uses `layer <= 0`: `grep -rn "\.layer = \|layer = -" godot3d/scripts` (expect none; if one exists, put the atmosphere one below it and update the test).

In `_setup_environment` (line ~300; `world_environment` is a local there), after `world_environment.environment = env` add `environment = env` (and declare `var environment: Environment`). Add `var world_atmosphere: CanvasLayer`.

In `world_art.gd`:

```gdscript
const ENVIRONMENT := {"exposure": 0.95, "saturation": 0.70, "contrast": 1.04, "ambient_energy": 0.72, "background": "0c2a40"}


static func apply_environment(env: Environment) -> void:
	env.tonemap_exposure = float(ENVIRONMENT.exposure)
	env.adjustment_saturation = float(ENVIRONMENT.saturation)
	env.adjustment_contrast = float(ENVIRONMENT.contrast)
	env.ambient_light_energy = float(ENVIRONMENT.ambient_energy)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(String(ENVIRONMENT.background))


## gen.py's "gSun": warm light from the top-left, darker toward the bottom-right, plus a soft edge vignette.
static func atmosphere_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "WorldAtmosphere"
	layer.layer = 0
	layer.set_meta("world_art", true)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 warm : source_color = vec4(1.0, 0.949, 0.784, 0.14);
uniform vec4 dark : source_color = vec4(0.0, 0.0, 0.0, 0.22);
uniform float vignette = 0.22;
void fragment() {
    vec2 uv = SCREEN_UV;
    float diag = clamp(uv.x * 0.55 + uv.y * 0.45, 0.0, 1.0);
    float w = warm.a * (1.0 - smoothstep(0.0, 0.6, diag));
    float edge = smoothstep(0.55, 1.05, length((uv - 0.5) * vec2(1.25, 1.6)));
    float d = clamp(dark.a * smoothstep(0.4, 1.0, diag) + vignette * edge, 0.0, 0.6);
    COLOR = vec4(mix(warm.rgb, dark.rgb, d / max(w + d, 0.001)), max(w, d));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	layer.add_child(rect)
	return layer
```

In `_apply_world_art`:

```gdscript
	if environment != null:
		WorldArt.apply_environment(environment)
	if world_atmosphere == null:
		world_atmosphere = WorldArt.atmosphere_layer()
		add_child(world_atmosphere)
```

- [ ] **Step 4: Run the tests**

Run: `$TESTS -- test_world_art`, `$TESTS -- test_world_art_survival`, `$TESTS -- test_lighting`, full suite. Expected: pass; leak lines unchanged (the layer is a child of the scene and is freed with it).

- [ ] **Step 5: Calibrate against the boards**

Capture `python3 tools/qa/world_capture.py $SCRATCH/world/t4 --display :94` and run `world_diff.py run ... --check tools/ui/world_scores.json`. Read `raw.sat_live` vs `raw.sat_mock` and `raw.b_live` vs `raw.b_mock` on gp01, gp05, gp07. Adjust only `ENVIRONMENT` values (saturation in 0.05 steps, exposure in 0.05 steps) and re-capture, at most four rounds. Target: the `saturation` penalty on gp01, gp05 and gp07 at least halves vs `world_scores.json`, and no board drops beyond tolerance. Note the ground is still the old palette; Task 5 recalibrates colours under this grade, so stop at "halved" and do not chase ground colour here.

Visual checklist: the top-left of `home.png` is slightly warmer than the bottom-right; HUD clicks still work (in the harness, click the BUILD tab button by text with `ui.button("BUILD")` and check `observe()` shows the deck change).

- [ ] **Step 6: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t4 --out $SCRATCH/world/side_t4 --write tools/ui/world_scores.json
git add godot3d/scripts/world/world_art.gd godot3d/scripts/earthfront_3d.gd godot3d/tests/test_world_art.gd godot3d/tests/test_world_art_survival.gd tools/ui/world_scores.json
git commit -m "Godot: Kestrel grade, deep-sea background and a warm atmosphere layer under the HUD"
```

---

### Task 5: Painted ground splat and palette calibration

**Files:**
- Modify: `godot3d/scripts/continuous_terrain.gd` (`GROUND_LOOK`, `_bake_ground`, `_blend_cells`, `_add_vertex`, `_terrain_material`, `_ground_shader_code`), `godot3d/tests/test_ground_model.gd` (re-pin), `godot3d/tests/test_world_water.gd` (create; ground-channel tests live here with the water ones in Task 6), `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: Task 2 edge continuation, Task 4 grade.
- Produces: per-vertex channels used by Task 6: `COLOR.rgb` class colour (linear), `COLOR.a` water share, `UV2.x` sea share, `UV2.y` rock (highland) share, `UV.x` sea distance in cells (0 at the coast, 4+ offshore; Task 6 fills it, 0.0 here), `UV.y` reserved 0.0. Detail UVs are computed in the shader from `world_position.xz * 0.17` (the old `UV`). Terrain helpers `func extras_at_world(world_x: float, world_z: float) -> Vector4` returning `(water, sea_share, rock_share, sea_distance)`. Shader uniforms `detail_strength`, `rotated_strength`, `patch_strength`, `rock_strength`, `rock_texture`.

- [ ] **Step 1: Write the failing tests**

`godot3d/tests/test_world_water.gd`:

```gdscript
extends RefCounted
## Kestrel ground and water channels baked into the terrain (spec addendum W3, W4). Pure data, no rendering.
const GroundModel := preload("res://scripts/terrain/ground_model.gd")
const Terrain := preload("res://scripts/continuous_terrain.gd")


func _terrain() -> Node3D:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var m = GroundModel.from_snapshot(JSON.parse_string(f.get_as_text()))
	var terrain: Node3D = Terrain.new()
	terrain.configure(44, 26, 2.1, 1.0, 0.68, 0.70, null)
	terrain.apply_ground(m)
	return terrain


func _at(terrain, x: int, y: int) -> Vector4:
	return terrain.extras_at_world(2.1 + float(x) * 0.68, 1.0 + float(y) * 0.70 + (0.35 if x % 2 else 0.0))


func test_rock_share_marks_the_ridge_only(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 33, 1).z > 0.9, "deep in Ironback Ridge is rock")
	t.ok(_at(terrain, 5, 9).z < 0.05, "Sunfield grass is not rock")
	terrain.free()


func test_sea_share_separates_sea_from_river(t) -> void:
	var terrain := _terrain()
	t.ok(_at(terrain, 40, 22).y > 0.9, "Kestrel Bay is sea")
	t.ok(_at(terrain, 24, 11).y < 0.05, "the Calder River is not sea")
	t.ok(_at(terrain, 24, 11).x > 0.5, "but it is water")
	terrain.free()


func test_palette_is_calm_and_ordered(t) -> void:
	var look: Dictionary = Terrain.GROUND_LOOK
	var g := Color(String(look["g"][2]))
	var f := Color(String(look["f"][2]))
	var h := Color(String(look["h"][2]))
	t.ok(g.s < 0.55, "grass is olive, not saturated green (s %s)" % g.s)
	t.ok(f.s < 0.50, "the Dry Flats are sand, not orange (s %s)" % f.s)
	t.ok(f.get_luminance() > g.get_luminance(), "flats are lighter than grass")
	t.ok(h.s < 0.15, "the ridge is grey rock (s %s)" % h.s)
	t.ok(float(look["h"][0]) <= 0.80, "the ridge is low relief, not a 1.6 plateau")
```

In `test_ground_model.gd` `test_ground_look_pins_height_colour_and_wetness_per_glyph`, the pins `-0.15`, `"6fb0c4"`, `1.60` will change with calibration. Leave the test as is for now so Step 2 shows it still passes; Step 6 re-pins it.

- [ ] **Step 2: Run them to see them fail**

Run: `$TESTS -- test_world_water`
Expected: FAIL (`extras_at_world` missing; palette saturation asserts fail on `6a9a3a` / `c9923a`).

- [ ] **Step 3: Bake the extra channels**

In `continuous_terrain.gd`:
- Add `var _cell_rock := PackedFloat32Array()`, `var _cell_sea := PackedFloat32Array()`, `var _raster_x := PackedVector4Array()` (water, sea share, rock share, sea distance).
- In `_bake_ground`, per cell: `_cell_rock[i] = 1.0 if glyph == "h" else 0.0`, `_cell_sea[i] = 1.0 if glyph == "o" else 0.0` (resize both to `count` first). Store `_raster_x[row * _raster_cols + col] = Vector4(blend[4], blend[5], blend[6], 0.0)`.
- `_blend_cells` accumulates `rock_sum += _cell_rock[i] * w` and `sea_sum += _cell_sea[i] * w` and returns `[height, r, g, b, water, sea_share, rock_share]`; the `total <= 0` fallback returns `[-0.8, 0, 0, 0, 1.0, 1.0, 0.0]`.
- Add `_raster_sample_extras(gx, gz) -> Vector4` (bilinear like `_raster_sample_color`) and the public:

```gdscript
func extras_at_world(world_x: float, world_z: float) -> Vector4:
	if ground == null:
		return Vector4.ZERO
	return _raster_sample_extras((world_x - origin_x) / cell_x, (world_z - origin_z) / cell_z)
```

- In `_add_vertex` with a ground model: `var e := _raster_sample_extras(gx, gz)`, `surface.set_uv(Vector2(e.w, 0.0))`, `surface.set_uv2(Vector2(e.y, e.z))`. The noise path keeps `surface.set_uv(Vector2(world_x, world_z) * 0.17)` and sets no UV2.
- `_terrain_material`: with a ground model also `material.set_shader_parameter("rock_texture", load("res://assets/terrain/painterly/highland_v3.png"))`.

- [ ] **Step 4: The painted ground shader**

Replace `_ground_shader_code()` with (water branch kept simple here; Task 6 replaces the water lines):

```gdscript
func _ground_shader_code() -> String:
	return """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.55;
uniform float rotated_strength = 0.35;
uniform float patch_strength = 0.16;
uniform float rock_strength = 0.85;
varying vec3 world_position;
varying vec3 world_normal;
varying vec2 extra;
float ground_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ground_noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(ground_hash(i), ground_hash(i + vec2(1, 0)), f.x),
               mix(ground_hash(i + vec2(0, 1)), ground_hash(i + vec2(1, 1)), f.x), f.y);
}
float soft_light(float base, float blend) {
    float d = base <= 0.25 ? ((16.0 * base - 12.0) * base + 4.0) * base : sqrt(base);
    return blend <= 0.5 ? base - (1.0 - 2.0 * blend) * base * (1.0 - base) : base + (2.0 * blend - 1.0) * (d - base);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
    extra = UV2;
}
void fragment() {
    vec2 uv_a = world_position.xz * 0.17;
    float ca = 0.7986, sa = 0.6018;  // 37 degrees, gen.py's rotated soft-light copy
    vec2 uv_b = mat2(vec2(ca, sa), vec2(-sa, ca)) * uv_a * (620.0 / 900.0);
    float d_a = dot(texture(detail_texture, uv_a).rgb, vec3(0.299, 0.587, 0.114));
    float d_b = dot(texture(detail_texture, uv_b).rgb, vec3(0.299, 0.587, 0.114));
    vec3 base = COLOR.rgb;
    vec3 land = mix(base, base * (0.55 + d_a * 0.9), detail_strength);
    vec3 soft = vec3(soft_light(land.r, d_b), soft_light(land.g, d_b), soft_light(land.b, d_b));
    land = mix(land, soft, rotated_strength);
    float patches = ground_noise(world_position.xz * 0.9) * 0.6 + ground_noise(world_position.xz * 3.6) * 0.4;
    land *= 1.0 - patch_strength * 0.5 + patches * patch_strength;
    vec3 rock = texture(rock_texture, uv_a * 1.3).rgb;
    float rock_l = dot(rock, vec3(0.299, 0.587, 0.114));
    vec3 grey_rock = mix(rock, vec3(rock_l), 0.65) * (base / max(dot(base, vec3(0.299, 0.587, 0.114)), 0.05)) * 0.5;
    land = mix(land, grey_rock, extra.y * rock_strength);
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    land = mix(land, land * 0.62, smoothstep(0.25, 0.65, slope) * 0.6);
    float water = smoothstep(0.42, 0.62, COLOR.a);
    float ripple = sin(world_position.x * 3.1 + TIME * 0.7) * cos(world_position.z * 2.7 - TIME * 0.5);
    vec3 wet = COLOR.rgb * (0.92 + ripple * 0.05 + patches * 0.08);
    ALBEDO = mix(land, wet, water);
    ROUGHNESS = mix(0.95, 0.30, water);
    SPECULAR = mix(0.06, 0.30, water);
}
"""
```

- [ ] **Step 5: Starting palette and heights**

Set `GROUND_LOOK` to the land.jpg medians as the starting point (Step 6 calibrates):

```gdscript
const GROUND_LOOK := {
	"g": [0.20, 0.08, "808844", 0.0],
	"m": [0.20, 0.08, "848948", 0.0],
	"f": [0.05, 0.03, "ac965e", 0.0],
	"h": [0.70, 0.12, "888680", 0.0],
	"t": [0.26, 0.05, "5d6b38", 0.0],
	"r": [-0.50, 0.0, "3a6c81", 1.0],
	"w": [-0.15, 0.0, "6fa3ac", 1.0],
	"s": [0.05, 0.0, "b9a373", 0.0],
	"o": [-0.80, 0.0, "133a51", 1.0],
	"c": [-0.30, 0.0, "6b5f4a", 0.0],
}
```

Run: `$TESTS -- test_world_water` and expect PASS; then `$TESTS -- test_ground_model` and expect FAIL only on the colour pin of the ford (`6fb0c4`) and the highland height pin (`1.60`).

- [ ] **Step 6: Calibrate, then re-pin**

Loop at most five rounds: `python3 tools/qa/world_capture.py $SCRATCH/world/t5 --only home,ford,flats,bay --display :94`, then `world_diff.py run --boards gp01,gp04,gp05,gp06,gp07,gp08 ... --check tools/ui/world_scores.json` and read `swatches` (Delta E per glyph). Lighting and tonemap change the on-screen colour, so adjust the GROUND_LOOK hex (not the shader) toward the target: if the live swatch is darker than the mock, lighten the albedo by the ratio of their luminances; if it is greener, pull the hue toward the mock. Shader uniforms (`detail_strength`, `rotated_strength`, `patch_strength`) are tuned only from the `detail` penalty and `raw.detail_ratio` (target 0.7 to 1.4).

Exit criteria: swatch Delta E at most 12 for `g`, `m`, `f`, `h`; `raw.detail_ratio` between 0.7 and 1.4 on gp01; gp01, gp04, gp06 and gp08 totals at least 8 above `tools/ui/world_scores.json`; no board drops beyond tolerance. If the criteria are not met after five rounds, stop, keep the best round, and report the numbers with the side-by-sides (DONE_WITH_CONCERNS), never loosen the criteria.

Then re-pin `test_ground_model.gd` `test_ground_look_pins_height_colour_and_wetness_per_glyph` to the calibrated values: the `look["w"][2]` colour and the baked `_cell_color[i]` colour become the calibrated ford hex, and `t.near(float(look["h"][0]), 1.60, ...)` becomes `0.70` with message `"highland is low rocky ground (spec addendum W4)"`. Leave the other assertions (ford -0.15, wet 1.0, river -0.50, highland dry, ordering) untouched. Update `test_palette_is_calm_and_ordered` only if a calibrated value genuinely needs it, and say so in the commit body.

- [ ] **Step 7: Run everything**

Run: full `$TESTS 2>&1 | tail -5`. Expected: all pass, leak lines unchanged, no `SCRIPT ERROR`. In the last capture `grep -c "SHADER ERROR" $SCRATCH/world/t5/godot.log` is 0.

Visual checklist (side_gp01, side_gp05): ground reads olive and textured, not flat green; the Dry Flats read pale sand, not orange; the ridge is grey and low; no seams at the edge-continuation margin.

- [ ] **Step 8: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t5 --out $SCRATCH/world/side_t5 --write tools/ui/world_scores.json
git add godot3d/scripts/continuous_terrain.gd godot3d/tests/test_world_water.gd godot3d/tests/test_ground_model.gd tools/ui/world_scores.json
git commit -m "Godot: painted Kestrel ground (detail splat, rock ridge) calibrated to the land.jpg palette"
```

Put the final per-glyph Delta E values and board deltas in the commit body.

---

### Task 6: Water bands: river, banks, ford, sea depth, surf

**Files:**
- Modify: `godot3d/scripts/continuous_terrain.gd` (`_bake_ground` sea distance, `_ground_shader_code` water branch), `godot3d/tests/test_world_water.gd`, `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: Task 5 channels (`COLOR.a` water share, `UV2.x` sea share, `UV.x` sea distance).
- Produces: `extras_at_world(...).w` = sea distance in cells; shader uniforms `bank_sand`, `river_edge`, `river_mid`, `river_centre`, `sea_shallow`, `sea_deep`, `surf_colour`, `bank_strength`, `surf_strength`.

- [ ] **Step 1: Write the failing tests**

Append to `test_world_water.gd`:

```gdscript
func test_sea_distance_grows_offshore(t) -> void:
	var terrain := _terrain()
	var coast := _at(terrain, 33, 18).w  # 's' and 'o' meet near here
	var open := _at(terrain, 43, 25).w
	var beyond: float = terrain.extras_at_world(2.1 + 50.0 * 0.68, 1.0 + 30.0 * 0.70).w
	t.ok(coast <= 1.5, "near the shore the sea is shallow (%s)" % coast)
	t.ok(open >= 4.0, "the far corner of the bay is deep (%s)" % open)
	t.ok(beyond >= open, "and it keeps deepening past the map edge (%s)" % beyond)
	t.near(_at(terrain, 24, 11).w, 0.0, 0.001, "the river has no sea distance")
	terrain.free()


func test_water_shader_names_every_band(t) -> void:
	var terrain := _terrain()
	var code: String = terrain._ground_shader_code()
	for name in ["bank_sand", "river_edge", "river_mid", "river_centre", "sea_shallow", "sea_deep", "surf_colour"]:
		t.ok(code.contains("uniform vec3 " + name), "uniform " + name)
	t.ok(not code.contains("hint_depth_texture") and not code.contains("hint_screen_texture"), "Compatibility-safe")
	terrain.free()
```

- [ ] **Step 2: Run them to see them fail**

Run: `$TESTS -- test_world_water`
Expected: FAIL (sea distance is 0 everywhere; uniforms missing).

- [ ] **Step 3: Bake the sea distance**

In `_bake_ground`, before the raster loop, compute a per-cell sea distance with a breadth-first search over the hex grid (odd-q neighbours: for even `x`, `(x+-1, y-1)` and `(x+-1, y)`; for odd `x`, `(x+-1, y)` and `(x+-1, y+1)`; plus `(x, y+-1)`): every non-sea cell is distance 0 and seeds the queue; each sea cell gets 1 + the smallest neighbour distance. Store in `var _cell_sea_dist := PackedFloat32Array()`. In `_blend_cells`, accumulate `dist_sum += d * w` where for an off-map cell `d = _cell_sea_dist[i] + overshoot` if the clamped edge cell is sea (`overshoot = maxf(absf(float(c - cc)), absf(float(r - rr)))`) and 0 otherwise; return it as the 8th element and store it in `_raster_x[...].w`. `_add_vertex` already writes `e.w` into `UV.x`.

- [ ] **Step 4: Water bands in the shader**

Add uniforms after `rock_strength` (colours from gen.py):

```glsl
uniform vec3 bank_sand : source_color = vec3(0.741, 0.659, 0.471);   // bda878
uniform vec3 river_edge : source_color = vec3(0.114, 0.302, 0.392);  // 1d4d64
uniform vec3 river_mid : source_color = vec3(0.169, 0.478, 0.596);   // 2b7a98
uniform vec3 river_centre : source_color = vec3(0.227, 0.424, 0.506); // 3a6c81
uniform vec3 sea_shallow : source_color = vec3(0.106, 0.278, 0.369); // 1b475e
uniform vec3 sea_deep : source_color = vec3(0.031, 0.165, 0.259);    // 082a42
uniform vec3 surf_colour : source_color = vec3(0.914, 0.937, 0.902); // e9efe6
uniform float bank_strength = 0.75;
uniform float surf_strength = 0.65;
```

`void vertex()` also passes `sea_dist = UV.x;` (declare `varying float sea_dist;`). Replace the last block of `fragment()` (from `float water = ...` to `SPECULAR`) with:

```glsl
    float share = COLOR.a;
    float sea = extra.x;
    float bank = smoothstep(0.10, 0.28, share) * (1.0 - smoothstep(0.30, 0.44, share));
    land = mix(land, bank_sand * (0.82 + d_a * 0.36), bank * (1.0 - sea) * bank_strength);
    float water = smoothstep(0.40, 0.56, share);
    float streak = smoothstep(0.62, 0.80, ground_noise(vec2(world_position.x * 1.1, world_position.z * 5.5) + vec2(TIME * 0.04, 0.0)));
    vec3 river = mix(river_edge, river_mid, smoothstep(0.50, 0.75, share));
    river = mix(river, river_centre, smoothstep(0.80, 0.98, share));
    river += vec3(0.05) * streak;
    vec3 ocean = mix(sea_shallow, sea_deep, smoothstep(0.5, 4.0, sea_dist));
    ocean += vec3(0.03) * streak * (1.0 - smoothstep(1.0, 3.0, sea_dist));
    vec3 wet = mix(river, ocean, smoothstep(0.3, 0.7, sea));
    float surf = (1.0 - smoothstep(0.0, 0.06, abs(share - 0.47))) * smoothstep(0.4, 0.6, sea);
    surf *= 0.55 + 0.45 * ground_noise(world_position.xz * 6.0 + vec2(TIME * 0.1));
    ALBEDO = mix(mix(land, wet, water), surf_colour, surf * surf_strength);
    ROUGHNESS = mix(0.95, 0.35, water);
    SPECULAR = mix(0.06, 0.25, water);
```

The ford keeps its own lighter class colour through `COLOR.rgb` on its two cells; pebbles come from Task 7 decals.

- [ ] **Step 5: Run the tests**

Run: `$TESTS -- test_world_water`, then the full suite. Expected: pass, leak lines unchanged.

- [ ] **Step 6: Calibrate and check**

At most four rounds: `world_capture.py $SCRATCH/world/t6 --only home,ford,bay --display :94`, `world_diff.py run --boards gp05,gp07,gp01 ... --check tools/ui/world_scores.json --require gp05:+5,gp07:+5`. Tune only the uniform defaults and `bank_strength`/`surf_strength`. Exit criteria: swatch Delta E at most 15 for `r` and `o`; gp05 and gp07 at least +5; nothing else drops beyond tolerance. `grep -c "SHADER ERROR" $SCRATCH/world/t6/godot.log` is 0.

Visual checklist (side_gp05, side_gp07, bay.png): sand banks along both river edges; darker edges and a lighter centre in the river; the bay deepens away from the shore; a thin broken white surf line on the coast; no white line along the river.

- [ ] **Step 7: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t6 --out $SCRATCH/world/side_t6 --write tools/ui/world_scores.json
git add godot3d/scripts/continuous_terrain.gd godot3d/tests/test_world_water.gd tools/ui/world_scores.json
git commit -m "Godot: Kestrel water bands (sand banks, river depth, sea depth, surf line)"
```

---

### Task 7: Prop atlas and billboard scatter

**Files:**
- Create: `tools/ui/build_prop_atlas.py`, `tools/ui/test_build_prop_atlas.py`, `godot3d/assets/world/props_atlas.png` (+ `.import`), `godot3d/assets/world/props_atlas.json`, `godot3d/scripts/world/world_props.gd`, `godot3d/tests/test_world_props.gd`
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_sync_ground`, `_build_terrain_dressing`, `_dress_ground_tile` gate), `godot3d/tests/test_world_art_survival.gd`, `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: terrain `height_at_world`, ground model `glyph_at`, snapshot `deposits` (`[{kind, x, y}]`).
- Produces:
  - Atlas JSON: `{"size": [1024, 1024], "sprites": {name: {"rect": [x, y, w, h], "uv": [u0, v0, du, dv], "aspect": h / w, "sink": float, "kind": "card" | "decal"}}}` with names `forest`, `forest_dry`, `scrub`, `rock`, `ore`, `alloy`, `crater`, `pebbles`, `shadow`.
  - `const WorldProps := preload("res://scripts/world/world_props.gd")`; `static func plan(model, deposits: Array, origin: Vector2, hex: Vector2, margin: int) -> Array` of `{"sprite": String, "pos": Vector2 (world x, z), "size": float (world width), "flip": bool, "tile": Vector2i}`; instance methods `build(parent: Node3D, items: Array, height_at: Callable) -> void`, `clear_around(world: Vector3, radius: float) -> int`, `add_pad(world: Vector3, width: float) -> int`, `release_pad(slot: int) -> void`; vars `cards: MultiMeshInstance3D`, `decals: MultiMeshInstance3D`.
  - Game var `var world_props: RefCounted`.

- [ ] **Step 1: Write the failing atlas test**

`tools/ui/test_build_prop_atlas.py`:

```python
import json, pathlib, tempfile, unittest
from PIL import Image
import build_prop_atlas as bpa

NAMES = {"forest", "forest_dry", "scrub", "rock", "ore", "alloy", "crater", "pebbles", "shadow"}


class AtlasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        out = pathlib.Path(cls.dir.name)
        bpa.build(out / "a.png", out / "a.json")
        cls.img = Image.open(out / "a.png")
        cls.meta = json.loads((out / "a.json").read_text())

    @classmethod
    def tearDownClass(cls):
        cls.dir.cleanup()

    def test_size_and_names(self):
        self.assertEqual(self.img.size, (1024, 1024))
        self.assertEqual(self.img.mode, "RGBA")
        self.assertEqual(set(self.meta["sprites"]), NAMES)

    def test_rects_in_bounds_and_disjoint(self):
        rects = [s["rect"] for s in self.meta["sprites"].values()]
        for x, y, w, h in rects:
            self.assertTrue(0 <= x and 0 <= y and x + w <= 1024 and y + h <= 1024)
        for i, a in enumerate(rects):
            for b in rects[i + 1:]:
                self.assertTrue(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])

    def test_uv_matches_rect(self):
        for s in self.meta["sprites"].values():
            x, y, w, h = s["rect"]
            self.assertEqual([round(v, 6) for v in s["uv"]], [round(x / 1024, 6), round(y / 1024, 6), round(w / 1024, 6), round(h / 1024, 6)])

    def test_cards_are_cropped_to_their_pixels(self):
        for name, s in self.meta["sprites"].items():
            if s["kind"] != "card":
                continue
            x, y, w, h = s["rect"]
            alpha = self.img.crop((x, y, x + w, y + h)).getchannel("A")
            self.assertGreater(max(alpha.crop((0, h - 2, w, h)).getdata()), 0, name + " touches its bottom edge")

    def test_alloy_is_a_hue_rotated_ore(self):
        def mean_rgb(name):
            x, y, w, h = self.meta["sprites"][name]["rect"]
            px = [p for p in self.img.crop((x, y, x + w, y + h)).getdata() if p[3] > 200]
            return [sum(p[i] for p in px) / len(px) for i in range(3)]
        ore, alloy = mean_rgb("ore"), mean_rgb("alloy")
        self.assertGreater(ore[2] + ore[1], 2 * ore[0], "ore is cyan")
        self.assertGreater(alloy[0] + alloy[2], 2 * alloy[1], "alloy is purple")


if __name__ == "__main__":
    unittest.main()
```

Run: `cd tools/ui && python3 -m unittest test_build_prop_atlas -v`. Expected: `ModuleNotFoundError`.

- [ ] **Step 2: Implement the atlas builder**

`tools/ui/build_prop_atlas.py`:

```python
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
```

Run: `cd tools/ui && python3 -m unittest test_build_prop_atlas -v` (5 tests OK). If `test_alloy_is_a_hue_rotated_ore` fails, check the real ore colour with Read on the atlas PNG before changing the test; the board shows ore cyan and alloy purple. Then bake: `python3 tools/ui/build_prop_atlas.py` and import: `$GODOT --headless --path godot3d --import`. Open `godot3d/assets/world/props_atlas.png.import` and make sure it has `mipmaps/generate=true` and `process/fix_alpha_border=true`; if not, set them and re-run `--import`.

- [ ] **Step 3: Write the failing Godot prop tests**

`godot3d/tests/test_world_props.gd`:

```gdscript
extends RefCounted
## Prop scatter for Kestrel (spec addendum W5): deterministic, data-driven, two MultiMeshes no matter how many props.
const WorldProps := preload("res://scripts/world/world_props.gd")
const GroundModel := preload("res://scripts/terrain/ground_model.gd")


func _snap() -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func _plan() -> Array:
	var s := _snap()
	return WorldProps.plan(GroundModel.from_snapshot(s), s["deposits"], Vector2(2.1, 1.0), Vector2(0.68, 0.70), 8)


func test_plan_is_deterministic(t) -> void:
	t.eq(_plan(), _plan(), "same snapshot, same props")


func test_every_forest_tile_gets_a_canopy_and_water_gets_no_cards(t) -> void:
	var s := _snap()
	var m = GroundModel.from_snapshot(s)
	var canopy := {}
	for item in _plan():
		var tile: Vector2i = item.tile
		if tile.x < 0 or tile.y < 0 or tile.x >= 44 or tile.y >= 26:
			continue
		var g := String(m.glyph_at(tile.x, tile.y))
		if g in ["r", "o"]:
			t.ok(false, "no prop on %s at %s" % [g, tile])
		if g == "w":
			t.eq(String(item.sprite), "pebbles", "the ford only gets pebbles")
		if g == "t" and String(item.sprite) == "forest":
			canopy[tile] = true
	for y in 26:
		for x in 44:
			if m.glyph_at(x, y) == "t":
				t.ok(canopy.has(Vector2i(x, y)), "forest tile %s has a canopy" % Vector2i(x, y))


func test_deposits_get_crystals_and_nothing_else(t) -> void:
	var items := _plan()
	for d in _snap()["deposits"]:
		var tile := Vector2i(int(d.x), int(d.y))
		var crystals := 0
		for item in items:
			if item.tile == tile:
				t.ok(String(item.sprite) in ["ore", "alloy", "shadow"], "only crystals on a deposit (%s)" % item.sprite)
				if String(item.sprite) == ("alloy" if String(d.kind) == "Alloy" else "ore"):
					crystals += 1
		t.eq(crystals, 2, "two crystal cards on %s" % tile)


func test_props_continue_past_the_map_edge(t) -> void:
	var outside := 0
	for item in _plan():
		if item.pos.x < 2.1 or item.pos.y < 1.0:
			outside += 1
	t.ok(outside > 10, "the edge margin is dressed too (%s)" % outside)


func test_counts_are_in_the_board_range(t) -> void:
	var n := {}
	for item in _plan():
		n[item.sprite] = int(n.get(item.sprite, 0)) + 1
	t.ok(int(n.get("forest", 0)) >= 66, "dense canopy (%s)" % n.get("forest", 0))
	t.ok(int(n.get("scrub", 0)) >= 40 and int(n.get("scrub", 0)) <= 260, "scrub (%s)" % n.get("scrub", 0))
	t.ok(int(n.get("rock", 0)) >= 30, "rocks on the ridge and flats (%s)" % n.get("rock", 0))
	t.eq(int(n.get("crater", 0)), 2, "one decal per crater tile")


func test_build_uses_two_multimeshes_without_shadow_casting(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	props.build(parent, _plan(), func(_x, _z): return 0.0)
	var mmis := parent.find_children("*", "MultiMeshInstance3D", true, false)
	t.eq(mmis.size(), 2, "cards and decals, nothing per prop")
	for mmi in mmis:
		t.eq((mmi as MultiMeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow pass for props")
	t.ok(props.cards.multimesh.use_custom_data, "atlas rect per instance")
	parent.free()


func test_clear_around_hides_only_nearby_props(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	var items := _plan()
	props.build(parent, items, func(_x, _z): return 0.0)
	var centre := Vector3(2.1 + 8.0 * 0.68, 0, 1.0 + 19.0 * 0.70)  # Hollow Wood
	var hidden: int = props.clear_around(centre, 1.0)
	t.ok(hidden > 0, "trees near a new building are cleared (%s)" % hidden)
	var mm: MultiMesh = props.cards.multimesh
	var still := 0
	for i in mm.instance_count:
		var tr := mm.get_instance_transform(i)
		if tr.basis.get_scale().length() > 0.001 and Vector2(tr.origin.x, tr.origin.z).distance_to(Vector2(centre.x, centre.z)) < 1.0:
			still += 1
	t.eq(still, 0, "nothing visible is left inside the radius")
	parent.free()


func test_pads_reuse_slots(t) -> void:
	var parent := Node3D.new()
	var props = WorldProps.new()
	props.build(parent, _plan(), func(_x, _z): return 0.0)
	var a: int = props.add_pad(Vector3(5, 0, 5), 1.9)
	props.release_pad(a)
	t.eq(props.add_pad(Vector3(6, 0, 6), 1.9), a, "a released pad slot is reused")
	parent.free()
```

Append to `test_world_art_survival.gd`:

```gdscript
func test_survival_keeps_the_legacy_dressing(t) -> void:
	var scene := _survival_scene()
	t.ok(scene.world_props == null, "no prop MultiMeshes")
	t.eq(scene.find_children("*", "MultiMeshInstance3D", true, false).size(), 0, "nothing new in the scene")
	scene.free()
```

Run: `$TESTS -- test_world_props`. Expected: FAIL (`world_props.gd` missing).

- [ ] **Step 4: Implement `world_props.gd`**

```gdscript
extends RefCounted
## Kestrel prop scatter (spec addendum W5). `plan` is pure and deterministic; `build` draws every prop with two
## MultiMeshes: camera-facing cards (trees, scrub, rocks, crystals) and flat decals (drop shadows, craters, pebbles, pads).

const ATLAS_PNG := "res://assets/world/props_atlas.png"
const ATLAS_JSON := "res://assets/world/props_atlas.json"
const TILE := 0.68
const PAD_SLOTS := 64
## glyph: [[sprite, every_n, min_tiles, max_tiles, jitter_tiles], ...]; a rule fires when hash % every_n == 0.
const RULES := {
	"t": [["forest", 1, 1.9, 2.6, 0.30], ["forest", 2, 1.5, 2.0, 0.45]],
	"g": [["scrub", 9, 0.8, 1.1, 0.35], ["forest", 23, 1.4, 1.8, 0.30]],
	"m": [["scrub", 6, 0.8, 1.1, 0.35]],
	"f": [["scrub", 11, 0.8, 1.0, 0.35], ["rock", 17, 0.9, 1.3, 0.35], ["forest_dry", 29, 1.4, 1.7, 0.30]],
	"h": [["rock", 3, 1.0, 1.7, 0.35]],
	"c": [["crater", 1, 1.5, 1.5, 0.0]],
	"w": [["pebbles", 1, 1.0, 1.0, 0.0]],
}
const BANK := ["forest", 4, 1.1, 1.5, 0.25]  # riverside willows on dry land next to river or ford
const CRYSTALS := [[1.25, Vector2(0.0, 0.0)], [0.85, Vector2(0.25, 0.15)]]
const DECAL_SPRITES := ["crater", "pebbles", "shadow"]

var cards: MultiMeshInstance3D
var decals: MultiMeshInstance3D
var _meta: Dictionary = {}
var _decal_base := 0
var _free_pads: Array[int] = []


static func _hash(x: int, y: int, salt: int) -> int:
	return absi(((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff)


static func _neighbours(x: int, y: int) -> Array[Vector2i]:
	var odd := posmod(x, 2) == 1
	var out: Array[Vector2i] = [Vector2i(x, y - 1), Vector2i(x, y + 1)]
	for dx in [-1, 1]:
		out.append(Vector2i(x + dx, y if odd else y - 1))
		out.append(Vector2i(x + dx, y + 1 if odd else y))
	return out


static func _glyph(model, x: int, y: int) -> String:
	return String(model.glyph_at(clampi(x, 0, model.width - 1), clampi(y, 0, model.height - 1)))


static func _place(out: Array, rule: Array, x: int, y: int, salt: int, origin: Vector2, hex: Vector2) -> void:
	var h := _hash(x, y, salt)
	if h % int(rule[1]) != 0:
		return
	var t := float((h >> 8) % 1000) / 999.0
	var jitter := float(rule[4]) * TILE
	var jx := (float((h >> 12) % 1000) / 999.0 - 0.5) * 2.0 * jitter
	var jz := (float((h >> 20) % 1000) / 999.0 - 0.5) * 2.0 * jitter
	var centre := Vector2(origin.x + float(x) * hex.x, origin.y + float(y) * hex.y + (hex.y * 0.5 if posmod(x, 2) == 1 else 0.0))
	out.append({"sprite": String(rule[0]), "pos": centre + Vector2(jx, jz), "size": lerpf(float(rule[2]), float(rule[3]), t) * TILE,
		"flip": (h >> 3) & 1 == 1, "tile": Vector2i(x, y)})


static func plan(model, deposits: Array, origin: Vector2, hex: Vector2, margin: int) -> Array:
	var out: Array = []
	var deposit_tiles := {}
	for d in deposits:
		if d is Dictionary:
			deposit_tiles[Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))] = String(d.get("kind", "Ore"))
	for y in range(-margin, model.height + margin):
		for x in range(-margin, model.width + margin):
			var tile := Vector2i(x, y)
			if deposit_tiles.has(tile):
				continue
			var g := _glyph(model, x, y)
			var rules: Array = RULES.get(g, [])
			for k in rules.size():
				_place(out, rules[k], x, y, k + 1, origin, hex)
			if g in ["g", "m", "f"]:
				for n in _neighbours(x, y):
					if _glyph(model, n.x, n.y) in ["r", "w"]:
						_place(out, BANK, x, y, 97, origin, hex)
						break
	for tile in deposit_tiles:
		var sprite := "alloy" if deposit_tiles[tile] == "Alloy" else "ore"
		var centre := Vector2(origin.x + float(tile.x) * hex.x, origin.y + float(tile.y) * hex.y + (hex.y * 0.5 if posmod(tile.x, 2) == 1 else 0.0))
		for c in CRYSTALS:
			out.append({"sprite": sprite, "pos": centre + c[1] * TILE, "size": float(c[0]) * TILE, "flip": false, "tile": tile})
	# one soft drop shadow per card, toward the lower right like the boards (the NW sun)
	var shadows: Array = []
	for item in out:
		if not String(item.sprite) in DECAL_SPRITES:
			shadows.append({"sprite": "shadow", "pos": item.pos + Vector2(0.16, 0.10) * item.size, "size": item.size * 0.9, "flip": false, "tile": item.tile})
	out.append_array(shadows)
	return out


func _load_meta() -> void:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))


func _rect(sprite: String, flip: bool) -> Color:
	var uv: Array = _meta.sprites[sprite].uv
	return Color(float(uv[0]) + float(uv[2]), float(uv[1]), -float(uv[2]), float(uv[3])) if flip else Color(float(uv[0]), float(uv[1]), float(uv[2]), float(uv[3]))


func build(parent: Node3D, items: Array, height_at: Callable) -> void:
	_load_meta()
	var atlas := load(ATLAS_PNG) as Texture2D
	var card_items := items.filter(func(i): return not String(i.sprite) in DECAL_SPRITES)
	var decal_items := items.filter(func(i): return String(i.sprite) in DECAL_SPRITES)
	cards = _multimesh(parent, "WorldPropCards", _card_material(atlas), _card_mesh(), card_items.size())
	decals = _multimesh(parent, "WorldPropDecals", _decal_material(atlas), _decal_mesh(), decal_items.size() + PAD_SLOTS)
	for i in card_items.size():
		var it: Dictionary = card_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var w: float = it.size
		var basis := Basis.from_scale(Vector3(w, w * float(s.aspect), 1.0))
		cards.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(it.pos.x, height_at.call(it.pos.x, it.pos.y), it.pos.y)))
		cards.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
		cards.multimesh.set_instance_color(i, Color(float(s.sink), 0.92 + float(_hash(it.tile.x, it.tile.y, i) % 16) / 100.0, 0, 1))
	for i in decal_items.size():
		var it: Dictionary = decal_items[i]
		var s: Dictionary = _meta.sprites[it.sprite]
		var basis := Basis.from_scale(Vector3(it.size, 1.0, it.size * float(s.aspect)))
		decals.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(it.pos.x, height_at.call(it.pos.x, it.pos.y) + 0.035, it.pos.y)))
		decals.multimesh.set_instance_custom_data(i, _rect(it.sprite, it.flip))
	_decal_base = decal_items.size()
	_free_pads.clear()
	for k in range(PAD_SLOTS - 1, -1, -1):
		_free_pads.append(_decal_base + k)
		decals.multimesh.set_instance_transform(_decal_base + k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		decals.multimesh.set_instance_custom_data(_decal_base + k, _rect("shadow", false))


func clear_around(world: Vector3, radius: float) -> int:
	var hidden := 0
	for mmi in [cards, decals]:
		if mmi == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var last := mm.instance_count if mmi == cards else _decal_base
		for i in last:
			var tr := mm.get_instance_transform(i)
			if tr.basis.get_scale().length() > 0.001 and Vector2(tr.origin.x, tr.origin.z).distance_to(Vector2(world.x, world.z)) < radius:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), tr.origin))
				hidden += 1
	return hidden


func add_pad(world: Vector3, width: float) -> int:
	if _free_pads.is_empty():
		return -1
	var slot: int = _free_pads.pop_back()
	var aspect := float(_meta.sprites["shadow"].aspect)
	var at := world + Vector3(0.08 * width, 0.03, 0.06 * width)
	decals.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3(width * 1.15, 1.0, width * 1.15 * aspect * 2.2)), at))
	return slot


func release_pad(slot: int) -> void:
	if slot < 0 or decals == null:
		return
	decals.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_free_pads.append(slot)


func _multimesh(parent: Node3D, node_name: String, material: Material, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _card_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.center_offset = Vector3(0, 0.5, 0)
	return q


func _decal_mesh() -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2.ONE
	return p


func _card_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.0;
varying vec4 rect;
varying float shade;
void vertex() {
    rect = INSTANCE_CUSTOM;
    shade = COLOR.g;
    VERTEX.y -= COLOR.r;  // sink the sprite's painted foot into the ground
    float sx = length(MODEL_MATRIX[0].xyz);
    float sy = length(MODEL_MATRIX[1].xyz);
    // camera-facing card: in an orthographic view the whole card has the depth of its base
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec4 c = texture(atlas, rect.xy + vec2(UV.x, UV.y) * rect.zw);
    ALBEDO = c.rgb * brightness * shade;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	return m


func _decal_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
varying vec4 rect;
void vertex() { rect = INSTANCE_CUSTOM; }
void fragment() {
    vec4 c = texture(atlas, rect.xy + UV * rect.zw);
    ALBEDO = c.rgb;
    ALPHA = c.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	return m
```

Notes for the implementer: `VERTEX.y -= COLOR.r` sinks the card by `sink` of its own (unit) height before scaling; `INV_VIEW_MATRIX[1]` is the camera up, so the card stays upright on screen whatever the yaw. If Godot reports that `MODELVIEW_MATRIX` is read-only in this render mode, use the documented billboard pattern from `BaseMaterial3D` (`BILLBOARD_ENABLED` generated code: `MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);` followed by the scale multiply) and say so in the commit body.

- [ ] **Step 5: Wire it into the game**

In `earthfront_3d.gd`: `const WorldProps := preload("res://scripts/world/world_props.gd")`, `var world_props: RefCounted`.
- `_sync_ground` stores the snapshot deposits for the dressing pass: `_ground_deposits = snapshot.get("deposits", [])` (declare `var _ground_deposits: Array = []`) before `_build_terrain_dressing()`.
- `_build_terrain_dressing`: inside the tile loop, call `_dress_ground_tile` only when `not world_art_on` (legacy world_tree and rock dressing stays for any future non-profile ground). After the loop, before `_build_hex_grid()`:

```gdscript
	if world_art_on:
		world_props = WorldProps.new()
		var items := WorldProps.plan(ground_model, _ground_deposits, Vector2(MAP_ORIGIN_X, MAP_ORIGIN_Z), Vector2(HEX_X, HEX_Z), int(WorldArt.CAMERA.edge_cells))
		world_props.build(self, items, func(x: float, z: float) -> float: return terrain_renderer.height_at_world(x, z))
```

The two MultiMeshInstance3D nodes are children added inside the `first_child..get_child_count()` window, so they join `terrain_dressing` and are freed on a rebuild like every other dressing node.

- [ ] **Step 6: Run the tests**

Run: `$TESTS -- test_world_props`, `$TESTS -- test_world_art_survival`, full suite with leak lines. Expected: pass; leak lines at most 4 and 2 (the test frees `parent`, which frees the MultiMeshInstance3D nodes; MultiMesh and ShaderMaterial are RefCounted).

Time the bake: add a temporary `print(Time.get_ticks_msec())` around `_sync_ground` in a harness run (do not commit it) or read the `perf` sidecar; ground bake plus scatter must stay under 1.5 s on the target machine (software rendering timings are fine as an upper bound).

- [ ] **Step 7: Calibrate and check**

At most four rounds: `world_capture.py $SCRATCH/world/t7 --display :94`, `world_diff.py run ... --check tools/ui/world_scores.json --require gp01:+5,gp04:+4,gp07:+4`. Tune `RULES` densities and sizes and the card `brightness` uniform only. Exit criteria: `raw.clutter_ratio` and `raw.detail_ratio` between 0.6 and 1.6 on gp01, gp04, gp05 and gp07; the required deltas met; `draw_calls` in `home.json` no more than the baseline `_perf.home.draw_calls + 120`.

Visual checklist: Hollow Wood is a dense painted canopy, not lollipops; scrub and rocks scattered on grass and flats; rock clusters on the ridge; willows along the river; craters on the flats; pebbles on Wyllow Ford; every card has a soft drop shadow to the lower right; cards never float or sink visibly; at max zoom there is no shimmering (mipmaps on).

- [ ] **Step 8: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t7 --out $SCRATCH/world/side_t7 --write tools/ui/world_scores.json
git add tools/ui/build_prop_atlas.py tools/ui/test_build_prop_atlas.py godot3d/assets/world/props_atlas.png godot3d/assets/world/props_atlas.png.import godot3d/assets/world/props_atlas.json godot3d/scripts/world/world_props.gd godot3d/tests/test_world_props.gd godot3d/tests/test_world_art_survival.gd godot3d/scripts/earthfront_3d.gd tools/ui/world_scores.json
git commit -m "Godot: Kestrel painted props as two MultiMeshes (canopy, scrub, rocks, willows, craters, pebbles, shadows)"
```

(Add the `.uid` files Godot creates for new scripts if they appear.)

---

### Task 8: Ore and alloy crystals on deposits

**Files:**
- Modify: `godot3d/scripts/earthfront_3d.gd` (`_sync_bridge_map` deposit loop at ~1949), `godot3d/tests/test_world_art.gd`, `godot3d/tests/test_world_art_survival.gd`

**Interfaces:**
- Consumes: Task 7 crystals (already planned on deposit tiles from `_ground_deposits`).
- Produces: under the profile each deposit is an empty `Node3D` named `Deposit_<kind>_<x>_<y>` in group `resource_deposits` (kept so every existing group user still finds it), `deposit_tiles` filled as before, no disk, spheres or Label3D.

- [ ] **Step 1: Check the HUD carries the label**

Find the resource pins (`grep -rn "resource_pins\|ResourcePins" godot3d/scripts/ui`; today they live in `godot3d/scripts/ui/hud.gd` and `godot3d/scripts/ui/sections/region_map.gd`) and confirm they show a pin per deposit on Kestrel, with a test under `godot3d/tests/` that pins it (`grep -rln "deposit" godot3d/tests | grep -i "pin\|region\|hud"`). If it does not cover deposits, stop and report: W9 then needs a Label3D kept, which is a spec change.

- [ ] **Step 2: Write the failing tests**

Append to `test_world_art.gd`:

```gdscript
func test_kestrel_deposits_are_crystals_without_labels(t) -> void:
	var scene := _kestrel_scene()
	scene._sync_bridge_map(_snap())
	var deposits := scene.find_children("Deposit_*", "Node3D", true, false)
	t.eq(deposits.size(), _snap()["deposits"].size(), "one deposit node per deposit")
	for d in deposits:
		t.eq(d.get_child_count(), 0, "no disk, spheres or ORE label under the profile (%s)" % d.name)
		t.ok(d.is_in_group("resource_deposits"), "still in its group")
	t.eq(scene.deposit_tiles.size(), _snap()["deposits"].size(), "build rules still see every deposit tile")
	scene.free()
```

Append to `test_world_art_survival.gd`:

```gdscript
func test_survival_deposits_keep_their_disk_and_label(t) -> void:
	var scene := _survival_scene()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	var snap: Dictionary = JSON.parse_string(f.get_as_text())
	scene._sync_bridge_map(snap)
	var labels := 0
	for d in scene.find_children("Deposit_*", "Node3D", true, false):
		labels += d.find_children("*", "Label3D", true, false).size()
	t.ok(labels > 0, "legacy ORE labels")
	scene.free()
```

`is_in_group` works outside the tree for groups added with `add_to_group` (Godot stores them on the node). If the runner reports otherwise, assert `d.get_groups().has("resource_deposits")` instead. The halo loop at `_process` (~1184) uses `get_node_or_null("ResourceHalo")`, so an empty deposit node is safe there.

- [ ] **Step 3: Run them to see them fail**

Run: `$TESTS -- test_world_art`. Expected: FAIL on "no disk, spheres or ORE label".

- [ ] **Step 4: Implement**

In `_sync_bridge_map`, inside the deposit loop, right after `root.position = ...`:

```gdscript
		if world_art_on:
			continue  # crystals are cards in WorldProps (spec addendum W9); the HUD pins carry the label
```

- [ ] **Step 5: Run the tests and check**

Run: `$TESTS -- test_world_art`, `$TESTS -- test_world_art_survival`, full suite. Harness: `world_capture.py $SCRATCH/world/t8 --only home,ford,flats --display :94`; visual: cyan crystals on the river ore sites, purple alloy on the ridge (35, 1), (31, 2), (39, 3), each with a drop shadow, no grey spheres or `ORE` text. Building a Refinery on an ore tile still works (in a harness, the placement ghost turns valid over a deposit and invalid off it, per `_update_hover_tile` rules at ~2379).

- [ ] **Step 6: Commit**

```bash
git add godot3d/scripts/earthfront_3d.gd godot3d/tests/test_world_art.gd godot3d/tests/test_world_art_survival.gd
git commit -m "Godot: Kestrel deposits are painted ore and alloy crystals (no disk, spheres or label)"
```

---

### Task 9: Buildings and units: authored models, width table, pads, rings

**Files:**
- Create: `godot3d/tests/test_world_models.gd`
- Modify: `godot3d/scripts/world/world_art.gd`, `godot3d/scripts/earthfront_3d.gd` (`_create_bridge_building` ~1980, `_create_unit` 962, `_set_selection` 1386, `_place_scene` recolour 2682), `godot3d/tests/test_world_art_survival.gd`, `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: `world_props.clear_around`, `add_pad`, `release_pad`.
- Produces: `WorldArt.BUILDING_TILES`, `WorldArt.UNIT_TILES`, `WorldArt.MODEL_PALETTE`, `static func merged_aabb(root: Node3D) -> AABB`, `static func fit_factor(root: Node3D, tiles: float) -> float`; node meta `visual_tiles` (float) on every profile building and unit root.

- [ ] **Step 1: Write the failing tests**

`godot3d/tests/test_world_models.gd`:

```gdscript
extends RefCounted
## Kestrel buildings and units (spec addendum W6): authored models fitted to a visual width table in tiles.
const WorldArt := preload("res://scripts/world/world_art.gd")
const MainScene = preload("res://main.tscn")


func _kestrel_scene() -> Node3D:
	var scene = MainScene.instantiate()
	scene._create_materials()
	scene._setup_environment()
	scene._build_terrain()
	var f := FileAccess.open("res://tests/fixtures/kestrel_snapshot.json", FileAccess.READ)
	scene._sync_ground(JSON.parse_string(f.get_as_text()))
	return scene


func _width(node: Node3D) -> float:
	var box := WorldArt.merged_aabb(node)
	return maxf(box.size.x, box.size.z) * node.scale.x


func test_fit_factor_hits_the_target_width(t) -> void:
	var packed := load("res://assets/models/authored/human_hq.glb") as PackedScene
	var hq := packed.instantiate() as Node3D
	var k := WorldArt.fit_factor(hq, 2.8)
	hq.scale = Vector3.ONE * k
	t.near(_width(hq), 2.8 * WorldArt.TILE, 0.01, "the CC is 2.8 tiles wide")
	hq.free()


func test_every_building_kind_has_a_width(t) -> void:
	for kind in ["CommandCenter", "PowerPlant", "Refinery", "Barracks", "VehicleFactory", "Airfield", "SupplyDepot", "Battery", "GunTurret", "AaTurret", "Wall", "ResearchLab", "AntimatterPlant"]:
		t.ok(WorldArt.BUILDING_TILES.has(kind), kind)


func test_kestrel_buildings_are_authored_and_sized(t) -> void:
	var scene := _kestrel_scene()
	for kind in ["CommandCenter", "Barracks", "GunTurret", "Wall"]:
		var root: Node3D = scene._create_bridge_building(0, kind, Vector3(10, 0, 10), 900)
		var visual := root.get_node("Visual") as Node3D
		t.ok(visual.scene_file_path.ends_with(".glb"), "%s uses the authored model" % kind)
		t.near(_width(visual), float(WorldArt.BUILDING_TILES[kind]) * WorldArt.TILE, 0.05, "%s width" % kind)
		t.near(float(root.get_meta("visual_tiles", 0.0)), float(WorldArt.BUILDING_TILES[kind]), 0.001, "%s meta" % kind)
		t.eq(root.find_children("*", "Label3D", true, false).size(), 0, "%s has no banner" % kind)
		var bar := root.get_node("HealthBack") as Node3D
		t.ok(bar.position.y > WorldArt.merged_aabb(visual).end.y * visual.scale.y, "%s health bar above the model" % kind)
	scene.free()


func test_kestrel_tank_is_bigger_than_infantry(t) -> void:
	var scene := _kestrel_scene()
	scene._create_unit(0, Vector3(6, 0, 6), 1)
	var tank: Node3D = scene.units.back()
	scene._create_unit(0, Vector3(7, 0, 6), 0)
	var rifle: Node3D = scene.units.back()
	t.near(float(tank.get_meta("visual_tiles", 0.0)), float(WorldArt.UNIT_TILES[1]), 0.001, "tank width from the table")
	t.ok(float(tank.get_meta("visual_tiles")) > float(rifle.get_meta("visual_tiles")), "tank reads bigger than a rifle squad")
	scene.free()
```

Append to `test_world_art_survival.gd`:

```gdscript
func test_survival_keeps_tactical_buildings(t) -> void:
	var scene := _survival_scene()
	var site := Node3D.new()
	scene.add_child(site)
	var hq: Node3D = scene.tactical_models.building(scene, site, "CommandCenter")
	t.ok(hq != null, "the box-built CC still builds")
	t.ok(not site.has_meta("visual_tiles"), "no width table outside the profile")
	scene.free()
```

(`_create_bridge_building` itself cannot run on the Survival scene in a headless test because its legacy branch calls `get_tree()`; the live Survival frame in Task 10 covers that path.)

- [ ] **Step 2: Run them to see them fail**

Run: `$TESTS -- test_world_models`. Expected: FAIL (`merged_aabb` missing).

- [ ] **Step 3: Implement the tables and fit**

In `world_art.gd`:

```gdscript
const BUILDING_TILES := {"CommandCenter": 2.8, "Barracks": 2.1, "VehicleFactory": 2.1, "Airfield": 2.1, "ResearchLab": 2.1,
	"Refinery": 2.1, "AntimatterPlant": 2.1, "PowerPlant": 1.7, "Battery": 1.7, "SupplyDepot": 1.7, "GunTurret": 1.3,
	"AaTurret": 1.3, "Wall": 1.0}
const UNIT_TILES := [1.0, 1.6, 1.0, 1.5, 1.8, 1.5]  # by _create_unit kind: infantry, tank, anti-armour, gunship, capital, harvester
## Authored material name (lower case contains) -> albedo for the boards' warm concrete, olive and gunmetal.
const MODEL_PALETTE := {"concrete": "b3a893", "olive": "6f7448", "gunmetal": "474d52", "energy": "3f8f9c"}


## Union of every MeshInstance3D AABB under `root`, in `root`'s local space (works outside the scene tree).
static func merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != root and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var box: AABB = xf * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func fit_factor(root: Node3D, tiles: float) -> float:
	var box := merged_aabb(root)
	var width := maxf(box.size.x, box.size.z)
	return tiles * TILE / width if width > 0.0001 else 1.0
```

- [ ] **Step 4: Use them in the game**

`_create_bridge_building`:
- Under the profile skip `tactical_models.building` (the `if owner == HUMAN and kind_name in [...]` branch becomes `if not world_art_on and owner == HUMAN and ...`), and map `VehicleFactory` to `human_industry` for the human side when `world_art_on`.
- After `visual.name = "Visual"`:

```gdscript
	if world_art_on:
		var tiles := float(WorldArt.BUILDING_TILES.get(kind_name, 1.7))
		var key := "%d:%s" % [owner, asset_name]
		if not _fit_cache.has(key):
			_fit_cache[key] = WorldArt.fit_factor(visual, tiles)
		visual.scale = Vector3.ONE * float(_fit_cache[key])
		root.set_meta("visual_tiles", tiles)
		if world_props != null:
			world_props.clear_around(destination, tiles * WorldArt.TILE * 0.5)
			var slot: int = world_props.add_pad(destination, tiles * WorldArt.TILE)
			root.tree_exiting.connect(func(): world_props.release_pad(slot))
	else:
		for prop in get_tree().get_nodes_in_group("scenery"):
			if prop is Node3D and prop.global_position.distance_to(destination) < 0.85:
				prop.hide()
```

(Declare `var _fit_cache: Dictionary = {}`. The cache keeps one AABB walk per model. `merged_aabb` measures in the visual's own local space, before its scale, so `fit_factor` is the absolute scale to set; never multiply it by the authored scale.) Note `tree_exiting` also fires when the whole scene is freed; `release_pad` ignores a null `decals`.
- Wrap the `CommandCenter` banner block in `if not world_art_on:`.
- The four health/shield bar `_box` calls: compute `var bar_y := (WorldArt.merged_aabb(visual).end.y * visual.scale.y + 0.18) if world_art_on else 1.15` and use `bar_y`, `bar_y + 0.005`, `bar_y + 0.09`, `bar_y + 0.095` for the four y values (legacy keeps 1.15, 1.155, 1.24, 1.245).

`_create_unit`: after the model call (`_create_human_unit_model` / `_create_alien_unit_model`):

```gdscript
	if world_art_on:
		var visual := root.get_node_or_null("UnitVisual") as Node3D
		var tiles := float(WorldArt.UNIT_TILES[clampi(kind, 0, WorldArt.UNIT_TILES.size() - 1)])
		if visual != null:
			var key := "unit:%d:%d" % [team, kind]
			if not _fit_cache.has(key):
				_fit_cache[key] = WorldArt.fit_factor(visual, tiles)
			visual.scale = Vector3.ONE * float(_fit_cache[key])
		root.set_meta("visual_tiles", tiles)
```

If the tactical infantry path (`kind == 0 or kind == 2`) builds no node named `UnitVisual`, wrap what `tactical_models.infantry` adds in a `Node3D` named `UnitVisual` under the profile only, or fit the root's first Node3D child; say which in the commit body. The alien model function must also name its visual `UnitVisual` (check it does).

`_place_scene` recolour: when `world_art_on`, use `WorldArt.MODEL_PALETTE` colours for the same four material-name checks (legacy colours unchanged otherwise).

`_set_selection`: after `selection_ring.visible = true`:

```gdscript
	var ring_scale := 1.0
	if world_art_on and selected.has_meta("visual_tiles"):
		ring_scale = float(selected.get_meta("visual_tiles")) * WorldArt.TILE * 0.55 / 0.46
	selection_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
```

- [ ] **Step 5: Run the tests**

Run: `$TESTS -- test_world_models`, `$TESTS -- test_world_art_survival`, `$TESTS -- test_lighting` (the shadow test builds a CC and units; still green), full suite with leak lines.

- [ ] **Step 6: Harness check**

`world_capture.py $SCRATCH/world/t9 --display :94`, then in a separate harness `launch_ui.py $SCRATCH/world/t9p --software --scenario kestrel --display :94 --driver world`: deploy, send `{"type": "probe", "name": "cc", "node": "Core_CommandCenter_000"}` (use the CC node name from the scene; `find_child` matches the first `Core_CommandCenter_*`, adjust the name from `observe()["entities"]` if the id differs) and check the union of hit rects is 2.8 x 0.68 x 1080 / 10 = 206 px wide, plus or minus 30 px, at zoom 10. Picking: every `observation.json["tiles"]` entry has `picked == tile`; click a hex just outside the CC tile but inside the CC model's screen rect and check the observation's hovered tile (tile inspector) is that hex, not the CC. Build a Barracks next to the CC with the deck: the ghost shows, props under the new site vanish, a contact pad appears, the selection ring wraps the model. Kill the PIDs.

`world_diff.py run ... --check tools/ui/world_scores.json --require gp01:+3,gp04:+3`. Visual checklist (side_gp01, side_gp04): buildings read as big painted-looking structures like the boards (warm concrete, olive), tanks clearly bigger than rifle squads, each building sits on a soft pad, no `COMMAND` text.

- [ ] **Step 7: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t9 --out $SCRATCH/world/side_t9 --write tools/ui/world_scores.json
git add godot3d/scripts/world/world_art.gd godot3d/scripts/earthfront_3d.gd godot3d/tests/test_world_models.gd godot3d/tests/test_world_art_survival.gd tools/ui/world_scores.json
git commit -m "Godot: Kestrel buildings and units use authored models fitted to a width table, with pads and rings"
```

---

### Task 10: Perf and Survival regression gate

**Files:**
- Modify: `tools/ui/world_baseline.json` (only the `_perf_gpu` block, if a GPU run is approved), `docs/superpowers/plans/2026-10-05-kestrel-world-art.md` (tick the gate results into this task's checklist)

**Interfaces:**
- Consumes: everything above; `tools/ui/world_baseline.json` `_perf`.
- Produces: a recorded pass/fail for each budget; no product code changes unless a budget fails (then fix in the owning task's files and say so).

- [ ] **Step 1: Headless suite with no display at all**

Run: `env -u DISPLAY $TESTS 2>&1 | tee $SCRATCH/world/suite.log | tail -8`
Expected: all pass (count = Task 1 count + every new test); `grep -c "SCRIPT ERROR" $SCRATCH/world/suite.log` is 0; the leak lines show at most `4` ObjectDB instances and `2` resources. If they grew, find the new owner (a scene built in a test and not freed, a MultiMesh held in a static) and free it in the test or code of the task that introduced it.

- [ ] **Step 2: Rust and golden untouched**

Run: `git diff --stat d81deab..HEAD -- crates/` (empty) and `cargo test -p rts-core golden_hash_pins_cross_target_determinism --offline` (passes).

- [ ] **Step 3: Software perf against the baseline**

`python3 tools/qa/world_capture.py $SCRATCH/world/t10 --display :94 --perf 20`. Compare `home.json` and `max.json` with `world_baseline.json["_perf"]`: draw calls at most baseline + 120, primitives at most baseline + 150000, `process_ms` at most 1.10 x baseline. Software fps is not a budget (llvmpipe), only a sanity check that it is not lower than half the baseline's.

- [ ] **Step 4: GPU perf (only with the controller's approval)**

Ask the controller: a GPU run opens a window on the user's display. If approved: `python3 tools/qa/world_capture.py $SCRATCH/world/t10g --gpu --perf 30` at HEAD, and the same at `d81deab` in a separate worktree (`git worktree add $SCRATCH/world/base_tree d81deab`; build nothing, the Godot project is client-only; the bridge binary `target/release/godot-bridge` is shared). Budgets: idle fps at least 0.9 x baseline, draw calls and primitives as Step 3. Record both in `world_baseline.json` under `"_perf_gpu"`. Remove the worktree afterwards (`git worktree remove $SCRATCH/world/base_tree`). If not approved, record "GPU perf not measured" in the final report.

- [ ] **Step 5: Survival looks the same**

`python3 tools/qa/world_capture.py $SCRATCH/world/t10s --scenario survival --display :94`, then `python3 tools/ui/world_diff.py pair $SCRATCH/world/surv/survival_home.png $SCRATCH/world/t10s/survival_home.png --crop 0,0,1920,1080 --out $SCRATCH/world/side_survival.png`. Expected total at least 97 (units move between runs, so not 100). Open the side-by-side: same rotated camera, same green noise terrain, same box-built HQ, same amber hover torus.

- [ ] **Step 6: Commit (only if files changed)**

```bash
git add tools/ui/world_baseline.json
git commit -m "QA: record the Kestrel world-art perf gate"
```

---

### Task 11: Final polish against all boards, and docs

**Files:**
- Modify: any table in `world_art.gd`, `world_props.gd`, `continuous_terrain.gd` (`GROUND_LOOK`, uniform defaults), `docs/ascension/ui-deviations.md`, `docs/ascension/ui-mocks-gameplay/README.md`, `tools/ui/world_scores.json`

**Interfaces:**
- Consumes: all of the above. Tuning edits tables and uniform defaults only; any code change goes back through the owning task's tests.

- [ ] **Step 1: Full scoreboard**

`world_capture.py $SCRATCH/world/t11 --display :94`, `world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t11 --out $SCRATCH/world/side_t11 --check tools/ui/world_baseline.json`. Print every board's delta against the frozen baseline.

- [ ] **Step 2: Polish rounds (at most five)**

For each board, open its side-by-side and list the top three visible differences. Fix only through tables (prop density and size, palette, grade, water uniforms, camera default zoom within 9 to 11). Re-capture and re-score after each round; keep a round only if no board drops beyond tolerance. Target: every board at least 20 points above `world_baseline.json`. If a board cannot get there, write down why (for example gp08's cyan overlay lines are HUD world marks, not ground) instead of over-tuning.

Final visual checklist against gp01, gp03, gp04, gp05, gp06, gp07, gp08:
- [ ] Olive textured ground with visible painted detail, no flat green, no orange flats.
- [ ] River with sand banks, dark edges, lighter centre, pebbled ford; deep bay with a surf line.
- [ ] Dense canopy in Hollow Wood, scattered scrub and rocks, willows along the river, craters.
- [ ] Cyan ore and purple alloy crystals, no grey spheres or labels.
- [ ] Big readable buildings with pads; tanks bigger than infantry; cyan selection ring sized to the model.
- [ ] North-up framing, warm top-left, darker bottom-right, no sky or void at any zoom or edge.
- [ ] No yellow blob anywhere (`world_diff.py blobs` on `home.png`, `flats.png`, `ford.png` returns nothing larger than 400 px inside the battlefield crops).
- [ ] HUD chrome numbers unchanged: `bash tools/ui/verify_all.sh` matches its pre-plan output.

- [ ] **Step 3: Docs**

- `docs/ascension/ui-deviations.md`: add a "Kestrel world art (2026-10-05)" section listing what still differs from the boards and why: buildings and units are 3D models (not the painted sprites), single-hex placement means neighbouring big models can overlap visually, the camera keeps a 57 degree pitch, props are billboard cards, the sea gradient is computed from coast distance, any board that missed the +20 target with its reason.
- `docs/ascension/ui-mocks-gameplay/README.md`: one paragraph on how the live world now follows `terrain/gen.py` (which layers map to which shader band or prop rule) and how to re-score with `world_capture.py` and `world_diff.py`.
- Grep both files for em and en dashes: `grep -nP "\x{2013}|\x{2014}" docs/ascension/ui-deviations.md docs/ascension/ui-mocks-gameplay/README.md` prints nothing.

- [ ] **Step 4: Full gate**

Run the full headless suite (pass count, no SCRIPT ERROR, leak lines), `cd tools/ui && python3 -m unittest test_world_diff test_build_prop_atlas -v`, `git diff --stat d81deab..HEAD -- crates/` (empty).

- [ ] **Step 5: Commit**

```bash
python3 tools/ui/world_diff.py run --mocks $SCRATCH/world/mocks --live $SCRATCH/world/t11 --out $SCRATCH/world/side_t11 --write tools/ui/world_scores.json
git add <the tables you tuned> docs/ascension/ui-deviations.md docs/ascension/ui-mocks-gameplay/README.md tools/ui/world_scores.json
git commit -m "Godot: Kestrel world-art polish against the gameplay boards, plus deviations and README"
```

Report to the controller: every board's baseline and final total, the per-glyph Delta E, the perf numbers (software, and GPU if measured), the suite count and leak lines, and the side-by-side PNG paths for gp01 and gp05 so the user can look at them.
