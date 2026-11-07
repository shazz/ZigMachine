#!/usr/bin/env python3
"""The parrot photo as an 8-bit texture for the rotozoom / Mode 7 / tunnel carts.

Used by apps/zig/assets/screens/parrot/parrot.zig, which ZIGGY (ROTO, the CPU rotozoom) and
CHISEL V2 (AFFINE rotozoom, Mode 7 and MAP tunnel) import. Both carts read
the SAME bytes, so there is one output for both.

Source: Adrian Pingstone, "Parrot.red.macaw.1.arp.750pix.jpg" (a scarlet macaw),
public domain, Wikimedia Commons:
  https://commons.wikimedia.org/wiki/File:Parrot.red.macaw.1.arp.750pix.jpg
  https://upload.wikimedia.org/wikipedia/commons/b/bc/Parrot.red.macaw.1.arp.750pix.jpg
The 750x1002 original is committed beside the outputs (parrot750.jpg); MPP TRUECOLOR
uses a 320x180 band of the same photo.

What it does (build-time, never per frame):
  1. square crop CROP (400x400, the head and the shoulder, the eye near the centre)
  2. LANCZOS down to 256, 128 and 64 texels a side
  3. ONE median-cut palette of COLOURS entries from the 256 picture; the 128 and 64
     are mapped to that same palette, so the palette never changes with the size.
     No dither: dither noise shimmers under a rotozoom.
  4. the indices are stored at BASE..BASE+COLOURS-1 (56..247): free in both carts.
     ZIGGY keeps 254/255 for its HUD; CHISEL V2 uses 0, 1, 2, 16..31, 40..43, 50.

Outputs, apps/zig/assets/screens/parrot/:
  parrot_tex.bin  64x64, then 128x128, then 256x256 u8 indices (86,016 bytes), the
                  layout of ZIGGY's generated textures (maps.zig TEX_BYTES)
  parrot_pal.bin  COLOURS x RGB (576 bytes), entry k is palette index BASE + k

Usage: tools/parrot_tex.py [--png DIR]   (--png: the three sizes as PNGs, to look at)
"""
import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "apps/zig/assets/screens/parrot"
CROP = (40, 0, 440, 400)  # left, top, right, bottom of the 750x1002 original
SIZES = (64, 128, 256)
COLOURS = 192
BASE = 56


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--png", help="also write the quantized sizes as PNGs here")
    args = ap.parse_args()
    square = Image.open(DIR / "parrot750.jpg").convert("RGB").crop(CROP)
    sized = {n: square.resize((n, n), Image.Resampling.LANCZOS) for n in SIZES}
    q256 = sized[256].quantize(COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q256.getpalette()[: COLOURS * 3]
    out = bytearray()
    for n in SIZES:
        q = q256 if n == 256 else sized[n].quantize(palette=q256, dither=Image.Dither.NONE)
        idx = q.tobytes()
        assert len(idx) == n * n and max(idx) < COLOURS
        out += bytes(BASE + i for i in idx)
        if args.png:
            Path(args.png).mkdir(parents=True, exist_ok=True)
            q.convert("RGB").save(Path(args.png) / f"parrot_{n}.png")
    (DIR / "parrot_tex.bin").write_bytes(out)
    (DIR / "parrot_pal.bin").write_bytes(bytes(pal))
    print(f"parrot: {len(out)} texel bytes, {COLOURS} colours at {BASE}..{BASE + COLOURS - 1}")


if __name__ == "__main__":
    main()
