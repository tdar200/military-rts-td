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
