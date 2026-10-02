"""dam_view.py FRAME CAPTURE K OUT.png [FIRST_ROW]: model frame vs capture, 3
panels (model, capture, diff), 2x."""
import sys

import numpy as np
from PIL import Image

import dam_main as D
import dam_show as S
from dam_model import Part

F, C, K = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
first = int(sys.argv[5]) if len(sys.argv) > 5 else 1
p = Part()
for _ in range(F + 1):
    shown = D.frame(p)
im = S.image(p.m, shown, K, first_row=first)
cap = np.array(Image.open(f'p3/f_{C:05d}.png').convert('RGB'))[::2, ::2]
bad = ~(im == cap).all(-1)
d = np.zeros_like(im)
d[bad] = (255, 0, 0)
ys = sorted(set(np.nonzero(bad)[0].tolist()))
print('rows differing', len(ys), ys[:30])
Image.fromarray(np.concatenate([im, cap, d], 1)).resize((2496, 552), 0).save(sys.argv[4])
