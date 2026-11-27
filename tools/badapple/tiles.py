"""The "BATL" tile-dictionary format (cart 167): encoder and the REFERENCE decoder the cart's plane is compared with.

A frame is 40 x 25 slots of 8x8 1-bit tiles. A tile is 8 bytes, one a pixel row, the leftmost pixel in bit 7.
Codes: 0 all black, 1 all white, 2 + i the block dictionary's tile i.
A block (raw, before ZX0) is:  u16 n, n tiles (8 bytes each, in order of first use), then its frames, each u16
length + bytes. A frame is a flag byte, then:
  0x01 key       1000 codes, slot order (row-major): a block's first frame, so a block decodes on its own
  0x00 delta     u32 row mask (bit r: tile row r has changes, bits 25+ zero), then per set row (ascending) a
                 5-byte slot mask (slot c of the row is bit c & 7 of byte c >> 3), then one code per set slot
                 (row-major). A code is a byte (< 128) or lo | 0x80 then hi (code = lo + hi * 128).
`hold` (encoder only, lossy): a slot whose new tile differs from the one on screen in at most `hold` pixels is
left alone; 0 is lossless.
"""
from __future__ import annotations

import struct
from collections.abc import Iterator
from pathlib import Path

from badapple import stream

MAGIC = b"BATL"
TW, COLS, ROWS = 8, 40, 25
SLOTS = COLS * ROWS
BLACK, WHITE = bytes(8), b"\xff" * 8
MAX_TILES = 16382  # codes up to 16383: two varint bytes
MAX_RAW, MAX_PACKED = 96 * 1024, 64 * 1024  # the cart's two raw block buffers and its packed one (tiles.zig)
KEY, DELTA = 1, 0
Tiles = list[bytes]


def cut(px: bytes) -> Tiles:
    """The 1000 tiles of a 0/1 picture, slot order."""
    rows = [int(px[y * stream.WIDTH:(y + 1) * stream.WIDTH].translate(_BITS), 2).to_bytes(COLS, "big")
            for y in range(stream.HEIGHT)]
    return [bytes(rows[r * TW + k][c] for k in range(TW)) for r in range(ROWS) for c in range(COLS)]


_BITS = bytes.maketrans(b"\x00\x01", b"01")


def _varint(v: int) -> bytes:
    return bytes([v]) if v < 128 else bytes([0x80 | (v & 0x7F), v >> 7])


def _differs(a: bytes, b: bytes, hold: int) -> bool:
    if a == b:
        return False
    return hold == 0 or sum((x ^ y).bit_count() for x, y in zip(a, b, strict=True)) > hold


