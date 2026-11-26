"""Kestrel Racing's three tunes (tools/racer/make_tunes.py, the scores in tunes_score.py; R82 M5 step 4): the committed files
are the script's, and they keep off the cart's sound-effect channels (FM 5-6, PSG tone 3, the noise), the DAC and the LFO."""

from __future__ import annotations

import struct
import unittest
from pathlib import Path

from racer import make_tunes, tunes_score

MUSIC = Path(__file__).resolve().parents[2] / "site/music"


def commands(vgm: bytes) -> list[tuple[str, int, int]]:
    """A VGM's commands from 0x100: ('ym', port << 8 | reg, val), ('psg', byte, 0); waits skipped."""
    out: list[tuple[str, int, int]] = []
    at = 0x34 + struct.unpack_from("<I", vgm, 0x34)[0]
    while vgm[at] != 0x66:
        op = vgm[at]
        if op in (0x52, 0x53):
            out.append(("ym", (op - 0x52) << 8 | vgm[at + 1], vgm[at + 2]))
            at += 3
        elif op == 0x50:
            out.append(("psg", vgm[at + 1], 0))
            at += 2
        elif op == 0x61:
            at += 3
        else:
            raise ValueError(f"unexpected VGM command {op:#x} at {at:#x}")
    return out


class TunesTest(unittest.TestCase):
    def test_the_committed_tunes_are_what_the_script_writes(self) -> None:
        for name, tune in tunes_score.TUNES.items():
            with self.subTest(name):
                self.assertEqual((MUSIC / name).read_bytes(), make_tunes.make(tune))

    def test_no_write_reaches_fm_5_6_the_dac_or_the_lfo(self) -> None:
        for name in tunes_score.TUNES:
            with self.subTest(name):
                for _, addr, val in (c for c in commands((MUSIC / name).read_bytes()) if c[0] == "ym"):
                    port, reg = addr >> 8, addr & 0xFF
                    self.assertNotIn(reg, (0x2A, 0x2B), "the DAC is FM 6's")
                    if reg == 0x22:
                        self.assertEqual(val, 0, "the LFO stays off")
                    if reg == 0x28:
                        self.assertIn(val & 7, (0, 1, 2, 4), f"a key-on for FM {val & 7}")
                    if port == 1 and reg >= 0x30:
                        self.assertEqual(reg & 3, 0, f"port 1 reg {reg:#x} is FM 5 or 6")

    def test_psg_tone_3_and_the_noise_are_only_muted(self) -> None:
        for name in tunes_score.TUNES:
            with self.subTest(name):
                latch = 0
                for _, byte, _ in (c for c in commands((MUSIC / name).read_bytes()) if c[0] == "psg"):
                    if byte & 0x80:
                        latch = byte >> 5 & 3
                        if latch >= 2:
                            self.assertEqual(byte & 0x9F, 0x9F, f"PSG channel {latch + 1}: only the mute")
                    else:
                        self.assertLess(latch, 2, "a data byte for tone 3 / the noise")

    def test_a_bad_bar_or_chord_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            make_tunes.lead_bar("E5:4 G5:4")  # 8 sixteenths, not 16
        with self.assertRaises(KeyError):
            make_tunes.chord("Hm")
        self.assertEqual(make_tunes.chord("F#dim"), [54, 57, 60])
        self.assertEqual(make_tunes.note("Bb4"), 70)


if __name__ == "__main__":
    unittest.main()
