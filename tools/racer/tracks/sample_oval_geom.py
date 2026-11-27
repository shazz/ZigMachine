"""The Track Kit's sample track (R82 M7), no bpy: Kestrel Oval, a small club oval in late-afternoon sun. Original content (ours).

The track a new author opens first, so it uses EVERY convention once and stays small enough to read:
- the road (TRACK_FACE), its shoulders (GROUND_FACE) and their wall edges (BORDER1), the barriers (walls, double-sided);
- the racing line (TRACK_L / TRACK_R, LINE_START) and four checkpoints (CHECKPT_1..4), the eight-slot start grid;
- decals (DETAIL_FACE): centre dashes, kerbs on both turns, the start line;
- a covered pit gantry over the back straight: its segments are CAM_NEAR (the far chase camera goes near under the roof);
- scenery (PROP_FACE): a grandstand, the gantry, infield trees, tyre stacks;
- the mood (sample_oval_build.py): sun, sky, the hills backdrop, haze, a set race clock, a draw distance cap, the scales.
A stadium oval: two 120-unit straights joined by two 32-unit-radius turns, 96 segments of ~4.4 units.
"""

from __future__ import annotations

import itertools
import math

from kitgeom import Road, Station, box, decal, far_from, road, spire, stations, turn
from salt_flats_geom import Mesh

N = 96
STRAIGHT, RADIUS = 120.0, 32.0
SPEC = Road(half=6.0, shoulder=2.5, wall_h=0.6, asphalt=("asphalt_a", "asphalt_b"), shoulder_mat="verge",
            barrier=("barrier_a", "barrier_b"), cam_near=(58, 64))  # the pit gantry's segments (the back straight)
PALETTE = {
    "grass": (92, 140, 72), "verge": (120, 150, 92), "asphalt_a": (100, 100, 106), "asphalt_b": (86, 86, 94),
    "barrier_a": (40, 90, 170), "barrier_b": (210, 210, 214), "paint": (206, 206, 198), "paint_start": (220, 186, 60),
    "kerb_a": (190, 50, 44), "kerb_b": (214, 212, 204), "stand": (150, 132, 112), "roof": (70, 80, 110),
    "gantry": (120, 120, 128), "tree": (50, 96, 56), "tree_dark": (38, 76, 46), "tyre": (44, 44, 50),
}
DUAL = {"barrier_a", "barrier_b", "gantry"}  # the gantry's ceiling is seen from below, its walls from both sides
SUN = (0.6, -0.5, 0.8)  # late afternoon: lower than noon, so walls facing west read a level or two brighter
SKY = [40, 84, 160, 236, 196, 150]  # a deep blue overhead to a warm horizon
HILLS = [122, 140, 168, 84, 120, 80, 70, 74, 104]  # far range, near hills, the skyline
HAZE = ([236, 196, 150], 128, 96)  # the horizon haze: the sky's horizon colour, from half the draw distance, gentle
CLOCK = [90, 15]  # the race clock: 90 s to start, 15 s a checkpoint (0, 0 would let the cart compute it from the line)
DRAW_R = 7  # the draw distance cap in tiles (3..8): the player's R 8 is lowered to 7 here
SCALE = (1067, 640)  # the arcade world and car scales, Q8: the Kit's defaults (kit.KIT_WORLD, KIT_CAR), set explicitly
GANTRY = SPEC.cam_near


def curve(t: float) -> tuple[float, float]:
    """The stadium, t in [0, 1) by arc length: the start straight along +x at y = -RADIUS, counter-clockwise."""
    per = 2 * STRAIGHT + 2 * math.pi * RADIUS
    s = (t % 1.0) * per
    half = STRAIGHT / 2
    if s < STRAIGHT:
        return -half + s, -RADIUS
    s -= STRAIGHT
    arc = math.pi * RADIUS
    if s < arc:
        a = -math.pi / 2 + s / RADIUS
        return half + RADIUS * math.cos(a), RADIUS * math.sin(a)
    s -= arc
    if s < STRAIGHT:
        return half - s, RADIUS
    a = math.pi / 2 + (s - STRAIGHT) / RADIUS
    return -half + RADIUS * math.cos(a), RADIUS * math.sin(a)


def st() -> list[Station]:
    return stations(curve, N)


def flat() -> tuple[list[float], list[float]]:
    return [0.0] * N, [0.0] * N


def track(m: Mesh, s: list[Station]) -> None:
    z, bank = flat()
    road(m, s, SPEC, z, bank)


def decals(m: Mesh, s: list[Station]) -> None:
    z, bank = flat()
    for i in range(N):
        if i % 2 == 0 and not GANTRY[0] <= i < GANTRY[1]:
            decal(m, s, SPEC, z, bank, i, (0.15, 0.85), (0.493, 0.507), "paint")
        k = turn(s, i)
        if abs(k) > 0.25:  # the turns: kerbs on the inside (left: the oval runs counter-clockwise)
            decal(m, s, SPEC, z, bank, i, (0.0, 1.0), (0.0, 0.07) if k > 0 else (0.93, 1.0), ("kerb_a", "kerb_b")[i % 2])
    decal(m, s, SPEC, z, bank, 0, (0.2, 0.55), (0.03, 0.97), "paint_start")


def gantry(m: Mesh, s: list[Station]) -> None:
    """The pit gantry: two walls just outside the barriers and a ceiling over the road, its segments CAM_NEAR."""
    edge, h = SPEC.half + SPEC.shoulder + 0.4, 4.5
    rows = []
    for i in range(GANTRY[0], GANTRY[1] + 1):
        x, y, lx, ly = s[i]
        rows.append([m.v(x + o * lx, y + o * ly, zz, "PROP_FACE") for o, zz in ((edge, 0.0), (edge, h), (-edge, h), (-edge, 0.0))])
    for a, b in itertools.pairwise(rows):
        m.f([a[0], b[0], b[1], a[1]], "gantry")
        m.f([a[3], a[2], b[2], b[3]], "gantry")
        m.f([a[1], b[1], b[2], a[2]], "gantry")
    roof = [rows[0][1], rows[-1][1], rows[-1][2], rows[0][2]]  # a flat roof slab on top, seen from the stand
    top = [m.v(*m.verts[v][:2], h + 0.6, "PROP_FACE") for v in roof]
    m.f(top[::-1], "roof")


def scenery(m: Mesh, s: list[Station]) -> None:
    x0, y0, lx, ly = s[N // 8]
    out = SPEC.half + SPEC.shoulder + 6.0  # the start straight's outside (right of travel)
    box(m, (x0 - lx * out, y0 - ly * out, 0.0), (40.0, 7.0, 4.0), 0.0, "stand", "roof")
    for k, x in enumerate((-40.0, -20.0, 0.0, 20.0, 40.0)):  # the infield: trees between the straights
        spire(m, x, 6.0 * (1 if k % 2 else -1), 0.0, 1.6, 5.0 + k % 3, "tree" if k % 2 else "tree_dark")
    for i in range(N // 4, N, N // 4):  # tyre stacks on the outside of each quarter
        x, y, lx, ly = s[i]
        o = SPEC.half + SPEC.shoulder + 3.0
        if far_from(s, x - lx * o, y - ly * o, o - 0.5):
            box(m, (x - lx * o, y - ly * o, 0.0), (1.6, 1.6, 1.2), 0.0, "tyre", "tyre")
