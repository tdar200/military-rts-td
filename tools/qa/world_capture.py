"""Capture world-only frames from an isolated harness for world_diff. Kills only the PIDs it started.
Usage: world_capture.py <qa_dir> [--scenario kestrel|survival] [--only a,b] [--display :94] [--gpu] [--perf SECONDS]"""
import json, os, pathlib, signal, subprocess, sys, time
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from ui_client import UI


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    qa = pathlib.Path(sys.argv[1]).resolve()
    scenario = arg("--scenario", "kestrel")
    cfg = json.loads((ROOT / "tools/ui/world_frames.json").read_text())
    frames = cfg["live"][scenario]
    only = arg("--only")
    if only:
        frames = {k: v for k, v in frames.items() if k in only.split(",")}
    cmd = [sys.executable, str(HERE / "launch_ui.py"), str(qa), "--scenario", scenario, "--driver", "world"]
    if "--gpu" not in sys.argv:
        cmd += ["--software", "--display", arg("--display", ":94")]
    subprocess.run(cmd, check=True)
    pids = json.loads((qa / "pids.json").read_text())
    try:
        ui = UI(qa)
        deadline = time.monotonic() + 120
        while not (qa / "observation.json").exists():
            if time.monotonic() > deadline:
                raise SystemExit("no observation after 120 s; see " + str(qa / "godot.log"))
            time.sleep(1)
        ui.button("New operation", soft=True)
        time.sleep(2)
        ui.button("Deploy forces", soft=True)
        time.sleep(6)
        for name, f in frames.items():
            event = {"type": "world_shot", "name": name, "zoom": f["zoom"], "swatches": f.get("swatches", {})}
            if "tile" in f:
                event["tile"] = f["tile"]
            else:
                event["focus"] = "home"
            ui.send(event, timeout=120)
            print(name, json.loads((qa / f"{name}.json").read_text())["draw_calls"])
        seconds = float(arg("--perf", "0"))
        if seconds > 0:
            samples = []
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                o = ui.observe()
                samples.append({"fps": o["fps"], "process_ms": o["process_ms"], "draw_calls": o["draw_calls"]})
                time.sleep(0.5)
            (qa / "perf.json").write_text(json.dumps(samples))
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


if __name__ == "__main__":
    main()
