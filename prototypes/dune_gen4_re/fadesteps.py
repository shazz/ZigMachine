"""fadesteps.py FRAMEDIR TNY FIRST LAST [PICROW0]: which step of DUNE.PRG's fade-in
($3CD2) each Hatari frame shows.

Samples the upper 100 lines of the screen, which show the picture from PICROW0
(the main part's logo copy: 10), against the shifted palette after s steps.
"""
import sys

from PIL import Image

import tny

src, path, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
row0 = int(sys.argv[5]) if len(sys.argv) > 5 else 10
pal, scr = tny.decode(open(path, 'rb').read())
rows = tny.to_rgb(pal, scr)


def shifted(s):
    work = []
    for t in pal:
        w = 0
        for sh in (8, 4, 0):
            w |= max(0, ((t >> sh) & 7) - 8 + s) << sh
        work.append(w)
    return work


for f in range(first, last + 1):
    px = Image.open(f'{src}/f{f:05d}.png').convert('RGB').load()
    obs = {}
    for y in range(0, 100, 3):
        for x in range(0, 320, 3):
            c = px[(x + 48) * 2, (y + 29) * 2]
            obs[(x, y)] = (c[0] // 34) << 8 | (c[1] // 34) << 4 | (c[2] // 34)
    cands = [('s%d' % s, shifted(s)) for s in range(9)] + [('true', pal)]
    score = [(sum(p[rows[y + row0][x]] != w for (x, y), w in obs.items()), n) for n, p in cands]
    print(f, min(score))
