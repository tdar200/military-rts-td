# Godot UI: deviations from the design set

Implements `docs/ascension/ui-mocks/*.dc.html` in `godot3d/scripts/ui/`. The bar is "UI chrome pixel-matched at 1920x1080,
battlefield stays 3D". This file lists every place the build knowingly differs from the mocks or the approved spec, so a
reviewer can tell a deliberate choice from a bug.

## 1. Measured match

`tools/ui/verify_all.sh` renders each mock with headless Chrome, captures the Godot gallery screen and diffs them per
rectangle. A pixel is bad when any channel differs by more than 24. Each rectangle's limit is its achieved value plus 3
points (limits live in `tools/ui/compare*.json`). Text-heavy rectangles sit at 5 to 11 percent because Chrome draws
LCD-fringed glyphs and Godot draws greyscale; a one-pixel shift search found the text correctly positioned. The painted
sprite battlefield in the mocks is a stand-in and is masked out.

## 2. Spec deltas (the approved spec stays as written; these were decided while building)

- Components live in `scripts/ui/components/*.gd` plus the factory file `scripts/ui/kit.gd`, not one `components.gd`.
- Icons are inline SVG path data in `scripts/ui/icons.gd`, rasterised on demand. There is no `assets/ui/icons/` folder.
- The gallery is `scripts/gallery/capture.gd` run with `--script`, not a `ui_gallery.tscn` scene.
- The panel gradient top is rgb(18,32,46), as every mock writes it. The spec's `#122030` was a rounding.
- The deck tabs are Build, Units, Orders, Science. Science opens the research modal. Logistics is hidden because the
  bridge exposes no supply routes (the spec says to hide it rather than fake it).
- The viewport is 1920x1080 with the window-size overrides removed.

## 3. Mock flaws and deliberate departures

Core assault:
- The minimap layer caption's third label ("Planetary") overflows into the alert column in the mock. Labels that do not
  fit 216 px are dropped.
- The mock's panel drop shadow is drawn by a local `DropShadow` child, not by changing `HoloPanel`.
- Ground rings under the squad are a `ring` mark kind because the mock draws them.
- The vignette is a `z_index = 50` section because a rebuilt Hud layer is re-appended at the end of the child order.
- World marks are a separate persistent control updated every frame, not a Hud section.
- Off-screen hostile and badge marks are dropped; off-screen callouts are pinned inside a 26 px inset with an edge arrow.
- The emitter card title wraps to "CORE / EMITTER" because Chrome flex-shrinks it. This is reproduced on purpose.

Research:
- The header title renders about 2 px narrower than Chrome's.
- The page ground is one level lighter than the mock's flat colour.
- There is no outer panel shadow.
- The mouse wheel emits a `zoom` action.

## 4. Mock blocks the live game cannot fill (omitted, never invented)

- Wave composition line ("2 artillery, 4 heavy escorts, 8 raiders"): the snapshot has doctrine and expedition size only.
- Core assault boss phase and retaliation timer; objective checklist steps in the assault state.
- Research era-gate criteria, theory and prototype split, retrofit block and path steps.
- Speed group (the bridge has no speed or pause command) and the Stop, Hold and Resupply orders.
- Debrief blocks whose values the client cannot record (it records kills, material samples, waves and relays itself).

## 5. Known cosmetic items

- The research screen has an empty band at the top where the era-gate block would sit.
- "Attack-move" wraps to two lines in the narrow order tile; the mock wraps it too.
- Godot logs an invalid-UID warning for a GLB in `_place_scene`. It predates this work.
- The minimap shows the whole map letterboxed in its slot.
- Hostile diamonds appear only while alien units are on screen (covered by `test_live_assault.gd`).
