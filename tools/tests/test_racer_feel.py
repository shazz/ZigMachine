"""Kestrel Racing, the 32X feel (R82, docs/ports/kestrel_racing/FEEL.md): the ARCADE engine's twin and fit, the AI's cues, the
mood's world / car scales, the shadow headroom and the 32X import's feel logic. No Sega data: synthetic inputs only."""

from __future__ import annotations

import copy
import itertools
import json
import math
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from racer import cues, feel, feel_fit, gen_track, mood, trackc, vr32x_feel, vr_colours
from racer.vr32x_tables import Course

FORMULA = feel.Block.of(feel.CLASSES[0])


class EngineTest(unittest.TestCase):
    def test_the_generated_zig_block_is_what_feel_py_writes_today(self) -> None:
        self.assertEqual(feel.main(["--check"]), 0)

    def test_full_throttle_reaches_the_top_and_never_passes_it(self) -> None:
        up = feel.run(FORMULA, 900)
        self.assertLessEqual(max(up), FORMULA.top)
        self.assertGreater(up[-1], FORMULA.top * 0.97)
        self.assertTrue(all(b >= a for a, b in itertools.pairwise(up)))

    def test_each_class_times_land_in_their_order_formula_quickest_off_the_line(self) -> None:
        to = [feel.ticks_to(feel.run(feel.Block.of(k), 900), 100) for k in feel.CLASSES]
        self.assertEqual(to, sorted(to))

    def test_off_road_settles_slower_with_more_wheels_off(self) -> None:
        full = feel.run(FORMULA, 900, FORMULA.top, off=feel.OFF_FULL)[-1]
        half = feel.run(FORMULA, 900, FORMULA.top, off=feel.OFF_HALF)[-1]
        self.assertLess(full, half)
        self.assertLess(half, FORMULA.top * 0.8)

    def test_the_brake_stops_the_car_and_never_reverses_it(self) -> None:
        self.assertEqual(feel.step(FORMULA, 10, 0, 256, feel.OFF_NONE), 0)

    def test_a_net_curve_not_ending_at_the_top_is_refused(self) -> None:
        bad = replace(feel.CLASSES[0], net=((0, 50.0), (100, 10.0)))
        with self.assertRaises(ValueError):
            feel.Block.of(bad)

    def test_a_curve_whose_speeds_do_not_rise_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            feel.Curve.of(((0, 1.0), (0, 2.0)))


class FitTest(unittest.TestCase):
    def test_residuals_of_a_target_equal_to_our_own_model_are_zero(self) -> None:
        up = feel.run(FORMULA, 900)
        down = feel.run(FORMULA, 900, FORMULA.top, held=False)
        target = {"accel": {"100": feel.ticks_to(up, 100), "200": feel.ticks_to(up, 200)},
                  "coast": {"200": next(i + 1 for i, s in enumerate(down) if s * feel.KMH <= 200 << 16)},
                  "off_full": feel_fit._off_eq(FORMULA, feel.OFF_FULL), "off_half": feel_fit._off_eq(FORMULA, feel.OFF_HALF)}
        r = feel_fit.residuals(feel.CLASSES[0], target)
        self.assertTrue(all(abs(v) < 1e-9 for v in r.values()), r)

    def test_the_fit_keeps_the_curves_physical(self) -> None:
        self.assertTrue(all(feel_fit._falling(k) for k in feel.CLASSES))
        rising = replace(feel.CLASSES[0], net=((0, 10.0), (100, 20.0), (200, 5.0), (280, 1.0), (330, 0.0)))
        self.assertFalse(feel_fit._falling(rising))

    def test_a_targets_file_with_the_wrong_class_count_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "t.json"
            p.write_text(json.dumps({"classes": []}))
            self.assertEqual(feel_fit.main([str(p)]), 1)


def _circle(r: float, n: int = 64) -> dict:
    """A ring racing line of radius r (units), road 6 wide."""
    vs, line = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for rr in (r - 3, r + 3):
            vs.append([round(rr * math.cos(a) * 128), 0, round(rr * math.sin(a) * 128)])
        line.append({"l": 2 * i, "r": 2 * i + 1})
    return {"vertices": vs, "racing_line": line}


def _wide(r: float) -> dict:
    d = _circle(r)
    d["vertices"] = [[x * 2, y, z * 2] if i % 2 else v for i, (v, (x, y, z)) in enumerate(zip(d["vertices"], d["vertices"], strict=True))]
    return d


