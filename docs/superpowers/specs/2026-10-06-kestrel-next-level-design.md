# Kestrel Next Level Design

Date: 2026-10-06. Branch base: `gameplay-hud-kestrel-reach` @ caf3920 (unmerged). Proposed work branch: `kestrel-next-level` cut from that HEAD.

## Intent (what the user asked for)

The user asked "how can we improve the game so its next level", was offered four directions (opening + sound, fog + minimap, art polish, tune what I built) and answered "do all". Context: world art, sprite buildings/units, combat effects, firing effects and movement animation are done (see the 2026-10-05 plans). The remaining weakness is the game around those: a thin start, almost no sound, no scouting, stale HUD art. Success = a new player sits down, has something to do in the first minute, hears and sees a fight, has to scout, and nothing on screen looks like a placeholder.

"Tune what I built" is not a workstream here: it needs the user's playtest notes and is done as small follow-ups when they arrive.

## Facts the design rests on (from the 2026-10-06 surveys)

- Kestrel start today: human has 1 Command Center, 4 infantry, 1800 credits, no power, no refinery, no harvester. Unlocked: CommandCenter, PowerPlant, Refinery, Barracks, ResearchLab, SupplyDepot, GunTurret, Wall; Infantry, Harvester. Alien base is built and inert until tick 2700 (90 s); first fight is about 105-115 s after Deploy. (`scenario.rs:309-392`, `earthfront.rs:918`, `godot-bridge.rs:821`.)
- The tutorial (`earthfront_3d.gd:3050-3107`, `live_adapter.gd:30-41`) is Survival-era: stages 0/3/5 are already satisfied on Kestrel, there is no hold-the-ford guidance.
- The golden hash test builds its own two-CC sim, not a Scenario, so scenario content changes cannot move it. Tests that pin the Kestrel start: `scenario.rs` kestrel tests (~1389-1820, including an overrun/defended playtest), bridge tests, and the Godot fixture `godot3d/tests/fixtures/kestrel_snapshot.json` (regenerate with `godot-bridge --scenario kestrel --dump-snapshot`).
- Audio: 2 sample files, `_play_tone` sine generator, no buses, no sounds for fire/UI/orders. The orthographic camera makes `AudioStreamPlayer3D` attenuation wrong. QA launches with `--audio-driver Dummy`.
- Fog: no sight concept in the sim; the AI and combat are omniscient on purpose. `NEXT_STEPS.md:57-61` says "Do not add a per-player visibility system"; several Godot tests ban fog wording.
- Minimap exists (SubViewport of the live world). Missing: click-to-jump, attack pings, "jump to alert" key, layer tabs.
- Build-deck icons: `BUILD_CARDS` (`live_adapter.gd:46-58`) points five building kinds at old art; correct art already exists in `godot3d/assets/world/sprites/`.

## Phases (each independently shippable, gated, committed, unmerged)

### P1. HUD icon truth (small)
Build deck, queue card and group icons use the world-sprite textures (`WorldSprites.SPRITES[kind][0]`, alien variants where a faction icon is shown). Fix the five stale `BUILD_CARDS` entries, the hard-coded queue `foundation_v1`, unit-group icons for all six unit kinds, fixtures. Pixel-gate UI tests re-baselined only where an icon legitimately changed, with the change shown.

### P2. A real opening (scenario + objectives)
- Scenario (`scenario.rs`, Kestrel only; golden hash safe): the human starts with CC, PowerPlant, Refinery, Barracks, one Harvester, 4 infantry; money stays 1800 or is lowered so early choices matter (tuned by playtest). No turrets (player builds defence). Keep the ford chokepoint and region tests green.
- Pacing: bring first contact to about the 2:00 mark with a small alien probe before wave 1 (2-3 infantry sent at the nearest relay/CC), then the existing escalating waves. Exact tick values tuned with the defended/undefended playtest tests; those tests must still hold (defended base survives at least 3 waves, undefended one falls).
- Objectives (client-only, derived from snapshot entities, no snapshot change): replace the Survival-era stage list on Kestrel with: 1 Power the base (power plant online), 2 Start the economy (refinery + harvester delivering), 3 Raise a squad (barracks, 6+ units), 4 Hold the ford (survive wave 1), 5 Break the Core Node. HUD objective card, briefing text and toasts match; Survival tutorial untouched.
- Regenerate the Kestrel fixture; update the pinned tests deliberately and explain each change.

### P3. Sound
- `tools/audio/build_sfx.py`: deterministic numpy synthesis (fixed seeds), CC0 by construction, committed WAV/OGG plus a test (duration, peak, loudness, deterministic hash, no clipping). Set: rifle, cannon, plasma bolt, small/large explosion, building collapse, rotor loop, tread/footfall loop, UI click/hover, select, order-acknowledge blips, alert, build-complete, wave-inbound. No spoken voice (no speech source available); acknowledgements are short tonal "barks" per unit class.
- `AudioDirector` (pure logic module, no engine calls): event to sound id, volume and pan from the world point through the camera view rect (off-screen sounds attenuated or skipped), per-sound cooldowns, priority, ducking of ambient/music under alerts and explosions. A thin Godot layer owns a pool of 16 SFX players + 1 ambient + 1 UI on a new bus layout (Master, SFX, UI, Ambient, Music).
- Hooks: shot dispatcher, WorldFx spawns (hit/explode/collapse), selection and orders, unit-ready, build-complete, wave-inbound, under-attack. Replace `_play_tone` call sites on Kestrel; keep Survival tones as is.
- Testing: audio logic is tested through a recording stub (assert event, id, volume, pan, cooldown). No test or QA run may reach a real audio device: Godot is only run with `--headless` or `--audio-driver Dummy`. Listening happens only when the user runs the game.

