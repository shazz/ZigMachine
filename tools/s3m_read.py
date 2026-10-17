"""Read a ScreamTracker 3 module (.s3m) into plain Python data, for s3m2xm.py.

Only what the XM player can carry is read: 8-bit mono PCM samples (refused
otherwise, never guessed), the order list, and the 64-row patterns as cells per
track. A "track" is an enabled S3M channel; tracks are numbered in channel
order, so track k is the k-th enabled channel.
"""
import struct
from dataclasses import dataclass, field

EMPTY, CUT = 255, 254  # note bytes: no note, ^^ (note cut)
MARKER, END = 254, 255  # order bytes: skip marker, end of song


@dataclass
class Sample:
    name: str
    pcm: bytes  # signed 8-bit
    volume: int  # 0..64
    c2spd: int  # Hz at C-4
    loop_start: int = 0
    loop_end: int = 0  # 0 = no loop


@dataclass
class Cell:
    note: int = EMPTY
    inst: int = 0
    vol: int = -1  # -1 = no volume column
    eff: int = 0  # 1 = A ... 26 = Z
    param: int = 0


@dataclass
class Song:
    title: str
    speed: int
    tempo: int
    global_volume: int
    orders: list  # raw order bytes up to END, markers included
    samples: list
    channels: list  # enabled S3M channel numbers (track k = channels[k])
    pans: list  # per track: 'L' or 'R' (channel setting < 8 is left)
    patterns: list = field(default_factory=list)  # [pattern][row][track] -> Cell


def u16(d: bytes, o: int) -> int:
    return struct.unpack_from("<H", d, o)[0]


def read(d: bytes) -> Song:
    if len(d) < 0x60 or d[0x2C:0x30] != b"SCRM":
        raise ValueError("not an S3M (no SCRM signature)")
    ordnum, insnum, patnum, _flags, _cwt, ffi = struct.unpack_from("<6H", d, 0x20)
    settings = d[0x40:0x60]
    channels = [c for c in range(32) if settings[c] < 16]
    o = 0x60
    raw_orders = list(d[o:o + ordnum])
    orders = raw_orders[:raw_orders.index(END)] if END in raw_orders else raw_orders
    ins_pp = struct.unpack_from(f"<{insnum}H", d, o + ordnum)
    pat_pp = struct.unpack_from(f"<{patnum}H", d, o + ordnum + 2 * insnum)
    song = Song(
        title=d[:28].split(b"\0")[0].decode("latin-1"),
        speed=d[0x31], tempo=d[0x32], global_volume=d[0x30],
        orders=orders, samples=[read_sample(d, p * 16, ffi) for p in ins_pp],
        channels=channels, pans=["L" if settings[c] < 8 else "R" for c in channels])
    song.patterns = [read_pattern(d, p * 16, channels) for p in pat_pp]
    return song


def read_sample(d: bytes, b: int, ffi: int) -> Sample:
    name = d[b + 48:b + 76].split(b"\0")[0].decode("latin-1")
    if d[b] != 1:  # 0 = empty slot (an AdLib instrument is refused below)
        if d[b] != 0:
            raise ValueError(f"instrument '{name}': AdLib instruments are not supported")
        return Sample(name, b"", d[b + 28], 8363)
    length, ls, le = struct.unpack_from("<3I", d, b + 16)
    flags = d[b + 31]
    if flags & 6:
        raise ValueError(f"sample '{name}': 16-bit or stereo samples are not supported")
    if d[b + 30] != 0:
        raise ValueError(f"sample '{name}': packed (ADPCM) samples are not supported")
    off = ((d[b + 13] << 16) | u16(d, b + 14)) * 16
    raw = d[off:off + length]
    if len(raw) != length:
        raise ValueError(f"sample '{name}': runs past the end of the file")
    pcm = bytes((x - 128) & 0xFF for x in raw) if ffi == 2 else bytes(raw)
    loop = flags & 1 and le > ls
    return Sample(name, pcm, min(d[b + 28], 64), struct.unpack_from("<I", d, b + 32)[0],
                  ls if loop else 0, min(le, length) if loop else 0)


def read_pattern(d: bytes, b: int, channels: list) -> list:
    rows = [[Cell() for _ in channels] for _ in range(64)]
    if b == 0:
        return rows  # parapointer 0: an empty pattern
    track = {c: k for k, c in enumerate(channels)}
    o, r = b + 2, 0
    while r < 64:
        w = d[o]
        o += 1
        if w == 0:
            r += 1
            continue
        c = Cell()
        if w & 32:
            c.note, c.inst = d[o], d[o + 1]
            o += 2
        if w & 64:
            c.vol = min(d[o], 64)
            o += 1
        if w & 128:
            c.eff, c.param = d[o], d[o + 1]
            o += 2
        if (w & 31) in track:
            rows[r][track[w & 31]] = c
    return rows
