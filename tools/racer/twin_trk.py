"""The cart's track-file rules in Python (R82 M7): a twin of apps/zig/scenes/racer/trk.zig `parse` and library.zig's scan
and `load` checks, so the track pack builder refuses a `.KTR` for the reason the cart would, with the same name, before it
goes on a disk or a card. Same checks in the same order; test_racer_trackpack.py pins the constants against the Zig.

    check(raw) -> None, or raises Refused(why): why is the cart's error name (BadCrc, BadBlock, BadMood, TooBig ...)
    raw_len(head, stored) -> library.rawLen: the size a file's first bytes promise, None = "not a track"
"""

from __future__ import annotations

import itertools
import struct
import zlib
from typing import Final

MAGIC: Final = 0x4B52544B
VERSION: Final = 3
HEADER: Final = 128
TILES: Final = 32 * 32
BUCKETS, RAYS = 16, 33
NOT_BAKED: Final = 0xFFFF_FFFF
MAX_RAMPS, MAX_SEG, MAX_GRID, MAX_RBAKE = 30, 256, 8, 8
MOOD_WORD, MOOD_SIZE, SCALE_SIZE = 25, 32, 4
BACKDROPS: Final = 3
BENCH_ONLY, DECAL_NEAR = 1, 2
MAX_CLOCK: Final = (250, 60)
SCALE_LIM: Final = (64, 4096)
LINE_ROOF, LINE_CUE = 1, 0xFF00
MAX_FILE: Final = 1 << 20  # library.MAX_FILE: a track's bytes once depacked
MAX_VERTS, MAX_FACES = 25600, 10240  # library.MAX_VERTS, MAX_FACES
FACE: Final = struct.Struct("<4HBBBB3hHiII")  # trk.Face, 32 bytes
SEG: Final = struct.Struct("<3iHH")  # trk.Seg, 16 bytes
ZX0_MAGIC: Final = b"ZX0!"


class Refused(ValueError):
    """The cart would refuse the file; `why` is its reason's name."""

    def __init__(self, why: str) -> None:
        super().__init__(why)
        self.why = why


def _w(b: bytes, i: int) -> int:
    return int.from_bytes(b[4 * i:4 * i + 4], "little")


def _block(b: bytes, off: int, n: int, size: int, end: int) -> bytes:
    if off < HEADER or off % 4 or end > len(b) or off > end or n * size > end - off:
        raise Refused("BadBlock")
    return b[off:off + n * size]


def raw_len(head: bytes, stored: int) -> int | None:
    """library.rawLen: a ZX0 image's stated length, or a v3 header whose total is the file's size."""
    if len(head) >= 10 and head[:4] == ZX0_MAGIC:
        return int.from_bytes(head[6:10], "little")
    if len(head) < 16 or _w(head, 0) != MAGIC or _w(head, 1) != VERSION:
        return None
    return _w(head, 3) if _w(head, 3) == stored else None


def _mood(b: bytes, at: int, total: int) -> None:
    if at == 0:
        return
    m = _block(b, at, 1, MOOD_SIZE, total)
    if at + MOOD_SIZE != total and at + MOOD_SIZE + SCALE_SIZE != total:
        raise Refused("BadMood")
    ramp, level, flags, backdrop = m[0], m[1], m[2], m[3]
    clock, draw_r, haze, start, strength = m[24:26], m[26], m[27:30], m[30], m[31]
    if ramp >= _w(b, 9) or level > 7 or flags & ~(BENCH_ONLY | DECAL_NEAR) or backdrop >= BACKDROPS:
        raise Refused("BadMood")
    if clock[0] > MAX_CLOCK[0] or clock[1] > MAX_CLOCK[1]:
        raise Refused("BadMood")
    if strength == 0 and (start != 0 or any(haze)):
        raise Refused("BadMood")
    if draw_r != 0 and not 3 <= draw_r <= MAX_RBAKE:
        raise Refused("BadMood")


def _scale(b: bytes, at: int, total: int) -> None:
    if at == 0 or total - at == MOOD_SIZE:
        return
    if total - at != MOOD_SIZE + SCALE_SIZE:
        raise Refused("BadMood")
    s = struct.unpack("<2H", _block(b, at + MOOD_SIZE, 1, SCALE_SIZE, total))
    if any(not SCALE_LIM[0] <= v <= SCALE_LIM[1] for v in s):
        raise Refused("BadMood")


