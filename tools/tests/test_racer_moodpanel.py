"""Kestrel Racing M5 finish: the Track Kit's mood properties as panel rows (tools/racer/mood_props.py, and headless in
Blender the add-on's "Add mood properties" operator, tools/racer/blender/moodpanel.py)."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

from racer import kit, mood, mood_props, trackc

ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path.home() / ".local/blender/blender"

HEADLESS = """
import sys; sys.path.insert(0, "tools")
import bpy, racer.blender as k
from racer.blender import moodpanel
bpy.ops.wm.read_factory_settings(use_empty=True)
k.register()
sc = bpy.context.scene
sc["ktrk_sky"] = [1, 2, 3, 4, 5, 6]
assert bpy.ops.ktrk.mood_defaults() == {"FINISHED"}
assert list(sc["ktrk_sky"]) == [1, 2, 3, 4, 5, 6], "an existing property was overwritten"
assert str(sc["ktrk_backdrop"]) == "hills" and list(sc["ktrk_clock"]) == [0, 0]
assert moodpanel.add_missing(sc) == []
assert "KTRK_PT_mood" in dir(bpy.types)
print("MOODPANEL OK")
"""


class MoodPropsTest(unittest.TestCase):
    def test_every_scene_property_the_export_reads_has_a_row(self) -> None:
        self.assertEqual({p.key for p in mood_props.PROPS},
                         {"name", "mood", "sun", "far_ground", "sky", "hills", "backdrop", "clock", "draw_r"})

    def test_defaults_are_the_ovals_look_and_pass_their_own_checks(self) -> None:
        by = {p.key: p for p in mood_props.PROPS}
        self.assertEqual(by["sky"].default, [28, 60, 150, 170, 205, 235])
        self.assertEqual(by["backdrop"].default, mood.BACKDROPS[0])
        for p in mood_props.PROPS:
            self.assertEqual(mood_props.problem(p, p.default), "", p.key)

    def test_missing_lists_only_the_unset_properties(self) -> None:
        got = [p.key for p in mood_props.missing({"ktrk_name", "ktrk_sky", "other"})]
        self.assertEqual(got, ["mood", "sun", "far_ground", "hills", "backdrop", "clock", "draw_r"])

    def test_a_value_the_converter_refuses_is_named(self) -> None:
        by = {p.key: p for p in mood_props.PROPS}
        self.assertIn("one of", mood_props.problem(by["backdrop"], "desert"))
        self.assertIn("6 numbers", mood_props.problem(by["sky"], [1, 2, 3]))
        self.assertIn("0..255", mood_props.problem(by["hills"], [300] * 9))
        self.assertIn("clock", mood_props.problem(by["clock"], [251, 0]))
        self.assertIn("3 numbers", mood_props.problem(by["sun"], "up"))
        self.assertIn("draw_r", mood_props.problem(by["draw_r"], 2))
        self.assertEqual(mood_props.problem(by["draw_r"], 6), "")

    def test_the_defaults_convert_to_the_same_mood_as_absent_properties(self) -> None:
        doc = json.loads((ROOT / "tools/racer/tracks/salt_flats.ktrk.json").read_text())
        for k in ("sky", "hills", "backdrop", "clock", "draw_r"):
            doc["mood"].pop(k, None)
        bare = kit.look(doc)
        by = {p.key: p for p in mood_props.PROPS}
        for k in ("sky", "hills", "backdrop", "clock", "draw_r"):
            doc["mood"][k] = by[k].default
        self.assertEqual(kit.look(doc), bare)
        self.assertEqual(by["sun"].default, (0.0, 0.0, 1.0))  # the add-on's extract() when ktrk_sun is absent

    def test_draw_r_packs_reads_back_and_is_refused_out_of_range(self) -> None:
        m = mood.Mood(draw_r=6)
        blob = bytearray(200)
        blob[4 * mood.WORD:4 * mood.WORD + 4] = (128).to_bytes(4, "little")
        blob[128:160] = m.pack()
        self.assertEqual(mood.unpack(bytes(blob)).draw_r, 6)
        self.assertEqual(m.pack()[26], 6)
        for bad in (1, 2, 9):
            with self.assertRaises(ValueError):
                mood.Mood(draw_r=bad).pack()
        doc = json.loads((ROOT / "tools/racer/tracks/salt_flats.ktrk.json").read_text())
        doc["mood"]["draw_r"] = 6
        self.assertEqual(kit.look(doc).draw_r, 6)
        doc["mood"]["draw_r"] = 12
        with self.assertRaises(trackc.ConvertError):
            kit.look(doc)

    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_blender_operator_adds_the_missing_properties_and_keeps_the_set_ones(self) -> None:
        r = subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python-expr", HEADLESS], cwd=ROOT,
                           capture_output=True, text=True, timeout=300, check=False)
        self.assertIn("MOODPANEL OK", r.stdout, r.stdout[-2000:] + r.stderr[-2000:])


if __name__ == "__main__":
    unittest.main()
