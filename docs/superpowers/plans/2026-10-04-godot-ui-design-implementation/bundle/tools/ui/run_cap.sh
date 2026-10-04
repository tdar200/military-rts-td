#!/bin/bash
# usage: tools/ui/run_cap.sh <screen> <ABSOLUTE out.png>
# Renders one gallery screen (main, builddeck, coreassault, research, title, debrief) at 1920x1080 under Xvfb.
# PROJ overrides the Godot project directory (default: <repo>/godot3d).
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
G="$REPO/tools/godot/Godot_v4.7.2-stable_linux.x86_64"
PROJ="${PROJ:-$REPO/godot3d}"
xvfb-run -a -s "-screen 0 1920x1080x24" env LIBGL_ALWAYS_SOFTWARE=1 "$G" --path "$PROJ" --resolution 1920x1080 \
  --script res://scripts/gallery/capture.gd -- "$1" "$2" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:|saved|    at:" | grep -v "x11\|xic" | head -30
