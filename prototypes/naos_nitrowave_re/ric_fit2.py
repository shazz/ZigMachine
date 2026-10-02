"""ric_fit2.py F N [SHIFT] [VIEW_K]: F1 with figure F from my set-up port
(ric_init.py) + VBL model + Timer B palette, against the same forced-figure
Hatari run (rF/, run_ric.sh F): sync near the logged entry, then per-frame
exactness."""
import re
import sys

import numpy as np
from PIL import Image

from ric_init import Init
from ric_model import Part
from ric_show import Regs, frame

F, N = int(sys.argv[1]), int(sys.argv[2])
shift = int(sys.argv[3]) if len(sys.argv) > 3 else 0
log = open(f'dumps/f1_{F}.log', errors='replace').read()
entry = int(re.findall(r'CPU=\$d98, VBL=(\d+)', log)[0])
p = Part.__new__(Part)
p.m = bytearray(open('dumps/f1_pre.bin', 'rb').read()[:0x80000])
p.shown = None
Init(p.m).run(F)
words = [int.from_bytes(p.m[0x68C2 + 2 * i:0x68C4 + 2 * i], 'big') for i in range(16)]
words[1] = 0  # $D82
regs = Regs(words)
base = p.l(0x4791C)
imgs = []
for _ in range(N):
    regs.vbl(p.m)  # $101A..$104C run before the VBL moves $4790E on
    p.vbl()
    imgs.append(frame(p.m, p.shown or base, regs, shift))
caps = {}
for c in range(entry - 10, entry + N + 10):
    try:
        caps[c] = np.array(Image.open(f'r{F}/f_{c:05d}.png').convert('RGB'))[::2, ::2]
    except FileNotFoundError:
        pass


def score(o):
    ks = [k for k in range(0, N, 2) if k + o in caps]
    return np.mean([(caps[k + o] == imgs[k]).all(-1).mean() for k in ks] or [0])


off = max(range(entry - 10, entry + 10), key=score)
print('entry logged at', entry, '; model frame 0 <-> capture', off, round(score(off), 5))
bad = []
for k in range(N):
    if k + off in caps:
        eq = (caps[k + off] == imgs[k]).all(-1)
        if not eq.all():
            ys = sorted(set(np.nonzero(~eq)[0].tolist()))
            bad.append((k, int((~eq).sum()), ys[:8]))
print(len(bad), 'of', N, 'differ', bad[:8])
if len(sys.argv) > 4:
    k = int(sys.argv[4])
    Image.fromarray(np.concatenate([imgs[k], caps[k + off]], 1)).resize((1664, 552), 0).save("/dev/shm/nw_ric.png")
    eq = (caps[k + off] == imgs[k]).all(-1)
    for y in sorted(set(np.nonzero(~eq)[0].tolist()))[:40]:
        xs = np.nonzero(~eq[y])[0]
        print(y, len(xs), xs.min(), xs.max(), imgs[k][y, xs[0]], caps[k + off][y, xs[0]])
