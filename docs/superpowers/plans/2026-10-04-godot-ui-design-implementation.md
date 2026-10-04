# Godot UI Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-built HUD in the Godot 3D client with the Ascension design set (title, Earthfront HUD, build deck, research graph, core assault, debrief), matching the mock boards pixel for pixel at 1920x1080 while the battlefield stays 3D.

**Architecture:** Code-built UI (approach A): a tokens file, a node-factory kit and small drawn components, then one script per screen that takes a plain `Dictionary` view model and emits `action(name, arg)`. A live layer (`live_*.gd`, `game_ui.gd`) maps `earthfront_3d.gd` state to those view models and maps actions back to the game's existing handlers, so game logic does not move. Every screen is verified three ways: headless unit tests, a per-rectangle pixel diff against the Chrome render of its mock, and a live run through the QA driver.

**Tech Stack:** Godot 4.7.2 (GDScript, `gl_compatibility`, `canvas_items` stretch), headless Chrome plus Python 3 (`numpy`, `Pillow`) and Node for the mock diff harness, Xvfb for software-rendered captures, the existing Rust `godot-bridge` for the live pass.

**Spec:** `docs/superpowers/specs/2026-10-04-godot-ui-design-implementation-design.md` (approved). Read it first. Design source: https://claude.ai/artifact/FCsmt1puJtbHqKGih7vuDg (the six boards used are copied into `docs/ascension/ui-mocks/` by Task 3).

## How the code is delivered: the bundle

The implementation already exists and has been verified end to end in a scratch copy of the repo (1491 tests, all six screens inside their diff limits, live pass with no script errors). Retyping 8,900 lines of GDScript into a plan would be slower and less safe than shipping the files, so the code lives next to this plan:

`docs/superpowers/plans/2026-10-04-godot-ui-design-implementation/bundle/` (136 files, 3.3 MB). It mirrors repo paths: `godot3d/scripts/ui/**`, `godot3d/scripts/gallery/**`, `godot3d/tests/**`, `godot3d/assets/**`, `tools/ui/**`, `tools/qa/**`, `docs/ascension/**`.

Each task installs its own slice of the bundle with the `inst` helper (a plain copy to the same relative path), tests first. That keeps the test-first loop real: you install the task's tests, watch them fail because the code is absent, install the code, watch them pass. The one project file that is edited rather than copied is `godot3d/project.godot` (Task 0), and the one game file is `godot3d/scripts/earthfront_3d.gd`, changed by the migration script `tools/ui/integrate_game.py` (Task 12), which asserts every anchor before editing.

Do not edit the bundle to "improve" it. If a step fails, fix the cause in the installed file and note the change in `docs/ascension/ui-deviations.md` (Task 14). The bundle has no `.uid` files; Godot creates them.

## Global Constraints

- Target: the Godot 3D client in `godot3d/` only. Out of scope: the solar strategic screen, gameplay boards G01-G08, the 3D scene, game logic, the Rust core and `godot-bridge`, the Macroquad shell.
- Fidelity: UI chrome pixel-matched at 1920x1080. Viewport 1920x1080, stretch `canvas_items`, renderer `gl_compatibility`. The 3D battlefield stays 3D.
- The UI is render-only. `cargo test --workspace` and the Rust golden hash are untouched by this work; do not run `cargo` commands that rebuild `godot-bridge` unless it is missing.
- Use `preload`, never `class_name`, in `scripts/ui`.
- Godot 4.7.2 binary: `tools/godot/Godot_v4.7.2-stable_linux.x86_64`. Headless tests: `--headless --path godot3d --script res://tests/run_tests.gd [-- "file.gd:"]`.
- No em dashes and no en dashes in any copy or document that a user will read (UI text, docs, README, deviations log). Use plain hyphens, commas or restructure. The only allowed occurrences are the em dash in the game's existing "ATTACK-MOVE ARMED" notification text, which `live_adapter.gd` splits and `test_live_adapter.gd` asserts, and the same text inside `integrate_game.py`. Task 14 greps for this.
- Commit nothing unless the user asks. `godot3d/` is entirely untracked in git and the repo has unrelated dirty changes; leave them alone. If the user later asks for a commit, end the message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; a PR description ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Back up `godot3d/` and `tools/qa` to a dated tarball outside the repo before the first edit (Task 0).
- Keep the QA button texts that `tools/qa/*` finds by visible `.text` (`BUILD`, `UNITS`, `DEPLOY FORCES`, building and research names), or update the QA tools in the same change (Task 13 does).
- Every clickable is a Button whose `.text` is its human label. Tests and the QA driver find controls by it.
- Keep `docs/ascension/ui-deviations.md` current: every mock flaw not copied, every block the live data cannot fill, every spec delta.
- Temporary files go to `$WORK` (set below), never into the repo.
- The user's CLAUDE.md rule on OpenAPI codegen pipelines does not apply here (nothing in this plan touches one).

## Review Focus

These are the inputs a person is most likely to meet that the spec does not spell out. Each is pinned by tests inside the task named in brackets; the pin lists the test names so a reviewer can check them.

1. **Missing, zero or empty data** (no power plant, no wave timer, no HQ, no Core, no relays, no research options, no recorded samples, a research project with no prerequisites or one naming a project that does not exist): the block is omitted or shows an honest empty state; nothing is faked and nothing crashes. [Tasks 4, 6, 8, 9, 10]
2. **Selection of zero, one or many units** (and mixed types): zero shows no panel or an empty state, one unit has no group row, many group by type and narrow when a group is clicked. [Tasks 4, 9, 10]
3. **Long or many things** (a 60-character operation name, 12 alerts, 12 chapters, 40 research projects, a long tag beside a state tag, 12 timeline rows): text is clipped or scrolls inside its panel, never overlaps a neighbour, and the button keeps its full name. [Tasks 5, 6, 7, 8, 9, 11]
4. **A click lost to a rebuild**: the HUD view model refreshes about ten times a second; a press must never land on a node that is replaced before the release, and scroll position must survive a rebuild. [Tasks 4, 5, 11]
5. **Input falling through to the 3D scene, and the QA driver at 1920x1080**: panels, the research modal and the debrief scrim must block hover, box-select and placement under them; the QA driver must still find and click buttons at the new size. [Tasks 4, 11, 13]

## Spec deltas decided while building

The approved spec is not rewritten; these departures are intentional and are recorded again in the deviations log (Task 14).

