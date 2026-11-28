"""Bad Apple polygons, the offline half (cart 168): a 0/1 picture to closed contours, then Douglas-Peucker.

Contours are traced along the PIXEL BOUNDARIES (the cracks between a foreground and a background pixel: marching
squares on the pixel-corner lattice), so every vertex is an integer corner (x 0..320, y 0..200) and the
unsimplified contours fill back to the exact picture under the even-odd, pixel-centre rule (poly.raster). Each
contour runs with the foreground on its right; at a saddle (two diagonal foreground pixels) it turns right, so
diagonal neighbours are separate contours. Douglas-Peucker then drops every vertex within `eps` pixels of the
chord (integer arithmetic only: the test is 16 * cross^2 <= (4 eps)^2 * len^2).
"""
from __future__ import annotations

from badapple import stream

W, H = stream.WIDTH, stream.HEIGHT
Point = tuple[int, int]
Contour = list[Point]
_RIGHT_OF = {(1, 0): (0, 1), (0, 1): (-1, 0), (-1, 0): (0, -1), (0, -1): (1, 0)}  # turning right in screen space


def _runs(px: bytes, y: int, fg: int) -> list[int]:
    """The x of every change along row y (outside the picture is background), as a sorted list."""
    if not 0 <= y < H:
        return []
    row = px[y * W:(y + 1) * W]
    out, cur = [], 0
    for x, v in enumerate(row):
        f = 1 if v == fg else 0
        if f != cur:
            out.append(x)
            cur = f
    if cur:
        out.append(W)
    return out


def _value_at(runs: list[int], x: int) -> int:
    """Foreground (1) or not at pixel x, from a row's change list."""
    n = 0
    for t in runs:
        if t > x:
            break
        n += 1
    return n & 1


def _edges(px: bytes, fg: int) -> dict[Point, list[Point]]:
    """Every boundary edge, start corner -> end corners; long horizontal edges, unit vertical ones."""
    out: dict[Point, list[Point]] = {}
    rows = [_runs(px, y, fg) for y in range(H)]
    for y, runs in enumerate(rows):
        for i, x in enumerate(runs):  # even i: background|foreground (going up), odd: foreground|background (down)
            a, b = ((x, y + 1), (x, y)) if i % 2 == 0 else ((x, y), (x, y + 1))
            out.setdefault(a, []).append(b)
    for y in range(H + 1):
        above, below = rows[y - 1] if y > 0 else [], rows[y] if y < H else []
        cuts = sorted({0, W, *above, *below})
        for x0, x1 in zip(cuts, cuts[1:], strict=False):
            u, d = _value_at(above, x0), _value_at(below, x0)
            if u == d:
                continue
            a, b = ((x0, y), (x1, y)) if d else ((x1, y), (x0, y))  # foreground below: going right
            out.setdefault(a, []).append(b)
    return out


def _direction(a: Point, b: Point) -> Point:
    return ((b[0] > a[0]) - (b[0] < a[0]), (b[1] > a[1]) - (b[1] < a[1]))


def trace(px: bytes, fg: int) -> list[Contour]:
    """The closed contours of the `fg` pixels, each from its smallest (y, x) corner, sorted by that corner."""
    edges = _edges(px, fg)
    loops = []
    for start in sorted(edges, key=lambda p: (p[1], p[0])):
        while edges.get(start):
            loop, cur, d = [start], start, None
            while True:
                outs = edges[cur]
                nxt = outs[0]
                if len(outs) > 1 and d is not None:  # a saddle: turn right
                    want = _RIGHT_OF[d]
                    nxt = next(o for o in outs if _direction(cur, o) == want)
                outs.remove(nxt)
                d, cur = _direction(cur, nxt), nxt
                if cur == start:
                    break
                loop.append(cur)
            loops.append(_canonical(_drop_collinear(loop)))
    return sorted(loops, key=lambda c: (c[0][1], c[0][0]))


def _drop_collinear(loop: Contour) -> Contour:
    n = len(loop)
    return [p for i, p in enumerate(loop) if _direction(loop[i - 1], p) != _direction(p, loop[(i + 1) % n])]


def _canonical(loop: Contour) -> Contour:
    k = min(range(len(loop)), key=lambda i: (loop[i][1], loop[i][0]))
    return loop[k:] + loop[:k]


def _far(a: Point, b: Point, p: Point, eps_q: int) -> int:
    """How far p is off the chord a-b, scaled so that > 0 means beyond eps (eps_q = 4 eps)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    cross = dx * (p[1] - a[1]) - dy * (p[0] - a[0])
    len2 = dx * dx + dy * dy
    if len2 == 0:
        d2 = (p[0] - a[0]) ** 2 + (p[1] - a[1]) ** 2  # a closed chord: the distance to a itself
        return 16 * d2 - eps_q * eps_q
    return 16 * cross * cross - eps_q * eps_q * len2


def _dp(pts: Contour, eps_q: int) -> Contour:
    """Douglas-Peucker of an open polyline, keeping both ends (iterative: contours can be long)."""
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    todo = [(0, len(pts) - 1)]
    while todo:
        i, j = todo.pop()
        best, k = 0, -1
        for m in range(i + 1, j):
            f = _far(pts[i], pts[j], pts[m], eps_q)
            if f > best:
                best, k = f, m
        if k >= 0:
            keep[k] = True
            todo += [(i, k), (k, j)]
    return [p for p, kp in zip(pts, keep, strict=True) if kp]


def simplify(loop: Contour, eps_q: int) -> Contour:
    """A closed contour simplified, split at its first vertex and the vertex farthest from it; [] if < 3 remain."""
    if eps_q == 0 or len(loop) <= 3:
        return loop
    a = loop[0]
    k = max(range(len(loop)), key=lambda i: (loop[i][0] - a[0]) ** 2 + (loop[i][1] - a[1]) ** 2)
    out = _dp(loop[:k + 1], eps_q)[:-1] + _dp([*loop[k:], a], eps_q)[:-1]
    return out if len(out) >= 3 else []
