"""The falcon wireframe, its pose and projection, the dot assignment (aurora_lab.html `V`/`E`/`pose`/`project`/`assignTargets`).

The lab's own placeholder model, ported number for number. The baker evaluates pose + projection for
every baked frame (floats are fine here); the cart only plays back 2D points.
"""
import math

import numpy as np

from aurora_common import H, W, beats, smooth


def _build():
    V, E = {}, []

    def v(n, x, y, z):
        V[n] = (x, y, z)

    v("beak", 0, 0.03, 1.12); v("crown", 0, 0.17, 0.93); v("chin", 0, -0.04, 0.9); v("chest", 0, -0.13, 0.55); v("back", 0, 0.12, 0.5)
    v("belly", 0, -0.1, 0.02); v("rump", 0, 0.06, -0.25); v("tailB", 0, 0.02, -0.4)
    v("tL2", -0.24, 0, -0.95); v("tL1", -0.09, 0, -1.02); v("tR1", 0.09, 0, -1.02); v("tR2", 0.24, 0, -0.95)
    for s, k in (("R", 1), ("L", -1)):
        v("side" + s, 0.12 * k, 0.02, 0.55); v("hip" + s, 0.13 * k, 0, 0.12); v("tsd" + s, 0.08 * k, 0, -0.3)
        v("sh" + s, 0.13 * k, 0.06, 0.44); v("le1" + s, 0.45 * k, 0.12, 0.42); v("wr" + s, 0.8 * k, 0.15, 0.3)
        v("le3" + s, 1.15 * k, 0.12, 0.1); v("tip" + s, 1.47 * k, 0.08, -0.16)
        v("p1" + s, 1.38 * k, 0.06, -0.33); v("p2" + s, 1.24 * k, 0.05, -0.43); v("p3" + s, 1.06 * k, 0.04, -0.46)
        v("p4" + s, 0.86 * k, 0.03, -0.39); v("s1" + s, 0.6 * k, 0.02, -0.3); v("s2" + s, 0.35 * k, 0.03, -0.18)
        v("s3" + s, 0.14 * k, 0.02, 0.06)
        w = lambda n: n + s  # noqa: E731
        E.extend([("crown", w("side")), ("chin", w("side")), (w("side"), w("hip")), (w("hip"), w("tsd")), (w("tsd"), "tailB"),
                  (w("side"), "back"), (w("side"), "chest"), (w("hip"), "belly"),
                  (w("sh"), w("le1")), (w("le1"), w("wr")), (w("wr"), w("le3")), (w("le3"), w("tip")), (w("tip"), w("p1")),
                  (w("p1"), w("p2")), (w("p2"), w("p3")), (w("p3"), w("p4")), (w("p4"), w("s1")), (w("s1"), w("s2")),
                  (w("s2"), w("s3")), (w("s3"), w("hip")), (w("le1"), w("s2")), (w("wr"), w("s1")), (w("le3"), w("p4")),
                  (w("le3"), w("p3")), (w("le3"), w("p2"))])
    E.extend([("beak", "crown"), ("beak", "chin"), ("crown", "back"), ("chin", "chest"), ("back", "rump"), ("chest", "belly"),
              ("belly", "tailB"), ("rump", "tailB"), ("tailB", "tL2"), ("tailB", "tL1"), ("tailB", "tR1"), ("tailB", "tR2"),
              ("tL2", "tL1"), ("tL1", "tR1"), ("tR1", "tR2")])
    return V, E


V, E = _build()
NAMES = list(V)
INDEX = {n: i for i, n in enumerate(NAMES)}
EDGES = [(INDEX[a], INDEX[b]) for a, b in E]
_LEN = [math.dist(V[a], V[b]) for a, b in E]
TOTAL_LEN = sum(_LEN)


def _rot(p, cx, cy, a):
    c, s, x, y = math.cos(a), math.sin(a), p[0] - cx, p[1] - cy
    return (cx + x * c - y * s, cy + x * s + y * c, p[2])


