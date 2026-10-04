# Asset credits

## Earthfront isometric sprite set

The active `*_v2.png` unit and structure sprites are original AI-generated
art created for this project with OpenAI's built-in image-generation tool. The
versioned source atlas is `rts_atlas_v2.png`; the twelve runtime sprites were
cropped from its strict 4×3 grid and normalized to 256×256 transparent PNGs.
They use native material colors in-game, with faction identity drawn separately
by the renderer. The older credited assets below remain in the repository but
are no longer loaded by the Earthfront renderer.

The active `alien_*_v1.png` set was produced through the same original
image-generation workflow as a second strict 4×3 transparent atlas
(`alien_atlas_v1.png`). Its iron/crimson biomechanical machines are intentionally
silhouette-distinct from the human olive/teal industrial faction.

The unique `capital_v1.png` mobile fortress and `alien_capital_v1.png`
Leviathan are original transparent production sprites generated with the same
built-in tool. They replace the former reused tank silhouettes for late-game
flagships.

## Earthfront environment set

`environment_atlas_v1.png` is an original AI-generated strict 4×3 transparent
atlas created for this project with OpenAI's built-in image-generation tool.
Its twelve normalized runtime sprites provide rocks, scrub, dead trees,
sandbags, wrecked vehicles, concrete barriers, floodlights, craters, illustrated
ore/alloy fields, building foundations, and damaged fencing. The renderer places
them deterministically as cosmetic battlefield dressing; they never obscure fog
or change simulation pathing.

## Combat sprites (units + turrets)

The four units and both turrets use top-down military art from the **Dark War
Pack** by **UnLuckY Studio** (www.unluckystudio.com), released free for commercial
use and listed as **CC0 1.0 Universal (public domain)** on OpenGameArt —
https://creativecommons.org/publicdomain/zero/1.0/
Source: https://opengameart.org/content/dark-war-pack
Each sprite was trimmed and rendered to a 128×128 transparent PNG.

| In-game | Source sprite |
|---|---|
| Infantry | soldier_with_ak_black |
| Tank | tank1 |
| Anti-armor | tank2 |
| Helicopter | helicoptor |
| Gun Turret | gunner (single cannon) |
| AA Turret | gunner_2face (dual cannon) |

## Building markers (economy / HQ / wall)

The remaining structures are icons from **game-icons.net**, used under the
**Creative Commons Attribution 3.0 (CC BY 3.0)** license —
https://creativecommons.org/licenses/by/3.0/ — rendered as 128×128 white
silhouettes (tinted/placed on team foundation pads in-game).

| In-game | Icon | Author |
|---|---|---|
| Command Center | bunker | Quoting |
| Power Plant | power-generator | Delapouite |
| Refinery | oil-pump | Delapouite |
| Barracks | barracks | Delapouite |
| Wall | brick-wall | Delapouite |

Icons by Delapouite and Quoting, available at https://game-icons.net under
CC BY 3.0.

## Fonts

**Rajdhani** (SemiBold + Bold), by Indian Type Foundry, used under the
**SIL Open Font License 1.1** — full license in `assets/fonts/Rajdhani-OFL.txt`.
Source: https://fonts.google.com/specimen/Rajdhani
Used for all in-game data/UI text.

**Black Ops One**, by Sorkin Type, used under the **SIL Open Font License 1.1** —
full license in `assets/fonts/BlackOpsOne-OFL.txt`.
Source: https://fonts.google.com/specimen/Black+Ops+One
Used as the military-stencil display face for the victory/defeat banner.

**Cinzel**, by Natanael Gama, used under the **SIL Open Font License 1.1** —
full license in `assets/fonts/Cinzel-OFL.txt`.
Source: https://fonts.google.com/specimen/Cinzel
Previously the inscriptional Roman serif for the regal menu register. Retained in
the repo but no longer loaded after the **Holographic Tactical Command** UI
overhaul — the wordmark and menus now use Rajdhani to match the sci-fi register.

## Audio

All sound effects and music are **procedurally generated** for this project with
**FFmpeg** (sine/noise synthesis) and are therefore original works released into
the public domain (**CC0 1.0**). No third-party audio is used. Files live in
`assets/audio/` as OGG Vorbis:

| File | Use |
|---|---|
| `ui_click.ogg` | command-bar button click |
| `laser.ogg` | weapon fire (throttled) |
| `explosion.ogg` | unit/building destruction |
| `build.ogg` / `train.ogg` | structure placed / unit deployed |
| `wave_incoming.ogg` | alarm as the wave countdown crosses 5 s |
| `victory.ogg` / `defeat.ogg` | match-end jingle |
| `music_menu.ogg` / `music_combat.ogg` | looping menu / in-match ambience |

Regenerate with the FFmpeg commands recorded in the project history; tweak the
synthesis expressions to taste.


## Godot 3D modular models

The Godot presentation client uses selected GLB models from Kenney City Kit (Industrial), Modular Space Kit, and Hexagon Kit. All three packs are Creative Commons CC0. Their original license files are preserved under `godot3d/assets/licenses/`.
