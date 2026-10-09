#!/usr/bin/env python3
"""Driver for tools/perf/gpu_frametime.sh (plan 2026-10-07-kestrel-depth, Task 29). Run the shell script, not this file.

It starts the real game on YOUR display through tools/qa/launch_ui.py (GPU rendering, the Dummy audio driver, an isolated
bridge), clicks New operation and Deploy forces, then records an uncapped frame-time window in three scenes with the
in-game perf window of tools/qa/ui_driver.gd (per-frame delta, root viewport GPU and CPU render time, draw calls):
  idle        the default Kestrel view over the home base, before any wave arrives
  zoomed-out  the maximum zoom over the middle of the map
  combat      the default view, once an alien unit is within CONTACT_TILES of something of ours (waits up to --combat-wait)
Each scene is judged on its frame-time p50 against BUDGET_MS and compared with tools/ui/world_baseline.json "_perf_gpu"
(measured on the same RTX 3050 on 2026-10-05). Results go to <out>/results.json and <out>/results.txt (written after every
scene, so a stopped run keeps what it measured) next to the raw perf_<scene>.json files.
The processes it starts are stopped by PID when it ends, on Ctrl-C or on SIGTERM; it never signals anything else."""
import argparse, datetime, json, math, os, pathlib, signal, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUDGET_MS = 10.0
CONTACT_TILES = 10.0
DEFAULT_SECONDS = 10.0
DEFAULT_COMBAT_WAIT_S = 420.0
BASELINE_FILE = ROOT / "tools/ui/world_baseline.json"
# scene name -> key under "_perf_gpu" in the baseline file (combat has none: it was never measured)
BASELINE_KEYS = {"idle": "idle_default", "zoomed-out": "idle_zoomed_out"}
SCENES = [
    ("idle", "default view (zoom 10) over the home base, before the first wave"),
    ("zoomed-out", "maximum zoom (18) over the middle of the map"),
    ("combat", "default view over the first contact: an alien unit within %d tiles of something of ours" % CONTACT_TILES),
]


def load_baseline(path=BASELINE_FILE):
    data = json.loads(pathlib.Path(path).read_text()).get("_perf_gpu", {})
    return {scene: data[key] for scene, key in BASELINE_KEYS.items() if key in data}


def plan_text(seconds=DEFAULT_SECONDS, out="<repo>/build/perf/gpu_frametime-<timestamp>"):
    base = load_baseline()
    lines = ["GPU frame-time plan (dry run: nothing is launched)",
             "  budget:   frame time p50 at or under %g ms in every scene (p95 is reported, not judged)" % BUDGET_MS,
             "  windows:  %g s each, uncapped (frame cap and vsync lifted inside the window), whole frame with the HUD" % seconds,
             "  output:   %s (results.json, results.txt, raw perf_<scene>.json)" % out,
             "  baseline: %s key _perf_gpu (RTX 3050 via PRIME offload, 2026-10-05, Kestrel idle after deploy)" % BASELINE_FILE.relative_to(ROOT),
             "  scenes:"]
    for i, (name, what) in enumerate(SCENES, 1):
        b = base.get(name)
        ref = ("baseline p50 %.2f ms, p95 %.2f ms, %.1f fps" % (b["frame_ms_p50"], b["frame_ms_p95"], b["fps"])) if b else "no baseline (never measured)"
        lines.append("    %d. %-10s %s; %s" % (i, name, what, ref))
    lines += ["  the game opens a window on your display (Dummy audio, so no sound), plays New operation then Deploy forces,",
              "  and is stopped by PID when the run ends. Combat waits up to %g s for the first wave." % DEFAULT_COMBAT_WAIT_S]
    return "\n".join(lines)


def summarise(perf):
    s = perf.get("summary", {})

    def pick(key, stat):
        return float(s.get(key, {}).get(stat, float("nan")))
    return {"frames": int(perf.get("frames", 0)), "fps": float(perf.get("fps", 0.0)),
            "frame_ms_p50": pick("frame_ms", "p50"), "frame_ms_p95": pick("frame_ms", "p95"), "frame_ms_max": pick("frame_ms", "max"),
            "gpu_ms_p50": pick("gpu_ms", "p50"), "cpu_render_ms_p50": pick("cpu_render_ms", "p50"),
            "draw_calls_p50": pick("draw_calls", "p50"), "primitives_p50": pick("primitives", "p50")}


