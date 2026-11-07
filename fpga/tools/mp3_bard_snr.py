"""The BARD MP3 study's accuracy check: a decoder's s16le PCM against ffmpeg's float decoder.

    uv run --with numpy python tools/mp3_bard_snr.py <in.mp3> <decoded.raw> <channels>

Prints the lag that aligns them (expected 0), the SNR in dB, the max and RMS error in LSB.
"""

import subprocess
import sys

import numpy as np


def reference(mp3: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp3, "-f", "s16le", "-acodec", "pcm_s16le", "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.int64)


def best_lag(ref: np.ndarray, dec: np.ndarray, ch: int) -> int:
    n = min(len(ref), len(dec)) - 2400 * ch
    best = min(range(-1152, 1153), key=lambda k: np.abs(ref[2400 * ch : n] - dec[2400 * ch + k * ch : n + k * ch]).sum())
    return best


def main() -> int:
    mp3, raw, ch = sys.argv[1], sys.argv[2], int(sys.argv[3])
    ref = reference(mp3)
    dec = np.fromfile(raw, dtype="<i2").astype(np.int64)
    lag = best_lag(ref, dec, ch)
    a, b = (ref, dec[lag * ch :]) if lag >= 0 else (ref[-lag * ch :], dec)
    n = min(len(a), len(b))
    err = a[:n] - b[:n]
    snr = 10 * np.log10((a[:n] ** 2).sum() / max(1, (err**2).sum()))
    print(f"{raw}: lag {lag} samples {n // ch} SNR {snr:.1f} dB max {np.abs(err).max()} LSB rms {np.sqrt((err**2).mean()):.2f} LSB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
