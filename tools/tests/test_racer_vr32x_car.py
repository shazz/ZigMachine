"""Kestrel Racing M5: the 32X car importer (tools/racer/vr32x_car.py, vr32x_carrom.py, vr32x_cargeom.py) on a SYNTHETIC
cartridge in the decoded layout (box cars, no Sega data): the tables found by shape, a polygon's extra words skipped, the pieces
of a block, the wheels, the winding, the colours on the car ramps, and a set the cart's parser layout accepts."""

from __future__ import annotations

import struct
import unittest

from racer import carc, vr32x_car, vr32x_cargeom
from racer import vr32x_carrom as cr
from racer.vr32x_rom import RomError

BOX = [(-1, 0, -1), (1, 0, -1), (1, 1, -1), (-1, 1, -1), (-1, 0, 1), (1, 0, 1), (1, 1, 1), (-1, 1, 1)]
# outward-wound quads of BOX as the 32X stores them (the same convention as ktrk.normal's): bottom, top, -z, +z, -x, +x
QUADS = [[0, 4, 5, 1], [3, 2, 6, 7], [0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2]]


def box(sx: int, y0: int, y1: int, z0: int, z1: int, x0: int | None = None) -> list[tuple[int, int, int]]:
    lo = -sx if x0 is None else x0
    return [(lo if x < 0 else sx, y0 if y == 0 else y1, z0 if z < 0 else z1) for x, y, z in BOX]


def encode(verts: list[tuple[int, int, int]], polys: list[tuple[list[int], int]], extra: int = -1) -> bytes:
    """A model in the 32X layout; polygon `extra` gets flags bit 5 and its three extra words."""
    out = struct.pack(">2H", len(verts), len(verts)) + b"".join(struct.pack(">3h", *v) for v in verts)
    for k, (ids, col) in enumerate(polys):
        fl = (0 if len(ids) == 4 else 1) | (0x20 if k == extra else 0)
        out += struct.pack(">2H", fl, col << 8) + b"".join(struct.pack(">H", 16 * i) for i in ids)
        out += b"\x11\x22\x33\x44\x55\x66" if k == extra else b""
    return out + struct.pack(">H", 0x0C00) + (b"\x00" if len(out) % 2 else b"")


def solid(verts: list[tuple[int, int, int]], col: int, base: int = 0) -> list[tuple[list[int], int]]:
    return [([base + i for i in q], col) for q in QUADS]


def block() -> bytes:
    body = box(600, 50, 500, -1500, 1500)
    axle = box(700, -250, 250, -250, 250)
    tyres = box(700, 0, 500, 400, 900, x0=650) + box(700, 0, 500, -1200, -700, x0=650)
    far = body + tyres
    models = [encode(body, solid(body, 40), extra=1),
              encode([(-600, 0, -1500), (600, 0, -1500), (600, 0, 1500), (-600, 0, 1500)], [([0, 3, 2, 1], 4)]),
              encode(axle, solid(axle, 1)), encode(axle, solid(axle, 2))]
    for k in range(cr.LIVERIES):
        models += [encode(body, solid(body, 50 + k)), encode(far, solid(body, 50 + k) + solid(tyres, 1, 8) + solid(tyres, 1, 16)),
                   encode([(0, 0, 0), (0, 9, 0), (9, 9, 0)], [([0, 1, 2], 60)])]
    out = b""
    for m in models:
        out += m + b"\x00" * (len(out + m) % 2)
    return out


def cartridge() -> bytes:
    rom = bytearray(0x400)  # the tables, then the three blocks
    blocks = []
    for _ in range(cr.CLASSES):
        blocks.append(len(rom))
        rom += block()
    ends = [*blocks[1:], len(rom)]
    for i, (a, b) in enumerate(zip(blocks, ends, strict=True)):
        struct.pack_into(">2I", rom, 0x40 + 8 * i, 0x22000000 + a, 0x22000000 + b)
    pal = 0x100
    for k in range(cr.CLASSES):
        struct.pack_into(">I", rom, pal + 4 * k, 0x880000 + pal + 12 + 128 * k)
        struct.pack_into(">64H", rom, pal + 12 + 128 * k, *[(i % 32) | ((31 - i % 32) << 10) for i in range(64)])
    return bytes(rom)


