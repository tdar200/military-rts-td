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
- The deck tabs are Build, Units, Orders, Science. Science opens the research modal. Logistics joins them (Task 13) once
  the snapshot carries the ground layer (Earthfront) and stays hidden otherwise; it offers only the lenses the snapshot
  can back (see "Gameplay board 8" below).
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
- "Select army" and "Idle crews N" are Buttons backed by new adapter actions (select_army, select_idle). The board's
  "Ctrl A" key cap is NOT drawn: Ctrl+A would collide with camera pan (physical A is camera_left, polled by
  Input.get_axis) and with the existing A / Ctrl+A attack-move arming, which is unchanged. Select army is bound to F2 (the
  same key the web client uses) and the button shows no key text. The idle crews chip keeps the board's "." cap; the
  period key is bound nowhere else.
- Brand sub: whenever the snapshot carries `map_name`, the brand sub shows it ("Kestrel Reach") instead of "Era 1 /
  Earthfront". Every gameplay board, including the build deck, prints "Kestrel Reach" there, so this is not limited to the
  main layout. Without a map_name the old text stays.
- Deposit pins are Buttons that centre the camera (focus_deposit). Only the first pin is compared by the harness: the
  mock's second pin sits over a deposit the fixture does not have.
- Excluded from the pixel gate: the minimap terrain image (an ignore rect; the 3D view is not a UI section), the tile
  inspector thumbnail (a rendered terrain swatch), the alert chip's "Next alert / Space" cap and the army column's third
  button slot (no counterpart, see above).
- Harness limits are achieved percent rounded to 0.1 plus 3, as for the original six screens. idle_chip (17.13) and
  tile_inspector_title (15.99) are high because of mono text anti-aliasing on short strings. army_orders is 13.17 (limit
  16.2) because the mock's Ctrl A key cap is deliberately not drawn (see above); it was 9.04 with the cap.

### Gameplay boards 2 and 3 (Build deck gp02, Core assault gp03), decided 2026-10-04 (Task 12B)
Built from live data: placing card, projected power grid, placement hint chip, "Ore in range" pin tag, enemy territory
card, combat preview card, hostile pin, thr lens with enemy cells. Not built, or reduced, because the snapshot, the ground
table or the bridge has nothing behind them:
- Footprints are single hexes (R1). The mock's 4x3 footprint grid is not drawn; the card says "1 hex is clear" or "1 hex
  is blocked".
- Placing card rows are Ore in range, River, Blocked tile, Territory and Power. The mock's Slope row and its "Ore +4"
  figure are dropped (no slope or haul data). Ore, river and power numbers come only from the deposit entities, the
  ground table and the sim bonuses (Refinery +20% within 1 hex of ore, Power Plant +12 kW beside river or ford). A test
  reads `earthfront.rs` so these constants cannot drift.
- Placement hint chip: "PLACEMENT", Click "place", Esc "cancel". The mock's rotate and Enter entries are dropped
  (footprints do not rotate and Enter is not a placement key). No key was bound. The chip's right edge is an estimate
  from the top strip.
- Projected grid: shows generation, demand and the real post-placement values only. No per-minute deltas.
- Enemy territory card: Defences (gun, AA and wall counts), Garrison (alien unit count), Terrain (the two most common
  ground names along the enemy border, names only) and Reinforce (next wave timer and size). Not built: "partly seen",
  "~14 est." and "east shore" lines (no fog, explored or discovery state, no sight range, no direction data) and any
  river attack penalty (not a sim mechanic).
- Combat preview rows: (1) damage type against armour class, one row per selected attacker kind, for example "Explosive
  vs Structure +50% damage", from the sim's damage matrix (`damage_multiplier`); built only when the attacker kind and the
  target's kind and category are known; (2) "Veteran rank N" with "+10%", "+20%" or "+35% damage" from the sim's
  veterancy factors, only for armed selected units with rank above 0; (3) the terrain rows: standing speed, range held on
  high ground, and the target's cover. The mock's health forecast bars, absolute damage numbers, "range 7" and "walls in
  the line" are not drawn. The tables live in `godot3d/scripts/ui/combat_rules.gd`; `tests/test_combat_rules.gd` parses
  the Rust source so a balance change fails a test. The harness rect covers only the header and sub line
  (`combat_head`), not the body rows.
