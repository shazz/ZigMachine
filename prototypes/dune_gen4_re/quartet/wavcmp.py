"""wavcmp.py HATARI.wav FROM_S OURS.wav SECONDS: is OURS the tune Hatari plays from FROM_S on?

Both are reduced to an onset curve (the rise of the 10 ms RMS envelope, which is what a sample
tune's notes are, whatever the two YM emulations' volume curves and filters do). The best lag
within +-2 s of FROM_S and the correlation there are printed, with the correlation of OURS
against stretches of Hatari away from it (another tune or silence) for scale.
"""
import sys
import wave

import numpy as np

HOP = 441  # 10 ms at 44.1 kHz


def mono(path):
    w = wave.open(path)
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
    a = a.reshape(-1, w.getnchannels()).mean(axis=1)
    assert w.getframerate() == 44100
    return a


def onsets(a):
    n = len(a) // HOP
    rms = np.sqrt((a[:n * HOP].reshape(n, HOP) ** 2).mean(axis=1))
    rise = np.maximum(np.diff(rms, prepend=rms[0]), 0)
    return (rise - rise.mean()) / (rise.std() + 1e-9)


def corr(x, y):
    n = min(len(x), len(y))
    x, y = x[:n] - x[:n].mean(), y[:n] - y[:n].mean()
    return float((x * y).sum() / (np.sqrt((x * x).sum() * (y * y).sum()) + 1e-9))


def main():
    hat, at, ours, secs = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4])
    h, o = onsets(mono(hat)), onsets(mono(ours))
    n = int(secs * 100)
    o = o[:n]
    start = int(at * 100)
    best = max(range(max(0, start - 200), start + 200), key=lambda k: corr(h[k:k + n], o))
    c = corr(h[best:best + n], o)
    away = [corr(h[k:k + n], o) for k in range(0, len(h) - n, 300) if abs(k - best) > n]
    print(f'best lag: Hatari {best / 100:.2f} s, correlation {c:.3f}; '
          f'elsewhere max {max(away, default=0):.3f} mean {np.mean(away) if away else 0:.3f}')


if __name__ == '__main__':
    main()
