"""LOCAL ONLY: a racing line SYNTHESISED on the asphalt of an imported 32X track (tools/racer/vr32x_import.py).

The 32X keeps its course data (the AI's path, the collision pages) in tables this importer does not decode, so the line
is found on the road faces instead, two ways (the importer keeps the longest good one): the SHORTEST LAP through a cut
across the road at a seed (vr32x_cells.Cells.lap: stubs and dead ends never on it, but it skips a lollipop) and the WALK
(vr32x_walk.py: follows the road, so it takes the lollipop). Along either, a station is a cross-section: a ray left and
right across the asphalt (at the current height, so a crossing above or below is not mistaken for the road), the middle
taken; a stretch much wider than the road so far (the pit apron, a junction) keeps the predicted point and the usual
width. The closed line is smoothed and resampled into evenly spaced segments, each a (left, right) pair of NEW vertices
on the road edges (faces do not use them).
"""

from __future__ import annotations

import math

from racer.vr32x_cells import Cells
from racer.vr32x_geom import Bins, Face, Mesh

STEP = 0.5  # units a walk step
RAY = 0.125  # units a ray step
MAX_HALF = 6.0  # units: a ray stops there
COVER = 0.4  # a lap passes through at least this share of the asphalt's tiles
CLIMB = 0.5  # units: the road's height between two samples a step apart (an overpass is higher)
TRACK = ("track",)
Pt = tuple[float, float, float]
Station = tuple[Pt, Pt, Pt]


class LineError(ValueError):
    pass


def _height(bins: Bins, x: float, z: float, y: float) -> float | None:
    hs = [h for _, h in bins.under(x, z, TRACK) if abs(h - y) < CLIMB]
    return min(hs, key=lambda h: abs(h - y)) if hs else None


def _reach(bins: Bins, x: float, z: float, y: float, dx: float, dz: float) -> float:
    d, h = 0.0, y
    while d < MAX_HALF:
        nh = _height(bins, x + dx * (d + RAY), z + dz * (d + RAY), h)
        if nh is None:
            return d
        d, h = d + RAY, nh
    return d


def _station(bins: Bins, p: Pt, hd: tuple[float, float], width: float) -> Station | None:
    """(left, centre, right) across the road one step ahead of p, or None off the road. Much wider than `width` (the pit
    apron, a junction) keeps the predicted point and the usual width."""
    x, z = p[0] + hd[0] * STEP, p[2] + hd[1] * STEP
    y = _height(bins, x, z, p[1])
    if y is None:
        return None
    nx, nz = -hd[1], hd[0]  # left of the heading (x right, z forward, y up)
    left, right = _reach(bins, x, z, y, nx, nz), _reach(bins, x, z, y, -nx, -nz)
    wide = width > 0 and left + right > 1.6 * width
    off = 0.0 if wide else (left - right) / 2
    x, z = x + nx * off, z + nz * off
    half = width / 2 if wide else (left + right) / 2

    def at(s: float) -> Pt:
        return (x + nx * s, _height(bins, x + nx * s, z + nz * s, y) or y, z + nz * s)
    return at(half), (x, y, z), at(-half)


