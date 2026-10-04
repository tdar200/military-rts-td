#!/bin/bash
# usage: tools/ui/verify_all.sh [screens...]   (default: all six)
# Renders each mock with headless Chrome (cached), captures the Godot gallery screen, and diffs the pair per rectangle.
# Output (mock PNGs, captures, side-by-sides) goes to $UI_OUT, default ${TMPDIR:-/tmp}/ascension-ui-verify. Exit 1 when any screen fails.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${UI_OUT:-${TMPDIR:-/tmp}/ascension-ui-verify}"
mkdir -p "$OUT"
SCREENS=${@:-main builddeck coreassault research title debrief}
declare -A SPEC=([main]=compare.json [builddeck]=compare_build.json [coreassault]=compare_assault.json [research]=compare_research.json [title]=compare_title.json [debrief]=compare_debrief.json)
status=0
for s in $SCREENS; do
  [ -f "$OUT/mock_$s.png" ] || python3 "$REPO/tools/ui/render_mock.py" "$s" "$OUT/mock_$s.png" >/dev/null || status=1
  "$REPO/tools/ui/run_cap.sh" "$s" "$OUT/godot_$s.png"
  echo "=== $s"
  python3 "$REPO/tools/ui/diff_screens.py" "$s" "$OUT/mock_$s.png" "$OUT/godot_$s.png" "$OUT/diff_$s" --spec "$REPO/tools/ui/${SPEC[$s]}" 2>&1 | tail -30
  [ "${PIPESTATUS[0]}" = 0 ] || status=1
done
exit $status
