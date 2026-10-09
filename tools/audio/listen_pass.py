#!/usr/bin/env python3
"""Guided listening pass over the procedural sound set (plan 2026-10-07-kestrel-depth, Task 29; spec section P6).

THIS TOOL IS FOR YOU TO RUN, ON YOUR OWN SPEAKERS. Agents never run it: it refuses unless stdin is an interactive
terminal, and it plays nothing until you type the word yes.

Usage (from the repo root):
  python3 tools/audio/listen_pass.py --list                     list every sound id with its category, no sound
  python3 tools/audio/listen_pass.py                            play all 26, in manifest order
  python3 tools/audio/listen_pass.py --only weapon              one category (weapon, impact, loop, ui, voice, alert)
  python3 tools/audio/listen_pass.py --only rifle,cannon        one or more ids (ids and categories can be mixed)
  python3 tools/audio/listen_pass.py --notes listen-notes.txt   after each sound, type a note (Enter = none, q = stop)

What happens: it prints how many sounds will play and asks you to type yes (anything else cancels). Then, for each
sound, it prints a line such as `[3/26] weapon  plasma_bolt  0.6 s  resonant saw zap ...` BEFORE playing the file, so you
know what you are about to hear. Turn your volume down first; the loudest sounds peak near -1.5 dBFS. A short gap
separates the sounds. Ctrl-C stops at once.

Notes: with --notes FILE, each note you type is appended to FILE as `id<TAB>category<TAB>note`, under a dated header,
so you can read the file back afterwards (or paste it to an agent). A blank answer writes nothing.

The sounds come from godot3d/assets/audio/sfx/sfx_manifest.json (written by tools/audio/build_sfx.py). Playback uses the
first of paplay, aplay or ffplay found on PATH; with none of them it stops with an error before asking anything.
Exit codes: 0 finished or stopped by you, 1 you did not type yes, 2 refused (not a terminal, no player, bad option,
missing file), 130 interrupted.

main(argv, stdin, player): `player` is a callable taking the WAV path (the tests inject a recorder)."""
import argparse, datetime, json, pathlib, shutil, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPO / "godot3d/assets/audio/sfx/sfx_manifest.json"
CATEGORY_ORDER = ["weapon", "impact", "loop", "ui", "voice", "alert"]
REAL_GAP_S = 0.5  # pause between sounds when the real player is used


def load_manifest(path=DEFAULT_MANIFEST):
    """The manifest's sounds in file order, each with an absolute `path` to its WAV."""
    path = pathlib.Path(path)
    data = json.loads(path.read_text())
    out = []
    for s in data["sounds"]:
        item = dict(s)
        item["path"] = str(path.parent / s["file"])
        out.append(item)
    return out


def find_player(which=shutil.which):
    """argv prefix of the first playback program found (paplay, aplay, ffplay), or None."""
    exe = which("paplay")
    if exe:
        return [exe]
    exe = which("aplay")
    if exe:
        return [exe, "-q"]
    exe = which("ffplay")
    if exe:
        return [exe, "-nodisp", "-autoexit", "-loglevel", "quiet"]
    return None


def make_player(prefix):
    """A player(path) that runs `prefix + [path]` and waits for it. Nothing starts until it is called."""
    def play(path):
        subprocess.run(list(prefix) + [str(path)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=60, check=False)
    return play


def select(sounds, only):
    """Sounds matching a comma list of ids and/or categories, keeping manifest order. None when `only` names nothing known."""
    if not only:
        return list(sounds)
    wanted = [w.strip() for w in only.split(",") if w.strip()]
    ids = {s["id"] for s in sounds}
    cats = {s["category"] for s in sounds}
    if not wanted or any(w not in ids and w not in cats for w in wanted):
        return None
    return [s for s in sounds if s["id"] in wanted or s["category"] in wanted]


def label(index, total, s):
    return "[%d/%d] %-7s %-18s %.1f s%s  %s" % (index, total, s["category"], s["id"], float(s.get("duration_s", 0)),
                                                " loop" if s.get("loop") else "", s.get("character", ""))


def main(argv=None, stdin=None, player=None, stdout=None, sleep=None, which=shutil.which):
    out = stdout if stdout is not None else sys.stdout
    stdin = stdin if stdin is not None else sys.stdin

    def say(text=""):
        out.write(text + "\n")
        out.flush()

    ap = argparse.ArgumentParser(prog="listen_pass.py", description="Guided listening pass over the procedural sound set.")
    ap.add_argument("--list", action="store_true", help="print every id with its category and exit (plays nothing)")
    ap.add_argument("--only", help="comma list of categories and/or ids")
    ap.add_argument("--notes", help="append a typed note per sound to this file")
    ap.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="sfx_manifest.json to use")
    ap.add_argument("--gap", type=float, help="seconds between sounds (default 0.5 with the real player)")
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0

    try:
        sounds = load_manifest(args.manifest)
    except (OSError, ValueError, KeyError) as e:
        say("listen_pass: cannot read the manifest %s (%s)" % (args.manifest, e))
        return 2

    if args.list:
        for i, s in enumerate(sounds, 1):
            say(label(i, len(sounds), s))
        return 0

    if not stdin.isatty():
        say("listen_pass: refusing to play. stdin is not an interactive terminal, and this tool makes sound on your speakers "
            "only when you run it yourself at a terminal and type yes.")
        return 2

    chosen = select(sounds, args.only)
    if chosen is None:
        say("listen_pass: --only %r matches nothing. Categories: %s" % (args.only, ", ".join(CATEGORY_ORDER)))
        say("ids: " + ", ".join(s["id"] for s in sounds))
        return 2
    missing = [s["file"] for s in chosen if not pathlib.Path(s["path"]).is_file()]
    if missing:
        say("listen_pass: missing WAV file(s): " + ", ".join(missing))
        return 2

    if player is None:
        prefix = find_player(which)
        if prefix is None:
            say("listen_pass: no audio player found. Install pulseaudio-utils (paplay), alsa-utils (aplay) or ffmpeg (ffplay).")
            return 2
        player = make_player(prefix)
        gap = REAL_GAP_S if args.gap is None else args.gap
    else:
        gap = 0.0 if args.gap is None else args.gap
    nap = sleep if sleep is not None else time.sleep

    total = len(chosen)
    say("This will play %d sound(s) through your default audio output, at the file's own level. Turn your volume down first." % total)
    out.write("Type yes to continue: ")
    out.flush()
    answer = stdin.readline()
    if answer.strip().lower() != "yes":
        say("Cancelled. Nothing was played.")
        return 1

    notes = None
    if args.notes:
        notes = open(args.notes, "a", encoding="utf-8")
        notes.write("# listening pass %s\n" % datetime.datetime.now().isoformat(timespec="seconds"))
        notes.flush()
    try:
        for i, s in enumerate(chosen, 1):
            say(label(i, total, s))
            player(s["path"])
            if notes is not None:
                out.write("  note (Enter = none, q = stop): ")
                out.flush()
                line = stdin.readline()
                if line == "" or line.strip().lower() == "q":
                    say("")
                    say("Stopped after %d of %d." % (i, total))
                    return 0
                text = line.strip()
                if text:
                    notes.write("%s\t%s\t%s\n" % (s["id"], s["category"], text))
                    notes.flush()
            elif gap > 0 and i < total:
                nap(gap)
    except KeyboardInterrupt:
        say("")
        say("Interrupted.")
        return 130
    finally:
        if notes is not None:
            notes.close()
    say("Done: %d sound(s)." % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
