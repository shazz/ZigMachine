"""Build apps/naos_nitrowave_ref.json.gz: the ORIGINAL as Hatari shows it.

Per part, for a set of cart frames k (k-th VBL after the part is entered), the
Hatari capture (frameskip 0) of VBL sync + k - 1, where `sync` is the capture
showing the part model's first frame (cmp_menu.py / cmp_part.py), mapped to
the 400x280 plane: physical (x, y) = capture (x + 8, y - 11), black outside
the capture. Pixels are the ST colour word's index in the part palette's
first-occurrence order ("canonical": $000 can be several entries), so the
harness compares colours, not entry numbers. Frames after the first are XORed
with it: only what moves survives the packing.
"""
import base64
import gzip
import json
import zlib

import numpy as np
from PIL import Image

from stimg import st_rgb

PARTS = {
    # part: (capture dir, sync capture, RAM image, palette address, frames)
    'menu': ('m3', 1276, 'menu_td.bin', 0xC3F8, [1, 2, 7, 50, 151, 180, 400, 714, 715, 716, 900, 1100]),
    'bspr': ('p2', 2258, 'bspr_ram.bin', 0x10796, [1, 2, 3, 60, 201, 600, 1000, 1300, 1700]),
}


def plane(capdir, n, canon):
    cap = np.array(Image.open(f'{capdir}/{"m" if capdir == "m3" else "f"}_{n:05d}.png').convert('RGB'))[::2, ::2]
    out = np.zeros((280, 400), np.uint8)
    for y in range(11, min(280, 11 + cap.shape[0])):
        out[y] = [canon[tuple(int(c) for c in px)] for px in cap[y - 11, 8:408]]
    return out


def z(a):
    return base64.b64encode(zlib.compress(a.tobytes(), 9)).decode()


ref = {}
for part, (capdir, sync, image, paladdr, frames) in PARTS.items():
    mem = open(image, 'rb').read()
    words = [int.from_bytes(mem[paladdr + 2 * i:paladdr + 2 * i + 2], 'big') for i in range(16)]
    canon = {}
    for i, w in enumerate(words):
        canon.setdefault(st_rgb(w), i)
    first = plane(capdir, sync + frames[0] - 1, canon)
    ref[part] = {'palette': words, 'sync_capture': sync, 'first': frames[0], 'base': z(first),
                 'frames': {str(k): z(plane(capdir, sync + k - 1, canon) ^ first) for k in frames[1:]}}
data = gzip.compress(json.dumps(ref).encode(), 9)
open('../../apps/naos_nitrowave_ref.json.gz', 'wb').write(data)
print({p: v[4] for p, v in PARTS.items()}, 'bytes', len(data))
