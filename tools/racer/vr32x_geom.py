"""LOCAL ONLY: the 32X tile models (vr32x_rom.py) -> one welded mesh of `.ktrk.json` faces (tools/racer/vr32x_import.py).

What this decides, none of it read from the dump (the 32X draws by its own rules and keeps collision in other tables):
- units: 2048 model units to a tile, our tile is 8 units, so a unit is 256 model units (as freds72's Genesis export);
  the vertices weld across tiles on our 1/128 grid;
- a quad that is not flat within ktrk.PLANAR_EPS or not convex is split into its two triangles (the same surface);
- kind: a face whose normal points up (ny > GROUND_NY) is ground; a neutral grey one (the road, its lines, the pit
  apron) is asphalt ("track") up to a steeper slope (KERB_NY: kerbs, crowned decks); everything else is a prop,
  dual-sided when flags bit 6 is set
  (the Genesis layout's dual bit: trees and fences, a guess);
- decals: a ground face lying flat inside a larger one (lines, grid boxes, arrows) becomes its `inner` face, so the
  cart draws it after its parent instead of fighting it in the sort;
- borders: a ground face's edge is a wall when the ground does not continue past it at the same height.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from racer import ktrk
from racer.vr32x_rom import RGB, Tile

UNIT = 256
GROUND_NY = 0.6
KERB_NY = 0.3  # grey faces this steep are still asphalt (crowned decks, kerbs, the bridge's median)
DUAL_BIT = 0x40
STEP_Y = 0.35  # units: the ground continues across an edge when the next face is this close in height
PLANE_TOL = 0.03  # units: a decal lies on its parent's plane
Vec = ktrk.Vec


@dataclass
class Face:
    v: list[int]
    colour: int
    kind: str = "prop"
    dual: bool = False
    borders: list[int] = field(default_factory=list)
    inner: list[Face] = field(default_factory=list)
    parent: int = -1


class Mesh:
    def __init__(self) -> None:
        self.verts: list[list[int]] = []
        self._at: dict[tuple[int, int, int], int] = {}
        self.faces: list[Face] = []
        self.stats = {"split_quads": 0, "dropped_degenerate": 0}

    def vert(self, m: tuple[int, int, int]) -> int:
        key = tuple(ktrk.q(c / UNIT) for c in m)
        if key not in self._at:
            self._at[key] = len(self.verts)
            self.verts.append(list(key))
        return self._at[key]

    def pts(self, ids: list[int]) -> list[Vec]:
        return [(v[0] / ktrk.SCALE, v[1] / ktrk.SCALE, v[2] / ktrk.SCALE) for v in (self.verts[i] for i in ids)]


def _area2(p: list[Vec]) -> float:
    n = (0.0, 0.0, 0.0)
    for i in range(1, len(p) - 1):
        c = ktrk.cross(ktrk.sub(p[i], p[0]), ktrk.sub(p[i + 1], p[0]))
        n = (n[0] + c[0], n[1] + c[1], n[2] + c[2])
    return math.sqrt(ktrk.dot(n, n))


def _good_quad(p: list[Vec]) -> bool:
    n = ktrk.cross(ktrk.sub(p[2], p[0]), ktrk.sub(p[1], p[0]))
    ln = math.sqrt(ktrk.dot(n, n))
    if ln < 1e-9 or abs(ktrk.dot(n, ktrk.sub(p[3], p[0]))) / ln > ktrk.PLANAR_EPS:
        return False
    signs = {ktrk.dot(ktrk.cross(ktrk.sub(p[(i + 1) % 4], p[i]), ktrk.sub(p[(i + 2) % 4], p[(i + 1) % 4])), n) > 0
             for i in range(4)}
    return len(signs) == 1


def build(tiles: list[Tile], pal: list[RGB]) -> Mesh:
    m = Mesh()
    for t in tiles:
        ids = [m.vert(v) for v in t.verts]
        for p in t.polys:
            v = [ids[i] for i in p.ids]
            parts = [v] if len(v) == 3 or _good_quad(m.pts(v)) else [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]
            m.stats["split_quads"] += len(parts) - 1
            for part in parts:
                if len(set(part)) < 3 or _area2(m.pts(part)) < 1e-3:  # budget.py's "no area" (|n|^2 < 1e-6)
                    m.stats["dropped_degenerate"] += 1
                    continue
                m.faces.append(_classify(m, Face(part, p.colour, dual=bool(p.flags & DUAL_BIT)), pal))
    return m


def place(m: Mesh, polys: list[tuple[list[Vec], int]]) -> int:
    """R82 32X look: the objects the 68000 places outside the tile maps (vr32x_objects.py: gantries, landmarks), world
    polygons in our units, as dual-sided props (never ground: nothing drives on a banner). Returns the faces added."""
    n = 0
    for pts, colour in polys:
        v = []
        for p in pts:
            key = tuple(ktrk.q(c) for c in p)
            if key not in m._at:
                m._at[key] = len(m.verts)
                m.verts.append(list(key))
            v.append(m._at[key])
        parts = [v] if len(v) == 3 or _good_quad(m.pts(v)) else [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]
        for part in parts:
            if len(set(part)) == len(part) and _area2(m.pts(part)) >= 1e-3:
                m.faces.append(Face(part, colour, kind="prop", dual=True))
                n += 1
    return n


def _classify(m: Mesh, f: Face, pal: list[RGB]) -> Face:
    ny = ktrk.normal(m.pts(f.v))[1]
    r, g, b = pal[f.colour]
    if ny > KERB_NY and r == g == b and f.colour != 0:
        f.kind, f.dual = "track", False
    elif ny > GROUND_NY:
        f.kind, f.dual = "ground", False
    return f


class Bins:
    """Face indices per tile (ktrk.tile_faces' binning) for the ground kinds."""

    def __init__(self, m: Mesh) -> None:
        self.m, self.at, self.p = m, {}, {}
        for i, f in enumerate(m.faces):
            if f.kind in ktrk.GROUND_KINDS:
                p = self.p[i] = m.pts(f.v)
                for tz in range(_t(min(v[2] for v in p)), _t(max(v[2] for v in p)) + 1):
                    for tx in range(_t(min(v[0] for v in p)), _t(max(v[0] for v in p)) + 1):
                        self.at.setdefault((tx, tz), []).append(i)

    def under(self, x: float, z: float, kinds: tuple[str, ...] = ktrk.GROUND_KINDS) -> list[tuple[int, float]]:
        """(face, height) of every ground face of these kinds over the point (x, z)."""
        out = []
        for i in self.at.get((_t(x), _t(z)), []):
            p = self.p[i]
            if self.m.faces[i].kind in kinds and ktrk.inside_by(p, (x, 0.0, z), 1e-4):
                out.append((i, ktrk.plane_y(p, x, z)))
        return out


def _t(c: float) -> int:
    return math.floor(c / ktrk.TILE)


def decals(m: Mesh, bins: Bins) -> int:
    """Attach every ground face lying flat inside a larger ground face to the largest one (its root); returns the count."""
    area = [_area2(m.pts(f.v)) for f in m.faces]
    for i, f in enumerate(m.faces):
        if f.kind not in ktrk.GROUND_KINDS:
            continue
        p = m.pts(f.v)
        c = ktrk.centroid(p)
        best = -1
        for j, y in bins.under(c[0], c[2]):
            g = m.pts(m.faces[j].v)
            if j == i or area[j] <= area[i] or (best >= 0 and area[j] <= area[best]) or abs(y - c[1]) > PLANE_TOL:
                continue
            if all(ktrk.inside_by(g, v, ktrk.DECAL_TOL) and abs(ktrk.plane_y(g, v[0], v[2]) - v[1]) <= PLANE_TOL for v in p):
                best = j
        f.parent = best
    for f in m.faces:
        while f.parent >= 0 and m.faces[f.parent].parent >= 0:
            f.parent = m.faces[f.parent].parent
    kids = [i for i, f in enumerate(m.faces) if f.parent >= 0]
    for i in sorted(kids, key=lambda k: -area[k]):
        m.faces[m.faces[i].parent].inner.append(m.faces[i])
    return len(kids)


def borders(m: Mesh, bins: Bins) -> int:
    """Mark the edges past which no ground face continues at the same height (walls); returns the count."""
    n = 0
    for f in m.faces:
        if f.kind not in ktrk.GROUND_KINDS or f.parent >= 0:
            continue
        p = m.pts(f.v)
        for e in range(len(p)):
            a, b = p[e], p[(e + 1) % len(p)]
            ln = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
            out = ((b[2] - a[2]) / ln * 0.05, (a[0] - b[0]) / ln * 0.05)  # minus the inside normal (a.z - b.z, b.x - a.x)
            x, z, y = (a[0] + b[0]) / 2 + out[0], (a[2] + b[2]) / 2 + out[1], (a[1] + b[1]) / 2
            if not any(abs(h - y) < STEP_Y for _, h in bins.under(x, z)):
                f.borders.append(e)
                n += 1
    return n
