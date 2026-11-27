"""Kestrel Racing M5 step 3: the GT car through the Car Kit (tools/racer/kcar_export.py, carcheck.py, carc.py), one test per
refusal, and the committed export and binary are what the tools write today."""

from __future__ import annotations

import copy
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from racer import carc, carcheck, kcar_export, ktrk, limits
from racer.kit_export import KitError

ROOT = Path(__file__).resolve().parents[2]
JSON = ROOT / "tools/racer/cars/gt.kcar.json"
BLOB = ROOT / "apps/zig/assets/screens/racer/gt.kcar"
BLENDER = Path.home() / ".local/blender/blender"


def gt() -> ktrk.Doc:
    return kcar_export.loads(JSON.read_text())


def refusals(doc: ktrk.Doc) -> list[str]:
    return carcheck.problems(doc)


class GtCarTest(unittest.TestCase):
    def test_committed_binary_is_what_carc_writes_from_the_committed_export(self) -> None:
        self.assertEqual(BLOB.read_bytes(), carc.convert(gt(), scale=carc.GT_SCALE))

    def test_carc_main_writes_the_binary_and_refuses_a_broken_car_with_exit_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out, bad = Path(tmp) / "gt.kcar", Path(tmp) / "bad.json"
            self.assertEqual(carc.main([str(JSON), "-o", str(out), "--scale", str(carc.GT_SCALE)]), 0)
            self.assertEqual(out.read_bytes(), BLOB.read_bytes())
            doc = gt()
            doc["parts"]["hull"] = []
            bad.write_text(ktrk.dumps(doc))
            self.assertEqual(carc.main([str(bad), "-o", str(Path(tmp) / "x")]), 1)

    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_the_blender_build_script_exports_the_committed_document(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "gt.json"
            subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(ROOT / "tools/racer/cars/gt_build.py"), "--",
                            str(out)], check=True, capture_output=True, timeout=300)
            self.assertEqual(out.read_text(), JSON.read_text())

    def test_the_gt_is_inside_its_budget_and_the_envelope(self) -> None:
        doc = gt()
        self.assertEqual(refusals(doc), [])
        nf, nv = carcheck.lod0(doc)
        self.assertLessEqual((nf, nv), (limits.CAR_FACES, limits.CAR_VERTICES))
        self.assertLessEqual(len(doc["parts"]["lod1"]), limits.CAR_LOD1_FACES)

    def test_the_header_names_the_parts_and_the_wing_and_the_crc_covers_the_rest(self) -> None:
        b = BLOB.read_bytes()
        w = struct.unpack("<4I6IiI4I", b[:64])
        self.assertEqual(w[:2], (carc.MAGIC, carc.VERSION))
        drawn = carc.with_footprint(carc.scaled(gt(), carc.GT_SCALE))  # the shadow part is the footprint (R82 bug pass)
        sizes = [len(drawn["parts"][p]) for p in kcar_export.PARTS]
        self.assertEqual(list(w[4:10]), [sum(sizes[: i + 1]) for i in range(6)])
        self.assertEqual(w[10], carc.GT_SCALE * max(gt()["vertices"][i][2] for f in gt()["parts"]["wing"] for i in f["v"]))
        import zlib

        self.assertEqual(w[11], zlib.crc32(b[64:]))

    def test_baked_colours_a_roof_face_is_lit_brightest_a_rear_face_darker_lamps_fixed(self) -> None:
        doc = gt()
        recs = {(p, i): struct.unpack("<4HBBBB3hHiII", carc._record(doc, f, tuple(doc["sun"])))
                for p in kcar_export.PARTS for i, f in enumerate(doc["parts"][p])}
        roof = [r for (p, _), r in recs.items() if p == "cabin" and r[9] > 16000]
        self.assertTrue(roof and all(r[6] & 7 == 7 for r in roof))
        rear = [r for (p, i), r in recs.items() if p == "hull" and r[10] < -16000 and doc["parts"][p][i]["mat"] != "tail"]
        self.assertTrue(rear and all(r[6] & 7 < 7 for r in rear))
        lamps = [r for (p, i), r in recs.items() if doc["parts"][p][i]["mat"] in ("head", "tail")]
        self.assertTrue(lamps and all(r[6] & 7 == 7 for r in lamps))


def face(doc: ktrk.Doc, part: str, ids: list[int], mat: str = "body") -> ktrk.Doc:
    d = copy.deepcopy(doc)
    d["parts"][part].append({"v": ids, "mat": mat})
    return d


def vert(doc: ktrk.Doc, *vs: tuple[int, int, int]) -> tuple[ktrk.Doc, list[int]]:
    d = copy.deepcopy(doc)
    base = len(d["vertices"])
    d["vertices"] += [list(v) for v in vs]
    return d, list(range(base, base + len(vs)))


