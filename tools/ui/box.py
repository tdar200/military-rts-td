"""Look up boxes by own text: python tools/ui/box.py out.json "Grid deficit" [--all]"""
import json, sys

boxes = json.load(open(sys.argv[1]))
needle = sys.argv[2].lower()
for b in boxes:
    if needle in b["text"].lower():
        print(f'{b["text"][:44]!r:48} x={b["x"]:.1f} y={b["y"]:.1f} w={b["w"]:.1f} h={b["h"]:.1f}  '
              f'{b["font"]} {b["fs"]} w{b["fw"]} ls={b["ls"]} lh={b["lh"]} {b["color"]}')
