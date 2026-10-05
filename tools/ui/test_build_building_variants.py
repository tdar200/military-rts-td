import colorsys, pathlib, tempfile, unittest
import numpy as np
from PIL import Image
import build_building_variants as bbv

KINDS = {"vehicle_factory", "airfield", "battery", "antimatter_plant", "supply_depot", "research_lab"}


def opaque(im):
    return np.asarray(im.getchannel("A")) > 128


def iou(a, b):
    return (a & b).sum() / max(1, (a | b).sum())


def mean_hue_of_glow(im, box):
    """Mean hue (degrees) of the bright, saturated pixels inside `box`."""
    px = [p for p in im.crop(box).getdata() if p[3] > 200]
    hues = []
    for r, g, b, _ in px:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s > 0.45 and v > 0.45:
            hues.append(h * 360)
    return np.median(hues) if hues else None, len(hues)


class VariantTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        cls.paths = bbv.build(cls.dir.name)
        cls.img = {n: Image.open(p) for n, p in cls.paths.items()}

    @classmethod
    def tearDownClass(cls):
        cls.dir.cleanup()

    def test_every_kind_for_both_sides(self):
        want = KINDS | {"alien_" + k for k in KINDS}
        self.assertEqual({n[:-3] for n in self.img}, want)
        for n, im in self.img.items():
            self.assertEqual(im.size, (256, 256), n)
            self.assertEqual(im.mode, "RGBA", n)

    def test_deterministic(self):
        with tempfile.TemporaryDirectory() as d:
            again = bbv.build(d)
            for n, p in again.items():
                self.assertEqual(pathlib.Path(p).read_bytes(), pathlib.Path(self.paths[n]).read_bytes(), n)

    def test_committed_sprites_are_the_script_output(self):
        """The committed PNGs match a fresh build. Resampling and blur rounding can move a channel by a step or two between
        Pillow or numpy versions, so a pixel may differ by up to 4 per channel and at most 1 % of pixels by more than 1;
        a stale sprite (an edited script not rerun) moves far more than that."""
        for n, im in self.img.items():
            committed = bbv.OUT / (n + ".png")
            self.assertTrue(committed.exists(), n)
            d = np.abs(np.asarray(Image.open(committed).convert("RGBA")).astype(np.int16) - np.asarray(im.convert("RGBA")).astype(np.int16))
            self.assertLessEqual(int(d.max()), 4, n + " is stale: rerun the script (max channel difference %d)" % d.max())
            self.assertLess(float((d.max(axis=2) > 1).mean()), 0.01, n + " is stale: rerun the script")

    def test_stands_on_the_boards_contact_line(self):
        """The painted base reaches the contact line (y 218) and runs at most about 25 px past it, as the board sprites do
        (their opaque bottoms are 205 to 243); the card's top row and corners stay transparent."""
        for n, im in self.img.items():
            a = opaque(im)
            ys, xs = np.nonzero(a)
            self.assertTrue(205 <= ys.max() + 1 <= 243, "%s bottom %d" % (n, ys.max() + 1))
            self.assertGreater(ys.min(), 2, n + " top margin")
            self.assertTrue(xs.min() > 2 and xs.max() < 253, n + " side margins")
            self.assertEqual(int(np.asarray(im.getchannel("A"))[:4, :4].max()), 0, n + " corner")

    def test_silhouette_differs_from_the_sprite_it_replaces(self):
        """Against the sprite the kind shared before: the alpha masks overlap by under 82 % (intersection over union) and
        the skyline (each column's top painted pixel) moves by more than 15 px on average (about 10 px at board size), so
        the kind reads as its own building. Sprites built on their old one (factory on the barracks, antimatter plant on
        the power plant) pass by their skyline: crane and stack, the taller core."""
        def skyline(a):
            return np.where(a.any(0), a.argmax(0), 256)
        for n, im in self.img.items():
            src = opaque(Image.open(bbv.SRC / (bbv.SOURCES[n] + ".png")).convert("RGBA"))
            src[226:] = False  # the alien power plant's stray fragments under its base
            a = opaque(im)
            self.assertLess(iou(a, src), 0.82, n)
            pa, ps = skyline(a), skyline(src)
            cols = (pa < 256) | (ps < 256)
            self.assertGreater(float(np.abs(pa[cols] - ps[cols]).mean()), 15.0, n)

    def test_no_two_variants_alike(self):
        names = sorted(self.img)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                pa = np.asarray(self.img[a].convert("RGBA")).astype(np.int16)
                pb = np.asarray(self.img[b].convert("RGBA")).astype(np.int16)
                self.assertGreater(np.abs(pa - pb).mean(), 12, a + " vs " + b)

    def test_accent_colours(self):
        """Batteries glow lime, antimatter plants violet, labs carry a cyan glass dome, the human factory's trim is amber."""
        checks = [("battery_v1", (40, 60, 220, 200), 60, 110), ("alien_battery_v1", (40, 60, 220, 200), 60, 120),
                  ("antimatter_plant_v1", (90, 30, 170, 150), 255, 300), ("alien_antimatter_plant_v1", (90, 30, 170, 150), 255, 300),
                  ("research_lab_v1", (80, 60, 180, 140), 175, 205), ("alien_research_lab_v1", (80, 50, 180, 140), 175, 205),
                  ("vehicle_factory_v1", (40, 60, 220, 230), 25, 50)]
        for n, box, lo, hi in checks:
            hue, count = mean_hue_of_glow(self.img[n], box)
            self.assertGreater(count, 40, n)
            self.assertTrue(lo <= hue <= hi, "%s hue %.0f" % (n, hue))


if __name__ == "__main__":
    unittest.main()
