"""The car's shadow as its FOOTPRINT (R82 bug pass, Matt 27 Nov: "the car shadow is a rectangle; the 32X's follows the
car's footprint"): the top view of the near model (wheels, hull, cabin, wing) cut into slabs along z, each slab's covered
x-intervals one quad (a trapezoid from the intervals at the slab's two ends, or a rectangle where they do not pair up).

The cart darkens the shadow polygons in place, so they must NOT overlap: within a slab the intervals are disjoint, the
slabs meet on their z lines, and the span emitter's fill rule gives a shared edge to exactly one polygon (poly.zig). The
quads lie on the ground (y = 1 Q7) wound to face up, as the one quad did. carc.convert writes them as the shadow part of
every car it converts (our GT and the local 32X cars alike): no per-car authoring, no format change (the cart reads 1 to
MAX_QUADS shadow faces).
"""

from __future__ import annotations

import itertools
from collections.abc import Sequence
from typing import Final

NEAR: Final = ("wheels", "hull", "cabin", "wing")
MAX_QUADS: Final = 16  # carfile.zig MAX_SHADOW
SLABS: Final = 10  # the first try: about this many slabs along the car
MIN_WIDTH: Final = 2.0  # Q7: a narrower interval is dropped (a side face seen edge on)
Y: Final = 1  # Q7 above the ground, as the authored quad
Pt = tuple[float, float]
Quad = list[tuple[int, int, int]]


def _section(poly: Sequence[Pt], z: float) -> tuple[float, float] | None:
    """The x-range of a convex polygon (x, z) cut by the line at z, or None when the line misses it."""
    xs = []
    n = len(poly)
    for i in range(n):
        (ax, az), (bx, bz) = poly[i], poly[(i + 1) % n]
        if az == bz:
            if az == z:
                xs += [ax, bx]
            continue
        if min(az, bz) <= z <= max(az, bz):
            xs.append(ax + (bx - ax) * (z - az) / (bz - az))
    return (min(xs), max(xs)) if xs else None


def intervals(polys: Sequence[Sequence[Pt]], z: float) -> list[tuple[float, float]]:
    """The union of the polygons' x-ranges on the line at z: sorted, disjoint, each at least MIN_WIDTH wide."""
    got = sorted(r for p in polys if (r := _section(p, z)) is not None)
    out: list[list[float]] = []
    for lo, hi in got:
        if out and lo <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], hi)
        else:
            out.append([lo, hi])
    return [(a, b) for a, b in out if b - a >= MIN_WIDTH]


def _cuts(polys: Sequence[Sequence[Pt]], slabs: int) -> list[float]:
    """The slab boundaries: every vertex z, merged so no slab is thinner than the car's length / `slabs`."""
    zs = sorted({z for p in polys for _, z in p})
    gap = (zs[-1] - zs[0]) / slabs
    cuts = [zs[0]]
    for z in zs[1:-1]:
        if z - cuts[-1] >= gap and zs[-1] - z >= gap / 2:
            cuts.append(z)
    return cuts + [zs[-1]]


def _slab(polys: Sequence[Sequence[Pt]], za: float, zb: float) -> list[Quad]:
    a, b = intervals(polys, za + 0.5), intervals(polys, zb - 0.5)
    if len(a) != len(b):
        a = b = intervals(polys, (za + zb) / 2)
    out = []
    for (a0, a1), (b0, b1) in zip(a, b, strict=True):
        za_, zb_ = round(za), round(zb)
        q = [(round(a0), Y, za_), (round(a1), Y, za_), (round(b1), Y, zb_), (round(b0), Y, zb_)]
        if q[0] == q[1]:
            q = q[1:]
        elif q[2] == q[3]:
            q = q[:3]
        if len(q) >= 3 and za_ < zb_:
            out.append(q)
    return out


def _colinear(a: tuple[int, int, int], b: tuple[int, int, int], c: tuple[int, int, int]) -> bool:
    return (b[0] - a[0]) * (c[2] - a[2]) == (c[0] - a[0]) * (b[2] - a[2])


def merged(qs: list[Quad]) -> list[Quad]:
    """Quads joined where one continues another (a shared edge, both sides straight on): fewer polygons, the same pixels."""
    out: list[Quad] = []
    for q in qs:
        for i, p in enumerate(out):
            if len(p) == 4 and len(q) == 4 and p[3] == q[0] and p[2] == q[1] and _colinear(p[0], p[3], q[3]) and _colinear(p[1], p[2], q[2]):
                out[i] = [p[0], p[1], q[2], q[3]]
                break
        else:
            out.append(q)
    return out


def quads(polys: Sequence[Sequence[Pt]]) -> list[Quad]:
    """The footprint of the top-view polygons as at most MAX_QUADS non-overlapping quads (or triangles) facing up."""
    for slabs in range(SLABS, 0, -1):
        cuts = _cuts(polys, slabs)
        out = merged([q for za, zb in itertools.pairwise(cuts) for q in _slab(polys, za, zb)])
        if len(out) <= MAX_QUADS:
            return out
    raise ValueError("footprint: no slab count fits the shadow's face limit")


def top_view(vertices: Sequence[Sequence[int]], faces: Sequence[Sequence[int]]) -> list[list[Pt]]:
    """Each face's (x, z) outline (car space: x right, z forward)."""
    return [[(float(vertices[i][0]), float(vertices[i][2])) for i in f] for f in faces]
