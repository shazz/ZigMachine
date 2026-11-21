#!/usr/bin/env python3
"""Render the ST game's files as PNGs for the analysis: the Degas pictures, BBLOCKS, sprite banks.

    python3 prototypes/bubble_re/tools/view.py <outdir>
"""
import os
import struct
import sys

from PIL import Image

RE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(RE, 'files', 'GRAPHICS')


def st_rgb(w):
    return tuple(((w >> s) & 7) * 255 // 7 for s in (8, 4, 0))


def planar(data, width, height, pal):
    im = Image.new('RGB', (width, height))
    px = im.load()
    stride = width // 2
    for y in range(height):
        for x in range(width):
            g = y * stride + (x // 16) * 8
            if g + 8 > len(data):
                continue
            b = 15 - (x % 16)
            c = 0
            for p in range(4):
                w = struct.unpack('>H', data[g + 2 * p:g + 2 * p + 2])[0]
                c |= ((w >> b) & 1) << p
            px[x, y] = st_rgb(pal[c])
    return im


def degas(name):
    d = open(os.path.join(G, name), 'rb').read()
    pal = struct.unpack('>16H', d[2:34])
    return d[34:], pal


def main(out):
    os.makedirs(out, exist_ok=True)
    for n in ('SPIC.PI1', 'SECRET.PI1', 'EXTEND.PI1', 'BBLOCKS.PI1'):
        body, pal = degas(n)
        h = min(200, len(body) // 160)
        planar(body, 320, h, pal).resize((640, 2 * h)).save(os.path.join(out, n.lower() + '.png'))
    _, pal = degas('BBLOCKS.PI1')
    for n in ('BUBBLE.SPR', 'DWARF.SPR', 'FRUIT.SPR', 'UNSHIFT.SPR'):
        d = open(os.path.join(G, n), 'rb').read()
        h = len(d) // 160
        planar(d, 320, h, pal).save(os.path.join(out, n.lower() + '.png'))


if __name__ == '__main__':
    main(sys.argv[1])


def strip(name, width, out, cols=32):
    """A sprite bank as a column of `width`-pixel rows, cut into `cols` columns of 64 rows."""
    _, pal = degas('BBLOCKS.PI1')
    d = open(os.path.join(G, name), 'rb').read()
    rb = width // 2
    h = len(d) // rb
    im = planar(d, width, h, pal)
    rows = 64
    n = (h + rows - 1) // rows
    sheet = Image.new('RGB', ((width + 2) * cols, rows * ((n + cols - 1) // cols)))
    for i in range(n):
        sheet.paste(im.crop((0, i * rows, width, i * rows + rows)), ((i % cols) * (width + 2), (i // cols) * rows))
    sheet.resize((sheet.width * 2, sheet.height * 2)).save(os.path.join(out, name.lower() + '.w%d.png' % width))
