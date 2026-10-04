# Godot UI: implement the Ascension design set 1:1

Date: 2026-10-04. Status: draft for review. Path: architectural.

## 1. Goal and agreed understanding

Implement the in-game UI screens from the Ascension Design Set canvas (https://claude.ai/artifact/FCsmt1puJtbHqKGih7vuDg) in the **Godot 3D client** (`godot3d/`), so the UI chrome matches the mock boards pixel for pixel at 1920x1080.

Agreed with the user (2026-10-04):

- Client: Godot 3D client only (not the Macroquad shell).
- Screens: the playable Earthfront screens only: title and campaign, Earthfront HUD (including the core-assault state), build deck and placement, research graph, victory and defeat debrief, plus the style-guide tokens.
- Fidelity bar: **UI chrome pixel-matched**. Every panel, bar, chip, icon, font and colour matches the mock in position, size and style. The 3D battlefield stays 3D. The mock's painted-sprite battlefield is a stand-in and is masked out of comparisons.
- Data: the live sim data fills the UI. The mock's sample numbers appear only in the verification gallery.

Out of scope: the solar strategic screen, the eight gameplay boards (they describe proposed mechanics that are not implemented), the Macroquad shell, the 3D scene, game logic, and the Rust core and `godot-bridge`.

## 2. Findings that shape the design

- `godot3d/` is entirely untracked in git. A baseline copy is taken before any edit (section 8).
- The current HUD is about 1,000 lines of hand-placed `Control` nodes inside `scripts/earthfront_3d.gd` (`_build_ui`, `_build_science_panel`, `_refresh_science_panel`, `_build_briefing`, `_show_end_screen`, `_build_minimap`). Its palette (gold `#caa75d` and teal) differs from the new theme.
- Viewport is 1440x900 with `canvas_items` stretch. The mocks are 1920x1080.
- The QA driver (`tools/qa/ui_driver.gd`, `campaign_player.py`) finds buttons by their `text` property. Changing labels breaks it unless the text is kept or the driver is updated.
- Only Rajdhani is bundled. The mocks use Rajdhani, IBM Plex Sans and IBM Plex Mono.
- Godot 4.7.2 is at `tools/godot/`. Headless Chrome is installed, so mock boards can be rendered to PNG.

## 3. Approach

Code-built UI from a small component library (approach A): GDScript Controls, a tokens file, custom `_draw()` for gradient, bracket and glow details. This matches how the file is built today, needs no editor, and reaches pixel-level detail that `StyleBoxFlat` alone cannot (gradients, corner brackets, scanlines).

Rejected: hand-authored `.tscn` scenes plus `.theme` (error-prone without the editor, cannot do brackets or gradients); restyle-only (cannot reach 1:1 because layout and components differ).

## 4. Architecture

```
godot3d/
  project.godot                      viewport 1920x1080, canvas_items stretch (changed)
  assets/fonts/                      + IBMPlexSans-*.ttf, IBMPlexMono-*.ttf (OFL, with licence files)
  assets/ui/icons/*.svg              icons exported from the mock boards
  scripts/ui/
    tokens.gd                        colours, fonts, sizes, spacing: the style guide as constants
    components.gd                    HoloPanel, Chip, HoloButton, Bar, Tag, KeyCap, CornerBrackets
    hud.gd                           top bar, objective tracker, wave telegraph, alert queue,
                                     minimap shell, selection panel, deck tabs, power tooltip,
                                     edge alerts, core-assault overlays
    build_deck.gd                    Build tab cards, cost lines, stall reasons, placement colours
    research_screen.gd               12-project graph, states, detail drawer, filter rail, era gate
    title_screen.gd                  title, menu, campaign panel (replaces the briefing)
    debrief.gd                       victory and defeat debrief (replaces the end screen)
    gallery.gd + ui_gallery.tscn     debug scene: each screen with the mock's fixture data
  scripts/earthfront_3d.gd           keeps all game logic; builds the UI via the new scripts
```

Boundaries:

- `tokens.gd` has no dependencies. It is the only place colours and sizes are defined.
- `components.gd` depends on `tokens.gd` only. Each component draws itself and exposes a few typed properties.
- Each screen script takes a plain `Dictionary` view model and emits signals for actions. It never reads `bridge_*` variables or the scene tree. This is what lets the gallery drive it with fixtures and the game drive it with live data.
- `earthfront_3d.gd` maps `bridge_*` state to the view models and maps the screens' action signals to the existing handlers (`_on_command_button`, `_arm_build`, `_write_bridge_*`). Game logic is not moved.

Old `_build_ui`, science panel, briefing and end-screen code is deleted once its replacement passes verification.

## 5. Screen mapping and data

| Mock board | Godot screen | Live data source |
|---|---|---|
| Earthfront HUD | `hud.gd` | `bridge_money`, `bridge_ore`, `bridge_power_generation/demand`, `bridge_energy` / `bridge_storage_capacity` (battery), `bridge_supply_used/cap` (crew), `bridge_depot_ammo`, `bridge_next_wave_ticks`, `bridge_incoming_doctrine`, `bridge_expedition_size`, `bridge_relays` / `bridge_active_relays`, selection metas, `bridge_services` |
| Build deck and placement | `build_deck.gd` | `bridge_unlocked_buildings`, `bridge_money`, the existing requirement tables, `_is_build_valid`, build ghost state |
| Core assault | `hud.gd` assault state | Core Node entity HP, relay counts, HQ HP, ammo supply. Shown only once the Core is in play |
| Research graph | `research_screen.gd` | `bridge_research_options`, `bridge_active_research_*`, `bridge_research_count`, `bridge_era`, prerequisites from each option |
| Title and campaign | `title_screen.gd` | static; Dawnshield playable, four locked chapters tagged DESIGN / LOCKED |
| Victory and defeat debrief | `debrief.gd` | `bridge_winner`, `bridge_tick`, `bridge_waves`, `bridge_research_count`, `bridge_era`, relay counts |

### Data gaps (decision needed at review)

The mock shows some values the snapshot (schema 5) does not carry. This pass does **not** change the Rust `godot-bridge`. Proposed handling:

- Wave composition estimate ("2 artillery, 4 heavy escorts, 8 raiders"): show doctrine name and expedition size only; the composition line is hidden.
- Power tooltip producer and consumer breakdown: derive from `bridge_services` per-building power where present; otherwise show generation, demand and shortfall only.
- Casualty counts, economy history chart, defeat-cause timeline in the debrief: the client records these itself during the session (kills, material samples every N seconds, last supply and power interruptions from service state). If a value cannot be derived, that block is omitted rather than filled with invented data.
- Objective checklist: driven by the existing tutorial stages and relay counts.
- Alert queue: fed from the existing notification events (wave committed, power short, relay destroyed, science complete, under attack).

If the user wants exact parity for any of these, a follow-up extends the bridge snapshot (Rust) first.

## 6. Design details that must match

Tokens come from the Style Guide board and BRIEF: bg `#060910`, panel gradient (`#122030` to `#08101a`, 92% alpha) with 1px `#284e60` border and inner top light, cyan `#40dceb` / hi `#96f5ff`, text `#cee8f0`, dim `#8fb0bf`, good `#50e6a0`, warn `#f0b040`, bad `#f04e46`, violet `#b79cff`. Type scale at 1080p: 12 caps tags, 14 secondary, 16 body, 20 panel titles, 28 section heads. Friendly selection marks are square corner brackets in cyan; hostile marks are diamonds in red (colour plus shape). Icons are 24px stroke icons, 1.75 stroke, round caps.

Layout geometry (1920x1080): top bar 56px at 12px margins; objective tracker 420px wide; minimap panel 304x298 bottom-left; selection panel 940x258; deck 624x298 with five tabs (Build, Units, Orders, Science, Logistics). The Logistics tab is shown only if the bridge exposes supply routes; otherwise it is hidden, not faked. Exact per-element coordinates are read from the mock `.dc.html` source by the plan.

## 7. Verification

1. **Gallery scene**: `ui_gallery.tscn` renders each screen with fixture view models equal to the mock's numbers, at 1920x1080, and saves a PNG per screen with `get_texture().get_image()` (the same mechanism `ui_driver.gd` already uses).
2. **Mock renders**: headless Chrome renders each mock board (`Main`, `BuildDeck`, `Title`, `Research`, `Debrief`, `CoreAssault`) to PNG at 1920x1080.
3. **Diff**: a script compares the pairs, masking the battlefield region (the 3D scene or the mock's sprite stand-in), and reports per-screen difference and writes a side-by-side image. Acceptance: no unmasked region is visibly off in the side-by-side, and the per-region pixel difference is under an agreed threshold set when the first screen is calibrated (anti-aliasing and font hinting prevent an exact zero).
4. **Live pass**: run the real game through the QA driver. Buttons keep their `text`, or `ui_driver.gd` / `campaign_player.py` are updated in the same change. A fresh campaign must still complete.
5. **No regressions**: `cargo test --workspace` is untouched by this work; the Godot editor parse check and visual smoke test must pass.

## 8. Safety and sequencing

- Before the first edit: copy `godot3d/` to a dated tarball outside the repo (not committed). Nothing is committed unless the user asks.
- The existing dirty Rust and docs changes stay as they are.
- Build order, each step verified before the next: (1) project settings, fonts, icons; (2) `tokens.gd` and `components.gd`; (3) HUD with the gallery and diff harness; (4) build deck; (5) research; (6) title; (7) debrief; (8) core-assault state; (9) delete old UI code and run the live pass.

## 9. Risks

- Font rendering differs between Chrome and Godot (hinting, metrics), so exact zero pixel diff is not achievable. Mitigation: calibrate the threshold on the HUD and compare layout boxes as well as pixels.
- The viewport change from 1440x900 to 1920x1080 can shift the 3D camera framing and hit-testing. Mitigation: check selection, placement and minimap clicks in the live pass.
- The research graph needs positions for the 12 projects; they come from the mock, and unknown future nodes are not invented.
- `earthfront_3d.gd` is large; keeping the UI behind view models limits how much of it changes.
