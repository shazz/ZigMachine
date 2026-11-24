"""Kestrel Racing M1: the Python reference renderer (tools/racer/ref_render.py) and its integer maths."""

from __future__ import annotations

import unittest
from pathlib import Path

from racer import ref_fx as fx
from racer import ref_render as rr

ASSETS = Path(__file__).resolve().parents[2] / "apps" / "zig" / "assets" / "screens" / "racer"


class MathTest(unittest.TestCase):
    def test_sin_cos_hit_the_quarter_turns_exactly(self) -> None:
        self.assertEqual((fx.sin(0), fx.cos(0), fx.sin(1 << 30), fx.cos(1 << 30)), (0, 65536, 65536, 0))
        self.assertEqual(fx.sin(3 << 30), -65536)

    def test_rcp_is_within_2_to_the_minus_14_of_2_32_over_d(self) -> None:
        for d in (2, 3, 100, 16384, 65536, 3 << 16, 123456, 1 << 23):
            self.assertLess(abs(fx.rcp(d) - (1 << 32) / d), (1 << 32) / d * 2**-13 + 1)
        self.assertEqual(fx.rcp(1), 0xFFFFFFFF)

    def test_tdiv_truncates_toward_zero_and_i32_wraps(self) -> None:
        self.assertEqual((fx.tdiv(-7, 2), fx.tdiv(7, -2), fx.tdiv(7, 2)), (-3, -3, 3))
        self.assertEqual(fx.i32(0x80000000), -(1 << 31))

    def test_near_clip_cuts_at_the_plane_and_drops_a_polygon_behind_it(self) -> None:
        q = 65536
        quad = [[-q, 0, -q], [q, 0, -q], [q, 0, 4 * q], [-q, 0, 4 * q]]
        out = fx.clip(quad, 1)
        self.assertEqual(len(out), 4)
        self.assertTrue(all(v[2] >= fx.NEAR for v in out))
        self.assertEqual(fx.clip([[0, 0, 100], [q, 0, 100], [q, q, 100]], 1), [])

    def test_a_shared_edge_is_cut_at_the_same_point_whichever_way_it_is_walked(self) -> None:
        a, b = [40 * 65536 + 123, 3 * 65536 + 7, 7 * 65536 + 11], [-31 * 65536 + 55, 9 * 65536 + 91, -5 * 65536 + 3]
        self.assertEqual(fx._cut(0, a, b), fx._cut(0, b, a))


class RenderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.track = rr.Track((ASSETS / "oval.ktrk").read_bytes())

    def render(self, pose: int, **kw: object) -> bytes:
        pos, yaw, pitch = rr.lap_pose(self.track, pose * 90, pose % 3)
        return rr.render(self.track, pos, yaw, pitch, **kw)  # type: ignore[arg-type]  # [arg-type] kwargs forwarded

    def test_a_view_is_176_rows_fully_painted_and_deterministic(self) -> None:
        a = self.render(2)
        self.assertEqual(len(a), 176 * 320)
        self.assertEqual(a.count(0), 0)
        self.assertEqual(a, self.render(2))

    def test_decals_and_the_draw_distance_change_the_picture(self) -> None:
        self.assertNotEqual(self.render(2), self.render(2, decals=False))
        self.assertNotEqual(self.render(2, r=3), self.render(2, r=8))

    def test_a_camera_tile_the_converter_did_not_bake_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            self.track.baked(0, 0)


if __name__ == "__main__":
    unittest.main()