### P4. Fog of war and minimap (presentation-only)
Decision for the user: this REVERSES the recorded "no fog" stance. Safety: sim, AI and combat stay omniscient; only what the player is shown changes. `crates/core` is untouched, golden hash cannot move, and fog can be switched off with `EARTHFRONT_FOG=0`.
- Bridge (`godot-bridge.rs`): per-kind sight radius table (weapon range + margin, buildings and CC larger; a unit's sight is never below its weapon range so nothing hits you from fully unseen ground at point-blank), a visibility mask for the 44x26 grid with explored persistence, new additive snapshot key `fog` (per cell 0 unseen / 1 explored / 2 visible). Non-human entities outside human sight are omitted (previously seen enemy structures stay as remembered entries flagged `remembered`). The `shots` window drops shots where neither end is visible. Enemy-derived fields (`alien_relays`, wave route, `core_node`) stay known as briefing intel; wave countdown stays.
- Godot: terrain shader gets a small mask texture (soft edges; the Kestrel ground shader only), enemy nodes created/freed on sight changes without re-firing "unit added" toasts or deploy effects, WorldFx/shot/dust gating by visible cell, enemy-intel and threat panels use only known data, minimap inherits the shader and filters hostile marks.
- Minimap additions: click-to-jump, attack pings (pulsing ring at the world position of a hit on the player's unit, 3 s), `Space` jumps to the latest alert. Layer tabs stay out of scope.
- Docs/tests: amend `NEXT_STEPS.md`, `README.md`, `godot3d/README.md`; rework the fog-wording bans and the "Full battlefield, no fog of war" copy deliberately (`live_screens.gd:36`, fixtures, five tests) so they describe the new truth; snapshot tail-key tests updated.

### P5. Art polish
- Composite building sprites (`tools/ui/build_building_variants.py`): give the weakest kinds (alien supply depot, alien battery, vehicle factory) distinct silhouettes, signage and accent treatment so they stop reading as recolours; accept a contact sheet side by side with the board sprites as the gate. Honest limit: these stay procedurally composited, not painted; a paint-quality redo needs outside art.
- Unit facing stays mirrored single poses (eight directions needs art that does not exist); a subtle lean toward the current target is added to the existing animation layers.
- Out of this phase: day/night, new factions or maps, voice acting, multiplayer, layer tabs, GPU perf instrumentation (needs the user's display; offered separately as a run-it-yourself script).

## Constraints (all phases)

- Golden hash and `crates/core` untouched; the only Rust files that may change are `crates/core/src/game/scenario.rs` (P2) and `crates/server/src/bin/godot-bridge.rs` (P4, plus `--dump-snapshot` fixtures). Check `git diff --stat d81deab..HEAD -- crates/` at every phase end.
- Survival byte-identical (SHA tests untouched); every new behaviour gated on Kestrel / `world_art_on`.
- Perf: at most +120 draw calls and +150k primitives vs `world_baseline.json` `_perf`; idle frame at most 10 ms p50 on the GPU baseline method (measured by the user's machine when possible).
- Never play audio, open windows or move the cursor on the user's machine during QA; software captures on private Xvfb only.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (re-check after each subagent task); no em or en dashes; stage only a task's own paths.
- Gates per phase: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --workspace`, Godot suite (0 SCRIPT/SHADER/ERROR, leak line 141), tools/ui + new tools tests, `verify_all.sh`, idle scoreboard no board drops more than 2.0 except where a phase intends the change (P1 icons, P4 fog), and Survival pair at least 97 (timing swings it).

## Open decisions (defaults chosen; user may overrule)

1. Fog reversal: default YES presentation-only, Kestrel only, kill switch `EARTHFRONT_FOG=0`.
2. Voice: default synthesised tonal barks, no speech.
3. Remembered enemy buildings after losing sight: default YES, dimmed.
4. Branch: default new branch `kestrel-next-level` from caf3920; `gameplay-hud-kestrel-reach` stays unmerged.
5. Phase order P1, P2, P3, P4, P5 (cheap and visible first; fog last because it touches the most).

## Risks

- Fog contradicts a recorded decision and a handful of tests and copy; handled by explicit amendment, not silent edits.
- Omniscient combat vs hidden enemies: mitigated by sight at least weapon range and by showing any shot whose target (the player's unit) is visible.
- Scenario retune can break the overrun/defended playtest; mitigated by tuning against those tests, not around them.
- Sound quality from procedural synthesis is plain; it is a large step from silence, not a studio mix.
