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
