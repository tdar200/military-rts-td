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


def scene(seed=1, w=480, h=300, grain=10.0, trees=True, river=True, tan=True):
    """A painted-board stand-in: olive field, diagonal blue river, tan flats, dark tree blobs, bright sprites, fine grain."""
    rng = np.random.default_rng(seed)
    img = np.tile(np.array([0x80, 0x88, 0x44], float), (h, w, 1))
    yy, xx = np.mgrid[0:h, 0:w]
    if river:
        d = (xx * 0.6 + yy) - 330
        img[np.abs(d) < 28] = (0x2a, 0x5f, 0x7e)
    if tan:
        img[(xx * 0.6 + yy) > 420] = (0xac, 0x96, 0x5e)
    if trees:
        for _ in range(26):
            cx, cy, r = rng.integers(20, w - 20), rng.integers(20, h - 20), rng.integers(6, 14)
            img[(xx - cx) ** 2 + (yy - cy) ** 2 < r * r] = (0x30, 0x50, 0x28)
        for _ in range(8):
            x0, y0 = rng.integers(10, w - 40), rng.integers(10, h - 30)
            img[y0:y0 + 14, x0:x0 + 26] = (0xd8, 0xd2, 0xc0)
    img += rng.normal(0, grain, (h, w, 1))
    return np.clip(img, 0, 255).astype(np.uint8)


def match_histogram(src, ref):
    """Per-channel histogram match: the strongest colour-only grade there is."""
    out = np.empty_like(src)
    for c in range(3):
        order = np.argsort(src[..., c], axis=None)
        vals = np.sort(ref[..., c], axis=None)
        idx = np.linspace(0, vals.size - 1, order.size).astype(int)
        flat = np.empty(order.size, np.uint8)
        flat[order] = vals[idx]
        out[..., c] = flat.reshape(src.shape[:2])
    return out


def smooth_noise(w=480, h=300, seed=5, sigma=14):
    from scipy import ndimage
    rng = np.random.default_rng(seed)
    f = ndimage.gaussian_filter(rng.normal(size=(h, w, 3)), (sigma, sigma, 0))
    f = (f - f.min()) / (f.max() - f.min())
    return (f * 255).astype(np.uint8)


class GamingTests(unittest.TestCase):
    """A genuinely closer frame must beat every cheap treatment that only matches colour statistics."""

    @classmethod
    def setUpClass(cls):
        cls.mock = scene(1)
        cls.sm = wd.stats(cls.mock, None)
        cls.tot = lambda cls_, live: wd.score(cls.sm, wd.stats(live, None))

    def total(self, live):
        return wd.score(self.sm, wd.stats(live, None))["total"]

    def test_genuinely_closer_frame_scores_high(self):
        self.assertGreater(self.total(scene(2)), 95)

    def test_histogram_matched_live_scores_clearly_worse(self):
        gamed = match_histogram(smooth_noise(), self.mock)
        self.assertLess(self.total(gamed), self.total(scene(2)) - 25)

    def test_shuffled_mock_pixels_score_clearly_worse(self):
        rng = np.random.default_rng(3)
        flat = self.mock.reshape(-1, 3).copy()
        rng.shuffle(flat)
        gamed = flat.reshape(self.mock.shape)
        self.assertLess(self.total(gamed), self.total(scene(2)) - 25)

    def test_flat_tint_scores_clearly_worse(self):
        for tint in ("808844", "246c07"):
            gamed = flat(480, 300, tint)
            gamed = (self.mock * 0.35 + gamed * 0.65).astype(np.uint8)  # a 65 percent flat grade over the mock itself
            self.assertLess(self.total(gamed), self.total(scene(2)) - 15, tint)
            self.assertLess(self.total(flat(480, 300, tint)), self.total(scene(2)) - 25, tint)

    def test_grade_only_cannot_pass_a_gate(self):
        # the three treatments stay under 75 while a real match is over 95
        rng = np.random.default_rng(3)
        sh = self.mock.reshape(-1, 3).copy(); rng.shuffle(sh)
        for live in (match_histogram(smooth_noise(), self.mock), sh.reshape(self.mock.shape), flat(480, 300, "808844")):
            self.assertLess(self.total(live), 75)


