"""U-Boot `md.l` dumps, parsed strictly, and a stdlib PNG writer (for board_shot.py).

The console runs at 921600 baud with no flow control, so a line can arrive
garbled or not at all. `parse_md` accepts a line only if its address is one the
request asked for and it carries the full number of 8-digit words; a chunk with
any word missing comes back as None and is asked for again.
"""

from __future__ import annotations

import re
import struct
import zlib

LINE = re.compile(r"^([0-9a-f]{8}): ((?:[0-9a-f]{8} ){0,3}[0-9a-f]{8})(?=\s|$)")
WORDS_PER_LINE = 4


def parse_md(text: str, start: int, nwords: int) -> list[int] | None:
    """The `nwords` 32-bit words at `start` from an `md.l start nwords` transcript, or None
    if any is missing or any line is malformed for its place."""
    got: dict[int, list[int]] = {}
    for raw in text.replace("\r", "").split("\n"):
        m = LINE.match(raw.strip())
        if not m:
            continue
        addr = int(m.group(1), 16)
        off = addr - start
        if off < 0 or off % (4 * WORDS_PER_LINE) or off >= 4 * nwords:
            continue  # not a line of this request (an echo, a garbled address)
        words = [int(w, 16) for w in m.group(2).split()]
        want = min(WORDS_PER_LINE, nwords - off // 4)
        if len(words) != want:
            return None  # a word lost or merged: the whole chunk again
        got[off] = words
    out: list[int] = []
    for off in range(0, 4 * nwords, 4 * WORDS_PER_LINE):
        if off not in got:
            return None
        out += got[off]
    return out


def words_to_bytes(words: list[int]) -> bytes:
    return struct.pack(f"<{len(words)}I", *words)


def png_rgb(path: str, width: int, height: int, data: bytes, stride: int = 4) -> None:
    """An RGB PNG from `data`: `stride` bytes a pixel, R, G, B first (picture {0,B,G,R} words
    and the PFB's RGBA bytes both start R, G, B in memory)."""
    rows = []
    for y in range(height):
        row = data[y * width * stride : (y + 1) * width * stride]
        rows.append(b"\x00" + b"".join(row[x * stride : x * stride + 3] for x in range(width)))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
    with open(path, "wb") as f:
        f.write(png + chunk(b"IEND", b""))
