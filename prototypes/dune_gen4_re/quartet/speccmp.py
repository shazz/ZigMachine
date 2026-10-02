"""speccmp.py OURS.wav AT_S HATARI.wav [SECONDS]: log-spectrogram correlation of OURS against
HATARI from AT_S (best lag within -3..+6 s). Run with PYTHONPATH=. (wavcmp.mono) and numpy.
"""
import sys
import numpy as np
import wavcmp


def spec(a, hop=441, n=2048):
    fr = (len(a) - n) // hop
    w = np.hanning(n)
    S = np.abs(np.fft.rfft(np.stack([a[i * hop:i * hop + n] * w for i in range(fr)]), axis=1))[:, 5:400]
    S = np.log1p(S)
    return S - S.mean(1, keepdims=True)


h = wavcmp.mono(sys.argv[3])
o = wavcmp.mono(sys.argv[1])
at = float(sys.argv[2])
secs = float(sys.argv[4]) if len(sys.argv) > 4 else 20
H = spec(h[int((at - 3) * 44100):int((at + secs + 6) * 44100)])
for st in (1.0,):
    oo = o[:int(secs * 44100 * st)]
    oo = np.interp(np.arange(0, len(oo), st), np.arange(len(oo)), oo)
    O = spec(oo)
    best = (-1, 0)
    for lag in range(0, len(H) - len(O)):
        Hs = H[lag:lag + len(O)]
        c = (Hs * O).sum() / np.sqrt((Hs * Hs).sum() * (O * O).sum())
        best = max(best, (c, lag))
    print(st, 'corr %.3f at %.2f s' % (best[0], at - 3 + best[1] / 100))
