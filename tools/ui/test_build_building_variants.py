import colorsys, pathlib, tempfile, unittest
import numpy as np
from PIL import Image
import build_building_variants as bbv

KINDS = {"vehicle_factory", "airfield", "battery", "antimatter_plant", "supply_depot", "research_lab"}


def opaque(im):
    return np.asarray(im.getchannel("A")) > 128


def iou(a, b):
    return (a & b).sum() / max(1, (a | b).sum())


SIL_MIN = 0.30
EDGE_MIN = 0.29
ALIGN = 128


def _aligned(im):
    """The painted body (alpha over 128) cropped to its box and stretched to ALIGN x ALIGN, as floats 0..1: position and
    scale drop out, so a part reused larger or shifted still reads as itself."""
    a = np.asarray(im.convert("RGBA"))
    ys, xs = np.nonzero(a[..., 3] > 128)
    crop = Image.fromarray(a).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)).resize((ALIGN, ALIGN), Image.BILINEAR)
    return np.asarray(crop).astype(np.float64) / 255


def board(name):
    """A board sprite from assets/ (the alien power plant without the stray fragments under its base)."""
    im = Image.open(bbv.SRC / (name + ".png")).convert("RGBA")
    if name == "alien_power_plant_v1":
        a = np.asarray(im).copy()
        a[226:] = 0
        im = Image.fromarray(a)
    return im


def structure_distance(im_a, im_b):
    """(silhouette, edges) between two sprites, both 0 for the same shape. Silhouette: 1 minus the intersection over
    union of the aligned alpha masks. Edges: the Sobel magnitude of the value channel max(R, G, B) times alpha (hue free:
    a hue turn keeps it), blurred 1.5 px, each map scaled to mean 1 over the union of the masks; half the mean absolute
    difference there (0 equal, 1 disjoint)."""
    from scipy import ndimage
    a, b = _aligned(im_a), _aligned(im_b)
    ma, mb = a[..., 3] > 0.5, b[..., 3] > 0.5
    union = ma | mb
    sil = 1.0 - (ma & mb).sum() / max(1, union.sum())

    def edges(x):
        v = x[..., :3].max(-1) * x[..., 3]
        return ndimage.gaussian_filter(np.hypot(ndimage.sobel(v, 0), ndimage.sobel(v, 1)), 1.5)
    ea, eb = edges(a), edges(b)
    ea, eb = ea / max(1e-9, ea[union].mean()), eb / max(1e-9, eb[union].mean())
    return float(sil), float(np.abs(ea - eb)[union].mean() / 2)


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

    def test_structure_metric_ignores_hue(self):
        """The metric below reads shape only: a copy of a board sprite with every hue turned by half the wheel scores 0 on
        both terms (the value channel, max(R, G, B), is what a hue turn keeps), so a recolour can never pass for a new
        building."""
        im = board("barracks_v2")
        hsv = np.asarray(im.convert("RGB").convert("HSV")).copy()
        hsv[..., 0] = (hsv[..., 0].astype(np.int16) + 128) % 256
        turned = Image.fromarray(hsv, "HSV").convert("RGB").convert("RGBA")
        turned.putalpha(im.getchannel("A"))
        sil, edge = structure_distance(im, turned)
        self.assertLess(sil, 0.01)
        self.assertLess(edge, 0.02)

    def test_the_three_weakest_kinds_are_their_own_buildings(self):
        """The alien supply depot and the alien battery were the human depot and battery laid out again in alien plate
        (structure distance 0.08 and 0.07 silhouette), the vehicle factory the barracks hall widened (0.24 silhouette,
        0.29 edges). Each must now differ from the sprite it was built on, from the sprite it was a recolour of and from
        the other two by at least the 10th percentile of the 42 same-side pairs of genuinely different board buildings
        (0.314 silhouette, 0.298 edges, measured with structure_distance on assets/*.png; the closest such pair, the
        human command centre and barracks, scores 0.19 and 0.27), rounded down to SIL_MIN and EDGE_MIN."""
        pairs = [("vehicle_factory_v1", board("barracks_v2")), ("vehicle_factory_v1", "alien_vehicle_factory_v1"),
                 ("alien_supply_depot_v1", board("alien_refinery_v1")), ("alien_supply_depot_v1", "supply_depot_v1"),
                 ("alien_battery_v1", board("alien_power_plant_v1")), ("alien_battery_v1", "battery_v1"),
                 ("alien_supply_depot_v1", "alien_battery_v1"), ("alien_supply_depot_v1", "vehicle_factory_v1"),
                 ("alien_battery_v1", "vehicle_factory_v1")]
        for a, b in pairs:
            other = self.img[b] if isinstance(b, str) else b
            sil, edge = structure_distance(self.img[a], other)
            label = "%s vs %s: silhouette %.3f edges %.3f" % (a, b if isinstance(b, str) else "its source", sil, edge)
            self.assertGreaterEqual(sil, SIL_MIN, label)
            self.assertGreaterEqual(edge, EDGE_MIN, label)

    def test_the_three_keep_their_ground_footprint(self):
        """A new silhouette, the same footprint: the painted base still ends on the row it did (picking, the pad, the bars
        and the selection ellipse read the opaque box), and the box keeps its width and centre within a few pixels, so
        WorldSprites.MOCK_PX and WorldArt.BUILDING_TILES need no change. Pinned from the sprites before Task 9: (box left,
        right, bottom) in canvas pixels, alpha over 128."""
        pins = {"vehicle_factory_v1": (12, 243, 230), "alien_supply_depot_v1": (6, 251, 231), "alien_battery_v1": (26, 231, 235)}
        for n, (x0, x1, y1) in pins.items():
            ys, xs = np.nonzero(opaque(self.img[n]))
            self.assertLessEqual(abs(int(ys.max()) + 1 - y1), 4, "%s bottom %d, pinned %d" % (n, ys.max() + 1, y1))
            width, pinned = int(xs.max()) + 1 - int(xs.min()), x1 - x0
            self.assertLessEqual(abs(width - pinned), 0.12 * pinned, "%s width %d, pinned %d" % (n, width, pinned))
            self.assertLessEqual(abs((int(xs.max()) + 1 + int(xs.min())) / 2 - (x0 + x1) / 2), 10, n + " centre")

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
