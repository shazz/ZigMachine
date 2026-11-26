"""Kestrel Racing M5 (local VR import): the colour mapping of tools/racer/vr_colours.py. No track data: synthetic colour bytes."""

from __future__ import annotations

import unittest

from racer import vr_colours as vc


class Colours(unittest.TestCase):
    def test_pico_palette_decodes_14_and_15_as_his_secret_palette_remap(self) -> None:
        self.assertEqual(vc.PICO[14], "291814")  # pal(14,128,1): dark brown
        self.assertEqual(vc.PICO[15], "125359")  # pal(15,131,1): dark teal

    def test_a_dither_pair_becomes_the_average_of_its_two_tones(self) -> None:
        a, b = vc.tone(6), vc.tone(13)
        self.assertEqual(vc.rgb_of(0xD6), tuple((x + y) // 2 for x, y in zip(a, b, strict=True)))
        self.assertEqual(vc.rgb_of(0x66), vc.tone(6))

    def test_arcade_road_panels_are_closer_than_his_palette(self) -> None:
        old = vc.TONES
        try:
            vc.TONES = "PICO"
            his = abs(vc.luma(vc.rgb_of(0x66)) - vc.luma(vc.rgb_of(0xDD)))
            vc.TONES = "ARCADE"
            ours = abs(vc.luma(vc.rgb_of(0x66)) - vc.luma(vc.rgb_of(0xDD)))
        finally:
            vc.TONES = old
        self.assertLess(ours, 30)
        self.assertLess(ours, his)

    def test_place_gives_the_first_codes_a_ramp_each_at_the_flat_level_and_lead_first(self) -> None:
        at, rgb = vc.place([0x33, 0x66, 0xDD], [0, 1, 19], lead=[0x66])
        self.assertEqual(at, {0x66: (0, vc.FLAT), 0x33: (1, vc.FLAT), 0xDD: (19, vc.FLAT)})
        self.assertEqual(rgb[19], vc.rgb_of(0xDD))

    def test_place_puts_an_overflow_code_on_the_nearest_shade_of_a_ramp(self) -> None:
        at, _ = vc.place([0x66, 0x33, 0x55], [0, 1], lead=[])
        ramp, level = at[0x55]  # dark grey: a darker step of the light grey road ramp, not the green
        self.assertEqual(ramp, 0)
        self.assertLess(level, vc.FLAT)

    def test_shader_returns_the_flat_index_and_two_lit_alternates(self) -> None:
        shade = vc.shader({0x66: (2, vc.FLAT)})
        c, alt = shade("c66", (0.0, 1.0, 0.0))
        self.assertEqual(c, 16 + 2 * 8 + vc.FLAT)
        lit, soft = alt & 255, alt >> 8
        self.assertTrue(16 + 16 <= lit <= c and 16 + 16 <= soft <= c)
        self.assertGreaterEqual(soft, lit)  # the gentle light never darkens more than the old one
        self.assertNotEqual(alt, 0)  # 0 means "no alternates" to the cart

    def test_shader_refuses_a_byte_it_has_not_placed(self) -> None:
        with self.assertRaises(KeyError):
            vc.shader({})("c66", (0.0, 1.0, 0.0))


if __name__ == "__main__":
    unittest.main()
