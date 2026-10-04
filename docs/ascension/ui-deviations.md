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
- The minimap layer tabs (`assault/bottom.gd` `_layer_tabs`) drop a label because it overflows the 216 px panel
  (the third label, "Planetary", overflows into the alert column in the mock). The live game passes `layers: []`, so
  the live minimap shows no layer tabs at all.
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

Minimap (core assault):
- The empty interior of the minimap card is by design. The interior is masked in the diff, and the live game mounts the
  real 3D minimap there; the gallery only draws the frame.

Debrief:
- The overflow on the `debrief_edge` capture comes from the Godot gallery capture: the left column of that case
  (from `gallery.gd:44`) is never passed through `Debrief.place_in`, while the live path does (`game_ui.gd:227`). The review finding was ruled a gallery-only artifact, not a live UI bug.
  The cost of that ruling: `place_in` has no scale floor, so very long content shrinks the column rather than clipping.

Title:
- The tagline is shortened to "Hold the Earthfront. Break the Core Node." because the longer mock line ran under the
  Campaign panel at 1920 wide. It is set in `live_screens.gd`; the bundle copy keeps the longer line, so this is a
  listed divergence (section 6).

## 4. Mock blocks the live game cannot fill (omitted, never invented)

- Wave composition line ("2 artillery, 4 heavy escorts, 8 raiders"): the snapshot has doctrine and expedition size only.
- Core assault boss phase and retaliation timer; objective checklist steps in the assault state.
- Research era-gate criteria, theory and prototype split, retrofit block and path steps.
- Speed group (the bridge has no speed or pause command) and the Stop, Hold and Resupply orders.
- Debrief blocks whose values the client cannot record (it records kills, material samples, waves and relays itself).
- Title menu: Continue campaign, Skirmish sandbox, Research archive and Settings are disabled (there is no saved
  campaign, sandbox, archive screen or settings screen behind them). "New operation" is the primary item, where the mock
  makes "Continue campaign" primary, and the featured card's primary button reads "Deploy forces" instead of "Continue
  operation". The mock's per-item hints ("Dawnshield 07:12", "Seed 2026", "Legacy map", "Remap keys", "Alt F4") are
  dropped; the only hint is the Research archive project count ("N projects"), shown when the technology total is known.
- Debrief buttons: the live column has "Review battlefield" (primary) and "Redeploy". The mock has "Next horizon",
  "Replay" and "Restart" on victory, and "Retry from checkpoint", "Review replay" and "Restart" on defeat. The client has
  no next chapter, checkpoint or replay to offer.

### Gameplay boards, R7 (decided 2026-10-04)
- Veteran chevrons: DECIDED TO BUILD (Task 12). Source: per-unit `rank` (0..3) already in the sim.
- Combat preview: DECIDED TO BUILD (Task 12) as damage-type multiplier and rank bonus only. Hit chance and
  "across the river -25%" are NOT shown (no such mechanic).
- Harness: when adding chrome rects to `tools/ui/compare_gpNN.json`, append them AFTER the `"mask": true` rect (rects are
  applied in order; an earlier chrome rect would be masked by the later full-board mask).

### Gameplay board 1 (Main, gp01), decided 2026-10-04 (Task 12A)
Built from live data: yield pill, territory card, tile inspector, colony ledger, army orders, alert chips (idle crews,
next alert), deposit pins, minimap lens keys with their overlays. Not built, because the snapshot or the bridge has nothing
behind them:
- Per-minute income deltas ("+38 M", "+22/m"): the snapshot has no income field. Only "+168 kW" (total generation) shows.
- "+4 ore haul" pill, the "+4 haul" tag on the inspector and the "Ore +4" / "Harvesting" pin text: no haul or worker
  data exists. Pins read "Ore 1,800 left" or "Ore, unclaimed" from the deposit and refinery data alone.