class BlockEncoder:
    """Encodes blocks one after the other; `shown` is what the screen holds (it carries across blocks)."""

    def __init__(self, hold: int = 0) -> None:
        self.hold = hold
        self.shown: Tiles = [BLACK] * SLOTS

    def block(self, pictures: list[bytes]) -> bytes:
        codes: dict[bytes, int] = {BLACK: 0, WHITE: 1}
        frames = []
        for i, px in enumerate(pictures):
            tiles = cut(px)
            if i == 0:
                self.shown = tiles
                frames.append(bytes([KEY]) + b"".join(_varint(self._code(codes, t)) for t in tiles))
            else:
                frames.append(self._delta(tiles, codes))
        if len(codes) - 2 > MAX_TILES:
            raise stream.StreamError(f"{len(codes) - 2} tiles in a block, the format holds {MAX_TILES}")
        dict_tiles = sorted((c, t) for t, c in codes.items() if c >= 2)
        return struct.pack("<H", len(dict_tiles)) + b"".join(t for _, t in dict_tiles) + stream.with_lengths(frames)

    @staticmethod
    def _code(codes: dict[bytes, int], tile: bytes) -> int:
        return codes.setdefault(tile, len(codes))

    def _delta(self, tiles: Tiles, codes: dict[bytes, int]) -> bytes:
        changed = [s for s in range(SLOTS) if _differs(tiles[s], self.shown[s], self.hold)]
        rowmask = 0
        for s in changed:
            rowmask |= 1 << (s // COLS)
        out = bytearray([DELTA]) + struct.pack("<I", rowmask)
        for r in range(ROWS):
            if rowmask >> r & 1:
                m = sum(1 << (s - r * COLS) for s in changed if s // COLS == r)
                out += m.to_bytes(5, "little")
        for s in changed:
            self.shown[s] = tiles[s]
            out += _varint(self._code(codes, tiles[s]))
        return bytes(out)


def encode(frames: Iterator[bytes], zx0pack: Path, hold: int = 0) -> tuple[bytes, dict[str, int]]:
    enc = BlockEncoder(hold)
    return stream.encode(MAGIC, frames, enc.block, zx0pack, MAX_RAW, MAX_PACKED)


# ---- the reference decoder


class _Reader:
    def __init__(self, data: bytes) -> None:
        self.data, self.p = data, 0

    def take(self, n: int) -> bytes:
        if self.p + n > len(self.data):
            raise ValueError("frame ends early")
        self.p += n
        return self.data[self.p - n:self.p]

    def code(self, limit: int) -> int:
        v = self.take(1)[0]
        if v & 0x80:
            v = (v & 0x7F) | self.take(1)[0] << 7
        if v >= limit:
            raise ValueError("tile code past the dictionary")
        return v


def decode_frame(fb: bytes, dict_tiles: Tiles, screen: bytearray, first: bool) -> None:
    """Paint one frame into `screen` (64,000 bytes of 0/1). Raises ValueError on a malformed frame."""
    rd, table = _Reader(fb), [BLACK, WHITE, *dict_tiles]
    flag = rd.take(1)[0]
    if flag not in (KEY, DELTA) or first != (flag == KEY):
        raise ValueError("a block starts with a key frame, and only there")
    if flag == KEY:
        slots = list(range(SLOTS))
    else:
        (rowmask,) = struct.unpack("<I", rd.take(4))
        if rowmask >> ROWS:
            raise ValueError("row mask past row 25")
        slots = []
        for r in range(ROWS):
            if rowmask >> r & 1:
                m = int.from_bytes(rd.take(5), "little")
                if m == 0 or m >> COLS:
                    raise ValueError("bad slot mask")
                slots += [r * COLS + c for c in range(COLS) if m >> c & 1]
    for s in slots:
        _paint(screen, s, table[rd.code(len(table))])
    if rd.p != len(fb):
        raise ValueError("bytes after the frame")


def _paint(screen: bytearray, slot: int, tile: bytes) -> None:
    x, y = slot % COLS * TW, slot // COLS * TW
    for k in range(TW):
        b = tile[k]
        screen[(y + k) * stream.WIDTH + x:(y + k) * stream.WIDTH + x + TW] = bytes(b >> (7 - i) & 1 for i in range(TW))


def parse_dict(raw: bytes) -> tuple[Tiles, int]:
    if len(raw) < 2:
        raise ValueError("block too short")
    (n,) = struct.unpack_from("<H", raw)
    if n > MAX_TILES or 2 + 8 * n > len(raw):
        raise ValueError("dictionary overruns its block")
    return [raw[2 + 8 * i:10 + 8 * i] for i in range(n)], 2 + 8 * n


def iter_frames(data: bytes) -> Iterator[bytes]:
    """Every frame's 0/1 picture, decoded from a whole file (ZX0 by tools/badapple/zx0.py, not the cart's code)."""
    screen = bytearray(stream.WIDTH * stream.HEIGHT)
    for raw, n in stream.iter_blocks(data, MAGIC):
        tiles, start = parse_dict(raw)
        for i, fb in enumerate(stream.frames_of_block(raw, start, n)):
            decode_frame(fb, tiles, screen, i == 0)
            yield bytes(screen)
