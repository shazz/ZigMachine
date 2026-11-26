"""Neon Docks' geometry (R82 M5 step 2), no bpy: a container port at night. Original content (ours).

A flat loop round the yard: a chicane on the quay straight, a warehouse the road runs through (a tunnel), sodium lamps with
their light pools baked onto the asphalt as decals (no run-time light), container stacks in six liveries, three gantry cranes
on the quay. neon_docks_build.py makes the Blender scene from these meshes (Blender axes, Z up).
"""

from __future__ import annotations

import math

from kitgeom import Road, Station, box, decal, far_from, road, spline, stations, turn
from salt_flats_geom import Mesh

POINTS = [(-84, -72), (-20, -80), (48, -76), (86, -64), (96, -36), (88, -6), (96, 24), (92, 58), (66, 78), (18, 80),
          (-34, 78), (-78, 70), (-94, 36), (-96, -36)]
N = 148
SPEC = Road(half=5.5, shoulder=2.0, wall_h=0.7, asphalt=("asphalt_a", "asphalt_b"), shoulder_mat="quay",
            barrier=("barrier_a", "barrier_b"), cam_near=(86, 98))  # the warehouse's segments: the far camera goes near
PALETTE = {
    "ground": (46, 48, 56), "quay": (66, 68, 74), "asphalt_a": (58, 60, 68), "asphalt_b": (48, 50, 58),
    "barrier_a": (196, 160, 40), "barrier_b": (54, 54, 60), "paint": (176, 176, 168), "paint_start": (200, 170, 60),
    "pool": (112, 98, 70), "lamp": (90, 92, 100), "lamp_head": (240, 200, 120),
    "box_red": (150, 46, 40), "box_blue": (40, 70, 140), "box_green": (44, 110, 70), "box_orange": (190, 104, 40),
    "box_grey": (120, 122, 126), "box_teal": (30, 120, 130), "box_top": (86, 88, 94),
    "crane": (180, 60, 40), "shed": (88, 84, 96), "shed_roof": (60, 58, 70), "neon": (220, 70, 170),
}
DUAL = {"barrier_a", "barrier_b"}
BOXES = ("box_red", "box_blue", "box_green", "box_orange", "box_grey", "box_teal")
SUN = (0.5, -0.3, 1.0)  # the yard's floodlights, high: flat faces show their colour, walls a level or three darker
SKY = [6, 8, 22, 46, 34, 78]  # night: ink blue to a purple sodium glow on the horizon
HILLS = [30, 30, 54, 20, 22, 36, 236, 90, 180]  # far stacks, near cranes, neon lamps
SHED = SPEC.cam_near  # the stations the warehouse roofs over (the top straight)


def st() -> list[Station]:
    return stations(spline([(float(x), float(y)) for x, y in POINTS]), N)


def flat() -> tuple[list[float], list[float]]:
    return [0.0] * N, [0.0] * N


def track(m: Mesh, s: list[Station]) -> None:
    z, bank = flat()
    road(m, s, SPEC, z, bank)


def decals(m: Mesh, s: list[Station]) -> None:
    z, bank = flat()
    for i in range(N):
        if i % 2 == 0 and not (i % 12 in (5, 6) or SHED[0] <= i < SHED[1]):
            decal(m, s, SPEC, z, bank, i, (0.15, 0.85), (0.494, 0.506), "paint")
        if i % 12 in (5, 6) and not SHED[0] <= i < SHED[1]:
            decal(m, s, SPEC, z, bank, i, (0.0, 1.0), (0.12, 0.88), "pool")  # a lamp's light pool, baked
    decal(m, s, SPEC, z, bank, 0, (0.2, 0.55), (0.03, 0.97), "paint_start")