- Components are `scripts/ui/components/*.gd` plus `kit.gd`, not one `components.gd`.
- Icons are inline SVG path data in `icons.gd`, rasterised on demand. There is no `assets/ui/icons/` folder.
- The gallery is `scripts/gallery/capture.gd` run with `--script`, not a `ui_gallery.tscn`.
- The panel gradient top is rgb(18,32,46), as every mock writes it (the spec's `#122030` is a rounding).
- Deck tabs are Build, Units, Orders, Science (Science opens the research modal). Logistics is hidden because the bridge exposes no supply routes.
- Blocks the snapshot cannot fill are omitted (wave composition line, boss phase and retaliation, era-gate criteria, speed group, Stop/Hold/Resupply). The spec section 5 "data gaps" rule applies; no Rust change.

---

## Setup used by every task

Open one shell at the repo root and paste this block. Re-paste it in any new shell.

```bash
cd /home/tahseen-dar/Projects/military-rts-td
export P=docs/superpowers/plans/2026-10-04-godot-ui-design-implementation
export B=$P/bundle
export G=$PWD/tools/godot/Godot_v4.7.2-stable_linux.x86_64
export WORK=/tmp/ascension-ui-work; mkdir -p "$WORK"
export UI_OUT=$WORK/ui-verify
inst()  { for f in "$@"; do mkdir -p "$(dirname "$f")" && cp "$B/$f" "$f" || return 1; done; }  # copy bundle files to the same repo path
tests() { timeout 120 "$G" --headless --path godot3d --script res://tests/run_tests.gd 2>&1 | grep -E "passed|FAIL"; }
```

`tests` prints the final `N passed, M failed` line and one `FAIL` line per problem. A test script that cannot compile (because the code it preloads is not installed yet) shows as `FAIL <file>: the test script did not compile ...`; this is the expected "red" state in the first half of every task.

The screen diff is `tools/ui/verify_all.sh <screen>`; it writes to `$UI_OUT`. A passing row ends in `ok`; the script exits 1 if any row is `FAIL`.

## File map

Class names in the Interfaces blocks (`T`, `K`, `Icons`, `Hud`, `BuildDeck`, `Assault`, `LiveAdapter`, `GameUI`, and so on) are the local `preload` constant names each file uses. There are no `class_name` declarations.

| Path (under repo root) | Responsibility | Task |
|---|---|---|
| `godot3d/project.godot` | viewport 1920x1080, window overrides removed | 0 |
| `godot3d/assets/fonts/IBMPlex*`, `Rajdhani-Bold.ttf`, `FONT-LICENSES.md` | the three UI families (OFL) | 0 |
| `godot3d/assets/ui/sprites/*.png` | 15 unit and building sprites for deck cards | 0 |
| `godot3d/tests/run_tests.gd` | headless runner | 1 |
| `godot3d/scripts/ui/tokens.gd`, `icons.gd` | style guide constants, fonts, stroke icons | 1 |
| `godot3d/scripts/ui/kit.gd`, `components/*.gd` | node factories and drawn components | 2, 4-9 |
| `tools/ui/*`, `docs/ascension/ui-mocks/*` | mock render + diff harness, mock sources | 3 |
| `godot3d/scripts/gallery/*` | gallery capture and per-screen fixtures | 3-9 |
| `godot3d/scripts/ui/hud.gd` | Earthfront HUD, section/layer engine | 4 |
| `godot3d/scripts/ui/build_deck.gd`, `build_logic.gd` | build tab and placement | 5 |
| `godot3d/scripts/ui/research_screen.gd`, `research_layout.gd` | research graph | 6 |
| `godot3d/scripts/ui/title_screen.gd`, `fx.gd` | title and campaign | 7 |
| `godot3d/scripts/ui/debrief.gd` | victory and defeat debrief | 8 |
| `godot3d/scripts/ui/assault/*`, `world_marks.gd` | core-assault layout and world marks | 9 |
| `godot3d/scripts/ui/live_adapter.gd`, `live_assault.gd`, `session_log.gd`, `live_screens.gd` | live game to view models | 10 |
| `godot3d/scripts/ui/live_research.gd`, `game_ui.gd` | research view model, the host node | 11 |
| `godot3d/scripts/earthfront_3d.gd` | game, migrated by `tools/ui/integrate_game.py` | 12 |
| `tools/qa/*` | QA driver updated for 1920x1080 and the new UI | 13 |
| `docs/ascension/ui-deviations.md`, `godot3d/scripts/ui/README.md` | deviations log, module guide | 14 |

---

### Task 0: Safety net, project settings, fonts, sprites, import

**Files:**
- Create: `~/backups/ascension/godot3d-qa-2026-10-04.tar.gz` (outside the repo), `$WORK/baseline/` (extracted copy)
- Modify: `godot3d/project.godot` (viewport lines only)
- Create: `godot3d/assets/fonts/{IBMPlexMono-Medium,IBMPlexMono-Regular,IBMPlexSans-VF,Rajdhani-Bold}.ttf` plus `.import`, `godot3d/assets/fonts/FONT-LICENSES.md`, `godot3d/assets/ui/sprites/*` (15 PNG plus `.import`)

**Interfaces:**
- Consumes: nothing.
- Produces: `res://assets/fonts/Rajdhani-Bold.ttf`, `Rajdhani-SemiBold.ttf` (already present), `IBMPlexSans-VF.ttf`, `IBMPlexMono-Regular.ttf`, `IBMPlexMono-Medium.ttf`; `res://assets/ui/sprites/<name>.png`; a 1920x1080 viewport. `$WORK/baseline/` is the pristine copy that reviewers diff against.

- [ ] **Step 1: Back up and extract a baseline**

```bash
mkdir -p ~/backups/ascension
tar --exclude=godot3d/.godot -czf ~/backups/ascension/godot3d-qa-2026-10-04.tar.gz godot3d tools/qa
rm -rf "$WORK/baseline" && mkdir -p "$WORK/baseline" && tar -xzf ~/backups/ascension/godot3d-qa-2026-10-04.tar.gz -C "$WORK/baseline"
tar -tzf ~/backups/ascension/godot3d-qa-2026-10-04.tar.gz | grep -c "godot3d/scripts/earthfront_3d.gd$"
```

Expected: the last command prints `1`. The tarball is about 30 MB.

- [ ] **Step 2: Check the baseline matches what this plan was written against**

```bash
wc -l godot3d/scripts/earthfront_3d.gd          # expect: 3226
ls godot3d/tests godot3d/scripts/ui 2>&1 | head -2   # expect: "No such file or directory" for both
"$G" --version                                  # expect: 4.7.2.stable...
test -x target/release/godot-bridge && echo bridge-ok   # expect: bridge-ok (needed for Task 13 only)
python3 -c "import numpy, PIL; print('py-ok')"; google-chrome --version; node --version; command -v xvfb-run
```

Expected: `3226`, both `ls` errors, `4.7.2`, `bridge-ok`, `py-ok`, a Chrome version, a Node version and the `xvfb-run` path. If `earthfront_3d.gd` is not 3226 lines, stop: the migration in Task 12 will refuse to run on a drifted file, and the user should decide how to proceed.

- [ ] **Step 3: Change the viewport**

```bash
python3 - <<'PY'
p = "godot3d/project.godot"
s = open(p).read()
for old, new in [("window/size/viewport_width=1440", "window/size/viewport_width=1920"),
                 ("window/size/viewport_height=900", "window/size/viewport_height=1080")]:
    assert s.count(old) == 1, old
    s = s.replace(old, new)
for line in ["window/size/window_width_override=1280\n", "window/size/window_height_override=800\n"]:
    assert s.count(line) == 1, line
    s = s.replace(line, "")
open(p, "w").write(s)
PY
grep -n "viewport\|override\|stretch" godot3d/project.godot
```

Expected: `viewport_width=1920`, `viewport_height=1080`, `stretch/mode="canvas_items"`, and no `override` lines.

- [ ] **Step 4: Install fonts, licences and sprites**

```bash
inst godot3d/assets/fonts/FONT-LICENSES.md $(cd "$B" && ls godot3d/assets/fonts/IBMPlex* godot3d/assets/fonts/Rajdhani-Bold* godot3d/assets/ui/sprites/*)
ls godot3d/assets/fonts godot3d/assets/ui/sprites | head -50
```

Expected: the four new font files (each with a `.import`), `FONT-LICENSES.md`, and 30 sprite entries (15 PNG, 15 `.import`).

- [ ] **Step 5: Import the new assets**

```bash
timeout 600 "$G" --headless --path godot3d --import 2>&1 | tail -2
ls godot3d/.godot/imported | grep -c "IBMPlex\|Rajdhani-Bold"
```

Expected: no `ERROR` lines; the count is at least `4`. A warm project takes seconds; a cold one can take a few minutes. Always run this before the first test run after adding assets, because a test run on an un-imported project can hang.

---

### Task 1: Test runner, tokens, icons

**Files:**
- Create: `godot3d/tests/run_tests.gd`, `godot3d/tests/test_tokens.gd`, `godot3d/scripts/ui/tokens.gd`, `godot3d/scripts/ui/icons.gd`

**Interfaces:**
- Consumes: the fonts from Task 0.
- Produces:
  - `run_tests.gd`: runs every `tests/test_*.gd` (`func test_*(t)`); `t.ok(cond, msg)`, `t.eq(actual, expected, msg)` (type-strict), `t.near(actual, expected, eps := 0.5, msg)`; optional filter `-- "file.gd:"` or `-- "file.gd:test_name"`; exit code 1 on any failure, including a test script that does not compile.
  - `tokens.gd` (`T`): colour constants `BG0 BG1 BG2 RAISED HOVER ACTIVE LINE LINE_DIM CYAN CYAN_HI CYAN_DK TEXT TEXT_HI DIM FAINT GOOD WARN WARN_HI BAD BAD_HI VIOLET SHIELD GROUND BAR_BG KEY_BG PANEL_TOP PANEL_BOT GLASS SCRIM TOP_LIGHT GLOW`; `T.tone(name: String) -> Color` (words `cyan good warn bad violet dim shield hi`, anything else returns `TEXT`); `T.font(kind: String, weight := 0) -> Font` (kinds `"disp"` Rajdhani, `"body"` IBM Plex Sans, `"mono"` IBM Plex Mono); `T.ascent(f: Font, px: int) -> int`, `T.descent(f: Font, px: int) -> int`; `T.MONO_ADVANCE := 0.6`.
  - `icons.gd` (`Icons`): `Icons.has(name: String) -> bool`, `Icons.texture(name: String, px := 18, stroke := 1.75) -> Texture2D` (white on transparent; tint at draw time), `Icons.cached(name, px, stroke) -> Texture2D` (safe inside `_draw`), `Icons.logo(px := 26) -> Texture2D`. Never call `texture()` from `_draw()`.

- [ ] **Step 1: Install the runner and the tests**

```bash
inst godot3d/tests/run_tests.gd godot3d/tests/test_tokens.gd
```

- [ ] **Step 2: Run the tests; they must fail**

Run: `tests`
Expected: `FAIL test_tokens.gd: the test script did not compile ...` and `0 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/tokens.gd godot3d/scripts/ui/icons.gd
```

- [ ] **Step 4: Run the tests; they must pass**

Run: `tests`
Expected: `32 passed, 0 failed` (style-guide colours, the 92 percent panel gradient, tone words with fallbacks, three font families with real metrics, icon rasterising).

**Review Focus pins:** `test_tone_words` (unknown and empty tone fall back to body text); `test_icons_rasterise_and_unknown_icon_is_reported`.

---

### Task 2: Node factories and components

**Files:**
- Create: `godot3d/scripts/ui/kit.gd`, `godot3d/scripts/ui/components/{bar,chip,diamond,holo_button,holo_panel,icon,key_cap,tag,text_box}.gd`, `godot3d/tests/test_kit.gd`

**Interfaces:**
- Consumes: `T`, `Icons` (Task 1).
- Produces `kit.gd` (`K`), all static, geometry in mock pixels, `(x, y)` is the top-left of the CSS box relative to `parent`; every factory adds the node to `parent` and returns it:
  - `K.place(n: Control, x, y, w := -1.0, h := -1.0) -> Control` (rounds position; size only when `w` or `h` is given)
  - `K.text(parent, s: String, o := {}) -> Control` (`o`: `x y w h f px wt sp col up`; sizes itself to its content unless `w`/`h` given)
  - `K.panel(parent, x, y, w, h, kind := "panel", o := {}) -> Control`
  - `K.icon(parent, name, x, y, color, px := 18, stroke := 1.75)`, `K.tag(parent, s, x, y, color, bg := Color(0,0,0,0))`, `K.key(parent, s, x, y, o := {})`, `K.bar(parent, x, y, w, ratio, color := T.CYAN, h := 6.0)`
  - `K.chip(parent, x, y, icon_name, icon_color, parts: Array, o := {})` where each part is `{t: String, col?, f?, px?, wt?, sp?, up?}` (the key is `t`, not `text`); chip height 28
  - `K.button(parent, label, x, y, o := {})`, `K.diamond(parent, cx, cy, half, color := T.BAD, filled := true)`, `K.rule(parent, x, y, w, h, color) -> ColorRect`
  - `K.hit(parent, x, y, w, h, label := "") -> Button` (invisible; `.text` is the accessible label and is never drawn)
  - `K.sprite_texture(path) -> Texture2D` (null for empty or missing absolute paths; cached) and `K.sprite(parent, path, x, y, w, h, grey := false)`

- [ ] **Step 1: Install the test**

```bash
inst godot3d/tests/test_kit.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_kit.gd: the test script did not compile ...`, final line `32 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/kit.gd $(cd "$B" && ls godot3d/scripts/ui/components/{bar,chip,diamond,holo_button,holo_panel,icon,key_cap,tag,text_box}.gd)
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `63 passed, 0 failed`.

**Review Focus pins:** `test_text_sizes_itself_to_its_content_unless_told_otherwise` (empty text gives a non-negative size); `test_hit_is_an_invisible_button_that_keeps_its_label`; `test_sprite_texture_handles_missing_and_empty_paths`.

---

### Task 3: Mock render and diff harness

**Files:**
- Create: `tools/ui/{mockkit.py,render_mock.py,dump_boxes.py,box.py,flatten_dc.mjs,screens.json,diff_screens.py,compare.json,compare_build.json,compare_assault.json,compare_research.json,compare_title.json,compare_debrief.json,run_cap.sh,verify_all.sh}`, `docs/ascension/ui-mocks/{Main,BuildDeck,CoreAssault,Research,Title,Debrief,StyleGuide}.dc.html`, `docs/ascension/ui-mocks/blob-map.json`, `godot3d/scripts/gallery/{gallery.gd,capture.gd}`

**Interfaces:**
- Consumes: `assets/*.png` in the repo root (the mock sprite stand-ins; `blob-map.json` maps them), Chrome, Node, Python with `numpy` and `Pillow`, Xvfb.
- Produces:
  - `python3 tools/ui/render_mock.py <screen> <abs out.png>`: renders one mock to a 1920x1080 PNG with the bundled fonts. Screens: `main builddeck coreassault research title debrief`.
  - `tools/ui/run_cap.sh <screen> <ABS out.png>`: runs `scripts/gallery/capture.gd` under Xvfb at 1920x1080. `PROJ` overrides the project dir.
  - `python3 tools/ui/diff_screens.py <screen> <mock.png> <godot.png> <outdir> --spec tools/ui/<compare file>`: per-rectangle diff table (tolerance 24 per channel, each rectangle has its own `max`), writes `<outdir>/<screen>-side.png` and `-heat.png`; exit 1 if any rectangle is over its limit.
  - `tools/ui/verify_all.sh [screens...]`: render mock (cached) + capture + diff, for each screen; exit 1 on any failure. Output in `$UI_OUT`.
  - `tools/ui/box.py` and `dump_boxes.py`: dump the mock's element boxes (position, size, font, colours) from the `.dc.html`; use them when a rectangle will not line up.
  - Gallery screen names: `main builddeck coreassault research title debrief`, plus edge screens `builddeck_many builddeck_none builddeck_locked builddeck_short builddeck_no_queue builddeck_invalid title_empty title_1 title_12 title_long title_disabled debrief_edge`. `gallery.gd` loads each screen's scripts on demand, so a screen can be captured as soon as its own files exist.

This task has no Godot unit test; its checks are that the harness works on its own.

- [ ] **Step 1: Install the harness, mocks and gallery shell**

```bash
inst $(cd "$B" && ls tools/ui/* docs/ascension/ui-mocks/* | grep -v integrate_game) godot3d/scripts/gallery/gallery.gd godot3d/scripts/gallery/capture.gd
chmod +x tools/ui/*.sh tools/ui/*.py
ls tools/ui docs/ascension/ui-mocks
```

Expected: 15 files in `tools/ui` (`integrate_game.py` is not among them; Task 12 installs it) and 8 in `ui-mocks`.

- [ ] **Step 2: Render every mock with Chrome**

```bash
mkdir -p "$UI_OUT"
for s in main builddeck coreassault research title debrief; do python3 tools/ui/render_mock.py $s "$UI_OUT/mock_$s.png" >/dev/null; done
python3 -c "
from PIL import Image; import glob
for p in sorted(glob.glob('$UI_OUT/mock_*.png')): print(p.split('/')[-1], Image.open(p).size)"
```

Expected: six lines, each `(1920, 1080)`.

- [ ] **Step 3: Check the diff tool on identical images**

```bash
python3 tools/ui/diff_screens.py main "$UI_OUT/mock_main.png" "$UI_OUT/mock_main.png" "$UI_OUT/self" --spec tools/ui/compare.json; echo "exit $?"
```

Expected: eight rows (`topbar objectives power_tip wave_card alerts minimap selection deck`), each `0.00` and `ok`, then `exit 0`.

- [ ] **Step 4: Look at one mock**

Open `$UI_OUT/mock_main.png` with the Read tool. Expected: the Earthfront HUD over a flat olive ground (`#30332a`), no painted battlefield sprites.

`verify_all.sh` is not run yet: the screens it captures arrive in Tasks 4-9.

---

### Task 4: Earthfront HUD

**Files:**
- Create: `godot3d/scripts/ui/hud.gd`, `godot3d/scripts/ui/components/map_marks.gd`, `godot3d/scripts/gallery/fixtures.gd`, `godot3d/tests/test_hud.gd`

**Interfaces:**
- Consumes: `K`, `T`, `Icons`, components `key_cap`, `text_box` (Task 2); `tools/ui/verify_all.sh`, `gallery.gd` (Task 3).
- Produces `hud.gd` (`Hud extends Control`, full-rect, mouse-ignoring):
  - `signal action(name: String, arg: Variant)`
  - `apply(vm: Dictionary) -> void`: each section reads one slice of the view model and rebuilds only when that slice's `hash` changes (so a button is never replaced between press and release). A `null` or missing slice builds nothing. Section keys and their slices: `top_chips` (vm `brand`, `chips`, `wave`, presence of `speed`), `top_speed` (vm `speed`), `objectives`, `power_tip`, `wave_card`, `alerts`, `minimap`, `minimap_slot` (persistent), `minimap_marks` (vm `map_marks`: `marks`, `view`), `selection`, `deck_tabs` (vm `deck.tabs`), `deck_body` (vm `deck.body`).
  - `register_section(key: String, builder: Callable(layer: Control, slice: Variant), before := "")`, `register_body(kind: String, builder: Callable(layer: Control, body: Dictionary))` (a deck body is chosen by `vm.deck.body.kind`).
  - `blocks_point(point: Vector2) -> bool` (true over any STOP-filter child of a layer, so the 3D scene must ignore that point).
  - `map_slot: Control` property: the control that hosts the live minimap. Getter returns an override set by a layout that builds its own slot (core assault) while that node is still in the tree, else the Hud's own persistent slot.
  - `Fixtures.hud_main() -> Dictionary` (the Main mock's numbers).

- [ ] **Step 1: Install the tests and fixture**

```bash
inst godot3d/tests/test_hud.gd godot3d/scripts/gallery/fixtures.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_hud.gd: the test script did not compile ...`, final line `63 passed, 1 failed`.

- [ ] **Step 3: Install the HUD**

```bash
inst godot3d/scripts/ui/hud.gd godot3d/scripts/ui/components/map_marks.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `103 passed, 0 failed`.

- [ ] **Step 5: Diff against the mock**

```bash
tools/ui/verify_all.sh main; echo "exit $?"
```

Expected: eight rows, all `ok`, `exit 0`. Typical values: `topbar 6.57`, `objectives 8.02`, `wave_card 11.07` (limits 10 to 14; the 5 to 11 percent is Chrome versus Godot text anti-aliasing).

- [ ] **Step 6: Look at the side-by-side**

Open `$UI_OUT/diff_main/main-side.png` (mock left, Godot right) and `main-heat.png` with the Read tool. Acceptance: no unmasked region is visibly off (positions, sizes, colours, fonts). The minimap interior is masked.

**Review Focus pins** (all in `test_hud.gd`): `test_empty_view_model_builds_nothing`; `test_zero_selection_hides_panel`; `test_single_unit_and_empty_groups`; `test_long_lists_do_not_overflow`; `test_unchanged_slice_keeps_nodes` (a rebuild never replaces an unchanged section); `test_blocks_point_over_panels_only`; `test_clickable_cards_carry_their_name`.

---

### Task 5: Build deck and placement

**Files:**
- Create: `godot3d/scripts/ui/build_deck.gd`, `godot3d/scripts/ui/build_logic.gd`, `godot3d/scripts/ui/components/{hatch_fill,kbd}.gd`, `godot3d/scripts/gallery/fixtures_build.gd`, `godot3d/tests/test_build.gd`

**Interfaces:**
- Consumes: `Hud.register_section`, `Hud.register_body`, `Hud.action` (Task 4); `K`, `T`, `Icons`.
- Produces:
  - `BuildDeck.register(hud: Control) -> void`: adds sections `build_top`, `build_power`, `build_alerts`, `build_minimap` (placed under `minimap_slot`), `build_placement`, `build_world` and the deck body kind `"build"`.
  - `build_logic.gd` (`Logic`): `format_cost(material: int, work: int, kw: int) -> String`, `shortfall(cost: int, have: int) -> int`, `projection(generation: int, demand: int, added: int) -> Dictionary`.
  - `FixturesBuild.build_deck() -> Dictionary`, `FixturesBuild.cards() -> Array`, `FixturesBuild.edge(kind: String) -> Dictionary` (`many none locked short no_queue invalid`).
  - Every card is a Button named after its building; actions reach `hud.action`.

- [ ] **Step 1: Install tests and fixtures**

```bash
inst godot3d/tests/test_build.gd godot3d/scripts/gallery/fixtures_build.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_build.gd: ...`, final line `103 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/build_deck.gd godot3d/scripts/ui/build_logic.gd godot3d/scripts/ui/components/hatch_fill.gd godot3d/scripts/ui/components/kbd.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `160 passed, 0 failed`.

- [ ] **Step 5: Diff**

Run: `tools/ui/verify_all.sh builddeck; echo "exit $?"`
Expected: every row `ok`, `exit 0`. Then open `$UI_OUT/diff_builddeck/builddeck-side.png` and check it by eye.

- [ ] **Step 6: Capture the edge states and look at them**

```bash
for s in builddeck_many builddeck_none builddeck_locked builddeck_short builddeck_no_queue builddeck_invalid; do tools/ui/run_cap.sh $s "$UI_OUT/$s.png"; done
```

Expected: six `saved ... (1920, 1080)` lines and no `ERROR`. Open `builddeck_many.png` and `builddeck_invalid.png`: many cards scroll inside the grid; invalid placement shows its failing checks without overlapping the hints.

**Review Focus pins** (`test_build.gd`): `test_zero_cards`; `test_all_locked_cards_are_not_clickable`; `test_many_cards_scroll_inside_the_grid`; `test_scroll_position_survives_a_rebuild`; `test_placement_with_failing_checks`; `test_placement_checks_never_overlap_the_hints`; `test_empty_queue`.

---

### Task 6: Research screen

**Files:**
- Create: `godot3d/scripts/ui/research_screen.gd`, `godot3d/scripts/ui/research_layout.gd`, `godot3d/scripts/ui/components/research_parts.gd`, `godot3d/scripts/gallery/fixtures_research.gd`, `godot3d/tests/test_research.gd`

**Interfaces:**
- Consumes: `K`, `T`, `Icons`, components `tag`, `text_box` (Task 2).
- Produces:
  - `ResearchScreen extends Control` (full screen): `signal action(name, arg)`, `apply(vm: Dictionary)`, `blocks_point(point: Vector2) -> bool`, `focus_node(id: Variant)`, `pan() -> Vector2`. View model keys: `header {title, close_label, chips}`, `graph {nodes, selected, highlight, click_to_start, empty}`, `zoom {value, scale}`, `filters {search, groups}`, `eras {title, items}`, `detail {...}` or `detail {empty}`. A node is `{id: String, name, state: "available"|"active"|"implemented"|"blocked", tags, segments, labels, prereqs: Array of ids, footer?, dim?}`. Actions emitted: `select` (id), `research` (id), `close`, `zoom` (+1/-1), `zoom_to` (0..1), `search` (text), `filter` ({group, id, on}).
  - `ResearchLayout.layout(nodes: Array) -> Dictionary` (depth columns, stable rows; reports a missing prerequisite instead of failing; terminates on cycles), `node_pos`, `node_rect`, `world_size`, `edge`, `edge_points`.
  - `FixturesResearch.research() -> Dictionary` (the mock's 12 projects).
  - Every project card is a Button whose `.text` is the project name.

- [ ] **Step 1: Install tests and fixtures**

```bash
inst godot3d/tests/test_research.gd godot3d/scripts/gallery/fixtures_research.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_research.gd: ...`, final line `160 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/research_screen.gd godot3d/scripts/ui/research_layout.gd godot3d/scripts/ui/components/research_parts.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `297 passed, 0 failed`.

- [ ] **Step 5: Diff**

Run: `tools/ui/verify_all.sh research; echo "exit $?"`
Expected: every row `ok`, `exit 0`. Open `$UI_OUT/diff_research/research-side.png` and check by eye. Known, logged departures: the header title is about 2 px narrower, the page ground is one level lighter, no outer panel shadow.

**Review Focus pins** (`test_research.gd`): `test_option_without_prerequisites_is_a_plain_root`; `test_missing_prerequisite_id_still_builds`; `test_layout_missing_prerequisite_is_reported_not_fatal`; `test_layout_cycle_and_duplicates_do_not_hang`; `test_zero_options_shows_the_empty_state`; `test_forty_options_build_and_pan`; `test_layout_forty_nodes_never_overlap`; `test_very_long_name_is_truncated_but_keeps_its_button_text`; `test_optional_detail_blocks_are_omitted_when_absent`; `test_blocks_point`.

---

### Task 7: Title and campaign screen

**Files:**
- Create: `godot3d/scripts/ui/title_screen.gd`, `godot3d/scripts/ui/fx.gd`, `godot3d/scripts/ui/components/{menu_button,wordmark}.gd`, `godot3d/scripts/gallery/fixtures_title.gd`, `godot3d/tests/test_title.gd`

**Interfaces:**
- Consumes: `K`, `T`, `Icons`, `text_box` (Task 2).
- Produces:
  - `TitleScreen extends Control`: `signal action(name, arg)` (`deploy`, `quit`, others from the menu), `apply(vm: Dictionary)` (idempotent), `focus_first()`, `first_enabled() -> Control`, `menu_buttons() -> Array`, `layer(key: String) -> Control`, `blocks_point(point) -> bool`. View model: menu items with `label`, `enabled`, `action`; a chapters list (scrolls inside the panel past four); a featured card; a backdrop that can be hidden.
  - `fx.gd` (`Fx`): `radial(parent, rect, center, radii, stops) -> ColorRect`, `linear(parent, rect, stops, horizontal := false) -> TextureRect`, `limb(parent, rect) -> ColorRect`.
  - `FixturesTitle.title()`, `.edge(screen)` (`title_empty title_1 title_12 title_long title_disabled`), `.menu(overrides)`, `.chapters(n)`, `.featured()`, `.with_chapters(n)`, `.long_name()`.

- [ ] **Step 1: Install tests and fixtures**

```bash
inst godot3d/tests/test_title.gd godot3d/scripts/gallery/fixtures_title.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_title.gd: ...`, final line `297 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/title_screen.gd godot3d/scripts/ui/fx.gd godot3d/scripts/ui/components/menu_button.gd godot3d/scripts/ui/components/wordmark.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `484 passed, 0 failed`.

- [ ] **Step 5: Diff**

Run: `tools/ui/verify_all.sh title; echo "exit $?"`
Expected: every row `ok`, `exit 0`. Open `$UI_OUT/diff_title/title-side.png`. The mock's painted stand-in art is masked by the `ignore` rectangles in `compare_title.json`.

- [ ] **Step 6: Capture the edge states**

```bash
for s in title_empty title_1 title_12 title_long title_disabled; do tools/ui/run_cap.sh $s "$UI_OUT/$s.png"; done
```

Expected: five `saved` lines, no `ERROR`. Open `title_long.png` and `title_12.png`.

**Review Focus pins** (`test_title.gd`): `test_empty_view_model_builds_no_widgets`; `test_no_chapters`; `test_twelve_chapters_scroll_inside_panel`; `test_long_operation_name_stays_inside_card`; `test_all_menu_items_disabled`; `test_focus_skips_disabled`; `test_continue_disabled_without_save`; `test_reapply_is_idempotent`.

---

### Task 8: Victory and defeat debrief

**Files:**
- Create: `godot3d/scripts/ui/debrief.gd`, `godot3d/scripts/ui/components/line_chart.gd`, `godot3d/scripts/gallery/fixtures_debrief.gd`, `godot3d/tests/test_debrief.gd`

**Interfaces:**
- Consumes: `K`, `T`, components `holo_button`, `text_box` (Task 2).
- Produces:
  - `Debrief extends Control` (one column; the gallery shows victory and defeat side by side): `signal action(name, arg)` (`review`, `restart`), `apply(vm: Dictionary)`, `static place_in(col: Control, host_size: Vector2) -> void` (centres the column and scales it to fit the host).
  - View model blocks, each optional and dropped with its gap closed when absent: headline and operation, stat chips, `casualties {rows}`, `economy {series}` (line chart), `timeline {rows}` (defeat), advice, buttons.
  - `FixturesDebrief.victory()`, `FixturesDebrief.defeat()`.

- [ ] **Step 1: Install tests and fixtures**

```bash
inst godot3d/tests/test_debrief.gd godot3d/scripts/gallery/fixtures_debrief.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_debrief.gd: ...`, final line `484 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/debrief.gd godot3d/scripts/ui/components/line_chart.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `1089 passed, 0 failed`.

- [ ] **Step 5: Diff**

Run: `tools/ui/verify_all.sh debrief; echo "exit $?"`
Expected: every row `ok` (`d_title d_lede d_chips d_timeline d_chain d_advice d_buttons` and the others in `compare_debrief.json`), `exit 0`. Open `$UI_OUT/diff_debrief/debrief-side.png`.

- [ ] **Step 6: Capture the stress layout**

Run: `tools/ui/run_cap.sh debrief_edge "$UI_OUT/debrief_edge.png"`
Expected: `saved ... (1920, 1080)`. Open it: a very long title and operation name on the left, a 12-row defeat timeline scaled into the right half, nothing overlapping.

**Review Focus pins** (`test_debrief.gd`): `test_empty_view_model`; `test_nothing_to_show_omits_everything`; `test_no_chart_series`; `test_chart_without_casualties_closes_up`; `test_zero_casualties`; `test_defeat_empty_timeline`; `test_defeat_twelve_rows`; `test_long_names`; `test_header_texts_never_collide`; `test_same_view_model_keeps_nodes`.

---

### Task 9: Core-assault layout and world marks

**Files:**
- Create: `godot3d/scripts/ui/assault/{assault,bottom,chrome,order_button,util,vignette}.gd`, `godot3d/scripts/ui/world_marks.gd`, `godot3d/scripts/ui/components/{drop_shadow,grad_box,solid_mark}.gd`, `godot3d/scripts/gallery/fixtures_assault.gd`, `godot3d/tests/test_assault.gd`

**Interfaces:**
- Consumes: `Hud.register_section`, `register_body`, `action`, `map_slot` setter semantics (Task 4); `K`, `T`.
- Produces:
  - `Assault.register(hud: Control) -> void` (call once after creating the Hud, before the first `apply`). View-model keys it reads: `as_top {groups, right}`, `as_boss {name, hp_text, ratio, ticks?, phase?, retaliation?}`, `as_objective {cap, tag, title, body, steps?}`, `as_relays {cap?, items, note?, max?}`, `as_edge {title, lines, side, y, action?, arg?}`, `as_bottom {layers, slot_fill?, alert_count?, alerts}` (its builder assigns `hud.map_slot`), `as_selection {name, sub, tag, tag_tone, groups, stats, empty_title, hint}`, `as_vignette {strength}` or a bare number; deck body `{kind: "assault_orders", tabs, orders, hint}`. The main HUD sections must be left out of the view model in this state so they clear.
  - Actions through `hud.action`: `minimap_layer` (id), `select_group` (group id), `deck_tab` (tab id), and each order, alert, relay row and edge card's own `action`/`arg`.
  - `WorldMarks extends Control` (separate persistent control, mouse-ignoring, updated every frame, sits BELOW the Hud): `set_marks(marks: Array)` with screen-space marks of kinds `brackets ring hostile impact link arrow beam countdown badge callout`; `static bezier(p0, c1, c2, p1, steps := 96) -> PackedVector2Array`. Off-screen hostile and badge marks are dropped; off-screen callouts pin inside a 26 px inset with an edge arrow.
  - `FixturesAssault.hud() -> Dictionary`, `FixturesAssault.marks() -> Array`.

- [ ] **Step 1: Install tests and fixtures**

```bash
inst godot3d/tests/test_assault.gd godot3d/scripts/gallery/fixtures_assault.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL test_assault.gd: ...`, final line `1089 passed, 1 failed`.

- [ ] **Step 3: Install the code**

```bash
inst $(cd "$B" && ls godot3d/scripts/ui/assault/*.gd) godot3d/scripts/ui/world_marks.gd godot3d/scripts/ui/components/drop_shadow.gd godot3d/scripts/ui/components/grad_box.gd godot3d/scripts/ui/components/solid_mark.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `1204 passed, 0 failed`.

- [ ] **Step 5: Diff**

Run: `tools/ui/verify_all.sh coreassault; echo "exit $?"`
Expected: 17 rows (`top bar` through `whole screen`), every one `ok`, `exit 0`. Highest values: `emitter card 10.35`, `hq edge alert 10.13`. Open `$UI_OUT/diff_coreassault/coreassault-side.png`.

**Review Focus pins** (`test_assault.gd`): `test_empty_view_model_builds_nothing`; `test_core_hp_zero_and_full`; `test_boss_missing_optional_fields`; `test_relays_zero_of_zero_builds_no_panel`; `test_relays_five_items_overflow_line`; `test_empty_objective_steps_drop_checklist`; `test_zero_alerts`; `test_twelve_alerts_newest_four_plus_count`; `test_no_selection_shows_empty_state`; `test_null_selection_builds_nothing`; `test_top_bar_tolerates_empty`; `test_offscreen_hostile_dropped`; `test_callout_clamps_each_edge`; `test_marks_tolerate_missing_fields`; `test_panels_block_clicks_through`.

---

### Task 10: Live adapter, session log, live screens, assault view model

**Files:**
- Create: `godot3d/scripts/ui/{live_adapter,live_assault,session_log,live_screens}.gd`, `godot3d/tests/{stub_game,test_live_adapter,test_live_assault,test_live_screens}.gd`

**Interfaces:**
- Consumes: the real `Hud` + `BuildDeck` + `Assault` (Tasks 4, 5, 9), `TitleScreen` (Task 7), `Debrief` (Task 8); the tests drive them with a stub game.
- Produces:
  - `tests/stub_game.gd`: stands in for `earthfront_3d.gd` with the real member names (`bridge_money`, `bridge_power_generation`, `bridge_next_wave_ticks`, `bridge_research_options`, `selected_units`, `attack_move_armed`, `mouse`, `camera`, `calls`, ...). It records every handler call in `calls`.
  - `live_adapter.gd`: `LiveAdapter.new(game)`; `var tab: String` (`"build"`, `"units"`, `"orders"`); `var assault` (a `LiveAssault`); `hud_vm(now: float) -> Dictionary` (the assault view model when `assault_active()`, otherwise Main or Build per `tab`); `assault_active() -> bool` (`tab == "orders" and assault.engaged`); `on_action(name: String, arg: Variant)` (maps HUD actions to the game's `_on_command_button`, `_set_selection`, build arming, `jump_hq`, order `hq`); `push_notification(title: String, body: String, color: Color, now: float)`; `poll_ticker(text: String, now: float)`. A block the snapshot cannot fill is left out of the view model, never invented.
  - `live_assault.gd`: `LiveAssault.new(game)`; `var engaged: bool` (latched once the alien Core Node is within `ENGAGE_RANGE 9.0` of a unit or hurt); `core_node() -> Node3D`, `hq_node() -> Node3D`; `update(now: float)`; `vm(now, alerts: Array, tabs: Array, selection: Dictionary, attack_armed: bool) -> Dictionary` (keys `as_top as_boss as_objective as_relays as_edge as_bottom as_selection as_vignette` and `deck.body.kind = "assault_orders"`; `as_relays` omitted at zero relays; `as_edge` only within 12 s of an HQ hit); `marks(project: Callable, visible_rect: Rect2, behind: Callable) -> Array` (hostile marks on screen only, capped at 24).
  - `session_log.gd`: `SessionLog.new()`; `observe(g)` (samples every 5 s, capped at 720), `unit_added(kind, team, category)`, `unit_removed(kind, team, category)`, `static hq_ratio(g) -> float`; fields `samples produced lost wave_times relay_times relays_total`.
  - `live_screens.gd`: `static title_vm(deploy_enabled: bool, research_projects: int) -> Dictionary`, `static debrief_vm(g, log) -> Dictionary` (blocks whose data was not recorded are left out), `static clock(seconds: float) -> String`, `static thousands(n: int) -> String`.

- [ ] **Step 1: Install the stub and tests**

```bash
inst godot3d/tests/stub_game.gd godot3d/tests/test_live_adapter.gd godot3d/tests/test_live_assault.gd godot3d/tests/test_live_screens.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL` lines for `test_live_adapter.gd`, `test_live_assault.gd` and `test_live_screens.gd` (all "did not compile"), final line `1204 passed, 3 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/live_adapter.gd godot3d/scripts/ui/live_assault.gd godot3d/scripts/ui/session_log.gd godot3d/scripts/ui/live_screens.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `1401 passed, 0 failed`.

**Review Focus pins:**
- Missing data: `test_missing_data_hides_chips_instead_of_faking`; `test_numbers_and_missing_pieces` (no core, no HQ, no ammo); `test_relays_follow_the_counts` (zero relays); `test_debrief_with_no_samples_is_just_the_headline`; `test_session_log_never_grows_without_bound`.
- Selection: `test_no_selection_means_no_panel`; `test_single_unit_has_no_groups`; `test_group_selection_averages_and_groups`; `test_select_group_narrows_selection`; `test_selection_with_none_one_and_many_units`.
- Long and many: `test_alerts_expire_and_cap`; `test_marks_only_hostiles_on_screen_and_capped`.
- Assault engagement: `test_engages_when_the_core_is_hurt_or_a_unit_is_close_and_stays_engaged`; `test_layout_follows_the_orders_tab_only_once_engaged`; `test_hq_edge_alert_appears_on_damage_and_expires`; `test_the_assault_hud_draws_and_clears_the_main_layout`.

---

### Task 11: Research view model and the `game_ui` host

**Files:**
- Create: `godot3d/scripts/ui/live_research.gd`, `godot3d/scripts/ui/game_ui.gd`, `godot3d/tests/test_live_research.gd`, `godot3d/tests/test_game_ui.gd`

**Interfaces:**
- Consumes: everything from Tasks 4 to 10.
- Produces:
  - `live_research.gd`: `LiveResearch.new()`; state `selected: String`, `scale: float` (0.5 to 1.5), `search: String`, `off: Dictionary`; `handle(name: String, arg: Variant) -> Dictionary` (returns `{"research": int}` to start a project, `{"close": true}` to close, else `{}`); `vm(g) -> Dictionary` (the research screen's view model from `g.bridge_research_options`, `bridge_active_research_*`, `bridge_era`); `static node_state(option, active_id) -> String`, `state_tag(state)`, `branch_name(option)`, `card_branch(option)`, `prereq_ids(option, options) -> Array`, `chain(id, options) -> Array`. Card tags use the shortened `CARD_BRANCHES` so the one long branch name fits beside the state tag.
  - `game_ui.gd` (`GameUI extends Node`), the only object `earthfront_3d.gd` talks to. The game adds it to its tree and then calls `setup(game)`. Members: `layer: CanvasLayer`, `hud`, `adapter`, `session_log`, `title`, `scrim`, `marks`, `research` (the Science modal; the game's `science_overlay` is this node), `live_research`, `selection_box: Panel`, `minimap_view`. Methods: `process(delta: float)` (call every frame; rebuilds the HUD view model at most every `VM_INTERVAL 0.1` s and never while the left button is down over a HUD surface), `blocks_point(point: Vector2) -> bool`, `notify(heading, body, color)`, `set_tab(name: String)` (`"build"`, `"units"`, `"orders"`; anything else is ignored), `research_open() -> bool`, `toggle_research()`, `begin_operation()` (title fades out in 0.32 s, HUD shows), `show_debrief()` (scrim plus debrief; `review` removes the scrim, `restart` calls `g._restart_mission()`), `minimap_world_rect() -> Rect2`.
  - What `game_ui` needs from the game (the migration in Task 12 provides the new ones): `mouse_position`, `minimap_world_rect`, `view_ground_rect`, `focus_camera`, `era_name`, `build_cursor_valid`, `_human_count`, `_has_selected_combat_unit`, `_on_command_button`, `_set_selection`, `_write_bridge_research`, `_deploy_mission`, `_restart_mission`, `camera`, `objective_label`, `bridge_*`.

- [ ] **Step 1: Install the tests**

```bash
inst godot3d/tests/test_live_research.gd godot3d/tests/test_game_ui.gd
```

- [ ] **Step 2: Run; must fail**

Run: `tests`
Expected: `FAIL` lines for `test_live_research.gd` and `test_game_ui.gd`, final line `1401 passed, 2 failed`.

- [ ] **Step 3: Install the code**

```bash
inst godot3d/scripts/ui/live_research.gd godot3d/scripts/ui/game_ui.gd
```

- [ ] **Step 4: Run; must pass**

Run: `tests`
Expected: `1491 passed, 0 failed`. The run ends with harmless "leaked ObjectDB" or "resources still in use" warnings on stderr; they are filtered out by `tests`.

- [ ] **Step 5: Diff all six screens together**

Run: `tools/ui/verify_all.sh | grep -c " ok$"; echo "exit ${PIPESTATUS[0]}"`
Expected: `77` and `exit 0` (77 rectangle rows across the six screens, none `FAIL`). Nothing in this task changes pixels; this is the regression check that the whole set still matches after all files are present.

**Review Focus pins:**
- Missing data: `test_no_options_means_an_empty_graph_not_an_error` and `test_states_and_prereqs_from_live_options` (an option with no prerequisites is a root; an unknown prerequisite name is dropped).
- Long text: `test_card_tags_fit_beside_the_state_tag_for_every_branch`.
- Click lost to a rebuild: `test_vm_is_throttled_and_skipped_during_a_hud_click` (no rebuild while the left button is down over the HUD; at most one per 0.1 s).
- Fall-through: `test_research_modal_opens_blocks_and_starts_a_project`; `test_research_modal_selecting_a_blocked_project_starts_nothing`; `test_debrief_blocks_input_and_both_buttons_work`; `test_title_first_then_hud_after_deploy`.
- Minimap handoff: `test_minimap_is_mounted_in_the_map_slot_and_follows_it`; `test_the_minimap_moves_into_the_assault_slot_and_back`.

---

### Task 12: Wire the UI into the game

**Files:**
- Create: `tools/ui/integrate_game.py`
- Modify: `godot3d/scripts/earthfront_3d.gd` (3226 lines to 2571 lines)

**Interfaces:**
- Consumes: `GameUI` (Task 11) and its requirements.
- Produces, on the game node: `var ui: Node` (the `GameUI`), `var selection_box: Control` (= `ui.selection_box`), `var build_cursor_is_valid := false`, `science_overlay = ui.research`; `mouse_position() -> Vector2`, `minimap_world_rect() -> Rect2`, `view_ground_rect() -> Rect2` (bounding rect of the four screen corners on the ground; `Rect2()` if any corner misses), `focus_camera(position: Vector3, zoom: float)` (cinematic 0.8 s), `era_name() -> String`, `build_cursor_valid() -> bool`. `_build_ui()` creates and sets up the `GameUI`, plus two hidden orphan labels `objective_label` and `tutorial_label` that other code still writes to. `_set_command_tab(name)` calls `ui.set_tab(name.to_lower())`; `_toggle_science_panel()` calls `ui.toggle_research()`; `_show_notification` calls `ui.notify`; `_show_end_screen` keeps its guard and tone, then `ui.show_debrief()`; `_deploy_mission()` takes no argument and calls `ui.begin_operation()`; `_process` calls `ui.process(delta)`; hover and ghost code uses `ui.blocks_point(pointer)`; `_sync_bridge_entities` feeds `ui.session_log.unit_added/unit_removed`.
- Removed: the old hand-built HUD (`_create_ui_theme`, `_build_science_panel`, `_refresh_science_panel`, `_refresh_command_availability`, `_build_briefing`, `_build_minimap`, `_panel_style`, `_progress_style`, `_living_team`, `_update_portrait` and their variables). This is the "delete the old UI" step of the spec.

**This is the only task that edits an existing game file.** Revert with `cp "$WORK/baseline/godot3d/scripts/earthfront_3d.gd" godot3d/scripts/earthfront_3d.gd`.

- [ ] **Step 1: Install the migration script and run it**

```bash
inst tools/ui/integrate_game.py
python3 tools/ui/integrate_game.py godot3d/scripts/earthfront_3d.gd
```

Expected: `ok: 3226 -> 2571 lines`. If it fails with `anchor found N times (want 1)`, the game file has drifted from the baseline; restore it from `$WORK/baseline` and stop, because the script edits nothing unless every anchor is present exactly once.

- [ ] **Step 2: Parse-check the game script**

```bash
timeout 120 "$G" --headless --path godot3d --check-only --script res://scripts/earthfront_3d.gd 2>&1 | tail -3; echo "exit ${PIPESTATUS[0]}"
```

Expected: the Godot banner line only and `exit 0`; no `SCRIPT ERROR` or `Parse Error`.

- [ ] **Step 3: Check that no old-UI symbol is left**

```bash
grep -nE "_build_science_panel|_build_briefing|_build_minimap|_create_ui_theme|_panel_style|unit_portrait|command_buttons|science_list" godot3d/scripts/earthfront_3d.gd; echo "grep exit $?"
```

Expected: no matches and `grep exit 1`.

- [ ] **Step 4: Re-run the full test suite**

Run: `tests`
Expected: `1491 passed, 0 failed` (the game file has no unit tests; this confirms nothing else moved).

- [ ] **Step 5: Confirm what changed in the game file**

```bash
diff <(sed 's/[[:space:]]*$//' "$WORK/baseline/godot3d/scripts/earthfront_3d.gd") <(sed 's/[[:space:]]*$//' godot3d/scripts/earthfront_3d.gd) | grep -c '^[<>]'
```

Expected: `809` (732 lines removed, 77 added). The live pass in Task 13 is what proves the game still runs.

---

### Task 13: QA tools and the live pass

**Files:**
- Modify (replace): `tools/qa/ui_driver.gd`, `tools/qa/ui_client.py`, `tools/qa/campaign_player.py`, `tools/qa/render_probe.gd`
- Create: `tools/qa/hud_states.py`
- Unchanged: `tools/qa/launch_ui.py`, `tools/qa/check_restart.py`

**Interfaces:**
- Consumes: the migrated game (Task 12), `target/release/godot-bridge`, Xvfb on display `:93`.
- Produces:
  - `ui_driver.gd`: viewport 1920x1080; a button's reported rect is intersected with its clip rects and skipped when fully clipped; entities and tiles carry `free` (inside a 12 px inset and not over the UI); a presentation-only `ui_state` event (`tab`, `engage`, `debrief`; it never touches the simulation).
  - `ui_client.py`: `UI(dir)`; `button(text: str, soft: bool = False)` (case-insensitive, clicks the centre of the reported rect, `soft` returns silently when absent); `ui_state(**kw)`; `observe()`, `snapshot()`, `click(x, y, button=1, double=False, shift=False)`, `key(name, ctrl=False)`, `capture(name)`.
  - `campaign_player.py <qa dir>`: plays the campaign through viewport input only (first the control checks: shift-select, double-click, control groups, research modal, terrain picking; then builds, research, harvester replacement, army and core assault) and appends a line per action to `<qa dir>/journey.jsonl`.
  - `hud_states.py <qa dir>`: captures `state-title`, `state-build`, `state-orders-selection`, `state-research`, `state-assault`, `state-debrief` PNGs into the QA dir.

- [ ] **Step 1: Install and syntax-check**

```bash
inst tools/qa/ui_driver.gd tools/qa/ui_client.py tools/qa/campaign_player.py tools/qa/render_probe.gd tools/qa/hud_states.py
python3 -m py_compile tools/qa/ui_client.py tools/qa/campaign_player.py tools/qa/hud_states.py && echo py-ok
```

Expected: `py-ok`. (The originals are in the Task 0 tarball.)

- [ ] **Step 2: Define a stop helper and capture every HUD state live**

```bash
qa_stop() { python3 - "$1" <<'PY'
import json, os, signal, sys
for pid in json.load(open(sys.argv[1] + "/pids.json")):
    try: os.killpg(pid, signal.SIGTERM)
    except Exception as e: print("kill", pid, e)
PY
}
QA=$WORK/qa-states; rm -rf "$QA"
python3 tools/qa/launch_ui.py "$QA" --software
for i in $(seq 1 60); do [ -f "$QA/observation.json" ] && break; sleep 2; done
python3 tools/qa/hud_states.py "$QA"; echo "hud_states exit $?"
grep -E "SCRIPT ERROR|Parse Error" "$QA/godot.log" | sort | uniq -c
qa_stop "$QA"
```

Expected: `captured ['state-assault.png', 'state-build.png', 'state-debrief.png', 'state-orders-selection.png', 'state-research.png', 'state-title.png']`, `hud_states exit 0`, and no `SCRIPT ERROR` lines. Never `pkill -f` a pattern that appears in your own command line; kill by the PIDs in `pids.json` as `qa_stop` does.

- [ ] **Step 3: Look at the six captures**

Open each `$QA/state-*.png` with the Read tool and check against the mocks:
- `state-title`: the title and campaign panel over the 3D scene, `DEPLOY FORCES` button.
- `state-build`: Earthfront HUD with the Build deck (cards for the unlocked buildings), top bar chips with live numbers.
- `state-orders-selection`: selection panel for the double-click-selected infantry group, Orders deck.
- `state-research`: the research graph modal over the scene, projects from the live snapshot. An empty band at the top where the era-gate block would be is a logged deviation, not a bug.
- `state-assault`: the core-assault layout (boss bar, objective, relays, minimap in the bottom-left panel, `ATTACK-MOVE / FOCUS / HQ` orders).
- `state-debrief`: the debrief over a scrim.

- [ ] **Step 4: Bounded fresh campaign (first four minutes)**

```bash
QA=$WORK/qa-campaign; rm -rf "$QA"
python3 tools/qa/launch_ui.py "$QA" --software
for i in $(seq 1 60); do [ -f "$QA/observation.json" ] && break; sleep 2; done
timeout 240 python3 tools/qa/campaign_player.py "$QA" > "$QA/player.log" 2>&1; echo "exit $? (124 means it was still playing at the cutoff, which is expected)"
head -2 "$QA/journey.jsonl" | cut -c1-120
tail -1 "$QA/journey.jsonl" | cut -c1-120
grep -E "SCRIPT ERROR|Parse Error" "$QA/godot.log" | sort | uniq -c
qa_stop "$QA"
```

Expected: the first journey line is `controls passed: shift, double-click, group, modal, terrain picking` (this proves box-select, control groups, the research modal and terrain picking work at 1920x1080), followed by `build REACTOR`, `build REFINERY`, ...; the last line has a `tick` above 5000 and `research` of 3 or more; no `SCRIPT ERROR` lines.

- [ ] **Step 5: Full campaign (the spec's "a fresh campaign must still complete")**

The player has a 1,400 s budget. Run it in the background and read the result when it ends:

```bash
QA=$WORK/qa-full; rm -rf "$QA"
python3 tools/qa/launch_ui.py "$QA" --software
for i in $(seq 1 60); do [ -f "$QA/observation.json" ] && break; sleep 2; done
timeout 1560 python3 tools/qa/campaign_player.py "$QA" > "$QA/player.log" 2>&1; echo "exit $?"
tail -3 "$QA/journey.jsonl" | cut -c1-260
grep -E "SCRIPT ERROR|Parse Error" "$QA/godot.log" | sort | uniq -c
qa_stop "$QA"
```

Expected: no `SCRIPT ERROR` lines, journey ticks keep rising, and the run either ends with `"winner"` other than `-1` in the last journey line (a recorded win or loss) or reaches the 1,400 s budget with the game still responding. Report the actual last line to the user either way. A crash, a frozen tick or a QA driver timeout is a failure to investigate before this task is called done.

- [ ] **Step 6: Restart protocol regression (unchanged tool)**

Run: `python3 tools/qa/check_restart.py; echo "exit $?"`
Expected: `exit 0`. It exercises the process-level restart through the bridge and does not touch the UI; it confirms the bridge contract is untouched.

**Review Focus pins:** the `controls passed` line (box-select, double-click, control groups, research modal and terrain picking at 1920x1080); `state-orders-selection` (double-click on a `free` unit selects its group); `ui_state(debrief=True)` shows the scrim and buttons that the driver can click.

---

### Task 14: Documentation, deviations log and final sweep

**Files:**
- Create: `docs/ascension/ui-deviations.md`, `godot3d/scripts/ui/README.md`

**Interfaces:**
- Consumes: the finished UI.
- Produces: the written record a reviewer reads to tell a deliberate choice from a bug.

- [ ] **Step 1: Install the documents**

```bash
inst docs/ascension/ui-deviations.md godot3d/scripts/ui/README.md
```

- [ ] **Step 2: Add anything new**

If any step above needed a fix to an installed file, or a screen showed a flaw you did not copy, add a line to the matching section of `docs/ascension/ui-deviations.md` (mock flaw, blocked block, or cosmetic item). Do not leave a known difference undocumented.

- [ ] **Step 3: Check the no-dash rule**

```bash
LC_ALL=C.UTF-8 grep -rnP '[\x{2013}\x{2014}]' godot3d/scripts/ui godot3d/scripts/gallery godot3d/tests docs/ascension tools/ui godot3d/assets/fonts/FONT-LICENSES.md | grep -v "live_adapter.gd:97:\|test_live_adapter.gd:\|integrate_game.py:"
```

Expected: no output. (The excluded lines are the game's own notification text that the adapter splits and its test asserts; they never reach the screen.)

- [ ] **Step 4: Final full verification**

```bash
tests
tools/ui/verify_all.sh | grep -cE " ok$"; echo "verify exit ${PIPESTATUS[0]}"
```

Expected: `1491 passed, 0 failed`; `77` and `verify exit 0`.

- [ ] **Step 5: Confirm only the intended files changed**

```bash
diff -rq "$WORK/baseline/godot3d" godot3d | grep -v "\.uid\|/\.godot" | sed "s|$WORK/baseline/||" | sort
diff -rq "$WORK/baseline/tools/qa" tools/qa | grep -v "__pycache__"
git status --short | grep -v "^??" | head -20
```

Expected: the first command lists `Files godot3d/project.godot ... differ`, `Files godot3d/scripts/earthfront_3d.gd ... differ`, `Only in godot3d: tests`, `Only in godot3d/scripts: gallery`, `Only in godot3d/scripts: ui`, `Only in godot3d/assets/ui: sprites`, and the new font files (`FONT-LICENSES.md` and four `.ttf` with their `.import`), and nothing else; the second lists the four replaced QA files plus `Only in tools/qa: hud_states.py`; the third shows only the repo's pre-existing modified files (this work adds nothing tracked; `godot3d/`, `tools/ui/` and the new docs are untracked).

- [ ] **Step 6: Report, do not commit**

Tell the user: what was built, the verification numbers (1491 tests, 77 diff rows ok, the live pass result including the last journey line), the deviations log path, and that nothing was committed. Offer to commit if they want (with the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer).

---

## Spec coverage

| Spec section | Where it is implemented and checked |
|---|---|
| 1 Goal, screens, fidelity | Tasks 4-9 (one screen each, diffed against its mock); out-of-scope list in Global Constraints |
| 2 Findings (untracked `godot3d/`, 1440x900, QA text lookup, one font) | Task 0 (backup, viewport, fonts), Task 13 (QA driver), `.text` rule in Global Constraints |
| 3 Approach A | Tasks 1-2 and every screen task |
| 4 Architecture (tokens, components, screens, view models, `earthfront_3d.gd` keeps logic) | Tasks 1, 2, 4-9; live layer Tasks 10-11; Task 12 keeps the game logic and swaps only UI code |
| 5 Screen mapping and data gaps | Tasks 10 and 11 (adapter, session log, live research, live screens) with the missing-data tests; gaps recorded in Task 14 |
| 6 Design details (tokens, geometry, tab rules) | Task 1 `test_tokens.gd`; geometry by the per-rectangle diffs in Tasks 4-9; Logistics hidden per the spec |
| 7 Verification (gallery, Chrome renders, diff, live pass, no regressions) | Task 3 (harness), Tasks 4-9 (diff), Task 13 (live pass), Task 12 and 14 (parse check, full suite; Rust untouched) |
| 8 Safety and sequencing | Task 0 (tarball, baseline), task order follows the spec build order, no commits |
| 9 Risks (font metrics, viewport change, research positions, large game file) | Calibrated per-rectangle limits (Tasks 4-9), Task 0 and 13 for the viewport, Task 6 layout tests, Task 12 anchored migration |

## Execution handoff note

The tasks share interfaces (the Hud section engine, the view-model keys and the game host), and a shipped integration mistake in Task 12 or 13 costs a broken game rather than a wrong pixel, so independent review between tasks is worth its cost here.