def pose(t, p, b):
    """{name: (x, y, z)} and the body placement at time t (the lab's `pose`)."""
    peg = p["bird"] == "PEREGRINE"
    flap = (0.5 if peg else 1) * p["wingAmp"] * math.sin(t * 2 * math.pi * p["wingHz"] * (0.5 if peg else 1))
    dive = min(1, max(0, (t - b.m0) / (b.m1 + 0.4 - b.m0))) if peg else 1
    tuck = (1 - smooth(min(1, max(0, (dive - 0.75) / 0.25)))) if peg else 0
    out = {}
    for n, v in V.items():
        side = 1 if n.endswith("R") else -1 if n.endswith("L") else 0
        wing = side and not n.startswith(("side", "hip", "tsd"))
        q = v
        if wing:
            q = (v[0] * side, v[1], v[2])
            if q[0] > 0.8:
                q = _rot(q, 0.8, 0.15, flap * 0.6)
            q = _rot(q, 0.13, 0.06, flap)
            if tuck > 0:
                ex = q[0] - 0.13
                q = (0.13 + ex * (1 - 0.72 * tuck), q[1] - 0.05 * tuck * ex, q[2] - ex * 0.7 * tuck)
            q = (q[0] * side, q[1], q[2])
        out[n] = q
    bob = 0 if peg else 0.06 * p["wingAmp"] * math.sin(t * 2 * math.pi * p["wingHz"] + 1.2)
    s = smooth(dive)
    return dict(V=out, dist=9 - 6.4 * s if peg else 2.7, lift=1.1 * (1 - s) + bob if peg else bob,
                nose=-1.05 * (1 - s) - 0.15 if peg else -0.12, yaw=0.15 if peg else 0.55 + 0.08 * math.sin(t * 0.7))


def project(pt, ps):
    x, y, z = pt
    cn, sn = math.cos(ps["nose"]), math.sin(ps["nose"])
    y, z = y * cn - z * sn, y * sn + z * cn
    cy, sy = math.cos(ps["yaw"]), math.sin(ps["yaw"])
    x, z = x * cy + z * sy, -x * sy + z * cy
    ct, st = math.cos(0.42), math.sin(0.42)
    y, z = y * ct - z * st, y * st + z * ct
    y += ps["lift"]
    zz = z + ps["dist"]
    f = H * 0.95
    return (W * 0.5 + f * x / zz, H * 0.44 - f * y / zz)


def projected(t, p, b):
    """(NV, 2) float array: every vertex at time t."""
    ps = pose(t, p, b)
    return np.array([project(ps["V"][n], ps) for n in NAMES])


def dots(n):
    """One (edge, u) per star, spread evenly along the edges by length."""
    out, e, acc = [], 0, 0.0
    for i in range(n):
        at = (i + 0.5) / n * TOTAL_LEN
        while e < len(E) - 1 and acc + _LEN[e] < at:
            acc += _LEN[e]
            e += 1
        out.append((e, min(1.0, (at - acc) / _LEN[e])))
    return out


def dot_xy(d, proj):
    (e, u), (a, b) = d, EDGES[d[0]]
    return proj[a] + (proj[b] - proj[a]) * u


def _ang(xy, cx, cy):
    return math.atan2(xy[1] - cy, xy[0] - cx)


def assign(stars, p):
    """(dot_of_star, delay_of_star): stars matched to dots by angle around the centre (the lab's `assignTargets`)."""
    b = beats(p)
    ds = dots(len(stars))
    proj = projected(b.m1, p, b)
    cx, cy = W * 0.5, H * 0.44
    d_ang = sorted(range(len(ds)), key=lambda i: _ang(dot_xy(ds[i], proj), cx, cy))
    s_ang = sorted(range(len(stars)), key=lambda i: math.atan2(stars[i][1] - cy, stars[i][0] - cx))
    rmax = max(1.0, *(math.hypot(s[1] - cy, s[0] - cx) for s in stars))
    dot_of, delay = [0] * len(stars), [0.0] * len(stars)
    for k, si in enumerate(s_ang):
        dot_of[si] = d_ang[k]
        delay[si] = 0.35 * (math.hypot(stars[si][1] - cy, stars[si][0] - cx) / rmax)
    return ds, dot_of, delay
