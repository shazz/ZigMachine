"""Kestrel Racing M5 finish: camera zones. The reference camera (tools/racer/ref_cam.py) weighs a roofed run as the cart does
(apps/zig/scenes/racer/zone_test.zig pins the same table), the flyby's far camera under a roof is the near one, and the
converter writes the line's roof flag from the Track Kit's CAM_NEAR (the committed Neon Docks / Glacier Pass binaries)."""

from __future__ import annotations

import struct
import unittest
from pathlib import Path

from racer import ref_cam, trackc
from racer import ref_render as rr

ASSETS = Path(__file__).resolve().parents[2] / "apps" / "zig" / "assets" / "screens" / "racer"
ONE = 1 << 16


def line_with_roof(a: int, b: int, n: int = 20) -> list[tuple[int, int, int, int, int]]:
    return [(i << 18, 0, 0, 0x4000, ref_cam.ROOF if a <= i < b else 0) for i in range(n)]


class _Line:
    def __init__(self, line: list[tuple[int, int, int, int, int]]) -> None:
        self.line = line


class ZoneTest(unittest.TestCase):
    def test_weight_is_full_under_the_roof_and_behind_it_and_ramps_each_side(self) -> None:
        line = line_with_roof(8, 11)
        want = [0] * 6 + [ONE // 3, 2 * ONE // 3] + [ONE] * 5 + [2 * ONE // 3, ONE // 3] + [0] * 5
        self.assertEqual([ref_cam.zone_at(line, i) for i in range(20)], want)
        half = (6 << 16) + (1 << 15)
        self.assertEqual(ref_cam.zone_weight(line, half), ONE // 3 + (2 * ONE // 3 - ONE // 3) // 2)

    def test_far_camera_under_a_roof_is_the_near_camera(self) -> None:
        t = _Line(line_with_roof(0, 20))
        self.assertEqual(ref_cam.lap_pose(t, 100, 0), ref_cam.lap_pose(t, 100, 1))

    def test_far_camera_with_no_roof_is_the_old_flyby_pose(self) -> None:
        t = _Line(line_with_roof(0, 0))
        pos, _yaw, pitch = ref_cam.lap_pose(t, 100, 0)
        self.assertEqual(pitch, ref_cam.PITCH[0])
        self.assertEqual(pos[1], ref_cam.HEIGHT[0])

    def test_shipped_tracks_carry_their_roofs_and_only_them(self) -> None:
        want = {"neon.ktrk": set(range(86, 98)), "glacier.ktrk": set(range(172, 182)), "salt.ktrk": set(), "oval.ktrk": set()}
        for name, roofs in want.items():
            t = rr.Track((ASSETS / name).read_bytes())
            self.assertEqual({i for i, s in enumerate(t.line) if s[4] & ref_cam.ROOF}, roofs, name)
            self.assertTrue(all(s[4] & ~ref_cam.ROOF & 0xFF == 0 for s in t.line), name)  # the high byte: the AI cue (R82 32X feel)

    def test_converter_writes_the_roof_flag_from_the_document(self) -> None:
        self.assertEqual(trackc.LINE_ROOF, ref_cam.ROOF)
        doc = {"vertices": [[0, 0, 0], [256, 0, 0], [0, 0, 256], [256, 0, 256], [0, 0, 512], [256, 0, 512]],
               "racing_line": [{"l": 0, "r": 1, "roof": 1}, {"l": 2, "r": 3}, {"l": 4, "r": 5}]}
        out, _ = trackc._line(doc)  # the line block alone
        flags = [struct.unpack_from("<3iHH", out, 16 * i)[4] for i in range(3)]
        self.assertEqual(flags, [1, 0, 0])


if __name__ == "__main__":
    unittest.main()
