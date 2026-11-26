"""Salt Flats' geometry (R82 M5), no bpy: the centre line, the road / shoulder / wall strip, the decals and the props as one
`Mesh` per Blender object, in Blender axes (Z up), with the Track Kit's vertex groups. salt_flats_build.py makes the scene.
"""

from __future__ import annotations

import math

N = 176  # racing-line segments (~4.3 units each)
A, B, EXP = 100.0, 106.0, 3.2  # the superellipse: semi-axes x, y and its exponent (rounded corners, long straights)
BAY_AT, BAY_DEPTH, BAY_W = 0.78 * math.pi, 0.2, 0.3 * math.pi  # a sweeping bay pulled in on the far side
HALF, SHOULDER, WALL_H = 6.0, 3.0, 0.5
PALETTE = {
    "salt": (172, 166, 150), "shoulder": (150, 142, 124), "asphalt_a": (106, 106, 110), "asphalt_b": (92, 92, 98),
    "barrier_a": (168, 62, 50), "barrier_b": (184, 180, 170), "paint": (200, 198, 188), "paint_start": (214, 184, 64),
    "kerb_a": (176, 58, 46), "kerb_b": (196, 194, 186), "stand": (128, 118, 104), "roof": (74, 92, 128),
    "tower": (150, 140, 122), "pylon": (206, 112, 44), "mesa": (150, 112, 82), "mesa_top": (164, 126, 92),
}
DUAL = {"barrier_a", "barrier_b"}
SKY = [34, 92, 186, 228, 216, 192]  # noon: a deep desert blue overhead to a warm, hazy horizon (M5 finish)
HILLS = [156, 140, 152, 176, 140, 104, 214, 196, 168]  # the "peaks" strip: a far violet range, a near tan one, sunlit tops


def curve(t: float) -> tuple[float, float]:
    c, s = math.cos(t), math.sin(t)
    x, y = A * math.copysign(abs(c) ** (2 / EXP), c), B * math.copysign(abs(s) ** (2 / EXP), s)
    d = abs((t - BAY_AT + math.pi) % (2 * math.pi) - math.pi)
    k = 1 - BAY_DEPTH * (0.5 * (1 + math.cos(math.pi * d / BAY_W)) if d < BAY_W else 0.0)
    return x * k, y * k


def stations() -> list[tuple[float, float, float, float]]:
    """N points equally spaced in arc length from t = 0: (x, y, left_x, left_y), left = the unit normal left of travel."""
    steps = 20000
    pts = [curve(2 * math.pi * k / steps) for k in range(steps + 1)]
    cum = [0.0]
    for a, b in zip(pts, pts[1:], strict=False):
        cum.append(cum[-1] + math.dist(a, b))
    out, k = [], 0
    for i in range(N):
        want = cum[-1] * i / N
        while cum[k + 1] < want:
            k += 1
        out.append(pts[k])
    res = []
    for i, (x, y) in enumerate(out):
        nx, ny = out[(i + 1) % N]
        px, py = out[i - 1]
        dx, dy = nx - px, ny - py
        n = math.hypot(dx, dy)
        res.append((x, y, -dy / n, dx / n))
    return res


class Mesh:
    def __init__(self) -> None:
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[list[int]] = []
        self.mats: list[str] = []
        self.groups: dict[str, set[int]] = {}

    def v(self, x: float, y: float, z: float, *groups: str) -> int:
        self.verts.append((x, y, z))
        for g in groups:
            self.groups.setdefault(g, set()).add(len(self.verts) - 1)
        return len(self.verts) - 1

    def f(self, ids: list[int], mat: str) -> None:
        self.faces.append(ids)
        self.mats.append(mat)


