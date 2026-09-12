#!/usr/bin/env python3
"""Convert the CODEF screen-525 (SUPPLEX / Flight Simulator II) assets.

The CODEF remake is authored at Amiga PAL overscan DOUBLED (720x568), so every
source image is halved back to Amiga pixels (360x284) and the screen is placed
in the 400x280 overscan plane at x=20 (bottom 4 Amiga lines cropped - they are
black; the lowest content is the red rule at y=273).

Doubling grids were measured, not assumed: main.png pairs rows (1,2),(3,4)...
so it samples at (2x, 2y+1); font.png pairs (0,1) so it samples at (2x, 2y).

Outputs (apps/zig/assets/screens/supplex_fs2/):
  main.raw / main_pal.dat - 400x280 background plane, index 0 = black
  font.raw                - 320x48 glyph MASK, 1 = ink, 0 = field
  raster.dat              - 731 x RGB, the vertical raster gradient, halved
"""
from pathlib import Path
from PIL import Image

SRC = Path(__file__).resolve().parent.parent / "prototypes/codef/525/assets"
DST = Path(__file__).resolve().parent.parent / "apps/zig/assets/screens/supplex_fs2"

PW, PH = 400, 280  # ZigMachine overscan plane
AMIGA_W, AMIGA_H = 360, 283  # the CODEF canvas, halved (row 0 of the PNG is a half-row)
X_OFF = 20  # centre the 360-wide Amiga screen in the 400-wide plane


def halve(path: Path, ox: int, oy: int) -> tuple[list[list[tuple]], int, int]:
    """Undo CODEF's 2x pixel doubling, sampling on the measured grid."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    hw, hh = (w - ox) // 2, (h - oy) // 2
    rows = [[px[2 * x + ox, 2 * y + oy] for x in range(hw)] for y in range(hh)]
    return rows, hw, hh


def write_palette(colors: list[tuple], out: Path) -> None:
    data = bytearray(256 * 4)
    for i, c in enumerate(colors):
        data[i * 4: i * 4 + 4] = bytes(c)
    out.write_bytes(bytes(data))


def convert_main() -> None:
    rows, w, h = halve(SRC / "main.png", 0, 1)
    assert (w, h) == (AMIGA_W, AMIGA_H), (w, h)
    black = (0, 0, 0, 255)
    colors = [black]
    index = {black: 0}
    raw = bytearray(PW * PH)  # zero = black everywhere, incl. the 20px margins
    for y in range(min(h, PH)):
        for x in range(w):
            c = rows[y][x]
            if c[3] == 0:
                c = black
            if c not in index:
                index[c] = len(colors)
                colors.append(c)
            raw[y * PW + X_OFF + x] = index[c]
    (DST / "main.raw").write_bytes(bytes(raw))
    write_palette(colors, DST / "main_pal.dat")
    print(f"main.raw {PW}x{PH}, {len(colors)} colours")


def convert_font() -> None:
    """font.png ink is the OPAQUE BLACK; the field is white with alpha 0."""
    rows, w, h = halve(SRC / "font.png", 0, 0)
    assert (w, h) == (320, 48), (w, h)
    raw = bytearray(w * h)
    ink = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = rows[y][x]
            if a != 0 and (r, g, b) == (0, 0, 0):
                raw[y * w + x] = 1
                ink += 1
    (DST / "font.raw").write_bytes(bytes(raw))
    print(f"font.raw {w}x{h}, {ink} ink pixels")


def convert_raster() -> None:
    """raster.png is horizontally uniform: keep one column, halved."""
    im = Image.open(SRC / "raster.png").convert("RGBA")
    px = im.load()
    h = im.size[1]
    out = bytearray()
    for y in range(h // 2):
        out += bytes(px[0, 2 * y][:3])
    (DST / "raster.dat").write_bytes(bytes(out))
    print(f"raster.dat {h // 2} entries")


if __name__ == "__main__":
    DST.mkdir(parents=True, exist_ok=True)
    convert_main()
    convert_font()
    convert_raster()
