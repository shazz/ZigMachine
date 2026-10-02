"""Fit a part's capture rows to its screen in a RAM dump.
    fit_part.py DUMP CAPTURE.png PALADDR BASE [STRIDE]
For each capture row: is it black, or which line of BASE (stride STRIDE, 230
default) with first pixel at capture x -X matches it best (whole row, x < 412)?
Prints runs of rows with the same (line - row, x0) relation."""
import sys

import numpy as np
from PIL import Image

from stimg import chunky, palette

mem = open(sys.argv[1], 'rb').read()
cap = np.array(Image.open(sys.argv[2]).convert('RGB'))[::2, ::2]
pal = palette(mem, int(sys.argv[3], 16))
base = int(sys.argv[4], 16)
stride = int(sys.argv[5]) if len(sys.argv) > 5 else 230
runs = []
for y in range(cap.shape[0]):
    row = cap[y, :412]
    if (row == 0).all():
        res = ('black',)
    else:
        best = (0, None, None)
        for line in range(-2, 280):
            a = base + 160 + line * stride if line >= 0 else base + 160 * (line + 1)
            if a < 0:
                continue
            px = pal[chunky(mem, a, 240, 1, 480)[0]]
            for x0 in (4, 0, 8, 12, 16, -48, -52, 48):
                seg = px[x0:x0 + 412] if x0 >= 0 else None
                if seg is None:
                    continue
                eq = float((seg == row).all(-1).mean())
                if eq > best[0]:
                    best = (eq, line, x0)
        res = ('line', best[1] - y, best[2], round(best[0], 3))
    if runs and runs[-1][1][:3] == res[:3]:
        runs[-1][2] = y
        runs[-1][3] = min(runs[-1][3], res[3] if len(res) > 3 else 1)
    else:
        runs.append([y, res, y, res[3] if len(res) > 3 else 1])
for a, res, b, worst in runs:
    print(f'rows {a}..{b}: {res[:3]} worst {worst}')