- Inspector "Movement 1.0x, shore sand 0.8x" becomes "Foot N%, vehicles N%" (the ground table has no neighbour
  breakdown). "Refinery +20% output" becomes the real bonus text, shown only when a refinery is in reach.
- Ledger "Supply 72%" becomes "Crew N / cap" (supply is the crew figure the snapshot carries); no worker or per-site
  production extras.
- "Open lab L" button: there is no bridge command that opens the lab from the colony panel, so no button is drawn. A
  Button with no command behind it is never built.
- "Select army" and "Idle crews N" are Buttons backed by new adapter actions (select_army, select_idle). The Ctrl A key
  cap is shown because the game now binds Ctrl+A; the "." key on the idle chip is bound too.
- Deposit pins are Buttons that centre the camera (focus_deposit). Only the first pin is compared by the harness: the
  mock's second pin sits over a deposit the fixture does not have.
- Excluded from the pixel gate: the minimap terrain image (an ignore rect; the 3D view is not a UI section), the tile
  inspector thumbnail (a rendered terrain swatch), the alert chip's "Next alert / Space" cap and the army column's third
  button slot (no counterpart, see above).
- Harness limits are achieved percent rounded to 0.1 plus 3, as for the original six screens. idle_chip (17.13) and
  tile_inspector_title (15.99) are high because of mono text anti-aliasing on short strings.

## 5. Known cosmetic items

- The research screen has an empty band at the top where the era-gate block would sit.
- "Attack-move" wraps to two lines in the narrow order tile; the mock wraps it too.
- Godot logs an invalid-UID warning for a GLB in `_place_scene`. It predates this work.
- The minimap shows the whole map letterboxed in its slot.
- Hostile diamonds appear only while alien units are on screen (covered by `test_live_assault.gd`).

## 6. Installed files that differ from the bundle (deliberate, not drift)

Every other installed file is byte-identical to the bundle (checked with `cmp` for all 136 bundle files against their
repo paths). The files below diverge on purpose; each change was found while wiring the live game or in the whole-branch
review, and is covered by a test or a one-off check. `docs/ascension/ui-deviations.md` itself also differs from its
bundle copy, because this file is where the divergences are recorded.

- `godot3d/scripts/ui/research_screen.gd`
  - Focus and caret restore (`_rebuild`, `_first_line_edit`). The filter rail, including the search `LineEdit`, is
    rebuilt on every keystroke because the `filters` slice hash includes the search text, which freed the focused field
    after one character. The rebuild now restores focus and caret on the new `LineEdit`.
  - Lambda connects. `_emit.bind("search")` appended the name, so the handler received `(text, "search")` and the search
    never reached the view model. `edit.text_changed` now calls `_emit("search", text)`. The zoom wiring
    (`track.changed`, formerly `_emit.bind("zoom_to")`) had the same bind-order bug and now calls `_emit("zoom_to", value)`.
  - The headless runner cannot assert real focus (the scene is not in a live tree during `_initialize`), so focus was
    verified with a one-off SceneTree script.
- `godot3d/scripts/ui/game_ui.gd`
  - Click guard. In `process`, the Science modal refresh (every 0.1 s) skips while the left button is down, as the HUD
    path does, so a card or the Start research button is not replaced between press and release.
  - Scrim guard. `toggle_research()` returns when a debrief scrim is up and the modal is closed, because pressing Y
    otherwise opened the modal beneath the scrim, invisible, swallowing keys. Closing an open modal still works.
  - Zoom drag. `_on_research_action` skips `research.apply(...)` for `zoom_to` while the left button is down (the track
    redraws itself, and the periodic refresh applies the scale after release). `live_research.handle` still runs, so
    the scale updates.
- `godot3d/scripts/ui/live_adapter.gd`
  - Freed selection. `_queue()` read `g.selected` into a `Node3D` variable, which raises "Trying to assign invalid
    previously freed instance" when the selected unit or building was freed (the game never clears `selected` or
    `selected_units` when a bridge entity disappears). The variable is untyped; the `is_instance_valid` check that
    follows handles it. All other readers of `g.selected` and `g.selected_units` in `scripts/ui` already use
    `is_instance_valid` before touching the node.
