"""Shared helpers: turn a design-canvas board (.dc.html) into plain HTML that headless Chrome can render."""
import json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).absolute().parent
REPO = HERE.parents[1]
MOCKS = REPO / "docs/ascension/ui-mocks"
GAMEPLAY = REPO / "docs/ascension/ui-mocks-gameplay"
LAND_BLOB = "4439b34dc8ac1316a28492d84cfe9efd"  # shared Kestrel Reach world image used by every gameplay board
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

# gp09's pause-menu board stacks its battlefield sprites above the menu chrome; with real sprites they would cover the
# buttons the chrome check measures, so its world sprites stay blank (as they always were).
BLANK_WORLD_SPRITES = {"gp09"}


def screens():
    return json.loads((HERE / "screens.json").read_text())

def prepare(screen, extra_head=""):
    """Return runnable HTML for a screen key from screens.json."""
    cfg = screens()[screen]
    gameplay = cfg.get("dir") == "ui-mocks-gameplay"
    src = (GAMEPLAY if gameplay else MOCKS) / cfg["mock"]
    if cfg.get("flatten"):
        html = subprocess.run(["node", str(HERE / "flatten_dc.mjs"), str(src)],
                              check=True, capture_output=True, text=True).stdout
    else:
        html = src.read_text(encoding="utf8")
    if gameplay:
        # gameplay boards link a shared stylesheet and the world image by relative / artifact paths
        css = (GAMEPLAY / "hud.css").read_text(encoding="utf8")
        html = html.replace('<link rel="stylesheet" href="./hud.css">', "<style>" + css + "</style>")
    blob = json.loads((MOCKS / "blob-map.json").read_text())
    if gameplay and screen not in BLANK_WORLD_SPRITES:
        blob.update(json.loads((HERE / "gameplay-blob-map.json").read_text()))
    def sprite(m):
        if gameplay and m.group(1) == LAND_BLOB:
            return "file://" + str(GAMEPLAY / "terrain/land.jpg")
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
