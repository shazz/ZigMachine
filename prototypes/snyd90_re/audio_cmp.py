"""audio_cmp.py HATARI.avi FROM_S OURS.f32: does an SNDH sound like Hatari's recording of the original?

The sample replays (F6) cannot be compared register by register (the YM volumes change 7400
times a second), so the comparison is of the SOUND: Hatari's AVI audio (run_hatari.sh with
--sound 44100) from FROM_S seconds on, against sndh_pcm.mjs's render. Both become 20 ms
frames of log-magnitude spectra (512-point FFT, 40 bands up to 8 kHz); the best lag (within
+-20 s) is found on the loudness envelopes, and at it the script prints the envelope and
the mean per-frame spectral correlations. Run with numpy (uv run --with numpy).
"""
import struct
import sys

import numpy as np

SR = 44100
HOP = SR // 50


def hatari_audio(path: str, start_s: float) -> np.ndarray:
    d = open(path, 'rb').read()
    out, p = [], 0
    while True:
        p = d.find(b'01wb', p)
        if p < 0:
            break
        n = struct.unpack('<I', d[p + 4:p + 8])[0]
        out.append(np.frombuffer(d[p + 8:p + 8 + n], dtype='<i2'))
        p += 8 + n
    pcm = np.concatenate(out).reshape(-1, 2).mean(axis=1) / 32768.0
    return pcm[int(start_s * SR):]


def frames(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    n = len(x) // HOP - 1
    win = np.hanning(512)
    spec = np.empty((n, 40))
    env = np.empty(n)
    edges = np.linspace(0, 512 * 8000 // SR, 41).astype(int)
    for i in range(n):
        seg = x[i * HOP:i * HOP + 512]
        if len(seg) < 512:
            seg = np.pad(seg, (0, 512 - len(seg)))
        mag = np.abs(np.fft.rfft(seg * win))
        spec[i] = [np.log1p(mag[a:b + 1].sum()) for a, b in zip(edges[:-1], edges[1:])]
        env[i] = np.sqrt(np.mean(seg ** 2))
    return spec, env


def corr(a: np.ndarray, b: np.ndarray) -> float:
    a, b = a - a.mean(), b - b.mean()
    return float((a * b).sum() / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-12))


def main() -> None:
    ref = hatari_audio(sys.argv[1], float(sys.argv[2]))
    ours = np.fromfile(sys.argv[3], dtype='<f4')
    rs, re_ = frames(ref)
    os_, oe = frames(ours)
    n = min(len(oe), len(re_) - 1000)
    best = max((corr(re_[k:k + n], oe[:n]), k) for k in range(0, min(1000, len(re_) - n)))
    lag = best[1]
    spec = np.mean([corr(rs[lag + i], os_[i]) for i in range(n)])
    print(f'envelope correlation {best[0]:.3f} at lag {lag} frames ({lag / 50:.1f} s into the recording)')
    print(f'mean per-frame spectrum correlation {spec:.3f} over {n} frames')


if __name__ == '__main__':
    main()
