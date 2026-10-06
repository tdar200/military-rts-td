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
  river attack penalty (not a sim mechanic). Since the Kestrel fog (section 9, Task 7) the card reads known structures,
  units in sight and "Not scouted"; the estimate and shore lines are still not built.
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
- Controls rows dropped because the key does not exist: Orbit (middle drag), Jump to alert (Space) and Jump on minimap
  (both exist on Kestrel Reach since Task 8 of the next-level plan and its Controls screen lists them; Survival and the
  gallery gp10 board still drop them),
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
  Since the Kestrel fog (section 9, Task 7) the Kestrel strategic map shrouds unseen hexes and has an Explored percent row;
  the other dropped items stand.
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

### Live QA and cleanup (Task 15), decided 2026-10-05
Everything above was measured against mocks in the harness; this pass played the real Kestrel Reach build under software
GL (Xvfb, Dummy audio, 1920x1080, about 3 fps) and looked at every capture. What it changed or confirmed:
- Survival keeps its noise terrain and shows no ground UI. The bridge emits an all-Grassland `ground` layer for every
  scenario (so the snapshot shape never forks); the client used to build a flat model from it, which replaced the noise
  terrain with plain green, added the Logistics tab and printed "Grassland 100%" on a territory card. `GroundModel.is_flat`
  (a well-formed layer of `g` only) now means "no terrain": `from_snapshot` returns null, `OverlayFeed.tab_available` is false
  and `_sync_ground` returns quietly. A wrong-sized all-`g` string is still reported once as malformed. Survival therefore has
  no Logistics tab, no territory card, no tile inspector, no M map and no river line in the briefing.
- Pause marker. At 3 fps the bridge answers a pause late, so the marker could stay on "SIMULATION STILL RUNNING" for as long as
  the poll lagged. `GameUI` now watches the tick while paused: it shows "STILL RUNNING" only while the tick keeps advancing
  past the slack, and flips to "STOPPED" once the tick has stood still for 0.6 s (`STOP_STILL_SECONDS`). Real frame rates
  never see the difference.
- Camera on a Kestrel deploy and on Home. The survival corner (3,14) is wrong for Kestrel, whose colony sits at the
  Command Center. With a ground layer, Home and Deploy centre on the player's Command Center (`home_focus`); Survival is
  unchanged.
- Reduced: the river bonus has three homes and the selected structure's terrain card is not one of them. "River +12 kW" shows
  on the hover tile inspector (only when nothing is selected, because a selection owns the bottom centre), on the Yield lens
  badge ("river +12") and in the briefing text. The structure panel's terrain card lists movement, cover and range only.
- Cosmetic: the Yield lens legend draws its two badge swatches ("+20% ore bonus", "River cooling") as empty outlined boxes.
- Not a bug, worth knowing: an idle player's Command Center falls to wave 1 at about 1:45 on Kestrel (the sim's undefended
  fall is tick 3159, just past the 2700-tick grace). A live session has to build defences in the first minute.
  Superseded 2026-10-06 by the Kestrel opening (section 9, "Kestrel opening"): wave one now spawns at 2:30, a scripted
  probe strikes first at about 1:55, and an idle player's Command Center falls at about 2:45 (tick 4959).
- The Build layout (a deck tab open at the start) still draws the older top bar ("ERA 01 CONTEMPORARY HUMANITY") and has no
  territory card; the main layout draws the board 1 bar. That split predates this branch (gp02 measures the older bar).
- Crater note. The terrain guide's Crater card reads "Some shelter from fire, but slow going. Nothing can be built here."
  The earlier draft said where craters came from; the snapshot says nothing about that, so the line is limited to the table.
- The briefing sits over the top of the territory card while it is up (the mock stacks them the same way); Hide removes it
  and the territory card is whole again.
- Leak tidy. `ResearchScreen` freed its `_meter` only in `_exit_tree`, which never runs for a screen that is freed unparented.
  A `NOTIFICATION_PREDELETE` handler now frees it. Suite exit counters went from 56 RIDs, 251 ObjectDB instances and 1
  resource still in use back to 0 RIDs, 137 ObjectDB instances and no resource line.

## 5. Known cosmetic items

- The research screen has an empty band at the top where the era-gate block would sit.
- "Attack-move" wraps to two lines in the narrow order tile; the mock wraps it too.
- Godot logs an invalid-UID warning for a GLB in `_place_scene`. It predates this work.
- The minimap shows the whole map letterboxed in its slot. On Kestrel a click or drag inside the map moves the camera
  there; a click in the letterbox does nothing (see "Kestrel minimap interaction").
- Hostile diamonds appear only while alien units are on screen (covered by `test_live_assault.gd`).
- Kestrel briefing card (seen in the Task 10 playthrough, 1920x1080): with the fog sentence the intel paragraph ran to
  four lines (the card reserves three, `early_mission.gd` `BODY_LINES`), and its last line ("side stays dark until your
  units scout it.") drew over the first objective row ("Start the economy"). Fixed in the copy (fix round, review I4): the
  fog note is folded into the probe sentence and the Core Node's cell is dropped (the minimap and the objectives card show
  it), so the paragraph is three lines; `test_the_kestrel_briefing_body_fits_its_three_card_lines` measures every opening
  variant with the card's own wrap. The card height is unchanged.
- Kestrel toasts still cover the territory card for their 9 s (by design since Task 3; the card's header shows through
  the toast backgrounds in captures).
