"""Render one screen of the mock set to a 1920x1080 PNG: python tools/ui/render_mock.py main out.png"""
import pathlib, sys
import mockkit

screen, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
html_path = out.with_suffix(".html")
html_path.write_text(mockkit.prepare(screen), encoding="utf8")
mockkit.chrome([f"--screenshot={out}", "file://" + str(html_path)])
html_path.unlink()
print(out)
