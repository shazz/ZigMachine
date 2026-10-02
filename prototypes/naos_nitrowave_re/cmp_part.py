"""Compare a part model with its Hatari capture (pN/f_<VBL>.png, frameskip 0).
    cmp_part.py MODULE N_FRAMES CAP0 CAP1 [OFF]
MODULE.Part().frame() returns the screen shown while that VBL ran; capture row
y is screen line y-1 from x+4 (fit_part.py), rows LAST.. black (MODULE.ROWS =
(first_row, last_row_exclusive) of the lit rows, MODULE.PALETTE)."""
import importlib
import sys

import numpy as np
from PIL import Image

from stimg import chunky, palette

mod = importlib.import_module(sys.argv[1])
N, C0, C1 = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
DIR = mod.CAPDIR
p = mod.Part()
pal = palette(p.m, mod.PALETTE)
lo, hi = mod.ROWS


def img(shown):
    idx = np.zeros((276, 416), np.uint8)
    lines = chunky(p.m, shown + 160, 230, hi - 1, 460)[:, 4:416]
    out = pal[idx]
    out[lo:hi, :412] = pal[lines[lo - 1:hi - 1]]
    return out


frames = [img(p.frame()) for _ in range(N)]
caps = {}
for c in range(C0, C1):
    try:
        caps[c] = np.array(Image.open(f'{DIR}/f_{c:05d}.png').convert('RGB'))[::2, ::2]
    except FileNotFoundError:
        pass


def score(off):
    ks = [k for k in range(0, N, 5) if k + off in caps]
    return sum(float((caps[k + off] == frames[k]).all(-1).mean()) for k in ks) / max(1, len(ks))


if len(sys.argv) > 5:
    off = int(sys.argv[5])
else:
    off = max(range(C0 - N, C1), key=score)
    print('model frame 0 <-> capture', off, 'mean', round(score(off), 5))
marks = ''.join('.' if (caps[k + off] == f).all() else 'x' for k, f in enumerate(frames) if k + off in caps)
print(marks)
print(marks.count('x'), 'of', len(marks), 'not pixel-exact')
