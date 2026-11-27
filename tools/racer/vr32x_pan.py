"""LOCAL ONLY: the per-course panorama backdrop of a Virtua Racing Deluxe (32X) cartridge dump the user owns.

This file holds NO data: it is the decoder of the layout, found by reading the 68000 code; every table is located by the
shape of the code that reads it, and refused when absent. Everything it decodes is Sega's: keep it out of the repository.

Layout, as decoded:
- **Mega Drive plane B.** The 32X pixels are in front (index 0 / the through bit let the VDP show), the backdrop is the MD
  VDP's plane B: 128 x 32 cells (VDP reg 16 = 3), nametable at VRAM $C000 (reg 4), backdrop colour = CRAM entry 0
  (reg 7 = 0). The course load DMAs 28 nametable rows ($E00 words): the strip is 1024 x 224.
- **Tiles.** Kosinski (LZSS): a 16-bit little-endian descriptor read LSB first and reloaded the moment it runs out;
  1 = a literal byte; 00 + 2 bits n = copy n + 2 from the offset byte - 256; 01 = two bytes lo, hi: offset
  ((hi & $F8) << 5 | lo) - $2000, count hi & 7 + 2, or when 0 a third byte: 0 ends, 1 does nothing, n copies n + 1.
- **Nametable.** Enigma: bytes inline-bit-count, PCCVH flag mask, words increment and common; then an MSB-first stream of
  packets 0 t nnnn (t 0: the increment word n + 1 times, +1 each; t 1: the common word) and 1 tt nnnn (00 an inline word
  repeated, 01 inline +1 each, 10 inline -1 each, 11 n + 1 separate inline words; 11 with n = 15 ends). An inline word
  is the enabled flag bits (P, CC, V, H) then the index bits. The job's base word (the VRAM tile the tiles were DMAed
  to) is added to every word.
- **Palette.** Four MD CRAM lines (64 words, 0000BBB0GGG0RRR0) per course, from a table of 68000 pointers.
- **Yaw.** Each race frame: hscroll_B = (camera heading + view offset) asr 6, negated in mirror mode. The heading is a
  16-bit angle, so one turn = 65536 >> 6 = 1024 = the plane's width (the wrap is exact). Screen column x shows strip
  column (x - hscroll) mod 1024.
- **Pitch.** vscroll_B = clamp((camera pitch + view tilt) asr 8, -8, 16) - 8: -8 at the start and when level. Screen line
  y shows strip row y + vscroll; rows < 0 are plane rows 30-31, which the course load never writes (unknown).
- **Horizon.** HORIZON is NOT a ROM value: row 88 (cell row 11) is where Big Forest, Bay Bridge and Acropolis paint a
  full-width haze row; Highland's lake and Sand Park's ground start within a cell of it.
"""

from __future__ import annotations

from dataclasses import dataclass

from racer import vr32x_sigs
from racer.vr32x_mdpack import PackError, enigma, kosinski, signed
from racer.vr32x_sigs import Sigs

RGB = tuple[int, int, int]
COURSES = 5
COLS, ROWS = 128, 28  # plane B's width in cells, and the rows the course load DMAs
HORIZON = 88
WINDOW = 0x80000  # the 68000's fixed ROM window at $880000

# The code that reads each table is found by its shape: the shapes (TILE_LIST, NAME_LIST, KOS_JOBS, ENI_JOBS, CRAM_LIST)
# are bytes of the cartridge's code, kept in the LOCAL signatures file (vr32x_sigs.py), never here.


PanError = PackError  # one error for the decode, its streams included


@dataclass(frozen=True)
class Pan:
    width: int  # pixels for one full turn (the wrap)
    height: int
    pixels: bytes  # row-major, an index into palette; 0 = transparent (sky shows)
    palette: list[RGB]  # entry 0 unused
    sky: RGB  # the VDP backdrop colour (CRAM entry 0)
    horizon: int  # the strip row on the horizon when level (see the module docstring)


def _rom(addr: int) -> int:
    """A 68000 address -> ROM offset: the $880000 window, or the $900000 bank (bank 1 = ROM $100000)."""
    if 0x880000 <= addr < 0x880000 + WINDOW:
        return addr - 0x880000
    if 0x900000 <= addr < 0xA00000:
        return addr - 0x800000
    raise PanError(f"address {addr:#x} is not in the cartridge")


