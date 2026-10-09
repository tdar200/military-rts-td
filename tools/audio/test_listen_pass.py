"""Tests for tools/audio/listen_pass.py (plan 2026-10-07-kestrel-depth, Task 29).
Run: cd tools/audio && python3 -m unittest test_listen_pass -v

Nothing here makes a sound: every test injects a recording player, and the one test of the default player replaces
subprocess with a fake. The module must refuse (exit 2, nothing played) when stdin is not a terminal."""
import io, json, pathlib, tempfile, unittest
from unittest import mock

import listen_pass as lp

MANIFEST = lp.DEFAULT_MANIFEST


class FakeTty(io.StringIO):
    def isatty(self):
        return True


class NotTty(io.StringIO):
    def isatty(self):
        return False


def run(argv, text, tty=True, with_player=True, **kw):
    """Run main() with canned stdin; returns (code, played paths, stdout text, order log)."""
    played, out = [], io.StringIO()
    log = []

    def player(path):
        # what was already printed when the sound starts: the label must come first
        log.append((pathlib.Path(path).name, out.getvalue()))
        played.append(str(path))

    stdin = (FakeTty if tty else NotTty)(text)
    code = lp.main(argv, stdin, player if with_player else None, stdout=out, **kw)
    return code, played, out.getvalue(), log


class Manifest(unittest.TestCase):
    def test_reads_every_id_with_its_category_and_an_existing_file(self):
        sounds = lp.load_manifest(MANIFEST)
        self.assertEqual(len(sounds), 26)
        self.assertEqual({s["category"] for s in sounds}, {"weapon", "impact", "loop", "ui", "voice", "alert"})
        for s in sounds:
            self.assertTrue(pathlib.Path(s["path"]).is_file(), s["id"])

    def test_a_missing_wav_is_reported_before_anything_is_asked(self):
        with tempfile.TemporaryDirectory() as d:
            m = pathlib.Path(d) / "sfx_manifest.json"
            m.write_text(json.dumps({"sounds": [{"id": "x", "file": "x.wav", "category": "ui", "duration_s": 0.1}]}))
            code, played, out, _ = run(["--manifest", str(m)], "yes\n")
            self.assertEqual(code, 2)
            self.assertEqual(played, [])
            self.assertIn("x.wav", out)


class Refusals(unittest.TestCase):
    def test_non_tty_stdin_returns_2_and_plays_nothing(self):
        code, played, out, _ = run([], "yes\n" * 40, tty=False)
        self.assertEqual(code, 2)
        self.assertEqual(played, [])
        self.assertIn("terminal", out.lower())

    def test_non_tty_refuses_even_with_only(self):
        code, played, _, _ = run(["--only", "rifle"], "yes\n", tty=False)
        self.assertEqual((code, played), (2, []))

    def test_answering_no_plays_nothing(self):
        for answer in ("no\n", "\n", "y\n", "YES please\n", ""):
            code, played, out, _ = run([], answer)
            self.assertEqual(played, [], repr(answer))
            self.assertNotEqual(code, 0, repr(answer))

    def test_no_player_on_path_is_a_clear_error_and_plays_nothing(self):
        self.assertIsNone(lp.find_player(which=lambda name: None))
        code, played, out, _ = run([], "yes\n", with_player=False, which=lambda name: None)
        self.assertEqual((code, played), (2, []))
        self.assertIn("paplay", out)

    def test_unknown_only_value_lists_the_valid_ones(self):
        code, played, out, _ = run(["--only", "nope"], "yes\n")
        self.assertEqual((code, played), (2, []))
        self.assertIn("rifle", out)
        self.assertIn("weapon", out)


class Playing(unittest.TestCase):
    def test_yes_plays_every_id_in_manifest_order_label_first(self):
        code, played, out, log = run([], "yes\n")
        self.assertEqual(code, 0)
        sounds = lp.load_manifest(MANIFEST)
        self.assertEqual([pathlib.Path(p).name for p in played], [s["file"] for s in sounds])
        for s, (name, printed) in zip(sounds, log):
            self.assertEqual(name, s["file"])
            self.assertIn(s["id"], printed)
            label = [l for l in printed.splitlines() if s["id"] in l][-1]
            self.assertIn(s["category"], label)  # id and category are on screen before the sound starts

    def test_only_a_category(self):
        _, played, _, _ = run(["--only", "ui"], "yes\n")
        want = [s["file"] for s in lp.load_manifest(MANIFEST) if s["category"] == "ui"]
        self.assertGreaterEqual(len(want), 3)
        self.assertEqual([pathlib.Path(p).name for p in played], want)

    def test_only_one_id_and_a_comma_list(self):
        _, played, _, _ = run(["--only", "rifle"], "yes\n")
        self.assertEqual([pathlib.Path(p).name for p in played], ["rifle.wav"])
        _, played, _, _ = run(["--only", "rifle,cannon"], "yes\n")
        self.assertEqual([pathlib.Path(p).name for p in played], ["rifle.wav", "cannon.wav"])

    def test_list_prints_every_id_needs_no_tty_and_plays_nothing(self):
        code, played, out, _ = run(["--list"], "", tty=False)
        self.assertEqual((code, played), (0, []))
        for s in lp.load_manifest(MANIFEST):
            self.assertIn(s["id"], out)
            self.assertIn(s["category"], out)

    def test_notes_are_asked_after_each_sound_and_written_to_the_file(self):
        with tempfile.TemporaryDirectory() as d:
            notes = pathlib.Path(d) / "notes.txt"
            code, played, _, _ = run(["--only", "rifle,cannon,ack_air", "--notes", str(notes)],
                                     "yes\nthin\n\ntoo loud, clips\n")
            self.assertEqual(code, 0)
            self.assertEqual(len(played), 3)
            text = notes.read_text()
            self.assertIn("rifle\tweapon\tthin", text)
            self.assertIn("ack_air\tvoice\ttoo loud, clips", text)
            self.assertNotIn("cannon\tweapon\t", text)  # a blank answer writes nothing

    def test_q_at_a_note_prompt_stops_the_pass(self):
        with tempfile.TemporaryDirectory() as d:
            code, played, _, _ = run(["--only", "weapon", "--notes", str(pathlib.Path(d) / "n.txt")], "yes\nq\n")
            self.assertEqual(len(played), 1)
            self.assertEqual(code, 0)

    def test_the_real_player_is_a_subprocess_and_only_built_after_yes(self):
        calls = []
        with mock.patch.object(lp.subprocess, "run", side_effect=lambda *a, **k: calls.append(a) or mock.Mock(returncode=0)):
            player = lp.make_player(["paplay"])
            self.assertEqual(calls, [])  # building a player starts nothing
            player("/x/y.wav")
        self.assertEqual(calls[0][0], ["paplay", "/x/y.wav"])

    def test_find_player_prefers_paplay_then_aplay_then_ffplay(self):
        self.assertEqual(lp.find_player(which=lambda n: "/usr/bin/" + n)[0], "/usr/bin/paplay")
        self.assertEqual(lp.find_player(which=lambda n: "/b/aplay" if n == "aplay" else None), ["/b/aplay", "-q"])
        self.assertEqual(lp.find_player(which=lambda n: "/b/ffplay" if n == "ffplay" else None)[1:3], ["-nodisp", "-autoexit"])


if __name__ == "__main__":
    unittest.main()
