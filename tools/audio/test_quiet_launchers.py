"""Every tools/ script that starts Godot keeps it silent (plan 2026-10-06-kestrel-next-level, Task 5).
Run: cd tools/audio && python3 -m unittest test_quiet_launchers -v

Once the AudioDirector exists, a capture or QA launch with a real audio driver would play the game on the developer's
speakers. So every launch line must pass the Dummy audio driver, or --headless (which implies it). The known set of
launchers is pinned: a new script that names the Godot binary fails here until it is checked and added."""
import pathlib, re, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
BINARY = "Godot_v4.7.2-stable_linux.x86_64"
SUFFIXES = {".sh", ".bash", ".py", ".gd"}
KNOWN = {"tools/ui/run_cap.sh", "tools/qa/launch_ui.py", "tools/audio/build_sfx.py", "tools/release/package.sh"}
QUIET = re.compile(r"--headless|--audio-driver['\"]?\s*,?\s*['\"]?Dummy")
# a Godot launch line: it hands Godot a project (--path) next to the binary or the shell variable holding it
LAUNCH = re.compile(r"--path")


def _launchers():
    found = {}
    for p in TOOLS.rglob("*"):
        if not p.is_file() or p.suffix not in SUFFIXES or "__pycache__" in p.parts or p.name == pathlib.Path(__file__).name:
            continue
        text = p.read_text(errors="replace")
        if BINARY in text:
            found[str(p.relative_to(ROOT))] = text
    return found


class QuietLaunchers(unittest.TestCase):
    def test_the_known_launchers_are_the_only_ones(self):
        self.assertEqual(set(_launchers()), KNOWN)

    def test_every_launch_line_is_quiet(self):
        checked = 0
        for rel, text in _launchers().items():
            for n, line in enumerate(text.splitlines(), 1):
                if LAUNCH.search(line):
                    checked += 1
                    self.assertRegex(line, QUIET, f"{rel}:{n} starts Godot without --audio-driver Dummy or --headless")
        self.assertGreaterEqual(checked, 3)

    def test_run_cap_and_launch_ui_name_the_dummy_driver(self):
        self.assertIn('"$G" --audio-driver Dummy', (ROOT / "tools/ui/run_cap.sh").read_text())
        self.assertIn("'--audio-driver','Dummy'", (ROOT / "tools/qa/launch_ui.py").read_text())

    def test_world_capture_launches_through_launch_ui(self):
        text = (ROOT / "tools/qa/world_capture.py").read_text()
        self.assertIn("launch_ui.py", text)
        self.assertNotIn(BINARY, text)


if __name__ == "__main__":
    unittest.main()
