"""For capture rows Y0..Y1 of model frame K / capture K+OFF, find the RAM address
(relative to the displayed screen base) whose 230-byte line matches, first pixel
at capture x -4.   fit_rows.py K OFF Y0 Y1"""
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
    best = (0, None, None)
    for rel in range(exp - 1200, exp + 1200, 2):
        for x0 in (-4, 0, -8, 4):
            line = pal[chunky(mem, shown + rel, 240, 1, 480)[0]]
            seg = line[-x0:-x0 + 412] if x0 <= 0 else None
            if seg is None or len(seg) < 412:
                continue
            eq = float((seg == c[y, :412]).all(-1).mean())
            if eq > best[0]:
                best = (eq, rel, x0)
    print(f'row {y}: best {best[0]:.3f} rel {best[1]} (expected {exp}, d={best[1] - exp if best[1] else None}) x0 {best[2]}',
          'black' if (c[y] == 0).all() else '')
