"""LOCAL ONLY: the asphalt of an imported 32X track as a graph of small cells, for the racing-line walk's forks
(tools/racer/vr32x_line.py): which way out of a fork can still reach the start without going back the way it came.

A node is a CELL x CELL square of the XZ plane at one asphalt height (a crossing has two); neighbours (8-connected) join
when their heights are within CLIMB, so an overpass and the road below stay apart where they cross.
"""

from __future__ import annotations

import math
from collections import deque

from racer.vr32x_geom import Bins

CELL = 0.25  # units (a road's painted median is ~0.3 wide: a bigger cell steps over it)
CLIMB = 0.6  # units between neighbouring cells
Node = tuple[int, int, int]  # (cell x, cell z, height layer index)
Pt = tuple[float, float, float]


class Cells:
    def __init__(self, bins: Bins) -> None:
        self.h: dict[tuple[int, int], list[float]] = {}
        for (tx, tz), ids in bins.at.items():
            if not any(bins.m.faces[i].kind == "track" for i in ids):
                continue
            n = int(8 / CELL)
            for cz in range(tz * n, tz * n + n):
                for cx in range(tx * n, tx * n + n):
                    hs: list[float] = []
                    for _, h in bins.under((cx + 0.5) * CELL, (cz + 0.5) * CELL, ("track",)):
                        if all(abs(h - o) > 0.3 for o in hs):
                            hs.append(h)
                    if hs:
                        self.h[(cx, cz)] = sorted(hs)

    def node(self, p: Pt) -> Node | None:
        c = (math.floor(p[0] / CELL), math.floor(p[2] / CELL))
        hs = self.h.get(c)
        if not hs:
            return None
        k = min(range(len(hs)), key=lambda i: abs(hs[i] - p[1]))
        return (c[0], c[1], k) if abs(hs[k] - p[1]) < 1.0 else None

    def _next(self, n: Node) -> list[Node]:
        y = self.h[(n[0], n[1])][n[2]]
        out = []
        for dz in (-1, 0, 1):
            for dx in (-1, 0, 1):
                hs = self.h.get((n[0] + dx, n[1] + dz))
                if (dx or dz) and hs:
                    out += [(n[0] + dx, n[1] + dz, k) for k, h in enumerate(hs) if abs(h - y) < CLIMB]
        return out

    def open_way(self, a: Pt, goal: Pt, banned: set[Node], limit: int = int(600 / CELL ** 2)) -> bool:
        """Whether the asphalt from a, avoiding `banned` (a cut across the road just behind the walker), reaches goal or
        at least `limit` cells (600 square units: more than a stub or a dead-end apron)."""
        s, g = self.node(a), self.node(goal)
        if s is None or g is None:
            return False
        seen, todo = {s} | banned, deque([s])
        while todo:
            if len(seen) - len(banned) > limit:
                return True
            n = todo.popleft()
            if abs(n[0] - g[0]) <= 1 and abs(n[1] - g[1]) <= 1 and n[2] == g[2]:
                return True
            for m in self._next(n):
                if m not in seen:
                    seen.add(m)
                    todo.append(m)
        return False

    def band(self, pts: list[Pt], radius: float) -> set[Node]:
        """The cells within `radius` of these points, at their heights: a cut across the road behind."""
        out: set[Node] = set()
        r = math.ceil(radius / CELL)
        for p in pts:
            n = self.node(p)
            if n is None:
                continue
            y = self.h[(n[0], n[1])][n[2]]
            for dz in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    for k, h in enumerate(self.h.get((n[0] + dx, n[1] + dz), [])):
                        if abs(h - y) < CLIMB:
                            out.add((n[0] + dx, n[1] + dz, k))
        return out

    def lap(self, s: Pt, hd: tuple[float, float]) -> list[Pt]:
        """The shortest way round from just ahead of s back to just behind it, through a slab cut across the road at s
        (1.5 units thick, 6 units each side): the lap, as cell centres at their heights. Empty when there is none."""
        n0 = self.node(s)
        if n0 is None:
            return []
        y0, cut = self.h[(n0[0], n0[1])][n0[2]], set()
        r = math.ceil(6 / CELL)
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                along = (dx * hd[0] + dz * hd[1]) * CELL
                for k, h in enumerate(self.h.get((n0[0] + dx, n0[1] + dz), [])):
                    if abs(along) <= 0.75 and abs(h - y0) < 1.0:
                        cut.add((n0[0] + dx, n0[1] + dz, k))
        src = self.node((s[0] + hd[0] * 1.25, y0, s[2] + hd[1] * 1.25))
        goal = self.node((s[0] - hd[0] * 1.25, y0, s[2] - hd[1] * 1.25))
        if src is None or goal is None:
            return []
        prev: dict[Node, Node | None] = {src: None}
        todo = deque([src])
        while todo and goal not in prev:
            n = todo.popleft()
            for m in self._next(n):
                if m not in prev and m not in cut:
                    prev[m] = n
                    todo.append(m)
        if goal not in prev:
            return []
        path: list[Pt] = []
        at: Node | None = goal
        while at is not None:
            path.append(((at[0] + 0.5) * CELL, self.h[(at[0], at[1])][at[2]], (at[1] + 0.5) * CELL))
            at = prev[at]
        return path[::-1]
