"""LOCAL ONLY: reads the track models of a Virtua Racing Deluxe (32X) cartridge dump the user owns (tools/racer/vr32x_import.py).

This file holds NO data: it is a decoder of the layout, found by reading the dump (freds72's 32x_dumper.py only probed it;
the 68000 side's tile lookup is described in the sega-vr-disasm project's analysis). Everything it decodes is Sega's: keep
it out of the repository (the importer writes under a git-ignored directory).

Layout, as decoded:
- **Tile maps.** Per track a 4 KB map of 32 x 32 big-endian longs, row-major (row 0 = the far +z edge), each an SH-2
  address `0x22000000 + ROM offset` of the tile's model, or EMPTY. The 68000 picks the map from a table indexed by the
  track (`track_tile_object_display_list_builder`); the maps are found here by scanning for that shape.
- **A tile model.** u16 vertex count, u16 (unknown: equal to the count or smaller, not needed to draw), the vertices
  (s16 x, y = up, z; 2048 to a tile), then polygons until the word 0x0C00. A polygon is u16 flags, u16 colour (high
  byte = palette index, low byte 0/1: unknown), then u16 vertex ids x16. Flags bit 0 set = a triangle, clear = a quad.
  Flags high byte 0 = a full polygon (3 or 4 ids); 2, 4 or 6 = a STRIP continuation: 1 (triangle) or 2 (quad) new ids,
  the rest the edge it shares with the previous polygon, `a = prev[e], b = prev[e + 1]` with e = last edge (2), edge 2
  (4) or edge 1 (6), giving `[b, a, new...]` (the winding of the previous polygon: checked on every track, convex and
  edge-adjacent for 85-99 % of them, the rest are folds). Flags low byte bits 1-6: unknown (layers / materials).
- **Palettes.** 256 words of 32X CRAM (bit 15 the through bit, then 5-bit B, G, R) per track, 512 bytes apart, from a table
  of 68000 pointers ($88xxxx = ROM + $880000) in the tracks' order: found here by scanning for that shape. (The race copies
  a car palette over entries 0x20..0x5F; the tracks only use 0x20 there, white in both.)
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

EMPTY = 0x2207FFFE
SH2_ROM = 0x22000000
END = 0x0C00
MAP = 0x1000
TRACKS = ("big_forest", "bay_bridge", "acropolis", "highland", "sand_park")  # the maps' order (named by look: see M5_VR.md)
ROM68K = 0x880000
EDGE = {2: -1, 4: 2, 6: 1}  # strip continuation (flags >> 8) -> the shared edge of the previous polygon

RGB = tuple[int, int, int]


class RomError(ValueError):
    pass


@dataclass(frozen=True)
class Poly:
    ids: list[int]  # tile-local vertex indices, in the dump's winding
    colour: int  # palette index
    low: int  # the colour word's low byte (0/1, unknown)
    flags: int  # the flags' low byte (bit 0 = triangle)


@dataclass(frozen=True)
class Tile:
    row: int
    col: int
    verts: list[tuple[int, int, int]]
    polys: list[Poly]


def load(path: Path) -> bytes:
    rom = path.read_bytes()
    if len(rom) < 0x300000 or rom[0x100:0x10A] != b"SEGA 32X U" or rom[0x120:0x126] != b"V.R.DX":
        raise RomError(f"{path}: not a Virtua Racing Deluxe (32X, USA) dump")
    return rom


def maps(rom: bytes) -> list[int]:
    """The ROM offsets of the tile maps, in order: 4 KB-aligned blocks of 1024 longs, each EMPTY or a model address."""
    out = []
    for at in range(0, len(rom) - MAP + 1, MAP):
        g = struct.unpack_from(">1024I", rom, at)
        used = [p for p in g if p != EMPTY]
        if len(used) >= 64 and all(SH2_ROM <= p < SH2_ROM + len(rom) for p in used):
            out.append(at)
    if len(out) != len(TRACKS):
        raise RomError(f"found {len(out)} tile maps, want {len(TRACKS)}")
    return out


def _model(rom: bytes, at: int) -> tuple[list[tuple[int, int, int]], list[Poly]]:
    nv = struct.unpack_from(">H", rom, at)[0]
    verts = [struct.unpack_from(">3h", rom, at + 4 + 6 * i) for i in range(nv)]
    p, polys, prev = at + 4 + 6 * nv, [], None
    while (fl := struct.unpack_from(">H", rom, p)[0]) != END:
        col, hi, tri = struct.unpack_from(">H", rom, p + 2)[0], fl >> 8, fl & 1
        if hi not in (0, 2, 4, 6) or (hi and prev is None):
            raise RomError(f"model at {at:#x}: polygon flags {fl:#06x} at {p:#x}")
        n = (3 if tri else 4) if hi == 0 else (1 if tri else 2)
        ids = []
        for k in range(n):
            raw = struct.unpack_from(">H", rom, p + 4 + 2 * k)[0]
            if raw % 16 or raw // 16 >= nv:
                raise RomError(f"model at {at:#x}: vertex id {raw:#x} (of {nv})")
            ids.append(raw // 16)
        if hi:
            e = EDGE[hi] % len(prev)
            ids = [prev[(e + 1) % len(prev)], prev[e]] + ids
        polys.append(Poly(ids, col >> 8, col & 0xFF, fl & 0xFF))
        prev, p = ids, p + 4 + 2 * n
        if len(polys) > 4096:
            raise RomError(f"model at {at:#x}: no end mark")
    return [tuple(v) for v in verts], polys


def tiles(rom: bytes, track: int) -> list[Tile]:
    g = struct.unpack_from(">1024I", rom, maps(rom)[track])
    return [Tile(i // 32, i % 32, *_model(rom, p - SH2_ROM)) for i, p in enumerate(g) if p != EMPTY]


def _rgb(w: int) -> RGB:
    return ((w & 31) * 255 // 31, ((w >> 5) & 31) * 255 // 31, ((w >> 10) & 31) * 255 // 31)


def palettes(rom: bytes) -> list[int]:
    """ROM offsets of the tracks' palettes: the first run of len(TRACKS) 68000 pointers 512 bytes apart whose palettes
    start with entry 0 transparent (0) and entry 1 the through-bit black (0x8000)."""
    for at in range(0, len(rom) - 4 * len(TRACKS), 2):
        ps = struct.unpack_from(f">{len(TRACKS)}I", rom, at)
        if not all(ROM68K <= p < ROM68K + 0x80000 for p in ps) or any(b - a != 0x200 for a, b in zip(ps, ps[1:], strict=False)):
            continue
        offs = [p - ROM68K for p in ps]
        if all(struct.unpack_from(">2H", rom, o) == (0, 0x8000) for o in offs):
            return offs
    raise RomError("no palette table found")


def palette(rom: bytes, track: int) -> list[RGB]:
    """The track's 256 palette entries as RGB (the through bit dropped)."""
    return [_rgb(w) for w in struct.unpack_from(">256H", rom, palettes(rom)[track])]
