#!/usr/bin/env python3
"""Assets for The Carebears' STARWARS SCROLLER, The Cuddly Demos (CODEF screen 360).

    python3 tools/cuddly_starwars_assets.py

Reads prototypes/codef/360/ (tools/fetch_codef.py 360). Every PNG is already at
ST scale (1x): the remake composes a 320x200 canvas and zooms THAT 2x onto its
768x540 page, so nothing here is halved.

Outputs into apps/zig/assets/screens/cuddly_starwars/:
    font.raw      320x156  fontr.png + fontg.png merged (their inks never overlap):
                           0 transparent, 1 red ink (recoloured by the raster), 2..7 greys
    swfont.raw    170x69   starwars glyphs, 0 / 1 ink (swfont.png, 17x11 tiles)
    sprite.raw    128x10   theunionsprite.png, 0 transparent, 10..15 its colours
    bg.raw        260x73   bg.png, 0 transparent, 8 orange, 9 its one grey pixel
    raster.dat             scrollraster.png's first 72 rows (the image repeats them
                           four times; asserted), as 256 RGBA entries
    screen_pal.dat         indices 0..15 above at full strength
And the screen's own data, verbatim, into apps/zig/scenes/cuddly_starwars/tables.zig:
    spriteX / spriteY (the definitions left live by the source's /*/ toggles),
    the horizontal scrolltext and the 128 starwars lines.
"""
from __future__ import annotations

import json
import re
import struct
from pathlib import Path

from PIL import Image

SRC = Path("prototypes/codef/360")
DST = Path("apps/zig/assets/screens/cuddly_starwars")
TABLES = Path("apps/zig/scenes/cuddly_starwars/tables.zig")

RED_INK = 1
GREY_FIRST = 2
BG_FIRST = 8
SPRITE_FIRST = 10
FIXED = 16


def rgba(name: str) -> Image.Image:
    return Image.open(SRC / "assets" / name).convert("RGBA")


def colours(im: Image.Image) -> list[tuple[int, int, int, int]]:
    """Distinct opaque colours, sorted; the PNGs carry no partial alpha (asserted)."""
    seen = set()
    for px in im.getdata():
        if px[3] not in (0, 255):
            raise SystemExit("unexpected partial alpha")
        if px[3]:
            seen.add(px)
    return sorted(seen)


def index(im: Image.Image, lut: dict) -> bytes:
    return bytes(lut[px] if px[3] else 0 for px in im.getdata())


def write(name: str, data: bytes, size: int) -> None:
    if len(data) != size:
        raise SystemExit(f"{name}: {len(data)} bytes, expected {size}")
    (DST / name).write_bytes(data)
    print(f"  {name}: {size} bytes")


def pal_bytes(entries: list[tuple[int, int, int, int]]) -> bytes:
    flat = [v for c in entries for v in c] + [0] * ((256 - len(entries)) * 4)
    return struct.pack("1024B", *flat)


def images() -> None:
    palette = [(0, 0, 0, 255)] * FIXED
    fontr, fontg = rgba("fontr.png"), rgba("fontg.png")
    reds, greys = colours(fontr), colours(fontg)
    if len(reds) != 1 or len(greys) != 6:
        raise SystemExit(f"fonts: {len(reds)} reds, {len(greys)} greys")
    lut = {reds[0]: RED_INK} | {c: GREY_FIRST + i for i, c in enumerate(greys)}
    merged = bytearray(index(fontg, lut))
    for i, px in enumerate(fontr.getdata()):
        if px[3]:
            if merged[i]:
                raise SystemExit("fontr and fontg overlap")
            merged[i] = RED_INK
    write("font.raw", bytes(merged), 320 * 156)
    palette[RED_INK] = reds[0]
    for i, c in enumerate(greys):
        palette[GREY_FIRST + i] = c

    sw = rgba("swfont.png")
    write("swfont.raw", bytes(1 if px[3] else 0 for px in sw.getdata()), 170 * 69)

    bg = rgba("bg.png")
    bgc = sorted(colours(bg), key=lambda c: -sum(1 for p in bg.getdata() if p == c))
    write("bg.raw", index(bg, {c: BG_FIRST + i for i, c in enumerate(bgc)}), 260 * 73)
    for i, c in enumerate(bgc):
        palette[BG_FIRST + i] = c

    spr = rgba("theunionsprite.png")
    sc = colours(spr)
    write("sprite.raw", index(spr, {c: SPRITE_FIRST + i for i, c in enumerate(sc)}), 128 * 10)
    for i, c in enumerate(sc):
        palette[SPRITE_FIRST + i] = c

    rast = rgba("scrollraster.png")
    rows = [rast.getpixel((0, y)) for y in range(rast.height)]
    if rast.size != (1, 288) or any(rows[y] != rows[y % 72] for y in range(288)):
        raise SystemExit("scrollraster.png is expected to be 4 x the same 72 rows")
    write("raster.dat", pal_bytes(rows[:72]), 1024)
    write("screen_pal.dat", pal_bytes(palette), 1024)


def js_strings(literal: str) -> list[str]:
    return [json.loads(m) for m in re.findall(r'"(?:[^"\\]|\\.)*"', literal)]


def tables() -> None:
    # Strip comments exactly as JS does: the source toggles whole blocks with /*/.
    js = re.sub(r"/\*.*?\*/", "", (SRC / "screen.js").read_text(), flags=re.S)
    js = re.sub(r"^\s*//.*$", "", js, flags=re.M)

    def array(name: str) -> str:
        found = re.findall(rf"var {name}\s*=\s*\[(.*?)\];", js, flags=re.S)
        if len(found) != 1:
            raise SystemExit(f"{name}: {len(found)} live definitions")
        return found[0]

    sx = [int(v) for v in array("spriteX").split(",")]
    sy = [int(v) for v in array("spriteY").split(",")]
    if len(sx) != len(sy):
        raise SystemExit("spriteX/spriteY lengths differ")
    stext = js_strings(re.search(r'var stext\s*=\s*("(?:[^"\\]|\\.)*");', js).group(1))[0]
    lines = js_strings(array("sstext"))

    def zig_str(s: str) -> str:
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    out = [
        "// GENERATED by tools/cuddly_starwars_assets.py from prototypes/codef/360/screen.js.",
        "// The screen's own data, verbatim. Do not edit by hand.",
        "",
        f"pub const sprite_x = [_]u16{{ {', '.join(map(str, sx))} }};",
        f"pub const sprite_y = [_]u16{{ {', '.join(map(str, sy))} }};",
        "",
        f"pub const scroll_text = {zig_str(stext)};",
        "",
        "pub const starwars_lines = [_][]const u8{",
        *[f"    {zig_str(s)}," for s in lines],
        "};",
        "",
    ]
    TABLES.parent.mkdir(parents=True, exist_ok=True)
    TABLES.write_text("\n".join(out))
    print(f"  {TABLES}: {len(sx)} sprite steps, text {len(stext)}, {len(lines)} lines")


if __name__ == "__main__":
    DST.mkdir(parents=True, exist_ok=True)
    print(f"CUDDLY STARWARS (CODEF 360) assets -> {DST}")
    images()
    tables()