- Placement toasts read "Place gunturret" and "Gunturret foundation ordered" (the kind name is case-folded without its
  word break), seen in the Task 10 playthrough. Fixed on Kestrel (fix round, review I5): `earthfront_3d._kind_text` spells
  the kind by `LiveAdapter.KIND_NAMES` at the place, foundation, train (unit and producer) and unit-ready toasts ("Gun
  turret foundation ordered", "Battle tank order sent to vehicle factory", "Rocket team reporting for duty"). The HUD's
  `_sentence` still lowercases everything after the first letter, so "AA battery" reads "Aa battery". Survival keeps the
  raw upper-cased name, so its ticker text is unchanged.

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

- Task 15 played Kestrel only at about 3 fps under software GL. Frame pacing, hover latency and the look of the shadows on a real
  GPU were not judged. A turret on Highland outranging a grass turret was not seen live (the Rust tests pin it).
- The ford slowdown was measured from snapshot polling, not by eye: a unit crossing paces about half as fast on the ford
  as on the Dry Flats (a wave unit: 0.020 against 0.040 world units per tick over 81 and 293 sampled ticks). The grass sample was too noisy
  (stops and turns) to quote.
- Nothing played to the end: the Kestrel colony fell within the first three waves in every run, and the live win path is unseen.
- No sound was played (Godot ran with the Dummy audio driver), so audio was not judged.
- Kestrel next-level playthrough (Task 10, 2026-10-06, real bridge and client on a private Xvfb, software, Dummy audio,
  driven only by viewport input): the economy ran from the first tick (the Harvester mines in place), the first three
  objectives were done by about 0:33 (tick 998, 7 riflemen), the probe was first in sight at 1:54 and died to two gun turrets and a 12-rifle
  squad, and wave one (10 rifles) was held at the cost of one gun turret and two riflemen; the run stopped at 4:02
  with the base whole. Numbers, captures and the audio log counts are in the Task 10 report
  (`.superpowers/sdd/2026-10-06-kestrel-next-level/task-10-report.md`). The win path is still unseen.
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
- Sim behaviour change (final fix round): on Earthfront maps a ground unit ordered onto an impassable tile (a building such as a
  Command Center, or River/Sea) now walks to the nearest passable tile and stops there. Before, it kept the raw point and
  stepped onto the impassable tile once its path ran out, so units could stand in the river. Units no longer "close the last
  step" onto a building; combat auto-fire is unaffected. Legacy non-Earthfront scenarios and the golden hash are unchanged.

## 9. Kestrel world art (2026-10-05)

The Kestrel 3D world was re-arted to read like boards gp01 and gp03 to gp08 (spec addendum
`docs/superpowers/specs/2026-10-05-kestrel-world-art-design.md`, rulings W1 to W9). Survival and every other scenario keep
every legacy path. What still differs from the boards, and why:

- Buildings are the boards' own painted sprites (2026-10-05, reversing W6 on the user's call; `WorldSprites`): one card
  per building, square to the fixed camera above the painted contact line (85 % of the card height, the boards' sort
  line) and lying on the ground below it, at the boards' pixel size (82 px per tile: CC 3.05 tiles, barracks, factory and
  refinery 2.44, power plant 2.07, lab 1.83, gun turret 1.40, wall 1.22, AA 1.04). The enemy draws the `alien_*`
  sprites. A building under construction no longer shows the boards' foundation slab (`foundation_v1`): live, the user
  read it as a ruin. A site draws its own building's painting (the alien one for the enemy) at the building's own width,
  revealed from the painted base up by the build progress (`WorldSprites.show_progress`), the built part under a faint
  scaffold tint (18 %) with a lit weld seam at the build line, the rest a scaffold lattice and faint sheeting clipped to
  the painting's silhouette. Its cast shadow is cut at the same line. The bars, crown, label, pick box, paint-mask hit and
  hover cover follow the built part (a fresh site picks by at least its bottom 15 %), and the card refits as the progress
  moves. Each site card carries its own copy of the site material (its own build line); finished buildings share one
  material per texture. No board draws a site part built, so the reveal and the lattice are ours. Each card casts the
  boards' sheared silhouette shadow and keeps a soft contact pad on the ground under its painted footprint. A sprite that
  fails to load never breaks a building or a unit: an entity without its sprite keeps its fitted model at the model width table
  (`WorldArt.MODEL_BUILDING_TILES`, `MODEL_UNIT_TILES`; the card widths include a painting's transparent margin). Every
  sprite's alpha scan, paint mask and graded copy are built once as the Kestrel ground loads (`WorldSprites.prewarm`,
  about 160 ms headless), not on the frame a kind first appears; one throwaway card each with the site and the ghost
  shader is drawn too small to see just past the camera's near plane for half a second as the ground loads, so the
  renderer compiles both pipelines then, not on the first site or the first armed build. Every one of the 13 building kinds draws its own painting
  for each side. Seven come from the boards (CC, power plant, refinery, barracks, gun turret, AA turret, wall). The other
  six, which no board paints (vehicle factory, airfield, battery, antimatter plant, supply depot, research lab), are
  composites built by `tools/ui/build_building_variants.py` from crops of the boards' own sprites, recoloured and
  relit, with procedural slabs, pads, tanks, crates and a glass dome (`*_v1.png` and `alien_*_v1.png`; its unit test pins
  the output, the contact line, distinct silhouettes and the accent hues). They are ours, not the boards': the human
  factory is the barracks hall with a crane arm and a stack, the alien factory the alien barracks flanked by refinery
  pods; the airfield is a landing pad with a hangar; the battery a bank of lime cells on a plinth; the antimatter plant
  the power plant recoloured violet with a taller column (2.32 tiles); the depot an apron of tanks and crates; the lab a
  low block under a glass dome. The dome reads a little CG next to the painted sprites, and the alien depot and battery
  decks are flatter than the boards' alien buildings. (Task 9 of the Kestrel next-level plan redrew the human factory,
  the alien depot and the alien battery; see "Building art honesty" below.)
- Placement ghost: on Kestrel the ghost is a translucent card of the armed kind's painting for your side on the hovered
  hex (60 % opacity), tinted 62 % toward the legacy validity colours (green valid, red invalid; the post chain mutes the
  red toward terracotta), with no cast shadow; it draws without a depth test, so a tall building in front never hides
  its colour; it hides on cancel. Survival keeps the hex cylinder.
  Units are sprite cards too, one per unit (`WorldArt.UNIT_TILES`: infantry 0.98, tank 1.71, anti-armour 1.10, gunship
  2.32, capital 4.02, harvester 1.34): the infantry sprite is itself the boards' three-figure squad, so a squad is one
  card, as the boards draw it. A card never turns; it shows its painting mirrored while it moves against the way it is
  painted facing and keeps its last facing when it stops (the boards draw every unit unmirrored). Units carry the boards'
  silhouette shadow and `.ao` contact band instead of a pad and keep their team ring at the feet; their health bars sit
  just over the painted top. The strategic badge (a coloured plate with I, AR, AT, AIR, CAP or HAR) is not built for a
  Kestrel unit card: the boards draw none, and over a column of squads one hex apart it covered the squad above. The gunship card hovers 0.30
  world units over the ground (`WorldSprites.HOVER`) with its bob; its shadow, contact band and team ring stay on the
  ground under it. The human capital unit uses `capital_v1` (the lab now draws its own `research_lab_v1`).
- Colour: the Kestrel post chain (filmic, exposure 0.95, saturation 0.50, the `gSun` overlay) drew the sprites lighter and
  greyer than the boards (CC body Lab L 45.8 and chroma 5.3 live against 36.5 and 7.3 on gp01). The cards, and only the
  cards, sample a copy of each sprite pre-graded by `WorldSprites.GRADE` (brightness 0.80, contrast 1.02, saturation
  1.60); the live CC now measures L 36.6, chroma 7.2. The post chain is not uniform (it shifts blue a little more than
  red), so other sprites can sit a shade off. Both board shadows (`.shd`, `.ao`) are drawn 1.6 times the boards' CSS
  opacity (`WorldSprites.SHADOW_GAIN`) because the same chain lifts dark ground.
- What still differs from the boards' sprites: each painting has one fixed facing, and a unit moving the other way shows
  it mirrored, so a mirrored sprite's light falls from the wrong side; the cards are flat billboards, so nothing turns
  or shows a side the painting does not have; six building kinds use our composites, not board paintings (see above).