- Pins: the "Alloy +6 on high ground" pin is not built (no haul claims). The hostile pin shows the kind only. Both pin
  positions in the gallery fixtures were moved a few pixels to sit clear of the map texture, as in gp01; this is a
  fixture detail, not a layout change.
- The thr lens now draws enemy cells as well as the route.
- Not built here, left to later tasks: objective panel, core bar, alert rows, the Logistics tab (Task 13 built it), the world-layer route and territory border (Task 13), and the top-strip chips of
  boards 2 and 3. The build and assault layouts keep their old minimap, alerts and queue panels.
- Live wiring: the placing card follows the hovered hex (below and left of it, clamped to the screen) and hides when the
  pointer is over the HUD; the old build_placement panel remains when there is no hover. The enemy card is live only in
  the assault layout; the combat preview and hostile pin work in every layout. Per-frame cost in the stub benchmark was
  about 1.0 ms (build layout) and 0.7 ms (main layout) per `hud_vm` call; no pre-change baseline was obtained.
- Harness limits are achieved percent plus 3. Highest rects: placement_card 22.10 (limit 25.1; the mock has an extra Slope
  row and different wording, so its title and rows wrap differently), hostile_pin 20.12, ore_pin 17.12, placement_hint
  16.98 (words differ from the mock). Mock-vs-Godot text noise is 5 to 11 percent per rect elsewhere.

### Gameplay boards 4, 5 and 7 (Structure selected gp04, Orders armed gp05, Wave inbound gp07), decided 2026-10-05 (Task 12C)
Built from live data: structure panel (name, tag, health, rows, queue, terrain, order buttons), site card, selection
roster with status strip, attack-move banner, control groups card, wave panel, and three world marks (rally arrow,
turret range ring, wave route beams). Not built, or reduced, because the snapshot, the ground table or the bridge has
nothing behind them:
- Structure order buttons are wired to the existing bridge command CSV: Set rally (`rally,producer,xbits,zbits`, only for
  Barracks, Refinery, Vehicle Factory and Airfield), Repair (`repair`, key U), Demolish (`sell`, key Del, hidden for the
  HQ, which cannot be sold) and Focus (camera, key F). A button the bridge cannot honour is hidden, never drawn dead.
  Not built: "Cancel last" (the bridge has no cancel command, so the queue cannot be unwound) and board 7's "Resupply" and
  "Focus fire" (no such commands).
- Set rally has no key. It arms the next left click as the rally destination (new `rally_armed` flag in
  `earthfront_3d.gd`); A, Esc, building placement, a new selection and an attack order clear it. Right-click with a
  building selected still sets the rally directly, as before. No key was added or rebound.
- Queue column: the running item (name, "Training" or "Building" note, progress bar) and a "N more queued" cell. Not built:
  the per-unit name list of the waiting queue ("Queue cost 520 M" and the like, no per-item data in the snapshot).
- Left column rows are only values the snapshot holds. Not built: "Supply range", "Rally 11 s walk", "Ore +4", the
  turret Targets and Ammo rows (no such data), "Fire across the river +10%" and "Ford ahead" (no sim effect behind them).
- Terrain column: a ground-colour swatch stands in for the mock's rendered terrain thumbnail, and its box is an ignore
  rect in the harness. The sprite boxes in the structure and roster cards are ignore rects too (a rendered building sprite
  is not a UI section).
- The structure name is numbered ("Barracks 2") only when several of one kind exist. The site card replaces the territory
  card, and the wave panel replaces the top wave card, while they are shown. For a single own building the old selection,
  territory and yields panels are removed so nothing stacks twice; the old selection panel's building orders (Repair, Sell,
  Focus) are exactly the new buttons.
- Attack-move banner: the mock says "Left click to confirm". Attack-move takes a RIGHT click, so the hint reads "Right
  click a tile to go, Esc to cancel". The mock's "Confirm target" and "Queue waypoint" lines are not built (no support).
  The same banner shows "Set rally armed" (cyan, flag icon) in rally mode. It ignores the mouse. Its harness rect is the
  highest at 22.67 (limit 25.7) because the longer real hint moves the banner edges and text about 4.5 px against the mock,
  and the hint text is an ignore rect.
