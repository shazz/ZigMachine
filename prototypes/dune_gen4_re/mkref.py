"""mkref.py FRAMEDIR OUT.json.gz OFFSET LABEL:VBL ...: reference frames from Hatari.

FRAMEDIR holds a Hatari AVI recorded with --frameskips 0 (one frame a VBL),
dumped by avi2png.py with step 1: f<VBL>.png. Each frame becomes the ST colour
word of every pixel of the window the cart's plane can show and Hatari captures
too: ST x -40..359 (Hatari's left border is 48 wide), ST y -29..239 (its top
border is 29). Hatari scales a 3-bit gun v to (2v) * 17, so v = c // 34.
OFFSET: the cart's VBL for Hatari VBL v is v - OFFSET.
"""
import gzip
import json
import struct
import sys

from PIL import Image

X0, X1, Y0, Y1 = -40, 360, -29, 240
HX, HY = 48, 29


def words(path):
    im = Image.open(path).convert('RGB')
    px = im.load()
    out = []
    for y in range(Y0, Y1):
        for x in range(X0, X1):
            r, g, b = px[(x + HX) * 2, (y + HY) * 2]
            out.append((r // 34) << 8 | (g // 34) << 4 | (b // 34))
    return struct.pack(f'<{len(out)}H', *out)


src, dst, off = sys.argv[1], sys.argv[2], int(sys.argv[3])
frames, blobs = [], []
for arg in sys.argv[4:]:
    label, v = arg.split(':')
    v = int(v)
    frames.append({'label': label, 'hatari_vbl': v, 'vbl': v - off})
    blobs.append(words(f'{src}/f{v:05d}.png'))
head = json.dumps({'x0': X0, 'y0': Y0, 'w': X1 - X0, 'h': Y1 - Y0, 'frames': frames}).encode()
# a u32 header length, the JSON, then each frame's words (u16 LE), in order
with gzip.open(dst, 'wb') as f:
    f.write(struct.pack('<I', len(head)) + head + b''.join(blobs))
print(len(frames), 'frames ->', dst)
