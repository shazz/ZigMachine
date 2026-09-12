#!/usr/bin/env python3
"""Assets for THE REPLICANTS "Garfield" crack intro (CODEF screen 28).

    python3 tools/replicants_garfield_assets.py

Source PNGs sit next to the outputs in apps/zig/assets/screens/replicants_garfield/,
copied from prototypes/codef/28/assets/ (tools/fetch_codef.py 28).

Every image is authored at 640x400 = ST 320x200 doubled, so it is halved by
taking the EVEN source pixel of each 2x2 cell (not PIL's NEAREST, which picks
the odd one). A handful of hand-edited pixels in background.png, fontsMask3.png
and logo.png break the doubling; the even pixel wins there.

Outputs:
    frame.raw     320x200  background.png with backgroundMask.png composited at
                           y=294, as the original stacks them; index 0 = transparent
    frame_pal.dat          its palette
    logo.raw      268x163  1 = ink, 0 = transparent (logo.png, one colour)
    font.raw      160x96   1 = ink, 0 = transparent (fonts2.png, 10x6 glyphs of 16x16)
    fontmask.raw  288x34   indices 2.. into text_pal.dat (fontsMask3.png)
    text_pal.dat           0 transparent, 1 logo ink (re-set per line), 2.. mask colours
    rows.dat      256 RGBA entries, one per 640-space ROW (not halved: the scene
                           samples them at sub-pixel offsets):
                           0..87   rasterBlue, rasterPink, rasterYellow, rasterGray (22 rows each)
                           88..147 rasterFont4 (60 rows) — the logo's gradient
"""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

DST = Path("apps/zig/assets/screens/replicants_garfield")
TRANSPARENT = (0, 0, 0, 0)
BARS = ("rasterBlue", "rasterPink", "rasterYellow", "rasterGray")


def write_pal(name: str, palette: list[tuple[int, int, int, int]]) -> None:
    if len(palette) > 256:
        raise SystemExit(f"{name}: {len(palette)} entries, more than 256")
    flat: list[int] = []
    for c in palette:
        flat += list(c)
    flat += [0] * ((256 - len(palette)) * 4)
    (DST / name).write_bytes(struct.pack("1024B", *flat))
    print(f"  {name}: {len(palette)} entries")


def write_raw(name: str, indices: list[int], w: int, h: int) -> None:
    if len(indices) != w * h:
        raise SystemExit(f"{name}: {len(indices)} indices for {w}x{h}")
    (DST / name).write_bytes(bytes(indices))
    print(f"  {name}: {w}x{h}")


def halve(im: Image.Image) -> Image.Image:
    """Keep the even pixel of every 2x2 cell."""
    src = im.convert("RGBA")
    w, h = src.width // 2, src.height // 2
    out = Image.new("RGBA", (w, h))
    sp, op = src.load(), out.load()
    for y in range(h):
        for x in range(w):
            op[x, y] = sp[2 * x, 2 * y]
    return out


def index_colours(im: Image.Image, first: int, palette: list) -> list[int]:
    """Alpha-0 -> 0; each distinct opaque colour gets the next index from `first`."""
    lookup = {c: i for i, c in enumerate(palette) if i >= first}
    px = im.load()
    out: list[int] = []
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                out.append(0)
                continue
            key = (r, g, b, 255)
            if key not in lookup:
                lookup[key] = len(palette)
                palette.append(key)
            out.append(lookup[key])
    return out


def ink_mask(im: Image.Image) -> list[int]:
    px = im.load()
    return [1 if px[x, y][3] else 0 for y in range(im.height) for x in range(im.width)]


def frame() -> None:
    """The original draws background.png, then (later, over the scroller)
    backgroundMask.png at y=294. The scroller only lands in the mask's hole, so
    baking both into one static plane is exact once the scene clips glyphs to it."""
    bg = Image.open(DST / "background.png").convert("RGBA")
    bg.alpha_composite(Image.open(DST / "backgroundMask.png").convert("RGBA"), (0, 294))
    palette: list = [TRANSPARENT]
    write_raw("frame.raw", index_colours(halve(bg), 1, palette), 320, 200)
    write_pal("frame_pal.dat", palette)


def text_layer() -> None:
    logo = halve(Image.open(DST / "logo.png"))
    if logo.size != (268, 163):
        raise SystemExit(f"logo halves to {logo.size}")
    if len(logo.convert("RGBA").getcolors()) != 2:
        raise SystemExit("logo.png is expected to carry one ink colour")
    write_raw("logo.raw", ink_mask(logo), 268, 163)

    font = halve(Image.open(DST / "fonts2.png"))
    write_raw("font.raw", ink_mask(font), 160, 96)

    palette: list = [TRANSPARENT, (224, 96, 64, 255)]  # 1: logo.png's own ink colour
    mask = halve(Image.open(DST / "fontsMask3.png"))
    write_raw("fontmask.raw", index_colours(mask, 2, palette), 288, 34)
    write_pal("text_pal.dat", palette)


def rows() -> None:
    """Every raster PNG is uniform along each row (checked here), so a colour per
    row is the whole image."""
    entries: list = []
    for name in (*BARS, "rasterFont4"):
        im = Image.open(DST / f"{name}.png").convert("RGBA")
        px = im.load()
        for y in range(im.height):
            if len({px[x, y] for x in range(im.width)}) != 1:
                raise SystemExit(f"{name}.png row {y} is not a single colour")
            entries.append(px[0, y])
    if len(entries) != 4 * 22 + 60:
        raise SystemExit(f"rows.dat: {len(entries)} rows, expected 148")
    write_pal("rows.dat", entries)


if __name__ == "__main__":
    if not DST.is_dir():
        raise SystemExit(f"missing {DST}")
    print(f"REPLICANTS GARFIELD (CODEF 28) assets -> {DST}")
    frame()
    text_layer()
    rows()