COURSE = [(i * 8, i * 8, i * 8) for i in range(256)]


class TablesTest(unittest.TestCase):
    def test_the_block_and_palette_tables_are_found_by_their_shape(self) -> None:
        rom = cartridge()
        bl = cr.blocks(rom)
        self.assertEqual(len(bl), cr.CLASSES)
        self.assertEqual([b[0] for b in bl[1:]], [b[1] for b in bl[:-1]])
        self.assertEqual(cr.palettes(rom), [0x100 + 12 + 128 * k for k in range(cr.CLASSES)])

    def test_no_table_is_an_error_not_a_guess(self) -> None:
        with self.assertRaises(RomError):
            cr.blocks(bytes(0x400))
        with self.assertRaises(RomError):
            cr.palettes(bytes(0x400))

    def test_a_polygon_with_flag_bit_5_carries_three_extra_words(self) -> None:
        rom = cartridge()
        ms = cr.walk(rom, *cr.blocks(rom)[0])
        self.assertEqual(len(ms), 4 + 3 * cr.LIVERIES)
        self.assertEqual(len(ms[0].polys), 6)
        self.assertEqual(ms[0].polys[1].flags & 0x20, 0x20)


class PiecesTest(unittest.TestCase):
    def test_a_block_gives_its_near_car_shadow_axles_liveries_and_wheels(self) -> None:
        rom = cartridge()
        pc = vr32x_car.Pieces(cr.walk(rom, *cr.blocks(rom)[0]))
        self.assertTrue(all(v[1] == 0 for v in pc.shadow.verts))
        self.assertEqual(len(pc.liveries), cr.LIVERIES)
        self.assertEqual(pc.wheels, [(0, 250, 650), (0, 250, -950)])

    def test_the_winding_is_read_from_the_model_and_a_mirrored_one_is_turned_over(self) -> None:
        vs = [vr32x_cargeom.q7(v) for v in box(600, 50, 500, -1500, 1500)]
        self.assertTrue(vr32x_cargeom.outward(vs, QUADS))
        self.assertFalse(vr32x_cargeom.outward(vs, [q[::-1] for q in QUADS]))

    def test_a_quad_rounded_off_its_plane_becomes_two_triangles_and_a_sliver_is_dropped(self) -> None:
        vs = [(0, 0, 0), (10, 0, 0), (10, 0, 10), (0, 3, 10), (0, 0, 0), (0, 0, 0)]
        self.assertEqual(len(vr32x_cargeom.drawable(vs, [0, 1, 2, 3])), 2)
        self.assertEqual(vr32x_cargeom.drawable(vs, [0, 4, 5]), [])


class SetTest(unittest.TestCase):
    def test_a_class_becomes_a_set_of_five_models_with_its_own_seven_ramps(self) -> None:
        blob, lines = vr32x_car.car_class(cartridge(), 1, COURSE, allow_soft=True)
        self.assertEqual(struct.unpack_from("<4I", blob, 0), (carc.MAGIC, 2, 5, 1))
        self.assertIn("5 models", lines[0])
        at, n = 64, 0
        while at < len(blob):
            nv, nf = struct.unpack_from("<2I", blob, at + 8)
            ends = struct.unpack_from("<6I", blob, at + 16)
            self.assertEqual(ends[5], nf)
            self.assertEqual(ends[4] - ends[3], 1)  # one shadow quad
            at += 64 + (nv * 6 + 3) // 4 * 4 + 32 * nf
            n += 1
        self.assertEqual((at, n), (len(blob), 5))

    def test_the_darkest_colour_owns_the_skid_ramp_and_each_colour_lands_on_its_own_hue(self) -> None:
        used = {1: 10.0, 40: 50.0, 50: 20.0}
        rgb = {1: (8, 8, 8), 40: (200, 30, 30), 50: (30, 30, 200)}
        at, ramps = vr32x_car.palette_for(used, rgb)
        self.assertEqual(at[1][0], vr32x_car.DARK)
        self.assertEqual(set(ramps), set(range(12, 19)))
        for c in (40, 50):
            shade = vr32x_car._shades(ramps[at[c][0]])[at[c][1]]
            self.assertLess(max(abs(a - b) for a, b in zip(shade, rgb[c], strict=True)), 8)

if __name__ == "__main__":
    unittest.main()
