"""The GT car's geometry (R82 M5 step 3), no bpy: our own flat-shaded low-poly GT coupe, designed for Kestrel Racing (not a
copy of any real or Sega car). One `Mesh` per Blender object, in Blender axes (x right, y forward, z up) and in 1/128 units
(the cart's Q7 grid, so the export's snap is exact). gt_build.py makes the scene.

The body is a loft of one cross-section (sill -> shoulder -> deck) translated per station, so every side quad is planar and
the hull is convex; the four wheel arches are where the lower side is left open. Wheels sit on carmodel.WHEELS' contact points
(x 19.2, z +-25.6 Q7), the visible size stays the placeholder's envelope (34 wide, 64 long, 18 high); the collision box is
freds72's and does not change (car.zig).
"""

from __future__ import annotations

import itertools
import math

Q = 1 / 128
# stations along y (rear to front): y, shoulder half-width W, shoulder height Z. sill = (W - 2, Z - 6), deck = (W - 4, Z + 2)
STATIONS = ((-32, 16, 10), (-20, 17, 10), (20, 17, 9), (32, 15, 7))
STRIPE = 3  # the livery stripe's half-width, over the deck and the roof
LAMP = 8  # the lamps run from the shoulder corner to x = +-LAMP on the nose and the tail
CABIN = {"base_y": (10, -16), "base_x": 12, "base_z": 11, "roof_y": (1, -10), "roof_x": 9, "roof_z": 18}
WING = {"y": (-24, -30), "x": 15, "z": (16, 17), "strut_x": (7, 9)}
AXLES, WHEEL_X, WHEEL_R, WHEEL_ZC = (25.6, -25.6), (14.0, 19.0), 5.0, 5.0
RIM = 2.6
SHADOW = {"x": (-22, 14), "y": (-40, 27), "z": 1}  # the footprint cast away from SUN (right, ahead, high): left and behind
SUN = (0.35, 0.45, 1.0)  # the car's own fixed sun (Blender axes): the bake's light, turning with the car
MATERIALS = {  # material -> the Blender preview colour (the cart's palette ramps decide the real one: carc.MATERIALS)
    "body": (205, 35, 35), "stripe": (232, 232, 236), "dark": (45, 45, 55), "glass": (110, 150, 190), "rim": (190, 190, 196),
    "head": (240, 236, 200), "tail": (230, 40, 30), "shadow": (20, 20, 20),
}


class Mesh:
    def __init__(self) -> None:
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[list[int]] = []
        self.mats: list[str] = []
        self.groups: dict[str, set[int]] = {}

    def v(self, x: float, y: float, z: float) -> int:
        self.verts.append((x * Q, y * Q, z * Q))
        return len(self.verts) - 1

    def f(self, ids: list[int], mat: str, out: tuple[float, float, float]) -> None:
        """A face wound counter-clockwise seen from `out` (Blender's normal convention), whatever order the ids came in."""
        p = [self.verts[i] for i in ids]
        n = [0.0, 0.0, 0.0]
        for a, b in zip(p, p[1:] + p[:1], strict=True):
            n[0] += (a[1] - b[1]) * (a[2] + b[2])
            n[1] += (a[2] - b[2]) * (a[0] + b[0])
            n[2] += (a[0] - b[0]) * (a[1] + b[1])
        self.faces.append(ids if sum(x * y for x, y in zip(n, out, strict=True)) > 0 else ids[::-1])
        self.mats.append(mat)


def _section(m: Mesh, y: float, w: float, z: float) -> dict[str, int]:
    pts = {"sill": (w - 2, z - 6), "shoulder": (w, z), "deck": (w - 4, z + 2), "stripe": (STRIPE, z + 2)}
    out = {}
    for name, (x, zz) in pts.items():
        out[name + "L"] = m.v(-x, y, zz)
        out[name + "R"] = m.v(x, y, zz)
    return out


