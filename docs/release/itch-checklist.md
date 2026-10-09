# itch.io release checklist (Ascension 0.2.0)

Plan 2026-10-07-kestrel-depth, Task 28. Nothing in this file has been uploaded, and no itch.io account was used.
Each step below that needs the user's account, machine, ears or GPU is marked **(you)**.

## 1. Where the build stands

| Piece | State |
|---|---|
| Version | `0.2.0` in `godot3d/project.godot` (`config/version`) and the Cargo workspace (`rts-server` takes it). The title footer shows `v0.2.0`, and `godot-bridge --version` prints `0.2.0`. `tools/release/test_package.py` and the bridge's unit test keep the two in step. |
| Export presets | `godot3d/export_presets.cfg`: "Linux" and "Windows Desktop", both x86_64, with the pack kept separate (`ascension.pck` beside the executable). The filters keep out tests (including `tests/fixtures/stub_bridge.sh`), `tools/`, the dev `runtime/`, the capture gallery, concept art, `*.md` and `.uid` files. |
| Packaging | `tools/release/package.sh [linux\|windows\|all]` checks templates and toolchain first, builds the bridge, exports, checks the pack with `tools/release/pck.py`, then archives to `build/` (gitignored). |
| Linux package | **Not produced yet.** The Godot 4.7.2 export templates are not installed on the dev machine, so `--export-release` cannot run. |
| What was verified without templates | The same presets exported as a bare pack (`--export-pack`, which needs no template): 575 files, 32.1 MB, `pck.py check` clean, and the Linux and Windows packs hold the same files. That pack ran under the Godot 4.7.2 editor binary, renamed `ascension.x86_64`, with the release `godot-bridge` beside it, once headless and once on a private Xvfb display with the Dummy audio driver. Both runs: the game spawned the bridge, the snapshot appeared at `user://runtime/<game pid>/snapshot.json` (user:// redirected with `XDG_DATA_HOME`), the title drew its own fonts and `v0.2.0`, Deploy started the match (tick 367 after 15 s), and a replay was written under `user://replays`. The bridge exited about 1 s after the game was killed. The logs had 0 ERROR lines. The release template binary itself was never run. |
| Windows package | **Not built and never run on Windows.** The templates, the `x86_64-pc-windows-gnu` Rust target and the MinGW linker are all missing on the dev machine. |
| macOS | Later (open decision 4). |
| Sound | Every effect is synthesised by `tools/audio/build_sfx.py`. There is no music. **Nobody has listened to the game on speakers yet**: the listening pass (`tools/audio/listen_pass.py`) is Task 29 and only you run it. |
| Performance | **Never measured on a GPU.** Every agent run used software rendering on Xvfb. The GPU frame-time script (`tools/perf/gpu_frametime.sh`, idle, combat and zoomed-out p50/p95 against a 10 ms budget) is Task 29 and only you run it, on the RTX 3050. |
| License | Open decision 5, still open (section 8). |

## 2. One-time setup on the build machine (you)

These steps install software. No agent did them, because that is your call.

1. Godot 4.7.2 export templates: download `Godot_v4.7.2-stable_export_templates.tpz` from the official Godot 4.7.2 release
   (godotengine.org download archive or the godotengine/godot GitHub release). The `.tpz` is a zip. Put the files from its
   `templates/` folder into `~/.local/share/godot/export_templates/4.7.2.stable/` (or `$XDG_DATA_HOME/godot/...` if you set
   it). `version.txt` there must read `4.7.2.stable`. `package.sh` needs `linux_release.x86_64` and `windows_release_x86_64.exe`.
2. Windows bridge cross-build:
   - `rustup target add x86_64-pc-windows-gnu`
   - the MinGW linker; on Ubuntu, `sudo apt install gcc-mingw-w64-x86-64` (gives `x86_64-w64-mingw32-gcc`).
   `package.sh` builds with `--offline`. The bridge depends only on serde and ron, which are already in the Cargo cache. If
   Cargo still reports a missing crate for the Windows target, run `cargo fetch --target x86_64-pc-windows-gnu` once.
   A `godot-bridge.exe` built on Windows itself also works: `BRIDGE_EXE=<path> tools/release/package.sh windows`.
3. Build: `tools/release/package.sh all`. The script ends with:
   - `build/ascension-0.2.0-linux-x86_64.tar.gz`, holding `ascension.x86_64`, `ascension.pck`, `godot-bridge` (exec bit
     set), `VERSION` and `licenses/`;
   - `build/ascension-0.2.0-windows-x86_64.zip`, with the same layout around `ascension.exe` and `godot-bridge.exe`.

   If anything is missing, the script stops before building and names it. A pack that fails `pck.py check` is never archived.

## 3. Linux smoke run (agent-safe; never on your display)

This is the check that could not run without templates. It runs the real exported binary on a private display with
silent audio and a redirected user:// directory, and it stops only the processes it started:

```bash
S=$(mktemp -d); V=0.2.0
tar -C "$S" -xzf build/ascension-$V-linux-x86_64.tar.gz && cd "$S/ascension-$V-linux-x86_64"
Xvfb :94 -screen 0 1920x1080x24 -nolisten tcp & XP=$!
sleep 2
env DISPLAY=:94 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME="$S/xdg" XDG_CONFIG_HOME="$S/xdg-config" XDG_CACHE_HOME="$S/xdg-cache" \
  ./ascension.x86_64 --audio-driver Dummy > "$S/game.log" 2>&1 & GP=$!
sleep 20
ls "$S/xdg/godot/app_userdata/Ascension- Earthfront 3D/runtime/$GP/snapshot.json"   # the launcher-spawned bridge wrote it
grep -c ERROR "$S/game.log"                                                          # expect 0
BP=$(ps -o pid= --ppid $GP)                                                          # the bridge, the game's child
kill $GP; sleep 2; kill -0 $BP 2>/dev/null && kill $BP; kill $XP
```

A failure here blocks the upload. "Simulation core missing" on the title means `godot-bridge` is not beside the executable
or lost its exec bit.

## 4. Windows test (you, on a Windows 10 or 11 x64 machine)

Nobody has run the game on Windows. Before any Windows upload:

1. Unzip `ascension-0.2.0-windows-x86_64.zip` into a normal folder (not inside the zip viewer).
2. Run `ascension.exe`. The exe is unsigned, so SmartScreen may warn: More info, then Run anyway. Note whether antivirus
   objects to the game starting `godot-bridge.exe`.
3. The title shows `v0.2.0` bottom right, and the Visibility fact reads "Fog of war, scout the alien side" once the bridge is
   up. "Simulation core missing" means the bridge did not start: report the path it names.
4. Play a few minutes of Kestrel Reach. Then Esc, Quit. In Task Manager, check that `godot-bridge.exe` has gone too.
5. Known limit to confirm: end `ascension.exe` from Task Manager. On Windows the bridge's `--exit-with-parent` watch does
   nothing, so `godot-bridge.exe` keeps running. End it by hand and note that it happened.
6. Your data lives in `%APPDATA%\Godot\app_userdata\Ascension- Earthfront 3D\` (settings, records, replays, runtime). Check
   that `runtime\` holds no leftover folder after a normal Quit.
7. Also try: Settings (volume sliders: this is the first time you will hear the game), a replay from the Replays screen, a
   Restart from the debrief.

## 5. Page copy (draft; edit freely)

Keep it as honest as the build. Every claim below is true of 0.2.0.

- **Title:** Ascension: Earthfront
- **Short description:** Real-time strategy on one frontier map. Build an industrial base, hold the river ford against
  alien waves, and break the Core Node.
- **Classification:** Game. Genre: Strategy. Release status: In development (prototype). Tags (suggested): rts,
  tower-defense, sci-fi, singleplayer, roguelite.
- **Body:**

  > Ascension is a single-player real-time strategy game with tower-defence pressure. On Kestrel Reach, a painted frontier of
  > river, ford, ridge and forest under fog of war, you mine ore, keep the power grid and ammunition flowing, train infantry,
  > armour and gunships, and hold against alien waves until you can break the Core Node. A match runs about 15 to 25 minutes.
  >
  > - Three difficulty presets, a seed per operation and a daily seed.
  > - Run mode: hold twelve waves and draft one of three perks after each cleared wave.
  > - Every match is recorded and can be replayed at up to 8x. A replay is checked against its recorded end.
  > - Earthfront Survival: the original open battlefield with the whole map in view.
  >
  > **This is an early build. Please read before you buy or download:**
  > - One campaign map plus the classic Survival map. "Continue campaign", "Skirmish sandbox" and the later eras on the title
  >   are design only and are disabled.
  > - The sound effects are synthesised placeholders and there is no music yet.
  > - Some vehicle and alien models are prototype art.
  > - Single player only. No online play, no leaderboards.
  > - Linux and Windows, x86_64 only; macOS is planned. The game uses Godot's Compatibility renderer (OpenGL 3.3 class
  >   hardware). Performance has not been measured on a range of GPUs yet.
  > - The simulation runs as a small companion program (`godot-bridge`) that the game starts and stops itself. Keep it in
  >   the same folder as the game.

- **Pricing:** your call (free, or pay-what-you-want with a 0 minimum, is the usual choice for a prototype).

## 6. Screenshots (from the capture tool)

Use real captures from the game, never the `task-*.png` review images in `.superpowers/` (several show fixture or synthetic
states). Every capture tool here renders on a private Xvfb display with silent audio:

- In-game boards: `python3 tools/qa/world_capture.py <out dir> --scenario kestrel --display :94` (software rendering, fog on
  unless `EARTHFRONT_FOG=0`; the frames listed in `tools/ui/world_frames.json`), and `--scenario survival` for Survival.
  Pick 3 to 5: the opening base, a held ford under attack, the HUD with a selection, the debrief.
- The title: the exported-pack smoke run (section 3) plus `import -display :94 -window root title.png` before the kill line.
  It shows the real footer `v0.2.0`. `tools/ui/run_cap.sh title <abs path>` renders the gallery fixture instead, whose footer
  carries a key hint, so do not use that one for the page.
- Software rendering (llvmpipe) is slightly softer than a GPU. For the page's cover image (itch suggests 630x500), take one
  GPU capture yourself: `world_capture.py <dir> --gpu --allow-user-display` opens a window on your own display.

## 7. Upload with butler (documented, NOT run)

butler is itch.io's command-line uploader (https://itch.io/docs/butler/). Nothing below has been run.

```bash
butler login                                   # once, opens the itch.io authorisation in your browser
V=$(cat build/ascension-0.2.0-linux-x86_64/VERSION)
butler push build/ascension-$V-linux-x86_64   <your-itch-user>/<game-slug>:linux-x86_64   --userversion "$V"
butler push build/ascension-$V-windows-x86_64 <your-itch-user>/<game-slug>:windows-x86_64 --userversion "$V"
butler status <your-itch-user>/<game-slug>
```

- Push the unpacked directories (`build/ascension-<version>-<platform>/`), not the archives, so butler can send diffs on
  later versions. Channel names that contain `linux` or `windows` are tagged with that platform automatically.
- Push the Windows channel only after the Windows test in section 4 has passed.
- After the first push, download the Linux build through the itch app or the page, and check that `godot-bridge` is still
  executable (the title would say "Simulation core missing" otherwise).
- On the page, set the Linux upload's executable to `ascension.x86_64` and the Windows one to `ascension.exe` if the itch
  app asks.

## 8. License decision (open decision 5: yours)

- Today there is **no LICENSE file**, and Cargo says `license = "Proprietary"`. Until you decide, that stays as it is, and the
  page should say "All rights reserved".
- The options from the spec: keep it proprietary (all rights reserved), or open the code with separate terms for the assets.
- Whatever you choose, the package must carry the third-party notices:
  - `licenses/` in each package already holds the three Kenney kit notes (CC0) and `FONT-LICENSES.md` (the fonts are SIL OFL
    1.1).
  - **Still missing, needed before a public upload:** the full OFL 1.1 text for Rajdhani and IBM Plex (the OFL asks for its
    text to travel with the fonts), and Godot's MIT license notice with its third-party notices (the Godot license page
    has the text, and `Engine.get_license_text()` returns it at runtime). Either add these files to `licenses/` (and to
    `package.sh`'s licence step), or add a credits screen.
  - This checklist did not audit where the remaining art came from (painted terrain, sprites, portraits, the ambient track,
    the deploy confirmation sound). Confirm you have the rights to each before upload. Task 30's art approvals list covers
    the sign-off.

## 9. Still to do before a public 0.2.0 (in order)

- [ ] (you) Install the export templates; run `tools/release/package.sh linux`; run the section 3 smoke run (an agent can do
      it once the templates exist).
- [ ] (you) Listening pass, `tools/audio/listen_pass.py` (Task 29), and a first real session with sound.
- [ ] (you) GPU frame times, `tools/perf/gpu_frametime.sh` (Task 29), on the RTX 3050.
- [ ] (you) Decide the license (section 8). Add the OFL and Godot notices.
- [ ] (you) Rust target and MinGW; `tools/release/package.sh windows`; the Windows test (section 4).
- [ ] (you) Create the itch.io page with the section 5 copy and the section 6 screenshots. Keep it as a draft until the
      checks above pass.
- [ ] (you) `butler push` (section 7), then download it again and play once from the itch build.
