"""Bad Apple polygons (tools/badapple/poly*.py, cart 168): contours trace back to the exact picture, the stream
round-trips the encoder's contours (NEW / KEEP / DELTA), and malformed frames are refused."""

from __future__ import annotations

import unittest
from pathlib import Path
from unittest import mock

from badapple import poly, poly_decode, poly_trace, stream, synth

ROOT = Path(__file__).resolve().parents[2]
ZX0PACK = ROOT / "zig-out" / "bin" / "zx0pack"
STREAM = ROOT / "apps" / "zig" / "assets" / "screens" / "badapple" / "test_poly.bin"
W, H = stream.WIDTH, stream.HEIGHT


def pic(f) -> bytes:  # noqa: ANN001 (f: (x, y) -> 0/1)
    return bytes(f(x, y) for y in range(H) for x in range(W))


def square(x0: int, y0: int, s: int) -> bytes:
    return pic(lambda x, y: int(x0 <= x < x0 + s and y0 <= y < y0 + s))


class TraceTest(unittest.TestCase):
    def test_unsimplified_contours_fill_back_to_the_exact_picture(self) -> None:
        checker = pic(lambda x, y: (x // 2 + y // 2) & 1 if x < 40 and y < 40 else 0)  # saddles everywhere
        ring = pic(lambda x, y: int(400 <= (x - 160) ** 2 + (y - 100) ** 2 < 2500))  # a hole
        edge = pic(lambda x, y: int(x >= 300 or y == 0))  # touches the picture's border
        for px in (checker, ring, edge, bytes(W * H), *list(synth.frames())[::15]):
            self.assertEqual(poly.raster(poly_trace.trace(px, 1), False), px)

    def test_a_ring_is_an_outer_contour_and_a_hole(self) -> None:
        ring = pic(lambda x, y: int(400 <= (x - 160) ** 2 + (y - 100) ** 2 < 2500))
        self.assertEqual(len(poly_trace.trace(ring, 1)), 2)

    def test_simplify_turns_a_staircase_into_one_edge_and_drops_a_speck(self) -> None:
        stairs = pic(lambda x, y: int(x < y))  # a 45 degree edge: a 1 px staircase
        cs, white = poly.shapes(stairs, 0.75)
        self.assertFalse(white)
        self.assertEqual(len(cs), 1)
        self.assertLessEqual(len(cs[0]), 6)
        speck = square(50, 50, 1)
        self.assertEqual(poly.shapes(speck, 0.75)[0], [])  # 0.71 px off the diagonal: gone
        self.assertEqual(len(poly.shapes(speck, 0.5)[0]), 1)

    def test_white_background_is_chosen_from_the_border(self) -> None:
        cs, white = poly.shapes(pic(lambda x, y: int(not (100 <= x < 120 and 50 <= y < 70))), 0.75)
        self.assertTrue(white)
        self.assertEqual(cs, [[(100, 50), (120, 50), (120, 70), (100, 70)]])

    def test_a_frame_over_the_carts_pools_is_simplified_harder(self) -> None:
        ring = pic(lambda x, y: int(400 <= (x - 160) ** 2 + (y - 100) ** 2 < 2500))
        with mock.patch.object(poly, "MAX_VERTS", 40):
            cs, _ = poly.shapes(ring, 0.25)
        self.assertLessEqual(sum(map(len, cs)), 40)


class FormatTest(unittest.TestCase):
    def roundtrip(self, pictures: list[bytes]) -> list[list[poly_trace.Contour]]:
        raw = poly.BlockEncoder().block(pictures)
        prev, out = None, []
        for fb in stream.frames_of_block(raw, 0, len(pictures)):
            prev, _ = poly_decode.decode_frame(fb, prev)
            out.append(prev)
        return out

    def test_keep_delta_and_new_contours_round_trip(self) -> None:
        a, b, c = square(10, 10, 30), square(12, 9, 30), square(60, 90, 30)  # still, moved 2 px, jumped
        got = self.roundtrip([a, a, b, c])
        want = [poly.shapes(px, poly.EPS)[0] for px in (a, a, b, c)]
        self.assertEqual(got, want)
        raw = poly.BlockEncoder().block([a, a, b, c])
        ops = [fb[2] for fb in stream.frames_of_block(raw, 0, 4)]
        self.assertEqual(ops, [poly.NEW, poly.KEEP, poly.DELTA, poly.NEW])

    def test_long_steps_are_escaped(self) -> None:
        self.assertEqual(self.roundtrip([square(10, 10, 150)])[0], [[(10, 10), (160, 10), (160, 160), (10, 160)]])

    def test_malformed_frames_are_refused(self) -> None:
        prev = [[(0, 0), (5, 0), (5, 5)]]
        bad = [
            (b"", None), (b"\x02\x00", None), (b"\x00\x01\x01\x00", None),  # empty, flags, KEEP in a first frame
            (b"\x00\x01\x00\x02\x00\x00\x00\x88", None),  # 2 vertices
            (b"\x00\x01\x00\x03\x41\x01\x00\x88\x88", None),  # x 321
            (b"\x00\x01\x00\x03\x00\x00\x00\x80\x88", None),  # a zero nibble
            (b"\x00\x01\x00\x03\x00\x00\x00\x87\x88", None),  # x -1
            (b"\x00\x00\x07", None),  # a stray byte
            (b"\x00\x01\x01\x01", prev),  # KEEP past the previous frame
            (b"\x00\x01\x02\x00\x88\x88", prev),  # DELTA short of its vertices
            (b"\x00\x01\x03\x00", prev),  # op 3
        ]
        for fb, p in bad:
            with self.assertRaises(ValueError, msg=fb.hex()):
                poly_decode.decode_frame(fb, p)


class StreamTest(unittest.TestCase):
    def test_committed_synthetic_stream_is_close_to_the_film(self) -> None:
        n = 0
        for got, want in zip(poly_decode.iter_frames(STREAM.read_bytes()), synth.frames(), strict=True):
            self.assertLess(sum(a != b for a, b in zip(got, want, strict=True)), 1500, f"frame {n}")  # under 2.4 %
            n += 1
        self.assertEqual(n, synth.FRAMES)

    def test_corrupt_stream_is_refused(self) -> None:
        with self.assertRaises(stream.StreamError):
            list(poly_decode.iter_frames(b"BATL" + STREAM.read_bytes()[4:]))

    @unittest.skipUnless(ZX0PACK.is_file(), "zig build has not installed zx0pack")
    def test_synthetic_stream_is_what_the_generator_writes(self) -> None:
        data, _ = poly.encode(synth.frames(), ZX0PACK)
        self.assertEqual(data, STREAM.read_bytes())


if __name__ == "__main__":
    unittest.main()
