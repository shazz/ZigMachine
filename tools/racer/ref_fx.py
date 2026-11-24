"""Integer maths of the RACER reference renderer (R82 M1): the Python twin of apps/zig/scenes/racer/fx.zig,
cam.zig and clip.zig. Everything is an exact int; `>>` floors like Zig's arithmetic shift, `tdiv` truncates
like `@divTrunc`. Written from the spec, not by translating the Zig line by line, so a disagreement is a bug
in one of the two."""

from __future__ import annotations

import math

M32 = 0xFFFFFFFF


def i32(v: int) -> int:
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def tdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def mulsh16(a: int, b: int) -> int:
    return i32((a * b) >> 16)


_RCP = [(2 * (1 << 25) + (512 + 2 * i + 1)) // (2 * (512 + 2 * i + 1)) for i in range(256)]


def rcp(d: int) -> int:
    if d < 2:
        return 0xFFFFFFFF
    n = 32 - d.bit_length()
    m = (d << n) & M32
    y0 = _RCP[(m >> 23) & 255]
    t = mulsh16(m >> 15, y0)
    y1 = mulsh16(y0, (2 << 16) - t)
    return min((y1 << (n + 1)) >> 16, M32)


_N = 1024
_TABLE = [int(math.floor(math.sin(i * 2.0 * math.pi / _N) * 65536.0 + 0.5)) for i in range(_N + 1)]
_TABLE[0], _TABLE[_N // 4], _TABLE[_N // 2], _TABLE[3 * _N // 4], _TABLE[_N] = 0, 65536, 0, -65536, 0


def sin(a: int) -> int:
    a &= M32
    i, f = a >> 22, (a >> 6) & 0xFFFF
    s0 = _TABLE[i]
    return s0 + (((_TABLE[i + 1] - s0) * f) >> 16)


def cos(a: int) -> int:
    return sin(a + (1 << 30))


NEAR = 1 << 14


def _dist(pl: int, v: list[int]) -> int:
    x, y, z = v
    return (z - NEAR, x + 3 * z, 3 * z - x, y + 3 * z, 3 * z - y)[pl]


def outside(v: list[int]) -> int:
    return sum(1 << pl for pl in range(5) if _dist(pl, v) < 0)


def _cut(pl: int, a: list[int], b: list[int]) -> list[int]:
    lo, hi = (b, a) if tuple(b) < tuple(a) else (a, b)
    dlo, dhi = _dist(pl, lo), _dist(pl, hi)
    t = tdiv(dlo << 16, dlo - dhi)
    out = [l + mulsh16(h - l, t) for l, h in zip(lo, hi)]
    if pl == 0:
        out[2] = NEAR
    return out


def clip(poly: list[list[int]], mask: int) -> list[list[int]]:
    for pl in range(5):
        if not poly or not mask & (1 << pl):
            continue
        out, prev = [], poly[-1]
        dprev = _dist(pl, prev)
        for cur in poly:
            dcur = _dist(pl, cur)
            if (dprev >= 0) != (dcur >= 0):
                out.append(_cut(pl, prev, cur))
            if dcur >= 0:
                out.append(cur)
            prev, dprev = cur, dcur
        poly = out
    return poly