def _cap(m: Mesh, s: dict[str, int], y: float, w: float, z: float, lamp: str, out: float) -> None:
    """The nose or the tail: the lower panel (a dark intake at the nose, the livery at the tail: a dark tail read black from
    behind), the upper band split into two lamps and the body between them."""
    d = (0.0, out, 0.0)
    m.f([s["sillL"], s["shoulderL"], s["shoulderR"], s["sillR"]], "dark" if out > 0 else "body", d)
    inner = {k: (m.v(k * LAMP, y, z), m.v(k * LAMP, y, z + 2)) for k in (-1, 1)}
    m.f([s["shoulderL"], s["deckL"], inner[-1][1], inner[-1][0]], lamp, d)
    m.f([inner[-1][0], inner[-1][1], inner[1][1], inner[1][0]], "body", d)
    m.f([inner[1][0], inner[1][1], s["deckR"], s["shoulderR"]], lamp, d)


def hull() -> Mesh:
    m = Mesh()
    secs = [_section(m, y, w, z) for y, w, z in STATIONS]
    for i, (a, b) in enumerate(itertools.pairwise(secs)):
        up = (0.0, 0.0, 1.0)
        m.f([a["deckL"], b["deckL"], b["stripeL"], a["stripeL"]], "body", up)
        m.f([a["stripeL"], b["stripeL"], b["stripeR"], a["stripeR"]], "stripe", up)
        m.f([a["stripeR"], b["stripeR"], b["deckR"], a["deckR"]], "body", up)
        for side, sx in (("L", -1.0), ("R", 1.0)):
            m.f([a["shoulder" + side], b["shoulder" + side], b["deck" + side], a["deck" + side]], "body", (sx, 0.0, 0.5))
            if i == 1:  # between the arches: the lower side; the arches stay open over the wheels
                m.f([a["sill" + side], b["sill" + side], b["shoulder" + side], a["shoulder" + side]], "body", (sx, 0.0, -0.2))
    _cap(m, secs[-1], *STATIONS[-1], "head", 1.0)
    _cap(m, secs[0], *STATIONS[0], "tail", -1.0)
    return m


def cabin() -> Mesh:
    c, m = CABIN, Mesh()
    b = {(s, k): m.v(s * c["base_x"], c["base_y"][k], c["base_z"]) for s in (-1, 1) for k in (0, 1)}
    r = {(s, k): m.v(s * c["roof_x"], c["roof_y"][k], c["roof_z"]) for s in (-1, 1) for k in (0, 1)}
    st = {(s, k): m.v(s * STRIPE, c["roof_y"][k], c["roof_z"]) for s in (-1, 1) for k in (0, 1)}
    m.f([b[-1, 0], r[-1, 0], r[1, 0], b[1, 0]], "glass", (0.0, 1.0, 0.8))
    m.f([b[-1, 1], r[-1, 1], r[1, 1], b[1, 1]], "glass", (0.0, -1.0, 0.8))
    up = (0.0, 0.0, 1.0)
    m.f([r[-1, 0], r[-1, 1], st[-1, 1], st[-1, 0]], "body", up)
    m.f([st[-1, 0], st[-1, 1], st[1, 1], st[1, 0]], "stripe", up)
    m.f([st[1, 0], st[1, 1], r[1, 1], r[1, 0]], "body", up)
    for s in (-1, 1):
        m.f([b[s, 0], r[s, 0], r[s, 1], b[s, 1]], "glass", (float(s), 0.0, 0.3))
    return m


def wing() -> Mesh:
    w, m = WING, Mesh()
    (yf, yb), (zb, zt) = w["y"], w["z"]
    top = [m.v(-w["x"], yf, zt), m.v(w["x"], yf, zt), m.v(w["x"], yb, zt), m.v(-w["x"], yb, zt)]
    low = [m.v(w["x"], yb, zb), m.v(-w["x"], yb, zb)]
    m.f(top, "stripe", (0.0, 0.0, 1.0))
    m.f([top[3], top[2], low[0], low[1]], "dark", (0.0, -1.0, 0.0))
    deck_z = STATIONS[0][2] + 2
    for s in (-1, 1):
        x0, x1 = (s * w["strut_x"][0], s * w["strut_x"][1])
        y = (yf + yb) / 2
        m.f([m.v(x0, y, deck_z), m.v(x1, y, deck_z), m.v(x1, y, zb), m.v(x0, y, zb)], "dark", (0.0, -1.0, 0.0))
    return m


