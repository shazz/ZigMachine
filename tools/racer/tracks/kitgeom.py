"""Shared geometry for the generated Track Kit scenes after Salt Flats (R82 M5 step 2: Neon Docks, Glacier Pass), no bpy.

A closed centre-line spline through control points, stations equally spaced in arc length, a road strip that can climb and
bank (each station's height and cross slope), its walls, embankments down to the lake level, decals on the road and boxes.
Everything is in Blender axes (Z up) with the Track Kit's vertex groups (docs/ports/kestrel_racing/M5.md).
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass

from salt_flats_geom import Mesh

Station = tuple[float, float, float, float]  # x, y, left_x, left_y


def spline(points: list[tuple[float, float]]) -> Callable[[float], tuple[float, float]]:
    """A closed Catmull-Rom curve through `points`, t in [0, 1)."""
    n = len(points)

    def at(t: float) -> tuple[float, float]:
        u = (t % 1.0) * n
        i = int(u)
        f = u - i
        p0, p1, p2, p3 = (points[(i + k) % n] for k in (-1, 0, 1, 2))

        def cr(a: float, b: float, c: float, d: float) -> float:
            return 0.5 * (2 * b + (c - a) * f + (2 * a - 5 * b + 4 * c - d) * f * f + (3 * b - a - 3 * c + d) * f ** 3)

        return cr(p0[0], p1[0], p2[0], p3[0]), cr(p0[1], p1[1], p2[1], p3[1])

    return at


def stations(curve: Callable[[float], tuple[float, float]], n: int, steps: int = 40000) -> list[Station]:
    pts = [curve(k / steps) for k in range(steps + 1)]
    cum = [0.0]
    for a, b in zip(pts, pts[1:], strict=False):
        cum.append(cum[-1] + math.dist(a, b))
    out, k = [], 0
    for i in range(n):
        want = cum[-1] * i / n
        while cum[k + 1] < want:
            k += 1
        out.append(pts[k])
    res = []
    for i, (x, y) in enumerate(out):
        (nx, ny), (px, py) = out[(i + 1) % n], out[i - 1]
        d = math.hypot(nx - px, ny - py)
        res.append((x, y, -(ny - py) / d, (nx - px) / d))
    return res


@dataclass(frozen=True)
class Road:
    half: float
    shoulder: float
    wall_h: float
    asphalt: tuple[str, str]  # alternating every 2 segments (authored, not lit)
    shoulder_mat: str
    barrier: tuple[str, str]  # alternating every 3 segments
    checkpoints: int = 4


def road(m: Mesh, st: list[Station], spec: Road, z: list[float], bank: list[float]) -> list[list[int]]:
    """The strip: per station 6 vertices (outer left, L, R, outer right, the two wall tops); z rises, bank tilts it (z + o * bank)."""
    n, rows = len(st), []
    for i, (x, y, lx, ly) in enumerate(st):
        at = lambda o, up=0.0, i=i: (x + o * lx, y + o * ly, z[i] + o * bank[i] + up)  # noqa: E731
        g = ["GROUND_FACE"]
        start = ["LINE_START"] if i == 0 else []
        every = n // spec.checkpoints
        cp = [f"CHECKPT_{(i // every) or spec.checkpoints}"] if i % every == 0 and i // every < spec.checkpoints else []
        edge = spec.half + spec.shoulder
        rows.append([m.v(*at(edge), *g, "BORDER1"), m.v(*at(spec.half), *g, "TRACK_FACE", "TRACK_L", *start, *cp),
                     m.v(*at(-spec.half), *g, "TRACK_FACE", "TRACK_R"), m.v(*at(-edge), *g, "BORDER1"),
                     m.v(*at(edge, spec.wall_h)), m.v(*at(-edge, spec.wall_h))])
    for i in range(n):
        a, b = rows[i], rows[(i + 1) % n]
        m.f([a[1], a[2], b[2], b[1]], spec.asphalt[(i // 2) % 2])
        m.f([a[0], a[1], b[1], b[0]], spec.shoulder_mat)
        m.f([a[2], a[3], b[3], b[2]], spec.shoulder_mat)
        bar = spec.barrier[(i // 3) % 2]
        m.f([a[0], b[0], b[4], a[4]], bar)
        m.f([a[3], a[5], b[5], b[3]], bar)
    return rows


def embank(m: Mesh, st: list[Station], spec: Road, z: list[float], bank: list[float], mat: str, slope: float = 2.0) -> None:
    """Where the road is above the lake, a bank from the outside of each wall down to z = 0 (scenery, both sides)."""
    edge = spec.half + spec.shoulder
    n = len(st)

    def foot(i: int, side: float) -> tuple[list[float], list[float]]:
        x, y, lx, ly = st[i]
        h = z[i] + side * edge * bank[i]
        top = [x + side * edge * lx, y + side * edge * ly, h]
        out = side * (edge + slope * max(h, 0.0))
        return top, [x + out * lx, y + out * ly, 0.0]

    for i in range(n):
        j = (i + 1) % n
        if max(z[i], z[j]) < 0.3:
            continue
        for side in (1.0, -1.0):
            (ta, fa), (tb, fb) = foot(i, side), foot(j, side)
            ids = [m.v(*p, "PROP_FACE") for p in (ta, fa, fb, tb)]
            m.f(ids if side > 0 else ids[::-1], mat)


def decal(m: Mesh, st: list[Station], spec: Road, z: list[float], bank: list[float], i: int,
          u: tuple[float, float], t: tuple[float, float], mat: str) -> None:
    """A DETAIL face on road segment i: u along (0 -> 1 = station i -> i+1), t across (0 left edge -> 1 right edge)."""
    n = len(st)
    a, b, j = st[i], st[(i + 1) % n], (i + 1) % n
    ids = []
    for uu, tt in ((u[0], t[1]), (u[0], t[0]), (u[1], t[0]), (u[1], t[1])):
        o = spec.half - 2 * spec.half * tt
        pa = (a[0] + o * a[2], a[1] + o * a[3], z[i] + o * bank[i])
        pb = (b[0] + o * b[2], b[1] + o * b[3], z[j] + o * bank[j])
        ids.append(m.v(*(pa[k] + (pb[k] - pa[k]) * uu for k in range(3)), "DETAIL_FACE"))
    m.f(ids, mat)


def box(m: Mesh, c: tuple[float, float, float], size: tuple[float, float, float], rot: float, side: str, top: str) -> None:
    """An upright box on z = c[2]: footprint size[0] x size[1] turned by rot, height size[2] (4 sides + the top)."""
    cs, sn = math.cos(rot), math.sin(rot)
    w, d, h = size
    corner = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
    lo = [m.v(c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2], "PROP_FACE") for x, y in corner]
    hi = [m.v(c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + h, "PROP_FACE") for x, y in corner]
    for k in range(4):
        m.f([lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]], side)
    m.f(hi, top)


def spire(m: Mesh, x: float, y: float, z0: float, r: float, h: float, mat: str) -> None:
    """A four-sided pyramid (a pine, a pylon)."""
    base = [m.v(x + dx * r, y + dy * r, z0, "PROP_FACE") for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    tip = m.v(x, y, z0 + h, "PROP_FACE")
    for k in range(4):
        m.f([base[k], base[(k + 1) % 4], tip], mat)


def turn(st: list[Station], i: int) -> float:
    """> 0: the line turns left at station i (its plan-view cross product)."""
    a, b, c = st[i - 1], st[i], st[(i + 1) % len(st)]
    return (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])


def far_from(st: list[Station], x: float, y: float, clear: float) -> bool:
    """True when (x, y) is at least `clear` units from every station (a prop off the road)."""
    return all(math.hypot(x - s[0], y - s[1]) >= clear for s in st)
