"""The RACER reference's backdrop (R82 M1): the panorama strip of apps/zig/scenes/racer/backdrop.zig (built
there at compile time with f64 sin) and the keyed AFFINE op that draws it above the horizon."""

from __future__ import annotations

import math

from racer import ref_fx as fx

DU = 52429  # 256 * 65536 / 320: a quarter of the 1024-texel strip is the 90 degree view


def strip() -> bytes:
    t = bytearray(1024 * 64)
    for x in range(1024):
        a = x * 2.0 * math.pi / 1024
        far = 18.0 + 8.0 * math.sin(a * 3.0) + 4.0 * math.sin(a * 7.0 + 1.0)
        near = 9.0 + 5.0 * math.sin(a * 5.0 + 2.0) + 2.5 * math.sin(a * 11.0)
        tower = 6.0 + (x // 8) % 5 if (x // 8) % 7 == 3 else 0.0
        for r in range(48):
            up = 47 - r
            t[r * 1024 + x] = 12 if up < far else t[r * 1024 + x]
            if up < near + tower:
                t[r * 1024 + x] = 14 if (tower > 0 and up >= near) else 13
    return bytes(t)


_STRIP = strip()


def backdrop(img: bytearray, yaw: int, hz: int, y_min: int) -> None:
    """The 48 spans of the strip, rows >= y_min above the horizon row `hz`, texel 0 = transparent."""
    u0 = ((yaw >> 6) - DU * 160) & fx.M32
    for row in range(48):
        y = hz - 48 + row
        if y_min <= y < hz:
            for x in range(320):
                v = _STRIP[row * 1024 + (((u0 + x * DU) & fx.M32) >> 16 & 1023)]
                if v:
                    img[y * 320 + x] = v