- `godot3d/scripts/ui/live_screens.gd`
  - `UNIT_ROWS` gains `["Capital", "Capital units"]` (capital units are trainable with X and recorded by `session_log`),
    so they appear in the debrief casualty table.
  - The title tagline is "Hold the Earthfront. Break the Core Node." (section 3). The bundle copy has the longer mock line.
- `godot3d/scripts/ui/README.md`
  - The Commands section replaces the racing `launch_ui.py <dir> --software && hud_states.py <dir>` one-liner with launch,
    a bounded wait for `<dir>/observation.json`, `hud_states.py`, then a stop by the PIDs in `<dir>/pids.json`
    (`os.killpg`), as in the plan's Task 13 Step 2.
- `godot3d/scripts/earthfront_3d.gd` (the game file, 2572 lines; not in the bundle)
  - Hand patch in `_sync_bridge_entities` (unit branch): `entity_node.set_meta("category", "unit")` after
    `set_meta("bridge_id", ...)`. The baseline sets a category only for buildings. The readers that default to ""
    (`session_log.unit_removed` loss record, `_has_selected_combat_unit`, `_human_count("unit")`, unit proximity in
    `live_assault.gd`) always saw an empty category, so the debrief showed a false 0 lost and Attack-move stayed locked.
    Older readers default to "unit" and are unaffected.
  - `_has_selected_combat_unit` and `_human_count` are baseline readers, not new ones, so this patch changes baseline
    tutorial behaviour: tutorial stages 8 and 9 are now reachable (extra "MISSION UPDATED" toasts, a forced switch to the
    Orders tab and the countdown objective), and Attack-move unlocks. The patch is therefore not behaviour-neutral for
    the game logic, even though it adds no logic of its own.
  - Apart from this patch the file carries only the anchored UI migration from Task 12.
- Test files
  - `godot3d/tests/test_game_ui.gd`: tests beyond the bundle, including `test_research_cannot_open_under_the_debrief_scrim`,
    `test_research_search_typing_reaches_the_vm_and_dims_the_graph`, `test_research_modal_is_not_rebuilt_while_a_click_is_held`
    and `test_zoom_drag_updates_the_scale_without_rebuilding_the_modal`.
  - `godot3d/tests/test_live_adapter.gd`: two freed-selection tests (build tab; units and orders tabs).
  - `godot3d/tests/stub_game.gd`: `_has_selected_combat_unit` guards with `is_instance_valid` (the stub segfaulted on a
    freed selection for the orders tab).
  - `godot3d/tests/test_live_screens.gd`: asserts the Capital casualty row.

Known documentation discrepancy (not a divergence): `tools/qa/hud_states.py` is bundle-verbatim, and its docstring says it
writes `<qa dir>/states/*.png`. It actually writes `<qa dir>/state-*.png`. It was left as is.

## 7. What was not verified live

- The live win path was not exercised. The full campaign QA bot ended in a recorded loss at tick 19975 with 0 script
  errors.
- A real victory debrief casualty table was not seen live. The table was rendered only through a throwaway driver
  (Infantry 1 / 4). The defeat debrief has no casualty table by design.

## 8. Known minor items

- `run_tests.gd` does not count runtime script errors as failures; read the log for `SCRIPT ERROR`.
- Redeploy on a double-click reloads the scene twice. This is baseline behaviour.
- The 3D relay marker label contains a dash in game text. That is the game's own copy, outside UI scope.
- The tutorial still calls `_set_command_tab("SCIENCE")`; that call is now a no-op because Science opens the modal.
- The QA `ui_driver` sends key events with a keycode only, so it cannot type into a `LineEdit`.
- Forcing `ui_state(debrief)` in QA fabricates a defeat summary, so its numbers are not real play data.
- Segment labels on a thin defeat-timeline segment clip.
