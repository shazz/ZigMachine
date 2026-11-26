"""LOCAL ONLY: a 32X car model's geometry as our car's (tools/racer/vr32x_car.py): Q7 vertices, the faces the cart can draw,
the winding the engine culls by, the axles at the wheels, a static painter's order. No data: rules only.

- **Units.** UNIT model units are one Q7 step (1/128 of our unit = one 68000 world unit). INFERRED, not read from the SH-2's
  transform: at 32 the class cars are about half a unit wide and a unit long, which fits the 32X's start grid and its roads
  as a real car fits its own; at 64 a car would be a quarter of its grid column. docs/ports/kestrel_racing/M5.md (car scale) has the measurements.
- **Axes.** The 32X car is x across, y up, z forward (its nose at +z): ours. The winding is checked, not assumed: if most
  faces' normals point INTO the model, every face is turned over (a mirrored x would do that).
- **Faces.** A quad that rounding to Q7 leaves non-planar or non-convex becomes two triangles; a face with no area left is
  dropped (counted in the report).
- **Order.** The cart draws a car's faces in the file's order under one depth key (carview.zig), so the importer sorts them
  once for the chase cameras: farthest first from an eye behind and above the car.
"""

from __future__ import annotations

import math
from collections.abc import Callable

from racer import carcheck
from racer.ktrk import Vec, cross, dot, sub, unit
from racer.vr32x_carrom import Model

UNIT = 32
XSPREAD = 16  # model units: how far a tyre side's corners may sit off one x
EYE = (0.0, 120.0, -400.0)  # Q7: the canonical chase eye (behind, above) the painter's order is sorted for
Face = tuple[list[int], int]  # vertex ids (into the doc's list), the 32X colour index


def q7(v: tuple[int, int, int], at: tuple[int, int, int] = (0, 0, 0)) -> tuple[int, int, int]:
    return (round((v[0] + at[0]) / UNIT), round((v[1] + at[1]) / UNIT), round((v[2] + at[2]) / UNIT))


def _pts(vs: list[tuple[int, int, int]], ids: list[int]) -> list[Vec]:
    return [tuple(float(c) for c in vs[i]) for i in ids]  # type: ignore[misc]  # [misc] 3 ints


def _area2(p: list[Vec]) -> float:
    n = (0.0, 0.0, 0.0)
    for i in range(1, len(p) - 1):
        c = cross(sub(p[i], p[0]), sub(p[i + 1], p[0]))
        n = (n[0] + c[0], n[1] + c[1], n[2] + c[2])
    return math.sqrt(dot(n, n))


def drawable(vs: list[tuple[int, int, int]], ids: list[int]) -> list[list[int]]:
    """`ids` as faces the cart can draw: itself, two triangles, or none (no area at Q7)."""
    ids = [i for k, i in enumerate(ids) if vs[i] != vs[ids[k - 1]]]  # a vertex rounded onto its neighbour
    if len(ids) < 3 or _area2(_pts(vs, ids)) < 1.0:
        return []
    if len(ids) == 3:
        return [ids]
    p = _pts(vs, ids)
    n = unit(cross(sub(p[1], p[0]), sub(p[2], p[0]))) if _area2(p[:3]) >= 1.0 else None
    if n and abs(dot(sub(p[3], p[0]), n)) <= carcheck.PLANAR_EPS and carcheck._convex(p, n):  # [private] the refusal's own rule
        return [ids]
    tris = [[ids[0], ids[1], ids[2]], [ids[0], ids[2], ids[3]]]
    return [t for t in tris if _area2(_pts(vs, t)) >= 1.0]


def outward(vs: list[tuple[int, int, int]], faces: list[list[int]]) -> bool:
    """True when most faces (by area) face away from the model's middle, as the engine's normal reads them."""
    mid = tuple(sum(v[k] for v in vs) / len(vs) for k in range(3))
    score = 0.0
    for ids in faces:
        p = _pts(vs, ids)
        n = cross(sub(p[-1], p[0]), sub(p[1], p[0]))  # ktrk.normal's order, unnormalised
        c = tuple(sum(q[k] for q in p) / len(p) for k in range(3))
        score += dot(n, sub(c, mid))  # type: ignore[arg-type]  # [arg-type] 3 floats
    return score >= 0


def wheels(far: Model) -> list[tuple[int, int, int]]:
    """The wheel centres (model units) in a far model, front axle first: its upright faces far out on the right, about one x
    (within XSPREAD), as long as they are tall (a tyre's side, not a body side)."""
    top = max(v[0] for v in far.verts)
    centres = []
    for p in far.polys:
        pts = [far.verts[i] for i in p.ids]
        xs, ys, zs = [q[0] for q in pts], [q[1] for q in pts], [q[2] for q in pts]
        if min(xs) > top / 2 and max(xs) - min(xs) <= XSPREAD and max(zs) - min(zs) < 3 * (max(ys) - min(ys)):
            centres.append((0, (min(ys) + max(ys)) // 2, (min(zs) + max(zs)) // 2))
    centres = sorted(set(centres), key=lambda c: -c[2])
    if len(centres) != 2:
        raise ValueError(f"far model: {len(centres)} wheel boxes on its right side, want 2 (a front and a rear axle)")
    return centres


def order(vs: list[tuple[int, int, int]], faces: list[Face]) -> list[Face]:
    """Farthest first from the canonical chase eye: the painter's order for every eye behind and above the car."""
    def far(f: Face) -> float:
        p = _pts(vs, f[0])
        c = tuple(sum(q[k] for q in p) / len(p) for k in range(3))
        return -math.dist(c, EYE)  # type: ignore[arg-type]  # [arg-type] 3 floats
    return sorted(faces, key=far)


def shadow(shape: Model) -> list[tuple[int, int, int]]:
    """Our one shadow quad (Q7, on the ground) around the 32X's flat shadow model, wound to face up."""
    xs, zs = [v[0] for v in shape.verts], [v[2] for v in shape.verts]
    x0, x1, z0, z1 = round(min(xs) / UNIT), round(max(xs) / UNIT), round(min(zs) / UNIT), round(max(zs) / UNIT)
    return [(x0, 1, z0), (x1, 1, z0), (x1, 1, z1), (x0, 1, z1)]  # 1 Q7 up, as the GT's; ktrk.normal: (last - first) x (second - first) = +y


def box(vs: list[tuple[int, int, int]], faces: list[Face], vid: Callable[[tuple[int, int, int]], int]) -> list[Face]:
    """A far model for a car that has none (the player's: never far from its own camera): its bounding box's top, sides and
    ends (Q7), in the colour that covers most of `faces`."""
    used: dict[int, float] = {}
    for ids, c in faces:
        used[c] = used.get(c, 0.0) + _area2(_pts(vs, ids))
    col = max(used, key=used.__getitem__)
    xs, ys, zs = ([v[k] for v in vs] for k in range(3))
    x0, x1, y1, z0, z1 = min(xs), max(xs), max(ys), min(zs), max(zs)
    quads = [[(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)],  # top (each wound as the shadow: ktrk.normal outward)
             [(x0, 0, z0), (x0, y1, z0), (x0, y1, z1), (x0, 0, z1)], [(x1, 0, z1), (x1, y1, z1), (x1, y1, z0), (x1, 0, z0)],
             [(x0, 0, z1), (x0, y1, z1), (x1, y1, z1), (x1, 0, z1)], [(x1, 0, z0), (x1, y1, z0), (x0, y1, z0), (x0, 0, z0)]]
    return [([vid(q) for q in quad], col) for quad in quads]
