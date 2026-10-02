"""mkref.py OUT.bin.br FRAMEDIR:OFFSET:PART LABEL:VBL ... [FRAMEDIR:OFFSET:PART LABEL:VBL ...]

Reference frames from Hatari, from one or more recordings. Each FRAMEDIR holds a
Hatari AVI recorded with --frameskips 0 (one frame a VBL), dumped by avi2png.py
with step 1: f<VBL>.png. A FRAMEDIR:OFFSET:PART argument starts a group: the
frames after it come from FRAMEDIR, and the cart's frame for Hatari VBL v is
VBL v - OFFSET of PART (the headless test steps the cart into each part with
its keys). Each frame becomes the ST colour word of every pixel of the window
the cart's plane can show and Hatari captures too: ST x -40..359 (Hatari's left
border is 48 wide), ST y -29..239 (its top border is 29). Hatari scales a 3-bit
gun v to (2v) * 17, so v = c // 34.
"""
import brotli
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
    return out


dst = sys.argv[1]
frames, blobs = [], []
src, off, part = None, 0, None
for arg in sys.argv[2:]:
    a = arg.split(':')
    if len(a) == 3:
        src, off, part = a[0], int(a[1]), a[2]
        continue
    label, v = a[0], int(a[1])
    frames.append({'label': label, 'part': part, 'hatari_vbl': v, 'vbl': v - off})
    blobs.append(words(f'{src}/f{v:05d}.png'))
# each frame stored XORed with the one before it (most of a frame is its
# neighbour's), as u16 LE
prev = [0] * len(blobs[0])
packed = []
for b in blobs:
    packed.append(struct.pack(f'<{len(b)}H', *[x ^ y for x, y in zip(b, prev)]))
    prev = b
blobs = packed
head = json.dumps({'x0': X0, 'y0': Y0, 'w': X1 - X0, 'h': Y1 - Y0, 'xor': True, 'frames': frames}).encode()
# a u32 header length, the JSON, then each frame's words, in order
with open(dst, "wb") as f:
    f.write(brotli.compress(struct.pack('<I', len(head)) + head + b''.join(blobs), quality=11))
print(len(frames), 'frames ->', dst)
