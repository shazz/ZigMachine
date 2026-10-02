"""For each capture frame K+OFF, which model display frame (K-3..K+3) matches it
best, and how well?  seqmap.py OFF K0 K1"""
import os
import sys

import numpy as np
from PIL import Image

from menu_model import menu_frames
from stimg import chunky, palette

DIR = os.environ.get('CAPDIR', 'm2')
OFF, K0, K1 = (int(a) for a in sys.argv[1:4])
model = []
for shown, mem in menu_frames(K1 + 4):
    pal = palette(mem, 0xC3F8)
    idx = np.zeros((276, 416), np.uint8)
    idx[1:261, :412] = chunky(mem, shown + 160, 230, 260, 460)[:, 4:416]
    model.append(pal[idx][:258])
for k in range(K0, K1):
    c = np.array(Image.open(f'{DIR}/m_{k + OFF:05d}.png').convert('RGB'))[::2, ::2][:258]
    sc = [(int((~(c == model[j]).all(-1)).sum()), j - k) for j in range(max(0, k - 3), k + 4)]
    sc.sort()
    print(k, 'best', sc[0], 'next', sc[1])
