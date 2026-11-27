"""Bad Apple tiles (tools/badapple/tiles.py, cart 167): the tile-dictionary format round-trips, and refuses what is
malformed; the shared block container (stream.py) refuses a broken stream."""

from __future__ import annotations

import struct
import unittest
from pathlib import Path

from badapple import stream, synth, tiles, zx0

ROOT = Path(__file__).resolve().parents[2]
ZX0PACK = ROOT / "zig-out" / "bin" / "zx0pack"
STREAM = ROOT / "apps" / "zig" / "assets" / "screens" / "badapple" / "test_tiles.bin"
N = stream.WIDTH * stream.HEIGHT


def pic(f) -> bytes:  # noqa: ANN001 (f: (x, y) -> 0/1)
    return bytes(f(x, y) for y in range(stream.HEIGHT) for x in range(stream.WIDTH))


def roundtrip(pictures: list[bytes], hold: int = 0) -> list[bytes]:
    raw = tiles.BlockEncoder(hold).block(pictures)
    dict_tiles, start = tiles.parse_dict(raw)
    screen, out = bytearray(N), []
    for i, fb in enumerate(stream.frames_of_block(raw, start, len(pictures))):
        tiles.decode_frame(fb, dict_tiles, screen, i == 0)
        out.append(bytes(screen))
    return out


class FormatTest(unittest.TestCase):
    def test_black_white_and_back_round_trip_with_an_empty_dictionary(self) -> None:
        black, white = bytes(N), b"\x01" * N
        raw = tiles.BlockEncoder().block([black, white, black])
        self.assertEqual(raw[:2], b"\x00\x00")
        self.assertEqual(roundtrip([black, white, black]), [black, white, black])

    def test_slow_morph_and_hard_cut_are_lossless(self) -> None:
        a = pic(lambda x, y: int(x < 100 + y // 4))
        b = pic(lambda x, y: int(x < 101 + y // 4))
        c = pic(lambda x, y: int((x * 7 + y * 3) % 11 < 5))  # a cut to a busy picture: many unique tiles
        self.assertEqual(roundtrip([a, b, c, a]), [a, b, c, a])

    def test_unchanged_frame_is_five_bytes(self) -> None:
        a = pic(lambda x, y: int(x < 100 + y // 4))
        raw = tiles.BlockEncoder().block([a, a])
        _, start = tiles.parse_dict(raw)
        self.assertEqual([len(f) for f in stream.frames_of_block(raw, start, 2)][1], 5)  # flag + an empty row mask

    def test_hold_leaves_a_one_pixel_change_alone(self) -> None:
        a = pic(lambda x, y: int(x < 100))
        b = bytearray(a)
        b[5 * stream.WIDTH + 200] = 1  # one stray pixel
        self.assertEqual(roundtrip([a, bytes(b)], hold=1), [a, a])
        self.assertEqual(roundtrip([a, bytes(b)], hold=0), [a, bytes(b)])

    def test_malformed_frames_are_refused(self) -> None:
        key = bytes([tiles.KEY]) + b"\x01" * tiles.SLOTS
        cases = [
            (b"", True), (bytes([2]) + key[1:], True), (key[:-1], True), (key + b"\x00", True),  # flag, short, long
            (bytes([tiles.KEY]) + b"\x02" * tiles.SLOTS, True),  # code past an empty dictionary
            (bytes([tiles.DELTA, 0, 0, 0, 0]), True),  # a block must open with a key frame
            (key, False),  # ...and only there
            (bytes([tiles.DELTA]) + struct.pack("<I", 1 << 25), False),  # row 25
            (bytes([tiles.DELTA]) + struct.pack("<I", 1) + bytes(5), False),  # an empty slot mask
        ]
        for fb, first in cases:
            with self.assertRaises(ValueError, msg=fb[:8].hex()):
                tiles.decode_frame(fb, [], bytearray(N), first)

    def test_dictionary_past_its_block_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            tiles.parse_dict(struct.pack("<H", 3) + bytes(16))


class StreamTest(unittest.TestCase):
    def test_committed_synthetic_stream_decodes_to_the_film_exactly(self) -> None:
        n = 0
        for got, want in zip(tiles.iter_frames(STREAM.read_bytes()), synth.frames(), strict=True):
            self.assertEqual(got, want, f"frame {n}")
            n += 1
        self.assertEqual(n, synth.FRAMES)

    def test_corrupt_block_and_wrong_magic_are_refused(self) -> None:
        data = bytearray(STREAM.read_bytes())
        data[16 + 10] ^= 0xFF  # block 0's ZX0! magic
        with self.assertRaises(zx0.Zx0Error):
            list(tiles.iter_frames(bytes(data)))
        with self.assertRaises(stream.StreamError):
            list(tiles.iter_frames(b"BASP" + STREAM.read_bytes()[4:]))
        with self.assertRaises(ValueError):  # a truncated file: the ZX0 reader overruns its input
            list(tiles.iter_frames(STREAM.read_bytes()[:40]))

    @unittest.skipUnless(ZX0PACK.is_file(), "zig build has not installed zx0pack")
    def test_synthetic_stream_is_what_the_generator_writes(self) -> None:
        data, _ = tiles.encode(synth.frames(), ZX0PACK)
        self.assertEqual(data, STREAM.read_bytes())

    @unittest.skipUnless(ZX0PACK.is_file(), "zig build has not installed zx0pack")
    def test_block_over_the_carts_buffers_is_refused(self) -> None:
        with self.assertRaises(stream.StreamError):
            stream.encode(tiles.MAGIC, synth.frames(), tiles.BlockEncoder().block, ZX0PACK, 1000, 1000)


if __name__ == "__main__":
    unittest.main()
