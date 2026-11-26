"""LOCAL ONLY: the 68000's surface map of a Virtua Racing Deluxe (32X) course (tools/racer/vr32x_import.py, decoded mode).

This file holds NO data: it decodes a layout found by reading the 68000 code of the user's own dump (the tile lookup, the
point-in-polygon test and the surface dispatch). Everything it reads is Sega's: nothing decoded is ever committed.

The layout, as decoded:
- **Positions.** The 68000 keeps x and z as s16 world units, half a model unit (so 128 to one of our units). The world is
  64 x 64 cells of 512 units from -16384; a cell's index is `row * 64 + col`.
- **The map.** Per course a pair (map, base): the map is 64 x 64 u16 word offsets (row-major), the cell's list is at
  `base + 2 * offset`. A list is an s16 count - 1 (negative: an empty cell), then that many 28-byte polygon records.
- **A polygon record.** u16 edge code, four edges of 4 bytes, the height plane (3 x s16), then four bytes: the surface
  (low nibble the class, bits 6-7 the timing gate 1..3), the flags (bit 0: the layer switch, see below), the course's
  heading (a byte, 256 to a turn), the path point (an index into the course's path table).
- **An edge** takes 3 bits of the code, first bit the most significant: `a` (the line is x = f(z), else z = f(x)), `b` (a
  constant, else a slope), `s` (the inner side). A slope edge is `line = (u * k + (c << 9)) >> 9` over the cell-local
  coordinate u (twice the offset in the cell, 0..1022); the point is inside when it is on the inner side of all four.
- **Layers.** One course has a second map pair (the upper deck of its crossing): a car whose polygon has flags bit 0 looks
  up in that map until it reaches a polygon without the bit.
- **Classes.** 0 is solid; 1, 4 and 13 are road (13 the pits); 2, 3 and 8 are three off-road classes (each slows the car).
  A point in no polygon is solid too: the walls are not stored, they are the edge of the polygons' union.
"""

from __future__ import annotations

import struct
from collections.abc import Callable
from dataclasses import dataclass

CELL = 512
ORIGIN = 16384
GRID = 64
RECORD = 28
ROAD = frozenset({1, 4, 13})
OFFROAD = frozenset({2, 3, 8})
WORLD_PER_UNIT = 128  # 68000 world units to one of ours (a model unit is 2 world units; ours is 256 model units)


class SurfaceError(ValueError):
    pass


@dataclass(frozen=True)
class Poly:
    edges: tuple[tuple[int, int, int], ...]  # (3 code bits, k, c) x 4
    plane: tuple[int, int, int]  # the height: (a * u + b * v + (c << 5)) >> 6 (>> 5 when flags bit 7 is set)
    surface: int  # the class (low nibble) and the gate (bits 6-7)
    flags: int
    heading: int
    point: int  # index into the course's path table (its byte map gives the course index)

    @property
    def cls(self) -> int:
        return self.surface & 15

    @property
    def gate(self) -> int:
        return self.surface >> 6

    def height(self, u: int, v: int) -> int:
        a, b, c = self.plane
        return (a * u + b * v + (c << 5)) >> (5 if self.flags & 0x80 else 6)


def _side(code: int, u: int, v: int, k: int, c: int) -> bool:
    """One edge: `u`, `v` are the cell-local x, z (doubled)."""
    across, const, inner = code >> 2 & 1, code >> 1 & 1, bool(code & 1)
    if not across:  # a bound on z: z = f(x), or a constant x
        if const:
            return (u >= k) if inner else (u < k)
        line = (u * k + (c << 9)) >> 9
        return (v < line) if inner else (v >= line)
    if const:  # a bound on x: x = f(z), or a constant z
        return (v < k) if inner else (v >= k)
    line = (v * k + (c << 9)) >> 9
    return (u >= line) if inner else (u < line)


def inside(poly: Poly, u: int, v: int) -> bool:
    return all(_side(code, u, v, k, c) for code, k, c in poly.edges)


class SurfaceMap:
    """One map pair over the ROM bytes, `at` the ROM offset of a 68000 address (vr32x_tables.Rom.at)."""

    def __init__(self, rom: bytes, at: Callable[[int], int], map_addr: int, base_addr: int) -> None:
        self.rom, self.at, self.map, self.base = rom, at, map_addr, base_addr
        self._cells: dict[int, list[Poly]] = {}

    def cell(self, row: int, col: int) -> list[Poly]:
        i = row * GRID + col
        if i not in self._cells:
            self._cells[i] = self._read(i) if 0 <= row < GRID and 0 <= col < GRID else []
        return self._cells[i]

    def _read(self, i: int) -> list[Poly]:
        off = struct.unpack_from(">H", self.rom, self.at(self.map + 2 * i))[0]
        a = self.at(self.base + 2 * off)
        n = struct.unpack_from(">h", self.rom, a)[0]
        if n > 63:
            raise SurfaceError(f"cell {i}: {n + 1} polygons")
        return [_poly(self.rom, a + 2 + RECORD * r) for r in range(n + 1)]

    def find(self, x: int, z: int) -> Poly | None:
        row, col = (z + ORIGIN) // CELL, (x + ORIGIN) // CELL
        u, v = ((x + ORIGIN) % CELL) * 2, ((z + ORIGIN) % CELL) * 2
        return next((p for p in self.cell(row, col) if inside(p, u, v)), None)


def _poly(rom: bytes, a: int) -> Poly:
    code = struct.unpack_from(">H", rom, a)[0]
    edges = tuple(((code >> (13 - 3 * e)) & 7, *struct.unpack_from(">2h", rom, a + 2 + 4 * e)) for e in range(4))
    surface, flags, heading, point = rom[a + 0x18:a + 0x1C]
    plane = struct.unpack_from(">3h", rom, a + 0x12)
    return Poly(edges, plane, surface, flags, heading, point)  # type: ignore[arg-type]  # [tuple-size] 4 edges, 3 words


class Layered:
    """A course's surface: the main map and, for a crossing, the upper deck's, chosen as the 68000 does."""

    def __init__(self, main: SurfaceMap, upper: SurfaceMap | None = None) -> None:
        self.main, self.upper = main, upper

    def find(self, x: int, z: int, up: bool = False) -> Poly | None:
        first = self.upper if up and self.upper else self.main
        got = first.find(x, z)
        if got is None and self.upper is not None:
            got = (self.main if first is self.upper else self.upper).find(x, z)
        return got

    def walk(self, pts: list[tuple[int, int]]) -> list[Poly | None]:
        """The polygons under a sequence of points, carrying the layer switch along (a car driving them in order)."""
        up, out = False, []
        for x, z in pts:
            p = self.find(x, z, up)
            out.append(p)
            if p is not None and self.upper is not None:
                up = bool(p.flags & 1)
        return out
