"""Baked face colours for Track Kit tracks (R82 M5): the arcade Virtua Racing look.

Each face stores its own colour; nothing is lit at run time and nothing is dithered. The converter bakes the tone once, from
the face normal against the track's fixed sun (its mood), onto the palette levels of the face's material ramp:

    level = LO + round((HI - LO) * max(0, n . sun))        (LO 4, HI 7)

so a face square to the sun shows its material's authored colour (level 7 = 253/256 of the RGB) and a face turned away from
it is at most three levels (~27 %) darker: neighbouring faces stay in close tones. The alternation of the road's panels is
AUTHORED (two close materials), not lit: on a flat lake every ground normal is the same. The record's `alt` word keeps the
debug key i's two other shades: byte 0 the converter's old light (trackc.colour, LIT), byte 1 a gentle light (SOFT).
"""

from __future__ import annotations

import math
from typing import Callable

from racer import ktrk

LO, HI = 4, 7
LIGHT = (0.4, 0.8, 0.45)  # trackc.LIGHT: the LIT debug shade is the oval's light
Shade = Callable[[str, ktrk.Vec], tuple[int, int]]


def lit(c: int, level: int) -> int:
    """palette.zig `lit`: level 0..7 is 36 % .. 99 % of the channel."""
    return (c * (92 + level * 23)) >> 8


def luma(rgb: tuple[int, int, int]) -> float:
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


def shown(rgb: tuple[int, int, int], level: int) -> tuple[int, int, int]:
    return (lit(rgb[0], level), lit(rgb[1], level), lit(rgb[2], level))


def level(n: ktrk.Vec, sun: ktrk.Vec) -> int:
    lam = max(0.0, ktrk.dot(n, ktrk.unit(sun)))
    return LO + math.floor((HI - LO) * lam + 0.5)


def _old(n: ktrk.Vec, base: float) -> int:
    lam = max(0.0, ktrk.dot(n, ktrk.unit(LIGHT)))
    return min(7, int((base + (1.0 - base) * lam) * 8))


def shader(ramps: dict[str, int], sun: ktrk.Vec) -> Shade:
    """trackc's `shade`: material -> (16 + ramp * 8 + the baked level, the LIT | SOFT << 8 alternates)."""

    def shade(mat: str, n: ktrk.Vec) -> tuple[int, int]:
        base = 16 + ramps[mat] * 8
        return base + level(n, sun), (base + _old(n, 0.25)) | (base + _old(n, 0.65)) << 8

    return shade
