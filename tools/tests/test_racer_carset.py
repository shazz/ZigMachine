"""Kestrel Racing M5 car files (tools/racer/carc.py): the draw scale, a face's own fixed colour, and a set of models with its
own palette (the cart's carfile.zig reads both; apps/zig/scenes/racer/carfile_test.zig checks the cart's side)."""

from __future__ import annotations

import struct
import unittest
import zlib
from pathlib import Path

from racer import carc, kcar_export

ROOT = Path(__file__).resolve().parents[2]
JSON = ROOT / "tools/racer/cars/gt.kcar.json"


def gt() -> dict:  # type: ignore[type-arg]  # [type-arg] a kcar-json document
    return kcar_export.loads(JSON.read_text())


def faces(blob: bytes) -> list[tuple[int, ...]]:
    nv, nf = struct.unpack_from("<2I", blob, 8)
    at = 64 + (nv * 6 + 3) // 4 * 4
    return [struct.unpack_from("<4HBBBB", blob, at + 32 * i) for i in range(nf)]


class ScaleTest(unittest.TestCase):
    def test_a_scaled_car_has_every_vertex_and_the_wing_edge_times_the_scale_and_the_same_colours(self) -> None:
        one, two = carc.convert(gt()), carc.convert(gt(), scale=2.0)
        nv = struct.unpack_from("<I", one, 8)[0]
        v1 = struct.unpack_from(f"<{3 * nv}h", one, 64)
        v2 = struct.unpack_from(f"<{3 * nv}h", two, 64)
        self.assertEqual([2 * c for c in v1], list(v2))
        self.assertEqual(2 * struct.unpack_from("<i", one, 40)[0], struct.unpack_from("<i", two, 40)[0])
        self.assertEqual([f[6] for f in faces(one)], [f[6] for f in faces(two)])

    def test_carc_main_refuses_a_scale_outside_its_range(self) -> None:
        self.assertEqual(carc.main([str(JSON), "-o", "/dev/null", "--scale", "20"]), 1)


class FixedColourTest(unittest.TestCase):
    def test_a_fixed_face_stores_its_own_ramp_and_level_unlit(self) -> None:
        doc = gt()
        doc["parts"]["hull"][0] = {**doc["parts"]["hull"][0], "mat": "fixed", "ramp": 17, "level": 2}
        first_hull = len(doc["parts"]["wheels"])
        f = faces(carc.convert(doc))[first_hull]
        self.assertEqual((f[4], f[6]), (0, 16 + 17 * 8 + 2))


class SetTest(unittest.TestCase):
    def test_a_set_is_a_header_with_its_palette_then_the_models_and_the_crc_covers_them(self) -> None:
        m = carc.convert(gt())
        pal = [(10 * i, 20, 30) for i in range(carc.RAMPS)]
        s = carc.pack_set([m, m], pal)
        self.assertEqual(struct.unpack_from("<4I", s, 0), (carc.MAGIC, 2, 2, 1))
        self.assertEqual(s[16 + 4 * 3:16 + 4 * 3 + 3], bytes((30, 20, 30)))
        self.assertEqual(struct.unpack_from("<I", s, 44)[0], zlib.crc32(s[64:]))
        self.assertEqual(s[64:], m + m)

    def test_a_set_without_a_palette_has_the_flag_clear(self) -> None:
        s = carc.pack_set([carc.convert(gt())], None)
        self.assertEqual(struct.unpack_from("<I", s, 12)[0], 0)

    def test_a_set_of_no_model_or_too_many_or_a_short_palette_is_refused(self) -> None:
        m = carc.convert(gt())
        for models, pal in (([], None), ([m] * (carc.MAX_MODELS + 1), None), ([m], [(0, 0, 0)] * 3)):
            with self.assertRaises(carc.CarError):
                carc.pack_set(models, pal)


if __name__ == "__main__":
    unittest.main()
