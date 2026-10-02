"""Build apps/naos_nitrowave_ref.json.gz: the ORIGINAL menu as Hatari shows it.

For a set of cart frames k (k-th render after init at one VBL a render), the
Hatari capture of VBL 1276 + k - 1 (m3/, frameskip 0; cmp_menu.py syncs the
menu's first main-loop VBL to capture 1276), mapped to the 400x280 plane:
physical (x, y) = capture (x + 8, y - 11), black outside the capture. Pixels
are stored as the ST colour word's index in the menu palette's first-occurrence
order ("canonical": $000 is both entry 0 and 8), so the harness compares
colours, not entry numbers.
"""
import base64
import gzip
import json
import zlib

import numpy as np
from PIL import Image

from stimg import st_rgb

FRAMES = [1, 2, 7, 50, 151, 180, 400, 714, 715, 716, 900, 1100]
SYNC = 1276
TD = open('menu_td.bin', 'rb').read()
words = [int.from_bytes(TD[0xC3F8 + 2 * i:0xC3FA + 2 * i], 'big') for i in range(16)]
canon = {}
for i, w in enumerate(words):
    canon.setdefault(st_rgb(w), i)


def plane(k):
    cap = np.array(Image.open(f'm3/m_{SYNC + k - 1:05d}.png').convert('RGB'))[::2, ::2]
    out = np.zeros((280, 400), np.uint8)
    for y in range(280):
        cy = y - 11
        if not 0 <= cy < cap.shape[0]:
            continue
        row = cap[cy, 8:408]
        out[y] = [canon[tuple(int(c) for c in px)] for px in row]
    return out


def z(a):
    return base64.b64encode(zlib.compress(a.tobytes(), 9)).decode()


# frames[k] is XORed with the first one: only the scroller band survives.
first = plane(FRAMES[0])
ref = {'palette': words, 'sync_capture': SYNC, 'first': FRAMES[0], 'base': z(first), 'frames': {}}
for k in FRAMES[1:]:
    ref['frames'][str(k)] = z(plane(k) ^ first)
data = gzip.compress(json.dumps(ref).encode(), 9)
open('../../apps/naos_nitrowave_ref.json.gz', 'wb').write(data)
print('frames', FRAMES, 'bytes', len(data))
