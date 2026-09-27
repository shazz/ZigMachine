"""The gate's harness selector must never narrow a change that can reach another screen."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import gate_scope as gs

BUILD_ZIG = """
    const cart_names = [_][]const u8{
        "demo", "demo-big_demo", "demo-union_tnt1", "demo-union_multifake",
        "demo-union_demo", "demo-dbug", "demo-tex", "demo-tex_neoshow", "demo-stream",
    };
    const other = "demo-audio";
"""
BUILD_SH = """
gate big_demo node apps/big_demo_headless.mjs
gate_timed digital_solution node apps/digital_solution_headless.mjs --break pixels
gate union_tnt1 node apps/union_tnt1_headless.mjs "$SHOTS"
gate union_multifake node apps/union_multifake_headless.mjs "$SHOTS"
gate union_demo node apps/union_demo_headless.mjs "$SHOTS"
gate dbug node apps/dbug_headless.mjs "$SHOTS"
gate tex node apps/tex_headless.mjs "$SHOTS"
gate tex_neoshow node apps/tex_neoshow_headless.mjs "$SHOTS"
"""
HARNESSES = {
    "big_demo_headless.mjs": 'import { m } from "./big_demo_machine.mjs"; load("docs/demo-big_demo.wasm")',
    "big_demo_machine.mjs": 'const f = "apps/big_fixture.json";',
    "digital_solution_headless.mjs": 'load("docs/demo-big_demo.wasm")',
    "union_tnt1_headless.mjs": 'load("docs/demo-union_tnt1.wasm"); load("docs/demo-union_multifake.wasm")',
    "union_multifake_headless.mjs": 'load("docs/demo-union_multifake.wasm")',
    "union_demo_headless.mjs": "readFile(`docs/demo-${t}.zmd`)",
    "dbug_headless.mjs": 'load("docs/demo-dbug.wasm")',
    "tex_headless.mjs": 'load("docs/demo-tex.wasm")',
    "tex_neoshow_headless.mjs": 'load("docs/demo-tex_neoshow.wasm")',
    "check_fits.mjs": "// a cross-cutting check, in no gate line",
}


def fake_repo() -> gs.Repo:
    root = Path(tempfile.mkdtemp())
    (root / "apps").mkdir()
    (root / "build.zig").write_text(BUILD_ZIG)
    (root / "build.sh").write_text(BUILD_SH)
    for name, text in HARNESSES.items():
        (root / "apps" / name).write_text(text)
    return gs.load(root)


class GateScope(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = fake_repo()

    def scope(self, *lines: str) -> list[str] | None:
        return gs.scope(self.repo, list(lines))[0]

    def test_cart_names_come_only_from_the_cart_matrix(self) -> None:
        self.assertNotIn("audio", self.repo.carts)
        self.assertIn("union_multifake", self.repo.carts)

    def test_one_scene_selects_its_harness_and_the_dynamic_hub(self) -> None:
        self.assertEqual(self.scope("M\tapps/zig/scenes/dbug.zig"), ["union_demo", "dbug"])

    def test_scene_helper_named_after_its_cart_maps_to_that_cart(self) -> None:
        self.assertEqual(self.scope("M\tapps/zig/scenes/dbug_draw.zig"), ["union_demo", "dbug"])

    def test_a_cart_run_by_another_screens_harness_pulls_that_harness_in(self) -> None:
        got = self.scope("M\tdocs/demo-union_multifake.wasm")
        self.assertEqual(got, ["union_tnt1", "union_multifake", "union_demo"])

    def test_shared_scene_dir_selects_every_cart_it_prefixes(self) -> None:
        got = self.scope("M\tapps/zig/scenes/big/digital.zig")
        self.assertEqual(got, ["big_demo", "digital_solution", "union_demo"])

    def test_registration_and_shared_files_force_the_full_gate(self) -> None:
        for path in ("apps/zig/scenes/catalog.zig", "apps/zig/scenes/menu.zig", "build.zig",
                     "build.sh", "libs/zig/zigos.zig", "rom/gem/x.zig", "machine/video.zig",
                     "docs/sealed-loader.js", "docs/index.html", "docs/channels.json",
                     "docs/demo.wasm", "docs/demo-audio.wasm", "docs/demo-c.wasm",
                     "tools/mkdisks.sh", "apps/zig/cart.zig", "apps/c/hello.c"):
            with self.subTest(path=path):
                self.assertIsNone(self.scope(f"M\t{path}"))

    def test_one_shared_file_among_screen_files_is_still_full(self) -> None:
        self.assertIsNone(self.scope("M\tapps/zig/scenes/dbug.zig", "M\tlibs/zig/zigos.zig"))

    def test_harness_helpers_select_the_harnesses_that_import_them(self) -> None:
        self.assertEqual(self.scope("M\tapps/big_demo_machine.mjs"), ["big_demo"])
        self.assertEqual(self.scope("M\tapps/big_fixture.json"), ["big_demo"])

    def test_an_apps_file_no_harness_reads_is_full(self) -> None:
        self.assertIsNone(self.scope("M\tapps/check_fits.mjs"))

    def test_prose_selects_nothing_but_is_not_full(self) -> None:
        self.assertEqual(self.scope("M\tdocs/ports/SKYSTRIKE.md", "M\tdecisions.md"), [])

    def test_a_new_tune_is_narrow_but_a_changed_one_is_full(self) -> None:
        self.assertEqual(self.scope("A\tdocs/music/new.sndh"), [])
        self.assertIsNone(self.scope("M\tdocs/music/old.sndh"))
        self.assertIsNone(self.scope("D\tdocs/music/old.sndh"))

    def test_an_empty_diff_selects_nothing(self) -> None:
        self.assertEqual(self.scope(), [])


if __name__ == "__main__":
    unittest.main()