def _head(b: bytes) -> None:
    if len(b) < HEADER:
        raise Refused("Truncated")
    if _w(b, 0) != MAGIC:
        raise Refused("BadMagic")
    if _w(b, 1) != VERSION:
        raise Refused("BadVersion")
    if _w(b, 3) != len(b):
        raise Refused("Truncated")
    if zlib.crc32(b[HEADER:]) != _w(b, 2):
        raise Refused("BadCrc")
    if _w(b, 9) > MAX_RAMPS or _w(b, 7) > MAX_SEG or not 1 <= _w(b, 8) <= MAX_GRID or _w(b, 10) > MAX_RBAKE:
        raise Refused("BadBlock")


def _blocks(b: bytes) -> dict[str, bytes]:
    total, mood_at = len(b), _w(b, MOOD_WORD)
    nv, nf, ni, nseg, ngrid, nramps = (_w(b, k) for k in (4, 5, 6, 7, 8, 9))
    o = [_w(b, k) for k in range(12, 25)]
    out = {"pal": _block(b, o[0], nramps, 4, o[1]), "verts": _block(b, o[1], nv, 6, o[2]),
           "faces": _block(b, o[2], nf, 32, o[3]), "inner": _block(b, o[3], ni, 32, o[4]),
           "tfirst": _block(b, o[4], TILES + 1, 4, o[5])}
    nt = _w(out["tfirst"], TILES)
    out["tfaces"] = _block(b, o[5], nt, 2, o[6])
    _block(b, o[6], 1, BUCKETS * RAYS * 4, o[7])
    out["pvs_index"] = _block(b, o[7], TILES * BUCKETS, 4, o[8])
    if o[9] < o[8]:
        raise Refused("BadBlock")
    out["pvs"] = _block(b, o[8], (o[9] - o[8]) // 2, 2, o[9])
    out["line"] = _block(b, o[9], nseg, 16, o[10])
    _block(b, o[10], ngrid, 16, o[11])
    out["lr"] = _block(b, o[11], nseg, 4, o[12])
    out["cps"] = _block(b, o[12], _w(b, 11), 4, total if mood_at == 0 else mood_at)
    return out


def _u(fmt: str, blob: bytes) -> list[int]:
    return list(struct.unpack(f"<{len(blob) // struct.calcsize(fmt)}{fmt}", blob))


def _check(k: dict[str, bytes]) -> None:
    nv, faces, inner = len(k["verts"]) // 6, list(FACE.iter_unpack(k["faces"])), list(FACE.iter_unpack(k["inner"]))
    for f in faces:
        if not 3 <= f[5] <= 4 or any(v >= nv for v in f[:f[5]]) or f[13] + f[7] > len(inner):  # nv, inner_first + inner_n
            raise Refused("BadBlock")
    if any(not 3 <= f[5] <= 4 or v >= nv for f in inner for v in f[:min(f[5], 4)]):  # (nv 0: no vertex read, as the cart)
        raise Refused("BadBlock")
    tfirst, pvs = _u("I", k["tfirst"]), _u("H", k["pvs"])
    if any(t >= len(faces) for t in _u("H", k["tfaces"])) or any(hi < lo for lo, hi in itertools.pairwise(tfirst)):
        raise Refused("BadBlock")
    line = list(SEG.iter_unpack(k["line"]))
    if len(line) < 3 or any(s[4] & ~(LINE_ROOF | LINE_CUE) for s in line):
        raise Refused("BadBlock")
    if any(a != NOT_BAKED and (a >= len(pvs) or pvs[a] > len(pvs) - a - 1) for a in _u("I", k["pvs_index"])):
        raise Refused("BadBlock")
    if any(v >= nv for v in _u("H", k["lr"])):
        raise Refused("BadBlock")
    cps = _u("I", k["cps"])
    if any(c >= len(line) or (i and c <= cps[i - 1]) for i, c in enumerate(cps)):
        raise Refused("BadBlock")
    if nv > MAX_VERTS or len(faces) > MAX_FACES:
        raise Refused("TooBig")


def check(b: bytes) -> None:
    """trk.parse then library.load's caps, on a file's depacked bytes."""
    if len(b) > MAX_FILE:
        raise Refused("TooBig")
    _head(b)
    at = _w(b, MOOD_WORD)
    _mood(b, at, len(b))
    _scale(b, at, len(b))
    _check(_blocks(b))
