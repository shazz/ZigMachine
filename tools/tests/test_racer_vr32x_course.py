"""Kestrel Racing (local 32X import, decoded mode): the course-table finders and the surface decoder of
tools/racer/vr32x_{tables,find,surface,course,kinds}.py. No Sega data: a synthetic cartridge built here in the layout
the modules document (a ring course of 64 points, one road polygon per point's cell, a grid on point 0's cell)."""

from __future__ import annotations

import math
import struct
import unittest

from racer import vr32x_course, vr32x_find, vr32x_kinds, vr32x_tables
from racer import vr32x_surface as surf

N = 64
R = 9000
BANK1 = 0x100000  # the synthetic cartridge's $900000 window is its second megabyte
TABLE = 0x1000  # where the course record sits (in the $880000 window)
FULL = [(0b011, 0, 0), (0b010, 1024, 0), (0b110, 0, 0), (0b111, 1024, 0)]  # x >= 0, x < 1024, z >= 0, z < 1024: the cell


def _record(edges: list[tuple[int, int, int]], surface: int, point: int, flags: int = 0, plane: tuple[int, int, int] = (0, 0, 0)) -> bytes:
    code = sum(bits << (13 - 3 * e) for e, (bits, _, _) in enumerate(edges))
    body = b"".join(struct.pack(">2h", k, c) for _, k, c in edges)
    return struct.pack(">H", code) + body + struct.pack(">3h", *plane) + bytes([surface, flags, 0, point])


def _path() -> list[tuple[int, int]]:
    return [(round(R * math.cos(-2 * math.pi * i / N)), round(R * math.sin(-2 * math.pi * i / N))) for i in range(N)]


def _cell_of(x: int, z: int) -> int:
    return ((z + surf.ORIGIN) // surf.CELL) * surf.GRID + (x + surf.ORIGIN) // surf.CELL


def _surface_blob(path: list[tuple[int, int]], gates: dict[int, int]) -> tuple[bytes, bytes]:
    """(map, base): every path point's cell holds one road polygon covering it, the rest are empty."""
    base, offs = bytearray(struct.pack(">h", -1)), [0] * (surf.GRID * surf.GRID)
    for i, (x, z) in enumerate(path):
        offs[_cell_of(x, z)] = len(base) // 2
        base += struct.pack(">h", 0) + _record(FULL, 1 | gates.get(i, 0) << 6, i, plane=(0, 0, 2048 * 2))
    return struct.pack(f">{len(offs)}H", *offs), bytes(base)


def cartridge(gates: dict[int, int] | None = None) -> bytes:
    data = bytearray(2 * BANK1)
    path = _path()

    def put(at: int, b: bytes) -> None:
        data[BANK1 + at:BANK1 + at + len(b)] = b
    put(0x1000, bytes(b for i in range(N) for b in (i, i)))  # respawn pairs, lane 0 the point itself
    put(0x1100, bytes(range(N)))  # the byte map
    put(0x1140, b"".join(struct.pack(">2h", *p) for p in path))  # the path, right after the byte map
    put(0x1300, b"".join(struct.pack(">3h", x, z, 0) for x, z in path))  # an AI line
    struct.pack_into(">5I", data, TABLE, 0x901140, 0x901100, 0x901000, 0x901300, 0x901300)
    smap, sbase = _surface_blob(path, {0: 1, 20: 2, 40: 3} if gates is None else gates)
    put(0x10000, smap)
    put(0x20000, sbase)
    struct.pack_into(">2I", data, 0x2000, 0x910000, 0x920000)
    grid = b"".join(struct.pack(">4h", 8800 + 100 * (k % 2), 2048 + k, 20 + 30 * k, 0) for k in range(16))
    data[0x3000:0x3000 + len(grid)] = grid
    return bytes(data)


class Tables(unittest.TestCase):
    def test_the_course_table_is_found_by_its_shape_under_the_right_bank(self) -> None:
        rom, cs = vr32x_tables.courses(cartridge(), 1)
        self.assertEqual(rom.bank, 1)
        self.assertEqual((len(cs[0].path), cs[0].path[0], cs[0].pit), (N, (R, 0), []))

    def test_a_cartridge_without_a_course_table_is_refused(self) -> None:
        with self.assertRaises(vr32x_tables.TableError):
            vr32x_tables.courses(bytes(2 * BANK1), 1)

    def test_the_surface_map_and_the_grid_are_found_and_agree_with_the_path(self) -> None:
        (c, lay, poses), = vr32x_find.tracks(cartridge(), 1)
        self.assertEqual(vr32x_find.score(c, lay.walk(c.path)), 1.0)
        self.assertEqual(len(poses), 16)
        self.assertEqual(poses[0], (8800, 2048, 20, 0))


class Surface(unittest.TestCase):
    def test_a_slope_edge_keeps_the_side_its_bit_names(self) -> None:
        tri = surf._poly(_record([(0b001, 512, 0)] * 4, 1, 0), 0)  # z < x (slope 1 over the doubled local coordinates)
        self.assertTrue(surf.inside(tri, 600, 100))
        self.assertFalse(surf.inside(tri, 100, 600))

    def test_the_surface_byte_splits_into_class_and_gate(self) -> None:
        p = surf._poly(_record(FULL, 0x83, 7), 0)
        self.assertEqual((p.cls, p.gate, p.point), (3, 2, 7))

    def test_a_car_on_a_flagged_polygon_looks_up_in_the_upper_deck_next(self) -> None:
        rom = cartridge()
        main = surf.SurfaceMap(rom, vr32x_tables.Rom(rom).at, 0x910000, 0x920000)
        lay = surf.Layered(main, main)
        self.assertEqual([p.point for p in lay.walk(_path()[:3]) if p], [0, 1, 2])


class Course(unittest.TestCase):
    def test_the_gates_become_our_checkpoints_one_segment_back_and_the_line_last(self) -> None:
        (c, lay, _), = vr32x_find.tracks(cartridge(), 1)
        self.assertEqual(vr32x_course.gates(c, lay), [19, 39, N - 1])

    def test_a_course_missing_a_gate_is_refused(self) -> None:
        (c, lay, _), = vr32x_find.tracks(cartridge({0: 1, 20: 2}), 1)
        with self.assertRaises(vr32x_course.CourseError):
            vr32x_course.gates(c, lay)

    def test_the_lap_is_the_path_length_in_our_units_and_its_sense_is_reported(self) -> None:
        (c, _, _), = vr32x_find.tracks(cartridge(), 1)
        self.assertAlmostEqual(vr32x_course.lap(c), 2 * math.pi * R / surf.WORLD_PER_UNIT, delta=2.0)
        self.assertTrue(vr32x_course.clockwise(c))  # the synthetic ring runs clockwise seen from above (+z up)

    def test_a_face_on_road_is_track_and_one_off_the_map_is_not_drivable(self) -> None:
        (_, lay, _), = vr32x_find.tracks(cartridge(), 1)
        x, z = R / surf.WORLD_PER_UNIT, 1.0
        square = [(x - 0.5, 1.0, z - 0.5), (x + 0.5, 1.0, z - 0.5), (x + 0.5, 1.0, z + 0.5), (x - 0.5, 1.0, z + 0.5)]
        self.assertEqual(vr32x_kinds.vote(lay, square)[0], "track")
        self.assertEqual(vr32x_kinds.vote(lay, [(0.0, 0, 0.0), (1.0, 0, 0.0), (0.0, 0, 1.0)])[0], "prop")


if __name__ == "__main__":
    unittest.main()
