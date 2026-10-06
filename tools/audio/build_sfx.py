"""Synthesise the Kestrel sound set (plan 2026-10-06-kestrel-next-level, Task 4; spec section P3).
Deterministic: numpy only, fixed seeds (PCG64 uniform draws), no network, no samples. CC0 by construction.
Usage: python3 tools/audio/build_sfx.py [OUT_DIR]   (default godot3d/assets/audio/sfx/)
Writes one 16-bit mono 44100 Hz WAV per sound plus sfx_manifest.json, then prints a loudness table.
After a regeneration, refresh the Godot .import files with a headless import (it makes no sound):
  tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot3d --import

Loudness is measured as the loudest 50 ms RMS window (10 ms hop), in dBFS. Each sound is scaled to its target; if that
pushes the peak above PEAK_DB the signal goes through a soft tanh limiter and is rescaled (a few passes), and as a last
resort is turned down, so no file peaks above -1.5 dBFS. The targets encode the mix hierarchy: weapons and impacts
loudest, alerts next, voice barks and loops in the middle, ui ticks quietest. base_volume_db in the manifest is the
director's starting trim on top of that (frequent or many-voiced sounds sit a little lower).

Loops are built circularly: noise is filtered in the frequency domain over exactly one loop length (so it repeats
seamlessly), every periodic part has a whole number of cycles in the loop, and events are added modulo the loop length.
A WAV smpl chunk marks one forward loop over the whole file; Godot's importer (edit/loop_mode 0, detect from WAV) picks
it up. One-shots start on a zero sample, fade out over 12 ms and end on 4 ms of silence."""
import json, math, pathlib, struct, sys
import numpy as np

REPO = pathlib.Path(__file__).absolute().parents[2]
OUT = REPO / "godot3d/assets/audio/sfx"
SR = 44100
PEAK_DB = -1.5
TAIL_FADE_S = 0.012
TAIL_ZERO_S = 0.004
METER_WIN_S, METER_HOP_S = 0.05, 0.01


# ---------------------------------------------------------------- primitives

def n_of(seconds):
    return int(round(seconds * SR))


def t_axis(n):
    return np.arange(n, dtype=np.float64) / SR


def white(n, seed):
    """Uniform white noise in [-1, 1). PCG64 uniform doubles are stable across numpy versions."""
    return np.random.Generator(np.random.PCG64(seed)).random(n) * 2.0 - 1.0


def uniform(seed, size):
    return np.random.Generator(np.random.PCG64(seed)).random(size)


def butter_mag(f, lo=None, hi=None, order=2):
    """Zero-phase Butterworth-shaped magnitude: high-pass at lo, low-pass at hi (either may be None)."""
    h = np.ones_like(f)
    if hi is not None:
        h = h / np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo is not None:
        with np.errstate(divide="ignore"):
            h = h / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
        h[f == 0] = 0.0
    return h


def band(x, lo=None, hi=None, order=2, circular=False):
    """Static filter in the frequency domain. circular=True filters over exactly len(x) (a seamless loop); otherwise the
    signal is zero padded so nothing wraps. Use on stationary sources, then apply the envelope."""
    n = len(x)
    m = n if circular else 2 * n
    spec = np.fft.rfft(x, m)
    spec *= butter_mag(np.fft.rfftfreq(m, 1.0 / SR), lo, hi, order)
    return np.fft.irfft(spec, m)[:n]


