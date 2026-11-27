"""LOCAL ONLY: the colours of an imported 32X course (tools/racer/vr32x_import.py), unlit as the 32X draws them.

Each face is its palette entry, solid. A course uses 74-99 entries and the cart has 23 free ramps of 8 levels
(vr_colours.lit), so: the road and the far ground own the first two ramps, then the entry worst served so far (its colour
distance to the nearest ramp shade, weighted by the square root of its area) owns the next, until the ramps run out; every
other entry takes its nearest (ramp, level) shade.
"""

from __future__ import annotations

import math

from racer import limits, vr_colours, vr_import
from racer.vr32x_geom import Mesh, _area2
from racer.vr32x_rom import RGB

BOOST = 50
At = dict[int, tuple[int, int]]  # palette index -> (ramp, level)
Cols = tuple[At, dict[int, RGB]]  # ... and ramp -> RGB


def colours(m: Mesh, pal: list[RGB], reserve: int = 0,
            boost: frozenset[int] = frozenset()) -> tuple[At, dict[int, RGB], dict[int, float]]:
    """palette index -> (ramp, level), ramp -> RGB, and each index's area (for the report's error). The last `reserve`
    free ramps are left to the panorama's colours (R82 32X look: `reserved`). `boost`: entries weighed as if BOOST times
    their area (the placed objects' colours: a banner's text is small but must not take the nearest grass shade)."""
    area: dict[int, float] = {}
    for f in m.faces:
        area[f.colour] = area.get(f.colour, 0.0) + _area2(m.pts(f.v))
    road = max((f for f in m.faces if f.kind == "track"), key=lambda f: area[f.colour]).colour
    ground = max((f.colour for f in m.faces if f.kind == "ground"), key=lambda c: area[c])
    own = [road, ground]

    def err(c: int) -> float:
        return min(math.dist(pal[c], tuple(vr_colours.lit(x, lv) for x in pal[o])) for o in own for lv in range(8))
    while len(own) < len(limits.FREE_RAMPS) - reserve:
        rest = [c for c in area if c not in own]
        if not rest:
            break
        own.append(max(rest, key=lambda c: math.sqrt(area[c] * (BOOST if c in boost else 1)) * err(c)))
    rgb = {r: pal[c] for r, c in zip(limits.FREE_RAMPS, own, strict=False)}
    at = {c: (r, vr_colours.FLAT) for r, c in zip(limits.FREE_RAMPS, own, strict=False)}
    for c in area:
        if c not in at:
            at[c] = min(((r, lv) for r in rgb for lv in range(8)),
                        key=lambda p: math.dist(pal[c], tuple(vr_colours.lit(x, p[1]) for x in rgb[p[0]])))
    return at, rgb, area


def errors(pal: list[RGB], at: At, rgb: dict[int, RGB]) -> dict[int, float]:
    """Each entry's RGB distance to the shade it is drawn with."""
    return {c: math.dist(pal[c], tuple(vr_colours.lit(x, lv) for x in rgb[r])) for c, (r, lv) in at.items()}


def reserved(n: int) -> list[int]:
    """The ramps `colours(reserve=n)` leaves free: the panorama's (its entries 16 + 8 x ramp ..)."""
    return list(limits.FREE_RAMPS[len(limits.FREE_RAMPS) - n:]) if n else []


def mats(rgb: dict[int, RGB], reserve: int = 0) -> dict[str, tuple[int, RGB]]:
    mats = dict(vr_import.CAR)
    for ramp in reserved(reserve):  # placeholders: the cart puts the panorama's colours there
        mats[f"pan{ramp}"] = (ramp, (128, 128, 128))
    for ramp, c in rgb.items():
        mats[f"vr{ramp}"] = (ramp, c)
    for ramp in range(15, 19):
        mats[f"pad{ramp}"] = (ramp, (128, 128, 128))
    return mats
