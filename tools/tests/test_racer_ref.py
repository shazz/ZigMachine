"""Kestrel Racing M0: the Lua reference harness (tools/racer/ref_harness.py): freds72's physics under z8lua on
our generated oval. The runs need z8lua and the engine source (git-ignored, prototypes/racer_re/ of the main
checkout; RACER_Z8LUA / RACER_FREDS72 override) and are skipped without them."""

from __future__ import annotations

import os
import unittest
from unittest import mock

from racer import gen_track, ktrk, ref_harness


def _available() -> bool:
    try:
        ref_harness.z8lua_path()
        ref_harness.source_path()
    except ref_harness.HarnessUnavailable:
        return False
    return True


class ExtractTest(unittest.TestCase):
    def test_extract_takes_whole_top_level_functions(self) -> None:
        src = "function a(x)\n\tif x then\n\t\treturn 1\n\tend\nend\nfunction b()\nend\n__gfx__\nfunction c()\nend\n"
        out = ref_harness.extract(src, ["a", "b"])
        self.assertIn("return 1", out)
        self.assertNotIn("function c", out)

    def test_extract_of_a_missing_function_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            ref_harness.extract("function a()\nend\n", ["nope"])


class ParseTest(unittest.TestCase):
    def test_parse_reads_signed_raw_16_16(self) -> None:
        cols = "tick\tcar\tpx\tpy\tpz\tvx\tvy\tvz\tangle\tface\tu\tv\tbtn\thits"
        row = "\t".join(["1", "0", "0x0001.8000", "0xffff.8000"] + ["0x0000.0000"] * 5 + ["0x0002.0000", "0x0000.0000", "0x0000.0000", "16", "3"])
        r = ref_harness.parse(cols + "\n" + row)[0]
        self.assertEqual((r["px"], r["py"], r["face"], r["btn"], r["hits"]), (0x18000, -0x8000, 0x20000, 16, 3))

    def test_parse_of_a_short_row_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            ref_harness.parse("tick\tcar\n1")


class UnavailableTest(unittest.TestCase):
    def test_a_missing_binary_is_reported_not_run(self) -> None:
        with mock.patch.dict(os.environ, {"RACER_Z8LUA": "/nonexistent/z8lua"}):
            with self.assertRaises(ref_harness.HarnessUnavailable):
                ref_harness.run(gen_track.build_oval(60))

    def test_an_unknown_scenario_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            ref_harness.run(gen_track.build_oval(60), scenario="nope")


@unittest.skipUnless(_available(), "z8lua / freds72_src not on this machine")
class ReferenceRunTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.doc = gen_track.build_oval()
        cls.lap = ref_harness.run(cls.doc)

    def test_two_runs_dump_identical_bytes(self) -> None:
        self.assertEqual(self.lap, ref_harness.run(self.doc))

    def test_dump_has_600_ticks_for_three_cars(self) -> None:
        rows = ref_harness.parse(self.lap)
        self.assertEqual(len(rows), 600 * 3)
        self.assertEqual({r["car"] for r in rows}, {0, 1, 2})

    def test_cars_stay_on_ground_faces_and_make_progress_round_the_oval(self) -> None:
        rows = ref_harness.parse(self.lap)
        self.assertEqual([r for r in rows if r["face"] == 0], [])
        player = [r for r in rows if r["car"] == 0]
        self.assertGreater(player[-1]["u"] / 65536, 30)  # segments covered (a segment is ~3.8 units)
        self.assertEqual(player[-1]["hits"], 0)  # the autopilot never touches a wall

    def test_the_wall_scenario_hits_a_wall(self) -> None:
        rows = ref_harness.parse(ref_harness.run(self.doc, "wall"))
        self.assertGreater(rows[-1]["hits"], 10)
        self.assertEqual([r for r in rows if r["face"] == 0], [])

    def test_replaying_the_dumped_buttons_reproduces_the_dump(self) -> None:
        player = [r for r in ref_harness.parse(self.lap) if r["car"] == 0]
        buttons = [r["btn"] for r in player]
        self.assertEqual(ref_harness.run(self.doc, "replay", inputs=buttons), self.lap)

    def test_a_different_track_gives_a_different_dump(self) -> None:
        self.assertNotEqual(ref_harness.run(gen_track.build_oval(100)), self.lap)
        self.assertEqual(ktrk.loads(ktrk.dumps(self.doc))["name"], "test_oval")


if __name__ == "__main__":
    unittest.main()
