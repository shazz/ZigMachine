"""LOCAL ONLY: the colours of freds72's Virtua Racing faces (tools/racer/vr_import.py), unlit as his engine draws them.

A face's PICO-8 colour byte is a pair of palette indices his engine fills as a 50 % checkerboard (`f.c += 0x1000.a5a5`,
vracing_main.p8 `unpack_face`); the arcade game has solid colours, so a face becomes the average RGB of the pair. His engine
draws every track face UNLIT (`polyfill(d, d.c)`): Sega's artists baked the relief into neighbouring faces' colours (the road's
alternating panels, the mountains' close beige tones), so our converter's n . L light on top doubled the contrast.

Two tone tables, one per PICO-8 index (TONES picks one):
- PICO: his screen palette, decoded right: `_init` remaps 14 and 15 to the secret palette (`pal(14,128,1)`, `pal(15,131,1)`:
  dark brown #291814, dark teal #125359; his exporter's table says the same: Genesis "1" and "c"). The first import used the
  default pink / peach there, the main reason the tracks looked far too bright.
- ARCADE (the default): OUR calibration, not ripped data. PICO-8's 16 colours are a coarse stand-in for the Mega Drive's
  (his exporter folds Genesis "7" and "8" into 6, and puts the road's darker panel, Genesis "9", on 13, far darker), so this
  table maps each index to the tone of the same surface sampled from two arcade screenshots (road panels ~90-116 grey,
  grass greens, dark trees; the banks and rock, indices 4 and 9, keep his luma order and spacing, darker: one PICO-8 index
  stands for two Genesis colours there). Change TONES to PICO to see his palette.
"""

from __future__ import annotations

import math
from typing import Callable

PICO = ["000000", "1D2B53", "7E2553", "008751", "AB5236", "5F574F", "C2C3C7", "FFF1E8", "FF004D", "FFA300", "FFEC27",
        "00E436", "29ADFF", "83769C", "291814", "125359"]
ARCADE = {  # PICO index -> the arcade tone (Genesis colour per blender_export_track.py, then the screenshot surface)
    0: (0, 0, 0), 1: (24, 48, 120), 2: (126, 37, 83),
    3: (34, 88, 12),     # Genesis "a" dark green: the darker grass band
    4: (104, 78, 48),    # "d" light yellow and "f" brown: banks and rock, kept in his luma order (below the light grass)
    5: (70, 70, 72),     # "6" dark grey
    6: (112, 112, 114),  # "7" / "8" light greys: the road's lighter panel
    7: (200, 200, 200),  # "2" white: lane lines, the light verge
    8: (206, 32, 32),    # "3" red
    9: (176, 116, 48),   # "e" dark yellow: sand, ochre banks
    10: (232, 204, 64),  # "5" yellow
    11: (70, 132, 12),   # "b" light green: the lighter grass band
    12: (32, 110, 228),  # "4" dark blue
    13: (92, 92, 98),    # "9" dark bluish grey: the road's darker panel
    14: (108, 90, 64),   # "1" dark brown (his secret 128)
    15: (12, 56, 16),    # "c" dark green (his secret 131): trees
}
TONES = "ARCADE"
LIGHT = (0.4, 0.8, 0.45)  # trackc.LIGHT: the debug key's "lit" shade reproduces the converter's light
FLAT = 7  # the palette's level 7 is 253/256 of the ramp's RGB: the colour as stored


def tone(i: int) -> tuple[int, int, int]:
    if TONES == "PICO":
        h = PICO[i]
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return ARCADE[i]


def rgb_of(c: int) -> tuple[int, int, int]:
    """The solid colour of a dither pair: the average of its two tones."""
    a, b = tone(c & 15), tone((c >> 4) & 15)
    return ((a[0] + b[0]) // 2, (a[1] + b[1]) // 2, (a[2] + b[2]) // 2)


def lit(c: int, level: int) -> int:
    """palette.zig `lit`: level 0..7 is 36 % .. 99 % of the channel."""
    return (c * (92 + level * 23)) >> 8


def luma(p: tuple[float, float, float]) -> float:
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def place(codes: list[int], ramps: list[int], lead: list[int]) -> tuple[dict[int, tuple[int, int]], dict[int, tuple[int, int, int]]]:
    """Codes (most used first, `lead` forced first) -> (ramp, level) and ramp -> RGB. The first len(ramps) codes own a ramp at
    FLAT; a code past them takes the (ramp, level) whose shade is nearest its colour (a darker step of a near ramp)."""
    order = lead + [c for c in codes if c not in lead]
    own = dict(zip(ramps, order, strict=False))
    rgb = {r: rgb_of(c) for r, c in own.items()}
    at = {c: (r, FLAT) for r, c in own.items()}
    for c in order[len(ramps):]:
        want = rgb_of(c)
        at[c] = min(((r, lv) for r in rgb for lv in range(8)),
                    key=lambda p: math.dist(want, tuple(lit(x, p[1]) for x in rgb[p[0]])))
    return at, rgb


def _level(n: tuple[float, float, float], base: float) -> int:
    lam = max(0.0, sum(a * b for a, b in zip(n, LIGHT, strict=True)) / math.sqrt(sum(x * x for x in LIGHT)))
    return min(7, int((base + (1.0 - base) * lam) * 8))


def shader(at: dict[int, tuple[int, int]], headroom: bool = False) -> Callable[[str, tuple[float, float, float]], tuple[int, int]]:
    """trackc's `shade`: material "c<byte>" -> (the flat colour, the debug key's alternates: byte 0 lit as the converter
    lights (the old look), byte 1 a gentle light, levels 5..7). `headroom` (R82, the shadow headroom): byte 2 is the flat
    colour kept one level off its ramp's bottom (level 0 -> 1), so the cars' one-darker shadow shows on it; the cart draws
    it with the toggle on (project.headroom), the plain colour otherwise."""

    def shade(mat: str, n: tuple[float, float, float]) -> tuple[int, int]:
        ramp, level = at[int(mat[1:], 16)]
        base = 16 + ramp * 8
        drop = FLAT - level
        old, soft = max(0, _level(n, 0.25) - drop), max(0, _level(n, 0.65) - drop)
        room = (base + max(1, level)) << 16 if headroom else 0
        return base + level, (base + old) | (base + soft) << 8 | room

    return shade