- Placement stays one hex per building, so a big sprite overhangs its neighbours (mostly to the north, where the
  painting rises) and two big neighbours can overlap on screen. Picking follows the painted pixels, not the hex: a click
  must fall inside the screen rectangle of the sprite's opaque pixels and on paint by the sprite's 64 x 64 paint mask
  (a cell holds paint when any pixel in it passes alpha 128, dilated by one cell, mirrored with a unit's card), so a
  see-through gap inside that rectangle (between the CC's towers, under a tank's barrel: about 40 % of a painting's box)
  selects whatever shows through it. A unit holding the click beats any building, then the narrowest building wins;
  between two touching units the nearer root wins, and a click on none keeps the legacy 32 px reach around a root
  (`_pick_entity`). The hover outline draws without a depth test, so it is hidden on a hex a building or unit stands on
  and on a hex whose centre a painted body's box covers on screen (as drawn: lifted for the gunship, mirrored, a site's
  built part): for a CC the hexes north, north-east, north-west and two north of it; the hexes beside and south of its
  base still show the outline.
- Selection draws the boards' ellipse, not the legacy spinning ring. A building takes StructureSelected's (rx 132 and
  ry 46 for a 200 px barracks, centred 155 px below the sprite's top, filled at 8 %), scaled by its painted width and
  drawn on the ground under the painting, so its back arc passes behind the sprite and the front arc wraps the base as
  on the board. A unit card takes CoreAssault's (rx 58 and ry 22 for a 140 px tank, 19 px over its contact line), drawn
  over the painting as that board draws it (z-index above the sprites), flat on the ground, mirrored with the card, and
  under a hovering gunship on the ground. OrdersArmed draws its unit ellipses under the sprites instead; under the
  painting a unit's ellipse, smaller than its hull, would barely show, so CoreAssault's layering is the one followed.
- The camera keeps its 57 degree pitch. The boards are painted at a steeper three-quarter view, so roofs read smaller
  and fronts taller in the live frame. The camera is north-up with a default zoom of 10.
- Home and the deploy shot look 4.1 world units (about 6 columns) east of your Command Center
  (`WorldArt.CAMERA.home_offset`), so the base sits in the left third and the Calder River shows top right. The boards put
  the river mid-frame because their base is about 7 columns from it; on the live map the river is 15 columns east of the
  CC on its row, so base and river cannot both sit where the boards have them at zoom 10. The HUD's HQ jump (the
  `jump_hq` and `hq` actions, `live_adapter._focus_hq`) still centres the CC: it answers an HQ alert, so the fight around
  the CC belongs mid-frame, not at the left edge.
- At deploy the live colony is one CC and four infantry squads; the home-frame boards (gp01, gp04, gp06, gp08) show a
  built-up base with tanks, a refinery and turrets. That gap is content, not art: the scenario and the sim are left as
  they are, so the home frame never shows the boards' full base, and the tank, harvester, gunship and capital cards
  were checked in a QA view with presentation-only spawned cards, not in the deploy frames.
- Props are camera-facing billboard cards drawn from a baked atlas of the game's own painted sprites, with flat soft
  drop-shadow decals. A card takes the depth of its base, so a deposit's crystal card on the hex in front of a CC draws
  over the CC's front ramp (seen with the ore at (7, 11) below the starting CC). Left as is: it is small and correct in
  depth order.
- The sea colour is computed from the distance to the coast in the terrain shader, not painted. The coast follows the hex
  grid, so the bay's west shore is a straight edge and the surf line is thin where the coast is shaded.
- Hollow Wood is one canopy card per forest tile plus a second on every other tile, with wide jitter and a ragged rim of
  canopies on about half of the grass tiles around it (`WorldProps.FRINGE`), so it reads as a wood, not a block.
- The invasion relay label floats above a building's health bars, so it never hides inside the painted sprite.

### Board scores (world_diff, private Xvfb software capture, after the sprite entities plan, 2026-10-05)

| Board | Frame | Baseline total | Final total | Delta | Baseline structure | Final structure |
|---|---|---|---|---|---|---|
| gp01 | home | 46.54 | 80.88 | +34.34 | 73.67 | 79.02 |
| gp03 | enemy | 54.49 | 82.62 | +28.13 | 55.88 | 79.45 |
| gp04 | home | 40.75 | 77.84 | +37.09 | 72.45 | 76.52 |
| gp05 | ford | 55.54 | 80.69 | +25.15 | 69.33 | 77.49 |
| gp06 | home | 50.63 | 80.57 | +29.94 | 74.66 | 80.02 |
| gp07 | ford | 59.89 | 80.30 | +20.41 | 71.27 | 75.71 |
| gp08 | home | 49.14 | 74.38 | +25.24 | 74.22 | 78.53 |

The sprite buildings and units moved every board by less than 1 point against the world-art scores (gp01 80.70, gp03
81.70, gp04 77.94, gp05 80.79, gp06 79.69, gp07 80.42, gp08 74.53): the deploy frames hold one CC, four squads and a
few enemy buildings, so the statistics are dominated by the ground. `tools/ui/world_scores.json` holds this run.

Every board is at least 20 points above `tools/ui/world_baseline.json`. Notes on the weakest:

- gp07 has the smallest margin (+20.41). The `ford` frame centres on Wyllow Ford, so the river runs mid-frame; the gp07
  board has it along the left edge with the Dry Flats filling the rest. The capture frame was not moved to chase the score.
- gp08 has the lowest total (74.38). The board is the power overlay: its cyan network lines and darker grade are HUD world
  marks, not ground, so palette and warmth lose points against the plain live ground.
- Ground swatches against the boards (CIE76 Delta E): grass 1.9, meadow 3.3, flats 1.6, river 5.3, highland 8.2. The
  `ford` frame's grass swatch point (16, 10) now falls under a Hollow Wood rim canopy, so it samples a tree (12.2); on open
  grass it read 2.6 before and the ground albedo did not change.
- `tools/ui/world_scores.json` was refreshed with this run (the user approved refreshing it).
- The review fixes (paint-mask picking, the selection ellipse, the foundation sizing) were captured again the same way:
  every board is within 0.02 of the table (gp01 80.88, gp03 82.62, gp04 77.85, gp05 80.68, gp06 80.56, gp07 80.29, gp08
  74.38), so `tools/ui/world_scores.json` was left as it is. The Survival home frame pairs at 99.77 against its last capture.
- The building variants, the construction reveal and the placement ghost were captured the same way: every board is
  within 0.05 of the table (gp01 80.83, gp03 82.62, gp04 77.84, gp05 80.64, gp06 80.54, gp07 80.26, gp08 74.38; the
  deploy frames hold no variant kind and no site), so `tools/ui/world_scores.json` was left as it is. Draw calls and
  primitives are unchanged (home 25 / 156,776, max 78 / 209,766). Survival pairs at 99.38.

### Combat effects (combat and motion plan Task 2, 2026-10-05)

The user read the hit flash and the death shard ring as blobs. On Kestrel (`world_art_on`) they are now layered flipbook
cards (`godot3d/scripts/world/world_fx.gd`); Survival keeps `_impact_effect` and `_death_effect` untouched. No board draws
combat, so every look here is ours.

- Atlas: `tools/ui/build_fx_atlas.py` writes `godot3d/assets/world/fx/fx_atlas.png` (1024 x 768, 128 px cells; 1024 x 1024 since Task 3 added a shot row) from
  hashed value noise and fixed seeds: fireball (8 frames, a turbulent white-yellow core cooling through orange to a dark
  smoke edge), smoke puff (8 frames), muzzle star, sparks, debris, ember, ground glow, dust ring and a burning-rubble decal.
  Band 0 is human amber fire, band 1 alien teal and magenta plasma. Texels are premultiplied and the import keeps the
  colour of transparent texels (`fix_alpha_border=false`); `test_build_fx_atlas` holds the committed PNG to the script.
- Cards: 64 slots (128 since Task 3) at most over three MultiMeshes (ground decals, smoke, fire), one shared material each: the frame, tint
  and fade travel in the instance data, so a firefight adds three draw calls and no node or material per card. The shader
  blends premultiplied (ONE, ONE_MINUS_SRC_ALPHA): fire, flash and sparks add light, smoke, debris and rubble cover. Fire
  cards also cover a little of what is behind them and pre-grade their saturation by 1.9, or the Kestrel grade (saturation
  0.5, filmic shoulder) washed them to pale yellow. Cards face the camera and sit 1.2 world units toward it (same place on
  screen, drawn over the card they burn on); glow, dust ring and rubble lie flat on the ground (a camera-facing decal was
  cut by the terrain in front of it). A spawn past the cap recycles the oldest card; every card frees itself; idle
  frames draw nothing; an effect outside the view plus 2.5 world units is not drawn.
- Hit (an HP drop): flash and sparks, a small fireball from weight 1, a smoke puff from weight 2 (weight by the struck
  kind: 0 infantry, 1 anti-armour and guns, 2 tanks and harvesters, 3 gunships, capitals, buildings), in the firing side's
  colours. The struck side is known, the shooter is not, so the hit sizes by the target until the shots window (Task 3:
  a shooter the window names now sizes it, and a shot whose impact already landed there draws no second flash).
- Unit death: ground glow, two fireballs, sparks, spinning debris, a two-puff smoke plume, embers and a scorch that
  smoulders 4 s, in the dying side's colours, over the ground point under the card.
- Building death: the painting is hidden the moment the sim drops the building (the node frees at the end of the frame);
  a staged collapse burns on its painted footprint: dust ring and two dust puffs, a rolling fireball (three balls climbing
  over 0.36 s), sparks, debris, a four-puff smoke column rising from 0.5 s to about 5 s and embers over a burning rubble decal that fades
  over 6 s.
- Camera shake and the human-hit tone are those of the legacy effects. The legacy wreck box and the OmniLight flashes are
  not drawn on Kestrel (the ground glow card stands in for the light).
- Cost: idle frames unchanged (home 25 draw calls / 156,776 primitives, max 78 / 209,766). 62 live cards: +3 draw calls
  and +384 primitives (software capture). `WorldFx.advance` with about 60 live cards: 0.16 ms p50 headless on the loaded
  machine; spawning a collapse 0.55 ms. Idle boards against the previous scores: every board within 0.15 (gp01 80.88,
  gp03 82.62, gp04 77.85, gp05 80.68, gp06 80.56, gp07 80.30, gp08 74.38), `tools/ui/world_scores.json` left as it is.
  The GPU firefight budget (10 ms p50) was not measured here: QA never opens a window on the user's display.

### Firing effects (combat and motion plan Task 3, 2026-10-06)

Firing used to show nothing but the target's hit flash. On Kestrel every round in the bridge's `shots` window (Task 1:
`[tick, ax, az, tx, tz]` rows, Fixed bits, the last 18 ticks) is drawn from its real shooter to its real target.

- Look per shooter (`WorldFx.shot`): a muzzle flash, then a stretched card turned along the shot's screen direction that
  flies muzzle to target, then an impact flash and sparks when it lands. Infantry, gun and AA turrets and any unknown
  shooter fire a short bright tracer (pale yellow core, amber halo); tanks, anti-armour and capitals a slower glowing
  shell with a short trail, a muzzle puff and a small impact fireball; gunships paired short bursts side by side; aliens
  fire plasma bolts (a teal core in a magenta rim) in each of those styles. Flight times follow the distance (rifle about
  26 world units a second, shell 10) within fixed bounds. Muzzle and impact sit a share of the card width over the
  ground point (a gunship adds its hover). The three shot sprites are a fourth atlas row per band (tracer, shell, bolt,
  vertical streaks with the head up). Streak and flash tints run over 1 so they read on sunlit grass.
- Dispatch (`earthfront_3d._dispatch_shots`, on the poll, before the entity sync): each row is drawn once. The dedup set
  is keyed by the row plus its repeat count in the poll (two shooters on one spot in one tick both draw) and pruned to
  the 18-tick window; a paused game re-sends the same window and draws nothing; a fresh scene's first poll only seeds the
  set (that window is history, possibly of a sim about to restart); a tick lower than the last clears it. Short,
  non-numeric or out-of-window rows are skipped; a snapshot without `shots` (Survival, an old bridge) draws nothing. A
  shot with neither end in view is skipped; past 24 new shots in one poll the oldest are dropped, never drawn late. A
  poll's shots replay at their ticks' rhythm (delays up to 0.6 s), so a 30 Hz fight read at 8 Hz does not flash in
  bursts.
- Shooter: the nearest unit or building within 0.6 tiles of the shot's start, among the snapshot's entities and then the
  `bridge_nodes` it no longer lists (a shooter killed this tick); none gives the infantry look on the target's enemy
  side. The impact sits over the target the same way when one is found.
- Recoil: a unit shooter's card kicks back along the ground, away from its target (0.02 to 0.055 world units by kind),
  over 0.1 s and comes home exactly. Only the card moves (x and z: the gunship bob owns y), never the root, so the pick
  box, the bars and the selection ellipse stay put. Buildings do not recoil.
- Pause: while the pause menu holds the sim (`set_sim_paused`) the effects clock stands still, so a round in flight
  hangs where it was and flies on from there on resume; recoil runs on the same clock.
- Everything here is cosmetic: no gameplay state, selection or HUD value is read back from it.
- Cost: idle frames unchanged (home 25 draw calls / 156,776 primitives, max 78 / 209,766); a volley of nine shots in the
  software capture added 2 draw calls and 512 primitives over the same frame before it. A 30-shots-a-second firefight
  through the real dispatcher (8 Hz polls of the 18-tick window, 60 entities, headless on the loaded machine):
  `_dispatch_shots` about 0.68 ms per poll (p50, about 0.09 ms a frame amortised), `_advance_fx` 0.16 ms p50 and 0.21 ms
  p95 per frame, peaking at 87 live cards, which is why the pool doubled to 128. Idle boards against the previous scores:
  every board within 0.15 (gp01 80.88, gp03 82.62, gp04 77.84, gp05 80.70, gp06 80.57, gp07 80.31, gp08 74.38),
  `tools/ui/world_scores.json` left as it is. The GPU firefight budget was not measured (no window on the user's
  display).

### Movement animation (combat and motion plan Task 4, 2026-10-06)

A Kestrel unit used to slide between its 8 Hz positions as a still painting. A moving unit's card now moves as its kind
moves, and the ground under it answers.

- Looks (`WorldSprites.animate`, one table `WorldSprites.ANIM`, one row per kind): infantry a stride bob (the card's
  height swings once a footfall, a step every 0.62 world units) with a slight lean into the motion and a side-to-side
  rock; anti-armour teams walk the same way with a longer, heavier step and a small lurch as they set off (the plan said
  rumble, but the painting is a team on foot, and an engine rumble on it read wrong); tanks an engine rumble (two
  mixed sines near 11 Hz) and a start/stop lurch (stretched along the motion and leaning back as they pull away,
  squashed and dipping forward as they brake); harvesters a heavy sway with a softer rumble and lurch; gunships a forward
  tilt into the motion with a slow sway; capitals a slow, heavy sway, a faint rumble and a lurch. At normal zoom
  (infantry about 40 px) the amplitudes are a few pixels: an infantry top swings about 3 px either way, a tank rumbles
  about 2.5 px, a gunship tilts 7 to 12 px forward, a capital sways about 6 px. Amplitude grows with ground speed and is
  zero at a standstill.
- How: the card is reshaped about its contact line (a shear of its height into x, and a scale of its width and its
  standing height), so the painted feet and tracks and the ground strip never leave the terrain. No per-unit material,
  no extra node. A gunship's shadow and contact band are moved under the tilt so they stay on the ground under it.
- One rest, layered movers: the first mover to start (a firing kick, the walk) records the card's rest transform; the
  walk, the recoil kick and the gunship bob are layers over it, and `_lift_unit_card` moves the rest itself. A unit
  that stops returns to exactly that rest (within 1e-5) and drops all pose state; a kick during a walk comes home to the
  walk, not to a mid-stride frame. Picking, the selection ellipse, the bars, the badge and the crown read the rest
  (`card_width`, `rest_lift`), never the reshaped card.
- Driving it: `_glide_bridge_nodes` starts tracking a unit only when its root actually moved this frame;
  `_animate_unit_cards` smooths each tracked root's own per-frame step (0.18 s) into a ground speed, a heading and an
  acceleration, and drops the unit once it is still and settled. Idle frames cost one emptiness check.
- Dust (`WorldFx.dust`, `WorldFx.wash`): a moving unit raises small soft puffs of pale sandy dust (the smoke sprite at
  `KICKED_TINT`) behind it at the ground, alternating either side of its path, at a spacing by kind: a tank every 0.2
  world units and wide, a harvester and anti-armour close behind, infantry light and sparse. A moving gunship leaves a
  rotor-wash ring spreading flat on the ground under it and two puffs blown aside. Dust is the lowest priority card: it
  spawns only while fewer than 80 of the 128 cards are live, so it never takes a combat effect's slot. Survival keeps its
  grey sphere puff.
- Pause: while the pause menu holds the sim, Kestrel stops the glide and the walk too (`_glide_bridge_nodes` and
  `_animate_unit_cards` skip while `sim_paused`), so walkers freeze mid-stride with the rumble, sway, recoil and
  effects; no dust rises while paused. The gunship's hover bob runs on the frame clock, as before, and keeps bobbing.
  Survival is unchanged: its units still finish their last glide while paused. Every pause in the game goes through `set_sim_paused` (the pause menu and the controls page over play);
  the HUD speed buttons do nothing on the bridge, and nothing sets the tree's pause or the engine time scale.
- Status bars: on Kestrel the health and shield bars cast no real shadow. Each shown bar used to throw a dark stripe far
  across the ground, nowhere near its owner (the dark bars in the Task 3 captures were the alien squad's and the CC's
  bars). The era crown's rod (era 1 and up) did the same: a software capture with every rod casting shows a thin dark
  stripe on open grass with no caster near it, gone with the rod's shadow off. It casts none on Kestrel now (the ring
  already cast none); Survival's crown rod still casts.
