# Kestrel sound effects

Every file in this folder is synthesised from scratch by `tools/audio/build_sfx.py`: numpy noise, oscillators, filters
and envelopes with fixed seeds. There are no third-party samples, recordings or presets in the chain, so the sounds are
CC0 by construction (public domain dedication, https://creativecommons.org/publicdomain/zero/1.0/).

## Contents

- 26 WAV files, 16-bit mono 44100 Hz: weapons (`rifle`, `cannon`, `plasma_bolt`), impacts (`explosion_small`,
  `explosion_large`, `collapse`), seamless loops (`rotor_loop`, `tread_loop`, `foot_loop`), ui ticks (`ui_click`,
  `ui_hover`, `denied` for a refused order, `place_thunk` for a placed building), tonal unit barks (`select`,
  `ack_infantry`, `ack_vehicle`, `ack_air`; no speech) and alerts (`alert`, `build_complete`, `wave_inbound`,
  `power_down`, `power_up`, `wave_cleared`, `research_complete`, and the match-end stings `victory_sting` and
  `defeat_sting`, 2.2 and 2.4 s).
- `sfx_manifest.json`: per sound the id, file, duration, loop flag, category (weapon, impact, loop, ui, voice, alert),
  a suggested `base_volume_db` trim for the player, a one-line character note, and the measured peak and loudness
  (loudest 50 ms RMS window, dBFS). The files already carry the mix hierarchy: weapons and impacts loudest, then alerts,
  voice barks and loops, ui ticks quietest. Every peak is at or below -1.5 dBFS.
- Loops carry a WAV `smpl` chunk with one forward loop over the whole file; the Godot importer (`edit/loop_mode` 0,
  detect from WAV) turns it into `LOOP_FORWARD`. They are built circularly, so the seam is click-free.
- The `.import` files are written by Godot and committed like the rest of `assets/`.

## Regenerate

```
python3 tools/audio/build_sfx.py
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --import
cd tools/audio && python3 -m unittest test_build_sfx -v
```

The script prints a table of duration, peak and loudness per sound. Output is byte-identical across runs; the test
checks that the committed files equal a fresh run (within 2 LSB), plus format, length, peak, DC, loop seams, loudness
order and a few sound-design properties measured offline. The headless import makes no sound.

These were designed and checked by analysis only (spectrograms, envelopes, levels); nobody had listened to them when
they were committed.
