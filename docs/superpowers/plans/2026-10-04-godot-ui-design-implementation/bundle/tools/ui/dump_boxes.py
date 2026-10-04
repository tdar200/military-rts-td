"""Dump every element's box and computed text style: python tools/ui/dump_boxes.py main out.json"""
import html, json, pathlib, re, sys
import mockkit

screen, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
page = out.with_suffix(".page.html")
page.write_text(mockkit.prepare(screen, extra_head=mockkit.BOXES_JS), encoding="utf8")
dom = mockkit.chrome(["--dump-dom", "file://" + str(page)]).stdout
page.unlink()
raw = re.search(r'<pre id="__boxes">(.*?)</pre>', dom, re.S).group(1)
boxes = json.loads(html.unescape(raw))
out.write_text(json.dumps(boxes, indent=1))
print(len(boxes), "boxes ->", out)
