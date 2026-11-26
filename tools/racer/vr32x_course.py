"""LOCAL ONLY: a 32X course's racing line, checkpoints and start grid from its decoded 68000 tables (vr32x_import.py).

What the 68000 does, and how we map it (no data here; vr32x_tables / vr32x_find find the tables):
- **Course index.** A car's course index is its polygon's path point through the byte map; the lap check counts a lap when
  the index drops by more than 100 (it wrapped from N - 1 to 0), so the driving direction is increasing index and the line
  is where index 0's region starts. A region is centred on its path point, so our segment boundaries are the midpoints of
  consecutive path points, rotated by one: segment j runs from mid(P[j], P[j + 1]) to the next and holds point j + 1, the
  line is the start of segment N - 1, and the race rules' gates (a gate passes at the start of its segment) fall exactly
  on the 32X's.
- **Gates.** A polygon's surface bits 6-7 are its timing gate: 1 at index 0 (the line), 2 and 3 the two split points. Our
  checkpoints are gates 2 and 3 then the line.
- **Edges.** Each boundary's left / right vertex is as far across as the surface map stays road (class 1 or 4: the pits'
  class 13 is not the racing road), at our ground's height.
- **Grid.** 16 poses, the player first and at the back; we keep the player and the 7 cars just ahead of him. A car's
  segment is its region's (a car behind the line, in the last segments, starts at segment 0: the track position walks it
  back on the first tick, so its u starts below 0 and the first lap is a whole one, as on the 32X).
"""

from __future__ import annotations

import math

from racer import ktrk
from racer import vr32x_kinds as kinds
from racer import vr32x_surface as surf
from racer.vr32x_geom import Bins, Mesh
from racer.vr32x_tables import Course

LINE_ROAD = frozenset({1, 4})
STEP = 16  # world units a probe step across the road
REACH = 2560  # world units at most from the line to an edge
KEEP_AI = 7
W = surf.WORLD_PER_UNIT


class CourseError(ValueError):
    pass


def _y(bins: Bins, x: float, z: float, near: float) -> float:
    hs = [h for _, h in bins.under(x, z)]
    return min(hs, key=lambda h: abs(h - near)) if hs else near


def _height(p: surf.Poly | None, x: float, z: float) -> float:
    if p is None:
        raise CourseError(f"the line at ({x:.1f}, {z:.1f}) is on no surface polygon")
    return p.height(*kinds.uv(x, z)) / kinds.HEIGHT_PER_UNIT


def _reach(lay: surf.Layered, x: float, z: float, y: float, d: tuple[float, float]) -> float:
    s = 0
    while s < REACH:
        p = kinds.under(lay, x + d[0] * (s + STEP) / W, z + d[1] * (s + STEP) / W, y)
        if p is None or p.cls not in LINE_ROAD:
            break
        s += STEP
    return max(s, STEP) / W


def line(m: Mesh, bins: Bins, c: Course, lay: surf.Layered) -> list[dict[str, int]]:
    """The racing line's segments, their edge points appended to the mesh's vertices."""
    n, seg = len(c.path), []
    hint = [_height(p, x / W, z / W) for p, (x, z) in zip(lay.walk(c.path), c.path, strict=True)]  # the layer a car is on
    for j in range(n):
        (ax, az), (bx, bz) = c.path[j], c.path[(j + 1) % n]
        ln = math.hypot(bx - ax, bz - az) or 1.0
        hd = ((bx - ax) / ln, (bz - az) / ln)
        x, z = (ax + bx) / 2 / W, (az + bz) / 2 / W
        y = _y(bins, x, z, _height(kinds.under(lay, x, z, hint[(j + 1) % n]), x, z))
        ids = []
        for d in ((-hd[1], hd[0]), (hd[1], -hd[0])):  # left of the heading (x right, z forward), then right
            r = _reach(lay, x, z, y, d)
            ex, ez = x + d[0] * r, z + d[1] * r
            ids.append(len(m.verts))
            m.verts.append([ktrk.q(ex), ktrk.q(_y(bins, ex, ez, y)), ktrk.q(ez)])
        seg.append({"l": ids[0], "r": ids[1]})
    return seg


def gates(c: Course, lay: surf.Layered) -> list[int]:
    """Our checkpoints: the segments of gates 2 and 3, then the line (segment N - 1)."""
    found: dict[int, set[int]] = {}
    for sm in (lay.main, lay.upper):
        for i in range(surf.GRID * surf.GRID) if sm else ():
            for p in sm.cell(i // surf.GRID, i % surf.GRID):
                if p.gate and p.point < len(c.bmap):
                    found.setdefault(p.gate, set()).add(c.bmap[p.point])
    n = len(c.path)
    if sorted(found) != [1, 2, 3] or found[1] != {0}:
        raise CourseError(f"timing gates {sorted((g, sorted(v)) for g, v in found.items())}: want 1 at index 0, 2, 3")
    cps = [(min(found[g]) - 1) % n for g in (2, 3)] + [n - 1]
    if not cps[0] < cps[1] < cps[2]:
        raise CourseError(f"checkpoints {cps} out of lap order")
    return cps


def _region(c: Course, lay: surf.Layered, x: int, z: int) -> int:
    p = lay.find(x, z)
    if p is None or p.point >= len(c.bmap):
        raise CourseError(f"grid pose ({x}, {z}) is on no surface polygon")
    return c.bmap[p.point]


def grid(bins: Bins, c: Course, lay: surf.Layered, poses: list[tuple[int, int, int, int]]) -> list[ktrk.Doc]:
    """Our 8 cars: the player (pose 0) and the AI poses nearest ahead of him (15, 14, ..)."""
    n, out = len(c.path), []
    for x, y, z, _ in [poses[0]] + poses[:-KEEP_AI - 1:-1]:
        k = _region(c, lay, x, z)
        a, b = c.path[(k - 1) % n], c.path[(k + 1) % n]
        yaw = (math.atan2(b[0] - a[0], b[1] - a[1]) / (2 * math.pi)) % 1.0
        s = (k - 1) % n
        pos = [x / W, _y(bins, x / W, z / W, y / kinds.HEIGHT_PER_UNIT), z / W]
        out.append({"segment": s if s < n // 2 else 0, "pos": [ktrk.q(v) for v in pos],
                    "yaw_q16": round(yaw * 65536) & 0xFFFF})
    return out


def lap(c: Course) -> float:
    n = len(c.path)
    return sum(math.dist(c.path[i], c.path[(i + 1) % n]) for i in range(n)) / W


def clockwise(c: Course) -> bool:
    """Seen from above with +z up the page (the importer's sense check: freds72's three run clockwise)."""
    n = len(c.path)
    return sum(c.path[i - 1][0] * c.path[i][1] - c.path[i][0] * c.path[i - 1][1] for i in range(n)) < 0
