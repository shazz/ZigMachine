"""The Aurora boot baker's CLI (tools/boot/aurora_bake.py main): the default bake is the boot's whole raster.

Needs numpy + pillow (the baker imports them): the gate runs it with test_aurora_bake through uv.
"""
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import numpy  # noqa: F401
except ImportError as e:  # the bake gate line installs it; discovery without it must not turn red
    raise unittest.SkipTest(f"tools/tests/test_aurora_cli.py skipped: {e} (run it through uv, see the gate line)") from e

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "boot"))
import aurora_bake as bake  # noqa: E402
import aurora_common as common  # noqa: E402


class CliTest(unittest.TestCase):
    """The CLI bakes the boot's whole raster by default; the 320x200 window never lands in the boot's assets."""

    def tearDown(self):
        common.set_screen(320, 200)

    def test_the_default_bake_is_the_whole_raster(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaises(bake.WordError):
            bake.main(["--font", str(Path(d, "none.otf"))])  # refused at the font, after the screen is chosen
        self.assertEqual((common.W, common.H), common.FULL)

    def test_the_window_needs_its_own_out_dir(self):
        with self.assertRaises(SystemExit):
            bake.main(["--window"])
        self.assertEqual((common.W, common.H), (320, 200))


if __name__ == "__main__":
    unittest.main()
