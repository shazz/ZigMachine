"""Kestrel Racing M7: the Track Kit manual cannot drift. Every message the kit's code can give (kit_sites.py reads them out of
the source) has a fix in the error table (kit_errors.py, kit_errors_car.py) and every table entry is still a message the
code gives; every reason the cart names for a refused file (read from its Zig) is explained; and the manual's generated
tables (docs/ports/kestrel_racing/TRACK_KIT.md) are what tools/racer/kit_manual.py writes today."""

from __future__ import annotations

import unittest

from racer import kit_errors, kit_errors_car, kit_manual, kit_sites


class KitManualTest(unittest.TestCase):
    def test_every_message_in_the_code_has_a_fix_and_every_fix_a_message(self) -> None:
        table = kit_errors.TRACK | kit_errors_car.MORE
        found = kit_sites.sites()
        self.assertEqual(set(table), set(found))
        for module, msgs in found.items():
            with self.subTest(module):
                self.assertEqual(sorted(set(msgs) - set(table[module])), [], "messages with no fix")
                self.assertEqual(sorted(set(table[module]) - set(msgs)), [], "fixes for messages the code no longer gives")

    def test_every_reason_the_cart_gives_is_explained(self) -> None:
        self.assertEqual(set(kit_errors_car.CART), kit_sites.cart_names())

    def test_the_site_reader_finds_a_new_message(self) -> None:
        import ast

        tree = ast.parse('raise KitError(f"face {fi}: brand new")\nout.append(f"{where}: also new")')
        self.assertEqual([t for n in ast.walk(tree) for t in kit_sites._messages(n)], ["face {}: brand new", "{}: also new"])

    def test_the_manuals_generated_tables_are_current(self) -> None:
        self.assertEqual(kit_manual.render(kit_manual.MANUAL.read_text()), kit_manual.MANUAL.read_text(),
                         "python3 -I tools/racer/kit_manual.py --write")

    def test_a_manual_without_its_markers_is_refused(self) -> None:
        with self.assertRaisesRegex(SystemExit, "no <!-- gen:budget -->"):
            kit_manual.render("no markers here")


if __name__ == "__main__":
    unittest.main()
