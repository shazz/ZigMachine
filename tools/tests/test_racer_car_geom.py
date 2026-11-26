"""Kestrel Racing M5 step 3: the GT car's geometry (tools/racer/cars/gt_geom.py) through the Car Kit export WITHOUT Blender:
the scene the add-on would extract, built from the same meshes, exports to the committed `.kcar.json`."""

from __future__ import annotations

import math
import struct
import sys
import unittest
from pathlib import Path

from racer import carcheck, kcar_export

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/racer/cars"))
import gt_geom  # noqa: E402

JSON = ROOT / "tools/racer/cars/gt.kcar.json"


def f32(x: float) -> float:
    """Blender stores vertex coordinates as 32-bit floats."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


def newell(p: list[tuple[float, float, float]]) -> list[float]:
    n = [0.0, 0.0, 0.0]
    for a, b in zip(p, p[1:] + p[:1], strict=True):
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    k = math.sqrt(sum(c * c for c in n))
    return [c / k for c in n]


def scene() -> kcar_export.Scene:
    obs = []
    for part, make in gt_geom.PARTS.items():
        m = make()
        verts = [[f32(c) for c in v] for v in m.verts]
        faces = [{"v": ids, "mat": mat, "normal": newell([m.verts[i] for i in ids])} for ids, mat in zip(m.faces, m.mats, strict=True)]
        obs.append({"name": f"car_{part}", "verts": verts, "faces": faces})
    return {"objects": obs, "scene": {"name": "gt", "sun": list(gt_geom.SUN)}}


class GtGeomTest(unittest.TestCase):
    def test_the_geometry_exports_to_the_committed_document_without_blender(self) -> None:
        doc = kcar_export.export(scene())
        self.assertEqual(doc, kcar_export.loads(JSON.read_text()))

    def test_every_quad_of_the_geometry_is_planar_and_convex_after_the_snap(self) -> None:
        self.assertEqual(carcheck.problems(kcar_export.export(scene())), [])

    def test_a_flipped_face_in_the_geometry_is_refused_by_the_export(self) -> None:
        sc = scene()
        hull = next(o for o in sc["objects"] if o["name"] == "car_hull")
        hull["faces"][0]["normal"] = [-c for c in hull["faces"][0]["normal"]]
        with self.assertRaises(kcar_export.KitError):
            kcar_export.export(sc)


if __name__ == "__main__":
    unittest.main()
