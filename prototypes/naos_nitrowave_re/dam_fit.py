"""dam_fit.py N C0 C1: sync the F3 model to the Hatari capture p3/ (frameskip
0), then fit K (the capture x of cycle 0) and report per-frame exactness.
    env K=..  skips the K search;  env OFF=.. skips the sync search."""
import os
import sys

import numpy as np
from PIL import Image

import dam_main as D
import dam_show as S
from dam_model import Part

N, C0, C1 = (int(a) for a in sys.argv[1:4])
caps = {}
for c in range(C0, C1):
    try:
        caps[c] = np.array(Image.open(f'p3/f_{c:05d}.png').convert('RGB'))[::2, ::2]
    except FileNotFoundError:
        pass
p = Part()
shots = []
for _ in range(N):
    shown = D.frame(p)
    shots.append((shown, bytes(p.m[shown:shown + 0xEB00]), bytes(p.m[0x5F24:0x5F24 + 1024])))


def img(i, k):
    shown, scr, tab = shots[i]
    mem = bytearray(0x100000)
    mem[shown:shown + 0xEB00] = scr
    mem[0x5F24:0x5F24 + 1024] = tab
    return S.image(mem, shown, k)


k0 = int(os.environ.get('K', '40'))
if 'OFF' in os.environ:
    off = int(os.environ['OFF'])
else:
    probe = [img(i, k0) for i in range(0, N, max(1, N // 6))]
    idx = list(range(0, N, max(1, N // 6)))
    def score(o):
        return np.mean([(caps[i + o] == im).all(-1).mean() for i, im in zip(idx, probe) if i + o in caps] or [0])
    off = max(range(C0, C1 - N), key=score)
    print('model frame 0 <-> capture', off, round(score(off), 4))
if 'K' not in os.environ:
    i = N // 2
    best = max(range(-120, 60, 2), key=lambda k: (caps[i + off] == img(i, k)).all(-1).mean())
    print('K', best, (caps[i + off] == img(i, best)).all(-1).mean())
    k0 = best
bad = []
for i in range(N):
    if i + off in caps:
        eq = (caps[i + off] == img(i, k0)).all(-1)
        if not eq.all():
            ys, xs = np.nonzero(~eq)
            bad.append((i, int((~eq).sum()), sorted(set(ys.tolist()))[:8]))
print(len(bad), 'of', N, 'frames differ', bad[:6])
