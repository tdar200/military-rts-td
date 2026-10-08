"""Tests for tools/audio/build_sfx.py (plan 2026-10-06-kestrel-next-level, Task 4; eight more ids in plan
2026-10-07-kestrel-depth, Task 6).
Run: cd tools/audio && python3 -m unittest test_build_sfx -v

Nothing here plays audio: every check is offline analysis of the written WAV files (format, length, peak, DC, loudness,
loop seams, spectra)."""
import json, pathlib, struct, tempfile, unittest
import numpy as np
import build_sfx as bs

IDS = ["rifle", "cannon", "plasma_bolt", "explosion_small", "explosion_large", "collapse", "rotor_loop", "tread_loop",
       "foot_loop", "ui_click", "ui_hover", "select", "ack_infantry", "ack_vehicle", "ack_air", "alert", "build_complete",
       "wave_inbound",
       # kestrel-depth Task 6: cues for events that were silent
       "denied", "place_thunk", "power_down", "power_up", "wave_cleared", "research_complete", "victory_sting",
       "defeat_sting"]
STINGS = ("victory_sting", "defeat_sting")
CATEGORIES = {"weapon", "impact", "loop", "ui", "voice", "alert"}
# stated duration range per category, seconds (inclusive)
DURATION_RANGE = {"weapon": (0.15, 1.5), "impact": (0.5, 4.0), "loop": (1.0, 4.0), "ui": (0.02, 0.3),
                  "voice": (0.1, 0.6), "alert": (0.4, 2.0)}
# the match-end stings are alerts with their own, longer range (they replace the reused cues on victory and defeat)
ID_DURATION_RANGE = {sid: (1.5, 3.0) for sid in STINGS}
SR = 44100
PEAK_LIMIT = 10 ** (-1.0 / 20.0)  # -1 dBFS
DC_LIMIT = 1e-3  # |mean| as a fraction of full scale (-60 dBFS)
HIERARCHY_MARGIN_DB = 12.0  # every weapon and impact is at least this much louder than every ui sound
CATEGORY_SPREAD_DB = 6.0  # members of one category sit within this loudness band
SIZE_LIMIT = 3 * 1024 * 1024


def read_wav(path):
    """Minimal RIFF reader: returns (sample_rate, channels, bits, int16 samples, chunks dict)."""
    raw = pathlib.Path(path).read_bytes()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
    assert struct.unpack("<I", raw[4:8])[0] == len(raw) - 8, "RIFF size field matches the file"
    pos, chunks = 12, {}
    while pos + 8 <= len(raw):
        cid, size = raw[pos:pos + 4], struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        chunks[cid] = raw[pos + 8:pos + 8 + size]
        pos += 8 + size + (size & 1)
    fmt, ch, sr, byte_rate, align, bits = struct.unpack("<HHIIHH", chunks[b"fmt "][:16])
    assert fmt == 1, "PCM"
    assert byte_rate == sr * ch * bits // 8 and align == ch * bits // 8, "consistent fmt chunk"
    data = np.frombuffer(chunks[b"data"], dtype="<i2")
    return sr, ch, bits, data, chunks


def loudness_db(x):
    """Short-term loudness: the loudest 50 ms RMS window (10 ms hop), dBFS. Independent of the generator's own meter."""
    w, hop = int(0.05 * SR), int(0.01 * SR)
    if len(x) <= w:
        r = np.sqrt(np.mean(x * x))
    else:
        r = max(np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, len(x) - w + 1, hop))
    return 20 * np.log10(max(r, 1e-9))


def centroid(x):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float((spec * f).sum() / max(spec.sum(), 1e-12))


def hf_energy(seg):
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    f = np.fft.rfftfreq(len(seg), 1 / SR)
    return float(spec[f > 6000].sum())


def dominant(seg, lo=60.0, hi=2000.0):
    """The strongest frequency in [lo, hi] of a Hann-windowed segment, Hz."""
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 8 * len(seg)))
    f = np.fft.rfftfreq(8 * len(seg), 1 / SR)
    keep = (f >= lo) & (f <= hi)
    return float(f[keep][np.argmax(spec[keep])])


def level_at(seg, freq, width=0.015):
    """Peak spectral magnitude within +-width (relative) of freq, relative to the segment's strongest bin under 4 kHz."""
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 8 * len(seg)))
    f = np.fft.rfftfreq(8 * len(seg), 1 / SR)
    near = (f >= freq * (1 - width)) & (f <= freq * (1 + width))
    return float(spec[near].max() / spec[f < 4000].max())


