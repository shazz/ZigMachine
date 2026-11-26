"""The boot screen's two playback streams: the aurora's change masks (tools/boot/aurora_mask.py) and the star plane baked
per 60 Hz frame (aurora_overlay.py). The cart's loops (masked.zig, overlay.zig) mirror the Python decoders here.

The gate runs it with test_aurora_bake: `uv run --with numpy --with pillow python -m unittest tools.tests.test_aurora_g`.
"""
import sys
import unittest
from pathlib import Path

try:
    import numpy as np
except ImportError as e:
    raise unittest.SkipTest(f"tools/tests/test_aurora_g.py skipped: {e} (run it through uv, see the gate line)") from e

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "boot"))
import aurora_direct as fg  # noqa: E402
import aurora_mask as mk  # noqa: E402
import aurora_overlay as ov  # noqa: E402
import aurora_pack as pack  # noqa: E402

ROWS, W = 6, 320


def film(seed=3, n=4):
    """A sky and n frames where a few hundred pixels change by small and some large (escaped) deltas."""
    rng = np.random.default_rng(seed)
    sky = rng.integers(0, 65536, (ROWS, W), dtype=np.uint16)
    frames, cur = [], sky.copy()
    for _ in range(n):
        cur = cur.copy()
        at = rng.random((ROWS, W)) < 0.15
        cur[at] = (cur[at] + rng.choice([1, 32, 2048, 65535, 2081, 7, 900] + list(range(100, 120)), at.sum())).astype(np.uint16)
        frames.append(cur)
    return sky, np.array(frames)


class MaskTest(unittest.TestCase):
    def test_every_frame_decodes_to_its_picture_escapes_included(self):
        sky, frames = film()
        d = fg.direct_deltas(frames, sky)
        table = mk.delta_table(d, d != 0)
        self.assertGreater(len(table), mk.ESC)  # some codes need the escape
        blob, offs, _ = mk.encode(d, table)
        fg.check_round_trip(blob, offs, table, sky, frames)

    def test_a_frame_that_does_not_decode_is_an_error(self):
        sky, frames = film()
        d = fg.direct_deltas(frames, sky)
        table = mk.delta_table(d, d != 0)
        blob, offs, _ = mk.encode(d, table)
        bad = bytearray(blob)
        bad[-1 - mk.PAD] ^= 0x11  # the last codes of the last frame (before its zero pad)
        with self.assertRaises(pack.PackError):
            fg.check_round_trip(bytes(bad), offs, table, sky, frames)

    def test_the_split_row_balances_the_changed_pixels(self):
        ch = np.zeros((10, W), bool)
        ch[0, :300] = True  # all the work in the first rows
        ch[1, :300] = True
        self.assertEqual(mk.split_row(ch), 1)
        ch[:] = True
        self.assertEqual(mk.split_row(ch), 5)

    def test_a_long_zero_run_is_split_at_255_and_a_short_mask_is_refused(self):
        self.assertEqual(mk.zero_runs(bytes(300)), bytes((0, 255, 0, 45)))
        plane = np.zeros((ROWS, W), np.uint16)
        with self.assertRaises(mk.MaskError):
            mk.apply(plane, bytes((0, 1, 2, 0, 0, 39)), np.array([1], np.uint16), ROWS)  # 39 bytes, a row is 40
        with self.assertRaises(mk.MaskError):
            mk.apply(plane, bytes((5, 2, 0, 0)), np.array([1], np.uint16), ROWS)  # rows 5..6 of a 6-row band

    def test_more_than_255_distinct_deltas_are_refused(self):
        d = np.arange(1, 400, dtype=np.uint16).reshape(1, -1)
        with self.assertRaises(mk.MaskError):
            mk.delta_table(d, d != 0)


def records(n_rec=6, n=3, nv=2):
    """Star records: n stars drifting right, two falcon vertices, the wire on from record 2, the name from record 4."""
    rec = np.zeros((n_rec, 3 * n + 2 * nv + 3), np.int16)
    for r in range(n_rec):
        rec[r, :n] = [10 + r, 50 + 2 * r, 300]
        rec[r, n:2 * n] = [20, 30, 199]
        rec[r, 2 * n:3 * n] = [15, 7 | 16, 3]  # the glint flag (16) is not drawn
        rec[r, 3 * n:3 * n + nv] = [100 * 16, 140 * 16]
        rec[r, 3 * n + nv:3 * n + 2 * nv] = [100 * 16, 100 * 16]
        rec[r, 3 * n + 2 * nv:] = [15 if r >= 2 else 0, 15 if r >= 4 else 0, 0]
    return rec, n, nv


class OverlayTest(unittest.TestCase):
    def test_the_lists_rebuild_every_frame_and_stars_are_single_dots(self):
        rec, n, nv = records()
        word = (200, 150, np.full((2, 3), 200, np.uint8))
        last = (len(rec) - 1) * 2
        blob, shots = ov.bake(rec, n, nv, [(0, 1)], word, last, probes=range(last + 1))
        plane, at = np.zeros(ov.W * ov.H, np.uint8), 0
        for f in range(last + 1):
            cnt = int.from_bytes(blob[at:at + 2], "little")
            rows = np.frombuffer(blob[at + 2:at + 2 + 3 * cnt], [("o", "<u2"), ("v", "u1")])
            plane[rows["o"]] = rows["v"]
            at += 2 + 3 * cnt
            self.assertTrue(np.array_equal(plane.reshape(ov.H, ov.W), shots[f]), f)
        self.assertEqual(at, len(blob))
        first = shots[0]
        self.assertEqual(int((first != 0).sum()), 3)  # three dots, no cross
        self.assertEqual(int(shots[1][20, 10]), 15)  # odd frame: halfway (+1 >> 1 = 0) toward the next record
        self.assertEqual(int((shots[4] == ov.LINE).sum()), 41)  # the wire from record 2: x 100..140
        self.assertEqual(int((shots[8] == 200).sum()), 6)  # the name from record 4

    def test_a_bad_word_file_and_an_out_of_range_scalar_are_refused(self):
        with self.assertRaises(ov.OverlayError):
            ov.parse_word(np.array([310, 0, 20, 1], "<u2").tobytes() + bytes(20))  # leaves the screen
        rec, n, nv = records()
        rec[0, -1] = -1
        with self.assertRaises(ov.OverlayError):
            ov.scalars(rec, n, nv)


if __name__ == "__main__":
    unittest.main()
