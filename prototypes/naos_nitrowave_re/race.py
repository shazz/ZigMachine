"""Beam-race test: does capture K+OFF show, row by row, the DRAWN buffer of VBL K
either before ('b') or after ('a') the VBL program ran, or the shown one ('s')?
race.py OFF K0 K1"""
import sys

import numpy as np
from PIL import Image

from menu_model import Menu
from stimg import chunky, palette

DIR = __import__('os').environ.get('CAPDIR', 'mshots')

OFF, K0, K1 = (int(a) for a in sys.argv[1:4])
mm = Menu()
pal = palette(mm.m, 0xC3F8)


def rgb(addr):
    idx = np.zeros((276, 416), np.uint8)
    idx[1:261, :412] = chunky(mm.m, addr + 160, 230, 260, 460)[:, 4:416]
    return pal[idx]


for k in range(K1 + 1):
    draw = mm.rl(0x3D8D6)
    shown = mm.shown
    before = rgb(draw) if k >= K0 else None
    shown_img = rgb(shown) if k >= K0 else None
    mm.cpu.run(mm.prog)
    if k >= K0:
        after = rgb(draw)
        c = np.array(Image.open(f'{DIR}/m_{k + OFF:05d}.png').convert('RGB'))[::2, ::2]
        s = ''
        for y in range(1, 258):
            ok = [(c[y] == im[y]).all() for im in (shown_img, before, after)]
            s += 's' if ok[0] and not (ok[1] or ok[2]) else ('*' if all(ok) else ('a' if ok[2] and not ok[1] else ('b' if ok[1] else ('?' if not any(ok) else '+'))))
        print(k, draw == shown, s)
    mm.f6c4()
    mm.f630()
    mm.f76c()