- Selection roster: it replaces the old selection panel only while attack-move is armed and units are selected. Title is
  "Strike group" in the live game (fixtures use the mock's "Vanguard"), "+N more" past nine cards, a "Vet" chevron only
  for rank above 0, and the hp bar follows health tone (the mock is always green). The strip reads "Standing on <ground>"
  with the real speed. The Cancel button sits at the board's third slot, shows Esc and emits `order,cancel_armed`, which
  runs the existing `cancel_orders` handling. Not built: the cursor read-out (path, ETA, ammo) next to the banner.
- Control groups: four slots with real counts and the commonest unit kind as the label; "empty" for empty slots. Filled
  slots are Buttons that recall the group (the same code as the 1-4 keys).
- Wave panel: countdown, wave number and size come from the snapshot. Not built: the hostile count "5 left of 12", "East
  line breaking", "2 prongs", and the mock's Suggested panel (no per-wave composition or lane data). The "WAVE INBOUND"
  tag is an ignore rect (the mock tag is wider than the real wording).
- World marks only use existing `world_marks.gd` kinds, from real data: a cyan `arrow` from a selected producer to its real
  rally hex, a `ring` for the selected turret's real range (rx from the hex columns, ry from the rows, range from
  `stats.rs`, pinned by a test), and red dashed `beam` segments for the wave route while the wave is inside its warning
  window. The route beams have no arrowhead (the arrow head kind is cyan). Pure functions are tested in
  `test_live_boards457.gd`.
- Left-stack heights (the panels stacked under the objectives, then the territory card) are estimated from row counts,
  not measured, so a very unusual row count could overlap by a few pixels. The estimates match the three fixtures.
- Harness limits are achieved percent plus 3. gp04: structure_head 8.79, structure_health 8.78, queue_cap 11.75,
  queue_running 9.47, btn_set_rally 13.59, btn_repair 4.79, site_card 6.38, minimap 7.55. gp05: banner 22.67,
  control_groups 6.83, roster_head 9.26, roster_cards 4.82, roster_status 12.39, btn_cancel 4.85, minimap 7.54. gp07:
  wave_head 9.64, structure_head 8.95, structure_health 9.41, terrain_head 7.50, btn_repair 5.22, minimap 10.04.
  The minimap rects exclude the terrain interior and compare only the frame.

### Gameplay board 8 (Map overlays gp08), decided 2026-10-05 (Task 13)
Built: the Logistics deck tab (shown when the snapshot has `ground`, hidden otherwise) holding the lens Buttons, the active
lens's legend, one line of what it draws and a note; and four world overlays through the existing `world_marks.gd` path
(`live_adapter.board_marks`), computed once per snapshot by `scripts/world/overlay_feed.gd` and projected every frame.
A lens is a client-side choice (`world_lens` in the adapter, no bridge command, no key binding added). The overlay shows
only while the Logistics tab is open; clicking the lit lens again turns it off.
- Supply lens (Task 13b, built): the bridge now sends an additive top-level `supply_links` array
  (`{"depot", "target", "state": "ok"|"severed"}`, schema stays 5) from the sim's own `supply_route`, via the read-only,
  non-hashed `Sim::earthfront_supply_links`. The sim shares its depot filter (finished, power at least 500, stock above 0)
  and its radius rule (5 tiles, 7 with Field Supply Networks) with that export. Per finished human building (walls and
  mobile units excluded) the link names the first ready depot that feeds it, `ok` when `supply_route` holds and `severed`
  when a depot is in reach but a wall or terrain cuts the route. The bridge recomputes it on the 30-tick supply beat (the
  path searches are not run every snapshot) and holds it between beats, so a new depot or a new wall shows up to one second
  late. `overlay_feed` draws one `link` per entry (cyan solid, 3 px, when `ok`; red dotted with a cross when `severed`) and
  the Supply button exists only while the array has at least one entry: absent or empty means no button, no marks (the
  Kestrel start has no link, since the lone Command Center has nothing else to serve). The deck shows "Supply depots / N"
  with one glass row per depot that has links (name is the kind and cell, detail "N supplied, M severed", tag OK or Cut;
  cut depots first, at most three rows or two and a "+N more depots" line). Not built: the mock's route names ("Refinery to
  ore harvesters", "Command to gun line"), connection times ("Connected, 14 s"), the "Fix" action (the bridge has no repair
  or relink command, so the tag reads Cut), the "Barracks 04 has no supply link" alert, the green dashed "carrying ammo"
  paths (the sim does not report flow) and "A depot feeds everything within 9 tiles" (the real radius is 5, or 7 with
  research, and the legend says so). Links name buildings only, so a unit out of supply is not drawn.