def _wheel(m: Mesh, side: int, axle: float) -> None:
    xi, xo = (side * WHEEL_X[0], side * WHEEL_X[1])
    ang = [math.radians(a) for a in (0, 60, 120, 180, 240, 300)]  # (y, z) round the hub: 0 = forward, flat top and bottom
    hexo = [m.v(xo, axle + WHEEL_R * math.cos(a), WHEEL_ZC + WHEEL_R * math.sin(a)) for a in ang]
    hexi = [m.v(xi, axle + WHEEL_R * math.cos(a), WHEEL_ZC + WHEEL_R * math.sin(a)) for a in ang]
    out = (float(side), 0.0, 0.0)
    m.f([hexo[0], hexo[1], hexo[2], hexo[3]], "dark", out)
    m.f([hexo[3], hexo[4], hexo[5], hexo[0]], "dark", out)
    rim = [m.v(xo, axle + RIM * math.cos(a), WHEEL_ZC + RIM * math.sin(a)) for a in [math.radians(45 + 90 * k) for k in range(4)]]
    m.f(rim, "rim", out)
    tread = (1, 2, 3) if axle < 0 else (5, 0, 1)  # the top, and the two faces each wheel shows away from the car's middle
    for k in tread:
        j = (k + 1) % 6
        a = (ang[k] + ang[j]) / 2 if j else (ang[k] + 2 * math.pi) / 2
        m.f([hexo[k], hexo[j], hexi[j], hexi[k]], "dark", (0.0, math.cos(a), math.sin(a)))


def wheels() -> Mesh:
    m = Mesh()
    for axle in AXLES:
        for side in (-1, 1):
            _wheel(m, side, axle)
    return m


def shadow() -> Mesh:
    s, m = SHADOW, Mesh()
    y0, y1 = s["y"]
    (x0, x1), z = s["x"], s["z"]
    m.f([m.v(x0, y0, z), m.v(x1, y0, z), m.v(x1, y1, z), m.v(x0, y1, z)], "shadow",
        (0.0, 0.0, 1.0))
    return m


def lod1() -> Mesh:
    """The far car (a few pixels): the hull's box, its deck stripe, the glasshouse as one wedge, the tail."""
    m = Mesh()
    yr, yf = STATIONS[0][0], STATIONS[-1][0]
    w = 17
    lo = {(s, k): m.v(s * w, (yr, yf)[k], 3) for s in (-1, 1) for k in (0, 1)}
    hi = {(s, k): m.v(s * (w - 3), (yr, yf)[k], 11) for s in (-1, 1) for k in (0, 1)}
    up = (0.0, 0.0, 1.0)
    m.f([hi[-1, 0], hi[-1, 1], hi[1, 1], hi[1, 0]], "body", up)
    for s in (-1, 1):
        m.f([lo[s, 0], lo[s, 1], hi[s, 1], hi[s, 0]], "body", (float(s), 0.0, 0.2))
    m.f([lo[-1, 0], hi[-1, 0], hi[1, 0], lo[1, 0]], "body", (0.0, -1.0, 0.0))
    m.f([lo[-1, 1], hi[-1, 1], hi[1, 1], lo[1, 1]], "dark", (0.0, 1.0, 0.0))
    c = CABIN
    g = {(s, k): m.v(s * c["base_x"], c["base_y"][k], c["base_z"]) for s in (-1, 1) for k in (0, 1)}
    r = [m.v(-c["roof_x"], c["roof_y"][1], c["roof_z"]), m.v(c["roof_x"], c["roof_y"][1], c["roof_z"])]
    m.f([g[-1, 0], r[0], r[1], g[1, 0]], "glass", (0.0, 1.0, 1.0))
    m.f([g[-1, 1], r[0], r[1], g[1, 1]], "glass", (0.0, -1.0, 0.6))
    for s, rs in ((-1, r[0]), (1, r[1])):
        m.f([g[s, 0], rs, g[s, 1]], "glass", (float(s), 0.0, 0.3))
    return m


PARTS = {"wheels": wheels, "hull": hull, "cabin": cabin, "wing": wing, "shadow": shadow, "lod1": lod1}
