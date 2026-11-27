"""R82 bug pass: the car's shadow is its footprint (tools/racer/footprint.py, carc.with_footprint): non-overlapping quads
under the near model, facing up, at most 16; an open-wheel car keeps its wheels apart; the committed GT's shadow is it."""

from __future__ import annotations

import unittest
from pathlib import Path

from racer import carc, footprint, kcar_export, ktrk

ROOT = Path(__file__).resolve().parents[2]
JSON = ROOT / "tools/racer/cars/gt.kcar.json"


def box(x0: float, x1: float, z0: float, z1: float) -> list[tuple[float, float]]:
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def inside(q: list[tuple[int, int, int]], x: float, z: float) -> bool:
    """The point is inside the convex quad (x/z), edges included."""
    s = []
    for i, (ax, _, az) in enumerate(q):
        bx, _, bz = q[(i + 1) % len(q)]
        s.append((bx - ax) * (z - az) - (bz - az) * (x - ax))
    return all(v >= 0 for v in s) or all(v <= 0 for v in s)


class FootprintTest(unittest.TestCase):
    def test_an_open_wheel_car_keeps_its_wheels_apart_and_no_point_is_under_two_quads(self) -> None:
        # a body 20 wide, four wheels 10 wide beside it, front and rear
        polys = [box(-10, 10, -60, 60), box(-30, -18, -50, -30), box(18, 30, -50, -30), box(-30, -18, 30, 50), box(18, 30, 30, 50)]
        qs = footprint.quads(polys)
        self.assertLessEqual(len(qs), footprint.MAX_QUADS)
        for x in range(-34, 35, 2):
            for z in range(-64, 65, 2):
                n = sum(inside(q, x + 0.5, z + 0.5) for q in qs)  # off the integer grid: never on a shared edge
                self.assertLessEqual(n, 1, f"({x}, {z}) under {n} quads")
        self.assertTrue(any(inside(q, -24, -40) for q in qs) and any(inside(q, 24, 40) for q in qs))  # the wheels
        self.assertFalse(any(inside(q, -15, -40) for q in qs))  # the gap between a wheel and the body
        self.assertFalse(any(inside(q, 0, -63) for q in qs))  # nothing past the car

    def test_quads_lie_on_the_ground_and_face_up(self) -> None:
        for q in footprint.quads([box(-10, 10, -20, 20)]):
            self.assertTrue(all(p[1] == footprint.Y for p in q))
            n = ktrk.normal([tuple(map(float, p)) for p in q])  # type: ignore[arg-type]  # [arg-type] 3 floats
            self.assertGreater(n[1], 0.99)

    def test_adjacent_slabs_that_continue_each_other_merge(self) -> None:
        self.assertEqual(len(footprint.quads([box(-10, 10, -40, 40), box(-10, 10, -5, 5)])), 1)

    def test_too_many_pieces_fall_back_to_fewer_slabs_and_a_car_past_256_vertices_is_refused(self) -> None:
        comb = [box(x, x + 1.5, -60 + k, -50 + k) for k in range(0, 100, 7) for x in range(-40, 40, 4)]
        self.assertLessEqual(len(footprint.quads(comb)), footprint.MAX_QUADS)
        doc = kcar_export.loads(JSON.read_text())
        doc["vertices"] = doc["vertices"] + [[0, 0, i] for i in range(carc.MAX_VERTS - len(doc["vertices"]))]
        with self.assertRaises(carc.CarError):
            carc.with_footprint(doc)

    def test_the_gt_shadow_is_its_footprint_under_the_wheels(self) -> None:
        doc = carc.with_footprint(carc.scaled(kcar_export.loads(JSON.read_text()), carc.GT_SCALE))
        vs = doc["vertices"]
        shadow = [[vs[i] for i in f["v"]] for f in doc["parts"]["shadow"]]
        self.assertTrue(1 < len(shadow) <= footprint.MAX_QUADS)
        for f in doc["parts"]["wheels"]:  # every wheel face's centre (top view) is under the shadow, within 2/128 unit
            x, z = (sum(vs[i][k] for i in f["v"]) / len(f["v"]) for k in (0, 2))
            x, z = x - 2 * (x > 0) + 2 * (x < 0), z - 2 * (z > 0) + 2 * (z < 0)
            self.assertTrue(any(inside(q, x, z) for q in shadow), f"wheel face at ({x}, {z}) not under the shadow")


if __name__ == "__main__":
    unittest.main()