def svf(x, fc, q=0.707, mode="lp"):
    """Topology-preserving state variable filter with a per-sample cutoff (time-varying sweeps). Stable at any cutoff."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=np.float64), (n,))
    g = np.tan(np.pi * np.clip(fc, 10.0, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3 = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    ic1 = ic2 = 0.0
    out = [0.0] * n
    want = {"lp": 0, "bp": 1, "hp": 2}[mode]
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2 if want == 0 else (v1 if want == 1 else xs[i] - k * v1 - v2)
    return np.array(out)


def env(n, attack, tau, delay=0.0):
    """Linear attack then exponential decay (time constant tau), starting after delay seconds."""
    t = t_axis(n) - delay
    e = np.where(t < 0, 0.0, np.minimum(t / max(attack, 1e-6), 1.0) * np.exp(-np.maximum(t - attack, 0.0) / tau))
    return e


def phase(freq):
    """Phase in cycles from a per-sample frequency (starts at 0)."""
    return np.concatenate([[0.0], np.cumsum(freq[:-1])]) / SR


def sine(freq, n=None, ph0=0.0):
    if n is not None:
        freq = np.full(n, float(freq))
    return np.sin(2 * np.pi * (phase(freq) + ph0))


def additive(freq, gains, limit=15000.0):
    """Band-limited additive tone: harmonic k gets gains(k) and fades out as k * f nears limit."""
    p = phase(freq)
    out = np.zeros_like(freq)
    k = 1
    while k * freq.min() < limit:
        g = gains(k)
        if g:
            fade = np.clip((limit - k * freq) / 2000.0, 0.0, 1.0)
            out += g * fade * np.sin(2 * np.pi * k * p)
        k += 1
    return out


def saw(freq, limit=15000.0):
    return additive(freq, lambda k: 1.0 / k, limit)


def square(freq, limit=15000.0, tilt=1.0):
    return additive(freq, lambda k: (1.0 / k ** tilt) if k % 2 else 0.0, limit)


def crackle(n, rate, seed, grain_s=0.002, lo=1500.0, hi=6000.0):
    """Sparse random clicks (debris): rate is clicks per second, per sample (array) so the density can fall."""
    u = uniform(seed, (2, n))
    rate = np.broadcast_to(np.asarray(rate, dtype=np.float64), (n,))
    imp = np.where(u[0] < rate / SR, u[1] * 2.0 - 1.0, 0.0)
    gn = n_of(grain_s * 3)
    grain = white(gn, seed + 7) * np.exp(-t_axis(gn) / grain_s)
    return band(np.convolve(imp, grain)[:n], lo, hi)


def tone_note(n, freq, start, length, attack=0.004, tau=0.05, release=0.012, timbre=None):
    """One note (sine plus overtones by default) gated to [start, start + length) with a soft attack and release."""
    t = t_axis(n)
    m = (t >= start) & (t < start + length)
    tt = t - start
    e = np.where(m, np.minimum(tt / attack, 1.0) * np.exp(-tt / tau) * np.clip((start + length - t) / release, 0, 1), 0.0)
    f = np.full(n, float(freq))
    wave = timbre(f) if timbre else (np.sin(2 * np.pi * phase(f)) + 0.25 * np.sin(4 * np.pi * phase(f)))
    return wave * e


def add_at(buf, ev, start, circular=False):
    """Add an event into buf at sample start; circular wraps it around the loop, otherwise it is clipped at the end."""
    idx = start + np.arange(len(ev))
    if circular:
        np.add.at(buf, idx % len(buf), ev)
    else:
        keep = idx < len(buf)
        buf[idx[keep]] += ev[keep]


# ---------------------------------------------------------------- metering and finishing

def meter_db(x):
    """Short-term loudness: the loudest 50 ms RMS window (10 ms hop), dBFS."""
    w, hop = n_of(METER_WIN_S), n_of(METER_HOP_S)
    if len(x) <= w:
        return 20 * math.log10(max(math.sqrt(float(np.mean(x * x))), 1e-9))
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    starts = np.arange(0, len(x) - w + 1, hop)
    r = np.sqrt((c[starts + w] - c[starts]) / w).max()
    return 20 * math.log10(max(float(r), 1e-9))


def peak_db(x):
    return 20 * math.log10(max(float(np.abs(x).max()), 1e-12))


def finish(x, target_db, loop):
    """DC removal, loudness to target, soft limiting under PEAK_DB, edge fades for one-shots. Returns (x, passes)."""
    lim = 10 ** (PEAK_DB / 20)
    x = x - x.mean()
    x = x * 10 ** ((target_db - meter_db(x)) / 20)
    passes = 0
    while peak_db(x) > PEAK_DB - 0.05 and passes < 8:
        x = lim * np.tanh(x / lim)
        x = x - x.mean()
        x = x * 10 ** ((target_db - meter_db(x)) / 20)
        passes += 1
    if peak_db(x) > PEAK_DB - 0.05:
        x = x * 10 ** ((PEAK_DB - 0.05 - peak_db(x)) / 20)
    if not loop:
        fi = 16
        x[:fi] *= np.linspace(0.0, 1.0, fi)
        fo, z = n_of(TAIL_FADE_S), n_of(TAIL_ZERO_S)
        x[-fo - z:-z] *= np.cos(np.linspace(0.0, np.pi / 2, fo)) ** 2
        x[-z:] = 0.0
    return x, passes


def to_int16(x):
    return np.clip(np.round(x * 32767.0), -32767, 32767).astype("<i2")


def wav_bytes(samples, loop):
    data = samples.tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    if loop:
        # smpl: manufacturer, product, sample period (ns), MIDI unity note, pitch fraction, SMPTE format, SMPTE offset,
        # loop count, sampler data; then one loop: cue id, type 0 (forward), start, end, fraction, play count 0 (infinite)
        smpl = struct.pack("<9I", 0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples), 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


# ---------------------------------------------------------------- weapons

def rifle():
    n = n_of(0.40)
    t = t_axis(n)
    crack = band(white(n, 11), 2500, 12000) * env(n, 0.0002, 0.004) * 1.2
    snap = band(white(n, 12), 800, 2600) * env(n, 0.0003, 0.018) * 0.6
    thump = sine(55 + 95 * np.exp(-t / 0.02)) * env(n, 0.001, 0.018) * 0.5
    thump += band(white(n, 15), 30, 220) * env(n, 0.001, 0.03) * 0.9  # noisy body so the low end is not a ringing tone
    tail = band(white(n, 13), 120, 700) * env(n, 0.006, 0.09) * 0.18
    slap = band(white(n, 14), 300, 2000) * env(n, 0.002, 0.03, delay=0.055) * 0.12  # a near-wall echo
    return crack + snap + thump + tail + slap


def cannon():
    n = n_of(1.10)
    t = t_axis(n)
    f = 38 + 60 * np.exp(-t / 0.06)
    boom = (sine(f) + 0.3 * np.sin(4 * np.pi * phase(f))) * env(n, 0.002, 0.18) * 0.6
    boom += band(white(n, 24), 20, 250) * env(n, 0.002, 0.25) * 1.4  # noisy low body under the tonal drop
    crack = band(white(n, 21), 1800, 12000) * env(n, 0.0003, 0.008) * 0.8
    mid = band(white(n, 22), 450, 1800) * env(n, 0.0005, 0.05) * 0.6
    tail = svf(white(n, 23), 150 + 1500 * np.exp(-t / 0.25), 0.7) * env(n, 0.01, 0.35) * 0.5
    return boom + crack + mid + tail


def plasma_bolt():
    n = n_of(0.60)
    t = t_axis(n)
    f = 160 + 1300 * np.exp(-t / 0.07)
    osc = saw(f) + 0.4 * saw(f * 1.5) + 0.3 * np.sin(2 * np.pi * phase(f * 0.5))
    body = svf(osc, 700 + 7000 * np.exp(-t / 0.06), 2.5) * env(n, 0.002, 0.12)
    zap = band(white(n, 31), 3000, 14000) * env(n, 0.0002, 0.006) * 0.5
    gate = np.clip(band(white(n, 32), None, 60, order=1) * 18.0, 0.0, 1.0)  # random on/off sputter
    fizz = band(white(n, 33), 2000, 5000) * gate * env(n, 0.02, 0.16) * 0.22
    return body + zap + fizz


# ---------------------------------------------------------------- impacts

def explosion_small():
    n = n_of(1.20)
    t = t_axis(n)
    burst = svf(white(n, 41), 250 + 5000 * np.exp(-t / 0.12), 0.8) * env(n, 0.003, 0.22)
    crack = band(white(n, 42), 2000, 12000) * env(n, 0.0003, 0.01) * 0.6
    sub = sine(32 + 45 * np.exp(-t / 0.08)) * env(n, 0.004, 0.16) * 0.5
    sub += band(white(n, 44), 20, 160) * env(n, 0.004, 0.25) * 1.1
    debris = crackle(n, 300 * np.exp(-t / 0.25), 43) * env(n, 0.03, 0.4) * 0.35
    return burst + crack + sub + debris


def explosion_large():
    n = n_of(2.50)
    t = t_axis(n)
    lp = 150 + 3500 * np.exp(-t / 0.25)
    burst = svf(white(n, 51), lp, 0.8) * (env(n, 0.004, 0.6) + 0.5 * env(n, 0.01, 0.3, 0.12) + 0.35 * env(n, 0.01, 0.4, 0.35))
    crack = band(white(n, 52), 1800, 12000) * env(n, 0.0003, 0.014) * 0.6
    sub = sine(26 + 40 * np.exp(-t / 0.12)) * env(n, 0.005, 0.45)
    rumble = band(white(n, 53), 25, 200) * env(n, 0.1, 0.9) * 0.4
    debris = crackle(n, 220 * np.exp(-t / 0.6), 54, lo=1200, hi=4500) * env(n, 0.05, 0.9) * 0.25
    return burst + crack + sub + rumble + debris


def collapse():
    n = n_of(3.20)
    t = t_axis(n)
    shape = np.minimum(t / 0.15, 1.0) * np.exp(-np.maximum(t - 0.4, 0.0) / 0.9)
    rumble = band(white(n, 61), 20, 160) * shape
    groan = sine(42 + 6 * np.sin(2 * np.pi * 0.7 * t)) * shape * 0.35
    first = sine(35 + 30 * np.exp(-t / 0.1)) * env(n, 0.004, 0.15) * 0.8 + band(white(n, 62), 200, 2500) * env(n, 0.002, 0.05) * 0.6
    crunch = np.zeros(n)
    r = uniform(63, (4, 16))
    for i in range(16):
        start = 0.08 + 2.3 * r[0, i] ** 1.6  # denser early
        centre = 300 + 1100 * r[1, i]
        ln = n_of(0.25)
        grain = band(white(ln, 600 + i), centre * 0.6, centre * 1.6) * env(ln, 0.002, 0.03 + 0.05 * r[2, i])
        add_at(crunch, grain * (0.4 + 0.6 * r[3, i]) * (1.0 - 0.25 * start), n_of(start))
    settle = sine(30 + 25 * np.exp(-t / 0.1)) * env(n, 0.006, 0.18, delay=2.15) * 0.5
    trickle = crackle(n, 80 * np.exp(-t / 1.2), 64, lo=800, hi=3500) * shape * 0.25
    return rumble + groan + first + crunch * 0.9 + settle + trickle


# ---------------------------------------------------------------- loops (circular, whole cycles only)

def rotor_loop():
    n = n_of(2.0)
    t = t_axis(n)
    blade = 20.0  # blade passes per second: 40 whole periods in the loop
    ph = (t * blade) % 1.0
    tp = ph / blade
    thump = np.sin(2 * np.pi * 70 * tp) * (1 - np.exp(-tp / 0.002)) * np.exp(-tp / 0.012) * (1 - ph) ** 2
    whoosh_env = 0.35 + 0.65 * (0.5 + 0.5 * np.cos(2 * np.pi * (ph - 0.1))) ** 3
    whoosh = band(white(n, 71), 300, 1500, circular=True) * whoosh_env
    whoosh /= np.abs(whoosh).max()
    whine = (0.05 * np.sin(2 * np.pi * 1900 * t) + 0.02 * np.sin(2 * np.pi * 3800 * t)) * (1 + 0.2 * np.sin(2 * np.pi * 2 * t))
    hum = 0.12 * np.sin(2 * np.pi * 40 * t)
    return thump + 0.45 * whoosh + whine + hum


def tread_loop():
    n = n_of(2.0)
    t = t_axis(n)
    rumble = band(white(n, 81), 20, 140, circular=True)
    rumble = 0.8 * rumble / np.abs(rumble).max()
    grind = band(white(n, 82), 200, 600, circular=True)
    grind = 0.15 * grind / np.abs(grind).max()
    engine = sum(np.sin(2 * np.pi * 30 * k * t + k) / k for k in range(1, 7)) * (0.85 + 0.15 * np.sin(2 * np.pi * 15 * t)) * 0.25
    clatter = np.zeros(n)
    r = uniform(83, (3, 16))
    for i in range(16):  # 8 track-link clanks per second
        ln = n_of(0.06)
        tt = t_axis(ln)
        heavy = i % 4 == 0
        metal = sum(a * np.sin(2 * np.pi * f * tt) * np.exp(-tt / d) for f, a, d in
                    ((1250, 1.0, 0.009), (2310, 0.6, 0.006), (3570, 0.4, 0.004), (600, 0.9 if heavy else 0.2, 0.012)))
        metal += band(white(ln, 800 + i), 2000, 9000) * np.exp(-tt / 0.001) * 0.5
        start = int(n / 32 + i * n / 16 + (r[0, i] - 0.5) * 0.008 * SR)
        add_at(clatter, metal * (0.6 + 0.4 * r[1, i]) * (1.3 if heavy else 1.0), start, circular=True)
    return rumble + grind + engine + 0.35 * clatter


def foot_loop():
    n = n_of(2.0)
    bed = band(white(n, 91), 80, 600, circular=True)
    out = 0.02 * bed / np.abs(bed).max()
    r = uniform(92, (3, 12))
    for i in range(12):  # two soldiers: six steps each at 3 per second, the second softer and offset
        second = i >= 6
        j = i % 6
        ln = n_of(0.12)
        tt = t_axis(ln)
        thud = band(white(ln, 900 + i), 60, 250) * np.minimum(tt / 0.002, 1) * np.exp(-tt / 0.025)
        thud += np.sin(2 * np.pi * 90 * tt) * np.minimum(tt / 0.003, 1) * np.exp(-tt / 0.02) * 0.4
        crunch = band(white(ln, 950 + i), 1000, 4000) * env(ln, 0.002, 0.015, delay=0.012) * 0.3
        rattle = band(white(ln, 980 + i), 5000, 12000) * env(ln, 0.001, 0.005, delay=0.02) * 0.08
        step = (thud + crunch + rattle) * (1.0 if j % 2 == 0 else 0.8) * (0.45 if second else 1.0) * (0.85 + 0.3 * r[1, i])
        start = int(n / 24 + (j + (0.37 if second else 0.0)) * n / 6 + (r[0, i] - 0.5) * 0.012 * SR)
        add_at(out, step, start, circular=True)
    return out


# ---------------------------------------------------------------- ui and voice barks

def ui_click():
    n = n_of(0.06)
    return (np.sin(2 * np.pi * 2200 * t_axis(n)) * env(n, 0.0003, 0.006) + 0.3 * np.sin(2 * np.pi * 4400 * t_axis(n)) * env(n, 0.0003, 0.003)
            + band(white(n, 101), 3000, 12000) * env(n, 0.0001, 0.0008) * 0.3)


def ui_hover():
    n = n_of(0.045)
    t = t_axis(n)
    return np.sin(2 * np.pi * 3000 * t) * env(n, 0.001, 0.005) + 0.3 * np.sin(2 * np.pi * 1500 * t) * env(n, 0.001, 0.008)


def select():
    n = n_of(0.16)
    timbre = lambda f: np.sin(2 * np.pi * phase(f)) + 0.25 * np.sin(4 * np.pi * phase(f)) + 0.1 * np.sin(6 * np.pi * phase(f))
    return tone_note(n, 990, 0.0, 0.06, tau=0.035, timbre=timbre) + tone_note(n, 1320, 0.065, 0.09, tau=0.04, timbre=timbre)


def ack_infantry():
    n = n_of(0.18)
    timbre = lambda f: square(f, 11000, tilt=1.4)
    return tone_note(n, 1568, 0.0, 0.07, attack=0.002, tau=0.04, timbre=timbre) + tone_note(n, 2093, 0.075, 0.1, attack=0.002, tau=0.05, timbre=timbre)


def ack_vehicle():
    n = n_of(0.32)
    t = t_axis(n)
    timbre = lambda f: svf(saw(f, 6000), 1400, 0.9)
    notes = tone_note(n, 392, 0.02, 0.12, tau=0.08, timbre=timbre) + tone_note(n, 294, 0.15, 0.17, tau=0.1, timbre=timbre)
    def relay(at):
        e = env(n, 0.0002, 0.003, delay=at)
        return (band(white(n, 111 + int(at * 1000)), 1500, 9000) * env(n, 0.0001, 0.001, delay=at) * 0.6
                + np.sin(2 * np.pi * 3200 * t) * e * 0.35 + np.sin(2 * np.pi * 900 * t) * env(n, 0.0005, 0.008, delay=at) * 0.4)
    return notes * 1.1 + relay(0.0) + relay(0.145) * 0.7


def ack_air():
    n = n_of(0.34)
    t = t_axis(n)
    trem = 1.0 - 0.7 * (0.5 + 0.5 * np.cos(2 * np.pi * 22 * t))
    notes = tone_note(n, 660, 0.0, 0.14, tau=0.09) + tone_note(n, 880, 0.15, 0.19, tau=0.12)
    whoosh = band(white(n, 121), 1500, 6000) * env(n, 0.01, 0.15) * 0.08
    return (notes + whoosh) * trem


# ---------------------------------------------------------------- alerts

def alert():
    n = n_of(0.90)
    timbre = lambda f: square(f, 9000, tilt=1.5)
    out = np.zeros(n)
    for i in range(6):
        out += tone_note(n, 1046 if i % 2 == 0 else 784, i * 0.15, 0.14, attack=0.005, tau=1.0, release=0.01, timbre=timbre)
    return out


def build_complete():
    n = n_of(0.80)
    bell = lambda f: np.sin(2 * np.pi * phase(f)) + 0.35 * np.sin(4 * np.pi * phase(f)) + 0.12 * np.sin(2 * np.pi * phase(f * 3.01))
    out = np.zeros(n)
    for i, f in enumerate((523.25, 659.26, 783.99, 1046.5)):
        last = i == 3
        out += tone_note(n, f, i * 0.08, 0.8 - i * 0.08, attack=0.004, tau=0.3 if last else 0.12, release=0.02, timbre=bell) * (1.1 if last else 1.0)
    return out


def wave_inbound():
    n = n_of(1.60)
    t = t_axis(n)
    pulse_env = sum(env(n, 0.02, 0.18, delay=d) for d in (0.0, 0.4, 0.8, 1.2))
    pulse = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110.7 * t)) * pulse_env
    f = 220 * 3.0 ** (t / 1.4)
    rise = (np.sin(2 * np.pi * phase(f)) + 0.15 * saw(f, 6000)) * np.minimum(t / 0.3, 1.0) * np.clip((1.6 - t) / 0.15, 0, 1) * 0.35
    return pulse + rise


# ---------------------------------------------------------------- the set

# id: (builder, category, loudness target dBFS, base_volume_db, character)
SOUNDS = {
    "rifle": (rifle, "weapon", -12.0, -3.0, "sharp noise crack over a short low thump, fast decay and a faint wall slap"),
    "cannon": (cannon, "weapon", -10.0, 0.0, "deep falling boom with a mid crack and a darkening noise tail"),
    "plasma_bolt": (plasma_bolt, "weapon", -12.0, -2.0, "resonant saw zap falling in pitch with a sputtering fizz tail"),
    "explosion_small": (explosion_small, "impact", -10.0, 0.0, "noise burst under a falling low-pass, sub thump and debris crackle"),
    "explosion_large": (explosion_large, "impact", -9.0, 0.0, "big low-passed blast with two after-bursts, sub boom, rumble and long crackle"),
    "collapse": (collapse, "impact", -12.0, 0.0, "slow rumble and groan with scattered crunches and a settling thud"),
    "rotor_loop": (rotor_loop, "loop", -18.0, -6.0, "20 Hz blade thump with a noise whoosh, turbine whine and hum; seamless"),
    "tread_loop": (tread_loop, "loop", -18.0, -6.0, "engine and ground rumble with 8 metal track clanks per second; seamless"),
    "foot_loop": (foot_loop, "loop", -20.0, -6.0, "two soldiers' soft steps (thud, grit, kit rattle) at 3 steps per second; seamless"),
    "ui_click": (ui_click, "ui", -26.0, 0.0, "short clean 2.2 kHz tick with a tiny transient"),
    "ui_hover": (ui_hover, "ui", -29.0, 0.0, "very short soft 3 kHz tick, quieter than the click"),
    "select": (select, "voice", -20.0, 0.0, "two-note rising blip, B5 to E6, soft sine timbre"),
    "ack_infantry": (ack_infantry, "voice", -19.0, 0.0, "bright, short square blip G6 to C7"),
    "ack_vehicle": (ack_vehicle, "voice", -19.0, 0.0, "low falling filtered-saw blip G4 to D4 framed by relay clicks"),
    "ack_air": (ack_air, "voice", -19.0, 0.0, "E5 to A5 blip under a 22 Hz rotor-like tremolo"),
    "alert": (alert, "alert", -15.0, 0.0, "two-tone hi-lo warning, C6 and G5, three cycles"),
    "build_complete": (build_complete, "alert", -17.0, 0.0, "rising C major bell arpeggio ending on a held C6"),
    "wave_inbound": (wave_inbound, "alert", -15.0, 0.0, "four low 55 Hz pulses under a tone rising from 220 Hz"),
}


def render(sid):
    builder, category, target, _, _ = SOUNDS[sid]
    loop = category == "loop"
    x, passes = finish(builder().astype(np.float64), target, loop)
    return to_int16(x), passes


def build(out_dir=OUT, verbose=False):
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    sounds, rows = [], []
    for sid, (_, category, target, base_db, character) in SOUNDS.items():
        pcm, passes = render(sid)
        loop = category == "loop"
        (out_dir / (sid + ".wav")).write_bytes(wav_bytes(pcm, loop))
        x = pcm.astype(np.float64) / 32768.0
        loud, pk = meter_db(x), peak_db(x)
        sounds.append({"id": sid, "file": sid + ".wav", "duration_s": round(len(pcm) / SR, 4), "loop": loop,
                       "base_volume_db": base_db, "category": category, "character": character,
                       "peak_dbfs": round(pk, 2), "loudness_dbfs": round(loud, 2)})
        rows.append((sid, category, len(pcm) / SR, pk, loud, target, passes, len(pcm) * 2 + 44 + (68 if loop else 0)))
    manifest = {"generator": "tools/audio/build_sfx.py", "license": "CC0-1.0", "base_path": "res://assets/audio/sfx/",
                "format": {"sample_rate": SR, "channels": 1, "bits": 16, "container": "wav"},
                "loudness": "loudest 50 ms RMS window, 10 ms hop, dBFS", "sounds": sounds}
    (out_dir / "sfx_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if verbose:
        print("%-16s %-7s %6s %7s %7s %7s %3s %8s" % ("id", "cat", "dur_s", "peak", "loud", "target", "lim", "bytes"))
        for r in rows:
            print("%-16s %-7s %6.3f %7.2f %7.2f %7.1f %3d %8d" % r)
        print("total %d bytes" % sum(r[-1] for r in rows))
    return manifest


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else OUT, verbose=True)
