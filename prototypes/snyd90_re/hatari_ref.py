"""hatari_ref.py NAME ROWS [--keep C,C..] FRAME.png...: a part's colour reference for apps/snyd_90_parts.mjs.

The best-effort parts (F3..F6) are not byte-identical to the original, so the harness
compares what they SHOW with Hatari's capture of the real demo by colour: the share of
each ST colour word over the 320-pixel-wide window column, ST lines 0..ROWS-1 (past 199:
the opened bottom border), averaged over the given frames of run_hatari.sh's AVI
(avi2png.py). Hatari's frame is 416x276 doubled, the window at (48, 29); its channels
are v * 34 (v = 0..7). Prints the JS entry: {colour word (hex): share}, shares >= 0.2 %.
--keep lists the colour words to keep apart; every other colour counts as 0x1000 ("other"):
for a part whose colours cycle (F5's texture), only its fixed colours are compared.
"""
import sys
from collections import Counter

from PIL import Image

X0, Y0 = 48, 29


def st_word(rgb: tuple[int, int, int]) -> int:
    r, g, b = (min(7, round(v / 34)) for v in rgb)
    return r << 8 | g << 4 | b


def histogram(path: str, rows: int, keep: set[int] | None) -> Counter:
    im = Image.open(path).convert('RGB')
    im = im.resize((im.width // 2, im.height // 2), Image.NEAREST)
    h: Counter = Counter()
    for y in range(Y0, min(im.height, Y0 + rows)):
        for x in range(X0, X0 + 320):
            c = st_word(im.getpixel((x, y)))
            h[c if keep is None or c in keep else 0x1000] += 1
    return h


def main() -> None:
    name, rows, frames = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
    keep = None
    if frames[0] == '--keep':
        keep = {int(c, 16) for c in frames[1].split(',')}
        frames = frames[2:]
    total: Counter = Counter()
    for f in frames:
        total.update(histogram(f, rows, keep))
    n = sum(total.values())
    shares = {c: k / n for c, k in total.most_common() if k / n >= 0.002}
    body = ', '.join(f'0x{c:03x}: {s:.4f}' for c, s in shares.items())
    lump = '' if keep is None else ', lump: true'
    print(f'    {name}: {{ rows: {rows}{lump}, colours: {{ {body} }} }},')


if __name__ == '__main__':
    main()
