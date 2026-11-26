"""LOCAL ONLY: finds the 68000's course tables in a Virtua Racing Deluxe (32X) dump the user owns (vr32x_import.py, decoded).

This file holds NO data and no offsets: every table is FOUND by its shape and then checked against the others. What the
shapes are was read from the 68000 code (the course setup, the lap check, the start-grid loader):
- **Addresses.** 68000 pointers into the cartridge are $88xxxx (ROM + $880000) or $9xxxxx: a 1 MB bank of the ROM, set by
  the boot code. The bank is the one under which the course table below decodes.
- **The course table.** Per course 5 pointers (20 bytes), in the tile maps' order: the path (s16 x, z per point), the byte
  map (path point -> course index: 0, 1, .. N - 1 for the course's N points, then the pit lane's points mapped back), the
  respawn pairs (2 bytes per course index), and two lines the AI cars drive (s16 x, z, speed cue per point).
- **The surface table.** Per course a (map, base) pointer pair (vr32x_surface.py); a second table of the same shape, zero
  but for the course with a crossing, is the upper deck. A pair is accepted when the path's points land in polygons that
  map back to their own course index.
- **The start grid.** Per course 16 poses of 4 s16 (x, y, z, heading), the player's first, the 15 AI cars after; a run is
  accepted when all 16 lie on the course's road.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

LO, BANKED, BANK = 0x880000, 0x900000, 0x100000
MIN_POINTS = 64
RECORD = 20
GRID_CARS = 16


class TableError(ValueError):
    pass


class Rom:
    def __init__(self, data: bytes, bank: int = 1) -> None:
        self.data, self.bank = data, bank

    def at(self, addr: int) -> int:
        """The ROM offset of a 68000 address (raises outside the cartridge)."""
        if LO <= addr < BANKED:
            off = addr - LO
        elif BANKED <= addr < BANKED + BANK:
            off = self.bank * BANK + addr - BANKED
        else:
            raise TableError(f"address {addr:#x} is not in the cartridge")
        if off >= len(self.data):
            raise TableError(f"address {addr:#x} is past the dump")
        return off

    def ok(self, addr: int) -> bool:
        try:
            self.at(addr)
        except TableError:
            return False
        return True


@dataclass(frozen=True)
class Course:
    path: list[tuple[int, int]]  # the course's N points (course index order); the pit lane's follow in `pit`
    pit: list[tuple[int, int, int]]  # (x, z, course index) of the pit lane's extra points
    lines: list[list[tuple[int, int, int]]]  # the two AI lines of the table: (x, z, speed cue) per course index
    bmap: list[int]  # path point -> course index (the course's points, then the pit lane's)


def _course(rom: Rom, ptrs: tuple[int, ...]) -> Course | None:
    path_a, bmap_a, resp_a, line_a, line_b = ptrs
    if not all(rom.ok(p) for p in ptrs) or not resp_a < bmap_a < path_a:
        return None
    m = path_a - bmap_a
    b = rom.data[rom.at(bmap_a):rom.at(bmap_a) + m]
    n = max(b) + 1 if b else 0
    if n < MIN_POINTS or m < n or list(b[:n]) != list(range(n)):
        return None
    if any(rom.data[rom.at(resp_a) + 2 * i] != i for i in range(n)):  # lane 0 of the respawn pairs is the point itself
        return None
    pts = [struct.unpack_from(">2h", rom.data, rom.at(path_a) + 4 * i) for i in range(m)]
    lines = [[struct.unpack_from(">3h", rom.data, rom.at(a) + 6 * i) for i in range(n)] for a in (line_a, line_b)]
    return Course(pts[:n], [(*pts[i], b[i]) for i in range(n, m)], lines, list(b))


def courses(data: bytes, count: int) -> tuple[Rom, list[Course]]:
    """The first run of `count` course records (4-byte aligned) that decode under one bank."""
    for bank in range(len(data) // BANK):
        rom = Rom(data, bank)
        for at in range(0, min(len(data), BANKED - LO) - RECORD * count, 4):
            first = struct.unpack_from(">5I", data, at)
            if not all(BANKED <= p < BANKED + BANK for p in first):
                continue
            got = [_course(rom, struct.unpack_from(">5I", data, at + RECORD * k)) for k in range(count)]
            if all(got):
                return rom, got  # type: ignore[return-value]  # [narrowing] all() checked every entry
    raise TableError("no course table found")
