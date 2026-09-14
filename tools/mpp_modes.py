"""The three MPP modes tools/mpp_convert.py builds from one 320x180 truecolor picture.

  1 GLOBAL     one 256-colour palette for the whole image, 1 plane (the baseline)
  2 PER-LINE   1 plane, a best 256-colour palette for every line
  3 4-PLANE    every pixel opaque in exactly ONE of the 4 planes; each plane gets its
               own per-line palette of 255 colours + transparent index 0, so a line
               can hold up to 4*255 = 1020 colours

A line is only 320 pixels wide, so it never has more than 320 distinct colours: mode 3
holds every line exactly (the per-line clustering to 1020 is the identity), and mode 2
merges only the lines that carry more than 256. A line's colours are sorted by
luminance (both per-line modes) and mode 3 cuts them into 4 contiguous runs, one per plane.
"""
import struct
import sys

from PIL import Image

from mpp_picture import IMAGE_H

W, H = 320, 200
CAPTION_H = H - IMAGE_H
PLANES = 4
# Alpha is not stored (every entry is opaque), so the band's entry 0 is black ON the
# scene's black background rather than transparent.
CAPTION_PAL = [(0, 0, 0), (255, 255, 255)]
METHODS = {"mediancut": Image.Quantize.MEDIANCUT, "libimagequant": Image.Quantize.LIBIMAGEQUANT}


def rows(img):
    data = list(img.getdata())
    return [data[y * W:(y + 1) * W] for y in range(IMAGE_H)]


def quantize(pixels, n, method, width, height):
    """Quantize a list of RGB pixels to <= n colours; returns (palette RGB list, indices)."""
    distinct = sorted(set(pixels))
    if len(distinct) <= n:  # exact: no clustering needed
        where = {c: i for i, c in enumerate(distinct)}
        return distinct, [where[p] for p in pixels]
    img = Image.new("RGB", (width, height))
    img.putdata(pixels)
    q = img.quantize(n, method=METHODS[method], dither=Image.Dither.NONE)
    # getpalette() may hold fewer than n entries; padding to n wrote 1-byte "entries".
    flat = q.getpalette()[: n * 3]
    pal = [tuple(flat[i * 3:i * 3 + 3]) for i in range(len(flat) // 3)]
    return pal, list(q.getdata())


def luma(c):
    return 299 * c[0] + 587 * c[1] + 114 * c[2]


def by_luma(pal, idx):
    """The same palette sorted by luminance, and the indices remapped to it."""
    order = sorted(range(len(pal)), key=lambda i: (luma(pal[i]), pal[i]))
    where = {old: new for new, old in enumerate(order)}
    return [pal[i] for i in order], [where[i] for i in idx]


class Mode:
    """Accumulates one mode's palette (RGB), line map and the colours it shows."""

    def __init__(self):
        self.pal = bytearray()
        self.map = [[(0, 0, 0)] * H for _ in range(PLANES)]
        self.cache = {}
        self.shown = set()

    def add(self, colours, first):
        key = (first, tuple(colours))
        if key not in self.cache:  # identical palettes share one copy (mode 1)
            self.cache[key] = len(self.pal) // 3
            for c in colours:
                self.pal += bytes(c[:3])
        return (self.cache[key] * 4, first, len(colours))  # the scene's offsets are RGBA

    def caption(self):
        for y in range(IMAGE_H, H):
            self.map[0][y] = self.add(CAPTION_PAL, 0)

    def blob(self, idx):
        """map + idx + the palette as RGB, each byte minus the byte 3 before it."""
        maps = b"".join(struct.pack("<IHH", *self.map[p][y]) for p in range(PLANES) for y in range(H))
        pal = bytearray(self.pal)
        for i in range(len(pal) - 1, 2, -1):
            pal[i] = (pal[i] - pal[i - 3]) & 255
        return maps + idx + bytes(pal)


def mode_global(img, method):
    """Also returns the palette and indices, for the banding measurement."""
    m = Mode()
    pal, idx = quantize(list(img.getdata()), 256, method, W, IMAGE_H)
    for y in range(IMAGE_H):
        m.map[0][y] = m.add(pal, 0)
    m.caption()
    m.shown = {pal[i] for i in idx}
    return m, bytes(idx) + bytes(W * CAPTION_H), pal, idx


def mode_per_line(img, method):
    m = Mode()
    out = bytearray()
    for y, row in enumerate(rows(img)):
        pal, idx = by_luma(*quantize(row, 256, method, W, 1))
        m.map[0][y] = m.add(pal, 0)
        out += bytes(idx)
        m.shown |= {pal[i] for i in idx}
    m.caption()
    return m, bytes(out) + bytes(W * CAPTION_H)


def mode_four_planes(img):
    """idx: the 320x200 index bytes, then the 320x200 plane bytes."""
    m = Mode()
    low, high = bytearray(), bytearray()
    for y, row in enumerate(rows(img)):
        colours = sorted(set(row), key=lambda c: (luma(c), c))
        if len(colours) > PLANES * 255:
            sys.exit(f"mpp_convert: line {y} has {len(colours)} colours > {PLANES * 255}")
        per = -(-len(colours) // PLANES)
        where = {}
        for p in range(PLANES):
            run = colours[p * per:(p + 1) * per]
            m.map[p][y] = m.add(run, 1)
            for i, c in enumerate(run):
                where[c] = (p, i + 1)
        low += bytes(where[c][1] for c in row)
        high += bytes(where[c][0] for c in row)
        m.shown |= set(row)
    m.caption()
    pad = bytes(W * CAPTION_H)
    return m, bytes(low) + pad + bytes(high) + pad
