"""Glacier Pass' geometry (R82 M5 step 2), no bpy: an alpine road in snow under an overcast sky. Original content (ours).

The loop climbs a zigzag of two hairpins, sweeps round a banked bowl, runs over a crest into a short rock tunnel and comes
down the long valley side to the start. The road's height and bank are per station (kitgeom.road), snow banks run from the
walls down to the valley floor (the far ground), pines and rocks stand off the road. glacier_pass_build.py makes the scene.
"""

from __future__ import annotations

import math

from kitgeom import Road, Station, box, decal, embank, far_from, road, spire, spline, stations, turn
from salt_flats_geom import Mesh

POINTS = [(-80, -92), (0, -94), (60, -92), (84, -84), (91, -72), (84, -58), (60, -52), (0, -52), (-40, -52),
          (-70, -45), (-78, -32), (-70, -19), (-40, -12), (20, -12), (62, -6), (92, 18), (100, 50), (86, 82),
          (50, 98), (0, 100), (-50, 98), (-84, 86), (-104, 56), (-108, 0), (-107, -50), (-102, -78)]
N = 236
SPEC = Road(half=5.0, shoulder=2.0, wall_h=0.6, asphalt=("asphalt_a", "asphalt_b"), shoulder_mat="verge",
            barrier=("barrier_a", "barrier_b"))
PALETTE = {
    "snow": (214, 220, 230), "verge": (176, 182, 192), "asphalt_a": (96, 98, 106), "asphalt_b": (82, 84, 92),
    "barrier_a": (178, 52, 48), "barrier_b": (206, 208, 214), "paint": (200, 202, 206), "paint_start": (206, 176, 64),
    "kerb_a": (178, 52, 48), "kerb_b": (206, 208, 214), "bank": (196, 202, 214), "rock": (104, 106, 114),
    "rock_top": (186, 192, 204), "pine": (40, 70, 58), "pine_dark": (30, 54, 46), "tunnel": (84, 84, 92),
}
DUAL = {"barrier_a", "barrier_b"}
SUN = (-0.3, 0.4, 1.0)  # overcast: a high, soft light; a face turned away loses at most three levels
SKY = [118, 128, 146, 202, 208, 216]  # a grey ceiling to a pale horizon
HILLS = [132, 144, 166, 92, 102, 120, 236, 240, 246]  # far range, near range, snow on the far tops
# (station, height) keys of the climb: a cosine ease between them; the crest is the bump on the top straight; the hairpins are level
HEIGHT = [(0, 0.0), (50, 0.0), (80, 3.0), (95, 3.0), (120, 7.0), (156, 7.0), (162, 10.0), (168, 7.0),
          (198, 7.0), (228, 0.0), (236, 0.0)]  # the climbs on the straights: a slope round a bend twists the quads
BOWL, BANK = (118, 154), -0.10  # the banked bowl: the outside (right) of the left turn raised
TUNNEL = (172, 182)


def st() -> list[Station]:
    return stations(spline([(float(x), float(y)) for x, y in POINTS]), N)


def heights() -> tuple[list[float], list[float]]:
    z = []
    for i in range(N):
        k = next(j for j in range(len(HEIGHT) - 1) if HEIGHT[j][0] <= i < HEIGHT[j + 1][0])
        (a, za), (b, zb) = HEIGHT[k], HEIGHT[k + 1]
        f = 0.5 - 0.5 * math.cos(math.pi * (i - a) / (b - a))
        z.append(round(za + (zb - za) * f, 3))
    ramp = 14  # a bank that changes faster twists the road quads past the planarity check
    bank = [BANK * min(1.0, (i - BOWL[0]) / ramp, (BOWL[1] - i) / ramp) if BOWL[0] <= i <= BOWL[1] else 0.0 for i in range(N)]
    return z, [round(b, 4) for b in bank]


def track(m: Mesh, s: list[Station]) -> None:
    z, bank = heights()
    road(m, s, SPEC, z, bank)
    embank(m, s, SPEC, z, bank, "bank", slope=1.5)


def decals(m: Mesh, s: list[Station]) -> None:
    z, bank = heights()
    for i in range(N):
        if i % 2 == 0:
            decal(m, s, SPEC, z, bank, i, (0.1, 0.9), (0.493, 0.507), "paint")
        k = turn(s, i)
        if abs(k) > 0.6:  # the hairpins and the bowl's apex
            decal(m, s, SPEC, z, bank, i, (0.0, 1.0), (0.0, 0.07) if k > 0 else (0.93, 1.0), ("kerb_a", "kerb_b")[i % 2])
    decal(m, s, SPEC, z, bank, 0, (0.2, 0.55), (0.03, 0.97), "paint_start")


def tunnel(m: Mesh, s: list[Station]) -> None:
    """Rock walls just outside the barriers, a ceiling over the road, snow on the rock above (the road's own height)."""
    z, _ = heights()
    edge, h = SPEC.half + SPEC.shoulder + 0.4, 4.0
    rows = []
    for i in range(TUNNEL[0], TUNNEL[1] + 1):
        x, y, lx, ly = s[i]
        p = lambda o, zz, i=i: (x + o * lx, y + o * ly, z[i] + zz)  # noqa: E731
        rows.append([m.v(*p(edge, 0.0), "PROP_FACE"), m.v(*p(edge, h), "PROP_FACE"), m.v(*p(-edge, h), "PROP_FACE"),
                     m.v(*p(-edge, 0.0), "PROP_FACE"), m.v(*p(edge + 3.0, 0.0), "PROP_FACE"),
                     m.v(*p(edge + 1.0, h + 1.5), "PROP_FACE"), m.v(*p(-edge - 1.0, h + 1.5), "PROP_FACE"),
                     m.v(*p(-edge - 3.0, 0.0), "PROP_FACE")])
    for a, b in zip(rows, rows[1:], strict=False):
        m.f([a[0], b[0], b[1], a[1]], "tunnel")
        m.f([a[3], a[2], b[2], b[3]], "tunnel")
        m.f([a[1], b[1], b[2], a[2]], "tunnel")
        m.f([a[5], a[6], b[6], b[5]], "rock_top")
        m.f([a[4], a[5], b[5], b[4]], "rock")
        m.f([a[7], b[7], b[6], a[6]], "rock")
    for r, sign in ((rows[0], -1), (rows[-1], 1)):
        portal = [r[1], r[5], r[6], r[2]]
        m.f(portal if sign > 0 else portal[::-1], "rock")


def scenery(m: Mesh, s: list[Station]) -> None:
    clear = SPEC.half + SPEC.shoulder + 12.0
    k = 0
    for gx in range(-120, 124, 11):
        for gy in range(-120, 124, 11):
            k += 1
            h = (k * 2654435761 >> 8) % 97
            x, y = gx + (h % 7) - 3, gy + (h % 5) - 2
            if h > 30 or not far_from(s, x, y, clear):
                continue
            if h % 4 == 0:
                box(m, (x, y, 0.0), (4.0 + h % 3, 3.0 + h % 2, 1.5 + (h % 5) * 0.5), h * 0.1, "rock", "rock_top")
            else:
                spire(m, x, y, 0.0, 1.4, 4.0 + (h % 4), "pine" if h % 2 else "pine_dark")
