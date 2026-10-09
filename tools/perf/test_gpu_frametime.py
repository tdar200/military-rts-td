"""Tests for tools/perf/gpu_frametime.sh and gpu_frametime_run.py (plan 2026-10-07-kestrel-depth, Task 29).
Run: cd tools/perf && python3 -m unittest test_gpu_frametime -v

The script opens a game window on the USER's display, so agents never run it for real. These tests run only its refusal
and its --dry-run, with a PATH full of shims that record and fail if anything that could start the game, a display
server or the GPU is executed. The pure helpers (summary, budget check, contact detection) are tested on fixtures."""
import json, os, pathlib, stat, subprocess, tempfile, unittest
from unittest import mock

import gpu_frametime_run as run

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCRIPT = HERE / "gpu_frametime.sh"
# built from parts so this file does not look like a Godot launcher to tools/audio/test_quiet_launchers.py
GODOT = "Godot_v4.7.2" + "-stable_linux.x86_64"
SHIMS = [GODOT, "Godot", "godot", "godot-bridge", "Xvfb", "nvidia-smi", "paplay", "aplay", "ffplay"]


def shim_dir(tmp):
    """A directory of fake executables that log their name to `ran.log` and exit 99."""
    d = pathlib.Path(tmp) / "shims"
    d.mkdir()
    log = pathlib.Path(tmp) / "ran.log"
    for name in SHIMS:
        f = d / name
        f.write_text(f'#!/bin/sh\necho "{name} $*" >> "{log}"\nexit 99\n')
        f.chmod(f.stat().st_mode | stat.S_IXUSR)
    return d, log


def run_script(*args, env_extra=None):
    with tempfile.TemporaryDirectory() as tmp:
        d, log = shim_dir(tmp)
        env = {"PATH": f"{d}:/usr/bin:/bin", "HOME": tmp}
        env.update(env_extra or {})
        p = subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, env=env, cwd=tmp, timeout=60)
        ran = log.read_text() if log.exists() else ""
        return p, ran


class Guards(unittest.TestCase):
    def test_refuses_without_the_flag(self):
        p, ran = run_script()
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("--allow-user-display", p.stderr)
        self.assertEqual(ran, "")

    def test_refuses_a_real_run_without_the_flag_even_with_other_options(self):
        p, ran = run_script("--seconds", "5", "--out", "/nonexistent/x")
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(ran, "")

    def test_dry_run_alone_also_needs_the_flag(self):
        p, ran = run_script("--dry-run")
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(ran, "")

    def test_unknown_option_is_refused(self):
        p, ran = run_script("--allow-user-display", "--bogus")
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(ran, "")


class DryRun(unittest.TestCase):
    def test_prints_the_three_scenes_the_budget_and_the_baseline_and_starts_nothing(self):
        before = set(os.listdir(ROOT / "build")) if (ROOT / "build").exists() else None
        p, ran = run_script("--dry-run", "--allow-user-display")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(ran, "", "a shimmed executable ran: " + ran)
        out = p.stdout
        for word in ("idle", "combat", "zoomed-out"):
            self.assertIn(word, out)
        self.assertIn("10 ms", out)
        self.assertIn("p50", out)
        self.assertIn("p95", out)
        self.assertIn("world_baseline.json", out)
        self.assertIn("5.56", out)   # idle_default baseline frame_ms_p50
        self.assertIn("7.07", out)   # idle_zoomed_out baseline frame_ms_p50
        self.assertIn("dry run", out.lower())
        after = set(os.listdir(ROOT / "build")) if (ROOT / "build").exists() else None
        self.assertEqual(before, after, "a dry run must not create output")

    def test_dry_run_honours_seconds_and_out(self):
        p, _ = run_script("--dry-run", "--allow-user-display", "--seconds", "7", "--out", "/tmp/somewhere-x")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("7 s", p.stdout)
        self.assertIn("/tmp/somewhere-x", p.stdout)

    def test_a_real_run_needs_a_display_and_still_starts_nothing_without_one(self):
        p, ran = run_script("--allow-user-display")  # no DISPLAY or WAYLAND_DISPLAY in the env
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("DISPLAY", p.stderr)
        self.assertEqual(ran, "")


