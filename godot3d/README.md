# Ascension: Earthfront 3D client

This is the Godot 4.7 client, the shipped way to play Ascension. The deterministic Rust simulation remains the
authoritative gameplay layer: `godot-bridge` (built from `crates/server`) steps it, writes a snapshot under `runtime/`
and reads the client's commands back. The client draws that state and owns everything presentational: a title screen with a
map picker and a Settings screen (volumes, fog of war, window mode, saved to `user://settings.cfg`), the command deck HUD,
pause menu, controls reference, research directorate, strategic map and debrief (Restart, Main menu, Quit), and audio
on SFX, UI, ambience and music buses.

It plays two maps. **Kestrel Reach**, the default, is the hand-authored coastal basin: a ground-layer terrain model with a
river, the Wyllow Ford, highland, forest and a bay, world sprites and props, a tile inspector, territory card,
Logistics lenses, briefing and objectives, and a presentation-only fog of war. **Earthfront Survival** is the original
generated map and shows the whole battlefield. Existing vehicle and alien models remain prototype assets.

Start it from the repository root with `./run-3d.sh`, which builds and starts the bridge first. To start only the client
(the bridge must already be writing `runtime/snapshot.json`):

```bash
../tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path .
```

Controls: the arrow keys pan (the cursor at a screen edge and a middle-button drag pan too), Z/E rotate, mouse wheel zoom,
left-click or drag-select, right-click to move units or set producer rally points (the structure panel's Set rally button
arms the next left click, Esc cancels it; it adds no key), A attack-move (the banner says to right-click the destination),
F2 select the whole army, . select an idle crew, Ctrl+1 to Ctrl+9 save a control group and 1 to 9 recall it,
On Kestrel Reach S stops the selection, D holds position, Z cycles its stance (aggressive, defensive, hold; Z does not
rotate there, the yaw is locked) and a right click on an enemy in sight attacks that target. Shift + right click (after
A too) queues a waypoint leg behind the current order, up to eight legs a unit counting the one under way; the selected
units' queued legs show as a thin path with a disc per leg (red for an attack-move leg). Any plain order, S or D clears
the queue. (The Controls screen has no row for it: Kestrel's Orders column has no room left.)
T/K/V/H/X train infantry/armour/anti-armour/gunships/capital units,
P/R/B/N/I/O/L/,/G/J/C place reactor/refinery/barracks/vehicle factory/airfield/supply depot/research lab/battery/gun turret/AA battery/wall,
Y opens the real-time science directorate, Q casts tactical abilities, U repairs, and Delete sells. Esc with nothing armed opens the pause menu (the bridge stops stepping while `pause.flag` exists in its runtime directory; its Terrain guide button shows the ground table), F1 opens the controls reference and M opens the strategic map (no pause; Esc or M closes it); all read their keys from `scripts/ui/keybinds.gd`. Survival shows the entire
battlefield. Kestrel Reach has a presentation-only fog of war (the bridge's `fog` mask: unseen ground shrouded, explored
ground dimmed, enemies only in sight, enemy structures remembered dimmed); `EARTHFRONT_FOG=0` turns it off. Press `F` to focus the current selection and `Home` to return to the Earthfront command district.