- Cost: idle unchanged (home 25 draw calls / 156,776 primitives, max 78 / 209,766); twelve units marching in the
  software capture added 2 draw calls and 512 primitives (the dust layers). 60 units of every kind marching at 60 fps
  with 8 Hz polls, headless on the loaded machine: `_animate_unit_cards` (poses and dust) about 0.27 ms p50 and
  0.46 to 0.50 ms p95 per frame (load average 4 to 16), live cards held at the 80-card dust room; idle 0 ms. Idle boards against the previous
  scores: every board within 0.15 (unchanged from Task 3); Survival pair 99.41.

### HUD icon truth (Kestrel next-level plan Task 1, 2026-10-06)

- On Kestrel (`world_art_on`) every building and unit icon in the HUD is the kind's own painted world sprite, one mapping
  (`LiveAdapter.icon_path_for_building` / `icon_path_for_unit`, reading `WorldSprites.SPRITES` and falling back to the
  generic icon only when no sprite file exists). It feeds the build deck cards, the placement preview, the queue card, the
  strike-group chips and the selected-structure, roster and queue cells (`vm_gameplay._sprite_path`). Before this the deck
  showed stand-ins: vehicle factory = barracks, airfield = gunship, supply depot = foundation slab, research lab = capital,
  battery = reactor; the group chips covered four unit kinds and the capital and harvester got a generic icon.
