"""Kestrel Racing (local 32X import): the course objects of tools/racer/vr32x_objects.py. No Sega bytes: a synthetic
cartridge with hand-written 68000 code shapes, tables and a one-triangle SH-2 model."""

from __future__ import annotations

import math
import struct
import unittest

from racer import vr32x_objects as vo
from racer import vr32x_rom
from racer.vr32x_rom import RomError

M68, SH2 = 0x880000, 0x22000000
TRI, TRI2 = 0x1000, 0x1100  # two models: a triangle of colour 7, one of colour 9


def _code(text: str) -> bytes:
    return bytes.fromhex(text.replace(" ", ""))


def _model(colour: int) -> bytes:
    verts = [(8192, 0, 0), (0, 8192, 0), (0, 0, 8192)]
    out = struct.pack(">HH", 3, 3) + b"".join(struct.pack(">3h", *v) for v in verts)
    return out + struct.pack(">HH3H", 0x0001, colour << 8, 0, 16, 32) + struct.pack(">H", vr32x_rom.END)


class Cart:
    def __init__(self) -> None:
        self.rom = bytearray(0x2000)
        self.put(TRI, _model(7))
        self.put(TRI2, _model(9))

    def put(self, at: int, data: bytes) -> None:
        self.rom[at : at + len(data)] = data

    def gantry_table(self, record: bytes) -> None:
        """The gantry code shape at 0x100 (one record: moveq #0, d7), its course table at 0x200, the record at 0x300."""
        self.put(0x100, _code(f"3238c8a0 43f9{M68 + 0x200:08x} 22711000 45f900ff659c 323c0c80 7e00"))
        self.put(0x200, struct.pack(">I", M68 + 0x300))
        self.put(0x300, record + struct.pack(">I", M68 + 0x400))
        self.put(0x400, struct.pack(">6I", *([0] * 5 + [SH2 + TRI])))

    def handler(self, code: bytes) -> None:
        """Course 0's special routine at 0x600, reached through the dispatch shape at 0x500."""
        self.put(0x500, _code(f"3038c8a0 227b0004 4ed1 {M68 + 0x600:08x}"))
        self.put(0x600, code)


def _rec(x: int, y: int, z: int, yaw: int, scale: int) -> bytes:
    return struct.pack(">5h", x, y, z, yaw, scale)


IMM = vo.IMM.replace("........", f"{SH2 + TRI:08x}")
SKIP_RTS = "4a38c80f 6702 4e75"  # tst.b; beq.s +2; rts: the 2-player exit the walk steps over


class Gantries(unittest.TestCase):
    def test_a_record_places_the_sixth_model_scaled_turned_and_moved(self) -> None:
        cart = Cart()
        cart.gantry_table(_rec(256, 2048, -128, 2048, 512))  # (2, 1, -1) units, yaw word 2048 = -90 deg, scale 2
        (g,) = vo.gantries(bytes(cart.rom), 0)
        self.assertEqual((g.kind, g.model, g.at, g.scale), ("gantry", SH2 + TRI, (2.0, 1.0, -1.0), 2.0))
        self.assertAlmostEqual(g.yaw, -math.pi / 2)
        (pts, colour), = g.polys
        self.assertEqual(colour, 7)
        want = [(2.0, 1.0, 1.0), (2.0, 3.0, -1.0), (0.0, 1.0, -1.0)]  # model +x -> world +z, +z -> world -x
        for got, w in zip(pts, want, strict=True):
            for a, b in zip(got, w, strict=True):
                self.assertAlmostEqual(a, b)

    def test_scale_zero_means_one(self) -> None:
        cart = Cart()
        cart.gantry_table(_rec(0, 0, 0, 0, 0))
        self.assertEqual(vo.gantries(bytes(cart.rom), 0)[0].scale, 1.0)

    def test_a_dump_without_the_gantry_code_is_refused(self) -> None:
        with self.assertRaises(RomError):
            vo.gantries(bytes(0x2000), 0)


class Specials(unittest.TestCase):
    def test_a_single_with_its_model_in_the_code_past_a_skipped_rts(self) -> None:
        cart = Cart()
        cart.handler(_code(f"{SKIP_RTS} 43f9{M68 + 0x700:08x} {IMM} 4e75"))
        cart.put(0x700, _rec(128, 0, 128, 0, 256))
        (o,) = vo.specials(bytes(cart.rom), 0)
        self.assertEqual((o.kind, o.model, o.at, o.yaw), ("single", SH2 + TRI, (1.0, 0.0, 1.0), 0.0))

    def test_a_pair_puts_its_second_model_at_the_offset_in_the_first_ones_frame(self) -> None:
        cart = Cart()
        cart.handler(_code(f"43f9{M68 + 0x700:08x} {vo.PAIR} 4e75"))
        first = _rec(0, 0, 0, -2048, 0) + struct.pack(">I", SH2 + TRI)  # yaw +90 deg: local +z -> world +x
        cart.put(0x700, first + _rec(0, 0, 2048, 0, 0) + struct.pack(">I", SH2 + TRI2))  # offset 1 unit along +z
        (o,) = vo.specials(bytes(cart.rom), 0)
        self.assertEqual([c for _, c in o.polys], [7, 9])
        second = o.polys[1][0]
        self.assertAlmostEqual(second[1][0], 1.0)  # the offset vertex (0, 1, 0) + (0, 0, 1) -> world x 1
        self.assertAlmostEqual(second[1][1], 1.0)

    def test_a_called_reader_reads_count_records_with_the_model_from_d0(self) -> None:
        cart = Cart()
        reader = 0x680
        call = 0x600 + 6 + 6 + 2  # after the lea, the move.l and the moveq
        cart.handler(_code(f"43f9{M68 + 0x700:08x} 203c{SH2 + TRI2:08x} 7e01 4eba{reader - call - 2:04x} 4e75"))
        cart.put(reader, _code(f"{vo.LOOP} 4e75"))
        cart.put(0x700, _rec(128, 0, 0, 0, 0) + _rec(256, 0, 0, 0, 0))
        got = vo.specials(bytes(cart.rom), 0)
        self.assertEqual([(o.kind, o.model, o.at[0]) for o in got], [("single", SH2 + TRI2, 1.0), ("single", SH2 + TRI2, 2.0)])

    def test_a_course_without_specials_has_none(self) -> None:
        cart = Cart()
        cart.handler(_code("4e75"))
        self.assertEqual(vo.specials(bytes(cart.rom), 0), [])

    def test_a_dump_without_the_dispatch_code_is_refused(self) -> None:
        with self.assertRaises(RomError):
            vo.specials(bytes(0x2000), 0)

    def test_a_model_address_outside_the_cartridge_is_refused(self) -> None:
        with self.assertRaises(RomError):
            vo._rom(0x00FF1000)


if __name__ == "__main__":
    unittest.main()
