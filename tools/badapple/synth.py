"""Our own test film for the Bad Apple cart: procedural black / white shapes, 90 frames (three 1 s blocks) at 30 fps.

It pins every path of the format: smooth morphs (delta rows), shapes that move faster than a nibble holds (full-row
fallback), a hard cut in the middle of a block, an all-white and an all-black frame, a row with exactly MAX_TRANS
transitions and one with far more (cut at MAX_TRANS), and a keyframe at each block start. No video is involved.
"""
from __future__ import annotations

import math
from collections.abc import Iterator

from badapple.spans import HEIGHT, MAX_TRANS, WIDTH

FRAMES = 90
CUT = 45  # the hard cut: the picture is inverted and a new shape set starts
WHITE_AT, BLACK_AT = 75, 89
MAX_ROW, OVER_ROW = 100, 101  # rows drawn as stripes from frame 60: MAX_TRANS transitions, and many more


def _disc(px: bytearray, cx: float, cy: float, r: float, val: int) -> None:
    for y in range(max(0, int(cy - r)), min(HEIGHT, int(cy + r) + 1)):
        dx = math.sqrt(max(0.0, r * r - (y - cy) ** 2))
        for x in range(max(0, int(cx - dx)), min(WIDTH, int(cx + dx) + 1)):
            px[y * WIDTH + x] = val


def _stripes(px: bytearray, y: int, x0: int, period: int, n: int) -> None:
    """n transitions starting at x0, one every `period` pixels (white, black, white...), the rest of the row black."""
    row = bytearray(WIDTH)
    for i in range(n):
        x = x0 + i * period
        if x >= WIDTH:
            break
        row[x:] = bytes([(i + 1) & 1]) * (WIDTH - x)
    px[y * WIDTH:(y + 1) * WIDTH] = row


def frame(t: int) -> bytes:
    if t == WHITE_AT:
        return b"\x01" * (WIDTH * HEIGHT)
    if t == BLACK_AT:
        return bytes(WIDTH * HEIGHT)
    px = bytearray(WIDTH * HEIGHT)
    if t < CUT:  # slow morph: a drifting disc, a ring and a thin bar
        _disc(px, 60 + 3 * t, 100 + 30 * math.sin(t / 7), 40, 1)
        _disc(px, 260 - 2 * t, 100, 28, 1)
        _disc(px, 260 - 2 * t, 100, 14, 0)
        for y in range(HEIGHT):
            px[y * WIDTH + 150 + t // 3:y * WIDTH + 153 + t // 3] = b"\x01\x01\x01"
    else:  # after the cut: white ground, a fast black blob (more than 7 px a frame) and a slow one
        px[:] = b"\x01" * (WIDTH * HEIGHT)
        _disc(px, 20 + 6 * (t - CUT), 60, 30, 0)
        _disc(px, 200 + (t - CUT), 150, 22 + (t - CUT) % 9, 0)
    if 60 <= t < WHITE_AT:
        _stripes(px, MAX_ROW, 10, 5, MAX_TRANS)
        _stripes(px, OVER_ROW, 0, 2, 150)
    return bytes(px)


def frames() -> Iterator[bytes]:
    for t in range(FRAMES):
        yield frame(t)