- The queue card shows what the selected structure is producing (its `production_name` is a unit kind), not a foundation slab.
- Survival keeps the legacy table (`BUILD_CARDS` field 7, `GROUP_SPRITES`, `foundation_v1` on the queue card) byte for byte:
  the adapter reads the game's `world_art_on`, which is false there.
- Gallery fixtures: `fixtures_build.gd` (the Build board and the gp boards that reuse it) shows the world sprites for the five
  stand-in kinds, the placement preview and the queue card. `fixtures_gp.gd` already used each kind's own sprite. The mock
  itself still draws the old stand-ins, so the Build board's rectangles that contain those icons moved toward the mock's
  worse side by a little: placement panel 6.38 to 8.47 (limit 9.53), deck cards 6.21 to 7.31 (9.21), deck queue 6.39 to 7.09
  (9.39). No limit was loosened and no other rectangle of any screen changed.

### Kestrel opening (Kestrel next-level plan Task 2, 2026-10-06)

Rust, `crates/core/src/game/scenario.rs` only (plus bridge test expectations and the regenerated fixture). Survival and
the golden hash are unchanged.

- The human side starts with a working base, all fully built on buildable, passable ground beside the Command Center
  (7,9): Power Plant (5,8), Refinery (6,11), Barracks (9,7), one Harvester (6,12) and the 4 riflemen (ids 1 to 4 kept).
  Power is 90 kW for 30 kW of demand. The Refinery sits within 1 hex of the ore at (7,11), so it carries the +20% bonus.
- The Harvester mines and unloads without moving: the ore and the Refinery are both in its reach from its start tile, so
  its cargo cycles and money rises (about 28 credits per 60 ticks on its own) while it stands still. A QA session that saw
  "the harvester never moved" was seeing this, not a stalled economy (Task 10 playthrough).
- Start credits 1200 (was 1800): the free stock is worth 590, so the player gets no net windfall. The alien side keeps 1800.
- Wave one spawns at 2:30 (tick 4500, was 1:30). The wave interval and sizes after it are unchanged.
- A scripted alien probe (three riflemen, ids 9 to 11, `Scenario::scripted_commands`) moves to a picket by the ford at
  0:55 (tick 1650) and attack-moves on the human building nearest it at 1:50 (tick 3300). First contact is about tick 3412
  and the first structure hit about tick 3461 (1:55), usually the Barracks. The orders are ordinary commands, so they
  replay from the command log; only the bridge calls `scripted_commands` today, so another host must add that call.
- Probe warning under fog (fix round after the final review, I1): the picket cells (25,9), (25,10) and (26,10) lie
  beyond human sight (about column 19 at the start), so with the Task 6 fog the probe was never seen before it struck and
  the staged "first-minute warning" was lost. The client now gives it as scouting intel at the stage tick
  (`godot3d/scripts/world/kestrel_intel.gd`, `PROBE_STAGE_TICK` 1650, pinned to `scenario.rs` by
  `test_kestrel_intel.gd`): one toast "Scouts report movement near the ford" with the existing `alert` sound, placeless,
  once per run, re-armed when the tick goes back on a restart, never repeated on a re-delivered snapshot, and silent if
  the first poll is already past the strike tick. It adds no minimap ring, no alert ping for Space and no camera move,
  so it reveals nothing the fog hides (the briefing already names the ford and the probe). Kestrel only.
