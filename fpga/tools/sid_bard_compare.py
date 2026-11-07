"""The BARD SID study: compare cRSID renders with the reference player's (sidplayfp/reSIDfp, local only).

A sample-exact comparison is meaningless between two SID emulators (different filters, a dither LFSR
in cRSID, start-up timing), so this compares what an ear compares: the level (RMS), the 20 ms loudness
envelope (correlation at the best lag, which also shows the two play the same notes at the same time)
and the spectrum in octave bands (dB difference per band, 63 Hz-16 kHz).
    uv run --with numpy python tools/sid_bard_compare.py <ref.wav> <test.wav> [...more test wavs]
"""

from __future__ import annotations

import sys
import wave
from pathlib import Path

import numpy as np

BANDS = [63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]


def load(path: Path) -> tuple[np.ndarray, int]:
    """Mono float samples of a 16-bit WAV (the left channel of a stereo one) and its rate."""
    with wave.open(str(path)) as w:
        rate, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64)
    return x[::ch] / 32768.0, rate


def envelope(x: np.ndarray, rate: int) -> np.ndarray:
    hop = rate // 50
    n = len(x) // hop
    return np.sqrt((x[: n * hop].reshape(n, hop) ** 2).mean(axis=1))


def best_lag_corr(a: np.ndarray, b: np.ndarray, max_lag: int = 150) -> tuple[float, int]:
    best = (-1.0, 0)
    for lag in range(-max_lag, max_lag + 1):
        x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
        n = min(len(x), len(y))
        if n < 10 or x[:n].std() == 0 or y[:n].std() == 0:
            continue
        c = float(np.corrcoef(x[:n], y[:n])[0, 1])
        best = max(best, (c, lag))
    return best


def band_db(x: np.ndarray, rate: int) -> np.ndarray:
    spec = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / rate)
    out = []
    for fc in BANDS:
        sel = (freqs >= fc / np.sqrt(2)) & (freqs < fc * np.sqrt(2))
        out.append(10 * np.log10(spec[sel].sum() + 1e-12))
    return np.array(out)


def main() -> int:
    ref, rate = load(Path(sys.argv[1]))
    ref_bands = band_db(ref, rate)
    print(f"{'file':34} {'rms dB':>7} {'env corr':>8} {'lag ms':>6}  band dB vs ref ({'/'.join(map(str, BANDS))} Hz)")
    print(f"{Path(sys.argv[1]).name:34} {20 * np.log10(ref.std() + 1e-12):7.1f}")
    for p in sys.argv[2:]:
        x, r = load(Path(p))
        if r != rate:
            print(f"{p}: rate {r} != {rate}")
            continue
        n = min(len(x), len(ref))
        corr, lag = best_lag_corr(envelope(ref[:n], rate), envelope(x[:n], rate))
        d = band_db(x[:n], rate) - band_db(ref[:n], rate) if n < len(ref) else band_db(x[:n], rate) - ref_bands
        bands = " ".join(f"{v:+5.1f}" for v in d)
        print(f"{Path(p).name:34} {20 * np.log10(x.std() + 1e-12):7.1f} {corr:8.3f} {lag * 20:6d}  {bands}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
