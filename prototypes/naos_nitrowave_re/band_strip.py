"""Stack model (left) vs capture (right) crops of the band rows for frames K0..K1.
band_strip.py OFF K0 K1"""
import sys

import numpy as np
from PIL import Image

from menu_model import menu_frames
from stimg import chunky, palette

OFF, K0, K1 = (int(a) for a in sys.argv[1:4])
rows = []
for k, (shown, mem) in enumerate(menu_frames(K1 + 1)):
    if k < K0:
        continue
    pal = palette(mem, 0xC3F8)
    idx = np.zeros((276, 416), np.uint8)
    idx[1:261, :412] = chunky(mem, shown + 160, 230, 260, 460)[:, 4:416]
    f = pal[idx]
    c = np.array(Image.open(f'mshots/m_{k + OFF:05d}.png').convert('RGB'))[::2, ::2]
    diff = (~(f == c).all(-1))
    diff[258:] = False
    ys = np.nonzero(diff.any(1))[0]
    y0 = int(ys.min()) if len(ys) else 0
    y0 = max(0, min(y0 - 2, 276 - 36))
    sep = np.full((36, 4, 3), 255, np.uint8)
    rows.append(np.concatenate([f[y0:y0 + 36], sep, c[y0:y0 + 36]], 1))
    print(k, 'diff rows', ys.min() if len(ys) else '-', ys.max() if len(ys) else '-',
          'diff cols', np.nonzero(diff.any(0))[0][[0, -1]] if diff.any() else '-')
Image.fromarray(np.concatenate(rows, 0)).resize((836 * 2, 36 * len(rows) * 2), 0).save('/dev/shm/nw_band.png')