- Power lens: tier order IS derivable (the sim allocates by building kind: defence, refinery, factories, laboratory; mirrored
  in `overlay_feed.TIER` and checked against `earthfront.rs` by a test) but WHICH plant feeds WHICH building is not (one
  shared grid). So each consumer gets one `link` to its nearest finished PowerPlant, Battery or CommandCenter (the Command
  Center generates 10 kW, `generation_for`; hex distance, ties to the lower id), links emitted in tier order then id. The
  lines are for display only: the grid is shared and served defence first, and the legend and note say so ("Not running,
  under 500 of 1000", not "Link broken"). Colour and weight follow the real delivered power, `services[].power`
  (0 to 1000): 1000 cyan, 500 to 999 amber, under 500 a red dotted line with a cross (the sim stops a building under 500).
  A consumer without a `services` row draws nothing. Line weight 2 to 6 px scales with the fraction, replacing the mock's kW
  weights (no per-line kW exists). No new cable mechanic; the mock's "Reactor A +100 kW" node pins, "Lab 30 kW, throttled"
  labels and "Power short by 8 kW" alert rows are not built (per-building kW is not in the snapshot).
- Borders lens: the player border is the outline of the real `construction_zone` (hex sides between a zone cell and an in
  map cell outside it; the map edge is not drawn); the enemy border is `vm_gameplay.enemy_border` with the label "Enemy
  territory". A cyan or red 3 px line with a halo; the mock's 5 percent territory fill is not drawn. The label sits on the
  enemy cell nearest the middle of the territory and pins to the screen edge with an arrow when it is off screen.
- Coverage lens: a dashed ring per finished human turret at the `stats.rs` range (the existing drift-tested constants), times
  (100 + `ground_table.range_pct` at the turret's cell) / 100, so a Highland turret shows +25 percent with a "+25%" pill. Not
  built: the mock's two big power-station circles (no coverage mechanic behind them).
- Yield lens: a one-hex ring around each human Refinery (the sim's ore reach), a "+20%" pill only when `ore_bonus` is true,
  and "river +N" over a PowerPlant only when `river_kw` > 0 (N is the real value). Not built: the mock's ore haul number "4",
  Cover "C" and Ford "F" tile chips (no Alloy or haul claims; cover and ford are already in the tile inspector).
- Minimap lens keys are unchanged (Land, Res, Bdr, Thr), not the mock's Pwr, Sup, Yld, Thr: the overlays are chosen in the
  Logistics tab, so the minimap header differs from the mock and is part of the minimap rect's 11.28 percent.
- Not built: the top-right "Map lenses" legend card (the legend rows live in the deck tab instead, so one place both picks
  and explains a lens), "Tab cycles" (no key), the Grid ledger panel, the alert rows, the top bar chips of this board. The
  deck tab strip keeps the Main board's icon tabs, as in boards 1 to 7 (the gp mocks draw them without icons), so the tab
  strip is not a harness rect.
- `world_marks.gd` gained styles, not kinds of data: `link` takes tone, width and broken; `ring` takes dashed and tone;
  `badge` becomes a pill for text longer than two characters; new `border` kind (segments in screen pixels).
- Cost: nothing is computed unless the Logistics tab is open with a lens on. Then the feed runs once per new snapshot
  (O(entities); the nearest-source search is plants times consumers, a handful of plants) and projection is O(marks) with a
  per-frame cell cache. On Kestrel the player border is 95 short segments.
- Harness limits are achieved percent plus 3 (floor 3.0). gp08: deck_frame_top 0.02 (3.0), deck_frame_bottom 0.06 (3.1),
  minimap 11.28 (14.3), unchanged by Task 13b. The battlefield (marks included) is masked. No supply-list rect was added:
  the mock draws its route rows at the top of the deck panel (rows 36 px tall, 8 px apart, route names in the text) with
  the lens picker in a separate card, while ours puts the lens Buttons and a two-line legend above shorter rows, so the
  row boxes land at different heights and widths with different text. A rect over them would measure layout and wording,
  not fidelity, and could only pass by loosening its limit. The gallery (gp08) now shows the Supply lens and its list,
  and renders Power, Supply, Borders, Coverage and Yield marks together for a visual check; the live game draws one lens
  at a time.
- The lens text (legend, note, summary, supply rows) is built once per snapshot beside the hex marks, not every frame (the
  borders summary walks the enemy border).

### Gameplay boards 9 and 10 (Pause menu gp09, Controls gp10), decided 2026-10-05 (Task 14A)
Built: `scripts/ui/keybinds.gd` (the one keybinding list: Esc, F1, F2, `.`, A, Q, U, Delete, Y, F, Home, 1 to 4, the train
and build maps, the six camera actions), read by the input handler in `earthfront_3d.gd` and listed by the Controls screen;
the Pause menu (`sections/pause_menu.gd`: Paused marker, Command pause panel with Resume, Controls, Restart mission, Quit
game, the Mission snapshot, and the Restart or Quit confirm strip); the Controls screen (`sections/controls_reference.gd`:
six groups in three columns, a Back button, a footer tip); `components/key_chip.gd`; `spread` option on HoloButton (label
left, key cap right, as the pause board's space-between buttons).
- Real pause. The game had no pause (the HUD speed buttons are dead and not shown live), so a pause that only drew a scrim
  would be fake. Godot writes `pause.flag` in the bridge runtime directory (`set_sim_paused`), and `godot-bridge` skips the sim
  step and command intake while the file exists, still publishing the snapshot every frame. This is the one Rust edit of the
  task (`crates/server/src/bin/godot-bridge.rs`: `pause_path`, removed at startup and on `restart.flag`, one loop branch). It
  is additive, touches no sim code and no hash. The process is not paused: UI, camera-free input and the pause screens still run;
  HUD view-model polling and the alert clock are frozen. The marker reads "Simulation stopped" only while the bridge tick has
  not advanced more than 6 ticks since the pause began, otherwise it reads "Simulation still running" in the warning tone, so
  it never claims a stop it cannot prove (an older bridge binary without the flag shows the warning).
- Esc precedence: Controls, then the confirm strip, then an open pause menu (resume), then the research modal (its own
  handler), then an armed attack-move, rally or placement (cancels, existing behaviour), then nothing before deploy, under the
  debrief scrim or with the HUD hidden, else it opens the pause menu. F1 toggles Controls (pausing first when opened in play).
- Restart maps to the existing `_restart_mission()` (restart.flag plus scene reload), so it returns to the title and a fresh
  mission, not an in-place restart; the menu footnote says so. When the host has no such method the Restart button is hidden.
  Quit is `get_tree().quit()`, labelled "Quit game" (the board says "Quit to title"; the game has no title to quit to without
  restarting, so it would be a false label). Both ask for a second confirmation. The confirm button reads "Restart", as the
  board does; the menu button reads "Restart mission".
- Hidden, no feature behind them: Settings (F10), Save and keep playing (F5), the Objective and Last save snapshot rows
  (the game has no objective text and no saves), the Rebind keys button and the Alt footer tip on Controls. The snapshot rows
  that exist are Waves survived, Elapsed (tick / 30), Next wave, Material, Power (warning tone when demand exceeds generation),
  Units alive (the ledger) and Losses (the session log).
- Controls rows dropped because the key does not exist: Orbit (middle drag), Jump to alert (Space), Jump on minimap,
  Pause simulation (P), Game speed, Quick save, Map overlays (Tab), Clear selection, Recall and centre, Open Build tab,
  Place several, Rotate ghost, Stop, Hold, Focus fire, Resupply, Spread out, Queue waypoint, Return to HQ, Set rally point
  key, Queue five, Cancel last queued. Rows added because the key exists and the board lacks it: Rotate (Z, E), Focus selection
  (F), Science panel (Y), Select idle crew (.), Tactical ability (Q), Repair (U), Sell (Delete), the seven build keys and five
  train keys. Control groups read 1-4 (four groups), not 1-9. Select all army is F2, not Ctrl+A. Attack-move is A then a right click.
  Deck cards show their own key, so the Alt overlay is not needed.
- Departures: no backdrop blur behind the scrim (Godot's CanvasItem has no cheap blur and the mock's is 3 px); the Pause
  screens live in `sections/` (view-model sections) rather than `screens/`; Controls draws a flat ground (no top radial glow).
- Harness: gp09 and gp10 gallery arms use the Kestrel snapshot (`fixtures_gp.gd` pause_board, controls_board; 14:36 elapsed,
  01:52 next wave, 840 material, 160 / 168 kW). The battlefield is masked. gp09 rects: paused_marker 3.01 (6.0), menu_head
  3.13 (6.1), btn_resume 2.09 (5.1), btn_controls 1.41 (4.4), snapshot_head 1.68 (4.7), snapshot_rows 2.10 (5.1), confirm_panel
  3.59 (6.6); ignore: the mock's broken image icon on the Resume button. gp10 rects: header_left 5.04 (8.0), btn_back 17.20
  (20.2), camera_head 2.47 (5.5), camera_zoom 2.05 (5.0), selection_head 3.70 (6.7), orders_head 2.42 (5.4), footer_frame 0.08
  (3.1); ignore: the footer sentence. btn_back is high because the shared key cap is about 3 px narrower than the mock's
  inline-sized one, which shifts the whole button 4 px; its limit was not loosened. Nothing below the first rows of the
  groups, the menu's lower buttons or the Units alive row is a rect: their rows, labels and heights differ from the mock by
  content, so a rect there would measure wording, not fidelity.

### Gameplay boards 6, 11 and 12 (Early mission gp06, Region map gp11, Terrain guide gp12), decided 2026-10-05 (Task 14B)
Built: `scripts/ui/vm_maps.gd` (view-model slices `region_map`, `terrain_guide`, `briefing`, pure, `{}` without data),
`components/hex_map.gd` (hex geometry and the cached ground mesh), `sections/region_map.gd`, `sections/terrain_guide.gd`,
`sections/early_mission.gd`, the `map` icon, `Keybinds.REGION_MAP`.
- Strategic map (gp11). Opened with M (`Keybinds.REGION_MAP`, the one key source; M was free: not a build, train, ability, camera
  or project.godot key, and `test_keybinds` pins that it belongs to one constant). Esc closes it through `escape_route`
  ("close_region", after the pause stack and before the Science modal). It is not a pause: the simulation keeps running and the
  world only stops taking input (`GameUI.world_blocked()` replaces the two `ui.paused()` gates in `earthfront_3d.gd`). M does
  nothing over the pause menu, the Science modal or the debrief, and nothing without a ground layer and named regions. The real
  `ground` layer is drawn flat in the 3D ground palette (`ContinuousTerrain.GROUND_LOOK`, so the colours cannot drift), as one
  cached `ArrayMesh` (`Hex.ground_mesh`, kept per ground string; a lens toggle or an unchanged snapshot never rebuilds it).
  The overlay (zone and enemy tints, border edges from the Task 13 feed, the `wave_route` as the expected assault route,
  hostile diamonds, the colony marker) is rebuilt by the host only when the hash of the view model changes (checked every
  0.5 s, never between a press and its release). Labels come from `regions`, each on a cell of the ground it names, with
  collision avoidance. Right panel: map name, Era, Composition (bar and legend from the ground counts, largest remainder so the
  legend totals 100), Territory (real `construction_zone` count), Hostile sites (real alien structure count), five lens Buttons
  (Terrain, Resources, Borders, Threat, Hex grid). A deposit pin click closes the map and centres the camera (`focus_deposit`).
- Strategic map, dropped (no data or no feature): Yields per minute (the snapshot has no per-minute yields), fog, explored
  percent, Unexplored and Islet pins, "Resources seen", Next goals, the painted terrain art (a flat hex fill replaces it, so the
  map area is masked in the diff), the compass and the scale bar, the board's "Coastal river basin" subtitle (the snapshot has no
  such text; the sub line is the era). The board's Alloy and Ore pins use the existing resource-pin section (Resources lens).
- Terrain guide (gp12). One card per `ground_table` row, then an Ore card and an Alloy card with real numbers (deposit counts,
  ore left from the snapshot, the mirrored refinery bonus; the Alloy card says Mining: None because alloy is scenery in the
  Earthfront sim, and exists only when the snapshot is Earthfront and has alloy deposits). Every number on a ground card is a
  table value; the notes are words only. The Rules footer is built from the table (high-ground range, fast open ground, the
  river crossing only at the ford, forest cover) and drops a rule when its table fact is absent. Dropped: "-25% across the
  river" and the Fog rule (the sim has neither), the Terrain / Resources / Structures / Units tabs (only the terrain page
  exists), "Home ground", "Chokepoint" and per-card place copy that would be invented (the sub line is the smallest region that
  holds the ground plus its real tile count), the painted swatch images (a flat hex crop of the ground colour stands in).
  The board names the cards after places (Ironback Ridge, Hollow Wood); the guide names the ground kinds, because the table is
  per kind, so the card set and order differ from the board (the card grid and frames match).
- Codex entry point. The pause menu gets a "Terrain guide" Button between Controls and Restart, shown only when the host sets
  `can_guide` (the snapshot has a ground table). The gp09 fixture does not set it, so board 9 keeps its own height. The guide
  replaces the pause menu in the pause layer; Back or Esc returns to the menu (never straight to the game). There is no
  dedicated key: the Codex has one page, and M, F1 and Esc already cover the rest.
- Early mission (gp06). The snapshot carries no objective data; the real objectives are the client's tutorial stages
  (`live_adapter.STAGE_DETAIL`, the text the HUD objectives panel already shows). The briefing card reads those: "Step N of 10"
  (the real count, the board says 9), a title per stage, a short paragraph, the done / current / next lines, a progress bar.
  Paragraph copy that names a place (the river) uses the snapshot's river region and is left out when there is none; the
  numbers in it are the mirrored sim constants. It shows from tutorial stage 0 to 2 (the first objective group, "Establish a
  supplied base"), while the match is undecided and the HUD is up, and never again after the player presses Hide (a button
  inside the card; the board has none). The card's nodes are freed on hide or after stage 2, so it cannot block input; while it
  is up the HUD leaves its own objectives panel out and the left card stack and territory card start below it
  (`LiveAdapter.briefing_up`). Not built: the "Mission updated" and "Reactor site is valid" toasts, the placement card and the
  tile inspector of the board (their data is the other boards' own screens), the board's survey wording.
- F1 over the Science modal (14A hardening). F1 no longer opens the controls over the open Science modal (`research.visible`).
- Stale pause flag (14A hardening). `earthfront_3d.gd` `_ready` calls `set_sim_paused(false)` after reading `--runtime-dir`,
  so a `pause.flag` left by a crash cannot hold the next run still. Same path logic as the pause itself.
- Harness: gp06, gp11 and gp12 gallery arms use the committed Kestrel snapshot (`fixtures_gp.gd` `region_board`, `guide_board`,
  `early_board`, `briefing_board`). The battlefield (the board's painted art) is masked, with chrome rects after it: gp06
  briefing_card 15.95 (18.95), briefing_head 8.47 (11.47), tactical_head 14.68 (17.68); gp11 title_bar 6.62 (9.62), panel_head
  8.06 (11.06), composition_top 11.24 (14.24), composition_rows 15.62 (18.62), lenses_panel 13.22 (16.22); gp12 header 5.52
  (8.52), row1_cards 14.80 (17.80), row2_cards 17.71 (20.71), row3_cards 18.17 (21.17), footer 13.65 (16.65). The values are
  high because the mock carries invented numbers and copy where the live screens print real ones (card text, legend rows,
  step wording); limits are achieved plus 3, none loosened. The gp06 top bar and Build deck are not rects: the mock draws the
  older bar and deck, which the Build layout (gp02) already measures.

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
