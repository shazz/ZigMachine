"""The intro's Spectrum 512 picture: 32000 B screen at $5724 + 199 x 48-word line palettes at $D424.

spu_index(x, c) is the standard Spectrum 512 mapping from (pixel x, colour register c) to the palette
slot live when the beam paints x. Line 0 has no palette (black); line y uses palette y-1.
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))


def load() -> tuple[bytes, list[list[int]]]:
    d = open(os.path.join(HERE, 'parts', 'p8_001000.bin'), 'rb').read()
    scr = d[0x4724:0x4724 + 32000]
    raw = d[0xC424:0xC424 + 199 * 96]
    pals = [list(struct.unpack('>48H', raw[i * 96:i * 96 + 96])) for i in range(199)]
    return scr, pals


def pixel(scr: bytes, x: int, y: int) -> int:
    o = y * 160 + (x >> 4) * 8
    b = 15 - (x & 15)
    return sum(((struct.unpack('>H', scr[o + 2 * p:o + 2 * p + 2])[0] >> b) & 1) << p for p in range(4))


def spu_index(x: int, c: int) -> int:
    x1 = 10 * c + (-5 if c & 1 else 1)
    if x1 <= x < x1 + 160:
        return c + 16
    return c + 32 if x >= x1 + 160 else c


def st_rgb(w: int) -> tuple[int, int, int]:
    return tuple(((w >> s) & 7) * 36 for s in (8, 4, 0))


def render() -> list[list[tuple[int, int, int]]]:
    scr, pals = load()
    img = [[(0, 0, 0)] * 320 for _ in range(200)]
    for y in range(1, 200):
        for x in range(320):
            c = pixel(scr, x, y)
            img[y][x] = st_rgb(pals[y - 1][spu_index(x, c)])
    return img


if __name__ == '__main__':
    from PIL import Image
    im = Image.new('RGB', (320, 200))
    im.putdata([p for row in render() for p in row])
    im.save(os.path.join(HERE, 'intro_spu.png'))
