"""Kestrel Racing: the panorama writer (tools/racer/panc.py, R82 32X look). Synthetic strips only: the header the cart's
panofile.zig reads, the colours cut and ordered, the lower part stored one period wide, the crop, the refusals."""

from __future__ import annotations

import struct
import unittest
import zlib

from racer import panc

W = 256
DARK, MID, LIGHT, SEA_A, SEA_B = (10, 10, 40), (90, 90, 90), (240, 240, 240), (20, 40, 160), (30, 60, 200)
PAL = [(0, 0, 0), LIGHT, DARK, MID, SEA_A, SEA_B, (91, 90, 90)]


def _strip(rows_up: int = 6, rows_low: int = 5) -> bytes:
    """Rows of sky (1) with a dark hill (2) in a few columns, then a sea alternating 4 / 5 every 8 texels."""
    up = b"".join(bytes(2 if 40 <= x < 60 + r else 1 for x in range(W)) for r in range(rows_up))
    low = b"".join(bytes(4 + (x // 8 + r) % 2 for x in range(W)) for r in range(rows_low))
    return up + low


def _head(b: bytes) -> tuple[int, ...]:
    return struct.unpack_from("<4sIIIHHHHBBBBHH", b, 0)


class Encode(unittest.TestCase):
    def test_the_header_the_cart_reads_and_the_crc_over_the_body(self) -> None:
        b = panc.encode(W, 11, _strip(), PAL, 6, 232, u0=17, colours=8)
        magic, ver, total, crc, w, up, hz, u0, n, first, flags, zero, lw, lr = _head(b)
        self.assertEqual((magic, ver, total, w, hz, u0, first, flags, zero), (b"KPAN", 1, len(b), W, 6, 17, 232, 1, 0))
        self.assertEqual(crc, zlib.crc32(b[panc.HEADER:]))
        self.assertEqual((up, lw, lr), (6, 16, 5))  # the sea repeats every 16 texels: stored 16 wide
        self.assertEqual(len(b), panc.HEADER + 4 * n + W * up + lw * lr)

    def test_colours_dark_to_light_on_their_entries_and_clear_stays_zero(self) -> None:
        px = bytes([0, 1, 2, 3] * (W // 4))
        b = panc.encode(W, 1, px, PAL, 1, 100, colours=3)
        n = _head(b)[8]
        cols = [tuple(b[panc.HEADER + 4 * k:panc.HEADER + 4 * k + 3]) for k in range(n)]
        self.assertEqual(cols, [DARK, MID, LIGHT])
        tex = b[panc.HEADER + 4 * n:]
        self.assertEqual(tex[:4], bytes([0, 102, 100, 101]))
        self.assertEqual(_head(b)[10], 0)  # a clear texel: not OPAQUE

    def test_too_many_colours_merge_the_nearest_pair_into_the_commoner(self) -> None:
        px = bytes([3] * 200 + [6] * 50 + [1] * 6)  # MID and its near twin, and LIGHT
        remap, cols = panc.reduce(px, PAL, 2)
        self.assertEqual(cols, [MID, LIGHT])
        self.assertEqual((remap[3], remap[6], remap[1]), (1, 1, 2))

    def test_a_lower_part_that_never_repeats_is_kept_whole_or_in_the_upper_part(self) -> None:
        px = bytes((x * 7 + r) % 5 + 1 for r in range(4) for x in range(W))
        up, period = panc.split(px, W, 4, 2)
        self.assertEqual(up * W + period * (4 - up), 4 * W)

    def test_crop_keeps_the_rows_around_the_horizon(self) -> None:
        rows, px, hz = panc.crop(W, 11, _strip(), 6, 2, 3)
        self.assertEqual((rows, hz, len(px)), (5, 2, 5 * W))
        self.assertEqual(px, _strip()[4 * W:9 * W])

    def test_refusals(self) -> None:
        for kw in ({"width": 320}, {"width": 128}, {"first": 8}, {"first": 120}, {"first": 250}, {"u0": W}):
            args = {"width": W, "rows": 11, "pixels": _strip(), "palette": PAL, "horizon": 6, "first": 232, "colours": 8} | kw
            if args["width"] != W:
                args["pixels"] = bytes(args["width"] * 11)
            with self.assertRaises(panc.PanError, msg=str(kw)):
                panc.encode(**args)


if __name__ == "__main__":
    unittest.main()
