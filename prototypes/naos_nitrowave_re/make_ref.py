"""Build apps/naos_nitrowave_ref.json.gz: the ORIGINAL as Hatari shows it.

Per part, for a set of cart frames k (k-th VBL after the part is entered), the
Hatari capture (frameskip 0) of VBL sync + k - 1, where `sync` is the capture
showing the part model's first frame (cmp_menu.py / cmp_part.py / dam_fit.py),
mapped to the 400x280 plane: physical (x, y) = capture (x + 8, y - 11), black
outside the capture. Pixels are ST colour words (u16 big-endian), so the
harness compares colours, not palette entries (F3 changes them along each
line). Frames after the first are XORed with it: only what moves survives
the packing.
"""
import base64
import gzip
import json
import zlib

import numpy as np
from PIL import Image

PARTS = {
    # part: (capture dir, sync capture, frames)
    'menu': ('m3', 1276, [1, 2, 7, 50, 151, 180, 400, 714, 715, 716, 900, 1100]),
    'bspr': ('p2', 2258, [1, 2, 3, 60, 201, 600, 1000, 1300, 1700]),
    'dam': ('p3', 2836, [1, 2, 3, 4, 5, 50, 101, 250, 400, 560]),
}


def plane(capdir, n):
    """The capture as ST colour words (Hatari shows STE levels: 17 x nibble,
    the nibble (c & 7) << 1 | c >> 3; ST colours have c >> 3 == 0)."""
    name = f'{capdir}/{"m" if capdir == "m3" else "f"}_{n:05d}.png'
    cap = np.array(Image.open(name).convert('RGB'))[::2, ::2]
    out = np.zeros((280, 400), '>u2')
    for y in range(11, min(280, 11 + cap.shape[0])):
        c3 = (cap[y - 11, 8:408].astype(np.uint16) // 17 >> 1) & 7
        out[y] = (c3[:, 0] << 8) | (c3[:, 1] << 4) | c3[:, 2]
    return out


def z(a):
    return base64.b64encode(zlib.compress(a.tobytes(), 9)).decode()


ref = {}
for part, (capdir, sync, frames) in PARTS.items():
    first = plane(capdir, sync + frames[0] - 1)
    ref[part] = {'sync_capture': sync, 'first': frames[0], 'base': z(first),
                 'frames': {str(k): z((plane(capdir, sync + k - 1) ^ first).astype('>u2')) for k in frames[1:]}}
data = gzip.compress(json.dumps(ref).encode(), 9)
open('../../apps/naos_nitrowave_ref.json.gz', 'wb').write(data)
print({p: v[2] for p, v in PARTS.items()}, 'bytes', len(data))
