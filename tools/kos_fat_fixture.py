#!/usr/bin/env python3
"""A FAT12 floppy image for KOS's desktop proofs (docs/KOS_FAT.md): an Atari 720 KB layout (TOS's
BPB: 9 sectors, 2 per cluster, 112 root entries, a BRA.S at 0 and no 55 AA), written here byte by
byte, the same on every run and every box (fixed times, read as UTC). No mkfs.fat or mtools: the gate
runs where they are not installed; tools/tests/test_kos_fat.py holds the image against KOS's reader
and, where mtools is installed, against mtools. The root holds a program (DEMO.WSM: any cart's
wasm), two data files and two folders, one nested; with --rv, DEMO.RV beside it (KOS F3b).
Image(label, sectors) is the writer tools/kos_c_image.py and fpga/tools/kos_rv.py use too.

    python3 tools/kos_fat_fixture.py OUT.st [CART.wasm] [--rv RV_FILE]
"""

from __future__ import annotations

import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAMP = 1_793_000_000  # 2026-10-26 07:33:20 UTC: every entry's time, so the image never changes
SPC, RESERVED, FATS, ROOT_ENTRIES = 2, 1, 2, 112
CLUSTER = SPC * 512


def dos_time() -> tuple[int, int]:
    t = time.gmtime(STAMP)
    return (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2), ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday


def short(name: str) -> bytes:
    base, _, ext = name.upper().partition(".")
    assert 0 < len(base) <= 8 and len(ext) <= 3, name
    return base.ljust(8).encode() + ext.ljust(3).encode()


def entry(name: bytes, attr: int, cluster: int, size: int) -> bytes:
    tm, dt = dos_time()
    return struct.pack("<11sBBBHHHHHHHI", name, attr, 0, 0, tm, dt, dt, 0, tm, dt, cluster, size)


class Image:
    """Files and folders written in order: each takes the next free clusters (one chain, unfragmented).
    `sectors`: the disk's size (1440: the Atari 720 KB floppy); the FAT is sized to it."""

    def __init__(self, label: str, sectors: int = 1440) -> None:
        self.sectors = sectors
        self.spf = 1
        while (sectors - RESERVED - FATS * self.spf - ROOT_ENTRIES // 16) // SPC + 2 > self.spf * 512 * 2 // 3:
            self.spf += 1
        self.root_at = RESERVED + FATS * self.spf
        self.data_at = self.root_at + ROOT_ENTRIES * 32 // 512
        self.clusters = (sectors - self.data_at) // SPC
        assert self.clusters < 4085, "a FAT12 disk"
        self.b = bytearray(sectors * 512)
        self.fat = [0xFF9, 0xFFF] + [0] * self.clusters
        self.next = 2
        self.dirs: dict[str, tuple[int, int]] = {"": (0, 0)}  # path -> (first cluster, entries used)
        self.bpb(label)
        self.add_entry("", label.ljust(11).encode(), 0x08, 0, 0)  # the volume label: DISK INFO's name

    def bpb(self, label: str) -> None:
        b = self.b
        b[0:3] = b"\x60\x38\x90"  # TOS: a BRA.S; no 55 AA at 510
        b[3:11] = b"KOSDISK "
        struct.pack_into("<HBHBHHBHHHII", b, 11, 512, SPC, RESERVED, FATS, ROOT_ENTRIES, self.sectors, 0xF9, self.spf, 9, 2, 0, 0)
        struct.pack_into("<BBBI11s8s", b, 36, 0, 0, 0x29, 0x4B4F5331, label.ljust(11).encode(), b"FAT12   ")

    def at(self, cluster: int) -> int:
        return (self.data_at + (cluster - 2) * SPC) * 512

    def alloc(self, n: int) -> int:
        first = self.next
        assert first + max(n, 1) <= self.clusters + 2, "the disk is full"
        for c in range(first, first + n):
            self.fat[c] = c + 1 if c + 1 < first + n else 0xFFF
        self.next += n
        return first

    def add_entry(self, parent: str, name: bytes, attr: int, cluster: int, size: int) -> None:
        first, used = self.dirs[parent]
        if first == 0:
            assert used < ROOT_ENTRIES, "the root is full"
            at = self.root_at * 512 + used * 32
        else:
            assert used < CLUSTER // 32, f"{parent} is full (one cluster a folder)"
            at = self.at(first) + used * 32
        self.b[at : at + 32] = entry(name, attr, cluster, size)
        self.dirs[parent] = (first, used + 1)

    def write(self, path: str, data: bytes) -> None:
        parent, _, name = path.rpartition("/")
        n = -(-len(data) // CLUSTER)
        first = self.alloc(n) if n else 0
        if n:
            self.b[self.at(first) : self.at(first) + len(data)] = data
        self.add_entry(parent, short(name), 0x20, first, len(data))

    def mkdir(self, path: str) -> None:
        parent, _, name = path.rpartition("/")
        first = self.alloc(1)
        self.add_entry(parent, short(name), 0x10, first, 0)
        self.dirs[path] = (first, 0)
        self.add_entry(path, b".          ", 0x10, first, 0)
        self.add_entry(path, b"..         ", 0x10, self.dirs[parent][0], 0)

    def bytes(self) -> bytes:
        fat = bytearray(self.spf * 512)
        for i in range(0, len(self.fat) - 1, 2):
            v = self.fat[i] | (self.fat[i + 1] << 12)
            fat[i * 3 // 2 : i * 3 // 2 + 3] = v.to_bytes(3, "little")
        for k in range(FATS):
            at = (RESERVED + k * self.spf) * 512
            self.b[at : at + len(fat)] = fat
        return bytes(self.b)


def build(out: Path, cart: Path, rv: Path | None = None) -> None:
    img = Image("KOS DISK")
    img.write("DEMO.WSM", cart.read_bytes())
    if rv is not None:
        img.write("DEMO.RV", rv.read_bytes())
    img.write("README.TXT", b"KOS reads real floppies.\r\n" * 40)
    img.write("PIC.PI1", bytes(range(256)) * 125)
    img.mkdir("GAMES")
    img.mkdir("GAMES/LEVELS")
    img.write("GAMES/SAVE.DAT", b"\x01\x02" * 900)
    img.write("GAMES/LEVELS/LEVEL1.MAP", b"#" * 5000)
    out.write_bytes(img.bytes())


if __name__ == "__main__":
    args = sys.argv[1:]
    rv = None
    if "--rv" in args:
        i = args.index("--rv")
        rv, args = Path(args[i + 1]), args[:i] + args[i + 2 :]
    if not args:
        sys.exit(__doc__)
    build(Path(args[0]), Path(args[1]) if len(args) > 1 else ROOT / "docs/demo-tutorial.wasm", rv)