def seg_at(x, a, b):
    return x[int(a * SR):int(b * SR)]


class SfxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(cls.tmp.name)
        cls.a, cls.b = root / "a", root / "b"
        bs.build(cls.a)
        bs.build(cls.b)
        cls.manifest = json.loads((cls.a / "sfx_manifest.json").read_text())
        cls.sounds = {s["id"]: s for s in cls.manifest["sounds"]}
        cls.audio = {}
        for sid, s in cls.sounds.items():
            sr, ch, bits, data, chunks = read_wav(cls.a / s["file"])
            cls.audio[sid] = {"sr": sr, "ch": ch, "bits": bits, "x": data.astype(np.float64) / 32768.0, "chunks": chunks}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def x(self, sid):
        return self.audio[sid]["x"]

    # ---- determinism and committed output

    def test_two_runs_are_byte_identical(self):
        names = sorted(p.name for p in self.a.iterdir())
        self.assertEqual(names, sorted(p.name for p in self.b.iterdir()))
        for n in names:
            self.assertEqual((self.a / n).read_bytes(), (self.b / n).read_bytes(), n)

    def test_committed_files_are_the_script_output(self):
        """Committed WAVs equal a fresh run within 2 LSB, and under 1 % of samples differ by more than 1 LSB (float
        rounding across machines); the committed manifest equals a fresh one (numbers within 0.2)."""
        out = bs.OUT
        committed = json.loads((out / "sfx_manifest.json").read_text())
        self.assertEqual([s["id"] for s in committed["sounds"]], IDS, "sfx_manifest.json is stale: rerun the script")
        for s, c in zip(self.manifest["sounds"], committed["sounds"]):
            for k, v in s.items():
                if isinstance(v, float):
                    self.assertAlmostEqual(v, c[k], delta=0.2, msg="%s.%s is stale" % (s["id"], k))
                else:
                    self.assertEqual(v, c[k], "%s.%s is stale" % (s["id"], k))
        self.assertEqual({k: v for k, v in committed.items() if k != "sounds"},
                         {k: v for k, v in self.manifest.items() if k != "sounds"})
        for sid, s in self.sounds.items():
            path = out / s["file"]
            self.assertTrue(path.exists(), str(path))
            got = read_wav(path)[3].astype(np.int32)
            want = read_wav(self.a / s["file"])[3].astype(np.int32)
            self.assertEqual(len(got), len(want), "%s length is stale: rerun the script" % sid)
            d = np.abs(got - want)
            self.assertLessEqual(int(d.max()), 2, "%s is stale: rerun the script (max diff %d)" % (sid, d.max()))
            self.assertLess(float((d > 1).mean()), 0.01, "%s is stale: rerun the script" % sid)

    def test_committed_wavs_have_godot_import_files(self):
        for s in self.sounds.values():
            imp = bs.OUT / (s["file"] + ".import")
            self.assertTrue(imp.exists(), "%s missing: run Godot --headless --import" % imp)
            self.assertIn('importer="wav"', imp.read_text())

    def test_total_size_under_3_mb(self):
        for d in (self.a, bs.OUT):
            total = sum(p.stat().st_size for p in d.iterdir() if p.suffix in (".wav", ".ogg", ".json"))
            self.assertLess(total, SIZE_LIMIT, "%s holds %d bytes" % (d, total))

    def test_readme_states_cc0_and_regeneration(self):
        text = (bs.OUT / "README.md").read_text()
        self.assertIn("CC0", text)
        self.assertIn("tools/audio/build_sfx.py", text)
        self.assertIn("no third-party samples", text.lower())
        for path in (bs.OUT / "README.md", self.a / "sfx_manifest.json", pathlib.Path(bs.__file__), pathlib.Path(__file__)):
            t = path.read_text()
            self.assertNotIn("\u2014", t, "%s has an em dash" % path.name)
            self.assertNotIn("\u2013", t, "%s has an en dash" % path.name)

    # ---- manifest

    def test_manifest_validates(self):
        m = self.manifest
        self.assertEqual(m["format"], {"sample_rate": SR, "channels": 1, "bits": 16, "container": "wav"})
        self.assertEqual(m["base_path"], "res://assets/audio/sfx/")
        self.assertEqual([s["id"] for s in m["sounds"]], IDS)
        keys = {"id", "file", "duration_s", "loop", "base_volume_db", "category", "character", "peak_dbfs", "loudness_dbfs"}
        for s in m["sounds"]:
            self.assertEqual(set(s), keys, s["id"])
            self.assertEqual(s["file"], s["id"] + ".wav")
            self.assertTrue((self.a / s["file"]).exists())
            self.assertIsInstance(s["duration_s"], float)
            self.assertIsInstance(s["loop"], bool)
            self.assertIsInstance(s["base_volume_db"], float)
            self.assertTrue(-24.0 <= s["base_volume_db"] <= 0.0, s["id"])
            self.assertIn(s["category"], CATEGORIES)
            self.assertEqual(s["loop"], s["category"] == "loop", s["id"])
            self.assertTrue(isinstance(s["character"], str) and 10 <= len(s["character"]) <= 160, s["id"])
        self.assertEqual({s["category"] for s in m["sounds"]}, CATEGORIES)

    def test_manifest_numbers_match_the_files(self):
        for sid, s in self.sounds.items():
            x = self.x(sid)
            self.assertAlmostEqual(s["duration_s"], len(x) / SR, delta=0.0005, msg=sid)
            self.assertAlmostEqual(s["peak_dbfs"], 20 * np.log10(np.abs(x).max()), delta=0.1, msg=sid)
            self.assertAlmostEqual(s["loudness_dbfs"], loudness_db(x), delta=0.1, msg=sid)

    # ---- format and signal hygiene

    def test_format_is_16_bit_mono_44100(self):
        for sid, a in self.audio.items():
            self.assertEqual((a["sr"], a["ch"], a["bits"]), (SR, 1, 16), sid)

    def test_durations_in_category_range(self):
        for sid, s in self.sounds.items():
            lo, hi = ID_DURATION_RANGE.get(sid, DURATION_RANGE[s["category"]])
            d = len(self.x(sid)) / SR
            self.assertTrue(lo <= d <= hi, "%s lasts %.3f s, outside %s for %s" % (sid, d, (lo, hi), s["category"]))

    def test_peak_below_minus_1_dbfs_and_no_clipping(self):
        for sid in IDS:
            x = self.x(sid)
            self.assertLess(np.abs(x).max(), PEAK_LIMIT, "%s peaks at %.2f dBFS" % (sid, 20 * np.log10(np.abs(x).max())))
            self.assertGreater(np.abs(x).max(), 10 ** (-30 / 20), "%s is not near silent" % sid)

    def test_no_dc_offset(self):
        for sid in IDS:
            self.assertLess(abs(self.x(sid).mean()), DC_LIMIT, sid)

    def test_one_shots_start_at_zero_and_fade_out(self):
        for sid, s in self.sounds.items():
            if s["loop"]:
                continue
            x = self.x(sid)
            self.assertEqual(x[0], 0.0, "%s starts at zero (no click)" % sid)
            tail = x[-int(0.003 * SR):]
            self.assertLess(np.abs(tail).max(), 10 ** (-50 / 20), "%s ends silent" % sid)
            self.assertNotIn(b"smpl", self.audio[sid]["chunks"], "%s is a one-shot: no loop chunk" % sid)

    def test_loops_carry_a_forward_loop_over_the_whole_file(self):
        """A WAV smpl chunk with one forward loop from 0 to the frame count: Godot's importer (edit/loop_mode 0, detect from
        WAV) turns it into LOOP_FORWARD."""
        for sid, s in self.sounds.items():
            if not s["loop"]:
                continue
            smpl = self.audio[sid]["chunks"][b"smpl"]
            n_loops = struct.unpack("<I", smpl[28:32])[0]
            loop_type, begin, end = struct.unpack("<4xIII", smpl[36:52])
            self.assertEqual((n_loops, loop_type, begin, end), (1, 0, 0, len(self.x(sid))), sid)

    def test_loops_are_click_free(self):
        """The seam (last sample to first) is no bigger a step than ordinary sample-to-sample motion inside the loop, and
        a window straddling the seam carries no more high-frequency energy than typical windows inside the loop."""
        for sid, s in self.sounds.items():
            if not s["loop"]:
                continue
            x = self.x(sid)
            steps = np.abs(np.diff(x))
            seam = abs(x[0] - x[-1])
            self.assertLessEqual(seam, np.percentile(steps, 99), "%s seam step %.5f" % (sid, seam))
            k = int(0.01 * SR)  # and no bigger than 0.75 x the largest step within 10 ms either side of the seam
            local = np.delete(np.abs(np.diff(np.concatenate([x[-k:], x[:k]]))), k - 1)
            self.assertLessEqual(seam, 0.75 * local.max(), "%s seam step %.5f vs local %.5f" % (sid, seam, local.max()))
            wrapped = np.concatenate([x[-256:], x[:256]])
            inner = [hf_energy(x[c - 256:c + 256]) for c in np.linspace(512, len(x) - 512, 64).astype(int)]
            self.assertLessEqual(hf_energy(wrapped), 1.5 * np.percentile(inner, 90), "%s seam has a spectral splash" % sid)
            # and the loop really is seamless in level: first and last 50 ms within 3 dB
            a, b = x[:int(0.05 * SR)], x[-int(0.05 * SR):]
            self.assertLess(abs(20 * np.log10(np.sqrt(np.mean(a * a)) / np.sqrt(np.mean(b * b)))), 3.0, sid)

    # ---- loudness

    def test_loudness_hierarchy(self):
        loud = {sid: loudness_db(self.x(sid)) for sid in IDS}
        by_cat = {}
        for sid, s in self.sounds.items():
            by_cat.setdefault(s["category"], []).append(loud[sid])
        quietest_hit = min(by_cat["weapon"] + by_cat["impact"])
        loudest_ui = max(by_cat["ui"])
        self.assertGreater(quietest_hit, loudest_ui + HIERARCHY_MARGIN_DB, loud)
        self.assertGreater(min(by_cat["weapon"] + by_cat["impact"]), max(by_cat["loop"]), "loops sit under combat")
        self.assertGreater(min(by_cat["alert"]), max(by_cat["ui"]), "alerts are louder than ui ticks")
        for cat, vals in by_cat.items():
            self.assertLessEqual(max(vals) - min(vals), CATEGORY_SPREAD_DB, "%s spread %s" % (cat, vals))

    # ---- character (sound design checks by analysis, no listening)

    def test_rotor_thumps_at_the_blade_rate(self):
        x = self.x("rotor_loop")
        env = np.abs(x).reshape(-1, 441).mean(axis=1)  # 100 Hz envelope
        spec = np.abs(np.fft.rfft(env - env.mean()))
        f = np.fft.rfftfreq(len(env), 0.01)
        peak = f[np.argmax(spec[1:]) + 1]
        self.assertTrue(18.0 <= peak <= 22.0, "rotor envelope peaks at %.2f Hz" % peak)

    def test_tread_and_foot_loops_are_rhythmic(self):
        """The clatter and the steps carry the rhythm: the RMS envelope (10 ms bins) of the signal above 800 Hz (which keeps
        the engine's low harmonics out) repeats with a period inside the stated range: the track-link rate for the tread,
        the walking cadence for the feet. Measured as the strongest circular autocorrelation lag (the loop wraps)."""
        for sid, lo, hi in (("tread_loop", 5.0, 14.0), ("foot_loop", 2.0, 6.0)):
            x = self.x(sid)
            spec = np.fft.rfft(x)
            spec[np.fft.rfftfreq(len(x), 1 / SR) < 800] = 0
            x = np.fft.irfft(spec, len(x))
            env = np.sqrt((x * x).reshape(-1, 441).mean(axis=1))
            env = env - env.mean()
            ac = np.fft.irfft(np.abs(np.fft.rfft(env)) ** 2, len(env))
            ac /= ac[0]
            lags = np.arange(int(np.ceil(100 / hi)), int(100 / lo) + 1)
            best = lags[np.argmax(ac[lags])]
            self.assertGreater(ac[best], 0.3, "%s envelope repeats clearly (autocorrelation %.2f)" % (sid, ac[best]))
            faster = np.arange(3, lags[0])  # no quicker pattern repeats better (multiples of the period are expected)
            self.assertGreater(ac[best], ac[faster].max(), "%s: no faster rhythm than the stated range" % sid)

    def test_weapons_and_explosions_have_low_end_and_decay(self):
        for sid in ("cannon", "explosion_small", "explosion_large", "collapse"):
            x = self.x(sid)
            spec = np.abs(np.fft.rfft(x)) ** 2
            f = np.fft.rfftfreq(len(x), 1 / SR)
            self.assertGreater(spec[f < 150].sum() / spec.sum(), 0.15, "%s has a low boom" % sid)
        for sid in ("rifle", "cannon", "explosion_small", "explosion_large"):
            x = self.x(sid)
            q = len(x) // 4
            self.assertGreater(np.abs(x[:q]).mean(), 2 * np.abs(x[-q:]).mean(), "%s decays" % sid)
        rifle, cannon = self.x("rifle"), self.x("cannon")
        self.assertGreater(centroid(rifle[:int(0.05 * SR)]), centroid(cannon[:int(0.05 * SR)]), "the rifle cracks brighter")

    def test_plasma_and_explosion_darken_over_time(self):
        for sid, a, b in (("plasma_bolt", (0.0, 0.08), (0.2, 0.35)), ("explosion_large", (0.0, 0.1), (0.8, 1.2))):
            x = self.x(sid)
            early = centroid(x[int(a[0] * SR):int(a[1] * SR)])
            late = centroid(x[int(b[0] * SR):int(b[1] * SR)])
            self.assertGreater(early, 1.3 * late, "%s: early %.0f Hz, late %.0f Hz" % (sid, early, late))

    def test_acks_differ_per_class(self):
        inf, veh, air = self.x("ack_infantry"), self.x("ack_vehicle"), self.x("ack_air")
        self.assertLess(len(inf), len(veh), "infantry is shorter than vehicle")
        self.assertLess(len(inf), len(air), "infantry is shorter than air")
        self.assertGreater(centroid(inf), centroid(veh) * 1.5, "infantry is brighter than vehicle")
        env = np.abs(air).reshape(-1, 147)[:, :].mean(axis=1)  # 300 Hz envelope
        spec = np.abs(np.fft.rfft(env - env.mean()))
        f = np.fft.rfftfreq(len(env), 147 / SR)
        band = (f >= 10) & (f <= 40)
        self.assertGreater(spec[band].max(), 2 * np.median(spec[(f >= 10) & (f <= 140)]), "air ack has a rotor tremolo")

    def test_wave_inbound_rises(self):
        x = self.x("wave_inbound")
        d = len(x) / SR
        self.assertTrue(1.3 <= d <= 1.8, d)

        def pitch(seg):
            spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
            f = np.fft.rfftfreq(len(seg), 1 / SR)
            band = (f > 180) & (f < 2000)
            return f[band][np.argmax(spec[band])]
        early, late = pitch(x[int(0.1 * SR):int(0.4 * SR)]), pitch(x[int(1.0 * SR):int(1.3 * SR)])
        self.assertGreater(late, 1.4 * early, "rising tone: %.0f Hz then %.0f Hz" % (early, late))
        spec = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1 / SR)
        self.assertGreater(spec[f < 120].sum() / spec.sum(), 0.1, "low ominous pulse")

    def test_alert_is_two_tone(self):
        x = self.x("alert")
        seg = int(0.05 * SR)
        peaks = []
        for i in range(0, len(x) - seg, seg):
            s = x[i:i + seg]
            if np.sqrt(np.mean(s * s)) < 0.02:
                continue
            spec = np.abs(np.fft.rfft(s * np.hanning(seg)))
            f = np.fft.rfftfreq(seg, 1 / SR)
            peaks.append(round(f[np.argmax(spec)] / 40) * 40)
        tones = sorted(set(peaks))
        self.assertGreaterEqual(len(tones), 2, peaks)
        self.assertGreater(max(tones) / min(tones), 1.15, "two distinct tones %s" % tones)


    # ---- kestrel-depth Task 6: the eight event cues

    def test_new_cues_have_their_categories(self):
        want = {"denied": "ui", "place_thunk": "ui", "power_down": "alert", "power_up": "alert", "wave_cleared": "alert",
                "research_complete": "alert", "victory_sting": "alert", "defeat_sting": "alert"}
        self.assertEqual({sid: self.sounds[sid]["category"] for sid in want}, want)
        for sid in want:
            self.assertFalse(self.sounds[sid]["loop"], sid)

    def test_stings_last_1_5_to_3_s(self):
        for sid in STINGS:
            d = len(self.x(sid)) / SR
            self.assertTrue(1.5 <= d <= 3.0, "%s lasts %.3f s" % (sid, d))

    def test_denied_is_a_low_double_buzz(self):
        """Two short low buzzes: well under the click's brightness, a fundamental below 300 Hz, and an RMS envelope
        (5 ms bins) with two bursts separated by a dip at least 12 dB down."""
        x = self.x("denied")
        self.assertLess(centroid(x), 0.5 * centroid(self.x("ui_click")))
        self.assertLess(dominant(x, 60, 2000), 300.0)
        e = 20 * np.log10(np.sqrt((x[:len(x) // 220 * 220] ** 2).reshape(-1, 220).mean(axis=1)) + 1e-9)
        on = e > e.max() - 12
        bursts = int(on[0]) + int(np.sum(on[1:] & ~on[:-1]))
        self.assertEqual(bursts, 2, "denied bursts: %s" % on.astype(int).tolist())

    def test_place_thunk_is_a_low_knock_that_decays(self):
        x = self.x("place_thunk")
        spec = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1 / SR)
        self.assertGreater(spec[f < 300].sum() / spec.sum(), 0.3, "place_thunk has a low body")
        self.assertGreater(spec[f >= 300].sum() / spec.sum(), 0.15, "and a knock that small speakers can play")
        q = len(x) // 4
        self.assertGreater(np.abs(x[:q]).mean(), 4 * np.abs(x[-q:]).mean(), "place_thunk decays")
        self.assertLess(centroid(x), centroid(self.x("ui_click")))

    def test_power_down_falls_and_power_up_rises(self):
        down, up = self.x("power_down"), self.x("power_up")
        a, b = dominant(seg_at(down, 0.03, 0.15)), dominant(seg_at(down, 0.5, 0.65))
        self.assertGreater(a, 1.8 * b, "power_down: %.0f Hz then %.0f Hz" % (a, b))
        a, b = dominant(seg_at(up, 0.03, 0.15)), dominant(seg_at(up, 0.4, 0.5))
        self.assertGreater(b, 1.8 * a, "power_up: %.0f Hz then %.0f Hz" % (a, b))
        self.assertLess(len(up), len(self.x("wave_inbound")), "power_up is shorter than the wave warning")

    def test_wave_cleared_resolves_dominant_to_tonic(self):
        """A V to I cadence: the first chord's root is G4 (392 Hz) and the held last one is C5 (523 Hz)."""
        x = self.x("wave_cleared")
        self.assertAlmostEqual(dominant(seg_at(x, 0.03, 0.25), 300, 450), 392.0, delta=6.0)
        last = seg_at(x, 0.55, 0.9)
        self.assertAlmostEqual(dominant(last, 450, 600), 523.25, delta=6.0)
        self.assertGreater(level_at(last, 659.26), 0.2, "the tonic chord carries its major third")

    def test_research_complete_is_brighter_and_quicker_than_build_complete(self):
        r, b = self.x("research_complete"), self.x("build_complete")
        self.assertGreater(centroid(r), 1.3 * centroid(b))
        spec = np.abs(np.fft.rfft(r)) ** 2
        f = np.fft.rfftfreq(len(r), 1 / SR)
        self.assertLess(spec[f > 6000].sum() / spec.sum(), 0.1, "bright from its tones, not from hiss")
        self.assertGreater(dominant(seg_at(r, 0.0, 0.04), 400, 4000), 1000.0, "it opens high (C6)")

    def test_victory_rises_to_a_major_chord_and_defeat_falls_to_a_minor_one(self):
        v, d = self.x("victory_sting"), self.x("defeat_sting")
        tail_v, tail_d = seg_at(v, 0.8, 1.6), seg_at(d, 1.0, 1.8)
        root_v = dominant(tail_v, 450, 600)
        self.assertAlmostEqual(root_v, 523.25, delta=6.0, msg="victory holds C5")
        self.assertGreater(level_at(tail_v, 523.25 * 1.2599), 0.2, "victory chord has a major third")
        self.assertGreater(dominant(tail_v, 300, 2000), dominant(seg_at(v, 0.02, 0.12), 300, 2000) * 0.99,
                           "victory ends at or above where it starts")
        self.assertGreater(dominant(seg_at(d, 0.02, 0.25), 200, 1000), 1.4 * dominant(tail_d, 100, 1000),
                           "defeat ends lower than it starts")
        self.assertGreater(level_at(tail_d, 130.81 * 1.1892), 0.2, "defeat chord has a minor third (E flat)")
        self.assertLess(level_at(tail_d, 130.81 * 1.2599), 0.1, "and no major third")
        self.assertLess(centroid(d), centroid(v), "defeat is darker than victory")
        spec = np.abs(np.fft.rfft(d)) ** 2
        f = np.fft.rfftfreq(len(d), 1 / SR)
        self.assertGreater(spec[f < 300].sum() / spec.sum(), 0.2, "defeat sits low")


if __name__ == "__main__":
    unittest.main()