- The alien AI stays asleep until wave one (the bridge gate `waves_survived() > 0` is unchanged); the probe is the only
  pre-wave pressure.
- An idle player loses: the probe takes the Barracks, then wave one plus the probe take the Command Center at about 2:45
  (tick 4959). The starting riflemen by the CC do not react to the Barracks being hit (out of acquisition range); the
  objectives task added a "<structure> under attack" alert for that.
- The defended AI playtest changed shape: the gifted Harvester feeds a playtest AI that never trains one, so it now wins
  outright (tick 13622, 2 waves) instead of holding 3 waves. Its assertion is "never overrun before wave 3, or a human
  win" (`KESTREL_DEFENDED_WAVES`).

### Kestrel objectives and briefing (Kestrel next-level plan Task 3, 2026-10-06)

- On Kestrel (`world_art_on`) the Survival-era tutorial (ten stages, "Secure the landing zone" to "Counterattack") no longer
  runs. Its stages never fit the prebuilt opening: stage 0 jumped to 1 at once, stages 3 and 5 were satisfied before the
  player did anything, and the survey and landing-zone copy never applied. `godot3d/scripts/world/kestrel_objectives.gd`
  derives five objectives from the snapshot instead: Power the base, Start the economy, Raise a squad, Hold the ford, Break
  the Core Node. The HUD objectives card (cap "Kestrel Reach"), the first-minutes briefing and the "Mission updated" toasts
  read it. Survival keeps `_advance_tutorial` / `_update_tutorial`, `OBJECTIVE_GROUPS`, `STAGE_DETAIL` and the
  "Operation Dawnshield" card byte for byte; `_process` calls the tutorial only when world art is off.