def follow(bins: Bins, guide: list[Pt]) -> list[Station]:
    """Stations along a guide path (vr32x_cells.Cells.lap): every STEP of it, a cross-section square to its direction."""
    acc = [0.0]
    for i in range(1, len(guide)):
        acc.append(acc[-1] + math.dist(guide[i - 1], guide[i]))
    out: list[Station] = []
    j, s = 0, 0.0
    while s < acc[-1]:
        while acc[j + 1] < s:
            j += 1
        a, b = guide[max(0, j - 4)], guide[min(len(guide) - 1, j + 5)]  # the direction over ~4 units: the cells zigzag
        d = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
        hd = ((b[0] - a[0]) / d, (b[2] - a[2]) / d)
        g = guide[j]
        widths = sorted(math.dist(t[0], t[2]) for t in out[-40:])
        st = _station(bins, (g[0] - hd[0] * STEP, g[1], g[2] - hd[1] * STEP), hd, widths[len(widths) // 2] if widths else 0.0)
        if st:
            out.append(st)
        s += STEP
    return out


def overlap(st: list[Station]) -> float:
    """The share of stations another stretch of the walk passes within a unit of (a walk that doubles back scores high;
    a figure-8's crossing only a few stations)."""
    n, far, cells = len(st), 40, {}
    for i, a in enumerate(st):
        cells.setdefault((round(a[1][0]), round(a[1][2])), []).append(i)
    hits = 0
    for i, a in enumerate(st):
        x, z = round(a[1][0]), round(a[1][2])
        near = (j for dx in (-1, 0, 1) for dz in (-1, 0, 1) for j in cells.get((x + dx, z + dz), []))
        if any(min(abs(i - j), n - abs(i - j)) >= far and math.dist(a[1], st[j][1]) < 1 for j in near):
            hits += 1
    return hits / n


def smooth(st: list[Station], k: int = 3) -> list[Station]:
    """A moving average of 2k + 1 stations (the walk's centres jitter by a ray step)."""
    n = len(st)
    return [tuple(tuple(sum(st[(i + d) % n][e][c] for d in range(-k, k + 1)) / (2 * k + 1) for c in range(3))
                  for e in range(3)) for i in range(n)]  # type: ignore[misc]  # [tuple-size] 3 x 3 by construction


def resample(st: list[tuple[Pt, Pt, Pt]], n: int) -> list[tuple[Pt, Pt]]:
    """n (left, right) pairs evenly spaced by arc length along the centres of a closed walk."""
    acc = [0.0]
    for i in range(1, len(st) + 1):
        acc.append(acc[-1] + math.dist(st[i - 1][1], st[i % len(st)][1]))
    out, j = [], 0
    for k in range(n):
        s = acc[-1] * k / n
        while acc[j + 1] < s:
            j += 1
        a, b = st[j], st[(j + 1) % len(st)]
        f = (s - acc[j]) / ((acc[j + 1] - acc[j]) or 1.0)
        out.append(tuple(tuple(a[e][c] + (b[e][c] - a[e][c]) * f for c in range(3)) for e in (0, 2)))  # type: ignore[misc]  # [tuple-size] 2 x 3 by construction
    return out


def length(st: list[tuple[Pt, Pt, Pt]]) -> float:
    return sum(math.dist(st[i - 1][1], st[i][1]) for i in range(len(st)))


def seeds(m: Mesh, n: int = 32) -> list[tuple[Pt, tuple[float, float]]]:
    """Start points spread over the asphalt: the centre of the largest asphalt face of every k-th tile holding some, and
    the direction of its longest edge."""
    best: dict[tuple[int, int], Face] = {}
    for f in m.faces:
        if f.kind == "track":
            v = m.pts(f.v)[0]
            t = (math.floor(v[0] / 8), math.floor(v[2] / 8))
            if t not in best or _area(m.pts(f.v)) > _area(m.pts(best[t].v)):
                best[t] = f
    tiles = sorted(best)
    out = []
    for t in tiles[::max(1, len(tiles) // n)]:
        p = m.pts(best[t].v)
        c = (sum(v[0] for v in p) / len(p), sum(v[1] for v in p) / len(p), sum(v[2] for v in p) / len(p))
        a, b = max(((p[i], p[(i + 1) % len(p)]) for i in range(len(p))), key=lambda ab: math.dist(*ab))
        d = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
        out.append((c, ((b[0] - a[0]) / d, (b[2] - a[2]) / d)))
    return out


def laps(m: Mesh, bins: Bins, cells: Cells) -> list[list[Station]]:
    """The shortest laps from every seed that pass through at least COVER of the asphalt's tiles."""
    out = []
    for c, hd in seeds(m):
        guide = cells.lap(c, hd)
        st = follow(bins, guide) if guide else []
        if len(st) > 20 and coverage(bins, st) >= COVER:
            out.append(st)
    return out


def coverage(bins: Bins, st: list[Station]) -> float:
    """The share of the tiles holding asphalt that the walk passes through."""
    road = {t for t, ids in bins.at.items() if any(bins.m.faces[i].kind == "track" for i in ids)}
    return len(road & {(math.floor(c[1][0] / 8), math.floor(c[1][2] / 8)) for c in st}) / max(1, len(road))


def _area(p: list[Pt]) -> float:
    return abs(sum(p[i - 1][0] * p[i][2] - p[i][0] * p[i - 1][2] for i in range(len(p)))) / 2