def lamps(m: Mesh, s: list[Station]) -> None:
    out = SPEC.half + SPEC.shoulder + 1.2
    for i in range(5, N, 12):
        if SHED[0] <= i < SHED[1]:
            continue
        x, y, lx, ly = s[i]
        side = 1.0 if turn(s, i) < 0 else -1.0  # on the outside of the bend
        px, py = x + side * out * lx, y + side * out * ly
        box(m, (px, py, 0.0), (0.3, 0.3, 6.0), 0.0, "lamp", "lamp")
        box(m, (px - side * 1.2 * lx, py - side * 1.2 * ly, 6.0), (1.4, 1.4, 0.3), math.atan2(ly, lx), "lamp", "lamp_head")


def shed(m: Mesh, s: list[Station]) -> None:
    """The warehouse: walls outside the barriers, a roof over the road (its underside seen from inside), gable ends."""
    edge, h = SPEC.half + SPEC.shoulder + 0.4, 4.5
    rows = []
    for i in range(SHED[0], SHED[1] + 1):
        x, y, lx, ly = s[i]
        p = lambda o, zz: (x + o * lx, y + o * ly, zz)  # noqa: E731
        rows.append([m.v(*p(edge, 0.0), "PROP_FACE"), m.v(*p(edge, h), "PROP_FACE"),
                     m.v(*p(-edge, h), "PROP_FACE"), m.v(*p(-edge, 0.0), "PROP_FACE"),
                     m.v(*p(edge + 1.0, 0.0), "PROP_FACE"), m.v(*p(edge + 1.0, h + 0.8), "PROP_FACE"),
                     m.v(*p(-edge - 1.0, h + 0.8), "PROP_FACE"), m.v(*p(-edge - 1.0, 0.0), "PROP_FACE")])
    for a, b in zip(rows, rows[1:], strict=False):
        m.f([a[0], b[0], b[1], a[1]], "shed")  # inside left, facing the road
        m.f([a[3], a[2], b[2], b[3]], "shed")  # inside right
        m.f([a[1], b[1], b[2], a[2]], "shed_roof")  # the ceiling, facing down
        m.f([a[5], a[6], b[6], b[5]], "shed_roof")  # the roof, facing up
        m.f([a[4], a[5], b[5], b[4]], "shed")  # outside left
        m.f([a[7], b[7], b[6], a[6]], "shed")  # outside right
    for r, sign in ((rows[0], -1), (rows[-1], 1)):  # the entry faces back up the road, the exit forward
        lintel = [r[1], r[5], r[6], r[2]]
        m.f(lintel if sign > 0 else lintel[::-1], "neon")  # the doorway's lit sign over the road


def stack(m: Mesh, x: float, y: float, rot: float, tall: int, k: int) -> None:
    for lvl in range(tall):
        mat = BOXES[(k * 7 + lvl * 3) % len(BOXES)]
        box(m, (x, y, 2.6 * lvl), (6.0, 2.4, 2.6), rot, mat, "box_top" if lvl == tall - 1 else mat)


def yard(m: Mesh, s: list[Station]) -> None:
    clear = SPEC.half + SPEC.shoulder + 5.0
    k = 0
    for gx in range(-60, 64, 15):
        for gy in range(-52, 56, 13):
            x, y = gx + (k % 3) * 1.5, gy
            if far_from(s, x, y, clear):
                stack(m, x, y, 0.0 if (gx // 15) % 2 else math.pi / 2, 1 + (k * 5) % 3, k)
            k += 1
    for x, y in ((110.0, -12.0), (110.0, 2.0), (110.0, 16.0), (116.0, 30.0)):  # the dense quay block by the chicane
        if far_from(s, x, y, clear):
            stack(m, x, y, math.pi / 2, 3, k)
            k += 1


def cranes(m: Mesh) -> None:
    for cx in (-50.0, 0.0, 50.0):
        cy = -100.0
        for dx in (-5.0, 5.0):
            for dy in (-3.0, 3.0):
                box(m, (cx + dx, cy + dy, 0.0), (0.8, 0.8, 14.0), 0.0, "crane", "crane")
        box(m, (cx, cy - 6.0, 14.0), (2.0, 26.0, 1.6), 0.0, "crane", "crane")  # the boom over the water side
        box(m, (cx, cy, 15.6), (4.0, 4.0, 2.0), 0.0, "shed", "shed_roof")  # the cab
