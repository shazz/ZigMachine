"""mkref_add.py REF.bin.br FRAMEDIR:OFFSET:PART LABEL:VBL ...: append Hatari frames to an existing
reference (mkref.py's format) without the earlier runs' frame dumps. Groups, labels and the
window are as mkref.py's; a label already in the file is replaced (same place, new pixels).
"""
import json
import struct
import sys

import brotli
from PIL import Image

X0, X1, Y0, Y1 = -40, 360, -29, 240  # mkref.py's window
HX, HY = 48, 29


def words(path):
    """mkref.py's: each pixel of the window as an ST colour word (Hatari scales a gun v to 34v)."""
    im = Image.open(path).convert('RGB')
    px = im.load()
    return [(r // 34) << 8 | (g // 34) << 4 | (b // 34)
            for y in range(Y0, Y1) for x in range(X0, X1)
            for r, g, b in [px[(x + HX) * 2, (y + HY) * 2]]]


def load(path):
    raw = brotli.decompress(open(path, 'rb').read())
    n = struct.unpack('<I', raw[:4])[0]
    head = json.loads(raw[4:4 + n])
    size = head['w'] * head['h']
    prev = [0] * size
    out = []
    for i in range(len(head['frames'])):
        at = 4 + n + i * size * 2
        cur = [x ^ y for x, y in zip(struct.unpack(f'<{size}H', raw[at:at + size * 2]), prev)]
        out.append(cur)
        prev = cur
    return head, out


def save(path, head, blobs):
    prev = [0] * len(blobs[0])
    packed = []
    for b in blobs:
        packed.append(struct.pack(f'<{len(b)}H', *[x ^ y for x, y in zip(b, prev)]))
        prev = b
    h = json.dumps(head).encode()
    with open(path, 'wb') as f:
        f.write(brotli.compress(struct.pack('<I', len(h)) + h + b''.join(packed), quality=11))


def main():
    dst = sys.argv[1]
    head, blobs = load(dst)
    src, off, part = None, 0, None
    for arg in sys.argv[2:]:
        a = arg.split(':')
        if len(a) == 3:
            src, off, part = a[0], int(a[1]), a[2]
            continue
        label, v = a[0], int(a[1])
        f = {'label': label, 'part': part, 'hatari_vbl': v, 'vbl': v - off}
        px = words(f'{src}/f{v:05d}.png')
        old = [i for i, g in enumerate(head['frames']) if g['label'] == label]
        if old:
            head['frames'][old[0]], blobs[old[0]] = f, px
        else:
            head['frames'].append(f)
            blobs.append(px)
    save(dst, head, blobs)
    print(len(head['frames']), 'frames ->', dst)


if __name__ == '__main__':
    main()
