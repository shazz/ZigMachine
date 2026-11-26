"""The aurora baker's final-picture deltas (tools/boot/aurora_direct.py) and the baked wordmark (aurora_word.py).

The gate runs it with test_aurora_bake: `uv run --with numpy --with pillow python -m unittest tools.tests.test_aurora_direct`.
"""
import sys
import unittest
from pathlib import Path

try:
    import numpy as np
except ImportError as e:
    raise unittest.SkipTest(f"tools/tests/test_aurora_direct.py skipped: {e} (run it through uv, see the gate line)") from e

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "boot"))
import aurora_direct as fg  # noqa: E402
import aurora_pack as pack  # noqa: E402
import aurora_word as word  # noqa: E402

H, W = 6, 8


class DirectTest(unittest.TestCase):
    def test_a_dark_film_is_refused(self):
        with self.assertRaises(pack.PackError):
            fg.lit_rows(np.zeros((2, H, W), bool))

    def test_wrapping_deltas_rebuild_every_frame_from_the_sky(self):
        rng = np.random.default_rng(1)
        sky = rng.integers(0, 65536, (H, W), dtype=np.uint16)
        frames = rng.integers(0, 65536, (4, H, W), dtype=np.uint16)
        d = fg.direct_deltas(frames, sky)
        acc = sky.copy()
        for t in range(4):
            acc = (acc + d[t]).astype(np.uint16)
            self.assertTrue(np.array_equal(acc, frames[t]))

    def test_the_final_picture_rounds_once_and_clamps(self):
        base_f = np.full((1, 1, 3), [30.4, 62.6, 0.2], np.float32)
        li = np.full((1, 1, 1, 3), [5.0, 0.0, 0.2], np.float32)
        self.assertEqual(fg.direct_frames(li, base_f)[0, 0, 0].tolist(), [31, 63, 0])


class WordTest(unittest.TestCase):
    def test_a_missing_font_is_an_error_not_a_blank_word(self):
        with self.assertRaises(word.WordError):
            word.coverage(ROOT / "no_such_font.otf", 100)

    def test_the_word_has_soft_coverage_and_stays_on_screen(self):
        font = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
        if not font.exists():
            self.skipTest("no DejaVuSans on this box")
        blob, x0, y0, w, h = word.bake(font, 120, 160, 190)
        img = np.frombuffer(blob[8:], np.uint8).reshape(h, w)
        self.assertLessEqual(y0 + h, 196)  # pushed up to stay on screen
        self.assertAlmostEqual(w, 120, delta=12)
        inked = img[img > 0]
        self.assertTrue((inked >= word.WORD_BASE).all())
        self.assertGreater(len(np.unique(inked)), 20)  # anti-aliased, not 1-bit


if __name__ == "__main__":
    unittest.main()
