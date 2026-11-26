"""The "BASP" row-transition span-delta format: encoder, and the REFERENCE decoder the cart's plane is compared with.

A frame is 200 rows of up to MAX_TRANS transition x positions (a row starts black; every transition flips the colour).
A frame's bytes, against the previous frame's rows (the keyframe, a block's first frame, has no previous):
  0x00..0x7F       skip 1..128 unchanged rows
  0x80|k, nibbles  a row with the same k transitions: dx -7..+7 each, two a byte (low nibble first), nibble = dx + 8
  0xC0|k, varints  a full row: k transitions, each one byte (< 128) or lo|0x80 then hi (x = lo + hi * 128)
A block is GOP frames, each as u16 length + bytes, ZX0-packed; the file is the header, then per block
<u32 packed, u32 raw, u16 frames> and the packed bytes.
"""
from __future__ import annotations

import struct
from collections.abc import Iterator

from badapple import zx0

WIDTH, HEIGHT, MAX_TRANS, GOP = 320, 200, 62, 30
HEADER = struct.Struct("<4sHHHHHH")  # BASP, w, h, fps, total frames, blocks, gop
BLOCK = struct.Struct("<IIH")
Rows = list[list[int]]


def row_transitions(row: bytes) -> list[int]:
    """The x of every colour change in a row of 0/1 pixels (a leading white pixel is a transition at 0). More than
    MAX_TRANS changes are cut there: the rest of the row keeps the last colour (the encoder's one lossy rule)."""
    out, cur = [], 0
    for x, px in enumerate(row):
        if px != cur:
            out.append(x)
            cur = px
            if len(out) == MAX_TRANS:
                break
    return out


def frame_rows(pixels: bytes) -> Rows:
    return [row_transitions(pixels[y * WIDTH:(y + 1) * WIDTH]) for y in range(HEIGHT)]


def paint(rows: Rows) -> bytes:
    """The 0/1 picture a set of rows decodes to."""
    out = bytearray()
    for tr in rows:
        row, x, col = bytearray(WIDTH), 0, 0
        for t in tr:
            if t > x:
                row[x:t] = bytes([col]) * (t - x)
                x = t
            col ^= 1
        row[x:] = bytes([col]) * (WIDTH - x)
        out += row
    return bytes(out)


def _varint(x: int) -> bytes:
    return bytes([x]) if x < 128 else bytes([0x80 | (x & 0x7F), x >> 7])


def _delta_row(cur: list[int], prev: list[int]) -> bytes | None:
    if len(cur) != len(prev) or not cur:
        return None
    dxs = [c - p for c, p in zip(cur, prev)]
    if any(abs(d) > 7 for d in dxs):
        return None
    dxs.append(0)  # an odd count: the last high nibble is padding (0 = unused: dx + 8 is 1..15)
    out = bytes([0x80 | len(cur)])
    return out + bytes((dxs[i + 1] + 8) << 4 | (dxs[i] + 8) if i + 1 < len(cur) else dxs[i] + 8 for i in range(0, len(cur), 2))


def encode_frame(rows: Rows, prev: Rows | None) -> bytes:
    out, y = bytearray(), 0
    while y < HEIGHT:
        if prev is not None and rows[y] == prev[y]:
            run = 1
            while y + run < HEIGHT and run < 128 and rows[y + run] == prev[y + run]:
                run += 1
            out.append(run - 1)
            y += run
            continue
        delta = None if prev is None else _delta_row(rows[y], prev[y])
        out += delta if delta is not None else bytes([0xC0 | len(rows[y])]) + b"".join(_varint(x) for x in rows[y])
        y += 1
    return bytes(out)


def encode_block(frames: list[Rows]) -> bytes:
    """One block's raw bytes (before ZX0): the first frame is a keyframe, the rest deltas."""
    out, prev = bytearray(), None
    for rows in frames:
        fb = encode_frame(rows, prev)
        out += struct.pack("<H", len(fb)) + fb
        prev = rows
    return bytes(out)


def pack_stream(blocks: list[tuple[bytes, int, bytes]], total: int, fps: int) -> bytes:
    """blocks: (raw, frames in it, ZX0! container)."""
    out = bytearray(HEADER.pack(b"BASP", WIDTH, HEIGHT, fps, total, len(blocks), GOP))
    for raw, n, packed in blocks:
        out += BLOCK.pack(len(packed), len(raw), n) + packed
    return bytes(out)


def decode_frame(fb: bytes, state: Rows) -> None:
    """Apply one frame's bytes to `state` (200 rows, edited in place). Raises ValueError on a malformed frame."""
    p = y = 0
    while y < HEIGHT:
        if p >= len(fb):
            raise ValueError("frame ends before row 200")
        tag, p = fb[p], p + 1
        k = tag & 0x3F
        if tag < 0x80:
            y += tag + 1
        elif tag < 0xC0:
            if not 0 < k <= MAX_TRANS or len(state[y]) != k or p + (k + 1) // 2 > len(fb):
                raise ValueError("bad delta row")
            for i in range(k):
                nib = fb[p + i // 2] >> (4 * (i & 1)) & 15
                state[y][i] += nib - 8
                if not 0 <= state[y][i] < WIDTH:
                    raise ValueError("transition out of range")
            p += (k + 1) // 2
            y += 1
        else:
            if k > MAX_TRANS:
                raise ValueError("too many transitions")
            row = []
            for _ in range(k):
                v, p = fb[p] & 0x7F, p + 1
                if fb[p - 1] & 0x80:
                    v, p = v | fb[p] << 7, p + 1
                if v >= WIDTH:
                    raise ValueError("transition out of range")
                row.append(v)
            state[y] = row
            y += 1
    if y != HEIGHT:
        raise ValueError("frame overshoots row 200")


def iter_rows(data: bytes) -> Iterator[Rows]:
    """Every frame's rows, decoded from a whole file exactly as the cart does (ZX0 by tools/badapple/zx0.py)."""
    magic, w, h, _fps, total, nblocks, _gop = HEADER.unpack_from(data)
    if magic != b"BASP" or (w, h) != (WIDTH, HEIGHT):
        raise ValueError("not a BASP 320x200 stream")
    state: Rows = [[] for _ in range(HEIGHT)]
    pos, seen = HEADER.size, 0
    for _ in range(nblocks):
        plen, rlen, n = BLOCK.unpack_from(data, pos)
        raw = zx0.depack(data[pos + BLOCK.size:pos + BLOCK.size + plen])
        pos += BLOCK.size + plen
        if len(raw) != rlen:
            raise ValueError("block raw length mismatch")
        q = 0
        for _ in range(n):
            (flen,) = struct.unpack_from("<H", raw, q)
            decode_frame(raw[q + 2:q + 2 + flen], state)
            q += 2 + flen
            seen += 1
            yield state
    if seen != total:
        raise ValueError("frame count mismatch")
