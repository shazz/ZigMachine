"""Kestrel Racing: a panorama strip -> the cart's `<TRACK>.PAN` file (apps/zig/scenes/racer/panofile.zig, R82 32X look).

    panc.encode(width, rows, pixels, palette, horizon, first, u0=0, colours=24) -> bytes

`pixels` are row-major indices into `palette` (RGB; index 0 = clear, the sky shows), `width` texels a full turn (a power
of two, 256..1024), `horizon` the strip row on the horizon line. The colours are cut to `colours` (the nearest pair by
RGB merged, the rarer into the commoner, until they fit), ordered dark to light (a car's shadow or a smoke puff steps
an entry down or up, which then reads as darker / lighter), and put on the palette entries `first..`: the caller picks
entries no face of the track uses (the 32X import reserves ramps for them). The strip is split where it pays: the
upper part is stored whole, the LOWER part (the sea, a plain) only one period wide when its rows repeat across (the
smallest power of two, >= MIN_LOWER). Holds no data.
"""

from __future__ import annotations

import math
import struct
import zlib

MAGIC = b"KPAN"
VERSION = 1
HEADER = 32
OPAQUE = 1
MIN_W, MAX_W, MAX_ROWS, MAX_LOWER, MIN_LOWER, MAX_COLOURS = 256, 1024, 128, 160, 8, 64
CAR_LO, CAR_HI = 16 + 12 * 8, 16 + 19 * 8
RGB = tuple[int, int, int]


class PanError(ValueError):
    pass


def _luma(c: RGB) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def reduce(pixels: bytes, palette: list[RGB], n: int) -> tuple[list[int], list[RGB]]:
    """Each index -> a new colour index 1..k (k <= n, dark to light; 0 stays clear), and the k colours."""
    used = sorted({p for p in pixels if p})
    count = {i: 0 for i in used}
    for p in pixels:
        if p:
            count[p] += 1
    groups = {}  # distinct RGB -> the source indices drawn with it
    for i in used:
        groups.setdefault(palette[i], []).append(i)
    cols = {c: sum(count[i] for i in ids) for c, ids in groups.items()}
    while len(cols) > n:
        a, b = min(((a, b) for a in cols for b in cols if a < b), key=lambda p: math.dist(*p))
        keep, drop = (a, b) if cols[a] >= cols[b] else (b, a)
        cols[keep] += cols.pop(drop)
        groups[keep] += groups.pop(drop)
    order = sorted(cols, key=_luma)
    remap = [0] * 256
    for k, c in enumerate(order, 1):
        for i in groups[c]:
            remap[i] = k
    return remap, order


