"""The "BAPO" REFERENCE decoder (cart 168): a frame's bytes to its contours, refusing anything malformed, and a whole
file to pictures (ZX0 by tools/badapple/zx0.py, the raster by poly.raster: none of the cart's code)."""
from __future__ import annotations

import struct
from collections.abc import Iterator

from badapple import poly, stream
from badapple.poly_trace import Contour


class _Reader:
    def __init__(self, data: bytes) -> None:
        self.data, self.p = data, 0

    def byte(self) -> int:
        if self.p >= len(self.data):
            raise ValueError("frame ends early")
        self.p += 1
        return self.data[self.p - 1]

    def varint(self) -> int:
        v = self.byte()
        return (v & 0x7F) | self.byte() << 7 if v & 0x80 else v

    def zz(self) -> int:
        v = self.varint()
        return -((v + 1) >> 1) if v & 1 else v >> 1

    def nibbles(self) -> tuple[int, int]:
        b = self.byte()
        if b & 15 == 0 or b >> 4 == 0:
            raise ValueError("a zero nibble")
        return (b & 15) - 8, (b >> 4) - 8


def _vertex(x: int, y: int) -> tuple[int, int]:
    if not (0 <= x <= poly.W and 0 <= y <= poly.H):
        raise ValueError("vertex off the picture")
    return x, y


def _contour(rd: _Reader, op: int, prev: list[Contour] | None) -> Contour:
    if op == poly.NEW:
        n = rd.varint()
        if n < 3:
            raise ValueError("a contour has 3 vertices or more")
        x, y = struct.unpack("<HB", bytes(rd.byte() for _ in range(3)))
        c = [_vertex(x, y)]
        for _ in range(n - 1):
            if rd.data[rd.p:rd.p + 1] == b"\x00":
                rd.byte()
                dx, dy = rd.zz(), rd.zz()
            else:
                dx, dy = rd.nibbles()
            c.append(_vertex(c[-1][0] + dx, c[-1][1] + dy))
        return c
    if op not in (poly.KEEP, poly.DELTA) or prev is None:
        raise ValueError("bad op, or a reference in a block's first frame")
    j = rd.varint()
    if j >= len(prev):
        raise ValueError("reference past the previous frame")
    if op == poly.KEEP:
        return list(prev[j])
    out = []
    for vx, vy in prev[j]:
        dx, dy = rd.nibbles()
        out.append(_vertex(vx + dx, vy + dy))
    return out


def decode_frame(fb: bytes, prev: list[Contour] | None) -> tuple[list[Contour], bool]:
    """(contours, white background). Raises ValueError on a malformed frame or one over the cart's pools."""
    rd = _Reader(fb)
    flags = rd.byte()
    if flags > 1:
        raise ValueError("unknown flags")
    n = rd.varint()
    if n > poly.MAX_CONTOURS:
        raise ValueError("too many contours")
    out = [_contour(rd, rd.byte(), prev) for _ in range(n)]
    if sum(map(len, out)) > poly.MAX_VERTS:
        raise ValueError("too many vertices")
    if rd.p != len(fb):
        raise ValueError("bytes after the frame")
    return out, flags == 1


def iter_frames(data: bytes) -> Iterator[bytes]:
    for raw, n in stream.iter_blocks(data, poly.MAGIC):
        prev = None
        for fb in stream.frames_of_block(raw, 0, n):
            prev, white = decode_frame(fb, prev)
            yield poly.raster(prev, white)
