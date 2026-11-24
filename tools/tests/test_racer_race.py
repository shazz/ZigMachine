"""Kestrel Racing M3: the race fixtures the Zig port is tested against must be what the Lua reference (z8lua + freds72's
engine, local-only) writes today, and the format / grid / checkpoint plumbing must hold without it. The reference runs are
skipped without z8lua / the engine source."""

from __future__ import annotations

import struct
import unittest

from racer import gen_track, race_fixture, ref_harness, trackc


def _available() -> bool:
    try:
        ref_harness.z8lua_path()
        ref_harness.source_path()
    except ref_harness.HarnessUnavailable:
        return False
    return True


class RaceGridTest(unittest.TestCase):
    def test_the_race_grid_puts_the_player_at_the_back_and_the_ai_cars_two_a_row_ahead(self) -> None:
        g = gen_track.build_oval()["start_grid"]
        self.assertEqual([e["segment"] for e in g], [0, 1, 1, 2, 2, 3, 3, 4])
        self.assertEqual((g[0]["segment"], g[0]["yaw_q16"]), (0, 0))  # the M2 fixtures spawn slot 0: it must not move

    def test_the_track_binary_carries_the_checkpoints_in_lap_order(self) -> None:
        doc = gen_track.build_oval()
        blob = trackc.convert(doc)
        words = struct.unpack_from("<32I", blob)
        n, off = words[11], words[24]
        self.assertEqual(list(struct.unpack_from(f"<{n}I", blob, off)), doc["checkpoints"])
        self.assertEqual(doc["checkpoints"], [29, 59, 89, 119])
        self.assertEqual(len(blob), off + 4 * n)  # the last block ends the file


class FixtureFormatTest(unittest.TestCase):
    def _cars(self, n: int, scale: int) -> list[dict[str, int]]:
        return [{**dict.fromkeys(race_fixture.CAR_COLS, scale + k), "hits": 1, "sfx": 2, "nbrake": 3, "btn": 16} for k in range(n)]

    def test_a_tick_is_each_cars_columns_then_the_shared_counters(self) -> None:
        w = race_fixture.words(self._cars(2, 10))
        self.assertEqual(len(w), 2 * len(race_fixture.CAR_COLS) + 3)
        self.assertEqual(w[-3:], [1, 2, 3])
        self.assertEqual(w[0], 10)
        self.assertEqual(w[len(race_fixture.CAR_COLS)], 11)

    def test_the_crc_fixture_round_trips_and_a_truncated_one_is_refused(self) -> None:
        ticks = [self._cars(3, i * 100) for i in range(race_fixture.SPARSE_EVERY * 2)]
        for t in ticks:  # u is what finish_ticks reads: park every car past the line at tick 5
            for c in t:
                c["u"] = 0
        ticks[4][1]["u"] = (3 * 120) << 16
        blob = race_fixture.pack_crc(ticks)
        info = race_fixture.unpack_crc(blob)
        self.assertEqual((info["cars"], info["ticks"]), (3, len(ticks)))
        self.assertEqual(info["finish"], [0, 5, 0])
        with self.assertRaises(ValueError):
            race_fixture.unpack_crc(blob[:-4])


@unittest.skipUnless(_available(), "z8lua / freds72_src not on this machine")
class ReferenceTest(unittest.TestCase):
    def test_committed_fixtures_equal_a_fresh_reference_run(self) -> None:
        for name, blob in race_fixture.expected().items():
            self.assertEqual((race_fixture.ASSETS / name).read_bytes(), blob, name)

    def test_the_ram_run_fires_contacts_and_the_race_run_brakes_the_ai(self) -> None:
        ram = race_fixture.run_ticks("ram", 2, 300)
        self.assertGreaterEqual(ram[-1][0]["sfx"], 2)
        race = race_fixture.run_ticks("race", 2, 600)
        self.assertGreater(race[-1][0]["nbrake"], 0)

    def test_every_car_of_the_seven_car_race_finishes_three_laps_and_the_player_first(self) -> None:
        info = race_fixture.unpack_crc((race_fixture.ASSETS / "race_full.bin").read_bytes())
        fin = info["finish"]
        self.assertTrue(all(fin))
        self.assertEqual(min(fin), fin[0])


if __name__ == "__main__":
    unittest.main()
