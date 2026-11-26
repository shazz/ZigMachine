"""Kestrel Racing M1: the track converter (tools/racer/trackc.py, pvs_bake.py) and the committed binaries."""

from __future__ import annotations

import copy
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from racer import gen_city, gen_track, ktrk, pvs_bake, trackc

ASSETS = Path(__file__).resolve().parents[2] / "apps" / "zig" / "assets" / "screens" / "racer"


def word(blob: bytes, i: int) -> int:
    return struct.unpack_from("<I", blob, 4 * i)[0]


class ConvertTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.doc = gen_track.build_oval()
        cls.blob = trackc.convert(cls.doc)

    def test_committed_oval_is_what_the_generator_and_converter_write_today(self) -> None:
        self.assertEqual((ASSETS / "oval.ktrk").read_bytes(), self.blob)

    def test_committed_city_is_what_the_generator_and_converter_write_today(self) -> None:
        self.assertEqual((ASSETS / "city.ktrk").read_bytes(), trackc.convert(gen_city.build_city(), look=gen_city.MOOD))

    def test_header_carries_magic_version_size_counts_and_a_crc_of_the_body(self) -> None:
        b = self.blob
        self.assertEqual((word(b, 0), word(b, 1), word(b, 3)), (trackc.MAGIC, trackc.VERSION, len(b)))
        self.assertEqual(word(b, 2), zlib.crc32(b[trackc.HEADER:]))
        self.assertEqual((word(b, 4), word(b, 5), word(b, 6), word(b, 7)), (1301, 600, 301, 120))
        self.assertEqual(b[104:128].rstrip(b"\0"), b"test_oval")

    def test_a_face_record_holds_its_plane_and_a_baked_light_in_its_ramp(self) -> None:
        b = self.blob
        at = word(b, 14)
        v = struct.unpack_from("<4HBBBB3hHiII", b, at)  # the first face: a grass ground quad
        self.assertEqual(v[5], 4)  # a quad
        self.assertGreater(v[8:11][1], 0)  # n.y > 0: ground faces point up
        ramp = (v[6] - 16) // 8
        self.assertEqual(ramp, trackc.MATERIALS["grass"][0])
        self.assertLess((v[6] - 16) % 8, 8)

    def test_every_baked_pvs_list_is_far_to_near_and_starts_with_its_count(self) -> None:
        b = self.blob
        idx_at, lists_at = word(b, 19), word(b, 20)
        baked = 0
        for k in range(1024 * 16):
            off = struct.unpack_from("<I", b, idx_at + 4 * k)[0]
            if off == pvs_bake.NOT_BAKED:
                continue
            baked += 1
            n = struct.unpack_from("<H", b, lists_at + 2 * off)[0]
            ents = struct.unpack_from(f"<{n}H", b, lists_at + 2 * off + 2)
            dists = [e >> 10 for e in ents]
            self.assertEqual(dists, sorted(dists, reverse=True))
        self.assertGreater(baked, 16 * 100)

    def test_an_unknown_material_is_refused_not_defaulted(self) -> None:
        bad = copy.deepcopy(self.doc)
        bad["faces"][0]["mat"] = "lava"
        with self.assertRaises(trackc.ConvertError):
            trackc.convert(bad)

    def test_a_document_the_checker_rejects_is_refused(self) -> None:
        bad = copy.deepcopy(self.doc)
        bad["racing_line"] = bad["racing_line"][:2]
        with self.assertRaises(trackc.ConvertError):
            trackc.convert(bad)

    def test_main_converts_a_file_and_reports_an_error_with_exit_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "t.json", Path(tmp) / "t.ktrk"
            src.write_text(ktrk.dumps(self.doc))
            self.assertEqual(trackc.main([str(src), "-o", str(out)]), 0)
            self.assertEqual(out.read_bytes(), self.blob)
            src.write_text("{}")
            self.assertEqual(trackc.main([str(src), "-o", str(out)]), 1)


class PvsTest(unittest.TestCase):
    dirs = pvs_bake.ray_dirs()

    def test_the_camera_tile_is_distance_zero_and_its_neighbours_one(self) -> None:
        vis = dict(pvs_bake.visible(16 * 32 + 16, 0, 8, self.dirs))
        self.assertEqual(vis[16 * 32 + 16], 0)
        self.assertTrue(all(vis[(16 + dz) * 32 + 16 + dx] == 1 for dx in (-1, 0, 1) for dz in (-1, 0, 1) if dx or dz))

    def test_a_ray_looking_plus_z_reaches_eight_tiles_straight_ahead(self) -> None:
        vis = dict(pvs_bake.visible(16 * 32 + 16, 0, 8, self.dirs))
        self.assertEqual([vis.get((16 + k) * 32 + 16) for k in range(1, 9)], list(range(1, 9)))
        self.assertNotIn(8 * 32 + 16, vis)  # nothing behind

    def test_r_zero_is_the_camera_tile_alone_and_the_grid_edge_stops_a_ray(self) -> None:
        self.assertEqual(pvs_bake.visible(5, 4, 0, self.dirs), [(5, 0)])
        vis = dict(pvs_bake.visible(31 * 32 + 5, 0, 8, self.dirs))  # looking +z from the last row
        self.assertTrue(all(t < 32 * 32 for t in vis))


if __name__ == "__main__":
    unittest.main()
