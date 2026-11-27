"""Kestrel Racing (local 32X import, R82 32X look item 3): the water's alternating tones (tools/racer/vr32x_water.py).
No track data: a synthetic 3 x 2 grid of level quads in a made-up palette."""

from __future__ import annotations

import unittest

from racer import ktrk, vr32x_water

BLUE, GRASS, WALL = 0x10, 0x11, 0x12
PAL = [(0, 0, 0)] * 256
PAL[BLUE], PAL[GRASS], PAL[WALL] = (40, 60, 200), (40, 140, 30), (30, 40, 180)


def _grid(colours: list[int], wall: bool = False) -> ktrk.Doc:
    """Quads in a row of len(colours) x 2 (a vertex every unit), level and wound up; a last face standing up if `wall`."""
    s = ktrk.SCALE
    n = len(colours)
    vs = [[x * s, 0, z * s] for z in range(3) for x in range(n + 1)]
    faces = []
    for z in range(2):
        for x, c in enumerate(colours):
            a = z * (n + 1) + x
            faces.append({"v": [a, a + n + 1, a + n + 2, a + 1], "kind": "ground", "mat": f"c{c:02x}"})
    if wall:
        vs += [[0, 0, 0], [0, s, 0], [s, s, 0], [s, 0, 0]]
        k = len(vs) - 4
        faces.append({"v": [k, k + 1, k + 2, k + 3], "kind": "prop", "mat": f"c{WALL:02x}"})
    return {"vertices": vs, "vertex_scale": s, "faces": faces, "materials": []}


class Water(unittest.TestCase):
    def test_neighbouring_water_faces_alternate_and_the_alternate_is_one_level_down(self) -> None:
        doc = _grid([BLUE, BLUE, BLUE])
        at = {BLUE: (3, 7)}
        n = vr32x_water.alternate(doc, PAL, at)
        self.assertEqual(n, 3)  # a 3 x 2 checkerboard: 3 of 6
        mats = [f["mat"] for f in doc["faces"]]
        self.assertEqual(mats, ["c10", "c110", "c10", "c110", "c10", "c110"])
        self.assertEqual(at[vr32x_water.ALT | BLUE], (3, 6))
        self.assertEqual(doc["materials"], ["c10", "c110"])

    def test_a_ramp_bottom_alternates_one_level_up(self) -> None:
        doc = _grid([BLUE, BLUE])
        at = {BLUE: (3, 0)}
        vr32x_water.alternate(doc, PAL, at)
        self.assertEqual(at[vr32x_water.ALT | BLUE], (3, 1))

    def test_land_and_standing_blue_faces_keep_their_colour(self) -> None:
        doc = _grid([GRASS, GRASS], wall=True)
        at = {GRASS: (1, 7), WALL: (2, 7)}
        self.assertEqual(vr32x_water.alternate(doc, PAL, at), 0)
        self.assertEqual({f["mat"] for f in doc["faces"]}, {"c11", "c12"})
        self.assertEqual(set(at), {GRASS, WALL})

    def test_what_counts_as_water(self) -> None:
        self.assertTrue(vr32x_water.is_water((0, 32, 189)))
        self.assertTrue(vr32x_water.is_water((41, 74, 205)))
        self.assertFalse(vr32x_water.is_water((90, 90, 110)))  # a blue-grey road
        self.assertFalse(vr32x_water.is_water((0, 0, 60)))  # too dark to read as water


if __name__ == "__main__":
    unittest.main()