def within_budget(summary):
    p50 = summary.get("frame_ms_p50", float("nan"))
    return not math.isnan(p50) and p50 <= BUDGET_MS


def compare_text(summary, base):
    if not base:
        return "no baseline"
    d = summary["frame_ms_p50"] - base["frame_ms_p50"]
    return "p50 %.2f ms vs baseline %.2f ms (%+.2f ms)" % (summary["frame_ms_p50"], base["frame_ms_p50"], d)


def _pos(e):
    return (e["x_bits"] / 65536.0, e["z_bits"] / 65536.0)


def contact_point(snapshot, tiles=CONTACT_TILES):
    """Midpoint (x, z) of the first alien unit within `tiles` of one of our entities, else None. Owner 0 is the player."""
    mine = [_pos(e) for e in snapshot.get("entities", []) if e.get("owner") == 0 and e.get("hp_bits", 1) > 0]
    for e in snapshot.get("entities", []):
        if e.get("owner") in (0, None) or e.get("category") != "unit" or e.get("hp_bits", 1) <= 0:
            continue
        x, z = _pos(e)
        for mx, mz in mine:
            if math.hypot(x - mx, z - mz) <= tiles:
                return ((x + mx) / 2.0, (z + mz) / 2.0)
    return None


def in_contact(snapshot, tiles=CONTACT_TILES):
    return contact_point(snapshot, tiles) is not None


def on_signal(signum, frame):
    raise SystemExit(128 + signum)


def stop_pids(pids, wait_s=8.0):
    """Stop the processes this run started, by PID. SIGTERM, then SIGKILL for any still alive after wait_s."""
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    end = time.monotonic() + wait_s
    alive = list(pids)
    while alive and time.monotonic() < end:
        alive = [p for p in alive if _alive(p)]
        if alive:
            time.sleep(0.2)
    for pid in alive:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    return [p for p in pids if _alive(p)]


