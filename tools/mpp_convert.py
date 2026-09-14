#!/usr/bin/env python3
"""Convert truecolor pictures into ZigMachine MPP-style assets (apps/zig/scenes/mpp_truecolor.zig).

MPP (Multi Palette Picture, https://codeberg.org/zerkman/mpp) shows more colours than
the hardware palette holds by reloading the palette between scanlines. ZigMachine's
per-plane HBL handler runs once before each line is composited, so a plane can take a
whole new 256-entry palette per line. The three modes (GLOBAL, PER-LINE, 4-PLANE) are
built in tools/mpp_modes.py.

The image area is IMAGE_H rows; the last CAPTION_H rows are the scene's caption band
(palette: 0 black, 1 white ink) on plane 0. The pictures, in the order Space steps
through them, are PICTURES below, with their credits.

Outputs under apps/zig/assets/screens/mpp_truecolor/, per picture <P> and mode <N>:
  p<P>_m<N>.bin   one blob; build.zig ZX0-packs it and the scene depacks only the one it shows:
                    map   4 planes x 200 lines of (u32 byte offset into the RGBA palette,
                          u16 first entry, u16 count): the HBL copies count*4 bytes
                    idx   modes 1, 2: 320x200 u8 indices for plane 0
                          mode 3: 320x200 index bytes, then 320x200 plane bytes
                    pal   RGB, each byte minus the byte 3 before it (mod 256); the scene
                          undoes the delta and widens it to RGBA (alpha 255) after depacking
  p<P>_counts.bin 5 x u32 LE: source, mode 1, mode 2, mode 3 distinct colours (image area),
                  then FNV-1a 32 of the source's RGB bytes (the harness's lossless check)

Why this layout: ZX0 has no entropy coder and a 32 KB window. An alpha byte between
random RGB costs a literal; palettes sorted by luminance and delta-coded repeat; the
plane bytes of mode 3 are spatially coherent once they are not interleaved. The
spheres: 655 KB unpacked, 422 KB packed as the old nine raw files, 328 KB as these.

Usage:
  tools/mpp_convert.py [--source-out DIR] [--method mediancut|libimagequant]
--source-out saves each source picture for comparisons.
"""
import argparse
import math
import struct
import sys
from pathlib import Path

from PIL import Image

import mpp_gradients
from mpp_modes import METHODS, W, mode_four_planes, mode_global, mode_per_line
from mpp_picture import IMAGE_H, generate

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps/zig/assets/screens/mpp_truecolor"


def photo(name):
    """A committed 320x180 crop: already LANCZOS-resized, so it is never resampled here."""
    return lambda: Image.open(OUT / name).convert("RGB")


# (name, picture) in scene order: the scene's NAMES and build.zig's MPP_PICTURES follow it.
PICTURES = [
    # Procedural: three Phong spheres, a sky and an HSV floor, +-3 of seeded noise.
    ("spheres", generate),
    # "Parrot.red.macaw.1.arp.750pix.jpg" by Adrian Pingstone, public domain (Wikimedia
    # Commons): the 750x422 band from y=40 (the head), LANCZOS-resized to 320x180.
    ("parrot", photo("parrot.png")),
    # "Sunset over ocean (27717086074).jpg" by Lisa Ann Yount, CC0 (Wikimedia Commons,
    # https://commons.wikimedia.org/wiki/File:Sunset_over_ocean_(27717086074).jpg): of
    # the 2730x1820 original, the 1820x1024 box at (450, 0), the sky and the sun,
    # LANCZOS-resized to 320x180.
    ("sunset", photo("sunset.png")),
    # Procedural, no noise (tools/mpp_gradients.py): a dusk sky and a low sun's halo.
    ("halo", mpp_gradients.halo),
    # Procedural, no noise: ridges fading into fog, a sun glowing through it.
    ("hills", mpp_gradients.hills),
]


def fnv1a(data):
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h


def banding(src, pal, idx):
    """Mode 1 against the source: (PSNR dB, max channel error)."""
    errors = [abs(a - b) for p, i in zip(src, idx) for a, b in zip(p, pal[i])]
    mse = sum(e * e for e in errors) / len(errors)
    return 10 * math.log10(255 ** 2 / mse) if mse else math.inf, max(errors)


def convert(p, name, img, method, source_out):
    if img.size != (W, IMAGE_H):
        sys.exit(f"mpp_convert: picture {name} is {img.size}, not {W}x{IMAGE_H}")
    if source_out:
        img.save(Path(source_out) / f"p{p}_source.png")
    m1, idx1, pal1, q1 = mode_global(img, method)
    counts, sizes = [len(set(img.getdata()))], []
    for n, (mode, idx) in enumerate([(m1, idx1), mode_per_line(img, method), mode_four_planes(img)], 1):
        blob = mode.blob(idx)
        (OUT / f"p{p}_m{n}.bin").write_bytes(blob)
        sizes.append(len(blob) + len(mode.pal) // 3)  # the scene's buffer, palette widened to RGBA
        counts.append(len(mode.shown))
    (OUT / f"p{p}_counts.bin").write_bytes(struct.pack("<5I", *counts, fnv1a(img.tobytes())))
    psnr, worst = banding(list(img.getdata()), pal1, q1)
    print(f"mpp_convert: {name}: source {counts[0]} colours; global {counts[1]} ({psnr:.2f} dB, max error {worst}), "
          f"per-line {counts[2]}, 4-plane {counts[3]}; largest mode {max(sizes)} bytes depacked")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source-out", help="save each source picture here as p<P>_source.png (a directory)")
    # libimagequant: +4.4 dB over median cut on the generated picture (global mode).
    # Needs a Pillow built with it (features.check("libimagequant")); else pass mediancut.
    ap.add_argument("--method", choices=sorted(METHODS), default="libimagequant")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    for p, (name, picture) in enumerate(PICTURES):
        convert(p, name, picture(), args.method, args.source_out)


if __name__ == "__main__":
    main()
