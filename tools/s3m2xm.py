"""Convert a ScreamTracker 3 module (.s3m) to a FastTracker 2 module (.xm).

    uv run python tools/s3m2xm.py in.s3m out.xm [--drop 6,7,8,9]

Why: the console has an XM player and no S3M player, and a converter is far
less code to trust than a second player. The output is an Amiga-frequency XM
(S3M pitches and slides are Amiga periods), one single-sample instrument per
S3M sample with no envelope (so key-off cuts, as ST3's ^^ does), the S3M
speed and tempo as the XM's. --drop removes tracks (enabled S3M channels,
numbered from 0) for a player with fewer voices than the song; by default
every track is kept. Lost in conversion, and printed: per-channel panning,
global volume other than 64, and any effect XM has no equivalent for.
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import s3m_effects  # noqa: E402  (a sibling tool module, not a package)
import s3m_read  # noqa: E402

TRACKER = b"s3m2xm (ZigMachine) "  # 20 bytes: says it is a conversion


def order_map(orders: list[int]) -> tuple[list[int], dict[int, int]]:
    """The XM order list (skip markers removed) and raw index -> XM index."""
    out, index = [], {}
    for raw, pat in enumerate(orders):
        index[raw] = len(out)
        if pat != s3m_read.MARKER:
            out.append(pat)
    return out, index


def tune(c2spd: int) -> tuple[int, int]:
    """C2SPD as (relative note, finetune in 1/128 semitone): C-4 plays at c2spd Hz."""
    total = round(12 * 128 * math.log2(max(c2spd, 1) / 8363))
    return total >> 7, total & 127


def xm_cell(c: s3m_read.Cell, track: int, fx: s3m_effects.EffectMapper) -> bytes:
    note = 0
    if c.note == s3m_read.CUT:
        note = 97
    elif c.note < s3m_read.CUT:
        note = (c.note >> 4) * 12 + (c.note & 15) + 1
        note = note if 1 <= note <= 96 else 0
    vol = 0x10 + c.vol if c.vol >= 0 else 0
    eff, param = fx.convert(track, c.eff, c.param)
    fields = [note, c.inst, vol, eff, param]
    flag = 0x80 | sum(1 << i for i, v in enumerate(fields) if v)
    return bytes([flag] + [v for v in fields if v])


def xm_pattern(rows: list, keep: list[int], fx: s3m_effects.EffectMapper) -> bytes:
    body = b"".join(xm_cell(row[t], t, fx) for row in rows for t in keep)
    return struct.pack("<IBHH", 9, 0, len(rows), len(body)) + body


def xm_instrument(s: s3m_read.Sample) -> bytes:
    name = s.name.encode("latin-1")[:22].ljust(22, b"\0")
    if not s.pcm:
        return struct.pack("<I", 29) + name + bytes([0]) + struct.pack("<H", 0)
    head = struct.pack("<I", 263) + name + bytes([0]) + struct.pack("<HI", 1, 40)
    head += bytes(96 + 48 + 48 + 14) + struct.pack("<HH", 0, 0)  # map, envelopes off, no fadeout
    head = head.ljust(263, b"\0")
    rel, ft = tune(s.c2spd)
    looped = s.loop_end > s.loop_start
    sh = struct.pack("<III", len(s.pcm), s.loop_start if looped else 0, s.loop_end - s.loop_start if looped else 0)
    sh += struct.pack("<BbBBbB", s.volume, ft - 128 if ft > 127 else ft, 1 if looped else 0, 128, rel, 0)
    sh += name
    return head + sh + delta(s.pcm)


def delta(pcm: bytes) -> bytes:
    out, prev = bytearray(len(pcm)), 0
    for i, v in enumerate(pcm):
        out[i] = (v - prev) & 0xFF
        prev = v
    return bytes(out)


def xm_header(song: s3m_read.Song, orders: list[int], channels: int) -> bytes:
    h = b"Extended Module: " + song.title.encode("latin-1")[:20].ljust(20, b"\0") + b"\x1a" + TRACKER
    h += struct.pack("<HI", 0x0104, 276)
    h += struct.pack("<8H", len(orders), 0, channels, len(song.patterns), len(song.samples), 0,
                     max(song.speed, 1), max(song.tempo, 32))
    return h + bytes(orders).ljust(256, b"\0")


def convert(data: bytes, drop: set[int]) -> tuple[bytes, list[str]]:
    """The XM image and the list of what the conversion lost."""
    song = s3m_read.read(data)
    keep = [t for t in range(len(song.channels)) if t not in drop]
    orders, index = order_map(song.orders)
    fx = s3m_effects.EffectMapper(index)
    out = xm_header(song, orders, len(keep))
    out += b"".join(xm_pattern(rows, keep, fx) for rows in song.patterns)
    out += b"".join(xm_instrument(s) for s in song.samples)
    lost = [f"dropped tracks {sorted(drop)}"] if drop else []
    lost.append(f"track panning {''.join(song.pans[t] for t in keep)} (XM has no channel pan)")
    if song.global_volume != 64:
        lost.append(f"global volume {song.global_volume} (not 64)")
    lost += [f"effect {k} x{n}" for k, n in sorted(fx.dropped.items())]
    return out, lost


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--drop", default="", help="tracks to remove, e.g. 6,7,8,9 (default: none)")
    a = ap.parse_args()
    drop = {int(t) for t in a.drop.split(",") if t.strip()}
    xm, lost = convert(a.src.read_bytes(), drop)
    a.dst.write_bytes(xm)
    print(f"{a.dst}: {len(xm)} bytes")
    for line in lost:
        print(f"  lost: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
