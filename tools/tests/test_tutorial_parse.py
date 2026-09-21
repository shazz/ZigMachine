"""docs/TUTORIAL.md structure contract — see tools/docgen/tutorial_parse.py.

Run: python3 -m unittest discover -s tools/tests -t tools
"""
from __future__ import annotations

import unittest

from docgen import ROOT
from docgen.tutorial_parse import LANGS, TutorialFormatError, parse

REAL = (ROOT / "docs" / "TUTORIAL.md").read_text()


class ParseRealFile(unittest.TestCase):
    """The happy path: the file that actually ships."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.t = parse(REAL)

    def test_thirteen_steps_and_two_framing_sections(self) -> None:
        self.assertEqual(len(self.t.steps), 13)
        plain = [s.slug for s in self.t.sections if not s.is_step]
        self.assertEqual(plain, ["before-you-start", "where-next"])

    # Steps 1-7 are the buildable core: every one ships Zig, C and Rust, and
    # apps/tutorial_steps_check.mjs fingerprints their carts (LAST_STEP = 7).
    # Step 8 is prose. Steps 9+ are reference steps with no carts behind them
    # (RUNNABLE_THROUGH in tutorial_render.py gives them no Run button), and one
    # of them is deliberately Zig-only.
    ZIG_ONLY = {11}  # 3D objects: zg.obj/wireframe/zig3d are compiled INTO the
    # cart, so there is no C or Rust equivalent to show.
    PROSE_ONLY = {8}  # "going further: opening the borders"

    def test_every_step_carries_the_languages_it_claims(self) -> None:
        for step in self.t.steps:
            got = [b.lang for b in step.langs]
            if step.number in self.PROSE_ONLY:
                self.assertEqual(got, [], f"step {step.number} is prose")
            elif step.number in self.ZIG_ONLY:
                self.assertEqual(got, ["zig"], f"step {step.number} is Zig only")
            else:
                self.assertEqual(got, list(LANGS.values()), f"step {step.number}")

    def test_checkpoint_prose_lands_after_the_language_blocks(self) -> None:
        # "**What you should see.**" must return to the shared zone, not stay
        # trapped inside the Rust block — that is what the lead-in rule is for.
        step3 = next(s for s in self.t.steps if s.number == 3)
        self.assertIn("What you should see", step3.after)
        self.assertNotIn("What you should see", step3.langs[-1].md)

    def test_no_language_block_leaks_a_heading_or_a_rule(self) -> None:
        for step in self.t.steps:
            for block in step.langs:
                self.assertNotIn("\n### ", block.md, f"step {step.number} {block.lang}")
                self.assertNotIn("\n---", block.md, f"step {step.number} {block.lang}")


class ParseEdgeCases(unittest.TestCase):
    def test_unknown_language_heading_is_an_error(self) -> None:
        bad = "# T\n\nintro\n\n## Step 1: x\n\n### Java\n\nnope\n"
        with self.assertRaises(TutorialFormatError) as cm:
            parse(bad)
        self.assertIn("### Java", str(cm.exception))

    def test_no_sections_is_an_error(self) -> None:
        with self.assertRaises(TutorialFormatError):
            parse("# Title\n\njust prose, no ## heading\n")

    def test_a_rule_inside_a_fence_does_not_end_the_block(self) -> None:
        src = ("# T\n\nintro\n\n## Step 1: x\n\n### Zig\n\n```zig\n"
               "const a = 1;\n---\n**Bold.** not a lead-in in here\n```\n\n"
               "**What you should see.** done\n")
        step = parse(src).steps[0]
        self.assertIn("---", step.langs[0].md)
        self.assertIn("Bold.", step.langs[0].md)
        self.assertIn("What you should see", step.after)

    def test_comma_form_of_the_step_heading_is_a_step(self) -> None:
        t = parse("# T\n\nintro\n\n## Step 8, going further: borders\n\nprose\n")
        self.assertEqual(t.steps[0].number, 8)
        self.assertEqual(t.steps[0].title, "going further: borders")


if __name__ == "__main__":
    unittest.main()
