"""Harness shot K (ppm) vs the ref frame: a 3-panel PNG (cart, ref, diff).
diff_ref.py SHOTDIR K OUT.png"""
import base64
import gzip
import json
import sys
import zlib

import numpy as np
from PIL import Image

d, k, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
ref = json.loads(gzip.decompress(open('../../apps/naos_nitrowave_ref.json.gz', 'rb').read()))
unz = lambda s: np.frombuffer(zlib.decompress(base64.b64decode(s)), np.uint8).reshape(280, 400)
base = unz(ref['base'])
want = base if k == ref['first'] else unz(ref['frames'][str(k)]) ^ base
pal = np.array([[((w >> s) & 7) * 255 // 7 for s in (8, 4, 0)] for w in ref['palette']], np.uint8)
got = np.array(Image.open(f'{d}/{k:05d}.ppm'))
diff = np.zeros_like(got)
bad = (got != pal[want]).any(-1)
diff[bad] = (255, 0, 0)
ys, xs = np.nonzero(bad)
print('bad', bad.sum(), 'rows', ys.min(), ys.max(), 'cols', xs.min(), xs.max())
Image.fromarray(np.concatenate([got, pal[want], diff], 1)).resize((2400, 560), 0).save(out)
