"""diff_part.py MODULE K CAPTURE OUT.png: model frame K vs a capture, 3 panels,
and the differing rows / columns."""
import importlib
import sys

import numpy as np
from PIL import Image

from stimg import chunky, palette

mod = importlib.import_module(sys.argv[1])
K = int(sys.argv[2])
p = mod.Part()
for _ in range(K + 1):
    shown = p.frame()
pal = palette(p.m, mod.PALETTE)
lo, hi = mod.ROWS
out = np.zeros((276, 416, 3), np.uint8)
out[lo:hi, :412] = pal[chunky(p.m, shown + 160, 230, hi - 1, 460)[lo - 1:hi - 1, 4:416]]
cap = np.array(Image.open(sys.argv[3]).convert('RGB'))[::2, ::2]
bad = ~(out == cap).all(-1)
ys, xs = np.nonzero(bad)
print('bad', bad.sum(), 'rows', sorted(set(ys.tolist()))[:12], '...', ys.max() if len(ys) else '', 'cols', xs.min() if len(xs) else '', xs.max() if len(xs) else '')
d = np.zeros_like(out)
d[bad] = (255, 0, 0)
Image.fromarray(np.concatenate([out, cap, d], 1)).resize((2496, 552), 0).save(sys.argv[4])
