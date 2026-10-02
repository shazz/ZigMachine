"""ric_survey.py F N OFF: which rows of the F1 model differ from rF/ captures
over N frames, how often, and the furthest x of a difference."""
import sys
from collections import Counter

import numpy as np
from PIL import Image

from ric_init import Init
from ric_model import Part
from ric_show import Regs, frame

F, N, OFF = (int(a) for a in sys.argv[1:4])
p = Part.__new__(Part)
p.m = bytearray(open('dumps/f1_pre.bin', 'rb').read()[:0x80000])
p.shown = None
Init(p.m).run(F)
words = [int.from_bytes(p.m[0x68C2 + 2 * i:0x68C4 + 2 * i], 'big') for i in range(16)]
words[1] = 0
regs = Regs(words)
base = p.l(0x4791C)
rows, maxx, frames = Counter(), Counter(), Counter()
lag = [base, base]  # the base a VBL writes shows two captured frames later
for k in range(N):
    regs.vbl(p.m)
    p.vbl()
    lag.append(p.shown or base)
    im = frame(p.m, lag[-3], regs, 0)
    cap = np.array(Image.open(f'r{F}/f_{OFF + k:05d}.png').convert('RGB'))[::2, ::2]
    eq = (cap == im).all(-1)
    for y in set(np.nonzero(~eq)[0].tolist()):
        xs = np.nonzero(~eq[y])[0]
        rows[y] += 1
        maxx[y] = max(maxx[y], int(xs.max()))
        frames[k] += len(xs)
print('rows (count, max x):', [(y, rows[y], maxx[y]) for y in sorted(rows)])
print('pixels per frame:', [(k, frames[k]) for k in range(0, N, 10)])
