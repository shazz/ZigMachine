"""LOCAL ONLY: finds each 32X course's surface map pair(s) and start grid by shape (vr32x_tables.py has the rules).

No data, no offsets: candidates are runs of 68000 pointers / poses anywhere in the dump, accepted only when they agree
with the course table (the path's points land in polygons that map back to their own course index; the grid's 16 poses
all lie on road).
"""

from __future__ import annotations

import itertools
import math
import struct

from racer import vr32x_surface as surf
from racer.vr32x_tables import BANK, BANKED, GRID_CARS, Course, Rom, TableError, courses

GAP = (64, 512)  # world units between consecutive grid slots (a car is ~150 long)
MATCH = 0.95  # share of the path's points a map pair must place on their own course index


def _agrees(c: Course, poly: surf.Poly | None, i: int) -> bool:
    if poly is None or poly.point >= len(c.bmap):
        return False
    d = (c.bmap[poly.point] - i) % len(c.path)
    return d in (0, 1, len(c.path) - 1)


def score(c: Course, polys: list[surf.Poly | None]) -> float:
    return sum(_agrees(c, p, i) for i, p in enumerate(polys)) / max(1, len(polys))


def _pair_ok(rom: Rom, m: int, b: int) -> bool:
    return BANKED <= m < BANKED + BANK and BANKED <= b < BANKED + BANK and rom.ok(m + 2 * 4095) and rom.ok(b)


def _try(rom: Rom, c: Course, m: int, b: int) -> float:
    try:
        sm = surf.SurfaceMap(rom.data, rom.at, m, b)
        if score(c, [sm.find(x, z) for x, z in c.path[:16]]) < MATCH:  # a quick reject
            return 0.0
        return score(c, [sm.find(x, z) for x, z in c.path])
    except (surf.SurfaceError, TableError, struct.error):
        return 0.0


def surfaces(rom: Rom, cs: list[Course]) -> tuple[int, list[tuple[int, int]]]:
    """(table address, the courses' (map, base)): the first run of pointer pairs, one per course, each agreeing."""
    n = len(cs)
    for at in range(0, len(rom.data) - 8 * n, 4):
        pairs = [struct.unpack_from(">2I", rom.data, at + 8 * k) for k in range(n)]
        if not all(_pair_ok(rom, m, b) for m, b in pairs):
            continue
        if all(_try(rom, c, m, b) >= MATCH for c, (m, b) in zip(cs, pairs, strict=True)):
            return at, pairs
    raise TableError("no surface map table found")


def upper(rom: Rom, after: int, cs: list[Course], main: list[tuple[int, int]]) -> list[tuple[int, int] | None]:
    """The upper-deck pairs: the next run of the same shape after the main table, zero but where a course has a crossing
    (its path, walked with the layer switch, then agrees better than the main map alone)."""
    n = len(cs)
    for at in range(after + 8 * n, min(len(rom.data) - 8 * n, after + 8 * n + 1024), 4):
        pairs = [struct.unpack_from(">2I", rom.data, at + 8 * k) for k in range(n)]
        used = [p for p in pairs if p != (0, 0)]
        if not used or not all(_pair_ok(rom, m, b) for m, b in used) or any(p in main for p in used):
            continue
        out = [None if p == (0, 0) else p for p in pairs]
        if all(p is None or _layered(rom, c, mp, p) for c, mp, p in zip(cs, main, out, strict=True)):
            return out
    return [None] * n


def _layered(rom: Rom, c: Course, main: tuple[int, int], up: tuple[int, int]) -> bool:
    lay = surf.Layered(surf.SurfaceMap(rom.data, rom.at, *main), surf.SurfaceMap(rom.data, rom.at, *up))
    one = surf.Layered(surf.SurfaceMap(rom.data, rom.at, *main))
    return score(c, lay.walk(c.path)) > score(c, one.walk(c.path))


def _rows(poses: list[tuple[int, ...]]) -> bool:
    """A grid's shape: the AI cars one after the other a car length or two apart, the player just behind the last, all one heading."""
    gaps = [math.dist((a[0], a[2]), (b[0], b[2])) for a, b in itertools.pairwise(poses[1:])]
    if len({p[3] for p in poses}) != 1:  # the cars start parallel: one heading
        return False
    return all(GAP[0] <= g <= GAP[1] for g in gaps) and math.dist((poses[0][0], poses[0][2]), (poses[-1][0], poses[-1][2])) <= GAP[1]


def _on_road(layer: surf.Layered, p: tuple[int, ...]) -> bool:
    """On a road polygon (the height word is not checked: it is copied between courses in the tables)."""
    q = layer.find(p[0], p[2])
    return q is not None and q.cls in surf.ROAD


def grid(rom: Rom, c: Course, layer: surf.Layered) -> list[tuple[int, int, int, int]]:
    """The first run of 16 poses (2-byte aligned) in a grid's shape, all on this course's road."""
    xs, zs = [p[0] for p in c.path], [p[1] for p in c.path]
    box = (min(xs) - 1024, max(xs) + 1024, min(zs) - 1024, max(zs) + 1024)
    d = rom.data
    for at in range(0, len(d) - 8 * GRID_CARS, 2):
        x, _, z, _ = struct.unpack_from(">4h", d, at)
        if not (box[0] <= x <= box[1] and box[2] <= z <= box[3]):
            continue
        poses = [struct.unpack_from(">4h", d, at + 8 * k) for k in range(GRID_CARS)]
        if not _rows(poses):
            continue
        if all(_on_road(layer, p) for p in poses):
            return poses  # type: ignore[return-value]  # [tuple-size] 4 shorts a pose
    raise TableError("no start grid found")


def tracks(data: bytes, count: int) -> list[tuple[Course, surf.Layered, list[tuple[int, int, int, int]]]]:
    """Every course's table entry, its surface (both layers) and its start grid, each found and cross-checked."""
    rom, cs = courses(data, count)
    at, main = surfaces(rom, cs)
    ups = upper(rom, at, cs, main)
    out = []
    for c, mp, up in zip(cs, main, ups, strict=True):
        lay = surf.Layered(surf.SurfaceMap(data, rom.at, *mp), surf.SurfaceMap(data, rom.at, *up) if up else None)
        if score(c, lay.walk(c.path)) < 1.0:
            raise TableError(f"the path's points do not all land on their own course index ({score(c, lay.walk(c.path)):.3f})")
        out.append((c, lay, grid(rom, c, lay)))
    return out