- The first objective is already met at the start (the prebuilt Reactor gives 90 kW for 30 kW of demand), so the card and
  the briefing show it done from the first frame (the top bar's Power chip carries the numbers). It reopens if the Reactor
  falls or demand outgrows generation before wave one, and its line then names the shortfall ("Build a Reactor (P): 10 of
  30 kW", "Power short: 90 of 120 kW, build a Reactor (P)").
- Before wave one the setup objectives are judged live (a lost Reactor, Refinery, Harvester or rifle squad reopens its line,
  toast "Objective reopened"); once wave one has spawned they stay done.
- "Hold the ford" (fix round after the final review, I2): the sim's `waves_survived` counts waves that have spawned
  (`Sim::waves_survived`), so on its own it only says wave one is on its way; the Task 10 playthrough saw the objective
  tick done at 2:30 with the wave still on the far bank. The objective now needs wave one beaten: spawned at least 600
  ticks (20 s) ago, no visible non-human unit on the home side of the ford (cell column at or west of the ford region's
  `x1`) for 300 ticks (10 s), the base alive (no other winner); or a second wave has spawned. Attackers that reach the base
  are inside human sight, so they are in the snapshot's `entities` even under fog, and the alien side beyond the ford never
  counts (fog off shows it all). The spawn tick, the last tick an attacker was seen and the held flag are latches carried
  through the previous result, so a held ford stays held and a restart (the tick going back) clears them. While the wave
  is on its way the line reads "Wave one crossing at Wyllow Ford". This is presentation only and reads only visible
  entities.
- The briefing (board 6 card) stays up for the first three objectives. Its paragraph is first-minutes intel: the ore beside
  the Command Centre, the ford wave one crosses and its mission time (2:30) and the alien probe that may strike sooner
  (the Core Node's cell was cut in the fix round so the paragraph fits its three lines). The gallery's board 6 keeps the tutorial's briefing (its mock draws that copy), so no pixel gate moved.
- Command tabs follow a new objective as the tutorial's did: Raise a squad opens Units, Hold the ford and Break the Core
  Node open Orders. A reopened objective leaves the tab alone.
- New on Kestrel: "<structure> under attack" (a hostile toast) when a human building loses HP, at most one every 5 s over
  all structures and one every 15 s per structure, with the hit's existing shake and tone. Task 2 found that idle riflemen
  never react to a structure under fire. The latest hit's position and cell are kept (`live_adapter.last_structure_attack`)
  for the minimap work in a later task.
- On Kestrel the alert toasts are the HUD's top layer (`Hud.raise_alerts`). Their column (x 12 to 312 from y 520) is where
  the left card stack ends once the six-line objectives card and the wave panel are up, and the first QA capture showed
  "Barracks under attack" and "Enemy signal detected" hidden under the wave panel and the territory card. A toast now
  covers those cards for its 9 s instead. Survival keeps the fixed section order.

### Kestrel sound (Kestrel next-level plan Task 5, 2026-10-06)

Nothing below was listened to. Every Godot run (tests, captures, QA) used `--headless` or `--audio-driver Dummy`; the
decisions are checked by tests and by the pool's `[audio]` log (`EARTHFRONT_AUDIO_LOG=1`), not by ear.

- On Kestrel (`world_art_on`) the game asks `scripts/audio/audio_director.gd` (pure logic) for every sound, and
  `scripts/audio/audio_pool.gd` plays what it allows, using Task 4's generated set (`assets/audio/sfx/`). Survival has no
  director and keeps `_play_tone`, `_impact_effect`, `_death_effect`, `_setup_audio` and `_play_deploy_sound` byte for byte
  (SHA pins in `test_world_art_survival.gd`).
- Pan: `AudioStreamPlayer` has no pan, and the camera is orthographic, so there are no 3D players. The director's pan
  (-0.8 to 0.8 from the camera's ground rectangle, yaw 0 so world x is screen x) picks one of five SFX buses, `SFX_L2`,
  `SFX_L1`, `SFX`, `SFX_R1`, `SFX_R2`, each with an AudioEffectPanner at -0.8, -0.4, 0, 0.4, 0.8. The layout is
  `godot3d/default_bus_layout.tres` (also `UI`, `Ambient`, `Music`); Godot loads it by name, so `project.godot` is unchanged.
- Players: 16 SFX, 1 UI, and one per loop bed (rotor, tread, foot), 3 more than the plan's 16 plus ambient plus UI, so a
  loop never steals a one-shot's voice. The scene's existing ambience player moves onto the `Ambient` bus, which the
  director ducks by 9 dB under large explosions, collapses, alerts and wave calls, recovering over 1.5 s.
- Off-screen: a sound more than 2.5 world units outside the view (WorldFx's margin) is skipped. Inside the view it falls
  to 3 dB down at the edge; past the edge it goes from 6 dB down to 15 dB down at the margin's outer edge. Zooming out
  trims world sounds by up to 6 dB. Announcements (wave, alert, unit ready, build complete, UI) are global and centred.
- Light hits (WorldFx weight under 2) are silent; the shot already sounded. The legacy human-unit-hit tone (section 9,
  combat effects) is dropped on Kestrel, and the structure alert (Task 3) now sounds `alert` instead of a tone; its shake
  and cooldowns are unchanged.
- Sounds that come with an effect (hits, deaths, collapses, shots) are asked for only when WorldFx actually drew the effect,
  so they share its view culling and caps, and a snapshot delivered twice does not sound twice.
- The cues Survival also has map to the nearest new sound: deploy to `select`, science complete to `build_complete`, a
  win to `build_complete`, a loss to `wave_inbound`, the ten-second wave warning to `alert`.
- UI click and hover cover the HUD's own buttons (`hud.action` and the hovered `BaseButton` inside the HUD), not the pause
  and research menus. UI sounds still play while the sim is paused; effects and loops pause and resume.
- `tools/ui/run_cap.sh` now passes `--audio-driver Dummy` (`launch_ui.py` already did), pinned by
  `tools/audio/test_quiet_launchers.py`. The three loop imports use `compress/mode=0` (lossless) so the forward loop has no
  codec seam.
- The 18 sounds are synthesised by `tools/audio/build_sfx.py` (Task 4: numpy only, fixed seeds, CC0 by construction, 16-bit
  mono 44.1 kHz WAV, about 1.7 MB, manifest `godot3d/assets/audio/sfx/sfx_manifest.json`). Rerunning it rewrites the same
  bytes; NEXT_STEPS.md has the regenerate and re-import steps.
- Fog (Task 7) adds one more gate: a world sound whose point is not visible now or on the previous poll is skipped, so an
  unseen fight is silent.

### Kestrel fog of war in the client (Kestrel next-level plan Task 7, 2026-10-06)

This reverses the "full battlefield, no fog" rule for Kestrel Reach only (NEXT_STEPS.md has the dated note). The fog is
presentation only: the sim and the AI stay omniscient. Survival is untouched (no mask, no shroud, no fog node; its noise
ground shader keeps its SHA pin). `EARTHFRONT_FOG=0` sends an all-visible mask, which the client treats as no fog, so the
frame draws exactly as before (the fog branch in each shader is off).

- The rule: the ground and the props are shaded by the mask; entities exist only when the bridge sends them (in sight, or
  a remembered structure flagged `remembered`); effects and world sounds are skipped at spawn when their point is not seen
  now or on the previous poll. An unseen enemy sprite is never drawn because it has no node.
- `scripts/world/fog_view.gd` (pure) reads the mask (0 unseen, 1 explored, 2 visible). An empty or wrong-length mask is no
  fog, without a warning. Points off the grid read the nearest edge cell. Its L8 texture (one texel per cell: 0, 128,
  255) is rewritten only when the mask string changes, and the same texture object is shared by every material.
- Shroud: the Kestrel ground shader and both prop shaders (cards by their foot, so a tree is shrouded or lit whole and a tree
  standing just in the dark can show as a dark silhouette over lit ground; decals per point) sample the mask through the shared `FogView.SHADER_FUNCTIONS`: the two nearest columns at their texel centres (an
  odd column half a row lower), a linear blend along the rows and a smoothstep across, so edges are soft and clamped at
  the map edge. Past the north and south edges the value fades within a row into a sliding mean of four columns: the
  edge row of a sight disc alternates seen and unseen cells, and a clamped column ran on over the margin as a stripe.
  The off-map margin therefore continues the nearest edge's shading (lit beside a seen edge, an even dim band where the
  edge row is mixed). `FogView.sample` mirrors `fog_at` for tests. Unseen is near black with a little blue, explored is about half brightness and slightly desaturated,
  visible is untouched; water specular fades in the shroud. No new shader was added (the fog is a uniform branch in shaders
  already drawn from deploy), so nothing new needs warming.
- The minimap is a SubViewport of the same world, so it shows the same shroud; its marks come from the entity nodes, which
  hold only what the player knows.
- Sight changes are silent: an enemy that leaves sight vanishes with no death, log line or sound; one that comes back is
  revived without a deploy ring or "unit added" (a seen-ids set, cleared when the tick goes back on a restart). An enemy
  unit that vanishes deep inside sight (its possible step since the last poll stays visible), or where a drawn shot just
  landed, died and explodes as before; an enemy building gone from a visible cell collapses. A first sighting is
  announced only when the ground was already in sight and, for a unit, it stands deep inside it (it was made there).
- Remembered structures: drawn at `WorldSprites.MEMORY_SHADE` (0.55) through one shared memory material per painting (a
  site card darkens its own site material's new `shade` uniform), with no health or shield bar, no era crown, no relay
  status ("INVASION RELAY" only), never picked or targeted, no combat preview or hostile pin, no HP diamond in the assault
  marks, and "CORE LAST SEEN" instead of its HP. Damage it took while unseen draws no hit when it is seen again.
- Panels under fog: Enemy territory shows Defences (known structures, "Not scouted" before any), Garrison "N units in
  sight", Memory "N last seen", Scouted "N% of the map", and shows before contact. The wave panel, wave card, objectives
  line and assault relay strip show the relay total (`alien_relays`, briefing intel), never `active_alien_relays`. The
  strategic map shrouds unseen hexes, dims explored ones and remembered sites, and adds an Explored percent row. The
  Kestrel briefing's probe sentence ends "from the dark east bank" (it was a separate sentence, "Their side stays dark
  until your units scout it.", until the fix round folded it in to fit the card). The title's Visibility fact reads "Fog of war,
  scout the alien side" once a fogged snapshot arrives (the gallery title board shows that copy). `hash` is never shown.
- Deposits: resource pins still show over unseen ground, because the bridge sends deposits as the briefing survey
  reported them and refreshes them only where the player can see (Task 6); amounts in the dark are the last known.
- Gallery: gp08 (logistics) and gp11 (strategic map) read the EARTHFRONT_FOG=0 twin fixture, since their boards draw the
  alien base, which the fogged start hides.
- Ore buffer chip (fix round, review I3): the bridge writes a service row carrying the sim's refinery capacity (300) for
  every shown entity, units and enemies included, and the chip summed them all, so it read "300 / 2700" and worse, jumped
  as enemies came in and out of sight (a rough enemy count under fog). On Kestrel the denominator now counts only
  finished human Refineries (`live_adapter._kestrel_ore_capacity`), tested on the fogged and the fog-off fixtures (both
  "/ 300"). Survival keeps the old sum.

### Kestrel minimap interaction (Kestrel next-level plan Task 8, 2026-10-06)

Kestrel Reach only (`world_art_on`). The Survival minimap keeps `MOUSE_FILTER_IGNORE`, has no rings, and Space does nothing
there; its world SHA pins are unchanged.

- Click to jump: a left press on the minimap (Main 288x250, Build 322x222, Core assault 216x192 slots) maps the pointer
  through the minimap camera's own rect (`minimap_world_rect`, height MINIMAP_SPAN, width by the slot aspect, so the
  letterbox is handled) to a ground point and moves the camera focus there at once, clamped by the same
  `WorldArt.clamp_focus` as panning (current zoom limits, aspect, yaw, art bounds). A press in the letterbox outside the
  map rect (`map_world_rect`, the hex extent) does nothing. Holding the button and dragging keeps jumping, clamped to the
  map edge. The drag clears on release, on any motion with the button up, on window focus loss, on pause and when the
  screen blocks the world (research, scrim, menus). A release the viewport saw but the minimap never got (live QA: the
  click that also focuses the window loses the GUI's mouse focus) ends the drag on the next frame.
- Clicks never fall through: the minimap control accepts every button event over it (left, right, middle, wheel), so the
  world never selects, orders or zooms from a minimap click. A right click issues no order. A stray release with no drag
  in progress passes on.
- Armed orders: a left click on the minimap moves the camera only; a build ghost, attack-move or rally stays armed, so the
  player can jump and then place or order on the main view.
- Alert rings: when a human unit or building loses HP the client adds a ring at its ground point (`scripts/ui/alert_pings.gd`,
  pure). A ring lives 3 s and pulses once a second (radius 3 to 15 px, alpha falling with each pulse, the last 0.6 s
  fading), in `T.BAD` with a small `T.BAD_HI` core, drawn by `map_marks.gd` in its one `_draw` (no node or material per
  ring). A hit within 1.5 s and 3 tiles (2.1 world units) of a live ring adds none; at most 6 rings at once (the oldest
  goes). The clock is the effects clock (`WorldFx.time`), which stops while the sim is paused, so rings freeze with the
  game; the pulse depends on the ring's age alone. The marks hash carries each ring's hit time, not its phase, so the HUD
  section rebuilds only when rings come and go and `set_clock` redraws them per frame.
- Space (`Keybinds.JUMP_ALERT`; it had no binding: no InputMap action, no Keybinds constant, and the HUD's buttons take no
  focus, so `ui_accept` never sees it) frames the newest alert; pressing again within 2.5 s steps to older ones (5 kept,
  no two within 3 tiles), wrapping round. With no alert it does nothing and shows no toast. Blocked like other world keys
  while a screen is over the world.
- The alert chip: `VmGameplay.next_alert` keeps the wave timer and adds a Space key cap once there is an alert to jump to;
  its border turns red while a ring is live. With no timer it reads "Last alert".
- Fog: rings come only from human-owned entities, which are always in sight, so they say nothing about hidden enemies.
- Controls screen: Kestrel lists "Jump to alert" (Space) and "Jump on minimap" (Click map) under Camera. The gallery gp10
  board and Survival keep the old rows, so their pixel gates are unchanged.
- Not unit-tested: GUI routing of a real click to the minimap control (the test runner's tree is not live). It was checked
  live on a private Xvfb with real X pointer events (xdotool): press, drag, release, right click, a second click and Space
  with no alert, the army selected throughout and no bridge command written.

### Building art honesty (Kestrel next-level plan Task 9, 2026-10-06)

The six composite kinds per side are ours, built by `tools/ui/build_building_variants.py` from crops of the boards' own
sprites plus PIL drawing, deterministic, no outside art. Task 9 measured how far each one really is from the sprite it
was built on, with a hue free structure distance (`structure_distance` in `tools/ui/test_build_building_variants.py`):
each sprite is cropped to its opaque box and stretched to 128 x 128; silhouette is 1 minus the intersection over union of
the masks; edges compares the blurred Sobel maps of the value channel max(R, G, B). A copy with every hue turned half the
wheel scores 0 on both, so a recolour cannot pass. Over the 42 same-side pairs of genuinely different board buildings the
10th percentile is 0.31 silhouette and 0.30 edges; the closest pair (human command centre and barracks) is 0.19 / 0.27.

- Redrawn (they read as recolours before):
  - Human vehicle factory: was the barracks hall widened (0.24 / 0.29 to the barracks). Now a long saw-tooth roofed hall
    with smoked glass, a bay door with a tank in the opening, hazard striped posts and sill, a yellow gantry lifting a
    crate, an amber tank sign and a ramp: 0.35 / 0.37 to the barracks, 0.33 / 0.37 to the alien factory.
  - Alien supply depot: was the human depot's slab relaid in alien plate (0.08 silhouette to the human depot). Now a relay
    yard: three tall cylindrical stores with a gold glyph beacon, a hoist mast whose claw jib swings a crystal cage,
    carapace cargo cells stacked two high, a gold guide line on the apron: 0.42 / 0.39 to the alien refinery, 0.34 / 0.39
    to the human depot.
  - Alien battery: was the human battery's cell bank in alien plate (0.07 silhouette). Now a clawed drum with twin
    capacitor coils (stacked fins, lime orbs, an arc between them) whose charge slots glow lime: 0.45 / 0.38 to the alien
    power plant, 0.47 / 0.38 to the human battery.
  - The three differ from each other by 0.41 to 0.53 silhouette. Their opaque ground boxes keep the old bottom row (within
    1 px), width (within 16 px) and centre (within 4 px), so `WorldSprites.MOCK_PX`, `WorldArt.BUILDING_TILES`, the anchor,
    picking, the pad and the bars are unchanged and no pin moved. The factory glass is a smoked steel blue (kept under the
    accent saturation) so amber stays the factory's only accent and cyan stays the labs'.
- Still read as recolours (not fixed in Task 9, honest list):
  - Both antimatter plants: the power plant recoloured violet with a taller column (human 0.22 / 0.25, alien 0.14 / 0.17
    to their power plants). At board scale they read as violet reactors.
  - Alien vehicle factory: the alien barracks flanked by refinery pods (0.25 / 0.29 to the alien barracks).
  - Human supply depot and human battery: one apron layout with different props (0.18 / 0.30 between them).
  - The two airfields share one layout across the sides (0.13 silhouette between them), though each is far from the
    barracks it was cropped from. Both research labs are their side's command centre body under a glass dome (0.23 / 0.22
    to the CC).
- Scoreboard (fog off, private Xvfb software capture): every board within 0.09 of the Task 2 scores; the boards hold no
  factory or battery, and the alien depots of the fog-off start are at board scale in the enemy shots.

### Unit aim lean (Kestrel next-level plan Task 9, 2026-10-06)

- A Kestrel unit that fires leans toward its target's side for 0.25 s (`WorldSprites.aim_lean`, `aim_lean_step`): a
  rotation in the card's own plane about the painted base, rising over the first 35 % and settling back, both eased.
  Peak by kind (`AIM_LEAN_DEG`): infantry and anti-armour 5 degrees, tanks and capitals 4, gunships 6, capped at 6
  (`AIM_LEAN_MAX_DEG`). The peak scales with the horizontal share of the shot (a target straight north or south, or
  straight below, gives no lean), and its sign follows the target's side of the screen. At normal zoom an infantry
  top moves about 3 to 4 px.
- It is driven by the same shot as the recoil kick: `_dispatch_shots` calls `aim_lean` beside `kick` with the same
  vector and start time, so a lean faces the real target and never happens without a drawn shot. `_advance_fx` steps it
  with the kick on the effects clock, which stops while the sim is paused (`set_sim_paused`), so the lean freezes with
  the game and resumes where it was.
- It is one more pose layer (`pose_aim`) over the shared rest: the final transform is the walk shape times the lean, plus
  the kick and bob. The base lifts by the painted base's half width times the sine of the angle on the leaning side, so
  the near corner stays on the ground. At the end every lean meta is dropped and the card returns to exactly its rest
  (or the walk's shape), with no residual.
- Shadow and contact band are counter-moved so they stay where the unleaned card puts them; picking, the selection
  ellipse, the bars, the badge and the crown read the rest, never the leaned card. Buildings (turrets included) never
  lean; harvesters have no weapon, so they draw no shot and never lean. Survival is untouched (no shots go through this path there; its SHA pins are unchanged).
- Cost: idle frames unchanged (all nine scoreboard shots have Task 8's draw calls and primitives, except enemy +1 / +256,
  an effect card caught in flight); the lean adds one basis product per recoiling card per frame.
