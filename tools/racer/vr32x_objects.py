"""LOCAL ONLY: the course objects a Virtua Racing Deluxe (32X) dump keeps OUTSIDE its tile maps (vr32x_rom.py).

This file holds NO data: it decodes the 68000 code that places them, every table found by the shape of the code that reads
it, refused when absent. Everything it decodes is Sega's: keep it out of the repository.

What the 68000 does, as read (26 Nov):
- **Slots.** Each frame it fills display slots for the SH-2: type, x, y, z, three rotation words, a scale word and an SH-2
  model address (tile-model layout: vr32x_rom._model). It shows an object only while the player is within $C80 (25
  units) of it in x and z; we keep them all.
- **Gantries.** A per-course list (68000 pointers indexed by course * 4) of three 14-byte records: x, y, z, yaw, scale and
  a pointer into a list of SH-2 models, the START gantry then the two C.P. gantries (at the split gates). The game cycles
  six models (the sign's text lighting up); we keep the sixth, the full text.
- **Specials.** A jump table indexed by course * 4 picks a routine; each reads its own table with one of four record
  readers: single (10 bytes, model given in the code), single with its model (14 bytes; one reader puts the word yaw
  should take in roll and spins yaw itself), and pairs (two 14-byte blocks, the second's x, y, z relative to the first:
  a wheel or a swinging ride on its stand, spun or swung about z each frame; we keep the rest pose).
- **Units (INFERRED, see the notes).** x and z / 128, y / 2048 (y sits on our ground's height at every record); a pair's
  offset / 2048 in the stand's frame; model units / 8192 times scale / 256 (scale 0 = 1): the gantries' posts then
  stand just outside the road at all five starts and the Ferris wheel's hub on its tower's top. Yaw is a 13-bit angle,
  turning model +z to (sin a, cos a) with a = -yaw * 2 pi / 8192: it lines the C.P. gantries across the road.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

from racer import vr32x_rom as rom32
from racer.vr32x_rom import RomError

Vec = tuple[float, float, float]
WINDOW, SH2 = 0x80000, 0x22000000
FRAME = 5  # the gantry sign's fully lit model of the six the game cycles

GANTRY = "3238c8a0 43f9........ 22711000 45f9........ 323c0c80 7e.."  # lea list table; 3 records (moveq #2, d7)
DISPATCH = "3038c8a0 227b0004 4ed1"  # move.w course*4; movea.l (table,pc,d0); jmp (a1)
PAIR = "357c00020000 25590002 35590006 3559000a 3559000e 25590010 357c00020014"
LOOP = "25590002 35590006 3559000a 3551000e 25400010"  # 10-byte records, the model in d0
IMM = "25590002 35590006 3559000a 3551000e 257c........0010"  # one 10-byte record, the model in the code
ROLL = "25590002 35590006 3559000c 3559000e 25590010"  # one 14-byte record, its yaw word into roll


@dataclass
class Obj:
    kind: str  # gantry / single / pair
    model: int  # SH-2 address of the (first) model
    at: Vec  # our units
    yaw: float  # radians, model +z -> (sin, cos)
    scale: float
    polys: list[tuple[list[Vec], int]] = field(default_factory=list)  # world vertices, course palette index


def _pat(code: str) -> re.Pattern[bytes]:
    toks = re.findall(r"\.\.|[0-9a-f]{2}", code.replace(" ", ""))
    return re.compile(b"".join(b"." if t == ".." else re.escape(bytes.fromhex(t)) for t in toks), re.DOTALL)


def _find(rom: bytes, code: str) -> int:
    for m in _pat(code).finditer(rom, 0, min(len(rom), WINDOW)):
        if m.start() % 2 == 0:
            return m.start()
    raise RomError(f"no code shape {code!r}")


def _u16(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 2], "big")


def _s16(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 2], "big", signed=True)


def _u32(b: bytes, at: int) -> int:
    return int.from_bytes(b[at : at + 4], "big")


def _rom(addr: int) -> int:
    if 0x880000 <= addr < 0x880000 + WINDOW:
        return addr - 0x880000
    if SH2 <= addr < SH2 + 0x400000:
        return addr - SH2
    raise RomError(f"address {addr:#x} is not in the cartridge's 68000 window or the SH-2's ROM")


def _place(rom: bytes, model: int, pose: tuple[Vec, float, float], off: Vec = (0.0, 0.0, 0.0)) -> list[tuple[list[Vec], int]]:
    """A model's polygons in world space: scaled, offset (in the object's frame), turned by yaw, moved to `at`."""
    at, yaw, scale = pose
    verts, polys = rom32._model(rom, _rom(model))
    c, s = math.cos(yaw), math.sin(yaw)
    out = []
    for p in polys:
        pts = []
        for i in p.ids:
            x, y, z = (verts[i][k] * scale / 8192 + off[k] for k in range(3))
            pts.append((at[0] + x * c + z * s, at[1] + y, at[2] - x * s + z * c))
        out.append((pts, p.colour))
    return out


def _block(rom: bytes, at: int, roll: bool = False) -> tuple[Vec, float, float]:
    """x, y, z, the yaw word (0 when it is the roll), scale: as (our position, yaw radians, scale)."""
    pos = (_s16(rom, at) / 128, _s16(rom, at + 2) / 2048, _s16(rom, at + 4) / 128)
    yaw = 0.0 if roll else -_s16(rom, at + 6) * 2 * math.pi / 8192
    return pos, yaw, (_u16(rom, at + 8) or 256) / 256


def _obj(rom: bytes, kind: str, model: int, pose: tuple[Vec, float, float]) -> Obj:
    return Obj(kind, model, pose[0], pose[1], pose[2], _place(rom, model, pose))


def gantries(rom: bytes, course: int) -> list[Obj]:
    g = _find(rom, GANTRY)
    table, n = _rom(_u32(rom, _rom(_u32(rom, g + 6)) + 4 * course)), rom[g + 25] + 1
    out = []
    for k in range(n):
        rec = table + 14 * k
        out.append(_obj(rom, "gantry", _u32(rom, _rom(_u32(rom, rec + 10)) + 4 * FRAME), _block(rom, rec)))
    return out


def _pair(rom: bytes, rec: int) -> Obj:
    pose = _block(rom, rec)
    o = _obj(rom, "pair", _u32(rom, rec + 10), pose)
    off = (_s16(rom, rec + 14) / 2048, _s16(rom, rec + 16) / 2048, _s16(rom, rec + 18) / 2048)
    o.polys += _place(rom, _u32(rom, rec + 24), pose, off)
    return o


def _target(rom: bytes, p: int) -> int | None:
    """The target of a bsr.b / bsr.w / jsr (pc) at p."""
    w = _u16(rom, p)
    if w in (0x4EBA, 0x6100):
        return p + 2 + _s16(rom, p + 2)
    if w >> 8 == 0x61 and w & 0xFF not in (0, 0xFF):
        return p + 2 + (w & 0xFF) - (256 if w & 0x80 else 0)
    return None


def _call(rom: bytes, kind: str | None, table: int, model: int, count: int) -> tuple[list[Obj], int]:
    """The records a call to a reader consumes: (objects, bytes)."""
    if kind == "pair":
        return [_pair(rom, table)], 28
    if kind == "loop":
        return [_obj(rom, "single", model, _block(rom, table + 10 * k)) for k in range(count)], 10 * count
    return [], 0


def _reader(rom: bytes, at: int) -> str | None:
    if _pat(PAIR).search(rom, at, at + 0x50):
        return "pair"
    return "loop" if _pat(LOOP).search(rom, at, at + 0x50) else None


def _handler(rom: bytes, h: int) -> list[Obj]:
    """Walk a course's routine (to its first unskipped rts), replaying its table reads."""
    out: list[Obj] = []
    table, model, count, p = 0, 0, 1, h
    while p < h + 0x200 and not (_u16(rom, p) == 0x4E75 and _u16(rom, p - 2) != 0x6702):
        w, step = _u16(rom, p), 2
        if w == 0x43F9:
            table, step = _rom(_u32(rom, p + 2)), 6
        elif w == 0x203C:
            model, step = _u32(rom, p + 2), 6
        elif w & 0xFFF8 == 0x7E00:
            count = (w & 7) + 1
        elif (t := _target(rom, p)) is not None:
            got, used = _call(rom, _reader(rom, t), table, model, count)
            out, table, step = out + got, table + used, 4 if w in (0x4EBA, 0x6100) else 2
        elif m := _pat(PAIR).match(rom, p):
            out, table, step = [*out, _pair(rom, table)], table + 28, m.end() - p
        elif m := _pat(IMM).match(rom, p):
            out, step = [*out, _obj(rom, "single", _u32(rom, p + 18), _block(rom, table))], m.end() - p
        elif m := _pat(ROLL).match(rom, p):
            out, step = [*out, _obj(rom, "single", _u32(rom, table + 10), _block(rom, table, roll=True))], m.end() - p
        p += step
    return out


def specials(rom: bytes, course: int) -> list[Obj]:
    d = _find(rom, DISPATCH)
    table = d + 6 + rom[d + 7]  # the (d8, pc, d0) jump table
    return _handler(rom, _rom(_u32(rom, table + 4 * course)))


def objects(rom: bytes, course: int) -> list[Obj]:
    return gantries(rom, course) + specials(rom, course)
