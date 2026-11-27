"""Kestrel Racing (local 32X import): the code-shape file (tools/racer/vr32x_sigs.py). Synthetic shapes only."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from racer import vr32x_sigs

NAMES = ("ONE", "TWO")


class Sigs(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "signatures.json"

    def tearDown(self) -> None:
        self.dir.cleanup()

    def _write(self, data: object) -> None:
        self.path.write_text(json.dumps(data))

    def test_a_good_file_gives_its_named_shapes_and_they_compile_with_wildcards(self) -> None:
        self._write({"ONE": "a1a2 ..", "TWO": "b1", "EXTRA": "c1"})
        sigs = vr32x_sigs.load(self.path, NAMES)
        self.assertEqual(sigs, {"ONE": "a1a2 ..", "TWO": "b1"})
        self.assertTrue(vr32x_sigs.pattern(sigs["ONE"]).fullmatch(b"\xa1\xa2\x00"))
        self.assertIsNone(vr32x_sigs.pattern(sigs["ONE"]).fullmatch(b"\xa1\xa3\x00"))

    def test_a_missing_file_is_an_error_that_names_it(self) -> None:
        with self.assertRaisesRegex(vr32x_sigs.SigError, "no signatures file"):
            vr32x_sigs.load(self.path, NAMES)

    def test_a_missing_name_a_bad_shape_or_not_json_is_refused(self) -> None:
        for data in ({"ONE": "a1"}, {"ONE": "a1", "TWO": "zz"}, {"ONE": "a1", "TWO": ""}, ["a1"]):
            self._write(data)
            with self.assertRaises(vr32x_sigs.SigError, msg=str(data)):
                vr32x_sigs.load(self.path, NAMES)
        self.path.write_text("{not json")
        with self.assertRaises(vr32x_sigs.SigError):
            vr32x_sigs.load(self.path, NAMES)


if __name__ == "__main__":
    unittest.main()
