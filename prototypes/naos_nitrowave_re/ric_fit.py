"""ric_fit.py N C0 C1 [HBL_SHIFT]: F1 model (RAM + Timer B palette) vs the
Hatari capture p1/ (frameskip 0): sync, then per-frame exactness.
env OFF=.. skips the sync search."""
import os
import sys

import numpy as np
from PIL import Image

from ric_model import Part
from ric_show import Regs, frame

N, C0, C1 = (int(a) for a in sys.argv[1:4])
shift = int(sys.argv[4]) if len(sys.argv) > 4 else 0
caps = {}
for c in range(C0, C1):
    try:
        caps[c] = np.array(Image.open(f'p1/f_{c:05d}.png').convert('RGB'))[::2, ::2]
    except FileNotFoundError:
        pass
p = Part()
words = [int.from_bytes(p.m[0x68C2 + 2 * i:0x68C4 + 2 * i], 'big') for i in range(16)]
words[1] = 0  # $D82
regs = Regs(words)
base = p.l(0x4791C)
imgs = []
for _ in range(N):
    p.vbl()
    shown = p.shown or base  # the base the VBL just set shows THIS frame
    regs.vbl(p.m)
    imgs.append(frame(p.m, shown, regs, shift))
if 'OFF' in os.environ:
    off = int(os.environ['OFF'])
else:
    def score(o):
        ks = [k for k in range(0, N, 3) if k + o in caps]
        return np.mean([(caps[k + o] == imgs[k]).all(-1).mean() for k in ks] or [0])
    off = max(range(C0, C1 - N), key=score)
    print('model frame 0 <-> capture', off, round(score(off), 4))
bad = []
for k in range(N):
    if k + off in caps:
        eq = (caps[k + off] == imgs[k]).all(-1)
        if not eq.all():
            ys = sorted(set(np.nonzero(~eq)[0].tolist()))
            bad.append((k, int((~eq).sum()), ys[:6]))
print(len(bad), 'of', N, 'differ', bad[:8])
if len(sys.argv) > 5:
    k = int(sys.argv[5])
    Image.fromarray(np.concatenate([imgs[k], caps[k + off]], 1)).resize((1664, 552), 0).save('/dev/shm/nw_ric.png')
