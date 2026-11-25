"""Bad Apple (tools/badapple): the span-delta format round-trips, and refuses what is malformed."""

from __future__ import annotations

import unittest
from pathlib import Path

from badapple import gen_spans, spans, synth, zx0

ROOT = Path(__file__).resolve().parents[2]
ZX0PACK = ROOT / "zig-out" / "bin" / "zx0pack"
STREAM = ROOT / "apps" / "zig" / "assets" / "screens" / "badapple" / "test_spans.bin"


def pic(f) -> bytes:
    """A 0/1 picture from f(x, y)."""
    return bytes(f(x, y) for y in range(spans.HEIGHT) for x in range(spans.WIDTH))


def roundtrip(pictures: list[bytes]) -> list[bytes]:
    rows = [spans.frame_rows(p) for p in pictures]
    raw, state, out = spans.encode_block(rows), [[] for _ in range(spans.HEIGHT)], []
    q = 0
    for _ in rows:
        n = int.from_bytes(raw[q:q + 2], "little")
        spans.decode_frame(raw[q + 2:q + 2 + n], state)
        out.append(spans.paint(state))
        q += 2 + n
    return out


class FormatTest(unittest.TestCase):
    def test_empty_black_and_white_frames(self) -> None:
        black, white = bytes(spans.WIDTH * spans.HEIGHT), b"\x01" * (spans.WIDTH * spans.HEIGHT)
        self.assertEqual(roundtrip([black, white, black]), [black, white, black])

    def test_hard_cut_and_slow_morph(self) -> None:
        a = pic(lambda x, y: int(x < 100 + y // 4))
        b = pic(lambda x, y: int(x < 101 + y // 4))  # every edge moves 1 px: pure delta rows
        c = pic(lambda x, y: int(x >= 200))  # a cut: every row changes
        self.assertEqual(roundtrip([a, b, c, a]), [a, b, c, a])

    def test_row_at_max_transitions_and_beyond(self) -> None:
        exact = pic(lambda x, y: int((x // 5) & 1) if x < 5 * spans.MAX_TRANS + 5 and y == 7 else 0)
        self.assertEqual(len(spans.frame_rows(exact)[7]), spans.MAX_TRANS)
        self.assertEqual(roundtrip([exact])[0], exact)
        over = pic(lambda x, y: x & 1 if y == 3 else 0)  # 319 changes: cut at MAX_TRANS, the rest keeps the last colour
        got = roundtrip([over])[0][3 * spans.WIDTH:4 * spans.WIDTH]
        self.assertEqual(len(spans.frame_rows(over)[3]), spans.MAX_TRANS)
        self.assertEqual(got[:spans.MAX_TRANS], over[3 * spans.WIDTH:3 * spans.WIDTH + spans.MAX_TRANS])

    def test_malformed_frames_are_refused(self) -> None:
        state: spans.Rows = [[] for _ in range(spans.HEIGHT)]
        for bad in (b"", b"\x7f", b"\x81\x88\x7f\x46", b"\xff", b"\xc1\xc0\x02\x7f\x46", b"\x7f\x7f"):
            with self.assertRaises(ValueError, msg=bad.hex()):
                spans.decode_frame(bad, state)


class StreamTest(unittest.TestCase):
    def test_committed_synthetic_stream_decodes_to_the_film(self) -> None:
        data = STREAM.read_bytes()
        n = 0
        for rows, px in zip(spans.iter_rows(data), synth.frames()):
            self.assertEqual(spans.paint(rows), spans.paint(spans.frame_rows(px)), f"frame {n}")
            n += 1
        self.assertEqual(n, synth.FRAMES)

    def test_corrupt_block_is_refused(self) -> None:
        data = bytearray(STREAM.read_bytes())
        data[16 + 10] ^= 0xFF  # block 0's ZX0! magic
        with self.assertRaises(zx0.Zx0Error):
            list(spans.iter_rows(bytes(data)))
        with self.assertRaises(ValueError):
            list(spans.iter_rows(b"NOPE" + bytes(60)))

    @unittest.skipUnless(ZX0PACK.is_file(), "zig build has not installed zx0pack")
    def test_synthetic_stream_is_what_the_generator_writes(self) -> None:
        data, _ = gen_spans.encode(synth.frames(), ZX0PACK)
        self.assertEqual(data, STREAM.read_bytes())


if __name__ == "__main__":
    unittest.main()
