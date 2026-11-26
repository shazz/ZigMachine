"""RACER reference camera (R82): the flyby's lap v0 pose (apps/zig/scenes/racer/cam.zig lapPose) and the camera zones
(apps/zig/scenes/racer/zone.zig, M5 finish), in the cart's integers. ref_render.py and walk.py fly the lap through it.

A racing-line entry whose `segment` word has bit ROOF runs under a roof; there the far camera blends to the near one:
at segment i, d = segments to the nearest roof segment j (j - i ahead, i - j - BEHIND past it), weight = (RAMP + 1 - d) /
(RAMP + 1) of the way, clamped, Q16, interpolated between two segments by the fraction.
"""

from __future__ import annotations

from typing import Any

from racer import ref_fx as fx
from racer.ref_fx import mulsh16

BACK, HEIGHT = (6 << 16, 3 << 16, 0), ((5 << 16) // 2, (3 << 16) // 2, (3 << 16) // 4)
PITCH = (0x06000000, 0x04000000, 0x01000000)
LAP = 720
ROOF, RAMP, BEHIND = 1, 2, 2
ONE = 1 << 16


def zone_at(line: list[tuple], i: int) -> int:
    best = RAMP + 1
    for k in range(-(BEHIND + RAMP), RAMP + 1):
        if line[(i + k) % len(line)][4] & ROOF:
            best = min(best, k if k >= 0 else max(0, -k - BEHIND))
    return (RAMP + 1 - best) * ONE // (RAMP + 1)


def zone_weight(line: list[tuple], s: int) -> int:
    """zone.weight: Q16 of the way from the far camera to the near one at line position s (Q16 segments)."""
    i, fr = (s >> 16) % len(line), s & 0xFFFF
    a, b = zone_at(line, i), zone_at(line, (i + 1) % len(line))
    return a + (((b - a) * fr) >> 16)


def _i32(v: int) -> int:
    return ((v + (1 << 31)) & 0xFFFFFFFF) - (1 << 31)


def blend(far: tuple[int, int, int], near: tuple[int, int, int], w: int) -> list[int]:
    return [a + _i32(((b - a) * w) >> 16) for a, b in zip(far, near, strict=True)]


def lap_pose(t: Any, frame: int, pov: int) -> tuple[list[int], int, int]:  # WHY: Any = a ref_render.Track (which imports this)
    f = frame % LAP
    s = (f * len(t.line) << 16) // LAP
    i, fr = s >> 16, s & 0xFFFF
    a, b = t.line[i], t.line[(i + 1) % len(t.line)]
    dy = ((b[3] - a[3] + 0x8000) & 0xFFFF) - 0x8000
    yaw = ((a[3] + ((dy * fr) >> 16)) & 0xFFFF) << 16
    pos = [a[k] + mulsh16(b[k] - a[k], fr) for k in range(3)]
    o = [BACK[pov], HEIGHT[pov], _i32(PITCH[pov])]
    if pov == 0:
        o = blend(tuple(o), (BACK[1], HEIGHT[1], PITCH[1]), zone_weight(t.line, s))
    pos[0] -= mulsh16(o[0], fx.sin(yaw))
    pos[2] -= mulsh16(o[0], fx.cos(yaw))
    pos[1] += o[1]
    return pos, yaw, o[2] & 0xFFFFFFFF


def pov_at(frame: int) -> int:  # cam.povAt: far, near, cockpit by thirds of the lap
    return min((frame % LAP) // (LAP // 3), 2)