def _find(rom: bytes, sigs: Sigs, name: str, at: int | None = None) -> int:
    """The ROM offset of the first (even) match of the code shape `name`, or check it matches exactly at `at`."""
    pat = vr32x_sigs.pattern(sigs[name])
    if at is not None:
        if not pat.match(rom, at):
            raise PanError(f"no code shape {name} at {at:#x}")
        return at
    for m in pat.finditer(rom, 0, min(len(rom), WINDOW)):
        if m.start() % 2 == 0:
            return m.start()
    raise PanError(f"no code shape {name} in the dump")


def _u16(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 2], "big")


def _u32(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 4], "big")


def strip(tiles: bytes, names: list[int], first: int, cols: int, rows: int) -> list[int]:
    """Plane cells -> row-major pixels, each line * 16 + colour; `first` = the tile number of tiles[0]."""
    if len(names) < cols * rows:
        raise PanError(f"nametable has {len(names)} cells, want {cols * rows}")
    out = [0] * (cols * 8 * rows * 8)
    for i, w in enumerate(names[: cols * rows]):
        t = (w & 0x7FF) - first
        if not 0 <= t < len(tiles) // 32:
            raise PanError(f"cell {i}: tile {w & 0x7FF} not loaded")
        hf, vf, line = w >> 11 & 1, w >> 12 & 1, (w >> 13 & 3) * 16
        for y in range(8):
            row = tiles[t * 32 + 4 * (7 - y if vf else y) :][:4]
            px = [c for byte in row for c in (byte >> 4, byte & 15)]
            at = ((i // cols) * 8 + y) * cols * 8 + (i % cols) * 8
            out[at : at + 8] = [line + c if c else 0 for c in (px[::-1] if hf else px)]
    return out


def _md(w: int) -> RGB:
    return ((w >> 1 & 7) * 255 // 7, (w >> 5 & 7) * 255 // 7, (w >> 9 & 7) * 255 // 7)


def _jobs(rom: bytes, sigs: Sigs) -> list[tuple[int, int, int, int]]:
    """Per course: (tile stream, nametable stream, nametable base word, CRAM) ROM offsets."""
    tl, nl = _find(rom, sigs, "TILE_LIST"), _find(rom, sigs, "NAME_LIST")
    kd, ed = _find(rom, sigs, "KOS_JOBS", _rom(_u32(rom, tl + 14))), _find(rom, sigs, "ENI_JOBS", _rom(_u32(rom, nl + 16)))
    ktab, etab = kd + 12 + signed(rom[kd + 13], 8), ed + 14 + signed(rom[ed + 15], 8)
    ttab, ntab = tl + 6 + signed(_u16(rom, tl + 6), 16), nl + 8 + signed(_u16(rom, nl + 8), 16)
    ctab = _rom(_u32(rom, _find(rom, sigs, "CRAM_LIST") + 6))
    out = []
    for c in range(COURSES):
        kj, ej = _u32(rom, ttab + 4 * c), _u32(rom, ntab + 4 * c)
        if not (1 <= kj <= 8 and 1 <= ej <= 25):
            raise PanError(f"course {c}: job ids {kj}, {ej} out of range")
        rec = etab + 10 * (ej - 1)
        out.append((_rom(_u32(rom, ktab + 8 * kj)), _rom(_u32(rom, rec)), _u16(rom, rec + 8), _rom(_u32(rom, ctab + 4 * c))))
    return out


def _pan(cells: list[int], cram: list[int]) -> Pan:
    used = sorted(set(cells) - {0})
    slot = {v: k + 1 for k, v in enumerate(used)}
    pixels = bytes(slot.get(v, 0) for v in cells)
    return Pan(COLS * 8, ROWS * 8, pixels, [(0, 0, 0)] + [_md(cram[v]) for v in used], _md(cram[0]), HORIZON)


def panoramas(rom: bytes, sigs: Sigs) -> list[Pan]:
    """Every course's panorama; `sigs` the code shapes (vr32x_sigs.load: the local file)."""
    out = []
    for tiles_at, names_at, base, cram_at in _jobs(rom, sigs):
        cram = [_u16(rom, cram_at + 2 * i) for i in range(64)]
        if any(w & 0xF111 for w in cram):
            raise PanError(f"CRAM at {cram_at:#x}: not MD colour words")
        cells = strip(kosinski(rom, tiles_at), enigma(rom, names_at, base), base & 0x7FF, COLS, ROWS)
        out.append(_pan(cells, cram))
    return out
