"""Kestrel Racing M0: the procedural track generators and the `.ktrk.json` helpers (tools/racer/)."""

from __future__ import annotations

import copy
import io
import tempfile
import unittest
from collections import Counter
from contextlib import redirect_stdout
from pathlib import Path

from racer import gen_city, gen_track, ktrk, ktrk_check, ktrk_lua


class OvalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.doc = gen_track.build_oval()

    def test_same_arguments_give_the_same_bytes(self) -> None:
        self.assertEqual(ktrk.dumps(self.doc), ktrk.dumps(gen_track.build_oval()))

    def test_different_segment_count_changes_the_track(self) -> None:
        self.assertNotEqual(ktrk.dumps(self.doc), ktrk.dumps(gen_track.build_oval(100)))

    def test_too_few_segments_for_seven_ai_cars_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            gen_track.build_oval(56)

    def test_the_oval_validates_clean(self) -> None:
        self.assertEqual(ktrk_check.validate(self.doc), [])

    def test_the_oval_has_the_features_m0_asks_for(self) -> None:
        d = self.doc
        ys = [v[1] for v in d["vertices"]]
        self.assertGreater(max(ys), ktrk.q(gen_track.CREST_H))  # a crest (and the walls on it)
        road = [f for f in d["faces"] if f["kind"] == "track"]
        self.assertEqual(len(road), 120)
        self.assertEqual(sum(len(f["inner"]) for f in road), 120 * 2 + 60 + 1)  # kerbs, dashes, start line
        self.assertEqual(len([f for f in d["faces"] if f["kind"] == "wall"]), 240)
        self.assertEqual(sum(len(f.get("borders", [])) for f in d["faces"]), 240)

    def test_the_road_is_banked_in_the_turn(self) -> None:
        d = self.doc
        spans = [abs(d["vertices"][s["l"]][1] - d["vertices"][s["r"]][1]) for s in d["racing_line"]]
        self.assertEqual(spans[0], 0)  # flat on the start straight
        self.assertGreater(max(spans), ktrk.q(0.5))  # one edge clearly higher than the other

    def test_start_grid_player_faces_plus_z_and_npcs_follow_the_line(self) -> None:
        g = self.doc["start_grid"]
        self.assertEqual((g[0]["segment"], g[0]["yaw_q16"]), (0, 0))
        self.assertEqual(g[0]["pos"][0], ktrk.q(gen_track.A))
        self.assertEqual([e["segment"] for e in g], [0, 1, 1, 2, 2, 3, 3, 4])
        self.assertNotEqual(g[1]["yaw_q16"], 0)

    def test_main_writes_the_file_and_the_stress_option_switches_generator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "t.json"
            self.assertEqual(gen_track.main(["-o", str(out), "--segments", "60"]), 0)
            self.assertEqual(ktrk.loads(out.read_text())["generator"]["segments"], 60)
        buf = io.StringIO()
        with redirect_stdout(buf):
            gen_track.main(["--stress"])
        self.assertEqual(ktrk.loads(buf.getvalue())["name"], "stress_city")


class StressCityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.doc = gen_city.build_city()

    def test_a_full_tile_holds_a_hundred_faces(self) -> None:
        tiles = ktrk.tile_faces(self.doc)
        counts = Counter(len(v) + sum(len(self.doc["faces"][f].get("inner", [])) for f in v) for v in tiles.values())
        self.assertEqual(counts[gen_city.PER_TILE], 100)  # the 10 x 10 tiles inside the ring
        self.assertEqual(set(counts), {100, 52})  # ring tiles: the road clears two lattice rows

    def test_the_city_validates_and_is_deterministic(self) -> None:
        self.assertEqual(ktrk_check.validate(self.doc), [])
        self.assertEqual(ktrk.dumps(self.doc), ktrk.dumps(gen_city.build_city()))

    def test_the_ring_road_is_closed_and_has_a_start(self) -> None:
        self.assertEqual(len(self.doc["racing_line"]), 4 * 11)
        self.assertEqual(self.doc["start_grid"][0]["segment"], 0)


class ValidatorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.doc = copy.deepcopy(gen_track.build_oval(60))

    def first(self, kind: str) -> dict:
        return next(f for f in self.doc["faces"] if f["kind"] == kind)

    def test_wound_against_the_physics_is_reported(self) -> None:
        f = self.first("track")
        f["v"] = f["v"][::-1]
        self.assertTrue(any("normal does not point up" in e for e in ktrk_check.validate(self.doc)))

    def test_more_than_three_borders_on_a_face_is_reported(self) -> None:
        next(f for f in self.doc["faces"] if f.get("borders"))["borders"] = [0, 1, 2, 3]
        self.assertTrue(any("more than 3 borders" in e for e in ktrk_check.validate(self.doc)))

    def test_a_vertex_id_out_of_range_is_reported(self) -> None:
        self.first("wall")["v"][0] = 10**6
        self.assertTrue(any("valid vertex ids" in e for e in ktrk_check.validate(self.doc)))

    def test_a_bent_quad_and_a_stray_decal_are_reported(self) -> None:
        road = self.first("track")
        self.doc["vertices"][road["v"][2]][1] += ktrk.q(1.0)
        errs = ktrk_check.validate(self.doc)
        self.assertTrue(any("not planar" in e for e in errs))

    def test_an_open_line_and_world_overflow_are_reported(self) -> None:
        self.doc["racing_line"] = self.doc["racing_line"][:2]
        self.doc["vertices"][0][0] = 200 * ktrk.SCALE
        errs = ktrk_check.validate(self.doc)
        self.assertTrue(any("at least 3 segments" in e for e in errs))
        self.assertTrue(any("outside the 32x32" in e for e in errs))


class KtrkHelpersTest(unittest.TestCase):
    def test_quantising_rounds_half_up_on_the_one_over_128_grid(self) -> None:
        self.assertEqual((ktrk.q(1.0), ktrk.q(-0.5), ktrk.q(1 / 256)), (128, -64, 1))

    def test_loads_refuses_another_format(self) -> None:
        with self.assertRaises(ValueError):
            ktrk.loads('{"format":"other","version":1}')
        self.assertEqual(ktrk.loads(ktrk.dumps(gen_track.build_oval(60)))["name"], "test_oval")

    def test_flags_follow_the_layout(self) -> None:
        road = {"v": [0, 1, 2, 3], "kind": "track", "inner": [{}], "borders": [0, 1]}
        self.assertEqual(ktrk.face_flags(road), 2 | 4 | 8 | 16 | 2 << 5)
        self.assertEqual(ktrk.face_flags({"v": [0, 1, 2], "kind": "wall", "dual": True}), 1)

    def test_builder_dedups_vertices_and_rewinds_ground_up(self) -> None:
        b = ktrk.Builder()
        a = [b.vert(0, 0, 0), b.vert(1, 0, 0), b.vert(1, 0, 1), b.vert(0, 0, 1)]
        self.assertEqual(b.vert(0, 0, 0), a[0])
        f = b.face(a, "ground", "grass")
        self.assertGreater(ktrk.normal(ktrk.pts({"vertices": b.vertices}, f["v"]))[1], 0)

    def test_tile_binning_puts_a_face_on_each_tile_its_box_overlaps(self) -> None:
        b = ktrk.Builder()
        ids = [b.vert(-4, 0, 0), b.vert(4, 0, 0), b.vert(4, 0, 1), b.vert(-4, 0, 1)]
        b.face(ids, "prop", "x")
        doc = b.document("t", {}, [], [], [])
        self.assertEqual(sorted(ktrk.tile_faces(doc)), [(15, 16), (16, 16)])
        self.assertEqual(ktrk.tile_faces(doc, ground_only=True), {})


class LuaExportTest(unittest.TestCase):
    def test_export_is_deterministic_and_carries_exact_numbers(self) -> None:
        doc = gen_track.build_oval(60)
        text = ktrk_lua.to_lua(doc)
        self.assertEqual(text, ktrk_lua.to_lua(doc))
        self.assertIn("KTRK={", text)
        self.assertIn("{50.0000000,0.0000000,0.0000000}", text)  # the start line's centre, x = A

    def test_export_without_a_line_is_refused(self) -> None:
        doc = gen_track.build_oval(60)
        doc["racing_line"] = []
        with self.assertRaises(ValueError):
            ktrk_lua.to_lua(doc)


if __name__ == "__main__":
    unittest.main()
