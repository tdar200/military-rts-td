"""Shared helpers: turn a design-canvas board (.dc.html) into plain HTML that headless Chrome can render."""
import json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).absolute().parent
REPO = HERE.parents[1]
MOCKS = REPO / "docs/ascension/ui-mocks"
ASSETS = REPO / "assets"
FONTS = REPO / "godot3d/assets/fonts"
ROOT_TAG = re.compile(r'<div style="position:relative;width:1920px;height:1080px[^>]*>')
BOXES_JS = r"""
<script>
window.addEventListener('load', () => setTimeout(() => {
  const out = [];
  const root = document.querySelector('div[style*="width:1920px"]') || document.body;
  for (const el of root.querySelectorAll('*')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    const cs = getComputedStyle(el);
    let own = '';
    for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
    own = own.replace(/\s+/g, ' ').trim();
    out.push({tag: el.tagName.toLowerCase(), cls: el.getAttribute('class') || '', text: own.slice(0, 60),
      x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2),
      font: cs.fontFamily.split(',')[0].replace(/["']/g, ''), fs: cs.fontSize, fw: cs.fontWeight,
      ls: cs.letterSpacing, lh: cs.lineHeight, color: cs.color, bg: cs.backgroundColor,
      bgi: cs.backgroundImage === 'none' ? '' : cs.backgroundImage.slice(0, 90),
      bc: cs.borderTopColor, bw: cs.borderTopWidth, br: cs.borderRadius});
  }
  const pre = document.createElement('pre'); pre.id = '__boxes'; pre.textContent = JSON.stringify(out);
  document.body.appendChild(pre);
}, 300));
</script>
"""

def screens():
    return json.loads((HERE / "screens.json").read_text())

def prepare(screen, extra_head=""):
    """Return runnable HTML for a screen key from screens.json."""
    cfg = screens()[screen]
    if cfg.get("flatten"):
        html = subprocess.run(["node", str(HERE / "flatten_dc.mjs"), str(MOCKS / cfg["mock"])],
                              check=True, capture_output=True, text=True).stdout
    else:
        html = (MOCKS / cfg["mock"]).read_text(encoding="utf8")
    blob = json.loads((MOCKS / "blob-map.json").read_text())
    def sprite(m):
        name = blob.get(m.group(1))
        return "file://" + str(ASSETS / name) if name else "data:image/gif;base64,R0lGODlhAQABAAAAACw="
    html = re.sub(r"/_blob/([0-9a-f]{32})", sprite, html)
    html = html.replace('<script src="./support.js"></script>', "")
    html = re.sub(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^>]*>', "", html)
    marker = cfg.get("strip_until")
    if marker:
        root = ROOT_TAG.search(html)
        end = html.index(marker)
        ground = f'<div style="position:absolute;left:0;top:0;width:1920px;height:1080px;background:{cfg["ground"]}"></div>'
        html = html[: root.end()] + ground + html[end:]
    if cfg.get("drop_sprites"):
        # keep world-space annotations, drop the painted battlefield (background, grid, <img class="spr">)
        root = ROOT_TAG.search(html)
        end = html.index(cfg["drop_sprites"])
        ground = f'<div style="position:absolute;left:0;top:0;width:1920px;height:1080px;background:{cfg["ground"]}"></div>'
        html = html[: root.end()] + ground + html[end:]
        html = re.sub(r'<img class="spr"[^>]*>', "", html)
    fonts = f"""<style>
@font-face{{font-family:'Rajdhani';font-weight:500 600;src:url(file://{FONTS}/Rajdhani-SemiBold.ttf)}}
@font-face{{font-family:'Rajdhani';font-weight:700;src:url(file://{FONTS}/Rajdhani-Bold.ttf)}}
@font-face{{font-family:'IBM Plex Sans';font-weight:100 900;src:url(file://{FONTS}/IBMPlexSans-VF.ttf)}}
@font-face{{font-family:'IBM Plex Mono';font-weight:400;src:url(file://{FONTS}/IBMPlexMono-Regular.ttf)}}
@font-face{{font-family:'IBM Plex Mono';font-weight:500;src:url(file://{FONTS}/IBMPlexMono-Medium.ttf)}}
</style>"""
    return html.replace("<head>", "<head>" + fonts + extra_head, 1)

def chrome(args, out=None):
    cmd = ["google-chrome", "--headless=new", "--disable-gpu", "--hide-scrollbars",
           "--force-device-scale-factor=1", "--window-size=1920,1080", "--virtual-time-budget=5000"] + args
    return subprocess.run(cmd, check=True, capture_output=True, text=True)
