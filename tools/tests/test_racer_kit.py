"""Kestrel Racing M5: the Track Kit (tools/racer/kit*.py, budget.py, bake.py, walk.py) and Salt Flats, the first authored track."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from racer import bake, budget, kit, kit_export, ktrk, ktrk_check, limits, trackc, walk
from racer import ref_render as rr

ROOT = Path(__file__).resolve().parents[2]
JSON = ROOT / "tools/racer/tracks/salt_flats.ktrk.json"
HEAVY = ROOT / "tools/racer/tracks/salt_flats.heavy.json"
BLOB = ROOT / "apps/zig/assets/screens/racer/salt.ktrk"
BLENDER = Path.home() / ".local/blender/blender"


def salt() -> ktrk.Doc:
    return ktrk.loads(JSON.read_text())


class SaltFlatsTest(unittest.TestCase):
    def test_committed_binary_is_what_the_kit_converter_writes_from_the_committed_export(self) -> None:
        self.assertEqual(BLOB.read_bytes(), kit.convert(salt()))

    def test_trackc_main_takes_an_authored_document_through_the_kit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "s.ktrk"
            self.assertEqual(trackc.main([str(JSON), "-o", str(out)]), 0)
            self.assertEqual(out.read_bytes(), BLOB.read_bytes())

    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_the_blender_build_script_exports_the_committed_document(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "s.json"
            subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(ROOT / "tools/racer/tracks/salt_flats_build.py"),
                            "--", str(out)], check=True, capture_output=True, timeout=300)
            self.assertEqual(out.read_text(), JSON.read_text())

    def test_salt_flats_is_inside_its_budget_and_validates(self) -> None:
        doc = salt()
        self.assertEqual((budget.problems(doc), ktrk_check.validate(doc)), ([], []))
        m = budget.meter(doc)
        self.assertLessEqual(m.faces, 1500)
        self.assertEqual((m.segments, len(doc["start_grid"]), doc["checkpoints"]), (176, 8, [43, 87, 131, 175]))

    def test_the_heaviest_poses_file_is_what_the_walk_finds_today_and_under_the_frame_ceiling(self) -> None:
        poses = walk.walk(rr.Track(BLOB.read_bytes()))
        self.assertEqual(json.loads(HEAVY.read_text())["frames"], [p.frame for p in walk.heaviest(poses)])
        self.assertLess(max(p.mc for p in poses), limits.FRAME_MC)

    def test_the_walk_fails_a_track_whose_heaviest_pose_is_over_the_ceiling(self) -> None:
        with mock.patch.object(limits, "FRAME_MC", 0.5), mock.patch("sys.stdout"), mock.patch("sys.stderr"):
            self.assertEqual(walk.main([str(BLOB), "--top", "1"]), 1)
        with mock.patch("sys.stdout"):
            self.assertEqual(walk.main([str(BLOB), "--top", "1"]), 0)


class BakeTest(unittest.TestCase):
    def test_a_face_square_to_the_noon_sun_bakes_to_level_7_the_far_grounds_level(self) -> None:
        self.assertEqual(bake.level((0.0, 1.0, 0.0), kit.sun(salt())), 7)  # its mood block's far-ground level (tools/racer/mood.py)

    def test_a_face_turned_from_the_sun_is_at_most_three_levels_darker(self) -> None:
        sun = kit.sun(salt())
        self.assertEqual(bake.level(ktrk.unit((-sun[0], -sun[1], -sun[2])), sun), bake.LO)
        self.assertIn(bake.level((1.0, 0.0, 0.0), sun), range(bake.LO, bake.HI))

    def test_the_road_panels_alternate_10_to_25_luma_apart_at_their_baked_level(self) -> None:
        pal = salt()["palette"]
        a, b = (bake.luma(bake.shown(tuple(pal[m]), 7)) for m in ("asphalt_a", "asphalt_b"))
        self.assertTrue(10 <= abs(a - b) <= 25, (a, b))
        self.assertTrue(80 <= min(a, b) and max(a, b) <= 130, "road panels are mid tones")

    def test_every_face_keeps_the_lit_and_soft_debug_shades(self) -> None:
        colour, alt = bake.shader({"x": 3}, (0.0, 1.0, 0.0))("x", (0.0, 1.0, 0.0))
        self.assertEqual(colour, 16 + 24 + 7)
        self.assertTrue(16 + 24 <= alt & 0xFF < 16 + 32 and 16 + 24 <= alt >> 8 < 16 + 32)


class BudgetTest(unittest.TestCase):
    def setUp(self) -> None:
        self.doc = salt()

    def refused(self, doc: ktrk.Doc, text: str) -> None:
        with self.assertRaises(trackc.ConvertError) as cm:
            kit.convert(doc)
        self.assertIn(text, str(cm.exception))

    def test_a_planted_over_budget_tile_is_refused_naming_the_tile(self) -> None:
        b = ktrk.Builder()
        b.vertices, b._index = self.doc["vertices"], {tuple(v): i for i, v in enumerate(self.doc["vertices"])}
        for k in range(limits.TILE_FACES + 1):
            x, z = 60.5 + (k % 8) * 0.3, 60.5 + (k // 8) * 0.3
            self.doc["faces"].append(b.face([b.vert(x, 1, z), b.vert(x + 0.5, 1, z), b.vert(x, 2, z)], "prop", "pylon"))
        self.refused(self.doc, f"SOFT limit: faces in the busiest tile {limits.TILE_FACES + 1} > {limits.TILE_FACES} (tile 23,23)")

    def test_too_many_faces_vertices_or_segments_are_refused(self) -> None:
        for name, text in (("TRACK_FACES", "faces (with decals)"), ("TRACK_VERTICES", "vertices"), ("MAX_SEGMENTS", "HARD limit: racing-line")):
            with self.subTest(name), mock.patch.object(limits, name, 10):
                self.refused(self.doc, text)

    def test_more_materials_than_free_ramps_is_refused(self) -> None:
        for k in range(len(limits.FREE_RAMPS)):
            self.doc["palette"][f"m{k}"] = [k, k, k]
            self.doc["faces"][k]["mat"] = f"m{k}"
        self.refused(self.doc, "HARD limit: colour ramps")

    def test_a_grid_without_eight_slots_is_refused(self) -> None:
        self.doc["start_grid"] = self.doc["start_grid"][:7]
        self.refused(self.doc, "start grid has 7 slots")

    def test_checkpoints_out_of_order_are_refused(self) -> None:
        self.doc["checkpoints"] = [87, 43, 131, 175]
        self.refused(self.doc, "must ascend strictly")

    def test_a_zero_area_face_is_refused_not_divided_by_zero(self) -> None:
        v = self.doc["faces"][5]["v"]
        self.doc["faces"][5]["v"] = [v[0], v[0], v[1]]
        self.refused(self.doc, "face 5 has no area")

    def test_the_meter_rows_mark_the_hard_limits(self) -> None:
        hard = {label for label, _, _, h in budget.rows(budget.meter(self.doc)) if h}
        self.assertEqual(hard, {"colour ramps", "racing-line segments"})


class PaletteTest(unittest.TestCase):
    def test_the_far_ground_goes_on_ramp_1_and_the_car_ramps_stay_put(self) -> None:
        at, mats = kit.ramps(salt())
        self.assertEqual(at["salt"], 1)
        self.assertEqual({m: mats[m][0] for m in limits.CAR_RAMPS}, {"car_body": 12, "car_dark": 13, "car_glass": 14})
        self.assertEqual(sorted(r for r, _ in mats.values()), list(range(len(mats))))  # contiguous: pads fill the gaps

    def test_authoring_mistakes_in_the_palette_are_refused(self) -> None:
        cases = (("palette", None, "needs 'palette'"), ("far_ground", "lava", "far_ground 'lava'"),
                 ("mood", {"sun": [0, -1, 0]}, "above the horizon"))
        for key, val, text in cases:
            doc = salt()
            if val is None:
                del doc[key]
            else:
                doc[key] = val
            with self.subTest(key), self.assertRaises(trackc.ConvertError) as cm:
                kit.ramps(doc) if key != "mood" else kit.sun(doc)
            self.assertIn(text, str(cm.exception))

    def test_a_material_without_a_colour_or_a_bad_colour_is_refused(self) -> None:
        doc = salt()
        del doc["palette"]["pylon"]
        with self.assertRaises(trackc.ConvertError):
            kit.ramps(doc)
        doc = salt()
        doc["palette"]["pylon"] = [300, 0, 0]
        with self.assertRaises(trackc.ConvertError):
            kit.ramps(doc)


if __name__ == "__main__":
    unittest.main()
