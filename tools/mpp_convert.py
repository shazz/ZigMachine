#!/usr/bin/env python3
"""Convert a truecolor picture into ZigMachine MPP-style assets (apps/zig/scenes/mpp_truecolor.zig).

MPP (Multi Palette Picture, https://codeberg.org/zerkman/mpp) shows more colours than
the hardware palette holds by reloading the palette between scanlines. ZigMachine's
per-plane HBL handler runs once before each line is composited, so a plane can take a
whole new 256-entry palette per line. Three modes, one image:

  1 GLOBAL     one 256-colour palette for the whole image, 1 plane (the baseline)
  2 PER-LINE   1 plane, a best 256-colour palette for every line
  3 4-PLANE    every pixel opaque in exactly ONE of the 4 planes; each plane gets its
               own per-line palette of 255 colours + transparent index 0, so a line
               can hold up to 4*255 = 1020 colours

A line is only 320 pixels wide, so it never has more than 320 distinct colours: mode 3
holds every line exactly (the per-line clustering to 1020 is the identity), and mode 2
merges only the lines that carry more than 256. A line's colours are sorted by
luminance and cut into 4 contiguous runs, one per plane.

The image area is IMAGE_H rows; the last CAPTION_H rows are the scene's caption band
(palette: 0 transparent, 1 white ink) on plane 0.

Two pictures, switched with Space in the scene: p0 is procedural (tools/mpp_picture.py,
deterministic), p1 is a public-domain photo (see PARROT below).

Outputs per picture <P>, under apps/zig/assets/screens/mpp_truecolor/:
  p<P>_m<N>_pal.bin   RGBA bytes (r,g,b,a — the plane palette's little-endian u32 packing)
  p<P>_m<N>_map.bin   4 planes x 200 lines of (u32 byte offset into the pal blob, u16
                      first entry, u16 count): the HBL copies count*4 bytes to palette[first..]
  p<P>_m1_idx.bin / p<P>_m2_idx.bin   320x200 u8 indices for plane 0
  p<P>_m3_idx.bin     320x200 u16 LE: plane << 8 | index
  p<P>_counts.bin     4 x u32 LE: source, mode 1, mode 2, mode 3 distinct colours (image area)

Usage:
  tools/mpp_convert.py [--source-out DIR] [--method mediancut|libimagequant]
--source-out saves each source picture for comparisons.
"""
import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

from mpp_picture import IMAGE_H, generate

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps/zig/assets/screens/mpp_truecolor"
# "Parrot.red.macaw.1.arp.750pix.jpg" by Adrian Pingstone, public domain (Wikimedia
# Commons): the 750x422 band from y=40 (the head), LANCZOS-resized to 320x180.
PARROT = OUT / "parrot.png"
W, H = 320, 200
CAPTION_H = H - IMAGE_H
PLANES = 4
CAPTION_PAL = [(0, 0, 0, 0), (255, 255, 255, 255)]  # entry 0 transparent, 1 ink
METHODS = {"mediancut": Image.Quantize.MEDIANCUT, "libimagequant": Image.Quantize.LIBIMAGEQUANT}


# ---- quantisation ---------------------------------------------------------------
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
    flat = q.getpalette()[: n * 3]
    pal = [tuple(flat[i * 3:i * 3 + 3]) for i in range(n)]
    return pal, list(q.getdata())


def luma(c):
    return 299 * c[0] + 587 * c[1] + 114 * c[2]


class Mode:
    """Accumulates one mode's palette blob, line map and indices."""

    def __init__(self):
        self.pal = bytearray()
        self.map = [[(0, 0, 0)] * H for _ in range(PLANES)]
        self.cache = {}

    def add(self, colours, first):
        key = (first, tuple(colours))
        if key not in self.cache:  # identical palettes share one copy (mode 1)
            self.cache[key] = len(self.pal)
            for c in colours:
                self.pal += bytes((*c[:3], c[3] if len(c) == 4 else 255))
        return (self.cache[key], first, len(colours))

    def caption(self):
        for y in range(IMAGE_H, H):
            self.map[0][y] = self.add(CAPTION_PAL, 0)

    def map_bytes(self):
        return b"".join(struct.pack("<IHH", *self.map[p][y]) for p in range(PLANES) for y in range(H))


def mode_global(img, method):
    m = Mode()
    pal, idx = quantize(list(img.getdata()), 256, method, W, IMAGE_H)
    for y in range(IMAGE_H):
        m.map[0][y] = m.add(pal, 0)
    m.caption()
    shown = {pal[i] for i in idx}
    return m, bytes(idx) + bytes(W * CAPTION_H), shown


def mode_per_line(img, method):
    m = Mode()
    out, shown = bytearray(), set()
    for y, row in enumerate(rows(img)):
        pal, idx = quantize(row, 256, method, W, 1)
        m.map[0][y] = m.add(pal, 0)
        out += bytes(idx)
        shown |= {pal[i] for i in idx}
    m.caption()
    return m, bytes(out) + bytes(W * CAPTION_H), shown


def mode_four_planes(img):
    m = Mode()
    out, shown = bytearray(), set()
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
                where[c] = (p << 8) | (i + 1)
        out += b"".join(struct.pack("<H", where[c]) for c in row)
        shown |= set(row)
    m.caption()
    return m, bytes(out) + bytes(2 * W * CAPTION_H), shown


def pictures():
    """The pictures the scene switches between with Space, in order."""
    return [
        ("spheres", generate()),
        # PARROT: already cropped and resized to 320x180, so the converter never resamples it.
        ("parrot", Image.open(PARROT).convert("RGB")),
    ]


def convert(p, name, img, method, source_out):
    if img.size != (W, IMAGE_H):
        sys.exit(f"mpp_convert: picture {name} is {img.size}, not {W}x{IMAGE_H}")
    if source_out:
        img.save(Path(source_out) / f"p{p}_source.png")
    results = [
        mode_global(img, method),
        mode_per_line(img, method),
        mode_four_planes(img),
    ]
    counts = [len(set(img.getdata()))]
    for n, (mode, idx, shown) in enumerate(results, 1):
        (OUT / f"p{p}_m{n}_pal.bin").write_bytes(mode.pal)
        (OUT / f"p{p}_m{n}_map.bin").write_bytes(mode.map_bytes())
        (OUT / f"p{p}_m{n}_idx.bin").write_bytes(idx)
        counts.append(len(shown))
    (OUT / f"p{p}_counts.bin").write_bytes(struct.pack("<4I", *counts))
    print(f"mpp_convert: {name}: source {counts[0]} colours; global {counts[1]}, per-line {counts[2]}, 4-plane {counts[3]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source-out", help="save each source picture here as p<P>_source.png (a directory)")
    # libimagequant: +4.4 dB over median cut on the generated picture (global mode).
    # Needs a Pillow built with it (features.check("libimagequant")); else pass mediancut.
    ap.add_argument("--method", choices=sorted(METHODS), default="libimagequant")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    for p, (name, img) in enumerate(pictures()):
        convert(p, name, img, args.method, args.source_out)


if __name__ == "__main__":
    main()
