"""Kestrel Racing (local 32X import): the panorama decoders of tools/racer/vr32x_pan.py. No Sega bytes: hand-built
Kosinski and Enigma streams, hand-made tiles and nametables."""

from __future__ import annotations

import unittest

from racer import vr32x_pan
from racer.vr32x_pan import PanError


def _kos(tokens: list[tuple[str, int]]) -> bytes:
    """Assemble a Kosinski stream from ('b', bit) / ('d', byte) tokens in decode order: a descriptor is read up front and
    re-read right after its 16th bit."""
    out, desc_at, bits = bytearray(2), 0, []
    for kind, v in tokens:
        if kind == "d":
            out.append(v)
            continue
        bits.append(v)
        if len(bits) == 16:
            word = sum(b << i for i, b in enumerate(bits))
            out[desc_at : desc_at + 2] = bytes((word & 0xFF, word >> 8))
            desc_at, bits = len(out), []
            out += b"\0\0"
    word = sum(b << i for i, b in enumerate(bits))
    out[desc_at : desc_at + 2] = bytes((word & 0xFF, word >> 8))
    return bytes(out)


def _lit(*bs: int) -> list[tuple[str, int]]:
    return [t for b in bs for t in (("b", 1), ("d", b))]


def _msb(fields: list[tuple[int, int]]) -> bytes:
    bits = "".join(format(v, f"0{n}b") for v, n in fields)
    bits += "0" * (-len(bits) % 8)
    return bytes(int(bits[i : i + 8], 2) for i in range(0, len(bits), 8))


class Kosinski(unittest.TestCase):
    def test_literals_short_long_and_extended_matches_decode(self) -> None:
        toks = _lit(0x41, 0x42, 0x43)
        toks += [("b", 0), ("b", 0), ("b", 1), ("b", 0), ("d", 0xFD)]  # short: n = 2 -> 4 bytes from -3
        toks += [("b", 0), ("b", 1), ("d", 0xF9), ("d", 0xFA)]  # long: offset -7, count 2 + 2
        toks += [("b", 0), ("b", 1), ("d", 0xFF), ("d", 0xF8), ("d", 1)]  # no-op
        toks += [("b", 0), ("b", 1), ("d", 0xFE), ("d", 0xF8), ("d", 4)]  # extended: offset -2, 4 + 1
        toks += _lit(0x5A) + [("b", 0), ("b", 1), ("d", 0), ("d", 0xF0), ("d", 0)]  # end mark
        # ABC + ABCA (short) = ABCABCA; + ABCA (from -7) ; + CACAC (from -2, overlapping); + Z
        self.assertEqual(vr32x_pan.kosinski(_kos(toks), 0), b"ABCABCA" + b"ABCA" + b"CACAC" + b"Z")

    def test_a_descriptor_is_reloaded_after_its_sixteenth_bit(self) -> None:
        data = bytes(range(1, 21))
        toks = _lit(*data) + [("b", 0), ("b", 1), ("d", 0), ("d", 0xF0), ("d", 0)]
        self.assertEqual(vr32x_pan.kosinski(_kos(toks), 0), data)

    def test_a_match_before_the_start_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.kosinski(_kos([("b", 0), ("b", 0), ("b", 0), ("b", 0), ("d", 0xFF)]), 0)

    def test_a_stream_without_an_end_mark_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.kosinski(_kos(_lit(1, 2, 3)), 0)


class Enigma(unittest.TestCase):
    def test_every_packet_kind_and_the_flag_bits(self) -> None:
        head = bytes((3, 0x19)) + (0x0002).to_bytes(2, "big") + (0x0007).to_bytes(2, "big")  # 3 bits; P, CC-hi, H
        body = _msb([
            (0b00, 2), (2, 4),  # increment word x3: 2 3 4
            (0b01, 2), (1, 4),  # common x2: 7 7
            (0b100, 3), (1, 4), (1, 1), (0, 1), (0, 1), (5, 3),  # inline P|5 repeated x2
            (0b101, 3), (2, 4), (0, 1), (1, 1), (1, 1), (1, 3),  # inline CC-hi|H|1, +1 x3
            (0b110, 3), (1, 4), (0, 1), (0, 1), (0, 1), (6, 3),  # inline 6, -1 x2
            (0b00, 2), (0, 4),  # increment continues: 5
            (0b111, 3), (1, 4), (0, 1), (0, 1), (0, 1), (2, 3), (1, 1), (0, 1), (0, 1), (3, 3),
            (0b111, 3), (15, 4),
        ])
        got = vr32x_pan.enigma(head + body, 0, 0x10)
        p, ch = 0x8000, 0x4800
        want = [0x12, 0x13, 0x14, 0x17, 0x17, p + 0x15, p + 0x15, ch + 0x11, ch + 0x12, ch + 0x13, 0x16, 0x15, 0x15]
        self.assertEqual(got, want + [0x12, p + 0x13])

    def test_a_truncated_stream_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.enigma(bytes((3, 0, 0, 0, 0, 0)) + _msb([(0b00, 2), (0, 4)]), 0, 0)


class Strip(unittest.TestCase):
    TILES = bytes([0x12, 0, 0, 0] + [0] * 28) + bytes([0, 0, 0, 0x03] + [0] * 24 + [0xF0, 0, 0, 0])

    def test_cells_flips_and_palette_lines_place_pixels(self) -> None:
        names = [5, 6 | 0x0800 | 0x2000, 5 | 0x1000 | 0x4000]  # tile 5 plain; 6 h-flip line 1; 5 v-flip line 2
        px = vr32x_pan.strip(self.TILES, names, 5, 3, 1)
        self.assertEqual(px[0:2], [1, 2])  # tile 5 row 0
        self.assertEqual(px[8:16], [16 + 3] + [0] * 7)  # h-flipped tile 6 row 0: its colour 3 now at x 0
        self.assertEqual(px[7 * 24 + 8 + 7], 16 + 15)  # its row 7, colour 15 at x 0 -> x 7
        self.assertEqual(px[7 * 24 + 16 : 7 * 24 + 18], [32 + 1, 32 + 2])  # v-flipped tile 5: row 0 at y 7

    def test_a_tile_that_was_not_loaded_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.strip(self.TILES, [4], 5, 1, 1)

    def test_a_short_nametable_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.strip(self.TILES, [5], 5, 2, 1)


class Tables(unittest.TestCase):
    def test_a_dump_without_the_course_load_code_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan.panoramas(bytes(0x100000))

    def test_an_address_outside_the_cartridge_windows_is_refused(self) -> None:
        with self.assertRaises(PanError):
            vr32x_pan._rom(0xFF1000)


if __name__ == "__main__":
    unittest.main()
