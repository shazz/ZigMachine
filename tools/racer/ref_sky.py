"""The RACER reference's backdrop (R82 M1, shapes M5 step 2): the panorama strips of apps/zig/scenes/racer/backdrop.zig and
the keyed AFFINE op that draws them above the horizon. Shape 0 (hills) is built there at compile time with f64 sin, the
others at a track change with integer maths; a track's mood block picks one (tools/racer/mood.py)."""

from __future__ import annotations

import math
from functools import cache

from racer import ref_fx as fx

DU = 52429  # 256 * 65536 / 320: a quarter of the 1024-texel strip is the 90 degree view
W, H = 1024, 48
FAR, NEAR, SKYLINE = 12, 13, 14


def _hills() -> bytearray:
    t = bytearray(W * 64)
    for x in range(W):
        a = x * 2.0 * math.pi / W
        far = 18.0 + 8.0 * math.sin(a * 3.0) + 4.0 * math.sin(a * 7.0 + 1.0)
        near = 9.0 + 5.0 * math.sin(a * 5.0 + 2.0) + 2.5 * math.sin(a * 11.0)
        tower = 6.0 + (x // 8) % 5 if (x // 8) % 7 == 3 else 0.0
        for r in range(H):
            up = H - 1 - r
            t[r * W + x] = FAR if up < far else t[r * W + x]
            if up < near + tower:
                t[r * W + x] = SKYLINE if (tower > 0 and up >= near) else NEAR
    return t


def _tri(x: int, period: int, amp: int) -> int:
    p = x % period
    d = 2 * p - period if 2 * p > period else period - 2 * p
    return amp - amp * d // period


def _docks(x: int) -> list[int]:
    c = [0] * H
    stack = 5 + ((((x // 24) * 2654435761) & 0xFFFFFFFF) >> 7) % 9
    cx = x % 128
    leg = 10 <= cx < 13 or 40 <= cx < 43
    for r in range(H):
        up = H - 1 - r
        if up < stack:
            c[r] = FAR
        if up == stack - 1 and x % 6 == 0:
            c[r] = SKYLINE
        if (leg and up < 30) or (26 <= up < 30 and 6 <= cx < 62) or (27 <= up < 29 and 62 <= cx < 92):
            c[r] = NEAR
        if up == 31 and cx in (11, 41):
            c[r] = SKYLINE
    return c


def _peaks(x: int) -> list[int]:
    c = [0] * H
    far = 14 + _tri(x, 256, 16) + _tri(x + 40, 64, 7) + _tri(x + 9, 16, 2)
    near = 6 + _tri(x + 100, 128, 9) + _tri(x, 32, 3)
    for r in range(H):
        up = H - 1 - r
        if up < far:
            c[r] = SKYLINE if (far > 26 and up + 5 >= far) else FAR
        if up < near:
            c[r] = NEAR
    return c


@cache
def strip(shape: int = 0) -> bytes:
    if shape == 0:
        return bytes(_hills())
    t = bytearray(W * 64)
    column = _docks if shape == 1 else _peaks
    for x in range(W):
        for r, v in enumerate(column(x)):
            t[r * W + x] = v
    return bytes(t)


def backdrop(img: bytearray, yaw: int, hz: int, y_min: int, shape: int = 0) -> None:
    """The 48 spans of the strip, rows >= y_min above the horizon row `hz`, texel 0 = transparent."""
    s = strip(shape)
    u0 = ((yaw >> 6) - DU * 160) & fx.M32
    for row in range(H):
        y = hz - H + row
        if y_min <= y < hz:
            for x in range(320):
                v = s[row * W + (((u0 + x * DU) & fx.M32) >> 16 & 1023)]
                if v:
                    img[y * 320 + x] = v
