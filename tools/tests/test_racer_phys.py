"""Kestrel Racing M2: the physics fixtures and number pins the Zig port is tested against must be what the Lua
reference (z8lua + freds72's engine, local-only) writes today. Skipped without z8lua / the engine source."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from racer import fix_pin, gen_track, phys_fixture, ref_harness, trackc

ROOT = Path(__file__).resolve().parents[2]


def _available() -> bool:
    try:
        ref_harness.z8lua_path()
        ref_harness.source_path()
    except ref_harness.HarnessUnavailable:
        return False
    return True


class FixtureFormatTest(unittest.TestCase):
    def test_pack_then_unpack_returns_the_rows(self) -> None:
        rows = [{c: i * 7 + k - 5 for k, c in enumerate(phys_fixture.COLS)} for i in range(3)]
        self.assertEqual(phys_fixture.unpack(phys_fixture.pack(rows)), rows)

    def test_a_truncated_fixture_is_refused(self) -> None:
        blob = phys_fixture.pack([dict.fromkeys(phys_fixture.COLS, 0)])
        with self.assertRaises(ValueError):
            phys_fixture.unpack(blob[:-4])

    def test_committed_fixtures_are_well_formed_and_the_lap_is_a_whole_lap(self) -> None:
        lap = phys_fixture.unpack((phys_fixture.ASSETS / "phys_lap.bin").read_bytes())
        self.assertEqual(len(lap), 1500)
        self.assertGreater(lap[-1]["u"], 120 << 16)
        stream = (phys_fixture.ASSETS / phys_fixture.BTN_NAME).read_bytes()
        self.assertEqual(stream, bytes(r["btn"] for r in lap[89:449]))


class BorderMaskTest(unittest.TestCase):
    def test_borders_out_of_order_or_out_of_range_are_refused(self) -> None:
        for bad in ([2, 1], [0, 0], [4]):
            with self.assertRaises(trackc.ConvertError):
                trackc._border_mask({"v": [0, 1, 2, 3], "borders": bad})

    def test_the_mask_has_a_bit_per_edge(self) -> None:
        self.assertEqual(trackc._border_mask({"v": [0, 1, 2, 3], "borders": [0, 3]}), 0b1001)
        self.assertEqual(trackc._border_mask({"v": [0, 1, 2, 3]}), 0)


@unittest.skipUnless(_available(), "z8lua / freds72_src not on this machine")
class ReferenceTest(unittest.TestCase):
    def test_committed_fixtures_equal_a_fresh_reference_run(self) -> None:
        for name, blob in phys_fixture.expected().items():
            self.assertEqual((phys_fixture.ASSETS / name).read_bytes(), blob, name)

    def test_zig_number_pins_equal_the_references(self) -> None:
        text = (ROOT / "apps/zig/scenes/racer/fix_test.zig").read_text()
        pins = [int(x, 16) for x in re.findall(r"@as\(u32, (0x[0-9a-f]{8})\)", text)]
        self.assertEqual(pins, fix_pin.crcs())

    def test_the_oval_the_fixtures_ran_on_is_the_committed_one(self) -> None:
        self.assertEqual((phys_fixture.ASSETS / "oval.ktrk").read_bytes(), trackc.convert(gen_track.build_oval()))


if __name__ == "__main__":
    unittest.main()