class RefusalTest(unittest.TestCase):
    def assertRefused(self, doc: ktrk.Doc, text: str, kind: str = "HARD") -> None:
        got = refusals(doc)
        self.assertTrue(any(text in p and p.startswith(kind) for p in got), got)
        if kind == "HARD":
            with self.assertRaises(carc.CarError):
                carc.convert(doc, allow_soft=True)

    def test_a_missing_part_is_refused(self) -> None:
        doc = gt()
        doc["parts"]["lod1"] = []
        self.assertRefused(doc, "part lod1 is missing")

    def test_an_unknown_part_is_refused_by_the_converter_and_the_exporter(self) -> None:
        doc = gt()
        doc["parts"]["spoiler"] = []
        self.assertRefused(doc, "no car part 'spoiler'")
        with self.assertRaises(KitError):
            kcar_export.export({"objects": [{"name": "car_spoiler", "verts": [], "faces": []}], "scene": {"name": "x", "sun": [0, 0, 1]}})

    def test_an_unknown_material_is_refused(self) -> None:
        doc = gt()
        doc["parts"]["hull"][0]["mat"] = "chrome"
        self.assertRefused(doc, "is not a car material")

    def test_a_face_of_five_vertices_is_refused(self) -> None:
        self.assertRefused(face(gt(), "hull", [0, 1, 2, 3, 4]), "has 5 vertices")

    def test_a_vertex_id_past_the_list_is_refused(self) -> None:
        self.assertRefused(face(gt(), "hull", [0, 1, 99999]), "past the")

    def test_a_face_with_no_area_is_refused(self) -> None:
        d, ids = vert(gt(), (0, 5, 0), (4, 5, 0), (8, 5, 0))
        self.assertRefused(face(d, "hull", ids), "has no area")

    def test_a_quad_that_is_not_planar_is_refused(self) -> None:
        d, ids = vert(gt(), (0, 5, 0), (8, 5, 0), (8, 5, 8), (0, 9, 8))
        self.assertRefused(face(d, "hull", ids), "not planar")

    def test_a_quad_that_is_not_convex_is_refused(self) -> None:
        d, ids = vert(gt(), (0, 5, 0), (8, 5, 0), (2, 5, 2), (0, 5, 8))
        self.assertRefused(face(d, "hull", ids), "not convex")

    def test_two_shadow_quads_are_refused(self) -> None:
        doc = gt()
        doc["parts"]["shadow"].append(dict(doc["parts"]["shadow"][0]))
        self.assertRefused(doc, "exactly one quad")

    def test_a_shadow_off_the_ground_is_refused(self) -> None:
        doc = gt()
        for i in doc["parts"]["shadow"][0]["v"]:
            doc["vertices"][i][1] = 10
        self.assertRefused(doc, "flat on the ground")

    def test_the_shadow_material_outside_the_shadow_part_is_refused(self) -> None:
        doc = gt()
        doc["parts"]["hull"][0]["mat"] = "shadow"
        self.assertRefused(doc, "only for the shadow part")

    def test_a_near_model_over_the_face_budget_is_soft_refused_and_taken_with_allow_soft(self) -> None:
        doc = gt()
        doc["parts"]["hull"] += doc["parts"]["hull"][: limits.CAR_FACES]
        self.assertRefused(doc, "near faces", kind="SOFT")
        with self.assertRaises(carc.CarError):
            carc.convert(doc)
        self.assertTrue(carc.convert(doc, allow_soft=True).startswith(b"KCAR"))

    def test_a_near_model_over_the_vertex_budget_is_soft_refused(self) -> None:
        doc, base = gt(), []
        for k in range(limits.CAR_VERTICES // 3 + 1):
            doc, ids = vert(doc, (0, 5 + k, 0), (6, 5 + k, 0), (0, 5 + k, 6))
            base.append(ids)
        for ids in base:
            doc["parts"]["cabin"].append({"v": ids, "mat": "glass"})
        self.assertRefused(doc, "near vertices", kind="SOFT")

    def test_a_far_model_over_its_budget_is_soft_refused(self) -> None:
        doc = gt()
        doc["parts"]["lod1"] += doc["parts"]["lod1"] * 2
        self.assertRefused(doc, "far faces", kind="SOFT")

    def test_a_car_outside_the_envelope_is_soft_refused(self) -> None:
        d, ids = vert(gt(), (-40, 5, 0), (-30, 5, 0), (-30, 5, 8))
        self.assertRefused(face(d, "wing", ids), "envelope", kind="SOFT")

    def test_more_vertices_than_the_cars_vertex_cache_holds_is_refused(self) -> None:
        doc = gt()
        doc["vertices"] += [[0, 0, 0]] * (limits.CAR_MAX_VERTICES + 1 - len(doc["vertices"]))
        self.assertRefused(doc, "vertices 257 > 256")

    def test_more_faces_than_a_car_file_holds_is_refused(self) -> None:
        doc = gt()
        doc["parts"]["hull"] += [doc["parts"]["hull"][0]] * (limits.CAR_MAX_FACES + 1 - sum(map(len, doc["parts"].values())))
        self.assertRefused(doc, "faces 257 > 256")

    def test_a_fixed_colour_off_the_car_ramps_is_refused(self) -> None:
        doc = gt()
        doc["parts"]["hull"][0] = {**doc["parts"]["hull"][0], "mat": "fixed", "ramp": 11, "level": 3}
        self.assertRefused(doc, "fixed colour")
        doc["parts"]["hull"][0]["ramp"], doc["parts"]["hull"][0]["level"] = 18, 8
        self.assertRefused(doc, "fixed colour")

    def test_the_exporter_refuses_a_face_wound_inside_out(self) -> None:
        ob = {"name": "car_hull", "verts": [[0, 0, 0.1], [0.1, 0, 0.1], [0.1, 0.1, 0.1]],
              "faces": [{"v": [0, 1, 2], "mat": "body", "normal": [0, 0, -1]}]}
        with self.assertRaises(KitError):
            kcar_export.export({"objects": [ob], "scene": {"name": "x", "sun": [0, 0, 1]}})


if __name__ == "__main__":
    unittest.main()