class StructureTests(unittest.TestCase):
    """The grade-proof subscore: a histogram match or tint of the SAME frame must not move it, real structure must."""

    def test_colour_grade_leaves_structure_alone_and_real_structure_moves_it(self):
        mock = scene(1)
        sm = wd.stats(mock, None)
        poor = scene(2, river=False, tan=False, trees=False, grain=3.0)  # right palette family, no regions or objects
        base = wd.score(sm, wd.stats(poor, None))
        graded = wd.score(sm, wd.stats(match_histogram(poor, mock), None))
        real = wd.score(sm, wd.stats(scene(2), None))
        self.assertLess(abs(graded["structure"] - base["structure"]), 6)
        self.assertGreater(real["structure"], base["structure"] + 15)

    def test_flat_has_no_structure(self):
        res = wd.score(wd.stats(scene(1), None), wd.stats(flat(480, 300, "808844"), None))
        self.assertLess(res["structure"], 30)


class TermTests(unittest.TestCase):
    """Each term moves on a partial improvement (no term is pinned at its cap on a realistic gap)."""

    def setUp(self):
        self.mock = scene(1)
        self.sm = wd.stats(self.mock, None)

    def terms(self, live):
        return wd.score(self.sm, wd.stats(live, None))

    def test_saturation_and_warmth_improve_with_colour(self):
        far = self.terms(flat(480, 300, "246c07"))
        near = self.terms(flat(480, 300, "808844"))
        self.assertLess(near["saturation"], far["saturation"])
        self.assertLess(near["warmth"], far["warmth"])
        self.assertLess(near["palette"], far["palette"])

    def test_detail_improves_with_texture(self):
        bare = self.terms(flat(480, 300, "808844"))
        rng = np.random.default_rng(4)
        grain = np.clip(np.array([0x80, 0x88, 0x44], float) + rng.normal(0, 10, (300, 480, 1)), 0, 255).astype(np.uint8)
        half = self.terms(grain)
        full = self.terms(scene(2))
        self.assertLess(half["detail"], bare["detail"])
        self.assertLess(full["detail"], half["detail"])

    def test_clutter_improves_with_sprites_and_trees(self):
        bare = self.terms(scene(2, trees=False))
        full = self.terms(scene(2))
        self.assertLess(full["clutter"], bare["clutter"])

    def test_layout_improves_with_the_right_regions(self):
        wrong = self.terms(scene(2, river=False, tan=False))
        right = self.terms(scene(2))
        self.assertLess(right["layout"], wrong["layout"])

    def test_every_term_inside_its_range_for_a_realistic_gap(self):
        res = self.terms(scene(2, river=False, tan=False, trees=False, grain=2.0))
        for key, cap in wd.WEIGHTS.items():
            self.assertLess(res[key], cap, key)


