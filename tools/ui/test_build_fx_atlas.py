import pathlib, tempfile, unittest
import numpy as np
from PIL import Image
import build_fx_atlas as bfa


def cell(arr, band, row, col, span=1):
    c = bfa.CELL
    y = (band * bfa.BAND_ROWS + row) * c
    return arr[y:y + c, col * c:(col + span) * c]


class FxAtlasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        out = pathlib.Path(cls.dir.name)
        bfa.build(out / "a.png")
        bfa.build(out / "b.png")
        cls.a_path, cls.b_path = out / "a.png", out / "b.png"
        cls.img = Image.open(cls.a_path)
        cls.arr = np.asarray(cls.img.convert("RGBA")).astype(np.int16)

    @classmethod
    def tearDownClass(cls):
        cls.dir.cleanup()

    def test_frame_grid(self):
        """Eight 128 px columns; two bands (human, alien) of four rows: fireball frames, smoke frames, single sprites,
        shot sprites (tracer, shell, bolt; Task 3)."""
        self.assertEqual(bfa.CELL, 128)
        self.assertEqual(bfa.COLS, 8)
        self.assertEqual(bfa.BAND_ROWS, 4)
        self.assertEqual(self.img.size, (1024, 1024))
        self.assertEqual(self.img.mode, "RGBA")
        self.assertEqual(bfa.FIREBALL_FRAMES, 8)
        self.assertEqual(bfa.SMOKE_FRAMES, 8)
        self.assertEqual(list(bfa.SINGLES), ["flash", "sparks", "debris", "ember", "glow", "ring", "rubble"])
        self.assertEqual(bfa.SINGLES["rubble"], (6, 2), "the rubble decal spans the last two cells")
        self.assertEqual(bfa.SHOTS, {"tracer": 0, "shell": 1, "bolt": 2}, "row 3: the shot sprites")

    def test_shot_sprites_point_up_and_add_light(self):
        """Tracer, shell and bolt are vertical streaks (a card stretches and turns them along the shot), brightest at the
        head (the top of the cell), emissive only (alpha 0: they add light), in both bands."""
        for band in range(2):
            for name, col in bfa.SHOTS.items():
                px = cell(self.arr, band, 3, col)
                lum = px[..., :3].max(axis=2)
                self.assertGreater(int(lum.max()), 220, "%s band %d is bright" % (name, band))
                self.assertLessEqual(int(px[..., 3].max()), 2, "%s band %d adds light (alpha 0)" % (name, band))
                ys, xs = np.nonzero(lum > 40)
                tall, wide = ys.max() - ys.min() + 1, xs.max() - xs.min() + 1
                self.assertGreater(tall, 2.0 * wide, "%s band %d is a vertical streak (%d x %d)" % (name, band, wide, tall))
                top, bottom = lum[:64].astype(float).sum(), lum[64:].astype(float).sum()
                self.assertGreater(top, bottom, "%s band %d: the head is at the top" % (name, band))
        tracer = cell(self.arr, 0, 3, 0)
        shell = cell(self.arr, 0, 3, 1)[..., :3].max(axis=2)
        hot = np.argwhere(shell >= shell.max() - 4)
        self.assertLess(hot[:, 0].mean(), 128 / 3, "the shell's hot slug rides at the head")
        self.assertGreater(np.ptp(hot[:, 1]) + 1, 6, "and is round, not a line")
        lit = tracer[..., :3].reshape(-1, 3)
        lit = lit[lit.max(axis=1) > 80].mean(axis=0)
        self.assertGreater(lit[0], lit[2] + 60, "the human tracer is amber %s" % lit)
        bolt = cell(self.arr, 1, 3, 2)[..., :3].reshape(-1, 3)
        bolt = bolt[bolt.max(axis=1) > 80].mean(axis=0)
        self.assertGreater(bolt[2], bolt[0] * 0.9, "the alien bolt carries blue %s" % bolt)
        self.assertGreater(bolt[1] + bolt[2], 2 * bolt[0] * 0.8, "the alien bolt is teal and magenta, not orange %s" % bolt)

    def test_two_runs_are_identical(self):
        self.assertEqual(self.a_path.read_bytes(), self.b_path.read_bytes())

    def test_committed_atlas_is_the_script_output(self):
        """Same tolerance as test_committed_sprites_are_the_script_output: up to 4 per channel, under 1 % of pixels by
        more than 1."""
        committed = bfa.OUT
        self.assertTrue(committed.exists(), str(committed))
        d = np.abs(np.asarray(Image.open(committed).convert("RGBA")).astype(np.int16) - self.arr)
        self.assertLessEqual(int(d.max()), 4, "fx_atlas.png is stale: rerun the script (max channel difference %d)" % d.max())
        self.assertLess(float((d.max(axis=2) > 1).mean()), 0.01, "fx_atlas.png is stale: rerun the script")

    def test_cells_keep_a_clear_border(self):
        """Every cell's outer 3 px are empty (no colour, no alpha), so a frame never bleeds into its neighbour."""
        c = bfa.CELL
        for band in range(2):
            for row in range(bfa.BAND_ROWS):
                for col in range(8):
                    if row == 2 and col == 7:
                        continue  # the second half of the rubble decal: checked as one wide cell below
                    span = 2 if (row == 2 and col == 6) else 1
                    px = cell(self.arr, band, row, col, span)
                    w = c * span
                    edge = np.concatenate([px[:3].reshape(-1, 4), px[-3:].reshape(-1, 4), px[:, :3].reshape(-1, 4), px[:, w - 3:].reshape(-1, 4)])
                    self.assertLessEqual(int(edge.max()), 2, "band %d row %d col %d border" % (band, row, col))

    def test_alpha_is_present(self):
        """Smoke frames and the debris and rubble occlude (alpha); fire is emissive (premultiplied colour over low alpha)."""
        for band in range(2):
            smoke = cell(self.arr, band, 1, 0)
            self.assertGreater(int(smoke[..., 3].max()), 180, "smoke puff is dense at its heart")
            self.assertGreater(float((smoke[..., 3] > 8).mean()), 0.15, "and covers a good part of its cell")
            debris = cell(self.arr, band, 2, 2)
            self.assertGreater(int(debris[..., 3].max()), 200, "debris chunks are solid")
            rubble = cell(self.arr, band, 2, 6, 2)
            self.assertGreater(int(rubble[..., 3].max()), 150, "the rubble decal darkens the ground")
            flash = cell(self.arr, band, 2, 0)
            self.assertGreater(int(flash[..., :3].max()), 230, "the flash is bright")

    def test_premultiplied(self):
        """Smoke texels are premultiplied: no colour channel exceeds alpha where nothing glows."""
        for band in range(2):
            smoke = cell(self.arr, band, 1, 3)
            self.assertLessEqual(int((smoke[..., :3].max(axis=2) - smoke[..., 3]).max()), 1)

    def test_fireball_animates_and_is_not_a_disc(self):
        """Eight distinct frames; the early frames are turbulent: the lit area's outline is ragged, not a circle."""
        frames = [cell(self.arr, 0, 0, i) for i in range(8)]
        for i in range(7):
            self.assertGreater(int(np.abs(frames[i] - frames[i + 1]).max()), 30, "frame %d differs from %d" % (i, i + 1))
        lum = frames[2][..., :3].max(axis=2)
        lit = lum > 60
        ys, xs = np.nonzero(lit)
        cy, cx = ys.mean(), xs.mean()
        radii = []
        for a in np.linspace(0, 2 * np.pi, 48, endpoint=False):
            r = 0
            while True:
                y, x = int(round(cy - np.sin(a) * r)), int(round(cx + np.cos(a) * r))
                if not (0 <= y < 128 and 0 <= x < 128) or not lit[y, x]:
                    break
                r += 1
            radii.append(r)
        radii = np.array(radii, float)
        self.assertGreater(radii.std() / radii.mean(), 0.08, "ragged outline (radius spread %.3f)" % (radii.std() / radii.mean()))

    def test_fireball_has_a_hot_core_and_a_smoky_edge(self):
        f = cell(self.arr, 0, 0, 1)
        core = f[56:72, 56:72, :3].mean(axis=(0, 1))
        self.assertGreater(core.min(), 170, "white-yellow core %s" % core)
        late = cell(self.arr, 0, 0, 6)
        self.assertGreater(int(late[..., 3].max()), 120, "late frames turn to occluding smoke")

    def test_human_fire_is_amber_and_alien_fire_is_plasma(self):
        def hue_sum(band):
            f = cell(self.arr, band, 0, 3)[..., :3].reshape(-1, 3)
            f = f[f.max(axis=1) > 80]
            return f.mean(axis=0)
        h, a = hue_sum(0), hue_sum(1)
        self.assertGreater(h[0], h[2] + 60, "human fire is warm %s" % h)
        self.assertGreater(a[2], a[1] * 0.6, "alien plasma carries blue %s" % a)
        self.assertGreater(a[2] + a[1], 2 * a[0] * 0.8, "alien plasma is teal and magenta, not orange %s" % a)


if __name__ == "__main__":
    unittest.main()