def road(m: Mesh, st: list[tuple[float, float, float, float]]) -> list[list[int]]:
    rows = []
    for i, (x, y, lx, ly) in enumerate(st):
        at = lambda o, z=0.0: (x + o * lx, y + o * ly, z)  # noqa: E731
        g = ["GROUND_FACE"]
        start = ["LINE_START"] if i == 0 else []
        cp = [f"CHECKPT_{(i // (N // 4)) or 4}"] if i % (N // 4) == 0 else []
        rows.append([m.v(*at(HALF + SHOULDER), *g, "BORDER1"), m.v(*at(HALF), *g, "TRACK_FACE", "TRACK_L", *start, *cp),
                     m.v(*at(-HALF), *g, "TRACK_FACE", "TRACK_R"), m.v(*at(-HALF - SHOULDER), *g, "BORDER1"),
                     m.v(*at(HALF + SHOULDER, WALL_H)), m.v(*at(-HALF - SHOULDER, WALL_H))])
    for i in range(N):
        a, b = rows[i], rows[(i + 1) % N]
        m.f([a[1], a[2], b[2], b[1]], ("asphalt_a", "asphalt_b")[(i // 2) % 2])
        m.f([a[0], a[1], b[1], b[0]], "shoulder")
        m.f([a[2], a[3], b[3], b[2]], "shoulder")
        bar = ("barrier_a", "barrier_b")[(i // 3) % 2]
        m.f([a[0], b[0], b[4], a[4]], bar)  # the walls, facing the road
        m.f([a[3], a[5], b[5], b[3]], bar)
    return rows


def decal(m: Mesh, st: list, i: int, u: tuple[float, float], t: tuple[float, float], mat: str) -> None:
    """A DETAIL face on road segment i: u along (0 -> 1 = station i -> i+1), t across (0 left edge -> 1 right edge)."""
    a, b = st[i], st[(i + 1) % N]
    ids = []
    for uu, tt in ((u[0], t[1]), (u[0], t[0]), (u[1], t[0]), (u[1], t[1])):
        o = HALF - 2 * HALF * tt
        pa = (a[0] + o * a[2], a[1] + o * a[3])
        pb = (b[0] + o * b[2], b[1] + o * b[3])
        ids.append(m.v(pa[0] + (pb[0] - pa[0]) * uu, pa[1] + (pb[1] - pa[1]) * uu, 0.0, "DETAIL_FACE"))
    m.f(ids, mat)


def decals(m: Mesh, st: list) -> None:
    for i in range(N):
        if i % 2 == 0:
            decal(m, st, i, (0.1, 0.9), (0.493, 0.507), "paint")
        a, b, c = st[i - 1], st[i], st[(i + 1) % N]
        turn = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])  # > 0: turning left
        if abs(turn) > 0.25:
            side = (0.0, 0.07) if turn > 0 else (0.93, 1.0)
            decal(m, st, i, (0.0, 1.0), side, ("kerb_a", "kerb_b")[i % 2])
    decal(m, st, 0, (0.2, 0.55), (0.03, 0.97), "paint_start")


def box(m: Mesh, cx: float, cy: float, w: float, d: float, h: float, rot: float, side: str, top: str, z0: float = 0.0) -> None:
    c, s = math.cos(rot), math.sin(rot)
    corner = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
    lo = [m.v(cx + x * c - y * s, cy + x * s + y * c, z0, "PROP_FACE") for x, y in corner]
    hi = [m.v(cx + x * c - y * s, cy + x * s + y * c, z0 + h, "PROP_FACE") for x, y in corner]
    for k in range(4):
        j = (k + 1) % 4
        m.f([lo[k], lo[j], hi[j], hi[k]], side)
    m.f(hi, top)


def pylon(m: Mesh, x: float, y: float) -> None:
    base = [m.v(x + dx, y + dy, 0.0, "PROP_FACE") for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))]
    tip = m.v(x, y, 2.2, "PROP_FACE")
    for k in range(4):
        m.f([base[k], base[(k + 1) % 4], tip], "pylon")


def props(m: Mesh, st: list) -> None:
    x0, y0, lx, ly = st[0]
    out = HALF + SHOULDER + 6.0  # the start straight's right side (outside the loop)
    box(m, x0 - lx * out, y0 - ly * out + 6, 6.0, 36.0, 4.0, 0.0, "stand", "roof")
    box(m, x0 + lx * 16, y0 + ly * 16 - 22, 3.0, 3.0, 9.0, 0.0, "tower", "roof")
    for i in range(0, N, 16):
        x, y, lx, ly = st[i]
        pylon(m, x - lx * (HALF + SHOULDER + 3), y - ly * (HALF + SHOULDER + 3))
    for cx, cy, w, d, h, r in ((-30.0, 20.0, 18.0, 12.0, 3.5, 0.3), (25.0, -35.0, 12.0, 20.0, 5.0, -0.5), (-10.0, -60.0, 10.0, 8.0, 2.5, 1.1)):
        box(m, cx, cy, w, d, h, r, "mesa", "mesa_top")
