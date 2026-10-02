"""Brute-force fit of capture rows Y0..Y1: any start address (even) in a window,
any first-pixel x0 in [-16, 64], scored on the non-black extent [lo, hi) of the
capture row. fit_rows2.py K OFF Y0 Y1"""
import sys

import numpy as np
from PIL import Image

from menu_model import menu_frames
from stimg import chunky, palette

K, OFF, Y0, Y1 = (int(a) for a in sys.argv[1:5])
for shown, mem in menu_frames(K + 1):
    pass
pal = palette(mem, 0xC3F8)
c = np.array(Image.open(f'mshots/m_{K + OFF:05d}.png').convert('RGB'))[::2, ::2]
for y in range(Y0, Y1):
    exp = 160 + 230 * (y - 1)
    res = []
    for rel in range(exp - 400, exp + 400, 2):
        line = pal[chunky(mem, shown + rel, 480, 1, 480)[0]]
        for x0 in range(-16, 65, 4):
            img = np.zeros((416, 3), np.uint8)
            lo, hi = max(x0, 0), min(416, x0 + 480)
            img[lo:hi] = line[lo - x0:hi - x0]
            for a, b in ((0, 412), (max(x0, 0), 412), (max(x0, 0), 368), (0, 368)):
                seg = np.zeros((416, 3), np.uint8)
                seg[a:b] = img[a:b]
                res.append((int((seg != c[y]).any(-1).sum()), rel - exp, x0, a, b))
    res.sort()
    print(f'row {y}: nonzero cap px {int((c[y] != 0).any(-1).sum())}; best', res[:3])
