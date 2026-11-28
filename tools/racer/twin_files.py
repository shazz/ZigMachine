"""The cart's car-file and panorama-file rules in Python (R82 M7): twins of apps/zig/scenes/racer/carfile.zig `parse` (and
cars.zig's size cap) and panofile.zig `parse` + `clash`, for the track pack builder. Same checks, same order, the cart's
error names (twin_trk.Refused); test_racer_trackpack.py pins the constants against the Zig.

    car(raw)               a `.KCR`, v1 (one model) or v2 (a set)
    pan(raw, track=None)   a `.PAN`; with its track's depacked bytes also `clash` (its entries on the track's ramps, unused)
"""

from __future__ import annotations

import struct
import zlib
from typing import Final

from racer.twin_trk import FACE, Refused

KCAR: Final = 0x5241434B
CAR_HEADER, MAX_MODELS, CAR_VERTS, CAR_FACES, CAR_FILE = 64, 5, 256, 256, 32 * 1024
PALETTE, FLAG_SHADOW, MAX_SHADOW = 1, 0x10, 16
SHADOW, LOD1 = 4, 5  # carfile.Part: wheels, hull, cabin, wing, shadow, lod1
KPAN: Final = 0x4E41504B
PAN_HEADER, MIN_W, MAX_W, MAX_ROWS, MAX_LOWER, MIN_LOWER, MAX_COLOURS, OPAQUE = 32, 256, 1024, 128, 160, 8, 64, 1
PIXEL = 2  # panofile.PIXEL: a texel a pixel
CAR_LO, CAR_HI = 16 + 12 * 8, 16 + 19 * 8


def _w(b: bytes, i: int) -> int:
    return int.from_bytes(b[4 * i:4 * i + 4], "little")


def _pow2(v: int) -> bool:
    return v > 0 and v & (v - 1) == 0


def _parts(end: list[int], faces: list[tuple[int, ...]], nv: int) -> None:
    def rng(i: int) -> tuple[int, int]:
        return (0 if i == 0 else end[i - 1], end[i])

    if rng(1)[1] - rng(1)[0] == 0 or rng(LOD1)[1] - rng(LOD1)[0] == 0:
        raise Refused("BadParts")
    s0, s1 = rng(SHADOW)
    if not 1 <= s1 - s0 <= MAX_SHADOW:
        raise Refused("BadParts")
    for i, f in enumerate(faces):
        if not 3 <= f[5] <= 4 or f[14] != 0 or f[7] != 0 or any(v >= nv for v in f[:4]):
            raise Refused("BadFace")  # no debug shades, no decals; all four ids are read
        if bool(f[4] & FLAG_SHADOW) != (s0 <= i < s1):
            raise Refused("BadParts")


def _model(b: bytes) -> int:
    """One v1 record at the start of b; its length."""
    if len(b) < CAR_HEADER:
        raise Refused("Truncated")
    if _w(b, 0) != KCAR:
        raise Refused("BadMagic")
    if _w(b, 1) != 1:
        raise Refused("BadVersion")
    nv, nf = _w(b, 2), _w(b, 3)
    if nv == 0 or nv > CAR_VERTS or nf > CAR_FACES or _w(b, 9) != nf:
        raise Refused("BadBlock")
    vbytes = (nv * 6 + 3) // 4 * 4
    n = CAR_HEADER + vbytes + nf * 32
    if n > len(b):
        raise Refused("Truncated")
    if zlib.crc32(b[CAR_HEADER:n]) != _w(b, 11):
        raise Refused("BadCrc")
    end, last = [], 0
    for i in range(6):
        x = _w(b, 4 + i)
        if x < last or x > nf:
            raise Refused("BadParts")
        end.append(x)
        last = x
    _parts(end, list(FACE.iter_unpack(b[CAR_HEADER + vbytes:n])), nv)
    return n


def car(b: bytes) -> None:
    if len(b) > CAR_FILE:
        raise Refused("TooBig")  # cars.zig: the car buffer
    if len(b) < CAR_HEADER:
        raise Refused("Truncated")
    if _w(b, 0) != KCAR:
        raise Refused("BadMagic")
    if _w(b, 1) == 1:
        if _model(b) != len(b):
            raise Refused("Truncated")
        return
    if _w(b, 1) != 2:
        raise Refused("BadVersion")
    n = _w(b, 2)
    if not 1 <= n <= MAX_MODELS or _w(b, 3) & ~PALETTE:
        raise Refused("BadBlock")
    if zlib.crc32(b[CAR_HEADER:]) != _w(b, 11):
        raise Refused("BadCrc")
    if b[48] > 3 or b[49] | b[50] | b[51] or any(x and not (chr(x).isupper() or chr(x).isdigit() or x == 32) for x in b[52:64]):
        raise Refused("BadBlock")  # carfile.tag: the class + 1, padding, the name
    at = CAR_HEADER
    for _ in range(n):
        at += _model(b[at:])
    if at != len(b):
        raise Refused("Truncated")


def _pan_size(b: bytes) -> tuple[int, int, int, int, int, int]:
    w, rows, hz, u0 = struct.unpack_from("<4H", b, 16)
    n, first, flags, pad = b[24], b[25], b[26], b[27]
    lw, lr = struct.unpack_from("<2H", b, 28)
    if not (MIN_W <= w <= MAX_W and _pow2(w) and 1 <= rows <= MAX_ROWS):
        raise Refused("BadSize")
    if hz > rows + lr or u0 >= w or flags & ~(OPAQUE | PIXEL) or pad != 0:
        raise Refused("BadSize")
    if (lw == 0) != (lr == 0) or lr > MAX_LOWER or (lw != 0 and not (MIN_LOWER <= lw <= w and _pow2(lw))):
        raise Refused("BadSize")
    if not 1 <= n <= MAX_COLOURS or first < 16 or first + n > 256 or (first < CAR_HI and first + n > CAR_LO):
        raise Refused("BadColours")
    if len(b) != PAN_HEADER + 4 * n + w * rows + lw * lr:
        raise Refused("BadSize")
    return w, rows, n, first, flags, lw * lr


def pan(b: bytes, track: bytes | None = None) -> None:
    if len(b) < PAN_HEADER:
        raise Refused("Truncated")
    if _w(b, 0) != KPAN:
        raise Refused("BadMagic")
    if _w(b, 1) != 1:
        raise Refused("BadVersion")
    if _w(b, 2) != len(b):
        raise Refused("Truncated")
    if zlib.crc32(b[PAN_HEADER:]) != _w(b, 3):
        raise Refused("BadCrc")
    _, _, n, first, flags, _ = _pan_size(b)
    for t in b[PAN_HEADER + 4 * n:]:
        if (t == 0 and flags & OPAQUE) or (t != 0 and not first <= t < first + n):
            raise Refused("BadTexel")
    if track is not None:
        _clash(first, n, track)


def _clash(first: int, n: int, t: bytes) -> None:
    """panofile.clash: the entries lie on the track's ramps and no face or decal of it uses them."""
    if first + n > 16 + 8 * _w(t, 9):
        raise Refused("Clash")
    for k in (14, 15):  # the faces' block, then the inner faces' (each ends where the next begins)
        for f in FACE.iter_unpack(t[_w(t, k):_w(t, k + 1)]):
            if first <= f[6] < first + n:
                raise Refused("Clash")
