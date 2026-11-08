"""TRIANGLE only, by the thousand (the edge walk, zm_blit_tri/_twalk, against the model's per-line
divide): every slope sign, slivers, flat tops and bottoms, collinear and one-point triangles,
dy = 1, |dx| >> dy, exact negative divisions, vertices far off the plane (the start divide), a
middle vertex on the clip's top row, with and without a clip rect, both plane heights. Same
script format as blitter_scripts.py.

The model computes (bx-ax) * (y-ay) in i32: vertices that would overflow it (|dx| ~ 65535 with
a top 33000 rows above the plane) are not drawn here; the RTL's product is 32-bit unsigned."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from blitter_scripts import CLIP, PLANE, TRI, Script, do, halftone, mm

Pt = tuple[int, int]
MTS = [mm.MT_B, mm.MT_B, mm.MT_XOR_BC, mm.MT_OR_BC]


def _fits_i32(pts: list[Pt]) -> bool:
    for i in range(3):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % 3]
        if ay > by:
            ax, ay, bx, by = bx, by, ax, ay
        t = min(by - 1, 279) - ay
        if ay < by and t > 0 and abs(bx - ax) * t > 2**31 - 1:
            return False
    return all(-32768 <= v <= 32767 for p in pts for v in p)


def _shape(s: Script) -> list[Pt]:
    r = s.r
    c = (r.randint(-20, 340), r.randint(-20, 220))

    def near(k: int) -> Pt:
        return c[0] + r.randint(-k, k), c[1] + r.randint(-k, k)

    kind = r.choice(["small", "small", "big", "big", "far", "huge", "sliver", "flat", "line", "dy1", "steep", "exact"])
    if kind == "small":
        return [near(12) for _ in range(3)]
    if kind == "big":
        return [(r.randint(-120, 440), r.randint(-120, 320)) for _ in range(3)]
    if kind == "far":  # one vertex far away: the start divide with a large t0
        return [near(40), near(40), (r.randint(-32768, 32767), r.choice([r.randint(-32768, -1000), r.randint(500, 32767)]))]
    if kind == "huge":
        return [(r.randint(-32768, 32767), r.randint(-32768, 32767)) for _ in range(3)]
    if kind == "sliver":
        a = near(60)
        return [a, (a[0] + r.randint(-2, 2), a[1] + r.randint(-150, 150)), near(60)]
    if kind == "flat":  # a flat top or bottom, or all three on one row
        y = c[1]
        return [(c[0] - r.randint(0, 80), y), (c[0] + r.randint(0, 80), y), near(90) if r.random() < 0.8 else (c[0], y)]
    if kind == "line":  # collinear, or a point
        dx, dy = r.randint(-40, 40), r.randint(-40, 40)
        k = r.choice([0, 1])
        return [c, (c[0] + k * dx, c[1] + k * dy), (c[0] + 2 * k * dx, c[1] + 2 * k * dy)]
    if kind == "dy1":
        return [c, (c[0] + r.randint(-300, 300), c[1] + 1), (c[0] + r.randint(-300, 300), c[1] + r.choice([0, 1, 2]))]
    if kind == "steep":  # |dx| >> dy and dy >> |dx|
        return [c, (c[0] + r.randint(-2000, 2000), c[1] + r.randint(1, 6)), (c[0] + r.randint(-3, 3), c[1] + r.randint(-90, 90))]
    # an exact negative division with the top above the clip: dx * t0 a multiple of dy
    dy, q = r.randint(1, 40), r.randint(-6, 6)
    top = (c[0], r.randint(-60, 10))
    return [top, (top[0] + q * dy, top[1] + dy), near(50)]


def _clip(s: Script, pts: list[Pt]) -> None:
    r = s.r
    if r.random() < 0.6:
        s.w(8, mm.BLIT_CON, 0)
        return
    ys = sorted(p[1] for p in pts)
    cy = max(0, min(199, ys[1] if r.random() < 0.3 else r.randint(0, 150)))  # sometimes the middle vertex's row
    do_w = (r.randint(0, 200), cy, r.randint(1, 300), r.randint(1, 200))
    s.w(8, mm.BLIT_CON, CLIP)
    for off, v in zip((mm.BLIT_CLIP_X, mm.BLIT_CLIP_Y, mm.BLIT_CLIP_W, mm.BLIT_CLIP_H), do_w, strict=True):
        s.w(16, off, v)


def tri_op(s: Script) -> None:
    r = s.r
    pts = _shape(s)
    while not _fits_i32(pts):
        pts = _shape(s)
    r.shuffle(pts)
    _clip(s, pts)
    s.w(8, mm.BLIT_CON2, mm.CON2_HALFTONE_EN if r.random() < 0.1 else 0)
    regs = {"mt": r.choice(MTS), "color": r.randrange(1, 256), "bg": r.randrange(256), "d": PLANE}
    regs["ds"] = r.choice([320, 320, 400])
    for k, (x, y) in enumerate(pts):
        regs[f"x{k}"], regs[f"y{k}"] = x & 0xFFFF, y & 0xFFFF
    do(s, TRI, **regs)


def make_tri_script(seed: int, n: int) -> Script:
    s = Script(seed)
    halftone(s, [0xAAAA, 0x5555] * 8)
    for i in range(n):
        if i % 200 == 199:
            s.lines.append(f"seed {seed + i}")
        tri_op(s)
    return s
