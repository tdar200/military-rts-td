#!/bin/bash
# usage: tools/ui/verify_all.sh [screens...]   (default: the six original screens, then gp01..gp12)
# Renders each mock with headless Chrome (cached), captures the Godot gallery screen, and diffs the pair per rectangle.
# Output (mock PNGs, captures, side-by-sides) goes to $UI_OUT, default ${TMPDIR:-/tmp}/ascension-ui-verify. Exit 1 when any screen fails.
# gp01..gp12 are the gameplay boards. A gpNN with no gallery case yet (no `"gpNN"` arm in scripts/gallery/gallery.gd) is
# reported as pending and skipped, never as a failure; it starts being verified the moment its gallery case lands.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${UI_OUT:-${TMPDIR:-/tmp}/ascension-ui-verify}"
mkdir -p "$OUT"
GP="gp01 gp02 gp03 gp04 gp05 gp06 gp07 gp08 gp09 gp10 gp11 gp12"
SCREENS=${@:-main builddeck coreassault research title debrief $GP}
declare -A SPEC=([main]=compare.json [builddeck]=compare_build.json [coreassault]=compare_assault.json [research]=compare_research.json [title]=compare_title.json [debrief]=compare_debrief.json)
for g in $GP; do SPEC[$g]=compare_$g.json; done
status=0
pending=0
for s in $SCREENS; do
  if [[ "$s" == gp[0-9][0-9] ]] && ! grep -q "\"$s\"" "$REPO/godot3d/scripts/gallery/gallery.gd"; then
    echo "=== $s"
    echo "pending: no gallery case (skipped)"
    pending=$((pending + 1))
    continue
  fi
  [ -f "$OUT/mock_$s.png" ] || python3 "$REPO/tools/ui/render_mock.py" "$s" "$OUT/mock_$s.png" >/dev/null || status=1
  "$REPO/tools/ui/run_cap.sh" "$s" "$OUT/godot_$s.png"
  echo "=== $s"
  python3 "$REPO/tools/ui/diff_screens.py" "$s" "$OUT/mock_$s.png" "$OUT/godot_$s.png" "$OUT/diff_$s" --spec "$REPO/tools/ui/${SPEC[$s]}" 2>&1 | tail -30
  [ "${PIPESTATUS[0]}" = 0 ] || status=1
done
[ "$pending" -gt 0 ] && echo "--- $pending gameplay board(s) pending a gallery case (not failures)"
exit $status
