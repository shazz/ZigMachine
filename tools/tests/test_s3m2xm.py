"""s3m2xm: a tiny S3M built in memory, converted, and the XM read back.

The conversion is also checked end to end against libopenmpt on a real song
(docs/MUSIC.md records it); these tests pin the byte-level rules.
"""
import struct
import unittest

import s3m2xm
import s3m_effects

C4 = 0x40  # S3M note byte: octave 4, C


def s3m(cells: list, pcm: bytes = bytes([128, 160, 96]), flags: int = 1, channels: int = 3) -> bytes:
    """One sample, one pattern, `channels` tracks; `cells` are (row, track, note, inst, vol, eff, param)."""
    d = bytearray(0x60 + 1 + 2 + 2)
    d[0:4] = b"test"
    struct.pack_into("<6H", d, 0x20, 1, 1, 1, 0, 0x1320, 2)
    d[0x2C:0x30] = b"SCRM"
    d[0x30], d[0x31], d[0x32] = 64, 6, 125
    d[0x40:0x60] = bytes(range(channels)) + bytes([0xFF] * (32 - channels))
    d[0x60] = 0
    ins_at, pat_at, pcm_at = 0x70, 0xA0, 0x400
    struct.pack_into("<HH", d, 0x61, ins_at // 16, pat_at // 16)
    d = d.ljust(pcm_at + len(pcm), b"\0")
    d[ins_at] = 1
    d[ins_at + 13], d[ins_at + 14:ins_at + 16] = 0, struct.pack("<H", pcm_at // 16)
    struct.pack_into("<3I", d, ins_at + 16, len(pcm), 1, len(pcm))
    d[ins_at + 28], d[ins_at + 31] = 40, flags
    struct.pack_into("<I", d, ins_at + 32, 16726)  # an octave up: relnote +12
    d[pcm_at:pcm_at + len(pcm)] = pcm
    body = bytearray()
    for r in range(64):
        for row, t, note, inst, vol, eff, param in cells:
            if row == r:
                body += bytes([t | 32 | 64 | 128, note, inst, vol, eff, param])
        body.append(0)
    d[pat_at:pat_at + 2 + len(body)] = struct.pack("<H", len(body) + 2) + body
    return bytes(d)


def first_cells(xm: bytes, channels: int) -> list:
    """The first row's cells of the first pattern, unpacked."""
    o = 60 + struct.unpack_from("<I", xm, 60)[0] + 9
    cells = []
    for _ in range(channels):
        f, o = xm[o], o + 1
        c = []
        for bit in range(5):
            if f & (1 << bit):
                c.append(xm[o])
                o += 1
            else:
                c.append(0)
        cells.append(c)
    return cells


class S3mToXm(unittest.TestCase):
    def test_header_carries_tempo_channels_and_amiga_frequencies(self):
        xm, _ = s3m2xm.convert(s3m([]), set())
        self.assertEqual(xm[:17], b"Extended Module: ")
        song_len, _, ch, npat, ninst, flags, speed, bpm = struct.unpack_from("<8H", xm, 64)
        self.assertEqual((song_len, ch, npat, ninst, flags, speed, bpm), (1, 3, 1, 1, 0, 6, 125))

    def test_note_volume_and_cut_map_to_xm_numbering(self):
        xm, _ = s3m2xm.convert(s3m([(0, 0, C4, 1, 33, 0, 0), (0, 1, 254, 0, 64, 0, 0)]), set())
        cells = first_cells(xm, 3)
        self.assertEqual(cells[0][:3], [49, 1, 0x10 + 33])  # C-4 is XM note 49
        self.assertEqual(cells[1][0], 97)  # ^^ becomes key-off (a cut: no envelope)

    def test_dropped_tracks_are_gone_and_reported(self):
        xm, lost = s3m2xm.convert(s3m([(0, 2, C4, 1, 10, 0, 0)]), {1})
        self.assertEqual(struct.unpack_from("<H", xm, 68)[0], 2)
        self.assertEqual(first_cells(xm, 2)[1][:3], [49, 1, 0x10 + 10])
        self.assertIn("dropped tracks [1]", lost[0])

    def test_sample_is_signed_delta_coded_with_its_c2spd_as_relnote(self):
        xm, _ = s3m2xm.convert(s3m([]), set())
        smp = xm.index(b"\x03\0\0\0\x01\0\0\0\x02\0\0\0")  # length 3, loop 1..3
        vol, ft, kind, _pan, rel = struct.unpack_from("<BbBBb", xm, smp + 12)
        self.assertEqual((vol, ft, kind, rel), (40, 0, 1, 12))
        self.assertEqual(xm[-3:], bytes([0, 32, (-32 - 32) & 0xFF]))  # 0, 32, -32 as deltas

    def test_sixteen_bit_and_non_s3m_input_are_refused(self):
        with self.assertRaises(ValueError):
            s3m2xm.convert(s3m([], flags=4), set())
        with self.assertRaises(ValueError):
            s3m2xm.convert(b"\0" * 200, set())


class Effects(unittest.TestCase):
    def setUp(self):
        self.fx = s3m_effects.EffectMapper({0: 0, 2: 1})

    def test_volume_slides_normal_and_fine(self):
        self.assertEqual(self.fx.convert(0, 4, 0x30), (0xA, 0x30))
        self.assertEqual(self.fx.convert(0, 4, 0x04), (0xA, 0x04))
        self.assertEqual(self.fx.convert(0, 4, 0x3F), (0xE, 0xA3))
        self.assertEqual(self.fx.convert(0, 4, 0xF2), (0xE, 0xB2))

    def test_shared_memory_resolves_a_zero_parameter_across_letters(self):
        self.fx.convert(0, 5, 0x12)  # E12 sets the shared memory
        self.assertEqual(self.fx.convert(0, 6, 0x00), (1, 0x12))  # F00 reuses it
        self.assertEqual(self.fx.convert(1, 6, 0x00), (1, 0x00))  # another track has its own

    def test_porta_fine_extra_fine_and_jump_remap(self):
        self.assertEqual(self.fx.convert(0, 6, 0xF3), (0xE, 0x13))
        self.assertEqual(self.fx.convert(0, 5, 0xE3), (s3m_effects.XM_X, 0x23))
        self.assertEqual(self.fx.convert(0, 2, 2), (0xB, 1))  # order 2 is XM order 1 (marker gone)

    def test_unconvertible_effect_is_dropped_and_counted(self):
        self.assertEqual(self.fx.convert(0, 19, 0x81), (0, 0))  # S81: panning
        self.assertEqual(self.fx.dropped["S8"], 1)


if __name__ == "__main__":
    unittest.main()
