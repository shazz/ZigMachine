"""Fit the Hatari bordered capture (416x276 at 2x) to the menu screen in RAM:
find (dx, dy) such that capture pixel (x, y) == screen line (y - dy) pixel (x - dx),
where screen line 0 is the first 230-byte line (base + 160)."""
import sys

import numpy as np
from PIL import Image

from stimg import chunky, palette

TD = open('menu_td.bin', 'rb').read()
pal = palette(TD, 0xC3F8)
idx = chunky(TD, 0xC418 + 160, 230, 260, 460)
rgb = pal[idx]
cap = np.array(Image.open(sys.argv[1]).convert('RGB'))[::2, ::2]
H, W = cap.shape[:2]
best = None
for dy in range(-10, 40):
    for dx in range(-60, 20):
        ys, xs = np.mgrid[0:H, 0:W]
        sy, sx = ys - dy, xs - dx
        ok = (sy >= 0) & (sy < 260) & (sx >= 0) & (sx < 460)
        if ok.sum() < 50000:
            continue
        eq = (rgb[sy[ok], sx[ok]] == cap[ok]).all(-1).mean()
        if best is None or eq > best[0]:
            best = (eq, dx, dy, ok.sum())
print('best match %.4f at dx=%d dy=%d over %d px' % best)
