#!/usr/bin/env python3
"""Assets for the REPLICANTS Double Dragon II screen (CODEF 515).

    python3 tools/reps5_assets.py

Source images are kept next to the outputs in apps/zig/assets/screens/reps5/,
fetched by tools/fetch_codef.py from wab.com screen 515.

Why this is not just tools/convert_png.py: that tool takes palette-mode images
and stamps every entry opaque. These three need alpha decided per asset —
the logo is 92% transparent black (it is an OVERLAY: two vertical wordmarks
drawn over the scrollers, not a background), and the font's black field must
drop out the same way or every glyph blits as a solid box.

ONE PALETTE FOR THE WHOLE SCREEN. The scene used to spend a plane per layer
(scrollers / snake / logo), which cost the host a full 800x280 RGBA copy and a
composited canvas layer per plane per frame — the reason it ran at ~30fps. It
now composites all three onto a single plane in the original's own order, so
all three assets must index the SAME 256-entry palette. That palette is built
here, from the complete set of colours, and emitted once as screen_pal.dat.

It fits comfortably: 58 font + 8 logo + 107 distinct gradient colours overlap
to 166 shared entries, 167 with transparent index 0. No quantisation, no
subsampling of the gradient — the snake keeps its full per-row colour.

Outputs:
    screen_pal.dat    256 RGBA entries, index 0 transparent — the whole screen
    logo.raw          320x200 indices into screen_pal
    font.raw          12x840 indices into screen_pal
    gradient_idx.dat  200 bytes: the snake's palette index for each screen row
"""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

DST = Path("apps/zig/assets/screens/reps5")
TRANSPARENT = (0, 0, 0, 0)


class SharedPalette:
    """The one palette every asset on this screen indexes into.

    Index 0 is reserved for transparent. Every other distinct colour gets its
    own entry — these are hand-drawn demo graphics plus a smooth ramp, so there
    is nothing worth quantising and quantising would only smear the ramp.
    """

    def __init__(self) -> None:
        self.entries: list[tuple[int, int, int, int]] = [TRANSPARENT]
        self._lookup: dict[tuple[int, int, int, int], int] = {}

    def index(self, rgb: tuple[int, int, int]) -> int:
        key = (rgb[0], rgb[1], rgb[2], 255)
        if key not in self._lookup:
            self._lookup[key] = len(self.entries)
            self.entries.append(key)
        return self._lookup[key]

    def write(self) -> None:
        if len(self.entries) > 256:
            raise SystemExit(
                f"shared palette needs {len(self.entries)} colours, more than the 256 a plane has"
            )
        flat: list[int] = []
        for r, g, b, a in self.entries:
            flat += [r, g, b, a]
        flat += [0] * ((256 - len(self.entries)) * 4)
        (DST / "screen_pal.dat").write_bytes(struct.pack(f"{len(flat)}B", *flat))
        print(f"  screen_pal.dat {len(self.entries)} colours (of 256)")


def write_raw(name: str, indices: list[int], w: int, h: int) -> None:
    if len(indices) != w * h:
        raise SystemExit(f"{name}: {len(indices)} indices for a {w}x{h} image")
    (DST / f"{name}.raw").write_bytes(struct.pack(f"{len(indices)}B", *indices))
    print(f"  {name}.raw {w}x{h} ({w*h} bytes)")


def index_image(im: Image.Image, pal: SharedPalette, transparent_is: str) -> list[int]:
    """Map an image to shared-palette indices, index 0 meaning transparent.

    `transparent_is` is "alpha" (a==0 drops out) or "black" (pure black drops out).
    """
    im = im.convert("RGBA")
    px = im.load()
    indices: list[int] = []
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            drop = (a == 0) if transparent_is == "alpha" else (r == 0 and g == 0 and b == 0)
            indices.append(0 if drop else pal.index((r, g, b)))
    return indices


def logo(pal: SharedPalette) -> list[int]:
    """640x400 -> 320x200. NEAREST: this is pixel art, and a smooth resample
    invents colours that then each claim a palette entry."""
    im = Image.open(DST / "logo.png").convert("RGBA").resize((320, 200), Image.NEAREST)
    return index_image(im, pal, "alpha")


def font(pal: SharedPalette) -> list[int]:
    """12x840 = 60 glyphs of 12x14, first char 32 (space), kept at ST size.

    NOT halved: the scroller's side copies draw the strip at 1:1 in ST space, so
    12x14 IS the ST glyph. Halving it here would shrink the text, not the screen.
    """
    im = Image.open(DST / "font.png")
    if im.size != (12, 840):
        raise SystemExit(f"font.png is {im.size}, expected (12, 840)")
    return index_image(im, pal, "black")


def gradient(pal: SharedPalette) -> list[int]:
    """raster.png (2x480) -> one palette index per screen row.

    The original stretches this strip across a 320x240 offscreen and masks it
    INTO the snake's lines (globalCompositeOperation = 'source-in'), so it is a
    per-row colour table, never a bitmap. One column is enough — the two are
    identical — and 480 rows resample to the ST's 200.
    """
    im = Image.open(DST / "raster.png").convert("RGBA").resize((1, 200), Image.BILINEAR)
    px = im.load()
    return [pal.index(px[0, y][:3]) for y in range(200)]


if __name__ == "__main__":
    if not DST.is_dir():
        raise SystemExit(f"missing {DST} — run tools/fetch_codef.py 515 and copy the PNGs in")
    print(f"REPLICANTS DD2 (CODEF 515) assets -> {DST}")

    # Index all three FIRST, then write: the palette has to be complete before
    # anything that depends on it is emitted, or the last asset in wins and the
    # earlier ones come out referencing entries that were never filled in.
    pal = SharedPalette()
    logo_idx = logo(pal)
    font_idx = font(pal)
    gradient_idx = gradient(pal)

    pal.write()
    write_raw("logo", logo_idx, 320, 200)
    write_raw("font", font_idx, 12, 840)
    (DST / "gradient_idx.dat").write_bytes(struct.pack("200B", *gradient_idx))
    print(f"  gradient_idx.dat 200 rows ({len(set(gradient_idx))} distinct colours)")

    for stale in ("logo_pal.dat", "font_pal.dat", "gradient.dat"):
        if (DST / stale).exists():
            (DST / stale).unlink()
            print(f"  removed {stale} (superseded by screen_pal.dat)")
