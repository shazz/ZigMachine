"""scenes.py FRAMEDIR [FROM]: which screen each Hatari frame (avi2png.py step 1) shows, as change points.

A frame is named by the Tiny picture it matches best (each picture's pixels over the ST screen,
colours ignored: two pixels are "the same" when both are colour 0 or both are not), or "black"
when the screen is all colour 0. Prints a line each time the name or the brightness changes.
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import tny  # noqa: E402

RE = '/home/matt/projects/ZigMachine/prototypes/dune_gen4_re/files/'
PICS = ('DUNE', 'MENU', 'SOUND', 'INTRO')


def masks():
    out = {}
    for p in PICS:
        _, scr = tny.decode(open(RE + p + '.TNY', 'rb').read())
        m = []
        for y in range(0, 200, 4):
            for x in range(0, 320, 4):
                w = (y * 160) + (x // 16) * 8
                bit = 15 - (x & 15)
                v = sum(((scr[w + 2 * k] << 8 | scr[w + 2 * k + 1]) >> bit & 1) for k in range(4))
                m.append(v != 0)
        out[p] = m
    return out


def frame(path):
    im = Image.open(path).convert('RGB')
    px = im.load()
    bg = px[4, 4]
    vals = [px[(x + 48) * 2, (y + 29) * 2] for y in range(0, 200, 4) for x in range(0, 320, 4)]
    lum = sum(sum(v) for v in vals) // len(vals)
    return [v != bg for v in vals], lum


def main():
    d = sys.argv[1]
    ms = masks()
    last = None
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    for f in sorted(os.listdir(d)):
        if int(f[1:6]) < start:
            continue
        m, lum = frame(os.path.join(d, f))
        if not any(m):
            name = 'black'
        else:
            name = max(PICS, key=lambda p: sum(a == b for a, b in zip(ms[p], m)))
        key = (name, lum // 8)
        if key != last:
            print(f[1:6], name, lum, flush=True)
            last = key


if __name__ == '__main__':
    main()
