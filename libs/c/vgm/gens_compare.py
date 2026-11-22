"""LOCAL tool: our VGM engine against a reference render (libs/c/vgm/README.md "Accuracy").

    uv run --with numpy --with scipy python libs/c/vgm/gens_compare.py <ref.wav> <ours.wav> [seconds] [skip]

The reference is any 16-bit stereo WAV of the same tune (on Matt's machine: libvgm's vgm2wav forced to
the Gens YM2612 core, prototypes/gens_fm/ref, GPL and never committed); ours is fpga/tools/vgm_render's
WAV at the engine's rate, resampled here (FFT) to the reference's. Prints the best lag, the gain, the
correlation, the residual below the reference, and the level difference per octave band. Nothing from
the reference is kept: only these numbers.
"""
import sys
import wave

import numpy as np
from scipy import signal


def load(path):
    with wave.open(path) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 2, path
        rate = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, 2).astype(np.float64)
    return rate, x


def main():
    rr, ref = load(sys.argv[1])
    ro, ours = load(sys.argv[2])
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    skip = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
    ours = ours[: int((secs + skip + 1) * ro)]
    if ro != rr:
        ours = signal.resample(ours, int(len(ours) * rr / ro), axis=0)
    a0, n = int(skip * rr), int(secs * rr)
    a, b = ref[a0 : a0 + n], ours[a0 : a0 + n]
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    m, t = a.sum(1), b.sum(1)
    cc = signal.correlate(t, m, mode="full", method="fft")
    mid = len(m) - 1
    win = cc[mid - 400 : mid + 401]
    lag = int(np.argmax(win)) - 400
    a2, b2 = (a[: n - lag], b[lag:]) if lag >= 0 else (a[-lag:], b[: n + lag])
    g = (a2 * b2).sum() / max((b2 * b2).sum(), 1e-9)
    res = a2 - g * b2
    corr = (a2 * b2).sum() / np.sqrt((a2**2).sum() * (b2**2).sum())
    db = 10 * np.log10((res**2).sum() / (a2**2).sum())
    print(f"seconds {n / rr:.1f}  rms ref {np.sqrt((a**2).mean()):.0f} ours {np.sqrt((b**2).mean()):.0f}")
    print(f"lag {lag} (ours behind)  gain ref/ours {g:.4f}  corr {corr:.5f}  residual {-db:.1f} dB")
    f, pa = signal.welch(a2.sum(1), rr, nperseg=4096)
    _, pb = signal.welch(g * b2.sum(1), rr, nperseg=4096)
    edges = [60, 125, 250, 500, 1000, 2000, 4000, 8000, 13000]
    bands = []
    for lo, hi in zip(edges[:-1], edges[1:], strict=True):
        s = (f >= lo) & (f < hi)
        bands.append(f"{lo}:{10 * np.log10(pb[s].sum() / max(pa[s].sum(), 1e-12)):+.1f}")
    print("band dB (ours-ref):", " ".join(bands))
    k = len(a2) // rr
    ea = np.sqrt((a2[: k * rr] ** 2).reshape(k, -1).mean(1))
    eb = np.sqrt((b2[: k * rr] ** 2).reshape(k, -1).mean(1))
    print(f"per-second loudness corr {np.corrcoef(ea, eb)[0, 1]:.4f}")


if __name__ == "__main__":
    main()