class NeverRunsAnythingAtImport(unittest.TestCase):
    def test_the_plan_launches_no_process(self):
        with mock.patch("subprocess.Popen", side_effect=AssertionError("Popen")), \
                mock.patch("subprocess.run", side_effect=AssertionError("run")):
            text = run.plan_text(seconds=10, out="/tmp/x")
        self.assertIn("combat", text)

    def test_the_script_never_names_the_game_binary(self):
        # it reaches Godot only through tools/qa/launch_ui.py, which pins the Dummy audio driver
        for f in (SCRIPT, HERE / "gpu_frametime_run.py"):
            self.assertNotIn(GODOT, f.read_text(), f.name)
        self.assertIn("launch_ui.py", (HERE / "gpu_frametime_run.py").read_text())


def perf_fixture(frame_ms):
    samples = [{"frame_ms": v, "gpu_ms": v / 4, "cpu_render_ms": v / 3, "draw_calls": 800 + i, "primitives": 150000} for i, v in enumerate(frame_ms)]
    return {"frames": len(frame_ms), "seconds": 1.0, "fps": float(len(frame_ms)), "samples": samples, "summary": {
        "frame_ms": {"p50": sorted(frame_ms)[len(frame_ms) // 2], "p95": sorted(frame_ms)[int(len(frame_ms) * 0.95)], "max": max(frame_ms)},
        "gpu_ms": {"p50": 1.0}, "cpu_render_ms": {"p50": 2.0}, "draw_calls": {"p50": 838.0}, "primitives": {"p50": 152056.0}}}


class Judging(unittest.TestCase):
    def test_summarise_reads_the_driver_summary(self):
        s = run.summarise(perf_fixture([5.0] * 90 + [9.0] * 10))
        self.assertEqual(s["frame_ms_p50"], 5.0)
        self.assertEqual(s["frames"], 100)
        self.assertEqual(s["draw_calls_p50"], 838.0)

    def test_budget_is_on_the_p50_only(self):
        self.assertTrue(run.within_budget({"frame_ms_p50": 10.0, "frame_ms_p95": 40.0}))
        self.assertFalse(run.within_budget({"frame_ms_p50": 10.01, "frame_ms_p95": 1.0}))
        self.assertEqual(run.BUDGET_MS, 10.0)

    def test_baseline_comes_from_the_baseline_file(self):
        base = run.load_baseline()
        self.assertEqual(base["idle"]["frame_ms_p50"], 5.56)
        self.assertEqual(base["zoomed-out"]["frame_ms_p50"], 7.07)
        self.assertNotIn("combat", base)

    def test_compare_marks_regression_over_the_baseline(self):
        self.assertIn("+", run.compare_text({"frame_ms_p50": 6.56}, {"frame_ms_p50": 5.56}))
        self.assertIn("no baseline", run.compare_text({"frame_ms_p50": 6.0}, None))

    def test_contact_needs_an_alien_unit_near_something_of_ours(self):
        def ent(i, owner, cat, x, z):
            return {"id": i, "owner": owner, "category": cat, "x_bits": int(x * 65536), "z_bits": int(z * 65536), "hp_bits": 65536}
        mine = ent(0, 0, "building", 5, 10)
        far = ent(1, 1, "unit", 40, 20)
        near = ent(2, 1, "unit", 9, 10)
        relay = ent(3, 1, "building", 6, 10)
        self.assertFalse(run.in_contact({"entities": [mine, far, relay]}))
        self.assertTrue(run.in_contact({"entities": [mine, far, near]}))
        self.assertFalse(run.in_contact({"entities": []}))

    def test_stop_signal_becomes_a_clean_exit(self):
        with self.assertRaises(SystemExit):
            run.on_signal(15, None)


if __name__ == "__main__":
    unittest.main()