def _alive(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            return f.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        return False


def gpu_name():
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else "unknown (nvidia-smi failed)"
    except (OSError, subprocess.SubprocessError):
        return "unknown (no nvidia-smi)"


def scene_lines(r):
    s = r["summary"]
    lines = ["%-10s p50 %6.2f ms  p95 %6.2f ms  max %6.2f ms  %6.1f fps  gpu p50 %5.2f  draws %5.0f  %s" % (
        r["scene"], s["frame_ms_p50"], s["frame_ms_p95"], s["frame_ms_max"], s["fps"], s["gpu_ms_p50"], s["draw_calls_p50"],
        "WITHIN BUDGET" if r["within_budget"] else "OVER BUDGET"), "           " + r["baseline_compare"]]
    return lines + ["           note: " + n for n in r["notes"]]


def write_results(out, meta, rows):
    (out / "results.json").write_text(json.dumps({"meta": meta, "scenes": rows}, indent=1))
    lines = ["GPU frame times, %s" % meta["started"], "GPU: %s   display: %s   budget: p50 <= %g ms   window: %g s" % (
        meta["gpu"], meta["display"], BUDGET_MS, meta["seconds"]), ""]
    for r in rows:
        lines += scene_lines(r)
    (out / "results.txt").write_text("\n".join(lines) + "\n")
    return "\n".join(lines)


def run_real(args):
    sys.path.insert(0, str(ROOT / "tools/qa"))
    from ui_client import UI
    out = pathlib.Path(args.out) if args.out else ROOT / "build/perf" / ("gpu_frametime-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    out = out.resolve()
    qa = out / "qa"
    qa.mkdir(parents=True, exist_ok=True)
    meta = {"started": datetime.datetime.now().isoformat(timespec="seconds"), "gpu": gpu_name(), "seconds": args.seconds,
            "display": os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY", ""), "budget_ms": BUDGET_MS,
            "prime_offload": os.environ.get("__NV_PRIME_RENDER_OFFLOAD", ""), "glx_vendor": os.environ.get("__GLX_VENDOR_LIBRARY_NAME", "")}
    print("output: %s\nGPU: %s" % (out, meta["gpu"]), flush=True)
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, on_signal)
    pids, rows = [], []
    base = load_baseline()
    try:
        # no software-render flag: launch_ui.py renders on the GPU on the current display and selects the NVIDIA GPU itself
        subprocess.run([sys.executable, str(ROOT / "tools/qa/launch_ui.py"), str(qa), "--scenario", "kestrel", "--driver", "world"], check=True)
        pids = json.loads((qa / "pids.json").read_text())
        ui = UI(qa)
        deadline = time.monotonic() + 120
        while not (qa / "observation.json").exists():
            if time.monotonic() > deadline:
                raise SystemExit("no observation after 120 s; see " + str(qa / "godot.log"))
            time.sleep(1)
        ui.button("New operation", soft=True)
        time.sleep(2)
        ui.button("Deploy forces", soft=True)
        time.sleep(8)

        def measure(scene, notes):
            ui.send({"type": "perf", "name": scene, "seconds": args.seconds, "uncapped": True}, timeout=args.seconds + 180)
            perf = json.loads((qa / ("perf_%s.json" % scene)).read_text())
            s = summarise(perf)
            snap = ui.snapshot()
            notes = list(notes) + ["tick %s, waves survived %s" % (snap.get("tick"), snap.get("waves_survived"))]
            if 58.0 <= s["fps"] <= 62.0 or 142.0 <= s["fps"] <= 146.0:
                notes.append("fps sits at a common display rate: the compositor or vsync may still be capping the window")
            if scene != "combat" and in_contact(snap):
                notes.append("an alien unit was already in contact: this scene is not idle")
            rows.append({"scene": scene, "summary": s, "within_budget": within_budget(s), "baseline": base.get(scene),
                         "baseline_compare": compare_text(s, base.get(scene)), "notes": notes})
            write_results(out, meta, rows)
            print("\n".join(scene_lines(rows[-1])), flush=True)

        ui.send({"type": "world_shot", "name": "idle", "focus": "home", "zoom": 10.0})
        measure("idle", [])
        ui.send({"type": "world_shot", "name": "zoomed_out", "tile": [21, 12], "zoom": 18.0})
        measure("zoomed-out", [])
        print("waiting up to %g s for the first contact..." % args.combat_wait, flush=True)
        end, point = time.monotonic() + args.combat_wait, None
        while time.monotonic() < end:
            point = contact_point(ui.snapshot())
            if point:
                break
            time.sleep(2)
        notes = []
        if point:
            ui.send({"type": "world_shot", "name": "combat", "tile": [int(round(point[0])), int(round(point[1]))], "zoom": 10.0})
        else:
            ui.send({"type": "world_shot", "name": "combat", "focus": "home", "zoom": 10.0})
            notes.append("NO CONTACT within %g s: this window is not combat, measure again with --combat-wait larger" % args.combat_wait)
        measure("combat", notes)
    finally:
        if not pids and (qa / "pids.json").exists():  # launch_ui.py died part way: it records each PID as it starts it
            pids = json.loads((qa / "pids.json").read_text())
        left = stop_pids(pids) if pids else []
        if left:
            print("WARNING: could not stop PIDs %s; stop them by hand" % left, file=sys.stderr)
        elif pids:
            print("game and bridge stopped (PIDs %s)" % pids, flush=True)
    text = write_results(out, meta, rows)
    print("\n" + text + "\n\nresults: %s" % (out / "results.txt"))
    return 0 if all(r["within_budget"] for r in rows) else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="gpu_frametime.sh")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--allow-user-display", action="store_true")
    ap.add_argument("--seconds", type=float, default=DEFAULT_SECONDS)
    ap.add_argument("--out")
    ap.add_argument("--combat-wait", type=float, default=DEFAULT_COMBAT_WAIT_S)
    args = ap.parse_args(argv)
    if args.seconds <= 0 or args.combat_wait < 0:
        ap.error("--seconds must be positive and --combat-wait not negative")
    if args.dry_run:
        print(plan_text(args.seconds, args.out or "<repo>/build/perf/gpu_frametime-<timestamp>"))
        return 0
    if not args.allow_user_display:
        print("gpu_frametime: refusing; pass --allow-user-display (the game opens a window on your display)", file=sys.stderr)
        return 2
    return run_real(args)


if __name__ == "__main__":
    sys.exit(main())