class CuesTest(unittest.TestCase):
    def test_a_wide_ring_is_flat_out_and_a_tight_one_is_not(self) -> None:
        self.assertEqual(set(cues.bake(_circle(2000), 256)), {255})
        tight = cues.bake(_circle(20), 1024)
        self.assertLess(max(tight), 255)
        self.assertGreaterEqual(min(tight), 1)

    def test_a_bigger_world_scale_lowers_every_cue(self) -> None:
        a, b = cues.bake(_circle(40), 256), cues.bake(_circle(40), 1024)
        self.assertTrue(all(y <= x for x, y in zip(a, b, strict=True)) and sum(b) < sum(a))

    def test_trackc_writes_a_cue_into_the_line_flags_high_byte_and_refuses_one_out_of_range(self) -> None:
        doc = gen_track.build_oval()
        doc["racing_line"][0]["cue"] = 200
        blob = trackc.convert(doc)
        at = int.from_bytes(blob[4 * 21:4 * 22], "little")  # the line block
        self.assertEqual(int.from_bytes(blob[at + 14:at + 16], "little") >> 8, 200)
        bad = copy.deepcopy(doc)
        bad["racing_line"][0]["cue"] = 300
        with self.assertRaises(trackc.ConvertError):
            trackc.convert(bad)


class ScaleTest(unittest.TestCase):
    def test_no_scale_packs_the_32_byte_block_every_earlier_file_has(self) -> None:
        self.assertEqual(len(mood.Mood().pack()), mood.SIZE)

    def test_a_scale_packs_36_bytes_and_reads_back(self) -> None:
        m = mood.Mood(world=1067, car=640)
        self.assertEqual(len(m.pack()), mood.SCALED)
        blob = gen_track.build_oval()
        out = trackc.convert(blob, look=m)
        self.assertEqual((mood.unpack(out).world, mood.unpack(out).car), (1067, 640))

    def test_a_scale_out_of_range_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            mood.Mood(world=10).pack()


class HeadroomTest(unittest.TestCase):
    def test_the_headroom_byte_keeps_level_0_off_the_ramp_bottom_and_leaves_the_rest(self) -> None:
        shade = vr_colours.shader({0x10: (3, 0), 0x11: (3, 5)}, headroom=True)
        base = 16 + 3 * 8
        for mat, level in (("c10", 0), ("c11", 5)):
            c, alt = shade(mat, (0.0, 1.0, 0.0))
            self.assertEqual(c, base + level)
            self.assertEqual(alt >> 16 & 0xFF, base + max(1, level))

    def test_without_the_option_no_headroom_byte(self) -> None:
        _, alt = vr_colours.shader({0x10: (3, 0)})("c10", (0.0, 1.0, 0.0))
        self.assertEqual(alt >> 16, 0)


class Vr32xFeelTest(unittest.TestCase):
    def test_the_world_scale_follows_the_road_width(self) -> None:
        w = vr32x_feel.world(_circle(100))  # a 6-unit road: 13 m is ~2.2 m a unit
        self.assertAlmostEqual(w, 256 * vr32x_feel.FREDS_M * 6 / vr32x_feel.ROAD_M, delta=2)
        self.assertLess(vr32x_feel.world(_circle(100)), vr32x_feel.world(_wide(100)))

    def test_the_32x_cue_maps_onto_ours_and_never_above_our_geometric_bake(self) -> None:
        doc = _circle(2000, 8)
        lines = [[(0, 0, -100 if i == 3 else 0) for i in range(8)]]
        c = Course(path=[(0, 0)] * 8, pit=[], lines=lines, bmap=list(range(8)))
        got = vr32x_feel.ai_cues(doc, c, 256)
        self.assertEqual(got[2], round(255 - 100 * vr32x_feel.CUE_GAIN))  # segment 2 holds point 3
        self.assertEqual([g for i, g in enumerate(got) if i != 2], [255] * 7)

    def test_an_ai_line_shorter_than_the_racing_line_is_refused(self) -> None:
        c = Course(path=[], pit=[], lines=[[(0, 0, 0)] * 3], bmap=[])
        with self.assertRaises(ValueError):
            vr32x_feel.ai_cues(_circle(100, 8), c, 256)


if __name__ == "__main__":
    unittest.main()
