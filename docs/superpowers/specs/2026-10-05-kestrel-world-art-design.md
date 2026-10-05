# Kestrel Reach world art: design addendum

Status: DRAFT for review, 2026-10-05. Addendum to `2026-10-04-gameplay-hud-kestrel-reach-design.md` (section 5.1 terrain,
5.2 shadows). Nothing here is implemented.

## 1. Why

The user ran Kestrel Reach and said "the gameplay graphic look nothing like the mocks". He chose to match the mock look:
re-art the Kestrel 3D world so a live frame reads like boards 1, 3 to 8, while the battlefield stays 3D. Section 1 of the
parent spec ("the boards' painted sprites are a stand-in") is narrowed: the sprites stay a stand-in for buildings and
units, but the ground, water, props, framing and grade now follow the boards.

## 2. Measured gap (live 2026-10-05 capture vs `terrain/land.jpg` and boards gp01, gp03 to gp08)

| Area | Live today | Mock |
|---|---|---|
| Grass | flat `#246c07` on screen, luma std 2.3 | olive textured `#808844` (p10 `#747b3a`, p90 `#8f974f`), luma std 10 |
| Grade | mean HSV saturation 178 | 108; warm top-left light to dark bottom-right (gen.py `gSun`) |
| Detail texture | `continuous_ground_detail_v4` at +-8 percent | the same texture at full strength, plus a 37 degree rotated copy in soft light |
| Dry Flats | orange `#c9923a` albedo, the biggest yellow area on screen | sand `#ac965e`, std 21.7 |
| Highland | 1.60 tall dark plateau `#6e747a` | grey rocky ground `#888680`, `highland_v3` desaturated, rock sprites |
| River | thin blue strip in the terrain colour, no banks | bank sand `#bda878`, edge `#1d4d64`, centre `#3a6c81`, ripples, ford pebbles, reeds |
| Sea and edges | grey-blue box `#4f6c7f`; off-map cells are sea, so the map is an island with cliffs and sky void | sea `#133a51` to `#082a42`, near shore `#1b475e`, white surf line; land runs past the frame |
| Props | about 33 low-poly `world_tree` lollipops, a few rocks | dense `forest_cluster_v5` canopies, scrub, rock clusters, riverside willows, craters, all with soft drop shadows |
| Ore and alloy | grey spheres on a brown disk plus an `ORE` label | cyan `ore_crystals_v1`, purple alloy (hue +95 degrees) |
| Buildings | human ones are grey box-built `tactical_models`, about 0.9 tile wide | painterly 3/4 sprites, CC 250 px (3 tiles), production 170-200 px, turrets about 110 px |
| Units | about 1 tile | tank 140 px (1.7 tiles), infantry 80 px (1 tile) |
| Camera | yaw -0.68 rad (map rotated 39 degrees), zoom 7.5-24, island void at max zoom | north-up; land.jpg maps 44 columns to 3600 px = 82 px per column, the same scale as live zoom 8.8 (83 px) |
| Hover marker | amber `#f0be4a` emissive torus, radius 0.47 (wider than the CC) | none; a thin cyan tile outline at most |
| Shadows | NW sun at 38 degrees | lower-right drop shadows: the same sun once the camera is north-up |

The "giant yellow blob" has two candidates: the amber hover torus (it sits over whatever hex the cursor is on, CC
included) and the orange Dry Flats. Both are fixed; the plan confirms which one the user saw with a mesh probe.

## 3. Decisions (rulings, reversible, flagged)

W1. Kestrel-only profile. A `WorldArt` profile switches on when the first non-flat ground layer arrives (`_sync_ground`).
    Survival and every other scenario never build a ground model, so they keep every legacy path byte for byte: camera,
    environment, hover torus, tactical models, ocean box, noise terrain. Cost if wrong: nothing; the gate is one branch.
W2. North-up camera for Kestrel: `camera_yaw = 0`, default zoom 10.0 (73 px per column), range 7.5 to 18.0, focus
    clamped so the visible ground never leaves the map plus an 8 cell margin. Pitch stays 57 degrees. Rotate keys still
    work. Cost if wrong: two constants.
W3. Map-edge continuation. Off-map cells take the nearest on-map glyph instead of sea; the terrain mesh grows to a 9 cell
    margin. The legacy ocean box is hidden under the profile; the sea is drawn by the terrain shader.
W4. Palette from land.jpg. Ground albedos are calibrated until a live swatch is within Delta E 12 (CIE76) of the
    land.jpg median for grass, meadow, flats, highland, shore and sea. The grade is set by measured saturation and warmth.
W5. Props are camera-facing billboard cards drawn by one MultiMesh from a baked atlas of the game's own painted sprites
    (`forest_cluster_v5`, `scrub_cluster_v1`, `rock_cluster_v1`, `crater_v1`, ore and alloy crystals), with alpha
    scissor and flat soft drop-shadow decals. This is the one place painted sprites enter the 3D world. In an orthographic
    camera a camera-facing card has the depth of its base, so it sorts correctly against 3D buildings. Cost if wrong:
    swap the card mesh for low-poly models; the placement table and atlas stay.
W6. Buildings and units stay 3D. Under the profile human buildings use the authored glbs (as alien ones already do), are
    scaled to a visual width table in tiles (CC 2.8, production 2.1, power and depot 1.7, turrets 1.3, wall 1.0; tank 1.6,
    harvester 1.5, infantry 1.0), get a soft contact pad and a selection ring sized to that width. Placement stays per
    tile, but picking follows the fitted model: a click inside the screen rectangle of one of its mesh boxes selects it
    (a unit's whole box), the narrowest model wins when several hold the click, and a click on no model falls back to
    the legacy 32 px reach around the root. The `COMMAND` / `CORE NODE` Label3D banners are dropped under the profile
    (the HUD names buildings) and health bars sit above the scaled model.
W7. The amber hover torus becomes a thin cyan hex outline under the profile.
W8. Atmosphere: a non-interactive CanvasLayer under the HUD paints the gen.py `gSun` gradient and a soft vignette; the
    environment background becomes deep sea `#0c2a40` so no sky can show.
W9. Deposits under the profile drop the disk, spheres and `ORE` Label3D; the HUD resource pins already carry the label.

## 4. Budgets

- Frame time: idle Kestrel fps on the RTX 3050 at least 0.9x the 2026-10-05 baseline; GDScript `process_ms` up no more
  than 10 percent. No compute shaders, no screen or depth textures (Compatibility renderer).
- Draw calls: idle default and max zoom no more than baseline + 120 (props add at most 4: cards, decals, crystals,
  vignette; removing the box-built buildings and deposit spheres should lower the total). Primitives no more than
  baseline + 150k.
- One-time build: ground bake plus prop scatter under 1.5 s on the target machine.

## 5. Verification

- `tools/ui/world_diff.py` scores a live world-only frame against each board's battlefield crop (palette distance,
  saturation, detail energy, clutter, warmth, per-ground swatches) and writes a side-by-side PNG. Each task names the
  boards it must improve and by how much; no task may lower another board by more than 2 points. This is a measured
  improvement plus a visual checklist, never a pixel match.
- Headless Godot tests need no GPU. Survival keeps every legacy value (camera, environment, hover, ocean, models).
- Golden hash `2_081_234_273_307_305_018` and `crates/` untouched; leak counters at exit no worse than today
  (4 ObjectDB instances, 2 resources).

## 6. Out of scope

Pixel-matching the boards, a top-down camera, sprite buildings or units, new sim rules, fog of war, Survival art,
day and night, weather, animated foliage beyond a slow sway.
