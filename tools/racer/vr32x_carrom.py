"""LOCAL ONLY: reads the CAR models of a Virtua Racing Deluxe (32X) cartridge dump the user owns (tools/racer/vr32x_car.py).

This file holds NO data and no offsets: every table is FOUND by its shape and cross-checked, as vr32x_rom.py does for the
courses. Everything it decodes is Sega's: keep it out of the repository (the importer writes under a git-ignored directory).

Layout, as decoded (26 Nov, the 68000 side read with rg-dis, the SH-2's copy loop with sh-elf-objdump):
- **Car blocks.** The SH-2 copies ONE block of models per car class into its SDRAM before a race, from a table of
  (start, end) SH-2 ROM addresses whose blocks follow each other (each end is the next start). Found here as the first run of
  at least CLASSES such pairs whose every block starts with a parsable model.
- **A car model** is a tile model's layout (vr32x_rom.py), plus: a polygon whose flags have bit 5 set carries three more
  words after its ids (unknown, skipped).
- **A block**, in file order: the near car, its flat shadow, two more near variants, the cockpit's wheels and dash, the axles
  (front, then rear: each the two wheels of an axle around the origin), then four AI liveries, each a near model, a far model
  and a flat 2-polygon sprite card (ignored).
- **Car palettes.** The race copies a 64-entry palette per class over CRAM entries 32..95, from a table of CLASSES 68000
  pointers that sits right before the palettes it points at, each 128 bytes after the last. Entries 1..31 are a grey ramp
  shared by every course.
"""

from __future__ import annotations

import itertools
import struct
from dataclasses import dataclass

from racer import vr32x_rom as rom32
from racer.vr32x_rom import RGB, Poly, RomError

CLASSES = 3  # the 68000's class index 0..2 (its corner and palette tables have three entries)
NAMES = ("formula", "stock", "prototype")  # named by look: an open-wheel car, a coupe, a closed sports prototype
LIVERIES = 4
CAR_PAL = 64
FIRST = 32  # the car palette's first CRAM entry


@dataclass(frozen=True)
class Model:
    verts: list[tuple[int, int, int]]
    polys: list[Poly]


def model(rom: bytes, at: int) -> tuple[Model, int]:
    """The model at `at` and the offset just past it."""
    nv = struct.unpack_from(">H", rom, at)[0]
    if not 3 <= nv <= 512:
        raise RomError(f"car model at {at:#x}: {nv} vertices")
    verts = [struct.unpack_from(">3h", rom, at + 4 + 6 * i) for i in range(nv)]
    p, polys, prev = at + 4 + 6 * nv, [], None
    while (fl := struct.unpack_from(">H", rom, p)[0]) != rom32.END:
        col, hi, tri = struct.unpack_from(">H", rom, p + 2)[0], fl >> 8, fl & 1
        if hi not in (0, 2, 4, 6) or (hi and prev is None):
            raise RomError(f"car model at {at:#x}: polygon flags {fl:#06x} at {p:#x}")
        n = (3 if tri else 4) if hi == 0 else (1 if tri else 2)
        ids = []
        for k in range(n):
            raw = struct.unpack_from(">H", rom, p + 4 + 2 * k)[0]
            if raw % 16 or raw // 16 >= nv:
                raise RomError(f"car model at {at:#x}: vertex id {raw:#x} (of {nv})")
            ids.append(raw // 16)
        if hi:
            e = rom32.EDGE[hi] % len(prev)
            ids = [prev[(e + 1) % len(prev)], prev[e], *ids]
        polys.append(Poly(ids, col >> 8, col & 0xFF, fl & 0xFF))
        prev, p = ids, p + 4 + 2 * n + (6 if fl & 0x20 else 0)
        if len(polys) > 1024:
            raise RomError(f"car model at {at:#x}: no end mark")
    return Model([tuple(v) for v in verts], polys), p + 2


def _parses(rom: bytes, at: int) -> bool:
    try:
        model(rom, at)
    except (RomError, struct.error):
        return False
    return True


def blocks(rom: bytes) -> list[tuple[int, int]]:
    """The classes' (start, end) ROM offsets: the first run of chained (start, end) pairs of SH-2 ROM addresses."""
    top = rom32.SH2_ROM + len(rom)
    for at in range(0, len(rom) - 8 * CLASSES, 4):
        pairs = [struct.unpack_from(">2I", rom, at + 8 * i) for i in range(CLASSES)]
        if not all(rom32.SH2_ROM <= a < b <= top and b - a <= 0x8000 for a, b in pairs):
            continue
        if any(pairs[i][1] != pairs[i + 1][0] for i in range(CLASSES - 1)):
            continue
        if all(_parses(rom, a - rom32.SH2_ROM) for a, _ in pairs):
            return [(a - rom32.SH2_ROM, b - rom32.SH2_ROM) for a, b in pairs]
    raise RomError("no car block table found")


def walk(rom: bytes, start: int, end: int) -> list[Model]:
    """Every model of a block, in file order (each starts where the last ended, word-aligned)."""
    out, at = [], start
    while at < end:
        m, nxt = model(rom, at)
        out.append(m)
        at = nxt + (nxt & 1)
    if at != end:
        raise RomError(f"car block {start:#x}: the models run past its end")
    return out


def palettes(rom: bytes) -> list[int]:
    """The car palettes' ROM offsets: CLASSES 68000 pointers right before the palettes they point at, 128 bytes apart."""
    for at in range(0, len(rom) - 4 * CLASSES, 2):
        ps = struct.unpack_from(f">{CLASSES}I", rom, at)
        if ps[0] != rom32.ROM68K + at + 4 * CLASSES:
            continue
        if all(b - a == 2 * CAR_PAL for a, b in itertools.pairwise(ps)):
            return [p - rom32.ROM68K for p in ps]
    raise RomError("no car palette table found")


def colours(rom: bytes, cls: int, course: list[RGB]) -> dict[int, RGB]:
    """CRAM index -> RGB as a car of class `cls` sees it: the course palette with the class's car palette over 32..95."""
    out = dict(enumerate(course))
    for i, w in enumerate(struct.unpack_from(f">{CAR_PAL}H", rom, palettes(rom)[cls])):
        out[FIRST + i] = rom32._rgb(w)  # [private-usage] the same CRAM word decode as the courses'
    return out