class RunTests(unittest.TestCase):
    """run(): a missing board, a typo or a missing check entry must fail, never pass vacuously."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = pathlib.Path(self.tmp.name)
        for d in ("mocks", "live"):
            (t / d).mkdir()
        for b in ("gp01", "gp05"):
            Image.fromarray(scene(1)).save(t / "mocks" / f"{b}.png")
        Image.fromarray(scene(2)).save(t / "live" / "home.png")
        Image.fromarray(scene(2, trees=False)).save(t / "live" / "ford.png")
        cfg = {"noise": 0.1, "palette": {"g": "808844"},
               "boards": {"gp01": {"frame": "home", "crop": [0, 0, 480, 300], "mask": []},
                          "gp05": {"frame": "ford", "crop": [0, 0, 480, 300], "mask": []}}}
        (t / "frames.json").write_text(json.dumps(cfg))
        self.t = t
        base = ["run", "--mocks", str(t / "mocks"), "--live", str(t / "live"), "--out", str(t / "out"), "--frames", str(t / "frames.json")]
        self.base = base
        wd.main(base + ["--write", str(t / "scores.json")])
        self.scores = t / "scores.json"

    def tearDown(self):
        self.tmp.cleanup()

    def go(self, *extra):
        return wd.main(self.base + list(extra))

    def test_plain_run_and_check_pass(self):
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.go("--check", str(self.scores)), 0)

    def test_require_without_check_fails(self):
        self.assertNotEqual(self.go("--require", "gp05:+5"), 0)

    def test_require_typo_fails(self):
        self.assertNotEqual(self.go("--check", str(self.scores), "--require", "gp5:+5"), 0)

    def test_require_board_not_scored_fails(self):
        self.assertNotEqual(self.go("--boards", "gp01", "--check", str(self.scores), "--require", "gp05:+5"), 0)

    def test_board_missing_from_check_file_fails(self):
        data = json.loads(self.scores.read_text())
        del data["gp05"]
        partial = self.t / "partial.json"
        partial.write_text(json.dumps(data))
        self.assertNotEqual(self.go("--check", str(partial)), 0)
        self.assertNotEqual(self.go("--check", str(partial), "--require", "gp05:+5"), 0)

    def test_unknown_board_fails(self):
        self.assertNotEqual(self.go("--boards", "gp99"), 0)

    def test_malformed_require_fails(self):
        self.assertNotEqual(self.go("--check", str(self.scores), "--require", "gp05"), 0)

    def test_require_structure_paths(self):
        data = json.loads(self.scores.read_text())
        self.assertNotEqual(self.go("--require-structure", "gp05:+3"), 0)  # needs --check
        self.assertNotEqual(self.go("--check", str(self.scores), "--require-structure", "gp05:+3"), 0)  # no gain
        self.assertNotEqual(self.go("--check", str(self.scores), "--require-structure", "gp5:+3"), 0)  # typo
        data["gp05"]["structure"] -= 10
        low = self.t / "low.json"
        low.write_text(json.dumps(data))
        self.assertEqual(self.go("--check", str(low), "--require-structure", "gp05:+3"), 0)
        del data["gp05"]["structure"]
        old = self.t / "old.json"
        old.write_text(json.dumps(data))
        self.assertNotEqual(self.go("--check", str(old), "--require-structure", "gp05:+3"), 0)  # old baseline without the key

    def test_unmet_requirement_fails_and_met_passes(self):
        self.assertNotEqual(self.go("--check", str(self.scores), "--require", "gp05:+5"), 0)  # same frame, 0.00 gained
        data = json.loads(self.scores.read_text())
        data["gp05"]["total"] -= 10
        worse = self.t / "worse.json"
        worse.write_text(json.dumps(data))
        self.assertEqual(self.go("--check", str(worse), "--require", "gp05:+5"), 0)

    def test_regression_beyond_tolerance_fails(self):
        data = json.loads(self.scores.read_text())
        data["gp01"]["total"] += 10
        better = self.t / "better.json"
        better.write_text(json.dumps(data))
        self.assertNotEqual(self.go("--check", str(better)), 0)


class BlobTests(unittest.TestCase):
    def test_ground_regions_are_not_blobs(self):
        img = olive_texture()
        img[0:100, 0:200] = (200, 120, 20)   # orange dry flats, large
        img[120:190, 0:200] = (240, 190, 74)  # a large amber region: ground, above max_area
        img[40:80, 250:290] = (240, 190, 74)  # a real marker
        blobs = wd.yellow_blobs(img, min_area=400, max_area=10000)
        self.assertEqual([(b["x"], b["y"]) for b in blobs], [(250, 40)])


if __name__ == "__main__":
    unittest.main()
