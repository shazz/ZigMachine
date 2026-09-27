#!/usr/bin/env python3
"""SKYSTRIKE's ZIG-mode sound effects, synthesized (stdlib only, reproducible).

The original plays two Maestro digis (the gun burst, the crash) and a PSG
noise splash. ZIG mode plays these instead, on the machine's Paula channels
through the STE DMA chip (apps/zig/scenes/skystrike/zig_sound.zig). Nothing is
downloaded or sampled: every sound is filtered noise and a few sines under
envelopes, from a fixed-seed generator, so the bytes are the same on every run.

Output: signed 8-bit mono PCM at one of the STE DMA rates (6258 / 12517 Hz),
apps/zig/assets/screens/skystrike/sfx/<name>.raw, which sound.s includes. The
order and rates here are sound.s's ztab and zig_sound.zig's Sample enum.

    python3 tools/skystrike/make_sfx.py [--check]

--check rebuilds in memory and fails if a committed file differs.
"""
import math
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "apps", "zig", "assets", "screens", "skystrike", "sfx")
LO, HI = 6258, 12517  # STE DMA rates (mode bits 0 and 1)
PEAK = 118


class Noise:
    """xorshift32: white noise in -1..1 from a fixed seed."""

    def __init__(self, seed):
        self.s = seed

    def __call__(self):
        s = self.s
        s ^= (s << 13) & 0xFFFFFFFF
        s ^= s >> 17
        s ^= (s << 5) & 0xFFFFFFFF
        self.s = s
        return s / 2147483648.0 - 1.0


def lowpass(fc, fs):
    """One-pole low-pass coefficient for cutoff fc at rate fs."""
    return 1.0 - math.exp(-2.0 * math.pi * fc / fs)


def gun(fs=HI):
    """One shot of a burst, 75 ms, looped by the chip: a crack and a thump."""
    n, rnd, y, out = int(fs * 0.075), Noise(0x6A11), 0.0, []
    for i in range(n):
        t = i / fs
        y += lowpass(2600, fs) * (rnd() - y)
        crack = y * math.exp(-t / 0.011)
        thump = math.sin(2 * math.pi * 95 * t) * math.exp(-t / 0.018)
        out.append((crack * 1.0 + thump * 0.8) * min(1.0, i / 12.0))
    return out


def bang(fs=HI):
    """An airburst, 450 ms: noise whose cutoff falls from 3 kHz to 250 Hz."""
    n, rnd, y, out = int(fs * 0.45), Noise(0xB4A6), 0.0, []
    for i in range(n):
        t = i / fs
        y += lowpass(250 + 2750 * math.exp(-t / 0.06), fs) * (rnd() - y)
        out.append(y * math.exp(-t / 0.13) * min(1.0, i / 20.0))
    return out


def crash(fs=LO):
    """A crash, 1 s: a low rumble with metal crackling through it."""
    n, rnd, crk, y, out = int(fs * 1.0), Noise(0xC7A5), Noise(0x5EED), 0.0, []
    for i in range(n):
        t = i / fs
        y += lowpass(420, fs) * (rnd() - y)
        spark = crk() if crk() > 0.93 else 0.0
        out.append((y * 2.2 + spark * 0.5 * math.exp(-t / 0.4)) * math.exp(-t / 0.32) * min(1.0, i / 8.0))
    return out


def bomb(fs=LO):
    """A ground explosion, 900 ms: a falling boom under dark noise."""
    n, rnd, y, ph, out = int(fs * 0.9), Noise(0xB0B0), 0.0, 0.0, []
    for i in range(n):
        t = i / fs
        ph += 2 * math.pi * (32 + 48 * math.exp(-t / 0.12)) / fs
        y += lowpass(120 + 700 * math.exp(-t / 0.08), fs) * (rnd() - y)
        boom = math.sin(ph) * math.exp(-t / 0.22)
        out.append((boom * 0.9 + y * 2.0 * math.exp(-t / 0.3)) * min(1.0, i / 6.0))
    return out


def splash(fs=HI):
    """Water, 550 ms: bright noise swelling in and washing away."""
    n, rnd, lo, out = int(fs * 0.55), Noise(0x5A1A), 0.0, []
    for i in range(n):
        t = i / fs
        x = rnd()
        lo += lowpass(900, fs) * (x - lo)
        hiss = x - lo  # the part above 900 Hz
        swell = min(1.0, t / 0.03) * math.exp(-t / 0.16)
        out.append(hiss * swell * (0.75 + 0.25 * math.sin(2 * math.pi * 23 * t)))
    return out


def hit(fs=HI):
    """A scrape on the deck, 220 ms: a clank of inharmonic partials."""
    n, rnd, out = int(fs * 0.22), Noise(0x417), []
    for i in range(n):
        t = i / fs
        ring = sum(math.sin(2 * math.pi * f * t) / k for k, f in enumerate((523, 1187, 1873), 1))
        out.append(ring * math.exp(-t / 0.045) + rnd() * 0.6 * math.exp(-t / 0.012))
    return out


# name, synth, rate -- sound.s's ztab order (zig_sound.zig's Sample).
SOUNDS = [("gun", gun, HI), ("bang", bang, HI), ("crash", crash, LO),
          ("bomb", bomb, LO), ("splash", splash, HI), ("hit", hit, HI)]


def pcm(samples):
    """Normalised to PEAK, as signed bytes."""
    top = max(abs(s) for s in samples) or 1.0
    return bytes((int(round(s / top * PEAK)) & 0xFF) for s in samples)


def build():
    return {name: pcm(fn(rate)) for name, fn, rate in SOUNDS}


def main():
    check = "--check" in sys.argv
    files = build()
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, data in files.items():
        path = os.path.join(OUT, name + ".raw")
        if check:
            old = open(path, "rb").read() if os.path.exists(path) else b""
            bad += old != data
            continue
        with open(path, "wb") as f:
            f.write(data)
    total = sum(len(d) for d in files.values())
    print(f"make_sfx: {len(files)} samples, {total} bytes" + (f", {bad} stale" if check else ""))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
