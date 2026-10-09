#!/bin/sh
# Task 27 test stub for godot-bridge (test_bridge_launcher.gd). It takes the launcher's arguments
# (--runtime-dir <dir> [--exit-with-parent]), writes a tick-0 snapshot into <dir> the way the bridge does (a .next file,
# then a rename), then sleeps. `exec` makes the sleep this same process, so the pid the launcher holds is the whole stub
# and killing it leaves nothing behind; the sleep is bounded, so a stub a failed test lost still ends by itself.
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runtime-dir) dir="$2"; shift 2 ;;
    --runtime-dir=*) dir="${1#--runtime-dir=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$dir" ] || exit 2
mkdir -p "$dir" || exit 3
printf '{"schema":5,"tick":0,"stub":true}\n' > "$dir/snapshot.json.next" && mv "$dir/snapshot.json.next" "$dir/snapshot.json"
exec sleep 15
