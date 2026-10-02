"""Render ST low-res planar bytes to PNG (any line stride), ST 3-bit palette.

    render.py FILE OFF STRIDE LINES PALOFF OUT.png [WIDTH_PX]
"""
import struct
import sys

from PIL import Image


def st_rgb(w):
    def c(n):
        n &= 0xF
        n = ((n & 7) << 1) | (n >> 3)  # STE nibble order; ST data has bit3=0
        return n * 17
    return (c(w >> 8), c(w >> 4), c(w))


def render(d, off, stride, lines, pal, width=None):
    width = width or (stride // 8) * 16
    img = Image.new('RGB', (width, lines))
    px = img.load()
    for y in range(lines):
        row = d[off + y * stride: off + (y + 1) * stride]
        for g in range(len(row) // 8):
            w = struct.unpack('>4H', row[g * 8:g * 8 + 8])
            for b in range(16):
                x = g * 16 + b
                if x >= width:
                    break
                ci = sum(((w[p] >> (15 - b)) & 1) << p for p in range(4))
                px[x, y] = pal[ci]
    return img


if __name__ == '__main__':
    d = open(sys.argv[1], 'rb').read()
    off, stride, lines, paloff = (int(a, 0) for a in sys.argv[2:6])
    pal = [st_rgb(v) for v in struct.unpack('>16H', d[paloff:paloff + 32])]
    w = int(sys.argv[7]) if len(sys.argv) > 7 else None
    img = render(d, off, stride, lines, pal, w)
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(sys.argv[6])
    print(sys.argv[6], img.size, [hex(v) for v in struct.unpack('>16H', d[paloff:paloff + 32])])
