# Asset credits

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
