"""Where does model frame K differ from capture K+OFF? diff_menu.py K OFF"""
import sys

import numpy as np
from PIL import Image

from menu_model import menu_frames
from stimg import chunky, palette

K, OFF = int(sys.argv[1]), int(sys.argv[2])
for k, (shown, mem) in enumerate(menu_frames(K + 1)):
    pass
pal = palette(mem, 0xC3F8)
idx = np.zeros((276, 416), np.uint8)
idx[1:261, :412] = chunky(mem, shown + 160, 230, 260, 460)[:, 4:416]  # capture x 412.. is black
f = pal[idx]
c = np.array(Image.open(f'mshots/m_{K + OFF:05d}.png').convert('RGB'))[::2, ::2]
bad = ~(f == c).all(-1)
ys, xs = np.nonzero(bad)
print('diff px', bad.sum(), 'rows', sorted(set(ys.tolist()))[:40], 'x range', xs.min() if len(xs) else None, xs.max() if len(xs) else None)
for y in sorted(set(ys.tolist()))[:6]:
    xx = xs[ys == y]
    print(y, xx[:20], 'model', [tuple(v) for v in f[y, xx[:4]]], 'cap', [tuple(v) for v in c[y, xx[:4]]])
