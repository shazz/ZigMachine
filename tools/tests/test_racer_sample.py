"""Kestrel Racing M7: the Track Kit's sample track, Kestrel Oval (tools/racer/tracks/sample_oval_*.py). Its generated Blender
scene exports to the committed document, which uses every authoring convention once, and converts end to end to a cart
file (the gate's racer_library.mjs then loads that file from C:\\RACER\\ in the cart)."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from racer import budget, cues, kit, ktrk, ktrk_check, limits, mood, walk
from racer import ref_render as rr

ROOT = Path(__file__).resolve().parents[2]
TRACKS = ROOT / "tools/racer/tracks"
SAMPLE = TRACKS / "sample_oval.ktrk.json"
BLENDER = Path.home() / ".local/blender/blender"


def doc() -> ktrk.Doc:
    return ktrk.loads(SAMPLE.read_text())


class SampleTrackTest(unittest.TestCase):
    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_the_blender_build_script_exports_the_committed_document(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "t.json"
            subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(TRACKS / "sample_oval_build.py"), "--", str(out)],
                           check=True, capture_output=True, timeout=300)
            self.assertEqual(out.read_text(), SAMPLE.read_text())

    def test_it_is_inside_every_budget_and_validates(self) -> None:
        d = doc()
        self.assertEqual((budget.problems(d), ktrk_check.validate(d)), ([], []))
        m = budget.meter(d)
        self.assertEqual((m.segments, len(d["start_grid"]), d["checkpoints"]), (96, 8, [23, 47, 71, 95]))
        self.assertLessEqual(m.faces, 1000)

    def test_every_face_kind_decals_borders_and_a_double_sided_material_are_used(self) -> None:
        d = doc()
        self.assertEqual({f["kind"] for f in d["faces"]}, set(ktrk.KINDS))
        inner = {i["mat"] for f in d["faces"] for i in f.get("inner", [])}
        self.assertEqual(inner, {"paint", "paint_start", "kerb_a", "kerb_b"})
        self.assertTrue(any(f.get("borders") for f in d["faces"]))
        self.assertTrue(any(f.get("dual") for f in d["faces"] if f["mat"] == "gantry"))

    def test_the_gantry_segments_are_cam_near_roofs(self) -> None:
        self.assertEqual([i for i, s in enumerate(doc()["racing_line"]) if s.get("roof")], list(range(58, 64)))

    def test_the_mood_sets_every_optional_property(self) -> None:
        self.assertEqual(set(doc()["mood"]), {"name", "sun", "sky", "hills", "backdrop", "clock", "draw_r", "haze", "haze_start",
                                              "haze_strength", "world", "car"})

    def test_the_converted_file_carries_the_mood_the_cues_and_holds_the_frame_budget(self) -> None:
        d = doc()
        blob = kit.convert(d)
        m = mood.unpack(blob)
        self.assertEqual((m.clock, m.draw_r, m.haze_strength, m.world, m.car), ((90, 15), 7, 96, kit.KIT_WORLD, kit.KIT_CAR))
        c = cues.bake(d, m.world)
        self.assertTrue(min(c) < 200 and max(c) == 255, (min(c), max(c)))  # slower into the turns, flat out on the straights
        self.assertLess(max(p.mc for p in walk.walk(rr.Track(blob), r=8)), limits.FRAME_MC)

    def test_a_sample_without_its_far_ground_material_is_refused_by_name(self) -> None:
        d = doc()
        del d["palette"][d["far_ground"]]
        with self.assertRaisesRegex(ValueError, "far_ground 'grass' is not in the palette"):
            kit.convert(d)


if __name__ == "__main__":
    unittest.main()
