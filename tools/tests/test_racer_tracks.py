"""Kestrel Racing M5 step 2: Neon Docks and Glacier Pass (generated Blender scenes -> the add-on's export -> kit.py), and the
mood block every track file carries (tools/racer/mood.py; the cart reads it in apps/zig/scenes/racer/trk.zig)."""

from __future__ import annotations

import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from racer import bake, budget, gen_city, kit, ktrk, ktrk_check, limits, mood, trackc, walk
from racer import ref_render as rr
from racer import ref_sky

ROOT = Path(__file__).resolve().parents[2]
TRACKS = ROOT / "tools/racer/tracks"
ASSETS = ROOT / "apps/zig/assets/screens/racer"
BLENDER = Path.home() / ".local/blender/blender"
# name -> (binary, segments, backdrop, the most faces we allow it)
AUTHORED = {"neon_docks": ("neon", 148, "docks", 2500), "glacier_pass": ("glacier", 236, "peaks", 2500)}


def doc(name: str) -> ktrk.Doc:
    return ktrk.loads((TRACKS / f"{name}.ktrk.json").read_text())


class AuthoredTracksTest(unittest.TestCase):
    def test_each_committed_binary_is_what_the_kit_converter_writes_from_its_committed_export(self) -> None:
        for name, (blob, *_) in AUTHORED.items():
            with self.subTest(name):
                self.assertEqual((ASSETS / f"{blob}.ktrk").read_bytes(), kit.convert(doc(name)))

    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_each_blender_build_script_exports_the_committed_document(self) -> None:
        for name in AUTHORED:
            with self.subTest(name), tempfile.TemporaryDirectory() as tmp:
                out = Path(tmp) / "t.json"
                subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(TRACKS / f"{name}_build.py"), "--", str(out)],
                               check=True, capture_output=True, timeout=300)
                self.assertEqual(out.read_text(), (TRACKS / f"{name}.ktrk.json").read_text())

    def test_each_track_is_inside_its_budget_validates_and_has_its_line_grid_and_checkpoints(self) -> None:
        for name, (_, segments, _, most) in AUTHORED.items():
            with self.subTest(name):
                d = doc(name)
                self.assertEqual((budget.problems(d), ktrk_check.validate(d)), ([], []))
                m = budget.meter(d)
                self.assertLessEqual(m.faces, most)
                self.assertEqual((m.segments, len(d["start_grid"]), len(d["checkpoints"])), (segments, 8, 4))

    def test_each_heavy_pose_list_is_what_the_walk_finds_today_and_every_pose_is_under_the_ceiling_at_r8(self) -> None:
        for name, (blob, *_) in AUTHORED.items():
            with self.subTest(name):
                t = rr.Track((ASSETS / f"{blob}.ktrk").read_bytes())
                self.assertEqual(json.loads((TRACKS / f"{name}.heavy.json").read_text())["frames"],
                                 [p.frame for p in walk.heaviest(walk.walk(t))])
                self.assertLess(max(p.mc for p in walk.walk(t, r=8)), limits.FRAME_MC)

    def test_each_mood_block_names_its_backdrop_sky_and_a_far_ground_at_the_baked_flat_level(self) -> None:
        for name, (blob, _, shape, _) in AUTHORED.items():
            with self.subTest(name):
                d, got = doc(name), mood.unpack((ASSETS / f"{blob}.ktrk").read_bytes())
                self.assertEqual(got.backdrop, mood.BACKDROPS.index(shape))
                self.assertEqual(got.ground_level, bake.level((0.0, 1.0, 0.0), kit.sun(d)))
                self.assertEqual(list(got.sky[0] + got.sky[1]), d["mood"]["sky"])

    def test_the_road_panels_alternate_in_close_tones(self) -> None:
        for name in AUTHORED:
            with self.subTest(name):
                pal = doc(name)["palette"]
                a, b = (bake.luma(bake.shown(tuple(pal[m]), 7)) for m in ("asphalt_a", "asphalt_b"))
                self.assertTrue(8 <= abs(a - b) <= 25, (a, b))


class MoodTest(unittest.TestCase):
    def test_the_oval_has_no_block_and_reads_as_the_defaults(self) -> None:
        blob = (ASSETS / "oval.ktrk").read_bytes()
        self.assertEqual((blob[100:104], mood.unpack(blob)), (bytes(4), mood.Mood()))

    def test_the_city_is_benchmark_only_on_the_plaza_ramp(self) -> None:
        self.assertEqual(mood.unpack((ASSETS / "city.ktrk").read_bytes()), gen_city.MOOD)
        self.assertEqual((gen_city.MOOD.ground_ramp, gen_city.MOOD.flags), (8, mood.BENCH_ONLY))

    def test_a_block_is_the_files_last_32_bytes_inside_the_crc(self) -> None:
        blob = (ASSETS / "salt.ktrk").read_bytes()
        at = int.from_bytes(blob[100:104], "little")
        self.assertEqual(at + len(mood.unpack(blob).pack()), len(blob))
        self.assertIn(len(blob) - at, (mood.SIZE, mood.SCALED))

    def test_a_track_clock_packs_into_bytes_24_25_and_reads_back_and_the_shipped_tracks_leave_it_to_the_cart(self) -> None:
        d = doc("neon_docks")
        d["mood"]["clock"] = [120, 18]
        m = kit.look(d)
        self.assertEqual(m.pack()[24:26], bytes([120, 18]))
        self.assertEqual(m.pack()[26:32], bytes(6))  # the scale tail (R82 32X feel) follows: the Kit default
        self.assertEqual(m.pack()[32:], struct.pack("<2H", kit.KIT_WORLD, kit.KIT_CAR))
        for blob in ("salt", "neon", "glacier", "city"):
            with self.subTest(blob):
                self.assertEqual(mood.unpack((ASSETS / f"{blob}.ktrk").read_bytes()).clock, (0, 0))  # computed (clock.zig)

    def test_bad_moods_are_refused_by_the_converter(self) -> None:
        for bad in (mood.Mood(ground_level=8), mood.Mood(backdrop=3), mood.Mood(flags=4), mood.Mood(sky=((0, 0, 256), (0, 0, 0))),
                    mood.Mood(clock=(251, 0)), mood.Mood(clock=(0, 61))):
            with self.subTest(bad), self.assertRaises(ValueError):
                bad.pack()
        with self.assertRaises(trackc.ConvertError):
            trackc.convert(gen_city.build_city(2), look=mood.Mood(ground_ramp=40))

    def test_an_unknown_backdrop_name_or_a_short_sky_is_refused_by_the_kit(self) -> None:
        for key, value in (("backdrop", "moon"), ("sky", [1, 2, 3]), ("clock", [90]), ("clock", [300, 10])):
            d = doc("neon_docks")
            d["mood"][key] = value
            with self.subTest(key), self.assertRaises(trackc.ConvertError):
                kit.look(d)

    def test_each_backdrop_strip_wraps_and_uses_only_the_three_backdrop_entries(self) -> None:
        for shape in range(len(mood.BACKDROPS)):
            with self.subTest(shape):
                s = ref_sky.strip(shape)
                self.assertEqual(set(s) - {0}, {ref_sky.FAR, ref_sky.NEAR, ref_sky.SKYLINE})
                self.assertTrue(all(v == 0 for v in s[ref_sky.H * ref_sky.W:]))


if __name__ == "__main__":
    unittest.main()
