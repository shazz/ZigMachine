"""Capture rows 258..275 (below the last 230-byte line the menu's VBL opens):
are they the same in every m3 capture frame? Prints the distinct pixels."""
import glob

import numpy as np
from PIL import Image

ref = None
n = 0
for p in sorted(glob.glob('m3/m_*.png'))[60::25]:
    c = np.array(Image.open(p).convert('RGB'))[::2, ::2][258:]
    if ref is None:
        ref = c
    assert (c == ref).all(), p
    n += 1
ys, xs = np.nonzero((ref != 0).any(-1))
print(n, 'frames identical; non-black pixels (row, x, rgb):')
for y, x in zip(ys, xs):
    print(258 + y, x, tuple(int(v) for v in ref[y, x]))
