"""The block container the Bad Apple variants share (tiles "BATL", polygons "BAPO"; spans "BASP" has its own copy in
spans.py, the first of them): a 16-byte header <magic, w, h, fps, total frames, blocks, gop>, then per block
<u32 packed, u32 raw, u16 frames> and the ZX0! container of the raw block. ZX0 packing is zig-out/bin/zx0pack's;
unpacking is tools/badapple/zx0.py's (not the cart's code). Also the film sources every encoder reads."""
from __future__ import annotations

import struct
import subprocess
import tempfile
from collections.abc import Callable, Iterable, Iterator
from pathlib import Path

from badapple import spans, zx0

WIDTH, HEIGHT, FPS, GOP = spans.WIDTH, spans.HEIGHT, 30, spans.GOP
HEADER = struct.Struct("<4sHHHHHH")
BLOCK = struct.Struct("<IIH")


class StreamError(ValueError):
    pass


def zx0_pack(zx0pack: Path, raw: bytes) -> bytes:
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "in.bin", Path(td) / "out.zx0"
        src.write_bytes(raw)
        subprocess.run([str(zx0pack), str(src), str(dst)], check=True, stdout=subprocess.DEVNULL)
        return dst.read_bytes()


def encode(magic: bytes, frames: Iterable[bytes], encode_block: Callable[[list[bytes]], bytes], zx0pack: Path,
           max_raw: int, max_packed: int) -> tuple[bytes, dict[str, int]]:
    """A whole stream from 0/1 pictures, GOP frames a block. A block over the cart's buffers is refused (StreamError)."""
    blocks: list[tuple[bytes, int, bytes]] = []
    group: list[bytes] = []
    total = 0

    def flush() -> None:
        raw = encode_block(group)
        packed = zx0_pack(zx0pack, raw)
        if len(raw) > max_raw or len(packed) > max_packed:
            raise StreamError(f"block {len(blocks)}: {len(raw)} raw / {len(packed)} packed bytes, the cart holds "
                              f"{max_raw} / {max_packed}")
        blocks.append((raw, len(group), packed))
        group.clear()

    for px in frames:
        group.append(px)
        total += 1
        if len(group) == GOP:
            flush()
    if group:
        flush()
    if not blocks:
        raise StreamError("no frames")
    out = bytearray(HEADER.pack(magic, WIDTH, HEIGHT, FPS, total, len(blocks), GOP))
    for raw, n, packed in blocks:
        out += BLOCK.pack(len(packed), len(raw), n) + packed
    stats = {"frames": total, "blocks": len(blocks), "bytes": len(out), "max_raw": max(len(b[0]) for b in blocks),
             "max_packed": max(len(b[2]) for b in blocks), "raw_total": sum(len(b[0]) for b in blocks)}
    return bytes(out), stats


def iter_blocks(data: bytes, magic: bytes) -> Iterator[tuple[bytes, int]]:
    """(raw block, frames in it) for every block, depacked by zx0.py; refuses a wrong header, length or count."""
    if len(data) < HEADER.size:
        raise StreamError("short header")
    m, w, h, fps, total, nblocks, gop = HEADER.unpack_from(data)
    if m != magic or (w, h) != (WIDTH, HEIGHT) or fps == 0 or gop == 0:
        raise StreamError(f"not a {magic.decode()} {WIDTH}x{HEIGHT} stream")
    pos, seen = HEADER.size, 0
    for _ in range(nblocks):
        if pos + BLOCK.size > len(data):
            raise StreamError("truncated block header")
        plen, rlen, n = BLOCK.unpack_from(data, pos)
        raw = zx0.depack(data[pos + BLOCK.size:pos + BLOCK.size + plen])
        pos += BLOCK.size + plen
        if len(raw) != rlen or n == 0:
            raise StreamError("block raw length / frame count mismatch")
        seen += n
        yield raw, n
    if seen != total:
        raise StreamError("frame count mismatch")


def frames_of_block(raw: bytes, start: int, n: int) -> Iterator[bytes]:
    """The n frames' bytes of a raw block, each stored as u16 length + bytes from `start`."""
    q = start
    for _ in range(n):
        if q + 2 > len(raw):
            raise StreamError("block ends before its frames")
        (flen,) = struct.unpack_from("<H", raw, q)
        if q + 2 + flen > len(raw):
            raise StreamError("frame overruns its block")
        yield raw[q + 2:q + 2 + flen]
        q += 2 + flen
    if q != len(raw):
        raise StreamError("bytes after the last frame")


def with_lengths(frames: Iterable[bytes]) -> bytes:
    return b"".join(struct.pack("<H", len(f)) + f for f in frames)


def spans_film(path: Path) -> Iterator[bytes]:
    """The real film as cart 166 shows it: every frame of a LOCAL spans.bin painted to 0/1 pixels (never committed)."""
    for rows in spans.iter_rows(path.read_bytes()):
        yield spans.paint(rows)
