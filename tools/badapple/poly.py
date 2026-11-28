"""The "BAPO" polygon-stream format (cart 168): encoder, and the REFERENCE decoder + rasteriser the cart must match.

A frame is a set of closed contours (integer corners, x 0..320, y 0..200), filled EVEN-ODD over the whole frame:
a pixel is foreground when a ray along its row's centre line crosses an odd number of edges left of its centre.
The rasteriser is integer and exact (raster()): for an edge from (xa, ya) to (xb, yb), ya < yb,
slope = trunc((xb - xa) * 65536 / (yb - ya)), X = xa * 65536 + trunc(slope / 2) at row ya, + slope a row, rows
ya..yb-1; the row's change points are (X + 0x7FFF) >> 16, sorted; colours alternate from the background.
A frame's bytes: flags (bit 0: the background is white; others 0), varint contour count, then per contour an op:
  0 NEW    varint n (3..), u16 x, u8 y, then n - 1 steps: one byte (dx + 8) | (dy + 8) << 4 for dx, dy in -7..7
           (nibbles 1..15), or 0x00 then zigzag varints dx, dy
  1 KEEP   varint j: the previous frame's contour j, unchanged
  2 DELTA  varint j, then one nibble byte a vertex: the previous frame's contour j, each vertex moved by dx, dy
A block's first frame has only NEW contours (a block decodes on its own). varints: < 128 one byte, else
lo | 0x80 then hi. A block is its frames, each u16 length + bytes (stream.py's container).
"""
from __future__ import annotations

import struct
from collections.abc import Iterator
from pathlib import Path

from badapple import poly_trace, stream
from badapple.poly_trace import Contour

MAGIC = b"BAPO"
W, H = stream.WIDTH, stream.HEIGHT
MAX_VERTS, MAX_CONTOURS = 6000, 1500  # a frame's, the cart's pools (poly.zig)
MAX_RAW, MAX_PACKED = 96 * 1024, 64 * 1024
NEW, KEEP, DELTA = 0, 1, 2
EPS = 0.75


def _trunc(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def raster(contours: list[Contour], white_bg: bool) -> bytes:
    """The 0/1 picture of a frame's contours (the cart's rule, see the module notes)."""
    cross: list[list[int]] = [[] for _ in range(H)]
    for c in contours:
        for (x0, y0), (x1, y1) in zip(c, c[1:] + c[:1], strict=True):
            if y0 == y1:
                continue
            (xa, ya), (xb, yb) = ((x0, y0), (x1, y1)) if y0 < y1 else ((x1, y1), (x0, y0))
            slope = _trunc((xb - xa) << 16, yb - ya)
            x = (xa << 16) + _trunc(slope, 2)
            for r in range(ya, yb):
                cross[r].append(min(W, max(0, (x + 0x7FFF) >> 16)))
                x += slope
    out = bytearray()
    bg = 1 if white_bg else 0
    for pts in cross:
        row, x, col = bytearray([bg]) * W, 0, bg
        for p in sorted(pts):
            row[x:p] = bytes([col]) * (p - x)
            x, col = max(x, p), col ^ 1
        row[x:] = bytes([col]) * (W - x)
        out += row
    return bytes(out)


def _varint(v: int) -> bytes:
    return bytes([v]) if v < 128 else bytes([0x80 | (v & 0x7F), v >> 7])


def _zz(d: int) -> bytes:
    return _varint(d << 1 if d >= 0 else (-d << 1) - 1)


def _step(dx: int, dy: int) -> bytes:
    if -7 <= dx <= 7 and -7 <= dy <= 7:
        return bytes([(dx + 8) | (dy + 8) << 4])
    return b"\x00" + _zz(dx) + _zz(dy)


def _new(c: Contour) -> bytes:
    out = bytearray([NEW]) + _varint(len(c)) + struct.pack("<HB", *c[0])
    for a, b in zip(c, c[1:], strict=False):
        out += _step(b[0] - a[0], b[1] - a[1])
    return bytes(out)


def _match(c: Contour, prev: list[Contour]) -> bytes | None:
    """KEEP or DELTA against the previous frame's contour that moved least (every vertex within 7 px), if any."""
    best, bj = None, -1
    for j, p in enumerate(prev):
        if len(p) != len(c):
            continue
        d = [(a[0] - b[0], a[1] - b[1]) for a, b in zip(c, p, strict=True)]
        if all(-7 <= dx <= 7 and -7 <= dy <= 7 for dx, dy in d):
            cost = sum(abs(dx) + abs(dy) for dx, dy in d)
            if best is None or cost < best[0]:
                best, bj = (cost, d), j
    if best is None:
        return None
    if best[0] == 0:
        return bytes([KEEP]) + _varint(bj)
    return bytes([DELTA]) + _varint(bj) + bytes((dx + 8) | (dy + 8) << 4 for dx, dy in best[1])


def shapes(px: bytes, eps: float) -> tuple[list[Contour], bool]:
    """A picture's simplified contours and its background colour (the majority on the border); eps grows by
    0.25 px until the frame fits the cart's pools."""
    border = px[:W] + px[-W:] + bytes(px[y * W] for y in range(H)) + bytes(px[y * W + W - 1] for y in range(H))
    white_bg = 2 * sum(border) > len(border)
    raw = poly_trace.trace(px, 0 if white_bg else 1)
    eps_q = round(eps * 4)
    while True:
        out = [s for s in (poly_trace.simplify(c, eps_q) for c in raw) if s]
        if sum(map(len, out)) <= MAX_VERTS and len(out) <= MAX_CONTOURS:
            return out, white_bg
        eps_q += 1


class BlockEncoder:
    def __init__(self, eps: float = EPS) -> None:
        self.eps = eps

    def frame(self, contours: list[Contour], white_bg: bool, prev: list[Contour] | None) -> bytes:
        out = bytearray([int(white_bg)]) + _varint(len(contours))
        for c in contours:
            m = _match(c, prev) if prev is not None else None
            out += m if m is not None else _new(c)
        return bytes(out)

    def block(self, pictures: list[bytes]) -> bytes:
        frames, prev = [], None
        for px in pictures:
            contours, white_bg = shapes(px, self.eps)
            frames.append(self.frame(contours, white_bg, prev))
            prev = contours
        return stream.with_lengths(frames)


def encode(frames: Iterator[bytes], zx0pack: Path, eps: float = EPS) -> tuple[bytes, dict[str, int]]:
    return stream.encode(MAGIC, frames, BlockEncoder(eps).block, zx0pack, MAX_RAW, MAX_PACKED)
