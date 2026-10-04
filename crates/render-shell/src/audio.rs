//! Shell-only audio: a tiny manager over macroquad's audio. Loads SFX + music
//! once, plays fire-and-forget SFX (throttled so a wall of lasers can't spam the
//! mixer), and loops music. Driven entirely off read-only sim queries and view
//! events, so it never touches determinism. Missing files degrade to silence.

#[cfg(feature = "audio")]
use macroquad::audio::{load_sound, play_sound, stop_sound, PlaySoundParams, Sound};
#[cfg(feature = "audio")]
use macroquad::time::get_time;
#[cfg(feature = "audio")]
use std::collections::HashMap;

/// A one-shot sound effect.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum Sfx {
    UiClick,
    Laser,
    Explosion,
    Build,
    Train,
    WaveIncoming,
    Victory,
    Defeat,
}

/// A looping music track.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Music {
    Menu,
    Combat,
}

#[cfg(feature = "audio")]
const SFX_VOL: f32 = 0.55;
#[cfg(feature = "audio")]
const MUSIC_VOL: f32 = 0.4;

/// Holds the loaded sounds and the currently looping track.
#[cfg(feature = "audio")]
pub struct AudioMgr {
    sfx: HashMap<Sfx, Sound>,
    music_menu: Option<Sound>,
    music_combat: Option<Sound>,
    playing: Option<Music>,
    last: HashMap<Sfx, f64>,
}

/// Silent native fallback used when the optional platform audio backend is not
/// linked. Keeping this a real no-op avoids Macroquad's disabled-feature stub
/// printing a warning on every shot, click, and frame.
#[cfg(not(feature = "audio"))]
pub struct AudioMgr;

#[cfg(feature = "audio")]
impl AudioMgr {
    /// Loads every sound from `assets/audio`. Missing files are skipped (silent),
    /// mirroring the sprite loader's graceful degradation.
    pub async fn load() -> Self {
        let names = [
            (Sfx::UiClick, "ui_click"),
            (Sfx::Laser, "laser"),
            (Sfx::Explosion, "explosion"),
            (Sfx::Build, "build"),
            (Sfx::Train, "train"),
            (Sfx::WaveIncoming, "wave_incoming"),
            (Sfx::Victory, "victory"),
            (Sfx::Defeat, "defeat"),
        ];
        let mut sfx = HashMap::new();
        for (kind, name) in names {
            if let Ok(s) = load_sound(&format!("assets/audio/{name}.ogg")).await {
                sfx.insert(kind, s);
            }
        }
        let music_menu = load_sound("assets/audio/music_menu.ogg").await.ok();
        let music_combat = load_sound("assets/audio/music_combat.ogg").await.ok();
        Self {
            sfx,
            music_menu,
            music_combat,
            playing: None,
            last: HashMap::new(),
        }
    }

    /// Plays a one-shot SFX immediately (no-op if it failed to load).
    pub fn play(&self, kind: Sfx) {
        if let Some(s) = self.sfx.get(&kind) {
            play_sound(
                s,
                PlaySoundParams {
                    looped: false,
                    volume: SFX_VOL,
                },
            );
        }
    }

    /// Plays `kind` only if at least `min_gap` seconds passed since the last one,
    /// so dense events (lasers, explosions) don't pile into a wall of sound.
    pub fn play_throttled(&mut self, kind: Sfx, min_gap: f64) {
        let now = get_time();
        if self.last.get(&kind).is_none_or(|&t| now - t >= min_gap) {
            self.last.insert(kind, now);
            self.play(kind);
        }
    }

    /// Switches the looping music to `track` (no-op if already playing it).
    pub fn set_music(&mut self, track: Music) {
        if self.playing == Some(track) {
            return;
        }
        self.stop_music();
        let snd = match track {
            Music::Menu => self.music_menu.as_ref(),
            Music::Combat => self.music_combat.as_ref(),
        };
        if let Some(s) = snd {
            play_sound(
                s,
                PlaySoundParams {
                    looped: true,
                    volume: MUSIC_VOL,
                },
            );
            self.playing = Some(track);
        }
    }

    /// Stops any looping music.
    pub fn stop_music(&mut self) {
        if let Some(prev) = self.playing.take() {
            let snd = match prev {
                Music::Menu => self.music_menu.as_ref(),
                Music::Combat => self.music_combat.as_ref(),
            };
            if let Some(s) = snd {
                stop_sound(s);
            }
        }
    }
}

#[cfg(not(feature = "audio"))]
#[allow(
    clippy::needless_pass_by_ref_mut,
    clippy::unused_async,
    clippy::unused_self,
    reason = "the silent fallback deliberately mirrors the feature-enabled manager API"
)]
impl AudioMgr {
    pub async fn load() -> Self {
        Self
    }

    pub const fn play(&self, _kind: Sfx) {}

    pub const fn play_throttled(&mut self, _kind: Sfx, _min_gap: f64) {}

    pub const fn set_music(&mut self, _track: Music) {}

    pub const fn stop_music(&mut self) {}
}
