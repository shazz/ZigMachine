"""Kestrel Racing M5: the Track Kit's Blender-free export (tools/racer/kit_export.py) and ktrk_check's remaining errors."""

from __future__ import annotations

import math
import unittest
from pathlib import Path

from racer import kit, kit_export, ktrk, ktrk_check, trackc

JSON = Path(__file__).resolve().parents[2] / "tools/racer/tracks/salt_flats.ktrk.json"


def salt() -> ktrk.Doc:
    return ktrk.loads(JSON.read_text())


def ring(n: int = 6) -> kit_export.Scene:
    """A small authored loop in Blender axes: n road quads round a circle of radius 20, travelling counter-clockwise."""
    verts, faces, groups = [], [], {"TRACK_FACE": [], "GROUND_FACE": [], "TRACK_L": [], "TRACK_R": [], "LINE_START": [0],
                                    "CHECKPT_1": [2 * (n // 2)], "CHECKPT_2": [0]}
    for i in range(n):
        t = 2 * math.pi * i / n
        c, lft = (20 * math.cos(t), 20 * math.sin(t)), (-math.cos(t), -math.sin(t))
        verts += [[c[0] + 3 * lft[0], c[1] + 3 * lft[1], 0.0], [c[0] - 3 * lft[0], c[1] - 3 * lft[1], 0.0]]
        groups["TRACK_L"].append(2 * i)
        groups["TRACK_R"].append(2 * i + 1)
    for i in range(n):
        j = (i + 1) % n
        faces.append({"v": [2 * i, 2 * i + 1, 2 * j + 1, 2 * j], "mat": "asphalt", "normal": [0.0, 0.0, 1.0]})
    groups["TRACK_FACE"] = groups["GROUND_FACE"] = list(range(2 * n))
    edges = sorted({tuple(sorted((f["v"][k], f["v"][(k + 1) % 4]))) for f in faces for k in range(4)})
    return {"objects": [{"name": "track", "verts": verts, "faces": faces, "edges": [list(e) for e in edges], "groups": groups}],
            "materials": {"asphalt": {"rgb": [100, 100, 100], "dual": False}, "pole": {"rgb": [1, 2, 3], "dual": False}},
            "grid": [{"name": f"slot{k}", "pos": [20.0, 0.0, 0.0], "rot_z": 0.0} for k in range(8)],
            "scene": {"name": "ring", "mood": "noon", "sun": [0.0, 0.0, 1.0], "far_ground": "asphalt"}}


class ExportTest(unittest.TestCase):
    def test_a_loop_exports_its_racing_line_the_way_slot_0_faces(self) -> None:
        doc = kit_export.export(ring())
        vs = doc["vertices"]
        self.assertEqual(len(doc["racing_line"]), 6)
        self.assertGreater(vs[doc["racing_line"][1]["l"]][2], vs[doc["racing_line"][0]["l"]][2])  # Blender +y = engine +z
        self.assertEqual(doc["checkpoints"], [2, 5])  # CHECKPT_1 at L3 ends segment 2, CHECKPT_2 at L0 the last
        self.assertEqual((doc["start_grid"][0]["yaw_q16"], doc["palette"], doc["mood"]["sun"]),
                         (0, {"asphalt": [100, 100, 100]}, [0.0, 1.0, 0.0]))
        self.assertTrue(all(ktrk.normal(ktrk.pts(doc, f["v"]))[1] > 0.99 for f in doc["faces"]))

    def test_a_prop_wound_inside_out_is_refused(self) -> None:
        sc = ring()
        ob = sc["objects"][0]
        base = len(ob["verts"])
        ob["verts"] += [[30.0, 0.0, 0.0], [30.0, 1.0, 0.0], [30.0, 0.0, 1.0]]
        ob["faces"].append({"v": [base, base + 1, base + 2], "mat": "pole", "normal": [-1.0, 0.0, 0.0]})
        ob["groups"]["PROP_FACE"] = [base, base + 1, base + 2]
        with self.assertRaisesRegex(kit_export.KitError, "winding"):
            kit_export.export(sc)

    def test_a_decal_off_every_ground_face_is_refused(self) -> None:
        sc = ring()
        ob = sc["objects"][0]
        base = len(ob["verts"])
        ob["verts"] += [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0]]
        ob["faces"].append({"v": [base, base + 1, base + 2], "mat": "asphalt", "normal": [0.0, 0.0, 1.0]})
        ob["groups"]["DETAIL_FACE"] = [base, base + 1, base + 2]
        with self.assertRaisesRegex(kit_export.KitError, "DETAIL_FACE lies on no ground face"):
            kit_export.export(sc)

    def test_broken_line_conventions_are_refused(self) -> None:
        cases = (("TRACK_L", [0, 2, 4], "closed edge loop"), ("LINE_START", [], "LINE_START"), ("CHECKPT_1", [2, 4], "CHECKPT_1"))
        for group, ids, text in cases:
            sc = ring()
            sc["objects"][0]["groups"][group] = ids
            with self.subTest(group), self.assertRaisesRegex(kit_export.KitError, text):
                kit_export.export(sc)

    def test_a_face_whose_material_has_no_colour_is_refused(self) -> None:
        sc = ring()
        sc["objects"][0]["faces"][0]["mat"] = "lava"
        with self.assertRaisesRegex(kit_export.KitError, "no ktrk_rgb"):
            kit_export.export(sc)

    def test_an_l_vertex_with_no_r_vertex_joined_to_it_is_refused(self) -> None:
        sc = ring()
        sc["objects"][0]["groups"]["TRACK_R"] = [3, 5, 7, 9, 11]
        with self.assertRaisesRegex(kit_export.KitError, "0 TRACK_R vertices joined"):
            kit_export.export(sc)

    def test_border_edges_outside_the_face_are_refused_by_the_converter(self) -> None:
        doc = salt()
        next(f for f in doc["faces"] if f.get("borders"))["borders"] = [7]
        with self.assertRaisesRegex(trackc.ConvertError, "border edges"):
            trackc.convert(doc, kit.ramps(doc)[1], validate=False)


class ValidationTest(unittest.TestCase):
    """ktrk_check's errors the M0 tests did not plant (one test each, PORT_PLAN M5)."""

    def setUp(self) -> None:
        self.doc = salt()

    def errs(self) -> str:
        return "; ".join(ktrk_check.validate(self.doc))

    def test_an_unknown_kind_is_reported(self) -> None:
        self.doc["faces"][0]["kind"] = "lava"
        self.assertIn("unknown kind 'lava'", self.errs())

    def test_a_ground_face_pointing_down_is_reported(self) -> None:
        f = next(f for f in self.doc["faces"] if f["kind"] == "track")
        f["v"] = f["v"][::-1]
        self.assertIn("ground normal does not point up", self.errs())

    def test_a_decal_off_its_parents_plane_is_reported(self) -> None:
        f = next(f for f in self.doc["faces"] if f.get("inner"))
        self.doc["vertices"][f["inner"][0]["v"][0]][1] += 64
        self.assertIn("not coplanar with its parent", self.errs())

    def test_a_checkpoint_past_the_line_and_an_empty_grid_are_reported(self) -> None:
        self.doc["checkpoints"] = [500]
        self.doc["start_grid"] = []
        self.assertIn("checkpoint 500 outside the line", self.errs())
        self.assertIn("start grid is empty", self.errs())


if __name__ == "__main__":
    unittest.main()

