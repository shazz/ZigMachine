"""Kestrel Racing (local 32X import): the decoder and the line search of tools/racer/vr32x_*.py. No track data: synthetic
tile models built here in the layout vr32x_rom.py documents, and a synthetic ring of asphalt."""

from __future__ import annotations

import math
import struct
import unittest

from racer import ktrk, vr32x_cells, vr32x_geom, vr32x_line, vr32x_rom
from racer.vr32x_rom import Poly, Tile


def _model(verts: list[tuple[int, int, int]], polys: list[tuple[int, int, list[int]]]) -> bytes:
    out = struct.pack(">HH", len(verts), len(verts)) + b"".join(struct.pack(">3h", *v) for v in verts)
    for flags, colour, ids in polys:
        out += struct.pack(">HH", flags, colour) + b"".join(struct.pack(">H", i * 16) for i in ids)
    return out + struct.pack(">H", vr32x_rom.END)


class Model(unittest.TestCase):
    def test_a_strip_continuation_reuses_the_named_edge_of_the_previous_polygon(self) -> None:
        verts = [(0, 0, 0), (100, 0, 0), (100, 0, 100), (0, 0, 100), (200, 0, 0), (200, 0, 100)]
        rom = _model(verts, [(0x0008, 0x0D00, [0, 1, 2, 3]), (0x0608, 0x0E01, [4, 5])])
        _, polys = vr32x_rom._model(rom, 0)
        self.assertEqual(polys[0].ids, [0, 1, 2, 3])
        self.assertEqual(polys[1].ids, [2, 1, 4, 5])  # flags 6: edge 1 (1 -> 2) as [b, a, new...]
        self.assertEqual((polys[1].colour, polys[1].low), (0x0E, 1))

    def test_a_triangle_continuation_on_the_last_edge_adds_one_vertex(self) -> None:
        rom = _model([(0, 0, 0), (100, 0, 0), (0, 0, 100), (-100, 0, 0)], [(0x0011, 0x2000, [0, 1, 2]), (0x0211, 0x2000, [3])])
        _, polys = vr32x_rom._model(rom, 0)
        self.assertEqual(polys[1].ids, [0, 2, 3])

    def test_a_vertex_id_past_the_model_is_refused(self) -> None:
        rom = _model([(0, 0, 0), (1, 0, 0), (0, 0, 1)], [(0x0011, 0x2000, [0, 1, 7])])
        with self.assertRaises(vr32x_rom.RomError):
            vr32x_rom._model(rom, 0)

    def test_a_continuation_without_a_previous_polygon_is_refused(self) -> None:
        with self.assertRaises(vr32x_rom.RomError):
            vr32x_rom._model(_model([(0, 0, 0), (1, 0, 0)], [(0x0211, 0x2000, [1])]), 0)

    def test_a_dump_that_is_not_the_game_is_refused(self) -> None:
        with self.assertRaises(vr32x_rom.RomError):
            vr32x_rom.palettes(bytes(4096))


def _ring() -> vr32x_geom.Mesh:
    """A square ring of grey road, 4 units wide, outer side 40 units, as quads one unit long; up = +y."""
    pal = [(0, 0, 0)] * 256
    pal[0x0D] = (98, 98, 98)
    verts: list[tuple[int, int, int]] = []
    polys = []
    path = [(x, -20) for x in range(-20, 20)] + [(20, z) for z in range(-20, 20)] + \
           [(x, 20) for x in range(20, -20, -1)] + [(-20, z) for z in range(20, -20, -1)]
    for (x0, z0), (x1, z1) in zip(path, path[1:] + path[:1], strict=True):
        dx, dz = x1 - x0, z1 - z0
        nx, nz = -dz * 2, dx * 2  # 2 units left of the direction
        quad = [(x0 + nx, z0 + nz), (x1 + nx, z1 + nz), (x1 - nx, z1 - nz), (x0 - nx, z0 - nz)]
        base = len(verts)
        verts += [(int(x * 256), 0, int(z * 256)) for x, z in quad]
        polys.append(Poly([base, base + 1, base + 2, base + 3], 0x0D, 0, 0x08))
    m = vr32x_geom.build([Tile(0, 0, verts, polys)], pal)
    for f in m.faces:  # wind every face up whichever way the path turned
        if ktrk.normal(m.pts(f.v))[1] < 0:
            f.v.reverse()
        f.kind = "track"
    return m


class Line(unittest.TestCase):
    def test_the_shortest_lap_of_a_ring_goes_all_the_way_round(self) -> None:
        m = _ring()
        bins = vr32x_geom.Bins(m)
        guide = vr32x_cells.Cells(bins).lap((0.0, 0.0, -20.0), (1.0, 0.0))
        st = vr32x_line.follow(bins, guide)
        self.assertAlmostEqual(vr32x_line.length(st), 160.0, delta=12.0)
        widths = sorted(math.dist(s[0], s[2]) for s in st)
        self.assertAlmostEqual(widths[len(widths) // 2], 4.0, delta=0.3)  # the corners cut wider: the median

    def test_no_lap_from_a_point_off_the_asphalt(self) -> None:
        m = _ring()
        self.assertEqual(vr32x_cells.Cells(vr32x_geom.Bins(m)).lap((0.0, 0.0, 0.0), (1.0, 0.0)), [])


if __name__ == "__main__":
    unittest.main()
