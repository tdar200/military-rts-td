#!/usr/bin/env bash
# GPU frame-time measurement for the Kestrel scene (plan 2026-10-07-kestrel-depth, Task 29; spec section P6).
#
# THIS SCRIPT IS FOR YOU TO RUN, on your own machine. It opens the game in a window on YOUR display (it can take focus,
# and your real cursor over the window scrolls and hovers the scene), so it refuses to do anything unless you pass
# --allow-user-display. Agents never run it for real; they only run the refusal and --dry-run.
#
# Usage:
#   tools/perf/gpu_frametime.sh --allow-user-display --dry-run         print the plan, launch nothing
#   tools/perf/gpu_frametime.sh --allow-user-display                   measure idle, zoomed-out and combat
#   options: --seconds N      length of each measuring window (default 10)
#            --out DIR        results directory (default build/perf/gpu_frametime-<timestamp>, gitignored)
#            --combat-wait N  seconds to wait for the first wave before measuring combat (default 420)
#
# Each scene is judged on its frame-time p50 against a 10 ms budget (about 100 fps) and compared with the 2026-10-05
# RTX 3050 numbers in tools/ui/world_baseline.json ("_perf_gpu"). Results land in <out>/results.txt and results.json.
# Exit codes: 0 every scene within budget, 1 some scene over budget, 2 refused or bad usage.
#
# How it runs: tools/perf/gpu_frametime_run.py starts the game and its bridge through tools/qa/launch_ui.py (Dummy audio
# driver, so no sound), uses the in-game perf window of tools/qa/ui_driver.gd for the frame times, and stops the processes
# it started by PID when it ends (also on Ctrl-C). The GPU is chosen as run-3d.sh does: PRIME render offload to the NVIDIA
# GPU on a hybrid laptop, unless EARTHFRONT_GPU=integrated.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/gpu_frametime_run.py"

allow=0
dry=0
passthrough=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-user-display) allow=1 ;;
    --dry-run) dry=1 ;;
    --seconds | --out | --combat-wait)
      if [[ $# -lt 2 ]]; then echo "gpu_frametime: $1 needs a value" >&2; exit 2; fi
      passthrough+=("$1" "$2"); shift ;;
    -h | --help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "gpu_frametime: unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ $allow -ne 1 ]]; then
  echo "gpu_frametime: refusing. This opens the game in a window on YOUR display (it can take focus, and your real cursor" >&2
  echo "over it scrolls and hovers the scene). Re-run with --allow-user-display to accept that, or add --dry-run to see the plan." >&2
  exit 2
fi

if [[ $dry -eq 1 ]]; then
  exec python3 "$RUNNER" --dry-run ${passthrough[@]+"${passthrough[@]}"}
fi

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "gpu_frametime: no DISPLAY or WAYLAND_DISPLAY in this shell, so there is no display to open the game on. Run it from a desktop terminal." >&2
  exit 2
fi

# Hybrid Linux laptops can otherwise select Mesa/Intel despite an available NVIDIA GPU (same handling as run-3d.sh).
if [[ "${EARTHFRONT_GPU:-auto}" != "integrated" ]] && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
fi

exec python3 "$RUNNER" --allow-user-display ${passthrough[@]+"${passthrough[@]}"}
