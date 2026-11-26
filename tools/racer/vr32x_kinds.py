"""LOCAL ONLY: each ground face's kind from the 32X's own surface map (vr32x_import.py, decoded mode).

A ground face is sampled at its centroid and halfway to each corner. Each sample votes with the surface polygon under it
(where a crossing has two layers, the one whose plane is nearest the face), if the face lies on that polygon's plane:
road -> "track" (full speed), off-road -> "ground" (our off-asphalt limit); no polygon, a solid one, or a face off the plane
(a rock or a deck over the road) -> "prop": not drivable, so the car never finds it and vr32x_geom.borders() turns the
edges of the drivable faces next to it into walls, which is what the 32X's walls are (the edge of its polygons' union).
The majority wins; a face whose samples disagree is counted as mixed in the report. Decals keep their parent's kind.
"""

from __future__ import annotations

from collections import Counter

from racer import ktrk
from racer import vr32x_surface as surf
from racer.vr32x_geom import Mesh

HEIGHT_PER_UNIT = 2048  # the 68000's plane heights to our units (the path's polygons sit on our road's height)
HEIGHT_TOL = 0.25  # our units: a face this far off the surface's plane is not the surface (a rock over the road)
W = surf.WORLD_PER_UNIT


def under(lay: surf.Layered, x: float, z: float, y: float | None = None) -> surf.Poly | None:
    """The surface polygon under our (x, z): the one of the two layers whose height is nearest y, when both have one."""
    wx, wz = round(x * W), round(z * W)
    got = [p for p in (lay.main.find(wx, wz), lay.upper.find(wx, wz) if lay.upper else None) if p is not None]
    if not got:
        return None
    if y is None or len(got) == 1:
        return got[0]
    return min(got, key=lambda p: abs(p.height(*uv(x, z)) / HEIGHT_PER_UNIT - y))


def uv(x: float, z: float) -> tuple[int, int]:
    """The cell-local coordinates (doubled) of our (x, z), as the 68000's plane and edge tests take them."""
    return ((round(x * W) + surf.ORIGIN) % surf.CELL) * 2, ((round(z * W) + surf.ORIGIN) % surf.CELL) * 2


def vote(lay: surf.Layered, pts: list[ktrk.Vec]) -> tuple[str, bool]:
    c = ktrk.centroid(pts)
    samples = [c] + [tuple((a + b) / 2 for a, b in zip(c, p, strict=True)) for p in pts]
    kinds = Counter(_kind(under(lay, s[0], s[2], s[1]), s) for s in samples)
    best = kinds.most_common(1)[0][0]
    return best, len(kinds) > 1


def _kind(p: surf.Poly | None, at: ktrk.Vec) -> str:
    if p is None or abs(p.height(*uv(at[0], at[2])) / HEIGHT_PER_UNIT - at[1]) > HEIGHT_TOL:
        return "prop"  # no surface here, or the face is not at its height (a rock or a deck over the road)
    if p.cls in surf.ROAD:
        return "track"
    return "ground" if p.cls in surf.OFFROAD else "prop"


def classify(m: Mesh, lay: surf.Layered) -> dict[str, int]:
    """Re-kind every ground face (roots; their decals follow) from the surface map; returns the counts."""
    out: Counter[str] = Counter()
    for f in m.faces:
        if f.kind not in ktrk.GROUND_KINDS or f.parent >= 0:
            continue
        f.kind, mixed = vote(lay, m.pts(f.v))
        out[f.kind] += 1
        out["mixed"] += mixed
    for f in m.faces:
        if f.parent >= 0:
            f.kind = m.faces[f.parent].kind
    return dict(out)