def _period(rows: list[bytes]) -> int:
    """The smallest power-of-two period (>= MIN_LOWER) every one of `rows` repeats with."""
    w = len(rows[0])
    p = MIN_LOWER
    while p < w and not all(r == r[:p] * (w // p) for r in rows):
        p *= 2
    return p


def split(texels: bytes, width: int, rows: int, horizon: int) -> tuple[int, int]:
    """The upper part's rows (>= horizon, <= MAX_ROWS) and the lower part's period, for the fewest bytes stored."""
    lines = [texels[r * width:(r + 1) * width] for r in range(rows)]
    best = None
    for s in range(min(horizon, rows), min(rows, MAX_ROWS) + 1):
        if rows - s > MAX_LOWER:
            continue
        p = _period(lines[s:]) if s < rows else 0
        size = s * width + p * (rows - s)
        if best is None or size < best[0]:
            best = (size, s, p)
    if best is None:
        raise PanError(f"{rows} rows do not fit {MAX_ROWS} upper + {MAX_LOWER} lower rows")
    return best[1], best[2]


def crop(width: int, rows: int, pixels: bytes, horizon: int, up: int, low: int) -> tuple[int, bytes, int]:
    """Only the rows a camera can show: `up` above the horizon row, `low` from it down (the cart fills the rest with the
    sky and the far ground). Returns the rows, the texels and the new horizon row."""
    a, b = max(0, horizon - up), min(rows, horizon + low)
    return b - a, pixels[a * width:b * width], horizon - a


def encode(width: int, rows: int, pixels: bytes, palette: list[RGB], horizon: int, first: int, u0: int = 0,
           colours: int = 24) -> bytes:
    if width < MIN_W or width > MAX_W or width & (width - 1) or len(pixels) != width * rows or not 0 <= u0 < width:
        raise PanError(f"a {width} x {rows} strip ({len(pixels)} texels, u0 {u0}): width a power of two 256..1024")
    if not 1 <= colours <= MAX_COLOURS or first < 16 or first + colours > 256 or (first < CAR_HI and first + colours > CAR_LO):
        raise PanError(f"entries {first}..{first + colours - 1}: off the fixed entries, the car ramps and 255")
    remap, cols = reduce(pixels, palette, colours)
    tex = bytes(first - 1 + remap[p] if p else 0 for p in pixels)
    up, period = split(tex, width, rows, horizon)
    lower_rows = rows - up
    lower = b"".join(tex[r * width:r * width + period] for r in range(up, rows))
    body = b"".join(bytes(c) + b"\0" for c in cols) + tex[:up * width] + lower
    flags = OPAQUE if 0 not in tex else 0
    head = struct.pack("<4sII", MAGIC, VERSION, HEADER + len(body))
    head += struct.pack("<IHHHHBBBBHH", zlib.crc32(body), width, up, horizon, u0, len(cols), first, flags, 0,
                        period if lower_rows else 0, lower_rows)
    return head + body


def free_entries(track: bytes, n: int) -> int:
    """The first run of `n` palette entries a track file (trackc's v3 binary) leaves free: on its ramps, off the car ramps,
    used by none of its faces or decals (what the cart's panofile.clash asks)."""
    word = [int.from_bytes(track[4 * i:4 * i + 4], "little") for i in range(32)]
    nf, ni, nramps, faces, inner = word[5], word[6], word[9], word[14], word[15]
    used = {track[faces + 32 * i + 10] for i in range(nf)} | {track[inner + 32 * i + 10] for i in range(ni)}
    for first in range(16, 16 + 8 * nramps - n + 1):
        span = range(first, first + n)
        if not (first < CAR_HI and first + n > CAR_LO) and not used.intersection(span):
            return first
    raise PanError(f"no {n} free entries on the track's {nramps} ramps")


def test_strip(width: int = 256) -> tuple[int, bytes, list[RGB], int]:
    """Our own synthetic panorama (the harness' and the tests'): sky bands over two ranges of rolling hills, a plain
    below the horizon repeating every 16 texels. Returns rows, texels, palette, horizon row."""
    pal = [(0, 0, 0), (60, 110, 200), (110, 160, 230), (60, 90, 70), (90, 130, 80), (150, 140, 100), (170, 160, 120)]
    rows, hz = 40, 28
    px = bytearray()
    for r in range(rows):
        for x in range(width):
            a = 2 * math.pi * x / width
            far, near = 14 + 6 * math.sin(3 * a) + 3 * math.sin(7 * a + 1), 6 + 4 * math.sin(5 * a + 2)
            up = hz - r
            if r >= hz:
                px.append(5 + (x // 8 + r) % 2)
            else:
                px.append(4 if up < near else 3 if up < far else 2 if up < 18 else 1)
    return rows, bytes(px), pal, hz


def main(argv: list[str] | None = None) -> int:
    import argparse
    from pathlib import Path

    ap = argparse.ArgumentParser(description="the synthetic test panorama for a track file, on its free entries")
    ap.add_argument("track", help="the track's .ktrk (its free palette entries are looked up)")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--corrupt", action="store_true", help="flip a texel after the CRC (the harness' refusal case)")
    a = ap.parse_args(argv)
    rows, px, pal, hz = test_strip()
    first = free_entries(Path(a.track).read_bytes(), len(pal) - 1)
    b = bytearray(encode(256, rows, px, pal, hz, first, colours=len(pal) - 1))
    if a.corrupt:
        b[-1] ^= 1
    Path(a.out).write_bytes(bytes(b))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
