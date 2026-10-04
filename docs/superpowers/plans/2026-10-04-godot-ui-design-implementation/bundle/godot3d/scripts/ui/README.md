# scripts/ui: the Ascension HUD

Plain-data screens built in code. A screen takes a view model (a `Dictionary`), draws it, and emits `action(name, arg)`.
Screens never read game state; `live_adapter.gd` and friends turn `earthfront_3d.gd` state into view models.

| Layer | Files |
|---|---|
| Style guide | `tokens.gd` (colours, fonts, tone words), `icons.gd` (stroke icons), `fx.gd` (gradients, glows) |
| Building blocks | `kit.gd` (node factories in mock pixels), `components/*.gd` |
| Screens | `hud.gd` (+ `build_deck.gd`, `assault/*`), `research_screen.gd`, `title_screen.gd`, `debrief.gd`, `world_marks.gd` |
| Live data | `live_adapter.gd`, `live_assault.gd`, `live_research.gd`, `live_screens.gd`, `session_log.gd` |
| Host | `game_ui.gd` (the one object `earthfront_3d.gd` talks to) |

Rules that keep it working:
- Use `preload`, never `class_name`.
- `Hud` rebuilds a section only when its slice of the view model changes, and `game_ui.gd` skips a rebuild while a click
  is in flight over the HUD. Do not rebuild a button between its press and release.
- Every clickable is a Button whose `.text` is its human label (hidden, never drawn). The QA driver and the tests find
  controls by that text.
- A missing or empty slice builds nothing. Never fill a block with invented numbers.
- Never call `Icons.texture()` from `_draw()`; create it in a setter or `_ready()` and read `Icons.cached()`.

Commands (repo root):

    tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --script res://tests/run_tests.gd [-- file.gd:]
    tools/ui/verify_all.sh [main builddeck coreassault research title debrief]
    python3 tools/qa/launch_ui.py <dir> --software && python3 tools/qa/hud_states.py <dir>

Deviations from the mocks: `docs/ascension/ui-deviations.md`.
