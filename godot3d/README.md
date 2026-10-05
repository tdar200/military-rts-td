# Ascension: Earthfront 3D client

This is the high-fidelity presentation frontend targeting a richly modeled,
stylized 3D strategy-map look. The deterministic Rust simulation remains the
authoritative gameplay layer; this client includes continuous shader-blended coast/river terrain and landmark mountains, cinematic camera controls, lighting, terrain-conforming illustrated faction districts, era-reactive infrastructure, terrain-following roads, irregular borders, named world landmarks, animated resource fields, strategic unit badges, formation overlays, production command art,
modeled cities, units, combat, strategic UI, and a bidirectional live-state
bridge carrying economy, supply, shields, and the ten-era science progression.

Run it with:

```bash
../tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path .
```

Controls: WASD pan, Z/E rotate, mouse wheel zoom, left-click or drag-select,
right-click to move units or set producer rally points (the structure panel's Set rally button arms the next left click, Esc cancels; it adds no key), A attack-move (the banner says to right-click the destination),
F2 select the whole army, . select an idle crew, T/K/V/H/X train infantry/armour/anti-armour/gunships/capital units,
P/R/B/G/J/C/L place power/refinery/barracks/turret/AA/wall/lab, Y opens the
real-time science directorate, Q casts tactical abilities, U repairs, and Delete sells. Esc with nothing armed opens the pause menu (the bridge stops stepping while `pause.flag` exists in its runtime directory; its Terrain guide button shows the ground table), F1 opens the controls reference and M opens the strategic map (no pause; Esc or M closes it); all read their keys from `scripts/ui/keybinds.gd`. The entire battlefield remains
visible; there is no fog of war. Press `F` to focus the current selection and `Home` to return to the Earthfront command district.
